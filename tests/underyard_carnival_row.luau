--!nolint
-- WP-H1 district builders: lune run tests/underyard_carnival_row.luau
-- Builds ServerStorage.UnderyardBuild.FuneralCarnival and .CrookedRow offline (a fresh DataModel holding the real
-- src modules: HalloweenBuild Kit / YardKit, UnderyardLayout and the two builders, executed through tools/sim.luau
-- exactly like tools/edits/40_underyard.luau does) and checks the gameplay contract of DESIGN §7 / §8.4 / §22.6:
--   * one Model per district named after it with UyDistrict, inside its district box, anchored, <= 3 500 parts / 35 lights
--   * FUNERAL RUN: 10 numbered checkpoint arches (>= 9 wide, every part RunCheckpoint = i) on the layout points, a clear
--     >= 10-stud lane through them (no solid part within 5 studs of the centreline at body height), 3 pendulum hinge
--     models (Atomic, hinge PrimaryPart at the pivot, UySwingAmp 1.0 / UySwingPeriod 3.2) sweeping across the lane
--     without touching their gallows, the carousel hinge model (Atomic, centre PrimaryPart, UySpin .35) spinning free
--     of every static solid, the conveyor, the start banner
--   * CROOKED ROW: the door wall from x -198 to -98 (solid, ~22 tall), 4 different hinge door leaves (Atomic, closed,
--     PrimaryPart hinge), numerals (NoTranslate), unlit DoorHint lamps, the door court (no obstacle within r 20), the
--     sealed rare room (closed on all six sides, 3 chest pedestals, candle light), blinking eye windows (UyBlink)
--   * every world sign is either NoTranslate digits or has a Russian entry; the new Exact keys collide with no other
--     dictionary
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Sim = require("../tools/sim")

local Instance, Vector3, CFrame, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Enum

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
local function check(cond, msg)
	if not cond then
		error(msg or "check failed", 2)
	end
end

------------------------------------------------------------------------------------------------------------------
-- offline place: the modules the builders need, run through the build sim
------------------------------------------------------------------------------------------------------------------
local game = Instance.new("DataModel")
local function module(parent, name, path)
	local m = Instance.new("ModuleScript")
	m.Name = name
	m.Source = fs.readFile(path)
	m.Parent = parent
	return m
end
local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
local SS, RS, WS = game:GetService("ServerStorage"), game:GetService("ReplicatedStorage"), game:GetService("Workspace")
local HB = folder(SS, "HalloweenBuild")
module(HB, "Kit", "src/ServerStorage/HalloweenBuild/Kit.luau")
module(HB, "YardKit", "src/ServerStorage/HalloweenBuild/YardKit.luau")
local UB = folder(SS, "UnderyardBuild")
local carnivalModule = module(UB, "FuneralCarnival", "src/ServerStorage/UnderyardBuild/FuneralCarnival.luau")
local CROOKED_SRC = "src/ServerStorage/UnderyardBuild/CrookedRow.luau"
local crookedModule = fs.isFile(CROOKED_SRC) and module(UB, "CrookedRow", CROOKED_SRC) or nil
local HW = folder(RS, "Halloween")
local layoutModule = module(HW, "UnderyardLayout", "src/ReplicatedStorage/Halloween/UnderyardLayout.luau")
local district = Instance.new("Model")
district.Name = "DOGROTS_District"
district.Parent = WS
local root = Instance.new("Model")
root.Name = "40_Underyard"
root.Parent = district

local sim = Sim.new(game)
local L = sim:require(layoutModule)
local Carnival = sim:require(carnivalModule)
local Crooked = crookedModule and sim:require(crookedModule) or nil
local notes = {}
local function ctxFor()
	return {
		Root = root,
		Anchors = nil,
		Layout = L,
		District = district,
		Kit = sim:require(HB.Kit),
		YardKit = sim:require(HB.YardKit),
		Note = function(t)
			table.insert(notes, t)
		end,
		Model = function(name)
			local m = Instance.new("Model")
			m.Name = name
			m.Parent = root
			return m
		end,
	}
end
local carnival = Carnival.Build(ctxFor())
local crooked = Crooked and Crooked.Build(ctxFor()) or nil

------------------------------------------------------------------------------------------------------------------
-- geometry helpers
------------------------------------------------------------------------------------------------------------------
local function parts(m)
	local out = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
local function find(m, name)
	for _, d in m:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function shapeOf(p)
	if p.ClassName ~= "Part" then
		return "Block"
	end
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		return "Ball"
	end
	return p.Shape.Name
end
-- is the world point inside the part (margin grows the part)?
-- cached plain-number geometry per part (userdata CFrame math is slow in Lune)
local geo = {}
local function geom(p)
	local g = geo[p]
	if not g then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
		local size = p.Size
		local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
		g = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, hx, hy, hz, shapeOf(p), math.sqrt(hx * hx + hy * hy + hz * hz) }
		geo[p] = g
	end
	return g
end
local function insideXYZ(p, wx, wy, wz, margin)
	local g = geom(p)
	local dx, dy, dz = wx - g[1], wy - g[2], wz - g[3]
	if dx * dx + dy * dy + dz * dz > (g[17] + margin) ^ 2 then
		return false
	end
	local lx = g[4] * dx + g[7] * dy + g[10] * dz
	local ly = g[5] * dx + g[8] * dy + g[11] * dz
	local lz = g[6] * dx + g[9] * dy + g[12] * dz
	local hx, hy, hz, sh = g[13], g[14], g[15], g[16]
	if sh == "Ball" then
		return math.sqrt((lx / hx) ^ 2 + (ly / hy) ^ 2 + (lz / hz) ^ 2) <= 1 + margin / math.min(hx, hy, hz)
	elseif sh == "Cylinder" then
		return math.abs(lx) <= hx + margin and math.sqrt(ly * ly + lz * lz) <= hy + margin
	end
	return math.abs(lx) <= hx + margin and math.abs(ly) <= hy + margin and math.abs(lz) <= hz + margin
end
-- is the world point inside the part (margin grows the part)?
local function inside(p, pos, margin)
	return insideXYZ(p, pos.X, pos.Y, pos.Z, margin or 0)
end
local function topY(p)
	local cf, h = p.CFrame, p.Size / 2
	local best = -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				best = math.max(best, (cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)).Y)
			end
		end
	end
	return best
end
local function corners(p)
	local cf, h = p.CFrame, p.Size / 2
	local out = { cf.Position }
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
			end
		end
	end
	return out
end
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function solids(m, skip)
	local out = {}
	for _, p in parts(m) do
		if p.CanCollide and not (skip and skip(p)) then
			table.insert(out, p)
		end
	end
	return out
end
local function boxOf(name)
	for _, d in L.Districts do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function signs(m)
	local out = {}
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceGui") then
			local label = d:FindFirstChildOfClass("TextLabel")
			table.insert(out, { Gui = d, Text = label and label.Text or "", NoTranslate = d:GetAttribute("NoTranslate") == true })
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- shared district checks
------------------------------------------------------------------------------------------------------------------
for _, case in { { carnival, "FuneralCarnival" }, { crooked or false, "CrookedRow" } } do
	local model, name = case[1] or nil, case[2]
	test(name .. ": one district model, attribute, budget, anchored", function()
		check(model and model:IsA("Model") and model.Name == name, "model named " .. name)
		check(model.Parent == root, "parented under 40_Underyard")
		check(model:GetAttribute("UyDistrict") == name, "UyDistrict attribute")
		local n, lights = 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
				check(d.Anchored, "unanchored part " .. d:GetFullName())
			elseif d:IsA("Light") then
				lights += 1
				check(d.Shadows == false, "light casts shadows " .. d:GetFullName())
			end
		end
		check(n <= 3500, name .. " parts " .. n)
		check(lights <= 35, name .. " lights " .. lights)
		check(n >= 1500, name .. " looks empty: " .. n .. " parts")
	end)
	test(name .. ": stays inside its district box (the entrance apron may reach the gate)", function()
		local box = boxOf(name)
		local gate = L.Gates[name].Position
		for _, p in parts(model) do
			local c = p.CFrame.Position
			local inBox = c.X >= box.Min.X - 2 and c.X <= box.Max.X + 2 and c.Z >= box.Min.Z - 2 and c.Z <= box.Max.Z + 2
			local nearGate = (flat(c) - flat(gate)).Magnitude <= 16
			check(inBox or nearGate, p:GetFullName() .. " outside the box at " .. tostring(c))
			check(c.Y >= -3 and c.Y <= 60, p:GetFullName() .. " height " .. c.Y)
		end
	end)
	test(name .. ": floor top at y 0 covers the box", function()
		local box = boxOf(name)
		local floors = {}
		for _, p in parts(model) do
			if p.CanCollide and math.abs(topY(p)) < .05 and p.Size.X > 40 then
				table.insert(floors, p)
			end
		end
		check(#floors >= 1, "no floor slab")
		for x = box.Min.X + 1, box.Max.X - 1, 7 do
			for z = box.Min.Z + 1, box.Max.Z - 1, 7 do
				local hit = false
				for _, f in floors do
					if inside(f, Vector3.new(x, -.05, z)) then
						hit = true
						break
					end
				end
				check(hit, string.format("no floor under %.0f, %.0f", x, z))
			end
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- FUNERAL CARNIVAL
------------------------------------------------------------------------------------------------------------------
local run = carnival:FindFirstChild("FuneralRun")
local carousel = carnival:FindFirstChild("Carousel")
local path = Carnival.LanePath(L)

test("carnival: lane path visits start then checkpoints 1..10 in order", function()
	check(path[1].Kind == "Start" and (path[1].Pos - L.Carnival.RunStart).Magnitude < .01, "starts at RunStart")
	local nextIndex = 1
	for _, e in path do
		if e.Kind == "Checkpoint" then
			check(e.Index == nextIndex, "checkpoint order")
			check((e.Pos - L.Carnival.Checkpoints[e.Index]).Magnitude < .01, "checkpoint position")
			nextIndex += 1
		end
	end
	check(nextIndex == 11, "10 checkpoints")
end)

test("carnival: 10 numbered checkpoint arches on the layout points, >= 9 wide, all parts tagged", function()
	for i, cp in L.Carnival.Checkpoints do
		local arch = run:FindFirstChild("Checkpoints"):FindFirstChild("RunCheckpoint_" .. i)
		check(arch, "RunCheckpoint_" .. i)
		check(arch:GetAttribute("RunCheckpoint") == i, "model attribute")
		local pillars = {}
		for _, p in parts(arch) do
			check(p:GetAttribute("RunCheckpoint") == i, "part tag " .. p.Name)
			if p.Name == "ArchPillar" and p.Size.Y > 3 then
				table.insert(pillars, p)
			end
		end
		check(#pillars >= 2, "pillars")
		local a, b = pillars[1], pillars[2]
		for _, p in pillars do
			if (flat(p.CFrame.Position) - flat(pillars[1].CFrame.Position)).Magnitude > 4 then
				b = p
			end
		end
		local gap = (flat(a.CFrame.Position) - flat(b.CFrame.Position)).Magnitude - math.max(a.Size.X, a.Size.Z)
		check(gap >= 9, "arch " .. i .. " inner width " .. gap)
		local mid = (flat(a.CFrame.Position) + flat(b.CFrame.Position)) / 2
		check((mid - flat(cp)).Magnitude < .6, "arch " .. i .. " centred on the checkpoint")
		local digit = false
		for _, s in signs(arch) do
			if s.Text == tostring(i) then
				check(s.NoTranslate, "digit sign NoTranslate")
				digit = true
			end
		end
		check(digit, "arch " .. i .. " has its number")
	end
end)

test("carnival: the run lane is clear (no solid within 5 studs of the centreline, body height)", function()
	local blockers = solids(carnival, function(p)
		return topY(p) <= 1.0 -- floors, deck, steps, belt and ramps are walkable
	end)
	local bad = {}
	for k = 1, #path - 1 do
		local a, b = flat(path[k].Pos), flat(path[k + 1].Pos)
		local len = (b - a).Magnitude
		local d = (b - a).Unit
		local side = Vector3.new(-d.Z, 0, d.X)
		for t = 0, len, 1 do
			for lat = -5, 5, 1 do
				for _, y in { 1.5, 3.2, 4.8 } do
					local pos = a + d * t + side * lat + Vector3.new(0, y + (path[k].Kind == "Carousel" and .9 or 0), 0)
					for _, p in blockers do
						if inside(p, pos) then
							bad[p:GetFullName()] = string.format("leg %d t %.0f lat %d", k, t, lat)
						end
					end
				end
			end
		end
	end
	local list = {}
	for n, where in bad do
		table.insert(list, n .. " @ " .. where)
	end
	check(#list == 0, "lane blocked by: " .. table.concat(list, "; "))
end)

test("carnival: pendulum hinge models swing across the lane, clear of their gallows", function()
	for i, pos in L.Carnival.Pendulums do
		local pm = find(run, "RunPendulum_" .. i)
		check(pm and pm:IsA("Model"), "RunPendulum_" .. i)
		check(pm.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "Atomic")
		local hinge = pm.PrimaryPart
		check(hinge and hinge.Name == "PendulumHinge" and hinge:IsDescendantOf(pm), "hinge PrimaryPart")
		check(pm:GetAttribute("UySwingAmp") == 1.0 and pm:GetAttribute("UySwingPeriod") == 3.2, "swing attributes")
		check(type(pm:GetAttribute("UySwingPhase")) == "number", "phase")
		check((flat(hinge.CFrame.Position) - flat(pos)).Magnitude < .5, "pivot above the layout point")
		check(hinge.CFrame.Position.Y >= 12, "pivot height")
		local coffin
		for _, p in parts(pm) do
			check(not p.CanCollide, "pendulum parts never collide: " .. p.Name)
			if p.Name == "CoffinBody" and (not coffin or p.Size.Y > coffin.Size.Y) then
				coffin = p
			end
		end
		check(coffin, "coffin")
		-- lateral sweep at full amplitude covers the 10-stud lane
		local arm = hinge.CFrame:PointToObjectSpace(coffin.CFrame.Position)
		local reach = math.abs(arm.Y) * math.sin(1.0)
		check(reach >= 5, "sweep reach " .. reach)
		check(math.abs(arm.X) < 1.5, "coffin hangs over the lane centre")
		-- sweep: no pendulum part corner enters a gallows solid
		local gallows = find(run, "RunGallows_" .. i)
		check(gallows, "gallows")
		local gsol = solids(gallows)
		for step = -10, 10 do
			local th = step / 10 * 1.0
			local rot = hinge.CFrame * CFrame.Angles(0, 0, th) * hinge.CFrame:Inverse()
			for _, p in parts(pm) do
				for _, c in corners(p) do
					local w = rot * c
					check(w.Y > .2, "pendulum hits the ground")
					for _, g in gsol do
						check(not inside(g, w), string.format("pendulum %d %s hits %s at %.2f rad", i, p.Name, g.Name, th))
					end
				end
			end
		end
	end
end)

test("carnival: carousel hinge model spins free of every static solid", function()
	check(carousel and carousel.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "Atomic carousel")
	local hub = carousel.PrimaryPart
	local c = L.Carnival.Carousel.Centre
	check(hub and hub.Name == "CarouselHub", "hub PrimaryPart")
	check((flat(hub.CFrame.Position) - flat(c)).Magnitude < .05, "hub at the centre")
	check(carousel:GetAttribute("UySpin") == .35, "UySpin")
	local deck = carousel:FindFirstChild("CarouselDeck")
	check(deck and deck.CanCollide, "walkable deck")
	check(math.abs(deck.RotVelocity.Y - .35) < 1e-3, "deck carries riders at the spin rate")
	local mountsSolid = 0
	for _, p in parts(carousel) do
		if p.Name:sub(1, 5) == "Mount" and p.CanCollide then
			mountsSolid += 1
		end
	end
	check(mountsSolid == 0, "mounts never block runners")
	local static = solids(carnival, function(p)
		return p:IsDescendantOf(carousel) or topY(p) <= .5
	end)
	local near = {}
	for _, s in static do
		if (flat(s.CFrame.Position) - flat(c)).Magnitude < 30 then
			table.insert(near, s)
		end
	end
	for step = 0, 23 do
		local th = step / 24 * 2 * math.pi
		local rot = hub.CFrame * CFrame.Angles(0, th, 0) * hub.CFrame:Inverse()
		for _, p in parts(carousel) do
			for _, k in corners(p) do
				local w = rot * k
				for _, s in near do
					check(not inside(s, w), string.format("carousel %s hits %s at %.2f rad", p.Name, s:GetFullName(), th))
				end
			end
		end
	end
end)

test("carnival: start banner, conveyor, ticket booth, tent, wheel, coaster", function()
	check(find(carnival, "RunStartBanner"), "start banner")
	local belt = find(carnival, "ConveyorBelt")
	check(belt and belt:GetAttribute("RunConveyor") == true and belt.CanCollide, "conveyor belt")
	check(belt.Velocity.Magnitude > 1, "belt carries runners")
	local booth = find(carnival, "TicketBooth")
	local plinth = booth and booth:FindFirstChild("BoothPlinth")
	check(plinth and (flat(plinth.CFrame.Position) - flat(L.Carnival.TicketBooth)).Magnitude < .1, "ticket booth at its point")
	for _, n in { "BigTop", "FerrisWheel", "CoffinCoaster", "Perimeter", "Ground" } do
		check(carnival:FindFirstChild(n), n)
	end
	local tent = carnival.BigTop
	local walls = 0
	for _, p in parts(tent) do
		if p.Name == "TentWall" then
			walls += 1
			check((flat(p.CFrame.Position) - flat(L.Carnival.Tent.Centre)).Magnitude <= L.Carnival.Tent.Radius + 1, "wall on the tent circle")
		end
	end
	check(walls >= 12 and walls < 20, "walk-through tent walls " .. walls)
end)

test("carnival: seal-state attributes are present", function()
	local light, show, hide = 0, 0, 0
	for _, d in carnival:GetDescendants() do
		if d:GetAttribute("UyLightAtSeal") == 2 then
			light += 1
		end
		if d:GetAttribute("UyShowAtSeal") == 2 then
			show += 1
		end
		if d:GetAttribute("UyHideAtSeal") == 2 then
			hide += 1
		end
	end
	check(light >= 20 and show >= 1 and hide >= 1, string.format("light %d show %d hide %d", light, show, hide))
end)

------------------------------------------------------------------------------------------------------------------
-- CROOKED ROW
------------------------------------------------------------------------------------------------------------------
local C2 = L.Crooked

test("crooked: door wall spans x -198..-98 along WallZ, solid, ~22 tall", function()
	local wall = crooked:FindFirstChild("DoorWall")
	check(wall, "DoorWall model")
	local sol = solids(crooked)
	local maxTop = 0
	for _, p in parts(wall) do
		maxTop = math.max(maxTop, topY(p))
	end
	check(maxTop >= 20, "wall height " .. maxTop)
	for x = -198, -98, 1 do
		for _, y in { 1.5, 4, 8 } do
			local pos = Vector3.new(x, y, C2.WallZ - .6)
			local hit = false
			for _, p in sol do
				if inside(p, pos) then
					hit = true
					break
				end
			end
			check(hit, string.format("gap in the door wall at x %d y %.1f", x, y))
		end
	end
end)

test("crooked: 4 different closed hinge doors with numerals and unlit hint lamps", function()
	local shapes = {}
	local wallSolids = solids(crooked)
	local allParts = parts(crooked)
	local allSigns = signs(crooked)
	for i, dp in C2.Doors do
		local leaf = find(crooked, "Door_" .. i .. "_Leaf")
		check(leaf and leaf:IsA("Model"), "Door_" .. i .. "_Leaf")
		check(leaf.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "Atomic leaf")
		local hinge = leaf.PrimaryPart
		check(hinge and hinge:IsDescendantOf(leaf) and hinge.Transparency == 1, "hinge PrimaryPart")
		check(math.abs(hinge.CFrame.Position.X - dp.X) < 6 and math.abs(hinge.CFrame.Position.Z - C2.WallZ) < 1.5, "hinge in door " .. i)
		check(leaf:GetAttribute("DoorIndex") == i, "DoorIndex")
		check(type(leaf:GetAttribute("OpenAngle")) == "number" and math.abs(leaf:GetAttribute("OpenSign")) == 1, "open attributes")
		-- closed: the leaf fills the opening in front of the vestibule; opening it swings toward +Z (the court)
		local ang = math.rad(leaf:GetAttribute("OpenAngle")) * leaf:GetAttribute("OpenSign")
		local open = hinge.CFrame * CFrame.Angles(0, ang, 0) * hinge.CFrame:Inverse()
		local slab
		for _, p in parts(leaf) do
			check(not p.CanCollide, "leaf parts are visual")
			if p.Name == "DoorSlab" then
				local far = (flat(p.CFrame.Position) - flat(hinge.CFrame.Position)).Magnitude
				if not slab or far > (flat(slab.CFrame.Position) - flat(hinge.CFrame.Position)).Magnitude then
					slab = p
				end
			end
		end
		check(slab, "DoorSlab")
		check((open * slab.CFrame.Position).Z > slab.CFrame.Position.Z + 1, "door " .. i .. " opens toward the court")
		local sig = {}
		for _, p in parts(leaf) do
			table.insert(sig, string.format("%s%.1f%.1f", p.Name, p.Size.X, p.Size.Y))
		end
		table.sort(sig)
		shapes[table.concat(sig, ",")] = true
		-- numeral
		local num = false
		for _, s in allSigns do
			if s.Text == tostring(i) and s.NoTranslate and (flat(s.Gui.Parent.CFrame.Position) - flat(dp)).Magnitude < 8 then
				num = true
			end
		end
		check(num, "numeral " .. i)
		-- hint lamp (unlit: no Light, not Neon)
		local lamp
		for _, p in allParts do
			if p:GetAttribute("DoorHint") == i then
				lamp = p
			end
		end
		check(lamp, "DoorHint " .. i)
		check(lamp.Material ~= Enum.Material.Neon and not lamp:FindFirstChildWhichIsA("Light"), "hint lamp unlit")
		check((flat(lamp.CFrame.Position) - flat(dp)).Magnitude < 8, "lamp above its door")
		-- blocker keeps players out of the doorway
		local blocked = false
		for _, p in wallSolids do
			if inside(p, Vector3.new(dp.X, 3, C2.WallZ - .6)) then
				blocked = true
			end
		end
		check(blocked, "doorway " .. i .. " blocked")
	end
	local n = 0
	for _ in shapes do
		n += 1
	end
	check(n == 4, "4 different doors, got " .. n)
end)

test("crooked: door court cobbles r 26, nothing standing within r 20", function()
	local court = crooked:FindFirstChild("DoorCourt")
	check(court, "DoorCourt model")
	local c = C2.Court.Centre
	for _, p in parts(crooked) do
		local d = (flat(p.CFrame.Position) - flat(c)).Magnitude
		if d < 20 then
			check(topY(p) <= .6 or p.Transparency >= 1 and not p.CanCollide, "obstacle in the court: " .. p:GetFullName())
		end
	end
	local far = 0
	for _, p in parts(court) do
		if p.Name:sub(1, 5) == "Court" then
			far = math.max(far, (flat(p.CFrame.Position) - flat(c)).Magnitude)
		end
	end
	check(far >= 23 and far <= 30, "court radius " .. far)
end)

test("crooked: the rare room is sealed (six solid sides) with 3 chest pedestals and candle light", function()
	local rr = C2.RareRoom
	local room = crooked:FindFirstChild("RareRoom")
	check(room, "RareRoom model")
	local sol = solids(room)
	local c, h = rr.Centre + Vector3.new(0, rr.Half.Y, 0), rr.Half
	local function sealedAt(pos)
		for _, p in sol do
			if inside(p, pos) then
				return true
			end
		end
		return false
	end
	for u = -1, 1, .125 do
		for v = -1, 1, .125 do
			for _, pos in {
				c + Vector3.new(u * h.X, v * h.Y, -h.Z - .5), c + Vector3.new(u * h.X, v * h.Y, h.Z + .5),
				c + Vector3.new(-h.X - .5, u * h.Y, v * h.Z), c + Vector3.new(h.X + .5, u * h.Y, v * h.Z),
				c + Vector3.new(u * h.X, -h.Y - .5, v * h.Z), c + Vector3.new(u * h.X, h.Y + .5, v * h.Z),
			} do
				check(sealedAt(pos), "hole in the rare room at " .. tostring(pos))
			end
		end
	end
	local pedestals, light = 0, 0
	for _, d in room:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ChestPedestal" then
			pedestals += 1
		elseif d:IsA("PointLight") then
			light += 1
		end
	end
	check(pedestals == 3, "pedestals " .. pedestals)
	check(light >= 1, "candle light")
	-- spawn point free
	for _, p in sol do
		check(not inside(p, rr.Spawn + Vector3.new(0, 2.5, 0)), "spawn blocked by " .. p.Name)
	end
end)

test("crooked: blinking eye windows, leaning houses, laundry, bent lane", function()
	local eyes = 0
	for _, d in crooked:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("UyBlink") == true then
			eyes += 1
			local pane, lids = false, 0
			for _, p in parts(d) do
				if p.Name == "EyePane" and p.Material == Enum.Material.Neon then
					pane = true
				elseif p.Name:sub(1, 6) == "Eyelid" then
					lids += 1
				end
			end
			check(pane and lids >= 2, "eye window parts")
		end
	end
	check(eyes >= 8, "eye windows " .. eyes)
	local houses = crooked:FindFirstChild("Houses")
	check(houses and #houses:GetChildren() >= 8, "houses")
	check(find(crooked, "Laundry"), "laundry lines")
	check(find(crooked, "BentLane"), "bent lane")
	-- the lane from the gate to the court has no solid obstacle at body height
	local lane = Crooked.LanePath(L)
	local sol = solids(crooked)
	for k = 1, #lane - 1 do
		local a, b = flat(lane[k]), flat(lane[k + 1])
		local d = (b - a).Unit
		local side = Vector3.new(-d.Z, 0, d.X)
		for t = 0, (b - a).Magnitude, 1 do
			for lat = -4, 4, 2 do
				local pos = a + d * t + side * lat + Vector3.new(0, 3, 0)
				for _, p in sol do
					check(not inside(p, pos), "bent lane blocked by " .. p:GetFullName())
				end
			end
		end
	end
end)

test("with WP-G's district floor present the builders add no second floor or apron", function()
	local root2 = Instance.new("Model")
	root2.Name = "40_Underyard_Shared"
	root2.Parent = district
	for _, n in { "FuneralCarnival", "CrookedRow" } do
		local f = Instance.new("Part")
		f.Name = n .. "Floor"
		f:SetAttribute("UyFloor", n)
		f.Parent = root2
	end
	local ctx = ctxFor()
	ctx.Root = root2
	ctx.Model = function(name)
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = root2
		return m
	end
	for _, mod in { Carnival, Crooked } do
		local m = mod.Build(ctx)
		for _, p in parts(m) do
			check(p:GetAttribute("UyFloor") == nil and p.Name ~= "EntranceApron", "duplicate floor " .. p:GetFullName())
		end
	end
	root2:Destroy()
end)

------------------------------------------------------------------------------------------------------------------
-- localization of world text
------------------------------------------------------------------------------------------------------------------
test("every world sign is NoTranslate or translated; new keys collide with no other dictionary", function()
	local loc = sim:require(module(folder(RS, "Localization"), "UnderyardCarnivalRow", "src/ReplicatedStorage/Localization/UnderyardCarnivalRow.luau"))
	check(type(loc.Exact) == "table", "Exact table")
	for en, ru in loc.Exact do
		check(type(ru) == "string" and ru ~= "" and ru ~= en, "translation of " .. en)
		check(ru:find("[\208\209]") ~= nil, "Russian (Cyrillic) text for " .. en)
	end
	-- every other dictionary the translator loads (base AutoTranslate table + the other Localization modules)
	local others = { "src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau" }
	for _, f in fs.readDir("src/ReplicatedStorage/Localization") do
		if f ~= "UnderyardCarnivalRow.luau" then
			table.insert(others, "src/ReplicatedStorage/Localization/" .. f)
		end
	end
	local sources = {}
	for _, f in others do
		sources[f] = fs.readFile(f)
	end
	local function known(text)
		if loc.Exact[text] then
			return true
		end
		for _, src in sources do
			if src:find('["' .. text .. '"]', 1, true) then
				return true
			end
		end
		return false
	end
	for _, m in { carnival, crooked } do
		for _, s in signs(m) do
			if s.NoTranslate then
				check(not s.Text:find(" "), "NoTranslate sign must be a number or a name: " .. s.Text)
			elseif s.Text:find("%a") then
				check(known(s.Text), "untranslated sign: " .. s.Text)
			end
		end
	end
	for f, src in sources do
		for en in loc.Exact do
			check(not src:find('["' .. en .. '"]', 1, true), "key " .. en .. " already in " .. f)
		end
	end
end)

print(table.concat(notes, "\n"))
print(string.format("underyard_carnival_row: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("underyard_carnival_row tests failed")
end
