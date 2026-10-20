-- WHERE TO GO? (kit window, Key "Navigate"): every place of the district and of the player's own
-- plot with an icon, a short subtitle, the walking distance and SHOW PATH, which starts a route
-- of glowing ground arrows (ReplicatedStorage.Navigation.PathGuide) and closes the window.
-- Category chips: ALL / MY PLOT / SHOPS / ATTRACTIONS. Sealed places are shown disabled.
--   NavigatorScreen.Open(arg?)  arg: a destination key or name -> start that route right away
--                               (no window); otherwise / sealed / unknown -> the window opens.
-- Routed by GUIIntegration (N.OpenPage("Navigate")); the N key toggles it (PathGuide.client).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local NavFolder = ReplicatedStorage:WaitForChild("Navigation")
local PathGuide = require(NavFolder:WaitForChild("PathGuide"))
local Destinations = require(NavFolder:WaitForChild("Destinations"))

local T = Kit.T
local Theme = Kit.Theme
local ACCENT = Color3.fromRGB(38, 164, 243)
local Z = 3

local M = {
	Window = nil :: any,
	Grid = nil :: any,
	Chips = nil :: any,
	Filter = "All",
	Distances = {} :: { [string]: number },
}

local function lang(): string
	return Kit.Lang()
end

local function navigation(): any
	local ok, N = pcall(require, script.Parent.GUIIntegration)
	return ok and N or nil
end

local REASONS = {
	noyard = { "Your yard is not ready yet", "Участок ещё не готов" },
	unknown = { "This place is not on the map", "Этого места нет на карте" },
}

-- Starts the route; true when it runs. quiet: no toast (Open with a key from another screen).
function M.Go(key: string, quiet: boolean?): boolean
	local entry = Destinations.ByKey[key]
	if not entry then
		return false
	end
	if entry.Sealed then
		if not quiet then
			Kit.Toast(Destinations.Text(entry, "Name", lang()) .. " · " .. Destinations.Text(entry, "Detail", lang()), { Kind = "warn" })
		end
		return false
	end
	local ok, reason = PathGuide.Show(key)
	if not ok then
		local row = REASONS[reason or "unknown"] or REASONS.unknown
		Kit.Toast(T(row[1], row[2]), { Kind = "error" })
		return false
	end
	if M.Window and M.Window.IsOpen then
		M.Window:Close("route")
	end
	if not quiet then
		Kit.Toast(T("Follow the glowing arrows!", "Иди по светящимся стрелкам!"), { Kind = "success" })
	end
	return true
end

------------------------------------------------------------------------------------------------
-- Cells
------------------------------------------------------------------------------------------------
local function createCell(frame: Frame): any
	local card = Kit.New("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 1,
	}, frame)
	Kit.Corner(card, Theme.Radius.Card)
	local stroke = Kit.Stroke(card, Theme.Colors.edge, 2, 0.6)
	local tile = Kit.New("Frame", { Name = "IconTile", BorderSizePixel = 0, ZIndex = Z + 2 }, card)
	Kit.Corner(tile, 12)
	local icon = Kit.Text(tile, { Name = "Glyph", TextSize = 30, AlignX = "Center", NoTranslate = true, ZIndex = Z + 3 })
	local name = Kit.Text(card, { Name = "Title", TextSize = Theme.Size("Heading"), Scaled = true, MinTextSize = 12, NoTranslate = true, ZIndex = Z + 2 })
	local sub = Kit.Text(card, { Name = "Subtitle", TextSize = Theme.Size("Small"), Color = Theme.InkMuted, Wrap = true, AlignY = "Top", NoTranslate = true, ZIndex = Z + 2 })
	local distance = Kit.Pill(card, { Text = "", Color = Theme.Colors.navy, TextSize = 13, Font = "numeric", NoTranslate = true, ZIndex = Z + 2 })
	distance.Label.TextColor3 = Theme.Ink
	local cell: any = { Card = card, Stroke = stroke, Tile = tile, Icon = icon, Name = name, Sub = sub, Distance = distance }
	cell.Button = Kit.Button(card, {
		Name = "ShowPath",
		Text = T("SHOW PATH", "ПОКАЗАТЬ ПУТЬ"),
		Style = "primary",
		TextSize = 15,
		NoTranslate = true,
		ZIndex = Z + 3,
		OnClick = function()
			local key = cell.Key
			if not key then
				return
			end
			local active = PathGuide.Active()
			if active and active.Key == key then
				PathGuide.Clear("cleared")
				M.Refresh(false)
			else
				M.Go(key)
			end
		end,
	})
	return cell
end

-- Wide cards (desktop / tablets) or list rows (phones).
local function layoutCell(cell: any, w: number, h: number)
	local row = h < 100
	local pad = row and 8 or 12
	local tileSize = row and (h - 16) or 58
	cell.Tile.Position = UDim2.fromOffset(pad, pad)
	cell.Tile.Size = UDim2.fromOffset(tileSize, tileSize)
	cell.Icon.Size = UDim2.fromScale(1, 1)
	cell.Icon.TextSize = row and 26 or 32
	local textX = pad + tileSize + 10
	if row then
		local buttonW = math.min(124, math.floor(w * 0.36))
		cell.Button.Instance.AnchorPoint = Vector2.new(1, 0.5)
		cell.Button.Instance.Position = UDim2.new(1, -pad, 0.5, 0)
		cell.Button.Instance.Size = UDim2.fromOffset(buttonW, h - 22)
		cell.Name.Position = UDim2.fromOffset(textX, 6)
		cell.Name.Size = UDim2.new(1, -(textX + buttonW + pad + 8), 0, 24)
		cell.Sub.Position = UDim2.fromOffset(textX, 30)
		cell.Sub.Size = UDim2.new(1, -(textX + buttonW + pad + 70), 0, h - 34)
		cell.Distance.Instance.AnchorPoint = Vector2.new(1, 1)
		cell.Distance.Instance.Position = UDim2.new(1, -(buttonW + pad + 8), 1, -8)
	else
		cell.Button.Instance.AnchorPoint = Vector2.new(1, 1)
		cell.Button.Instance.Position = UDim2.new(1, -pad, 1, -pad)
		cell.Button.Instance.Size = UDim2.fromOffset(math.min(150, w - 110), 40)
		cell.Name.Position = UDim2.fromOffset(textX, pad)
		cell.Name.Size = UDim2.new(1, -(textX + pad), 0, 26)
		cell.Sub.Position = UDim2.fromOffset(textX, pad + 28)
		cell.Sub.Size = UDim2.new(1, -(textX + pad), 0, h - pad * 2 - 28 - 46)
		cell.Distance.Instance.AnchorPoint = Vector2.new(0, 1)
		cell.Distance.Instance.Position = UDim2.new(0, pad, 1, -pad - 9)
	end
end

local function bindCell(cell: any, item: any)
	local entry = item.Entry
	local color = Destinations.Color(entry)
	local l = lang()
	cell.Key = entry.Key
	cell.Tile.BackgroundColor3 = entry.Sealed and Color3.fromRGB(200, 208, 220) or color:Lerp(Theme.White, 0.55)
	cell.Icon.Text = entry.Icon or "★"
	cell.Name.Text = Destinations.Text(entry, "Name", l)
	cell.Sub.Text = Destinations.Text(entry, "Detail", l)
	local active = PathGuide.Active()
	local on = active ~= nil and active.Key == entry.Key
	cell.Stroke.Color = on and color or Theme.Colors.edge
	cell.Stroke.Transparency = on and 0 or 0.6
	cell.Stroke.Thickness = on and 3 or 2
	local d = M.Distances[entry.Key]
	if entry.Sealed then
		cell.Distance:Set(T("CLOSED", "ЗАКРЫТО"), Color3.fromRGB(220, 226, 236))
	elseif on then
		cell.Distance:Set(T("ON ROUTE", "В ПУТИ"), color:Lerp(Theme.White, 0.5))
	else
		cell.Distance:Set(d and ("≈ " .. PathGuide.FormatDistance(d)) or "—", Theme.Colors.navy)
	end
	if entry.Sealed then
		cell.Button:SetText(T("SEALED", "ЗАКРЫТО"))
		cell.Button:SetStyle("secondary")
		cell.Button:SetDisabled(true)
	elseif on then
		cell.Button:SetDisabled(false)
		cell.Button:SetText(T("STOP", "СТОП"))
		cell.Button:SetStyle("danger")
	else
		cell.Button:SetDisabled(false)
		cell.Button:SetText(T("SHOW PATH", "ПОКАЗАТЬ ПУТЬ"))
		cell.Button:SetStyle("primary", color:Lerp(Theme.Colors.edge, 0.12))
	end
end

------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------
local function items(): { any }
	local list = {}
	for _, entry in ipairs(Destinations.List) do
		if M.Filter == "All" or entry.Category == M.Filter then
			table.insert(list, { Key = entry.Key, Entry = entry })
		end
	end
	-- Open places first (nearest first inside a category), sealed ones last.
	table.sort(list, function(a, b)
		local sa, sb = a.Entry.Sealed == true, b.Entry.Sealed == true
		if sa ~= sb then
			return not sa
		end
		if M.Filter ~= "All" then
			local da, db = M.Distances[a.Key] or math.huge, M.Distances[b.Key] or math.huge
			if da ~= db then
				return da < db
			end
		end
		return a.Entry.Order < b.Entry.Order
	end)
	return list
end

function M.Refresh(resetScroll: boolean?)
	if not M.Grid then
		return
	end
	M.Grid:SetItems(items(), { ResetScroll = resetScroll == true })
	M.Grid:Refresh()
	local active = PathGuide.Active()
	if M.Window then
		if active then
			M.Window:SetTitle(nil, T("On route: ", "В пути: ") .. Destinations.Text(active.Entry, "Name", lang()) .. " · " .. PathGuide.FormatDistance(active.Remaining or 0))
		else
			M.Window:SetTitle(nil, T("Pick a place: glowing arrows will lead you there", "Выбери место — светящиеся стрелки приведут тебя туда"))
		end
	end
end

local function measure()
	table.clear(M.Distances)
	for _, entry in ipairs(Destinations.List) do
		if not entry.Sealed then
			local ok, d = pcall(PathGuide.Estimate, entry.Key)
			if ok and d then
				M.Distances[entry.Key] = d
			end
		end
	end
end

local function build()
	local win = Kit.Window.new({
		Key = "Navigate",
		Title = T("WHERE TO GO?", "КУДА ИДТИ?"),
		Subtitle = T("Pick a place: glowing arrows will lead you there", "Выбери место — светящиеся стрелки приведут тебя туда"),
		Accent = ACCENT,
		NoTranslate = true,
		MaxSize = Vector2.new(980, 720),
	})
	M.Window = win
	local body = win.Body
	local options = { { Id = "All", Text = T("ALL", "ВСЕ"), NoTranslate = true } }
	for _, category in ipairs(Destinations.Categories) do
		table.insert(options, { Id = category.Id, Text = lang() == "ru" and category.Ru or category.Text, Color = category.Color, NoTranslate = true })
	end
	M.Chips = Kit.Chips(body, {
		Name = "Categories",
		Options = options,
		Selected = M.Filter,
		AllowNone = false,
		ZIndex = Z,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 40),
		OnChange = function(id)
			M.Filter = id or "All"
			M.Refresh(true)
		end,
	})
	local hint = Kit.Text(body, {
		Name = "KeyHint",
		Text = T("N — this window · M — district map", "N — это окно · M — карта района"),
		TextSize = Theme.Size("Tiny"),
		Color = Theme.InkMuted,
		AlignX = "Right",
		NoTranslate = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -6, 1, 0),
		Size = UDim2.new(1, -12, 0, 18),
		ZIndex = Z,
	})
	M.Grid = Kit.VirtualGrid(body, {
		Name = "Places",
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -68),
		CellSize = function(viewW: number, _viewH: number): Vector2
			if viewW < 560 then
				return Vector2.new(viewW - 24, 78)
			end
			return Vector2.new(286, 142)
		end,
		Gap = 10,
		Padding = 8,
		ZIndex = Z,
		Create = createCell,
		Bind = function(cell: any, item: any)
			bindCell(cell, item)
		end,
		Layout = layoutCell,
		Key = function(item: any)
			return item.Key
		end,
		Empty = { Title = Kit.Word("NO_RESULTS") },
	})
	win.Maid:Give(M.Grid)
	win.Resized:Connect(function(layout: any)
		local phone = layout.Phone
		hint.Visible = not (layout.Touch and phone)
		M.Grid.Instance.Size = UDim2.new(1, 0, 1, phone and -48 or -68)
	end)
	win.Maid:Give(PathGuide.Changed:Connect(function()
		if win.IsOpen then
			M.Refresh(false)
		end
	end))
end

function M.Open(arg: any?)
	if type(arg) == "string" and arg ~= "" then
		local key = Destinations.Resolve(arg)
		if key and not Destinations.ByKey[key].Sealed then
			local N = navigation()
			if N and N.Owner ~= "HUD" then
				N.Close()
			end
			if M.Go(key, true) then
				return
			end
		end
	end
	if not M.Window then
		build()
	end
	measure()
	M.Refresh(true)
	M.Window:Open()
end

function M.IsOpen(): boolean
	return M.Window ~= nil and M.Window.IsOpen == true
end

return M
