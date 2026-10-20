-- THE UNDERYARD · CROOKED ROW (ServerStorage.UnderyardBuild.CrookedRow, WP-H1, docs/halloween2/DESIGN.md §7, §8.4.5,
-- §22.6). Build-time only: tools/edits/40_underyard.luau runs it through tools/sim.luau (Order 41) and the result is
-- SAVED in the place (editable in Studio). A crooked street of leaning kennel-houses in the district box
-- x -222..-75, z 2168..2330 (UnderyardLayout.Crooked); every gameplay coordinate comes from the layout.
--
-- One Model `CrookedRow` (attribute UyDistrict = "CrookedRow") under ctx.Root:
--   Ground     dead-grass yards, flagstones and puddles on the floor (top y 0); the floor slab + an entrance apron only
--              when WP-G's Ground has not laid the district floor (parts with UyFloor = "CrookedRow") already
--   BentLane   cobbled lane from L.Gates.CrookedRow bending into the court (C.LanePath), kerbs, the "13 CROOKED ROW"
--              street sign
--   DoorCourt  circular cobbles r 26 at L.Crooked.Court (nothing stands within r 20), rune ring, the flagstone apron in
--              front of the door wall
--   DoorWall   the crooked wall along z = L.Crooked.WallZ from x -198 to -98 (~22 tall, solid, 4 thick) with four
--              different doors at L.Crooked.Doors:
--                1 lancet (pointed gothic), 2 round (half-octagon top), 3 coffin (hexagonal), 4 kennel (gabled)
--              per door: leaf hinge Model `Door_i_Leaf` (ModelStreamingMode Atomic, PrimaryPart `DoorHinge` on the
--              hinge line at the opening's -X edge, CLOSED, visual only; attributes DoorIndex = i, OpenAngle = 95,
--              OpenSign = -1: open = Hinge.CFrame * CFrame.Angles(0, rad(OpenAngle) * OpenSign, 0) swings it out toward
--              the court), the shaped opening (filler stones), frame trim, a digit plaque (NoTranslate), an unlit
--              hint lamp `DoorHintLamp` (attribute DoorHint = i, HintColor; Glass, no Light: the door client lights
--              it), a dark vestibule with a void panel behind the leaf and an invisible `DoorBlocker` collider
--              + the giant blinking eye of the wall, gargoyle dogs, banners, sconces, "CHOOSE YOUR DOOR"
--   RareRoom   the sealed treasure room behind the wall at L.Crooked.RareRoom: interior 2 x Half (32 x 20 x 24), solid
--              floor / walls / ceiling, no door (teleport only, spawn L.Crooked.RareRoom.Spawn kept free); three
--              `ChestPedestal`s with chests `RareChest_i` (attribute RareChest = i, lid sub-model `Lid` with PrimaryPart
--              `LidHinge`), gold, gems, a golden dog statue, candles (HwCandle) and warm candle PointLights; a dome
--              peeks over the wall
--   Houses     leaning, stacked kennel-houses (each storey twists a little), stretched gothic windows (Neon, HwLantern,
--              some UyLightAtSeal = 5), blinking eye windows (Model `EyeWindow`, UyBlink = true: Neon `EyePane`,
--              `EyePupil`, `EyelidTop` / `EyelidBottom` with LidDir (-1 down / +1 up) and LidTravel studs: blink by
--              moving the lid LidDir * LidTravel along its own UpVector), crooked chimneys, curled gables, fake doors
--   Laundry    lines between the houses with shrouds, ghost sheets, striped shirts and socks (never over the court)
--   Props      crooked lamps (HwLantern + PointLight), dead trees, dog graves, bone fences, FX markers
--   Perimeter  bone fences on the inner (east / south) edges with the gap exactly where the 22-wide spoke bridge from
--              L.Gates.CrookedRow crosses the district corner, invisible 40-tall colliders on all sides (CanQuery off),
--              backstage colliders closing the space behind the wall
-- Budget: <= 3 500 parts, <= 35 lights (tests/underyard_carnival_row.luau). World text is English, translated by
-- DOGROTS_AutoTranslateUI from Localization.UnderyardCarnivalRow (Exact); digits / names carry NoTranslate.
local K = require(script.Parent.Parent.HalloweenBuild.Kit)
local Y = require(script.Parent.Parent.HalloweenBuild.YardKit)
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi
local S = Y.Solid
local Rng = Y.Rng

-- §7.1 palette + the row's own stone / timber
local GREEN = C(120, 255, 140)
local VIOLET = C(150, 80, 230)
local CANDLE = C(255, 170, 80)
local MOON = C(150, 200, 255)
local BONE = C(230, 222, 200)
local INK = C(16, 12, 26)
local GOLD = C(232, 186, 82)
local DIRT = C(44, 40, 50)
local DIRT_D = C(34, 30, 40)
local FLAG = C(74, 70, 88)
local COBBLE = C(70, 64, 84)
local COBBLE2 = C(58, 54, 72)
local STONE = C(66, 60, 78)
local STONE_D = C(48, 44, 58)
local STONE_L = C(128, 120, 132)
local IRON = C(44, 44, 56)
local TIMBER = C(46, 34, 38)
local DEADGRASS = C(74, 70, 52)
local SHEET = C(222, 228, 236)

local DOOR_OPEN_ANGLE = 95

local CR = {}
CR.Order = 41
CR.Name = "CrookedRow"
CR.Budget = { Parts = 3500, Lights = 35 }

------------------------------------------------------------------------------------------------------------------
-- geometry helpers
------------------------------------------------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z)
end

local function copy(t)
	return t and table.clone(t) or nil
end

-- right-angled wedge with the right angle at `f`, legs f -> a and f -> c (perpendicular), thickness along their normal
local function rightWedge(m, name, f: Vector3, a: Vector3, c: Vector3, thick: number, color, mat, props)
	local u, v = a - f, c - f
	if u.Magnitude < .03 or v.Magnitude < .03 then
		return
	end
	local zw, yw = -u.Unit, v.Unit
	local xw = yw:Cross(zw)
	K.Wedge(m, name, V3(thick, v.Magnitude, u.Magnitude), CFrame.fromMatrix(f + u / 2 + v / 2, xw, yw, zw), color, mat, copy(props))
end

-- any triangle a, b, c (two right wedges split at the foot of the altitude onto the longest edge)
local function tri(m, name, a: Vector3, b: Vector3, c: Vector3, thick: number, color, mat, props)
	local la, lb, lc = (b - c).Magnitude, (c - a).Magnitude, (a - b).Magnitude
	if la >= lb and la >= lc then
		a, b, c = b, c, a
	elseif lb >= la and lb >= lc then
		a, b, c = c, a, b
	end
	-- now a-b is the longest edge
	local ab = b - a
	local t = math.clamp((c - a):Dot(ab) / ab:Dot(ab), 0, 1)
	local f = a + ab * t
	rightWedge(m, name, f, a, c, thick, color, mat, props)
	rightWedge(m, name, f, b, c, thick, color, mat, props)
end

local function slab(m, name, cx, cz, sx, sz, rot, top, thick, color, mat, props)
	return K.Part(m, name, V3(sx, thick, sz), CF(cx, top - thick / 2, cz) * ANG(0, rot, 0), color, mat, props)
end

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

-- distance from q to the segment a..b in the XZ plane
local function segDist(q: Vector3, a: Vector3, b: Vector3): number
	local qa, aa, bb = flat(q), flat(a), flat(b)
	local ab = bb - aa
	local t = math.clamp((qa - aa):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (aa + ab * t - qa).Magnitude
end

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

-- crooked lamp post (three bent segments, curled arm, hanging lantern)
local function crookedLamp(m, base: Vector3, h: number, rng, color, kind: string, light: boolean?)
	local lm = K.Model(m, "CrookedLamp")
	local lean = V3(rng:NextNumber(-.18, .18), 1, rng:NextNumber(-.18, .18)).Unit
	K.CylY(lm, "LampFoot", .5, 1.4, CF(base + V3(0, .25, 0)), IRON, M.CorrodedMetal, S())
	local p1 = base + lean * h * .45
	local lean2 = (lean + V3(rng:NextNumber(-.3, .3), 0, rng:NextNumber(-.3, .3))).Unit
	local p2 = p1 + lean2 * h * .35
	local p3 = p2 + (lean2 + V3(rng:NextNumber(-.4, .4), .2, rng:NextNumber(-.4, .4))).Unit * h * .2
	K.Rod(lm, "LampPost", base, p1, .5, IRON, M.CorrodedMetal, S())
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

------------------------------------------------------------------------------------------------------------------
-- the bent lane (shared with the tests: gate -> court edge centreline)
------------------------------------------------------------------------------------------------------------------

function CR.LanePath(L): { Vector3 }
	local g = L.Gates.CrookedRow
	local f = g.Facing
	local court = L.Crooked.Court
	local entry = court.Centre + V3(26, 0, 19).Unit * (court.Radius + .5) -- the court's south-east rim
	return {
		g.Position + f * 10,
		g.Position + f * 16,
		V3(-96, 0, 2306),
		V3(-112, 0, 2295),
		V3(entry.X, 0, entry.Z),
	}
end

------------------------------------------------------------------------------------------------------------------
-- windows, eye windows, chimneys
------------------------------------------------------------------------------------------------------------------

-- stretched gothic window; W = CFrame on the outer wall surface (-Z out), centre of the rectangular part
local function gothicWindow(m, W: CFrame, w: number, h: number, glow, kind: string?, attrs, trim)
	trim = trim or BONE:Lerp(TIMBER, .55)
	K.Part(m, "WindowCasing", V3(w + .5, h + .4, .16), W * CF(0, 0, -.08), trim, M.Wood)
	local mat = glow and M.Neon or M.Glass
	local col = glow or C(30, 26, 42)
	local a = attrs and table.clone(attrs) or {}
	if glow and kind then
		a.HwLantern = kind
	end
	local glass = K.Part(m, "WindowGlass", V3(w, h, .1), W * CF(0, 0, -.14), col, mat, { Attrs = a })
	Y.GableTri(m, "WindowGlassHead", W * CF(0, h / 2, -.14) * ANG(0, PI / 2, 0), w, w * .85, .1, col, mat)
	K.Bar(m, "WindowHood", (W * CF(-w / 2 - .3, h / 2 - .1, -.2)).Position, (W * CF(0, h / 2 + w * .95, -.2)).Position, .3, .32, trim, M.Wood)
	K.Bar(m, "WindowHood", (W * CF(w / 2 + .3, h / 2 - .1, -.2)).Position, (W * CF(0, h / 2 + w * .95, -.2)).Position, .3, .32, trim, M.Wood)
	K.Part(m, "Mullion", V3(.14, h, .08), W * CF(0, 0, -.21), trim, M.Wood)
	K.Part(m, "WindowSill", V3(w + .9, .22, .5), W * CF(0, -h / 2 - .3, -.25), trim:Lerp(INK, .2), M.Wood)
	return glass
end

-- blinking eye window (Model EyeWindow, UyBlink = true): socket, Neon pane, slit pupil, two lids
local function eyeWindow(m, W: CFrame, w: number, h: number, eye, skin)
	local e = K.Model(m, "EyeWindow")
	e:SetAttribute("UyBlink", true)
	e:SetAttribute("EyeHeight", h)
	K.Ellipsoid(e, "EyeSocket", V3(w + 1, h + 1, .2), W * CF(0, 0, -.06), INK, M.SmoothPlastic)
	K.Ellipsoid(e, "EyePane", V3(w, h, .16), W * CF(0, 0, -.16), eye, M.Neon)
	K.Ellipsoid(e, "EyePupil", V3(w * .2, h * .78, .1), W * CF(0, 0, -.26), INK, M.SmoothPlastic)
	K.Ball(e, "EyeGlint", math.min(w, h) * .14, W * CF(w * .12, h * .2, -.3), BONE, M.Neon)
	local travel = h * .37
	local top = K.Part(e, "EyelidTop", V3(w + .8, h * .5 + .2, .22), W * CF(0, h * .62, -.34), skin, M.SmoothPlastic)
	top:SetAttribute("LidDir", -1)
	top:SetAttribute("LidTravel", travel)
	local bot = K.Part(e, "EyelidBottom", V3(w + .6, h * .4 + .2, .22), W * CF(0, -h * .58, -.34), skin, M.SmoothPlastic)
	bot:SetAttribute("LidDir", 1)
	bot:SetAttribute("LidTravel", travel * .8)
	-- lashes on the upper lid
	for k = -1, 1 do
		K.Part(e, "EyeLash", V3(.14, .7, .12), W * CF(k * w * .3, h * .62 + h * .25 + .3, -.36) * ANG(0, 0, -k * .35), INK, M.SmoothPlastic)
	end
	return e
end

-- crooked chimney rising from `base` (world), three twisted blocks + cap + a curl of iron
local function chimney(m, base: Vector3, h: number, rng, color)
	local cf = CF(base)
	local prev = cf
	local seg = h / 3
	for k = 1, 3 do
		local c = prev * CF(rng:NextNumber(-.35, .35), seg / 2, rng:NextNumber(-.35, .35)) * ANG(rng:NextNumber(-.08, .08), rng:NextNumber(-.3, .3), rng:NextNumber(-.1, .1))
		K.Part(m, "Chimney", V3(1.9 - k * .15, seg + .2, 1.9 - k * .15), c, color:Lerp(INK, k * .08), M.Brick)
		prev = c * CF(0, seg / 2, 0)
	end
	local cap = K.Part(m, "ChimneyCap", V3(2.4, .4, 2.4), prev * CF(0, .2, 0), STONE_D, M.Slate)
	K.Part(m, "ChimneyPot", V3(.9, 1, .9), prev * CF(.3, .9, -.2) * ANG(.15, 0, .2), C(110, 60, 50), M.Brick)
	K.Attach(cap, "SmokePoint", CF(.3, 1.6, -.2))
	K.Attach(cap, "CrowPerch", CF(-.7, .4, .5))
	return prev
end

------------------------------------------------------------------------------------------------------------------
-- leaning kennel houses
------------------------------------------------------------------------------------------------------------------

-- spec: Pos (front centre, ground), Face (unit), W, D, Storeys, Wall, Trim, Roof, Eye, Glow ({colour, kind}), Seed,
-- Number, Lit (PointLight in one window), Lean (roll), Twist
local function buildHouse(parent, spec)
	local rng = Rng(spec.Seed)
	local hm = K.Model(parent, "CrookedHouse")
	hm:SetAttribute("HouseNumber", spec.Number)
	local H = K.Look(spec.Pos, spec.Pos + spec.Face) -- -Z = the street
	local W, D, NS = spec.W, spec.D, spec.Storeys
	local HS = 7
	-- plinth (not leaning)
	K.Part(hm, "HousePlinth", V3(W + 1.2, 1.2, D + 1.2), H * CF(0, .3, D / 2), STONE_D, M.Slate, S())
	K.Part(hm, "HouseStep", V3(3.6, .5, 1.6), H * CF(0, .25, -.9), STONE_L:Lerp(STONE_D, .4), M.Slate, S())
	-- storeys chained: each sits on the one below with a small offset, twist and roll (the stop-motion bend)
	local base = H * CF(0, .9, D / 2) * ANG(0, 0, spec.Lean or 0)
	local frames = {}
	for s = 0, NS - 1 do
		local w = W + s * .9
		local d = D + s * .4
		local body = base * CF(0, HS / 2, 0)
		K.Part(hm, "HouseStorey", V3(w, HS, d), body, spec.Wall:Lerp(INK, s * .06), s == 0 and M.WoodPlanks or M.Plaster, S())
		-- half-timber: corner posts, floor beam, one diagonal brace on the front
		local front = body * CF(0, 0, -d / 2)
		for _, sx in ipairs({ -1, 1 }) do
			K.Part(hm, "Timber", V3(.5, HS, .3), front * CF(sx * (w / 2 - .25), 0, -.12), spec.Trim, M.Wood)
		end
		K.Part(hm, "Timber", V3(w + .3, .5, .35), front * CF(0, HS / 2 - .25, -.14), spec.Trim, M.Wood)
		if s > 0 then
			K.Bar(hm, "TimberBrace", (front * CF(-w / 2 + .4, -HS / 2 + .4, -.13)).Position, (front * CF(-w / 2 + 2.6, HS / 2 - .6, -.13)).Position, .35, .3,
				spec.Trim, M.Wood)
		end
		table.insert(frames, { Body = body, Front = front, W = w, D = d })
		base = base * CF(rng:NextNumber(-.5, .5), HS, -.35) * ANG(0, rng:NextNumber(-.06, .06) + (spec.Twist or 0), rng:NextNumber(-.035, .035))
	end
	-- facade: ground floor = kennel door + a gothic window; upper floors = gothic windows / an eye
	local glow, kind = spec.Glow[1], spec.Glow[2]
	local g0 = frames[1]
	local doorX = (spec.DoorSide or -1) * g0.W * .22
	local Dcf = g0.Front * CF(doorX, -HS / 2 + 2.6, 0)
	K.Part(hm, "HouseDoor", V3(2.6, 4.4, .2), Dcf * CF(0, -.4, -.1), TIMBER:Lerp(INK, .3), M.WoodPlanks)
	K.CylZ(hm, "HouseDoorArch", .2, 2.6, Dcf * CF(0, 1.8, -.1), TIMBER:Lerp(INK, .3), M.WoodPlanks)
	K.Bar(hm, "DoorFrame", (Dcf * CF(-1.55, -2.6, -.18)).Position, (Dcf * CF(-1.55, 1.8, -.18)).Position, .4, .35, spec.Trim, M.Wood)
	K.Bar(hm, "DoorFrame", (Dcf * CF(1.55, -2.6, -.18)).Position, (Dcf * CF(1.55, 1.8, -.18)).Position, .4, .35, spec.Trim, M.Wood)
	Y.Skull(hm, Dcf * CF(0, 1.05, -.42), .45, nil, BONE)
	local plate = K.Part(hm, "HouseNumberPlate", V3(1.2, 1.1, .12), Dcf * CF(0, 3.4, -.2), GOLD:Lerp(INK, .25), M.Metal)
	digits(plate, N.Front, tostring(spec.Number), INK, { PixelsPerStud = 40, Stroke = false, W = .8, H = .86 })
	local lit = nil
	local lightWindow = rng:NextInteger(1, 2)
	local gw = g0.Front * CF(-doorX * 1.1, .4, 0)
	gothicWindow(hm, gw, 1.6, 3.4, glow, kind, nil, spec.Trim)
	-- shutters (one hangs by a single hinge) and a little porch roof over the door
	K.Part(hm, "Shutter", V3(1, 3.8, .14), gw * CF(-1.45, 0, -.2), spec.Roof:Lerp(spec.Wall, .5), M.WoodPlanks)
	K.Part(hm, "Shutter", V3(1, 3.8, .14), gw * CF(1.7, -.7, -.35) * ANG(0, -.3, -.35), spec.Roof:Lerp(spec.Wall, .5), M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		K.Wedge(hm, "PorchRoof", V3(2.1, .9, 1.8), Dcf * CF(sx * 1.05, 2.7, -.9) * ANG(0, -sx * PI / 2, 0), spec.Roof, M.Slate)
		K.Bar(hm, "PorchBracket", (Dcf * CF(sx * 1.8, 1.3, -.1)).Position, (Dcf * CF(sx * 1.8, 2.3, -1.6)).Position, .2, .2, spec.Trim, M.Wood)
	end
	for s = 2, NS do
		local fr = frames[s]
		local isTop = s == NS
		if isTop and spec.EyeTop then
			eyeWindow(hm, fr.Front * CF(0, .2, 0), 3.4, 2.2, spec.Eye, spec.Wall)
		else
			local n = fr.W > 13 and 2 or 1
			for k = 1, n do
				local x = n == 1 and 0 or (k == 1 and -fr.W * .24 or fr.W * .24)
				local attrs = nil
				if not (k == lightWindow or n == 1) then
					attrs = { UyLightAtSeal = 5 }
				end
				local gl = gothicWindow(hm, fr.Front * CF(x, .1, 0), 1.4, 3.8, glow, kind, attrs, spec.Trim)
				if not lit and spec.Lit and attrs == nil then
					lit = gl
				end
			end
			if not isTop and s == 2 and spec.EyeMid then
				-- an eye squeezed between the windows of the first floor
				eyeWindow(hm, fr.Front * CF(0, .6, 0), 2.2, 1.5, spec.Eye, spec.Wall)
			end
		end
	end
	if lit then
		K.Light(lit, glow, 16, .8)
		lit:SetAttribute("HwBaseBrightness", .8)
	end
	-- steep crooked gable roof (ridge front-to-back), curled ridge tip, gable triangles, shingle strips
	local top = frames[NS]
	local Rcf = top.Body * CF(0, HS / 2, 0)
	local wt, dt = top.W, top.D
	local rise = spec.Rise or (wt * .78)
	local oh = .9
	local ridgeF = (Rcf * CF(0, rise, -dt / 2 - oh)).Position
	local ridgeB = (Rcf * CF(.4, rise - .6, dt / 2 + oh)).Position
	for _, sx in ipairs({ -1, 1 }) do
		local eF = (Rcf * CF(sx * (wt / 2 + oh), -.3, -dt / 2 - oh)).Position
		local eB = (Rcf * CF(sx * (wt / 2 + oh), -.3, dt / 2 + oh)).Position
		-- each roof plane: two triangles (front + back) so the ridge may sag / skew
		tri(hm, "HouseRoof", eF, ridgeF, ridgeB, .5, spec.Roof, M.Slate, S())
		tri(hm, "HouseRoof", eF, eB, ridgeB, .5, spec.Roof, M.Slate, S())
		for k = 1, 2 do
			local t = k / 3
			K.Bar(hm, "Shingles", eF:Lerp(ridgeF, t) + V3(0, .25, 0), eB:Lerp(ridgeB, t) + V3(0, .25, 0), .6, .2, spec.Roof:Lerp(INK, .25), M.Slate)
		end
	end
	K.Bar(hm, "RidgeCap", ridgeF + V3(0, .25, 0), ridgeB + V3(0, .25, 0), .7, .5, spec.Roof:Lerp(INK, .4), M.Slate)
	-- gable triangle on the front, with the attic eye or a round vent
	tri(hm, "GableWall", (Rcf * CF(-wt / 2, 0, -dt / 2)).Position, (Rcf * CF(wt / 2, 0, -dt / 2)).Position, (Rcf * CF(0, rise - .2, -dt / 2)).Position, .4,
		spec.Wall:Lerp(BONE, .08), M.Plaster)
	tri(hm, "GableWall", (Rcf * CF(-wt / 2, 0, dt / 2)).Position, (Rcf * CF(wt / 2, 0, dt / 2)).Position, (Rcf * CF(.3, rise - .8, dt / 2)).Position, .4,
		spec.Wall:Lerp(BONE, .08), M.Plaster)
	if spec.GableEye then
		eyeWindow(hm, Rcf * CF(0, rise * .38, -dt / 2 - .2), 2.6, 1.7, spec.Eye, spec.Wall:Lerp(BONE, .08))
	else
		K.CylZ(hm, "GableVent", .2, 1.8, Rcf * CF(0, rise * .4, -dt / 2 - .25), glow, M.Neon, { Attrs = { HwLantern = kind } })
	end
	-- the ridge curls up over the street like a cat's tail
	local curl = ridgeF + V3(0, .3, 0)
	local dirF = (Rcf.LookVector)
	local pts = { curl, curl + dirF * 1.2 + V3(0, .9, 0), curl + dirF * 1.6 + V3(0, 2.2, 0), curl + dirF * .9 + V3(0, 3, 0), curl + V3(0, 2.6, 0) }
	for k = 1, #pts - 1 do
		K.Rod(hm, "RidgeCurl", pts[k], pts[k + 1], .35 - k * .04, IRON, M.CorrodedMetal)
	end
	K.Ball(hm, "RidgeCurlTip", .45, CF(pts[#pts]), spec.Eye, M.Neon)
	-- chimney on the roof slope
	local chX = (spec.ChimneySide or 1) * wt * .26
	local chBase = (Rcf * CF(chX, rise * (1 - math.abs(chX) / (wt / 2 + oh)) - 1.2, dt * .18)).Position
	chimney(hm, chBase, spec.Chimney or 6, rng, C(96, 58, 54))
	-- bone-picket fence across the front yard (2 short runs either side of the path)
	if spec.Fence then
		for _, sx in ipairs({ -1, 1 }) do
			local a = (H * CF(sx * 2.4, 0, -2.6)).Position
			local b = (H * CF(sx * (W / 2 + .4), 0, -2.6)).Position
			local len = (b - a).Magnitude
			local dir = (b - a).Unit
			K.Bar(hm, "BoneRail", a + V3(0, 1.1, 0), b + V3(0, 1.1, 0), .18, .18, BONE:Lerp(INK, .25), M.SmoothPlastic)
			for k = 0, math.floor(len / 1.3) do
				local p = a + dir * (k * 1.3)
				K.Part(hm, "BonePicket", V3(.3, 1.7, .3), CF(p + V3(0, .85, 0)) * ANG(rng:NextNumber(-.08, .08), 0, rng:NextNumber(-.1, .1)), BONE, M.SmoothPlastic)
			end
		end
	end
	K.Attach(hm:FindFirstChild("RidgeCap") :: BasePart, "CrowPerch", CF(0, .5, 0))
	-- line points for the laundry (front eave corners)
	local eaveL = (top.Front * CF(-wt / 2 + .4, HS / 2 - .8, -.35)).Position
	local eaveR = (top.Front * CF(wt / 2 - .4, HS / 2 - .8, -.35)).Position
	return hm, { eaveL, eaveR }
end

------------------------------------------------------------------------------------------------------------------
-- the DOOR WALL
------------------------------------------------------------------------------------------------------------------

-- door outlines in door-local (x, y) coords (x across, y up, y = 0 on the ground): convex leaf pieces and the filler
-- triangles that shape the rectangular hole W x H
local function doorSpecs()
	local function v(x, y)
		return { x, y }
	end
	return {
		{ -- 1: tall lancet, leaning gothic
			Style = "Lancet", W = 5, H = 12, Wood = C(54, 40, 60), Glow = VIOLET, Stone = C(84, 74, 104),
			Outline = { v(-2.5, 0), v(2.5, 0), v(2.5, 8.5), v(0, 12), v(-2.5, 8.5) },
			Pieces = { { "Rect", -2.5, 0, 2.5, 8.5 }, { "Tri", v(-2.5, 8.5), v(2.5, 8.5), v(0, 12) } },
			Fillers = { { v(-2.5, 8.5), v(-2.5, 12), v(0, 12) }, { v(2.5, 8.5), v(2.5, 12), v(0, 12) } },
		},
		{ -- 2: short, wide, round-topped (half octagon) with a giant keyhole
			Style = "Round", W = 6.6, H = 9.8, Wood = C(70, 46, 40), Glow = CANDLE, Stone = C(98, 66, 56),
			Outline = { v(-3.3, 0), v(3.3, 0), v(3.3, 6.5), v(2.33, 8.83), v(0, 9.8), v(-2.33, 8.83), v(-3.3, 6.5) },
			Pieces = {
				{ "Rect", -3.3, 0, 3.3, 6.5 }, { "Rect", -2.33, 6.5, 2.33, 8.83 },
				{ "Tri", v(-3.3, 6.5), v(-2.33, 6.5), v(-2.33, 8.83) }, { "Tri", v(3.3, 6.5), v(2.33, 6.5), v(2.33, 8.83) },
				{ "Tri", v(-2.33, 8.83), v(2.33, 8.83), v(0, 9.8) },
			},
			Fillers = {
				{ v(-3.3, 6.5), v(-3.3, 9.8), v(-2.33, 8.83) }, { v(-3.3, 9.8), v(0, 9.8), v(-2.33, 8.83) },
				{ v(3.3, 6.5), v(3.3, 9.8), v(2.33, 8.83) }, { v(3.3, 9.8), v(0, 9.8), v(2.33, 8.83) },
			},
		},
		{ -- 3: coffin door (hexagon: narrow foot, wide shoulders, narrow head)
			Style = "Coffin", W = 5.2, H = 10.4, Wood = C(30, 26, 36), Glow = GREEN, Stone = C(40, 36, 48),
			Outline = { v(-1.7, 0), v(1.7, 0), v(2.6, 7.4), v(1.9, 10.4), v(-1.9, 10.4), v(-2.6, 7.4) },
			Pieces = {
				{ "Trap", v(-1.7, 0), v(1.7, 0), v(-2.6, 7.4), v(2.6, 7.4) },
				{ "Trap", v(-2.6, 7.4), v(2.6, 7.4), v(-1.9, 10.4), v(1.9, 10.4) },
			},
			Fillers = {
				{ v(-2.6, 0), v(-1.7, 0), v(-2.6, 7.4) }, { v(2.6, 0), v(1.7, 0), v(2.6, 7.4) },
				{ v(-2.6, 7.4), v(-2.6, 10.4), v(-1.9, 10.4) }, { v(2.6, 7.4), v(2.6, 10.4), v(1.9, 10.4) },
			},
		},
		{ -- 4: kennel door (rectangle + steep gable)
			Style = "Kennel", W = 5.6, H = 9.2, Wood = C(96, 52, 40), Glow = MOON, Stone = C(70, 78, 92),
			Outline = { v(-2.8, 0), v(2.8, 0), v(2.8, 6.2), v(0, 9.2), v(-2.8, 6.2) },
			Pieces = { { "Rect", -2.8, 0, 2.8, 6.2 }, { "Tri", v(-2.8, 6.2), v(2.8, 6.2), v(0, 9.2) } },
			Fillers = { { v(-2.8, 6.2), v(-2.8, 9.2), v(0, 9.2) }, { v(2.8, 6.2), v(2.8, 9.2), v(0, 9.2) } },
		},
	}
end

-- dog gargoyle crouching on a ledge (faces -Z of cf)
local function gargoyle(m, cf: CFrame, eye)
	local g = STONE_L:Lerp(STONE, .5)
	K.Part(m, "GargoyleBody", V3(1.4, 1.3, 2.2), cf * CF(0, .65, .1), g, M.Slate)
	K.Part(m, "GargoyleHead", V3(1.2, 1.1, 1.2), cf * CF(0, 1.35, -.9), g, M.Slate)
	K.Part(m, "GargoyleSnout", V3(.7, .55, .8), cf * CF(0, 1.15, -1.7), g, M.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		K.Wedge(m, "GargoyleEar", V3(.2, .8, .5), cf * CF(sx * .45, 2.1, -.8), g:Lerp(INK, .2), M.Slate)
		K.Wedge(m, "GargoyleWing", V3(.15, 1.5, 1.6), cf * CF(sx * .8, 1.5, .5) * ANG(0, 0, -sx * .5), g:Lerp(INK, .25), M.Slate)
		K.Ball(m, "GargoyleEye", .25, cf * CF(sx * .28, 1.5, -1.5), eye, M.Neon)
	end
end

local function buildDoorWall(root, L, rng)
	local wall = K.Model(root, "DoorWall")
	local Z = L.Crooked.WallZ
	local T = 4 -- thickness (z Z-4 .. Z)
	local zc = Z - T / 2
	local specs = doorSpecs()
	local doors = L.Crooked.Doors
	local BAY = 7 -- half width of a door bay
	-- wall sections between the bays (x0, x1, height, roll); the ends reach the corner houses
	local sections = {}
	local edges = { -201.5 }
	for _, d in ipairs(doors) do
		table.insert(edges, d.X - BAY)
		table.insert(edges, d.X + BAY)
	end
	table.insert(edges, -94.5)
	local heights = { 19, 17.5, 20, 18, 19.5 }
	for k = 1, #edges, 2 do
		table.insert(sections, { edges[k], edges[k + 1], heights[(k + 1) / 2], ((k + 1) / 2 % 2 == 0) and -.025 or .02 })
	end
	for si, s in ipairs(sections) do
		local x0, x1, h, roll = s[1], s[2], s[3], s[4]
		local cx = (x0 + x1) / 2
		local w = x1 - x0
		K.Part(wall, "WallSection", V3(w + .2, h, T), CF(cx, h / 2, zc), STONE, M.Slate, S())
		-- crooked coping: tilted cap + uneven merlons
		local cap = CF(cx, h + .35, zc) * ANG(0, 0, roll)
		K.Part(wall, "WallCoping", V3(w + .8, .7, T + .8), cap, STONE_D, M.Slate)
		local nm = math.max(1, math.floor(w / 3.2))
		for k = 1, nm do
			local x = -w / 2 + (k - .5) * w / nm
			local mh = rng:NextNumber(1.2, 2.6)
			K.Part(wall, "WallMerlon", V3(w / nm * .55, mh, T * .8), cap * CF(x, .35 + mh / 2, 0) * ANG(0, 0, rng:NextNumber(-.12, .12)), STONE:Lerp(INK, .1), M.Slate)
		end
		-- protruding stones + a string course for texture
		K.Part(wall, "StringCourse", V3(w, .5, .5), CF(cx, h * .62, Z + .2), STONE_L:Lerp(STONE, .55), M.Slate)
		for _ = 1, 3 do
			K.Part(wall, "WallStone", V3(rng:NextNumber(1.4, 2.6), rng:NextNumber(.8, 1.4), .35),
				CF(cx + rng:NextNumber(-w / 2 + 1.2, w / 2 - 1.2), rng:NextNumber(1, h - 2), Z + .1) * ANG(0, 0, rng:NextNumber(-.1, .1)),
				STONE:Lerp(STONE_L, rng:NextNumber(.1, .35)), M.Slate)
		end
		-- leaning buttress on the court side at each section end
		if si > 1 and si < #sections then
			for _, bx in ipairs({ x0 + .9, x1 - .9 }) do
				K.Wedge(wall, "Buttress", V3(1.6, h * .7, 2.6), CF(bx, h * .35, Z + 1.3) * ANG(0, PI, 0), STONE_D, M.Slate, S())
			end
		end
	end
	-- the giant eye of the wall (middle section) + "CHOOSE YOUR DOOR"
	local mid = sections[3]
	local mx = (mid[1] + mid[2]) / 2
	local bigEye = eyeWindow(wall, CF(mx, 13.2, Z) * ANG(0, PI, 0), 5.6, 3.4, GREEN, STONE)
	K.Light(bigEye:FindFirstChild("EyePane") :: BasePart, GREEN, 26, .9)
	local banner = K.Part(wall, "ChooseBanner", V3(7.4, 1.6, .25), CF(mx, 8.4, Z + .3), C(70, 24, 60), M.Fabric)
	sign(banner, N.Back, "CHOOSE YOUR DOOR", BONE, { PixelsPerStud = 26, H = .78, StrokeColor = INK })
	-- door bays
	local hintColors = { GOLD, GOLD, GOLD, GOLD }
	for i, dp in ipairs(doors) do
		local sp = specs[i]
		local bay = K.Model(wall, "DoorBay_" .. i)
		local x = dp.X
		local function at(lx: number, ly: number, lz: number): Vector3
			return V3(x + lx, ly, Z + lz) -- door-local: x across, y up, z out of the wall (+Z = court)
		end
		local w, h = sp.W, sp.H
		local facadeH = ({ 27, 22, 25, 23.5 })[i]
		-- piers either side of the opening + the block above it
		local pierW = BAY - w / 2
		for _, sx in ipairs({ -1, 1 }) do
			local px = sx * (w / 2 + pierW / 2)
			K.Part(bay, "BayPier", V3(pierW + .1, facadeH - 3, T), CF(x + px, (facadeH - 3) / 2, zc), sp.Stone, M.Slate, S())
			-- bone-white quoins up the outer edge of each pier
			for q = 0, 3 do
				local qy = 1.4 + q * (facadeH - 5) / 4
				K.Part(bay, "Quoin", V3(q % 2 == 0 and 1.6 or 1.1, 1.2, .4), CF(x + sx * (BAY - .7 - (q % 2 == 0 and 0 or .25)), qy, Z + .1) * ANG(0, 0, (q - 1.5) * .03),
					BONE:Lerp(sp.Stone, .45), M.Slate)
			end
		end
		K.Part(bay, "BayLintel", V3(w + .2, facadeH - 3 - h, T), CF(x, h + (facadeH - 3 - h) / 2, zc), sp.Stone, M.Slate, S())
		-- filler stones shape the opening; trim follows the outline
		for _, f in ipairs(sp.Fillers) do
			tri(bay, "DoorFiller", at(f[1][1], f[1][2], -.5), at(f[2][1], f[2][2], -.5), at(f[3][1], f[3][2], -.5), 1, sp.Stone, M.Slate, S())
		end
		local ol = sp.Outline
		for k = 2, #ol do
			local a, b = ol[k], ol[k % #ol + 1]
			if not (k == #ol and b[2] == 0) then
				local da = V3(a[1], a[2], 0)
				local db = V3(b[1], b[2], 0)
				local out = (da + db) / 2
				local n = V3(out.X, out.Y - h / 2, 0).Unit * .45
				K.Bar(bay, "DoorTrim", at(a[1] + n.X, a[2] + n.Y, .3), at(b[1] + n.X, b[2] + n.Y, .3), .7, .6, BONE:Lerp(STONE_L, .5), M.Slate)
			end
		end
		K.Bar(bay, "DoorTrim", at(ol[1][1] - .45, 0, .3), at(ol[#ol][1] - .45, ol[#ol][2], .3), .7, .6, BONE:Lerp(STONE_L, .5), M.Slate)
		K.Part(bay, "DoorStep", V3(w + 2, .35, 1.6), CF(x, .175, Z + .8), STONE_L:Lerp(STONE_D, .4), M.Slate, S())
		-- the facade above the door: a different crooked crown per door
		local fz = Z + .35
		if sp.Style == "Lancet" then
			tri(bay, "BayGable", at(-BAY, facadeH - 3, .35), at(BAY, facadeH - 3, .35), at(-1.2, facadeH + 5, .35), 1.2, sp.Stone:Lerp(INK, .2), M.Slate)
			K.CylZ(bay, "RoseWindow", .3, 3.2, CF(x - .3, facadeH - .2, fz + .3), VIOLET, M.Neon, { Attrs = { HwLantern = "Purple" } })
			for k = 0, 3 do
				local a = k / 4 * PI
				K.Part(bay, "RoseTracery", V3(3.3, .22, .2), CF(x - .3, facadeH - .2, fz + .5) * ANG(0, 0, a), STONE_L, M.Slate)
			end
			K.Part(bay, "BaySpire", V3(.8, 4, .8), CF(x - 1.2, facadeH + 6.4, Z - 1.6) * ANG(0, 0, .12), STONE_D, M.Slate)
		elseif sp.Style == "Round" then
			K.Part(bay, "BayTower", V3(BAY * 2 - 1.6, 4, T + .6), CF(x, facadeH - 1, zc + .3) * ANG(0, 0, -.04), sp.Stone, M.Brick)
			K.Ellipsoid(bay, "BayDome", V3(BAY * 2 - 1, 6, T + 2), CF(x + .3, facadeH + 1, zc + .3) * ANG(0, 0, -.08), C(60, 40, 80), M.Slate)
			K.Rod(bay, "DomeSpike", V3(x + .5, facadeH + 3.6, zc + .3), V3(x + 1.4, facadeH + 7, zc + .3), .4, IRON, M.CorrodedMetal)
			K.Ball(bay, "DomeOrb", .9, CF(x + 1.45, facadeH + 7.2, zc + .3), CANDLE, M.Neon)
		elseif sp.Style == "Coffin" then
			for k = 0, 3 do
				local sw = BAY * 2 - k * 3.2
				K.Part(bay, "CrowStep", V3(sw, 1.6, T + .4), CF(x + k * .25, facadeH - 3 + .8 + k * 1.6, zc + .2), k % 2 == 0 and sp.Stone or BONE:Lerp(sp.Stone, .35), M.Slate)
			end
			Y.Skull(bay, CF(x + 1, facadeH + 4.3, Z + .2) * ANG(0, PI, 0), 1.6, GREEN, BONE)
		else -- Kennel
			tri(bay, "BayGable", at(-BAY - .6, facadeH - 3, .5), at(BAY + .6, facadeH - 3, .5), at(.6, facadeH + 3.2, .5), 1, C(96, 52, 40), M.Slate)
			for k = 1, 3 do
				local t = k / 4
				K.Bar(bay, "KennelShingle", at(-BAY - .6 + (BAY + 1.2) * t, facadeH - 3 + 6.2 * t, 1.05), at(BAY + .6 - (BAY - .0) * t, facadeH - 3 + 6.2 * t, 1.05),
					.4, .3, C(70, 36, 30), M.Slate)
			end
			K.Bone(bay, CF(x + .6, facadeH + 1, Z + 1.2), 3.6, BONE)
		end
		-- the leaf: hinge model, closed, visual only
		local leaf = K.Model(bay, "Door_" .. i .. "_Leaf")
		leaf.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		leaf:SetAttribute("DoorIndex", i)
		leaf:SetAttribute("DoorStyle", sp.Style)
		leaf:SetAttribute("OpenAngle", DOOR_OPEN_ANGLE)
		leaf:SetAttribute("OpenSign", -1)
		local LZ = -.32 -- leaf centre plane (front face at -.17)
		local hinge = K.Part(leaf, "DoorHinge", V3(.2, h, .2), CF(x - w / 2, h / 2, Z - .17), IRON, M.CorrodedMetal, { Transparency = 1 })
		leaf.PrimaryPart = hinge
		for _, pc in ipairs(sp.Pieces) do
			if pc[1] == "Rect" then
				local x0, y0, x1, y1 = pc[2], pc[3], pc[4], pc[5]
				K.Part(leaf, "DoorSlab", V3(x1 - x0 - .06, y1 - y0, .3), CF(x + (x0 + x1) / 2, (y0 + y1) / 2, Z + LZ), sp.Wood, M.WoodPlanks)
			elseif pc[1] == "Tri" then
				tri(leaf, "DoorSlab", at(pc[2][1], pc[2][2], LZ), at(pc[3][1], pc[3][2], LZ), at(pc[4][1], pc[4][2], LZ), .3, sp.Wood, M.WoodPlanks)
			else -- Trap: two triangles
				tri(leaf, "DoorSlab", at(pc[2][1], pc[2][2], LZ), at(pc[3][1], pc[3][2], LZ), at(pc[5][1], pc[5][2], LZ), .3, sp.Wood, M.WoodPlanks)
				tri(leaf, "DoorSlab", at(pc[2][1], pc[2][2], LZ), at(pc[4][1], pc[4][2], LZ), at(pc[5][1], pc[5][2], LZ), .3, sp.Wood, M.WoodPlanks)
			end
		end
		-- leaf decoration per style
		local face = Z - .1
		for _, yy in ipairs({ h * .18, h * .55 }) do
			K.Part(leaf, "DoorStrap", V3(w * .55, .28, .08), CF(x - w * .2, yy, face), IRON, M.CorrodedMetal)
			K.Ball(leaf, "StrapNail", .2, CF(x - w * .45, yy, face + .02), IRON, M.CorrodedMetal)
		end
		if sp.Style == "Lancet" then
			K.Part(leaf, "DoorPanel", V3(w * .5, h * .35, .08), CF(x, h * .4, face), sp.Wood:Lerp(INK, .35), M.Wood)
			K.Ball(leaf, "DoorKnob", .4, CF(x + w * .32, h * .38, face + .1), GOLD, M.Metal)
			K.Part(leaf, "DoorSlit", V3(.25, 1.4, .06), CF(x, h * .72, face + .02), VIOLET, M.Neon)
		elseif sp.Style == "Round" then
			K.Ellipsoid(leaf, "Keyhole", V3(1.2, 1.2, .1), CF(x, h * .5, face + .02), INK, M.SmoothPlastic)
			K.Wedge(leaf, "KeyholeSlot", V3(.08, 1.6, 1.1), CF(x, h * .5 - 1, face + .02) * ANG(0, PI / 2, 0), INK, M.SmoothPlastic)
			K.CylZ(leaf, "KnockerRing", .1, 1.2, CF(x + w * .3, h * .45, face + .06), GOLD, M.Metal)
		elseif sp.Style == "Coffin" then
			K.Part(leaf, "CoffinCross", V3(.35, h * .45, .08), CF(x, h * .5, face + .02), GREEN, M.Neon)
			K.Part(leaf, "CoffinCross", V3(w * .45, .35, .08), CF(x, h * .62, face + .02), GREEN, M.Neon)
			K.Ball(leaf, "DoorKnob", .35, CF(x + w * .28, h * .4, face + .1), BONE, M.SmoothPlastic)
		else
			K.Ellipsoid(leaf, "PawPad", V3(1.2, 1, .1), CF(x, h * .42, face + .02), BONE, M.SmoothPlastic)
			for t = -1, 1 do
				K.Ellipsoid(leaf, "PawToe", V3(.45, .5, .1), CF(x + t * .55, h * .42 + .85 - math.abs(t) * .2, face + .02), BONE, M.SmoothPlastic)
			end
			K.CylX(leaf, "DogFlap", .1, 1.6, CF(x, .9, face) * ANG(0, PI / 2, 0), sp.Wood:Lerp(INK, .4), M.Wood)
		end
		for _, p in ipairs(leaf:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.CanQuery = false
				p.CastShadow = false
			end
		end
		-- doorway blocker + the dark vestibule behind it (a void panel glows faintly)
		collider(bay, V3(w, h, .4), CF(x, h / 2, Z - .6))
		local vb = K.Model(bay, "Vestibule")
		local zb = Z - T - 3.5
		K.Part(vb, "VestibuleBack", V3(w + 2, h + 1.5, .5), CF(x, (h + 1.5) / 2, zb), INK, M.Slate, S())
		K.Part(vb, "DoorVoid", V3(w - .4, h - 1, .1), CF(x, h / 2, zb + .35), sp.Glow:Lerp(INK, .7), M.Neon, { Transparency = .15 })
		for _, sx in ipairs({ -1, 1 }) do
			K.Part(vb, "VestibuleSide", V3(.5, h + 1.5, 3.6), CF(x + sx * (w / 2 + .5), (h + 1.5) / 2, zb + 1.9), INK, M.Slate, S())
		end
		K.Part(vb, "VestibuleCeiling", V3(w + 2, .5, 3.6), CF(x, h + 1.25, zb + 1.9), INK, M.Slate, S())
		K.Part(vb, "VestibuleFloor", V3(w + 2, .2, T + 3.6), CF(x, .02, Z - (T + 3.6) / 2), INK, M.Slate)
		-- numeral plaque (digits) + the unlit hint lamp above it
		local plaqueY = h + 1.2
		K.Part(bay, "DoorNumeral", V3(1.8, 1.8, .25), CF(x, plaqueY, Z + .55) * ANG(0, 0, PI / 4), BONE:Lerp(GOLD, .3), M.Metal)
		local pf = K.Part(bay, "DoorNumeralFace", V3(1.5, 1.5, .1), CF(x, plaqueY, Z + .7), INK, M.SmoothPlastic)
		digits(pf, N.Back, tostring(i), BONE, { PixelsPerStud = 40, W = .8, H = .8, StrokeColor = sp.Glow })
		local lampY = plaqueY + 2.6
		K.Part(bay, "HintBracket", V3(.2, .2, 1.4), CF(x, lampY + 1.2, Z + .7), IRON, M.CorrodedMetal)
		K.Part(bay, "HintCap", V3(1.1, .3, 1.1), CF(x, lampY + .95, Z + 1.3), IRON, M.CorrodedMetal)
		K.Part(bay, "DoorHintLamp", V3(.8, 1.3, .8), CF(x, lampY, Z + 1.3), C(46, 40, 56), M.Glass,
			{ Transparency = .15, Attrs = { DoorHint = i, HintColor = hintColors[i] } })
		K.Part(bay, "HintBase", V3(1, .2, 1), CF(x, lampY - .75, Z + 1.3), IRON, M.CorrodedMetal)
		-- candles on the step
		K.Candles(bay, CF(x - w / 2 - 1.2, .35, Z + .8), 3, rng, { Light = false, Spread = .5 })
	end
	-- gargoyle dogs on the section tops, banners, two sconces with light
	for si, s in ipairs(sections) do
		local cx = (s[1] + s[2]) / 2
		if si == 2 or si == 4 then
			gargoyle(wall, CF(cx, s[3] + .7, Z) * ANG(0, PI, 0), si == 2 and VIOLET or GREEN)
			K.Part(wall, "WallBanner", V3(3, 7, .12), CF(cx, s[3] - 5, Z + .25), C(60, 22, 70), M.Fabric)
			Y.GableTri(wall, "WallBannerTail", CF(cx, s[3] - 8.5, Z + .25) * ANG(PI, PI / 2, 0), 3, 1.4, .12, C(60, 22, 70), M.Fabric)
			K.Ball(wall, "BannerEye", 1.2, CF(cx, s[3] - 4, Z + .35), BONE, M.SmoothPlastic)
			lantern(wall, CF(cx, 6.2, Z + 1.3), CANDLE, "Orange", true, 18)
			K.Part(wall, "SconceArm", V3(.2, .2, 1.4), CF(cx, 7.4, Z + .7), IRON, M.CorrodedMetal)
		end
	end
	return wall
end

------------------------------------------------------------------------------------------------------------------
-- the sealed RARE ROOM
------------------------------------------------------------------------------------------------------------------

local function buildRareRoom(root, L, rng)
	local rr = L.Crooked.RareRoom
	local room = K.Model(root, "RareRoom")
	room:SetAttribute("Sealed", true)
	local c, h = rr.Centre, rr.Half
	local x0, x1, z0, z1, top = c.X - h.X, c.X + h.X, c.Z - h.Z, c.Z + h.Z, 2 * h.Y
	local T = 1.6
	-- shell: floor, ceiling, four walls (overlapping at the corners)
	K.Part(room, "RoomFloor", V3(2 * h.X + 2 * T, 1, 2 * h.Z + 2 * T), CF(c.X, -.48, c.Z), C(70, 56, 40), M.Slate, S())
	K.Part(room, "RoomCeiling", V3(2 * h.X + 2 * T, T, 2 * h.Z + 2 * T), CF(c.X, top + T / 2, c.Z), STONE_D, M.Slate, S())
	K.Part(room, "RoomWall", V3(2 * h.X + 2 * T, top + 1, T), CF(c.X, top / 2, z0 - T / 2), STONE_D, M.Slate, S())
	K.Part(room, "RoomWall", V3(2 * h.X + 2 * T, top + 1, T), CF(c.X, top / 2, z1 + T / 2), STONE_D, M.Slate, S())
	K.Part(room, "RoomWall", V3(T, top + 1, 2 * h.Z + 2 * T), CF(x0 - T / 2, top / 2, c.Z), STONE_D, M.Slate, S())
	K.Part(room, "RoomWall", V3(T, top + 1, 2 * h.Z + 2 * T), CF(x1 + T / 2, top / 2, c.Z), STONE_D, M.Slate, S())
	-- inside: gold-veined floor bands, a long rug, pilasters and arches on the long walls
	for k = 0, 5 do
		K.Part(room, "FloorBand", V3(2 * h.X - .4, .06, 2 * h.Z / 6 - .3), CF(c.X, .03, z0 + (k + .5) * 2 * h.Z / 6), k % 2 == 0 and C(96, 76, 50) or C(78, 60, 44), M.Slate)
	end
	K.Part(room, "TreasureRug", V3(7, .08, 2 * h.Z - 4), CF(c.X, .08, c.Z), C(110, 30, 50), M.Fabric)
	K.Part(room, "RugTrim", V3(7.6, .06, 2 * h.Z - 3.4), CF(c.X, .05, c.Z), GOLD, M.Fabric)
	for _, sz in ipairs({ -1, 1 }) do
		local wz = sz < 0 and z0 or z1
		for k = 0, 4 do
			local px = x0 + 3 + k * (2 * h.X - 6) / 4
			K.Part(room, "Pilaster", V3(1.4, top, .8), CF(px, top / 2, wz - sz * .4), STONE_L:Lerp(STONE, .5), M.Slate)
			K.Part(room, "PilasterCap", V3(2, .6, 1.2), CF(px, top - 2.6, wz - sz * .6), GOLD:Lerp(INK, .3), M.Metal)
		end
		for k = 0, 3 do
			local ax = x0 + 3 + (k + .5) * (2 * h.X - 6) / 4
			local arch = CF(ax, top - 5, wz - sz * .3)
			for a = 0, 5 do
				local t0, t1 = a / 6 * PI, (a + 1) / 6 * PI
				K.Bar(room, "WallArch", (arch * CF(math.cos(t0) * 3, math.sin(t0) * 2.2, 0)).Position, (arch * CF(math.cos(t1) * 3, math.sin(t1) * 2.2, 0)).Position, .5,
					.5, STONE_L:Lerp(STONE, .4), M.Slate)
			end
			-- skull niches with candles in the back wall arches
			if sz < 0 then
				Y.Skull(room, CF(ax, top - 5.6, wz + .6), 1, CANDLE, BONE)
			end
		end
	end
	-- the hoard: three pedestals with chests, gold piles, gems, goblets, a crown, the golden dog
	local chestZ = z0 + 6
	for i = 1, 3 do
		local px = c.X + (i - 2) * 9
		local ped = K.Part(room, "ChestPedestal", V3(3.6, 1.6, 3), CF(px, .8, chestZ), STONE_L:Lerp(STONE, .3), M.Marble, S())
		ped:SetAttribute("RareChest", i)
		K.Part(room, "PedestalTrim", V3(3.9, .3, 3.3), CF(px, 1.5, chestZ), GOLD, M.Metal)
		local chest = K.Model(room, "RareChest_" .. i)
		chest:SetAttribute("RareChest", i)
		chest.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local body = K.Part(chest, "ChestBody", V3(3, 1.6, 2), CF(px, 2.45, chestZ), C(80, 40, 50), M.WoodPlanks)
		chest.PrimaryPart = body
		for _, sx in ipairs({ -1, 1 }) do
			K.Part(chest, "ChestBand", V3(.3, 1.7, 2.1), CF(px + sx * 1, 2.45, chestZ), GOLD, M.Metal)
		end
		K.Part(chest, "ChestLock", V3(.6, .7, .2), CF(px, 2.7, chestZ + 1.05), GOLD, M.Metal)
		local lid = K.Model(chest, "Lid")
		local lh = K.Part(lid, "LidHinge", V3(3, .2, .2), CF(px, 3.25, chestZ - 1), IRON, M.Metal, { Transparency = 1 })
		lid.PrimaryPart = lh
		lid:SetAttribute("OpenAngle", 70)
		lid:SetAttribute("OpenAxis", "X")
		K.CylX(lid, "LidDome", 3, 2, CF(px, 3.25, chestZ), C(90, 46, 56), M.WoodPlanks)
		K.CylX(lid, "LidBand", .3, 2.1, CF(px - 1, 3.25, chestZ), GOLD, M.Metal)
		K.CylX(lid, "LidBand", .3, 2.1, CF(px + 1, 3.25, chestZ), GOLD, M.Metal)
		K.Part(chest, "ChestGlow", V3(2.6, .1, 1.6), CF(px, 3.28, chestZ), GOLD, M.Neon, { Transparency = .4 })
		for _, d in ipairs(chest:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	end
	local function coinPile(pos: Vector3, s: number)
		K.Ellipsoid(room, "CoinPile", V3(3 * s, 1.2 * s, 2.6 * s), CF(pos + V3(0, .3 * s, 0)), GOLD, M.Metal)
		K.Ellipsoid(room, "CoinPile", V3(1.8 * s, 1.1 * s, 1.6 * s), CF(pos + V3(.3 * s, .8 * s, -.2 * s)), GOLD:Lerp(BONE, .2), M.Metal)
	end
	for _, cp in ipairs({ V3(x0 + 3, 0, z0 + 3), V3(x1 - 3, 0, z0 + 3.5), V3(x0 + 4, 0, z1 - 6), V3(x1 - 3.5, 0, z1 - 7), V3(c.X - 4.5, 0, chestZ + 3.5),
		V3(c.X + 5, 0, chestZ + 3) }) do
		coinPile(cp, rng:NextNumber(.8, 1.3))
	end
	local gems = { GREEN, VIOLET, MOON, C(240, 80, 90) }
	for k = 1, 10 do
		local p = V3(rng:NextNumber(x0 + 2, x1 - 2), .4, rng:NextNumber(z0 + 2, z0 + 10))
		K.Part(room, "Gem", V3(.5, .7, .5), CF(p) * ANG(rng:NextNumber(0, PI), rng:NextNumber(0, PI), 0), gems[k % 4 + 1], M.Neon)
	end
	for k, gp in ipairs({ V3(c.X - 4.5, 1.6, chestZ), V3(c.X + 4.5, 1.6, chestZ), V3(x1 - 4, 0, c.Z) }) do
		K.CylY(room, "Goblet", .9, .4, CF(gp + V3(0, .45, 0)), GOLD, M.Metal)
		K.CylY(room, "GobletCup", .8, 1, CF(gp + V3(0, 1.3, 0)), GOLD, M.Metal)
		K.CylY(room, "GobletWine", .05, .8, CF(gp + V3(0, 1.7, 0)), k == 3 and GREEN or C(140, 20, 40), M.Neon)
	end
	-- crown on the middle chest
	local crownC = CF(c.X, 3.5, chestZ + .3)
	K.CylY(room, "Crown", .7, 1.6, crownC * CF(0, .35, 0), GOLD, M.Metal)
	for k = 0, 4 do
		local a = k / 5 * 2 * PI
		K.Wedge(room, "CrownPoint", V3(.2, .6, .4), crownC * CF(math.cos(a) * .7, .95, math.sin(a) * .7) * ANG(0, -a, 0), GOLD, M.Metal)
	end
	-- the golden dog statue watches the spawn from the far end
	Y.DogStatue(room, CF(x0 + 4, 0, c.Z + 2) * ANG(0, -PI / 2, 0), { Scale = 1.1, Color = GOLD, EyeColor = GREEN, Name = "GoldenHound" })
	-- candles + warm light
	for _, cp in ipairs({ V3(x0 + 2, 0, z0 + 2), V3(x1 - 2, 0, z0 + 2), V3(x0 + 2, 0, z1 - 2), V3(x1 - 2, 0, z1 - 2), V3(c.X, 0, chestZ - 2.5) }) do
		K.Candles(room, CF(cp), 4, rng, { Light = false, Spread = .9 })
	end
	for k, lp in ipairs({ V3(c.X - 9, 8, chestZ + 2), V3(c.X + 9, 8, chestZ + 2), V3(c.X, 9, z1 - 5) }) do
		local glow = K.Part(room, "CandleGlow", V3(.4, .4, .4), CF(lp), CANDLE, M.Neon, { Transparency = 1, Attrs = { HwCandle = true } })
		K.Light(glow, CANDLE, 22, k == 3 and .8 or 1.1)
		glow:SetAttribute("HwBaseBrightness", k == 3 and .8 or 1.1)
	end
	-- hanging chains + a chandelier ring
	local chand = CF(c.X, top - 4, c.Z)
	Y.RuneRing(room, chand, 3, 10, .3, GOLD, { Fill = .9, H = .3, Transparency = 0, Name = "Chandelier" })
	for k = 0, 3 do
		local a = k / 4 * 2 * PI
		K.Bar(room, "ChandelierChain", (chand * CF(math.cos(a) * 3, 0, math.sin(a) * 3)).Position, V3(c.X, top, c.Z), .12, .12, IRON, M.CorrodedMetal)
	end
	K.Candles(room, chand * CF(0, .2, 0), 4, rng, { Light = false, Spread = 2.6 })
	local plaque = K.Part(room, "HoardPlaque", V3(6, 1.4, .2), CF(c.X, 9.5, z0 + .3), GOLD:Lerp(INK, .35), M.Metal)
	sign(plaque, N.Back, "THE HOLLOW HOARD", BONE, { PixelsPerStud = 26, H = .78, StrokeColor = INK })
	-- outside: a slate roof and a dome peeking over the door wall
	K.Part(room, "VaultRoof", V3(2 * h.X + 4, .6, 2 * h.Z + 4), CF(c.X, top + T + .3, c.Z), C(40, 34, 52), M.Slate)
	K.Ellipsoid(room, "VaultDome", V3(12, 8, 12), CF(c.X, top + T + .6, c.Z), C(64, 46, 86), M.Slate)
	K.CylY(room, "VaultLantern", 2, 2, CF(c.X, top + T + 5.2, c.Z), GOLD:Lerp(INK, .2), M.Metal)
	K.Ball(room, "VaultFinial", 1.2, CF(c.X, top + T + 6.8, c.Z), GOLD, M.Neon)
	return room
end

------------------------------------------------------------------------------------------------------------------
-- ground, court, lane, perimeter
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

local function buildGround(root, L, rng, lane, shared: boolean)
	local g = K.Model(root, "Ground")
	local box
	for _, d in ipairs(L.Districts) do
		if d.Name == "CrookedRow" then
			box = d
		end
	end
	local x0, x1, z0, z1 = box.Min.X, box.Max.X, box.Min.Z, box.Max.Z
	if not shared then
		local floor = slab(g, "RowFloor", (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0, 0, 0, 2, DIRT, M.Ground, { Solid = true, Shadow = false })
		floor:SetAttribute("UyFloor", "CrookedRow")
		-- entrance apron from the gate into the district (WP-G's spoke bridge takes this role when present)
		local gate = L.Gates.CrookedRow
		local ap = K.Look(gate.Position + gate.Facing * 8, gate.Position + gate.Facing * 20)
		K.Part(g, "EntranceApron", V3(15, .2, 16), ap * CF(0, -.06, 0), COBBLE, M.Cobblestone, { Solid = true, Shadow = false })
	end
	local court = L.Crooked.Court
	local function clearOf(x, z, r)
		if (V3(x, 0, z) - flat(court.Centre)).Magnitude < court.Radius + 2 + r then
			return false
		end
		if z < L.Crooked.WallZ + 24 and z > L.Crooked.WallZ - 6 and x > -200 and x < -96 then
			return false -- apron
		end
		for k = 1, #lane - 1 do
			if segDist(V3(x, 0, z), lane[k], lane[k + 1]) < 6 + r then
				return false
			end
		end
		return true
	end
	-- dead-grass yards, flagstone clusters, puddles, cracks
	for k = 1, 30 do
		local cx, cz = rng:NextNumber(x0 + 5, x1 - 5), rng:NextNumber(L.Crooked.WallZ + 2, z1 - 5)
		if clearOf(cx, cz, 3) then
			K.Ellipsoid(g, "DeadGrass", V3(rng:NextNumber(5, 10), .12, rng:NextNumber(4, 8)), CF(cx, .02, cz) * ANG(0, rng:NextNumber(0, PI), 0),
				DEADGRASS:Lerp(DIRT, rng:NextNumber(0, .4)), M.Grass)
			if k % 3 == 0 then
				for _ = 1, 3 do
					slab(g, "Flagstone", cx + rng:NextNumber(-3, 3), cz + rng:NextNumber(-3, 3), rng:NextNumber(1.6, 3), rng:NextNumber(1.4, 2.6), rng:NextNumber(0, PI),
						rng:NextNumber(.04, .09), .12, FLAG:Lerp(DIRT_D, rng:NextNumber(0, .4)), M.Slate)
				end
			end
			if k % 4 == 1 then
				K.Ellipsoid(g, "Puddle", V3(rng:NextNumber(2.5, 5), .06, rng:NextNumber(2, 4)), CF(cx + 3, .02, cz - 2), C(40, 44, 70), M.Glass,
					{ Reflectance = .25, Transparency = .1 })
			end
		end
	end
	return g
end

local function buildLane(root, L, lane)
	local m = K.Model(root, "BentLane")
	local LW = 11
	for k = 1, #lane - 1 do
		local a, b = flat(lane[k]), flat(lane[k + 1])
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = K.Look(V3(mid.X, .03, mid.Z), V3(b.X, .03, b.Z))
		K.Part(m, "LaneCobbles", V3(LW, .1, len), cf, k % 2 == 0 and COBBLE or COBBLE2, M.Cobblestone)
		for _, sx in ipairs({ -1, 1 }) do
			K.Part(m, "LaneKerb", V3(.5, .22, len), cf * CF(sx * (LW / 2 + .2), .08, 0) * ANG(0, sx * .01, 0), BONE:Lerp(FLAG, .6), M.Slate)
			K.Part(m, "LaneGutter", V3(.6, .04, len), cf * CF(sx * (LW / 2 - .6), .04, 0), INK, M.Slate)
		end
		if k < #lane - 1 then
			K.CylY(m, "LaneJoint", .1, LW, CF(b.X, .035, b.Z), k % 2 == 0 and COBBLE2 or COBBLE, M.Cobblestone)
		end
		-- paw prints wandering down the lane
		local d = (b - a).Unit
		local side = V3(-d.Z, 0, d.X)
		for t = 3, len - 2, 4.5 do
			local p = a + d * t + side * (math.floor(t / 4.5) % 2 == 0 and 1.2 or -1.2)
			local pc = K.Look(V3(p.X, .1, p.Z), V3(p.X, .1, p.Z) + d)
			K.Ellipsoid(m, "PawPrint", V3(.9, .04, .8), pc, INK:Lerp(COBBLE, .3), M.SmoothPlastic)
			K.Ellipsoid(m, "PawPrintToe", V3(.8, .04, .3), pc * CF(0, 0, -.65), INK:Lerp(COBBLE, .3), M.SmoothPlastic)
		end
	end
	-- the street sign by the gate
	local a, b = lane[2], lane[3]
	local d = flat(b - a).Unit
	local side = V3(-d.Z, 0, d.X)
	local sp = a + side * 7.2 + d * 2
	local post = K.CylY(m, "SignPost", 9, .5, CF(sp + V3(0, 4.5, 0)) * ANG(.04, 0, -.05), IRON, M.CorrodedMetal, S())
	local face = K.Look(sp, sp - side)
	local s1 = K.Part(m, "StreetSign", V3(6.4, 1.2, .2), face * CF(0, 7.6, 0) * ANG(0, 0, .06), C(36, 30, 52), M.SmoothPlastic)
	sign(s1, N.Front, "13 CROOKED ROW", BONE, { PixelsPerStud = 26, H = .78, StrokeColor = VIOLET })
	sign(s1, N.Back, "13 CROOKED ROW", BONE, { PixelsPerStud = 26, H = .78, StrokeColor = VIOLET })
	local arrow = K.Look(sp, sp + d)
	local s2 = K.Part(m, "StreetSign", V3(.2, 1, 5.6), arrow * CF(0, 6.1, -2.2) * ANG(0, 0, -.05), C(70, 24, 60), M.SmoothPlastic)
	sign(s2, N.Right, "THE DOOR COURT", BONE, { PixelsPerStud = 26, H = .78 })
	sign(s2, N.Left, "THE DOOR COURT", BONE, { PixelsPerStud = 26, H = .78 })
	K.Wedge(m, "SignArrow", V3(.2, 1, .9), arrow * CF(0, 6.1, -5.45), C(70, 24, 60), M.SmoothPlastic)
	K.Ball(m, "SignFinial", .7, CF(sp + V3(0, 9.2, 0)), BONE, M.SmoothPlastic)
	K.Attach(post, "CrowPerch", CF(4.9, 0, 0))
	return m
end

local function buildCourt(root, L, rng)
	local m = K.Model(root, "DoorCourt")
	local court = L.Crooked.Court
	local c = court.Centre
	local R = court.Radius
	-- concentric cobble rings (alternating tones), a paw-rose in the middle, a rune ring for the challenges
	K.CylY(m, "CourtBase", .12, 2 * R + .4, CF(c + V3(0, .02, 0)), COBBLE2, M.Cobblestone)
	local rings = { 4.2, 8.4, 12.6, 16.8, 21, 24.8 }
	for k, r in ipairs(rings) do
		if k > 1 then
			local inner = rings[k - 1]
			local mid = (r + inner) / 2
			local n = math.max(8, math.floor(2 * PI * mid / 3.6))
			for s = 0, n - 1 do
				local a0, a1 = s / n * 2 * PI, (s + 1) / n * 2 * PI
				local col = (s + k) % 2 == 0 and COBBLE or COBBLE:Lerp(STONE_L, .18)
				K.Bar(m, "CourtCobble", V3(c.X + math.cos(a0) * mid, .1, c.Z + math.sin(a0) * mid), V3(c.X + math.cos(a1) * mid, .1, c.Z + math.sin(a1) * mid),
					r - inner - .25, .1, col, M.Cobblestone)
			end
		end
	end
	K.CylY(m, "CourtHeart", .14, 8, CF(c + V3(0, .06, 0)), STONE_L:Lerp(COBBLE, .5), M.Slate)
	-- paw rose
	K.Ellipsoid(m, "RosePad", V3(3, .06, 2.6), CF(c + V3(0, .14, .4)), INK, M.SmoothPlastic)
	for t = -1, 1 do
		K.Ellipsoid(m, "RoseToe", V3(1, .06, 1.2), CF(c + V3(t * 1.2, .14, -1.6 + math.abs(t) * .5)), INK, M.SmoothPlastic)
	end
	Y.RuneRing(m, CF(c + V3(0, .16, 0)), 18.9, 28, .35, VIOLET, { Fill = .65, H = .04, Transparency = .35, Name = "CourtRune" })
	Y.RuneRing(m, CF(c + V3(0, .16, 0)), 10.5, 16, .25, GREEN:Lerp(INK, .3), { Fill = .5, H = .04, Transparency = .45, Phase = .2, Name = "CourtRune" })
	-- rim: low kerb ring at r 26
	for s = 0, 39 do
		local a0, a1 = s / 40 * 2 * PI, (s + 1) / 40 * 2 * PI
		K.Bar(m, "CourtKerb", V3(c.X + math.cos(a0) * (R - .2), .14, c.Z + math.sin(a0) * (R - .2)), V3(c.X + math.cos(a1) * (R - .2), .14, c.Z + math.sin(a1) * (R - .2)),
			.7, .28, s % 2 == 0 and BONE:Lerp(STONE_L, .5) or STONE_L, M.Slate)
	end
	-- the apron: flagstones from the wall to the court rim
	local Z = L.Crooked.WallZ
	local ap = K.Model(m, "DoorApron")
	K.Part(ap, "ApronSlab", V3(106, .1, 24), CF(-148, .02, Z + 12), FLAG, M.Slate)
	for k = 0, 16 do
		local x = -200 + k * 6.4
		K.Part(ap, "ApronJoint", V3(.18, .04, 24), CF(x, .08, Z + 12) * ANG(0, rng:NextNumber(-.04, .04), 0), INK:Lerp(FLAG, .4), M.Slate)
	end
	for k = 0, 3 do
		K.Part(ap, "ApronJoint", V3(106, .04, .18), CF(-148, .08, Z + 3 + k * 6) * ANG(0, rng:NextNumber(-.004, .004), 0), INK:Lerp(FLAG, .4), M.Slate)
	end
	-- stepping stones from each door to the court
	for _, dp in ipairs(L.Crooked.Doors) do
		local a = V3(dp.X, 0, Z + 2)
		local b = flat(c) + (V3(dp.X, 0, Z) - flat(c)).Unit * (R - 1)
		for t = 0, 3 do
			local p = a:Lerp(b, (t + .5) / 4)
			K.CylY(m, "SteppingStone", .1, 2.2, CF(p.X, .12, p.Z), STONE_L:Lerp(FLAG, .4), M.Slate)
		end
	end
	return m
end

local function buildPerimeter(root, L, rng)
	local m = K.Model(root, "Perimeter")
	local B = L.Bounds
	local box
	for _, d in ipairs(L.Districts) do
		if d.Name == "CrookedRow" then
			box = d
		end
	end
	local xE, zS = box.Max.X - .6, box.Max.Z - .6
	local gate = L.Gates.CrookedRow
	-- entrance gap = where the spoke bridge crosses the district corner (east and south edges)
	local zE = bridgeCrossings(L, gate, "X", xE) - .5
	local xS = bridgeCrossings(L, gate, "Z", zS) - .5
	local endE, endS = V3(xE, 0, zE), V3(xS, 0, zS)
	-- bone fence runs on the inner edges (gaps behind the houses are covered by the houses themselves)
	local function boneFence(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = math.max(1, math.floor(len / 6))
		for k = 0, n do
			local p = a + dir * (len * k / n)
			K.CylY(m, "FencePost", 5.6, .7, CF(p + V3(0, 2.8, 0)) * ANG(rng:NextNumber(-.05, .05), 0, rng:NextNumber(-.05, .05)), STONE_D, M.Slate, S())
			Y.Skull(m, CF(p + V3(0, 6, 0)) * ANG(0, rng:NextNumber(-.6, .6), 0), .9, nil, BONE)
			if k < n then
				local q0, q1 = a + dir * (len * k / n), a + dir * (len * (k + 1) / n)
				K.Bar(m, "FenceRail", q0 + V3(0, 1.4, 0), q1 + V3(0, 1.4, 0), .3, .3, IRON, M.CorrodedMetal, S())
				K.Bar(m, "FenceRail", q0 + V3(0, 4.3, 0), q1 + V3(0, 4.3, 0), .3, .3, IRON, M.CorrodedMetal)
				for j = 1, 4 do
					local pj = q0:Lerp(q1, j / 5)
					K.Part(m, "FenceBone", V3(.35, 3.6, .35), CF(pj + V3(0, 2.85, 0)) * ANG(rng:NextNumber(-.1, .1), 0, rng:NextNumber(-.12, .12)), BONE:Lerp(STONE_L, .3),
						M.SmoothPlastic, S())
				end
			end
		end
	end
	boneFence(V3(xE, 0, B.Z0 + 52), V3(xE, 0, endE.Z))
	boneFence(V3(B.X0 + 30, 0, zS), V3(endS.X, 0, zS))
	-- gate posts of the entrance gap
	for k, p in ipairs({ V3(xE, 0, endE.Z), V3(endS.X, 0, zS) }) do
		K.Part(m, "GatePier", V3(2.4, 11, 2.4), CF(p + V3(0, 5.5, 0)) * ANG(0, 0, k == 1 and .04 or -.04), STONE, M.Slate, S())
		K.Part(m, "GatePierCap", V3(3, .6, 3), CF(p + V3(0, 11.2, 0)), STONE_D, M.Slate)
		Y.Skull(m, CF(p + V3(0, 12.3, 0)) * ANG(0, PI * .75, 0), 1.6, k == 1 and GREEN or VIOLET, BONE)
	end
	-- colliders: all four sides (gap left open), plus the backstage behind the wall
	collider(m, V3(1, 40, endE.Z - (B.Z0 - 2)), CF(box.Max.X + .2, 20, (endE.Z + B.Z0 - 2) / 2))
	collider(m, V3(endS.X - (B.X0 - 2), 40, 1), CF((endS.X + B.X0 - 2) / 2, 20, box.Max.Z + .2))
	collider(m, V3(B.X1 - B.X0, 40, 1), CF((box.Min.X + box.Max.X) / 2, 20, B.Z0 - .2))
	collider(m, V3(1, 40, box.Max.Z - B.Z0 + 4), CF(B.X0 - .2, 20, (box.Max.Z + B.Z0) / 2))
	local Z = L.Crooked.WallZ
	collider(m, V3(24, 40, 1), CF((B.X0 + -198) / 2, 20, Z - 2))
	collider(m, V3(24, 40, 1), CF((-98 + box.Max.X) / 2, 20, Z - 2))
	return m
end

------------------------------------------------------------------------------------------------------------------
-- laundry
------------------------------------------------------------------------------------------------------------------

local function laundryLine(m, a: Vector3, b: Vector3, rng)
	local lm = K.Model(m, "LaundryLine")
	local sag = math.min(2.2, (b - a).Magnitude * .07)
	local function at(t)
		return a:Lerp(b, t) - V3(0, math.sin(t * PI) * sag, 0)
	end
	local prev = a
	for k = 1, 4 do
		local q = at(k / 4)
		K.Bar(lm, "LaundryRope", prev, q, .09, .09, C(150, 140, 120), M.Fabric)
		prev = q
	end
	local along = flat(b - a).Unit
	local n = math.max(2, math.floor((b - a).Magnitude / 3.2))
	for k = 1, n do
		local t = k / (n + 1)
		local p = at(t)
		local cf = K.Look(p, p + V3(-along.Z, 0, along.X)) * ANG(rng:NextNumber(-.06, .06), 0, rng:NextNumber(-.08, .08))
		local kind = rng:NextInteger(1, 5)
		if kind <= 2 then
			-- shroud / ghost sheet
			local hgt = rng:NextNumber(3.2, 4.6)
			K.Part(lm, "Shroud", V3(2.2, hgt, .06), cf * CF(0, -hgt / 2, 0), SHEET, M.Fabric, { Transparency = .2 })
			for j = -1, 1, 2 do
				K.Part(lm, "Clothespin", V3(.15, .4, .15), cf * CF(j * .9, -.1, 0), TIMBER, M.Wood)
			end
			if kind == 2 then
				for j = -1, 1, 2 do
					K.Ellipsoid(lm, "SheetEye", V3(.4, .55, .08), cf * CF(j * .45, -1.2, -.04), INK, M.SmoothPlastic)
				end
			end
		elseif kind == 3 then
			-- striped shirt (black / white) with sleeves
			for j = 0, 3 do
				K.Part(lm, "ShirtStripe", V3(1.9, .45, .06), cf * CF(0, -.3 - j * .45, 0), j % 2 == 0 and INK or SHEET, M.Fabric)
			end
			for j = -1, 1, 2 do
				K.Part(lm, "ShirtSleeve", V3(.6, 1.1, .06), cf * CF(j * 1.2, -.6, 0) * ANG(0, 0, j * .5), INK, M.Fabric)
			end
		elseif kind == 4 then
			-- pair of socks
			for j = -1, 1, 2 do
				K.Part(lm, "Sock", V3(.45, 1.3, .1), cf * CF(j * .35, -.65, 0), j < 0 and VIOLET:Lerp(INK, .3) or GREEN:Lerp(INK, .45), M.Fabric)
				K.Part(lm, "SockFoot", V3(.45, .4, .5), cf * CF(j * .35, -1.2, -.2), j < 0 and VIOLET:Lerp(INK, .3) or GREEN:Lerp(INK, .45), M.Fabric)
			end
		else
			-- a tattered burial shroud with a bone print
			K.Part(lm, "Shroud", V3(1.6, 3, .06), cf * CF(0, -1.5, 0), BONE:Lerp(SHEET, .5), M.Fabric, { Transparency = .1 })
			K.Bone(lm, cf * CF(0, -1.6, -.05), 1.1, INK)
		end
	end
	return lm
end

------------------------------------------------------------------------------------------------------------------

-- behind the wall (never reachable): two crooked spires and an ivy-grown backdrop that give the wall its skyline
local function buildBackstage(root, L, rng)
	local m = K.Model(root, "Backstage")
	local Z = L.Crooked.WallZ
	for k, sp in ipairs({ V3(-184, 0, Z - 16), V3(-111, 0, Z - 14) }) do
		local lean = k == 1 and .05 or -.06
		local base = CF(sp) * ANG(0, (k == 1 and 1 or -1) * .15, 0)
		K.Part(m, "SpireBody", V3(7, 22, 7), base * CF(0, 11, 0), STONE_D:Lerp(VIOLET, .08), M.Slate)
		local upper = base * CF(0, 22, 0) * ANG(0, .2, lean)
		K.Part(m, "SpireUpper", V3(5.4, 7, 5.4), upper * CF(0, 3.5, 0), STONE:Lerp(VIOLET, .06), M.Slate)
		local roofBase = upper * CF(0, 7, 0) * ANG(0, 0, lean)
		local apex = (roofBase * CF(.8, 9, 0)).Position
		for q = 0, 3 do
			local a0, a1 = q / 4 * 2 * PI + PI / 4, (q + 1) / 4 * 2 * PI + PI / 4
			tri(m, "SpireRoof", (roofBase * CF(math.cos(a0) * 4.1, 0, math.sin(a0) * 4.1)).Position, (roofBase * CF(math.cos(a1) * 4.1, 0, math.sin(a1) * 4.1)).Position,
				apex, .4, C(36, 28, 52), M.Slate)
		end
		K.Rod(m, "SpireCurl", apex, apex + V3(1.2, 1.4, 0), .3, IRON, M.CorrodedMetal)
		local tip = K.Ball(m, "SpireTip", .7, CF(apex + V3(1.4, 1.8, 0)), k == 1 and GREEN or CANDLE, M.Neon)
		K.Attach(tip, "CrowPerch", CF(0, .5, 0))
		-- a lit slit window facing the court + an eye under the roof
		gothicWindow(m, upper * CF(0, 3.6, 2.7) * ANG(0, PI, 0), 1.1, 3.2, k == 1 and VIOLET or CANDLE, k == 1 and "Purple" or "Orange", nil, STONE_L)
		eyeWindow(m, base * CF(0, 17, 3.55) * ANG(0, PI, 0), 2.8, 1.8, k == 1 and GREEN or MOON, STONE_D:Lerp(VIOLET, .08))
	end
	-- ivy on the wall face
	for _, x in ipairs({ -194, -168.5, -125 }) do
		Y.Vine(m, V3(x, 16.5, Z + .25), V3(x + rng:NextNumber(-1, 1), 4, Z + .25), rng, V3(0, 0, 1))
	end
	return m
end

-- a black hearse with a glass-sided coffin, pulled by a ghost hound (faces cf's -Z)
local function hearse(m, cf: CFrame)
	local g = K.Model(m, "Hearse")
	K.Part(g, "HearseBody", V3(4.2, 3.4, 8), cf * CF(0, 3.2, 0), INK:Lerp(VIOLET, .12), M.Wood, S())
	K.Part(g, "HearseRoof", V3(4.8, .5, 8.8), cf * CF(0, 5.2, 0), INK, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(g, "HearseGlass", V3(.1, 2.2, 5.6), cf * CF(sx * 2.12, 3.6, 0), MOON:Lerp(INK, .55), M.Glass, { Transparency = .3 })
		for _, sz in ipairs({ -1, 1 }) do
			K.CylX(g, "HearseWheel", .35, sz < 0 and 2.6 or 3.2, cf * CF(sx * 2.3, sz < 0 and 1.3 or 1.6, sz * 2.8), TIMBER, M.Wood)
			K.CylX(g, "HearseHub", .5, .7, cf * CF(sx * 2.45, sz < 0 and 1.3 or 1.6, sz * 2.8), GOLD, M.Metal)
		end
	end
	for k = -1, 1, 2 do
		K.Part(g, "HearsePlume", V3(.5, 1.6, .5), cf * CF(k * 1.8, 6.2, k * 3.6), INK, M.Fabric)
	end
	K.Part(g, "HearseCoffin", V3(1.8, 1.1, 5), cf * CF(0, 3.5, .2), C(70, 40, 40), M.Wood)
	K.Part(g, "HearseCoffinLid", V3(1.9, .2, 5.1), cf * CF(0, 4.12, .2), GOLD:Lerp(INK, .4), M.Metal)
	K.Bar(g, "HearseShaft", (cf * CF(-1, 1.6, -4)).Position, (cf * CF(-1, 1.8, -8.5)).Position, .25, .25, TIMBER, M.Wood)
	K.Bar(g, "HearseShaft", (cf * CF(1, 1.6, -4)).Position, (cf * CF(1, 1.8, -8.5)).Position, .25, .25, TIMBER, M.Wood)
	-- the ghost hound in the shafts
	local hc = cf * CF(0, 2.6, -7.4)
	K.Ellipsoid(g, "GhostHound", V3(1.8, 2, 3.6), hc, MOON, M.Neon, { Transparency = .55 })
	K.Ellipsoid(g, "GhostHoundHead", V3(1.3, 1.3, 1.6), hc * CF(0, 1.4, -1.8), MOON, M.Neon, { Transparency = .45 })
	for _, sx in ipairs({ -1, 1 }) do
		K.Wedge(g, "GhostHoundEar", V3(.2, .9, .6), hc * CF(sx * .45, 2.3, -1.6), MOON, M.Neon, { Transparency = .45 })
		K.Ball(g, "GhostHoundEye", .3, hc * CF(sx * .3, 1.55, -2.55), INK, M.SmoothPlastic)
	end
	return g
end

-- stone well with a crooked roof and a bucket
local function well(m, c: Vector3)
	local g = K.Model(m, "Well")
	for k = 0, 9 do
		local a0, a1 = k / 10 * 2 * PI, (k + 1) / 10 * 2 * PI
		K.Bar(g, "WellRing", c + V3(math.cos(a0) * 2.4, 1.1, math.sin(a0) * 2.4), c + V3(math.cos(a1) * 2.4, 1.1, math.sin(a1) * 2.4), .9, 2.2,
			STONE_L:Lerp(STONE_D, k % 2 * .3), M.Slate, S())
	end
	K.CylY(g, "WellWater", .1, 4, CF(c + V3(0, .6, 0)), GREEN:Lerp(INK, .55), M.Neon, { Transparency = .2 })
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(g, "WellPost", V3(.4, 5, .4), CF(c + V3(sx * 2.4, 2.5, 0)) * ANG(0, 0, sx * .05), TIMBER, M.Wood, S())
	end
	K.CylX(g, "WellAxle", 5.4, .4, CF(c + V3(0, 4.4, 0)), TIMBER, M.Wood)
	tri(g, "WellRoof", c + V3(-3.2, 4.8, -2), c + V3(-3.2, 4.8, 2), c + V3(0, 7, -.2), .3, C(32, 26, 44), M.Slate)
	tri(g, "WellRoof", c + V3(-3.2, 4.8, 2), c + V3(0, 7, 2.2), c + V3(0, 7, -.2), .3, C(32, 26, 44), M.Slate)
	tri(g, "WellRoof", c + V3(3.2, 4.8, -2), c + V3(3.2, 4.8, 2), c + V3(0, 7, -.2), .3, C(32, 26, 44), M.Slate)
	tri(g, "WellRoof", c + V3(3.2, 4.8, 2), c + V3(0, 7, 2.2), c + V3(0, 7, -.2), .3, C(32, 26, 44), M.Slate)
	K.Part(g, "WellRope", V3(.1, 2.4, .1), CF(c + V3(.5, 3.2, 0)), C(150, 140, 120), M.Fabric)
	K.CylY(g, "WellBucket", .9, .9, CF(c + V3(.5, 1.75, 0)), TIMBER, M.Wood)
	return g
end

-- little kennel (faces cf's -Z) with a bowl and a chain
local function kennel(m, cf: CFrame)
	local g = K.Model(m, "Kennel")
	K.Part(g, "KennelBox", V3(3, 2.4, 3.4), cf * CF(0, 1.2, 0), C(96, 52, 40), M.WoodPlanks, S())
	for _, sx in ipairs({ -1, 1 }) do
		K.Bar(g, "KennelRoof", (cf * CF(sx * 1.9, 2.3, 0)).Position, (cf * CF(0, 3.6, 0)).Position, 3.9, .25, C(40, 30, 44), M.Slate)
	end
	tri(g, "KennelGable", (cf * CF(-1.5, 2.4, -1.7)).Position, (cf * CF(1.5, 2.4, -1.7)).Position, (cf * CF(0, 3.5, -1.7)).Position, .2, C(96, 52, 40), M.WoodPlanks)
	K.Part(g, "KennelHole", V3(1.4, 1.5, .1), cf * CF(0, .9, -1.72), INK, M.SmoothPlastic)
	K.Ball(g, "KennelEyes", .25, cf * CF(-.25, 1.1, -1.76), GREEN, M.Neon)
	K.Ball(g, "KennelEyes", .25, cf * CF(.25, 1.1, -1.76), GREEN, M.Neon)
	K.CylY(g, "DogBowl", .35, 1.1, cf * CF(1.6, .18, -2.4), VIOLET:Lerp(INK, .3), M.Metal)
	return g
end

local function houseSpecs(L)
	local Z = L.Crooked.WallZ
	local function u(x, z)
		return V3(x, 0, z).Unit
	end
	local WALL = { C(70, 62, 86), C(58, 64, 74), C(80, 66, 70), C(62, 56, 70), C(52, 60, 66), C(74, 70, 82) }
	local ROOF = { C(32, 26, 44), C(26, 36, 44), C(42, 28, 40), C(30, 30, 38) }
	local EYES = { GREEN, CANDLE, MOON, GREEN, VIOLET }
	local GLOWS = { { CANDLE, "Orange" }, { GREEN, "Green" }, { CANDLE, "Orange" }, { VIOLET, "Purple" } }
	local list = {
		{ Pos = V3(-210, 0, Z - 2), Face = V3(0, 0, 1), W = 17, D = 16, Storeys = 3, Lean = .03, Twist = .02, EyeTop = true, Rise = 11, Chimney = 8 },
		{ Pos = V3(-86, 0, Z - 2), Face = V3(0, 0, 1), W = 17, D = 16, Storeys = 3, Lean = -.035, Twist = -.025, EyeMid = true, GableEye = true, Rise = 12 },
		{ Pos = V3(-201, 0, 2238), Face = V3(1, 0, 0), W = 14, D = 14, Storeys = 2, Lean = .04, GableEye = true, Fence = true },
		{ Pos = V3(-203, 0, 2267), Face = u(1, .12), W = 13, D = 14, Storeys = 3, Lean = -.03, Twist = .03, EyeTop = true, Chimney = 7 },
		{ Pos = V3(-203, 0, 2306), Face = u(.8, -.6), W = 14, D = 13, Storeys = 2, Lean = .035, EyeMid = true, GableEye = true, Fence = true },
		{ Pos = V3(-176, 0, 2307), Face = u(.22, -1), W = 15, D = 14, Storeys = 3, Lean = -.04, Twist = -.02, GableEye = true },
		{ Pos = V3(-148, 0, 2310), Face = V3(0, 0, -1), W = 16, D = 13, Storeys = 2, Lean = .03, EyeMid = true, GableEye = true, Fence = true, Rise = 13 },
		{ Pos = V3(-122, 0, 2312), Face = u(-.3, -1), W = 13, D = 13, Storeys = 3, Lean = .045, Twist = .03, EyeTop = true },
		{ Pos = V3(-92, 0, 2246), Face = u(-1, .15), W = 14, D = 14, Storeys = 2, Lean = -.04, GableEye = true, Fence = true },
		{ Pos = V3(-90, 0, 2276), Face = u(-1, .3), W = 13, D = 13, Storeys = 3, Lean = .03, Twist = -.03, EyeTop = true, Chimney = 7 },
		{ Pos = V3(-100, 0, 2318), Face = V3(0, 0, -1), W = 9, D = 9, Storeys = 1, Lean = -.05, GableEye = true, Rise = 8, Chimney = 4 },
	}
	for i, s in ipairs(list) do
		s.Number = i
		s.Seed = 6100 + i * 37
		s.Wall = WALL[(i - 1) % #WALL + 1]
		s.Trim = (i % 3 == 0) and BONE:Lerp(TIMBER, .45) or TIMBER
		s.Roof = ROOF[(i - 1) % #ROOF + 1]
		s.Eye = EYES[(i - 1) % #EYES + 1]
		s.Glow = GLOWS[(i - 1) % #GLOWS + 1]
		s.Lit = i ~= 11
		s.DoorSide = i % 2 == 0 and 1 or -1
		s.ChimneySide = i % 2 == 0 and -1 or 1
	end
	return list
end

local function buildProps(root, L, rng, lane, linePoints)
	local m = K.Model(root, "Props")
	local court = L.Crooked.Court
	local c = court.Centre
	local Z = L.Crooked.WallZ
	-- crooked lamps: around the court rim (outside r 26), flanking the apron, along the lane
	local lamps = K.Model(m, "Lamps")
	local kinds = { { GREEN, "Green" }, { CANDLE, "Orange" }, { VIOLET, "Purple" } }
	local spots = {
		c + V3(0, 0, court.Radius + 3.5), c + V3(-court.Radius - 3.5, 0, 0), c + V3(court.Radius + 4, 0, -4),
		V3(-194, 0, Z + 9), V3(-102, 0, Z + 9),
	}
	for k = 2, #lane - 1, 2 do
		local a, b = lane[k], lane[k + 1]
		local d = flat(b - a).Unit
		table.insert(spots, a:Lerp(b, .5) + V3(-d.Z, 0, d.X) * (k % 4 == 1 and 8 or -8))
	end
	for k, p in ipairs(spots) do
		local kind = kinds[(k - 1) % 3 + 1]
		crookedLamp(lamps, p, rng:NextNumber(10, 12.5), rng, kind[1], kind[2], true)
	end
	-- laundry between neighbouring houses (never over the court, never through the wall)
	local laundry = K.Model(m, "Laundry")
	local made = 0
	for i = 1, #linePoints do
		for j = i + 1, #linePoints do
			local best, bd = nil, math.huge
			for _, pa in ipairs(linePoints[i]) do
				for _, pb in ipairs(linePoints[j]) do
					local dd = (pa - pb).Magnitude
					if dd < bd then
						best, bd = { pa, pb }, dd
					end
				end
			end
			if best and bd > 7 and bd < 36 and made < 9 then
				local a, b = best[1], best[2]
				local ok = segDist(c, a, b) > court.Radius + 2 and math.min(a.Z, b.Z) > Z + 1
				if ok then
					laundryLine(laundry, a, b, rng)
					made += 1
				end
			end
		end
	end
	-- dead trees and dog graves in the yards
	local yard = K.Model(m, "Yards")
	for k, tp in ipairs({ V3(-212, 0, 2222), V3(-86, 0, 2226), V3(-212, 0, 2286), V3(-134, 0, 2322) }) do
		Y.Tree(yard, CF(tp), rng:NextNumber(13, 17), rng, { Branches = 3, Hollow = k % 2 == 1, HollowColor = GREEN, Perches = 2, Spread = 6, Name = "CrookedTree" })
	end
	local names = { "REX", "FANG", "BONES", "LADY", "MOLE", "SCRAP" }
	for k, gp in ipairs({ V3(-206, 0, 2252), V3(-208, 0, 2283), V3(-192, 0, 2323), V3(-133, 0, 2327), V3(-83, 0, 2232), V3(-84, 0, 2262) }) do
		Y.Tombstone(yard, CF(gp) * ANG(0, rng:NextNumber(0, 2 * PI), 0), ({ 4, 7, 8, 1, 6, 9 })[k], rng, names[k], { NoTranslate = true })
	end
	-- the hearse waiting by the court, the well, kennels in the yards
	hearse(yard, K.Look(V3(-110, 0, 2258), V3(-110, 0, 2247)))
	well(yard, V3(-190, 0, 2252))
	for _, kp in ipairs({ { V3(-212, 0, 2228), V3(-200, 0, 2230) }, { V3(-84, 0, 2216), V3(-90, 0, 2226) }, { V3(-160, 0, 2326), V3(-160, 0, 2316) } }) do
		kennel(yard, K.Look(kp[1], kp[2]))
	end
	-- crooked mailboxes with eyes at a few doors
	for k, mp in ipairs({ V3(-196, 0, 2232), V3(-160, 0, 2300), V3(-98, 0, 2253) }) do
		K.Part(yard, "MailPost", V3(.4, 3.2, .4), CF(mp + V3(0, 1.6, 0)) * ANG(0, 0, (k - 2) * .12), TIMBER, M.Wood, S())
		local box = K.Part(yard, "Mailbox", V3(1.2, 1.1, 2), CF(mp + V3(0, 3.7, 0)) * ANG(0, k, (k - 2) * .12), VIOLET:Lerp(INK, .5), M.Metal)
		K.Ball(yard, "MailboxEye", .35, box.CFrame * CF(-.25, .2, -1.02), GREEN, M.Neon)
		K.Ball(yard, "MailboxEye", .35, box.CFrame * CF(.25, .2, -1.02), GREEN, M.Neon)
	end
	-- fog + ghost path markers for UnderyardFX
	local fx = K.Model(m, "FXMarkers")
	for k, p in ipairs({ c + V3(0, .3, 0), c + V3(14, .3, 10), c + V3(-14, .3, -8), V3(-104, .3, 2298), V3(-190, .3, 2290), V3(-148, .3, Z + 6) }) do
		K.Marker(fx, "FogPoint", p, { Order = k })
	end
	for k, p in ipairs({ V3(-100, 4, 2300), V3(-126, 4, 2280), V3(-160, 4, 2245), V3(-190, 4, 2290), V3(-148, 4, 2292) }) do
		K.Marker(fx, "GhostPath_" .. k, p)
	end
	return m
end

function CR.Build(ctx)
	local L = ctx.Layout
	local root = ctx.Model and ctx.Model("CrookedRow") or K.Model(ctx.Root, "CrookedRow")
	root:SetAttribute("UyDistrict", "CrookedRow")
	root:SetAttribute("Seal", 5)
	local lane = CR.LanePath(L)
	buildGround(root, L, Rng(5101), lane, sharedFloor(ctx.Root, "CrookedRow"))
	buildLane(root, L, lane)
	buildCourt(root, L, Rng(5103))
	buildDoorWall(root, L, Rng(5104))
	buildRareRoom(root, L, Rng(5105))
	buildBackstage(root, L, Rng(5108))
	local houses = K.Model(root, "Houses")
	local linePoints = {}
	for _, spec in ipairs(houseSpecs(L)) do
		local _, pts = buildHouse(houses, spec)
		table.insert(linePoints, pts)
	end
	buildPerimeter(root, L, Rng(5106))
	buildProps(root, L, Rng(5107), lane, linePoints)
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
		ctx.Note(string.format("CrookedRow: %d parts, %d lights (budget %d / %d)", parts, lights, CR.Budget.Parts, CR.Budget.Lights))
	end
	return root
end

return CR
