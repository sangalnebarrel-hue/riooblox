-- MY DOGS window (UI kit, docs/UIKIT.md; spec §8). Shows how good every dog is:
--   * a virtual grid of owned dogs (cards: income / min, digs / min, efficiency), sort (rarity,
--     efficiency, income, dig speed, newest, mastery, name), filters (digging / idle, locked,
--     favourites, rarity, variant) and search (English and translated names);
--   * the dog panel: big preview, rarity, variant, kennel, every stat with an explanation (tap a row),
--     the bonuses on the dog, its ability, the actions (put to work / remove, lock, favourite,
--     display, view in Dogdex, compare) and an ARTIFACTS tab (Modules.Equipment.ArtifactPanel);
--   * COMPARE: pick two dogs, a stacked window puts every stat side by side with the better value
--     marked and an overall winner.
-- Desktop: grid + side panel. Phones: the panel covers the grid (BACK returns).
-- Numbers: Snapshot.DogStats (the server's income model, Rules.IncomeModel). Requests: Assign, Remove,
-- DogLock, DogFavorite, DisplayDog through Modules.Net. Entry points: GUIIntegration routes
-- N.OpenPage('Dogs') / N.OpenScreen('Dogs' | 'DogDetail') here on every device.
-- Text: Localization.Dogs (self-localized labels carry NoTranslate; dog names, rarity and variant tags
-- and server replies stay with DOGROTS_AutoTranslateUI).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Info = require(script.Parent.DogInfo)
local Dict = require(RS:WaitForChild("Localization"):WaitForChild("Dogs"))
local Economy = RS:WaitForChild("DogEconomy")
local Config = require(Economy:WaitForChild("Config"))
local Defs = require(Economy:WaitForChild("DogDefinitions"))
local Bonuses = require(Economy:WaitForChild("Bonuses"))
local Theme, Format = Kit.Theme, Kit.Format
local P = Theme.Colors
local ACCENT = Color3.fromRGB(255, 169, 38) -- UITheme.WindowSpecs.Dogs
local Z = 3

local S = {}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function ru(): boolean
	return Kit.Lang() == "ru"
end
local function T(en: string): string
	if ru() then
		return Dict.UI[en] or Dict.Exact[en] or en
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
-- A server reply in the player's language (this feature's entries; the rest is AutoTranslate's).
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
S.T, S.F, S.Said = T, F, said

local function short(n: any): string
	return Format.Short(tonumber(n) or 0, 1)
end
local function fixed(n: any, decimals: number): string
	local s = string.format("%." .. decimals .. "f", tonumber(n) or 0)
	return s
end
local function pct(fraction: any): string
	local v = (tonumber(fraction) or 0) * 100
	if math.abs(v) < 0.05 then
		return "0%"
	end
	return "+" .. (v >= 10 and string.format("%.0f", v) or string.format("%.1f", v)) .. "%"
end

-- Translated dog names: hidden labels that DOGROTS_AutoTranslateUI translates like any card name.
local probes: { [string]: any } = {}
local function dogName(id: string?): string
	local probe = id and probes[id]
	if probe and probe.Parent then
		return probe.Text
	end
	local def = id and Defs[id]
	return def and def.DisplayName or tostring(id or "")
end
S.DogName = dogName

------------------------------------------------------------------------------------------------
-- Stats shown for a dog: label, value, explanation
------------------------------------------------------------------------------------------------
local function variantTip(): string
	local parts = {}
	for _, v in ipairs(Config.Variants) do
		if (v.Bonus or 0) > 0 then
			table.insert(parts, T(string.upper(v.Name)) .. " " .. pct(v.Bonus))
		end
	end
	return F("Mutated dogs earn more: %s.", table.concat(parts, " · "))
end
local function ascensionTip(): string
	local parts = {}
	for i = 2, #Config.Ascension do
		table.insert(parts, pct(Config.Ascension[i]))
	end
	-- The lab's merge procedure is retired (LabConfig.SimpleMode): ascension stays an earned bonus.
	local ok, LabConfig = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("LabConfig", 2))
	end)
	if ok and type(LabConfig) == "table" and LabConfig.SimpleMode then
		return F("Ascension from earlier lab work: %s income.", table.concat(parts, " / "))
	end
	return F("Raised in the Genetics Lab by merging copies: %s income.", table.concat(parts, " / "))
end
-- {Id, Label, Value(entry) -> text, Tip}
local STAT_ROWS = {
	{
		Id = "income",
		Label = "COINS / MIN",
		Tip = "Coins it earns per minute at your current depth: the loot it digs plus its finds, with every bonus you have.",
		Value = function(e)
			return "$" .. short(e.Stats.CoinsPerMin)
		end,
	},
	{
		Id = "efficiency",
		Label = "EFFICIENCY",
		Tip = "Its income compared with a plain Common dog in your yard (x1.00). The quickest way to compare any two dogs.",
		Value = function(e)
			return "x" .. fixed(e.Stats.Efficiency, 2)
		end,
	},
	{
		Id = "speed",
		Label = "DIGS / MIN",
		Tip = "How many digs it makes per minute. Mastery, dig upgrades and speed bonuses shorten its rest.",
		Value = function(e)
			return fixed(e.Stats.DigsPerMin, 1)
		end,
	},
	{
		Id = "luck",
		Label = "LUCK",
		Tip = "Extra chance of rare loot (artifacts, treasure, space finds) in every roll.",
		Value = function(e)
			return pct((tonumber(e.Stats.LuckPct) or 0) / 100)
		end,
	},
	{
		Id = "finds",
		Label = "FINDS / MIN",
		Tip = "Discoveries (items for your bag) it digs up per minute while your bag has room.",
		Value = function(e)
			return fixed(e.Stats.ItemFindsPerMin, 2)
		end,
	},
	{
		Id = "rest",
		Label = "REST",
		Tip = "Seconds it rests between digs. Each dig itself takes 4 seconds.",
		Value = function(e)
			return F("%s s", fixed(e.Stats.Cooldown, 1))
		end,
	},
	{
		Id = "power",
		Label = "RARITY POWER",
		Tip = function()
			return F("Rarer dogs multiply the value of every loot roll: Common x%s up to Secret x%s.", tostring(Config.Power[1]), tostring(Config.Power[#Config.Power]))
		end,
		Value = function(e)
			return "x" .. tostring(Info.Power(e.Def))
		end,
	},
	{
		Id = "variant",
		Label = "VARIANT BONUS",
		Tip = variantTip,
		Value = function(e)
			return pct(Info.Bonus(e.Dog).Variant)
		end,
	},
	{
		Id = "mastery",
		Label = "MASTERY",
		Tip = "Grows as the dog digs, up to 100: +0.15% income per level and shorter rests.",
		Value = function(e)
			return F("%d / 100", math.floor(tonumber(e.Dog.Mastery) or 0))
		end,
	},
	{
		Id = "ascension",
		Label = "ASCENSION",
		Tip = ascensionTip,
		Value = function(e)
			return F("%d / %d", math.floor(tonumber(e.Dog.AscensionLevel) or 0), #Config.Ascension - 1)
		end,
	},
}
S.StatRows = STAT_ROWS
local catalog: any = nil
local function abilityLabel(id: any): string
	if catalog == nil then
		local ok, value = pcall(function()
			return require(RS:WaitForChild("MuseumCatalog"))
		end)
		catalog = ok and type(value) == "table" and value or false
	end
	local text = tostring(id or "")
	if catalog and type(catalog.AbilityLabel) == "function" then
		local ok, value = pcall(catalog.AbilityLabel, text)
		if ok and type(value) == "string" then
			return value
		end
	end
	return string.upper((text:gsub("(%l)(%u)", "%1 %2")))
end
S.AbilityLabel = abilityLabel

local function tipText(row: any): string
	if type(row.Tip) == "function" then
		return row.Tip()
	end
	return T(row.Tip)
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st: any = {
	Search = "",
	States = {},
	Rarities = {},
	Variant = "Any",
	Sort = "rarity",
	Desc = true,
	Selected = nil, -- DogUid shown in the panel
	Compare = false,
	Picks = {}, -- DogUids picked for COMPARE (max 2)
	Tab = "stats",
	OpenTip = nil, -- stat row whose explanation is expanded
	Busy = false,
	Snapshot = nil,
	Entries = {}, -- uid -> entry
	List = {}, -- filtered + sorted entries shown in the grid
}
S.State = st
local ui: any = nil
local win: any = nil
local compareWin: any = nil
local cmp: any = nil
local openToken = 0

local function profile(): any
	return st.Snapshot and st.Snapshot.Profile or nil
end

------------------------------------------------------------------------------------------------
-- Small building blocks
------------------------------------------------------------------------------------------------
local function panel(parent: Instance, name: string, color: Color3?): any
	local frame = Kit.New("Frame", {
		Name = name,
		BackgroundColor3 = color or Theme.White,
		BorderSizePixel = 0,
		ZIndex = Z,
	}, parent)
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

-- Height of wrapped text (TextService when available, an estimate otherwise).
local function textHeight(text: string, size: number, width: number): number
	if text == "" then
		return 0
	end
	local ok, bounds = pcall(function()
		return game:GetService("TextService"):GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(math.max(10, width), 10000))
	end)
	if ok and typeof(bounds) == "Vector2" and bounds.Y > 0 then
		return math.ceil(bounds.Y) + 4
	end
	local perLine = math.max(1, math.floor(width / (size * 0.52)))
	local chars = utf8.len(text) or #text
	return math.ceil(chars / perLine) * math.ceil(size * 1.25) + 4
end

-- A small dropdown (variant filter): a secondary button that opens a list in a kit popup.
local function dropdown(parent: Instance, props: any): any
	local self: any = { Value = props.Selected, Options = props.Options }
	local function caption(): string
		for _, o in ipairs(self.Options) do
			if o.Id == self.Value then
				return props.Prefix .. o.Text .. "  ▾"
			end
		end
		return props.Prefix .. "▾"
	end
	self.Button = Kit.Button(parent, {
		Name = props.Name,
		Text = caption(),
		Style = "secondary",
		TextSize = 15,
		ZIndex = Z,
		NoTranslate = true,
		OnClick = function()
			self:Open()
		end,
	})
	self.Instance = self.Button.Instance
	function self.Set(_s: any, id: any, silent: boolean?)
		self.Value = id
		self.Button:SetText(caption())
		if not silent and props.OnChange then
			task.spawn(props.OnChange, id)
		end
	end
	function self.Refresh(_s: any)
		self.Button:SetText(caption())
	end
	function self.Open(_s: any)
		if self.Popup then
			return
		end
		local rowH = 40
		local count = #self.Options
		local w = math.max(190, self.Instance.AbsoluteSize.X)
		local h = math.min(count * rowH + 8, 330)
		local entry: any
		local function close()
			if entry then
				Kit.Overlay.Remove(entry)
				entry = nil
			end
			if self.Popup then
				self.Popup:Destroy()
				self.Catcher:Destroy()
				self.Popup = nil
			end
		end
		local popup, catcher = Kit.Overlay.Popup(self.Instance, w, h, close)
		self.Popup, self.Catcher = popup, catcher
		entry = Kit.Overlay.Push({ Dismiss = close, Kind = "popup" })
		local list = Kit.New("ScrollingFrame", {
			Name = "Options",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			CanvasSize = UDim2.fromOffset(0, count * rowH),
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = ACCENT,
			ZIndex = popup.ZIndex + 1,
		}, popup)
		for i, o in ipairs(self.Options) do
			local row = Kit.Text(list, {
				Name = "Option_" .. tostring(o.Id),
				Class = "TextButton",
				Text = o.Text,
				TextSize = 16,
				Color = o.Id == self.Value and ACCENT or Theme.Ink,
				Position = UDim2.fromOffset(0, (i - 1) * rowH),
				Size = UDim2.new(1, 0, 0, rowH - 2),
				ZIndex = popup.ZIndex + 2,
				NoTranslate = o.NoTranslate,
			})
			Kit.Padding(row, o.Color and 30 or 12, 0, 12, 0)
			if o.Color then
				local dot = Kit.New("Frame", {
					Name = "Dot",
					BackgroundColor3 = o.Color,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, -20, 0.5, 0),
					Size = UDim2.fromOffset(12, 12),
					ZIndex = popup.ZIndex + 3,
				}, row)
				Kit.Corner(dot, "pill")
			end
			row.Activated:Connect(function()
				close()
				self:Set(o.Id)
			end)
		end
		popup.Size = UDim2.fromOffset(w, 0)
		Kit.Motion.Tween(popup, Theme.Motion.Fast, { Size = UDim2.fromOffset(w, h) })
		self.ClosePopup = close
	end
	return self
end

------------------------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------------------------
local function capacity(p: any): number
	local attr = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("DogCapacity")
	if type(attr) == "number" and attr > 0 then
		return attr
	end
	return math.min(Config.MaxDogs, 20 + 20 * ((p and p.Upgrades or {}).DogStorage or 0))
end
local function kennels(p: any): number
	local ok, catalog = pcall(function()
		return require(RS:WaitForChild("PlotCatalog"))
	end)
	if ok and catalog and type(catalog.Slots) == "function" then
		local ok2, n = pcall(catalog.Slots, p)
		if ok2 and type(n) == "number" then
			return n
		end
	end
	return 1
end

local function rebuildEntries()
	local p = profile()
	local stats = st.Snapshot and st.Snapshot.DogStats or {}
	local entries = {}
	for uid, d in pairs(p and p.Dogs or {}) do
		if type(d) == "table" then
			entries[uid] = Info.Entry(d, stats[uid], dogName(d.DogId))
		end
	end
	st.Entries = entries
end

local function filterAndSort(): { any }
	local filter = { Query = Info.Fold(st.Search), States = st.States, Rarities = st.Rarities, Variant = st.Variant }
	local list = {}
	for _, e in pairs(st.Entries) do
		if Info.Match(e, filter) then
			table.insert(list, e)
		end
	end
	return Info.SortEntries(list, st.Sort, st.Desc)
end

local function entryCount(): number
	local n = 0
	for _ in pairs(st.Entries) do
		n += 1
	end
	return n
end

local function bestEfficiency(): number
	local best = 0
	for _, e in pairs(st.Entries) do
		best = math.max(best, tonumber(e.Stats.Efficiency) or 0)
	end
	return best
end

------------------------------------------------------------------------------------------------
-- Cards
------------------------------------------------------------------------------------------------
local function effColor(e: number): Color3?
	if e >= 6 then
		return Theme.Rarity.Secret
	elseif e >= 3 then
		return P.gold
	elseif e >= 1.5 then
		return P.green
	end
	return nil
end

local function cardData(e: any): any
	local d, s = e.Dog, e.Stats
	local stats = {}
	if s.CoinsPerMin then
		table.insert(stats, { Text = "$" .. short(s.CoinsPerMin) })
	end
	if s.DigsPerMin then
		table.insert(stats, { Text = "⛏" .. fixed(s.DigsPerMin, 1) })
	end
	if s.Efficiency then
		table.insert(stats, { Text = "x" .. fixed(s.Efficiency, 2), Color = effColor(tonumber(s.Efficiency) or 0) })
	end
	local marks = {}
	local state = Info.State(d)
	if state == "Digging" then
		table.insert(marks, "⛏" .. tostring(Info.Slot(d) or ""))
	elseif state == "Arriving" then
		table.insert(marks, T("ARRIVING"))
	end
	if d.Favorite then
		table.insert(marks, "★")
	end
	if d.Locked then
		table.insert(marks, "🔒")
	end
	local picked = table.find(st.Picks, e.Uid) ~= nil
	return {
		Id = e.Uid,
		Name = d.DisplayName or e.Def.DisplayName or d.DogId,
		Rarity = e.Def.Rarity or d.Rarity,
		Variant = d.Variant,
		Preview = { Kind = "Dog", DogId = d.DogId, Variant = d.Variant },
		Stats = stats,
		Badge = #marks > 0 and table.concat(marks, " ") or nil,
		BadgeColor = state == "Digging" and P.green or (state == "Arriving" and P.blue or P.edge),
		Selected = picked or (not st.Compare and st.Selected == e.Uid),
	}
end

------------------------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------------------------
local refresh: (snapshot: any?) -> ()

-- Sends one request; toasts the reply; refreshes from the reply's snapshot.
local function send(action: string, args: any, button: any?, success: string?): (boolean, any)
	if st.Busy then
		return false, nil
	end
	st.Busy = true
	if button then
		button:SetBusy(true)
	end
	local ok, result = Net.Request(action, args)
	st.Busy = false
	if button then
		button:SetBusy(false)
	end
	local message = type(result) == "table" and result.Message or result
	if ok then
		Kit.Toast(success or said(message), { Kind = "success", NoTranslate = success ~= nil })
	else
		Kit.Toast(said(message), { Kind = "error" })
	end
	if ok and not (type(result) == "table" and result.StateSnapshot) then
		task.spawn(function()
			Net.Snapshot(0)
		end)
	end
	return ok, result
end

local function myYard(): any
	local player = Players.LocalPlayer
	local map = workspace:FindFirstChild("DOGROTS_District")
	local yards = map and map:FindFirstChild("04_PlayerYards")
	if not (player and yards) then
		return nil
	end
	for _, yard in ipairs(yards:GetChildren()) do
		if yard:GetAttribute("YardId") == player:GetAttribute("YardId") and yard:GetAttribute("OwnerUserId") == player.UserId then
			return yard
		end
	end
	return nil
end
local function atStorage(): boolean
	local yard = myYard()
	local anchor = yard and yard:FindFirstChild("StorageAnchor")
	if not anchor then
		return false
	end
	local ok, result = pcall(function()
		return require(RS:WaitForChild("PlotInteractionAccess")).CanUse(Players.LocalPlayer, yard, anchor)
	end)
	return ok and result == true
end
local function navigate(destination: string)
	local ok, N = pcall(function()
		return require(script.Parent.GUIIntegration)
	end)
	if ok and N and type(N.Navigate) == "function" then
		N.Navigate(destination)
	end
end

-- Radio list inside a kit modal: rows {Id, Title, Sub, Disabled}; returns the modal and a getter.
local function pickerModal(title: string, body: string, rows: { any }, selected: any, confirmText: string, onPick: (any) -> ()): any
	local chosen = selected
	local rowH = 52
	local buttons = {}
	local function paint()
		for _, b in ipairs(buttons) do
			local on = b.Row.Id == chosen
			b.Face.BackgroundColor3 = on and Theme.Lighten(ACCENT, 0.72) or Theme.White
			b.Stroke.Color = on and ACCENT or P.edge
			b.Stroke.Transparency = on and 0 or 0.6
			b.Mark.Text = on and "●" or "○"
		end
	end
	local modal = Kit.Modal({
		Title = title,
		Body = body,
		NoTranslate = true,
		ConfirmText = confirmText,
		CancelText = T("CANCEL"),
		Accent = ACCENT,
		ContentHeight = math.min(#rows * (rowH + 6), 4 * (rowH + 6)),
		Content = function(frame, width)
			local scroll = Kit.New("ScrollingFrame", {
				Name = "Choices",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				CanvasSize = UDim2.fromOffset(0, #rows * (rowH + 6)),
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = ACCENT,
				ZIndex = frame.ZIndex,
			}, frame)
			for i, row in ipairs(rows) do
				local button = Kit.New("TextButton", {
					Name = "Choice_" .. tostring(row.Id),
					Text = "",
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, (i - 1) * (rowH + 6)),
					Size = UDim2.new(1, -6, 0, rowH),
					ZIndex = frame.ZIndex + 1,
				}, scroll)
				local face = Kit.New("Frame", { Name = "Face", BackgroundColor3 = Theme.White, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = frame.ZIndex + 1 }, button)
				Kit.Corner(face, Theme.Radius.Small)
				local stroke = Kit.Stroke(face, P.edge, 2, 0.6)
				local mark = label(button, { Name = "Mark", Text = "○", TextSize = 20, AlignX = "Center", Color = ACCENT, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 28, 1, 0), ZIndex = frame.ZIndex + 2 })
				label(button, { Name = "Title", Text = row.Title, TextSize = 17, Scaled = true, MinTextSize = 11, Position = UDim2.fromOffset(40, 5), Size = UDim2.new(1, -50, 0, 22), ZIndex = frame.ZIndex + 2, Color = row.Disabled and Theme.InkMuted or Theme.Ink })
				label(button, { Name = "Sub", Text = row.Sub or "", TextSize = 13, Color = Theme.InkMuted, Position = UDim2.fromOffset(40, 27), Size = UDim2.new(1, -50, 0, 18), ZIndex = frame.ZIndex + 2, NoTranslate = row.SubTranslate ~= true })
				table.insert(buttons, { Row = row, Face = face, Stroke = stroke, Mark = mark })
				button.Activated:Connect(function()
					if row.Disabled then
						Kit.Toast(row.Reason or T("Not available"), { Kind = "warn", NoTranslate = true })
						return
					end
					chosen = row.Id
					paint()
				end)
			end
			paint()
		end,
	})
	modal:Then(function(confirmed)
		if confirmed and chosen ~= nil then
			onPick(chosen)
		end
	end)
	return modal
end

local function occupantOf(p: any, slot: number): any
	for _, d in pairs(p and p.Dogs or {}) do
		if Info.Slot(d) == slot then
			return d
		end
	end
	return nil
end

local function putToWork(e: any, button: any?)
	local p = profile()
	if not p then
		return
	end
	local d = e.Dog
	if Info.State(d) == "Arriving" then
		Kit.Toast(T("Wait until your dog arrives in your yard"), { Kind = "warn", NoTranslate = true })
		return
	end
	local unlocked = kennels(p)
	local rows, first = {}, nil
	for slot = 1, 5 do
		local other = occupantOf(p, slot)
		local row = { Id = slot, Title = F("KENNEL %d", slot) }
		if slot > unlocked then
			row.Disabled = true
			row.Sub = T("Locked: expand your yard to open it")
			row.Reason = T("This kennel is locked: expand your yard first")
		elseif other then
			row.Sub = F("Now: %s · tap ASSIGN to swap", dogName(other.DogId))
		else
			row.Sub = T("Free")
			first = first or slot
		end
		table.insert(rows, row)
	end
	pickerModal(T("PUT TO WORK"), F("Choose a kennel for %s.", dogName(d.DogId)), rows, first or 1, T("ASSIGN"), function(slot)
		task.spawn(function()
			local fresh = profile()
			local other = occupantOf(fresh, slot)
			if other and other.DogUid ~= d.DogUid then
				local ok = send("Remove", { Uid = other.DogUid }, button, F("%s returned to storage", dogName(other.DogId)))
				if not ok then
					return
				end
			end
			send("Assign", { Uid = d.DogUid, Slot = "DigSlot_" .. slot }, button, F("%s digs in kennel %d", dogName(d.DogId), slot))
		end)
	end)
end

local function displaySlotOf(p: any, uid: string): number?
	for key, value in pairs(p and p.DisplayDogs or {}) do
		if value == uid then
			return tonumber(key)
		end
	end
	return nil
end

local function displayDog(e: any, button: any?)
	local p = profile()
	if not p then
		return
	end
	local d = e.Dog
	local current = displaySlotOf(p, d.DogUid)
	if not atStorage() then
		Kit.Confirm(T("DISPLAYS ARE SET AT DOG STORAGE"), T("Dog displays are chosen at DOG STORAGE in your yard. Walk there and open MY DOGS again."), {
			NoTranslate = true,
			ConfirmText = T("SHOW THE WAY"),
			CancelText = T("CANCEL"),
			Accent = ACCENT,
		}):Then(function(go)
			if go then
				navigate("Your yard")
			end
		end)
		return
	end
	if current then
		task.spawn(send, "DisplayDog", { Slot = current, Uid = "" }, button, T("Removed from the display"))
		return
	end
	local rows, first = {}, nil
	for slot = 1, 3 do
		local uid = (p.DisplayDogs or {})[tostring(slot)]
		local other = uid and p.Dogs[uid]
		local row = { Id = slot, Title = F("DISPLAY %d", slot) }
		if other then
			row.Sub = F("Now: %s · it will be replaced", dogName(other.DogId))
		else
			row.Sub = T("Empty")
			first = first or slot
		end
		table.insert(rows, row)
	end
	pickerModal(T("PUT ON DISPLAY"), F("Show %s on a stand in your yard.", dogName(d.DogId)), rows, first or 1, T("PLACE"), function(slot)
		task.spawn(send, "DisplayDog", { Slot = slot, Uid = d.DogUid }, button, F("%s is on display %d", dogName(d.DogId), slot))
	end)
end

------------------------------------------------------------------------------------------------
-- Artifacts tab (Modules.Equipment.ArtifactPanel, see the equipment contract)
------------------------------------------------------------------------------------------------
local artifactModule: any = nil -- the module, or false after it failed to load
local function artifacts(): any
	if artifactModule ~= nil then
		return artifactModule or nil
	end
	local folder = script.Parent:FindFirstChild("Equipment")
	local module = folder and folder:FindFirstChild("ArtifactPanel")
	if not (module and module:IsA("ModuleScript")) then
		return nil -- not in this place (yet): looked up again next time
	end
	local ok, value = pcall(require, module)
	if ok and type(value) == "table" and type(value.Mount) == "function" then
		artifactModule = value
	else
		artifactModule = false
		warn("DogsScreen: ArtifactPanel failed to load: " .. tostring(value))
	end
	return artifactModule or nil
end
-- handle.Update may be a plain function (snapshot) or a method (self, snapshot).
local function updateHandle(handle: any, snapshot: any)
	if type(handle) ~= "table" or type(handle.Update) ~= "function" then
		return
	end
	local arity = 2
	pcall(function()
		arity = (debug.info(handle.Update, "a"))
	end)
	local ok, err
	if arity == 1 then
		ok, err = pcall(handle.Update, snapshot)
	else
		ok, err = pcall(handle.Update, handle, snapshot)
	end
	if not ok then
		warn("DogsScreen: ArtifactPanel.Update: " .. tostring(err))
	end
end
local function destroyHandle(handle: any)
	if type(handle) == "table" and type(handle.Destroy) == "function" then
		local ok, err = pcall(handle.Destroy, handle)
		if not ok then
			warn("DogsScreen: ArtifactPanel.Destroy: " .. tostring(err))
		end
	end
end
local function syncArtifacts()
	if not ui then
		return
	end
	local uid = st.Selected
	local want = uid ~= nil and st.Tab == "artifacts" and win and win.IsOpen
	if ui.ArtifactHandle and (not want or ui.ArtifactUid ~= uid) then
		destroyHandle(ui.ArtifactHandle)
		ui.ArtifactHandle, ui.ArtifactUid = nil, nil
	end
	if not want then
		return
	end
	local module = artifacts()
	ui.ArtifactEmpty.Visible = module == nil
	if module and not ui.ArtifactHandle then
		local ok, handle = pcall(module.Mount, ui.ArtifactHost, { DogUid = uid, Net = Net })
		if ok and type(handle) == "table" then
			ui.ArtifactHandle, ui.ArtifactUid = handle, uid
			updateHandle(handle, st.Snapshot)
		else
			warn("DogsScreen: ArtifactPanel.Mount: " .. tostring(handle))
			ui.ArtifactEmpty.Visible = true
		end
	elseif ui.ArtifactHandle then
		updateHandle(ui.ArtifactHandle, st.Snapshot)
	end
end

------------------------------------------------------------------------------------------------
-- The dog panel
------------------------------------------------------------------------------------------------
local layoutDetail: () -> ()
local fillDetail: () -> ()
local relayout: () -> ()
local refreshList: (resetScroll: boolean?) -> ()

local function buildDetail(body: Instance)
	local d: any = {}
	ui.Detail = d
	local root = panel(body, "DogPanel", Theme.White)
	root.ClipsDescendants = true
	d.Root = root
	d.Back = Kit.Button(root, {
		Name = "Back",
		Text = T("‹ BACK"),
		Style = "secondary",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			S.Select(nil)
		end,
	})
	-- Hero: preview + name + tags + state.
	d.Glow = Kit.New("Frame", { Name = "HeroGlow", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, root)
	Kit.Corner(d.Glow, Theme.Radius.Card)
	d.GlowGradient = Kit.New("UIGradient", { Rotation = 90 }, d.Glow)
	d.Holder = Kit.New("Frame", { Name = "PreviewHolder", BackgroundTransparency = 1, ZIndex = Z + 2 }, root)
	d.Slot = Kit.Preview.Slot(d.Holder)
	d.Name = Kit.Text(root, { Name = "DogName", TextSize = 24, Scaled = true, MinTextSize = 14, ZIndex = Z + 2 })
	d.Tags = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, ZIndex = Z + 2 }, root)
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, d.Tags)
	d.Rarity = Kit.RarityTag(d.Tags, "Common", { Height = 22, TextSize = 13, LayoutOrder = 1, ZIndex = Z + 3 })
	d.Variant = Kit.VariantTag(d.Tags, "Normal", { Height = 22, TextSize = 13, LayoutOrder = 2, ZIndex = Z + 3 })
	d.State = label(root, { Name = "StateLine", TextSize = 15, Color = Theme.InkMuted, Scaled = true, MinTextSize = 10, ZIndex = Z + 2 })
	d.Fav = Kit.Button(root, {
		Name = "Favorite",
		Text = "☆",
		Style = "secondary",
		TextSize = 20,
		ZIndex = Z + 3,
		NoTranslate = true,
		OnClick = function()
			local e = st.Entries[st.Selected]
			if e then
				task.spawn(send, "DogFavorite", { Uid = e.Uid, Enabled = not e.Dog.Favorite }, d.Fav, e.Dog.Favorite and T("Removed from favourites") or T("Added to favourites"))
			end
		end,
	})
	Kit.Tooltip(d.Fav.Instance, function()
		return T("Favourite: find it fast with the ★ FAVOURITES filter."), T("FAVOURITE")
	end)
	d.Lock = Kit.Button(root, {
		Name = "Lock",
		Text = "🔓",
		Style = "secondary",
		TextSize = 18,
		ZIndex = Z + 3,
		NoTranslate = true,
		OnClick = function()
			local e = st.Entries[st.Selected]
			if e then
				task.spawn(send, "DogLock", { Uid = e.Uid, Enabled = not e.Dog.Locked }, d.Lock, e.Dog.Locked and T("Unlocked") or T("Locked: it cannot be traded, listed or used in the lab"))
			end
		end,
	})
	Kit.Tooltip(d.Lock.Instance, function()
		return T("A locked dog cannot be traded, listed, sold to the shelter or used in the lab."), T("LOCK")
	end)
	d.Tabs = Kit.Tabs(root, {
		Name = "DogTabs",
		Tabs = { { Id = "stats", Text = T("STATS"), NoTranslate = true }, { Id = "artifacts", Text = T("ARTIFACTS"), NoTranslate = true } },
		Selected = "stats",
		Accent = ACCENT,
		TextSize = 16,
		ZIndex = Z + 2,
		OnChange = function(id)
			st.Tab = id
			layoutDetail()
			syncArtifacts()
		end,
	})
	-- STATS page: a scroll laid out by fillDetail.
	d.Scroll = Kit.New("ScrollingFrame", {
		Name = "StatsScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = ACCENT,
		ZIndex = Z + 1,
	}, root)
	-- Efficiency hero card.
	d.Eff = Kit.New("Frame", { Name = "Efficiency", BackgroundColor3 = Theme.SurfaceAlt, BorderSizePixel = 0, ZIndex = Z + 1 }, d.Scroll)
	Kit.Corner(d.Eff, Theme.Radius.Small)
	d.EffValue = label(d.Eff, { Name = "Value", TextSize = 30, Font = "numeric", Color = Theme.Ink, ZIndex = Z + 2, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0, 120, 0, 34) })
	d.EffLabel = label(d.Eff, { Name = "Label", Text = T("EFFICIENCY"), TextSize = 15, Color = Theme.InkMuted, ZIndex = Z + 2, Position = UDim2.fromOffset(130, 6), Size = UDim2.new(1, -140, 0, 18), Scaled = true, MinTextSize = 10 })
	d.EffSub = label(d.Eff, { Name = "Sub", TextSize = 13, Color = Theme.InkMuted, ZIndex = Z + 2, Position = UDim2.fromOffset(130, 24), Size = UDim2.new(1, -140, 0, 18), Scaled = true, MinTextSize = 9 })
	d.EffBar = Kit.ProgressBar(d.Eff, { Name = "EffBar", Value = 0, Height = 16, Color = ACCENT, ZIndex = Z + 2, NoTranslate = true })
	d.EffBar.Instance.Position = UDim2.fromOffset(12, 48)
	d.EffBar.Instance.Size = UDim2.new(1, -24, 0, 16)
	-- Stat rows (tap: explanation; hover: tooltip).
	d.Rows = {}
	for _, row in ipairs(STAT_ROWS) do
		local button = Kit.New("TextButton", { Name = "Stat_" .. row.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, d.Scroll)
		Kit.Corner(button, Theme.Radius.Small)
		Kit.Stroke(button, P.edge, 1, 0.82)
		local info = Kit.New("Frame", { Name = "Info", BackgroundColor3 = Theme.Colors.secondary, BorderSizePixel = 0, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(8, 7), ZIndex = Z + 2 }, button)
		Kit.Corner(info, "pill")
		label(info, { Name = "Glyph", Text = "i", TextSize = 13, AlignX = "Center", Font = "numeric", Color = ACCENT, ZIndex = Z + 3 })
		local name = label(button, { Name = "Label", Text = T(row.Label), TextSize = 14, Color = Theme.InkMuted, Scaled = true, MinTextSize = 9, Position = UDim2.fromOffset(32, 0), Size = UDim2.new(0.58, -32, 0, 32), ZIndex = Z + 2 })
		local value = label(button, { Name = "Value", TextSize = 17, Font = "numeric", AlignX = "Right", Scaled = true, MinTextSize = 10, Position = UDim2.new(0.58, 0, 0, 0), Size = UDim2.new(0.42, -10, 0, 32), ZIndex = Z + 2 })
		local tip = label(button, { Name = "Tip", TextSize = 13, Color = Theme.InkMuted, Wrap = true, AlignY = "Top", Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 0), ZIndex = Z + 2 })
		tip.Visible = false
		button.Activated:Connect(function()
			st.OpenTip = st.OpenTip ~= row.Id and row.Id or nil
			fillDetail()
		end)
		Kit.Tooltip(button, function()
			return tipText(row), T(row.Label)
		end)
		d.Rows[row.Id] = { Button = button, Label = name, Value = value, Tip = tip, Row = row }
	end
	d.BonusTitle = label(d.Scroll, { Name = "BonusTitle", Text = T("BONUSES ON THIS DOG"), TextSize = 15, Color = ACCENT })
	d.BonusText = label(d.Scroll, { Name = "BonusText", TextSize = 14, Wrap = true, AlignY = "Top", Rich = true })
	-- "ABILITY · FOOD FINDER" (catalogue wording); Russian: the heading only (ability ids have no
	-- translation, the signature sentence below is translated).
	d.AbilityTitle = label(d.Scroll, { Name = "AbilityTitle", TextSize = 15, Color = ACCENT })
	-- The signature sentence stays translatable (DOGROTS_AutoTranslateUI has the catalogue).
	d.AbilityText = Kit.Text(d.Scroll, { Name = "AbilityText", TextSize = 14, Wrap = true, AlignY = "Top", ZIndex = Z + 1 })
	d.Identity = label(d.Scroll, { Name = "Identity", TextSize = 13, Color = Theme.InkMuted, Wrap = true, AlignY = "Top" })
	-- ARTIFACTS page.
	d.ArtifactPage = Kit.New("Frame", { Name = "ArtifactPage", BackgroundTransparency = 1, ZIndex = Z + 1, Visible = false }, root)
	ui.ArtifactHost = Kit.New("Frame", { Name = "ArtifactHost", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z + 1 }, d.ArtifactPage)
	local empty = Kit.EmptyState(d.ArtifactPage, {
		Icon = "Lab",
		Title = T("NO ARTIFACTS YET"),
		Body = T("Artifacts are not available in this version of the game."),
		ZIndex = Z + 2,
		NoTranslate = true,
	})
	ui.ArtifactEmpty = empty.Instance
	ui.ArtifactEmpty.Visible = false
	-- Actions.
	d.Work = Kit.Button(root, {
		Name = "Work",
		Text = T("PUT TO WORK"),
		Style = "success",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			local e = st.Entries[st.Selected]
			if not e then
				return
			end
			if Info.State(e.Dog) == "Digging" then
				task.spawn(send, "Remove", { Uid = e.Uid }, d.Work, F("%s returned to storage", dogName(e.Dog.DogId)))
			else
				putToWork(e, d.Work)
			end
		end,
	})
	d.Display = Kit.Button(root, {
		Name = "Display",
		Text = T("DISPLAY"),
		Style = "secondary",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			local e = st.Entries[st.Selected]
			if e then
				displayDog(e, d.Display)
			end
		end,
	})
	d.Dex = Kit.Button(root, {
		Name = "ViewInDex",
		Text = T("VIEW IN DEX"),
		Style = "primary",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			local e = st.Entries[st.Selected]
			if e then
				S.ViewInDex(e.Dog.DogId)
			end
		end,
	})
	d.Compare = Kit.Button(root, {
		Name = "CompareWith",
		Text = T("COMPARE"),
		Style = "gold",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			local uid = st.Selected
			if uid then
				S.SetCompare(true, { uid })
			end
		end,
	})
end

-- The team summary on the side panel when no dog is selected (desktop).
local function buildSummary(body: Instance)
	local s: any = {}
	ui.Summary = s
	local root = panel(body, "TeamPanel", Theme.White)
	s.Root = root
	s.Title = label(root, { Name = "Title", Text = T("YOUR TEAM"), TextSize = 22, Color = Theme.Ink })
	s.Rows = {}
	for i, key in ipairs({ "income", "digging", "dogs", "best" }) do
		local row = Kit.New("Frame", { Name = "Row_" .. key, BackgroundColor3 = Theme.SurfaceAlt, BorderSizePixel = 0, ZIndex = Z + 1 }, root)
		Kit.Corner(row, Theme.Radius.Small)
		local l = label(row, { Name = "Label", TextSize = 14, Color = Theme.InkMuted, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 18), ZIndex = Z + 2 })
		local v = label(row, { Name = "Value", TextSize = 20, Font = "numeric", Position = UDim2.fromOffset(12, 22), Size = UDim2.new(1, -24, 0, 24), Scaled = true, MinTextSize = 11, ZIndex = Z + 2 })
		s.Rows[i] = { Root = row, Label = l, Value = v, Key = key }
	end
	s.Best = Kit.Button(root, {
		Name = "ShowBest",
		Text = T("SHOW BEST DOG"),
		Style = "primary",
		TextSize = 15,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			local best, value = nil, -1
			for uid, e in pairs(st.Entries) do
				local v = tonumber(e.Stats.CoinsPerMin) or 0
				if v > value then
					best, value = uid, v
				end
			end
			if best then
				S.Select(best)
				ui.Grid:ScrollToKey(best, true)
			end
		end,
	})
	s.Hint = label(root, { Name = "Hint", TextSize = 14, Color = Theme.InkMuted, Wrap = true, AlignY = "Top" })
	s.Hint.Text = T("Tap a dog to see what it earns, how fast it digs and what makes it strong. Tap any stat for an explanation.")
	s.Legend = label(root, { Name = "Legend", TextSize = 14, Color = Theme.Ink, Wrap = true, AlignY = "Top", Rich = true })
	s.Legend.Text = T("<b>$</b> coins per minute   <b>⛏</b> digs per minute   <b>x</b> efficiency (x1.00 = a plain Common dog)")
end

local function layoutSummary(w: number, h: number)
	local s = ui.Summary
	local pad = 14
	local y = pad
	s.Title.Position = UDim2.fromOffset(pad, y)
	s.Title.Size = UDim2.new(1, -pad * 2, 0, 28)
	y += 36
	for _, row in ipairs(s.Rows) do
		row.Root.Position = UDim2.fromOffset(pad, y)
		row.Root.Size = UDim2.new(1, -pad * 2, 0, 50)
		y += 56
	end
	s.Best.Instance.Position = UDim2.fromOffset(pad, y)
	s.Best.Instance.Size = UDim2.new(1, -pad * 2, 0, 42)
	y += 52
	local inner = w - pad * 2
	local hintH = textHeight(s.Hint.Text, 14, inner)
	s.Hint.Position = UDim2.fromOffset(pad, y)
	s.Hint.Size = UDim2.new(1, -pad * 2, 0, hintH)
	y += hintH + 8
	s.Legend.Position = UDim2.fromOffset(pad, y)
	s.Legend.Size = UDim2.new(1, -pad * 2, 0, math.max(0, h - y - pad))
end

local function fillSummary()
	local s = ui.Summary
	local p = profile()
	local count, digging, best, bestE = 0, 0, nil, -1
	for _, e in pairs(st.Entries) do
		count += 1
		if Info.State(e.Dog) == "Digging" then
			digging += 1
		end
		local v = tonumber(e.Stats.CoinsPerMin) or 0
		if v > bestE then
			best, bestE = e, v
		end
	end
	local income = st.Snapshot and tonumber(st.Snapshot.IncomePerMinute) or 0
	s.Rows[1].Label.Text = T("TEAM INCOME")
	s.Rows[1].Value.Text = F("$%s / min", short(income))
	s.Rows[2].Label.Text = T("DOGS DIGGING")
	s.Rows[2].Value.Text = F("%d / %d kennels", digging, kennels(p))
	s.Rows[3].Label.Text = T("DOGS OWNED")
	s.Rows[3].Value.Text = F("%d / %d", count, capacity(p))
	s.Rows[4].Label.Text = T("BEST EARNER")
	s.Rows[4].Value.Text = best and F("%s · $%s / min", dogName(best.Dog.DogId), short(bestE)) or "—"
	s.Best:SetDisabled(best == nil)
end

local function detailMode(): string
	local layout = win and win:GetLayout()
	if not layout or not layout.Phone then
		return "side"
	end
	return layout.Landscape and "landscape" or "portrait"
end

layoutDetail = function()
	local d = ui and ui.Detail
	if not d then
		return
	end
	local size = d.Root.AbsoluteSize
	local w, h = math.max(1, ui.PanelW or size.X), math.max(1, ui.PanelH or size.Y)
	local mode = detailMode()
	local pad = mode == "side" and 12 or 10
	d.Back.Instance.Visible = mode ~= "side"
	local colW = w - pad * 2
	local leftW = mode == "landscape" and math.floor(math.min(330, w * 0.44)) or colW
	local y = pad
	if mode ~= "side" then
		d.Back.Instance.Position = UDim2.fromOffset(pad, y)
		d.Back.Instance.Size = UDim2.fromOffset(110, 38)
	end
	local heroTop = mode ~= "side" and (y + 46) or y
	local previewSize = mode == "landscape" and math.min(96, h * 0.32) or (mode == "side" and 116 or 120)
	if mode == "landscape" then
		heroTop = y + 44
	end
	d.Glow.Position = UDim2.fromOffset(pad, heroTop)
	d.Glow.Size = UDim2.fromOffset(previewSize, previewSize)
	d.Holder.Position = UDim2.fromOffset(pad + 4, heroTop + 4)
	d.Holder.Size = UDim2.fromOffset(previewSize - 8, previewSize - 8)
	local textX = pad + previewSize + 10
	local textW = leftW - previewSize - 10
	local iconW = 40
	d.Name.Position = UDim2.fromOffset(textX, heroTop + 2)
	d.Name.Size = UDim2.fromOffset(math.max(40, textW - iconW * 2 - 8), 30)
	d.Fav.Instance.Size = UDim2.fromOffset(iconW, 36)
	d.Lock.Instance.Size = UDim2.fromOffset(iconW, 36)
	d.Fav.Instance.Position = UDim2.fromOffset(textX + textW - iconW * 2 - 4, heroTop)
	d.Lock.Instance.Position = UDim2.fromOffset(textX + textW - iconW, heroTop)
	d.Tags.Position = UDim2.fromOffset(textX, heroTop + 38)
	d.Tags.Size = UDim2.fromOffset(textW, 24)
	d.State.Position = UDim2.fromOffset(textX, heroTop + 66)
	d.State.Size = UDim2.fromOffset(textW, 20)
	local heroBottom = heroTop + previewSize
	-- Actions: 2 x 2 buttons.
	local btnH = 42
	local gap = 8
	local actionsH = btnH * 2 + gap
	local actionsW = leftW
	local actionsX, actionsY
	if mode == "landscape" then
		actionsX, actionsY = pad, heroBottom + 10
		actionsH = math.min(actionsH, h - actionsY - pad)
		btnH = math.max(34, math.floor((actionsH - gap) / 2))
	else
		actionsX, actionsY = pad, h - pad - actionsH
	end
	local half = math.floor((actionsW - gap) / 2)
	d.Work.Instance.Position = UDim2.fromOffset(actionsX, actionsY)
	d.Display.Instance.Position = UDim2.fromOffset(actionsX + half + gap, actionsY)
	d.Dex.Instance.Position = UDim2.fromOffset(actionsX, actionsY + btnH + gap)
	d.Compare.Instance.Position = UDim2.fromOffset(actionsX + half + gap, actionsY + btnH + gap)
	for _, b in ipairs({ d.Work, d.Display, d.Dex, d.Compare }) do
		b.Instance.Size = UDim2.fromOffset(half, btnH)
	end
	-- Tabs and pages.
	local contentX, contentW, contentTop, contentBottom
	if mode == "landscape" then
		contentX = pad + leftW + 12
		contentW = w - contentX - pad
		contentTop = pad
		contentBottom = h - pad
	else
		contentX = pad
		contentW = colW
		contentTop = heroBottom + 10
		contentBottom = actionsY - 8
	end
	d.Tabs.Instance.Position = UDim2.fromOffset(contentX, contentTop)
	d.Tabs.Instance.Size = UDim2.fromOffset(contentW, 38)
	local pageTop = contentTop + 44
	local pageH = math.max(40, contentBottom - pageTop)
	d.Scroll.Position = UDim2.fromOffset(contentX, pageTop)
	d.Scroll.Size = UDim2.fromOffset(contentW, pageH)
	d.ArtifactPage.Position = UDim2.fromOffset(contentX, pageTop)
	d.ArtifactPage.Size = UDim2.fromOffset(contentW, pageH)
	d.Scroll.Visible = st.Tab ~= "artifacts"
	d.ArtifactPage.Visible = st.Tab == "artifacts"
	d.ContentW = contentW
	fillDetail()
end

fillDetail = function()
	local d = ui and ui.Detail
	if not d then
		return
	end
	local e = st.Selected and st.Entries[st.Selected]
	if not e then
		return
	end
	local dog, def = e.Dog, e.Def
	local rarityColor = Theme.RarityColor(def.Rarity or dog.Rarity)
	local gradient = Theme.RarityGradient[def.Rarity or dog.Rarity]
	local top = gradient and gradient[1] or rarityColor
	d.GlowGradient.Color = ColorSequence.new(top:Lerp(Theme.White, 0.45), Theme.White)
	d.Slot:Show({ Kind = "Dog", DogId = dog.DogId, Variant = dog.Variant })
	d.Name.Text = dog.DisplayName or def.DisplayName or dog.DogId
	d.Rarity:SetRarity(def.Rarity or dog.Rarity)
	d.Variant:SetVariant(dog.Variant)
	local state = Info.State(dog)
	local stateText
	if state == "Digging" then
		stateText = F("⛏ DIGGING IN KENNEL %d", Info.Slot(dog) or 0)
	elseif state == "Arriving" then
		stateText = T("ARRIVING FROM THE DOG LINE")
	else
		stateText = T("IDLE · NOT EARNING")
	end
	local p = profile()
	local shown = p and displaySlotOf(p, dog.DogUid)
	if shown then
		stateText ..= " · " .. F("DISPLAY %d", shown)
	end
	d.State.Text = stateText
	d.State.TextColor3 = state == "Digging" and Color3.fromRGB(74, 170, 22) or Theme.InkMuted
	d.Fav:SetText(dog.Favorite and "★" or "☆")
	d.Fav:SetStyle(dog.Favorite and "gold" or "secondary")
	d.Lock:SetText(dog.Locked and "🔒" or "🔓")
	d.Lock:SetStyle(dog.Locked and "primary" or "secondary")
	d.Work:SetText(state == "Digging" and T("REMOVE FROM KENNEL") or T("PUT TO WORK"))
	d.Work:SetStyle(state == "Digging" and "danger" or "success")
	d.Work:SetDisabled(state == "Arriving")
	d.Display:SetText(shown and T("TAKE OFF DISPLAY") or T("DISPLAY"))
	d.Display:SetDisabled(state == "Arriving")
	-- Efficiency hero.
	local s = e.Stats
	local eff = tonumber(s.Efficiency) or 0
	local best = bestEfficiency()
	d.EffValue.Text = "x" .. fixed(eff, 2)
	d.EffValue.TextColor3 = effColor(eff) or Theme.Ink
	d.EffSub.Text = best > 0 and eff >= best - 1e-6 and T("Your most efficient dog") or F("%d%% of your best dog", math.floor(eff / math.max(best, 1e-6) * 100 + 0.5))
	d.EffBar:SetValue(best > 0 and eff / best or 0)
	-- Stat rows.
	local w = d.ContentW or d.Scroll.AbsoluteSize.X
	local inner = math.max(60, w - 8)
	local y = 0
	d.Eff.Position = UDim2.fromOffset(0, y)
	d.Eff.Size = UDim2.fromOffset(inner, 72)
	y += 80
	for _, row in ipairs(STAT_ROWS) do
		local r = d.Rows[row.Id]
		r.Value.Text = row.Value(e)
		local open = st.OpenTip == row.Id
		local tipH = 0
		if open then
			r.Tip.Text = tipText(row)
			tipH = textHeight(r.Tip.Text, 13, inner - 20) + 6
		end
		r.Tip.Visible = open
		r.Tip.Size = UDim2.new(1, -20, 0, tipH)
		r.Button.Position = UDim2.fromOffset(0, y)
		r.Button.Size = UDim2.fromOffset(inner, 32 + tipH)
		y += 32 + tipH + 5
	end
	-- Bonuses on this dog.
	local bonus = Info.Bonus(dog)
	local lines = {
		F("Rarity power <b>x%s</b> on every loot roll", tostring(Info.Power(def))),
	}
	if bonus.Variant > 0 then
		table.insert(lines, F("Variant <b>%s</b> income", pct(bonus.Variant)))
	end
	if bonus.Mastery > 0 then
		table.insert(lines, F("Mastery <b>%s</b> income", pct(bonus.Mastery)))
	end
	if bonus.Ascension > 0 then
		table.insert(lines, F("Ascension <b>%s</b> income", pct(bonus.Ascension)))
	end
	local okDog, own = pcall(Bonuses.Dog, p or {}, dog, Kit.Now())
	if okDog and type(own) == "table" then
		local names = {
			DigSpeed = T("Dig speed"),
			Luck = T("Luck"),
			Income = T("Income"),
			MoneyMult = T("Money"),
			RareFind = T("Rare finds"),
			ItemMutation = T("Item mutations"),
			DogPower = T("Dog power"),
			XP = T("XP"),
		}
		for _, key in ipairs(Bonuses.Keys) do
			local v = tonumber(own[key]) or 0
			if names[key] and math.abs(v) > 1e-6 then
				table.insert(lines, F("%s <b>%s</b> (artifacts)", names[key], pct(v)))
			end
		end
	end
	d.BonusTitle.Position = UDim2.fromOffset(2, y + 4)
	d.BonusTitle.Size = UDim2.fromOffset(inner, 20)
	y += 26
	d.BonusText.Text = "• " .. table.concat(lines, "\n• ")
	local bonusH = #lines * 19 + 6
	d.BonusText.Position = UDim2.fromOffset(4, y)
	d.BonusText.Size = UDim2.fromOffset(inner - 6, bonusH)
	y += bonusH + 8
	-- Ability.
	d.AbilityTitle.Text = ru() and T("ABILITY") or ("ABILITY · " .. abilityLabel(def.Ability or dog.Ability))
	d.AbilityTitle.Position = UDim2.fromOffset(2, y)
	d.AbilityTitle.Size = UDim2.fromOffset(inner, 20)
	y += 24
	d.AbilityText.Text = def.Signature or ""
	local abilityH = textHeight(d.AbilityText.Text, 14, inner - 6)
	d.AbilityText.Position = UDim2.fromOffset(4, y)
	d.AbilityText.Size = UDim2.fromOffset(inner - 6, abilityH)
	y += abilityH + 8
	-- Identity.
	local idParts = {}
	if (tonumber(dog.SerialNumber) or 0) > 0 then
		table.insert(idParts, string.format("#%06d", dog.SerialNumber))
	end
	if dog.Edition == "First Edition" then
		table.insert(idParts, T("FIRST EDITION"))
	end
	if dog.CreatedAt then
		local t = os.date("!*t", math.floor(tonumber(dog.CreatedAt) or 0))
		if type(t) == "table" then
			table.insert(idParts, F("Since %s", string.format("%04d-%02d-%02d", t.year, t.month, t.day)))
		end
	end
	d.Identity.Text = table.concat(idParts, " · ")
	d.Identity.Position = UDim2.fromOffset(4, y)
	d.Identity.Size = UDim2.fromOffset(inner - 6, 18)
	y += 26
	d.Scroll.CanvasSize = UDim2.fromOffset(0, y)
end

------------------------------------------------------------------------------------------------
-- Compare window
------------------------------------------------------------------------------------------------
local function compareLabels(): any
	return {
		income = T("COINS / MIN"),
		efficiency = T("EFFICIENCY"),
		speed = T("DIGS / MIN"),
		luck = T("LUCK"),
		finds = T("FINDS / MIN"),
		power = T("RARITY POWER"),
		variant = T("VARIANT BONUS"),
		mastery = T("MASTERY"),
		ascension = T("ASCENSION"),
	}
end
local function compareValue(id: string, v: number): string
	if id == "income" then
		return "$" .. short(v)
	elseif id == "efficiency" then
		return "x" .. fixed(v, 2)
	elseif id == "speed" then
		return fixed(v, 1)
	elseif id == "luck" then
		return pct(v / 100)
	elseif id == "finds" then
		return fixed(v, 2)
	elseif id == "power" then
		return "x" .. tostring(v)
	elseif id == "variant" then
		return pct(v)
	elseif id == "mastery" then
		return tostring(math.floor(v))
	end
	return tostring(math.floor(v))
end
-- How much better the better side is ("+$84.6K", "+0.30", "+5%"...).
local function compareDelta(id: string, diff: number): string
	diff = math.abs(diff)
	if id == "income" then
		return "+$" .. short(diff)
	elseif id == "efficiency" then
		return "+" .. fixed(diff, 2)
	elseif id == "speed" then
		return "+" .. fixed(diff, 1)
	elseif id == "luck" then
		return pct(diff / 100)
	elseif id == "finds" then
		return "+" .. fixed(diff, 2)
	elseif id == "power" then
		return "+" .. tostring(math.floor(diff * 10 + 0.5) / 10)
	elseif id == "variant" then
		return pct(diff)
	end
	return "+" .. tostring(math.floor(diff + 0.5))
end
S.CompareDelta = compareDelta

local layoutCompare: () -> ()
local fillCompare: () -> ()

local function buildCompare()
	compareWin = Kit.Window.new({
		Key = "DogCompare",
		Title = T("COMPARE DOGS"),
		Subtitle = T("Green = better. The crown marks the dog that earns more."),
		Accent = ACCENT,
		Icon = "Dogs",
		Stack = true,
		NoTranslate = true,
		MaxSize = Vector2.new(780, 740),
		OnClose = function()
			if win and win.IsOpen then
				refreshList(false)
			end
		end,
	})
	cmp = { Sides = {}, Rows = {} }
	local body = compareWin.Body
	cmp.Verdict = label(body, { Name = "Verdict", TextSize = 17, Rich = true, AlignX = "Center", Wrap = true })
	for _, side in ipairs({ "a", "b" }) do
		local s: any = {}
		s.Root = panel(body, "Side_" .. side, Theme.White)
		s.Glow = Kit.New("Frame", { Name = "Glow", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, s.Root)
		Kit.Corner(s.Glow, Theme.Radius.Card - 4)
		s.Gradient = Kit.New("UIGradient", { Rotation = 90 }, s.Glow)
		s.Holder = Kit.New("Frame", { Name = "PreviewHolder", BackgroundTransparency = 1, ZIndex = Z + 2 }, s.Root)
		s.Slot = Kit.Preview.Slot(s.Holder)
		s.Name = Kit.Text(s.Root, { Name = "DogName", TextSize = 19, Scaled = true, MinTextSize = 11, AlignX = "Center", ZIndex = Z + 2 })
		s.Tags = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, ZIndex = Z + 2 }, s.Root)
		Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, s.Tags)
		s.Rarity = Kit.RarityTag(s.Tags, "Common", { Height = 20, TextSize = 12, LayoutOrder = 1, ZIndex = Z + 3 })
		s.Variant = Kit.VariantTag(s.Tags, "Normal", { Height = 20, TextSize = 12, LayoutOrder = 2, ZIndex = Z + 3 })
		s.Crown = Kit.Pill(s.Root, { Name = "Winner", Text = T("👑 BETTER"), Color = P.gold, Height = 24, TextSize = 13, ZIndex = Z + 4, NoTranslate = true })
		s.Details = Kit.Button(s.Root, {
			Name = "Details",
			Text = T("DETAILS"),
			Style = "secondary",
			TextSize = 14,
			ZIndex = Z + 2,
			NoTranslate = true,
			OnClick = function()
				local uid = cmp.Uids and cmp.Uids[side == "a" and 1 or 2]
				compareWin:Close("details")
				if uid then
					S.SetCompare(false)
					S.Select(uid)
				end
			end,
		})
		cmp.Sides[side] = s
	end
	cmp.Table = Kit.New("ScrollingFrame", {
		Name = "Table",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = ACCENT,
		ZIndex = Z,
	}, body)
	local names = compareLabels()
	for i, spec in ipairs(Info.CompareRows) do
		local row = Kit.New("Frame", { Name = "Row_" .. spec.Id, BackgroundColor3 = i % 2 == 0 and Theme.SurfaceAlt or Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, cmp.Table)
		Kit.Corner(row, Theme.Radius.Small)
		local a = label(row, { Name = "A", TextSize = 17, Font = "numeric", AlignX = "Center", Rich = true, Scaled = true, MinTextSize = 10, ZIndex = Z + 2 })
		local name = label(row, { Name = "Label", Text = names[spec.Id], TextSize = 14, Color = Theme.InkMuted, AlignX = "Center", Scaled = true, MinTextSize = 9, ZIndex = Z + 2 })
		local b = label(row, { Name = "B", TextSize = 17, Font = "numeric", AlignX = "Center", Rich = true, Scaled = true, MinTextSize = 10, ZIndex = Z + 2 })
		cmp.Rows[spec.Id] = { Root = row, A = a, B = b, Label = name }
	end
	compareWin.Resized:Connect(function()
		layoutCompare()
	end)
end

layoutCompare = function()
	if not cmp then
		return
	end
	local layout = compareWin:GetLayout()
	local w, h = layout.Width, layout.Height
	if w < 2 then
		return
	end
	local phone = layout.Phone
	local landscape = layout.Landscape
	local gap = 10
	local colW = math.floor((w - gap) / 2)
	local verdictH = landscape and 26 or 44
	cmp.Verdict.Position = UDim2.fromOffset(0, 0)
	cmp.Verdict.Size = UDim2.fromOffset(w, verdictH)
	local heroY = verdictH + 6
	local preview = landscape and 0 or (phone and math.min(110, colW - 30) or 140)
	local heroH = preview + (landscape and 70 or 112)
	if landscape then
		heroH = 92
	end
	for i, side in ipairs({ "a", "b" }) do
		local s = cmp.Sides[side]
		local x = (i - 1) * (colW + gap)
		s.Root.Position = UDim2.fromOffset(x, heroY)
		s.Root.Size = UDim2.fromOffset(colW, heroH)
		local y = 8
		if preview > 0 then
			s.Glow.Visible = true
			s.Holder.Visible = true
			s.Glow.Position = UDim2.new(0.5, -preview / 2, 0, y)
			s.Glow.Size = UDim2.fromOffset(preview, preview)
			s.Holder.Position = UDim2.new(0.5, -preview / 2 + 4, 0, y + 4)
			s.Holder.Size = UDim2.fromOffset(preview - 8, preview - 8)
			y += preview + 4
		else
			s.Glow.Visible = false
			s.Holder.Visible = false
		end
		s.Name.Position = UDim2.fromOffset(8, y)
		s.Name.Size = UDim2.new(1, -16, 0, 24)
		y += 26
		s.Tags.Position = UDim2.fromOffset(8, y)
		s.Tags.Size = UDim2.new(1, -16, 0, 22)
		y += 26
		s.Details.Instance.Position = UDim2.new(0, 8, 0, y)
		s.Details.Instance.Size = UDim2.new(1, -16, 0, math.max(28, heroH - y - 8))
		s.Crown.Instance.AnchorPoint = Vector2.new(0.5, 0)
		s.Crown.Instance.Position = UDim2.new(0.5, 0, 0, 4)
	end
	local tableY = heroY + heroH + 8
	cmp.Table.Position = UDim2.fromOffset(0, tableY)
	cmp.Table.Size = UDim2.fromOffset(w, math.max(40, h - tableY))
	local rowH = phone and 34 or 38
	local labelW = math.floor(w * 0.36)
	local valueW = math.floor((w - 6 - labelW) / 2)
	for i, spec in ipairs(Info.CompareRows) do
		local r = cmp.Rows[spec.Id]
		r.Root.Position = UDim2.fromOffset(0, (i - 1) * (rowH + 4))
		r.Root.Size = UDim2.fromOffset(w - 6, rowH)
		r.A.Position = UDim2.fromOffset(6, 0)
		r.A.Size = UDim2.fromOffset(valueW - 12, rowH)
		r.Label.Position = UDim2.fromOffset(valueW, 0)
		r.Label.Size = UDim2.fromOffset(labelW, rowH)
		r.B.Position = UDim2.fromOffset(valueW + labelW + 6, 0)
		r.B.Size = UDim2.fromOffset(valueW - 12, rowH)
	end
	cmp.Table.CanvasSize = UDim2.fromOffset(0, #Info.CompareRows * (rowH + 4))
end

fillCompare = function()
	if not cmp or not cmp.Uids then
		return
	end
	local a, b = st.Entries[cmp.Uids[1]], st.Entries[cmp.Uids[2]]
	if not (a and b) then
		compareWin:Close("gone")
		return
	end
	local result = Info.Compare(a, b)
	cmp.Result = result
	for side, e in pairs({ a = a, b = b }) do
		local s = cmp.Sides[side]
		local def = e.Def
		local gradient = Theme.RarityGradient[def.Rarity]
		local top = gradient and gradient[1] or Theme.RarityColor(def.Rarity)
		s.Gradient.Color = ColorSequence.new(top:Lerp(Theme.White, 0.45), Theme.White)
		s.Slot:Show({ Kind = "Dog", DogId = e.Dog.DogId, Variant = e.Dog.Variant })
		s.Name.Text = e.Dog.DisplayName or def.DisplayName
		s.Rarity:SetRarity(def.Rarity)
		s.Variant:SetVariant(e.Dog.Variant)
		s.Crown:SetVisible(result.Winner == side)
		local stroke = s.Root:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = result.Winner == side and P.gold or P.edge
			stroke.Thickness = result.Winner == side and 4 or 2
			stroke.Transparency = result.Winner == side and 0 or 0.55
		end
	end
	local green = Theme.Hex(Color3.fromRGB(74, 170, 22))
	local function better(value: string, delta: string): string
		return string.format('<font color="%s">▲ %s <font size="13">(%s)</font></font>', green, value, delta)
	end
	for _, row in ipairs(result.Rows) do
		local r = cmp.Rows[row.Id]
		local ta, tb = compareValue(row.Id, row.A), compareValue(row.Id, row.B)
		local delta = compareDelta(row.Id, row.A - row.B)
		r.A.Text = row.Better == "a" and better(ta, delta) or ta
		r.B.Text = row.Better == "b" and better(tb, delta) or tb
	end
	if result.Winner then
		local winner = result.Winner == "a" and a or b
		local gain = result.IncomeGain
		if gain and gain >= 1 then
			cmp.Verdict.Text = F("<b>%s</b> earns more: <b>x%s</b> coins per minute", dogName(winner.Dog.DogId), fixed(1 + gain, 1))
		elseif gain and gain > 0 then
			cmp.Verdict.Text = F("<b>%s</b> earns <b>%s</b> more coins per minute", dogName(winner.Dog.DogId), pct(gain))
		else
			cmp.Verdict.Text = F("<b>%s</b> is the more efficient dog", dogName(winner.Dog.DogId))
		end
	else
		cmp.Verdict.Text = T("These two dogs earn the same")
	end
end

local function openCompare(uids: { string })
	if not compareWin then
		buildCompare()
	end
	cmp.Uids = { uids[1], uids[2] }
	compareWin:Open()
	layoutCompare()
	fillCompare()
end

------------------------------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------------------------------
local function setChips()
	local selected = {}
	for key, on in pairs(st.States) do
		if on then
			table.insert(selected, "s:" .. key)
		end
	end
	for key, on in pairs(st.Rarities) do
		if on then
			table.insert(selected, "r:" .. key)
		end
	end
	ui.Chips:SetSelected(selected, true)
end

local function onCardClick(e: any)
	if st.Compare then
		S.Pick(e.Uid)
	else
		S.Select(e.Uid)
	end
end

local function build()
	if win then
		return
	end
	win = Kit.Window.new({
		Key = "Dogs",
		Title = T("MY DOGS"),
		Subtitle = T("Tap a dog to see how good it is"),
		Accent = ACCENT,
		Icon = "Dogs",
		NoTranslate = true,
		MaxSize = Vector2.new(1120, 780),
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			S._closed()
		end,
	})
	S.Window = win
	ui = { Lang = Kit.Lang() }
	S.UI = ui
	local body = win.Body
	-- Hidden name probes (auto-translated names for search and sentences).
	local probeFrame = Kit.New("Frame", { Name = "NameProbes", BackgroundTransparency = 1, Visible = false, Size = UDim2.fromOffset(1, 1) }, body)
	local namesChanged = false
	for _, def in ipairs(Info.Species) do
		local probe = Kit.New("TextLabel", { Name = def.Id, Text = def.DisplayName, BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1) }, probeFrame)
		probes[def.Id] = probe
		probe:GetPropertyChangedSignal("Text"):Connect(function()
			if namesChanged then
				return
			end
			namesChanged = true
			task.delay(0.2, function()
				namesChanged = false
				if win and win.IsOpen then
					refresh(nil)
				end
			end)
		end)
	end
	ui.Probes = probes
	-- Toolbar.
	ui.Search = Kit.SearchBox(body, {
		Name = "Search",
		Placeholder = T("Search your dogs"),
		ZIndex = Z,
		OnChange = function(text)
			st.Search = text
			refreshList(true)
		end,
	})
	local variantOptions = { { Id = "Any", Text = T("ANY"), NoTranslate = true }, { Id = "Mutated", Text = T("ANY MUTATION"), NoTranslate = true } }
	for _, name in ipairs(Info.Variants) do
		table.insert(variantOptions, { Id = name, Text = T(string.upper(name)), Color = Theme.VariantColor(name), NoTranslate = true })
	end
	ui.Variant = dropdown(body, {
		Name = "VariantFilter",
		Prefix = T("VARIANT: "),
		Options = variantOptions,
		Selected = "Any",
		OnChange = function(id)
			st.Variant = id
			refreshList(true)
		end,
	})
	ui.Sort = Kit.SortSelect(body, {
		Name = "Sort",
		Options = {
			{ Id = "rarity", Text = T("RARITY"), NoTranslate = true },
			{ Id = "efficiency", Text = T("EFFICIENCY"), NoTranslate = true },
			{ Id = "income", Text = T("INCOME"), NoTranslate = true },
			{ Id = "speed", Text = T("DIG SPEED"), NoTranslate = true },
			{ Id = "newest", Text = T("NEWEST"), NoTranslate = true },
			{ Id = "mastery", Text = T("MASTERY"), NoTranslate = true },
			{ Id = "name", Text = T("NAME"), NoTranslate = true, Descending = false },
		},
		Selected = "rarity",
		ZIndex = Z,
		OnChange = function(id, desc)
			st.Sort, st.Desc = id, desc
			refreshList(true)
		end,
	})
	ui.CompareBtn = Kit.Button(body, {
		Name = "Compare",
		Text = T("COMPARE"),
		Style = "secondary",
		TextSize = 16,
		ZIndex = Z,
		NoTranslate = true,
		OnClick = function()
			S.SetCompare(not st.Compare)
		end,
	})
	Kit.Tooltip(ui.CompareBtn.Instance, function()
		return T("Pick two dogs to see every stat side by side."), T("COMPARE")
	end)
	local chipOptions = {
		{ Id = "s:Digging", Text = T("DIGGING"), Color = P.green, NoTranslate = true },
		{ Id = "s:Idle", Text = T("IDLE"), Color = Theme.Disabled, NoTranslate = true },
		{ Id = "s:Locked", Text = T("🔒 LOCKED"), Color = P.edge, NoTranslate = true },
		{ Id = "s:Favorite", Text = T("★ FAVOURITES"), Color = P.gold, NoTranslate = true },
	}
	for _, rarity in ipairs(Info.Rarities) do
		table.insert(chipOptions, { Id = "r:" .. rarity, Text = string.upper(rarity), Color = Theme.RarityColor(rarity) })
	end
	ui.Chips = Kit.Chips(body, {
		Name = "Filters",
		Multi = true,
		Options = chipOptions,
		TextSize = 14,
		ZIndex = Z,
		OnChange = function(selected)
			local states, rarities = {}, {}
			for _, id in ipairs(selected) do
				local kind, key = string.match(id, "^(%a):(.+)$")
				if kind == "s" then
					states[key] = true
				elseif kind == "r" then
					rarities[key] = true
				end
			end
			st.States, st.Rarities = states, rarities
			refreshList(true)
		end,
	})
	ui.Count = label(body, { Name = "Count", TextSize = 14, Color = Theme.InkMuted, AlignX = "Right", Scaled = true, MinTextSize = 9 })
	-- Grid.
	ui.GridHost = Kit.New("Frame", { Name = "GridHost", BackgroundTransparency = 1, ZIndex = Z }, body)
	ui.Grid = Kit.CardGrid(ui.GridHost, {
		Name = "DogGrid",
		Kind = "Dog",
		CardSize = Vector2.new(170, 214),
		RowHeight = 78,
		ZIndex = Z,
		Map = cardData,
		Key = function(e)
			return e.Uid
		end,
		OnClick = function(e)
			onCardClick(e)
		end,
		OnLongPress = function(e)
			if not st.Compare then
				S.SetCompare(true, { e.Uid })
			end
		end,
		Empty = { Icon = "Dogs", Title = T("NO DOGS HERE"), Body = T("Try another search or filter."), NoTranslate = true },
	})
	-- No dogs at all.
	ui.NoDogs = Kit.EmptyState(body, {
		Icon = "Dogs",
		Title = T("NO DOGS YET"),
		Body = T("Adopt your first dog at the DOG LINE. It will dig and earn coins for you."),
		ActionText = T("SHOW THE WAY"),
		NoTranslate = true,
		ZIndex = Z + 1,
		OnAction = function()
			navigate("Factory")
		end,
	})
	ui.NoDogs:SetVisible(false)
	-- Compare bar.
	ui.CompareBar = panel(body, "CompareBar", Theme.Lighten(ACCENT, 0.8))
	ui.CompareText = label(ui.CompareBar, { Name = "Text", TextSize = 16, Scaled = true, MinTextSize = 10, Wrap = true })
	ui.CompareGo = Kit.Button(ui.CompareBar, {
		Name = "Go",
		Text = T("COMPARE"),
		Style = "gold",
		TextSize = 15,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			if #st.Picks == 2 then
				openCompare(st.Picks)
			end
		end,
	})
	ui.CompareCancel = Kit.Button(ui.CompareBar, {
		Name = "Cancel",
		Text = T("CANCEL"),
		Style = "secondary",
		TextSize = 15,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			S.SetCompare(false)
		end,
	})
	ui.CompareBar.Visible = false
	-- Side panel (desktop) / covering panel (phones).
	buildSummary(body)
	buildDetail(body)
	win.Resized:Connect(function()
		relayout()
	end)
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
	local phone = layout.Phone
	local landscape = layout.Landscape
	local gap = phone and 6 or 10
	local rowH = phone and 40 or 42
	local y = 0
	-- Toolbar rows.
	if phone and not landscape then
		local compareW = 104
		ui.Search.Instance.Position = UDim2.fromOffset(0, y)
		ui.Search.Instance.Size = UDim2.fromOffset(w - compareW - gap, rowH)
		ui.CompareBtn.Instance.Position = UDim2.fromOffset(w - compareW, y)
		ui.CompareBtn.Instance.Size = UDim2.fromOffset(compareW, rowH)
		y += rowH + gap
		local half = math.floor((w - gap) / 2)
		ui.Variant.Instance.Position = UDim2.fromOffset(0, y)
		ui.Variant.Instance.Size = UDim2.fromOffset(half, rowH)
		ui.Sort.Instance.Position = UDim2.fromOffset(half + gap, y)
		ui.Sort.Instance.Size = UDim2.fromOffset(w - half - gap, rowH)
		y += rowH + gap
	else
		local compareW = phone and 110 or 132
		local sortW = phone and 176 or 212
		local variantW = phone and 158 or 200
		local searchW = w - compareW - sortW - variantW - gap * 3
		if searchW < 150 then
			variantW = math.max(130, variantW - (150 - searchW))
			searchW = w - compareW - sortW - variantW - gap * 3
		end
		ui.Search.Instance.Position = UDim2.fromOffset(0, y)
		ui.Search.Instance.Size = UDim2.fromOffset(searchW, rowH)
		ui.Variant.Instance.Position = UDim2.fromOffset(searchW + gap, y)
		ui.Variant.Instance.Size = UDim2.fromOffset(variantW, rowH)
		ui.Sort.Instance.Position = UDim2.fromOffset(searchW + variantW + gap * 2, y)
		ui.Sort.Instance.Size = UDim2.fromOffset(sortW, rowH)
		ui.CompareBtn.Instance.Position = UDim2.fromOffset(w - compareW, y)
		ui.CompareBtn.Instance.Size = UDim2.fromOffset(compareW, rowH)
		y += rowH + gap
	end
	local chipsH = phone and 34 or 36
	local countW = phone and 0 or 120
	ui.Chips.Instance.Position = UDim2.fromOffset(0, y)
	ui.Chips.Instance.Size = UDim2.fromOffset(w - countW - (countW > 0 and gap or 0), chipsH)
	ui.Count.Visible = countW > 0
	ui.Count.Position = UDim2.fromOffset(w - countW, y)
	ui.Count.Size = UDim2.fromOffset(countW, chipsH)
	y += chipsH + gap
	-- Grid + panel.
	local panelW = 0
	if not phone then
		panelW = math.clamp(math.floor(w * 0.36), 320, 400)
	end
	local gridW = w - (panelW > 0 and panelW + gap or 0)
	local barH = st.Compare and (phone and 52 or 56) or 0
	local gridH = h - y - (barH > 0 and barH + gap or 0)
	ui.GridHost.Position = UDim2.fromOffset(0, y)
	ui.GridHost.Size = UDim2.fromOffset(gridW, math.max(40, gridH))
	ui.NoDogs.Instance.Position = UDim2.fromOffset(gridW / 2, y + gridH / 2)
	ui.NoDogs.Instance.Size = UDim2.fromOffset(math.max(200, gridW - 24), 230)
	ui.CompareBar.Visible = st.Compare
	ui.CompareBar.Position = UDim2.fromOffset(0, h - barH)
	ui.CompareBar.Size = UDim2.fromOffset(gridW, math.max(1, barH))
	local goW, cancelW = phone and 104 or 130, phone and 92 or 110
	ui.CompareGo.Instance.Position = UDim2.new(1, -(goW + cancelW + 16), 0.5, -18)
	ui.CompareGo.Instance.Size = UDim2.fromOffset(goW, 36)
	ui.CompareCancel.Instance.Position = UDim2.new(1, -(cancelW + 8), 0.5, -18)
	ui.CompareCancel.Instance.Size = UDim2.fromOffset(cancelW, 36)
	ui.CompareText.Position = UDim2.fromOffset(12, 4)
	ui.CompareText.Size = UDim2.new(1, -(goW + cancelW + 36), 1, -8)
	local d = ui.Detail
	local showDetail = st.Selected ~= nil and st.Entries[st.Selected] ~= nil
	if phone then
		-- The panel covers the grid area while a dog is open.
		d.Root.Visible = showDetail
		d.Root.Position = UDim2.fromOffset(0, 0)
		d.Root.Size = UDim2.fromOffset(w, h)
		ui.PanelW, ui.PanelH = w, h
		ui.Summary.Root.Visible = false
		for _, o in ipairs({ ui.Search.Instance, ui.Variant.Instance, ui.Sort.Instance, ui.CompareBtn.Instance, ui.Chips.Instance }) do
			o.Visible = not showDetail
		end
		ui.GridHost.Visible = not showDetail and entryCount() > 0
		ui.NoDogs:SetVisible(not showDetail and entryCount() == 0 and st.Snapshot ~= nil)
		ui.Count.Visible = false
		ui.CompareBar.Visible = st.Compare and not showDetail
	else
		for _, o in ipairs({ ui.Search.Instance, ui.Variant.Instance, ui.Sort.Instance, ui.CompareBtn.Instance, ui.Chips.Instance }) do
			o.Visible = true
		end
		ui.GridHost.Visible = entryCount() > 0
		ui.NoDogs:SetVisible(entryCount() == 0 and st.Snapshot ~= nil)
		local px = w - panelW
		d.Root.Visible = showDetail
		d.Root.Position = UDim2.fromOffset(px, y)
		d.Root.Size = UDim2.fromOffset(panelW, h - y)
		ui.Summary.Root.Visible = not showDetail
		ui.Summary.Root.Position = UDim2.fromOffset(px, y)
		ui.Summary.Root.Size = UDim2.fromOffset(panelW, h - y)
		ui.PanelW, ui.PanelH = panelW, h - y
		layoutSummary(panelW, h - y)
	end
	if showDetail then
		layoutDetail()
	end
	ui.Grid:Relayout()
end

-- Rebuilds the visible list from the current entries (no instance is rebuilt: cells are keyed).
refreshList = function(resetScroll: boolean?)
	if not ui then
		return
	end
	local list = filterAndSort()
	st.List = list
	ui.Grid:SetItems(list, { ResetScroll = resetScroll == true })
	local total = entryCount()
	ui.Count.Text = F("%d / %d SHOWN", #list, total)
	if st.Compare then
		local n = #st.Picks
		if n == 0 then
			ui.CompareText.Text = T("Pick 2 dogs to compare")
		elseif n == 1 then
			local e = st.Entries[st.Picks[1]]
			ui.CompareText.Text = F("Pick a dog to compare with %s", e and dogName(e.Dog.DogId) or "?")
		else
			ui.CompareText.Text = T("Ready: tap COMPARE")
		end
		ui.CompareGo:SetDisabled(n < 2)
	end
	ui.CompareBtn:SetStyle(st.Compare and "gold" or "secondary")
end

refresh = function(snapshot: any?)
	if snapshot then
		st.Snapshot = snapshot
	end
	if not ui or not st.Snapshot then
		return
	end
	rebuildEntries()
	if st.Selected and not st.Entries[st.Selected] then
		st.Selected = nil
	end
	local kept = {}
	for _, uid in ipairs(st.Picks) do
		if st.Entries[uid] then
			table.insert(kept, uid)
		end
	end
	st.Picks = kept
	local p = profile()
	local count, digging = 0, 0
	for _, e in pairs(st.Entries) do
		count += 1
		if Info.State(e.Dog) == "Digging" then
			digging += 1
		end
	end
	local income = tonumber(st.Snapshot.IncomePerMinute) or 0
	win:SetTitle(T("MY DOGS"), F("%d / %d dogs · %d digging · $%s / min", count, capacity(p), digging, short(income)))
	fillSummary()
	refreshList(false)
	relayout()
	if st.Selected then
		fillDetail()
	end
	syncArtifacts()
	if compareWin and compareWin.IsOpen then
		fillCompare()
	end
end
S.Refresh = refresh

function S._opened()
	openToken += 1
	local token = openToken
	local cached = Net.Cached()
	if cached then
		refresh(cached)
	else
		relayout()
	end
	task.spawn(function()
		local snapshot = Net.Snapshot(2)
		if snapshot and openToken == token and win.IsOpen then
			refresh(snapshot)
		end
		-- While open: a light refresh (shared cache, so other screens' fetches count too).
		while openToken == token and win.IsOpen do
			task.wait(10)
			if openToken ~= token or not win.IsOpen then
				break
			end
			Net.Snapshot(10)
		end
	end)
end
function S._closed()
	openToken += 1
	if compareWin and compareWin.IsOpen then
		compareWin:Close("parent")
	end
	if ui and ui.Variant.ClosePopup then
		ui.Variant.ClosePopup()
	end
	syncArtifacts()
end

Net.Changed:Connect(function(snapshot)
	if win and win.IsOpen then
		refresh(snapshot)
	end
end)

------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------
-- Labels are localized when the window is built: after a language change (LocaleId) the closed
-- windows are rebuilt on the next open.
local function rebuildIfLanguageChanged()
	if not (win and ui) or ui.Lang == Kit.Lang() or win.IsOpen then
		return
	end
	if compareWin then
		if cmp then
			for _, side in pairs(cmp.Sides) do
				side.Slot:Destroy()
			end
		end
		compareWin:Destroy()
		compareWin, cmp = nil, nil
	end
	syncArtifacts()
	ui.Grid:Destroy()
	ui.Detail.Slot:Destroy()
	win:Destroy()
	win, ui = nil, nil
	S.Window, S.UI = nil, nil
end

-- opts: {Uid = dog to open, Search = text, Species = DogId (search by its name)}
function S.Open(opts: any?)
	rebuildIfLanguageChanged()
	build()
	local o = opts or {}
	if o.Species or o.Search then
		st.Selected = nil
	end
	if o.Species then
		st.Search = dogName(o.Species)
		ui.Search:SetText(st.Search, true)
		st.States, st.Rarities, st.Variant = {}, {}, "Any"
		setChips()
		ui.Variant:Set("Any", true)
	elseif o.Search then
		st.Search = o.Search
		ui.Search:SetText(o.Search, true)
	end
	if o.Uid then
		st.Selected = o.Uid
	end
	win:Open()
	if o.Species or o.Search then
		refreshList(true)
	end
	if o.Uid then
		relayout()
		task.defer(function()
			if ui then
				ui.Grid:ScrollToKey(o.Uid, false)
			end
		end)
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

function S.Select(uid: string?)
	if not ui then
		return
	end
	local previous = st.Selected
	st.Selected = uid
	st.OpenTip = nil
	if uid ~= previous then
		st.Tab = "stats"
		ui.Detail.Tabs:Select("stats", true)
	end
	if previous and previous ~= uid then
		ui.Grid:RefreshKey(previous)
	end
	if uid then
		ui.Grid:RefreshKey(uid)
	end
	relayout()
	syncArtifacts()
	if uid and not win:GetLayout().Phone then
		local e = st.Entries[uid]
		if e then
			ui.Detail.Root.Position = ui.Detail.Root.Position + UDim2.fromOffset(12, 0)
			Kit.Motion.Tween(ui.Detail.Root, Theme.Motion.Fast, { Position = ui.Detail.Root.Position - UDim2.fromOffset(12, 0) })
		end
	end
end

-- Compare mode on/off; picks: DogUids to start with.
function S.SetCompare(on: boolean, picks: { string }?)
	if not ui then
		return
	end
	st.Compare = on == true
	st.Picks = {}
	if on and picks then
		for _, uid in ipairs(picks) do
			if st.Entries[uid] and #st.Picks < 2 then
				table.insert(st.Picks, uid)
			end
		end
	end
	if on then
		st.Selected = nil
	end
	ui.Grid:Refresh()
	refreshList(false)
	relayout()
	if on then
		Kit.Toast(T("Pick 2 dogs to compare"), { Kind = "info", NoTranslate = true, Duration = 2 })
	end
end

-- Compare mode: toggles a pick; the second pick opens the comparison.
function S.Pick(uid: string)
	if not st.Entries[uid] then
		return
	end
	local index = table.find(st.Picks, uid)
	if index then
		table.remove(st.Picks, index)
	else
		if #st.Picks >= 2 then
			local old = table.remove(st.Picks, 1)
			ui.Grid:RefreshKey(old)
		end
		table.insert(st.Picks, uid)
	end
	ui.Grid:RefreshKey(uid)
	refreshList(false)
	if #st.Picks == 2 then
		openCompare(st.Picks)
	end
end

function S.OpenCompare(a: string, b: string)
	rebuildIfLanguageChanged()
	build()
	if not win.IsOpen then
		win:Open()
	end
	S.SetCompare(true, { a, b })
	if #st.Picks == 2 then
		openCompare(st.Picks)
	end
end
function S.CompareWindow(): any
	return compareWin, cmp
end

-- VIEW IN DEX: the Dogdex entry of this species over this window (closing it comes back here).
function S.ViewInDex(dogId: string)
	local ok, Dex = pcall(function()
		return require(script.Parent.DogdexScreen)
	end)
	if ok and Dex and type(Dex.OpenEntry) == "function" then
		Dex.OpenEntry(dogId, { Stack = true })
	else
		warn("DogsScreen: DogdexScreen unavailable: " .. tostring(Dex))
	end
end

-- Menus fallback (legacy 'Dogs' / 'DogDetail' screens): opens the window instead.
function S.Build(c: any)
	task.defer(function()
		S.Open({ Uid = c and c.Page == "DogDetail" and c.State and c.State.SelectedDog or nil })
	end)
end

return S
