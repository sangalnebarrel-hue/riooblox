-- MINE ELEVATOR window (Kit, Key = "Mine"; GUIIntegration.kitScreens routes N.OpenPage("Mine")
-- here). Opened by the headframe prompt and by the stop prompt of every mine level
-- (StarterPlayerScripts.MineClient). Lists the five depths of one yard's mine (Surface, Caverns,
-- Ancient Ruins, Cursed Depths, THE VOID): locked / unlocked for that yard's owner (visitors may
-- ride another player's mine to look), where the dogs dig, where the player is, how many finds
-- of each depth the player owns. Buttons: GO (ride the elevator), and for the owner DIG HERE /
-- UNLOCK, which send the existing economy action "Layer" (no new economy: the server checks the
-- level, prestige and price as before).
--   Screen.Open({YardId = n}?)  Screen.Close()  Screen.IsOpen()
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local MineFolder = RS:WaitForChild("Mine")
local Layout = require(MineFolder:WaitForChild("MineLayout"))
local Themes = require(MineFolder:WaitForChild("MineThemes"))
local State = require(MineFolder:WaitForChild("MineState"))
local Config = require(RS:WaitForChild("DogEconomy"):WaitForChild("Config"))
local Depth = require(RS:WaitForChild("DogEconomy"):WaitForChild("DepthDefinitions"))

local Theme = Kit.Theme
local T = Kit.T
local C = Color3.fromRGB
local player = Players.LocalPlayer

local Screen = {}
local win: any = nil
local rows: { any } = {}
local ui: any = {}
local yardId: any = nil
local maid: any = nil
local busy = false

local ACCENT = C(64, 82, 104)

local function yardById(id: any): Instance?
	local map = workspace:FindFirstChild("DOGROTS_District")
	local yards = map and map:FindFirstChild("04_PlayerYards")
	if not yards then
		return nil
	end
	for _, yard in yards:GetChildren() do
		if id ~= nil and yard:GetAttribute("YardId") == id then
			return yard
		end
	end
	return nil
end
local function ownYard(): Instance?
	local map = workspace:FindFirstChild("DOGROTS_District")
	local yards = map and map:FindFirstChild("04_PlayerYards")
	for _, yard in yards and yards:GetChildren() or {} do
		if yard:GetAttribute("OwnerUserId") == player.UserId then
			return yard
		end
	end
	return nil
end

-- Server messages in the player's language (Localization.Mine has the full list for
-- AutoTranslate; the window labels are NoTranslate).
local MESSAGES = {
	["This depth is still locked"] = "Эта глубина ещё закрыта",
	["Stand at the mine elevator"] = "Подойди к лифту шахты",
	["This yard has no owner"] = "У этого участка нет хозяина",
	["Wait for your character"] = "Подожди появления персонажа",
	["Please wait a moment"] = "Подожди немного",
	["Invalid request"] = "Неверный запрос",
	["THE VOID requires Prestige 1"] = "Для ПУСТОТЫ нужен престиж 1",
	["Not enough Cash or Bones"] = "Не хватает монет или костей",
	["Invalid layer"] = "Неверная глубина",
}
local function serverText(message: any): string
	local text = type(message) == "table" and tostring(message.Message or "") or tostring(message or "")
	if Kit.Lang() ~= "ru" then
		return text
	end
	if MESSAGES[text] then
		return MESSAGES[text]
	end
	local level = string.match(text, "^Unlock the previous layer and reach level (%d+)$")
	if level then
		return "Открой предыдущую глубину и достигни уровня " .. level
	end
	return text
end

------------------------------------------------------------------------------------------------
-- Build (once)
------------------------------------------------------------------------------------------------
local function label(parent: Instance, props: any): TextLabel
	props.NoTranslate = true
	return Kit.Text(parent, props)
end

local function buildRow(parent: Instance, layer: number): any
	local theme = Themes.Get(layer)
	local row: any = { Layer = layer }
	local frame = Kit.New("Frame", {
		Name = "Depth" .. layer,
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		LayoutOrder = layer,
		Size = UDim2.new(1, -8, 0, 110),
		ZIndex = 3,
	}, parent)
	Kit.Corner(frame, Theme.Radius.Card)
	row.Stroke = Kit.Stroke(frame, Theme.Colors.edge, 2)
	row.Frame = frame
	-- Depth band: the level's colours from the dark rock to its glow.
	local band = Kit.New("Frame", {
		Name = "Band",
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 64, 1, 0),
		ZIndex = 4,
	}, frame)
	Kit.Corner(band, Theme.Radius.Card)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new((theme.RockDark or theme.Rock):Lerp(C(0, 0, 0), 0.2), theme.Accent)
	gradient.Parent = band
	row.Number = label(band, {
		Text = layer == 1 and "▲" or tostring(layer - 1),
		TextSize = 30,
		Color = Theme.White,
		AlignX = "Center",
		Stroke = true,
		Size = UDim2.new(1, 0, 0.55, 0),
		Position = UDim2.fromScale(0, 0.08),
		ZIndex = 5,
	})
	row.DepthText = label(band, {
		Text = Themes.DepthText(layer, Kit.Lang()),
		TextSize = 13,
		Color = Theme.White,
		AlignX = "Center",
		Stroke = true,
		Scaled = true,
		MinTextSize = 8,
		Size = UDim2.new(1, -6, 0.26, 0),
		Position = UDim2.new(0, 3, 0.64, 0),
		ZIndex = 5,
	})
	row.Title = label(frame, { Text = Themes.Name(layer, Kit.Lang()), TextSize = 22, Color = Theme.Ink, ZIndex = 4 })
	row.Tagline = label(frame, {
		Text = Kit.Lang() == "ru" and theme.TaglineRu or theme.Tagline,
		TextSize = 14,
		Color = Theme.InkMuted,
		ZIndex = 4,
	})
	local pills = Kit.New("Frame", { Name = "Pills", BackgroundTransparency = 1, ZIndex = 4 }, frame)
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, pills)
	row.Pills = pills
	row.Here = Kit.Pill(pills, { Text = T("YOU ARE HERE", "ТЫ ЗДЕСЬ"), Color = Theme.Colors.green, LayoutOrder = 1, ZIndex = 5, NoTranslate = true })
	row.Dogs = Kit.Pill(pills, { Text = T("DOGS DIG HERE", "СОБАКИ КОПАЮТ ЗДЕСЬ"), Color = Theme.Colors.gold, LayoutOrder = 2, ZIndex = 5, NoTranslate = true })
	row.Locked = Kit.Pill(pills, { Text = T("LOCKED", "ЗАКРЫТО"), Color = Theme.Disabled, LayoutOrder = 3, ZIndex = 5, NoTranslate = true })
	row.Finds = Kit.Pill(pills, { Text = "", Color = theme.Accent:Lerp(C(0, 0, 0), 0.25), LayoutOrder = 4, ZIndex = 5, NoTranslate = true })
	row.Go = Kit.Button(frame, {
		Name = "Go",
		Text = T("GO", "ПОЕХАЛИ"),
		Style = "primary",
		ZIndex = 5,
		NoTranslate = true,
		OnClick = function()
			Screen.Ride(layer, row)
		end,
	})
	row.Dig = Kit.Button(frame, {
		Name = "Dig",
		Text = T("DIG HERE", "КОПАТЬ ЗДЕСЬ"),
		Style = "success",
		ZIndex = 5,
		NoTranslate = true,
		OnClick = function()
			Screen.SetDigLayer(layer, row)
		end,
	})
	row.Need = label(frame, { Text = "", TextSize = 13, Color = Theme.InkMuted, AlignX = "Right", Wrap = true, ZIndex = 4 })
	return row
end

local function layoutRows(info: any)
	local phone = info.Phone or (info.Width or 600) < 560
	for _, row in rows do
		local h = phone and 150 or 112
		row.Frame.Size = UDim2.new(1, -8, 0, h)
		local bandW = phone and 52 or 70
		local band = row.Frame:FindFirstChild("Band")
		if band then
			band.Size = UDim2.new(0, bandW, 1, 0)
		end
		local x = bandW + 12
		local right = phone and 12 or 172
		row.Title.Position = UDim2.fromOffset(x, 8)
		row.Title.Size = UDim2.new(1, -(x + right), 0, 30)
		row.Tagline.Position = UDim2.fromOffset(x, 38)
		row.Tagline.Size = UDim2.new(1, -(x + right), 0, 20)
		row.Pills.Position = UDim2.fromOffset(x, 64)
		row.Pills.Size = UDim2.new(1, -(x + right), 0, 24)
		if phone then
			local bw = 0.5
			row.Go.Instance.Position = UDim2.new(0, x, 1, -52)
			row.Go.Instance.Size = UDim2.new(bw, -(x / 2 + 8), 0, 42)
			row.Dig.Instance.Position = UDim2.new(bw, x / 2, 1, -52)
			row.Dig.Instance.Size = UDim2.new(bw, -(x / 2 + 12), 0, 42)
			row.Need.Position = UDim2.new(bw, x / 2, 1, -52)
			row.Need.Size = UDim2.new(bw, -(x / 2 + 12), 0, 42)
		else
			row.Go.Instance.Position = UDim2.new(1, -160, 0, 12)
			row.Go.Instance.Size = UDim2.fromOffset(148, 44)
			row.Dig.Instance.Position = UDim2.new(1, -160, 0, 62)
			row.Dig.Instance.Size = UDim2.fromOffset(148, 38)
			row.Need.Position = UDim2.new(1, -164, 0, 60)
			row.Need.Size = UDim2.fromOffset(152, 42)
		end
	end
end

local function build()
	win = Kit.Window.new({
		Key = "Mine",
		Title = T("MINE ELEVATOR", "ЛИФТ ШАХТЫ"),
		Subtitle = "",
		Accent = ACCENT,
		Icon = "Yard",
		MaxSize = Vector2.new(820, 760),
		NoTranslate = true,
	})
	maid = Kit.Maid.new()
	win.Maid:Give(maid)
	local scroll = Kit.New("ScrollingFrame", {
		Name = "Depths",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 3,
	}, win.Body)
	Kit.New("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	Kit.Padding(scroll, 4, 4, 4, 8)
	ui.Hint = label(scroll, {
		Text = "",
		TextSize = 15,
		Color = Theme.InkMuted,
		Wrap = true,
		Size = UDim2.new(1, -8, 0, 40),
		LayoutOrder = 0,
		ZIndex = 3,
	})
	for layer = 1, 5 do
		rows[layer] = buildRow(scroll, layer)
	end
	win.Resized:Connect(layoutRows)
	layoutRows(win:GetLayout())
end

------------------------------------------------------------------------------------------------
-- Refresh (in place)
------------------------------------------------------------------------------------------------
local function snapshotProfile(): any
	local snapshot = Net.Cached()
	return snapshot and snapshot.Profile or nil
end

function Screen.Refresh()
	if not win then
		return
	end
	local yard = yardById(yardId)
	local owner = yard and yard:GetAttribute("OwnerUserId") or 0
	local isOwner = owner ~= 0 and owner == player.UserId
	local mask = yard and yard:GetAttribute("MineUnlocked") or 1
	local digLayer = yard and yard:GetAttribute("MineLayer") or 1
	local profile = snapshotProfile()
	if isOwner and profile and type(profile.UnlockedLayers) == "table" then
		mask = Layout.Mask(profile.UnlockedLayers)
		digLayer = Layout.LayerNumber(profile.CurrentLayer) or digLayer
	end
	local ownerName = yard and yard:GetAttribute("OwnerDisplayName") or ""
	if (ownerName == nil or ownerName == "") and owner ~= 0 then
		local who = Players:GetPlayerByUserId(owner)
		ownerName = who and who.DisplayName or ""
	end
	local subtitle
	if isOwner then
		subtitle = T("Your mine · dogs dig at ", "Твоя шахта · собаки копают: ") .. Themes.Name(digLayer, Kit.Lang())
	elseif owner ~= 0 then
		subtitle = T("Mine of ", "Шахта игрока ") .. ownerName .. " · " .. T("visitors may look around", "гостям можно осмотреться")
	else
		subtitle = T("Nobody owns this yard yet", "У этого участка пока нет хозяина")
	end
	win:SetTitle(T("MINE ELEVATOR", "ЛИФТ ШАХТЫ"), subtitle)
	ui.Hint.Text = isOwner and T("Pick a depth: ride down to watch your dogs dig, or make it your dig layer.", "Выбери глубину: спустись посмотреть, как копают собаки, или копай там.")
		or T("Ride down to look around. Only the owner chooses where the dogs dig.", "Спустись и осмотрись. Где копать, выбирает только хозяин.")
	local location = State.Location
	local here = (location.YardId ~= nil and location.YardId == yardId) and (location.Layer or 1) or (yard and 1 or nil)
	local owned = profile and type(profile.Collection) == "table" and profile.Collection or {}
	local level = profile and tonumber(profile.Level) or 0
	local prestige = profile and tonumber(profile.Prestige) or 0
	for layer, row in rows do
		local unlocked = Layout.Unlocked(mask, layer)
		local isHere = here == layer
		row.Here:SetVisible(isHere)
		row.Dogs:SetVisible(digLayer == layer and owner ~= 0)
		row.Locked:SetVisible(not unlocked)
		local items = Depth[tostring(layer)] and Depth[tostring(layer)].Items or {}
		local found = 0
		for _, id in items do
			if owned[id] == true then
				found += 1
			end
		end
		row.Finds:Set(T("FINDS ", "НАХОДКИ ") .. found .. "/" .. #items)
		row.Finds:SetVisible(#items > 0)
		row.Stroke.Color = isHere and Theme.Colors.green or Theme.Colors.edge
		row.Stroke.Thickness = isHere and 3 or 2
		-- GO
		row.Go:SetText(isHere and T("YOU ARE HERE", "ТЫ ЗДЕСЬ") or unlocked and T("GO", "ПОЕХАЛИ") or T("LOCKED", "ЗАКРЫТО"))
		row.Go:SetStyle(isHere and "secondary" or unlocked and "primary" or "secondary")
		row.Go:SetDisabled(isHere or not unlocked or yard == nil or busy)
		-- Owner: dig here / unlock
		local def = Config.Layers[layer]
		local prevUnlocked = layer == 1 or Layout.Unlocked(mask, layer - 1)
		row.Need.Text = ""
		if isOwner and unlocked and digLayer ~= layer then
			row.Dig.Instance.Visible = true
			row.Dig:SetText(T("DIG HERE", "КОПАТЬ ЗДЕСЬ"))
			row.Dig:SetStyle("success")
			row.Dig:SetPrice(nil)
			row.Dig:SetDisabled(busy)
		elseif isOwner and not unlocked and prevUnlocked and def then
			local needLevel = level < (def.Level or 0)
			local needPrestige = layer == 5 and prestige < 1
			if needLevel or needPrestige then
				row.Dig.Instance.Visible = false
				row.Need.Text = needPrestige and T("Needs Prestige 1", "Нужен престиж 1") or (T("Needs level ", "Нужен уровень ") .. tostring(def.Level))
			else
				row.Dig.Instance.Visible = true
				row.Dig:SetText(T("UNLOCK", "ОТКРЫТЬ"))
				row.Dig:SetStyle("gold")
				row.Dig:SetPrice(def.Cost)
				row.Dig:SetDisabled(busy)
			end
		else
			row.Dig.Instance.Visible = false
			if not unlocked and isOwner and not prevUnlocked then
				row.Need.Text = T("Open the depth above first", "Сначала открой глубину выше")
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------------
function Screen.Ride(layer: number, row: any)
	if busy then
		return
	end
	if not State.Ride then
		Kit.Toast(T("The mine is not ready yet", "Шахта ещё не готова"), { Kind = "warn", NoTranslate = true })
		return
	end
	busy = true
	row.Go:SetBusy(true)
	task.spawn(function()
		local ok, message = (State.Ride :: any)(yardId, layer)
		busy = false
		row.Go:SetBusy(false)
		if ok then
			if win and win.IsOpen then
				win:Close("ride")
			end
		else
			Kit.Toast(serverText(message), { Kind = "error", NoTranslate = true })
			Screen.Refresh()
		end
	end)
end

function Screen.SetDigLayer(layer: number, row: any)
	if busy then
		return
	end
	local def = Config.Layers[layer]
	local yard = yardById(yardId)
	local mask = yard and yard:GetAttribute("MineUnlocked") or 1
	local profile = snapshotProfile()
	if profile and type(profile.UnlockedLayers) == "table" then
		mask = Layout.Mask(profile.UnlockedLayers)
	end
	local unlocking = not Layout.Unlocked(mask, layer)
	local function send()
		busy = true
		row.Dig:SetBusy(true)
		task.spawn(function()
			local ok, result = Net.Request("Layer", { Layer = layer })
			busy = false
			row.Dig:SetBusy(false)
			if ok then
				Kit.Toast(T("Dogs now dig at ", "Собаки теперь копают: ") .. Themes.Name(layer, Kit.Lang()), { Kind = "success", NoTranslate = true })
				Net.Snapshot(0)
			else
				Kit.Toast(serverText(result), { Kind = "error", NoTranslate = true })
			end
			Screen.Refresh()
		end)
	end
	if unlocking and def then
		Kit.Confirm(
			T("UNLOCK ", "ОТКРЫТЬ ") .. Themes.Name(layer, Kit.Lang()) .. "?",
			T("Costs ", "Стоит ") .. Kit.Format.Short(def.Cost) .. T(" coins. Your dogs will dig there.", " монет. Собаки начнут копать там."),
			{ ConfirmText = T("UNLOCK", "ОТКРЫТЬ"), NoTranslate = true }
		):Then(function(confirmed)
			if confirmed then
				send()
			end
		end)
	else
		send()
	end
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
local watched: Instance? = nil
local function watchYard(yard: Instance?)
	if watched == yard then
		return
	end
	maid:Clean()
	watched = yard
	if yard then
		for _, key in { "MineLayer", "MineUnlocked", "OwnerUserId", "OwnerDisplayName" } do
			maid:Give(yard:GetAttributeChangedSignal(key):Connect(function()
				if win and win.IsOpen then
					Screen.Refresh()
				end
			end))
		end
	end
	maid:Give(State.Changed:Connect(function()
		if win and win.IsOpen then
			Screen.Refresh()
		end
	end))
	maid:Give(Net.Changed:Connect(function()
		if win and win.IsOpen then
			Screen.Refresh()
		end
	end))
end

function Screen.Open(arg: any)
	if State.Riding then
		return
	end
	if not win then
		build()
	end
	local id = type(arg) == "table" and arg.YardId or nil
	if id == nil then
		id = State.Location.YardId
	end
	if id == nil then
		local own = ownYard()
		id = own and own:GetAttribute("YardId") or nil
	end
	yardId = id
	watchYard(yardById(id))
	Screen.Refresh()
	win:Open()
	task.spawn(function()
		Net.Snapshot(4)
		Screen.Refresh()
	end)
end

function Screen.Close()
	if win and win.IsOpen then
		win:Close()
	end
end

function Screen.IsOpen(): boolean
	return win ~= nil and win.IsOpen == true
end

return Screen
