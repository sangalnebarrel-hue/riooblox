-- Visuals of the Halloween ore nodes and the Haunted Dig Spots (ReplicatedStorage.Halloween.Models.Spots).
-- Pure Part builders (Part / WedgePart / Ball / Cylinder, no meshes, no assets), deterministic per seed so every
-- client draws the same node. Used by the client (HalloweenClient.SpotFX builds the models locally on top of the
-- invisible server target parts) and by the server (Spots.HitPoints for the target hit points; Spots.Info for sizes).
--
-- API
--   Spots.Info[variant]                 {Kind="Ore"|"Spot", Name, RU, Radius, Height, Soil|Rock, Accent, Sound, FX, Rare?}
--   Spots.Build(variant, seed, opts)    -> Model (dispatches to Ore / Spot); opts {Lite=bool (Low quality), Facing=yaw rad}
--   Spots.Ore(kindId, seed, opts)       PUMPKIN ORE | GRAVE STONE | MOON SHARD   (Config.Ore.Kinds ids)
--   Spots.Spot(typeId, seed, opts)      CURSED SOIL | GHOST SOIL | PUMPKIN PATCH | BONE GRAVE | CURSED TREASURE
--   Spots.HitPoints(variant)            -> {{Pos=Vector3 (model space, ground centre = origin), Normal=Vector3}}
--   Spots.Label(variant, ru) -> string  display name
-- Model conventions (SpotFX animates by these):
--   built at the origin: ground centre (0,0,0), +Y up, the "front" (faces, chest lock, jack-o'-lantern) looks along -Z.
--   PrimaryPart "Root" (invisible). Model attrs HwVariant, HwKind, Height, Radius.
--   Part attrs: HwAnim = "Orbit" | "Bob" | "Lid" | "Flicker" | "Pulse"   (+ HwPhase, HwSpeed, HwAmp, HwHinge (Vector3))
--               HwStage = 1..3       detail that crumbles off as the target loses HP (1 first)
--               HwGlow = true        neon accents SpotFX brightens on hits
--   Attachments "FXPoint" (attr FX = "Rise"|"Ground"|"Core") where idle particles emit; PointLights named "SpotGlow".
local Spots = {}

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi
local TAU = math.pi * 2
local M = Enum.Material

local Config = nil
pcall(function()
	Config = require(script.Parent.Parent:WaitForChild("Config", 5))
end)

local function rgb(t: any, fallback: Color3): Color3
	if type(t) == "table" then
		return C(t[1] or 255, t[2] or 255, t[3] or 255)
	end
	return fallback
end
local function cfgRow(list: any, id: string): any
	for _, row in ipairs(list or {}) do
		if row.Id == id then
			return row
		end
	end
	return nil
end
local oreCfg = Config and Config.Ore and Config.Ore.Kinds or {}
local spotCfg = Config and Config.DigSpots and Config.DigSpots.Types or {}

Spots.Info = {
	PumpkinOre = { Kind = "Ore", Name = "PUMPKIN ORE", RU = "ТЫКВЕННАЯ РУДА", Radius = 4.4, Height = 6.6,
		Rock = rgb((cfgRow(oreCfg, "PumpkinOre") or {}).Rock, C(54, 36, 28)), Accent = rgb((cfgRow(oreCfg, "PumpkinOre") or {}).Accent, C(255, 128, 24)),
		FX = "Ember", Sound = "DigPumpkin", Chip = M.Slate },
	GraveStone = { Kind = "Ore", Name = "GRAVE STONE", RU = "МОГИЛЬНЫЙ КАМЕНЬ", Radius = 4.4, Height = 6.4,
		Rock = rgb((cfgRow(oreCfg, "GraveStone") or {}).Rock, C(92, 96, 108)), Accent = rgb((cfgRow(oreCfg, "GraveStone") or {}).Accent, C(140, 255, 150)),
		FX = "Sparkle", Sound = "DigBone", Chip = M.Slate },
	MoonShard = { Kind = "Ore", Name = "MOON SHARD", RU = "ЛУННЫЙ ОСКОЛОК", Radius = 4.4, Height = 7.6,
		Rock = rgb((cfgRow(oreCfg, "MoonShard") or {}).Rock, C(40, 26, 58)), Accent = rgb((cfgRow(oreCfg, "MoonShard") or {}).Accent, C(190, 110, 255)),
		FX = "Void", Sound = "DigCursed", Chip = M.Basalt },
	CursedSoil = { Kind = "Spot", Name = "CURSED SOIL", RU = "ПРОКЛЯТАЯ ЗЕМЛЯ", Radius = 4.0, Height = 2.6,
		Soil = C(52, 18, 22), Accent = rgb((cfgRow(spotCfg, "CursedSoil") or {}).Accent, C(255, 60, 60)), Sound = "DigCursed", Chip = M.Ground },
	GhostSoil = { Kind = "Spot", Name = "GHOST SOIL", RU = "ПРИЗРАЧНАЯ ЗЕМЛЯ", Radius = 3.9, Height = 2.6,
		Soil = C(150, 170, 198), Accent = rgb((cfgRow(spotCfg, "GhostSoil") or {}).Accent, C(210, 245, 255)), Sound = "DigGhost", Chip = M.Sand },
	PumpkinPatch = { Kind = "Spot", Name = "PUMPKIN PATCH", RU = "ТЫКВЕННАЯ ГРЯДКА", Radius = 4.0, Height = 2.6,
		Soil = C(58, 42, 32), Accent = rgb((cfgRow(spotCfg, "PumpkinPatch") or {}).Color, C(255, 130, 30)), Sound = "DigPumpkin", Chip = M.Ground },
	BoneGrave = { Kind = "Spot", Name = "BONE GRAVE", RU = "КОСТЯНАЯ МОГИЛА", Radius = 3.9, Height = 2.4,
		Soil = C(72, 58, 46), Accent = rgb((cfgRow(spotCfg, "BoneGrave") or {}).Accent, C(140, 255, 150)), Sound = "DigBone", Chip = M.Ground },
	CursedTreasure = { Kind = "Spot", Name = "CURSED TREASURE", RU = "ПРОКЛЯТЫЙ КЛАД", Radius = 4.4, Height = 3.4,
		Soil = C(46, 30, 42), Accent = rgb((cfgRow(spotCfg, "CursedTreasure") or {}).Accent, C(190, 90, 255)),
		Gold = rgb((cfgRow(spotCfg, "CursedTreasure") or {}).Color, C(255, 200, 70)), Sound = "TreasureReveal", Chip = M.Ground, Rare = true },
}

function Spots.Label(variant: string, ru: boolean?): string
	local info = Spots.Info[variant]
	if not info then
		return tostring(variant)
	end
	return ru and info.RU or info.Name
end

---------------------------------------------------------------------------------------------------------------------
-- part helpers
---------------------------------------------------------------------------------------------------------------------
local function make(class: string, parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?,
	props: { [string]: any }?): BasePart
	local p = Instance.new(class) :: any
	p.Name = name
	if props and props.Shape then
		p.Shape = props.Shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = props ~= nil and props.Shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	if props then
		for k, v in pairs(props) do
			if k == "Attrs" then
				for a, x in pairs(v) do
					p:SetAttribute(a, x)
				end
			elseif k ~= "Shape" and k ~= "Shadow" then
				p[k] = v
			end
		end
	end
	p.Parent = parent
	return p
end
local function block(parent, name, size, cf, color, mat, props)
	return make("Part", parent, name, size, cf, color, mat, props)
end
local function wedge(parent, name, size, cf, color, mat, props)
	return make("WedgePart", parent, name, size, cf, color, mat, props)
end
local function ball(parent, name, d: number, cf, color, mat, props)
	props = props or {}
	props.Shape = Enum.PartType.Ball
	return make("Part", parent, name, V(d, d, d), cf, color, mat, props)
end
-- cylinder whose axis is the cframe's X axis
local function cyl(parent, name, length: number, d: number, cf, color, mat, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	return make("Part", parent, name, V(length, d, d), cf, color, mat, props)
end
-- rotation turning +Y into dir
local function alignY(dir: Vector3): CFrame
	local up = V(0, 1, 0)
	local d = dir.Unit
	local dot = math.clamp(up:Dot(d), -1, 1)
	if dot > .9999 then
		return CFrame.identity
	end
	if dot < -.9999 then
		return ANG(PI, 0, 0)
	end
	return CFrame.fromAxisAngle(up:Cross(d).Unit, math.acos(dot))
end
-- rotation turning +X into dir (cylinders)
local function alignX(dir: Vector3): CFrame
	return alignY(dir) * ANG(0, 0, PI / 2)
end
-- a bar from a to b (block or cylinder), w = width, h = height (blocks)
local function bar(parent, name, a: Vector3, b: Vector3, w: number, h: number, color, mat, props)
	local d = b - a
	local len = d.Magnitude
	if len < 1e-3 then
		return nil
	end
	local mid = (a + b) / 2
	local cf = CF(mid) * alignY(d) -- +Y along the bar
	return block(parent, name, V(w, len, h), cf, color, mat, props)
end
local function rod(parent, name, a: Vector3, b: Vector3, d: number, color, mat, props)
	local dir = b - a
	local len = dir.Magnitude
	if len < 1e-3 then
		return nil
	end
	return cyl(parent, name, len, d, CF((a + b) / 2) * alignX(dir), color, mat, props)
end
local function shade(rng, c: Color3, k: number?): Color3
	local x = rng:NextNumber(-(k or .12), k or .12)
	return x > 0 and c:Lerp(C(255, 255, 255), x) or c:Lerp(C(0, 0, 0), -x)
end
local function anim(p: Instance?, kind: string, extra: { [string]: any }?)
	if not p then
		return p
	end
	p:SetAttribute("HwAnim", kind)
	for k, v in pairs(extra or {}) do
		p:SetAttribute(k, v)
	end
	return p
end
local function stage(p: Instance?, n: number)
	if p then
		p:SetAttribute("HwStage", n)
	end
	return p
end
local function glow(p: Instance?)
	if p then
		p:SetAttribute("HwGlow", true)
	end
	return p
end
local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Name = "SpotGlow"
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l:SetAttribute("Base", brightness)
	l.Parent = parent
	return l
end
local function fxPoint(root: BasePart, pos: Vector3, kind: string)
	local a = Instance.new("Attachment")
	a.Name = "FXPoint"
	a.Position = pos
	a:SetAttribute("FX", kind)
	a.Parent = root
	return a
end

local function newModel(name: string, variant: string, info: any): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = name
	local root = block(m, "Root", V(.4, .4, .4), CFrame.identity, C(255, 255, 255), M.SmoothPlastic, { Transparency = 1 })
	m.PrimaryPart = root
	m:SetAttribute("HwVariant", variant)
	m:SetAttribute("HwKind", info.Kind)
	m:SetAttribute("Height", info.Height)
	m:SetAttribute("Radius", info.Radius)
	return m, root
end

---------------------------------------------------------------------------------------------------------------------
-- shared pieces: dirt mound, ribbed pumpkin, jack-o'-lantern face, runes, bones, crystals, rock pile
---------------------------------------------------------------------------------------------------------------------
-- dome of a sphere cap with base radius R and height H
local function dome(R: number, H: number): (number, number)
	local rs = (R * R + H * H) / (2 * H)
	return rs, H - rs
end
local function domeY(R: number, H: number, r: number): number
	local rs, cy = dome(R, H)
	local q = rs * rs - r * r
	if q <= 0 then
		return 0
	end
	return math.max(0, cy + math.sqrt(q))
end
local function domeNormal(R: number, H: number, x: number, z: number): Vector3
	local rs, cy = dome(R, H)
	local y = domeY(R, H, math.sqrt(x * x + z * z))
	local n = V(x, y - cy, z)
	return n.Magnitude > 0 and n.Unit or V(0, 1, 0)
end
local function onDome(R: number, H: number, a: number, r: number, lift: number?): (Vector3, Vector3)
	local x, z = math.cos(a) * r, math.sin(a) * r
	local n = domeNormal(R, H, x, z)
	return V(x, domeY(R, H, r) + (lift or 0), z), n
end

-- o = {R, H, Soil, Soil2, Clod, Mat, ClodMat, Lite, Lumps, Clods, Rim, Pebble}
local function mound(m: Model, rng, o)
	local R, H = o.R, o.H
	local rs, cy = dome(R, H)
	local mat = o.Mat or M.Ground
	ball(m, "Mound", rs * 2, CF(0, cy, 0), o.Soil, mat, { Shadow = true })
	-- lumps break the perfect dome into a heap
	local lumps = o.Lumps or (o.Lite and 4 or 7)
	for i = 1, lumps do
		local a = i / lumps * TAU + rng:NextNumber(-.35, .35)
		local r = R * rng:NextNumber(.38, .7)
		local d = R * rng:NextNumber(.52, .78)
		local y = domeY(R, H, r) - d * rng:NextNumber(.3, .42)
		ball(m, "Lump", d, CF(math.cos(a) * r, y, math.sin(a) * r), shade(rng, o.Soil2 or o.Soil, .1), mat)
	end
	-- turned clods on the surface (crumble off as it is dug)
	local clods = o.Clods or (o.Lite and 6 or 16)
	for i = 1, clods do
		local a = rng:NextNumber(0, TAU)
		local r = R * math.sqrt(rng:NextNumber(.02, .8))
		local pos, n = onDome(R, H, a, r)
		local s = rng:NextNumber(.38, .85)
		local p = block(m, "Clod", V(s, s * rng:NextNumber(.55, .9), s * rng:NextNumber(.7, 1.1)),
			CF(pos + n * s * .12) * alignY(n) * ANG(rng:NextNumber(-.4, .4), rng:NextNumber(0, TAU), rng:NextNumber(-.4, .4)),
			shade(rng, o.Clod or o.Soil2 or o.Soil, .12), o.ClodMat or mat)
		stage(p, 1 + (i % 3))
	end
	-- spilled earth around the base: small irregular clumps, half sunk into the floor
	local rim = o.Rim or (o.Lite and 7 or 16)
	for i = 1, rim do
		local a = i / rim * TAU + rng:NextNumber(-.2, .2)
		local r = R * rng:NextNumber(.86, 1.12)
		local w = rng:NextNumber(.45, .95)
		local col = shade(rng, (o.Soil2 or o.Soil):Lerp(o.Soil, .5), .08)
		if i % 3 == 0 then
			ball(m, "Spill", w * 1.3, CF(math.cos(a) * r, -w * .3, math.sin(a) * r), col, mat)
		else
			block(m, "Spill", V(w, w * rng:NextNumber(.45, .7), w * rng:NextNumber(.7, 1.1)),
				CF(math.cos(a) * r, w * .1, math.sin(a) * r) * ANG(rng:NextNumber(-.5, .5), rng:NextNumber(0, TAU), rng:NextNumber(-.5, .5)), col, mat)
		end
	end
	local pebbles = o.Pebble and (o.Lite and 3 or 7) or 0
	for _ = 1, pebbles do
		local a = rng:NextNumber(0, TAU)
		local r = R * rng:NextNumber(1.0, 1.3)
		local s = rng:NextNumber(.25, .55)
		block(m, "Pebble", V(s, s * .6, s * .8), CF(math.cos(a) * r, s * .2, math.sin(a) * r) * ANG(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0),
			shade(rng, o.Pebble, .12), M.Slate)
	end
end

-- ribbed pumpkin standing on cf (bottom centre); returns the jack face frame (front = -Z of cf) or nil
local PUMPKIN = C(255, 128, 24)
local PUMPKIN_DARK = C(214, 92, 18)
local STEM = C(84, 92, 40)
local LEAF = C(70, 128, 50)
local VINE = C(98, 156, 58)
local function pumpkin(m: Model, cf: CFrame, r: number, rng, o: { [string]: any }?)
	o = o or {}
	local lobes = o.Lite and 6 or 8
	local base = o.Color or PUMPKIN
	local dark = o.Dark or PUMPKIN_DARK
	for k = 0, lobes - 1 do
		local a = k / lobes * TAU - PI / 2
		ball(m, "PumpkinLobe", r * 1.12, cf * CF(math.cos(a) * r * .44, r * .56, math.sin(a) * r * .44), k % 2 == 0 and base or dark,
			M.SmoothPlastic, { Shadow = r > .9 })
	end
	ball(m, "PumpkinCore", r * 1.02, cf * CF(0, r * .62, 0), base:Lerp(dark, .5), M.SmoothPlastic)
	-- stem + leaf
	local tilt = ANG(rng:NextNumber(-.3, .3), 0, rng:NextNumber(-.3, .3))
	local stemBase = cf * CF(0, r * 1.08, 0) * tilt
	cyl(m, "PumpkinStem", r * .42, r * .2, stemBase * CF(0, r * .16, 0) * ANG(0, 0, PI / 2), o.Stem or STEM, M.Wood)
	ball(m, "PumpkinStemTop", r * .22, stemBase * CF(r * .03, r * .38, 0), (o.Stem or STEM):Lerp(C(0, 0, 0), .2), M.Wood)
	if not o.NoLeaf then
		wedge(m, "PumpkinLeaf", V(.06, r * .45, r * .75), stemBase * CF(r * .3, r * .02, 0) * ANG(0, PI / 2 + rng:NextNumber(-.4, .4), -.5),
			LEAF, M.SmoothPlastic)
	end
	if not o.Face then
		return nil
	end
	-- carved face: features follow the front of an r-sphere around the core
	local center = cf * CF(0, r * .6, 0)
	local faceColor = o.FaceColor or C(255, 214, 92)
	local function onFront(x: number, y: number, inset: number): CFrame
		local z2 = r * r - x * x - y * y
		local z = -math.sqrt(math.max(0, z2)) + inset
		local p = Vector3.new(x, y, z)
		local n = p.Unit
		return center * CFrame.lookAt(p, p + n)
	end
	local parts = {}
	local function eye(x: number)
		local w, h = r * .26, r * .3
		local f = onFront(x, r * .2, r * .07)
		table.insert(parts, wedge(m, "JackEye", V(r * .12, h, w), f * CF(-w / 2, 0, 0) * ANG(0, PI / 2, 0), faceColor, M.Neon))
		table.insert(parts, wedge(m, "JackEye", V(r * .12, h, w), f * CF(w / 2, 0, 0) * ANG(0, -PI / 2, 0), faceColor, M.Neon))
	end
	eye(-r * .36)
	eye(r * .36)
	-- nose
	local nose = onFront(0, -r * .02, r * .03)
	table.insert(parts, wedge(m, "JackNose", V(r * .1, r * .16, r * .1), nose * CF(-r * .05, 0, 0) * ANG(0, PI / 2, 0), faceColor, M.Neon))
	table.insert(parts, wedge(m, "JackNose", V(r * .1, r * .16, r * .1), nose * CF(r * .05, 0, 0) * ANG(0, -PI / 2, 0), faceColor, M.Neon))
	-- jagged grin
	local teeth = 6
	for i = 0, teeth - 1 do
		local t = (i + .5) / teeth
		local x = (t - .5) * r * 1.05
		local y = -r * .3 + math.abs(t - .5) * r * .32
		local h = (i % 2 == 0) and r * .2 or r * .13
		local f = onFront(x, y, r * .07)
		table.insert(parts, block(m, "JackMouth", V(r * 1.05 / teeth * 1.08, h, r * .12), f * ANG(0, 0, (t - .5) * -.7), faceColor, M.Neon))
	end
	for _, p in ipairs(parts) do
		anim(p, "Flicker", { HwPhase = rng:NextNumber(0, 6) })
		glow(p)
	end
	local inner = ball(m, "JackGlow", r * .7, center, faceColor:Lerp(C(255, 120, 20), .4), M.Neon, { Transparency = .35 })
	anim(inner, "Flicker", { HwPhase = rng:NextNumber(0, 6) })
	return center
end

-- flat glowing rune glyphs (lying in the XZ plane of cf, "up" of the glyph = -Z)
local GLYPHS = {
	{ { -.25, -.5, -.25, .5 }, { -.25, .5, .25, .22 }, { .25, .22, -.25, -.02 }, { -.25, -.02, .28, -.5 } },
	{ { 0, -.5, 0, .5 }, { 0, .08, -.34, .5 }, { 0, .08, .34, .5 } },
	{ { 0, .5, .3, .1 }, { .3, .1, 0, -.22 }, { 0, -.22, -.3, .1 }, { -.3, .1, 0, .5 }, { 0, -.22, .3, -.5 }, { 0, -.22, -.3, -.5 } },
	{ { -.22, -.5, -.22, .5 }, { -.22, .32, .26, .02 }, { .26, .02, -.22, -.28 } },
	{ { -.32, -.5, .32, .5 }, { .32, -.5, -.32, .5 }, { -.32, 0, .32, 0 } },
	{ { -.3, -.5, -.3, .5 }, { .3, -.5, .3, .5 }, { -.3, .5, .3, -.1 } },
}
local function rune(m: Model, cf: CFrame, size: number, color: Color3, index: number)
	local g = GLYPHS[(index - 1) % #GLYPHS + 1]
	local out = {}
	for _, s in ipairs(g) do
		local a = cf * CF(s[1] * size, .025, -s[2] * size)
		local b = cf * CF(s[3] * size, .025, -s[4] * size)
		local mid = (a.Position + b.Position) / 2
		local d = b.Position - a.Position
		local len = d.Magnitude
		local up = cf.UpVector
		local right = d.Unit
		local back = right:Cross(up).Unit
		local p = block(m, "Rune", V(len + size * .08, .05, size * .1), CFrame.fromMatrix(mid, right, up, back), color, M.Neon)
		glow(p)
		table.insert(out, p)
	end
	return out
end

-- cartoon bone from a to b
local BONE = C(236, 226, 200)
local BONE_DARK = C(196, 182, 150)
local function bone(m: Model, a: Vector3, b: Vector3, d: number, color: Color3?)
	color = color or BONE
	local shaft = rod(m, "Bone", a, b, d, color, M.SmoothPlastic)
	local dir = (b - a).Unit
	local side = dir:Cross(V(0, 1, 0))
	if side.Magnitude < .1 then
		side = dir:Cross(V(1, 0, 0))
	end
	side = side.Unit * d * .45
	for _, e in ipairs({ a, b }) do
		local out = (e == a) and -dir or dir
		ball(m, "BoneKnob", d * 1.55, CF(e + side + out * d * .2), color, M.SmoothPlastic)
		ball(m, "BoneKnob", d * 1.55, CF(e - side + out * d * .2), color:Lerp(BONE_DARK, .3), M.SmoothPlastic)
	end
	return shaft
end

-- small dog skull looking along -Z of cf (cf = centre of the cranium)
local function skull(m: Model, cf: CFrame, s: number, color: Color3?, eyeColor: Color3?)
	color = color or BONE
	ball(m, "Skull", s, cf, color, M.SmoothPlastic, { Shadow = s > 1 })
	block(m, "SkullSnout", V(s * .55, s * .42, s * .62), cf * CF(0, -s * .14, -s * .52), color:Lerp(BONE_DARK, .25), M.SmoothPlastic)
	block(m, "SkullJaw", V(s * .46, s * .14, s * .5), cf * CF(0, -s * .38, -s * .46) * ANG(.12, 0, 0), color:Lerp(BONE_DARK, .45), M.SmoothPlastic)
	ball(m, "SkullNose", s * .2, cf * CF(0, -s * .02, -s * .84), C(30, 22, 26), M.SmoothPlastic)
	for i = -1, 1, 2 do
		local e = ball(m, "SkullEye", s * .3, cf * CF(i * s * .22, s * .06, -s * .36), eyeColor or C(26, 18, 22), eyeColor and M.Neon or M.SmoothPlastic)
		if eyeColor then
			glow(e)
		end
		wedge(m, "SkullEar", V(s * .1, s * .34, s * .3), cf * CF(i * s * .3, s * .46, s * .05) * ANG(0, 0, i * -.35), color:Lerp(BONE_DARK, .2), M.SmoothPlastic)
	end
end

-- hexagonal-ish crystal growing from base along dir
local function crystal(m: Model, base: CFrame, w: number, h: number, color: Color3, coreColor: Color3?, t: number?)
	local body = block(m, "Crystal", V(w, h, w), base * CF(0, h * .5, 0), color, M.Glass, { Transparency = t or .12, Reflectance = .15 })
	local tip = block(m, "CrystalTip", V(w * .72, w * .72, w * .72), base * CF(0, h, 0) * ANG(PI / 4, 0, PI / 4), color, M.Glass,
		{ Transparency = t or .12, Reflectance = .15 })
	local core = nil
	if coreColor then
		core = block(m, "CrystalCore", V(w * .36, h * .82, w * .36), base * CF(0, h * .48, 0), coreColor, M.Neon)
		glow(core)
	end
	return body, tip, core
end

-- the craggy rock heap every ore node stands on: rock chunks laid on an analytic surface (so accents can sit on it)
local function heapY(R: number, H: number, r: number): number
	local t = math.clamp(r / R, 0, .999)
	return H * (1 - t * t) ^ .75
end
local function heapPoint(R: number, H: number, a: number, r: number, lift: number?): (Vector3, Vector3)
	local t = math.clamp(r / R, 0, .97)
	local y = H * (1 - t * t) ^ .75
	local slope = H * 1.5 * t / R * (1 - t * t) ^ (-.25)
	local n = V(math.cos(a) * slope, 1, math.sin(a) * slope).Unit
	return V(math.cos(a) * r, y, math.sin(a) * r) + n * (lift or 0), n
end
local function angleGap(a: number, b: number): number
	local d = (a - b) % TAU
	return math.min(d, TAU - d)
end
-- o = {R, H, Rock, Rock2, Mat, Lite, Gap (angle kept clear), GapWidth}
local function heap(m: Model, rng, o)
	local R, H = o.R, o.H
	local mat = o.Mat or M.Slate
	local rock, rock2 = o.Rock, o.Rock2 or o.Rock
	block(m, "RockCore", V(R * 1.25, H * .8, R * 1.25), CF(0, H * .38, 0) * ANG(0, rng:NextNumber(0, TAU), 0), rock:Lerp(C(0, 0, 0), .35), mat)
	local rings = {
		{ t = .9, n = o.Lite and 6 or 10, s = { 1.7, 2.6 } },
		{ t = .66, n = o.Lite and 5 or 8, s = { 1.6, 2.4 } },
		{ t = .4, n = o.Lite and 4 or 6, s = { 1.5, 2.2 } },
		{ t = .1, n = 2, s = { 1.5, 2.0 } },
	}
	local k = 0
	for ri, ring in ipairs(rings) do
		local off = rng:NextNumber(0, TAU)
		for i = 1, ring.n do
			local a = off + i / ring.n * TAU + rng:NextNumber(-.2, .2)
			if o.Gap and ri <= 2 and angleGap(a, o.Gap) < (o.GapWidth or .5) then
				continue
			end
			k += 1
			local r = ring.t * R * rng:NextNumber(.92, 1.06)
			local pos, n = heapPoint(R, H, a, r)
			local sz = rng:NextNumber(ring.s[1], ring.s[2])
			local size = V(sz * rng:NextNumber(.85, 1.25), sz * rng:NextNumber(.6, .9), sz * rng:NextNumber(.8, 1.15))
			local cf = CF(pos - n * size.Y * .22) * alignY(n) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, TAU), rng:NextNumber(-.3, .3))
			block(m, "Rock", size, cf, shade(rng, k % 3 == 0 and rock2 or rock, .13), mat, { Shadow = sz > 1.9 })
			-- a lighter facet on some chunks catches the moonlight
			if not o.Lite and k % 2 == 0 then
				local f = block(m, "Facet", V(size.X * .62, size.Y * .16, size.Z * .5), cf * CF(size.X * .08, size.Y * .5, 0) * ANG(0, rng:NextNumber(0, TAU), rng:NextNumber(-.15, .15)),
					shade(rng, rock2:Lerp(C(255, 255, 255), .1), .06), mat)
				stage(f, 1 + k % 3)
			end
		end
	end
	for i = 1, (o.Lite and 3 or 8) do
		local a = i / 8 * TAU + rng:NextNumber(-.3, .3)
		local r = R * rng:NextNumber(1.0, 1.22)
		local sz = rng:NextNumber(.35, .8)
		block(m, "Pebble", V(sz, sz * .6, sz * .8), CF(math.cos(a) * r, sz * .2, math.sin(a) * r) * ANG(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0),
			shade(rng, i % 2 == 0 and rock2 or rock, .12), mat)
	end
end
-- glowing veins following the heap surface downhill from near the top
local function veins(m: Model, rng, R: number, H: number, count: number, color: Color3, skip: number?)
	for kk = 1, count do
		local a = kk / count * TAU + rng:NextNumber(-.3, .3)
		if skip and angleGap(a, skip) < .45 then
			a += .7
		end
		local prev = nil
		for j = 0, 3 do
			local r = R * (.22 + j * .2)
			local pos = heapPoint(R, H, a + rng:NextNumber(-.18, .18), r, .45)
			if prev then
				local p = bar(m, "Vein", prev, pos, .16 - j * .025, .1, color, M.Neon)
				glow(p)
				anim(p, "Pulse", { HwPhase = kk + j * .3 })
			end
			prev = pos
		end
	end
end

-- a twisting branch / root from base along dir
local function branch(m: Model, rng, base: Vector3, dir: Vector3, len: number, w: number, color: Color3)
	local p = base
	local d = dir.Unit
	for i = 1, 3 do
		local seg = len / 3 * (1 - (i - 1) * .12)
		d = (d + V(rng:NextNumber(-.5, .5), rng:NextNumber(-.15, .35), rng:NextNumber(-.5, .5))).Unit
		local q = p + d * seg
		bar(m, "Root", p, q, w * (1 - (i - 1) * .25), w * (1 - (i - 1) * .25), color, M.Wood)
		p = q
	end
	return p
end

-- a curly vine along points (pts = list of Vector3) + leaves
local function vine(m: Model, rng, pts: { Vector3 }, lite: boolean?)
	for i = 1, #pts - 1 do
		rod(m, "Vine", pts[i], pts[i + 1], .13, VINE, M.SmoothPlastic)
		if not lite and i % 2 == 0 then
			local p = pts[i]
			wedge(m, "VineLeaf", V(.05, .38, .62), CF(p + V(0, .12, 0)) * ANG(0, rng:NextNumber(0, TAU), rng:NextNumber(-.9, -.4)), LEAF, M.SmoothPlastic)
		end
	end
	-- curl at the end
	local last = pts[#pts]
	for k = 1, 4 do
		local a = k / 4 * TAU
		local q = last + V(math.cos(a) * .22, .1 + k * .05, math.sin(a) * .22)
		ball(m, "VineCurl", .12, CF(q), VINE, M.SmoothPlastic)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- ORE NODES
---------------------------------------------------------------------------------------------------------------------
local ORE = {}

-- PUMPKIN ORE: a black-brown rock heap cracked by lava-orange veins, a carved jack-o'-lantern heart bursting out of the
-- front, pumpkin nuggets and orange crystal clusters on top, vines
ORE.PumpkinOre = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 4.2, 3.8
	local accent = info.Accent
	heap(m, rng, { R = R, H = H, Rock = info.Rock:Lerp(C(90, 64, 48), .25), Rock2 = C(104, 74, 54), Mat = M.Slate, Lite = lite, Gap = -PI / 2, GapWidth = .7 })
	veins(m, rng, R, H, lite and 3 or 6, C(255, 110, 24), -PI / 2)
	-- the carved heart
	local heart = pumpkin(m, CF(0, -.1, -3.15) * ANG(-.12, 0, 0), 1.55, rng, { Face = true, Lite = lite })
	if heart then
		local lp = block(m, "HeartLight", V(.2, .2, .2), heart * CF(0, .2, -1.6), C(255, 160, 50), M.Neon, { Transparency = 1 })
		light(lp, C(255, 150, 40), 16, 2)
	end
	-- rocks hugging the heart (low, beside it)
	for _, side in ipairs({ -1, 1 }) do
		block(m, "Rock", V(1.3, .9, 1.4), CF(side * 2.15, .3, -3.2) * ANG(.2, side * .5, side * .25), shade(rng, info.Rock, .1), M.Slate, { Shadow = true })
	end
	-- pumpkin nuggets on the heap
	local nuggets = { { a = -PI / 2 + 1.05, r = .58, s = .72 }, { a = -PI / 2 - 1.1, r = .55, s = .66 }, { a = PI / 2 + .5, r = .5, s = .62 },
		{ a = .2, r = .78, s = .5 }, { a = PI - .2, r = .76, s = .48 } }
	for i, nu in ipairs(nuggets) do
		if lite and i > 3 then
			break
		end
		local pos, n = heapPoint(R, H, nu.a, R * nu.r)
		local cf = CF(pos - n * nu.s * .12) * alignY(n:Lerp(V(0, 1, 0), .5)) * ANG(0, rng:NextNumber(0, TAU), 0)
		pumpkin(m, cf, nu.s, rng, { Lite = true, NoLeaf = i % 2 == 0, Color = accent, Dark = accent:Lerp(C(120, 40, 10), .3) })
	end
	-- orange crystal cluster on the crown
	local crown = CF(0, H - .2, .3)
	for i = 1, (lite and 3 or 5) do
		local a = i / 5 * TAU
		local dir = (V(math.cos(a) * .45, 1, math.sin(a) * .45)).Unit
		local w = i == 1 and .95 or rng:NextNumber(.55, .8)
		local h = i == 1 and 2.9 or rng:NextNumber(1.5, 2.3)
		local base = crown * CF(math.cos(a) * (i == 1 and 0 or .6), 0, math.sin(a) * (i == 1 and 0 or .6))
		local body, tip, core = crystal(m, base * alignY(i == 1 and V(0, 1, 0) or dir) * ANG(0, rng:NextNumber(0, 6), 0), w, h, C(255, 146, 44),
			C(255, 214, 120), .1)
		stage(tip, 1 + i % 3)
		if i > 2 then
			stage(body, 3)
			stage(core, 3)
		end
	end
	-- ember speckles
	for i = 1, (lite and 4 or 10) do
		local pos, n = heapPoint(R, H, i * 2.4, R * rng:NextNumber(.3, .85), .05)
		local e = block(m, "Ember", V(.3, .1, .3), CF(pos) * alignY(n) * ANG(0, rng:NextNumber(0, 6), 0), C(255, 120, 30), M.Neon)
		anim(e, "Pulse", { HwPhase = rng:NextNumber(0, 6) })
		glow(e)
	end
	-- vines from the heart over the heap
	if not lite then
		for k = 1, 3 do
			local a0 = -PI / 2 + (k - 2) * .9
			local pts = {}
			for j = 0, 5 do
				local a = a0 + j * .3 * (k == 2 and 0 or (k - 2))
				local pos = heapPoint(R, H, a, R * (.9 - j * .13), .12)
				table.insert(pts, pos)
			end
			vine(m, rng, pts, lite)
		end
	end
	fxPoint(root, V(0, H + 1.2, .3), "Rise")
	fxPoint(root, V(0, 1.1, -3.6), "Core")
end

-- GRAVE STONE: a slate heap with broken tombstones standing in it, green ectoplasm bleeding from the cracks, green
-- crystals, candles and a stone dog skull
ORE.GraveStone = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 4.2, 2.8
	local accent = info.Accent
	heap(m, rng, { R = R, H = H, Rock = info.Rock, Rock2 = C(126, 128, 140), Mat = M.Slate, Lite = lite })
	veins(m, rng, R, H, lite and 2 or 4, accent)
	local stone, stoneDark = C(156, 156, 170), C(112, 114, 128)
	local engr = C(46, 46, 58)
	local slabs = {
		{ p = V(.2, 0, 1.1), w = 2.3, h = 4.6, lean = .12, yaw = .1 },
		{ p = V(-1.9, 0, -.7), w = 1.8, h = 3.4, lean = -.22, yaw = -.5 },
		{ p = V(2.0, 0, -.4), w = 1.7, h = 3.0, lean = -.3, yaw = .55 },
		{ p = V(-1.4, 0, 1.9), w = 1.5, h = 2.8, lean = .25, yaw = 2.4 },
	}
	for i, s in ipairs(slabs) do
		if lite and i > 3 then
			break
		end
		local r = math.sqrt(s.p.X * s.p.X + s.p.Z * s.p.Z)
		local baseY = heapY(R, H, r) - .9
		local face = CF(s.p.X, baseY + s.h / 2, s.p.Z) * ANG(0, s.yaw, 0) * CF(0, -s.h / 2, 0) * ANG(s.lean, 0, rng:NextNumber(-.1, .1)) * CF(0, s.h / 2, 0)
		local col = shade(rng, i % 2 == 0 and stoneDark or stone, .06)
		block(m, "Tombstone", V(s.w, s.h, .5), face, col, M.Slate, { Shadow = true })
		cyl(m, "TombstoneTop", .5, s.w, face * CF(0, s.h / 2, 0) * ANG(0, PI / 2, 0), col, M.Slate, { Shadow = true })
		block(m, "TombstoneRim", V(s.w + .16, .22, .62), face * CF(0, -s.h / 2 + .9, 0), col:Lerp(C(0, 0, 0), .15), M.Slate)
		-- engraved cross on the front (-Z of face)
		block(m, "Engraving", V(.18, s.h * .36, .06), face * CF(0, s.h * .16, -.26), engr, M.Slate)
		block(m, "Engraving", V(s.w * .44, .18, .06), face * CF(0, s.h * .24, -.26), engr, M.Slate)
		-- a crack bleeding ectoplasm
		local c0 = face * CF(-s.w * .32, -s.h * .02, -.27)
		local c1 = face * CF(s.w * .04, -s.h * .14, -.27)
		local c2 = face * CF(s.w * .34, -s.h * .06, -.27)
		glow(bar(m, "Ecto", c0.Position, c1.Position, .1, .06, accent, M.Neon))
		glow(bar(m, "Ecto", c1.Position, c2.Position, .09, .06, accent, M.Neon))
		local drip = c1 * CF(0, -.05, 0)
		glow(bar(m, "EctoDrip", drip.Position, drip.Position - V(0, .9, 0), .1, .1, accent, M.Neon))
		anim(ball(m, "EctoDrop", .22, CF(drip.Position - V(0, 1.0, 0)), accent, M.Neon), "Pulse", { HwPhase = i })
		block(m, "Moss", V(s.w * .55, .16, .58), face * CF(-s.w * .18, s.h / 2 + s.w * .38, 0) * ANG(0, 0, .25), C(70, 104, 62), M.Grass)
		stage(block(m, "Chip", V(.6, .5, .55), face * CF(s.w * .45, s.h * .42, 0) * ANG(.3, .2, .4), col, M.Slate), 1 + i % 3)
	end
	-- green crystal clusters between the stones
	local clusters = { { a = -PI / 2 + .35, r = .55 }, { a = PI / 2 + 1.0, r = .5 }, { a = .3, r = .62 } }
	for i, cl in ipairs(clusters) do
		if lite and i > 2 then
			break
		end
		local pos, n = heapPoint(R, H, cl.a, R * cl.r)
		for k = 1, 3 do
			local dir = (n + V(rng:NextNumber(-.5, .5), 1.1, rng:NextNumber(-.5, .5))).Unit
			local _, tip = crystal(m, CF(pos - n * .2) * alignY(dir), rng:NextNumber(.38, .58), rng:NextNumber(1.0, 1.8) * (k == 1 and 1.3 or 1),
				C(150, 255, 170), C(210, 255, 220), .14)
			stage(tip, k)
		end
	end
	-- the stone dog skull at the front base + ectoplasm pool
	local sp, sn = heapPoint(R, H, -PI / 2 - .3, R * .8, -.1)
	skull(m, CF(sp) * alignY(sn:Lerp(V(0, 1, 0), .6)) * ANG(-.15, -.2, 0) * CF(0, .3, 0), 1.0, C(170, 166, 160), accent)
	local pool = cyl(m, "EctoPool", .06, 1.8, CF(1.2, .08, -4.2) * ANG(0, 0, PI / 2), accent, M.Neon, { Transparency = .25 })
	anim(pool, "Pulse", { HwPhase = 2 })
	glow(pool)
	if not lite then
		for i, s in ipairs({ { a = -PI / 2 + .9, r = .82 }, { a = PI - .5, r = .7 }, { a = .7, r = .45 } }) do
			local p = heapPoint(R, H, s.a, R * s.r)
			local h = .55 + i * .18
			cyl(m, "Candle", h, .32, CF(p + V(0, h / 2 - .1, 0)) * ANG(0, 0, PI / 2), C(236, 226, 200), M.SmoothPlastic)
			local flame = ball(m, "CandleFlame", .24, CF(p + V(0, h + .06, 0)), C(255, 200, 110), M.Neon)
			anim(flame, "Flicker", { HwPhase = i })
		end
	end
	local lp = block(m, "GraveLight", V(.2, .2, .2), CF(0, 3.4, -2.2), accent, M.Neon, { Transparency = 1 })
	light(lp, accent, 15, 1.6)
	fxPoint(root, V(0, H + 1.5, 0), "Rise")
	fxPoint(root, V(0, 1.6, -3), "Core")
end

-- MOON SHARD: a dark basalt heap with violet veins, a crown of glowing crystal spires, a crescent moon floating above
-- and shards orbiting it
ORE.MoonShard = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 4.0, 3.2
	local accent = info.Accent
	heap(m, rng, { R = R, H = H, Rock = info.Rock, Rock2 = C(70, 50, 96), Mat = M.Basalt, Lite = lite })
	veins(m, rng, R, H, lite and 3 or 6, C(176, 96, 255))
	local glass = C(176, 110, 255)
	local core = C(236, 204, 255)
	local spires = {
		{ p = V(0, H - .3, 0), d = V(0, 1, 0), w = 1.35, h = 4.4 },
		{ p = V(.9, H - .6, .4), d = V(.5, 1, .2), w = .85, h = 2.9 },
		{ p = V(-.9, H - .6, .3), d = V(-.55, 1, .15), w = .9, h = 2.7 },
		{ p = V(.2, H - .5, -.9), d = V(.1, 1, -.55), w = .75, h = 2.3 },
		{ p = V(-.3, H - .6, 1.0), d = V(-.1, 1, .6), w = .7, h = 2.0 },
	}
	for i, s in ipairs(spires) do
		if lite and i > 3 then
			break
		end
		local body, tip, c = crystal(m, CF(s.p) * alignY(s.d) * ANG(0, rng:NextNumber(0, 6), 0), s.w, s.h, glass, core, .1)
		stage(tip, i == 1 and 3 or 1 + i % 2)
		if i > 1 then
			stage(body, 2)
			stage(c, 2)
		end
	end
	for i = 1, (lite and 3 or 6) do
		local a = i / 6 * TAU + .4
		local pos, n = heapPoint(R, H, a, R * rng:NextNumber(.5, .75))
		local dir = (n + V(0, .8, 0)).Unit
		local _, tip = crystal(m, CF(pos - n * .25) * alignY(dir) * ANG(0, rng:NextNumber(0, 6), 0), rng:NextNumber(.45, .7), rng:NextNumber(1.2, 2.0), glass,
			i % 2 == 0 and core or nil, .12)
		stage(tip, 1 + i % 3)
	end
	for i = 1, (lite and 4 or 12) do
		local pos, n = heapPoint(R, H, i * 2.1, R * rng:NextNumber(.25, .9), .06)
		local e = block(m, "Star", V(.16, .16, .16), CF(pos) * alignY(n) * ANG(PI / 4, i, PI / 4), C(255, 255, 255), M.Neon)
		anim(e, "Pulse", { HwPhase = i * .9 })
	end
	-- the crescent moon floating above the crown (faces -Z)
	local moonCF = CF(0, H + 7.2, 0)
	local seg = lite and 9 or 15
	local crescent = {}
	for i = 0, seg - 1 do
		local t0, t1 = i / seg, (i + 1) / seg
		local a0, a1 = PI * .4 + t0 * PI * 1.2, PI * .4 + t1 * PI * 1.2
		local mid = (t0 + t1) / 2
		local thick = .18 + .62 * math.sin(mid * PI)
		local r = 1.7 - thick * .5
		local p0 = V(math.cos(a0) * r, math.sin(a0) * r, 0)
		local p1 = V(math.cos(a1) * r, math.sin(a1) * r, 0)
		table.insert(crescent, bar(m, "Crescent", moonCF * p0, moonCF * p1, thick, .45, core, M.Neon))
	end
	for i = 0, (lite and 7 or 13) do
		local a = i / (lite and 8 or 14) * TAU
		local p0 = V(math.cos(a) * 2.25, math.sin(a) * 2.25, .2)
		local p1 = V(math.cos(a + .28) * 2.25, math.sin(a + .28) * 2.25, .2)
		table.insert(crescent, bar(m, "CrescentHalo", moonCF * p0, moonCF * p1, .1, .1, glass, M.Neon, { Transparency = .3 }))
	end
	for _, p in ipairs(crescent) do
		anim(p, "Bob", { HwAmp = .45, HwSpeed = 1.1, HwPhase = 0 })
		glow(p)
	end
	for i = 1, (lite and 3 or 6) do
		local a = i / 6 * TAU
		local r = 3.2 + (i % 2) * .7
		local p = block(m, "OrbitShard", V(.34, .95, .34), CF(math.cos(a) * r, H + 2.4 + (i % 3) * .55, math.sin(a) * r) * ANG(.4, a, .3), glass, M.Glass,
			{ Transparency = .05 })
		anim(p, "Orbit", { HwSpeed = .55 + (i % 3) * .12, HwPhase = a, HwAmp = .3 })
		glow(p)
	end
	local lp = block(m, "MoonLight", V(.2, .2, .2), CF(0, H + 2.2, -1), accent, M.Neon, { Transparency = 1 })
	light(lp, accent, 18, 1.9)
	fxPoint(root, V(0, H + 1.6, 0), "Rise")
	fxPoint(root, V(0, H + 7.2, 0), "Core")
end

---------------------------------------------------------------------------------------------------------------------
-- HAUNTED DIG SPOTS
---------------------------------------------------------------------------------------------------------------------
local SPOT = {}

-- CURSED SOIL: red-black heap, glowing red fissures, tiny red runes, dead roots, a ring of rune stones
SPOT.CursedSoil = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 3.3, 2.0
	local red = info.Accent
	mound(m, rng, { R = R, H = H, Soil = C(46, 16, 20), Soil2 = C(64, 20, 26), Clod = C(84, 26, 30), Mat = M.Ground, ClodMat = M.Mud,
		Lite = lite, Pebble = C(40, 34, 40) })
	-- glowing fissures running down from the top
	local cracks = lite and 3 or 6
	for k = 1, cracks do
		local a = k / cracks * TAU + rng:NextNumber(-.3, .3)
		local prev = nil
		for j = 0, 3 do
			local r = R * (.08 + j * .27)
			local pos = onDome(R, H, a + rng:NextNumber(-.25, .25), r, .03)
			if prev then
				local p = bar(m, "Fissure", prev, pos, .14 - j * .02, .1, j == 1 and red or red:Lerp(C(120, 10, 20), .3), M.Neon)
				glow(p)
				anim(p, "Pulse", { HwPhase = k })
			end
			prev = pos
		end
	end
	-- a boiling red crater in the crown
	local core = cyl(m, "CursedPool", .12, 1.9, CF(0, H - .02, 0) * ANG(0, 0, PI / 2), C(230, 40, 50), M.Neon)
	anim(core, "Pulse", { HwPhase = 0 })
	glow(core)
	for k = 1, (lite and 5 or 9) do
		local a = k / (lite and 5 or 9) * TAU
		local pos, n = onDome(R, H, a, 1.15, -.05)
		block(m, "CraterLip", V(.7, .45, .55), CF(pos) * alignY(n) * ANG(0, -a, .3), shade(rng, C(70, 22, 28), .1), M.Mud)
	end
	local bubble = ball(m, "CurseBubble", .5, CF(.3, H + .1, -.2), C(255, 90, 90), M.Neon, { Transparency = .2 })
	anim(bubble, "Pulse", { HwPhase = 2 })
	-- tiny runes on the heap
	for k = 1, (lite and 2 or 5) do
		local a = k / 5 * TAU + .4
		local pos, n = onDome(R, H, a, R * .55, .02)
		local cf = CF(pos) * alignY(n) * ANG(0, -a + PI / 2, 0)
		rune(m, cf, .42, red, k)
	end
	-- rune stones ringing the heap
	local stones = lite and 4 or 6
	for k = 1, stones do
		local a = k / stones * TAU + .3
		local r = R * 1.18
		local cf = CF(math.cos(a) * r, .14, math.sin(a) * r) * ANG(0, -a + PI / 2, 0) * ANG(rng:NextNumber(-.08, .08), 0, rng:NextNumber(-.08, .08))
		block(m, "RuneStone", V(1.05, .34, .78), cf, shade(rng, C(36, 30, 38), .08), M.Basalt, { Shadow = true })
		rune(m, cf * CF(0, .17, 0), .46, red, k + 2)
	end
	-- dead roots clawing out of the soil
	for k = 1, (lite and 2 or 4) do
		local a = k / 4 * TAU + 1.1
		local pos, n = onDome(R, H, a, R * .7)
		branch(m, rng, pos - n * .2, (n + V(0, 1.3, 0)).Unit, 2.2, .2, C(44, 30, 26))
	end
	local lp = block(m, "CursedLight", V(.2, .2, .2), CF(0, H + .6, 0), red, M.Neon, { Transparency = 1 })
	light(lp, C(255, 50, 50), 13, 1.6)
	fxPoint(root, V(0, H, 0), "Rise")
	fxPoint(root, V(0, .3, 0), "Ground")
end

-- GHOST SOIL: pale white-blue soil wrapped in ghost smoke rings, a little ghost rising out of it, wisps
SPOT.GhostSoil = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 3.2, 1.9
	local ghost = info.Accent
	mound(m, rng, { R = R, H = H, Soil = C(132, 150, 182), Soil2 = C(162, 180, 208), Clod = C(196, 210, 230), Mat = M.Sand, ClodMat = M.Snow,
		Lite = lite, Pebble = C(150, 160, 178) })
	-- ghost smoke puffs hugging the heap
	local puffs = lite and 5 or 9
	for i = 1, puffs do
		local a = i / puffs * TAU + rng:NextNumber(-.2, .2)
		local r = R * rng:NextNumber(.85, 1.05)
		local d = rng:NextNumber(1.3, 2.0)
		local puff = ball(m, "GhostMist", d, CF(math.cos(a) * r, d * .22, math.sin(a) * r), C(214, 236, 255), M.SmoothPlastic, { Transparency = .62 })
		anim(puff, "Pulse", { HwPhase = i * .8 })
	end
	-- blue cracks
	for k = 1, (lite and 3 or 5) do
		local a = k / 5 * TAU + rng:NextNumber(-.2, .2)
		local p0 = onDome(R, H, a, R * .25, .03)
		local p1 = onDome(R, H, a + .3, R * .6, .03)
		local p2 = onDome(R, H, a + .1, R * .88, .03)
		glow(bar(m, "GhostCrack", p0, p1, .11, .08, C(150, 220, 255), M.Neon))
		glow(bar(m, "GhostCrack", p1, p2, .09, .08, C(150, 220, 255), M.Neon))
	end
	-- the ghost (bobs, looks at -Z)
	local g = CF(0, H + 1.55, -.2)
	local body = C(232, 244, 255)
	local parts = {}
	table.insert(parts, ball(m, "GhostBody", 1.7, g, body, M.Glass, { Transparency = .28 }))
	table.insert(parts, ball(m, "GhostTail", 1.35, g * CF(0, -.75, .1), body, M.Glass, { Transparency = .34 }))
	table.insert(parts, ball(m, "GhostTail", .95, g * CF(.15, -1.35, .2), body, M.Glass, { Transparency = .42 }))
	table.insert(parts, ball(m, "GhostTail", .6, g * CF(.32, -1.8, .25), body, M.Glass, { Transparency = .5 }))
	for i = -1, 1, 2 do
		table.insert(parts, ball(m, "GhostEye", .36, g * CF(i * .3, .16, -.72), C(20, 26, 44), M.SmoothPlastic))
		table.insert(parts, ball(m, "GhostEyeShine", .1, g * CF(i * .3 + .06, .24, -.86), C(255, 255, 255), M.Neon))
		table.insert(parts, ball(m, "GhostArm", .45, g * CF(i * .86, -.25, -.1), body, M.Glass, { Transparency = .3 }))
	end
	table.insert(parts, ball(m, "GhostMouth", .3, g * CF(0, -.24, -.74), C(20, 26, 44), M.SmoothPlastic))
	local aura = ball(m, "GhostAura", 2.6, g * CF(0, -.3, 0), ghost, M.ForceField, { Transparency = .7 })
	table.insert(parts, aura)
	for _, p in ipairs(parts) do
		anim(p, "Bob", { HwAmp = .35, HwSpeed = 1.4, HwPhase = .5 })
	end
	local glowPart = block(m, "GhostLight", V(.2, .2, .2), g, ghost, M.Neon, { Transparency = 1 })
	anim(glowPart, "Bob", { HwAmp = .35, HwSpeed = 1.4, HwPhase = .5 })
	light(glowPart, C(140, 215, 255), 14, 1.7)
	-- wisps orbiting
	for i = 1, (lite and 2 or 5) do
		local a = i / 5 * TAU
		local w = ball(m, "Wisp", .32, CF(math.cos(a) * 2.6, 1.4 + (i % 2) * .7, math.sin(a) * 2.6), C(200, 240, 255), M.Neon)
		anim(w, "Orbit", { HwSpeed = .7 + i * .08, HwPhase = a, HwAmp = .35 })
	end
	-- an old wooden grave marker leaning at the back
	if not lite then
		local mk = CF(1.4, 1.2, 2.6) * ANG(.15, .4, .22)
		block(m, "Marker", V(.3, 2.6, .22), mk, C(92, 82, 74), M.WoodPlanks, { Shadow = true })
		block(m, "Marker", V(1.4, .28, .22), mk * CF(0, .6, 0), C(92, 82, 74), M.WoodPlanks)
	end
	fxPoint(root, V(0, H + .5, 0), "Rise")
	fxPoint(root, V(0, .3, 0), "Ground")
end

-- PUMPKIN PATCH: dark soil with half-buried pumpkins, a glowing jack-o'-lantern, vines and leaves
SPOT.PumpkinPatch = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 3.4, 1.4
	mound(m, rng, { R = R, H = H, Soil = C(56, 40, 30), Soil2 = C(72, 52, 38), Clod = C(88, 64, 44), Mat = M.Ground, ClodMat = M.Mud,
		Lite = lite, Pebble = C(70, 60, 54) })
	-- the jack-o'-lantern in front, the rest around
	local jackPos = onDome(R, H, -PI / 2, R * .32)
	local face = pumpkin(m, CF(jackPos - V(0, .45, 0)) * ANG(-.12, 0, 0), 1.25, rng, { Face = true, Lite = lite })
	if face then
		local lp = block(m, "JackLight", V(.2, .2, .2), face * CF(0, 0, -1), C(255, 150, 40), M.Neon, { Transparency = 1 })
		light(lp, C(255, 150, 40), 14, 2)
	end
	local others = {
		{ a = .35, r = .62, s = .92 }, { a = 2.4, r = .58, s = .78 }, { a = 1.35, r = .74, s = .55 }, { a = 3.6, r = .78, s = .48 },
	}
	for i, o in ipairs(others) do
		if lite and i > 2 then
			break
		end
		local pos, n = onDome(R, H, o.a, R * o.r)
		local p = pumpkin(m, CF(pos - V(0, o.s * .35, 0)) * alignY(n:Lerp(V(0, 1, 0), .6)) * ANG(0, rng:NextNumber(0, TAU), 0), o.s, rng,
			{ Lite = lite, NoLeaf = i == 3 })
		stage(p, i)
	end
	-- vines between them
	if not lite then
		for k = 1, 3 do
			local a0 = k / 3 * TAU + .5
			local pts = {}
			for j = 0, 5 do
				local a = a0 + j * .28
				local r = R * (.25 + j * .17)
				local pos = onDome(R, H, a, math.min(r, R * 1.05), .08)
				table.insert(pts, pos)
			end
			vine(m, rng, pts, lite)
		end
		-- big leaves on the ground
		for k = 1, 6 do
			local a = k / 6 * TAU + .2
			local pos = onDome(R, H, a, R * .95, .05)
			wedge(m, "PatchLeaf", V(.06, .7, 1.1), CF(pos + V(0, .1, 0)) * ANG(0, -a, 0) * ANG(0, 0, -1.25), shade(rng, LEAF, .12), M.SmoothPlastic)
		end
	end
	-- a tiny broken scarecrow stake
	if not lite then
		local st = CF(-2.3, 1.4, 2.1) * ANG(.1, .3, -.12)
		block(m, "Stake", V(.26, 2.8, .26), st, C(96, 70, 48), M.Wood, { Shadow = true })
		block(m, "Stake", V(1.8, .22, .22), st * CF(0, .7, 0) * ANG(0, 0, .1), C(96, 70, 48), M.Wood)
		ball(m, "StakeHead", .74, st * CF(0, 1.55, 0), C(196, 170, 110), M.Fabric)
		cyl(m, "StakeHatBrim", .08, 1.2, st * CF(0, 1.88, 0) * ANG(0, 0, PI / 2), C(34, 26, 40), M.Fabric)
		block(m, "StakeHat", V(.5, .62, .5), st * CF(.05, 2.18, 0) * ANG(0, .3, -.25), C(34, 26, 40), M.Fabric)
		block(m, "StakeHatBand", V(.54, .12, .54), st * CF(.02, 1.98, 0) * ANG(0, .3, -.1), C(255, 128, 24), M.Fabric)
	end
	fxPoint(root, V(0, 1.6, -1.2), "Core")
	fxPoint(root, V(0, H, 0), "Rise")
end

-- BONE GRAVE: a grave mound bristling with bones, a half-buried dog skull, mini tombstones, green glow
SPOT.BoneGrave = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 3.0, 1.5
	local accent = info.Accent
	mound(m, rng, { R = R, H = H, Soil = C(70, 56, 44), Soil2 = C(86, 70, 54), Clod = C(100, 82, 62), Mat = M.Ground, ClodMat = M.Mud,
		Lite = lite, Lumps = lite and 3 or 5, Pebble = C(110, 104, 100) })
	-- elongate: two extra caps along Z make it a grave shape
	for _, z in ipairs({ -1.7, 1.7 }) do
		local rs, cy = dome(2.3, 1.2)
		ball(m, "Mound", rs * 2, CF(0, cy, z), C(74, 60, 46), M.Ground)
	end
	-- headstones at the +Z end
	local stone = C(120, 118, 130)
	local heads = {
		{ p = V(0, 1.15, 3.6), w = 1.7, h = 2.2, r = .12, t = .08 },
		{ p = V(-2.0, .75, 2.9), w = 1.1, h = 1.4, r = -.25, t = .2 },
		{ p = V(1.95, .62, 3.1), w = 1.0, h = 1.2, r = .3, t = -.18 },
	}
	for i, s in ipairs(heads) do
		if lite and i > 1 then
			break
		end
		local cf = CF(s.p) * ANG(s.t, s.r, rng:NextNumber(-.1, .1))
		local col = shade(rng, stone, .08)
		block(m, "Headstone", V(s.w, s.h, .36), cf, col, M.Slate, { Shadow = true })
		cyl(m, "HeadstoneTop", .36, s.w, cf * CF(0, s.h / 2, 0) * ANG(0, PI / 2, 0), col, M.Slate, { Shadow = true })
		-- paw print engraving (front = -Z)
		local e = C(44, 44, 56)
		ball(m, "Paw", s.w * .3, cf * CF(0, s.h * .05, -.14), e, M.Slate)
		for k = -1, 1 do
			ball(m, "PawToe", s.w * .13, cf * CF(k * s.w * .17, s.h * .05 + s.w * .25 - math.abs(k) * s.w * .05, -.15), e, M.Slate)
		end
		block(m, "Moss", V(s.w * .7, .12, .44), cf * CF(.1, s.h / 2 + s.w * .44, 0), C(62, 92, 58), M.Grass)
	end
	-- bones sticking out
	local bones = {
		{ a = .4, r = .45, len = 1.9, up = .9 }, { a = 2.1, r = .55, len = 1.6, up = 1.1 }, { a = 3.5, r = .4, len = 2.0, up = .7 },
		{ a = 5.0, r = .62, len = 1.5, up = 1.2 }, { a = 1.3, r = .2, len = 1.4, up = 1.5 },
	}
	for i, b in ipairs(bones) do
		if lite and i > 3 then
			break
		end
		local pos, n = onDome(R, H, b.a, R * b.r)
		local dir = (n + V(math.cos(b.a + 1.2) * .6, b.up, math.sin(b.a + 1.2) * .6)).Unit
		local s = bone(m, pos - dir * .5, pos + dir * b.len, .24)
		stage(s, 1 + i % 3)
	end
	-- ribs arching out of the side
	if not lite then
		for k = 0, 3 do
			local z = -1.0 + k * .62
			local pts = {}
			for j = 0, 4 do
				local t = j / 4
				local ang = t * PI * .85
				table.insert(pts, V(1.2 + math.sin(ang) * 1.1, .4 + math.sin(ang) * 1.3 - t * .3, z + t * .15))
			end
			for j = 1, #pts - 1 do
				bar(m, "Rib", pts[j], pts[j + 1], .16, .16, j > 2 and BONE_DARK or BONE, M.SmoothPlastic)
			end
		end
		rod(m, "Spine", V(1.2, .5, -1.3), V(1.2, .5, 1.3), .26, BONE_DARK, M.SmoothPlastic)
	end
	-- the dog skull, half buried at the foot end
	skull(m, CF(-.6, .75, -2.6) * ANG(-.35, .5, .15), 1.25, BONE, accent)
	-- green ectoplasm
	local pool = cyl(m, "EctoPool", .06, 1.6, CF(.9, .1, -3.3) * ANG(0, 0, PI / 2), accent, M.Neon, { Transparency = .25 })
	anim(pool, "Pulse", { HwPhase = 1 })
	glow(pool)
	for k = 1, (lite and 2 or 4) do
		local a = k / 4 * TAU + .7
		local p0 = onDome(R, H, a, R * .2, .03)
		local p1 = onDome(R, H, a + .25, R * .62, .03)
		glow(bar(m, "EctoCrack", p0, p1, .1, .07, accent, M.Neon))
	end
	-- dead grass tufts
	for k = 1, (lite and 3 or 8) do
		local a = rng:NextNumber(0, TAU)
		local r = R * rng:NextNumber(.95, 1.25)
		wedge(m, "Tuft", V(.06, .55, .3), CF(math.cos(a) * r, .26, math.sin(a) * r) * ANG(0, rng:NextNumber(0, TAU), 0), C(84, 88, 54), M.Grass)
	end
	local lp = block(m, "GraveLight", V(.2, .2, .2), CF(0, 1.8, -1.6), accent, M.Neon, { Transparency = 1 })
	light(lp, accent, 12, 1.4)
	fxPoint(root, V(-.6, 1, -2.6), "Core")
	fxPoint(root, V(0, H, 0), "Rise")
end

-- CURSED TREASURE: a chest bursting out of dark earth, gold glow from the lid, purple rune circle, coins, chains
SPOT.CursedTreasure = function(m: Model, root: BasePart, rng, info, lite: boolean?)
	local R, H = 3.4, 1.5
	local purple = info.Accent
	local gold = info.Gold
	local goldDark = C(196, 140, 40)
	mound(m, rng, { R = R, H = H, Soil = C(44, 30, 40), Soil2 = C(60, 40, 54), Clod = C(74, 50, 62), Mat = M.Ground, ClodMat = M.Mud,
		Lite = lite, Pebble = C(60, 50, 64) })
	-- the chest (tilted toward the viewer at -Z)
	local chest = CF(0, H + .35, .1) * ANG(.22, 0, .05)
	local wood, woodDark = C(112, 70, 40), C(70, 42, 26)
	block(m, "Chest", V(3.0, 1.5, 2.0), chest, wood, M.WoodPlanks, { Shadow = true })
	for k = -1, 1, 2 do
		block(m, "ChestSeam", V(3.04, .08, 2.04), chest * CF(0, k * .35, 0), woodDark, M.Wood)
	end
	for _, x in ipairs({ -1.05, 1.05 }) do
		block(m, "ChestBand", V(.28, 1.56, 2.08), chest * CF(x, 0, 0), gold, M.Foil)
	end
	for _, c in ipairs({ { -1.45, -.95 }, { 1.45, -.95 }, { -1.45, .95 }, { 1.45, .95 } }) do
		block(m, "ChestCorner", V(.24, 1.58, .24), chest * CF(c[1], 0, c[2]), goldDark, M.Foil)
	end
	-- lock plate + glowing keyhole
	block(m, "Lock", V(.62, .72, .14), chest * CF(0, .2, -1.04), gold, M.Foil)
	local key = block(m, "Keyhole", V(.16, .3, .06), chest * CF(0, .18, -1.12), purple, M.Neon)
	glow(key)
	anim(key, "Pulse", { HwPhase = 0 })
	-- glow inside + gold heap seen through the open lid
	local inner = block(m, "ChestGlow", V(2.7, .1, 1.7), chest * CF(0, .74, 0), C(255, 220, 110), M.Neon)
	glow(inner)
	anim(inner, "Pulse", { HwPhase = 1.5 })
	for k = 1, (lite and 3 or 7) do
		ball(m, "GoldHeap", rng:NextNumber(.45, .7), chest * CF(rng:NextNumber(-1, 1), .8, rng:NextNumber(-.55, .55)), shade(rng, gold, .1), M.Foil)
	end
	-- lid hinged at the back top edge, opened a crack
	local hinge = chest * CF(0, .75, 1.0)
	local open = ANG(-.72, 0, 0)
	local lid = hinge * open
	local lidParts = {}
	table.insert(lidParts, block(m, "Lid", V(3.08, .42, 2.06), lid * CF(0, .21, -1.03), wood, M.WoodPlanks, { Shadow = true }))
	table.insert(lidParts, cyl(m, "LidTop", 3.08, 2.0, lid * CF(0, .42, -1.03) * ANG(0, 0, 0), wood:Lerp(woodDark, .2), M.WoodPlanks))
	for _, x in ipairs({ -1.05, 1.05 }) do
		table.insert(lidParts, cyl(m, "LidBand", .3, 2.1, lid * CF(x, .43, -1.03), gold, M.Foil))
	end
	table.insert(lidParts, block(m, "LidLip", V(3.1, .16, .22), lid * CF(0, .1, -2.05), goldDark, M.Foil))
	-- skull ornament on the lid
	skull(m, lid * CF(0, 1.32, -1.1) * ANG(-.1, 0, 0), .6, C(226, 214, 190), purple)
	for _, p in ipairs(lidParts) do
		anim(p, "Lid", { HwHinge = hinge.Position, HwAmp = .12 })
	end
	-- light fanning out of the crack
	if not lite then
		for k = 1, 4 do
			local x = -1.05 + (k - 1) * .7
			local ray = block(m, "GoldRay", V(.2, 2.2 + (k % 2) * .8, .05), chest * CF(x, 1.6 + (k % 2) * .4, -.35) * ANG(-.42, 0, x * -.28),
				C(255, 214, 90), M.Neon, { Transparency = .72 })
			glow(ray)
			anim(ray, "Pulse", { HwPhase = k })
		end
	end
	-- purple rune circle on the ground
	local ringR = R + .7
	local segs = lite and 16 or 28
	for k = 0, segs - 1 do
		local a0, a1 = k / segs * TAU, (k + .82) / segs * TAU
		local p = bar(m, "RuneCircle", V(math.cos(a0) * ringR, .06, math.sin(a0) * ringR), V(math.cos(a1) * ringR, .06, math.sin(a1) * ringR), .16, .05,
			purple, M.Neon)
		glow(p)
		anim(p, "Pulse", { HwPhase = k * .3 })
	end
	for k = 1, (lite and 3 or 6) do
		local a = k / 6 * TAU + .25
		local r = ringR - .55
		rune(m, CF(math.cos(a) * r, .04, math.sin(a) * r) * ANG(0, -a - PI / 2, 0), .46, purple, k)
	end
	-- coins scattered + small stacks
	for k = 1, (lite and 5 or 14) do
		local a = rng:NextNumber(0, TAU)
		local r = R * rng:NextNumber(.5, 1.15)
		local pos = onDome(R, H, a, math.min(r, R * .98), .04)
		if r > R then
			pos = V(math.cos(a) * r, .05, math.sin(a) * r)
		end
		cyl(m, "Coin", .09, .5, CF(pos) * ANG(rng:NextNumber(-.4, .4), rng:NextNumber(0, TAU), PI / 2 + rng:NextNumber(-.3, .3)), shade(rng, gold, .1), M.Foil)
	end
	if not lite then
		for _, base in ipairs({ V(-2.8, 0, -1.6), V(2.6, 0, -2.0) }) do
			for k = 0, 3 do
				cyl(m, "CoinStack", .1, .52, CF(base + V(rng:NextNumber(-.04, .04), .06 + k * .1, rng:NextNumber(-.04, .04))) * ANG(0, 0, PI / 2), gold, M.Foil)
			end
		end
	end
	-- gems
	for k = 1, (lite and 2 or 5) do
		local a = k / 5 * TAU + 1
		local pos = onDome(R, H, a, R * .75, .15)
		local g = block(m, "Gem", V(.42, .42, .42), CF(pos) * ANG(PI / 4, a, PI / 4), k % 2 == 0 and C(110, 230, 255) or purple, M.Glass, { Transparency = .05 })
		glow(g)
	end
	-- a chain draped from the chest to the ground
	if not lite then
		local a, b = chest * V(1.5, .5, -.6), V(3.2, .1, -1.4)
		for k = 0, 7 do
			local t = k / 7
			local p = a:Lerp(b, t) - V(0, math.sin(t * PI) * .5, 0)
			block(m, "ChainLink", V(.12, .32, .5), CF(p) * ANG(k % 2 == 0 and 0 or PI / 2, .4, 0), C(70, 66, 74), M.CorrodedMetal)
		end
	end
	-- floating cursed sparks
	for k = 1, (lite and 2 or 5) do
		local a = k / 5 * TAU
		local s = ball(m, "CurseSpark", .3, CF(math.cos(a) * 2.4, 2.6 + (k % 2) * .8, math.sin(a) * 2.4), k % 2 == 0 and gold or purple, M.Neon)
		anim(s, "Orbit", { HwSpeed = .8 + k * .07, HwPhase = a, HwAmp = .4 })
	end
	local lp = block(m, "TreasureLight", V(.2, .2, .2), chest * CF(0, 1.6, -.4), gold, M.Neon, { Transparency = 1 })
	light(lp, C(255, 200, 90), 16, 2.2)
	local lp2 = block(m, "CurseLight", V(.2, .2, .2), CF(0, .8, -2.6), purple, M.Neon, { Transparency = 1 })
	light(lp2, purple, 14, 1.6)
	fxPoint(root, V(0, H + 1.6, 0), "Core")
	fxPoint(root, V(0, .3, 0), "Ground")
	fxPoint(root, V(0, H + .4, 0), "Rise")
end

---------------------------------------------------------------------------------------------------------------------
-- public builders
---------------------------------------------------------------------------------------------------------------------
local function build(list, variant: string, seed: number?, opts: { [string]: any }?): Model?
	opts = opts or {}
	local info = Spots.Info[variant]
	local fn = list[variant]
	if not (info and fn) then
		return nil
	end
	local m, root = newModel("Hw" .. info.Kind .. "_" .. variant, variant, info)
	local rng = Random.new(math.floor(tonumber(seed) or 1) % 2147483646 + 1)
	fn(m, root, rng, info, opts.Lite == true)
	if opts.Facing then
		m:PivotTo(CFrame.Angles(0, opts.Facing, 0))
	end
	return m
end

function Spots.Ore(kindId: string, seed: number?, opts: { [string]: any }?): Model?
	return build(ORE, kindId, seed, opts)
end

function Spots.Spot(typeId: string, seed: number?, opts: { [string]: any }?): Model?
	return build(SPOT, typeId, seed, opts)
end

function Spots.Build(variant: string, seed: number?, opts: { [string]: any }?): Model?
	if ORE[variant] then
		return Spots.Ore(variant, seed, opts)
	end
	return Spots.Spot(variant, seed, opts)
end

-- hit points (model space). Ores: three turns over the rock heap like MiningModels.Ore; spots: over the dome.
local hitCache = {}
function Spots.HitPoints(variant: string): { { Pos: Vector3, Normal: Vector3 } }
	if hitCache[variant] then
		return hitCache[variant]
	end
	local info = Spots.Info[variant]
	local out = {}
	if info and info.Kind == "Ore" then
		local R, H = 4.1, (variant == "GraveStone" and 2.8 or variant == "MoonShard" and 3.2 or 3.8)
		for i = 1, 16 do
			local a = (i / 16) * TAU * 3
			local t = .3 + ((i - 1) % 4) * .17
			local pos, n = heapPoint(R, H, a, R * t, .35)
			table.insert(out, { Pos = pos, Normal = n })
		end
	else
		local R = (info and info.Radius or 3.6) * .85
		local H = (info and info.Height or 2.4) * .72
		for i = 1, 12 do
			local a = (i / 12) * TAU * 2
			local r = R * (.25 + ((i - 1) % 3) * .25)
			local pos, n = onDome(R, H, a, r, .1)
			table.insert(out, { Pos = pos, Normal = n })
		end
	end
	hitCache[variant] = out
	return out
end

return Spots
