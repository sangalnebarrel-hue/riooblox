-- EQUIPMENT (feature module, see Economy.FeatureRegistry): dog artifacts, player accessories and
-- the cases they come from. Catalogue and balance: ReplicatedStorage.DogEconomy.EquipmentDefinitions.
-- Stats reach the game through Bonuses (BonusSources.Artifacts / Accessories). Docs: docs/EQUIPMENT.md.
--
-- p.Equipment = {Version=1, Next=n (uid counter), Rev=n (bumped on every change),
--   Artifacts   = {[uid] = {Uid, Id, Rarity, Roll (0..1), DogUid?, Slot? (1..n), CreatedAt, Origin, PaidRandom?, Locked?}},
--   Accessories = {[uid] = {Uid, Id, Rarity, Roll, Slot? (equipped slot name), CreatedAt, Origin, PaidRandom?, Locked?}},
--   CaseCredits = {[caseId] = {Free = n, Paid = n}}, Seen = {[pieceId] = true}, Pity = {[caseId] = n}, Opened = {[caseId] = n}}
-- Artifacts point at dogs (DogUid) and are never stored inside p.Dogs: a dog that leaves the
-- profile (lab, trade, market listing, shelter) simply leaves its artifacts in the bag (Normalize).
--
-- Actions (DogEconomyRequest -> Rules.Action -> here):
--   EquipmentOpenCase {Case, Pay = 'Cash'|'Bones'|'Credit', Quote?} -> message, {Opened, Reel, WinIndex, Case}
--   EquipArtifact {Uid, DogUid, Slot}   UnequipArtifact {Uid}
--   EquipAccessory {Uid}                UnequipAccessory {Slot}
--   SalvageEquipment {Uids = {...}}     LockEquipment {Uid, Enabled}
-- Robux: credits for the Robux cases are granted by PurchaseService receipts (F.Catalogs); opening
-- them is EquipmentOpenCase with Pay = 'Credit' (free credits first, paid ones only where Roblox
-- policy allows paid random items; those pieces get PaidRandom = true).
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local E = require(RS.DogEconomy.EquipmentDefinitions)
local DogDefinitions = require(RS.DogEconomy.DogDefinitions)
local Config = require(script.Parent.Parent.Config)

local F = { Name = "Equipment", Order = 40 }
F.Definitions = E

local MAX_INT = 9007199254740990
local MAX_CREDITS = 1000000
local REEL_LENGTH, WIN_INDEX = 32, 27

local function int(n: any, min: number, max: number): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= min and n <= max
end
local function count(t: any): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end
local function wholeOrZero(n: any, max: number): number
	if type(n) ~= "number" or n ~= n or n < 0 then
		return 0
	end
	return math.min(math.floor(n), max)
end

function F.New(): any
	return { Version = E.Version, Next = 1, Rev = 0, Artifacts = {}, Accessories = {}, CaseCredits = {}, Seen = {}, Pity = {}, Opened = {} }
end

-- p.Equipment with every table present (no other healing). Used by the actions and grants.
function F.Ensure(p: any): any
	local eq = p.Equipment
	if type(eq) ~= "table" then
		eq = F.New()
		p.Equipment = eq
	end
	for _, key in ipairs({ "Artifacts", "Accessories", "CaseCredits", "Seen", "Pity", "Opened" }) do
		if type(eq[key]) ~= "table" then
			eq[key] = {}
		end
	end
	if not int(eq.Next, 1, MAX_INT) then
		eq.Next = 1
	end
	if not int(eq.Rev, 0, MAX_INT) then
		eq.Rev = 0
	end
	return eq
end

local function dogSlots(dog: any): number
	return E.DogSlots(DogDefinitions[dog.DogId] or dog)
end

-- Defaults, healing of saved data and dangling pointers. Never drops a valid piece.
function F.Normalize(_R, p, _now)
	local eq = F.Ensure(p)
	if not int(eq.Version, 1, MAX_INT) or eq.Version < E.Version then
		eq.Version = E.Version
	end
	local changed = false
	local dogs = type(p.Dogs) == "table" and p.Dogs or {}
	-- Artifacts: the dog must still be in p.Dogs, the slot must exist on it and be unique.
	local occupied = {}
	for uid, a in pairs(eq.Artifacts) do
		if type(a) ~= "table" or type(uid) ~= "string" then
			eq.Artifacts[uid] = nil
			changed = true
			continue
		end
		if a.Uid ~= uid then
			a.Uid = uid
			changed = true
		end
		local def = E.ArtifactById[a.Id]
		if def and a.Rarity ~= def.Rarity then
			a.Rarity = def.Rarity
			changed = true
		end
		local roll = tonumber(a.Roll)
		if roll == nil or roll ~= roll or roll < 0 or roll > 1 then
			a.Roll = roll and roll == roll and math.clamp(roll, 0, 1) or 0
			changed = true
		end
		if a.Locked ~= nil and a.Locked ~= true then
			a.Locked = nil
		end
		if a.DogUid ~= nil or a.Slot ~= nil then
			local dog = type(a.DogUid) == "string" and dogs[a.DogUid] or nil
			local slot = a.Slot
			local ok = def ~= nil and type(dog) == "table" and int(slot, 1, dogSlots(dog))
			if ok then
				local key = a.DogUid .. "#" .. slot
				local other = occupied[key]
				if other then
					-- Two artifacts in one slot: the lower uid keeps it.
					if uid < other.Uid then
						other.DogUid, other.Slot = nil, nil
						occupied[key] = a
					else
						ok = false
					end
					changed = true
				else
					occupied[key] = a
				end
			end
			if not ok then
				a.DogUid, a.Slot = nil, nil
				changed = true
			end
		end
	end
	-- Accessories: the slot must be the definition's slot and hold one accessory.
	local worn = {}
	for uid, a in pairs(eq.Accessories) do
		if type(a) ~= "table" or type(uid) ~= "string" then
			eq.Accessories[uid] = nil
			changed = true
			continue
		end
		if a.Uid ~= uid then
			a.Uid = uid
			changed = true
		end
		local def = E.AccessoryById[a.Id]
		if def and a.Rarity ~= def.Rarity then
			a.Rarity = def.Rarity
			changed = true
		end
		local roll = tonumber(a.Roll)
		if roll == nil or roll ~= roll or roll < 0 or roll > 1 then
			a.Roll = roll and roll == roll and math.clamp(roll, 0, 1) or 0
			changed = true
		end
		if a.Locked ~= nil and a.Locked ~= true then
			a.Locked = nil
		end
		if a.Slot ~= nil then
			local ok = def ~= nil and a.Slot == def.Slot
			if ok then
				local other = worn[a.Slot]
				if other then
					if uid < other.Uid then
						other.Slot = nil
						worn[a.Slot] = a
					else
						ok = false
					end
					changed = true
				else
					worn[a.Slot] = a
				end
			end
			if not ok then
				a.Slot = nil
				changed = true
			end
		end
	end
	-- Credits, pity and counters: whole numbers >= 0.
	for caseId, credit in pairs(eq.CaseCredits) do
		if type(caseId) ~= "string" or type(credit) ~= "table" then
			eq.CaseCredits[caseId] = nil
		else
			credit.Free = wholeOrZero(credit.Free, MAX_CREDITS)
			credit.Paid = wholeOrZero(credit.Paid, MAX_CREDITS)
		end
	end
	for _, key in ipairs({ "Pity", "Opened" }) do
		local t = eq[key]
		for caseId, n in pairs(t) do
			if type(caseId) ~= "string" then
				t[caseId] = nil
			elseif not int(n, 0, MAX_INT) then
				t[caseId] = wholeOrZero(n, MAX_INT)
			end
		end
	end
	for id, seen in pairs(eq.Seen) do
		if type(id) ~= "string" or seen ~= true then
			eq.Seen[id] = nil
		end
	end
	if changed then
		eq.Rev += 1
	end
end

-- Structure only (trade / lab call Validate without Normalize): never rejects what Normalize heals.
function F.Validate(R, p)
	if p.Equipment ~= nil then
		R.Check(type(p.Equipment) == "table", "Invalid equipment data")
	end
end

------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------
local function newUid(p: any, eq: any): string
	local n = eq.Next
	local uid
	repeat
		uid = "E" .. tostring(p.UserId or 0) .. "-" .. tostring(n)
		n += 1
	until eq.Artifacts[uid] == nil and eq.Accessories[uid] == nil
	eq.Next = n
	return uid
end

local function bagOf(eq: any, kind: string): any
	return kind == "Artifact" and eq.Artifacts or eq.Accessories
end

local function round4(x: number): number
	return math.floor(x * 10000 + 0.5) / 10000
end

-- Rarity of one open: the case odds, or only the rarities at or above the pity floor when this
-- open completes the pity streak. Returns rarity, forcedByPity.
function F.RollRarity(case: any, streak: number, random: () -> number): (string, boolean)
	local rows = E.Odds(case)
	local floor = case.Pity and E.RarityIndex[case.Pity.Rarity] or nil
	local forced = floor ~= nil and streak + 1 >= case.Pity.Opens
	local total = 0
	local candidates = {}
	for _, row in ipairs(rows) do
		if not forced or E.RarityIndex[row.Rarity] >= floor then
			table.insert(candidates, row)
			total += row.Chance
		end
	end
	local r = random() * total
	for _, row in ipairs(candidates) do
		r -= row.Chance
		if r < 0 then
			return row.Rarity, forced
		end
	end
	return candidates[#candidates].Rarity, forced
end

local function pick(list: { any }, random: () -> number): any
	local i = math.floor(random() * #list) + 1
	return list[math.clamp(i, 1, #list)]
end

-- The pieces the opening reel shows: honest draws with the case odds, the winner at WinIndex.
local function reel(case: any, winner: any, random: () -> number): { string }
	local pool = E.Pool(case)
	local rows = E.Odds(case)
	local ids = {}
	for i = 1, REEL_LENGTH do
		if i == WIN_INDEX then
			ids[i] = winner.Id
		else
			local r = random()
			local rarity = rows[#rows].Rarity
			for _, row in ipairs(rows) do
				r -= row.Chance
				if r < 0 then
					rarity = row.Rarity
					break
				end
			end
			ids[i] = pick(pool[rarity], random).Id
		end
	end
	return ids
end

-- The client may quote the price it showed: within 5% of the server price it is charged, a real
-- change (income moved) asks the player to look again. Never more than the server price.
local function quoted(R: any, price: number, quote: any): number
	if type(quote) ~= "number" or price <= quote then
		return price
	end
	R.Check(R.Int(quote, 0, Config.MaxCash) and price <= quote * 1.05, "The price changed with your income: " .. price .. " Coins now. Check and open again")
	return quote
end

-- Opens per player in a short window (RAM only): a case takes about three seconds to reveal.
local recent: { [number]: { number } } = {}
F.RateWindow, F.RateLimit = 2, 4
local function rateLimited(userId: number): boolean
	local now = os.clock()
	local list = recent[userId]
	if not list then
		list = {}
		recent[userId] = list
	end
	while list[1] and now - list[1] > F.RateWindow do
		table.remove(list, 1)
	end
	if #list >= F.RateLimit then
		return true
	end
	table.insert(list, now)
	return false
end
Players.PlayerRemoving:Connect(function(player)
	recent[player.UserId] = nil
end)

-- Paid random policy of the profile owner (PaidRandomPolicy, cached per player).
local function policy(): any
	local ok, module = pcall(function()
		return require(script.Parent.Parent.PaidRandomPolicy)
	end)
	return ok and module or nil
end
local function paidAllowed(userId: any): boolean
	local player = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	local P = player and policy()
	return P ~= nil and P.Allowed(player) == true
end
-- Non-blocking read for the snapshot: allowed, known (a lookup starts when unknown or stale).
local function paidAllowedNow(userId: any): (boolean, boolean)
	local player = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	local P = player and policy()
	if not P then
		return false, true
	end
	local row = P.Cache[player.UserId]
	local fresh = row and os.clock() - row.At < (row.Ok and P.CacheSeconds or P.FailSeconds)
	if not fresh and not P.Pending[player.UserId] then
		task.spawn(P.Info, player)
	end
	if row then
		return row.PaidRandom == true, true
	end
	return false, false
end

-- Free credits from game rewards (other systems may call this inside their transaction).
function F.GrantCredits(p: any, caseId: string, n: number, paid: boolean?): number
	local case = E.CaseById[caseId]
	assert(case, "Unknown case")
	assert(int(n, 1, MAX_CREDITS), "Invalid credit amount")
	local eq = F.Ensure(p)
	local credit = eq.CaseCredits[caseId]
	if type(credit) ~= "table" then
		credit = { Free = 0, Paid = 0 }
		eq.CaseCredits[caseId] = credit
	end
	local key = paid and "Paid" or "Free"
	credit[key] = math.min(MAX_CREDITS, wholeOrZero(credit[key], MAX_CREDITS) + n)
	eq.Rev += 1
	return credit[key]
end

-- One piece as the client sees it.
local function view(entry: any): any
	local def = E.Def(entry.Id)
	return {
		Uid = entry.Uid,
		Id = entry.Id,
		Rarity = entry.Rarity,
		Roll = entry.Roll,
		Value = round4(E.Value(entry)),
		Stat = def and def.Stat or nil,
		DogUid = entry.DogUid,
		Slot = entry.Slot,
		Locked = entry.Locked,
		PaidRandom = entry.PaidRandom,
		CreatedAt = entry.CreatedAt,
	}
end

------------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------------
local function piece(R: any, bag: any, uid: any, what: string): any
	R.Check(type(uid) == "string" and #uid <= 64, "Choose " .. what)
	local entry = bag[uid]
	R.Check(type(entry) == "table", "That " .. what .. " is not in your bag")
	return entry
end

local function openCase(R, p, a, now, random)
	local case = type(a.Case) == "string" and E.CaseById[a.Case] or nil
	R.Check(case, "Unknown case")
	local pay = a.Pay
	R.Check(pay == "Cash" or pay == "Bones" or pay == "Credit", "Choose how to pay")
	local eq = F.Ensure(p)
	local bag = bagOf(eq, case.Kind)
	R.Check(count(bag) < E.Capacity[case.Kind], case.Kind == "Artifact" and "Your artifact bag is full: salvage some artifacts first"
		or "Your accessory bag is full: salvage some accessories first")
	R.Check(not rateLimited(p.UserId), "Opening too fast; wait a moment")
	local paid = false
	if pay == "Cash" then
		R.Check(type(case.Cash) == "table", "This case is not sold for Coins")
		local price = E.CashPrice(case, p, now)
		R.Check(R.Int(price, 1, Config.MaxCash), "This case is not sold for Coins")
		R.Pay(p, quoted(R, price, a.Quote), 0)
	elseif pay == "Bones" then
		R.Check(R.Int(case.Bones, 1, Config.MaxCash), "This case is not sold for Bones")
		R.Pay(p, 0, case.Bones)
	else
		local credit = eq.CaseCredits[case.Id]
		local free = type(credit) == "table" and wholeOrZero(credit.Free, MAX_CREDITS) or 0
		local owned = type(credit) == "table" and wholeOrZero(credit.Paid, MAX_CREDITS) or 0
		R.Check(free + owned > 0, "You have no keys for this case")
		if free > 0 then
			credit.Free = free - 1
		else
			-- Roblox policy: paid random rewards only where allowed. The keys are never lost.
			R.Check(paidAllowed(p.UserId), "Paid random items are unavailable for this account; your keys are kept")
			credit.Paid = owned - 1
			paid = true
		end
	end
	local streak = wholeOrZero(eq.Pity[case.Id], MAX_INT)
	local rarity, forced = F.RollRarity(case, streak, random)
	local def = pick(E.Pool(case)[rarity], random)
	local entry = {
		Uid = newUid(p, eq),
		Id = def.Id,
		Rarity = def.Rarity,
		Roll = round4(random()),
		CreatedAt = now,
		Origin = case.Id,
		PaidRandom = paid or nil,
	}
	bag[entry.Uid] = entry
	local floor = case.Pity and E.RarityIndex[case.Pity.Rarity]
	if floor and E.RarityIndex[rarity] >= floor then
		eq.Pity[case.Id] = 0
	else
		eq.Pity[case.Id] = streak + 1
	end
	local new = eq.Seen[def.Id] ~= true
	eq.Seen[def.Id] = true
	eq.Opened[case.Id] = wholeOrZero(eq.Opened[case.Id], MAX_INT) + 1
	eq.Rev += 1
	local opened = view(entry)
	opened.Kind = case.Kind
	opened.New = new
	opened.Pity = forced or nil
	return def.Name .. " (" .. def.Rarity .. ")", {
		Opened = opened,
		Reel = reel(case, def, random),
		WinIndex = WIN_INDEX,
		Case = case.Id,
		Pay = pay,
	}
end

local function equipArtifact(R, p, a)
	local eq = F.Ensure(p)
	local art = piece(R, eq.Artifacts, a.Uid, "artifact")
	R.Check(E.ArtifactById[art.Id] ~= nil, "This artifact can no longer be used")
	local dog = R.Dog(p, a.DogUid, false)
	local slots = dogSlots(dog)
	R.Check(R.Int(a.Slot, 1, slots), slots == 1 and "This dog has 1 artifact slot" or ("This dog has " .. slots .. " artifact slots"))
	if art.DogUid == dog.DogUid and art.Slot == a.Slot then
		return "Already equipped", { Equipped = { Uid = art.Uid, DogUid = dog.DogUid, Slot = a.Slot } }
	end
	local replaced = nil
	for _, other in pairs(eq.Artifacts) do
		if other ~= art and other.DogUid == dog.DogUid and other.Slot == a.Slot then
			other.DogUid, other.Slot = nil, nil
			replaced = other.Uid
		end
	end
	local movedFrom = art.DogUid ~= dog.DogUid and art.DogUid or nil
	art.DogUid, art.Slot = dog.DogUid, a.Slot
	eq.Rev += 1
	return replaced and "Artifact replaced" or "Artifact equipped", {
		Equipped = { Uid = art.Uid, DogUid = dog.DogUid, Slot = a.Slot },
		Replaced = replaced,
		MovedFrom = movedFrom,
	}
end

local function unequipArtifact(R, p, a)
	local eq = F.Ensure(p)
	local art = piece(R, eq.Artifacts, a.Uid, "artifact")
	if art.DogUid == nil and art.Slot == nil then
		return "Already in your bag"
	end
	art.DogUid, art.Slot = nil, nil
	eq.Rev += 1
	return "Artifact returned to your bag"
end

local function equipAccessory(R, p, a)
	local eq = F.Ensure(p)
	local acc = piece(R, eq.Accessories, a.Uid, "accessory")
	local def = E.AccessoryById[acc.Id]
	R.Check(def ~= nil, "This accessory can no longer be used")
	if acc.Slot == def.Slot then
		return "Already equipped"
	end
	local replaced = nil
	for _, other in pairs(eq.Accessories) do
		if other ~= acc and other.Slot == def.Slot then
			other.Slot = nil
			replaced = other.Uid
		end
	end
	acc.Slot = def.Slot
	eq.Rev += 1
	return "Accessory equipped", { Equipped = { Uid = acc.Uid, Slot = def.Slot }, Replaced = replaced }
end

local function unequipAccessory(R, p, a)
	local eq = F.Ensure(p)
	R.Check(type(a.Slot) == "string" and E.SlotInfo[a.Slot] ~= nil, "Choose a slot")
	local found = false
	for _, acc in pairs(eq.Accessories) do
		if acc.Slot == a.Slot then
			acc.Slot = nil
			found = true
		end
	end
	R.Check(found, "Nothing is equipped there")
	eq.Rev += 1
	return "Accessory taken off"
end

local function salvage(R, p, a)
	local eq = F.Ensure(p)
	local uids = a.Uids
	R.Check(type(uids) == "table", "Choose pieces to salvage")
	local list, seen = {}, {}
	for i, uid in ipairs(uids) do
		R.Check(i <= E.MaxSalvageBatch, "Salvage at most " .. E.MaxSalvageBatch .. " pieces at once")
		R.Check(type(uid) == "string" and #uid <= 64 and not seen[uid], "Invalid selection")
		seen[uid] = true
		local entry = eq.Artifacts[uid] or eq.Accessories[uid]
		R.Check(type(entry) == "table", "That piece is not in your bag")
		R.Check(entry.Locked ~= true, "Unlock " .. ((E.Def(entry.Id) or {}).Name or "this piece") .. " before salvaging it")
		R.Check(entry.DogUid == nil and entry.Slot == nil, "Take " .. ((E.Def(entry.Id) or {}).Name or "this piece") .. " off before salvaging it")
		table.insert(list, entry)
	end
	R.Check(#list > 0 and #list == count(uids), "Choose pieces to salvage")
	local bones = 0
	for _, entry in ipairs(list) do
		bones += E.Salvage[entry.Rarity] or E.Salvage.Common
		eq.Artifacts[entry.Uid] = nil
		eq.Accessories[entry.Uid] = nil
	end
	p.Bones = math.min(Config.MaxCash, (tonumber(p.Bones) or 0) + bones)
	eq.Rev += 1
	return "Salvaged " .. #list .. (#list == 1 and " piece" or " pieces") .. " for " .. bones .. " Bones", { Bones = bones, Count = #list }
end

local function lock(R, p, a)
	local eq = F.Ensure(p)
	R.Check(type(a.Uid) == "string" and #a.Uid <= 64, "Choose a piece")
	local entry = eq.Artifacts[a.Uid] or eq.Accessories[a.Uid]
	R.Check(type(entry) == "table", "That piece is not in your bag")
	R.Check(type(a.Enabled) == "boolean", "Invalid toggle")
	entry.Locked = a.Enabled or nil
	eq.Rev += 1
	return a.Enabled and "Locked: it cannot be salvaged" or "Unlocked"
end

local handlers = {
	EquipmentOpenCase = openCase,
	EquipArtifact = equipArtifact,
	UnequipArtifact = unequipArtifact,
	EquipAccessory = equipAccessory,
	UnequipAccessory = unequipAccessory,
	SalvageEquipment = salvage,
	LockEquipment = lock,
}
F.Actions = handlers

function F.Action(R, p, action, a, now, random)
	local handler = handlers[action]
	if not handler then
		return nil
	end
	R.Check(type(a) == "table", "Invalid request")
	return handler(R, p, a, now, random)
end

------------------------------------------------------------------------------------------------
-- Snapshot: snapshot.Features.Equipment
------------------------------------------------------------------------------------------------
function F.Snapshot(_R, p, out, now)
	local eq = type(p.Equipment) == "table" and p.Equipment or F.New()
	local artifacts, accessories, byDog, equipped = {}, {}, {}, {}
	for _, entry in pairs(type(eq.Artifacts) == "table" and eq.Artifacts or {}) do
		if type(entry) == "table" then
			table.insert(artifacts, view(entry))
			if type(entry.DogUid) == "string" then
				byDog[entry.DogUid] = byDog[entry.DogUid] or {}
				table.insert(byDog[entry.DogUid], entry.Uid)
			end
		end
	end
	for _, entry in pairs(type(eq.Accessories) == "table" and eq.Accessories or {}) do
		if type(entry) == "table" then
			table.insert(accessories, view(entry))
			if type(entry.Slot) == "string" then
				equipped[entry.Slot] = entry.Uid
			end
		end
	end
	local function order(x, y)
		local rx, ry = E.RarityIndex[x.Rarity] or 0, E.RarityIndex[y.Rarity] or 0
		if rx ~= ry then
			return rx > ry
		end
		if x.Value ~= y.Value then
			return x.Value > y.Value
		end
		return tostring(x.Uid) < tostring(y.Uid)
	end
	table.sort(artifacts, order)
	table.sort(accessories, order)
	local credits = {}
	for caseId, credit in pairs(type(eq.CaseCredits) == "table" and eq.CaseCredits or {}) do
		if type(credit) == "table" then
			credits[caseId] = { Free = wholeOrZero(credit.Free, MAX_CREDITS), Paid = wholeOrZero(credit.Paid, MAX_CREDITS) }
		end
	end
	local allowed, known = paidAllowedNow(p.UserId)
	local cases = {}
	for _, case in ipairs(E.Cases) do
		local products = {}
		for _, product in ipairs(E.Products) do
			if product.Case == case.Id and product.Enabled == true and int(product.Id, 1, MAX_INT) then
				table.insert(products, { Key = product.Key, Count = product.Count, ProductId = product.Id, Name = product.Name, Robux = product.Robux })
			end
		end
		local pity = type(eq.Pity) == "table" and wholeOrZero(eq.Pity[case.Id], MAX_INT) or 0
		table.insert(cases, {
			Id = case.Id,
			Kind = case.Kind,
			Cash = E.CashPrice(case, p, now),
			Bones = case.Bones,
			Robux = case.Robux == true,
			Credits = credits[case.Id] or { Free = 0, Paid = 0 },
			Pity = case.Pity and { Rarity = case.Pity.Rarity, Opens = case.Pity.Opens, Count = pity } or nil,
			Odds = E.Odds(case),
			Products = products,
			Opened = type(eq.Opened) == "table" and wholeOrZero(eq.Opened[case.Id], MAX_INT) or 0,
		})
	end
	local slots = {}
	for rank, n in ipairs(E.DogSlotsByRank) do
		slots[E.DogRarities[rank]] = n
	end
	out.Equipment = {
		Version = E.Version,
		Artifacts = artifacts,
		Accessories = accessories,
		CaseCredits = credits,
		Cases = cases,
		PaidAllowed = allowed,
		PaidKnown = known,
		DogSlots = slots,
		Capacity = { Artifact = E.Capacity.Artifact, Accessory = E.Capacity.Accessory },
		Equipped = equipped,
		ByDog = byDog,
		Rev = tonumber(eq.Rev) or 0,
	}
end

------------------------------------------------------------------------------------------------
-- Robux case keys (PurchaseService.RegisterCatalog through the feature catalog hook)
------------------------------------------------------------------------------------------------
-- Inside PurchaseService's single receipt transaction: credits only (opening is a separate,
-- policy-gated action). A completed purchase always credits, whatever the policy is today.
function F.GrantProduct(p: any, product: any, _context: any): any
	local case = E.CaseById[product.Case]
	assert(case and int(product.Count, 1, 1000), "Invalid case product")
	local total = F.GrantCredits(p, case.Id, product.Count, true)
	return {
		Message = product.Count .. (product.Count == 1 and " key" or " keys") .. " for " .. case.Name .. " added · open it in the EQUIPMENT shop",
		Case = case.Id,
		Count = product.Count,
		Total = total,
	}
end
function F.AfterProduct(runtime: any, player: any, _product: any, result: any)
	if type(result) ~= "table" then
		return
	end
	local presentation = RS:FindFirstChild("RewardPresentation")
	if presentation and player.Parent and result.Message then
		presentation:FireClient(player, { Cue = "Reward", Message = result.Message })
	end
	if runtime and type(runtime.PushTo) == "function" then
		runtime.PushTo(player, "EquipmentCredits", { Case = result.Case, Count = result.Count })
	end
end
-- Called by PurchaseService with its RegisterCatalog (rows with Id = 0 are never indexed).
function F.Catalogs(register: any)
	register({
		Kind = "EquipmentCases",
		Source = "EquipmentDefinitions",
		Rows = function()
			return E.Products
		end,
		Sold = function(row)
			return row.Enabled == true
		end,
	}, { Record = "EquipmentCases", Grant = F.GrantProduct, After = F.AfterProduct })
end

return F
