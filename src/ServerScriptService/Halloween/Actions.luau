-- Player actions of NIGHT OF THE BURIED MOON (ServerScriptService.Halloween.Actions), on RS.Halloween.Remotes.Request:
--   Hello                       -> {View, Server}            first sync of the client
--   QuestClaim {Id} / QuestBonus                             daily quests (+ the all-quests bonus)
--   RushStart                                                personal Candy Rush (once per UTC day, 10 min of ACTIVE play)
--   CauldronTrick                                            TRICK: 80 Candy -> Pumpkin Lucky Block (sometimes Cursed)
--   CauldronInvest {Amount} / CauldronClaim                  TREAT: invest candy, level up, claim the brew after 7 days
--   SkinEquip {Id}                                           cosmetic pickaxe skin ("" = none)
--   DexClaim {Count}                                         event DogDex (BURIED MOON 2026) rewards
--   Onboarded / Seen {Key}                                   first-visit guide flags
--   OnboardingStep                                           a guide card is on screen: hold the curse (bounded)
-- Request costs (Core bucket: 14 tokens, +7/s): every action here but OnboardingStep runs a full profile transaction,
-- so the UI ones (first sync, guide flags, skins, once-a-day claims) cost UI (~1.75 writes/s sustained, like the
-- economy remote's 1.5/s) and the repeatable gameplay spends / claims PLAY. A request that changes nothing skips the write.
local RS = game:GetService("ReplicatedStorage")
local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config
local Layout = Shared.Layout

local A = {}
local UI, PLAY = { Cost = 4 }, { Cost = 2 }

local function serverView()
	local st = Halloween:FindFirstChild("State")
	local ex = st and st:FindFirstChild("Exorcism")
	return {
		Enabled = Shared.Enabled(), Now = os.time(), ServerRushUntil = st and st:GetAttribute("ServerRushUntil") or 0,
		MutationBoostUntil = st and st:GetAttribute("MutationBoostUntil") or 0,
		Exorcism = ex and { Souls = ex:GetAttribute("Souls") or 0, Goal = ex:GetAttribute("Goal") or Config.Exorcism.Goal,
			Milestone = ex:GetAttribute("Milestone") or 0, Cycle = ex:GetAttribute("Cycle") or 1 } or nil,
	}
end

function A.Start(core)
	local R = core.Rules
	local Feature = core.Feature

	-- Cauldron FX go to everyone (every client near the cauldron builds candy / block models): at most one TRICK and one
	-- TREAT per player per second; level-ups and claims always show
	local fxAt = setmetatable({}, { __mode = "k" })
	local function cauldronFx(player: Player, data: any)
		if data.Kind == "Trick" or data.Kind == "Treat" then
			local t, last = os.clock(), fxAt[player] or {}
			fxAt[player] = last
			if t - (last[data.Kind] or -1e9) < 1 then
				return
			end
			last[data.Kind] = t
		end
		core.Signal("all", "Cauldron", data)
	end

	core.OnRequest("Hello", function(player)
		local ok, res = core.Transact(player, "Hello", function(_p, _h)
			return {}
		end)
		if not ok then
			return false, res
		end
		res.Server = serverView()
		return true, res
	end, UI)

	core.OnRequest("QuestClaim", function(player, a)
		R.Check(type(a.Id) == "string" and #a.Id <= 40, "Invalid quest")
		return core.Transact(player, "QuestClaim", function(_p, h, ctx)
			local row = nil
			for _, q in ipairs(h.Quests.List) do
				if q.Id == a.Id then
					row = q
				end
			end
			R.Check(row ~= nil, "This quest is not part of today's list")
			R.Check(not row.Claimed, "Already claimed")
			R.Check(row.Progress >= row.Goal, "Quest not finished yet")
			row.Claimed = true
			local def = Feature.QuestDef(row.Id) or {}
			local candy = ctx.Candy(def.Candy or Config.Candy.Quest[1], "Quest", { NoMult = true, NoCap = true })
			local bones = def.Bones and ctx.Bones(def.Bones) or 0
			ctx.Souls(Config.Exorcism.Souls.Quest or 0)
			ctx.Relief("Objective")
			return { Message = "Quest reward claimed", Candy = candy, Bones = bones }
		end)
	end, PLAY)

	core.OnRequest("QuestBonus", function(player)
		local bonus = Config.Quests.AllBonus
		return core.Transact(player, "QuestBonus", function(_p, h, ctx)
			R.Check(not h.Quests.AllClaimed, "Already claimed today")
			for _, q in ipairs(h.Quests.List) do
				R.Check(q.Claimed, "Finish and claim every daily quest first")
			end
			h.Quests.AllClaimed = true
			local rows = {}
			if bonus.Candy then
				table.insert(rows, ctx.Reward({ Kind = "Candy", Amount = bonus.Candy }))
			end
			table.insert(rows, ctx.Reward(bonus))
			return { Message = "Daily bonus claimed", Rewards = rows }
		end)
	end, UI)

	-- the RAM timer takes the started rush from the committed view (Core.Sync), never from inside the transform
	core.OnRequest("RushStart", function(player)
		return core.Transact(player, "RushStart", function(_p, h)
			R.Check(not h.Rush.Active, "Your Candy Rush is already running")
			R.Check(h.Rush.Remaining > 0, "Candy Rush used today. Come back tomorrow!")
			h.Rush.Active = true
			return { Message = "CANDY RUSH x2 started", Remaining = h.Rush.Remaining }
		end)
	end, UI)

	-- no client-chosen receipt (a.Request is ignored): a replayed receipt returned the cached reply without spending
	-- candy, and Core re-ran its souls / broadcast every time. Every trick is a new paid transaction.
	core.OnRequest("CauldronTrick", function(player)
		R.Check(core.Near(player, Layout.Cauldron.Center, Config.Cauldron.Range + 8), "Come closer to the Haunted Cauldron")
		local cursed = math.random() < Config.Cauldron.CursedChance
		local tier = cursed and "Cursed Pumpkin" or "Pumpkin"
		local ok, res, _, cached = core.Transact(player, "CauldronTrick", function(p, h, ctx)
			ctx.Spend(Config.Cauldron.TrickCost)
			local cap = require(RS.LuckyLifecycleConfig).InventoryCapacity or 60
			R.Check(R.Count(p.OwnedBlocks or {}) + 1 <= cap, "Your Lucky Block storage is full. Open a block first")
			local ids = ctx.Block(tier, 1)
			R.Check(ids ~= nil, "Your Lucky Block storage is full. Open a block first")
			h.Cauldron.Tricks += 1
			ctx.Stat("Tricks", 1)
			ctx.Souls(Config.Exorcism.Souls.Trick or 0)
			ctx.Relief("Cauldron")
			return { Message = string.upper(tier) .. " LUCKY BLOCK added to your Inventory", Tier = tier, Uids = ids }
		end)
		if ok and not cached then
			cauldronFx(player, { Kind = "Trick", UserId = player.UserId, Tier = tier })
		end
		return ok, res
	end, PLAY)

	core.OnRequest("CauldronInvest", function(player, a)
		local amount = math.floor(tonumber(a.Amount) or 0)
		R.Check(amount >= 1 and amount <= 1e7, "Invalid amount")
		local leveled = nil
		local ok, res, _, cached = core.Transact(player, "CauldronInvest", function(_p, h, ctx)
			local c = h.Cauldron
			R.Check(not c.Claimed, "Your brew is finished for this season")
			local thresholds = Feature.CauldronThresholds()
			local maxInvest = thresholds[#thresholds]
			R.Check(c.Invested < maxInvest, "The cauldron is already at the top level")
			amount = math.min(amount, maxInvest - c.Invested)
			ctx.Spend(amount)
			if c.StartedAt <= 0 then
				c.StartedAt = os.time()
			end
			c.Invested += amount
			local before = c.Level
			for i = #thresholds, 1, -1 do
				if c.Invested >= thresholds[i] then
					c.Level = math.max(c.Level, i)
					break
				end
			end
			if c.Level > before then
				leveled = c.Level
			end
			ctx.Relief("Cauldron")
			return { Message = leveled and ("CAULDRON LEVEL " .. leveled) or ("Invested " .. amount .. " Candy"), Level = c.Level, Invested = c.Invested }
		end)
		if ok and not cached then
			cauldronFx(player, { Kind = leveled and "LevelUp" or "Treat", UserId = player.UserId, Level = res.Level })
		end
		return ok, res
	end, PLAY)

	-- TREAT can also be started for free (level 1) without investing
	core.OnRequest("CauldronBrew", function(player)
		return core.Transact(player, "CauldronBrew", function(_p, h)
			local c = h.Cauldron
			R.Check(not c.Claimed, "Your brew is finished for this season")
			if c.StartedAt <= 0 then
				c.StartedAt = os.time()
			end
			return { Message = "Your brew is simmering", StartedAt = c.StartedAt }
		end)
	end, UI)

	core.OnRequest("CauldronClaim", function(player)
		local level = 1
		local ok, res, _, cached = core.Transact(player, "CauldronClaim", function(_p, h, ctx)
			local c = h.Cauldron
			R.Check(c.StartedAt > 0, "Start a brew first")
			R.Check(not c.Claimed, "Already claimed")
			R.Check(os.time() >= c.StartedAt + Shared.BrewSeconds(), "The brew is not ready yet")
			c.Claimed = true
			level = c.Level
			local tableName = Shared.CauldronLevel(c.Level).Table
			local rows = {}
			for _, row in ipairs(Config.Rewards[tableName] or {}) do
				table.insert(rows, ctx.Reward(row))
			end
			ctx.Relief("Objective")
			return { Message = "The Buried Moon Brew is ready!", Rewards = rows, Level = c.Level }
		end, { Rows = (function()
			local all = {}
			for _, lv in ipairs(Config.Cauldron.Levels) do
				for _, row in ipairs(Config.Rewards[lv.Table] or {}) do
					table.insert(all, row)
				end
			end
			return all
		end)() })
		if ok and not cached then
			cauldronFx(player, { Kind = "Claim", UserId = player.UserId, Level = level })
		end
		return ok, res
	end, UI)

	core.OnRequest("SkinEquip", function(player, a)
		local id = type(a.Id) == "string" and a.Id or ""
		return core.Transact(player, "SkinEquip", function(_p, h)
			R.Check(id == "" or h.Skins[id] == true, "You don't own this skin")
			h.Skin = id
			return { Message = id == "" and "Skin removed" or ((Config.Skins.Names[id] or id) .. " equipped"), Skin = id }
		end)
	end, UI)

	core.OnRequest("DexClaim", function(player, a)
		local count = math.floor(tonumber(a.Count) or 0)
		local tier = nil
		for _, row in ipairs(Config.DexRewards) do
			if row.Count == count then
				tier = row
			end
		end
		R.Check(tier ~= nil, "Invalid reward")
		return core.Transact(player, "DexClaim", function(p, h, ctx)
			R.Check(not h.DexClaims[tostring(count)], "Already claimed")
			R.Check(Feature.EventDexCount(p) >= count, "Discover more Buried Moon dogs first")
			h.DexClaims[tostring(count)] = true
			local rows = {}
			if tier.Candy then
				table.insert(rows, ctx.Reward({ Kind = "Candy", Amount = tier.Candy }))
			end
			if tier.Bones then
				table.insert(rows, ctx.Reward({ Kind = "Bones", Amount = tier.Bones }))
			end
			if tier.Block then
				table.insert(rows, ctx.Reward({ Kind = "Block", Id = tier.Block, Amount = 1 }))
			end
			if tier.Skin then
				table.insert(rows, ctx.Reward({ Kind = "Skin", Id = tier.Skin }))
			end
			if tier.Title then
				p.Cosmetics = type(p.Cosmetics) == "table" and p.Cosmetics or {}
				p.Cosmetics[tier.Title] = true
				ctx.Touched = true
			end
			return { Message = "Event DogDex reward claimed", Rewards = rows }
		end)
	end, PLAY) -- several milestones may be claimed in a row

	-- the latest committed view in RAM, for requests that would change nothing
	local function known(player: Player)
		local st = core.State(player)
		return st and type(st.View) == "table" and st.View or nil
	end

	core.OnRequest("Onboarded", function(player)
		local st, view = core.State(player), known(player)
		if st then
			st.CurseFrozenUntil = nil -- the guide is over
		end
		if view and view.Onboarded == true then
			return true, { Message = "", View = view }
		end
		return core.Transact(player, "Onboarded", function(_p, h)
			h.Onboarded = true
			return { Message = "" }
		end)
	end, UI)

	core.OnRequest("Seen", function(player, a)
		R.Check(type(a.Key) == "string" and #a.Key <= 40, "Invalid key")
		local view = known(player)
		local seen = view and type(view.Seen) == "table" and view.Seen or nil
		if seen then
			local n = 0
			for _ in pairs(seen) do
				n += 1
			end
			if seen[a.Key] or n >= 60 then -- already set / full (Feature.Shape keeps 60 keys)
				return true, { Message = "", View = view }
			end
		end
		return core.Transact(player, "Seen", function(_p, h)
			h.Seen[a.Key] = true
			return { Message = "" }
		end)
	end, UI)

	-- A first-visit guide card is on screen (the guide locks the controls): hold the curse rise for one card's reading
	-- time. RAM only, and bounded: only while the profile is not onboarded yet (the "Onboarded" flag ends it), at most
	-- Config.Curse.OnboardingFreezeMax seconds of freeze per session, Candy Rush / activity untouched.
	core.OnRequest("OnboardingStep", function(player)
		local st, view = core.State(player), known(player)
		if st and view and view.Onboarded == false then
			local t = os.clock()
			local from = math.max(t, st.CurseFrozenUntil or 0)
			local untilAt = math.min(t + Config.Curse.OnboardingFreeze, from + math.max(0, Config.Curse.OnboardingFreezeMax - (st.FreezeUsed or 0)))
			if untilAt > from then
				st.FreezeUsed = (st.FreezeUsed or 0) + (untilAt - from)
				st.CurseFrozenUntil = untilAt
			end
		end
		return true, { Message = "" }
	end, { Cost = 1 })
end

return A
