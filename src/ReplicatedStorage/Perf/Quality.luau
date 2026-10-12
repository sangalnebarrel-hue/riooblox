-- One source of truth for the client's effect quality and reduced motion.
--
--   local Quality = require(ReplicatedStorage.Perf.Quality)
--   Quality.Tier()          -> "High" | "Medium" | "Low"   (the tier in use)
--   Quality.Preference()    -> "Auto" | "High" | "Medium" | "Low"
--   Quality.Reduced()       -> boolean (reduced motion)
--   Quality.Budget("Lights")            -> number for the current tier (Quality.Budgets has every key)
--   Quality.Budget("Lights", "Low")     -> number for a given tier
--   Quality.Changed:Connect(function(tier, reduced) end)
--   Quality.SetPreference("Low")        -- session choice; the settings window also saves it on the server
--
-- Where the tier comes from (the most recent explicit choice wins):
--   * Setting_Quality player attribute (the saved setting published by the server),
--   * WorldEventFX player attribute written by someone else (PAWPAD's "World Event FX" button),
--   * otherwise "Auto": UserGameSettings().SavedQualityLevel (1-3 Low, 4-6 Medium, 7-10 / Automatic
--     High), a touch device without a keyboard is capped at Medium, and an FPS watchdog steps down
--     one tier after a 10 s average below 40 FPS and steps back up after a long stable stretch.
-- Reduced motion: Roblox's accessibility setting (GuiService.ReducedMotionEnabled) OR the in-game
-- choice (Setting_ReducedMotion, or the ReducedMotion attribute written by PAWPAD).
--
-- Compatibility: about a dozen older scripts read player attributes directly. Quality keeps them
-- in step by writing WorldEventFX = tier, LowFX = (tier == "Low") and ReducedMotion = Reduced()
-- (only when a value changes). Every script requiring this module shares one state; the first
-- call starts it (StarterPlayerScripts.PerfQuality starts it at join).
--
-- tests/perf.luau covers the pure helpers (AutoTier, Resolve, NormalizePreference, Watchdog) and
-- the attribute sync in Lune.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(script.Parent.Signal)
local Scheduler = require(script.Parent.Scheduler)

local Quality = {}

Quality.Tiers = { "High", "Medium", "Low" }
local TIER_INDEX = { High = 1, Medium = 2, Low = 3 }

-- WorldEventConfig.FX holds the world-event particle budgets; the same numbers are the
-- district-wide particle budget of docs/OVERHAUL_PLAN.md §4.
local function eventFx(): any
	local folder = ReplicatedStorage:FindFirstChild("WorldEvents")
	local module = folder and folder:FindFirstChild("WorldEventConfig")
	if module and module:IsA("ModuleScript") then
		local ok, config = pcall(require, module)
		if ok and type(config) == "table" and type(config.FX) == "table" then
			return config.FX
		end
	end
	return {
		High = { Particles = 64, Debris = 52, Dogs = 14 },
		Medium = { Particles = 28, Debris = 24, Dogs = 8 },
		Low = { Particles = 4, Debris = 8, Dogs = 3 },
	}
end
local FX = eventFx()

local function row(high: number, medium: number, low: number): { [string]: number }
	return { High = high, Medium = medium, Low = low }
end
local function fxRow(key: string): { [string]: number }
	return row(FX.High[key], FX.Medium[key], FX.Low[key])
end

-- Budgets per tier (docs/OVERHAUL_PLAN.md §4). Counts are "at most, at the same time" unless noted.
Quality.Budgets = {
	Lights = row(24, 16, 8), -- visible light sources in the district (WorldDetailQuality + features)
	LightRadius = row(160, 120, 85), -- studs: lights farther than this stay off
	Particles = fxRow("Particles"), -- particles per second, the whole district
	EmitterRate = row(8, 5, 2), -- particles per second of one ambient emitter
	EmitterRadius = row(210, 150, 90), -- studs: ambient emitters farther than this stay off
	Burst = row(300, 150, 45), -- particles in one 4 s "wow" burst (F12, F7)
	BurstScale = row(1, 0.5, 0.15),
	Debris = fxRow("Debris"), -- world-event debris pieces
	Dogs = fxRow("Dogs"), -- world-event extra dogs
	Highlights = row(8, 4, 2), -- Highlight instances, every system together
	Viewports = row(12, 8, 4), -- visible ViewportFrames
	Arrows = row(32, 20, 12), -- path arrows (F1)
	Titles = row(12, 8, 8), -- title boards over characters (F10)
	DecorParts = row(300, 300, 300), -- parts per plot: decor (F8)
	ShowcaseParts = row(150, 150, 150), -- parts per plot: showcase (F3)
	MineParts = row(400, 400, 400), -- parts per plot: the visible mine level (F5)
	LabParts = row(600, 600, 600), -- the mutation machine (F12)
	LabLights = row(6, 6, 6),
	LabEmitters = row(4, 4, 4),
	LodNear = row(160, 120, 85), -- studs: full detail inside (Perf.Lod default)
	LodFar = row(320, 240, 160), -- studs: hidden / impostor beyond (Perf.Lod default)
	FeatureMs = row(0.3, 0.3, 0.2), -- steady Lua time of one feature per frame
}

------------------------------------------------------------------------------------------------
-- Pure helpers
------------------------------------------------------------------------------------------------

-- "auto" / "LOW" / nil / junk -> "Auto" | "High" | "Medium" | "Low".
function Quality.NormalizePreference(value: any): string
	if type(value) == "string" then
		local lower = string.lower(value)
		if lower == "high" then
			return "High"
		elseif lower == "medium" then
			return "Medium"
		elseif lower == "low" then
			return "Low"
		end
	end
	return "Auto"
end

-- The tier "Auto" starts from: the Roblox graphics level (0 = Automatic) and the device.
function Quality.AutoTier(savedLevel: number?, touchOnly: boolean?): string
	local level = tonumber(savedLevel) or 0
	local tier = "High"
	if level > 0 and level <= 3 then
		tier = "Low"
	elseif level > 0 and level <= 6 then
		tier = "Medium"
	end
	if touchOnly and tier == "High" then
		tier = "Medium"
	end
	return tier
end

-- The tier in use: an explicit preference as is; "Auto" = the auto tier stepped down by the watchdog.
function Quality.Resolve(preference: string?, autoTier: string?, steps: number?): string
	local pref = Quality.NormalizePreference(preference)
	if pref ~= "Auto" then
		return pref
	end
	local index = (TIER_INDEX[autoTier or "High"] or 1) + math.max(0, math.floor(steps or 0))
	return Quality.Tiers[math.min(3, index)]
end

function Quality.TouchOnly(touchEnabled: boolean?, keyboardEnabled: boolean?): boolean
	return touchEnabled == true and keyboardEnabled ~= true
end

function Quality.StepDown(tier: string): string
	return Quality.Tiers[math.min(3, (TIER_INDEX[tier] or 1) + 1)]
end

-- FPS watchdog: feed it samples (frames, seconds), it answers -1 (step down), +1 (step up) or 0.
--   * Warmup: the first 15 s after start are ignored (loading).
--   * Down: a 10 s block averaging below 40 FPS steps down one tier (at most MaxSteps).
--   * Up: RecoverAfter seconds of blocks at 55+ FPS step back up one tier. A step down within
--     60 s of a step up doubles RecoverAfter (60 s -> 120 -> ... -> 600) so it never flaps.
local Watchdog = {}
Watchdog.__index = Watchdog
Quality.Watchdog = Watchdog

function Watchdog.new(options: any?): any
	local o = options or {}
	return setmetatable({
		Threshold = o.Threshold or 40,
		Window = o.Window or 10,
		RecoverFps = o.RecoverFps or 55,
		RecoverAfter = o.RecoverAfter or 60,
		RecoverMax = o.RecoverMax or 600,
		Warmup = o.Warmup or 15,
		MaxSteps = o.MaxSteps or 2,
		Steps = 0,
		Elapsed = 0,
		BlockFrames = 0,
		BlockTime = 0,
		Good = 0,
		LastUp = nil,
	}, Watchdog)
end

function Watchdog.Reset(self: any)
	self.Steps = 0
	self.BlockFrames, self.BlockTime, self.Good = 0, 0, 0
	self.LastUp = nil
end

-- Drops the partial block (window unfocused, a teleport, a loading screen).
function Watchdog.Pause(self: any)
	self.BlockFrames, self.BlockTime = 0, 0
end

function Watchdog.Sample(self: any, frames: number, seconds: number): number
	if seconds <= 0 then
		return 0
	end
	self.Elapsed += seconds
	if self.Elapsed <= self.Warmup then
		return 0
	end
	self.BlockFrames += frames
	self.BlockTime += seconds
	if self.BlockTime < self.Window then
		return 0
	end
	local fps = self.BlockFrames / self.BlockTime
	local blockTime = self.BlockTime
	self.BlockFrames, self.BlockTime = 0, 0
	if fps < self.Threshold then
		self.Good = 0
		if self.Steps >= self.MaxSteps then
			return 0
		end
		if self.LastUp and self.Elapsed - self.LastUp <= 60 then
			self.RecoverAfter = math.min(self.RecoverMax, self.RecoverAfter * 2)
		end
		self.Steps += 1
		return -1
	end
	if fps >= self.RecoverFps and self.Steps > 0 then
		self.Good += blockTime
		if self.Good >= self.RecoverAfter then
			self.Good = 0
			self.Steps -= 1
			self.LastUp = self.Elapsed
			return 1
		end
	else
		self.Good = 0
	end
	return 0
end

------------------------------------------------------------------------------------------------
-- Runtime (client)
------------------------------------------------------------------------------------------------

Quality.Changed = Signal.new()

local state = {
	Started = false,
	Preference = "Auto",
	ReducedChoice = nil :: boolean?, -- the in-game choice; nil = none made
	SystemReduced = false,
	SavedLevel = 0,
	TouchOnly = false,
	Tier = "High",
	Reduced = false,
	Watchdog = Watchdog.new(),
	Written = {} :: { [string]: any }, -- attribute values this module wrote last
	Fps = 0,
}

local function player(): Player?
	return Players.LocalPlayer
end

local function readSavedLevel(): number
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return ok and tonumber(level) or 0
end

local function readSystemReduced(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local function write(name: string, value: any)
	local p = player()
	if not p then
		return
	end
	state.Written[name] = value
	if p:GetAttribute(name) ~= value then
		p:SetAttribute(name, value)
	end
end

local function recompute()
	local autoTier = Quality.AutoTier(state.SavedLevel, state.TouchOnly)
	local tier = Quality.Resolve(state.Preference, autoTier, state.Watchdog.Steps)
	local reduced = state.SystemReduced or state.ReducedChoice == true
	local changed = tier ~= state.Tier or reduced ~= state.Reduced
	state.Tier, state.Reduced = tier, reduced
	write("WorldEventFX", tier)
	write("LowFX", tier == "Low")
	write("ReducedMotion", reduced)
	if changed then
		Quality.Changed:Fire(tier, reduced)
	end
end

-- true when the attribute's current value is not an echo of this module's own write.
local function external(p: Player, name: string): (boolean, any)
	local value = p:GetAttribute(name)
	return value ~= state.Written[name], value
end

local watchJob: any = nil
local lastFrames, lastTime = 0, 0
local function updateWatchdog()
	local wanted = state.Preference == "Auto"
	if wanted and not watchJob then
		lastFrames, lastTime = Scheduler.FrameCounter()
		watchJob = Scheduler.Every(1, "Perf.Quality", function()
			local frames, time = Scheduler.FrameCounter()
			local df, dtime = frames - lastFrames, time - lastTime
			lastFrames, lastTime = frames, time
			if dtime > 0 then
				state.Fps = df / dtime
			end
			local step = state.Watchdog:Sample(df, dtime)
			if step ~= 0 then
				recompute()
			end
			return false
		end)
	elseif not wanted and watchJob then
		watchJob:Stop()
		watchJob = nil
	end
end

local function setPreference(value: any)
	local pref = Quality.NormalizePreference(value)
	if pref ~= state.Preference then
		state.Preference = pref
		state.Watchdog:Reset()
		updateWatchdog()
	end
	recompute()
end

function Quality.Start()
	if state.Started then
		return
	end
	state.Started = true
	state.SavedLevel = readSavedLevel()
	state.TouchOnly = Quality.TouchOnly(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	state.SystemReduced = readSystemReduced()
	local p = player()
	if p and RunService:IsClient() then
		local saved = p:GetAttribute("Setting_Quality")
		local legacy = p:GetAttribute("WorldEventFX")
		state.Preference = Quality.NormalizePreference(saved ~= nil and saved or legacy)
		local savedReduced = p:GetAttribute("Setting_ReducedMotion")
		local legacyReduced = p:GetAttribute("ReducedMotion")
		if type(savedReduced) == "boolean" then
			state.ReducedChoice = savedReduced
		elseif type(legacyReduced) == "boolean" then
			state.ReducedChoice = legacyReduced
		end
		p:GetAttributeChangedSignal("Setting_Quality"):Connect(function()
			setPreference(p:GetAttribute("Setting_Quality"))
		end)
		p:GetAttributeChangedSignal("WorldEventFX"):Connect(function()
			local isExternal, value = external(p, "WorldEventFX")
			if isExternal then
				setPreference(value)
			end
		end)
		p:GetAttributeChangedSignal("Setting_ReducedMotion"):Connect(function()
			local value = p:GetAttribute("Setting_ReducedMotion")
			state.ReducedChoice = if type(value) == "boolean" then value else nil
			recompute()
		end)
		p:GetAttributeChangedSignal("ReducedMotion"):Connect(function()
			local isExternal, value = external(p, "ReducedMotion")
			if isExternal then
				state.ReducedChoice = value == true
				recompute()
			end
		end)
		pcall(function()
			GuiService:GetPropertyChangedSignal("ReducedMotionEnabled" :: any):Connect(function()
				state.SystemReduced = readSystemReduced()
				recompute()
			end)
		end)
		pcall(function()
			local settings: any = UserSettings():GetService("UserGameSettings")
			settings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
				state.SavedLevel = readSavedLevel()
				recompute()
			end)
		end)
		UserInputService.WindowFocusReleased:Connect(function()
			state.Watchdog:Pause()
		end)
		UserInputService.WindowFocused:Connect(function()
			state.Watchdog:Pause()
			lastFrames, lastTime = Scheduler.FrameCounter()
		end)
		updateWatchdog()
	end
	recompute()
end

function Quality.Tier(): string
	Quality.Start()
	return state.Tier
end

function Quality.Preference(): string
	Quality.Start()
	return state.Preference
end

function Quality.Reduced(): boolean
	Quality.Start()
	return state.Reduced
end

function Quality.IsLow(): boolean
	return Quality.Tier() == "Low"
end

-- Session preference ("Auto" | "High" | "Medium" | "Low"). The settings window saves it on the
-- server as well (SettingsSave), which comes back as Setting_Quality.
function Quality.SetPreference(value: string)
	Quality.Start()
	setPreference(value)
end

local warnedKeys: { [string]: boolean } = {}
function Quality.Budget(key: string, tier: string?): number?
	local budget = Quality.Budgets[key]
	if not budget then
		if not warnedKeys[key] then
			warnedKeys[key] = true
			warn("Perf.Quality: unknown budget " .. tostring(key))
		end
		return nil
	end
	return budget[tier or Quality.Tier()] or budget.High
end

-- Debug view of the inputs and the result.
function Quality.State(): any
	Quality.Start()
	return {
		Preference = state.Preference,
		Tier = state.Tier,
		AutoTier = Quality.AutoTier(state.SavedLevel, state.TouchOnly),
		Steps = state.Watchdog.Steps,
		Reduced = state.Reduced,
		SystemReduced = state.SystemReduced,
		ReducedChoice = state.ReducedChoice,
		SavedLevel = state.SavedLevel,
		TouchOnly = state.TouchOnly,
		Fps = state.Fps,
	}
end

return Quality
