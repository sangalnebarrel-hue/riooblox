-- TRICK OR TREAT STREET presentation (StarterPlayerScripts.HalloweenClient.HouseFX), WP10b. Client only.
-- Server logic: ServerScriptService.Halloween.Houses (one knock per house per UTC day, outcome decided there).
-- Signal "House" {Index, Kind = "Treat"|"Trick", Trick, UserId, Candy} (everyone): three knocks, the door (Model with
-- attribute HwDoor = i, pivot = hinge, OpenAngle / OpenSign) creaks open, the vestibule light flickers, then
--   TREAT      a skeleton paw in a ghostly sleeve reaches out and offers candy (+ candies hop from the porch bowl);
--   Jumpscare  a ghost-dog skull pops at the knocker's camera (<= 0.6 s, small flash; ReducedMotion: fade, no pop/shake)
--   Ghosts     three little ghosts fly out and circle the knocker for 6 s
--   Fog        thick local fog for 8 s (screen haze + fog around the knocker)
--   FakeChest  a treasure chest rises on the porch, rattles, opens: bats burst out + a little candy
--   CurseBoost purple curse smoke around the knocker
--   MiniBoss   a skeleton dog leaps out onto the porch path (the Strike target "MiniBoss"; HouseFX renders it)
-- and the door closes ~5 s later. Every trick shows the small candy reward. Signal "HouseBoss" {Kind = Spawn|Down|Escape}.
-- Houses the local player already knocked today get a dimmed porch lantern (attribute HwLocalDim read by AmbientFX) and
-- a "come back tomorrow" prompt text. Part-built models: HouseFX.Models (Paw, ScareFace, Chest, Skeleton).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Ambient = require(script.Parent:WaitForChild("AmbientFX"))
local Rig = Ambient.Rig

local IDENT = CFrame.new()
local V3 = Vector3.new
local RGB = Color3.fromRGB
local rad = math.rad
local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end
local smooth, envelope, bezier, yawCF = Ambient.Smooth, Ambient.Envelope, Ambient.Bezier, Ambient.YawCF
local attPos = Ambient.AttPos

local HouseFX = {}

local C = {
	Bone = RGB(236, 226, 200), BoneDark = RGB(188, 172, 140), Socket = RGB(20, 14, 26), Eye = RGB(140, 255, 120),
	Claw = RGB(46, 40, 48), Ghost = RGB(170, 225, 255), Wood = RGB(104, 66, 40), WoodDark = RGB(70, 44, 30), Iron = RGB(60, 58, 66),
	Gold = RGB(255, 200, 70), Purple = RGB(150, 80, 255), Sack = RGB(196, 110, 40), Tie = RGB(122, 62, 200), Pumpkin = RGB(255, 128, 24),
}
HouseFX.Colors = C

---------------------------------------------------------------------------------------------------------------------
-- Models (rest space, facing -Z)
---------------------------------------------------------------------------------------------------------------------
local Models = {}
HouseFX.Models = Models

-- skeleton paw in a ghostly sleeve, reaching along -Z (elbow at +Z). Bones: Wrist, Toe1..4
function Models.Paw(parent: Instance?): any
	local r = Rig.new("HwSkeletonPaw", parent)
	local m = Enum.Material.SmoothPlastic
	r:Bone("Wrist", "Root", at(0, 0, -.7))
	-- ghostly sleeve
	r:Part("Root", V3(1.1, 1.0, 3.8), at(0, .05, 1.5), C.Ghost, Enum.Material.SmoothPlastic, { Mesh = "Sphere", T = .6, Name = "Sleeve" })
	r:Part("Root", V3(.7, .66, 3.0), at(0, .05, 1.4), RGB(120, 200, 255), Enum.Material.Neon, { Mesh = "Sphere", T = .82, Name = "SleeveGlow" })
	for k = 0, 4 do
		local a = rad(-70 + k * 35)
		r:Part("Root", V3(.22, .55, .3), at(math.sin(a) * .5, -.25 + math.cos(a) * -.2, -.15) * ang(0, 0, math.deg(a) * .6), C.Ghost,
			Enum.Material.SmoothPlastic, { Class = "WedgePart", T = .55, Name = "Cuff" })
	end
	-- radius + ulna
	for s = -1, 1, 2 do
		r:Part("Root", V3(2.2, .17, .17), at(s * .12, 0, .4) * ang(0, 90, 0), C.Bone, m, { Shape = "Cylinder", Name = "Forearm" })
		r:Part("Root", V3(.26, .26, .26), at(s * .12, 0, 1.5), C.Bone, m, { Shape = "Ball", Name = "Elbow" })
	end
	r:Part("Wrist", V3(.44, .36, .4), at(0, 0, -.72), C.Bone, m, { Mesh = "Sphere", Name = "Carpal" })
	r:Part("Wrist", V3(.92, .26, .7), at(0, -.03, -1.1), C.Bone, m, { Mesh = "Sphere", Name = "Pad" })
	for k = 1, 4 do
		local x = -.33 + (k - 1) * .22
		local spread = (k - 2.5) * 9
		r:Bone("Toe" .. k, "Wrist", at(x, -.02, -1.38) * ang(0, -spread, 0))
		r:Part("Toe" .. k, V3(.13, .13, .38), at(x, -.02, -1.56) * ang(0, -spread, 0), C.Bone, m, { Name = "Toe" })
		r:Part("Toe" .. k, V3(.15, .15, .15), at(x, -.02, -1.38), C.BoneDark, m, { Shape = "Ball", Name = "Knuckle" })
		r:Part("Toe" .. k, V3(.1, .1, .3), at(x - math.sin(rad(spread)) * .3, -.04, -1.86) * ang(-20, -spread, 0), C.Bone, m, { Name = "Toe" })
		r:Part("Toe" .. k, V3(.08, .14, .2), at(x - math.sin(rad(spread)) * .42, -.1, -2.06) * ang(0, -spread, 180), C.Claw, m, { Class = "WedgePart", Name = "Claw" })
	end
	-- dewclaw / thumb
	r:Part("Wrist", V3(.12, .12, .3), at(.5, -.02, -.95) * ang(0, -40, 0), C.Bone, m, { Name = "Thumb" })
	r:Update(IDENT, Models.PawPose(0))
	return r
end

-- open 0 (curled, holding) .. 1 (open, offering)
function Models.PawPose(open: number, wave: number?): { [string]: CFrame }
	local curl = 52 * (1 - open) - 8 * open
	local pose = { Wrist = ang(-18 * (1 - open) + 8 * open, (wave or 0) * 14, 0) }
	for k = 1, 4 do
		pose["Toe" .. k] = ang(-curl, 0, 0)
	end
	return pose
end

-- ghost-dog skull for the jumpscare (~3 wide): angry slanted sockets, glowing eyes, nasal cavity, fangs, dark maw.
-- Bones: Jaw
function Models.ScareFace(parent: Instance?): any
	local r = Rig.new("HwScareFace", parent)
	local m = Enum.Material.SmoothPlastic
	local bone, shade = RGB(222, 210, 180), RGB(168, 152, 120)
	local eye = RGB(190, 255, 90)
	r:Bone("Jaw", "Root", at(0, -.45, .25))
	r:Part("Root", V3(3.7, 3.4, 3.3), at(0, .2, .45), RGB(150, 255, 190), m, { Mesh = "Sphere", T = .8, Name = "Aura" })
	r:Part("Root", V3(2.5, 2.05, 2.4), at(0, .62, .45), bone, m, { Mesh = "Sphere", Name = "Cranium" })
	r:Part("Root", V3(1.9, 1.2, 1.2), at(0, .15, -.25), bone, m, { Mesh = "Sphere", Name = "Cheeks" })
	r:Part("Root", V3(.98, .78, 1.55), at(0, .02, -.95), bone, m, { Mesh = "Sphere", Name = "Snout" })
	r:Part("Root", V3(.5, .22, 1.2), at(0, .42, -.8) * ang(-8, 0, 0), shade, m, { Name = "Bridge" })
	-- inverted-heart nasal cavity
	for s = -1, 1, 2 do
		r:Part("Root", V3(.2, .3, .12), at(s * .09, .3, -1.69) * ang(0, 0, s * 25), C.Socket, m, { Mesh = "Sphere", Name = "Nostril" })
	end
	for s = -1, 1, 2 do
		-- angry brow ridge (inner end lower) over a deep slanted socket with a burning eye
		r:Part("Root", V3(1.15, .34, .62), at(s * .56, 1.1, -.5) * ang(0, s * -10, s * 20), shade, m, { Name = "Brow" })
		r:Part("Root", V3(.9, .72, .42), at(s * .56, .64, -.66) * ang(0, s * -14, s * 18), C.Socket, m, { Mesh = "Sphere", Name = "Socket" })
		r:Part("Root", V3(.24, .24, .24), at(s * .52, .6, -.88), eye, Enum.Material.Neon, { Shape = "Ball", Name = "Eye" })
		r:Part("Root", V3(.5, .5, .2), at(s * .52, .6, -.84), eye, Enum.Material.Neon, { Mesh = "Sphere", T = .65, Name = "EyeGlow" })
		-- torn ghostly ears
		r:Part("Root", V3(.42, 1.45, .7), at(s * 1.18, 1.55, .55) * ang(-18, 0, s * -30), RGB(170, 235, 210), m, { Mesh = "Sphere", T = .5, Name = "Ear" })
		r:Part("Root", V3(.2, .5, .2), at(s * 1.42, 2.15, .45) * ang(0, 0, s * -40), RGB(170, 235, 210), m, { Class = "WedgePart", T = .5, Name = "EarTear" })
		-- cracks
		r:Part("Root", V3(.05, .55, .05), at(s * 1.08, .3, -.15) * ang(0, 0, s * 28), C.Socket, m, { Name = "Crack" })
		r:Part("Root", V3(.05, .32, .05), at(s * 1.2, -.02, -.05) * ang(0, 0, s * -24), C.Socket, m, { Name = "Crack" })
		-- upper fangs
		r:Part("Root", V3(.15, .62, .15), at(s * .36, -.5, -1.4) * ang(0, 0, 180), bone, m, { Class = "WedgePart", Name = "Fang" })
	end
	r:Part("Root", V3(.05, .8, .05), at(.25, 1.45, -.5) * ang(0, 0, 14), C.Socket, m, { Name = "Crack" })
	r:Part("Root", V3(.05, .4, .05), at(.36, 1.12, -.62) * ang(0, 0, -30), C.Socket, m, { Name = "Crack" })
	for k, x in ipairs({ -.22, -.08, .08, .22 }) do
		r:Part("Root", V3(.09, .2 + (k % 2) * .1, .09), at(x, -.42, -1.6), bone, m, { Class = "WedgePart", Name = "Tooth" })
	end
	-- the maw (dark cavity; shows when the jaw drops)
	r:Part("Root", V3(1.05, .95, 1.3), at(0, -.45, -.7), RGB(10, 4, 14), m, { Mesh = "Sphere", Name = "Maw" })
	r:Part("Root", V3(.6, .4, .6), at(0, -.5, -.6), RGB(120, 255, 120), Enum.Material.Neon, { Mesh = "Sphere", T = .55, Name = "MawGlow" })
	-- jaw with lower fangs
	r:Part("Jaw", V3(1.02, .28, 1.4), at(0, -.92, -.72), bone, m, { Mesh = "Sphere", Name = "Jaw" })
	for s = -1, 1, 2 do
		r:Part("Jaw", V3(.13, .45, .13), at(s * .3, -.62, -1.25), bone, m, { Class = "WedgePart", Name = "Fang" })
		r:Part("Jaw", V3(.08, .2, .08), at(s * .12, -.72, -1.36), bone, m, { Class = "WedgePart", Name = "Tooth" })
	end
	r:Update(IDENT, Models.ScarePose(0))
	return r
end

function Models.ScarePose(open: number, shake: number?): { [string]: CFrame }
	return { Jaw = ang(open * 38, 0, 0), Root = ang(-open * 8, 0, (shake or 0) * 6) }
end

-- treasure chest (~2.6 wide, lid hinged at the back top edge). Bones: Lid
function Models.Chest(parent: Instance?): any
	local r = Rig.new("HwFakeChest", parent)
	local w, h, d = 2.5, 1.35, 1.6
	r:Bone("Lid", "Root", at(0, h, d / 2))
	r:Part("Root", V3(w, h, d), at(0, h / 2, 0), C.Wood, Enum.Material.WoodPlanks, { Name = "ChestBox" })
	-- treasure glow on top of the box (hidden under the domed lid until it opens)
	r:Part("Root", V3(w - .3, .06, d - .3), at(0, h + .03, 0), C.Gold, Enum.Material.Neon, { Name = "ChestGlow" })
	for k = 1, 5 do
		r:Part("Root", V3(.26, .1, .26), at(-.8 + k * .3, h + .08, (k % 2) * .3 - .15), RGB(255, 226, 120), Enum.Material.Metal, { Shape = "Cylinder", Name = "Coin" })
	end
	for _, x in ipairs({ -.85, 0, .85 }) do
		r:Part("Root", V3(.2, h + .04, d + .06), at(x, h / 2, 0), C.Iron, Enum.Material.CorrodedMetal, { Name = "Band" })
	end
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			r:Part("Root", V3(.24, .24, .24), at(sx * (w / 2 - .05), .14, sz * (d / 2 - .05)), C.Gold, Enum.Material.Metal, { Name = "Corner" })
		end
	end
	r:Part("Root", V3(w + .1, .16, d + .1), at(0, .08, 0), C.WoodDark, Enum.Material.Wood, { Name = "Plinth" })
	r:Part("Root", V3(.55, .62, .14), at(0, h - .28, -d / 2 - .05), C.Gold, Enum.Material.Metal, { Name = "Lock" })
	r:Part("Root", V3(.12, .24, .05), at(0, h - .3, -d / 2 - .13), C.Socket, Enum.Material.SmoothPlastic, { Name = "Keyhole" })
	-- domed lid: half-cylinder sitting on the box, with bands and a skull boss
	r:Part("Lid", V3(w, d, d), at(0, h, 0), C.Wood, Enum.Material.WoodPlanks, { Shape = "Cylinder", Name = "LidDome" })
	r:Part("Lid", V3(w + .02, .14, d + .02), at(0, h + .02, 0), C.WoodDark, Enum.Material.Wood, { Name = "LidRim" })
	for _, x in ipairs({ -.85, 0, .85 }) do
		r:Part("Lid", V3(.2, d + .08, d + .08), at(x, h, 0), C.Iron, Enum.Material.CorrodedMetal, { Shape = "Cylinder", Name = "LidBand" })
	end
	r:Part("Lid", V3(.42, .4, .3), at(0, h + .55, -.62), C.Bone, Enum.Material.SmoothPlastic, { Mesh = "Sphere", Name = "LidSkull" })
	for s = -1, 1, 2 do
		r:Part("Lid", V3(.1, .1, .05), at(s * .09, h + .6, -.77), C.Purple, Enum.Material.Neon, { Shape = "Ball", Name = "SkullEye" })
	end
	r:Update(IDENT, Models.ChestPose(0))
	return r
end

function Models.ChestPose(open: number, rattle: number?): { [string]: CFrame }
	local j = rattle or 0
	-- +X rotation about the back hinge swings the lid up and back
	return { Lid = ang(open * 105 + math.sin(j * 40) * 4 * math.min(1, j), 0, 0), Root = ang(0, 0, math.sin(j * 31) * 3 * math.min(1, j)) }
end

-- skeleton dog with a candy sack on its back (~3.4 tall). Bones: Body, Neck, Head, Jaw, Tail, LegFL/FR/BL/BR
function Models.Skeleton(parent: Instance?): any
	local r = Rig.new("HwPorchSkeleton", parent)
	local m = Enum.Material.SmoothPlastic
	local bone, dark = C.Bone, C.BoneDark
	r:Bone("Body", "Root", at(0, 2.2, 0))
	r:Bone("Neck", "Body", at(0, 2.45, -1.35))
	r:Bone("Head", "Neck", at(0, 3.0, -1.75))
	r:Bone("Jaw", "Head", at(0, 2.75, -2.0))
	r:Bone("Tail", "Body", at(0, 2.35, 1.35))
	for _, l in ipairs({ { "LegFL", -.42, -1.0 }, { "LegFR", .42, -1.0 }, { "LegBL", -.4, 1.05 }, { "LegBR", .4, 1.05 } }) do
		r:Bone(l[1], "Body", at(l[2], 2.05, l[3]))
	end
	-- spine with little spikes
	for k = 0, 6 do
		local z = -1.2 + k * .42
		r:Part("Body", V3(.34, .3, .3), at(0, 2.45 + math.sin(k / 6 * math.pi) * .12, z), bone, m, { Name = "Vertebra" })
		r:Part("Body", V3(.12, .22, .16), at(0, 2.7 + math.sin(k / 6 * math.pi) * .12, z), dark, m, { Class = "WedgePart", Name = "Spike" })
	end
	-- ribcage: 4 pairs of curved ribs (upper + lower segment) and a sternum
	for k = 0, 3 do
		local z = -.95 + k * .38
		local len = 1 - k * .12
		for s = -1, 1, 2 do
			r:Part("Body", V3(.12, .7 * len, .12), at(s * .38, 2.18, z) * ang(0, 0, s * 28), bone, m, { Name = "Rib" })
			r:Part("Body", V3(.12, .62 * len, .12), at(s * .44, 1.62 + (1 - len) * .3, z) * ang(0, 0, s * -22), bone, m, { Name = "Rib" })
		end
	end
	r:Part("Body", V3(.22, .14, 1.3), at(0, 1.35, -.4), dark, m, { Name = "Sternum" })
	r:Part("Body", V3(1.0, .46, .7), at(0, 2.3, 1.2), bone, m, { Name = "Pelvis" })
	r:Part("Body", V3(.9, .5, .6), at(0, 2.35, -1.25), bone, m, { Name = "Shoulders" })
	-- candy sack (the bounty) strapped to the back
	r:Part("Body", V3(1.1, .95, 1.0), at(0, 3.05, .35), C.Sack, Enum.Material.Fabric, { Mesh = "Sphere", Name = "Sack" })
	r:Part("Body", V3(.42, .32, .42), at(0, 3.55, .35), C.Sack, Enum.Material.Fabric, { Mesh = "Sphere", Name = "SackNeck" })
	r:Part("Body", V3(.5, .12, .5), at(0, 3.45, .35), C.Tie, Enum.Material.Fabric, { Shape = "Cylinder", Name = "SackTie" })
	r:Part("Body", V3(.32, .3, .3), at(.12, 3.78, .3), C.Pumpkin, m, { Shape = "Ball", Name = "SackCandy" })
	r:Part("Body", V3(.26, .26, .26), at(-.16, 3.74, .45), RGB(120, 255, 110), m, { Shape = "Ball", Name = "SackCandy" })
	r:Part("Body", V3(1.25, .08, .12), at(0, 2.75, .35), C.Tie, Enum.Material.Fabric, { Name = "Strap" })
	-- neck + head
	r:Part("Neck", V3(.3, .3, .3), at(0, 2.6, -1.5), bone, m, { Shape = "Ball", Name = "Vertebra" })
	r:Part("Neck", V3(.28, .28, .28), at(0, 2.82, -1.66), bone, m, { Shape = "Ball", Name = "Vertebra" })
	r:Part("Head", V3(1.05, .9, 1.0), at(0, 3.15, -2.0), bone, m, { Mesh = "Sphere", Name = "Skull" })
	r:Part("Head", V3(.62, .5, .95), at(0, 3.02, -2.65), bone, m, { Mesh = "Sphere", Name = "Snout" })
	r:Part("Head", V3(.22, .14, .1), at(0, 3.16, -3.1), C.Socket, m, { Mesh = "Sphere", Name = "Nose" })
	for s = -1, 1, 2 do
		r:Part("Head", V3(.34, .36, .2), at(s * .26, 3.28, -2.42), C.Socket, m, { Mesh = "Sphere", Name = "Socket" })
		r:Part("Head", V3(.15, .15, .15), at(s * .26, 3.28, -2.5), C.Eye, Enum.Material.Neon, { Shape = "Ball", Name = "Eye" })
		r:Part("Head", V3(.16, .5, .3), at(s * .38, 3.68, -1.85) * ang(-10, 0, s * -18), dark, m, { Class = "WedgePart", Name = "Ear" })
		r:Part("Head", V3(.08, .2, .08), at(s * .14, 2.8, -2.95) * ang(0, 0, 180), bone, m, { Class = "WedgePart", Name = "Fang" })
	end
	r:Part("Jaw", V3(.5, .18, .85), at(0, 2.72, -2.55), bone, m, { Name = "Jaw" })
	for k = -1, 1 do
		r:Part("Jaw", V3(.07, .14, .07), at(k * .14, 2.86, -2.88), bone, m, { Class = "WedgePart", Name = "Tooth" })
	end
	-- tail
	for k = 0, 3 do
		r:Part("Tail", V3(.24 - k * .04, .24 - k * .04, .34), at(0, 2.4 + k * .16, 1.55 + k * .3) * ang(28, 0, 0), bone, m, { Name = "TailBone" })
	end
	-- legs: femur, tibia, paw
	for _, l in ipairs({ { "LegFL", -.42, -1.0 }, { "LegFR", .42, -1.0 }, { "LegBL", -.4, 1.05 }, { "LegBR", .4, 1.05 } }) do
		local x, z = l[2], l[3]
		local back = z > 0 and 1 or -1
		r:Part(l[1], V3(.2, 1.05, .2), at(x, 1.55, z + back * .1) * ang(back * 10, 0, 0), bone, m, { Name = "Femur" })
		r:Part(l[1], V3(.24, .24, .24), at(x, 1.02, z + back * .18), dark, m, { Shape = "Ball", Name = "Knee" })
		r:Part(l[1], V3(.16, .95, .16), at(x, .52, z + back * .05) * ang(-back * 8, 0, 0), bone, m, { Name = "Tibia" })
		r:Part(l[1], V3(.36, .14, .5), at(x, .07, z - .12), bone, m, { Name = "Paw" })
	end
	r:Update(IDENT, Models.SkeletonPose(0, "Idle"))
	return r
end

-- mode: "Idle" | "Hit" (t = 0..1 flinch) | "Leap" (legs tucked) | "Taunt"
function Models.SkeletonPose(t: number, mode: string, look: number?): { [string]: CFrame }
	local pose = {}
	if mode == "Hit" then
		local k = math.sin(math.clamp(t, 0, 1) * math.pi)
		pose.Body = ang(14 * k, 0, 6 * k)
		pose.Head = ang(-20 * k, 0, 0)
		pose.Jaw = ang(30 * k, 0, 0)
		pose.Tail = ang(-20 * k, 0, 0)
	elseif mode == "Leap" then
		pose.Body = ang(-12, 0, 0)
		pose.Head = ang(10, 0, 0)
		pose.Jaw = ang(25, 0, 0)
		pose.LegFL, pose.LegFR = ang(-55, 0, 0), ang(-55, 0, 0)
		pose.LegBL, pose.LegBR = ang(45, 0, 0), ang(45, 0, 0)
		pose.Tail = ang(-25, 0, 0)
	else
		local taunt = mode == "Taunt" and 1 or 0
		pose.Root = at(0, math.abs(math.sin(t * 2.2)) * .06, 0)
		pose.Body = ang(math.sin(t * 2.2) * 2 - taunt * 10, 0, math.sin(t * 1.1) * 1.5)
		pose.Neck = ang(math.sin(t * 1.3) * 5 - taunt * 15, (look or 0) * .5, 0)
		pose.Head = ang(math.sin(t * 1.7) * 6, (look or 0) * .5, math.sin(t * .9) * 10)
		pose.Jaw = ang(math.max(0, math.sin(t * 13)) * (8 + taunt * 22), 0, 0)
		pose.Tail = ang(math.sin(t * 3) * 6, math.sin(t * 7) * 28, 0)
		pose.LegFL = ang(math.sin(t * 2.2) * 2, 0, 0)
		pose.LegFR = ang(-math.sin(t * 2.2) * 2, 0, 0)
	end
	return pose
end

---------------------------------------------------------------------------------------------------------------------
-- pure helpers (Lune-tested)
---------------------------------------------------------------------------------------------------------------------
-- door swing sign: +1/-1 so that rotating the door about the hinge's Y axis moves its centre along `inward`
function HouseFX.SwingSign(pivot: CFrame, center: Vector3, inward: Vector3, angleDeg: number): number
	local function moved(sign)
		local rot = pivot * CFrame.Angles(0, rad(angleDeg) * sign, 0) * pivot:Inverse()
		return (rot * center - center):Dot(inward)
	end
	return moved(1) >= moved(-1) and 1 or -1
end

function HouseFX.KnockedToday(view: any, index: number, day: number): boolean
	local h = type(view) == "table" and view.Houses
	return type(h) == "table" and h.Day == day and type(h.Knocked) == "table" and h.Knocked[tostring(index)] == true
end

---------------------------------------------------------------------------------------------------------------------
-- runtime
---------------------------------------------------------------------------------------------------------------------
function HouseFX.Start(ctx)
	local Shared, Layout, Bus, FX, Audio, State = ctx.Shared, ctx.Layout, ctx.Bus, ctx.FX, ctx.Audio, ctx.State
	local Config = ctx.Config
	local player = Players.LocalPlayer
	local L = Shared.L
	local rng = Random.new()
	local AModels = Ambient.Models
	local folder = Instance.new("Folder")
	folder.Name = "Houses"
	folder.Parent = FX.Folder()

	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Layout.Zone.Center
	end
	local function rootOf(pl: Player?): BasePart?
		local ch = pl and pl.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		return (root and root:IsA("BasePart")) and root or nil
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local function groundY(pos: Vector3, fallback: number): number
		local ignore = { folder, FX.Folder() }
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				table.insert(ignore, pl.Character)
			end
		end
		local live = workspace:FindFirstChild("HalloweenLive")
		if live then
			table.insert(ignore, live)
		end
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(pos + V3(0, 6, 0), V3(0, -14, 0), rayParams)
		return hit and hit.Position.Y or fallback
	end

	-------------------------------------------------------------------------------------------------------------
	-- per-house registry
	-------------------------------------------------------------------------------------------------------------
	local houses = {}
	for i, lay in ipairs(Layout.Houses) do
		houses[i] = { Index = i, Lay = lay, Parts = {}, Closed = {}, Angle = 0, Anim = nil, CloseAt = nil, Lanterns = {}, Eyes = {},
			Prompt = nil, Knocked = false }
	end
	local function houseAt(pos: Vector3, maxD: number): any
		local best, bd = nil, maxD
		for _, h in ipairs(houses) do
			local d = (V3(pos.X, 0, pos.Z) - V3(h.Lay.Door.X, 0, h.Lay.Door.Z)).Magnitude
			if d < bd then
				best, bd = h, d
			end
		end
		return best
	end
	-- Streaming: the Door Model can reach the client before its parts, so GetPivot() at registration is a bounding box, not
	-- the hinge. The pivot is the DoorHinge's (PrimaryPart's) closed CFrame, taken when that part actually arrives; until
	-- then the door stays put. The server never moves the doors, so every part arrives (and streams back in) closed.
	local doorOfPart = {} -- part -> house
	local applyDoor -- (below)
	local function doorTransform(h): CFrame
		if not h.Pivot or math.abs(h.Angle) < 1e-4 then
			return IDENT
		end
		if not h.Sign then
			local sum, n = V3(), 0
			for _, p in ipairs(h.Parts) do
				sum += h.Closed[p].Position
				n += 1
			end
			local center = n > 1 and sum / n or (h.Pivot * V3(1.7, 0, 0))
			h.Sign = HouseFX.SwingSign(h.Pivot, center, -h.Lay.Facing, h.OpenAngle)
		end
		return h.Pivot * CFrame.Angles(0, rad(h.Angle) * h.Sign, 0) * h.Pivot:Inverse()
	end
	local function addDoorPart(h, p: BasePart)
		if h.Closed[p] then
			return
		end
		h.Closed[p] = p.CFrame
		doorOfPart[p] = h
		table.insert(h.Parts, p)
		if not h.Pivot and (p.Name == "DoorHinge" or p == h.Door.PrimaryPart) then
			h.Pivot = p.CFrame
			if math.abs(h.Angle) > 1e-4 then
				applyDoor(h) -- the parts that came first get the current pose too
			end
		elseif math.abs(h.Angle) > 1e-4 then
			p.CFrame = doorTransform(h) * p.CFrame
		end
	end
	local function removeDoorPart(p: BasePart)
		local h = doorOfPart[p]
		if h then
			doorOfPart[p] = nil
			h.Closed[p] = nil
			local i = table.find(h.Parts, p)
			if i then
				table.remove(h.Parts, i)
			end
		end
	end
	local doorByModel = {} -- Door model -> house
	local function dropDoor(h)
		for _, p in ipairs(h.Parts) do
			doorOfPart[p] = nil
		end
		if h.Door then
			doorByModel[h.Door] = nil
			h.DoorConn:Disconnect()
		end
		h.Door, h.Pivot, h.Parts, h.Closed = nil, nil, {}, {}
	end
	local function registerDoor(model: Model)
		local i = tonumber(model:GetAttribute("HwDoor"))
		local h = i and houses[i]
		if not h or h.Door == model then
			return
		end
		dropDoor(h)
		h.Door = model
		doorByModel[model] = h
		h.OpenAngle = tonumber(model:GetAttribute("OpenAngle")) or 100
		local sign = tonumber(model:GetAttribute("OpenSign"))
		h.Sign = (sign == 1 or sign == -1) and sign or nil
		-- the PrimaryPart reference can resolve after its part arrived
		h.DoorConn = model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			local pp = model.PrimaryPart
			if h.Door == model and not h.Pivot and pp and h.Closed[pp] then
				h.Pivot = h.Closed[pp]
				if math.abs(h.Angle) > 1e-4 then
					applyDoor(h)
				end
			end
		end)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				addDoorPart(h, d)
			end
		end
	end
	local function doorAncestor(inst: Instance): any
		local a = inst.Parent
		while a do
			local h = doorByModel[a]
			if h then
				return h
			end
			a = a.Parent
		end
		return nil
	end
	function applyDoor(h)
		if not h.Door then
			return
		end
		local T = doorTransform(h)
		local parts, cfs = {}, {}
		for _, p in ipairs(h.Parts) do
			if p.Parent then
				table.insert(parts, p)
				table.insert(cfs, T * h.Closed[p])
			end
		end
		Rig.Bulk(parts, cfs)
	end

	local function updateKnockedLook()
		local view = State.View
		local day = Shared.Day(Shared.Now())
		for _, h in ipairs(houses) do
			local knocked = HouseFX.KnockedToday(view, h.Index, day)
			h.Knocked = knocked
			for lantern in pairs(h.Lanterns) do
				if lantern.Parent then
					lantern:SetAttribute("HwLocalDim", knocked and .22 or nil)
				end
			end
			local pr = h.Prompt
			if pr and pr.Parent then
				pcall(function()
					(pr :: any).AutoLocalize = false
				end)
				if knocked then
					pr.ActionText = L("KNOCKED", "УЖЕ СТУЧАЛ")
					pr.ObjectText = L("Come back tomorrow", "Приходи завтра")
				else
					pr.ActionText = L("KNOCK", "ПОСТУЧАТЬ")
					pr.ObjectText = L("TRICK OR TREAT · HOUSE ", "СЛАДОСТЬ ИЛИ ГАДОСТЬ · ДОМ ") .. h.Index
				end
			end
		end
	end

	local function onAdded(inst: Instance)
		if inst:IsA("Model") and inst:GetAttribute("HwDoor") ~= nil then
			registerDoor(inst)
		elseif inst:IsA("BasePart") then
			local dh = doorAncestor(inst)
			if dh then
				addDoorPart(dh, inst) -- parts streaming in after their Door model
			end
			if inst.Name == "LanternGlass" and inst:GetAttribute("HwLantern") ~= nil then
				local h = houseAt(inst.CFrame.Position, 9)
				if h and inst.CFrame.Position.Z > h.Lay.Door.Z - 1 then
					h.Lanterns[inst] = true
					if h.Knocked then
						inst:SetAttribute("HwLocalDim", .22)
					end
				end
			elseif inst.Name == "WatchingEye" then
				local h = houseAt(inst.CFrame.Position, 9)
				if h then
					h.Eyes[inst] = inst.Color
				end
			end
		elseif inst:IsA("Attachment") and inst.Name == "CandyPoint" then
			local h = houseAt(attPos(inst), 10)
			if h then
				h.CandyPoint = inst
			end
		elseif inst:IsA("ProximityPrompt") then
			local key = inst:GetAttribute("HalloweenPrompt")
			local i = type(key) == "string" and tonumber(string.match(key, "^House(%d+)$"))
			if i and houses[i] then
				houses[i].Prompt = inst
				updateKnockedLook()
			end
		end
	end
	task.spawn(function()
		local yard = nil
		while not yard do
			local d = workspace:FindFirstChild("DOGROTS_District")
			yard = d and d:FindFirstChild("38_DeadYard")
			if not yard then
				task.wait(1)
			end
		end
		yard.DescendantAdded:Connect(onAdded)
		yard.DescendantRemoving:Connect(function(inst)
			local h = doorByModel[inst :: any]
			if h then
				dropDoor(h) -- streamed out as a whole: a fresh registration when it comes back
			elseif doorOfPart[inst :: any] then
				removeDoorPart(inst :: any)
			end
		end)
		for i, inst in ipairs(yard:GetDescendants()) do
			onAdded(inst)
			if i % 4000 == 0 then
				task.wait()
			end
		end
		updateKnockedLook()
	end)
	Bus.On("StateChanged", updateKnockedLook)
	task.spawn(function()
		local day = Shared.Day(Shared.Now())
		while true do
			task.wait(20)
			local now = Shared.Day(Shared.Now())
			if now ~= day then
				day = now
				updateKnockedLook()
			end
		end
	end)

	-------------------------------------------------------------------------------------------------------------
	-- door animation
	-------------------------------------------------------------------------------------------------------------
	local function swing(h, to: number, dur: number, style: string)
		h.Anim = { From = h.Angle, To = to, T0 = os.clock(), Dur = dur, Style = style }
	end
	local function openDoor(h)
		if h.Angle < (h.OpenAngle or 100) * .5 or (h.Anim and h.Anim.To == 0) then
			swing(h, (h.OpenAngle or 100) * .92, .95, "Back")
			Audio.Play("DoorCreak", h.Lay.Door + V3(0, 3, 0), { Pitch = rng:NextNumber(.9, 1.1) })
		end
	end
	local function scheduleClose(h, seconds: number)
		h.CloseAt = math.max(h.CloseAt or 0, os.clock() + seconds)
	end

	-- the vestibule: client light + watching eyes
	local function vestibule(h, color: Color3, seconds: number)
		local pos = h.Lay.Door + V3(0, 3.6, -2.4)
		local lp = FX.Part({ Name = "HwHouseGlow", Size = V3(.2, .2, .2), Transparency = 1, CFrame = CFrame.new(pos), Parent = folder })
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 13
		l.Brightness = 0
		l.Shadows = false
		l.Parent = lp
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = (os.clock() - t0) / seconds
			if t >= 1 or not lp.Parent then
				conn:Disconnect()
				lp:Destroy()
				for eye, col in pairs(h.Eyes) do
					if eye.Parent then
						eye.Color = col
					end
				end
				return
			end
			local flick = .75 + .25 * math.noise(os.clock() * 9, h.Index)
			l.Brightness = 2.2 * envelope(t, .1, .35) * flick
			for eye, col in pairs(h.Eyes) do
				if eye.Parent then
					eye.Color = col:Lerp(color, envelope(t, .05, .4))
				end
			end
		end)
	end

	-------------------------------------------------------------------------------------------------------------
	-- animated actors (one Heartbeat drives every running effect)
	-------------------------------------------------------------------------------------------------------------
	local actors = {}
	local function actor(fn: (number, number) -> boolean)
		table.insert(actors, { Fn = fn, T0 = os.clock() })
	end

	local function popupCandy(pos: Vector3, amount: number, from: Vector3?)
		if amount <= 0 then
			return
		end
		FX.Popup(pos, "+" .. Shared.Format(amount) .. " " .. L("CANDY", "КОНФЕТ"), Shared.Color("Pumpkin"), false)
		Bus.Fire("CandyGain", { Amount = amount, From = from or pos, Source = "House" })
		Audio.Play("CandyTick", nil, { Pitch = 1.1 })
	end

	local candyColors = { RGB(255, 128, 24), RGB(122, 62, 200), RGB(120, 255, 110), RGB(255, 92, 170), RGB(255, 220, 60) }
	-- a candy hops from a to a moving target (function) and vanishes there
	local function candyHop(from: Vector3, target: () -> Vector3, delay: number, dur: number, onArrive: (() -> ())?)
		local rig = AModels.Candy(nil, { Color = candyColors[rng:NextInteger(1, #candyColors)] })
		rig:SetScale(rng:NextNumber(.8, 1.1))
		rig.Model.Parent = folder
		rig:SetFade(1)
		local spin = V3(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9))
		local arrived = false
		actor(function(t)
			local k = (t - delay) / dur
			if k < 0 then
				rig:Update(CFrame.new(from))
				return true
			end
			rig:SetFade(k < .1 and 1 - k / .1 or 0)
			local to = target()
			local mid = (from + to) / 2 + V3(0, 2.5 + (from - to).Magnitude * .15, 0)
			local u = math.min(k, 1)
			local p = from * ((1 - u) ^ 2) + mid * (2 * (1 - u) * u) + to * (u * u)
			rig:Update(CFrame.new(p) * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t))
			if k >= 1 then
				if not arrived then
					arrived = true
					if onArrive then
						onArrive()
					end
				end
				rig:SetFade(math.min(1, (k - 1) / .25))
				if k > 1.25 then
					rig:Destroy()
					return false
				end
			end
			return true
		end)
	end

	-- the knocker's position (character, else the porch)
	local function knockerPos(h, pl: Player?): () -> Vector3
		return function()
			local root = rootOf(pl)
			if root and (root.CFrame.Position - h.Lay.Door).Magnitude < 40 then
				return root.CFrame.Position + V3(0, .6, 0)
			end
			return h.Lay.Porch + V3(0, 2.5, 2)
		end
	end

	local function doorFrame(h, y: number): CFrame
		-- at the threshold, facing out of the house
		return yawCF(V3(h.Lay.Door.X, y, h.Lay.Door.Z), h.Lay.Facing)
	end

	-------------------------------------------------------------------------------------------------------------
	-- TREAT: the skeleton paw
	-------------------------------------------------------------------------------------------------------------
	local function treat(h, d, pl: Player?, isMe: boolean)
		local paw = Models.Paw(folder)
		paw:SetScale(1.5) -- a big bony paw reads from the lane
		paw:SetFade(1)
		local base = doorFrame(h, 3.6)
		local target = knockerPos(h, pl)
		local candy = tonumber(d.Candy) or 0
		local released = false
		Audio.Play("GhostWoo", h.Lay.Door + V3(0, 3, 0), { Volume = .6, Pitch = 1.25 })
		actor(function(t)
			local reach
			if t < .55 then
				reach = smooth(t / .55)
			elseif t < 2.1 then
				reach = 1
			else
				reach = 1 - smooth((t - 2.1) / .45)
			end
			local open = smooth((t - .75) / .25)
			local wave = t > 1.25 and t < 2.0 and math.sin((t - 1.25) * 12) or 0
			local bob = math.sin(t * 5) * .06
			paw:Update(base * at(0, bob - .2 + reach * .2, 2.0 - reach * 3.0) * ang(-6 + reach * 6, 0, 0), Models.PawPose(open, wave))
			paw:SetFade(1 - math.min(reach * 1.6, 1))
			if t >= .85 and not released then
				released = true
				local from = (base * at(0, -.2, -2.8)).Position
				local n = math.clamp(math.floor(candy / 3), 3, 5)
				for k = 1, n do
					candyHop(from, target, (k - 1) * .07, .5, (k == 1 and isMe) and function()
						popupCandy(target() + V3(0, 2, 0), candy, from)
					end or nil)
				end
				if h.CandyPoint and h.CandyPoint.Parent then
					local bowl = attPos(h.CandyPoint)
					for k = 1, 2 do
						candyHop(bowl, target, .15 + k * .1, .55)
					end
				end
				Audio.Play("Sparkle", from)
				FX.Burst(from, { Color = Shared.Color("Gold"), Color2 = Shared.Color("Pumpkin"), Count = 14, Speed = { 3, 7 }, Lifetime = { .4, .8 },
					Size = { .25, .45, 0 } })
			end
			if t > 2.6 then
				paw:Destroy()
				return false
			end
			return true
		end)
	end

	-------------------------------------------------------------------------------------------------------------
	-- TRICKS
	-------------------------------------------------------------------------------------------------------------
	local function jumpscare(h, d, pl: Player?, isMe: boolean)
		local face = Models.ScareFace(folder)
		face:SetFade(1)
		local reduced = Shared.ReducedMotion()
		Audio.Play("Jumpscare", isMe and nil or (h.Lay.Door + V3(0, 3, 0)), { Volume = isMe and .85 or .6 })
		if isMe then
			FX.Flash(RGB(200, 255, 190), .28, .3)
			if not reduced then
				FX.Shake(.4, .3)
			end
		end
		local door = doorFrame(h, 4.2)
		local dur = .6
		actor(function(t)
			local k = t / dur
			local cf
			if isMe and not reduced then
				-- pops between the door and the camera, scaled up, then snaps back into the dark
				local cam = workspace.CurrentCamera
				local camPos2 = cam and cam.CFrame.Position or (door.Position + V3(0, 0, 8))
				local toCam = camPos2 - door.Position
				local dist = toCam.Magnitude
				local pop = k < .25 and smooth(k / .25) or k < .7 and 1 or 1 - smooth((k - .7) / .3)
				local pos = door.Position + toCam.Unit * math.min(dist * .55, 5.5) * pop
				-- the skull's snout (-Z) faces the camera
				cf = CFrame.lookAt(pos, camPos2) * ang(0, 0, math.sin(t * 60) * 4 * pop)
				face:SetScale(math.max(.05, .55 + .75 * pop) / face.Scale)
			else
				cf = door * at(0, 0, -.4) * ang(0, 0, 0)
			end
			face:Update(cf, Models.ScarePose(envelope(k, .2, .3)))
			face:SetFade(1 - envelope(k, reduced and .3 or .1, .3))
			if t > dur then
				face:Destroy()
				return false
			end
			return true
		end)
		if not isMe then
			Audio.Play("Cackle", h.Lay.Door + V3(0, 3, 0), { Delay = .2 })
		end
	end

	local function ghosts(h, d, pl: Player?, isMe: boolean)
		local target = knockerPos(h, pl)
		local n = (Shared.Low() and not isMe) and 1 or 3
		local door = h.Lay.Door + V3(0, 3.4, 0)
		Audio.Play("GhostWoo", door, { Pitch = 1.1 })
		for k = 1, n do
			local g = AModels.Ghost(folder)
			g:SetScale(.52)
			g:SetFade(1)
			local phase = (k - 1) / n * math.pi * 2
			local hgt = .6 + k * .7
			local dur = 7.4
			local last = door
			actor(function(t)
				local center = target()
				local orbit = center + V3(math.cos(phase + t * 2.3) * 4.4, hgt + math.sin(t * 3 + k) * .4, math.sin(phase + t * 2.3) * 4.4)
				local p
				if t < .8 then
					p = door:Lerp(orbit, smooth(t / .8))
				elseif t > dur - 1 then
					p = orbit + V3(0, smooth((t - (dur - 1)) / 1) * 9, 0)
				else
					p = orbit
				end
				local move = p - last
				last = p
				local yaw = move.Magnitude > 1e-3 and math.atan2(-move.X, -move.Z) or 0
				g:Update(CFrame.new(p) * CFrame.Angles(0, yaw, 0) * ang(0, 0, -14), Ambient.Models.GhostPose(t * 1.6 + k))
				g:SetFade(1 - envelope(t / dur, .1, .14))
				if t > dur then
					g:Destroy()
					return false
				end
				return true
			end)
		end
		task.delay(2.5, function()
			Audio.Play("GhostWoo", target(), { Volume = .7, Pitch = .9 })
		end)
	end

	local fogGui = nil
	local function screenFog(seconds: number)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return
		end
		if not fogGui or not fogGui.Parent then
			fogGui = Instance.new("ScreenGui")
			fogGui.Name = "DOGROTS_HalloweenFog"
			fogGui.IgnoreGuiInset = true
			fogGui.ResetOnSpawn = false
			fogGui.DisplayOrder = -2
			fogGui:SetAttribute("NoTranslate", true)
			fogGui.Parent = pg
		end
		local haze = Instance.new("Frame")
		haze.Size = UDim2.fromScale(1, 1)
		haze.BorderSizePixel = 0
		haze.BackgroundColor3 = RGB(178, 172, 200)
		haze.BackgroundTransparency = 1
		haze.Parent = fogGui
		local edges = {}
		for k = 0, 3 do
			local e = Instance.new("Frame")
			e.BorderSizePixel = 0
			e.BackgroundColor3 = RGB(150, 144, 176)
			e.BackgroundTransparency = 1
			local gr = Instance.new("UIGradient")
			gr.Transparency = NumberSequence.new(0, 1)
			gr.Rotation = k * 90
			gr.Parent = e
			if k == 0 then
				e.Size, e.Position = UDim2.fromScale(.35, 1), UDim2.fromScale(0, 0)
			elseif k == 1 then
				e.Size, e.Position = UDim2.fromScale(1, .35), UDim2.fromScale(0, 0)
			elseif k == 2 then
				e.Size, e.Position = UDim2.fromScale(.35, 1), UDim2.fromScale(.65, 0)
			else
				e.Size, e.Position = UDim2.fromScale(1, .35), UDim2.fromScale(0, .65)
			end
			e.Parent = fogGui
			table.insert(edges, e)
		end
		actor(function(t)
			local k = envelope(t / seconds, .16, .18) * (.92 + .08 * math.sin(t * 1.7))
			haze.BackgroundTransparency = 1 - .52 * k
			for _, e in ipairs(edges) do
				e.BackgroundTransparency = 1 - .55 * k
			end
			if t > seconds then
				haze:Destroy()
				for _, e in ipairs(edges) do
					e:Destroy()
				end
				return false
			end
			return true
		end)
	end
	local function fog(h, d, pl: Player?, isMe: boolean)
		local seconds = 8
		local target = knockerPos(h, pl)
		local anchor = FX.Part({ Name = "HwTrickFog", Size = V3(10, 1, 10), Transparency = 1, CFrame = CFrame.new(target()), Parent = folder })
		local e = Instance.new("ParticleEmitter")
		e.Texture = FX.Textures.Smoke
		e.Color = ColorSequence.new(RGB(190, 184, 212), RGB(120, 112, 150))
		e.LightEmission = .05
		e.LightInfluence = .4
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(.5, 9), NumberSequenceKeypoint.new(1, 12) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.25, .55), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(2.5, 4)
		e.Speed = NumberRange.new(.5, 2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = V3(0, .4, 0)
		e.Drag = 1
		e.RotSpeed = NumberRange.new(-20, 20)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.Rate = 0
		e.Parent = anchor
		local peak = (isMe and 9 or 5) * FX.Budget("Particles")
		Audio.Play("Whisper", target())
		if isMe then
			screenFog(seconds)
		end
		actor(function(t)
			anchor.CFrame = CFrame.new(target() + V3(0, .5, 0))
			e.Rate = peak * envelope(t / seconds, .12, .3)
			if t > seconds + 4 then
				anchor:Destroy()
				return false
			end
			return true
		end)
	end

	local function fakeChest(h, d, pl: Player?, isMe: boolean)
		local chest = Models.Chest(folder)
		-- on the front path between the porch steps and the yard gate, lock facing the knocker on the porch
		local spot = h.Lay.Porch + V3(0, 0, 2.6)
		local gy = groundY(spot, Layout.FloorY + .1)
		local base = yawCF(V3(spot.X, gy, spot.Z), -h.Lay.Facing)
		local opened = false
		local candy = tonumber(d.Candy) or 0
		local target = knockerPos(h, pl)
		FX.Burst(V3(spot.X, gy + .3, spot.Z), { Texture = FX.Textures.Smoke, Color = RGB(120, 100, 90), Count = 10, Speed = { 2, 5 }, Spread = 70,
			Direction = V3(0, 1, 0), Lifetime = { .6, 1.1 }, Size = { 1, 2.2, 3 }, Transparency = { .4, 1 }, LightEmission = 0 })
		FX.Light(V3(spot.X, gy + 1.6, spot.Z), Shared.Color("Gold"), 12, 1.6, 1.2)
		Audio.Play("TreasureReveal", spot, { Volume = .5, Pitch = .9 })
		actor(function(t)
			local rise = smooth(t / .45)
			local rattle = (t > .55 and t < 1.25) and (t - .55) or 0
			local open = smooth((t - 1.3) / .22)
			if t > .55 and t < 1.25 and not chest.Rattled then
				chest.Rattled = true
				Audio.Play("PumpkinShake", spot)
				task.delay(.35, Audio.Play, "PumpkinShake", spot)
			end
			if t >= 1.3 and not opened then
				opened = true
				Audio.Play("Cackle", spot)
				Audio.Play("ChainRattle", spot, { Pitch = 1.3 })
				local mouth = V3(spot.X, gy + 1.5, spot.Z)
				FX.Burst(mouth, { Texture = FX.Textures.Smoke, Color = RGB(110, 60, 160), Count = 12, Speed = { 2, 6 }, Spread = 50,
					Direction = V3(0, 1, 0), Lifetime = { .7, 1.3 }, Size = { 1, 2.5, 3.5 }, Transparency = { .35, 1 }, LightEmission = .2 })
				local nb = (Shared.Low() and not isMe) and 3 or 7
				for k = 1, nb do
					local bat = AModels.Bat(folder)
					bat:SetScale(rng:NextNumber(.7, 1))
					-- out of the chest, up and away from the house (toward the lane)
					local a = rng:NextNumber(.15, .85) * math.pi
					local dir = V3(math.cos(a), rng:NextNumber(.7, 1.5), math.sin(a) * h.Lay.Facing.Z).Unit
					local speed = rng:NextNumber(9, 14)
					local life = rng:NextNumber(1.3, 1.9)
					local flap = rng:NextNumber(0, 6)
					actor(function(bt)
						local p = mouth + dir * speed * bt + V3(0, math.sin(bt * 6 + k) * .4, 0)
						bat:Update(Ambient.FlyCF(p, dir, .7), Ambient.Models.BatPose(flap + bt * 15))
						bat:SetFade(smooth((bt - (life - .5)) / .5))
						if bt > life then
							bat:Destroy()
							return false
						end
						return true
					end)
				end
				if isMe then
					candyHop(mouth, target, .1, .45, function()
						popupCandy(target() + V3(0, 2, 0), candy, mouth)
					end)
				end
			end
			local sink = smooth((t - 3.2) / .5)
			chest:Update(base * at(0, -1.6 * (1 - rise) - 1.5 * sink, 0), Models.ChestPose(open, rattle))
			chest:SetFade(sink)
			if t > 3.8 then
				chest:Destroy()
				return false
			end
			return true
		end)
	end

	local function curse(h, d, pl: Player?, isMe: boolean)
		local target = knockerPos(h, pl)
		local pos = target()
		local purple = Shared.Color("Purple")
		FX.Smoke(pos, purple, 6, 2.2)
		FX.Burst(pos + V3(0, 1, 0), { Color = RGB(190, 110, 255), Color2 = RGB(60, 20, 90), Count = 26, Speed = { 4, 10 }, Lifetime = { .6, 1.3 },
			Size = { .4, .7, 0 }, Acceleration = V3(0, 3, 0) })
		FX.Ring(V3(pos.X, groundY(pos, Layout.FloorY) + .1, pos.Z), purple, 9, .8)
		FX.Light(pos + V3(0, 2, 0), purple, 16, 2, 1.4)
		Audio.Play("Whisper", pos)
		Audio.Play("Cackle", h.Lay.Door + V3(0, 3, 0), { Delay = .15 })
		if isMe then
			FX.Flash(RGB(120, 40, 200), .2, .5)
			local row = nil
			for _, r in ipairs(Config.TrickOrTreat.Tricks) do
				if r.Id == "CurseBoost" then
					row = r
				end
			end
			task.delay(.5, function()
				FX.Popup(target() + V3(0, 3.4, 0), L("CURSED", "ПРОКЛЯТИЕ") .. " +" .. tostring(row and row.Curse or 18), RGB(200, 120, 255), true)
			end)
			task.delay(1.1, function()
				popupCandy(target() + V3(0, 2, 0), tonumber(d.Candy) or 0, h.Lay.Door + V3(0, 3, 0))
			end)
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- the porch skeleton (Strike target kind "MiniBoss")
	-------------------------------------------------------------------------------------------------------------
	local skeletons = {} -- TargetId (or the part) -> state
	local ended = {} -- TargetIds whose skeleton already left (never resurrect a lingering part)
	local function keyOf(part: Instance): any
		local id = part:GetAttribute("TargetId")
		return id ~= nil and id or part
	end
	local bossOwner = {} -- TargetId -> UserId (from HouseBoss Spawn)
	local function startSkeleton(part: BasePart)
		local key = keyOf(part)
		if skeletons[key] then
			return
		end
		local h = houses[tonumber(part:GetAttribute("HouseIndex")) or 0] or houseAt(part.CFrame.Position, 14)
		local rig = Models.Skeleton(folder)
		rig:SetFade(1)
		local gy = groundY(part.CFrame.Position, part.CFrame.Position.Y - part.Size.Y / 2)
		local facing = part:GetAttribute("Facing")
		local st = { Part = part, Rig = rig, House = h, T = 0, Hit = -10, HP = part:GetAttribute("HP"), Ground = gy,
			Yaw = type(facing) == "number" and facing or math.pi, Dead = false, Key = key }
		skeletons[key] = st
		Audio.Play("SkeletonRattle", part.CFrame.Position)
		Audio.Play("Cackle", part.CFrame.Position, { Pitch = .8, Delay = .1 })
	end
	-- hit feedback: the target's HP attribute dropped (polled each frame; robust to attribute batching)
	local function pollHit(st)
		local part = st.Part
		local hp = part:GetAttribute("HP")
		if type(hp) == "number" and type(st.HP) == "number" and hp < st.HP then
			st.Hit = os.clock()
			FX.Debris(part.CFrame.Position + V3(0, .5, 0), C.Bone, Enum.Material.SmoothPlastic, 4, 14, { MaxSize = .35, Floor = st.Ground })
			FX.Burst(part.CFrame.Position + V3(0, 1, 0), { Color = C.Eye, Count = 6, Speed = { 3, 6 }, Lifetime = { .25, .5 }, Size = { .25, .4, 0 } })
			Audio.Play("SkeletonRattle", part.CFrame.Position, { Volume = .7 })
		end
		st.HP = hp
	end
	local function endSkeleton(st, how: string, data: any)
		if st.Dead then
			return
		end
		st.Dead = true
		skeletons[st.Key] = nil
		ended[st.Key] = true
		local rig = st.Rig
		local root = rig.Root
		local pos = root.Position + V3(0, 2, 0)
		if how == "Down" then
			FX.Debris(pos, C.Bone, Enum.Material.SmoothPlastic, 16, 30, { MaxSize = .6, Floor = st.Ground })
			FX.Burst(pos, { Color = C.Eye, Color2 = C.Bone, Count = 24, Speed = { 6, 14 }, Lifetime = { .4, .9 }, Size = { .4, .8, 0 } })
			FX.Smoke(pos, RGB(140, 255, 140), 4, 1.2)
			Audio.Play("SkeletonBreak", pos)
			rig:Destroy()
			local uid = data and data.UserId
			if uid == player.UserId then
				local amount = tonumber(data.Candy) or 0
				local me = function()
					local r = rootOf(player)
					return r and (r.CFrame.Position + V3(0, .6, 0)) or pos
				end
				for k = 1, 4 do
					candyHop(pos, me, (k - 1) * .06, .5, k == 1 and function()
						popupCandy(me() + V3(0, 2, 0), amount, pos)
					end or nil)
				end
			end
		else
			-- escape: back through the door (or crumble into the ground when the house is unknown)
			local h = st.House
			local from = root
			local door = h and doorFrame(h, h.Lay.Door.Y + .5) * ang(0, 180, 0) * at(0, 0, -1.5) or nil
			if h then
				openDoor(h)
				scheduleClose(h, 1.4)
			end
			actor(function(t)
				local k = smooth(t / .6)
				if door then
					local p = from.Position:Lerp(door.Position, k) + V3(0, math.sin(k * math.pi) * 2.5, 0)
					rig:Update(CFrame.new(p) * (door - door.Position), Models.SkeletonPose(t, "Leap"))
				else
					rig:Update(from * at(0, -2.5 * k, 0), Models.SkeletonPose(t, "Idle"))
				end
				rig:SetFade(smooth((t - .3) / .35))
				if t > .7 then
					rig:Destroy()
					return false
				end
				return true
			end)
			Audio.Play("Cackle", root.Position, { Pitch = .9 })
		end
	end
	local function stepSkeletons(dt: number, now: number)
		for _, st in pairs(skeletons) do
			local part = st.Part
			st.T += dt
			local reason = part.Parent and part:GetAttribute("EndReason")
			if reason ~= nil then
				-- Strike.Remove replicates the reason before the part goes: shatter on "Broke", slip away otherwise
				endSkeleton(st, reason == "Broke" and "Down" or "Escape", { UserId = 0 })
			elseif not part.Parent then
				-- removed without a reason (streamed out): slip away after a short grace
				st.Gone = (st.Gone or 0) + dt
				if st.Gone > .6 then
					endSkeleton(st, "Escape")
				end
			else
				pollHit(st)
				local h = st.House
				local target = CFrame.new(part.CFrame.Position.X, st.Ground, part.CFrame.Position.Z)
				-- face the nearest player
				local best, bd = nil, 30
				for _, pl in ipairs(Players:GetPlayers()) do
					local r = rootOf(pl)
					if r then
						local dd = (r.CFrame.Position - part.CFrame.Position).Magnitude
						if dd < bd then
							best, bd = r, dd
						end
					end
				end
				local want = st.Yaw
				if best then
					local to = best.CFrame.Position - part.CFrame.Position
					want = math.atan2(-to.X, -to.Z)
				end
				local dy = (want - st.Yaw + math.pi) % (2 * math.pi) - math.pi
				st.Yaw += dy * math.min(1, dt * 4)
				local cf = target * CFrame.Angles(0, st.Yaw, 0)
				if st.T < .55 and h then
					-- leap out of the doorway
					local k = smooth(st.T / .55)
					local from = doorFrame(h, h.Lay.Door.Y + .5) * at(0, 0, 1.5)
					local p = from.Position:Lerp(cf.Position, k) + V3(0, math.sin(k * math.pi) * 3, 0)
					st.Rig:Update(CFrame.new(p) * (cf - cf.Position), Models.SkeletonPose(st.T, "Leap"))
					st.Rig:SetFade(1 - smooth(st.T / .2))
					if st.T + dt >= .55 then
						FX.Ring(V3(cf.Position.X, st.Ground + .1, cf.Position.Z), C.Eye, 5, .5)
						Audio.Play("BossStep", cf.Position, { Volume = .5, Pitch = 1.6 })
					end
				else
					st.Rig:SetFade(0)
					local hitT = now - st.Hit
					if hitT < .35 then
						st.Rig:Update(cf, Models.SkeletonPose(hitT / .35, "Hit"))
					else
						local taunt = (math.floor(st.T / 4) % 3 == 2) and "Taunt" or "Idle"
						st.Rig:Update(cf, Models.SkeletonPose(st.T, taunt))
					end
				end
			end
		end
	end
	-- Strike sets every attribute before parenting the target part, so Kind is there on arrival; a 1 Hz rescan from the
	-- Heartbeat also catches parts that streamed in late or were missed
	local targetsFolder = nil
	local function consider(part: Instance)
		if part:IsA("BasePart") and part:GetAttribute("Kind") == "MiniBoss" and not skeletons[keyOf(part)] and not ended[keyOf(part)]
			and part:GetAttribute("EndReason") == nil then
			startSkeleton(part)
		end
	end
	local function watchTargets()
		local live = workspace:WaitForChild("HalloweenLive", 60)
		local targets = live and live:WaitForChild("Targets", 60)
		if not targets then
			return
		end
		targetsFolder = targets
		targets.ChildAdded:Connect(consider)
		for _, c in ipairs(targets:GetChildren()) do
			consider(c)
		end
	end
	local rescanAt = 0
	local function rescanTargets(now: number)
		if now - rescanAt < 1 then
			return
		end
		rescanAt = now
		if not targetsFolder or not targetsFolder.Parent then
			local live = workspace:FindFirstChild("HalloweenLive")
			targetsFolder = live and live:FindFirstChild("Targets")
		end
		if targetsFolder then
			for _, c in ipairs(targetsFolder:GetChildren()) do
				consider(c)
			end
		end
	end
	task.spawn(watchTargets)

	-------------------------------------------------------------------------------------------------------------
	-- signals
	-------------------------------------------------------------------------------------------------------------
	local TRICKS = { Jumpscare = jumpscare, Ghosts = ghosts, Fog = fog, FakeChest = fakeChest, CurseBoost = curse }
	local function onHouse(d)
		local i = tonumber(d.Index)
		local h = i and houses[i]
		if not h then
			return
		end
		local pl = Players:GetPlayerByUserId(tonumber(d.UserId) or 0)
		local isMe = pl == player
		if isMe then
			-- mark knocked at once (the View follows)
			local view = State.View
			if type(view) == "table" and type(view.Houses) == "table" and type(view.Houses.Knocked) == "table" then
				view.Houses.Knocked[tostring(i)] = true
				if d.Day then
					view.Houses.Day = d.Day
				end
			end
			updateKnockedLook()
		end
		local doorPos = h.Lay.Door + V3(0, 3.2, 0)
		if (doorPos - camPos()).Magnitude > 220 then
			return
		end
		Audio.Play("DoorKnock", doorPos)
		local trickColor = { Jumpscare = RGB(140, 255, 120), Ghosts = RGB(150, 210, 255), Fog = RGB(170, 160, 220), FakeChest = RGB(255, 200, 70),
			CurseBoost = RGB(170, 80, 255), MiniBoss = RGB(255, 70, 60) }
		local isTreat = d.Kind == "Treat"
		task.delay(.6, function()
			openDoor(h)
			scheduleClose(h, d.Trick == "MiniBoss" and 3.2 or 5.6)
			vestibule(h, isTreat and RGB(255, 160, 70) or (trickColor[d.Trick] or RGB(140, 255, 120)), 5.8)
			Bus.Fire("LanternFlare", { Position = h.Lay.Door + V3(0, 4, 2), Radius = 9, Strength = isTreat and .8 or 1.4, Seconds = 1.4 })
			FX.Burst(h.Lay.Door + V3(0, 1.2, .5), { Texture = FX.Textures.Smoke, Color = RGB(60, 40, 80), Count = 6, Speed = { 1, 3 }, Spread = 60,
				Direction = h.Lay.Facing, Lifetime = { .8, 1.4 }, Size = { 1, 2.5, 3 }, Transparency = { .5, 1 }, LightEmission = 0 })
		end)
		task.delay(1.15, function()
			FX.Popup(doorPos + V3(0, 3.2, 1.5), isTreat and L("TREAT!", "СЛАДОСТЬ!") or L("TRICK!", "ГАДОСТЬ!"),
				isTreat and Shared.Color("Pumpkin") or RGB(190, 110, 255), true)
			if isTreat then
				treat(h, d, pl, isMe)
			elseif d.Trick == "MiniBoss" then
				Audio.Play("SkeletonRattle", doorPos)
				Audio.Play("Cackle", doorPos, { Pitch = .8, Delay = .25 })
				if isMe then
					task.delay(.9, function()
						popupCandy(doorPos + V3(0, 1.5, 3), tonumber(d.Candy) or 0, doorPos)
						FX.Popup(doorPos + V3(0, 4.5, 3), L("BREAK THE SKELETON!", "РАЗБЕЙ СКЕЛЕТ!"), RGB(140, 255, 120), false)
					end)
				end
			else
				local fn = TRICKS[d.Trick]
				if fn then
					fn(h, d, pl, isMe)
					if isMe and d.Trick ~= "CurseBoost" and d.Trick ~= "FakeChest" then
						task.delay(d.Trick == "Jumpscare" and .9 or 1.6, function()
							popupCandy((rootOf(player) and rootOf(player).CFrame.Position or doorPos) + V3(0, 2.6, 0), tonumber(d.Candy) or 0, doorPos)
						end)
					end
				end
			end
		end)
	end
	Bus.On("Signal", function(sig)
		if type(sig) ~= "table" or type(sig.Data) ~= "table" then
			return
		end
		local d = sig.Data
		if sig.Kind == "House" then
			onHouse(d)
		elseif sig.Kind == "HouseBoss" then
			if d.Kind == "Spawn" and d.TargetId then
				bossOwner[d.TargetId] = d.UserId
			elseif d.Kind == "Down" or d.Kind == "Escape" then
				local h = houses[tonumber(d.Index) or 0]
				local handled = false
				for _, st in pairs(skeletons) do
					local tid = st.Part:GetAttribute("TargetId")
					local owner = tid ~= nil and bossOwner[tid] or nil
					if (d.TargetId ~= nil and tid == d.TargetId) or (owner == d.UserId) or (h and st.House == h and owner == nil) then
						endSkeleton(st, d.Kind, d)
						handled = true
						break
					end
				end
				if not handled and d.Kind == "Down" and d.UserId == player.UserId and (tonumber(d.Candy) or 0) > 0 then
					local r = rootOf(player)
					popupCandy((r and r.CFrame.Position or Layout.Houses[1].Porch) + V3(0, 2.6, 0), tonumber(d.Candy) or 0, nil)
				end
			end
		end
	end)

	-------------------------------------------------------------------------------------------------------------
	-- main loop
	-------------------------------------------------------------------------------------------------------------
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		dt = math.min(dt, .1)
		for _, h in ipairs(houses) do
			if h.CloseAt and now >= h.CloseAt and not (h.Anim and h.Anim.To == 0) then
				h.CloseAt = nil
				swing(h, 0, .55, "In")
				h.Slam = true
			end
			local a = h.Anim
			if a then
				local k = math.clamp((now - a.T0) / a.Dur, 0, 1)
				local e
				if a.Style == "Back" then
					local c1, c3 = 1.2, 2.2
					e = 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
				else
					e = k * k
				end
				h.Angle = a.From + (a.To - a.From) * e
				if k >= 1 then
					h.Angle = a.To
					h.Anim = nil
					if a.To == 0 and h.Slam then
						h.Slam = false
						Audio.Play("DoorSlam", h.Lay.Door + V3(0, 3, 0), { Volume = .7 })
						FX.Burst(h.Lay.Door + V3(0, .8, .6), { Texture = FX.Textures.Smoke, Color = RGB(90, 80, 100), Count = 5, Speed = { 1, 3 }, Spread = 80,
							Direction = V3(0, 1, 0), Lifetime = { .5, .9 }, Size = { .6, 1.4, 2 }, Transparency = { .5, 1 }, LightEmission = 0 })
					end
				end
				applyDoor(h)
			end
		end
		for i = #actors, 1, -1 do
			local a = actors[i]
			local ok, alive = pcall(a.Fn, now - a.T0, dt)
			if not ok then
				warn("HouseFX effect failed: " .. tostring(alive))
				table.remove(actors, i)
			elseif not alive then
				table.remove(actors, i)
			end
		end
		local ok, err = pcall(function()
			rescanTargets(now)
			stepSkeletons(dt, now)
		end)
		if not ok then
			warn("HouseFX skeleton: " .. tostring(err))
		end
	end)
end

return HouseFX
