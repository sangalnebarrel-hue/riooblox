-- Shared helpers of the Halloween event (ReplicatedStorage.Halloween.Shared). Pure and safe on server and client.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local root = script.Parent
local Config = require(root:WaitForChild("Config"))
local Layout = require(root:WaitForChild("Layout"))

local S = {}
S.Config = Config
S.Layout = Layout
S.IsServer = RunService:IsServer()
S.IsStudio = RunService:IsStudio()

local function stateFolder()
	return root:FindFirstChild("State")
end

-- Event switch: the config flag, confirmed by the server (State.Enabled is written once at server start).
function S.Enabled(): boolean
	if not Config.HalloweenEventEnabled then
		return false
	end
	local st = stateFolder()
	local v = st and st:GetAttribute("Enabled")
	if v == nil then
		return true
	end
	return v == true
end

-- Chapter switches: the master switch, the config flag and the server's replicated State attribute of the same name
-- (written at boot by HalloweenServer; nil = trust the config).
local function flag(name: string): boolean
	if not S.Enabled() or Config[name] ~= true then
		return false
	end
	local st = stateFolder()
	local v = st and st:GetAttribute(name)
	return v == nil or v == true
end
function S.Chapter1Enabled(): boolean
	return flag("HalloweenChapter1Enabled")
end
function S.Chapter2Enabled(): boolean
	return flag("HalloweenChapter2Enabled")
end
function S.CalendarEnabled(): boolean
	-- the calendar dresses the main map even without the event chapters, but never when the master switch is off
	return flag("HalloweenCalendarEnabled")
end
function S.BossFinaleEnabled(): boolean
	return flag("HalloweenBossFinaleEnabled")
end

function S.FastTimers(): boolean
	return S.IsStudio and Config.Studio and Config.Studio.FastTimers == true and game.GameId == 0
end

---------------------------------------------------------------------------------------------------------------------
-- Language
---------------------------------------------------------------------------------------------------------------------
local cachedLang, langAt = nil, -1
function S.IsRussian(): boolean
	if S.IsServer then
		return false
	end
	local now = os.clock()
	if cachedLang ~= nil and now - langAt < 5 then
		return cachedLang
	end
	langAt = now
	local ok, ru = pcall(function()
		local player = Players.LocalPlayer
		local forced = player and player:GetAttribute("DOGROTS_Language")
		if type(forced) == "string" then
			return string.sub(string.lower(forced), 1, 2) == "ru"
		end
		local id = string.lower(player and player.LocaleId or "")
		if string.sub(id, 1, 2) == "ru" then
			return true
		end
		local loc = game:GetService("LocalizationService")
		return string.sub(string.lower(loc.RobloxLocaleId or ""), 1, 2) == "ru"
	end)
	cachedLang = ok and ru == true
	return cachedLang
end

function S.L(en: string, ru: string?): string
	if ru and S.IsRussian() then
		return ru
	end
	return en
end

-- Russian of an English event string through ReplicatedStorage.Localization.Halloween (Exact / UI / Patterns), else `en`
local locModule: any = nil
function S.T(en: string): string
	if type(en) ~= "string" or not S.IsRussian() then
		return en
	end
	if locModule == nil then
		local ok, m = pcall(function()
			local folder = RS:FindFirstChild("Localization")
			local inst = folder and folder:FindFirstChild("Halloween")
			return inst and require(inst)
		end)
		locModule = ok and type(m) == "table" and m or false
	end
	local out = locModule and locModule.Translate and locModule.Translate(en, "ru")
	return out or en
end

---------------------------------------------------------------------------------------------------------------------
-- Colours / formatting
---------------------------------------------------------------------------------------------------------------------
function S.Color(v: any): Color3
	if typeof(v) == "Color3" then
		return v
	end
	if type(v) == "string" then
		v = Config.Palette[v] or { 255, 255, 255 }
	end
	if type(v) == "table" then
		return Color3.fromRGB(v[1] or 255, v[2] or 255, v[3] or 255)
	end
	return Color3.new(1, 1, 1)
end

S.RarityNames = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
S.RarityColors = {
	Common = Color3.fromRGB(170, 190, 205), Rare = Color3.fromRGB(38, 164, 243), Epic = Color3.fromRGB(161, 103, 242),
	Legendary = Color3.fromRGB(249, 180, 35), Mythic = Color3.fromRGB(247, 73, 112), Secret = Color3.fromRGB(230, 115, 245),
}
function S.Rarity(rank: any): (string, Color3)
	local name = type(rank) == "number" and S.RarityNames[math.clamp(math.floor(rank), 1, 6)] or tostring(rank or "Common")
	return name, S.RarityColors[name] or S.RarityColors.Common
end

function S.Format(n: number): string
	n = math.floor(tonumber(n) or 0)
	local a = math.abs(n)
	if a >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif a >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif a >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

function S.Clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds or 0))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

---------------------------------------------------------------------------------------------------------------------
-- Time
---------------------------------------------------------------------------------------------------------------------
function S.Now(): number
	return workspace:GetServerTimeNow()
end

function S.Day(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

function S.SecondsToNextDay(now: number?): number
	now = now or os.time()
	return 86400 - now % 86400
end

-- Blood Moon schedule: phase-locked inside the NORMAL gap of the world-event cycle (never overlaps a world event).
-- Deterministic: the same on every server and client. now = os.time() on the server, Shared.Now() on clients.
local scheduleCache = nil
local function schedule()
	if scheduleCache then
		return scheduleCache
	end
	local ok, res = pcall(function()
		local we = RS:WaitForChild("WorldEvents", 10)
		return { Config = require(we.WorldEventConfig), Schedule = require(we.WorldEventSchedule) }
	end)
	scheduleCache = ok and res or { Config = { Epoch = 1704067200 }, Schedule = { Period = function() return 915 end } }
	local bm, gap = Config.BloodMoon, scheduleCache.Config.NormalInterval
	if S.IsServer and type(gap) == "number" and (tonumber(bm.Period) or 0) <= 0 and bm.Offset + bm.Warning + bm.Active + bm.Fade > gap then
		warn("Halloween Config.BloodMoon: Offset+Warning+Active+Fade is longer than the world-event NORMAL gap (" .. gap .. " s)")
	end
	return scheduleCache
end

-- Config.BloodMoon.Period > 0 replaces the world-event period (own clock from the same epoch; may overlap world events)
function S.BloodMoonAt(now: number)
	local bm = Config.BloodMoon
	local period, epoch, offset
	if S.FastTimers() then
		period, epoch, offset = bm.StudioPeriod, 0, bm.StudioOffset
	else
		local sc = schedule()
		local own = tonumber(bm.Period) or 0
		period = own > 0 and own or sc.Schedule.Period()
		epoch = sc.Config.Epoch
		offset = bm.Offset
	end
	local index = math.floor((now - epoch) / period)
	local start = epoch + index * period
	local w = start + offset
	local a = w + bm.Warning
	local e = a + bm.Active
	local f = e + bm.Fade
	local state
	if now < w or now >= f then
		state = "NORMAL"
	elseif now < a then
		state = "WARNING"
	elseif now < e then
		state = "ACTIVE"
	else
		state = "ENDING"
	end
	if state == "NORMAL" and now >= f then -- this cycle's moon is over: describe the next one
		index += 1
		w += period
		a, e, f = w + bm.Warning, w + bm.Warning + bm.Active, w + bm.Warning + bm.Active + bm.Fade
	end
	local endTs = state == "WARNING" and a or state == "ACTIVE" and e or state == "ENDING" and f or w
	return {
		State = state, Cycle = index, Generation = tostring(index) .. ":BLOOD_MOON", Period = period,
		WarningTimestamp = w, StartTimestamp = a, ActiveEndTimestamp = e, FadeEndTimestamp = f, EndTimestamp = endTs,
	}
end

-- The live Blood Moon state: the server's attributes (State.BloodMoon, authoritative, includes Studio-forced moons)
-- or, before they replicate, the deterministic schedule.
function S.BloodMoonState(now: number?): { [string]: any }
	local st = stateFolder()
	local f = st and st:FindFirstChild("BloodMoon")
	if f and type(f:GetAttribute("State")) == "string" then
		return {
			State = f:GetAttribute("State"), Cycle = f:GetAttribute("Cycle") or 0,
			WarningTimestamp = f:GetAttribute("WarningTimestamp") or 0, StartTimestamp = f:GetAttribute("StartTimestamp") or 0,
			ActiveEndTimestamp = f:GetAttribute("ActiveEndTimestamp") or 0, FadeEndTimestamp = f:GetAttribute("FadeEndTimestamp") or 0,
			EndTimestamp = f:GetAttribute("EndTimestamp") or 0,
		}
	end
	return S.BloodMoonAt(now or S.Now())
end

-- 0..1 visual strength of the Blood Moon at time `now` (smooth): warning tints, active full, ending fades.
function S.BloodMoonAlpha(now: number, state: { [string]: any }?): number
	local s = state or S.BloodMoonState(now)
	local function smooth(t)
		t = math.clamp(t, 0, 1)
		return t * t * (3 - 2 * t)
	end
	if s.State == "WARNING" then
		return .25 * smooth((now - s.WarningTimestamp) / Config.BloodMoon.Warning)
	elseif s.State == "ACTIVE" then
		return math.max(.25, smooth((now - s.StartTimestamp) / 6))
	elseif s.State == "ENDING" then
		local fade = math.max(1, (s.FadeEndTimestamp or 0) - s.ActiveEndTimestamp)
		return 1 - smooth((now - s.ActiveEndTimestamp) / fade)
	end
	return 0
end

---------------------------------------------------------------------------------------------------------------------
-- Zone
---------------------------------------------------------------------------------------------------------------------
function S.InZone(pos: Vector3, margin: number?): boolean
	return Layout.InZone(pos, margin)
end

function S.ZoneWeight(pos: Vector3, feather: number?): number
	return Layout.Weight(pos, feather)
end

---------------------------------------------------------------------------------------------------------------------
-- Client quality (the game's own convention: WorldEventFX attribute, LowFX, ReducedMotion, touch default)
---------------------------------------------------------------------------------------------------------------------
function S.Quality(): string
	if S.IsServer then
		return "High"
	end
	local player = Players.LocalPlayer
	local fx = player and player:GetAttribute("WorldEventFX")
	if player and (player:GetAttribute("LowFX") == true or fx == "Low") then
		return "Low"
	end
	if fx == "Medium" then
		return "Medium"
	end
	if fx == nil then
		local ok, touch = pcall(function()
			local UIS = game:GetService("UserInputService")
			return UIS.TouchEnabled and not UIS.KeyboardEnabled
		end)
		if ok and touch then
			return "Medium"
		end
		local ok2, level = pcall(function()
			return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
		end)
		if ok2 and type(level) == "number" and level > 0 and level <= 3 then
			return "Low"
		end
	end
	return "High"
end

function S.Low(): boolean
	return S.Quality() == "Low"
end

function S.ReducedMotion(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("ReducedMotion") == true
end

-- Chapter II quality keys (UnderMotes, Telegraph, FinaleFX, CalendarFX, CoffinFX, GhostLights) live in
-- Chapter2Config.Quality; Config.Quality keys win when both define one
local c2Quality: any = nil
function S.Budget(key: string): number
	local tier = S.Quality()
	local q = Config.Quality[tier] or Config.Quality.High
	local v = q[key]
	if v ~= nil then
		return v
	end
	if c2Quality == nil then
		local mod = root:FindFirstChild("Chapter2Config")
		local ok, cfg = false, nil
		if mod then
			ok, cfg = pcall(require, mod)
		end
		c2Quality = ok and type(cfg) == "table" and type(cfg.Quality) == "table" and cfg.Quality or false
	end
	local q2 = c2Quality and (c2Quality[tier] or c2Quality.High)
	return q2 and q2[key] or 0
end

---------------------------------------------------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------------------------------------------------
function S.IsEventDog(id: any): boolean
	return type(id) == "string" and Config.Dogs.Defs[id] ~= nil
end

function S.EventDog(id: string)
	return Config.Dogs.Defs[id]
end

function S.MutationDef(name: any)
	if type(name) ~= "string" then
		return nil
	end
	return Config.Mutations.Defs[string.upper(name)]
end

function S.IsEventMutation(name: any): boolean
	return S.MutationDef(name) ~= nil
end

-- rows = {{Weight=n,...}}; rand = function() -> [0,1)
function S.Weighted(rows: { any }, rand: (() -> number)?): any
	local total = 0
	for _, r in ipairs(rows) do
		total += math.max(0, r.Weight or 0)
	end
	if total <= 0 then
		return rows[1]
	end
	local x = (rand and rand() or math.random()) * total
	for _, r in ipairs(rows) do
		x -= math.max(0, r.Weight or 0)
		if x <= 0 then
			return r
		end
	end
	return rows[#rows]
end

-- candy multiplier from the curse level (Config.Curse.CandyMultiplier, piecewise linear)
function S.CurseMultiplier(curse: number): number
	local rows = Config.Curse.CandyMultiplier
	curse = math.clamp(curse or 0, 0, 100)
	for i = 2, #rows do
		local a, b = rows[i - 1], rows[i]
		if curse <= b.At then
			local t = (b.At - a.At) > 0 and (curse - a.At) / (b.At - a.At) or 1
			return a.Mult + (b.Mult - a.Mult) * math.clamp(t, 0, 1)
		end
	end
	return rows[#rows].Mult
end

function S.CauldronLevel(level: number)
	local rows = Config.Cauldron.Levels
	return rows[math.clamp(math.floor(level or 1), 1, #rows)]
end

-- [WP-E] late-starter catch-up: pass the brew's StartedAt for its real length (Chapter1Rules.BrewSeconds: ready at
-- min(StartedAt + 7 days, Config.Rebalance.BrewDeadline); started after the deadline: 1 day); no StartedAt = the full
-- brew. Studio fast timers unchanged.
function S.BrewSeconds(startedAt: number?): number
	if S.FastTimers() then
		return Config.Cauldron.StudioBrewSeconds
	end
	local ok, secs = pcall(function()
		local rules = root:FindFirstChild("Chapter1Rules")
		return rules and require(rules :: any).BrewSeconds(startedAt, Config)
	end)
	return ok and type(secs) == "number" and secs or Config.Cauldron.BrewSeconds
end

function S.Remotes()
	return root:WaitForChild("Remotes")
end

function S.State()
	return root:WaitForChild("State")
end

return S
