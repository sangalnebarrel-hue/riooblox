-- HALLOWEEN CALENDAR service (ServerScriptService.Halloween.Calendar) — the HalloweenCalendarService of
-- docs/halloween2/DESIGN.md §13. The main map rots a little more every UTC midnight from D-7 (October 24) to October 31.
-- * The stage decorations are prebuilt offline (tools/edits/41_calendar.luau) into ServerStorage.HalloweenCalendar
--   .Stage01..Stage08 (Folders, attribute CalendarStage = n). This service moves every folder with stage <= today into
--   Workspace.DOGROTS_District.41_HalloweenCalendar and every later one back into storage — a reparent, never a clone, and
--   only when a folder is on the wrong side — so a date that moves backwards (Studio force, clock fix) also works.
-- * The date is UTC os.time() through CalendarRules (pure); it is checked every HalloweenCalendarConfig.CheckEvery seconds
--   and exactly at the next stage boundary. Studio only: HalloweenCalendarConfig.Studio.ForceStage, Calendar.Force(n)
--   (used by the C2Debug "Calendar n" command and the Chapter I debug panel command "Calendar" {N}).
-- * Publishes RS.Halloween.State.Calendar {Enabled, Stage, DaysLeft, Target, NextAt, Forced, Revision}; clients
--   (HalloweenClient.CalendarFX) do the grass / fog / moon / lamps / windows / creatures from it.
-- * Respects Shared.CalendarEnabled() (Config.HalloweenCalendarEnabled + the replicated State attribute): switched off,
--   every folder goes back into storage and Stage is published as 0. Nothing here touches player data.
-- API: Calendar.Start(core, modules), Calendar.Stage() -> n, Calendar.Info() -> table, Calendar.Force(stage?) -> ok, msg,
--      Calendar.Refresh(), Calendar.Apply(stage) (moves the folders; tests / Studio).
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("HalloweenCalendarConfig"))
local Rules = require(Halloween:WaitForChild("CalendarRules"))

local Cal = { Current = -1, Forced = nil :: number?, Revision = 0, Started = false }

local function isStudio(): boolean
	return RunService:IsStudio()
end

local function district(): Instance?
	return workspace:FindFirstChild("DOGROTS_District")
end

-- Workspace.DOGROTS_District.41_HalloweenCalendar (created when missing; decor only, never streamed atomically)
local function root(create: boolean): Instance?
	local d = district()
	if not d then
		return nil
	end
	local r = d:FindFirstChild(Cfg.Root)
	if not r and create then
		r = Instance.new("Model")
		r.Name = Cfg.Root
		r:SetAttribute("HalloweenCalendar", true)
		r.Parent = d
	end
	return r
end

local function storage(): Instance?
	return ServerStorage:FindFirstChild(Cfg.Storage)
end

-- the stage number of a stage folder: attribute CalendarStage, else the digits of its name (Stage03 -> 3)
local function stageOf(folder: Instance): number?
	local n = folder:GetAttribute("CalendarStage")
	if type(n) == "number" then
		return n
	end
	local digits = string.match(folder.Name, "^Stage(%d+)$")
	return digits and tonumber(digits) or nil
end

-- every stage folder wherever it currently is (storage or the live root)
local function folders(): { { Folder: Instance, Stage: number } }
	local out = {}
	for _, parent in ipairs({ storage(), root(false) }) do
		if parent then
			for _, f in ipairs(parent:GetChildren()) do
				local n = stageOf(f)
				if n then
					table.insert(out, { Folder = f, Stage = n })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Stage < b.Stage
	end)
	return out
end

-- move the folders: stage <= `stage` live, the rest stored. Returns how many folders moved.
function Cal.Apply(stage: number): number
	local list = folders()
	local moved = 0
	if #list == 0 then
		return 0
	end
	local live = stage > 0 and root(true) or root(false)
	local store = storage()
	if not store then
		store = Instance.new("Folder")
		store.Name = Cfg.Storage
		store.Parent = ServerStorage
	end
	for _, row in ipairs(list) do
		local want = (row.Stage <= stage and live) or store
		if want and row.Folder.Parent ~= want then
			local ok, err = pcall(function()
				row.Folder.Parent = want
			end)
			if ok then
				moved += 1
			else
				warn("Halloween calendar: could not move " .. row.Folder.Name .. ": " .. tostring(err))
			end
		end
	end
	local r = root(false)
	if r then
		r:SetAttribute("Stage", stage)
	end
	return moved
end

local function stateFolder(): Instance?
	local st = Halloween:FindFirstChild("State")
	if not st then
		return nil
	end
	local f = st:FindFirstChild(Cfg.StateName)
	if not f then
		f = Instance.new("Folder")
		f.Name = Cfg.StateName
		f.Parent = st
	end
	return f
end

local function set(f: Instance, key: string, v: any)
	if f:GetAttribute(key) ~= v then
		f:SetAttribute(key, v)
	end
end

local function studioForce(): number?
	if not isStudio() then
		return nil
	end
	if Cal.Forced ~= nil then
		return Cal.Forced
	end
	return Cfg.Studio and Cfg.Studio.ForceStage or nil
end

-- the stage the island should show right now (0 when the calendar is switched off)
local function compute(now: number): (number, boolean, boolean)
	local enabled = Shared.CalendarEnabled()
	if not enabled then
		return 0, false, false
	end
	local stage, forced = Rules.Effective(now, Cfg, studioForce())
	return stage, forced, true
end

function Cal.Refresh()
	local now = os.time()
	local stage, forced, enabled = compute(now)
	local changed = stage ~= Cal.Current
	if changed then
		local moved = Cal.Apply(stage)
		if Cal.Current >= 0 or stage > 0 then
			print(string.format("Halloween calendar: stage %d (%s%d folder moves)", stage, forced and "forced, " or "", moved))
		end
		Cal.Current = stage
		Cal.Revision += 1
	end
	local f = stateFolder()
	if f then
		set(f, "Enabled", enabled)
		set(f, "Stage", stage)
		set(f, "DaysLeft", Rules.DaysLeft(now, Cfg))
		set(f, "Target", Rules.Target(Cfg))
		set(f, "NextAt", (not forced and enabled and Rules.NextChange(now, Cfg)) or 0)
		set(f, "Forced", forced)
		set(f, "Revision", Cal.Revision)
	end
end

function Cal.Stage(): number
	return math.max(0, Cal.Current)
end

function Cal.Info(): { [string]: any }
	local now = os.time()
	local stage, forced, enabled = compute(now)
	return { Stage = stage, Forced = forced, Enabled = enabled, DaysLeft = Rules.DaysLeft(now, Cfg), Target = Rules.Target(Cfg),
		NextAt = Rules.NextChange(now, Cfg), Live = Cal.Current }
end

-- Studio only: show stage n now (0..8), or nil to follow the date again
function Cal.Force(stage: number?): (boolean, string)
	if not isStudio() then
		return false, "Calendar override is Studio only"
	end
	if stage ~= nil then
		local n = tonumber(stage)
		if not n or n ~= n or n < 0 or n > Cfg.MaxStage then
			return false, string.format("Calendar stage must be 0..%d", Cfg.MaxStage)
		end
		Cal.Forced = math.floor(n)
	else
		Cal.Forced = nil
	end
	Cal.Refresh()
	if Cal.Forced then
		return true, string.format("Calendar stage %d", Cal.Forced)
	end
	return true, string.format("Calendar follows the date (stage %d)", Cal.Current)
end

function Cal.Start(_core, modules)
	if Cal.Started then
		return
	end
	Cal.Started = true
	Cal.Refresh()
	-- the chapter switches can be flipped on a live server (State attribute): re-evaluate at once
	local st = Halloween:FindFirstChild("State")
	if st then
		for _, key in ipairs({ "Enabled", "HalloweenCalendarEnabled" }) do
			st:GetAttributeChangedSignal(key):Connect(function()
				task.defer(Cal.Refresh)
			end)
		end
	end
	-- the loop: every CheckEvery seconds, and right at the next stage boundary (+1 s)
	task.spawn(function()
		while true do
			local wait = Cfg.CheckEvery
			local nxt = Rules.NextChange(os.time(), Cfg)
			if nxt then
				wait = math.clamp(nxt - os.time() + 1, 1, Cfg.CheckEvery)
			end
			task.wait(wait)
			local ok, err = pcall(Cal.Refresh)
			if not ok then
				warn("Halloween calendar refresh failed: " .. tostring(err))
			end
		end
	end)
	-- Studio: a "Calendar" command for the Chapter I debug panel (Debug starts after us; its table exists already)
	if isStudio() then
		task.defer(function()
			local D = modules and modules.Debug
			if type(D) == "table" and type(D.Commands) == "table" and D.Commands.Calendar == nil then
				-- {N = 0..8} shows that stage, {N = -1} (or no N) follows the date again
				D.Commands.Calendar = function(_player, a)
					local n = type(a) == "table" and tonumber(a.N) or nil
					if n and n < 0 then
						n = nil
					end
					local ok, msg = Cal.Force(n)
					return ok, { Message = msg }
				end
			end
		end)
	end
end

return Cal
