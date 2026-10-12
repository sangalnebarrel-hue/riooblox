--!nocheck
--!nolint
-- Client performance helpers (ReplicatedStorage.Perf): Signal, Maid, Scheduler, Pool, Quality, Lod.
-- lune run tests/perf.luau
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")
L.Task = require("@lune/task")

local Vector3, CFrame, Vector2 = roblox.Vector3, roblox.CFrame, roblox.Vector2

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
local function near(a, b, tolerance, msg)
	if math.abs(a - b) > (tolerance or 1e-6) then
		error((msg or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a), 2)
	end
end

-- A fake clock for Scheduler runners.
local function clock(start)
	local c = { T = start or 100 }
	function c.Now()
		return c.T
	end
	return c
end

-- A player-like object: attributes with synchronous changed signals.
local function fakePlayer()
	local p = { Attributes = {}, Signals = {}, Writes = {} }
	function p:GetAttribute(k)
		return self.Attributes[k]
	end
	function p:SetAttribute(k, v)
		self.Writes[k] = (self.Writes[k] or 0) + 1
		self.Attributes[k] = v
		for _, fn in ipairs(self.Signals[k] or {}) do
			fn()
		end
	end
	function p:GetAttributeChangedSignal(k)
		local list = self.Signals[k] or {}
		self.Signals[k] = list
		return {
			Connect = function(_, fn)
				table.insert(list, fn)
				return { Disconnect = function() end }
			end,
		}
	end
	return p
end

local noSignal = { Connect = function() return { Disconnect = function() end } end }

-- SIGNAL / MAID -----------------------------------------------------------------------------------
local Signal = L.Require("ReplicatedStorage.Perf.Signal")
local Maid = L.Require("ReplicatedStorage.Perf.Maid")

test("Signal connect / once / disconnect", function()
	local s = Signal.new()
	local got, once = {}, 0
	local c = s:Connect(function(v) table.insert(got, v) end)
	s:Once(function() once += 1 end)
	s:Fire(1)
	s:Fire(2)
	c:Disconnect()
	s:Fire(3)
	eq(#got, 2)
	eq(got[2], 2)
	eq(once, 1)
	truthy(not c.Connected, "disconnected")
	local after = 0
	s:Connect(function() after += 1 end)
	s:DisconnectAll()
	s:Fire(4)
	eq(after, 0, "DisconnectAll")
end)

test("Maid cleans in reverse order, keyed slots, failures isolated", function()
	local order = {}
	local m = Maid.new()
	m:Give(function() table.insert(order, "a") end)
	m:Give({ Destroy = function() table.insert(order, "b") end })
	m:Give(function() error("boom") end)
	m:Give({ Disconnect = function() table.insert(order, "c") end })
	m:Set("slot", function() table.insert(order, "old") end)
	m:Set("slot", function() table.insert(order, "new") end)
	eq(order[1], "old", "replacing a keyed item cleans the previous one")
	m:Clean()
	eq(table.concat(order, ","), "old,new,c,b,a")
	m:Clean() -- a second clean is a no-op
	eq(#order, 5)
	eq(m:Give(nil), nil)
end)

test("Kit Maid / Signal forward to Perf", function()
	eq(L.Require("StarterGui.ScreenGui.Modules.Kit.Maid"), Maid)
	eq(L.Require("StarterGui.ScreenGui.Modules.Kit.Signal"), Signal)
end)

-- SCHEDULER -----------------------------------------------------------------------------------------
local Scheduler = L.Require("ReplicatedStorage.Perf.Scheduler")

local function runner(c, options)
	options = options or {}
	options.Clock = c.Now
	options.Profile = false
	return Scheduler.new(options)
end
local function frames(r, c, count, dt)
	for _ = 1, count do
		c.T += dt
		r:Step(dt)
	end
end

test("Scheduler rate and every-frame jobs", function()
	local c = clock()
	local r = runner(c)
	local slow, every = 0, 0
	r:Every(10, "slow", function() slow += 1 end)
	r:Every(0, "every", function() every += 1 end)
	frames(r, c, 60, 1 / 60)
	truthy(slow >= 10 and slow <= 11, "10 Hz over 1 s, got " .. slow)
	eq(every, 60)
	eq(r:Count(), 2)
end)

test("Scheduler passes dt since the last call and never bursts after a hitch", function()
	local c = clock()
	local r = runner(c)
	local calls, lastDt = 0, nil
	r:Every(10, "j", function(dt) calls += 1; lastDt = dt end)
	frames(r, c, 1, 1 / 60)
	eq(calls, 1)
	c.T += 2 -- a 2 s hitch
	r:Step(2)
	eq(calls, 2, "one call after the hitch, not twenty")
	near(lastDt, 2, 1e-6)
	frames(r, c, 3, 1 / 60)
	eq(calls, 2, "next call waits a full interval")
end)

test("Scheduler resumes a pass that returns true on the next frame", function()
	local c = clock()
	local r = runner(c)
	local calls, deadlines = 0, {}
	r:Every(1, "pass", function(_, deadline)
		calls += 1
		table.insert(deadlines, deadline)
		return calls < 3
	end)
	frames(r, c, 3, 1 / 60)
	eq(calls, 3, "continued on consecutive frames")
	near(deadlines[1], c.T - 2 / 60 + 0.001, 1e-6, "deadline = start + 1 ms")
	frames(r, c, 30, 1 / 60)
	eq(calls, 3, "then waits for its 1 Hz schedule")
end)

test("Scheduler carries over time debt", function()
	local c = clock()
	local r = runner(c, { FrameBudget = 1 })
	local heavy, light = 0, 0
	r:Every(0, "heavy", function()
		heavy += 1
		c.T += 0.005 -- uses 5 ms of a 1 ms budget
	end)
	r:Every(0, "light", function() light += 1 end)
	frames(r, c, 10, 0)
	truthy(heavy <= 2 and heavy >= 1, "heavy job sits out frames to repay its debt, ran " .. heavy)
	eq(light, 10, "other jobs are not affected")
end)

test("Scheduler frame budget is shared round robin", function()
	local c = clock()
	local r = runner(c, { FrameBudget = 0.003 })
	local ran = {}
	for i = 1, 6 do
		ran[i] = 0
		r:Every(0, "job" .. i, function()
			ran[i] += 1
			c.T += 0.001
		end)
	end
	r:Step(0)
	local first = 0
	for i = 1, 6 do first += ran[i] end
	eq(first, 3, "frame budget stops the pass")
	r:Step(0)
	for i = 1, 6 do
		eq(ran[i], 1, "every job ran once over two frames (job " .. i .. ")")
	end
end)

test("Scheduler isolates errors and warns once", function()
	local c = clock()
	local warnings = {}
	local r = runner(c, { Warn = function(m) table.insert(warnings, m) end })
	local calls, ok = 0, 0
	local bad = r:Every(0, "bad", function()
		calls += 1
		error("nope")
	end)
	r:Every(0, "good", function() ok += 1 end)
	frames(r, c, 5, 1 / 60)
	eq(calls, 5, "the failing job keeps its schedule")
	eq(ok, 5)
	eq(#warnings, 1, "warned once")
	truthy(warnings[1]:find("bad", 1, true), "warning names the job")
	eq(r:Stats().ByName.bad.Errors, 5)
	bad:Stop()
	frames(r, c, 2, 1 / 60)
	eq(calls, 5, "stopped")
	eq(r:Count(), 1)
end)

test("Scheduler stop inside a job, SetRate, count callback", function()
	local c = clock()
	local r = runner(c)
	local counts = {}
	r.OnCountChanged = function(n) table.insert(counts, n) end
	local handle
	local calls = 0
	handle = r:Every(0, "self-stop", function()
		calls += 1
		handle:Stop()
	end)
	frames(r, c, 3, 1 / 60)
	eq(calls, 1)
	eq(counts[#counts], 0, "count callback reports an empty runner")
	local n = 0
	local h = r:Every(1, "rate", function() n += 1 end)
	frames(r, c, 1, 1 / 60)
	h:SetRate(30)
	frames(r, c, 30, 1 / 60)
	truthy(n >= 15, "SetRate raises the rate, got " .. n)
end)

-- POOL ----------------------------------------------------------------------------------------------
local Pool = L.Require("ReplicatedStorage.Perf.Pool")

test("Pool reuse, Max, Dropped, Reset, Stats", function()
	local made, resets = 0, 0
	local pool = Pool.new({
		Create = function() made += 1; return { Id = made } end,
		Reset = function() resets += 1 end,
		Max = 3,
		Prewarm = 2,
	})
	eq(made, 2, "prewarmed")
	local a, b, c3 = pool:Acquire(), pool:Acquire(), pool:Acquire()
	truthy(a and b and c3)
	eq(made, 3)
	eq(pool:Acquire(), nil, "at Max without Steal")
	eq(pool:Release(a), true)
	eq(pool:Release(a), false, "double release ignored")
	eq(pool:Release({}), false, "foreign object ignored")
	eq(resets, 1)
	eq(pool:Acquire(), a, "reused")
	local s = pool:Stats()
	eq(s.Active, 3)
	eq(s.Free, 0)
	eq(s.Created, 3)
	eq(s.Dropped, 1)
	eq(s.Peak, 3)
	truthy(s.Reused >= 2)
end)

test("Pool Steal recycles the oldest active object", function()
	local n = 0
	local pool = Pool.new({ Create = function() n += 1; return { Id = n } end, Max = 2, Steal = true })
	local first = pool:Acquire()
	local second = pool:Acquire()
	local third = pool:Acquire()
	eq(third, first, "oldest stolen")
	truthy(pool:IsActive(second) and pool:IsActive(third))
	eq(pool:Stats().Active, 2)
end)

test("Pool hides Instances in place (Modifier) and restores exactly", function()
	local folder = roblox.Instance.new("Folder")
	local pool = Pool.new({
		Create = function()
			local p = roblox.Instance.new("Part")
			p.LocalTransparencyModifier = 0 -- rbx-dom has no default for this runtime-only property
			local light = roblox.Instance.new("PointLight")
			light.Enabled = true
			light.Parent = p
			local off = roblox.Instance.new("ParticleEmitter")
			off.Enabled = false
			off.Parent = p
			return p
		end,
		Parent = folder,
		Prewarm = 1,
	})
	local part = folder:GetChildren()[1]
	truthy(part, "prewarmed object is parented once")
	eq(part.LocalTransparencyModifier, 1, "free object hidden")
	eq(part.PointLight.Enabled, false)
	local got = pool:Acquire()
	eq(got, part)
	eq(got.Parent, folder, "no reparent")
	eq(got.LocalTransparencyModifier, 0)
	eq(got.PointLight.Enabled, true, "restored")
	eq(got.ParticleEmitter.Enabled, false, "an emitter that was off stays off")
	pool:Release(got)
	eq(got.Parent, folder)
	eq(got.LocalTransparencyModifier, 1)
	pool:Destroy()
	eq(#folder:GetChildren(), 0, "Destroy removes every object")
	eq(pool:Acquire(), nil)
end)

test("Pool Folder and Transparency modes", function()
	local world = roblox.Instance.new("Folder")
	local pool = Pool.new({ Create = function() return roblox.Instance.new("Part") end, Parent = world, Hide = "Folder" })
	local p = pool:Acquire()
	eq(p.Parent, world)
	pool:Release(p)
	truthy(p.Parent ~= world and p.Parent.Name == "PerfPoolHidden", "moved to the hidden folder")
	eq(pool:Acquire(), p)
	eq(p.Parent, world)
	local server = Pool.new({
		Create = function()
			local q = roblox.Instance.new("Part")
			q.Transparency = 0.25
			return q
		end,
		Parent = world,
		Hide = "Transparency",
	})
	local q = server:Acquire()
	server:Release(q)
	eq(q.Transparency, 1)
	server:Acquire()
	eq(q.Transparency, 0.25, "original transparency restored")
end)

-- QUALITY (pure) --------------------------------------------------------------------------------------
local Quality = L.Require("ReplicatedStorage.Perf.Quality")

test("Quality.NormalizePreference / AutoTier / Resolve", function()
	eq(Quality.NormalizePreference("low"), "Low")
	eq(Quality.NormalizePreference("HIGH"), "High")
	eq(Quality.NormalizePreference("Medium"), "Medium")
	eq(Quality.NormalizePreference(nil), "Auto")
	eq(Quality.NormalizePreference(5), "Auto")
	eq(Quality.NormalizePreference("Ultra"), "Auto")
	local cases = { { 0, "High" }, { 1, "Low" }, { 3, "Low" }, { 4, "Medium" }, { 6, "Medium" }, { 7, "High" }, { 10, "High" } }
	for _, c in ipairs(cases) do
		eq(Quality.AutoTier(c[1], false), c[2], "SavedQualityLevel " .. c[1])
	end
	eq(Quality.AutoTier(0, true), "Medium", "touch without keyboard caps at Medium")
	eq(Quality.AutoTier(2, true), "Low")
	eq(Quality.Resolve("Low", "High", 0), "Low")
	eq(Quality.Resolve("High", "Low", 2), "High", "an explicit choice ignores device and watchdog")
	eq(Quality.Resolve("Auto", "High", 1), "Medium")
	eq(Quality.Resolve("Auto", "Medium", 5), "Low")
	eq(Quality.Resolve(nil, "High", 0), "High")
	eq(Quality.TouchOnly(true, false), true)
	eq(Quality.TouchOnly(true, true), false)
	eq(Quality.TouchOnly(false, false), false)
end)

test("Quality budgets follow the plan and WorldEventConfig.FX", function()
	local fx = L.Require("ReplicatedStorage.WorldEvents.WorldEventConfig").FX
	for key, row in pairs(Quality.Budgets) do
		for _, tier in ipairs(Quality.Tiers) do
			truthy(type(row[tier]) == "number" and row[tier] >= 0, key .. "." .. tier)
		end
		truthy(row.High >= row.Medium and row.Medium >= row.Low, key .. " never grows on a lower tier")
	end
	for _, tier in ipairs(Quality.Tiers) do
		eq(Quality.Budget("Particles", tier), fx[tier].Particles)
		eq(Quality.Budget("Debris", tier), fx[tier].Debris)
		eq(Quality.Budget("Dogs", tier), fx[tier].Dogs)
	end
	eq(Quality.Budget("Lights", "High"), 24)
	eq(Quality.Budget("Lights", "Medium"), 16)
	eq(Quality.Budget("Lights", "Low"), 8)
	eq(Quality.Budget("Highlights", "Low"), 2)
	eq(Quality.Budget("Arrows", "High"), 32)
	eq(Quality.Budget("LabParts", "Low"), 600)
	eq(Quality.Budget("NoSuchBudget"), nil)
end)

test("Quality.Watchdog steps down, recovers slowly, never flaps", function()
	local w = Quality.Watchdog.new()
	local function seconds(n, fps)
		local result = 0
		for _ = 1, n do
			local r = w:Sample(fps, 1)
			if r ~= 0 then result = r end
		end
		return result
	end
	eq(seconds(15, 10), 0, "warmup ignored")
	eq(seconds(9, 30), 0, "a block needs 10 s")
	eq(seconds(1, 30), -1, "10 s below 40 FPS steps down")
	eq(w.Steps, 1)
	eq(seconds(10, 45), 0, "45 FPS is fine")
	eq(seconds(10, 20), -1)
	eq(seconds(10, 20), 0, "at most two steps")
	eq(w.Steps, 2)
	eq(seconds(50, 60), 0, "recovery needs 60 s")
	eq(seconds(10, 60), 1, "60 s at 55+ steps back up")
	eq(w.Steps, 1)
	eq(seconds(10, 30), -1, "dropping again soon after a recovery")
	eq(w.RecoverAfter, 120, "doubles the recovery time")
	eq(seconds(60, 60), 0)
	eq(seconds(60, 60), 1, "now 120 s")
	w:Sample(100, 3)
	w:Pause()
	eq(w.BlockTime, 0, "Pause drops the partial block")
	w:Reset()
	eq(w.Steps, 0)
end)

-- QUALITY (runtime with a fake client) -------------------------------------------------------------
local function freshClient(options)
	options = options or {}
	L.Reset()
	local player = fakePlayer()
	for k, v in pairs(options.Attributes or {}) do
		player.Attributes[k] = v
	end
	L.Stubs.Players.LocalPlayer = player
	L.Stubs.RunService.IsClient = function() return true end
	L.Stubs.UserInputService = {
		TouchEnabled = options.Touch == true,
		KeyboardEnabled = options.Touch ~= true,
		WindowFocused = noSignal,
		WindowFocusReleased = noSignal,
	}
	L.Stubs.GuiService = { ReducedMotionEnabled = options.SystemReduced == true, GetPropertyChangedSignal = function() return noSignal end }
	local scheduler = L.Require("ReplicatedStorage.Perf.Scheduler")
	local c = clock()
	scheduler.Shared.Clock = c.Now
	scheduler.Shared.Profile = false
	local quality = L.Require("ReplicatedStorage.Perf.Quality")
	return quality, player, scheduler, c
end

test("Quality starts on Auto and publishes the legacy attributes", function()
	local quality, player = freshClient()
	eq(quality.Tier(), "High")
	eq(quality.Preference(), "Auto")
	eq(quality.Reduced(), false)
	eq(player.Attributes.WorldEventFX, "High")
	eq(player.Attributes.LowFX, false)
	eq(player.Attributes.ReducedMotion, false)
	local writes = player.Writes.WorldEventFX
	quality.Start()
	quality.Tier()
	eq(player.Writes.WorldEventFX, writes, "attributes are written only when they change")
end)

test("Quality follows PAWPAD (WorldEventFX) and the saved setting both ways", function()
	local quality, player = freshClient()
	local changes = {}
	quality.Changed:Connect(function(tier, reduced) table.insert(changes, tier .. ":" .. tostring(reduced)) end)
	player:SetAttribute("WorldEventFX", "Low") -- PAWPAD cycles the level
	eq(quality.Preference(), "Low")
	eq(quality.Tier(), "Low")
	eq(player.Attributes.LowFX, true, "LowFX is now set for the 12 legacy readers")
	player:SetAttribute("Setting_Quality", "Medium") -- the server publishes the saved choice
	eq(quality.Tier(), "Medium")
	eq(player.Attributes.WorldEventFX, "Medium", "WorldEventFX mirrors the tier in use")
	eq(player.Attributes.LowFX, false)
	quality.SetPreference("auto")
	eq(quality.Preference(), "Auto")
	eq(quality.Tier(), "High")
	eq(changes[1], "Low:false")
	eq(changes[#changes], "High:false")
end)

test("Quality reduced motion: system setting, saved setting, PAWPAD", function()
	local quality, player = freshClient({ SystemReduced = true })
	eq(quality.Reduced(), true, "Roblox accessibility setting")
	eq(player.Attributes.ReducedMotion, true)
	local q2, p2 = freshClient({ Attributes = { Setting_ReducedMotion = true } })
	eq(q2.Reduced(), true, "saved in-game setting")
	p2:SetAttribute("ReducedMotion", false) -- PAWPAD toggles it off
	eq(q2.Reduced(), false)
	eq(p2.Attributes.ReducedMotion, false)
	p2:SetAttribute("Setting_ReducedMotion", true)
	eq(q2.Reduced(), true)
end)

test("Quality phone default and saved preference at join", function()
	local phone, phonePlayer = freshClient({ Touch = true })
	eq(phone.Tier(), "Medium", "touch without keyboard starts on Medium")
	eq(phonePlayer.Attributes.WorldEventFX, "Medium")
	local saved = freshClient({ Attributes = { Setting_Quality = "Low", WorldEventFX = "High" } })
	eq(saved.Tier(), "Low", "the saved setting wins over a stale session value")
end)

test("Quality FPS watchdog steps down on Auto only", function()
	local quality, player, scheduler, c = freshClient()
	eq(quality.Tier(), "High")
	for _ = 1, 30 * 20 do -- 30 s at 20 FPS
		c.T += 0.05
		scheduler.Shared:Step(0.05)
	end
	eq(quality.Tier(), "Medium", "a slow client steps down one tier")
	eq(player.Attributes.WorldEventFX, "Medium")
	quality.SetPreference("High")
	for _ = 1, 30 * 20 do
		c.T += 0.05
		scheduler.Shared:Step(0.05)
	end
	eq(quality.Tier(), "High", "an explicit choice is never overridden")
	eq(scheduler.Shared:Count(), 0, "the watchdog job stops off Auto")
end)

-- LOD ------------------------------------------------------------------------------------------------
test("Lod.LevelFor thresholds and hysteresis", function()
	L.Reset()
	local Lod = L.Require("ReplicatedStorage.Perf.Lod")
	eq(Lod.LevelFor(50, 100, 200), 0)
	eq(Lod.LevelFor(150, 100, 200), 1)
	eq(Lod.LevelFor(250, 100, 200), 2)
	eq(Lod.LevelFor(105, 100, 200, 0), 0, "inside the +10 % band stays detailed")
	eq(Lod.LevelFor(111, 100, 200, 0), 1)
	eq(Lod.LevelFor(95, 100, 200, 1), 1, "inside the -10 % band stays reduced")
	eq(Lod.LevelFor(89, 100, 200, 1), 0)
	eq(Lod.LevelFor(215, 100, 200, 1), 1)
	eq(Lod.LevelFor(221, 100, 200, 1), 2)
	eq(Lod.LevelFor(185, 100, 200, 2), 2)
	eq(Lod.LevelFor(179, 100, 200, 2), 1)
	eq(Lod.LevelFor(500, 100, nil), 1, "no Far: two levels")
	eq(Lod.LevelFor(500, 100, 200, 0), 2, "a jump crosses both boundaries")
end)

test("Lod view cone matches DogAnimations", function()
	local Lod = L.Require("ReplicatedStorage.Perf.Lod")
	local fov, aspect = 70, 16 / 9
	local vertical = math.rad(fov) / 2
	local expected = math.atan(math.tan(vertical) * math.sqrt(1 + aspect * aspect)) + math.rad(12)
	near(Lod.ViewHalfAngle(fov, aspect), expected, 1e-9)
	local half = Lod.ViewHalfAngle(fov, aspect)
	local forward = Vector3.new(0, 0, -1)
	eq(Lod.InView(Vector3.new(0, 0, -50), forward, 2, half), true, "ahead")
	eq(Lod.InView(Vector3.new(0, 0, 50), forward, 2, half), false, "behind")
	eq(Lod.InView(Vector3.new(0, 0, 3), forward, 5, half), true, "camera inside the object")
	eq(Lod.InView(Vector3.new(100, 0, 1), forward, 2, half), false, "far to the side")
	eq(Lod.InView(Vector3.new(100, 0, 1), forward, 150, half), true, "a big object reaches into view")
end)

test("Lod runtime: initial levels, switches per tick, cull, destroy", function()
	L.Reset()
	L.Workspace = { CurrentCamera = { CFrame = CFrame.new(0, 0, 0), ViewportSize = Vector2.new(1600, 900), FieldOfView = 70 } }
	local scheduler = L.Require("ReplicatedStorage.Perf.Scheduler")
	local c = clock()
	scheduler.Shared.Clock = c.Now
	scheduler.Shared.Profile = false
	local Lod = L.Require("ReplicatedStorage.Perf.Lod")
	local function tick()
		c.T += 0.2
		scheduler.Shared:Step(0.2)
	end
	local positions, levels, calls = {}, {}, 0
	local handles = {}
	for i = 1, 20 do
		positions[i] = Vector3.new(0, 0, -10 * i) -- in front of the camera, 10..200 studs
		handles[i] = Lod.Register("slot" .. i, {
			Near = 60,
			Far = 150,
			Position = function() return positions[i] end,
			OnLevel = function(level)
				calls += 1
				levels[i] = level
			end,
		})
	end
	tick()
	eq(calls, 20, "first levels are assigned in one tick (MaxInitial)")
	eq(levels[1], 0)
	eq(levels[10], 1)
	eq(levels[20], 2)
	for i = 1, 20 do
		positions[i] = Vector3.new(0, 0, -400) -- everything leaves at once
	end
	calls = 0
	tick()
	eq(calls, Lod.MaxSwitches, "at most MaxSwitches changes per tick")
	tick()
	tick()
	for i = 1, 20 do
		eq(levels[i], 2, "slot " .. i .. " eventually far")
	end
	-- Behind the camera with Cull: beyond Near counts as far, inside Near stays detailed.
	local culled = {}
	Lod.Register("behind", { Near = 30, Far = 300, Cull = true, Position = function() return Vector3.new(0, 0, 80) end, OnLevel = function(l) culled.far = l end })
	Lod.Register("close", { Near = 30, Far = 300, Cull = true, Position = function() return Vector3.new(0, 0, 10) end, OnLevel = function(l) culled.near = l end })
	tick()
	eq(culled.far, 2)
	eq(culled.near, 0)
	for _, h in ipairs(handles) do
		h:Destroy()
	end
	calls = 0
	positions[1] = Vector3.zero
	tick()
	eq(calls, 0, "destroyed handles get no calls")
	eq(Lod.Count(), 2)
end)

print(string.format("perf: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("perf tests failed")
end
