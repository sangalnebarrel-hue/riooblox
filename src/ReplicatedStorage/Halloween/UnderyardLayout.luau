-- THE UNDERYARD — every coordinate of Chapter II (ReplicatedStorage.Halloween.UnderyardLayout). Pure data + helpers,
-- shared by the offline builders (ServerStorage.UnderyardBuild through tools/edits/40_underyard.luau), the server
-- (Underyard / Seals / Coffin / Resonance) and the client (UnderyardFX, trials). Builders place geometry AROUND these
-- points and never move them; gameplay reads them from here (or from the saved Anchors parts of the same names).
--
-- Placement: centre (0, 0, 2400), floor top y = 0, far south of the island (z 775) and outside the client streaming
-- radius (1024) of every playable area; above DistrictSafety's y -85 floor. Axis convention: "north" = -Z (towards the
-- island / the arrival arch), "south" = +Z (towards the Black Bell Arena).
local V = Vector3.new

local L = {}

L.Centre = V(0, 0, 2400)
L.Floor = 0
L.Zone = { Min = V(-230, -40, 2160), Max = V(230, 170, 2720) }
L.Bounds = { X0 = -222, X1 = 222, Z0 = 2168, Z1 = 2712 } -- playable boundary (cliffs + invisible colliders outside)

-- Church side (THE DEAD YARD, Chapter I zone): the Grand Crypt + Moon Tower act as the church.
L.Church = {
	Door = V(128, 0.2, 724), -- crypt threshold (doors face -Z, towards the pit)
	Portal = V(128, 3, 729), -- server prompt anchor 38_DeadYard.Anchors.Portal ("DESCEND")
	PortalCentre = V(128, 5.2, 732), -- visual portal disc centre (inside the crypt)
	Forecourt = V(128, 3, 712), -- return point when ascending
	Bell = V(128, 36.3, 737.5), -- Moon Tower bell
	TriggerRadius = 46, -- first approach plays the church cinematic
	TeaserRadius = 70,
	Shot = { From = V(150, 9, 690), At = V(128, 16, 728) }, -- default cinematic framing (client may refine)
}

-- Arrival / return portal (Bell Square, north edge)
L.Arrival = CFrame.lookAt(V(0, 3.2, 2352), V(0, 3.2, 2400)) -- facing the bell tower (south)
L.ArrivalArch = V(0, 0, 2342)
L.ReturnPrompt = V(0, 3, 2345)

-- District presence boxes (axis aligned) and circles
L.Districts = {
	{ Name = "BellSquare", Kind = "Circle", Centre = V(0, 0, 2400), Radius = 84, Y0 = -10, Y1 = 140 },
	{ Name = "BlackBellArena", Kind = "Box", Min = V(-70, -12, 2486), Max = V(70, 140, 2712) },
	{ Name = "FuneralCarnival", Kind = "Box", Min = V(75, -12, 2168), Max = V(222, 120, 2330) },
	{ Name = "CrookedRow", Kind = "Box", Min = V(-222, -12, 2168), Max = V(-75, 120, 2330) },
	{ Name = "MourningMarsh", Kind = "Box", Min = V(-222, -12, 2470), Max = V(-75, 120, 2712) },
	{ Name = "Undercrypt", Kind = "Box", Min = V(75, -40, 2470), Max = V(222, 120, 2712) },
}
L.DistrictOrder = { "BellSquare", "FuneralCarnival", "MourningMarsh", "Undercrypt", "CrookedRow", "BlackBellArena" }
-- seals needed to enter a district (per player): Carnival after I, Marsh after II, Undercrypt after III,
-- Crooked Row after IV, Arena after VI. Bell Square is always open.
L.Unlock = { BellSquare = 0, FuneralCarnival = 1, MourningMarsh = 2, Undercrypt = 3, CrookedRow = 4, BlackBellArena = 6 }
L.Names = {
	BellSquare = { "BELL SQUARE", "КОЛОКОЛЬНАЯ ПЛОЩАДЬ" },
	FuneralCarnival = { "FUNERAL CARNIVAL", "ПОХОРОННЫЙ КАРНАВАЛ" },
	MourningMarsh = { "MOURNING MARSH", "ТРАУРНАЯ ТОПЬ" },
	Undercrypt = { "UNDERCRYPT", "ПОДКЛЕПЬЕ" },
	CrookedRow = { "CROOKED ROW", "КРИВОЙ РЯД" },
	BlackBellArena = { "BLACK BELL ARENA", "АРЕНА ЧЁРНОГО КОЛОКОЛА" },
}

-- Gates on the ring road (veiled arch; the arch opening faces the district)
L.Gates = {
	FuneralCarnival = { Position = V(68, 0, 2332), Facing = V(1, 0, -1).Unit },
	CrookedRow = { Position = V(-68, 0, 2332), Facing = V(-1, 0, -1).Unit },
	MourningMarsh = { Position = V(-68, 0, 2468), Facing = V(-1, 0, 1).Unit },
	Undercrypt = { Position = V(68, 0, 2468), Facing = V(1, 0, 1).Unit },
	BlackBellArena = { Position = V(0, 0, 2486), Facing = V(0, 0, 1) },
}

-- BELL SQUARE
L.Square = {
	Plaza = { Centre = V(0, 0, 2400), Radius = 62 },
	RingRoad = { Inner = 66, Outer = 82 },
	Tower = { Centre = V(0, 0, 2400), Half = 12, Height = 92, BellY = 70 }, -- broken bell tower
	AltarRadius = 34,
	CoffinShrine = CFrame.lookAt(V(-44, 0, 2400), V(0, 0, 2400)), -- Black Coffin on its shrine, facing the tower
	ContractsBoard = CFrame.lookAt(V(44, 0, 2378), V(0, 0, 2400)),
	TollBox = CFrame.lookAt(V(44, 0, 2422), V(0, 0, 2400)),
	PracticeRing = { Centre = V(0, 0, 2462), Radius = 11 },
	TutorialBell = V(0, 0, 2472),
	Mourner = V(0, 0, 2462),
	Tailor = CFrame.lookAt(V(-40, 0, 2440), V(0, 0, 2400)), -- fragments craft stall
}

local function ring(centre: Vector3, radius: number, count: number, phase: number?): { Vector3 }
	local out = {}
	for i = 1, count do
		local a = (phase or 0) + (i - 1) * 2 * math.pi / count
		table.insert(out, centre + V(math.sin(a) * radius, 0, -math.cos(a) * radius))
	end
	return out
end
L.Ring = ring

L.SealAltars = ring(L.Square.Tower.Centre, L.Square.AltarRadius, 7, 0) -- altar 1 = north (towards the arrival)

L.EchoPoints = {}
for _, p in ipairs(ring(L.Centre, 47, 8, math.pi / 8)) do
	table.insert(L.EchoPoints, p)
end
for _, p in ipairs(ring(L.Centre, 57, 8, 0)) do
	table.insert(L.EchoPoints, p)
end
L.TutorialEchoes = { V(-24, 0, 2372), V(26, 0, 2376), V(-20, 0, 2440) }
L.ResonantEchoes = ring(L.Centre, 40, 6, math.pi / 6)

-- FUNERAL CARNIVAL (Seal II: FUNERAL RUN)
L.Carnival = {
	Tent = { Centre = V(160, 0, 2240), Radius = 22 },
	Carousel = { Centre = V(105, 0, 2215), Radius = 13 },
	FerrisWheel = V(196, 0, 2304),
	TicketBooth = V(84, 0, 2322),
	RunStart = V(90, 0, 2316),
	Checkpoints = {
		V(115, 0, 2300), V(150, 0, 2296), V(190, 0, 2280), V(202, 0, 2240), V(182, 0, 2198),
		V(140, 0, 2190), V(119, 0, 2215), V(91, 0, 2215), V(100, 0, 2262), V(126, 0, 2264),
	},
	Pendulums = { V(132, 0, 2298), V(201, 0, 2262), V(160, 0, 2193) },
	CheckpointRadius = 7,
}

-- MOURNING MARSH (Seal III: MIRROR GRAVES)
L.Marsh = {
	GroundY = -1.5, WaterY = -0.6, BoardwalkY = 0.5,
	Pond = { Centre = V(-142, 0, 2548), Radius = 14 },
	Consult = V(-142, 0.5, 2526), -- north shore stone ("CONSULT THE POND")
	GraveRadius = 24,
}
L.MirrorGraves = ring(L.Marsh.Pond.Centre, L.Marsh.GraveRadius, 6, 0)

-- UNDERCRYPT (Seal IV: HOLLOW MINE)
L.Undercrypt = {
	Entrance = V(100, 0, 2488),
	FloorY = -16,
	Floor = { Min = V(110, -16, 2515), Max = V(205, -16, 2615) },
	Spawn = V(118, -15.5, 2525), -- mine-edge respawn (bleed-out / run start)
	RampTop = V(104, 0, 2500), RampBottom = V(118, -16, 2522),
}
L.MineNodes = {
	V(132, -16, 2534), V(156, -16, 2528), V(184, -16, 2536), V(196, -16, 2560), V(178, -16, 2566), V(150, -16, 2558),
	V(124, -16, 2566), V(122, -16, 2596), V(146, -16, 2604), V(172, -16, 2600), V(196, -16, 2596), V(160, -16, 2582),
}

-- CROOKED ROW (Seal V: CROOKED DOORS)
L.Crooked = {
	WallZ = 2215, -- the door wall's front face; doors open towards +Z (the court)
	Doors = { V(-180, 0, 2216), V(-158, 0, 2216), V(-136, 0, 2216), V(-114, 0, 2216) },
	Court = { Centre = V(-148, 0, 2262), Radius = 26 },
	RareRoom = { Centre = V(-148, 0, 2190), Spawn = V(-148, 0.6, 2196), Half = V(16, 10, 12) }, -- sealed, teleport only
	Doorkeeper = V(-148, 0, 2262),
}

-- BLACK BELL ARENA (Seal VII: LAST BELL TRIAL, BLACK BELL ASSAULT)
L.Arena = {
	Centre = V(0, 0, 2625),
	Radius = 52,
	Bell = V(0, 58, 2625), -- hanging Black Bell centre
	Chains = { N = V(0, 0, 2585), E = V(40, 0, 2625), S = V(0, 0, 2665), W = V(-40, 0, 2625) },
	Spawn = V(0, 0.6, 2580), -- arena-edge respawn
	Bellkeeper = V(0, 0, 2640),
	Approach = { From = V(0, 0, 2486), To = V(0, 0, 2573), Width = 18 },
}

-- CHOIR HUNT (Seal VI): spirit wander points across the districts unlocked by seals I-V (+ ring road)
L.ChoirPaths = {
	V(-36, 0, 2352), V(52, 0, 2420), V(-50, 0, 2452), -- Bell Square
	V(120, 0, 2290), V(186, 0, 2218), V(98, 0, 2244), -- Carnival
	V(-110, 0.5, 2500), V(-176, 0.5, 2532), V(-150, 0.5, 2590), -- Marsh
	V(140, -16, 2545), V(188, -16, 2580), V(130, -16, 2605), -- Undercrypt mine floor
	V(-100, 0, 2300), V(-190, 0, 2290), V(-160, 0, 2245), -- Crooked Row
	V(74, 0, 2380), V(-76, 0, 2420), V(0, 0, 2322), V(60, 0, 2470), V(-60, 0, 2340), V(0, 0, 2478), -- ring road
}

-- Anchor parts saved in 40_Underyard.Anchors (name -> position). Built by the world framework; read with
-- UnderyardLayout.Anchor(name) server/client side (falls back to the data above when the part is streamed out).
L.Anchors = {}
local function add(name: string, pos: Vector3)
	L.Anchors[name] = pos
end
add("Arrival", L.Arrival.Position)
add("ReturnPortal", L.ReturnPrompt)
add("CoffinShrine", L.Square.CoffinShrine.Position + V(0, 3, 0))
add("ContractsBoard", L.Square.ContractsBoard.Position + V(0, 3, 0))
add("TollBox", L.Square.TollBox.Position + V(0, 3, 0))
add("Tailor", L.Square.Tailor.Position + V(0, 3, 0))
add("PracticeRing", L.Square.PracticeRing.Centre + V(0, 1, 0))
add("TutorialBell", L.Square.TutorialBell + V(0, 2.5, 0))
add("Mourner", L.Square.Mourner + V(0, 3, 0))
add("TowerBell", L.Square.Tower.Centre + V(0, L.Square.Tower.BellY, 0))
for i, p in ipairs(L.SealAltars) do
	add("SealAltar_" .. i, p + V(0, 3, 0))
end
for i, p in ipairs(L.EchoPoints) do
	add("EchoPoint_" .. i, p)
end
for i, p in ipairs(L.TutorialEchoes) do
	add("TutorialEcho_" .. i, p)
end
for i, p in ipairs(L.ResonantEchoes) do
	add("ResonantEcho_" .. i, p)
end
for name, g in pairs(L.Gates) do
	add("Gate_" .. name, g.Position + V(0, 3, 0))
end
add("RunStart", L.Carnival.RunStart + V(0, 3, 0))
for i, p in ipairs(L.Carnival.Checkpoints) do
	add("RunCheckpoint_" .. i, p + V(0, 3, 0))
end
for i, p in ipairs(L.Carnival.Pendulums) do
	add("RunPendulum_" .. i, p)
end
add("RunCarousel", L.Carnival.Carousel.Centre)
add("PondConsult", L.Marsh.Consult + V(0, 2.5, 0))
add("MirrorPond", L.Marsh.Pond.Centre)
for i, p in ipairs(L.MirrorGraves) do
	add("MirrorGrave_" .. i, p + V(0, 3, 0))
end
add("MineEntrance", L.Undercrypt.Entrance + V(0, 3, 0))
add("MineSpawn", L.Undercrypt.Spawn)
for i, p in ipairs(L.MineNodes) do
	add("MineNode_" .. i, p)
end
for i, p in ipairs(L.Crooked.Doors) do
	add("Door_" .. i, p + V(0, 3.5, 1.5))
end
add("DoorCourt", L.Crooked.Court.Centre)
add("RareRoom", L.Crooked.RareRoom.Spawn)
add("ArenaCentre", L.Arena.Centre)
add("ArenaSpawn", L.Arena.Spawn)
add("BlackBell", L.Arena.Bell)
add("Bellkeeper", L.Arena.Bellkeeper)
for k, p in pairs(L.Arena.Chains) do
	add("Chain_" .. k, p + V(0, 2, 0))
end
for i, p in ipairs(L.ChoirPaths) do
	add("ChoirPath_" .. i, p + V(0, 3, 0))
end

-- helpers --------------------------------------------------------------------------------------------------------
function L.InZone(pos: Vector3, margin: number?): boolean
	local m = margin or 0
	local a, b = L.Zone.Min, L.Zone.Max
	return pos.X >= a.X - m and pos.X <= b.X + m and pos.Y >= a.Y - m and pos.Y <= b.Y + m and pos.Z >= a.Z - m
		and pos.Z <= b.Z + m
end

-- 0..1 presence weight with a horizontal feather (Y counts: 0 below Zone.Min.Y - feather or above Max.Y + feather)
function L.Weight(pos: Vector3, feather: number?): number
	local f = feather or 60
	local a, b = L.Zone.Min, L.Zone.Max
	local dx = math.max(a.X - pos.X, 0, pos.X - b.X)
	local dz = math.max(a.Z - pos.Z, 0, pos.Z - b.Z)
	local dy = math.max(a.Y - pos.Y, 0, pos.Y - b.Y)
	local d = math.sqrt(dx * dx + dz * dz + dy * dy)
	return math.clamp(1 - d / f, 0, 1)
end

function L.District(pos: Vector3): string?
	if not L.InZone(pos) then
		return nil
	end
	for _, d in ipairs(L.Districts) do
		if d.Kind == "Circle" then
			local flat = V(pos.X - d.Centre.X, 0, pos.Z - d.Centre.Z)
			if flat.Magnitude <= d.Radius and pos.Y >= d.Y0 and pos.Y <= d.Y1 then
				return d.Name
			end
		elseif pos.X >= d.Min.X and pos.X <= d.Max.X and pos.Y >= d.Min.Y and pos.Y <= d.Max.Y and pos.Z >= d.Min.Z
			and pos.Z <= d.Max.Z then
			return d.Name
		end
	end
	return "BellSquare" -- ring road / spokes count as the square
end

function L.Anchor(name: string): Vector3?
	return L.Anchors[name]
end

-- live anchor part when it is streamed in (server always has it), else the layout position
function L.AnchorPart(name: string): BasePart?
	local d = workspace:FindFirstChild("DOGROTS_District")
	local root = d and d:FindFirstChild("40_Underyard")
	local anchors = root and root:FindFirstChild("Anchors")
	local part = anchors and anchors:FindFirstChild(name)
	return part and part:IsA("BasePart") and part or nil
end

return L
