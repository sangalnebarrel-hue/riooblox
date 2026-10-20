-- LUCKY DUST (feature module, see Economy.FeatureRegistry; docs/halloween2/DESIGN.md §14): dismantle Lucky Blocks into
-- Lucky Dust and forge new blocks from it at the DUST FORGE. Numbers: DogEconomy.LuckyDustConfig; maths (values,
-- yields, forge costs, eligibility, selection): Halloween.DustRules (pure). Lucky Dust is the stored resource
-- p.Resources.LuckyDust (DogEconomy.Resources), projected as the player attribute LuckyDust by Runtime.Project.
--
-- Actions (DogEconomyRequest -> Engine:Action -> Rules.Action -> here). Engine:Action runs them in one profile
-- transaction keyed by the request id, so a retried request answers the same reply (Transactions receipts):
--   DismantleQuote {Uids = {uid, ...}, Credits = {[tier] = n}?}   (at most MaxBatch blocks in total)
--       -> message, {Token, Total, Rows = {{Uid?, Tier, Count, Dust, Bonus, Credit?}}, NeedsConfirm, Candy, Count,
--          Expires (server unix time), TTL (seconds)}
--       Stored blocks the player owns that are not opening, and legacy credit stacks (p.LuckyCredits). PaidRandom
--       blocks and credits are allowed: the conversion is a fixed number, nothing random comes out. Refused during a
--       trade session. The quote (token, per-block fingerprints, totals) lives in server RAM for QuoteSeconds.
--   Dismantle {Token, Confirm?} -> message, {Dust, Candy, Count, Balance}
--       Confirm = true is required when the quote holds a block of rank >= ConfirmRank (Legendary, Mythic, Secret and
--       both pumpkin tiers). Every block is checked again against its fingerprint, then removed; the dust is added
--       and, for pumpkin tiers while the Halloween event is on, candy through Features.Halloween.AddCandy (no souls,
--       no quest progress). A token is single-use; its result is kept in p.LuckyDust.Receipts, so the same token
--       sent again answers the same result instead of failing or paying twice.
--   DustForge {Tier, Count?} -> message, {Tier, Count, Cost, Uids, Balance}
--       Common..Legendary for DustRules.ForgeCost dust each, into Lucky Block storage through
--       LuckyLifecycle.AddStored (origin "DustForge", never PaidRandom) within the storage cap (60).
--
-- Saved data (additive; created by the first dismantle / forge, healed by a pcall'd Shape, unknown keys kept):
--   p.LuckyDust = {Version = 1, Dismantled = n (blocks), Earned = n (dust from dismantling), Forged = n (blocks),
--     Spent = n (dust at the forge), Candy = n, Receipts = {[token] = {Dust, Candy, Count, At}}, ReceiptOrder = {token}}
-- Snapshot: snapshot.Features.LuckyDust = {Dust, Dismantled, Earned, Forged, Spent, Candy, Salvage, Capacity}.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local Resources = require(RS.DogEconomy.Resources)
local Lifecycle = require(RS.LuckyLifecycleConfig)
local Dust = require(RS.Halloween.DustRules)
local Config = Dust.Config

local F = { Name = "LuckyDust", Order = 80 }
F.Rules = Dust

local MAX_INT = 9007199254740990
local KIND = "LuckyDust"

-- Quotes in server RAM: [userId] = {Token, Expires, Uids, Credits, Prints, Total, Candy, Count, NeedsConfirm}.
F.Quotes = {} :: { [number]: any }

------------------------------------------------------------------------------------------------
-- Hooks into other server modules (reached lazily at call time; tests replace them)
------------------------------------------------------------------------------------------------
-- True while the player is in a trade session (Engine.TradeByUser, like the Shelter and the Lab).
function F.TradeBusy(userId: number): boolean
	local ok, busy = pcall(function()
		local runtime = require(script.Parent.Parent.Runtime) :: any
		return runtime.Engine ~= nil and runtime.Engine.TradeByUser[userId] ~= nil
	end)
	return ok and busy == true
end

-- True while LuckyLifecycle is opening that block.
function F.Opening(uid: string): boolean
	local ok, opening = pcall(function()
		local lifecycle = require(script.Parent.Parent.LuckyLifecycle) :: any
		return lifecycle.Opening and lifecycle.Opening[uid]
	end)
	return ok and opening ~= nil and opening ~= false
end

-- The Halloween event is on (pumpkin dismantles add candy only then).
function F.EventOn(): boolean
	local ok, on = pcall(function()
		-- FindFirstChild, never WaitForChild: this runs inside a profile transaction and must not yield.
		local folder = RS:FindFirstChild("Halloween")
		local module = folder and folder:FindFirstChild("Shared")
		return module ~= nil and (require(module) :: any).Enabled()
	end)
	return ok and on == true
end

local function lifecycle(): any
	return require(script.Parent.Parent.LuckyLifecycle)
end

local function feature(R: any, name: string): any
	local registry = R and R.Features
	for _, f in ipairs(registry and registry.Modules or {}) do
		if f.Name == name then
			return f
		end
	end
	return nil
end

-- Adds Halloween candy through Features.Halloween.AddCandy; returns what was added (0 when the event is off or the
-- Halloween feature is missing). Never fails the dismantle.
function F.GrantCandy(R: any, p: any, n: number): number
	n = math.floor(tonumber(n) or 0)
	if n <= 0 or not F.EventOn() then
		return 0
	end
	local hw = feature(R, "Halloween")
	if not (hw and type(hw.AddCandy) == "function") then
		return 0
	end
	local ok, added = pcall(hw.AddCandy, p, n)
	return ok and math.max(0, math.floor(tonumber(added) or 0)) or 0
end

------------------------------------------------------------------------------------------------
-- Saved data
------------------------------------------------------------------------------------------------
local COUNTERS = { "Dismantled", "Earned", "Forged", "Spent", "Candy" }

local function whole(v: any): number
	if type(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return math.min(math.floor(v), MAX_INT)
end

local function isToken(v: any): boolean
	return type(v) == "string" and #v == 32 and v:match("^%x+$") ~= nil
end

-- Creates / heals p.LuckyDust in place; never throws on any saved value; keeps unknown keys.
function F.Shape(p: any): any
	local d = p.LuckyDust
	if type(d) ~= "table" then
		d = {}
		p.LuckyDust = d
	end
	d.Version = 1
	for _, key in ipairs(COUNTERS) do
		d[key] = whole(d[key])
	end
	if type(d.Receipts) ~= "table" then
		d.Receipts = {}
	end
	local order, kept = {}, {}
	for _, token in ipairs(type(d.ReceiptOrder) == "table" and d.ReceiptOrder or {}) do
		if isToken(token) and not kept[token] and type(d.Receipts[token]) == "table" then
			kept[token] = true
			table.insert(order, token)
		end
	end
	while #order > Config.ReceiptCount do
		table.remove(order, 1)
	end
	local receipts = {}
	for _, token in ipairs(order) do
		local r = d.Receipts[token]
		receipts[token] = { Dust = whole(r.Dust), Candy = whole(r.Candy), Count = whole(r.Count), At = whole(r.At) }
	end
	d.Receipts, d.ReceiptOrder = receipts, order
	return d
end

function F.Normalize(_R: any, p: any, _now: number)
	if p.LuckyDust ~= nil then
		local ok = pcall(F.Shape, p)
		if not ok then
			p.LuckyDust = nil -- never let a corrupt sub-table break the economy tick
		end
	end
end

-- Nil-safe; checks only the shape the actions keep (Normalize heals everything else).
function F.Validate(R: any, p: any)
	local d = p.LuckyDust
	if d == nil then
		return
	end
	R.Check(type(d) == "table", "Invalid Lucky Dust data")
	R.Check(d.Receipts == nil or type(d.Receipts) == "table", "Invalid Lucky Dust data")
end

local function remember(d: any, token: string, receipt: any)
	if d.Receipts[token] == nil then
		table.insert(d.ReceiptOrder, token)
	end
	d.Receipts[token] = receipt
	while #d.ReceiptOrder > Config.ReceiptCount do
		local old = table.remove(d.ReceiptOrder, 1)
		d.Receipts[old] = nil
	end
end

------------------------------------------------------------------------------------------------
-- Messages (English; Russian in ReplicatedStorage.Localization.LuckyDust)
------------------------------------------------------------------------------------------------
local function blocksWord(n: number): string
	return n == 1 and "block" or "blocks"
end

local function dismantledMessage(count: number, dust: number, candy: number): string
	local text = string.format("Dismantled %d %s: +%d Lucky Dust", count, blocksWord(count), dust)
	if candy > 0 then
		text ..= string.format(" · +%d Candy", candy)
	end
	return text
end

------------------------------------------------------------------------------------------------
-- Quote / dismantle
------------------------------------------------------------------------------------------------
local function credits(p: any, tier: string): number
	local t = type(p.LuckyCredits) == "table" and p.LuckyCredits or {}
	return whole(t[tier])
end

-- Values of a selection with the rules in force now: {Rows, Total, Candy, Count, NeedsConfirm}.
local function price(p: any, uids: { string }, credit: { [string]: number }): any
	local entries, rows = {}, {}
	for _, uid in ipairs(uids) do
		local b = p.OwnedBlocks[uid]
		local tier = Dust.Canonical(b.Tier) :: string
		table.insert(entries, { Tier = tier, Count = 1 })
		table.insert(rows, { Uid = uid, Tier = tier, Count = 1, Dust = Dust.Yield(tier), Bonus = Dust.EventBonus(tier) })
	end
	local tiers = {}
	for tier in pairs(credit) do
		table.insert(tiers, tier)
	end
	table.sort(tiers)
	for _, saved in ipairs(tiers) do
		local n = credit[saved]
		local tier = Dust.Canonical(saved) :: string
		table.insert(entries, { Tier = tier, Count = n })
		table.insert(rows, { Tier = tier, Count = n, Dust = Dust.Yield(tier) * n, Bonus = Dust.EventBonus(tier) * n, Credit = true })
	end
	local sum = Dust.Summarize(entries)
	local event = sum.Candy > 0 and F.EventOn()
	if not event then
		for _, row in ipairs(rows) do
			row.Bonus = 0
		end
	end
	return { Rows = rows, Total = sum.Total, Candy = event and sum.Candy or 0, Count = sum.Count, NeedsConfirm = sum.NeedsConfirm }
end

-- Every block of a request must still be dismantlable right now.
local function checkBlock(R: any, p: any, uid: string)
	local ok, why = Dust.Eligible(p.OwnedBlocks[uid], p.UserId, uid)
	R.Check(ok, why)
	R.Check(not F.Opening(uid), "That block is opening")
end

local function prune(now: number)
	for userId, q in pairs(F.Quotes) do
		if q.Expires < now then
			F.Quotes[userId] = nil
		end
	end
end

local function quote(R: any, p: any, a: any, now: number)
	R.Check(not F.TradeBusy(p.UserId), "Finish your trade first")
	lifecycle().Normalize(p)
	local list = a.Uids
	if list == nil then
		list = {}
	end
	R.Check(type(list) == "table", "Choose blocks to dismantle")
	local entries = 0
	for _ in pairs(list) do
		entries += 1
	end
	R.Check(entries == #list, "Choose blocks to dismantle")
	local uids, seen = {}, {}
	for _, uid in ipairs(list) do
		R.Check(isToken(uid) and not seen[uid], "Choose blocks to dismantle")
		seen[uid] = true
		table.insert(uids, uid)
	end
	local credit, creditCount = {}, 0
	if a.Credits ~= nil then
		R.Check(type(a.Credits) == "table", "Choose blocks to dismantle")
		for tier, n in pairs(a.Credits) do
			R.Check(type(tier) == "string" and #tier <= 40 and R.Int(n, 1, Config.MaxBatch), "Choose blocks to dismantle")
			R.Check(Dust.Yield(tier) > 0, "This block cannot be dismantled")
			R.Check(credits(p, tier) >= n, "You do not have that many blocks of this tier")
			credit[tier] = n
			creditCount += n
		end
	end
	local count = #uids + creditCount
	R.Check(count >= 1, "Choose blocks to dismantle")
	R.Check(count <= Config.MaxBatch, string.format("Dismantle at most %d blocks at once", Config.MaxBatch))
	local prints = {}
	for _, uid in ipairs(uids) do
		checkBlock(R, p, uid)
		prints[uid] = Dust.Fingerprint(p.OwnedBlocks[uid])
	end
	local priced = price(p, uids, credit)
	R.Check(priced.Total > 0, "This block cannot be dismantled")
	prune(now)
	local token = (Http:GenerateGUID(false):gsub("-", ""))
	F.Quotes[p.UserId] = {
		Token = token,
		Expires = now + Config.QuoteSeconds,
		Uids = uids,
		Credits = credit,
		Prints = prints,
		Total = priced.Total,
		Candy = priced.Candy,
		Count = priced.Count,
		NeedsConfirm = priced.NeedsConfirm,
	}
	local message = string.format("Dismantle %d %s for %d Lucky Dust", priced.Count, blocksWord(priced.Count), priced.Total)
	return message, {
		Token = token,
		Total = priced.Total,
		Rows = priced.Rows,
		NeedsConfirm = priced.NeedsConfirm,
		Candy = priced.Candy,
		Count = priced.Count,
		Expires = now + Config.QuoteSeconds,
		TTL = Config.QuoteSeconds,
	}
end

local function dismantle(R: any, p: any, a: any, now: number)
	local token = a.Token
	R.Check(isToken(token), "Quote expired; review the blocks again")
	-- The same token again (a lost reply, a double tap): the saved result, nothing paid twice.
	local saved = type(p.LuckyDust) == "table" and type(p.LuckyDust.Receipts) == "table" and p.LuckyDust.Receipts[token]
	if type(saved) == "table" then
		local balance = Resources.Get(p, KIND)
		return dismantledMessage(whole(saved.Count), whole(saved.Dust), whole(saved.Candy)),
			{ Dust = whole(saved.Dust), Candy = whole(saved.Candy), Count = whole(saved.Count), Balance = balance, Repeat = true }
	end
	local q = F.Quotes[p.UserId]
	R.Check(q ~= nil and q.Token == token and q.Expires >= now, "Quote expired; review the blocks again")
	R.Check(not q.NeedsConfirm or a.Confirm == true, "Hold to confirm: Legendary and rarer blocks need a confirmation")
	R.Check(not F.TradeBusy(p.UserId), "Finish your trade first")
	lifecycle().Normalize(p)
	for _, uid in ipairs(q.Uids) do
		R.Check(p.OwnedBlocks[uid] ~= nil, "Blocks changed; review them again")
		checkBlock(R, p, uid)
		R.Check(Dust.Fingerprint(p.OwnedBlocks[uid]) == q.Prints[uid], "Blocks changed; review them again")
	end
	for tier, n in pairs(q.Credits) do
		R.Check(credits(p, tier) >= n, "Blocks changed; review them again")
	end
	local priced = price(p, q.Uids, q.Credits)
	R.Check(priced.Total == q.Total and priced.Candy == q.Candy and priced.Count == q.Count, "Dust values changed; review the blocks again")
	R.Check(Resources.Get(p, KIND) + priced.Total <= Resources.Kinds[KIND].Max, "Your Lucky Dust is full")
	-- Everything checked: remove the blocks, pay the dust (and the event candy).
	for _, uid in ipairs(q.Uids) do
		p.OwnedBlocks[uid] = nil
	end
	for tier, n in pairs(q.Credits) do
		p.LuckyCredits[tier] = credits(p, tier) - n
	end
	Resources.Add(p, KIND, priced.Total)
	local candy = F.GrantCandy(R, p, priced.Candy)
	local d = F.Shape(p)
	d.Dismantled = math.min(MAX_INT, d.Dismantled + priced.Count)
	d.Earned = math.min(MAX_INT, d.Earned + priced.Total)
	d.Candy = math.min(MAX_INT, d.Candy + candy)
	remember(d, token, { Dust = priced.Total, Candy = candy, Count = priced.Count, At = now })
	F.Quotes[p.UserId] = nil
	return dismantledMessage(priced.Count, priced.Total, candy),
		{ Dust = priced.Total, Candy = candy, Count = priced.Count, Balance = Resources.Get(p, KIND) }
end

------------------------------------------------------------------------------------------------
-- Forge
------------------------------------------------------------------------------------------------
local function forge(R: any, p: any, a: any, _now: number)
	local tier = a.Tier
	R.Check(type(tier) == "string" and Dust.CanForge(tier), "This block cannot be forged")
	local count = a.Count
	if count == nil then
		count = 1
	end
	R.Check(R.Int(count, 1, Config.ForgeMaxCount), "Choose how many blocks to forge")
	local L = lifecycle()
	L.Normalize(p)
	R.Check(R.Count(p.OwnedBlocks) + count <= (Lifecycle.InventoryCapacity or 60), "Your Lucky Block storage is full")
	local cost = (Dust.ForgeCost(tier) :: number) * count
	R.Check(Resources.Get(p, KIND) >= cost, "Not enough Lucky Dust")
	Resources.Spend(p, { [KIND] = cost })
	local uids = L.AddStored(p, tier, count, "DustForge", false)
	local d = F.Shape(p)
	d.Forged = math.min(MAX_INT, d.Forged + count)
	d.Spent = math.min(MAX_INT, d.Spent + cost)
	local article = tier:match("^[AEIOU]") and "an" or "a"
	local message = count == 1 and string.format("Forged %s %s Lucky Block", article, tier)
		or string.format("Forged %d %s Lucky Blocks", count, tier)
	return message, { Tier = tier, Count = count, Cost = cost, Uids = uids, Balance = Resources.Get(p, KIND) }
end

local handlers = {
	DismantleQuote = quote,
	Dismantle = dismantle,
	DustForge = forge,
}
F.Actions = handlers

function F.Action(R: any, p: any, action: string, a: any, now: number, _random: any)
	local handler = handlers[action]
	if not handler then
		return nil
	end
	R.Check(type(a) == "table", "Invalid request")
	return handler(R, p, a, now)
end

------------------------------------------------------------------------------------------------
-- Snapshot: snapshot.Features.LuckyDust
------------------------------------------------------------------------------------------------
function F.Snapshot(_R: any, p: any, view: any, _now: number)
	local d = type(p.LuckyDust) == "table" and p.LuckyDust or {}
	view.LuckyDust = {
		Dust = Resources.Get(p, KIND),
		Dismantled = whole(d.Dismantled),
		Earned = whole(d.Earned),
		Forged = whole(d.Forged),
		Spent = whole(d.Spent),
		Candy = whole(d.Candy),
		Salvage = Dust.Salvage(),
		Capacity = Lifecycle.InventoryCapacity or 60,
	}
end

-- Quotes of players who left are dropped (they expire anyway).
Players.PlayerRemoving:Connect(function(player)
	F.Quotes[player.UserId] = nil
end)

return F
