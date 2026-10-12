-- Shared 3D preview cache for cards.
--  * A Slot is a holder frame inside a card; slot:Show(spec) puts the preview of spec in it.
--  * Showing the key a slot already shows does nothing (no re-clone on rebind).
--  * A preview leaving a slot goes to an off-screen shelf (hidden, not rendered) and is reused
--    by the next slot that shows the same key; the shelf keeps at most Preview.MaxFree.
--  * New previews are built from a queue, at most Preview.PerFrame per frame, only while the
--    queue has work (no idle per-frame loop).
-- Kinds: "Dog" {DogId, Variant, Silhouette} via Modules.PreviewRenderer (MenuModels),
-- "Item" {ItemId, Mutation, Silhouette} via DogEconomy.DiscoveryVisuals, "Image" {Image}.
-- Preview.Register(kind, builder, keyer) adds kinds (accessories, decor...).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Overlay = require(script.Parent.Overlay)

local Preview = {}
Preview.PerFrame = 2
Preview.MaxFree = 48
Preview.BuildSize = 128 -- square render size; previews are framed for a square holder

local builders: { [string]: (spec: any, parent: Instance) -> any } = {}
local keyers: { [string]: (spec: any) -> string } = {}
local free: { [string]: { any } } = {}
local freeOrder: { any } = {} -- {Key, Content}, oldest first
local queue: { any } = {}
local stats = { Built = 0, Reused = 0, Failed = 0, Evicted = 0, Live = 0 }
local shelf: any = nil
local pump: RBXScriptConnection? = nil

local function getShelf(): any
	if shelf and shelf.Parent then
		return shelf
	end
	shelf = Base.New("Frame", {
		Name = "KitPreviewShelf",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Preview.BuildSize, Preview.BuildSize),
		Visible = false,
	}, Overlay.Top())
	return shelf
end

keyers.Dog = function(spec)
	return tostring(spec.DogId) .. "|" .. tostring(spec.Variant or "Normal") .. "|" .. (spec.Silhouette and "S" or "")
end
keyers.Item = function(spec)
	return tostring(spec.ItemId) .. "|" .. string.upper(tostring(spec.Mutation or "NORMAL")) .. "|" .. (spec.Silhouette and "S" or "")
end
keyers.Image = function(spec)
	return tostring(spec.Image)
end

local renderer: any = nil
builders.Dog = function(spec, parent)
	if renderer == nil then
		local kit: any = script.Parent
		local module = kit.Parent and kit.Parent:FindFirstChild("PreviewRenderer")
		renderer = module and require(module) or false
	end
	if not renderer then
		return nil
	end
	local size = Preview.BuildSize
	return renderer.Dog(parent, { DogId = spec.DogId, Variant = spec.Variant }, 0, 0, size, size, spec.Silhouette == true)
end

builders.Item = function(spec, parent)
	local economy = ReplicatedStorage:FindFirstChild("DogEconomy")
	local module = economy and economy:FindFirstChild("DiscoveryVisuals")
	if not module then
		return nil
	end
	local visuals: any = require(module :: any)
	local size = Preview.BuildSize
	local view = visuals.Preview(parent, { ItemId = spec.ItemId, Mutation = spec.Mutation }, 0, 0, size, size)
	view.BackgroundTransparency = 1
	if spec.Silhouette then
		view.ImageColor3 = Color3.new(0, 0, 0)
	end
	return view
end

builders.Image = function(spec, parent)
	return Base.New("ImageLabel", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Image = Base.IconImage(spec.Image) or "",
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = spec.Silhouette and Color3.new(0, 0, 0) or Theme.White,
	}, parent)
end

-- Adds a preview kind. builder(spec, parent) returns a GuiObject parented to `parent`;
-- keyer(spec) returns the cache key (previews with the same key must look the same).
function Preview.Register(kind: string, builder: (spec: any, parent: Instance) -> any, keyer: ((spec: any) -> string)?)
	builders[kind] = builder
	if keyer then
		keyers[kind] = keyer
	end
end

function Preview.Key(spec: any): string?
	if type(spec) ~= "table" then
		return nil
	end
	local kind = spec.Kind or "Dog"
	local keyer = keyers[kind]
	if keyer then
		return kind .. "|" .. keyer(spec)
	end
	return kind .. "|" .. tostring(spec.Key or spec.Id)
end

local function takeFree(key: string): any
	local list = free[key]
	if not list or #list == 0 then
		return nil
	end
	local content = table.remove(list)
	if #list == 0 then
		free[key] = nil
	end
	for i, entry in ipairs(freeOrder) do
		if entry.Content == content then
			table.remove(freeOrder, i)
			break
		end
	end
	return content
end

local function putFree(key: string, content: any)
	if not content or not content.Parent then
		stats.Live -= 1
		return
	end
	content.Parent = getShelf()
	local list = free[key]
	if not list then
		list = {}
		free[key] = list
	end
	table.insert(list, content)
	table.insert(freeOrder, { Key = key, Content = content })
	while #freeOrder > Preview.MaxFree do
		local oldest = table.remove(freeOrder, 1)
		local bucket = free[oldest.Key]
		if bucket then
			local index = table.find(bucket, oldest.Content)
			if index then
				table.remove(bucket, index)
			end
			if #bucket == 0 then
				free[oldest.Key] = nil
			end
		end
		oldest.Content:Destroy()
		stats.Evicted += 1
		stats.Live -= 1
	end
end

local function placeholder(parent: Instance): any
	local label = Base.Text(nil, {
		Name = "Preview",
		Text = "?",
		TextSize = 40,
		Scaled = true,
		AlignX = "Center",
		Color = Theme.InkMuted,
		NoTranslate = true,
	})
	label.Parent = parent
	return label
end

local function build(spec: any): any
	local builder = builders[spec.Kind or "Dog"]
	local content
	if builder then
		local ok, result = pcall(builder, spec, getShelf())
		if ok and result then
			content = result
			stats.Built += 1
		else
			if not ok then
				warn("Kit.Preview: " .. tostring(result))
			end
			stats.Failed += 1
		end
	end
	if not content then
		content = placeholder(getShelf())
	end
	stats.Live += 1
	return content
end

local function attach(slot: any, content: any)
	slot.Content = content
	content.AnchorPoint = Vector2.zero
	content.Position = UDim2.new()
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = slot.Holder.ZIndex + 1
	content.Visible = true
	-- PreviewRenderer places its "Loading…" / "?" label in pixels of the build size.
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Position = UDim2.new()
			child.Size = UDim2.fromScale(1, 1)
			child.TextScaled = true
		end
	end
	content.Parent = slot.Holder
end

local function process()
	local built = 0
	while built < Preview.PerFrame and #queue > 0 do
		local job = table.remove(queue, 1)
		local slot = job.Slot
		if not slot.Dead and slot.Key == job.Key and not slot.Content then
			local content = takeFree(job.Key)
			if content then
				stats.Reused += 1
			else
				content = build(slot.Spec)
				built += 1
			end
			attach(slot, content)
		end
	end
	if #queue == 0 and pump then
		pump:Disconnect()
		pump = nil
	end
end

local function enqueue(slot: any)
	table.insert(queue, { Slot = slot, Key = slot.Key })
	if not pump then
		pump = RunService.Heartbeat:Connect(process)
	end
end

local Slot = {}
Slot.__index = Slot

-- A preview slot over `holder` (a transparent frame of the card).
function Preview.Slot(holder: GuiObject): any
	local self: any = setmetatable({}, Slot)
	self.Holder = holder
	return self
end

-- Shows spec (nil clears). The same key as now is a no-op.
function Slot.Show(self: any, spec: any)
	local key = Preview.Key(spec)
	if key == self.Key then
		return
	end
	self:Clear()
	if not key then
		return
	end
	self.Key, self.Spec = key, spec
	local content = takeFree(key)
	if content then
		stats.Reused += 1
		attach(self, content)
	else
		enqueue(self)
	end
end

function Slot.Clear(self: any)
	if self.Content then
		putFree(self.Key, self.Content)
		self.Content = nil
	end
	self.Key, self.Spec = nil, nil
end

function Slot.Destroy(self: any)
	self:Clear()
	self.Dead = true
end

-- Builds everything queued now (tests, or before a screenshot).
function Preview.Flush()
	while #queue > 0 do
		local before = Preview.PerFrame
		Preview.PerFrame = math.huge
		process()
		Preview.PerFrame = before
	end
end

-- Drops every off-screen preview (low memory, or after closing a big screen).
function Preview.Purge()
	for _, entry in ipairs(freeOrder) do
		entry.Content:Destroy()
		stats.Evicted += 1
		stats.Live -= 1
	end
	table.clear(freeOrder)
	table.clear(free)
end

function Preview.Stats(): any
	return {
		Built = stats.Built,
		Reused = stats.Reused,
		Failed = stats.Failed,
		Evicted = stats.Evicted,
		Live = stats.Live,
		Free = #freeOrder,
		Queue = #queue,
	}
end

return Preview
