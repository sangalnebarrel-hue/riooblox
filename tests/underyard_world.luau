--!nocheck
-- THE UNDERYARD world framework (WP-G): lune run tests/underyard_world.luau
-- Builds 40_Underyard offline from src/ (tests/lib/underyard_env: the real builder modules + tools/edits/40_underyard.luau
-- in a fresh DataModel) and checks the builder contract of DESIGN §7 / §22.6: budgets, anchoring, anchors, gameplay
-- points kept clear and standing on floor, colliders sealing every walkable edge, seal-state tags, gate signs, the
-- coffin seat, FX markers, bilingual signs, determinism, plus the UKit geometry helpers.
local E = require("./lib/underyard_env")
local roblox = require("@lune/roblox")
local Sim = require("../tools/sim")
local V3 = roblox.Vector3.new
local CF = roblox.CFrame
local Enum = roblox.Enum

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

local game, report = E.Build()
local root = E.Root(game)
local sim = Sim.new(game)
local L = sim:require(game:GetService("ReplicatedStorage").Halloween.UnderyardLayout)
local U = sim:require(game:GetService("ServerStorage").UnderyardBuild.UKit)
local MINE = { "Ground", "Sky", "Roads", "BellSquare", "Gates", "FXMarkers" }

local function count(inst)
	local parts, lights = 0, 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	return parts, lights
end

-- all parts of WP-G models (anchors excluded)
local ALL = {}
for _, name in MINE do
	local m = root:FindFirstChild(name)
	if m then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(ALL, d)
			end
		end
	end
end

-- point inside a part (box / wedge / cylinder / ball / sphere-mesh ellipsoid), with an optional pad
local function inside(part, p, pad)
	pad = pad or 0
	local lp = part.CFrame:Inverse() * p
	local s = part.Size / 2
	local x, y, z = lp.X, lp.Y, lp.Z
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if part.ClassName == "Part" and part.Shape == Enum.PartType.Ball then
		return lp.Magnitude <= s.X + pad
	end
	if mesh and mesh.MeshType == Enum.MeshType.Sphere then
		local ex, ey, ez = (s.X + pad), (s.Y + pad), (s.Z + pad)
		return (x / ex) ^ 2 + (y / ey) ^ 2 + (z / ez) ^ 2 <= 1
	end
	if part.ClassName == "Part" and part.Shape == Enum.PartType.Cylinder then
		return math.abs(x) <= s.X + pad and (y * y + z * z) <= (s.Y + pad) ^ 2
	end
	if math.abs(x) > s.X + pad or math.abs(y) > s.Y + pad or math.abs(z) > s.Z + pad then
		return false
	end
	if part.ClassName == "WedgePart" then
		-- vertical face at +Z, slope from (y -sy, z -sz) up to (y +sy, z +sz)
		local t = (z + s.Z) / (2 * s.Z)
		return y <= -s.Y + 2 * s.Y * t + pad
	end
	return true
end

-- spatial index over the WP-G parts (16-stud XZ cells, each part filed in every cell its bounding sphere touches)
local CELL = 16
local GRID = {}
local function cellKey(ix, iz)
	return ix * 100000 + iz
end
for _, part in ALL do
	local pos = part.CFrame.Position
	local r = (part.Size / 2).Magnitude + 1
	for ix = math.floor((pos.X - r) / CELL), math.floor((pos.X + r) / CELL) do
		for iz = math.floor((pos.Z - r) / CELL), math.floor((pos.Z + r) / CELL) do
			local k = cellKey(ix, iz)
			GRID[k] = GRID[k] or {}
			table.insert(GRID[k], part)
		end
	end
end
local function near(p)
	return GRID[cellKey(math.floor(p.X / CELL), math.floor(p.Z / CELL))] or {}
end

local function solidAt(p, pad)
	for _, part in near(p) do
		if part.CanCollide and inside(part, p, pad) then
			return part
		end
	end
	return nil
end

local function visibleAt(p)
	for _, part in near(p) do
		if (part.Transparency < .98 or part.CanCollide) and inside(part, p) then
			return part
		end
	end
	return nil
end

local function colliderAt(p)
	for _, part in near(p) do
		if part.CanCollide and part.Transparency >= 1 and inside(part, p) then
			return part
		end
	end
	return nil
end

-- floor under a point: a solid part containing (x, y - .15, z) (or just below: sloped decks)
local function floorAt(p)
	return solidAt(p - V3(0, .15, 0)) or solidAt(p - V3(0, .4, 0))
end

------------------------------------------------------------------------------------------------------------------
test("every WP-G builder ran and made its model", function()
	local seen = {}
	for _, b in report.Builders do
		seen[b.Name] = b
	end
	for _, name in MINE do
		assert(seen[name], "builder " .. name .. " did not run")
		assert(root:FindFirstChild(name), "model " .. name .. " missing")
	end
	assert(not seen.UKit, "UKit must not run as a builder")
end)

test("budgets: <= 9500 parts / 90 lights for WP-G, BellSquare <= 5000 / 50, Roads <= 40 lights, zone <= 26000 / 250", function()
	local tp, tl = 0, 0
	for _, name in MINE do
		local p, l = count(root[name])
		tp += p
		tl += l
	end
	assert(tp <= 9500, "WP-G parts " .. tp)
	assert(tl <= 90, "WP-G lights " .. tl)
	local bp, bl = count(root.BellSquare)
	assert(bp <= 5000 and bl <= 50, string.format("BellSquare %d parts %d lights", bp, bl))
	local _, rl = count(root.Roads)
	assert(rl <= 40, "Roads lights " .. rl)
	local zp, zl = count(root)
	assert(zp <= 26000 and zl <= 250, string.format("zone %d parts %d lights", zp, zl))
	print(string.format("  WP-G: %d parts, %d lights (BellSquare %d / %d)", tp, tl, bp, bl))
end)

test("everything anchored, lights shadowless, invisible parts never cast shadows", function()
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			assert(d.Anchored, d:GetFullName() .. " unanchored")
			if d.Transparency >= 1 then
				assert(not d.CastShadow, d:GetFullName() .. " invisible but casts a shadow")
			end
		elseif d:IsA("Light") then
			assert(d.Shadows == false, d:GetFullName() .. " has shadows")
		end
	end
end)

test("every layout anchor exists as an invisible 1x1 part at its exact position", function()
	local anchors = root:FindFirstChild("Anchors")
	assert(anchors, "Anchors model missing")
	local n = 0
	for name, pos in pairs(L.Anchors) do
		local a = anchors:FindFirstChild(name)
		assert(a, "anchor " .. name .. " missing")
		assert((a.CFrame.Position - pos).Magnitude < 1e-3, "anchor " .. name .. " moved")
		assert(a.Transparency == 1 and not a.CanCollide, "anchor " .. name .. " visible / solid")
		n += 1
	end
	assert(n >= 100, "anchors " .. n)
end)

-- gameplay points that must stay clear: Strike targets / spawn / prompts in the square and on the roads
local CLEAR = {}
local KNOWN_CONFLICT = {
	-- UnderyardLayout puts this resonant echo 0.25 studs past the Black Coffin's foot end (coffin space x -47.75..-40.25):
	-- the coffin itself (WP-K) and its bier cover it whatever the shrine looks like; reported to the integrator.
	ResonantEcho_5 = true,
}
local ANCHOR_UP = { ChoirPath = 3, ContractsBoard = 3, TollBox = 3, Tailor = 3, Arrival = 3.2, ReturnPortal = 3 }
for name, pos in pairs(L.Anchors) do
	local inSquare = (V3(pos.X, 0, pos.Z) - V3(L.Centre.X, 0, L.Centre.Z)).Magnitude < 100
	local kind = name:match("^(%a+)_") or name
	if inSquare and not KNOWN_CONFLICT[name] and (kind == "EchoPoint" or kind == "TutorialEcho" or kind == "ResonantEcho" or kind == "ChoirPath"
		or name == "Arrival" or name == "ReturnPortal" or name == "ContractsBoard" or name == "TollBox" or name == "Tailor") then
		table.insert(CLEAR, { Name = name, Pos = pos, Floor = pos.Y - (ANCHOR_UP[kind] or 0) })
	end
end

test("gameplay points in the square / on the roads are clear (no solid or visible prop within 1.5 studs, 0.4..6 above the floor)", function()
	assert(#CLEAR >= 30, "too few points " .. #CLEAR)
	for _, g in CLEAR do
		-- TutorialEcho_2 is 2.9 studs from Seal Altar II's centre in the layout: checked with a 1.0 radius
		local r = g.Name == "TutorialEcho_2" and 1.0 or 1.5
		for _, dy in { .5, 1.5, 3, 5 } do
			for _, off in { V3(0, 0, 0), V3(r, 0, 0), V3(-r, 0, 0), V3(0, 0, r), V3(0, 0, -r) } do
				local p = V3(g.Pos.X, g.Floor + dy, g.Pos.Z) + off
				local hit = visibleAt(p)
				assert(not hit, g.Name .. " blocked by " .. (hit and hit:GetFullName() or ""))
			end
		end
	end
end)

test("gameplay points stand on solid floor at their height", function()
	for _, g in CLEAR do
		local p = V3(g.Pos.X, g.Floor, g.Pos.Z)
		assert(floorAt(p), g.Name .. " has no floor")
		assert(not solidAt(p + V3(0, .45, 0)), g.Name .. " floor too high")
	end
	for _, name in { "MineEntrance" } do
		local pos = L.Anchors[name]
		assert(floorAt(V3(pos.X, 0, pos.Z)), name .. " (Undercrypt base at y 0 round the entrance) has no floor")
	end
end)

-- march from a floor point in a flat direction: hitting a collider is fine, walking off the floor is not
local function sealed(from, dir, maxDist, label)
	local d = V3(dir.X, 0, dir.Z).Unit
	for s = 0, maxDist, .5 do
		local p = from + d * s
		if colliderAt(p + V3(0, 3, 0)) or colliderAt(p + V3(0, 8, 0)) then
			return
		end
		if not floorAt(p) and not solidAt(p + V3(0, .6, 0)) and not solidAt(p - V3(0, 1.2, 0)) then
			-- the floor ends here: a collider must close the gap within 1.5 studs (narrower than a player)
			for k = .25, 1.5, .25 do
				if colliderAt(p + d * k + V3(0, 3, 0)) then
					return
				end
			end
			error(string.format("%s: walked off the floor at (%.1f, %.1f, %.1f) without a collider", label, p.X, p.Y, p.Z))
		end
	end
	error(label .. ": no collider within " .. maxDist)
end

test("the central island rim is sealed except at the five bridges", function()
	local c = L.Centre
	local bridges = 0
	for k = 0, 179 do
		local a = k / 180 * math.pi * 2
		local out = V3(math.sin(a), 0, -math.cos(a))
		local from = V3(c.X, 0, c.Z) + out * 85
		-- a bridge leaves here when the floor continues past the rim (spoke deck / arena approach)
		if floorAt(V3(c.X, 0, c.Z) + out * 91.5) then
			bridges += 1
		else
			sealed(from, out, 12, string.format("rim at %.0f deg", math.deg(a)))
		end
	end
	assert(bridges > 5, "expected the bridge corridors to show up, got " .. bridges)
end)

test("bridges and the arena approach are sealed on both sides and >= 8 wide", function()
	local c = L.Centre
	for name, g in pairs(L.Gates) do
		local u = V3(g.Position.X - c.X, 0, g.Position.Z - c.Z).Unit
		local n = V3(-u.Z, 0, u.X)
		if name ~= "BlackBellArena" then
			for _, t in { 90, 96, 104 } do
				local mid = V3(c.X, 0, c.Z) + u * t
				local y = (name == "MourningMarsh" and t > 102) and L.Marsh.GroundY or 0
				mid = V3(mid.X, y, mid.Z)
				assert(floorAt(mid), name .. " bridge has no deck at t " .. t)
				for _, side in { -1, 1 } do
					sealed(mid, n * side, 13, name .. " bridge side " .. side .. " at t " .. t)
				end
				for off = -4, 4 do
					assert(floorAt(mid + n * off) and not solidAt(mid + n * off + V3(0, 2, 0)), name .. " bridge walkway blocked at offset " .. off)
				end
			end
		end
	end
	local Roads = sim:require(game:GetService("ServerStorage").UnderyardBuild.Roads)
	local path = Roads.ApproachPath(L)
	local samples = U.Sample(path, 6, 6)
	local prevTop
	for i, smp in samples do
		if i > 1 and i < #samples then
			-- deck height at this point: highest solid under y 9
			local base = V3(smp.Pos.X, 0, smp.Pos.Z)
			local y, deckPart
			for yy = 9, -1, -.1 do
				local hit = solidAt(base + V3(0, yy, 0))
				if hit and hit.Transparency < 1 then
					y, deckPart = yy, hit
					break
				end
			end
			assert(deckPart == nil or deckPart.Name:match("^ApproachDeck") or deckPart.Name:match("Landing") or deckPart.Name:match("Floor"),
				"approach centre blocked by " .. (deckPart and deckPart:GetFullName() or "") .. " at sample " .. i)
			-- the deck follows the crest-and-descent profile: no bumps or dips (heights at +-6 across agree too)
			local function topAt(q)
				for yy = 9, -1, -.05 do
					local hit = solidAt(q + V3(0, yy, 0))
					if hit and hit.Transparency < 1 then
						return yy
					end
				end
				return nil
			end
			local right0 = V3(-smp.Dir.Z, 0, smp.Dir.X)
			for _, off in { -6, 6 } do
				local t2 = topAt(base + right0 * off)
				assert(t2 and y and math.abs(t2 - y) < .6, string.format("approach deck uneven across at sample %d (%.2f vs %.2f)", i, t2 or -99, y or -99))
			end
			if prevTop then
				assert(math.abs(y - prevTop) < 6 * math.tan(math.rad(32)), "approach deck too steep at sample " .. i)
			end
			prevTop = y
			assert(y, "approach has no deck at sample " .. i)
			local top = base + V3(0, y + .12, 0)
			local right = V3(-smp.Dir.Z, 0, smp.Dir.X)
			for _, side in { -1, 1 } do
				sealed(top, right * side, 12, "approach side " .. side .. " at sample " .. i)
			end
			for off = -4, 4 do
				assert(not solidAt(top + right * off + V3(0, 2.2, 0)), "approach walkway blocked at sample " .. i .. " offset " .. off)
			end
		end
	end
	assert((path[1] - V3(L.Arena.Approach.From.X, 0, L.Arena.Approach.From.Z)).Magnitude < 6, "approach does not start at the arena gate")
	assert((path[#path] - V3(L.Arena.Approach.To.X, 0, L.Arena.Approach.To.Z)).Magnitude < 8, "approach does not end at the arena edge")
end)

-- inside a spoke bridge's corridor (where it joins a district floor, the floor legitimately continues)
local function nearBridge(p)
	local c = L.Centre
	for name, g in pairs(L.Gates) do
		if name ~= "BlackBellArena" then
			local u = V3(g.Position.X - c.X, 0, g.Position.Z - c.Z).Unit
			local rel = V3(p.X - c.X, 0, p.Z - c.Z)
			local along = rel:Dot(u)
			local across = math.abs(rel:Dot(V3(-u.Z, 0, u.X)))
			if along > 80 and along < 135 and across < 14 then
				return true
			end
		end
	end
	return false
end

test("district floors cover their boxes at the right height and their inner edges are sealed", function()
	for _, d in L.Districts do
		if d.Kind == "Box" and d.Name ~= "BlackBellArena" then
			local y = d.Name == "MourningMarsh" and L.Marsh.GroundY or 0
			local hole = function(x, z)
				if d.Name ~= "Undercrypt" then
					return false
				end
				local F = L.Undercrypt.Floor
				if x > F.Min.X - 1 and x < F.Max.X + 1 and z > F.Min.Z - 1 and z < F.Max.Z + 1 then
					return true
				end
				local a, b = L.Undercrypt.RampTop, L.Undercrypt.RampBottom
				local dd = V3(b.X - a.X, 0, b.Z - a.Z).Unit
				local rel = V3(x - a.X, 0, z - a.Z)
				local along = rel:Dot(dd)
				local across = math.abs(rel:Dot(V3(dd.Z, 0, -dd.X)))
				return along > -3 and along < (b - a).Magnitude + 6 and across < 7
			end
			for x = d.Min.X + 2, d.Max.X - 2, 9 do
				for z = d.Min.Z + 2, d.Max.Z - 2, 9 do
					if not hole(x, z) then
						local p = V3(x, y, z)
						assert(floorAt(p), d.Name .. string.format(" floor missing at (%d, %d)", x, z))
						assert(not solidAt(p + V3(0, .5, 0)), d.Name .. string.format(" floor not flat at (%d, %d)", x, z))
					end
				end
			end
			-- inner edges: march outward from 2 studs inside the edge
			local B = L.Bounds
			local sides = {
				{ d.Min.X > B.X0 + .5, function(t)
					return V3(d.Min.X + 2, y, d.Min.Z + t * (d.Max.Z - d.Min.Z))
				end, V3(-1, 0, 0) },
				{ d.Max.X < B.X1 - .5, function(t)
					return V3(d.Max.X - 2, y, d.Min.Z + t * (d.Max.Z - d.Min.Z))
				end, V3(1, 0, 0) },
				{ d.Min.Z > B.Z0 + .5, function(t)
					return V3(d.Min.X + t * (d.Max.X - d.Min.X), y, d.Min.Z + 2)
				end, V3(0, 0, -1) },
				{ d.Max.Z < B.Z1 - .5, function(t)
					return V3(d.Min.X + t * (d.Max.X - d.Min.X), y, d.Max.Z - 2)
				end, V3(0, 0, 1) },
			}
			for _, sd in sides do
				if sd[1] then
					for t = .02, .98, .04 do
						local p = sd[2](t)
						if not hole(p.X, p.Z) and not nearBridge(p) then
							sealed(p, sd[3], 14, d.Name .. " edge")
						end
					end
				end
			end
		end
	end
end)

test("the Bounds are walled by 60-tall colliders down to the catch floor, the catch floor spans the zone", function()
	local B = L.Bounds
	for _, y in { -30, 5, 30, 59 } do
		for x = B.X0, B.X1, 12 do
			assert(colliderAt(V3(x, y, B.Z0 - .5)), "north bound open at x " .. x .. " y " .. y)
			assert(colliderAt(V3(x, y, B.Z1 + .5)), "south bound open at x " .. x .. " y " .. y)
		end
		for z = B.Z0, B.Z1, 12 do
			assert(colliderAt(V3(B.X0 - .5, y, z)), "west bound open at z " .. z .. " y " .. y)
			assert(colliderAt(V3(B.X1 + .5, y, z)), "east bound open at z " .. z .. " y " .. y)
		end
	end
	for x = L.Zone.Min.X, L.Zone.Max.X, 40 do
		for z = L.Zone.Min.Z, L.Zone.Max.Z, 40 do
			assert(solidAt(V3(x, -40.5, z)), string.format("catch floor missing at (%d, %d)", x, z))
		end
	end
end)

test("seal altars: ignited parts tagged UyShowAtSeal = i, socket light tagged UyLightAtSeal = i, numeral plaque", function()
	local altars = root.BellSquare:FindFirstChild("SealAltars")
	assert(altars, "SealAltars missing")
	for i = 1, 7 do
		local m = altars:FindFirstChild("SealAltar_" .. i)
		assert(m, "altar " .. i .. " missing")
		local shows, light = 0, nil
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("UyShowAtSeal") == i then
				shows += 1
			elseif d:IsA("Light") and d:GetAttribute("UyLightAtSeal") == i then
				light = d
			end
		end
		assert(shows >= 8, "altar " .. i .. " ignited parts " .. shows)
		assert(light and math.abs((light:GetAttribute("UyBaseBrightness") or 0) - light.Brightness) < 1e-4 and light.Brightness > 0, "altar " .. i .. " socket light")
		local plaque = m:FindFirstChild("AltarNumeral")
		local gui = plaque and plaque:FindFirstChildOfClass("SurfaceGui")
		assert(gui and gui:GetAttribute("NoTranslate"), "altar " .. i .. " numeral")
		local mid = (m:FindFirstChild("AltarStep") :: any).CFrame.Position
		assert((V3(mid.X, 0, mid.Z) - V3(L.SealAltars[i].X, 0, L.SealAltars[i].Z)).Magnitude < .01, "altar " .. i .. " not on its anchor")
	end
end)

test("gates: veil / chains / plaque tagged UyHideAtSeal = Unlock, bilingual SEALED sign, opening clear", function()
	local gates = root.Gates
	for name, g in pairs(L.Gates) do
		local m
		for _, ch in gates:GetChildren() do
			if ch:GetAttribute("UyGate") == name then
				m = ch
			end
		end
		assert(m, "gate " .. name .. " missing")
		local seal = L.Unlock[name]
		local hidden = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("UyHideAtSeal") ~= nil then
				assert(d:GetAttribute("UyHideAtSeal") == seal, name .. " wrong seal tag")
				assert(not d.CanCollide, name .. " veil part collides")
				hidden += 1
			end
		end
		assert(hidden >= 12, name .. " hidden parts " .. hidden)
		local sealed = false
		for _, d in m:GetDescendants() do
			if d:IsA("SurfaceGui") and d:GetAttribute("TextEN") == "SEALED" then
				assert(d:GetAttribute("TextRU") == "ЗАПЕЧАТАНО" and d:GetAttribute("NoTranslate") == true, name .. " sign attributes")
				assert(d:GetAttribute("UyHideAtSeal") == seal, name .. " sign not tagged")
				sealed = true
			end
		end
		assert(sealed, name .. " has no SEALED sign")
		-- the opening (14 wide, 0.5..10 high, 3 deep) holds nothing solid
		local base = U.K.Look(g.Position, g.Position + g.Facing)
		for x = -7, 7, 1 do
			for y = .5, 10, 1.5 do
				for z = -1.5, 1.5, 1.5 do
					local p = (base * CF.new(x, y, z)).Position
					local hit = solidAt(p)
					assert(not hit, name .. " opening blocked at " .. tostring(p) .. " by " .. (hit and hit:GetFullName() or ""))
				end
			end
		end
	end
end)

test("coffin shrine: CoffinSeat at the shrine centre, the 4 x 2.4 x 7.5 coffin space is empty, 3 chain anchors, 6 candles", function()
	local shrine = root.BellSquare:FindFirstChild("CoffinShrine")
	assert(shrine, "CoffinShrine missing")
	local seat, anchors, candles = nil, 0, 0
	for _, d in shrine:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "CoffinSeat" then
			seat = d
		elseif d:IsA("Attachment") and d.Name:match("^ChainAnchor_%d$") then
			anchors += 1
		elseif d:IsA("BasePart") and d:GetAttribute("HwCandle") then
			candles += 1
		end
	end
	assert(seat, "CoffinSeat missing")
	assert(anchors == 3, "chain anchors " .. anchors)
	assert(candles >= 6, "candles " .. candles)
	local S = L.Square.CoffinShrine
	local world = seat.Parent.CFrame * seat.CFrame
	assert((world.Position - (S.Position + V3(0, 3.2, 0))).Magnitude < .01, "CoffinSeat off centre " .. tostring(world.Position))
	assert(world.LookVector:Dot(S.LookVector) > .999, "CoffinSeat not aligned with the shrine")
	for x = -1.9, 1.9, .475 do
		for y = -1.15, 1.15, .46 do
			for z = -3.7, 3.7, .74 do
				local p = (world * CF.new(x, y, z)).Position
				local hit = visibleAt(p)
				if hit then
					error("coffin space blocked by " .. hit:GetFullName())
				end
			end
		end
	end
end)

test("arrival arch: portal swirl model + PortalCentre, the arrival spawn and its echo point are clear", function()
	local arch = root.BellSquare:FindFirstChild("ArrivalArch")
	assert(arch, "ArrivalArch missing")
	local swirl = arch:FindFirstChild("PortalSwirl")
	assert(swirl and swirl:GetAttribute("UySwirl") == true and swirl.PrimaryPart, "PortalSwirl")
	assert(swirl.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "PortalSwirl streaming mode")
	local centre = swirl.PrimaryPart:FindFirstChild("PortalCentre")
	assert(centre, "PortalCentre attachment")
	local p = (swirl.PrimaryPart.CFrame * centre.CFrame).Position
	assert(math.abs(p.X - L.ArrivalArch.X) < .5 and p.Z < L.Anchors.EchoPoint_1.Z - 3, "portal plane must stay north of EchoPoint_1")
end)

test("tower: the huge bell hangs at TowerBell inside the belfry, the tower rises to ~92+", function()
	local tower = root.BellSquare:FindFirstChild("BellTower")
	assert(tower, "BellTower missing")
	local bell = tower:FindFirstChild("TowerBellBody")
	assert(bell, "bell missing")
	local lo, hi = math.huge, -math.huge
	local sx, sz, n = 0, 0, 0
	for _, d in bell:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "BellBand" then
			local y = d.CFrame.Position.Y
			lo, hi = math.min(lo, y), math.max(hi, y)
			sx += d.CFrame.Position.X
			sz += d.CFrame.Position.Z
			n += 1
		end
	end
	local tb = L.Anchors.TowerBell
	assert(math.abs((lo + hi) / 2 - tb.Y) < 1.5, "bell centre y " .. (lo + hi) / 2)
	assert(math.abs(sx / n - tb.X) < 1 and math.abs(sz / n - tb.Z) < 1, "bell off axis")
	assert((tower:GetAttribute("BellClearance") or 0) > 1.5, "bell touches the belfry piers")
	local top = tower:GetAttribute("TowerTop") or 0
	assert(top >= 90 and top <= 110, "tower top " .. top)
	local parts = count(tower)
	assert(parts >= 900, "tower too plain: " .. parts .. " parts")
end)

test("FX markers: MothSwarm / FogPoint / WispPath / GhostResident attachments, numbered from 1", function()
	local fx = root.FXMarkers
	local found = {}
	for _, d in fx:GetDescendants() do
		if d:IsA("Attachment") then
			local kind, n = d.Name:match("^(%a+)_(%d+)$")
			assert(kind, "bad marker name " .. d.Name)
			found[kind] = found[kind] or {}
			found[kind][tonumber(n)] = true
		elseif d:IsA("BasePart") then
			assert(d.Transparency == 1 and not d.CanCollide and not d.CanQuery, "visible / solid marker holder")
		end
	end
	for kind, minimum in { MothSwarm = 8, FogPoint = 20, WispPath = 24, GhostResident = 8 } do
		local set = found[kind] or {}
		local k = 0
		while set[k + 1] do
			k += 1
		end
		assert(k >= minimum, kind .. " count " .. k)
		for idx in pairs(set) do
			assert(idx <= k, kind .. " numbering has a gap before " .. idx)
		end
	end
end)

test("world text: every sign is NoTranslate with TextEN / TextRU (or has no Latin text)", function()
	local signs = 0
	for _, name in MINE do
		for _, d in root[name]:GetDescendants() do
			if d:IsA("SurfaceGui") then
				local label = d:FindFirstChildOfClass("TextLabel")
				local text = label and label.Text or ""
				if text:match("%a") then
					assert(d:GetAttribute("NoTranslate") == true, d:GetFullName() .. " not NoTranslate")
					if not text:match("^[IVX]+$") then
						assert(d:GetAttribute("TextEN") == text and type(d:GetAttribute("TextRU")) == "string" and #d:GetAttribute("TextRU") > 0,
							d:GetFullName() .. " missing TextEN / TextRU")
						signs += 1
					end
				end
			end
		end
	end
	assert(signs >= 10, "signs " .. signs)
end)

test("deterministic: a second build is identical", function()
	local game2 = E.Build()
	local r2 = E.Root(game2)
	for _, name in MINE do
		local a, b = root[name]:GetDescendants(), r2[name]:GetDescendants()
		assert(#a == #b, name .. " descendant count differs")
		for i = 1, #a, 7 do
			if a[i]:IsA("BasePart") then
				assert(b[i]:IsA("BasePart") and (a[i].CFrame.Position - b[i].CFrame.Position).Magnitude < 1e-6, name .. " differs at " .. i)
			end
		end
	end
end)

test("UKit helpers: Polar / AngleOf round trip, Sample spacing, ArcColliders openings, Space keep-out", function()
	local c = V3(0, 0, 2400)
	for _, a in { 0, .5, 1.7, 3, 4.4, 6 } do
		local p = U.Polar(c, 40, a)
		local back = U.AngleOf(c, p) % (math.pi * 2)
		assert(math.abs(back - a % (math.pi * 2)) < 1e-4, "Polar/AngleOf")
	end
	assert((U.Polar(c, 10, 0) - V3(0, 0, 2390)).Magnitude < 1e-3, "angle 0 must be north (-Z)")
	assert((U.Polar(c, 10, math.pi / 2) - V3(10, 0, 2400)).Magnitude < 1e-3, "angle pi/2 must be east (+X)")
	local s = U.Sample({ V3(0, 0, 0), V3(10, 0, 0), V3(10, 0, 10) }, 2, 0)
	assert(#s == 11, "samples " .. #s)
	for i = 2, #s do
		assert(math.abs(s[i].S - s[i - 1].S - 2) < 1e-6, "spacing")
	end
	local holder = roblox.Instance.new("Model")
	local parts = U.ArcColliders(holder, c, 50, 0, math.pi * 2, { { Angle = 0, Half = 5 } }, 0, 10)
	-- the opening spans x -5..5 at the north; colliders cover everything else (sample the circle)
	for k = 0, 359 do
		local p = U.Polar(c, 50, math.rad(k), 5)
		local covered = false
		for _, part in parts do
			if inside(part, p, .05) then
				covered = true
			end
		end
		if math.abs(p.X) < 4.6 and p.Z < 2400 then
			assert(not covered, "opening closed at " .. k)
		elseif math.abs(p.X) > 5.4 or p.Z > 2400 then
			assert(covered, "ring open at " .. k)
		end
	end
	local space = U.Space(L)
	assert(not space:Free(L.Anchors.EchoPoint_3, 1), "echo point must be kept out")
	assert(space:Try(V3(0, 0, 2400), 3) and not space:Free(V3(1, 0, 2400), 1), "claims")
end)

print(string.format("underyard_world: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("underyard_world tests failed")
end
