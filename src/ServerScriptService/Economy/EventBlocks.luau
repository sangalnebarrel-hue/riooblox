-- NIGHT OF THE BURIED MOON Lucky Block tiers (ServerScriptService.Economy.EventBlocks): PUMPKIN and CURSED PUMPKIN.
-- They live in the normal p.OwnedBlocks, sit on the normal Lucky Pads and open through LuckyLifecycle.Open; this
-- module only freezes their reward table and resolves the rows that are not dogs.
--   E.Has(tier) / E.Def(tier)                    event tier? (LuckyBlockConfig.EventTiers)
--   E.Rows(tier) -> {row}                        fresh copies of the reward rows (Halloween.Config.Rewards[def.Rewards])
--   E.Freeze(b, random)                          at grant (LuckyLifecycle.AddStored): Seed + Pool + Variants + OddsVersion,
--                                                so freeze()/RewardService.Pool never run for an event block. The Pool is
--                                                frozen for good: a later balance change (the Chapter I rare prize
--                                                rescale, Config.Rebalance) only reaches blocks granted after it
--   E.Ghost(b) -> bool                           deterministic "a ghost flies out" flag (own stream; never moves the roll)
--   E.Apply(p, b, row, rand, now) -> value       inside LuckyLifecycle.Open's transaction for a row with Kind ~= 'Dog':
--                                                Cash / Bones / Candy / Dust / Decor / Skin / Mutation. Never fails on a
--                                                full wallet, decor set, skin collection or bag: converts and marks
--                                                Converted. Dust (the rescaled tables' filler): Amount = n or {min, max}
--                                                rolled on the block's own stream -> Resources "LuckyDust" (no art model:
--                                                the reward card / pumpkin show fall back to the name)
--   E.Track(p, b, value, now) -> questRow?       quest OpenPumpkin + stat Pumpkins (+ FindMutation / Mutations for an
--                                                event-mutated find) while the event is on; inside the same transaction
--   E.AfterOpen(player, value, quest)            after commit: pushes the Halloween view / QuestComplete to the client
--   E.Odds(tier) -> {{Id,Kind,Name,Rarity,Rank,Chance}}   disclosed chances (RewardService Catalog, LuckyBlockUI)
-- Plain ModuleScript (not a Feature): Features load while Rules loads, this one may require Rules at the top.
-- Saved data: blocks are never deleted when the event ends; they keep opening (and their show keeps playing).
local RS = game:GetService("ReplicatedStorage")
local Blocks = require(RS:WaitForChild("LuckyBlockConfig"))
local Econ = require(RS:WaitForChild("DogEconomy"):WaitForChild("Config"))
local R = require(script.Parent:WaitForChild("Rules"))

local E = {}

local function hw()
	local folder = RS:FindFirstChild("Halloween") or RS:WaitForChild("Halloween", 10)
	local module = folder and (folder:FindFirstChild("Config") or folder:WaitForChild("Config", 10))
	return module and require(module) or {}
end
E.Config = hw

-- Event on? (config switch + the server's State.Enabled attribute) — only for quests / stats, never for opening.
function E.Enabled(): boolean
	local cfg = hw()
	if cfg.HalloweenEventEnabled ~= true then
		return false
	end
	local folder = RS:FindFirstChild("Halloween")
	local state = folder and folder:FindFirstChild("State")
	local v = state and state:GetAttribute("Enabled")
	return v == nil or v == true
end

function E.Has(tier: any): boolean
	return type(tier) == "string" and Blocks.EventTiers ~= nil and Blocks.EventTiers[tier] ~= nil
end

function E.Def(tier: any)
	return E.Has(tier) and Blocks.EventTiers[tier] or nil
end

-- the reward table of an event tier (Halloween.Config.Rewards[def.Rewards]; PumpkinBlocks[tier] as a legacy fallback)
local function rawRows(tier: string): { any }
	local cfg = hw()
	local def = E.Def(tier)
	local key = def and def.Rewards
	local rows = key and type(cfg.Rewards) == "table" and cfg.Rewards[key]
	if type(rows) ~= "table" and type(cfg.PumpkinBlocks) == "table" then
		rows = cfg.PumpkinBlocks[tier]
	end
	return type(rows) == "table" and rows or {}
end

local KINDS = { Cash = true, Bones = true, Candy = true, Dust = true, Decor = true, Skin = true, Mutation = true, Dog = true }
function E.Rows(tier: string): { any }
	local out = {}
	for _, row in ipairs(rawRows(tier)) do
		if type(row) == "table" and KINDS[row.Kind] and (tonumber(row.Weight) or 0) > 0 then
			local copy = R.Copy(row)
			copy.Weight = tonumber(copy.Weight)
			copy.Rank = math.clamp(math.floor(tonumber(copy.Rank) or 1), 1, 6)
			copy.Rarity = type(copy.Rarity) == "string" and copy.Rarity or ({ "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" })[copy.Rank]
			copy.Name = type(copy.Name) == "string" and copy.Name or tostring(copy.Id or copy.Kind)
			table.insert(out, copy)
		end
	end
	return out
end

function E.Freeze(b: any, random: any)
	if type(b) ~= "table" or not E.Has(b.Tier) then
		return
	end
	if b.Pool and b.Variants and b.Seed then
		return
	end
	local rows = E.Rows(b.Tier)
	R.Check(#rows > 0, "Event reward table missing for " .. tostring(b.Tier))
	b.Pool = rows
	b.Seed = b.Seed or random:NextInteger(1, 2147483646)
	local ok, variants = pcall(function()
		return require(RS.WorldEvents.WorldEventModifiers).MutationRows(Econ.Variants, "Name", "Weight", os.time())
	end)
	b.Variants = R.Copy(ok and variants or Econ.Variants)
	local rb = hw().Rebalance
	b.OddsVersion = (type(rb) == "table" and rb.Applied == true and type(rb.OddsVersion) == "string") and rb.OddsVersion
		or ("hw" .. tostring(hw().DataVersion or 1))
end

-- the same weighted pick LuckyLifecycle.Open makes (Random.new(Seed), first NextNumber)
function E.Pick(b: any): any
	local pool = b.Pool or {}
	local rand = Random.new(b.Seed)
	local total = 0
	for _, row in ipairs(pool) do
		total += row.Weight
	end
	local n = rand:NextNumber() * total
	local chosen = pool[#pool]
	for _, row in ipairs(pool) do
		n -= row.Weight
		if n < 0 then
			chosen = row
			break
		end
	end
	return chosen, rand
end

function E.Ghost(b: any): boolean
	local def = E.Def(b and b.Tier)
	if not def or type(b.Seed) ~= "number" then
		return false
	end
	local chance = tonumber(def.GhostChance) or 0
	if chance >= 1 then
		return true
	end
	return Random.new((b.Seed * 7) % 2147483646 + 1):NextNumber() < chance
end

local function share(b: any, row: any): number
	local total = 0
	for _, r in ipairs(b.Pool or {}) do
		total += r.Weight or 0
	end
	return total > 0 and (row.Weight or 0) / total or 1
end

local function bones(p: any, n: number): number
	n = math.max(0, math.min(math.floor(n or 0), Econ.MaxCash - (p.Bones or 0)))
	p.Bones = (p.Bones or 0) + n
	return n
end

local function coins(p: any, spec: any, now: number): number
	local amount = 0
	if type(spec) == "table" then
		amount = require(RS.DogEconomy.BoostPricing).Coins(spec, p, now)
	elseif type(spec) == "number" then
		amount = spec
	end
	amount = math.max(0, math.min(math.floor(tonumber(amount) or 0), Econ.MaxCash - p.Cash))
	if amount > 0 then
		R.Credit(p, amount)
	end
	return amount
end

-- a Dust row's amount: n, or {min, max} rolled on the block's own stream (rand: the Random the pick was made with)
local function dustAmount(spec: any, rand: any): number
	if type(spec) == "table" then
		local lo = math.max(0, math.floor(tonumber(spec[1]) or 0))
		local hi = math.max(lo, math.floor(tonumber(spec[2]) or lo))
		if rand and type(rand.NextInteger) == "function" then
			return rand:NextInteger(lo, hi)
		end
		return math.floor((lo + hi) / 2)
	end
	return math.max(0, math.floor(tonumber(spec) or 0))
end

local function number(n: number): string
	local ok, text = pcall(function()
		return require(RS.PriceFormat).Number(n)
	end)
	return ok and text or tostring(n)
end

-- an item rolled on the player's deepest layer (the bag must have room) with the row's event mutation forced
local function mutatedFind(p: any, b: any, row: any, rand: any, now: number): any
	local I = require(script.Parent.ItemRules)
	if not I.Free(p) then
		return nil
	end
	local roll = function()
		return rand:NextNumber()
	end
	local e = R.Team(p, now)
	local def, chance = nil, nil
	if type(row.ItemId) == "string" and I.Definitions[row.ItemId] then
		def = I.Definitions[row.ItemId]
		chance = def.BaseDropChance
	end
	local depth = math.clamp(math.floor(tonumber(row.Depth) or R.MaxUnlockedLayer(p) or 1), 1, 5)
	for _ = 1, 16 do
		if def then
			break
		end
		def, chance = I.Pick(depth, roll, e)
	end
	for _ = 1, 16 do
		if def then
			break
		end
		def, chance = I.Pick(1, roll, e)
	end
	if not def then
		return nil
	end
	e.ForceMutation = string.upper(tostring(row.Id))
	e.ForceMutationChance = share(b, row)
	local uid = "PB" .. tostring(b.Uid)
	if p.Items and p.Items[uid] then
		uid = uid .. ":" .. tostring(now)
	end
	local x = I.Mint(p, def, chance, uid, now, roll, e)
	x.Origin = "Halloween"
	return x
end

function E.Apply(p: any, b: any, row: any, rand: any, now: number): any
	local kind = row.Kind
	local v = { Kind = kind, Id = row.Id, Name = row.Name, Rarity = row.Rarity, Rank = row.Rank }
	if kind == "Cash" then
		v.Amount = coins(p, row.Coins or row.Amount or 0, now)
		v.Name = number(v.Amount) .. " Coins"
	elseif kind == "Bones" then
		v.Amount = bones(p, row.Amount or 0)
		v.Name = number(v.Amount) .. " Bones"
	elseif kind == "Candy" then
		local F = require(script.Parent.Features.Halloween)
		v.Amount = F.AddCandy(p, tonumber(row.Amount) or 0)
		v.Name = number(v.Amount) .. " Candy"
	elseif kind == "Dust" then
		local n = dustAmount(row.Amount, rand)
		local Resources = require(RS.DogEconomy.Resources)
		if Resources.Kinds.LuckyDust and n > 0 then
			v.Amount = Resources.Add(p, "LuckyDust", n)
			v.Name = number(v.Amount) .. " Lucky Dust"
		else
			-- a build without Lucky Dust: the same roll as bones (never a failed open)
			v.Kind, v.Converted = "Bones", true
			v.Amount = bones(p, math.max(1, n))
			v.Name = number(v.Amount) .. " Bones"
		end
	elseif kind == "Decor" then
		local Catalog = require(RS.DogEconomy.DecorCatalog)
		require(script.Parent.Features.Decor).Normalize(R, p, now)
		local item = Catalog.Get(row.Id)
		local have = p.Decor.Owned[row.Id] or 0
		if item and have < Catalog.MaxOwned(row.Id) then
			p.Decor.Owned[row.Id] = have + 1
			v.Name = item.Name
		else
			v.Kind, v.Converted = "Bones", true
			v.Amount = bones(p, row.Rank and row.Rank >= 3 and 120 or 60)
			v.Name = number(v.Amount) .. " Bones"
			v.Detail = "Decoration maxed"
		end
	elseif kind == "Skin" then
		local F = require(script.Parent.Features.Halloween)
		local h = F.Shape(p)
		local names = hw().Skins and hw().Skins.Names or {}
		R.Check(type(row.Id) == "string" and names[row.Id] ~= nil, "Unknown pickaxe skin")
		if h.Skins[row.Id] then
			v.Kind, v.Converted = "Bones", true
			v.Amount = bones(p, 100 * math.max(1, (row.Rank or 4) - 2))
			v.Name = number(v.Amount) .. " Bones"
			v.Detail = "Skin already owned"
		else
			h.Skins[row.Id] = true -- p.Halloween.Skins, never p.Cosmetics (every Cosmetics key becomes a title)
			v.Name = string.upper(names[row.Id]) .. " SKIN"
		end
	elseif kind == "Mutation" then
		local x = mutatedFind(p, b, row, rand, now)
		if x then
			v.Item = R.Copy(x)
			v.Mutation = x.Mutation
			v.Name = tostring(row.Name or (tostring(x.Mutation) .. " FIND")) .. " · " .. tostring(x.DisplayName)
		else
			-- full bag (or nothing to roll): the find becomes coins worth a long dig
			v.Kind, v.Converted = "Cash", true
			v.Amount = coins(p, { MinCash = 40000 * (row.Rank or 3), IncomeMinutes = 10 * (row.Rank or 3) }, now)
			v.Name = number(v.Amount) .. " Coins"
			v.Detail = "Bag full"
		end
	else
		error("Unknown event reward " .. tostring(kind), 0)
	end
	return v
end

function E.Track(p: any, b: any, value: any, now: number): any
	if not E.Enabled() or not E.Has(b and b.Tier) then
		return nil
	end
	local F = require(script.Parent.Features.Halloween)
	local h = F.Shape(p)
	h.Stats.Pumpkins += 1
	local done = F.QuestProgress(p, "OpenPumpkin", 1, now)
	local x = type(value) == "table" and value.Item
	local cfg = hw()
	if type(x) == "table" and type(x.Mutation) == "string" and cfg.Mutations and cfg.Mutations.Defs and cfg.Mutations.Defs[x.Mutation] then
		h.Stats.Mutations += 1
		done = F.QuestProgress(p, "FindMutation", 1, now) or done
	end
	return done
end

function E.AfterOpen(player: any, value: any, quest: any)
	if not E.Enabled() then
		return
	end
	local ok, err = pcall(function()
		local folder = RS:FindFirstChild("Halloween")
		local remotes = folder and folder:FindFirstChild("Remotes")
		local signal = remotes and remotes:FindFirstChild("Signal")
		if not signal then
			return
		end
		if type(quest) == "table" and quest.Id then
			local F = require(script.Parent.Features.Halloween)
			local def = F.QuestDef(quest.Id)
			signal:FireClient(player, "QuestComplete", { Id = quest.Id, Text = def and def.Text, Goal = def and def.Goal })
		end
		local runtime = require(script.Parent.Runtime)
		local p = runtime.Engine:Get(player.UserId)
		if type(p) == "table" and type(p.Halloween) == "table" then
			local F = require(script.Parent.Features.Halloween)
			local now = os.time()
			local view = F.View(p, now)
			-- the same view Halloween.Core sends: + TRICK price of the moment and the catch-up brew time
			local folder = RS:FindFirstChild("Halloween")
			local rules = folder and folder:FindFirstChild("Chapter1Rules")
			local shared = folder and folder:FindFirstChild("Shared")
			if rules and shared and type(p.Halloween.Cauldron) == "table" then
				local Shared = require(shared) :: any
				require(rules).DecorateView(view, p.Halloween, now, hw(), Shared.BrewSeconds(p.Halloween.Cauldron.StartedAt))
			end
			signal:FireClient(player, "View", { View = view })
		end
	end)
	if not ok then
		warn("EventBlocks after-open: " .. tostring(err))
	end
end

function E.Odds(tier: string): { any }
	local rows = E.Rows(tier)
	local total = 0
	for _, row in ipairs(rows) do
		total += row.Weight
	end
	local defs = nil
	pcall(function()
		defs = require(RS.DogEconomy.DogDefinitions)
	end)
	local out = {}
	for _, row in ipairs(rows) do
		local dog = row.Kind == "Dog" and defs and defs[row.Id] or nil
		table.insert(out, { Id = row.Id, Kind = row.Kind, Name = dog and dog.DisplayName or row.Name, Rarity = row.Rarity,
			Rank = row.Rank, Chance = total > 0 and row.Weight / total or 0 })
	end
	return out
end

return E
