--!strict
-- Geometry of the NUCLEAR MUTATION TOWER (the mutation lab is a nuclear power plant cooling tower
-- now), shared by the builder (ServerScriptService.NuclearTowerBuild), the world script and the
-- client cinematic (Modules.LabPresentation). Pure data + maths: no services, safe in Lune.
--
-- World frame: axes = world axes. The compound stands where the old lab building stood. The tower
-- axis is at Center; its door, the loading pad, the console and the entrance all lie on the west
-- (-X) axis at Z = Center.Z, so a player walking in from the promenade faces the tower.
local L = {}

L.Version = 1
L.Name = "NuclearCompound" -- model under Workspace.DOGROTS_District.05_MutationLab
L.Ground = 0.45 -- top of the plaza slab
L.Center = Vector3.new(128, 0.45, 477)

-- The cooling tower: a hyperboloid shell of concrete facets (two hyperbolas meeting at the waist).
L.Tower = {
	Height = 118,
	BaseRadius = 25,
	WaistRadius = 16,
	WaistY = 90,
	TopRadius = 18.6,
	Facets = 36,
	Bands = { 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 90, 98, 106, 112, 118 }, -- the shell starts on its legs at 8
	Thickness = 1.6,
}
local T = L.Tower
local LOWER_C = T.WaistY / math.sqrt((T.BaseRadius / T.WaistRadius) ^ 2 - 1)
local UPPER_C = (T.Height - T.WaistY) / math.sqrt((T.TopRadius / T.WaistRadius) ^ 2 - 1)
-- Outer radius of the shell at height y above the ground.
function L.Radius(y: number): number
	local c = y < T.WaistY and LOWER_C or UPPER_C
	local t = (y - T.WaistY) / c
	return T.WaistRadius * math.sqrt(1 + t * t)
end
-- A point on the shell surface: angle a (radians, 0 = +X, pi = west), height y, extra = outward offset.
function L.Shell(a: number, y: number, extra: number?): Vector3
	local r = L.Radius(y) + (extra or 0)
	return L.Center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end
-- Frame on the shell (Right = tangent, Up = along the surface towards the top, -Look = outward).
function L.ShellFrame(a: number, y: number, extra: number?): CFrame
	local p = L.Shell(a, y, extra)
	local dy = 1
	local dr = L.Radius(y + dy) - L.Radius(y - dy)
	local outward = Vector3.new(math.cos(a), 0, math.sin(a))
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	local along = (outward * dr + Vector3.new(0, 2 * dy, 0)).Unit
	-- fromMatrix(X = tangent, Y = along): Z = X x Y points inwards, so the front (-Z) faces out.
	return CFrame.fromMatrix(p, tangent, along)
end
L.West = math.pi

-- The emblem on the west face: a radiation trefoil with a glowing dog paw in its centre.
L.Emblem = { Y = 50, Radius = 11.5 }

-- The portal on the west side: a concrete block in the shell holding the blast door (WARNING).
L.Portal = { Front = 95, Back = 107, Width = 16, Height = 22 }
L.Door = { Width = 9.6, Height = 12, Rise = 10.3, Thickness = 0.8 } -- rises into the header block
L.DoorX = L.Portal.Front + 0.5 -- the door leaf's centre (X)
-- The dark chamber behind the door, where the mechanical arm lives.
L.Chamber = { Front = 95.6, Back = 107, Height = 12 }

-- The loading pad in front of the door: the dog is placed here.
L.Pad = { Center = Vector3.new(87.5, 0.45, 477), Radius = 3.6 }
L.DogLimits = Vector3.new(5, 4, 5)
-- Where the owner stands while the cinematic plays (beside the pad, facing it): the dog is taken out
-- of the inventory and set down here, and walks back here when it leaves the tower. North-west of the pad:
-- the cameras around the owner look south-east (north of the plaza stands
-- 37_AttractionRefresh.GlobalEventComingSoon.OpaqueBlackCuboid, 50 studs tall: low shots must not look north).
L.OwnerSpot = Vector3.new(83.2, 0.45, 482.2)
-- Where the owner stands while pressing START (the console's operator mat).
L.OperatorSpot = Vector3.new(74.2, 0.45, 477)
-- The Void island's portal (Workspace.DOGROTS_District.13_TheVoid.VoidPortalCore), used by the VOID shots.
L.VoidPortal = Vector3.new(903.2, 236, -892.6)

-- The mechanical arm: a ceiling turret at the back of the chamber, two links and a claw.
L.Arm = {
	Base = Vector3.new(103, 10.8, 477), -- shoulder joint (world)
	Upper = 9.4,
	Fore = 8.6,
	Rest = Vector3.new(101.5, 5.2, 477), -- claw target when folded inside
	Grab = Vector3.new(87.5, 2.6, 477), -- claw target over the pad
	Hold = Vector3.new(101, 6.2, 477), -- dog held inside the chamber
	-- telescopic links: folded they shrink to MinUpper so the elbow stays inside the chamber (with fixed
	-- 9.4 / 8.6 links the elbow stuck out through the closed blast door at x 93.6)
	MinUpper = 3.2,
	Bend = math.rad(25),
}

-- The console (operator side): desk front faces west; the operator stands at ~X 74.
L.Console = {
	Center = Vector3.new(79, 0.45, 477),
	Width = 10,
	Depth = 3.2,
	DeskTop = 3.4,
	Operator = Vector3.new(74.2, 0.45, 477),
}
L.Anchor = Vector3.new(77.0, 3.9, 477) -- InteractionAnchor (the console prompt, LabAccess reach)

-- The plaza (concrete slab) and the zone LabAccess accepts.
L.Plaza = { X0 = 62, X1 = 172, Z0 = 428, Z1 = 526 }
L.Zone = { X0 = 64, X1 = 112, Z0 = 446, Z1 = 508, Y0 = -1, Y1 = 30 }

-- Nuclear waste barrels: clusters {X, Z, count, seed}.
L.Barrels = {
	{ 101, 451, 6, 1 }, { 101, 503, 6, 2 }, { 153, 447, 7, 3 }, { 155, 507, 6, 4 },
	{ 68, 449, 4, 5 }, { 68, 505, 4, 6 }, { 140, 434, 4, 7 }, { 140, 520, 4, 8 },
}
-- The toppled, leaking barrel by the pad.
L.Spill = { Barrel = Vector3.new(92, 0.45, 495), Puddle = Vector3.new(89.5, 0.47, 491) }

-- Camera shots of the cinematic (Modules.LabPresentation): {Eye, Focus, Fov} in world space, Eye1 / Focus1 /
-- Fov1 = where a slow eased move ends. In order: Operator (START over the owner's shoulder), Place, Door,
-- Grab (high), [look: over the owner's shoulder, computed], Intake, Crane, Hero (the crown and the beam),
-- Chamber (the reel and the burst inside), the variant scenes (Hero, Crown, Screen, DoorLow, near the
-- owner), ExitDoor, [the walk out, the close-ups of the paws / head / tail and the pad orbit: computed from
-- the dog standing on the pad facing its owner], Final (home).
-- North of the plaza (z > 531, x 33 .. 214.5, up to y 50) stands 37_AttractionRefresh.GlobalEventComingSoon.
-- OpaqueBlackCuboid: every low shot looks east-south-east .. south-west so it never shows behind the subject
-- (looking east, north is on the frame's right; phones are up to 2.17:1 wide and Roblox's Fov is vertical,
-- so check new shots at that width).
local V = Vector3.new
L.Shots = {
	Operator = { Eye = V(71.4, 8.4, 482.4), Eye1 = V(72.2, 7.6, 481.4), Focus = V(78.6, 3.9, 476.6), Focus1 = V(78.6, 4.3, 476.8), Fov = 46, Fov1 = 42 },
	Console = { Eye = V(70.5, 7.2, 469.5), Focus = V(80.5, 4.6, 477), Fov = 50 }, -- unused (kept for old callers)
	-- in front of the owner on the pad side: the dog comes out of the inventory (the build also puts the
	-- lab's PresentationCamera anchor here)
	Place = { Eye = V(91.9, 5.05, 482.7), Eye1 = V(91.4, 4.75, 482.3), Focus = V(86.0, 2.4, 480.4), Fov = 50 },
	Door = { Eye = V(81.4, 6.0, 479.8), Eye1 = V(82.2, 5.6, 479.2), Focus = V(95.5, 6.0, 473.6), Focus1 = V(95.5, 5.4, 473.6), Fov = 54 },
	Grab = { Eye = V(82.6, 15, 486.6), Eye1 = V(83.6, 13.6, 485.0), Fov = 52 },
	-- low, just in front of the owner (clear of the avatar and its accessories): the dog is pulled in, the
	-- door slams
	Intake = { Eye = V(84.8, 2.9, 480.4), Eye1 = V(84.3, 2.7, 481.0), Focus = V(96.5, 5.6, 473.8), Fov = 58 },
	Crane = { Eye = V(86, 3, 492), Eye1 = V(90, 26, 508), Focus = V(104, 14, 475), Focus1 = V(126, 74, 475), Fov = 62 },
	Hero = { Eye = V(88, 3, 490), Eye1 = V(89, 3.4, 489), Focus = V(128, 118, 462), Focus1 = V(128, 128, 462), Fov = 56 },
	Crown = { Eye = V(100, 150, 512), Focus = V(128, 112, 474), Fov = 56 },
	Chamber = { Eye = V(97.0, 7.0, 473.4), Fov = 64 },
	-- the door opens on the mutated dog (the focus leans 40% from the dog to Focus: south of the door, so a
	-- phone's wide frame never reaches past the tower's north side)
	ExitDoor = { Eye = V(84.6, 4.2, 480.4), Eye1 = V(86.4, 3.9, 479.6), Focus = V(98, 3.0, 472.4), Fov = 48 },
	Final = { Eye = V(91.0, 5.4, 488.6), Focus = V(84.6, 3.6, 480.6), Fov = 52 }, -- home: the dog and its owner
	Screen = { Eye = V(75.2, 9.0, 478.4), Focus = V(80.1, 8.5, 477), Fov = 46 }, -- the main screen (MUTATION FAILED)
	DoorLow = { Eye = V(85.6, 1.8, 486.2), Eye1 = V(86.4, 2.4, 485.0), Focus = V(95, 8, 476), Fov = 62, Fov1 = 66 }, -- SHINY: the light round the door
}

-- Variant colours (match the dogs' mutation glow).
L.Colors = {
	Normal = Color3.fromRGB(120, 255, 140),
	Shiny = Color3.fromRGB(220, 245, 255),
	Golden = Color3.fromRGB(255, 199, 54),
	Corrupted = Color3.fromRGB(235, 40, 60),
	Glitched = Color3.fromRGB(40, 239, 213),
	Void = Color3.fromRGB(140, 60, 255),
}
L.Toxic = Color3.fromRGB(110, 255, 90)
L.Hazard = Color3.fromRGB(255, 206, 0)

-- IK of the telescopic arm for a claw target (world): the upper link points at the target bent Bend
-- upwards and is as long as needed (MinUpper..Upper); the forearm stretches to the wrist.
-- Returns the elbow and the wrist positions.
function L.ArmIK(target: Vector3): (Vector3, Vector3)
	local A = L.Arm
	local base = A.Base
	local d = target - base
	local dist = math.clamp(d.Magnitude, 0.5, A.Upper + A.Fore - 0.05)
	local dir = d.Magnitude > 1e-3 and d.Unit or Vector3.new(-1, 0, 0)
	local side = dir:Cross(Vector3.new(0, 1, 0))
	if side.Magnitude < 1e-3 then side = Vector3.new(0, 0, 1) end
	local up = side.Unit:Cross(dir).Unit
	if up.Y < 0 then up = -up end
	local u = math.clamp(dist * 0.55, A.MinUpper or 3.2, A.Upper)
	-- folded: bent up (the elbow stays in the chamber); reaching out: a straight boom (it passes under
	-- the raised blast door, whose bottom edge is at Ground + Door.Rise)
	local b = (A.Bend or math.rad(25)) * math.clamp((13 - dist) / 7, 0, 1)
	local elbow = base + (dir * math.cos(b) + up * math.sin(b)) * u
	local wrist = base + dir * dist
	return elbow, wrist
end

-- Poses the arm model (names from NuclearTowerBuild) so the claw reaches `target`; open 0..1 spreads
-- the claw fingers. Writes CFrames and the telescopic links' lengths (Size.Y): client-side animation of
-- anchored parts (LabPresentation remembers both and puts them back).
function L.PoseArm(arm: Instance, target: Vector3, open: number?)
	local A = L.Arm
	local elbow, wrist = L.ArmIK(target)
	local function seg(name: string, a: Vector3, b: Vector3, stretch: number?)
		local p = arm:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local d = b - a
			if stretch then p.Size = Vector3.new(p.Size.X, math.max(0.2, d.Magnitude * stretch), p.Size.Z) end
			local mid = (a + b) / 2
			local look = d.Magnitude > 1e-3 and d.Unit or Vector3.new(0, -1, 0)
			local right = look:Cross(Vector3.new(0, 0, 1))
			if right.Magnitude < 1e-3 then right = Vector3.new(1, 0, 0) end
			p.CFrame = CFrame.fromMatrix(mid, right.Unit, look) -- local Y along the link
		end
	end
	local function at(name: string, pos: Vector3)
		local p = arm:FindFirstChild(name)
		if p and p:IsA("BasePart") then p.CFrame = CFrame.new(pos) * (p.CFrame - p.CFrame.Position) end
	end
	seg("UpperArm", A.Base, elbow, 1)
	seg("UpperPiston", A.Base + Vector3.new(0, 0, 0.75), elbow + Vector3.new(0, 0, 0.75), 0.8)
	at("Elbow", elbow)
	seg("ForeArm", elbow, wrist, 1)
	seg("ForePiston", elbow + Vector3.new(0, 0, -0.75), wrist + Vector3.new(0, 0, -0.75), 0.8)
	at("Wrist", wrist)
	local palm = arm:FindFirstChild("Palm")
	if palm and palm:IsA("BasePart") then palm.CFrame = CFrame.new(wrist + Vector3.new(0, -0.55, 0)) end
	local o = math.clamp(open or 0, 0, 1)
	for i = 1, 3 do
		local a = (i - 1) / 3 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local root = wrist + Vector3.new(0, -0.9, 0) + dir * 0.55
		local spread = 0.25 + o * 0.9
		local mid = root + dir * spread + Vector3.new(0, -1.1, 0)
		local tip = mid + dir * (-0.35 + o * 0.25) + Vector3.new(0, -0.9, 0)
		seg("Finger" .. i .. "A", root, mid)
		seg("Finger" .. i .. "B", mid, tip)
	end
	local turret = arm:FindFirstChild("Turret")
	if turret and turret:IsA("BasePart") then
		local flat = Vector3.new(target.X - A.Base.X, 0, target.Z - A.Base.Z)
		local yaw = flat.Magnitude > 1e-3 and math.atan2(-flat.X, -flat.Z) or 0
		turret.CFrame = CFrame.new(A.Base + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, yaw, 0)
	end
	return wrist
end

-- Reel steps of the mutation roulette: slows down like a slot reel and lands on `result`.
function L.ReelSteps(result: string, duration: number, names: { string }): { { At: number, Name: string } }
	local intervals = {}
	local total, dt = 0, 0.06
	while total < duration * 0.82 do
		table.insert(intervals, dt)
		total += dt
		dt *= 1.12
	end
	local scale = duration / total
	local before = result == "Normal" and "Shiny" or "Normal"
	local out = {}
	local at = 0
	local n = #intervals
	for i = 1, n do
		at += intervals[i] * scale
		local name = names[(i - 1) % #names + 1]
		if i == n then
			name = result
		elseif i == n - 1 then
			name = before
		end
		out[i] = { At = at, Name = name }
	end
	return out
end

return L
