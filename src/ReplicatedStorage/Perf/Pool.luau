-- Object pool for repeated client objects (path arrows, title boards, sparkles, floating text):
-- objects are created once, then reused instead of Instance.new / Destroy on every use.
--
--   local arrows = Pool.new({
--       Create = function() return makeArrow() end,     -- required; returns an Instance or a table
--       Reset = function(arrow) arrow.Color = WHITE end, -- optional, runs on Release
--       Max = 32,          -- live objects at most (active + free), default 64
--       Prewarm = 8,       -- created up front
--       Parent = folder,   -- Instances are parented here once and stay there
--       Hide = "Modifier", -- how a free object is hidden (see below)
--       Steal = false,     -- at Max: true recycles the oldest active object, false returns nil
--   })
--   local arrow = arrows:Acquire(); ...; arrows:Release(arrow)
--   arrows:Stats() -> {Active, Free, Created, Reused, Dropped, Peak, Max}; arrows:Destroy()
--
-- Hide modes (free objects stay where they are, no reparent churn):
--   "Modifier"     BaseParts get LocalTransparencyModifier = 1 (client only), GUI objects
--                  Visible = false, lights / emitters / beams / trails / GUIs Enabled = false.
--                  Showing restores exactly what hiding changed. Default for Instances with a Parent.
--   "Transparency" the same, but writes BasePart.Transparency (server-side pools).
--   "Folder"       free objects move to a hidden folder (parented to nil) and back to Parent.
--   "None"         nothing: Reset / the caller hides the object. Default for tables.
--   function(object, hidden) custom.
local Pool = {}
Pool.__index = Pool

export type Options = {
	Create: () -> any,
	Reset: ((any) -> ())?,
	Max: number?,
	Prewarm: number?,
	Parent: Instance?,
	Hide: any?, -- "Modifier" | "Transparency" | "Folder" | "None" | (object, hidden) -> ()
	Steal: boolean?,
}

local FX_CLASSES = { "Light", "ParticleEmitter", "Beam", "Trail", "LayerCollector", "Highlight" }

local function isFx(object: Instance): boolean
	for _, class in ipairs(FX_CLASSES) do
		if object:IsA(class) then
			return true
		end
	end
	return false
end

-- Hides an Instance tree and returns what must be restored when it is shown again.
local function hideTree(root: Instance, useTransparency: boolean): { any }
	local saved = {}
	local function visit(object: Instance)
		if object:IsA("BasePart") then
			if useTransparency then
				table.insert(saved, { object, "Transparency", object.Transparency })
				object.Transparency = 1
			else
				table.insert(saved, { object, "LocalTransparencyModifier", object.LocalTransparencyModifier })
				object.LocalTransparencyModifier = 1
			end
		elseif object:IsA("GuiObject") then
			table.insert(saved, { object, "Visible", object.Visible })
			object.Visible = false
		elseif isFx(object) then
			local fx: any = object
			table.insert(saved, { object, "Enabled", fx.Enabled })
			fx.Enabled = false
		end
	end
	visit(root)
	for _, object in ipairs(root:GetDescendants()) do
		visit(object)
	end
	return saved
end

local function showTree(saved: { any })
	for _, row in ipairs(saved) do
		local object: any = row[1]
		object[row[2]] = row[3]
	end
end

function Pool.new(options: Options): any
	assert(type(options) == "table" and type(options.Create) == "function", "Pool.new: Create is required")
	local self: any = setmetatable({}, Pool)
	self.Options = options
	self.Max = math.max(1, math.floor(options.Max or 64))
	self.Free = {} -- stack of free objects
	self.Active = {} -- [object] = acquire serial
	self.Hidden = {} -- [object] = saved state of a hidden Instance
	self.Owned = {} -- [object] = true for every object this pool created
	self.Serial = 0
	self.Counts = { Created = 0, Reused = 0, Dropped = 0, Peak = 0 }
	self.ActiveCount = 0
	self.Total = 0
	local hide = options.Hide
	if hide == nil then
		hide = options.Parent and "Modifier" or "None"
	end
	self.HideMode = hide
	if hide == "Folder" then
		self.Holder = Instance.new("Folder")
		self.Holder.Name = "PerfPoolHidden"
	end
	for _ = 1, math.min(self.Max, math.floor(options.Prewarm or 0)) do
		local object = self:_create()
		self:_hide(object)
		table.insert(self.Free, object)
	end
	return self
end

function Pool._create(self: any): any
	local object = self.Options.Create()
	assert(object ~= nil, "Pool: Create returned nil")
	self.Owned[object] = true
	self.Total += 1
	self.Counts.Created += 1
	if typeof(object) == "Instance" and self.Options.Parent then
		object.Parent = self.Options.Parent
	end
	return object
end

function Pool._hide(self: any, object: any)
	local mode = self.HideMode
	if type(mode) == "function" then
		mode(object, true)
	elseif typeof(object) ~= "Instance" or mode == "None" then
		return
	elseif mode == "Folder" then
		object.Parent = self.Holder
	else
		self.Hidden[object] = hideTree(object, mode == "Transparency")
	end
end

function Pool._show(self: any, object: any)
	local mode = self.HideMode
	if type(mode) == "function" then
		mode(object, false)
	elseif typeof(object) ~= "Instance" or mode == "None" then
		return
	elseif mode == "Folder" then
		object.Parent = self.Options.Parent
	else
		local saved = self.Hidden[object]
		self.Hidden[object] = nil
		if saved then
			showTree(saved)
		end
	end
end

local function track(self: any, object: any): any
	self.Serial += 1
	self.Active[object] = self.Serial
	self.ActiveCount += 1
	if self.ActiveCount > self.Counts.Peak then
		self.Counts.Peak = self.ActiveCount
	end
	return object
end

-- A ready object, or nil when the pool is at Max (unless Steal is on).
function Pool.Acquire(self: any): any
	if self.Destroyed then
		return nil
	end
	local object = table.remove(self.Free)
	if object ~= nil then
		self.Counts.Reused += 1
		self:_show(object)
		return track(self, object)
	end
	if self.Total < self.Max then
		return track(self, self:_create())
	end
	if self.Options.Steal then
		local oldest, serial = nil, math.huge
		for candidate, s in pairs(self.Active) do
			if s < serial then
				oldest, serial = candidate, s
			end
		end
		if oldest ~= nil then
			self.Active[oldest] = nil
			self.ActiveCount -= 1
			if self.Options.Reset then
				self.Options.Reset(oldest)
			end
			self.Counts.Reused += 1
			return track(self, oldest)
		end
	end
	self.Counts.Dropped += 1
	return nil
end

-- Returns an object to the pool. Unknown or already free objects are ignored (returns false).
function Pool.Release(self: any, object: any): boolean
	if object == nil or self.Active[object] == nil then
		return false
	end
	self.Active[object] = nil
	self.ActiveCount -= 1
	if self.Destroyed then
		return false
	end
	if self.Options.Reset then
		self.Options.Reset(object)
	end
	self:_hide(object)
	table.insert(self.Free, object)
	return true
end

function Pool.IsActive(self: any, object: any): boolean
	return self.Active[object] ~= nil
end

function Pool.ForEachActive(self: any, fn: (any) -> ())
	for object in pairs(self.Active) do
		fn(object)
	end
end

function Pool.Stats(self: any): any
	return {
		Active = self.ActiveCount,
		Free = #self.Free,
		Created = self.Counts.Created,
		Reused = self.Counts.Reused,
		Dropped = self.Counts.Dropped,
		Peak = self.Counts.Peak,
		Max = self.Max,
	}
end

-- Destroys every object the pool created (active ones too) and the hidden folder.
function Pool.Destroy(self: any)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for object in pairs(self.Owned) do
		if typeof(object) == "Instance" then
			object:Destroy()
		elseif type(object) == "table" and type(object.Destroy) == "function" then
			object:Destroy()
		end
	end
	table.clear(self.Owned)
	table.clear(self.Active)
	table.clear(self.Free)
	table.clear(self.Hidden)
	self.ActiveCount = 0
	self.Total = 0
	if self.Holder then
		self.Holder:Destroy()
	end
end

return Pool
