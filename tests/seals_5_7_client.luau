--!nocheck
-- BELL SEALS V-VII client presenters, headless (tests/lib/client_env.luau): lune run tests/seals_5_7_client.luau
-- Drives the real HalloweenClient.Trials.{Resonance, Doors, Choir, Bell, Assault} modules frame by frame in a fake
-- client with a small fake Underyard (door leaves, hint lamps, the hidden room's chests, the arena's chains and bell) and
-- checks what matters: the resonance meter / raid bar fit the screen on desktop and phones (EN + RU) and hide with menus
-- and trials; doors swing open and come back to their exact rest pose; the H13 lamp is restored; chest lids open and
-- close; the Doorkeeper / spirits / Bellkeeper models appear and are cleaned up; the bell arena restores every chain it
-- touched; the falling Black Bell restores the real one; every presenter tears down on Stop. No errors in tasks.
-- DUMP_DIR=<dir> also writes the meter / raid bar layouts as JSON for tools-free PNG renders (scratch QA only).
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
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-3) then
		error((msg or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function cfNear(a, b, msg)
	truthy((a.Position - b.Position).Magnitude < 1e-3, (msg or "") .. " position " .. tostring(a.Position) .. " vs " .. tostring(b.Position))
	truthy((a.LookVector - b.LookVector).Magnitude < 1e-3 and (a.UpVector - b.UpVector).Magnitude < 1e-3, (msg or "") .. " rotation")
end

---------------------------------------------------------------------------------------------------------------------
-- fake world
---------------------------------------------------------------------------------------------------------------------
local RS = CE.MountReplicated()
local Halloween = RS:FindFirstChild("Halloween")
local State = CE.Folder("State", Halloween)
State:SetAttribute("Enabled", true)
local function stateFolder(name)
	local f = CE.Folder(name, State)
	local sig = CE.Signal.new()
	CE.StateOf(f).Events.AttributeChanged = sig
	CE.StateOf(f).Props.AttributeChanged = sig
	return f
end
local ResState = stateFolder("Resonance")
local AssaultState = stateFolder("Assault")
local Arena = stateFolder("BellArena")
for k, v in pairs({ Mode = "", RunId = 0, Wave = 0, TollSerial = 0, Chain = "", ChainSince = 0, ChainHits = 0, ChainNeed = 0, Pulse = 1.2,
	Bright = .55, Broken = "", WeakId = 0, KeeperId = 0, AttackSerial = 0 }) do
	Arena:SetAttribute(k, v)
end

-- CollectionService: the tagged Strike targets
local tagged = {}
local tagAdded = CE.Signal.new()
local CS = CE.Service("CollectionService")
CS.GetTagged = function(_, _tag)
	return table.clone(tagged)
end
CS.GetInstanceAddedSignal = function(_, _tag)
	return tagAdded
end
local live = CE.Folder("HalloweenLive", CE.Workspace)
local targets = CE.Folder("Targets", live)
local nextTarget = 0
local function addTarget(kind, cf, attrs)
	nextTarget += 1
	local p = CE.Part("Target_" .. nextTarget, V3.new(0, 0, 0), V3.new(2, 2, 2), targets)
	p.CFrame = cf
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
		p:Destroy()
	end)
end

-- the Underyard pieces the presenters touch (names / pivots as the builders make them)
local district = CE.Model("DOGROTS_District", CE.Workspace)
local underyard = CE.Model("40_Underyard", district)
local Layout = CE.Require(Halloween:FindFirstChild("UnderyardLayout"))
local crooked = CE.Model("CrookedRow", underyard)
local wall = CE.Model("DoorWall", crooked)
local leaves, lamps = {}, {}
for i, d in ipairs(Layout.Crooked.Doors) do
	local bay = CE.Model("DoorBay_" .. i, wall)
	local leaf = CE.Model("Door_" .. i .. "_Leaf", bay)
	local hinge = CE.Part("DoorHinge", V3.new(d.X - 3, 5, d.Z - .17), V3.new(.2, 10, .2), leaf)
	leaf.PrimaryPart = hinge
	CE.Part("DoorSlab", V3.new(d.X, 5, d.Z), V3.new(6, 10, .3), leaf)
	leaf:SetAttribute("OpenAngle", 95)
	leaf:SetAttribute("OpenSign", -1)
	leaves[i] = leaf
	local lamp = CE.Part("DoorHintLamp", V3.new(d.X, 14, d.Z + 1.3), V3.new(.8, 1.3, .8), bay)
	lamp.Material = roblox.Enum.Material.Glass
	lamp.Color = Color3.fromRGB(46, 40, 56)
	lamp.Transparency = .15
	lamp:SetAttribute("DoorHint", i)
	lamp:SetAttribute("HintColor", Color3.fromRGB(255, 206, 110))
	lamps[i] = lamp
end
local room = CE.Model("RareRoom", crooked)
local lids = {}
for i = 1, 3 do
	local chest = CE.Model("RareChest_" .. i, room)
	local px = Layout.Crooked.RareRoom.Centre.X + (i - 2) * 9
	local cz = Layout.Crooked.RareRoom.Centre.Z - 6
	chest.PrimaryPart = CE.Part("ChestBody", V3.new(px, 2.45, cz), V3.new(3, 1.6, 2), chest)
	local lid = CE.Model("Lid", chest)
	lid.PrimaryPart = CE.Part("LidHinge", V3.new(px, 3.25, cz - 1), V3.new(3, .2, .2), lid)
	CE.Part("LidDome", V3.new(px, 3.25, cz), V3.new(3, 2, 2), lid)
	lid:SetAttribute("OpenAngle", 70)
	lid:SetAttribute("OpenAxis", "X")
	lids[i] = lid
end
local arenaModel = CE.Model("BlackBellArena", underyard)
local chains = {}
for key, p in pairs(Layout.Arena.Chains) do
	local m = CE.Model("ArenaChain_" .. key, arenaModel)
	m.PrimaryPart = CE.Part("AnchorBase", V3.new(p.X, .6, p.Z), V3.new(4, 1.2, 4), m)
	local glow = CE.Part("ChainGlow", V3.new(p.X, 3.2, p.Z), V3.new(2.9, .5, 2.9), m)
	glow.Color = Color3.fromRGB(170, 100, 255)
	glow.Transparency = .1
	local link = CE.Part("Link", V3.new(p.X, 20, p.Z), V3.new(1, 2.3, .5), m)
	chains[key] = { Model = m, Glow = glow, Link = link }
end
local bell = CE.Model("BlackBell", arenaModel)
bell.PrimaryPart = CE.Part("BellCrown", V3.new(0, 69.8, 2625), V3.new(3.8, 2.2, 3.8), bell)
local bellBody = CE.Part("BellBody", V3.new(0, 58, 2625), V3.new(16, 20, 16), bell)
bell:SetAttribute("UySwing", true)

-- the local player, main ScreenGui and a fake Halloween ctx (records banners, toasts, sounds, effects)
local player = CE.Player
player:SetAttribute("HalloweenChapter1Complete", true)
player:SetAttribute("UyInZone", true)
player:SetAttribute("UyDistrict", "BellSquare")
CE.Spawn(V3.new(0, 3, 2400))
local main = CE.Instance.new("ScreenGui")
main.Name = "ScreenGui"
main.Parent = CE.PlayerGui
main:SetAttribute("HwStripBottom", 64)

local Shared = CE.Require(Halloween:FindFirstChild("Shared"))
local Bus = CE.Require(Halloween:FindFirstChild("Bus"))
local log = { Banners = {}, Toasts = {}, Sounds = {}, FX = {}, Marks = {}, Strikes = {} }
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
}
local ctx = {
	Player = player, Shared = Shared, Config = Shared.Config, Bus = Bus, FX = fakeFX, Audio = fakeAudio, Modules = {},
	Trials = {
		Banner = function(en, ru, _opts)
			table.insert(log.Banners, { En = en, Ru = ru })
		end,
		Toast = function(en, ru)
			table.insert(log.Toasts, { En = en, Ru = ru })
		end,
		Mark = function(pos, en, ru)
			local h = { Pos = pos, En = en, Ru = ru, Alive = true }
			function h.Destroy()
				h.Alive = false
			end
			table.insert(log.Marks, h)
			return h
		end,
	},
}
Bus.On("UyBellStrike", function(d)
	table.insert(log.Strikes, d)
end)
local function sounds(cue)
	local out = {}
	for _, s in ipairs(log.Sounds) do
		if s.Cue == cue then
			table.insert(out, s)
		end
	end
	return out
end
local function lastBanner()
	return log.Banners[#log.Banners]
end
local function fxFolder()
	return CE.Workspace:FindFirstChild("DOGROTS_Seals2FX")
end
local function countModels(name)
	local f = fxFolder()
	local n = 0
	for _, d in ipairs(f and f:GetDescendants() or {}) do
		if d:IsA("Model") and d.Name == name then
			n += 1
		end
	end
	return n
end
local function signal(kind, data)
	Bus.Fire("C2Signal", { Kind = kind, Data = data })
	CE.Advance(.05)
end

local TrialsDir = CE.Folder("HalloweenClient", CE.PlayerGui)
CE.Mount("StarterPlayer/StarterPlayerScripts/HalloweenClient", TrialsDir)
local Trials = TrialsDir:FindFirstChild("Trials")
local function presenter(name)
	return CE.Require(Trials:FindFirstChild(name))
end
local Cfg = CE.Require(Halloween:FindFirstChild("Seals2Config"))

---------------------------------------------------------------------------------------------------------------------
-- layout dump (DUMP_DIR): the GUI rectangles + texts of a ScreenGui, for an offline PNG render
---------------------------------------------------------------------------------------------------------------------
local DUMP = process.env.DUMP_DIR
local function dumpGui(gui, file, extra)
	if not DUMP then
		return
	end
	local out = { Screen = { CE.Screen.X, CE.Screen.Y }, Items = {}, Extra = extra }
	local order = 0
	local function walk(o)
		for _, c in ipairs(o:GetChildren()) do
			if c:IsA("GuiObject") and CE.Shown(c) then
				order += 1
				local p, s = c.AbsolutePosition, c.AbsoluteSize
				local w = s.X
				local text = c.ClassName == "TextLabel" and c.Text or nil
				if c.AutomaticSize == roblox.Enum.AutomaticSize.X and w <= 0 then
					local label = c:FindFirstChildWhichIsA("TextLabel")
					local t = text or (label and label.Text) or ""
					w = utf8.len(t) * (label and label.TextSize or 14) * .58 + 20
				end
				local stroke = c:FindFirstChildOfClass("UIStroke")
				local corner = c:FindFirstChildOfClass("UICorner")
				local bg = c.BackgroundColor3
				table.insert(out.Items, {
					Name = c.Name, Class = c.ClassName, X = p.X, Y = p.Y, W = w, H = s.Y, Order = order, Rotation = c.Rotation or 0,
					Bg = bg and { bg.R, bg.G, bg.B } or nil, BgT = c.BackgroundTransparency,
					Text = text, TextColor = c.TextColor3 and { c.TextColor3.R, c.TextColor3.G, c.TextColor3.B } or nil,
					Align = c.TextXAlignment and tostring(c.TextXAlignment) or nil,
					Stroke = stroke and { stroke.Color.R, stroke.Color.G, stroke.Color.B } or nil,
					Round = corner ~= nil,
				})
				walk(c)
			end
		end
	end
	walk(gui)
	fs.writeFile(DUMP .. "/" .. file .. ".json", serde.encode("json", out))
end

---------------------------------------------------------------------------------------------------------------------
-- BELL RESONANCE meter
---------------------------------------------------------------------------------------------------------------------
local Res = presenter("Resonance")
Res.Init(ctx)
CE.Advance(.2)

local function meterGui()
	return CE.PlayerGui:FindFirstChild("DOGROTS_Resonance")
end

test("resonance meter: shown in the Underyard, values, milestone ticks, buff pill", function()
	local now = CE.Unix
	ResState:SetAttribute("Value", 1500)
	ResState:SetAttribute("Goal", 4000)
	ResState:SetAttribute("Milestone", 1)
	ResState:SetAttribute("BuffUntil", math.floor(now) + 200)
	CE.Advance(.6)
	local gui = meterGui()
	truthy(gui and gui.Enabled, "meter enabled")
	local card = gui:FindFirstChild("ResonanceCard")
	eq(card.Title.Text, "BELL RESONANCE")
	eq(card.Percent.Text, "37%")
	truthy(string.find(card.Info.Text, "1,500", 1, true) or string.find(card.Info.Text, "1500", 1, true), "value in info: " .. card.Info.Text)
	near(card.Track.Fill.Size.X.Scale, .375, 1e-6)
	local tick1 = card.Track:FindFirstChild("Tick1")
	local tick2 = card.Track:FindFirstChild("Tick2")
	truthy(tick1.BackgroundColor3 ~= tick2.BackgroundColor3, "reached tick lit")
	truthy(CE.Shown(gui.Pills.BuffPill), "buff pill")
	truthy(not CE.Shown(gui.Pills.AssaultPill), "no assault pill")
	truthy(main:GetAttribute("HwResonanceBottom") ~= nil, "publishes its bottom edge")
end)

test("resonance meter: hidden with menus, HIDE UI, cinematics, the player's own trial, outside the zone", function()
	local gui = meterGui()
	main:SetAttribute("OpenMenu", "Shop")
	CE.Advance(.1)
	eq(gui.Enabled, false, "menu")
	main:SetAttribute("OpenMenu", nil)
	CE.Advance(.1)
	eq(gui.Enabled, true)
	main:SetAttribute("CinemaActive", true)
	CE.Advance(.1)
	eq(gui.Enabled, false, "cinema")
	main:SetAttribute("CinemaActive", nil)
	player:SetAttribute("UyTrial", "ChoirHunt:4")
	CE.Advance(.1)
	eq(gui.Enabled, false, "own trial")
	eq(main:GetAttribute("HwResonanceBottom"), nil, "no bottom edge while hidden")
	player:SetAttribute("UyTrial", "")
	player:SetAttribute("UyInZone", false)
	CE.Advance(.1)
	eq(gui.Enabled, false, "outside")
	player:SetAttribute("UyInZone", true)
	CE.Advance(.1)
	eq(gui.Enabled, true)
end)

local function inside(gui, W, H)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiObject") and CE.Shown(d) and d.ClassName ~= "UIStroke" then
			local p, s = d.AbsolutePosition, d.AbsoluteSize
			truthy(p.X >= -1 and p.Y >= -1 and p.X + s.X <= W + 1 and p.Y + s.Y <= H + 1,
				d.Name .. " off screen " .. tostring(p) .. " " .. tostring(s) .. " at " .. W .. "x" .. H)
		end
	end
end

test("resonance meter: fits desktop, phone portrait and phone landscape (EN + RU), under the HUD strip", function()
	local gui = meterGui()
	ResState:SetAttribute("EchoUntil", math.floor(CE.Unix) + 120)
	AssaultState:SetAttribute("State", "Countdown")
	AssaultState:SetAttribute("StartsAt", CE.Unix + 25)
	for _, lang in ipairs({ "en", "ru" }) do
		player:SetAttribute("DOGROTS_Language", lang)
		for _, screen in ipairs({ { 1280, 720 }, { 390, 844 }, { 844, 390 } }) do
			CE.Screen = roblox.Vector2.new(screen[1], screen[2])
			main:SetAttribute("HwStripBottom", screen[1] < 700 and 52 or 64)
			CE.Advance(11) -- the language cache refreshes every 5 s
			truthy(gui.Enabled, "shown")
			local card = gui.ResonanceCard
			truthy(card.AbsolutePosition.Y >= main:GetAttribute("HwStripBottom"), "under the strip")
			inside(gui, screen[1], screen[2])
			if lang == "ru" then
				eq(card.Title.Text, "РЕЗОНАНС КОЛОКОЛА")
				truthy(string.find(gui.Pills.AssaultPill.Text.Text, "ШТУРМ", 1, true), "ru assault pill")
			else
				truthy(string.find(gui.Pills.AssaultPill.Text.Text, "ASSAULT IN", 1, true), "assault countdown pill")
			end
			dumpGui(gui, string.format("meter_%s_%dx%d", lang, screen[1], screen[2]))
		end
	end
	player:SetAttribute("DOGROTS_Language", "en")
	CE.Screen = roblox.Vector2.new(1280, 720)
	main:SetAttribute("HwStripBottom", 64)
	AssaultState:SetAttribute("State", "")
	ResState:SetAttribute("EchoUntil", 0)
	CE.Advance(6)
end)

test("resonance: milestone signal flashes and toasts, Resonant Echo spots get their shard model", function()
	local before = #log.Toasts
	signal("C2Resonance", { Kind = "Milestone", Index = 2 })
	truthy(#log.Toasts > before, "milestone toast")
	truthy(string.find(log.Toasts[#log.Toasts].En, "KEYS FOR THE FAITHFUL", 1, true), "keys toast")
	local echo = addTarget("UyResEcho", CF.new(10, 3, 2400))
	CE.Advance(.2)
	eq(countModels("ResonantEcho") + countModels("Echo"), 1, "echo model")
	removeTarget(echo, "Broke")
	CE.Advance(1)
	eq(countModels("ResonantEcho") + countModels("Echo"), 0, "echo model gone")
end)

---------------------------------------------------------------------------------------------------------------------
-- CROOKED DOORS
---------------------------------------------------------------------------------------------------------------------
local Doors = presenter("Doors")
Doors.Init(ctx)
CE.Advance(.1)

test("doors: an opening swings the leaf open, reveals the outcome, then shuts back to its exact rest pose", function()
	local rest = leaves[1]:GetPivot()
	signal("C2Door", { Kind = "Open", Door = 1, Outcome = "Reward", Rewards = { { Kind = "Shards", Amount = 52 } }, Counted = true,
		Progress = 1, Need = 3, Left = 2, Max = 3 })
	CE.Advance(Cfg.Client.DoorOpenTime + .1)
	local open = leaves[1]:GetPivot()
	truthy((open.LookVector - rest.LookVector).Magnitude > 1, "leaf turned")
	-- swings out toward the court (+Z): the slab's far edge moves to +Z
	local slab = leaves[1]:FindFirstChild("DoorSlab")
	truthy(slab.Position.Z > Layout.Crooked.Doors[1].Z + 1, "opens toward the court")
	eq(lastBanner().En, "TREASURE")
	truthy(#sounds("DoorCreak") >= 1, "creak")
	truthy(#log.Toasts >= 1 and string.find(log.Toasts[#log.Toasts].En, "Seal V: 1 / 3", 1, true), "seal progress toast")
	CE.Advance(Cfg.Client.DoorHold + Cfg.Client.DoorOpenTime * 1.2 + .3)
	cfNear(leaves[1]:GetPivot(), rest, "rest pose")
	truthy(#sounds("DoorSlam") >= 1, "slam")
end)

test("doors: someone else's opening swings the door too; a refund slams it at once", function()
	local rest = leaves[3]:GetPivot()
	signal("C2Door", { Kind = "Swing", Door = 3, Outcome = "MiniBoss", UserId = 2 })
	CE.Advance(.5)
	truthy((leaves[3]:GetPivot().LookVector - rest.LookVector).Magnitude > .3, "swinging")
	signal("C2Door", { Kind = "Refund", Door = 3 })
	CE.Advance(.6)
	cfNear(leaves[3]:GetPivot(), rest, "slammed shut")
end)

test("doors: the H13 hint lamp lights with moths and is restored as soon as a door is opened", function()
	local lamp = lamps[2]
	local mat, col, tr = lamp.Material, lamp.Color, lamp.Transparency
	signal("C2Door", { Kind = "Hint", Door = 2 })
	eq(lamp.Material, roblox.Enum.Material.Neon)
	truthy(lamp:FindFirstChild("DOGROTS_DoorHintLight"), "lamp light")
	truthy(countModels("Moth") > 0, "moths")
	truthy(#sounds("Moths") >= 1, "moth sound")
	signal("C2Door", { Kind = "Open", Door = 4, Outcome = "Challenge", Counted = false, Progress = 1, Need = 3 })
	eq(lamp.Material, mat)
	eq(lamp.Color, col)
	eq(lamp.Transparency, tr)
	eq(lamp:FindFirstChild("DOGROTS_DoorHintLight"), nil)
	CE.Advance(5)
	eq(countModels("Moth"), 0, "moths gone")
end)

test("doors: the sign shows openings and Seal V progress (EN / RU), only near the wall", function()
	player:SetAttribute("UyDoorsLeft", 2)
	player:SetAttribute("UyDoorsMax", 3)
	player:SetAttribute("UySealVProgress", 1)
	CE.MoveTo(V3.new(-147, 3, 2250))
	CE.Advance(1.2)
	local f = fxFolder()
	local anchor = f:FindFirstChild("DoorSignAnchor")
	truthy(anchor, "sign built near the wall")
	local gui = anchor:FindFirstChild("DOGROTS_DoorSign")
	local card = gui:FindFirstChildOfClass("Frame")
	eq(card.Doors.Text, "OPENINGS TODAY: 2 / 3")
	eq(card.Seal.Text, "SEAL V · DOOR OUTCOMES: 1 / 3")
	player:SetAttribute("UySealMask", "1111100")
	player:SetAttribute("UySealVProgress", 4)
	CE.Advance(.1)
	eq(card.Seal.Text, "SEAL V BROKEN · NEXT CLEAR: 1 / 3")
	player:SetAttribute("UyDoorsLeft", 0)
	CE.Advance(.1)
	truthy(string.find(card.Doors.Text, "BACK TOMORROW", 1, true), "none left")
	CE.MoveTo(V3.new(0, 3, 2400))
	CE.Advance(1.2)
	eq(fxFolder():FindFirstChild("DoorSignAnchor"), nil, "sign gone away from the wall")
end)

test("doors: the hidden room: timer, chest lids open with the granted rows, all close again", function()
	local rest = lids[2]:GetPivot()
	signal("C2Door", { Kind = "Rare", Door = 2, Chests = 3, Until = CE.Unix + 90 })
	eq(lastBanner().En, "THE HIDDEN ROOM")
	truthy(fxFolder():FindFirstChild("RareTimerAnchor"), "timer")
	signal("C2Door", { Kind = "Chest", Index = 2, Rewards = { { Kind = "Find", Id = "uy_coffin_nail", Amount = 1 } } })
	CE.Advance(.8)
	local dome = lids[2]:FindFirstChild("LidDome")
	truthy(dome.Position.Y > lids[2].PrimaryPart.Position.Y + .6, "lid flipped up (its front rises over the hinge)")
	truthy(#sounds("RareFind") >= 1, "rare find sound for a showcase find")
	signal("C2Door", { Kind = "RareEnd", Door = 2 })
	CE.Advance(1)
	cfNear(lids[2]:GetPivot(), rest, "lid closed")
	eq(fxFolder():FindFirstChild("RareTimerAnchor"), nil, "timer gone")
end)

test("doors: the Doorkeeper rises on its target, animates an attack for members, falls apart when beaten", function()
	local court = Layout.Crooked.Court.Centre
	local t = addTarget("UyDoorkeeper", CF.lookAt(court + V3.new(0, 7, 0), court + V3.new(0, 7, -40)), { UyRunId = 7, UyMembers = ",1," })
	CE.Advance(1.2)
	eq(countModels("Doorkeeper"), 1, "keeper model")
	Doors.Start(ctx, { TrialId = "Doorkeeper", RunId = 7, Data = { Kind = "MiniBoss", TargetId = t:GetAttribute("TargetId"), Keeper = court,
		StaggerUntil = 0 } })
	eq(lastBanner().En, "THE DOORKEEPER")
	Doors.Signal(ctx, "DoorkeeperAttack", { Attack = "Slam", ImpactAt = CE.Unix + 1.2, Target = court + V3.new(4, 0, 6),
		StaggerUntil = CE.Unix + 2.8, TargetId = t:GetAttribute("TargetId") }, nil)
	CE.Advance(1.5)
	local lines = Doors.HudLines({})
	truthy(string.find(lines[1], "STUCK", 1, true), "stuck line: " .. tostring(lines[1]))
	t:SetAttribute("HP", 4)
	CE.Advance(.2)
	removeTarget(t, "Broke")
	CE.Advance(2)
	eq(countModels("Doorkeeper"), 0, "keeper gone")
	truthy(#sounds("ArmorBreak") >= 1, "breaks apart")
	Doors.Stop(ctx, { RunId = 7 }, "Won")
end)

test("doors: the challenge rim warns outside the court and is removed on Stop", function()
	local court = Layout.Crooked.Court.Centre
	CE.MoveTo(court + V3.new(0, 3, 0))
	Doors.Start(ctx, { TrialId = "DoorChallenge", RunId = 8, Data = { Kind = "Challenge", Center = court, Radius = 26, LeaveRadius = 34 } })
	eq(lastBanner().En, "DOOR CHALLENGE")
	CE.Advance(.2)
	truthy(fxFolder():FindFirstChild("DoorCourtRim"), "rim")
	eq(Doors.HudLines({})[1], "Stay inside the Door Court")
	CE.MoveTo(court + V3.new(30, 3, 0))
	CE.Advance(.2)
	eq(Doors.HudLines({})[1], "BACK INTO THE COURT!")
	Doors.Signal(ctx, "DoorWave", { Wave = "Stomp" }, nil)
	truthy(string.find(Doors.HudLines({})[2], "STOMP", 1, true), "wave line")
	Doors.Stop(ctx, { RunId = 8 }, "Failed")
	CE.Advance(.1)
	eq(fxFolder():FindFirstChild("DoorCourtRim"), nil, "rim removed")
	eq(Doors.HudLines({}), nil)
	CE.MoveTo(V3.new(0, 3, 2400))
end)

---------------------------------------------------------------------------------------------------------------------
-- CHOIR HUNT
---------------------------------------------------------------------------------------------------------------------
local Choir = presenter("Choir")

test("choir: only this run's spirits get models; they sing on the shared schedule at their own pitch", function()
	local p1 = addTarget("UyChoir", CF.new(0, 3, 2380), { UyRunId = 21, UyChoirNote = 1, UyMembers = ",1,2," })
	local p3 = addTarget("UyChoir", CF.new(8, 3, 2380), { UyRunId = 21, UyChoirNote = 3, UyMembers = ",1,2," })
	addTarget("UyChoir", CF.new(-8, 3, 2380), { UyRunId = 22, UyChoirNote = 2, UyMembers = ",5," }) -- another party's
	local before = #sounds("ChoirNote")
	CE.Camera.CFrame = CF.new(0, 20, 2420)
	Choir.Start(ctx, { TrialId = "ChoirHunt", RunId = 21, StartedAt = CE.Unix, Goal = 7,
		Data = { SingEvery = Cfg.Choir.SingEvery, Count = 7, Caught = 0 } })
	CE.Advance(.2)
	eq(countModels("ChoirSpirit"), 2, "two spirits of this run")
	CE.Advance(Cfg.Choir.SingEvery + .2)
	local pitches = {}
	for i = before + 1, #log.Sounds do
		local s = log.Sounds[i]
		if s.Cue == "ChoirNote" then
			pitches[s.Pitch] = true
		end
	end
	truthy(pitches[Cfg.Choir.Melody[1]] and pitches[Cfg.Choir.Melody[3]], "notes 1 and 3 sung")
	truthy(not pitches[Cfg.Choir.Melody[2]], "the other party's spirit is not sung here")
	-- the spirit follows its target
	p1.CFrame = CF.new(0, 3, 2390)
	CE.Advance(1.5)
	local model
	for _, d in ipairs(fxFolder():GetDescendants()) do
		if d:IsA("Model") and d.Name == "ChoirSpirit" and d:GetAttribute("Note") == 1 then
			model = d
		end
	end
	truthy(model and (model:GetPivot().Position - V3.new(0, 3, 2390)).Magnitude < 1.5, "follows the target")
	-- a Good hit startles it; a catch sends it up
	Choir.Signal(ctx, "ChoirFlee", { TargetId = p3:GetAttribute("TargetId"), UserId = 1 }, nil)
	truthy(string.find(log.Toasts[#log.Toasts].En, "PERFECT", 1, true), "flee hint")
	Choir.Signal(ctx, "ChoirCaught", { TargetId = p1:GetAttribute("TargetId"), Note = 1, UserId = 1, Caught = 1 }, nil)
	removeTarget(p1, "Broke")
	CE.Advance(2)
	eq(countModels("ChoirSpirit"), 1, "caught one gone")
	eq(Choir.HudLines({})[1], "Spirits caught: 1 / 7")
	Choir.Stop(ctx, { RunId = 21 }, "Won")
	CE.Advance(.1)
	eq(countModels("ChoirSpirit"), 0, "all spirits gone on Stop")
	CE.Advance(4)
	truthy(#sounds("ChoirNote") >= before + 7, "the whole song on the win")
end)

---------------------------------------------------------------------------------------------------------------------
-- LAST BELL TRIAL arena
---------------------------------------------------------------------------------------------------------------------
local Bell = presenter("Bell")
Bell.Init(ctx)
CE.Camera.CFrame = CF.new(0, 30, 2560)

test("bell arena: the Bellkeeper appears for the trial, tolls haul the rope and strike the bell", function()
	Arena:SetAttribute("Mode", "Trial")
	Arena:SetAttribute("RunId", 30)
	CE.Advance(1.5)
	eq(countModels("Bellkeeper"), 1, "keeper")
	local rope = fxFolder():FindFirstChild("BellRope", true)
	truthy(rope and rope.Size.Z > 20, "rope stretched up to the bell")
	local strikes = #log.Strikes
	Arena:SetAttribute("TollSerial", 1)
	CE.Advance(.2)
	eq(#log.Strikes, strikes + 1, "UyBellStrike fired")
	truthy(#sounds("BellTollFar") + #sounds("BellTollHuge") >= 1, "toll heard")
end)

test("bell arena: the ringing chain pulses on the server clock; a broken chain hides its links; all restored", function()
	local glow = chains.N.Glow
	local original = Color3.fromRGB(170, 100, 255) -- as the builder made it
	Arena:SetAttribute("Wave", 2)
	Arena:SetAttribute("Chain", "N")
	Arena:SetAttribute("ChainSince", CE.Unix)
	Arena:SetAttribute("ChainNeed", 9)
	CE.Advance(.1) -- inside the bright part
	local bright = glow.Color
	CE.Advance(.9) -- ~.83 of the pulse: dark
	truthy(glow.Color ~= bright, "pulses")
	truthy(fxFolder():FindFirstChild("ChainSignAnchor", true), "hits sign")
	Arena:SetAttribute("Broken", "N")
	Arena:SetAttribute("Chain", "")
	CE.Advance(.2)
	eq(chains.N.Link.LocalTransparencyModifier, 1, "links hidden")
	truthy(#sounds("ChainBreak") >= 1, "shatter")
	eq(fxFolder():FindFirstChild("ChainSignAnchor", true), nil, "sign gone with no ringing chain")
	-- heart opens, gets beaten
	local weak = addTarget("UyBellWeak", CF.new(0, 7.5, 2640), { UyRunId = 30, UyWeak = true })
	Arena:SetAttribute("Wave", 3)
	Arena:SetAttribute("WeakId", weak:GetAttribute("TargetId"))
	CE.Advance(.3)
	weak:SetAttribute("HP", 3)
	CE.Advance(.1)
	removeTarget(weak, "Broke")
	CE.Advance(.05)
	Arena:SetAttribute("Mode", "")
	Arena:SetAttribute("Broken", "")
	CE.Advance(3)
	eq(countModels("Bellkeeper"), 0, "keeper gone")
	truthy(#sounds("BossDeath") >= 1, "defeat played although the trial ended in the same breath")
	eq(chains.N.Link.LocalTransparencyModifier, 0, "links restored")
	eq(glow.Color, original, "glow restored")
	eq(glow.Transparency, .1)
end)

test("bell presenter: wave banners, chain marker, HUD lines", function()
	Bell.Start(ctx, { TrialId = "LastBell", RunId = 31, Data = { Wave = 0, Tolls = 0, TollsNeed = 4 } })
	eq(lastBanner().En, "LAST BELL TRIAL")
	Bell.Signal(ctx, "BellWave", { Wave = 1 }, { RunId = 31, Data = { Wave = 1, Tolls = 2, TollsNeed = 4 } })
	truthy(string.find(lastBanner().En, "SHOCKWAVE", 1, true), "wave 1 banner")
	truthy(string.find(Bell.HudLines({})[1], "2 / 4", 1, true), "tolls line")
	Bell.Signal(ctx, "ChainActive", { Key = "E", Need = 9 }, { RunId = 31, Data = { Wave = 2, ChainsLeft = 4, Chain = "E", ChainNeed = 9 } })
	local mark = log.Marks[#log.Marks]
	truthy(mark.Alive and mark.En == "EAST CHAIN", "chain marker")
	Bell.Signal(ctx, "ChainHit", { Key = "E", Hits = 3, Need = 9, UserId = 1, Counted = true }, nil)
	truthy(string.find(Bell.HudLines({})[2], "3 / 9", 1, true), "chain hits line")
	Bell.Stop(ctx, { RunId = 31 }, "Failed")
	eq(mark.Alive, false, "marker removed")
	eq(Bell.HudLines({}), nil)
end)

---------------------------------------------------------------------------------------------------------------------
-- BLACK BELL ASSAULT
---------------------------------------------------------------------------------------------------------------------
local Assault = presenter("Assault")
Assault.Init(ctx)
CE.Advance(.2)

test("assault: raid bar in the arena (EN / RU, desktop + phones), the bell falls on a win and is restored", function()
	local gui = CE.PlayerGui:FindFirstChild("DOGROTS_Assault")
	truthy(gui, "raid gui")
	player:SetAttribute("UyDistrict", "BlackBellArena")
	AssaultState:SetAttribute("State", "Active")
	AssaultState:SetAttribute("HP", 4200)
	AssaultState:SetAttribute("MaxHP", 9000)
	AssaultState:SetAttribute("EndsAt", CE.Unix + 300)
	AssaultState:SetAttribute("Attackers", 12)
	player:SetAttribute("UyAssaultHits", 3)
	player:SetAttribute("UyTrial", "Assault:44")
	Arena:SetAttribute("Mode", "Assault")
	CE.Advance(.5)
	truthy(gui.Enabled and CE.Shown(gui.RaidCard), "raid card")
	eq(gui.RaidCard.Track.HP.Text, "47%")
	truthy(string.find(gui.RaidCard.Info.Text, "3 / 5", 1, true), "your hits")
	truthy(fxFolder():FindFirstChild("AssaultBeacon"), "beacon")
	eq(countModels("BellkeeperAssault"), 1, "assault variant keeper")
	for _, lang in ipairs({ "en", "ru" }) do
		player:SetAttribute("DOGROTS_Language", lang)
		for _, screen in ipairs({ { 1280, 720 }, { 390, 844 }, { 844, 390 } }) do
			CE.Screen = roblox.Vector2.new(screen[1], screen[2])
			main:SetAttribute("HwStripBottom", screen[1] < 700 and 52 or 64)
			CE.Advance(5.5)
			inside(gui, screen[1], screen[2])
			truthy(gui.RaidCard.AbsolutePosition.Y >= 52, "under the strip")
			if lang == "ru" then
				truthy(string.find(gui.RaidCard.Title.Text, "ЗВОНАРЬ", 1, true), "ru title")
			end
			dumpGui(gui, string.format("raid_%s_%dx%d", lang, screen[1], screen[2]))
		end
	end
	player:SetAttribute("DOGROTS_Language", "en")
	CE.Screen = roblox.Vector2.new(1280, 720)
	main:SetAttribute("HwStripBottom", 64)
	CE.Advance(5.5)
	-- the win: the bell falls (a client copy), the real one is hidden, then everything comes back
	local before = bellBody.LocalTransparencyModifier
	AssaultState:SetAttribute("State", "Won")
	CE.Advance(1.6)
	truthy(fxFolder():FindFirstChild("FallingBlackBell"), "falling copy")
	eq(bellBody.LocalTransparencyModifier, 1, "real bell hidden")
	truthy(#sounds("BossSlam") >= 1, "lands")
	eq(gui.RaidCard.Info.Text, "THE BLACK BELL FALLS")
	AssaultState:SetAttribute("State", "")
	Arena:SetAttribute("Mode", "")
	player:SetAttribute("UyTrial", "")
	CE.Advance(1.5)
	eq(bellBody.LocalTransparencyModifier, before, "real bell restored")
	eq(fxFolder():FindFirstChild("FallingBlackBell"), nil, "copy gone")
	eq(fxFolder():FindFirstChild("AssaultBeacon"), nil, "beacon gone")
	eq(gui.Enabled, false, "raid bar hidden")
end)

test("assault: the last five seconds of the countdown", function()
	local gui = CE.PlayerGui:FindFirstChild("DOGROTS_Assault")
	AssaultState:SetAttribute("State", "Countdown")
	AssaultState:SetAttribute("StartsAt", CE.Unix + 4.2)
	CE.Advance(.3)
	truthy(CE.Shown(gui.Countdown), "countdown shown")
	eq(gui.Countdown.Text, "4")
	main:SetAttribute("OpenMenu", "Bag")
	CE.Advance(.2)
	eq(CE.Shown(gui.Countdown), false, "hidden with a menu")
	main:SetAttribute("OpenMenu", nil)
	AssaultState:SetAttribute("State", "")
	CE.Advance(.3)
	eq(gui.Enabled, false)
end)

test("presenter contract: every presenter has Ids, Start, Stop, HudLines; no task errors", function()
	for _, name in ipairs({ "Doors", "Choir", "Bell", "Assault", "Resonance" }) do
		local p = presenter(name)
		truthy(type(p.Ids) == "table", name .. " Ids")
		for _, fn in ipairs({ "Start", "Stop", "HudLines" }) do
			truthy(type(p[fn]) == "function", name .. "." .. fn)
		end
	end
	eq(#CE.Errors, 0, "task errors: " .. tostring(CE.Errors[1]))
end)

print(string.format("seals_5_7_client: %d passed, %d failed", passed, failed))
if #CE.Warnings > 0 then
	print("warnings: " .. table.concat(CE.Warnings, " | "))
end
if failed > 0 then
	error("seals_5_7_client tests failed")
end
