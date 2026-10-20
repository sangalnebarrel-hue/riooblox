-- MineLayout: the deterministic geometry of the yard mines ("dogs dig DOWN"), shared by the
-- server (MineWorld, DogKennelService, KennelLootPlacement, DistrictSafety), the client
-- (MineClient, MineLevels) and the tests. Pure maths: no instances are created here.
--
-- Design space. Everything is described once in YARD DESIGN coordinates (x', y, z):
--   x' = sx * (local X of the yard frame) - Origin.X, z = local Z of the yard frame - Origin.Z,
--   y = world Y.
-- The yard frame is PlotAppearance.Frame (centre of YardFoundation, looking at the service row,
-- so -z points at the storage / workshop buildings) and sx = -1 for the mirrored yards 5-8.
-- Layout.Origin moves the whole mine rigidly inside the yard: the design origin sits at yard
-- (x' 4, z -18), so the shaft (design x' 20, z -36) is at yard x' 24, z -54, on the old Workshop
-- lot of the SERVICE ROW (collector x' -24, DOG STORAGE x' 0, elevator x' +24).
-- A design CFrame becomes a world CFrame with layout:ToWorld(cf) (positions and rotations are
-- mirrored for sx = -1; every Forge primitive is symmetric about its local X axis, so a mirrored
-- part is still a proper rotated part).
--
-- Vertical stack of one yard (world Y):
--   surface       ground 1.0 (YardFoundation top); the headframe stands over the shaft
--   island rock   0 .. -32 (CohesiveIsland.IslandMass, carved by MineWorld for the shaft only)
--   CAVERNS       floor -58, ceiling -32 (the island's own underside)     layer 2
--   ANCIENT RUINS floor -92, ceiling -68                                  layer 3
--   CURSED DEPTHS floor -126, ceiling -102                                layer 4
--   THE VOID      floor -160, ceiling -136                                layer 5
--   shell bottom  -172 (stalactite tips about -200; FallenPartsDestroyHeight is -250)
-- The shaft (design x' 16..24, z -40..-32; yard x' 20..28, z -58..-50) runs from the surface to
-- the Void floor along the -z wall of the chambers and opens into every chamber at its elevator
-- stop.
local Layout = {}
Layout.Version = 1

Layout.GroundY = 1.0
Layout.IslandBottom = -32
Layout.ShellTop = -30 -- the shell walls reach 2 studs into the island rock
Layout.Bottom = -172
Layout.Wall = 4

-- Shaft opening (design x', z): 8 x 8 studs.
Layout.Shaft = { X = 20, Z = -36, Half = 4 }
-- Chamber interior of every level (design x', z).
Layout.Chamber = { X0 = -24, X1 = 26, Z0 = -32, Z1 = 14 }
-- Reserved surface zone of the station incl. its porch (design x' 13..27, z -44.5..-26; yard
-- x' 17..31, z -62.5..-44). Documentation only.
Layout.Zone = { X0 = 13, X1 = 27, Z0 = -44.5, Z1 = -26 }
-- Where the mine's design origin sits in the yard frame (yard x', z). The whole mine (station,
-- shaft, shell, levels, worksites, arrivals) moves rigidly with it, so the station stands in the
-- SERVICE ROW on the old Workshop lot: shaft centre at yard x' 24, z -54, beside the DOG STORAGE
-- (x' 0) and the collector (x' -24). Keep Z >= -18: deeper, the shaft cuts the island-edge cliff
-- slabs; the station's back (counterweight channel, yard z -62) must stay before the back fence.
Layout.Origin = { X = 4, Z = -18 }
-- The station (MineStructures.Headframe) is turned about the shaft axis by this yaw so its
-- doorway faces +z (the yard), like the storage and collector counters (0 = doorway on -x').
Layout.StationYaw = math.pi / 2

Layout.Levels = {
	[2] = { Layer = 2, Key = "Caverns", Floor = -58, Ceiling = -32 },
	[3] = { Layer = 3, Key = "Ruins", Floor = -92, Ceiling = -68 },
	[4] = { Layer = 4, Key = "Cursed", Floor = -126, Ceiling = -102 },
	[5] = { Layer = 5, Key = "Void", Floor = -160, Ceiling = -136 },
}
Layout.Keys = { [1] = "Surface", [2] = "Caverns", [3] = "Ruins", [4] = "Cursed", [5] = "Void" }

-- Dog worksites, one per kennel slot, in the same arrangement as the kennels: odd slots on the
-- -x' side, even slots on the +x' side, rows from the elevator end towards the far wall.
-- X/Z: the dig face point (where the dog's nose is), Dir: +1 / -1 = the dog faces +x' / -x'
-- (towards the ore vein in the wall).
Layout.Worksites = {
	{ X = -19.5, Z = -16, Dir = -1 },
	{ X = 21.5, Z = -13, Dir = 1 },
	{ X = -19.5, Z = -2, Dir = -1 },
	{ X = 21.5, Z = 2, Dir = 1 },
	{ X = -19.5, Z = 11, Dir = -1 },
}

-- Elevator stops. Surface: the station doorway faces the yard (+z, Layout.StationYaw); the rider
-- steps out onto the porch at design z -28.2 (yard x' 24, z -46.2), 7.8 studs from the shaft axis,
-- in the open between the tower and the canopy posts (Navigation.RouteGraph models the station as
-- its MineStation / MinePost blockers and turns routes out of the elevator at this point: keep
-- them in step when the station or this arrival moves).
-- Levels: the shaft opens into the chamber (+z); the rider steps out at z -27.
Layout.SurfaceArrival = { X = 20, Z = -28.2, DX = 0, DZ = 1 }
Layout.LevelArrival = { X = 20, Z = -27, DX = 0, DZ = 1 }

local EPS = 1e-4

local function layerNumber(layer: any): number?
	local n = tonumber(layer)
	if not n or n ~= math.floor(n) or n < 1 or n > 5 then
		return nil
	end
	return n
end
Layout.LayerNumber = layerNumber

function Layout.Level(layer: any): any
	local n = layerNumber(layer)
	return n and Layout.Levels[n] or nil
end

-- Unlocked layers as a bitmask (bit i-1 = layer i; the surface is always open), as MineWorld
-- writes it on the yard (attribute MineUnlocked).
function Layout.Mask(unlocked: any): number
	local mask = 1
	if type(unlocked) == "table" then
		for i = 2, 5 do
			if unlocked[tostring(i)] == true then
				mask += 2 ^ (i - 1)
			end
		end
	end
	return mask
end
function Layout.Unlocked(mask: any, layer: any): boolean
	local n = layerNumber(layer)
	if not n then
		return false
	end
	if n == 1 then
		return true
	end
	return math.floor((tonumber(mask) or 1) / 2 ^ (n - 1)) % 2 == 1
end

-- Where the dogs of a player whose CurrentLayer is `layer` work: "Surface" (layer 1, the kennel
-- pits as before) or the level key of the mine.
function Layout.DogPlacement(layer: any): string
	local n = layerNumber(layer) or 1
	if n <= 1 then
		return "Surface"
	end
	return Layout.Keys[n]
end

-- Mirrors a design CFrame for sx = -1 (M R M with M = diag(-1, 1, 1): a proper rotation).
function Layout.MirrorCF(cf: CFrame, sx: number): CFrame
	if sx >= 0 then
		return cf
	end
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

-- A CFrame at `pos` whose LookVector is `dir` (horizontal), built without CFrame.lookAt.
local function facing(pos: Vector3, dir: Vector3): CFrame
	local look = Vector3.new(dir.X, 0, dir.Z)
	if look.Magnitude < 1e-6 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local up = Vector3.new(0, 1, 0)
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, up)
end
Layout.Facing = facing

------------------------------------------------------------------------------------------------
-- Yard frame
------------------------------------------------------------------------------------------------
-- From the yard's parts (server, tests): the same rule as PlotAppearance.Frame and the sx rule
-- of PlotAppearance / MiningWorld (mirrored when DigSlot_1's pit lies at positive local X).
function Layout.FrameFromParts(yard: Instance): (CFrame?, number?)
	local landscape = yard:FindFirstChild("YardLandscape")
	local ground = landscape and landscape:FindFirstChild("YardFoundation")
	local storage = yard:FindFirstChild("StorageAnchor")
	if not (ground and ground:IsA("BasePart") and storage and storage:IsA("BasePart")) then
		return nil, nil
	end
	local g = (ground :: BasePart).CFrame.Position
	local s = (storage :: BasePart).CFrame.Position
	local center = Vector3.new(g.X, 1.2, g.Z)
	local frame = facing(center, Vector3.new(s.X, 1.2, s.Z) - center)
	local sx = 1
	local slot = yard:FindFirstChild("DigSlot_1")
	local pit = slot and slot:FindFirstChild("DarkExcavation")
	if pit and pit:IsA("BasePart") and frame:PointToObjectSpace(pit.CFrame.Position).X > 0 then
		sx = -1
	end
	return frame, sx
end

------------------------------------------------------------------------------------------------
-- A yard's layout
------------------------------------------------------------------------------------------------
local Yard = {}
Yard.__index = Yard

function Layout.New(frame: CFrame, sx: number, yardId: any?): any
	local p = frame.Position
	local self = setmetatable({}, Yard)
	self.Frame = frame
	self.Sx = (sx or 1) < 0 and -1 or 1
	self.YardId = yardId
	-- Base: the yard frame's rotation at world Y = 0 (design y is world y), shifted to the mine's
	-- origin in the yard (Layout.Origin; x' is mirrored with sx like every design x').
	self.Base = CFrame.new(p.X, 0, p.Z) * frame.Rotation * CFrame.new(self.Sx * Layout.Origin.X, 0, Layout.Origin.Z)
	return self
end

-- Design point -> world point.
function Yard.Point(self: any, x: number, y: number, z: number): Vector3
	return self.Base:PointToWorldSpace(Vector3.new(self.Sx * x, y, z))
end
-- Design direction -> world direction.
function Yard.Dir(self: any, dx: number, dz: number): Vector3
	return self.Base:VectorToWorldSpace(Vector3.new(self.Sx * dx, 0, dz))
end
-- Design CFrame -> world CFrame.
function Yard.ToWorld(self: any, cf: CFrame): CFrame
	return self.Base * Layout.MirrorCF(cf, self.Sx)
end
-- World point -> design point.
function Yard.ToDesign(self: any, pos: Vector3): Vector3
	local l = self.Base:PointToObjectSpace(pos)
	return Vector3.new(self.Sx * l.X, l.Y, l.Z)
end
-- World CFrame at a design point facing a design direction.
function Yard.CF(self: any, x: number, y: number, z: number, dx: number?, dz: number?): CFrame
	return facing(self:Point(x, y, z), self:Dir(dx or 0, dz or -1))
end

-- What a world position is inside: "Shaft" (below the surface, in the shaft column) or "Level"
-- (a chamber), with the layer; nil outside the mine.
function Yard.Contains(self: any, pos: Vector3): (string?, number?)
	if pos.Y > Layout.GroundY + 0.5 or pos.Y < Layout.Bottom then
		return nil, nil
	end
	local d = self:ToDesign(pos)
	local s = Layout.Shaft
	if math.abs(d.X - s.X) <= s.Half + 0.75 and math.abs(d.Z - s.Z) <= s.Half + 0.75 then
		return "Shaft", self:LayerAtY(pos.Y)
	end
	local c = Layout.Chamber
	if d.X >= c.X0 - 0.5 and d.X <= c.X1 + 0.5 and d.Z >= c.Z0 - 0.5 and d.Z <= c.Z1 + 0.5 then
		for layer, level in Layout.Levels do
			if pos.Y >= level.Floor - 4 and pos.Y <= level.Ceiling + 1 then
				return "Level", layer
			end
		end
	end
	return nil, nil
end

-- The level whose chamber height band contains y (shaft riders between levels: the next one up).
function Yard.LayerAtY(self: any, y: number): number
	local best = 1
	for layer = 2, 5 do
		local level = Layout.Levels[layer]
		if y <= level.Ceiling + 1 then
			best = layer
		end
	end
	return best
end

-- Dog worksite of a kennel slot on a level: Face = CFrame on the floor at the dig face point,
-- LookVector towards the ore vein; Loot = where a find appears (beside the dog, on the floor).
function Yard.Worksite(self: any, layer: any, slot: any): any
	local level = Layout.Level(layer)
	local site = Layout.Worksites[tonumber(slot) or 0]
	if not level or not site then
		return nil
	end
	local face = self:CF(site.X, level.Floor, site.Z, site.Dir, 0)
	-- Toward the chamber centre in z, 3 studs from the nose line, a little back from the face.
	local side = site.Z < 0 and 1 or -1
	local loot = self:CF(site.X - site.Dir * 2.2, level.Floor, site.Z + side * 3.2, -site.Dir, 0)
	return { Face = face, Loot = loot, Floor = level.Floor, Slot = tonumber(slot) }
end

-- Where a rider steps out (feet position), facing out of the cage.
function Yard.Arrival(self: any, layer: any): CFrame?
	local n = layerNumber(layer)
	if not n then
		return nil
	end
	if n == 1 then
		local a = Layout.SurfaceArrival
		return self:CF(a.X, Layout.GroundY, a.Z, a.DX, a.DZ)
	end
	local a = Layout.LevelArrival
	return self:CF(a.X, Layout.Levels[n].Floor, a.Z, a.DX, a.DZ)
end

-- Cage floor height at a stop.
function Layout.StopY(layer: any): number?
	local n = layerNumber(layer)
	if not n then
		return nil
	end
	if n == 1 then
		return Layout.GroundY
	end
	return Layout.Levels[n].Floor
end

-- World CFrame of the cage floor centre at a stop (cage front = LookVector).
function Yard.StopCF(self: any, layer: any): CFrame?
	local y = Layout.StopY(layer)
	if not y then
		return nil
	end
	local s = Layout.Shaft
	return self:CF(s.X, y, s.Z, 0, 1)
end

-- World AABB of the shaft opening column (for carving): centre CFrame and size.
function Yard.Hole(self: any, top: number?, bottom: number?): (CFrame, Vector3)
	local s = Layout.Shaft
	local t, b = top or 2, bottom or (Layout.IslandBottom - 2)
	return self:CF(s.X, (t + b) / 2, s.Z, 0, -1), Vector3.new(s.Half * 2, t - b, s.Half * 2)
end

------------------------------------------------------------------------------------------------
-- Yards
------------------------------------------------------------------------------------------------
local cache = setmetatable({}, { __mode = "k" })

-- The layout of a yard model: from the MineFrame / MineSx attributes written by MineWorld
-- (clients: they replicate even while the yard's parts are streamed out), else from the parts.
function Layout.ForYard(yard: Instance?): any
	if not yard then
		return nil
	end
	local cached = cache[yard]
	if cached then
		return cached
	end
	local frame = yard:GetAttribute("MineFrame")
	local sx = yard:GetAttribute("MineSx")
	if typeof(frame) ~= "CFrame" or type(sx) ~= "number" then
		frame, sx = Layout.FrameFromParts(yard)
	end
	if typeof(frame) ~= "CFrame" then
		return nil
	end
	local layout = Layout.New(frame :: CFrame, sx :: number, yard:GetAttribute("YardId"))
	cache[yard] = layout
	return layout
end

-- First yard (of a list or a folder) whose mine contains pos: yard, layout, kind, layer.
function Layout.Find(yards: any, pos: Vector3): (Instance?, any, string?, number?)
	if pos.Y > Layout.GroundY + 0.5 or pos.Y < Layout.Bottom then
		return nil, nil, nil, nil
	end
	local list = typeof(yards) == "Instance" and yards:GetChildren() or yards
	for _, yard in list do
		if typeof(yard) == "Instance" and yard:GetAttribute("YardId") ~= nil then
			local layout = Layout.ForYard(yard)
			if layout then
				local kind, layer = layout:Contains(pos)
				if kind then
					return yard, layout, kind, layer
				end
			end
		end
	end
	return nil, nil, nil, nil
end

------------------------------------------------------------------------------------------------
-- Carving maths
------------------------------------------------------------------------------------------------
-- rect = {X0, X1, Z0, Z1}. Returns the non-overlapping rects that exactly cover `box` minus
-- `hole` (at most 4; the box itself when they do not overlap).
function Layout.CarveRect(box: any, hole: any): { any }
	local x0, x1 = math.max(box.X0, hole.X0), math.min(box.X1, hole.X1)
	local z0, z1 = math.max(box.Z0, hole.Z0), math.min(box.Z1, hole.Z1)
	if x1 - x0 <= EPS or z1 - z0 <= EPS then
		return { box }
	end
	local out = {}
	local function add(a, b, c, d)
		if b - a > EPS and d - c > EPS then
			table.insert(out, { X0 = a, X1 = b, Z0 = c, Z1 = d })
		end
	end
	add(box.X0, x0, box.Z0, box.Z1)
	add(x1, box.X1, box.Z0, box.Z1)
	add(x0, x1, box.Z0, z0)
	add(x0, x1, z1, box.Z1)
	return out
end

-- Carves several holes out of one rect (each hole a vertical column through the whole box).
function Layout.CarveRects(box: any, holes: { any }): { any }
	local rects = { box }
	for _, hole in holes do
		local nextRects = {}
		for _, r in rects do
			for _, piece in Layout.CarveRect(r, hole) do
				table.insert(nextRects, piece)
			end
		end
		rects = nextRects
	end
	return rects
end

-- A part's footprint in its own frame and the holes (world CFrame + size columns) expressed in
-- it. Only parts whose local Y axis is vertical and whose X/Z axes are aligned with the holes
-- can be carved; returns nil otherwise.
function Layout.LocalHoles(partCF: CFrame, partSize: Vector3, holes: { any }): (any, { any }?)
	if math.abs(partCF.UpVector.Y) < 0.999 then
		return nil, nil
	end
	local box = { X0 = -partSize.X / 2, X1 = partSize.X / 2, Z0 = -partSize.Z / 2, Z1 = partSize.Z / 2 }
	local out = {}
	for _, hole in holes do
		local cf, size = hole.CFrame, hole.Size
		local hx0, hx1, hz0, hz1 = math.huge, -math.huge, math.huge, -math.huge
		for _, dx in { -0.5, 0.5 } do
			for _, dz in { -0.5, 0.5 } do
				local p = partCF:PointToObjectSpace(cf:PointToWorldSpace(Vector3.new(size.X * dx, 0, size.Z * dz)))
				hx0, hx1 = math.min(hx0, p.X), math.max(hx1, p.X)
				hz0, hz1 = math.min(hz0, p.Z), math.max(hz1, p.Z)
			end
		end
		-- The hole must be axis-aligned in the part's frame (its corners span a rect of its area).
		local area = size.X * size.Z
		if math.abs((hx1 - hx0) * (hz1 - hz0) - area) > 0.05 * area + 0.01 then
			return nil, nil
		end
		-- Vertical overlap with the part.
		local py = partCF:PointToObjectSpace(cf.Position).Y
		local half = partSize.Y / 2
		if math.abs(py) <= half + size.Y / 2 then
			table.insert(out, { X0 = hx0, X1 = hx1, Z0 = hz0, Z1 = hz1 })
		end
	end
	return box, out
end

return Layout
