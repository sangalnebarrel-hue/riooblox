--!nocheck
-- The Gravekeeper's endgame + the difficulty V finale on the client (docs/halloween2/DESIGN.md §10.5, §11, §23):
-- HalloweenClient.BossFX (Event HP hazards, endgame patterns, downed camera, wipe, the false-victory handoff) and
-- HalloweenClient.FinaleFX (every §23.2 stage, late joiners, the journal replay, teardown) run headless in the fake client
-- of tests/lib/client_env.luau with the real Shared / Bus / FX / Cinema / Models and fake Audio, AudioMixer, Music and
-- Lighting compositor. The server is played by hand: State.Boss / State.Finale attributes + BossEvent signals in the
-- order BossFinale (WP-C) sends them. Checks: nothing errors, the right presentation exists at each beat, and whatever
-- ends the finale (victory, leaving the arena, a new fight, the replay's end) leaves nothing behind (models, guis,
-- lighting layers, ducks, Cinema, camera, control sinks). lune run tests/finale_client.luau
local roblox = require("@lune/roblox")
local CE = require("./lib/client_env")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local V3 = Vector3.new

local passed, failed = 0, 0
local function test(name, fn)
	local before = #CE.Errors
	local ok, err = pcall(fn)
	if ok and #CE.Errors > before then
		ok, err = false, "runtime errors:\n  " .. table.concat(CE.Errors, "\n  ", before + 1)
	end
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
local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- the fake engine pieces the presentation touches beyond client_env
---------------------------------------------------------------------------------------------------------------------
local Debris = CE.Service("Debris")
Debris.AddItem = function(_, inst, life)
	CE.task.delay(tonumber(life) or 10, function()
		if inst.Parent then
			inst:Destroy()
		end
	end)
end
local sinks = {}
local CAS = CE.Service("ContextActionService")
CAS.BindAction = function(_, name)
	sinks[name] = true
end
CAS.BindActionAtPriority = function(_, name)
	sinks[name] = true
end
CAS.UnbindAction = function(_, name)
	sinks[name] = nil
end
CE.Workspace.BulkMoveTo = function(_, parts, cfs)
	for i, p in ipairs(parts) do
		p.CFrame = cfs[i]
	end
end
local rawNew = CE.Instance.new
CE.Instance.new = function(className, parent)
	local inst = rawNew(className, parent)
	if className == "ParticleEmitter" then
		inst.Emit = function() end
		inst.Clear = function() end
	end
	return inst
end

-- AudioMixer: every duck must be released
local ducks = {}
local Mixer = {
	Duck = function(reason, _levels, _fade)
		ducks[reason] = true
	end,
	Release = function(reason, _fade)
		ducks[reason] = nil
	end,
	Ducked = function(reason)
		return ducks[reason] == true
	end,
}
CE.Overrides["ReplicatedStorage/AudioMixer"] = Mixer
-- Music: the finale theme goes back when the finale ends
local music = { Theme = nil, Sets = {} }
CE.Overrides["Halloween/Music"] = {
	SetTheme = function(name, opts)
		music.Theme = name
		table.insert(music.Sets, { Name = name, Opts = opts })
	end,
	Theme = function()
		return music.Theme
	end,
	Beat = function(_theme)
		return CE.Unix % 1, 0
	end,
}

---------------------------------------------------------------------------------------------------------------------
-- the world: ReplicatedStorage from src, the replicated state folders, the player in the Dead Yard pit
---------------------------------------------------------------------------------------------------------------------
-- client_env has no Instance.AttributeChanged event: give the replicated state folders one (SetAttribute fires
-- Events.AttributeChanged, the property read returns the same signal)
local function withAttributeChanged(inst)
	local st = CE.StateOf(inst)
	local sig = CE.Signal.new()
	st.Events.AttributeChanged = sig
	st.Props.AttributeChanged = sig
	return inst
end
local RS = CE.MountReplicated()
local Halloween = RS:FindFirstChild("Halloween")
local stateRoot = withAttributeChanged(CE.Folder("State", Halloween))
stateRoot:SetAttribute("Enabled", true)
local bossState = withAttributeChanged(CE.Folder("Boss", stateRoot))
local finState = withAttributeChanged(CE.Folder("Finale", stateRoot))
local live = CE.Folder("HalloweenLive", CE.Workspace)
local targets = CE.Folder("Targets", live)
local mainGui = withAttributeChanged(CE.Instance.new("ScreenGui"))
mainGui.Name = "ScreenGui"
mainGui.Parent = CE.PlayerGui
withAttributeChanged(CE.Player)

local Shared = CE.Require(Halloween:FindFirstChild("Shared"))
local Layout = Shared.Layout
local PIT = Layout.Pit.Center
local FLOOR = Layout.Pit.FloorY
local function spawn(pos)
	local ch = CE.Spawn(pos)
	ch:FindFirstChildOfClass("Humanoid").ChangeState = function() end
	return ch
end
spawn(V3(PIT.X, FLOOR + 3, PIT.Z + 18))

local clientFolder = CE.Folder("HalloweenClient", CE.Service("StarterPlayer"))
CE.Mount("StarterPlayer/StarterPlayerScripts/HalloweenClient", clientFolder)

-- Audio: record the cues
local plays = {}
local Audio = {
	Play = function(cue, _where, _opts)
		table.insert(plays, cue)
	end,
	Has = function(_cue)
		return true
	end,
}
-- the Halloween Lighting compositor's pushed layers
local layers = {}
local LightingModule = {
	Layer = function(name, profile)
		local rec = { Name = name, Profile = profile, Weight = 0, Removed = false }
		layers[name] = rec
		return {
			Set = function(_, w, _fade)
				rec.Weight = w
			end,
			Remove = function(_, _fade)
				rec.Removed = true
			end,
		}
	end,
}
local function liveLayers()
	local n = 0
	for _, rec in pairs(layers) do
		if not rec.Removed then
			n += 1
		end
	end
	return n
end

local Bus = CE.Require(Halloween:FindFirstChild("Bus"))
local FXmod = CE.Require(Halloween:FindFirstChild("FX"))
local banners = {}
Bus.On("Banner", function(d)
	table.insert(banners, d)
end)
local ctx = {
	Player = CE.Player, Shared = Shared, Config = Shared.Config, Layout = Layout, Bus = Bus, FX = FXmod, Audio = Audio,
	State = {}, Modules = {},
}
local Cinema = CE.Require(clientFolder:FindFirstChild("Cinema"))
local BossFX = CE.Require(clientFolder:FindFirstChild("BossFX"))
local FinaleFX = CE.Require(clientFolder:FindFirstChild("FinaleFX"))
ctx.Modules.Cinema = Cinema
ctx.Modules.BossFX = BossFX
ctx.Modules.FinaleFX = FinaleFX
ctx.Modules.Lighting = LightingModule

local function now()
	return CE.Unix
end
local function event(d)
	Bus.Fire("Signal", { Kind = "BossEvent", Data = d })
	CE.Step(1 / 30)
end
local function finale(d)
	d.Kind = "Finale"
	event(d)
end
local function bannerWith(text)
	for _, b in ipairs(banners) do
		if string.find(tostring(b.Title), text, 1, true) or string.find(tostring(b.Subtitle or ""), text, 1, true) then
			return b
		end
	end
	return nil
end
local function fxFolder()
	return CE.Workspace:FindFirstChild("DOGROTS_HalloweenFX")
end
local function finaleRoots()
	local f = fxFolder()
	local n = 0
	for _, c in ipairs(f and f:GetChildren() or {}) do
		if c.Name == "DOGROTS_Finale" or c.Name == "DOGROTS_FinaleReplay" then
			n += 1
		end
	end
	return n
end
local function guiNamed(name)
	return CE.PlayerGui:FindFirstChild(name)
end
local function S()
	return FinaleFX.Debug and FinaleFX.Debug.Session()
end
local function target(id, kind, pos, attrs)
	local p = CE.Part("Target_" .. id, pos, V3(4, 4, 4), targets)
	p.Transparency = 1
	p:SetAttribute("TargetId", id)
	p:SetAttribute("Kind", kind)
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	return p
end
local function noLeftovers(what)
	eq(finaleRoots(), 0, what .. ": finale model roots left")
	truthy(not guiNamed("DOGROTS_FinaleHUD"), what .. ": finale panel left")
	truthy(not guiNamed("DOGROTS_FinaleCard"), what .. ": fake reward card left")
	truthy(not CE.Camera:FindFirstChild("DOGROTS_FinaleGrade"), what .. ": camera grade left")
	eq(liveLayers(), 0, what .. ": lighting layers left")
	for key in pairs(ducks) do
		truthy(string.sub(key, 1, 7) ~= "Finale:", what .. ": duck left " .. key)
	end
	truthy(not Cinema.Busy(), what .. ": a cinematic still runs")
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom, what .. ": camera type")
	eq(count(sinks), 0, what .. ": input sinks left")
	eq(Cinema.Locked(), false, what .. ": controls still locked")
end

-- the boot (State.Boss first: BossFX waits for it)
bossState:SetAttribute("State", "Idle")
bossState:SetAttribute("Mode", "")
local okCinema = pcall(Cinema.Start, ctx)
truthy(okCinema, "Cinema.Start")
BossFX.Start(ctx)
FinaleFX.Start(ctx)
CE.Advance(.5)

---------------------------------------------------------------------------------------------------------------------
-- BossFX: the Chapter II fight
---------------------------------------------------------------------------------------------------------------------
local function fight()
	bossState:SetAttribute("State", "Fight")
	bossState:SetAttribute("Mode", "Idle")
	bossState:SetAttribute("ModeAt", now())
	bossState:SetAttribute("Phase", 5)
	bossState:SetAttribute("Difficulty", 5)
	bossState:SetAttribute("MaxArmor", 1000)
	bossState:SetAttribute("Armor", 400)
	bossState:SetAttribute("PerfectOnly", true)
	bossState:SetAttribute("BossCF", CFrame.new(PIT.X, FLOOR, PIT.Z))
	bossState:SetAttribute("FightId", "F1")
	bossState:SetAttribute("Pattern", "")
	bossState:SetAttribute("PatternUntil", 0)
	BossFX.Debug.Sync()
	CE.Advance(.3)
end

test("the boss rig is built for a fighter in the pit", function()
	fight()
	truthy(BossFX.Debug.Boss(), "boss rig")
end)

test("hazard-backed attacks get no BossFX telegraph; old attacks still do", function()
	local tg = BossFX.Debug.Telegraphs
	local n0 = #tg
	event({ Kind = "Attack", Stage = "Telegraph", Attack = "Slam", Position = PIT, Radius = 12, ImpactAt = now() + 1.4, HazardId = "h1" })
	eq(#tg, n0, "telegraph with HazardId")
	event({ Kind = "Attack", Stage = "Telegraph", Attack = "Sweep", Position = PIT, Radius = 20, Angle = 120, Direction = V3(0, 0, 1),
		ImpactAt = now() + 1.4, HazardIds = { "h2" } })
	eq(#tg, n0, "telegraph with HazardIds")
	event({ Kind = "Attack", Stage = "Telegraph", Attack = "Stomp", Position = PIT, Radius = 12, ImpactAt = now() + 1.2 })
	eq(#tg, n0 + 1, "a legacy attack (no hazard) keeps its telegraph")
	event({ Kind = "Attack", Stage = "Impact", Attack = "Slam", Position = PIT, Radius = 12, HazardId = "h1" })
	event({ Kind = "Rocks", Wave = 1, Waves = 0, HazardIds = { "r1", "r2" }, Rocks = {
		{ Key = 1, Position = PIT + V3(10, 0, 4), LandAt = now() + 1.6, Radius = 4.5, HazardId = "r1" },
		{ Key = 2, Position = PIT + V3(-12, 0, -6), LandAt = now() + 1.6, Radius = 4.5, HazardId = "r2" } } })
	eq(#tg, n0 + 1, "rock landings with hazards draw no circle")
	CE.Advance(2.5)
	eq(#tg, 0, "telegraphs expire")
end)

test("Event HP knock-back, PERFECT ONLY and SYNC STRIKE feedback", function()
	event({ Kind = "Knock", Velocity = V3(10, 30, 0), Curse = 2, Attack = "Slam", Damage = 18 })
	event({ Kind = "Hit", Damage = 0, Weak = true, Slot = "Heart", NeedPerfect = true, Armor = 400 })
	event({ Kind = "Hit", Damage = 40, Weak = false, Slot = "Back", Sync = true, Armor = 360 })
	event({ Kind = "Hit", Damage = 12, Sync = true, Retro = true, Armor = 348 })
	CE.Advance(.5)
end)

test("endgame pattern: banner + a pose for its duration, late joiners from the attributes", function()
	local anim = BossFX.Debug.Anim
	event({ Kind = "Pattern", Name = "GraveLines", StartAt = now(), Duration = 3, HazardIds = { "p1", "p2" } })
	truthy(anim.Pattern and anim.Pattern.Name == "GraveLines", "pattern pose on")
	truthy(bannerWith("GRAVE LINES"), "GRAVE LINES banner")
	for _ = 1, 30 do
		BossFX.Debug.Step(1 / 30)
		CE.Step(1 / 30)
	end
	CE.Advance(2.6)
	BossFX.Debug.Sync()
	truthy(anim.Pattern == nil, "pattern pose off after its duration")
	-- a lantern walk joined late (only the attributes)
	bossState:SetAttribute("Pattern", "LanternWalk")
	bossState:SetAttribute("PatternUntil", now() + 4)
	BossFX.Debug.Sync()
	truthy(anim.Pattern and anim.Pattern.Name == "LanternWalk", "late pattern from attributes")
	event({ Kind = "Pattern", Name = "LanternWalk", StartAt = now(), Duration = 4 })
	truthy(BossFX.Debug.Boss().PatternLight, "lantern glow")
	CE.Advance(1)
	bossState:SetAttribute("Pattern", "")
	CE.Advance(4.5)
	BossFX.Debug.Sync()
	truthy(anim.Pattern == nil, "late pattern cleared")
	truthy(not BossFX.Debug.Boss().PatternLight, "lantern glow gone")
	event({ Kind = "Pattern", Name = "BoneRain", StartAt = now(), Duration = 1.5 })
	truthy(bannerWith("BONE RAIN"), "BONE RAIN banner")
	CE.Advance(2)
end)

test("no boss camera shot while downed; a running shot ends when the player goes down", function()
	local shot = BossFX.Debug.CameraShot
	CE.Player:SetAttribute("HwDowned", true)
	eq(shot(2, function()
		return CFrame.lookAt(PIT + V3(0, 30, 40), PIT)
	end, true), false, "refused while downed")
	CE.Player:SetAttribute("HwDowned", false)
	local started = shot(3, function()
		return CFrame.lookAt(PIT + V3(0, 30, 40), PIT)
	end, true)
	truthy(started, "a shot starts when standing")
	CE.Advance(.4)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Scriptable, "shot running")
	CE.Player:SetAttribute("HwDowned", true)
	CE.Step(1 / 30)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom, "camera handed back when downed")
	CE.Player:SetAttribute("HwDowned", false)
	CE.Advance(.5)
end)

test("team wipe: one banner, the boss gloats then burrows away", function()
	banners = {}
	event({ Kind = "Wiped", Difficulty = 4, Position = PIT })
	bossState:SetAttribute("State", "Escaped")
	bossState:SetAttribute("Mode", "Escape")
	event({ Kind = "Escaped", Reason = "Wiped", Position = PIT, Difficulty = 4 })
	truthy(bannerWith("WIPED OUT"), "wipe banner")
	truthy(not bannerWith("ESCAPED"), "no second escape banner")
	eq(BossFX.Debug.Anim.Mode, "Roar", "gloating roar first")
	CE.Advance(2)
	eq(BossFX.Debug.Anim.Mode, "Escape", "then the burrow")
	CE.Advance(4)
	truthy(BossFX.Debug.Boss() == nil, "rig gone after the escape")
	bossState:SetAttribute("State", "Idle")
	CE.Advance(.5)
	banners = {}
end)

---------------------------------------------------------------------------------------------------------------------
-- the difficulty V finale, live
---------------------------------------------------------------------------------------------------------------------
local BELL_CF = CFrame.new(PIT + V3(0, 28, 0))
local ANCHORS = { N = PIT + V3(0, 4, -32), E = PIT + V3(32, 4, 0), S = PIT + V3(0, 4, 32), W = PIT + V3(-32, 4, 0) }
local function setFinale(attrs)
	for k, v in pairs(attrs) do
		finState:SetAttribute(k, v)
	end
	finState:SetAttribute("Revision", (finState:GetAttribute("Revision") or 0) + 1)
end

test("FakeDeath: the boss collapses (no soul to the moon), the fake card, silence, the toll, the spirit", function()
	fight()
	truthy(BossFX.Debug.Boss(), "boss before the false victory")
	bossState:SetAttribute("Armor", 0)
	bossState:SetAttribute("Mode", "Finale")
	local at = now()
	setFinale({ State = "FakeDeath", Stage = "FakeDeath", StageStart = at, StageUntil = at + 6, FightId = "F1", Deadline = at + 420 })
	finale({ Stage = "FakeDeath", At = at, Seconds = 6, Silence = 2.5, Deadline = at + 420 })
	local d = BossFX.Debug.Death()
	truthy(d and d.Fake, "BossFX plays the false-victory collapse")
	truthy(BossFX.CorpsePos() ~= nil, "corpse position for the spirit")
	truthy(S() and S().Stage == "FakeDeath", "FinaleFX in FakeDeath")
	truthy(ducks["Finale:HardStop"], "music hard stop")
	truthy(Cinema.Busy(), "the false-victory shot")
	CE.Advance(1.4)
	local card = guiNamed("DOGROTS_FinaleCard")
	truthy(card, "fake reward card at At+1.2")
	local saysFalls = false
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextLabel") and string.find(d.Text, "THE GRAVEKEEPER FALLS!", 1, true) then
			saysFalls = true
		end
	end
	truthy(saysFalls, "the card says THE GRAVEKEEPER FALLS!")
	truthy(ducks["Finale:Silence"], "silence")
	CE.Advance(2.7) -- At+4.1: the toll
	truthy(not ducks["Finale:Silence"], "silence lifted at the toll")
	CE.Advance(1.6) -- At+5.7: the spirit
	truthy(S().Spirit, "the spirit tore out")
	truthy(BossFX.Debug.Soul() == nil, "no soul flies to the moon")
	truthy(BossFX.Debug.MoonFlare() == nil, "no moon flare")
	CE.Advance(2.8) -- At+8.5
	truthy(BossFX.Debug.Boss() == nil, "the corpse crumbled away")
	truthy(not guiNamed("DOGROTS_FinaleCard"), "card dissolved")
	BossFX.Debug.Sync()
	CE.Advance(1.2)
	truthy(BossFX.Debug.Boss() == nil, "the rig is never rebuilt during the finale")
end)

test("Bell: descent, four chains, the active chain, hits, the toll, breaks", function()
	local t = now()
	setFinale({ State = "Bell", Stage = "Bell", StageStart = t, StageUntil = 0, Chain = "", ChainsLeft = 4, ChainNeed = 6, Pulse = 1.2,
		Bright = .55, BellCF = BELL_CF })
	finale({ Stage = "Bell", StartAt = t, BellCF = BELL_CF, Chains = ANCHORS, Pulse = 1.2, Bright = .55, Need = 6, Order = { "N", "E", "S", "W" },
		Descend = 2.5 })
	truthy(S().Bell, "bell built")
	CE.Advance(.5)
	truthy(Cinema.Busy(), "the descent shot")
	-- the first hazard telegraph hands the fighter's camera back at once
	Bus.Fire("CombatHazard", { Id = "ring0", Kind = "Ring", ImpactAt = now() + 1.2 })
	CE.Advance(.2)
	truthy(not Cinema.Busy(), "in-combat shot cancelled by a hazard telegraph")
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom, "camera back")
	CE.Advance(2.5)
	eq(count(S().Chains), 4, "four chains")
	truthy(guiNamed("DOGROTS_FinaleHUD"), "finale panel")
	target("chainN", "FinaleChain", ANCHORS.N:Lerp(BELL_CF.Position, .25), { Key = "N" })
	setFinale({ Chain = "N", ChainSince = now(), ChainHits = 0 })
	finale({ Stage = "ChainActive", Key = "N", Since = now(), Pulse = 1.2, Bright = .55, Need = 6, Hits = 0, TargetId = "chainN",
		Position = ANCHORS.N:Lerp(BELL_CF.Position, .25) })
	CE.Advance(1.3)
	finale({ Stage = "ChainHit", Key = "N", Hits = 1, Need = 6, UserId = 1, Counted = true })
	finale({ Stage = "ChainHit", Key = "N", Hits = 1, Need = 6, UserId = 1, Counted = false, Reason = "Toll" })
	finale({ Stage = "ChainHit", Key = "N", Hits = 1, Need = 6, UserId = 1, Counted = false, Reason = "Immune" })
	finale({ Stage = "BellToll", At = now() + .8, HazardIds = { "ring1" }, Rings = 2 })
	CE.Advance(1.2)
	finale({ Stage = "ChainBreak", Key = "N", Left = 3 })
	truthy(bannerWith("CHAIN BROKEN"), "chain broken banner")
	CE.Advance(1)
	for i, key in ipairs({ "E", "S", "W" }) do
		finale({ Stage = "ChainActive", Key = key, Since = now(), Pulse = 1.2, Bright = .55, Need = 6, Hits = 0 })
		CE.Advance(.5)
		finale({ Stage = "ChainBreak", Key = key, Left = 3 - i })
		CE.Advance(.5)
	end
	truthy(bannerWith("THE BELL IS FREE"), "bell free banner")
	-- strikes on the hidden bell are refused on screen
	finale({ Stage = "ChainHit", Key = "", Hits = 0, Need = 0, UserId = 1, Counted = false })
	CE.Advance(1)
end)

test("Choir: fog, candles, pattern, ghost dogs, weak points, volleys", function()
	local t = now()
	local candles = {}
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		local pos = PIT + V3(math.sin(a) * 26, 4, -math.cos(a) * 26)
		candles[i] = { Position = pos, Lit = i % 2 == 1, TargetId = "candle" .. i }
		target("candle" .. i, "FinaleCandle", pos, { Index = i, Lit = i % 2 == 1 })
	end
	setFinale({ State = "Choir", Stage = "Choir", StageStart = t, Candles = "101010", Pattern = "110011", Round = 1, Rounds = 3 })
	finale({ Stage = "Choir", StartAt = t, Candles = candles, Pattern = "110011", Round = 1, Rounds = 3 })
	CE.Advance(2)
	eq(count(S().Candles), 6, "six candles")
	truthy(layers.FINALE_CHOIR and not layers.FINALE_CHOIR.Removed, "choir fog layer")
	setFinale({ Candles = "111010" })
	finale({ Stage = "Candle", Index = 2, Lit = true, UserId = 1, Candles = "111010" })
	CE.Advance(.5)
	truthy(S().Candles[2].Lit, "candle 2 lit")
	-- ghost dogs on their Strike targets
	target("g1", "FinaleGhost", PIT + V3(8, FLOOR - PIT.Y + 2, 6))
	target("g2", "FinaleGhost", PIT + V3(-8, FLOOR - PIT.Y + 2, -6))
	finale({ Stage = "Ghosts", Count = 2, Spawns = { { TargetId = "g1", Position = PIT + V3(8, 0, 6), Key = 1 }, { TargetId = "g2",
		Position = PIT + V3(-8, 0, -6), Key = 2 } } })
	CE.Advance(.6)
	eq(count(S().Ghosts), 2, "two ghost dogs")
	finale({ Stage = "GhostBite", Key = 1, TargetId = "g1", UserId = 1, Position = PIT })
	CE.Advance(.4)
	targets:FindFirstChild("Target_g2"):Destroy()
	finale({ Stage = "GhostDown", Key = 2, TargetId = "g2", UserId = 1, Position = PIT })
	CE.Advance(1)
	finale({ Stage = "Volley", At = now(), From = PIT + V3(0, 6, -30), HazardIds = { "v1" } })
	setFinale({ Pattern = "111010" })
	finale({ Stage = "Round", Round = 1, Pattern = "111010", Cleared = true })
	target("w1", "FinaleWeak", PIT + V3(5, FLOOR - PIT.Y + 1, 5))
	finale({ Stage = "WeakOpen", Points = { { Id = "w1", Position = PIT + V3(5, FLOOR - PIT.Y, 5) } }, Until = now() + 10, Round = 1 })
	CE.Advance(1)
	truthy(count(S().Weak) >= 1, "buried weak point mound")
	targets:FindFirstChild("Target_w1"):Destroy()
	CE.Advance(1.5)
	finale({ Stage = "Round", Round = 2, Pattern = "010101", Cleared = false })
	CE.Advance(1)
end)

test("Hound: rises with the Black Moon, patterns on the beat, bark + counter window", function()
	local t = now()
	local houndCF = CFrame.lookAt(PIT + V3(0, 0, 50), PIT)
	setFinale({ State = "Hound", Stage = "Hound", StageStart = t, StartAt = t, Bpm = 100, HoundHP = 24, HoundMax = 24, HoundCF = houndCF })
	CE.Player:SetAttribute("HwDowned", true)
	finale({ Stage = "Hound", StartAt = t, Bpm = 100, HoundCF = houndCF, MoonDir = V3(0, .35, 1).Unit, HP = 24, Max = 24 })
	truthy(S().Hound, "hound built")
	truthy(not Cinema.Busy(), "no finale shot while downed")
	CE.Player:SetAttribute("HwDowned", false)
	CE.Advance(3.2)
	finale({ Stage = "HoundPattern", Name = "Circles", BeatAt = now() + .6, Beats = 8, BarkAt = now() + 5.4 })
	CE.Advance(1.5)
	finale({ Stage = "HoundPattern", Name = "SafeDance", BeatAt = now() + .6, Beats = 8, BarkAt = now() + 5.4 })
	CE.Advance(1.5)
	local jaw = PIT + V3(0, 10, 18)
	target("jaw", "HoundJaw", jaw)
	setFinale({ CounterUntil = now() + 3.3, JawPos = jaw })
	finale({ Stage = "Bark", At = now() + .3, CounterUntil = now() + 3.3, JawPos = jaw, TargetId = "jaw" })
	CE.Advance(.6)
	truthy(S().Hound.Bark, "bark lunge running")
	finale({ Stage = "Counter", HP = 23, Max = 24, UserId = 1, Hits = 1, Counted = true })
	finale({ Stage = "Counter", HP = 23, Max = 24, UserId = 1, Counted = false, Reason = "Perfect" })
	setFinale({ HoundHP = 23 })
	CE.Advance(3)
	eq(S().Hound.HP, 23, "bark points follow the attribute")
	finale({ Stage = "HoundPattern", Name = "Waves", BeatAt = now() + .6, Beats = 8 })
	CE.Advance(1)
	finale({ Stage = "HoundPattern", Name = "Lines", BeatAt = now() + .6, Beats = 8 })
	CE.Advance(1)
end)

test("Victory: howl, moths, the moon breaks, dawn; the reward waits; then everything goes", function()
	banners = {}
	local t = now()
	setFinale({ State = "Victory", Stage = "Victory", StageStart = t, StageUntil = t + 8 })
	finale({ Stage = "Victory", At = t, Top = { { UserId = 1, Name = "Tester", Score = 12 } } })
	bossState:SetAttribute("State", "Defeated")
	event({ Kind = "Defeated", Difficulty = 5, Numeral = "V", Top = { { UserId = 1, Name = "Tester", Damage = 900 } }, Position = PIT, Duration = 6,
		Finale = "Victory", FinaleReason = "FinaleVictory" })
	event({ Kind = "Reward", Outcome = "Defeated", Difficulty = 5, Candy = 500, Bones = 20, Full = true, Finale = true, FinaleRun = true })
	truthy(not bannerWith("THE GRAVEKEEPER FALLS!"), "no false-victory banner at the real end")
	CE.Advance(5)
	truthy(S() and S().Stage == "Victory", "victory presenting")
	truthy(not bannerWith("FINALE REWARD"), "reward banner waits for the victory shot")
	CE.Advance(5)
	truthy(bannerWith("FINALE REWARD"), "reward banner after the shot")
	-- the fight is released
	setFinale({ State = "", Stage = "", StageStart = 0, FightId = "" })
	bossState:SetAttribute("State", "Idle")
	bossState:SetAttribute("Mode", "")
	CE.Advance(6)
	truthy(S() == nil, "session over")
	noLeftovers("after victory")
	truthy(music.Theme == nil or string.sub(tostring(music.Theme), 1, 7) ~= "FINALE_", "finale music handed back")
end)

---------------------------------------------------------------------------------------------------------------------
-- late joiners, leaving, a new fight, fail, the replay
---------------------------------------------------------------------------------------------------------------------
test("a late joiner gets the current stage without set pieces, and leaving the arena tears it all down", function()
	local t = now()
	setFinale({ State = "Choir", Stage = "Choir", StageStart = t - 30, Candles = "100110", Pattern = "101010", Round = 2, Rounds = 3,
		FightId = "F2", ChainsLeft = 0 })
	bossState:SetAttribute("State", "Fight")
	bossState:SetAttribute("Mode", "Finale")
	CE.Advance(1.2)
	truthy(S() and S().Entered.Choir, "entered the choir late")
	truthy(not Cinema.Busy(), "no cinematic replayed for a late joiner")
	eq(count(S().Candles), 6, "candles from the attributes")
	truthy(S().Bell, "bell hanging")
	truthy(BossFX.Debug.Boss() == nil, "no boss rig for a finale late joiner")
	CE.MoveTo(PIT + V3(600, 20, 600))
	CE.Advance(2)
	truthy(S() == nil, "left the arena")
	noLeftovers("after leaving")
	CE.MoveTo(V3(PIT.X, FLOOR + 3, PIT.Z + 18))
	CE.Advance(1)
end)

test("a late joiner to the hound, then a new fight id resets the session", function()
	local t = now()
	setFinale({ State = "Hound", Stage = "Hound", StageStart = t - 20, StartAt = t - 20, Bpm = 100, HoundHP = 10, HoundMax = 24,
		HoundCF = CFrame.lookAt(PIT + V3(0, 0, 50), PIT), FightId = "F3" })
	CE.Advance(1.2)
	truthy(S() and S().Hound, "hound for the late joiner")
	eq(S().Hound.HP, 10, "bark points from the attribute")
	setFinale({ FightId = "F4", State = "Bell", Stage = "Bell", StageStart = now(), Chain = "E", ChainsLeft = 3, ChainSince = now() })
	CE.Advance(1.2)
	truthy(S() and S().FightId == "F4", "new fight, new session")
	truthy(S().Hound == nil, "nothing of the old fight")
	truthy(S().Bell, "bell of the new fight")
end)

test("Fail: THE BELL SILENCES YOU, then teardown", function()
	local t = now()
	setFinale({ State = "Fail", Stage = "Fail", StageStart = t, StageUntil = t + 8, Reason = "Wipe" })
	finale({ Stage = "Fail", Reason = "Wipe", At = t })
	event({ Kind = "Defeated", Difficulty = 5, Numeral = "V", Top = {}, Position = PIT, Duration = 6, Finale = "Fail", FinaleReason = "FinaleFail" })
	truthy(not bannerWith("THE GRAVEKEEPER FALLS!"), "no false-victory banner on fail")
	CE.Advance(6)
	setFinale({ State = "", Stage = "", FightId = "" })
	bossState:SetAttribute("State", "Idle")
	bossState:SetAttribute("Mode", "")
	CE.Advance(6)
	truthy(S() == nil, "session over")
	noLeftovers("after fail")
end)

test("journal replay: client-only FakeDeath -> bell rise on a memory stage, restored at its end", function()
	ctx.Modules.Lighting = nil -- the camera-grade fallback this time
	local fires = 0
	CE.OnFire = function()
		fires += 1
	end
	Bus.Fire("C2Replay", { Id = "Finale" })
	CE.Step(1 / 30)
	truthy(S() and S().Replay, "replay session")
	truthy(Cinema.Busy(), "replay cinematic")
	CE.Advance(8)
	truthy(S() and S().Bell, "the bell rises in the replay")
	CE.Advance(10)
	truthy(S() == nil, "replay over")
	eq(fires, 0, "the replay sends nothing")
	noLeftovers("after the replay")
	ctx.Modules.Lighting = LightingModule
end)

test("the replay is cancelled by a real finale; switching the event off tears everything down", function()
	Bus.Fire("C2Replay", { Id = "Finale" })
	CE.Advance(1)
	truthy(S() and S().Replay, "replay running")
	local t = now()
	setFinale({ State = "Bell", Stage = "Bell", StageStart = t, FightId = "F5", ChainsLeft = 4 })
	CE.Advance(1.5)
	truthy(S() and not S().Replay, "the live finale won")
	stateRoot:SetAttribute("Enabled", false)
	CE.Advance(1)
	truthy(S() == nil, "event off")
	noLeftovers("after the event switched off")
	stateRoot:SetAttribute("Enabled", true)
	setFinale({ State = "", Stage = "", FightId = "" })
	CE.Advance(1)
end)

test("quality Low + Reduced Motion: the finale still runs, no camera shots", function()
	CE.Player:SetAttribute("LowFX", true)
	CE.Player:SetAttribute("ReducedMotion", true)
	local t = now()
	setFinale({ State = "FakeDeath", Stage = "FakeDeath", StageStart = t, FightId = "F6" })
	finale({ Stage = "FakeDeath", At = t, Seconds = 6 })
	CE.Advance(6.2)
	setFinale({ State = "Bell", Stage = "Bell", StageStart = now() })
	finale({ Stage = "Bell", StartAt = now(), BellCF = BELL_CF, Chains = ANCHORS, Pulse = 1.2, Bright = .55, Need = 6 })
	CE.Advance(3)
	truthy(S() and S().Bell, "bell on low quality")
	FinaleFX.Debug.Teardown("Test", true)
	setFinale({ State = "", Stage = "", FightId = "" })
	CE.Advance(1)
	noLeftovers("after low quality")
	CE.Player:SetAttribute("LowFX", nil)
	CE.Player:SetAttribute("ReducedMotion", nil)
end)

test("no runtime errors or presentation warnings", function()
	local bad = {}
	for _, w in ipairs(CE.Warnings) do
		if string.find(w, "FinaleFX", 1, true) or string.find(w, "BossFX", 1, true) or string.find(w, "Cinema", 1, true) then
			table.insert(bad, w)
		end
	end
	eq(#CE.Errors, 0, "errors:\n" .. table.concat(CE.Errors, "\n"))
	eq(#bad, 0, "warnings:\n" .. table.concat(bad, "\n"))
end)

print(string.format("finale_client: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("finale_client tests failed")
end
