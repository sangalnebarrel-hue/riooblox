-- Kit.VirtualGrid / Kit.VirtualList: a scrolling grid that only creates and binds the cells in
-- view (plus one row of overscan), recycles them while scrolling and keys them by item id, so a
-- refresh keeps the scroll position and reuses the cell (and its 3D preview) of the same item.
-- Works the same for 10 or 10,000 items: instance count depends on the viewport, not the data.
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Layout = require(script.Parent.Layout)
local Motion = require(script.Parent.Motion)
local Maid = require(script.Parent.Maid)
local Display = require(script.Parent.Display)

local VirtualGrid = {}
VirtualGrid.__index = VirtualGrid

export type Props = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	-- Minimum cell width and the row height, or a function (viewWidth, viewHeight) -> Vector2
	-- (return a wide, short size to switch to list rows on small screens).
	CellSize: any?,
	Columns: number?, -- fixed column count (overrides CellSize.X)
	MaxColumns: number?,
	Gap: number?, -- 10
	Padding: number?, -- 10
	Overscan: number?, -- rows bound above and below the viewport (1)
	Create: ((frame: Frame, grid: any) -> any)?, -- builds a pooled cell inside frame
	Bind: ((cell: any, item: any, index: number) -> ())?, -- fills a cell with an item
	Unbind: ((cell: any, item: any) -> ())?, -- the cell left the viewport
	Layout: ((cell: any, width: number, height: number) -> ())?, -- the cell size changed
	Destroy: ((cell: any) -> ())?, -- the pool dropped the cell
	Key: ((item: any, index: number) -> any)?, -- default item.Id / Uid / DogUid / ItemUid / Key
	Empty: any?, -- Kit.EmptyState props shown when there are no items
	ScrollBarColor: Color3?,
}

local function defaultKey(item: any, index: number): any
	if type(item) == "table" then
		return item.Id or item.Uid or item.DogUid or item.ItemUid or item.Key or index
	end
	return item
end

-- Product of the UIScale factors on `object` and its ancestors (AbsoluteSize includes them; the
-- grid lays out in unscaled pixels so an open/press animation never changes the column count).
local function scaleOf(object: Instance): number
	local factor = 1
	local node: Instance? = object
	while node and not node:IsA("LayerCollector") do
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("UIScale") then
				factor *= child.Scale
			end
		end
		node = node.Parent
	end
	return factor > 0.01 and factor or 1
end

function VirtualGrid.new(parent: Instance?, props: Props): any
	local p: any = props or {}
	local self: any = setmetatable({}, VirtualGrid)
	self.Props = p
	self.Maid = Maid.new()
	self.Gap = p.Gap or 10
	self.Pad = p.Padding or 10
	self.Overscan = p.Overscan or 1
	self.KeyOf = p.Key or defaultKey
	self.Items = {}
	self.Keys = {}
	self.KeyIndex = {}
	self.Active = {} -- index -> record
	self.Free = {} -- released records (kept for reuse)
	self.Records = {} -- every live record
	self.Created = 0
	self.Binds = 0
	self.First, self.Last = 1, 0
	self.Cols, self.CellW, self.CellH = 1, 0, 0
	self.CanvasH = 0
	local z = p.ZIndex or 1
	self.Z = z

	local root = Base.New("Frame", {
		Name = p.Name or "KitGrid",
		BackgroundTransparency = 1,
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		ZIndex = z,
	})
	self.Instance = root
	self.Maid:Give(root)
	local scroll = Base.New("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = p.ScrollBarColor or Theme.Accent,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Selectable = false,
		ZIndex = z,
	}, root)
	self.Scroll = scroll
	if p.Empty then
		local empty = table.clone(p.Empty)
		empty.ZIndex = empty.ZIndex or z + 1
		self.Empty = Display.EmptyState(root, empty)
		self.Empty:SetVisible(false)
		self.Maid:Give(self.Empty)
	end
	self.Maid:Give(scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_update(false)
	end))
	self.Maid:Give(scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_update(true)
	end))
	if parent then
		root.Parent = parent
	end
	return self
end

function VirtualGrid._canvas(self: any)
	self.CanvasH = Layout.CanvasHeight(#self.Items, self.Cols, self.CellH, self.Gap, self.Pad)
	self.Scroll.CanvasSize = UDim2.fromOffset(0, self.CanvasH)
end

function VirtualGrid._place(self: any, record: any, index: number)
	local x, y = Layout.CellPosition(index, self.Cols, self.CellW, self.CellH, self.Gap, self.Pad)
	record.Frame.Position = UDim2.fromOffset(x, y)
end

function VirtualGrid._create(self: any): any
	local p = self.Props
	local frame = Base.New("Frame", {
		Name = "Cell",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(self.CellW, self.CellH),
		ZIndex = self.Z + 1,
	}, self.Scroll)
	local cell = frame
	if p.Create then
		cell = p.Create(frame, self)
	end
	local record = { Frame = frame, Cell = cell }
	if p.Layout then
		p.Layout(cell, self.CellW, self.CellH)
	end
	table.insert(self.Records, record)
	self.Created += 1
	return record
end

function VirtualGrid._acquire(self: any, key: any): any
	local free = self.Free
	-- A released cell that last showed this item still has its preview: reuse it first.
	for i = #free, 1, -1 do
		if free[i].Key == key then
			return table.remove(free, i)
		end
	end
	return table.remove(free) or self:_create()
end

function VirtualGrid._release(self: any, record: any)
	record.Frame.Visible = false
	local p = self.Props
	if p.Unbind then
		local ok, err = pcall(p.Unbind, record.Cell, record.Item)
		if not ok then
			warn("Kit.VirtualGrid Unbind: " .. tostring(err))
		end
	end
	record.Item = nil
	record.Index = nil
	table.insert(self.Free, record)
end

function VirtualGrid._bind(self: any, record: any, index: number)
	record.Index = index
	record.Key = self.Keys[index]
	record.Item = self.Items[index]
	self:_place(record, index)
	record.Frame.Visible = true
	self.Binds += 1
	local p = self.Props
	if p.Bind then
		local ok, err = pcall(p.Bind, record.Cell, record.Item, index)
		if not ok then
			warn("Kit.VirtualGrid Bind: " .. tostring(err))
		end
	end
end

-- Keeps the pool at what the viewport can need; extra released cells are destroyed.
function VirtualGrid._trim(self: any)
	local limit = Layout.MaxCells(self.ViewH or 0, self.Cols, self.CellH, self.Gap, self.Overscan) + self.Cols
	local p = self.Props
	while #self.Records > limit and #self.Free > 0 do
		local record = table.remove(self.Free, 1)
		local index = table.find(self.Records, record)
		if index then
			table.remove(self.Records, index)
		end
		if p.Destroy then
			pcall(p.Destroy, record.Cell)
		end
		record.Frame:Destroy()
	end
end

function VirtualGrid._update(self: any, relayout: boolean)
	if self.Destroyed then
		return
	end
	local scroll = self.Scroll
	if relayout or not self.ViewW then
		local factor = scaleOf(scroll)
		local abs = scroll.AbsoluteSize
		local viewW = math.floor(abs.X / factor + 0.5) - scroll.ScrollBarThickness
		local viewH = math.floor(abs.Y / factor + 0.5)
		if viewW <= 1 or viewH <= 1 then
			return
		end
		self.ViewW, self.ViewH = viewW, viewH
		local p = self.Props
		local spec = p.CellSize
		local size: Vector2 = if type(spec) == "function" then spec(viewW, viewH) else (spec or Vector2.new(160, 200))
		local cols, cellW
		if p.Columns then
			cols = math.max(1, p.Columns)
			cellW = math.max(1, math.floor((viewW - self.Pad * 2 - self.Gap * (cols - 1)) / cols))
		else
			cols, cellW = Layout.Columns(viewW, size.X, self.Gap, self.Pad, p.MaxColumns)
		end
		local cellH = math.max(1, math.floor(size.Y))
		if cols ~= self.Cols or cellW ~= self.CellW or cellH ~= self.CellH then
			self.Cols, self.CellW, self.CellH = cols, cellW, cellH
			for _, record in ipairs(self.Records) do
				record.Frame.Size = UDim2.fromOffset(cellW, cellH)
				if p.Layout then
					p.Layout(record.Cell, cellW, cellH)
				end
			end
			for index, record in pairs(self.Active) do
				self:_place(record, index)
			end
			self.First, self.Last = 1, 0
		end
		self:_canvas()
	end
	local y = Layout.ClampScroll(scroll.CanvasPosition.Y, self.CanvasH, self.ViewH)
	local first, last = Layout.VisibleRange(y, self.ViewH, #self.Items, self.Cols, self.CellH, self.Gap, self.Pad, self.Overscan)
	if first == self.First and last == self.Last and not self.Dirty then
		return
	end
	self.First, self.Last = first, last
	for index, record in pairs(self.Active) do
		if index < first or index > last then
			self.Active[index] = nil
			self:_release(record)
		end
	end
	local dirty = self.Dirty
	self.Dirty = false
	for index = first, last do
		local record = self.Active[index]
		if not record then
			record = self:_acquire(self.Keys[index])
			self.Active[index] = record
			self:_bind(record, index)
		elseif dirty then
			self:_bind(record, index)
		end
	end
	self:_trim()
end

-- Replaces the data. Cells are matched by key: an item that stays visible keeps its cell (and
-- preview); the scroll offset is kept (clamped).
-- opts.ResetScroll: back to the top (a new filter). opts.Anchor: keep the first visible item at
-- the same place even if items were inserted above it (live refresh).
function VirtualGrid.SetItems(self: any, items: { any }, opts: any?)
	local o: any = opts or {}
	local scroll = self.Scroll
	local anchorKey, anchorOffset
	if o.Anchor and self.Last >= self.First and self.ViewH then
		local y = scroll.CanvasPosition.Y
		for index = self.First, self.Last do
			local _, top = Layout.CellPosition(index, self.Cols, self.CellW, self.CellH, self.Gap, self.Pad)
			if top + self.CellH > y then
				anchorKey, anchorOffset = self.Keys[index], top - y
				break
			end
		end
	end
	local keys, where = table.create(#items), {}
	for i, item in ipairs(items) do
		local key = self.KeyOf(item, i)
		if key == nil or where[key] then
			key = "#dup" .. i
		end
		keys[i] = key
		where[key] = i
	end
	local remapped = {}
	for _, record in pairs(self.Active) do
		local index = where[record.Key]
		if index and not remapped[index] then
			remapped[index] = record
		else
			self:_release(record)
		end
	end
	self.Items, self.Keys, self.KeyIndex = items, keys, where
	self.Active = remapped
	for index, record in pairs(remapped) do
		self:_place(record, index)
	end
	if self.ViewW then
		self:_canvas()
		local target = scroll.CanvasPosition.Y
		if o.ResetScroll then
			target = 0
		elseif anchorKey ~= nil and where[anchorKey] then
			local _, top = Layout.CellPosition(where[anchorKey], self.Cols, self.CellW, self.CellH, self.Gap, self.Pad)
			target = top - anchorOffset
		end
		target = Layout.ClampScroll(target, self.CanvasH, self.ViewH)
		if target ~= scroll.CanvasPosition.Y then
			scroll.CanvasPosition = Vector2.new(0, target)
		end
	elseif o.ResetScroll then
		scroll.CanvasPosition = Vector2.zero
	end
	if self.Empty then
		self.Empty:SetVisible(#items == 0)
	end
	self.Dirty = true
	self:_update(false)
end

function VirtualGrid.GetItems(self: any): { any }
	return self.Items
end

-- Rebinds the visible cells (data inside the items changed).
function VirtualGrid.Refresh(self: any)
	self.Dirty = true
	self:_update(false)
end

-- Rebinds the cell of one item if it is visible.
function VirtualGrid.RefreshKey(self: any, key: any)
	local index = self.KeyIndex[key]
	local record = index and self.Active[index]
	if record then
		record.Item = self.Items[index]
		self:_bind(record, index)
	end
end

-- Recomputes columns and sizes (call after changing the container size by code).
function VirtualGrid.Relayout(self: any)
	self:_update(true)
end

function VirtualGrid.ScrollToIndex(self: any, index: number, animate: boolean?)
	if not self.ViewH or index < 1 or index > #self.Items then
		return
	end
	local y = Layout.ScrollToReveal(index, self.Scroll.CanvasPosition.Y, self.ViewH, self.Cols, self.CellH, self.Gap, self.Pad)
	y = Layout.ClampScroll(y, self.CanvasH, self.ViewH)
	if animate then
		Motion.Tween(self.Scroll, Theme.Motion.Slide, { CanvasPosition = Vector2.new(0, y) })
	else
		self.Scroll.CanvasPosition = Vector2.new(0, y)
	end
end

function VirtualGrid.ScrollToKey(self: any, key: any, animate: boolean?)
	local index = self.KeyIndex[key]
	if index then
		self:ScrollToIndex(index, animate)
	end
end

-- Calls fn(cell, item, index) for every bound cell.
function VirtualGrid.ForEachVisible(self: any, fn: (any, any, number) -> ())
	for index, record in pairs(self.Active) do
		fn(record.Cell, record.Item, index)
	end
end

-- Counters for tests and debugging.
function VirtualGrid.GetStats(self: any): any
	local active = 0
	for _ in pairs(self.Active) do
		active += 1
	end
	return {
		Count = #self.Items,
		Active = active,
		Records = #self.Records,
		Free = #self.Free,
		Created = self.Created,
		Binds = self.Binds,
		Columns = self.Cols,
		CellWidth = self.CellW,
		CellHeight = self.CellH,
		First = self.First,
		Last = self.Last,
		ViewWidth = self.ViewW,
		ViewHeight = self.ViewH,
		CanvasHeight = self.CanvasH,
	}
end

function VirtualGrid.Destroy(self: any)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	local p = self.Props
	if p.Destroy then
		for _, record in ipairs(self.Records) do
			pcall(p.Destroy, record.Cell)
		end
	end
	self.Records, self.Free, self.Active = {}, {}, {}
	self.Maid:Clean()
end

-- A one-column list: props.RowHeight (default 64) instead of CellSize.
local function list(parent: Instance?, props: any): any
	local p = table.clone(props or {})
	local rowHeight = p.RowHeight or 64
	p.Columns = 1
	p.CellSize = Vector2.new(1, rowHeight)
	p.Gap = p.Gap or 6
	return VirtualGrid.new(parent, p)
end

return {
	Grid = VirtualGrid,
	List = list,
}
