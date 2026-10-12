-- Sample World.Spec layout: a showcase stand (the kind F3 builds) that uses every part class and
-- the main materials, to check tools/preview end to end:
--   lune run tools/preview/export.luau tools/preview/out/stand.json --file tools/preview/samples/stand.luau
--   node tools/preview/render.mjs tools/preview/out/stand.json tools/preview/out/stand
-- Evaluated by export.luau with Spec, Vector3, CFrame and Color3 in scope. The front is -Z.
local S = Spec
local rgb = Color3.fromRGB
local CREAM, SLATE, GOLD, WOOD = rgb(240, 236, 226), rgb(64, 70, 86), rgb(255, 196, 64), rgb(150, 104, 66)
local CYAN, PINK, STEEL = rgb(80, 230, 240), rgb(244, 140, 255), rgb(170, 180, 196)
local UP = CFrame.Angles(0, 0, math.pi / 2) -- stands a cylinder up (its axis is X)

local ground = S.Block("Lawn", Vector3.new(26, 0.4, 26), CFrame.new(0, -0.2, 0), S.Mat("Grass", rgb(98, 160, 74)))
local plinth = S.Block("Plinth", Vector3.new(12, 1, 12), CFrame.new(0, 0.5, 0), S.Mat("Marble", CREAM))
local tier = S.Block("Tier", Vector3.new(9, 1, 9), CFrame.new(0, 1.5, 0), S.Mat("Slate", SLATE))
local ramp = S.Wedge("Ramp", Vector3.new(5, 1, 2), CFrame.new(0, 1.5, -5.5), S.Mat("Marble", CREAM))
local step = S.Block("Step", Vector3.new(5, 0.2, 1.4), CFrame.new(0, 0.1, -6.7), S.Mat("Concrete", rgb(200, 196, 188)))

local pedestal = S.Cylinder("Pedestal", 3, 3, CFrame.new(0, 3.5, 0) * UP, S.Metal(GOLD, { Reflectance = 0.15 }))
local cap = S.Cylinder("PedestalCap", 0.4, 3.6, CFrame.new(0, 5.2, 0) * UP, S.Mat("DiamondPlate", STEEL))
local case = S.Block("Case", Vector3.new(4.2, 4.2, 4.2), CFrame.new(0, 7.5, 0), S.Glass(rgb(200, 235, 255), 0.65))
local aura = S.Ball("Aura", 6.4, CFrame.new(0, 7.5, 0), S.ForceField(PINK, 0.35))

-- The find on display: a bone (cylinder shaft, four ball knobs), tilted.
local BONE = S.Mat("SmoothPlastic", rgb(250, 246, 232))
local boneAt = CFrame.new(0, 7.5, 0) * CFrame.Angles(0, math.rad(30), math.rad(18))
local knobs = { S.Ball("BoneKnob", 0.9, CFrame.new(1.35, 0.3, 0), BONE), S.Ball("BoneKnob", 0.9, CFrame.new(1.35, -0.3, 0), BONE) }
local bone = S.Offset(S.Concat(S.Cylinder("BoneShaft", 2.6, 0.7, CFrame.identity, BONE), knobs, S.MirrorX(knobs)), boneAt)

-- A neon halo of twelve tiles around the case.
local halo = S.Offset(S.Ring({ S.Block("HaloTile", Vector3.new(1.1, 0.25, 0.4), CFrame.identity, S.Neon(CYAN)) }, 12, 3.4), CFrame.new(0, 5.6, 0))

-- Four wooden posts with lamps; authored for +X and mirrored to -X.
local function post(z)
	return {
		S.Cylinder("Post", 6, 0.8, CFrame.new(4.6, 5, z) * UP, S.Mat("Wood", WOOD)),
		S.Ball("Lamp", 1.2, CFrame.new(4.6, 8.4, z), S.Neon(GOLD, { Children = { S.PointLight({ Range = 16, Brightness = 1.6, Color = GOLD }) } })),
		S.CornerWedge("Fin", Vector3.new(1.4, 1.4, 1.4), CFrame.new(5.3, 1.7, z), S.Mat("Slate", SLATE)),
	}
end
local right = S.Concat(post(-4.6), post(4.6))
local posts = S.Concat(right, S.MirrorX(right))

-- A truss arch at the back with a sign.
local arch = S.Concat(
	S.Truss("ArchLeft", Vector3.new(2, 10, 2), CFrame.new(-6, 6, 6.2), S.Metal(STEEL)),
	S.Truss("ArchRight", Vector3.new(2, 10, 2), CFrame.new(6, 6, 6.2), S.Metal(STEEL)),
	S.Block("ArchBeam", Vector3.new(14, 1.4, 1.2), CFrame.new(0, 11.7, 6.2), S.Mat("DiamondPlate", STEEL)),
	S.Block("Sign", Vector3.new(8, 2, 0.4), CFrame.new(0, 9.6, 6.4), S.Mat("SmoothPlastic", SLATE)),
	S.Block("SignStripe", Vector3.new(7.2, 0.3, 0.1), CFrame.new(0, 9.1, 6.15), S.Neon(PINK))
)

return S.Concat({ ground, plinth, tier, ramp, step, pedestal, cap, case, aura }, bone, halo, posts, arch)
