--!nocheck
-- SHOW THE WAY: route graph, A*, entry selection, corner filleting and resampling, destinations,
-- name resolution, arrow flow, localization, and (when build/DOGROTS_MINING.rbxl exists) the graph
-- against the real place geometry.   lune run tests/navigation.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")
local G = L.Require("ReplicatedStorage.Navigation.RouteGraph")
local D = L.Require("ReplicatedStorage.Navigation.Destinations")
local F = L.Require("ReplicatedStorage.Navigation.ArrowFlow")
local V = roblox.Vector3.new

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
local function near(a, b, tolerance, msg)
	if math.abs(a - b) > tolerance then
		error((msg or "") .. string.format(" expected %.4g ±%.3g got %.4g", b, tolerance, a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function flat(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- Start points used by several tests: spawn, every yard spawn, interior points of every yard,
-- inside buildings and odd corners of the district.
local SPAWN = V(0, 0.6, 377)
local function yardSpawn(id)
	local yard = G.Yard(id)
	return V(yard.Side * 28, 0.35, yard.Center.Z)
end
local YARD_POINTS = { { 0, 60 }, { 0, 40 }, { 0, 50 }, { -18, -6.5 }, { 20, -36 }, { 20, 61 }, { -24, -44.5 }, { 0, 0 }, { 25, 20 }, { -28, 30 } }
local EXTRA = {
	V(100, 2.2, 470), -- inside the lab
	V(-88, 4.1, 470), -- inside the museum hall
	V(130, 0.4, 340), -- inside the cosmetics shop
	V(112, 1.1, 205), -- inside the shelter
	V(-120, 0.3, 300), -- garden lawn
	V(-150, 0.4, 749), -- south loop
	V(30, 0.3, -150), -- beside THE DOG's mouth
	V(-100, 0.5, 230), -- leaderboard plaza
	V(0, 0.5, 750), -- south end of the boulevard
}

local function plan(from, key, yardId)
	local target = G.Target(key, { YardId = yardId })
	local route, why = G.Plan(from, target)
	return route, why, target
end

-- GRAPH ------------------------------------------------------------------------------------------
test("graph size and node data", function()
	truthy(#G.Nodes >= 40 and #G.Nodes <= 70, "nodes " .. #G.Nodes)
	truthy(#G.Edges >= #G.Nodes - 1, "edges " .. #G.Edges)
	for _, node in ipairs(G.Nodes) do
		truthy(node.Pos.Y > -0.5 and node.Pos.Y < 2, node.Id .. " Y on the walking surface " .. node.Pos.Y)
		truthy(#node.Links > 0, node.Id .. " has links")
	end
	for _, edge in ipairs(G.Edges) do
		truthy(edge.Length > 1, edge.A.Id .. "-" .. edge.B.Id .. " length")
	end
end)

test("graph is connected without the sealed nodes", function()
	local seen, queue = { [G.ById.B377] = true }, { G.ById.B377 }
	while #queue > 0 do
		local node = table.remove(queue)
		for _, link in ipairs(node.Links) do
			if not seen[link.Node] and not link.Node.Sealed then
				seen[link.Node] = true
				table.insert(queue, link.Node)
			end
		end
	end
	for _, node in ipairs(G.Nodes) do
		truthy(node.Sealed or seen[node], "unreachable node " .. node.Id)
	end
end)

test("nodes and edges stay clear of every building footprint", function()
	for _, node in ipairs(G.Nodes) do
		local b = G.BlockerAt(node.Pos, 0.5)
		truthy(b == nil, node.Id .. " inside " .. tostring(b and b.Name))
	end
	for _, edge in ipairs(G.Edges) do
		local b = G.SegmentBlocker(edge.A.Pos, edge.B.Pos, 0.5)
		truthy(b == nil, edge.A.Id .. "-" .. edge.B.Id .. " crosses " .. tostring(b and b.Name))
	end
end)

test("A* finds the shortest street path", function()
	local path, cost = G.AStar({ { Node = G.ById.B377, G = 0 } }, G.ById.LabDock)
	truthy(path, "path")
	local ids = {}
	for _, n in ipairs(path) do
		table.insert(ids, n.Id)
	end
	eq(table.concat(ids, " "), "B377 B395 B479 LabDock")
	near(cost, (G.ById.B377.Pos - G.ById.B395.Pos).Magnitude + (G.ById.B395.Pos - G.ById.B479.Pos).Magnitude + (G.ById.B479.Pos - G.ById.LabDock.Pos).Magnitude, 1e-6, "cost")
	-- Several sources: the cheaper start wins.
	local path2 = G.AStar({ { Node = G.ById.B162, G = 500 }, { Node = G.ById.B566, G = 0 } }, G.ById.B479)
	eq(path2[1].Id, "B566")
	-- A sealed node is never a goal.
	eq(G.AStar({ { Node = G.ById.B566, G = 0 } }, G.ById.FutureDock), nil)
end)

-- YARDS ------------------------------------------------------------------------------------------
test("yard frame matches PlotAppearance / MiningWorld", function()
	for _, yard in ipairs(G.Yards) do
		local c = yard.Center
		-- MiningWorld.placement fallback: centre (+-111.5, spawn z + 18).
		local mine = G.YardPoint(yard.Id, -18, -6.5)
		near(mine.X, (c.X < 0 and -1 or 1) * 111.5, 1e-6, "mining X yard " .. yard.Id)
		near(mine.Z, c.Z + 18, 1e-6, "mining Z yard " .. yard.Id)
		-- Gate towards the inner promenade, service row outwards.
		local gate = G.YardPoint(yard.Id, 0, 60)
		truthy(math.abs(gate.X) < math.abs(c.X), "gate faces the street")
		local xp, z = G.YardLocal(yard.Id, V(gate.X, 1, gate.Z + 7))
		near(xp, -7, 1e-6, "YardLocal x'")
		near(z, 60, 1e-6, "YardLocal z")
		eq(G.YardAt(gate), yard.Id)
		eq(G.GateNode(yard.Id), "YG" .. yard.Id)
	end
	eq(G.YardAt(SPAWN), nil)
end)

-- DESTINATIONS -----------------------------------------------------------------------------------
test("every destination has a target and every target a destination", function()
	for _, entry in ipairs(D.List) do
		truthy(G.Targets[entry.Key], "target for " .. entry.Key)
		truthy(D.Categories[1].Id == entry.Category or D.Categories[2].Id == entry.Category or D.Categories[3].Id == entry.Category, entry.Key .. " category")
		truthy(type(entry.Icon) == "string" and entry.Icon ~= "", entry.Key .. " icon")
		for _, field in ipairs({ "Name", "Short", "Detail" }) do
			truthy(type(entry[field]) == "string", entry.Key .. " " .. field)
			truthy(D.Text(entry, field, "ru") ~= nil, entry.Key .. " ru " .. field)
		end
		truthy(entry.Ru and entry.ShortRu and entry.DetailRu, entry.Key .. " has Russian texts")
	end
	for key in pairs(G.Targets) do
		truthy(D.ByKey[key], "destination for target " .. key)
	end
end)

test("names, keys and the old aliases resolve", function()
	local cases = {
		["Your yard"] = "PlayerYards",
		["your yard"] = "PlayerYards",
		Factory = "DogLine",
		["THE DOG"] = "DogLine",
		["Mutation lab"] = "MutationLab",
		["DOG-O-MATIC PLAZA"] = "RewardMachine",
		["Dog Shelter"] = "Shelter",
		["Developer mailbox"] = "Feedback",
		Feedback = "Feedback",
		["Event headquarters"] = "GlobalDigSite",
		["Paw square"] = "WelcomeHub",
		["Global event"] = "GlobalDigSite",
		["DogDex museum"] = "DogDex",
		["Leaderboard Plaza"] = "DogPark",
		["Digging layers"] = "PortalRuins",
		["Paw market"] = "Shops",
		["The Void"] = "TheVoid",
		Lab = "MutationLab",
		MiningCorner = "MiningCorner",
		["mining corner"] = "MiningCorner",
		Showcase = "BestFinds",
		EQUIPMENT = "Equipment",
	}
	for name, key in pairs(cases) do
		eq(D.Resolve(name), key, name)
	end
	eq(D.Resolve("Nowhere"), nil)
	eq(D.Resolve(nil), nil)
	-- MapRouting keeps its 13 anchored places (needs workspace: read the source).
	local source = fs.readFile("src/ReplicatedStorage/MapRouting.luau")
	local count = 0
	for key in string.gmatch(source, "{Key='(%w+)'") do
		count += 1
		truthy(D.ByKey[key], "MapRouting key in Destinations: " .. key)
	end
	eq(count, 13, "MapRouting.Locations")
end)

test("old callers' names all reach a destination", function()
	-- Every literal passed to Navigate / navigate / c.Go / Destination= in the client.
	local names = {}
	local function scan(dir)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				scan(path)
			elseif string.find(entry, "%.luau$") then
				local text = fs.readFile(path)
				for _, pattern in ipairs({ "[Nn]avigate%(['\"]([^'\"]+)['\"]%)", "c%.Go%(['\"]([^'\"]+)['\"]%)", "Destination=['\"]([^'\"]+)['\"]", "signal:Fire%(['\"]([^'\"]+)['\"]%)" }) do
					for name in string.gmatch(text, pattern) do
						names[name] = path
					end
				end
			end
		end
	end
	scan("src/StarterGui")
	local count = 0
	for name, path in pairs(names) do
		count += 1
		truthy(D.Resolve(name), "unresolved destination '" .. name .. "' in " .. path)
	end
	truthy(count >= 6, "callers found: " .. count)
end)

-- ROUTES -----------------------------------------------------------------------------------------
local function checkRoute(route, label)
	truthy(route, label .. ": no route")
	truthy(#route.Points >= 2, label .. ": points")
	truthy(route.Length >= 0 and route.Length < 2500, label .. ": length " .. tostring(route.Length))
	for _, id in ipairs(route.Nodes) do
		truthy(not G.ById[id].Sealed, label .. ": through sealed " .. id)
	end
	local samples = G.Build(route.Points)
	for i, p in ipairs(samples.Positions) do
		-- The start may stand inside a hall or on the tongue: judge from the second sample on.
		if i > 1 then
			local b = G.BlockerAt(p, 0)
			if b and not G.BlockerAt(route.Points[1], 0) then
				error(label .. string.format(": sample %d (%.1f, %.1f) inside %s", i, p.X, p.Z, b.Name))
			end
		end
	end
	return samples
end

test("every destination is reachable from the spawn", function()
	for _, entry in ipairs(D.List) do
		if not entry.Sealed then
			local route = plan(SPAWN, entry.Key, 1)
			checkRoute(route, "spawn>" .. entry.Key)
		end
	end
end)

test("every destination is reachable from every yard spawn and yard interior point", function()
	local total = 0
	for _, yard in ipairs(G.Yards) do
		local starts = { yardSpawn(yard.Id) }
		for _, pair in ipairs(YARD_POINTS) do
			table.insert(starts, G.YardPoint(yard.Id, pair[1], pair[2]))
		end
		for si, from in ipairs(starts) do
			for _, entry in ipairs(D.List) do
				if not entry.Sealed then
					-- Plot places of this yard and of a neighbour yard.
					for _, yid in ipairs({ yard.Id, yard.Id % 8 + 1 }) do
						local route = plan(from, entry.Key, yid)
						checkRoute(route, string.format("yard%d/%d>%s(y%d)", yard.Id, si, entry.Key, yid))
						total += 1
					end
				end
			end
		end
	end
	truthy(total > 3000, "routes " .. total)
end)

test("routes from inside buildings and odd corners", function()
	for i, from in ipairs(EXTRA) do
		for _, entry in ipairs(D.List) do
			if not entry.Sealed then
				checkRoute(plan(from, entry.Key, 3), "extra" .. i .. ">" .. entry.Key)
			end
		end
	end
end)

test("sealed places are never routed", function()
	for _, key in ipairs({ "GlobalDigSite", "TheVoid" }) do
		local route, reason = plan(SPAWN, key, 1)
		eq(route, nil, key)
		eq(reason, "sealed", key)
	end
	-- Nothing goes through the global dig cube or its sealed dock.
	local route = plan(V(30, 0.5, 600), "RewardMachine", 1)
	checkRoute(route, "nearSealed>RewardMachine")
	for _, id in ipairs(route.Nodes) do
		truthy(id ~= "FutureDock", "sealed dock used")
	end
	-- Yard places need a yard.
	eq(G.Target("MiningCorner", {}), nil)
	-- Far away (The Void island): no street within reach.
	local far, why = plan(V(700, 117, -633), "MutationLab", 1)
	eq(far, nil)
	eq(why, "far")
end)

test("plot routes end inside the right yard", function()
	for _, yard in ipairs(G.Yards) do
		for _, key in ipairs({ "PlayerYards", "MyKennels", "MiningCorner", "MineElevator", "BestFinds", "Collector" }) do
			local route = plan(SPAWN, key, yard.Id)
			eq(G.YardAt(route.Goal), yard.Id, key .. " goal yard " .. yard.Id)
			eq(route.Nodes[#route.Nodes], "YG" .. yard.Id, key .. " enters through the gate")
		end
	end
end)

test("lab and museum routes walk through the door to the console / desk", function()
	local lab = plan(SPAWN, "MutationLab", 1)
	local throughDoor = false
	for i = 2, #lab.Points do
		local a, b = lab.Points[i - 1], lab.Points[i]
		if (a.X - 84) * (b.X - 84) <= 0 then
			local t = (84 - a.X) / (b.X - a.X)
			local z = a.Z + (b.Z - a.Z) * t
			throughDoor = z > 467 and z < 487
		end
	end
	truthy(throughDoor, "lab route crosses X 84 at the glass door")
	near(lab.Goal.X, 110, 0.01, "lab goal before the console")
	near(lab.Pointer.X, 114, 0.01, "pointer at the console")
	local museum = plan(SPAWN, "DogDex", 1)
	truthy(museum.Goal.X < -85 and museum.Goal.Y > 3.5, "museum route goes up the stairs to the reception")
end)

-- ENTRY SELECTION --------------------------------------------------------------------------------
test("nearest entry: project onto the street, never walk back to a node", function()
	-- Beside the boulevard between two junctions: step onto it right there.
	local route = plan(V(12, 0.5, 300), "MutationLab", 1)
	local entry = route.Points[2]
	near(entry.X, 0, 0.01, "entry on the boulevard centre line")
	near(entry.Z, 300, 0.01, "entry level with the player")
	-- Inside the lab: leave through the door, not through a wall.
	local out = plan(V(100, 2.2, 470), "Shelter", 1)
	local a, b = out.Points[1], out.Points[2]
	local t = (84 - a.X) / (b.X - a.X)
	local z = a.Z + (b.Z - a.Z) * t
	truthy(t > 0 and t <= 1 and z > 467 and z < 487, string.format("leaves through the door (z %.1f)", z))
	-- The client's line-of-sight check can veto the nearest street.
	local target = G.Target("DogDex")
	local vetoed = G.Plan(V(12, 0.5, 300), target, {
		Visible = function(_, p)
			return not (math.abs(p.X) < 0.01 and math.abs(p.Z - 300) < 0.01)
		end,
	})
	truthy(vetoed and (math.abs(vetoed.Points[2].X) > 0.01 or math.abs(vetoed.Points[2].Z - 300) > 0.01), "veto respected")
	-- Inside the own yard: walk straight to a visible plot place, no detour through the gate.
	local inYard = plan(G.YardPoint(4, 0, 30), "MiningCorner", 4)
	eq(#inYard.Nodes, 0, "direct inside the yard")
	truthy(inYard.Length < 60, "short " .. inYard.Length)
	-- On the promenade in front of a yard: the fence forces the gate.
	local fence = plan(V(-34, 0.3, 117 + 25), "MyKennels", 4)
	truthy(G.SegmentClear(fence.Points[1], fence.Points[2], 0, true), "no fence crossing")
end)

-- SMOOTHING / RESAMPLING ---------------------------------------------------------------------------
test("filleting rounds corners and keeps samples evenly spaced", function()
	local corner = { V(0, 0, 0), V(0, 0, 40), V(40, 0, 40) }
	local dense = G.Smooth(corner, 5)
	-- The corner vertex is cut: the closest dense point is ~ r(sqrt2 - 1) away.
	local closest = math.huge
	for _, p in ipairs(dense) do
		closest = math.min(closest, (p - V(0, 0, 40)).Magnitude)
	end
	near(closest, 5 * (math.sqrt(2) - 1), 0.1, "fillet depth")
	local samples = G.Resample(dense, 2)
	local n = #samples.Positions
	for i = 1, n - 1 do
		near(samples.Distances[i], (i - 1) * 2, 1e-6, "arc distance")
		local gap = (samples.Positions[i + 1] - samples.Positions[i]).Magnitude
		if i < n - 1 then
			near(gap, 2, 0.05, "spacing at " .. i)
		end
		local turn = math.deg(math.acos(math.clamp(samples.Tangents[i]:Dot(samples.Tangents[i + 1]), -1, 1)))
		truthy(turn < 30, "tangent jump " .. turn)
	end
	near(samples.Length, 80 - 2 * 5 + 5 * math.pi / 2, 0.05, "length of the filleted L")
	-- Real routes too.
	for _, key in ipairs({ "MutationLab", "Collector", "DogPark", "Shelter" }) do
		local route = plan(yardSpawn(6), key, 6)
		local s = G.Build(route.Points)
		for i = 1, #s.Positions - 2 do
			near((s.Positions[i + 1] - s.Positions[i]).Magnitude, 2, 0.1, key .. " spacing " .. i)
		end
		near(s.Distances[#s.Distances], s.Length, 1e-6, key .. " last sample at the end")
	end
end)

test("tight corners clamp the fillet radius", function()
	local dense = G.Smooth({ V(0, 0, 0), V(0, 0, 4), V(4, 0, 4) }, 5)
	for _, p in ipairs(dense) do
		truthy(p.X >= -1e-6 and p.Z <= 4 + 1e-6, "arc stays inside the corner")
	end
	-- Straight lines are left alone; Y follows the slope.
	local straight = G.Smooth({ V(0, 0, 0), V(0, 1, 10), V(0, 2, 20) }, 5)
	eq(#straight, 3)
end)

test("locate and point-at on the samples", function()
	local s = G.Build({ V(0, 0, 0), V(0, 0, 50), V(50, 0, 50) })
	local d, lateral, i = G.Locate(s, V(3, 0, 20), 1)
	near(d, 20, 0.01, "arc length")
	near(lateral, 3, 0.01, "lateral")
	truthy(i >= 1, "index")
	local p, t = G.PointAt(s, 10)
	near(p.Z, 10, 0.01)
	near(t.Z, 1, 0.01)
	-- A wrong hint still finds the global closest point.
	local d2 = G.Locate(s, V(40, 0, 52), 1)
	truthy(d2 > 80, "global fallback " .. d2)
end)

-- ARROW FLOW ---------------------------------------------------------------------------------------
test("arrow flow: window, budget, motion, reduced motion", function()
	local cfg = F.Config()
	for _, t in ipairs({ 0, 0.4, 1.7, 33.3 }) do
		local list = F.Layout(400, 50, t, cfg)
		truthy(#list > 0 and #list <= cfg.Max, "count " .. #list)
		for i, a in ipairs(list) do
			truthy(a.S >= 50 + cfg.Near - 1e-6 and a.S <= 50 + cfg.Far + 1e-6, "inside the window " .. a.S)
			truthy(a.Alpha >= 0 and a.Alpha <= 1 and a.Glow >= 0 and a.Glow <= 1, "ranges")
			if i > 1 then
				near(a.S - list[i - 1].S, cfg.Spacing, 1e-6, "spacing")
			end
		end
	end
	-- The lattice glides forward with time.
	local a0 = F.Layout(400, 50, 0, cfg)[1].S
	local a1 = F.Layout(400, 50, 0.25, cfg)[1].S
	near((a1 - a0) % cfg.Spacing, (0.25 * cfg.Speed) % cfg.Spacing, 1e-6, "phase")
	-- Near the goal: arrows stop EndGap short of it.
	for _, a in ipairs(F.Layout(100, 60, 3, cfg)) do
		truthy(a.S <= 100 - cfg.EndGap + 1e-6, "end gap")
	end
	eq(#F.Layout(100, 99, 0, cfg), 0, "nothing left to draw at the goal")
	-- Reduced motion: fixed lattice, constant glow.
	local still = F.Config({ Static = true })
	local s1, s2 = F.Layout(300, 20, 0, still), F.Layout(300, 20, 5.5, still)
	eq(#s1, #s2)
	for i = 1, #s1 do
		eq(s1[i].S, s2[i].S)
		eq(s1[i].Glow, s2[i].Glow)
		near(s1[i].S % still.Spacing, 0, 1e-9, "lattice fixed to the route")
	end
	-- Low quality: fewer arrows. Pool budget: <= 40 parts (2 per arrow + 4 for the pointer).
	local low = F.Config(F.Low)
	truthy(#F.Layout(1000, 0, 0, low) <= 8, "low quality")
	truthy(F.Defaults.Max * 2 + 4 <= 40, "part budget")
end)

-- LOCALIZATION -------------------------------------------------------------------------------------
test("every destination name and subtitle has Russian", function()
	local dict = L.Require("ReplicatedStorage.Localization.Navigation")
	local base = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	local known = {}
	for en, ru in string.gmatch(base, '%["(.-)"%]%s*=%s*"(.-)"') do
		known[en] = ru
	end
	for _, entry in ipairs(D.List) do
		for _, field in ipairs({ "Name", "Detail" }) do
			local en = entry[field]
			truthy(dict.Exact[en] or known[en] or en == D.Text(entry, field, "ru"), "Russian for " .. en)
		end
	end
	for en, ru in pairs(dict.Exact) do
		truthy(known[en] == nil or known[en] == ru, "Navigation dictionary contradicts the base entry " .. en)
	end
	eq(D.Text(D.ByKey.MutationLab, "Short", "ru"), "ЛАБА")
	eq(D.Text(D.ByKey.MutationLab, "Short", "en"), "LAB")
end)

-- PLACE GEOMETRY -------------------------------------------------------------------------------------
-- The graph and the routes against the real place: every node stands on a walkable surface and no
-- edge passes within 0.9 stud of a solid part at body height (the lab's automatic glass door opens).
local PLACE = "build/DOGROTS_MINING.rbxl"
if fs.isFile(PLACE) then
	local game = roblox.deserializePlace(fs.readFile(PLACE))
	local district = game:GetService("Workspace"):FindFirstChild("DOGROTS_District")
	local boxes, grid, CELL = {}, {}, 16
	for _, part in ipairs(district:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			local cf = part.CFrame
			local size = part.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ey = math.abs(r.Y) * size.X / 2 + math.abs(u.Y) * size.Y / 2 + math.abs(l.Y) * size.Z / 2
			local p = cf.Position
			if p.Y - ey < 14 and p.Y + ey > -1 and not string.find(part:GetFullName(), "TheVoid", 1, true) then
				-- Horizontal footprint: the two axes closest to horizontal.
				local axes = { { r, size.X }, { u, size.Y }, { l, size.Z } }
				table.sort(axes, function(a, b)
					return math.abs(a[1].Y) < math.abs(b[1].Y)
				end)
				local function dir(v)
					local m = math.sqrt(v.X * v.X + v.Z * v.Z)
					return m > 1e-6 and { v.X / m, v.Z / m } or { 1, 0 }
				end
				local b = {
					Name = part:GetFullName(),
					C = { p.X, p.Z },
					D1 = dir(axes[1][1]),
					D2 = dir(axes[2][1]),
					H1 = axes[1][2] / 2 * math.sqrt(axes[1][1].X ^ 2 + axes[1][1].Z ^ 2),
					H2 = axes[2][2] / 2 * math.sqrt(axes[2][1].X ^ 2 + axes[2][1].Z ^ 2),
					Y0 = p.Y - ey,
					Y1 = p.Y + ey,
				}
				table.insert(boxes, b)
				local reach = math.sqrt(b.H1 ^ 2 + b.H2 ^ 2)
				for gx = math.floor((p.X - reach) / CELL), math.floor((p.X + reach) / CELL) do
					for gz = math.floor((p.Z - reach) / CELL), math.floor((p.Z + reach) / CELL) do
						local key = gx .. ":" .. gz
						grid[key] = grid[key] or {}
						table.insert(grid[key], b)
					end
				end
			end
		end
	end
	local function distance(b, x, z)
		local dx, dz = x - b.C[1], z - b.C[2]
		local a = math.abs(dx * b.D1[1] + dz * b.D1[2]) - b.H1
		local c = math.abs(dx * b.D2[1] + dz * b.D2[2]) - b.H2
		return math.sqrt(math.max(0, a) ^ 2 + math.max(0, c) ^ 2)
	end
	local function cellOf(x, z)
		return grid[math.floor(x / CELL) .. ":" .. math.floor(z / CELL)] or {}
	end
	local function ground(x, z, y)
		local best = 0
		for _, b in ipairs(cellOf(x, z)) do
			if b.Y1 <= y + 2.6 and b.Y1 > best and distance(b, x, z) <= 0 then
				best = b.Y1
			end
		end
		return best
	end
	local function obstacle(x, z, y, clearance)
		local g = ground(x, z, y)
		for _, b in ipairs(cellOf(x, z)) do
			if b.Y1 > g + 0.9 and b.Y0 < g + 5.5 and distance(b, x, z) < clearance and not string.find(b.Name, "AutomaticDoor", 1, true) then
				return b, g
			end
		end
		return nil, g
	end
	local function walk(a, b, label, clearance)
		local n = math.max(1, math.floor(flat(a, b) / 0.5))
		for k = 0, n do
			local t = k / n
			local x, z, y = a.X + (b.X - a.X) * t, a.Z + (b.Z - a.Z) * t, a.Y + (b.Y - a.Y) * t
			local hit = obstacle(x, z, y, clearance)
			if hit then
				error(string.format("%s passes %.2f studs from %s at (%.1f, %.1f)", label, distance(hit, x, z), hit.Name, x, z))
			end
		end
	end

	test("place: every node stands on a walkable surface", function()
		for _, node in ipairs(G.Nodes) do
			local g = ground(node.Pos.X, node.Pos.Z, node.Pos.Y)
			truthy(math.abs(g - node.Pos.Y) <= 0.75, string.format("%s Y %.2f, ground %.2f", node.Id, node.Pos.Y, g))
		end
	end)

	test("place: graph edges keep clear of solid parts", function()
		for _, edge in ipairs(G.Edges) do
			walk(edge.A.Pos, edge.B.Pos, edge.A.Id .. "-" .. edge.B.Id, 0.9)
		end
	end)

	test("place: routes from the spawn and the yards keep clear of solid parts", function()
		local starts = { SPAWN, yardSpawn(1), yardSpawn(6), G.YardPoint(3, -18, -6.5), V(100, 2.2, 470) }
		for si, from in ipairs(starts) do
			for _, entry in ipairs(D.List) do
				if not entry.Sealed then
					local route = plan(from, entry.Key, si % 8 + 1)
					local s = G.Build(route.Points)
					for i = 2, #s.Positions do
						walk(s.Positions[i - 1], s.Positions[i], "start" .. si .. ">" .. entry.Key, 0.7)
					end
				end
			end
		end
	end)
else
	print("(skipped the place geometry checks: " .. PLACE .. " not built)")
end

print(string.format("navigation: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("navigation tests failed")
end
