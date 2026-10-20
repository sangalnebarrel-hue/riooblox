-- THE UNDERYARD · FUNERAL CARNIVAL (ServerStorage.UnderyardBuild.FuneralCarnival, WP-H1, docs/halloween2/DESIGN.md §7,
-- §8.4.2, §22.6). Build-time only: tools/edits/40_underyard.luau runs it through tools/sim.luau (Order 40) and the result
-- is SAVED in the place (editable in Studio). An abandoned circus of the dead in the district box x 75..222, z 2168..2330
-- (UnderyardLayout.Carnival); every coordinate comes from the layout, nothing here moves an anchor.
--
-- One Model `FuneralCarnival` (attribute UyDistrict = "FuneralCarnival") under ctx.Root:
--   Ground       irregular dirt / flagstone dressing on the floor (top y 0); the floor slab + an entrance apron only when
--                WP-G's Ground has not laid the district floor (parts with UyFloor = "FuneralCarnival") already
--   Perimeter    striped carnival palisade on the inner (west / south) edges, dark boards on the zone edges, the
--                entrance gap exactly where the 22-wide spoke bridge from L.Gates.FuneralCarnival crosses the district
--                corner, invisible 40-tall colliders (CanQuery off) with the same gap
--   Midway       ticket booth (L.Carnival.TicketBooth, marquee "THE FUNERAL CARNIVAL", CLOSED plank UyHideAtSeal = 2)
--                and the start banner over RunStart
--   BigTop       black / white / violet striped tent at L.Carnival.Tent: walk-through (SW entrance portico toward the
--                finish, NE exit), king pole + flag, sagging roof, quarter poles, guy ropes, circus ring, bleachers,
--                ghost audience (UyShowAtSeal = 2), dog cannon, fire hoop, trapeze, ringmaster ghost
--   CarouselBase static step ring around the carousel (walkable, two 0.45 steps)
--   Carousel     the broken carousel at L.Carnival.Carousel: hinge Model, ModelStreamingMode Atomic, PrimaryPart
--                `CarouselHub` (invisible, axis aligned, deck top centre), attribute UySpin = 0.35 rad/s (+Y; the client
--                spins it with Hub.CFrame * CFrame.Angles(0, UySpin * serverTime, 0)); the walkable deck carries
--                RotVelocity (0, UySpin, 0) so riders are carried with the visual spin; dog-shaped mounts (non-solid)
--   FerrisWheel  tilted wheel at L.Carnival.FerrisWheel with coffin gondolas, boarding deck, operator shack
--   CoffinCoaster track along the east edge: station, lift hill, vertical loop, camel hill, broken end, coffin carts
--   FuneralRun   the Seal II course (§8.4.2):
--     RunLane            paved lane 12 wide along F.LanePath(L) (start -> 1..10, under the pendulums, across the
--                        carousel annulus around its centre column; via points 5 studs before / after a turning
--                        checkpoint so every arch is passed straight), edge kerbs, Neon chevrons; nothing solid within
--                        5 studs of the centreline at body height (tests/underyard_carnival_row.luau checks it)
--     RunCheckpoint_i    ring arch (inner clear width 12.6 >= 9) at L.Carnival.Checkpoints[i], every part carries
--                        attribute RunCheckpoint = i; Neon hoop `RunRing` (client highlight); digit plaque (NoTranslate)
--     RunGallows_i       static double gallows straddling the lane at L.Carnival.Pendulums[i]
--     RunPendulum_i      hinge Model (Atomic, non-solid), PrimaryPart `PendulumHinge` at the pivot (y 17) whose
--                        LookVector is the lane direction; attributes UySwingAmp = 1.0 (rad), UySwingPeriod = 3.2 (s),
--                        UySwingPhase (rad), UySwingAxis = "Z": angle(t) = Amp * sin(2*pi*t / Period + Phase) applied as
--                        Hinge.CFrame * CFrame.Angles(0, 0, angle) swings the coffin ACROSS the lane
--     CoffinConveyor     belt on the leg 2 -> 3 (attribute RunConveyor = true, UyConveyorSpeed; saved Velocity along
--                        the run so it carries runners), ramps, roller beds with coffins, gantries
--   Props        crooked lamps (HwLantern glass + the district's PointLights), ghostly bunting on striped masts across
--                the lane, ghost carts with spectral vendors, balloon skulls, midway games (SKULL TOSS, LUCKY BONES),
--                the BELL STRIKER, the fortune teller's tent, an empty cage wagon, a coffin stack, hay, crates, the
--                performers' dog graves, FogPoint / GhostPath markers, CrowPerch attachments
-- Budget: <= 3 500 parts, <= 35 lights (checked by the test). Seal-state attributes (§7.3): UyLightAtSeal = 2 on the
-- carnival bulbs (carousel crown, wheel rim, marquees, coaster lift), UyShowAtSeal = 2 ghost audience, UyHideAtSeal = 2
-- the CLOSED plank on the ticket booth.
-- World text is English and translated by DOGROTS_AutoTranslateUI from Localization.UnderyardCarnivalRow (Exact);
-- digits carry NoTranslate.
local K = require(script.Parent.Parent.HalloweenBuild.Kit)
local Y = require(script.Parent.Parent.HalloweenBuild.YardKit)
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi
local S = Y.Solid
local Rng = Y.Rng

-- §7.1 palette + carnival accents
local GREEN = C(120, 255, 140)
local VIOLET = C(150, 80, 230)
local CANDLE = C(255, 170, 80)
local MOON = C(150, 200, 255)
local BONE = C(230, 222, 200)
local INK = C(16, 12, 26)
local STRIPES = { C(28, 24, 36), C(226, 220, 212), C(112, 56, 176) } -- black / white / violet
local DIRT = C(46, 40, 52)
local DIRT_D = C(36, 30, 42)
local FLAG = C(76, 72, 90)
local LANE = C(66, 60, 80)
local WOOD = C(74, 56, 54)
local WOOD_D = C(42, 32, 38)
local IRON = C(46, 46, 58)
local BRASS = C(196, 156, 84)
local GHOST = C(196, 228, 255)
local SAWDUST = C(122, 100, 78)

local SWING_AMP, SWING_PERIOD, SPIN = 1.0, 3.2, .35
local PIVOT_Y = 17 -- pendulum pivot height
local ARCH_HALF = 7 -- checkpoint pillar centre offset from the lane centre (inner clear width 2 * 7 - 1.4 = 12.6)
local LANE_W = 12 -- paved width (the clear lane is the inner 10)
local CAROUSEL_LANE_R = 8.2 -- crossing radius on the deck (column r 2.5 .. deck r 13)

local F = {}
F.Order = 40
F.Name = "FuneralCarnival"
F.Budget = { Parts = 3500, Lights = 35 }

------------------------------------------------------------------------------------------------------------------
-- geometry helpers
------------------------------------------------------------------------------------------------------------------

local function flat(y: Vector3): Vector3
	return V3(y.X, 0, y.Z)
end

local function copy(t)
	return t and table.clone(t) or nil
end

-- isosceles trapezoid (or triangle when the top edge has no width) between a bottom edge bl..br and a top edge tl..tr:
-- one box for the parallel middle + one wedge per flare. Works for any orientation ("top" may hang below "bottom").
local function trapezoid(m, name, bl: Vector3, br: Vector3, tl: Vector3, tr: Vector3, thick: number, color, mat, props)
	local bm, tm = (bl + br) / 2, (tl + tr) / 2
	local xa = (br - bl).Unit
	local up = tm - bm
	local yv = up - xa * up:Dot(xa)
	local h = yv.Magnitude
	if h < .02 then
		return
	end
	yv = yv.Unit
	local nz = xa:Cross(yv)
	local wb, wt = (br - bl).Magnitude, (tr - tl).Magnitude
	local frame = CFrame.fromMatrix(bm, xa, yv, nz)
	if wt > .05 then
		K.Part(m, name, V3(wt, h, thick), frame * CF(0, h / 2, 0), color, mat, copy(props))
	end
	local fl = (wb - wt) / 2
	if fl > .05 then
		local pr = (frame * CF((wt + wb) / 4, h / 2, 0)).Position
		local pl = (frame * CF(-(wt + wb) / 4, h / 2, 0)).Position
		K.Wedge(m, name, V3(thick, h, fl), CFrame.fromMatrix(pr, nz, yv, -xa), color, mat, copy(props))
		K.Wedge(m, name, V3(thick, h, fl), CFrame.fromMatrix(pl, -nz, yv, xa), color, mat, copy(props))
	end
end

-- point on a horizontal circle (angle from +X toward +Z)
local function ring(c: Vector3, a: number, r: number, y: number): Vector3
	return V3(c.X + math.cos(a) * r, y, c.Z + math.sin(a) * r)
end

-- flat floor piece whose top is at `top`
local function slab(m, name, cx, cz, sx, sz, rot, top, thick, color, mat, props)
	return K.Part(m, name, V3(sx, thick, sz), CF(cx, top - thick / 2, cz) * ANG(0, rot, 0), color, mat, props)
end

-- invisible wall: collides, never casts / queries (prompts and the camera ignore it)
local function collider(m, size: Vector3, cf: CFrame)
	local p = K.Part(m, "Collider", size, cf, INK, M.SmoothPlastic, { Transparency = 1, Solid = true, Shadow = false })
	p.CanQuery = false
	return p
end

local function sign(part: BasePart, face, text: string, color, opts)
	return K.Sign(part, face, text, color, opts)
end

local function digits(part: BasePart, face, text: string, color, opts)
	local g = K.Sign(part, face, text, color, opts)
	g:SetAttribute("NoTranslate", true)
	return g
end

local function setAll(m: Instance, key: string, value: any)
	m:SetAttribute(key, value)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d:SetAttribute(key, value)
		end
	end
end

-- hanging lantern (glass HwLantern = kind), optional PointLight; cf = lantern centre
local function lantern(m, cf: CFrame, color, kind: string, light: boolean?, range: number?)
	K.Part(m, "LanternCap", V3(1.2, .28, 1.2), cf * CF(0, .95, 0), IRON, M.CorrodedMetal)
	K.Wedge(m, "LanternRoof", V3(1.2, .45, .6), cf * CF(0, 1.32, -.3), IRON, M.CorrodedMetal)
	K.Wedge(m, "LanternRoof", V3(1.2, .45, .6), cf * CF(0, 1.32, .3) * ANG(0, PI, 0), IRON, M.CorrodedMetal)
	local glass = K.Part(m, "LanternGlass", V3(.85, 1.4, .85), cf, color, M.Neon, { Attrs = { HwLantern = kind } })
	K.Part(m, "LanternBase", V3(1.05, .22, 1.05), cf * CF(0, -.8, 0), IRON, M.CorrodedMetal)
	if light then
		K.Light(glass, color, range or 20, 1.1)
		glass:SetAttribute("HwBaseBrightness", 1.1)
	end
	return glass
end

-- crooked lamp post: three bent segments, a curled arm, a hanging lantern
local function crookedLamp(m, base: Vector3, h: number, rng, color, kind: string, light: boolean?)
	local lm = K.Model(m, "CrookedLamp")
	local lean = V3(rng:NextNumber(-.18, .18), 1, rng:NextNumber(-.18, .18)).Unit
	local p0 = base
	K.CylY(lm, "LampFoot", .5, 1.4, CF(base + V3(0, .25, 0)), IRON, M.CorrodedMetal, S())
	local p1 = p0 + lean * h * .45
	local lean2 = (lean + V3(rng:NextNumber(-.3, .3), 0, rng:NextNumber(-.3, .3))).Unit
	local p2 = p1 + lean2 * h * .35
	local p3 = p2 + (lean2 + V3(rng:NextNumber(-.4, .4), .2, rng:NextNumber(-.4, .4))).Unit * h * .2
	K.Rod(lm, "LampPost", p0, p1, .5, IRON, M.CorrodedMetal, S())
	K.Ball(lm, "LampKnot", .62, CF(p1), IRON, M.CorrodedMetal)
	K.Rod(lm, "LampPost", p1, p2, .42, IRON, M.CorrodedMetal)
	K.Ball(lm, "LampKnot", .52, CF(p2), IRON, M.CorrodedMetal)
	K.Rod(lm, "LampPost", p2, p3, .36, IRON, M.CorrodedMetal)
	local out = V3(p3.X - base.X, 0, p3.Z - base.Z)
	out = out.Magnitude > .2 and out.Unit or V3(1, 0, 0)
	local tip = p3 + out * 1.6 + V3(0, .3, 0)
	K.Rod(lm, "LampArm", p3, tip, .26, IRON, M.CorrodedMetal)
	K.Ball(lm, "LampCurl", .55, CF(tip + V3(0, .25, 0)), IRON, M.CorrodedMetal)
	K.Part(lm, "LampHook", V3(.12, 1, .12), CF(tip - V3(0, .45, 0)), IRON, M.CorrodedMetal)
	local glass = lantern(lm, CF(tip - V3(0, 2.2, 0)), color, kind, light)
	K.Attach(glass, "CrowPerch", CF(0, 3.1, 0))
	return lm, tip
end

-- dog-bone pennant line from a to b (rope + hanging triangular pennants)
local function bunting(m, a: Vector3, b: Vector3, sag: number, n: number, colors, ghostly: boolean?)
	local bm = K.Model(m, "Bunting")
	local segs = math.max(3, math.floor(n / 2))
	local function at(t)
		return a:Lerp(b, t) - V3(0, math.sin(t * PI) * sag, 0)
	end
	local prev = a
	for i = 1, segs do
		local q = at(i / segs)
		K.Bar(bm, "BuntingRope", prev, q, .1, .1, IRON, M.SmoothPlastic)
		prev = q
	end
	local along = flat(b - a)
	along = along.Magnitude > .01 and along.Unit or V3(1, 0, 0)
	local up = V3(0, 1, 0)
	for i = 1, n do
		local t = (i - .5) / n
		local p = at(t)
		local col = colors[(i - 1) % #colors + 1]
		-- one wedge per pennant, flipped so its right angle hangs from the rope: a flag-shaped triangle
		local cf = CFrame.fromMatrix(p - V3(0, .85, 0), up:Cross(along), up, along) * ANG(0, 0, PI)
		K.Wedge(bm, "Pennant", V3(.06, 1.7, 1.4), cf, col, M.Fabric, ghostly and { Transparency = .35 } or nil)
	end
	return bm
end

-- skull balloon on a string tied at `tie`
local function balloonSkull(m, tie: Vector3, top: Vector3, color, rng)
	local s = rng:NextNumber(1.5, 1.9)
	K.Bar(m, "BalloonString", tie, top - V3(0, s * .5, 0), .05, .05, BONE:Lerp(INK, .3), M.SmoothPlastic)
	local cf = CF(top) * ANG(rng:NextNumber(-.15, .15), rng:NextNumber(0, 2 * PI), rng:NextNumber(-.15, .15))
	K.Ball(m, "BalloonSkull", s, cf, color, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		K.Ball(m, "BalloonEye", s * .28, cf * CF(sx * s * .2, s * .04, -s * .36), INK, M.SmoothPlastic)
	end
end

-- coffin standing upright, centred on cf (lid faces cf's -Z). w = shoulder width, h = length, d = depth;
-- bothFaces puts the glowing cross on the back as well (a pendulum is seen from both ends of the lane)
local function coffinUpright(m, cf: CFrame, w: number, h: number, d: number, wood, trim, props, bothFaces: boolean?)
	local foot, head = w * .64, w * .7
	local sh = h * .72 -- shoulder height from the foot
	local y0 = -h / 2
	local function pt(x, y)
		return (cf * CF(x, y, 0)).Position
	end
	trapezoid(m, "CoffinBody", pt(-foot / 2, y0), pt(foot / 2, y0), pt(-w / 2, y0 + sh), pt(w / 2, y0 + sh), d, wood, M.Wood, props)
	trapezoid(m, "CoffinBody", pt(-w / 2, y0 + sh), pt(w / 2, y0 + sh), pt(-head / 2, y0 + h), pt(head / 2, y0 + h), d, wood, M.Wood, props)
	-- lid inlay cross on the front face (and the back), an iron band at the shoulders
	for _, s in ipairs(bothFaces and { -1, 1 } or { -1 }) do
		K.Part(m, "CoffinCross", V3(.28, h * .5, .1), cf * CF(0, h * .08, s * (d / 2 + .04)), trim, M.Neon, copy(props))
		K.Part(m, "CoffinCross", V3(w * .5, .28, .1), cf * CF(0, h * .2, s * (d / 2 + .04)), trim, M.Neon, copy(props))
	end
	K.Part(m, "CoffinBand", V3(w * .9, .22, d + .12), cf * CF(0, y0 + sh, 0), IRON, M.CorrodedMetal, copy(props))
end

-- open coffin car / gondola (long axis along cf's Z), bottom at cf
local function coffinCar(m, cf: CFrame, len: number, w: number, wood, rng)
	local hgt = 1.3
	local function pt(x, z)
		return (cf * CF(x, hgt / 2, z)).Position
	end
	-- floor + hexagonal rim (two trapezoids lying flat as the floor plan, extruded up)
	local foot, head = w * .66, w * .72
	local sh = len * .3
	K.Part(m, "CarFloor", V3(w * .9, .3, len * .92), cf * CF(0, .15, 0), wood:Lerp(INK, .3), M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		K.Bar(m, "CarRim", pt(sx * foot / 2, len / 2), pt(sx * w / 2, len / 2 - (len - sh)), .3, hgt, wood, M.Wood)
		K.Bar(m, "CarRim", pt(sx * w / 2, -len / 2 + sh), pt(sx * head / 2, -len / 2), .3, hgt, wood, M.Wood)
	end
	K.Part(m, "CarRim", V3(foot, hgt, .3), cf * CF(0, hgt / 2, len / 2), wood, M.Wood)
	K.Part(m, "CarRim", V3(head, hgt, .3), cf * CF(0, hgt / 2, -len / 2), wood, M.Wood)
	K.Part(m, "CarSeat", V3(w * .7, .35, .9), cf * CF(0, .65, len * .1), C(70, 30, 60), M.Fabric)
	Y.Skull(m, cf * CF(0, hgt + .25, -len / 2 + .1), .8, rng:NextNumber() < .5 and VIOLET or nil, BONE)
end

------------------------------------------------------------------------------------------------------------------
-- FUNERAL RUN path (shared with the tests and the run client: the paved centreline of the course)
------------------------------------------------------------------------------------------------------------------

-- unit run direction through path point i (bisector of the incoming and outgoing legs)
local function pathDir(path, i: number): Vector3
	local p = path[i].Pos
	local inc = i > 1 and flat(p - path[i - 1].Pos).Unit or nil
	local out = i < #path and flat(path[i + 1].Pos - p).Unit or nil
	if inc and out then
		local b = inc + out
		return b.Magnitude > .05 and b.Unit or out
	end
	return (inc or out) :: Vector3
end

-- {Pos = Vector3 (y 0), Kind = "Start" | "Checkpoint" | "Via" | "Carousel", Index = checkpoint index, Dir = run
-- direction through a checkpoint (its arch is perpendicular to it)}. Where the course turns at a checkpoint, two via
-- points 5 studs before / after it make the lane pass straight through the arch (the corner happens off the arch).
function F.LanePath(L)
	local c = L.Carnival
	local cp = c.Checkpoints
	local car = c.Carousel.Centre
	local function onDeck(deg: number): Vector3
		local a = math.rad(deg)
		return V3(car.X + math.cos(a) * CAROUSEL_LANE_R, 0, car.Z + math.sin(a) * CAROUSEL_LANE_R)
	end
	local base = {
		{ Pos = c.RunStart, Kind = "Start" },
		{ Pos = cp[1], Kind = "Checkpoint", Index = 1 },
		{ Pos = cp[2], Kind = "Checkpoint", Index = 2 },
		{ Pos = cp[3], Kind = "Checkpoint", Index = 3 },
		{ Pos = c.Pendulums[2], Kind = "Via" }, -- the lane bends under pendulum 2
		{ Pos = cp[4], Kind = "Checkpoint", Index = 4 },
		{ Pos = cp[5], Kind = "Checkpoint", Index = 5 },
		{ Pos = cp[6], Kind = "Checkpoint", Index = 6 },
		{ Pos = cp[7], Kind = "Checkpoint", Index = 7, Dir = flat(car - cp[7]).Unit }, -- deck gates face the carousel
		{ Pos = onDeck(-35), Kind = "Carousel" }, -- ride the deck around the centre column (north half)
		{ Pos = onDeck(-71.7), Kind = "Carousel" },
		{ Pos = onDeck(-108.3), Kind = "Carousel" },
		{ Pos = onDeck(-145), Kind = "Carousel" },
		{ Pos = cp[8], Kind = "Checkpoint", Index = 8, Dir = flat(cp[8] - car).Unit },
		{ Pos = cp[8] + V3(-6, 0, 24), Kind = "Via" }, -- south along the west palisade
		{ Pos = cp[9], Kind = "Checkpoint", Index = 9 },
		{ Pos = cp[10], Kind = "Checkpoint", Index = 10 },
	}
	local out = {}
	for i, e in ipairs(base) do
		if e.Kind == "Checkpoint" then
			local dir = e.Dir or pathDir(base, i)
			e.Dir = dir
			local inc = flat(e.Pos - base[i - 1].Pos).Unit
			local nxt = base[i + 1]
			local straight = inc:Dot(dir) > .97 and (not nxt or flat(nxt.Pos - e.Pos).Unit:Dot(dir) > .97)
			if not straight then
				table.insert(out, { Pos = e.Pos - dir * 5, Kind = e.Index == 8 and "Carousel" or "Via" })
			end
			table.insert(out, e)
			if not straight and nxt then
				-- the west deck gate turns hard south right after the arch: leave it further out
				table.insert(out, { Pos = e.Pos + dir * (e.Index == 8 and 8 or 5), Kind = e.Index == 7 and "Carousel" or "Via" })
			end
		else
			table.insert(out, e)
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- ground
------------------------------------------------------------------------------------------------------------------

-- WP-G's Ground (Order 10) lays every district's floor slab (parts with attribute UyFloor = district, top y 0, the
-- district box) and the 22-wide spoke bridge into its corner. When that floor exists, this builder adds only the surface
-- dressing (no coplanar second floor); built standalone (tests, or without the world framework) it lays its own.
local BRIDGE_HALF = 11.8 -- spoke bridge half width (11) + clearance
local function sharedFloor(zoneRoot: Instance?, name: string): boolean
	if not zoneRoot then
		return false
	end
	for _, d in ipairs(zoneRoot:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("UyFloor") == name then
			return true
		end
	end
	return false
end

-- where the two sides of the gate's spoke bridge (radial from the zone centre through the gate) cross the district edge
-- line x = value (axis "X") or z = value (axis "Z"): returns the lower and the higher crossing coordinate
local function bridgeCrossings(L, gate, axis: string, value: number): (number, number)
	local f = flat(gate.Position - L.Centre).Unit
	local side = V3(-f.Z, 0, f.X)
	local out = {}
	for _, s in ipairs({ -1, 1 }) do
		local o = gate.Position + side * s * BRIDGE_HALF
		local t = axis == "X" and (value - o.X) / f.X or (value - o.Z) / f.Z
		local p = o + f * t
		table.insert(out, axis == "X" and p.Z or p.X)
	end
	return math.min(out[1], out[2]), math.max(out[1], out[2])
end

local function buildGround(root, L, rng, shared: boolean)
	local g = K.Model(root, "Ground")
	local box = L.Districts[3]
	for _, d in ipairs(L.Districts) do
		if d.Name == "FuneralCarnival" then
			box = d
		end
	end
	local x0, x1, z0, z1 = box.Min.X, box.Max.X, box.Min.Z, box.Max.Z
	if not shared then
		local floor = slab(g, "CarnivalFloor", (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0, 0, 0, 2, DIRT, M.Ground, { Solid = true, Shadow = false })
		floor:SetAttribute("UyFloor", "FuneralCarnival")
		-- entrance apron from the gate into the district (WP-G's spoke bridge takes this role when present)
		local gate = L.Gates.FuneralCarnival
		local fwd = gate.Facing
		local apron = K.Look(gate.Position + fwd * 9, gate.Position + fwd * 20)
		K.Part(g, "EntranceApron", V3(17, .2, 18), apron * CF(0, -.06, 0), LANE, M.Cobblestone, { Solid = true, Shadow = false })
		for _, s in ipairs({ -1, 1 }) do
			K.Part(g, "ApronKerb", V3(.6, .3, 18), apron * CF(s * 8.6, .05, 0), BONE:Lerp(FLAG, .5), M.Slate)
		end
	end
	-- irregular flagstone clusters, mud, cracks and fungus (deterministic)
	local inside = function(x, z, pad)
		return x > x0 + pad and x < x1 - pad and z > z0 + pad and z < z1 - pad
	end
	-- raised decor stays off the paved run lane
	local lane = F.LanePath(L)
	local function offLane(x: number, z: number, r: number): boolean
		local q = V3(x, 0, z)
		for i = 1, #lane - 1 do
			local a, b = flat(lane[i].Pos), flat(lane[i + 1].Pos)
			local ab = b - a
			local t = math.clamp((q - a):Dot(ab) / ab:Dot(ab), 0, 1)
			if (a + ab * t - q).Magnitude < r then
				return false
			end
		end
		return true
	end
	for k = 1, 34 do
		local cx, cz = rng:NextNumber(x0 + 6, x1 - 6), rng:NextNumber(z0 + 6, z1 - 6)
		local n = rng:NextInteger(2, 4)
		for _ = 1, n do
			local x, z = cx + rng:NextNumber(-4, 4), cz + rng:NextNumber(-4, 4)
			if inside(x, z, 2) and offLane(x, z, 8.5) then
				slab(g, "Flagstone", x, z, rng:NextNumber(1.8, 3.6), rng:NextNumber(1.6, 3.2), rng:NextNumber(0, PI), rng:NextNumber(.03, .09), .12,
					FLAG:Lerp(DIRT_D, rng:NextNumber(0, .45)), M.Slate)
			end
		end
		if k % 3 == 0 then
			K.Ellipsoid(g, "MudPatch", V3(rng:NextNumber(5, 10), .1, rng:NextNumber(4, 8)), CF(cx + 5, .01, cz - 4) * ANG(0, rng:NextNumber(0, PI), 0),
				DIRT_D, M.Mud)
		end
		if k % 5 == 1 then
			local a = rng:NextNumber(0, PI)
			K.Part(g, "GroundCrack", V3(.18, .04, rng:NextNumber(4, 9)), CF(cx - 4, .02, cz + 3) * ANG(0, a, 0), INK, M.SmoothPlastic)
			K.Part(g, "GroundCrack", V3(.14, .04, rng:NextNumber(2, 4)), CF(cx - 4, .02, cz + 3) * ANG(0, a, 0) * CF(0, 0, 3) * ANG(0, .7, 0), INK,
				M.SmoothPlastic)
		end
		if k % 6 == 2 and offLane(cx + 3, cz + 5, 8) then
			K.Mushrooms(g, CF(cx + 3, 0, cz + 5), 3, rng, GREEN:Lerp(DIRT, .35))
		end
	end
	-- scattered tickets / confetti near the midway (dull colours)
	local tix = { C(170, 60, 70), C(200, 180, 120), C(120, 80, 170), C(180, 180, 190) }
	for _ = 1, 16 do
		local x, z = rng:NextNumber(80, 130), rng:NextNumber(2290, 2326)
		K.Part(g, "Ticket", V3(.7, .03, .35), CF(x, .03, z) * ANG(0, rng:NextNumber(0, PI), 0), tix[rng:NextInteger(1, #tix)], M.SmoothPlastic)
	end
	return g
end

------------------------------------------------------------------------------------------------------------------
-- perimeter (inner edges: palisade + entrance gap; zone edges: low boards)
------------------------------------------------------------------------------------------------------------------

local function palisade(m, a: Vector3, b: Vector3, rng, tall: boolean, posters)
	local len = flat(b - a).Magnitude
	local dir = flat(b - a).Unit
	local spans = math.max(1, math.floor(len / (tall and 7 or 10) + .5))
	local h = tall and 7 or 4
	for k = 0, spans do
		local p = a + dir * (len * k / spans)
		local post = K.CylY(m, "PalisadePost", h + 1.6, .7, CF(p + V3(0, (h + 1.6) / 2, 0)) * ANG(rng:NextNumber(-.04, .04), 0, rng:NextNumber(-.04, .04)),
			STRIPES[1], M.Wood, S())
		if tall then
			if k % 2 == 0 then
				K.CylY(m, "PostBand", .6, .78, CF(p + V3(0, h * .55, 0)), STRIPES[2], M.Wood)
			end
			K.Ball(m, "PostFinial", 1, CF(p + V3(0, h + 1.9, 0)), k % 2 == 0 and BONE or VIOLET, M.SmoothPlastic)
			if k % 3 == 0 then
				K.Attach(post, "CrowPerch", CF(h / 2 + 1.4, 0, 0))
			end
		end
		if k < spans then
			local q = a + dir * (len * (k + .5) / spans)
			local cf = K.Look(q + V3(0, h / 2, 0), q + V3(0, h / 2, 0) + dir)
			local col = STRIPES[k % 2 + 1]
			K.Part(m, "PalisadeBoard", V3(.4, h - .6, len / spans - .5), cf * CF(0, -.2, 0) * ANG(0, 0, rng:NextNumber(-.02, .02)),
				col:Lerp(DIRT, .25), M.WoodPlanks, S())
			if tall and k % 2 == 1 then
				-- sawtooth top: one tilted plank tip per span
				K.Wedge(m, "PalisadeTip", V3(.38, 1.2, 1.4), cf * CF(0, h / 2 + .6, -len / spans * .25), col:Lerp(DIRT, .25), M.WoodPlanks)
			end
			if posters and posters[k] then
				local pst = K.Part(m, "Poster", V3(.1, 3.2, 2.4), cf * CF(posters.Side * .26, .3, 0) * ANG(0, 0, rng:NextNumber(-.05, .05)),
					C(196, 180, 150), M.SmoothPlastic)
				sign(pst, posters.Side > 0 and N.Right or N.Left, posters[k], C(70, 30, 60),
					{ PixelsPerStud = 30, Stroke = false, W = .88, H = .8, LightInfluence = .6 })
			end
		end
	end
end

local function buildPerimeter(root, L, rng)
	local m = K.Model(root, "Perimeter")
	local B = L.Bounds
	local box
	for _, d in ipairs(L.Districts) do
		if d.Name == "FuneralCarnival" then
			box = d
		end
	end
	local x0, z1 = box.Min.X + .6, box.Max.Z - .6
	local gate = L.Gates.FuneralCarnival
	-- entrance gap = where the spoke bridge crosses the district corner (west and south edges)
	local zW = bridgeCrossings(L, gate, "X", x0) - .5
	local _, xS = bridgeCrossings(L, gate, "Z", z1)
	xS += .5
	local endW, endS = V3(x0, 0, zW), V3(xS, 0, z1)
	local west0 = V3(x0, 0, B.Z0 + 1.5)
	local west1 = V3(x0, 0, endW.Z)
	local south0 = V3(endS.X, 0, z1)
	local south1 = V3(B.X1 - 1.5, 0, z1)
	palisade(m, west0, west1, rng, true, { Side = -1, [3] = "THE GREAT DOGINI", [9] = "THE HEADLESS HOUND", [15] = "LAST SHOW TONIGHT" })
	palisade(m, south0, south1, rng, true, { Side = 1, [4] = "LAST SHOW TONIGHT", [10] = "THE GREAT DOGINI", [16] = "THE HEADLESS HOUND" })
	palisade(m, V3(x0 + 1, 0, B.Z0 + 1), V3(B.X1 - 1, 0, B.Z0 + 1), rng, false)
	palisade(m, V3(B.X1 - 1, 0, B.Z0 + 1), V3(B.X1 - 1, 0, z1 - 1), rng, false)
	-- gate posts of the entrance gap (tall striped poles with skull balloons)
	for k, p in ipairs({ endW, endS }) do
		local pos = V3(k == 1 and x0 or p.X, 0, k == 1 and p.Z or z1)
		K.CylY(m, "EntrancePole", 12, 1.1, CF(pos + V3(0, 6, 0)), STRIPES[3], M.Wood, S())
		for b = 1, 3 do
			K.CylY(m, "EntrancePoleBand", .8, 1.2, CF(pos + V3(0, b * 3.4, 0)), STRIPES[2], M.Wood)
		end
		K.Ball(m, "EntrancePoleTop", 1.5, CF(pos + V3(0, 12.6, 0)), BONE, M.SmoothPlastic)
		for b = 1, 3 do
			balloonSkull(m, pos + V3(0, 10, 0), pos + V3(rng:NextNumber(.5, 3), 15 + b * 1.4, rng:NextNumber(-3, -.5)),
				({ BONE, C(190, 160, 230), C(170, 230, 180) })[b], rng)
		end
	end
	-- invisible colliders (40 tall) on all four sides; the gap stays open
	local cx = (box.Min.X + box.Max.X) / 2
	collider(m, V3(1, 40, west1.Z - (B.Z0 - 2)), CF(x0 - .8, 20, (west1.Z + B.Z0 - 2) / 2))
	collider(m, V3(B.X1 + 2 - south0.X, 40, 1), CF((south0.X + B.X1 + 2) / 2, 20, z1 + .8))
	collider(m, V3(B.X1 - x0 + 4, 40, 1), CF(cx, 20, B.Z0 - .2))
	collider(m, V3(1, 40, z1 - B.Z0 + 4), CF(B.X1 + .2, 20, (z1 + B.Z0) / 2))
	return m
end

------------------------------------------------------------------------------------------------------------------
-- midway: ticket booth + start banner
------------------------------------------------------------------------------------------------------------------

local function buildMidway(root, L, rng)
	local m = K.Model(root, "Midway")
	local gate = L.Gates.FuneralCarnival
	local bp = L.Carnival.TicketBooth
	-- the booth faces the gate (window toward arriving players)
	local face = flat(gate.Position - bp).Unit
	local B = K.Look(bp, bp + face) -- -Z = toward the gate
	local booth = K.Model(m, "TicketBooth")
	local w, d, h = 5.2, 4.2, 7.4
	K.Part(booth, "BoothPlinth", V3(w + .8, .5, d + .8), B * CF(0, .25, 0), FLAG, M.Slate, S())
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(booth, "BoothWall", V3(.4, h, d), B * CF(sx * (w / 2 - .2), .5 + h / 2, 0), STRIPES[1], M.WoodPlanks, S())
	end
	K.Part(booth, "BoothBack", V3(w, h, .4), B * CF(0, .5 + h / 2, d / 2 - .2), STRIPES[1], M.WoodPlanks, S())
	K.Part(booth, "BoothCounter", V3(w, 3.2, .5), B * CF(0, .5 + 1.6, -d / 2 + .25), STRIPES[3], M.WoodPlanks, S())
	K.Part(booth, "BoothSill", V3(w + .3, .3, 1.1), B * CF(0, 3.85, -d / 2 + .1), WOOD_D, M.Wood)
	K.Part(booth, "BoothLintel", V3(w, 1.4, .5), B * CF(0, .5 + h - .7, -d / 2 + .25), STRIPES[3], M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(booth, "WindowBar", V3(.12, 2.4, .12), B * CF(sx * .8, 5.1, -d / 2 + .3), BRASS, M.Metal)
		K.CylY(booth, "BoothPillar", h + .6, .5, B * CF(sx * (w / 2 + .1), .5 + (h + .6) / 2, -d / 2 - .1), BRASS, M.Metal)
	end
	-- the skeletal ticket seller behind the window
	Y.Skull(booth, B * CF(0, 5.3, .4) * ANG(.1, 0, .05), 1.3, GREEN, BONE)
	K.Part(booth, "SellerTorso", V3(1.6, 1.6, .9), B * CF(0, 4.0, .6), C(40, 30, 50), M.Fabric)
	K.Part(booth, "SellerHatBrim", V3(1.9, .12, 1.9), B * CF(0, 6.05, .4), INK, M.Fabric)
	K.CylY(booth, "SellerHat", 1.2, 1.2, B * CF(0, 6.7, .4), INK, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		K.Bar(booth, "SellerFinger", (B * CF(sx * .5, 4.1, -.6)).Position, (B * CF(sx * .9, 4.05, -1.6)).Position, .14, .14, BONE, M.SmoothPlastic)
	end
	K.CylZ(booth, "TicketRoll", .8, .9, B * CF(1.6, 4.3, -1.2), C(170, 60, 70), M.SmoothPlastic)
	-- the CLOSED plank across the window until Seal II is cleared
	local plank = K.Part(booth, "ClosedPlank", V3(w + .6, .8, .2), B * CF(0, 5.1, -d / 2 - .1) * ANG(0, 0, -.18), WOOD, M.WoodPlanks,
		{ Attrs = { UyHideAtSeal = 2 } })
	sign(plank, N.Front, "CLOSED", C(200, 60, 60), { PixelsPerStud = 30, H = .8, LightInfluence = .7 })
	-- striped awning + marquee
	for k = 0, 4 do
		local x = -w / 2 + (k + .5) * w / 5
		K.Wedge(booth, "Awning", V3(w / 5, .9, 1.6), B * CF(x, .5 + h - 1.0, -d / 2 - .7) * ANG(0, PI, 0), STRIPES[k % 2 + 2], M.Fabric)
	end
	K.Part(booth, "BoothRoof", V3(w + 1, .4, d + 1), B * CF(0, .5 + h + .2, 0), WOOD_D, M.Slate)
	local marquee = K.Part(booth, "Marquee", V3(w + 2.4, 2.4, .4), B * CF(0, .5 + h + 1.7, -d / 2 + .3), INK, M.SmoothPlastic)
	sign(marquee, N.Front, "THE FUNERAL CARNIVAL", BONE, { PixelsPerStud = 24, H = .7, StrokeColor = VIOLET, Brightness = 1.4 })
	for k = 0, 9 do
		local x = -(w + 2.4) / 2 + .2 + k * (w + 2) / 9
		for _, y in ipairs({ -1.35, 1.35 }) do
			K.Ball(booth, "MarqueeBulb", .3, B * CF(x, .5 + h + 1.7 + y, -d / 2 + .05), k % 2 == 0 and CANDLE or VIOLET, M.Neon,
				{ Attrs = { UyLightAtSeal = 2 } })
		end
	end
	local tix = K.Part(booth, "TicketSign", V3(3.4, .9, .15), B * CF(0, 3.0, -d / 2 - .05), C(170, 60, 70), M.SmoothPlastic)
	sign(tix, N.Front, "TICKETS", BONE, { PixelsPerStud = 30, H = .8 })
	local adm = K.Part(booth, "AdmitSign", V3(.15, 1.2, 3.2), B * CF(w / 2 + .05, 2.2, 0), C(200, 180, 120), M.SmoothPlastic)
	sign(adm, N.Right, "ADMIT ONE · NO RETURN", C(90, 30, 40), { PixelsPerStud = 30, Stroke = false, H = .75, LightInfluence = .6 })
	lantern(booth, B * CF(-w / 2 - .9, 6.2, -d / 2 - .4), CANDLE, "Orange", true, 18)
	K.Part(booth, "LanternBracket", V3(1.2, .15, .15), B * CF(-w / 2 - .35, 7.4, -d / 2 - .4), IRON, M.CorrodedMetal)
	-- balloons tied to the booth roof
	for b = 1, 4 do
		balloonSkull(booth, (B * CF(w / 2, .5 + h + .4, d / 2)).Position,
			(B * CF(w / 2 + rng:NextNumber(-1, 2.5), h + 5 + b * 1.1, d / 2 + rng:NextNumber(-1.5, 1.5))).Position,
			({ BONE, C(190, 160, 230), C(170, 230, 180), C(240, 200, 150) })[b], rng)
	end

	-- START banner over RunStart (perpendicular to the first leg)
	local path = F.LanePath(L)
	local sp = L.Carnival.RunStart
	local dir = pathDir(path, 1)
	local Sf = K.Look(sp, sp + dir)
	local st = K.Model(m, "RunStartBanner")
	for _, sx in ipairs({ -1, 1 }) do
		K.CylY(st, "BannerPole", 13, 1, Sf * CF(sx * 7.6, 6.5, 0), STRIPES[1], M.Wood, S())
		for b = 1, 4 do
			K.CylY(st, "BannerPoleBand", .7, 1.08, Sf * CF(sx * 7.6, b * 2.8, 0), STRIPES[(b % 2) + 2], M.Wood)
		end
		Y.Skull(st, Sf * CF(sx * 7.6, 13.8, 0) * ANG(0, PI, 0), 1.6, VIOLET, BONE)
	end
	local board = K.Part(st, "StartBoard", V3(14.4, 2.6, .4), Sf * CF(0, 11.2, 0), INK, M.SmoothPlastic)
	sign(board, N.Back, "THE FUNERAL RUN", BONE, { PixelsPerStud = 24, H = .75, StrokeColor = VIOLET })
	sign(board, N.Front, "THE FUNERAL RUN", BONE, { PixelsPerStud = 24, H = .75, StrokeColor = VIOLET })
	local sub = K.Part(st, "StartSubBoard", V3(7, 1.2, .3), Sf * CF(0, 9.3, 0), C(170, 60, 70), M.SmoothPlastic)
	sign(sub, N.Back, "START LINE", BONE, { PixelsPerStud = 30, H = .8 })
	K.Part(st, "StartChain", V3(.12, 1.2, .12), Sf * CF(-2.5, 10.1, 0), IRON, M.CorrodedMetal)
	K.Part(st, "StartChain", V3(.12, 1.2, .12), Sf * CF(2.5, 10.1, 0), IRON, M.CorrodedMetal)
	bunting(st, (Sf * CF(-7.6, 12.6, 0)).Position, (Sf * CF(7.6, 12.6, 0)).Position, .6, 8, { STRIPES[2], STRIPES[3], STRIPES[1] }, false)
	K.Part(st, "StartLine", V3(14, .05, .8), Sf * CF(0, .1, 0), CANDLE, M.Neon, { Transparency = .15 })
	for k = -3, 3 do
		K.Part(st, "StartLineTile", V3(1, .06, .8), Sf * CF(k * 2, .11, .8), k % 2 == 0 and STRIPES[1] or STRIPES[2], M.SmoothPlastic)
	end
	return m
end

------------------------------------------------------------------------------------------------------------------
-- the BIG TOP
------------------------------------------------------------------------------------------------------------------

local function buildTent(root, L, rng)
	local m = K.Model(root, "BigTop")
	local c = L.Carnival.Tent.Centre
	local R = L.Carnival.Tent.Radius
	local finish = L.Carnival.Checkpoints[#L.Carnival.Checkpoints]
	local aEntry = math.atan2(finish.Z - c.Z, finish.X - c.X)
	local NP = 20
	local step = 2 * PI / NP
	local WALL_H, EAVE_R, EAVE_Y = 11, R + .8, 11.6
	local MID_R, MID_Y, PEAK_Y = 12, 20.4, 32.5
	local function isOpen(k) -- entrance panels (k = 0, NP-1) and exit panels (NP/2 - 1, NP/2)
		return k == 0 or k == NP - 1 or k == NP / 2 - 1 or k == NP / 2
	end
	local function aOf(k)
		return aEntry + step * k + step -- panel k spans aOf(k-1)..aOf(k); panels 0 and NP-1 meet at aEntry
	end
	-- walls (solid canvas), roof (sagging two-tier cone), valance flaps
	for k = 0, NP - 1 do
		local a0, a1 = aOf(k - 1), aOf(k)
		local col = STRIPES[k % 3 + 1]
		if not isOpen(k) then
			local p0, p1 = ring(c, a0, R, 0), ring(c, a1, R, 0)
			local mid = (p0 + p1) / 2
			local cf = K.Look(mid + V3(0, WALL_H / 2, 0), mid + V3(0, WALL_H / 2, 0) + (p1 - p0).Unit)
			K.Part(m, "TentWall", V3(.5, WALL_H, (p1 - p0).Magnitude + .15), cf, col:Lerp(DIRT, .15), M.Fabric, S())
		end
		trapezoid(m, "TentRoof", ring(c, a0, EAVE_R, EAVE_Y), ring(c, a1, EAVE_R, EAVE_Y), ring(c, a0, MID_R, MID_Y), ring(c, a1, MID_R, MID_Y), .35,
			col, M.Fabric)
		trapezoid(m, "TentRoof", ring(c, a0, MID_R, MID_Y), ring(c, a1, MID_R, MID_Y), V3(c.X, PEAK_Y, c.Z), V3(c.X, PEAK_Y, c.Z), .35, col, M.Fabric)
		-- valance flap (points down) at the eave
		local f0, f1 = ring(c, a0, EAVE_R + .1, EAVE_Y), ring(c, a1, EAVE_R + .1, EAVE_Y)
		local fm = ring(c, (a0 + a1) / 2, EAVE_R + .1, EAVE_Y - 1.9)
		trapezoid(m, "TentValance", f0, f1, fm, fm, .12, STRIPES[(k + 1) % 3 + 1], M.Fabric)
		-- side pole + guy rope + stake at each wall seam
		local seam = ring(c, a1, R + .55, 0)
		if not (k == NP - 1 or k == NP / 2 - 1) then
			K.CylY(m, "SidePole", EAVE_Y + .9, .45, CF(seam + V3(0, (EAVE_Y + .9) / 2, 0)), WOOD_D, M.Wood, S())
			K.Ball(m, "SidePoleTop", .7, CF(seam + V3(0, EAVE_Y + 1, 0)), k % 2 == 0 and BONE or VIOLET, M.SmoothPlastic)
			if not (k == 0 or k == NP / 2) then
				local stake = ring(c, a1, R + 6, 0)
				K.Bar(m, "GuyRope", seam + V3(0, EAVE_Y + .5, 0), stake + V3(0, .4, 0), .1, .1, C(150, 140, 120), M.Fabric)
				K.Part(m, "GuyStake", V3(.3, 1, .3), CF(stake + V3(0, .4, 0)) * ANG(0, 0, .3), WOOD_D, M.Wood)
			end
		end
	end
	-- king pole, crown, tattered flag
	K.CylY(m, "KingPole", PEAK_Y + 6, 1.4, CF(c + V3(0, (PEAK_Y + 6) / 2, 0)), WOOD_D, M.Wood, S())
	K.CylY(m, "KingPoleCollar", 1, 2.4, CF(c + V3(0, PEAK_Y + .3, 0)), BRASS, M.Metal)
	local crown = K.Ball(m, "KingPoleSkull", 2, CF(c + V3(0, PEAK_Y + 6.8, 0)), BONE, M.SmoothPlastic)
	K.Attach(crown, "CrowPerch", CF(0, 1.1, 0))
	for _, sx in ipairs({ -1, 1 }) do
		K.Ball(m, "KingPoleEye", .5, CF(c + V3(sx * .4, PEAK_Y + 6.9, -.85)), GREEN, M.Neon)
	end
	local fl = c + V3(0, PEAK_Y + 5.2, 0)
	trapezoid(m, "TentFlag", fl, fl + V3(0, -2.6, 0), fl + V3(5.5, -.6, .8), fl + V3(5.5, -1.8, .8), .1, STRIPES[3], M.Fabric)
	trapezoid(m, "TentFlagTatter", fl + V3(5.5, -.6, .8), fl + V3(5.5, -1.8, .8), fl + V3(7.4, -1.6, 1.4), fl + V3(7.4, -1.6, 1.4), .1, STRIPES[3],
		M.Fabric)
	-- quarter poles under the sag ring
	for q = 0, 3 do
		local p = ring(c, aEntry + PI / 4 + q * PI / 2, MID_R - .6, 0)
		K.CylY(m, "QuarterPole", MID_Y - .3, .8, CF(p + V3(0, (MID_Y - .3) / 2, 0)), WOOD_D, M.Wood, S())
	end
	-- interior: sawdust floor, ring curb, ringmaster ghost, fire hoop, dog cannon, stools, bleachers, trapeze
	K.CylY(m, "SawdustFloor", .1, R * 2 - 1, CF(c + V3(0, .02, 0)), SAWDUST, M.Sand)
	K.CylY(m, "RingFloor", .1, 17, CF(c + V3(0, .05, 0)), C(70, 40, 74), M.Fabric)
	Y.RuneRing(m, CF(c + V3(0, .12, 0)), 6.5, 12, .25, VIOLET, { Fill = .7, H = .04, Transparency = .3, Name = "RingRune" })
	for k = 0, 15 do
		local a0, a1 = k / 16 * 2 * PI, (k + 1) / 16 * 2 * PI
		K.Bar(m, "RingCurb", ring(c, a0, 9, .5), ring(c, a1, 9, .5), .9, 1, STRIPES[k % 2 == 0 and 3 or 2], M.WoodPlanks, S())
	end
	K.CylY(m, "RingmasterDrum", 1.4, 4.2, CF(c + V3(0, .7, 0)), STRIPES[3], M.Fabric, S())
	K.CylY(m, "RingmasterDrumTop", .2, 4.4, CF(c + V3(0, 1.45, 0)), BRASS, M.Metal)
	local ghost = K.Model(m, "RingmasterGhost")
	K.Ellipsoid(ghost, "GhostBody", V3(2.2, 4.2, 1.8), CF(c + V3(0, 3.8, 0)), GHOST, M.Neon, { Transparency = .55 })
	K.Ellipsoid(ghost, "GhostHead", V3(1.7, 1.7, 1.6), CF(c + V3(0, 6.4, 0)), GHOST, M.Neon, { Transparency = .45 })
	K.Part(ghost, "GhostHatBrim", V3(2.2, .14, 2.2), CF(c + V3(0, 7.25, 0)), INK, M.Fabric)
	K.CylY(ghost, "GhostHat", 1.5, 1.4, CF(c + V3(0, 8, 0)), INK, M.Fabric)
	K.CylY(ghost, "GhostHatBand", .3, 1.45, CF(c + V3(0, 7.45, 0)), VIOLET, M.Neon)
	local toFinish = flat(finish - c).Unit
	for _, sx in ipairs({ -1, 1 }) do
		local side = V3(-toFinish.Z, 0, toFinish.X) * sx * .35
		K.Ball(ghost, "GhostEye", .3, CF(c + V3(0, 6.5, 0) + toFinish * .75 + side), INK, M.SmoothPlastic)
	end
	K.Rod(ghost, "GhostCane", c + V3(1.2, 1.5, .2), c + V3(1.6, 5, .5), .2, INK, M.SmoothPlastic)
	K.Ball(ghost, "GhostCaneTop", .45, CF(c + V3(1.6, 5.1, .5)), BRASS, M.Metal)
	local spotRig = K.Part(m, "RingSpot", V3(.8, .8, .8), CF(c + V3(0, 19, 0)) * ANG(-PI / 2, 0, 0), IRON, M.CorrodedMetal)
	local spot = Instance.new("SpotLight")
	spot.Color = VIOLET
	spot.Range = 26
	spot.Brightness = 1.6
	spot.Angle = 70
	spot.Shadows = false
	spot.Face = N.Front
	spot.Parent = spotRig
	K.Stats.Lights += 1
	local glow = K.Part(m, "TentGlow", V3(.3, .3, .3), CF(c + V3(0, 9, 0)), CANDLE, M.Neon, { Transparency = 1 })
	K.Light(glow, CANDLE, 24, .7)
	-- fire hoop on a stand (green spectral flames)
	local hoopC = ring(c, aEntry + PI * .62, 5.5, 3.6)
	local hoopF = K.Look(hoopC, hoopC + V3(-math.sin(aEntry + PI * .62), 0, math.cos(aEntry + PI * .62)))
	for k = 0, 11 do
		local a0, a1 = k / 12 * 2 * PI, (k + 1) / 12 * 2 * PI
		K.Bar(m, "FireHoop", (hoopF * CF(math.cos(a0) * 2.2, math.sin(a0) * 2.2, 0)).Position, (hoopF * CF(math.cos(a1) * 2.2, math.sin(a1) * 2.2, 0)).Position,
			.35, .35, GREEN, M.Neon)
	end
	K.Part(m, "HoopStand", V3(.3, 1.6, .3), hoopF * CF(0, -2.9, 0), IRON, M.CorrodedMetal)
	K.Part(m, "HoopFoot", V3(1.6, .2, 1.6), hoopF * CF(0, -3.6, 0), IRON, M.CorrodedMetal)
	-- the dog cannon, aimed at the roof
	local cannonC = ring(c, aEntry - PI * .62, 5.6, 0)
	local toC = flat(c - cannonC).Unit
	local cf0 = K.Look(cannonC, cannonC + toC)
	for _, sx in ipairs({ -1, 1 }) do
		K.CylX(m, "CannonWheel", .4, 2.6, cf0 * CF(sx * 1.3, 1.3, .3), WOOD_D, M.Wood)
	end
	K.Part(m, "CannonCarriage", V3(2.2, .9, 3), cf0 * CF(0, 1.3, .3), STRIPES[3], M.Wood)
	local barrel = cf0 * CF(0, 2.6, -.6) * ANG(.75, 0, 0)
	K.CylZ(m, "CannonBarrel", 5, 1.7, barrel, STRIPES[1], M.Metal)
	for b = 0, 2 do
		K.CylZ(m, "CannonBand", .4, 1.85, barrel * CF(0, 0, -1.6 + b * 1.6), b == 1 and STRIPES[2] or BRASS, M.Metal)
	end
	K.CylZ(m, "CannonMuzzle", .5, 2.1, barrel * CF(0, 0, -2.6), BRASS, M.Metal)
	-- performer stools
	for s = 0, 2 do
		local p = ring(c, aEntry + PI + (s - 1) * .5, 6.2, 0)
		K.CylY(m, "PerformerStool", 1.6, 1.5, CF(p + V3(0, .8, 0)), STRIPES[(s % 2) + 2], M.Fabric)
		K.CylY(m, "StoolTop", .2, 1.6, CF(p + V3(0, 1.65, 0)), BRASS, M.Metal)
	end
	K.Ball(m, "CircusBall", 1.6, CF(ring(c, aEntry + PI, 6.2, 2.55)), STRIPES[3], M.SmoothPlastic)
	-- bleachers on the two flanks (keep the entrance / exit axis clear), skull audience + ghost dogs after Seal II
	local audience = K.Model(m, "GhostAudience")
	audience:SetAttribute("UyShowAtSeal", 2)
	for _, base in ipairs({ aEntry + PI / 2, aEntry - PI / 2 }) do
		for tier = 0, 2 do
			local r = 13.5 + tier * 2.2
			local yTop = .7 + tier * .8
			for k = 0, 5 do
				local a0 = base - .62 + k * .207
				local a1 = a0 + .207
				K.Bar(m, "Bleacher", ring(c, a0, r, yTop - .35), ring(c, a1, r, yTop - .35), 2.1, .7, WOOD:Lerp(INK, tier * .12), M.WoodPlanks, S())
				if (k + tier) % 3 == 0 then
					local seat = ring(c, a0 + .1, r, yTop + .55)
					local look = K.Look(seat, V3(c.X, seat.Y, c.Z))
					if tier == 1 and k == 3 then
						Y.Skull(m, look * CF(0, .1, 0), .9, nil, BONE)
					else
						local gd = look * CF(0, .3, 0)
						K.Ellipsoid(audience, "GhostDog", V3(1.2, 1.4, 1.4), gd, GHOST, M.Neon, { Transparency = .6 })
						K.Ellipsoid(audience, "GhostDogHead", V3(.9, .8, 1), gd * CF(0, .95, -.35), GHOST, M.Neon, { Transparency = .55 })
						for _, sx in ipairs({ -1, 1 }) do
							K.Wedge(audience, "GhostDogEar", V3(.15, .45, .3), gd * CF(sx * .35, 1.45, -.25), GHOST, M.Neon, { Transparency = .55 })
						end
					end
				end
			end
		end
	end
	-- trapeze
	local tA, tB = ring(c, aEntry + PI / 2, 3, MID_Y - 1), ring(c, aEntry - PI / 2, 3, MID_Y - 1)
	local barA, barB = ring(c, aEntry + PI / 2, 2.2, 13.5), ring(c, aEntry - PI / 2, 2.2, 13.5)
	K.Bar(m, "TrapezeRope", tA, barA, .1, .1, C(160, 150, 130), M.Fabric)
	K.Bar(m, "TrapezeRope", tB, barB, .1, .1, C(160, 150, 130), M.Fabric)
	K.Rod(m, "TrapezeBar", barA, barB, .25, BRASS, M.Metal)
	-- entrance portico toward the finish: two posts, striped gable roof, marquee "THE LAST SHOW"
	local eMid = ring(c, aEntry, R, 0)
	local outward = flat(eMid - c).Unit
	local Pf = K.Look(eMid + outward * 2.4, eMid + outward * 10) -- -Z = out of the tent
	for _, sx in ipairs({ -1, 1 }) do
		K.CylY(m, "PorticoPost", 10.5, .9, Pf * CF(sx * 6.4, 5.25, -2.2), STRIPES[1], M.Wood, S())
		K.CylY(m, "PorticoBand", .6, 1, Pf * CF(sx * 6.4, 3.5, -2.2), STRIPES[2], M.Wood)
		K.CylY(m, "PorticoBand", .6, 1, Pf * CF(sx * 6.4, 7, -2.2), STRIPES[2], M.Wood)
		trapezoid(m, "PorticoRoof", (Pf * CF(sx * 7.4, 10.4, -3.4)).Position, (Pf * CF(sx * 7.4, 10.4, 2.2)).Position,
			(Pf * CF(0, 13.2, -3.4)).Position, (Pf * CF(0, 13.2, 2.2)).Position, .3, STRIPES[sx > 0 and 3 or 2], M.Fabric)
	end
	local marquee = K.Part(m, "LastShowSign", V3(10, 2, .3), Pf * CF(0, 11.6, -3.6), INK, M.SmoothPlastic)
	sign(marquee, N.Front, "THE LAST SHOW", BONE, { PixelsPerStud = 24, H = .72, StrokeColor = VIOLET, Brightness = 1.3 })
	for k = 0, 8 do
		K.Ball(m, "MarqueeBulb", .32, Pf * CF(-4.6 + k * 1.15, 10.45, -3.75), k % 2 == 0 and CANDLE or GREEN, M.Neon, { Attrs = { UyLightAtSeal = 2 } })
	end
	lantern(m, Pf * CF(0, 8.6, -2.6), CANDLE, "Orange", true, 20)
	-- exit flaps (NE), tied back
	local xMid = ring(c, aEntry + PI, R, 0)
	local Xf = K.Look(xMid, xMid + flat(xMid - c).Unit)
	for _, sx in ipairs({ -1, 1 }) do
		trapezoid(m, "ExitFlap", (Xf * CF(sx * 6.6, 0, -.2)).Position, (Xf * CF(sx * 5.4, 0, -.9)).Position, (Xf * CF(sx * 6.6, WALL_H, -.2)).Position,
			(Xf * CF(sx * 4.6, WALL_H, -.4)).Position, .2, STRIPES[sx > 0 and 2 or 1], M.Fabric)
	end
	return m
end

------------------------------------------------------------------------------------------------------------------
-- the broken CAROUSEL (static step ring + spinning hinge model)
------------------------------------------------------------------------------------------------------------------

local function carouselDog(m, cf: CFrame, color, saddle, skeletal: boolean?)
	-- cf at the body centre, facing -Z (the ride direction); prancing pose
	K.Part(m, "MountBody", V3(1.3, 1.4, 3.1), cf, color, M.SmoothPlastic)
	K.Part(m, "MountChest", V3(1.35, 1.6, 1.2), cf * CF(0, .35, -1.3) * ANG(.35, 0, 0), color, M.SmoothPlastic)
	local head = cf * CF(0, 1.55, -2.0) * ANG(.25, 0, 0)
	K.Part(m, "MountHead", V3(1.15, 1.15, 1.3), head, color, M.SmoothPlastic)
	K.Part(m, "MountSnout", V3(.75, .62, 1.0), head * CF(0, -.2, -1.0), color, M.SmoothPlastic)
	K.Ball(m, "MountNose", .35, head * CF(0, -.05, -1.52), INK, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		K.Wedge(m, "MountEar", V3(.2, .9, .55), head * CF(sx * .45, .85, .15) * ANG(0, 0, sx * .2), color:Lerp(INK, .3), M.SmoothPlastic)
		K.Ball(m, "MountEye", .22, head * CF(sx * .33, .22, -.66), skeletal and GREEN or INK, skeletal and M.Neon or M.SmoothPlastic)
	end
	-- legs: front pair reaching forward, hind pair back
	for _, sx in ipairs({ -1, 1 }) do
		K.Bar(m, "MountLeg", (cf * CF(sx * .45, -.3, -1.2)).Position, (cf * CF(sx * .45, -1.2, -2.5)).Position, .38, .38, color, M.SmoothPlastic)
		K.Bar(m, "MountLeg", (cf * CF(sx * .45, -.4, 1.2)).Position, (cf * CF(sx * .45, -1.5, 2.3)).Position, .4, .4, color, M.SmoothPlastic)
	end
	K.Rod(m, "MountTail", (cf * CF(0, .4, 1.5)).Position, (cf * CF(0, 1.4, 2.4)).Position, .3, color, M.SmoothPlastic)
	K.Part(m, "MountSaddle", V3(1.45, .3, 1.4), cf * CF(0, .78, .1), saddle, M.Fabric)
	K.Part(m, "MountBridle", V3(1.2, .2, .2), head * CF(0, -.2, -.6), BRASS, M.Metal)
	if skeletal then
		for r = -1, 1 do
			K.Part(m, "MountRib", V3(1.36, .16, .18), cf * CF(0, .1, r * .7), INK, M.SmoothPlastic)
		end
	end
end

local function buildCarousel(root, L, rng)
	local c = L.Carnival.Carousel.Centre
	local R = L.Carnival.Carousel.Radius
	local DECK_Y = .9
	-- static step ring (0.45 then the deck at 0.9) so runners step on without jumping
	local base = K.Model(root, "CarouselBase")
	for k = 0, 23 do
		local a0, a1 = k / 24 * 2 * PI, (k + 1) / 24 * 2 * PI
		local mid = ring(c, (a0 + a1) / 2, R + .55, 0)
		local len = 2 * (R + 1.1) * math.sin(PI / 24) + .1
		K.Part(base, "CarouselStep", V3(1.1, .45, len), K.Look(mid + V3(0, .225, 0), mid + V3(0, .225, 0) + (ring(c, a1, 1, 0) - ring(c, a0, 1, 0)).Unit),
			k % 2 == 0 and FLAG or FLAG:Lerp(INK, .2), M.Slate, { Solid = true, Shadow = false })
	end
	K.CylY(base, "CarouselPit", .3, R * 2 - .4, CF(c + V3(0, .3, 0)), INK, M.Slate, S())

	-- the spinning part
	local cm = K.Model(root, "Carousel")
	cm.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	cm:SetAttribute("UySpin", SPIN)
	cm:SetAttribute("UySpinAxis", "Y")
	local hub = K.Part(cm, "CarouselHub", V3(1, 1, 1), CF(c + V3(0, DECK_Y, 0)), IRON, M.SmoothPlastic, { Transparency = 1 })
	cm.PrimaryPart = hub
	local deck = K.CylY(cm, "CarouselDeck", .6, R * 2, CF(c + V3(0, DECK_Y - .3, 0)), C(60, 40, 70), M.WoodPlanks, S())
	;(deck :: any).RotVelocity = V3(0, SPIN, 0)
	deck:SetAttribute("RunCarouselDeck", true)
	-- deck inlay: sun-ray boards, rim trim, bulbs on the deck edge
	for k = 0, 11 do
		local a = k / 12 * 2 * PI
		K.Bar(cm, "DeckRay", ring(c, a, 3, DECK_Y + .02), ring(c, a, R - .6, DECK_Y + .02), .5, .05, k % 2 == 0 and BRASS or STRIPES[2], M.SmoothPlastic)
	end
	for k = 0, 23 do
		local a0, a1 = k / 24 * 2 * PI, (k + 1) / 24 * 2 * PI
		K.Bar(cm, "DeckRim", ring(c, a0, R - .1, DECK_Y - .45), ring(c, a1, R - .1, DECK_Y - .45), .3, .9, k % 2 == 0 and STRIPES[3] or STRIPES[2], M.Wood)
	end
	-- centre column (solid) with mirror panels and an organ face
	K.CylY(cm, "CentreColumn", 11.6, 5, CF(c + V3(0, DECK_Y + 5.8, 0)), STRIPES[1], M.Wood, S())
	for k = 0, 7 do
		local a = k / 8 * 2 * PI + PI / 8
		local p = ring(c, a, 2.55, DECK_Y + 4.5)
		local mirror = K.Part(cm, "ColumnMirror", V3(1.5, 3.4, .12), K.Look(p, p + flat(p - c).Unit), k % 2 == 0 and C(120, 140, 170) or C(80, 60, 110), M.Glass,
			{ Reflectance = .25 })
		K.Part(cm, "MirrorFrame", V3(1.8, .25, .2), mirror.CFrame * CF(0, 1.8, 0), BRASS, M.Metal)
		K.Part(cm, "MirrorFrame", V3(1.8, .25, .2), mirror.CFrame * CF(0, -1.8, 0), BRASS, M.Metal)
	end
	K.CylY(cm, "ColumnCollar", .6, 6, CF(c + V3(0, DECK_Y + 7.6, 0)), BRASS, M.Metal)
	-- poles + dog mounts (two mounts are gone: a bare bent pole and a snapped stub)
	local NPOLE = 10
	local POLE_R = 10.4
	local mounts = { BONE, STRIPES[1], C(186, 170, 220), BONE, STRIPES[1], BONE, C(170, 200, 190), STRIPES[1], BONE, C(186, 170, 220) }
	local saddles = { STRIPES[3], C(150, 40, 60), STRIPES[3], GREEN:Lerp(INK, .5), STRIPES[3], C(150, 40, 60), STRIPES[3], C(150, 40, 60), STRIPES[3], GREEN:Lerp(INK, .5) }
	for k = 0, NPOLE - 1 do
		local a = k / NPOLE * 2 * PI
		local p = ring(c, a, POLE_R, 0)
		local tangent = V3(math.sin(a), 0, -math.cos(a)) -- +Y spin direction
		if k == 3 then
			-- bent pole, no mount
			local kink = p + V3(0, 6, 0) + tangent * .9
			K.Rod(cm, "CarouselPole", p + V3(0, DECK_Y, 0), kink, .35, BRASS, M.Metal)
			K.Rod(cm, "CarouselPole", kink, p + V3(0, 12.4, 0), .35, BRASS, M.Metal)
		elseif k == 7 then
			-- snapped stub; the top half hangs from the canopy
			K.Rod(cm, "CarouselPole", p + V3(0, DECK_Y, 0), p + V3(0, 3.6, 0), .35, BRASS, M.Metal)
			K.Rod(cm, "CarouselPole", p + V3(0, 12.4, 0), p + V3(0, 8.2, 0) + tangent * .6, .35, BRASS, M.Metal)
		else
			K.CylY(cm, "CarouselPole", 12.4 - DECK_Y, .35, CF(p + V3(0, (12.4 + DECK_Y) / 2, 0)), BRASS, M.Metal)
			local h = DECK_Y + 3.2 + (k % 2) * 1.1
			carouselDog(cm, K.Look(p + V3(0, h, 0), p + V3(0, h, 0) + tangent), mounts[k + 1], saddles[k + 1], k == 5)
		end
	end
	-- canopy: striped 16-panel cone (two panels torn away), crown band with bulbs, scalloped valance
	local NC = 16
	local EAVE_Y, PEAK_Y, CR = 12.4, 18.2, R - 1
	for k = 0, NC - 1 do
		local a0, a1 = k / NC * 2 * PI, (k + 1) / NC * 2 * PI
		local col = k % 2 == 0 and STRIPES[3] or STRIPES[2]
		if k ~= 5 and k ~= 6 then
			trapezoid(cm, "CanopyPanel", ring(c, a0, CR, EAVE_Y), ring(c, a1, CR, EAVE_Y), V3(c.X, PEAK_Y, c.Z), V3(c.X, PEAK_Y, c.Z), .25, col, M.Fabric)
		else
			-- exposed rib of the torn sector + a dangling scrap
			K.Rod(cm, "CanopyRib", ring(c, a0, CR, EAVE_Y), V3(c.X, PEAK_Y - .3, c.Z), .25, WOOD_D, M.Wood)
			if k == 5 then
				local tp = ring(c, (a0 + a1) / 2, CR * .6, EAVE_Y + 2.3)
				trapezoid(cm, "CanopyScrap", tp + V3(-.9, 0, .4), tp + V3(.9, 0, -.4), tp + V3(.2, -3.2, .4), tp + V3(.2, -3.2, .4), .1, col, M.Fabric)
			end
		end
		local f0, f1 = ring(c, a0, CR + .05, EAVE_Y - .7), ring(c, a1, CR + .05, EAVE_Y - .7)
		local fm = ring(c, (a0 + a1) / 2, CR + .05, EAVE_Y - 2.0)
		trapezoid(cm, "CanopyValance", f0, f1, fm, fm, .12, k % 2 == 0 and STRIPES[2] or STRIPES[1], M.Fabric)
		K.Bar(cm, "CanopyBand", ring(c, a0, CR + .05, EAVE_Y - .35), ring(c, a1, CR + .05, EAVE_Y - .35), .3, .75, BRASS, M.Metal)
		K.Ball(cm, "CrownBulb", .36, CF(ring(c, a0, CR + .25, EAVE_Y - .35)), k % 2 == 0 and CANDLE or VIOLET, M.Neon, { Attrs = { UyLightAtSeal = 2 } })
	end
	-- top ornament: a bell with a dog-skull finial and the name boards
	K.CylY(cm, "CanopyCap", .8, 2.2, CF(c + V3(0, PEAK_Y + .1, 0)), BRASS, M.Metal)
	K.Ball(cm, "CanopyBell", 1.8, CF(c + V3(0, PEAK_Y + 1.2, 0)), BRASS, M.Metal)
	Y.Skull(cm, CF(c + V3(0, PEAK_Y + 2.7, 0)), 1.2, VIOLET, BONE)
	-- name crests standing on the eave (pediment boards), facing out on opposite sides
	for _, a in ipairs({ PI / 16, PI + PI / 16 }) do
		local p = ring(c, a, CR + .35, EAVE_Y + .95)
		local Bf = K.Look(p, p + flat(p - c).Unit)
		local board = K.Part(cm, "CarouselName", V3(7.4, 1.6, .2), Bf, INK, M.SmoothPlastic)
		sign(board, N.Front, "GHOST-GO-ROUND", BONE, { PixelsPerStud = 24, H = .8, StrokeColor = VIOLET })
		trapezoid(cm, "CarouselCrest", (Bf * CF(-2.4, .8, .02)).Position, (Bf * CF(2.4, .8, .02)).Position, (Bf * CF(0, 2.3, .02)).Position,
			(Bf * CF(0, 2.3, .02)).Position, .2, BRASS, M.Metal)
	end
	local cl = K.Part(cm, "CarouselGlow", V3(.3, .3, .3), CF(c + V3(0, 11, 0)), CANDLE, M.Neon, { Transparency = 1 })
	K.Light(cl, CANDLE, 20, .8)
	-- the fallen mount lies on the ground outside the ring (static, not part of the spin)
	local fallen = K.Model(root, "FallenMount")
	local fp = c + V3(-6, 0, R + 6)
	carouselDog(fallen, CF(fp + V3(0, .7, 0)) * ANG(0, .8, PI / 2 - .1), BONE, STRIPES[3], false)
	K.Rod(fallen, "FallenPole", fp + V3(-1, .2, -2.6), fp + V3(2.4, .2, 3.2), .35, BRASS, M.Metal)
	return cm, base
end

------------------------------------------------------------------------------------------------------------------
-- the tilted FERRIS WHEEL
------------------------------------------------------------------------------------------------------------------

local function buildFerris(root, L, rng)
	local m = K.Model(root, "FerrisWheel")
	local pos = L.Carnival.FerrisWheel
	local HUB, R = 21, 16
	local W = CF(pos.X, HUB, pos.Z) * ANG(.11, 0, .07) -- leaning south + rolled: the wheel plane is W's XY
	local function wp(a, r, z)
		return (W * CF(math.cos(a) * r, math.sin(a) * r, z)).Position
	end
	-- boarding deck + ramp + operator shack
	K.Part(m, "WheelDeck", V3(24, 1, 10), CF(pos.X, .5, pos.Z + 1), WOOD, M.WoodPlanks, S())
	K.Wedge(m, "WheelDeckRamp", V3(8, 1, 3), CF(pos.X - 4, .5, pos.Z - 5.5) * ANG(0, PI, 0), WOOD, M.WoodPlanks, S())
	local shack = CF(pos.X + 9.5, 1, pos.Z + 3)
	K.Part(m, "OperatorShack", V3(4, 5, 3.6), shack * CF(0, 2.5, 0), STRIPES[1], M.WoodPlanks, S())
	K.Wedge(m, "OperatorRoof", V3(4.6, 1.4, 2.1), shack * CF(0, 5.7, -.9), STRIPES[3], M.Slate)
	K.Wedge(m, "OperatorRoof", V3(4.6, 1.4, 2.1), shack * CF(0, 5.7, .9) * ANG(0, PI, 0), STRIPES[3], M.Slate)
	K.Part(m, "OperatorWindow", V3(2.2, 1.4, .1), shack * CF(0, 3.2, -1.82), CANDLE:Lerp(INK, .35), M.Neon, { Attrs = { HwLantern = "Orange" } })
	K.Part(m, "OperatorLever", V3(.2, 1.8, .2), shack * CF(-1.4, 1.6, -2.3) * ANG(.5, 0, 0), IRON, M.CorrodedMetal)
	K.Ball(m, "OperatorLeverKnob", .45, shack * CF(-1.4, 2.4, -2.8), C(170, 40, 50), M.SmoothPlastic)
	local wsign = K.Part(m, "WheelSign", V3(8, 1.6, .3), CF(pos.X - 4, 6.6, pos.Z - 6.4), INK, M.SmoothPlastic)
	sign(wsign, N.Front, "WHEEL OF FATE", BONE, { PixelsPerStud = 24, H = .75, StrokeColor = VIOLET })
	for _, sx in ipairs({ -1, 1 }) do
		K.CylY(m, "WheelSignPost", 7.2, .4, CF(pos.X - 4 + sx * 3.8, 3.6, pos.Z - 6.4), IRON, M.CorrodedMetal, S())
	end
	-- A-frame legs on both faces + braces
	for _, z in ipairs({ -3.3, 3.3 }) do
		local top = (W * CF(0, 0, z)).Position
		local f0 = V3(pos.X - 10, 1, pos.Z + z * 1.5)
		local f1 = V3(pos.X + 10, 1, pos.Z + z * 1.5)
		K.Rod(m, "WheelLeg", f0, top, 1.1, IRON, M.CorrodedMetal, S())
		K.Rod(m, "WheelLeg", f1, top, 1.1, IRON, M.CorrodedMetal, S())
		K.Rod(m, "WheelBrace", f0:Lerp(top, .45), f1:Lerp(top, .45), .5, IRON, M.CorrodedMetal)
		K.Part(m, "WheelFoot", V3(2, .6, 2), CF(f0 + V3(0, .3, 0)), FLAG, M.Slate)
		K.Part(m, "WheelFoot", V3(2, .6, 2), CF(f1 + V3(0, .3, 0)), FLAG, M.Slate)
	end
	-- the crack: a snapped brace hangs loose
	K.Rod(m, "WheelBraceBroken", V3(pos.X + 6, 9, pos.Z + 4.9), V3(pos.X + 9, 3.5, pos.Z + 6), .5, IRON:Lerp(C(110, 60, 40), .4), M.CorrodedMetal)
	K.CylZ(m, "WheelAxle", 8, 1.1, W, IRON, M.CorrodedMetal)
	K.CylZ(m, "WheelHub", 2.2, 3.4, W, STRIPES[3], M.Metal)
	K.CylZ(m, "WheelHubCap", .4, 2.2, W * CF(0, 0, -1.3), BRASS, M.Metal)
	-- rims (outer + inner), spokes, cross ties, rim bulbs
	local NS = 24
	for _, z in ipairs({ -1.6, 1.6 }) do
		for k = 0, NS - 1 do
			local a0, a1 = k / NS * 2 * PI, (k + 1) / NS * 2 * PI
			K.Bar(m, "WheelRim", wp(a0, R, z), wp(a1, R, z), .45, .45, k % 2 == 0 and STRIPES[2] or BONE:Lerp(INK, .2), M.Metal)
			if k % 2 == 0 then
				K.Bar(m, "WheelInnerRim", wp(a0, R * .62, z), wp(a0 + 2 * PI / 12, R * .62, z), .3, .3, IRON, M.CorrodedMetal)
			end
		end
		for k = 0, 11 do
			local a = k / 12 * 2 * PI
			K.Bar(m, "WheelSpoke", wp(a, 1.4, z), wp(a, R, z), .28, .28, IRON, M.CorrodedMetal)
		end
	end
	for k = 0, NS - 1 do
		local a = k / NS * 2 * PI
		K.Ball(m, "WheelBulb", .5, CF(wp(a, R + .1, -1.95)), k % 3 == 0 and GREEN or (k % 3 == 1 and VIOLET or CANDLE), M.Neon,
			{ Attrs = { UyLightAtSeal = 2 } })
	end
	-- coffin gondolas hang straight down from the cross ties (8 of 12; one fell onto the deck)
	for k = 0, 11 do
		local a = k / 12 * 2 * PI + PI / 24
		K.Bar(m, "WheelTie", wp(a, R, -1.8), wp(a, R, 1.8), .32, .32, IRON, M.CorrodedMetal)
		if k % 3 ~= 1 and k ~= 8 then
			local pin = wp(a, R, 0)
			local g = K.Model(m, "CoffinGondola")
			K.Part(g, "GondolaHanger", V3(.2, 2, .2), CF(pin - V3(0, 1, 0)), IRON, M.CorrodedMetal)
			K.Part(g, "GondolaYoke", V3(.2, .2, 2.4), CF(pin - V3(0, 2, 0)), IRON, M.CorrodedMetal)
			local base = CF(pin - V3(0, 3.6, 0)) * ANG(0, PI / 2 + rng:NextNumber(-.06, .06), rng:NextNumber(-.05, .05))
			coffinCar(g, base, 3.6, 2.2, k % 2 == 0 and WOOD or STRIPES[1], rng)
		end
	end
	-- the fallen gondola, smashed on the deck
	local fg = K.Model(m, "FallenGondola")
	coffinCar(fg, CF(pos.X - 7, 1, pos.Z + 3.5) * ANG(.25, 1.1, .5), 3.6, 2.2, WOOD, rng)
	local hl = K.Part(m, "WheelHubGlow", V3(.3, .3, .3), (W * CF(0, 0, -2.2)), VIOLET, M.Neon, { Transparency = 1 })
	K.Light(hl, VIOLET, 22, .9)
	return m
end

------------------------------------------------------------------------------------------------------------------
-- the COFFIN COASTER along the east edge
------------------------------------------------------------------------------------------------------------------

local function smooth(t)
	return t * t * (3 - 2 * t)
end

local function buildCoaster(root, L, rng)
	local m = K.Model(root, "CoffinCoaster")
	local X = L.Bounds.X1 - 7 -- track centreline
	local G = 1.4 -- half gauge
	-- (z, y) profile from the station (south) to the broken end (north); the loop is inserted at LOOP_Z
	local prof = {
		{ 2296, 3.2 }, { 2282, 3.2 }, { 2252, 22 }, { 2246, 22.4 }, { 2230, 3.6 }, { 2226, 3.4 },
	}
	local LOOP_Z, LOOP_R = 2222, 6.4
	local after = { { 2218, 3.4 }, { 2208, 6 }, { 2198, 14.5 }, { 2190, 9 }, { 2181, 13 } }
	local pts = {}
	local function push(z, y, x)
		table.insert(pts, V3(x or X, y, z))
	end
	-- interpolate the profile with eased segments, ~2.5-stud steps
	local function run(list)
		for i = 1, #list - 1 do
			local a, b = list[i], list[i + 1]
			local n = math.max(1, math.floor(math.abs(b[1] - a[1]) / 2.5))
			for s = (i == 1 and #pts == 0) and 0 or 1, n do
				local t = s / n
				push(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * smooth(t))
			end
		end
	end
	run(prof)
	-- vertical loop (heading north = -Z), drifting 1.6 studs sideways so the exit clears the entry
	local loopStart = #pts
	for s = 1, 20 do
		local th = s / 20 * 2 * PI
		push(LOOP_Z + 4 - LOOP_R * math.sin(th) - 4 * s / 20, 3.4 + LOOP_R - LOOP_R * math.cos(th), X - 1.6 * s / 20)
	end
	local loopEnd = #pts
	local tail = { { pts[#pts].Z, 3.4 } }
	for _, e in ipairs(after) do
		table.insert(tail, e)
	end
	local n0 = #pts
	run(tail)
	for i = n0 + 1, #pts do
		pts[i] = V3(X - 1.6, pts[i].Y, pts[i].Z)
	end
	-- rails, sleepers, supports
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local along = (b - a).Unit
		local inLoop = i > loopStart and i <= loopEnd
		local lateral = V3(1, 0, 0)
		local normal = lateral:Cross(along).Unit -- "up" of the track
		if normal.Y < 0 and not inLoop then
			normal = -normal
		end
		for _, s in ipairs({ -1, 1 }) do
			K.Bar(m, "CoasterRail", a + lateral * s * G + normal * .25, b + lateral * s * G + normal * .25, .5, .5, s < 0 and BONE:Lerp(STRIPES[3], .25) or BONE,
				M.Metal)
		end
		if not inLoop then
			K.Bar(m, "CoasterSpine", a - normal * .3, b - normal * .3, .7, .7, STRIPES[3]:Lerp(INK, .35), M.Metal)
		end
		if i % 3 == 0 then
			K.Bar(m, "CoasterSleeper", a - lateral * (G + .5) - normal * .05, a + lateral * (G + .5) - normal * .05, .45, .45, WOOD_D, M.Wood)
		end
		if not inLoop and i % 4 == 0 and a.Y > 2 then
			for _, s in ipairs({ -1, 1 }) do
				local top = a + lateral * s * (G + .1) - V3(0, .35, 0)
				K.Bar(m, "CoasterSupport", V3(top.X + s * .5, 0, top.Z), top, .55, .55, STRIPES[1], M.Wood, S())
			end
			if a.Y > 7 then
				-- lattice: an X between the two legs, a cap tie under the track
				local yb = a.Y - .9
				K.Bar(m, "CoasterBrace", V3(a.X - G - .4, .5, a.Z), V3(a.X + G + .4, yb, a.Z), .3, .3, STRIPES[2]:Lerp(INK, .45), M.Wood)
				K.Bar(m, "CoasterBrace", V3(a.X + G + .4, .5, a.Z), V3(a.X - G - .4, yb, a.Z), .3, .3, STRIPES[2]:Lerp(INK, .45), M.Wood)
				K.Bar(m, "CoasterBrace", V3(a.X - G - .4, yb, a.Z), V3(a.X + G + .4, yb, a.Z), .35, .35, STRIPES[1], M.Wood)
			end
		end
		-- chaser bulbs along the lift hill (lit once FUNERAL RUN is cleared)
		if i % 2 == 1 and a.Z < 2282 and a.Z > 2250 then
			K.Ball(m, "LiftBulb", .45, CF(a + lateral * (G + .45) + normal * .35), i % 4 == 1 and CANDLE or VIOLET, M.Neon, { Attrs = { UyLightAtSeal = 2 } })
		end
	end
	-- loop supports: two tall towers either side
	for _, s in ipairs({ -1, 1 }) do
		local zt = LOOP_Z + 2
		K.Bar(m, "LoopTower", V3(X - .8 + s * (G + 1.4), 0, zt - 3), V3(X - .8 + s * (G + 1.4), 3.4 + LOOP_R, zt), .6, .6, BONE:Lerp(WOOD_D, .55), M.Wood, S())
		K.Bar(m, "LoopTower", V3(X - .8 + s * (G + 1.4), 0, zt + 3), V3(X - .8 + s * (G + 1.4), 3.4 + LOOP_R, zt), .6, .6, BONE:Lerp(WOOD_D, .55), M.Wood, S())
		K.Bar(m, "LoopAxle", V3(X - .8 + s * (G + 1.4), 3.4 + LOOP_R, zt), V3(X - .8, 3.4 + LOOP_R, zt), .4, .4, IRON, M.CorrodedMetal)
	end
	-- the broken end: splayed rails and a coffin cart dangling nose down
	local last = pts[#pts]
	local bendL = last + V3(-G - 1.2, 1.8, -2.4)
	local bendR = last + V3(G + .8, -1.4, -2.8)
	K.Bar(m, "CoasterRailBroken", last + V3(-G, .2, 0), bendL, .36, .36, C(110, 60, 50), M.CorrodedMetal)
	K.Bar(m, "CoasterRailBroken", last + V3(G, .2, 0), bendR, .36, .36, C(110, 60, 50), M.CorrodedMetal)
	local hang = last + V3(0, -3.2, -1.2)
	K.Bar(m, "DanglingChain", last + V3(0, .1, 0), hang + V3(0, 1.6, 0), .15, .15, IRON, M.CorrodedMetal)
	local dc = K.Model(m, "DanglingCart")
	coffinCar(dc, CF(hang) * ANG(-1.05, 0, .15), 4, 2.6, STRIPES[1], rng)
	-- station: platform, steps, striped canopy, sign, carts waiting on the track
	local st = K.Model(m, "CoasterStation")
	local sz0, sz1 = 2280, 2297
	local px = X - G - 3.3
	K.Part(st, "StationDeck", V3(5, 2.6, sz1 - sz0), CF(px, 1.3, (sz0 + sz1) / 2), WOOD, M.WoodPlanks, S())
	for k = 0, 2 do
		K.Part(st, "StationStep", V3(1.2, .85 * (k + 1), 4), CF(px - 3.1 + k * 1.2 - 1.2, .425 * (k + 1), sz0 + 4), FLAG, M.Slate, S())
	end
	for _, z in ipairs({ sz0 + .6, sz1 - .6 }) do
		for _, x in ipairs({ px - 2.2, X + G + 1 }) do
			K.CylY(st, "StationPost", 7.6, .5, CF(x, 2.6 + 3.8, z), STRIPES[1], M.Wood, S())
		end
	end
	for k = 0, 5 do
		local z0 = sz0 + k * (sz1 - sz0) / 6
		local z1 = z0 + (sz1 - sz0) / 6
		trapezoid(st, "StationCanopy", V3(px - 2.8, 10.2, z0), V3(px - 2.8, 10.2, z1), V3(X + G + 1.6, 11.8, z0), V3(X + G + 1.6, 11.8, z1), .25,
			STRIPES[k % 2 + 2], M.Fabric)
	end
	local csign = K.Part(st, "CoasterSign", V3(.3, 1.8, 10), CF(px - 2.9, 9, (sz0 + sz1) / 2), INK, M.SmoothPlastic)
	sign(csign, N.Left, "COFFIN COASTER", BONE, { PixelsPerStud = 24, H = .75, StrokeColor = VIOLET })
	lantern(st, CF(px - 2.2, 8, sz0 + 3), CANDLE, "Orange", true, 18)
	for k = 0, 1 do
		local z = 2290 - k * 4.6
		coffinCar(st, CF(X, 3.6, z), 4, 2.6, k == 0 and STRIPES[3] or STRIPES[1], rng)
	end
	-- the cart stuck at the lift crest
	coffinCar(m, CF(X, 22.6, 2249) * ANG(0, 0, .06), 4, 2.6, STRIPES[1], rng)
	return m
end

------------------------------------------------------------------------------------------------------------------
-- FUNERAL RUN: lane, checkpoint arches, pendulums, conveyor
------------------------------------------------------------------------------------------------------------------

local function checkpointArch(m, i: number, pos: Vector3, dir: Vector3, rng, finish: boolean)
	local a = K.Model(m, "RunCheckpoint_" .. i)
	local Fm = K.Look(pos, pos + dir) -- local X = lateral, -Z = run direction
	local PH = 7.4 -- pillar height
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * ARCH_HALF
		K.Part(a, "ArchPlinth", V3(2, .6, 2), Fm * CF(x, .3, 0), FLAG, M.Slate, S())
		K.Part(a, "ArchPillar", V3(1.4, PH * .55, 1.4), Fm * CF(x, .6 + PH * .275, 0), STRIPES[1], M.WoodPlanks, S())
		K.Part(a, "ArchPillar", V3(1.3, PH * .45, 1.3), Fm * CF(x, .6 + PH * .55 + PH * .225, 0), STRIPES[2], M.WoodPlanks, S())
		K.Ball(a, "ArchFinial", 1.3, Fm * CF(x, PH + 1.25, 0), BONE, M.SmoothPlastic)
		K.Part(a, "ArchFinialGlow", V3(.5, .5, .5), Fm * CF(x, PH + 2.1, 0) * ANG(PI / 4, 0, PI / 4), i % 2 == 0 and GREEN or VIOLET, M.Neon)
	end
	-- arch (8 bone segments) + inner Neon hoop
	local cy = PH + .6
	local prev, prevIn
	for k = 0, 8 do
		local th = k / 8 * PI
		local p = (Fm * CF(math.cos(th) * ARCH_HALF, cy + math.sin(th) * ARCH_HALF * .8, 0)).Position
		local pin = (Fm * CF(math.cos(th) * (ARCH_HALF - .9), cy + math.sin(th) * (ARCH_HALF * .8 - .9), 0)).Position
		if prev then
			K.Bar(a, "ArchSpan", prev, p, 1.1, .9, BONE:Lerp(FLAG, .25), M.SmoothPlastic)
			K.Bar(a, "RunRing", prevIn, pin, .32, .32, i == 10 and CANDLE or VIOLET, M.Neon, { Transparency = .1 })
		end
		prev, prevIn = p, pin
	end
	-- number plaque (digits, NoTranslate) on both faces
	local plaque = K.CylZ(a, "ArchPlaque", .4, 2.8, Fm * CF(0, cy + ARCH_HALF * .8 + 1.2, 0), INK, M.SmoothPlastic)
	K.CylZ(a, "ArchPlaqueRim", .3, 3.2, Fm * CF(0, cy + ARCH_HALF * .8 + 1.2, 0), BRASS, M.Metal)
	-- the plaque cylinder's faces: Left/Right are its round ends (axis along local X after CylZ's turn)
	digits(plaque, N.Left, tostring(i), BONE, { PixelsPerStud = 30, W = .7, H = .7, StrokeColor = VIOLET })
	digits(plaque, N.Right, tostring(i), BONE, { PixelsPerStud = 30, W = .7, H = .7, StrokeColor = VIOLET })
	K.Part(a, "RunLine", V3(ARCH_HALF * 2 - 1.6, .04, .6), Fm * CF(0, .1, 0), i == 10 and CANDLE or VIOLET, M.Neon, { Transparency = .25 })
	if finish then
		local fb = K.Part(a, "FinishBoard", V3(9, 1.5, .3), Fm * CF(0, cy + ARCH_HALF * .8 + 3.2, 0), C(170, 60, 70), M.SmoothPlastic)
		sign(fb, N.Back, "FINISH LINE", BONE, { PixelsPerStud = 30, H = .78 })
		sign(fb, N.Front, "FINISH LINE", BONE, { PixelsPerStud = 30, H = .78 })
		for k = -3, 3 do
			K.Part(a, "FinishTile", V3(1.4, .05, .9), Fm * CF(k * 1.8, .11, .9), k % 2 == 0 and STRIPES[1] or STRIPES[2], M.SmoothPlastic)
		end
	end
	setAll(a, "RunCheckpoint", i)
	return a
end

local function pendulumRig(m, i: number, pos: Vector3, dir: Vector3, phase: number, rng)
	local Fm = K.Look(pos, pos + dir) -- X lateral (swing direction), -Z = along the lane
	local g = K.Model(m, "RunGallows_" .. i)
	local PY = PIVOT_Y
	for _, s in ipairs({ -1, 1 }) do
		local z = s * 5
		for _, lx in ipairs({ -7.6, 7.6 }) do
			K.Part(g, "GallowsPost", V3(1.1, PY + 1.4, 1.1), Fm * CF(lx, (PY + 1.4) / 2, z), WOOD_D, M.Wood, S())
			K.Part(g, "GallowsFoot", V3(2, .5, 2), Fm * CF(lx, .25, z), FLAG, M.Slate)
			K.Bar(g, "GallowsKnee", (Fm * CF(lx, PY - 2.2, z)).Position, (Fm * CF(lx - math.sign(lx) * 2.4, PY + .9, z)).Position, .5, .5, WOOD_D, M.Wood)
		end
		K.Part(g, "GallowsCross", V3(16.4, 1, 1.1), Fm * CF(0, PY + 1.1, z), WOOD, M.Wood)
		Y.Skull(g, Fm * CF(0, PY + 2.2, z) * ANG(0, s > 0 and 0 or PI, 0), 1.1, nil, BONE)
	end
	K.Part(g, "GallowsBeam", V3(1.3, 1.3, 11.4), Fm * CF(0, PY + 1.75, 0), WOOD, M.Wood)
	K.CylZ(g, "GallowsAxle", 3.6, .7, Fm * CF(0, PY, 0), IRON, M.CorrodedMetal)
	-- noose rope coils on the beam ends
	for _, s in ipairs({ -1, 1 }) do
		K.Part(g, "Noose", V3(.2, 2.4, .2), Fm * CF(0, PY + .2, s * 4.4), C(150, 140, 120), M.Fabric)
		K.CylY(g, "NooseLoop", .3, 1, Fm * CF(0, PY - 1.1, s * 4.4), C(150, 140, 120), M.Fabric)
	end
	-- the swinging part
	local pm = K.Model(m, "RunPendulum_" .. i)
	pm.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local hinge = K.Part(pm, "PendulumHinge", V3(.8, .8, .8), Fm * CF(0, PY, 0), IRON, M.CorrodedMetal, { Transparency = 1 })
	pm.PrimaryPart = hinge
	pm:SetAttribute("UySwingAmp", SWING_AMP)
	pm:SetAttribute("UySwingPeriod", SWING_PERIOD)
	pm:SetAttribute("UySwingPhase", phase)
	pm:SetAttribute("UySwingAxis", "Z")
	pm:SetAttribute("RunPendulum", i)
	local COFFIN_H, COFFIN_W, COFFIN_D = 6.4, 3.4, 2.1
	local cy = 1.6 + COFFIN_H / 2 -- coffin centre height at rest (foot 1.6 above the lane)
	local Cf = Fm * CF(0, cy, 0)
	K.Part(pm, "PendulumCollar", V3(1.4, 1.4, 1.6), Fm * CF(0, PY, 0), IRON, M.CorrodedMetal)
	for _, sx in ipairs({ -1, 1 }) do
		K.Bar(pm, "PendulumArm", (Fm * CF(sx * .3, PY - .5, 0)).Position, (Cf * CF(sx * COFFIN_W * .3, COFFIN_H / 2 + .1, 0)).Position, .32, .32, IRON, M.CorrodedMetal)
	end
	K.Part(pm, "PendulumBar", V3(COFFIN_W * .8, .4, .4), Cf * CF(0, COFFIN_H / 2 + .1, 0), IRON, M.CorrodedMetal)
	coffinUpright(pm, Cf, COFFIN_W, COFFIN_H, COFFIN_D, i == 2 and STRIPES[1] or WOOD, i == 3 and GREEN or VIOLET, nil, true)
	Y.Skull(pm, Cf * CF(0, COFFIN_H / 2 - .9, -COFFIN_D / 2 - .45), .9, i == 3 and GREEN or VIOLET, BONE)
	for _, d in ipairs(pm:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	return g, pm
end

local function buildRun(root, L, rng)
	local m = K.Model(root, "FuneralRun")
	local path = F.LanePath(L)
	local lane = K.Model(m, "RunLane")
	local cpDir = {}
	for i, e in ipairs(path) do
		if e.Kind == "Checkpoint" then
			cpDir[e.Index] = e.Dir or pathDir(path, i)
		end
	end
	-- the conveyor occupies the middle of leg 2 -> 3
	local cp = L.Carnival.Checkpoints
	local conv0, conv1
	do
		local a, b = cp[2], cp[3]
		local d = flat(b - a).Unit
		conv0, conv1 = a + d * 8, b - d * 8
	end
	-- paving: one strip per leg (skipping the carousel deck and the belt), round joints, kerbs, chevrons
	local chevronEvery, sinceChevron = 18, 9
	for i = 1, #path - 1 do
		local a, b = path[i].Pos, path[i + 1].Pos
		local onDeck = path[i].Kind == "Carousel" or path[i + 1].Kind == "Carousel"
		if not onDeck then
			local segs = { { a, b } }
			if path[i].Index == 2 then
				segs = { { a, conv0 }, { conv1, b } }
			end
			for _, sg in ipairs(segs) do
				local s0, s1 = sg[1], sg[2]
				local len = flat(s1 - s0).Magnitude
				local mid = (s0 + s1) / 2
				local cf = K.Look(V3(mid.X, .03, mid.Z), V3(s1.X, .03, s1.Z))
				K.Part(lane, "RunLane", V3(LANE_W, .1, len), cf, LANE, M.Cobblestone)
				for _, sx in ipairs({ -1, 1 }) do
					K.Part(lane, "RunKerb", V3(.5, .2, len), cf * CF(sx * (LANE_W / 2 + .2), .07, 0), BONE:Lerp(FLAG, .55), M.Slate)
				end
				-- chevrons pointing along the run
				local d = flat(s1 - s0).Unit
				local t = chevronEvery - sinceChevron
				while t < len - 3 do
					local p = s0 + d * t
					local ccf = K.Look(V3(p.X, .1, p.Z), V3(p.X, .1, p.Z) + d)
					for _, sx in ipairs({ -1, 1 }) do
						K.Part(lane, "RunChevron", V3(.45, .04, 2.6), ccf * CF(sx * .85, 0, .45) * ANG(0, -sx * .65, 0), VIOLET, M.Neon, { Transparency = .35 })
					end
					t += chevronEvery
				end
				sinceChevron = (len - (t - chevronEvery))
			end
		end
		if not (path[i + 1].Kind == "Carousel") and i + 1 < #path then
			K.CylY(lane, "RunLaneJoint", .1, LANE_W, CF(path[i + 1].Pos.X, .035, path[i + 1].Pos.Z), LANE, M.Cobblestone)
		end
	end
	K.CylY(lane, "RunLaneJoint", .1, LANE_W, CF(path[1].Pos.X, .035, path[1].Pos.Z), LANE, M.Cobblestone)
	K.CylY(lane, "RunLaneJoint", .1, LANE_W + 2, CF(path[#path].Pos.X, .035, path[#path].Pos.Z), LANE, M.Cobblestone)
	-- checkpoint arches
	local arches = K.Model(m, "Checkpoints")
	for i, p in ipairs(cp) do
		checkpointArch(arches, i, p, cpDir[i], rng, i == #cp)
	end
	-- pendulums (phases spread so the three never swing in step)
	local rigs = K.Model(m, "Pendulums")
	for i, p in ipairs(L.Carnival.Pendulums) do
		-- lane direction at the pendulum = direction of the leg / via point it sits on
		local best, bd = 1, math.huge
		for k = 1, #path - 1 do
			local a, b = path[k].Pos, path[k + 1].Pos
			local ab = flat(b - a)
			local t = math.clamp(flat(p - a):Dot(ab) / ab:Dot(ab), 0, 1)
			local d = (flat(a + ab * t) - flat(p)).Magnitude
			if d < bd then
				best, bd = k, d
			end
		end
		local dir = flat(path[best + 1].Pos - path[best].Pos).Unit
		for k, e in ipairs(path) do
			if (flat(e.Pos) - flat(p)).Magnitude < .5 then
				dir = pathDir(path, k)
			end
		end
		pendulumRig(rigs, i, p, dir, (i - 1) * 2 * PI / 3, rng)
	end
	-- COFFIN CONVEYOR (leg 2 -> 3): belt + ramps, roller beds with coffins, two gantries and the sign
	local cv = K.Model(m, "CoffinConveyor")
	local d = flat(conv1 - conv0).Unit
	local len = flat(conv1 - conv0).Magnitude
	local mid = (conv0 + conv1) / 2
	local Cf = K.Look(V3(mid.X, 0, mid.Z), V3(mid.X, 0, mid.Z) + d)
	local BELT_Y, SPEED = .6, 8
	local belt = K.Part(cv, "ConveyorBelt", V3(LANE_W, BELT_Y, len), Cf * CF(0, BELT_Y / 2, 0), C(34, 30, 40), M.Fabric, { Solid = true, Shadow = false })
	;(belt :: any).Velocity = d * SPEED
	belt:SetAttribute("RunConveyor", true)
	belt:SetAttribute("UyConveyorSpeed", SPEED)
	for _, s in ipairs({ -1, 1 }) do
		K.Wedge(cv, "ConveyorRamp", V3(LANE_W, BELT_Y, 2.4), Cf * CF(0, BELT_Y / 2, s * (len / 2 + 1.2)) * ANG(0, s > 0 and 0 or PI, 0), FLAG, M.Slate,
			{ Solid = true, Shadow = false })
	end
	-- belt slats (visual)
	for k = 0, math.floor(len / 2.2) do
		K.Part(cv, "BeltSlat", V3(LANE_W - .4, .05, .25), Cf * CF(0, BELT_Y + .02, -len / 2 + 1 + k * 2.2), C(60, 52, 66), M.Metal)
	end
	for _, s in ipairs({ -1, 1 }) do
		-- side frame + roller bed (outside the lane)
		K.Part(cv, "ConveyorFrame", V3(.8, 1.4, len + 4.8), Cf * CF(s * (LANE_W / 2 + .4), .7, 0), IRON, M.CorrodedMetal, S())
		K.Part(cv, "RollerBed", V3(3.4, 1.6, len - 2), Cf * CF(s * (LANE_W / 2 + 2.6), .8, 0), IRON:Lerp(WOOD_D, .5), M.CorrodedMetal, S())
		for k = 0, 6 do
			K.CylX(cv, "Roller", 3.2, .7, Cf * CF(s * (LANE_W / 2 + 2.6), 1.75, -len / 2 + 2 + k * (len - 4) / 6), BRASS:Lerp(IRON, .5), M.Metal)
		end
		-- coffins riding the beds
		for k = 0, 2 do
			local z = -len / 2 + 5 + k * (len - 10) / 2 + s * 1.5
			local lie = Cf * CF(s * (LANE_W / 2 + 2.6), 2.6, z) * ANG(-PI / 2, 0, 0)
			coffinUpright(cv, lie, 2.6, 5.2, 1.4, (k + (s > 0 and 1 or 0)) % 2 == 0 and WOOD or STRIPES[1], VIOLET:Lerp(INK, .3), nil)
		end
	end
	for _, z in ipairs({ -len / 2 + 3, len / 2 - 3 }) do
		for _, s in ipairs({ -1, 1 }) do
			K.Part(cv, "GantryPost", V3(1, 12, 1), Cf * CF(s * (LANE_W / 2 + 4.8), 6, z), STRIPES[1], M.Metal, S())
		end
		K.Part(cv, "GantryBeam", V3(LANE_W + 11, 1.2, 1.2), Cf * CF(0, 12.4, z), IRON, M.CorrodedMetal)
		for k = -2, 2 do
			K.Part(cv, "GantryHook", V3(.15, 2.4, .15), Cf * CF(k * 2.6, 10.6, z), IRON, M.CorrodedMetal)
		end
	end
	local cs = K.Part(cv, "ConveyorSign", V3(10, 1.8, .3), Cf * CF(0, 14.2, -len / 2 + 3), INK, M.SmoothPlastic)
	sign(cs, N.Back, "COFFIN WORKS", BONE, { PixelsPerStud = 24, H = .75, StrokeColor = VIOLET })
	sign(cs, N.Front, "COFFIN WORKS", BONE, { PixelsPerStud = 24, H = .75, StrokeColor = VIOLET })
	return m, path
end

------------------------------------------------------------------------------------------------------------------
-- props: lamps, bunting, ghost carts, balloons, graves, crates, fog markers
------------------------------------------------------------------------------------------------------------------

local function ghostCart(m, cf: CFrame, title: string, color, rng)
	local g = K.Model(m, "GhostCart")
	K.Part(g, "CartBody", V3(4.4, 2.2, 2.6), cf * CF(0, 2.0, 0), color, M.WoodPlanks, S())
	K.Part(g, "CartTrim", V3(4.6, .3, 2.8), cf * CF(0, 3.2, 0), BRASS, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		K.CylX(g, "CartWheel", .35, 2, cf * CF(sx * 1.4, 1, 1.45), WOOD_D, M.Wood)
		K.CylX(g, "CartWheel", .35, 2, cf * CF(sx * 1.4, 1, -1.45), WOOD_D, M.Wood)
		K.Part(g, "CanopyPost", V3(.2, 4, .2), cf * CF(sx * 2, 5.2, 0), BRASS, M.Metal)
	end
	K.Bar(g, "CartHandle", (cf * CF(2.2, 2.6, 0)).Position, (cf * CF(4.2, 2.2, 0)).Position, .2, .2, WOOD_D, M.Wood)
	for k = 0, 3 do
		trapezoid(g, "CartCanopy", (cf * CF(-2.6 + k * 1.3, 7.2, -1.8)).Position, (cf * CF(-1.3 + k * 1.3, 7.2, -1.8)).Position,
			(cf * CF(-2.6 + k * 1.3, 7.8, 0)).Position, (cf * CF(-1.3 + k * 1.3, 7.8, 0)).Position, .12, STRIPES[k % 2 + 2], M.Fabric)
		trapezoid(g, "CartCanopy", (cf * CF(-2.6 + k * 1.3, 7.8, 0)).Position, (cf * CF(-1.3 + k * 1.3, 7.8, 0)).Position,
			(cf * CF(-2.6 + k * 1.3, 7.2, 1.8)).Position, (cf * CF(-1.3 + k * 1.3, 7.2, 1.8)).Position, .12, STRIPES[k % 2 + 2], M.Fabric)
	end
	local board = K.Part(g, "CartSign", V3(3.8, .9, .12), cf * CF(0, 2.1, -1.36), INK, M.SmoothPlastic)
	sign(board, N.Front, title, BONE, { PixelsPerStud = 30, H = .75, StrokeColor = VIOLET })
	-- the ghost vendor behind the cart
	local vg = cf * CF(0, 3.8, 2.2)
	K.Ellipsoid(g, "VendorGhost", V3(1.8, 3.2, 1.5), vg, GHOST, M.Neon, { Transparency = .55 })
	K.Ellipsoid(g, "VendorGhostHead", V3(1.4, 1.4, 1.3), vg * CF(0, 2, 0), GHOST, M.Neon, { Transparency = .45 })
	for _, sx in ipairs({ -1, 1 }) do
		K.Ball(g, "VendorEye", .28, vg * CF(sx * .3, 2.1, -.6), INK, M.SmoothPlastic)
	end
	K.Part(g, "VendorCap", V3(1.2, .4, 1.2), vg * CF(0, 2.8, 0), STRIPES[2], M.Fabric)
	-- wares on the counter: puffs of grey candy floss / bone popcorn
	for k = 1, 3 do
		K.Ball(g, "CartWare", rng:NextNumber(.7, 1.1), cf * CF(-1.5 + k * .8, 3.7, rng:NextNumber(-.5, .5)), k % 2 == 0 and C(200, 190, 210) or BONE, M.SmoothPlastic)
	end
	for b = 1, 3 do
		balloonSkull(g, (cf * CF(2, 7.4, 0)).Position, (cf * CF(2 + rng:NextNumber(-.5, 2), 9.5 + b * 1.2, rng:NextNumber(-1.5, 1.5))).Position,
			({ BONE, C(190, 160, 230), C(170, 230, 180) })[b], rng)
	end
	return g
end

-- game stall facing cf's -Z: counter, back wall with a shelf of skull prizes, posts, striped awning, title board
local function gameStall(m, cf: CFrame, title: string, rng, glow)
	local g = K.Model(m, "GameStall")
	local w, d = 8.4, 4.6
	K.Part(g, "StallFloor", V3(w, .4, d), cf * CF(0, .2, 0), WOOD_D, M.WoodPlanks, S())
	K.Part(g, "StallCounter", V3(w, 3, .6), cf * CF(0, 1.9, -d / 2 + .3), STRIPES[3], M.WoodPlanks, S())
	K.Part(g, "StallCounterTop", V3(w + .4, .3, 1.2), cf * CF(0, 3.5, -d / 2 + .3), WOOD, M.Wood)
	K.Part(g, "StallBack", V3(w, 7.4, .4), cf * CF(0, 4.1, d / 2 - .2), STRIPES[1], M.WoodPlanks, S())
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(g, "StallSide", V3(.4, 7.4, d), cf * CF(sx * (w / 2 - .2), 4.1, 0), STRIPES[1], M.WoodPlanks, S())
		K.CylY(g, "StallPost", 9, .5, cf * CF(sx * (w / 2 + .1), 4.5, -d / 2 - .1), BRASS, M.Metal)
	end
	for row = 0, 1 do
		K.Part(g, "PrizeShelf", V3(w - 1, .25, .9), cf * CF(0, 4.6 + row * 1.6, d / 2 - .7), WOOD, M.Wood)
		for k = 0, 4 do
			local col = ({ BONE, C(190, 160, 230), C(170, 230, 180), C(240, 200, 150) })[(k + row) % 4 + 1]
			local pc = cf * CF(-3 + k * 1.5, 5.25 + row * 1.6, d / 2 - .7) * ANG(0, PI + rng:NextNumber(-.3, .3), 0)
			K.Ball(g, "PrizeSkull", 1, pc, col, M.SmoothPlastic)
		end
	end
	-- toss targets: three bottles of bone on the counter
	for k = -1, 1 do
		K.CylY(g, "TossBottle", 1, .5, cf * CF(k * 1.2, 4.15, -d / 2 + .4), k == 0 and GREEN:Lerp(INK, .4) or STRIPES[2], M.Glass)
	end
	for k = 0, 5 do
		local x = -w / 2 + (k + .5) * w / 6
		K.Wedge(g, "StallAwning", V3(w / 6, 1.1, 2.2), cf * CF(x, 8.5, -d / 2 - .6) * ANG(0, PI, 0), STRIPES[k % 2 + 2], M.Fabric)
	end
	K.Part(g, "StallRoof", V3(w + .6, .3, d + .6), cf * CF(0, 7.95, .3), WOOD_D, M.Slate)
	local board = K.Part(g, "StallTitle", V3(w - .4, 1.5, .25), cf * CF(0, 9.9, -d / 2 + .4), INK, M.SmoothPlastic)
	sign(board, N.Front, title, BONE, { PixelsPerStud = 24, H = .75, StrokeColor = VIOLET })
	local bulb = K.Part(g, "StallBulb", V3(.5, .5, .5), cf * CF(0, 7.5, -d / 2 + .9), glow, M.Neon, { Attrs = { HwLantern = "Orange" } })
	K.Light(bulb, glow, 14, .7)
	return g
end

-- THE BELL STRIKER: the strongman's high striker (lever pad, scale post, stuck puck, bell, mallet)
local function bellStriker(m, cf: CFrame)
	local g = K.Model(m, "BellStriker")
	K.Part(g, "StrikerBase", V3(4, .6, 4), cf * CF(0, .3, 0), FLAG, M.Slate, S())
	K.Part(g, "StrikerPad", V3(1.6, .5, 2.2), cf * CF(0, .85, -1) * ANG(.12, 0, 0), C(170, 40, 50), M.SmoothPlastic)
	local H = 17
	K.Part(g, "StrikerPost", V3(1, H, .7), cf * CF(0, .6 + H / 2, .6), STRIPES[1], M.Wood, S())
	local bands = { GREEN, CANDLE, C(200, 60, 60) }
	for k = 1, 3 do
		K.Part(g, "StrikerScale", V3(1.06, H / 3 - .4, .1), cf * CF(0, .6 + (k - .5) * H / 3, .22), bands[k]:Lerp(INK, .35), M.SmoothPlastic)
	end
	for k = 1, 8 do
		K.Part(g, "StrikerTick", V3(.7, .12, .12), cf * CF(0, .6 + k * H / 9, .18), BONE, M.SmoothPlastic)
	end
	K.Part(g, "StrikerWire", V3(.08, H - 1, .08), cf * CF(0, .6 + H / 2, -.1), IRON, M.Metal)
	K.Ball(g, "StrikerPuck", .7, cf * CF(0, .6 + H * .62, -.1), BRASS, M.Metal)
	local bell = K.Ball(g, "StrikerBell", 2, cf * CF(0, H + 1.4, .4), BRASS, M.Metal)
	K.CylY(g, "StrikerBellLip", .35, 2.3, cf * CF(0, H + .6, .4), BRASS:Lerp(INK, .2), M.Metal)
	K.Light(bell, CANDLE, 14, .7)
	Y.Skull(g, cf * CF(0, H + 3, .4), 1.2, VIOLET, BONE)
	-- the mallet, leaning on the base
	K.Rod(g, "MalletHandle", (cf * CF(1.6, .6, -1.6)).Position, (cf * CF(1.9, 4.2, -.4)).Position, .3, WOOD, M.Wood)
	K.CylX(g, "MalletHead", 1.8, 1, cf * CF(1.6, .9, -1.8) * ANG(0, .3, 0), C(170, 40, 50), M.Wood)
	local board = K.Part(g, "StrikerSign", V3(5.6, 1.3, .25), cf * CF(0, 3.4, -.15), INK, M.SmoothPlastic)
	sign(board, N.Front, "RING THE BELL", BONE, { PixelsPerStud = 30, H = .78, StrokeColor = VIOLET })
	return g
end

-- fortune teller's little striped tent with a glowing crystal ball inside
local function fortuneTent(m, c: Vector3, faceTo: Vector3)
	local g = K.Model(m, "FortuneTent")
	local R, WH, PEAK = 4.6, 5, 10.5
	local aDoor = math.atan2(faceTo.Z - c.Z, faceTo.X - c.X)
	local NP = 8
	for k = 0, NP - 1 do
		local a0, a1 = aDoor + (k + .5) / NP * 2 * PI, aDoor + (k + 1.5) / NP * 2 * PI
		local col = k % 2 == 0 and STRIPES[3] or STRIPES[1]
		if k ~= NP - 1 then
			local p0, p1 = ring(c, a0, R, 0), ring(c, a1, R, 0)
			local mid = (p0 + p1) / 2
			K.Part(g, "FortuneWall", V3(.3, WH, (p1 - p0).Magnitude + .1), K.Look(mid + V3(0, WH / 2, 0), mid + V3(0, WH / 2, 0) + (p1 - p0).Unit), col, M.Fabric, S())
		end
		trapezoid(g, "FortuneRoof", ring(c, a0, R + .5, WH), ring(c, a1, R + .5, WH), V3(c.X, PEAK, c.Z), V3(c.X, PEAK, c.Z), .25, col, M.Fabric)
	end
	K.CylY(g, "FortunePole", PEAK + 2.2, .4, CF(c + V3(0, (PEAK + 2.2) / 2, 0)), BRASS, M.Metal)
	K.Ball(g, "FortuneStar", .8, CF(c + V3(0, PEAK + 2.4, 0)), MOON, M.Neon)
	-- door curtains tied back
	local dm = ring(c, aDoor, R, 0)
	local Df = K.Look(dm, dm + flat(dm - c).Unit)
	for _, sx in ipairs({ -1, 1 }) do
		trapezoid(g, "FortuneCurtain", (Df * CF(sx * 1.8, 0, 0)).Position, (Df * CF(sx * 1.1, 0, -.2)).Position, (Df * CF(sx * 1.8, WH, 0)).Position,
			(Df * CF(sx * .5, WH, 0)).Position, .15, VIOLET:Lerp(INK, .45), M.Fabric)
	end
	K.CylY(g, "FortuneTable", 2.4, 2.6, CF(c + V3(0, 1.2, 0)), C(60, 30, 70), M.Fabric)
	local orb = K.Ball(g, "CrystalBall", 1.3, CF(c + V3(0, 3.05, 0)), MOON, M.Neon, { Transparency = .15 })
	K.Light(orb, VIOLET, 14, .9)
	Y.Skull(g, CF(c + V3(.9, 2.75, .4)) * ANG(0, aDoor, 0), .6, nil, BONE)
	local board = K.Part(g, "FortuneSign", V3(6, 1.2, .2), Df * CF(0, WH + 1.2, -.6) * ANG(-.3, 0, 0), INK, M.SmoothPlastic)
	sign(board, N.Front, "THE FORTUNE HOUND", MOON, { PixelsPerStud = 30, H = .78, StrokeColor = VIOLET })
	return g
end

-- circus cage wagon, door hanging open (the beast is out: paw prints lead away)
local function cageWagon(m, cf: CFrame, rng)
	local g = K.Model(m, "CageWagon")
	local w, l = 5, 9
	K.Part(g, "WagonBed", V3(w, .8, l), cf * CF(0, 2, 0), STRIPES[3]:Lerp(INK, .2), M.WoodPlanks, S())
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			K.CylX(g, "WagonWheel", .5, 3, cf * CF(sx * (w / 2 + .3), 1.5, sz * l * .32), WOOD_D, M.Wood)
			K.CylX(g, "WagonHub", .7, .8, cf * CF(sx * (w / 2 + .3), 1.5, sz * l * .32), BRASS, M.Metal)
		end
	end
	K.Part(g, "WagonRoof", V3(w + .8, .5, l + .8), cf * CF(0, 7.6, 0), STRIPES[1], M.WoodPlanks)
	K.Part(g, "WagonRoofTrim", V3(w + 1, .35, l + 1), cf * CF(0, 7.25, 0), BRASS, M.Metal)
	-- bars on the long sides (one bent outward), back wall, open door at the front
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 5 do
			local z = -l / 2 + .6 + k * (l - 1.2) / 5
			if sx > 0 and k == 3 then
				K.Bar(g, "CageBarBent", (cf * CF(sx * w / 2, 2.4, z)).Position, (cf * CF(sx * (w / 2 + 1.4), 4.6, z + .3)).Position, .22, .22, IRON, M.CorrodedMetal)
				K.Bar(g, "CageBarBent", (cf * CF(sx * (w / 2 + 1.4), 4.6, z + .3)).Position, (cf * CF(sx * w / 2, 7.1, z)).Position, .22, .22, IRON, M.CorrodedMetal)
			else
				K.Part(g, "CageBar", V3(.22, 4.8, .22), cf * CF(sx * (w / 2 - .1), 4.8, z), IRON, M.CorrodedMetal, S())
			end
		end
	end
	K.Part(g, "WagonBack", V3(w, 4.8, .4), cf * CF(0, 4.8, l / 2 - .2), STRIPES[1], M.WoodPlanks, S())
	K.Part(g, "CageDoor", V3(.2, 4.6, w * .9), cf * CF(-w / 2 - w * .45 + .2, 4.8, -l / 2 - .1) * ANG(0, -.25, 0), IRON:Lerp(WOOD_D, .3), M.CorrodedMetal)
	K.Part(g, "CageStraw", V3(w - .6, .3, l - 1), cf * CF(0, 2.55, 0), SAWDUST, M.Sand)
	K.Ellipsoid(g, "CageEyes", V3(1, .3, .1), cf * CF(0, 4.4, l / 2 - .45), GREEN, M.Neon)
	-- paw prints leading away from the door
	for k = 1, 5 do
		local pp = cf * CF((k % 2 == 0 and .7 or -.7) + rng:NextNumber(-.2, .2), .03, -l / 2 - 1.5 - k * 2.1)
		K.Ellipsoid(g, "PawPad", V3(1, .06, .9), pp, INK, M.SmoothPlastic)
		for t = -1, 1 do
			K.Ellipsoid(g, "PawToe", V3(.35, .06, .4), pp * CF(t * .38, 0, -.65 + math.abs(t) * .15), INK, M.SmoothPlastic)
		end
	end
	return g
end

local function buildProps(root, L, rng)
	local m = K.Model(root, "Props")
	local c = L.Carnival
	-- crooked lamps beside the lane (outside the 5-stud clear lane), alternating sides
	local lamps = K.Model(m, "Lamps")
	local kinds = { { VIOLET, "Purple" }, { GREEN, "Green" }, { CANDLE, "Orange" } }
	local lampTips = {}
	-- {from checkpoint (0 = start), to checkpoint, t along the straight line, side}; spots keep clear of the conveyor
	-- (leg 2 -> 3) and the gallows (tests/underyard_carnival_row.luau checks the lane stays clear)
	local spots = {
		{ 0, 1, .55, 1 }, { 1, 2, .25, -1 }, { 3, 4, .5, -1 }, { 4, 5, .5, 1 }, { 5, 6, .2, -1 }, { 6, 7, .5, 1 }, { 8, 9, .5, -1 },
		{ 9, 10, .5, 1 },
	}
	local function cpAt(i)
		return i == 0 and c.RunStart or c.Checkpoints[i]
	end
	for k, sp in ipairs(spots) do
		local a, b = cpAt(sp[1]), cpAt(sp[2])
		local d = flat(b - a).Unit
		local side = V3(-d.Z, 0, d.X) * sp[4]
		local p = a:Lerp(b, sp[3]) + side * 9.5
		local kind = kinds[(k - 1) % 3 + 1]
		local _, tip = crookedLamp(lamps, p, rng:NextNumber(9, 11.5), rng, kind[1], kind[2], true)
		table.insert(lampTips, tip)
	end
	-- midway lamps
	for k, p in ipairs({ V3(80, 0, 2300), V3(104, 0, 2326), V3(139, 0, 2323), V3(98, 0, 2280) }) do
		local kind = kinds[(k + 1) % 3 + 1]
		local _, tip = crookedLamp(lamps, p, rng:NextNumber(9, 11), rng, kind[1], kind[2], k <= 3)
		table.insert(lampTips, tip)
	end
	-- ghostly bunting crossing over the lane between striped masts (lateral 10, the line hangs at y ~10)
	local buntCols = { STRIPES[2], STRIPES[3], STRIPES[1], GHOST }
	local crossings = { { 0, 1, .4 }, { 1, 2, .82 }, { 4, 5, .25 }, { 5, 6, .82 }, { 6, 7, .2 }, { 9, 10, .25 } }
	for k, cr in ipairs(crossings) do
		local a, b = cpAt(cr[1]), cpAt(cr[2])
		local d = flat(b - a).Unit
		local side = V3(-d.Z, 0, d.X)
		local p = a:Lerp(b, cr[3])
		local tops = {}
		for _, s in ipairs({ -1, 1 }) do
			local foot = p + side * s * 10
			K.CylY(m, "BuntingMast", 11.5, .45, CF(foot + V3(0, 5.75, 0)), STRIPES[1], M.Wood, S())
			K.CylY(m, "BuntingMastBand", .5, .5, CF(foot + V3(0, 7.5, 0)), STRIPES[2], M.Wood)
			K.Ball(m, "BuntingMastTop", .75, CF(foot + V3(0, 11.7, 0)), k % 2 == 0 and VIOLET or BONE, M.SmoothPlastic)
			table.insert(tops, foot + V3(0, 11.2, 0))
		end
		bunting(m, tops[1], tops[2], 1.4, 9, buntCols, k % 2 == 0)
	end
	-- the midway: one line from the booth corner over the start to the first lamp
	bunting(m, lampTips[#lampTips - 3] + V3(0, 1.2, 0), lampTips[#lampTips - 2] + V3(0, 1.2, 0), 1.5, 9, buntCols, true)
	-- a stack of spare coffins and hay bales by the north palisade
	local stack = K.Model(m, "CoffinStack")
	for k = 0, 4 do
		local row = k < 3 and 0 or 1
		local x = 168 + (k < 3 and k * 3 or (k - 3) * 3 + 1.5)
		coffinUpright(stack, CF(x, .7 + row * 1.4, 2178) * ANG(-PI / 2, 0, (k % 2) * PI), 2.6, 5.4, 1.4, k % 2 == 0 and WOOD or STRIPES[1],
			VIOLET:Lerp(INK, .4), nil)
	end
	for k, hb in ipairs({ V3(158, 0, 2178), V3(161, 0, 2181), V3(136, 0, 2228), V3(186, 0, 2262) }) do
		K.Part(m, "HayBale", V3(2.6, 1.6, 1.8), CF(hb + V3(0, .8, 0)) * ANG(0, k * .9, 0), SAWDUST:Lerp(C(150, 130, 80), .4), M.Fabric, S())
		K.Part(m, "HayTwine", V3(2.65, 1.65, .15), CF(hb + V3(0, .8, 0)) * ANG(0, k * .9, 0), C(70, 50, 40), M.Fabric)
	end
	local tentTop = c.Tent.Centre + V3(0, 32, 0)
	for _, ang in ipairs({ .4, 2.1, 3.9, 5.4 }) do
		local foot = ring(c.Tent.Centre, ang, c.Tent.Radius + 9, 9)
		bunting(m, tentTop - V3(0, 3, 0), foot, 1.2, 12, buntCols, true)
		K.CylY(m, "BuntingMast", 9.4, .5, CF(foot.X, 4.7, foot.Z), STRIPES[1], M.Wood, S())
		K.Ball(m, "BuntingMastTop", .8, CF(foot.X, 9.6, foot.Z), BONE, M.SmoothPlastic)
	end
	-- ghost carts
	local carts = K.Model(m, "GhostCarts")
	ghostCart(carts, K.Look(V3(108, 0, 2322), V3(108, 0, 2312)), "CANDY FLOSS", STRIPES[3], rng)
	ghostCart(carts, K.Look(V3(128, 0, 2240), V3(140, 0, 2240)), "BONE CORN", STRIPES[1], rng)
	ghostCart(carts, K.Look(V3(84, 0, 2190), V3(92, 0, 2200)), "CANDY FLOSS", C(70, 40, 80), rng)
	-- midway games, the bell striker, the fortune teller, the empty cage wagon
	local games = K.Model(m, "Games")
	gameStall(games, K.Look(V3(122, 0, 2319), V3(122, 0, 2300)), "SKULL TOSS", rng, CANDLE)
	gameStall(games, K.Look(V3(157, 0, 2318), V3(157, 0, 2300)), "LUCKY BONES", rng, GREEN)
	bellStriker(games, K.Look(V3(176, 0, 2320), V3(176, 0, 2300)))
	fortuneTent(games, V3(116, 0, 2247), c.Checkpoints[10])
	cageWagon(games, K.Look(V3(197, 0, 2179), V3(186, 0, 2181)) * ANG(0, PI / 2, 0), rng)
	-- balloon skull bunches on stakes around the tent and the wheel
	for k, p in ipairs({ V3(174, 0, 2270), V3(124, 0, 2196), V3(168, 0, 2326), V3(146, 0, 2280), V3(95, 0, 2240) }) do
		K.Part(m, "BalloonStake", V3(.3, 2, .3), CF(p + V3(0, 1, 0)), WOOD_D, M.Wood)
		for b = 1, 3 + k % 2 do
			balloonSkull(m, p + V3(0, 2, 0), p + V3(rng:NextNumber(-2, 2), 7 + b * 1.3, rng:NextNumber(-2, 2)),
				({ BONE, C(190, 160, 230), C(170, 230, 180), C(240, 200, 150) })[(b + k) % 4 + 1], rng)
		end
	end
	-- the carnival's own dead: a row of performer dog graves by the north palisade
	local graves = K.Model(m, "PerformerGraves")
	local names = { "DOGINI", "BISCUIT", "SHADOW", "PIP" }
	for k = 0, 5 do
		local p = V3(92 + k * 6.5, 0, 2176 + (k % 2) * 1.5)
		Y.Tombstone(graves, CF(p) * ANG(0, PI + rng:NextNumber(-.2, .2), 0), ({ 4, 8, 1, 6, 4, 3 })[k + 1], rng, names[k % 4 + 1], { NoTranslate = true })
	end
	-- crates, barrels and hay near the coaster station and the tent
	for k, p in ipairs({ V3(204, 0, 2296), V3(206, 0, 2302), V3(176, 0, 2210), V3(142, 0, 2214), V3(186, 0, 2322), V3(118, 0, 2186), V3(146, 0, 2177) }) do
		local rot = rng:NextNumber(0, PI)
		if k % 3 == 0 then
			K.CylY(m, "Barrel", 2.4, 2, CF(p + V3(0, 1.2, 0)), WOOD, M.Wood, S())
			K.CylY(m, "BarrelHoop", .2, 2.1, CF(p + V3(0, 1.9, 0)), IRON, M.CorrodedMetal)
		else
			K.Part(m, "Crate", V3(2.4, 2.4, 2.4), CF(p + V3(0, 1.2, 0)) * ANG(0, rot, 0), WOOD, M.WoodPlanks, S())
			K.Part(m, "Crate", V3(1.8, 1.8, 1.8), CF(p + V3(0, 3.3, 0)) * ANG(0, rot + .4, 0), WOOD:Lerp(INK, .2), M.WoodPlanks)
		end
	end
	-- fog points + ghost path markers for UnderyardFX
	local fx = K.Model(m, "FXMarkers")
	for k, p in ipairs({ V3(100, .3, 2300), V3(160, .3, 2276), V3(205, .3, 2210), V3(130, .3, 2200), V3(86, .3, 2250), V3(180, .3, 2300), V3(196, .3, 2180) }) do
		K.Marker(fx, "FogPoint", p, { Order = k })
	end
	for k, p in ipairs({ V3(118, 4, 2300), V3(170, 4, 2290), V3(200, 4, 2240), V3(150, 4, 2194), V3(96, 4, 2236) }) do
		K.Marker(fx, "GhostPath_" .. k, p)
	end
	return m
end

------------------------------------------------------------------------------------------------------------------

function F.Build(ctx)
	local L = ctx.Layout
	local root = ctx.Model and ctx.Model("FuneralCarnival") or K.Model(ctx.Root, "FuneralCarnival")
	root:SetAttribute("UyDistrict", "FuneralCarnival")
	root:SetAttribute("Seal", 2)
	buildGround(root, L, Rng(4101), sharedFloor(ctx.Root, "FuneralCarnival"))
	buildPerimeter(root, L, Rng(4102))
	buildMidway(root, L, Rng(4103))
	buildTent(root, L, Rng(4104))
	buildCarousel(root, L, Rng(4105))
	buildFerris(root, L, Rng(4106))
	buildCoaster(root, L, Rng(4107))
	buildRun(root, L, Rng(4108))
	buildProps(root, L, Rng(4109))
	local parts, lights = 0, 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	root:SetAttribute("Parts", parts)
	if ctx.Note then
		ctx.Note(string.format("FuneralCarnival: %d parts, %d lights (budget %d / %d)", parts, lights, F.Budget.Parts, F.Budget.Lights))
	end
	return root
end

return F
