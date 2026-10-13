-- Studio-only showcase of the UI kit (StarterGui.ScreenGui.Modules.Kit, docs/UIKIT.md).
-- Does nothing outside Studio. In Studio it starts when the workspace attribute KitDemo is true
-- (set it before Play, or from the command bar during Play: workspace:SetAttribute("KitDemo", true)).
-- K toggles the demo window. Nothing here talks to the server.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local started = false

local function build()
	local player = Players.LocalPlayer
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
	local Kit = require(gui:WaitForChild("Modules"):WaitForChild("Kit")) :: any
	local Theme, Format = Kit.Theme, Kit.Format
	local economy = ReplicatedStorage:WaitForChild("DogEconomy")
	local DogDefinitions = require(economy:WaitForChild("DogDefinitions")) :: any
	local ItemDefinitions = require(economy:WaitForChild("ItemDefinitions")) :: any
	local random = Random.new(7)

	local win = Kit.Window.new({
		Key = "KitDemo",
		Title = "UI KIT",
		Subtitle = "Every component of Modules.Kit",
		Accent = Theme.Colors.purple,
		Icon = "Lab",
		Tabs = {
			{ Id = "controls", Text = "CONTROLS" },
			{ Id = "dogs", Text = "DOGS", Badge = 500 },
			{ Id = "items", Text = "ITEMS" },
			{ Id = "dialogs", Text = "DIALOGS" },
		},
	})

	-- CONTROLS -------------------------------------------------------------------------------
	local controls = win:Page("controls")
	local scroll = Kit.New("ScrollingFrame", {
		Name = "Showcase",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.purple,
		ZIndex = 3,
	}, controls)
	Kit.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, scroll)
	Kit.Padding(scroll, 4, 4, 12, 12)
	local order = 0
	local function section(title: string, height: number): Frame
		order += 1
		Kit.Text(scroll, {
			Name = "Heading",
			Text = title,
			TextSize = 18,
			Color = Theme.InkMuted,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = order,
			ZIndex = 3,
		})
		order += 1
		local frame = Kit.New("Frame", {
			Name = "Section",
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = order,
			ZIndex = 3,
		}, scroll)
		Kit.Corner(frame, Theme.Radius.Card)
		Kit.Stroke(frame, Theme.Colors.edge, 2, 0.6)
		return frame
	end
	local function flow(frame: Frame, gap: number?)
		Kit.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Wraps = true,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap or 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}, frame)
		Kit.Padding(frame, 10, 10, 10, 10)
	end

	local buttons = section("BUTTONS", 128)
	flow(buttons)
	local busy
	Kit.Button(buttons, { Text = "PRIMARY", LayoutOrder = 1, ZIndex = 4, OnClick = function()
		Kit.Toast("Primary clicked")
	end })
	Kit.Button(buttons, { Text = "SECONDARY", Style = "secondary", LayoutOrder = 2, ZIndex = 4, OnClick = function() end })
	Kit.Button(buttons, { Text = "DANGER", Style = "danger", LayoutOrder = 3, ZIndex = 4, OnClick = function() end })
	Kit.Button(buttons, { Text = "GHOST", Style = "ghost", LayoutOrder = 4, ZIndex = 4, OnClick = function() end })
	Kit.Button(buttons, { Text = "BUY", Style = "success", Price = 125000, LayoutOrder = 5, ZIndex = 4, Size = UDim2.fromOffset(200, 46), OnClick = function()
		Kit.Toast("Bought for " .. Format.Short(125000), { Kind = "success" })
	end })
	Kit.Button(buttons, { Text = "SHOP", Style = "gold", Icon = "Shop", LayoutOrder = 6, ZIndex = 4, OnClick = function() end })
	Kit.Button(buttons, { Text = "DISABLED", Disabled = true, LayoutOrder = 7, ZIndex = 4, OnClick = function() end })
	busy = Kit.Button(buttons, { Text = "BUSY 2 S", Style = "primary", LayoutOrder = 8, ZIndex = 4, OnClick = function()
		busy:SetBusy(true)
		task.delay(2, function()
			busy:SetBusy(false)
		end)
	end })
	local tip = Kit.Button(buttons, { Text = "HOVER / HOLD ME", Style = "secondary", LayoutOrder = 9, ZIndex = 4, Size = UDim2.fromOffset(200, 46), OnClick = function() end })
	Kit.Tooltip(tip.Instance, "Tooltips show on hover (mouse), selection (gamepad) or a long press (touch).", { Title = "TOOLTIP" })

	local inputs = section("SEARCH · CHIPS · SORT", 112)
	local state = Kit.Text(inputs, {
		Name = "State",
		TextSize = 14,
		Color = Theme.InkMuted,
		Position = UDim2.new(0, 12, 1, -28),
		Size = UDim2.new(1, -24, 0, 22),
		ZIndex = 4,
		NoTranslate = true,
	})
	local current = { Search = "", Chip = "all", Sort = "rarity", Desc = true }
	local function showState()
		state.Text = string.format("search=%q  chip=%s  sort=%s %s", current.Search, tostring(current.Chip), current.Sort, current.Desc and "desc" or "asc")
	end
	Kit.SearchBox(inputs, { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(0.4, -12, 0, 42), ZIndex = 4, OnChange = function(text)
		current.Search = text
		showState()
	end })
	Kit.Chips(inputs, {
		Position = UDim2.new(0.4, 8, 0, 10),
		Size = UDim2.new(0.6, -250, 0, 42),
		ZIndex = 4,
		Selected = "all",
		AllowNone = false,
		Options = { { Id = "all", Text = "ALL" }, { Id = "working", Text = "WORKING" }, { Id = "storage", Text = "STORAGE" }, { Id = "favorite", Text = "FAVORITES", Color = Theme.Colors.gold } },
		OnChange = function(id)
			current.Chip = id
			showState()
		end,
	})
	Kit.SortSelect(inputs, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(220, 42),
		ZIndex = 4,
		Options = { { Id = "rarity", Text = "RARITY" }, { Id = "power", Text = "POWER" }, { Id = "name", Text = "NAME", Descending = false } },
		OnChange = function(id, descending)
			current.Sort, current.Desc = id, descending
			showState()
		end,
	})
	showState()

	local tags = section("TAGS", 110)
	flow(tags, 6)
	for i, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }) do
		Kit.RarityTag(tags, rarity, { LayoutOrder = i, ZIndex = 4 })
	end
	for i, variant in ipairs({ "Shiny", "Golden", "Corrupted", "Glitched", "Void" }) do
		Kit.VariantTag(tags, variant, { LayoutOrder = 10 + i, ZIndex = 4 })
	end
	for i, mutation in ipairs({ "RAINBOW", "FROZEN", "INFERNAL", "RADIOACTIVE" }) do
		Kit.MutationTag(tags, mutation, { LayoutOrder = 20 + i, ZIndex = 4 })
	end
	Kit.Badge(tags, { Text = "3", LayoutOrder = 30, ZIndex = 4 })
	Kit.Pill(tags, { Text = "NEW", Color = Theme.Colors.green, LayoutOrder = 31, ZIndex = 4 })

	local progress = section("PROGRESS · STATS · COUNTDOWN", 236)
	local bar = Kit.ProgressBar(progress, { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -150, 0, 22), Value = 0.35, Text = "35 / 100", ZIndex = 4 })
	local value = 35
	Kit.Button(progress, { Text = "+10", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(120, 36), ZIndex = 4, OnClick = function()
		value = (value + 10) % 110
		bar:SetValue(value / 100)
		bar:SetText(value .. " / 100")
	end })
	Kit.StatRow(progress, { Label = "DIG SPEED", Value = 12, Next = 15, Format = "short", Icon = "Dig", Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 32), ZIndex = 4 })
	Kit.StatRow(progress, { Label = "INCOME", Value = 1250, Next = 1100, Format = "short", Icon = "Coins", Position = UDim2.fromOffset(12, 82), Size = UDim2.new(1, -24, 0, 32), ZIndex = 4 })
	Kit.StatRow(progress, { Label = "LUCK", Value = 0.12, Next = 0.18, Format = "percent", Icon = "Luck", Position = UDim2.fromOffset(12, 118), Size = UDim2.new(1, -24, 0, 32), ZIndex = 4 })
	Kit.StatRow(progress, { Label = "COOLDOWN", Value = 20, Next = 14, Format = "duration", HigherIsBetter = false, Position = UDim2.fromOffset(12, 154), Size = UDim2.new(1, -24, 0, 32), ZIndex = 4 })
	Kit.Countdown(progress, { EndsAt = Kit.Now() + 95, Prefix = Kit.T("ENDS IN ", "ДО КОНЦА "), Position = UDim2.fromOffset(14, 196), Size = UDim2.new(1, -28, 0, 26), ZIndex = 4 })

	local empty = section("EMPTY STATE", 240)
	Kit.EmptyState(empty, { Icon = "Dogs", Title = "NO DOGS YET", Body = "Adopt your first dog at the Dog Line.", ActionText = "SHOW THE WAY", ZIndex = 4, OnAction = function()
		Kit.Toast("Navigation would start here")
	end })

	-- DOGS -----------------------------------------------------------------------------------
	local species = {}
	for _, def in pairs(DogDefinitions) do
		if type(def) == "table" and def.Id and def.Rank then
			table.insert(species, def)
		end
	end
	table.sort(species, function(a, b)
		return (a.Index or 0) < (b.Index or 0)
	end)
	local variants = { "Normal", "Normal", "Normal", "Normal", "Shiny", "Golden", "Corrupted", "Glitched", "Void" }
	local dogs = {}
	for i = 1, 500 do
		local def = species[random:NextInteger(1, #species)]
		table.insert(dogs, {
			Uid = "dog" .. i,
			DogId = def.Id,
			Name = def.DisplayName or def.Id,
			Rarity = def.Rarity,
			Rank = def.Rank,
			Variant = variants[random:NextInteger(1, #variants)],
			Dig = def.Rank * random:NextNumber(0.6, 1.4),
			Power = def.PowerBudget or 1,
			Mastery = random:NextInteger(0, 5),
			Count = random:NextInteger(1, 10) == 1 and random:NextInteger(2, 4) or 1,
			Locked = random:NextInteger(1, 25) == 1,
		})
	end
	local selected = {}
	local dogsPage = win:Page("dogs")
	local filter = { Text = "", Rarities = {}, Sort = "rarity", Desc = true }
	local dogSearch, dogChips, dogSort, dogGrid
	local function dogCard(d)
		return {
			Id = d.Uid,
			Name = d.Name,
			Rarity = d.Rarity,
			Preview = { Kind = "Dog", DogId = d.DogId, Variant = d.Variant },
			Stats = { { Text = "⛏ " .. Format.Short(d.Dig, 1) .. "/s" }, { Text = Format.Mult(d.Power) } },
			Subtitle = "Mastery " .. d.Mastery,
			Count = d.Count,
			Selected = selected[d.Uid] == true,
			Locked = d.Locked,
			Disabled = d.Locked,
			DisabledReason = d.Locked and "Locked dogs cannot be selected" or nil,
		}
	end
	local function applyDogs(reset: boolean?)
		local list = {}
		local needle = string.lower(filter.Text)
		local any = next(filter.Rarities) ~= nil
		for _, d in ipairs(dogs) do
			if (needle == "" or string.find(string.lower(d.Name), needle, 1, true)) and (not any or filter.Rarities[d.Rarity]) then
				table.insert(list, d)
			end
		end
		table.sort(list, function(a, b)
			local x, y
			if filter.Sort == "name" then
				x, y = a.Name, b.Name
			elseif filter.Sort == "power" then
				x, y = a.Dig, b.Dig
			else
				x, y = a.Rank * 10 + Theme.VariantRank[a.Variant], b.Rank * 10 + Theme.VariantRank[b.Variant]
			end
			if x == y then
				return a.Uid < b.Uid
			end
			if filter.Desc then
				return x > y
			end
			return x < y
		end)
		dogGrid:SetItems(list, { ResetScroll = reset })
		win:SetBadge("dogs", #list)
	end
	dogSearch = Kit.SearchBox(dogsPage, { ZIndex = 3, OnChange = function(text)
		filter.Text = text
		applyDogs(true)
	end })
	local rarityOptions = {}
	for _, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }) do
		table.insert(rarityOptions, { Id = rarity, Text = string.upper(rarity), Color = Theme.RarityColor(rarity) })
	end
	dogChips = Kit.Chips(dogsPage, { Multi = true, Options = rarityOptions, ZIndex = 3, OnChange = function(list)
		filter.Rarities = {}
		for _, id in ipairs(list) do
			filter.Rarities[id] = true
		end
		applyDogs(true)
	end })
	dogSort = Kit.SortSelect(dogsPage, {
		ZIndex = 3,
		Options = { { Id = "rarity", Text = "RARITY" }, { Id = "power", Text = "DIG SPEED" }, { Id = "name", Text = "NAME", Descending = false } },
		OnChange = function(id, descending)
			filter.Sort, filter.Desc = id, descending
			applyDogs(false)
		end,
	})
	dogGrid = Kit.CardGrid(dogsPage, {
		Name = "DogGrid",
		Kind = "Dog",
		ZIndex = 3,
		Map = dogCard,
		Empty = { Icon = "Dogs", Title = Kit.Word("NO_RESULTS"), Body = Kit.Word("TRY_FILTERS") },
		OnClick = function(d)
			selected[d.Uid] = not selected[d.Uid] or nil
			dogGrid:RefreshKey(d.Uid)
		end,
		OnLongPress = function(d)
			Kit.Toast(d.Name .. " · " .. d.Variant .. " · Mastery " .. d.Mastery, { NoTranslate = true })
		end,
	})
	local function layoutDogs(l)
		if l.Phone and not l.Landscape then
			-- Portrait phone: search + sort on one row, chips below.
			dogSearch.Instance.Position = UDim2.new()
			dogSearch.Instance.Size = UDim2.new(1, -134, 0, 40)
			dogSort.Instance.AnchorPoint = Vector2.new(1, 0)
			dogSort.Instance.Position = UDim2.fromScale(1, 0)
			dogSort.Instance.Size = UDim2.fromOffset(128, 40)
			dogChips.Instance.Position = UDim2.fromOffset(0, 44)
			dogChips.Instance.Size = UDim2.new(1, 0, 0, 34)
			dogGrid.Instance.Position = UDim2.fromOffset(0, 82)
			dogGrid.Instance.Size = UDim2.new(1, 0, 1, -82)
		else
			-- Desktop and landscape phone: one toolbar row.
			local searchW, sortW = l.Phone and 200 or 260, l.Phone and 160 or 220
			local h = l.Phone and 38 or 42
			dogSearch.Instance.Position = UDim2.new()
			dogSearch.Instance.Size = UDim2.fromOffset(searchW, h)
			dogChips.Instance.Position = UDim2.fromOffset(searchW + 8, 0)
			dogChips.Instance.Size = UDim2.new(1, -(searchW + sortW + 16), 0, h)
			dogSort.Instance.AnchorPoint = Vector2.new(1, 0)
			dogSort.Instance.Position = UDim2.fromScale(1, 0)
			dogSort.Instance.Size = UDim2.fromOffset(sortW, h)
			dogGrid.Instance.Position = UDim2.fromOffset(0, h + 6)
			dogGrid.Instance.Size = UDim2.new(1, 0, 1, -(h + 6))
		end
	end
	win.Resized:Connect(layoutDogs)
	layoutDogs(win:GetLayout())
	applyDogs(true)

	-- ITEMS ----------------------------------------------------------------------------------
	local items = {}
	local mutations = { "NORMAL", "NORMAL", "NORMAL", "GOLDEN", "RAINBOW", "CURSED", "GLITCHED", "FROZEN" }
	local defs = {}
	for id, def in pairs(ItemDefinitions) do
		if type(def) == "table" then
			table.insert(defs, { Id = id, Def = def })
		end
	end
	table.sort(defs, function(a, b)
		if (a.Def.Depth or 0) ~= (b.Def.Depth or 0) then
			return (a.Def.Depth or 0) < (b.Def.Depth or 0)
		end
		return a.Id < b.Id
	end)
	for i, entry in ipairs(defs) do
		local found = random:NextInteger(1, 5) > 1
		local mutation = mutations[random:NextInteger(1, #mutations)]
		table.insert(items, {
			Id = "item" .. i,
			Name = found and (entry.Def.DisplayName or entry.Id) or "???",
			Rarity = found and (entry.Def.BaseDropChance <= 0.001 and "Epic" or entry.Def.BaseDropChance <= 0.01 and "Rare" or "Common") or nil,
			Preview = { Kind = "Item", ItemId = entry.Id, Mutation = found and mutation or nil, Silhouette = not found },
			Stats = found and { { Text = Format.Short(entry.Def.BaseValue * 10) .. " $" }, { Text = string.format("%.2f kg", entry.Def.BaseWeightKg) } } or nil,
			Count = found and random:NextInteger(0, 4) or nil,
			Subtitle = "Depth " .. tostring(entry.Def.Depth),
		})
	end
	local itemGrid = Kit.CardGrid(win:Page("items"), {
		Name = "ItemGrid",
		Kind = "Item",
		ZIndex = 3,
		CardSize = Vector2.new(140, 190),
		OnClick = function(item)
			Kit.Toast(item.Name, { NoTranslate = true })
		end,
	})
	itemGrid:SetItems(items)

	-- DIALOGS --------------------------------------------------------------------------------
	local dialogs = win:Page("dialogs")
	local grid = Kit.New("Frame", { Name = "Actions", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, dialogs)
	Kit.New("UIGridLayout", { CellSize = UDim2.fromOffset(230, 52), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local result = Kit.Text(dialogs, {
		Name = "Result",
		TextSize = 16,
		Color = Theme.InkMuted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 28),
		ZIndex = 3,
		NoTranslate = true,
	})
	local function action(order: number, text: string, style: string, fn: () -> ())
		Kit.Button(grid, { Text = text, Style = style, LayoutOrder = order, ZIndex = 4, Size = UDim2.fromOffset(230, 52), OnClick = fn })
	end
	action(1, "CONFIRM", "primary", function()
		local ok = Kit.Confirm("BUY 5 TREATS?", "Each treat gives +10% dig speed for 10 minutes.", { ConfirmText = "BUY" }):Await()
		result.Text = "Confirm -> " .. tostring(ok)
	end)
	action(2, "DANGER (HOLD 1 S)", "danger", function()
		local list = {}
		for i = 1, 5 do
			table.insert(list, dogCard(dogs[i]))
		end
		Kit.Confirm("RELEASE 5 DOGS?", "They leave your pack forever. This cannot be undone.", {
			Danger = true,
			Cards = list,
			ConfirmText = "RELEASE",
		}):Then(function(ok)
			result.Text = "Danger -> " .. tostring(ok)
		end)
	end)
	action(3, "ALERT", "secondary", function()
		Kit.Alert("SAVED", "Your showcase layout was saved."):Then(function()
			result.Text = "Alert closed"
		end)
	end)
	action(4, "5 TOASTS", "success", function()
		for i = 1, 5 do
			Kit.Toast("Toast number " .. i, { Kind = ({ "info", "success", "warn", "error", "info" })[i], NoTranslate = true })
		end
	end)
	action(5, "STACKED WINDOW", "gold", function()
		local child = Kit.Window.new({ Key = "KitDemoChild", Title = "DETAILS", Subtitle = "Opened over the demo (Stack)", Accent = Theme.Colors.gold, Stack = true, MaxSize = Vector2.new(560, 420) })
		Kit.EmptyState(child.Body, { Icon = "Star", Title = "STACKED", Body = "Close me to return to the demo." })
		child.Closed:Connect(function()
			task.delay(0.3, function()
				child:Destroy()
			end)
		end)
		child:Open()
	end)
	action(6, "TOGGLE REDUCED MOTION", "secondary", function()
		Kit.Motion.Override = not Kit.Motion.Reduced()
		result.Text = "Reduced motion: " .. tostring(Kit.Motion.Override)
	end)

	win:Open()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.K then
			win:Toggle()
		end
	end)
	return win
end

local function start()
	if started or workspace:GetAttribute("KitDemo") ~= true then
		return
	end
	started = true
	local ok, err = pcall(build)
	if not ok then
		warn("KitDemo failed: " .. tostring(err))
	end
end

workspace:GetAttributeChangedSignal("KitDemo"):Connect(start)
start()
