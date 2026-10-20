-- Visuals of BELL SEALS V-VII and the BLACK BELL ASSAULT (ReplicatedStorage.Halloween.Models.Seals2, WP-J).
-- Pure Part builders (Part / WedgePart / Ball / Cylinder, no meshes, no assets, deterministic): the client presenters
-- (HalloweenClient.Trials.Doors / Choir / Bell / Assault / Resonance) build these models locally on top of the invisible
-- server Strike targets; tests and the QA renders build them offline.
--
-- API
--   Seals2.Doorkeeper(opts?) -> Model      THE DOORKEEPER: a crooked, dog-eared door that walks (~13 studs)
--   Seals2.Bellkeeper(opts?) -> Model      THE BELLKEEPER: a hooded sexton with a dog-skull face, a lantern heart, the
--                                          bell rope in one hand (opts.Variant = "Assault": 1.35x, violet crown + cracks)
--   Seals2.ChoirSpirit(note, opts?) -> Model   a little singing ghost-dog in a choir robe, tinted by its note (1..7)
--   Seals2.Moth(opts?) -> Model            one pale moth (body + two wings)
--   Seals2.Echo(opts?) -> Model            a Resonant Echo spot: a floating cracked bell shard in a rune ring
--   opts = {Lite = bool (Low quality: fewer details), Scale = number}
-- Model conventions (the presenters animate by these names):
--   built at the origin: ground centre (0, 0, 0) (spirits / moths / echoes: their centre), +Y up, the front looks along -Z.
--   PrimaryPart "Root" (invisible, CanQuery off). Every part: Anchored, CanCollide / CanQuery / CanTouch off, no shadow.
--   Sub-models with their own PrimaryPart pivot: Doorkeeper "ArmL" / "ArmR" (pivot = shoulder), Bellkeeper "RopeArm" /
--   "BellArm" (pivot = shoulder), Moth "WingL" / "WingR" (pivot = wing root).
--   Named parts: Doorkeeper "EyeL" / "EyeR" / "Mouth" / "Crack" (neon, brighten while stuck), "Tatter" (sway);
--   Bellkeeper "Heart" (the weak point core), "HeartCage", "EyeL" / "EyeR", "RopeHand" (rope start), "Crown" (Assault);
--   ChoirSpirit "Mouth", "Note" (the floating note), "Robe"; Echo "Shard", "Rune".
local Seals2 = {}

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material

local INK = C(16, 12, 26)
local VIOLET = C(150, 80, 230)
local VIOLET_HI = C(196, 140, 255)
local CANDLE = C(255, 170, 80)
local MOON = C(150, 200, 255)
local BONE = C(230, 222, 200)
local IRON = C(44, 44, 56)
local IRON_HI = C(70, 68, 84)
local WOOD = C(84, 58, 62)
local WOOD_D = C(56, 38, 44)
local ROBE = C(30, 22, 42)
local ROBE_HI = C(48, 34, 66)
local GOLD = C(232, 186, 82)

Seals2.Colors = { Ink = INK, Violet = VIOLET, Candle = CANDLE, Moon = MOON, Bone = BONE }

-- note i of the Last Bell's song -> its spirit's colour (moon blue .. violet)
function Seals2.NoteColor(note: number): Color3
	local t = math.clamp(((tonumber(note) or 1) - 1) / 6, 0, 1)
	return MOON:Lerp(VIOLET_HI, t)
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local class = props and props.Class or "Part"
	local p: any = Instance.new(class)
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	if props then
		if props.Shape then
			p.Shape = props.Shape
		end
		if props.Transparency then
			p.Transparency = props.Transparency
		end
		if props.Reflectance then
			p.Reflectance = props.Reflectance
		end
	end
	p.Parent = parent
	return p
end

local function ball(parent: Instance, name: string, d: number, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local o = props and table.clone(props) or {}
	o.Shape = Enum.PartType.Ball
	return part(parent, name, V(d, d, d), cf, color, material, o)
end

-- a cylinder standing upright (Roblox cylinders lie along X)
local function cylY(parent: Instance, name: string, h: number, d: number, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local o = props and table.clone(props) or {}
	o.Shape = Enum.PartType.Cylinder
	return part(parent, name, V(h, d, d), cf * ANG(0, 0, PI / 2), color, material, o)
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local o = props and table.clone(props) or {}
	o.Class = "WedgePart"
	return part(parent, name, size, cf, color, material, o)
end

-- a bar between two points (square section w x w)
local function bar(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf
	if len < 1e-3 then
		cf = CF(mid)
	else
		local up = math.abs((b - a).Unit.Y) > .95 and V(1, 0, 0) or V(0, 1, 0)
		cf = CFrame.lookAt(mid, b, up)
	end
	return part(parent, name, V(w, w, math.max(.05, len)), cf, color, material, props)
end

local function model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

local function root(m: Model, at: CFrame): BasePart
	local r = part(m, "Root", V(1, 1, 1), at, INK, M.SmoothPlastic, { Transparency = 1 })
	m.PrimaryPart = r
	return r
end

local function finish(m: Model, scale: number?): Model
	local s = tonumber(scale) or 1
	if s ~= 1 then
		pcall(function()
			(m :: any):ScaleTo(s)
		end)
	end
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- THE DOORKEEPER
---------------------------------------------------------------------------------------------------------------------
function Seals2.Doorkeeper(opts: { [string]: any }?): Model
	local o = opts or {}
	local lite = o.Lite == true
	local m = model("Doorkeeper")
	root(m, CF(0, .5, 0))
	m:SetAttribute("Height", 13.5)
	-- legs: two crooked door-frame posts on iron shoes
	for _, sx in ipairs({ -1, 1 }) do
		part(m, "Leg", V(1.2, 2.8, 1.1), CF(sx * 1.55, 1.4, 0) * ANG(0, 0, sx * .06), WOOD_D, M.WoodPlanks)
		part(m, "Shoe", V(1.6, .5, 1.8), CF(sx * 1.65, .25, -.15), IRON, M.CorrodedMetal)
	end
	-- the door body: two planks, slightly twisted, a darker inset panel
	local body = CF(0, 7.4, 0) * ANG(0, 0, .035)
	part(m, "Plank", V(3.3, 9.2, .9), body * CF(-1.68, 0, 0) * ANG(0, 0, -.02), WOOD, M.WoodPlanks)
	part(m, "Plank", V(3.3, 9.2, .9), body * CF(1.68, .15, 0) * ANG(0, 0, .025), WOOD:Lerp(WOOD_D, .3), M.WoodPlanks)
	part(m, "Panel", V(4.6, 3.6, .2), body * CF(0, -2.2, -.5), WOOD_D, M.Wood)
	-- iron frame: posts, a crooked lintel, two "dog ear" gables on top
	for _, sx in ipairs({ -1, 1 }) do
		part(m, "Frame", V(.4, 9.8, 1.2), body * CF(sx * 3.55, 0, 0), IRON, M.CorrodedMetal)
		wedge(m, "Ear", V(.9, 2.8, 1.8), body * CF(sx * 2.45, 6.05, 0) * ANG(0, sx > 0 and PI / 2 or -PI / 2, 0) * ANG(0, 0, 0), WOOD_D, M.WoodPlanks)
		wedge(m, "EarInner", V(.3, 1.9, 1), body * CF(sx * 2.45, 5.75, -.5) * ANG(0, sx > 0 and PI / 2 or -PI / 2, 0), VIOLET:Lerp(INK, .45), M.Fabric)
	end
	part(m, "Lintel", V(7.8, .45, 1.3), body * CF(0, 4.85, 0) * ANG(0, 0, -.06), IRON, M.CorrodedMetal)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, "Seam", V(.12, 8.8, .3), body * CF(sx * 3.3, 0, -.4), VIOLET, M.Neon, { Transparency = .1 })
	end
	part(m, "Seam", V(6.5, .12, .3), body * CF(0, 4.55, -.4) * ANG(0, 0, -.06), VIOLET, M.Neon, { Transparency = .1 })
	-- face: brow strap, two candle eyes, a keyhole mouth with a violet glow inside, a knocker ring nose
	part(m, "Brow", V(5.2, .32, .2), body * CF(0, 3.25, -.55) * ANG(0, 0, .08), IRON_HI, M.CorrodedMetal)
	ball(m, "EyeSocket", 1.3, body * CF(-1.05, 2.55, -.2), INK, M.SmoothPlastic)
	ball(m, "EyeSocket", 1.3, body * CF(1.05, 2.45, -.2), INK, M.SmoothPlastic)
	ball(m, "EyeL", .8, body * CF(-1.05, 2.55, -.62), CANDLE, M.Neon)
	ball(m, "EyeR", .8, body * CF(1.05, 2.45, -.62), CANDLE, M.Neon)
	ball(m, "Mouth", 1.5, body * CF(0, .35, -.4), INK, M.SmoothPlastic)
	wedge(m, "Mouth", V(.2, 2, 1.1), body * CF(0, -1.05, -.47) * ANG(0, PI / 2, 0), INK, M.SmoothPlastic)
	ball(m, "MouthGlow", .8, body * CF(0, .3, -.32), VIOLET, M.Neon)
	part(m, "Knocker", V(.18, 1.2, 1.2), body * CF(0, 1.3, -.62) * ANG(0, PI / 2, 0), GOLD, M.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "KnockerHole", V(.2, .7, .7), body * CF(0, 1.3, -.63) * ANG(0, PI / 2, 0), WOOD_D, M.Wood, { Shape = Enum.PartType.Cylinder })
	-- straps + nails across the body
	for _, y in ipairs({ -3.5, -.9 }) do
		part(m, "Strap", V(6.9, .36, .14), body * CF(0, y, -.5), IRON, M.CorrodedMetal)
		if not lite then
			for _, x in ipairs({ -2.9, -1, 1, 2.9 }) do
				ball(m, "Nail", .26, body * CF(x, y, -.58), IRON_HI, M.Metal)
			end
		end
	end
	-- neon cracks (brighten while the Doorkeeper is stuck after a slam)
	local cracks = { { -2.6, 1.8, -1.9, .6 }, { -1.9, .6, -2.3, -.8 }, { 2.2, -1.6, 1.4, -2.8 }, { 1.4, -2.8, 2.1, -4 } }
	for _, c in ipairs(cracks) do
		bar(m, "Crack", (body * CF(c[1], c[2], -.5)).Position, (body * CF(c[3], c[4], -.5)).Position, .16, VIOLET, M.Neon)
	end
	-- arms: hinge straps from the shoulders, key-tooth claws
	for _, sx in ipairs({ -1, 1 }) do
		local arm = model(sx < 0 and "ArmL" or "ArmR", m)
		local shoulder = (body * CF(sx * 3.9, 3.6, 0)).Position
		local pivot = part(arm, "Shoulder", V(.6, .6, .6), CF(shoulder), IRON, M.CorrodedMetal, { Transparency = 1 })
		arm.PrimaryPart = pivot
		ball(arm, "Joint", 1.3, CF(shoulder), IRON_HI, M.CorrodedMetal)
		local elbow = shoulder + V(sx * 1.6, -3.3, -.8)
		local wrist = elbow + V(sx * .2, -3, -1.1)
		bar(arm, "Upper", shoulder, elbow, .8, IRON, M.CorrodedMetal)
		ball(arm, "Elbow", 1, CF(elbow), IRON_HI, M.CorrodedMetal)
		bar(arm, "Fore", elbow, wrist, .7, IRON, M.CorrodedMetal)
		part(arm, "Hand", V(1.6, .6, 1.1), CF(wrist) * ANG(0, 0, sx * .2), IRON_HI, M.CorrodedMetal)
		for k = -1, 1 do
			local tip = wrist + V(sx * .2 + k * .5, -1.6 - math.abs(k) * .25, -.35)
			bar(arm, "Claw", wrist + V(k * .48, -.25, 0), tip, .3, IRON_HI, M.Metal)
		end
		if sx > 0 then
			-- the Doorkeeper's key: bow, shaft, bit
			local k0 = wrist + V(.1, -.9, -.9)
			part(arm, "KeyBow", V(.25, 1.3, 1.3), CF(k0 + V(0, .6, 0)) * ANG(0, PI / 2, 0), GOLD, M.Metal, { Shape = Enum.PartType.Cylinder })
			part(arm, "KeyBowHole", V(.3, .7, .7), CF(k0 + V(0, .6, 0)) * ANG(0, PI / 2, 0), INK, M.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
			bar(arm, "KeyShaft", k0, k0 + V(0, -3.2, -.3), .32, GOLD, M.Metal)
			part(arm, "KeyBit", V(.25, .7, .9), CF(k0 + V(0, -2.8, -.75)), GOLD, M.Metal)
		end
	end
	-- ghost tatters around the base
	if not lite then
		for k = 0, 5 do
			local a = k / 6 * PI * 2 + .3
			wedge(m, "Tatter", V(.15, 2.4, 1.6), CF(math.sin(a) * 2.7, 1.6, math.cos(a) * 1.2) * ANG(0, a, 0) * ANG(PI, 0, 0),
				VIOLET:Lerp(INK, .35), M.Fabric, { Transparency = .35 })
		end
	end
	return finish(m, o.Scale)
end

---------------------------------------------------------------------------------------------------------------------
-- THE BELLKEEPER
---------------------------------------------------------------------------------------------------------------------
function Seals2.Bellkeeper(opts: { [string]: any }?): Model
	local o = opts or {}
	local lite = o.Lite == true
	local assault = o.Variant == "Assault"
	local m = model(assault and "BellkeeperAssault" or "Bellkeeper")
	root(m, CF(0, .5, 0))
	m:SetAttribute("Height", 17)
	m:SetAttribute("HeartHeight", 7.5)
	local robe = assault and ROBE:Lerp(VIOLET, .12) or ROBE
	-- the robe: a bell-shaped stack of tiers
	local tiers = { { 1.6, 7.2 }, { 1.7, 6.4 }, { 1.7, 5.6 }, { 1.7, 4.8 }, { 1.6, 4.1 }, { 1.4, 3.6 } }
	local y = 0
	for i, t in ipairs(tiers) do
		cylY(m, "Robe", t[1] + .15, t[2], CF(0, y + t[1] / 2, 0) * ANG(0, i * .5, (i % 2 == 0 and 1 or -1) * .012),
			i % 2 == 0 and robe:Lerp(ROBE_HI, .35) or robe, M.Fabric)
		y += t[1]
	end
	local shoulderY = y
	-- hem tatters
	if not lite then
		for k = 0, 9 do
			local a = k / 10 * PI * 2
			wedge(m, "Tatter", V(.15, 1.6, 1.4), CF(math.sin(a) * 3.55, .55, math.cos(a) * 3.55) * ANG(0, a + PI / 2, 0) * ANG(PI, 0, 0),
				robe:Lerp(INK, .3), M.Fabric, { Transparency = .2 })
		end
	end
	-- the lantern heart on the chest (the weak point sits at HeartHeight)
	local heartCF = CF(0, 7.5, -2.05)
	ball(m, "Heart", 1.5, heartCF, CANDLE, M.Neon)
	cylY(m, "HeartCap", .35, 2.1, heartCF * CF(0, 1.15, 0), IRON, M.CorrodedMetal)
	cylY(m, "HeartCap", .35, 2.1, heartCF * CF(0, -1.15, 0), IRON, M.CorrodedMetal)
	for k = 0, 3 do
		local a = k / 4 * PI * 2 + PI / 4
		part(m, "HeartCage", V(.16, 2.3, .16), heartCF * CF(math.cos(a) * .95, 0, math.sin(a) * .95), IRON_HI, M.CorrodedMetal)
	end
	-- shoulders, collar
	cylY(m, "Collar", .6, 4.4, CF(0, shoulderY + .2, 0), robe:Lerp(ROBE_HI, .5), M.Fabric)
	-- the hood: a tall pointed cowl around a dark opening
	local hood = CF(0, shoulderY + 2.3, .2)
	ball(m, "Hood", 3.8, hood, robe, M.Fabric)
	part(m, "Hood", V(3.4, 2, 3.2), hood * CF(0, -1.1, .1), robe, M.Fabric)
	for k, d in ipairs({ 3, 2.3, 1.6, .9 }) do
		cylY(m, "HoodTip", .9, d, hood * CF(0, 1.3 + k * .7, .35 * k) * ANG(-.25 * k, 0, 0), robe:Lerp(ROBE_HI, k * .08), M.Fabric)
	end
	ball(m, "HoodOpening", 2.7, hood * CF(0, -.2, -.95), INK, M.SmoothPlastic)
	-- the dog-skull face inside the hood
	local face = hood * CF(0, -.15, -1.85)
	ball(m, "Skull", 1.7, face * CF(0, .25, .25), BONE, M.SmoothPlastic)
	part(m, "Snout", V(.9, .7, 1.2), face * CF(0, -.35, -.4), BONE, M.SmoothPlastic)
	ball(m, "Nose", .4, face * CF(0, -.15, -1), INK, M.SmoothPlastic)
	ball(m, "EyeL", .42, face * CF(-.42, .45, -.55), CANDLE, M.Neon)
	ball(m, "EyeR", .42, face * CF(.42, .45, -.55), CANDLE, M.Neon)
	part(m, "Jaw", V(.8, .2, 1), face * CF(0, -.78, -.35), BONE:Lerp(INK, .2), M.SmoothPlastic)
	-- the rope arm: up to the bell rope, a bony hand gripping it
	local function arm(name: string, sx: number, hand: Vector3, elbowOff: Vector3): Model
		local a = model(name, m)
		local shoulder = V(sx * 2, shoulderY - .3, 0)
		local pivot = part(a, "Shoulder", V(.6, .6, .6), CF(shoulder), robe, M.Fabric, { Transparency = 1 })
		a.PrimaryPart = pivot
		local elbow = shoulder + elbowOff
		bar(a, "Sleeve", shoulder, elbow, 1.3, robe:Lerp(ROBE_HI, .25), M.Fabric)
		bar(a, "Sleeve", elbow, hand, 1.1, robe:Lerp(ROBE_HI, .25), M.Fabric)
		ball(a, "Cuff", 1.25, CF(elbow:Lerp(hand, .82)), robe:Lerp(ROBE_HI, .5), M.Fabric)
		ball(a, "Hand", .8, CF(hand), BONE, M.SmoothPlastic)
		return a
	end
	local ropeHand = V(-1.6, shoulderY + 5.2, -.9)
	local ra = arm("RopeArm", -1, ropeHand, V(-.6, 2.4, -.5))
	part(ra, "RopeHand", V(.3, .3, .3), CF(ropeHand), BONE, M.SmoothPlastic, { Transparency = 1 })
	local bellHand = V(2.8, shoulderY - 3.4, -1.6)
	local ba = arm("BellArm", 1, bellHand, V(1.2, -1.8, -.6))
	-- the hand-bell
	cylY(ba, "HandBellHandle", 1.1, .3, CF(bellHand + V(0, .55, 0)), WOOD, M.Wood)
	cylY(ba, "HandBell", 1, 1.2, CF(bellHand - V(0, .45, 0)), C(70, 60, 54), M.Metal)
	ball(ba, "HandBellClapper", .35, CF(bellHand - V(0, 1.05, 0)), IRON_HI, M.Metal)
	-- a short rope stub in the hand (the presenter stretches "Rope" up to the Black Bell)
	part(m, "Rope", V(.35, .35, 2), CF(ropeHand + V(0, 1, 0)) * ANG(PI / 2, 0, 0), C(120, 92, 62), M.Fabric)
	-- violet rune trims
	cylY(m, "RobeRune", .25, 7.35, CF(0, 1.1, 0), assault and VIOLET_HI or VIOLET, M.Neon, { Transparency = .25 })
	cylY(m, "RobeRune", .2, 4.95, CF(0, 6.6, 0), assault and VIOLET_HI or VIOLET, M.Neon, { Transparency = .35 })
	if assault then
		-- the Assault variant: a crown of violet fire, cracks of light down the robe, chains wrapped round
		for k = 0, 5 do
			local a = k / 6 * PI * 2
			wedge(m, "Crown", V(.35, 1.8, .7), hood * CF(math.sin(a) * 1.55, 2.2, .3 + math.cos(a) * 1.45) * ANG(0, a, 0), VIOLET_HI, M.Neon)
		end
		local cracks = { { -1.8, 9.5, -1.4, 6.2 }, { -1.4, 6.2, -2.4, 3.1 }, { 1.6, 8.6, 2.2, 4.8 }, { 2.2, 4.8, 1.5, 1.6 } }
		for _, c in ipairs(cracks) do
			bar(m, "Crack", V(c[1], c[2], -2.1), V(c[3], c[4], -2.6), .2, VIOLET_HI, M.Neon)
		end
		if not lite then
			for k = 0, 7 do
				local a = k / 8 * PI * 2
				ball(m, "ChainLink", .55, CF(math.sin(a) * 2.6, 4.2 + k * .25, math.cos(a) * 2.6), IRON, M.CorrodedMetal)
			end
		end
	end
	return finish(m, (o.Scale or 1) * (assault and 1.35 or 1))
end

---------------------------------------------------------------------------------------------------------------------
-- CHOIR SPIRIT
---------------------------------------------------------------------------------------------------------------------
function Seals2.ChoirSpirit(note: number, opts: { [string]: any }?): Model
	local o = opts or {}
	local col = Seals2.NoteColor(note)
	local m = model("ChoirSpirit")
	root(m, CF(0, 0, 0))
	m:SetAttribute("Note", note)
	-- robe: a translucent bell with a white ruff collar, a wisp tail
	cylY(m, "Robe", 1.3, 2.6, CF(0, -.9, 0), col, M.ForceField, { Transparency = .15 })
	cylY(m, "Robe", 1, 2.1, CF(0, -.1, 0), col:Lerp(Color3.new(1, 1, 1), .15), M.ForceField, { Transparency = .1 })
	cylY(m, "Ruff", .35, 2.3, CF(0, .5, 0), Color3.new(1, 1, 1):Lerp(col, .2), M.SmoothPlastic, { Transparency = .1 })
	wedge(m, "Tail", V(1.6, 1.2, .9), CF(0, -2.1, .25) * ANG(PI, 0, 0), col, M.ForceField, { Transparency = .35 })
	wedge(m, "Tail", V(.9, .9, .6), CF(0, -2.9, .45) * ANG(PI, 0, 0), col, M.ForceField, { Transparency = .55 })
	-- a ghost-dog head: floppy ears, two dark eyes, an open singing mouth
	local head = CF(0, 1.45, 0)
	local white = Color3.new(1, 1, 1):Lerp(col, .12)
	ball(m, "Head", 1.75, head, white, M.SmoothPlastic, { Transparency = .05 })
	part(m, "Muzzle", V(1.05, .72, 1), head * CF(0, -.32, -.95), white, M.SmoothPlastic)
	ball(m, "Nose", .38, head * CF(0, -.08, -1.47), INK, M.SmoothPlastic)
	ball(m, "Mouth", .55, head * CF(0, -.72, -1.28), INK, M.SmoothPlastic)
	ball(m, "EyeL", .3, head * CF(-.4, .28, -.72), INK, M.SmoothPlastic)
	ball(m, "EyeR", .3, head * CF(.4, .28, -.72), INK, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, "Ear", V(.28, 1.55, .85), head * CF(sx * .92, -.45, .1) * ANG(0, 0, sx * .22), col:Lerp(INK, .1), M.SmoothPlastic)
	end
	-- the note it sings, floating above the head
	local note3 = model("Note", m)
	local nroot = ball(note3, "NoteHead", .55, head * CF(.35, 1.6, 0), col, M.Neon)
	note3.PrimaryPart = nroot
	part(note3, "NoteStem", V(.12, 1.1, .12), head * CF(.6, 2.15, 0), col, M.Neon)
	wedge(note3, "NoteFlag", V(.1, .55, .5), head * CF(.6, 2.45, -.25) * ANG(0, 0, 0), col, M.Neon)
	if o.Lite ~= true then
		local light = Instance.new("PointLight")
		light.Name = "SpiritGlow"
		light.Color = col
		light.Range = 9
		light.Brightness = 1.1
		light.Shadows = false
		light.Parent = m.PrimaryPart
	end
	return finish(m, o.Scale)
end

---------------------------------------------------------------------------------------------------------------------
-- MOTH
---------------------------------------------------------------------------------------------------------------------
function Seals2.Moth(opts: { [string]: any }?): Model
	local o = opts or {}
	local m = model("Moth")
	root(m, CF(0, 0, 0))
	local pale = C(232, 236, 255)
	part(m, "Body", V(.16, .16, .6), CF(0, 0, 0), C(160, 150, 140), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		local w = model(sx < 0 and "WingL" or "WingR", m)
		local pivot = part(w, "WingRoot", V(.05, .05, .05), CF(sx * .05, 0, 0), pale, M.SmoothPlastic, { Transparency = 1 })
		w.PrimaryPart = pivot
		part(w, "Wing", V(.62, .03, .5), CF(sx * .38, 0, .05), pale, M.Neon, { Transparency = .15 })
	end
	return finish(m, o.Scale)
end

---------------------------------------------------------------------------------------------------------------------
-- RESONANT ECHO
---------------------------------------------------------------------------------------------------------------------
function Seals2.Echo(opts: { [string]: any }?): Model
	local o = opts or {}
	local m = model("ResonantEcho")
	root(m, CF(0, 0, 0))
	-- a floating cracked shard of the Black Bell, a violet rune ring on the ground under it
	local shard = CF(0, .4, 0) * ANG(.2, .4, .15)
	wedge(m, "Shard", V(.6, 2.6, 1.6), shard, C(58, 50, 74), M.CorrodedMetal)
	wedge(m, "Shard", V(.6, 1.6, 1.2), shard * CF(0, -1.9, .1) * ANG(PI, 0, 0), C(58, 50, 74), M.CorrodedMetal)
	bar(m, "ShardCrack", (shard * CF(.32, .9, -.2)).Position, (shard * CF(.32, -1.6, .3)).Position, .12, VIOLET_HI, M.Neon)
	bar(m, "ShardCrack", (shard * CF(-.32, .3, .3)).Position, (shard * CF(-.32, -1.9, -.1)).Position, .1, VIOLET_HI, M.Neon)
	ball(m, "ShardGlow", .7, shard * CF(0, -.4, 0), VIOLET, M.Neon, { Transparency = .3 })
	for k = 0, (o.Lite and 7 or 11) do
		local n = o.Lite and 8 or 12
		local a = k / n * PI * 2
		part(m, "Rune", V(.9, .06, .25), CF(math.cos(a) * 2.4, -2.45, math.sin(a) * 2.4) * ANG(0, -a, 0), VIOLET, M.Neon, { Transparency = .2 })
	end
	return finish(m, o.Scale)
end

return Seals2
