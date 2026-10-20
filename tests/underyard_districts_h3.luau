--!nolint
-- WP-H3 district builders (ServerStorage.UnderyardBuild.MourningMarsh / Undercrypt / BlackBellArena): runs the real
-- builders from src/ through tools/edits/40_underyard.luau + tools/sim.luau on a minimal DataModel and checks the
-- builder contract (DESIGN §7.3, §22.6) and the gameplay needs of seals III / IV / VII (§8.4).
-- usage: lune run tests/underyard_districts_h3.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Sim = require("../tools/sim")
local V3 = roblox.Vector3.new

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

local BUILDERS = { "GothicProps", "MourningMarsh", "Undercrypt", "BlackBellArena" }

local function module(parent, name, path)
	local m = roblox.Instance.new("ModuleScript")
	m.Name = name
	m.Source = fs.readFile(path)
	m.Parent = parent
	return m
end

-- a fresh DataModel with only what the edit + the WP-H3 builders need, then the edit itself
local function build()
	local game = roblox.Instance.new("DataModel")
	local ws = game:GetService("Workspace")
	local district = roblox.Instance.new("Model")
	district.Name = "DOGROTS_District"
	district.Parent = ws
	local ss = game:GetService("ServerStorage")
	local hb = roblox.Instance.new("Folder")
	hb.Name = "HalloweenBuild"
	hb.Parent = ss
	module(hb, "Kit", "src/ServerStorage/HalloweenBuild/Kit.luau")
	module(hb, "YardKit", "src/ServerStorage/HalloweenBuild/YardKit.luau")
	local ub = roblox.Instance.new("Folder")
	ub.Name = "UnderyardBuild"
	ub.Parent = ss
	for _, n in BUILDERS do
		module(ub, n, "src/ServerStorage/UnderyardBuild/" .. n .. ".luau")
	end
	local rs = game:GetService("ReplicatedStorage")
	local hw = roblox.Instance.new("Folder")
	hw.Name = "Halloween"
	hw.Parent = rs
	module(hw, "UnderyardLayout", "src/ReplicatedStorage/Halloween/UnderyardLayout.luau")
	local sim = Sim.new(game)
	local edit = luau.load(fs.readFile("tools/edits/40_underyard.luau"), { debugName = "40_underyard" })()
	local report = {}
	edit({ game = game, sim = sim, report = report, roblox = roblox, fs = fs })
	local layout = sim:require(rs.Halloween.UnderyardLayout)
	return game, district:FindFirstChild("40_Underyard"), layout, report
end

local game, root, L, report = build()
local marsh = root and root:FindFirstChild("MourningMarsh")
local crypt = root and root:FindFirstChild("Undercrypt")
local arena = root and root:FindFirstChild("BlackBellArena")

-- geometry helpers ---------------------------------------------------------------------------------------------
local function aabb(p)
	local cf, s = p.CFrame, p.Size
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local hx = (math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z) / 2
	local hy = (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2
	local hz = (math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z) / 2
	return x - hx, y - hy, z - hz, x + hx, y + hy, z + hz
end
-- horizontal distance from a point to a part's footprint: the convex hull of its 8 box corners projected on XZ
-- (exact for boxes and wedge bounds, conservative for balls / cylinders); 0 inside
local function hull(points)
	table.sort(points, function(a, b)
		return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
	end)
	local function cross(o, a, b)
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	local lower, upper = {}, {}
	for _, p in points do
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do
			table.remove(lower)
		end
		table.insert(lower, p)
	end
	for i = #points, 1, -1 do
		local p = points[i]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do
			table.remove(upper)
		end
		table.insert(upper, p)
	end
	table.remove(lower)
	table.remove(upper)
	for _, p in upper do
		table.insert(lower, p)
	end
	return lower
end
local function flatDist(px, pz, p)
	local cf, s = p.CFrame, p.Size / 2
	local pts = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local w = cf * V3(sx * s.X, sy * s.Y, sz * s.Z)
				table.insert(pts, { w.X, w.Z })
			end
		end
	end
	local h = hull(pts)
	if #h < 3 then
		local x0, _, z0, x1, _, z1 = aabb(p)
		local dx = math.max(x0 - px, 0, px - x1)
		local dz = math.max(z0 - pz, 0, pz - z1)
		return math.sqrt(dx * dx + dz * dz)
	end
	local inside, best = true, math.huge
	for i = 1, #h do
		local a, b = h[i], h[i % #h + 1]
		local ex, ez = b[1] - a[1], b[2] - a[2]
		if ex * (pz - a[2]) - ez * (px - a[1]) < 0 then
			inside = false
		end
		local t = math.clamp(((px - a[1]) * ex + (pz - a[2]) * ez) / math.max(ex * ex + ez * ez, 1e-9), 0, 1)
		local qx, qz = a[1] + ex * t, a[2] + ez * t
		best = math.min(best, math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2))
	end
	return inside and 0 or best
end
local function parts(rootInst)
	local out = {}
	for _, d in rootInst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
local function count(rootInst, class)
	local n = 0
	for _, d in rootInst:GetDescendants() do
		if d:IsA(class) then
			n += 1
		end
	end
	return n
end
local function within(inst, ancestor)
	local p = inst.Parent
	while p do
		if p == ancestor then
			return true
		end
		p = p.Parent
	end
	return false
end
local function insideModel(part, prefix)
	local p = part.Parent
	while p and p ~= root do
		if p:IsA("Model") and string.sub(p.Name, 1, #prefix) == prefix then
			return true
		end
		p = p.Parent
	end
	return false
end
-- the top of a solid floor part covering (x, z) closest to y (or nil)
local function floorAt(rootInst, x, z, y, tol)
	for _, p in parts(rootInst) do
		if p.CanCollide then
			local x0, _, z0, x1, y1, z1 = aabb(p)
			if x >= x0 and x <= x1 and z >= z0 and z <= z1 and math.abs(y1 - y) <= tol then
				return p
			end
		end
	end
	return nil
end
local function box(name)
	for _, d in L.Districts do
		if d.Name == name then
			return d
		end
	end
end

-- contract -------------------------------------------------------------------------------------------------------
test("each builder makes one model named after its district (UyDistrict)", function()
	assert(root, "40_Underyard missing")
	for _, name in { "MourningMarsh", "Undercrypt", "BlackBellArena" } do
		local n = 0
		for _, c in root:GetChildren() do
			if c.Name == name then
				n += 1
				assert(c:IsA("Model"), name .. " is not a Model")
				assert(c:GetAttribute("UyDistrict") == name, name .. " UyDistrict = " .. tostring(c:GetAttribute("UyDistrict")))
			end
		end
		assert(n == 1, name .. " models: " .. n)
	end
	local orders = {}
	for _, b in report.Builders do
		table.insert(orders, b.Name)
	end
	assert(table.concat(orders, ",") == "MourningMarsh,Undercrypt,BlackBellArena", "build order " .. table.concat(orders, ","))
end)

test("budgets: parts and lights per district", function()
	for _, b in { { marsh, 3000 }, { crypt, 3200 }, { arena, 3000 } } do
		local n, l = #parts(b[1]), count(b[1], "Light")
		assert(n <= b[2], b[1].Name .. " parts " .. n .. " > " .. b[2])
		assert(l <= 30, b[1].Name .. " lights " .. l .. " > 30")
		assert(n >= 1500, b[1].Name .. " suspiciously small: " .. n .. " parts")
	end
end)

test("house style: anchored, CanTouch off, lights without shadows, emitters only under SelfManagedFX", function()
	for _, m in { marsh, crypt, arena } do
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				assert(d.Anchored, d:GetFullName() .. " not anchored")
				assert(not d.CanTouch, d:GetFullName() .. " CanTouch")
				if d.Transparency >= 1 and d.CanCollide then
					assert(not d.CastShadow, d:GetFullName() .. " invisible collider casts a shadow")
				end
			elseif d:IsA("Light") then
				assert(d.Shadows == false, d:GetFullName() .. " casts shadows")
			elseif d:IsA("ParticleEmitter") then
				local ok = false
				local p = d.Parent
				while p and p ~= m do
					if p:GetAttribute("SelfManagedFX") == true then
						ok = true
					end
					p = p.Parent
				end
				assert(ok, d:GetFullName() .. " outside a SelfManagedFX model")
			end
		end
	end
end)

test("deterministic: two builds produce identical geometry", function()
	local _, root2 = build()
	for _, name in { "MourningMarsh", "Undercrypt", "BlackBellArena" } do
		local a, b = parts(root:FindFirstChild(name)), parts(root2:FindFirstChild(name))
		assert(#a == #b, name .. " part count differs " .. #a .. " vs " .. #b)
		local sa, sb = 0, 0
		for i = 1, #a do
			sa += a[i].CFrame.Position.X * 3 + a[i].CFrame.Position.Y * 7 + a[i].CFrame.Position.Z * 11 + a[i].Size.Magnitude
			sb += b[i].CFrame.Position.X * 3 + b[i].CFrame.Position.Y * 7 + b[i].CFrame.Position.Z * 11 + b[i].Size.Magnitude
		end
		assert(math.abs(sa - sb) < 1e-3, name .. " geometry differs")
	end
end)

test("own ground stays inside the district box; everything stays inside the zone", function()
	for _, pair in { { marsh, "MourningMarsh" }, { crypt, "Undercrypt" }, { arena, "BlackBellArena" } } do
		local b = box(pair[2])
		local g = pair[1]:FindFirstChild("Ground")
		assert(g, pair[2] .. " has no Ground model")
		for _, p in parts(g) do
			local x0, _, z0, x1, _, z1 = aabb(p)
			assert(x0 >= b.Min.X - 1 and x1 <= b.Max.X + 1 and z0 >= b.Min.Z - 1 and z1 <= b.Max.Z + 1, p:GetFullName() .. " ground outside the district box")
		end
		for _, p in parts(pair[1]) do
			local x0, y0, z0, x1, y1, z1 = aabb(p)
			assert(L.InZone(V3(x0, y0, z0), 2) and L.InZone(V3(x1, y1, z1), 2), p:GetFullName() .. " outside the Underyard zone")
			assert(x0 >= b.Min.X - 8 and x1 <= b.Max.X + 8 and z0 >= b.Min.Z - 8 and z1 <= b.Max.Z + 8, p:GetFullName() .. " far outside " .. pair[2])
		end
	end
end)

-- MOURNING MARSH ------------------------------------------------------------------------------------------------
test("marsh: mud bed at GroundY, black water at WaterY (Glass, walk-through), boardwalks at BoardwalkY", function()
	local bed = marsh.Ground:FindFirstChild("MarshMudBed")
	local _, _, _, _, top = aabb(bed)
	assert(math.abs(top - L.Marsh.GroundY) < .01 and bed.CanCollide, "mud bed top " .. top)
	local water = marsh.Ground:FindFirstChild("BlackWater")
	local _, _, _, _, wtop = aabb(water)
	assert(math.abs(wtop - L.Marsh.WaterY) < .01, "water top " .. wtop)
	assert(water.Material == roblox.Enum.Material.Glass and not water.CanCollide and not water.CanQuery, "water must be dark glass, CanCollide false")
	local edges = 0
	for _, p in parts(marsh) do
		if p.Name == "WaterEdge" then
			edges += 1
			assert(p.Material == roblox.Enum.Material.Neon, "water edge not Neon")
		end
	end
	assert(edges >= 40, "neon water edges: " .. edges)
	local floors = 0
	for _, p in parts(marsh.Boardwalks) do
		if p.Name == "BoardwalkFloor" then
			floors += 1
			local _, _, _, _, ft = aabb(p)
			assert(math.abs(ft - L.Marsh.BoardwalkY) < .35, "boardwalk floor top " .. ft)
		end
	end
	assert(floors >= 30, "boardwalk floors " .. floors)
end)

test("marsh: the gate path, the pond ring and the marsh choir points are walkable boardwalk (>= 8 wide)", function()
	for i = 7, 9 do
		local cp = L.ChoirPaths[i]
		local f = floorAt(marsh, cp.X, cp.Z, L.Marsh.BoardwalkY, .35)
		assert(f, "ChoirPath_" .. i .. " not on a boardwalk")
	end
	-- width: walk across the gate path at mid-length and around the ring at 12 bearings
	local g = L.Gates.MourningMarsh
	local a = g.Position + g.Facing * 9
	local b = L.ChoirPaths[7]
	local mid = a:Lerp(b, .5)
	local dir = V3(b.X - a.X, 0, b.Z - a.Z).Unit
	local side = V3(-dir.Z, 0, dir.X)
	for _, o in { -4, -2, 0, 2, 4 } do
		local p = mid + side * o
		assert(floorAt(marsh, p.X, p.Z, L.Marsh.BoardwalkY, .35), "gate path not 8 wide at offset " .. o)
	end
	local pc = L.Marsh.Pond.Centre
	for k = 0, 11 do
		local ang = (k + .25) / 12 * math.pi * 2
		for _, r in { 35, 39, 43 } do
			local p = V3(pc.X + math.sin(ang) * r, 0, pc.Z - math.cos(ang) * r)
			assert(floorAt(marsh, p.X, p.Z, L.Marsh.BoardwalkY, .35), string.format("pond ring gap at bearing %d r %d", k, r))
		end
	end
	-- the path starts at the gate: the first plank floor is within 12 studs of the gate
	assert(floorAt(marsh, (g.Position + g.Facing * 10).X, (g.Position + g.Facing * 10).Z, L.Marsh.BoardwalkY, .35), "boardwalk does not reach the gate")
end)

test("marsh: mirror pond (reflective Glass disc, stone rim, collider ring)", function()
	local pond = marsh.MirrorPond:FindFirstChild("MirrorPond")
	assert(pond and pond.Material == roblox.Enum.Material.Glass and pond.Reflectance >= .4, "mirror disc")
	local pc = L.Marsh.Pond.Centre
	assert(math.abs(pond.CFrame.Position.X - pc.X) < .01 and math.abs(pond.CFrame.Position.Z - pc.Z) < .01, "mirror off centre")
	assert(math.abs(math.max(pond.Size.Y, pond.Size.Z) - (L.Marsh.Pond.Radius * 2 + .6)) < .01, "mirror radius")
	local rim, cols = 0, 0
	for _, p in parts(marsh) do
		if p.Name == "PondRim" then
			rim += 1
			assert(p.CanCollide, "rim not solid")
		elseif p.Name == "PondCollider" then
			cols += 1
			assert(p.CanCollide and p.Transparency == 1 and not p.CanQuery, "pond collider")
			assert(math.abs(((p.CFrame.Position - pc) * V3(1, 0, 1)).Magnitude - (L.Marsh.Pond.Radius - .2)) < .5, "pond collider off the rim")
		end
	end
	assert(rim >= 24 and cols >= 16, "rim " .. rim .. " colliders " .. cols)
end)

test("marsh: six mirror graves are Atomic hinge models with a Neon rune on +Z, turning freely", function()
	local stones = {}
	for i, gp in L.MirrorGraves do
		local m = marsh:FindFirstChild("MirrorGraves") and marsh.MirrorGraves:FindFirstChild("MirrorGrave_" .. i .. "_Stone")
		assert(m and m:IsA("Model"), "MirrorGrave_" .. i .. "_Stone missing")
		assert(m.ModelStreamingMode == roblox.Enum.ModelStreamingMode.Atomic, "grave " .. i .. " not Atomic")
		assert(m:GetAttribute("MirrorGrave") == i and type(m:GetAttribute("Rune")) == "string", "grave " .. i .. " attributes")
		local h = m.PrimaryPart
		assert(h and h.Name == "StoneHinge", "grave " .. i .. " PrimaryPart")
		assert(math.abs(h.CFrame.Position.X - gp.X) < .01 and math.abs(h.CFrame.Position.Z - gp.Z) < .01, "hinge off the grave point")
		local look = h.CFrame.LookVector
		assert(math.abs(look.Z + 1) < 1e-4 and math.abs(h.CFrame.UpVector.Y - 1) < 1e-4, "hinge not world aligned")
		-- the hinge is the stone's base: no stone part below it
		local top, runes = -math.huge, 0
		for _, p in parts(m) do
			local _, y0, _, _, y1 = aabb(p)
			assert(y0 >= h.CFrame.Position.Y - .15, p.Name .. " below the hinge of grave " .. i)
			top = math.max(top, y1)
			if p.Material == roblox.Enum.Material.Neon then
				runes += 1
				assert(p.CFrame.Position.Z - h.CFrame.Position.Z > 1, "grave " .. i .. " rune not on the +Z face")
			end
		end
		assert(runes >= 3, "grave " .. i .. " rune strokes " .. runes)
		-- sweep radius of the stone; nothing else may intrude while it turns
		local R = 0
		for _, p in parts(m) do
			local x0, _, z0, x1, _, z1 = aabb(p)
			for _, c in { { x0, z0 }, { x0, z1 }, { x1, z0 }, { x1, z1 } } do
				R = math.max(R, math.sqrt((c[1] - h.CFrame.Position.X) ^ 2 + (c[2] - h.CFrame.Position.Z) ^ 2))
			end
		end
		assert(R < 2.4, "grave " .. i .. " sweep radius " .. R)
		for _, p in parts(marsh) do
			if not within(p, m) and p.Transparency < 1 then
				local _, y0, _, _, y1 = aabb(p)
				if y1 > h.CFrame.Position.Y + .06 and y0 < top and flatDist(h.CFrame.Position.X, h.CFrame.Position.Z, p) < R then
					error(p:GetFullName() .. " intrudes into the turning circle of grave " .. i)
				end
			end
		end
		stones[i] = m
	end
	local glyphs = {}
	for _, m in stones do
		glyphs[m:GetAttribute("Rune")] = true
	end
	local n = 0
	for _ in glyphs do
		n += 1
	end
	assert(n == 6, "the six graves need six different runes")
end)

test("marsh: consult stone at Marsh.Consult, fog FX, seal-state lamps and lilies", function()
	local cs = marsh.MirrorGraves:FindFirstChild("ConsultStone")
	assert(cs, "ConsultStone missing")
	local c = L.Marsh.Consult
	local base = cs:FindFirstChild("ConsultBase")
	assert(base and flatDist(c.X, c.Z, base) < 1, "consult stone not at Marsh.Consult")
	local fog = marsh:FindFirstChild("MarshFog")
	assert(fog and fog:GetAttribute("SelfManagedFX") == true and count(fog, "ParticleEmitter") >= 8, "marsh fog")
	local lit, lilies, flowers = 0, 0, 0
	for _, p in parts(marsh) do
		if p:GetAttribute("UyLightAtSeal") == 3 and p:FindFirstChildOfClass("PointLight") then
			lit += 1
		end
		if p:GetAttribute("UyShowAtSeal") == 3 then
			lilies += 1
		end
		if p.Name == "FlowerPetal" then
			flowers += 1
			assert(p.Material == roblox.Enum.Material.Neon, "petals must glow")
		end
	end
	assert(lit >= 4 and lilies >= 6 and flowers >= 60, string.format("lit %d lilies %d petals %d", lit, lilies, flowers))
	local willows, boats = 0, 0
	for _, d in marsh:GetDescendants() do
		if d.Name == "DeadWillow" then
			willows += 1
		elseif d.Name == "FuneralBoat" then
			boats += 1
		end
	end
	assert(willows >= 8 and boats >= 3, "willows " .. willows .. " boats " .. boats)
end)

-- UNDERCRYPT ----------------------------------------------------------------------------------------------------
local U = L.Undercrypt
test("undercrypt: mine floor at y -16 covering the Floor box; a >= 10 wide ramp from RampTop to RampBottom", function()
	local slab = crypt.Cavern:FindFirstChild("MineFloorSlab")
	local x0, _, z0, x1, y1, z1 = aabb(slab)
	assert(math.abs(y1 - U.FloorY) < .01, "floor top " .. y1)
	assert(x0 <= U.Floor.Min.X and x1 >= U.Floor.Max.X and z0 <= U.Floor.Min.Z and z1 >= U.Floor.Max.Z, "floor does not cover the Floor box")
	local ramp = crypt.CatacombMouth:FindFirstChild("Ramp")
	assert(ramp and ramp:IsA("WedgePart") and ramp.CanCollide, "ramp wedge")
	assert(ramp.Size.X >= 10, "ramp width " .. ramp.Size.X)
	-- the sloped top runs from RampTop (high edge, local -Z) to RampBottom
	local hi = ramp.CFrame * V3(0, ramp.Size.Y / 2, -ramp.Size.Z / 2)
	local lo = ramp.CFrame * V3(0, -ramp.Size.Y / 2, ramp.Size.Z / 2)
	assert((hi - U.RampTop).Magnitude < .6, "ramp top end " .. tostring(hi))
	assert((lo - U.RampBottom).Magnitude < .6, "ramp bottom end " .. tostring(lo))
	-- the respawn point stands on the floor with headroom
	assert(floorAt(crypt, U.Spawn.X, U.Spawn.Z, U.FloorY, .05), "no floor under the spawn")
	for _, p in parts(crypt) do
		if p.CanCollide and p.Transparency < 1 and p.Name ~= "Ramp" then -- the ramp foot is the way out of the spawn
			local _, y0, _, _, yt = aabb(p)
			if yt > U.FloorY + .6 and y0 < U.FloorY + 7 then
				assert(flatDist(U.Spawn.X, U.Spawn.Z, p) > 2.5, p:GetFullName() .. " crowds the mine spawn")
			end
		end
	end
end)

test("undercrypt: nothing taller than 1 stud within r 6 of a mine node", function()
	for i, n in L.MineNodes do
		for _, p in parts(crypt) do
			local _, y0, _, _, y1 = aabb(p)
			if y1 > U.FloorY + 1 and y0 < U.FloorY + 8 and p.Transparency < .95 then
				local d = flatDist(n.X, n.Z, p)
				assert(d >= 6, string.format("%s (top %.2f) is %.2f from MineNode_%d", p:GetFullName(), y1, d, i))
			end
		end
		local crater = crypt.MineFloor:FindFirstChild("Crater_" .. i)
		assert(crater, "crater ring " .. i .. " missing")
	end
end)

test("undercrypt: rock ceiling over the mine with open light shafts", function()
	local covered, total = 0, 0
	local function roofAbove(x, z)
		for _, p in parts(crypt) do
			if p.CanCollide then
				local x0, y0, z0, x1, _, z1 = aabb(p)
				if x >= x0 and x <= x1 and z >= z0 and z <= z1 and y0 > U.FloorY + 10 and y0 < 6 then
					return true
				end
			end
		end
		return false
	end
	for x = U.Floor.Min.X + 4, U.Floor.Max.X - 4, 9 do
		for z = U.Floor.Min.Z + 4, U.Floor.Max.Z - 4, 9 do
			total += 1
			if roofAbove(x, z) then
				covered += 1
			end
		end
	end
	assert(covered / total >= .6, string.format("ceiling covers only %d / %d samples", covered, total))
	assert(covered < total, "no light-shaft gaps in the ceiling")
	local spots, shafts = 0, 0
	for _, d in crypt:GetDescendants() do
		if d:IsA("SpotLight") then
			spots += 1
		elseif d.Name == "ShaftGlow" then
			shafts += 1
			assert(not roofAbove(d.CFrame.Position.X, d.CFrame.Position.Z), "light shaft at " .. tostring(d.CFrame.Position) .. " is roofed over")
		end
	end
	assert(spots >= 4 and shafts >= 4, "shafts " .. shafts .. " spots " .. spots)
end)

test("undercrypt: catacomb mouth at the Entrance, seams, bone walls, niches, rails, carts, seal lamps", function()
	local e = U.Entrance
	local near = false
	for _, p in parts(crypt.CatacombMouth) do
		if p.Name == "ArchVoussoir" and flatDist(e.X, e.Z, p) < 9 then
			near = true
		end
	end
	assert(near, "no arch at Undercrypt.Entrance")
	local names = {}
	for _, p in parts(crypt) do
		names[p.Name] = (names[p.Name] or 0) + 1
	end
	assert((names.OreSeam or 0) >= 20 and (names.OreCrystal or 0) >= 10, "violet ore seams")
	assert((names.WallSkull or 0) >= 20 and (names.BoneEnd or 0) >= 40, "bone walls")
	assert((names.NicheRecess or 0) >= 8 and (names.TimberPost or 0) >= 20, "niches / timber supports")
	assert((names.Rail or 0) >= 16 and (names.Sleeper or 0) >= 60 and (names.CartBody or 0) >= 4, "rails and carts")
	local seal = 0
	for _, p in parts(crypt) do
		if p:GetAttribute("UyLightAtSeal") == 4 and p:FindFirstChildOfClass("PointLight") then
			seal += 1
		end
	end
	assert(seal >= 3, "seal IV lamps " .. seal)
end)

-- BLACK BELL ARENA ----------------------------------------------------------------------------------------------
local A = L.Arena
test("arena: floor r 52 at y 0 and nothing inside r 48 but flush inlays and the chain anchors", function()
	local fl = arena.ArenaFloor:FindFirstChild("ArenaFloorStone")
	local _, _, _, _, top = aabb(fl)
	assert(math.abs(top) < .01 and math.abs(fl.Size.Y - 104) < .01 and math.abs(fl.Size.Z - 104) < .01, "arena floor")
	assert(math.abs(fl.CFrame.Position.X - A.Centre.X) < .01 and math.abs(fl.CFrame.Position.Z - A.Centre.Z) < .01, "arena floor off centre")
	for _, p in parts(arena) do
		if p ~= fl and not insideModel(p, "ArenaChain_") and not insideModel(p, "BlackBell") and p.Transparency < .95 then
			local _, y0, _, _, y1 = aabb(p)
			if y1 > .2 and y0 < 14 then
				local d = flatDist(A.Centre.X, A.Centre.Z, p)
				assert(d >= 48, string.format("%s (y %.1f..%.1f) is %.2f from the arena centre", p:GetFullName(), y0, y1, d))
			end
		end
	end
	-- the bronze rune ring + its seal glyphs
	local band, glyphs = 0, 0
	for _, p in parts(arena.ArenaFloor) do
		if p.Name == "RuneRingBand" then
			band += 1
			assert(p.Material == roblox.Enum.Material.Metal, "rune ring is bronze metal")
		elseif p.Name == "RingGlyph" then
			glyphs += 1
			assert(p:GetAttribute("UyLightAtSeal") == 7, "ring glyph without UyLightAtSeal 7")
		end
	end
	assert(band >= 40 and glyphs >= 60, "rune ring " .. band .. " glyph strokes " .. glyphs)
	-- the edge spawn is on the floor and clear
	local s = A.Spawn
	for _, p in parts(arena) do
		if p.CanCollide and p ~= fl then
			local _, y0, _, _, y1 = aabb(p)
			if y1 > .3 and y0 < 7 then
				assert(flatDist(s.X, s.Z, p) > 2.5, p:GetFullName() .. " crowds the arena spawn")
			end
		end
	end
end)

test("arena: the Black Bell (Atomic, PrimaryPart at its crown, UySwing, ~22 tall at Arena.Bell)", function()
	local bell = arena:FindFirstChild("BlackBell")
	assert(bell and bell.ModelStreamingMode == roblox.Enum.ModelStreamingMode.Atomic, "BlackBell Atomic")
	assert(bell:GetAttribute("UySwing") ~= nil and bell:GetAttribute("UySwing") ~= false, "UySwing")
	local pp = bell.PrimaryPart
	assert(pp and pp.Name == "BellCrown", "PrimaryPart BellCrown")
	local y0, y1 = math.huge, -math.huge
	local neon = 0
	for _, p in parts(bell) do
		local _, a, _, _, b = aabb(p)
		if p.Name ~= "BellClapper" and p.Name ~= "BellClapperCore" and p.Name ~= "BellClapperRod" and p.Transparency < 1 then
			y0, y1 = math.min(y0, a), math.max(y1, b)
		end
		if p.Material == roblox.Enum.Material.Neon then
			neon += 1
		end
		assert(not p.CanCollide, p.Name .. " of the bell collides")
	end
	assert(y1 - y0 >= 20 and y1 - y0 <= 27, "bell height " .. (y1 - y0))
	assert(math.abs((y0 + y1) / 2 - A.Bell.Y) < 2.5, "bell centre " .. (y0 + y1) / 2)
	assert(pp.CFrame.Position.Y >= y1 - 4 and math.abs(pp.CFrame.Position.X - A.Bell.X) < .01 and math.abs(pp.CFrame.Position.Z - A.Bell.Z) < .01, "PrimaryPart not at the crown")
	assert(neon >= 30, "violet runes " .. neon)
	-- the gallows frame actually holds it: frame parts above the crown and uprights outside r 52
	local above, legs = false, 0
	for _, p in parts(arena.BellFrame) do
		local _, a = aabb(p)
		if a > y1 and flatDist(A.Bell.X, A.Bell.Z, p) < 3 then
			above = true
		end
		if p.Name == "GallowsUpright" then
			legs += 1
			assert(flatDist(A.Centre.X, A.Centre.Z, p) > 48, "gallows upright inside the arena")
		end
	end
	assert(above and legs >= 16, "gallows frame")
end)

test("arena: four chain anchors with chains rising to the bell", function()
	for key, pos in A.Chains do
		local m = arena:FindFirstChild("ArenaChain_" .. key)
		assert(m and m:GetAttribute("ChainKey") == key, "ArenaChain_" .. key)
		assert(m.ModelStreamingMode == roblox.Enum.ModelStreamingMode.Atomic, key .. " not Atomic")
		local solid, links, top = false, 0, -math.huge
		local nearBell = false
		for _, p in parts(m) do
			if p.CanCollide and flatDist(pos.X, pos.Z, p) < .5 then
				solid = true
			end
			if p.Name == "ChainLink" then
				links += 1
				if (p.CFrame.Position - A.Bell).Magnitude < 14 then
					nearBell = true
				end
				top = math.max(top, p.CFrame.Position.Y)
			end
		end
		assert(solid, key .. " has no solid post at the anchor")
		assert(links >= 20 and nearBell, key .. " chain does not reach the bell")
		assert(m:FindFirstChild("ChainGlow"), key .. " has no ChainGlow")
	end
end)

test("arena: raised outer ring with ruins and braziers, an open approach, a dressed approach", function()
	local names = {}
	for _, p in parts(arena) do
		names[p.Name] = (names[p.Name] or 0) + 1
	end
	assert((names.RingTierA or 0) >= 30 and (names.RingTierB or 0) >= 30, "outer ring")
	assert((names.BrazierFlame or 0) >= 16, "braziers")
	local ruins = 0
	for _, d in arena:GetDescendants() do
		if d.Name == "Ruin" then
			ruins += 1
		end
	end
	assert(ruins >= 8, "ruins " .. ruins)
	-- the approach corridor (|x| < Width / 2) stays open from the gate into the arena
	local ap = A.Approach
	for _, p in parts(arena) do
		if p.CanCollide and p.Name ~= "ArenaGround" then
			local x0, y0, z0, x1, y1, z1 = aabb(p)
			if y1 > .3 and y0 < 6 and z1 > ap.From.Z and z0 < ap.To.Z then
				assert(x1 < ap.From.X - ap.Width / 2 + .01 or x0 > ap.From.X + ap.Width / 2 - .01, p:GetFullName() .. " blocks the approach")
			end
		end
	end
	assert((names.BannerCloth or 0) >= 12 and (names.ChainPost or 0) >= 12 and (names.GraveBase or 0) >= 12, "approach dressing")
end)

print(string.format("underyard_districts_h3: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("underyard_districts_h3 tests failed")
end
