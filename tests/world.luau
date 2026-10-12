--!nocheck
--!nolint
-- World.Spec (pure part specs) and World.Builder (real Instances via Lune's roblox library).
-- lune run tests/world.luau
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
local Spec = L.Require("ReplicatedStorage.World.Spec")
local Builder = L.Require("ReplicatedStorage.World.Builder")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function nearV(a, b, msg)
	if (a - b).Magnitude > 1e-4 then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function nearCF(a, b, msg)
	local x, y = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(x[i] - y[i]) > 1e-4 then
			error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
		end
	end
end

local GOLD = Color3.fromRGB(255, 200, 60)
local WHITE = Color3.new(1, 1, 1)

-- A small stand: base, column, neon lamp with a light, a sign, two beams' attachments.
local function stand()
	local S = Spec
	local column = S.Cylinder("Column", 6, 1.2, CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.pi / 2), S.Metal(WHITE))
	local lamp = S.Ball("Lamp", 1.6, CFrame.new(0, 7.8, 0), S.Neon(GOLD, {
		Children = { S.PointLight({ Range = 14, Brightness = 2, Color = GOLD }), S.Attachment("LampA", CFrame.new(0, 0.8, 0)) },
	}))
	local base = S.Block("Base", Vector3.new(6, 1, 6), CFrame.new(0, 0.5, 0), S.Mat("Marble", WHITE, {
		Tags = { "StandBase" }, Attributes = { Slot = 1 },
		Children = { S.Attachment("BaseA", CFrame.new(0, 0.5, 0)), S.Beam("Glow", "BaseA", "LampA", { Width0 = 0.3, Width1 = 0.1 }), S.Label("Front", "BEST FIND") },
	}))
	local ramp = S.Wedge("Ramp", Vector3.new(6, 1, 2), CFrame.new(0, 0.5, -4))
	local posts = S.Ring({ S.Block("Post", Vector3.new(0.5, 2, 0.5), CFrame.new(0, 1, 0)) }, 4, 4)
	return S.Concat({ base, column, lamp, ramp }, posts)
end

local function serialize(specs)
	local out = {}
	for _, s in ipairs(specs) do
		table.insert(out, table.concat({ s.Class, tostring(s.Shape), s.Name, tostring(s.Size), tostring(s.CFrame), tostring(s.Color), s.Material }, "|"))
	end
	return table.concat(out, "\n")
end

-- SPEC ------------------------------------------------------------------------------------------------
test("Spec part constructors and defaults", function()
	local b = Spec.Block("B", Vector3.new(2, 3, 4))
	eq(b.Class, "Part")
	eq(b.Shape, "Block")
	eq(b.Material, "SmoothPlastic")
	eq(b.Transparency, 0)
	eq(b.CanCollide, false)
	nearCF(b.CFrame, CFrame.identity)
	local ball = Spec.Ball("Ball", 3)
	eq(ball.Shape, "Ball")
	nearV(ball.Size, Vector3.new(3, 3, 3))
	local cyl = Spec.Cylinder("C", 10, 2)
	eq(cyl.Shape, "Cylinder")
	nearV(cyl.Size, Vector3.new(10, 2, 2), "length along X")
	eq(Spec.Wedge("W", Vector3.one).Class, "WedgePart")
	eq(Spec.CornerWedge("CW", Vector3.one).Class, "CornerWedgePart")
	eq(Spec.Truss("T", Vector3.new(2, 10, 2)).Class, "TrussPart")
	eq(Spec.Truss("T", Vector3.new(2, 10, 2)).Shape, nil, "only Part has a Shape")
	local neon = Spec.Block("N", Vector3.one, nil, Spec.Neon(GOLD))
	eq(neon.Material, "Neon")
	eq(neon.CastShadow, false)
	local glass = Spec.Block("G", Vector3.one, nil, Spec.Glass(WHITE))
	truthy(glass.Transparency > 0)
end)

test("Spec.Merge concatenates Children / Tags and merges Attributes", function()
	local m = Spec.Merge({ Tags = { "A" }, Attributes = { X = 1 }, Children = { 1 } }, { Tags = { "B" }, Attributes = { Y = 2 }, Children = { 2 } })
	eq(#m.Tags, 2)
	eq(m.Attributes.X, 1)
	eq(m.Attributes.Y, 2)
	eq(#m.Children, 2)
end)

test("Spec transforms return new lists", function()
	local src = { Spec.Block("A", Vector3.one, CFrame.new(1, 0, 0)) }
	local moved = Spec.Offset(src, Vector3.new(0, 5, 0))
	nearV(moved[1].CFrame.Position, Vector3.new(1, 5, 0))
	nearV(src[1].CFrame.Position, Vector3.new(1, 0, 0), "input untouched")
	local turned = Spec.Rotate(src, 90)
	nearV(turned[1].CFrame.Position, Vector3.new(0, 0, -1), "yaw 90 turns +X to -Z")
	local single = Spec.Offset(Spec.Block("S", Vector3.one), CFrame.new(0, 0, 2))
	eq(#single, 1, "a single spec is accepted")
end)

test("Spec.MirrorX mirrors boxes exactly and twice is identity", function()
	local cf = CFrame.new(3, 1, 2) * CFrame.Angles(0.3, 0.7, -0.2)
	local box = Spec.Block("Box", Vector3.new(2, 1, 4), cf)
	local m = Spec.MirrorX({ box })[1]
	nearV(m.CFrame.Position, Vector3.new(-3, 1, 2))
	-- every corner of the mirrored box is the mirror of a corner of the original
	local function corners(s)
		local out = {}
		local h = s.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					table.insert(out, s.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
				end
			end
		end
		return out
	end
	for _, p in ipairs(corners(m)) do
		local found = false
		for _, q in ipairs(corners(box)) do
			if (p - Vector3.new(-q.X, q.Y, q.Z)).Magnitude < 1e-4 then
				found = true
			end
		end
		truthy(found, "corner " .. tostring(p))
	end
	local back = Spec.MirrorX(Spec.MirrorX({ box }))[1]
	nearCF(back.CFrame, cf, "mirror twice")
end)

test("Spec.MirrorX keeps a corner wedge's peak at the mirrored corner", function()
	local cf = CFrame.new(5, 2, -3) * CFrame.Angles(0, 0.4, 0)
	local w = Spec.CornerWedge("CW", Vector3.new(2, 3, 5), cf)
	local function peak(s)
		return s.CFrame * Vector3.new(s.Size.X / 2, s.Size.Y / 2, -s.Size.Z / 2)
	end
	local p = peak(w)
	local m = Spec.MirrorX(w)[1]
	nearV(peak(m), Vector3.new(-p.X, p.Y, p.Z))
	nearV(m.Size, Vector3.new(5, 3, 2), "X / Z sizes swap")
	local back = Spec.MirrorX(m)[1]
	nearCF(back.CFrame, cf)
	nearV(back.Size, w.Size)
end)

test("Spec.MirrorX mirrors children: attachments, lights and sign faces", function()
	local board = Spec.Block("Board", Vector3.new(1, 4, 6), CFrame.new(5, 3, 0), {
		Children = {
			Spec.Attachment("Lamp", CFrame.new(2, 0, 0)),
			Spec.Label("Right", "SHOP"),
			Spec.SpotLight({ Face = "Right" }),
			Spec.Emitter({ EmissionDirection = Enum.NormalId.Left }),
			Spec.Attachment("Pos", nil, { Position = Vector3.new(0.5, 1, -2) }),
		},
	})
	local mirrored = Spec.MirrorX(board)[1]
	eq(board.Children[2].Face, "Right", "input untouched")
	local function world(spec, child)
		return spec.CFrame * child.CFrame.Position
	end
	nearV(world(mirrored, mirrored.Children[1]), Vector3.new(-7, 3, 0), "the lamp sits outside the mirrored board")
	eq(mirrored.Children[2].Face, "Left", "the sign faces outwards")
	eq(mirrored.Children[3].Face, "Left", "a spot light too")
	eq(mirrored.Children[4].EmissionDirection, "Right", "an EnumItem face is mirrored by name")
	nearV(mirrored.CFrame * mirrored.Children[5].Position, Vector3.new(-5.5, 4, -2), "a Position is mirrored")
	-- the sign's outward normal mirrors too: +X on the right board, -X on the left one
	local normal = { Right = Vector3.new(1, 0, 0), Left = Vector3.new(-1, 0, 0) }
	nearV(mirrored.CFrame:VectorToWorldSpace(normal[mirrored.Children[2].Face]), Vector3.new(-1, 0, 0))
	-- built: the lamp attachment's world position is the mirror of the original's
	local model = Builder.Build(Spec.Concat(board, Spec.MirrorX(board)), CFrame.identity)
	local parts = {}
	for _, part in ipairs(model:GetChildren()) do
		table.insert(parts, part)
	end
	table.sort(parts, function(a, b) return a.CFrame.Position.X < b.CFrame.Position.X end)
	local left, right = parts[1], parts[2]
	local function lamp(part)
		return part.CFrame * part:FindFirstChild("Lamp").CFrame.Position
	end
	nearV(lamp(right), Vector3.new(7, 3, 0))
	nearV(lamp(left), Vector3.new(-7, 3, 0))
	eq(left:FindFirstChild("Label").Face, Enum.NormalId.Left)
	-- a corner wedge's quarter turn is undone for its children
	local wedge = Spec.CornerWedge("CW", Vector3.new(2, 3, 5), CFrame.new(4, 0, 1) * CFrame.Angles(0, 0.3, 0), {
		Children = { Spec.Attachment("Tip", CFrame.new(0.7, 1.2, -2)), Spec.Label("Right", "X") },
	})
	local mw = Spec.MirrorX(wedge)[1]
	local p = wedge.CFrame * wedge.Children[1].CFrame.Position
	nearV(mw.CFrame * mw.Children[1].CFrame.Position, Vector3.new(-p.X, p.Y, p.Z), "corner wedge child")
	local n = wedge.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0))
	local faces = { Right = Vector3.new(1, 0, 0), Left = Vector3.new(-1, 0, 0), Front = Vector3.new(0, 0, -1), Back = Vector3.new(0, 0, 1) }
	nearV(mw.CFrame:VectorToWorldSpace(faces[mw.Children[2].Face]), Vector3.new(-n.X, n.Y, n.Z), "corner wedge sign")
	local back = Spec.MirrorX(mw)[1]
	nearCF(back.Children[1].CFrame, wedge.Children[1].CFrame, "mirror twice")
	eq(back.Children[2].Face, "Right")
end)

test("Spec Array / Ring / Arc", function()
	local post = Spec.Block("Post", Vector3.one)
	local row = Spec.Array(post, 4, Vector3.new(2, 0, 0))
	eq(#row, 4)
	nearV(row[4].CFrame.Position, Vector3.new(6, 0, 0))
	eq(row[1].Name, "Post_1")
	eq(row[4].Name, "Post_4")
	local stairs = Spec.Array(post, 3, CFrame.new(0, 1, -1))
	nearV(stairs[3].CFrame.Position, Vector3.new(0, 2, -2))
	local ring = Spec.Ring(post, 6, 10)
	eq(#ring, 6)
	for _, s in ipairs(ring) do
		truthy(math.abs(s.CFrame.Position.Magnitude - 10) < 1e-4, "on the radius")
	end
	nearV(ring[1].CFrame.Position, Vector3.new(0, 0, -10), "first copy on -Z")
	truthy((ring[1].CFrame.Position - ring[2].CFrame.Position).Magnitude > 9.9, "evenly spread (60 degrees)")
	local arc = Spec.Arc(post, 3, 5, -90, 90)
	nearV(arc[1].CFrame.Position, Vector3.new(5, 0, 0), "-90 degrees")
	nearV(arc[3].CFrame.Position, Vector3.new(-5, 0, 0), "+90 degrees")
	local out = Spec.Ring(post, 4, 3)[1].CFrame.LookVector
	nearV(out, Vector3.new(0, 0, -1), "Face Out: -Z points away from the centre")
	local inward = Spec.Ring(post, 4, 3, { Face = "In" })[1].CFrame.LookVector
	nearV(inward, Vector3.new(0, 0, 1), "Face In")
	local fixed = Spec.Ring(post, 4, 3, { Face = "Fixed", Start = 90 })[1].CFrame
	nearV(fixed.LookVector, Vector3.new(0, 0, -1), "Face Fixed keeps the rotation")
	nearV(fixed.Position, Vector3.new(-3, 0, 0))
	eq(#Spec.Arc(post, 1, 5, 0, 90), 1, "one copy sits in the middle")
end)

test("Spec Bounds / PartCount / Count / Validate", function()
	local specs = stand()
	eq(Spec.PartCount(specs), 8)
	local counts = Spec.Count(specs)
	eq(counts.Parts, 8)
	eq(counts.Lights, 1)
	eq(counts.Beams, 1)
	eq(counts.Attachments, 2)
	eq(counts.Guis, 1)
	local b = Spec.Bounds(specs)
	nearV(b.Min, Vector3.new(-4.25, 0, -5), "min")
	nearV(b.Max, Vector3.new(4.25, 8.6, 4.25), "max")
	nearV(b.Size, b.Max - b.Min)
	eq(Spec.Bounds({}), nil)
	local ok, problems = Spec.Validate(specs)
	truthy(ok, table.concat(problems, "; "))
	local bad = { Spec.Block("Zero", Vector3.new(0, 1, 1)), Spec.With(Spec.Block("X", Vector3.one), { Glow = true }), { Class = "MeshPart", Size = Vector3.one, CFrame = CFrame.identity } }
	local ok2, list = Spec.Validate(bad)
	eq(ok2, false)
	eq(#list, 3, table.concat(list, "; "))
end)

test("Spec layouts are deterministic", function()
	eq(serialize(stand()), serialize(stand()))
	local a, b, c = Spec.Rng(42), Spec.Rng(42), Spec.Rng(7)
	local sameA, sameB, other = {}, {}, {}
	for i = 1, 20 do
		sameA[i], sameB[i], other[i] = a.Number(), b.Number(), c.Number()
	end
	eq(table.concat(sameA, ","), table.concat(sameB, ","), "same seed, same sequence")
	truthy(table.concat(sameA, ",") ~= table.concat(other, ","), "another seed differs")
	local r = Spec.Rng(1)
	for _ = 1, 200 do
		local n = r.Integer(3, 5)
		truthy(n >= 3 and n <= 5, "Integer in range")
	end
	eq(Spec.Rng(9).Pick({ "a" }), "a")
end)

-- BUILDER ----------------------------------------------------------------------------------------------
test("Builder builds detached, parents once, sets attributes", function()
	local folder = roblox.Instance.new("Folder")
	local anchor = CFrame.new(100, 0, 50) * CFrame.Angles(0, math.pi / 2, 0)
	local specs = stand()
	local model = Builder.Build(specs, anchor, {
		Name = "Stand", Parent = folder, BuilderId = "Showcase", LayoutVersion = 3, StreamingMode = "Atomic",
		FXManaged = true, Lod = { Near = 60, Far = 150 }, Attributes = { Owner = 7 },
	})
	eq(model.Parent, folder)
	eq(model.Name, "Stand")
	eq(model:GetAttribute("BuilderId"), "Showcase")
	eq(model:GetAttribute("LayoutVersion"), 3)
	eq(model:GetAttribute("PartCount"), 8)
	eq(model:GetAttribute("FXManaged"), true)
	eq(model:GetAttribute("Owner"), 7)
	eq(model:GetAttribute("LodNear"), 60)
	truthy(model:HasTag("DOGROTS_Lod"), "Lod tag")
	eq(model.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
	nearCF(model.WorldPivot, anchor)
	eq(#model:GetChildren(), 8)
	local base = model:FindFirstChild("Base")
	nearCF(base.CFrame, anchor * CFrame.new(0, 0.5, 0), "anchor * spec CFrame")
	eq(base.Material, Enum.Material.Marble)
	eq(base.Anchored, true)
	eq(base.CanCollide, false)
	eq(base.CanQuery, false)
	eq(base.CanTouch, false)
	truthy(base:HasTag("StandBase"))
	eq(base:GetAttribute("Slot"), 1)
	eq(base.CastShadow, true, "a 6 stud base casts a shadow")
	eq(base.TopSurface, Enum.SurfaceType.Smooth)
	local column = model:FindFirstChild("Column")
	eq(column.Shape, Enum.PartType.Cylinder)
	eq(column.Material, Enum.Material.Metal)
	local lamp = model:FindFirstChild("Lamp")
	eq(lamp.Shape, Enum.PartType.Ball)
	eq(lamp.CastShadow, false, "neon never casts a shadow")
	local light = lamp:FindFirstChildOfClass("PointLight")
	eq(light.Range, 14)
	eq(light.Shadows, false)
	local beam = base:FindFirstChild("Glow")
	eq(beam.Attachment0, base:FindFirstChild("BaseA"), "beam linked to attachments by name")
	eq(beam.Attachment1, lamp:FindFirstChild("LampA"))
	local gui = base:FindFirstChild("Label")
	eq(gui.Face, Enum.NormalId.Front, "enum by name")
	eq(gui:FindFirstChild("Text").Text, "BEST FIND")
	eq(model:FindFirstChild("Ramp").ClassName, "WedgePart")
	eq(model:FindFirstChild("Post_1").CastShadow, false, "small parts skip shadows")
end)

test("Builder spec options: collisions, Props, unknown material, bad streaming mode", function()
	local specs = {
		Spec.Block("Floor", Vector3.new(10, 1, 10), nil, { CanCollide = true, CanQuery = true, CastShadow = false, Props = { Massless = true } }),
		Spec.Block("Odd", Vector3.one, nil, { Material = "NotAMaterial" }),
	}
	local model = Builder.Build(specs, nil, { BuilderId = "Test", StreamingMode = "NoSuchMode" })
	eq(model.Parent, nil, "no Parent: stays detached")
	eq(model.Name, "Test")
	local floor = model:FindFirstChild("Floor")
	eq(floor.CanCollide, true)
	eq(floor.CanQuery, true)
	eq(floor.CastShadow, false)
	eq(floor.Massless, true)
	eq(model:FindFirstChild("Odd").Material, Enum.Material.SmoothPlastic, "unknown material falls back")
	eq(model.ModelStreamingMode, Enum.ModelStreamingMode.Default, "a bad mode is ignored")
end)

test("Builder links each copy's beam to its own attachments", function()
	local post = Spec.Block("Post", Vector3.new(1, 6, 1), CFrame.new(0, 3, 0), {
		Children = { Spec.Attachment("Low", CFrame.new(0, -3, 0)), Spec.Attachment("High", CFrame.new(0, 3, 0)), Spec.Beam("Glow", "Low", "High") },
	})
	for label, specs in pairs({ Array = Spec.Array({ post }, 3, Vector3.new(10, 0, 0)), Ring = Spec.Ring({ post }, 4, 8), Mirror = Spec.Concat(Spec.Offset(post, Vector3.new(4, 0, 0)), Spec.MirrorX(Spec.Offset(post, Vector3.new(4, 0, 0)))) }) do
		local model = Builder.Build(specs, CFrame.identity)
		for _, part in ipairs(model:GetChildren()) do
			local beam = part:FindFirstChild("Glow")
			eq(beam.Attachment0.Parent, part, label .. " " .. part.Name .. " Attachment0")
			eq(beam.Attachment1.Parent, part, label .. " " .. part.Name .. " Attachment1")
		end
	end
	-- a beam may still reach another part's attachment by a unique name
	local a = Spec.Block("A", Vector3.one, nil, { Children = { Spec.Attachment("FromA"), Spec.Beam("Link", "FromA", "ToB") } })
	local b = Spec.Block("B", Vector3.one, CFrame.new(0, 5, 0), { Children = { Spec.Attachment("ToB") } })
	local model = Builder.Build({ a, b }, nil)
	local link = model:FindFirstChild("A"):FindFirstChild("Link")
	eq(link.Attachment1, model:FindFirstChild("B"):FindFirstChild("ToB"))
	-- a single part built on its own links its beams too
	local single = Builder.Part(post, CFrame.identity)
	eq(single:FindFirstChild("Glow").Attachment0, single:FindFirstChild("Low"))
end)

test("Builder.Begin builds in slices and parents once", function()
	local specs = Spec.Array({ Spec.Block("Tile", Vector3.new(2, 1, 2)) }, 50, Vector3.new(3, 0, 0))
	local folder = roblox.Instance.new("Folder")
	local build = Builder.Begin(specs, CFrame.new(0, 10, 0), { Name = "Floor", Parent = folder, LayoutVersion = 2 })
	local done, model = build:Step(os.clock() - 1) -- an expired deadline: one part per step
	eq(done, false)
	eq(#model:GetChildren(), 1, "at least one part per step")
	eq(model.Parent, nil, "not parented before it is complete")
	local steps = 1
	while not done do
		done, model = build:Step(os.clock() - 1)
		steps += 1
	end
	eq(steps, 50)
	eq(model.Parent, folder, "parented on the last step")
	eq(model:GetAttribute("PartCount"), 50)
	eq(model:GetAttribute("LayoutVersion"), 2)
	nearCF(model.WorldPivot, CFrame.new(0, 10, 0))
	local again, same = build:Step()
	eq(again, true)
	eq(same, model)
	local cancelled = Builder.Begin(specs, nil, { Parent = folder })
	cancelled:Step(os.clock() - 1)
	cancelled:Cancel()
	eq(#folder:GetChildren(), 1, "a cancelled build never appears")
	eq(Builder.Build(specs, nil):GetAttribute("PartCount"), 50, "Build is Begin + one Step")
end)

test("Builder.EnsureBuilt reuses the same LayoutVersion and rebuilds otherwise", function()
	local parent = roblox.Instance.new("Folder")
	local builds = 0
	local function build()
		builds += 1
		return Builder.Build({ Spec.Block("P", Vector3.one) }, nil, { BuilderId = "Corner" })
	end
	local first, rebuilt = Builder.EnsureBuilt(parent, "Corner", 1, build)
	eq(rebuilt, true)
	eq(first.Parent, parent)
	eq(first:GetAttribute("LayoutVersion"), 1)
	local again, rebuilt2 = Builder.EnsureBuilt(parent, "Corner", 1, build)
	eq(again, first)
	eq(rebuilt2, false)
	eq(builds, 1, "same version: no rebuild")
	local newer = Builder.EnsureBuilt(parent, "Corner", 2, build)
	truthy(newer ~= first)
	eq(first.Parent, nil, "old model destroyed")
	eq(#parent:GetChildren(), 1)
	-- the build's own LayoutVersion never makes it rebuild every time
	local mismatched = 0
	local function own()
		mismatched += 1
		return Builder.Build({ Spec.Block("P", Vector3.one) }, nil, { BuilderId = "Own", LayoutVersion = 1 })
	end
	for _ = 1, 3 do
		Builder.EnsureBuilt(parent, "Own", 2, own)
	end
	eq(mismatched, 1, "built once")
	eq(parent:FindFirstChild("Own"):GetAttribute("LayoutVersion"), 2)
	-- stale duplicates are all removed
	for _ = 1, 2 do
		local dup = roblox.Instance.new("Model")
		dup.Name = "Dup"
		dup.Parent = parent
	end
	Builder.EnsureBuilt(parent, "Dup", 1, build)
	local dups = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "Dup" then dups += 1 end
	end
	eq(dups, 1, "one model of that name remains")
	local twin = roblox.Instance.new("Model")
	twin.Name = "Dup"
	twin:SetAttribute("LayoutVersion", 1)
	twin.Parent = parent
	local kept = Builder.EnsureBuilt(parent, "Dup", 1, build)
	local count = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "Dup" then count += 1 end
	end
	eq(count, 1, "a same-version duplicate is removed too")
	truthy(kept.Parent == parent)
	local stray = roblox.Instance.new("Folder")
	stray.Name = "Other"
	stray.Parent = parent
	Builder.EnsureBuilt(parent, "Other", 1, build)
	eq(stray.Parent, nil, "a non-model child of that name is replaced")
	eq(parent:FindFirstChild("Other").ClassName, "Model")
end)

print(string.format("world: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("world tests failed")
end
