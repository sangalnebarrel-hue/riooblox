-- CHAPTER II · THE UNDERYARD — server core (ServerScriptService.Halloween.Chapter2; docs/halloween2/DESIGN.md §4.2, §22.2).
-- * C2.Transact: Core.Transact + the Chapter II profile (Features.Underyard.Shape + EnsureDaily) + the Chapter I latch
--   (HalloweenChapter1Complete) + a ctx with the Chapter II grant helpers (Bell Shards with daily diminishing returns and
--   the rested allowance, Lucky Dust, Coffin Keys, fragments, showcase finds, journal, contracts, reward rows that
--   convert duplicates and never fail). Every write of Chapter II goes through it.
--   ctx = the Core ctx (Candy, Spend, Bones, Coins, XP, Item, Dog, Block, Decor, Skin, Reward, Quest, Stat, After ...) +
--     Shards(n, source) -> granted · SpendShards(n) · Dust(n) · Keys(n, source?) -> stored, overflow · Fragments(n)
--     Find(itemId, mutation?) -> item? · Journal(key) · Contract(statKey, n) · C2Stat(key, n) · UseDoor() -> left
--     SealProgress(i, n) -> total · RecordCoffin(result) · TakeCrownRoll() -> bool · C2Reward(row) -> out
--     C2Signal(kind, data) (sent after the commit) · U (p.Underyard) · Now · Player
-- * Player attributes (§3.4): HalloweenChapter1Complete, Chapter2RevealSeen, Chapter2Notified, Chapter2Entered,
--   CoffinKeys, UySeals, UySealMask, UyTutorial (+ BellShards / LuckyDust right after a write; Runtime projects them too).
-- * RS.Halloween.State.Chapter2 {Enabled, Phase, NextPhaseAt, Start, PhaseOverride?} and the C2Phase signal.
-- * Requests (RS.Halloween.Remotes.Request): C2Hello, C2Notified, C2RevealSeen, C2ContractClaim, C2ContractBonus,
--   C2Exchange, C2SealOffer, C2DexClaim, C2Craft, C2Journal, C2Tutorial. With Chapter II switched off every one answers
--   "Chapter II is closed".
-- * C2.Progress (contracts, stats, resonance) and Perfect streak shards (C2.StreakHit) are queued per player and written
--   in ONE transaction per second; C2.OnTick gives other modules a 1 s per-player tick.
-- * Signals (Core.Signal): C2Toast {Text}, C2Shards {Amount, Source, Eff}, C2Seal {Seal, Stage, Rewards}, C2Contract {Id},
--   C2Key {Amount, Source}, C2Reveal {Need?}, C2Phase {Phase}, C2Journal {Key}, C2Tutorial {Step, Done}.
-- Other modules reach this one lazily through `modules.Chapter2` (DESIGN §22.1).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Economy = SSS:WaitForChild("Economy")
local Feature = require(Economy:WaitForChild("Features"):WaitForChild("Underyard"))
local Resources = require(RS:WaitForChild("DogEconomy"):WaitForChild("Resources"))

local C2 = {}
C2.Config = Cfg
C2.Rules = Rules
C2.Feature = Feature
C2.Layout = Layout
C2.Closed = "Chapter II is closed"

local core: any = nil
local modules: any = nil
local stateFolder: Folder? = nil
local phaseOverride: number? = nil
local rng = Random.new()
local ram: { [Player]: any } = {} -- per-player RAM: Queue, streak, last activity, last synced view
local tickFns: { (Player, number) -> () } = {}
local SLACK = Cfg.Proximity.Slack

local function R()
	return core.Rules
end

function C2.Enabled(): boolean
	return Shared.Chapter2Enabled()
end

local function stateOf(player: Player): any
	local st = ram[player]
	if not st then
		st = { Streak = 0, StreakAt = 0, MinuteStart = os.clock(), MinuteShards = 0, Carry = 0, LastActive = -1e9, BossRem = 0,
			Crown = 0, InFlight = {} }
		ram[player] = st
	end
	return st
end

---------------------------------------------------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------------------------------------------------
function C2.InUnderyard(player: Player): boolean
	local UY = modules and modules.Underyard
	if UY and UY.InZone then
		return UY.InZone(player) == true
	end
	return player:GetAttribute("UyInZone") == true
end

function C2.UnderyardPlayers(): { Player }
	local UY = modules and modules.Underyard
	if UY and UY.Players then
		return UY.Players()
	end
	local out = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl:GetAttribute("UyInZone") == true then
			table.insert(out, pl)
		end
	end
	return out
end

-- target: Player | "all" | "underyard"
function C2.Signal(target: any, kind: string, data: any)
	if not core then
		return
	end
	if target == "underyard" then
		for _, pl in ipairs(C2.UnderyardPlayers()) do
			core.Signal(pl, kind, data)
		end
	else
		core.Signal(target, kind, data)
	end
end

function C2.Toast(player: Player, text: string, kind: string?)
	C2.Signal(player, "C2Toast", { Text = text, Kind = kind or "info" })
end

---------------------------------------------------------------------------------------------------------------------
-- Phase (seals open by date) + RS.Halloween.State.Chapter2
---------------------------------------------------------------------------------------------------------------------
function C2.Phase(now: number?): number
	return Rules.Phase(now or os.time(), Cfg, phaseOverride)
end

function C2.SealOpen(i: number, now: number?): boolean
	return Rules.SealOpen(i, now or os.time(), Cfg, phaseOverride)
end

function C2.PhaseOverride(): number?
	return phaseOverride
end

-- Studio (C2Debug "Phase n"): open seals early; nil = back to the dates
function C2.SetPhaseOverride(n: number?)
	phaseOverride = n and math.clamp(math.floor(n), 0, #Cfg.Seals) or nil
	if stateFolder then
		stateFolder:SetAttribute("PhaseOverride", phaseOverride)
	end
	C2.PublishPhase(true)
end

local lastPhase: number? = nil
function C2.PublishPhase(force: boolean?)
	if not stateFolder then
		return
	end
	local now = os.time()
	local phase = C2.Phase(now)
	core.SetAttr(stateFolder, "Enabled", C2.Enabled())
	core.SetAttr(stateFolder, "Phase", phase)
	core.SetAttr(stateFolder, "NextPhaseAt", Rules.NextPhaseAt(now, Cfg, phaseOverride))
	core.SetAttr(stateFolder, "Start", Rules.StartUnix(Cfg))
	if lastPhase ~= nil and (phase ~= lastPhase or force) then
		C2.Signal("all", "C2Phase", { Phase = phase, NextPhaseAt = Rules.NextPhaseAt(now, Cfg, phaseOverride) })
	end
	lastPhase = phase
end

local function serverInfo(): any
	local now = os.time()
	local st = Halloween:FindFirstChild("State")
	local res = st and st:FindFirstChild("Resonance")
	return {
		Enabled = C2.Enabled(), Now = now, Phase = C2.Phase(now), NextPhaseAt = Rules.NextPhaseAt(now, Cfg, phaseOverride),
		Start = Rules.StartUnix(Cfg), Override = phaseOverride, Resonance = res and res:GetAttributes() or nil,
	}
end
C2.ServerInfo = serverInfo

---------------------------------------------------------------------------------------------------------------------
-- Player state readers (server-latched attributes / the RAM view of the last committed write)
---------------------------------------------------------------------------------------------------------------------
function C2.Eligible(player: Player): boolean
	if player == nil then
		return false
	end
	local ok, v = pcall(function()
		return player:GetAttribute("HalloweenChapter1Complete")
	end)
	return ok and v == true
end

-- the client view of a profile (Features.Underyard.View; embedded in every Halloween view as .Chapter2)
function C2.View(p: any, now: number?): any
	return Feature.View(p, now or os.time())
end

function C2.ViewOf(player: Player): any
	local st = core and core.State(player)
	local view = st and type(st.View) == "table" and st.View.Chapter2
	return type(view) == "table" and view or nil
end

function C2.SealMask(player: Player): string
	local mask = player:GetAttribute("UySealMask")
	return type(mask) == "string" and #mask == #Cfg.Seals and mask or string.rep("0", #Cfg.Seals)
end
C2.Sealsof = C2.SealMask -- (DESIGN §4.2 spelling)

function C2.SealCleared(player: Player, i: number): boolean
	return string.sub(C2.SealMask(player), i, i) == "1"
end

function C2.ClearedCount(player: Player): number
	return tonumber(player:GetAttribute("UySeals")) or 0
end

function C2.TutorialStep(player: Player): number
	return tonumber(player:GetAttribute("UyTutorial")) or 0
end

-- dogs assigned to a yard dig slot (abilities rule, §9.8), from the economy's last projected profile (RAM)
local function teamOf(p: any): { [string]: boolean }
	local out = {}
	for _, d in pairs(type(p) == "table" and type(p.Dogs) == "table" and p.Dogs or {}) do
		if type(d) == "table" and type(d.DogId) == "string" and type(d.AssignedSlot) == "string" and d.AssignedSlot ~= ""
			and d.State ~= "Walking" then
			out[d.DogId] = true
		end
	end
	return out
end
C2.TeamOfProfile = teamOf

function C2.TeamDogs(player: Player): { [string]: boolean }
	local Runtime = core and core.Runtime
	local view = Runtime and Runtime.Views and Runtime.Views[player.UserId]
	return teamOf(view)
end

function C2.HasTeamDog(player: Player, dogId: string): boolean
	return C2.TeamDogs(player)[dogId] == true
end

-- the dog's ability numbers when it is in the player's yard team (nil otherwise)
function C2.Ability(player: Player, dogId: string): any
	if C2.HasTeamDog(player, dogId) then
		return Cfg.Dogs.Defs[dogId]
	end
	return nil
end

function C2.ActiveWithin(player: Player, seconds: number): boolean
	local st = ram[player]
	return st ~= nil and os.clock() - st.LastActive <= seconds
end

local function setAttr(inst: Instance, name: string, value: any)
	if core then
		core.SetAttr(inst, name, value)
	elseif inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

-- player attributes from a Chapter II view (Features.Underyard.View)
local function syncAttrs(player: Player, view: any)
	if type(view) ~= "table" or view.Fresh or not player.Parent then
		return
	end
	local c1 = view.Chapter1 or {}
	setAttr(player, "HalloweenChapter1Complete", c1.Complete == true)
	setAttr(player, "Chapter2Notified", c1.Notified == true)
	setAttr(player, "Chapter2RevealSeen", view.RevealSeen == true)
	setAttr(player, "Chapter2Entered", view.Entered == true)
	setAttr(player, "CoffinKeys", tonumber(view.Keys) or 0)
	setAttr(player, "UySeals", tonumber(view.Cleared) or 0)
	setAttr(player, "UySealMask", type(view.Mask) == "string" and view.Mask or string.rep("0", #Cfg.Seals))
	setAttr(player, "UyTutorial", view.Tutorial and tonumber(view.Tutorial.Current) or 0)
	setAttr(player, "BellShards", tonumber(view.Shards) or 0)
	setAttr(player, "LuckyDust", tonumber(view.Dust) or 0)
end
C2.SyncAttrs = syncAttrs

---------------------------------------------------------------------------------------------------------------------
-- The Chapter I latch (§3.3)
---------------------------------------------------------------------------------------------------------------------
function C2.Latch(p: any, u: any, now: number): boolean
	if u.Chapter1.Complete then
		return false
	end
	local ok = Rules.Chapter1Complete(p, Cfg)
	if not ok then
		return false
	end
	u.Chapter1.Complete = true
	u.Chapter1.At = now
	if not u.Journal.chapter1 then
		u.Journal.chapter1 = now
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Transactions
---------------------------------------------------------------------------------------------------------------------
local STAT_OF = { Perfect = "Perfect", Streak = "Streaks", Trial = "Trials", Door = "Doors", Spirit = "Spirits",
	Revive = "Revives", Down = "Downs" }

local function makeCtx(player: Player, p: any, u: any, ctx: any, now: number, dogs: { string }): any
	local Rl = R()
	local pending = {} -- signals sent after the commit
	local shardsBy = {} -- source -> granted (one C2Shards per source and write)
	local team = nil
	local function hasTeam(id: string): boolean
		team = team or teamOf(p)
		return team[id] == true
	end
	local function signal(kind: string, data: any)
		table.insert(pending, { kind, data })
	end
	ctx.U = u
	ctx.Now = now
	ctx.Player = player
	ctx.C2Signal = signal
	ctx.After(function()
		for source, n in pairs(shardsBy) do
			if n > 0 then
				local rate = Rules.DRRate(u.Daily.Raw, Cfg)
				C2.Signal(player, "C2Shards", { Amount = n, Source = source, Eff = Rules.Exempt(source, Cfg) and 1 or rate })
			end
		end
		for _, s in ipairs(pending) do
			C2.Signal(player, s[1], s[2])
		end
	end)

	-- Bell Shards: daily DR (and the rested allowance) unless the source is exempt
	function ctx.Shards(n: number, source: string?): number
		source = type(source) == "string" and source or "Reward"
		n = math.max(0, math.floor(tonumber(n) or 0))
		if n <= 0 then
			return 0
		end
		local pay = n
		if not Rules.Exempt(source, Cfg) then
			pay = Rules.ShardGrant(u.Daily, u.Rested, n, Cfg)
		end
		local granted = Resources.Add(p, "BellShards", pay)
		ctx.Touched = true
		if not Cfg.ShardsIgnore[source] then
			u.Stats.ShardsEarned = math.min(Cfg.Limits.Stat, u.Stats.ShardsEarned + granted)
			ctx.Contract("Shards", granted)
		end
		shardsBy[source] = (shardsBy[source] or 0) + granted
		return granted
	end

	function ctx.SpendShards(n: number)
		n = math.max(0, math.floor(tonumber(n) or 0))
		Rl.Check(Resources.Get(p, "BellShards") >= n, "Not enough Bell Shards")
		if n > 0 then
			Resources.Spend(p, { BellShards = n })
			ctx.Touched = true
		end
	end

	function ctx.Dust(n: number): number
		n = math.max(0, math.floor(tonumber(n) or 0))
		if n <= 0 then
			return 0
		end
		local granted = Resources.Add(p, "LuckyDust", n)
		ctx.Touched = true
		return granted
	end

	-- -> keys stored, keys that did not fit (above Coffin.MaxKeys). Resonance keys also obey the per-day cap.
	function ctx.Keys(n: number, source: string?): (number, number)
		n = math.max(0, math.floor(tonumber(n) or 0))
		if source == "Resonance" then
			n = math.min(n, math.max(0, Cfg.Resonance.KeysPerDay - u.Daily.Keys))
			u.Daily.Keys += n
		end
		if n <= 0 then
			return 0, 0
		end
		local keys, granted, overflow = Rules.AddKeys(u.Keys, n, Cfg)
		u.Keys = keys
		if granted > 0 then
			signal("C2Key", { Amount = granted, Source = source or "Reward" })
		end
		return granted, overflow
	end

	function ctx.Fragments(n: number): number
		n = math.max(0, math.floor(tonumber(n) or 0))
		local before = u.Fragments
		u.Fragments = math.min(Cfg.Craft.MaxFragments, before + n)
		return u.Fragments - before
	end

	-- a showcase find (ItemDefinitions id) -> item copy, or nil (unknown id / full item storage)
	function ctx.Find(itemId: string, mutation: string?): any
		local Items = require(Economy:WaitForChild("ItemRules"))
		if type(itemId) ~= "string" or not Items.Definitions[itemId] then
			return nil
		end
		local copy = ctx.Item({ ItemId = itemId, Mutation = mutation, Origin = "Underyard" })
		if copy and copy.ItemId == itemId then
			u.Owned.Finds[itemId] = true
			return copy
		end
		return copy
	end

	function ctx.Journal(key: string): boolean
		if type(key) ~= "string" or #key > 40 or u.Journal[key] then
			return false
		end
		local n = 0
		for _ in pairs(u.Journal) do
			n += 1
		end
		if n >= Cfg.Journal.Max then
			return false
		end
		u.Journal[key] = now
		signal("C2Journal", { Key = key })
		return true
	end

	-- progress today's contract `id` (a C2.Progress statKey)
	function ctx.Contract(id: string, n: number?)
		n = math.max(0, math.floor(tonumber(n) or 1))
		if n <= 0 then
			return
		end
		for _, row in ipairs(u.Daily.Contracts.List) do
			if row.Id == id and not row.Claimed and row.Progress < row.Goal then
				row.Progress = math.min(row.Goal, row.Progress + n)
				if row.Progress >= row.Goal then
					signal("C2Contract", { Id = row.Id, Goal = row.Goal })
				end
			end
		end
	end

	function ctx.C2Stat(key: string, n: number?)
		if u.Stats[key] ~= nil then
			u.Stats[key] = math.min(Cfg.Limits.Stat, u.Stats[key] + math.max(0, math.floor(tonumber(n) or 1)))
		end
	end

	-- a Crooked Door opening of today (Seal V): errors when none is left
	function ctx.UseDoor(): number
		local max = Rules.DoorsPerDay(u, Cfg)
		Rl.Check(u.Daily.Doors < max, "No Crooked Door openings left today")
		u.Daily.Doors += 1
		return max - u.Daily.Doors
	end

	-- persistent per-seal progress (Seal V counts door outcomes across days) -> new total
	function ctx.SealProgress(i: number, n: number): number
		local s = u.Seals[tostring(i)]
		Rl.Check(s ~= nil, "Unknown seal")
		s.Progress = math.clamp(math.floor((tonumber(s.Progress) or 0) + (tonumber(n) or 0)), 0, 1e6)
		return s.Progress
	end

	-- the Black Coffin (Coffin.luau): record one opening (Coffins.Opened, Coffins.Last newest first, "Coffin" contract)
	function ctx.RecordCoffin(result: any)
		result = type(result) == "table" and result or {}
		u.Coffins.Opened += 1
		table.insert(u.Coffins.Last, 1, { Key = tostring(result.Key or result.Id or result.Kind or "?"), Kind = tostring(result.Kind or ""),
			Id = type(result.Id) == "string" and result.Id or nil, Amount = math.max(0, math.floor(tonumber(result.Amount) or 0)),
			Rank = math.clamp(math.floor(tonumber(result.Rank) or 1), 1, 6), Converted = result.Converted == true or nil, At = now })
		while #u.Coffins.Last > Cfg.Coffin.Last do
			table.remove(u.Coffins.Last)
		end
		ctx.Contract("Coffin", 1)
	end

	-- H16 CROWN OF THE UNDERYARD: consume one stored extra showcase-find roll -> true when one was stored
	function ctx.TakeCrownRoll(): boolean
		local crown = u.Coffins.Crown
		if crown.Rolls > 0 then
			crown.Rolls -= 1
			return true
		end
		return false
	end

	-- one reward row (Kinds: Shards Dust Key Fragments Find Decor Skin Dog Candy Bones Cash Title). Never fails:
	-- duplicates / undeliverable rewards convert (§9.4) and say so (Converted, Reason, Conversion).
	local convert
	function ctx.C2Reward(row: any): any
		row = type(row) == "table" and row or {}
		local kind = row.Kind
		local out = { Kind = kind, Id = row.Id, Key = row.Key, Rank = row.Rank, Group = row.Group, Tier = row.Tier }
		local amount = tonumber(row.Amount)
		if amount == nil and tonumber(row.Min) and tonumber(row.Max) then
			amount = Rules.Between(rng, row.Min, row.Max)
		end
		amount = math.max(0, math.floor(amount or 0))
		if kind == "Shards" then
			out.Amount = ctx.Shards(amount, row.Source or "Reward")
		elseif kind == "Dust" then
			out.Amount = ctx.Dust(amount)
		elseif kind == "Key" then
			local granted, overflow = ctx.Keys(math.max(1, amount), row.Source or "Reward")
			out.Amount = granted
			if overflow > 0 then
				out.Overflow = { Kind = "Shards", Amount = ctx.Shards(overflow * Cfg.Coffin.OverflowKeyShards, "Overflow") }
			end
		elseif kind == "Fragments" then
			out.Amount = ctx.Fragments(amount)
		elseif kind == "Find" then
			local Items = require(Economy:WaitForChild("ItemRules"))
			if u.Owned.Finds[row.Id] then
				convert(out, row, "Owned")
			elseif type(row.Id) ~= "string" or not Items.Definitions[row.Id] then
				convert(out, row, "Unavailable")
			elseif not Items.Free(p) then
				convert(out, row, "Full")
			else
				local item = ctx.Find(row.Id, row.Mutation)
				if item then
					out.Item, out.Amount = item, 1
				else
					convert(out, row, "Full")
				end
			end
		elseif kind == "Decor" then
			local Catalog = require(RS:WaitForChild("DogEconomy"):WaitForChild("DecorCatalog"))
			if type(row.Id) ~= "string" or Catalog.MaxOwned(row.Id) <= 0 then
				convert(out, row, "Unavailable")
			elseif ctx.Decor(row.Id) then
				u.Owned.Decor[row.Id] = true
				out.Amount = 1
			else
				convert(out, row, "Owned")
			end
		elseif kind == "Skin" then
			local hcfg = Shared.Config
			local h = p.Halloween
			if type(row.Id) ~= "string" or not hcfg.Skins.Names[row.Id] then
				convert(out, row, "Unavailable")
			elseif type(h) == "table" and type(h.Skins) == "table" and h.Skins[row.Id] then
				convert(out, row, "Owned")
			elseif ctx.Skin(row.Id) then
				out.Amount = 1
			else
				convert(out, row, "Owned")
			end
		elseif kind == "Dog" then
			local id = row.Id
			if type(id) ~= "string" or not table.find(dogs, id) then
				convert(out, row, "Undeclared")
			elseif not Rl.Free(p) then
				convert(out, row, "Full")
			elseif not core.Runtime.Engine.AssetReady(id) then
				convert(out, row, "Unavailable")
			else
				local dog = ctx.Dog(id, row.Variant)
				local live = dog and p.Dogs[dog.DogUid]
				if live then
					live.Origin = "Underyard"
					dog.Origin = "Underyard"
				end
				out.Dog, out.Amount = dog, 1
			end
		elseif kind == "Candy" then
			out.Amount = ctx.Candy(amount, "Underyard", { NoMult = true, NoCap = true })
		elseif kind == "Bones" then
			out.Amount = ctx.Bones(amount)
		elseif kind == "Cash" then
			out.Amount = ctx.Coins(row.Coins or amount)
		elseif kind == "Title" then
			if type(row.Id) == "string" and #row.Id <= 60 then
				p.Cosmetics = type(p.Cosmetics) == "table" and p.Cosmetics or {}
				out.New = p.Cosmetics[row.Id] ~= true
				p.Cosmetics[row.Id] = true
				ctx.Touched = true
				out.Amount = 1
			end
		else
			-- an unknown kind (a newer config on an older server) becomes a little dust, never an error
			warn("Chapter2: unknown reward kind " .. tostring(kind))
			out.Converted, out.Reason = true, "Unknown"
			out.Kind, out.Amount = "Dust", ctx.Dust(Cfg.Duplicates.Decor.Dust)
		end
		return out
	end

	convert = function(out: any, row: any, reason: string)
		local rows = Rules.DuplicateConversion(row, Cfg, { CoffinPug = hasTeam("HW_CoffinPug") }) or {}
		out.Converted, out.Reason, out.Conversion = true, reason, {}
		for _, c in ipairs(rows) do
			local got = ctx.C2Reward(c)
			table.insert(out.Conversion, { Kind = got.Kind, Amount = got.Amount })
		end
	end

	return ctx
end

-- tutorial: the condition of a step that completes from profile state (Chapter2Config.Tutorial.Steps[].Auto)
local function autoDone(def: any, p: any, u: any): boolean
	local t = u.Tutorial
	if def.Auto == "ShardsEarned" then
		return u.Stats.ShardsEarned - (tonumber(t.Mark) or 0) >= (def.Goal or 1)
	elseif def.Auto == "CoffinOpened" then
		return u.Coffins.Opened - (tonumber(t.Mark) or 0) >= (def.Goal or 1)
	elseif def.Auto == "SealOffered" then
		return u.Seals[tostring(def.RefundSeal or 1)].Offered == true
	end
	return false
end

local function stepMark(def: any, u: any): number
	if def and def.Auto == "ShardsEarned" then
		return u.Stats.ShardsEarned
	elseif def and def.Auto == "CoffinOpened" then
		return u.Coffins.Opened
	end
	return 0
end

-- advance the onboarding by one step (grants the next step's Grant)
local function advanceTutorial(ctx: any, u: any)
	local t = u.Tutorial
	t.Step += 1
	local def = Rules.TutorialStep(t.Step, Cfg)
	if not def then
		t.Done = true
		ctx.C2Signal("C2Tutorial", { Step = t.Step, Done = true })
		return
	end
	t.Mark = stepMark(def, u)
	if def.Grant then
		if def.Grant.Keys then
			ctx.C2Reward({ Kind = "Key", Amount = def.Grant.Keys, Source = "Tutorial" })
		end
		if def.Grant.Shards then
			ctx.Shards(def.Grant.Shards, "Tutorial")
		end
	end
	ctx.C2Signal("C2Tutorial", { Step = t.Step, Done = false })
end

local function startTutorial(ctx: any, u: any)
	local t = u.Tutorial
	if t.Done or t.Step > 0 then
		return
	end
	t.Step = 0
	advanceTutorial(ctx, u)
end

local function autoTutorial(p: any, u: any, ctx: any)
	local t = u.Tutorial
	for _ = 1, #Cfg.Tutorial.Steps + 1 do
		if t.Done or t.Step < 1 then
			return
		end
		local def = Rules.TutorialStep(t.Step, Cfg)
		if not def then
			t.Done = true
			return
		end
		if not autoDone(def, p, u) then
			return
		end
		advanceTutorial(ctx, u)
	end
end

-- opts = Core.Transact opts (Dogs, Rows, Timeout, Silent, Refresh, Receipt) + EvenIfClosed (Studio / maintenance)
-- -> ok, result|err, raw, cached. fn(p, u, ctx, now) where u = p.Underyard (shaped, today's daily state).
function C2.Transact(player: Player, label: string, fn: (any, any, any, number) -> any, opts: { [string]: any }?): (boolean, any, any, boolean?)
	local o: { [string]: any } = opts or {}
	if not core then
		return false, C2.Closed
	end
	if not o.EvenIfClosed and not C2.Enabled() then
		return false, C2.Closed
	end
	local dogs = table.clone(o.Dogs or {})
	for _, id in ipairs(core.DogsOf(o.Rows)) do
		if not table.find(dogs, id) then
			table.insert(dogs, id)
		end
	end
	local ok, res, raw, cached = core.Transact(player, label, function(p, _h, cctx, now)
		local u = Feature.Shape(p)
		Feature.EnsureDaily(p, now)
		local ctx = makeCtx(player, p, u, cctx, now, dogs)
		if C2.Latch(p, u, now) then
			ctx.C2Signal("C2Reveal", { Chapter1 = true })
		end
		local result = fn(p, u, ctx, now)
		autoTutorial(p, u, ctx)
		if result == nil then
			result = {}
		end
		return result
	end, { Dogs = dogs, Rows = o.Rows, Timeout = o.Timeout, Silent = o.Silent, Refresh = o.Refresh,
		Receipt = o.Receipt, EvenIfDisabled = o.EvenIfDisabled })
	if ok and not cached and type(res) == "table" and type(res.View) == "table" then
		syncAttrs(player, res.View.Chapter2)
		local st = ram[player]
		if st then
			st.LastView = res.View
		end
	end
	return ok, res, raw, cached
end

-- reward rows in one transaction -> ok, granted rows (ctx.C2Reward outs), raw result
-- opts = {Source?, Journal?, Message?, Silent?, Timeout?, Receipt?, Dogs?}
function C2.Grant(player: Player, label: string, rows: { any }, opts: { [string]: any }?): (boolean, any, any)
	local o: { [string]: any } = opts or {}
	local ok, res = C2.Transact(player, label, function(_p, _u, ctx)
		local out = {}
		for _, row in ipairs(rows or {}) do
			if type(row) == "table" then
				local r = row
				if o.Source and r.Kind == "Shards" and not r.Source then
					r = table.clone(row)
					r.Source = o.Source
				end
				table.insert(out, ctx.C2Reward(r))
			end
		end
		if type(o.Journal) == "string" then
			ctx.Journal(o.Journal)
		end
		return { Message = o.Message, Rewards = out }
	end, { Rows = rows, Dogs = o.Dogs, Silent = o.Silent, Timeout = o.Timeout, Receipt = o.Receipt })
	if not ok then
		return false, res, nil
	end
	return true, type(res) == "table" and res.Rewards or {}, res
end

---------------------------------------------------------------------------------------------------------------------
-- Seals, trials, the Gravekeeper (called by Seals.luau / activity modules / Boss + BossFinale)
---------------------------------------------------------------------------------------------------------------------
local function numeral(i: number): string
	local seal = Cfg.Seals[i]
	return seal and seal.Numeral or tostring(i)
end

-- server-validated seal clear: first clear (First shards DR-exempt + key + rows + journal), repeat (Repeat shards, DR),
-- Gold first time (+GoldRewards). info = {Gold = bool, Score = n (higher is better), Time = s, RunId}
function C2.GrantSeal(player: Player, i: number, info: { [string]: any }?): (boolean, any)
	local inf: { [string]: any } = info or {}
	local seal = Cfg.Seals[i]
	if not seal then
		return false, "Unknown seal"
	end
	return C2.Transact(player, "C2Seal", function(_p, u, ctx, now)
		local s = u.Seals[tostring(i)]
		R().Check(s.Offered or s.Cleared, "Make the offering at the seal's altar first")
		local out = { Seal = i, First = false, Gold = false, Rewards = {} }
		local function add(row)
			table.insert(out.Rewards, ctx.C2Reward(row))
		end
		if not s.Cleared then
			s.Cleared, s.At, out.First = true, now, true
			add({ Kind = "Shards", Amount = seal.Rewards.First, Source = "First" })
			if (seal.Rewards.Keys or 0) > 0 then
				add({ Kind = "Key", Amount = seal.Rewards.Keys, Source = "Seal" })
			end
			for _, row in ipairs(seal.Rewards.Rows or {}) do
				add(row)
			end
			ctx.Journal("seal" .. i)
			ctx.C2Signal("C2Seal", { Seal = i, Stage = "Cleared", Rewards = table.clone(out.Rewards) })
			out.Message = "BELL SEAL " .. numeral(i) .. " BROKEN"
		else
			add({ Kind = "Shards", Amount = seal.Rewards.Repeat, Source = "Repeat" })
			ctx.C2Signal("C2Seal", { Seal = i, Stage = "Repeat", Rewards = table.clone(out.Rewards) })
			out.Message = "Trial cleared again"
		end
		if inf.Gold == true and not s.Gold then
			s.Gold, out.Gold = true, true
			local gold = {}
			if (seal.GoldRewards.Keys or 0) > 0 then
				table.insert(gold, ctx.C2Reward({ Kind = "Key", Amount = seal.GoldRewards.Keys, Source = "Gold" }))
			end
			for _, row in ipairs(seal.GoldRewards.Rows or {}) do
				table.insert(gold, ctx.C2Reward(row))
			end
			for _, g in ipairs(gold) do
				table.insert(out.Rewards, g)
			end
			ctx.C2Signal("C2Seal", { Seal = i, Stage = "Gold", Rewards = gold })
		end
		s.Best = math.max(s.Best, math.clamp(math.floor(tonumber(inf.Score) or 0), 0, 1e9))
		return out
	end, { Rows = seal.Rewards.Rows })
end

-- Black Coffin helpers (Coffin.luau): the price, and whether this opening is the onboarding's first coffin (step 3
-- forces the showcase-find group, Chapter2Config.Tutorial.ForceCoffinFind)
function C2.CoffinPrice(): any
	return Cfg.Coffin.Price
end

function C2.ForceCoffinFind(player: Player): boolean
	local step = Rules.TutorialStep(C2.TutorialStep(player), Cfg)
	return Cfg.Tutorial.ForceCoffinFind == true and step ~= nil and step.Event == "Coffin"
end

-- generic trial hook (contracts "Trial", Stats.Trials, resonance)
function C2.TrialCleared(player: Player, trialId: string, _info: any?)
	if type(trialId) == "string" then
		C2.Progress(player, "Trial", 1)
	end
end

-- THE GRAVEKEEPER for Chapter II players (call once per full-reward fighter, after the Chapter I reward):
-- info = {Finale = bool (difficulty V finale won)}. Shards per difficulty (DR "Boss"), first full clear key per
-- difficulty III-V, finale first / repeat rewards with the dog and skin rolls (§11.1). -> ok, result {Rewards}
function C2.BossReward(player: Player, difficulty: number, info: { [string]: any }?): (boolean, any)
	local inf: { [string]: any } = info or {}
	if not C2.Eligible(player) then
		return false, "Finish Chapter I first"
	end
	difficulty = math.clamp(math.floor(tonumber(difficulty) or 0), 1, 5)
	local fin = Cfg.Finale.Rewards
	local dogIds = {}
	for _, d in ipairs(fin.First.Dogs) do
		table.insert(dogIds, d.Id)
	end
	for _, d in ipairs(fin.Repeat.Dogs) do
		if not table.find(dogIds, d.Id) then
			table.insert(dogIds, d.Id)
		end
	end
	-- rolled before the write (dog supply keys must be declared); which table applies is decided inside
	local dogRoll, skinRoll, skinPick = rng:NextNumber(), rng:NextNumber(), rng:NextNumber()
	return C2.Transact(player, "C2Boss", function(_p, u, ctx)
		local out = { Rewards = {}, Difficulty = difficulty }
		local function add(row)
			table.insert(out.Rewards, ctx.C2Reward(row))
		end
		local shards = Cfg.BossRewards.Shards[difficulty]
		if shards then
			add({ Kind = "Shards", Amount = shards, Source = "Boss" })
		end
		local key = tostring(difficulty)
		if Cfg.BossRewards.FirstClearKeys[difficulty] and not u.Boss.FirstClears[key] then
			u.Boss.FirstClears[key] = true
			add({ Kind = "Key", Amount = Cfg.BossRewards.FirstClearKeys[difficulty], Source = "Boss" })
		end
		if inf.Finale == true then
			local first = not u.Boss.FirstClears.F
			local t = first and fin.First or fin.Repeat
			out.FinaleFirst = first
			u.Boss.FirstClears.F = true
			u.Boss.FinaleClears += 1
			add({ Kind = "Shards", Amount = t.Shards, Source = t.ShardSource })
			add({ Kind = "Key", Amount = t.Keys, Source = "Finale" })
			if t.Title then
				add({ Kind = "Title", Id = t.Title })
			end
			if t.Decor then
				add({ Kind = "Decor", Id = t.Decor })
			end
			-- one roll over the dog chances (rarest first)
			local x = dogRoll
			local sorted = table.clone(t.Dogs)
			table.sort(sorted, function(a, b)
				return a.Chance < b.Chance
			end)
			for _, d in ipairs(sorted) do
				if x < d.Chance then
					add({ Kind = "Dog", Id = d.Id, Rank = d.Rank })
					break
				end
				x -= d.Chance
			end
			if t.SkinChance and skinRoll < t.SkinChance then
				local pool = {}
				for _, id in ipairs(Cfg.Skins.Order) do
					if not Cfg.Skins.Defs[id].DexOnly then
						table.insert(pool, id)
					end
				end
				if #pool > 0 then
					add({ Kind = "Skin", Id = pool[math.clamp(1 + math.floor(skinPick * #pool), 1, #pool)] })
				end
			end
			ctx.Journal("finale")
		end
		return out
	end, { Dogs = dogIds })
end

---------------------------------------------------------------------------------------------------------------------
-- Progress queue (contracts + stats + resonance), Perfect streaks, the 1 s tick
---------------------------------------------------------------------------------------------------------------------
local function newQueue()
	return { Stat = {}, Shards = {}, Resonance = 0, Crown = 0 }
end

local function resonanceAdd(player: Player, points: number, statKey: string)
	local Res = modules and modules.Resonance
	if Res and type(Res.Add) == "function" and points > 0 then
		local ok, err = pcall(Res.Add, points, player, statKey)
		if not ok then
			warn("Chapter2: Resonance.Add failed: " .. tostring(err))
		end
	end
end

local function resonancePoints(player: Player, st: any, statKey: string, n: number): number
	local rc = Cfg.Resonance
	if statKey == "BossDamage" then
		st.BossRem += n
		local pts = math.floor(st.BossRem / rc.BossDamagePer)
		st.BossRem -= pts * rc.BossDamagePer
		return pts
	end
	local per = rc.Points[statKey]
	if not per then
		return 0
	end
	local pts = per * n
	if statKey == "Perfect" then
		local wolf = C2.Ability(player, "HW_BellkeeperWolf")
		if wolf then
			pts *= wolf.ResonancePerfectMult or 1
		end
	end
	return math.floor(pts)
end

-- statKeys: Perfect Streak Echo Ore Spirit Trial Door Revive Down BossDamage Coffin (contracts + stats + resonance).
-- Queued and written once per second. Only Chapter II players (latched Chapter I) count.
function C2.Progress(player: Player, statKey: string, n: number?)
	if not core or not C2.Enabled() or type(statKey) ~= "string" or not C2.Eligible(player) then
		return
	end
	local amount: number = tonumber(n) or 1
	if amount <= 0 or amount ~= amount then
		return
	end
	local st = stateOf(player)
	st.LastActive = os.clock()
	local q = st.Queue or newQueue()
	st.Queue = q
	if statKey ~= "Shards" then -- (Bell Shards contracts advance from the grants themselves)
		q.Stat[statKey] = (q.Stat[statKey] or 0) + amount
	end
	local pts = resonancePoints(player, st, statKey, amount)
	if pts > 0 then
		q.Resonance += pts
		resonanceAdd(player, pts, statKey)
	end
end

-- shards from a gameplay source, queued (DR applies at the write unless the source is exempt)
function C2.QueueShards(player: Player, n: number, source: string)
	if not core or not C2.Enabled() or not C2.Eligible(player) then
		return
	end
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then
		return
	end
	local st = stateOf(player)
	st.LastActive = os.clock()
	local q = st.Queue or newQueue()
	st.Queue = q
	q.Shards[source] = (q.Shards[source] or 0) + n
end

local function resonanceBuff(): number
	local st = Halloween:FindFirstChild("State")
	local res = st and st:FindFirstChild("Resonance")
	local untilAt = res and tonumber(res:GetAttribute("BuffUntil")) or 0
	if untilAt > os.time() then
		return Cfg.Resonance.Milestones[1].StreakBonus or 0
	end
	return 0
end

-- every judged hit on an Underyard Strike kind: Perfect streaks pay shards (every Streak.Every consecutive Perfects,
-- capped per minute, +25% under the RESONANT TOLL buff in the Underyard)
function C2.StreakHit(player: Player, perfect: boolean)
	if not core or not C2.Enabled() or not C2.Eligible(player) then
		return
	end
	local st = stateOf(player)
	local now = os.clock()
	local sc = Cfg.Streak
	if not perfect or now - st.StreakAt > sc.Timeout then
		st.Streak = 0
	end
	st.StreakAt = now
	st.LastActive = now
	if not perfect then
		return
	end
	st.Streak += 1
	C2.Progress(player, "Perfect", 1)
	if st.Streak % sc.Every ~= 0 then
		return
	end
	C2.Progress(player, "Streak", 1)
	if now - st.MinuteStart >= 60 then
		st.MinuteStart, st.MinuteShards = now, 0
	end
	local base = math.min(sc.Shards, math.max(0, sc.MinuteCap - st.MinuteShards))
	if base <= 0 then
		return
	end
	st.MinuteShards += base
	local bonus = C2.InUnderyard(player) and resonanceBuff() or 0
	st.Carry += base * (1 + bonus)
	local whole = math.floor(st.Carry + 1e-9)
	st.Carry -= whole
	C2.QueueShards(player, whole, "Streak")
end

local function applyQueue(ctx: any, u: any, q: any)
	for statKey, n in pairs(q.Stat) do
		local whole = math.floor(n)
		if whole > 0 then
			local stat = STAT_OF[statKey]
			if stat then
				ctx.C2Stat(stat, whole)
			end
			ctx.Contract(statKey, whole)
		end
	end
	if q.Resonance > 0 then
		u.Daily.Resonance += q.Resonance
		ctx.Contract("Resonance", q.Resonance)
	end
	for source, n in pairs(q.Shards) do
		ctx.Shards(n, source)
	end
	if q.Crown > 0 then
		-- H16 CROWN OF THE UNDERYARD: every ActiveMinutesPerRoll active minutes -> one extra showcase-find roll
		local def = Cfg.Dogs.Defs.HW_HollowKing
		local crown = u.Coffins.Crown
		crown.Seconds += q.Crown
		local per = def.ActiveMinutesPerRoll * 60
		while crown.Seconds >= per do
			crown.Seconds -= per
			crown.Rolls = math.min(9, crown.Rolls + (def.ExtraFindRolls or 1))
		end
	end
end

local function mergeQueue(into: any, q: any)
	for k, n in pairs(q.Stat) do
		into.Stat[k] = (into.Stat[k] or 0) + n
	end
	for k, n in pairs(q.Shards) do
		into.Shards[k] = (into.Shards[k] or 0) + n
	end
	into.Resonance += q.Resonance
	into.Crown += q.Crown
end

local function flushQueue(player: Player, st: any)
	local q = st.Queue
	if not q then
		return
	end
	st.Queue = nil
	local ok, err = C2.Transact(player, "C2Queue", function(_p, u, ctx)
		applyQueue(ctx, u, q)
	end, { Timeout = 2 })
	if not ok then
		if err == C2.Closed then
			return
		end
		if st.Queue then
			mergeQueue(st.Queue, q)
		else
			st.Queue = q
		end
		if type(err) == "string" and not string.find(err, "busy") and not string.find(err, "loading") then
			warn("Chapter2 queue flush failed: " .. err)
		end
	end
end

-- (yields) write this player's queued progress now (before a read that must see it, e.g. a coffin opening)
function C2.FlushNow(player: Player)
	local st = ram[player]
	if st and st.Queue then
		flushQueue(player, st)
	end
end

-- 1 s per-player tick hook (fn(player, dt) runs pcall'd for every ready player while Chapter II is on)
function C2.OnTick(fn: (Player, number) -> ())
	table.insert(tickFns, fn)
end

---------------------------------------------------------------------------------------------------------------------
-- Onboarding (§9): C2.TutorialEvent(player, key) completes the current step when its Event matches
---------------------------------------------------------------------------------------------------------------------
local function stepOfEvent(key: string): any
	for _, def in ipairs(Cfg.Tutorial.Steps) do
		if def.Event == key then
			return def
		end
	end
	return nil
end

-- (yields) the write of a tutorial event: completes the step when it is still the current one -> advanced
function C2.TutorialEventNow(player: Player, key: string): boolean
	local def = type(key) == "string" and stepOfEvent(key)
	if not def or not C2.Enabled() or C2.TutorialStep(player) ~= def.Id then
		return false
	end
	local st = stateOf(player)
	if st.InFlight["Tutorial" .. key] then
		return false
	end
	st.InFlight["Tutorial" .. key] = true
	local advanced = false
	pcall(C2.Transact, player, "C2Tutorial", function(_p, u, ctx)
		advanced = false
		if not u.Tutorial.Done and u.Tutorial.Step == def.Id then
			advanceTutorial(ctx, u)
			advanced = true
		end
		return {}
	end)
	st.InFlight["Tutorial" .. key] = nil
	return advanced
end

-- non-blocking: activity modules call this from Strike / trial callbacks
function C2.TutorialEvent(player: Player, key: string)
	local def = type(key) == "string" and stepOfEvent(key)
	if not def or not C2.Enabled() or C2.TutorialStep(player) ~= def.Id then
		return
	end
	task.spawn(C2.TutorialEventNow, player, key)
end

-- first descent (Underyard.Descend): Entered + journal "descend" + the onboarding starts
function C2.MarkEntered(player: Player): (boolean, any)
	return C2.Transact(player, "C2Enter", function(_p, u, ctx, now)
		local first = not u.Entered
		if first then
			u.Entered, u.FirstEnterAt = true, now
		end
		ctx.Journal("descend")
		startTutorial(ctx, u)
		return { First = first }
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------------------------------------------------
local function anchorPos(name: string): Vector3?
	local part = Layout.AnchorPart(name)
	if part then
		return part.Position
	end
	return Layout.Anchor(name)
end
C2.AnchorPos = anchorPos

local function near(player: Player, anchor: string, radius: number?): boolean
	local pos = anchorPos(anchor)
	return pos ~= nil and core.Near(player, pos, (radius or Cfg.Proximity.Radius) + SLACK)
end
C2.Near = near

local function request(action: string, cost: number, fn: (Player, any) -> (boolean, any), needsEligible: boolean?)
	core.OnRequest(action, function(player, args)
		if not C2.Enabled() then
			return false, C2.Closed
		end
		if needsEligible and not C2.Eligible(player) then
			return false, "Finish Chapter I first"
		end
		return fn(player, args)
	end, { Cost = cost })
end

local function intArg(v: any, lo: number, hi: number): number?
	local n = tonumber(v)
	if n == nil or n ~= n or n % 1 ~= 0 or n < lo or n > hi then
		return nil
	end
	return n
end

local function registerRequests()
	local Rl = R()

	request("C2Hello", 3, function(player)
		local ok, res = C2.Transact(player, "C2Hello", function()
			return {}
		end)
		if not ok then
			return false, res
		end
		res.Server = serverInfo()
		return true, res
	end)

	request("C2Notified", 2, function(player)
		return C2.Transact(player, "C2Notified", function(_p, u)
			Rl.Check(u.Chapter1.Complete, "Finish Chapter I first")
			u.Chapter1.Notified = true
			return { Message = "" }
		end)
	end)

	request("C2RevealSeen", 2, function(player, a)
		if a.Replay == true then
			return true, { Replay = true } -- replays never set flags
		end
		Rl.Check(core.Near(player, Layout.Church.Door, Cfg.Reveal.ChurchRadius + SLACK), "Come closer to the church")
		return C2.Transact(player, "C2RevealSeen", function(_p, u, ctx, now)
			Rl.Check(u.Chapter1.Complete, "Finish Chapter I first")
			if not u.RevealSeen then
				u.RevealSeen, u.RevealAt = true, now
			end
			u.Chapter1.Notified = true
			ctx.Journal("reveal")
			return { Message = "" }
		end)
	end)

	request("C2ContractClaim", 2, function(player, a)
		Rl.Check(type(a.Id) == "string" and #a.Id <= 40, "Invalid contract")
		return C2.Transact(player, "C2ContractClaim", function(_p, u, ctx)
			local row = nil
			for _, c in ipairs(u.Daily.Contracts.List) do
				if c.Id == a.Id then
					row = c
				end
			end
			Rl.Check(row ~= nil, "This contract is not part of today's list")
			Rl.Check(not row.Claimed, "Contract already claimed")
			Rl.Check(row.Progress >= row.Goal, "Contract not finished yet")
			row.Claimed = true
			local reward = ctx.C2Reward({ Kind = "Shards", Amount = Cfg.Contracts.Reward.Shards, Source = "Contract" })
			return { Message = "Contract reward claimed", Rewards = { reward } }
		end)
	end, true)

	request("C2ContractBonus", 3, function(player)
		return C2.Transact(player, "C2ContractBonus", function(_p, u, ctx)
			local c = u.Daily.Contracts
			Rl.Check(not c.AllClaimed, "Contract bonus already claimed today")
			Rl.Check(#c.List > 0, "Finish and claim every contract first")
			for _, row in ipairs(c.List) do
				Rl.Check(row.Claimed, "Finish and claim every contract first")
			end
			c.AllClaimed = true
			local reward = ctx.C2Reward({ Kind = "Key", Amount = Cfg.Contracts.Bonus.Keys, Source = "Contracts" })
			return { Message = "Contract bonus claimed", Rewards = { reward } }
		end)
	end, true)

	request("C2Exchange", 2, function(player, a)
		local n = intArg(a.Shards, 1, Cfg.Exchange.MaxPerRequest)
		Rl.Check(n ~= nil, "Choose how many shards to buy")
		Rl.Check(near(player, "TollBox"), "Come closer to the Toll Box")
		return C2.Transact(player, "C2Exchange", function(_p, u, ctx)
			local shards, candy = Rules.ExchangeQuote(n :: number, u.Daily.Exchange, Cfg)
			Rl.Check(shards > 0, "The Toll Box is full for today. Come back tomorrow!")
			ctx.Spend(candy)
			u.Daily.Exchange += shards
			local got = ctx.Shards(shards, "Exchange")
			return { Message = "Bell Shards bought", Shards = got, Candy = candy, Left = Cfg.Exchange.MaxPerDay - u.Daily.Exchange }
		end)
	end, true)

	request("C2SealOffer", 2, function(player, a)
		local i = intArg(a.Seal, 1, #Cfg.Seals)
		Rl.Check(i ~= nil, "Unknown seal")
		local seal = i :: number
		Rl.Check(near(player, "SealAltar_" .. seal), "Come closer to the seal's altar")
		return C2.Transact(player, "C2SealOffer", function(_p, u, ctx, now)
			local ok, why = Rules.CanOffer(u, seal, now, Cfg, phaseOverride)
			Rl.Check(ok, why or "Unknown seal")
			local cost = Rules.OfferingCost(seal, now, Cfg)
			local step = Rules.TutorialStep(u.Tutorial.Step, Cfg)
			local covered = 0
			if not u.Tutorial.Done and step and step.RefundSeal == seal and not u.Tutorial.Refunded then
				-- the onboarding refunds its first offering: the tutorial pays it (no dead end without shards)
				u.Tutorial.Refunded = true
				covered = cost
			else
				ctx.SpendShards(cost)
			end
			u.Seals[tostring(seal)].Offered = true
			ctx.C2Signal("C2Seal", { Seal = seal, Stage = "Offered", Rewards = {} })
			return { Message = "Offering accepted", Seal = seal, Cost = cost, Refunded = covered }
		end)
	end, true)

	request("C2DexClaim", 2, function(player, a)
		local count = intArg(a.Count, 1, #Cfg.Dogs.Order)
		local tier = count and Rules.Dex2Reward(count, Cfg)
		Rl.Check(tier ~= nil, "Invalid reward")
		return C2.Transact(player, "C2DexClaim", function(p, u, ctx)
			local key = tostring(tier.Count)
			Rl.Check(not u.Dex2Claims[key], "Reward already claimed")
			Rl.Check(Rules.Dex2Count(p, Cfg) >= tier.Count, "Discover more Underyard dogs first")
			u.Dex2Claims[key] = true
			local out = {}
			for _, row in ipairs(tier.Rows) do
				table.insert(out, ctx.C2Reward(row))
			end
			return { Message = "Dex II reward claimed", Count = tier.Count, Rewards = out }
		end, { Rows = tier.Rows })
	end, true)

	request("C2Craft", 3, function(player, a)
		local id = a.Id
		local cost, kind = Rules.CraftCost(id, Cfg)
		Rl.Check(cost ~= nil, kind or "Unknown cosmetic")
		return C2.Transact(player, "C2Craft", function(p, u, ctx)
			Rl.Check(u.Fragments >= (cost :: number), "Not enough fragments")
			if kind == "Decor" then
				local Catalog = require(RS:WaitForChild("DogEconomy"):WaitForChild("DecorCatalog"))
				Rl.Check(Catalog.MaxOwned(id) > 0, "This cosmetic is not available yet")
				Rl.Check(ctx.Decor(id), "You already own this cosmetic")
				u.Owned.Decor[id] = true
			else
				Rl.Check(Shared.Config.Skins.Names[id] ~= nil, "This cosmetic is not available yet")
				local h = p.Halloween
				Rl.Check(not (type(h) == "table" and type(h.Skins) == "table" and h.Skins[id]), "You already own this cosmetic")
				Rl.Check(ctx.Skin(id), "You already own this cosmetic")
			end
			u.Fragments -= cost :: number
			return { Message = "Cosmetic crafted", Id = id, Kind = kind, Cost = cost }
		end)
	end, true)

	request("C2Journal", 1, function(player, a)
		local key = a.Key
		Rl.Check(type(key) == "string" and #key <= 40, "Invalid entry")
		local view = C2.ViewOf(player)
		if view and type(view.JournalRead) == "table" and view.JournalRead[key] then
			return true, { Message = "", View = core.State(player) and core.State(player).View }
		end
		return C2.Transact(player, "C2Journal", function(_p, u)
			Rl.Check(u.Journal[key] ~= nil, "This entry is still locked")
			u.JournalRead[key] = true
			return { Message = "" }
		end)
	end)

	request("C2Tutorial", 1, function(player, a)
		if a.Skip == true then
			return C2.Transact(player, "C2Tutorial", function(_p, u, ctx)
				if not u.Tutorial.Done then
					u.Tutorial.Done = true
					ctx.C2Signal("C2Tutorial", { Step = u.Tutorial.Step, Done = true, Skipped = true })
				end
				return { Message = "Guide skipped" }
			end)
		end
		local step = intArg(a.Step, 1, #Cfg.Tutorial.Steps)
		Rl.Check(step ~= nil, "Invalid step")
		local def = Rules.TutorialStep(step :: number, Cfg)
		-- the practice ring (step 4) is checked here; the other steps complete from server events / profile state
		local practice = def and def.Event == "Practice" and C2.InPracticeRing(player)
		return C2.Transact(player, "C2Tutorial", function(p, u, ctx)
			Rl.Check(not u.Tutorial.Done and u.Tutorial.Step == step, "Invalid step")
			if practice or (def.Auto and autoDone(def, p, u)) then
				advanceTutorial(ctx, u)
				return { Message = "Step complete", Step = u.Tutorial.Step }
			end
			Rl.Check(false, "Finish this step first")
			return {}
		end)
	end, true)
end

function C2.InPracticeRing(player: Player): boolean
	local ring = Layout.Square.PracticeRing
	local root = core and core.Root(player)
	if not root then
		return false
	end
	local d = Vector3.new(root.Position.X - ring.Centre.X, 0, root.Position.Z - ring.Centre.Z).Magnitude
	return d <= ring.Radius + Cfg.Zone.PracticeSlack and math.abs(root.Position.Y - ring.Centre.Y) < 12
end

---------------------------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------------------------
local function ensureStateFolder()
	local st = Halloween:FindFirstChild("State")
	if not st then
		return
	end
	local f = st:FindFirstChild("Chapter2")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Chapter2"
		f.Parent = st
	end
	stateFolder = f :: Folder
end

local function join(player: Player)
	if not C2.Enabled() then
		return
	end
	stateOf(player)
	for attempt = 1, 4 do
		if not player.Parent then
			return
		end
		local ok = C2.Transact(player, "C2Join", function()
			return {}
		end)
		if ok then
			return
		end
		task.wait(3 * attempt)
	end
end

-- per-player 1 s work: attributes from the latest view, the Chapter I latch outside Chapter II writes, a new UTC day,
-- H16 active time, other modules' ticks, the queue
local function refresh(player: Player, st: any)
	if st.InFlight.Refresh or os.clock() - (st.RefreshAt or -1e9) < 5 then
		return
	end
	st.InFlight.Refresh, st.RefreshAt = true, os.clock()
	task.spawn(function()
		C2.Transact(player, "C2Refresh", function()
			return {}
		end, { Timeout = 2 })
		st.InFlight.Refresh = nil
	end)
end

local function tickPlayer(player: Player, st: any, dt: number)
	local cst = core.State(player)
	local view = cst and cst.View
	local c2 = type(view) == "table" and view.Chapter2 or nil
	if type(c2) == "table" then
		if view ~= st.LastView then
			st.LastView = view
			syncAttrs(player, c2)
		end
		-- no Chapter II data yet, Chapter I just finished in a Chapter I write, or a new UTC day without a write yet
		local today = Rules.Day(os.time())
		if c2.Fresh or (c2.Chapter1 and c2.Chapter1.Ready and not c2.Chapter1.Complete)
			or (C2.Eligible(player) and c2.Daily and c2.Daily.Day ~= today) then
			refresh(player, st)
		end
	end
	if C2.Eligible(player) and C2.InUnderyard(player) and core.IsActive(player) and C2.HasTeamDog(player, "HW_HollowKing") then
		st.Crown += dt
		if st.Crown >= 60 then
			local whole = math.floor(st.Crown)
			st.Crown -= whole
			local q = st.Queue or newQueue()
			st.Queue = q
			q.Crown += whole
		end
	end
	for _, fn in ipairs(tickFns) do
		local ok, err = pcall(fn, player, dt)
		if not ok then
			warn("Chapter2 tick hook failed: " .. tostring(err))
		end
	end
	if st.Queue then
		task.spawn(flushQueue, player, st)
	end
end

function C2.Start(c: any, m: any)
	core, modules = c, m
	ensureStateFolder()
	if stateFolder then
		stateFolder:SetAttribute("Enabled", C2.Enabled())
		stateFolder:SetAttribute("Start", Rules.StartUnix(Cfg))
	end
	-- requests are registered even when Chapter II is off: each answers "Chapter II is closed"
	registerRequests()
	if not C2.Enabled() then
		return
	end
	C2.PublishPhase()
	core.OnReady(function(player)
		task.spawn(join, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local st = ram[player]
		ram[player] = nil
		local q = st and st.Queue
		if q then
			pcall(C2.Transact, player, "C2Leave", function(_p, u, ctx)
				applyQueue(ctx, u, q)
			end, { Timeout = 0, Silent = true })
		end
	end)
	task.spawn(function()
		local last = os.clock()
		local phaseAt = 0
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = math.clamp(now - last, 0, 3)
			last = now
			if now - phaseAt >= 15 then
				phaseAt = now
				local ok, err = pcall(C2.PublishPhase)
				if not ok then
					warn("Chapter2 phase publish failed: " .. tostring(err))
				end
			end
			if C2.Enabled() then
				for player, cst in pairs(core.Players) do
					if cst.Ready and player.Parent then
						local ok, err = pcall(tickPlayer, player, stateOf(player), dt)
						if not ok then
							warn("Chapter2 tick failed: " .. tostring(err))
						end
					end
				end
			end
		end
	end)
end

return C2
