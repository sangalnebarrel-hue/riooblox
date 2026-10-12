-- Kit.Tabs, Kit.SearchBox, Kit.Chips, Kit.SortSelect.
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Motion = require(script.Parent.Motion)
local Maid = require(script.Parent.Maid)
local Lang = require(script.Parent.Lang)
local Overlay = require(script.Parent.Overlay)

local Controls = {}

local function place(object: any, p: any)
	if p.Size then
		object.Size = p.Size
	end
	if p.Position then
		object.Position = p.Position
	end
	if p.AnchorPoint then
		object.AnchorPoint = p.AnchorPoint
	end
	if p.LayoutOrder then
		object.LayoutOrder = p.LayoutOrder
	end
end

------------------------------------------------------------------------------------------------
-- Tabs: a row of pill tabs (scrolls sideways on phones). Tabs = {{Id, Text, Badge?}}.
------------------------------------------------------------------------------------------------
local Tabs = {}
Tabs.__index = Tabs
Controls.Tabs = Tabs

function Tabs.new(parent: Instance?, props: any): any
	local self: any = setmetatable({}, Tabs)
	self.Maid = Maid.new()
	self.Props = props
	self.Accent = props.Accent or Theme.Accent
	self.Buttons = {}
	self.Z = props.ZIndex or 1
	local strip = Base.Strip(parent, props.Name or "KitTabs", 8)
	strip.ZIndex = self.Z
	strip.Size = UDim2.new(1, 0, 0, 44)
	place(strip, props)
	self.Instance = strip
	self.Maid:Give(strip)
	self:SetTabs(props.Tabs or {}, props.Selected)
	return self
end

function Tabs.SetTabs(self: any, tabs: { any }, selected: string?)
	for _, entry in pairs(self.Buttons) do
		entry.Button:Destroy()
	end
	self.Buttons = {}
	self.Order = {}
	for i, tab in ipairs(tabs) do
		local button, caption, face = Base.PillButton(self.Instance, {
			Name = "Tab_" .. tostring(tab.Id),
			Text = tab.Text,
			TextSize = self.Props.TextSize or 17,
			MinWidth = 84,
			LayoutOrder = i,
			ZIndex = self.Z + 1,
			NoTranslate = tab.NoTranslate,
		})
		button.Size = UDim2.new(0, 0, 1, -4)
		local badge = Base.Text(button, {
			Name = "Badge",
			Text = tab.Badge and tostring(tab.Badge) or "",
			TextSize = 12,
			Font = "numeric",
			AlignX = "Center",
			Color = Theme.White,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 12, 0, 4),
			Size = UDim2.fromOffset(22, 18),
			ZIndex = self.Z + 3,
			NoTranslate = true,
		})
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Theme.Danger
		badge.Visible = tab.Badge ~= nil and tostring(tab.Badge) ~= ""
		Base.Corner(badge, "pill")
		Base.Press(button, nil, self.Maid)
		self.Maid:Give(button.Activated:Connect(function()
			self:Select(tab.Id)
		end))
		self.Buttons[tab.Id] = { Button = button, Caption = caption, Badge = badge, Face = face }
		table.insert(self.Order, tab.Id)
	end
	self.Selected = selected or self.Selected or (tabs[1] and tabs[1].Id)
	if self.Selected and not self.Buttons[self.Selected] then
		self.Selected = tabs[1] and tabs[1].Id
	end
	self:_paint(true)
end

function Tabs._paint(self: any, instant: boolean?)
	for id, entry in pairs(self.Buttons) do
		local on = id == self.Selected
		local goal = { BackgroundColor3 = on and self.Accent or Theme.White }
		if instant then
			entry.Face.BackgroundColor3 = goal.BackgroundColor3
		else
			Motion.Tween(entry.Face, Theme.Motion.Fast, goal)
		end
		entry.Caption.TextColor3 = on and Theme.OnColor(self.Accent) or Theme.InkMuted
		entry.Caption.TextStrokeTransparency = (on and Theme.OnColor(self.Accent) == Theme.White) and 0.3 or 1
		local stroke = entry.Face:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Transparency = on and 0 or 0.55
		end
	end
end

-- Selects a tab; silent=true skips OnChange.
function Tabs.Select(self: any, id: string, silent: boolean?)
	if not self.Buttons[id] then
		return
	end
	local changed = self.Selected ~= id
	self.Selected = id
	self:_paint(false)
	Base.Reveal(self.Instance, self.Buttons[id].Button)
	if changed and not silent and self.Props.OnChange then
		task.spawn(self.Props.OnChange, id)
	end
end

function Tabs.SetBadge(self: any, id: string, text: any)
	local entry = self.Buttons[id]
	if not entry then
		return
	end
	local value = text ~= nil and tostring(text) or ""
	entry.Badge.Text = value
	entry.Badge.Visible = value ~= "" and value ~= "0"
end

function Tabs.SetAccent(self: any, color: Color3)
	self.Accent = color
	self:_paint(true)
end

function Tabs.Destroy(self: any)
	self.Maid:Clean()
end

------------------------------------------------------------------------------------------------
-- SearchBox: a text box with a clear button; OnChange is debounced while typing and immediate
-- on Enter / focus lost.
------------------------------------------------------------------------------------------------
local SearchBox = {}
SearchBox.__index = SearchBox
Controls.SearchBox = SearchBox

function SearchBox.new(parent: Instance?, props: any): any
	local self: any = setmetatable({}, SearchBox)
	self.Maid = Maid.new()
	self.Props = props
	self.Debounce = props.Debounce or 0.25
	self.Last = props.Text or ""
	local z = props.ZIndex or 1
	local root = Base.New("Frame", {
		Name = props.Name or "KitSearch",
		BackgroundColor3 = Theme.Field,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 42),
		ZIndex = z,
	})
	place(root, props)
	self.Instance = root
	self.Maid:Give(root)
	Base.Corner(root, Theme.Radius.Field)
	local stroke = Base.Stroke(root, Theme.Colors.edge, 2, 0.5)
	-- Magnifier glyph drawn with frames (no font dependency).
	local glass = Base.New("Frame", {
		Name = "Glass",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, -1),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = z + 1,
	}, root)
	Base.Corner(glass, "pill")
	Base.Stroke(glass, Theme.InkMuted, 2.5)
	local handle = Base.New("Frame", {
		Name = "Handle",
		BackgroundColor3 = Theme.InkMuted,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 13),
		Size = UDim2.fromOffset(8, 3),
		Rotation = 45,
		ZIndex = z + 1,
	}, glass)
	Base.Corner(handle, 2)
	local box = Base.New("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Text = props.Text or "",
		PlaceholderText = props.Placeholder or Lang.Word("SEARCH"),
		PlaceholderColor3 = Theme.InkMuted,
		TextColor3 = Theme.Ink,
		FontFace = Theme.Font,
		TextSize = props.TextSize or 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -76, 1, 0),
		ZIndex = z + 1,
	}, root)
	self.Box = box
	local clear = Base.Text(root, {
		Name = "Clear",
		Class = "TextButton",
		Text = "×",
		TextSize = 24,
		AlignX = "Center",
		Color = Theme.InkMuted,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = z + 2,
		NoTranslate = true,
	})
	clear.Visible = box.Text ~= ""
	self.Clear = clear
	local token = 0
	local function emit()
		token += 1
		if box.Text == self.Last then
			return
		end
		self.Last = box.Text
		if self.Props.OnChange then
			task.spawn(self.Props.OnChange, box.Text)
		end
	end
	self.Emit = emit
	self.Maid:Give(box:GetPropertyChangedSignal("Text"):Connect(function()
		clear.Visible = box.Text ~= ""
		if self.Silent then
			return
		end
		token += 1
		local mine = token
		task.delay(self.Debounce, function()
			if mine == token then
				emit()
			end
		end)
	end))
	self.Maid:Give(box.FocusLost:Connect(function()
		emit()
	end))
	self.Maid:Give(box.Focused:Connect(function()
		stroke.Transparency = 0
		stroke.Color = Theme.Accent
	end))
	self.Maid:Give(box.FocusLost:Connect(function()
		stroke.Transparency = 0.5
		stroke.Color = Theme.Colors.edge
	end))
	self.Maid:Give(clear.Activated:Connect(function()
		box.Text = ""
		emit()
	end))
	if parent then
		root.Parent = parent
	end
	return self
end

function SearchBox.GetText(self: any): string
	return self.Box.Text
end

-- Sets the text; silent=true does not call OnChange.
function SearchBox.SetText(self: any, text: string, silent: boolean?)
	self.Silent = silent == true
	self.Box.Text = text
	self.Silent = false
	if silent then
		self.Last = text
	else
		self.Emit()
	end
end

function SearchBox.Focus(self: any)
	self.Box:CaptureFocus()
end

function SearchBox.Destroy(self: any)
	self.Maid:Clean()
end

------------------------------------------------------------------------------------------------
-- Chips: filter pills. Single select (Selected = id or nil) or Multi (Selected = {id = true}).
------------------------------------------------------------------------------------------------
local Chips = {}
Chips.__index = Chips
Controls.Chips = Chips

function Chips.new(parent: Instance?, props: any): any
	local self: any = setmetatable({}, Chips)
	self.Maid = Maid.new()
	self.Props = props
	self.Multi = props.Multi == true
	self.AllowNone = props.AllowNone ~= false
	self.Z = props.ZIndex or 1
	local strip = Base.Strip(parent, props.Name or "KitChips", 6)
	strip.ZIndex = self.Z
	strip.Size = UDim2.new(1, 0, 0, 36)
	place(strip, props)
	self.Instance = strip
	self.Maid:Give(strip)
	if self.Multi then
		local set = {}
		for _, id in ipairs(props.Selected or {}) do
			set[id] = true
		end
		self.Set = set
	else
		self.Value = props.Selected
	end
	self:SetOptions(props.Options or {})
	return self
end

function Chips.SetOptions(self: any, options: { any })
	for _, entry in pairs(self.Entries or {}) do
		entry.Button:Destroy()
	end
	self.Entries = {}
	self.Options = options
	for i, option in ipairs(options) do
		local button, caption, face = Base.PillButton(self.Instance, {
			Name = "Chip_" .. tostring(option.Id),
			Text = option.Text,
			TextSize = self.Props.TextSize or 15,
			MinWidth = 48,
			LayoutOrder = i,
			ZIndex = self.Z + 1,
			NoTranslate = option.NoTranslate,
		})
		button.Size = UDim2.new(0, 0, 1, -4)
		local dot = Base.New("Frame", {
			Name = "Dot",
			BackgroundColor3 = option.Color or Theme.Accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -8, 0.5, 0),
			Size = UDim2.fromOffset(8, 8),
			Visible = option.Color ~= nil,
			ZIndex = self.Z + 2,
		}, button)
		Base.Corner(dot, "pill")
		Base.Press(button, nil, self.Maid)
		self.Maid:Give(button.Activated:Connect(function()
			self:Toggle(option.Id)
		end))
		self.Entries[option.Id] = { Button = button, Caption = caption, Option = option, Face = face }
	end
	self:_paint(true)
end

function Chips.IsOn(self: any, id: any): boolean
	if self.Multi then
		return self.Set[id] == true
	end
	return self.Value == id
end

function Chips._paint(self: any, instant: boolean?)
	for id, entry in pairs(self.Entries) do
		local on = self:IsOn(id)
		local color = entry.Option.Color or Theme.Accent
		local goal = { BackgroundColor3 = on and color or Theme.White }
		if instant then
			entry.Face.BackgroundColor3 = goal.BackgroundColor3
		else
			Motion.Tween(entry.Face, Theme.Motion.Fast, goal)
		end
		entry.Caption.TextColor3 = on and Theme.OnColor(color) or Theme.Ink
		local stroke = entry.Face:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Transparency = on and 0 or 0.55
		end
		local dot = entry.Button:FindFirstChild("Dot")
		if dot then
			dot.BackgroundColor3 = on and Theme.White or color
		end
	end
end

function Chips.Toggle(self: any, id: any)
	if self.Multi then
		self.Set[id] = not self.Set[id] or nil
	elseif self.Value == id then
		if not self.AllowNone then
			return
		end
		self.Value = nil
	else
		self.Value = id
	end
	self:_paint(false)
	if self.Props.OnChange then
		task.spawn(self.Props.OnChange, self:GetSelected())
	end
end

-- Single: id or nil. Multi: array of ids (in option order).
function Chips.GetSelected(self: any): any
	if not self.Multi then
		return self.Value
	end
	local list = {}
	for _, option in ipairs(self.Options) do
		if self.Set[option.Id] then
			table.insert(list, option.Id)
		end
	end
	return list
end

function Chips.SetSelected(self: any, selected: any, silent: boolean?)
	if self.Multi then
		self.Set = {}
		for _, id in ipairs(selected or {}) do
			self.Set[id] = true
		end
	else
		self.Value = selected
	end
	self:_paint(false)
	if not silent and self.Props.OnChange then
		task.spawn(self.Props.OnChange, self:GetSelected())
	end
end

function Chips.Destroy(self: any)
	self.Maid:Clean()
end

------------------------------------------------------------------------------------------------
-- SortSelect: "SORT · <option>" opens a dropdown; the arrow button flips the direction.
------------------------------------------------------------------------------------------------
local SortSelect = {}
SortSelect.__index = SortSelect
Controls.SortSelect = SortSelect

function SortSelect.new(parent: Instance?, props: any): any
	local self: any = setmetatable({}, SortSelect)
	self.Maid = Maid.new()
	self.Props = props
	self.Options = props.Options or {}
	self.Value = props.Selected or (self.Options[1] and self.Options[1].Id)
	self.Descending = props.Descending ~= false
	local z = props.ZIndex or 1
	self.Z = z
	local root = Base.New("Frame", {
		Name = props.Name or "KitSort",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(220, 42),
		ZIndex = z,
	})
	place(root, props)
	self.Instance = root
	self.Maid:Give(root)

	local main = Base.New("TextButton", {
		Name = "Open",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -48, 1, 0),
		ZIndex = z + 1,
	}, root)
	local mainFace = Base.Face(main, Theme.White, Theme.Radius.Field, z + 1)
	Base.Stroke(mainFace, Theme.Colors.edge, 2, 0.45)
	Base.Press(main, nil, self.Maid, 1.02)
	Base.Text(main, {
		Name = "Caption",
		Text = Lang.Word("SORT"),
		TextSize = 11,
		Color = Theme.InkMuted,
		Position = UDim2.fromOffset(12, 3),
		Size = UDim2.new(1, -36, 0, 13),
		ZIndex = z + 2,
	})
	self.ValueLabel = Base.Text(main, {
		Name = "Value",
		TextSize = 16,
		Scaled = true,
		MinTextSize = 10,
		Position = UDim2.fromOffset(12, 15),
		Size = UDim2.new(1, -36, 1, -18),
		ZIndex = z + 2,
	})
	Base.Text(main, {
		Name = "Chevron",
		Text = "▾",
		TextSize = 18,
		AlignX = "Center",
		Color = Theme.InkMuted,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = z + 2,
		NoTranslate = true,
	})
	local direction = Base.New("TextButton", {
		Name = "Direction",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 42, 1, 0),
		ZIndex = z + 1,
	}, root)
	local directionFace = Base.Face(direction, Theme.White, Theme.Radius.Field, z + 1)
	Base.Stroke(directionFace, Theme.Colors.edge, 2, 0.45)
	self.DirectionLabel = Base.Text(direction, {
		Name = "Arrow",
		TextSize = 20,
		AlignX = "Center",
		ZIndex = z + 2,
		NoTranslate = true,
	})
	Base.Press(direction, nil, self.Maid)
	self.DirectionButton = direction
	self.Maid:Give(main.Activated:Connect(function()
		self:Open()
	end))
	self.Maid:Give(direction.Activated:Connect(function()
		self.Descending = not self.Descending
		self:_paint()
		self:_emit()
	end))
	self:_paint()
	if parent then
		root.Parent = parent
	end
	return self
end

function SortSelect._text(self: any, id: any): string
	for _, option in ipairs(self.Options) do
		if option.Id == id then
			return option.Text
		end
	end
	return tostring(id or "")
end

function SortSelect._paint(self: any)
	self.ValueLabel.Text = self:_text(self.Value)
	self.DirectionLabel.Text = self.Descending and "↓" or "↑"
end

function SortSelect._emit(self: any)
	if self.Props.OnChange then
		task.spawn(self.Props.OnChange, self.Value, self.Descending)
	end
end

function SortSelect.Open(self: any)
	if self.Popup then
		return
	end
	local rowH = 40
	local count = #self.Options
	local w = math.max(200, self.Instance.AbsoluteSize.X)
	local h = math.min(count * rowH + 8, 320)
	local entry: any
	local function close()
		if entry then
			Overlay.Remove(entry)
			entry = nil
		end
		if self.Popup then
			self.Popup:Destroy()
			self.Catcher:Destroy()
			self.Popup = nil
		end
	end
	local panel, catcher = Overlay.Popup(self.Instance, w, h, close)
	self.Popup, self.Catcher = panel, catcher
	entry = Overlay.Push({ Dismiss = close, Kind = "popup" })
	local list = Base.New("ScrollingFrame", {
		Name = "Options",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		CanvasSize = UDim2.fromOffset(0, count * rowH),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Accent,
		ZIndex = panel.ZIndex + 1,
	}, panel)
	for i, option in ipairs(self.Options) do
		local on = option.Id == self.Value
		local row = Base.Text(list, {
			Name = "Option_" .. tostring(option.Id),
			Class = "TextButton",
			Text = option.Text,
			TextSize = 16,
			Color = on and Theme.Accent or Theme.Ink,
			Position = UDim2.fromOffset(0, (i - 1) * rowH),
			Size = UDim2.new(1, 0, 0, rowH - 2),
			ZIndex = panel.ZIndex + 2,
			NoTranslate = option.NoTranslate,
		})
		Base.Padding(row, 12, 0, 12, 0)
		if on then
			local mark = Base.New("Frame", {
				Name = "Current",
				BackgroundColor3 = Theme.Field,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(-12, 0),
				Size = UDim2.new(1, 24, 1, 0),
				ZIndex = panel.ZIndex + 1,
			}, row)
			Base.Corner(mark, Theme.Radius.Small)
		end
		row.Activated:Connect(function()
			close()
			if self.Value == option.Id then
				self.Descending = not self.Descending
			else
				self.Value = option.Id
				if option.Descending ~= nil then
					self.Descending = option.Descending
				end
			end
			self:_paint()
			self:_emit()
		end)
	end
	panel.Size = UDim2.fromOffset(w, 0)
	Motion.Tween(panel, Theme.Motion.Fast, { Size = UDim2.fromOffset(w, h) })
	self.ClosePopup = close
end

function SortSelect.Set(self: any, id: any, descending: boolean?, silent: boolean?)
	self.Value = id
	if descending ~= nil then
		self.Descending = descending
	end
	self:_paint()
	if not silent then
		self:_emit()
	end
end

function SortSelect.SetOptions(self: any, options: { any })
	self.Options = options
	self:_paint()
end

function SortSelect.Destroy(self: any)
	if self.ClosePopup then
		self.ClosePopup()
	end
	self.Maid:Clean()
end

return Controls
