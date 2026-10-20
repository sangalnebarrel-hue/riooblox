--!nocheck
-- LUCKY DUST (dismantle Lucky Blocks, DUST FORGE): lune run tests/lucky_dust.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): Halloween.DustRules (values, yields, forge costs,
-- confirm rule, selection), the Features.LuckyDust feature through Rules.Action / Normalize / Validate / Snapshot
-- (eligibility, quote tokens, fingerprints, credits, candy, the storage cap) and, for the request-id receipts, the
-- real Engine + Transactions on an in-memory store. Also checks the Russian dictionary of the server answers and the
-- self-localized strings the bag adds.
local fs = require("@lune/fs")
local L = require("./lib/economy_env")

L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end, Current = function() return 1 end }
local R = L.Require("ServerScriptService.Economy.Rules")
local D = L.Require("ReplicatedStorage.Halloween.DustRules")
local F = L.Require("ServerScriptService.Economy.Features.LuckyDust")
local Blocks = L.Require("ReplicatedStorage.LuckyBlockConfig")
local Resources = L.Require("ReplicatedStorage.DogEconomy.Resources")
local Lifecycle = L.Require("ReplicatedStorage.LuckyLifecycleConfig")
local Halloween = L.Require("ServerScriptService.Economy.Features.Halloween")
local C = D.Config

local passed, failed = 0, 0
local NOW = 1760000000
local function test(name, fn)
	L.Time = NOW
	local salvage = D.Config.Salvage
	local ok, err = pcall(fn)
	D.Config.Salvage = salvage -- a failed balance test never leaks its salvage into the next one
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end
local function truthy(v, msg)
	if not v then error(msg or "expected truthy", 2) end
end
local function count(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

-- Hooks the feature reaches at call time (trade sessions, opening blocks, the Halloween switch).
local busy, opening, eventOn = {}, {}, true
F.TradeBusy = function(userId) return busy[userId] == true end
F.Opening = function(uid) return opening[uid] == true end
F.EventOn = function() return eventOn end
local function reset()
	busy, opening, eventOn = {}, {}, true
	table.clear(F.Quotes)
end

local uidN = 0
local function uid()
	uidN += 1
	return string.format("%032x", 0xD000 + uidN)
end
local function block(p, tier, extra)
	local id = uid()
	local b = { Uid = id, OwnerUserId = p.UserId, Tier = tier, State = "Stored", PurchasedAt = NOW - 1000 + uidN, PaidRandom = false, Origin = "Reward" }
	for k, v in pairs(extra or {}) do b[k] = v end
	p.OwnedBlocks[id] = b
	return id, b
end
local function profile()
	local p = R.Normalize(R.Profile(1, NOW), 1, NOW)
	p.OwnedBlocks = p.OwnedBlocks or {}
	p.LuckyCredits = p.LuckyCredits or {}
	return p
end
local function action(p, name, args)
	return R.Action(p, name, args, NOW, function() return 0.5 end)
end
-- Runs an action on a copy (like the transaction does): ok, message/err, extra, copy.
local function try(p, name, args)
	local copy = R.Copy(p)
	local ok, message, extra = pcall(action, copy, name, args)
	if ok then
		R.Validate(copy)
	end
	return ok, message, extra, copy
end
local function fails(p, name, args, needle)
	local ok, err = try(p, name, args)
	truthy(not ok, name .. " should fail with " .. needle)
	truthy(string.find(tostring(err), needle, 1, true), "expected '" .. needle .. "' got '" .. tostring(err) .. "'")
end
local function dust(p)
	return Resources.Get(p, "LuckyDust")
end

-- VALUES ----------------------------------------------------------------------------------------------------------
test("values: computed values equal the frozen reference table", function()
	for _, tier in ipairs(D.Order) do
		local ref = D.Reference[tier]
		truthy(ref, "reference for " .. tier)
		eq(D.BlockValue(tier), ref.Value, tier .. " value")
		eq(D.Yield(tier), ref.Yield, tier .. " yield")
		eq(D.ForgeCost(tier), ref.Forge, tier .. " forge cost")
		eq(D.EventBonus(tier), ref.Candy or 0, tier .. " candy")
		if ref.Price then
			eq(Blocks.ConveyorPrices[tier], ref.Price, tier .. " price")
			eq(D.Contents(tier), ref.EV, tier .. " EV")
			eq(ref.Value, math.min(ref.Price, ref.EV), tier .. " value = min(price, EV)")
		else
			eq(Blocks.EventTiers[tier].TradeValue, ref.TradeValue, tier .. " trade value")
		end
	end
	-- The design numbers (DESIGN §14): Common 5 000 ... Secret min(45M, 10.38M), pumpkins by TradeValue.
	eq(D.BlockValue("Common"), 5000)
	eq(D.BlockValue("Secret"), 10380000)
	eq(D.BlockValue("Pumpkin"), 600000)
	eq(D.BlockValue("Cursed Pumpkin"), 4000000)
	-- Legacy aliases are valued as their canonical tier; unknown tiers have no value.
	eq(D.BlockValue("Uncommon"), D.BlockValue("Rare"), "Uncommon = Rare")
	eq(D.BlockValue("Brainrot God"), D.BlockValue("Mythic"), "Brainrot God = Mythic")
	eq(D.BlockValue("Nope"), nil)
	eq(D.Yield("Nope"), 0)
	eq(D.Yield(nil), 0)
end)

test("yield: dismantling returns .20-.30 of a block's value at every allowed salvage", function()
	local saved = C.Salvage
	for _, salvage in ipairs({ C.Salvage, C.SalvageMin, C.SalvageMax }) do
		C.Salvage = salvage
		for _, tier in ipairs(D.Order) do
			local share = D.Yield(tier) * C.CoinsPerDust / D.BlockValue(tier)
			truthy(share >= 0.20 - 1e-9 and share <= 0.30 + 1e-9, string.format("%s at %.2f returns %.4f", tier, salvage, share))
		end
	end
	C.Salvage = saved
	truthy(C.Salvage >= 0.20 and C.Salvage <= 0.30, "configured salvage inside .20-.30")
	-- The config is clamped to the allowed range.
	C.Salvage = 0.9
	eq(D.Salvage(), C.SalvageMax, "clamped high")
	C.Salvage = 0.01
	eq(D.Salvage(), C.SalvageMin, "clamped low")
	C.Salvage = saved
	eq(D.Salvage(), 0.25, "default .25")
end)

test("no profitable loop: every dismantle -> forge cycle returns well under the value that went in", function()
	local saved = C.Salvage
	local best = 0
	for _, salvage in ipairs({ C.SalvageMin, saved, C.SalvageMax }) do
		C.Salvage = salvage
		for _, from in ipairs(D.Order) do
			for _, to in ipairs(C.Forgeable) do
				for _, n in ipairs({ 1, 7, 60, 1000 }) do
					local back = D.CycleReturn(from, to, n)
					truthy(back < 1, string.format("%s -> %s ×%d returns %.3f at salvage %.2f", from, to, n, back, salvage))
					truthy(back <= salvage * 1.75, string.format("%s -> %s ×%d returns %.3f > salvage × max(EV/value)", from, to, n, back))
					if salvage == saved then
						best = math.max(best, back)
					end
				end
			end
		end
	end
	C.Salvage = saved
	-- DESIGN §14: "any dismantle -> forge cycle returns ≤ 0.43× of the original value" (.25 × 1.727 = .4318).
	truthy(best <= 0.44 and best > 0.40, string.format("best cycle %.4f", best))
	-- Forging is never cheaper than the value of the block: dust bought with blocks always loses 75 %.
	for _, tier in ipairs(C.Forgeable) do
		truthy(D.ForgeCost(tier) * C.CoinsPerDust >= D.BlockValue(tier), tier .. " forge price covers the value")
		truthy(D.Yield(tier) < D.ForgeCost(tier), tier .. " one dismantle never forges the same block")
	end
end)

test("forge: Common..Legendary only, never Mythic, Secret or event tiers", function()
	for _, tier in ipairs({ "Common", "Rare", "Epic", "Legendary" }) do
		truthy(D.CanForge(tier), tier)
		eq(D.ForgeCost(tier), D.BlockValue(tier) / C.CoinsPerDust, tier .. " = value / 100")
	end
	for _, tier in ipairs({ "Mythic", "Secret", "Pumpkin", "Cursed Pumpkin", "Uncommon", "Nope" }) do
		truthy(not D.CanForge(tier), tier .. " not forgeable")
		eq(D.ForgeCost(tier), nil, tier)
	end
end)

test("confirm rule: rank >= 4 (Legendary, Mythic, Secret, both pumpkins) needs a confirmation", function()
	for tier, need in pairs({ Common = false, Rare = false, Epic = false, Legendary = true, Mythic = true, Secret = true, Pumpkin = true, ["Cursed Pumpkin"] = true, Uncommon = false, ["Brainrot God"] = true }) do
		eq(D.ConfirmNeeded(tier), need, tier)
	end
	eq(D.ConfirmNeeded("Nope"), false)
	local sum = D.Summarize({ { Tier = "Common", Count = 3 }, { Tier = "Pumpkin" } })
	eq(sum.Count, 4)
	eq(sum.Total, 3 * 12 + 1500)
	eq(sum.Candy, 15)
	eq(sum.NeedsConfirm, true)
	eq(D.Summarize({ { Tier = "Rare", Count = 2 } }).NeedsConfirm, false)
end)

test("event bonus: Pumpkin 15 candy, Cursed Pumpkin 50, others none", function()
	eq(D.EventBonus("Pumpkin"), 15)
	eq(D.EventBonus("Cursed Pumpkin"), 50)
	eq(D.EventBonus("Legendary"), 0)
	eq(D.EventBonus(nil), 0)
end)

test("select: stored blocks oldest first, then credits, at most max; never pads or other owners", function()
	reset()
	local p = profile()
	local old = block(p, "Common", { PurchasedAt = NOW - 5000 })
	local newer = block(p, "Common", { PurchasedAt = NOW - 10 })
	block(p, "Common", { State = "Placed", Slot = 1 })
	block(p, "Common", { OwnerUserId = 99 })
	local rare = block(p, "Rare")
	p.LuckyCredits.Common = 3
	p.LuckyCredits.Uncommon = 2
	local all = D.Select(p, { "Common", "Rare" }, 30)
	eq(all.Count, 2 + 3 + 1 + 2, "count")
	eq(all.Available, 8, "available")
	eq(all.Uids[1], old, "oldest first")
	eq(all.Uids[2], newer)
	eq(all.Uids[3], rare, "Rare after Common")
	eq(all.Credits.Common, 3)
	eq(all.Credits.Uncommon, 2, "legacy alias stacks count as Rare")
	eq(all.ByTier.Common, 5)
	eq(all.ByTier.Rare, 3)
	local one = D.Select(p, { "Common" }, 1)
	eq(one.Count, 1)
	eq(one.Uids[1], old)
	eq(count(one.Credits), 0)
	local some = D.Select(p, { "Common" }, 4)
	eq(#some.Uids, 2)
	eq(some.Credits.Common, 2, "credits fill the rest")
	eq(D.Select(nil, { "Common" }).Count, 0)
end)

-- ACTIONS ---------------------------------------------------------------------------------------------------------
test("quote + dismantle: stored blocks become Lucky Dust, blocks leave the profile", function()
	reset()
	local p = profile()
	local a = block(p, "Common")
	local b = block(p, "Rare", { PaidRandom = true }) -- paid random blocks convert like any other (fixed amount)
	local message, q = action(p, "DismantleQuote", { Uids = { a, b } })
	eq(message, "Dismantle 2 blocks for 67 Lucky Dust")
	eq(q.Total, 12 + 55)
	eq(q.Count, 2)
	eq(q.NeedsConfirm, false)
	eq(q.Candy, 0)
	eq(#q.Rows, 2)
	eq(q.Rows[1].Uid, a)
	eq(q.Rows[1].Dust, 12)
	eq(q.Rows[2].Tier, "Rare")
	eq(q.TTL, C.QuoteSeconds)
	truthy(type(q.Token) == "string" and #q.Token == 32, "token")
	local ok, msg, res, after = try(p, "Dismantle", { Token = q.Token })
	truthy(ok, tostring(msg))
	eq(msg, "Dismantled 2 blocks: +67 Lucky Dust")
	eq(res.Dust, 67)
	eq(res.Balance, 67)
	eq(dust(after), 67, "dust added")
	eq(after.OwnedBlocks[a], nil, "Common gone")
	eq(after.OwnedBlocks[b], nil, "Rare gone")
	eq(after.LuckyDust.Dismantled, 2)
	eq(after.LuckyDust.Earned, 67)
end)

test("eligibility: not owned, on a pad, opening, unknown, duplicates, too many, trade session", function()
	reset()
	local p = profile()
	local placed = block(p, "Epic", { State = "Placed", Slot = 1, ReadyAt = NOW + 30 })
	local ready = block(p, "Epic", { State = "Ready", Slot = 2, ReadyAt = NOW - 1 })
	local carried = block(p, "Epic", { State = "Carried" })
	local foreign = block(p, "Epic", { OwnerUserId = 77 })
	local good = block(p, "Common")
	fails(p, "DismantleQuote", { Uids = { placed } }, "Take that block off its Lucky pad first")
	fails(p, "DismantleQuote", { Uids = { ready } }, "Take that block off its Lucky pad first")
	fails(p, "DismantleQuote", { Uids = { carried } }, "Take that block off its Lucky pad first")
	fails(p, "DismantleQuote", { Uids = { foreign } }, "That block is not in your bag")
	fails(p, "DismantleQuote", { Uids = { string.rep("a", 32) } }, "That block is not in your bag")
	fails(p, "DismantleQuote", { Uids = { good, good } }, "Choose blocks to dismantle")
	fails(p, "DismantleQuote", { Uids = { "short" } }, "Choose blocks to dismantle")
	fails(p, "DismantleQuote", { Uids = {} }, "Choose blocks to dismantle")
	fails(p, "DismantleQuote", {}, "Choose blocks to dismantle")
	fails(p, "DismantleQuote", { Uids = "x" }, "Choose blocks to dismantle")
	-- An unknown tier cannot be valued.
	local odd = block(p, "Mystery")
	fails(p, "DismantleQuote", { Uids = { odd } }, "This block cannot be dismantled")
	-- Opening right now (LuckyLifecycle.Opening).
	opening[good] = true
	fails(p, "DismantleQuote", { Uids = { good } }, "That block is opening")
	opening[good] = nil
	-- Batch limit: 31 blocks.
	local many = {}
	for _ = 1, 31 do table.insert(many, (block(p, "Common"))) end
	fails(p, "DismantleQuote", { Uids = many }, "Dismantle at most 30 blocks at once")
	table.remove(many)
	local ok = try(p, "DismantleQuote", { Uids = many })
	truthy(ok, "30 blocks are fine")
	-- A trade session refuses both the quote and the dismantle.
	local _, q = action(p, "DismantleQuote", { Uids = { good } })
	busy[1] = true
	fails(p, "DismantleQuote", { Uids = { good } }, "Finish your trade first")
	fails(p, "Dismantle", { Token = q.Token }, "Finish your trade first")
	busy[1] = nil
	truthy((try(p, "Dismantle", { Token = q.Token })), "fine after the trade")
end)

test("confirm: a quote with Legendary+ (or a pumpkin) needs Confirm = true; Common/Rare/Epic do not", function()
	reset()
	local p = profile()
	local leg = block(p, "Legendary")
	local c = block(p, "Common")
	local _, q = action(p, "DismantleQuote", { Uids = { c, leg } })
	eq(q.NeedsConfirm, true)
	eq(q.Total, 12 + 1875)
	fails(p, "Dismantle", { Token = q.Token }, "Hold to confirm")
	fails(p, "Dismantle", { Token = q.Token, Confirm = "yes" }, "Hold to confirm")
	local ok, msg, res, after = try(p, "Dismantle", { Token = q.Token, Confirm = true })
	truthy(ok, tostring(msg))
	eq(res.Dust, 1887)
	eq(after.OwnedBlocks[leg], nil)
	-- Pumpkin (rank 4) also asks.
	local pump = block(p, "Pumpkin")
	local _, q2 = action(p, "DismantleQuote", { Uids = { pump } })
	eq(q2.NeedsConfirm, true)
	-- Epic does not.
	local epic = block(p, "Epic")
	local _, q3 = action(p, "DismantleQuote", { Uids = { epic } })
	eq(q3.NeedsConfirm, false)
	truthy((try(p, "Dismantle", { Token = q3.Token })), "epic without confirm")
end)

test("tokens: single quote per player, expiry after 60 s, fingerprints catch changed blocks", function()
	reset()
	local p = profile()
	local a = block(p, "Rare")
	local b = block(p, "Rare")
	local _, q1 = action(p, "DismantleQuote", { Uids = { a } })
	local _, q2 = action(p, "DismantleQuote", { Uids = { b } })
	fails(p, "Dismantle", { Token = q1.Token }, "Quote expired") -- replaced by the newer quote
	fails(p, "Dismantle", { Token = "zz" }, "Quote expired")
	fails(p, "Dismantle", {}, "Quote expired")
	-- Expired.
	local _, q3 = action(p, "DismantleQuote", { Uids = { a } })
	local ok, err = pcall(R.Action, R.Copy(p), "Dismantle", { Token = q3.Token }, NOW + C.QuoteSeconds + 1, function() return 0.5 end)
	truthy(not ok and string.find(err, "Quote expired", 1, true), "expired: " .. tostring(err))
	-- The block changed between quote and dismantle.
	local _, q4 = action(p, "DismantleQuote", { Uids = { a } })
	p.OwnedBlocks[a].PurchasedAt += 1
	fails(p, "Dismantle", { Token = q4.Token }, "Blocks changed")
	p.OwnedBlocks[a].PurchasedAt -= 1
	-- Placed on a pad meanwhile.
	local _, q5 = action(p, "DismantleQuote", { Uids = { a } })
	p.OwnedBlocks[a].State = "Placed"
	fails(p, "Dismantle", { Token = q5.Token }, "Take that block off its Lucky pad first")
	p.OwnedBlocks[a].State = "Stored"
	-- Gone (opened / traded) meanwhile.
	local _, q6 = action(p, "DismantleQuote", { Uids = { a } })
	local moved = p.OwnedBlocks[a]
	p.OwnedBlocks[a] = nil
	fails(p, "Dismantle", { Token = q6.Token }, "Blocks changed")
	p.OwnedBlocks[a] = moved
	-- Values changed (a balance update between quote and dismantle).
	local _, q7 = action(p, "DismantleQuote", { Uids = { a } })
	local saved = C.Salvage
	C.Salvage = 0.3
	fails(p, "Dismantle", { Token = q7.Token }, "Dust values changed")
	C.Salvage = saved
	truthy(q2.Token ~= q1.Token, "fresh tokens")
end)

test("receipts: the same token again answers the same result and pays nothing twice", function()
	reset()
	local p = profile()
	local a = block(p, "Epic")
	local _, q = action(p, "DismantleQuote", { Uids = { a } })
	local m1, r1 = action(p, "Dismantle", { Token = q.Token })
	eq(dust(p), 300)
	local m2, r2 = action(p, "Dismantle", { Token = q.Token })
	eq(m2, m1, "same message")
	eq(r2.Dust, r1.Dust)
	eq(r2.Repeat, true)
	eq(dust(p), 300, "paid once")
	eq(p.LuckyDust.Dismantled, 1)
	-- The receipt list is capped.
	for _ = 1, C.ReceiptCount + 3 do
		local id = block(p, "Common")
		local _, qq = action(p, "DismantleQuote", { Uids = { id } })
		action(p, "Dismantle", { Token = qq.Token })
	end
	eq(#p.LuckyDust.ReceiptOrder, C.ReceiptCount)
	eq(count(p.LuckyDust.Receipts), C.ReceiptCount)
end)

test("credits: legacy stacks dismantle by tier and count (incl. aliases)", function()
	reset()
	local p = profile()
	p.LuckyCredits.Common = 5
	p.LuckyCredits.Uncommon = 2
	p.LuckyCredits.Legendary = 1
	fails(p, "DismantleQuote", { Credits = { Common = 6 } }, "You do not have that many blocks of this tier")
	fails(p, "DismantleQuote", { Credits = { Common = 0 } }, "Choose blocks to dismantle")
	fails(p, "DismantleQuote", { Credits = { Nope = 1 } }, "This block cannot be dismantled")
	fails(p, "DismantleQuote", { Credits = { Common = 31 } }, "Choose blocks to dismantle")
	local _, q = action(p, "DismantleQuote", { Credits = { Common = 3, Uncommon = 2 } })
	eq(q.Count, 5)
	eq(q.Total, 3 * 12 + 2 * 55)
	eq(q.NeedsConfirm, false)
	local ok, msg, _, after = try(p, "Dismantle", { Token = q.Token })
	truthy(ok, tostring(msg))
	eq(after.LuckyCredits.Common, 2)
	eq(after.LuckyCredits.Uncommon, 0)
	eq(dust(after), 146)
	-- Credits + blocks share the 30 limit; Legendary credits need a confirmation.
	local ids = {}
	for _ = 1, 26 do table.insert(ids, (block(p, "Common"))) end
	fails(p, "DismantleQuote", { Uids = ids, Credits = { Common = 5 } }, "Dismantle at most 30 blocks at once")
	local _, q2 = action(p, "DismantleQuote", { Credits = { Legendary = 1 } })
	eq(q2.NeedsConfirm, true)
	-- Credits spent elsewhere between quote and dismantle.
	local _, q3 = action(p, "DismantleQuote", { Credits = { Common = 5 } })
	p.LuckyCredits.Common = 4
	fails(p, "Dismantle", { Token = q3.Token }, "Blocks changed")
end)

test("event candy: pumpkin tiers add Halloween candy while the event is on, nothing when off", function()
	reset()
	local p = profile()
	local pump = block(p, "Pumpkin")
	local cursed = block(p, "Cursed Pumpkin")
	local _, q = action(p, "DismantleQuote", { Uids = { pump, cursed } })
	eq(q.Candy, 65)
	eq(q.Total, 1500 + 10000)
	eq(q.NeedsConfirm, true)
	local before = Halloween.Shape(R.Copy(p)).Candy
	local message, res = action(p, "Dismantle", { Token = q.Token, Confirm = true })
	eq(message, "Dismantled 2 blocks: +11500 Lucky Dust · +65 Candy")
	eq(res.Candy, 65)
	eq(p.Halloween.Candy, before + 65, "candy through Features.Halloween.AddCandy")
	eq(p.LuckyDust.Candy, 65)
	-- Event off: no candy in the quote or the result.
	eventOn = false
	local p2 = profile()
	local pump2 = block(p2, "Pumpkin")
	local _, q2 = action(p2, "DismantleQuote", { Uids = { pump2 } })
	eq(q2.Candy, 0)
	eq(q2.Rows[1].Bonus, 0)
	local m2, r2 = action(p2, "Dismantle", { Token = q2.Token, Confirm = true })
	eq(m2, "Dismantled 1 block: +1500 Lucky Dust")
	eq(r2.Candy, 0)
	eq(p2.Halloween, nil, "no Halloween data created")
	-- The event switched on between quote and dismantle: values changed, review again.
	local pump3 = block(p2, "Pumpkin")
	local _, q3 = action(p2, "DismantleQuote", { Uids = { pump3 } })
	eventOn = true
	fails(p2, "Dismantle", { Token = q3.Token, Confirm = true }, "Dust values changed")
end)

test("dust cap: a dismantle past the Lucky Dust maximum is refused", function()
	reset()
	local p = profile()
	Resources.Add(p, "LuckyDust", Resources.Kinds.LuckyDust.Max - 5)
	local a = block(p, "Common")
	local _, q = action(p, "DismantleQuote", { Uids = { a } })
	fails(p, "Dismantle", { Token = q.Token }, "Your Lucky Dust is full")
end)

test("forge: spends dust, adds a stored block (DustForge, not paid random), respects the 60 cap", function()
	reset()
	local p = profile()
	fails(p, "DustForge", { Tier = "Rare" }, "Not enough Lucky Dust")
	Resources.Add(p, "LuckyDust", 1000)
	local ok, msg, res, after = try(p, "DustForge", { Tier = "Rare" })
	truthy(ok, tostring(msg))
	eq(msg, "Forged a Rare Lucky Block")
	eq(res.Cost, 220)
	eq(res.Balance, 780)
	eq(dust(after), 780)
	eq(#res.Uids, 1)
	local b = after.OwnedBlocks[res.Uids[1]]
	eq(b.Tier, "Rare")
	eq(b.State, "Stored")
	eq(b.Origin, "DustForge")
	eq(b.PaidRandom, false)
	eq(b.OwnerUserId, 1)
	eq(after.LuckyDust.Forged, 1)
	eq(after.LuckyDust.Spent, 220)
	-- Several at once (ForgeMaxCount), "an Epic".
	Resources.Add(p, "LuckyDust", 10000)
	local _, m2, r2 = try(p, "DustForge", { Tier = "Common", Count = 3 })
	eq(m2, "Forged 3 Common Lucky Blocks")
	eq(r2.Cost, 150)
	local _, m3 = try(p, "DustForge", { Tier = "Epic" })
	eq(m3, "Forged an Epic Lucky Block")
	fails(p, "DustForge", { Tier = "Common", Count = C.ForgeMaxCount + 1 }, "Choose how many blocks to forge")
	fails(p, "DustForge", { Tier = "Common", Count = 0 }, "Choose how many blocks to forge")
	fails(p, "DustForge", { Tier = "Mythic" }, "This block cannot be forged")
	fails(p, "DustForge", { Tier = "Pumpkin" }, "This block cannot be forged")
	fails(p, "DustForge", {}, "This block cannot be forged")
	-- Storage cap: Stored + Placed + Ready count (credits do not).
	local cap = Lifecycle.InventoryCapacity
	eq(cap, 60)
	local q = profile()
	Resources.Add(q, "LuckyDust", 100000)
	for i = 1, cap - 1 do block(q, "Common", i % 3 == 0 and { State = "Placed", Slot = 1 } or nil) end
	q.LuckyCredits.Common = 10
	truthy((try(q, "DustForge", { Tier = "Common" })), "59 + 1 fits")
	fails(q, "DustForge", { Tier = "Common", Count = 2 }, "Your Lucky Block storage is full")
	block(q, "Common")
	fails(q, "DustForge", { Tier = "Common" }, "Your Lucky Block storage is full")
	eq(dust(q), 100000, "nothing spent when refused")
end)

test("saved data: Normalize heals p.LuckyDust, Validate is nil-safe, Snapshot shows the totals", function()
	reset()
	local p = profile()
	eq(p.LuckyDust, nil, "not created by Normalize")
	R.Validate(p)
	p.LuckyDust = { Dismantled = -4, Earned = 0 / 0, Forged = "x", Receipts = { [string.rep("b", 32)] = { Dust = 5 } }, ReceiptOrder = { string.rep("b", 32), "junk", string.rep("c", 32) }, Future = 1 }
	F.Normalize(R, p, NOW)
	eq(p.LuckyDust.Dismantled, 0)
	eq(p.LuckyDust.Earned, 0)
	eq(p.LuckyDust.Forged, 0)
	eq(#p.LuckyDust.ReceiptOrder, 1, "orphans dropped")
	eq(p.LuckyDust.Future, 1, "unknown keys kept")
	R.Validate(p)
	p.LuckyDust = "corrupt"
	F.Normalize(R, p, NOW)
	eq(type(p.LuckyDust), "table", "healed")
	Resources.Add(p, "LuckyDust", 42)
	local view = {}
	R.Features.Snapshot(R, p, view, NOW)
	eq(view.LuckyDust.Dust, 42)
	eq(view.LuckyDust.Salvage, 0.25)
	eq(view.LuckyDust.Capacity, 60)
	-- Registered after Halloween (Order 80).
	local order = {}
	for i, f in ipairs(R.Features.Modules) do order[f.Name] = i end
	truthy(order.LuckyDust and order.Halloween and order.LuckyDust > order.Halloween, "feature order")
end)

test("receipts by request id: Engine:Action answers a retried Dismantle once (real Engine + Transactions)", function()
	reset()
	local Tx = L.Require("ServerScriptService.Economy.Transactions")
	local Engine = L.Require("ServerScriptService.Economy.Engine")
	local data = {}
	local store = {}
	function store:Read(k) return R.Copy(data[k]) end
	function store:Update(k, fn)
		local v = fn(R.Copy(data[k]))
		if v ~= nil then data[k] = R.Copy(v) end
		return R.Copy(v)
	end
	local n = 0
	local function guid() n += 1; return string.format("%032x", n) end
	local clock = function() return NOW end
	local tx = Tx.new(store, clock, guid, {})
	local engine = Engine.new(tx, { Now = clock, Guid = guid, Random = function() return 0.5 end, Session = "S1" })
	truthy(engine:Join(1), "join")
	local ids = {}
	truthy(tx:Run({ "p:1" }, function(v)
		local p = v["p:1"]
		for _ = 1, 3 do table.insert(ids, (block(p, "Rare"))) end
		p.LuckyCredits.Common = 2
		return true
	end), "seed")
	local okQ, q = engine:Action(1, "DismantleQuote", { Uids = ids, Credits = { Common = 2 } }, "1:quote-a")
	truthy(okQ, "quote: " .. tostring(q))
	eq(q.Total, 3 * 55 + 2 * 12)
	local okA, a = engine:Action(1, "Dismantle", { Token = q.Token }, "1:dismantle-a")
	local okB, b = engine:Action(1, "Dismantle", { Token = q.Token }, "1:dismantle-a")
	truthy(okA and okB, "both answered: " .. tostring(a) .. " / " .. tostring(b))
	eq(a.Message, b.Message, "same reply")
	eq(a.Dust, 189)
	local p = tx:Read("p:1")
	eq(Resources.Get(p, "LuckyDust"), 189, "paid once")
	eq(R.Count(p.OwnedBlocks), 0, "blocks gone")
	eq(p.LuckyCredits.Common, 0, "credits gone")
	-- A new request id with the used token: the saved receipt, still paid once.
	local okC, c = engine:Action(1, "Dismantle", { Token = q.Token }, "1:dismantle-b")
	truthy(okC, tostring(c))
	eq(c.Repeat, true)
	eq(Resources.Get(tx:Read("p:1"), "LuckyDust"), 189)
	-- A refused dismantle leaves the profile as it was.
	local okD, d = engine:Action(1, "Dismantle", { Token = string.rep("e", 32) }, "1:dismantle-c")
	truthy(not okD and string.find(tostring(d), "Quote expired", 1, true), tostring(d))
	-- Forge through the engine: refused without the dust (nothing changes), then answered once per request id.
	local okE, e = engine:Action(1, "DustForge", { Tier = "Rare" }, "1:forge-poor")
	truthy(not okE and string.find(tostring(e), "Not enough Lucky Dust", 1, true), tostring(e))
	eq(Resources.Get(tx:Read("p:1"), "LuckyDust"), 189)
	truthy(tx:Run({ "p:1" }, function(v)
		Resources.Add(v["p:1"], "LuckyDust", 1000)
		return true
	end), "top up")
	local okF, f = engine:Action(1, "DustForge", { Tier = "Rare" }, "1:forge-a")
	truthy(okF, tostring(f))
	local okF2, f2 = engine:Action(1, "DustForge", { Tier = "Rare" }, "1:forge-a")
	truthy(okF2, "retry answered")
	eq(f2.Uids[1], f.Uids[1], "same block in the retried reply")
	local after = tx:Read("p:1")
	eq(Resources.Get(after, "LuckyDust"), 1189 - 220, "charged once")
	eq(R.Count(after.OwnedBlocks), 1, "forged once")
	L.Overrides["ServerScriptService/Economy/ServerLuck"] = nil
end)

-- LOCALIZATION ----------------------------------------------------------------------------------------------------
local dictionaries = {}
for _, file in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
	local name = file:gsub("%.luau$", "")
	dictionaries[name] = L.Require("ReplicatedStorage.Localization." .. name)
end
local own = dictionaries.LuckyDust
local function translate(text)
	for _, dict in pairs(dictionaries) do
		if dict.Exact and dict.Exact[text] then return dict.Exact[text] end
	end
	for _, dict in pairs(dictionaries) do
		for _, rule in ipairs(dict.Patterns or {}) do
			local out, hits = string.gsub(text, rule[1], rule[2])
			if hits > 0 then return out end
		end
	end
	return nil
end
local function cyrillic(s)
	return type(s) == "string" and string.find(s, "[\208\209]") ~= nil
end

test("localization: every server answer has Russian (exact keys and the formatted messages)", function()
	local missing = {}
	local function need(text)
		local ru = translate(text)
		if not cyrillic(ru) then table.insert(missing, text) end
	end
	for _, path in ipairs({ "src/ServerScriptService/Economy/Features/LuckyDust.luau", "src/ReplicatedStorage/Halloween/DustRules.luau" }) do
		local source = fs.readFile(path)
		for line in string.gmatch(source, "[^\n]+") do
			if string.find(line, "R.Check(", 1, true) or string.find(line, "return false, \"", 1, true) then
				local last
				for literal in string.gmatch(line, '"([^"]*)"') do last = literal end
				if last and last ~= "" and not string.find(last, "%", 1, true) and string.find(last, " ") then
					need(last)
				end
			end
		end
	end
	for _, text in ipairs({
		"Dismantle 1 block for 12 Lucky Dust",
		"Dismantle 3 blocks for 1875 Lucky Dust",
		"Dismantled 1 block: +12 Lucky Dust",
		"Dismantled 2 blocks: +11500 Lucky Dust · +65 Candy",
		"Dismantle at most 30 blocks at once",
		"Forged a Common Lucky Block",
		"Forged a Rare Lucky Block",
		"Forged an Epic Lucky Block",
		"Forged a Legendary Lucky Block",
		"Forged 3 Common Lucky Blocks",
		"Forged 2 Legendary Lucky Blocks",
		"Not enough Lucky Dust",
		"Finish your trade first",
		"Your Lucky Block storage is full",
	}) do
		need(text)
	end
	eq(#missing, 0, "untranslated: " .. table.concat(missing, " | "))
	eq(translate("Dismantled 2 blocks: +11500 Lucky Dust · +65 Candy"), "Разобрано блоков: 2 · +11500 счастливой пыли · +65 конфет")
end)

test("localization: Localization.LuckyDust repeats no key of another dictionary or the base table", function()
	local base = {}
	local auto = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for en in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"') do base[en] = true end
	for en, ru in pairs(own.Exact) do
		truthy(not base[en], "repeats a base entry: " .. en)
		for name, dict in pairs(dictionaries) do
			if name ~= "LuckyDust" then
				truthy(not (dict.Exact and dict.Exact[en]), "repeats Localization." .. name .. ": " .. en)
			end
		end
		truthy(cyrillic(ru) and not string.find(ru, "[A-Za-z]"), "Russian text for " .. en)
	end
	for _, rule in ipairs(own.Patterns) do
		truthy(cyrillic(rule[2]), "Russian pattern " .. rule[1])
	end
end)

test("bag: every self-localized string the dismantle / forge UI adds has a Russian text", function()
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/InventoryScreen.luau")
	local n = 0
	for en, ru in string.gmatch(source, 'LT%("([^"]*)",%s*"([^"]*)"') do
		n += 1
		truthy(cyrillic(ru), "Russian for " .. en)
	end
	for en, ru in string.gmatch(source, 'FT%("([^"]*)",%s*"([^"]*)"') do
		n += 1
		truthy(cyrillic(ru), "Russian for " .. en)
		local _, a = string.gsub(en, "%%[sd]", "")
		local _, b = string.gsub(ru, "%%[sd]", "")
		eq(a, b, "same placeholders: " .. en)
	end
	truthy(n >= 20, "dismantle / forge strings found: " .. n)
	truthy(not string.find(source, 'LT%("[^"]*"%)'), "LT without a Russian text")
	truthy(not string.find(source, 'FT%("[^"]*"%)'), "FT without a Russian text")
end)

print(string.format("lucky_dust: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lucky_dust tests failed")
end
