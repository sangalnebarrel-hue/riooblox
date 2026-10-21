--!nolint
-- BELL SEALS V-VII, BELL RESONANCE and the BLACK BELL ASSAULT (WP-J): lune run tests/seals_5_7.luau
-- * Seals2Rules (pure): door roll distribution + deals + moth hints, chests, Seal V steps, the hazard patterns of the door
--   challenge / Doorkeeper / Last Bell / Assault against the fairness rules (Hazards.Check, CheckPattern), choir loops and
--   flee, chain pulses, resonance goal + milestones.
-- * The real server modules (SealDoors, SealChoir, SealBell, Resonance) with the REAL Chapter2 + Seals framework on a fake
--   Core (transactions with rollback), fake Underyard / EventHP / Strike and a manual clock: door allowance + contract
--   bonus, Seal V counting incl. failed fights and the clear + Gold, the rare room grants, choir catch rules + flee + the
--   H13 hint, the bell trial waves, resonance goal scaling, milestones, the key cap, AFK exclusion and the assault life.
-- * Localization.Seals2: Russian for every server message, no key repeated from another dictionary or the base table.
local L = require("./lib/economy_env")
-- the modules' PlayerRemoving handlers, so a test can play a disconnect
local removing = {}
L.Stubs.Players.PlayerRemoving = { Connect = function(_, fn)
	table.insert(removing, fn)
	return { Disconnect = function() end }
end }
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Base = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local Rules = L.Require("ReplicatedStorage.Halloween.Chapter2Rules")
local Cfg = L.Require("ReplicatedStorage.Halloween.Seals2Config")
local SR = L.Require("ReplicatedStorage.Halloween.Seals2Rules")
local Hazards = L.Require("ReplicatedStorage.Halloween.Hazards")
local Layout = L.Require("ReplicatedStorage.Halloween.UnderyardLayout")
local F = L.Require("ServerScriptService.Economy.Features.Underyard")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > eps then
		error((msg or "") .. string.format(" expected %.5f got %.5f", b, a), 2)
	end
end
local Rstub = { Check = function(ok, msg)
	if not ok then
		error(msg, 0)
	end
end }

local DAY = 86400
local START = Rules.UnixFromDate(2026, 10, 20)
local NOW = START + 6 * DAY + 3600 -- Oct 26 01:00 UTC: every seal open
L.Time = NOW

-- deterministic number streams
local function lcg(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
local function seq(list)
	local i = 0
	return function()
		i += 1
		return list[(i - 1) % #list + 1]
	end
end
local function deep(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[k] = deep(x)
	end
	return o
end

local COURT = Layout.Crooked.Court.Centre
local ARENA = Layout.Arena.Centre
local TRIAL_CFG = { Trial = true }

---------------------------------------------------------------------------------------------------------------------
-- pure rules
---------------------------------------------------------------------------------------------------------------------
test("door roll: 40 / 30 / 20 / 10 over the weights, exact boundaries", function()
	eq(SR.PickOutcome(0, Base), "Reward")
	eq(SR.PickOutcome(.3999, Base), "Reward")
	eq(SR.PickOutcome(.4001, Base), "Challenge")
	eq(SR.PickOutcome(.6999, Base), "Challenge")
	eq(SR.PickOutcome(.7001, Base), "MiniBoss")
	eq(SR.PickOutcome(.8999, Base), "MiniBoss")
	eq(SR.PickOutcome(.9001, Base), "Rare")
	eq(SR.PickOutcome(1, Base), "Rare")
	local counts = { Reward = 0, Challenge = 0, MiniBoss = 0, Rare = 0 }
	local rng = lcg(4242)
	local N = 200000
	for _ = 1, N do
		local d = SR.NewDeal(rng, Base, { Count = 4 })
		counts[d.Doors[1 + math.floor(rng() * 4)]] += 1
	end
	near(counts.Reward / N, .40, .005, "Reward")
	near(counts.Challenge / N, .30, .005, "Challenge")
	near(counts.MiniBoss / N, .20, .005, "MiniBoss")
	near(counts.Rare / N, .10, .004, "Rare")
end)

test("deals: H13 moth hint only on a reward door, at 35% x P(a reward door exists)", function()
	local rng = lcg(77)
	local N, hints = 100000, 0
	for _ = 1, N do
		local d = SR.NewDeal(rng, Base, { Moth = true, Count = 4 })
		truthy(d.MothRolled, "moth rolled")
		if d.Hint then
			hints += 1
			eq(d.Doors[d.Hint], "Reward", "the moth marks a reward door")
		end
	end
	local expect = Base.Doors.MothChance * (1 - (1 - .4) ^ 4)
	near(hints / N, expect, .006, "hint rate")
	for _ = 1, 2000 do
		local d = SR.NewDeal(rng, Base, { Count = 4 })
		eq(d.Hint, nil, "no hint without the Moth Hound")
		eq(d.MothRolled, false)
	end
end)

test("chests: reward rows, challenge / mini boss rows, the hidden room (find + key + dust, 0.5% Hollow King)", function()
	local rng = lcg(9)
	local keys, finds, N = 0, 0, 40000
	for _ = 1, N do
		local rows = SR.RewardChest(rng, Base)
		eq(rows[1].Kind, "Shards")
		truthy(rows[1].Amount >= 30 and rows[1].Amount <= 80, "shards 30-80")
		eq(rows[1].Source, "Door")
		eq(rows[2].Kind, "Dust")
		for _, r in ipairs(rows) do
			if r.Kind == "Key" then
				keys += 1
			elseif r.Kind == "Find" then
				finds += 1
				truthy(Base.Finds.Defs[r.Id], "a real find id")
			end
		end
	end
	near(keys / N, .15, .01, "15% key")
	near(finds / N, Base.Doors.Reward.FindChance, .006, "find chance")
	local ch = SR.ChallengeRewards(rng, Base)
	truthy(ch[1].Kind == "Shards" and ch[1].Amount >= 30 and ch[1].Amount <= 60 and ch[2].Kind == "Dust", "challenge rows")
	local mb = SR.MiniBossRewards(rng, Base)
	truthy(mb[1].Amount >= 40 and mb[1].Amount <= 80, "mini boss shards")
	local kings = 0
	for _ = 1, 200000 do
		local rr = SR.RareRoom(rng, Base)
		eq(#rr.Chests, 3)
		local kinds = {}
		for _, list in ipairs(rr.Chests) do
			for _, r in ipairs(list) do
				kinds[r.Kind] = (kinds[r.Kind] or 0) + 1
			end
		end
		truthy(kinds.Find == 1 and kinds.Key == 1 and kinds.Dust == 1, "find + key + dust")
		if rr.HollowKing then
			kings += 1
			eq(kinds.Dog, 1)
		end
	end
	near(kings / 200000, .005, .0007, "H16 0.5%")
end)

test("Seal V steps: every 3 outcomes is one clear (first, then repeats); counting rules", function()
	local p, due = SR.SealStep(0, 1, 3)
	eq(p, 1)
	eq(due, 0)
	p, due = SR.SealStep(2, 1, 3)
	eq(p, 3)
	eq(due, 1)
	p, due = SR.SealStep(5, 1, 3)
	eq(due, 1)
	eq(SR.Counts("Reward"), true)
	eq(SR.Counts("Rare"), true)
	eq(SR.Counts("Challenge", false), false)
	eq(SR.Counts("Challenge", true), true)
	eq(SR.Counts("MiniBoss", false), false)
	eq(SR.Counts("MiniBoss", true), true)
	local u = { Daily = { Day = 5, Doors = 2, Contracts = { AllClaimed = false } } }
	eq(SR.DoorsLeft(u, Base, 5), 1)
	u.Daily.Contracts.AllClaimed = true
	eq(SR.DoorsLeft(u, Base, 5), 2, "contract bonus")
	eq(SR.DoorsLeft(u, Base, 6), 4, "a new day")
end)

local function checkDefs(defs, what, cfg)
	for _, d in ipairs(defs) do
		local ok, problems = Hazards.Check(d, cfg or TRIAL_CFG)
		truthy(ok, what .. ": " .. table.concat(problems, "; "))
		truthy(Hazards.TypeOf(d.Shape) ~= nil, what .. " shape")
	end
end

test("fairness: every door challenge wave is fair and leaves a safe spot in the court", function()
	local rng = lcg(31)
	local CH = Cfg.Doors.Challenge
	local court = { Center = COURT, Radius = CH.Radius }
	for _, kind in ipairs({ "Stomp", "Cross", "Ripple", "Lanes", "Finale" }) do
		for k = 1, 60 do
			local player = COURT + Vector3.new((rng() - .5) * 40, 0, (rng() - .5) * 40)
			local t = (k % 25)
			local defs = SR.ChallengeWave(kind, court, player, t, CH, rng, 25)
			truthy(#defs > 0, kind .. " made hazards")
			checkDefs(defs, "challenge " .. kind)
			for _, d in ipairs(defs) do
				truthy(d.Damage <= Hazards.HitCap(TRIAL_CFG), "trial cap")
				if d.Telegraph then
					truthy(d.Telegraph >= .9, "telegraph")
				end
			end
			if kind ~= "Finale" then
				local ok, frac = Hazards.CheckPattern(defs, { Center = COURT, Radius = CH.Radius, Step = 2 })
				truthy(ok and frac > .15, kind .. " leaves room to dodge (" .. frac .. ")")
			else
				truthy(Hazards.PathSpeed(defs[1].Shape) <= 11, "the safe circle moves <= 11 studs/s")
			end
		end
	end
	-- the kind cycle never repeats a kind back to back
	local prev = nil
	for _ = 1, 200 do
		local k = SR.ChallengeKind(prev, rng)
		truthy(k ~= prev, "no repeat")
		prev = k
	end
end)

test("fairness: Doorkeeper attacks, Last Bell tolls / volleys and Assault patterns", function()
	local rng = lcg(5)
	local DK = Cfg.Doors.Doorkeeper
	for _, kind in ipairs({ "Slam", "Sweep", "Ring", "Charge" }) do
		local defs = SR.DoorkeeperAttack(kind, COURT, COURT + Vector3.new(6, 0, 8), DK, rng, COURT + Vector3.new(-8, 0, 3))
		truthy(#defs >= 1, kind)
		checkDefs(defs, "doorkeeper " .. kind)
		local ok = Hazards.CheckPattern(defs, { Center = COURT, Radius = 26 })
		truthy(ok, kind .. " safe spot")
	end
	local rc = Cfg.Bell.Rings
	for k = 1, 40 do
		local defs = SR.Toll(ARENA, { Bands = rc.Bands, Gaps = rc.Gaps, GapWidth = rc.GapWidth, GapTurn = rc.GapTurn, Stagger = rc.Stagger,
			Telegraph = rc.Telegraph, Damage = Base.Seals[7].Activity.ShockwaveDamage, Start = k * 37 })
		eq(#defs, #rc.Bands)
		checkDefs(defs, "toll")
		for i, d in ipairs(defs) do
			truthy(Hazards.GapStuds(d.Shape) >= 6, "a doorway a dog fits through")
			near(d.Delay, (i - 1) * rc.Stagger, 1e-9, "bands expand")
		end
		local ok, frac = Hazards.CheckPattern(defs, { Center = ARENA, Radius = Layout.Arena.Radius, Step = 2 })
		truthy(ok and frac > .2, "toll leaves safe channels")
	end
	local fighters = {}
	for i = 1, 6 do
		table.insert(fighters, ARENA + Vector3.new(math.cos(i) * 20, 0, math.sin(i) * 20))
	end
	for _ = 1, 30 do
		local defs = SR.Burn(Layout.Arena.Bellkeeper, fighters, Cfg.Bell.Burn, rng)
		checkDefs(defs, "burn")
		truthy(Hazards.CheckPattern(defs, { Center = ARENA, Radius = Layout.Arena.Radius }), "burn safe spot")
		local AC = Cfg.Resonance.Assault
		checkDefs(SR.Burn(Layout.Arena.Bellkeeper, fighters, { Line = AC.Line, Circle = { Max = 0 } }, rng), "assault lines")
		checkDefs(SR.Burn(Layout.Arena.Bellkeeper, fighters, { Line = { Count = 0 }, Circle = AC.Circle }, rng), "assault circles")
	end
end)

test("chains: need / weak HP by fighters, the bright part of a pulse (+ grace)", function()
	local act = Base.Seals[7].Activity
	eq(SR.ChainNeed(1, act), 6)
	eq(SR.ChainNeed(3, act), 12)
	eq(SR.WeakHP(1, act), 30)
	eq(SR.WeakHP(4, act), 60)
	local P, B = act.PulsePeriod, Cfg.Bell.Chains.Bright
	truthy(SR.PulseBright(100, 100, P, B, 0), "pulse start")
	truthy(SR.PulseBright(100 + P * B - .01, 100, P, B, 0), "end of the bright part")
	truthy(not SR.PulseBright(100 + P * B + .05, 100, P, B, 0), "dark part")
	truthy(SR.PulseBright(100 + P * B + .05, 100, P, B, .15), "latency grace")
	truthy(not SR.PulseBright(100 + P * .95, 100, P, B, .15), "late in the dark part")
	truthy(SR.PulseBright(100 + 3 * P + .1, 100, P, B, 0), "every pulse")
	truthy(not SR.PulseBright(99, 100, P, B, .15), "before the chain rang")
end)

test("choir: loops, flee away from the hitter by the flee distance, singing schedule, routes", function()
	local pts = { Vector3.new(0, 3, 0), Vector3.new(30, 3, 0), Vector3.new(30, 3, 40) }
	local total = SR.LoopLength(pts)
	eq(total, 30 + 40 + 50)
	local p = SR.LoopAt(pts, 45)
	near(p.X, 30, 1e-6)
	near(p.Z, 15, 1e-6)
	-- a player on the far side: the spirit flees forward / backward, whichever ends farther
	local s, pos = SR.Flee(pts, 10, Vector3.new(-5, 0, 0), 25)
	eq(s, 35, "away from a player behind it")
	near(pos.X, 30, 1e-6)
	s = SR.Flee(pts, 10, Vector3.new(40, 0, 0), 25)
	near(s, (10 - 25) % total, 1e-6, "back the other way")
	eq(SR.Judge(2), "Catch")
	eq(SR.Judge(1), "Flee")
	local CC = Cfg.Choir
	local t1 = SR.SingAt(1, 1000, CC, 7, 1000)
	local t2 = SR.SingAt(2, 1000, CC, 7, 1000)
	near(t2 - t1, CC.SingEvery / 7, 1e-9, "the melody is staggered")
	truthy(SR.SingAt(3, 1000, CC, 7, 1100) >= 1100, "next note in the future")
	local all = SR.Routes(function()
		return true
	end, CC)
	eq(#all, 7)
	local some = SR.Routes(function(d)
		return d == "BellSquare"
	end, CC)
	for _, r in ipairs(some) do
		eq(r.District, "BellSquare", "locked districts fall back to the ring road")
	end
	for _, r in ipairs(CC.Routes) do
		for _, i in ipairs(r.Points) do
			truthy(Layout.ChoirPaths[i], "path point " .. i)
		end
	end
	eq(#CC.Melody, Base.Choir.Spirits)
end)

test("resonance: goal scaling, milestones (once, in order), assault HP / phases", function()
	eq(SR.Goal(0, Base), 2400, "x .6")
	eq(SR.Goal(3, Base), 2400)
	eq(SR.Goal(6, Base), 4000)
	eq(SR.Goal(9, Base), 6000)
	eq(SR.Goal(12, Base), 8000)
	eq(SR.Goal(40, Base), 8000, "x 2")
	eq(SR.Milestone(0, 4000, Base), 0)
	eq(SR.Milestone(999, 4000, Base), 0)
	eq(SR.Milestone(1000, 4000, Base), 1)
	eq(SR.Milestone(3000, 4000, Base), 3)
	eq(SR.Milestone(4000, 4000, Base), 4)
	local new = SR.NewMilestones(1, 3100, 4000, Base)
	eq(#new, 2)
	eq(new[1], 2)
	eq(new[2], 3)
	eq(#SR.NewMilestones(3, 3100, 4000, Base), 0, "never twice")
	eq(SR.AssaultMaxHP(1, Base), 400)
	eq(SR.AssaultMaxHP(5, Base), 2000)
	local AC = Cfg.Resonance.Assault
	eq(SR.AssaultPhase(1, AC), 1)
	eq(SR.AssaultPhase(.5, AC), 2)
	eq(SR.AssaultPhase(.1, AC), 3)
end)

---------------------------------------------------------------------------------------------------------------------
-- the server modules on a fake Core
---------------------------------------------------------------------------------------------------------------------
local itemDefs = {}
for _, id in ipairs(Base.Finds.Order) do
	itemDefs[id] = { Id = id, BaseDropChance = 1e-3 }
end
L.Overrides["ServerScriptService/Economy/ItemRules"] = {
	Definitions = itemDefs,
	Free = function()
		return true
	end,
}
L.Overrides["ReplicatedStorage/DogEconomy/DecorCatalog"] = { MaxOwned = function(id)
	return Base.Decor.Defs[id] and 1 or 0
end }
local C2 = L.Require("ServerScriptService.Halloween.Chapter2")
local clock = 1000
-- the Seals framework reads os.clock for its start cooldown: load it with the test's manual clock
local SealsMod
do
	local luau = require("@lune/luau")
	local path = "ServerScriptService/Halloween/Seals"
	local env = setmetatable({
		script = L.Game:FindFirstChild("ServerScriptService"):FindFirstChild("Halloween"):FindFirstChild("Seals"),
		game = L.Game,
		workspace = { GetServerTimeNow = function()
			return L.Time
		end },
		require = function(node)
			return L.Require((string.gsub(L.Paths[node], "/", ".")))
		end,
		os = setmetatable({ clock = function()
			return clock
		end, time = function()
			return math.floor(L.Time)
		end }, { __index = os }),
		task = { wait = function() end, spawn = function() end, defer = function() end, delay = function() end },
		warn = function(...)
			if L.Verbose then
				print("warn:", ...)
			end
		end,
		Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, Instance = roblox.Instance, typeof = typeof, Random = L.Random,
	}, { __index = _G })
	SealsMod = luau.load(fs.readFile("src/" .. path .. ".luau"), { debugName = path, environment = env })()
end
local Doors = L.Require("ServerScriptService.Halloween.SealDoors")
local Choir = L.Require("ServerScriptService.Halloween.SealChoir")
local Bell = L.Require("ServerScriptService.Halloween.SealBell")
local Res = L.Require("ServerScriptService.Halloween.Resonance")
local HConfig = L.Require("ReplicatedStorage.Halloween.Config")
local H = L.Require("ServerScriptService.Economy.Features.Halloween")

local function advance(dt)
	clock += dt
	L.Time += dt
end
local delays = {}
local function runDelays()
	local list = delays
	delays = {}
	for _, d in ipairs(list) do
		d.Fn(table.unpack(d.Args, 1, d.Args.n))
	end
end
for _, M in ipairs({ Doors, Choir, Bell, Res }) do
	M.Clock = function()
		return clock
	end
	M.Now = function()
		return L.Time
	end
end
Res.Unix = function()
	return math.floor(L.Time)
end
local roll = lcg(2024)
for _, M in ipairs({ Doors, Choir, Bell, Res }) do
	M.Roll = function()
		return roll()
	end
end
Doors.Spawn = function(fn, ...)
	fn(...)
end
Res.Spawn = Doors.Spawn
Doors.Delay = function(t, fn, ...)
	table.insert(delays, { T = t, Fn = fn, Args = table.pack(...) })
end
Res.Delay = Doors.Delay
Doors.Wait = function() end

local players = {}
local posOf = {}
local function fakePlayer(uid)
	local attrs = {}
	local pl = { UserId = uid, Name = "P" .. uid, DisplayName = "Player" .. uid, Parent = true, Attrs = attrs,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end }
	table.insert(players, pl)
	return pl
end
L.Stubs.Players.GetPlayers = function()
	return players
end
L.Stubs.Players.GetPlayerByUserId = function(_, uid)
	for _, pl in ipairs(players) do
		if pl.UserId == uid then
			return pl
		end
	end
	return nil
end

local profiles, signals, handlers = {}, {}, {}
local views = {}
local core = {
	Players = {},
	Rules = { Check = Rstub.Check, Free = function()
		return true
	end },
	Runtime = { Engine = { AssetReady = function()
		return true
	end }, Views = views },
	DogsOf = function(rows)
		local out = {}
		for _, row in ipairs(rows or {}) do
			if type(row) == "table" and row.Kind == "Dog" and not table.find(out, row.Id) then
				table.insert(out, row.Id)
			end
		end
		return out
	end,
	SetAttr = function(inst, k, v)
		inst:SetAttribute(k, v)
	end,
	Signal = function(target, kind, data)
		table.insert(signals, { Target = target, Kind = kind, Data = data })
	end,
	OnRequest = function(action, fn)
		handlers[action] = fn
	end,
	OnReady = function() end,
	Near = function(player, pos, range)
		local p = posOf[player]
		return p ~= nil and (p - pos).Magnitude <= range
	end,
	Root = function(player)
		local p = posOf[player]
		return p and { Position = p } or nil
	end,
	IsActive = function()
		return true
	end,
}
function core.State(player)
	return core.Players[player]
end
function core.Transact(player, label, fn, opts)
	opts = opts or {}
	local p = profiles[player.UserId]
	local backup = deep(p)
	local after = {}
	local declared = table.clone(opts.Dogs or {})
	local ok, res = pcall(function()
		local h = H.Shape(p)
		local ctx = { Touched = false }
		function ctx.After(f)
			table.insert(after, f)
		end
		function ctx.Item(o)
			p.Items = p.Items or {}
			local x = { ItemId = o.ItemId, Uid = tostring(#p.Items + 1), Origin = o.Origin }
			table.insert(p.Items, x)
			return deep(x)
		end
		function ctx.Decor()
			return true
		end
		function ctx.Skin()
			return true
		end
		function ctx.Dog(id)
			Rstub.Check(table.find(declared, id) ~= nil, "Dog grant not declared")
			p.Dogs = p.Dogs or {}
			local uid = "D" .. tostring(#p.Dogs + 1)
			p.Dogs[uid] = { DogUid = uid, DogId = id }
			return { DogUid = uid, DogId = id }
		end
		function ctx.Candy(n)
			h.Candy += n
			return n
		end
		function ctx.Stat() end
		function ctx.Spend(n)
			h.Candy -= n
		end
		function ctx.Bones(n)
			return n
		end
		function ctx.Coins(n)
			return type(n) == "number" and n or 50000
		end
		local r = fn(p, h, ctx, L.Time)
		F.Validate(Rstub, p)
		return r
	end)
	if not ok then
		profiles[player.UserId] = backup
		return false, res
	end
	local view = H.View(p, L.Time)
	if type(res) == "table" and res.View == nil then
		res.View = view
	end
	core.Players[player] = core.Players[player] or { Ready = true }
	core.Players[player].View = view
	for _, f in ipairs(after) do
		f()
	end
	return true, res, nil, false
end

-- Underyard (zone) fake: districts by test, real seal gating, prompts recorded, teleports move the player
local UY = { Prompts = {}, Teleports = {}, Allow = {}, Dist = {}, Out = {} }
function UY.InZone(pl)
	return UY.Out[pl] ~= true
end
function UY.District(pl)
	return UY.Dist[pl] or "BellSquare"
end
function UY.Players()
	local out = {}
	for _, pl in ipairs(players) do
		if UY.Out[pl] ~= true then
			table.insert(out, pl)
		end
	end
	return out
end
function UY.Unlocked(pl, d)
	if Rules.DistrictUnlocked(C2.ClearedCount(pl), d, Layout.Unlock) then
		return true
	end
	local run = SealsMod.RunOf(pl)
	if run and run.State == "Running" and run.Def and (run.Def.District == d or run.Def.District == "*") then
		return true
	end
	for _, fn in ipairs(UY.Allow) do
		if fn(pl, d) == true then
			return true
		end
	end
	return false
end
function UY.Prompt(anchor, props, fn)
	UY.Prompts[anchor] = { Props = props, Fn = fn }
	return {}
end
function UY.Teleport(pl, cf)
	table.insert(UY.Teleports, { Player = pl, CF = cf })
	posOf[pl] = cf.Position
	return true
end
function UY.AllowDistrict(fn)
	table.insert(UY.Allow, fn)
end
function UY.Root()
	return nil
end

-- EventHP fake
local HP = { Zones = {}, States = {}, Waves = {}, Downed = {}, BleedFns = {}, Spawns = {} }
local function zoneOf(z)
	HP.Zones[z] = HP.Zones[z] or { Members = {}, Hazards = {} }
	return HP.Zones[z]
end
function HP.SetZone(z, opts)
	zoneOf(z).Opts = opts
	return zoneOf(z)
end
function HP.Enter(pl, z)
	if HP.States[pl] and HP.States[pl] ~= z then
		HP.Leave(pl)
	end
	HP.States[pl] = z
	zoneOf(z).Members[pl] = true
	return true
end
function HP.Leave(pl, z)
	local cur = HP.States[pl]
	if not cur or (z ~= nil and cur ~= z) then
		return false
	end
	HP.Zones[cur].Members[pl] = nil
	HP.States[pl] = nil
	HP.Downed[pl] = nil
	return true
end
function HP.InCombat(pl)
	return HP.States[pl] ~= nil
end
function HP.IsDowned(pl)
	return HP.Downed[pl] == true
end
function HP.CanTarget(pl)
	return HP.States[pl] ~= nil and not HP.Downed[pl]
end
function HP.Players(z)
	local out = {}
	for pl in pairs(zoneOf(z).Members) do
		table.insert(out, pl)
	end
	return out
end
function HP.HazardWave(z, defs)
	table.insert(HP.Waves, { Zone = z, Defs = defs })
	return {}
end
function HP.Hazard(z, def)
	table.insert(HP.Waves, { Zone = z, Defs = { def } })
	return 1
end
function HP.CancelHazards(z)
	HP.Cancelled = z
	return 0
end
function HP.OnBleedOut(fn)
	table.insert(HP.BleedFns, fn)
end
function HP.DamageMult()
	return 1
end

-- Strike fake (the same judge order as Strike.Hit: CanHit -> damage mode -> OnHit -> apply -> OnBreak)
local Strike = { Kinds = {}, Targets = {}, Sessions = {}, NextId = 0 }
function Strike.Register(kind, def)
	def.Kind = kind
	Strike.Kinds[kind] = def
	return def
end
function Strike.Add(t)
	Strike.NextId += 1
	local cf = t.CFrame or CFrame.new(t.Position or Vector3.new())
	local target = { Id = Strike.NextId, Kind = t.Kind, Def = Strike.Kinds[t.Kind], HP = t.HP or t.MaxHP or 1, MaxHP = t.MaxHP or t.HP or 1,
		Unit = t.Unit or 1, Position = cf.Position, Data = t.Data or {}, Alive = true, Contributors = {}, Attrs = t.Attributes or {} }
	Strike.Targets[target.Id] = target
	return target
end
function Strike.Move(target, cf)
	target.Position = cf.Position
end
function Strike.Remove(target, reason)
	target.Alive = false
	target.Removed = reason or "Removed"
	Strike.Targets[target.Id] = nil
end
function Strike.SetHP(target, hp, max)
	target.MaxHP = max or target.MaxHP
	target.HP = hp
end
function Strike.All(kind)
	local out = {}
	for _, t in pairs(Strike.Targets) do
		if not kind or t.Kind == kind then
			table.insert(out, t)
		end
	end
	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)
	return out
end
local function hit(player, target, quality, power)
	local def = target.Def
	if not target.Alive then
		return false, "HW:GONE"
	end
	if def.CanHit then
		local ok, err = def.CanHit(player, target)
		if not ok then
			return false, err
		end
	end
	local h = { Quality = quality, Damage = power or 1, Power = power or 1, Crit = false, Player = player }
	local mode = def.Damage
	if type(mode) == "function" then
		h.Applied = mode(player, target, h)
	elseif mode == "Power" then
		h.Applied = h.Power * target.Unit
	else
		h.Applied = h.Damage
	end
	local extra = def.OnHit and def.OnHit(player, target, h) or nil
	if not target.Alive then
		return true, { Extra = extra, Broke = true }
	end
	local applied = math.clamp(tonumber(h.Applied) or 0, 0, target.HP)
	target.HP -= applied
	local c = target.Contributors[player.UserId] or { Player = player, Damage = 0, Hits = 0 }
	target.Contributors[player.UserId] = c
	c.Hits += 1
	c.Damage += applied
	local broke = false
	if target.HP <= 1e-6 then
		broke = true
		target.Alive = false
		if def.OnBreak then
			def.OnBreak(player, target, { Contributors = target.Contributors, Killer = player })
		end
		if def.Remove ~= false then
			Strike.Remove(target, "Broke")
		end
	end
	return true, { Extra = extra, Damage = applied, Broke = broke }
end

local modules = { Chapter2 = C2, Underyard = UY, EventHP = HP, Strike = Strike, SealDoors = Doors, SealChoir = Choir,
	SealBell = Bell, Resonance = Res }
modules.Seals = SealsMod
C2.Start(core, modules)
SealsMod.Start(core, modules)
Doors.Start(core, modules)
Choir.Start(core, modules)
Bell.Start(core, modules)
Res.Start(core, modules)

local function newPlayer(uid, cleared)
	local pl = fakePlayer(uid)
	local p = { UserId = uid, Resources = { BellShards = 5000 }, Cosmetics = {}, Halloween = { Season = HConfig.Season, Candy = 0, Skins = {},
		Boss = { Best = 2 }, Cauldron = { Invested = 300 }, Stats = { Knocks = 7, BloodMoons = 1, Spots = 10 } } }
	profiles[uid] = p
	handlers.C2Hello(pl, {})
	local u = profiles[uid].Underyard
	u.Tutorial.Done = true
	u.Rested.Pool = 0
	for i = 1, cleared do
		u.Seals[tostring(i)].Offered = true
		u.Seals[tostring(i)].Cleared = true
	end
	handlers.C2Hello(pl, {})
	return pl
end
local function U(pl)
	return profiles[pl.UserId].Underyard
end
local function signalsOf(kind, filter)
	local out = {}
	for _, s in ipairs(signals) do
		if s.Kind == kind and (not filter or filter(s)) then
			table.insert(out, s)
		end
	end
	return out
end
local function tickRun(run, seconds, dt)
	dt = dt or .1
	local t = 0
	while t < seconds and run.State == "Running" do
		advance(dt)
		t += dt
		if run.Def.OnTick then
			run.Def.OnTick(run, dt)
		end
	end
end
local function doorPos(i)
	return Layout.Anchor("Door_" .. i)
end
local function setDeal(pl, doors, hint)
	local st = Doors.StateOf(pl)
	st.Deal = { Doors = doors, Hint = hint, MothRolled = hint ~= nil }
	st.DealAt = clock
end
local function open(pl, i)
	posOf[pl] = doorPos(i) + Vector3.new(0, 0, 4)
	UY.Dist[pl] = "CrookedRow"
	advance(Cfg.Doors.Cooldown + .1)
	return Doors.Open(pl, i)
end

test("doors: prompts, allowance 3 per day (+1 with all contracts claimed), refusals", function()
	for i = 1, 4 do
		truthy(UY.Prompts["Door_" .. i], "door prompt " .. i)
	end
	for i = 1, 3 do
		truthy(UY.Prompts["RareChest_" .. i], "chest prompt " .. i)
	end
	truthy(handlers.C2DoorState, "C2DoorState request")
	local pl = newPlayer(501, 4)
	local ok, err = Doors.Open(pl, 1)
	eq(ok, false)
	posOf[pl] = doorPos(1) + Vector3.new(0, 0, 40)
	UY.Dist[pl] = "CrookedRow"
	advance(5)
	ok, err = Doors.Open(pl, 1)
	eq(err, "Walk up to the door")
	for k = 1, 3 do
		setDeal(pl, { "Reward", "Reward", "Reward", "Reward" })
		ok, err = open(pl, k)
		truthy(ok, "opening " .. k .. ": " .. tostring(err))
	end
	eq(U(pl).Daily.Doors, 3)
	eq(pl.Attrs.UyDoorsLeft, 0)
	setDeal(pl, { "Reward", "Reward", "Reward", "Reward" })
	ok, err = open(pl, 4)
	eq(ok, false)
	eq(err, "No Crooked Door openings left today")
	-- all of today's contracts claimed: +1
	U(pl).Daily.Contracts.AllClaimed = true
	ok, err = open(pl, 4)
	truthy(ok, tostring(err))
	eq(U(pl).Daily.Doors, 4)
	ok, err = open(pl, 4)
	eq(err, "No Crooked Door openings left today")
	-- a new UTC day resets the allowance
	L.Time += DAY
	handlers.C2Hello(pl, {})
	eq(U(pl).Daily.Doors, 0)
	ok = open(pl, 2)
	truthy(ok, "new day")
	-- a district still sealed (Seal IV not cleared) refuses
	local rookie = newPlayer(502, 2)
	setDeal(rookie, { "Reward", "Reward", "Reward", "Reward" })
	ok, err = open(rookie, 1)
	eq(err, "This district is still sealed")
	-- in a fight: refused
	HP.Enter(pl, "Practice")
	ok, err = open(pl, 1)
	eq(err, "Finish your fight first")
	HP.Leave(pl)
	L.Time -= DAY
end)

test("doors: reward chest pays, counts for Seal V only once offered, contract + resonance progress", function()
	local pl = newPlayer(503, 4)
	U(pl).Daily.Contracts.List = { { Id = "Door", Goal = 1, Progress = 0, Claimed = false } }
	signals = {}
	setDeal(pl, { "Reward", "Reward", "Reward", "Reward" })
	local before = profiles[503].Resources.BellShards
	local ok = open(pl, 2)
	truthy(ok)
	truthy(profiles[503].Resources.BellShards > before, "chest shards")
	eq(U(pl).Seals["5"].Progress, 0, "not offered: no progress")
	local openSig = signalsOf("C2Door", function(s)
		return s.Data.Kind == "Open"
	end)[1]
	truthy(openSig and openSig.Data.Outcome == "Reward" and #openSig.Data.Rewards >= 2, "open signal with rewards")
	eq(openSig.Data.Counted, false)
	-- the queued progress (contract "Door") lands at the next flush
	C2.FlushNow(pl)
	eq(U(pl).Daily.Contracts.List[1].Progress, 1, "door contract")
	-- offering made: rewards count
	U(pl).Seals["5"].Offered = true
	handlers.C2Hello(pl, {})
	setDeal(pl, { "Reward", "Reward", "Reward", "Reward" })
	open(pl, 1)
	eq(U(pl).Seals["5"].Progress, 1)
	eq(pl.Attrs.UySealVProgress, 1)
end)

test("Seal V: failed challenge counts nothing, won fights count, 3 outcomes clear (+Gold), then repeats", function()
	local pl = newPlayer(504, 4)
	U(pl).Seals["5"].Offered = true
	handlers.C2Hello(pl, {})
	-- 1) a challenge, failed (fled the court)
	setDeal(pl, { "Challenge", "Reward", "Reward", "Reward" })
	local ok, out = open(pl, 1)
	truthy(ok and out == "Challenge", tostring(out))
	local run = SealsMod.RunOf(pl)
	truthy(run and run.TrialId == "DoorChallenge", "challenge run")
	eq(run.Zone, "Trial:DoorChallenge:" .. run.Id, "own Event HP zone")
	eq(HP.States[pl], run.Zone)
	truthy(#UY.Teleports > 0 and UY.Teleports[#UY.Teleports].Player == pl, "thrown into the court")
	-- waves come out of the court
	local waves0 = #HP.Waves
	tickRun(run, 6)
	truthy(#HP.Waves > waves0, "hazard waves")
	for k = waves0 + 1, #HP.Waves do
		eq(HP.Waves[k].Zone, run.Zone)
		checkDefs(HP.Waves[k].Defs, "live challenge wave")
	end
	-- run away from the court
	posOf[pl] = COURT + Vector3.new(0, 3, 60)
	tickRun(run, 4)
	eq(run.State, "Failed")
	eq(SealsMod.RunOf(pl), nil)
	eq(U(pl).Seals["5"].Progress, 0, "a failed challenge counts nothing")
	eq(U(pl).Daily.Doors, 1, "the door is used")
	-- 2) a challenge survived
	setDeal(pl, { "Reward", "Challenge", "Reward", "Reward" })
	open(pl, 2)
	run = SealsMod.RunOf(pl)
	posOf[pl] = COURT + Vector3.new(0, 3, 0)
	tickRun(run, 4)
	run.Def.OnTimeUp(run)
	eq(run.State, "Won")
	eq(U(pl).Seals["5"].Progress, 1, "a won challenge counts")
	-- 3) the Doorkeeper, won (the opener was downed once: no Gold this cycle)
	setDeal(pl, { "Reward", "Reward", "MiniBoss", "Reward" })
	open(pl, 3)
	run = SealsMod.RunOf(pl)
	truthy(run and run.TrialId == "Doorkeeper", "doorkeeper run")
	eq(run.Zone, "Trial:Doorkeeper:" .. run.Id)
	posOf[pl] = COURT + Vector3.new(0, 3, 6)
	tickRun(run, Cfg.Doors.Doorkeeper.Intro + .2)
	local keeper = Strike.All("UyDoorkeeper")[1]
	truthy(keeper and keeper.Alive, "the Doorkeeper stepped out")
	eq(keeper.MaxHP, Cfg.Doors.Doorkeeper.HP, "solo HP")
	tickRun(run, 6)
	truthy(#signalsOf("C2Trial", function(s)
		return s.Data.Kind == "DoorkeeperAttack"
	end) > 0, "telegraphed attacks")
	run.Downed[pl.UserId] = true
	-- a stranger cannot hit it
	local stranger = newPlayer(505, 4)
	local okHit, code = hit(stranger, keeper, 2, 5)
	eq(okHit, false)
	eq(code, "HW:NOT_YOURS")
	while keeper.Alive do
		hit(pl, keeper, 2, 7)
	end
	eq(run.State, "Won")
	eq(U(pl).Seals["5"].Progress, 2, "a won mini boss counts")
	eq(U(pl).Seals["5"].Cleared, false)
	-- 4) a reward door: the third outcome
	U(pl).Daily.Doors = 0
	setDeal(pl, { "Reward", "Reward", "Reward", "Reward" })
	local okR, errR = open(pl, 4)
	truthy(okR, tostring(errR))
	local u = U(pl)
	eq(u.Seals["5"].Progress, 3)
	eq(u.Seals["5"].Cleared, true, "three outcomes clear Seal V")
	eq(u.Seals["5"].Gold, false, "downed in a counted fight: no Gold")
	truthy(u.Journal.seal5, "journal seal5")
	-- 5) three more reward outcomes: a repeat clear with Gold (clean cycle)
	local keys = u.Keys
	for k = 1, 3 do
		L.Time += DAY / 4
		U(pl).Daily.Doors = 0
		setDeal(pl, { "Reward", "Reward", "Reward", "Reward" })
		local okO, err = open(pl, k)
		truthy(okO, tostring(err))
	end
	u = U(pl)
	eq(u.Seals["5"].Progress, 6)
	eq(u.Seals["5"].Gold, true, "clean cycle: Gold")
	truthy(u.Keys >= keys + 1, "gold key")
	L.Time = NOW
end)

test("rare room: grants find + key + dust at the opening, chests reveal, back out in front of the door", function()
	local pl = newPlayer(506, 4)
	U(pl).Seals["5"].Offered = true
	handlers.C2Hello(pl, {})
	local keys = U(pl).Keys
	local dust = profiles[506].Resources.LuckyDust or 0
	signals = {}
	setDeal(pl, { "Rare", "Reward", "Reward", "Reward" })
	local ok = open(pl, 1)
	truthy(ok)
	local u = U(pl)
	eq(u.Keys, keys + 1, "rare room key")
	truthy((profiles[506].Resources.LuckyDust or 0) > dust, "rare room dust")
	local finds = 0
	for _, it in ipairs(profiles[506].Items or {}) do
		if Base.Finds.Defs[it.ItemId] then
			finds += 1
		end
	end
	eq(finds, 1, "a guaranteed showcase find")
	eq(u.Seals["5"].Progress, 1, "the rare room counts")
	eq(pl.Attrs.UyRareRoom, 1)
	local tp = UY.Teleports[#UY.Teleports]
	truthy((tp.CF.Position - Layout.Crooked.RareRoom.Spawn).Magnitude < 4, "teleported into the room")
	local okC, err = Doors.OpenChest(pl, 2)
	truthy(okC, tostring(err))
	okC, err = Doors.OpenChest(pl, 2)
	eq(err, "This chest is already open")
	Doors.OpenChest(pl, 1)
	Doors.OpenChest(pl, 3)
	eq(#signalsOf("C2Door", function(s)
		return s.Data.Kind == "Chest"
	end), 3)
	runDelays()
	eq(pl.Attrs.UyRareRoom, 0)
	tp = UY.Teleports[#UY.Teleports]
	truthy(tp.CF.Position.Z > Layout.Crooked.WallZ, "back out in front of the doors")
	okC, err = Doors.OpenChest(pl, 1)
	eq(err, "Nothing to open here")
	-- the Hollow King roll: a declared dog row
	roll = seq({ .1, .2, .001, .5, .5 }) -- find pick, dust amount, the king roll, the shuffle
	local rr = SR.RareRoom(roll, Base)
	truthy(rr.HollowKing, "forced king roll")
	roll = lcg(99)
end)

test("doors: H13 moth hint on approach, never without the dog", function()
	for _, other in ipairs(players) do
		UY.Dist[other] = "BellSquare"
	end
	local pl = newPlayer(507, 4)
	views[507] = { Dogs = { d1 = { DogId = "HW_MothHound", AssignedSlot = "1", State = "Idle" } } }
	signals = {}
	posOf[pl] = Layout.Crooked.Court.Centre + Vector3.new(0, 3, -10)
	UY.Dist[pl] = "CrookedRow"
	roll = seq({ .05, .5, .6, .9, .1, .3 }) -- doors: Reward Challenge Challenge Rare; moth .1 < .35; pick
	Doors.StateOf(pl).Deal = nil
	Doors.Approach()
	local st = signalsOf("C2Door", function(s)
		return s.Target == pl and s.Data.Kind == "State"
	end)[1]
	truthy(st and st.Data.Hint == 1, "the moth marks door 1")
	UY.Dist[pl] = "BellSquare"
	local plain = newPlayer(508, 4)
	signals = {}
	posOf[plain] = posOf[pl]
	UY.Dist[plain] = "CrookedRow"
	roll = seq({ .05, .5, .6, .9, .1, .3 })
	Doors.Approach()
	local st2 = signalsOf("C2Door", function(s)
		return s.Target == plain and s.Data.Kind == "State"
	end)[1]
	truthy(st2 and st2.Data.Hint == nil, "no hint without H13")
	roll = lcg(7)
end)

test("doors: a HOLLOW KING left in a closed chest is announced once, also when its winner disconnects in the room", function()
	local function kingAnnounces()
		return #signalsOf("C2Announce", function(s)
			return s.Data.Kind == "HollowKing" and s.Data.Source == "Doors"
		end)
	end
	local function kingVisit(uid)
		local pl = newPlayer(uid, 4)
		U(pl).Seals["5"].Offered = true
		handlers.C2Hello(pl, {})
		signals = {}
		delays = {}
		setDeal(pl, { "Rare", "Reward", "Reward", "Reward" })
		roll = function()
			return .001 -- every roll low: the 0.5% Hollow King lands in a chest
		end
		local ok, err = open(pl, 1)
		truthy(ok, tostring(err))
		roll = lcg(99)
		local visit = Doors.StateOf(pl).Rare
		local king = false
		for _, rows in ipairs(visit.Chests) do
			for _, r in ipairs(rows) do
				king = king or (r.Kind == "Dog" and r.Id == "HW_HollowKing")
			end
		end
		truthy(king, "the visit holds the Hollow King")
		return pl, visit
	end
	-- stays: the visit timer ends the visit with the chest closed
	local a = kingVisit(531)
	runDelays()
	eq(kingAnnounces(), 1, "announced when the visit ends")
	UY.Dist[a] = "BellSquare"
	-- disconnects inside the room: PlayerRemoving announces, the later visit timer neither repeats it nor re-creates state
	local b, visit = kingVisit(532)
	for _, fn in ipairs(removing) do
		fn(b)
	end
	b.Parent = nil
	eq(kingAnnounces(), 1, "announced on disconnect")
	truthy(visit.KingAnnounced, "marked")
	runDelays()
	eq(kingAnnounces(), 1, "only once")
	eq(Doors.HasState(b), false, "no state left for the departed player")
	-- a door fight cut short by a disconnect: whatever order the PlayerRemoving handlers run in (Roblox does not fix it),
	-- the run Seals ends after SealDoors dropped the player leaves no state behind
	for _, reverse in ipairs({ false, true }) do
		local c = newPlayer(reverse and 534 or 533, 4)
		U(c).Seals["5"].Offered = true
		handlers.C2Hello(c, {})
		setDeal(c, { "Challenge", "Challenge", "Challenge", "Challenge" })
		local ok, out = open(c, 1)
		truthy(ok and out == "Challenge", tostring(out))
		local run = SealsMod.RunOf(c)
		truthy(run and run.State == "Running", "the door fight runs")
		local from, to, step = 1, #removing, 1
		if reverse then
			from, to, step = #removing, 1, -1
		end
		for i = from, to, step do
			removing[i](c)
		end
		c.Parent = nil
		eq(run.State, "Failed", "the fight ends with its opener")
		eq(Doors.HasState(c), false, "no state left after the fight ended (reverse = " .. tostring(reverse) .. ")")
		UY.Dist[c] = "BellSquare"
	end
end)

-- a Chapter II player who may play seal `seal` (previous cleared + offered), near its start
local function sealPlayer(uid, seal)
	local pl = newPlayer(uid, seal - 1)
	U(pl).Seals[tostring(seal)].Offered = true
	handlers.C2Hello(pl, {})
	return pl
end

test("choir hunt: seven spirits, only a Perfect catches, Good makes it flee, H13 hint, clear + gold", function()
	local pl = sealPlayer(601, 6)
	views[601] = { Dogs = { d1 = { DogId = "HW_MothHound", AssignedSlot = "1", State = "Idle" } } }
	posOf[pl] = Layout.Anchor("SealAltar_6")
	advance(5)
	local ok, run = SealsMod.Start(pl, 6)
	truthy(ok, tostring(run))
	eq(run.TrialId, "ChoirHunt")
	local spirits = Strike.All("UyChoir")
	eq(#spirits, 7)
	eq(#run.Public.Spirits, 7)
	for _, t in ipairs(spirits) do
		truthy(string.find(t.Attrs.UyMembers, "," .. pl.UserId .. ",", 1, true), "members attribute")
	end
	-- wandering
	local t1 = spirits[1]
	local p0 = t1.Position
	tickRun(run, 5)
	truthy((t1.Position - p0).Magnitude > 1, "spirits wander")
	-- the H13 hint names an uncaught spirit
	local moth = signalsOf("C2Trial", function(s)
		return s.Target == pl and s.Data.Kind == "ChoirMoth"
	end)
	truthy(#moth > 0, "moth hint")
	-- a Good hit: the spirit flees ~25 studs along its loop, away from the hitter
	posOf[pl] = t1.Position + Vector3.new(3, 0, 0)
	local before = t1.Position
	local okH, res = hit(pl, t1, 1)
	truthy(okH and res.Extra and res.Extra.Flee, "flee")
	eq(t1.HP, 1, "a Good hit catches nothing")
	tickRun(run, 2)
	local moved = (t1.Position - before).Magnitude
	truthy(moved > 8, "fled (" .. moved .. ")")
	truthy(#signalsOf("C2Trial", function(s)
		return s.Data.Kind == "ChoirFlee"
	end) > 0, "flee signal")
	-- a stranger cannot catch them
	local stranger = newPlayer(602, 6)
	eq(select(2, hit(stranger, spirits[2], 2)), "HW:NOT_YOURS")
	-- the session trims to one circle
	Strike.Sessions[pl] = { Targets = { [1] = { Id = 1 }, [2] = { Id = 2 }, [3] = { Id = 3 } } }
	Strike.Kinds.UyChoir.OnBegin(pl, t1)
	local n = 0
	for _ in pairs(Strike.Sessions[pl].Targets) do
		n += 1
	end
	eq(n, 1, "one timing circle")
	-- Perfects catch all seven within 5 min: clear + gold
	for _, t in ipairs(spirits) do
		if t.Alive then
			posOf[pl] = t.Position
			local okP = hit(pl, t, 2)
			truthy(okP, "perfect catch")
		end
	end
	eq(run.State, "Won")
	eq(run.Total, 7)
	truthy(SealsMod.DefaultGold(run, pl), "<= 5 min: gold")
	eq(#signalsOf("C2Trial", function(s)
		return s.Data.Kind == "ChoirCaught"
	end), 7)
end)

test("last bell trial: intro, 4 tolls, chains (Perfect in the bright pulse), heart burn -> clear", function()
	local pl = sealPlayer(701, 7)
	posOf[pl] = Layout.Anchor("ArenaCentre") + Vector3.new(0, 3, 0)
	UY.Dist[pl] = "BlackBellArena"
	advance(5)
	HP.Waves = {}
	local ok, run = SealsMod.Start(pl, 7)
	truthy(ok, tostring(run))
	eq(run.TrialId, "LastBell")
	eq(run.Zone, "Trial:LastBell")
	-- intro + wave 1: the tolls
	tickRun(run, Cfg.Bell.Intro + .2)
	eq(run.Public.Wave, 1)
	local guard = 0
	while run.Data.Wave == 1 and guard < 2000 do
		guard += 1
		tickRun(run, .1)
	end
	eq(run.Public.Tolls, Cfg.Bell.Rings.Tolls)
	local rings = 0
	for _, w in ipairs(HP.Waves) do
		checkDefs(w.Defs, "live toll")
		for _, d in ipairs(w.Defs) do
			if Hazards.TypeOf(d.Shape) == "Ring" then
				rings += 1
			end
		end
	end
	truthy(rings >= Cfg.Bell.Rings.Tolls * 3, "ring bands per toll")
	eq(run.Data.Wave, 2)
	eq(run.Total, 1, "wave 1 scored")
	-- chains: four targets, only the ringing one takes hits; only Perfects in the bright part count
	tickRun(run, 2)
	local chains = Strike.All("UyBellChain")
	eq(#chains, 4)
	local need = SR.ChainNeed(1, Base.Seals[7].Activity)
	for _, key in ipairs(Cfg.Bell.Chains.Order) do
		local target
		for _, t in ipairs(Strike.All("UyBellChain")) do
			if t.Data.Chain == key then
				target = t
			end
		end
		truthy(target, "chain " .. key)
		eq(run.Data.Chain, key, "ringing chain")
		for _, other in ipairs(Strike.All("UyBellChain")) do
			if other ~= target then
				local okO, err = hit(pl, other, 2)
				eq(okO, false)
				eq(err, "This chain is not ringing yet")
			end
		end
		-- in the dark part a Perfect does not count; a Good never does
		L.Time = run.Data.Since + Base.Seals[7].Activity.PulsePeriod * .95
		hit(pl, target, 2)
		eq(target.HP, need, "dark part")
		L.Time = run.Data.Since + .1
		hit(pl, target, 1)
		eq(target.HP, need, "Good hit")
		for _ = 1, need do
			L.Time = run.Data.Since + .1
			hit(pl, target, 2)
		end
		truthy(not target.Alive, "chain " .. key .. " broke")
		tickRun(run, 1.4)
	end
	eq(run.Total, 2, "chains scored")
	-- the heart
	tickRun(run, 3)
	eq(run.Data.Wave, 3)
	local weak = Strike.All("UyBellWeak")[1]
	truthy(weak and weak.MaxHP == SR.WeakHP(1, Base.Seals[7].Activity), "weak point HP")
	HP.Waves = {}
	tickRun(run, 4)
	truthy(#HP.Waves > 0, "volleys during the burn")
	for _, w in ipairs(HP.Waves) do
		checkDefs(w.Defs, "live volley")
	end
	while weak.Alive do
		hit(pl, weak, 2, 3)
	end
	eq(run.State, "Won")
	truthy(SealsMod.DefaultGold(run, pl), "nobody bled out: gold")
end)

test("last bell trial: refused while the Black Bell Assault rings", function()
	local pl = sealPlayer(702, 7)
	posOf[pl] = Layout.Anchor("ArenaCentre") + Vector3.new(0, 3, 0)
	UY.Dist[pl] = "BlackBellArena"
	Res.State.Assault.State = "Countdown"
	advance(5)
	local ok, err = SealsMod.Start(pl, 7)
	eq(ok, false)
	eq(err, "The Black Bell Assault is ringing: join it in the arena")
	Res.State.Assault.State = ""
	advance(5)
	ok, err = SealsMod.Start(pl, 7)
	truthy(ok, tostring(err))
	SealsMod.Fail(err, "Test")
end)

test("resonance: goal scales with active players, milestones fire once in order (buff, keys, echoes, assault)", function()
	Res.ResetCycle()
	local a = sealPlayer(801, 1)
	local b = sealPlayer(802, 1)
	-- activity: both acted in the Underyard just now
	C2.Progress(a, "Perfect", 1)
	C2.Progress(b, "Perfect", 1)
	Res.RecomputeGoal()
	local active = Res.ActiveCount()
	truthy(active >= 2, "active players counted")
	eq(Res.State.Goal, SR.Goal(active, Base))
	local goal = Res.State.Goal
	signals = {}
	Res.Add(math.ceil(goal * .25), a, "Debug")
	eq(Res.State.Milestone, 1)
	truthy(Res.State.BuffUntil > math.floor(L.Time), "RESONANT TOLL buff")
	local ms = signalsOf("C2Resonance", function(s)
		return s.Data.Kind == "Milestone"
	end)
	truthy(#ms > 0 and ms[1].Data.Index == 1, "milestone 1 signal")
	Res.Add(5, a, "Debug")
	eq(Res.State.Milestone, 1, "no second fire")
	-- 50%: keys for the active, AFK players get nothing
	local afk = sealPlayer(803, 1)
	local keysA, keysAfk = U(a).Keys, U(afk).Keys
	Res.Add(math.ceil(goal * .25), b, "Debug")
	eq(Res.State.Milestone, 2)
	eq(U(a).Keys, keysA + 1, "active player's key")
	eq(U(afk).Keys, keysAfk, "AFK: nothing")
	-- 75%: six resonant echoes, breaking one pays its contributors
	Res.Add(math.ceil(goal * .25), a, "Debug")
	eq(Res.State.Milestone, 3)
	local echoes = Strike.All("UyResEcho")
	eq(#echoes, 6)
	local v = Res.State.Value
	while echoes[1].Alive do
		hit(b, echoes[1], 2, 2)
	end
	truthy(Res.State.Value > v, "echo resonance")
	runDelays()
	eq(#Strike.All("UyResEcho"), 6, "the echo respawned")
	-- 100%: the assault countdown; the value freezes
	Res.Add(goal, a, "Debug")
	eq(Res.State.Milestone, 4)
	eq(Res.State.Assault.State, "Countdown")
	local frozen = Res.State.Value
	Res.Add(500, a, "Debug")
	eq(Res.State.Value, frozen, "frozen during the assault")
	truthy(#signalsOf("C2Announce", function(s)
		return s.Data.Kind == "Assault" and s.Data.Stage == "Countdown"
	end) == 1, "announced")
	-- the arena opens for every Chapter II player during the countdown
	local rookie = newPlayer(804, 0)
	truthy(UY.Unlocked(rookie, "BlackBellArena"), "arena open")
end)

test("resonance keys: at most 2 per UTC day", function()
	Res.ResetCycle()
	local pl = sealPlayer(811, 1)
	local keys = U(pl).Keys
	for _ = 1, 3 do
		C2.Progress(pl, "Perfect", 1)
		Res.KeyMilestone()
	end
	eq(U(pl).Keys, keys + 2, "capped at 2")
	eq(U(pl).Daily.Keys, 2)
	local capped = signalsOf("C2Resonance", function(s)
		return s.Target == pl and s.Data.Kind == "Key" and s.Data.Capped
	end)
	truthy(#capped >= 1, "told it is capped")
end)

test("assault: waits for a running Last Bell trial, joins, HP scales by attackers, win pays contributors", function()
	Res.ResetCycle()
	for _, other in ipairs(players) do
		UY.Dist[other] = "BellSquare"
	end
	local a = sealPlayer(821, 1)
	local b = sealPlayer(822, 1)
	local lazy = sealPlayer(823, 1)
	C2.Progress(a, "Perfect", 1)
	Res.StartCountdown(a)
	eq(Res.State.Assault.State, "Countdown")
	-- a Last Bell run holds the start
	local fakeRun = { TrialId = "LastBell", State = "Running" }
	local realRuns = SealsMod.Runs
	SealsMod.Runs = function()
		return { fakeRun }
	end
	L.Time = Res.State.Assault.StartsAt + .1
	Res.AssaultStep()
	eq(Res.State.Assault.State, "Countdown")
	eq(Res.State.Assault.Waiting, true, "waiting for the trial")
	SealsMod.Runs = realRuns
	L.Time = Res.State.Assault.StartsAt + .1
	Res.AssaultStep()
	eq(Res.State.Assault.State, "Active")
	local boss = Strike.All("UyAssault")[1]
	truthy(boss, "the Bellkeeper")
	eq(boss.MaxHP, SR.AssaultMaxHP(1, Base))
	-- players in the arena join (one solo run each, shared Event HP zone)
	for _, pl in ipairs({ a, b, lazy }) do
		UY.Dist[pl] = "BlackBellArena"
		posOf[pl] = Layout.Arena.Centre + Vector3.new(math.random(-10, 10), 3, math.random(-10, 10))
	end
	advance(5)
	Res.JoinScan()
	for _, pl in ipairs({ a, b, lazy }) do
		local run = SealsMod.RunOf(pl)
		truthy(run and run.TrialId == "Assault", "joined: " .. pl.Name)
		eq(HP.States[pl], "Assault", "shared zone")
		eq(run.EndsAt, Res.State.Assault.EndsAt, "the raid's end")
	end
	eq(Res.State.Assault.Count, 3)
	eq(boss.MaxHP, SR.AssaultMaxHP(3, Base), "HP scaled by attackers")
	-- hazards over the phases
	HP.Waves = {}
	for _ = 1, 120 do
		advance(.1)
		Res.AssaultStep()
	end
	truthy(#HP.Waves > 0, "assault hazards")
	for _, w in ipairs(HP.Waves) do
		eq(w.Zone, "Assault")
		checkDefs(w.Defs, "assault")
	end
	-- a non-member cannot hit
	local outsider = sealPlayer(824, 1)
	eq(select(2, hit(outsider, boss, 2, 5)), "Step into the arena to join the Assault")
	-- a and b fight, lazy hits twice (below MinHits)
	hit(lazy, boss, 2, 1)
	hit(lazy, boss, 2, 1)
	local shardsA = profiles[821].Resources.BellShards
	local keysA, keysLazy = U(a).Keys, U(lazy).Keys
	local k = 0
	while boss.Alive do
		k += 1
		hit(k % 2 == 0 and a or b, boss, 2, 9)
	end
	eq(Res.State.Assault.State, "Won")
	truthy(profiles[821].Resources.BellShards > shardsA, "winner shards")
	eq(U(a).Keys, keysA + 1, "winner key")
	eq(U(lazy).Keys, keysLazy, "below MinHits: nothing")
	truthy(U(a).Journal.assault, "journal assault")
	eq(SealsMod.RunOf(a), nil, "runs ended")
	truthy(#signalsOf("C2Announce", function(s)
		return s.Data.Stage == "Won"
	end) == 1, "won announced")
	-- the result holds, then the counter resets
	local cycle = Res.State.Cycle
	runDelays()
	eq(Res.State.Assault.State, "")
	eq(Res.State.Value, 0)
	eq(Res.State.Milestone, 0)
	eq(Res.State.Cycle, cycle + 1)
	L.Time = NOW
end)

test("assault: time runs out -> the bell holds (contributors get a few shards, no key)", function()
	Res.ResetCycle()
	for _, other in ipairs(players) do
		UY.Dist[other] = "BellSquare"
	end
	local a = sealPlayer(831, 1)
	C2.Progress(a, "Perfect", 1)
	Res.StartCountdown(a)
	L.Time = Res.State.Assault.StartsAt + .1
	Res.AssaultStep()
	UY.Dist[a] = "BlackBellArena"
	posOf[a] = Layout.Arena.Centre + Vector3.new(0, 3, 0)
	advance(5)
	Res.JoinScan()
	local boss = Strike.All("UyAssault")[1]
	for _ = 1, Cfg.Resonance.Assault.MinHits do
		hit(a, boss, 2, 1)
	end
	local keys = U(a).Keys
	local shards = profiles[831].Resources.BellShards
	L.Time = Res.State.Assault.EndsAt + .1
	Res.AssaultStep()
	eq(Res.State.Assault.State, "Failed")
	eq(U(a).Keys, keys, "no key")
	truthy(profiles[831].Resources.BellShards > shards, "consolation shards")
	runDelays()
	eq(Res.State.Assault.State, "")
	L.Time = NOW
end)

---------------------------------------------------------------------------------------------------------------------
-- localization
---------------------------------------------------------------------------------------------------------------------
local own = L.Require("ReplicatedStorage.Localization.Seals2")
local function cyrillic(s)
	return type(s) == "string" and string.find(s, "[\208\209]") ~= nil
end

test("localization: every server message of the four modules has Russian", function()
	local need = {}
	for _, file in ipairs({ "SealDoors", "SealChoir", "SealBell", "Resonance" }) do
		local src = fs.readFile("src/ServerScriptService/Halloween/" .. file .. ".luau")
		for _, pat in ipairs({ 'return false, "([^"]+)"', 'toast%(player, "([^"]+)"%)', 'Message = "([^"]+)"', 'Message = [^"]*"([^"]+)" or "([^"]+)"',
			'return true, "([^"]+)"' }) do
			for a, b in string.gmatch(src, pat) do
				need[a] = true
				if b then
					need[b] = true
				end
			end
		end
	end
	local function translated(en)
		if own.Translate(en, "ru") then
			return true
		end
		for _, entry in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
			local mod = string.match(entry, "^(.+)%.luau$")
			local ok, dict = pcall(L.Require, "ReplicatedStorage.Localization." .. tostring(mod))
			if ok and type(dict) == "table" then
				if type(dict.Exact) == "table" and dict.Exact[en] then
					return true
				end
				if type(dict.Translate) == "function" and dict.Translate(en, "ru") then
					return true
				end
			end
		end
		local auto = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
		return string.find(auto, '["' .. en .. '"]', 1, true) ~= nil
	end
	local missing = {}
	for en in pairs(need) do
		if not string.find(en, "^HW:") and not translated(en) then
			table.insert(missing, en)
		end
	end
	table.sort(missing)
	eq(#missing, 0, "untranslated: " .. table.concat(missing, " | "))
	eq(own.Translate("CROOKED DOOR 3", "ru"), "КРИВАЯ ДВЕРЬ 3")
end)

test("localization: Localization.Seals2 repeats no key of another dictionary or the base table", function()
	local base = {}
	local auto = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for en in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"') do
		base[en] = true
	end
	local dictionaries = {}
	for _, entry in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		local name = string.match(entry, "^(.+)%.luau$")
		if name and name ~= "Seals2" then
			local ok, dict = pcall(L.Require, "ReplicatedStorage.Localization." .. name)
			if ok and type(dict) == "table" then
				dictionaries[name] = dict
			end
		end
	end
	for en, ru in pairs(own.Exact) do
		truthy(not base[en], "repeats a base entry: " .. en)
		for name, dict in pairs(dictionaries) do
			truthy(not (type(dict.Exact) == "table" and dict.Exact[en]), "repeats Localization." .. name .. ": " .. en)
		end
		truthy(cyrillic(ru) and not string.find(ru, "[A-Za-z]"), "Russian text for " .. en)
	end
	for _, group in pairs({ own.Reasons, own.UI.Outcomes, own.UI.OutcomeLines, own.UI.Kinds }) do
		for _, pair in pairs(group) do
			truthy(type(pair[1]) == "string" and cyrillic(pair[2]), "pair " .. tostring(pair[1]))
		end
	end
end)

-- the string literals of a Luau source in order {S, E, Text} (comments and long strings skipped)
local function literals(src)
	local out = {}
	local i, n = 1, #src
	while i <= n do
		local c = string.sub(src, i, i)
		if c == "-" and string.sub(src, i, i + 1) == "--" then
			local long = string.match(src, "^%-%-%[(=*)%[", i)
			if long then
				local close = "]" .. long .. "]"
				local e = string.find(src, close, i, true) or n
				i = e + #close
			else
				i = (string.find(src, "\n", i, true) or n) + 1
			end
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c or d == "\n" then
					break
				else
					j += 1
				end
			end
			table.insert(out, { S = i, E = j, Text = string.sub(src, i + 1, j - 1) })
			i = j + 1
		elseif c == "[" and string.match(src, "^%[=*%[", i) then
			local eq = string.match(src, "^%[(=*)%[", i)
			local close = "]" .. eq .. "]"
			local e = string.find(src, close, i, true) or n
			i = e + #close
		else
			i += 1
		end
	end
	return out
end

test("client presenters: every self-localized pair has Russian", function()
	local n = 0
	for _, file in ipairs({ "Doors", "Choir", "Bell", "Assault", "Resonance" }) do
		local path = "src/StarterPlayer/StarterPlayerScripts/HalloweenClient/Trials/" .. file .. ".luau"
		if fs.isFile(path) then
			local src = fs.readFile(path)
			for en, ru in string.gmatch(src, 'L%("([^"]*)",%s*"([^"]*)"%)') do
				n += 1
				truthy(cyrillic(ru) or ru == en, file .. ": Russian for " .. en)
			end
			truthy(not string.find(src, 'L%("[^"]*"%)'), file .. ": L without a Russian text")
			-- banners / toasts / marks / {en, ru} tables: every two string literals separated only by a comma, the first
			-- reading like text (words, or a CAPITALS label)
			local lits = literals(src)
			for k = 1, #lits - 1 do
				local a, b = lits[k], lits[k + 1]
				if string.match(string.sub(src, a.E + 1, b.S - 1), "^%s*,%s*$") then
					local en, ru = a.Text, b.Text
					local texty = string.find(en, "%a %a") ~= nil or (string.find(en, "^[%u%p%d ]+$") ~= nil and #en >= 3)
					if texty and not cyrillic(en) then
						n += 1
						truthy(cyrillic(ru) or ru == en, file .. ": Russian for " .. en)
					end
				end
			end
		end
	end
	truthy(n >= 100, "pairs checked: " .. n)
end)

print(string.format("seals_5_7: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("seals_5_7 tests failed")
end
