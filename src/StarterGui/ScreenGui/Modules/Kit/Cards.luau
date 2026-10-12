-- Kit.DogCard / Kit.ItemCard cells and Kit.CardGrid.
-- A card shows a lazy 3D preview (Kit.Preview: only cards in view own one, cached by key), the
-- name, a rarity tag, a variant (dog) or mutation (item) tag, up to 3 stat chips and the
-- selected / disabled / locked / owned-count overlays. Wide cells (width >= 1.8 x height) use
-- the compact list-row layout for phones.
--
-- Card data (what Map(item) returns, or the item itself):
--   Id, Name, Rarity, Preview = {Kind="Dog", DogId, Variant, Silhouette} | {Kind="Item", ItemId,
--   Mutation, Silhouette} | {Kind="Image", Image}, Tag / TagColor (override the variant /
--   mutation tag), Variant / Mutation, Stats = {{Text, Color?}, ...} (max 3), Subtitle,
--   Count (owned copies), Badge ("NEW"), Selected, Disabled, DisabledReason, Locked.
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Motion = require(script.Parent.Motion)
local Maid = require(script.Parent.Maid)
local Display = require(script.Parent.Display)
local Feedback = require(script.Parent.Feedback)
local Preview = require(script.Parent.Preview)
local Virtual = require(script.Parent.Virtual)

local Cards = {}
local Card = {}
Card.__index = Card
Cards.Card = Card

local MAX_STATS = 3

-- Builds a card inside `frame` (a VirtualGrid cell or any frame). kind: "Dog" | "Item".
function Cards.new(frame: GuiObject, kind: string?, opts: any?): any
	local o: any = opts or {}
	local self: any = setmetatable({}, Card)
	self.Kind = kind or "Dog"
	self.Maid = Maid.new()
	local z = (frame.ZIndex or 1) + 1
	self.Z = z
	local root = Base.New("TextButton", {
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, frame)
	self.Instance = root
	self.Maid:Give(root)
	self.Face = Base.Face(root, Theme.White, Theme.Radius.Card, z)
	self.StrokeObject = Base.Stroke(self.Face, Theme.Colors.edge, 2)
	self.Press = Base.Press(root, nil, self.Maid, 1.02)

	self.Glow = Base.New("Frame", {
		Name = "Glow",
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = z + 1,
	}, root)
	Base.Corner(self.Glow, Theme.Radius.Card - 4)
	self.GlowGradient = Base.New("UIGradient", { Rotation = 90 }, self.Glow)

	self.Holder = Base.New("Frame", {
		Name = "PreviewHolder",
		BackgroundTransparency = 1,
		ZIndex = z + 2,
	}, root)
	self.Slot = Preview.Slot(self.Holder)

	self.Name = Base.Text(root, {
		Name = "DisplayName",
		TextSize = 16,
		Scaled = true,
		MinTextSize = 10,
		ZIndex = z + 3,
	})
	self.Subtitle = Base.Text(root, {
		Name = "Subtitle",
		TextSize = 13,
		Color = Theme.InkMuted,
		ZIndex = z + 3,
	})

	-- Tag row: rarity + variant / mutation.
	self.TagRow = Base.New("Frame", { Name = "Tags", BackgroundTransparency = 1, ZIndex = z + 3 }, root)
	Base.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
	}, self.TagRow)
	self.RarityTag = Display.RarityTag(self.TagRow, "Common", { Height = 18, TextSize = 11, LayoutOrder = 1, ZIndex = z + 4 })
	self.Tag = Display.Pill(self.TagRow, { Height = 18, TextSize = 11, LayoutOrder = 2, ZIndex = z + 4 })

	-- Stat chips.
	self.StatRow = Base.New("Frame", { Name = "Stats", BackgroundTransparency = 1, ZIndex = z + 3 }, root)
	Base.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
	}, self.StatRow)
	self.Chips = {}
	for i = 1, MAX_STATS do
		local chip = Display.Pill(self.StatRow, {
			Name = "Stat" .. i,
			Height = 18,
			TextSize = 12,
			Font = "numeric",
			PadX = 6,
			Color = Theme.Colors.secondary,
			TextColor = Theme.Ink,
			LayoutOrder = i,
			ZIndex = z + 4,
			NoTranslate = true,
		})
		chip:SetVisible(false)
		table.insert(self.Chips, chip)
	end

	self.Count = Display.Badge(root, { Name = "Count", Color = Theme.Colors.edge, ZIndex = z + 5 })
	self.Count:SetVisible(false)
	self.Badge = Display.Pill(root, { Name = "Badge", Height = 18, TextSize = 11, Color = Theme.Danger, ZIndex = z + 5 })
	self.Badge:SetVisible(false)

	self.Veil = Base.New("Frame", {
		Name = "Veil",
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z + 6,
	}, root)
	Base.Corner(self.Veil, Theme.Radius.Card)
	self.Lock = Base.Text(self.Veil, {
		Name = "Lock",
		Text = "🔒",
		TextSize = 26,
		AlignX = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = z + 7,
		NoTranslate = true,
	})

	self.Check = Base.New("Frame", {
		Name = "Check",
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(26, 26),
		Visible = false,
		ZIndex = z + 8,
	}, root)
	Base.Corner(self.Check, "pill")
	Base.Stroke(self.Check, Theme.White, 2)
	Base.Text(self.Check, {
		Name = "Mark",
		Text = "✓",
		TextSize = 17,
		AlignX = "Center",
		Color = Theme.White,
		ZIndex = z + 9,
		NoTranslate = true,
	})

	-- Clicks: OnClick(card); long press / right click: OnLongPress(card).
	self.LongPress = Feedback.LongPress(root, function()
		if self.OnLongPress then
			self.OnLongPress(self)
		end
	end)
	self.Maid:Give(self.LongPress)
	self.Maid:Give(root.Activated:Connect(function()
		if self.LongPress.Consumed() then
			return
		end
		local data = self.Data
		if data and data.Disabled then
			if data.DisabledReason then
				Feedback.Toast(data.DisabledReason, { Kind = "warn" })
			end
			return
		end
		if self.OnClick then
			self.OnClick(self)
		end
	end))
	self.Mode = nil
	self:Layout(o.Width or 156, o.Height or 206)
	return self
end

-- Positions the parts for a w x h cell: "card" (grid) or "row" (list on phones).
function Card.Layout(self: any, w: number, h: number)
	local mode = w >= h * 1.8 and "row" or "card"
	self.Mode = mode
	local pad = 8
	if mode == "card" then
		local previewH = math.max(40, math.floor(h * 0.5))
		self.Glow.Position = UDim2.fromOffset(4, 4)
		self.Glow.Size = UDim2.fromOffset(w - 8, previewH + pad - 2)
		self.Holder.Position = UDim2.fromOffset(pad + 6, pad)
		self.Holder.Size = UDim2.fromOffset(w - pad * 2 - 12, previewH)
		local y = pad + previewH + 4
		self.Name.Position = UDim2.fromOffset(pad + 2, y)
		self.Name.Size = UDim2.fromOffset(w - pad * 2 - 4, 22)
		self.Name.TextXAlignment = Enum.TextXAlignment.Center
		self.TagRow.Position = UDim2.fromOffset(pad, y + 24)
		self.TagRow.Size = UDim2.fromOffset(w - pad * 2, 20)
		self.TagRow:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
		self.StatRow.Position = UDim2.fromOffset(pad, h - pad - 20)
		self.StatRow.Size = UDim2.fromOffset(w - pad * 2, 20)
		self.StatRow:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
		self.Count.Instance.AnchorPoint = Vector2.new(0, 0)
		self.Count.Instance.Position = UDim2.fromOffset(pad, pad)
		self.Badge.Instance.AnchorPoint = Vector2.new(0, 1)
		self.Badge.Instance.Position = UDim2.fromOffset(pad, pad + previewH)
		self.Check.Position = UDim2.new(1, -6, 0, 6)
		self.Lock.Position = UDim2.new(0.5, 0, 0, pad + previewH / 2)
	else
		local size = h - pad * 2
		self.Glow.Position = UDim2.fromOffset(4, 4)
		self.Glow.Size = UDim2.fromOffset(size + pad - 4, h - 8)
		self.Holder.Position = UDim2.fromOffset(pad, pad)
		self.Holder.Size = UDim2.fromOffset(size, size)
		local x = size + pad * 2
		local right = 40
		local textW = math.max(20, w - x - right)
		self.Name.Position = UDim2.fromOffset(x, pad - 2)
		self.Name.Size = UDim2.fromOffset(textW, 22)
		self.Name.TextXAlignment = Enum.TextXAlignment.Left
		self.TagRow.Position = UDim2.fromOffset(x, pad + 21)
		self.TagRow.Size = UDim2.fromOffset(textW, 20)
		self.TagRow:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Left
		-- Third line: stat chips, or the subtitle when there are no stats.
		self.Subtitle.Position = UDim2.fromOffset(x, h - pad - 18)
		self.Subtitle.Size = UDim2.fromOffset(textW, 18)
		self.StatRow.Position = UDim2.fromOffset(x, h - pad - 20)
		self.StatRow.Size = UDim2.fromOffset(textW, 20)
		self.StatRow:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Left
		self.Count.Instance.AnchorPoint = Vector2.new(1, 1)
		self.Count.Instance.Position = UDim2.new(1, -8, 1, -8)
		self.Badge.Instance.AnchorPoint = Vector2.new(0, 1)
		self.Badge.Instance.Position = UDim2.fromOffset(pad, h - pad)
		self.Check.Position = UDim2.new(1, -8, 0, 6)
		self.Lock.Position = UDim2.new(0, pad + size / 2, 0.5, 0)
	end
	self.W, self.H = w, h
	if self.Data then
		self:_paintStats()
	end
end

function Card._paintStats(self: any)
	local data = self.Data
	local stats = data and data.Stats or {}
	-- Rows show the subtitle on the third line only when there are no stats; cards never do.
	self.Subtitle.Visible = self.Mode == "row" and #stats == 0 and (data and data.Subtitle or "") ~= "" and (self.H or 0) >= 64
	for i, chip in ipairs(self.Chips) do
		local stat = stats[i]
		if stat then
			local text = type(stat) == "table" and stat.Text or tostring(stat)
			local color = type(stat) == "table" and stat.Color or nil
			chip:Set(text, color or Theme.Colors.secondary, color and Theme.OnColor(color) or Theme.Ink)
			chip:SetVisible(true)
		else
			chip:SetVisible(false)
		end
	end
end

-- Fills the card. Cheap to call again with the same data (the preview is kept by key).
function Card.Bind(self: any, data: any)
	self.Data = data
	local rarityColor = Theme.RarityColor(data.Rarity)
	self.Name.Text = data.Name or ""
	self.Name.TextColor3 = data.Disabled and Theme.InkMuted or Theme.Ink
	self.Subtitle.Text = data.Subtitle or ""

	self.RarityTag:SetVisible(data.Rarity ~= nil)
	if data.Rarity then
		self.RarityTag:SetRarity(data.Rarity)
	end
	local gradient = data.Rarity and Theme.RarityGradient[data.Rarity]
	local top = gradient and gradient[1] or rarityColor
	self.GlowGradient.Color = ColorSequence.new(top:Lerp(Theme.White, 0.55), Theme.White)

	-- Variant (dogs) / mutation (items) tag, unless the caller supplies one.
	local preview = data.Preview
	local tagText, tagColor = data.Tag, data.TagColor
	if not tagText then
		if self.Kind == "Item" then
			local mutation = string.upper(tostring(data.Mutation or (preview and preview.Mutation) or "NORMAL"))
			if mutation ~= "NORMAL" then
				tagText, tagColor = mutation, Theme.MutationColor(mutation)
			end
		else
			local variant = data.Variant or (preview and preview.Variant)
			if variant and variant ~= "Normal" then
				tagText, tagColor = string.upper(variant), Theme.VariantColor(variant)
			end
		end
	end
	self.Tag:SetVisible(tagText ~= nil)
	if tagText then
		self.Tag:Set(tagText, tagColor or Theme.Accent)
	end

	self:_paintStats()

	local count = tonumber(data.Count)
	self.Count:SetVisible(count ~= nil and count > 1)
	if count and count > 1 then
		self.Count:Set("×" .. math.floor(count))
	end
	self.Badge:SetVisible(data.Badge ~= nil)
	if data.Badge then
		self.Badge:Set(data.Badge, data.BadgeColor or Theme.Danger)
	end

	local selected = data.Selected == true
	self.Check.Visible = selected
	self.StrokeObject.Color = selected and Theme.Accent or rarityColor:Lerp(Theme.Colors.edge, 0.45)
	self.StrokeObject.Thickness = selected and 4 or 2
	self.Veil.Visible = data.Disabled == true or data.Locked == true
	self.Veil.BackgroundColor3 = data.Locked and Theme.Colors.edge or Theme.White
	self.Veil.BackgroundTransparency = data.Locked and 0.55 or 0.4
	self.Lock.Visible = data.Locked == true

	if preview then
		local spec = preview
		if spec.Kind == nil then
			spec = table.clone(preview)
			spec.Kind = self.Kind
		end
		self.Slot:Show(spec)
	elseif data.Image then
		self.Slot:Show({ Kind = "Image", Image = data.Image })
	else
		self.Slot:Show(nil)
	end
end

-- Small "selected" pop used by screens after toggling selection in place.
function Card.Pulse(self: any)
	self.Press.Scale = 1.06
	Motion.Tween(self.Press, Theme.Motion.Fast, { Scale = 1 })
end

function Card.Destroy(self: any)
	self.Slot:Destroy()
	self.Maid:Clean()
end

-- Kind-bound constructors: Kit.DogCard.new(frame), Kit.ItemCard.new(frame).
Cards.DogCard = {
	new = function(frame: GuiObject, opts: any?): any
		return Cards.new(frame, "Dog", opts)
	end,
}
Cards.ItemCard = {
	new = function(frame: GuiObject, opts: any?): any
		return Cards.new(frame, "Item", opts)
	end,
}

-- A virtual grid of cards. It switches to list rows (one column, or several on wide screens)
-- when the view is narrower than ListBelow or too short for a card and a half (landscape phones).
-- props: Kind ("Dog" | "Item"), Map(item, index) -> card data (default: the item), OnClick(item,
-- index, card), OnLongPress(item, index, card), CardSize (Vector2 156x206), RowHeight (76),
-- RowMinWidth (300), ListBelow (500; 0 = width never forces rows), plus any VirtualGrid props
-- (Gap, Padding, MaxColumns, Key, Empty...).
function Cards.Grid(parent: Instance?, props: any): any
	local p: any = props or {}
	local kind = p.Kind or "Dog"
	local cardSize: Vector2 = p.CardSize or Vector2.new(156, 206)
	local rowHeight = p.RowHeight or 76
	local rowMinWidth = p.RowMinWidth or 300
	local listBelow = p.ListBelow or 500
	local map = p.Map
	local gridProps = table.clone(p)
	gridProps.CellSize = function(width: number, height: number): Vector2
		if width < listBelow or height < cardSize.Y * 1.5 then
			return Vector2.new(math.min(rowMinWidth, width), rowHeight)
		end
		return cardSize
	end
	gridProps.Create = function(frame: Frame)
		local card = Cards.new(frame, kind)
		card.OnClick = function(c)
			if p.OnClick and c.Item ~= nil then
				p.OnClick(c.Item, c.Index, c)
			end
		end
		card.OnLongPress = function(c)
			if p.OnLongPress and c.Item ~= nil then
				p.OnLongPress(c.Item, c.Index, c)
			end
		end
		return card
	end
	gridProps.Bind = function(card: any, item: any, index: number)
		card.Item, card.Index = item, index
		card:Bind(map and map(item, index) or item)
	end
	gridProps.Unbind = function(card: any)
		card.Item, card.Index = nil, nil
	end
	gridProps.Layout = function(card: any, w: number, h: number)
		card:Layout(w, h)
	end
	gridProps.Destroy = function(card: any)
		card:Destroy()
	end
	return Virtual.Grid.new(parent, gridProps)
end

return Cards
