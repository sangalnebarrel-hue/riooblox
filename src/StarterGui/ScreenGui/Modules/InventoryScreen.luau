-- MY BAG (UI kit window, docs/UI.md). Replaces the static InventoryPage on every device (its
-- controller keeps running for the HUD counter, the Lucky pad prompts and notifications).
--   FINDS         one toolbar: search, sort, FILTERS (depth, mutation, favourites) and rarity chips;
--                 the capacity bar ("23 / 50", GO SELL when full); cards coloured by rarity
--                 (mutation tag, weight, value, ★ favourite, 🏆 showcase). Desktop: a detail panel on
--                 the right; phones: list rows and the detail as a stacked window. Detail: big 3D
--                 preview, rarity / mutation, weight / value / depth chips, MORE for the rest;
--                 ★ (favourite), SELL (at your collector, always confirmed, hold for Epic+ and
--                 favourites; elsewhere GO SELL shows the way) and ••• (LIST ON MARKET, SHOW IN DEX).
--   LUCKY BLOCKS  one card per tier: how many you have, what is on your pads; OPEN AT MY PAD
--                 (shows the way) and CHANCES.
-- Entry: GUIIntegration.kitScreens (N.OpenPage('Inventory' | 'LuckyBlocks' | 'OwnedBlocks'), the BAG
-- tile, B). Requests (Modules.Net): ItemFavorite, BulkSell, List. Logic: Modules.InventoryLogic.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Logic = require(script.Parent.InventoryLogic)
local Dict = require(RS:WaitForChild("Localization"):WaitForChild("UI"))
local Economy = RS:WaitForChild("DogEconomy")
local Config = require(Economy:WaitForChild("Config"))
local Definitions = require(Economy:WaitForChild("ItemDefinitions"))
local Depths = require(Economy:WaitForChild("DepthDefinitions"))
local ValueConfig = require(RS:WaitForChild("ItemValueConfig"))
local Valuation = require(RS:WaitForChild("ItemValuation"))
local BlockConfig = require(RS:WaitForChild("LuckyBlockConfig"))
local Lifecycle = require(RS:WaitForChild("LuckyLifecycleConfig"))
local Access = require(RS:WaitForChild("PlotInteractionAccess"))
local BlockVisuals = require(RS:WaitForChild("LuckyBlockVisuals"))
local Theme, Format = Kit.Theme, Kit.Format
local P = Theme.Colors
local ACCENT = Color3.fromRGB(26, 192, 239) -- UITheme.WindowSpecs.Inventory
local Z = 3
local player = Players.LocalPlayer

local S = {}

------------------------------------------------------------------------------------------------
-- Text (self-localized labels carry NoTranslate; Localization.UI has the Russian)
------------------------------------------------------------------------------------------------
local function ru(): boolean
	return Kit.Lang() == "ru"
end
local function T(en: string): string
	if ru() then
		return Dict.Exact[en] or Dict.Words[en] or en
	end
	return en
end
local function F(en: string, ...: any): string
	local pattern = en
	if ru() then
		pattern = Dict.Templates[en] or en
	end
	return string.format(pattern, ...)
end
local function short(n: any): string
	return Format.Short(tonumber(n) or 0, 1)
end
local function said(value: any): string
	return type(value) == "table" and tostring(value.Message or "") or tostring(value or "")
end
local function depthName(depth: any): string
	local def = Depths[tostring(depth)]
	local name = def and def.Name or tostring(depth)
	return T(name)
end
local function blockName(tier: string): string
	return T(string.upper(tier) .. " LUCKY BLOCK")
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local win: any = nil
local ui: any = nil
local detailWin: any = nil
local dw: any = nil
local st: any = {
	Tab = "finds",
	Query = "",
	Sort = "rarest",
	Desc = true,
	Rarities = {},
	Depth = nil,
	Mutations = {},
	Favorites = false,
	Selected = nil,
	SelectedTier = nil,
	Snapshot = nil,
	Rows = {},
	List = {},
	Groups = {},
	Near = false,
	Phone = false,
	Busy = false,
	Token = 0,
}
S.State = st

local function nav(): any
	local ok, N = pcall(require, script.Parent:FindFirstChild("GUIIntegration") :: any)
	return ok and N or nil
end

-- True while the player stands at the collector of their own yard (the server's rule,
-- PlotInteractionAccess; far yards are not streamed in, which also means "not here").
local function nearCollector(): boolean
	local district = workspace:FindFirstChild("DOGROTS_District")
	local yards = district and district:FindFirstChild("04_PlayerYards")
	if not yards then
		return false
	end
	for _, yard in ipairs(yards:GetChildren()) do
		if yard:GetAttribute("OwnerUserId") == player.UserId and yard:GetAttribute("YardId") == player:GetAttribute("YardId") then
			local ok, near = pcall(Access.CanUse, player, yard, yard:FindFirstChild("SellAnchor"))
			return ok and near == true
		end
	end
	return false
end

local function rowsCtx(snapshot: any): any
	local items = snapshot and snapshot.Profile and snapshot.Profile.Items or {}
	return {
		Definitions = Definitions,
		ValueConfig = ValueConfig,
		Price = function(item)
			return (Valuation.Price(item))
		end,
		Showcase = Logic.ShowcaseSet(snapshot, items),
	}
end

------------------------------------------------------------------------------------------------
-- Lucky block previews (Kit.Preview kind "LuckyBlock")
------------------------------------------------------------------------------------------------
Kit.Preview.Register("LuckyBlock", function(spec, parent)
	local view = Instance.new("ViewportFrame")
	view.Name = "LuckyBlockPreview"
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(205, 205, 215)
	view.LightColor = Color3.new(1, 1, 0.95)
	view.LightDirection = Vector3.new(-1, -1.4, -0.6)
	view.Size = UDim2.fromOffset(Kit.Preview.BuildSize, Kit.Preview.BuildSize)
	view.Parent = parent
	local ok, model = pcall(BlockVisuals.Build, spec.Tier)
	if ok and model then
		for _, o in ipairs(model:GetDescendants()) do
			if o:IsA("LuaSourceContainer") or o:IsA("ProximityPrompt") or o:IsA("LayerCollector") or o:IsA("Sound") or o:IsA("ParticleEmitter") or o:IsA("Light") or o:IsA("Beam") or o:IsA("Trail") then
				o:Destroy()
			end
		end
		model.Parent = view
		local cf, size = model:GetBoundingBox()
		local camera = Instance.new("Camera")
		camera.FieldOfView = 34
		camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(1, 0.7, -1.2).Unit * size.Magnitude * 1.55, cf.Position)
		camera.Parent = view
		view.CurrentCamera = camera
	end
	return view
end, function(spec)
	return tostring(spec.Tier)
end)

------------------------------------------------------------------------------------------------
-- Card data
------------------------------------------------------------------------------------------------
local function cardData(row: any, plain: boolean?): any
	local badge = nil
	if row.Favorite then
		badge = "★"
	end
	if row.Showcase then
		badge = (badge and badge .. " " or "") .. "🏆"
	end
	return {
		Id = row.Key,
		Name = row.Name,
		Rarity = row.Rarity,
		Preview = { Kind = "Item", ItemId = row.ItemId, Mutation = row.Mutation },
		Mutation = row.Mutation,
		Stats = {
			{ Text = "⚖ " .. Logic.WeightText(row.Weight, short) },
			{ Text = "💰 " .. short(row.Value), Color = P.gold },
		},
		Badge = badge,
		BadgeColor = P.gold,
		Selected = (not plain) and not st.Phone and row.Key == st.Selected,
	}
end

local function blockStatus(g: any): (string?, Color3?)
	if g.Ready > 0 then
		return "✓ " .. T("READY"), Theme.Success
	elseif g.NextReadyAt then
		return "⏱ " .. Format.Clock(math.max(0, math.ceil(g.NextReadyAt - Kit.Now()))), Theme.Info
	end
	return nil, nil
end

local function blockCard(g: any): any
	local tag, tagColor = blockStatus(g)
	local stats = {}
	if g.Stored > 0 then
		table.insert(stats, { Text = "🎒 " .. g.Stored })
	end
	if g.Placed > 0 then
		table.insert(stats, { Text = "🎲 " .. g.Placed })
	end
	return {
		Id = g.Tier,
		Name = T("LUCKY BLOCK"),
		Rarity = g.Tier,
		Preview = { Kind = "LuckyBlock", Tier = g.Tier },
		Tag = tag,
		TagColor = tagColor,
		Count = g.Count,
		Stats = stats,
		Selected = not st.Phone and g.Tier == st.SelectedTier,
	}
end

------------------------------------------------------------------------------------------------
-- Detail panel (desktop: right of the grid; phones: inside a stacked window)
------------------------------------------------------------------------------------------------
local actions: any = {}

local Detail = {}
Detail.__index = Detail

local function factPill(parent: Instance, order: number): any
	return Kit.Pill(parent, {
		Name = "Fact" .. order,
		Text = "",
		Height = 28,
		TextSize = 15,
		Font = "numeric",
		PadX = 10,
		Color = P.secondary,
		TextColor = Theme.Ink,
		LayoutOrder = order,
		ZIndex = Z + 2,
		NoTranslate = true,
	})
end

local function buildDetail(parent: Instance, compact: boolean): any
	local d: any = setmetatable({ Compact = compact, MoreOpen = false }, Detail)
	local root = Kit.New("Frame", { Name = "Detail", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z }, parent)
	Kit.Corner(root, Theme.Radius.Card)
	Kit.Stroke(root, P.edge, 2, compact and 1 or 0.55)
	if compact then
		root.BackgroundTransparency = 1
	end
	d.Root = root
	local scroll = Kit.New("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = ACCENT,
		ZIndex = Z,
	}, root)
	d.Scroll = scroll
	Kit.New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
	}, scroll)
	Kit.Padding(scroll, 10, 10, 10, 10)
	-- A soft stage in the rarity colour behind the 3D preview.
	d.Stage = Kit.New("Frame", { Name = "Stage", BackgroundColor3 = Theme.White, BorderSizePixel = 0, LayoutOrder = 1, ZIndex = Z + 1 }, scroll)
	Kit.Corner(d.Stage, Theme.Radius.Card)
	d.StageGradient = Kit.New("UIGradient", { Rotation = 90 }, d.Stage)
	d.Holder = Kit.New("Frame", { Name = "PreviewHolder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z + 2 }, d.Stage)
	d.Slot = Kit.Preview.Slot(d.Holder)
	d.Name = Kit.Text(scroll, {
		Name = "ItemName",
		TextSize = Theme.TextSize.Heading,
		Scaled = true,
		MinTextSize = 12,
		AlignX = "Center",
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
		ZIndex = Z + 1,
	})
	d.Name.Visible = not compact
	d.Tags = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 3, ZIndex = Z + 1 }, scroll)
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, d.Tags)
	d.Rarity = Kit.RarityTag(d.Tags, "Common", { Height = 22, TextSize = 13, LayoutOrder = 1, ZIndex = Z + 2 })
	d.Mutation = Kit.MutationTag(d.Tags, "NORMAL", { Height = 22, TextSize = 13, LayoutOrder = 2, ZIndex = Z + 2 })
	d.Star = Kit.Pill(d.Tags, { Text = "★", Color = P.gold, Height = 22, TextSize = 14, LayoutOrder = 3, ZIndex = Z + 2, NoTranslate = true })
	d.Showcase = Kit.Pill(d.Tags, { Text = "🏆", Color = P.purple, Height = 22, TextSize = 13, LayoutOrder = 4, ZIndex = Z + 2, NoTranslate = true })
	d.Facts = Kit.New("Frame", { Name = "Facts", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 4, ZIndex = Z + 1 }, scroll)
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Wraps = true,
	}, d.Facts)
	d.Fact = { factPill(d.Facts, 1), factPill(d.Facts, 2), factPill(d.Facts, 3) }
	d.MoreButton = Kit.Button(scroll, {
		Name = "More",
		Text = T("MORE ▾"),
		Style = "ghost",
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 5,
		ZIndex = Z + 1,
		NoTranslate = true,
		OnClick = function()
			d.MoreOpen = not d.MoreOpen
			d:_more()
		end,
	})
	d.More = Kit.Text(scroll, {
		Name = "MoreText",
		TextSize = 15,
		Color = Theme.InkMuted,
		Wrap = true,
		Rich = true,
		AlignY = "Top",
		Size = UDim2.new(1, -8, 0, 0),
		LayoutOrder = 6,
		ZIndex = Z + 1,
		NoTranslate = true,
	})
	d.More.AutomaticSize = Enum.AutomaticSize.Y
	d.More.Visible = false
	-- Actions (fixed at the bottom).
	d.Actions = Kit.New("Frame", { Name = "Actions", BackgroundTransparency = 1, ZIndex = Z + 1 }, root)
	d.Fav = Kit.Button(d.Actions, {
		Name = "Favourite",
		Text = "☆",
		Style = "secondary",
		TextSize = 24,
		NoTranslate = true,
		ZIndex = Z + 1,
		OnClick = function()
			if d.Row then
				actions.Favourite(d.Row)
			end
		end,
	})
	d.Fav.Instance:SetAttribute("KitSound", "Toggle")
	d.Main = Kit.Button(d.Actions, {
		Name = "Main",
		Text = T("SELL"),
		Style = "success",
		TextSize = 18,
		NoTranslate = true,
		ZIndex = Z + 1,
		OnClick = function()
			if d.Kind == "Item" and d.Row then
				actions.Sell(d.Row, d)
			elseif d.Kind == "Block" and d.Group then
				actions.OpenAtPad(d.Group)
			end
		end,
	})
	d.Second = Kit.Button(d.Actions, {
		Name = "Second",
		Text = T("CHANCES"),
		Style = "secondary",
		TextSize = 16,
		NoTranslate = true,
		ZIndex = Z + 1,
		OnClick = function()
			if d.Group then
				actions.Chances(d.Group)
			end
		end,
	})
	d.Menu = Kit.Button(d.Actions, {
		Name = "Menu",
		Text = "•••",
		Style = "secondary",
		TextSize = 18,
		NoTranslate = true,
		ZIndex = Z + 1,
		OnClick = function()
			if d.Row then
				actions.Menu(d.Menu.Instance, d.Row)
			end
		end,
	})
	pcall(function()
		Kit.Tooltip(d.Fav.Instance, function()
			return T("Favourites are easy to find and ask before they are sold."), T("FAVOURITE")
		end)
		Kit.Tooltip(d.Menu.Instance, function()
			return T("List on the market or find it in your collection."), T("MORE")
		end)
	end)
	d.Empty = Kit.EmptyState(root, {
		Icon = "Inventory",
		Title = T("PICK A FIND"),
		Body = T("Tap a card to see it here."),
		NoTranslate = true,
		ZIndex = Z + 1,
	})
	d.Empty:SetVisible(false)
	d.W, d.H = 300, 400
	return d
end

function Detail._more(self: any)
	self.More.Visible = self.MoreOpen and self.Kind == "Item"
	self.MoreButton:SetText(self.MoreOpen and T("LESS ▴") or T("MORE ▾"))
end

function Detail.Layout(self: any, w: number, h: number)
	self.W, self.H = w, h
	local actionsH = (w < 340) and 46 or 50
	local pad = 10
	self.Scroll.Position = UDim2.new()
	self.Scroll.Size = UDim2.new(1, 0, 1, -(actionsH + pad * 2))
	local side = math.max(80, math.min(w - pad * 2 - 10, math.floor((h - actionsH - pad * 2) * 0.5)))
	self.Stage.Size = UDim2.fromOffset(side, side)
	self.Actions.Position = UDim2.new(0, pad, 1, -(actionsH + pad))
	self.Actions.Size = UDim2.new(1, -pad * 2, 0, actionsH)
	local inner = w - pad * 2
	if self.Kind == "Block" then
		local half = math.floor((inner - 8) * 0.58)
		self.Main.Instance.Position = UDim2.fromOffset(0, 0)
		self.Main.Instance.Size = UDim2.fromOffset(half, actionsH)
		self.Second.Instance.Position = UDim2.fromOffset(half + 8, 0)
		self.Second.Instance.Size = UDim2.fromOffset(inner - half - 8, actionsH)
	else
		self.Fav.Instance.Position = UDim2.fromOffset(0, 0)
		self.Fav.Instance.Size = UDim2.fromOffset(actionsH, actionsH)
		self.Menu.Instance.Position = UDim2.fromOffset(inner - actionsH, 0)
		self.Menu.Instance.Size = UDim2.fromOffset(actionsH, actionsH)
		self.Main.Instance.Position = UDim2.fromOffset(actionsH + 8, 0)
		self.Main.Instance.Size = UDim2.fromOffset(inner - actionsH * 2 - 16, actionsH)
	end
end

local function stage(d: any, rarity: string?)
	local color = Theme.RarityColor(rarity)
	local gradient = rarity and Theme.RarityGradient[rarity]
	local top = gradient and gradient[1] or color
	d.StageGradient.Color = ColorSequence.new(top:Lerp(Theme.White, 0.5), Theme.SurfaceAlt)
end

function Detail.BindItem(self: any, row: any)
	self.Kind, self.Row, self.Group = "Item", row, nil
	local has = row ~= nil
	self.Empty:SetVisible(not has)
	self.Scroll.Visible = has
	self.Actions.Visible = has
	if not row then
		self.Slot:Show(nil)
		return
	end
	self.Slot:Show({ Kind = "Item", ItemId = row.ItemId, Mutation = row.Mutation })
	stage(self, row.Rarity)
	self.Name.Text = row.Name
	self.Rarity:SetVisible(true)
	self.Rarity:SetRarity(row.Rarity)
	self.Mutation:SetMutation(row.Mutation)
	self.Star:SetVisible(row.Favorite)
	self.Showcase:SetVisible(row.Showcase)
	self.Fact[1]:Set("⚖ " .. Logic.WeightText(row.Weight, short))
	self.Fact[2]:Set("💰 " .. short(row.Value))
	self.Fact[3]:Set("⛏ " .. depthName(row.Depth))
	self.Fact[3]:SetVisible(true)
	local item = row.Item or {}
	local lines = {}
	local function add(label: string, value: any)
		if value ~= nil and value ~= "" then
			table.insert(lines, string.format('<font color="%s">%s</font>  %s', Theme.Hex(Theme.InkMuted), T(label), tostring(value)))
		end
	end
	add("Value", Format.Number(row.Value))
	add("Weight", item.WeightTier and T(string.upper(tostring(item.WeightTier))) or nil)
	add("Chance", row.Odds > 0 and Format.Odds(1 / row.Odds) or nil)
	add("Class", item.Class and T(string.upper(tostring(item.Class))) or nil)
	if row.FoundAt > 0 then
		add("Found", os.date("%d.%m.%Y", row.FoundAt))
	end
	local origin = item.Origin == "Roulette" and "DOG-O-MATIC" or item.EventTag or nil
	add("Origin", origin)
	self.More.Text = table.concat(lines, "\n")
	self.MoreButton.Instance.Visible = true
	self:_more()
	self.Fav.Instance.Visible = true
	self.Menu.Instance.Visible = true
	self.Second.Instance.Visible = false
	self.Fav:SetText(row.Favorite and "★" or "☆")
	self.Fav:SetStyle(row.Favorite and "gold" or "secondary")
	if st.Near then
		self.Main:SetText(T("SELL"))
		self.Main:SetStyle("success")
		self.Main:SetPrice(row.Value)
	else
		self.Main:SetText(T("GO SELL"))
		self.Main:SetStyle("gold")
		self.Main:SetPrice(nil)
	end
	self.Main:SetDisabled(false)
	self:Layout(self.W, self.H)
end

function Detail.BindBlock(self: any, g: any)
	self.Kind, self.Row, self.Group = "Block", nil, g
	local has = g ~= nil
	self.Empty:SetVisible(not has)
	self.Scroll.Visible = has
	self.Actions.Visible = has
	if not g then
		self.Slot:Show(nil)
		return
	end
	self.Slot:Show({ Kind = "LuckyBlock", Tier = g.Tier })
	stage(self, g.Tier)
	self.Name.Text = blockName(g.Tier)
	self.Rarity:SetVisible(true)
	self.Rarity:SetRarity(g.Tier)
	self.Mutation:SetMutation("NORMAL")
	self.Star:SetVisible(false)
	self.Showcase:SetVisible(false)
	self.Fact[1]:Set("🎒 " .. g.Stored)
	self.Fact[2]:Set("🎲 " .. g.Placed)
	local status = blockStatus(g)
	self.Fact[3]:Set(status or ("×" .. g.Count))
	self.Fact[3]:SetVisible(true)
	self.MoreOpen = false
	self:_more()
	self.MoreButton.Instance.Visible = false
	self.Fav.Instance.Visible = false
	self.Menu.Instance.Visible = false
	self.Second.Instance.Visible = true
	self.Main:SetText(T("OPEN AT MY PAD"))
	self.Main:SetStyle(g.Ready > 0 and "success" or "primary")
	self.Main:SetPrice(nil)
	self.Main:SetDisabled(false)
	self:Layout(self.W, self.H)
end

------------------------------------------------------------------------------------------------
-- Lists
------------------------------------------------------------------------------------------------
local function rowByKey(key: any): any
	for _, row in ipairs(st.Rows) do
		if row.Key == key then
			return row
		end
	end
	return nil
end
local function groupByTier(tier: any): any
	for _, g in ipairs(st.Groups) do
		if g.Tier == tier then
			return g
		end
	end
	return nil
end
local function inList(key: any): boolean
	for _, row in ipairs(st.List) do
		if row.Key == key then
			return true
		end
	end
	return false
end

local function updateFilterButton()
	if not ui then
		return
	end
	local n = Logic.ExtraFilters(st)
	local label = st.Phone and "☰" or T("FILTERS")
	ui.FilterButton:SetText(n > 0 and (label .. " · " .. n) or label)
	ui.FilterButton:SetStyle(n > 0 and "primary" or "secondary")
end

local function updateCapacity()
	if not ui then
		return
	end
	local count = player:GetAttribute("ItemCount")
	local capacity = player:GetAttribute("ItemCapacity")
	if type(count) ~= "number" then
		count = #st.Rows
	end
	if type(capacity) ~= "number" then
		capacity = st.Snapshot and tonumber(st.Snapshot.ItemCapacity) or 0
	end
	local cap = Logic.Capacity(count, capacity)
	ui.CapBar:SetValue(cap.Fraction)
	ui.CapBar:SetText(string.format("%d / %d", cap.Count, cap.Capacity))
	ui.CapBar:SetColor(cap.Full and Theme.Danger or cap.Warn and P.gold or Theme.Success)
	ui.CapValue:Set("💰 " .. short(Logic.TotalValue(st.Rows)))
	ui.CapFull.Instance.Visible = cap.Full
	ui.CapFull:SetText(st.Near and T("BAG FULL · SELL HERE") or T("BAG FULL · GO SELL"))
	ui.CapValue:SetVisible(not cap.Full or not st.Phone)
	-- LUCKY BLOCKS: count and the ready badge.
	local blocks = Logic.BlockCount(st.Groups)
	ui.BlockCount.Text = string.format("🎲 %d / %d", blocks, Lifecycle.InventoryCapacity or 60)
	local ready = 0
	for _, g in ipairs(st.Groups) do
		ready += g.Ready
	end
	win:SetBadge("blocks", ready > 0 and ready or nil)
end

local function bindDetail()
	if not ui then
		return
	end
	if st.Phone then
		if detailWin and detailWin.IsOpen and dw then
			if dw.Kind == "Block" then
				local g = groupByTier(st.SelectedTier)
				if g then
					dw:BindBlock(g)
				else
					detailWin:Close("gone")
				end
			else
				local row = rowByKey(st.Selected)
				if row then
					dw:BindItem(row)
				else
					detailWin:Close("gone")
				end
			end
		end
		return
	end
	if st.Tab == "blocks" then
		ui.BlockDetail:BindBlock(groupByTier(st.SelectedTier))
	else
		ui.Detail:BindItem(rowByKey(st.Selected))
	end
end

local function refreshFinds(resetScroll: boolean?)
	if not ui then
		return
	end
	st.List = Logic.View(st.Rows, st)
	-- Desktop keeps a find selected so the detail panel is never empty.
	if not st.Phone and (st.Selected == nil or not inList(st.Selected)) then
		st.Selected = st.List[1] and st.List[1].Key or nil
	end
	local filtering = Logic.Filtering(st)
	if filtering then
		ui.Grid.Empty:Set({ Title = T("NO RESULTS"), Body = T("Try another search or filter."), ActionText = T("CLEAR FILTERS") })
	else
		ui.Grid.Empty:Set({ Title = T("NO FINDS YET"), Body = T("Dogs in your kennels dig up finds for you."), ActionText = T("GO TO MY YARD") })
	end
	ui.Grid:SetItems(st.List, { ResetScroll = resetScroll })
	updateFilterButton()
	bindDetail()
end

local function refreshBlocks()
	if not ui then
		return
	end
	if not st.Phone and (st.SelectedTier == nil or not groupByTier(st.SelectedTier)) then
		st.SelectedTier = st.Groups[1] and st.Groups[1].Tier or nil
	end
	ui.BlockGrid:SetItems(st.Groups)
	bindDetail()
end

local function refresh(snapshot: any)
	if snapshot then
		st.Snapshot = snapshot
	end
	local snap = st.Snapshot
	if not snap or type(snap.Profile) ~= "table" then
		return
	end
	st.Rows = Logic.Rows(snap.Profile, rowsCtx(snap))
	st.Groups = Logic.Blocks(snap.Profile, Kit.Now(), BlockConfig)
	if ui then
		refreshFinds(false)
		refreshBlocks()
		updateCapacity()
	end
end

local function clearFilters()
	st.Query, st.Rarities, st.Depth, st.Mutations, st.Favorites = "", {}, nil, {}, false
	if ui then
		ui.Search:SetText("", true)
		ui.Chips:SetSelected({}, true)
	end
	refreshFinds(true)
end

------------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------------
local function goSell()
	local N = nav()
	Kit.Toast(T("Walk to the collector in your yard to sell."), { Kind = "info", NoTranslate = true })
	if N then
		N.Navigate("Your yard")
	end
end

local function select(row: any)
	if not row then
		return
	end
	local previous = st.Selected
	st.Selected = row.Key
	st.Near = nearCollector()
	if st.Phone then
		if not detailWin then
			S._buildDetailWindow()
		end
		detailWin:SetTitle(row.Name)
		dw:BindItem(row)
		if not detailWin.IsOpen then
			detailWin:Open()
		end
		return
	end
	if previous and previous ~= row.Key then
		ui.Grid:RefreshKey(previous)
	end
	ui.Grid:RefreshKey(row.Key)
	ui.Detail:BindItem(row)
end

local function selectBlock(g: any)
	if not g then
		return
	end
	local previous = st.SelectedTier
	st.SelectedTier = g.Tier
	if st.Phone then
		if not detailWin then
			S._buildDetailWindow()
		end
		detailWin:SetTitle(blockName(g.Tier))
		dw:BindBlock(g)
		if not detailWin.IsOpen then
			detailWin:Open()
		end
		return
	end
	if previous and previous ~= g.Tier then
		ui.BlockGrid:RefreshKey(previous)
	end
	ui.BlockGrid:RefreshKey(g.Tier)
	ui.BlockDetail:BindBlock(g)
end

function actions.Favourite(row: any)
	if st.Busy or not row then
		return
	end
	st.Busy = true
	local enabled = not row.Favorite
	-- Optimistic: the star changes at once; a refused request puts it back.
	local function apply(on: boolean)
		row.Favorite = on
		if type(row.Item) == "table" then
			row.Item.Favorite = on
		end
		if ui then
			ui.Grid:RefreshKey(row.Key)
		end
		bindDetail()
	end
	apply(enabled)
	local ok, result = Net.Request("ItemFavorite", { Uid = row.Key, Enabled = enabled })
	st.Busy = false
	if not ok then
		apply(not enabled)
		Kit.Toast(said(result), { Kind = "error" })
	end
end

local function doSell(row: any, d: any)
	st.Busy = true
	d.Main:SetBusy(true)
	local ok, result = Net.Request("BulkSell", { Uids = { row.Key } })
	d.Main:SetBusy(false)
	st.Busy = false
	if not ok then
		Kit.Toast(said(result), { Kind = "error" })
		task.spawn(Net.Snapshot, 0)
		return
	end
	Kit.Toast(said(result) ~= "" and said(result) or T("SOLD!"), { Kind = "success", Sound = "Coin" })
	-- The sale patch (fast path): drop the find from the shared snapshot now, then fetch the exact one.
	local snap = st.Snapshot or Net.Cached()
	if type(snap) == "table" and type(snap.Profile) == "table" and type(snap.Profile.Items) == "table" then
		snap.Profile.Items[row.Key] = nil
		local patch = type(result) == "table" and result.StatePatch or nil
		if type(patch) == "table" and type(patch.Cash) == "number" then
			snap.Profile.Cash = patch.Cash
		end
		Net.Publish(snap)
	end
	if detailWin and detailWin.IsOpen then
		detailWin:Close("sold")
	end
	task.spawn(Net.Snapshot, 0)
end

function actions.Sell(row: any, d: any)
	if st.Busy or not row then
		return
	end
	st.Near = nearCollector()
	if not st.Near then
		goSell()
		return
	end
	Kit.Confirm(T("SELL THIS FIND?"), F("You get %s coins.", Format.Number(row.Value)), {
		NoTranslate = true,
		Cards = { cardData(row, true) },
		CardKind = "Item",
		ConfirmText = F("SELL · %s", short(row.Value)),
		ConfirmStyle = "success",
		Accent = Theme.Success,
		Hold = Logic.SellHold(row.Rarity, row.Favorite),
	}):Then(function(confirmed)
		if confirmed and rowByKey(row.Key) then
			doSell(row, d)
		end
	end)
end

function actions.List(row: any)
	if not row.Tradeable then
		Kit.Toast(T("This find cannot be traded."), { Kind = "warn", NoTranslate = true })
		return
	end
	local hints = Logic.PriceHints(row.Value)
	local input: any = nil
	local summary: any = nil
	local maxPrice = tonumber(Config.MaxCash) or 9e15
	local modal = Kit.Modal({
		Title = T("LIST ON MARKET"),
		Body = T("Buy Now for 7 days. The buyer gets this exact find."),
		NoTranslate = true,
		Cards = { cardData(row, true) },
		CardKind = "Item",
		ContentHeight = 118,
		ConfirmText = T("LIST"),
		ConfirmStyle = "primary",
		Content = function(frame, width)
			local field = Kit.New("Frame", {
				Name = "PriceField",
				BackgroundColor3 = Theme.Field,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(width, 46),
				ZIndex = frame.ZIndex,
			}, frame)
			Kit.Corner(field, Theme.Radius.Field)
			Kit.Stroke(field, P.edge, 2, 0.35)
			Kit.Icon(field, "Coins", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(10, 8), ZIndex = frame.ZIndex + 1, Glyph = "$" })
			input = Kit.New("TextBox", {
				Name = "Price",
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				Text = tostring(hints[3]),
				PlaceholderText = T("Price in coins"),
				PlaceholderColor3 = Theme.InkMuted,
				TextColor3 = Theme.Ink,
				FontFace = Theme.FontNumeric,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(48, 0),
				Size = UDim2.new(1, -58, 1, 0),
				ZIndex = frame.ZIndex + 1,
			}, field)
			input:SetAttribute("KeepFont", true)
			input:SetAttribute("NoTranslate", true)
			local options = {}
			for i, value in ipairs(hints) do
				local mult = ({ "×1", "×1.5", "×2", "×3" })[i]
				table.insert(options, { Id = i, Text = mult .. "  " .. short(value), NoTranslate = true })
			end
			Kit.Chips(frame, {
				Name = "Hints",
				Options = options,
				Selected = 3,
				TextSize = 14,
				Position = UDim2.fromOffset(0, 52),
				Size = UDim2.fromOffset(width, 34),
				ZIndex = frame.ZIndex,
				OnChange = function(id)
					if id and hints[id] and input then
						input.Text = tostring(hints[id])
					end
				end,
			})
			summary = Kit.Text(frame, {
				Name = "Summary",
				TextSize = 14,
				Color = Theme.InkMuted,
				Position = UDim2.fromOffset(2, 92),
				Size = UDim2.fromOffset(width - 4, 24),
				ZIndex = frame.ZIndex,
				NoTranslate = true,
			})
		end,
	})
	local function validate()
		if not (input and summary) then
			return
		end
		local value, why = Logic.ParsePrice(input.Text, 10, maxPrice)
		if modal.ConfirmButton then
			modal.ConfirmButton:SetDisabled(value == nil)
		end
		if value then
			summary.Text = F("Listing fee: %s coins (1%%).", Format.Number(Logic.Fee(value)))
			summary.TextColor3 = Theme.InkMuted
		else
			summary.Text = why == "low" and T("At least 10 coins.") or T("Type a price in coins.")
			summary.TextColor3 = Theme.Danger
		end
	end
	if input then
		modal.Maid:Give(input:GetPropertyChangedSignal("Text"):Connect(validate))
	end
	validate()
	modal:Then(function(confirmed)
		if not confirmed or not input then
			return
		end
		local price = Logic.ParsePrice(input.Text, 10, maxPrice)
		if not price then
			return
		end
		local ok, result = Net.Request("List", { Kind = "Item", Uid = row.Key, Mode = "BuyNow", Price = price })
		Kit.Toast(said(result), { Kind = ok and "success" or "error" })
		if ok then
			if detailWin and detailWin.IsOpen then
				detailWin:Close("listed")
			end
			task.spawn(Net.Snapshot, 0)
		end
	end)
end

function actions.ShowInDex(row: any)
	local N = nav()
	if N then
		N.OpenScreen("Collection", { CollectionDepth = row.Depth })
	end
end

-- The ••• menu next to SELL.
function actions.Menu(anchor: GuiObject, row: any)
	local Overlay = Kit.Overlay
	local items = {
		{ Text = T("LIST ON MARKET"), Enabled = row.Tradeable, Run = function()
			actions.List(row)
		end },
		{ Text = T("SHOW IN DEX"), Enabled = true, Run = function()
			actions.ShowInDex(row)
		end },
	}
	local rowH = 44
	local entry: any = nil
	local panel: any, catcher: any = nil, nil
	local function close()
		if entry then
			Overlay.Remove(entry)
			entry = nil
		end
		if panel then
			panel:Destroy()
			catcher:Destroy()
			panel = nil
		end
	end
	panel, catcher = Overlay.Popup(anchor, 240, #items * rowH + 8, close)
	entry = Overlay.Push({ Dismiss = close, Kind = "popup" })
	Kit.Sound.Play("Open", { Pitch = 1.3, Volume = 0.7 })
	for i, item in ipairs(items) do
		local button = Kit.Text(panel, {
			Name = "Option" .. i,
			Class = "TextButton",
			Text = item.Text,
			TextSize = 16,
			Color = item.Enabled and Theme.Ink or Theme.InkMuted,
			Position = UDim2.fromOffset(4, 4 + (i - 1) * rowH),
			Size = UDim2.new(1, -8, 0, rowH - 2),
			ZIndex = panel.ZIndex + 2,
			NoTranslate = true,
		})
		Kit.Padding(button, 12, 0, 12, 0)
		Kit.Sound.Attach(button)
		button.Activated:Connect(function()
			close()
			if item.Enabled then
				item.Run()
			else
				Kit.Toast(T("This find cannot be traded."), { Kind = "warn", NoTranslate = true })
			end
		end)
	end
end

function actions.OpenAtPad(_g: any)
	local N = nav()
	Kit.Toast(T("Open Lucky Blocks at the Lucky pads in your yard."), { Kind = "info", NoTranslate = true })
	if N then
		N.Navigate("Your yard")
	end
end

function actions.Chances(g: any)
	local N = nav()
	if N then
		N.OpenScreen("LuckyOdds", {
			LuckyOffer = false,
			BlockOddsUid = g.Uid or false,
			BlockOddsTier = g.Tier,
			BlockOddsPage = 1,
			BlockCatalog = false,
			BlockCatalogFailed = false,
			BlockMessage = false,
		})
	end
end

-- The FILTERS popover: depth (one), mutations (several), favourites only, CLEAR.
local function openFilters()
	local Overlay = Kit.Overlay
	local anchor = ui.FilterButton.Instance
	local mutations = Logic.Mutations(st.Rows, ValueConfig)
	local layer = anchor:FindFirstAncestorWhichIsA("LayerCollector")
	local screenW = layer and layer.AbsoluteSize.X or 400
	local w = math.min(380, screenW - 16)
	local pad, labelH, chipH, gap = 12, 20, 36, 6
	local h = pad + labelH + chipH + gap + labelH + chipH + gap + chipH + gap + 40 + pad
	local entry: any = nil
	local panel: any, catcher: any = nil, nil
	local function close()
		if entry then
			Overlay.Remove(entry)
			entry = nil
		end
		if panel then
			panel:Destroy()
			catcher:Destroy()
			panel = nil
		end
	end
	panel, catcher = Overlay.Popup(anchor, w, h, close)
	entry = Overlay.Push({ Dismiss = close, Kind = "popup" })
	Kit.Sound.Play("Open", { Pitch = 1.3, Volume = 0.7 })
	local z = panel.ZIndex + 1
	local y = pad
	local function heading(text: string)
		Kit.Text(panel, { Text = text, TextSize = 13, Color = Theme.InkMuted, Position = UDim2.fromOffset(pad, y), Size = UDim2.fromOffset(w - pad * 2, labelH), ZIndex = z, NoTranslate = true })
		y += labelH
	end
	heading(T("DEPTH"))
	local depthOptions = { { Id = 0, Text = T("ALL"), NoTranslate = true } }
	for i = 1, 5 do
		if Depths[tostring(i)] then
			table.insert(depthOptions, { Id = i, Text = depthName(i), NoTranslate = true })
		end
	end
	Kit.Chips(panel, {
		Name = "Depth",
		Options = depthOptions,
		Selected = st.Depth or 0,
		AllowNone = false,
		TextSize = 14,
		Position = UDim2.fromOffset(pad - 2, y),
		Size = UDim2.fromOffset(w - pad * 2 + 4, chipH),
		ZIndex = z,
		OnChange = function(id)
			st.Depth = (id and id ~= 0) and id or nil
			refreshFinds(true)
		end,
	})
	y += chipH + gap
	heading(T("MUTATION"))
	if #mutations == 0 then
		Kit.Text(panel, { Text = T("No mutated finds yet."), TextSize = 14, Color = Theme.InkMuted, Position = UDim2.fromOffset(pad, y), Size = UDim2.fromOffset(w - pad * 2, chipH), ZIndex = z, NoTranslate = true })
	else
		local options, selected = {}, {}
		for _, name in ipairs(mutations) do
			table.insert(options, { Id = name, Text = name, Color = Theme.MutationColor(name) })
			if st.Mutations[name] then
				table.insert(selected, name)
			end
		end
		Kit.Chips(panel, {
			Name = "Mutations",
			Multi = true,
			Options = options,
			Selected = selected,
			TextSize = 14,
			Position = UDim2.fromOffset(pad - 2, y),
			Size = UDim2.fromOffset(w - pad * 2 + 4, chipH),
			ZIndex = z,
			OnChange = function(list)
				local set = {}
				for _, name in ipairs(list) do
					set[name] = true
				end
				st.Mutations = set
				refreshFinds(true)
			end,
		})
	end
	y += chipH + gap
	Kit.Chips(panel, {
		Name = "Favourites",
		Multi = true,
		Options = { { Id = "fav", Text = "★ " .. T("FAVOURITES ONLY"), Color = P.gold, NoTranslate = true } },
		Selected = st.Favorites and { "fav" } or {},
		TextSize = 14,
		Position = UDim2.fromOffset(pad - 2, y),
		Size = UDim2.fromOffset(w - pad * 2 + 4, chipH),
		ZIndex = z,
		OnChange = function(list)
			st.Favorites = #list > 0
			refreshFinds(true)
		end,
	})
	y += chipH + gap
	Kit.Button(panel, {
		Name = "Clear",
		Text = T("CLEAR FILTERS"),
		Style = "secondary",
		TextSize = 15,
		Position = UDim2.fromOffset(pad, y),
		Size = UDim2.fromOffset(w - pad * 2, 40),
		ZIndex = z,
		NoTranslate = true,
		OnClick = function()
			st.Depth, st.Mutations, st.Favorites = nil, {}, false
			close()
			refreshFinds(true)
		end,
	})
end

------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------
local function place(object: GuiObject, x: number, y: number, w: number, h: number)
	object.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	object.Size = UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h)))
end

local function relayout()
	if not (win and ui) then
		return
	end
	local L = win:GetLayout()
	local w, h = L.Width, L.Height
	if w < 2 then
		return
	end
	local phone, landscape = L.Phone == true, L.Landscape == true
	local wasPhone = st.Phone
	st.Phone = phone
	local gap = phone and 6 or 10
	local barH = phone and (landscape and 36 or 40) or 42
	-- FINDS.
	local detailW = phone and 0 or math.clamp(math.floor(w * 0.36), 300, 380)
	local listW = phone and w or (w - detailW - 12)
	local y = 0
	local filterW = phone and barH + 22 or 128
	if phone and not landscape then
		place(ui.Search.Instance, 0, 0, w - filterW - gap, barH)
		place(ui.FilterButton.Instance, w - filterW, 0, filterW, barH)
		y = barH + gap
		local sortW = math.min(170, math.floor(w * 0.46))
		place(ui.Sort.Instance, 0, y, sortW, barH)
		place(ui.Chips.Instance, sortW + gap, y, w - sortW - gap, barH)
		y += barH + gap
	else
		local searchW = phone and 190 or math.clamp(math.floor(w * 0.24), 190, 270)
		local sortW = phone and 168 or 200
		place(ui.Search.Instance, 0, 0, searchW, barH)
		place(ui.Sort.Instance, searchW + gap, 0, sortW, barH)
		place(ui.FilterButton.Instance, searchW + sortW + gap * 2, 0, filterW, barH)
		local cx = searchW + sortW + filterW + gap * 3
		place(ui.Chips.Instance, cx, 0, w - cx, barH)
		y = barH + gap
	end
	local capH = phone and 22 or 24
	place(ui.CapRow, 0, y, w, capH)
	local barW = math.min(phone and 170 or 280, math.floor(w * 0.45))
	place(ui.CapBar.Instance, 0, 0, barW, capH)
	ui.CapValue.Instance.Position = UDim2.fromOffset(barW + 8, 0)
	ui.CapValue.Instance.Size = UDim2.fromOffset(0, capH)
	local fullW = math.min(phone and 190 or 240, w - barW - 16)
	place(ui.CapFull.Instance, w - fullW, -2, fullW, capH + 4)
	y += capH + gap
	place(ui.GridHost, 0, y, listW, h - y)
	ui.Detail.Root.Visible = not phone
	if not phone then
		place(ui.Detail.Root, listW + 12, y, detailW, h - y)
		ui.Detail:Layout(detailW, h - y)
	end
	-- LUCKY BLOCKS.
	local headH = phone and 26 or 30
	place(ui.BlockHead, 0, 0, w, headH)
	local by = headH + gap
	place(ui.BlockGridHost, 0, by, listW, h - by)
	ui.BlockDetail.Root.Visible = not phone
	if not phone then
		place(ui.BlockDetail.Root, listW + 12, by, detailW, h - by)
		ui.BlockDetail:Layout(detailW, h - by)
	end
	if wasPhone ~= phone then
		if not phone and detailWin and detailWin.IsOpen then
			detailWin:Close("layout")
		end
		updateFilterButton()
		refreshFinds(false)
		refreshBlocks()
	end
end

function S._buildDetailWindow()
	if detailWin then
		return
	end
	detailWin = Kit.Window.new({
		Key = "InventoryDetail",
		Title = T("MY BAG"),
		Accent = ACCENT,
		Icon = "Inventory",
		Stack = true,
		MaxSize = Vector2.new(520, 760),
	})
	dw = buildDetail(detailWin.Body, true)
	dw.Root.Size = UDim2.fromScale(1, 1)
	detailWin.Resized:Connect(function(L)
		dw:Layout(L.Width, L.Height)
	end)
	S.DetailWindow, S.DetailUI = detailWin, dw
end

local function build()
	if win then
		return
	end
	win = Kit.Window.new({
		Key = "Inventory",
		Title = T("MY BAG"),
		Accent = ACCENT,
		Icon = "Inventory",
		NoTranslate = true,
		MaxSize = Vector2.new(1120, 780),
		Tabs = {
			{ Id = "finds", Text = T("FINDS"), NoTranslate = true },
			{ Id = "blocks", Text = T("LUCKY BLOCKS"), NoTranslate = true },
		},
		Tab = st.Tab,
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			S._closed()
		end,
		OnTab = function(id)
			st.Tab = id
			bindDetail()
		end,
	})
	S.Window = win
	ui = { Lang = Kit.Lang() }
	S.UI = ui
	local finds = win:Page("finds")
	local blocks = win:Page("blocks")
	-- Toolbar.
	ui.Search = Kit.SearchBox(finds, {
		Name = "Search",
		Placeholder = T("Search finds"),
		ZIndex = Z,
		OnChange = function(text)
			st.Query = text
			refreshFinds(true)
		end,
	})
	ui.Sort = Kit.SortSelect(finds, {
		Name = "Sort",
		Options = {
			{ Id = "rarest", Text = T("RAREST"), NoTranslate = true, Descending = true },
			{ Id = "newest", Text = T("NEWEST"), NoTranslate = true, Descending = true },
			{ Id = "value", Text = T("VALUE"), NoTranslate = true, Descending = true },
			{ Id = "heaviest", Text = T("HEAVIEST"), NoTranslate = true, Descending = true },
			{ Id = "name", Text = T("NAME"), NoTranslate = true, Descending = false },
		},
		Selected = st.Sort,
		Descending = st.Desc,
		ZIndex = Z,
		OnChange = function(id, descending)
			st.Sort, st.Desc = id, descending
			refreshFinds(true)
		end,
	})
	ui.FilterButton = Kit.Button(finds, {
		Name = "Filters",
		Text = T("FILTERS"),
		Style = "secondary",
		TextSize = 16,
		NoTranslate = true,
		ZIndex = Z,
		OnClick = function()
			openFilters()
		end,
	})
	pcall(function()
		Kit.Tooltip(ui.FilterButton.Instance, function()
			return T("Depth, mutation and favourites."), T("FILTERS")
		end)
	end)
	local rarityOptions = {}
	for _, rarity in ipairs(Logic.Rarities) do
		table.insert(rarityOptions, { Id = rarity, Text = string.upper(rarity), Color = Theme.RarityColor(rarity) })
	end
	ui.Chips = Kit.Chips(finds, {
		Name = "Rarities",
		Multi = true,
		Options = rarityOptions,
		TextSize = 14,
		ZIndex = Z,
		OnChange = function(list)
			st.Rarities = list
			refreshFinds(true)
		end,
	})
	-- Capacity row.
	ui.CapRow = Kit.New("Frame", { Name = "Capacity", BackgroundTransparency = 1, ZIndex = Z }, finds)
	ui.CapBar = Kit.ProgressBar(ui.CapRow, { Name = "Bar", Value = 0, Text = "0 / 0", Height = 24, ZIndex = Z + 1, NoTranslate = true })
	ui.CapValue = Kit.Pill(ui.CapRow, {
		Name = "Value",
		Text = "💰 0",
		Height = 24,
		TextSize = 14,
		Font = "numeric",
		Color = P.secondary,
		TextColor = Theme.Ink,
		ZIndex = Z + 1,
		NoTranslate = true,
	})
	pcall(function()
		Kit.Tooltip(ui.CapValue.Instance, function()
			return T("What all your finds sell for at the collector."), T("BAG VALUE")
		end)
	end)
	ui.CapFull = Kit.Button(ui.CapRow, {
		Name = "Full",
		Text = T("BAG FULL · GO SELL"),
		Style = "danger",
		TextSize = 14,
		NoTranslate = true,
		ZIndex = Z + 1,
		OnClick = function()
			st.Near = nearCollector()
			if st.Near then
				Kit.Toast(T("Pick a find and press SELL."), { Kind = "info", NoTranslate = true })
			else
				goSell()
			end
		end,
	})
	ui.CapFull.Instance.Visible = false
	-- Grid and detail.
	ui.GridHost = Kit.New("Frame", { Name = "GridHost", BackgroundTransparency = 1, ZIndex = Z }, finds)
	ui.Grid = Kit.CardGrid(ui.GridHost, {
		Name = "Finds",
		Kind = "Item",
		CardSize = Vector2.new(150, 200),
		RowHeight = 76,
		ZIndex = Z,
		Map = function(row)
			return cardData(row)
		end,
		Key = function(row)
			return row.Key
		end,
		OnClick = function(row)
			select(row)
		end,
		Empty = {
			Icon = "Inventory",
			Title = T("NO FINDS YET"),
			Body = T("Dogs in your kennels dig up finds for you."),
			ActionText = T("GO TO MY YARD"),
			NoTranslate = true,
			OnAction = function()
				if Logic.Filtering(st) then
					clearFilters()
				else
					local N = nav()
					if N then
						N.Navigate("Your yard")
					end
				end
			end,
		},
	})
	ui.Detail = buildDetail(finds, false)
	-- LUCKY BLOCKS.
	ui.BlockHead = Kit.New("Frame", { Name = "BlockHead", BackgroundTransparency = 1, ZIndex = Z }, blocks)
	ui.BlockCount = Kit.Text(ui.BlockHead, {
		Name = "Count",
		Text = "🎲 0",
		TextSize = 18,
		Font = "numeric",
		Size = UDim2.new(0, 130, 1, 0),
		ZIndex = Z,
		NoTranslate = true,
	})
	Kit.Text(ui.BlockHead, {
		Name = "Hint",
		Text = T("Open them at the Lucky pads in your yard."),
		TextSize = 15,
		Color = Theme.InkMuted,
		Scaled = true,
		MinTextSize = 10,
		Position = UDim2.fromOffset(136, 0),
		Size = UDim2.new(1, -136, 1, 0),
		ZIndex = Z,
		NoTranslate = true,
	})
	ui.BlockGridHost = Kit.New("Frame", { Name = "BlockGridHost", BackgroundTransparency = 1, ZIndex = Z }, blocks)
	ui.BlockGrid = Kit.CardGrid(ui.BlockGridHost, {
		Name = "Blocks",
		Kind = "Item",
		CardSize = Vector2.new(150, 200),
		RowHeight = 76,
		ZIndex = Z,
		Map = blockCard,
		Key = function(g)
			return g.Tier
		end,
		OnClick = function(g)
			selectBlock(g)
		end,
		Empty = {
			Icon = "Inventory",
			Title = T("NO LUCKY BLOCKS YET"),
			Body = T("Buy one on the conveyor (press E)."),
			NoTranslate = true,
		},
	})
	ui.BlockDetail = buildDetail(blocks, false)
	ui.BlockDetail.Kind = "Block"
	win.Resized:Connect(function()
		relayout()
	end)
	relayout()
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
local function pending(): boolean
	for _, g in ipairs(st.Groups) do
		if g.NextReadyAt then
			return true
		end
	end
	return false
end

function S._opened()
	st.Token += 1
	local token = st.Token
	st.Near = nearCollector()
	local cached = Net.Cached()
	if cached then
		refresh(cached)
	else
		updateCapacity()
		refreshFinds(true)
		refreshBlocks()
	end
	relayout()
	task.spawn(function()
		local snapshot = Net.Snapshot(2)
		if snapshot and st.Token == token and win.IsOpen then
			refresh(snapshot)
		end
	end)
	-- While open: a slow refresh, and the pad timers once a second while one is running.
	task.spawn(function()
		local elapsed = 0
		while st.Token == token and win.IsOpen do
			task.wait(1)
			if st.Token ~= token or not win.IsOpen then
				break
			end
			elapsed += 1
			-- Walked up to (or away from) the collector: SELL <-> GO SELL.
			local near = nearCollector()
			if near ~= st.Near then
				st.Near = near
				bindDetail()
				updateCapacity()
			end
			if pending() and st.Snapshot and type(st.Snapshot.Profile) == "table" then
				-- Keyed SetItems rebinds the visible cards only (the timers and READY flips).
				st.Groups = Logic.Blocks(st.Snapshot.Profile, Kit.Now(), BlockConfig)
				refreshBlocks()
				updateCapacity()
			end
			if elapsed % 10 == 0 then
				Net.Snapshot(10)
			end
		end
	end)
end

function S._closed()
	st.Token += 1
end

Net.Changed:Connect(function(snapshot)
	if win and win.IsOpen then
		refresh(snapshot)
	else
		st.Snapshot = snapshot
	end
end)

-- The bag changed on the server (a find, a sale, a block): refresh soon while open.
local queued = false
local function bagChanged()
	if not (win and win.IsOpen) then
		return
	end
	updateCapacity()
	if queued then
		return
	end
	queued = true
	task.delay(1.5, function()
		queued = false
		if win and win.IsOpen then
			Net.Snapshot(1)
		end
	end)
end
for _, name in ipairs({ "InventoryRevision", "ItemCount", "ItemCapacity", "OwnedBlockCount", "AvailableBlockCount" }) do
	player:GetAttributeChangedSignal(name):Connect(bagChanged)
end

-- Labels are localized when the window is built: after a language change it is rebuilt.
local function rebuildIfLanguageChanged()
	if win and ui and ui.Lang ~= Kit.Lang() and not win.IsOpen then
		ui.Grid:Destroy()
		ui.BlockGrid:Destroy()
		win:Destroy()
		win, ui = nil, nil
		if detailWin then
			detailWin:Destroy()
			detailWin, dw = nil, nil
		end
	end
end

-- arg: the page message (shown as a toast) or {Tab = "finds" | "blocks"}; page: the route
-- name ("LuckyBlocks" / "OwnedBlocks" open the blocks tab).
function S.Open(arg: any, page: string?)
	rebuildIfLanguageChanged()
	build()
	local tab = nil
	if page == "LuckyBlocks" or page == "OwnedBlocks" then
		tab = "blocks"
	elseif type(arg) == "table" and (arg.Tab == "finds" or arg.Tab == "blocks") then
		tab = arg.Tab
	end
	if tab then
		st.Tab = tab
		win:SetTab(tab, true)
	end
	win:Open()
	if type(arg) == "string" and arg ~= "" then
		Kit.Toast(arg)
	end
end

function S.Close()
	if win and win.IsOpen then
		win:Close("api")
	end
end

function S.IsOpen(): boolean
	return win ~= nil and win.IsOpen
end

function S.Toggle(arg: any, page: string?)
	if S.IsOpen() then
		S.Close()
	else
		S.Open(arg, page)
	end
end

return S
