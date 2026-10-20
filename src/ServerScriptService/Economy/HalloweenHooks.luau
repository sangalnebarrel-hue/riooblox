-- NIGHT OF THE BURIED MOON hooks inside the yard dig (ServerScriptService.Economy.HalloweenHooks, WP4).
-- Called by Economy.Rules R.Dig (server only, inside the profile transaction). Every entry point is pcall-protected
-- and returns a neutral result on any error, so a Halloween problem can never break a dig.
--   H.Pass(p, now)                        once per R.Dig pass -> pass | nil (nil: nothing to do for this player)
--   H.Dog(pass, p, d, def, now)           per working dog before its rolls -> dog state | nil
--   H.Item(pass, ds, effects, random)     per item attempt, before I.Pick / I.Mint: event mutation rows + conversions
--   H.Loot(pass, ds, p, d, produced, now, random) -> extra coins (after the loot rolls, before payIncome)
--   H.After(pass, ds, p, d, now, cooldown, work)    after the item attempts (dig speed abilities)
--   H.Found(pass, p, item, now)          after each minted find: event-mutated finds count for the FindMutation quest
-- Event dogs (Config.Dogs.Defs, abilities only while the dog digs in a yard slot: R.Dig only runs working dogs):
--   H02 Sheet Shiba   YardHaunted: chance per item attempt that the find is HAUNTED (effects.ForceMutation)
--   H03 Bone Corgi    +Bones: bones it digs this pass x (1 + Bones)
--   H04 Frankenpug    every ChargeDigs digs -> OVERCHARGE for Seconds (d.HwChargeUntil; the speed comes from
--                     DogEconomy.BonusSources.BuriedMoon so menus show it too)
--   H05 Bat Dachshund after a find its next dig comes NextDigSpeed faster (d.NextWorkAt shortened)
--   H06 Plague Pug    ItemMutation / TeamMutation through BonusSources.BuriedMoon
--   H07 Headless Hound TreasureChance per dig: a coin cache worth TreasureMinutes of its share of the team income
--   H08 Eclipse Dog   EclipseChance per item attempt: the find becomes ECLIPSED (decided before I.Mint)
--   H01 / H05 spots / H07 cursed treasure: Halloween dig spots (WP7, Runtime.Views team)
-- Natural event rows on every yard dig while the event is ON (Config.Mutations.YardChance x Config.Rebalance.PassiveScale
-- — the Chapter I rebalance keeps passive Halloween generation at ~20% of before; BLOOD MOON only while
-- State.BloodMoon.State == "ACTIVE", which also multiplies every row by Config.BloodMoon.MutationBonus; x ExorcismBoost
-- while State.MutationBoostUntil > now): effects.EventMutations, consumed by ItemRules.MutationRows (WP5).
-- Event dog abilities follow BonusSources.BuriedMoon.Active().
local RS = game:GetService("ReplicatedStorage")

local H = {}

local Bonus, Pricing
do
	local ok, res = pcall(function()
		return require(RS.DogEconomy.BonusSources.BuriedMoon)
	end)
	Bonus = ok and res or nil
	local ok2, res2 = pcall(function()
		return require(RS.DogEconomy.BoostPricing)
	end)
	Pricing = ok2 and res2 or nil
end

local warned = {}
local function safe(name: string, fn, ...)
	local ok, a = pcall(fn, ...)
	if not ok then
		if not warned[name] then
			warned[name] = true
			warn("DOGROTS Halloween dig hook " .. name .. ": " .. tostring(a))
		end
		return nil
	end
	return a
end

local function stateFolder()
	local folder = RS:FindFirstChild("Halloween")
	return folder and folder:FindFirstChild("State")
end

-- {{Name, Chance}} natural event rows for this moment, or nil when the event is off.
function H.Rows(now: number): any
	if not Bonus or not Bonus.EventEnabled() then
		return nil
	end
	local cfg = Bonus.Config()
	local m = cfg and cfg.Mutations
	if type(m) ~= "table" or type(m.YardChance) ~= "table" then
		return nil
	end
	local st = stateFolder()
	local boost = 1
	if st and (tonumber(st:GetAttribute("MutationBoostUntil")) or 0) > now then
		boost = tonumber(m.ExorcismBoost) or 1
	end
	local bm = st and st:FindFirstChild("BloodMoon")
	local blood = bm ~= nil and bm:GetAttribute("State") == "ACTIVE"
	if blood then
		boost *= math.max(1, tonumber(cfg.BloodMoon and cfg.BloodMoon.MutationBonus) or 1)
	end
	local passive = type(cfg.Rebalance) == "table" and tonumber(cfg.Rebalance.PassiveScale) or nil
	if passive and passive == passive then
		boost *= math.clamp(passive, 0, 1)
	end
	local rows = {}
	for _, name in ipairs(m.Order or {}) do
		local chance = tonumber(m.YardChance[name])
		if chance and chance > 0 and (name ~= "BLOOD MOON" or blood) then
			table.insert(rows, { Name = name, Chance = chance * boost })
		end
	end
	return #rows > 0 and rows or nil
end

local function pass(p: any, now: number): any
	local abilities = Bonus ~= nil and Bonus.Active()
	local rows = H.Rows(now)
	local working, eventDogs = 0, 0
	for _, d in pairs(type(p.Dogs) == "table" and p.Dogs or {}) do
		if Bonus and Bonus.Working(d) then
			working += 1
			if abilities and Bonus.Ability(d.DogId) then
				eventDogs += 1
			end
		end
	end
	if not rows and eventDogs == 0 then
		return nil
	end
	return { Now = now, Rows = rows, Abilities = abilities and eventDogs > 0, Working = math.max(1, working) }
end
function H.Pass(p: any, now: number): any
	return safe("Pass", pass, p, now)
end

function H.Dog(ps: any, p: any, d: any, def: any, _now: number): any
	return safe("Dog", function()
		local ability = ps.Abilities and def and def.EventDex and Bonus.Ability(d.DogId) or nil
		if not ability and not ps.Rows then
			return nil
		end
		return { Id = d.DogId, Ability = ability, Bones0 = tonumber(p.Bones) or 0, Found = false }
	end)
end

function H.Item(ps: any, ds: any, effects: any, random: () -> number)
	safe("Item", function()
		if ps.Rows then
			effects.EventMutations = ps.Rows
		end
		local a = ds.Ability
		if not a then
			return
		end
		local name, chance = nil, 0
		if ds.Id == "HW_EclipseDog" then
			name, chance = "ECLIPSED", tonumber(a.EclipseChance) or 0
		elseif ds.Id == "HW_SheetShiba" then
			name, chance = "HAUNTED", tonumber(a.YardHaunted) or 0
		end
		if name and chance > 0 and random() < chance then
			effects.ForceMutation = name
			effects.ForceMutationChance = chance
		end
	end)
end

function H.Loot(ps: any, ds: any, p: any, d: any, produced: number, now: number, random: () -> number): number
	return safe("Loot", function()
		local a = ds.Ability
		if not a then
			return 0
		end
		if ds.Id == "HW_BoneCorgi" then
			local gained = (tonumber(p.Bones) or 0) - ds.Bones0
			if gained > 0 then
				local exact = gained * (tonumber(a.Bones) or 0)
				local whole = math.floor(exact)
				if random() < exact - whole then
					whole += 1
				end
				p.Bones += whole
				ds.BonusBones = whole
			end
		elseif ds.Id == "HW_HeadlessHound" and produced > 0 and Pricing then
			if random() < (tonumber(a.TreasureChance) or 0) then
				local share = Pricing.Rate(p, now) / ps.Working
				-- a.TreasureFloor: the smallest Headless Treasure, x BoostPricing layer scale (Config.Dogs.Defs)
				local coins = Pricing.Round(math.max(Pricing.Floor(p, tonumber(a.TreasureFloor) or 0), share * 60 * (tonumber(a.TreasureMinutes) or 0)))
				d.LastAbility = "HEADLESS TREASURE"
				d.HwTreasureAt = now
				d.HwTreasures = (tonumber(d.HwTreasures) or 0) + 1
				return math.max(0, math.floor(coins))
			end
		end
		return 0
	end) or 0
end

-- An event-mutated yard find (natural row, Sheet Shiba, Eclipse Dog) counts like the Halloween grants do (Core ctx.Item):
-- Stats.Mutations + the daily FindMutation quest. Only while the event is on (the profile data is the event's).
local Feature = nil
function H.Found(_ps: any, p: any, item: any, now: number)
	safe("Found", function()
		local c = Bonus and Bonus.Config()
		local name = type(item) == "table" and type(item.Mutation) == "string" and string.upper(item.Mutation) or nil
		if not name or not c or type(c.Mutations) ~= "table" or not c.Mutations.Defs[name] or not Bonus.EventEnabled() then
			return
		end
		Feature = Feature or require(script.Parent.Features.Halloween)
		local h = Feature.Shape(p)
		h.Stats.Mutations += 1
		Feature.QuestProgress(p, "FindMutation", 1, now)
	end)
end

function H.After(ps: any, ds: any, _p: any, d: any, now: number, cooldown: number, work: any)
	safe("After", function()
		local a = ds.Ability
		if not a then
			return
		end
		-- ds.Hit: the mutation of a converted find that was really minted (set by Rules after I.Mint)
		if ds.Hit == "ECLIPSED" or ds.Hit == "HAUNTED" then
			d.LastAbility = ds.Hit == "ECLIPSED" and "ECLIPSE" or "GHOST LOOT"
		end
		if ds.Id == "HW_Frankenpug" then
			if (tonumber(d.HwChargeUntil) or 0) <= now then
				d.HwCharge = (tonumber(d.HwCharge) or 0) + 1
				if d.HwCharge >= (tonumber(a.ChargeDigs) or 5) then
					d.HwCharge = 0
					d.HwChargeUntil = now + (tonumber(a.Seconds) or 40)
					d.LastAbility = "OVERCHARGE"
				end
			end
		elseif ds.Id == "HW_BatDachshund" and ds.Found and type(cooldown) == "number" then
			local speed = tonumber(a.NextDigSpeed) or 0
			if speed > 0 then
				local floor = (work and work.MinCooldown or 6) * 0.75
				local fast = math.max(floor, cooldown / (1 + speed))
				d.NextWorkAt = now + math.min(cooldown, fast) + (work and work.Duration or 4)
				d.LastAbility = "NIGHT FLIGHT"
			end
		end
	end)
end

return H
