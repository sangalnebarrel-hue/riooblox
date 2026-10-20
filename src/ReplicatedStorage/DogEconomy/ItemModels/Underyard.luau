-- THE UNDERYARD showcase finds (Halloween Chapter II, docs/halloween2/DESIGN.md §9.8): Black Coffin, Crooked Door and
-- first-coffin rewards that no depth ever rolls (ItemDefinitions UNDERYARD_FINDS). Each recipe builds one find around
-- the origin, resting on Y = 0, front towards -Z, 2-2.6 studs tall, so it reads in a showcase case, on a reward card
-- and in the coffin reveal. b:Accent marks the parts mutations recolour; b:Detail holds the small work the Lod 1
-- silhouette skips. The showcase look (StarterPlayerScripts.PlotCosmetics, also usable by any reveal):
--   model attribute ShowcaseAura = Color3     the find's own glow colour (soft disc under it, glint colour)
--   model attribute ShowcaseMotif = "Wisp" | "Ember"   optional slow rising trail
--   part attribute ShowcaseGlint = true       sparkle spots (the first three are used)
-- Palette of the Underyard: ink, bone, moon blue, violet, sickly green, candle orange, funeral blue.
local V3 = Vector3.new
local CN = CFrame.new
local rad, cos, sin = math.rad, math.cos, math.sin

local function ang(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(rad(x), rad(y or 0), rad(z or 0))
end
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local INK = rgb(18, 14, 26)
local IRON = rgb(64, 62, 72)
local RUST = rgb(132, 76, 50)
local BRONZE = rgb(160, 120, 64)
local GOLD_OLD = rgb(198, 160, 82)
local SILVER = rgb(196, 202, 214)
local SILVER_D = rgb(132, 138, 152)
local BONE = rgb(232, 224, 204)
local BONE_D = rgb(196, 184, 160)
local PORCELAIN = rgb(236, 232, 222)
local WAX = rgb(238, 228, 206)
local WOOD = rgb(62, 44, 48)
local SOIL = rgb(56, 44, 42)
local MOSS = rgb(78, 104, 66)
local VELVET = rgb(70, 34, 96)
local SATIN = rgb(132, 92, 178)
local SEPIA = rgb(178, 150, 112)
local SEPIA_D = rgb(112, 88, 62)
local ROSE = rgb(64, 112, 232)
local ROSE_D = rgb(36, 66, 170)
local LEAF = rgb(46, 84, 58)
local VIOLET = rgb(170, 100, 255)
local MAGENTA = rgb(222, 92, 255)
local MOON = rgb(170, 212, 255)
local SPIRIT = rgb(150, 236, 255)
local GHOST = rgb(130, 255, 150)
local CANDLE = rgb(255, 170, 80)
local CANDLE_CORE = rgb(255, 236, 170)

local GLINT = { Attributes = { ShowcaseGlint = true } }

-- The find's showcase look (see the header).
local function showcase(b: any, aura: Color3, motif: string?)
	b.Model:SetAttribute("ShowcaseAura", aura)
	if motif then
		b.Model:SetAttribute("ShowcaseMotif", motif)
	end
end

-- A CFrame at `at` whose LookVector points at `target` (fromMatrix: the same in Roblox and Lune).
local function look(at: Vector3, target: Vector3): CFrame
	local dir = target - at
	if dir.Magnitude < 1e-6 then
		return CN(at)
	end
	dir = dir.Unit
	local up = if math.abs(dir.Y) > 0.98 then V3(0, 0, -1) else V3(0, 1, 0)
	local right = dir:Cross(up).Unit
	return CFrame.fromMatrix(at, right, right:Cross(dir))
end
-- Round rod from a to c.
local function rod(b: any, a: Vector3, c: Vector3, d: number, color: Color3, mat: string?, props: any?): BasePart
	return b:Cyl(math.max((c - a).Magnitude, 0.02), d, look((a + c) / 2, c) * ang(0, 90, 0), color, mat, props)
end
-- Square bar from a to c (cracks, hands, forged iron).
local function bar(b: any, a: Vector3, c: Vector3, w: number, color: Color3, mat: string?, props: any?): BasePart
	return b:Box(V3(w, w, math.max((c - a).Magnitude, 0.02)), look((a + c) / 2, c), color, mat, props)
end
-- Organic segment: an ellipsoid of diameter d stretched from a to c (fingers, snouts, petals).
local function blob(b: any, a: Vector3, c: Vector3, d: number, color: Color3, mat: string?, over: number?, props: any?): BasePart
	return b:Ellipsoid(V3(d, d, (c - a).Magnitude + d * (over or 0.5)), look((a + c) / 2, c), color, mat, props)
end
-- Arc of rods in the local XY plane of cf (angles in degrees from local +X towards +Y).
local function arc(b: any, cf: CFrame, r: number, d: number, a0: number, a1: number, n: number, color: Color3, mat: string?): { BasePart }
	local out = {}
	local step = (a1 - a0) / n
	for i = 1, n do
		local t0, t1 = rad(a0 + step * (i - 1)), rad(a0 + step * i)
		local p0 = cf:PointToWorldSpace(V3(cos(t0) * r, sin(t0) * r, 0))
		local p1 = cf:PointToWorldSpace(V3(cos(t1) * r, sin(t1) * r, 0))
		local mid, dir = (p0 + p1) / 2, (p1 - p0).Unit
		local half = (p1 - p0).Magnitude / 2 + d * 0.3
		table.insert(out, rod(b, mid - dir * half, mid + dir * half, d, color, mat))
	end
	return out
end
-- A heart shape in the XY plane of cf (two lobes and a turned square), s wide, t thick.
local function heart(b: any, cf: CFrame, s: number, t: number, color: Color3, mat: string?, props: any?): { BasePart }
	return {
		b:Ellipsoid(V3(0.56 * s, 0.56 * s, t), cf * CN(-0.22 * s, 0.14 * s, 0), color, mat, props),
		b:Ellipsoid(V3(0.56 * s, 0.56 * s, t), cf * CN(0.22 * s, 0.14 * s, 0), color, mat, props),
		b:Box(V3(0.5 * s, 0.5 * s, t * 0.9), cf * CN(0, -0.12 * s, 0) * ang(0, 0, 45), color, mat, props),
	}
end
-- A chain of links along pts (alternating link planes).
local function chain(b: any, pts: { Vector3 }, size: number, color: Color3, mat: string?)
	for i = 1, #pts - 1 do
		local a, c = pts[i], pts[i + 1]
		b:Ellipsoid(V3(size * 0.5, size * 0.22, (c - a).Magnitude + size * 0.3), look((a + c) / 2, c) * ang(0, 0, (i % 2) * 90), color, mat)
	end
end

local R = {}

------------------------------------------------------------------------------------------------
-- Common
------------------------------------------------------------------------------------------------

-- Coffin Nail: a crooked hand-forged nail driven through a splintered coffin plank with a brass handle and a strip of
-- violet satin; the wood glows violet where the nail went in.
R.uy_coffin_nail = function(b: any, lod: number)
	showcase(b, VIOLET)
	local plank = CN(0, 0.17, 0.05) * ang(0, -8, 0)
	b:Box(V3(2.3, 0.34, 1.0), plank, WOOD, "WoodPlanks")
	b:Box(V3(2.2, 0.06, 0.2), plank * CN(0, 0.19, 0.38), SATIN, "Fabric")
	b:Box(V3(0.9, 0.08, 0.08), plank * CN(-0.35, 0.02, -0.62), BRONZE, "Metal")
	for _, x in { -0.75, 0.05 } do
		b:Box(V3(0.1, 0.1, 0.16), plank * CN(x, 0.02, -0.55), BRONZE, "Metal")
	end
	local entry = (plank * CN(0.25, 0.17, -0.05)).Position
	b:Accent(b:Ellipsoid(V3(0.5, 0.06, 0.46), CN(entry + V3(0, 0.01, 0)), VIOLET, "Neon"))
	local bend = entry + V3(0.32, 1.25, -0.04)
	local tip = bend + V3(-0.3, 0.72, -0.06)
	bar(b, entry - V3(0, 0.1, 0), bend, 0.17, IRON, "Metal")
	bar(b, bend, tip, 0.15, IRON, "Metal")
	b:Box(V3(0.48, 0.48, 0.12), look(tip, tip + (tip - bend).Unit), IRON, "Metal", GLINT)
	b:Accent(bar(b, entry + V3(0, 0.02, 0), entry:Lerp(bend, 0.22), 0.2, VIOLET, "Neon", GLINT))
	b:Detail(function()
		-- rust bands on the shaft
		bar(b, entry:Lerp(bend, 0.38), entry:Lerp(bend, 0.5), 0.19, RUST, "Metal")
		bar(b, bend:Lerp(tip, 0.42), bend:Lerp(tip, 0.52), 0.17, RUST, "Metal")
		for i, x in { -1.05, 1.05 } do
			b:Wedge(V3(0.9, 0.3, 0.36), plank * CN(x, 0.05, (i - 1.5) * 0.5) * ang(0, x > 0 and -90 or 90, 0), WOOD, "WoodPlanks")
		end
		for i = 0, 1 do
			b:Box(V3(2.1, 0.03, 0.04), plank * CN(0, 0.17, -0.3 + i * 0.32), rgb(44, 30, 34), "WoodPlanks")
		end
		-- a second, smaller bent nail lying on the plank
		local n0 = (plank * CN(-0.6, 0.22, 0.05)).Position
		bar(b, n0, n0 + V3(0.5, 0.02, -0.18), 0.08, IRON, "Metal")
		bar(b, n0 + V3(0.5, 0.02, -0.18), n0 + V3(0.62, 0.2, -0.24), 0.08, IRON, "Metal")
		b:Box(V3(0.2, 0.05, 0.2), CN(n0 - V3(0.03, 0, -0.01)), IRON, "Metal")
	end)
end

-- Black Feather: a long glossy raven feather standing in grave soil, its curved vane catching a violet-blue sheen,
-- a bone-white quill and downy barbs at the base.
R.uy_black_feather = function(b: any, lod: number)
	showcase(b, rgb(120, 110, 255))
	local FEATHER = rgb(24, 22, 34)
	local SHEEN = rgb(92, 76, 200)
	b:Ellipsoid(V3(1.05, 0.38, 0.85), CN(0, 0.08, 0), SOIL, "Ground")
	local function at(t: number): Vector3
		return V3(0.3 * t * t - 0.05 * t, 0.12 + 2.45 * t, 0.06 * t)
	end
	local function tangent(t: number): Vector3
		return (at(math.min(1, t + 0.02)) - at(math.max(0, t - 0.02))).Unit
	end
	local n = if lod > 0 then 3 else 5
	for i = 1, n do
		local t0, t1 = (i - 1) / n, i / n
		rod(b, at(t0), at(t1) + tangent(t1) * 0.02, 0.1 - 0.05 * t0, if t0 < 0.15 then BONE else FEATHER, "SmoothPlastic")
	end
	-- the vane: three long flat blades following the shaft (smooth outline), the outer side wider than the inner
	local function vanePiece(t: number, w: number, h: number, color: Color3, x: number, z: number, props: any?): BasePart
		local d = tangent(t)
		local cf = CN(at(t)) * CFrame.Angles(0, 0, -math.atan2(d.X, d.Y)) * CN(x, 0, z)
		return b:Ellipsoid(V3(w, h, 0.05), cf, color, "SmoothPlastic", props)
	end
	vanePiece(0.42, 0.8, 1.45, FEATHER, 0.06, 0)
	vanePiece(0.68, 0.66, 1.25, FEATHER, 0.05, 0.005)
	vanePiece(0.88, 0.36, 0.68, FEATHER, 0.02, 0.01)
	b:Accent(vanePiece(0.45, 0.42, 1.0, SHEEN, 0.1, -0.03, { Transparency = 0.3 }))
	b:Accent(vanePiece(0.7, 0.3, 0.8, SHEEN, 0.08, -0.03, { Transparency = 0.3, Attributes = { ShowcaseGlint = true } }))
	b:Detail(function()
		-- a few split barbs on the edge and soft down at the base
		for i, t in { 0.32, 0.5, 0.62 } do
			local s = if i == 2 then -1 else 1
			local d = tangent(t)
			local cf = CN(at(t)) * CFrame.Angles(0, 0, -math.atan2(d.X, d.Y)) * CN(s * (0.36 + (i % 2) * 0.04), -0.06, 0) * ang(0, 0, s * 38)
			b:Ellipsoid(V3(0.3, 0.07, 0.04), cf, FEATHER, "SmoothPlastic")
		end
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.26, 0.2, 0.1), CN(at(0.12) + V3(s * 0.12, 0, 0)) * ang(0, 0, s * -30), rgb(62, 58, 78), "SmoothPlastic")
		end
		b:Ball(0.2, CN(0.32, 0.18, -0.28), rgb(96, 92, 104), "Slate")
	end)
end

-- Wax Hand: a pale wax hand rising from a puddle of wax, fingers spread, a wick and a small flame on every fingertip.
R.uy_wax_hand = function(b: any, lod: number)
	showcase(b, CANDLE, "Ember")
	local WAX_D = rgb(214, 202, 176)
	b:Ellipsoid(V3(1.7, 0.14, 1.45), CN(0, 0.05, 0), WAX, "SmoothPlastic")
	b:Ellipsoid(V3(0.85, 0.12, 0.6), CN(0.55, 0.08, -0.35), WAX_D, "SmoothPlastic")
	b:Ellipsoid(V3(0.6, 1.25, 0.5), CN(0, 0.6, 0.05) * ang(-6, 0, 4), WAX, "SmoothPlastic")
	local palm = CN(0.02, 1.34, 0) * ang(-6, 0, 2)
	b:Ellipsoid(V3(0.92, 0.84, 0.34), palm, WAX, "SmoothPlastic")
	local tips = {}
	local fingers = { { -0.3, -16, 0.6 }, { -0.1, -5, 0.72 }, { 0.1, 5, 0.7 }, { 0.3, 15, 0.56 } }
	for _, f in fingers do
		local base = (palm * CN(f[1], 0.32, 0)).Position
		local dir = (palm * ang(0, 0, -f[2])).UpVector
		local knuckle = base + dir * f[3] * 0.55 - V3(0, 0, 0.04)
		local tip = knuckle + (dir + V3(0, 0, -0.18)).Unit * f[3] * 0.48
		blob(b, base, knuckle, 0.21, WAX, "SmoothPlastic", 0.6)
		blob(b, knuckle, tip, 0.18, WAX, "SmoothPlastic", 0.6)
		table.insert(tips, tip)
	end
	local thumbBase = (palm * CN(0.42, -0.1, -0.04)).Position
	local thumbMid = thumbBase + V3(0.26, 0.24, -0.06)
	local thumbTip = thumbMid + V3(0.12, 0.26, -0.08)
	blob(b, thumbBase, thumbMid, 0.23, WAX, "SmoothPlastic", 0.6)
	blob(b, thumbMid, thumbTip, 0.19, WAX, "SmoothPlastic", 0.6)
	table.insert(tips, thumbTip)
	for i, tip in tips do
		b:CylY(0.12, 0.035, CN(tip + V3(0, 0.1, 0)), INK, "SmoothPlastic")
		b:Accent(b:Ellipsoid(V3(0.1, 0.22, 0.1), CN(tip + V3(0, 0.27, 0)), CANDLE, "Neon", if i == 2 or i == 5 then GLINT else nil))
	end
	b:Detail(function()
		for _, p in { V3(-0.28, 1.15, -0.17), V3(0.12, 0.95, -0.2), V3(0.3, 0.6, -0.2) } do
			b:Ellipsoid(V3(0.1, 0.34, 0.08), CN(p), WAX_D, "SmoothPlastic")
		end
		for _, tip in { tips[2], tips[3] } do
			b:Ball(0.06, CN(tip + V3(0, 0.36, 0)), CANDLE_CORE, "Neon")
		end
	end)
end

-- Crooked House Key: a big bronze key with a bow shaped like a crooked little house (its window glowing), turned in
-- the lock of a crooked Crooked Row door.
R.uy_crooked_house_key = function(b: any, lod: number)
	showcase(b, rgb(255, 196, 96))
	local DOOR = rgb(74, 58, 80)
	local KEY = rgb(176, 136, 70)
	local door = CN(0, 0, 0.35) * ang(0, 0, 4)
	b:Box(V3(1.6, 0.14, 0.62), CN(0, 0.07, 0.3), rgb(70, 66, 76), "Slate")
	b:Box(V3(1.3, 2.15, 0.16), door * CN(0, 1.2, 0), DOOR, "WoodPlanks")
	b:Box(V3(0.14, 2.3, 0.22), door * CN(-0.72, 1.2, 0), WOOD, "Wood")
	b:Box(V3(0.14, 2.3, 0.22), door * CN(0.72, 1.2, 0), WOOD, "Wood")
	b:Box(V3(1.62, 0.18, 0.26), door * CN(0.06, 2.4, 0) * ang(0, 0, -7), WOOD, "Wood")
	b:Accent(b:Ellipsoid(V3(0.42, 0.22, 0.06), door * CN(0, 1.9, -0.09), CANDLE, "Neon"))
	b:Box(V3(0.32, 0.46, 0.05), door * CN(0, 1.0, -0.1), BRONZE, "Metal")
	-- the key: shaft into the lock, two collars and the house-shaped bow facing the viewer
	local keyhole = (door * CN(0, 0.98, -0.13)).Position
	local mid = keyhole + V3(0.03, 0.02, -0.38)
	local front = keyhole + V3(-0.02, 0.0, -0.78)
	rod(b, keyhole, mid, 0.14, KEY, "Metal")
	rod(b, mid, front, 0.14, KEY, "Metal")
	for _, z in { -0.5, -0.66 } do
		b:CylZ(0.06, 0.26, CN(keyhole + V3(0, 0, z)), KEY, "Metal")
	end
	local bow = CN(front + V3(0, 0.02, -0.06)) * ang(0, 0, -6)
	local w, h = 0.66, 0.5
	b:Box(V3(w, 0.11, 0.1), bow * CN(0, -0.28, 0), KEY, "Metal")
	for _, s in { -1, 1 } do
		b:Box(V3(0.11, h, 0.1), bow * CN(s * (w / 2 - 0.05), -0.05, 0), KEY, "Metal")
		bar(b, (bow * CN(s * (w / 2 + 0.06), 0.18, 0)).Position, (bow * CN(0.04, 0.56, 0)).Position, 0.11, KEY, "Metal", GLINT)
	end
	b:Box(V3(0.1, 0.22, 0.1), bow * CN(0.2, 0.42, 0), KEY, "Metal")
	b:Accent(b:Box(V3(0.22, 0.24, 0.05), bow * CN(0, -0.02, 0.01), CANDLE, "Neon"))
	b:Detail(function()
		b:Box(V3(0.08, 0.16, 0.06), door * CN(0, 0.98, -0.11), INK, "SmoothPlastic")
		for _, y in { 0.5, 1.9 } do
			b:Box(V3(0.42, 0.1, 0.04), door * CN(-0.48, y, -0.1), IRON, "Metal")
		end
		rod(b, (bow * CN(-0.3, -0.25, 0)).Position, (bow * CN(-0.5, -0.62, -0.05)).Position, 0.025, BONE_D, "Fabric")
		b:Box(V3(0.3, 0.2, 0.02), bow * CN(-0.52, -0.74, -0.05) * ang(0, 0, 12), SEPIA, "SmoothPlastic")
	end)
end

-- Blue Funeral Rose: a single blue rose in a little black funeral urn, thorns, two leaves, glowing dew drops and a
-- black ribbon tied around its stem.
R.uy_blue_funeral_rose = function(b: any, lod: number)
	showcase(b, rgb(90, 140, 255))
	b:CylY(0.12, 0.62, CN(0, 0.06, 0), INK, "Metal")
	b:Ellipsoid(V3(0.68, 0.62, 0.68), CN(0, 0.42, 0), INK, "SmoothPlastic")
	b:CylY(0.24, 0.34, CN(0, 0.8, 0), INK, "SmoothPlastic")
	b:Disc(CN(0, 0.93, 0), 0.46, 0.06, INK, "Metal")
	local stemMid = V3(-0.05, 1.45, 0)
	local top = V3(0.08, 2.0, -0.02)
	rod(b, V3(0, 0.85, 0), stemMid, 0.07, LEAF, "SmoothPlastic")
	rod(b, stemMid, top, 0.065, LEAF, "SmoothPlastic")
	for _, l in { { At = stemMid + V3(0.2, -0.12, 0), Tilt = 35 }, { At = stemMid + V3(-0.2, 0.18, 0), Tilt = -30 } } do
		b:Ellipsoid(V3(0.38, 0.05, 0.2), CN(l.At) * ang(0, 0, l.Tilt), LEAF, "SmoothPlastic")
	end
	-- the bloom: sepals, an outer cup of five petals, three inner petals and the bud
	local bloom = CN(top + V3(0, 0.2, 0))
	for i = 0, 2 do
		local a = rad(i * 120 + 20)
		b:Ellipsoid(V3(0.1, 0.06, 0.3), bloom * CN(cos(a) * 0.16, -0.17, sin(a) * 0.16) * ang(0, -math.deg(a) + 90, 0) * ang(28, 0, 0), LEAF, "SmoothPlastic")
	end
	for i = 0, 4 do
		local a = rad(i * 72)
		b:Ellipsoid(V3(0.36, 0.34, 0.13), bloom * CN(cos(a) * 0.17, 0.02, sin(a) * 0.17) * ang(0, -math.deg(a) - 90, 0) * ang(-22, 0, 0), ROSE, "SmoothPlastic")
	end
	for i = 0, 2 do
		local a = rad(i * 120 + 40)
		b:Ellipsoid(V3(0.26, 0.28, 0.11), bloom * CN(cos(a) * 0.08, 0.1, sin(a) * 0.08) * ang(0, -math.deg(a) - 90, 0) * ang(-12, 0, 0), ROSE_D, "SmoothPlastic")
	end
	b:Accent(b:Ball(0.2, bloom * CN(0, 0.16, 0), ROSE_D, "SmoothPlastic"))
	b:Accent(b:Ball(0.07, bloom * CN(0.14, 0.12, -0.17), SPIRIT, "Neon", GLINT))
	b:Accent(b:Ball(0.06, CN(stemMid + V3(0.27, -0.09, -0.04)), SPIRIT, "Neon", GLINT))
	b:Detail(function()
		for i, y in { 1.1, 1.38, 1.7 } do
			local s = if i % 2 == 0 then -1 else 1
			b:Wedge(V3(0.03, 0.08, 0.1), CN(-0.04 + s * 0.04, y, 0) * ang(0, s * 90, 0), LEAF, "SmoothPlastic")
		end
		b:CylY(0.04, 0.7, CN(0, 0.42, 0), SILVER_D, "Metal")
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.2, 0.12, 0.06), CN(s * 0.12, 1.05, -0.04) * ang(0, 0, s * -25), INK, "Fabric")
		end
		b:Box(V3(0.06, 0.32, 0.03), CN(0.05, 0.9, -0.06) * ang(0, 0, 12), INK, "Fabric")
	end)
end

------------------------------------------------------------------------------------------------
-- Rare
------------------------------------------------------------------------------------------------

-- Bottled Whisper: a round corked flask with a violet wax seal; inside, a pale ghost whisper curls up in a spiral.
R.uy_bottled_whisper = function(b: any, lod: number)
	showcase(b, SPIRIT, "Wisp")
	local GLASS = rgb(196, 226, 255)
	b:CylY(0.06, 0.9, CN(0, 0.03, 0), GLASS, "Glass", { Transparency = 0.45 })
	b:Ball(1.3, CN(0, 0.68, 0), GLASS, "Glass", { Transparency = 0.62, Attributes = { ShowcaseGlint = true } })
	b:CylY(0.62, 0.36, CN(0, 1.56, 0), GLASS, "Glass", { Transparency = 0.5 })
	b:Disc(CN(0, 1.88, 0), 0.44, 0.08, GLASS, "Glass", { Transparency = 0.35 })
	b:CylY(0.34, 0.3, CN(0, 2.02, 0), rgb(150, 112, 74), "Wood")
	b:Accent(b:Ellipsoid(V3(0.46, 0.2, 0.46), CN(0, 2.2, 0), VIOLET:Lerp(INK, 0.35), "SmoothPlastic"))
	-- the whisper: a glowing core and a spiral of wisp puffs rising through the flask
	b:Accent(b:Ball(0.34, CN(0, 0.55, 0), SPIRIT, "Neon", { Transparency = 0.3, Attributes = { ShowcaseGlint = true } }))
	local n = if lod > 0 then 4 else 7
	for i = 1, n do
		local t = (i - 1) / (n - 1)
		local a = t * math.pi * 3.2
		local r = 0.34 - t * 0.2
		local p = V3(cos(a) * r, 0.32 + t * 1.15, sin(a) * r)
		local nxt = V3(cos(a + 0.6) * r, 0.32 + t * 1.15 + 0.12, sin(a + 0.6) * r)
		b:Accent(b:Ellipsoid(V3(0.15 - t * 0.06, 0.15 - t * 0.06, 0.3), look(p, nxt), SPIRIT, "Neon", { Transparency = 0.2 + t * 0.35 }))
	end
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.07, 0.2, 0.07), CN(s * 0.16, 2.05, -0.1), VIOLET:Lerp(INK, 0.35), "SmoothPlastic")
		end
		rod(b, V3(0.18, 1.62, -0.08), V3(0.52, 1.25, -0.2), 0.025, BONE_D, "Fabric")
		b:Box(V3(0.4, 0.28, 0.03), CN(0.6, 1.08, -0.22) * ang(0, -20, -8), SEPIA, "SmoothPlastic")
	end)
end

-- Broken Pocket Watch: a silver watch on its edge with the lid flung open, cracked glass, hands stopped at midnight,
-- a gear spilled beside it and the chain coiled on the ground.
R.uy_broken_pocket_watch = function(b: any, lod: number)
	showcase(b, rgb(200, 220, 255))
	local W = CN(0, 1.08, 0.05) * ang(-10, 0, 0)
	b:CylZ(0.28, 1.9, W, SILVER, "Metal")
	b:CylZ(0.08, 2.0, W * CN(0, 0, -0.13), SILVER_D, "Metal")
	b:CylZ(0.06, 1.62, W * CN(0, 0, -0.16), rgb(240, 234, 216), "SmoothPlastic")
	local face = W * CN(0, 0, -0.2)
	b:Box(V3(0.08, 0.44, 0.03), face * CN(0.02, 0.2, 0) * ang(0, 0, -4), INK, "SmoothPlastic")
	b:Box(V3(0.06, 0.64, 0.03), face * CN(-0.02, 0.3, -0.01) * ang(0, 0, 3), INK, "SmoothPlastic")
	b:Ball(0.1, face * CN(0, 0, -0.02), INK, "Metal")
	b:CylZ(0.04, 1.62, W * CN(0, 0, -0.23), rgb(220, 240, 255), "Glass", { Transparency = 0.72 })
	b:Accent(b:Box(V3(0.025, 0.5, 0.02), face * CN(0.46, -0.2, -0.05) * ang(0, 0, 28), rgb(190, 226, 255), "Glass", { Transparency = 0.15 }))
	b:Accent(b:Box(V3(0.025, 0.34, 0.02), face * CN(0.36, -0.5, -0.05) * ang(0, 0, -52), rgb(190, 226, 255), "Glass", { Transparency = 0.15 }))
	b:Accent(b:Box(V3(0.025, 0.26, 0.02), face * CN(0.58, -0.44, -0.05) * ang(0, 0, 70), rgb(190, 226, 255), "Glass", { Transparency = 0.15 }))
	-- crown and bow ring
	b:CylY(0.18, 0.16, W * CN(0, 1.04, 0), SILVER, "Metal")
	b:Accent(b:Ball(0.24, W * CN(0, 1.18, 0), SILVER, "Metal", GLINT))
	arc(b, W * CN(0, 1.45, 0), 0.22, 0.07, 0, 360, if lod > 0 then 4 else 6, SILVER, "Metal")
	-- the cover snapped off its hinge and leans against the back; a sprung coil sticks out of the case
	local lid = W * CN(-0.42, -0.12, 0.58) * ang(-16, 24, 0)
	b:CylZ(0.12, 1.9, lid, SILVER, "Metal")
	b:Box(V3(0.12, 0.3, 0.14), W * CN(-0.98, 0.05, 0.08), SILVER_D, "Metal")
	local coil = W * CN(0.86, -0.42, -0.02)
	rod(b, coil.Position, (coil * CN(0.32, -0.08, -0.06)).Position, 0.04, GOLD_OLD, "Metal")
	rod(b, (coil * CN(0.32, -0.08, -0.06)).Position, (coil * CN(0.3, 0.12, -0.12)).Position, 0.04, GOLD_OLD, "Metal")
	b:Detail(function()
		b:CylZ(0.03, 1.4, lid * CN(0, 0, 0.07), SILVER_D, "Metal")
		for i = 0, 3 do
			local a = rad(i * 90)
			b:Box(V3(0.05, 0.14, 0.03), face * CN(sin(a) * 0.66, cos(a) * 0.66, 0) * ang(0, 0, -i * 90), INK, "SmoothPlastic")
		end
		-- a spilled gear
		local gear = CN(0.95, 0.04, -0.55) * ang(0, 20, 0)
		b:Disc(gear, 0.46, 0.06, GOLD_OLD, "Metal")
		for i = 0, 5 do
			local a = rad(i * 60)
			b:Box(V3(0.1, 0.06, 0.1), gear * CN(cos(a) * 0.25, 0, sin(a) * 0.25) * ang(0, -i * 60, 0), GOLD_OLD, "Metal")
		end
	end)
	-- the chain from the bow down around the watch and coiled in front
	local top = (W * CN(0, 1.66, 0)).Position
	chain(b, { top, top + V3(0.45, -0.1, -0.1), V3(1.05, 1.2, -0.15), V3(1.15, 0.5, -0.25), V3(0.8, 0.07, -0.5), V3(0.2, 0.07, -0.7), V3(-0.5, 0.07, -0.6), V3(-0.9, 0.07, -0.25) }, 0.22, SILVER_D, "Metal")
end

-- Lost Veil: a bridal veil hanging from a crown of white flowers on an iron stand; a faint ghost face looks out from
-- under it, and one end drifts aside as if something breathed.
R.uy_lost_veil = function(b: any, lod: number)
	showcase(b, rgb(214, 232, 255), "Wisp")
	local VEIL = rgb(246, 246, 255)
	b:CylY(0.1, 1.2, CN(0, 0.05, 0.05), IRON, "Metal")
	b:CylY(0.1, 0.7, CN(0, 0.15, 0.05), IRON, "Metal")
	rod(b, V3(0, 0.15, 0.05), V3(0, 2.2, 0.05), 0.07, IRON, "Metal")
	-- the veil: a back sheet, four folds fanning out from the crown and one end drifting aside
	b:Ellipsoid(V3(1.1, 2.0, 0.34), CN(0.03, 1.2, 0.2), VEIL, "Fabric", { Transparency = 0.5 })
	for i, x in { -0.33, -0.11, 0.11, 0.33 } do
		local depth = -0.04 - (0.33 - math.abs(x)) * 0.25
		b:Ellipsoid(V3(0.42, 1.95, 0.16), CN(x * 0.75, 1.2, depth) * ang(0, 0, x * 26) * CN(x * 0.3, 0, 0), VEIL, "Fabric", { Transparency = if i % 2 == 0 then 0.46 else 0.4 })
	end
	b:Ellipsoid(V3(0.26, 1.5, 0.1), CN(0.62, 1.38, 0.0) * ang(0, 0, -38), VEIL, "Fabric", { Transparency = 0.5 })
	-- the ghost under it
	b:Accent(b:Ellipsoid(V3(0.6, 0.72, 0.42), CN(0, 1.86, 0), SPIRIT, "Neon", { Transparency = 0.55 }))
	for _, x in { -0.13, 0.13 } do
		b:Ellipsoid(V3(0.12, 0.18, 0.06), CN(x, 1.94, -0.2), INK, "SmoothPlastic")
	end
	-- the flower crown
	local crown = CN(0, 2.24, 0.04) * ang(-12, 0, 0)
	for i = 0, 6 do
		local a = rad(i * (360 / 7))
		local p = crown * CN(cos(a) * 0.34, 0, sin(a) * 0.34)
		b:Ball(0.2, p, if i % 3 == 1 then rgb(214, 226, 255) else rgb(250, 250, 255), "SmoothPlastic", if i == 0 or i == 4 then GLINT else nil)
	end
	for _, a in { 50, 230 } do
		b:Ellipsoid(V3(0.24, 0.05, 0.12), crown * CN(cos(rad(a)) * 0.36, 0.05, sin(rad(a)) * 0.36) * ang(0, -a, 0), LEAF, "SmoothPlastic")
	end
	b:Detail(function()
		for i = 0, 3 do
			local a = rad(i * 90 + 45)
			b:Ball(0.08, crown * CN(cos(a) * 0.36, 0.08, sin(a) * 0.36), rgb(255, 250, 240), "SmoothPlastic")
		end
		b:Ellipsoid(V3(1.3, 0.07, 0.42), CN(0.02, 0.27, 0.0), rgb(226, 230, 245), "Fabric", { Transparency = 0.3 })
	end)
end

-- Cracked Bell Clapper: the heavy iron tongue of a bell, cracked through with violet light, a broken chain link in its
-- eye, standing on a curved shard of the bronze bell it broke.
R.uy_cracked_bell_clapper = function(b: any, lod: number)
	showcase(b, VIOLET)
	for i = 0, 2 do
		local a = rad(200 + i * 22)
		b:Box(V3(0.62, 0.16, 0.66), CN(cos(a) * 0.9 + 0.75, 0.09 + i * 0.04, sin(a) * 0.6 + 0.1) * ang(0, -math.deg(a) - 90, 8 + i * 6), BRONZE, "Metal")
	end
	b:Accent(b:Box(V3(0.66, 0.05, 0.05), CN(-0.12, 0.17, -0.42) * ang(0, -20, 10), VIOLET, "Neon"))
	local C = CN(0.05, 0, 0) * ang(0, 0, -6)
	b:Ball(0.5, C * CN(0, 0.2, 0), IRON, "Metal")
	b:Ellipsoid(V3(0.86, 1.06, 0.86), C * CN(0, 0.68, 0), IRON, "Metal")
	b:Ellipsoid(V3(0.42, 0.62, 0.42), C * CN(0, 1.24, 0), IRON, "Metal")
	b:CylY(0.08, 0.5, C * CN(0, 1.42, 0), BRONZE, "Metal")
	b:CylY(0.8, 0.22, C * CN(0, 1.84, 0), IRON, "Metal")
	arc(b, C * CN(0, 2.43, 0), 0.22, 0.1, -60, 240, if lod > 0 then 5 else 8, IRON, "Metal")
	-- a broken link still hanging in the eye
	local eye = (C * CN(0, 2.62, 0)).Position
	rod(b, eye + V3(-0.02, 0.02, 0), eye + V3(0.22, 0.32, 0.02), 0.07, BRONZE, "Metal")
	rod(b, eye + V3(0.22, 0.32, 0.02), eye + V3(0.4, 0.18, 0.04), 0.07, BRONZE, "Metal")
	-- glowing cracks
	local cracks = { { V3(-0.2, 1.0, -0.4), V3(0.02, 0.72, -0.43) }, { V3(0.02, 0.72, -0.43), V3(-0.08, 0.42, -0.42) }, { V3(0.15, 1.32, -0.18), V3(0.06, 1.12, -0.32) }, { V3(0.3, 0.55, -0.32), V3(0.38, 0.85, -0.2) } }
	for i, c in cracks do
		b:Accent(bar(b, C:PointToWorldSpace(c[1]), C:PointToWorldSpace(c[2]), 0.07, VIOLET, "Neon", if i == 1 then GLINT else nil))
	end
	b:Detail(function()
		bar(b, C:PointToWorldSpace(V3(0, 1.6, 0)), C:PointToWorldSpace(V3(0, 1.72, 0)), 0.25, RUST, "Metal")
		b:Ball(0.18, CN(-0.6, 0.08, -0.3), rgb(110, 100, 96), "Slate")
		b:Ball(0.13, CN(-0.42, 0.06, -0.52), BRONZE, "Metal")
	end)
end

-- Tiny Tombstone: a little grave for a very good dog: a headstone with an engraved paw, a candle that is still lit,
-- a pot of blue flowers and a bone left in the grass.
R.uy_tiny_tombstone = function(b: any, lod: number)
	showcase(b, GHOST)
	local STONE = rgb(150, 146, 160)
	local CARVE = rgb(96, 92, 108)
	b:Ellipsoid(V3(2.2, 0.4, 1.6), CN(0, 0.06, 0), SOIL, "Ground")
	b:Ellipsoid(V3(2.0, 0.3, 1.4), CN(0, 0.12, 0.02), MOSS, "Grass")
	b:Box(V3(1.45, 0.2, 0.55), CN(0, 0.3, 0.32), rgb(120, 116, 130), "Slate")
	local stone = CN(0, 0.38, 0.34) * ang(-4, 0, 3)
	local w, h, t = 1.2, 1.65, 0.3
	b:Box(V3(w, h - w / 2, t), stone * CN(0, (h - w / 2) / 2, 0), STONE, "Slate")
	b:CylZ(t, w, stone * CN(0, h - w / 2, 0), STONE, "Slate")
	-- engraved paw
	local paw = stone * CN(0, 0.75, -t / 2 - 0.01)
	b:Ellipsoid(V3(0.42, 0.34, 0.04), paw, CARVE, "Slate")
	for i, x in { -0.21, -0.08, 0.08, 0.21 } do
		local lift = if i == 2 or i == 3 then 0.06 else 0
		b:Ellipsoid(V3(0.13, 0.16, 0.04), paw * CN(x, 0.27 + lift, 0), CARVE, "Slate")
	end
	-- the candle, the flower pot and a bone
	b:CylY(0.32, 0.14, CN(-0.62, 0.38, -0.25), rgb(238, 228, 206), "SmoothPlastic")
	b:Accent(b:Ellipsoid(V3(0.1, 0.2, 0.1), CN(-0.62, 0.64, -0.25), CANDLE, "Neon", GLINT))
	b:CylY(0.3, 0.32, CN(0.62, 0.36, -0.22), rgb(150, 82, 60), "SmoothPlastic")
	for i, p in { V3(0.56, 0.62, -0.24), V3(0.7, 0.6, -0.18), V3(0.62, 0.68, -0.14) } do
		b:Ball(0.15, CN(p), if i == 2 then rgb(150, 110, 240) else ROSE, "SmoothPlastic")
	end
	local bone = CN(0.1, 0.27, -0.55) * ang(0, 18, 0)
	b:Cyl(0.48, 0.09, bone, BONE, "SmoothPlastic")
	for _, x in { -0.25, 0.25 } do
		b:Ball(0.14, bone * CN(x, 0, 0), BONE, "SmoothPlastic")
	end
	b:Detail(function()
		for _, y in { 0.42, 0.32 } do
			b:Box(V3(0.5 - y * 0.4, 0.04, 0.03), stone * CN(0, y, -t / 2 - 0.01), CARVE, "Slate")
		end
		b:Ellipsoid(V3(0.5, 0.14, 0.34), stone * CN(-0.32, h - 0.22, 0), MOSS, "Grass")
		b:Disc(CN(-0.62, 0.23, -0.25), 0.3, 0.04, IRON, "Metal")
		for _, x in { -0.9, 0.95 } do
			b:Wedge(V3(0.06, 0.24, 0.12), CN(x, 0.3, -0.3), MOSS, "Grass")
		end
	end)
end

------------------------------------------------------------------------------------------------
-- Epic
------------------------------------------------------------------------------------------------

-- Dead Wedding Ring: a tarnished gold ring with a pale moonstone held by bone claws, a black thorned vine grown round
-- the band, presented in an open black velvet ring box.
R.uy_dead_wedding_ring = function(b: any, lod: number)
	showcase(b, MOON)
	local BOX = rgb(30, 22, 40)
	b:Box(V3(1.5, 0.7, 1.3), CN(0, 0.35, 0), BOX, "Fabric")
	local hinge = CN(0, 0.7, 0.65)
	local lid = hinge * ang(105, 0, 0) * CN(0, 0.08, -0.65)
	b:Box(V3(1.5, 0.16, 1.3), lid, BOX, "Fabric")
	b:Box(V3(1.32, 0.04, 1.12), lid * CN(0, -0.09, 0), SATIN, "Fabric")
	b:Ellipsoid(V3(1.3, 0.3, 1.0), CN(0, 0.72, 0), VELVET, "Fabric")
	b:Box(V3(0.9, 0.05, 0.08), CN(0, 0.86, 0), INK, "Fabric")
	-- the band standing in the slit
	local ring = CN(0, 1.3, 0)
	arc(b, ring, 0.5, 0.15, 102, 438, if lod > 0 then 6 else 10, GOLD_OLD, "Metal")
	-- the setting: bone claws around a moonstone with a glowing heart
	local setting = ring * CN(0, 0.58, 0)
	b:CylY(0.12, 0.32, setting * CN(0, -0.04, 0), GOLD_OLD, "Metal")
	for i = 0, 3 do
		local a = rad(i * 90 + 45)
		rod(b, setting:PointToWorldSpace(V3(cos(a) * 0.12, 0.02, sin(a) * 0.12)), setting:PointToWorldSpace(V3(cos(a) * 0.2, 0.3, sin(a) * 0.2)), 0.06, BONE, "SmoothPlastic")
	end
	b:Accent(b:Ball(0.44, setting * CN(0, 0.26, 0), rgb(196, 222, 255), "Glass", { Transparency = 0.25 }))
	b:Accent(b:Ball(0.2, setting * CN(0, 0.26, -0.05), MOON, "Neon", GLINT))
	-- the thorned vine
	local vine = rgb(30, 40, 34)
	for i = 0, 2 do
		local a0, a1 = rad(200 + i * 40), rad(225 + i * 40)
		rod(b, ring:PointToWorldSpace(V3(cos(a0) * 0.5, sin(a0) * 0.5, -0.09)), ring:PointToWorldSpace(V3(cos(a1) * 0.5, sin(a1) * 0.5, 0.09)), 0.05, vine, "SmoothPlastic")
	end
	b:Detail(function()
		for i = 0, 2 do
			local a = rad(212 + i * 40)
			b:Wedge(V3(0.03, 0.1, 0.06), ring * CN(cos(a) * 0.56, sin(a) * 0.56, -0.05) * ang(0, 0, math.deg(a) - 90), vine, "SmoothPlastic")
		end
		-- a tiny skull on the band and gold edges on the box
		local skull = ring * CN(0.5, 0.1, -0.08) * ang(0, -20, 0)
		b:Ball(0.16, skull, BONE, "SmoothPlastic")
		for _, x in { -0.035, 0.035 } do
			b:Ball(0.045, skull * CN(x, 0.01, -0.07), INK, "SmoothPlastic")
		end
		b:Box(V3(1.54, 0.05, 0.05), CN(0, 0.7, -0.66), GOLD_OLD, "Metal")
		b:Box(V3(1.54, 0.05, 0.05), lid * CN(0, 0.06, -0.66), GOLD_OLD, "Metal")
	end)
end

-- Ghost Photograph: an old sepia photograph in a tarnished arch-topped frame on a little easel; a lady stands in it,
-- and beside her, faintly glowing, a dog that was never there. The glass is cracked.
R.uy_ghost_photograph = function(b: any, lod: number)
	showcase(b, SPIRIT, "Wisp")
	local FRAME = rgb(128, 98, 56)
	local F = CN(0, 1.22, 0) * ang(12, 0, 0)
	-- easel
	rod(b, V3(-0.5, 0, -0.2), V3(-0.3, 1.0, 0.05), 0.08, WOOD, "Wood")
	rod(b, V3(0.5, 0, -0.2), V3(0.3, 1.0, 0.05), 0.08, WOOD, "Wood")
	rod(b, V3(0, 0, 0.75), F:PointToWorldSpace(V3(0, 0.55, 0.08)), 0.07, WOOD, "Wood")
	b:Box(V3(1.3, 0.06, 0.12), F * CN(0, -0.92, -0.06), WOOD, "Wood")
	-- the photograph and its people
	b:Box(V3(1.3, 1.7, 0.04), F, SEPIA, "SmoothPlastic")
	local photo = F * CN(0, 0, -0.03)
	b:Ellipsoid(V3(0.36, 0.86, 0.02), photo * CN(-0.3, -0.3, 0), SEPIA_D, "SmoothPlastic")
	b:Ball(0.24, photo * CN(-0.3, 0.26, -0.005), SEPIA_D, "SmoothPlastic")
	b:Ellipsoid(V3(0.44, 0.08, 0.02), photo * CN(-0.3, 0.38, -0.008), SEPIA_D, "SmoothPlastic")
	local dog = photo * CN(0.3, -0.5, -0.02)
	b:Accent(b:Ellipsoid(V3(0.5, 0.3, 0.03), dog, SPIRIT, "Neon", { Transparency = 0.25 }))
	b:Accent(b:Ball(0.24, dog * CN(-0.22, 0.2, -0.005), SPIRIT, "Neon", { Transparency = 0.2, Attributes = { ShowcaseGlint = true } }))
	for _, x in { -0.3, -0.14 } do
		b:Accent(b:Wedge(V3(0.02, 0.14, 0.08), dog * CN(x, 0.36, -0.01) * ang(0, 90, 0), SPIRIT, "Neon", { Transparency = 0.25 }))
	end
	b:Accent(b:Ellipsoid(V3(0.2, 0.06, 0.03), dog * CN(0.3, 0.1, 0) * ang(0, 0, 35), SPIRIT, "Neon", { Transparency = 0.3 }))
	-- glass and its cracks
	b:Box(V3(1.32, 1.72, 0.03), F * CN(0, 0, -0.06), rgb(220, 236, 255), "Glass", { Transparency = 0.78 })
	b:Box(V3(0.025, 0.7, 0.02), F * CN(0.32, 0.36, -0.08) * ang(0, 0, 28), rgb(236, 244, 255), "Neon")
	b:Box(V3(0.025, 0.4, 0.02), F * CN(0.2, 0.0, -0.08) * ang(0, 0, -40), rgb(236, 244, 255), "Neon")
	-- the arch-topped frame
	for _, s in { -1, 1 } do
		b:Box(V3(0.14, 1.86, 0.14), F * CN(s * 0.72, -0.02, -0.04), FRAME, "Metal")
	end
	b:Box(V3(1.58, 0.14, 0.14), F * CN(0, -0.93, -0.04), FRAME, "Metal")
	b:Box(V3(1.58, 0.14, 0.14), F * CN(0, 0.88, -0.04), FRAME, "Metal")
	for _, s in { -1, 1 } do
		bar(b, F:PointToWorldSpace(V3(s * 0.78, 0.92, -0.04)), F:PointToWorldSpace(V3(0, 1.32, -0.04)), 0.12, FRAME, "Metal")
	end
	b:Accent(b:Ball(0.2, F * CN(0, 1.4, -0.04), FRAME, "Metal", GLINT))
	b:Detail(function()
		for _, x in { -0.72, 0.72 } do
			for _, y in { -0.93, 0.88 } do
				b:Ball(0.2, F * CN(x, y, -0.07), FRAME, "Metal")
			end
		end
		b:Accent(b:Ball(0.12, F * CN(0, 1.1, -0.08), SPIRIT, "Neon"))
	end)
end

-- Mourning Locket: an open heart locket in black enamel and silver on a velvet pad: a tiny portrait of a dog in one
-- half, a glowing violet keepsake heart in the other, the chain coiled around it.
R.uy_mourning_locket = function(b: any, lod: number)
	showcase(b, VIOLET)
	b:Ellipsoid(V3(2.0, 0.3, 1.4), CN(0, 0.1, 0.05), VELVET, "Fabric")
	local hingeAt = V3(0, 1.0, 0.1)
	local left = CN(hingeAt) * ang(0, 22, 0) * CN(-0.48, 0, 0)
	local right = CN(hingeAt) * ang(0, -22, 0) * CN(0.48, 0, 0)
	heart(b, left, 0.95, 0.1, SILVER, "Metal")
	heart(b, left * CN(0, 0.01, -0.04), 0.78, 0.06, INK, "SmoothPlastic")
	heart(b, right, 0.95, 0.1, SILVER, "Metal")
	heart(b, right * CN(0, 0.01, -0.04), 0.78, 0.06, SATIN, "Fabric")
	-- portrait (left) and keepsake (right)
	b:CylZ(0.03, 0.4, left * CN(0, 0.04, -0.08), SEPIA, "SmoothPlastic")
	b:Ellipsoid(V3(0.16, 0.12, 0.02), left * CN(0.02, -0.02, -0.1), SEPIA_D, "SmoothPlastic")
	b:Ball(0.11, left * CN(-0.06, 0.06, -0.1), SEPIA_D, "SmoothPlastic")
	for _, part in heart(b, right * CN(0, 0.03, -0.09), 0.36, 0.08, VIOLET, "Neon") do
		b:Accent(part)
	end
	b:Ball(0.1, right * CN(0, 0.06, -0.14), rgb(255, 230, 255), "Neon", GLINT)
	-- hinge, bail and chain
	b:CylY(0.5, 0.08, CN(hingeAt + V3(0, -0.02, 0)), SILVER, "Metal")
	b:Ball(0.14, CN(hingeAt + V3(0, 0.3, 0)), SILVER, "Metal", GLINT)
	local bail = hingeAt + V3(0, 0.36, 0)
	chain(b, { bail, bail + V3(0.25, 0.1, 0.1), V3(0.75, 1.0, 0.25), V3(0.95, 0.5, 0.15), V3(0.8, 0.26, -0.3), V3(0.2, 0.25, -0.5), V3(-0.45, 0.25, -0.45), V3(-0.85, 0.25, -0.05) }, 0.17, SILVER_D, "Metal")
	b:Detail(function()
		for _, s in { -1, 1 } do
			rod(b, (left * CN(s * 0.2, -0.3, 0.06)).Position, (left * CN(s * 0.05, -0.44, 0.06)).Position, 0.03, SILVER_D, "Metal")
		end
		b:Box(V3(0.06, 0.06, 0.06), left * CN(0.3, -0.18, -0.08) * ang(0, 0, 45), SILVER, "Metal")
	end)
end

------------------------------------------------------------------------------------------------
-- Legendary
------------------------------------------------------------------------------------------------

-- Bellkeeper Mask: the porcelain mask THE BELLKEEPER wore to ring the last bell: a long crooked dog snout, tall ears,
-- hollow eyes burning violet, cracks of light, a bell glyph on the brow, a small bell at the chin and black ribbons,
-- hung on an iron stand.
R.uy_bellkeeper_mask = function(b: any, lod: number)
	showcase(b, VIOLET, "Wisp")
	b:CylY(0.14, 1.3, CN(0, 0.07, 0.2), IRON, "Metal")
	b:CylY(0.12, 0.8, CN(0, 0.2, 0.2), IRON, "Metal")
	rod(b, V3(0, 0.25, 0.2), V3(0, 1.45, 0.2), 0.12, IRON, "Metal")
	b:Box(V3(0.5, 0.12, 0.3), CN(0, 1.42, 0.12), IRON, "Metal")
	b:Ellipsoid(V3(1.3, 1.62, 0.5), CN(0, 1.62, 0.18), INK, "Fabric")
	local M = CN(0, 1.62, -0.06) * ang(-6, 0, 0)
	b:Ellipsoid(V3(1.22, 1.62, 0.55), M, PORCELAIN, "SmoothPlastic")
	b:Ellipsoid(V3(1.0, 0.22, 0.34), M * CN(0, 0.36, -0.16), BONE_D, "SmoothPlastic")
	-- the crooked snout
	local s0 = M:PointToWorldSpace(V3(0, -0.06, -0.2))
	local s1 = M:PointToWorldSpace(V3(0.06, -0.24, -0.6))
	local s2 = M:PointToWorldSpace(V3(0.16, -0.36, -0.88))
	blob(b, s0, s1, 0.58, PORCELAIN, "SmoothPlastic", 0.5)
	blob(b, s1, s2, 0.48, PORCELAIN, "SmoothPlastic", 0.6)
	b:Ball(0.2, CN(s2 + V3(0.02, 0.02, -0.12)), INK, "SmoothPlastic")
	bar(b, M:PointToWorldSpace(V3(-0.02, -0.38, -0.38)), s2 + V3(-0.02, -0.18, 0.02), 0.06, INK, "SmoothPlastic")
	-- hollow eyes with violet light
	for i, x in { -0.27, 0.27 } do
		local eye = M * CN(x, 0.17, -0.25) * ang(0, 0, x > 0 and -14 or 14)
		b:Ellipsoid(V3(0.32, 0.2, 0.12), eye, INK, "SmoothPlastic")
		b:Accent(b:Ball(0.13, eye * CN(0, 0, -0.04), VIOLET, "Neon", if i == 1 then GLINT else nil))
	end
	-- tall pointed dog ears, the right one bent forward
	for _, s in { -1, 1 } do
		local base = M * CN(s * 0.36, 0.62, 0.04) * ang(if s > 0 then -26 else -4, 0, s * -14)
		local w, h = 0.46, 0.92
		b:Wedge(V3(0.14, h, w / 2), base * CN(-w / 4, h / 2, 0) * ang(0, 90, 0), PORCELAIN, "SmoothPlastic")
		b:Wedge(V3(0.14, h, w / 2), base * CN(w / 4, h / 2, 0) * ang(0, -90, 0), PORCELAIN, "SmoothPlastic")
		b:Detail(function()
			b:Wedge(V3(0.04, h * 0.62, w * 0.24), base * CN(-w * 0.12, h * 0.3, -0.08) * ang(0, 90, 0), rgb(70, 40, 90), "SmoothPlastic")
			b:Wedge(V3(0.04, h * 0.62, w * 0.24), base * CN(w * 0.12, h * 0.3, -0.08) * ang(0, -90, 0), rgb(70, 40, 90), "SmoothPlastic")
		end)
	end
	-- cracks of light and the bell glyph on the brow
	b:Accent(bar(b, M:PointToWorldSpace(V3(-0.36, 0.62, -0.24)), M:PointToWorldSpace(V3(-0.18, 0.34, -0.3)), 0.05, VIOLET, "Neon"))
	b:Accent(bar(b, M:PointToWorldSpace(V3(-0.18, 0.34, -0.3)), M:PointToWorldSpace(V3(-0.3, 0.02, -0.28)), 0.05, VIOLET, "Neon"))
	b:Accent(bar(b, M:PointToWorldSpace(V3(0.42, -0.2, -0.24)), M:PointToWorldSpace(V3(0.26, -0.5, -0.2)), 0.05, VIOLET, "Neon"))
	b:Accent(b:Ellipsoid(V3(0.16, 0.18, 0.05), M * CN(0, 0.56, -0.25), VIOLET, "Neon"))
	b:Accent(b:Box(V3(0.24, 0.04, 0.05), M * CN(0, 0.46, -0.25), VIOLET, "Neon"))
	-- the chin bell
	local hook = M:PointToWorldSpace(V3(0, -0.74, -0.2))
	rod(b, hook, hook - V3(0, 0.2, 0), 0.04, IRON, "Metal")
	b:Ellipsoid(V3(0.26, 0.16, 0.26), CN(hook - V3(0, 0.24, 0)), BRONZE, "Metal")
	b:Cone(CN(hook - V3(0, 0.56, 0)), 0.32, 0.36, 0.22, 2, BRONZE, "Metal")
	b:Ball(0.1, CN(hook - V3(0, 0.6, 0)), IRON, "Metal")
	-- ribbons
	for _, s in { -1, 1 } do
		local from = M:PointToWorldSpace(V3(s * 0.56, 0.1, 0.1))
		local mid = from + V3(s * 0.22, -0.55, 0.12)
		bar(b, from, mid, 0.05, INK, "Fabric")
		b:Box(V3(0.14, 0.62, 0.03), CN((mid + mid + V3(s * 0.1, -0.5, 0.06)) / 2) * ang(0, 0, s * 10), INK, "Fabric")
	end
	b:Detail(function()
		for i = -1, 1 do
			b:Wedge(V3(0.05, 0.1, 0.06), CN(s2:Lerp(s1, 0.4) + V3(i * 0.08, -0.2, 0)) * ang(180, 0, 0), BONE, "SmoothPlastic")
		end
		b:Box(V3(0.1, 0.5, 0.03), CN(M:PointToWorldSpace(V3(0.72, -0.5, 0.2))) * ang(0, 0, -6), VIOLET:Lerp(INK, 0.3), "Fabric")
	end)
end

-- Hollow Heart: a black crystal heart cradled by bone ribs; a window in it shows a violet flame floating in the
-- hollow inside. Veins of light, three arteries and an iron chain wrapped round it.
R.uy_hollow_heart = function(b: any, lod: number)
	showcase(b, MAGENTA, "Ember")
	local CRYSTAL = rgb(48, 24, 72)
	local ARTERY = rgb(92, 26, 54)
	b:CylY(0.14, 1.4, CN(0, 0.07, 0.1), rgb(62, 56, 72), "Slate")
	-- spine and ribs
	for i = 0, 2 do
		b:CylY(0.24, 0.3 - i * 0.04, CN(0, 0.28 + i * 0.27, 0.42), BONE_D, "SmoothPlastic")
	end
	for _, s in { -1, 1 } do
		for k = 0, 1 do
			local y = 0.32 + k * 0.42
			local p0 = V3(s * 0.08, y, 0.42)
			local p1 = V3(s * 0.62, y + 0.25, 0.12)
			local p2 = V3(s * 0.55, y + 0.6, -0.36)
			rod(b, p0, p1, 0.1, BONE, "SmoothPlastic")
			rod(b, p1, p2, 0.08, BONE, "SmoothPlastic")
		end
	end
	-- the crystal heart
	local H = CN(0, 1.5, 0)
	b:Ball(1.0, H * CN(-0.28, 0.25, 0), CRYSTAL, "Glass", { Transparency = 0.08 })
	b:Ball(1.0, H * CN(0.28, 0.25, 0), CRYSTAL, "Glass", { Transparency = 0.08 })
	b:Ellipsoid(V3(1.05, 1.0, 0.86), H * CN(0, -0.12, 0), CRYSTAL, "Glass", { Transparency = 0.08 })
	b:Ellipsoid(V3(0.46, 0.66, 0.46), H * CN(0.05, -0.6, 0) * ang(0, 0, 8), CRYSTAL, "Glass", { Transparency = 0.08 })
	-- the hollow and its flame
	b:Ellipsoid(V3(0.72, 0.66, 0.2), H * CN(0, 0.06, -0.38), INK, "SmoothPlastic")
	b:Accent(b:Ellipsoid(V3(0.84, 0.78, 0.12), H * CN(0, 0.06, -0.33), VIOLET, "Neon", { Transparency = 0.35 }))
	b:Accent(b:Ellipsoid(V3(0.28, 0.46, 0.2), H * CN(0, 0.06, -0.46), MAGENTA, "Neon"))
	b:Accent(b:Ball(0.14, H * CN(0, 0.0, -0.52), rgb(255, 226, 255), "Neon", GLINT))
	-- veins of light
	local veins = { { V3(-0.5, 0.45, -0.3), V3(-0.3, 0.2, -0.42) }, { V3(0.52, 0.42, -0.28), V3(0.36, 0.0, -0.4) }, { V3(-0.25, -0.35, -0.38), V3(0.0, -0.62, -0.2) }, { V3(0.3, -0.3, -0.38), V3(0.12, -0.55, -0.26) } }
	for i, v in veins do
		b:Accent(bar(b, H:PointToWorldSpace(v[1]), H:PointToWorldSpace(v[2]), 0.05, MAGENTA, "Neon", if i == 2 then GLINT else nil))
	end
	-- arteries
	for i, a in { { -0.2, 0.7, -10 }, { 0.1, 0.78, 6 }, { 0.36, 0.66, 22 } } do
		local cf = H * CN(a[1], a[2], 0.08) * ang(0, 0, -a[3])
		b:CylY(0.42 - i * 0.05, 0.2 - i * 0.02, cf, ARTERY, "SmoothPlastic")
		b:Detail(function()
			b:CylY(0.03, 0.12 - i * 0.015, cf * CN(0, 0.21 - i * 0.025, 0), INK, "SmoothPlastic")
		end)
	end
	-- the iron chain wrapped across it
	local links = {}
	for i = 0, 6 do
		local t = i / 6
		local a = rad(-60 + t * 220)
		table.insert(links, H:PointToWorldSpace(V3(-0.62 + t * 1.24, 0.5 - t * 0.9, -0.52 * math.max(0.2, sin(a * 0.5 + 0.9)))))
	end
	chain(b, links, 0.2, IRON, "Metal")
	b:Detail(function()
		b:Gem(0.16, H * CN(-0.45, 0.55, -0.25), rgb(110, 60, 160), "Glass")
		b:Gem(0.12, H * CN(0.5, -0.1, -0.3), rgb(110, 60, 160), "Glass")
	end)
end

return R
