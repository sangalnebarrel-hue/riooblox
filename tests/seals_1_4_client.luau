--!nocheck
-- BELL SEALS I-IV client, headless (tests/lib/client_env.luau): lune run tests/seals_1_4_client.luau
-- Drives the real HalloweenClient.Trials host and its presenters (Trials.Echo / Run / Mirror / Mine) frame by frame in a
-- fake client with a small fake Underyard (mirror headstones, checkpoint arches, pendulum hinges, prompts on anchors)
-- and fake Chapter2State / Cinema / FX / Audio, and checks what matters:
--   * the §24.1 dispatcher: every presenter loads with the contract, Start / Update / Signal / Stop get the payloads,
--     late joins, a run whose signal never came is closed, ctx.Trials has its helpers;
--   * the trial HUD (time bar, score, Gold target + state, lines, party, LEAVE with its confirm) fits desktop and phone
--     screens in English and Russian; the countdown holds the runner only until GO; the results card fits and lists the
--     seal's rewards; the seal-clear cinematic reveals the held seal state (Bus UySealReveal) and is replayable;
--   * trial prompts: TURN / CONSULT only for Mirror Graves runners, BEGIN TRIAL / altars hidden during a trial;
--   * the presenters' world visuals appear on their targets and everything they touch is restored on Stop.
-- DUMP_DIR=<dir> writes the HUD / results layouts as JSON for offline PNG renders (scratch QA only).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")
local CE = require("./lib/client_env")

local V3 = roblox.Vector3
local CF = roblox.CFrame
local Color3 = roblox.Color3

local passed, failed = 0, 0
local function test(name, fn)
	local before = #CE.Errors
	local ok, err = pcall(fn)
	if ok and #CE.Errors > before then
		ok, err = false, "task error: " .. CE.Errors[before + 1]
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
local function yes(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function no(v, msg)
	if v then
		error(msg or "expected falsy", 2)
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-3) then
		error((msg or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a), 2)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- fake world
---------------------------------------------------------------------------------------------------------------------
local RS = CE.MountReplicated()
local Halloween = RS:FindFirstChild("Halloween")
local State = CE.Folder("State", Halloween)
State:SetAttribute("Enabled", true)
local Layout = CE.Require(Halloween:FindFirstChild("UnderyardLayout"))
local Rules = CE.Require(Halloween:FindFirstChild("SealRules"))
local Cfg = CE.Require(Halloween:FindFirstChild("Chapter2Config"))
local Shared = CE.Require(Halloween:FindFirstChild("Shared"))
local Bus = CE.Require(Halloween:FindFirstChild("Bus"))

-- CollectionService: the tagged Strike targets
local tagged = {}
local tagAdded = CE.Signal.new()
local tagRemoved = CE.Signal.new()
local CS = CE.Service("CollectionService")
CS.GetTagged = function(_, _tag)
	return table.clone(tagged)
end
CS.GetInstanceAddedSignal = function(_, _tag)
	return tagAdded
end
CS.GetInstanceRemovedSignal = function(_, _tag)
	return tagRemoved
end
local live = CE.Folder("HalloweenLive", CE.Workspace)
local targets = CE.Folder("Targets", live)
local nextTarget = 0
local function addTarget(kind, pos, attrs)
	nextTarget += 1
	local p = CE.Part("Target_" .. nextTarget, pos, V3.new(6, 4, 6), targets)
	p.Transparency = 1
	p:SetAttribute("TargetId", nextTarget)
	p:SetAttribute("Kind", kind)
	p:SetAttribute("HP", 10)
	p:SetAttribute("MaxHP", 10)
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	table.insert(tagged, p)
	tagAdded:Fire(p)
	return p
end
local function removeTarget(p, reason)
	p:SetAttribute("EndReason", reason)
	local i = table.find(tagged, p)
	if i then
		table.remove(tagged, i)
	end
	CE.task.delay(.6, function()
		tagRemoved:Fire(p)
		p:Destroy()
	end)
end

local district = CE.Model("DOGROTS_District", CE.Workspace)
local underyard = CE.Model("40_Underyard", district)
local anchors = CE.Folder("Anchors", underyard)
local function anchor(name)
	local p = CE.Part(name, Layout.Anchor(name), V3.new(1, 1, 1), anchors)
	p.Transparency = 1
	return p
end
local function prompt(parent, name, attrs)
	local pr = CE.Instance.new("ProximityPrompt")
	pr.Name = name
	pr.Enabled = true
	for k, v in pairs(attrs) do
		pr:SetAttribute(k, v)
	end
	pr.Parent = parent
	return pr
end
-- prompts as the server makes them (Seals + SealMirror)
local consultAnchor = anchor("PondConsult")
local beginPrompt = prompt(consultAnchor, "UyTrialPrompt", { UyTrialId = "MirrorGraves" })
local consultPrompt = prompt(consultAnchor, "UyMirrorConsult", { UyTrialOnly = "MirrorGraves", MirrorConsult = true })
local turnPrompt = prompt(anchor("MirrorGrave_1"), "UyMirrorTurn", { UyTrialOnly = "MirrorGraves", MirrorGrave = 1 })
local altarPrompt = prompt(anchor("SealAltar_1"), "UySealPrompt", { UySeal = 1 })
local otherPrompt = prompt(anchor("TollBox"), "UyTollBoxPrompt", {})

-- the marsh: six turning headstones (hinge PrimaryPart at the plinth top, rune on +Z)
local marsh = CE.Model("MourningMarsh", underyard)
local graves = CE.Model("MirrorGraves", marsh)
local stones = {}
for g, p in ipairs(Layout.MirrorGraves) do
	local m = CE.Model("MirrorGrave_" .. g .. "_Stone", graves)
	local hinge = CE.Part("StoneHinge", V3.new(p.X, 1.3, p.Z), V3.new(1, .2, 1), m)
	m.PrimaryPart = hinge
	CE.Part("Headstone", V3.new(p.X, 3.4, p.Z), V3.new(2.2, 4.2, 2.2), m)
	local panel = CE.Part("RunePanel", V3.new(p.X, 3.3, p.Z + 1.13), V3.new(1.8, 2.2, .06), m)
	panel.Color = Color3.fromRGB(16, 12, 26)
	local glyph = CE.Part("RuneGlyph", V3.new(p.X, 3.3, p.Z + 1.16), V3.new(.2, 1.4, .1), m)
	glyph.Color = Color3.fromRGB(150, 80, 230)
	glyph.Material = roblox.Enum.Material.Neon
	m:SetAttribute("MirrorGrave", g)
	stones[g] = m
end

-- the carnival: ten checkpoint arches (RunRing hoops) + three pendulum hinges
local carnival = CE.Model("FuneralCarnival", underyard)
local runModel = CE.Model("FuneralRun", carnival)
local arches = CE.Model("Checkpoints", runModel)
local ringParts = {}
for i, p in ipairs(Layout.Carnival.Checkpoints) do
	local a = CE.Model("RunCheckpoint_" .. i, arches)
	a:SetAttribute("RunCheckpoint", i)
	ringParts[i] = {}
	for k = 1, 3 do
		local r = CE.Part("RunRing", V3.new(p.X + k, 7, p.Z), V3.new(.32, .32, 2), a)
		r.Color = Color3.fromRGB(150, 80, 230)
		r.Material = roblox.Enum.Material.Neon
		r.Transparency = .1
		table.insert(ringParts[i], r)
	end
end
local pendulums = CE.Model("Pendulums", runModel)
for i, p in ipairs(Layout.Carnival.Pendulums) do
	local m = CE.Model("RunPendulum_" .. i, pendulums)
	m.PrimaryPart = CE.Part("PendulumHinge", V3.new(p.X, 17, p.Z), V3.new(.8, .8, .8), m)
	m:SetAttribute("UySwingAmp", 1)
	m:SetAttribute("UySwingPeriod", 3.2)
	m:SetAttribute("UySwingPhase", (i - 1) * 2 * math.pi / 3)
	anchor("RunPendulum_" .. i) -- an anchor PART with the same name: presenters must find the model
end

-- the local player, the main ScreenGui (Kit), a fake Halloween ctx
local player = CE.Player
player:SetAttribute("HalloweenChapter1Complete", true)
player:SetAttribute("UyInZone", true)
player:SetAttribute("UyTrial", "")
CE.Spawn(V3.new(0, 3, 2366))
local main = CE.MainGui()
main:SetAttribute("HwStripBottom", 64)

local log = { Banners = {}, Toasts = {}, Sounds = {}, FX = {}, Requests = {}, Reveals = 0, Locks = {}, Plays = {}, Titles = {} }
local fakeFX = setmetatable({}, {
	__index = function(_, name)
		return function(...)
			table.insert(log.FX, { Name = name, Args = table.pack(...) })
		end
	end,
})
local fakeAudio = {
	Play = function(cue, _where, opts)
		table.insert(log.Sounds, { Cue = cue, Pitch = opts and opts.Pitch })
	end,
	Has = function()
		return true
	end,
}
local fakeCS = {
	Request = function(action, args)
		table.insert(log.Requests, { Action = action, Args = args })
		return true, {}
	end,
	T = function(t)
		return t
	end,
}
local cinemaBusy = false
local fakeCinema = {
	Play = function(opts)
		if cinemaBusy then
			return nil, "Busy"
		end
		table.insert(log.Plays, opts)
		return { Cancel = function() end }
	end,
	Blocked = function()
		return nil
	end,
	LockControls = function(reason)
		log.Locks[reason] = (log.Locks[reason] or 0) + 1
	end,
	Unlock = function(reason)
		log.Locks[reason] = (log.Locks[reason] or 0) - 1
	end,
	Title = function(en, ru)
		table.insert(log.Titles, { En = en, Ru = ru })
		return { Hide = function() end }
	end,
	Flash = function() end,
	Shake = function() end,
	LookAt = function(from, to)
		local d = (to - from).Unit
		local r = d:Cross(V3.new(0, 1, 0)).Unit
		return CF.fromMatrix(from, r, r:Cross(d), -d)
	end,
}
Bus.On("Banner", function(d)
	table.insert(log.Banners, d)
end)
Bus.On("Toast", function(d)
	table.insert(log.Toasts, d)
end)
Bus.On("UySealReveal", function()
	log.Reveals += 1
end)
local ctx = { Player = player, Shared = Shared, Config = Shared.Config, Bus = Bus, FX = fakeFX, Audio = fakeAudio,
	Modules = { Chapter2State = fakeCS, Cinema = fakeCinema } }

local HC = CE.Folder("HalloweenClient", CE.PlayerGui)
CE.Mount("StarterPlayer/StarterPlayerScripts/HalloweenClient", HC)
local TrialsModule = HC:FindFirstChild("Trials")
local Trials = CE.Require(TrialsModule)
CE.task.spawn(Trials.Start, ctx)
CE.Advance(.5)

local function signal(kind, data)
	Bus.Fire("C2Signal", { Kind = kind, Data = data })
	CE.Advance(.05)
end
local function hudGui()
	return CE.PlayerGui:FindFirstChild("DOGROTS_TrialHUD")
end
local function fxFolder()
	return CE.Workspace:FindFirstChild("DOGROTS_TrialsFX")
end
local function countIn(folder, name)
	local n = 0
	for _, d in ipairs(folder and folder:GetDescendants() or {}) do
		if d.Name == name then
			n += 1
		end
	end
	return n
end
local function camAt(pos)
	CE.Camera.CFrame = CF.new(pos + V3.new(0, 14, 24))
end
local function lastToast()
	return log.Toasts[#log.Toasts]
end
local runSerial = 100
local function payload(kind, trialId, seal, data, extra)
	local p = { Kind = kind, TrialId = trialId, Seal = seal, RunId = runSerial, StartedAt = CE.Unix, EndsAt = CE.Unix + 3 + Cfg.Seals[seal].Trial.TimeLimit,
		Players = { 1 }, Score = { ["1"] = 0 }, Total = 0, Goal = Cfg.Seals[seal].Trial.Goal, Data = data, State = "Running" }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

---------------------------------------------------------------------------------------------------------------------
-- layout dump (DUMP_DIR): the GUI rectangles + texts of a ScreenGui, for an offline PNG render
---------------------------------------------------------------------------------------------------------------------
local DUMP = process.env.DUMP_DIR
local function dumpGui(guis, file)
	if not DUMP then
		return
	end
	local out = { Screen = { CE.Screen.X, CE.Screen.Y }, Items = {} }
	local order = 0
	local function walk(o)
		for _, c in ipairs(o:GetChildren()) do
			if c:IsA("GuiObject") and CE.Shown(c) then
				order += 1
				local p, s = c.AbsolutePosition, c.AbsoluteSize
				local text = (c.ClassName == "TextLabel" or c.ClassName == "TextButton") and c.Text or nil
				local stroke = c:FindFirstChildOfClass("UIStroke")
				local bg = c.BackgroundColor3
				local grad = c:FindFirstChildOfClass("UIGradient")
				local g0, g1 = nil, nil
				if grad and grad.Color then
					local kp = grad.Color.Keypoints
					g0, g1 = kp[1].Value, kp[#kp].Value
				end
				table.insert(out.Items, {
					Grad = g0 and { { g0.R, g0.G, g0.B }, { g1.R, g1.G, g1.B } } or nil,
					Name = c.Name, Class = c.ClassName, X = p.X, Y = p.Y, W = s.X, H = s.Y, Order = order, Rotation = c.Rotation or 0,
					Bg = bg and { bg.R, bg.G, bg.B } or nil, BgT = c.BackgroundTransparency,
					Text = text, TextColor = c.TextColor3 and { c.TextColor3.R, c.TextColor3.G, c.TextColor3.B } or nil,
					TextSize = c.TextSize, Align = c.TextXAlignment and tostring(c.TextXAlignment) or nil,
					Stroke = stroke and { stroke.Color.R, stroke.Color.G, stroke.Color.B } or nil, Round = c:FindFirstChildOfClass("UICorner") ~= nil,
				})
				walk(c)
			end
		end
	end
	for _, g in ipairs(guis) do
		if g then
			walk(g)
		end
	end
	fs.writeFile(DUMP .. "/" .. file .. ".json", serde.encode("json", out))
end

-- every visible GuiObject of a gui lies on the screen
local function onScreen(gui, label)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiObject") and CE.Shown(d) and d.AbsoluteSize.X > 0 and d.Name ~= "Fill" and d.Name ~= "Shine" then
			local p, s = d.AbsolutePosition, d.AbsoluteSize
			if p.X < -1 or p.Y < -1 or p.X + s.X > CE.Screen.X + 1 or p.Y + s.Y > CE.Screen.Y + 1 then
				error(label .. ": " .. d.Name .. " off screen at " .. tostring(p) .. " size " .. tostring(s), 2)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the dispatcher
---------------------------------------------------------------------------------------------------------------------
test("presenters load with the §24.1 contract; ctx.Trials helpers", function()
	for _, id in ipairs({ "EchoDig", "FuneralRun", "MirrorGraves", "HollowMine" }) do
		local p = Trials.Presenters[id]
		yes(p, "presenter for " .. id)
		for _, fn in ipairs({ "Start", "Update", "Signal", "Stop", "HudLines" }) do
			eq(type(p[fn]), "function", id .. "." .. fn)
		end
		eq(type(p.Ids), "table")
	end
	-- every presenter module under HalloweenClient/Trials loads (seals I-IV here, V-VII + resonance + assault from
	-- WP-J, the Toll / Mourner practice trials from WP-H2)
	local presenterFiles = 0
	for _, name in ipairs(require("@lune/fs").readDir("src/StarterPlayer/StarterPlayerScripts/HalloweenClient/Trials")) do
		if string.match(name, "%.luau$") then
			presenterFiles += 1
		end
	end
	eq(#Trials.Loaded, presenterFiles, "every child module of Trials")
	for _, id in ipairs({ "DoorChallenge", "Doorkeeper", "ChoirHunt", "LastBell", "Assault", "Toll", "Mourner" }) do
		yes(Trials.Presenters[id], "presenter for " .. id)
	end
	local T = ctx.Trials
	yes(T, "ctx.Trials")
	for _, fn in ipairs({ "Request", "Run", "Banner", "Toast", "Mark" }) do
		eq(type(T[fn]), "function", "ctx.Trials." .. fn)
	end
	eq(T.Cinema, fakeCinema, "Cinema")
	-- Request wraps C2Trial
	T.Request("Turn", { Grave = 3 })
	local r = log.Requests[#log.Requests]
	eq(r.Action, "C2Trial")
	eq(r.Args.Action, "Turn")
	eq(r.Args.Grave, 3)
	-- Mark: a world marker with a Destroy the presenters can call any way
	local h = T.Mark(V3.new(10, 3, 2400), "HERE", "ЗДЕСЬ")
	yes(h and h.Part and h.Part.Parent, "mark part")
	h.Destroy(h)
	eq(h.Part.Parent, nil, "destroyed")
end)

test("trial prompts: TURN / CONSULT only for Mirror Graves runners; BEGIN TRIAL and altars hidden in a trial", function()
	CE.Advance(2.2)
	eq(beginPrompt.Enabled, true, "begin shown outside a trial")
	eq(consultPrompt.Enabled, false, "consult hidden outside")
	eq(turnPrompt.Enabled, false, "turn hidden outside")
	eq(altarPrompt.Enabled, true, "altar shown outside")
	player:SetAttribute("UyTrial", "MirrorGraves:7")
	CE.Advance(.1)
	eq(beginPrompt.Enabled, false, "begin hidden in a trial")
	eq(consultPrompt.Enabled, true, "consult for runners")
	eq(turnPrompt.Enabled, true, "turn for runners")
	eq(altarPrompt.Enabled, false, "altar hidden in a trial")
	player:SetAttribute("UyTrial", "EchoDig:8")
	CE.Advance(.1)
	eq(consultPrompt.Enabled, false, "not for other trials' runners")
	eq(otherPrompt.Enabled, true, "other prompts untouched")
	player:SetAttribute("UyTrial", "")
	CE.Advance(.1)
	eq(beginPrompt.Enabled, true)
	eq(Trials.PromptWanted(consultPrompt, "MirrorGravesX:1"), false, "the id must match exactly")
end)

test("Gold criteria: text pieces and the live state", function()
	local parts = Trials.GoldParts(1, { "ECHOES", "ЭХО" })
	eq(#parts, 2)
	eq(parts[1][1], "18 ECHOES")
	eq(parts[2][1], "60% PERFECT")
	eq(Trials.GoldParts(2)[1][1], "UNDER 0:55")
	eq(Trials.GoldParts(3)[1][1], "NO MISTAKES")
	eq(Trials.GoldParts(4)[2][1], "NEVER DOWNED")
	local now = CE.Unix
	eq(Trials.GoldState(2, { Data = { GoAt = now - 30 } }, {}), "On")
	eq(Trials.GoldState(2, { Data = { GoAt = now - 60 } }, {}), "Lost", "over 55 s")
	eq(Trials.GoldState(2, { Data = { GoAt = now - 60, Finish = { ["1"] = 50 } } }, {}), "On", "finished in time")
	eq(Trials.GoldState(3, { Data = { Wrong = 1 } }, {}), "Lost")
	eq(Trials.GoldState(4, { Data = {} }, { Downed = true }), "Lost")
	eq(Trials.GoldState(1, { Data = { Hits = 10, Perfects = 3 } }, {}), "Behind")
	eq(Trials.GoldState(1, { Data = { Hits = 10, Perfects = 7 } }, {}), "On")
end)

---------------------------------------------------------------------------------------------------------------------
-- ECHO DIG
---------------------------------------------------------------------------------------------------------------------
local echoRun
test("ECHO DIG: HUD, countdown, echo mounds on our targets, life ring, telegraphed jump, H09 mark, dig burst", function()
	runSerial += 1
	player:SetAttribute("UyTrial", "EchoDig:" .. runSerial)
	camAt(Layout.Anchor("EchoPoint_3"))
	local goAt = CE.Unix + 3
	local data = { GoAt = goAt, Goal = 12, Gold = { Total = 18, PerfectShare = .6 }, Dug = 0, Hits = 0, Perfects = 0, Pup = true, Life = 8.5 }
	echoRun = payload("Start", "EchoDig", 1, data)
	signal("C2Trial", echoRun)
	local gui = hudGui()
	yes(gui, "HUD")
	local card = gui:FindFirstChild("TrialCard")
	eq(card.Title.Text, "ECHO DIG")
	eq(card.Badge.Numeral.Text, "I")
	eq(card.Score.Text, "0 / 12")
	eq(card.ScoreLabel.Text, "ECHOES")
	yes(string.find(card.Gold.Text.Text, "18 ECHOES", 1, true) and string.find(card.Gold.Text.Text, "60% PERFECT", 1, true), card.Gold.Text.Text)
	yes(CE.PlayerGui:FindFirstChild("DOGROTS_TrialCountdown"), "countdown")
	eq(log.Locks.TrialCountdown, nil, "the echo dig does not hold the player")
	local banner = log.Banners[#log.Banners]
	eq(banner.Title, "ECHO DIG")
	-- an echo of OUR run rises; a stranger's (another run) is ignored
	local ground = Layout.Anchor("EchoPoint_3")
	local t = addTarget("UyEcho", ground + V3.new(0, 2.2, 0), { UyRun = runSerial, Ground = ground, Facing = .5, LifeFrom = CE.Unix, Life = 8.5,
		ExpireAt = CE.Unix + 8.5, Index = 3, NextPos = Layout.Anchor("EchoPoint_9") })
	addTarget("UyEcho", Layout.Anchor("EchoPoint_4") + V3.new(0, 2.2, 0), { UyRun = 999, Ground = Layout.Anchor("EchoPoint_4") })
	CE.Advance(.8)
	eq(countIn(fxFolder(), "EchoMound"), 1, "one mound (ours)")
	eq(countIn(fxFolder(), "EchoNextMark"), 1, "H09: the next landing point")
	local active = Trials.Presenters.EchoDig.Active()
	local rec = active.Recs[t]
	yes(rec, "record")
	near((rec.Model:GetPivot().Position - ground).Magnitude, 0, .05, "risen onto the point")
	-- the life ring empties with the time
	CE.Advance(3)
	CE.Advance(1.2) -- (countdown over)
	local lit = 0
	for _, seg in ipairs(rec.P.Ring) do
		if seg.Transparency < .5 then
			lit += 1
		end
	end
	yes(lit < #rec.P.Ring and lit > 0, "life ring partly empty: " .. lit)
	eq(CE.PlayerGui:FindFirstChild("DOGROTS_TrialCountdown"), nil, "countdown gone after GO")
	-- the server telegraphs the jump: arc + landing rune
	local to = Layout.Anchor("EchoPoint_9")
	t:SetAttribute("JumpTo", to)
	t:SetAttribute("JumpAt", CE.Unix + 1.2)
	CE.Advance(.2)
	eq(countIn(fxFolder(), "EchoJumpTrail"), 1, "jump trail")
	eq(countIn(fxFolder(), "EchoNextMark"), 0, "the next mark gives way to the trail")
	-- the jump: the target moves (Ground), the mound goes along
	t:SetAttribute("JumpTo", nil)
	t:SetAttribute("Ground", to)
	t:SetAttribute("NextPos", nil)
	CE.Advance(1.3)
	eq(countIn(fxFolder(), "EchoJumpTrail"), 0, "trail gone")
	near((rec.Model:GetPivot().Position - to).Magnitude, 0, .05, "the mound rose at the new point")
	-- HUD lines (presenter) + score
	signal("C2Trial", payload("Score", "EchoDig", 1, { GoAt = goAt, Goal = 12, Dug = 1, Hits = 4, Perfects = 3, Pup = true, Life = 8.5 }, { Total = 1,
		Score = { ["1"] = 1 } }))
	CE.Advance(.2)
	eq(card.Score.Text, "1 / 12")
	yes(string.find(card.Line2.Text, "3 / 4", 1, true), "perfect share line: " .. card.Line2.Text)
	yes(string.find(card.Line3.Text, "Bell Pup", 1, true), "Bell Pup line")
	-- dug (Broke): the burst + the mound goes
	Bus.Fire("StrikeSwing", { Part = t, Perfect = true })
	CE.Advance(.05)
	removeTarget(t, "Broke")
	CE.Advance(1.5)
	eq(countIn(fxFolder(), "EchoMound"), 0, "dug: gone")
	local burst = false
	for _, f in ipairs(log.FX) do
		if f.Name == "Burst" then
			burst = true
		end
	end
	yes(burst, "burst")
end)

test("HUD: the time bar, the last-seconds ticks, LEAVE needs a second tap", function()
	local card = hudGui().TrialCard
	local leave = card:FindFirstChild("Leave")
	yes(leave.AbsoluteSize.Y >= 44, "LEAVE is a 44 px touch target")
	CE.Click(leave)
	CE.Advance(.15)
	eq(leave.Label.Text, "SURE?", "armed")
	local before = #log.Requests
	CE.Advance(3.2)
	eq(leave.Label.Text, "LEAVE", "disarms after a moment")
	CE.Click(leave)
	CE.Advance(.1)
	CE.Click(leave)
	CE.Advance(.1)
	eq(#log.Requests, before + 1, "one leave request")
	eq(log.Requests[#log.Requests].Action, "C2TrialLeave")
	-- the last seconds
	local cur = Trials.Current()
	local endsAt = CE.Unix + 4.5
	signal("C2Trial", payload("Tick", "EchoDig", 1, cur.Payload.Data, { EndsAt = endsAt, Total = 1 }))
	local n0 = 0
	for _, s in ipairs(log.Sounds) do
		if s.Cue == "TrialTick" then
			n0 += 1
		end
	end
	CE.Advance(2.2)
	local n1 = 0
	for _, s in ipairs(log.Sounds) do
		if s.Cue == "TrialTick" then
			n1 += 1
		end
	end
	yes(n1 - n0 >= 2, "a tick per second in the last 5 s")
	yes(string.find(card.Time.Text, "%.") ~= nil, "tenths in the last 10 s: " .. card.Time.Text)
end)

local function dumpLayouts(tag)
	for _, s in ipairs({ { "desktop", 1280, 720 }, { "phone_land", 844, 390 }, { "phone_port", 390, 844 } }) do
		CE.Screen = roblox.Vector2.new(s[2], s[3])
		Trials.Refresh()
		CE.Advance(.15)
		onScreen(hudGui(), tag .. " " .. s[1])
		dumpGui({ hudGui() }, tag .. "_" .. s[1])
	end
	CE.Screen = roblox.Vector2.new(1280, 720)
	Trials.Refresh()
end

test("HUD layout: desktop / phone landscape / phone portrait, English and Russian, with a party", function()
	local cur = Trials.Current()
	signal("C2Trial", payload("Tick", "EchoDig", 1, cur.Payload.Data, { EndsAt = CE.Unix + 60, Total = 7, Players = { 1, 2, 3 },
		Score = { ["1"] = 4, ["2"] = 2, ["3"] = 1 } }))
	dumpLayouts("hud_en")
	player:SetAttribute("DOGROTS_Language", "ru")
	CE.Advance(5.1) -- (the language cache)
	Trials.Refresh()
	CE.Advance(.2)
	local card = hudGui().TrialCard
	eq(card.Title.Text, "ЭХО-РАСКОПКИ")
	eq(card.Leave.Label.Text, "ВЫЙТИ")
	dumpLayouts("hud_ru")
	player:SetAttribute("DOGROTS_Language", nil)
	CE.Advance(5.1)
	-- the party box lists three members
	local party = hudGui():FindFirstChild("Party")
	yes(CE.Shown(party), "party shown")
	yes(CE.Shown(party.Member3) and not CE.Shown(party.Member4), "three rows")
	-- phone landscape with a full party of six: the card stays clear of the screen centre (the character) and the party
	-- rows that do not fit fold into "+k"
	CE.Screen = roblox.Vector2.new(844, 390)
	main:SetAttribute("HUDInnerLeft", 136)
	main:SetAttribute("HUDInnerRight", 786)
	for _, stripBottom in ipairs({ 63, 121 }) do
		main:SetAttribute("HwStripBottom", stripBottom)
		signal("C2Trial", payload("Tick", "EchoDig", 1, cur.Payload.Data, { EndsAt = CE.Unix + 60, Total = 7, Players = { 1, 2, 3, 4, 5, 6 },
			Score = { ["1"] = 4, ["2"] = 2, ["3"] = 1, ["4"] = 1, ["5"] = 0, ["6"] = 0 } }))
		Trials.Refresh()
		CE.Advance(.2)
		onScreen(hudGui(), "phone_land party of 6, strip " .. stripBottom)
		local c = hudGui().TrialCard
		local p, sz = c.AbsolutePosition, c.AbsoluteSize
		yes(not (p.X <= 422 and p.X + sz.X >= 422 and p.Y <= 195 and p.Y + sz.Y >= 195), "card clear of the screen centre")
	end
	for _, k in ipairs({ "HUDInnerLeft", "HUDInnerRight", "HwStripBottom" }) do
		main:SetAttribute(k, nil)
	end
	CE.Screen = roblox.Vector2.new(1280, 720)
	signal("C2Trial", payload("Tick", "EchoDig", 1, cur.Payload.Data, { EndsAt = CE.Unix + 60, Total = 7, Players = { 1, 2, 3 },
		Score = { ["1"] = 4, ["2"] = 2, ["3"] = 1 } }))
	Trials.Refresh()
	CE.Advance(.2)
	-- hidden with menus / HIDE UI / cinematics
	main:SetAttribute("OpenMenu", "Shop")
	CE.Advance(.2)
	eq(hudGui().Enabled, false, "hidden with a menu")
	main:SetAttribute("OpenMenu", nil)
	main:SetAttribute("CinemaActive", true)
	CE.Advance(.2)
	eq(hudGui().Enabled, false, "hidden during a cinematic")
	main:SetAttribute("CinemaActive", nil)
	CE.Advance(.2)
	eq(hudGui().Enabled, true)
end)

test("ECHO DIG won + C2Seal Cleared/Gold: stamp, seal cinematic (reveal), results card with the rewards", function()
	local cur = Trials.Current()
	local runId = cur.RunId
	local won = payload("Won", "EchoDig", 1, cur.Payload.Data, { RunId = runId, Total = 18, Gold = { ["1"] = true }, Elapsed = 80 })
	local revealsBefore = log.Reveals
	signal("C2Trial", won)
	eq(hudGui(), nil, "HUD torn down")
	eq(Trials.Current(), nil)
	CE.Advance(.6)
	eq(countIn(fxFolder(), "EchoMound"), 0, "mounds gone with the run")
	signal("C2Seal", { Seal = 1, Stage = "Cleared", Rewards = { { Kind = "Shards", Amount = 150 }, { Kind = "Key", Amount = 1 },
		{ Kind = "Dog", Id = "HW_BellPup", Amount = 1 } } })
	signal("C2Seal", { Seal = 1, Stage = "Gold", Rewards = { { Kind = "Key", Amount = 1 } } })
	CE.Advance(2.5)
	local play = log.Plays[#log.Plays]
	yes(play and play.Id == "SealClear", "the seal cinematic")
	yes(play.Duration > 9, "full cinematic for a first clear")
	-- the shots are finite CFrames all the way
	for t = 0, play.Duration, .5 do
		local cf = play.Shot(t)
		yes(cf and cf.Position.Magnitude < 1e5, "shot at " .. t)
	end
	-- run the timeline (the reveal is Always) then end the cinematic
	for _, e in ipairs(play.Timeline) do
		e[2]()
	end
	yes(log.Reveals > revealsBefore, "UySealReveal fired")
	yes(countIn(fxFolder(), "AltarFlare") == 1, "the altar ignites")
	play.OnDone(true)
	CE.Advance(.3)
	local res = CE.PlayerGui:FindFirstChild("DOGROTS_TrialResults")
	yes(res, "results card")
	local rc = res.ResultCard
	eq(rc.Head.Text, "BELL SEAL I BROKEN!")
	eq(rc.Rank.Text, "RANK: GOLD")
	local texts = {}
	for _, d in ipairs(rc:GetChildren()) do
		if d.Name == "Reward" then
			table.insert(texts, d.Text)
		end
	end
	eq(#texts, 4, "four reward rows")
	yes(string.find(texts[1], "150", 1, true) and string.find(texts[1], "Bell Shards", 1, true), texts[1])
	yes(string.find(texts[3], "Bell Pup", 1, true), texts[3])
	onScreen(res, "results desktop")
	dumpGui({ res }, "results_en_desktop")
	CE.Advance(1.5)
	eq(countIn(fxFolder(), "AltarFlare"), 0, "ignition dressing cleaned")
	-- close
	CE.Click(rc.Close)
	CE.Advance(.1)
	eq(CE.PlayerGui:FindFirstChild("DOGROTS_TrialResults"), nil, "closed")
	player:SetAttribute("UyTrial", "")
end)

test("results card on phones: fits with a long reward list (two columns), Russian", function()
	for _, s in ipairs({ { "phone_land", 844, 390 }, { "phone_port", 390, 844 } }) do
		CE.Screen = roblox.Vector2.new(s[2], s[3])
		Trials.ShowResults({ Result = "Won", Gold = false, First = true, Seal = 4, Payload = { Seal = 4, TrialId = "HollowMine" },
			Stats = { { "Time", "Время", "3:41" }, { "Cores", "Ядра", "14 / 14" }, { "Perfect hits", "Идеальные удары", "40 / 61 (66%)" } },
			Rewards = { { Kind = "Shards", Amount = 250 }, { Kind = "Key", Amount = 1 }, { Kind = "Dog", Id = "HW_CandleCorgi", Amount = 1 },
				{ Kind = "Dust", Amount = 400 }, { Kind = "Fragments", Amount = 12 }, { Kind = "Decor", Id = "uy_crooked_bell_tower", Converted = true,
					Conversion = { { Kind = "Fragments", Amount = 12 }, { Kind = "Dust", Amount = 400 } } } } })
		CE.Advance(.4)
		local res = CE.PlayerGui:FindFirstChild("DOGROTS_TrialResults")
		onScreen(res, "results " .. s[1])
		local close = res.ResultCard.Close
		local cb = close.AbsolutePosition.Y + close.AbsoluteSize.Y
		local card = res.ResultCard
		yes(cb <= card.AbsolutePosition.Y + card.AbsoluteSize.Y + 1, "CLOSE on the card")
		dumpGui({ res }, "results_" .. s[1])
	end
	CE.Screen = roblox.Vector2.new(1280, 720)
	CE.Click(CE.PlayerGui.DOGROTS_TrialResults.ResultCard.Close)
	CE.Advance(.1)
end)

test("C2Replay {Id = Seal}: the cinematic plays again, nothing is requested", function()
	local before, req = #log.Plays, #log.Requests
	Bus.Fire("C2Replay", { Id = "Seal", Seal = 2 })
	CE.Advance(.3)
	eq(#log.Plays, before + 1, "replayed")
	local play = log.Plays[#log.Plays]
	eq(play.Id, "SealClear")
	play.OnDone(true)
	CE.Advance(1.5)
	eq(#log.Requests, req, "no requests")
	eq(CE.PlayerGui:FindFirstChild("DOGROTS_TrialResults"), nil, "no results card for a replay")
	-- a refused cinematic still releases the seal state
	cinemaBusy = true
	local r0 = log.Reveals
	Trials.PlaySeal(3, {})
	CE.Advance(.3)
	yes(log.Reveals > r0, "reveal even when Cinema refuses")
	cinemaBusy = false
	-- the shot plan: the gate the seal opens
	eq(Trials.OpensDistrict(1), "FuneralCarnival")
	eq(Trials.OpensDistrict(4), "CrookedRow")
	eq(Trials.OpensDistrict(5), nil)
	local plan = Trials.SealShots(3)
	eq(plan.Opens, "Undercrypt")
	yes(plan.Ignite < plan.Reveal and plan.Reveal < plan.Duration, "beats in order")
end)

---------------------------------------------------------------------------------------------------------------------
-- FUNERAL RUN
---------------------------------------------------------------------------------------------------------------------
test("FUNERAL RUN: held start until GO, arches painted, arrow + mark, swing arcs, splits, rewind, restore on Stop", function()
	runSerial += 1
	player:SetAttribute("UyTrial", "FuneralRun:" .. runSerial)
	CE.MoveTo(Layout.Anchor("RunStart"))
	camAt(Layout.Anchor("RunStart"))
	local goAt = CE.Unix + 3
	local data = { GoAt = goAt, Gold = { Time = 55 }, Checkpoints = 10, Progress = {}, Finish = {}, Carousel = 7 }
	signal("C2Trial", payload("Start", "FuneralRun", 2, data))
	eq(log.Locks.TrialCountdown, 1, "movement held for the 3-2-1")
	CE.Advance(3.4)
	eq(log.Locks.TrialCountdown, 0, "released at GO")
	-- ring 1 is next (gold), ring 2 after it (violet), with a highlight
	eq(ringParts[1][1].Color, Color3.fromRGB(255, 210, 110), "next ring gold")
	eq(ringParts[2][1].Color, Color3.fromRGB(196, 150, 255), "the one after violet")
	eq(ringParts[5][1].Color, Color3.fromRGB(150, 80, 230), "others untouched")
	eq(countIn(fxFolder(), "TrialNextRing"), 1, "highlight")
	eq(countIn(fxFolder(), "SwingArc"), 3, "three swing arcs")
	eq(countIn(fxFolder(), "RunArrow"), 1, "guide arrow")
	eq(countIn(fxFolder(), "TrialMark"), 1, "mark over the next ring")
	-- the arc dash under the coffin lights up (the §24.2 formula on the server clock)
	local run = Trials.Presenters.FuneralRun.Active()
	local arc = run.Arcs[1]
	local angle = Rules.SwingAngle(CE.Unix, arc.Spec.Amp, arc.Spec.Period, arc.Spec.Phase)
	local best, bestT = nil, 9
	for _, d in ipairs(arc.P.Dashes) do
		if math.abs(d:GetAttribute("A") - angle) < (best and math.abs(best:GetAttribute("A") - angle) or 9) then
			best, bestT = d, d.Transparency
		end
	end
	yes(bestT < .3, "the dash under the coffin is bright")
	near(arc.Spec.Phase, 0, 1e-9, "pendulum 1 phase from its model")
	-- the arrow points at ring 1
	local arrow = run.Arrow.Model:GetPivot()
	local want = Rules.Flat(Layout.Anchor("RunCheckpoint_1") - Layout.Anchor("RunStart")).Unit
	local look = Rules.Flat(arrow.LookVector).Unit
	yes(look:Dot(want) > .9, "arrow towards ring 1")
	-- ring 1 credited
	data.Progress = { ["1"] = 1 }
	signal("C2Trial", payload("Checkpoint", "FuneralRun", 2, data, { UserId = 1, Index = 1, Split = 3.21 }))
	CE.Advance(.1)
	eq(ringParts[1][1].Color, Color3.fromRGB(120, 255, 140), "passed ring green")
	eq(ringParts[2][1].Color, Color3.fromRGB(255, 210, 110), "ring 2 next")
	local card = hudGui().TrialCard
	eq(card.Score.Text, "1 / 10", "YOUR rings")
	yes(string.find(card.Line1.Text, "ring 2", 1, true), card.Line1.Text)
	-- the carousel hint on the leg that crosses the deck
	data.Progress = { ["1"] = 7 }
	signal("C2Trial", payload("Tick", "FuneralRun", 2, data))
	CE.Advance(.2)
	yes(string.find(card.Line2.Text, "carousel", 1, true), "carousel hint: " .. tostring(card.Line2.Text))
	-- rewind: back to ring 3
	signal("C2Trial", payload("Rewind", "FuneralRun", 2, data, { UserId = 1, Index = 4, Reason = "TooFast", Violations = 1 }))
	yes(string.find(lastToast().Text, "back to ring 3", 1, true), lastToast().Text)
	eq(ringParts[4][1].Color, Color3.fromRGB(255, 210, 110), "ring 4 next again")
	-- failed: everything restored
	signal("C2Trial", payload("Failed", "FuneralRun", 2, data, { Reason = "Time" }))
	CE.Advance(2)
	for i = 1, 10 do
		eq(ringParts[i][1].Color, Color3.fromRGB(150, 80, 230), "ring " .. i .. " restored")
		near(ringParts[i][1].Transparency, .1, 1e-6)
	end
	eq(countIn(fxFolder(), "TrialNextRing"), 0, "highlight gone")
	eq(countIn(fxFolder(), "SwingArc"), 0, "arcs gone")
	eq(countIn(fxFolder(), "RunArrow"), 0, "arrow gone")
	eq(countIn(fxFolder(), "TrialMark"), 0, "marks gone")
	local res = CE.PlayerGui:FindFirstChild("DOGROTS_TrialResults")
	yes(res and res.ResultCard.Head.Text == "TRIAL FAILED", "failed card")
	yes(string.find(res.ResultCard.Sub.Text, "Time ran out", 1, true), res.ResultCard.Sub.Text)
	CE.Click(res.ResultCard.Close)
	player:SetAttribute("UyTrial", "")
	CE.Advance(.2)
end)

---------------------------------------------------------------------------------------------------------------------
-- MIRROR GRAVES
---------------------------------------------------------------------------------------------------------------------
local function runeFacing(g)
	local hinge = stones[g].PrimaryPart.CFrame
	return hinge:VectorToWorldSpace(V3.new(0, 0, 1))
end

test("MIRROR GRAVES: stones turn to the run's facings, mirror runes, the pond's reflection, turn / round / wrong, restore", function()
	runSerial += 1
	player:SetAttribute("UyTrial", "MirrorGraves:" .. runSerial)
	camAt(Layout.Anchor("MirrorPond"))
	local round = { Index = 1, Active = { 1, 3, 4, 6 }, Target = { 1, 0, 3, 2, 0, 1 }, Start = { 0, 1, 2, 3, 0, 1 } }
	local data = { GoAt = CE.Unix + 3, ReadyAt = CE.Unix + 3, Round = 1, Rounds = 3, Active = round.Active, Reflection = Rules.Reflection(round),
		Current = { 0, 1, 2, 3, 0, 1 }, Wrong = 0, Penalty = 15, Gold = { NoMistakes = true } }
	signal("C2Trial", payload("Start", "MirrorGraves", 3, data))
	CE.Advance(1)
	-- facings: d = 1 -> the rune faces +X, 2 -> -Z, 3 -> -X
	near(runeFacing(2):Dot(V3.new(1, 0, 0)), 1, 1e-3, "grave 2 east")
	near(runeFacing(3):Dot(V3.new(0, 0, -1)), 1, 1e-3, "grave 3 north")
	near(runeFacing(4):Dot(V3.new(-1, 0, 0)), 1, 1e-3, "grave 4 west")
	near(runeFacing(1):Dot(V3.new(0, 0, 1)), 1, 1e-3, "grave 1 south (rest)")
	-- runes: awake bright, sleeping dark
	local awakeGlyph = stones[1]:FindFirstChild("RuneGlyph")
	local sleepGlyph = stones[2]:FindFirstChild("RuneGlyph")
	yes(awakeGlyph.Transparency == 0 and sleepGlyph.Transparency > .2, "awake / sleeping runes")
	-- the reflection: grave g's ghost at grave 7 - g's place facing the mirrored direction
	local folder = fxFolder()
	eq(countIn(folder, "Reflection_1") + countIn(folder, "Reflection_3") + countIn(folder, "Reflection_4") + countIn(folder, "Reflection_6"), 4,
		"four reflections")
	CE.Advance(1.5)
	local m = Trials.Presenters.MirrorGraves.Active()
	for _, r in ipairs(m.Reflection) do
		local spot = Trials.Presenters.MirrorGraves.ReflectionSpot(7 - r.Grave)
		local piv = r.Model:GetPivot()
		near(Rules.Flat(piv.Position - spot).Magnitude, 0, .05, "ghost of grave " .. r.Grave .. " at grave " .. (7 - r.Grave))
		local face = piv:VectorToWorldSpace(V3.new(0, 0, 1))
		near(face:Dot(Rules.Facing(Rules.Flip(round.Target[r.Grave]))), 1, 1e-3, "mirrored facing")
	end
	-- the mirror axis
	yes(countIn(folder, "MirrorAxis") == 1, "mirror axis")
	-- a TURN: grave 1 goes from south to east over the turn time
	data.Current = { 1, 1, 2, 3, 0, 1 }
	signal("C2Trial", payload("Turn", "MirrorGraves", 3, data, { Grave = 1, Dir = 1, UserId = 1 }))
	CE.Advance(.1)
	local mid = runeFacing(1)
	yes(mid:Dot(V3.new(1, 0, 0)) < .99, "turning, not snapped")
	CE.Advance(.5)
	near(runeFacing(1):Dot(V3.new(1, 0, 0)), 1, 1e-3, "grave 1 east")
	-- a wrong consult
	data.Wrong = 1
	signal("C2Trial", payload("Wrong", "MirrorGraves", 3, data, { Wrong = 2, Penalty = 15, UserId = 1 }))
	yes(string.find(lastToast().Text, "2 graves are still wrong", 1, true), lastToast().Text)
	local card = hudGui().TrialCard
	CE.Advance(.2)
	yes(string.find(card.Gold.Text.Text, "LOST", 1, true), "Gold lost after a wrong consult")
	-- the next round: new reflection, stones spin into the round's start
	local round2 = { Index = 2, Active = { 1, 2, 3, 5, 6 }, Target = { 2, 2, 1, 0, 3, 0 }, Start = { 3, 0, 0, 1, 2, 2 } }
	data.Round, data.Active, data.Reflection, data.Current = 2, round2.Active, Rules.Reflection(round2), { 3, 0, 0, 1, 2, 2 }
	signal("C2Trial", payload("Round", "MirrorGraves", 3, data, { Round = 2, Cleared = 1, UserId = 1 }))
	CE.Advance(2.5)
	eq(#m.Reflection, 5, "five reflections in round 2")
	near(runeFacing(1):Dot(V3.new(-1, 0, 0)), 1, 1e-3, "grave 1 west (round 2 start)")
	yes(string.find(card.Line1.Text, "Round 2 / 3", 1, true), card.Line1.Text)
	-- stop: every stone back at rest, runes restored, the reflection gone
	signal("C2Trial", payload("Left", "MirrorGraves", 3, data, { UserId = 1, Reason = "LeftDistrict" }))
	CE.Advance(1.5)
	for g = 1, 6 do
		near(runeFacing(g):Dot(V3.new(0, 0, 1)), 1, 1e-3, "grave " .. g .. " back at rest")
	end
	eq(awakeGlyph.Color, Color3.fromRGB(150, 80, 230), "rune colour restored")
	eq(countIn(fxFolder(), "MirrorAxis"), 0)
	eq(#(fxFolder():GetChildren()) <= 1, true, "no reflection left")
	local res = CE.PlayerGui:FindFirstChild("DOGROTS_TrialResults")
	yes(res and res.ResultCard.Head.Text == "OUT OF THE TRIAL", "out card")
	CE.Click(res.ResultCard.Close)
	player:SetAttribute("UyTrial", "")
	CE.Advance(.2)
end)

---------------------------------------------------------------------------------------------------------------------
-- HOLLOW MINE
---------------------------------------------------------------------------------------------------------------------
test("HOLLOW MINE: hollow ore grows on our nodes, breaks in stages, shatters; rocks / gas / collapses dressed on the floor", function()
	runSerial += 1
	player:SetAttribute("UyTrial", "HollowMine:" .. runSerial)
	CE.MoveTo(V3.new(140, -13, 2550))
	camAt(V3.new(150, -16, 2560))
	local data = { GoAt = CE.Unix, Goal = 14, Gold = { Total = 20, NoDowns = true }, Cores = 0, Nodes = 12 }
	signal("C2Trial", payload("Start", "HollowMine", 4, data))
	local ground = Layout.Anchor("MineNode_2")
	local node = addTarget("UyHollowOre", ground + V3.new(0, 2.5, 0), { UyRun = runSerial, Ground = ground, Facing = 0, Seed = 77, Index = 2 })
	node:SetAttribute("MaxHP", 70)
	node:SetAttribute("HP", 70)
	CE.Advance(1)
	eq(countIn(fxFolder(), "HollowOre"), 1, "ore built")
	local rec = Trials.Presenters.HollowMine.Active().Recs[node]
	near((rec.Model:GetPivot().Position - ground).Magnitude, 0, .05, "grown out of the crater")
	local stage1 = rec.P.Crystals[1][1]
	eq(stage1.Transparency < 1, true)
	node:SetAttribute("HP", 40)
	CE.Advance(.2)
	eq(stage1.Transparency, 1, "stage 1 crystals broke off")
	eq(rec.P.Crystals[3][1].Transparency < 1, true, "the inner spires still stand")
	removeTarget(node, "Broke")
	CE.Advance(1.6)
	eq(countIn(fxFolder(), "HollowOre"), 0, "shattered")
	-- hazards on the mine floor (CombatFX's Bus event)
	local rockAt = CE.Unix + 1.4
	Bus.Fire("CombatHazard", { Id = 1, Kind = "Rock", Shape = { Type = "Circle", Center = V3.new(150, -16, 2560), Radius = 6 }, ImpactAt = rockAt })
	Bus.Fire("CombatHazard", { Id = 2, Kind = "Gas", Shape = { Type = "Circle", Center = V3.new(170, -16, 2580), Radius = 5 }, ImpactAt = CE.Unix + 1.2 })
	Bus.Fire("CombatHazard", { Id = 3, Kind = "Collapse", Shape = { Type = "Line", From = V3.new(120, -16, 2600), To = V3.new(160, -16, 2600), Width = 8 },
		ImpactAt = CE.Unix + 1.6 })
	Bus.Fire("CombatHazard", { Id = 4, Kind = "Rock", Shape = { Type = "Circle", Center = V3.new(0, 0, 2400), Radius = 6 }, ImpactAt = rockAt })
	CE.Advance(.5)
	eq(countIn(fxFolder(), "GasVent"), 1, "vent cracks open")
	eq(countIn(fxFolder(), "FallingRock"), 0, "the rock is not falling yet")
	CE.Advance(.5)
	eq(countIn(fxFolder(), "FallingRock"), 1, "one rock falls (the one on the mine floor)")
	CE.Advance(.45)
	local mine = Trials.Presenters.HollowMine.Active()
	local r = mine.Rocks[1]
	yes(r and r.Landed, "landed at the impact")
	near(r.Model:GetPivot().Position.Y, -16 + 1.2, .05, "on the floor")
	eq(countIn(fxFolder(), "CollapseDebris"), 1, "collapse rubble")
	-- the core signal: a popup
	signal("C2Trial", payload("Core", "HollowMine", 4, data, { Index = 2, UserId = 1, Position = ground }))
	-- a downed ally shows in the lines
	player:SetAttribute("HwDowned", true)
	CE.Advance(.3)
	yes(string.find(hudGui().TrialCard.Line2.Text, "DOWN", 1, true), "downed line")
	player:SetAttribute("HwDowned", false)
	CE.Advance(.2)
	yes(string.find(hudGui().TrialCard.Gold.Text.Text, "LOST", 1, true), "Gold lost once downed")
	signal("C2Trial", payload("Failed", "HollowMine", 4, data, { Reason = "Wipe" }))
	CE.Advance(8)
	eq(#(fxFolder():GetChildren()), 0, "everything gone")
	local res = CE.PlayerGui:FindFirstChild("DOGROTS_TrialResults")
	if res then
		CE.Click(res.ResultCard.Close)
	end
	player:SetAttribute("UyTrial", "")
	CE.Advance(.2)
end)

---------------------------------------------------------------------------------------------------------------------
-- robustness
---------------------------------------------------------------------------------------------------------------------
test("late join (Tick without Start) and a run whose end signal never came", function()
	runSerial += 1
	player:SetAttribute("UyTrial", "EchoDig:" .. runSerial)
	local data = { GoAt = CE.Unix - 20, Goal = 12, Dug = 3, Hits = 3, Perfects = 3, Life = 4.5 }
	signal("C2Trial", payload("Tick", "EchoDig", 1, data, { Total = 3 }))
	yes(hudGui(), "HUD from a Tick")
	eq(CE.PlayerGui:FindFirstChild("DOGROTS_TrialCountdown"), nil, "no countdown after GO")
	eq(hudGui().TrialCard.Score.Text, "3 / 12")
	-- the server cleared UyTrial but its signal got lost: closed locally after a few seconds
	player:SetAttribute("UyTrial", "")
	CE.Advance(6)
	eq(hudGui(), nil, "closed")
	eq(Trials.Current(), nil)
	-- a Tick of that ended run never restarts it
	signal("C2Trial", payload("Tick", "EchoDig", 1, data, { Total = 3 }))
	eq(hudGui(), nil, "ended run stays ended")
end)

test("a stranger's run is ignored; C2TrialMsg becomes a localized toast", function()
	runSerial += 1
	signal("C2Trial", payload("Start", "EchoDig", 1, { GoAt = CE.Unix + 3 }, { Players = { 42 } }))
	eq(hudGui(), nil, "not a member")
	player:SetAttribute("DOGROTS_Language", "ru")
	CE.Advance(5.1)
	signal("C2TrialMsg", { Text = "Move closer to the grave" })
	eq(lastToast().Text, "Подойди ближе к могиле")
	player:SetAttribute("DOGROTS_Language", nil)
	CE.Advance(5.1)
end)

test("no errors in tasks or signal handlers, no warnings from the trials client", function()
	if #CE.Errors > 0 then
		error(CE.Errors[1])
	end
	for _, w in ipairs(CE.Warnings) do
		if string.find(w, "Trials", 1, true) or string.find(w, "Seals1", 1, true) then
			error("warning: " .. w)
		end
	end
end)

print(string.format("seals_1_4 (client): %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
