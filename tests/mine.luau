--!nocheck
-- MINE ("dogs dig DOWN"): lune run tests/mine.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): MineLayout (yard frames, levels,
-- worksites, Contains, carving maths, masks, dog placement by layer), MineStructures (headframe
-- inside its reserved zone, shell never inside a chamber or the shaft, nothing below -230),
-- MineLevels (part / light / emitter budgets, everything inside its chamber), MineCarve (pieces
-- of real-looking blocks) and the Mine localization.
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

-- Lune's CFrame.lookAt is wrong (tools/qa/scene.luau): give the modules a corrected library.
local RawCFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return RawCFrame.new(at)
	end
	look = look.Unit
	up = up or Vector3.new(0, 1, 0)
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, -1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.new(1, 0, 0))
		end
	end
	right = right.Unit
	return RawCFrame.fromMatrix(at, right, right:Cross(look))
end
local CFrame = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return RawCFrame.new(...)
	end,
}, { __index = RawCFrame })
L.CFrame = CFrame

local Layout = L.Require("ReplicatedStorage.Mine.MineLayout")
local Themes = L.Require("ReplicatedStorage.Mine.MineThemes")
local Structures = L.Require("ReplicatedStorage.Mine.MineStructures")
local Levels = L.Require("ReplicatedStorage.Mine.MineLevels")
local Carve = L.Require("ServerScriptService.Mine.MineCarve")
local Locale = L.Require("ReplicatedStorage.Localization.Mine")
local Depth = L.Require("ReplicatedStorage.DogEconomy.DepthDefinitions")
local Config = L.Require("ReplicatedStorage.DogEconomy.Config")

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
local function near(a, b, tol, msg)
	if math.abs(a - b) > tol then
		error((msg or "") .. string.format(" expected %.6g ±%.3g got %.6g", b, tol, a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

-- The eight real yards: centre of YardFoundation (Y 1.2) looking at the storage anchor; yards
-- 1-4 west (sx 1), 5-8 mirrored east (sx -1).
local YARDS = {}
for i, z in { -117, -39, 39, 117 } do
	YARDS[i] = { Frame = lookAt(Vector3.new(-105, 1.2, z), Vector3.new(-152.9, 1.2, z)), Sx = 1 }
	YARDS[i + 4] = { Frame = lookAt(Vector3.new(105, 1.2, z), Vector3.new(152.9, 1.2, z)), Sx = -1 }
end
local function layouts()
	local out = {}
	for i, y in YARDS do
		out[i] = Layout.New(y.Frame, y.Sx, i)
	end
	return out
end

-- Every corner of a part, in design coordinates of a layout (or world when layout is nil).
local function corners(part, layout)
	local out = {}
	local cf, s = part.CFrame, part.Size
	for _, dx in { -0.5, 0.5 } do
		for _, dy in { -0.5, 0.5 } do
			for _, dz in { -0.5, 0.5 } do
				local w = cf:PointToWorldSpace(Vector3.new(s.X * dx, s.Y * dy, s.Z * dz))
				table.insert(out, layout and layout:ToDesign(w) or w)
			end
		end
	end
	return out
end
local function parts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			table.insert(out, d)
		end
	end
	return out
end

------------------------------------------------------------------------------------------------
-- MineLayout
------------------------------------------------------------------------------------------------
test("yard frames: real yard 1 hole and mirrored yard 5", function()
	local all = layouts()
	local hole1 = all[1]:Point(Layout.Shaft.X, 1.2, Layout.Shaft.Z)
	near(hole1.X, -141, 1e-3, "yard 1 x")
	near(hole1.Z, -137, 1e-3, "yard 1 z")
	local hole5 = all[5]:Point(Layout.Shaft.X, 1.2, Layout.Shaft.Z)
	near(hole5.X, 141, 1e-3, "yard 5 x")
	near(hole5.Z, -137, 1e-3, "yard 5 z")
end)

test("layout is deterministic", function()
	local a = Layout.New(YARDS[3].Frame, YARDS[3].Sx)
	local b = Layout.New(YARDS[3].Frame, YARDS[3].Sx)
	for layer = 2, 5 do
		for slot = 1, 5 do
			local wa, wb = a:Worksite(layer, slot), b:Worksite(layer, slot)
			eq(wa.Face, wb.Face, "face " .. layer .. "/" .. slot)
			eq(wa.Loot, wb.Loot, "loot")
		end
		eq(a:Arrival(layer), b:Arrival(layer), "arrival")
	end
end)

test("levels: stacked, disjoint, above -230 and under the island", function()
	local prev = Layout.IslandBottom
	for layer = 2, 5 do
		local level = Layout.Levels[layer]
		truthy(level.Ceiling <= prev + 1e-6, "ceiling under the level above " .. layer)
		truthy(level.Ceiling - level.Floor >= 20, "room height " .. layer)
		truthy(level.Floor > -230, "floor above -230")
		eq(Layout.Keys[layer], level.Key, "key")
		prev = level.Floor
	end
	truthy(Layout.Bottom > -230, "bottom")
	eq(Layout.Levels[2].Ceiling, Layout.IslandBottom, "caverns ceiling is the island underside")
end)

test("worksites lie inside their chambers, on the floor, facing a side wall", function()
	for i, layout in layouts() do
		for layer = 2, 5 do
			local level = Layout.Levels[layer]
			for slot = 1, 5 do
				local site = layout:Worksite(layer, slot)
				truthy(site, "site " .. layer .. "/" .. slot)
				local p = site.Face.Position
				truthy(p.Y > -230, "above -230")
				near(p.Y, level.Floor, 1e-4, "on the floor")
				local kind, at = layout:Contains(p + Vector3.new(0, 2, 0))
				eq(kind, "Level", "contained yard " .. i)
				eq(at, layer, "level")
				local d = layout:ToDesign(p)
				local c = Layout.Chamber
				-- room for a 10 stud dog behind the face point
				local back = d.X - Layout.Worksites[slot].Dir * 10
				truthy(back > c.X0 and back < c.X1, "dog fits in the chamber " .. slot)
				local look = layout:ToDesign(p + site.Face.LookVector) - d
				near(look.X, Layout.Worksites[slot].Dir, 1e-4, "faces the wall")
				eq(layout:Contains(site.Loot.Position + Vector3.new(0, 1, 0)), "Level", "loot inside")
			end
		end
		truthy(layout:Worksite(1, 1) == nil, "no worksite on the surface")
		truthy(layout:Worksite(2, 6) == nil, "only 5 slots")
	end
end)

test("worksites keep the kennel arrangement (odd slots -x', even +x')", function()
	for slot, site in Layout.Worksites do
		eq(site.Dir, slot % 2 == 1 and -1 or 1, "side " .. slot)
	end
end)

test("Contains: shaft, levels, outside", function()
	local all = layouts()
	for i, layout in all do
		local s = Layout.Shaft
		eq(layout:Contains(layout:Point(s.X, -10, s.Z)), "Shaft", "shaft in the island " .. i)
		eq(layout:Contains(layout:Point(s.X, -120, s.Z)), "Shaft", "deep shaft")
		eq(layout:Contains(layout:Point(s.X, 4, s.Z)), nil, "above ground is the surface")
		eq(layout:Contains(layout:Point(0, -80, -60)), nil, "rock next to the chamber")
		eq(layout:Contains(layout:Point(0, -200, 0)), nil, "below the mine")
		for layer = 2, 5 do
			local arrival = layout:Arrival(layer)
			local kind, at = layout:Contains(arrival.Position + Vector3.new(0, 3, 0))
			eq(kind, "Level", "arrival " .. layer)
			eq(at, layer, "arrival level")
		end
		eq(layout:Contains(layout:Arrival(1).Position + Vector3.new(0, 3, 0)), nil, "surface arrival")
		-- Another yard's mine is not this one.
		local other = all[i % 8 + 1]
		eq(layout:Contains(other:Arrival(3).Position + Vector3.new(0, 3, 0)), nil, "other yard")
	end
	-- Layout.Find over a list of fake yards.
	local fake = {}
	for i, y in YARDS do
		local attrs = { YardId = i, MineFrame = y.Frame, MineSx = y.Sx }
		local inst = roblox.Instance.new("Model")
		for k, v in attrs do
			inst:SetAttribute(k, v)
		end
		table.insert(fake, inst)
	end
	local found, _, kind, layer = Layout.Find(fake, all[6]:Arrival(4).Position + Vector3.new(0, 3, 0))
	eq(found and found:GetAttribute("YardId"), 6, "find yard")
	eq(kind, "Level")
	eq(layer, 4)
	eq(Layout.Find(fake, Vector3.new(0, -100, 0)), nil, "street below")
end)

test("MirrorCF: proper rotation, involution, ToWorld/ToDesign round trip", function()
	local cf = CFrame.new(3, 4, -5) * CFrame.Angles(0.3, 1.1, -0.4)
	local m = Layout.MirrorCF(cf, -1)
	local det = m.RightVector:Cross(m.UpVector):Dot(-m.LookVector)
	near(det, 1, 1e-5, "det")
	local back = Layout.MirrorCF(m, -1)
	near((back.Position - cf.Position).Magnitude, 0, 1e-5, "involution pos")
	near(back.LookVector:Dot(cf.LookVector), 1, 1e-5, "involution rot")
	local layout = layouts()[7]
	local p = Vector3.new(7, -40, -12)
	local w = layout:Point(p.X, p.Y, p.Z)
	near((layout:ToDesign(w) - p).Magnitude, 0, 1e-4, "round trip")
	near((layout:ToWorld(CFrame.new(p)).Position - w).Magnitude, 0, 1e-4, "ToWorld = Point")
end)

test("dog placement follows the dig layer", function()
	eq(Layout.DogPlacement(1), "Surface")
	eq(Layout.DogPlacement(nil), "Surface")
	eq(Layout.DogPlacement("x"), "Surface")
	eq(Layout.DogPlacement(2), "Caverns")
	eq(Layout.DogPlacement(3), "Ruins")
	eq(Layout.DogPlacement(4), "Cursed")
	eq(Layout.DogPlacement(5), "Void")
	eq(Layout.DogPlacement(6), "Surface", "out of range")
end)

test("unlock masks (new and old profiles)", function()
	local R = L.Require("ServerScriptService.Economy.Rules")
	local fresh = R.Profile(1, L.Time)
	eq(Layout.Mask(fresh.UnlockedLayers), 1, "new player: surface only")
	eq(Layout.Mask(nil), 1, "old profile without the field")
	eq(Layout.Mask({ ["1"] = true, ["2"] = true, ["3"] = true }), 1 + 2 + 4)
	local mask = Layout.Mask({ ["1"] = true, ["2"] = true, ["5"] = true })
	truthy(Layout.Unlocked(mask, 1) and Layout.Unlocked(mask, 2) and Layout.Unlocked(mask, 5), "unlocked")
	truthy(not Layout.Unlocked(mask, 3) and not Layout.Unlocked(mask, 4), "locked")
	truthy(not Layout.Unlocked(mask, 0) and not Layout.Unlocked(mask, 6), "out of range")
	truthy(Layout.Unlocked(0, 1), "surface always open")
end)

------------------------------------------------------------------------------------------------
-- Carving
------------------------------------------------------------------------------------------------
local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 1103515245 + 12345) % 2147483648
		return a + (b - a) * (s / 2147483648)
	end
end
local function area(r)
	return (r.X1 - r.X0) * (r.Z1 - r.Z0)
end
local function inside(r, x, z)
	return x > r.X0 and x < r.X1 and z > r.Z0 and z < r.Z1
end

test("carve: pieces exactly cover the box minus the holes", function()
	local R = rng(11)
	for trial = 1, 300 do
		local box = { X0 = R(-50, 0), X1 = R(1, 60), Z0 = R(-40, -1), Z1 = R(0, 40) }
		local holes = {}
		for _ = 1, (trial % 3) + 1 do
			local hx, hz, hw, hd = R(-60, 60), R(-50, 50), R(1, 14), R(1, 14)
			table.insert(holes, { X0 = hx, X1 = hx + hw, Z0 = hz, Z1 = hz + hd })
		end
		-- the holes of one part never overlap each other (shafts are far apart)
		local disjoint = true
		for i = 1, #holes do
			for j = i + 1, #holes do
				local a, b = holes[i], holes[j]
				if a.X0 < b.X1 and b.X0 < a.X1 and a.Z0 < b.Z1 and b.Z0 < a.Z1 then
					disjoint = false
				end
			end
		end
		if disjoint then
			local pieces = Layout.CarveRects(box, holes)
			local expected = area(box)
			for _, h in holes do
				local x0, x1 = math.max(box.X0, h.X0), math.min(box.X1, h.X1)
				local z0, z1 = math.max(box.Z0, h.Z0), math.min(box.Z1, h.Z1)
				if x1 > x0 and z1 > z0 then
					expected -= (x1 - x0) * (z1 - z0)
				end
			end
			local total = 0
			for i, p in pieces do
				truthy(p.X1 > p.X0 and p.Z1 > p.Z0, "non-empty piece")
				truthy(p.X0 >= box.X0 - 1e-9 and p.X1 <= box.X1 + 1e-9 and p.Z0 >= box.Z0 - 1e-9 and p.Z1 <= box.Z1 + 1e-9, "inside the box")
				total += area(p)
				for j = i + 1, #pieces do
					local q = pieces[j]
					local ox = math.min(p.X1, q.X1) - math.max(p.X0, q.X0)
					local oz = math.min(p.Z1, q.Z1) - math.max(p.Z0, q.Z0)
					truthy(not (ox > 1e-6 and oz > 1e-6), "pieces overlap")
				end
			end
			near(total, expected, 1e-6 * math.max(1, expected), "area")
			-- sample points: in a piece <=> in the box and in no hole
			for _ = 1, 25 do
				local x, z = R(box.X0, box.X1), R(box.Z0, box.Z1)
				local inHole = false
				for _, h in holes do
					inHole = inHole or inside(h, x, z)
				end
				local inPiece = 0
				for _, p in pieces do
					if inside(p, x, z) then
						inPiece += 1
					end
				end
				if inHole then
					eq(inPiece, 0, "point in a hole is uncovered")
				else
					-- points on a cut line can be on the border of two pieces: allow 0 only there
					truthy(inPiece <= 1, "covered once")
				end
			end
			truthy(#pieces <= 4 * #holes + 1, "piece count")
		end
	end
end)

test("carve: real blocks (rotated 90°) around a shaft column", function()
	local layout = layouts()[1]
	local cf, size = layout:Hole(2, -34)
	-- LivingGround-like strip 360 x 0.41 x 12 at z -144..-132, and a strip turned by 90°.
	local strips = {
		{ CFrame = CFrame.new(0, -0.155, -138), Size = Vector3.new(360, 0.41, 12) },
		{ CFrame = CFrame.new(-141, -16, -138) * CFrame.Angles(0, math.pi / 2, 0), Size = Vector3.new(12, 32, 60) },
	}
	for _, strip in strips do
		local pieces = Carve.Pieces(strip.CFrame, strip.Size, { { CFrame = cf, Size = size } })
		truthy(pieces and #pieces >= 2, "pieces")
		local vol = 0
		for _, p in pieces do
			vol += p.Size.X * p.Size.Y * p.Size.Z
			near(p.Size.Y, strip.Size.Y, 1e-6, "same height")
			near(p.CFrame.Position.Y, strip.CFrame.Position.Y, 1e-6, "same level")
		end
		near(vol, strip.Size.X * strip.Size.Y * strip.Size.Z - 64 * strip.Size.Y, 1e-3, "volume minus the 8x8 hole")
		-- the hole centre is free, a point beside the hole is covered
		local centre = layout:Point(Layout.Shaft.X, strip.CFrame.Position.Y, Layout.Shaft.Z)
		local beside = layout:Point(Layout.Shaft.X + 5, strip.CFrame.Position.Y, Layout.Shaft.Z)
		local function covered(point)
			for _, p in pieces do
				local l = p.CFrame:PointToObjectSpace(point)
				if math.abs(l.X) < p.Size.X / 2 and math.abs(l.Y) <= p.Size.Y / 2 and math.abs(l.Z) < p.Size.Z / 2 then
					return true
				end
			end
			return false
		end
		truthy(not covered(centre), "hole open")
		truthy(covered(beside), "ground beside the hole")
	end
	-- A tilted block cannot be cut.
	eq(Carve.Pieces(CFrame.new(0, 0, 0) * CFrame.Angles(0.3, 0, 0), Vector3.new(10, 1, 10), { { CFrame = cf, Size = size } }), nil, "tilted")
end)

test("carve: Apply hides the original reversibly and Restore puts it back", function()
	local layout = layouts()[2]
	local cf, size = layout:Hole(2, -34)
	local folder = roblox.Instance.new("Folder")
	local part = roblox.Instance.new("Part")
	part.Name = "YardFoundation"
	part.Size = Vector3.new(134, 1, 70)
	part.CFrame = CFrame.new(-105, 0.5, -39)
	part.Anchored = true
	part:SetAttribute("PlotBaseTransparency", 0)
	part:SetAttribute("PlotBaseCollide", true)
	part.Parent = folder
	local made = Carve.Apply(part, { { CFrame = cf, Size = size } })
	eq(#made, 4, "four pieces around an inner hole")
	eq(part.Transparency, 1, "hidden")
	eq(part.CanCollide, false, "no collision")
	eq(part:GetAttribute("PlotBaseTransparency"), 1, "PlotAppearance keeps it hidden")
	eq(part:GetAttribute("MineCarved"), true, "marked")
	for _, piece in made do
		eq(piece.Parent, folder, "piece beside the original")
		eq(piece:GetAttribute("PlotBaseTransparency"), 0, "pieces stay visible")
		eq(piece.CanCollide, true, "pieces collide")
	end
	eq(#Carve.Apply(part, { { CFrame = cf, Size = size } }), 0, "idempotent")
	Carve.Restore(part)
	eq(part.Transparency, 0, "restored transparency")
	eq(part.CanCollide, true, "restored collision")
	eq(part:GetAttribute("PlotBaseTransparency"), 0, "restored base")
	eq(part:GetAttribute("MineCarved"), nil, "unmarked")
	eq(#folder:GetChildren(), 1, "pieces removed")
end)

------------------------------------------------------------------------------------------------
-- Structures
------------------------------------------------------------------------------------------------
test("headframe stays inside its reserved zone", function()
	local model = Structures.Headframe()
	local z = Layout.Zone
	local count = 0
	for _, p in parts(model) do
		count += 1
		for _, c in corners(p, nil) do
			truthy(c.X >= z.X0 - 0.6 and c.X <= z.X1 + 0.6, p.Name .. " x' " .. c.X)
			truthy(c.Z >= z.Z0 - 0.6 and c.Z <= z.Z1 + 0.6, p.Name .. " z " .. c.Z)
			truthy(c.Y >= Layout.GroundY - 0.05 and c.Y < 26, p.Name .. " y " .. c.Y)
		end
	end
	truthy(count <= 160, "headframe parts " .. count)
	truthy(model:FindFirstChild("PromptAnchor", true), "prompt anchor")
	truthy(model:FindFirstChild("DepthSignGui", true), "depth sign")
	truthy(model:FindFirstChild("Wheel"), "wheel model")
end)

test("shell: never inside a chamber or the shaft, nothing below -230, budget", function()
	local model = Structures.Shell()
	local c, sh = Layout.Chamber, Layout.Shaft
	local count = 0
	for _, p in parts(model) do
		count += 1
		local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
		for _, k in corners(p, nil) do
			x0, x1 = math.min(x0, k.X), math.max(x1, k.X)
			y0, y1 = math.min(y0, k.Y), math.max(y1, k.Y)
			z0, z1 = math.min(z0, k.Z), math.max(z1, k.Z)
		end
		truthy(y0 > -230, p.Name .. " below -230: " .. y0)
		-- exact test: no corner of the part strictly inside a chamber / the shaft column
		for layer = 2, 5 do
			local level = Layout.Levels[layer]
			for _, k in corners(p, nil) do
				local inChamber = k.X > c.X0 + 0.05 and k.X < c.X1 - 0.05 and k.Z > c.Z0 + 0.05 and k.Z < c.Z1 - 0.05 and k.Y > level.Floor + 0.05 and k.Y < level.Ceiling - 0.05
				truthy(not inChamber, p.Name .. " corner inside chamber " .. layer)
			end
		end
		if not p.Name:match("^Landing") then
			for _, k in corners(p, nil) do
				local inShaft = k.X > sh.X - sh.Half + 0.05 and k.X < sh.X + sh.Half - 0.05 and k.Z > sh.Z - sh.Half + 0.05 and k.Z < sh.Z + sh.Half - 0.05 and k.Y > Layout.Levels[5].Floor + 0.05 and k.Y < Layout.GroundY
				truthy(not inShaft, p.Name .. " corner inside the shaft")
			end
		end
		-- an axis-aligned structural box must not overlap a chamber volume either
		if p.Name:match("^Wall") or p.Name:match("^Slab") or p.Name == "Bottom" or p.Name == "ShaftBack" then
			for layer = 2, 5 do
				local level = Layout.Levels[layer]
				local overlap = x0 < c.X1 - 0.01 and x1 > c.X0 + 0.01 and z0 < c.Z1 - 0.01 and z1 > c.Z0 + 0.01 and y0 < level.Ceiling - 0.01 and y1 > level.Floor + 0.01
				truthy(not overlap, p.Name .. " overlaps chamber " .. layer)
			end
		end
	end
	truthy(count <= 48, "shell parts " .. count .. " (<= 12 per level)")
end)

test("winch and cage build", function()
	local winch = Structures.Winch(CFrame.new(10, 1, 10), roblox.Color3.new(1, 0, 0))
	truthy(winch:FindFirstChild("WinchSignGui", true), "sign")
	truthy(#parts(winch) <= 20, "winch parts")
	local cage = Structures.Cage()
	truthy(#parts(cage) <= 30, "cage parts")
	local lining = Structures.Lining()
	truthy(#parts(lining) <= 160, "lining parts " .. #parts(lining))
end)

------------------------------------------------------------------------------------------------
-- Levels
------------------------------------------------------------------------------------------------
test("level interiors: budgets and everything inside the chamber", function()
	local c = Layout.Chamber
	for layer = 2, 5 do
		for _, low in { false, true } do
			local model = Levels.Build(layer, { LowFX = low })
			local n, lights, emitters = Levels.Count(model)
			truthy(n <= Levels.Budget.Parts, "parts " .. layer .. ": " .. n)
			truthy(lights <= Levels.Budget.Lights, "lights " .. layer .. ": " .. lights)
			truthy(emitters <= Levels.Budget.Emitters, "emitters " .. layer .. ": " .. emitters)
			local level = Layout.Levels[layer]
			for _, p in parts(model) do
				local pos = p.CFrame.Position
				truthy(pos.X >= c.X0 - 0.5 and pos.X <= c.X1 + 0.5, p.Name .. " x " .. pos.X)
				truthy(pos.Z >= c.Z0 - 0.5 and pos.Z <= c.Z1 + 0.5, p.Name .. " z " .. pos.Z)
				truthy(pos.Y >= level.Floor - 2 and pos.Y <= level.Ceiling + 3, p.Name .. " y " .. pos.Y)
			end
			truthy(model:FindFirstChild("StopAnchor", true), "stop prompt anchor")
			truthy(model:FindFirstChild("FindsBoardGui", true), "finds board")
			for i = 1, 3 do
				truthy(model:FindFirstChild("Pedestal" .. i, true), "pedestal " .. i)
			end
			for _, id in Depth[tostring(layer)].Items do
				truthy(model:FindFirstChild("Item_" .. id, true), "board cell " .. id)
			end
		end
	end
end)

test("level interiors are deterministic", function()
	for layer = 2, 5 do
		local a, b = Levels.Build(layer), Levels.Build(layer)
		local pa, pb = parts(a), parts(b)
		eq(#pa, #pb, "same count")
		for i = 1, #pa, 7 do
			near((pa[i].CFrame.Position - pb[i].CFrame.Position).Magnitude, 0, 1e-6, "same place")
		end
	end
end)

test("level items come from DepthDefinitions", function()
	for layer = 2, 5 do
		local items = Levels.Items(layer)
		eq(#items, #Depth[tostring(layer)].Items, "item count " .. layer)
	end
end)

------------------------------------------------------------------------------------------------
-- Themes and localization
------------------------------------------------------------------------------------------------
test("themes match the dig layers", function()
	for layer = 1, 5 do
		local t = Themes.Get(layer)
		eq(t.Layer, layer)
		truthy(Config.Layers[layer], "config layer")
		truthy(t.Title:upper() == t.Title, "title upper case")
		truthy(t.Ru:find("[\208\209]"), "russian title " .. layer)
		truthy(t.DepthRu and t.DepthRu ~= t.Depth, "russian depth")
		if layer >= 2 then
			truthy(t.Lighting and t.Lighting.Atmosphere and t.Lighting.Grade, "mood " .. layer)
		end
	end
	eq(Themes.Name(3, "ru"), "ДРЕВНИЕ РУИНЫ")
	eq(Themes.Name(3, "en"), "ANCIENT RUINS")
end)

test("localization covers every world sign", function()
	local keys = { "DOGS DIG AT", "DIGGING AT", "FINDS AT THIS DEPTH", "This depth is still locked", "Stand at the mine elevator" }
	for layer = 1, 5 do
		table.insert(keys, Themes[layer].Title)
		table.insert(keys, Themes[layer].Depth)
	end
	for _, key in keys do
		local ru = Locale.Exact[key]
		truthy(ru and ru:find("[\208\209]") or (ru and ru:find("м$")), "ru " .. key)
	end
	local hit = false
	for _, rule in Locale.Patterns do
		if ("Unlock the previous layer and reach level 12"):find(rule[1]) then
			hit = true
		end
	end
	truthy(hit, "layer unlock pattern")
end)

print(string.format("mine: %d passed, %d failed", passed, failed))
if failed > 0 then
	error(failed .. " mine test(s) failed")
end
