-- THE UNDERYARD — shared style kit of the world builders (ServerStorage.UnderyardBuild.UKit). Build-time only: the
-- builders next to it (Ground, Sky, Roads, BellSquare, Gates, FXMarkers and the district builders) are run offline by
-- tools/edits/40_underyard.luau through tools/sim.luau and their output is SAVED in the place (40_Underyard). UKit has
-- no Build function, so the edit loads it like any module but never runs it as a builder.
-- Builds on HalloweenBuild.Kit (parts + house style) and YardKit (deterministic Rng, gables, skulls, statues):
--   * crooked stacked boxes (Crooked), twisted / curled spires (Spire), pointed arches (Arch), stretched gothic windows
--     with Neon panes (GothicWindow), crooked gabled roofs (CrookedRoof),
--   * paw-print trails and deck ribbons along sampled curves (Sample, ArcPoints, PawTrail, Paw, Deck), black/white
--     stripe trims and pennant strings (StripeTrim, Pennants - accents only), bone fences (BoneFence),
--   * dog gargoyles (Gargoyle), HwLantern lanterns and crooked street lamps (Lantern, Lamp), bells (Bell), candle
--     clusters (Candles), glowing flowers (Flower, FlowerPatch), stalactites and glow-root curtains (Stalactite, Roots),
--     rune rings (RuneRing), the veiled gate arch (VeilArch), cliff columns (CliffColumn), pointed tips (Point),
--   * invisible colliders (Collider, ArcColliders with exact openings), bilingual world signs (Sign: NoTranslate +
--     TextEN / TextRU, localized by the client), attribute tagging (Tag) and a placement registry (Space) that keeps
--     props off the gameplay points of UnderyardLayout (echo points, choir paths, prompts, arrival).
-- Style (DESIGN §7.1): crooked gothic stop-motion, exaggerated silhouettes, leaning / twisted architecture, stretched
-- windows, crooked roofs, spiral roads, black/white stripes as accents only; palette sickly green, violet, candle orange,
-- moon blue, bone, ink; dogs everywhere in the motif. House style (A10 §2.5): everything anchored, only walkable or
-- blocking parts collide / query / cast shadows, decor is shadowless, every light has Shadows=false, FX hooks are
-- attributes (HwLantern, HwCandle, UyShowAtSeal, UyHideAtSeal, UyLightAtSeal), not scripts.
-- Angle convention (UnderyardLayout.Ring): a = 0 is north (-Z), a = pi/2 east (+X); U.Polar(c, r, a) is that point.
local HB = script.Parent.Parent.HalloweenBuild
local K = require(HB.Kit)
local Y = require(HB.YardKit)
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local U = {}
U.K, U.Y = K, Y
U.C = C

U.P = {
	Ink = C(16, 12, 26), Night = C(30, 26, 46), Abyss = C(14, 10, 22),
	Green = C(120, 255, 140), Violet = C(150, 80, 230), Candle = C(255, 170, 80), Moon = C(150, 200, 255),
	Bone = C(230, 222, 200), BoneDark = C(184, 172, 146),
	Stone = C(96, 92, 114), StoneDark = C(64, 60, 80), StoneLight = C(138, 134, 156), StoneWarm = C(110, 100, 112),
	Rock = C(56, 50, 68), RockDark = C(36, 32, 46), RockLight = C(82, 76, 98),
	Cobble = C(70, 66, 84), CobbleDark = C(50, 46, 62), CobbleLight = C(104, 98, 120),
	Iron = C(38, 38, 48), Wood = C(74, 56, 50), WoodDark = C(46, 34, 34), Slate = C(46, 42, 58),
	Black = C(24, 20, 30), White = C(234, 230, 222), Moss = C(56, 82, 62), Root = C(60, 46, 44), Wax = C(238, 226, 200),
}
U.GLOW = {
	Green = C(134, 255, 150), Violet = C(178, 112, 255), Candle = C(255, 170, 80), Moon = C(165, 210, 255),
	Ghost = C(205, 230, 255), Ember = C(255, 110, 60),
}
local P = U.P

U.Rng = Y.Rng
U.Solid = Y.Solid

------------------------------------------------------------------------------------------------------------------
-- small helpers
------------------------------------------------------------------------------------------------------------------

-- point on the circle of radius r around centre at layout angle a (0 = north / -Z, pi/2 = east / +X)
function U.Polar(centre: Vector3, r: number, a: number, y: number?): Vector3
	return Vector3.new(centre.X + math.sin(a) * r, y or centre.Y, centre.Z - math.cos(a) * r)
end

-- layout angle of pos seen from centre (inverse of Polar)
function U.AngleOf(centre: Vector3, pos: Vector3): number
	return math.atan2(pos.X - centre.X, -(pos.Z - centre.Z))
end

-- CFrame on the ground at pos, facing (-Z) towards target (flattened)
function U.Facing(pos: Vector3, target: Vector3): CFrame
	return K.Look(pos, Vector3.new(target.X, pos.Y, target.Z))
end

-- set attributes on an instance (or a list of instances); returns the input
function U.Tag(inst: any, attrs: { [string]: any }): any
	local list = typeof(inst) == "Instance" and { inst } or inst
	for _, i in ipairs(list) do
		for k, v in pairs(attrs) do
			i:SetAttribute(k, v)
		end
	end
	return inst
end

-- shorter angle difference a - b in (-pi, pi]
function U.AngleDiff(a: number, b: number): number
	local d = (a - b) % (2 * PI)
	if d > PI then
		d -= 2 * PI
	end
	return d
end

-- every BasePart under root (Model / Folder), for tagging whole props
function U.PartsOf(root: Instance): { BasePart }
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- placement registry: gameplay points of UnderyardLayout + claimed prop footprints (all tested in the XZ plane)
------------------------------------------------------------------------------------------------------------------
-- U.Space(L) -> space; space:Free(pos, r) true when a prop of radius r at pos touches neither a gameplay point (its
-- keep-out radius) nor an earlier claim; space:Claim(pos, r) records a footprint; space:Try(pos, r) = Free + Claim.
local KEEPOUT = {
	EchoPoint_ = 4.5, TutorialEcho_ = 4.5, ResonantEcho_ = 4.5, ChoirPath_ = 3.5, Arrival = 5, ReturnPortal = 3,
	PracticeRing = 0, Mourner = 2.5, TutorialBell = 1.5, SealAltar_ = 4, Gate_ = 3, CoffinShrine = 3, ContractsBoard = 2.5,
	TollBox = 2.5, Tailor = 2.5, TowerBell = 0, RunStart = 3, RunCheckpoint_ = 7, MineNode_ = 4, Door_ = 3, MirrorGrave_ = 3,
}
function U.Space(L)
	local pts = {}
	for name, pos in pairs(L.Anchors) do
		local r = 3
		for prefix, rr in pairs(KEEPOUT) do
			if string.sub(name, 1, #prefix) == prefix then
				r = rr
				break
			end
		end
		if r > 0 then
			table.insert(pts, { P = pos, R = r, Name = name })
		end
	end
	local claims = {}
	local space = { Points = pts, Claims = claims }
	function space:Free(pos: Vector3, r: number): boolean
		for _, g in ipairs(pts) do
			if math.abs(g.P.Y - pos.Y) < 12 then
				local dx, dz = pos.X - g.P.X, pos.Z - g.P.Z
				if dx * dx + dz * dz < (g.R + r) ^ 2 then
					return false
				end
			end
		end
		for _, c in ipairs(claims) do
			local dx, dz = pos.X - c.P.X, pos.Z - c.P.Z
			if dx * dx + dz * dz < (c.R + r) ^ 2 then
				return false
			end
		end
		return true
	end
	function space:Claim(pos: Vector3, r: number)
		table.insert(claims, { P = pos, R = r })
	end
	function space:Try(pos: Vector3, r: number): boolean
		if self:Free(pos, r) then
			self:Claim(pos, r)
			return true
		end
		return false
	end
	return space
end

------------------------------------------------------------------------------------------------------------------
-- curves: sampling, paw trails, deck ribbons, stripe trims
------------------------------------------------------------------------------------------------------------------

-- points on an arc around centre from layout angle a0 to a1 (radius r, height y), n + 1 points
function U.ArcPoints(centre: Vector3, r: number, a0: number, a1: number, n: number, y: number?): { Vector3 }
	local out = {}
	for i = 0, n do
		table.insert(out, U.Polar(centre, r, a0 + (a1 - a0) * i / n, y))
	end
	return out
end

-- resample a polyline at a fixed spacing: { {Pos, Dir (unit, flattened), S (arc length)} }
function U.Sample(points: { Vector3 }, spacing: number, offset: number?): { { Pos: Vector3, Dir: Vector3, S: number } }
	local out = {}
	local s0 = offset or spacing / 2
	local walked = 0
	local nextAt = s0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local seg = (b - a).Magnitude
		if seg > 1e-6 then
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local dir = flat.Magnitude > 1e-6 and flat.Unit or Vector3.new(0, 0, -1)
			while nextAt <= walked + seg do
				local t = (nextAt - walked) / seg
				table.insert(out, { Pos = a:Lerp(b, t), Dir = dir, S = nextAt })
				nextAt += spacing
			end
			walked += seg
		end
	end
	return out
end

-- total length of a polyline
function U.Length(points: { Vector3 }): number
	local n = 0
	for i = 1, #points - 1 do
		n += (points[i + 1] - points[i]).Magnitude
	end
	return n
end

-- flat paw print lying on the plane of cf (toes towards -Z), s = pad length; 5 thin parts centred on cf's height
function U.Paw(parent: Instance, cf: CFrame, s: number, color: Color3, material: Enum.Material?)
	local mat = material or M.Slate
	K.Ellipsoid(parent, "PawPad", V3(s * .95, .1, s * .78), cf * CF(0, 0, s * .16), color, mat)
	for _, t in ipairs({ { -.43, -.3 }, { -.16, -.56 }, { .16, -.56 }, { .43, -.3 } }) do
		K.Ellipsoid(parent, "PawToe", V3(s * .3, .1, s * .38), cf * CF(t[1] * s, 0, t[2] * s) * ANG(0, -t[1] * .7, 0), color, mat)
	end
end

-- a dog's walk along a polyline: paws every `spacing`, alternating left / right of the line (gait), toes forward.
-- opts: Size (1.5), Gait (.9 off the line), Color, Height (centre y offset above the points, .05), Skip(pos) -> bool
function U.PawTrail(parent: Instance, points: { Vector3 }, spacing: number, opts: any): number
	opts = opts or {}
	local n = 0
	local s = opts.Size or 1.5
	for i, smp in ipairs(U.Sample(points, spacing)) do
		local side = (i % 2 == 0) and 1 or -1
		local right = Vector3.new(-smp.Dir.Z, 0, smp.Dir.X)
		local pos = smp.Pos + right * side * (opts.Gait or .9) + Vector3.new(0, opts.Height or .05, 0)
		if not (opts.Skip and opts.Skip(pos)) then
			U.Paw(parent, K.Look(pos, pos + smp.Dir), s, opts.Color or P.BoneDark, opts.Material)
			n += 1
		end
	end
	return n
end

-- a deck ribbon along a sampled centreline (points = top-surface centre, any height): one box per segment along its
-- chord (following the slope). Where the road turns, a segment is lengthened by (width / 2) * tan(turn / 2) at that end
-- so the outer edges close without filler parts (and without the bumps a tilted joint disc would leave on a sloped
-- curve). Solid unless opts.Solid == false. Returns the parts. opts: Overlap (.4), Shadow
function U.Deck(parent: Instance, name: string, points: { Vector3 }, width: number, thick: number, color: Color3, material: Enum.Material?,
	opts: any): { BasePart }
	opts = opts or {}
	local out = {}
	local ov = opts.Overlap or .4
	local n = #points - 1
	local flat = {}
	for i = 1, n do
		local d = Vector3.new(points[i + 1].X - points[i].X, 0, points[i + 1].Z - points[i].Z)
		flat[i] = d.Magnitude > 1e-6 and d.Unit or Vector3.new(0, 0, -1)
	end
	local function turnExt(i: number): number -- extra length needed at joint i (between segment i - 1 and i)
		if i <= 1 or i > n then
			return 0
		end
		local c = math.clamp(flat[i - 1]:Dot(flat[i]), -1, 1)
		return width / 2 * math.tan(math.acos(c) / 2)
	end
	for i = 1, n do
		local a, b = points[i], points[i + 1]
		local look = K.Look((a + b) / 2, b)
		local up = look.UpVector
		local e0, e1 = turnExt(i) + ov / 2, turnExt(i + 1) + ov / 2
		local len = (b - a).Magnitude + e0 + e1
		-- shift the box so it reaches e0 behind a and e1 beyond b
		local cf = look * CF(0, -thick / 2, (e0 - e1) / 2)
		table.insert(out, K.Part(parent, name, V3(width, thick, len), cf, color, material or M.Slate, { Solid = opts.Solid ~= false, Shadow = opts.Shadow }))
	end
	return out
end

-- black/white stripe trim along a polyline (points = bottom centre of the trim): alternating boxes `seg` long.
-- opts: Colors {a, b}, Material, Solid, Phase (start colour index 0/1), Skip(pos) -> bool. Returns parts.
function U.StripeTrim(parent: Instance, name: string, points: { Vector3 }, w: number, h: number, seg: number, opts: any): { BasePart }
	opts = opts or {}
	local cols = opts.Colors or { P.Black, P.White }
	local out = {}
	local k = opts.Phase or 0
	for _, smp in ipairs(U.Sample(points, seg, seg / 2)) do
		k += 1
		if not (opts.Skip and opts.Skip(smp.Pos)) then
			local cf = K.Look(smp.Pos, smp.Pos + smp.Dir) * CF(0, h / 2, 0)
			table.insert(out, K.Part(parent, name, V3(w, h, seg + .02), cf, cols[k % 2 + 1], opts.Material or M.SmoothPlastic,
				opts.Solid and { Solid = true } or nil))
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- architecture
------------------------------------------------------------------------------------------------------------------

-- crooked stack of `tiers` boxes from base (local y up): each tier leans / twists a little more and the stack tapers,
-- the stop-motion "leaning tower" look. Returns the top CFrame and the parts.
-- opts: Color, Shade (second colour, tiers alternate towards it), Material, Solid (true | number of solid bottom tiers),
-- Taper (.07), Lean (.045 rad), Twist (.1 rad), Shift (.04 of the width), Plumb (first tier upright), Name
function U.Crooked(parent: Instance, name: string, base: CFrame, size: Vector3, tiers: number, rng, opts: any): (CFrame, { BasePart })
	opts = opts or {}
	local parts = {}
	local cf = base
	local w, d = size.X, size.Z
	local h = size.Y / tiers
	local ov = math.min(h * .3, 1.2)
	local lean, twist, shift = opts.Lean or .045, opts.Twist or .1, opts.Shift or .04
	local solidN = opts.Solid == true and tiers or (type(opts.Solid) == "number" and opts.Solid or 0)
	for i = 1, tiers do
		if i > 1 or not opts.Plumb then
			cf = cf * ANG(rng:NextNumber(-lean, lean), rng:NextNumber(-twist, twist), rng:NextNumber(-lean, lean))
		else
			cf = cf * ANG(0, rng:NextNumber(-twist, twist), 0)
		end
		local col = opts.Color or P.Stone
		if opts.Shade then
			col = col:Lerp(opts.Shade, (i % 2 == 0) and .55 or rng:NextNumber(0, .3))
		end
		table.insert(parts, K.Part(parent, name, V3(w, h + ov, d), cf * CF(0, h / 2, 0), col, opts.Material or M.Slate,
			i <= solidN and { Solid = true } or nil))
		cf = cf * CF(rng:NextNumber(-1, 1) * w * shift, h, rng:NextNumber(-1, 1) * d * shift)
		w *= 1 - (opts.Taper or .07)
		d *= 1 - (opts.Taper or .07)
	end
	return cf, parts
end

-- four-sided pointed tip (two crossed gable triangles), apex up from base
function U.Point(parent: Instance, name: string, base: CFrame, w: number, h: number, color: Color3, material: Enum.Material?)
	Y.GableTri(parent, name, base, w, h, w, color, material or M.Slate)
	Y.GableTri(parent, name, base * ANG(0, PI / 2, 0), w * .98, h * .98, w * .98, color, material or M.Slate)
end

-- twisted, curling spire from base: shrinking tiers that twist and bend a little more each step, a pointed tip.
-- opts: Tiers (6), Twist (.16 rad per tier), Curl (.05 rad per tier, bends towards local +X), Color, Shade, Material,
-- Solid (bottom tier), Orb (finial colour), Flat (two-wedge tip for distant silhouettes). Returns the tip CFrame.
function U.Spire(parent: Instance, name: string, base: CFrame, w: number, h: number, rng, opts: any): CFrame
	opts = opts or {}
	local n = opts.Tiers or 6
	local cf = base
	local th = h / (n + 1)
	local width = w
	for i = 1, n do
		cf = cf * ANG(0, (opts.Twist or .16) + rng:NextNumber(-.04, .04), -(opts.Curl or .05) * (i / n) * 1.6)
		local col = opts.Color or P.Slate
		if opts.Shade and i % 2 == 0 then
			col = col:Lerp(opts.Shade, .6)
		end
		K.Part(parent, name, V3(width, th + .3, width), cf * CF(0, th / 2, 0), col, opts.Material or M.Slate,
			(i == 1 and opts.Solid) and { Solid = true } or nil)
		cf = cf * CF(0, th, 0)
		width *= .78
	end
	if opts.Flat then
		Y.GableTri(parent, name .. "Tip", cf, width * 1.05, th * 1.6, width, opts.Color or P.Slate, opts.Material or M.Slate)
	else
		U.Point(parent, name .. "Tip", cf, width * 1.05, th * 1.6, opts.Color or P.Slate, opts.Material)
	end
	local tip = cf * CF(0, th * 1.6, 0)
	if opts.Orb then
		K.Ball(parent, name .. "Orb", math.max(.35, width * .5), tip, opts.Orb, M.Neon)
	end
	return tip
end

-- pointed (gothic) arch in the local XY plane of cf: springing points (+-span/2, 0), apex raised by Stretch.
-- Built from `segs` bars per side (w = depth along Z, h = ring thickness). Returns the parts and the apex CFrame.
-- opts: Stretch (1.25), Radius (= span * .8), Striped (alternate Black / White), Color, Material, Solid
function U.Arch(parent: Instance, name: string, cf: CFrame, span: number, depth: number, thick: number, segs: number, opts: any): ({ BasePart }, CFrame)
	opts = opts or {}
	local half = span / 2
	local R = opts.Radius or span * .8
	local xc = half - R -- centre of the right half's arc (left of the axis)
	local tApex = math.acos(math.clamp(-xc / R, -1, 1))
	local st = opts.Stretch or 1.25
	local parts = {}
	local function pt(side: number, t: number): Vector3
		return (cf * CF(side * (xc + R * math.cos(t)), R * math.sin(t) * st, 0)).Position
	end
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, segs do
			local t0, t1 = tApex * (i - 1) / segs, tApex * i / segs
			local a, b = pt(side, t0), pt(side, t1)
			local col = opts.Color or P.StoneLight
			if opts.Striped then
				col = (i % 2 == 0) and P.White or P.Black
			end
			local bar = K.Bar(parent, name, a, b, depth, thick, col, opts.Material or M.Slate, opts.Solid and { Solid = true } or nil)
			-- lengthen a little so the joints close on the outside of the curve
			bar.Size += V3(0, 0, thick * .45)
			table.insert(parts, bar)
		end
	end
	local apexY = R * math.sin(tApex) * st
	return parts, cf * CF(0, apexY, 0)
end

-- height of the INSIDE of that arch above the springing line at local x (for veils / glass filling the opening)
function U.ArchInner(span: number, thick: number, x: number, opts: any): number
	opts = opts or {}
	local half = span / 2
	local R = (opts.Radius or span * .8) - thick / 2
	local xc = half - (opts.Radius or span * .8)
	local dx = math.abs(x) - xc
	if dx >= R then
		return 0
	end
	return math.sqrt(math.max(0, R * R - dx * dx)) * (opts.Stretch or 1.25)
end

-- stretched gothic window on a wall (faces -Z of cf; cf = sill centre on the wall face): jambs, sill, pointed hood,
-- Neon pane with a tall pointed head, mullion + transom. opts: Color (pane), Frame, Head (head height / width, 1.0),
-- Tilt (roll, the crooked look), Lantern (HwLantern kind on the pane), Attrs (extra pane attributes), Mullion (true)
function U.GothicWindow(parent: Instance, cf: CFrame, w: number, h: number, opts: any): BasePart
	opts = opts or {}
	local stone = opts.Frame or P.StoneLight
	local glass = opts.Color or U.GLOW.Violet
	local f = cf * ANG(0, 0, opts.Tilt or 0)
	local head = w * (opts.Head or 1)
	local attrs = {}
	for k, v in pairs(opts.Attrs or {}) do
		attrs[k] = v
	end
	if opts.Lantern then
		attrs.HwLantern = opts.Lantern
	end
	K.Part(parent, "WindowSill", V3(w + 1, .35, .7), f * CF(0, -.17, -.25), stone, M.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(parent, "WindowJamb", V3(.45, h, .6), f * CF(sx * (w / 2 + .2), h / 2, -.25), stone, M.Slate)
		K.Bar(parent, "WindowHood", (f * CF(sx * (w / 2 + .35), h - .1, -.28)).Position, (f * CF(0, h + head + .3, -.28)).Position, .55, .42,
			stone, M.Slate)
	end
	local pane = K.Part(parent, "WindowPane", V3(w, h, .14), f * CF(0, h / 2, -.07), glass, M.Neon, { Attrs = attrs })
	Y.GableTri(parent, "WindowPaneHead", f * CF(0, h, -.07) * ANG(0, PI / 2, 0), w, head, .14, glass, M.Neon)
	if opts.Mullion ~= false then
		K.Part(parent, "WindowMullion", V3(.18, h + head * .55, .12), f * CF(0, (h + head * .55) / 2, -.2), stone, M.Slate)
		K.Part(parent, "WindowTransom", V3(w, .16, .12), f * CF(0, h * .62, -.2), stone, M.Slate)
	end
	return pane
end

-- crooked gabled roof: cf = centre at eaves height, ridge along local Z (length d), span w along X, rise h. The ridge
-- is pushed sideways and sags, the slabs overhang and the ridge ends curl up. Returns the ridge-top CFrame.
-- opts: Color, Material, Overhang (.9), Thick (.55), Ridge (ridge beam colour)
function U.CrookedRoof(parent: Instance, cf: CFrame, w: number, d: number, h: number, rng, opts: any): CFrame
	opts = opts or {}
	local col = opts.Color or P.Slate
	local mat = opts.Material or M.Slate
	local ov = opts.Overhang or .9
	local th = opts.Thick or .55
	local rx = rng:NextNumber(-w, w) * .07
	local f = cf * ANG(0, rng:NextNumber(-.05, .05), 0)
	for half = -1, 1, 2 do -- two sections along the ridge, slightly different pitch: a sagging roof
		local z = half * d / 4
		local hh = h * (1 + half * rng:NextNumber(.02, .08))
		for _, side in ipairs({ -1, 1 }) do
			local ex = side * (w / 2 + ov)
			local run = math.abs(ex - rx)
			local ang = math.atan2(hh, run)
			local len = math.sqrt(run * run + hh * hh) + .25
			local mx = (ex + rx) / 2
			local slab = f * CF(mx, hh / 2, z) * ANG(0, 0, -side * ang) * CF(0, th / 2, 0)
			K.Part(parent, "RoofSlab", V3(len, th, d / 2 + ov + .05), slab, col:Lerp(P.Ink, rng:NextNumber(0, .25)), mat)
		end
	end
	local ridge = f * CF(rx, h + th * .9, 0)
	K.Part(parent, "RoofRidge", V3(.6, .5, d + ov * 2.2), ridge, opts.Ridge or col:Lerp(P.Ink, .4), mat)
	for _, sz in ipairs({ -1, 1 }) do
		K.Wedge(parent, "RoofCurl", V3(.5, 1.2, 1.1), ridge * CF(0, .5, sz * (d / 2 + ov * 1.1)) * ANG(0, sz > 0 and PI or 0, 0),
			opts.Ridge or col:Lerp(P.Ink, .4), mat)
	end
	return ridge
end

-- crooked cliff column (rock strata) from a top point down to bottomY; out = horizontal outward direction (the face
-- leans out a little, tiers shift). opts: Width (8), Depth (7), Tiers (3), Color, Shade, Material, Solid (true), Moss,
-- Push (fixed outward shift of the top tier; default random)
function U.CliffColumn(parent: Instance, top: Vector3, bottomY: number, out: Vector3, rng, opts: any): { BasePart }
	opts = opts or {}
	local parts = {}
	local tiers = opts.Tiers or 3
	local hTot = top.Y - bottomY
	if hTot <= .5 then
		return parts
	end
	local w, d = opts.Width or 8, opts.Depth or 7
	local o = Vector3.new(out.X, 0, out.Z)
	o = o.Magnitude > 1e-6 and o.Unit or Vector3.new(0, 0, -1)
	local y = top.Y
	for i = 1, tiers do
		local h = hTot / tiers * rng:NextNumber(.85, 1.15)
		if i == tiers then
			h = y - bottomY
		end
		local push = rng:NextNumber(-.8, 1.4) * (i == 1 and .5 or 1)
		if i == 1 and opts.Push then
			push = opts.Push
		end
		local c = Vector3.new(top.X, y - h / 2, top.Z) + o * push
		local cf = K.Look(c, c + o) * ANG(rng:NextNumber(-.06, .06), rng:NextNumber(-.12, .12), rng:NextNumber(-.05, .05))
		local col = (opts.Color or P.Rock):Lerp(opts.Shade or P.RockDark, (i - 1) / math.max(1, tiers - 1) * .8 + rng:NextNumber(0, .2))
		table.insert(parts, K.Part(parent, opts.Name or "CliffRock", V3(w * rng:NextNumber(.85, 1.15), h + .6, d * rng:NextNumber(.8, 1.2)), cf, col,
			opts.Material or M.Slate, if opts.Solid == false then nil else { Solid = true }))
		y -= h
		w *= rng:NextNumber(.95, 1.12)
	end
	if opts.Moss and rng:NextNumber() < opts.Moss then
		local c = top + o * (d * .45) - Vector3.new(0, rng:NextNumber(.5, 3), 0)
		K.Part(parent, "CliffMoss", V3(w * .7, .35, 1.2), K.Look(c, c + o) * ANG(.5, 0, 0), P.Moss, M.Grass)
	end
	return parts
end

------------------------------------------------------------------------------------------------------------------
-- creatures and props
------------------------------------------------------------------------------------------------------------------

-- crouching dog-headed gargoyle with folded bat wings (faces -Z of cf, feet on cf), s = scale (1: ~2.7 tall).
-- opts: Color, Eye (Neon colour), Wings (true), Mouth (open jaw + fangs, true), Name. Returns model, head CFrame.
function U.Gargoyle(parent: Instance, cf: CFrame, s: number, opts: any): (Model, CFrame)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "DogGargoyle")
	local g = opts.Color or C(88, 86, 102)
	local shade = g:Lerp(P.Ink, .3)
	local eye = opts.Eye or U.GLOW.Violet
	local function at(x, y, z)
		return cf * CF(x * s, y * s, z * s)
	end
	K.Ellipsoid(m, "GargoyleHaunch", V3(1.7 * s, 1.4 * s, 1.9 * s), at(0, .72, .45), g, M.Slate)
	K.Part(m, "GargoyleChest", V3(1.3 * s, 1.6 * s, 1.15 * s), at(0, 1.3, -.35) * ANG(.35, 0, 0), g, M.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "GargoyleLeg", V3(.38 * s, 1.3 * s, .42 * s), at(sx * .42, .65, -.78), g, M.Slate)
		K.Part(m, "GargoylePaw", V3(.5 * s, .26 * s, .66 * s), at(sx * .42, .13, -1.0), shade, M.Slate)
		K.Part(m, "GargoyleHindPaw", V3(.5 * s, .3 * s, .9 * s), at(sx * .82, .15, .25), shade, M.Slate)
		Y.GableTri(m, "GargoyleEar", at(sx * .32, 2.6, -.72) * ANG(0, PI / 2, sx * .18), .5 * s, 1.0 * s, .16 * s, shade, M.Slate)
		K.Ball(m, "GargoyleEye", .22 * s, at(sx * .24, 2.3, -1.32), eye, M.Neon)
		if opts.Wings ~= false then
			K.Wedge(m, "GargoyleWing", V3(.14 * s, 1.9 * s, 1.7 * s), at(sx * .78, 2.0, .45) * ANG(-.25, 0, sx * .55), shade, M.Slate)
			K.Wedge(m, "GargoyleWing", V3(.12 * s, 1.3 * s, 1.2 * s), at(sx * 1.15, 1.75, .95) * ANG(-.5, 0, sx * .8), shade:Lerp(P.Ink, .2), M.Slate)
		end
	end
	local head = at(0, 2.15, -.95)
	K.Part(m, "GargoyleHead", V3(1.0 * s, .9 * s, 1.0 * s), head, g, M.Slate)
	K.Part(m, "GargoyleBrow", V3(1.06 * s, .22 * s, .34 * s), head * CF(0, .32 * s, -.42 * s), shade, M.Slate)
	K.Part(m, "GargoyleSnout", V3(.56 * s, .42 * s, .95 * s), head * CF(0, -.12 * s, -.88 * s), g, M.Slate)
	K.Ball(m, "GargoyleNose", .26 * s, head * CF(0, 0, -1.36 * s), shade, M.Slate)
	if opts.Mouth ~= false then
		K.Part(m, "GargoyleJaw", V3(.5 * s, .2 * s, .8 * s), head * CF(0, -.5 * s, -.7 * s) * ANG(-.35, 0, 0), shade, M.Slate)
		for _, sx in ipairs({ -1, 1 }) do
			K.Wedge(m, "GargoyleFang", V3(.12 * s, .3 * s, .12 * s), head * CF(sx * .17 * s, -.42 * s, -1.22 * s) * ANG(PI, 0, 0), P.Bone, M.SmoothPlastic)
		end
	end
	K.Rod(m, "GargoyleTail", at(0, .5, 1.3).Position, at(.3, 1.4, 1.8).Position, .28 * s, g, M.Slate)
	return m, head
end

-- iron lantern (HwLantern glass), hanging from its top ring at cf (the ring is at cf; the body hangs below).
-- opts: Light (true), Range (16), Brightness (1), Attrs (extra glass attributes), Size (1), Lite (fewer parts: two
-- frame posts and a two-wedge roof, for lanterns repeated along roads). Returns model, glass.
function U.Lantern(parent: Instance, cf: CFrame, color: Color3, kind: string?, opts: any): (Model, BasePart)
	opts = opts or {}
	local m = K.Model(parent, "HwLantern")
	local s = opts.Size or 1
	local top = cf * CF(0, -1.25 * s, 0)
	local iron = P.Iron
	K.CylY(m, "LanternRing", .12 * s, .5 * s, cf, iron, M.CorrodedMetal)
	K.Part(m, "LanternCap", V3(1.4 * s, .3 * s, 1.4 * s), top * CF(0, 1.0 * s, 0), iron, M.CorrodedMetal)
	if opts.Lite then
		Y.GableTri(m, "LanternRoof", top * CF(0, 1.15 * s, 0), 1.3 * s, .55 * s, 1.3 * s, iron, M.CorrodedMetal)
	else
		U.Point(m, "LanternRoof", top * CF(0, 1.15 * s, 0), 1.3 * s, .55 * s, iron, M.CorrodedMetal)
	end
	local attrs = {}
	if kind then
		attrs.HwLantern = kind
	end
	for k, v in pairs(opts.Attrs or {}) do
		attrs[k] = v
	end
	local glass = K.Part(m, "LanternGlass", V3(.95 * s, 1.45 * s, .95 * s), top * CF(0, .15 * s, 0), color, M.Neon, { Attrs = attrs })
	for _, x in ipairs({ -.5, .5 }) do
		for _, z in ipairs({ -.5, .5 }) do
			if not opts.Lite or x == z then
				K.Part(m, "LanternFrame", V3(.12 * s, 1.65 * s, .12 * s), top * CF(x * s, .15 * s, z * s), iron, M.CorrodedMetal)
			end
		end
	end
	K.Part(m, "LanternBase", V3(1.2 * s, .25 * s, 1.2 * s), top * CF(0, -.7 * s, 0), iron, M.CorrodedMetal)
	if opts.Light ~= false then
		K.Light(glass, color, opts.Range or 16, opts.Brightness or 1)
	end
	return m, glass
end

-- crooked street lamp: stepped foot, a three-bend post leaning one way and back, a curled iron hook with a hanging
-- HwLantern, a small dog-skull finial. base = ground point, the hook reaches towards -Z of base.
-- opts: Height (11), Color (glass), Kind (HwLantern), Light (true), Range (20), Brightness (1.1), Iron, Lite (lighter
-- lantern and a bone-knob finial instead of the skull). Returns model, glass.
function U.Lamp(parent: Instance, base: CFrame, rng, opts: any): (Model, BasePart)
	opts = opts or {}
	local m = K.Model(parent, "CrookedLamp")
	local iron = opts.Iron or P.Iron
	local h = opts.Height or 11
	K.Part(m, "LampFoot", V3(1.7, .5, 1.7), base * CF(0, .25, 0), P.StoneDark, M.Slate, { Solid = true })
	K.CylY(m, "LampFootRing", .5, 1.2, base * CF(0, .75, 0), iron, M.CorrodedMetal)
	local pts = { (base * CF(0, .9, 0)).Position }
	local bends = { { .35, .9 }, { -.55, .55 }, { .3, -.4 } }
	for i, b in ipairs(bends) do
		local y = .9 + (h - .9) * i / 3
		table.insert(pts, (base * CF(b[1] * rng:NextNumber(.6, 1.2), y, b[2] * rng:NextNumber(.6, 1.2))).Position)
	end
	for i = 1, #pts - 1 do
		K.Rod(m, "LampPost", pts[i], pts[i + 1], .42 - i * .06, iron, M.CorrodedMetal, i == 1 and { Solid = true } or nil)
		if i < #pts - 1 then
			K.Ball(m, "LampKnuckle", .5 - i * .05, CF(pts[i + 1]), iron, M.CorrodedMetal)
		end
	end
	local top = pts[#pts]
	local fwd = base.LookVector
	local hookEnd = top + fwd * 2.6 + Vector3.new(0, .5, 0)
	K.Rod(m, "LampHook", top, hookEnd, .22, iron, M.CorrodedMetal)
	K.Rod(m, "LampCurl", hookEnd, hookEnd + fwd * .7 + Vector3.new(0, .6, 0), .18, iron, M.CorrodedMetal)
	K.Rod(m, "LampCurl", hookEnd + fwd * .7 + Vector3.new(0, .6, 0), hookEnd + fwd * .25 + Vector3.new(0, 1.0, 0), .15, iron, M.CorrodedMetal)
	if opts.Lite then
		K.Ball(m, "LampFinial", .55, CF(top + Vector3.new(0, .35, 0)), P.Bone, M.SmoothPlastic)
	else
		Y.Skull(m, K.Look(top + Vector3.new(0, .45, 0), top + Vector3.new(0, .45, 0) - fwd), .65, nil, P.Bone)
	end
	K.Bar(m, "LampChain", hookEnd, hookEnd - Vector3.new(0, .55, 0), .08, .14, iron, M.CorrodedMetal)
	local lm, glass = U.Lantern(m, K.Look(hookEnd - Vector3.new(0, .55, 0), hookEnd - Vector3.new(0, .55, 0) + fwd), opts.Color or U.GLOW.Candle,
		opts.Kind or "Orange", { Light = opts.Light, Range = opts.Range or 20, Brightness = opts.Brightness or 1.1, Attrs = opts.Attrs, Lite = opts.Lite })
	local _ = lm
	return m, glass
end

-- candle cluster (flames HwCandle); the first candle lights unless opts.Light == false
function U.Candles(parent: Instance, cf: CFrame, n: number, rng, opts: any): Model
	return K.Candles(parent, cf, n, rng, opts)
end

-- glowing flower: bent stem, five Neon petals around a dark heart. cf = ground point. opts: Color, Height (1.6), Size (1)
function U.Flower(parent: Instance, cf: CFrame, rng, opts: any)
	opts = opts or {}
	local h = (opts.Height or 1.6) * rng:NextNumber(.75, 1.2)
	local s = (opts.Size or 1) * rng:NextNumber(.8, 1.15)
	local col = opts.Color or U.GLOW.Green
	local lean = Vector3.new(rng:NextNumber(-.35, .35), 0, rng:NextNumber(-.35, .35))
	local a = cf.Position
	local mid = a + Vector3.new(0, h * .55, 0) + lean * .4
	local top = a + Vector3.new(0, h, 0) + lean
	K.Rod(parent, "FlowerStem", a, mid, .12, P.Moss, M.Grass)
	K.Rod(parent, "FlowerStem", mid, top, .1, P.Moss, M.Grass)
	local head = K.Look(top, top + Vector3.new(lean.X, 1.5, lean.Z), Vector3.new(0, 0, 1)) -- face up and a little out
	for k = 0, 4 do
		local ang = k / 5 * PI * 2 + rng:NextNumber(-.2, .2)
		K.Ellipsoid(parent, "FlowerPetal", V3(.42 * s, .12 * s, .7 * s), head * ANG(0, 0, ang) * CF(0, .36 * s, -.05) * ANG(-.5, 0, 0) * ANG(PI / 2, 0, 0),
			col, M.Neon)
	end
	K.Ball(parent, "FlowerHeart", .3 * s, head * CF(0, 0, -.12), P.Ink, M.SmoothPlastic)
end

-- patch of n glowing flowers within opts.Spread (2.2) of cf, with a couple of leaf blades
function U.FlowerPatch(parent: Instance, cf: CFrame, n: number, rng, opts: any): Model
	opts = opts or {}
	local m = K.Model(parent, "GlowFlowers")
	local spread = opts.Spread or 2.2
	for _ = 1, n do
		local a, r = rng:NextNumber(0, PI * 2), rng:NextNumber(0, spread)
		U.Flower(m, cf * CF(math.cos(a) * r, 0, math.sin(a) * r), rng, opts)
	end
	for k = 1, 2 do
		local a = rng:NextNumber(0, PI * 2)
		K.Wedge(m, "FlowerLeaf", V3(.12, .9, .6), cf * CF(math.cos(a) * .5, .45, math.sin(a) * .5) * ANG(0, a + k, .3), P.Moss, M.Grass)
	end
	return m
end

-- stalactite hanging from `top`: shrinking, twisting tiers and a downward point. opts: Tiers (3), Color, Shade,
-- Glow (Neon drip colour), Material, Twist. Returns the tip position.
function U.Stalactite(parent: Instance, top: Vector3, len: number, w: number, rng, opts: any): Vector3
	opts = opts or {}
	local n = opts.Tiers or 3
	local th = len / (n + .8)
	local cf = CF(top) * ANG(0, rng:NextNumber(0, PI), 0)
	local width = w
	local col = opts.Color or P.Rock
	for i = 1, n do
		cf = cf * ANG(rng:NextNumber(-.06, .06), (opts.Twist or .25) + rng:NextNumber(-.1, .1), rng:NextNumber(-.06, .06))
		local c = col:Lerp(opts.Shade or P.RockDark, (i - 1) / n * .7)
		K.Part(parent, opts.Name or "Stalactite", V3(width, th + .4, width * rng:NextNumber(.8, 1.1)), cf * CF(0, -th / 2, 0), c, opts.Material or M.Slate)
		cf = cf * CF(rng:NextNumber(-.08, .08) * width, -th, rng:NextNumber(-.08, .08) * width)
		width *= .68
	end
	local tipLen = th * .8
	Y.GableTri(parent, (opts.Name or "Stalactite") .. "Tip", cf * ANG(PI, 0, 0), width * 1.05, tipLen, width, col:Lerp(opts.Shade or P.RockDark, .7),
		opts.Material or M.Slate)
	local tip = (cf * CF(0, -tipLen, 0)).Position
	if opts.Glow then
		K.Ball(parent, "StalactiteDrip", math.max(.35, width * .35), CF(tip), opts.Glow, M.Neon)
	end
	return tip
end

-- curtain of roots hanging from `top` (strands wander down and thin out); opts: Count (3), Spread (2), Color, Glow
-- (Neon bulb colour at the strand tips: glow-worm threads), Thick (.7)
function U.Roots(parent: Instance, top: Vector3, len: number, rng, opts: any)
	opts = opts or {}
	local col = opts.Color or P.Root
	for _ = 1, opts.Count or 3 do
		local p = top + Vector3.new(rng:NextNumber(-1, 1) * (opts.Spread or 2), 0, rng:NextNumber(-1, 1) * (opts.Spread or 2))
		local th = (opts.Thick or .7) * rng:NextNumber(.75, 1.2)
		local l = len * rng:NextNumber(.6, 1.1)
		for k = 1, 3 do
			local q = p + Vector3.new(rng:NextNumber(-1.2, 1.2), -l / 3, rng:NextNumber(-1.2, 1.2))
			K.Rod(parent, "Root", p, q, th, col:Lerp(P.Ink, k * .12), M.Wood)
			p = q
			th *= .66
		end
		if opts.Glow then
			K.Ball(parent, "RootGlow", .45, CF(p), opts.Glow, M.Neon)
		end
	end
end

-- rune ring flush in the XZ plane of cf: n Neon arcs + short glyph ticks crossing it. Returns the parts (tag them).
-- opts: N (12), Fill (.7), Width (.35), H (.06), Color, Transparency (.25), Glyphs (true), Phase, Name
function U.RuneRing(parent: Instance, cf: CFrame, r: number, opts: any): { BasePart }
	opts = opts or {}
	local n = opts.N or 12
	local fill = opts.Fill or .7
	local out = {}
	local col = opts.Color or U.GLOW.Violet
	local props = function()
		return { Transparency = opts.Transparency or .25 }
	end
	for i = 1, n do
		local a0 = (i - 1) / n * PI * 2 + (opts.Phase or 0)
		local a1 = a0 + fill / n * PI * 2
		local pa = (cf * CF(math.cos(a0) * r, 0, math.sin(a0) * r)).Position
		local pb = (cf * CF(math.cos(a1) * r, 0, math.sin(a1) * r)).Position
		table.insert(out, K.Bar(parent, opts.Name or "RuneRing", pa, pb, opts.Width or .35, opts.H or .06, col, M.Neon, props()))
		if opts.Glyphs ~= false then
			local am = a1 + (1 - fill) / n * PI -- in the gap: a glyph (two crossed ticks)
			local g = cf * CF(math.cos(am) * r, 0, math.sin(am) * r) * ANG(0, -am, 0)
			table.insert(out, K.Part(parent, (opts.Name or "RuneRing") .. "Glyph", V3(r * .12 + .5, opts.H or .06, (opts.Width or .35) * .8),
				g * ANG(0, .5, 0), col, M.Neon, props()))
			table.insert(out, K.Part(parent, (opts.Name or "RuneRing") .. "Glyph", V3(r * .09 + .35, opts.H or .06, (opts.Width or .35) * .8),
				g * ANG(0, -.7, 0), col, M.Neon, props()))
		end
	end
	return out
end

-- bone fence a -> b on the ground: upright bone posts (shaft + two knuckles) every Spacing and two bone rails.
-- opts: Height (2.4), Spacing (3.2), Color, Solid (rails + posts collide). Returns the parts.
function U.BoneFence(parent: Instance, a: Vector3, b: Vector3, opts: any, rng): { BasePart }
	opts = opts or {}
	local out = {}
	local h = opts.Height or 2.4
	local col = opts.Color or P.Bone
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / (opts.Spacing or 3.2) + .5))
	local solid = opts.Solid and { Solid = true } or nil
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		local c = col:Lerp(P.BoneDark, rng and rng:NextNumber(0, .5) or .2)
		local tilt = rng and ANG(rng:NextNumber(-.08, .08), 0, rng:NextNumber(-.08, .08)) or CF()
		local post = CF(p) * tilt
		table.insert(out, K.CylY(parent, "BonePost", h, .42, post * CF(0, h / 2, 0), c, M.SmoothPlastic, solid))
		table.insert(out, K.Ball(parent, "BoneKnuckle", .5, post * CF(-.16, h + .05, 0), c, M.SmoothPlastic))
		table.insert(out, K.Ball(parent, "BoneKnuckle", .5, post * CF(.16, h + .05, 0), c, M.SmoothPlastic))
	end
	for _, y in ipairs({ h * .35, h * .75 }) do
		table.insert(out, K.Rod(parent, "BoneRail", a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), .26, col:Lerp(P.BoneDark, .3), M.SmoothPlastic, solid))
	end
	return out
end

-- sagging pennant string a -> b: a thin rope in `segs` straight pieces and alternating black / white (or opts.Colors)
-- triangular pennants hanging under it every opts.Spacing (2.2). opts: Sag (fraction of the span, .08), Size (1.1),
-- Colors, Segs (4). Non-collide. Returns the parts.
function U.Pennants(parent: Instance, a: Vector3, b: Vector3, opts: any): { BasePart }
	opts = opts or {}
	local out = {}
	local span = (b - a).Magnitude
	local sag = span * (opts.Sag or .08)
	local segs = opts.Segs or 4
	local function at(t: number): Vector3
		return a:Lerp(b, t) - Vector3.new(0, math.sin(t * PI) * sag, 0)
	end
	for i = 1, segs do
		table.insert(out, K.Bar(parent, "PennantRope", at((i - 1) / segs), at(i / segs), .1, .1, P.Ink, M.Fabric))
	end
	local cols = opts.Colors or { P.Black, P.White }
	local n = math.max(1, math.floor(span / (opts.Spacing or 2.2)))
	local s = opts.Size or 1.1
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	for k = 1, n do
		local t = (k - .5) / n
		local p = at(t)
		local cf = K.Look(p, p + (flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)))
		-- a downward-pointing triangle in the rope's vertical plane (thickness across the rope)
		-- (two right-triangle halves: each has its full-height leg on the centre line and its long leg along the rope)
		table.insert(out, K.Wedge(parent, "Pennant", V3(.06, s * 1.2, s * .5), cf * CF(0, -s * .6, -s * .25) * ANG(0, 0, PI), cols[k % 2 + 1], M.Fabric))
		table.insert(out, K.Wedge(parent, "Pennant", V3(.06, s * 1.2, s * .5), cf * CF(0, -s * .6, s * .25) * ANG(PI, 0, 0), cols[k % 2 + 1], M.Fabric))
	end
	return out
end

-- invisible collider wall between two ground points (XZ), from y0 to y1, thickness `thick` (2), lengthened by `pad`
-- (default = thick, half at each end, so chained walls close their joints; 0 = ends exactly at a and b). UyCollider.
function U.Collider(parent: Instance, a: Vector3, b: Vector3, y0: number, y1: number, thick: number?, pad: number?): BasePart
	local fa, fb = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local len = (fb - fa).Magnitude
	local mid = (fa + fb) / 2 + Vector3.new(0, (y0 + y1) / 2, 0)
	local cf = K.Look(mid, mid + (fb - fa))
	return K.Part(parent, "UyCollider", V3(thick or 2, y1 - y0, len + (pad or thick or 2)), cf, P.Violet, M.SmoothPlastic,
		{ Solid = true, Shadow = false, Transparency = 1 })
end

-- colliders along an arc round centre (radius r, layout angles a0..a1) leaving exact openings: gaps = { {Angle, Half} }
-- where Half is the half-width in studs of the opening measured across its radial line (a bridge whose side colliders
-- run at +-Half). Segments are at most maxLen long; their ends sit exactly on the opening edges. Returns the parts.
function U.ArcColliders(parent: Instance, centre: Vector3, r: number, a0: number, a1: number, gaps: { any }, y0: number, y1: number,
	maxLen: number?): { BasePart }
	-- blocked angle intervals, shifted into [a0, a0 + 2pi)
	local blocked = {}
	for _, g in ipairs(gaps) do
		local d = math.asin(math.clamp(g.Half / r, 0, 1))
		local mid = a0 + (g.Angle - a0) % (2 * PI)
		for _, wrap in ipairs({ -2 * PI, 0, 2 * PI }) do
			table.insert(blocked, { mid - d + wrap, mid + d + wrap })
		end
	end
	table.sort(blocked, function(x, y)
		return x[1] < y[1]
	end)
	local runs = {}
	local cur = a0
	for _, b in ipairs(blocked) do
		if b[2] > cur and b[1] < a1 then
			if b[1] > cur then
				table.insert(runs, { cur, math.min(b[1], a1) })
			end
			cur = math.max(cur, b[2])
		end
	end
	if cur < a1 then
		table.insert(runs, { cur, a1 })
	end
	local out = {}
	local step = (maxLen or 8) / r
	local eps = .6 / r -- inner joints overlap a little; the run ends stop exactly at the opening edges
	for _, run in ipairs(runs) do
		local n = math.max(1, math.ceil((run[2] - run[1]) / step))
		for i = 1, n do
			local ta = run[1] + (run[2] - run[1]) * (i - 1) / n - (i > 1 and eps or 0)
			local tb = run[1] + (run[2] - run[1]) * i / n + (i < n and eps or 0)
			table.insert(out, U.Collider(parent, U.Polar(centre, r, ta, 0), U.Polar(centre, r, tb, 0), y0, y1, 2, 0))
		end
	end
	return out
end

-- bilingual world sign: K.Sign + NoTranslate + TextEN / TextRU on the SurfaceGui and its TextLabel (the Underyard
-- client localizes them; AutoTranslate skips them). Shows the English text until the client swaps it.
function U.Sign(part: BasePart, face: Enum.NormalId, en: string, ru: string, color: Color3?, opts: any): SurfaceGui
	local g = K.Sign(part, face, en, color, opts)
	g:SetAttribute("NoTranslate", true)
	g:SetAttribute("TextEN", en)
	g:SetAttribute("TextRU", ru)
	local label = g:FindFirstChildOfClass("TextLabel")
	if label then
		label:SetAttribute("NoTranslate", true)
		label:SetAttribute("TextEN", en)
		label:SetAttribute("TextRU", ru)
	end
	return g
end

-- hanging bell (local y up, hangs from its crown at cf; mouth down): crown loop, stacked bronze bands flaring to a lip,
-- clapper. s = scale (1 = 2.2 wide at the lip). opts: Color, Lip, Clapper, Name. Returns model, body part, lip CFrame
function U.Bell(parent: Instance, cf: CFrame, s: number, opts: any): (Model, BasePart, CFrame)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "Bell")
	local col = opts.Color or C(118, 92, 60)
	local dark = col:Lerp(P.Ink, .35)
	K.CylZ(m, "BellLoop", .25 * s, .8 * s, cf * CF(0, -.2 * s, 0), dark, M.Metal)
	local profile = { { .25, .95 }, { .55, 1.25 }, { .95, 1.4 }, { 1.35, 1.55 }, { 1.7, 1.85 }, { 1.95, 2.2 } }
	local body
	for i, row in ipairs(profile) do
		local p = K.CylY(m, i == 1 and "BellCrown" or "BellBody", .5 * s, row[2] * s, cf * CF(0, -(.25 + row[1]) * s, 0), col:Lerp(dark, i % 2 == 0 and .2 or 0), M.Metal)
		if i == 3 then
			body = p
		end
	end
	local lip = cf * CF(0, -2.35 * s, 0)
	K.CylY(m, "BellLip", .22 * s, 2.4 * s, lip, opts.Lip or dark, M.Metal)
	K.Rod(m, "BellClapperRod", (cf * CF(0, -1.2 * s, 0)).Position, (cf * CF(0, -2.35 * s, 0)).Position, .14 * s, P.Iron, M.Metal)
	K.Ball(m, "BellClapper", .5 * s, cf * CF(0, -2.5 * s, 0), opts.Clapper or P.Iron, M.Metal)
	return m, body, lip
end

------------------------------------------------------------------------------------------------------------------
-- the veiled gate arch (Gates builder; also usable by districts)
------------------------------------------------------------------------------------------------------------------
-- cf = ground centre of the opening, faces -Z (towards the district); the square side is +Z. w = clear opening width,
-- h = pillar height. Two crooked pillars on plinths, a striped pointed arch, a dog-skull keystone with a hanging bell,
-- and the spectral veil filling the opening (layered translucent Neon strips + tattered hem + a rune ring) - every
-- veil part carries opts.VeilAttrs (e.g. {UyHideAtSeal = n}) and never collides.
-- opts: VeilAttrs, VeilColors {a, b}, Stone, Name. Returns { Model, Veil = {parts}, Apex = CFrame, Tops = {CFrame, CFrame}, Arch = {parts} }
function U.VeilArch(parent: Instance, cf: CFrame, w: number, h: number, rng, opts: any)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "VeilArch")
	local stone = opts.Stone or P.Stone
	local pw = 3.4
	local tops = {}
	for _, sx in ipairs({ -1, 1 }) do
		local base = cf * CF(sx * (w / 2 + pw / 2 + .2), 0, 0)
		K.Part(m, "ArchPlinth", V3(pw + 1.6, 1.4, pw + 1.8), base * CF(0, .7, 0), P.StoneDark, M.Slate, { Solid = true })
		K.Part(m, "ArchPlinthCap", V3(pw + 1.9, .35, pw + 2.1), base * CF(0, 1.55, 0), P.StoneLight, M.Slate)
		local top = U.Crooked(m, "ArchPillar", base * CF(0, 1.7, 0) * ANG(0, 0, -sx * .03), V3(pw, h - 1.7, pw + .6), 4, rng,
			{ Color = stone, Shade = P.StoneDark, Solid = 2, Lean = .02, Twist = .08, Shift = .02, Taper = .03 })
		table.insert(tops, top)
		-- black / white banded collar halfway up (accent)
		local collar = base * CF(0, h * .55, 0)
		for k = 0, 3 do
			K.Part(m, "ArchBand", V3(pw + .5, .45, pw + 1.1), collar * CF(0, k * .45, 0), k % 2 == 0 and P.Black or P.White, M.SmoothPlastic)
		end
	end
	local span = w + pw + .4
	local springs = cf * CF(0, h, 0)
	local arch, apex = U.Arch(m, "ArchRing", springs, span, pw + .4, 1.5, 5, { Stretch = 1.35, Striped = true })
	-- outer moulding (stone) a little behind / larger
	U.Arch(m, "ArchMoulding", springs * CF(0, 0, .3), span + 1.6, pw - .6, .8, 5, { Stretch = 1.38, Color = P.StoneDark, Radius = (span + 1.6) * .8 })
	-- keystone: dog skull facing the district, a bell hanging under the apex on the square side
	Y.Skull(m, apex * CF(0, .6, -1.0), 2.1, U.GLOW.Violet, P.Bone)
	Y.Skull(m, apex * CF(0, .6, 1.0) * ANG(0, PI, 0), 2.1, U.GLOW.Violet, P.Bone)
	K.Bar(m, "ArchBellChain", (apex * CF(0, -.6, 0)).Position, (apex * CF(0, -2.2, 0)).Position, .12, .2, P.Iron, M.CorrodedMetal)
	U.Bell(m, apex * CF(0, -2.2, 0), .75, { Name = "ArchBell" })
	-- the veil: two layers of translucent strips (staggered), shaped to the arch, plus a tattered hem
	local veil = {}
	local va = opts.VeilAttrs or {}
	local cols = opts.VeilColors or { C(150, 90, 240), C(140, 190, 255) }
	local n = 7
	local stripW = w / n
	for layer = 0, 1 do
		for i = 1, n do
			local x = -w / 2 + (i - .5) * stripW + (layer == 1 and stripW * .5 or 0)
			if math.abs(x) < w / 2 then
				local top = h + U.ArchInner(span, 1.5, x, { Stretch = 1.35 }) - .4
				local bottom = .3 + rng:NextNumber(0, .6) + layer * .5
				local col = cols[1]:Lerp(cols[2], (i / n + layer * .3) % 1)
				local p = K.Part(m, "VeilStrip", V3(stripW * .96, top - bottom, .08), cf * CF(x, (top + bottom) / 2, -.5 + layer * .9), col, M.Neon,
					{ Transparency = layer == 0 and .55 or .7 })
				table.insert(veil, p)
				if layer == 0 then
					local tat = K.Wedge(m, "VeilTatter", V3(.08, .9, stripW * .5), cf * CF(x, bottom - .2, -.5) * ANG(PI, PI / 2, 0), col, M.Neon,
						{ Transparency = .6 })
					table.insert(veil, tat)
				end
			end
		end
	end
	for _, p in ipairs(U.RuneRing(m, cf * CF(0, h * .55, -.05) * ANG(PI / 2, 0, 0), w * .28, { N = 8, Width = .3, H = .1, Color = C(220, 200, 255),
		Transparency = .35, Glyphs = false })) do
		table.insert(veil, p)
	end
	for _, p in ipairs(veil) do
		U.Tag(p, va)
	end
	return { Model = m, Veil = veil, Apex = apex, Tops = tops, Arch = arch }
end

return U
