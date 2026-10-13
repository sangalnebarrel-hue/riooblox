-- PLOT DECOR window (UI kit window Key = "Decor"; docs/PLOT_COSMETICS.md).
--   Left (desktop) / top (phones): every decor spot of the yard (BIG 1-4, SMALL 1-16) with what
--   stands there. Right: category tabs (only the categories that fit the chosen spot), decoration
--   cards with a 3D preview (Kit.Preview kind "Decor"), price chips (coins + 🪨 Stone, 🦴 Bones
--   on Mythic pieces) and owned counts. The bar below acts on the chosen decoration and spot:
--   BUY & PLACE, PLACE, BUY (no spot chosen) and REMOVE.
-- Entry points: the DECORATE prompt of a spot (StarterPlayerScripts.PlotCosmetics) opens it on that
-- spot, the yard page DECORATE button and N.OpenPage('Decor') open it on ALL SPOTS.
-- Data: Snapshot.Features.Decor (Features.Decor), Profile.Cash / Bones, player attribute Stone.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Economy = RS:WaitForChild("DogEconomy")
local Catalog = require(Economy:WaitForChild("DecorCatalog"))
local Dict = require(RS:WaitForChild("Localization"):WaitForChild("Plot"))
local Theme, Format = Kit.Theme, Kit.Format
local P = Theme.Colors
local ACCENT = Color3.fromRGB(64, 186, 120)
local STONE = Color3.fromRGB(176, 170, 160)
local Z = 3
local player = Players.LocalPlayer

local S = {}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function ru(): boolean
	return Kit.Lang() == "ru"
end
local function T(en: string, ruText: string?): string
	return Kit.T(en, ruText or Dict.Exact[en] or en)
end
local function said(text: any): string
	text = tostring(text or "")
	if not ru() then
		return text
	end
	local exact = Dict.Exact[text]
	if exact then
		return exact
	end
	for _, rule in ipairs(Dict.Patterns) do
		local out, n = string.gsub(text, rule[1], rule[2])
		if n > 0 then
			return out
		end
	end
	return text
end
local function short(n: any): string
	return Format.Short(tonumber(n) or 0, 1)
end
local function itemName(item: any): string
	return Catalog.ItemName(item, ru())
end
local function slotName(slot: any): string
	return Catalog.SlotName(slot, ru())
end
local function priceText(item: any): string
	local cash, stone, bones = Catalog.Price(item.Id)
	local text = "💰 " .. short(cash) .. "  🪨 " .. Format.Number(stone)
	if bones > 0 then
		text ..= "  🦴 " .. Format.Number(bones)
	end
	return text
end

------------------------------------------------------------------------------------------------
-- 3D previews of decorations (Kit.Preview kind "Decor")
------------------------------------------------------------------------------------------------
local models: any = nil
local function decorModels(): any
	if models == nil then
		local folder = RS:FindFirstChild("Decor")
		local module = folder and folder:FindFirstChild("DecorModels")
		local ok, result = pcall(function()
			return require(module :: any)
		end)
		models = ok and result or false
	end
	return models or nil
end
Kit.Preview.Register("Decor", function(spec: any, parent: Instance)
	local view = Instance.new("ViewportFrame")
	view.Name = "DecorPreview"
	view.BackgroundTransparency = 1
	view.Size = UDim2.fromOffset(Kit.Preview.BuildSize, Kit.Preview.BuildSize)
	view.Ambient = Color3.fromRGB(170, 175, 190)
	view.LightColor = Color3.fromRGB(255, 250, 240)
	view.LightDirection = Vector3.new(-0.6, -1, -0.4)
	view.Parent = parent
	local M = decorModels()
	local model = M and M.Get(spec.DecorId)
	if not model then
		return view
	end
	model.Parent = view
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local radius = size.Magnitude * 0.5
	local distance = radius / math.sin(math.rad(15)) * 1.02
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-0.62, 0.48, -1).Unit * distance, cf.Position)
	camera.Parent = view
	view.CurrentCamera = camera
	return view
end, function(spec: any)
	return tostring(spec.DecorId)
end)

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st: any = {
	Snapshot = nil,
	Slot = nil, -- selected slot id, nil = ALL SPOTS
	Category = Catalog.Categories[1].Id,
	Item = nil, -- selected decoration id
	Busy = false,
}
S.State = st
local win: any = nil
local ui: any = nil
local relayout: () -> ()
local refresh: (snapshot: any?) -> ()

local function decor(): any
	local features = st.Snapshot and st.Snapshot.Features
	return type(features) == "table" and features.Decor or nil
end
local function profile(): any
	return st.Snapshot and st.Snapshot.Profile or nil
end
local function owned(id: string): number
	local d = decor()
	return d and type(d.Owned) == "table" and tonumber(d.Owned[id]) or 0
end
local function free(id: string): number
	local d = decor()
	return d and type(d.Free) == "table" and tonumber(d.Free[id]) or 0
end
local function placedAt(slotId: string): string?
	local d = decor()
	local id = d and type(d.Placed) == "table" and d.Placed[slotId] or nil
	return type(id) == "string" and id or nil
end
local function stage(): number
	local d = decor()
	return d and tonumber(d.Stage) or 1
end
local function wallet(): (number, number, number)
	local p = profile()
	local stone = player:GetAttribute("Stone")
	if type(stone) ~= "number" then
		local d = decor()
		stone = d and tonumber(d.Stone) or 0
	end
	return p and tonumber(p.Cash) or 0, stone :: number, p and tonumber(p.Bones) or 0
end
local function selectedSlot(): any
	return st.Slot and Catalog.Slot(st.Slot) or nil
end
local function categoriesFor(slot: any): { any }
	local list = {}
	for _, c in ipairs(Catalog.Categories) do
		if not slot or c.Size == slot.Size then
			table.insert(list, c)
		end
	end
	return list
end

------------------------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------------------------
local function request(action: string, args: any, button: any?, after: (() -> ())?)
	if st.Busy then
		return
	end
	st.Busy = true
	if button then
		button:SetBusy(true)
	end
	task.spawn(function()
		local ok, result = Net.Request(action, args)
		st.Busy = false
		if button then
			button:SetBusy(false)
		end
		local message = type(result) == "table" and result.Message or result
		Kit.Toast(said(message), { Kind = ok and "success" or "error", NoTranslate = true })
		if ok and not (type(result) == "table" and result.StateSnapshot) then
			Net.Snapshot(0)
		end
		if ok and after then
			after()
		end
		if win and win.IsOpen then
			refresh(Net.Cached())
		end
	end)
end

-- Expensive pieces ask first (hold to confirm for the big ones).
local function confirmBuy(item: any, andPlace: boolean): boolean
	local cash, stone = Catalog.Price(item.Id)
	if cash < 1000000 and stone < 500 then
		return true
	end
	local title = (andPlace and T("BUY & PLACE") or T("BUY")) .. " · " .. itemName(item)
	return Kit.Confirm(title, priceText(item), { Hold = cash >= 20000000 and 1 or 0, ConfirmText = andPlace and T("BUY & PLACE") or T("BUY"), NoTranslate = true }):Await()
end

function S.Buy(andPlace: boolean)
	local item = Catalog.Get(st.Item)
	if not item then
		return
	end
	local slot = andPlace and selectedSlot() or nil
	task.spawn(function()
		if not confirmBuy(item, slot ~= nil) then
			return
		end
		local cash = Catalog.Price(item.Id)
		request("DecorBuy", { Id = item.Id, Quote = cash, Slot = slot and slot.Id or nil }, ui.Primary)
	end)
end
function S.Place()
	local slot, item = selectedSlot(), Catalog.Get(st.Item)
	if slot and item then
		request("DecorPlace", { Slot = slot.Id, Id = item.Id }, ui.Primary)
	end
end
function S.Remove()
	local slot = selectedSlot()
	if slot then
		request("DecorRemove", { Slot = slot.Id }, ui.Remove)
	end
end

------------------------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------------------------
local function panel(parent: Instance, name: string, color: Color3?): any
	local frame = Kit.New("Frame", { Name = name, BackgroundColor3 = color or Theme.White, BorderSizePixel = 0, ZIndex = Z }, parent)
	Kit.Corner(frame, Theme.Radius.Card)
	Kit.Stroke(frame, P.edge, 2, 0.55)
	return frame
end
local function label(parent: Instance, props: any): any
	local p = table.clone(props)
	p.ZIndex = p.ZIndex or Z + 1
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	return Kit.Text(parent, p)
end

local function buildSlotRow(id: string?): any
	local r: any = { Id = id }
	local button = Kit.New("TextButton", { Name = id or "All", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, ui.Spots)
	Kit.Corner(button, Theme.Radius.Small)
	r.Stroke = Kit.Stroke(button, P.edge, 2, 0.6)
	r.Button = button
	r.Icon = label(button, { Name = "Icon", Text = "", TextSize = 18, AlignX = "Center", ZIndex = Z + 2 })
	r.Title = label(button, { Name = "Title", Text = "", TextSize = 14, Scaled = true, MinTextSize = 9, ZIndex = Z + 2 })
	r.Sub = label(button, { Name = "Sub", Text = "", TextSize = 12, Color = Theme.InkMuted, Scaled = true, MinTextSize = 8, ZIndex = Z + 2 })
	r.Maid = Kit.Maid.new()
	r.Maid:Give(button.Activated:Connect(function()
		S.SelectSlot(id)
	end))
	return r
end

local function build()
	if win then
		return
	end
	win = Kit.Window.new({
		Key = "Decor",
		Title = T("PLOT DECOR"),
		Subtitle = T("Make your yard one of a kind"),
		Accent = ACCENT,
		Icon = "Yard",
		NoTranslate = true,
		MaxSize = Vector2.new(1100, 780),
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			S._closed()
		end,
	})
	S.Window = win
	ui = { Rows = {}, Lang = Kit.Lang() }
	S.UI = ui
	local body = win.Body
	-- Spots list.
	ui.Spots = Kit.New("ScrollingFrame", {
		Name = "Spots",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(),
		ZIndex = Z,
	}, body)
	table.insert(ui.Rows, buildSlotRow(nil))
	for _, slot in ipairs(Catalog.Slots) do
		table.insert(ui.Rows, buildSlotRow(slot.Id))
	end
	-- Wallet line and category tabs.
	ui.Wallet = label(body, { Name = "Wallet", TextSize = 16, Font = "numeric", AlignX = "Right" })
	ui.Tabs = Kit.Tabs(body, {
		Name = "Categories",
		Tabs = {},
		Accent = ACCENT,
		TextSize = 15,
		ZIndex = Z,
		OnChange = function(id)
			st.Category = id
			S.RefreshCards(true)
		end,
	})
	ui.GridHost = Kit.New("Frame", { Name = "GridHost", BackgroundTransparency = 1, ZIndex = Z }, body)
	ui.Grid = Kit.CardGrid(ui.GridHost, {
		Name = "Decorations",
		Kind = "Item",
		CardSize = Vector2.new(156, 206),
		RowHeight = 76,
		ZIndex = Z,
		Key = function(item)
			return item.Id
		end,
		Map = function(item)
			local cash, stone, bones = Catalog.Price(item.Id)
			local haveCash, haveStone, haveBones = wallet()
			local stats = {
				{ Text = "💰 " .. short(cash), Color = haveCash < cash and Theme.Danger or nil },
				{ Text = "🪨 " .. short(stone), Color = haveStone < stone and Theme.Danger or STONE },
			}
			if bones > 0 then
				table.insert(stats, { Text = "🦴 " .. short(bones), Color = haveBones < bones and Theme.Danger or nil })
			end
			local slot = selectedSlot()
			local here = slot and placedAt(slot.Id) == item.Id
			local locked = stage() < item.Stage
			return {
				Id = item.Id,
				Name = itemName(item),
				Rarity = item.Rarity,
				Preview = { Kind = "Decor", DecorId = item.Id },
				Stats = stats,
				Count = owned(item.Id),
				Tag = ru() and Catalog.Sizes[item.Size].RU or Catalog.Sizes[item.Size].Name,
				TagColor = item.Size == "Large" and P.purple or P.blue,
				Badge = here and (ru() and "ЗДЕСЬ" or "HERE") or (locked and ((ru() and "СТАДИЯ " or "STAGE ") .. item.Stage) or nil),
				BadgeColor = here and ACCENT or Theme.Disabled,
				Selected = st.Item == item.Id,
				Locked = locked,
			}
		end,
		OnClick = function(item)
			st.Item = item.Id
			S.RefreshCards(false)
			S.RefreshBar()
		end,
		Empty = { Icon = "Yard", Title = Kit.Word("NO_RESULTS"), NoTranslate = true },
	})
	-- Action bar.
	ui.Bar = panel(body, "ActionBar", Theme.White)
	ui.BarHolder = Kit.New("Frame", { Name = "Preview", BackgroundColor3 = Color3.fromRGB(214, 236, 250), BorderSizePixel = 0, ZIndex = Z + 1 }, ui.Bar)
	Kit.Corner(ui.BarHolder, Theme.Radius.Small)
	ui.BarPreview = Kit.Preview.Slot(ui.BarHolder)
	ui.BarName = label(ui.Bar, { Name = "ItemName", TextSize = 18, Scaled = true, MinTextSize = 10 })
	ui.BarPrice = label(ui.Bar, { Name = "Price", TextSize = 15, Font = "numeric", Scaled = true, MinTextSize = 9 })
	ui.BarInfo = label(ui.Bar, { Name = "Info", TextSize = 13, Color = Theme.InkMuted, Scaled = true, MinTextSize = 8 })
	ui.Primary = Kit.Button(ui.Bar, {
		Name = "Primary",
		Text = T("BUY & PLACE"),
		Style = "success",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			S.Primary()
		end,
	})
	ui.Remove = Kit.Button(ui.Bar, {
		Name = "Remove",
		Text = T("REMOVE"),
		Style = "danger",
		TextSize = 15,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			S.Remove()
		end,
	})
	Kit.Tooltip(ui.Remove.Instance, function()
		local slot = selectedSlot()
		local id = slot and placedAt(slot.Id)
		local item = id and Catalog.Get(id)
		return item and itemName(item) or T("This spot is already empty"), T("REMOVE")
	end)
	Kit.Tooltip(ui.Primary.Instance, function()
		local item = Catalog.Get(st.Item)
		if not item then
			return T("Choose a spot on the left, then a decoration."), T("PLOT DECOR")
		end
		return priceText(item), itemName(item)
	end)
	win.Resized:Connect(function()
		relayout()
	end)
end

------------------------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------------------------
local function paintRow(r: any)
	local selected = st.Slot == r.Id
	r.Stroke.Color = selected and ACCENT or P.edge
	r.Stroke.Transparency = selected and 0 or 0.6
	r.Stroke.Thickness = selected and 3 or 2
	if not r.Id then
		r.Icon.Text = "🏡"
		r.Title.Text = T("ALL SPOTS")
		local used = 0
		for _, slot in ipairs(Catalog.Slots) do
			if placedAt(slot.Id) then
				used += 1
			end
		end
		r.Sub.Text = used .. " / " .. #Catalog.Slots
		return
	end
	local slot = Catalog.Slot(r.Id)
	local id = placedAt(r.Id)
	local item = id and Catalog.Get(id)
	r.Icon.Text = slot.Size == "Large" and "🏠" or "🌷"
	r.Title.Text = slotName(slot)
	r.Sub.Text = item and itemName(item) or T("FREE")
	r.Sub.TextColor3 = item and Theme.Ink or Theme.InkMuted
end

function S.RefreshBar()
	if not ui then
		return
	end
	local slot = selectedSlot()
	local item = Catalog.Get(st.Item)
	local current = slot and placedAt(slot.Id)
	ui.Remove.Instance.Visible = current ~= nil
	if not item then
		ui.BarPreview:Show(current and { Kind = "Decor", DecorId = current } or nil)
		ui.BarName.Text = slot and slotName(slot) or T("PLOT DECOR")
		ui.BarPrice.Text = ""
		ui.BarInfo.Text = T("Choose a spot on the left, then a decoration.")
		ui.Primary.Instance.Visible = false
		return
	end
	ui.BarPreview:Show({ Kind = "Decor", DecorId = item.Id })
	ui.BarName.Text = itemName(item)
	ui.BarPrice.Text = priceText(item)
	local n, spare = owned(item.Id), free(item.Id)
	local info = T("OWNED") .. " " .. n .. (n > 0 and (" · " .. T("FREE") .. " " .. spare) or "")
	ui.Primary.Instance.Visible = true
	local d = decor()
	local inYard = d and d.InYard == true
	local locked = stage() < item.Stage
	if locked then
		ui.Primary:SetText((ru() and "СТАДИЯ " or "STAGE ") .. item.Stage)
		ui.Primary:SetStyle("secondary")
		ui.Primary:SetDisabled(true)
		info ..= " · " .. said("Unlocks at yard stage " .. item.Stage)
	elseif slot and item.Size ~= slot.Size then
		ui.Primary:SetText(T("BUY"))
		ui.Primary:SetStyle("success")
		ui.Primary:SetDisabled(n >= Catalog.MaxOwned(item.Id))
		info ..= " · " .. said(item.Size == "Large" and "This decoration needs a BIG spot" or "This decoration needs a SMALL spot")
	elseif slot and current == item.Id then
		ui.Primary:SetText(T("PLACE"))
		ui.Primary:SetStyle("secondary")
		ui.Primary:SetDisabled(true)
	elseif slot and spare > 0 then
		ui.Primary:SetText(T("PLACE"))
		ui.Primary:SetStyle("primary")
		ui.Primary:SetDisabled(false)
	elseif slot then
		ui.Primary:SetText(T("BUY & PLACE"))
		ui.Primary:SetStyle("success")
		ui.Primary:SetDisabled(n >= Catalog.MaxOwned(item.Id))
	else
		ui.Primary:SetText(T("BUY"))
		ui.Primary:SetStyle("success")
		ui.Primary:SetDisabled(n >= Catalog.MaxOwned(item.Id))
	end
	if slot and not inYard and not locked then
		info ..= " · " .. T("Walk into your yard to place decorations")
	end
	ui.BarInfo.Text = info
end

function S.Primary()
	local item = Catalog.Get(st.Item)
	local slot = selectedSlot()
	if not item then
		return
	end
	if slot and item.Size == slot.Size then
		if free(item.Id) > 0 then
			S.Place()
		else
			S.Buy(true)
		end
	else
		S.Buy(false)
	end
end

function S.RefreshCards(resetScroll: boolean?)
	if not ui then
		return
	end
	local list = {}
	for _, item in ipairs(Catalog.Items) do
		if item.Category == st.Category then
			table.insert(list, item)
		end
	end
	ui.Grid:SetItems(list, { ResetScroll = resetScroll == true })
end

local function refreshTabs()
	local slot = selectedSlot()
	local cats = categoriesFor(slot)
	local valid = false
	for _, c in ipairs(cats) do
		if c.Id == st.Category then
			valid = true
		end
	end
	if not valid then
		st.Category = cats[1].Id
	end
	local key = (slot and slot.Size or "All") .. ":" .. Kit.Lang()
	if ui.TabsKey ~= key then
		ui.TabsKey = key
		local tabs = {}
		for _, c in ipairs(cats) do
			table.insert(tabs, { Id = c.Id, Text = c.Icon .. " " .. (ru() and c.RU or c.Name), NoTranslate = true })
		end
		ui.Tabs:SetTabs(tabs, st.Category)
	else
		ui.Tabs:Select(st.Category, true)
	end
end

refresh = function(snapshot: any?)
	if snapshot then
		st.Snapshot = snapshot
	end
	if not ui then
		return
	end
	for _, r in ipairs(ui.Rows) do
		paintRow(r)
	end
	refreshTabs()
	local cash, stone, bones = wallet()
	ui.Wallet.Text = "💰 " .. short(cash) .. "   🪨 " .. Format.Number(stone) .. "   🦴 " .. Format.Number(bones)
	S.RefreshCards(false)
	S.RefreshBar()
end
S.Refresh = refresh

function S.SelectSlot(id: string?)
	st.Slot = id and Catalog.Slot(id) and id or nil
	local slot = selectedSlot()
	local item = Catalog.Get(st.Item)
	if slot and item and item.Size ~= slot.Size then
		st.Item = nil
	end
	if slot and not st.Item then
		st.Item = placedAt(slot.Id)
	end
	refresh(nil)
	relayout()
end

relayout = function()
	if not ui then
		return
	end
	local layout = win:GetLayout()
	local w, h = layout.Width, layout.Height
	if w < 2 or h < 2 then
		return
	end
	local phone, landscape = layout.Phone, layout.Landscape
	local gap = phone and 6 or 10
	local x, y = 0, 0
	-- Spots: a column on desktop and landscape phones, a sideways strip on portrait phones.
	local column = not phone or landscape
	if column then
		local colW = landscape and 150 or 220
		ui.Spots.Position = UDim2.fromOffset(0, 0)
		ui.Spots.Size = UDim2.fromOffset(colW, h)
		ui.Spots.ScrollingDirection = Enum.ScrollingDirection.Y
		local rowH = landscape and 40 or 48
		for i, r in ipairs(ui.Rows) do
			r.Button.Position = UDim2.fromOffset(2, (i - 1) * (rowH + 4) + 2)
			r.Button.Size = UDim2.fromOffset(colW - 12, rowH)
			r.Icon.Position = UDim2.fromOffset(4, 0)
			r.Icon.Size = UDim2.fromOffset(26, rowH)
			r.Title.Position = UDim2.fromOffset(32, 3)
			r.Title.Size = UDim2.fromOffset(colW - 50, rowH * 0.48)
			r.Sub.Position = UDim2.fromOffset(32, rowH * 0.5)
			r.Sub.Size = UDim2.fromOffset(colW - 50, rowH * 0.42)
		end
		ui.Spots.CanvasSize = UDim2.fromOffset(0, #ui.Rows * (rowH + 4) + 4)
		x = colW + gap
	else
		local stripH = 58
		ui.Spots.Position = UDim2.fromOffset(0, 0)
		ui.Spots.Size = UDim2.fromOffset(w, stripH)
		ui.Spots.ScrollingDirection = Enum.ScrollingDirection.X
		local tileW = 104
		for i, r in ipairs(ui.Rows) do
			r.Button.Position = UDim2.fromOffset((i - 1) * (tileW + 4) + 2, 2)
			r.Button.Size = UDim2.fromOffset(tileW, stripH - 10)
			r.Icon.Position = UDim2.fromOffset(2, 0)
			r.Icon.Size = UDim2.fromOffset(22, stripH - 10)
			r.Title.Position = UDim2.fromOffset(24, 3)
			r.Title.Size = UDim2.fromOffset(tileW - 28, 20)
			r.Sub.Position = UDim2.fromOffset(24, 24)
			r.Sub.Size = UDim2.fromOffset(tileW - 28, 18)
		end
		ui.Spots.CanvasSize = UDim2.fromOffset(#ui.Rows * (tileW + 4) + 4, 0)
		y = stripH + gap
	end
	local mw = w - x
	-- Wallet + tabs.
	local tabH = phone and 38 or 44
	local walletW = phone and 0 or 260
	ui.Wallet.Visible = not phone
	ui.Wallet.Position = UDim2.fromOffset(x + mw - walletW, y)
	ui.Wallet.Size = UDim2.fromOffset(walletW, tabH)
	ui.Tabs.Instance.Position = UDim2.fromOffset(x, y)
	ui.Tabs.Instance.Size = UDim2.fromOffset(mw - walletW - (walletW > 0 and gap or 0), tabH)
	y += tabH + gap
	-- Action bar at the bottom.
	local barH = landscape and 64 or (phone and 112 or 96)
	ui.Bar.Position = UDim2.fromOffset(x, h - barH)
	ui.Bar.Size = UDim2.fromOffset(mw, barH)
	local pv = landscape and 52 or (phone and 64 or 76)
	ui.BarHolder.Position = UDim2.fromOffset(8, math.floor((barH - pv) / 2))
	ui.BarHolder.Size = UDim2.fromOffset(pv, pv)
	local buttonW = phone and 128 or 190
	local removeW = phone and 92 or 120
	local tx = pv + 16
	if phone and not landscape then
		-- Text on top, buttons on a second row.
		ui.BarHolder.Position = UDim2.fromOffset(8, 8)
		ui.BarName.Position = UDim2.fromOffset(tx, 6)
		ui.BarName.Size = UDim2.fromOffset(mw - tx - 8, 22)
		ui.BarPrice.Position = UDim2.fromOffset(tx, 28)
		ui.BarPrice.Size = UDim2.fromOffset(mw - tx - 8, 18)
		ui.BarInfo.Position = UDim2.fromOffset(tx, 46)
		ui.BarInfo.Size = UDim2.fromOffset(mw - tx - 8, 16)
		ui.Primary.Instance.Position = UDim2.new(1, -(buttonW + 8), 1, -46)
		ui.Primary.Instance.Size = UDim2.fromOffset(buttonW, 40)
		ui.Remove.Instance.Position = UDim2.new(1, -(buttonW + removeW + 14), 1, -46)
		ui.Remove.Instance.Size = UDim2.fromOffset(removeW, 40)
	else
		local textW = mw - tx - buttonW - removeW - 28
		ui.BarName.Position = UDim2.fromOffset(tx, landscape and 4 or 10)
		ui.BarName.Size = UDim2.fromOffset(textW, landscape and 20 or 26)
		ui.BarPrice.Position = UDim2.fromOffset(tx, landscape and 24 or 38)
		ui.BarPrice.Size = UDim2.fromOffset(textW, landscape and 18 or 22)
		ui.BarInfo.Position = UDim2.fromOffset(tx, landscape and 42 or 62)
		ui.BarInfo.Size = UDim2.fromOffset(textW, landscape and 16 or 22)
		local bh = landscape and 44 or 48
		ui.Primary.Instance.Position = UDim2.new(1, -(buttonW + 10), 0.5, -bh / 2)
		ui.Primary.Instance.Size = UDim2.fromOffset(buttonW, bh)
		ui.Remove.Instance.Position = UDim2.new(1, -(buttonW + removeW + 18), 0.5, -bh / 2)
		ui.Remove.Instance.Size = UDim2.fromOffset(removeW, bh)
	end
	ui.GridHost.Position = UDim2.fromOffset(x, y)
	ui.GridHost.Size = UDim2.fromOffset(mw, math.max(40, h - barH - gap - y))
	ui.Grid:Relayout()
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
local openToken = 0
local stoneConnection: RBXScriptConnection? = nil
function S._opened()
	openToken += 1
	local token = openToken
	local cached = Net.Cached()
	if cached then
		refresh(cached)
	end
	stoneConnection = player:GetAttributeChangedSignal("Stone"):Connect(function()
		if win and win.IsOpen then
			refresh(nil)
		end
	end)
	task.spawn(function()
		local snapshot = Net.Snapshot(1)
		if snapshot and openToken == token and win.IsOpen then
			refresh(snapshot)
		end
		while openToken == token and win.IsOpen do
			task.wait(8)
			if openToken ~= token or not win.IsOpen then
				break
			end
			Net.Snapshot(6)
		end
	end)
end
function S._closed()
	openToken += 1
	if stoneConnection then
		stoneConnection:Disconnect()
		stoneConnection = nil
	end
end

Net.Changed:Connect(function(snapshot)
	if win and win.IsOpen then
		refresh(snapshot)
	end
end)

local function rebuildIfLanguageChanged()
	if win and ui and ui.Lang ~= Kit.Lang() and not win.IsOpen then
		ui.Grid:Destroy()
		ui.BarPreview:Destroy()
		for _, r in ipairs(ui.Rows) do
			r.Maid:Clean()
		end
		win:Destroy()
		win, ui = nil, nil
		S.Window, S.UI = nil, nil
	end
end

-- arg: a slot id ("L1", "S3"...) to open on that spot; anything else opens ALL SPOTS.
function S.Open(arg: any?)
	rebuildIfLanguageChanged()
	build()
	local slot = type(arg) == "string" and Catalog.Slot(arg) or nil
	st.Slot = slot and slot.Id or nil
	st.Item = slot and placedAt(slot.Id) or nil
	if slot then
		st.Category = categoriesFor(slot)[1].Id
		local current = st.Item and Catalog.Get(st.Item)
		if current then
			st.Category = current.Category
		end
	end
	win:Open()
	refresh(nil)
	relayout()
end

function S.Close()
	if win and win.IsOpen then
		win:Close("api")
	end
end

function S.IsOpen(): boolean
	return win ~= nil and win.IsOpen
end

return S
