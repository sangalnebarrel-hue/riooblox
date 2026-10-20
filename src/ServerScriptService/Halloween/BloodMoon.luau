-- BLOOD MOON scheduler (ServerScriptService.Halloween.BloodMoon). Every ~15 minutes (Config.BloodMoon.Period, default
-- one per world-event cycle), phase-locked inside the NORMAL gap of the world-event clock (Shared.BloodMoonAt) so it
-- never overlaps a world event; 30 s warning, 150 s active, 12 s fade. Publishes RS.Halloween.State.BloodMoon attributes (State, Cycle, WarningTimestamp, StartTimestamp,
-- ActiveEndTimestamp, FadeEndTimestamp, EndTimestamp, Revision) and fires Signal "BloodMoon" on every transition.
-- Gameplay modules subscribe with BloodMoon.OnChange(fn(state, info)). Studio: BloodMoon.Force() starts one now.
local RS = game:GetService("ReplicatedStorage")
local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config

local BM = { Listeners = {}, Current = nil, Forced = nil }
local folder = Halloween:WaitForChild("State"):WaitForChild("BloodMoon")

function BM.OnChange(fn: (string, any) -> ())
	table.insert(BM.Listeners, fn)
	if BM.Current then
		task.spawn(fn, BM.Current.State, BM.Current)
	end
end

function BM.Active(): boolean
	return BM.Current ~= nil and BM.Current.State == "ACTIVE"
end

function BM.State(): string
	return BM.Current and BM.Current.State or "NORMAL"
end

-- Studio / debug: start a Blood Moon now (warning first unless skipWarning)
function BM.Force(skipWarning: boolean?)
	local now = os.time()
	local cfg = Config.BloodMoon
	local w = skipWarning and now - cfg.Warning or now
	BM.Forced = { WarningTimestamp = w, StartTimestamp = w + cfg.Warning, ActiveEndTimestamp = w + cfg.Warning + cfg.Active,
		FadeEndTimestamp = w + cfg.Warning + cfg.Active + cfg.Fade, Cycle = -math.floor(now) }
end

function BM.Stop()
	BM.Forced = nil
end

local function compute(now: number)
	local f = BM.Forced
	if f then
		local state
		if now < f.WarningTimestamp then
			state = "NORMAL"
		elseif now < f.StartTimestamp then
			state = "WARNING"
		elseif now < f.ActiveEndTimestamp then
			state = "ACTIVE"
		elseif now < f.FadeEndTimestamp then
			state = "ENDING"
		else
			BM.Forced = nil
			return compute(now)
		end
		local endTs = state == "WARNING" and f.StartTimestamp or state == "ACTIVE" and f.ActiveEndTimestamp or f.FadeEndTimestamp
		return { State = state, Cycle = f.Cycle, Generation = tostring(f.Cycle) .. ":FORCED", WarningTimestamp = f.WarningTimestamp,
			StartTimestamp = f.StartTimestamp, ActiveEndTimestamp = f.ActiveEndTimestamp, FadeEndTimestamp = f.FadeEndTimestamp, EndTimestamp = endTs }
	end
	return Shared.BloodMoonAt(now)
end

local function publish(s)
	for _, key in ipairs({ "State", "Cycle", "WarningTimestamp", "StartTimestamp", "ActiveEndTimestamp", "FadeEndTimestamp", "EndTimestamp" }) do
		if folder:GetAttribute(key) ~= s[key] then
			folder:SetAttribute(key, s[key])
		end
	end
end

function BM.Start(core)
	if BM.Started then
		return
	end
	BM.Started = true
	local first = compute(os.time())
	BM.Current = first
	publish(first)
	folder:SetAttribute("Revision", 1)
	task.spawn(function()
		while true do
			task.wait(.5)
			if not Shared.Enabled() then
				continue
			end
			local s = compute(os.time())
			local prev = BM.Current
			BM.Current = s
			if prev == nil or prev.State ~= s.State or prev.Cycle ~= s.Cycle then
				publish(s)
				folder:SetAttribute("Revision", (folder:GetAttribute("Revision") or 0) + 1)
				core.Signal("all", "BloodMoon", { State = s.State, Cycle = s.Cycle, StartTimestamp = s.StartTimestamp,
					ActiveEndTimestamp = s.ActiveEndTimestamp, EndTimestamp = s.EndTimestamp })
				for _, fn in ipairs(BM.Listeners) do
					task.spawn(fn, s.State, s)
				end
			elseif prev.EndTimestamp ~= s.EndTimestamp then
				publish(s)
			end
		end
	end)
end

return BM
