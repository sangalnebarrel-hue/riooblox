-- THE DEAD YARD · props (ServerStorage.HalloweenBuild.Props, WP2). Build-time only.
-- Model `Props` under ctx.Root:
--   GhostKennel1..4 at Layout.Kennels (haunted dog houses facing the cauldron: shingled gable roofs, a ghost dog peeking
--   out of the doorway, chains, bowls), Cart1..3 at Layout.Carts (pumpkin wagon, ore mine cart on rails, bone cart), two
--   broken Dig Stations on the east field (excavation, derrick + bucket, snapped drill rig, rusted hopper), an abandoned
--   excavator digging up a grave by the south fence, a generator with a flickering bulb, the GIANT DOG SKELETON arching
--   over the path to the pit's east ramp with its voxel skull (YardKit.GiantSkull, green eyes, 1 PointLight) at the neck
--   end, the Hollow Lane lantern row on the lane's +Z edge (8 lights, HwLantern glass) with hanging chains, two
--   signposts, two pumpkin patches with a scarecrow-dog, bone piles.
-- Markers: GhostPath_7..12 (loop around the pit), BatRoost, CrowPerch, FogPoint. Layout.DigPoints / OrePoints stay clear.
local K = require(script.Parent.Kit)
local Y = require(script.Parent.YardKit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi
local S = Y.Solid

local WOOD = C(104, 78, 60)
local WOOD_D = C(70, 50, 40)
local RUST = C(130, 74, 48)
local IRON = C(52, 54, 62)
local YELLOW = C(214, 168, 40)

------------------------------------------------------------------------------------------------------------------
local KENNEL_NAMES = { "REX", "FIDO", "SPOT", "BONES" }
local SHINGLE = { C(70, 52, 80), C(58, 44, 66), C(82, 62, 94) }
local GHOST = C(150, 215, 255)
-- haunted dog house (door = -Z of the look frame): clapboard walls with seams and four corner posts, a steep shingled
-- gable (three stepped courses per slope; the +X slope sags and misses a shingle over the dark deck), barge boards, a
-- ridge with bone knobs, a bone-shaped name plate on the front gable, broken door trim, a spectral ghost glowing in the
-- dark doorway behind its Neon eyes, chain + collar, a tipped kibble bowl, a bowl of ectoplasm, a bone and a cobweb
local function kennel(parent, i, pos, faceDir, rng)
	local m = K.Model(parent, "GhostKennel" .. i)
	local O = K.Look(pos, pos + faceDir) -- front (door) = -Z local
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local wood = WOOD:Lerp(C(90, 84, 100), rng:NextNumber(0, .5))
	local trim = WOOD_D
	local seam = wood:Lerp(P.Ink, .45)
	local bone = P.Bone:Lerp(P.BoneDark, .3)
	K.Part(m, "KennelBase", V3(6.4, .5, 6.4), at(0, .25, 0), C(72, 68, 80), M.Cobblestone, S())
	K.Part(m, "KennelFloor", V3(5.6, .2, 5.6), at(0, .6, 0), C(40, 30, 34), M.WoodPlanks)
	K.Part(m, "KennelBack", V3(6, 4.6, .45), at(0, .5 + 2.3, 2.8), wood, M.WoodPlanks, S())
	K.Part(m, "PlankSeam", V3(5.0, .08, .06), at(0, 2.7, 3.05), seam, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "KennelSide", V3(.45, 4.6, 5.6), at(sx * 2.78, .5 + 2.3, 0), wood, M.WoodPlanks, S())
		K.Part(m, "KennelFront", V3(1.5, 4.6, .45), at(sx * 2.25, .5 + 2.3, -2.8), wood, M.WoodPlanks, S())
		for _, z in ipairs({ -2.85, 2.85 }) do
			K.Part(m, "CornerPost", V3(.55, 4.8, .55), at(sx * 2.85, .5 + 2.4, z), trim, M.Wood)
		end
		K.Part(m, "WallPlate", V3(.6, .4, 6.2), at(sx * 2.85, 5.3, 0), trim, M.Wood)
		K.Part(m, "PlankSeam", V3(.06, .08, 5.0), at(sx * 3.03, 2.7, 0), seam, M.SmoothPlastic) -- clapboard seam
	end
	K.Part(m, "KennelLintel", V3(3.1, 1.2, .45), at(0, .5 + 4, -2.8), wood, M.WoodPlanks, S())
	for _, sx in ipairs({ -1, 1 }) do -- chamfered (arched) top corners of the doorway
		K.Wedge(m, "DoorCorner", V3(.45, .9, .9), at(sx * 1.05, 3.45, -2.8) * ANG(0, sx * PI / 2, 0) * ANG(0, 0, PI), wood, M.WoodPlanks)
	end
	-- dark doorway: the interior, a spectral ghost glowing behind the Neon eyes, a faint glow on the floor
	K.Part(m, "KennelDark", V3(5, 4.2, .2), at(0, .5 + 2.2, 2.45), C(12, 8, 16), M.SmoothPlastic)
	K.Part(m, "KennelDarkSide", V3(.2, 4.2, 4.8), at(-2.45, .5 + 2.2, 0), C(16, 12, 20), M.SmoothPlastic)
	K.Part(m, "KennelDarkSide", V3(.2, 4.2, 4.8), at(2.45, .5 + 2.2, 0), C(16, 12, 20), M.SmoothPlastic)
	local eye = i % 2 == 0 and Y.GLOW.Purple or Y.GLOW.Green
	-- the ghost dog peeking out of the doorway: wispy body + tail, floppy ears, Neon eyes, an "O" mouth
	K.Ellipsoid(m, "GhostWisp", V3(2.2, 2.6, 1.0), at(0, 2.3, -1.45), GHOST, M.Neon, { Transparency = .5 })
	K.Ellipsoid(m, "GhostWisp", V3(1.3, 1.1, .7), at(.6, 1.1, -1.2) * ANG(0, 0, .6), GHOST, M.Neon, { Transparency = .62 })
	for _, sx in ipairs({ -1, 1 }) do
		K.Ellipsoid(m, "GhostEar", V3(.5, 1.1, .3), at(sx * .9, 3.25, -1.45) * ANG(0, 0, sx * .7), GHOST, M.Neon, { Transparency = .45 })
		K.Ball(m, "GhostEye", .38, at(sx * .42, 2.75, -1.98), eye, M.Neon)
	end
	K.Ball(m, "GhostMouth", .36, at(0, 2.2, -1.95), C(30, 40, 70), M.SmoothPlastic)
	K.Part(m, "SpectralGlow", V3(4.4, .04, 4.2), at(0, .72, .4), eye:Lerp(GHOST, .5), M.Neon, { Transparency = .78 })
	-- steep shingled gable roof: three stepped courses per slope, the +X slope sagging with a missing shingle
	local EAVE_X, EAVE_Y, RIDGE_Y = 3.75, 4.95, 7.6
	local rise = RIDGE_Y - EAVE_Y
	local slope = math.sqrt(EAVE_X * EAVE_X + rise * rise)
	local a = math.atan2(rise, EAVE_X)
	for _, sx in ipairs({ -1, 1 }) do
		local u = V3(-sx * math.cos(a), math.sin(a), 0) -- up the slope
		local n = V3(sx * math.sin(a), math.cos(a), 0) -- outward normal
		local eave = V3(sx * EAVE_X, EAVE_Y, 0)
		if sx > 0 then
			K.Part(m, "RoofDeck", V3(slope, .12, 6.9), O * CFrame.fromMatrix(eave + u * slope / 2 + n * .02, u, n), C(28, 20, 30), M.WoodPlanks)
		end
		for r = 0, 2 do
			local c = eave + u * ((r + .5) * slope / 3) + n * (.18 + r * .07)
			local col = SHINGLE[(r + (sx > 0 and 1 or 0)) % 3 + 1]
			local cf = O * CFrame.fromMatrix(c, u, n)
			if sx > 0 and r == 1 then
				local sag = cf * CF(0, -.12, 0) * ANG(0, 0, .05)
				K.Part(m, "GhostKennelTop", V3(slope / 3 + .25, .3, 3.9), sag * CF(0, 0, -1.65), col, M.WoodPlanks)
				K.Part(m, "GhostKennelTop", V3(slope / 3 + .25, .3, 2.0), sag * CF(0, 0, 2.6), col, M.WoodPlanks)
			else
				K.Part(m, "GhostKennelTop", V3(slope / 3 + .25, .3, 7.2), cf, col, M.WoodPlanks, r == 0 and S() or nil)
			end
		end
	end
	for _, gz in ipairs({ -2.83, 2.83 }) do
		Y.GableTri(m, "KennelGable", at(0, 5.1, gz) * ANG(0, PI / 2, 0), 6.6, 2.55, .5, wood, M.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			K.Bar(m, "BargeBoard", at(sx * 3.95, 4.82, gz * 1.3).Position, at(0, 7.9, gz * 1.3).Position, .22, .45, trim, M.Wood)
		end
	end
	local cap = K.Part(m, "GhostKennelRidge", V3(.55, .35, 7.5), at(0, 7.95, 0), trim, M.Wood)
	K.Attach(cap, "CrowPerch", CF(0, .3, 2.6))
	for _, z in ipairs({ -3.75, 3.75 }) do
		K.Ball(m, "RidgeKnob", .55, at(0, 8.05, z), bone, M.SmoothPlastic)
	end
	K.Part(m, "FallenShingle", V3(1.4, .2, 1.9), at(3.9, .32, 1.6) * ANG(0, .5, .12), SHINGLE[2], M.WoodPlanks)
	-- bone-shaped name plate on the front gable
	local plate = K.Part(m, "NamePlate", V3(2.3, .6, .16), at(0, 5.95, -3.15), bone, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			K.Ball(m, "NamePlateKnob", .5, at(sx * 1.18, 5.95 + sy * .2, -3.15), bone, M.SmoothPlastic)
		end
	end
	local g = K.Sign(plate, N.Front, KENNEL_NAMES[i], C(64, 34, 28), { PixelsPerStud = 30, Stroke = false, H = .8 })
	g:SetAttribute("NoTranslate", true)
	-- door trim along the jambs, chamfers and head (the right chamfer piece hangs loose) + claw scratches
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "DoorTrim", V3(.28, 2.45, .2), at(sx * 1.64, 1.9, -3.12), trim, M.Wood)
		local c0, c1 = at(sx * 1.64, 3.08, -3.12).Position, at(sx * .6, 4.08, -3.12).Position
		if sx > 0 then
			c0 = at(1.95, 2.55, -3.2).Position -- pulled off its nail
		end
		K.Bar(m, "DoorTrim", c0, c1, .28, .26, trim, M.Wood)
	end
	K.Part(m, "DoorTrim", V3(1.3, .26, .2), at(0, 4.08, -3.12), trim, M.Wood)
	for k = 1, 3 do
		K.Part(m, "Scratch", V3(.06, 1.4, .08), at(-2.4 + k * .3, 2.2, -3.07) * ANG(0, 0, .3), C(40, 30, 30), M.SmoothPlastic)
	end
	-- chain from a stake to a collar in the doorway, tipped kibble bowl, a bowl of ectoplasm, a bone
	local stake = at(-1.2, 0, -6.2)
	K.CylY(m, "ChainStake", 1.2, .35, stake * CF(0, .6, 0), IRON, M.CorrodedMetal)
	K.Chain(m, (stake * CF(0, 1.1, 0)).Position, (at(-.4, .9, -2.4)).Position, .4, 7)
	K.CylY(m, "Collar", .14, .95, at(-.3, .77, -1.95), C(170, 40, 50), M.Fabric)
	K.CylY(m, "Collar", .16, .62, at(-.3, .77, -1.95), C(40, 30, 34), M.WoodPlanks)
	K.CylZ(m, "CollarTag", .06, .32, at(-.3, .62, -2.45), P.Gold, M.Metal)
	local bowl = at(1.9, .45, -4.3) * ANG(0, 0, .5)
	K.CylY(m, "DogBowl", .45, 1.5, bowl, C(150, 40, 50), M.SmoothPlastic)
	K.CylY(m, "DogBowlRim", .12, 1.64, bowl * CF(0, .2, 0), C(120, 30, 40), M.SmoothPlastic)
	K.Ball(m, "Kibble", .3, at(.9, .32, -4.1), P.Pumpkin, M.SmoothPlastic)
	K.Ball(m, "Kibble", .26, at(.6, .3, -4.6), C(150, 80, 200), M.SmoothPlastic)
	K.CylY(m, "EctoBowl", .5, 1.4, at(-2.5, .45, -4.1), C(70, 80, 110), M.Metal)
	K.CylY(m, "Ectoplasm", .06, 1.12, at(-2.5, .7, -4.1), Y.GLOW.Green, M.Neon)
	K.Bone(m, at(1.2, .35, -5.2) * ANG(0, .6, 0), 1.3, P.Bone)
	Y.Cobweb(m, at(-1.45, 3.9, -2.95), 1.1)
	return m
end

------------------------------------------------------------------------------------------------------------------
local function wheel(m, cf, d, w, color)
	K.CylX(m, "Wheel", w, d, cf, color, M.Wood)
	K.CylX(m, "WheelRim", w + .05, d * .82, cf, color:Lerp(P.Ink, .4), M.Wood)
	K.CylX(m, "WheelHub", w + .3, d * .28, cf, IRON, M.CorrodedMetal)
end

local function pumpkinWagon(parent, pos, rng)
	local m = K.Model(parent, "Cart1")
	local O = CF(pos) * ANG(0, .35, 0)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	K.Part(m, "WagonBed", V3(4.2, .4, 6.4), at(0, 1.9, 0), WOOD, M.WoodPlanks, S())
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "WagonSide", V3(.25, 1.3, 6.4), at(sx * 2.1, 2.7, 0), WOOD_D, M.WoodPlanks)
		for _, z in ipairs({ -2.1, 2.1 }) do
			wheel(m, at(sx * 2.45, 1.25, z), 2.5, .35, WOOD_D)
		end
	end
	K.Part(m, "WagonFront", V3(4.2, 1.3, .25), at(0, 2.7, -3.1), WOOD_D, M.WoodPlanks)
	K.Part(m, "WagonBack", V3(4.2, .8, .25), at(0, 3.2, 3.6) * ANG(-.9, 0, 0), WOOD_D, M.WoodPlanks)
	K.Rod(m, "WagonShaft", (at(-1, 1.8, -3.2)).Position, (at(-.8, .25, -7.4)).Position, .22, WOOD_D, M.Wood)
	K.Rod(m, "WagonShaft", (at(1, 1.8, -3.2)).Position, (at(.8, .25, -7.4)).Position, .22, WOOD_D, M.Wood)
	K.Part(m, "Axle", V3(4.9, .25, .25), at(0, 1.25, -2.1), IRON, M.CorrodedMetal)
	K.Part(m, "Axle", V3(4.9, .25, .25), at(0, 1.25, 2.1), IRON, M.CorrodedMetal)
	Y.Pumpkin(m, at(-.9, 2.1, -1.6) * ANG(0, .3, 0), 2, { Light = false })
	Y.Pumpkin(m, at(1, 2.1, -.6) * ANG(0, -.5, 0), 1.7, { Face = false })
	Y.Pumpkin(m, at(-.6, 2.1, 1.5) * ANG(0, 2.6, 0), 1.9, { Face = false, Lobes = 4 })
	Y.Pumpkin(m, at(.4, 3.1, .4) * ANG(.2, 0, .3), 1.3, { Glow = Y.GLOW.Green })
	Y.Pumpkin(m, at(2.6, 0, 3.8) * ANG(0, .8, .25), 1.4, { Face = false, Lobes = 4 })
	local pole = K.Part(m, "LanternPole", V3(.2, 3, .2), at(-1.9, 3.8, -3), WOOD_D, M.Wood)
	K.Attach(pole, "CrowPerch", CF(0, 1.6, 0))
	K.Attach(pole, "BatRoost", CF(0, -.5, 0))
	return m
end

local function mineCart(parent, pos, rng)
	local m = K.Model(parent, "Cart2")
	local O = CF(pos)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	for _, x in ipairs({ -.75, .75 }) do
		K.Part(m, "Rail", V3(.22, .25, 13), at(x, .38, 0), C(100, 92, 90), M.CorrodedMetal)
	end
	for k = -2, 2 do
		K.Part(m, "Sleeper", V3(2.6, .22, .6), at(0, .22, k * 2.8 + rng:NextNumber(-.2, .2)) * ANG(0, rng:NextNumber(-.08, .08), 0), WOOD_D, M.WoodPlanks)
	end
	local c = at(0, 0, -1)
	K.Part(m, "CartFrame", V3(2.4, .4, 3.4), c * CF(0, 1.1, 0), IRON, M.CorrodedMetal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1.1, 1.1 }) do
			K.CylX(m, "CartWheel", .3, 1.1, c * CF(sx * .75, .75, z), IRON, M.CorrodedMetal)
		end
	end
	K.Part(m, "CartTub", V3(2.8, .3, 3.8), c * CF(0, 1.45, 0), RUST, M.CorrodedMetal, S())
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "CartTubSide", V3(.2, 1.6, 3.8), c * CF(sx * 1.5, 2.3, 0) * ANG(0, 0, sx * .18), RUST:Lerp(P.Ink, .2), M.CorrodedMetal)
		K.Part(m, "CartTubEnd", V3(3, 1.6, .2), c * CF(0, 2.3, sx * 1.95) * ANG(-sx * .18, 0, 0), RUST:Lerp(P.Ink, .1), M.CorrodedMetal)
	end
	K.Part(m, "OreHeap", V3(2.4, .7, 3.2), c * CF(0, 2.6, 0), C(60, 54, 70), M.Basalt)
	for k = 1, 5 do
		K.Wedge(m, "OreCrystal", V3(.5, rng:NextNumber(.9, 1.5), .5), c * CF(rng:NextNumber(-.8, .8), 3.2, rng:NextNumber(-1.2, 1.2)) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, PI), rng:NextNumber(-.3, .3)),
			k % 2 == 0 and Y.GLOW.Purple or C(150, 120, 255), M.Neon)
	end
	K.Part(m, "BufferStop", V3(2.4, 1.2, .5), at(0, .9, 6.6), WOOD_D, M.WoodPlanks, S())
	return m
end

local function boneCart(parent, pos, rng)
	local m = K.Model(parent, "Cart3")
	local O = CF(pos) * ANG(0, -.4, 0) * CF(0, 0, 0)
	local tilt = O * CF(0, 0, 0) * ANG(-.16, 0, 0)
	local function at(x, y, z)
		return tilt * CF(x, y, z)
	end
	K.Part(m, "CartBed", V3(3.6, .35, 4.8), at(0, 1.7, 0), WOOD_D, M.WoodPlanks, S())
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "CartSide", V3(.22, 1, 4.8), at(sx * 1.8, 2.35, 0), WOOD, M.WoodPlanks)
		wheel(m, O * CF(sx * 2.15, 1.45, .6), 2.9, .3, WOOD_D)
		K.Rod(m, "CartHandle", (at(sx * 1.2, 1.8, -2.4)).Position, (at(sx * 1.1, .7, -5.4)).Position, .2, WOOD, M.Wood)
	end
	K.Part(m, "CartFront", V3(3.6, 1, .22), at(0, 2.35, -2.4), WOOD, M.WoodPlanks)
	for k = 1, 6 do
		K.Bone(m, at(rng:NextNumber(-1.1, 1.1), 2.15 + k * .12, rng:NextNumber(-1.6, 1.6)) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, PI), rng:NextNumber(-.2, .2)), rng:NextNumber(1.2, 1.8),
			P.Bone:Lerp(P.BoneDark, rng:NextNumber(0, .6)))
	end
	Y.Skull(m, at(-.5, 3.1, .6) * ANG(-.2, .5, 0), 1, nil)
	Y.Skull(m, at(.7, 2.9, -1) * ANG(0, -.4, .2), .85, Y.GLOW.Green)
	return m
end

------------------------------------------------------------------------------------------------------------------
local function digStation(parent, idx, pos, yaw, rng)
	local m = K.Model(parent, "BrokenDigStation" .. idx)
	local O = CF(pos) * ANG(0, yaw, 0)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- excavation with timber borders and a faint glow down the hole
	K.Part(m, "DarkExcavation", V3(7, .08, 7), at(0, .05, 0), C(34, 26, 30), M.Mud)
	K.CylY(m, "ExcavationDeep", .06, 3.4, at(.4, .1, -.3), C(60, 30, 90), M.Neon)
	for _, e in ipairs({ { 0, -3.7, 7.8, .5 }, { 0, 3.7, 7.8, .5 }, { -3.7, 0, .5, 7 }, { 3.7, 0, .5, 7 } }) do
		K.Part(m, "PitTimber", V3(e[3], .4, e[4]), at(e[1], .2, e[2]) * ANG(0, 0, rng:NextNumber(-.03, .03)), WOOD_D, M.WoodPlanks, S())
	end
	-- A-frame derrick with a pulley, rope and a bucket
	for _, sz in ipairs({ -1, 1 }) do
		K.Rod(m, "DerrickLeg", (at(-3.2, .3, sz * 3.2)).Position, (at(-.4, 7.6, sz * .9)).Position, .45, WOOD, M.Wood, S())
		K.Rod(m, "DerrickLeg", (at(3.2, .3, sz * 3.2)).Position, (at(.4, 7.6, sz * .9)).Position, .45, WOOD, M.Wood)
	end
	local beam = K.Part(m, "DerrickBeam", V3(1.4, .5, 2.6), at(0, 7.7, 0), WOOD_D, M.Wood)
	K.Attach(beam, "BatRoost", CF(0, -.4, 0))
	K.Attach(beam, "CrowPerch", CF(0, .35, 1))
	K.CylZ(m, "Pulley", .3, 1.1, at(0, 7.1, 0), IRON, M.CorrodedMetal)
	K.Part(m, "Rope", V3(.09, 4.4, .09), at(.5, 4.85, 0), C(150, 126, 90), M.Fabric)
	K.CylY(m, "Bucket", 1, 1.1, at(.5, 2.15, 0) * ANG(0, 0, .1), RUST, M.CorrodedMetal)
	K.Part(m, "BucketHandle", V3(1.2, .08, .08), at(.5, 2.8, 0), IRON, M.CorrodedMetal)
	-- snapped drill rig on a plate beside the pit
	local d = at(5.4, 0, 1.4)
	K.Part(m, "RigPlate", V3(3.4, .3, 3.6), d * CF(0, .15, 0), C(80, 82, 90), M.DiamondPlate, S())
	K.Part(m, "RigMotor", V3(2.2, 1.8, 2), d * CF(0, 1.2, .5), YELLOW:Lerp(RUST, .45), M.CorrodedMetal, S())
	for k = 0, 2 do
		K.Part(m, "RigStripe", V3(.35, 1.9, .06), d * CF(-.7 + k * .7, 1.2, -.53) * ANG(0, 0, .5), C(30, 28, 32), M.SmoothPlastic)
	end
	K.Part(m, "RigMast", V3(.6, 6.4, .6), d * CF(0, 3.5, -.6) * ANG(-.22, 0, .1), IRON, M.CorrodedMetal)
	K.CylY(m, "DrillShaft", 3.6, .5, d * CF(-1.6, 1.3, -1.6) * ANG(.3, 0, .85), C(150, 150, 160), M.Metal)
	for k, dd in ipairs({ .9, .65, .4 }) do
		K.CylY(m, "DrillBit", .45, dd, d * CF(-2.9 - k * .25, .25 + k * .1, -2.2 - k * .1) * ANG(.3, 0, .85), C(120, 120, 130), M.Metal)
	end
	-- rusted hopper on legs with a chute
	local h = at(-5.4, 0, -1.2)
	for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		K.Part(m, "HopperLeg", V3(.3, 4, .3), h * CF(o[1] * 1.1, 2, o[2] * 1.1), IRON, M.CorrodedMetal, S())
	end
	K.Part(m, "HopperBin", V3(3.2, 1.6, 3.2), h * CF(0, 5.6, 0), RUST, M.CorrodedMetal)
	K.Part(m, "HopperRim", V3(3.5, .25, 3.5), h * CF(0, 6.45, 0), RUST:Lerp(P.Ink, .3), M.CorrodedMetal)
	for k, dd in ipairs({ 2.6, 1.7 }) do
		K.CylY(m, "Hopper", .8, dd, h * CF(0, 4.85 - k * .7, 0), RUST:Lerp(P.Ink, k * .12), M.CorrodedMetal)
	end
	K.Part(m, "HopperChute", V3(.9, .2, 3), h * CF(0, 2.6, 1.6) * ANG(.45, 0, 0), RUST, M.CorrodedMetal)
	-- CLOSED sign
	local sp = at(-2.6, 0, -4.6)
	K.Part(m, "SignPost", V3(.25, 3.2, .25), sp * CF(0, 1.6, 0), WOOD_D, M.Wood)
	local sign = K.Part(m, "ClosedSign", V3(2.6, 1, .14), sp * CF(0, 2.9, -.15) * ANG(0, 0, .12), C(170, 40, 40), M.WoodPlanks)
	K.Sign(sign, N.Front, "CLOSED", P.Cream, { PixelsPerStud = 24, H = .7 })
	return m
end

-- abandoned excavator digging up a dog grave by the south fence: tracked undercarriage (frames, belts with grouser plates,
-- sprocket / idler / road-wheel hubs, caked mud), slewed upper body (deck, engine hood with bevel + grille, exhaust
-- stack, hazard-striped counterweight, cab with posts, glass, a smashed pane, a seat and a work lamp dangling on its
-- wire), banana boom + stick with hydraulic rams (barrel + chrome rod) and pins, and a toothed bucket curled up full of
-- grave dirt, bones and a skull over the open grave. Paint pushed toward rust.
local function excavator(parent, pos, yaw, slew)
	local m = K.Model(parent, "Excavator")
	local O = CF(pos) * ANG(0, yaw, 0)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local paint = YELLOW:Lerp(RUST, .66):Lerp(P.Ink, .14)
	local paintD = paint:Lerp(P.Ink, .3)
	local hazard = YELLOW:Lerp(RUST, .3)
	local STEEL, BELT, CHROME, MUD = C(44, 44, 50), C(34, 32, 36), C(168, 170, 178), C(72, 56, 46)
	-- tracked undercarriage
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * 1.75
		K.Part(m, "TrackFrame", V3(.9, .8, 4.6), at(x, .85, 0), STEEL, M.CorrodedMetal, S())
		for _, y in ipairs({ .13, 1.47 }) do
			K.Part(m, "TrackBelt", V3(1.3, .26, 5.3), at(x, y, 0), BELT, M.DiamondPlate)
		end
		for _, z in ipairs({ -2.65, 2.65 }) do
			K.CylX(m, "TrackEnd", 1.3, 1.6, at(x, .8, z), BELT, M.DiamondPlate)
			K.CylX(m, z < 0 and "Idler" or "Sprocket", 1.36, .9, at(x, .8, z), z < 0 and STEEL or RUST, M.CorrodedMetal)
		end
		for k = -2, 2 do
			K.Part(m, "Grouser", V3(1.36, .12, .22), at(x, 1.65, k * 1.05), C(56, 54, 58), M.CorrodedMetal)
		end
		K.Ellipsoid(m, "TrackMud", V3(1.5, .8, 2.4), at(x, .45, sx * 1.1), MUD, M.Mud)
	end
	K.CylY(m, "SlewRing", .5, 3.2, at(0, 1.85, 0), STEEL, M.CorrodedMetal)
	-- slewed upper body
	local B = O * ANG(0, slew, 0)
	local function bt(x, y, z)
		return B * CF(x, y, z)
	end
	K.Part(m, "Deck", V3(3.8, .35, 5.0), bt(0, 2.27, .3), paintD, M.CorrodedMetal, S())
	K.Part(m, "EngineHood", V3(3.6, 1.4, 2.2), bt(.1, 3.15, 1.4), paint, M.CorrodedMetal, S())
	K.Wedge(m, "HoodBevel", V3(3.6, .45, .7), bt(.1, 4.07, .65), paint, M.CorrodedMetal)
	for k = 0, 2 do
		K.Part(m, "HoodGrille", V3(.06, .14, 1.3), bt(1.92, 2.8 + k * .35, 1.45), C(26, 24, 28), M.SmoothPlastic)
	end
	K.Part(m, "RustPatch", V3(.05, .8, .7), bt(1.93, 3.3, 2.2) * ANG(.2, 0, 0), RUST, M.CorrodedMetal)
	K.Part(m, "RustPatch", V3(1.1, .05, .8), bt(-.9, 3.88, 1.9) * ANG(0, .3, 0), RUST:Lerp(P.Ink, .2), M.CorrodedMetal)
	K.Part(m, "RustPatch", V3(.05, .6, 1.0), bt(-1.86, 2.85, -.6), RUST:Lerp(P.Ink, .1), M.CorrodedMetal)
	K.Ellipsoid(m, "DeckMud", V3(1.6, .14, 1.2), bt(.9, 2.47, -1.5) * ANG(0, .5, 0), MUD, M.Mud)
	K.Part(m, "Counterweight", V3(3.8, 1.25, .9), bt(0, 2.9, 2.95), hazard, M.CorrodedMetal, S())
	for k = 0, 3 do
		K.Part(m, "HazardStripe", V3(.3, 1.0, .06), bt(-1.3 + k * .86, 2.9, 3.42) * ANG(0, 0, .6), C(24, 22, 26), M.SmoothPlastic)
	end
	K.CylY(m, "ExhaustStack", 1.5, .32, bt(1.3, 4.6, 2.0), C(48, 46, 50), M.CorrodedMetal)
	K.Part(m, "ExhaustCap", V3(.42, .1, .5), bt(1.3, 5.4, 2.05) * ANG(.5, 0, 0), C(48, 46, 50), M.CorrodedMetal)
	-- cab: lower panel, posts, roof, glass (right pane smashed), seat, a work lamp dangling on its wire
	local cx, cz = -.95, -1.0
	K.Part(m, "CabPanel", V3(1.8, 1.0, 2.1), bt(cx, 2.95, cz), paint, M.CorrodedMetal, S())
	for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		K.Part(m, "CabPost", V3(.16, 1.55, .16), bt(cx + o[1] * .82, 4.22, cz + o[2] * .97), paintD, M.CorrodedMetal)
	end
	K.Part(m, "CabRoof", V3(2.0, .22, 2.3), bt(cx, 5.1, cz), paint, M.CorrodedMetal)
	local glass = C(56, 74, 86)
	K.Part(m, "CabWindow", V3(1.5, 1.3, .06), bt(cx, 4.2, cz - .99), glass, M.Glass, { Transparency = .3, Reflectance = .25 })
	K.Part(m, "CabWindow", V3(.06, 1.3, 1.8), bt(cx - .84, 4.2, cz), glass, M.Glass, { Transparency = .3, Reflectance = .25 })
	K.Part(m, "CabWindowBroken", V3(.06, .6, .9), bt(cx + .84, 3.8, cz + .35) * ANG(.25, 0, 0), glass:Lerp(P.Ink, .3), M.Glass, { Transparency = .2, Reflectance = .3 })
	K.Part(m, "CabBack", V3(1.6, 1.4, .1), bt(cx, 4.2, cz + .99), paintD, M.CorrodedMetal)
	K.Part(m, "CabSeat", V3(.8, .3, .8), bt(cx, 3.6, cz + .2), C(40, 34, 36), M.Fabric)
	K.Part(m, "CabSeat", V3(.8, .9, .2), bt(cx, 4.05, cz + .55) * ANG(-.15, 0, 0), C(40, 34, 36), M.Fabric)
	K.Part(m, "LampWire", V3(.05, .45, .05), bt(cx + .6, 4.82, cz - 1.2), C(24, 24, 28), M.Fabric)
	local lamp = K.Part(m, "WorkLamp", V3(.45, .35, .32), bt(cx + .6, 4.5, cz - 1.25) * ANG(.7, 0, .3), C(36, 36, 40), M.CorrodedMetal)
	K.Part(m, "WorkLampLens", V3(.34, .25, .05), lamp.CFrame * CF(0, 0, -.17), C(255, 214, 120), M.Neon, { Transparency = .35 })
	-- banana boom + stick with hydraulic rams and pins
	local A, Kn, E, T = bt(.75, 2.6, -1.6), bt(.75, 6.9, -3.6), bt(.75, 8.0, -5.7), bt(.75, 4.6, -7.9)
	local ext = E.Position + (E.Position - T.Position).Unit * 1.0
	K.Bar(m, "Boom", A.Position, Kn.Position, .82, 1.0, paint, M.CorrodedMetal)
	K.Bar(m, "Boom", Kn.Position, E.Position, .78, .92, paint, M.CorrodedMetal)
	K.Part(m, "BoomKnee", V3(.84, 1.15, 1.15), Kn, paint, M.CorrodedMetal)
	K.Bar(m, "Stick", ext, T.Position, .6, .78, paintD, M.CorrodedMetal)
	for _, p in ipairs({ A, E, T }) do
		K.CylX(m, "Pin", 1.05, .42, p, CHROME:Lerp(RUST, .5), M.CorrodedMetal)
	end
	local function ram(name, a, b, d)
		K.Rod(m, name, a, a:Lerp(b, .58), d, paintD, M.CorrodedMetal)
		K.Rod(m, name .. "Rod", a:Lerp(b, .5), b, d * .5, CHROME, M.Metal)
	end
	for _, o in ipairs({ -.62, .62 }) do
		ram("BoomCylinder", bt(.75 + o, 2.4, -1.0).Position, bt(.75 + o, 5.4, -3.1).Position, .42)
	end
	ram("StickCylinder", bt(.75, 7.55, -3.3).Position, ext + V3(0, .1, 0), .38)
	ram("BucketCylinder", bt(.75, 7.6, -6.2).Position, bt(.75, 5.2, -8.4).Position, .34)
	local piv = K.Part(m, "BoomPivot", V3(.3, .3, .3), E, paint, nil, { Transparency = 1 })
	K.Attach(piv, "BatRoost", CF(0, -.5, 0))
	K.Attach(piv, "CrowPerch", CF(0, .9, 0))
	-- toothed bucket curled up, heaped with grave dirt, bones and a skull
	local Bk = bt(.75, 3.55, -8.55) * ANG(-.25, 0, 0)
	K.Part(m, "BucketBack", V3(1.9, 1.5, .18), Bk * CF(0, .05, .78), paintD, M.CorrodedMetal)
	K.Part(m, "BucketFloor", V3(1.9, .18, 1.6), Bk * CF(0, -.7, 0), paintD, M.CorrodedMetal)
	K.Part(m, "BucketLip", V3(1.95, .9, .18), Bk * CF(0, -.3, -.8) * ANG(-.3, 0, 0), C(60, 58, 60), M.CorrodedMetal)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "BucketSide", V3(.16, 1.45, 1.7), Bk * CF(sx * 1.0, -.05, 0), paint, M.CorrodedMetal)
	end
	for k = -2, 2 do
		K.Wedge(m, "BucketTooth", V3(.22, .42, .32), Bk * CF(k * .4, .3, -1.0), C(150, 150, 156), M.Metal)
	end
	K.Ellipsoid(m, "BucketDirt", V3(1.9, 1.0, 1.7), Bk * CF(0, .55, 0), MUD, M.Mud)
	K.Bone(m, Bk * CF(-.2, 1.0, .1) * ANG(.3, .7, .5), 1.6, P.Bone:Lerp(P.BoneDark, .3))
	K.Bone(m, Bk * CF(.45, .9, -.35) * ANG(-.2, -.4, -.3), 1.2, P.Bone)
	Y.Skull(m, Bk * CF(.45, 1.05, .4) * ANG(-.3, 2.6, 0), .75, nil)
	-- the open grave below: dark hole, heaped earth with clods, a toppled wooden cross
	local g = bt(.75, 0, -9.2)
	K.Ellipsoid(m, "OpenGrave", V3(2.4, .1, 3.4), g * CF(0, .06, 0), C(22, 16, 22), M.Mud)
	K.Ellipsoid(m, "DugEarth", V3(3.2, 1.3, 2.8), g * CF(2.4, .1, .3) * ANG(0, .4, 0), MUD, M.Mud)
	K.Ball(m, "DirtClod", .7, g * CF(1.4, .25, -1.5), MUD:Lerp(P.Ink, .15), M.Mud)
	K.Ball(m, "DirtClod", .5, g * CF(-1.5, .2, .9), MUD:Lerp(P.Ink, .1), M.Mud)
	K.Part(m, "ToppledCross", V3(.3, .25, 2.2), g * CF(-1.8, .35, -.4) * ANG(0, .5, .1), P.WoodOld, M.WoodPlanks)
	K.Part(m, "ToppledCross", V3(1.3, .25, .28), g * CF(-1.8, .4, -.4) * ANG(0, .5, .1) * CF(0, .02, -.45), P.WoodOld, M.WoodPlanks)
	return m
end

local function generator(parent, pos, yaw)
	local m = K.Model(parent, "Generator")
	local O = CF(pos) * ANG(0, yaw, 0)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	K.Part(m, "GenSkid", V3(3.6, .3, 2.2), at(0, .15, 0), IRON, M.CorrodedMetal)
	K.Part(m, "GenBody", V3(3.2, 1.8, 1.9), at(0, 1.2, 0), C(70, 110, 74), M.CorrodedMetal, S())
	K.Part(m, "GenGrille", V3(.06, 1.2, 1.4), at(-1.62, 1.2, 0), C(36, 38, 40), M.DiamondPlate)
	K.CylY(m, "GenExhaust", 1.6, .4, at(1, 2.8, .4), C(60, 60, 64), M.CorrodedMetal)
	K.CylY(m, "GenTank", .5, 1.2, at(.4, 2.3, -.3), C(150, 40, 40), M.CorrodedMetal)
	K.Part(m, "FuelCan", V3(.7, 1, .4), at(-2.3, .5, .6) * ANG(0, .4, 0), C(170, 40, 40), M.Metal)
	-- a pole with a flickering bulb on a cable
	local pole = at(2.6, 0, -1.2)
	K.Part(m, "BulbPole", V3(.3, 6.2, .3), pole * CF(0, 3.1, 0), WOOD_D, M.Wood, S())
	K.Part(m, "BulbArm", V3(1.6, .2, .2), pole * CF(-.7, 6, 0), WOOD_D, M.Wood)
	K.Part(m, "BulbWire", V3(.06, .9, .06), pole * CF(-1.3, 5.5, 0), C(30, 30, 34), M.Fabric)
	local bulb = K.Ball(m, "BulbGlass", .55, pole * CF(-1.3, 4.95, 0), C(255, 200, 120), M.Neon, { Attrs = { HwLantern = "Orange" } })
	K.Light(bulb, C(255, 170, 90), 12, .8)
	K.Rod(m, "GenCable", (at(1.6, 1.4, 0)).Position, (pole * CF(0, 1.2, 0)).Position, .12, C(30, 30, 34), M.Fabric)
	K.Attach(K.Part(m, "PoleTop", V3(.2, .2, .2), pole * CF(0, 6.3, 0), WOOD_D, nil, { Transparency = 1 }), "CrowPerch")
	return m
end

------------------------------------------------------------------------------------------------------------------
-- GIANT DOG SKELETON lying belly-down across the path to the pit's east ramp: a spine of voxel vertebrae (body, disc,
-- spinous process leaning toward the tail with a knob, transverse bar) arching over the walk, 7 rib pairs on a barrel
-- curve that taper from the spine and get a knuckle at every joint (three bone tones), diving into earth berms (one rib
-- snapped, its end in the dirt), a neck curling down to the skull, a pelvis with ilium wings, hip sockets and a femur, a
-- tail sinking into the ground, a scapula and foreleg on the south side, two lanterns hanging from the spine (the purple
-- one lit), a candle cluster, cobwebs and moss. The walkway between the rib feet stays ~7 wide.
local BONE3 = { C(236, 226, 200), C(216, 202, 170), C(192, 176, 142) } -- bone light / mid / dark
local function ribcage(parent, x0, x1, z, neckTo, rng)
	local m = K.Model(parent, "GiantDogRibcage")
	local function spine(t) -- t 0..1 from the pit end to the hips
		local x = x0 + (x1 - x0) * t
		local y = .2 + 7.4 + math.sin(t * PI) * 2.2 - t * 2.2
		return V3(x, y, z)
	end
	local function dirAt(t)
		return (spine(math.min(1, t + .01)) - spine(math.max(0, t - .01))).Unit
	end
	-- vertebrae
	local NV = 10
	local half = (x1 - x0) / NV * .36
	local prevEnd
	for i = 1, NV do
		local t = (i - .5) / NV
		local p, d = spine(t), dirAt(t)
		local tone = BONE3[i % 2 + 1]
		K.Rod(m, "VertebraBody", p - d * half, p + d * half, 1.3, tone, M.SmoothPlastic)
		if prevEnd then
			K.Rod(m, "SpineDisc", prevEnd, p - d * half, .95, BONE3[3]:Lerp(C(120, 100, 84), .3), M.SmoothPlastic)
		end
		prevEnd = p + d * half
		local F = K.Look(p, p - d) -- -Z toward the head
		local h = 2.1 - i * .11
		local proc = F * CF(0, .45, 0) * ANG(.34, 0, 0)
		K.Part(m, "SpinousProcess", V3(.36, h, .72), proc * CF(0, h / 2, 0), tone, M.SmoothPlastic)
		if i <= 7 then
			K.Ball(m, "ProcessKnob", .52, proc * CF(0, h, 0), BONE3[1], M.SmoothPlastic)
		end
		K.Part(m, "TransverseProcess", V3(2.3 - i * .05, .32, .5), F * CF(0, -.1, 0), BONE3[2], M.SmoothPlastic)
	end
	for _, t in ipairs({ .15, .45, .85 }) do
		K.Part(m, "BoneMoss", V3(.75, .12, .9), CF(spine(t) + V3(0, .6, rng:NextNumber(-.2, .2))) * ANG(0, rng:NextNumber(-.4, .4), 0), P.Moss, M.Grass)
	end
	-- neck: four cervical vertebrae curling down from the withers to the skull
	local n0 = spine(0) - dirAt(0) * (half + .3)
	local ctl = V3(n0.X - 1.2, n0.Y - 1.6, n0.Z + (neckTo.Z - n0.Z) * .35)
	local prevN = n0
	for k = 1, 4 do
		local t = k / 4.3
		local q = n0:Lerp(ctl, t):Lerp(ctl:Lerp(neckTo, t), t)
		local nd = (q - prevN).Unit
		local side = nd:Cross(V3(0, 1, 0))
		side = side.Magnitude > .1 and side.Unit or V3(0, 0, 1)
		K.Rod(m, "NeckLink", prevN, q, .62, BONE3[3], M.SmoothPlastic)
		K.Ball(m, "NeckVertebra", 1.25 - k * .06, CF(q), BONE3[k % 2 + 1], M.SmoothPlastic)
		K.Bar(m, "NeckProcess", q - side * .85, q + side * .85, .4, .3, BONE3[2], M.SmoothPlastic)
		prevN = q
	end
	-- ribs: phi 0 (spine) .. 125 deg (into the berm), sweeping back toward the hips; one north rib snapped
	local phis = { 0, .55, 1.15, 1.7, 2.18 }
	local W, H = { .66, .58, .5, .42 }, { .74, .66, .58, .5 }
	local feet, knuckles = {}, {}
	for k = 1, 7 do
		local t = .06 + (k - 1) * .115
		local sp = spine(t)
		local R = (sp.Y - .3) / (1 - math.cos(phis[#phis]))
		local cy = sp.Y - R
		for _, s in ipairs({ -1, 1 }) do
			local tone = BONE3[(k + (s > 0 and 1 or 0)) % 3 + 1]
			local broken = k == 5 and s == -1
			local pts = {}
			for j, phi in ipairs(phis) do
				pts[j] = V3(sp.X + j * .32, cy + R * math.cos(phi), z + s * R * math.sin(phi) * (k == 7 and .85 or 1))
			end
			pts[#phis] = V3(pts[#phis].X + .1, -.35, pts[#phis].Z + s * .25) -- the foot dives into the berm
			local last = broken and 3 or #phis
			for j = 1, last - 1 do
				local col = j >= 3 and tone:Lerp(BONE3[3], .45) or tone
				K.Bar(m, "Rib", pts[j], pts[j + 1], W[j], H[j], col, M.SmoothPlastic, (j == last - 1 and not broken and k % 2 == 1) and S() or nil)
				if j > 1 then
					K.Ball(m, "RibKnuckle", math.max(W[j - 1], H[j - 1]) * 1.12, CF(pts[j]), BONE3[1]:Lerp(tone, .5), M.SmoothPlastic)
				end
			end
			if broken then
				K.Wedge(m, "RibSnap", V3(.46, .55, .5), CF(pts[3]) * ANG(.3, 0, s * .4), tone, M.SmoothPlastic)
				local a = V3(pts[4].X + .8, .35, pts[4].Z + s * 1.1)
				local b = V3(pts[5].X - .6, .3, pts[5].Z + s * 2.6)
				K.Bar(m, "BrokenRib", a, b, .44, .5, tone:Lerp(BONE3[3], .4), M.SmoothPlastic)
				K.Ball(m, "RibKnuckle", .56, CF(a), BONE3[2], M.SmoothPlastic)
			end
			if k == 4 and s == 1 then
				K.Attach(K.Part(m, "RibTop", V3(.2, .2, .2), CF(pts[3] + V3(0, .4, 0)), BONE3[1], nil, { Transparency = 1 }), "CrowPerch")
			end
			table.insert(feet, pts[#phis])
			knuckles[k * s] = pts[2]
		end
	end
	-- earth berms swallowing the rib feet, clods, a candle cluster inside the cage, cobwebs between two ribs
	for _, s in ipairs({ -1, 1 }) do
		local zz = z + s * 4.1
		K.Ellipsoid(m, "RibBerm", V3(x1 - x0 + 1.5, 1.2, 3.0), CF((x0 + x1) / 2 + .2, -.1, zz) * ANG(0, s * .03, 0), C(62, 48, 44), M.Mud)
		K.Ellipsoid(m, "RibBerm", V3((x1 - x0) * .55, .9, 2.0), CF(x0 + (x1 - x0) * .3, .05, zz + s * .6), C(72, 58, 50), M.Ground)
	end
	for k = 1, 2 do
		local f = feet[k * 6]
		K.Ball(m, "DirtClod", rng:NextNumber(.6, 1.0), CF(f.X + rng:NextNumber(-.8, .8), .15, f.Z + rng:NextNumber(-.6, .6)), C(56, 42, 40), M.Mud)
	end
	K.Candles(m, CF(feet[8].X - .4, .2, z + 2.7), 4, rng, { Light = false, Spread = .5 })
	Y.Cobweb(m, CF(knuckles[2]), 1.4)
	-- pelvis: sacrum, ilium wings, hip sockets, ischia, a femur lying out on the south side; tail into the ground
	local hip = spine(1)
	local hd = dirAt(.99)
	local HF = K.Look(hip, hip - hd) -- -Z toward the head, +X = north
	K.Bar(m, "Sacrum", hip - hd * .4, hip + hd * 1.6 + V3(0, -.5, 0), 1.3, .9, BONE3[2], M.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		K.Part(m, "IliumWing", V3(.5, 2.8, 2.3), HF * CF(s * 1.3, -.9, -.2) * ANG(-.25, 0, s * .55), BONE3[1], M.SmoothPlastic, s < 0 and S() or nil)
		K.Ball(m, "HipSocket", 1.25, HF * CF(s * 2.15, -2.35, .5), BONE3[2], M.SmoothPlastic)
		K.Bar(m, "Ischium", (HF * CF(s * 2.0, -2.4, .6)).Position, (HF * CF(s * 1.1, -3.0, 2.4)).Position, .55, .6, BONE3[3], M.SmoothPlastic)
	end
	local fa, fb = (HF * CF(-2.2, -2.6, .7)).Position, V3(hip.X + 3.4, .45, z + 4.8)
	K.Rod(m, "Femur", fa, fb, .62, BONE3[1], M.SmoothPlastic)
	K.Ball(m, "FemurKnob", .85, CF(fb + V3(.2, .05, .35)), BONE3[2], M.SmoothPlastic)
	K.Ball(m, "FemurKnob", .85, CF(fb + V3(.35, .05, -.3)), BONE3[2], M.SmoothPlastic)
	local tp = hip + hd * 1.6 + V3(0, -.6, 0)
	for k = 1, 6 do
		tp += V3(.85, -.62 - k * .05, k % 2 == 0 and .25 or -.15)
		K.Ball(m, "TailBone", .82 - k * .08, CF(tp), BONE3[k % 3 + 1], M.SmoothPlastic)
	end
	-- scapula against the front ribs, foreleg + paw bones in the dirt (south side)
	local sc = spine(.1)
	K.Wedge(m, "Scapula", V3(.35, 2.6, 1.9), CF(sc.X + .6, 3.9, z + 5.05) * ANG(-.3, 0, 0) * ANG(0, PI / 2, 0), BONE3[3], M.SmoothPlastic)
	local h0, h1, h2 = V3(sc.X + .3, 2.5, z + 5.3), V3(sc.X + 1.0, .5, z + 7.4), V3(sc.X + 3.4, .32, z + 8.5)
	K.Rod(m, "Humerus", h0, h1, .58, BONE3[1], M.SmoothPlastic)
	K.Ball(m, "ElbowKnob", .82, CF(h1), BONE3[2], M.SmoothPlastic)
	K.Rod(m, "Radius", h1, h2, .46, BONE3[2], M.SmoothPlastic)
	for k = 1, 4 do
		K.Ball(m, "PawBone", .36, CF(h2 + V3(.6, -.05, (k - 2.5) * .34)), BONE3[1], M.SmoothPlastic)
	end
	-- two lanterns hanging from the spine inside the cage (the purple one lights the ribs, the green one only glows)
	for _, def in ipairs({ { .28, "Purple", true }, { .55, "Green", false } }) do
		local p = spine(def[1])
		local hookY = p.Y - .6
		K.Chain(m, V3(p.X, hookY + .1, z), V3(p.X, hookY - .1, z), 0, 1)
		local ln = K.Lantern(m, CF(p.X, hookY - 1.75, z) * ANG(0, .3, 0), Y.GLOW[def[2]], def[2], { Range = 16, Brightness = 1.1 })
		ln.Name = "SpineLantern"
		if not def[3] then
			local glass = ln:FindFirstChild("LanternGlass")
			local l = glass and glass:FindFirstChildOfClass("PointLight")
			if l then
				l:Destroy()
				K.Stats.Lights -= 1
			end
		end
	end
	K.Attach(K.Part(m, "SpineTop", V3(.2, .2, .2), CF(spine(.45) + V3(0, -.9, 0)), BONE3[1], nil, { Transparency = 1 }), "BatRoost")
	return m
end

------------------------------------------------------------------------------------------------------------------
local function scarecrow(parent, cf)
	local m = K.Model(parent, "ScarecrowDog")
	local post = K.Part(m, "ScarecrowPost", V3(.4, 7.4, .4), cf * CF(0, 3.7, 0), WOOD_D, M.Wood, S())
	K.Part(m, "ScarecrowArm", V3(5.4, .35, .35), cf * CF(0, 5.4, 0), WOOD_D, M.Wood)
	K.Part(m, "ScarecrowCoat", V3(2.4, 2.8, 1.2), cf * CF(0, 4.6, 0), C(90, 60, 110), M.Fabric)
	K.Part(m, "CoatPatch", V3(.8, .7, .06), cf * CF(.5, 4.2, -.62), C(200, 120, 40), M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "Sleeve", V3(1.4, .9, .9), cf * CF(sx * 1.8, 5.4, 0), C(80, 54, 100), M.Fabric)
		K.Part(m, "Straw", V3(.7, .5, .5), cf * CF(sx * 2.75, 5.3, 0) * ANG(0, 0, sx * .5), C(220, 180, 90), M.Fabric)
	end
	local head = cf * CF(0, 6.9, 0)
	K.Part(m, "SackHead", V3(1.8, 1.6, 1.7), head, C(190, 160, 110), M.Fabric)
	K.Part(m, "SackSnout", V3(1, .8, .9), head * CF(0, -.3, -1.1), C(180, 150, 100), M.Fabric)
	K.Ball(m, "ButtonNose", .4, head * CF(0, -.1, -1.56), C(30, 20, 20), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "SackEar", V3(.4, 1.2, .8), head * CF(sx * 1, -.2, .1) * ANG(0, 0, sx * .35), C(160, 130, 90), M.Fabric)
		K.CylZ(m, "ButtonEye", .1, .38, head * CF(sx * .45, .3, -.86), Y.GLOW.Orange, M.Neon)
	end
	K.Part(m, "Stitches", V3(.9, .06, .06), head * CF(0, -.55, -1.56), C(40, 30, 30), M.SmoothPlastic)
	-- witch hat
	K.CylY(m, "HatBrim", .15, 2.6, head * CF(0, .85, 0), C(30, 24, 40), M.Fabric)
	for k, d in ipairs({ 1.5, 1.1, .7, .35 }) do
		K.CylY(m, "HatCone", .55, d, head * CF(k * .06, .95 + k * .5, k * .04) * ANG(0, 0, -k * .08), C(36, 28, 48), M.Fabric)
	end
	K.CylY(m, "HatBand", .2, 1.55, head * CF(0, 1.1, 0), C(200, 110, 40), M.Fabric)
	K.Attach(post, "CrowPerch", CF(2.6, 1.85, 0))
	return m
end

local function pumpkinPatch(parent, name, center, rng, count)
	local m = K.Model(parent, name)
	K.Ellipsoid(m, "PatchDirt", V3(8.4, .2, 6.6), CF(center + V3(0, .03, 0)), C(64, 48, 40), M.Mud)
	for k = 1, count do
		local a = k / count * PI * 2 + rng:NextNumber(-.3, .3)
		local r = rng:NextNumber(1, 3)
		local pos = center + V3(math.cos(a) * r, 0, math.sin(a) * r * .75)
		local size = rng:NextNumber(1.1, 2.3)
		local face = k % 3 == 0
		Y.Pumpkin(m, CF(pos) * ANG(0, rng:NextNumber(0, PI * 2), 0), size, { Face = face, Lobes = face and 5 or 4,
			Glow = (k % 2 == 0) and Y.GLOW.Orange or Y.GLOW.Green })
		local nxt = center + V3(math.cos(a + .9) * (r + .4), 0, math.sin(a + .9) * (r + .4) * .75)
		K.Rod(m, "PumpkinVine", pos + V3(0, .25, 0), nxt + V3(0, .2, 0), .16, P.Stem, M.Grass)
		K.Ellipsoid(m, "PumpkinLeaf", V3(1, .1, .8), CF(nxt + V3(0, .26, 0)) * ANG(0, a, .1), C(60, 90, 50), M.Grass)
	end
	return m
end

local function signpost(parent, pos, boards)
	local m = K.Model(parent, "Signpost")
	local post = K.Part(m, "SignPost", V3(.5, 8.2, .5), CF(pos + V3(0, 4.1, 0)), WOOD_D, M.Wood, S())
	K.Part(m, "SignPostFoot", V3(1.1, .5, 1.1), CF(pos + V3(0, .25, 0)), C(70, 66, 78), M.Cobblestone)
	for k, b in ipairs(boards) do
		local dir = b[2].Unit
		local y = 7.4 - (k - 1) * 1.25
		local cf = CFrame.fromMatrix(pos + V3(0, y, 0) + dir * 1.75, dir, V3(0, 1, 0)) -- board's X runs along dir
		local col = b[3] or C(110, 80, 56):Lerp(C(80, 60, 90), (k % 2) * .5)
		local board = K.Part(m, "SignBoard", V3(3.2, .9, .16), cf * ANG(0, 0, (k % 2 == 0 and .03 or -.04)), col, M.WoodPlanks)
		K.Part(m, "SignArrow", V3(.64, .64, .16), cf * CF(1.6, 0, 0) * ANG(0, 0, PI / 4), col, M.WoodPlanks)
		local g1 = K.Sign(board, N.Front, b[1], P.Cream, { PixelsPerStud = 24, H = .74, StrokeColor = C(40, 24, 20) })
		local g2 = K.Sign(board, N.Back, b[1], P.Cream, { PixelsPerStud = 24, H = .74, StrokeColor = C(40, 24, 20), Name = "LetteringBack" })
		local _ = { g1, g2 }
	end
	local cap = K.Part(m, "SignPostCap", V3(.8, .3, .8), CF(pos + V3(0, 8.35, 0)), C(60, 44, 36), M.Wood)
	K.Attach(cap, "CrowPerch", CF(0, .3, 0))
	Y.Pumpkin(m, CF(pos + V3(.9, 0, -1)) * ANG(0, .5, 0), 1.3, { Lobes = 4 })
	return m
end

------------------------------------------------------------------------------------------------------------------
return {
	Build = function(ctx)
		local L = ctx.Layout
		local rng = Y.Rng(7301)
		local clear = Y.Keepout(L)
		local root = K.Model(ctx.Root, "Props")
		local y0 = L.FloorY
		local cauldron = L.Cauldron.Center

		-- 1. ghost kennels facing the cauldron plaza
		for i, p in ipairs(L.Kennels) do
			local dir = V3(cauldron.X - p.X, 0, 0).Unit
			kennel(root, i, p, dir, Y.Rng(7400 + i))
		end

		-- 2. carts
		pumpkinWagon(root, L.Carts[1], rng)
		local c2 = L.Carts[2]
		mineCart(root, V3(c2.X + 1.5, c2.Y, c2.Z - 1.5), rng) -- nudged east: ore node 7 sits 7 studs west of the cart point
		boneCart(root, L.Carts[3], rng)

		-- 3. broken dig stations + machinery on the east field
		digStation(root, 1, V3(168, y0, 612), .3, Y.Rng(7501))
		digStation(root, 2, V3(183, y0, 708), -.5, Y.Rng(7502))
		excavator(root, V3(152, y0, 732.5), 2.4, PI - 2.4) -- tracks diagonal, arm slewed south over a grave by the fence
		generator(root, V3(178, y0, 592), .2)

		-- 4. the giant dog skeleton over the path to the pit's east ramp; its skull lies at the neck end north of the walk,
		--    staring at the pit rim, the Grave Bell and the cauldron (green eyes: the only PointLight is in the left socket)
		local skullCf = CF(168, y0, 660) * ANG(0, .2, 0) * ANG(0, 0, .04)
		Y.GiantSkull(root, skullCf, 1.1, { Name = "GiantDogSkull", Light = 14, Brightness = 1.3, Lantern = "Green" })
		ribcage(root, 165.5, 179.5, L.Pit.Center.Z, (skullCf * CF(0, 2.5, 7.0)).Position, rng)

		-- 5. Hollow Lane lantern row on the lane's +Z edge with chains between pairs of posts
		local kinds = { "Orange", "Purple", "Green" }
		local lz = L.Lane.Z1 + 1.8
		local posts = {}
		for k, x in ipairs({ 46.5, 69.5, 92.5, 115.5, 138.5, 161.5, 184.5, 203.5 }) do
			local kind = kinds[(k - 1) % 3 + 1]
			local base = CF(x, y0, lz) * ANG(0, PI / 2, 0) -- arm reaches over the lane (-Z)
			K.Part(root, "LanternFoot", V3(1.3, .6, 1.3), CF(x, y0 + .3, lz), C(70, 66, 80), M.Cobblestone, S())
			local ln = K.Lantern(root, base * CF(0, .6, 0), Y.GLOW[kind], kind, { Height = 8.4, Range = 18, Brightness = 1 })
			ln.Name = "LaneLantern"
			local cap = K.Part(root, "LanternFinial", V3(.5, .5, .5), CF(x, y0 + 9.25, lz), C(50, 52, 60), M.CorrodedMetal)
			K.Attach(cap, "CrowPerch", CF(0, .4, 0))
			table.insert(posts, V3(x, y0 + 8.5, lz))
			if k % 3 == 1 then
				Y.Pumpkin(root, CF(x + .9, y0, lz + 1) * ANG(0, PI + .4, 0), 1.2, { Lobes = 4 })
			end
		end
		for _, pair in ipairs({ { 2, 3 }, { 5, 6 }, { 7, 8 } }) do -- spans that cross neither the cemetery arch nor the cauldron walk
			K.Chain(root, posts[pair[1]], posts[pair[2]], 1.1, 21) -- lowest link ~y 7.6: above the players' heads
		end

		-- 6. signposts
		signpost(root, V3(118.6, y0, 585.6), {
			{ "CAULDRON", V3(1, 0, 1.2) }, { "THE PIT", V3(.3, 0, 1) }, { "CEMETERY", V3(-1, 0, .25) }, { "BROKEN LAB", V3(1, 0, .1) },
		})
		signpost(root, V3(113, y0, 636), {
			{ "THE PIT", V3(1, 0, 1) }, { "CRYPTS", V3(.1, 0, 1) }, { "HOLLOW LANE", V3(0, 0, -1) },
		})

		-- 7. pumpkin patches + scarecrow-dog
		pumpkinPatch(root, "PumpkinPatch", V3(106.5, y0, 610), Y.Rng(7601), 7)
		scarecrow(root, CF(108.8, y0, 612.6) * ANG(0, -1.2, 0))
		pumpkinPatch(root, "PumpkinPatch", V3(167, y0, 641), Y.Rng(7602), 6)

		-- 8. bone piles
		for k, b in ipairs({ { 162.5, 695, true }, { 112, 594, false }, { 190, 716, true } }) do
			local pos = V3(b[1], y0, b[2])
			if clear(pos, 6) then
				Y.BonePile(root, CF(pos), Y.Rng(7700 + k), 4, b[3])
			end
		end

		-- 9. markers: ghost path loop around the pit (continues the graveyard's GhostPath_1..6), fog
		for i, g in ipairs({ { 106, 598 }, { 150, 604 }, { 170, 640 }, { 186, 700 }, { 156, 724 }, { 104, 728 } }) do
			Y.Marker(root, "GhostPath_" .. (6 + i), V3(g[1], y0 + 3.2, g[2]))
		end
		for _, f in ipairs({ { 167, 672 }, { 106, 616 }, { 168, 618 }, { 183, 712 }, { 150, 728 }, { 200, 668 } }) do
			Y.Marker(root, "FogPoint", V3(f[1], y0 + .4, f[2]))
		end
	end,
}
