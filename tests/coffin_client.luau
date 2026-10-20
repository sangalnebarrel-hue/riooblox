--!nocheck
-- THE BLACK COFFIN · the opening presentation (docs/halloween2/DESIGN.md §9.7, §24.4): HalloweenClient.CoffinFX runs
-- headless in the fake client of tests/lib/client_env.luau with the real Shared / Bus / FX / Cinema / CoffinConfig /
-- Localization and fake Audio + AudioMixer, on a hand-built BlackCoffin rig with the builder's attribute contract
-- (CoffinConfig.Attr). The server is played by hand: C2Coffin / C2CoffinNear / C2CoffinRefused / C2Announce through the
-- Bus "C2Signal" the way Chapter2State relays them. Checks: every beat of §9.7 happens in order (chains, padlock,
-- candles, rattle, seams, lid, pillar, reward, card), Rare+ shockwave, Mythic lightning + slow motion, the Secret's
-- blackout / music cut / hand-off to the SecretReveal arrival (and the module's own moon + king + banner without it),
-- the skip, duplicates on the card, bonus rows, the lighter version, queueing + OPEN AGAIN, refusals, the announce
-- banner, Russian, quality / reduced motion, and that every way a show ends restores the coffin, the prompt, the
-- character, the camera, the controls, the grade, the mixer and destroys the scene + card. lune run tests/coffin_client.luau
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local CE = require("./lib/client_env")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local V3, CF = Vector3.new, CFrame.new

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
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then
		error((msg or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a), 2)
	end
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
	elseif className == "Model" then
		-- Model:GetScale / ScaleTo about the pivot
		inst.GetScale = function(self)
			return self:GetAttribute("FakeScale") or 1
		end
		inst.ScaleTo = function(self, s)
			local k = s / (self:GetAttribute("FakeScale") or 1)
			local pivot = self:GetPivot()
			for _, d in ipairs(self:GetDescendants()) do
				if d:IsA("BasePart") then
					local rel = pivot:ToObjectSpace(d.CFrame)
					d.CFrame = pivot * CF(rel.Position * k) * rel.Rotation
					d.Size = d.Size * k
				end
			end
			self:SetAttribute("FakeScale", s)
		end
	end
	return inst
end

-- AudioMixer: every duck must be released
local ducks = {}
CE.Overrides["ReplicatedStorage/AudioMixer"] = {
	Duck = function(reason, levels, _fade)
		ducks[reason] = levels or true
	end,
	Release = function(reason, _fade)
		ducks[reason] = nil
	end,
}
local function liveDucks()
	local n = 0
	for _ in pairs(ducks) do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- the world: ReplicatedStorage from src, the shrine + a BlackCoffin rig with the builder's attributes, the player
---------------------------------------------------------------------------------------------------------------------
local RS = CE.MountReplicated()
local Halloween = RS:FindFirstChild("Halloween")
local stateRoot = CE.Folder("State", Halloween)
stateRoot:SetAttribute("Enabled", true)
local mainGui = CE.Instance.new("ScreenGui")
mainGui.Name = "ScreenGui"
local mainSig = CE.Signal.new()
CE.StateOf(mainGui).Events.AttributeChanged = mainSig
CE.StateOf(mainGui).Props.AttributeChanged = mainSig
mainGui.Parent = CE.PlayerGui

local Shared = CE.Require(Halloween:FindFirstChild("Shared"))
local Layout = CE.Require(Halloween:FindFirstChild("UnderyardLayout"))
local CC = CE.Require(Halloween:FindFirstChild("CoffinConfig"))
local Cfg = CE.Require(Halloween:FindFirstChild("Chapter2Config"))
local SHRINE = Layout.Square.CoffinShrine
local SEAT = SHRINE * CF(0, 3.1, 0)
local VIOLET = Color3.fromRGB(150, 80, 230)

local function part(name, cf, size, parent, attrs, props)
	local p = CE.Instance.new("Part")
	p.Name = name
	p.CFrame = cf
	p.Size = size or V3(1, 1, 1)
	p.Color = (props and props.Color) or Color3.fromRGB(20, 14, 30)
	p.Transparency = (props and props.Transparency) or 0
	p.Material = (props and props.Material) or Enum.Material.SmoothPlastic
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	p.Parent = parent
	return p
end

local district = CE.Model("DOGROTS_District", CE.Workspace)
local uy = CE.Model("40_Underyard", district)
local anchors = CE.Folder("Anchors", uy)
local anchorPart = part("CoffinShrine", CF(Layout.Anchors.CoffinShrine), V3(1, 1, 1), anchors, nil, { Transparency = 1 })
local prompt = CE.Instance.new("ProximityPrompt")
prompt.Name = "UyCoffinPrompt"
prompt.Enabled = true
prompt:SetAttribute("CoffinPrompt", true)
prompt.Parent = anchorPart
local square = CE.Model("BellSquare", uy)
local shrineModel = CE.Model("CoffinShrine", square)
local shrineFlames = {}
for i, x in ipairs({ -3.7, 3.7 }) do
	shrineFlames[i] = part("CandleFlame", SHRINE * CF(x, 4.6, .2), V3(.2, .38, .2), shrineModel, { HwCandle = true },
		{ Color = Color3.fromRGB(255, 170, 80), Material = Enum.Material.Neon })
end

local coffin = CE.Model("BlackCoffin", uy)
coffin:SetAttribute("CoffinRoot", true)
coffin:SetAttribute("CoffinSeat", SEAT)
local pivot = part("CoffinPivot", SEAT, V3(1, 1, 1), coffin, nil, { Transparency = 1 })
coffin.PrimaryPart = pivot
local lid = CE.Model("Lid", coffin)
lid:SetAttribute("CoffinLid", true)
lid:SetAttribute("OpenAngle", 118)
local hinge = part("LidHinge", SEAT * CF(-1.88, .6, 0), V3(.2, .2, .2), lid, nil, { Transparency = 1 })
lid.PrimaryPart = hinge
local lidParts = { hinge }
for i, z in ipairs({ -2.4, 0, 2.4 }) do
	lidParts[#lidParts + 1] = part("LidSlab", SEAT * CF(0, .75, z), V3(3.4, .3, 2.4), lid)
end
local closed = {}
for i, p in ipairs(lidParts) do
	closed[i] = p.CFrame
end
local seamsModel = CE.Model("Seams", coffin)
local seams = {}
for o = 1, 5 do
	seams[o] = part("Seam", SEAT * CF(0, .55 - o * .2, -1), V3(3, .06, .06), seamsModel, { CoffinSeam = o },
		{ Transparency = 1, Color = Color3.fromRGB(168, 70, 255), Material = Enum.Material.Neon })
end
local innerModel = CE.Model("Inner", coffin)
local glow = part("InnerGlow", SEAT * CF(0, -.8, 0), V3(1.7, .06, 5.8), innerModel, { CoffinInner = true },
	{ Transparency = 1, Color = Color3.fromRGB(168, 70, 255), Material = Enum.Material.Neon })
local haze = part("InnerHaze", SEAT * CF(0, -.3, 0), V3(1.9, .9, 6), innerModel, { CoffinInner = true },
	{ Transparency = 1, Color = Color3.fromRGB(168, 70, 255), Material = Enum.Material.ForceField })
local innerLight = CE.Instance.new("PointLight")
innerLight.Name = "InnerLight"
innerLight.Enabled = false
innerLight.Brightness = 3
innerLight.Color = Color3.fromRGB(168, 70, 255)
innerLight:SetAttribute("CoffinLight", true)
innerLight.Parent = glow
local runes = {}
for i = 1, 3 do
	runes[i] = part("Rune", SEAT * CF(1.8, 0, -2 + i), V3(.07, .03, .4), coffin, { CoffinRune = true },
		{ Transparency = .3, Color = VIOLET, Material = Enum.Material.Neon })
end
local chains, chainBase = {}, {}
local ANCHORS = { SEAT * V3(-5, -.3, 0), SEAT * V3(5, -.3, 0), SEAT * V3(0, -.3, 5.6) }
for k = 1, 3 do
	local m = CE.Model("CoffinChain_" .. k, coffin)
	m:SetAttribute("CoffinChain", k)
	m:SetAttribute("Anchor", ANCHORS[k])
	chains[k] = {}
	for i = 1, 8 do
		local pos = ANCHORS[k]:Lerp(SEAT * V3(0, 1.2, -.7), i / 9)
		local p = part("Link", CF(pos), V3(.06, .06, .42), m, { CoffinLink = i }, { Material = Enum.Material.CorrodedMetal })
		chains[k][i] = p
		chainBase[p] = p.CFrame
	end
end
local padlockModel = CE.Model("Padlock", coffin)
padlockModel:SetAttribute("CoffinPadlock", true)
local padlock = {}
for i = 1, 3 do
	padlock[i] = part("PadlockBody", SEAT * CF(0, 1.5, -.75 + i * .01), V3(.64, .56, .26), padlockModel)
end
local candleModel = CE.Model("Candles", coffin)
candleModel:SetAttribute("CoffinCandle", true)
local ownFlames = {}
for i, x in ipairs({ -1.85, 1.85 }) do
	ownFlames[i] = part("CandleFlame", SEAT * CF(x, -.1, -3.1), V3(.13, .26, .13), candleModel, { HwCandle = true },
		{ Color = Color3.fromRGB(255, 170, 80), Material = Enum.Material.Neon })
end

-- the player stands at the shrine
local function spawn(pos)
	local ch = CE.Spawn(pos)
	ch:FindFirstChildOfClass("Humanoid").ChangeState = function() end
	local head = part("Head", CF(pos + V3(0, 1.5, 0)), V3(1, 1, 1), ch)
	return ch
end
local character = spawn((SHRINE * CF(0, 3, -7)).Position)

local clientFolder = CE.Folder("HalloweenClient", CE.Service("StarterPlayer"))
CE.Mount("StarterPlayer/StarterPlayerScripts/HalloweenClient", clientFolder)

-- Audio: record the cues
local plays = {}
local Audio = {
	Play = function(cue, where, opts)
		table.insert(plays, { Cue = cue, Where = where, Volume = opts and opts.Volume })
	end,
	Has = function()
		return true
	end,
}
local function played(name)
	local n = 0
	for _, p in ipairs(plays) do
		if p.Cue == name then
			n += 1
		end
	end
	return n
end

local Bus = CE.Require(Halloween:FindFirstChild("Bus"))
local FXmod = CE.Require(Halloween:FindFirstChild("FX"))
local toasts, music = {}, {}
Bus.On("Toast", function(d)
	table.insert(toasts, d)
end)
Bus.On("MusicOverride", function(d)
	table.insert(music, d)
end)
-- Chapter2State stand-in: OPEN AGAIN requests
local requests = {}
local requestReply = { true, {} }
local C2State = {
	Request = function(action, args)
		table.insert(requests, { Action = action, Args = args })
		return table.unpack(requestReply)
	end,
}
local ctx = {
	Player = CE.Player, Shared = Shared, Config = Shared.Config, Layout = Shared.Layout, Bus = Bus, FX = FXmod, Audio = Audio,
	State = {}, Modules = {},
}
local Cinema = CE.Require(clientFolder:FindFirstChild("Cinema"))
ctx.Modules.Cinema = Cinema
ctx.Modules.Chapter2State = C2State
Cinema.Start(ctx)
local CoffinFX = CE.Require(clientFolder:FindFirstChild("CoffinFX"))
ctx.Modules.CoffinFX = CoffinFX
CoffinFX.Start(ctx)
local State = CoffinFX.State

---------------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------------
local nextId = 0
local function payload(rank, main, extra)
	nextId += 1
	local p = { Id = nextId, UserId = 1, Name = "Tester", Rank = rank, Rarity = Shared.Rarity(rank), Tier = rank, Main = main, Rows = { main },
		Converted = main.Converted == true, Duplicate = main.Reason == "Owned", Forced = false, Keys = 3, Shards = 600, Seed = 4242 + nextId,
		At = CE.Unix }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end
local function signal(kind, data)
	Bus.Fire("C2Signal", { Kind = kind, Data = data })
	CE.Advance(0)
end
local function card()
	return CE.PlayerGui:FindFirstChild("DOGROTS_CoffinCard")
end
local function cardText(name)
	local g = card()
	local f = g and g:FindFirstChild("Card")
	local l = f and f:FindFirstChild(name, true)
	return l and l.Text
end
local function scene()
	local folder = CE.Workspace:FindFirstChild("DOGROTS_CoffinFX")
	return folder and folder:GetChildren()[1]
end
local function sceneHas(name)
	local s = scene()
	return s ~= nil and s:FindFirstChild(name, true) ~= nil
end
local function lidOpen()
	-- the lid's slabs left their closed CFrames
	return (lidParts[2].CFrame.Position - closed[2].Position).Magnitude > .5
end
local function advanceTo(show, t)
	-- run until the show clock reaches t
	local guard = 0
	while CC.ShowTime(show.Beats, CE.Now - show.T0) < t and guard < 4000 do
		CE.Step(1 / 30)
		guard += 1
	end
end
-- everything a show touched is back the way the place has it
local function assertRestored(label)
	label = label or ""
	eq(State.Current, nil, label .. "no show")
	for i, p in ipairs(lidParts) do
		truthy((p.CFrame.Position - closed[i].Position).Magnitude < 1e-4, label .. "lid part " .. i .. " closed")
	end
	for k = 1, 3 do
		for _, p in ipairs(chains[k]) do
			eq(p.LocalTransparencyModifier, 0, label .. "chain visible")
			truthy((p.CFrame.Position - chainBase[p].Position).Magnitude < 1e-4, label .. "link home")
		end
	end
	for _, p in ipairs(padlock) do
		eq(p.LocalTransparencyModifier, 0, label .. "padlock")
	end
	for _, f in ipairs(ownFlames) do
		eq(f.LocalTransparencyModifier, 0, label .. "own candle")
	end
	for _, f in ipairs(shrineFlames) do
		eq(f.LocalTransparencyModifier, 0, label .. "shrine candle")
	end
	for _, s in ipairs(seams) do
		eq(s.Transparency, 1, label .. "seam dark")
		eq(s.Color, Color3.fromRGB(168, 70, 255), label .. "seam colour")
	end
	eq(glow.Transparency, 1, label .. "inner glow")
	eq(haze.Transparency, 1, label .. "inner haze")
	eq(innerLight.Enabled, false, label .. "inner light")
	eq(innerLight.Brightness, 3, label .. "inner light brightness")
	for _, r in ipairs(runes) do
		eq(r.Transparency, .3, label .. "rune")
		eq(r.Color, VIOLET, label .. "rune colour")
	end
	eq(prompt.Enabled, true, label .. "prompt back")
	local folder = CE.Workspace:FindFirstChild("DOGROTS_CoffinFX")
	eq(folder and #folder:GetChildren() or 0, 0, label .. "scene destroyed")
	eq(card(), nil, label .. "card gone")
	eq(liveDucks(), 0, label .. "no mixer duck")
	eq(CE.Service("Lighting"):FindFirstChild("DOGROTS_CoffinGrade"), nil, label .. "grade gone")
	eq(CE.Camera.CameraType, Enum.CameraType.Custom, label .. "camera custom")
	eq(CE.Bound[Cinema.RenderName], nil, label .. "no cinema render step")
	eq(mainGui:GetAttribute("CinemaActive"), nil, label .. "cinema off")
	local live = 0
	for _ in pairs(sinks) do
		live += 1
	end
	eq(live, 0, label .. "controls released")
	for _, p in ipairs(character:GetDescendants()) do
		if p:IsA("BasePart") then
			eq(p.LocalTransparencyModifier, 0, label .. "character visible")
		end
	end
	local overlay = CE.PlayerGui:FindFirstChild("DOGROTS_CinemaOverlay")
	local fade = overlay and overlay:FindFirstChild("Fade")
	truthy(not fade or fade.BackgroundTransparency > .999, label .. "no fade left")
end
local function finish(show)
	-- let a show end on its own (close the card, wait out the reset)
	local guard = 0
	while State.Current == show and guard < 3000 do
		local c = State.Card
		if c and not c.Closed and c.Continue then
			CE.Click(c.Continue)
		end
		CE.Step(1 / 20)
		guard += 1
	end
	CE.Advance(1)
end

---------------------------------------------------------------------------------------------------------------------
-- tests
---------------------------------------------------------------------------------------------------------------------
test("CoffinFX.Describe: currencies, cosmetics, dogs, finds, conversions, overflow", function()
	local d = CoffinFX.Describe({ Kind = "Dust", Amount = 96 })
	eq(d.Title, "LUCKY DUST")
	eq(d.Amount, "+96")
	d = CoffinFX.Describe({ Kind = "Find", Id = "uy_hollow_heart", Amount = 1 })
	eq(d.Title, "HOLLOW HEART")
	eq(d.Sub, "SHOWCASE FIND")
	eq(d.New, true)
	d = CoffinFX.Describe({ Kind = "Dog", Id = "HW_Bridehound" })
	eq(d.Title, "BRIDEHOUND")
	eq(d.Sub, "EVENT DOG · H14")
	eq(d.Status, "JOINED YOUR DOGS")
	d = CoffinFX.Describe({ Kind = "Decor", Id = "uy_moon_statue", Converted = true, Reason = "Owned",
		Conversion = { { Kind = "Fragments", Amount = 12 }, { Kind = "Dust", Amount = 400 } } })
	eq(d.Title, "MOON STATUE")
	eq(d.Status, "DUPLICATE")
	eq(#d.Chips, 2)
	eq(d.Chips[1], "FRAGMENTS +12")
	eq(d.Chips[2], "LUCKY DUST +400")
	d = CoffinFX.Describe({ Kind = "Find", Id = "uy_wax_hand", Converted = true, Reason = "Full", Conversion = { { Kind = "Shards", Amount = 80 } } })
	eq(d.Status, "STORAGE FULL")
	d = CoffinFX.Describe({ Kind = "Key", Amount = 0, Overflow = { Kind = "Shards", Amount = 60 } })
	eq(d.Status, "KEY STORAGE FULL")
	eq(d.Chips[1], "BELL SHARDS +60")
	d = CoffinFX.Describe({ Kind = "Cash", Amount = 50000 })
	eq(d.Title, "COINS")
	d = CoffinFX.Describe({ Kind = "Skin", Id = "UY_TVHead" })
	eq(d.Sub, "PICKAXE SKIN")
end)

test("every reward kind builds a display model (the real one or an icon), anchored and inert", function()
	for _, row in ipairs({ { Kind = "Dust" }, { Kind = "Shards" }, { Kind = "Bones" }, { Kind = "Cash" }, { Kind = "Fragments" }, { Kind = "Key" },
		{ Kind = "Title" }, { Kind = "Candy" }, { Kind = "Dog", Id = "HW_Bridehound" }, { Kind = "Find", Id = "uy_coffin_nail" },
		{ Kind = "Decor", Id = "uy_spirit_fence" }, { Kind = "Skin", Id = "UY_GummyHorror" }, { Kind = "Weird" } }) do
		local m = CoffinFX.BuildReward(row)
		truthy(m, "model for " .. row.Kind)
		local n = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				eq(d.Anchored, true)
				eq(d.CanCollide, false)
			end
		end
		truthy(n > 0, "parts for " .. row.Kind)
		truthy(m.PrimaryPart, "primary part for " .. row.Kind)
		m:Destroy()
	end
	-- a dog whose menu model the place has is the real thing
	local menu = CE.Folder("MenuModels", RS)
	local dog = CE.Model("HW_Bridehound", menu)
	part("RootPart", CF(0, 2, 0), V3(1, 1, 2), dog)
	local m, real = CoffinFX.BuildReward({ Kind = "Dog", Id = "HW_Bridehound" })
	eq(real, true)
	eq(m:FindFirstChild("RootPart") ~= nil, true)
	m:Destroy()
	menu:Destroy()
end)

test("a Common opening: chains, padlock, candles, rattle, seams, lid, pillar, reward, card, then everything restored", function()
	plays = {}
	signal("C2Coffin", payload(1, { Kind = "Dust", Amount = 96, Key = "Dust" }))
	local show = State.Current
	truthy(show, "the show runs")
	eq(show.Near, false)
	eq(mainGui:GetAttribute("CinemaActive"), true, "the cinematic")
	eq(prompt.Enabled, false, "the shrine prompt hides during the show")
	local b = show.Beats
	advanceTo(show, b.Chains[1].Tighten + .2)
	eq(played("CoffinChain"), 1)
	advanceTo(show, b.Chains[1].Snap + .05)
	eq(chains[1][1].LocalTransparencyModifier, 1, "chain 1 snapped")
	eq(chains[2][1].LocalTransparencyModifier, 0, "chain 2 still on")
	eq(played("CoffinChainSnap"), 1)
	truthy(sceneHas("FlyingLink"), "links fly")
	truthy(seams[1].Transparency < 1, "the first seam lights")
	eq(seams[5].Transparency, 1, "the cracks wait")
	advanceTo(show, b.Chains[3].Snap + .05)
	eq(played("CoffinChainSnap"), 3)
	eq(played("CoffinChain"), 3)
	advanceTo(show, b.Padlock + .05)
	eq(padlock[1].LocalTransparencyModifier, 1, "padlock dropped")
	truthy(sceneHas("FallingPadlock"))
	advanceTo(show, b.Flare + .3)
	truthy(sceneHas("CandleHalo"), "candles flare")
	eq(played("CandleLight"), 1)
	advanceTo(show, b.RattleFrom + .2)
	eq(played("CoffinRattle"), 1)
	truthy(not lidOpen(), "the lid only rattles")
	advanceTo(show, b.Open - .02)
	for _, s in ipairs(seams) do
		truthy(s.Transparency < .5, "every seam lit before the lid opens")
		truthy(s.Color.R > .75, "Common = bone-white light")
	end
	advanceTo(show, b.Open + .6)
	truthy(lidOpen(), "the lid blasts open")
	eq(played("CoffinLid"), 1)
	eq(played("CoffinRevealCommon"), 1)
	truthy(sceneHas("PillarCore"), "the light pillar")
	truthy(glow.Transparency < .5, "the inner glow")
	eq(innerLight.Enabled, true)
	eq(#music, 1, "the COFFIN sting")
	eq(music[1].Theme, "COFFIN")
	advanceTo(show, b.Rise + CC.Show.Rise)
	truthy(sceneHas("CoffinReward"), "the reward climbed out")
	advanceTo(show, b.Card + .1)
	truthy(card(), "the card")
	eq(cardText("Title"), "LUCKY DUST")
	eq(cardText("Rarity"), "COMMON")
	truthy(string.find(cardText("Sub"), "+96", 1, true), "the amount")
	eq(cardText("Kicker"), "THE BLACK COFFIN")
	truthy(string.find(cardText("Wallet"), "3", 1, true), "keys left")
	advanceTo(show, b.End + .5)
	eq(mainGui:GetAttribute("CinemaActive"), nil, "the cinematic ended")
	eq(CE.Camera.CameraType, Enum.CameraType.Custom)
	truthy(card(), "the card stays")
	truthy(lidOpen(), "the lid hangs open while the card is up")
	finish(show)
	assertRestored("common: ")
	eq(State.Last.Reason, "Done")
end)

test("Rare+: the shockwave; Mythic: lightning, slow motion, the longer show", function()
	plays = {}
	signal("C2Coffin", payload(3, { Kind = "Find", Id = "uy_lost_veil", Amount = 1 }))
	local show = State.Current
	advanceTo(show, show.Beats.Open + .3)
	eq(played("ShockwaveRing"), 1, "Rare+ shockwave")
	eq(played("CoffinRevealEpic"), 1)
	eq(played("Thunder"), 0, "no lightning below Mythic")
	finish(show)
	assertRestored("epic: ")
	plays = {}
	signal("C2Coffin", payload(5, { Kind = "Dog", Id = "HW_Bridehound", Amount = 1 }))
	show = State.Current
	local b = show.Beats
	truthy(b.SlowFrom and b.RealEnd > b.End, "slow motion")
	advanceTo(show, b.Lightning[1] + .1)
	eq(played("Thunder"), 1, "the first strike")
	truthy(sceneHas("Bolt"), "a bolt")
	advanceTo(show, b.Open + .3)
	eq(played("Thunder"), 3, "three strikes")
	eq(played("CoffinRevealMythic"), 1)
	-- the slow-motion window: show time runs at the configured rate
	advanceTo(show, b.SlowFrom + .01)
	local t0, r0 = CC.ShowTime(b, CE.Now - show.T0), CE.Now
	CE.Advance(.5, 1 / 30)
	local rate = (CC.ShowTime(b, CE.Now - show.T0) - t0) / (CE.Now - r0)
	near(rate, CC.Show.SlowMo.Rate, .05, "slow motion rate")
	advanceTo(show, b.Card + .1)
	eq(cardText("Rarity"), "MYTHIC")
	eq(cardText("Title"), "BRIDEHOUND")
	eq(cardText("Status"), "JOINED YOUR DOGS")
	finish(show)
	assertRestored("mythic: ")
end)

test("the skip: only after the lid opens, then straight to the card", function()
	plays = {}
	signal("C2Coffin", payload(4, { Kind = "Decor", Id = "uy_ghost_fountain", Amount = 1 }))
	local show = State.Current
	local b = show.Beats
	advanceTo(show, b.Chains[2].Snap)
	CE.Tap()
	CE.Step(1 / 30)
	eq(card(), nil, "no skip before the lid opens")
	eq(mainGui:GetAttribute("CinemaActive"), true)
	advanceTo(show, b.Open + .1)
	CE.Tap()
	CE.Advance(.5)
	truthy(card(), "the card at once")
	eq(cardText("Title"), "GHOST FOUNTAIN")
	eq(cardText("Status"), "NEW · ADDED TO YOUR PLOT COSMETICS")
	truthy(lidOpen())
	truthy(sceneHas("CoffinReward"), "the reward is out")
	eq(mainGui:GetAttribute("CinemaActive"), nil, "the camera went home")
	finish(show)
	assertRestored("skip: ")
end)

test("a duplicate shows its conversion; bonus rows (crown, pug) are on the card", function()
	local main = { Kind = "Find", Id = "uy_hollow_heart", Converted = true, Reason = "Owned",
		Conversion = { { Kind = "Shards", Amount = 100 }, { Kind = "Dust", Amount = 188 }, { Kind = "Fragments", Amount = 3 } } }
	local p = payload(5, main, { Converted = true, Duplicate = true })
	p.Rows = { main, { Kind = "Find", Id = "uy_wax_hand", Amount = 1, Bonus = "Crown" },
		{ Kind = "Find", Id = "uy_black_feather", Amount = 0, Bonus = "Pug", Converted = true, Reason = "Owned",
			Conversion = { { Kind = "Shards", Amount = 100 } } } }
	signal("C2Coffin", p)
	local show = State.Current
	advanceTo(show, show.Beats.Card + .05)
	eq(cardText("Status"), "DUPLICATE")
	local conv = card().Card.Conversion
	local chips = {}
	for _, c in ipairs(conv:GetChildren()) do
		if c.Name == "Chip" then
			table.insert(chips, c)
		end
	end
	eq(#chips, 3)
	eq(chips[1].Visible, false, "the chips pop in after the stamp")
	CE.Advance(1.8)
	eq(chips[1].Visible, true)
	eq(chips[3].Visible, true)
	eq(chips[1].Text.Text, "BELL SHARDS +100")
	local bonus = {}
	for _, c in ipairs(card().Card:GetChildren()) do
		if c.Name == "Bonus" then
			table.insert(bonus, c.Chip.Text.Text)
		end
	end
	eq(#bonus, 2)
	truthy(string.find(bonus[1], "CROWN OF THE UNDERYARD: WAX HAND", 1, true), bonus[1])
	truthy(string.find(bonus[2], "COFFIN SENSE: BLACK FEATHER", 1, true) and string.find(bonus[2], "BELL SHARDS +100", 1, true), bonus[2])
	finish(show)
	assertRestored("duplicate: ")
end)

test("SECRET with the arrival: blackout, music cut, violet seams, the lid, the hand-off; nothing presented twice", function()
	plays = {}
	music = {}
	local p = payload(6, { Kind = "Dog", Id = "HW_HollowKing", Amount = 1 })
	local b6 = CC.Beats(6)
	p.Arrival = true
	p.Handoff = p.At + b6.Handoff
	signal("C2Coffin", p)
	local show = State.Current
	local b = show.Beats
	eq(b.Secret, true)
	advanceTo(show, b.Blackout + .5)
	truthy(ducks.HollowKing, "the music is cut")
	eq(ducks.HollowKing, "Silence")
	truthy(CE.Service("Lighting"):FindFirstChild("DOGROTS_CoffinGrade"), "the grade")
	local fade = CE.PlayerGui.DOGROTS_CinemaOverlay.Fade
	truthy(fade.BackgroundTransparency < .05, "black")
	eq(ownFlames[1].LocalTransparencyModifier, 1, "the candles die")
	eq(played("CandleSnuff"), 1)
	advanceTo(show, b.Lift + .9)
	near(fade.BackgroundTransparency, 1 - CC.Show.Secret.Lift, .02, "the dark lifts a little")
	truthy(seams[1].Transparency < .5, "the seams burn in the dark")
	truthy(seams[1].Color.B > .9 and seams[1].Color.G < .5, "violet")
	advanceTo(show, b.Open + .4)
	truthy(lidOpen())
	eq(played("CoffinRevealSecret"), 1)
	truthy(sceneHas("PillarCore"))
	eq(#music, 0, "no sting over the silence")
	advanceTo(show, b.Handoff + 4.5)
	eq(sceneHas("BlackMoon"), false, "the arrival has the moon")
	eq(sceneHas("HollowKing"), false, "the arrival has the king")
	eq(CE.PlayerGui:FindFirstChild("DOGROTS_CoffinBanner"), nil, "the Mega layer has the banner")
	advanceTo(show, b.Release + .2)
	eq(ducks.HollowKing, nil, "the music comes back")
	advanceTo(show, b.Card + .2)
	eq(card(), nil, "the arrival is the card")
	truthy(lidOpen(), "the lid stays open for the arrival")
	advanceTo(show, b.Handoff + CC.Show.Secret.Linger - .3)
	truthy(State.Current == show, "still on")
	finish(show)
	assertRestored("secret: ")
end)

test("SECRET without an arrival: the module's own moon, king, crown, banner and card", function()
	plays = {}
	local p = payload(6, { Kind = "Dog", Id = "HW_HollowKing", Amount = 1 })
	p.Arrival = false
	p.Handoff = p.At + CC.Beats(6).Handoff
	signal("C2Coffin", p)
	local show = State.Current
	local b = show.Beats
	advanceTo(show, b.Handoff + .2)
	truthy(sceneHas("BlackMoon"), "the black moon")
	truthy(sceneHas("HollowKing"), "the king")
	advanceTo(show, b.Handoff + CC.Show.Secret.Total + .2)
	local king = scene():FindFirstChild("HollowKing", true)
	local hl = king:FindFirstChild("Ink")
	truthy(hl and hl.FillTransparency < .5, "still an ink silhouette at totality")
	eq(played("BellTollHuge"), 1)
	advanceTo(show, b.Handoff + CC.Show.Secret.Banner + .2)
	local banner = CE.PlayerGui:FindFirstChild("DOGROTS_CoffinBanner")
	truthy(banner, "the banner")
	eq(banner.Banner.Main.Text, "TESTER RAISED THE HOLLOW KING")
	advanceTo(show, b.Card + .2)
	truthy(card(), "the card")
	eq(cardText("Title"), "HOLLOW KING")
	eq(cardText("Rarity"), "SECRET")
	finish(show)
	assertRestored("secret fallback: ")
	CE.Advance(CC.Show.Omen.Hold + 1)
end)

test("the lighter version: no camera, no card, a name plate; it yields to the player's own opening", function()
	plays = {}
	local p = payload(4, { Kind = "Skin", Id = "UY_FateHand", Amount = 1 }, { UserId = 77, Name = "Neighbour" })
	signal("C2CoffinNear", p)
	local show = State.Current
	truthy(show and show.Near, "the lighter show")
	eq(mainGui:GetAttribute("CinemaActive"), nil, "no cinematic for onlookers")
	advanceTo(show, show.Beats.Card + .2)
	eq(card(), nil, "no card")
	local plate = scene():FindFirstChild("CoffinNamePlate", true)
	truthy(plate, "the name plate")
	eq(plate.Who.Text, "NEIGHBOUR")
	truthy(string.find(plate.What.Text, "HAND OF FATE", 1, true), plate.What.Text)
	for _, pl in ipairs(plays) do
		if pl.Cue == "CoffinLid" then
			near(pl.Volume, CC.Show.Near.Volume, 1e-6, "quieter")
		end
	end
	-- the player's own opening takes over at once
	signal("C2Coffin", payload(1, { Kind = "Bones", Amount = 450 }))
	local own = State.Current
	truthy(own and not own.Near, "own show")
	eq(State.Last.Reason, "Preempted")
	finish(own)
	assertRestored("near: ")
	-- an onlooker's show never interrupts the player's own
	signal("C2Coffin", payload(1, { Kind = "Bones", Amount = 450 }))
	own = State.Current
	signal("C2CoffinNear", payload(2, { Kind = "Cash", Amount = 50000 }, { UserId = 78, Name = "Other" }))
	eq(State.Current, own)
	finish(own)
	assertRestored("near 2: ")
end)

test("openings queue; OPEN AGAIN asks the server and the next show plays after the reset", function()
	requests = {}
	signal("C2Coffin", payload(2, { Kind = "Fragments", Amount = 2 }))
	local first = State.Current
	advanceTo(first, first.Beats.Card + .1)
	local c = State.Card
	truthy(c and c.Again, "OPEN AGAIN while keys and shards last and the player is at the shrine")
	CE.Click(c.Again)
	CE.Advance(0)
	eq(#requests, 1)
	eq(requests[1].Action, "C2CoffinOpen")
	-- the server's answer arrives while the lid is still closing
	signal("C2Coffin", payload(1, { Kind = "Dust", Amount = 70 }))
	eq(State.Current, first, "queued")
	eq(#State.Queue, 1)
	CE.Advance(CC.Show.CloseLid + 1)
	local second = State.Current
	truthy(second and second ~= first, "the next show")
	eq(#State.Queue, 0)
	finish(second)
	assertRestored("queue: ")
	-- no OPEN AGAIN without keys
	signal("C2Coffin", payload(1, { Kind = "Dust", Amount = 70 }, { Keys = 0 }))
	local third = State.Current
	advanceTo(third, third.Beats.Card + .1)
	eq(State.Card.Again, nil)
	finish(third)
	assertRestored("no keys: ")
end)

test("a refused OPEN AGAIN and C2CoffinRefused become localized toasts", function()
	toasts = {}
	CE.Player:SetAttribute("DOGROTS_Language", "ru")
	CE.Advance(6) -- Shared.IsRussian caches for 5 s
	signal("C2CoffinRefused", { Text = "You need a Coffin Key", Need = "Key" })
	CE.Advance(0)
	eq(#toasts, 1)
	eq(toasts[1].Text, "Нужен ключ от гроба")
	eq(toasts[1].NoTranslate, true)
	requestReply = { false, "Make room in your dog storage first" }
	signal("C2Coffin", payload(2, { Kind = "Fragments", Amount = 2 }))
	local show = State.Current
	advanceTo(show, show.Beats.Card + .1)
	eq(cardText("Kicker"), "ЧЁРНЫЙ ГРОБ", "Russian card")
	eq(cardText("Rarity"), "РЕДКОЕ")
	eq(cardText("Title"), "ФРАГМЕНТЫ КОСМЕТИКИ")
	CE.Click(State.Card.Again)
	CE.Advance(0)
	eq(toasts[#toasts].Text, "Сначала освободи место в хранилище собак")
	requestReply = { true, {} }
	finish(show)
	assertRestored("ru: ")
	CE.Player:SetAttribute("DOGROTS_Language", "en")
	CE.Advance(6)
end)

test("C2Announce HollowKing: the banner for others only when no arrival names the raiser; Mythic is the HUD's", function()
	local before = State.Banners
	signal("C2Announce", { Kind = "HollowKing", Name = "Someone", UserId = 99, Arrival = true, RevealAt = CE.Unix })
	CE.Advance(6)
	eq(State.Banners, before, "the Mega layer names the raiser")
	signal("C2Announce", { Kind = "Mythic", Name = "Someone", UserId = 99, RevealAt = CE.Unix })
	CE.Advance(2)
	eq(State.Banners, before)
	signal("C2Announce", { Kind = "HollowKing", Name = "Tester", UserId = 1, Arrival = false, RevealAt = CE.Unix })
	CE.Advance(6)
	eq(State.Banners, before, "the opener's own show has it")
	signal("C2Announce", { Kind = "HollowKing", Name = "Someone", UserId = 99, Arrival = false, RevealAt = CE.Unix })
	CE.Advance(2)
	eq(State.Banners, before + 1, "the omen banner")
	local g = CE.PlayerGui:FindFirstChild("DOGROTS_CoffinBanner")
	eq(g.Banner.Main.Text, "SOMEONE RAISED THE HOLLOW KING")
	CE.Advance(CC.Show.Omen.Hold + 1)
	eq(CE.PlayerGui:FindFirstChild("DOGROTS_CoffinBanner"), nil, "the banner fades")
end)

test("low quality + reduced motion: fewer lights and links, no flashes, same beats, same restore", function()
	CE.Player:SetAttribute("WorldEventFX", "Low")
	CE.Player:SetAttribute("ReducedMotion", true)
	plays = {}
	signal("C2Coffin", payload(5, { Kind = "Skin", Id = "UY_TVHead", Amount = 1 }))
	local show = State.Current
	eq(show.LightBudget <= math.floor(12 * .5 + .5), true, "light budget")
	advanceTo(show, show.Beats.Chains[1].Snap + .05)
	local links = 0
	for _, d in ipairs(scene():GetChildren()) do
		if d.Name == "FlyingLink" then
			links += 1
		end
	end
	truthy(links > 0 and links < #chains[1], "a share of the links fly")
	advanceTo(show, show.Beats.Card + .1)
	truthy(card())
	eq(cardText("Rarity"), "MYTHIC")
	finish(show)
	assertRestored("low: ")
	CE.Player:SetAttribute("WorldEventFX", nil)
	CE.Player:SetAttribute("ReducedMotion", nil)
end)

test("an error mid-show, a death mid-show and Stop all restore everything", function()
	signal("C2Coffin", payload(2, { Kind = "Bones", Amount = 400 }))
	local show = State.Current
	advanceTo(show, show.Beats.Chains[2].Snap + .1)
	show.Halos = "sabotage" -- the frame loop throws
	CE.Step(1 / 30)
	eq(State.Current, nil, "torn down")
	eq(State.Last.Reason, "Error")
	CE.Advance(1)
	assertRestored("error: ")
	-- death: the camera goes home, the world show and the card still finish
	signal("C2Coffin", payload(2, { Kind = "Bones", Amount = 400 }))
	show = State.Current
	advanceTo(show, show.Beats.Open + .2)
	character:FindFirstChildOfClass("Humanoid").Died:Fire()
	CE.Advance(.2)
	eq(mainGui:GetAttribute("CinemaActive"), nil, "the cinematic ended with the death")
	truthy(State.Current == show, "the show goes on")
	finish(show)
	assertRestored("death: ")
	-- Stop
	signal("C2Coffin", payload(3, { Kind = "Key", Amount = 1 }))
	show = State.Current
	advanceTo(show, show.Beats.Open + .5)
	CoffinFX.Stop("Test")
	CE.Advance(1)
	assertRestored("stop: ")
end)

test("no coffin in the world (streamed out): the opener still gets the card", function()
	coffin.Parent = nil
	signal("C2Coffin", payload(3, { Kind = "Find", Id = "uy_dead_wedding_ring", Amount = 1 }))
	eq(State.Current, nil)
	truthy(card(), "the card")
	eq(cardText("Title"), "DEAD WEDDING RING")
	CE.Click(State.Card.Continue)
	CE.Advance(1)
	eq(card(), nil)
	coffin.Parent = uy
end)

test("localization: every CoffinFX text has Russian; server replies are in Localization.Coffin", function()
	local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HalloweenClient/CoffinFX.luau")
	local Loc = CE.Require(RS.Localization.Coffin)
	local missing = {}
	local function check(key)
		if not Loc.Translate(key, "ru") then
			table.insert(missing, key)
		end
	end
	for key in string.gmatch(src, "[^%w_][TF]%(\"([^\"]+)\"") do
		check(key)
	end
	for _, block in ipairs({ "CURRENCY", "CHIP", "REASON" }) do
		local body = string.match(src, "local " .. block .. " = (%b{})")
		truthy(body, block)
		for key in string.gmatch(body, "\"([^\"]+)\"") do
			check(key)
		end
	end
	eq(#missing, 0, "missing Russian: " .. table.concat(missing, ", "))
	local server = fs.readFile("src/ServerScriptService/Halloween/Coffin.luau")
	for _, msg in ipairs({ "You need a Coffin Key", "Come closer to the Black Coffin", "Make room in your dog storage first",
		"The Black Coffin opens", "Coffin preview" }) do
		truthy(string.find(server, msg, 1, true), "the server sends " .. msg)
		truthy(Loc.Exact[msg], "Exact " .. msg)
	end
	-- no Exact key repeats another module's (they are all global)
	local seen = {}
	for _, inst in ipairs(RS.Localization:GetChildren()) do
		if inst.Name ~= "Coffin" then
			local ok, m = pcall(CE.Require, inst)
			if ok and type(m) == "table" and type(m.Exact) == "table" then
				for k in pairs(m.Exact) do
					seen[k] = inst.Name
				end
			end
		end
	end
	for k in pairs(Loc.Exact) do
		eq(seen[k], nil, "duplicate Exact key " .. k)
	end
end)

test("nothing warned along the way (but the sabotaged frame)", function()
	local bad = {}
	for _, w in ipairs(CE.Warnings) do
		if (string.find(w, "CoffinFX", 1, true) or string.find(w, "Cinema", 1, true)) and not string.find(w, "got string", 1, true) then
			table.insert(bad, w)
		end
	end
	eq(#bad, 0, table.concat(bad, "\n"))
end)

print(string.format("coffin_client: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("coffin_client tests failed")
end
