-- One shared Heartbeat for every periodic client job (docs/OVERHAUL.md, "Клиентский фундамент").
-- Feature code never connects its own RenderStepped / Heartbeat (tests/perf_lint.luau checks it):
--
--   local Scheduler = require(ReplicatedStorage.Perf.Scheduler)
--   local job = Scheduler.Every(5, "Showcase.Lod", function(dt, deadline)
--       ... -- dt = seconds since this job last ran
--       return false -- or true: "work left", the job is called again next frame
--   end)
--   job:SetRate(2); job:Stop()
--
-- Rules the scheduler enforces:
--   * Rate: a job runs at most `hz` times per second (hz <= 0 or >= 60 = every frame). A hitch
--     never causes a burst of catch-up calls.
--   * Time slicing: each call should finish by `deadline` (os.clock() + TaskBudget, 1 ms). A long
--     pass returns true to continue on the next frame. Time a call spends over its budget becomes
--     debt that carries over: the job sits out frames until the debt is repaid, so its average
--     stays near TaskBudget per frame. All jobs together get FrameBudget per frame; jobs still due
--     when it runs out go first on the next frame (round robin, nobody starves).
--   * Profiling: each call is wrapped in debug.profilebegin("Perf:" .. name) for the MicroProfiler.
--   * Errors: a failing call is caught (pcall), counted and reported with warn once per job; the
--     job keeps its schedule.
-- Scheduler.new(options) makes an independent runner with its own clock and no Heartbeat (tests).
local RunService = game:GetService("RunService")

local Scheduler = {}

local DEFAULT_TASK_BUDGET = 0.001
local DEFAULT_FRAME_BUDGET = 0.004
local MAX_DEBT = 0.05 -- a single huge hitch costs at most ~50 skipped frames

local profileBegin = (debug :: any).profilebegin
local profileEnd = (debug :: any).profileend

export type Options = {
	Clock: (() -> number)?, -- default os.clock
	TaskBudget: number?, -- seconds per job per frame (default 0.001)
	FrameBudget: number?, -- seconds for all jobs in one frame (default 0.004)
	Profile: boolean?, -- debug.profilebegin labels (default true when available)
	Warn: ((string) -> ())?, -- default warn
}

local Runner = {}
Runner.__index = Runner

local Handle = {}
Handle.__index = Handle

local function interval(hz: number): number
	if hz ~= hz or hz <= 0 or hz >= 60 then
		return 0
	end
	return 1 / hz
end

function Scheduler.new(options: Options?): any
	local o: any = options or {}
	local self: any = setmetatable({}, Runner)
	self.Clock = o.Clock or os.clock
	self.TaskBudget = o.TaskBudget or DEFAULT_TASK_BUDGET
	self.FrameBudget = o.FrameBudget or DEFAULT_FRAME_BUDGET
	self.Profile = o.Profile ~= false and profileBegin ~= nil
	self.Warn = o.Warn or warn
	self.Jobs = {}
	self.Cursor = 1
	self.Frames = 0
	self.Time = 0
	self.Dirty = false
	return self
end

-- Adds a job. fn(dt, deadline) -> boolean? (true = continue next frame).
function Runner.Every(self: any, hz: number, name: string, fn: (number, number) -> boolean?): any
	assert(type(fn) == "function", "Scheduler.Every: fn must be a function")
	local now = self.Clock()
	local job: any = setmetatable({
		Runner = self,
		Name = tostring(name or "job"),
		Interval = interval(hz),
		Fn = fn,
		Next = now, -- due on the next step
		Last = nil,
		Debt = 0,
		Pending = false,
		Running = true,
		Calls = 0,
		Errors = 0,
		Warned = false,
		Total = 0,
		Max = 0,
	}, Handle)
	table.insert(self.Jobs, job)
	if self.OnCountChanged then
		self.OnCountChanged(#self.Jobs)
	end
	return job
end

function Handle.Stop(self: any)
	if not self.Running then
		return
	end
	self.Running = false
	self.Runner.Dirty = true
	self.Runner:_compact()
end

function Handle.SetRate(self: any, hz: number)
	self.Interval = interval(hz)
	self.Next = math.min(self.Next, self.Runner.Clock() + self.Interval)
end

Handle.Destroy = Handle.Stop
Handle.Disconnect = Handle.Stop

function Runner._compact(self: any)
	if not self.Dirty or self.Stepping then
		return
	end
	self.Dirty = false
	local kept = {}
	for _, job in ipairs(self.Jobs) do
		if job.Running then
			table.insert(kept, job)
		end
	end
	self.Jobs = kept
	if self.Cursor > #kept then
		self.Cursor = 1
	end
	if self.OnCountChanged then
		self.OnCountChanged(#kept)
	end
end

function Runner._run(self: any, job: any, now: number)
	local dt = job.Last and (now - job.Last) or job.Interval
	job.Last = now
	local deadline = now + self.TaskBudget
	local profiling = self.Profile
	if profiling then
		profileBegin("Perf:" .. job.Name)
	end
	local ok, result = pcall(job.Fn, dt, deadline)
	if profiling then
		profileEnd()
	end
	local used = self.Clock() - now
	job.Calls += 1
	job.Total += used
	if used > job.Max then
		job.Max = used
	end
	if used > self.TaskBudget then
		job.Debt = math.min(MAX_DEBT, job.Debt + used - self.TaskBudget)
	end
	if not ok then
		job.Errors += 1
		job.Pending = false
		if not job.Warned then
			job.Warned = true
			self.Warn(string.format("Perf.Scheduler: job %s failed: %s", job.Name, tostring(result)))
		end
	else
		job.Pending = result == true
	end
	if not job.Pending then
		-- Keep the average rate exact, but never schedule a burst after a hitch.
		job.Next += job.Interval
		if job.Next < now then
			job.Next = now + job.Interval
		end
	end
	return used
end

-- One frame. The shared runner calls it from Heartbeat; tests call it directly.
function Runner.Step(self: any, dt: number?)
	self.Frames += 1
	self.Time += dt or 0
	local jobs = self.Jobs
	local count = #jobs
	if count == 0 then
		return
	end
	self.Stepping = true
	local started = self.Clock()
	local spent = 0
	local start = self.Cursor
	if start > count then
		start = 1
	end
	local nextCursor = start
	for offset = 0, count - 1 do
		local index = (start - 1 + offset) % count + 1
		local job = jobs[index]
		if job.Running then
			if job.Debt > 0 then
				job.Debt = math.max(0, job.Debt - self.TaskBudget)
			elseif job.Pending or started >= job.Next then
				if spent >= self.FrameBudget then
					nextCursor = index -- out of frame budget: this job goes first next frame
					break
				end
				local now = self.Clock()
				spent += self:_run(job, now)
				nextCursor = index % count + 1
			end
		end
	end
	self.Cursor = nextCursor
	self.Stepping = false
	self:_compact()
end

function Runner.Count(self: any): number
	local n = 0
	for _, job in ipairs(self.Jobs) do
		if job.Running then
			n += 1
		end
	end
	return n
end

-- Per-job counters for debugging: {Jobs, Frames, ByName = {[name] = {Calls, Errors, AvgMs, MaxMs, Hz}}}.
function Runner.Stats(self: any): any
	local byName = {}
	for _, job in ipairs(self.Jobs) do
		if job.Running then
			byName[job.Name] = {
				Calls = job.Calls,
				Errors = job.Errors,
				AvgMs = job.Calls > 0 and job.Total / job.Calls * 1000 or 0,
				MaxMs = job.Max * 1000,
				Hz = job.Interval > 0 and 1 / job.Interval or 60,
			}
		end
	end
	return { Jobs = self:Count(), Frames = self.Frames, ByName = byName }
end

-- The shared runner: Heartbeat is connected only while it has jobs.
local shared: any = Scheduler.new()
local connection: RBXScriptConnection? = nil
shared.OnCountChanged = function(count: number)
	if count > 0 and not connection then
		connection = RunService.Heartbeat:Connect(function(dt)
			shared:Step(dt)
		end)
	elseif count == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end
Scheduler.Shared = shared

function Scheduler.Every(hz: number, name: string, fn: (number, number) -> boolean?): any
	return shared:Every(hz, name, fn)
end

-- Frames counted by the shared runner and the seconds they covered (the FPS watchdog reads it).
function Scheduler.FrameCounter(): (number, number)
	return shared.Frames, shared.Time
end

function Scheduler.Stats(): any
	return shared:Stats()
end

return Scheduler
