-- Distance levels of detail for client-built models (decor, showcase stands, item models, mine
-- levels). Level 0 = full detail (closer than Near), 1 = reduced (Near..Far), 2 = far / hidden.
--
--   local Lod = require(ReplicatedStorage.Perf.Lod)
--   local handle = Lod.Register(model, {
--       Near = 80, Far = 200,           -- studs; default Quality.Budget("LodNear" / "LodFar")
--       Radius = 6,                     -- object radius for the view cone (default from the bounds)
--       Cull = true,                    -- outside the camera's view (and beyond Near) counts as level 2
--       Position = function() return slotCFrame.Position end, -- optional; default: the target's pivot
--       OnLevel = function(level, handle) ... end, -- called on every change (and once at start)
--   })
--   The target is normally a Model / BasePart / Attachment. With Position it can be any key, so a
--   feature can register a slot whose model is only built when it comes near.
--   handle.Level; handle:SetRange(near, far); handle:Destroy()
--
-- Tag path (no code): tag a Model or BasePart "DOGROTS_Lod" (Builder does it with opts.Lod).
-- Attributes LodNear / LodFar / LodCull override the defaults. On level 1 descendants with
-- LodDetail = true are hidden; on level 2 everything is hidden except LodKeep = true parts (far
-- silhouettes). Hidden = LocalTransparencyModifier 1; lights / emitters / beams are switched off
-- only when the model is FXManaged (otherwise WorldDetailQuality owns them).
--
-- Rules: evaluated at Lod.Rate (5 Hz) through Perf.Scheduler, the pass is time sliced, distance
-- thresholds have ±10 % hysteresis (no flicker at a boundary), at most Lod.MaxSwitches level
-- changes are applied per tick (nearest first) plus Lod.MaxInitial first assignments.
-- tests/perf.luau covers the maths (LevelFor, ViewHalfAngle, InView) and the runtime in Lune.
local CollectionService = game:GetService("CollectionService")

local Scheduler = require(script.Parent.Scheduler)
local Quality = require(script.Parent.Quality)

local Lod = {}

Lod.Tag = "DOGROTS_Lod"
Lod.Rate = 5
Lod.Hysteresis = 0.1
Lod.MaxSwitches = 8
Lod.MaxInitial = 64
Lod.ViewMargin = math.rad(12) -- objects entering the view are already at their level

------------------------------------------------------------------------------------------------
-- Pure maths
------------------------------------------------------------------------------------------------

-- Level for `distance` given the current level (nil = first evaluation). A boundary is crossed
-- outwards only beyond threshold * (1 + h) and back only inside threshold * (1 - h).
function Lod.LevelFor(distance: number, near: number, far: number?, current: number?, hysteresis: number?): number
	local h = hysteresis or Lod.Hysteresis
	local farValue = far or math.huge
	local function beyond(threshold: number, lower: number): boolean
		if current == nil then
			return distance > threshold
		elseif current <= lower then
			return distance > threshold * (1 + h)
		end
		return distance >= threshold * (1 - h)
	end
	local level = 0
	if beyond(near, 0) then
		level = 1
	end
	if farValue < math.huge and beyond(farValue, 1) then
		level = 2
	end
	return level
end

-- Half angle (radians) of the cone around the camera's look vector that contains the whole
-- screen (the corner direction) plus a margin. Same maths as DogAnimations.viewHalfAngle.
function Lod.ViewHalfAngle(fieldOfView: number, aspect: number?, margin: number?): number
	local vertical = math.rad(math.clamp(fieldOfView, 1, 120)) / 2
	local a = aspect or 16 / 9
	return math.atan(math.tan(vertical) * math.sqrt(1 + a * a)) + (margin or Lod.ViewMargin)
end

-- Whether a sphere (offset from the camera, radius) intersects the view cone.
function Lod.InView(offset: Vector3, forward: Vector3, radius: number, halfAngle: number): boolean
	local distance = offset.Magnitude
	if distance <= math.max(radius, 1e-3) then
		return true
	end
	local slack = math.asin(math.min(1, radius / distance))
	return offset:Dot(forward) / distance >= math.cos(math.min(math.pi, halfAngle + slack))
end

------------------------------------------------------------------------------------------------
-- Runtime
------------------------------------------------------------------------------------------------

local entries: { any } = {}
local byTarget: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local cursor = 1
local job: any = nil

local Handle = {}
Handle.__index = Handle

local function position(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		return target:GetPivot().Position
	elseif target:IsA("Attachment") then
		return target.WorldPosition
	end
	return nil
end

local function radiusOf(target: Instance): number
	if target:IsA("BasePart") then
		return target.Size.Magnitude / 2
	elseif target:IsA("Model") then
		local ok, _, size = pcall(function()
			return target:GetBoundingBox()
		end)
		if ok and size then
			return size.Magnitude / 2
		end
	end
	return 4
end

local pending: { any } = {}
local initial: { any } = {}

local view: any = { Near = 160, Far = 320 }

local function evaluate(entry: any)
	local target = entry.Target
	if typeof(target) == "Instance" and not target.Parent then
		return
	end
	local pos = if entry.Position then entry.Position() else position(target)
	if not pos then
		return
	end
	local offset = pos - view.Origin
	local distance = offset.Magnitude
	local near = entry.Near or view.Near
	local level = Lod.LevelFor(distance, near, entry.Far or view.Far, entry.Level)
	if entry.Cull and level < 2 and distance > near and not Lod.InView(offset, view.Forward, entry.Radius, view.HalfAngle) then
		level = 2
	end
	if level ~= entry.Level then
		entry.Want, entry.Distance = level, distance
		table.insert(entry.Level == nil and initial or pending, entry)
	else
		entry.Want = nil
	end
end

local function apply(list: { any }, limit: number)
	table.sort(list, function(a, b)
		return a.Distance < b.Distance
	end)
	for i = 1, math.min(limit, #list) do
		local entry = list[i]
		if not entry.Destroyed and entry.Want ~= nil then
			entry.Level = entry.Want
			entry.Want = nil
			local ok, err = pcall(entry.OnLevel, entry.Level, entry)
			if not ok and not entry.Warned then
				entry.Warned = true
				local name = typeof(entry.Target) == "Instance" and entry.Target:GetFullName() or tostring(entry.Target)
				warn("Perf.Lod: OnLevel failed for " .. name .. ": " .. tostring(err))
			end
		end
	end
	table.clear(list)
end

local function step(_: number, deadline: number): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	if cursor == 1 then
		-- One camera snapshot and one set of default ranges per pass.
		local frame = camera.CFrame
		local viewport = camera.ViewportSize
		view.Origin, view.Forward = frame.Position, frame.LookVector
		view.HalfAngle = Lod.ViewHalfAngle(camera.FieldOfView, viewport.Y > 0 and viewport.X / viewport.Y or nil)
		view.Near = Quality.Budget("LodNear") or 160
		view.Far = Quality.Budget("LodFar") or 320
	end
	local count = #entries
	while cursor <= count do
		local entry = entries[cursor]
		cursor += 1
		if not entry.Destroyed then
			evaluate(entry)
		end
		if cursor % 64 == 0 and os.clock() > deadline then
			return true -- continue the pass next frame
		end
	end
	cursor = 1
	apply(initial, Lod.MaxInitial)
	apply(pending, Lod.MaxSwitches)
	-- Drop destroyed entries once per full pass.
	local kept = {}
	for _, entry in ipairs(entries) do
		if not entry.Destroyed then
			table.insert(kept, entry)
		end
	end
	entries = kept
	if #entries == 0 and job then
		job:Stop()
		job = nil
	end
	return false
end

function Lod.Register(target: any, options: any?): any
	local o = options or {}
	assert(target ~= nil, "Lod.Register: target is required")
	assert(typeof(target) == "Instance" or type(o.Position) == "function", "Lod.Register: Position is required for a non-Instance target")
	assert(type(o.OnLevel) == "function", "Lod.Register: OnLevel is required")
	local existing = byTarget[target]
	if existing then
		existing:Destroy()
	end
	local entry = setmetatable({
		Target = target,
		Near = o.Near,
		Far = o.Far,
		Radius = o.Radius or (typeof(target) == "Instance" and radiusOf(target)) or 4,
		Cull = o.Cull == true,
		Position = o.Position,
		OnLevel = o.OnLevel,
		Level = nil,
	}, Handle)
	byTarget[target] = entry
	table.insert(entries, entry)
	if not job then
		cursor = 1
		job = Scheduler.Every(Lod.Rate, "Lod", step)
	end
	return entry
end

function Handle.SetRange(self: any, near: number?, far: number?)
	self.Near, self.Far = near, far
end

function Handle.Destroy(self: any)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if byTarget[self.Target] == self then
		byTarget[self.Target] = nil
	end
end

function Lod.Count(): number
	local n = 0
	for _, entry in ipairs(entries) do
		if not entry.Destroyed then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------------------------------------
-- Tag path: CollectionService "DOGROTS_Lod"
------------------------------------------------------------------------------------------------

local FX_CLASSES = { "Light", "ParticleEmitter", "Beam", "Trail", "SurfaceGui", "BillboardGui" }
local function isFx(object: Instance): boolean
	for _, class in ipairs(FX_CLASSES) do
		if object:IsA(class) then
			return true
		end
	end
	return false
end

local function managed(root: Instance): boolean
	local node: Instance? = root
	while node and node ~= workspace do
		if node:GetAttribute("FXManaged") == true then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Whether a descendant is visible at `level` under the tag rules.
local function shown(object: Instance, level: number): boolean
	if level >= 2 then
		return object:GetAttribute("LodKeep") == true
	elseif level == 1 then
		return object:GetAttribute("LodDetail") ~= true
	end
	return true
end

local fxEnabled: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function applyTagged(root: Instance, level: number, fx: boolean)
	local function visit(object: Instance)
		if object:IsA("BasePart") then
			object.LocalTransparencyModifier = shown(object, level) and 0 or 1
		elseif fx and isFx(object) then
			local item: any = object
			local part = object:FindFirstAncestorWhichIsA("BasePart")
			local visible = if part then shown(part, level) else level < 2
			if fxEnabled[object] == nil then
				fxEnabled[object] = item.Enabled
			end
			item.Enabled = visible and fxEnabled[object]
		end
	end
	visit(root)
	for _, object in ipairs(root:GetDescendants()) do
		visit(object)
	end
end

local tagged: { [Instance]: any } = {}

local function attachTagged(target: Instance)
	if tagged[target] or not (target:IsA("Model") or target:IsA("BasePart")) then
		return
	end
	local near, far = target:GetAttribute("LodNear"), target:GetAttribute("LodFar")
	local fx = managed(target)
	local record: any = {}
	record.Handle = Lod.Register(target, {
		Near = type(near) == "number" and near or nil,
		Far = type(far) == "number" and far or nil,
		Cull = target:GetAttribute("LodCull") == true,
		OnLevel = function(level)
			applyTagged(target, level, fx)
		end,
	})
	-- Parts that stream in later take the current level at once (scoped to this model only).
	record.Added = target.DescendantAdded:Connect(function(object)
		local level = record.Handle.Level
		if level and level > 0 and object:IsA("BasePart") then
			object.LocalTransparencyModifier = shown(object, level) and 0 or 1
		end
	end)
	tagged[target] = record
end

local function detachTagged(target: Instance)
	local record = tagged[target]
	if record then
		tagged[target] = nil
		record.Handle:Destroy()
		record.Added:Disconnect()
	end
end

local tagStarted = false
-- Starts the tag path (StarterPlayerScripts.PerfQuality calls it once on the client).
function Lod.StartTags()
	if tagStarted then
		return
	end
	tagStarted = true
	CollectionService:GetInstanceAddedSignal(Lod.Tag):Connect(attachTagged)
	CollectionService:GetInstanceRemovedSignal(Lod.Tag):Connect(detachTagged)
	for _, target in ipairs(CollectionService:GetTagged(Lod.Tag)) do
		attachTagged(target)
	end
end

return Lod
