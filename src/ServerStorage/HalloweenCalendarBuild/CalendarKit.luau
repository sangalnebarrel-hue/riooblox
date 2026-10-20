-- HALLOWEEN CALENDAR — build-time kit of the stage builders (ServerStorage.HalloweenCalendarBuild.CalendarKit).
-- Run offline by tools/edits/41_calendar.luau through tools/sim.luau (Instance.new + datatypes only, deterministic
-- YardKit Rng); the output is saved in ServerStorage.HalloweenCalendar.Stage01..Stage08. docs/halloween2/DESIGN.md §13.
--
-- 1. SITE — an occupancy model of the real main map, measured at build time:
--    * the island grass (EventTintSurface + Material Grass blocks, top y ~0; the players' yards excluded),
--    * every ground-level part (paths, plazas, buildings, props, lamps, trees, the Chapter I Halloween layer) as an AABB in
--      a spatial hash (flat invisible strips are ignored; invisible colliders count),
--    * keep-out boxes (yards, shops, Dead Yard, spawn, factory, shelter) and keep-out discs around every ProximityPrompt,
--      NavigationAnchor and *Door* / *Entrance* / *Gate* part.
--    Site:Free(x, z, r, opts) answers "a disc of radius r fully on open grass, PathMargin away from anything in the
--    height band [Y0, Y1]"; Site:Reserve adds what a builder placed, so later items (and later stages) never overlap.
--    Site:Pool() is the list of every free grass cell (2 studs) used for scattering; Site:Scatter picks from it.
-- 2. PROPS in the crooked stop-motion style of the Dead Yard (Kit / YardKit palette): crooked trees (faces with CalEyes,
--    swaying CalBranch models with CalSway / CalPivot, CalBatRoost), dead-grass patches with dry tufts and leaves,
--    creeping roots, pumpkin clusters, candle stumps, thorn bushes, grave clusters, rune circles, ghost markers, sky-island
--    silhouette trees, and the October 31 set pieces (scarecrow, giant jack-o'-lantern, ghost dogs, signpost).
-- Everything is anchored decor: never collides, never casts (the edit's final pass enforces it), lights Shadows=false.
-- Names avoid MapArtDirection keywords (trunk, leaves, lawn, soil, hedge, planting, promenade, boulevard …).
local HB = script.Parent.Parent.HalloweenBuild
local K = require(HB.Kit)
local Y = require(HB.YardKit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI, TAU = math.pi, math.pi * 2

local CK = {}
CK.K, CK.Y = K, Y

CK.BARK = C(54, 42, 48)
CK.BARK_DARK = C(32, 24, 32)
CK.BARK_PALE = C(118, 108, 104)
CK.DEAD = { C(176, 122, 52), C(150, 104, 46), C(168, 142, 70), C(132, 84, 44), C(120, 92, 54) }
CK.STRAW = { C(196, 164, 92), C(172, 136, 70), C(150, 112, 58) }
CK.LEAF = { C(196, 110, 40), C(170, 70, 30), C(210, 160, 60), C(128, 60, 34) }
CK.ROT = C(150, 80, 230) -- violet rot glow (Underyard palette)
CK.GLOW = { Orange = C(255, 150, 54), Green = C(134, 255, 110), Violet = C(176, 110, 255) }

------------------------------------------------------------------------------------------------------------------
-- geometry helpers
------------------------------------------------------------------------------------------------------------------
local function aabb(p: BasePart): (number, number, number, number, number, number)
	local cf, s = p.CFrame, p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
	local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(l.Y) * hz
	local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
	local c = cf.Position
	return c.X - ex, c.Y - ey, c.Z - ez, c.X + ex, c.Y + ey, c.Z + ez
end
CK.AABB = aabb

-- horizontal unit vector at angle a
local function dirAt(a: number): Vector3
	return V3(math.cos(a), 0, math.sin(a))
end
CK.DirAt = dirAt

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end
CK.Pick = pick

------------------------------------------------------------------------------------------------------------------
-- SITE
------------------------------------------------------------------------------------------------------------------
local Site = {}
Site.__index = Site
CK.SiteClass = Site

local HASH = 16 -- spatial hash cell (studs)

local function cellKey(i: number, k: number): number
	return (i + 4096) * 8192 + (k + 4096)
end

local function hashInsert(hash, e)
	for i = math.floor(e[1] / HASH), math.floor(e[2] / HASH) do
		for k = math.floor(e[3] / HASH), math.floor(e[4] / HASH) do
			local key = cellKey(i, k)
			local list = hash[key]
			if not list then
				list = {}
				hash[key] = list
			end
			table.insert(list, e)
		end
	end
end

local NAME_KEEPOUT = { "Door", "Entrance", "Gate", "Portal", "Spawn" }

-- district: Workspace.DOGROTS_District; cfg: HalloweenCalendarConfig; workspace: for prompts / anchors / spawns
function CK.Site(district: Instance, cfg, ws: Instance?)
	local b = cfg.Build
	local self = setmetatable({
		Cfg = cfg, Build = b, Blocked = {}, GrassHash = {}, Grass = {}, Walk = {}, WalkHash = {}, Discs = {}, Rects = {},
		Counts = { Grass = 0, Blocked = 0, Prompts = 0, Doors = 0 }, Reserved = 0, PoolCache = nil,
	}, Site)
	for _, r in ipairs(b.Keepout) do
		table.insert(self.Rects, r)
	end
	local skipTop = { ["13_TheVoid"] = true, ["08_GlobalDigSite"] = true, ["40_Underyard"] = true, [cfg.Root] = true }
	skipTop[string.match(b.SkyIslands, "^[^/]+") or "23_DistrictPolish"] = true
	local noGrass = {}
	for _, n in ipairs(cfg.Grass.Exclude) do
		noGrass[n] = true
	end
	for _, top in ipairs(district:GetChildren()) do
		if not skipTop[top.Name] then
			local list = top:IsA("BasePart") and { top } or {}
			for _, d in ipairs(top:GetDescendants()) do
				table.insert(list, d)
			end
			for _, d in ipairs(list) do
				if d:IsA("BasePart") then
					local x0, y0, z0, x1, y1, z1 = aabb(d)
					local isGrass = d.ClassName == "Part" and d.Material == M.Grass and d:GetAttribute("EventTintSurface") == true
						and not noGrass[top.Name] and (y1 - y0) < 6 and math.abs(d.CFrame.UpVector.Y) > .999
					if isGrass then
						local g = { x0, x1, z0, z1, y1, d }
						table.insert(self.Grass, g)
						hashInsert(self.GrassHash, g)
						self.Counts.Grass += 1
					elseif y1 > .12 and y0 < 60 and not (d.Transparency >= .95 and (y1 - y0) < 1.5) then
						local e = { x0, x1, z0, z1, y0, y1, d.Name }
						hashInsert(self.Blocked, e)
						self.Counts.Blocked += 1
						-- walkable surfaces (paths / plazas): flat, low, big — faces and roots look toward them
						if y1 < 1.4 and (y1 - y0) < 1.1 and (x1 - x0) * (z1 - z0) > 24 and d.Transparency < .95 then
							local w = { x0, x1, z0, z1 }
							table.insert(self.Walk, w)
							hashInsert(self.WalkHash, w)
						end
					end
					for _, word in ipairs(NAME_KEEPOUT) do
						if string.find(d.Name, word, 1, true) and y0 < 12 then
							table.insert(self.Rects, { X0 = x0 - b.PromptMargin, X1 = x1 + b.PromptMargin, Z0 = z0 - b.PromptMargin,
								Z1 = z1 + b.PromptMargin, Name = d.Name })
							self.Counts.Doors += 1
							break
						end
					end
				end
			end
		end
	end
	-- prompts, navigation anchors and spawns anywhere in the Workspace
	local wsRoot = ws or district.Parent
	if wsRoot then
		for _, d in ipairs(wsRoot:GetDescendants()) do
			local pos = nil
			if d:IsA("ProximityPrompt") then
				local par = d.Parent
				if par and par:IsA("BasePart") then
					pos = par.CFrame.Position
				elseif par and par:IsA("Attachment") and par.Parent and par.Parent:IsA("BasePart") then
					pos = (par.Parent.CFrame * par.CFrame).Position
				end
			elseif d:IsA("SpawnLocation") then
				pos = d.CFrame.Position
			elseif d.Parent and d.Parent.Name == "NavigationAnchors" and d:IsA("BasePart") then
				pos = d.CFrame.Position
			end
			if pos then
				table.insert(self.Discs, { X = pos.X, Z = pos.Z, R = b.PromptMargin + 3 })
				self.Counts.Prompts += 1
			end
		end
	end
	return self
end

-- grass top under (x, z), or nil (not on the island grass)
function Site:GrassTop(x: number, z: number): number?
	local list = self.GrassHash[cellKey(math.floor(x / HASH), math.floor(z / HASH))]
	if not list then
		return nil
	end
	local best = nil
	for _, g in ipairs(list) do
		if x >= g[1] and x <= g[2] and z >= g[3] and z <= g[4] and (best == nil or g[5] > best) then
			best = g[5]
		end
	end
	return best
end

function Site:InRules(x: number, z: number, r: number): boolean
	local isl = self.Build.Island
	if x - r < isl.X0 or x + r > isl.X1 or z - r < isl.Z0 or z + r > isl.Z1 then
		return false
	end
	for _, k in ipairs(self.Rects) do
		if x + r > k.X0 and x - r < k.X1 and z + r > k.Z0 and z - r < k.Z1 then
			return false
		end
	end
	for _, d in ipairs(self.Discs) do
		local dx, dz = x - d.X, z - d.Z
		if dx * dx + dz * dz < (d.R + r) * (d.R + r) then
			return false
		end
	end
	return true
end

-- nothing in the height band [y0, y1] within r + margin of (x, z)
function Site:Clear(x: number, z: number, r: number, y0: number, y1: number, margin: number): boolean
	local reach = r + margin
	local seen = {}
	for i = math.floor((x - reach) / HASH), math.floor((x + reach) / HASH) do
		for k = math.floor((z - reach) / HASH), math.floor((z + reach) / HASH) do
			local list = self.Blocked[cellKey(i, k)]
			if list then
				for _, e in ipairs(list) do
					if not seen[e] then
						seen[e] = true
						if e[6] > y0 and e[5] < y1 then
							local cx = math.clamp(x, e[1], e[2])
							local cz = math.clamp(z, e[3], e[4])
							local dx, dz = x - cx, z - cz
							if dx * dx + dz * dz < reach * reach then
								return false
							end
						end
					end
				end
			end
		end
	end
	return true
end

-- a disc of radius r fully on open grass: returns the grass top (y) or nil.
-- opts: Y0 (default .12), Y1 (default 6), Margin (default Build.PathMargin), NoGrass (skip the grass test: sky islands)
function Site:Free(x: number, z: number, r: number, opts: any): number?
	opts = opts or {}
	if not self:InRules(x, z, r) then
		return nil
	end
	local top = self:GrassTop(x, z)
	if not top then
		return nil
	end
	for k = 0, 7 do
		local a = k / 8 * TAU
		local t = self:GrassTop(x + math.cos(a) * r, z + math.sin(a) * r)
		if not t or math.abs(t - top) > .3 then
			return nil
		end
	end
	if not self:Clear(x, z, r, opts.Y0 or .12, opts.Y1 or 6, opts.Margin or self.Build.PathMargin) then
		return nil
	end
	return top
end

-- a tree: the base disc on clear grass and its crown in the air (overhanging a flat path is fine, a roof is not)
function Site:FreeTree(x: number, z: number, base: number, spread: number, height: number): number?
	local top = self:Free(x, z, base, { Y0 = .12, Y1 = 4 })
	if not top then
		return nil
	end
	if not self:Clear(x, z, spread, 3, height + 2, 1) then
		return nil
	end
	return top
end

function Site:Reserve(x: number, z: number, r: number, y0: number?, y1: number?, name: string?)
	local e = { x - r, x + r, z - r, z + r, y0 or 0, y1 or 8, name or "Calendar" }
	hashInsert(self.Blocked, e)
	self.Reserved += 1
end

-- direction (unit, horizontal) and distance from (x, z) to the nearest walkable surface within maxDist, or nil
function Site:NearestWalk(x: number, z: number, maxDist: number): (Vector3?, number?)
	local best, bestD = nil, maxDist
	local seen = {}
	for i = math.floor((x - maxDist) / HASH), math.floor((x + maxDist) / HASH) do
		for k = math.floor((z - maxDist) / HASH), math.floor((z + maxDist) / HASH) do
			local list = self.WalkHash[cellKey(i, k)]
			if list then
				for _, w in ipairs(list) do
					if not seen[w] then
						seen[w] = true
						local cx, cz = math.clamp(x, w[1], w[2]), math.clamp(z, w[3], w[4])
						local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
						if d < bestD and d > .01 then
							bestD = d
							best = V3(cx - x, 0, cz - z).Unit
						end
					end
				end
			end
		end
	end
	if best then
		return best, bestD
	end
	return nil, nil
end

-- every free grass cell (Build.Cell studs; r = 1, PathMargin) of the island: {X, Z, Top, D (distance to Grass.Origin)}
function Site:Pool(): { { X: number, Z: number, Top: number, D: number } }
	if self.PoolCache then
		return self.PoolCache
	end
	local out = {}
	local cell = self.Build.Cell
	local isl = self.Build.Island
	local o = self.Cfg.Grass.Origin
	for z = isl.Z0 + cell / 2, isl.Z1, cell do
		for x = isl.X0 + cell / 2, isl.X1, cell do
			local top = self:Free(x, z, 1)
			if top then
				table.insert(out, { X = x, Z = z, Top = top, D = math.sqrt((x - o.X) ^ 2 + (z - o.Z) ^ 2) })
			end
		end
	end
	self.PoolCache = out
	return out
end

-- pick up to `count` spots of radius r from the pool (re-checked against everything reserved so far, then reserved).
-- opts: Y0/Y1/Margin (the Free band), Spacing (extra distance between picks), Front (0..1: favour cells nearer the Dead
-- Yard — cells farther than Front × SpreadRange are rarely taken), Box {X0, X1, Z0, Z1}, Tree {Spread, Height},
-- Reserve {Y0, Y1} (what is reserved), Tries
function Site:Scatter(rng, count: number, r: number, opts: any): { { X: number, Z: number, Top: number } }
	opts = opts or {}
	local pool = self:Pool()
	local out = {}
	if #pool == 0 or count <= 0 then
		return out
	end
	local range = self.Cfg.Grass.SpreadRange
	local tries = opts.Tries or count * 60
	for _ = 1, tries do
		if #out >= count then
			break
		end
		local c = pool[rng:NextInteger(1, #pool)]
		local ok = true
		if opts.Box then
			local bx = opts.Box
			ok = c.X >= bx.X0 and c.X <= bx.X1 and c.Z >= bx.Z0 and c.Z <= bx.Z1
		end
		if ok and opts.Front then
			local u = c.D / range
			if u > opts.Front and rng:NextNumber() > math.exp(-(u - opts.Front) * 22) then
				ok = false
			end
		end
		if ok then
			local x = c.X + rng:NextNumber(-.9, .9)
			local z = c.Z + rng:NextNumber(-.9, .9)
			local top
			if opts.Tree then
				top = self:FreeTree(x, z, r, opts.Tree.Spread, opts.Tree.Height)
			else
				top = self:Free(x, z, r + (opts.Spacing or 0), { Y0 = opts.Y0, Y1 = opts.Y1, Margin = opts.Margin })
			end
			if top then
				local res = opts.Reserve or {}
				self:Reserve(x, z, r + (opts.Spacing or 0), res.Y0 or 0, res.Y1 or (opts.Tree and opts.Tree.Height or 6))
				if opts.Tree then
					self:Reserve(x, z, opts.Tree.Spread, 3, opts.Tree.Height, "Crown")
				end
				table.insert(out, { X = x, Z = z, Top = top })
			end
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- PROPS
------------------------------------------------------------------------------------------------------------------
local function mark(m: Instance, attrs: { [string]: any })
	for k, v in pairs(attrs) do
		m:SetAttribute(k, v)
	end
end

-- jagged face carved into a trunk: dark eye sockets with CalEyes glow balls (closed = Transparency 1 in the saved
-- place; HalloweenClient.CalendarFX opens / blinks them from D-4), angry brows, a knot nose, a toothy mouth.
-- at = the bark surface point on the stem axis' side, n = outward normal (horizontal), R = stem radius, s = face scale
-- (studs per face unit; the face is ~1.4 s wide). Every feature follows the stem's curvature (no floating brows).
-- opts: EyeColor, MouthGlow (Neon mouth), Open (eyes saved open)
function CK.Face(m: Instance, at: Vector3, n: Vector3, R: number, s: number, rng, opts: any)
	opts = opts or {}
	local f = K.Look(at, at + n) -- LookVector = outward; local -Z = out of the bark
	local ink = C(16, 10, 20)
	local eye = opts.EyeColor or CK.GLOW.Orange
	local eyes = {}
	-- a point on the bark at face-local (x, y), `out` studs outward of the curved surface
	local function onBark(x: number, y: number, out: number): CFrame
		local dz = R - math.sqrt(math.max(0, R * R - x * x))
		return f * CF(x, y, -out + dz)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local sock = onBark(sx * .38 * s, .28 * s, -.04 * s)
		K.Ellipsoid(m, "FaceSocket", V3(.46 * s, .56 * s, .4 * s), sock * ANG(0, 0, sx * .3), ink, M.SmoothPlastic)
		local e = K.Ball(m, "FaceEye", .26 * s, sock * CF(0, -.03 * s, -.11 * s), eye, M.Neon,
			{ Transparency = opts.Open and 0 or 1, Attrs = { CalEyes = true, CalEyeColor = eye } })
		table.insert(eyes, e)
		K.Bar(m, "FaceBrow", onBark(sx * .6 * s, .55 * s, .02 * s).Position, onBark(sx * .12 * s, .45 * s, .02 * s).Position,
			.13 * s, .12 * s, CK.BARK_DARK, M.Wood)
	end
	K.Ball(m, "FaceKnot", .22 * s, onBark(0, .02 * s, -.04 * s), CK.BARK, M.Wood)
	local mouth = onBark(0, -.4 * s, -.06 * s)
	K.Ellipsoid(m, "FaceMouth", V3(1.0 * s, .44 * s, .42 * s), mouth * ANG(0, 0, rng:NextNumber(-.12, .12)), ink, M.SmoothPlastic)
	if opts.MouthGlow then
		K.Ellipsoid(m, "FaceMouthGlow", V3(.74 * s, .24 * s, .3 * s), mouth * CF(0, -.02 * s, -.07 * s), opts.MouthGlow, M.Neon)
	end
	for k = -1, 1 do
		local tooth = onBark(k * .24 * s, -.26 * s, .1 * s)
		K.Wedge(m, "FaceTooth", V3(.09 * s, .18 * s, .12 * s), tooth * ANG(PI, 0, 0), P.BoneDark, M.Wood)
	end
	return eyes
end

-- CROOKED TREE (base on the ground at `base`): flared roots sinking into the grass, a zig-zag stem in 5 tapering
-- segments that leans and twists, and 4-6 long claw branches — out, a sharp crook up, then a hooked tip curling down
-- (each branch its own CalBranch model: CalSway, CalPivot, CalPhase, CalAxis -> the client sways it about its base) —
-- with thin side twigs and knots at every joint. opts: Thick (stem diameter / h, .1), Branches, Face (bool), FaceDir,
-- EyeColor, MouthGlow, EyesOpen, Bark (Color3), Roost (CalBatRoost attachment), Lantern (Color3) + Lanterns (how many
-- branches carry one), LanternLight, Lite (fewer twigs / roots), Lean (radians), Name.
-- Returns model, info {Eyes, Branches, Top, Spread, Tips}
function CK.CrookedTree(parent: Instance, base: Vector3, h: number, rng, opts: any)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "CrookedTree")
	local bark = opts.Bark or CK.BARK:Lerp(CK.BARK_DARK, rng:NextNumber(0, .5))
	local dark = bark:Lerp(P.Ink, .4)
	local thick = h * (opts.Thick or .1)
	local info = { Eyes = {}, Branches = {}, Spread = 0 }
	-- the face looks toward FaceDir; no root may cross in front of it
	local faceDir = opts.Face and (opts.FaceDir or dirAt(rng:NextNumber(0, TAU))) or nil
	local faceA = faceDir and math.atan2(faceDir.Z, faceDir.X) or nil
	-- roots: flared, two segments each, the tip sinking under the grass; a small dirt mound hides the joint
	local nRoots = opts.Lite and 3 or rng:NextInteger(4, 5)
	for k = 1, nRoots do
		local a = k / nRoots * TAU + rng:NextNumber(-.4, .4)
		if faceA then
			local d = (a - faceA + PI) % TAU - PI
			if math.abs(d) < .75 then
				a = faceA + (d >= 0 and .75 or -.75)
			end
		end
		local reach = thick * rng:NextNumber(1.1, 1.55)
		local tip = base + dirAt(a) * reach + V3(0, -.15, 0)
		local mid = base + dirAt(a + rng:NextNumber(-.25, .25)) * reach * .5 + V3(0, thick * .22, 0)
		K.Rod(m, "TreeRoot", base + V3(0, thick * .45, 0), mid, thick * .4, dark, M.Wood)
		K.Rod(m, "TreeRoot", mid, tip, thick * .24, dark, M.Wood)
		K.Ball(m, "TreeKnot", thick * .4, CF(mid), dark, M.Wood)
	end
	K.Ellipsoid(m, "RootMound", V3(thick * 1.9, thick * .38, thick * 1.9), CF(base + V3(0, .02, 0)), C(62, 48, 42), M.Ground)
	-- the stem: zig-zag with a slow twist, tapering hard so the crown reads thin and spiky
	local p = base
	local lean = opts.Lean or rng:NextNumber(0, TAU)
	local dir = (V3(0, 1, 0) + dirAt(lean) * rng:NextNumber(.1, .25)).Unit
	local th = thick
	local joints = {}
	local stemParts = {}
	local segs = 5
	local lens = { .2, .16, .14, .12, .1 }
	for k = 1, segs do
		local q = p + dir * h * lens[k]
		local part = K.Rod(m, "TreeStem", p, q, th, bark:Lerp(dark, k * .07), M.Wood)
		table.insert(stemParts, { Part = part, A = p, B = q, Th = th })
		K.Ball(m, "TreeKnot", th * 1.04, CF(q), bark, M.Wood)
		joints[k] = { q, dir, th }
		local zig = (k % 2 == 0) and 1 or -1
		dir = (dir + dirAt(lean + zig * rng:NextNumber(1, 1.7)) * rng:NextNumber(.3, .5)).Unit
		th *= .7
		p = q
	end
	info.Top = p
	-- the stem's tip hooks over like a crooked finger
	local hookDir = (dirAt(lean + PI + rng:NextNumber(-.5, .5)) + V3(0, -.35, 0)).Unit
	local hookEnd = p + hookDir * h * .07
	K.Rod(m, "TreeTwig", p, hookEnd, th, dark, M.Wood)
	-- a carved face on the first segment, looking at FaceDir (toward the nearest walk)
	if opts.Face then
		local seg = stemParts[1]
		local a0, a1, sth = seg.A, seg.B, seg.Th
		local axisP = a0:Lerp(a1, .74)
		local fd = faceDir or dirAt(0)
		local axis = (a1 - a0).Unit
		local nrm = (fd - axis * fd:Dot(axis))
		nrm = nrm.Magnitude > 1e-3 and nrm.Unit or fd
		local R = sth * .5
		local eyes = CK.Face(m, axisP + nrm * R * .96, nrm, R, R * 1.15, rng,
			{ EyeColor = opts.EyeColor, MouthGlow = opts.MouthGlow, Open = opts.EyesOpen })
		info.Eyes = eyes
		m:SetAttribute("CalFace", true)
	end
	-- claw branches (own models so the client can sway them about their base)
	local nb = opts.Branches or rng:NextInteger(4, 5)
	local tips = {}
	for bi = 1, nb do
		local j = joints[math.clamp(2 + (bi - 1) % (segs - 1), 2, segs)]
		local from = j[1]
		local bm = K.Model(m, "CalBranch")
		local a = bi / nb * TAU + rng:NextNumber(-.45, .45) + lean
		local bth = j[3] * .58
		local len = h * rng:NextNumber(.3, .42) * (bi == 1 and 1.1 or 1)
		local q = from
		local reach = 0
		local curl = rng:NextNumber() < .5 and 1 or -1
		-- out and a little up, a sharp crook upward, out again, then the hooked tip curling down / sideways
		local dirs = {
			(dirAt(a) + V3(0, rng:NextNumber(.25, .55), 0)).Unit,
			(dirAt(a + curl * .35) * .45 + V3(0, 1, 0)).Unit,
			(dirAt(a + curl * .7) + V3(0, rng:NextNumber(-.05, .25), 0)).Unit,
			(dirAt(a + curl * 1.6) * .7 + V3(0, -.75, 0)).Unit,
		}
		local share = { .34, .26, .24, .16 }
		for sIdx = 1, 4 do
			local nd = dirs[sIdx]
			local seglen = len * share[sIdx]
			local nq = q + nd * seglen
			K.Rod(bm, sIdx == 1 and "TreeBranch" or "TreeTwig", q, nq, math.max(.18, bth), sIdx <= 2 and bark or dark, M.Wood)
			if sIdx < 4 then
				K.Ball(bm, "TreeKnot", math.max(.18, bth) * 1.05, CF(nq), bark, M.Wood)
			end
			-- thin side twigs off the crook and the third segment
			if (sIdx == 2 or (sIdx == 3 and not opts.Lite)) and bth > .2 then
				local td = (nd + dirAt(a + (rng:NextNumber() < .5 and 1.2 or -1.2)) * .8 + V3(0, .45, 0)).Unit
				local tEnd = nq + td * seglen * rng:NextNumber(.55, .8)
				K.Rod(bm, "TreeTwig", nq, tEnd, math.max(.12, bth * .45), dark, M.Wood)
				table.insert(tips, tEnd)
			end
			q = nq
			bth *= .68
			reach = math.max(reach, V3(q.X - base.X, 0, q.Z - base.Z).Magnitude)
		end
		table.insert(tips, q)
		info.Spread = math.max(info.Spread, reach)
		mark(bm, { CalSway = true, CalPivot = from, CalPhase = rng:NextNumber(0, TAU), CalAxis = V3(-math.sin(a), 0, math.cos(a)) })
		table.insert(info.Branches, bm)
		-- lanterns hang from the first `Lanterns` branches, under the end of the outer segment
		if opts.Lantern and bi <= (opts.Lanterns or 1) then
			local hook = from + dirs[1] * len * share[1] + dirs[2] * len * share[2] + dirs[3] * len * share[3] * .7
			CK.HangingLantern(bm, hook - V3(0, math.max(.18, j[3] * .58 * .68 * .68) * .5, 0), rng:NextNumber(1.6, 2.4), opts.Lantern,
				opts.LanternLight ~= false)
		end
		if opts.Roost and bi == 2 then
			local rp = K.Part(bm, "RoostPoint", V3(.2, .2, .2), CF(from:Lerp(q, .5) - V3(0, .5, 0)), dark, nil, { Transparency = 1 })
			K.Attach(rp, "CalBatRoost")
		end
	end
	info.Tips = tips
	m:SetAttribute("CalHeight", h)
	return m, info
end

-- iron lantern hanging on a chain (the glass carries HwLantern; one PointLight unless light == false)
function CK.HangingLantern(parent: Instance, hook: Vector3, drop: number, color: Color3, light: boolean?)
	local lm = K.Model(parent, "CalLantern")
	local bottom = hook - V3(0, drop, 0)
	K.Bar(lm, "LanternChain", hook, bottom + V3(0, .55, 0), .1, .1, P.Iron, M.CorrodedMetal)
	K.Part(lm, "LanternCap", V3(.8, .2, .8), CF(bottom + V3(0, .5, 0)), P.Iron, M.CorrodedMetal)
	local glass = K.Part(lm, "LanternGlass", V3(.55, .8, .55), CF(bottom), color, M.Neon, { Attrs = { HwLantern = "Orange" } })
	K.Part(lm, "LanternBase", V3(.7, .16, .7), CF(bottom - V3(0, .46, 0)), P.Iron, M.CorrodedMetal)
	if light ~= false then
		K.Light(glass, color, 14, .9)
	end
	return lm
end

-- flat organic discs of dead grass on the grass top, dry tufts standing in them, maybe fallen leaves.
-- pos = centre (y ignored), top = grass top y. opts: Tufts, Leaves, Layers
function CK.DeadPatch(parent: Instance, pos: Vector3, top: number, r: number, rng, opts: any)
	opts = opts or {}
	local m = K.Model(parent, "DeadGrass")
	local layers = opts.Layers or rng:NextInteger(2, 3)
	for k = 1, layers do
		local a = rng:NextNumber(0, TAU)
		local off = k == 1 and V3() or dirAt(a) * r * rng:NextNumber(.3, .6)
		local rr = (k == 1 and r or r * rng:NextNumber(.45, .7))
		local y = top + .05 + k * .022
		-- a thin cylinder disc (axis up)
		K.Part(m, "DeadGrassMat", V3(.06, rr * 2, rr * 2), CF(pos.X + off.X, y, pos.Z + off.Z) * ANG(0, a, PI / 2),
			pick(rng, CK.DEAD):Lerp(C(96, 80, 50), rng:NextNumber(0, .25)), M.Grass, { Shape = Enum.PartType.Cylinder })
	end
	for _ = 1, opts.Tufts or rng:NextInteger(2, 4) do
		local a, d = rng:NextNumber(0, TAU), rng:NextNumber(0, r * .8)
		local at = V3(pos.X, top, pos.Z) + dirAt(a) * d
		local hgt = rng:NextNumber(.7, 1.5)
		local col = pick(rng, CK.STRAW)
		local yaw = rng:NextNumber(0, TAU)
		for blade = 1, 2 do
			local tilt = (blade == 1 and 1 or -1) * rng:NextNumber(.15, .4)
			K.Wedge(m, "DryTuft", V3(.08, hgt, .45), CF(at + V3(0, hgt / 2 - .05, 0)) * ANG(0, yaw + blade * 1.4, tilt), col, M.Grass)
		end
	end
	for _ = 1, opts.Leaves or 0 do
		local a, d = rng:NextNumber(0, TAU), rng:NextNumber(0, r * 1.1)
		local at = V3(pos.X, top + .14, pos.Z) + dirAt(a) * d
		K.Part(m, "DryLeaf", V3(.55, .05, .38), CF(at) * ANG(rng:NextNumber(-.15, .15), rng:NextNumber(0, TAU), rng:NextNumber(-.15, .15)),
			pick(rng, CK.LEAF), M.SmoothPlastic)
	end
	return m
end

-- dead thorn bush: a knot of crooked bare twigs on a dark mound
function CK.Thorns(parent: Instance, pos: Vector3, top: number, rng, size: number?)
	local s = size or rng:NextNumber(1.6, 2.6)
	local m = K.Model(parent, "ThornBush")
	local base = V3(pos.X, top, pos.Z)
	K.Ellipsoid(m, "ThornMound", V3(s * 1.3, s * .3, s * 1.2), CF(base + V3(0, .04, 0)), C(52, 40, 38), M.Ground)
	for k = 1, 6 do
		local a = k / 6 * TAU + rng:NextNumber(-.3, .3)
		local d = (dirAt(a) * rng:NextNumber(.5, .9) + V3(0, rng:NextNumber(.7, 1.2), 0)).Unit
		local a1 = base + V3(0, .1, 0)
		local a2 = a1 + d * s * rng:NextNumber(.5, .8)
		local a3 = a2 + (d + dirAt(a + 1.2) * .7).Unit * s * .4
		K.Rod(m, "ThornTwig", a1, a2, .16, CK.BARK_DARK, M.Wood)
		K.Rod(m, "ThornTwig", a2, a3, .1, CK.BARK, M.Wood)
	end
	return m
end

-- creeping roots: n tendrils from `origin` that crawl over the grass toward the nearest path and stop short of it
-- (every segment end is re-checked on the site); violet rot nodules on some. Returns the model (nil if nothing fits)
function CK.Roots(parent: Instance, site, origin: Vector3, top: number, rng, n: number, dir: Vector3?)
	local m = K.Model(parent, "CreepingRoots")
	local count = 0
	for t = 1, n do
		local a = dir and math.atan2(dir.Z, dir.X) + rng:NextNumber(-.9, .9) or rng:NextNumber(0, TAU)
		local p = V3(origin.X, top + .12, origin.Z)
		local th = rng:NextNumber(.55, .8)
		for s = 1, rng:NextInteger(4, 7) do
			a += rng:NextNumber(-.55, .55)
			local len = rng:NextNumber(1.8, 3)
			local q = p + dirAt(a) * len
			local gt = site:Free(q.X, q.Z, th * .6 + .3, { Y0 = .12, Y1 = 3, Margin = 1.6 })
			if not gt then
				break
			end
			q = V3(q.X, gt + .1 + th * .15, q.Z)
			K.Rod(m, "CreepRoot", p, q, th, (s % 2 == 0) and CK.BARK or CK.BARK_DARK, M.Wood)
			K.Ball(m, "CreepKnot", th * 1.06, CF(q), CK.BARK, M.Wood)
			if rng:NextNumber() < .22 then
				K.Ball(m, "RotNodule", th * .55, CF(q + V3(0, th * .45, 0)), CK.ROT, M.Neon)
			end
			site:Reserve(q.X, q.Z, th, 0, 1.5, "Root")
			count += 1
			p = q
			th *= .86
		end
		local _ = t
	end
	if count == 0 then
		m:Destroy()
		return nil
	end
	return m
end

-- 1-3 pumpkins with a vine (one carved; `light` gives the carved one a PointLight)
function CK.PumpkinCluster(parent: Instance, pos: Vector3, top: number, rng, opts: any)
	opts = opts or {}
	local m = K.Model(parent, "PumpkinCluster")
	local n = opts.Count or rng:NextInteger(2, 3)
	local face = opts.Face or dirAt(rng:NextNumber(0, TAU))
	local yaw = math.atan2(-face.X, -face.Z)
	local prev = nil
	for k = 1, n do
		local size = k == 1 and (opts.Size or rng:NextNumber(2.2, 3.2)) or rng:NextNumber(1.2, 2)
		local off = k == 1 and V3() or dirAt(rng:NextNumber(0, TAU)) * rng:NextNumber(1.6, 2.4)
		local at = V3(pos.X + off.X, top - .1, pos.Z + off.Z)
		local carved = k == 1 and opts.Carved ~= false
		Y.Pumpkin(m, CF(at) * ANG(0, yaw + rng:NextNumber(-.5, .5), 0), size, { Face = carved, Light = carved and opts.Light == true,
			Glow = opts.Glow, Lobes = 5, Color = P.Pumpkin:Lerp(P.PumpkinDark, rng:NextNumber(0, .35)) })
		local stem = at + V3(0, size * .8, 0)
		if prev then
			local mid = (prev + stem) / 2 + V3(0, .3, 0)
			K.Rod(m, "PumpkinVine", prev, V3(mid.X, top + .2, mid.Z), .14, P.Stem, M.Grass)
			K.Rod(m, "PumpkinVine", V3(mid.X, top + .2, mid.Z), stem, .14, P.Stem, M.Grass)
			K.Ellipsoid(m, "VineLeaf", V3(1.1, .08, .8), CF(mid.X, top + .16, mid.Z) * ANG(0, rng:NextNumber(0, TAU), 0), C(78, 92, 40), M.Grass)
		end
		prev = stem
	end
	return m
end

-- a cut stump with a candle cluster on top (one PointLight when light ~= false)
function CK.CandleStump(parent: Instance, pos: Vector3, top: number, rng, light: boolean?)
	local m = K.Model(parent, "CandleStump")
	local h = rng:NextNumber(.9, 1.5)
	local d = rng:NextNumber(1.5, 2.1)
	K.CylY(m, "StumpWood", h, d, CF(pos.X, top + h / 2, pos.Z), CK.BARK, M.Wood)
	K.CylY(m, "StumpRing", .06, d * .9, CF(pos.X, top + h + .02, pos.Z), C(150, 116, 84), M.Wood)
	for k = 1, 3 do
		local a = k / 3 * TAU + rng:NextNumber(-.3, .3)
		K.Rod(m, "StumpRoot", V3(pos.X, top + h * .5, pos.Z) + dirAt(a) * d * .35, V3(pos.X, top, pos.Z) + dirAt(a) * d * .85, d * .22, CK.BARK_DARK, M.Wood)
	end
	K.Candles(m, CF(pos.X, top + h + .03, pos.Z), rng:NextInteger(3, 4), rng, { Spread = d * .3, Light = light ~= false, Range = 10 })
	-- wax drips down the side
	K.Part(m, "WaxDrip", V3(.16, h * .5, .1), CF(V3(pos.X, top + h * .78, pos.Z) + dirAt(rng:NextNumber(0, TAU)) * d * .5), P.Candle, M.SmoothPlastic)
	return m
end

-- 2-4 small dog graves sprouting crooked
function CK.GraveCluster(parent: Instance, pos: Vector3, top: number, rng, face: Vector3?)
	local m = K.Model(parent, "SproutedGraves")
	local f = face or dirAt(rng:NextNumber(0, TAU))
	local n = rng:NextInteger(2, 3)
	for k = 1, n do
		local off = k == 1 and V3() or dirAt(rng:NextNumber(0, TAU)) * rng:NextNumber(2.4, 3.4)
		local at = V3(pos.X + off.X, top, pos.Z + off.Z)
		local style = pick(rng, { 1, 3, 4, 6, 7, 9 })
		Y.Tombstone(m, K.Look(at, at + f) * ANG(0, PI, 0), style, rng, nil, { NoTranslate = true })
		K.Ellipsoid(m, "GraveDirt", V3(2.4, .3, 3), CF(at + V3(0, .06, 0)) * ANG(0, math.atan2(f.X, f.Z), 0) * CF(0, 0, -1.4), C(70, 54, 46), M.Ground)
	end
	return m
end

-- a flush neon rune circle on the grass with stones (spectral)
function CK.RuneCircle(parent: Instance, pos: Vector3, top: number, r: number, rng, color: Color3?)
	local m = K.Model(parent, "RuneCircle")
	local col = color or CK.ROT
	local cf = CF(pos.X, top + .04, pos.Z)
	Y.RuneRing(m, cf, r, 12, .3, col, { Fill = .7, Transparency = .25, H = .06 })
	Y.RuneRing(m, cf, r * .62, 8, .2, col, { Fill = .55, Phase = .3, Transparency = .35, H = .06 })
	for k = 1, 5 do
		local a = k / 5 * TAU
		local at = V3(pos.X, top, pos.Z) + dirAt(a) * (r + .9)
		K.Part(m, "RuneStone", V3(.9, rng:NextNumber(1.1, 1.8), .7), CF(at + V3(0, .55, 0)) * ANG(rng:NextNumber(-.12, .12), a, rng:NextNumber(-.12, .12)),
			P.StoneDark, M.Slate)
	end
	return m
end

-- an invisible marker for client presences (distant ghosts, bat roosts on open ground)
function CK.Marker(parent: Instance, name: string, pos: Vector3, attrs: { [string]: any }?)
	local p = K.Part(parent, name .. "Marker", V3(.2, .2, .2), CF(pos), P.Ink, nil, { Transparency = 1 })
	return K.Attach(p, name, CF(), attrs)
end

-- silhouette tree for the far sky islands: chunky, few parts, two glowing eyes (CalEyes) that read at 600 studs
function CK.SkyTree(parent: Instance, base: Vector3, h: number, rng, opts: any)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "SkyCrookedTree")
	local bark = CK.BARK_DARK:Lerp(P.Ink, rng:NextNumber(0, .4))
	local lean = rng:NextNumber(0, TAU)
	local dir = (V3(0, 1, 0) + dirAt(lean) * .2).Unit
	local th = h * .1
	local p = base - V3(0, .4, 0)
	K.Ellipsoid(m, "RootMound", V3(th * 3, th * .7, th * 3), CF(base), bark, M.Wood)
	local joints = {}
	local first = nil
	for k = 1, 3 do
		local q = p + dir * h * ({ .3, .22, .16 })[k]
		K.Rod(m, "TreeStem", p, q, th, bark, M.Wood)
		K.Ball(m, "TreeKnot", th, CF(q), bark, M.Wood)
		joints[k] = { q, th }
		if k == 1 then
			first = { p, q, th }
		end
		dir = (dir + dirAt(lean + (k % 2 == 0 and 1.3 or -1.3)) * .4).Unit
		th *= .72
		p = q
	end
	for bi = 1, 4 do
		local j = joints[bi <= 2 and 2 or 3]
		local a = bi / 4 * TAU + rng:NextNumber(-.4, .4) + lean
		local curl = (bi % 2 == 0) and 1 or -1
		local q1 = j[1] + (dirAt(a) + V3(0, .4, 0)).Unit * h * .17
		local q2 = q1 + (dirAt(a + curl * .4) * .4 + V3(0, 1, 0)).Unit * h * .12
		local q3 = q2 + (dirAt(a + curl * 1.2) * .8 + V3(0, -.6, 0)).Unit * h * .08
		K.Rod(m, "TreeBranch", j[1], q1, j[2] * .58, bark, M.Wood)
		K.Rod(m, "TreeTwig", q1, q2, j[2] * .4, bark, M.Wood)
		K.Rod(m, "TreeTwig", q2, q3, j[2] * .26, bark, M.Wood)
	end
	if opts.Eyes ~= false and first then
		-- two glowing eyes half sunk in the stem's surface, 70 % up the first segment
		local f = opts.FaceDir or dirAt(rng:NextNumber(0, TAU))
		local a0, a1, sth = first[1], first[2], first[3]
		local axis = (a1 - a0).Unit
		local nrm = f - axis * f:Dot(axis)
		nrm = nrm.Magnitude > 1e-3 and nrm.Unit or f
		local R = sth / 2
		local c = a0:Lerp(a1, .7)
		local fc = K.Look(c, c + nrm)
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * R * .42
			local depth = math.sqrt(math.max(0, R * R - x * x))
			K.Ball(m, "FaceEye", R * .42, fc * CF(x, 0, -depth + R * .06), opts.EyeColor or CK.GLOW.Orange, M.Neon,
				{ Transparency = 1, Attrs = { CalEyes = true, CalEyeColor = opts.EyeColor or CK.GLOW.Orange, CalFar = true } })
		end
	end
	return m
end

-- SCARECROW DOG for the pumpkin patch: a crooked pole and cross arm, a stuffed sack body, a sack dog head with floppy
-- ears and stitched neon eyes, a witch hat, straw sticking out (faces -Z of cf)
function CK.Scarecrow(parent: Instance, cf: CFrame, rng)
	local m = K.Model(parent, "ScarecrowDog")
	local wood = P.WoodOld:Lerp(P.WoodDark, .3)
	local sack = C(170, 140, 96)
	local cloth = C(84, 40, 110)
	K.Part(m, "ScarecrowPole", V3(.45, 7.4, .45), cf * CF(0, 3.7, 0) * ANG(0, 0, .04), wood, M.WoodPlanks)
	K.Part(m, "ScarecrowArm", V3(6.2, .4, .4), cf * CF(0, 5.3, 0) * ANG(0, 0, -.06), wood, M.WoodPlanks)
	K.Ellipsoid(m, "ScarecrowBody", V3(2.6, 3.2, 1.6), cf * CF(0, 4.6, 0), cloth, M.Fabric)
	K.Part(m, "ScarecrowPatch", V3(.8, .8, .1), cf * CF(.5, 4.9, -.8) * ANG(0, 0, .3), C(180, 90, 40), M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		K.Ellipsoid(m, "ScarecrowSleeve", V3(2.2, .9, .9), cf * CF(sx * 1.9, 5.3, 0), cloth:Lerp(P.Ink, .2), M.Fabric)
		for k = 1, 3 do
			K.Wedge(m, "ScarecrowStraw", V3(.08, .7, .25), cf * CF(sx * 3.05, 5.25 + (k - 2) * .18, 0) * ANG(0, 0, sx * (1.3 + k * .15)),
				pick(rng, CK.STRAW), M.Grass)
		end
	end
	local head = cf * CF(0, 7.1, -.1)
	K.Ellipsoid(m, "ScarecrowHead", V3(1.9, 1.7, 1.7), head, sack, M.Fabric)
	K.Ellipsoid(m, "ScarecrowSnout", V3(1, .8, 1.1), head * CF(0, -.3, -.8), sack:Lerp(P.Ink, .1), M.Fabric)
	K.Ball(m, "ScarecrowNose", .38, head * CF(0, -.15, -1.32), P.Ink, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		K.Ellipsoid(m, "ScarecrowEar", V3(.5, 1.5, .9), head * CF(sx * 1, -.2, .1) * ANG(0, 0, sx * .35), sack:Lerp(P.WoodDark, .3), M.Fabric)
		K.Part(m, "ScarecrowEye", V3(.32, .32, .08), head * CF(sx * .42, .25, -.78) * ANG(0, 0, PI / 4), CK.GLOW.Orange, M.Neon,
			{ Attrs = { CalEyes = true, CalEyeColor = CK.GLOW.Orange }, Transparency = 1 })
		K.Part(m, "ScarecrowStitch", V3(.5, .07, .06), head * CF(sx * .42, .25, -.8) * ANG(0, 0, -PI / 4), P.Ink, M.SmoothPlastic)
	end
	K.Part(m, "ScarecrowMouth", V3(.8, .08, .06), head * CF(0, -.62, -1.02), P.Ink, M.SmoothPlastic)
	-- witch hat
	K.CylY(m, "HatBrim", .14, 2.8, head * CF(0, .78, 0) * ANG(.08, 0, -.1), C(40, 20, 60), M.Fabric)
	K.CylY(m, "HatCrown", 1.0, 1.3, head * CF(0, 1.35, 0) * ANG(.08, 0, -.1), C(48, 24, 72), M.Fabric)
	K.Wedge(m, "HatTip", V3(1, 1.3, 1), head * CF(.15, 2.4, .05) * ANG(.08, 0, -.35), C(48, 24, 72), M.Fabric)
	K.CylY(m, "HatBand", .22, 1.36, head * CF(0, 1.0, 0) * ANG(.08, 0, -.1), C(255, 140, 40), M.Neon)
	return m
end

-- GIANT JACK-O'-LANTERN on a mound (faces -Z of cf), with a glow and a big lid stem; s = diameter
function CK.GiantJack(parent: Instance, cf: CFrame, s: number)
	local m = K.Model(parent, "GiantJackOLantern")
	K.Ellipsoid(m, "JackMound", V3(s * 1.5, s * .3, s * 1.4), cf * CF(0, .02, 0), C(64, 48, 40), M.Ground)
	K.Pumpkin(m, cf * CF(0, s * .06, 0), s, { Lobes = 8, Light = true, Glow = C(255, 160, 50) })
	K.CylY(m, "JackCurl", s * .1, s * .06, cf * CF(s * .1, s * .9, 0) * ANG(0, 0, -.9), P.Stem, M.Grass)
	return m
end

-- a translucent ghost dog walking (Y.DogStatue in spectral Neon; faces -Z of cf)
function CK.GhostDog(parent: Instance, cf: CFrame, scale: number)
	local m, _ = Y.DogStatue(parent, cf, { Scale = scale, Color = C(170, 220, 255), EyeColor = C(120, 255, 200), Name = "GhostDog" })
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Material ~= M.Neon then
				d.Material = M.Neon
				d.Transparency = .55
				d.Color = d.Color:Lerp(C(170, 220, 255), .7)
			end
		end
	end
	m:SetAttribute("CalGhost", true)
	return m
end

-- crooked signpost with a hanging board (English text, NoTranslate + HwTextEN: CalendarFX localizes it)
function CK.Signpost(parent: Instance, cf: CFrame, text: string, rng)
	local m = K.Model(parent, "CalendarSign")
	local wood = P.WoodOld:Lerp(P.WoodDark, .35)
	K.Part(m, "SignPost", V3(.5, 6.4, .5), cf * CF(0, 3.2, 0) * ANG(0, 0, .05), wood, M.WoodPlanks)
	K.Part(m, "SignArm", V3(3.6, .35, .35), cf * CF(1.5, 5.8, 0) * ANG(0, 0, -.05), wood, M.WoodPlanks)
	local board = K.Part(m, "SignBoard", V3(4.6, 1.5, .25), cf * CF(1.9, 4.3, 0) * ANG(0, 0, .08), C(64, 40, 30), M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		K.Bar(m, "SignChain", (cf * CF(1.9 + sx * 1.8, 5.65, 0)).Position, (cf * CF(1.9 + sx * 1.8, 5.05, 0)).Position, .08, .08, P.Iron, M.CorrodedMetal)
	end
	local g = K.Sign(board, Enum.NormalId.Front, text, C(255, 170, 70), { PixelsPerStud = 24, Stroke = true, StrokeColor = C(30, 10, 20), MaxDistance = 180 })
	g:SetAttribute("NoTranslate", true)
	for _, t in ipairs(g:GetDescendants()) do
		if t:IsA("TextLabel") then
			t:SetAttribute("NoTranslate", true)
			t:SetAttribute("HwTextEN", text)
		end
	end
	local back = K.Sign(board, Enum.NormalId.Back, text, C(255, 170, 70), { PixelsPerStud = 24, Stroke = true, StrokeColor = C(30, 10, 20), MaxDistance = 180, Name = "LetteringBack" })
	for _, t in ipairs(back:GetDescendants()) do
		if t:IsA("TextLabel") then
			t:SetAttribute("NoTranslate", true)
			t:SetAttribute("HwTextEN", text)
		end
	end
	Y.Pumpkin(m, cf * CF(-.9, 0, -.6), 1.6, { Face = true })
	local _ = rng
	return m
end

------------------------------------------------------------------------------------------------------------------
-- placement helpers used by every stage
------------------------------------------------------------------------------------------------------------------
-- open grass areas of the island measured from the place (top view, x right / z down). Stage builders use them to put
-- the eye-catchers where players walk; the free-cell pool decides the exact spots.
CK.Regions = {
	WestLawn = { X0 = -188, X1 = -142, Z0 = 168, Z1 = 272 }, -- west of the Dog Park (the biggest open grass)
	WestLawnS = { X0 = -184, X1 = -130, Z0 = 286, Z1 = 320 },
	CourtWest = { X0 = -142, X1 = -108, Z0 = 374, Z1 = 408 }, -- south-west of the Community Court
	CourtSouth = { X0 = -112, X1 = -64, Z0 = 390, Z1 = 412 },
	ParkEast = { X0 = -56, X1 = -28, Z0 = 176, Z1 = 300 }, -- between the Dog Park and the boulevard
	HubEast = { X0 = 34, X1 = 80, Z0 = 178, Z1 = 300 }, -- east of the boulevard, north of the spawn plaza
	ShelterEast = { X0 = 150, X1 = 190, Z0 = 160, Z1 = 252 }, -- east of the Dog Shelter
	EastLawn = { X0 = 166, X1 = 190, Z0 = 300, Z1 = 400 },
	WestCliff = { X0 = -212, X1 = -182, Z0 = 548, Z1 = 718 }, -- west of DOG-O-MATIC, along the cliff
	SouthField = { X0 = -172, X1 = -28, Z0 = 706, Z1 = 744 }, -- behind DOG-O-MATIC
	DogNorthW = { X0 = -106, X1 = -70, Z0 = -202, Z1 = -168 }, -- the lawns beside THE DOG
	DogNorthE = { X0 = 70, X1 = 106, Z0 = -202, Z1 = -168 },
}

-- claim a free disc for a set piece before any stage builds (Stage modules may export Claim(ctx)): the spot is found in
-- `region` and reserved for the whole height of the piece; the claimant builds inside it later (site.Claims[name]).
-- opts: Tree {Spread, Height} (a tree's crown is checked and reserved too)
function Site:Claim(name: string, rng, region: string, r: number, height: number, opts: any)
	opts = opts or {}
	self.Claims = self.Claims or {}
	local spot = self:Scatter(rng, 1, r, { Box = CK.Regions[region], Y1 = math.min(height, 6), Tries = 1500, Tree = opts.Tree,
		Reserve = { Y0 = 0, Y1 = height } })[1]
	if spot then
		spot.R = r
		self.Claims[name] = spot
	end
	return spot
end

-- `n` dead-grass patches spreading out of the Dead Yard up to `front` (0..1 of Grass.SpreadRange). opts: Leaves (share
-- of patches with fallen leaves), Box, Radius {lo, hi}
function CK.Patches(ctx, n: number, front: number, opts: any): number
	opts = opts or {}
	local rng = ctx.Rng
	local lo, hi = (opts.Radius or { 1.8, 3.2 })[1], (opts.Radius or { 1.8, 3.2 })[2]
	-- mats only keep clear of each other (band below .12): trees, pumpkins and candles may stand on dead grass later
	local spots = ctx.Site:Scatter(rng, n, hi + .2, { Front = front, Margin = 1.4, Y0 = -1, Y1 = 2, Box = opts.Box, Reserve = { Y0 = -1, Y1 = .1 } })
	local model = ctx.Model("DeadGrass")
	for _, s in ipairs(spots) do
		local leaves = rng:NextNumber() < (opts.Leaves or .4) and rng:NextInteger(2, 4) or 0
		CK.DeadPatch(model, V3(s.X, s.Top, s.Z), s.Top, rng:NextNumber(lo, hi), rng, { Leaves = leaves })
	end
	return #spots
end

-- `n` crooked trees. opts: Box / Boxes (list of region names, one tree each in turn), Front, Height {lo, hi}, Thick,
-- Face, EyeColor, MouthGlow, Roost, Lantern, Lite, Branches, Name. Trees are recorded in ctx.Site.Trees.
function CK.Trees(ctx, n: number, opts: { [string]: any }): { Model }
	local rng = ctx.Rng
	local site = ctx.Site
	site.Trees = site.Trees or {}
	local model = ctx.Model(opts.Name or "CrookedTrees")
	local out = {}
	for i = 1, n do
		local h = rng:NextNumber(opts.Height[1], opts.Height[2])
		local thick = opts.Thick or .1
		local base = math.max(1.2, h * thick * 1.45)
		local spread = h * .32
		local box = opts.Box
		if opts.Boxes then
			box = CK.Regions[opts.Boxes[(i - 1) % #opts.Boxes + 1]]
		end
		local s = site:Scatter(rng, 1, base, { Front = opts.Front, Box = box, Tree = { Spread = spread, Height = h + 2 }, Tries = 400 })[1]
		if not s and box then
			-- the region is full: anywhere on the island's open grass instead
			s = site:Scatter(rng, 1, base, { Front = opts.Front, Tree = { Spread = spread, Height = h + 2 }, Tries = 800 })[1]
		end
		if s then
			local m, info = CK.TreeAt(model, site, s, h, rng, { Thick = thick, Face = opts.Face, EyeColor = opts.EyeColor,
				MouthGlow = opts.MouthGlow, Roost = opts.Roost, Lantern = opts.Lantern, Lanterns = opts.Lanterns, Lite = opts.Lite, Branches = opts.Branches,
				Name = opts.TreeName })
			table.insert(site.Trees, { X = s.X, Z = s.Z, Top = s.Top, R = base, Model = m, Face = opts.Face == true })
			table.insert(out, m)
			local _ = info
		else
			ctx.Note(string.format("tree %d/%d: no free spot (%s)", i, n, opts.Boxes and opts.Boxes[(i - 1) % #opts.Boxes + 1] or "any"))
		end
	end
	return out
end

-- `n` small props from a builder fn(model, spot) on free spots of radius r. opts: Box / Boxes, Front, Y1, Margin, Name
function CK.Props(ctx, n: number, r: number, opts: { [string]: any }, fn: (Instance, { [string]: number }) -> ()): number
	local model = ctx.Model(opts.Name or "Props")
	local made = 0
	for i = 1, n do
		local box = opts.Box
		if opts.Boxes then
			box = CK.Regions[opts.Boxes[(i - 1) % #opts.Boxes + 1]]
		end
		local scatter = { Front = opts.Front, Box = box, Y1 = opts.Y1 or 6, Margin = opts.Margin, Tries = 300, Reserve = { Y0 = 0, Y1 = opts.Y1 or 6 } }
		local s = ctx.Site:Scatter(ctx.Rng, 1, r, scatter)[1]
		if not s and box then
			scatter.Box, scatter.Tries = nil, 600 -- the region is full: anywhere on the island's open grass
			s = ctx.Site:Scatter(ctx.Rng, 1, r, scatter)[1]
		end
		if s then
			fn(model, s)
			made += 1
		end
	end
	if made < n then
		ctx.Note(string.format("%s: %d/%d placed", opts.Name or "Props", made, n))
	end
	return made
end

-- one silhouette tree on each sky island meadow (23_DistrictPolish.Horizon_Islands), clear of the island's own trees
-- and of trees placed earlier; eyes face the main island. `slot` 1/2 picks different spots for two stages.
function CK.SkyIslandTrees(ctx, slot: number, heights: { number })
	local rng = ctx.Rng
	local d = ctx.District
	local path = ctx.Cfg.Build.SkyIslands
	local node: Instance? = d
	for name in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	if not node then
		ctx.Note("no sky islands at " .. path)
		return 0
	end
	local model = ctx.Model("SkyIslandTrees")
	ctx.Site.SkyTaken = ctx.Site.SkyTaken or {}
	local taken = ctx.Site.SkyTaken
	local made = 0
	local islands = node:GetChildren()
	table.sort(islands, function(a, b)
		return a.Name < b.Name
	end)
	for _, isl in ipairs(islands) do
		local meadow = isl:FindFirstChild("UpperMeadow")
		if meadow and meadow:IsA("BasePart") then
			local x0, _, z0, x1, y1, z1 = aabb(meadow)
			local avoid = {}
			for _, p in ipairs(isl:GetDescendants()) do
				if p:IsA("BasePart") and (p.Name == "DistantTrunk" or p.Name == "Canopy") then
					table.insert(avoid, p.CFrame.Position)
				end
			end
			for _, t in ipairs(taken) do
				table.insert(avoid, t)
			end
			local centre = V3((x0 + x1) / 2, y1, (z0 + z1) / 2)
			local toIsland = V3(-centre.X, 0, 300 - centre.Z) -- face the main island (its middle is ~ (0, 300))
			toIsland = toIsland.Magnitude > 1 and toIsland.Unit or V3(0, 0, 1)
			local best = nil
			for _ = 1, 40 do
				-- the edge facing the island first, so the silhouette reads against the sky from the island
				local u = rng:NextNumber(.18, .82)
				local v = rng:NextNumber(.18, .82)
				local p = V3(x0 + (x1 - x0) * u, y1, z0 + (z1 - z0) * v)
				local ok = true
				for _, a in ipairs(avoid) do
					if V3(p.X - a.X, 0, p.Z - a.Z).Magnitude < 22 then
						ok = false
						break
					end
				end
				if ok then
					local score = (p - centre):Dot(toIsland) * (slot == 1 and 1 or -1)
					if not best or score > best.Score then
						best = { P = p, Score = score }
					end
				end
			end
			if best then
				local h = rng:NextNumber(heights[1], heights[2])
				CK.SkyTree(model, best.P, h, rng, { FaceDir = toIsland, EyeColor = slot == 1 and CK.GLOW.Orange or CK.GLOW.Green })
				table.insert(taken, best.P)
				made += 1
			end
		end
	end
	return made
end
-- a crooked tree on a free spot: returns the model or nil. spot = {X, Z, Top}; the face looks at the nearest path
function CK.TreeAt(parent: Instance, site, spot, h: number, rng, opts: any)
	opts = opts or {}
	local base = V3(spot.X, spot.Top, spot.Z)
	if opts.Face and not opts.FaceDir then
		local d = site:NearestWalk(spot.X, spot.Z, 60)
		opts.FaceDir = d or dirAt(rng:NextNumber(0, TAU))
	end
	return CK.CrookedTree(parent, base, h, rng, opts)
end

-- final pass on a stage folder: decor never collides / casts / touches, lights shadowless with a base brightness,
-- lettering NoTranslate. Returns parts, lights
function CK.Finish(folder: Instance): (number, number)
	local parts, lights = 0, 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			parts += 1
		elseif d:IsA("Light") then
			d.Shadows = false
			d:SetAttribute("HwBaseBrightness", d.Brightness)
			lights += 1
		elseif d:IsA("TextLabel") then
			d:SetAttribute("NoTranslate", true)
		end
	end
	return parts, lights
end

return CK
