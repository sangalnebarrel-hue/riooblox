-- THE CHURCH (Grand Crypt + Moon Tower) · CHAPTER II reveal geometry (ServerStorage.HalloweenBuild.Church, WP-F).
-- Build-time only: run offline by tools/edits/38_church.luau (docs/halloween2/DESIGN.md §6.4); the output is saved in
-- the place as Workspace.DOGROTS_District.38_DeadYard.Church. Everything the client animates per player starts in its
-- "closed / hidden" state here; HalloweenClient.Reveal opens it for players who watched the church cinematic.
--   ChurchChamber  the Grand Crypt's solid core (CellaCore) is replaced by a hollow vaulted chamber behind the door
--                  (same outer faces, dark lining, ribs, candles, cobwebs, bones): room for the doors and the portal.
--   ChurchDoorL/R  the iron double door rebuilt CLOSED at the back of the door reveal as two hinge models
--                  (ModelStreamingMode Atomic, PrimaryPart = Hinge on the leaf's outer edge; attributes Side, OpenAngle
--                  (-100 / 100 degrees: both swing inward), ClosedPivot). The leaf collides, so a closed door blocks.
--                  A sealed violet emblem is split across the two leaves.
--   ChurchSlit     the sealed light slit between the closed leaves + a glow under them (attribute ChurchSlit, RevealT =
--                  idle transparency; a PointLight with Brightness 0 and RevealBrightness for the teaser's breathing).
--   ChurchPortal   the black-violet portal inside the chamber (Atomic, SelfManagedFX, attribute ChurchPortal = true,
--                  Centre, Facing): spinning rings (sub-models with Spin rad/s), a swirling disc, an inner glow, an eye
--                  pupil, floor runes, two lights. Every part is Transparency 1 in the saved place; its shown
--                  transparency is the attribute RevealT, a light's shown brightness RevealBrightness.
--   ChurchCracks   glowing fissures spreading from the door over the porch, down the stairs and across the forecourt,
--                  up the front wall (CrackGlow / CrackEdge strips, attributes CrackT = 0..1 spread order and RevealT;
--                  Transparency 1 saved). Their heights are sampled from the saved ground (stepping stones, curbs).
--   ChurchFX       invisible rails with Attachments: ChurchDust (Kind = "Roof" under the portico cornice, "Tower" at the
--                  Moon Tower's string course) and ChurchFog (the forecourt) for the client's dust / ground fog.
-- Originals that change (the solid core, the old ajar door leaves and their fittings, the dark recess panel, the green
-- floor glow and the two eyes in the recess) are hidden with K.Hide, which records Halloween_Original* once (K.Remember),
-- so World.Disable can restore them and a second run of the edit changes nothing.
local K = require(script.Parent.Kit)
local Y = require(script.Parent.YardKit)
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi
local S = Y.Solid

local Church = {}
Church.Version = 1

local STONE = C(108, 104, 122) -- the Grand Crypt cella stone (the core this replaces)
local STONE_L = C(146, 142, 158)
local LINING = C(36, 32, 48)
local FLOOR = C(27, 23, 36)
local IRON = C(46, 48, 58)
local IRON_L = C(72, 68, 78)
local RELIEF = C(80, 76, 90)
local BRASS = C(150, 120, 60)
local VIOLET = C(150, 80, 230)
local VIOLET_DIM = C(96, 46, 156)
local MOON = C(150, 200, 255)
local INK = C(16, 12, 26)

-- World geometry of the Grand Crypt (Layout.Crypts.Grand: x 114..142, z 724..742, door (128, 0.2, 724) facing -Z;
-- measured in the saved place: porch / chamber floor = PlinthCap top 2.375, the front wall CellaFront z 728.1..730.1 with
-- the 6 x 9 door opening x 125..131, lintel underside y 11.4, solid core CellaCore x 117.5..138.5 z 730..742 y 2.4..13.2)
local G = {
	FloorY = 2.375,
	DoorX0 = 125,
	DoorX1 = 131,
	OpenTop = 11.4,
	WallFront = 728.1, -- front face of the front wall
	WallBack = 730.1, -- back face of the front wall (the closed leaves sit against it)
	Chamber = { X0 = 122, X1 = 134, Z0 = 730.1, Z1 = 738.4, Y1 = 11.6 },
	Core = { X0 = 117.5, X1 = 138.5, Z1 = 742, Y0 = 2.4, Y1 = 13.2 },
	PortalCentre = V3(128, 7, 735.2),
	LeafWidth = 2.86,
	LeafHeight = 8.9,
	LeafThick = .3,
	OpenAngle = 100,
}
Church.Geometry = G

-- parts of the Grand Crypt that the chamber / the new door replace (direct children, inside the door + core box)
local REPLACED = {
	CellaCore = true, CryptDark = true, CryptEye = true, CryptGlowFloor = true, CryptDoorLeaf = true, CryptDoorBand = true,
	CryptDoorStud = true, PawPad = true, PawToe = true, CryptRing = true,
}
local function replaced(p: BasePart): boolean
	if not REPLACED[p.Name] then
		return false
	end
	local pos = p.CFrame.Position
	return pos.X > 116 and pos.X < 140 and pos.Y > 0 and pos.Y < 14 and pos.Z > 726.5 and pos.Z < 743
end

local function hidden(p: BasePart, shownTransparency: number): BasePart
	p:SetAttribute("RevealT", shownTransparency)
	p.Transparency = 1
	p.CastShadow = false
	p.CanCollide = false
	p.CanQuery = false
	return p
end

-- a flat strip from a to b lying on a surface with normal n (width across, thickness along n)
local function strip(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, thick: number, n: Vector3, color: Color3,
	material: Enum.Material, attrs: { [string]: any }?): BasePart
	local d = b - a
	local len = d.Magnitude
	local dir = d.Unit
	local side = dir:Cross(n).Unit
	local up = side:Cross(dir).Unit
	local cf = CFrame.fromMatrix((a + b) / 2, side, up, -dir)
	return K.Part(parent, name, V3(width, thick, len), cf, color, material, { Attrs = attrs })
end

------------------------------------------------------------------------------------------------------------------------
-- the chamber
------------------------------------------------------------------------------------------------------------------------
local function chamber(parent: Instance, rng: any): Model
	local m = K.Model(parent, "ChurchChamber")
	local ch, core = G.Chamber, G.Core
	local midY = (core.Y0 + core.Y1) / 2
	local h = core.Y1 - core.Y0
	-- the shell keeps the core's outer faces: two side blocks, the back block and the vault slab
	K.Part(m, "CellaWall", V3(ch.X0 - core.X0, h, core.Z1 - ch.Z0), CF((core.X0 + ch.X0) / 2, midY, (ch.Z0 + core.Z1) / 2), STONE, M.Slate, S())
	K.Part(m, "CellaWall", V3(core.X1 - ch.X1, h, core.Z1 - ch.Z0), CF((ch.X1 + core.X1) / 2, midY, (ch.Z0 + core.Z1) / 2), STONE, M.Slate, S())
	K.Part(m, "CellaWall", V3(ch.X1 - ch.X0, h, core.Z1 - ch.Z1), CF(128, midY, (ch.Z1 + core.Z1) / 2), STONE, M.Slate, S())
	K.Part(m, "CellaVault", V3(ch.X1 - ch.X0, core.Y1 - ch.Y1, ch.Z1 - ch.Z0), CF(128, (ch.Y1 + core.Y1) / 2, (ch.Z0 + ch.Z1) / 2), STONE, M.Slate, S())
	-- dark lining inside (the room reads as a deep black-violet hollow behind the door)
	local iy = (G.FloorY + ch.Y1) / 2
	local ih = ch.Y1 - G.FloorY
	local cz = (ch.Z0 + ch.Z1) / 2
	local depth = ch.Z1 - ch.Z0
	K.Part(m, "ChamberLining", V3(.12, ih, depth), CF(ch.X0 + .06, iy, cz), LINING, M.Slate)
	K.Part(m, "ChamberLining", V3(.12, ih, depth), CF(ch.X1 - .06, iy, cz), LINING, M.Slate)
	K.Part(m, "ChamberLining", V3(ch.X1 - ch.X0, ih, .12), CF(128, iy, ch.Z1 - .06), LINING, M.Slate)
	K.Part(m, "ChamberLining", V3(ch.X1 - ch.X0, .12, depth), CF(128, ch.Y1 - .06, cz), LINING, M.Slate)
	for _, sx in ipairs({ -1, 1 }) do -- the inner face of the front wall beside the door
		local w = sx < 0 and (G.DoorX0 - ch.X0) or (ch.X1 - G.DoorX1)
		local x = sx < 0 and (ch.X0 + w / 2) or (ch.X1 - w / 2)
		K.Part(m, "ChamberLining", V3(w, ih, .12), CF(x, iy, ch.Z0 + .06), LINING, M.Slate)
	end
	K.Part(m, "ChamberFloor", V3(ch.X1 - ch.X0 - .1, .06, depth - .1), CF(128, G.FloorY + .03, cz), FLOOR, M.Slate)
	-- the floor's worn rune circle (dark, not glowing: the portal's own runes light up over it)
	for i = 1, 16 do
		local a0 = (i - 1) / 16 * PI * 2
		local a1 = a0 + .75 / 16 * PI * 2
		local p0 = V3(128 + math.cos(a0) * 3.6, G.FloorY + .07, G.PortalCentre.Z + math.sin(a0) * 2.4)
		local p1 = V3(128 + math.cos(a1) * 3.6, G.FloorY + .07, G.PortalCentre.Z + math.sin(a1) * 2.4)
		strip(m, "FloorRuneGroove", p0, p1, .16, .03, V3(0, 1, 0), C(44, 34, 60), M.Slate)
	end
	-- ribbed vault: two pointed ribs springing from wall shafts
	for _, z in ipairs({ ch.Z0 + 2.1, ch.Z1 - 1.6 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local wx = sx < 0 and ch.X0 + .35 or ch.X1 - .35
			K.Part(m, "VaultShaft", V3(.5, 6.6, .5), CF(wx, G.FloorY + 3.3, z), STONE_L:Lerp(LINING, .35), M.Slate)
			K.Part(m, "VaultCapital", V3(.75, .3, .75), CF(wx, G.FloorY + 6.75, z), STONE_L:Lerp(LINING, .2), M.Slate)
			K.Bar(m, "VaultRib", V3(wx, G.FloorY + 6.85, z), V3(128, ch.Y1 - .25, z), .42, .36, STONE_L:Lerp(LINING, .3), M.Slate)
		end
		K.Part(m, "VaultBoss", V3(.7, .5, .7), CF(128, ch.Y1 - .3, z), STONE_L:Lerp(LINING, .2), M.Slate)
	end
	-- skull sconces with candles on the side walls, candles on the floor, cobwebs, a pile of bones
	for _, sx in ipairs({ -1, 1 }) do
		local wx = sx < 0 and ch.X0 + .12 or ch.X1 - .12
		local base = CF(wx, G.FloorY + 4.3, cz + .6)
		K.Part(m, "SconceBracket", V3(.7, .16, .5), base * CF(-sx * .35, 0, 0), IRON, M.CorrodedMetal)
		K.Part(m, "SconcePlate", V3(.08, 1.1, .7), base * CF(-sx * .04, .25, 0), IRON_L, M.CorrodedMetal)
		Y.Skull(m, base * CF(-sx * .62, .38, 0) * ANG(0, sx * PI / 2, 0), .62, Y.GLOW_DIM.Purple, C(196, 186, 162))
		K.Candles(m, base * CF(-sx * .62, .75, 0), 1, rng, { Light = false, Spread = .05 })
		K.Candles(m, CF(sx < 0 and ch.X0 + 1.1 or ch.X1 - 1.1, G.FloorY + .06, ch.Z1 - .9), 3, rng, { Light = false, Spread = .45 })
		Y.Cobweb(m, CF(sx < 0 and ch.X0 + .15 or ch.X1 - .15, ch.Y1 - .15, ch.Z1 - .15) * ANG(0, sx < 0 and 0 or PI, 0), 1.5)
	end
	Y.BonePile(m, CF(ch.X0 + 1.3, G.FloorY + .04, ch.Z0 + 1.6), rng, 5, true)
	return m
end

------------------------------------------------------------------------------------------------------------------------
-- the doors (closed): hinge on the leaf's outer edge, +x' towards the door centre, -z' out to the porch
------------------------------------------------------------------------------------------------------------------------
local function door(parent: Instance, side: number): Model
	local m = K.Model(parent, side < 0 and "ChurchDoorL" or "ChurchDoorR")
	local hx = side < 0 and G.DoorX0 or G.DoorX1
	local cy = G.FloorY + .05 + G.LeafHeight / 2
	local hinge = CF(hx, cy, G.WallBack - .02 - G.LeafThick / 2)
	local function at(x: number, y: number, z: number): CFrame
		return hinge * CF(-side * x, y, z)
	end
	local w, hh = G.LeafWidth, G.LeafHeight / 2
	local pin = K.Part(m, "Hinge", V3(.3, G.LeafHeight, .3), hinge, IRON, M.CorrodedMetal)
	K.Part(m, "Leaf", V3(w, G.LeafHeight, G.LeafThick), at(w / 2, 0, 0), IRON, M.CorrodedMetal, S())
	-- frame: rails, stiles and three riveted bands on the outer face
	K.Part(m, "LeafStile", V3(.22, G.LeafHeight, .1), at(w - .11, 0, -.19), IRON_L, M.CorrodedMetal)
	K.Part(m, "LeafRail", V3(w, .26, .1), at(w / 2, hh - .13, -.19), IRON_L, M.CorrodedMetal)
	K.Part(m, "LeafKick", V3(w, .6, .1), at(w / 2, -hh + .3, -.19), IRON_L, M.CorrodedMetal)
	for _, y in ipairs({ -2.9, 0, 2.9 }) do
		K.Part(m, "LeafBand", V3(w, .3, .12), at(w / 2, y, -.2), IRON_L, M.CorrodedMetal)
		for k = 0, 3 do
			K.Ball(m, "LeafRivet", .16, at(.35 + k * (w - .6) / 3, y, -.27), C(98, 92, 84), M.Metal)
		end
	end
	-- strap hinges with knuckles on the pin
	for _, y in ipairs({ -2.35, 2.35 }) do
		K.Part(m, "StrapHinge", V3(1.8, .24, .1), at(.9, y, -.22), IRON, M.CorrodedMetal)
		K.Ball(m, "StrapCurl", .34, at(1.82, y, -.23), IRON, M.CorrodedMetal)
		K.CylY(m, "HingeKnuckle", .7, .42, at(0, y, 0), IRON_L, M.Metal)
	end
	-- dog-paw relief and the ring knocker
	K.Ball(m, "PawPad", .9, at(1.45, 1.15, -.2), RELIEF, M.CorrodedMetal)
	for t = -1, 1 do
		K.Ball(m, "PawToe", .42, at(1.45 + t * .45, 1.9 + (t == 0 and .12 or 0), -.2), RELIEF, M.CorrodedMetal)
	end
	K.Ball(m, "KnockerBoss", .38, at(w - .5, -.35, -.24), BRASS, M.Metal)
	K.CylZ(m, "KnockerRing", .12, .74, at(w - .5, -.78, -.28), BRASS, M.Metal)
	-- half of the seal: a broken ring of dim violet runes round the door centre (both halves meet when closed)
	local ex, ey = w + .14, 1.6 -- emblem centre in leaf space (the door centre line, two thirds up the door)
	for k = 0, 4 do
		local a = PI / 2 + (k + .5) / 5 * PI
		local r = .95
		K.Part(m, "SealRune", V3(.46, .16, .06), at(ex + math.cos(a) * r, ey + math.sin(a) * r, -.18) * ANG(0, 0, -side * (a + PI / 2)), VIOLET_DIM,
			M.Neon, { Attrs = { SealRune = true } })
	end
	K.Part(m, "SealEye", V3(.12, .9, .06), at(w - .06, ey, -.18), VIOLET_DIM, M.Neon, { Attrs = { SealRune = true } })
	m.PrimaryPart = pin
	pcall(function()
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	m:SetAttribute("ChurchDoor", true)
	m:SetAttribute("Side", side < 0 and "L" or "R")
	m:SetAttribute("OpenAngle", side < 0 and -G.OpenAngle or G.OpenAngle)
	m:SetAttribute("ClosedPivot", hinge)
	return m
end

------------------------------------------------------------------------------------------------------------------------
-- the sealed slit of light between the leaves (the teaser breathes it)
------------------------------------------------------------------------------------------------------------------------
local function slit(parent: Instance)
	local s = K.Part(parent, "ChurchSlit", V3(.18, G.LeafHeight - .3, .06), CF(128, G.FloorY + .05 + G.LeafHeight / 2, G.WallBack + .03), C(120, 58, 196),
		M.Neon, { Transparency = .25, Attrs = { ChurchSlit = true, RevealT = .25, SelfManagedFX = true } })
	local light = K.Light(s, C(170, 110, 255), 13, 0)
	light:SetAttribute("RevealBrightness", 1.7)
	-- the glow that leaks under the doors onto the threshold
	K.Part(parent, "ChurchSlitSill", V3(G.DoorX1 - G.DoorX0 - .4, .03, .34), CF(128, G.FloorY + .016, G.WallBack - .5), C(104, 52, 170), M.Neon,
		{ Transparency = .55, Attrs = { ChurchSlit = true, RevealT = .55 } })
end

------------------------------------------------------------------------------------------------------------------------
-- the portal (hidden): faces -Z, the door; rings spin round the Z axis through Centre
------------------------------------------------------------------------------------------------------------------------
local function ringOf(parent: Instance, name: string, centre: CFrame, r: number, n: number, thick: number, depth: number, color: Color3,
	material: Enum.Material, shownT: number, z: number)
	local seg = 2 * PI * r / n * 1.06
	for k = 1, n do
		local a = (k - .5) / n * 2 * PI
		local cf = centre * CF(math.cos(a) * r, math.sin(a) * r, z) * ANG(0, 0, a + PI / 2)
		hidden(K.Part(parent, name, V3(seg, thick, depth), cf, color, material), shownT)
	end
end

local function portal(parent: Instance): Model
	local m = K.Model(parent, "ChurchPortal")
	local pc = G.PortalCentre
	local O = CF(pc)
	-- outer iron ring with rune studs (slow), violet ring (fast), moon-blue inner ring (counter-spin)
	local ringA = K.Model(m, "PortalRingA")
	ringA:SetAttribute("Spin", .12)
	ringOf(ringA, "PortalRing", O, 4.25, 20, .5, .55, C(46, 38, 62), M.Metal, 0, -.15)
	for k = 0, 3 do
		local a = PI / 4 + k * PI / 2
		hidden(K.Part(ringA, "PortalRuneStud", V3(.52, .52, .3), O * CF(math.cos(a) * 4.25, math.sin(a) * 4.25, -.45) * ANG(0, 0, a + PI / 4), VIOLET, M.Neon), 0)
	end
	local ringB = K.Model(m, "PortalRingB")
	ringB:SetAttribute("Spin", .55)
	ringB:SetAttribute("Wobble", .08)
	ringOf(ringB, "PortalRing", O, 3.8, 18, .24, .32, VIOLET, M.Neon, .05, -.1)
	local ringC = K.Model(m, "PortalRingC")
	ringC:SetAttribute("Spin", -.8)
	ringOf(ringC, "PortalRing", O, 3.38, 16, .16, .22, MOON, M.Neon, .15, -.05)
	-- the deep disc, its dark backing and the inner glow
	hidden(K.CylZ(m, "PortalBacking", .1, 7.6, O * CF(0, 0, .45), INK, M.SmoothPlastic), 0)
	hidden(K.CylZ(m, "PortalDisc", .12, 6.9, O * CF(0, 0, .3), C(42, 14, 82), M.Neon), .02)
	hidden(K.CylZ(m, "PortalGlow", .06, 3.1, O * CF(0, 0, .1), C(214, 182, 255), M.Neon), .3)
	-- three spiral arms swirling into the core
	local swirl = K.Model(m, "PortalSwirl")
	swirl:SetAttribute("Spin", 1.3)
	for arm = 0, 2 do
		local a0 = arm * 2 * PI / 3
		local prev: Vector3? = nil
		for k = 0, 7 do
			local t = k / 7
			local r = .55 + 2.75 * t
			local a = a0 + 2.7 * t
			local p = (O * CF(math.cos(a) * r, math.sin(a) * r, .18)).Position
			if prev then
				local part = strip(swirl, "PortalSwirlArm", prev, p, .26 - .12 * t, .05, V3(0, 0, -1), C(196, 150, 255), M.Neon)
				hidden(part, .08 + .4 * t)
			end
			prev = p
		end
	end
	-- the core, its lights and the eye's pupil
	local coreBall = hidden(K.Ball(m, "PortalCore", 1.05, O, C(244, 234, 255), M.Neon), .12)
	local glow = K.Light(coreBall, C(170, 110, 255), 26, 0)
	glow:SetAttribute("RevealBrightness", 2.4)
	local wash = K.Light(coreBall, C(150, 90, 240), 44, 0, "SpotLight") :: SpotLight
	wash.Face = Enum.NormalId.Front
	wash.Angle = 75
	wash:SetAttribute("RevealBrightness", 3)
	K.Attach(coreBall, "PortalSuck", CF())
	hidden(K.Ellipsoid(m, "PortalPupil", V3(.42, 1.9, .14), O * CF(0, 0, -.62), C(8, 2, 16), M.SmoothPlastic), 0)
	-- glowing runes on the chamber floor round the portal's foot
	for i = 1, 12 do
		local a0 = (i - 1) / 12 * PI * 2 + .1
		local a1 = a0 + .55 / 12 * PI * 2
		local y = G.FloorY + .1
		local p0 = V3(128 + math.cos(a0) * 3.6, y, pc.Z + math.sin(a0) * 2.4)
		local p1 = V3(128 + math.cos(a1) * 3.6, y, pc.Z + math.sin(a1) * 2.4)
		hidden(strip(m, "PortalFloorRune", p0, p1, .2, .04, V3(0, 1, 0), VIOLET, M.Neon), .15)
	end
	pcall(function()
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	m:SetAttribute("ChurchPortal", true)
	m:SetAttribute("SelfManagedFX", true)
	m:SetAttribute("Centre", pc)
	m:SetAttribute("Facing", V3(0, 0, -1))
	return m
end

------------------------------------------------------------------------------------------------------------------------
-- the cracks (hidden): sampled heights over the saved ground
------------------------------------------------------------------------------------------------------------------------
-- highest top of a block-shaped part under (x, z) below maxY, from a candidate list (nil: none)
local function surfaceAt(parts: { BasePart }, x: number, z: number, maxY: number): number?
	local best: number? = nil
	for _, p in ipairs(parts) do
		local cf = p.CFrame
		local half = p.Size / 2
		local o = cf:PointToObjectSpace(V3(x, 0, z))
		local u = cf:VectorToObjectSpace(V3(0, 1, 0))
		local lo, hi = -math.huge, math.huge
		local inside = true
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			local p0, du, h = (o :: any)[axis], (u :: any)[axis], (half :: any)[axis]
			if math.abs(du) < 1e-6 then
				if math.abs(p0) > h then
					inside = false
					break
				end
			else
				local a, b = (-h - p0) / du, (h - p0) / du
				lo, hi = math.max(lo, math.min(a, b)), math.min(hi, math.max(a, b))
			end
		end
		if inside and lo <= hi and hi <= maxY and (best == nil or hi > (best :: number)) then
			best = hi
		end
	end
	return best
end

-- the crack network, spreading from the door: Kind "Ground" = (x, z) polylines lying on the sampled ground (porch,
-- crypt walk, forecourt), "Step" = explicit (x, y, z) points running over the three stairs (treads flat, risers upright),
-- "Wall" = (x, y) polylines on the front wall's face. From = {index of the polyline it splits from, point index}.
local CRACKS = {
	{ Name = "Porch", Kind = "Ground", Pts = { { 128, 729.4 }, { 127.6, 728.0 }, { 128.5, 726.9 }, { 127.8, 725.9 }, { 128.15, 724.9 },
		{ 128.1, 724.3 } } },
	{ Name = "Stairs", Kind = "Step", From = { 1, 6 }, Pts = { { 128.1, 2.33, 724.25 }, { 127.98, 2.33, 723.15 }, { 127.92, 1.63, 723.1 },
		{ 128.12, 1.63, 721.99 }, { 128.18, .93, 721.95 }, { 128.3, .93, 720.84 }, { 128.3, .62, 720.8 } } },
	{ Name = "Walk", Kind = "Ground", From = { 2, 7 }, Pts = { { 128.3, 720.6 }, { 128.6, 718.8 }, { 127.4, 716.6 }, { 128.3, 714.6 },
		{ 127.7, 712.3 }, { 128.4, 710.0 }, { 127.9, 708.2 } } },
	{ Name = "ForecourtW", Kind = "Ground", From = { 3, 4 }, Pts = { { 128.3, 714.6 }, { 126.8, 713.2 }, { 124.9, 712.6 }, { 122.6, 711.3 },
		{ 120.1, 711.7 }, { 117.4, 710.3 }, { 115.2, 710.8 } } },
	{ Name = "ForecourtE", Kind = "Ground", From = { 3, 4 }, Pts = { { 128.3, 714.6 }, { 129.9, 712.9 }, { 131.6, 711.6 }, { 133.6, 710.4 },
		{ 136.6, 710.9 }, { 139.6, 709.4 }, { 141.4, 709.9 } } },
	{ Name = "ForecourtSW", Kind = "Ground", From = { 3, 2 }, Pts = { { 128.6, 718.8 }, { 126.4, 718.1 }, { 124.6, 718.6 }, { 122.4, 717.9 } } },
	{ Name = "ForecourtSE", Kind = "Ground", From = { 3, 1 }, Pts = { { 128.3, 720.6 }, { 130.0, 719.6 }, { 131.9, 719.9 }, { 133.6, 719.0 } } },
	{ Name = "PorchW", Kind = "Ground", From = { 1, 2 }, Pts = { { 127.6, 728.0 }, { 126.0, 727.4 }, { 124.2, 727.6 }, { 122.3, 727.1 },
		{ 120.2, 727.5 }, { 118.1, 727.0 } } },
	{ Name = "PorchE", Kind = "Ground", From = { 1, 2 }, Pts = { { 127.6, 728.0 }, { 129.8, 727.3 }, { 131.9, 727.6 }, { 133.8, 727.1 },
		{ 135.9, 727.5 }, { 137.9, 727.0 } } },
	{ Name = "WallW", Kind = "Wall", From = { 8, 3 }, Pts = { { 123.3, 2.4 }, { 123.0, 3.6 }, { 123.4, 4.7 }, { 122.9, 5.9 }, { 123.2, 6.9 },
		{ 122.8, 7.6 } } },
	{ Name = "WallE", Kind = "Wall", From = { 9, 3 }, Pts = { { 132.7, 2.4 }, { 133.0, 3.5 }, { 132.6, 4.8 }, { 133.1, 5.8 }, { 132.8, 6.7 },
		{ 133.2, 7.5 } } },
}
Church.Cracks = CRACKS

local function crackLength(a: { number }, b: { number }): number
	local s = 0
	for i = 1, #a do
		s += (b[i] - a[i]) ^ 2
	end
	return math.sqrt(s)
end

local function cracks(parent: Instance, groundParts: { BasePart }): Model
	local m = K.Model(parent, "ChurchCracks")
	-- distance along the network from the door for every polyline point (the spread order)
	local dist: { { number } } = {}
	for i, list in ipairs(CRACKS) do
		local out = { list.From and dist[list.From[1]][list.From[2]] or 0 }
		for k = 2, #list.Pts do
			out[k] = out[k - 1] + crackLength(list.Pts[k - 1], list.Pts[k])
		end
		dist[i] = out
	end
	local maxD = 0
	for _, d in ipairs(dist) do
		maxD = math.max(maxD, d[#d])
	end
	local glowColor = C(176, 108, 255)
	local function piece(p0: Vector3, p1: Vector3, n: Vector3, w: number, ct: number)
		hidden(strip(m, "CrackEdge", p0, p1, w + .22, .04, n, INK, M.SmoothPlastic, { CrackT = ct }), 0)
		hidden(strip(m, "CrackGlow", p0 + n * .012, p1 + n * .012, w, .04, n, glowColor, M.Neon, { CrackT = ct }), .05)
	end
	local up, face = V3(0, 1, 0), V3(0, 0, -1)
	local function ground(x: number, z: number): number
		return surfaceAt(groundParts, x, z, 3) or .2
	end
	for i, list in ipairs(CRACKS) do
		local d = dist[i]
		for k = 2, #list.Pts do
			local a, b = list.Pts[k - 1], list.Pts[k]
			local taper = 1 - .55 * (d[k] / maxD)
			local w = (.3 + .08 * math.sin(k * 1.7 + i)) * taper
			if list.Kind == "Ground" then
				-- cut into short pieces that hug the stepped ground (stepping stones, curbs)
				local pieces = math.max(1, math.ceil(crackLength(a, b) / .85))
				for j = 1, pieces do
					local t0, t1 = (j - 1) / pieces, j / pieces
					local x0, z0 = a[1] + (b[1] - a[1]) * t0, a[2] + (b[2] - a[2]) * t0
					local x1, z1 = a[1] + (b[1] - a[1]) * t1, a[2] + (b[2] - a[2]) * t1
					local y = math.max(ground(x0, z0), ground(x1, z1), ground((x0 + x1) / 2, (z0 + z1) / 2))
					piece(V3(x0, y + .03, z0), V3(x1, y + .03, z1), up, w, (d[k - 1] + (d[k] - d[k - 1]) * (t0 + t1) / 2) / maxD)
				end
			elseif list.Kind == "Step" then
				local vertical = math.abs(b[2] - a[2]) > math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
				piece(V3(a[1], a[2], a[3]), V3(b[1], b[2], b[3]), vertical and face or up, w, ((d[k - 1] + d[k]) / 2) / maxD)
			else
				piece(V3(a[1], a[2], G.WallFront - .02), V3(b[1], b[2], G.WallFront - .02), face, w * .9, ((d[k - 1] + d[k]) / 2) / maxD)
			end
		end
	end
	m:SetAttribute("ChurchCracks", true)
	return m
end

------------------------------------------------------------------------------------------------------------------------
-- FX rails (invisible, attachments only)
------------------------------------------------------------------------------------------------------------------------
local function rail(parent: Instance, name: string, cf: CFrame): BasePart
	local p = K.Part(parent, name, V3(.4, .4, .4), cf, INK, M.SmoothPlastic, { Transparency = 1 })
	p.CastShadow = false
	return p
end

local function fxRails(parent: Instance): Model
	local m = K.Model(parent, "ChurchFX")
	m:SetAttribute("SelfManagedFX", true)
	-- dust under the portico cornice (front face z ~723.8, underside y ~15.9) and at the Moon Tower's string course
	local roof = rail(m, "ChurchDustRoof", CF(128, 15.7, 723.7))
	for k = -3, 3 do
		Y.AttachAt(roof, "ChurchDust", V3(128 + k * 3.6, 15.7, 723.7), { Kind = "Roof" })
	end
	local tower = rail(m, "ChurchDustTower", CF(128, 26, 737.5))
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		Y.AttachAt(tower, "ChurchDust", V3(128 + c[1] * 5.7, 26, 737.5 + c[2] * 5.7), { Kind = "Tower" })
	end
	-- ground fog on the forecourt and the porch
	local fog = rail(m, "ChurchFogRail", CF(128, .6, 714))
	for _, p in ipairs({ { -9, .6, 708 }, { 0, .6, 706 }, { 9, .6, 708 }, { -6, .7, 716 }, { 6, .7, 716 }, { 0, 2.6, 726.5 } }) do
		Y.AttachAt(fog, "ChurchFog", V3(128 + p[1], p[2], p[3]), {})
	end
	return m
end

------------------------------------------------------------------------------------------------------------------------
-- Build(ctx): ctx = {Root = 38_DeadYard, Note(text)?}; returns the Church model (and a report table)
------------------------------------------------------------------------------------------------------------------------
function Church.Build(ctx: any): (Model?, { [string]: any })
	local yard = ctx.Root
	local report: { [string]: any } = {}
	local crypts = yard:FindFirstChild("Crypts")
	local crypt = crypts and crypts:FindFirstChild("GrandCrypt")
	if not crypt then
		report.Skipped = "38_DeadYard.Crypts.GrandCrypt missing"
		return nil, report
	end
	local old = yard:FindFirstChild("Church")
	if old then
		old:Destroy()
	end
	-- 1. hide the parts the chamber and the new doors replace (originals recorded once)
	local hiddenCount = 0
	for _, child in ipairs(crypt:GetChildren()) do
		if child:IsA("BasePart") and replaced(child) then
			K.Hide(child)
			child.CastShadow = false
			hiddenCount += 1
		end
	end
	report.Hidden = hiddenCount
	-- 2. ground candidates for the crack heights: visible block parts round the forecourt below y 3 (slabs, curbs,
	--    stairs, the porch), the church's own replaced parts excluded
	local ground: { BasePart } = {}
	for _, d in ipairs(yard:GetDescendants()) do
		if d:IsA("Part") and d.Shape == Enum.PartType.Block and d.Transparency < .5 and d:GetAttribute("Halloween_Changed") == nil then
			local pos = d.CFrame.Position
			local s = d.Size
			if pos.X > 104 and pos.X < 152 and pos.Z > 700 and pos.Z < 732 and pos.Y < 3 and (d.CanCollide or (s.X >= 1.2 and s.Z >= 1.2)) then
				table.insert(ground, d)
			end
		end
	end
	-- 3. the church model
	local root = K.Model(yard, "Church")
	local rng = Y.Rng(3801)
	chamber(root, rng)
	door(root, -1)
	door(root, 1)
	slit(root)
	portal(root)
	cracks(root, ground)
	fxRails(root)
	root:SetAttribute("ChurchEdit", Church.Version)
	-- 4. the DESCEND prompt anchor (Underyard.luau creates the prompt on it at runtime)
	local anchors = yard:FindFirstChild("Anchors")
	if not anchors then
		anchors = K.Model(yard, "Anchors")
	end
	local anchor = anchors:FindFirstChild("Portal")
	if not anchor then
		anchor = K.Part(anchors, "Portal", V3(1, 1, 1), CF(128, 3, 729), C(150, 80, 230), M.SmoothPlastic, { Transparency = 1 })
		anchor.CastShadow = false
		report.AnchorCreated = true
	end
	local parts, lights = 0, 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	root:SetAttribute("Parts", parts)
	report.Parts, report.Lights, report.Ground = parts, lights, #ground
	if ctx.Note then
		ctx.Note(string.format("Church: %d parts, %d lights, %d originals hidden", parts, lights, hiddenCount))
	end
	return root, report
end

return Church
