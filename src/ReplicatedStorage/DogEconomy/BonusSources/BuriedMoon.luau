-- Bonus source: NIGHT OF THE BURIED MOON event dogs (ReplicatedStorage.DogEconomy.BonusSources.BuriedMoon, WP4).
-- Loaded by DogEconomy.Bonuses (server Rules.Dig / IncomeModel and the client menus), so every screen shows the numbers
-- the server applies. Pure and nil-safe; numbers from ReplicatedStorage.Halloween.Config.Dogs.Defs.
--   Plague Pug       ItemMutation +ItemMutation on its own finds; +TeamMutation for the whole team while it digs (once)
--   Frankenpug       DigSpeed +Speed while OVERCHARGED (dog field HwChargeUntil, written by Economy.HalloweenHooks)
-- The other event abilities act inside the dig itself (Economy.HalloweenHooks) or at Halloween dig spots (WP7).
-- Policy: event dogs keep their abilities after the event (they are permanent dogs). Set AbilitiesNeedEvent = true to
-- switch every event-dog ability off together with the event (HalloweenEventEnabled / State.Enabled).
local RS = game:GetService("ReplicatedStorage")
local Defs = require(script.Parent.Parent.DogDefinitions)

local S = { Name = "BuriedMoon" }
S.AbilitiesNeedEvent = false

local cached = nil
local function config(): any
	if cached then
		return cached
	end
	local ok, res = pcall(function()
		local folder = RS:FindFirstChild("Halloween")
		local module = folder and folder:FindFirstChild("Config")
		return module and require(module) or nil
	end)
	-- not cached while missing (it may still be replicating on a client)
	cached = ok and type(res) == "table" and type(res.Dogs) == "table" and res or nil
	return cached
end
S.Config = config

-- The event switch (Config flag confirmed by RS.Halloween.State.Enabled), like Halloween.Shared.Enabled.
function S.EventEnabled(): boolean
	local c = config()
	if not c or not c.HalloweenEventEnabled then
		return false
	end
	local folder = RS:FindFirstChild("Halloween")
	local state = folder and folder:FindFirstChild("State")
	local v = state and state:GetAttribute("Enabled")
	return v == nil or v == true
end

-- THE DEAD YARD activities on? (the event, Config.HalloweenChapter1Enabled and the server's replicated switch)
function S.Chapter1Enabled(): boolean
	if not S.EventEnabled() then
		return false
	end
	local c = config()
	if c and c.HalloweenChapter1Enabled == false then
		return false
	end
	local folder = RS:FindFirstChild("Halloween")
	local state = folder and folder:FindFirstChild("State")
	return not (state and state:GetAttribute("HalloweenChapter1Enabled") == false)
end

-- Do event-dog abilities apply right now?
function S.Active(): boolean
	if not config() then
		return false
	end
	if S.AbilitiesNeedEvent then
		return S.EventEnabled()
	end
	return true
end

-- Ability numbers of an event dog (Config.Dogs.Defs[id]) or nil.
function S.Ability(id: any): any
	local c = config()
	local def = type(id) == "string" and Defs[id]
	if not c or not def or not def.EventDex then
		return nil
	end
	return c.Dogs.Defs[id]
end

local function working(d: any): boolean
	return type(d) == "table" and type(d.AssignedSlot) == "string" and d.AssignedSlot ~= "" and d.State ~= "Walking"
end
S.Working = working

function S.Dog(_p, d, now, add)
	if type(d) ~= "table" or not S.Active() then
		return
	end
	local ability = S.Ability(d.DogId)
	if not ability then
		return
	end
	if d.DogId == "HW_PlaguePug" then
		add("ItemMutation", tonumber(ability.ItemMutation) or 0)
	elseif d.DogId == "HW_Frankenpug" then
		-- a current charge ends after `now` and at most Seconds (+ slack) after it: the quiet-time estimates
		-- (OfflineEarnings / BaseRate model the dog at now = 41) must not see a saved unix time as a permanent charge
		local untilAt = tonumber(d.HwChargeUntil) or 0
		local t = tonumber(now) or os.time()
		if untilAt > t and untilAt - t <= (tonumber(ability.Seconds) or 40) + 5 then
			add("DigSpeed", tonumber(ability.Speed) or 0)
		end
	end
end

function S.Global(p, _now, add)
	if type(p) ~= "table" or type(p.Dogs) ~= "table" or not S.Active() then
		return
	end
	-- Config.Dogs.TeamOnly: only a Plague Pug assigned to a dig slot spreads its plague
	for _, d in pairs(p.Dogs) do
		if type(d) == "table" and d.DogId == "HW_PlaguePug" and working(d) then
			local ability = S.Ability(d.DogId)
			add("ItemMutation", ability and tonumber(ability.TeamMutation) or 0)
			return -- the plague aura does not stack
		end
	end
end

return S
