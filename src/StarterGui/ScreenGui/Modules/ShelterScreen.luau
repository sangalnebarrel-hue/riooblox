-- DOG SHELTER window (Kit, Key = "Shelter"; GUIIntegration.kitScreens.Shelter). The ShelterPrompt in the Welcome Hub
-- opens it through the server's DogEconomyOpen("Shelter") (and at once on the local PromptTriggered, Screen.Watch).
-- Built once:
--   * the list panel: YOUR DOGS count + what the sellable dogs are worth, filter chips (ALL / SELLABLE / PROTECTED),
--     a sort (SELLABLE FIRST / RARITY / PRICE) and a virtual list of dog cards (Kit.DogCard): a lazy 3D preview only
--     for the rows in view, the price chip or the protection icon (🔒 ❤️ ⛏️ 🏠 🏆 ...);
--   * the detail panel: the selected dog, the price breakdown (catalog value × shelter rate × bonus, with the variant /
--     mastery / ascension parts), PROTECTED + the server's reason, REVIEW SALE -> CONFIRM SALE (hold-to-confirm for
--     Mythic / Secret and event dogs, ShelterConfig.HoldRank) with the server price countdown, CANCEL;
--   * loading / error (RETRY) / empty / "visit the shelter" states; one automatic retry for replies that heal by
--     themselves (a lagged visit, a loading profile, an empty request bucket: ShelterModel.Retryable).
-- The list is built once per List reply; a selection only restyles the two affected cards. Phones: the window is a
-- full-screen sheet (Kit), the detail panel slides up over the list (BACK, Escape and gamepad B close it first).
-- Gamepad: B / Escape dismiss the confirm step, then the sheet, then the window; the first card takes the selection.
-- The window closes when the player walks away from the reception (ShelterConfig.InReach, client radius).
-- Server: Economy.ShelterService through ReplicatedStorage.ShelterRequest (List / Quote / Sell). Every reply is
-- checked again there; a Sell whose reply was lost is retried once with the same token (the server answers a sale
-- that went through from its receipt and never pays twice).
-- Self-localized: Localization.Shelter (UI, Templates; server replies through Exact / Patterns of every module).
--   Screen.Open(arg?, page?), Screen.Close(), Screen.IsOpen(), Screen.Watch(), Screen.Internals()
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Kit = require(script.Parent.Kit)
local Base = require(script.Parent.Kit.Base)
local Model = require(script.ShelterModel)
local Config = require(RS:WaitForChild("DogEconomy"):WaitForChild("ShelterConfig"))

local Theme = Kit.Theme
local P = Theme.Colors
local ACCENT = Color3.fromRGB(255, 169, 38) -- UITheme.WindowSpecs.Shelter
local PROTECT = Color3.fromRGB(150, 110, 230)
local COIN = Color3.fromRGB(255, 196, 46)
local EVENT = Color3.fromRGB(255, 128, 24)
local Z = 3
local REQUEST_TIMEOUT = 15
local player = Players.LocalPlayer

local Screen = {}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local Dict: any = { UI = {}, Templates = {}, Exact = {}, Patterns = {} }
do
	local folder = RS:FindFirstChild("Localization")
	local module = folder and folder:FindFirstChild("Shelter")
	if module and module:IsA("ModuleScript") then
		local ok, value = pcall(require, module)
		if ok and type(value) == "table" then
			Dict = value
			Dict.UI = Dict.UI or {}
			Dict.Templates = Dict.Templates or {}
			Dict.Exact = Dict.Exact or {}
			Dict.Patterns = Dict.Patterns or {}
		end
	end
end
local function ru(): boolean
	return Kit.Lang() == "ru"
end
local function T(en: string): string
	if ru() then
		return Dict.UI[en] or en
	end
	return en
end
local function F(fmt: string, ...: any): string
	local pattern = ru() and Dict.Templates[fmt] or fmt
	local ok, text = pcall(string.format, pattern, ...)
	if ok then
		return text
	end
	return string.format(fmt, ...)
end
Screen.T, Screen.F = T, F

-- Server replies: this package's dictionary, then every Localization module's Exact (shared replies such as
-- "Unlock this dog first" live with their own feature), then the shelter patterns.
local shared: { [string]: string }? = nil
local function sharedExact(): { [string]: string }
	if shared then
		return shared
	end
	local merged = {}
	local folder = RS:FindFirstChild("Localization")
	for _, module in ipairs(folder and folder:GetChildren() or {}) do
		if module:IsA("ModuleScript") then
			local ok, dict = pcall(require, module)
			if ok and type(dict) == "table" and type(dict.Exact) == "table" then
				for en, text in pairs(dict.Exact) do
					if type(en) == "string" and type(text) == "string" and merged[en] == nil then
						merged[en] = text
					end
				end
			end
		end
	end
	shared = merged
	return merged
end
local function serverText(message: any): string
	local text = type(message) == "table" and tostring(message.Message or "") or tostring(message or "")
	if not ru() then
		return text
	end
	local own = Dict.Exact[text]
	if own then
		return own
	end
	local other = sharedExact()[text]
	if other then
		return other
	end
	for _, rule in ipairs(Dict.Patterns) do
		local out, n = string.gsub(text, rule[1], rule[2])
		if n > 0 then
			return out
		end
	end
	return text
end
Screen.ServerText = serverText

local function short(n: any): string
	return Kit.Format.Short(math.max(0, math.floor(tonumber(n) or 0)))
end
local function number(n: any): string
	return Kit.Format.Number(math.max(0, math.floor(tonumber(n) or 0)))
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st: any = {
	Rows = {},
	Counts = Model.Counts({}),
	Loaded = false,
	Loading = false,
	Retried = false,
	Filter = "all",
	Sort = "sellable",
	Desc = false,
	Selected = nil, -- uid
	Phase = "review", -- review | quoting | confirm | expired | selling
	Quote = nil,
	Deadline = 0, -- os.clock() deadline of the quote
	LoadToken = 0, -- drops late List replies
	ActionToken = 0, -- drops late Quote / Sell replies
	OpenToken = 0, -- stops the open-window loop
	Mode = "shelter", -- shelter | away (opened far from the reception)
	LocalOpenAt = -100, -- os.clock() of the last local prompt open (the server's open follows it)
	SheetOpen = false,
}
local ui: any = nil

local function isOpen(): boolean
	return ui ~= nil and ui.Window.IsOpen == true
end
Screen.State = st

local function remote(): RemoteFunction?
	local r = RS:FindFirstChild("ShelterRequest") or RS:WaitForChild("ShelterRequest", 10)
	if r and r:IsA("RemoteFunction") then
		return r
	end
	return nil
end

-- InvokeServer with a client timeout. Returns transport (false = no reply), ok, data.
local function invoke(action: string, args: any, timeout: number?): (boolean, boolean, any)
	local fn = remote()
	if not fn then
		return false, false, "NO_REMOTE"
	end
	local thread = coroutine.running()
	local done = false
	task.spawn(function()
		local transport, ok, data = pcall(function()
			return (fn :: RemoteFunction):InvokeServer(action, args)
		end)
		if done then
			return
		end
		done = true
		if transport then
			task.spawn(thread, true, ok == true, data)
		else
			task.spawn(thread, false, false, "CONNECTION")
		end
	end)
	task.delay(timeout or REQUEST_TIMEOUT, function()
		if done then
			return
		end
		done = true
		task.spawn(thread, false, false, "TIMEOUT")
	end)
	return coroutine.yield()
end

local function failureText(transport: boolean, data: any): string
	if not transport then
		if data == "TIMEOUT" then
			return T("The shelter did not answer. Try again.")
		end
		return T("Connection interrupted. Try again.")
	end
	return serverText(data)
end

-- Position of the local character in the reception anchor's space: true when the window may stay open.
local function inReach(): boolean
	local district = workspace:FindFirstChild("DOGROTS_District")
	local hub = district and district:FindFirstChild("32_WelcomeHub")
	local building = hub and hub:FindFirstChild("DogShelter")
	local anchor = building and building:FindFirstChild("SellAnchor")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (anchor and anchor:IsA("BasePart") and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return false
	end
	local offset = anchor.CFrame:PointToObjectSpace(root.Position)
	return Config.InReach(offset.X, offset.Y, offset.Z, true)
end

------------------------------------------------------------------------------------------------
-- Building blocks
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

local function selectedRow(): any
	return Model.Find(st.Rows, st.Selected)
end

local refreshItems: (resetScroll: boolean?) -> ()
local paintDetail: () -> ()
local paintActions: () -> ()
local relayout: () -> ()
local selectDog: (uid: any) -> ()
local closeSheet: (silent: boolean?) -> ()

-- Card data for one row (Kit.DogCard).
local function cardData(row: any): any
	local stats
	if row.Eligible then
		stats = { { Text = "🪙 " .. short(row.Price), Color = Color3.fromRGB(96, 196, 40) } }
	else
		local protection = Model.Protection(row.Protection)
		stats = { { Text = protection.Icon .. " " .. T(protection.Label), Color = PROTECT } }
	end
	return {
		Name = row.Name,
		Rarity = row.Rarity,
		Variant = row.Variant,
		Preview = { Kind = "Dog", DogId = row.DogId, Variant = row.Variant },
		Stats = stats,
		Badge = row.Event and T("EVENT") or nil,
		BadgeColor = EVENT,
		Selected = row.Uid == st.Selected,
		Locked = not row.Eligible,
	}
end

local function bindCard(card: any, row: any)
	card.Row = row
	card:Bind(cardData(row))
	-- Protected rows: a light veil and the protection's own icon instead of the kit lock.
	if not row.Eligible then
		card.Veil.BackgroundColor3 = Theme.White
		card.Veil.BackgroundTransparency = 0.45
		card.Lock.Text = Model.Protection(row.Protection).Icon
	end
end

------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------
local function filterOptions(): { any }
	local c = st.Counts
	return {
		{ Id = "all", Text = T("ALL") .. " · " .. c.all, Color = ACCENT, NoTranslate = true },
		{ Id = "sellable", Text = "✓ " .. T("SELLABLE") .. " · " .. c.sellable, Color = P.green, NoTranslate = true },
		{ Id = "protected", Text = "🔒 " .. T("PROTECTED") .. " · " .. c.protected, Color = PROTECT, NoTranslate = true },
	}
end

local function showState(kind: string?, message: string?)
	if not ui then
		return
	end
	st.StateKind = kind
	local state = ui.State
	if kind == nil then
		state:SetVisible(false)
		ui.StateScrim.Visible = false
		if ui.Spin then
			ui.Spin:Cancel()
			ui.Spin = nil
		end
		state.Icon.Rotation = 0
		return
	end
	ui.StateScrim.Visible = true
	state:SetVisible(true)
	local action = state.Action
	if kind == "loading" or kind == "retrying" then
		state:Set({ Title = kind == "loading" and T("LOADING YOUR DOGS…") or T("RETRYING…"), Body = T("Asking the reception…") })
		action.Instance.Visible = false
		if not ui.Spin then
			ui.Spin = Kit.Motion.Loop(state.Icon, 0.6, { Rotation = 18 })
		end
	else
		if ui.Spin then
			ui.Spin:Cancel()
			ui.Spin = nil
		end
		state.Icon.Rotation = 0
		if kind == "error" then
			state:Set({ Title = T("COULD NOT LOAD YOUR DOGS"), Body = message or "", ActionText = T("RETRY") })
			action.Instance.Visible = true
			Base.GamepadFocus(action.Instance)
		elseif kind == "away" then
			state:Set({ Title = T("VISIT THE DOG SHELTER"), Body = T("Talk to the reception inside the shelter to rehome a dog."), ActionText = T("SHOW THE WAY") })
			action.Instance.Visible = true
			Base.GamepadFocus(action.Instance)
		elseif kind == "empty" then
			state:Set({ Title = T("NO DOGS YET"), Body = T("Adopt your first dog at the DOG LINE.") })
			action.Instance.Visible = false
		end
	end
end

local function stateAction()
	if st.StateKind == "error" then
		st.Retried = false
		Screen.Reload()
	elseif st.StateKind == "away" then
		Screen.Close()
		local ok, nav = pcall(require, script.Parent.GUIIntegration)
		if ok and type(nav) == "table" and type(nav.Navigate) == "function" then
			pcall(nav.Navigate, "Dog Shelter")
		end
	end
end

local function build()
	if ui then
		return
	end
	ui = {}
	local win = Kit.Window.new({
		Key = "Shelter",
		Title = T("DOG SHELTER"),
		Subtitle = T("Find your extra dogs a new home"),
		Accent = ACCENT,
		Icon = "Dogs",
		NoTranslate = true,
		MaxSize = Vector2.new(1080, 760),
		OnClose = function(_, reason)
			Screen._closed(reason)
		end,
	})
	ui.Window = win
	local body = win.Body

	-- List panel ----------------------------------------------------------------------------------
	ui.List = panel(body, "DogList", Theme.White)
	ui.Count = label(ui.List, { Name = "Count", Text = F("YOUR DOGS · %d", 0), TextSize = 20, Scaled = true, MinTextSize = 11 })
	ui.Worth = label(ui.List, { Name = "Worth", Text = "", TextSize = 15, Scaled = true, MinTextSize = 9, AlignX = "Right", Color = Theme.InkMuted, Font = "numeric" })
	ui.Chips = Kit.Chips(ui.List, {
		Name = "Filters",
		Options = filterOptions(),
		Selected = st.Filter,
		AllowNone = false,
		TextSize = 14,
		ZIndex = Z + 1,
		OnChange = function(id)
			st.Filter = id or "all"
			refreshItems(true)
		end,
	})
	ui.Sort = Kit.SortSelect(ui.List, {
		Name = "Sort",
		-- Every sort starts in its natural direction (sellable: cheapest first; rarity / price: best first); the arrow
		-- flips it (ShelterModel.Items).
		Options = {
			{ Id = "sellable", Text = T("SELLABLE FIRST"), NoTranslate = true, Descending = false },
			{ Id = "rarity", Text = T("RARITY"), NoTranslate = true, Descending = false },
			{ Id = "price", Text = T("PRICE"), NoTranslate = true, Descending = false },
		},
		Selected = st.Sort,
		Descending = st.Desc,
		ZIndex = Z + 1,
		OnChange = function(id, desc)
			st.Sort, st.Desc = id, desc == true
			refreshItems(true)
		end,
	})
	ui.GridHost = Kit.New("Frame", { Name = "GridHost", BackgroundTransparency = 1, ZIndex = Z + 1 }, ui.List)
	ui.Grid = Kit.VirtualGrid(ui.GridHost, {
		Name = "Dogs",
		CellSize = Vector2.new(286, 86),
		MaxColumns = 2,
		Gap = 8,
		Padding = 6,
		ZIndex = Z + 1,
		Create = function(frame)
			local card = Kit.DogCard.new(frame)
			card.OnClick = function(c)
				if c.Row then
					selectDog(c.Row.Uid)
				end
			end
			return card
		end,
		Layout = function(card, w, h)
			card:Layout(w, h)
		end,
		Bind = function(card, row)
			bindCard(card, row)
		end,
		Unbind = function(card)
			card.Row = nil
		end,
		Destroy = function(card)
			card:Destroy()
		end,
		Key = function(row)
			return row.Uid
		end,
		Empty = { Icon = "Dogs", Title = T("NO DOGS HERE"), Body = T("Try another filter."), NoTranslate = true },
	})
	-- Loading / error / away / empty: a state card over the list (the scrim keeps the cards from being tapped).
	ui.StateScrim = Kit.New("Frame", { Name = "StateScrim", BackgroundColor3 = Theme.White, BackgroundTransparency = 0.08, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = Z + 8 }, ui.List)
	Kit.Corner(ui.StateScrim, Theme.Radius.Card)
	ui.State = Kit.EmptyState(ui.StateScrim, {
		Name = "State",
		Icon = "Dogs",
		Title = T("LOADING YOUR DOGS…"),
		Body = "",
		ActionText = T("RETRY"),
		NoTranslate = true,
		ZIndex = Z + 9,
		OnAction = stateAction,
	})
	ui.State.Action.Instance:SetAttribute("NoTranslate", true)
	ui.State.Action.Caption:SetAttribute("NoTranslate", true)

	-- Detail panel ----------------------------------------------------------------------------------
	ui.SheetScrim = Kit.New("TextButton", { Name = "SheetScrim", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Backdrop, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Selectable = false, ZIndex = Z + 18 }, body)
	ui.SheetScrim.Activated:Connect(function()
		closeSheet()
	end)
	ui.Detail = panel(body, "Detail", Theme.White)
	ui.Detail.Active = true
	ui.Detail.ClipsDescendants = true
	ui.SheetBar = Kit.New("Frame", { Name = "SheetBar", BackgroundTransparency = 1, ZIndex = Z + 2, Visible = false }, ui.Detail)
	ui.Back = Kit.Button(ui.SheetBar, {
		Name = "Back",
		Text = "◂ " .. T("BACK"),
		Style = "secondary",
		TextSize = 16,
		ZIndex = Z + 3,
		NoTranslate = true,
		OnClick = function()
			closeSheet()
		end,
	})
	ui.Scroll = Kit.New("ScrollingFrame", {
		Name = "DetailScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = ACCENT,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		ZIndex = Z + 1,
	}, ui.Detail)
	local scroll = ui.Scroll
	ui.Name = Kit.Text(scroll, { Name = "DogName", Text = "", TextSize = 26, Scaled = true, MinTextSize = 13, ZIndex = Z + 2 })
	ui.Tags = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, ZIndex = Z + 2 }, scroll)
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) }, ui.Tags)
	ui.RarityTag = Kit.RarityTag(ui.Tags, "Common", { Height = 22, TextSize = 13, LayoutOrder = 1, ZIndex = Z + 3 })
	ui.VariantTag = Kit.VariantTag(ui.Tags, "Normal", { Height = 22, TextSize = 13, LayoutOrder = 2, ZIndex = Z + 3 })
	ui.EventTag = Kit.Pill(ui.Tags, { Name = "EventTag", Text = "🎃 " .. T("EVENT DOG"), Height = 22, TextSize = 13, Color = EVENT, LayoutOrder = 3, ZIndex = Z + 3, NoTranslate = true })
	ui.Stage = Kit.New("Frame", { Name = "PreviewStage", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1, ClipsDescendants = true }, scroll)
	Kit.Corner(ui.Stage, Theme.Radius.Card)
	ui.StageGradient = Kit.New("UIGradient", { Rotation = 90 }, ui.Stage)
	ui.PreviewHolder = Kit.New("Frame", { Name = "PreviewHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = Z + 2 }, ui.Stage)
	ui.Preview = Kit.Preview.Slot(ui.PreviewHolder)
	ui.StatLine = label(scroll, { Name = "Stats", Text = "", TextSize = 14, Scaled = true, MinTextSize = 9, AlignX = "Center", Color = Theme.InkMuted })
	-- Price breakdown: catalog value × shelter rate × bonus = you receive.
	ui.Breakdown = Kit.New("Frame", { Name = "Breakdown", BackgroundColor3 = Theme.SurfaceAlt, BorderSizePixel = 0, ZIndex = Z + 1 }, scroll)
	Kit.Corner(ui.Breakdown, Theme.Radius.Field)
	local function line(name: string, text: string): (any, any)
		local key = label(ui.Breakdown, { Name = name .. "Label", Text = text, TextSize = 14, Scaled = true, MinTextSize = 9, Color = Theme.InkMuted, ZIndex = Z + 2 })
		local value = label(ui.Breakdown, { Name = name .. "Value", Text = "", TextSize = 16, Scaled = true, MinTextSize = 9, AlignX = "Right", Font = "numeric", ZIndex = Z + 2 })
		return key, value
	end
	ui.BaseKey, ui.BaseValue = line("Base", T("CATALOG VALUE"))
	ui.RateKey, ui.RateValue = line("Rate", T("SHELTER RATE"))
	ui.BonusKey, ui.BonusValue = line("Bonus", T("BONUS"))
	ui.BonusParts = label(ui.Breakdown, { Name = "BonusParts", Text = "", TextSize = 12, Scaled = true, MinTextSize = 8, AlignX = "Right", Color = Theme.InkMuted, ZIndex = Z + 2 })
	ui.Divider = Kit.New("Frame", { Name = "Divider", BackgroundColor3 = P.edge, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = Z + 2 }, ui.Breakdown)
	ui.ReceiveKey = label(ui.Breakdown, { Name = "ReceiveLabel", Text = T("YOU RECEIVE"), TextSize = 17, Scaled = true, MinTextSize = 10, ZIndex = Z + 2 })
	ui.ReceiveIcon = Kit.Icon(ui.Breakdown, "Coins", { ZIndex = Z + 2, AnchorPoint = Vector2.new(1, 0.5), Glyph = "🪙" })
	ui.ReceiveValue = label(ui.Breakdown, { Name = "ReceiveValue", Text = "", TextSize = 24, Scaled = true, MinTextSize = 11, AlignX = "Right", Font = "numeric", Color = Color3.fromRGB(70, 160, 30), Stroke = 0.85, ZIndex = Z + 2 })
	-- PROTECTED card.
	ui.Protect = Kit.New("Frame", { Name = "Protected", BackgroundColor3 = Color3.fromRGB(240, 232, 255), BorderSizePixel = 0, ZIndex = Z + 1 }, scroll)
	Kit.Corner(ui.Protect, Theme.Radius.Field)
	Kit.Stroke(ui.Protect, PROTECT, 2, 0.2)
	ui.ProtectIcon = label(ui.Protect, { Name = "Icon", Text = "🔒", TextSize = 30, Scaled = true, MinTextSize = 12, AlignX = "Center", ZIndex = Z + 2 })
	ui.ProtectTitle = label(ui.Protect, { Name = "Title", Text = T("PROTECTED"), TextSize = 17, Scaled = true, MinTextSize = 10, Color = Theme.Darken(PROTECT, 0.25), ZIndex = Z + 2 })
	ui.ProtectReason = label(ui.Protect, { Name = "Reason", Text = "", TextSize = 14, Wrap = true, AlignY = "Top", Color = Theme.Ink, ZIndex = Z + 2 })
	ui.Info = label(scroll, { Name = "Info", Text = T("The dog leaves your pack for good. Your DogDex discovery stays."), TextSize = 14, Wrap = true, AlignX = "Center", AlignY = "Top", Color = Theme.InkMuted })
	-- Placeholder while no dog is selected.
	ui.Placeholder = Kit.EmptyState(ui.Detail, { Name = "Choose", Icon = "Dogs", Title = T("CHOOSE A DOG"), Body = T("Tap a dog to see what the shelter pays for it."), NoTranslate = true, ZIndex = Z + 2 })
	-- Action bar (always visible at the bottom of the panel).
	ui.Actions = Kit.New("Frame", { Name = "Actions", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 4 }, ui.Detail)
	Kit.Corner(ui.Actions, Theme.Radius.Card - 2)
	ui.ActionsLine = Kit.New("Frame", { Name = "Line", BackgroundColor3 = P.edge, BackgroundTransparency = 0.85, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), ZIndex = Z + 5 }, ui.Actions)
	ui.Hint = label(ui.Actions, { Name = "Hint", Text = "", TextSize = 14, Scaled = true, MinTextSize = 9, AlignX = "Center", Color = Theme.InkMuted, ZIndex = Z + 5 })
	ui.Primary = Kit.Button(ui.Actions, {
		Name = "Primary",
		Text = T("REVIEW SALE"),
		Style = "success",
		TextSize = 19,
		ZIndex = Z + 5,
		NoTranslate = true,
		OnClick = function()
			Screen.Primary()
		end,
	})
	ui.Cancel = Kit.Button(ui.Actions, {
		Name = "Cancel",
		Text = T("CANCEL"),
		Style = "secondary",
		TextSize = 17,
		ZIndex = Z + 5,
		NoTranslate = true,
		OnClick = function()
			Screen.CancelQuote()
		end,
	})
	-- Sale result banner over the detail panel.
	ui.Result = Kit.New("Frame", { Name = "Result", BackgroundColor3 = Theme.White, BorderSizePixel = 0, Visible = false, Active = true, ZIndex = Z + 30 }, ui.Detail)
	Kit.Corner(ui.Result, Theme.Radius.Card)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(150, 232, 90), Color3.fromRGB(72, 170, 40)) }, ui.Result)
	ui.ResultScale = Kit.New("UIScale", { Name = "Pop" }, ui.Result)
	ui.ResultTitle = label(ui.Result, { Name = "Title", Text = T("NEW HOME FOUND!"), TextSize = 30, Scaled = true, MinTextSize = 14, AlignX = "Center", Color = Theme.White, Stroke = 0.1, ZIndex = Z + 31 })
	ui.ResultCoins = label(ui.Result, { Name = "Coins", Text = "", TextSize = 34, Scaled = true, MinTextSize = 14, AlignX = "Center", Color = Color3.fromRGB(255, 236, 120), Stroke = 0.1, Font = "numeric", ZIndex = Z + 31 })
	ui.ResultName = Kit.Text(ui.Result, { Name = "DogName", Text = "", TextSize = 20, Scaled = true, MinTextSize = 10, AlignX = "Center", Color = Theme.White, Stroke = 0.3, ZIndex = Z + 31 })

	win.Resized:Connect(function()
		relayout()
	end)
	-- Fresh data while open: the profile projection bumps InventoryRevision (deliveries, other screens).
	win.Maid:Give(player:GetAttributeChangedSignal("InventoryRevision"):Connect(function()
		if not isOpen() or st.Mode ~= "shelter" or not st.Loaded then
			return
		end
		-- Our own sale bumps it too; its fresh List is already on the way.
		if os.clock() < (st.IgnoreRevisionUntil or 0) then
			return
		end
		st.RevisionDirty = os.clock()
	end))
end

------------------------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------------------------
local function sheetMode(): boolean
	return ui ~= nil and ui.Sheet == true
end

local function layoutDetail()
	local w, h = ui.DetailW or 0, ui.DetailH or 0
	if w < 2 or h < 2 then
		return
	end
	local phone = ui.Phone == true
	local pad = phone and 10 or 14
	local top = 0
	ui.SheetBar.Visible = sheetMode()
	if sheetMode() then
		ui.SheetBar.Position = UDim2.fromOffset(pad, 8)
		ui.SheetBar.Size = UDim2.fromOffset(w - pad * 2, 44)
		ui.Back.Instance.Position = UDim2.fromOffset(0, 0)
		ui.Back.Instance.Size = UDim2.fromOffset(math.min(150, w - pad * 2), 44)
		top = 56
	end
	-- Action bar: hint + one or two buttons (>= 46 px touch targets).
	local barH = 46 + 8 + 20 + (phone and 10 or 14)
	ui.Actions.Position = UDim2.fromOffset(2, h - barH - 2)
	ui.Actions.Size = UDim2.fromOffset(w - 4, barH)
	ui.Hint.Position = UDim2.fromOffset(pad, 6)
	ui.Hint.Size = UDim2.fromOffset(w - pad * 2, 18)
	local confirmLayout = ui.Cancel.Instance.Visible
	local buttonsW = w - pad * 2
	if confirmLayout then
		local cancelW = math.floor(buttonsW * 0.34)
		ui.Cancel.Instance.Position = UDim2.fromOffset(pad, 28)
		ui.Cancel.Instance.Size = UDim2.fromOffset(cancelW, 46)
		ui.Primary.Instance.Position = UDim2.fromOffset(pad + cancelW + 8, 28)
		ui.Primary.Instance.Size = UDim2.fromOffset(buttonsW - cancelW - 8, 46)
	else
		ui.Primary.Instance.Position = UDim2.fromOffset(pad, 28)
		ui.Primary.Instance.Size = UDim2.fromOffset(buttonsW, 46)
	end
	-- Scroll content.
	ui.Scroll.Position = UDim2.fromOffset(0, top)
	ui.Scroll.Size = UDim2.fromOffset(w, math.max(10, h - barH - top))
	local inner = w - pad * 2 - 6
	local y = phone and 6 or 12
	ui.Name.Position = UDim2.fromOffset(pad, y)
	ui.Name.Size = UDim2.fromOffset(inner, phone and 28 or 32)
	y += (phone and 28 or 32) + 4
	ui.Tags.Position = UDim2.fromOffset(pad, y)
	ui.Tags.Size = UDim2.fromOffset(inner, 22)
	y += 30
	local viewH = h - barH - top
	local stageH = math.clamp(math.floor(inner * 0.46), 96, 190)
	if viewH < 360 then
		stageH = math.clamp(math.floor(viewH * 0.32), 84, stageH)
	end
	ui.Stage.Position = UDim2.fromOffset(pad, y)
	ui.Stage.Size = UDim2.fromOffset(inner, stageH)
	ui.PreviewHolder.Size = UDim2.fromOffset(stageH - 8, stageH - 8)
	y += stageH + 6
	ui.StatLine.Position = UDim2.fromOffset(pad, y)
	ui.StatLine.Size = UDim2.fromOffset(inner, 18)
	y += 24
	-- Breakdown rows.
	local rowH = 24
	local bw = inner
	local bx = 12
	local by = 8
	for _, pair in ipairs({ { ui.BaseKey, ui.BaseValue }, { ui.RateKey, ui.RateValue }, { ui.BonusKey, ui.BonusValue } }) do
		pair[1].Position = UDim2.fromOffset(bx, by)
		pair[1].Size = UDim2.fromOffset(math.floor((bw - bx * 2) * 0.55), rowH)
		pair[2].Position = UDim2.fromOffset(bx + math.floor((bw - bx * 2) * 0.55), by)
		pair[2].Size = UDim2.fromOffset(bw - bx * 2 - math.floor((bw - bx * 2) * 0.55), rowH)
		by += rowH
	end
	ui.BonusParts.Position = UDim2.fromOffset(bx, by)
	ui.BonusParts.Size = UDim2.fromOffset(bw - bx * 2, 16)
	by += 22
	ui.Divider.Position = UDim2.fromOffset(bx, by)
	ui.Divider.Size = UDim2.fromOffset(bw - bx * 2, 2)
	by += 8
	ui.ReceiveKey.Position = UDim2.fromOffset(bx, by)
	ui.ReceiveKey.Size = UDim2.fromOffset(math.floor((bw - bx * 2) * 0.45), 34)
	ui.ReceiveValue.Position = UDim2.fromOffset(bx + math.floor((bw - bx * 2) * 0.45), by)
	ui.ReceiveValue.Size = UDim2.fromOffset(bw - bx * 2 - math.floor((bw - bx * 2) * 0.45) - 34, 34)
	ui.ReceiveIcon.Position = UDim2.fromOffset(bw - bx, by + 17)
	ui.ReceiveIcon.Size = UDim2.fromOffset(28, 28)
	by += 34 + 8
	ui.Breakdown.Position = UDim2.fromOffset(pad, y)
	ui.Breakdown.Size = UDim2.fromOffset(bw, by)
	y += by + 8
	if ui.Protect.Visible then
		ui.Protect.Position = UDim2.fromOffset(pad, y)
		ui.Protect.Size = UDim2.fromOffset(inner, 70)
		ui.ProtectIcon.Position = UDim2.fromOffset(8, 12)
		ui.ProtectIcon.Size = UDim2.fromOffset(46, 46)
		ui.ProtectTitle.Position = UDim2.fromOffset(62, 8)
		ui.ProtectTitle.Size = UDim2.fromOffset(inner - 72, 22)
		ui.ProtectReason.Position = UDim2.fromOffset(62, 30)
		ui.ProtectReason.Size = UDim2.fromOffset(inner - 72, 36)
		y += 78
	end
	ui.Info.Position = UDim2.fromOffset(pad, y)
	ui.Info.Size = UDim2.fromOffset(inner, 38)
	y += 44
	ui.Scroll.CanvasSize = UDim2.fromOffset(0, y)
	-- Placeholder and result banner.
	ui.Placeholder.Instance.Size = UDim2.new(1, -24, 0, math.min(230, h - barH))
	ui.Placeholder.Instance.Position = UDim2.new(0.5, 0, 0, top + math.floor((h - top) / 2))
	local rw, rh = math.min(w - 24, 420), math.min(h - 24, 200)
	ui.Result.Size = UDim2.fromOffset(rw, rh)
	ui.Result.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.Result.Position = UDim2.new(0.5, 0, 0.5, math.floor(top / 2))
	ui.ResultTitle.Position = UDim2.fromOffset(12, math.floor(rh * 0.1))
	ui.ResultTitle.Size = UDim2.fromOffset(rw - 24, math.floor(rh * 0.26))
	ui.ResultCoins.Position = UDim2.fromOffset(12, math.floor(rh * 0.38))
	ui.ResultCoins.Size = UDim2.fromOffset(rw - 24, math.floor(rh * 0.3))
	ui.ResultName.Position = UDim2.fromOffset(12, math.floor(rh * 0.72))
	ui.ResultName.Size = UDim2.fromOffset(rw - 24, math.floor(rh * 0.18))
end

relayout = function()
	if not ui then
		return
	end
	local layout = ui.Window:GetLayout()
	local w, h = layout.Width, layout.Height
	if w < 2 or h < 2 then
		return
	end
	local phone = layout.Phone == true
	ui.Phone = phone
	local gap = phone and 6 or 10
	-- Side by side when both panels fit; otherwise the detail is a sheet over the list.
	local split = (not phone and w >= 760) or (phone and layout.Landscape and w >= 600)
	local wasSheet = ui.Sheet
	ui.Sheet = not split
	local listW, detailW
	if split then
		detailW = math.clamp(math.floor(w * (phone and 0.47 or 0.42)), 280, 460)
		listW = w - detailW - gap
	else
		listW, detailW = w, w
	end
	ui.List.Position = UDim2.fromOffset(0, 0)
	ui.List.Size = UDim2.fromOffset(listW, h)
	-- List panel: count + worth, filters + sort, the grid.
	local pad = phone and 8 or 12
	local inner = listW - pad * 2
	local y = pad
	ui.Count.Position = UDim2.fromOffset(pad + 2, y)
	ui.Count.Size = UDim2.fromOffset(math.floor(inner * 0.5), 26)
	ui.Worth.Position = UDim2.fromOffset(pad + math.floor(inner * 0.5), y + 4)
	ui.Worth.Size = UDim2.fromOffset(inner - math.floor(inner * 0.5) - 2, 20)
	y += 30
	local sortW = phone and 158 or 196
	if inner - sortW - 8 >= 300 then
		ui.Chips.Instance.Position = UDim2.fromOffset(pad, y + 2)
		ui.Chips.Instance.Size = UDim2.fromOffset(inner - sortW - 8, 36)
		ui.Sort.Instance.Position = UDim2.fromOffset(pad + inner - sortW, y)
		ui.Sort.Instance.Size = UDim2.fromOffset(sortW, 40)
		y += 46
	else
		ui.Chips.Instance.Position = UDim2.fromOffset(pad, y)
		ui.Chips.Instance.Size = UDim2.fromOffset(inner, 36)
		y += 42
		ui.Sort.Instance.Position = UDim2.fromOffset(pad, y)
		ui.Sort.Instance.Size = UDim2.fromOffset(inner, 40)
		y += 46
	end
	ui.GridHost.Position = UDim2.fromOffset(pad - 6, y)
	ui.GridHost.Size = UDim2.fromOffset(inner + 12, math.max(40, h - y - pad + 4))
	ui.StateScrim.Position = UDim2.fromOffset(0, y)
	ui.StateScrim.Size = UDim2.fromOffset(listW, math.max(40, h - y))
	ui.Grid:Relayout()
	-- Detail panel.
	ui.DetailW, ui.DetailH = detailW, h
	ui.Detail.Size = UDim2.fromOffset(detailW, h)
	if split then
		ui.Detail.Position = UDim2.fromOffset(listW + gap, 0)
		ui.Detail.Visible = true
		ui.Detail.ZIndex = Z
		ui.SheetScrim.Visible = false
		if st.SheetOpen then
			st.SheetOpen = false
			if ui.SheetEntry then
				Kit.Overlay.Remove(ui.SheetEntry)
				ui.SheetEntry = nil
			end
		end
	else
		ui.Detail.ZIndex = Z + 20
		ui.SheetScrim.Size = UDim2.fromScale(1, 1)
		if not st.SheetOpen then
			ui.Detail.Visible = false
			ui.SheetScrim.Visible = false
		else
			ui.Detail.Visible = true
			ui.Detail.Position = UDim2.fromOffset(0, 0)
		end
	end
	if wasSheet ~= ui.Sheet then
		paintDetail()
	end
	layoutDetail()
end

------------------------------------------------------------------------------------------------
-- Detail
------------------------------------------------------------------------------------------------
local function openSheet()
	if not sheetMode() or st.SheetOpen then
		return
	end
	st.SheetOpen = true
	ui.Detail.Visible = true
	ui.SheetScrim.Visible = true
	ui.SheetScrim.BackgroundTransparency = 1
	local h = ui.DetailH or 0
	ui.Detail.Position = UDim2.fromOffset(0, h)
	Kit.Motion.Tween(ui.Detail, Theme.Motion.Slide, { Position = UDim2.fromOffset(0, 0) })
	Kit.Motion.Tween(ui.SheetScrim, Theme.Motion.Slide, { BackgroundTransparency = 0.6 })
	ui.SheetEntry = Kit.Overlay.Push({
		Kind = "sheet",
		Dismiss = function()
			ui.SheetEntry = nil
			closeSheet(true)
		end,
	})
	Base.GamepadFocus(ui.Primary.Instance)
end

closeSheet = function(fromOverlay: boolean?)
	if not ui or not st.SheetOpen then
		return
	end
	if st.Phase == "quoting" or st.Phase == "selling" then
		-- A request is in flight for this dog: keep the sheet (the overlay entry comes back).
		if fromOverlay and not ui.SheetEntry and isOpen() then
			ui.SheetEntry = Kit.Overlay.Push({ Kind = "sheet", Dismiss = function()
				ui.SheetEntry = nil
				closeSheet(true)
			end })
		end
		return
	end
	Screen.CancelQuote()
	st.SheetOpen = false
	if ui.SheetEntry and not fromOverlay then
		Kit.Overlay.Remove(ui.SheetEntry)
	end
	ui.SheetEntry = nil
	local h = ui.DetailH or 0
	Kit.Motion.Tween(ui.SheetScrim, Theme.Motion.Close, { BackgroundTransparency = 1 })
	local tween = Kit.Motion.Tween(ui.Detail, Theme.Motion.Close, { Position = UDim2.fromOffset(0, h) })
	local function hide()
		if not st.SheetOpen and sheetMode() then
			ui.Detail.Visible = false
			ui.SheetScrim.Visible = false
		end
	end
	if tween then
		tween.Completed:Connect(hide)
	else
		hide()
	end
	-- Gamepad: back on the dog that was open.
	local previous = st.Selected
	ui.Grid:ForEachVisible(function(card, row)
		if row and row.Uid == previous then
			Base.GamepadFocus(card.Instance)
		end
	end)
end

paintActions = function()
	if not ui then
		return
	end
	local row = selectedRow()
	local primary, cancel = ui.Primary, ui.Cancel
	primary.Props.Hold = nil
	primary:SetBusy(false)
	cancel:SetBusy(false)
	cancel:SetDisabled(false)
	cancel.Instance.Visible = false
	if not row then
		ui.Actions.Visible = false
		return
	end
	ui.Actions.Visible = true
	ui.Hint.TextColor3 = Theme.InkMuted
	if not row.Eligible then
		primary:SetText("🔒 " .. T("PROTECTED"))
		primary:SetStyle("secondary")
		primary:SetDisabled(true)
		ui.Hint.Text = T("Free this dog first to rehome it.")
	elseif st.Phase == "review" or st.Phase == "quoting" then
		primary:SetText(T("REVIEW SALE"))
		primary:SetStyle("success")
		primary:SetDisabled(false)
		primary:SetBusy(st.Phase == "quoting")
		ui.Hint.Text = row.NeedsHold and (row.Event and T("Event dog: you will hold the button to confirm.") or T("Rare dog: you will hold the button to confirm.")) or T("Check the price, then confirm.")
	elseif st.Phase == "confirm" or st.Phase == "selling" then
		cancel.Instance.Visible = true
		primary:SetText(T("CONFIRM SALE"))
		primary:SetStyle(row.NeedsHold and "gold" or "success")
		primary:SetDisabled(false)
		primary.Props.Hold = (st.Quote and st.Quote.NeedsHold) and Config.HoldSeconds or nil
		primary:SetBusy(st.Phase == "selling")
		cancel:SetDisabled(st.Phase == "selling")
	elseif st.Phase == "expired" then
		cancel.Instance.Visible = true
		primary:SetText(T("REVIEW AGAIN"))
		primary:SetStyle("primary")
		primary:SetDisabled(false)
		ui.Hint.Text = T("PRICE EXPIRED")
		ui.Hint.TextColor3 = Theme.Danger
	end
	Screen.Tick()
	layoutDetail()
end

paintDetail = function()
	if not ui then
		return
	end
	local row = selectedRow()
	local visible = row ~= nil
	ui.Scroll.Visible = visible
	ui.Placeholder:SetVisible(not visible)
	if sheetMode() and not visible and st.SheetOpen and not ui.Result.Visible then
		closeSheet()
	end
	if not row then
		ui.Preview:Show(nil)
		paintActions()
		return
	end
	local q = st.Quote and st.Quote.Uid == row.Uid and st.Quote or nil
	local source = q or row
	ui.Name.Text = tostring(row.Name or "")
	ui.RarityTag:SetRarity(row.Rarity)
	ui.VariantTag:SetVariant(row.Variant)
	ui.EventTag:SetVisible(row.Event == true)
	local rarityColor = Theme.RarityColor(row.Rarity)
	ui.StageGradient.Color = ColorSequence.new(rarityColor:Lerp(Theme.White, 0.55), rarityColor:Lerp(Theme.White, 0.85))
	ui.Preview:Show({ Kind = "Dog", DogId = row.DogId, Variant = row.Variant })
	local stats = F("Mastery %d · Ascension %d", math.floor(tonumber(row.Mastery) or 0), math.floor(tonumber(row.AscensionLevel) or 0))
	local serial = tonumber(row.SerialNumber) or 0
	if serial > 0 then
		stats ..= " · #" .. serial
	end
	ui.StatLine.Text = stats
	local b = type(source.Breakdown) == "table" and source.Breakdown or {}
	ui.BaseValue.Text = number(b.Base)
	ui.RateValue.Text = "× " .. Model.Percent(tonumber(b.Rate) or 0)
	ui.BonusValue.Text = Model.Mult(b.Bonus)
	local parts = {}
	for _, part in ipairs(Model.BonusParts(b)) do
		table.insert(parts, F(part.Key, part.Value))
	end
	ui.BonusParts.Text = #parts > 0 and table.concat(parts, " · ") or T("No bonus")
	ui.ReceiveValue.Text = "+" .. number(source.Price)
	ui.ReceiveKey.Text = row.Eligible and T("YOU RECEIVE") or T("WORTH")
	ui.ReceiveValue.TextColor3 = row.Eligible and Color3.fromRGB(70, 160, 30) or Theme.InkMuted
	ui.Protect.Visible = not row.Eligible
	if not row.Eligible then
		local protection = Model.Protection(row.Protection)
		ui.ProtectIcon.Text = protection.Icon
		ui.ProtectTitle.Text = T("PROTECTED") .. " · " .. T(protection.Label)
		ui.ProtectReason.Text = serverText(row.Reason or "")
	end
	ui.Info.Visible = row.Eligible == true
	paintActions()
end

------------------------------------------------------------------------------------------------
-- List
------------------------------------------------------------------------------------------------
refreshItems = function(resetScroll: boolean?)
	if not ui then
		return
	end
	ui.Items = Model.Items(st.Rows, st.Filter, st.Sort, st.Desc)
	ui.Grid:SetItems(ui.Items, { ResetScroll = resetScroll == true })
end

-- Count, worth and the filter chips (rebuilt only when a count changed).
local function paintSummary()
	st.Counts = Model.Counts(st.Rows)
	ui.Count.Text = F("YOUR DOGS · %d", #st.Rows)
	if st.Counts.sellable > 0 then
		ui.Worth.Text = F("SELLABLE %d · WORTH %s", st.Counts.sellable, short(st.Counts.Total))
	else
		ui.Worth.Text = #st.Rows > 0 and T("Every dog is protected") or ""
	end
	local signature = st.Counts.all .. "/" .. st.Counts.sellable .. "/" .. st.Counts.protected
	if ui.ChipSignature ~= signature then
		ui.ChipSignature = signature
		ui.Chips:SetOptions(filterOptions())
		ui.Chips:SetSelected(st.Filter, true)
	end
end

local function applyList(data: any)
	st.Rows = data.Rows
	st.Loaded = true
	paintSummary()
	if st.Selected and not Model.Find(st.Rows, st.Selected) then
		st.Selected = nil
		Screen.CancelQuote()
	end
	refreshItems(false)
	if #st.Rows == 0 then
		showState("empty")
	else
		showState(nil)
	end
	paintDetail()
	if not st.Selected and not st.SheetOpen then
		ui.Grid:ForEachVisible(function(card, _, index)
			if index == 1 then
				Base.GamepadFocus(card.Instance)
			end
		end)
	end
end

-- Loads the list. opts.Quiet: keep the current list on screen (after a sale / a background refresh).
function Screen.Reload(opts: any?)
	if not ui or not isOpen() then
		return
	end
	local o = opts or {}
	st.LoadToken += 1
	local token = st.LoadToken
	st.Loading = true
	st.RevisionDirty = nil
	if not o.Quiet then
		showState(o.Retry and "retrying" or "loading")
	end
	task.spawn(function()
		local transport, ok, data = invoke("List", {}, REQUEST_TIMEOUT)
		if token ~= st.LoadToken or not isOpen() then
			return
		end
		st.Loading = false
		if transport and ok and type(data) == "table" and type(data.Rows) == "table" then
			st.Retried = false
			applyList(data)
			return
		end
		if o.Quiet and st.Loaded then
			return -- the list on screen stays; the next refresh tries again
		end
		local retryable = not transport or Model.Retryable(data)
		if retryable and not st.Retried then
			st.Retried = true
			showState("retrying")
			task.wait(Config.RetryDelay)
			if token ~= st.LoadToken or not isOpen() then
				return
			end
			Screen.Reload({ Retry = true })
			return
		end
		showState("error", failureText(transport, data))
		Kit.Sound.Play("Error")
	end)
end

selectDog = function(uid: any)
	if not ui or uid == nil then
		return
	end
	if st.Phase == "quoting" or st.Phase == "selling" then
		return
	end
	local previous = st.Selected
	if previous ~= uid then
		Screen.CancelQuote()
		st.Selected = uid
		if previous ~= nil then
			ui.Grid:RefreshKey(previous)
		end
		ui.Grid:RefreshKey(uid)
	end
	paintDetail()
	openSheet()
end
Screen.Select = function(uid: any)
	selectDog(uid)
end

------------------------------------------------------------------------------------------------
-- Quote / confirm / sell
------------------------------------------------------------------------------------------------
local function removeConfirmEntry()
	if ui and ui.ConfirmEntry then
		Kit.Overlay.Remove(ui.ConfirmEntry)
		ui.ConfirmEntry = nil
	end
end

function Screen.CancelQuote()
	if not ui then
		return
	end
	if st.Phase == "selling" then
		return
	end
	st.ActionToken += 1
	st.Quote = nil
	st.Deadline = 0
	st.Phase = "review"
	removeConfirmEntry()
	paintActions()
end

local function requestQuote()
	local row = selectedRow()
	if not row or not row.Eligible or st.Phase == "quoting" or st.Phase == "selling" then
		return
	end
	st.Phase = "quoting"
	st.Quote = nil
	removeConfirmEntry()
	paintActions()
	st.ActionToken += 1
	local token = st.ActionToken
	local uid = row.Uid
	task.spawn(function()
		local transport, ok, q = invoke("Quote", { Uid = uid }, REQUEST_TIMEOUT)
		if token ~= st.ActionToken or not isOpen() then
			return
		end
		if transport and ok and type(q) == "table" and q.Uid == uid and type(q.Token) == "string" then
			st.Quote = q
			st.Deadline = Model.Deadline(q, os.clock())
			st.Phase = "confirm"
			-- The quote is the freshest view of this dog: the price the window shows is the reviewed one.
			for k, v in pairs(q) do
				if k ~= "Token" and k ~= "TTL" and k ~= "Expires" and k ~= "ServerNow" then
					row[k] = v
				end
			end
			ui.Grid:RefreshKey(uid)
			ui.ConfirmEntry = Kit.Overlay.Push({
				Kind = "confirm",
				Dismiss = function()
					ui.ConfirmEntry = nil
					Screen.CancelQuote()
				end,
			})
			Kit.Sound.Play("Toggle")
			paintDetail()
			Base.GamepadFocus(ui.Primary.Instance)
			return
		end
		st.Phase = "review"
		paintActions()
		Kit.Toast(failureText(transport, q), { Kind = "error", NoTranslate = true })
		if transport and not ok then
			-- The dog changed under the window (locked elsewhere, put to work...): show the fresh state.
			Screen.Reload({ Quiet = true })
		end
	end)
end

local function finishSale(q: any, result: any)
	st.Quote = nil
	st.Deadline = 0
	st.Phase = "review"
	removeConfirmEntry()
	Kit.Sound.Play("Coin")
	Kit.Toast(serverText(result.Message or ""), { Kind = "success", NoTranslate = true, Duration = 3.2 })
	-- Result banner.
	ui.ResultCoins.Text = F("+%s COINS", number(result.Cash or q.Price))
	ui.ResultName.Text = tostring(result.Name or q.Name or "")
	ui.Result.Visible = true
	ui.ResultScale.Scale = 0.8
	Kit.Motion.Tween(ui.ResultScale, Theme.Motion.Open + 0.08, { Scale = 1 }, Enum.EasingStyle.Back)
	local shownAt = os.clock()
	ui.ResultAt = shownAt
	task.delay(2.2, function()
		if ui and ui.ResultAt == shownAt then
			ui.Result.Visible = false
			if sheetMode() and st.SheetOpen and st.Selected == nil then
				closeSheet()
			end
		end
	end)
	-- The sold dog leaves the list at once; the next dog in view takes the selection (desktop), the fresh List
	-- from the server follows.
	local nextUid = Model.NextUid(ui.Items or {}, q.Uid)
	for i, row in ipairs(st.Rows) do
		if row.Uid == q.Uid then
			table.remove(st.Rows, i)
			break
		end
	end
	paintSummary()
	-- Phones keep the sheet up behind the banner; it slides away when the banner goes (above).
	st.Selected = (not sheetMode()) and nextUid or nil
	refreshItems(false)
	paintDetail()
	st.IgnoreRevisionUntil = os.clock() + 1.5
	Screen.Reload({ Quiet = true })
end

local function requestSell(isRetry: boolean?)
	local q = st.Quote
	if not q then
		return
	end
	if not isRetry and os.clock() > st.Deadline then
		st.Phase = "expired"
		paintActions()
		return
	end
	st.Phase = "selling"
	paintActions()
	st.ActionToken += 1
	local token = st.ActionToken
	local args = { Token = q.Token, Confirm = q.NeedsHold == true }
	task.spawn(function()
		local transport, ok, result = invoke("Sell", args, REQUEST_TIMEOUT)
		if token ~= st.ActionToken then
			return
		end
		if not isOpen() then
			-- The window closed (respawn, another menu) while the sale was on its way: still say what happened.
			st.Phase = "review"
			if transport and ok and type(result) == "table" then
				Kit.Sound.Play("Coin")
				Kit.Toast(serverText(result.Message or ""), { Kind = "success", NoTranslate = true, Duration = 3.2 })
			end
			return
		end
		if transport and ok and type(result) == "table" then
			finishSale(q, result)
			return
		end
		if not transport and not isRetry then
			-- No reply: the sale may have gone through. The same token is answered from the server's receipt.
			st.Phase = "confirm"
			requestSell(true)
			return
		end
		-- Refused (or still no reply): the reviewed price is gone (A07 D12); back to REVIEW SALE with a fresh list.
		st.Quote = nil
		st.Deadline = 0
		st.Phase = "review"
		removeConfirmEntry()
		Kit.Sound.Play("Error")
		Kit.Toast(failureText(transport, result), { Kind = "error", NoTranslate = true })
		paintDetail()
		Screen.Reload({ Quiet = true })
	end)
end

function Screen.Primary()
	if st.Phase == "review" or st.Phase == "expired" then
		requestQuote()
	elseif st.Phase == "confirm" then
		requestSell(false)
	end
end

-- Countdown of the reviewed price (called by the open loop and when the actions repaint).
function Screen.Tick()
	if not ui then
		return
	end
	if st.Phase == "confirm" and st.Quote then
		local left = st.Deadline - os.clock()
		if left <= 0 then
			st.Phase = "expired"
			paintActions()
			return
		end
		local clock = Kit.Format.Clock(left)
		if st.Quote.NeedsHold then
			ui.Hint.Text = "✋ " .. T("HOLD TO CONFIRM") .. " · " .. clock
		else
			ui.Hint.Text = F("Price held for %s", clock)
		end
		ui.Hint.TextColor3 = left < 10 and Theme.Danger or Theme.InkMuted
	end
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
local function startLoop()
	st.OpenToken += 1
	local token = st.OpenToken
	task.spawn(function()
		local misses = 0
		local nextReach = 0
		while st.OpenToken == token and isOpen() do
			task.wait(0.25)
			if st.OpenToken ~= token or not isOpen() then
				break
			end
			local ok, err = pcall(function()
				Screen.Tick()
				local now = os.clock()
				-- A background refresh after an inventory change (debounced, never during a review).
				if st.RevisionDirty and now - st.RevisionDirty > 0.6 and not st.Loading and st.Phase == "review" then
					st.RevisionDirty = nil
					Screen.Reload({ Quiet = true })
				end
				-- Opened far away ("visit the shelter"): walking in loads the list.
				if st.Mode == "away" and now >= nextReach then
					nextReach = now + Config.ClosePoll
					if inReach() then
						st.Mode = "shelter"
						st.Retried = false
						Screen.Reload()
					end
				elseif st.Mode == "shelter" and now >= nextReach then
					nextReach = now + Config.ClosePoll
					if inReach() then
						misses = 0
					else
						misses += 1
						if misses >= 2 and st.Phase ~= "selling" then
							Kit.Toast(T("You walked away from the Dog Shelter"), { Kind = "info", NoTranslate = true })
							Screen.Close()
						end
					end
				end
			end)
			if not ok then
				warn("DOGROTS shelter window: " .. tostring(err))
			end
		end
	end)
end

function Screen.Open(_arg: any?, _page: any?)
	-- The server's DogEconomyOpen follows the local prompt open by one ping: never reopen what was just handled.
	if os.clock() - st.LocalOpenAt < 2 and not st.OpeningLocally then
		return
	end
	build()
	if isOpen() then
		if not st.Loaded and not st.Loading and st.Mode == "shelter" then
			Screen.Reload()
		end
		return
	end
	st.Mode = inReach() and "shelter" or "away"
	st.Retried = false
	st.Phase = "review"
	st.Quote = nil
	st.SheetOpen = false
	ui.Result.Visible = false
	ui.Window:Open()
	relayout()
	paintDetail()
	if st.Mode == "shelter" then
		if st.Loaded then
			-- Last visit's list shows at once (dimmed by the loading card) while the fresh one loads.
			refreshItems(false)
		end
		Screen.Reload()
	else
		showState("away")
	end
	startLoop()
end

-- Window closed (any reason): drop requests in flight, the review and the sheet.
function Screen._closed(_reason: any)
	st.OpenToken += 1
	st.LoadToken += 1
	if st.Phase ~= "selling" then
		st.ActionToken += 1
	end
	st.Loading = false
	st.Quote = nil
	st.Deadline = 0
	st.Phase = "review"
	st.SheetOpen = false
	if ui then
		ui.ConfirmEntry = nil
		ui.SheetEntry = nil
		ui.SheetScrim.Visible = false
		ui.Result.Visible = false
		if ui.Sheet then
			ui.Detail.Visible = false
		end
		showState(nil)
	end
end

function Screen.Close()
	if ui and ui.Window.IsOpen then
		ui.Window:Close("close")
	end
end

function Screen.IsOpen(): boolean
	return isOpen()
end

------------------------------------------------------------------------------------------------
-- The prompt: instant local open, Russian text (server prompts are never auto-translated)
------------------------------------------------------------------------------------------------
local function shelterPrompt(): ProximityPrompt?
	local district = workspace:FindFirstChild("DOGROTS_District")
	local hub = district and district:FindFirstChild("32_WelcomeHub")
	local building = hub and hub:FindFirstChild("DogShelter")
	local anchor = building and building:FindFirstChild("SellAnchor")
	local prompt = anchor and anchor:FindFirstChild("ShelterPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt
	end
	return nil
end

local function localizePrompt(prompt: ProximityPrompt)
	for _, prop in ipairs({ "ActionText", "ObjectText" }) do
		local key = "EnglishText" .. prop
		local en = prompt:GetAttribute(key)
		if type(en) ~= "string" then
			en = (prompt :: any)[prop]
			prompt:SetAttribute(key, en)
		end
		local text = ru() and (Dict.UI[en] or en) or en
		if (prompt :: any)[prop] ~= text then
			(prompt :: any)[prop] = text
		end
	end
end

local watching = false
function Screen.Watch()
	if watching then
		return
	end
	watching = true
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who and who ~= player then
			return
		end
		if prompt ~= shelterPrompt() then
			return
		end
		st.OpeningLocally = true
		local ok, err = pcall(Screen.Open)
		st.OpeningLocally = false
		st.LocalOpenAt = os.clock()
		if not ok then
			warn("DOGROTS shelter window: " .. tostring(err))
		end
	end)
	-- The prompt streams in and out with the hub: re-apply the text to whichever instance is there.
	task.spawn(function()
		local last: ProximityPrompt? = nil
		while true do
			local ok, err = pcall(function()
				local prompt = shelterPrompt()
				if prompt and prompt ~= last then
					last = prompt
					localizePrompt(prompt)
				end
			end)
			if not ok then
				warn("DOGROTS shelter prompt: " .. tostring(err))
			end
			task.wait(3)
		end
	end)
end

-- For the emulation harness and debugging.
function Screen.Internals(): any
	return ui, st
end

return Screen
