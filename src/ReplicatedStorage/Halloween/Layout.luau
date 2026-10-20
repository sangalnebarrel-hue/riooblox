-- THE DEAD YARD layout (ReplicatedStorage.Halloween.Layout). The only place where Dead Yard coordinates live:
-- build-time builders, server gameplay and client FX all read these. World axes: players arrive from -X along z=575;
-- the lab compound is at -Z, cliffs (island edge) at +X and +Z. Floor top y 0.2, Hollow Lane top y 0.5.
local V = Vector3.new
local L = {}

L.Zone = { Min = V(33, -20, 531), Max = V(214.5, 60, 745.3) }
L.Zone.Center = (L.Zone.Min + L.Zone.Max) / 2
L.Zone.Size = L.Zone.Max - L.Zone.Min
L.Inner = { X0 = 33.5, X1 = 209.5, Z0 = 531.5, Z1 = 744.8 } -- fence line (players stay inside)
L.FloorY = 0.2
L.LaneY = 0.5

-- Gate (faces -X toward the boulevard). Opening z 566..584; leaves hinge on the pillars and swing inward (+X).
L.Gate = {
	Center = V(36, 0.2, 575), Facing = V(-1, 0, 0), Opening = { Z0 = 566, Z1 = 584 }, Height = 22,
	PillarL = V(36, 0.2, 564), PillarR = V(36, 0.2, 586), OpenRange = 34, CloseRange = 46,
	Approach = V(14, 0.5, 575), -- boulevard side, where the approach effects start
	Sign = V(33.6, 24.5, 575), Plaque = V(33.6, 6, 556),
}

-- Hollow Lane (Trick-or-Treat street) and the 7 houses on its -Z side (doors face +Z onto the lane).
L.Lane = { X0 = 38, X1 = 206, Z0 = 568, Z1 = 582 }
L.Houses = {}
for i, x in ipairs({ 58, 81, 104, 127, 150, 173, 196 }) do
	L.Houses[i] = {
		Index = i, Center = V(x, 0.2, 550), Size = V(16, 12, 14), -- footprint x-8..x+8, z 543..557
		Door = V(x, 0.5, 557), Prompt = V(x, 3, 559.5), Porch = V(x, 0.5, 562), Facing = V(0, 0, 1),
	}
end

-- Haunted Cauldron (social hub on the gate sightline) and the Grave Bell (boss summon) at the pit's north rim.
L.Cauldron = { Center = V(128, 0.2, 612), PlazaRadius = 14, Radius = 5.5, Height = 6.5, Walk = { X0 = 122, X1 = 134, Z0 = 582, Z1 = 598 },
	Prompt = V(128, 3, 602), Drop = V(128, 7.5, 612) }
L.Bell = { Position = V(146, 0.5, 636), Facing = V(0, 0, 1), Prompt = V(146, 3, 634) }

-- Graveyard Pit = boss arena. Opening rim y 0.2, terrace ring y -4, arena floor y -8.
L.Pit = {
	Center = V(128, -8, 672), Rim = { X0 = 98, X1 = 158, Z0 = 642, Z1 = 702 }, TerraceY = -4, FloorY = -8,
	Arena = { X0 = 104, X1 = 152, Z0 = 648, Z1 = 696 },
	Ramps = { -- 8 wide; Top on the rim, Mid on the terrace, Bottom on the arena floor
		{ Id = "N", Top = V(128, 0.2, 642), Mid = V(128, -4, 648), Bottom = V(128, -8, 658) },
		{ Id = "S", Top = V(128, 0.2, 702), Mid = V(128, -4, 696), Bottom = V(128, -8, 686) },
		{ Id = "W", Top = V(98, 0.2, 672), Mid = V(104, -4, 672), Bottom = V(114, -8, 672) },
		{ Id = "E", Top = V(158, 0.2, 672), Mid = V(152, -4, 672), Bottom = V(142, -8, 672) },
	},
	SpectatorRadius = { 30, 36 },
}
L.Boss = {
	Spawn = V(128, -8, 672), Facing = V(0, 0, -1), LeashRadius = 20,
	Mounds = {}, SkeletonSpawns = {}, RockZone = { X0 = 100, X1 = 156, Z0 = 644, Z1 = 700 },
	Camera = { Eye = V(128, 26, 616), Focus = V(128, 2, 672) }, -- entrance shot (players on the north rim)
}
-- mounds and skeleton spawns stay off the 4 ramps (which run along the N/S/E/W axes into the arena)
for i, m in ipairs({ { 14, 45 }, { 14, 135 }, { 14, 225 }, { 14, 315 }, { 8, 0 }, { 8, 180 } }) do
	local a = math.rad(m[2])
	L.Boss.Mounds[i] = V(128 + math.cos(a) * m[1], -8, 672 + math.sin(a) * m[1])
end
for i = 1, 8 do
	local a = (i - .5) / 8 * math.pi * 2
	L.Boss.SkeletonSpawns[i] = V(128 + math.cos(a) * 19, -8, 672 + math.sin(a) * 19)
end

-- Big set pieces along the edges (tall content at +X/+Z, low content in the middle for sightlines).
L.Crypts = {
	Grand = { X0 = 114, X1 = 142, Z0 = 724, Z1 = 742, Height = 20, Door = V(128, 0.2, 724) },
	B = { X0 = 176, X1 = 196, Z0 = 724, Z1 = 742, Height = 14, Door = V(186, 0.2, 724) },
	C = { X0 = 40, X1 = 56, Z0 = 734, Z1 = 744, Height = 10, Door = V(48, 0.2, 734) },
}
L.BrokenLab = { X0 = 184, X1 = 208, Z0 = 604, Z1 = 634, Height = 14, OpenSide = V(-1, 0, 0) }
L.Kennels = { V(104, 0.2, 592), V(152, 0.2, 596), V(100, 0.2, 628), V(156, 0.2, 628) }
L.Carts = { V(164, 0.2, 592), V(200, 0.2, 668), V(98, 0.2, 740) }
L.Graveyard = { X0 = 40, X1 = 94, Z0 = 590, Z1 = 742 }
L.OreField = { X0 = 160, X1 = 206, Z0 = 590, Z1 = 725 }

-- Haunted dig spot points (Blood Moon) and Halloween ore nodes (always on). Keep 4+ studs clear of solid props.
L.DigPoints = {
	V(50, 0.2, 604), V(50, 0.2, 628), V(50, 0.2, 652), V(50, 0.2, 676), V(50, 0.2, 700), V(50, 0.2, 724),
	V(68, 0.2, 616), V(68, 0.2, 640), V(68, 0.2, 664), V(68, 0.2, 688), V(68, 0.2, 712),
	V(86, 0.2, 604), V(86, 0.2, 628), V(86, 0.2, 722), V(100, 0.2, 716), V(156, 0.2, 716),
}
L.OrePoints = {
	V(176, 0.2, 604), V(196, 0.2, 598), V(172, 0.2, 628), V(190, 0.2, 642), V(202, 0.2, 652),
	V(176, 0.2, 656), V(194, 0.2, 672), V(202, 0.2, 692), V(178, 0.2, 690), V(160, 0.2, 722),
}

-- Ambient life
L.SilhouettePath = { V(30, 0.2, 751), V(108, 0.2, 751), V(150, 0.2, 751), V(206, 0.2, 751) } -- strip behind the south fence
L.Moon = { Position = V(380, 150, 650), Radius = 44, BloodRadius = 74 } -- over the void east of the yard, seen from the gate
L.Nav = { Gate = V(42, 0.5, 575), Lane = V(128, 0.5, 575), Cauldron = V(128, 0.5, 598), LaneEast = V(196, 0.5, 575),
	Goal = V(128, 0.5, 600), Pointer = V(128, 9, 612) }
L.Arrival = V(44, 3, 575) -- teleport / respawn point just inside the gate

-- Fence runs (x0,z0,x1,z1) — the west run has the gate gap z 566..584.
L.FenceRuns = {
	{ 33.5, 531.5, 33.5, 564 }, { 33.5, 586, 33.5, 744.8 },
	{ 33.5, 531.5, 209.5, 531.5 }, { 209.5, 531.5, 209.5, 744.8 }, { 33.5, 744.8, 209.5, 744.8 },
}

function L.InZone(pos: Vector3, margin: number?): boolean
	local m = margin or 0
	local a, b = L.Zone.Min, L.Zone.Max
	return pos.X >= a.X - m and pos.X <= b.X + m and pos.Z >= a.Z - m and pos.Z <= b.Z + m and pos.Y >= a.Y - m and pos.Y <= b.Y + m
end

-- 0 outside .. 1 inside, with a smooth feather band around the footprint (y ignored)
function L.Weight(pos: Vector3, feather: number?): number
	local f = feather or 60
	local a, b = L.Zone.Min, L.Zone.Max
	local dx = math.max(a.X - pos.X, pos.X - b.X, 0)
	local dz = math.max(a.Z - pos.Z, pos.Z - b.Z, 0)
	local d = math.sqrt(dx * dx + dz * dz)
	local t = math.clamp(1 - d / f, 0, 1)
	return t * t * (3 - 2 * t)
end

function L.InPit(pos: Vector3): boolean
	local r = L.Pit.Rim
	return pos.X >= r.X0 and pos.X <= r.X1 and pos.Z >= r.Z0 and pos.Z <= r.Z1 and pos.Y < 4
end

return L
