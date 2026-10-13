-- Navigation.RouteGraph: the walking graph of the DOGROTS district and the route maths of
-- "SHOW THE WAY" (pure: Vector3 only, no services; shared by the client and tests/navigation.luau).
--
--   * Nodes sit on the centre lines of the real streets (MainBoulevard, the spurs to every
--     attraction, the inner yard promenades, the leaderboard / garden paths, the south loop) with
--     Y on the walking surface. Coordinates were measured in the place (docs/NAVIGATION.md).
--   * Targets: every destination is one or more docks (a graph node) + optional interior
--     waypoints (lab door -> console, museum stairs -> reception) + the goal point where the route
--     ends + the pointer point the final arrow hovers over. Yard targets are written in yard-frame
--     coordinates (x', z) and resolved for the player's own yard.
--   * Blockers: building footprints / fences (XZ boxes). Routes never cross them; they also decide
--     which streets a player can reach in a straight line (the client adds a raycast check).
--   * Plan(from, target): nearest reachable street (projection on an edge) -> A* -> dock -> via ->
--     goal. Smooth(points) fillets the corners, Resample(dense) gives evenly spaced samples with
--     tangents, Locate() projects the player on the sampled route, PointAt() interpolates.
local RouteGraph = {}

RouteGraph.Spacing = 2 -- studs between route samples
RouteGraph.FilletRadius = 5 -- corner radius (clamped to the segment lengths)
RouteGraph.MaxEntryDistance = 260 -- farther than this from every street: no arrows (The Void...)
RouteGraph.DirectRange = 70 -- a visible goal / waypoint closer than this is walked to directly
RouteGraph.YardGround = 1.1 -- top of the yard foundations / entry walks

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
RouteGraph.Flat = flat

local function lerp(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

------------------------------------------------------------------------------------------------
-- Yards: Yard_0N (YardId N). Centre = YardFoundation centre, Side = -1 west / +1 east. The yard
-- frame (PlotAppearance.Frame) looks from the centre at the service row (outwards); x' is the
-- mirrored local x (MiningWorld.placement / PlotAppearance: x' = local x * sx, sx = -Side), z is
-- local z (+z towards the street gate at z = 64, -z towards the service row at z = -44..-66).
------------------------------------------------------------------------------------------------
RouteGraph.Yards = {
	{ Id = 1, Center = v(-105, 1.2, -117), Side = -1 },
	{ Id = 2, Center = v(-105, 1.2, -39), Side = -1 },
	{ Id = 3, Center = v(-105, 1.2, 39), Side = -1 },
	{ Id = 4, Center = v(-105, 1.2, 117), Side = -1 },
	{ Id = 5, Center = v(105, 1.2, -117), Side = 1 },
	{ Id = 6, Center = v(105, 1.2, -39), Side = 1 },
	{ Id = 7, Center = v(105, 1.2, 39), Side = 1 },
	{ Id = 8, Center = v(105, 1.2, 117), Side = 1 },
}
RouteGraph.GateZ = 60 -- yard gate node (the gate posts stand at z = 64, x' = +-9)

function RouteGraph.Yard(id: any): any
	local n = tonumber(id)
	return n and RouteGraph.Yards[n] or nil
end

-- World point of yard-frame coordinates. Same result as Frame(yard) * CFrame.new(x' * sx, 0, z)
-- for the standard yards: world X = cx - Side * z, world Z = cz - x'.
function RouteGraph.YardPoint(id: any, xp: number, z: number, y: number?): Vector3?
	local yard = RouteGraph.Yard(id)
	if not yard then
		return nil
	end
	local c = yard.Center
	return v(c.X - yard.Side * z, y or RouteGraph.YardGround, c.Z - xp)
end

-- Yard-frame coordinates of a world point (inverse of YardPoint).
function RouteGraph.YardLocal(id: any, point: Vector3): (number?, number?)
	local yard = RouteGraph.Yard(id)
	if not yard then
		return nil, nil
	end
	local c = yard.Center
	return c.Z - point.Z, (c.X - point.X) * yard.Side
end

-- The yard a world point stands in (foundation 134 x 70 studs), or nil.
function RouteGraph.YardAt(point: Vector3): number?
	for _, yard in ipairs(RouteGraph.Yards) do
		local c = yard.Center
		if math.abs(point.X - c.X) <= 67 and math.abs(point.Z - c.Z) <= 35 then
			return yard.Id
		end
	end
	return nil
end

------------------------------------------------------------------------------------------------
-- Graph nodes {Id, x, y, z, Sealed?}. Y = top of the walking surface.
------------------------------------------------------------------------------------------------
local NODE_LIST: { any } = {
	-- MainBoulevard (X -18..18, Z 146..754): centre line, one node per junction.
	{ "B162", 0, 0.5, 162 }, -- portal arrival court / developer mailbox
	{ "B205", 0, 0.5, 205 }, -- shelter (east) / leaderboard plaza (west)
	{ "B275", 0, 0.5, 275 }, -- equipment shop (east) / community garden (west)
	{ "B342", 0, 0.6, 341.5 }, -- cosmetics (east) / honor approach (west): the paw plaza's side exits
	{ "B377", 0, 0.6, 377 }, -- spawn pad, welcome plaza
	{ "B395", 0, 0.5, 395 }, -- supplies (east)
	{ "B479", 0, 0.5, 479 }, -- lab (east, Z 477) / museum (west, Z 481)
	{ "B566", 0, 0.5, 566 }, -- digging layers portal (west) / global dig (east, sealed)
	{ "B630", 0, 0.5, 630 }, -- DOG-O-MATIC (west)
	{ "B749", 0, 0.5, 749 }, -- south garden loop
	-- Arrival court corners -> inner yard promenades (walkway X 29..38 beside the DOG EXPRESS lane).
	{ "CE", 34, 0.3, 159.5 },
	{ "CW", -34, 0.3, 159.5 },
	{ "PE117", 33.5, 0.3, 117 },
	{ "PE39", 33.5, 0.3, 39 },
	{ "PEm39", 33.5, 0.3, -39 },
	{ "PEm117", 33.5, 0.3, -117 },
	{ "PW117", -33.5, 0.3, 117 },
	{ "PW39", -33.5, 0.3, 39 },
	{ "PWm39", -33.5, 0.3, -39 },
	{ "PWm117", -33.5, 0.3, -117 },
	-- THE DOG: tongue side paths (X 12..20) beside the mouth.
	{ "DogE", 16, 0.6, -140 },
	{ "DogW", -16, 0.6, -140 },
	-- East spurs.
	{ "ShelterDock", 84, 0.6, 205 }, -- in front of the shelter door
	{ "ShelterSide", 91, 0.6, 222 }, -- shelter forecourt -> service promenade
	{ "CosmeticsWalk", 57, 0.5, 327.5 }, -- east welcome plaza: north of the planter on the Z 335 approach
	{ "SuppliesWalk", 50, 0.5, 386.5 }, -- ... south of the bench and planter on the Z 395 approach
	{ "Market275", 92, 0.5, 275 }, -- service promenade (X 82..102) at the EQUIPMENT door
	{ "Market335", 92, 0.5, 335 }, -- ... COSMETICS door (Paw market anchor)
	{ "Market395", 92, 0.5, 395 }, -- ... SUPPLIES door
	{ "LabDock", 62, 0.5, 477 }, -- laboratory approach, before the entry steps
	{ "FutureDock", 31, 0.5, 575, true }, -- global dig site (sealed: COMING SOON)
	-- West spurs.
	{ "ParkGate", -56, 0.5, 207 }, -- leaderboard plaza east gate
	{ "ParkInner", -86, 0.5, 216 }, -- inside the plaza, south of the pavilions
	{ "ParkSouth", -100, 0.4, 249 }, -- plaza south gate (ParkSouthLink)
	{ "GardenEast", -57, 0.4, 284.5 }, -- community garden entrance (north of the bench)
	{ "GardenCross", -100, 0.4, 284.5 }, -- garden loop x garden cross path
	{ "HonorCross", -100, 0.4, 342 }, -- cross path x honor approach
	{ "GardenSouth", -100, 0.4, 381 }, -- cross path x south return
	{ "CommunityWest", -40, 0.4, 342 }, -- honor approach east end
	{ "SouthReturn", -36, 0.4, 381 }, -- south return east end
	{ "MuseumDock", -48, 0.4, 481 }, -- museum approach, before the grand stairs
	{ "MachineDock", -98, 0.5, 630 }, -- end of the DOG-O-MATIC procession carpet
	{ "MachineSouth", -128, 0.3, 696 }, -- reward plaza south-west
	{ "LoopWest", -177, 0.4, 702 }, -- machine garden return
	{ "LoopSouth", -177, 0.4, 749 }, -- south garden loop corner
}

local EDGE_LIST: { any } = {
	-- Boulevard.
	{ "B162", "B205" },
	{ "B205", "B275" },
	{ "B275", "B342" },
	{ "B342", "B377" },
	{ "B377", "B395" },
	{ "B395", "B479" },
	{ "B479", "B566" },
	{ "B566", "B630" },
	{ "B630", "B749" },
	-- Arrival court and the yard promenades.
	{ "B162", "CE" },
	{ "B162", "CW" },
	{ "CE", "PE117" },
	{ "PE117", "PE39" },
	{ "PE39", "PEm39" },
	{ "PEm39", "PEm117" },
	{ "PEm117", "DogE" },
	{ "CW", "PW117" },
	{ "PW117", "PW39" },
	{ "PW39", "PWm39" },
	{ "PWm39", "PWm117" },
	{ "PWm117", "DogW" },
	-- East.
	{ "B205", "ShelterDock" },
	{ "ShelterDock", "ShelterSide" },
	{ "ShelterSide", "Market275" },
	{ "B275", "Market275" },
	{ "Market275", "Market335" },
	{ "Market335", "Market395" },
	{ "B342", "CosmeticsWalk" },
	{ "CosmeticsWalk", "Market335" },
	{ "B395", "SuppliesWalk" },
	{ "SuppliesWalk", "Market395" },
	{ "B479", "LabDock" },
	{ "B566", "FutureDock" },
	-- West.
	{ "B205", "ParkGate" },
	{ "ParkGate", "ParkInner" },
	{ "ParkInner", "ParkSouth" },
	{ "ParkSouth", "GardenCross" },
	{ "B275", "GardenEast" },
	{ "GardenEast", "GardenCross" },
	{ "GardenCross", "HonorCross" },
	{ "B342", "CommunityWest" },
	{ "CommunityWest", "HonorCross" },
	{ "HonorCross", "GardenSouth" },
	{ "GardenSouth", "SouthReturn" },
	{ "SouthReturn", "B377" },
	{ "B479", "MuseumDock" },
	{ "B630", "MachineDock" },
	{ "MachineDock", "MachineSouth" },
	{ "MachineSouth", "LoopWest" },
	{ "LoopWest", "LoopSouth" },
	{ "LoopSouth", "B749" },
}

-- Yard gates: one node per yard on its entry walk, joined to the promenade at the yard's centre line.
local PROMENADE_OF = { [1] = "PWm117", [2] = "PWm39", [3] = "PW39", [4] = "PW117", [5] = "PEm117", [6] = "PEm39", [7] = "PE39", [8] = "PE117" }

export type Node = { Id: string, Index: number, Pos: Vector3, Sealed: boolean, Links: { any } }

RouteGraph.Nodes = {} :: { Node }
RouteGraph.ById = {} :: { [string]: Node }
RouteGraph.Edges = {} :: { any } -- {A = Node, B = Node, Length}

local function addNode(id: string, pos: Vector3, sealed: boolean?)
	assert(RouteGraph.ById[id] == nil, "duplicate node " .. id)
	local node = { Id = id, Index = #RouteGraph.Nodes + 1, Pos = pos, Sealed = sealed == true, Links = {} }
	table.insert(RouteGraph.Nodes, node)
	RouteGraph.ById[id] = node
end
local function addEdge(a: string, b: string)
	local na, nb = RouteGraph.ById[a], RouteGraph.ById[b]
	assert(na and nb, "edge with unknown node " .. a .. "-" .. b)
	local length = (na.Pos - nb.Pos).Magnitude
	local edge = { A = na, B = nb, Length = length }
	table.insert(RouteGraph.Edges, edge)
	table.insert(na.Links, { Node = nb, Cost = length })
	table.insert(nb.Links, { Node = na, Cost = length })
end

for _, row in ipairs(NODE_LIST) do
	addNode(row[1], v(row[2], row[3], row[4]), row[5])
end
for _, yard in ipairs(RouteGraph.Yards) do
	addNode("YG" .. yard.Id, RouteGraph.YardPoint(yard.Id, 0, RouteGraph.GateZ, 1.2) :: Vector3)
end
for _, row in ipairs(EDGE_LIST) do
	addEdge(row[1], row[2])
end
for id, promenade in pairs(PROMENADE_OF) do
	addEdge(promenade, "YG" .. id)
end

function RouteGraph.GateNode(yardId: any): string?
	local yard = RouteGraph.Yard(yardId)
	return yard and ("YG" .. yard.Id) or nil
end

------------------------------------------------------------------------------------------------
-- Blockers: XZ boxes {Name, X0, X1, Z0, Z1}. Solid things a route must not cross (walls,
-- facades, counters, the sealed cube, fences). Interiors with an entrance are modelled by their
-- walls so the route can walk in through the door.
------------------------------------------------------------------------------------------------
export type Box = { Name: string, X0: number, X1: number, Z0: number, Z1: number }
RouteGraph.Blockers = {} :: { Box }

local function box(name: string, x0: number, x1: number, z0: number, z1: number)
	table.insert(RouteGraph.Blockers, { Name = name, X0 = math.min(x0, x1), X1 = math.max(x0, x1), Z0 = math.min(z0, z1), Z1 = math.max(z0, z1) })
end

-- THE DOG head, its mouth walls and the tongue belt (dogs walk there).
box("DogHead", -74, 74, -262, -186)
box("MouthWallE", 15.5, 18.5, -184, -146)
box("MouthWallW", -18.5, -15.5, -184, -146)
box("TongueBelt", -11, 11, -168, 137)
box("MouthBollardE", 17.9, 20.1, -147.1, -144.9)
box("MouthBollardW", -20.1, -17.9, -147.1, -144.9)
box("ArrivalPlinthE", 14.5, 21.5, 132, 144)
box("ArrivalPlinthW", -21.5, -14.5, 132, 144)
box("Mailbox", -3.5, 3.5, 147.7, 152.3)
-- Dog shelter: front wall with a door (Z 197.6..212.2), kennel rooms, reception desk, planters.
box("ShelterFrontN", 96.3, 99, 163, 197.6)
box("ShelterFrontS", 96.3, 99, 212.2, 247)
box("ShelterRoomsN", 100, 142, 163, 189)
box("ShelterRoomsS", 100, 142, 221, 247)
box("ShelterDesk", 123.9, 130, 194.4, 215.4)
box("ShelterPlanterN", 81.7, 86.1, 169.9, 181.9)
box("ShelterPlanterS", 81.7, 86.1, 227.9, 239.9)
-- Paw market shops (doors at Z c +-5) and their terminals.
for _, c in ipairs({ 275, 335, 395 }) do
	box("ShopFrontN_" .. c, 117.8, 119, c - 20, c - 5)
	box("ShopFrontS_" .. c, 117.8, 119, c + 5, c + 20)
	box("ShopTerminal_" .. c, 144, 148, c - 3.5, c + 3.5)
	box("ShopBack_" .. c, 152, 156, c - 20, c + 20)
end
-- Mutation lab: facade with the automatic glass door (Z 467..487), central chamber, back wall.
box("LabFacadeN", 75, 86.5, 440, 466.6)
box("LabFacadeS", 75, 86.5, 487.4, 514)
box("LabWingN", 86.5, 157, 425, 446.5)
box("LabWingS", 86.5, 157, 507.5, 529)
box("LabChamber", 124.7, 143.3, 467, 486)
box("LabBack", 151, 157, 446.5, 507.5)
-- East welcome plaza furniture on the shop approaches.
box("PlazaPlanter335", 55, 59, 331, 345)
box("PlazaBench395", 37.9, 46.1, 393.9, 396.2)
box("PlazaPlanter395", 47, 59, 391.5, 400.5)
box("PlazaPlanter401", 33, 45, 399, 403)
-- DogDex museum: facade (door Z 470.6..491.4), reception desk, pedestals, the western halls.
box("MuseumFacadeN", -76, -72, 421, 470.4)
box("MuseumFacadeS", -76, -72, 491.6, 541)
box("MuseumDesk", -100.2, -95.8, 452.7, 463.3)
box("MuseumPedestalsN", -82.2, -78.2, 435.9, 460.6)
box("MuseumPedestalsS", -82.2, -78.2, 501.4, 526)
box("MuseumHalls", -199, -104, 421, 541)
box("MuseumRoomsN", -104, -73, 414, 435.5)
box("MuseumRoomsS", -104, -73, 526.5, 548)
-- Shop side walls (the shops stand side by side along the service promenade).
for _, c in ipairs({ 275, 335, 395 }) do
	box("ShopSideN_" .. c, 118, 156, c - 20.5, c - 19)
	box("ShopSideS_" .. c, 118, 156, c + 19, c + 20.5)
end
-- DOG EXPRESS lantern bollards (head-height roofs) beside both lanes.
for _, z in ipairs({ -158, 154, 310, 466, 622, 734 }) do
	box("ExpressBollardE" .. z, 29.9, 32.1, z - 1.1, z + 1.1)
	box("ExpressBollardW" .. z, -32.1, -29.9, z - 1.1, z + 1.1)
end
-- Planters and garden beds next to the streets.
for _, row in
	ipairs({
		{ "PawGardenNE", 8.4, 19.1, 322.9, 333.6 },
		{ "PawGardenNW", -19.1, -8.4, 322.9, 333.6 },
		{ "PawGardenSE", 8.4, 19.1, 350.4, 361.1 },
		{ "PawGardenSW", -19.1, -8.4, 350.4, 361.1 },
		{ "CourtBedE", 37.5, 56.5, 163.5, 168.5 },
		{ "CourtBedW", -56.5, -37.5, 163.5, 168.5 },
		{ "ForecourtBedNE", 47.5, 92.5, 412.5, 417.5 },
		{ "ForecourtBedNW", -92.5, -47.5, 412.5, 417.5 },
		{ "ForecourtBedSE", 47.5, 92.5, 512.5, 517.5 },
		{ "GardenWalkBedN", 63.5, 78.5, 244.5, 249.5 },
		{ "GardenWalkBedS", 64.5, 79.5, 290.5, 295.5 },
		{ "GardenBedE", -86, -68, 254.5, 259.5 },
		{ "GardenBedW", -132, -114, 254.5, 259.5 },
		{ "HonorPlanterNE", -87, -67, 304, 316.5 },
		{ "HonorPlanterNW", -129, -109, 304, 316.5 },
		{ "HonorPlanterSE", -87, -67, 360, 372.5 },
		{ "HonorPlanterSW", -129, -109, 360, 372.5 },
		{ "HonorSquareN", -180.5, -153.5, 318.7, 321.3 },
		{ "HonorSquareS", -180.5, -153.5, 362.7, 365.3 },
	})
do
	box(row[1], row[2], row[3], row[4], row[5])
end
-- Global dig site: the sealed COMING SOON cube.
box("GlobalDigCube", 33, 214.5, 531, 745.3)
-- DOG-O-MATIC machine.
box("RewardMachine", -172, -140, 573, 685)
-- Leaderboard plaza pavilions.
box("LegacyPavilion", -79.9, -74.1, 188, 210)
box("HonorPavilion", -125.9, -120.1, 188, 210)
box("DiscoveryPavilion", -111, -89, 179.1, 184.9)
-- Community garden benches at the loop entrances.
box("GardenBenchE", -64.3, -61.7, 271, 279)
box("GardenBenchW", -138.3, -135.7, 271, 279)
-- Yards: front fence beside the gate, side edges, service row (vendor, storage, workshop).
for _, yard in ipairs(RouteGraph.Yards) do
	local id = yard.Id
	local function yardBox(name: string, xa: number, xb: number, za: number, zb: number)
		local a = RouteGraph.YardPoint(id, xa, za) :: Vector3
		local b = RouteGraph.YardPoint(id, xb, zb) :: Vector3
		box("Yard" .. id .. name, a.X, b.X, a.Z, b.Z)
	end
	yardBox("FenceL", -36, -7.6, 63, 65.5)
	yardBox("FenceR", 7.6, 36, 63, 65.5)
	yardBox("SideL", -36, -34.5, -67, 65.5)
	yardBox("SideR", 34.5, 36, -67, 65.5)
	yardBox("Service", -31, 31, -67, -46.5)
end

local function insideBox(b: Box, x: number, z: number, margin: number): boolean
	return x > b.X0 - margin and x < b.X1 + margin and z > b.Z0 - margin and z < b.Z1 + margin
end

-- First blocker containing the point (XZ), or nil.
function RouteGraph.BlockerAt(point: Vector3, margin: number?): Box?
	local m = margin or 0
	for _, b in ipairs(RouteGraph.Blockers) do
		if insideBox(b, point.X, point.Z, m) then
			return b
		end
	end
	return nil
end

-- Does the XZ segment a-b cross a blocker? (Liang-Barsky clip against each box.)
local function segmentHits(b: Box, ax: number, az: number, bx: number, bz: number, margin: number): boolean
	local x0, x1, z0, z1 = b.X0 - margin, b.X1 + margin, b.Z0 - margin, b.Z1 + margin
	local dx, dz = bx - ax, bz - az
	local t0, t1 = 0, 1
	local p = { -dx, dx, -dz, dz }
	local q = { ax - x0, x1 - ax, az - z0, z1 - az }
	for i = 1, 4 do
		if p[i] == 0 then
			if q[i] < 0 then
				return false
			end
		else
			local t = q[i] / p[i]
			if p[i] < 0 then
				if t > t1 then
					return false
				end
				if t > t0 then
					t0 = t
				end
			else
				if t < t0 then
					return false
				end
				if t < t1 then
					t1 = t
				end
			end
		end
	end
	return t0 <= t1
end

-- First blocker the XZ segment a-b crosses, or nil. With skipInside, boxes that already contain a
-- are ignored (a player standing on the tongue or inside a hall can still walk out).
function RouteGraph.SegmentBlocker(a: Vector3, b: Vector3, margin: number?, skipInside: boolean?): Box?
	local m = margin or 0
	for _, blocker in ipairs(RouteGraph.Blockers) do
		if not (skipInside and insideBox(blocker, a.X, a.Z, 0)) and segmentHits(blocker, a.X, a.Z, b.X, b.Z, m) then
			return blocker
		end
	end
	return nil
end

function RouteGraph.SegmentClear(a: Vector3, b: Vector3, margin: number?, skipInside: boolean?): boolean
	return RouteGraph.SegmentBlocker(a, b, margin, skipInside) == nil
end

------------------------------------------------------------------------------------------------
-- Targets. Docks: {{Node, Via = {Vector3}, Goal = Vector3}}; Pointer: the point the final arrow
-- hovers over (top of the object). Yard targets use yard-frame {x', z} pairs (Yard = true).
------------------------------------------------------------------------------------------------
RouteGraph.Targets = {
	PlayerYards = { Yard = true, Goal = { 0, 50 }, Pointer = { 0, 50, 1.2 } },
	MyKennels = { Yard = true, Goal = { 0, 40 }, Pointer = { 0, 40, 1.2 } },
	MiningCorner = { Yard = true, Via = { { 0, -6.5 } }, Goal = { -8, -6.5 }, Pointer = { -18, -6.5, 1.6 } },
	MineElevator = { Yard = true, Via = { { 0, -36 } }, Goal = { 7, -36 }, Pointer = { 20, -36, 1.2 } },
	BestFinds = { Yard = true, Goal = { 18, 61 }, Pointer = { 20, 55, 5 } },
	Collector = { Yard = true, Via = { { 0, -28 }, { -20, -40 } }, Goal = { -24, -44.5 }, Pointer = { -24, -48.9, 4.7 } },

	DogLine = {
		Docks = { { Node = "DogE", Goal = v(12.6, 0.6, -140) }, { Node = "DogW", Goal = v(-12.6, 0.6, -140) } },
		Pointer = v(0, 2.2, -140),
	},
	Feedback = { Docks = { { Node = "B162", Goal = v(0, 0.4, 156) } }, Pointer = v(0, 8.6, 150) },
	WelcomeHub = { Docks = { { Node = "B377", Goal = v(0, 0.6, 377) } }, Pointer = v(0, 0.6, 377) },
	Shelter = {
		Docks = { { Node = "ShelterDock", Goal = v(118.5, 1.1, 205) } },
		Pointer = v(121.9, 3.6, 204.9),
	},
	Shops = { Docks = { { Node = "Market335", Goal = v(94, 0.5, 335) } }, Pointer = v(94, 0.5, 335) },
	-- Shops: in through the door (Z c +-5), up to the service terminal.
	Equipment = { Docks = { { Node = "Market275", Goal = v(139.5, 0.4, 275) } }, Pointer = v(142.8, 4.3, 275) },
	Cosmetics = { Docks = { { Node = "Market335", Goal = v(139.5, 0.4, 335) } }, Pointer = v(142.8, 4.3, 335) },
	Supplies = { Docks = { { Node = "Market395", Goal = v(139.5, 0.4, 395) } }, Pointer = v(142.8, 4.3, 395) },
	MutationLab = {
		-- Entry steps (X 75..84 up to Y 2), the automatic glass door at X 84, the operator spot in
		-- front of the mutation machine's console (desk front X 106, ACTIVATE button anchor
		-- MutationMachineLayout.Anchor = world (107.7, 7.9, 477)).
		Docks = { { Node = "LabDock", Via = { v(76, 0.5, 477), v(86, 2.2, 477), v(98, 2.2, 477) }, Goal = v(103.5, 2.2, 477) } },
		Pointer = v(107.7, 7.9, 477),
	},
	DogDex = {
		-- Grand stairs (X -63..-73 up to Y 4), the open door, the DOGDEX reception desk.
		Docks = { { Node = "MuseumDock", Via = { v(-60, 0.5, 481), v(-75, 4.1, 481), v(-84, 4.1, 476) }, Goal = v(-92.5, 4.1, 461) } },
		Pointer = v(-93, 6, 458),
	},
	DogPark = { Docks = { { Node = "ParkInner", Goal = v(-100, 0.5, 236) } }, Pointer = v(-100, 0.5, 238) },
	PortalRuins = { Docks = { { Node = "B566", Goal = v(-61, 0.3, 564) } }, Pointer = v(-63, 0.3, 564) },
	RewardMachine = { Docks = { { Node = "MachineDock", Goal = v(-103, 0.8, 630) } }, Pointer = v(-106, 1.2, 630) },
	GlobalDigSite = { Sealed = true, Docks = { { Node = "FutureDock", Goal = v(36, 0.5, 575) } }, Pointer = v(38, 3, 575) },
	TheVoid = { Sealed = true, Docks = {}, Pointer = v(700.7, 117, -633.3) },
}

local function yardVec(id: any, pair: { number }, y: number?): Vector3
	return RouteGraph.YardPoint(id, pair[1], pair[2], y or pair[3]) :: Vector3
end

-- Concrete target {Key, Docks, Pointer, Sealed}. ctx: {YardId, Overrides = {Via?, Goal?, Pointer?}}
-- (Via only for yard targets: the live model of a yard object moved by another system).
-- Yard targets need ctx.YardId (nil otherwise).
function RouteGraph.Target(key: string, ctx: any?): any
	local spec = (RouteGraph.Targets :: any)[key]
	if not spec then
		return nil
	end
	local c = ctx or {}
	local overrides = c.Overrides or {}
	if spec.Yard then
		local id = c.YardId
		if not RouteGraph.Yard(id) then
			return nil
		end
		local via = overrides.Via
		if not via then
			via = {}
			for _, pair in ipairs(spec.Via or {}) do
				table.insert(via, yardVec(id, pair))
			end
		end
		local goal = overrides.Goal or yardVec(id, spec.Goal)
		local pointer = overrides.Pointer or yardVec(id, spec.Pointer, spec.Pointer[3])
		return { Key = key, Yard = id, Docks = { { Node = "YG" .. RouteGraph.Yard(id).Id, Via = via, Goal = goal } }, Pointer = pointer }
	end
	local docks = {}
	for _, dock in ipairs(spec.Docks) do
		table.insert(docks, { Node = dock.Node, Via = dock.Via or {}, Goal = overrides.Goal or dock.Goal })
	end
	return { Key = key, Docks = docks, Pointer = overrides.Pointer or spec.Pointer, Sealed = spec.Sealed == true }
end

------------------------------------------------------------------------------------------------
-- A*: sources {{Node, G}} (several entry points at once), one goal node. Sealed nodes are never
-- entered. Returns the node list (first source .. goal) and the cost, or nil.
------------------------------------------------------------------------------------------------
function RouteGraph.AStar(sources: { any }, goal: Node): ({ Node }?, number)
	local open: { Node } = {}
	local g: { [Node]: number } = {}
	local f: { [Node]: number } = {}
	local parent: { [Node]: Node } = {}
	local closed: { [Node]: boolean } = {}
	local function h(n: Node): number
		return (n.Pos - goal.Pos).Magnitude
	end
	for _, s in ipairs(sources) do
		local n: Node = s.Node
		if not n.Sealed and (g[n] == nil or s.G < g[n]) then
			if g[n] == nil then
				table.insert(open, n)
			end
			g[n] = s.G
			f[n] = s.G + h(n)
		end
	end
	while #open > 0 do
		local best, bestIndex = open[1], 1
		for i = 2, #open do
			if f[open[i]] < f[best] then
				best, bestIndex = open[i], i
			end
		end
		table.remove(open, bestIndex)
		if best == goal then
			local path = { best }
			local node = best
			while parent[node] do
				node = parent[node]
				table.insert(path, 1, node)
			end
			return path, g[best]
		end
		closed[best] = true
		for _, link in ipairs(best.Links) do
			local n: Node = link.Node
			if not closed[n] and not n.Sealed then
				local cost = g[best] + link.Cost
				if g[n] == nil or cost < g[n] then
					if g[n] == nil then
						table.insert(open, n)
					end
					g[n] = cost
					f[n] = cost + h(n)
					parent[n] = best
				end
			end
		end
	end
	return nil, math.huge
end

------------------------------------------------------------------------------------------------
-- Entry points: the closest point of every (unsealed) street edge, nearest first.
------------------------------------------------------------------------------------------------
local function closestOnSegment(p: Vector3, a: Vector3, b: Vector3): (Vector3, number)
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 1e-9 then
		t = math.clamp(((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2, 0, 1)
	end
	return lerp(a, b, t), t
end
RouteGraph.ClosestOnSegment = closestOnSegment

function RouteGraph.Entries(from: Vector3, limit: number?): { any }
	local list = {}
	for _, edge in ipairs(RouteGraph.Edges) do
		if not edge.A.Sealed and not edge.B.Sealed then
			local q, t = closestOnSegment(from, edge.A.Pos, edge.B.Pos)
			table.insert(list, { Edge = edge, Point = q, T = t, Distance = flat(from, q) })
		end
	end
	table.sort(list, function(x, y)
		return x.Distance < y.Distance
	end)
	local n = limit or #list
	while #list > n do
		table.remove(list)
	end
	return list
end

local function polylineLength(points: { Vector3 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end
RouteGraph.PolylineLength = polylineLength

-- Line of sight on the ground plane: blockers, plus the caller's check (client raycast).
local function visible(opts: any, a: Vector3, b: Vector3): boolean
	if not RouteGraph.SegmentClear(a, b, 0.4, true) then
		return false
	end
	local check = opts and opts.Visible
	if check then
		local ok, result = pcall(check, a, b)
		return not ok or result ~= false
	end
	return true
end

------------------------------------------------------------------------------------------------
-- Plan(from, target, opts) -> route {Points, Nodes, Length, Goal, Pointer, Dock} | nil, reason
-- opts: {Visible = function(a, b) -> boolean (extra line-of-sight test), Entries = 8}
------------------------------------------------------------------------------------------------
function RouteGraph.Plan(from: Vector3, target: any, opts: any?): (any?, string?)
	if not target then
		return nil, "unknown"
	end
	if target.Sealed then
		return nil, "sealed"
	end
	if #target.Docks == 0 then
		return nil, "unreachable"
	end
	local o = opts or {}
	local best: any = nil
	local function consider(points: { Vector3 }, nodes: { string }, dock: any)
		local length = polylineLength(points)
		if not best or length < best.Length then
			best = { Points = points, Nodes = nodes, Length = length, Dock = dock }
		end
	end

	-- 1. Direct: the goal or one of its waypoints is in plain sight and close (inside a yard, in
	--    front of the shop...). Walk there, then follow the rest of the tail.
	for _, dock in ipairs(target.Docks) do
		local tail = table.clone(dock.Via)
		table.insert(tail, dock.Goal)
		for i = #tail, 1, -1 do
			if flat(from, tail[i]) <= RouteGraph.DirectRange and visible(o, from, tail[i]) then
				local points = { from }
				for j = i, #tail do
					table.insert(points, tail[j])
				end
				consider(points, {}, dock)
				break
			end
		end
	end

	-- 2. Streets: enter the graph at the nearest visible edge point(s), A* to each dock.
	local entries = RouteGraph.Entries(from, 24)
	if #entries == 0 or entries[1].Distance > RouteGraph.MaxEntryDistance then
		if best then
			best.Length = polylineLength(best.Points)
			best.Goal = best.Points[#best.Points]
			best.Pointer = target.Pointer
			return best, nil
		end
		return nil, "far"
	end
	local chosen = {}
	for _, entry in ipairs(entries) do
		if #chosen >= (o.Entries or 4) then
			break
		end
		if visible(o, from, entry.Point) then
			table.insert(chosen, entry)
		end
	end
	if #chosen == 0 then
		-- Nothing in sight (behind a wall, unusual spot): trust the nearest street.
		chosen = { entries[1] }
	end
	for _, dock in ipairs(target.Docks) do
		local goalNode = RouteGraph.ById[dock.Node]
		if goalNode and not goalNode.Sealed then
			for _, entry in ipairs(chosen) do
				local a, b = entry.Edge.A, entry.Edge.B
				local lead = (from - entry.Point).Magnitude
				local path, cost = RouteGraph.AStar({
					{ Node = a, G = lead + (entry.Point - a.Pos).Magnitude },
					{ Node = b, G = lead + (entry.Point - b.Pos).Magnitude },
				}, goalNode)
				if path and cost < math.huge then
					local points = { from }
					local first = path[1].Pos
					-- Step onto the street unless the entry point is the first node itself.
					if (entry.Point - first).Magnitude > 0.75 then
						table.insert(points, entry.Point)
					end
					local ids = {}
					for _, node in ipairs(path) do
						table.insert(points, node.Pos)
						table.insert(ids, node.Id)
					end
					for _, p in ipairs(dock.Via) do
						table.insert(points, p)
					end
					table.insert(points, dock.Goal)
					consider(points, ids, dock)
				end
			end
		end
	end
	if not best then
		return nil, "unreachable"
	end
	-- Drop points that sit on top of each other.
	local cleaned = { best.Points[1] }
	for i = 2, #best.Points do
		local p = best.Points[i]
		if (p - cleaned[#cleaned]).Magnitude > 0.5 or i == #best.Points then
			if i == #best.Points and (p - cleaned[#cleaned]).Magnitude <= 0.5 and #cleaned > 1 then
				cleaned[#cleaned] = p
			else
				table.insert(cleaned, p)
			end
		end
	end
	best.Points = cleaned
	best.Length = polylineLength(cleaned)
	best.Goal = cleaned[#cleaned]
	best.Pointer = target.Pointer
	return best, nil
end

------------------------------------------------------------------------------------------------
-- Smooth(points, radius): fillets every corner with a circular arc (radius clamped so it never
-- eats more than 45 % of a segment) and returns a dense polyline.
------------------------------------------------------------------------------------------------
function RouteGraph.Smooth(points: { Vector3 }, radius: number?): { Vector3 }
	local r = radius or RouteGraph.FilletRadius
	local n = #points
	if n < 3 then
		return table.clone(points)
	end
	local out = { points[1] }
	for i = 2, n - 1 do
		local p0, p1, p2 = points[i - 1], points[i], points[i + 1]
		local ax, az = p1.X - p0.X, p1.Z - p0.Z
		local bx, bz = p2.X - p1.X, p2.Z - p1.Z
		local la, lb = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
		if la < 1e-6 or lb < 1e-6 then
			table.insert(out, p1)
			continue
		end
		ax, az, bx, bz = ax / la, az / la, bx / lb, bz / lb
		local dot = math.clamp(ax * bx + az * bz, -1, 1)
		local turn = math.acos(dot) -- 0 = straight on
		if turn < math.rad(2) or turn > math.rad(178) then
			table.insert(out, p1)
			continue
		end
		local tangent = r * math.tan(turn / 2)
		tangent = math.min(tangent, la * 0.45, lb * 0.45)
		local radiusUsed = tangent / math.tan(turn / 2)
		-- Tangent points and the arc centre (on the inner side of the corner).
		local s = p1 - Vector3.new(ax, 0, az) * tangent
		local e = p1 + Vector3.new(bx, 0, bz) * tangent
		-- Y along the corner follows the two segments' slopes.
		local sy = p1.Y + (p0.Y - p1.Y) * (tangent / la)
		local ey = p1.Y + (p2.Y - p1.Y) * (tangent / lb)
		local cross = ax * bz - az * bx -- > 0: turning towards +90 (left in X/Z with Z down)
		local nx, nz
		if cross > 0 then
			nx, nz = -az, ax
		else
			nx, nz = az, -ax
		end
		local cx, cz = s.X + nx * radiusUsed, s.Z + nz * radiusUsed
		local a0 = math.atan2(s.Z - cz, s.X - cx)
		local a1 = math.atan2(e.Z - cz, e.X - cx)
		local delta = a1 - a0
		while delta > math.pi do
			delta -= 2 * math.pi
		end
		while delta < -math.pi do
			delta += 2 * math.pi
		end
		local steps = math.max(2, math.ceil(math.abs(delta) / math.rad(7.5)))
		for k = 0, steps do
			local t = k / steps
			local angle = a0 + delta * t
			table.insert(out, Vector3.new(cx + math.cos(angle) * radiusUsed, sy + (ey - sy) * t, cz + math.sin(angle) * radiusUsed))
		end
	end
	table.insert(out, points[n])
	return out
end

------------------------------------------------------------------------------------------------
-- Resample(dense, spacing) -> {Positions, Tangents (flat unit vectors), Distances, Length,
-- Spacing}: samples every `spacing` studs of arc length, the last one exactly at the end.
------------------------------------------------------------------------------------------------
function RouteGraph.Resample(dense: { Vector3 }, spacing: number?): any
	local step = spacing or RouteGraph.Spacing
	local positions, tangents, distances = {}, {}, {}
	local n = #dense
	local function flatDir(a: Vector3, b: Vector3): Vector3
		local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local m = d.Magnitude
		if m < 1e-6 then
			return Vector3.new(0, 0, -1)
		end
		return d / m
	end
	if n == 0 then
		return { Positions = positions, Tangents = tangents, Distances = distances, Length = 0, Spacing = step }
	end
	if n == 1 then
		return { Positions = { dense[1] }, Tangents = { Vector3.new(0, 0, -1) }, Distances = { 0 }, Length = 0, Spacing = step }
	end
	local total = polylineLength(dense)
	local seg, segStart = 1, 0
	local segLen = (dense[2] - dense[1]).Magnitude
	local count = math.max(1, math.floor(total / step + 1e-6))
	for k = 0, count do
		local d = math.min(k * step, total)
		while seg < n - 1 and segStart + segLen < d - 1e-9 do
			segStart += segLen
			seg += 1
			segLen = (dense[seg + 1] - dense[seg]).Magnitude
		end
		local t = segLen > 1e-9 and math.clamp((d - segStart) / segLen, 0, 1) or 0
		table.insert(positions, lerp(dense[seg], dense[seg + 1], t))
		table.insert(tangents, flatDir(dense[seg], dense[seg + 1]))
		table.insert(distances, d)
	end
	if distances[#distances] < total - 1e-6 then
		table.insert(positions, dense[n])
		table.insert(tangents, flatDir(dense[n - 1], dense[n]))
		table.insert(distances, total)
	end
	-- Smoother headings: average each tangent with its neighbours (arcs are already dense).
	local smoothed = {}
	for i = 1, #tangents do
		local a, b = tangents[math.max(1, i - 1)], tangents[math.min(#tangents, i + 1)]
		local sum = a + tangents[i] * 2 + b
		smoothed[i] = sum.Magnitude > 1e-6 and sum.Unit or tangents[i]
	end
	return { Positions = positions, Tangents = smoothed, Distances = distances, Length = total, Spacing = step }
end

-- Build(points): Smooth + Resample in one call.
function RouteGraph.Build(points: { Vector3 }, spacing: number?, radius: number?): any
	return RouteGraph.Resample(RouteGraph.Smooth(points, radius), spacing)
end

-- Position and flat heading at arc length s (clamped).
function RouteGraph.PointAt(samples: any, s: number): (Vector3, Vector3)
	local positions = samples.Positions
	local n = #positions
	if n == 0 then
		return Vector3.zero, Vector3.new(0, 0, -1)
	end
	if n == 1 or s <= 0 then
		return positions[1], samples.Tangents[1]
	end
	local f = s / samples.Spacing
	local i = math.floor(f) + 1
	if i >= n then
		return positions[n], samples.Tangents[n]
	end
	local d0, d1 = samples.Distances[i], samples.Distances[i + 1]
	local t = d1 > d0 and math.clamp((s - d0) / (d1 - d0), 0, 1) or 0
	local tangent = samples.Tangents[i] + (samples.Tangents[i + 1] - samples.Tangents[i]) * t
	return lerp(positions[i], positions[i + 1], t), (tangent.Magnitude > 1e-6 and tangent.Unit or samples.Tangents[i])
end

-- Locate(samples, pos, hint) -> s (arc length of the closest route point), lateral XZ distance,
-- sample index. Searches +-window samples around the hint first; a global scan when that fails.
function RouteGraph.Locate(samples: any, pos: Vector3, hint: number?, window: number?): (number, number, number)
	local positions = samples.Positions
	local n = #positions
	if n == 0 then
		return 0, math.huge, 1
	end
	if n == 1 then
		return 0, flat(pos, positions[1]), 1
	end
	local function scan(i0: number, i1: number): (number, number, number)
		local bestS, bestD, bestI = 0, math.huge, i0
		for i = math.max(1, i0), math.min(n - 1, i1) do
			local q, t = closestOnSegment(pos, positions[i], positions[i + 1])
			local d = flat(pos, q)
			if d < bestD then
				bestD = d
				bestS = samples.Distances[i] + (samples.Distances[i + 1] - samples.Distances[i]) * t
				bestI = i
			end
		end
		return bestS, bestD, bestI
	end
	local w = window or 14
	if hint then
		local s, d, i = scan(hint - w, hint + w)
		if d <= 6 then
			return s, d, i
		end
	end
	return scan(1, n - 1)
end

return RouteGraph
