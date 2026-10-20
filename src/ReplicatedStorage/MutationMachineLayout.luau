--!strict
-- Geometry of the NUCLEAR MUTATION MACHINE in the Mutation Lab (docs/LAB.md), shared by the server
-- builder (ServerScriptService.MutationMachineBuild) and the client cinematic (Modules.LabPresentation).
-- Pure data + maths: no services, safe in Lune tests and the QA scene.
--
-- Local frame: origin = the tube axis on the hall floor (PanelFloor top, world (133, 2.2, 477)),
-- axes = world axes. +X points from the console (west) to the tube (east), +Y up, +Z south.
-- The console's operator stands at local x ~ -29 and looks +X at the tube.
local M = {}

M.Version = 2
M.Name = "MutationMachine" -- the model under Workspace.DOGROTS_District.05_MutationLab
M.Origin = Vector3.new(133, 2.2, 477)
M.Frame = CFrame.new(M.Origin)

-- Tube (all Y values are local heights above the hall floor).
M.Tube = {
	Radius = 8.5, -- glass radius (diameter 17); the hall cross beams leave 10.35 studs either side
	PedestalTop = 4.3, -- tube floor (top of the solid pedestal)
	FloorTop = 4.5, -- top of the glowing energy floor disc inside the tube
	IntakeTop = 11.3, -- the intake ring (with the loading door) spans PedestalTop..IntakeTop
	GlassTop = 31.0, -- in-hall glass; the membrane and the upper collar close the chamber
	LiquidRadius = 8.1,
	LiquidIdle = 4.6, -- drained
	LiquidFull = 27.5, -- covers the dog during the mutation
	Rotors = { { Name = "Rotor1", Y = 13.0 }, { Name = "Rotor2", Y = 21.6 } },
	Rails = 4, -- vertical energy rails inside the glass (EnergyRail1..4)
	RailRadius = 7.5,
	InjectorTip = 25.4, -- the core's tip hanging from the membrane
	UpperBottom = 37.6, -- top of the roof deck: the giant column (M.Tower) starts here
	UpperTop = 218.0, -- the giant column's crown rim (M.Tower.Top)
	Top = 252.0, -- the warning beacon on the spire
}

-- The giant reactor column above the roof (the district landmark): a cooling-tower hyperboloid. A twisted
-- steel lattice of straight rods (both families of the hyperboloid's generators; they turn 45 degrees per
-- section and meet at the foot, the waist and the crown), a faceted glass shell just inside it (drums
-- between the Drums joints, glowing rings at the joints), a coolant pool, a plasma column with the core
-- and a DNA double helix, a flared crown with a glowing rim, tesla coils, steam and the beacon spire.
-- Radii are the lattice's. The roof's air handlers (r >= 19 below local y 43) limit the foot's radius.
M.Tower = {
	Plinth = 36.3, -- bottom of the roof plinth (on the roof deck and the roof rails)
	Bottom = 38.4, -- lattice foot (top of the foot ring)
	Waist = 175.0, -- narrowest height
	Top = 218.0, -- crown rim
	WaistRadius = 11.8, -- the foot and the crown are WaistRadius * sqrt(2) (16.7)
	Inset = 1.0, -- glass radius = lattice radius - Inset (the rods stay outside the glass)
	Rods = 20, -- per family and section (the 45-degree turn is 2.5 rod spacings: the families meet)
	Facets = 16, -- glass panels per drum and segments per ring
	Drums = { 38.4, 65.7, 93.0, 120.3, 147.6, 175.0, 189.3, 203.7, 218.0 }, -- glass joints (rings between)
	PoolTop = 64.0, -- coolant pool at the column's foot
	Helix = { Bottom = 82, Top = 206, Radius = 5.6, Pitch = 32, Step = 45 }, -- degrees per ball
	Hub = 228.0, -- where the crown struts meet under the spire
}
M.Tower.RimRadius = M.Tower.WaistRadius * math.sqrt(2)

-- Lattice radius of the giant column at local height y (two hyperbolas meeting at the waist).
function M.TowerRadius(y: number): number
	local W = M.Tower
	local c = y < W.Waist and (W.Waist - W.Bottom) or (W.Top - W.Waist)
	local t = (y - W.Waist) / c
	return W.WaistRadius * math.sqrt(1 + t * t)
end
-- Radius of the glass shell (its facets' inner circle) at local height y: linear between the joints.
function M.TowerGlass(y: number): number
	local W = M.Tower
	local d = W.Drums
	for i = 1, #d - 1 do
		if y <= d[i + 1] or i == #d - 1 then
			local f = math.clamp((y - d[i]) / (d[i + 1] - d[i]), 0, 1)
			local r0, r1 = M.TowerRadius(d[i]), M.TowerRadius(d[i + 1])
			return r0 + (r1 - r0) * f - W.Inset
		end
	end
	return W.WaistRadius - W.Inset
end
-- Ends (local) of lattice rod k (0..Rods-1) of family s (1 or -1) in section 1 (foot..waist) or
-- 2 (waist..crown): straight generators of x^2 + z^2 = a^2 (1 + t^2), y = Waist + c t.
function M.TowerRod(section: number, k: number, s: number): (Vector3, Vector3)
	local W = M.Tower
	local a = W.WaistRadius
	local theta = k * 2 * math.pi / W.Rods
	local cos, sin = math.cos(theta), math.sin(theta)
	local function point(t: number, c: number): Vector3
		local x, z = a, s * a * t
		return Vector3.new(x * cos - z * sin, W.Waist + c * t, x * sin + z * cos)
	end
	if section == 1 then
		local c = W.Waist - W.Bottom
		return point(-1, c), point(0, c)
	end
	local c = W.Top - W.Waist
	return point(0, c), point(1, c)
end

-- Loading door: a segment of the intake ring facing the console (-X). It drops into the pedestal.
M.Door = { Bottom = 4.8, Top = 10.7, Radius = 9.6, Width = 6.2, Drop = 6.8 }

-- Lift: a carriage on two rails (RailTop), a telescopic mast and the platform the dog stands on.
M.Lift = {
	RailTop = 4.8,
	CarriageHeight = 0.8,
	DeckThickness = 0.5,
	RestX = -16, -- at the console's loading bay
	InsideX = 0, -- tube axis
	RestDeck = 5.6, -- platform bottom at rest (on the carriage)
	RaisedDeck = 13.7, -- platform bottom when lifted into the chamber
}
M.Lift.CarriageTop = M.Lift.RailTop + M.Lift.CarriageHeight
-- The dog clone is scaled to fit this box (it must pass the loading door standing on the platform).
M.DogLimits = Vector3.new(5.2, 4.1, 5.2)

-- Placer arm on the console: places the dog on the platform, then folds away.
M.Arm = {
	Base = Vector3.new(-13.2, 0.5, -5.8),
	ShoulderHeight = 2.5,
	Upper = 6.4,
	Fore = 5.6,
	Rest = Vector3.new(-12.2, 12.4, -6.6),
	Place = Vector3.new(-16, 11.0, 0),
}

-- Console (operator side). The ACTIVATE button sits on the sloped command desk. The mega desk wraps
-- around the operator: wings (U arms) either side of the walkway (|z| < WingInner stays free) and two
-- instrument towers behind the command desk. The gap between the towers (|z| < TowerInner, up to the
-- screens' bottom) keeps the loading bay and the tube in view for the operator and the Load / Chamber
-- camera shots; nothing above the towers' screens is near the Chamber orbit (eye y 18.5).
M.Console = {
	DeskFront = -27, -- front face of the command desk (operator side)
	SlopeBottom = 3.6,
	SlopeTop = 4.8,
	SlopeFrom = -27,
	SlopeTo = -23,
	ButtonU = 0, -- along the slope from its middle
	LeverZ = 3.7,
	WingFrom = -34.0, -- wings: x range, |z| range, slope heights (inner edge low, outer edge high)
	WingTo = -21.6,
	WingInner = 6.6,
	WingOuter = 10.8,
	WingLow = 3.0,
	WingHigh = 4.4,
	TowerFront = -21.5, -- instrument towers: x range (front faces the operator), |z| range, height
	TowerBack = -19.6,
	TowerInner = 3.4,
	TowerOuter = 10.8,
	TowerTop = 10.6,
}
M.Console.SlopeAngle = math.atan((M.Console.SlopeTop - M.Console.SlopeBottom) / (M.Console.SlopeTo - M.Console.SlopeFrom))
-- Frame on the sloped desk surface at the ACTIVATE button (UpVector = surface normal, tilted to the operator).
M.Console.Slope = CFrame.new((M.Console.SlopeFrom + M.Console.SlopeTo) / 2, (M.Console.SlopeBottom + M.Console.SlopeTop) / 2, 0)
	* CFrame.Angles(0, 0, M.Console.SlopeAngle)
-- The ACTIVATE button (local): the console's colour waves start here.
M.Console.Button = M.Console.Slope.Position
-- Where LabService's InteractionAnchor (the ACTIVATE prompt, LabAccess reach) is moved to.
M.Anchor = Vector3.new(-25.3, 5.7, 0)

-- Camera shots of the cinematic (local; Eye, Focus, field of view).
M.Shots = {
	Activate = { Eye = Vector3.new(-33.5, 9.4, 7.5), Focus = Vector3.new(-23.5, 5.8, 0.4), Fov = 52 },
	Load = { Eye = Vector3.new(-33, 16.5, 6), Focus = Vector3.new(-10, 7.5, 0), Fov = 56 },
	Chamber = { Center = Vector3.new(0, 15.5, 0), Radius = 24, Height = 3, From = 158, To = 128, Fov = 60 },
	Reveal = { Eye = Vector3.new(-15.5, 17.2, 4.5), Focus = Vector3.new(0, 16.2, 0), Fov = 46 },
	Public = { Focus = Vector3.new(0, 18, 0) },
}

function M.World(v: Vector3): Vector3
	return M.Frame:PointToWorldSpace(v)
end
function M.WorldCFrame(cf: CFrame): CFrame
	return M.Frame * cf
end

-- An orthonormal frame at `position` whose LookVector is `look` (unit) and RightVector `right`.
function M.Basis(position: Vector3, look: Vector3, right: Vector3): CFrame
	local z = -look
	local y = z:Cross(right)
	return CFrame.fromMatrix(position, right, y.Unit, z)
end

-- Two-link inverse kinematics of the placer arm for a claw target (local). Returns the joint frames
-- (local): Turret (LookVector = horizontal reach direction), Upper (at the shoulder, LookVector along
-- the upper link), Fore (at the elbow, along the forearm) and Claw (at the wrist, level).
function M.ArmPose(target: Vector3): { Turret: CFrame, Upper: CFrame, Fore: CFrame, Claw: CFrame }
	local A = M.Arm
	local shoulder = A.Base + Vector3.new(0, A.ShoulderHeight, 0)
	local delta = target - shoulder
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dir = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(-1, 0, 0)
	local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
	local h, v = flat.Magnitude, delta.Y
	local reach = math.clamp(math.sqrt(h * h + v * v), math.abs(A.Upper - A.Fore) + 0.05, A.Upper + A.Fore - 0.05)
	local base = math.atan2(v, h)
	local cosA = math.clamp((A.Upper * A.Upper + reach * reach - A.Fore * A.Fore) / (2 * A.Upper * reach), -1, 1)
	local shoulderAngle = base + math.acos(cosA) -- elbow up
	local up = Vector3.new(0, 1, 0)
	local upperDir = dir * math.cos(shoulderAngle) + up * math.sin(shoulderAngle)
	local elbow = shoulder + upperDir * A.Upper
	local wrist = shoulder + (dir * math.cos(base) + up * math.sin(base)) * reach
	local foreDir = (wrist - elbow).Unit
	return {
		Turret = M.Basis(A.Base, dir, right),
		Upper = M.Basis(shoulder, upperDir, right),
		Fore = M.Basis(elbow, foreDir, right),
		Claw = M.Basis(wrist, dir, right),
	}
end

-- Colour reel of the cinematic: steps {At (seconds from the reel start), Name} that slow down like a slot
-- reel and land on `result` at the last step. A Normal result passes Shiny right before it lands (the near
-- miss), a mutation passes Normal. Pure presentation: the result itself is the server's roll.
function M.ReelSteps(result: string, duration: number, names: { string }): { { At: number, Name: string } }
	local intervals = {}
	local total, dt = 0, 0.065
	while total < duration * 0.82 do
		table.insert(intervals, dt)
		total += dt
		dt *= 1.13
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

-- Variant colours of the world (EconomyVisuals' Highlight palette: dogs in kennels and on the conveyor
-- use these), so the dog revealed in the tube matches the world. Normal = the machine's own teal.
M.WorldColors = {
	Normal = Color3.fromRGB(70, 255, 190),
	Shiny = Color3.fromRGB(220, 245, 255),
	Golden = Color3.fromRGB(255, 199, 54),
	Corrupted = Color3.fromRGB(184, 67, 233),
	Glitched = Color3.fromRGB(40, 239, 213),
	Void = Color3.fromRGB(88, 41, 165),
}
M.Teal = Color3.fromRGB(70, 255, 190)
M.Liquid = Color3.fromRGB(60, 235, 165)

return M
