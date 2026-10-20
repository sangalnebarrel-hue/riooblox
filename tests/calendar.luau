--!nolint
-- HALLOWEEN CALENDAR rules (docs/halloween2/DESIGN.md §13): lune run tests/calendar.luau
-- UTC date math, stage boundaries D-7 .. D-1 and October 31 00:00 UTC, before / after, the Studio force, cumulative and
-- monotonic stage parameters, the client's pure helpers (grass order, lamp tint, plan).
local L = require("./lib/economy_env")
local R = L.Require("ReplicatedStorage.Halloween.CalendarRules")
local C = L.Require("ReplicatedStorage.Halloween.HalloweenCalendarConfig")

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
		error(string.format("%s: expected %s got %s", msg or "", tostring(b), tostring(a)), 2)
	end
end

local DAY = 86400
local function cfgWith(over)
	local c = table.clone(C)
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

test("UnixFromDate matches known UTC timestamps (Hinnant days-from-civil)", function()
	eq(R.UnixFromDate(1970, 1, 1), 0, "epoch")
	eq(R.UnixFromDate(1969, 12, 31), -86400, "before epoch")
	eq(R.UnixFromDate(2000, 2, 29), 951782400, "leap day 2000")
	eq(R.UnixFromDate(2024, 3, 1), 1709251200, "after leap day 2024")
	eq(R.UnixFromDate(2026, 10, 20), 1792454400, "Chapter II start")
	eq(R.UnixFromDate(2026, 10, 24), 1792800000, "D-7")
	eq(R.UnixFromDate(2026, 10, 31), 1793404800, "target")
	eq(R.UnixFromDate(2100, 3, 1), 4107542400, "2100 is not a leap year")
	eq(R.UnixFromDate(2026, 10, 31, 18, 30, 15), 1793404800 + 18 * 3600 + 30 * 60 + 15, "hours / minutes / seconds")
end)

test("days-from-civil agrees with a day-by-day walk and round-trips", function()
	local mdays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	local function leap(y)
		return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
	end
	local n = R.DaysFromCivil(1999, 12, 31) + 1
	for y = 2000, 2031 do
		for m = 1, 12 do
			local len = mdays[m] + ((m == 2 and leap(y)) and 1 or 0)
			for d = 1, len do
				eq(R.DaysFromCivil(y, m, d), n, string.format("%04d-%02d-%02d", y, m, d))
				local y2, m2, d2 = R.CivilFromDays(n)
				assert(y2 == y and m2 == m and d2 == d, "round trip " .. n)
				n += 1
			end
		end
	end
end)

test("the target is October 31 00:00 UTC", function()
	eq(R.Target(C), 1793404800, "target")
	eq(C.Target.Year, 2026)
	eq(C.Target.Month, 10)
	eq(C.Target.Day, 31)
end)

test("stage boundaries D-7 .. D-1 and October 31 00:00 UTC", function()
	local target = R.Target(C)
	eq(R.Stage(target - 7 * DAY - 1, C), 0, "one second before D-7")
	for k = 1, 7 do
		local start = target - (8 - k) * DAY
		eq(R.Stage(start, C), k, "start of D-" .. (8 - k))
		eq(R.Stage(start + DAY - 1, C), k, "last second of D-" .. (8 - k))
		eq(R.Stage(start - 1, C), k - 1, "one second before D-" .. (8 - k))
	end
	eq(R.Stage(target - 1, C), 7, "last second of October 30")
	eq(R.Stage(target, C), 8, "October 31 00:00:00 UTC")
	-- calendar dates (UTC)
	eq(R.Stage(R.UnixFromDate(2026, 10, 24), C), 1, "Oct 24")
	eq(R.Stage(R.UnixFromDate(2026, 10, 27, 13), C), 4, "Oct 27 13:00")
	eq(R.Stage(R.UnixFromDate(2026, 10, 30, 23, 59, 59), C), 7, "Oct 30 23:59:59")
end)

test("before and after the calendar", function()
	eq(R.Stage(R.UnixFromDate(2026, 10, 20), C), 0, "Chapter II launch day")
	eq(R.Stage(R.UnixFromDate(2026, 1, 1), C), 0, "new year")
	eq(R.Stage(0, C), 0, "epoch")
	eq(R.Stage(R.UnixFromDate(2026, 11, 1), C), 8, "November 1 (no Until)")
	eq(R.Stage(R.UnixFromDate(2027, 3, 1), C), 8, "much later (no Until)")
	local c = cfgWith({ Until = { Year = 2026, Month = 11, Day = 3 } })
	eq(R.Stage(R.UnixFromDate(2026, 11, 2, 23, 59, 59), c), 8, "before Until")
	eq(R.Stage(R.UnixFromDate(2026, 11, 3), c), 0, "from Until")
	eq(R.NextChange(R.UnixFromDate(2026, 11, 1), c), R.UnixFromDate(2026, 11, 3), "Until is a change")
end)

test("days left", function()
	local target = R.Target(C)
	eq(R.DaysLeft(target - 7 * DAY, C), 7, "D-7")
	eq(R.DaysLeft(target - 7 * DAY + 1, C), 7, "D-7 + 1 s")
	eq(R.DaysLeft(target - 7 * DAY - 1, C), 8, "a second earlier")
	eq(R.DaysLeft(target - 1, C), 1, "last second")
	eq(R.DaysLeft(target, C), 0, "target")
	eq(R.DaysLeft(target + 5 * DAY, C), 0, "after")
	-- the stage always agrees with the days left before the target
	for t = target - 9 * DAY, target - 1, 3607 do
		local d = R.DaysLeft(t, C)
		eq(R.Stage(t, C), math.max(0, 8 - d), "stage vs days left at " .. t)
	end
end)

test("next change is the next stage start", function()
	local target = R.Target(C)
	eq(R.NextChange(R.UnixFromDate(2026, 10, 20), C), target - 7 * DAY, "before the calendar")
	eq(R.NextChange(target - 3 * DAY + 5, C), target - 2 * DAY, "mid D-3")
	eq(R.NextChange(target - DAY, C), target, "D-1 start")
	eq(R.NextChange(target, C), nil, "nothing after the target without Until")
	-- the stage never changes strictly between now and NextChange
	local now = target - 6 * DAY + 777
	local nxt = R.NextChange(now, C)
	eq(R.Stage(nxt - 1, C), R.Stage(now, C), "stable until the change")
	assert(R.Stage(nxt, C) ~= R.Stage(now, C), "changes at the change")
end)

test("Studio force wins only when valid", function()
	local early = R.UnixFromDate(2026, 10, 20)
	local s, forced = R.Effective(early, C, 5)
	eq(s, 5, "forced stage")
	eq(forced, true, "forced flag")
	s, forced = R.Effective(early, C, nil)
	eq(s, 0, "no force")
	eq(forced, false, "no force flag")
	for _, bad in ipairs({ -1, 9, 0 / 0, "3", true }) do
		local s2, f2 = R.Effective(early, C, bad)
		eq(s2, 0, "invalid force " .. tostring(bad))
		eq(f2, false, "invalid force flag " .. tostring(bad))
	end
	eq(select(1, R.Effective(early, C, 0)), 0, "force 0 hides everything")
	eq(select(1, R.Effective(early, C, 4.7)), 4, "fractional force floors")
	eq(C.Studio.ForceStage, nil, "the shipped config never forces a stage")
end)

test("stage table: 8 stages, folders Stage01..08, From 7..0, bilingual texts", function()
	eq(#C.Stages, 8, "stage count")
	eq(C.MaxStage, 8, "MaxStage")
	for k, row in ipairs(C.Stages) do
		eq(row.Folder, string.format("Stage%02d", k), "folder " .. k)
		eq(row.From, 8 - k, "From " .. k)
		for _, field in ipairs({ "Label", "Name", "Toast" }) do
			local pair = row[field]
			assert(type(pair) == "table" and type(pair[1]) == "string" and type(pair[2]) == "string" and pair[1] ~= "" and pair[2] ~= "",
				field .. " of stage " .. k .. " needs EN + RU")
			assert(pair[1] ~= pair[2], field .. " of stage " .. k .. " is not translated")
		end
		eq(R.Text(k, C, "Name", false), row.Name[1], "Text EN")
		eq(R.Text(k, C, "Name", true), row.Name[2], "Text RU")
	end
	eq(R.Text(0, C, "Name", false), nil, "stage 0 has no text")
end)

test("stage params are cumulative and every number only grows", function()
	local prev = R.StageParams(0, C)
	for k, v in pairs(C.Base) do
		eq(prev[k], v, "base " .. k)
	end
	eq(prev.Stage, 0, "stage field")
	for s = 1, 8 do
		local p = R.StageParams(s, C)
		eq(p.Stage, s, "stage field")
		for k, v in pairs(C.Base) do
			assert(type(p[k]) == "number", "param " .. k .. " missing at stage " .. s)
			assert(p[k] >= prev[k], string.format("%s shrinks at stage %d (%s -> %s)", k, s, prev[k], p[k]))
		end
		-- a key a stage does not list keeps the previous stage's value
		for k in pairs(C.Base) do
			if C.Stages[s][k] == nil then
				eq(p[k], prev[k], "inherited " .. k .. " at stage " .. s)
			else
				eq(p[k], C.Stages[s][k], "own " .. k .. " at stage " .. s)
			end
		end
		prev = p
	end
	-- every stage brings something new
	for s = 1, 8 do
		local a, b = R.StageParams(s - 1, C), R.StageParams(s, C)
		local grew = false
		for k in pairs(C.Base) do
			if b[k] > a[k] then
				grew = true
			end
		end
		assert(grew, "stage " .. s .. " adds nothing")
	end
	-- the design beats (§13): ~10 / 20 / 33 % grass, > 50 % at D-3, most of the map at D-2, almost all at D-1
	eq(R.StageParams(1, C).Grass, .10)
	eq(R.StageParams(2, C).Grass, .20)
	eq(R.StageParams(3, C).Grass, .33)
	assert(R.StageParams(5, C).Grass > .5, "D-3 > 50 %")
	assert(R.StageParams(6, C).Grass >= .7, "D-2 most of the map")
	assert(R.StageParams(7, C).Grass >= .9, "D-1 almost fully infected")
	eq(R.StageParams(2, C).Bats, 0, "no bats before D-5")
	assert(R.StageParams(3, C).Bats > 0, "rare bats at D-5")
	eq(R.StageParams(3, C).Eyes, 0, "eyes only from D-4")
	assert(R.StageParams(4, C).Eyes > 0 and R.StageParams(4, C).Windows > 0, "eyes + windows at D-4")
	assert(R.StageParams(5, C).Ghosts > 0 and R.StageParams(5, C).Halo > 0 and R.StageParams(5, C).Lamps > 0, "D-3 ghosts, moon, lamps")
	assert(R.StageParams(6, C).Sway > 0 and R.StageParams(6, C).Whispers > 0, "D-2 sway + whispers")
	assert(R.StageParams(7, C).Eclipse > 0, "D-1 moon transformation")
	eq(R.StageParams(8, C).Finale, 1, "October 31 set pieces")
	-- out of range stages clamp
	eq(R.StageParams(-3, C).Stage, 0)
	eq(R.StageParams(42, C).Stage, 8)
end)

test("fog stays within the gameplay visibility limit", function()
	assert(C.Lighting.Atmo.Density <= C.Lighting.MaxDensity + 1e-9, "full look denser than MaxDensity")
	assert(C.Lighting.MaxDensity <= .36, "MaxDensity above .36")
	for s = 0, 8 do
		local w = R.StageParams(s, C).Atmos
		assert(w >= 0 and w <= 1, "Atmos weight out of 0..1 at stage " .. s)
	end
end)

test("blend glides every parameter", function()
	local a, b = R.StageParams(2, C), R.StageParams(5, C)
	local m = R.Blend(a, b, .5)
	for k, v in pairs(b) do
		local want = a[k] + (v - a[k]) * .5
		assert(math.abs(m[k] - want) < 1e-9, "blend " .. k)
	end
	local e = R.Blend(a, b, 7)
	for k, v in pairs(b) do
		eq(e[k], v, "blend clamps " .. k)
	end
end)

test("hash is deterministic and spread", function()
	eq(R.Hash("LivingGround|12"), R.Hash("LivingGround|12"), "stable")
	assert(R.Hash("a") ~= R.Hash("b"), "differs")
	local buckets = { 0, 0, 0, 0 }
	for i = 1, 4000 do
		local h = R.Hash("part" .. i)
		assert(h >= 0 and h < 1, "range")
		local b = math.floor(h * 4) + 1
		buckets[b] += 1
	end
	for i, n in ipairs(buckets) do
		assert(n > 800 and n < 1200, "bucket " .. i .. " = " .. n)
	end
end)

-- the client's pure helpers (HalloweenClient.CalendarFX.Pure) — loaded with stubbed services
local okFX, FX = pcall(function()
	return L.Require("StarterPlayer.StarterPlayerScripts.HalloweenClient.CalendarFX")
end)
test("CalendarFX loads offline", function()
	assert(okFX, tostring(FX))
	assert(type(FX.Pure) == "table", "Pure helpers")
end)
if okFX and type(FX.Pure) == "table" then
	local P = FX.Pure
	test("grass order: a fixed share, nearest the Dead Yard first, stable per part", function()
		local parts = {}
		for i = 1, 60 do
			table.insert(parts, { Key = "g" .. i, X = -200 + (i % 10) * 40, Z = -200 + math.floor(i / 10) * 160 })
		end
		local ranked = P.RankGrass(parts, C)
		eq(#ranked, 60, "all ranked")
		local again = P.RankGrass(parts, C)
		for i = 1, 60 do
			eq(ranked[i].Key, again[i].Key, "stable order")
		end
		-- count tinted at each stage share
		for _, share in ipairs({ 0, .1, .33, .55, .92, 1 }) do
			eq(P.TintCount(60, share), math.floor(60 * share + .5), "count at " .. share)
		end
		-- the first tenth is on average much nearer the origin than the last tenth
		local function meanDist(a, b)
			local s = 0
			for i = a, b do
				local p = ranked[i]
				s += math.sqrt((p.X - C.Grass.Origin.X) ^ 2 + (p.Z - C.Grass.Origin.Z) ^ 2)
			end
			return s / (b - a + 1)
		end
		assert(meanDist(1, 6) < meanDist(55, 60), "rot spreads from the Dead Yard")
	end)
	test("dead colour per part is one of the palette and deterministic", function()
		local Color3 = require("@lune/roblox").Color3
		local orig = Color3.fromRGB(95, 210, 47)
		local c1 = P.DeadColor("g7", orig, .8, C)
		local c2 = P.DeadColor("g7", orig, .8, C)
		eq(c1, c2, "deterministic")
		local c0 = P.DeadColor("g7", orig, 0, C)
		eq(c0, orig, "depth 0 = original")
	end)
	test("lamp tint: 0 keeps the event colour, 1 is a calendar colour", function()
		local Color3 = require("@lune/roblox").Color3
		local ev = Color3.fromRGB(120, 255, 90)
		eq(P.LampColor("lamp1", ev, 0, C), ev, "strength 0")
		local full = P.LampColor("lamp1", ev, 1, C)
		local ok = false
		for _, rgb in ipairs(C.Lamps.Colors) do
			local want = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
			if math.abs(full.R - want.R) < 1e-6 and math.abs(full.G - want.G) < 1e-6 and math.abs(full.B - want.B) < 1e-6 then
				ok = true
			end
		end
		assert(ok, "full strength is a calendar colour")
	end)
	test("plan scales with quality and never runs creatures before their stage", function()
		local p0 = P.Plan(R.StageParams(0, C), "High", C)
		eq(p0.Bats, 0)
		eq(p0.Ghosts, 0)
		eq(p0.Wisps, 0)
		local hi = P.Plan(R.StageParams(8, C), "High", C)
		local lo = P.Plan(R.StageParams(8, C), "Low", C)
		assert(hi.Bats > lo.Bats and hi.Ghosts >= lo.Ghosts and hi.Wisps > lo.Wisps, "Low runs less")
		assert(lo.Bats >= 1 and lo.Ghosts >= 1, "Low still shows a little")
		assert(hi.SwayRange > lo.SwayRange, "sway range scales")
	end)
	test("lighting profile: fog capped, nights darker with Dark, October 31 tint", function()
		local p7, p8 = R.StageParams(7, C), R.StageParams(8, C)
		local day, night = P.Profile(p7, 0, C), P.Profile(p7, 1, C)
		assert(day.Atmo.Density <= C.Lighting.MaxDensity + 1e-9 and night.Atmo.Density <= C.Lighting.MaxDensity + 1e-9, "density cap")
		eq(day.Prio, C.Lighting.Prio, "prio below the Dead Yard zone (20)")
		assert(day.Prio < 20, "prio must stay below ZONE")
		assert(night.Grade.Brightness < day.Grade.Brightness, "nights darker")
		local calm = P.Profile(R.StageParams(1, C), 1, C)
		assert(calm.Grade.Brightness > night.Grade.Brightness, "D-7 nights less dark than D-1")
		local fin = P.Profile(p8, 1, C)
		assert(fin.Atmo.Color ~= night.Atmo.Color, "October 31 changes the fog colour")
		eq(fin.Sky.MoonAngularSize, C.Lighting.Sky.MoonAngularSize, "bigger sky moon")
	end)
	test("sway, darkness and colour helpers stay in range", function()
		for t = 0, 60, .37 do
			local a = P.SwayAngle(t, 1.3, 6, .6, C.Sway.Gust)
			assert(math.abs(a) <= math.rad(6) * (1 + C.Sway.Gust) + 1e-9, "sway amplitude")
		end
		eq(P.SwayAngle(5, 0, 0, .6, .35), 0, "no sway at 0 degrees")
		eq(P.Darkness(1, nil), 0, "full day")
		eq(P.Darkness(0, nil), 1, "full night")
		eq(P.Darkness(nil, true), 1, "IsNight")
		assert(P.Darkness(nil, nil, 13) < .05, "1 pm by the clock is day")
		assert(P.Darkness(nil, nil, 1) > .95, "1 am by the clock is night")
		local Color3 = require("@lune/roblox").Color3
		assert(P.SameColor(Color3.fromRGB(10, 20, 30), Color3.new(10 / 255 + 1e-6, 20 / 255, 30 / 255)), "float32 read-back equals")
		assert(not P.SameColor(Color3.fromRGB(10, 20, 30), Color3.fromRGB(11, 20, 30)), "one level apart differs")
	end)
	test("nothing runs at stage 0, everything scales up by D-1", function()
		local p0 = P.Plan(R.StageParams(0, C), "High", C)
		eq(p0.Mist, 0)
		eq(p0.Leaves, 0)
		eq(p0.Windows, 0)
		eq(p0.Halo, 0)
		eq(p0.Eclipse, 0)
		local p7 = P.Plan(R.StageParams(7, C), "Medium", C)
		assert(p7.Mist > 0 and p7.Leaves > 0 and p7.Windows > 0 and p7.Eclipse > 0 and p7.Wisps > 0, "D-1 runs everything")
		-- the game's own Config.Quality[*].CalendarFX wins when present
		local q = P.Plan(R.StageParams(7, C), "Medium", C, { Quality = { Medium = { CalendarFX = .5 } } })
		eq(q.Q, .5, "Config.Quality override")
	end)
	test("ghosts and bats stay near their markers", function()
		local Vector3 = require("@lune/roblox").Vector3
		local c = Vector3.new(10, 3, -40)
		for u = 0, 1, .05 do
			local g = P.GhostPos(c, 16, 4, u, .3)
			assert((Vector3.new(g.X, 0, g.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude <= 16 + 1e-6, "ghost radius")
			assert(math.abs(g.Y - c.Y) <= 1 + 1e-6, "ghost height")
		end
		eq(P.Fade(0), 0)
		eq(P.Fade(1), 0)
		eq(P.Fade(.5), 1)
		for t = 0, 30, .5 do
			local b = P.BatPos(c, 3, 6, t, C)
			local d = (Vector3.new(b.X, 0, b.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude
			assert(d <= C.Bats.Radius[2] * 1.2 + 1e-6, "bat radius " .. d)
			assert(b.Y >= c.Y + C.Bats.Height[1] - 1.5 and b.Y <= c.Y + C.Bats.Height[2] + 1.5, "bat height")
		end
	end)
	test("eye and window timings stay in their configured ranges", function()
		local rnd = L.Random.new(7)
		for _ = 1, 200 do
			local open = P.EyeSpan(true, .5, function() return rnd:NextNumber() end, C)
			local closed = P.EyeSpan(false, .5, function() return rnd:NextNumber() end, C)
			assert(open >= C.Eyes.Open[1] - 1e-9 and open <= C.Eyes.Open[2] * 2 + 1e-9, "open span " .. open)
			assert(closed > 0, "closed span")
		end
		eq(P.EyeOpenShare(0), 0, "no eyes at 0")
	end)
end

-------------------------------------------------------------------------------------------------------------------
-- the server service (ServerScriptService.Halloween.Calendar) on a tiny mock DataModel: it must only reparent the
-- prebuilt stage folders (never clone), follow the date both ways, publish State.Calendar, obey the switch and keep the
-- Studio force Studio-only
-------------------------------------------------------------------------------------------------------------------
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function signal()
	return { Connect = function() return { Disconnect = function() end } end }
end
local Mock = {}
Mock.__index = function(self, k)
	if k == "Parent" then
		return rawget(self, "_parent")
	end
	if Mock[k] then
		return Mock[k]
	end
	return self:FindFirstChild(k)
end
Mock.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			for i, c in ipairs(old._children) do
				if c == self then
					table.remove(old._children, i)
					break
				end
			end
		end
		rawset(self, "_parent", v)
		if v then
			table.insert(v._children, self)
		end
		rawset(self, "_moves", (rawget(self, "_moves") or 0) + 1)
	else
		rawset(self, k, v)
	end
end
local created = 0
local function mock(class, name, parent)
	created += 1
	local o = setmetatable({ ClassName = class, Name = name or class, _children = {}, _attrs = {} }, Mock)
	if parent then
		o.Parent = parent
	end
	return o
end
function Mock.FindFirstChild(self, name)
	for _, c in ipairs(self._children) do
		if c.Name == name then
			return c
		end
	end
	return nil
end
Mock.WaitForChild = Mock.FindFirstChild
function Mock.GetChildren(self)
	return table.clone(self._children)
end
function Mock.GetAttribute(self, k)
	return self._attrs[k]
end
function Mock.SetAttribute(self, k, v)
	self._attrs[k] = v
end
function Mock.GetAttributeChangedSignal()
	return signal()
end
function Mock.IsA(self, class)
	return self.ClassName == class
end
function Mock.Destroy(self)
	self.Parent = nil
end

local function world(enabled, studio)
	local env = { Enabled = enabled, Studio = studio, Now = R.UnixFromDate(2026, 10, 20) }
	local game = mock("DataModel", "game")
	local RSm = mock("ReplicatedStorage", "ReplicatedStorage", game)
	local SSm = mock("ServerStorage", "ServerStorage", game)
	local WS = mock("Workspace", "Workspace", game)
	local district = mock("Model", "DOGROTS_District", WS)
	local hw = mock("Folder", "Halloween", RSm)
	local state = mock("Folder", "State", hw)
	local mods = {
		Shared = { CalendarEnabled = function() return env.Enabled end },
		HalloweenCalendarConfig = C,
		CalendarRules = R,
	}
	local modInst = {}
	for name in pairs(mods) do
		modInst[mock("ModuleScript", name, hw)] = mods[name]
	end
	local store = mock("Folder", "HalloweenCalendar", SSm)
	local folders = {}
	for k = 1, 8 do
		local f = mock("Folder", string.format("Stage%02d", k), store)
		f:SetAttribute("CalendarStage", k)
		rawset(f, "_moves", 0)
		folders[k] = f
	end
	local runService = { IsStudio = function() return env.Studio end }
	game.GetService = function(_, name)
		if name == "RunService" then
			return runService
		end
		return game:FindFirstChild(name)
	end
	local src = fs.readFile("src/ServerScriptService/Halloween/Calendar.luau")
	local fnEnv = setmetatable({
		game = game, workspace = WS,
		require = function(m) return assert(modInst[m], "unexpected require") end,
		Instance = { new = function(class) return mock(class) end },
		task = { spawn = function() end, defer = function() end, wait = function() end, delay = function() end },
		os = setmetatable({ time = function() return env.Now end }, { __index = os }),
		print = function() end, warn = function() end,
	}, { __index = _G })
	local Cal = luau.load(src, { debugName = "Calendar", environment = fnEnv })()
	env.Cal, env.Folders, env.District, env.Store, env.State = Cal, folders, district, store, state
	return env
end
local function liveStages(env)
	local root = env.District:FindFirstChild(C.Root)
	local live = {}
	for k, f in ipairs(env.Folders) do
		if f.Parent == root and root ~= nil then
			table.insert(live, k)
		else
			assert(f.Parent == env.Store, "folder " .. k .. " is neither live nor stored")
		end
	end
	return table.concat(live, ",")
end

test("service: folders follow the date both ways, by reparenting only", function()
	local env = world(true, false)
	local before = created
	env.Cal.Start(nil, {})
	eq(liveStages(env), "", "Oct 20: nothing live")
	local cal = env.State:FindFirstChild(C.StateName)
	assert(cal, "State.Calendar published")
	eq(cal:GetAttribute("Stage"), 0, "stage 0")
	eq(cal:GetAttribute("Enabled"), true, "enabled")
	eq(cal:GetAttribute("DaysLeft"), 11, "days left")
	eq(cal:GetAttribute("Target"), R.Target(C), "target")
	eq(cal:GetAttribute("NextAt"), R.UnixFromDate(2026, 10, 24), "next change at D-7")
	env.Now = R.UnixFromDate(2026, 10, 27, 12)
	env.Cal.Refresh()
	eq(liveStages(env), "1,2,3,4", "Oct 27: stages 1-4 live")
	eq(cal:GetAttribute("Stage"), 4, "stage 4")
	local rev = cal:GetAttribute("Revision")
	env.Cal.Refresh()
	eq(cal:GetAttribute("Revision"), rev, "no change, no revision bump")
	for k = 1, 8 do
		assert(rawget(env.Folders[k], "_moves") <= 1, "folder " .. k .. " moved more than once")
	end
	env.Now = R.UnixFromDate(2026, 10, 24, 0, 0, 5) -- the clock went back (Studio)
	env.Cal.Refresh()
	eq(liveStages(env), "1", "back to D-7")
	env.Now = R.UnixFromDate(2026, 10, 31)
	env.Cal.Refresh()
	eq(liveStages(env), "1,2,3,4,5,6,7,8", "Oct 31: everything live")
	eq(cal:GetAttribute("DaysLeft"), 0, "no days left")
	eq(cal:GetAttribute("NextAt"), 0, "nothing more to come")
	assert(cal:GetAttribute("Revision") > rev, "revision bumped")
	-- the only instances made are the live root and the state folder: no clones of the decorations
	assert(created - before <= 2, "the service created " .. (created - before) .. " instances")
end)

test("service: switched off -> everything stored, stage 0", function()
	local env = world(true, false)
	env.Now = R.UnixFromDate(2026, 10, 29)
	env.Cal.Start(nil, {})
	eq(liveStages(env), "1,2,3,4,5,6", "D-2 live")
	env.Enabled = false
	env.Cal.Refresh()
	eq(liveStages(env), "", "off: all stored")
	local cal = env.State:FindFirstChild(C.StateName)
	eq(cal:GetAttribute("Stage"), 0, "stage 0 when off")
	eq(cal:GetAttribute("Enabled"), false, "Enabled false")
	env.Enabled = true
	env.Cal.Refresh()
	eq(liveStages(env), "1,2,3,4,5,6", "back on")
end)

test("service: the force is Studio-only and validated", function()
	local live = world(true, false)
	live.Cal.Start(nil, {})
	local ok = live.Cal.Force(5)
	eq(ok, false, "refused on a live server")
	eq(liveStages(live), "", "live server unchanged")
	local studio = world(true, true)
	studio.Cal.Start(nil, {})
	ok = studio.Cal.Force(5)
	eq(ok, true, "Studio force accepted")
	eq(liveStages(studio), "1,2,3,4,5", "forced stage 5")
	eq(studio.State:FindFirstChild(C.StateName):GetAttribute("Forced"), true, "Forced published")
	eq(select(1, studio.Cal.Force(12)), false, "out of range refused")
	eq(liveStages(studio), "1,2,3,4,5", "still stage 5")
	studio.Cal.Force(nil)
	eq(liveStages(studio), "", "back to the date (Oct 20)")
	eq(studio.State:FindFirstChild(C.StateName):GetAttribute("Forced"), false, "not forced")
end)

print(string.format("calendar: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("calendar tests failed")
end
