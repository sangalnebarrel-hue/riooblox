-- EQUIPMENT SHOP (Paw Market, the former UPGRADES building): a persistent kit window with two
-- clearly different tabs.
--   PLAYER ACCESSORIES  boost YOU: every dog and your earnings (one per slot Hat/Face/Back/Aura)
--   DOG ARTIFACTS       boost ONE DOG: equipped on a dog's slots (ArtifactPanel)
-- Each tab: CASES (price, odds, open x1, keys) and MY BAG (equipped, filters, sort, details,
-- lock, salvage for Bones). Opening plays Equipment.CaseOpening. Data: snapshot.Features.Equipment;
-- every action is a server request (Features.Equipment). Built once, updated in place.
--   EquipmentScreen.Open(tab?)  tab: "accessories" | "artifacts"
local Players = game:GetService("Players")
local Marketplace = game:GetService("MarketplaceService")

local Shared = require(script.Parent.Shared)
local CaseOpening = require(script.Parent.CaseOpening)
local ArtifactPanel = require(script.Parent.ArtifactPanel)
local Kit = Shared.Kit
local Net = Shared.Net
local E = Shared.E
local T = Shared.T
local W = Shared.W
local AccessoryTotals = require(game:GetService("ReplicatedStorage").DogEconomy.BonusSources.Accessories)

local M = {
	Window = nil :: any,
	Data = nil :: any,
	DogNames = {} :: { [string]: string },
	Detail = nil :: any,
	Opening = false,
	PolicyRetry = nil :: boolean?,
}
M.State = {
	Tab = "accessories",
	Segment = { accessories = "cases", artifacts = "cases" },
	Filter = {
		accessories = { Rarities = {}, Kind = "All", Sort = "rarity", Desc = true },
		artifacts = { Rarities = {}, Kind = "All", Sort = "rarity", Desc = true },
	},
	Selecting = false,
	Selected = {},
	Known = nil :: any,
	New = {},
}
M.UI = { Pages = {} }

local TABS = {
	accessories = { Kind = "Accessory", Accent = Shared.Colors.Accessory },
	artifacts = { Kind = "Artifact", Accent = Shared.Colors.Artifact },
}

local function snapshotNow(): any
	return Net.Cached()
end
local function dataNow(): any
	return Shared.Data(snapshotNow())
end
local function caseRow(caseId: string): any
	local data = dataNow()
	for _, row in ipairs(data and data.Cases or {}) do
		if row.Id == caseId then
			return row
		end
	end
	return nil
end
local function bagCount(data: any, kind: string): number
	return #((kind == "Artifact" and data.Artifacts or data.Accessories) or {})
end

------------------------------------------------------------------------------------------------
-- Case cards
------------------------------------------------------------------------------------------------
local function caseCard(parent: Instance, case: any, z: number): any
	local card: any = { Case = case, Buttons = {} }
	local accent = case.Kind == "Artifact" and Shared.Colors.Artifact or Shared.Colors.Accessory
	local look = case.Look or {}
	local base = look.Base and Color3.fromRGB(look.Base[1], look.Base[2], look.Base[3]) or accent
	local frame = Kit.New("Frame", { Name = "Case_" .. case.Id, BackgroundColor3 = Kit.Theme.White, BorderSizePixel = 0, ZIndex = z }, parent)
	Kit.Corner(frame, 14)
	Kit.Stroke(frame, base:Lerp(Kit.Theme.Colors.edge, 0.35), 2)
	Kit.New("UIGradient", { Rotation = 0, Color = ColorSequence.new(base:Lerp(Kit.Theme.White, 0.72), Kit.Theme.White) }, frame)
	card.Frame = frame
	card.Holder = Kit.New("Frame", { Name = "Preview", BackgroundTransparency = 1, ZIndex = z + 1 }, frame)
	card.Preview = Shared.Preview(card.Holder, { Kind = "Equipment", Case = case.Id })
	card.Title = Kit.Text(frame, { Name = "CaseName", Text = Shared.CaseName(case), TextSize = 20, Scaled = true, MinTextSize = 11, ZIndex = z + 1, NoTranslate = true })
	local rarities = {}
	for _, row in ipairs(E.Odds(case)) do
		table.insert(rarities, row.Rarity)
	end
	local what = case.Kind == "Artifact" and T("artifacts", "артефакты") or T("accessories", "аксессуары")
	card.Sub = Kit.Text(frame, {
		Name = "Contents",
		Text = Shared.Rarity(rarities[1]) .. " → " .. Shared.Rarity(rarities[#rarities]) .. " " .. what,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 8,
		Color = Kit.Theme.InkMuted,
		ZIndex = z + 1,
		NoTranslate = true,
	})
	card.Pity = Kit.ProgressBar(frame, { Name = "Pity", Height = 18, TextSize = 11, Color = Kit.Theme.RarityColor(case.Pity and case.Pity.Rarity or "Epic"), ZIndex = z + 1, NoTranslate = true })
	card.Odds = Kit.Button(frame, { Name = "Odds", Text = W("ODDS") .. " %", Style = "secondary", TextSize = 14, ZIndex = z + 2, NoTranslate = true, OnClick = function()
		local row = caseRow(case.Id)
		if row then
			Shared.ShowOdds(row)
		end
	end })
	Kit.Tooltip(card.Odds.Instance, T("Exact chances of every rarity, shown before you buy.", "Точные шансы каждой редкости — до покупки."), { Title = W("ODDS") })
	local function add(key: string, props: any)
		props.Name = key
		props.ZIndex = z + 2
		props.TextSize = props.TextSize or 15
		props.NoTranslate = true
		card.Buttons[key] = Kit.Button(frame, props)
	end
	if case.Cash then
		add("Cash", { Text = W("OPEN"), Style = "primary", Price = 0, OnClick = function()
			M.OpenCase(case.Id, "Cash", card.Buttons.Cash)
		end })
	end
	if case.Bones then
		add("Bones", { Text = W("OPEN"), Style = "gold", PriceIcon = "Bones", Price = case.Bones, OnClick = function()
			M.OpenCase(case.Id, "Bones", card.Buttons.Bones)
		end })
	end
	add("Credit", { Text = W("OPEN"), Style = "success", PriceText = "", OnClick = function()
		M.OpenCase(case.Id, "Credit", card.Buttons.Credit)
	end })
	for _, product in ipairs(E.Products) do
		if product.Case == case.Id then
			add("Buy_" .. product.Key, { Text = product.Count == 1 and W("BUY_KEY") or (T("BUY ", "КУПИТЬ ") .. product.Count .. T(" KEYS", " КЛЮЧЕЙ")), Style = "gold", PriceText = "R$", OnClick = function()
				M.BuyKey(case.Id, product.Key)
			end })
			card.Buttons["Buy_" .. product.Key].Product = product.Key
		end
	end
	function card.Update(row: any, profile: any, data: any)
		card.Row = row
		local visible = row ~= nil
		if row and case.Robux then
			local credits = (row.Credits.Free or 0) + (row.Credits.Paid or 0)
			visible = #row.Products > 0 or credits > 0
		end
		frame.Visible = visible
		if not row then
			return
		end
		local full = bagCount(data, case.Kind) >= (data.Capacity and data.Capacity[case.Kind] or math.huge)
		if card.Buttons.Cash then
			card.Buttons.Cash:SetPrice(row.Cash or 0)
			card.Buttons.Cash:SetText(full and W("BAG_FULL") or W("OPEN"))
		end
		if card.Buttons.Bones then
			card.Buttons.Bones:SetText(full and W("BAG_FULL") or W("OPEN"))
		end
		local credits = (row.Credits.Free or 0) + (row.Credits.Paid or 0)
		local creditButton = card.Buttons.Credit
		creditButton.Instance.Visible = credits > 0
		creditButton:SetPrice(credits .. " " .. W("KEYS"))
		creditButton:SetText(full and W("BAG_FULL") or W("OPEN"))
		for _, product in ipairs(E.Products) do
			local button = card.Buttons["Buy_" .. product.Key]
			if button then
				local live = nil
				for _, p in ipairs(row.Products or {}) do
					if p.Key == product.Key then
						live = p
					end
				end
				button.Instance.Visible = live ~= nil
				button.Live = live
				if live then
					button:SetPrice(Shared.RobuxPrice(live, function()
						-- Roblox's own price arrived: show it.
						M.Refresh()
					end))
				end
			end
		end
		if row.Pity then
			local left = math.max(1, row.Pity.Opens - row.Pity.Count)
			card.Pity.Instance.Visible = true
			card.Pity:SetValue(math.clamp(row.Pity.Count / row.Pity.Opens, 0.02, 1))
			card.Pity:SetText(Shared.Rarity(row.Pity.Rarity) .. T("+ GUARANTEED IN ", "+ ГАРАНТИЯ ЧЕРЕЗ ") .. left)
		else
			card.Pity.Instance.Visible = false
		end
		card.Layout(card.Width or 300, card.Height or 170)
	end
	function card.Layout(w: number, h: number)
		card.Width, card.Height = w, h
		local pad = 10
		local view = math.min(h - 64, 96)
		card.Holder.Position = UDim2.fromOffset(pad, pad)
		card.Holder.Size = UDim2.fromOffset(view, view)
		local x = pad + view + 10
		local oddsW = 74
		card.Title.Position = UDim2.fromOffset(x, pad)
		card.Title.Size = UDim2.fromOffset(math.max(40, w - x - oddsW - pad - 6), 26)
		card.Odds.Instance.Position = UDim2.fromOffset(w - pad - oddsW, pad)
		card.Odds.Instance.Size = UDim2.fromOffset(oddsW, 32)
		card.Sub.Position = UDim2.fromOffset(x, pad + 30)
		card.Sub.Size = UDim2.fromOffset(w - x - pad, 18)
		card.Pity.Instance.Position = UDim2.fromOffset(x, pad + 54)
		card.Pity.Instance.Size = UDim2.fromOffset(w - x - pad, 18)
		-- Open buttons on the bottom row; Robux key packs get a row of their own under them.
		local opens, buys = {}, {}
		for _, key in ipairs({ "Cash", "Bones", "Credit" }) do
			local b = card.Buttons[key]
			if b and b.Instance.Visible then
				table.insert(opens, b)
			end
		end
		for _, product in ipairs(E.Products) do
			local b = card.Buttons["Buy_" .. product.Key]
			if b and b.Instance.Visible then
				table.insert(buys, b)
			end
		end
		local buttonH = 44
		local gap = 8
		local extra = (#opens > 0 and #buys > 0) and (buttonH + gap) or 0
		local function row(list: { any }, y: number)
			local bw = #list > 0 and math.floor((w - pad * 2 - gap * (#list - 1)) / #list) or 0
			for i, b in ipairs(list) do
				b.Instance.Position = UDim2.fromOffset(pad + (i - 1) * (bw + gap), y)
				b.Instance.Size = UDim2.fromOffset(bw, buttonH)
			end
		end
		local bottom = h + extra - pad - buttonH
		if #opens > 0 and #buys > 0 then
			row(opens, bottom - buttonH - gap)
			row(buys, bottom)
		else
			row(#opens > 0 and opens or buys, bottom)
		end
		frame.Size = UDim2.new(1, -6, 0, h + extra)
	end
	return card
end

------------------------------------------------------------------------------------------------
-- Equipped strip (accessories) / dogs strip (artifacts)
------------------------------------------------------------------------------------------------
local function slotTile(parent: Instance, slot: string, z: number): any
	local tile: any = { Slot = slot }
	local button = Kit.New("TextButton", { Name = "Slot_" .. slot, Text = "", AutoButtonColor = false, BackgroundColor3 = Kit.Theme.White, BorderSizePixel = 0, ZIndex = z }, parent)
	Kit.Corner(button, 12)
	tile.Stroke = Kit.Stroke(button, Kit.Theme.Colors.edge, 2, 0.4)
	tile.Button = button
	tile.Label = Kit.Text(button, { Name = "SlotName", Text = Shared.SlotName(slot), TextSize = 12, Color = Kit.Theme.InkMuted, AlignX = "Center", ZIndex = z + 1, NoTranslate = true })
	tile.Holder = Kit.New("Frame", { Name = "Preview", BackgroundTransparency = 1, ZIndex = z + 1 }, button)
	tile.Preview = Kit.Preview.Slot(tile.Holder)
	tile.Empty = Kit.Text(button, { Name = "EmptyMark", Text = "+", TextSize = 30, AlignX = "Center", Color = Shared.Colors.Accessory, ZIndex = z + 1, NoTranslate = true })
	tile.Stat = Kit.Text(button, { Name = "Stat", TextSize = 13, Scaled = true, MinTextSize = 8, AlignX = "Center", Font = "numeric", ZIndex = z + 1, NoTranslate = true })
	function tile.Layout(w: number, h: number)
		local label = 16
		local stat = 16
		local s = math.max(20, math.min(w - 8, h - label - stat - 8))
		tile.Label.Position = UDim2.fromOffset(4, 3)
		tile.Label.Size = UDim2.new(1, -8, 0, label)
		tile.Holder.Position = UDim2.new(0.5, -s / 2, 0, label + 3)
		tile.Holder.Size = UDim2.fromOffset(s, s)
		tile.Empty.Position = UDim2.fromOffset(0, label + 3)
		tile.Empty.Size = UDim2.new(1, 0, 0, s)
		tile.Stat.Position = UDim2.new(0, 4, 1, -(stat + 3))
		tile.Stat.Size = UDim2.new(1, -8, 0, stat)
	end
	Kit.LongPress(button, function()
		if tile.Entry then
			M.ShowPiece(tile.Entry)
		end
	end)
	button.Activated:Connect(function()
		if tile.Entry then
			M.ShowPiece(tile.Entry)
		else
			-- Empty slot: show the bag filtered to that slot.
			local page = M.UI.Pages.accessories
			M.State.Filter.accessories.Kind = slot
			if page and page.KindChips then
				page.KindChips:SetSelected(slot, true)
			end
			M.SetSegment("accessories", "bag")
			M.Refresh()
		end
	end)
	return tile
end

------------------------------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------------------------------
local function buildPage(tabId: string)
	local info = TABS[tabId]
	local kind = info.Kind
	local win = M.Window
	local root = win:Page(tabId)
	local z = 3
	local page: any = { Id = tabId, Kind = kind, Root = root, Cards = {} }
	M.UI.Pages[tabId] = page
	local accent = info.Accent

	-- Banner: who this tab boosts, in the tab's colour.
	local banner = Kit.New("Frame", { Name = "Banner", BackgroundColor3 = Kit.Theme.White, BorderSizePixel = 0, ZIndex = z }, root)
	Kit.Corner(banner, 14)
	Kit.New("UIGradient", { Rotation = 0, Color = ColorSequence.new(accent, accent:Lerp(Kit.Theme.White, 0.35)) }, banner)
	Kit.Stroke(banner, accent:Lerp(Kit.Theme.Colors.edge, 0.4), 2)
	page.Banner = banner
	page.BannerIcon = Kit.Text(banner, { Name = "Icon", Text = kind == "Artifact" and "🐾" or "★", TextSize = 30, AlignX = "Center", Color = Kit.Theme.White, Stroke = 0, ZIndex = z + 1, NoTranslate = true })
	page.BannerTitle = Kit.Text(banner, {
		Name = "Title",
		Text = kind == "Artifact" and T("DOG ARTIFACTS BOOST ONE DOG", "АРТЕФАКТЫ УСИЛИВАЮТ ОДНУ СОБАКУ") or T("ACCESSORIES BOOST YOU", "АКСЕССУАРЫ УСИЛИВАЮТ ТЕБЯ"),
		TextSize = 22,
		Scaled = true,
		MinTextSize = 12,
		Color = Kit.Theme.White,
		Stroke = 0,
		ZIndex = z + 1,
		NoTranslate = true,
	})
	page.BannerBody = Kit.Text(banner, {
		Name = "Body",
		Text = kind == "Artifact"
				and T("Put an artifact on a dog: only that dog gets the bonus. Better dogs have more slots (Common 1 · Rare/Epic 2 · Legendary/Mythic 3 · Secret 4).",
					"Надень артефакт на собаку: бонус получит только она. У лучших собак больше слотов (Обычная 1 · Редкая/Эпическая 2 · Легендарная/Мифическая 3 · Секретная 4).")
			or T("Wear one in each slot (hat, face, back, aura). Their bonus works for ALL your dogs and your earnings.",
				"Носи по одному в каждом слоте (шапка, лицо, спина, аура). Бонус действует на ВСЕХ собак и твой доход."),
		TextSize = 14,
		Scaled = true,
		MinTextSize = 8,
		Wrap = true,
		Color = Kit.Theme.White,
		Stroke = 0.45,
		ZIndex = z + 1,
		NoTranslate = true,
	})
	page.BannerStat = Kit.Text(banner, { Name = "Summary", TextSize = 15, Scaled = true, MinTextSize = 9, Wrap = true, AlignX = "Right", Font = "numeric", Color = Kit.Theme.White, Stroke = 0.2, ZIndex = z + 1, NoTranslate = true })

	-- Phone segment: CASES | MY BAG.
	page.Segment = Kit.Chips(root, {
		Name = "Segment",
		Options = { { Id = "cases", Text = W("CASES"), NoTranslate = true }, { Id = "bag", Text = W("BAG"), NoTranslate = true } },
		Selected = "cases",
		AllowNone = false,
		ZIndex = z,
		OnChange = function(id)
			M.SetSegment(tabId, id)
		end,
	})
	page.Scope = Kit.Pill(root, { Name = "Scope", Text = Shared.Scope(kind), Color = accent, Height = 26, TextSize = 13, ZIndex = z, NoTranslate = true })

	-- CASES column.
	local cases = Kit.New("ScrollingFrame", {
		Name = "Cases",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = z,
	}, root)
	Kit.New("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, cases)
	Kit.Padding(cases, 2, 2, 2, 2)
	page.Cases = cases
	page.CasesTitle = Kit.Text(cases, { Name = "Heading", Text = W("CASES"), TextSize = 18, Size = UDim2.new(1, -6, 0, 22), LayoutOrder = 0, ZIndex = z, NoTranslate = true })
	for _, case in ipairs(E.Cases) do
		if case.Kind == kind then
			local card = caseCard(cases, case, z)
			card.Frame.LayoutOrder = case.Order
			page.Cards[case.Id] = card
		end
	end

	-- MY BAG column.
	local bag = Kit.New("Frame", { Name = "Bag", BackgroundTransparency = 1, ZIndex = z }, root)
	page.Bag = bag
	local strip = Kit.New("Frame", { Name = "Equipped", BackgroundColor3 = Kit.Theme.SurfaceAlt, BorderSizePixel = 0, ZIndex = z }, bag)
	Kit.Corner(strip, 12)
	page.Strip = strip
	if kind == "Accessory" then
		page.SlotTiles = {}
		for _, slot in ipairs(E.Slots) do
			page.SlotTiles[slot] = slotTile(strip, slot, z + 1)
		end
		page.StripTitle = Kit.Text(strip, { Name = "Title", Text = T("WORN NOW", "НАДЕТО"), TextSize = 14, Color = Kit.Theme.InkMuted, ZIndex = z + 1, NoTranslate = true })
	else
		page.StripText = Kit.Text(strip, { Name = "Info", TextSize = 15, Scaled = true, MinTextSize = 9, Wrap = true, ZIndex = z + 1, NoTranslate = true })
		page.Manage = Kit.Button(strip, { Name = "Manage", Text = T("MANAGE A DOG", "ВЫБРАТЬ СОБАКУ"), Style = "primary", TextSize = 15, ZIndex = z + 2, NoTranslate = true, OnClick = function()
			M.ManageDog()
		end })
	end

	local filter = M.State.Filter[tabId]
	local kindOptions = { { Id = "All", Text = W("ALL"), NoTranslate = true } }
	if kind == "Accessory" then
		for _, slot in ipairs(E.Slots) do
			table.insert(kindOptions, { Id = slot, Text = Shared.SlotName(slot), NoTranslate = true })
		end
	else
		for _, stat in ipairs(E.ArtifactStats) do
			table.insert(kindOptions, { Id = stat, Text = Shared.StatName(stat), Color = Shared.StatColor(stat), NoTranslate = true })
		end
	end
	page.KindChips = Kit.Chips(bag, {
		Name = "KindFilter",
		Options = kindOptions,
		Selected = "All",
		AllowNone = false,
		ZIndex = z,
		OnChange = function(id)
			filter.Kind = id or "All"
			M.Refresh(nil, { ResetScroll = true })
		end,
	})
	local rarityOptions = {}
	for _, rarity in ipairs(E.Rarities) do
		table.insert(rarityOptions, { Id = rarity, Text = Shared.Rarity(rarity), Color = Shared.RarityColor(rarity), NoTranslate = true })
	end
	page.RarityChips = Kit.Chips(bag, {
		Name = "RarityFilter",
		Multi = true,
		Options = rarityOptions,
		ZIndex = z,
		OnChange = function(selected)
			filter.Rarities = {}
			for _, id in ipairs(selected or {}) do
				filter.Rarities[id] = true
			end
			M.Refresh(nil, { ResetScroll = true })
		end,
	})
	page.Sort = Kit.SortSelect(bag, {
		Name = "Sort",
		Options = {
			{ Id = "rarity", Text = W("SORT_RARITY"), NoTranslate = true },
			{ Id = "value", Text = W("SORT_VALUE"), NoTranslate = true },
			{ Id = "new", Text = W("SORT_NEW"), NoTranslate = true },
		},
		Selected = "rarity",
		ZIndex = z,
		OnChange = function(id, descending)
			filter.Sort, filter.Desc = id, descending ~= false
			M.Refresh(nil, { ResetScroll = true })
		end,
	})
	page.SelectButton = Kit.Button(bag, { Name = "Select", Text = W("SALVAGE"), Style = "secondary", TextSize = 15, ZIndex = z, NoTranslate = true, OnClick = function()
		M.SetSelecting(not M.State.Selecting)
	end })
	Kit.Tooltip(page.SelectButton.Instance, T("Pick pieces you do not need and turn them into Bones.", "Выбери ненужные предметы и разбери их на кости."), { Title = W("SALVAGE") })
	page.Grid = Kit.CardGrid(bag, {
		Name = "Grid",
		Kind = "Item",
		ZIndex = z,
		CardSize = Vector2.new(146, 196),
		Map = function(entry)
			return Shared.Card(entry, { Selecting = M.State.Selecting, Selected = M.State.Selected, New = M.State.New })
		end,
		Key = function(entry)
			return entry.Uid
		end,
		Empty = {
			Title = T("YOUR BAG IS EMPTY", "СУМКА ПУСТА"),
			Body = kind == "Artifact" and T("Open a case to get your first artifact.", "Открой кейс, чтобы получить первый артефакт.")
				or T("Open a case to get your first accessory.", "Открой кейс, чтобы получить первый аксессуар."),
			ActionText = W("CASES"),
			NoTranslate = true,
			OnAction = function()
				M.SetSegment(tabId, "cases")
			end,
		},
		OnClick = function(entry, _, card)
			if M.State.Selecting then
				M.ToggleSelect(entry, card)
			else
				M.ShowPiece(entry)
			end
		end,
		OnLongPress = function(entry)
			M.ShowPiece(entry)
		end,
	})
	-- Salvage bar (select mode).
	local bar = Kit.New("Frame", { Name = "SalvageBar", BackgroundColor3 = Kit.Theme.White, BorderSizePixel = 0, Visible = false, ZIndex = z + 2 }, bag)
	Kit.Corner(bar, 12)
	Kit.Stroke(bar, Kit.Theme.Danger, 2)
	page.Bar = bar
	page.BarText = Kit.Text(bar, { Name = "Summary", TextSize = 15, Scaled = true, MinTextSize = 9, ZIndex = z + 3, NoTranslate = true })
	page.BarAll = Kit.Button(bar, { Name = "SelectShown", Text = T("SELECT SHOWN", "ВЫБРАТЬ ВСЁ"), Style = "secondary", TextSize = 14, ZIndex = z + 3, NoTranslate = true, OnClick = function()
		M.SelectShown(tabId)
	end })
	page.BarGo = Kit.Button(bar, { Name = "Salvage", Text = W("SALVAGE"), Style = "danger", TextSize = 15, ZIndex = z + 3, NoTranslate = true, OnClick = function()
		M.SalvageSelected()
	end })
	page.BarCancel = Kit.Button(bar, { Name = "Cancel", Text = W("CANCEL"), Style = "secondary", TextSize = 14, ZIndex = z + 3, NoTranslate = true, OnClick = function()
		M.SetSelecting(false)
	end })
	return page
end

-- Positions every part of a page for the window layout.
local function layoutPage(page: any, l: any)
	local w, h = l.Width, l.Height
	if w < 2 then
		return
	end
	local phone = l.Phone
	local landscape = l.Landscape
	local gap = phone and 6 or 10
	local y = 0
	-- Banner (hidden on landscape phones: the scope pill keeps the message).
	local bannerH = landscape and 0 or (phone and 58 or 66)
	page.Banner.Visible = bannerH > 0
	if bannerH > 0 then
		page.Banner.Position = UDim2.fromOffset(0, 0)
		page.Banner.Size = UDim2.new(1, 0, 0, bannerH)
		local iconW = phone and 34 or 46
		page.BannerIcon.Position = UDim2.fromOffset(6, 0)
		page.BannerIcon.Size = UDim2.new(0, iconW, 1, 0)
		local statW = phone and 0 or math.floor(math.min(260, w * 0.3))
		page.BannerStat.Visible = statW > 0
		page.BannerStat.Position = UDim2.new(1, -(statW + 12), 0, 6)
		page.BannerStat.Size = UDim2.new(0, statW, 1, -12)
		page.BannerTitle.Position = UDim2.fromOffset(iconW + 10, 5)
		page.BannerTitle.Size = UDim2.new(1, -(iconW + 22 + statW), 0, phone and 22 or 26)
		page.BannerBody.Position = UDim2.fromOffset(iconW + 10, (phone and 27 or 32))
		page.BannerBody.Size = UDim2.new(1, -(iconW + 22 + statW), 0, bannerH - (phone and 30 or 36))
		y = bannerH + gap
	end
	-- Segment row (phones) / nothing (desktop).
	if phone then
		local segH = landscape and 32 or 36
		page.Segment.Instance.Visible = true
		page.Segment.Instance.Position = UDim2.fromOffset(0, y)
		-- Portrait phones have the banner; landscape ones show who it boosts next to the segment.
		page.Segment.Instance.Size = UDim2.new(landscape and 0.6 or 1, 0, 0, segH)
		page.Scope.Instance.Visible = landscape
		page.Scope.Instance.AnchorPoint = Vector2.new(1, 0)
		page.Scope.Instance.Position = UDim2.new(1, 0, 0, y + math.floor((segH - 26) / 2))
		y += segH + gap
	else
		page.Segment.Instance.Visible = false
		page.Scope.Instance.Visible = false
	end
	local contentH = h - y
	local segment = M.State.Segment[page.Id]
	local casesX, casesW, bagX, bagW
	if phone then
		casesX, casesW, bagX, bagW = 0, w, 0, w
		page.Cases.Visible = segment == "cases"
		page.Bag.Visible = segment == "bag"
	else
		casesW = math.floor(math.clamp(w * 0.34, 280, 350))
		casesX, bagX, bagW = 0, casesW + gap, w - casesW - gap
		page.Cases.Visible = true
		page.Bag.Visible = true
	end
	page.Cases.Position = UDim2.fromOffset(casesX, y)
	page.Cases.Size = UDim2.fromOffset(casesW, contentH)
	local cardH = phone and 164 or 172
	for _, card in pairs(page.Cards) do
		card.Layout(casesW - 10, cardH)
	end
	page.Bag.Position = UDim2.fromOffset(bagX, y)
	page.Bag.Size = UDim2.fromOffset(bagW, contentH)
	-- Inside the bag: the equipped strip (left column on landscape phones), toolbar, grid, bar.
	local rowH = phone and 34 or 38
	local bw = phone and 92 or 120
	local stripX, stripW, stripH, gridX, gridW, top
	-- Salvage bar: [summary][CANCEL][SELECT SHOWN][SALVAGE] on one row, or the summary on its own
	-- row above the buttons where the grid is too narrow for both (portrait phones, narrow windows).
	local barGridW = landscape and (bagW - math.floor(math.clamp(bagW * 0.3, 170, 240)) - gap) or bagW
	local barTwoRows = barGridW - (bw * 3 + 40) < 160
	local barH = M.State.Selecting and (barTwoRows and 100 or 56) or 0
	if landscape then
		stripW = math.floor(math.clamp(bagW * 0.3, 170, 240))
		stripX, stripH = 0, contentH - barH
		gridX, gridW, top = stripW + gap, bagW - stripW - gap, 0
	else
		stripX, stripW = 0, bagW
		stripH = page.Kind == "Accessory" and (phone and 96 or 104) or (phone and 58 or 54)
		gridX, gridW, top = 0, bagW, stripH + gap
	end
	page.Strip.Position = UDim2.fromOffset(stripX, 0)
	page.Strip.Size = UDim2.fromOffset(stripW, stripH)
	if page.SlotTiles then
		local titleH = landscape and 18 or 0
		page.StripTitle.Visible = landscape
		page.StripTitle.Position = UDim2.fromOffset(8, 2)
		page.StripTitle.Size = UDim2.new(1, -16, 0, 16)
		local cols = landscape and 2 or 4
		local rows = landscape and 2 or 1
		local tw = math.floor((stripW - 8 - 6 * (cols - 1)) / cols)
		local th = math.floor((stripH - 8 - titleH - 6 * (rows - 1)) / rows)
		for i, slot in ipairs(E.Slots) do
			local tile = page.SlotTiles[slot]
			local c = (i - 1) % cols
			local r = math.floor((i - 1) / cols)
			tile.Button.Position = UDim2.fromOffset(4 + c * (tw + 6), 4 + titleH + r * (th + 6))
			tile.Button.Size = UDim2.fromOffset(tw, th)
			tile.Layout(tw, th)
		end
	else
		local buttonW = landscape and (stripW - 16) or (phone and 140 or 170)
		if landscape then
			page.StripText.Position = UDim2.fromOffset(8, 6)
			page.StripText.Size = UDim2.new(1, -16, 1, -(6 + 52))
			page.Manage.Instance.Position = UDim2.new(0, 8, 1, -50)
			page.Manage.Instance.Size = UDim2.fromOffset(buttonW, 42)
		else
			page.StripText.Position = UDim2.fromOffset(10, 4)
			page.StripText.Size = UDim2.new(1, -(buttonW + 30), 1, -8)
			page.Manage.Instance.Position = UDim2.new(1, -(buttonW + 8), 0.5, -21)
			page.Manage.Instance.Size = UDim2.fromOffset(buttonW, 42)
		end
	end
	-- Toolbar: [kind chips][sort][salvage] / [rarity chips]; one row on landscape phones.
	local sortW = phone and 130 or 176
	local selectW = phone and 96 or 120
	page.KindChips.Instance.Position = UDim2.fromOffset(gridX, top)
	page.KindChips.Instance.Size = UDim2.fromOffset(math.max(60, gridW - sortW - selectW - 12), rowH)
	page.Sort.Instance.Position = UDim2.fromOffset(gridX + gridW - sortW - selectW - 6, top)
	page.Sort.Instance.Size = UDim2.fromOffset(sortW, rowH)
	page.SelectButton.Instance.Position = UDim2.fromOffset(gridX + gridW - selectW, top)
	page.SelectButton.Instance.Size = UDim2.fromOffset(selectW, rowH)
	top += rowH + 4
	page.RarityChips.Instance.Visible = not landscape
	if not landscape then
		page.RarityChips.Instance.Position = UDim2.fromOffset(gridX, top)
		page.RarityChips.Instance.Size = UDim2.fromOffset(gridW, rowH)
		top += rowH + 4
	end
	page.Grid.Instance.Position = UDim2.fromOffset(gridX, top)
	page.Grid.Instance.Size = UDim2.fromOffset(gridW, math.max(40, contentH - top - (barH > 0 and barH + 6 or 0)))
	page.Bar.Visible = barH > 0
	page.Bar.Position = UDim2.fromOffset(gridX, contentH - barH)
	page.Bar.Size = UDim2.fromOffset(gridW, math.max(1, barH))
	if barTwoRows then
		-- Summary across the top, the three buttons share the row under it.
		local w3 = math.floor((gridW - 32) / 3)
		for i, button in ipairs({ page.BarCancel, page.BarAll, page.BarGo }) do
			button.Instance.Position = UDim2.new(0, 8 + (i - 1) * (w3 + 8), 1, -50)
			button.Instance.Size = UDim2.fromOffset(w3, 42)
		end
		page.BarText.Position = UDim2.fromOffset(10, 6)
		page.BarText.Size = UDim2.new(1, -20, 1, -62)
	else
		page.BarCancel.Instance.Position = UDim2.new(1, -(bw * 3 + 24), 0.5, -21)
		page.BarCancel.Instance.Size = UDim2.fromOffset(bw, 42)
		page.BarAll.Instance.Position = UDim2.new(1, -(bw * 2 + 16), 0.5, -21)
		page.BarAll.Instance.Size = UDim2.fromOffset(bw, 42)
		page.BarGo.Instance.Position = UDim2.new(1, -(bw + 8), 0.5, -21)
		page.BarGo.Instance.Size = UDim2.fromOffset(bw, 42)
		page.BarText.Position = UDim2.fromOffset(10, 4)
		page.BarText.Size = UDim2.new(1, -(bw * 3 + 40), 1, -8)
	end
end

------------------------------------------------------------------------------------------------
-- Data -> UI
------------------------------------------------------------------------------------------------
local function filtered(page: any, data: any): { any }
	local filter = M.State.Filter[page.Id]
	local list = page.Kind == "Artifact" and data.Artifacts or data.Accessories
	local out = {}
	local anyRarity = next(filter.Rarities) ~= nil
	for _, entry in ipairs(list or {}) do
		local def = E.Def(entry.Id)
		if def then
			local ok = not anyRarity or filter.Rarities[entry.Rarity]
			if ok and filter.Kind ~= "All" then
				ok = (page.Kind == "Accessory" and def.Slot == filter.Kind) or (page.Kind == "Artifact" and def.Stat == filter.Kind)
			end
			if ok then
				table.insert(out, entry)
			end
		end
	end
	local sort, desc = filter.Sort, filter.Desc
	table.sort(out, function(a, b)
		local ka, kb
		if sort == "value" then
			ka, kb = a.Value or 0, b.Value or 0
		elseif sort == "new" then
			ka, kb = a.CreatedAt or 0, b.CreatedAt or 0
		else
			ka, kb = E.RarityIndex[a.Rarity] or 0, E.RarityIndex[b.Rarity] or 0
		end
		if ka ~= kb then
			if desc then
				return ka > kb
			end
			return ka < kb
		end
		if (a.Value or 0) ~= (b.Value or 0) then
			return (a.Value or 0) > (b.Value or 0)
		end
		return tostring(a.Uid) < tostring(b.Uid)
	end)
	return out
end

local function bonusSummary(totals: any, stats: { string }): string
	local parts = {}
	for _, stat in ipairs(stats) do
		if (totals[stat] or 0) > 0 then
			table.insert(parts, Shared.StatLine(stat, totals[stat]))
		end
	end
	return table.concat(parts, "\n")
end

-- Re-renders both pages from a snapshot (default: the cached one). opts: ResetScroll.
function M.Refresh(snapshot: any?, opts: any?)
	if not M.Window then
		return
	end
	snapshot = snapshot or snapshotNow()
	local data = Shared.Data(snapshot)
	local profile = snapshot and snapshot.Profile
	if not data or type(profile) ~= "table" then
		return
	end
	M.Data = data
	-- NEW marks: pieces that appeared while the shop is open.
	local known = M.State.Known
	local seenNow = {}
	for _, list in ipairs({ data.Artifacts or {}, data.Accessories or {} }) do
		for _, entry in ipairs(list) do
			seenNow[entry.Uid] = true
			if known and not known[entry.Uid] then
				M.State.New[entry.Uid] = true
			end
		end
	end
	M.State.Known = seenNow
	for uid in pairs(M.State.Selected) do
		if not seenNow[uid] then
			M.State.Selected[uid] = nil
		end
	end
	local names = {}
	for uid, dog in pairs(profile.Dogs or {}) do
		names[uid] = Shared.DogName(dog)
	end
	M.DogNames = names
	for tabId, page in pairs(M.UI.Pages) do
		local rowsById = {}
		for _, row in ipairs(data.Cases or {}) do
			rowsById[row.Id] = row
		end
		for caseId, card in pairs(page.Cards) do
			card.Update(rowsById[caseId], profile, data)
		end
		local items = filtered(page, data)
		page.Grid:SetItems(items, { ResetScroll = opts and opts.ResetScroll })
		page.Items = items
		local count = bagCount(data, page.Kind)
		local capacity = data.Capacity and data.Capacity[page.Kind] or 0
		M.Window:SetBadge(tabId, count > 0 and tostring(count) or nil)
		local segment = page.Segment
		local bagEntry = segment.Entries and segment.Entries.bag
		if bagEntry then
			bagEntry.Caption.Text = W("BAG") .. " " .. count .. "/" .. capacity
		end
		if page.Kind == "Accessory" then
			local worn = AccessoryTotals.Equipped(profile)
			for slot, tile in pairs(page.SlotTiles) do
				local raw = worn[slot]
				local entry = raw and Shared.Find(data, raw.Uid)
				tile.Entry = entry
				if entry then
					local def = E.Def(entry.Id)
					tile.Preview:Show({ Kind = "Equipment", Id = entry.Id })
					tile.Empty.Visible = false
					tile.Stat.Text = def and Shared.StatLine(def.Stat, entry.Value or 0) or ""
					tile.Stroke.Color = Shared.RarityColor(entry.Rarity)
					tile.Stroke.Transparency = 0
				else
					tile.Preview:Show(nil)
					tile.Empty.Visible = true
					tile.Stat.Text = W("EMPTY")
					tile.Stroke.Color = Kit.Theme.Colors.edge
					tile.Stroke.Transparency = 0.4
				end
			end
			local text = bonusSummary(AccessoryTotals.Totals(profile), E.AccessoryStats)
			page.BannerStat.Text = text ~= "" and text or T("Nothing worn yet", "Пока ничего не надето")
		else
			local onDogs, dogs = 0, {}
			for _, entry in ipairs(data.Artifacts or {}) do
				if entry.DogUid then
					onDogs += 1
					dogs[entry.DogUid] = true
				end
			end
			local dogCount = 0
			for _ in pairs(dogs) do
				dogCount += 1
			end
			page.StripText.Text = T("On your dogs: ", "На собаках: ") .. onDogs .. T(" (", " (") .. dogCount .. T(" dogs) · In the bag: ", " соб.) · В сумке: ") .. (count - onDogs)
				.. "\n" .. T("Equip from a dog's page or tap an artifact.", "Надевай со страницы собаки или нажми на артефакт.")
			page.BannerStat.Text = T("ON DOGS: ", "НА СОБАКАХ: ") .. onDogs .. "\n" .. T("IN BAG: ", "В СУМКЕ: ") .. (count - onDogs) .. "/" .. capacity
		end
		M.UpdateBar(page)
	end
	if data.PaidKnown == false and not M.PolicyRetry then
		M.PolicyRetry = true
		task.delay(2, function()
			M.PolicyRetry = nil
			if M.Window and M.Window.IsOpen then
				local fresh = Net.Snapshot(0)
				if fresh then
					M.Refresh(fresh)
				end
			end
		end)
	end
	if M.Window.Layout then
		M.Relayout(M.Window.Layout)
	end
end

function M.Relayout(l: any)
	for _, page in pairs(M.UI.Pages) do
		layoutPage(page, l)
	end
end

function M.SetSegment(tabId: string, segment: string)
	M.State.Segment[tabId] = segment
	local page = M.UI.Pages[tabId]
	if page and page.Segment.Value ~= segment then
		page.Segment:SetSelected(segment, true)
	end
	if M.Window and M.Window.Layout then
		M.Relayout(M.Window.Layout)
	end
end

------------------------------------------------------------------------------------------------
-- Salvage mode
------------------------------------------------------------------------------------------------
local function selectedList(): ({ string }, number)
	local uids, bones = {}, 0
	local data = M.Data
	for uid in pairs(M.State.Selected) do
		local entry = Shared.Find(data, uid)
		if entry then
			table.insert(uids, uid)
			bones += E.Salvage[entry.Rarity] or 0
		end
	end
	table.sort(uids)
	return uids, bones
end

function M.UpdateBar(page: any)
	local uids, bones = selectedList()
	page.BarText.Text = #uids .. T(" selected · +", " выбрано · +") .. bones .. T(" BONES", " КОСТЕЙ")
	page.BarGo:SetDisabled(#uids == 0)
	page.SelectButton:SetText(M.State.Selecting and W("CANCEL") or W("SALVAGE"))
	page.SelectButton:SetStyle(M.State.Selecting and "danger" or "secondary")
end

function M.SetSelecting(on: boolean)
	M.State.Selecting = on
	M.State.Selected = {}
	for _, page in pairs(M.UI.Pages) do
		page.Grid:Refresh()
		M.UpdateBar(page)
	end
	if M.Window and M.Window.Layout then
		M.Relayout(M.Window.Layout)
	end
end

function M.ToggleSelect(entry: any, card: any?)
	local uid = entry.Uid
	if M.State.Selected[uid] then
		M.State.Selected[uid] = nil
	else
		if #(selectedList()) >= E.MaxSalvageBatch then
			Kit.Toast(T("You can salvage up to ", "Можно разобрать до ") .. E.MaxSalvageBatch .. T(" pieces at once.", " предметов за раз."), { Kind = "warn", NoTranslate = true })
			return
		end
		M.State.Selected[uid] = true
	end
	for _, page in pairs(M.UI.Pages) do
		page.Grid:RefreshKey(uid)
		M.UpdateBar(page)
	end
	if card and card.Pulse then
		card:Pulse()
	end
end

-- Selects every shown piece that can be salvaged (unlocked, not equipped), up to the batch size.
function M.SelectShown(tabId: string)
	local page = M.UI.Pages[tabId]
	if not page then
		return
	end
	local count = #(selectedList())
	for _, entry in ipairs(page.Items or {}) do
		if count >= E.MaxSalvageBatch then
			break
		end
		if not entry.Locked and not entry.DogUid and not entry.Slot and not M.State.Selected[entry.Uid] then
			M.State.Selected[entry.Uid] = true
			count += 1
		end
	end
	page.Grid:Refresh()
	M.UpdateBar(page)
end

function M.SalvageSelected()
	local uids, bones = selectedList()
	if #uids == 0 then
		return
	end
	local cards = {}
	for _, uid in ipairs(uids) do
		local entry = Shared.Find(M.Data, uid)
		if entry then
			table.insert(cards, Shared.Card(entry))
		end
	end
	local ok = Kit.Confirm(T("SALVAGE ", "РАЗОБРАТЬ ") .. #uids .. T(" PIECES?", " ПРЕДМ.?"), T("They are gone for good. You get ", "Они исчезнут навсегда. Ты получишь ") .. bones .. T(" Bones.", " костей."), {
		NoTranslate = true,
		Danger = true,
		Cards = cards,
		CardKind = "Item",
		ConfirmText = W("SALVAGE") .. " +" .. bones,
		CancelText = W("CANCEL"),
	}):Await()
	if not ok then
		return
	end
	local done = Shared.Request("SalvageEquipment", { Uids = uids }, {
		Success = T("Salvaged for ", "Разобрано: +") .. bones .. T(" Bones", " костей"),
	})
	if done then
		M.SetSelecting(false)
	end
end

------------------------------------------------------------------------------------------------
-- Details of one piece
------------------------------------------------------------------------------------------------
function M.ShowPiece(entry: any)
	local data = M.Data or dataNow()
	entry = Shared.Find(data, entry.Uid) or entry
	local def = E.Def(entry.Id)
	if not def then
		return
	end
	local kind = def.Kind
	local accent = kind == "Artifact" and Shared.Colors.Artifact or Shared.Colors.Accessory
	local snapshot = snapshotNow()
	local profile = snapshot and snapshot.Profile
	-- Primary action and the line that explains it.
	local confirmText, note, action
	if kind == "Accessory" then
		if entry.Slot then
			confirmText, action = W("TAKE_OFF"), "unequip"
		else
			confirmText, action = W("WEAR"), "equip"
			local worn = profile and AccessoryTotals.Equipped(profile)[def.Slot]
			if worn then
				local wornDef = E.Def(worn.Id)
				note = T("Replaces ", "Заменит ") .. Shared.Name(wornDef) .. T(" (it goes back to your bag).", " (он вернётся в сумку).")
				confirmText = T("WEAR · SWAP", "НАДЕТЬ · ЗАМЕНИТЬ")
			end
		end
	else
		if entry.DogUid then
			confirmText, action = W("TAKE_OFF"), "unequip"
			local dog = Shared.Dog(snapshot, entry.DogUid)
			note = T("On ", "На собаке ") .. Shared.DogName(dog) .. T(", slot ", ", слот ") .. tostring(entry.Slot) .. "."
		else
			confirmText, action = W("EQUIP_DOG"), "dog"
		end
	end
	local _, _, _, sh = require(script.Parent.Parent.Kit.Base).SafeArea(Kit.Overlay.Modals())
	local short = sh < 420
	local contentH = short and math.max(110, sh - 24 - 150) or 300
	local modal
	modal = Kit.Modal({
		Title = Shared.Name(def),
		NoTranslate = true,
		Accent = accent,
		ConfirmText = confirmText,
		ConfirmStyle = action == "unequip" and "secondary" or "success",
		CancelText = W("CLOSE"),
		Width = short and 640 or 520,
		ContentHeight = contentH,
		Content = function(frame, width)
			local zz = frame.ZIndex
			local viewS = short and math.max(60, contentH - 50) or 140
			local band = Kit.New("Frame", { Name = "Band", BackgroundColor3 = Kit.Theme.White, BorderSizePixel = 0, Size = UDim2.fromOffset(viewS + 8, viewS + 8), ZIndex = zz }, frame)
			Kit.Corner(band, 14)
			local top, bottom = Shared.RarityColor(entry.Rarity), Shared.RarityColor(entry.Rarity)
			local g = Kit.Theme.RarityGradient[entry.Rarity]
			if g then
				top, bottom = g[1], g[2]
			end
			Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(top:Lerp(Kit.Theme.White, 0.6), bottom:Lerp(Kit.Theme.White, 0.2)) }, band)
			local holder = Kit.New("Frame", { Name = "View", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(viewS, viewS), ZIndex = zz + 1 }, band)
			local view = Shared.Visuals.Viewport(holder, { Id = entry.Id })
			view.ZIndex = zz + 1
			local x = viewS + 18
			local textW = width - x
			local tags = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(textW, 24), ZIndex = zz }, frame)
			Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, tags)
			local rarity = Kit.Pill(tags, { Text = Shared.Rarity(entry.Rarity), Color = Shared.RarityColor(entry.Rarity), Height = 22, TextSize = 13, LayoutOrder = 1, ZIndex = zz + 1, NoTranslate = true })
			if g then
				rarity:SetGradient(g[1], g[2])
			end
			if kind == "Accessory" then
				Kit.Pill(tags, { Text = Shared.SlotName(def.Slot), Color = Kit.Theme.Colors.edge, Height = 22, TextSize = 13, LayoutOrder = 2, ZIndex = zz + 1, NoTranslate = true })
			end
			if entry.Locked then
				Kit.Pill(tags, { Text = "🔒 " .. W("LOCKED"), Color = Kit.Theme.Colors.gold, Height = 22, TextSize = 13, LayoutOrder = 3, ZIndex = zz + 1, NoTranslate = true })
			end
			Kit.Text(frame, { Name = "Stat", Text = Shared.StatLine(def.Stat, entry.Value or E.Value(entry)), TextSize = 24, Scaled = true, MinTextSize = 12, Font = "numeric",
				Color = Shared.StatColor(def.Stat):Lerp(Kit.Theme.Ink, 0.3), Position = UDim2.fromOffset(x, 28), Size = UDim2.fromOffset(textW, 30), ZIndex = zz, NoTranslate = true })
			Kit.Pill(frame, { Name = "Scope", Text = Shared.Scope(kind), Color = accent, Height = 24, TextSize = 13, Position = UDim2.fromOffset(x, 62), ZIndex = zz, NoTranslate = true })
			Kit.Text(frame, { Name = "Help", Text = Shared.Help(def.Stat, kind) .. (note and ("\n" .. note) or ""), TextSize = 14, Wrap = true, AlignY = "Top", Color = Kit.Theme.InkMuted,
				Position = UDim2.fromOffset(x, 92), Size = UDim2.fromOffset(textW, short and math.max(18, contentH - 92 - 30) or 56), ZIndex = zz, NoTranslate = true })
			local bar = Kit.ProgressBar(frame, { Name = "Quality", Value = math.clamp(entry.Roll or 0, 0.03, 1), Text = Shared.Quality(entry.Roll or 0) .. "  (" .. E.Format(def.Min) .. " – " .. E.Format(def.Max):sub(2) .. ")",
				Color = Shared.RarityColor(entry.Rarity), Height = 20, TextSize = 12, ZIndex = zz, NoTranslate = true })
			bar.Instance.Position = short and UDim2.fromOffset(x, contentH - 24) or UDim2.fromOffset(0, viewS + 18)
			bar.Instance.Size = UDim2.fromOffset(short and textW or width, 20)
			if entry.PaidRandom and not short then
				Kit.Text(frame, { Name = "Paid", Text = T("From a Robux key", "Из ключа за Robux"), TextSize = 12, Color = Kit.Theme.InkMuted, Position = UDim2.fromOffset(0, viewS + 40), Size = UDim2.fromOffset(width, 16), ZIndex = zz, NoTranslate = true })
			end
			-- Lock and salvage (secondary actions). Short screens: lock under the preview only
			-- (salvage from the bag's SALVAGE mode there).
			local rowY = short and (viewS + 12) or (contentH - 46)
			local bw = short and viewS + 8 or math.floor((width - 10) / 2)
			local lock = Kit.Button(frame, { Name = "Lock", Text = entry.Locked and W("UNLOCK") or ("🔒 " .. W("LOCK")), Style = "secondary", TextSize = 14, ZIndex = zz + 1, NoTranslate = true,
				Position = UDim2.fromOffset(0, rowY), Size = UDim2.fromOffset(bw, short and 38 or 42), OnClick = function()
					modal:Cancel()
					Shared.Request("LockEquipment", { Uid = entry.Uid, Enabled = not entry.Locked }, {
						Success = entry.Locked and T("Unlocked: it can be salvaged again", "Защита снята") or T("Locked: it cannot be salvaged", "Защищено: его нельзя разобрать"),
					})
				end })
			local _ = lock
			if not short then
				local equipped = entry.DogUid ~= nil or entry.Slot ~= nil
				local salvage = Kit.Button(frame, { Name = "Salvage", Text = W("SALVAGE") .. " +" .. (E.Salvage[entry.Rarity] or 0), Style = "danger", TextSize = 14, ZIndex = zz + 1, NoTranslate = true,
					Position = UDim2.fromOffset(bw + 10, rowY), Size = UDim2.fromOffset(bw, 42), Disabled = entry.Locked == true or equipped, OnClick = function()
						modal:Cancel()
						M.SalvageOne(entry)
					end })
				local _ = salvage
			end
		end,
	})
	M.Detail = modal
	modal:Then(function(confirmed)
		if M.Detail == modal then
			M.Detail = nil
		end
		if not confirmed then
			return
		end
		if action == "equip" then
			Shared.Request("EquipAccessory", { Uid = entry.Uid }, { Success = Shared.Name(def) .. T(" is on: everyone can see it", " надето: его видят все") })
		elseif action == "unequip" then
			if kind == "Accessory" then
				Shared.Request("UnequipAccessory", { Slot = def.Slot }, { Success = Shared.Name(def) .. T(" is back in your bag", " снова в сумке") })
			else
				Shared.Request("UnequipArtifact", { Uid = entry.Uid }, { Success = Shared.Name(def) .. T(" is back in your bag", " снова в сумке") })
			end
		elseif action == "dog" then
			ArtifactPanel.PickDog(entry.Uid)
		end
	end)
	return modal
end

function M.SalvageOne(entry: any)
	local def = E.Def(entry.Id)
	local bones = E.Salvage[entry.Rarity] or 0
	local ok = Kit.Confirm(T("SALVAGE ", "РАЗОБРАТЬ ") .. Shared.Name(def) .. "?", T("It is gone for good. You get ", "Он исчезнет навсегда. Ты получишь ") .. bones .. T(" Bones.", " костей."), {
		NoTranslate = true,
		Danger = true,
		Cards = { Shared.Card(entry) },
		CardKind = "Item",
		ConfirmText = W("SALVAGE") .. " +" .. bones,
		CancelText = W("CANCEL"),
	}):Await()
	if ok then
		Shared.Request("SalvageEquipment", { Uids = { entry.Uid } }, { Success = T("Salvaged for ", "Разобрано: +") .. bones .. T(" Bones", " костей") })
	end
end

-- Browse a dog's artifacts from the shop.
function M.ManageDog()
	local snapshot = snapshotNow()
	local profile = snapshot and snapshot.Profile
	if not profile or next(profile.Dogs or {}) == nil then
		Kit.Toast(T("You have no dogs yet.", "У тебя пока нет собак."), { Kind = "info", NoTranslate = true })
		return
	end
	-- The dog picker without an artifact opens the chosen dog's panel.
	ArtifactPanel.PickDog(nil)
end

------------------------------------------------------------------------------------------------
-- Opening cases and buying keys
------------------------------------------------------------------------------------------------
local function againSpec(caseId: string, pay: string): any
	local row = caseRow(caseId)
	local data = dataNow()
	local snapshot = snapshotNow()
	local profile = snapshot and snapshot.Profile
	if not row or not data or not profile then
		return nil
	end
	local case = E.CaseById[caseId]
	local full = bagCount(data, case.Kind) >= (data.Capacity and data.Capacity[case.Kind] or math.huge)
	if pay == "Cash" then
		return { Text = W("AGAIN"), Price = row.Cash, Disabled = full or (profile.Cash or 0) < (row.Cash or 0) }
	elseif pay == "Bones" then
		return { Text = W("AGAIN"), PriceText = (row.Bones or 0) .. " " .. T("BONES", "КОСТЕЙ"), Style = "gold", Disabled = full or (profile.Bones or 0) < (row.Bones or 0) }
	end
	local credits = (row.Credits.Free or 0) + (row.Credits.Paid or 0)
	if credits <= 0 then
		return nil
	end
	return { Text = W("AGAIN"), PriceText = credits .. " " .. W("KEYS"), Style = "success", Disabled = full }
end

-- Opens one case. fromAgain: called from the reveal's OPEN AGAIN.
function M.OpenCase(caseId: string, pay: string, button: any?, fromAgain: boolean?)
	if M.Opening then
		return
	end
	local case = E.CaseById[caseId]
	local row = caseRow(caseId)
	local data = dataNow()
	local snapshot = snapshotNow()
	local profile = snapshot and snapshot.Profile
	if not case or not row or not data or not profile then
		return
	end
	local function refuse(text: string)
		Kit.Toast(text, { Kind = "warn", NoTranslate = true })
		if fromAgain then
			CaseOpening.AgainDone()
		end
	end
	if bagCount(data, case.Kind) >= (data.Capacity and data.Capacity[case.Kind] or math.huge) then
		return refuse(T("Your bag is full: salvage pieces you do not need first.", "Сумка полна: сначала разбери ненужные предметы."))
	end
	if pay == "Cash" and (profile.Cash or 0) < (row.Cash or 0) then
		return refuse(T("Not enough Coins for ", "Не хватает монет на ") .. Shared.CaseName(case))
	elseif pay == "Bones" and (profile.Bones or 0) < (row.Bones or 0) then
		return refuse(T("Not enough Bones for ", "Не хватает костей на ") .. Shared.CaseName(case))
	elseif pay == "Credit" then
		local credits = (row.Credits.Free or 0) + (row.Credits.Paid or 0)
		if credits <= 0 then
			return refuse(T("You have no keys for this case.", "У тебя нет ключей от этого кейса."))
		end
		if (row.Credits.Free or 0) <= 0 and data.PaidAllowed ~= true then
			return refuse(T("Paid random items are unavailable for this account; your keys are kept.", "Платные случайные предметы недоступны для этого аккаунта; ключи сохранены."))
		end
	end
	M.Opening = true
	local ok, result = Shared.Request("EquipmentOpenCase", { Case = caseId, Pay = pay, Quote = pay == "Cash" and row.Cash or nil }, { Button = button, Quiet = true })
	M.Opening = false
	if not ok or type(result) ~= "table" or type(result.Opened) ~= "table" then
		if fromAgain then
			CaseOpening.AgainDone()
		end
		return
	end
	local opened = result.Opened
	-- The shop was closed while the request ran: no overlay over the game, just say what came out.
	if not (M.Window and M.Window.IsOpen) then
		local def = E.Def(opened.Id)
		Kit.Toast(T("You got ", "Тебе выпало: ") .. Shared.Name(def) .. " (" .. Shared.Rarity(opened.Rarity) .. ")", { Kind = "success", NoTranslate = true })
		return
	end
	local action
	if opened.Kind == "Accessory" then
		action = { Text = W("WEAR"), Style = "secondary" }
	else
		action = { Text = W("EQUIP_DOG"), Style = "secondary" }
	end
	CaseOpening.Play(result, {
		Again = againSpec(caseId, pay),
		OnAgain = function()
			M.OpenCase(caseId, pay, nil, true)
		end,
		Action = action,
		OnAction = function(piece)
			if piece.Kind == "Accessory" then
				local def = E.Def(piece.Id)
				Shared.Request("EquipAccessory", { Uid = piece.Uid }, { Success = Shared.Name(def) .. T(" is on: everyone can see it", " надето: его видят все") })
			else
				ArtifactPanel.PickDog(piece.Uid)
			end
		end,
		OnClose = function()
			M.Refresh()
		end,
	})
end

function M.BuyKey(caseId: string, productKey: string)
	local row = caseRow(caseId)
	local data = dataNow()
	if not row or not data then
		return
	end
	if data.PaidAllowed ~= true then
		Kit.Toast(data.PaidKnown == false and T("Checking availability… try again in a moment.", "Проверяем доступность… попробуй через секунду.")
			or T("Paid random items are unavailable for this account.", "Платные случайные предметы недоступны для этого аккаунта."), { Kind = "warn", NoTranslate = true })
		return
	end
	local live
	for _, p in ipairs(row.Products or {}) do
		if p.Key == productKey then
			live = p
		end
	end
	if not live then
		Kit.Toast(T("This offer is not on sale.", "Это предложение не продаётся."), { Kind = "warn", NoTranslate = true })
		return
	end
	-- Odds are shown before every Robux purchase; the purchase prompt follows their confirm.
	local modal = Shared.ShowOdds(row, { Buy = W("BUY_KEY") .. " · " .. Shared.RobuxPrice(live) })
	if modal then
		modal:Then(function(confirmed)
			if confirmed then
				Shared.PromptRobux(live)
			end
		end)
	end
end

------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------
local function build()
	if M.Window then
		return M.Window
	end
	local win = Kit.Window.new({
		Key = "Equipment",
		Name = "EquipmentShop",
		Title = W("SHOP"),
		Subtitle = T("Accessories boost YOU · Artifacts boost ONE DOG", "Аксессуары усиливают ТЕБЯ · Артефакты — ОДНУ СОБАКУ"),
		Accent = Shared.Colors.Accessory,
		Icon = "Shop",
		Tabs = {
			{ Id = "accessories", Text = "★ " .. W("ACCESSORIES"), NoTranslate = true },
			{ Id = "artifacts", Text = "🐾 " .. W("ARTIFACTS"), NoTranslate = true },
		},
		Tab = M.State.Tab,
		MaxSize = Vector2.new(1180, 820),
		NoTranslate = true,
		OnClose = function()
			if CaseOpening.IsOpen() then
				CaseOpening.Close()
			end
			M.State.New = {}
			M.State.Known = nil
			if M.State.Selecting then
				M.SetSelecting(false)
			end
		end,
	})
	M.Window = win
	for tabId in pairs(TABS) do
		buildPage(tabId)
	end
	win.Resized:Connect(function(l)
		M.Relayout(l)
	end)
	win.TabChanged:Connect(function(id)
		M.State.Tab = id
		local info = TABS[id]
		if info then
			win:SetAccent(info.Accent)
		end
		if M.State.Selecting then
			M.SetSelecting(false)
		end
	end)
	win.Maid:Give(Net.Changed:Connect(function(snapshot)
		if win.IsOpen then
			M.Refresh(snapshot)
		end
	end))
	win.Maid:Give(Net.OnPush("EquipmentCredits", function(info)
		local fresh = Net.Snapshot(0)
		if fresh and win.IsOpen then
			M.Refresh(fresh)
		end
		local case = type(info) == "table" and E.CaseById[info.Case]
		if case then
			Kit.Toast(T("Keys added: ", "Ключи добавлены: ") .. Shared.CaseName(case), { Kind = "success", NoTranslate = true })
		end
	end))
	win.Maid:Give(Marketplace.PromptProductPurchaseFinished:Connect(function(userId, _productId, purchased)
		if purchased and userId == Players.LocalPlayer.UserId then
			task.delay(2, function()
				local fresh = Net.Snapshot(0)
				if fresh and win.IsOpen then
					M.Refresh(fresh)
				end
			end)
		end
	end))
	M.Relayout(win:GetLayout())
	return win
end

-- Opens the shop ("accessories" | "artifacts", default the last tab).
function M.Open(tab: string?)
	local win = build()
	if tab == "Artifact" or tab == "artifacts" then
		tab = "artifacts"
	elseif tab == "Accessory" or tab == "accessories" then
		tab = "accessories"
	else
		tab = nil
	end
	if tab and win.Tab ~= tab then
		win:SetTab(tab)
	end
	win:Open()
	M.Refresh(Net.Cached())
	task.spawn(function()
		local snapshot = Net.Snapshot(2)
		if snapshot and win.IsOpen then
			M.Refresh(snapshot)
		end
	end)
	return win
end

function M.Close()
	if M.Window then
		M.Window:Close("close")
	end
end

return M
