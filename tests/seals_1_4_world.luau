--!nocheck
-- BELL SEALS I-IV (WP-I) against the BUILT Underyard: runs tools/edits/40_underyard.luau with every builder in
-- src/ServerStorage/UnderyardBuild through tools/sim.luau on a minimal DataModel (as tests/underyard_districts_h3.luau
-- does) and checks what the activity servers and presenters assume about the world:
--   I    echo points stand on open ground (nothing solid in the mound's column)
--   II   the RunPendulum_i hinge models match SealRules (pivot 17 above the lane, coffin centre Arm below the hinge,
--        LookVector along the lane), the hazard strip of a pass contains the coffin, the lane passes under each hinge and
--        is free of solid parts start -> ring 10 (the carousel deck aside), every arch's hoop is open at its checkpoint
--   III  the TURN (per grave) and CONSULT prompt spots of SealMirror are outside solid parts, a standing player reaches
--        each of them, there are standing spots that show ONLY one of them, the nearest standing spot of each prompt is
--        unambiguous, and every reachable prompt spot passes the server's range check
--   IV   mine nodes sit on the mine floor under the cavern ceiling the presenter drops rocks from
-- Usage: lune run tests/seals_1_4_world.luau   (DOGROTS_SRC=<dir> runs it against another src tree)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local SRC = (process.env.DOGROTS_SRC or "src"):gsub("/$", "")
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
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then
		error((msg or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function yes(v, msg)
	if not v then
		error(msg or "expected true", 2)
	end
end

local BUILDERS = {}
for _, f in fs.readDir(SRC .. "/ServerStorage/UnderyardBuild") do
	if string.sub(f, -5) == ".luau" then
		table.insert(BUILDERS, string.sub(f, 1, -6))
	end
end
table.sort(BUILDERS)

local function module(parent, name, path)
	local m = roblox.Instance.new("ModuleScript")
	m.Name = name
	m.Source = fs.readFile(path)
	m.Parent = parent
	return m
end

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
	module(hb, "Kit", SRC .. "/ServerStorage/HalloweenBuild/Kit.luau")
	module(hb, "YardKit", SRC .. "/ServerStorage/HalloweenBuild/YardKit.luau")
	local ub = roblox.Instance.new("Folder")
	ub.Name = "UnderyardBuild"
	ub.Parent = ss
	for _, n in BUILDERS do
		module(ub, n, SRC .. "/ServerStorage/UnderyardBuild/" .. n .. ".luau")
	end
	local rs = game:GetService("ReplicatedStorage")
	local hw = roblox.Instance.new("Folder")
	hw.Name = "Halloween"
	hw.Parent = rs
	module(hw, "UnderyardLayout", SRC .. "/ReplicatedStorage/Halloween/UnderyardLayout.luau")
	local sim = Sim.new(game)
	local edit = luau.load(fs.readFile("tools/edits/40_underyard.luau"), { debugName = "40_underyard" })()
	edit({ game = game, sim = sim, report = {}, roblox = roblox, fs = fs })
	return sim, district:FindFirstChild("40_Underyard"), sim:require(hw.UnderyardLayout),
		ub:FindFirstChild("FuneralCarnival") and sim:require(ub.FuneralCarnival)
end

local sim, root, Layout, Carnival = build()
-- the pure rules through the server harness (Instance:WaitForChild etc.)
local Rules = require("./lib/economy_env").Require("ReplicatedStorage.Halloween.SealRules")
assert(root, "40_Underyard was not built")
local anchors = root:FindFirstChild("Anchors")
local carnival = root:FindFirstChild("FuneralCarnival")
local marsh = root:FindFirstChild("MourningMarsh")
local crypt = root:FindFirstChild("Undercrypt")

---------------------------------------------------------------------------------------------------------------------
-- solid geometry as plain numbers: every CanCollide part's oriented box (wedges: the slope as one more half space);
-- a vertical line (x, z) meets a box in one y interval
---------------------------------------------------------------------------------------------------------------------
local SOLIDS = {}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide and not (anchors and d:IsDescendantOf(anchors)) then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
		local s = d.Size
		local hx = (math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z) / 2
		local hy = (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2
		local hz = (math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z) / 2
		table.insert(SOLIDS, {
			Part = d, P = { x, y, z }, R = { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, H = { s.X / 2, s.Y / 2, s.Z / 2 },
			Wedge = d:IsA("WedgePart"), Lo = { x - hx, y - hy, z - hz }, Hi = { x + hx, y + hy, z + hz },
		})
	end
end

-- the solids whose bounds come within `pad` of the box [x0, x1] x [y0, y1] x [z0, z1]
local function solidsNear(x0, y0, z0, x1, y1, z1, pad)
	local out = {}
	for _, s in SOLIDS do
		if s.Hi[1] >= x0 - pad and s.Lo[1] <= x1 + pad and s.Hi[2] >= y0 - pad and s.Lo[2] <= y1 + pad and s.Hi[3] >= z0 - pad
			and s.Lo[3] <= z1 + pad then
			table.insert(out, s)
		end
	end
	return out
end

-- local coordinates of a world point
local function toLocal(s, px, py, pz)
	local dx, dy, dz = px - s.P[1], py - s.P[2], pz - s.P[3]
	local R = s.R
	return R[1] * dx + R[4] * dy + R[7] * dz, R[2] * dx + R[5] * dy + R[8] * dz, R[3] * dx + R[6] * dy + R[9] * dz
end

local function inside(s, px, py, pz, shrink)
	local lx, ly, lz = toLocal(s, px, py, pz)
	local e = shrink or 0
	if math.abs(lx) > s.H[1] - e or math.abs(ly) > s.H[2] - e or math.abs(lz) > s.H[3] - e then
		return false
	end
	-- a wedge is solid under its slope: the tall face at +Z, the edge at the top of -Z ... (y + hy) / 2hy <= (z + hz) / 2hz
	return not s.Wedge or (ly + s.H[2]) / (2 * s.H[2]) <= (lz + s.H[3]) / (2 * s.H[3])
end

local function solidAt(list, px, py, pz, shrink)
	for _, s in list do
		if inside(s, px, py, pz, shrink) then
			return s.Part
		end
	end
	return nil
end

-- the y interval of the vertical line (x, z) inside solid s, or nil
local function column(s, px, pz)
	local R = s.R
	local dx, dz = px - s.P[1], pz - s.P[3]
	local lo, hi = -math.huge, math.huge
	-- local axis i: l_i(y) = a + b * (y - cy)
	local cons = {}
	for i = 1, 3 do
		local a = R[i] * dx + R[6 + i] * dz
		local b = R[3 + i]
		table.insert(cons, { a, b, s.H[i] })
	end
	for _, c in cons do
		local a, b, h = c[1], c[2], c[3]
		if math.abs(b) < 1e-9 then
			if math.abs(a) > h then
				return nil
			end
		else
			local t0, t1 = (-h - a) / b, (h - a) / b
			if t0 > t1 then
				t0, t1 = t1, t0
			end
			lo, hi = math.max(lo, t0), math.min(hi, t1)
		end
	end
	if s.Wedge then
		-- (ly + hy) / 2hy - (lz + hz) / 2hz <= 0, linear in u = y - cy
		local ay, by = cons[2][1], cons[2][2]
		local az, bz = cons[3][1], cons[3][2]
		local hy, hz = s.H[2], s.H[3]
		local a = (ay + hy) / (2 * hy) - (az + hz) / (2 * hz)
		local b = by / (2 * hy) - bz / (2 * hz)
		if math.abs(b) < 1e-9 then
			if a > 0 then
				return nil
			end
		elseif b > 0 then
			hi = math.min(hi, -a / b)
		else
			lo = math.max(lo, -a / b)
		end
	end
	if lo > hi then
		return nil
	end
	return s.P[2] + lo, s.P[2] + hi
end

-- the highest solid top at (x, z) not above `top` (a player standing there), or nil
local function groundAt(list, px, pz, top)
	local best, part = nil, nil
	for _, s in list do
		local y0, y1 = column(s, px, pz)
		if y0 and y1 <= top and (not best or y1 > best) then
			best, part = y1, s.Part
		end
	end
	return best, part
end

-- the first solid interval of the line (x, z) overlapping [y0, y1]
local function blockedColumn(list, px, pz, y0, y1)
	for _, s in list do
		local a, b = column(s, px, pz)
		if a and b > y0 and a < y1 then
			return s.Part, a, b
		end
	end
	return nil
end

local ROOT_ABOVE = 3 -- HumanoidRootPart centre above the feet (R15 HipHeight 2 + half the root)
local BODY = 5 -- the character's height
local BODY_R = .8 -- the character's half width
local STEP = 1.2 -- a kerb / ramp edge this high under the character's side is walked over

-- a standing player at (x, z): feet on the highest solid top within `drop` below `top`, body clear of solids (a low
-- step beside the feet allowed)
local function stand(list, px, pz, top, drop)
	local g = groundAt(list, px, pz, top)
	if not g or g < top - drop then
		return nil
	end
	for k, o in { { 0, 0 }, { BODY_R, 0 }, { -BODY_R, 0 }, { 0, BODY_R }, { 0, -BODY_R } } do
		if blockedColumn(list, px + o[1], pz + o[2], g + (k == 1 and .25 or STEP), g + BODY) then
			return nil
		end
	end
	return V3(px, g + ROOT_ABOVE, pz)
end

local function fmt(v)
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end
local function name(p)
	return p and p:GetFullName():gsub("^.-40_Underyard%.", "") or "?"
end

---------------------------------------------------------------------------------------------------------------------
test("the world: every anchor seals I-IV read is saved in 40_Underyard.Anchors at its layout position", function()
	yes(anchors, "40_Underyard.Anchors")
	yes(#SOLIDS > 500, "solid parts " .. #SOLIDS)
	local names = { "PondConsult", "MirrorPond" }
	for i = 1, #Layout.EchoPoints do
		table.insert(names, "EchoPoint_" .. i)
	end
	for i = 1, #Layout.Carnival.Checkpoints do
		table.insert(names, "RunCheckpoint_" .. i)
	end
	for i = 1, 6 do
		table.insert(names, "MirrorGrave_" .. i)
	end
	for i = 1, #Layout.MineNodes do
		table.insert(names, "MineNode_" .. i)
	end
	for i = 1, 4 do
		local a = Rules.Activity(i)
		if a.StartAnchor then
			table.insert(names, a.StartAnchor)
		end
	end
	for _, n in names do
		local want = Layout.Anchors[n]
		yes(want, "layout anchor " .. n)
		local p = anchors:FindFirstChild(n)
		yes(p and p:IsA("BasePart"), "anchor part " .. n)
		near((p.CFrame.Position - want).Magnitude, 0, 1e-3, n)
		eq(p.CanCollide, false, n .. " CanCollide")
	end
	eq(#Layout.EchoPoints, Rules.Activity(1).Points, "echo points")
	eq(#Layout.Carnival.Checkpoints, Rules.Activity(2).Checkpoints, "checkpoints")
	eq(#Layout.MineNodes, Rules.Activity(4).Nodes, "mine nodes")
end)

---------------------------------------------------------------------------------------------------------------------
-- I · HAUNTED ECHO
---------------------------------------------------------------------------------------------------------------------
test("I: every echo point is open ground: a floor near y 0 and nothing solid in the mound's column", function()
	local bad = {}
	for i, p in ipairs(Layout.EchoPoints) do
		local list = solidsNear(p.X - 3, p.Y - 4, p.Z - 3, p.X + 3, p.Y + 8, p.Z + 3, 1)
		local g = groundAt(list, p.X, p.Z, p.Y + 1)
		if not g or math.abs(g - p.Y) > 1.5 then
			table.insert(bad, "EchoPoint_" .. i .. " floor " .. tostring(g))
		end
		for _, o in { { 0, 0 }, { 1.5, 0 }, { -1.5, 0 }, { 0, 1.5 }, { 0, -1.5 } } do
			local hit = blockedColumn(list, p.X + o[1], p.Z + o[2], (g or p.Y) + .3, p.Y + 6)
			if hit then
				table.insert(bad, "EchoPoint_" .. i .. " blocked by " .. name(hit))
				break
			end
		end
	end
	eq(#bad, 0, table.concat(bad, "; "))
end)

---------------------------------------------------------------------------------------------------------------------
-- II · FUNERAL RUN
---------------------------------------------------------------------------------------------------------------------
local act2 = Rules.Activity(2)
local function pendulum(i)
	local m = carnival and carnival:FindFirstChild("RunPendulum_" .. i, true)
	return m and m:IsA("Model") and m or nil
end

test("II: RunPendulum_i hinges match SealRules (pivot 17 above the lane, swing numbers, coffin centre Arm below)", function()
	yes(carnival, "FuneralCarnival")
	for i = 1, 3 do
		local m = pendulum(i)
		yes(m, "RunPendulum_" .. i)
		local hinge = m.PrimaryPart
		yes(hinge and hinge.Name == "PendulumHinge", "PrimaryPart PendulumHinge " .. i)
		local spec = Rules.PendulumSpec(i, hinge.CFrame, m:GetAttributes(), act2)
		near(spec.Amp, act2.PendulumAmp, 1e-6, "amp " .. i)
		near(spec.Period, act2.PendulumPeriod, 1e-6, "period " .. i)
		near(spec.Phase, (i - 1) * act2.PendulumPhaseStep, 1e-4, "phase " .. i)
		eq(m:GetAttribute("UySwingAxis"), "Z", "axis " .. i)
		local lp = Layout.Carnival.Pendulums[i]
		near(Rules.Flat(hinge.CFrame.Position - lp).Magnitude, 0, .05, "hinge over the layout point " .. i)
		-- the lane under the hinge
		local list = solidsNear(lp.X - 2, -6, lp.Z - 2, lp.X + 2, 6, lp.Z + 2, 1)
		local g = groundAt(list, lp.X, lp.Z, 2)
		yes(g, "lane floor under pendulum " .. i)
		near(spec.GroundY, g, .6, "GroundY = lane top under pendulum " .. i)
		-- the coffin body's centre at rest, in hinge space
		local lo, hi = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
		local n = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "CoffinBody" then
				n += 1
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local w = hinge.CFrame:PointToObjectSpace(d.CFrame * V3(sx * d.Size.X / 2, sy * d.Size.Y / 2, sz * d.Size.Z / 2))
							lo, hi = lo:Min(w), hi:Max(w)
						end
					end
				end
			end
		end
		yes(n > 0, "CoffinBody parts " .. i)
		local c = (lo + hi) / 2
		near(c.X, 0, .3, "coffin centre x " .. i)
		near(c.Z, 0, .3, "coffin centre z " .. i)
		near(-c.Y, act2.PendulumArm, .35, "coffin centre below the hinge " .. i)
		-- non-solid: the server's hazard is the only hit
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				eq(d.CanCollide, false, "pendulum part solid " .. d.Name)
			end
		end
	end
end)

test("II: the hazard strip of a pass contains the coffin at the lane centre and stays clear of solid props", function()
	for i = 1, 3 do
		local m = pendulum(i)
		local hinge = m.PrimaryPart
		local spec = Rules.PendulumSpec(i, hinge.CFrame, m:GetAttributes(), act2)
		local cross = Rules.Crossings(spec, 0, spec.Period)[1]
		yes(cross, "a pass in one period " .. i)
		near(Rules.SwingAngle(cross.T, spec.Amp, spec.Period, spec.Phase), 0, 1e-6, "angle 0 at the pass " .. i)
		local def = Rules.PendulumHazard(spec, cross, act2)
		local box = def.Shape
		local bcf, bsize = box.CFrame, box.Size
		yes(bcf and bsize, "Box shape " .. i)
		-- the coffin at the pass: every CoffinBody corner, rotated by the swing at the pass, inside the box (+ .3)
		local swing = hinge.CFrame * roblox.CFrame.Angles(0, 0, Rules.SwingAngle(cross.T, spec.Amp, spec.Period, spec.Phase))
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "CoffinBody" then
				local rel = hinge.CFrame:ToObjectSpace(d.CFrame)
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local w = (swing * rel) * V3(sx * d.Size.X / 2, sy * d.Size.Y / 2, sz * d.Size.Z / 2)
							local l = bcf:PointToObjectSpace(w)
							yes(math.abs(l.X) <= bsize.X / 2 + .3 and math.abs(l.Y) <= bsize.Y / 2 + .3 and math.abs(l.Z) <= bsize.Z / 2 + .3,
								"pendulum " .. i .. " coffin corner outside the strip " .. fmt(l))
						end
					end
				end
			end
		end
		-- the strip runs ACROSS the lane: its long side is the hinge's RightVector (the swing plane)
		near(math.abs(bcf.RightVector:Dot(Rules.Flat(hinge.CFrame.RightVector).Unit)), 1, 1e-3, "strip across the lane " .. i)
		-- nothing solid stands in the strip above the lane (a runner can always dodge or take the hit)
		local list = solidsNear(bcf.X - 10, spec.GroundY - 1, bcf.Z - 10, bcf.X + 10, spec.GroundY + 9, bcf.Z + 10, 1)
		for x = -bsize.X / 2 + .5, bsize.X / 2 - .5, 1 do
			for z = -bsize.Z / 2 + .3, bsize.Z / 2 - .3, .8 do
				local w = bcf * V3(x, 0, z)
				local hit, a, b = blockedColumn(list, w.X, w.Z, spec.GroundY + .6, spec.GroundY + 6)
				yes(not hit, string.format("pendulum %d strip blocked at %s by %s [%.1f, %.1f]", i, fmt(w), name(hit), a or 0, b or 0))
			end
		end
	end
end)

test("II: the lane runs under every hinge along its LookVector, and start -> ring 10 is free of solid parts", function()
	yes(Carnival and Carnival.LanePath, "FuneralCarnival.LanePath")
	local path = Carnival.LanePath(Layout)
	yes(#path >= 11, "lane path")
	local function closest(p)
		local best, dir = math.huge, nil
		for k = 1, #path - 1 do
			local a, b = Rules.Flat(path[k].Pos), Rules.Flat(path[k + 1].Pos)
			local d, t = Rules.SegmentClosest(a, b, Rules.Flat(p))
			if d < best then
				best, dir = d, (b - a).Unit
			end
		end
		return best, dir
	end
	for i = 1, 3 do
		local hinge = pendulum(i).PrimaryPart
		local d, dir = closest(hinge.CFrame.Position)
		-- the lane is 12 wide and the strip 14 across: a hinge up to 1 stud off the lane's centre line still covers it
		yes(d < 1 + (act2.PendulumStrip[1] - 12) / 2, "pendulum " .. i .. " off the lane by " .. d)
		yes(math.abs(Rules.Flat(hinge.CFrame.LookVector).Unit:Dot(dir)) > .97, "pendulum " .. i .. " LookVector along the lane")
	end
	-- walk the lane: every stud, a standing runner fits (the carousel deck legs ride a moving platform: skipped)
	local bad = {}
	for k = 1, #path - 1 do
		local a, b = path[k], path[k + 1]
		if a.Kind ~= "Carousel" and b.Kind ~= "Carousel" then
			local from, to = Rules.Flat(a.Pos), Rules.Flat(b.Pos)
			local len = (to - from).Magnitude
			local list = solidsNear(math.min(from.X, to.X) - 3, -6, math.min(from.Z, to.Z) - 3, math.max(from.X, to.X) + 3, 10,
				math.max(from.Z, to.Z) + 3, 1)
			for s = 0, len, 1 do
				local p = from + (to - from) * (s / math.max(len, 1e-6))
				if not stand(list, p.X, p.Z, 2.5, 4) then
					local g, gp = groundAt(list, p.X, p.Z, 2.5)
					local hit
					for k, o in { { 0, 0 }, { BODY_R, 0 }, { -BODY_R, 0 }, { 0, BODY_R }, { 0, -BODY_R } } do
						if g and not hit then
							hit = blockedColumn(list, p.X + o[1], p.Z + o[2], g + (k == 1 and .25 or STEP), g + BODY)
						end
					end
					table.insert(bad, string.format("%s->%s at %s floor %s blocked by %s", tostring(a.Index or a.Kind), tostring(b.Index or b.Kind),
						fmt(p), g and string.format("%.1f (%s)", g, name(gp)) or "none", name(hit)))
					if #bad > 6 then
						break
					end
				end
			end
		end
	end
	eq(#bad, 0, table.concat(bad, "; "))
end)

test("II: each RunCheckpoint_i arch carries its RunRing hoop around the checkpoint, open for a runner", function()
	local run = carnival:FindFirstChild("FuneralRun")
	local arches = run and run:FindFirstChild("Checkpoints")
	yes(arches, "FuneralRun.Checkpoints")
	for i, cp in ipairs(Layout.Carnival.Checkpoints) do
		local m = arches:FindFirstChild("RunCheckpoint_" .. i)
		yes(m and m:IsA("Model"), "RunCheckpoint_" .. i)
		local rings, sum = 0, V3(0, 0, 0)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "RunRing" then
				rings += 1
				sum += d.CFrame.Position
				eq(d:GetAttribute("RunCheckpoint"), i, "RunRing attribute " .. i)
			end
		end
		yes(rings >= 6, "hoop segments " .. i)
		local c = sum / rings
		yes(Rules.Flat(c - cp).Magnitude < 1.5, "hoop centred on checkpoint " .. i .. " " .. fmt(c))
		local list = solidsNear(cp.X - 8, -4, cp.Z - 8, cp.X + 8, 12, cp.Z + 8, 1)
		yes(stand(list, cp.X, cp.Z, 2.5, 4), "a runner fits through ring " .. i)
		-- a runner on the lane through the hoop passes the server's crossing check (anchor RunCheckpoint_i)
		local dir
		for _, e in ipairs(Carnival.LanePath(Layout)) do
			if e.Kind == "Checkpoint" and e.Index == i then
				dir = e.Dir
			end
		end
		yes(dir, "lane direction through ring " .. i)
		local g = groundAt(list, cp.X, cp.Z, 2.5)
		local rootAt = V3(cp.X, g + ROOT_ABOVE, cp.Z)
		local r = act2.CheckpointRadius + act2.CheckpointSlack
		yes(Rules.CrossesCheckpoint(rootAt - dir * 4, rootAt + dir * 4, Layout.Anchors["RunCheckpoint_" .. i], r, act2.CheckpointBand),
			"a runner through hoop " .. i .. " crosses the server checkpoint")
		-- ... and one running past the arch (outside its posts) does not
		local side = V3(-dir.Z, 0, dir.X) * (r + 1)
		yes(not Rules.CrossesCheckpoint(rootAt + side - dir * 4, rootAt + side + dir * 4, Layout.Anchors["RunCheckpoint_" .. i], r,
			act2.CheckpointBand), "running past arch " .. i .. " does not count")
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- III · MIRROR GRAVES (prompt geometry)
---------------------------------------------------------------------------------------------------------------------
local act3 = Rules.Activity(3)
local SLACK = 6 -- Chapter2Config.Proximity.Slack (server range checks)
-- the same maths as SealMirror.TurnSpot / ConsultSpot (tests/seals_1_4.luau checks the server functions)
local function turnSpot(g)
	local pos = Layout.Anchors["MirrorGrave_" .. g]
	local out = Rules.Flat(pos - Layout.Anchors.MirrorPond)
	return pos + out.Unit * act3.TurnOffset
end
local function consultSpot()
	local o = act3.ConsultOffset
	return Layout.Anchors.PondConsult + V3(o[1], o[2], o[3])
end

-- standing spots on a 0.5 grid around a prompt (players stand on the boardwalk / the shore, never inside a stone)
local standCache = {}
local function standing(centre, radius)
	local key = fmt(centre) .. radius
	if standCache[key] then
		return standCache[key]
	end
	local list = solidsNear(centre.X - radius - 2, centre.Y - 12, centre.Z - radius - 2, centre.X + radius + 2, centre.Y + 8,
		centre.Z + radius + 2, 1)
	local out = {}
	for x = -radius, radius, .5 do
		for z = -radius, radius, .5 do
			if x * x + z * z <= radius * radius then
				local p = stand(list, centre.X + x, centre.Z + z, Layout.Marsh.BoardwalkY + 2, 4)
				if p then
					table.insert(out, p)
				end
			end
		end
	end
	standCache[key] = out
	return out
end

local TURN_R, CONSULT_R = act3.TurnPromptRange, act3.ConsultPromptRange

test("III: prompt numbers: separate keys, tight ranges, every in-range spot passes the server check", function()
	yes(act3.TurnKeys[1] ~= act3.ConsultKeys[1], "keyboard keys differ")
	yes(act3.TurnKeys[2] ~= act3.ConsultKeys[2], "gamepad keys differ")
	yes(TURN_R <= 8 and CONSULT_R <= 8, "tight prompt ranges")
	-- a player that sees the prompt is at most range + offset from the anchor the server measures from
	yes(act3.TurnOffset + TURN_R <= act3.TurnRange + SLACK, "TURN reach within the server check")
	local o = act3.ConsultOffset
	yes(V3(o[1], o[2], o[3]).Magnitude + CONSULT_R <= act3.ConsultRange + SLACK, "CONSULT reach within the server check")
end)

test("III: TURN / CONSULT spots are outside solid parts, and stones stand between each TURN spot and the pond", function()
	local spots = { CONSULT = consultSpot() }
	for g = 1, 6 do
		spots["TURN " .. g] = turnSpot(g)
	end
	for label, p in spots do
		local list = solidsNear(p.X - 1, p.Y - 1, p.Z - 1, p.X + 1, p.Y + 1, p.Z + 1, 1)
		local hit = solidAt(list, p.X, p.Y, p.Z, .05)
		yes(not hit, label .. " spot " .. fmt(p) .. " inside " .. name(hit))
	end
	local pond = Layout.Anchors.MirrorPond
	for g = 1, 6 do
		local grave = Layout.Anchors["MirrorGrave_" .. g]
		local t = turnSpot(g)
		yes(Rules.Flat(t - pond).Magnitude > Rules.Flat(grave - pond).Magnitude + 2, "TURN " .. g .. " on the outer side")
	end
	local c = consultSpot()
	yes(Rules.Flat(c - pond).Magnitude < Rules.Flat(Layout.Anchors.PondConsult - pond).Magnitude, "CONSULT on the pond side")
	yes((c - turnSpot(1)).Magnitude > 7, "TURN 1 and CONSULT spots apart: " .. (c - turnSpot(1)).Magnitude)
end)

test("III: from standing spots each prompt is reachable, shows alone somewhere, and its nearest spot is unambiguous", function()
	local prompts = { { Label = "CONSULT", At = consultSpot(), R = CONSULT_R } }
	for g = 1, 6 do
		table.insert(prompts, { Label = "TURN " .. g, At = turnSpot(g), R = TURN_R })
	end
	local function shown(p)
		local out = {}
		for _, q in prompts do
			if (p - q.At).Magnitude <= q.R then
				table.insert(out, q.Label)
			end
		end
		return out
	end
	for _, q in prompts do
		local spots = standing(q.At, q.R)
		local reach, alone, nearest, nd = 0, 0, nil, math.huge
		for _, p in spots do
			local d = (p - q.At).Magnitude
			if d <= q.R then
				reach += 1
				local s = shown(p)
				if #s == 1 then
					alone += 1
				end
				if d < nd then
					nearest, nd = p, d
				end
			end
		end
		yes(reach >= 8, q.Label .. ": standing spots in range " .. reach)
		yes(alone >= 4, q.Label .. ": spots that show only this prompt " .. alone)
		local s = shown(nearest)
		eq(#s, 1, q.Label .. ": the closest standing spot " .. fmt(nearest) .. " also shows " .. table.concat(s, ", "))
	end
end)

test("III: the basin and the headstones are solid where the prompts say (the stones turn on their plinths)", function()
	yes(marsh, "MourningMarsh")
	for g = 1, 6 do
		local stone = marsh:FindFirstChild("MirrorGrave_" .. g .. "_Stone", true)
		yes(stone and stone:IsA("Model"), "MirrorGrave_" .. g .. "_Stone")
		local hinge = stone.PrimaryPart
		yes(hinge and hinge.Name == "StoneHinge", "StoneHinge " .. g)
		local a = Layout.Anchors["MirrorGrave_" .. g]
		yes(Rules.Flat(hinge.CFrame.Position - a).Magnitude < 1, "stone " .. g .. " at its anchor")
		-- turning a quarter keeps the rune on +Z of the hinge: the presenter's turn is hinge * Angles(0, k pi / 2, 0)
		local up = hinge.CFrame.UpVector
		near(up.Y, 1, 1e-3, "hinge upright " .. g)
		local glyph = stone:FindFirstChild("RuneGlyph", true) or stone:FindFirstChild("RunePanel", true)
		yes(glyph, "rune on stone " .. g)
		yes(hinge.CFrame:PointToObjectSpace(glyph.CFrame.Position).Z > .2, "rune faces the hinge's +Z " .. g)
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- IV · HOLLOW MINE
---------------------------------------------------------------------------------------------------------------------
test("IV: every mine node sits on the mine floor, clear above, under the ceiling the rocks fall from", function()
	yes(crypt, "Undercrypt")
	local floorY = Layout.Undercrypt.FloorY
	local mineSrc = fs.readFile(SRC .. "/StarterPlayer/StarterPlayerScripts/HalloweenClient/Trials/Mine.luau")
	local ceilingY = tonumber(string.match(mineSrc, "local CEILING_Y = ([%-%d%.]+)"))
	yes(ceilingY, "Trials/Mine CEILING_Y")
	local bad = {}
	for i, p in ipairs(Layout.MineNodes) do
		local list = solidsNear(p.X - 3, floorY - 4, p.Z - 3, p.X + 3, 12, p.Z + 3, 1)
		local g = groundAt(list, p.X, p.Z, floorY + 1)
		if not g or math.abs(g - floorY) > .8 then
			table.insert(bad, "MineNode_" .. i .. " floor " .. tostring(g))
		end
		local hit = blockedColumn(list, p.X, p.Z, (g or floorY) + .3, floorY + 7)
		if hit then
			table.insert(bad, "MineNode_" .. i .. " blocked by " .. name(hit))
		end
		-- the ceiling: the lowest solid above the node
		local low = math.huge
		for _, s in list do
			local a = column(s, p.X, p.Z)
			if a and a > floorY + 7 then
				low = math.min(low, a)
			end
		end
		if low == math.huge or math.abs(low - ceilingY) > 2.5 then
			table.insert(bad, string.format("MineNode_%d ceiling %s (presenter %s)", i, tostring(low), tostring(ceilingY)))
		end
		yes(Rules.OnFloor(p, Layout, Rules.Activity(4)), "MineNode_" .. i .. " on the floor box")
	end
	eq(#bad, 0, table.concat(bad, "; "))
end)

print(string.format("seals_1_4 (world): %d passed, %d failed", passed, failed))
if failed > 0 then
	error("seals_1_4_world tests failed")
end
return { Passed = passed, Failed = failed }
