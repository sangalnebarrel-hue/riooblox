-- THE HAUNTED CAULDRON, alive (StarterPlayerScripts.HalloweenClient.CauldronFX), WP10b. Client only.
-- Idle: bubbles rising and popping on BrewSurface, steam wisps from SteamPoint attachments, green flames under the pot,
-- faces forming in the smoke now and then (part-built, fade in -> wail -> fade out), runes Rune1..8 lit by the LOCAL
-- player's cauldron level (State.View.Cauldron.Level: more runes, brighter brew, taller flames, more steam, orbiting
-- wisps at L4-L5), the hanging chains nudged (Bus "ChainKick", AmbientFX swings them), a bubbling sound bed.
-- Signal "Cauldron" {Kind, UserId, Level, Tier} for everyone:
--   Trick   candies arc from the player into the pot -> the brew boils up -> flash -> a Pumpkin Lucky Block
--           (RS.Halloween.Models.Pumpkin.Block(tier) when present, else CauldronFX.Models.PumpkinBlock) flies out,
--           lands at the player and dissolves into them (the real block went to their inventory).
--   Treat   a few candies into the pot, a small surge.          LevelUp  rune flare + ring + steam burst.
--   Claim   a brew geyser + gold sparks + beam.
-- Everything is client-local under workspace.DOGROTS_HalloweenFX (SelfManagedFX), budgeted by Shared.Quality(), off
-- beyond 260 studs. Markers (WP1 Cauldron builder): BrewSurface, Rune1..8, SteamPoint / RunePoint / ChainPoint.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Ambient = require(script.Parent:WaitForChild("AmbientFX"))
local Rig = Ambient.Rig

local IDENT = CFrame.new()
local V3 = Vector3.new
local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local rad = math.rad
local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end
local smooth, envelope = Ambient.Smooth, Ambient.Envelope
local attPos = Ambient.AttPos

local CauldronFX = {}

-- per cauldron level presentation (index = level 1..5)
CauldronFX.Levels = {
	{ Runes = 2, Bubbles = 2.2, BubbleSize = .7, Steam = 1.0, Flame = .55, Glow = .8, Bright = 0, Wisps = 0, Face = 22 },
	{ Runes = 3, Bubbles = 3.2, BubbleSize = .8, Steam = 1.3, Flame = .7, Glow = .95, Bright = .15, Wisps = 0, Face = 18 },
	{ Runes = 5, Bubbles = 4.4, BubbleSize = .9, Steam = 1.7, Flame = .85, Glow = 1.15, Bright = .3, Wisps = 0, Face = 15 },
	{ Runes = 6, Bubbles = 5.6, BubbleSize = 1.0, Steam = 2.1, Flame = 1.0, Glow = 1.35, Bright = .45, Wisps = 2, Face = 12 },
	{ Runes = 8, Bubbles = 7.0, BubbleSize = 1.15, Steam = 2.6, Flame = 1.25, Glow = 1.6, Bright = .65, Wisps = 4, Face = 9 },
}
function CauldronFX.Profile(level: any)
	local n = math.clamp(math.floor(tonumber(level) or 1), 1, #CauldronFX.Levels)
	return CauldronFX.Levels[n], n
end

local C = {
	Smoke = RGB(170, 255, 196), SmokeDark = RGB(20, 40, 30), FaceEye = RGB(200, 255, 150),
	Brew = RGB(120, 255, 90), BrewHot = RGB(200, 255, 140), Rune = RGB(180, 100, 255), RuneHot = RGB(235, 190, 255),
	Pumpkin = RGB(255, 128, 24), PumpkinDark = RGB(196, 82, 16), Stem = RGB(78, 96, 44), Glow = RGB(255, 214, 90),
	Cursed = RGB(52, 24, 70), CursedDark = RGB(30, 12, 42), CursedGlow = RGB(190, 90, 255), Gold = RGB(255, 200, 70),
}
CauldronFX.Colors = C

---------------------------------------------------------------------------------------------------------------------
-- Models
---------------------------------------------------------------------------------------------------------------------
local Models = {}
CauldronFX.Models = Models

-- a face formed of smoke (~3 tall). opts.Style 1 = wailing ghost dog, 2 = skull, 3 = howling hound. Bones: Jaw, Ears
function Models.SmokeFace(parent: Instance?, opts: { [string]: any }?): any
	opts = opts or {}
	local style = opts.Style or 1
	local r = Rig.new("HwSmokeFace", parent)
	local m = Enum.Material.SmoothPlastic
	local smoke, hole = C.Smoke, C.SmokeDark
	r:Bone("Jaw", "Root", at(0, -.35, .2))
	r:Bone("Ears", "Root", at(0, .9, .2))
	if style == 2 then
		r:Part("Root", V3(2.2, 2.0, 2.0), at(0, .45, .3), smoke, m, { Mesh = "Sphere", T = .5, Name = "Smoke" })
		r:Part("Root", V3(1.2, .9, 1.2), at(0, -.1, -.5), smoke, m, { Mesh = "Sphere", T = .45, Name = "Smoke" })
		for s = -1, 1, 2 do
			r:Part("Root", V3(.62, .7, .3), at(s * .45, .55, -.6) * ang(0, 0, s * 14), hole, m, { Mesh = "Sphere", T = .15, Name = "Hole" })
			r:Part("Root", V3(.14, .14, .14), at(s * .43, .52, -.72), C.FaceEye, Enum.Material.Neon, { Shape = "Ball", T = .1, Name = "Eye" })
		end
		r:Part("Root", V3(.3, .36, .2), at(0, .08, -1.06), hole, m, { Mesh = "Sphere", T = .2, Name = "Hole" })
		r:Part("Jaw", V3(1.0, .6, .9), at(0, -.62, -.4), smoke, m, { Mesh = "Sphere", T = .5, Name = "Smoke" })
		r:Part("Jaw", V3(.7, .45, .25), at(0, -.45, -.82), hole, m, { Mesh = "Sphere", T = .2, Name = "Mouth" })
	else
		r:Part("Root", V3(1.9, 1.7, 1.8), at(0, .4, .3), smoke, m, { Mesh = "Sphere", T = .5, Name = "Smoke" })
		r:Part("Root", V3(.9, .7, 1.4), at(0, .05, -.7) * ang(style == 3 and 18 or 0, 0, 0), smoke, m, { Mesh = "Sphere", T = .45, Name = "Smoke" })
		r:Part("Root", V3(.26, .2, .16), at(0, style == 3 and .45 or .2, style == 3 and -1.35 or -1.4), hole, m, { Mesh = "Sphere", T = .2, Name = "Nose" })
		for s = -1, 1, 2 do
			r:Part("Root", V3(.38, .5, .2), at(s * .36, .6, -.62) * ang(0, s * -12, s * (style == 3 and -14 or 14)), hole, m,
				{ Mesh = "Sphere", T = .12, Name = "Hole" })
			r:Part("Root", V3(.12, .12, .12), at(s * .34, .58, -.72), C.FaceEye, Enum.Material.Neon, { Shape = "Ball", T = .1, Name = "Eye" })
			if style == 3 then
				r:Part("Ears", V3(.36, 1.2, .5), at(s * .6, 1.45, .25) * ang(-10, 0, s * -16), smoke, m, { Class = "WedgePart", T = .5, Name = "Ear" })
			else
				r:Part("Ears", V3(.42, 1.5, .55), at(s * .95, .9, .25) * ang(0, 0, s * 35), smoke, m, { Mesh = "Sphere", T = .55, Name = "Ear" })
			end
		end
		r:Part("Jaw", V3(.8, .45, 1.1), at(0, -.5, -.55), smoke, m, { Mesh = "Sphere", T = .5, Name = "Smoke" })
		r:Part("Jaw", V3(.5, .55, .2), at(0, -.36, -1.05), hole, m, { Mesh = "Sphere", T = .2, Name = "Mouth" })
	end
	-- trailing smoke tail below the face
	r:Part("Root", V3(1.3, 1.3, 1.3), at(0, -1.2, .5), smoke, m, { Mesh = "Sphere", T = .62, Name = "Tail" })
	r:Part("Root", V3(.8, .9, .8), at(.15, -2.0, .65), smoke, m, { Mesh = "Sphere", T = .7, Name = "Tail" })
	r:Part("Root", V3(.45, .6, .45), at(.3, -2.6, .75), smoke, m, { Mesh = "Sphere", T = .78, Name = "Tail" })
	r:Update(IDENT, Models.SmokeFacePose(0))
	return r
end

function Models.SmokeFacePose(wail: number, t: number?): { [string]: CFrame }
	t = t or 0
	return { Jaw = ang(wail * 32, 0, 0) * at(0, -wail * .2, 0), Ears = ang(-wail * 15 + math.sin(t * 3) * 5, 0, 0) }
end

-- fallback Pumpkin Lucky Block (when RS.Halloween.Models.Pumpkin is missing): carved pumpkin cube with a stem and vines
function Models.PumpkinBlock(parent: Instance?, opts: { [string]: any }?): any
	opts = opts or {}
	local cursed = opts.Tier == "Cursed Pumpkin"
	local body = cursed and C.Cursed or C.Pumpkin
	local dark = cursed and C.CursedDark or C.PumpkinDark
	local glow = cursed and C.CursedGlow or C.Glow
	local r = Rig.new("HwPumpkinBlock", parent)
	local m = Enum.Material.SmoothPlastic
	local S = 2.6
	r:Bone("Lid", "Root", at(0, S, 0))
	r:Part("Root", V3(S, S, S), at(0, S / 2, 0), body, m, { Name = "Body" })
	-- ribs (vertical grooves) on every face
	for face = 0, 3 do
		local rot = ang(0, face * 90, 0)
		for _, x in ipairs({ -.65, 0, .65 }) do
			r:Part("Root", V3(.16, S - .2, .06), rot * at(x, S / 2, -S / 2 - .02), dark, m, { Name = "Rib" })
		end
		-- carved face
		for s = -1, 1, 2 do
			r:Part("Root", V3(.05, .5, .46), rot * at(s * .5, S * .62, -S / 2 - .04) * ang(0, s * 90, 0), glow, Enum.Material.Neon,
				{ Class = "WedgePart", Name = "Eye" })
		end
		r:Part("Root", V3(.3, .26, .05), rot * at(0, S * .48, -S / 2 - .04), glow, Enum.Material.Neon, { Name = "NoseGlow" })
		r:Part("Root", V3(1.5, .34, .05), rot * at(0, S * .3, -S / 2 - .04), glow, Enum.Material.Neon, { Name = "Mouth" })
		for _, x in ipairs({ -.4, .4 }) do
			r:Part("Root", V3(.22, .2, .07), rot * at(x, S * .36, -S / 2 - .06), body, m, { Name = "Tooth" })
		end
	end
	-- bevel edges
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			r:Part("Root", V3(.22, S + .04, .22), at(sx * S / 2, S / 2, sz * S / 2), dark, m, { Name = "Edge" })
		end
	end
	r:Part("Lid", V3(S + .1, .22, S + .1), at(0, S + .05, 0), dark, m, { Name = "Cap" })
	r:Part("Lid", V3(.36, .7, .36), at(0, S + .5, 0) * ang(8, 0, 12), cursed and RGB(40, 30, 50) or C.Stem, Enum.Material.Wood, { Name = "Stem" })
	r:Part("Lid", V3(.9, .08, .5), at(.45, S + .3, .2) * ang(0, 30, -12), cursed and RGB(70, 30, 90) or RGB(96, 150, 60), m, { Mesh = "Sphere", Name = "Leaf" })
	for k = 0, 3 do
		local a = rad(k * 90 + 25)
		r:Part("Lid", V3(.1, .1, .8), at(math.cos(a) * .9, S + .18, math.sin(a) * .9) * ang(0, -math.deg(a), 0), cursed and RGB(70, 30, 90) or RGB(96, 150, 60),
			m, { Name = "Vine" })
	end
	if cursed then
		for k = 0, 2 do
			r:Part("Lid", V3(.22, .7, .22), at(-.6 + k * .6, S + .5, -.9), C.CursedGlow, Enum.Material.Neon, { Class = "WedgePart", T = .3, Name = "Flame" })
		end
	end
	r:Update(IDENT)
	return r
end

-- THE BURIED MOON BREW: the season's potion (~4.6 tall, base at the origin). Glass flask with the glowing brew inside,
-- bubbles, neck + lip, cork, a blood-red wax seal with drips, a rope collar, a parchment label with a moon emblem and two
-- stars, glass highlights. opts.Brew = liquid colour. Bones: Liquid (pulses), Cork.
function Models.PotionBottle(parent: Instance?, opts: { [string]: any }?): any
	opts = opts or {}
	local brewCol = opts.Brew or C.Brew
	local glass = RGB(206, 232, 255)
	local r = Rig.new("HwBrewPotion", parent)
	local GL, NE, SM = Enum.Material.Glass, Enum.Material.Neon, Enum.Material.SmoothPlastic
	local UP = ang(0, 0, 90) -- cylinder axis (X) -> up
	r:Bone("Liquid", "Root", at(0, 1.45, 0))
	r:Bone("Cork", "Root", at(0, 4.1, 0))
	-- glass body, base ring, neck and lip
	r:Part("Root", V3(3.1, 3.1, 3.1), at(0, 1.55, 0), glass, GL, { Shape = "Ball", T = .55, Name = "Flask" })
	r:Part("Root", V3(.16, 2.1, 2.1), at(0, .12, 0) * UP, glass:Lerp(RGB(60, 70, 110), .4), GL, { Shape = "Cylinder", T = .35, Name = "Base" })
	r:Part("Root", V3(1.15, .86, .86), at(0, 3.25, 0) * UP, glass, GL, { Shape = "Cylinder", T = .5, Name = "Neck" })
	r:Part("Root", V3(.2, 1.08, 1.08), at(0, 3.82, 0) * UP, glass:Lerp(WHITE, .3), GL, { Shape = "Cylinder", T = .35, Name = "Lip" })
	-- the brew: a glowing core, the liquid, its surface and bubbles
	r:Part("Liquid", V3(2.6, 2.4, 2.6), at(0, 1.3, 0), brewCol, NE, { Mesh = "Sphere", T = .08, Name = "Liquid", Glow = true })
	r:Part("Liquid", V3(1.3, 1.3, 1.3), at(0, 1.35, 0), brewCol:Lerp(WHITE, .6), NE, { Shape = "Ball", T = .25, Name = "Core", Glow = true })
	r:Part("Liquid", V3(.12, 2.3, 2.3), at(0, 2.42, 0) * UP, brewCol:Lerp(WHITE, .35), NE, { Shape = "Cylinder", T = .2, Name = "Surface", Glow = true })
	for k, b in ipairs({ { -.5, .9, -.6, .32 }, { .55, 1.3, -.4, .24 }, { .1, 1.9, -.8, .2 }, { -.3, 1.6, .5, .26 }, { .45, .7, .5, .18 } }) do
		r:Part("Liquid", V3(b[4], b[4], b[4]), at(b[1], b[2], b[3]), brewCol:Lerp(WHITE, .75), NE, { Shape = "Ball", T = .1, Name = "Bubble" .. k, Glow = true })
	end
	-- cork, wax seal + drips, rope collar
	r:Part("Cork", V3(.62, .72, .72), at(0, 4.12, 0) * UP, RGB(176, 124, 72), Enum.Material.Wood, { Shape = "Cylinder", Name = "Cork" })
	r:Part("Cork", V3(1.0, .34, 1.0), at(0, 4.52, 0), RGB(170, 18, 40), SM, { Mesh = "Sphere", Name = "Wax" })
	for k = 0, 2 do
		local a = rad(k * 120 + 20)
		r:Part("Root", V3(.16, .42, .16), at(math.cos(a) * .48, 3.86, math.sin(a) * .48), RGB(170, 18, 40), SM, { Mesh = "Sphere", Name = "Drip" })
	end
	r:Part("Root", V3(.14, 1.0, 1.0), at(0, 3.5, 0) * UP, RGB(150, 110, 70), Enum.Material.Fabric, { Shape = "Cylinder", Name = "Rope" })
	r:Part("Root", V3(.12, .55, .12), at(.42, 3.2, -.32) * ang(0, 0, 18), RGB(150, 110, 70), Enum.Material.Fabric, { Name = "RopeEnd" })
	-- parchment label (a curved band of panels) with the moon emblem and two stars
	for k = -2, 2 do
		local a = rad(k * 21)
		r:Part("Root", V3(.6, 1.1, .05), CFrame.new(math.sin(a) * 1.5, 1.45, -math.cos(a) * 1.5) * ang(0, -math.deg(a), 0), RGB(236, 220, 178), SM,
			{ Name = "Label" })
	end
	r:Part("Root", V3(.05, .62, .62), at(0, 1.5, -1.56) * ang(0, 90, 0), RGB(255, 240, 200), NE, { Shape = "Cylinder", Name = "Moon", Glow = true })
	r:Part("Root", V3(.05, .5, .5), at(.14, 1.56, -1.58) * ang(0, 90, 0), RGB(64, 30, 90), SM, { Shape = "Cylinder", Name = "MoonShadow" })
	for _, s in ipairs({ { -.38, 1.75 }, { .36, 1.2 } }) do
		r:Part("Root", V3(.1, .1, .05), at(s[1], s[2], -1.57) * ang(0, 0, 45), RGB(255, 220, 120), NE, { Name = "Star", Glow = true })
	end
	-- glass highlights
	r:Part("Root", V3(.22, 1.2, .1), at(-.95, 2.0, -.95) * ang(0, 45, 18), WHITE, NE, { Mesh = "Sphere", T = .35, Name = "Shine" })
	r:Part("Root", V3(.12, .4, .08), at(-.32, 3.3, -.38) * ang(0, 45, 0), WHITE, NE, { Mesh = "Sphere", T = .3, Name = "Shine" })
	r:Update(IDENT)
	return r
end

---------------------------------------------------------------------------------------------------------------------
-- pure helpers (Lune-tested)
---------------------------------------------------------------------------------------------------------------------
-- surface height of the brew at horizontal distance d from its centre (dome or flat)
function CauldronFX.SurfaceY(brew: { [string]: any }, d: number): number
	if brew.Dome then
		local k = math.clamp(d / math.max(.1, brew.R), 0, 1)
		return brew.Base + brew.Rise * math.sqrt(1 - k * k)
	end
	return brew.Top
end

-- the season finale timeline (seconds from the claim): boil-up orbit, crane up the geyser, push in on the potion,
-- the potion flies to the player and bursts at Fly; Range = max distance from the cauldron to play it
CauldronFX.Finale = { Boil = 2.6, Crane = 4.8, Push = 7.8, Fly = 8.8, Total = 9.2, Range = 110 }

-- quadratic arc (candies, flying block)
function CauldronFX.Arc(a: Vector3, b: Vector3, h: number, t: number): Vector3
	local mid = (a + b) / 2 + V3(0, h, 0)
	local u = 1 - t
	return a * (u * u) + mid * (2 * u * t) + b * (t * t)
end

---------------------------------------------------------------------------------------------------------------------
-- runtime
---------------------------------------------------------------------------------------------------------------------
function CauldronFX.Start(ctx)
	local Shared, Layout, Bus, FX, Audio, State = ctx.Shared, ctx.Layout, ctx.Bus, ctx.FX, ctx.Audio, ctx.State
	local L = Shared.L
	local player = Players.LocalPlayer
	local rng = Random.new()
	local lay = Layout.Cauldron
	local folder = Instance.new("Folder")
	folder.Name = "Cauldron"
	folder.Parent = FX.Folder()

	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Layout.Zone.Center
	end

	-- brew geometry (BrewSurface when streamed in, else Layout)
	local brew = { Center = lay.Center + V3(0, lay.Height - .5, 0), R = lay.Radius * .8, Top = lay.Center.Y + lay.Height - .5,
		Base = lay.Center.Y + lay.Height - .7, Rise = .2, Dome = false, Part = nil, BaseCF = nil, BaseColor = C.Brew }
	local runes = {} -- index -> {Part, Color}
	local flames = {} -- builder fire-pit tongues (HwCauldronFlame): part -> {Size, CF, Phase}
	local staticBubbles = {} -- builder BrewBubble balls: part -> {Size, CF, Phase, Life}
	local steamPoints, runePoints, chainPoints = {}, {}, {}
	local function nearCauldron(pos: Vector3, r: number): boolean
		return (V3(pos.X, 0, pos.Z) - V3(lay.Center.X, 0, lay.Center.Z)).Magnitude <= r
	end
	local function setBrew(p: BasePart)
		local cf, s = p.CFrame, p.Size
		local mn, mx = V3(1e9, 1e9, 1e9), V3(-1e9, -1e9, -1e9)
		for _, a in ipairs({ -1, 1 }) do
			for _, b in ipairs({ -1, 1 }) do
				for _, c in ipairs({ -1, 1 }) do
					local q = cf * V3(s.X / 2 * a, s.Y / 2 * b, s.Z / 2 * c)
					mn = V3(math.min(mn.X, q.X), math.min(mn.Y, q.Y), math.min(mn.Z, q.Z))
					mx = V3(math.max(mx.X, q.X), math.max(mx.Y, q.Y), math.max(mx.Z, q.Z))
				end
			end
		end
		local mesh = p:FindFirstChildOfClass("SpecialMesh")
		local dome = (mesh ~= nil and mesh.MeshType == Enum.MeshType.Sphere) or (p:IsA("Part") and p.Shape == Enum.PartType.Ball)
		brew.Part = p
		brew.SeenAt = os.clock()
		brew.BaseCF = cf
		brew.BaseColor = p.Color
		brew.Center = V3((mn.X + mx.X) / 2, mx.Y, (mn.Z + mx.Z) / 2)
		brew.R = math.max(1, math.min(mx.X - mn.X, mx.Z - mn.Z) / 2 * .92)
		brew.Top = mx.Y
		brew.Dome = dome
		brew.Base = dome and (mn.Y + mx.Y) / 2 or mx.Y
		brew.Rise = mx.Y - brew.Base
	end
	local function onAdded(inst: Instance)
		if inst:IsA("BasePart") then
			if inst.Name == "BrewSurface" and nearCauldron(inst.CFrame.Position, 20) then
				setBrew(inst)
			elseif inst:GetAttribute("HwCauldronFlame") == true then
				flames[inst] = { Size = inst.Size, CF = inst.CFrame, Phase = rng:NextNumber(0, 50) }
			elseif inst.Name == "BrewBubble" and nearCauldron(inst.CFrame.Position, 12) then
				staticBubbles[inst] = { Size = inst.Size, CF = inst.CFrame, Phase = rng:NextNumber(0, 10), Life = rng:NextNumber(2.2, 4) }
			else
				local i = tonumber(string.match(inst.Name, "^Rune(%d)$"))
				if i and nearCauldron(inst.CFrame.Position, 26) then
					runes[i] = { Part = inst, Color = inst.Color }
				end
			end
		elseif inst:IsA("Attachment") then
			local n = inst.Name
			if (n == "SteamPoint" or n == "RunePoint" or n == "ChainPoint") and nearCauldron(attPos(inst), 26) then
				if n == "SteamPoint" then
					steamPoints[inst] = true
				elseif n == "RunePoint" then
					runePoints[inst] = true
				else
					chainPoints[inst] = true
				end
			end
		end
	end
	task.spawn(function()
		local yard = nil
		while not yard do
			local d = workspace:FindFirstChild("DOGROTS_District")
			yard = d and d:FindFirstChild("38_DeadYard")
			if not yard then
				task.wait(1)
			end
		end
		yard.DescendantAdded:Connect(onAdded)
		yard.DescendantRemoving:Connect(function(inst)
			if inst == brew.Part then
				brew.Part = nil
			end
			flames[inst :: any] = nil
			staticBubbles[inst :: any] = nil
			steamPoints[inst :: any] = nil
			runePoints[inst :: any] = nil
			chainPoints[inst :: any] = nil
		end)
		for i, inst in ipairs(yard:GetDescendants()) do
			onAdded(inst)
			if i % 4000 == 0 then
				task.wait()
			end
		end
	end)

	local function myLevel(): number
		local v = State.View
		local c = type(v) == "table" and v.Cauldron
		return type(c) == "table" and tonumber(c.Level) or 1
	end

	-- quality
	local Q = { Particles = 1, Quality = "High", Near = false, Close = false }
	local function refresh()
		Q.Quality = Shared.Quality()
		Q.Particles = FX.Budget("Particles")
		local d = (camPos() - lay.Center).Magnitude
		Q.Near = Shared.Enabled() and Ambient.ZoneDistance(Layout, camPos()) < 260 and d < 300
		Q.Close = d < 130
	end
	refresh()

	-------------------------------------------------------------------------------------------------------------
	-- emitters (client parts at the markers)
	-------------------------------------------------------------------------------------------------------------
	local function emitterAt(name: string, pos: Vector3, size: Vector3?): (BasePart, ParticleEmitter)
		local p = FX.Part({ Name = name, Size = size or V3(.4, .4, .4), Transparency = 1, CFrame = CFrame.new(pos), Parent = folder })
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.Parent = p
		return p, e
	end
	-- steam: one emitter per SteamPoint (fallback: 3 around the brew)
	local steam = {}
	local function buildSteam()
		for _, s in ipairs(steam) do
			s.Part:Destroy()
		end
		table.clear(steam)
		local pts = {}
		for a in pairs(steamPoints) do
			if a.Parent then
				table.insert(pts, attPos(a))
			end
		end
		if #pts == 0 then
			for k = 0, 2 do
				local a = k / 3 * math.pi * 2
				table.insert(pts, brew.Center + V3(math.cos(a) * brew.R * .45, .3, math.sin(a) * brew.R * .45))
			end
		end
		for _, pos in ipairs(pts) do
			local p, e = emitterAt("HwSteam", pos)
			e.Texture = FX.Textures.Smoke
			e.Color = ColorSequence.new(RGB(170, 255, 180), RGB(120, 110, 160))
			e.LightEmission = .25
			e.LightInfluence = .3
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(.5, 4), NumberSequenceKeypoint.new(1, 6) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.15, .62), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(2.6, 4.4)
			e.Speed = NumberRange.new(2, 3.6)
			e.SpreadAngle = Vector2.new(14, 14)
			e.EmissionDirection = Enum.NormalId.Top
			e.Acceleration = V3(.3, 1.1, 0)
			e.Drag = .6
			e.RotSpeed = NumberRange.new(-25, 25)
			e.Rotation = NumberRange.new(0, 360)
			table.insert(steam, { Part = p, E = e })
		end
	end
	-- green fire under the pot
	local fireP, fire = emitterAt("HwCauldronFire", lay.Center + V3(0, .6, 0), V3(lay.Radius * 1.1, .2, lay.Radius * 1.1))
	fire.Texture = FX.Textures.Fire
	fire.Color = ColorSequence.new(RGB(170, 255, 120), RGB(40, 170, 70))
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .3), NumberSequenceKeypoint.new(.6, .5), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(.45, .8)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.SpreadAngle = Vector2.new(8, 8)
	fire.Shape = Enum.ParticleEmitterShape.Box
	fire.RotSpeed = NumberRange.new(-60, 60)
	fire.Rotation = NumberRange.new(0, 360)
	-- surface sparkles
	local sparkP, spark = emitterAt("HwBrewSparkle", brew.Center, V3(brew.R * 1.4, .2, brew.R * 1.4))
	spark.Texture = FX.Textures.Sparkle
	spark.Color = ColorSequence.new(RGB(220, 255, 170), RGB(120, 255, 110))
	spark.LightEmission = 1
	spark.LightInfluence = 0
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.3, .3), NumberSequenceKeypoint.new(1, 0) })
	spark.Lifetime = NumberRange.new(.6, 1.2)
	spark.Speed = NumberRange.new(1, 2.5)
	spark.EmissionDirection = Enum.NormalId.Top
	spark.SpreadAngle = Vector2.new(25, 25)
	spark.Shape = Enum.ParticleEmitterShape.Box
	-- the brew light
	local lightP = FX.Part({ Name = "HwBrewLight", Size = V3(.2, .2, .2), Transparency = 1, CFrame = CFrame.new(brew.Center + V3(0, 2.5, 0)), Parent = folder })
	local light = Instance.new("PointLight")
	light.Color = C.Brew
	light.Shadows = false
	light.Brightness = 0
	light.Range = 18
	light.Parent = lightP

	-------------------------------------------------------------------------------------------------------------
	-- state shared by idle + events
	-------------------------------------------------------------------------------------------------------------
	local surge = 0 -- 0..1 boiling surge (trick / treat / claim)
	local surgeTarget = 0
	local flash = 0 -- rune / light flash
	local actors = {}
	local function actor(fn: (number, number) -> boolean)
		table.insert(actors, { Fn = fn, T0 = os.clock() })
	end

	-- bubbles (pooled balls on the brew surface)
	local bubbles = {}
	local bubbleAcc = 0
	local function spawnBubble(prof)
		if #bubbles >= (Q.Quality == "Low" and 6 or 16) then
			return
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local d = math.sqrt(rng:NextNumber()) * brew.R * .85
		local pos = V3(brew.Center.X + math.cos(a) * d, 0, brew.Center.Z + math.sin(a) * d)
		local y = CauldronFX.SurfaceY(brew, d)
		local size = prof.BubbleSize * rng:NextNumber(.45, 1.1) * (1 + surge * .5)
		local p = FX.Part({ Name = "HwBubble", Shape = Enum.PartType.Ball, Size = V3(.05, .05, .05), Color = C.BrewHot:Lerp(C.Brew, rng:NextNumber(0, .6)),
			Transparency = .3, CFrame = CFrame.new(pos.X, y, pos.Z), Parent = folder })
		table.insert(bubbles, { Part = p, X = pos.X, Z = pos.Z, Y = y, Size = size, T = 0, Life = rng:NextNumber(.55, 1.25) })
	end
	local function stepBubbles(dt: number, prof)
		bubbleAcc += dt * prof.Bubbles * (1 + surge * 3) * (Q.Quality == "Low" and .45 or Q.Quality == "Medium" and .75 or 1)
		while bubbleAcc >= 1 do
			bubbleAcc -= 1
			spawnBubble(prof)
		end
		for i = #bubbles, 1, -1 do
			local b = bubbles[i]
			b.T += dt
			local k = b.T / b.Life
			if k >= 1 then
				if Q.Quality == "High" and rng:NextNumber() < .35 then
					FX.Burst(V3(b.X, b.Y + b.Size * .4, b.Z), { Color = C.BrewHot, Count = 4, Speed = { 2, 4 }, Spread = 60, Direction = V3(0, 1, 0),
						Lifetime = { .25, .45 }, Size = { .18, .25, 0 }, Acceleration = V3(0, -14, 0) })
				end
				b.Part:Destroy()
				table.remove(bubbles, i)
			else
				local grow = k < .8 and smooth(k / .8) or 1 + (k - .8) / .2 * .3
				local s = b.Size * grow
				b.Part.Size = V3(s, s * (1 - .15 * math.sin(b.T * 14)), s)
				b.Part.CFrame = CFrame.new(b.X, b.Y + s * .25, b.Z)
				b.Part.Transparency = k < .8 and .3 or .3 + .7 * (k - .8) / .2
			end
		end
	end

	-- faces in the smoke
	local faces = {}
	local nextFace = os.clock() + rng:NextNumber(6, 12)
	local function spawnFace()
		local rig = Models.SmokeFace(folder, { Style = rng:NextInteger(1, 3) })
		rig:SetFade(1)
		local a = rng:NextNumber(0, math.pi * 2)
		local off = V3(math.cos(a) * brew.R * .3, 0, math.sin(a) * brew.R * .3)
		table.insert(faces, { Rig = rig, Start = brew.Center + off + V3(0, 2.6, 0), T = 0, Dur = rng:NextNumber(4, 5.5), Drift = V3(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)),
			Scale = 1, Whisper = rng:NextNumber() < .45 })
	end
	local function stepFaces(dt: number)
		for i = #faces, 1, -1 do
			local f = faces[i]
			f.T += dt
			local k = f.T / f.Dur
			if k >= 1 then
				FX.Smoke(f.Rig.Root.Position, C.Smoke, 3, 1.4)
				f.Rig:Destroy()
				table.remove(faces, i)
			else
				local pos = f.Start + V3(0, 3.4 * smooth(k), 0) + f.Drift * k
				local cam = camPos()
				local to = cam - pos
				local yaw = math.atan2(-to.X, -to.Z)
				local want = .9 + .5 * k
				f.Rig:SetScale(want / f.Rig.Scale)
				local wail = envelope((k - .25) / .5, .3, .4)
				f.Rig:Update(CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * ang(math.sin(f.T * 1.3) * 6, 0, math.sin(f.T) * 8), Models.SmokeFacePose(wail, f.T))
				f.Rig:SetFade(1 - .95 * envelope(k, .28, .3))
				if f.Whisper and k > .35 then
					f.Whisper = false
					Audio.Play("Whisper", pos, { Volume = .6 })
				end
			end
		end
	end

	-- orbiting wisps (L4-L5)
	local wisps = {}
	local function stepWisps(dt: number, prof, lvl: number)
		local want = Q.Quality == "Low" and math.min(1, prof.Wisps) or prof.Wisps
		while #wisps < want do
			local k = #wisps
			local col = (lvl >= 5 and k % 2 == 1) and RGB(200, 140, 255) or RGB(150, 255, 150)
			local rig = Ambient.Models.Wisp(folder, { Color = col })
			table.insert(wisps, { Rig = rig, Phase = k / math.max(1, want) * math.pi * 2, Dir = k % 2 == 0 and 1 or -1, H = 1.2 + (k % 3) * .9, T = 0 })
		end
		while #wisps > want do
			table.remove(wisps).Rig:Destroy()
		end
		for _, w in ipairs(wisps) do
			w.T += dt
			local a = w.Phase + w.T * .75 * w.Dir
			local rr = brew.R + 2.4 + math.sin(w.T * .9 + w.Phase) * .6
			local p = brew.Center + V3(math.cos(a) * rr, w.H + math.sin(w.T * 1.7 + w.Phase) * .5, math.sin(a) * rr)
			w.Rig:Update(CFrame.new(p))
			w.Rig:SetFade(.05 + .1 * math.sin(w.T * 5))
		end
	end

	-- runes
	local function stepRunes(now: number, prof, lvl: number)
		for i = 1, 8 do
			local r = runes[i]
			if r and r.Part.Parent then
				local lit = i <= prof.Runes
				local col
				if lit then
					local pulse = .5 + .5 * math.sin(now * 2.2 + i * .8)
					local hot = lvl >= 5 and (i % 2 == 0 and RGB(150, 255, 140) or C.RuneHot) or C.RuneHot
					col = C.Rune:Lerp(hot, pulse * .6 + flash * .4)
				else
					col = r.Color:Lerp(RGB(20, 12, 30), .45):Lerp(C.RuneHot, flash * .5)
				end
				r.Part.Color = col
			end
		end
	end

	-- own short chains when the builder has ChainPoints but no chain model hangs there
	local ownChains = nil
	local function ensureChains()
		if ownChains then
			return
		end
		local pts = {}
		for a in pairs(chainPoints) do
			if a.Parent then
				table.insert(pts, a)
			end
		end
		if #pts == 0 then
			return
		end
		local yard = workspace:FindFirstChild("DOGROTS_District")
		yard = yard and yard:FindFirstChild("38_DeadYard")
		local hasChains = false
		if yard then
			for _, d in ipairs(yard:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "ChainLink" then
					for _, a in ipairs(pts) do
						if (d.CFrame.Position - attPos(a)).Magnitude < 3 then
							hasChains = true
							break
						end
					end
				end
				if hasChains then
					break
				end
			end
		end
		ownChains = {}
		if hasChains then
			return
		end
		for k, a in ipairs(pts) do
			if k > 6 then
				break
			end
			local rig = Rig.new("HwCauldronChain", folder)
			local n = 7
			for j = 1, n do
				rig:Part("Root", V3(.14, .32, .5), at(0, -(j - .5) * .42, 0) * (j % 2 == 0 and ang(0, 90, 0) or IDENT), RGB(58, 58, 66),
					Enum.Material.CorrodedMetal, { Name = "Link" })
			end
			rig:Part("Root", V3(.42, .38, .42), at(0, -n * .42 - .2, 0), RGB(226, 216, 190), Enum.Material.SmoothPlastic, { Mesh = "Sphere", Name = "Charm" })
			rig:Part("Root", V3(.08, .08, .05), at(-.08, -n * .42 - .18, -.2), RGB(150, 255, 120), Enum.Material.Neon, { Shape = "Ball", Name = "CharmEye" })
			rig:Part("Root", V3(.08, .08, .05), at(.08, -n * .42 - .18, -.2), RGB(150, 255, 120), Enum.Material.Neon, { Shape = "Ball", Name = "CharmEye" })
			table.insert(ownChains, { Rig = rig, Att = a, Angle = 0, Vel = 0, Phase = rng:NextNumber(0, 10), Axis = rng:NextNumber(0, math.pi) })
		end
	end
	local function kickChains(strength: number)
		Bus.Fire("ChainKick", { Position = brew.Center, Radius = 16, Strength = strength })
		for _, c in ipairs(ownChains or {}) do
			c.Vel += strength * rng:NextNumber(.6, 1.1) * (rng:NextNumber() < .5 and -1 or 1)
		end
	end
	local function stepOwnChains(dt: number, now: number)
		for _, c in ipairs(ownChains or {}) do
			if c.Att.Parent then
				local w = 2.6
				c.Vel += (-w * w * c.Angle - 2 * .12 * w * c.Vel) * dt
				c.Angle = math.clamp(c.Angle + c.Vel * dt, -.7, .7)
				local wind = .06 * math.sin(now * 1.1 + c.Phase)
				c.Rig:Update(CFrame.new(attPos(c.Att)) * CFrame.Angles(0, c.Axis, 0) * CFrame.Angles(c.Angle + wind, 0, 0))
			end
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- events
	-------------------------------------------------------------------------------------------------------------
	local Pumpkin = nil
	local function pumpkinModels()
		if Pumpkin == nil then
			Pumpkin = false
			local folderM = RS:FindFirstChild("Halloween")
			folderM = folderM and folderM:FindFirstChild("Models")
			local mod = folderM and folderM:FindFirstChild("Pumpkin")
			if mod then
				local ok, m = pcall(require, mod)
				if ok and type(m) == "table" then
					Pumpkin = m
				end
			end
		end
		return Pumpkin or nil
	end
	-- a flying object handle: {Set(cf, scale), Fade(f), Destroy()}
	local function prepModel(model: Model, want: number)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		local base = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				base[d] = d.Transparency
			end
		end
		local size = 1
		local ok, _, ext = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and typeof(ext) == "Vector3" then
			size = math.max(ext.X, ext.Y, ext.Z)
		end
		local okS, own = pcall(function()
			return model:GetScale()
		end)
		own = (okS and type(own) == "number" and own > 0) and own or 1
		-- ScaleTo is absolute: unit = the scale factor at which the model's largest extent is `want` studs
		local unit = own * want / math.max(.1, size)
		model.Parent = folder
		local scale = -1
		return {
			Size = size,
			Set = function(cf: CFrame, s: number)
				if math.abs(s - scale) > .01 then
					pcall(function()
						model:ScaleTo(math.max(.02, unit * s))
					end)
					scale = s
				end
				model:PivotTo(cf)
			end,
			Fade = function(f: number)
				for p, t in pairs(base) do
					if p.Parent and t < 1 then
						p.Transparency = t + (1 - t) * f
					end
				end
			end,
			Destroy = function()
				model:Destroy()
			end,
		}
	end
	local function makeBlock(tier: string)
		local P = pumpkinModels()
		if P and type(P.Block) == "function" then
			local ok, model = pcall(P.Block, tier, { Lit = true })
			if ok and typeof(model) == "Instance" and model:IsA("Model") then
				return prepModel(model, 3.2) -- pivot = body centre
			end
		end
		local rig = Models.PumpkinBlock(folder, { Tier = tier })
		return {
			Set = function(cf: CFrame, s: number)
				if math.abs(s - rig.Scale) > .01 then
					rig:SetScale(s / rig.Scale)
				end
				rig:Update(cf * at(0, -1.3 * s, 0))
			end,
			Fade = function(f: number)
				rig:SetFade(f)
			end,
			Destroy = function()
				rig:Destroy()
			end,
		}
	end
	local candyColors = { RGB(255, 128, 24), RGB(122, 62, 200), RGB(120, 255, 110), RGB(255, 92, 170), RGB(255, 220, 60) }
	local function makeCandy()
		local P = pumpkinModels()
		local col = candyColors[rng:NextInteger(1, #candyColors)]
		if P and type(P.Candy) == "function" then
			local ok, model = pcall(P.Candy, col)
			if ok and typeof(model) == "Instance" and model:IsA("Model") then
				return prepModel(model, 1.0)
			end
		end
		local rig = Ambient.Models.Candy(folder, { Color = col })
		return {
			Set = function(cf: CFrame, s: number)
				if math.abs(s - rig.Scale) > .01 then
					rig:SetScale(s / rig.Scale)
				end
				rig:Update(cf)
			end,
			Fade = function(f: number)
				rig:SetFade(f)
			end,
			Destroy = function()
				rig:Destroy()
			end,
		}
	end

	local function playerRoot(uid: any): BasePart?
		local pl = Players:GetPlayerByUserId(tonumber(uid) or 0)
		local ch = pl and pl.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		return (root and root:IsA("BasePart")) and root or nil
	end
	local function fromPos(uid: any): Vector3
		local root = playerRoot(uid)
		if root and (root.CFrame.Position - lay.Center).Magnitude < 60 then
			return root.CFrame.Position + V3(0, 1.2, 0)
		end
		return lay.Prompt + V3(0, 1.5, 0)
	end
	local mouth = function(): Vector3
		return brew.Center + V3(0, .4, 0)
	end

	-- candies arc from `from` into the pot; returns the time of the last splash
	local function candiesIn(uid: any, n: number, spread: number): number
		local last = 0
		for k = 1, n do
			local delay = (k - 1) * spread
			local dur = rng:NextNumber(.55, .75)
			last = math.max(last, delay + dur)
			local c = makeCandy()
			c.Fade(1)
			local spin = V3(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
			local splashed = false
			local jitter = V3(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * brew.R * .4
			actor(function(t)
				local k2 = (t - delay) / dur
				if k2 < 0 then
					return true
				end
				local a = fromPos(uid)
				local b = mouth() + jitter
				local p = CauldronFX.Arc(a, b, 4 + (a - b).Magnitude * .18, math.min(k2, 1))
				c.Set(CFrame.new(p) * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t), 1)
				c.Fade(k2 < .12 and 1 - k2 / .12 or 0)
				if k2 >= 1 then
					if not splashed then
						splashed = true
						Audio.Play("CandyDrop", b, { Pitch = rng:NextNumber(.9, 1.2) })
						FX.Burst(b, { Color = C.BrewHot, Color2 = C.Brew, Count = 6, Speed = { 3, 6 }, Spread = 40, Direction = V3(0, 1, 0),
							Lifetime = { .3, .55 }, Size = { .25, .35, 0 }, Acceleration = V3(0, -18, 0) })
						surgeTarget = math.min(1, surgeTarget + .12)
					end
					c.Destroy()
					return false
				end
				return true
			end)
		end
		return last
	end

	local function trick(d)
		if (camPos() - lay.Center).Magnitude > 200 then
			return
		end
		local uid = d.UserId
		local isMe = tonumber(uid) == player.UserId
		local cursed = d.Tier == "Cursed Pumpkin"
		local low = Q.Quality == "Low"
		local landAt = candiesIn(uid, low and 4 or 8, .09)
		-- boil
		task.delay(landAt, function()
			surgeTarget = 1
			Audio.Play("CauldronSplash", brew.Center)
			kickChains(1.2)
			for _, s in ipairs(steam) do
				s.E:Emit(math.floor(6 * Q.Particles + .5))
			end
		end)
		-- flash + the block
		task.delay(landAt + 1.3, function()
			flash = 1
			local col = cursed and C.CursedGlow or C.BrewHot
			Audio.Play("CauldronFlash", brew.Center)
			FX.Light(brew.Center + V3(0, 3, 0), col, 34, 5, 1)
			FX.Shockwave(V3(lay.Center.X, lay.Center.Y + .25, lay.Center.Z), col, 16, .8)
			FX.Burst(brew.Center + V3(0, 1, 0), { Color = col, Color2 = RGB(255, 255, 255), Count = 30, Speed = { 10, 22 }, Spread = 40,
				Direction = V3(0, 1, 0), Lifetime = { .5, 1 }, Size = { .5, .9, 0 }, Acceleration = V3(0, -20, 0) })
			Bus.Fire("LanternFlare", { Position = lay.Center, Radius = 26, Strength = 1.6, Seconds = 1.2, Color = col })
			if isMe then
				FX.Flash(col, .25, .35)
				FX.Shake(.35, .35)
			elseif (camPos() - lay.Center).Magnitude < 40 then
				FX.Shake(.15, .25)
			end
			local block = makeBlock(cursed and "Cursed Pumpkin" or "Pumpkin")
			local spinDir = rng:NextNumber() < .5 and -1 or 1
			local landed = false
			local fromP = brew.Center + V3(0, 1, 0)
			Audio.Play("PumpkinShake", fromP, { Delay = .05 })
			actor(function(t)
				local target = fromPos(uid)
				local ground = V3(target.X, lay.Center.Y + .3, target.Z)
				local dir = V3(lay.Center.X - ground.X, 0, lay.Center.Z - ground.Z)
				local landP = ground + (dir.Magnitude > .1 and dir.Unit * 2.4 or V3(0, 0, -2.4)) + V3(0, 1.3, 0)
				local fly = 1.0
				if t < fly then
					local k = t / fly
					local p = CauldronFX.Arc(fromP, landP, 9 + (fromP - landP).Magnitude * .12, k)
					local s = .35 + .65 * smooth(k / .35)
					block.Set(CFrame.new(p) * CFrame.Angles(t * 7, t * 9 * spinDir, t * 3), s)
					block.Fade(0)
				else
					if not landed then
						landed = true
						Audio.Play("BlockPop", landP)
						FX.Ring(V3(landP.X, lay.Center.Y + .3, landP.Z), cursed and C.CursedGlow or Shared.Color("Pumpkin"), 6, .5)
						FX.Burst(landP, { Color = Shared.Color("Gold"), Count = 16, Speed = { 4, 9 }, Lifetime = { .4, .8 }, Size = { .3, .5, 0 } })
						if isMe then
							FX.Popup(landP + V3(0, 2.5, 0), (cursed and L("CURSED PUMPKIN", "ПРОКЛЯТАЯ ТЫКВА") or L("PUMPKIN BLOCK", "ТЫКВЕННЫЙ БЛОК")) .. "!",
								cursed and C.CursedGlow or Shared.Color("Pumpkin"), true)
						end
					end
					local k = t - fly
					local bounce = math.abs(math.sin(math.min(k, .5) / .5 * math.pi)) * (1 - math.min(k, .5) * 2) * .8
					local into = smooth((k - .9) / .45)
					local p = landP + V3(0, bounce, 0)
					local root = playerRoot(uid)
					if root and into > 0 then
						p = p:Lerp(root.CFrame.Position + V3(0, .8, 0), into)
					end
					block.Set(CFrame.new(p) * CFrame.Angles(0, (t * 2 + into * 6) * spinDir, 0), 1 - .8 * into)
					block.Fade(smooth((k - 1.15) / .2))
					if k > .9 and not block.Sparkled then
						block.Sparkled = true
						Audio.Play("Sparkle", p)
					end
					if k > 1.4 then
						FX.Burst(p, { Color = Shared.Color("Gold"), Color2 = Shared.Color("Pumpkin"), Count = 12, Speed = { 3, 6 }, Lifetime = { .3, .6 },
							Size = { .3, .5, 0 } })
						block.Destroy()
						return false
					end
				end
				return true
			end)
		end)
		task.delay(landAt + 3.6, function()
			surgeTarget = 0
		end)
	end

	local function treat(d)
		if (camPos() - lay.Center).Magnitude > 200 then
			return
		end
		local landAt = candiesIn(d.UserId, Q.Quality == "Low" and 2 or 3, .12)
		task.delay(landAt, function()
			surgeTarget = math.max(surgeTarget, .45)
			flash = math.max(flash, .4)
			FX.Burst(brew.Center + V3(0, 1, 0), { Color = C.RuneHot, Color2 = C.BrewHot, Count = 12, Speed = { 3, 7 }, Spread = 50, Direction = V3(0, 1, 0),
				Lifetime = { .5, .9 }, Size = { .3, .5, 0 } })
			Audio.Play("Sparkle", brew.Center)
		end)
		task.delay(landAt + 1.6, function()
			surgeTarget = 0
		end)
	end

	local function levelUp(d)
		if (camPos() - lay.Center).Magnitude > 220 then
			return
		end
		flash = 1
		surgeTarget = math.max(surgeTarget, .6)
		Audio.Play("CauldronLevelUp", brew.Center)
		local ground = V3(lay.Center.X, lay.Center.Y + .25, lay.Center.Z)
		FX.Ring(ground, C.Rune, lay.PlazaRadius, 1.1, { Thickness = .25 })
		task.delay(.15, FX.Ring, ground, C.RuneHot, lay.PlazaRadius * .7, .9)
		FX.Beam(brew.Center, C.Rune, 26, 2.2)
		for _, s in ipairs(steam) do
			s.E:Emit(math.floor(5 * Q.Particles + .5))
		end
		for k = 1, 8 do
			local r = runes[k]
			if r and r.Part.Parent then
				FX.Burst(r.Part.CFrame.Position + V3(0, .6, 0), { Color = C.RuneHot, Count = 6, Speed = { 2, 5 }, Spread = 30, Direction = V3(0, 1, 0),
					Lifetime = { .5, .9 }, Size = { .25, .4, 0 } })
			end
		end
		Bus.Fire("LanternFlare", { Position = lay.Center, Radius = 26, Strength = 1.2, Seconds = 1.6, Color = C.RuneHot })
		kickChains(.8)
		if tonumber(d.UserId) == player.UserId then
			local lvl = tonumber(d.Level) or myLevel()
			local row = Shared.CauldronLevel(lvl)
			FX.Popup(brew.Center + V3(0, 6, 0), L("CAULDRON LEVEL ", "КОТЁЛ · УРОВЕНЬ ") .. lvl .. (row and (" · " .. Shared.T(row.Name)) or ""), C.RuneHot, true)
		end
		task.delay(2, function()
			surgeTarget = 0
		end)
	end

	local finaleRunning: () -> boolean -- set by the finale below
	-- the claimer's own CLAIM request in flight (Bus "CauldronClaimPending" from the window, before the request): the public
	-- Claim signal can arrive before the reply, so the claimer's geyser waits for CauldronClaimLocal to decide (finale or not)
	local claimPendingAt = -math.huge
	local deferredClaim = nil
	local CLAIM_WAIT = 8
	local function claim(d)
		if (camPos() - lay.Center).Magnitude > 220 then
			return
		end
		local isMe = tonumber(d.UserId) == player.UserId
		if isMe and finaleRunning and finaleRunning() then
			return -- the claimer's own finale plays this moment (bigger)
		end
		if isMe and os.clock() - claimPendingAt < CLAIM_WAIT then
			deferredClaim = d
			task.delay(CLAIM_WAIT, function()
				if deferredClaim == d then -- the reply never came: play the public moment after all
					deferredClaim = nil
					claimPendingAt = -math.huge
					claim(d)
				end
			end)
			return
		end
		surgeTarget = 1
		flash = 1
		Audio.Play("CauldronFlash", brew.Center)
		Audio.Play("CauldronLevelUp", brew.Center, { Delay = .2 })
		FX.Beam(brew.Center, Shared.Color("Gold"), 34, 3.5)
		kickChains(1.4)
		if isMe then
			FX.Flash(Shared.Color("Gold"), .25, .5)
		end
		-- geyser: a column of brew shoots up, holds, collapses (begin -> peak -> fade)
		local segs = {}
		local n = Q.Quality == "Low" and 4 or 7
		for k = 1, n do
			local p = FX.Part({ Name = "HwGeyser", Shape = Enum.PartType.Ball, Size = V3(.1, .1, .1), Color = C.BrewHot:Lerp(C.Brew, k / n),
				Transparency = .15, CFrame = CFrame.new(brew.Center), Parent = folder })
			table.insert(segs, p)
		end
		local height = 16
		local sprayed = false
		actor(function(t)
			local rise = smooth(t / .45)
			local fall = smooth((t - 1.9) / .6)
			local hgt = height * rise * (1 - fall)
			for k, p in ipairs(segs) do
				local f = (k - 1) / (n - 1)
				local w = (1.9 - f * 1.1) * (1 - fall * .6) * (1 + .12 * math.sin(t * 18 + k))
				p.Size = V3(w, w * 1.4, w)
				p.CFrame = CFrame.new(brew.Center + V3(math.sin(t * 7 + k) * .15, hgt * f, math.cos(t * 6 + k) * .15))
				p.Transparency = .15 + .85 * fall
			end
			if t > .45 and not sprayed then
				sprayed = true
				local top = brew.Center + V3(0, height, 0)
				FX.Burst(top, { Color = Shared.Color("Gold"), Color2 = C.BrewHot, Count = 36, Speed = { 8, 18 }, Lifetime = { .7, 1.4 },
					Size = { .4, .7, 0 }, Acceleration = V3(0, -22, 0) })
				FX.Debris(top, C.Brew, Enum.Material.Neon, 10, 20, { MaxSize = .5, Floor = lay.Center.Y + .3 })
				Audio.Play("CauldronSplash", brew.Center, { Pitch = .8 })
			end
			if t > 2.6 then
				for _, p in ipairs(segs) do
					p:Destroy()
				end
				surgeTarget = 0
				return false
			end
			return true
		end)
	end


	-------------------------------------------------------------------------------------------------------------
	-- THE BURIED MOON BREW: the season finale for the claimer (Bus "CauldronClaimLocal" from the Halloween window)
	-- ~9 s, three directed shots under letterbox bars and a brew-green (L5: moon-violet) grade:
	--   0.0  low orbit round the pot while the brew boils up (runes light one by one, chains swing, steam)
	--   2.6  crane up the geyser: the brew erupts, a moon beam falls into the pot, lanterns flare
	--   4.8  push in on THE BURIED MOON BREW potion forming in the geyser (part-built bottle, sparkles)
	--   7.8  the bottle flies to the player and bursts -> the reward card (d.Reveal)
	-- Any key / click / tap skips to the burst. ReducedMotion, far from the cauldron, no character or a busy camera
	-- (timing hits, a modal): no finale; the window shows the card at once. Everyone else sees the public Claim geyser.
	-------------------------------------------------------------------------------------------------------------
	local UserInputService = game:GetService("UserInputService")
	local finale = nil
	-- ignoreModal: the start check of a claim from the Halloween window (the window itself owns the modal count; it closes
	-- right after the finale accepts, before the per-frame check starts)
	local function finaleCameraLocked(ignoreModal: boolean?): boolean
		local ok, locked = pcall(function()
			local pg = player:FindFirstChildOfClass("PlayerGui")
			local main = pg and pg:FindFirstChild("ScreenGui")
			return main ~= nil and (main:GetAttribute("MiningActive") == true
				or (not ignoreModal and (tonumber(main:GetAttribute("ModalOwnerCount")) or 0) > 0))
		end)
		return ok and locked == true
	end
	local FIN = CauldronFX.Finale
	local function playFinale(d): boolean
		if finale or not Shared.Enabled() or Shared.ReducedMotion() then
			return false
		end
		local cam = workspace.CurrentCamera
		local root = playerRoot(player.UserId)
		if not cam or cam.CameraType ~= Enum.CameraType.Custom or not root then
			return false
		end
		if (root.CFrame.Position - lay.Center).Magnitude > FIN.Range or finaleCameraLocked(d.FromWindow == true) then
			return false
		end
		local level = math.clamp(tonumber(d.Level) or myLevel(), 1, 5)
		local brewCol = level >= 5 and RGB(200, 150, 255) or C.Brew
		local low = Q.Quality == "Low"
		local me = { T0 = os.clock(), Done = false }
		finale = me
		d.Handled = true
		d.Seconds = FIN.Total + 4
		local startCF = cam.CFrame
		local rootPos = root.CFrame.Position
		local a0 = math.atan2(rootPos.Z - lay.Center.Z, rootPos.X - lay.Center.X)
		-- the potion forms in the geyser top, then glides out in front of the pot (toward the player) to hover clear of the
		-- tripod / chains, where the push-in frames it with the cauldron behind it
		local formPos = brew.Center + V3(0, 9, 0)
		local flat = V3(math.cos(a0), 0, math.sin(a0))
		local bottlePos = brew.Center + flat * (brew.R + 3.5) + V3(0, 3.5, 0)
		local cleanup = {}
		-- letterbox + grade
		local gui = Instance.new("ScreenGui")
		gui.Name = "DOGROTS_HalloweenCinema"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 90
		gui:SetAttribute("NoTranslate", true)
		local bars = {}
		for i, y in ipairs({ 0, 1 }) do
			local b = Instance.new("Frame")
			b.Name = "Letterbox"
			b.BorderSizePixel = 0
			b.BackgroundColor3 = Color3.new(0, 0, 0)
			b.AnchorPoint = Vector2.new(0, y)
			b.Position = UDim2.fromScale(0, y)
			b.Size = UDim2.fromScale(1, 0)
			b.Parent = gui
			bars[i] = b
			FX.Tween(b, .45, { Size = UDim2.fromScale(1, .11) })
		end
		local skipL = Instance.new("TextLabel")
		skipL.Name = "Skip"
		skipL.BackgroundTransparency = 1
		skipL.FontFace = FX.Font
		skipL.TextColor3 = RGB(200, 190, 230)
		skipL.TextTransparency = 1
		skipL.TextScaled = true
		skipL.Text = L("TAP TO SKIP", "НАЖМИ, ЧТОБЫ ПРОПУСТИТЬ")
		skipL:SetAttribute("NoTranslate", true)
		skipL.AnchorPoint = Vector2.new(1, .5)
		skipL.Position = UDim2.new(1, -24, .5, 0)
		skipL.Size = UDim2.new(.4, 0, .32, 0)
		skipL.TextXAlignment = Enum.TextXAlignment.Right
		skipL.Parent = bars[2]
		task.delay(1, function()
			if skipL.Parent then
				FX.Tween(skipL, .4, { TextTransparency = .25 })
			end
		end)
		local titleL = skipL:Clone()
		titleL.Name = "Title"
		titleL.Text = L("THE BURIED MOON BREW", "ЗЕЛЬЕ ПОГРЕБЁННОЙ ЛУНЫ")
		titleL.TextColor3 = brewCol:Lerp(WHITE, .45)
		titleL.AnchorPoint = Vector2.new(.5, .5)
		titleL.Position = UDim2.fromScale(.5, .55)
		titleL.Size = UDim2.fromScale(.8, .5)
		titleL.TextXAlignment = Enum.TextXAlignment.Center
		titleL.Parent = bars[1]
		gui.Parent = player:WaitForChild("PlayerGui")
		table.insert(cleanup, gui)
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "DOGROTS_BrewGrade"
		grade.Parent = cam
		FX.Tween(grade, .5, { TintColor = level >= 5 and RGB(236, 222, 255) or RGB(222, 255, 228), Saturation = .18, Contrast = .1, Brightness = .02 })
		table.insert(cleanup, function()
			FX.Tween(grade, .6, { TintColor = WHITE, Saturation = 0, Contrast = 0, Brightness = 0 })
			task.delay(.65, function()
				grade:Destroy()
			end)
		end)
		local bubbles = Audio.Loop("CauldronBubbles", brew.Center + V3(0, 1, 0), { Volume = 1.4 })
		table.insert(cleanup, function()
			if bubbles then
				bubbles:Stop(1)
			end
		end)
		Audio.Play("BrewRise", brew.Center)
		-- the potion (hidden until it forms)
		local bottle = Models.PotionBottle(folder, { Brew = brewCol })
		bottle:SetFade(1)
		local bottleLight = FX.Part({ Name = "HwBottleLight", Size = V3(.2, .2, .2), Transparency = 1, CFrame = CFrame.new(bottlePos), Parent = folder })
		local bl = Instance.new("PointLight")
		bl.Color = brewCol
		bl.Range = 16
		bl.Brightness = 0
		bl.Shadows = false
		bl.Parent = bottleLight
		table.insert(cleanup, bottleLight)
		local sparkleE = Instance.new("ParticleEmitter")
		sparkleE.Texture = FX.Textures.Sparkle
		sparkleE.Color = ColorSequence.new(brewCol:Lerp(WHITE, .5), Shared.Color("Gold"))
		sparkleE.LightEmission = 1
		sparkleE.LightInfluence = 0
		sparkleE.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.3, .45), NumberSequenceKeypoint.new(1, 0) })
		sparkleE.Lifetime = NumberRange.new(.6, 1.1)
		sparkleE.Speed = NumberRange.new(1.5, 4)
		sparkleE.SpreadAngle = Vector2.new(180, 180)
		sparkleE.Rate = 0
		sparkleE.Parent = bottleLight
		local geyserParts = {}
		local fired = {}
		local function once(key: string, t: number, now: number, fn: () -> ())
			if not fired[key] and now >= t then
				fired[key] = true
				local ok, err = pcall(fn)
				if not ok then
					warn("CauldronFX finale " .. key .. ": " .. tostring(err))
				end
			end
		end
		local inputConn
		local function finish()
			if me.Done then
				return
			end
			me.Done = true
			if inputConn then
				inputConn:Disconnect()
			end
			RunService:UnbindFromRenderStep("DOGROTS_BrewFinale")
			if cam.CameraType == Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Custom
			end
			for _, b in ipairs(bars) do
				FX.Tween(b, .45, { Size = UDim2.fromScale(1, 0) })
			end
			FX.Tween(skipL, .3, { TextTransparency = 1 })
			FX.Tween(titleL, .3, { TextTransparency = 1 })
			sparkleE.Rate = 0
			for _, p in ipairs(geyserParts) do
				p:Destroy()
			end
			task.delay(.5, function()
				for i = #cleanup, 1, -1 do
					local x = cleanup[i]
					pcall(function()
						if typeof(x) == "Instance" then
							x:Destroy()
						else
							x()
						end
					end)
				end
			end)
			surgeTarget = 0
			if finale == me then
				finale = nil
			end
		end
		-- the burst at the player and the card (also the skip target)
		local function burst()
			if fired.Burst then
				return
			end
			fired.Burst = true
			local r2 = playerRoot(player.UserId)
			local at2 = (r2 and r2.CFrame.Position or rootPos) + V3(0, 1.4, 0)
			pcall(function()
				bottle:Destroy()
			end)
			FX.Burst(at2, { Color = brewCol, Color2 = Shared.Color("Gold"), Count = low and 18 or 40, Speed = { 6, 16 }, Lifetime = { .5, 1.1 },
				Size = { .4, .7, 0 }, Acceleration = V3(0, -14, 0) })
			FX.Ring(V3(at2.X, (r2 and r2.CFrame.Position.Y or rootPos.Y) - 2.6, at2.Z), brewCol, 9, .7, { Thickness = .3 })
			FX.Flash(brewCol:Lerp(WHITE, .4), .3, .45)
			Audio.Play("Claim")
			finish()
			if type(d.Reveal) == "function" then
				task.spawn(d.Reveal)
			elseif d.Rows then
				Bus.Fire("RewardReveal", { Title = L("THE BURIED MOON BREW", "ЗЕЛЬЕ ПОГРЕБЁННОЙ ЛУНЫ"), Rows = d.Rows })
			end
		end
		inputConn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp or os.clock() - me.T0 < .5 then
				return
			end
			local ty = input.UserInputType
			if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch or ty == Enum.UserInputType.Gamepad1 then
				burst()
			end
		end)
		local function look(from: Vector3, to: Vector3): CFrame
			return CFrame.lookAt(from, to)
		end
		task.delay(.2, function()
			if me.Done then
				return
			end
			cam.CameraType = Enum.CameraType.Scriptable
			RunService:BindToRenderStep("DOGROTS_BrewFinale", Enum.RenderPriority.Camera.Value + 1, function()
				if me.Done then
					return
				end
				if finaleCameraLocked() then
					burst() -- a timing session / modal took over: hand the camera straight back
					return
				end
				local t = os.clock() - me.T0
				local c = brew.Center
				-- events on the timeline
				once("Boil", 0, t, function()
					surgeTarget = .7
					kickChains(.9)
				end)
				for k = 1, 8 do
					once("Rune" .. k, .2 + k * .22, t, function()
						flash = math.max(flash, .6)
						local rn = runes[k]
						if rn and rn.Part.Parent and not low then
							FX.Burst(rn.Part.CFrame.Position + V3(0, .5, 0), { Color = C.RuneHot, Count = 5, Speed = { 2, 4 }, Spread = 25, Direction = V3(0, 1, 0),
								Lifetime = { .4, .8 }, Size = { .25, .35, 0 } })
						end
						Audio.Play("CandyTick", nil, { Pitch = .8 + k * .09, Volume = .6 })
					end)
				end
				once("Erupt", FIN.Boil + .2, t, function()
					surgeTarget = 1
					flash = 1
					Audio.Play("CauldronSplash", c)
					kickChains(1.6)
					for _, s in ipairs(steam) do
						s.E:Emit(math.floor(8 * Q.Particles + .5))
					end
					local n = low and 5 or 9
					for k = 1, n do
						local p = FX.Part({ Name = "HwFinaleGeyser", Shape = Enum.PartType.Ball, Size = V3(.1, .1, .1), Color = C.BrewHot:Lerp(brewCol, k / n),
							Transparency = .12, CFrame = CFrame.new(c), Parent = folder })
						table.insert(geyserParts, p)
					end
				end)
				once("Moon", FIN.Boil + .6, t, function()
					Audio.Play("CauldronFlash", c)
					FX.Beam(c, RGB(205, 190, 255), 90, 5)
					FX.Ring(V3(lay.Center.X, lay.Center.Y + .3, lay.Center.Z), brewCol, lay.PlazaRadius + 4, 1.2, { Thickness = .3 })
					FX.Light(c + V3(0, 4, 0), brewCol, 40, 6, 1.6)
					Bus.Fire("LanternFlare", { Position = lay.Center, Radius = 70, Strength = 2, Seconds = 2.4, Color = brewCol })
					FX.Shake(.25, .5)
				end)
				once("Form", FIN.Crane, t, function()
					Audio.Play("TreasureReveal", bottlePos)
					sparkleE.Rate = low and 8 or 22
					flash = 1
				end)
				once("Gold", FIN.Crane + .9, t, function()
					FX.Burst(bottlePos, { Color = Shared.Color("Gold"), Color2 = brewCol, Count = low and 14 or 30, Speed = { 6, 14 }, Lifetime = { .6, 1.2 },
						Size = { .35, .6, 0 }, Acceleration = V3(0, -10, 0) })
					Audio.Play("Sparkle", bottlePos)
				end)
				once("Fly", FIN.Push, t, function()
					Audio.Play("Teleport", bottlePos)
					sparkleE.Rate = 0
				end)
				-- geyser column: rises at the eruption, holds the bottle, sinks after it leaves
				local gk = (t - FIN.Boil - .2)
				if #geyserParts > 0 then
					local rise = smooth(gk / .5)
					local fall = smooth((t - FIN.Push - .2) / .8)
					local hgt = 10 * rise * (1 - fall)
					for k, p in ipairs(geyserParts) do
						local f = (k - 1) / (#geyserParts - 1)
						local w = (2.2 - f * 1.2) * (1 - fall * .7) * (1 + .12 * math.sin(t * 16 + k))
						p.Size = V3(w, w * 1.5, w)
						p.CFrame = CFrame.new(c + V3(math.sin(t * 7 + k) * .18, hgt * f, math.cos(t * 6 + k) * .18))
						p.Transparency = .12 + .88 * fall
					end
				end
				-- the bottle: forms in the geyser top, turns, then flies to the player
				local form = smooth((t - FIN.Crane) / 1.4)
				if t >= FIN.Crane and not fired.Burst then
					local spin = (t - FIN.Crane) * 1.6
					local glide = smooth((t - FIN.Crane - .6) / 1.1)
					local pos = formPos:Lerp(bottlePos, glide) + V3(0, math.sin(t * 2.2) * .25, 0)
					local scale = .3 + .7 * form
					if t >= FIN.Push then
						local k = math.clamp((t - FIN.Push) / (FIN.Fly - FIN.Push), 0, 1)
						local r3 = playerRoot(player.UserId)
						local dest = (r3 and r3.CFrame.Position or rootPos) + V3(0, 1.4, 0)
						pos = CauldronFX.Arc(bottlePos, dest, 5, smooth(k))
						scale = 1 - .7 * k
						spin += k * 8
					end
					if math.abs(scale - bottle.Scale) > .02 then
						bottle:SetScale(scale / bottle.Scale)
					end
					bottle:Update(CFrame.new(pos) * CFrame.Angles(0, spin, math.sin(t * 1.7) * .08) * CFrame.new(0, -2.2 * bottle.Scale, 0),
						{ Liquid = CFrame.new(0, math.sin(t * 5) * .04, 0) })
					bottle:SetFade(1 - form)
					bottleLight.CFrame = CFrame.new(pos)
					bl.Brightness = 3 * form
				end
				if t >= FIN.Fly then
					burst()
					return
				end
				-- the camera: three shots, then ease back to where the player looked
				local camCF
				if t < FIN.Boil then
					local k = smooth(t / FIN.Boil)
					local a = a0 + 1.2 * k
					local rr = 15 - 3 * k
					local eye = V3(lay.Center.X + math.cos(a) * rr, lay.Center.Y + 2.6 + k, lay.Center.Z + math.sin(a) * rr)
					camCF = look(eye, c + V3(0, .8 + surge * 1.5, 0))
				elseif t < FIN.Crane then
					local k = smooth((t - FIN.Boil) / (FIN.Crane - FIN.Boil))
					local a = a0 + 1.2 + .3 * k
					local rr = 12 + 6 * k
					local eye = V3(lay.Center.X + math.cos(a) * rr, c.Y + 1 + 14 * k, lay.Center.Z + math.sin(a) * rr)
					camCF = look(eye, c + V3(0, 3 + 7 * k, 0))
				elseif t < FIN.Push then
					-- from the player's side, off-axis: the potion in front, the boiling cauldron behind it
					local k = smooth((t - FIN.Crane) / (FIN.Push - FIN.Crane))
					local a = a0 + .6 - .3 * k
					local rr = 14 - 7 * k
					local focus = formPos:Lerp(bottlePos, smooth((t - FIN.Crane - .6) / 1.1))
					local eye = bottlePos + V3(math.cos(a) * rr, 2.6 - 1.8 * k, math.sin(a) * rr)
					camCF = look(eye, focus + V3(0, .2, 0))
				else
					local k = smooth((t - FIN.Push) / (FIN.Fly - FIN.Push))
					local a = a0 + .3
					local shot = look(bottlePos + V3(math.cos(a) * 7, .8, math.sin(a) * 7), bottlePos + V3(0, .2, 0))
					camCF = shot:Lerp(startCF, k)
				end
				cam.CFrame = camCF
			end)
		end)
		-- hard ceiling: never leave the camera scripted
		task.delay(FIN.Total + 3, function()
			if not me.Done then
				burst()
			end
		end)
		return true
	end
	CauldronFX.PlayFinale = playFinale
	finaleRunning = function()
		return finale ~= nil and os.clock() - finale.T0 < FIN.Total + 3
	end
	Bus.On("CauldronClaimPending", function()
		claimPendingAt = os.clock()
	end)
	Bus.On("CauldronClaimLocal", function(d)
		if type(d) ~= "table" then
			return
		end
		claimPendingAt = -math.huge
		local ok, res = pcall(playFinale, d)
		if not ok then
			warn("CauldronFX finale: " .. tostring(res))
			d.Handled = nil
		end
		local waiting = deferredClaim
		deferredClaim = nil
		if waiting and not d.Handled then
			task.spawn(claim, waiting) -- no finale (far, ReducedMotion, busy camera): the public geyser instead
		end
		if not d.Handled and d.Test then
			-- the Studio test without the window: the card at once
			Bus.Fire("RewardReveal", { Title = L("THE BURIED MOON BREW", "ЗЕЛЬЕ ПОГРЕБЁННОЙ ЛУНЫ"), Rows = d.Rows or {} })
		end
	end)

	Bus.On("Signal", function(sig)
		if type(sig) ~= "table" or sig.Kind ~= "Cauldron" or type(sig.Data) ~= "table" then
			return
		end
		local d = sig.Data
		local ok, err = pcall(function()
			if d.Kind == "Trick" then
				trick(d)
			elseif d.Kind == "Treat" then
				treat(d)
			elseif d.Kind == "LevelUp" then
				levelUp(d)
			elseif d.Kind == "Claim" then
				claim(d)
			end
		end)
		if not ok then
			warn("CauldronFX " .. tostring(d.Kind) .. ": " .. tostring(err))
		end
	end)

	-------------------------------------------------------------------------------------------------------------
	-- main loop
	-------------------------------------------------------------------------------------------------------------
	local bubbleLoop = nil
	local qAt, slowAt, runeAt, flameAt = 0, 0, 0, 0
	local steamBuilt = -1
	local nextKick = os.clock() + 6
	local brewT = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		dt = math.min(dt, .1)
		if now - qAt > 1 then
			qAt = now
			refresh()
			local n = 0
			for _ in pairs(steamPoints) do
				n += 1
			end
			if n ~= steamBuilt then
				steamBuilt = n
				buildSteam()
			end
			if Q.Close and brew.Part ~= nil and now - (brew.SeenAt or now) > 4 then
				ensureChains()
			end
			-- sound bed
			local d = (camPos() - brew.Center).Magnitude
			if d < 75 and Q.Near then
				if not bubbleLoop then
					bubbleLoop = Audio.Loop("CauldronBubbles", brew.Center + V3(0, 1, 0))
				end
				local prof = CauldronFX.Profile(myLevel())
				bubbleLoop:SetVolume((.7 + prof.Glow * .25) * (1 + surge * .6), .8)
			elseif bubbleLoop and d > 90 then
				bubbleLoop:Stop(1.2)
				bubbleLoop = nil
			end
		end
		local ok, err = pcall(function()
			local prof, lvl = CauldronFX.Profile(myLevel())
			-- surge eases toward its target; flash decays (begin -> peak -> fade)
			surge += (surgeTarget - surge) * math.min(1, dt * (surgeTarget > surge and 4 or 1.5))
			flash = math.max(0, flash - dt * 1.4)
			local active = Q.Near
			local rate = active and Q.Particles or 0
			for _, s in ipairs(steam) do
				s.E.Rate = rate * prof.Steam * .9 * (1 + surge * 2)
			end
			fire.Rate = rate * (10 + 10 * prof.Flame) * (1 + surge * .6)
			fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3 * prof.Flame * (1 + surge * .4)), NumberSequenceKeypoint.new(1, 0) })
			fire.Speed = NumberRange.new(3 * prof.Flame, 6 * prof.Flame * (1 + surge * .5))
			spark.Rate = Q.Quality == "Low" and 0 or rate * (2 + 3 * prof.Bright) * (1 + surge * 2)
			sparkP.CFrame = CFrame.new(brew.Center + V3(0, .2, 0))
			-- light
			light.Brightness = active and (prof.Glow * 1.1 * (1 + surge * .8 + flash * 1.5) * (.92 + .08 * math.noise(now * 3, 1.7))) or 0
			light.Range = 16 + lvl * 2 + surge * 6
			lightP.CFrame = CFrame.new(brew.Center + V3(0, 2.5 + surge, 0))
			for i = #actors, 1, -1 do
				local a = actors[i]
				local okA, alive = pcall(a.Fn, now - a.T0, dt)
				if not okA then
					warn("CauldronFX effect failed: " .. tostring(alive))
					table.remove(actors, i)
				elseif not alive then
					table.remove(actors, i)
				end
			end
			if not active then
				return
			end
			-- brew surface: brighter per level, swells with the surge
			brewT += dt
			if brew.Part and brew.Part.Parent and brew.BaseCF and Q.Close then
				local swell = math.sin(brewT * 1.7) * .05 + surge * .45
				brew.Part.CFrame = brew.BaseCF + V3(0, swell, 0)
				local hot = C.BrewHot
				if lvl >= 5 then
					hot = hot:Lerp(RGB(200, 160, 255), .5 + .5 * math.sin(brewT * .8))
				end
				brew.Part.Color = brew.BaseColor:Lerp(hot, math.clamp(prof.Bright * .7 + surge * .4 + flash * .3, 0, 1))
			end
			if Q.Close then
				stepBubbles(dt, prof)
				if now >= nextFace then
					nextFace = now + prof.Face * rng:NextNumber(.7, 1.3) / (Q.Quality == "Low" and .5 or 1)
					spawnFace()
				end
				stepFaces(dt)
				stepWisps(dt, prof, lvl)
				stepOwnChains(dt, now)
				if now - flameAt > 1 / 20 then
					flameAt = now
					-- the fire-pit tongues: taller with every cauldron level, licking, leaping with the surge
					local h = .72 + .5 * (prof.Flame - .55) / .7
					for p, f in pairs(flames) do
						if p.Parent then
							local t = now + f.Phase
							local k = h * (1 + .14 * math.noise(t * 3.1, f.Phase) + .06 * math.sin(t * 9.3)) * (1 + surge * .35)
							p.Size = V3(f.Size.X, f.Size.Y * k, f.Size.Z)
							p.CFrame = f.CF * CFrame.new(0, f.Size.Y * (k - 1) / 2, 0)
						end
					end
					-- the builder's bubbles swell and pop too
					for p, b in pairs(staticBubbles) do
						if p.Parent then
							local k = ((now + b.Phase) % b.Life) / b.Life
							local grow = k < .86 and (.25 + .85 * smooth(k / .86)) or (1.1 + (k - .86) / .14 * .3)
							p.Size = b.Size * grow
							p.CFrame = b.CF + V3(0, math.sin((now + b.Phase) * 2) * .04 + surge * .4, 0)
							p.Transparency = k < .86 and 0 or (k - .86) / .14
						end
					end
				end
				if now - runeAt > 1 / 15 then
					runeAt = now
					stepRunes(now, prof, lvl)
				end
				if now >= nextKick then
					nextKick = now + rng:NextNumber(5, 9)
					kickChains(.25)
				end
			elseif now - slowAt > .5 then
				slowAt = now
				stepRunes(now, prof, lvl)
			end
		end)
		if not ok then
			warn("CauldronFX: " .. tostring(err))
		end
	end)
end

return CauldronFX
