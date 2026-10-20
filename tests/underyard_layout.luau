--!nolint
-- Sanity checks for ReplicatedStorage.Halloween.UnderyardLayout: lune run tests/underyard_layout.luau
local L = require("./lib/economy_env")
local Vector3 = require("@lune/roblox").Vector3
local U = L.Require("ReplicatedStorage.Halloween.UnderyardLayout")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed += 1 else failed += 1 print("FAIL " .. name .. ": " .. tostring(err)) end
end
test("every anchor is inside the zone and inside its bounds", function()
	local n = 0
	for name, p in pairs(U.Anchors) do
		n += 1
		assert(U.InZone(p), name .. " outside zone")
		assert(p.X >= U.Bounds.X0 and p.X <= U.Bounds.X1 and p.Z >= U.Bounds.Z0 and p.Z <= U.Bounds.Z1, name .. " outside bounds")
	end
	assert(n >= 100, "expected >= 100 anchors, got " .. n)
end)
test("district lookup matches the activity sites", function()
	local function is(p, d) assert(U.District(p) == d, tostring(p) .. " -> " .. tostring(U.District(p)) .. " expected " .. d) end
	is(U.Square.Tower.Centre, "BellSquare")
	for _, p in ipairs(U.Carnival.Checkpoints) do is(p, "FuneralCarnival") end
	for _, p in ipairs(U.MirrorGraves) do is(p, "MourningMarsh") end
	for _, p in ipairs(U.MineNodes) do is(p, "Undercrypt") end
	for _, p in ipairs(U.Crooked.Doors) do is(p, "CrookedRow") end
	is(U.Crooked.RareRoom.Spawn, "CrookedRow")
	is(U.Arena.Centre, "BlackBellArena")
	for _, p in pairs(U.Arena.Chains) do is(p, "BlackBellArena") end
	for _, p in ipairs(U.EchoPoints) do is(p, "BellSquare") end
	for _, p in ipairs(U.SealAltars) do is(p, "BellSquare") end
end)
test("echo points clear of the tower and altars", function()
	for i, p in ipairs(U.EchoPoints) do
		local flat = Vector3.new(p.X, 0, p.Z) - Vector3.new(0, 0, 2400)
		assert(flat.Magnitude > U.Square.Tower.Half * 1.5 + 6, "echo " .. i .. " too close to tower")
		for j, a in ipairs(U.SealAltars) do
			assert((p - a).Magnitude > 8, "echo " .. i .. " too close to altar " .. j)
		end
	end
end)
test("gates sit on the ring road", function()
	for name, g in pairs(U.Gates) do
		local r = (Vector3.new(g.Position.X, 0, g.Position.Z) - Vector3.new(0, 0, 2400)).Magnitude
		assert(r >= 80 and r <= 100, name .. " gate radius " .. r)
	end
end)
test("weight and zone", function()
	assert(U.Weight(U.Centre) == 1)
	assert(U.Weight(Vector3.new(0, 0, 700)) == 0)
	assert(U.Weight(Vector3.new(0, -400, 2400)) == 0)
	assert(not U.InZone(Vector3.new(128, 0, 700)))
end)
print(string.format("underyard_layout: %d passed, %d failed", passed, failed))
if failed > 0 then error("underyard_layout tests failed") end
