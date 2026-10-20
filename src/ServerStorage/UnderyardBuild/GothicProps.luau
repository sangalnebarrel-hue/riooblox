-- THE UNDERYARD · crooked gothic prop kit of the district builders (ServerStorage.UnderyardBuild.GothicProps, WP-H3).
-- Build-time only: required by MourningMarsh / Undercrypt / BlackBellArena (and free for the other Underyard builders).
-- It returns no Build function, so tools/edits/40_underyard.luau skips it when it runs the builders.
-- Builds on HalloweenBuild.Kit (K) + YardKit (Y) and keeps their house style: anchored parts, collide / query / shadow
-- only when Solid, CanTouch false, every Light with Shadows = false, FX hooks as attributes (HwLantern on lantern glass,
-- HwCandle on flames, HwBrazier on brazier fire, UyLightAtSeal / UyShowAtSeal / UyHideAtSeal for the seal state, §7.3),
-- emitters only under a model flagged SelfManagedFX. Palette = DESIGN §7.1 (sickly green, violet, candle orange, moon
-- blue, bone, ink). Nothing here uses services or Roblox's Random: deterministic Y.Rng streams are passed in.
local K = require(script.Parent.Parent.HalloweenBuild.Kit)
local Y = require(script.Parent.Parent.HalloweenBuild.YardKit)
local C = Color3.fromRGB
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local G = {}
G.K, G.Y = K, Y

-- DESIGN §7.1 palette + the district materials shared by the three builders
G.Col = {
	Green = C(120, 255, 140), Violet = C(150, 80, 230), Candle = C(255, 170, 80), Moon = C(150, 200, 255),
	Bone = C(230, 222, 200), Ink = C(16, 12, 26),
	BoneDark = C(196, 184, 156), Iron = C(34, 32, 42), IronHi = C(58, 54, 70), Rust = C(98, 58, 44),
	Stone = C(86, 82, 98), StoneDark = C(56, 52, 66), StoneLight = C(122, 118, 136), Slate = C(44, 42, 54),
	Timber = C(78, 58, 44), TimberDark = C(52, 38, 32), Rope = C(120, 104, 80), Bronze = C(150, 108, 56),
	BronzeDark = C(108, 76, 42), Cloth = C(30, 22, 40), ClothViolet = C(70, 34, 100), Moss = C(78, 96, 72),
	VioletDim = C(92, 48, 150), MoonDim = C(70, 104, 170), GreenDim = C(60, 140, 80),
}
local COL = G.Col

-- deterministic RNG (YardKit Park-Miller x16807: identical in the build sim and in Studio)
function G.Rng(seed: number)
	return Y.Rng(seed)
end

-- fresh props tables (Kit mutates the props table it gets: never share one between calls)
function G.Solid(extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { Solid = true }
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end

function G.Props(extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = {}
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end

-- invisible blocker that keeps players on walkable ground (no query: the camera and clicks pass through it)
function G.Collider(parent: Instance, name: string, size: Vector3, cf: CFrame): BasePart
	local p = K.Part(parent, name, size, cf, COL.Ink, M.SmoothPlastic, { Solid = true, Transparency = 1, Shadow = false })
	p.CanQuery = false
	return p
end

-- invisible walkable floor (players stand on it; visible decking above / below it is decoration)
function G.Floor(parent: Instance, name: string, size: Vector3, cf: CFrame): BasePart
	return K.Part(parent, name, size, cf, COL.Ink, M.SmoothPlastic, { Solid = true, Transparency = 1, Shadow = false })
end

-- invisible collider wall along a ground line a -> b (height up from the higher of the two points)
function G.Fence(parent: Instance, a: Vector3, b: Vector3, height: number, thick: number?)
	local mid = (a + b) / 2
	local flat = V3(b.X - a.X, 0, b.Z - a.Z)
	local len = flat.Magnitude
	if len < .05 then
		return nil
	end
	local base = math.max(a.Y, b.Y)
	return G.Collider(parent, "Collider", V3(thick or 1, height, len + (thick or 1)),
		K.Look(V3(mid.X, base + height / 2, mid.Z), V3(b.X, base + height / 2, b.Z)))
end

-- a ring of straight segments in the XZ plane of cf (rims, rune rings, crater rings, rails). opts: Fill (share of each
-- step covered, 1), Phase (radians), Solid, Transparency, Name, Attrs, Jitter + Rng (random height / radius variation)
function G.Ring(parent: Instance, cf: CFrame, r: number, n: number, w: number, h: number, color: Color3, mat: Enum.Material,
	options: { [string]: any }?): { BasePart }
	local opts: { [string]: any } = options or {}
	local out = {}
	local fill = opts.Fill or 1
	local rng = opts.Rng
	for i = 1, n do
		local a0 = (i - 1) / n * PI * 2 + (opts.Phase or 0)
		local a1 = a0 + fill / n * PI * 2
		local am = (a0 + a1) / 2
		local rr = r + (rng and opts.Jitter and rng:NextNumber(-opts.Jitter, opts.Jitter) or 0)
		local chord = 2 * rr * math.sin((a1 - a0) / 2) + (fill >= 1 and w * .35 or 0)
		local hh = h + (rng and opts.HJitter and rng:NextNumber(0, opts.HJitter) or 0)
		local seg = cf * CF(math.cos(am) * rr, hh / 2, math.sin(am) * rr) * ANG(0, -am, 0)
		local props = opts.Solid and G.Solid() or G.Props()
		props.Transparency = opts.Transparency
		props.Attrs = opts.Attrs
		table.insert(out, K.Part(parent, opts.Name or "Ring", V3(w, hh, chord), seg, color, mat, props))
	end
	return out
end

-- a light dog bone (3 parts: shaft + one knob per end), along X of cf
function G.Bone(parent: Instance, cf: CFrame, len: number, color: Color3?): BasePart
	local col = color or COL.Bone
	local t = len * .2
	local shaft = K.CylX(parent, "Bone", len * .78, t, cf, col, M.SmoothPlastic)
	K.Ball(parent, "BoneKnob", t * 1.6, cf * CF(len * .42, 0, 0), col, M.SmoothPlastic)
	K.Ball(parent, "BoneKnob", t * 1.6, cf * CF(-len * .42, 0, 0), col, M.SmoothPlastic)
	return shaft
end

-- a dog skull (faces -Z of cf): cranium, snout, jaw, two sockets (Neon when eye is given)
function G.Skull(parent: Instance, cf: CFrame, s: number, eye: Color3?, bone: Color3?): BasePart
	local col = bone or COL.Bone
	local head = K.Ball(parent, "Skull", s, cf, col, M.SmoothPlastic)
	K.Part(parent, "SkullSnout", V3(s * .5, s * .38, s * .62), cf * CF(0, -s * .14, -s * .5), col:Lerp(COL.BoneDark, .3), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		K.Ball(parent, "SkullEye", s * .28, cf * CF(sx * s * .2, s * .06, -s * .4), eye or COL.Ink, eye and M.Neon or M.SmoothPlastic)
	end
	return head
end

-- skull lantern: a skull on a little bracket with a candle in its cranium; the glowing eyes carry HwLantern (client
-- flicker). opts: Light (range, false = none), Brightness, Kind ("Orange"|"Green"|"Purple"), Attrs (on the eye glow part)
function G.SkullLantern(parent: Instance, cf: CFrame, s: number, color: Color3, options: { [string]: any }?): Model
	local opts: { [string]: any } = options or {}
	local m = K.Model(parent, "SkullLantern")
	G.Skull(m, cf, s, color)
	local glow = K.Ball(m, "SkullGlow", s * .4, cf * CF(0, s * .05, -s * .05), color, M.Neon,
		{ Transparency = .35, Attrs = { HwLantern = opts.Kind or "Orange" } })
	for k, v in pairs(opts.Attrs or {}) do
		glow:SetAttribute(k, v)
	end
	K.CylY(m, "SkullCandle", s * .45, s * .16, cf * CF(0, s * .62, 0), COL.Bone:Lerp(COL.Candle, .2), M.SmoothPlastic)
	K.Ellipsoid(m, "CandleFlame", V3(s * .12, s * .22, s * .12), cf * CF(0, s * .95, 0), COL.Candle, M.Neon, { Attrs = { HwCandle = true } })
	if opts.Light ~= false then
		local l = K.Light(glow, color, opts.Light or 12, opts.Brightness or .9)
		l:SetAttribute("HwBaseBrightness", l.Brightness)
	end
	return m
end

-- chain of big alternating links from a to b with a parabolic sag. opts: Link (link length, 1.6), Thick (.28),
-- Width (.7), Color, Name ("ChainLink"), Material. Returns the link parts in order (a -> b).
function G.Chain(parent: Instance, a: Vector3, b: Vector3, sag: number, options: { [string]: any }?): { BasePart }
	local opts: { [string]: any } = options or {}
	local linkLen = opts.Link or 1.6
	local n = math.max(2, math.floor((b - a).Magnitude / (linkLen * .86) + .5))
	local out = {}
	local prev = a
	for i = 1, n do
		local t = i / n
		local p = a:Lerp(b, t) - V3(0, math.sin(t * PI) * sag, 0)
		local link = K.Bar(parent, opts.Name or "ChainLink", prev, p, opts.Thick or .28, opts.Width or .7, opts.Color or COL.Iron,
			opts.Material or M.CorrodedMetal)
		link.Size = V3(link.Size.X, link.Size.Y, link.Size.Z + (opts.Thick or .28) * 1.4) -- links overlap at the joints
		if i % 2 == 0 then
			link.CFrame = link.CFrame * ANG(0, 0, PI / 2)
		end
		table.insert(out, link)
		prev = p
	end
	return out
end

-- hanging cage lantern (hook point at `top`): cap, glass (Neon, HwLantern = kind), 4 bars, base. opts: Light (range,
-- false = none), Brightness, Attrs (on the glass: e.g. UyLightAtSeal), Scale
function G.CageLantern(parent: Instance, top: CFrame, color: Color3, kind: string, options: { [string]: any }?): Model
	local opts: { [string]: any } = options or {}
	local s = opts.Scale or 1
	local m = K.Model(parent, "HwLantern")
	K.CylY(m, "LanternHook", .5 * s, .14 * s, top * CF(0, -.25 * s, 0), COL.Iron, M.CorrodedMetal)
	K.Wedge(m, "LanternRoof", V3(1.2 * s, .5 * s, .6 * s), top * CF(0, -.75 * s, -.3 * s), COL.Iron, M.CorrodedMetal)
	K.Wedge(m, "LanternRoof", V3(1.2 * s, .5 * s, .6 * s), top * CF(0, -.75 * s, .3 * s) * ANG(0, PI, 0), COL.Iron, M.CorrodedMetal)
	local glass = K.Part(m, "LanternGlass", V3(.8 * s, 1.2 * s, .8 * s), top * CF(0, -1.65 * s, 0), color, M.Neon,
		{ Attrs = { HwLantern = kind } })
	for k, v in pairs(opts.Attrs or {}) do
		glass:SetAttribute(k, v)
	end
	for _, x in ipairs({ -.45, .45 }) do
		for _, z in ipairs({ -.45, .45 }) do
			K.Part(m, "LanternFrame", V3(.1 * s, 1.35 * s, .1 * s), top * CF(x * s, -1.65 * s, z * s), COL.Iron, M.CorrodedMetal)
		end
	end
	K.Part(m, "LanternBase", V3(1.0 * s, .2 * s, 1.0 * s), top * CF(0, -2.35 * s, 0), COL.Iron, M.CorrodedMetal)
	if opts.Light ~= false then
		local l = K.Light(glass, color, opts.Light or 16, opts.Brightness or 1)
		l:SetAttribute("HwBaseBrightness", l.Brightness)
	end
	return m
end

-- crooked iron lamp post: leaning shaft in two kinked segments, a curled arm and a hanging cage lantern.
-- base = ground CFrame (the arm reaches along -Z of base). opts: as CageLantern + Solid (post collides, default true)
function G.LampPost(parent: Instance, base: CFrame, height: number, color: Color3, kind: string, rng, options: { [string]: any }?): Model
	local opts: { [string]: any } = options or {}
	local m = K.Model(parent, "LampPost")
	local p0 = base.Position
	local lean = base:VectorToWorldSpace(V3(rng:NextNumber(-.12, .12), 1, rng:NextNumber(.02, .1))).Unit
	local p1 = p0 + lean * height * .55
	local kink = base:VectorToWorldSpace(V3(rng:NextNumber(-.15, .15), 1, rng:NextNumber(-.12, .02))).Unit
	local p2 = p1 + kink * height * .45
	K.Part(m, "LampFoot", V3(1.4, .5, 1.4), base * CF(0, .25, 0), COL.Iron, M.CorrodedMetal, opts.Solid ~= false and G.Solid() or nil)
	K.Rod(m, "LampShaft", p0, p1, .42, COL.Iron, M.CorrodedMetal, opts.Solid ~= false and G.Solid() or nil)
	K.Ball(m, "LampKnot", .55, CF(p1), COL.IronHi, M.CorrodedMetal)
	K.Rod(m, "LampShaft", p1, p2, .34, COL.Iron, M.CorrodedMetal)
	local fwd = base:VectorToWorldSpace(V3(0, 0, -1))
	local tip = p2 + fwd * 2.2 + V3(0, .5, 0)
	K.Rod(m, "LampArm", p2, p2 + fwd * 1.2 + V3(0, .7, 0), .22, COL.Iron, M.CorrodedMetal)
	K.Rod(m, "LampArm", p2 + fwd * 1.2 + V3(0, .7, 0), tip, .22, COL.Iron, M.CorrodedMetal)
	K.Ball(m, "LampFinial", .4, CF(p2 + V3(0, .35, 0)), COL.IronHi, M.CorrodedMetal)
	G.CageLantern(m, CF(tip) * ANG(0, rng:NextNumber(-.3, .3), 0), color, kind, opts)
	Y.AttachAt(K.Part(m, "LampPerch", V3(.2, .2, .2), CF(p2 + V3(0, .6, 0)), COL.Iron, nil, { Transparency = 1 }), "CrowPerch",
		p2 + V3(0, .7, 0))
	return m
end

-- tattered banner on a crooked pole (cloth hangs in the XY plane of base, facing -Z): pole, crossbar with finials,
-- 3 cloth strips with ragged ends, a Neon sigil (bell or eye). opts: Sigil ("Bell"|"Eye"|"Paw"), Glow (sigil colour),
-- Attrs (on the sigil parts)
function G.Banner(parent: Instance, base: CFrame, height: number, cloth: Color3, rng, options: { [string]: any }?): Model
	local opts: { [string]: any } = options or {}
	local m = K.Model(parent, "Banner")
	local tilt = ANG(rng:NextNumber(-.05, .05), 0, rng:NextNumber(-.06, .06))
	local pole = base * tilt
	K.Part(m, "BannerFoot", V3(1.6, .6, 1.6), base * CF(0, .3, 0), COL.StoneDark, M.Slate, G.Solid())
	K.CylY(m, "BannerPole", height, .36, pole * CF(0, height / 2, 0), COL.Iron, M.CorrodedMetal, G.Solid())
	local barY = height - .8
	local w = math.max(3, height * .28)
	K.CylX(m, "BannerBar", w + 1, .26, pole * CF(0, barY, 0), COL.Iron, M.CorrodedMetal)
	for _, sx in ipairs({ -1, 1 }) do
		K.Wedge(m, "BannerFinial", V3(.2, .6, .3), pole * CF(sx * (w / 2 + .5), barY, 0) * ANG(0, 0, sx * -PI / 2), COL.IronHi, M.CorrodedMetal)
	end
	K.Ball(m, "BannerTop", .55, pole * CF(0, height + .2, 0), COL.IronHi, M.CorrodedMetal)
	local clothH = height * .48
	local strips = 3
	for i = 1, strips do
		local x = (i - (strips + 1) / 2) * (w / strips)
		local len = clothH * rng:NextNumber(.82, 1)
		K.Part(m, "BannerCloth", V3(w / strips + .02, len, .08), pole * CF(x, barY - .15 - len / 2, -.18) * ANG(rng:NextNumber(-.03, .03), 0, 0),
			cloth:Lerp(COL.Ink, rng:NextNumber(0, .25)), M.Fabric)
		K.Wedge(m, "BannerTatter", V3(w / strips * .5, .9, .08), pole * CF(x - w / strips * .25, barY - .15 - len - .45, -.18) * ANG(0, 0, PI),
			cloth:Lerp(COL.Ink, .2), M.Fabric)
	end
	local glow = opts.Glow or COL.Violet
	local sc = pole * CF(0, barY - clothH * .42, -.26)
	G.Rune(m, sc, opts.Sigil or "Bell", math.min(w * .62, 2.6), glow, { Depth = .06, Attrs = opts.Attrs, Name = "BannerSigil" })
	return m
end

-- scattered rubble around a centre (flat stones, max height `maxH`). opts: Color, Solid, Min/Max (size)
function G.Rubble(parent: Instance, centre: CFrame, radius: number, n: number, rng, maxH: number, options: { [string]: any }?)
	local opts: { [string]: any } = options or {}
	local col = opts.Color or COL.StoneDark
	for _ = 1, n do
		local a = rng:NextNumber(0, PI * 2)
		local r = math.sqrt(rng:NextNumber()) * radius
		local sx = rng:NextNumber(opts.Min or .5, opts.Max or 1.6)
		local sh = math.min(maxH, sx * rng:NextNumber(.35, .7))
		local cf = centre * CF(math.cos(a) * r, sh * .45, math.sin(a) * r) * ANG(rng:NextNumber(-.25, .25), rng:NextNumber(0, PI), rng:NextNumber(-.25, .25))
		K.Part(parent, "Rubble", V3(sx, sh, sx * rng:NextNumber(.6, 1.1)), cf, col:Lerp(COL.Slate, rng:NextNumber(0, .5)), M.Slate,
			opts.Solid and G.Solid() or nil)
	end
end

-- rune glyphs: strokes in a unit square (x right, y up), drawn as bars on the XY plane of cf (proud of it by Depth / 2,
-- towards -Z of cf). Original DOGROTS glyphs: Arrow, Fork, Eye, Moon, Bone, Paw, Bell, Hook, Star.
local GLYPHS = {
	Arrow = { { 0, -.5, 0, .5 }, { 0, .5, -.32, .18 }, { 0, .5, .32, .18 }, { -.2, -.32, .2, -.32 } },
	Fork = { { 0, -.5, 0, .5 }, { 0, .1, -.34, .46 }, { 0, .1, .34, .46 }, { -.22, -.5, .22, -.5 } },
	Eye = { { -.42, 0, 0, .3 }, { 0, .3, .42, 0 }, { .42, 0, 0, -.3 }, { 0, -.3, -.42, 0 }, { -.07, 0, .07, 0 } },
	Moon = { { .18, .48, -.14, .3 }, { -.14, .3, -.26, 0 }, { -.26, 0, -.14, -.3 }, { -.14, -.3, .18, -.48 }, { .18, .48, .04, 0 }, { .04, 0, .18, -.48 } },
	Bone = { { -.36, -.42, .36, .42 }, { -.36, .42, .36, -.42 }, { -.46, -.3, -.24, -.5 }, { .24, .5, .46, .3 } },
	Paw = { { -.08, -.32, .08, -.32 }, { -.22, -.16, .22, -.16 }, { -.3, .16, -.22, .26 }, { -.06, .34, .06, .34 }, { .22, .26, .3, .16 } },
	Bell = { { -.3, -.36, .3, -.36 }, { -.22, -.36, -.16, .22 }, { .22, -.36, .16, .22 }, { -.16, .22, 0, .38 }, { 0, .38, .16, .22 }, { -.05, -.5, .05, -.5 } },
	Hook = { { -.3, .46, -.3, -.2 }, { -.3, -.2, 0, -.46 }, { 0, -.46, .3, -.2 }, { .3, -.2, .3, .1 }, { -.3, .16, .1, .16 } },
	Star = { { 0, -.48, 0, .48 }, { -.42, -.24, .42, .24 }, { -.42, .24, .42, -.24 } },
}
G.GlyphNames = { "Arrow", "Fork", "Eye", "Moon", "Bone", "Paw", "Bell", "Hook", "Star" }

-- opts: Width (stroke width share, .14), Depth (.1), Transparency, Material (Neon), Attrs, Name. Returns the parts.
function G.Rune(parent: Instance, cf: CFrame, kind: string, size: number, color: Color3, options: { [string]: any }?): { BasePart }
	local opts: { [string]: any } = options or {}
	local strokes = GLYPHS[kind] or GLYPHS.Star
	local w = size * (opts.Width or .14)
	local d = opts.Depth or .1
	local out = {}
	for _, s in ipairs(strokes) do
		local a = cf * V3(s[1] * size, s[2] * size, -d / 2)
		local b = cf * V3(s[3] * size, s[4] * size, -d / 2)
		local len = (b - a).Magnitude + w
		local mid = (a + b) / 2
		local ang = math.atan2(s[4] - s[2], s[3] - s[1])
		local part = K.Part(parent, opts.Name or "Rune", V3(len, w, d), CF(mid) * (cf - cf.Position) * ANG(0, 0, ang), color, opts.Material or M.Neon,
			{ Transparency = opts.Transparency, Attrs = opts.Attrs })
		table.insert(out, part)
	end
	return out
end

-- glowing flower (Neon petals): stem, `petals` petals around a bright core. base = ground point
function G.Flower(parent: Instance, base: CFrame, height: number, color: Color3, rng, petals: number?)
	local top = base * CF(rng:NextNumber(-.25, .25), height, rng:NextNumber(-.25, .25))
	K.Bar(parent, "FlowerStem", base.Position, top.Position, .1, .1, C(56, 84, 62), M.SmoothPlastic)
	local n = petals or 4
	local spin = rng:NextNumber(0, PI)
	for i = 1, n do
		local a = spin + i / n * PI * 2
		K.Part(parent, "FlowerPetal", V3(.34, .06, .62), CF(top.Position) * ANG(0, a, 0) * CF(0, .05, -.3) * ANG(.45, 0, 0), color, M.Neon,
			{ Transparency = .1 })
	end
	K.Ball(parent, "FlowerCore", .24, CF(top.Position + V3(0, .1, 0)), color:Lerp(C(255, 255, 255), .55), M.Neon)
end

-- emitter host part inside a SelfManagedFX model: invisible, no collision / query / touch
function G.EmitterPart(parent: Instance, name: string, size: Vector3, cf: CFrame): BasePart
	local p = K.Part(parent, name, size, cf, COL.Ink, M.SmoothPlastic, { Transparency = 1, Shadow = false })
	return p
end

local function seq(points: { { number } }): NumberSequence
	local kps = {}
	for _, p in ipairs(points) do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end
G.Seq = seq

-- low drifting fog (smoke texture, Box volume emission over the host part). opts: Color, Color2, Rate, Size {a, b},
-- Lifetime {a, b}, Transparency (min, .8), Rise (upward acceleration)
function G.Fog(host: BasePart, options: { [string]: any }?): ParticleEmitter
	local opts: { [string]: any } = options or {}
	local e = Instance.new("ParticleEmitter")
	e.Name = "Fog"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(opts.Color or COL.Moon, opts.Color2 or COL.MoonDim)
	e.LightEmission = opts.LightEmission or .25
	e.LightInfluence = .35
	local s = opts.Size or { 7, 15 }
	e.Size = seq({ { 0, s[1] }, { 1, s[2] } })
	local tmin = opts.Transparency or .8
	e.Transparency = seq({ { 0, 1 }, { .25, tmin }, { .7, tmin + .04 }, { 1, 1 } })
	local lt = opts.Lifetime or { 9, 14 }
	e.Lifetime = NumberRange.new(lt[1], lt[2])
	e.Rate = opts.Rate or 1.2
	e.Speed = NumberRange.new(.2, .7)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = V3(0, opts.Rise or .04, 0)
	e.Drag = .5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-6, 6)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = false
	e.Parent = host
	return e
end

-- brazier / torch fire (fire texture, rising). opts: Color, Color2, Rate, Size
function G.Fire(host: BasePart, options: { [string]: any }?): ParticleEmitter
	local opts: { [string]: any } = options or {}
	local e = Instance.new("ParticleEmitter")
	e.Name = "Fire"
	e.Texture = "rbxasset://textures/particles/fire_main.dds"
	e.Color = ColorSequence.new(opts.Color or COL.Candle, opts.Color2 or C(200, 60, 30))
	e.LightEmission = .85
	e.LightInfluence = 0
	local s = opts.Size or 2.2
	e.Size = seq({ { 0, s }, { .6, s * .7 }, { 1, s * .2 } })
	e.Transparency = seq({ { 0, .35 }, { .7, .55 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(.6, 1.1)
	e.Rate = opts.Rate or 14
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(12, 12)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = V3(0, 2, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = host
	return e
end

-- sparks / motes rising (sparkles texture). opts: Color, Rate, Size, Speed
function G.Motes(host: BasePart, options: { [string]: any }?): ParticleEmitter
	local opts: { [string]: any } = options or {}
	local e = Instance.new("ParticleEmitter")
	e.Name = "Motes"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(opts.Color or COL.Violet)
	e.LightEmission = 1
	e.LightInfluence = 0
	local s = opts.Size or .35
	e.Size = seq({ { 0, s }, { 1, 0 } })
	e.Transparency = seq({ { 0, 1 }, { .2, .2 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(2.5, 4.5)
	e.Rate = opts.Rate or 3
	e.Speed = NumberRange.new(opts.Speed or .6, (opts.Speed or .6) * 2)
	e.SpreadAngle = Vector2.new(35, 35)
	e.EmissionDirection = Enum.NormalId.Top
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = host
	return e
end

-- SelfManagedFX holder model (ParticleGovernor / WorldDetailQuality contract, DESIGN §17)
function G.FXModel(parent: Instance, name: string): Model
	local m = K.Model(parent, name)
	m:SetAttribute("SelfManagedFX", true)
	return m
end

-- counts for ctx.Note
function G.Count(root: Instance): (number, number, number)
	local parts, lights, emitters = 0, 0, 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	return parts, lights, emitters
end

-- horizontal distance helper
function G.Flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

------------------------------------------------------------------------------------------------------------------
-- Cooperation with the world framework builders that run earlier (Ground Order 10, Roads Order 20): when they have
-- laid a district base / bridge / approach deck, a district builder builds on top of it instead of duplicating floors.
------------------------------------------------------------------------------------------------------------------

-- the framework's base model for a district (a descendant carrying UyDistrictBase = name), or nil when absent
function G.DistrictBase(root: Instance, name: string): Instance?
	for _, d in ipairs(root:GetDescendants()) do
		if d:GetAttribute("UyDistrictBase") == name then
			return d
		end
	end
	return nil
end

-- every BasePart called `name` under root (skipping the subtree `exclude`)
function G.Named(root: Instance, name: string, exclude: Instance?): { BasePart }
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == name and not (exclude and d:IsDescendantOf(exclude)) then
			table.insert(out, d)
		end
	end
	return out
end

-- the bridge deck parts of the framework's spoke into a district (model with attribute Gate = name)
function G.BridgeDeck(root: Instance, name: string): { BasePart }
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("Gate") == name then
			for _, p in ipairs(d:GetDescendants()) do
				if p:IsA("BasePart") and p.CanCollide and string.find(p.Name, "Deck", 1, true) then
					table.insert(out, p)
				end
			end
		end
	end
	return out
end

-- top of the highest block deck part covering (x, z) (rotated / sloped segments handled in their own frame), or nil
function G.DeckTop(deck: { BasePart }, x: number, z: number): number?
	local best = nil
	for _, p in ipairs(deck) do
		local isBlock = p:IsA("Part") and (p :: Part).Shape == Enum.PartType.Block
		if isBlock then
			local cf, s = p.CFrame, p.Size
			local lp = cf:PointToObjectSpace(Vector3.new(x, cf.Position.Y, z))
			if math.abs(lp.X) <= s.X / 2 and math.abs(lp.Z) <= s.Z / 2 then
				local top = (cf * Vector3.new(lp.X, s.Y / 2, lp.Z)).Y
				if best == nil or top > best then
					best = top
				end
			end
		end
	end
	return best
end

-- polyline helpers (XZ): total length and the point + unit direction at distance s
function G.PathLength(pts: { Vector3 }): number
	local total = 0
	for i = 2, #pts do
		total += G.Flat(pts[i - 1], pts[i])
	end
	return total
end

function G.PathAt(pts: { Vector3 }, s: number): (Vector3, Vector3)
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local len = G.Flat(a, b)
		if len > 1e-6 and (acc + len >= s or i == #pts) then
			local t = math.clamp((s - acc) / len, 0, 1)
			local p = a:Lerp(b, t)
			return Vector3.new(p.X, 0, p.Z), Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		end
		acc += len
	end
	local last = pts[#pts]
	return Vector3.new(last.X, 0, last.Z), Vector3.new(0, 0, 1)
end

return G
