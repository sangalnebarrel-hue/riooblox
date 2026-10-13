-- MY BEST FINDS editor (UI kit window Key = "Showcase"; docs/PLOT_COSMETICS.md).
--   Top: the showcase cases as big preview tiles (pinned / AUTO / empty, rarity border; the fifth
--   "crown" case opens at yard stage 5). Pick a case, then tap one of your finds below (rarest
--   first, search + rarity chips) to put it there: one request, a toast, the stand updates.
--   REMOVE gives the case back to the automatic pick. Long-press / right-click a find to preview it
--   in 3D without placing it. Changes need the player at their own showcase (EDIT SHOWCASE prompt).
-- Entry points: the stand prompt (DogEconomyOpen 'Showcase'), N.OpenPage('Showcase') (GUIIntegration).
-- Data: Snapshot.Features.Showcase (Features.Showcase) and Snapshot.Profile.Items via Modules.Net.
local RS = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Economy = RS:WaitForChild("DogEconomy")
local Rules = require(Economy:WaitForChild("ShowcaseRules"))
local Dict = require(RS:WaitForChild("Localization"):WaitForChild("Plot"))
local Theme, Format = Kit.Theme, Kit.Format
local P = Theme.Colors
local ACCENT = Color3.fromRGB(240, 170, 40)
local Z = 3

local S = {}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function T(en: string, ru: string?): string
	return Kit.T(en, ru or Dict.Exact[en] or en)
end
-- A server reply in the player's language (Localization.Plot exact entries and patterns).
local function said(text: any): string
	text = tostring(text or "")
	if Kit.Lang() ~= "ru" then
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
local RARITY_RU = { Common = "ОБЫЧНОЕ", Uncommon = "НЕОБЫЧНОЕ", Rare = "РЕДКОЕ", Epic = "ЭПИЧЕСКОЕ", Legendary = "ЛЕГЕНДАРНОЕ", Mythic = "МИФИЧЕСКОЕ", Secret = "СЕКРЕТНОЕ" }
local function rarityWord(r: string?): string
	local name: string = r or "Common"
	return Kit.T(string.upper(name), RARITY_RU[name] or string.upper(name))
end
local function kg(weight: any): string
	local w = tonumber(weight) or 0
	local text = w >= 100 and Format.Number(math.floor(w + 0.5)) or string.format("%.3g", w)
	return text .. (Kit.Lang() == "ru" and " кг" or " kg")
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st: any = {
	Snapshot = nil,
	Selected = 1,
	Search = "",
	Rarities = {},
	Busy = false,
	PreviewUid = nil, -- a find shown in the big preview without placing it (long-press)
}
S.State = st
local win: any = nil
local ui: any = nil
local relayout: () -> ()
local refresh: (snapshot: any?) -> ()

local function view(): any
	local features = st.Snapshot and st.Snapshot.Features
	return type(features) == "table" and features.Showcase or nil
end
local function items(): { [string]: any }
	local profile = st.Snapshot and st.Snapshot.Profile
	return type(profile) == "table" and type(profile.Items) == "table" and profile.Items or {}
end
local function capacity(): number
	local v = view()
	return v and tonumber(v.Capacity) or Rules.BaseSlots
end
local function exhibit(i: number): any
	local v = view()
	return v and type(v.Exhibits) == "table" and v.Exhibits[tostring(i)] or nil
end
local function pinnedSlot(uid: string): number?
	local v = view()
	local slot = v and type(v.Pinned) == "table" and v.Pinned[uid]
	return tonumber(slot)
end

------------------------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------------------------
local function request(action: string, args: any, button: any?)
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
		if win and win.IsOpen then
			refresh(Net.Cached())
		end
	end)
end

function S.Place(uid: string)
	local slot = st.Selected
	if slot > capacity() then
		Kit.Toast(said("The fifth case opens at yard stage " .. Rules.BonusStage), { Kind = "warn", NoTranslate = true })
		return
	end
	local current = exhibit(slot)
	if current and current.Pinned and current.Uid == uid then
		Kit.Toast(T("ON DISPLAY"), { Kind = "info", NoTranslate = true })
		return
	end
	st.PreviewUid = nil
	request("ShowcaseSet", { Slot = slot, Uid = uid })
end

function S.Clear()
	request("ShowcaseClear", { Slot = st.Selected }, ui and ui.Remove)
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

local function buildTile(i: number): any
	local t: any = { Index = i }
	local button = Kit.New("TextButton", { Name = "Case" .. i, Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z }, ui.Strip)
	Kit.Corner(button, Theme.Radius.Card)
	t.Stroke = Kit.Stroke(button, P.edge, 2)
	t.Button = button
	t.Glow = Kit.New("Frame", { Name = "Glow", BackgroundColor3 = Theme.White, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.55), ZIndex = Z + 1 }, button)
	Kit.Corner(t.Glow, Theme.Radius.Card)
	t.GlowGradient = Kit.New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.55, 1) }, t.Glow)
	t.Holder = Kit.New("Frame", { Name = "PreviewHolder", BackgroundTransparency = 1, ZIndex = Z + 2 }, button)
	t.Slot = Kit.Preview.Slot(t.Holder)
	t.Number = label(button, { Name = "Number", Text = i == Rules.MaxSlots and "👑" or tostring(i), TextSize = 16, Font = "numeric", Color = Theme.InkMuted, ZIndex = Z + 3 })
	t.Name = label(button, { Name = "ItemName", Text = "", TextSize = 14, AlignX = "Center", Scaled = true, MinTextSize = 8, NoTranslate = false, ZIndex = Z + 3 })
	t.Badge = Kit.Pill(button, { Text = "", Height = 18, TextSize = 11, ZIndex = Z + 4, NoTranslate = true })
	t.Lock = label(button, { Name = "Lock", Text = "🔒", TextSize = 28, AlignX = "Center", ZIndex = Z + 3 })
	t.Maid = Kit.Maid.new()
	t.Maid:Give(button.Activated:Connect(function()
		st.Selected = i
		st.PreviewUid = nil
		refresh(nil)
	end))
	Kit.Tooltip(button, function()
		local row = exhibit(i)
		if i > capacity() then
			return said("The fifth case opens at yard stage " .. Rules.BonusStage), T("CROWN CASE")
		end
		if not row then
			return T("Empty cases show your best finds automatically."), T("CASE") .. " " .. i
		end
		local how = row.Pinned and T("PINNED") or T("AUTO")
		return how .. " · " .. rarityWord(row.Rarity) .. " · " .. kg(row.WeightKg), row.DisplayName
	end, { Title = T("CASE") })
	return t
end

local function build()
	if win then
		return
	end
	win = Kit.Window.new({
		Key = "Showcase",
		Title = T("MY BEST FINDS"),
		Subtitle = T("Choose the finds your visitors see"),
		Accent = ACCENT,
		Icon = "Inventory",
		NoTranslate = true,
		MaxSize = Vector2.new(1080, 780),
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			S._closed()
		end,
	})
	S.Window = win
	ui = { Tiles = {}, Lang = Kit.Lang() }
	S.UI = ui
	local body = win.Body
	ui.Strip = Kit.New("Frame", { Name = "Cases", BackgroundTransparency = 1, ZIndex = Z }, body)
	for i = 1, Rules.MaxSlots do
		ui.Tiles[i] = buildTile(i)
	end
	-- Detail of the selected case (big live preview).
	ui.Detail = panel(body, "Detail", Theme.White)
	ui.BigHolder = Kit.New("Frame", { Name = "BigPreview", BackgroundColor3 = Color3.fromRGB(22, 30, 46), BorderSizePixel = 0, ZIndex = Z + 1 }, ui.Detail)
	Kit.Corner(ui.BigHolder, Theme.Radius.Small)
	ui.Big = Kit.Preview.Slot(ui.BigHolder)
	ui.DetailTitle = label(ui.Detail, { Name = "Case", TextSize = 14, Color = Theme.InkMuted })
	ui.DetailName = label(ui.Detail, { Name = "ItemName", TextSize = 20, Scaled = true, MinTextSize = 11, NoTranslate = false })
	ui.DetailRarity = Kit.RarityTag(ui.Detail, "Common", { Height = 20, TextSize = 12, ZIndex = Z + 2 })
	ui.DetailInfo = label(ui.Detail, { Name = "Info", TextSize = 14, Color = Theme.InkMuted, Font = "numeric" })
	ui.DetailState = Kit.Pill(ui.Detail, { Text = "", Height = 22, TextSize = 12, ZIndex = Z + 2, NoTranslate = true })
	ui.Remove = Kit.Button(ui.Detail, {
		Name = "Remove",
		Text = T("REMOVE"),
		Style = "danger",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			S.Clear()
		end,
	})
	Kit.Tooltip(ui.Remove.Instance, T("Empty cases show your best finds automatically."), { Title = T("REMOVE") })
	ui.PlacePreview = Kit.Button(ui.Detail, {
		Name = "PlacePreview",
		Text = T("PLACE"),
		Style = "success",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			if st.PreviewUid then
				S.Place(st.PreviewUid)
			end
		end,
	})
	ui.Hint = label(ui.Detail, { Name = "Hint", TextSize = 13, Color = Theme.InkMuted, Wrap = true, AlignY = "Top" })
	-- Finds.
	ui.Search = Kit.SearchBox(body, {
		Name = "Search",
		Placeholder = Kit.Word("SEARCH"),
		ZIndex = Z,
		OnChange = function(text)
			st.Search = string.lower(text or "")
			S.RefreshList(true)
		end,
	})
	local chips = {}
	for _, r in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }) do
		table.insert(chips, { Id = r, Text = rarityWord(r), Color = Theme.RarityColor(r), NoTranslate = true })
	end
	ui.Chips = Kit.Chips(body, {
		Name = "Rarities",
		Multi = true,
		Options = chips,
		TextSize = 13,
		ZIndex = Z,
		OnChange = function(selected)
			local set = {}
			for _, id in ipairs(selected) do
				set[id] = true
			end
			st.Rarities = set
			S.RefreshList(true)
		end,
	})
	ui.GridHost = Kit.New("Frame", { Name = "GridHost", BackgroundTransparency = 1, ZIndex = Z }, body)
	ui.Grid = Kit.CardGrid(ui.GridHost, {
		Name = "Finds",
		Kind = "Item",
		CardSize = Vector2.new(150, 196),
		RowHeight = 72,
		ZIndex = Z,
		Key = function(x)
			return x.ItemUid
		end,
		Map = function(x)
			local slot = pinnedSlot(x.ItemUid)
			local rarity = Rules.Rarity(x.ItemId)
			local here = exhibit(st.Selected)
			return {
				Id = x.ItemUid,
				Name = x.DisplayName or x.ItemId,
				Rarity = rarity,
				Mutation = x.Mutation,
				Preview = { Kind = "Item", ItemId = x.ItemId, Mutation = x.Mutation },
				Stats = { { Text = kg(x.WeightKg) } },
				Badge = slot and ((Kit.Lang() == "ru" and "ВИТРИНА " or "CASE ") .. slot) or nil,
				BadgeColor = ACCENT,
				Selected = here ~= nil and here.Uid == x.ItemUid,
			}
		end,
		OnClick = function(x)
			S.Place(x.ItemUid)
		end,
		OnLongPress = function(x)
			st.PreviewUid = x.ItemUid
			S.RefreshDetail()
		end,
		Empty = { Icon = "Inventory", Title = T("No finds yet"), Body = T("Your dogs dig up finds: the rarest ones go on display here."), NoTranslate = true },
	})
	win.Resized:Connect(function()
		relayout()
	end)
end

------------------------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------------------------
local function paintTile(t: any)
	local i = t.Index
	local locked = i > capacity()
	local row = not locked and exhibit(i) or nil
	local selected = st.Selected == i
	local color = row and (Rules.Colors[row.Effect] or Rules.Colors[row.Rarity]) or Theme.Disabled
	t.Stroke.Color = selected and ACCENT or color:Lerp(P.edge, 0.35)
	t.Stroke.Thickness = selected and 4 or 2
	t.Glow.BackgroundColor3 = color
	t.Glow.Visible = row ~= nil
	t.Lock.Visible = locked
	t.Button.BackgroundColor3 = locked and Theme.SurfaceAlt or Theme.White
	if row then
		t.Slot:Show({ Kind = "Item", ItemId = row.ItemId, Mutation = row.Mutation })
		t.Name.Text = row.DisplayName
		t.Badge:SetVisible(true)
		if row.Pinned then
			t.Badge:Set(T("PINNED"), ACCENT)
		else
			t.Badge:Set(T("AUTO"), Theme.Info)
		end
	else
		t.Slot:Show(nil)
		t.Name.Text = locked and (Kit.Lang() == "ru" and ("СТАДИЯ " .. Rules.BonusStage) or ("STAGE " .. Rules.BonusStage)) or T("EMPTY")
		t.Badge:SetVisible(locked)
		if locked then
			t.Badge:Set(T("LOCKED"), Theme.Disabled)
		end
	end
end

function S.RefreshDetail()
	if not ui then
		return
	end
	local i = st.Selected
	local locked = i > capacity()
	local row = not locked and exhibit(i) or nil
	local preview = nil
	if st.PreviewUid then
		local x = items()[st.PreviewUid]
		if x then
			preview = { DisplayName = x.DisplayName or x.ItemId, ItemId = x.ItemId, Mutation = x.Mutation, WeightKg = x.WeightKg, Rarity = Rules.Rarity(x.ItemId), Preview = true }
		else
			st.PreviewUid = nil
		end
	end
	local shown = preview or row
	ui.DetailTitle.Text = (i == Rules.MaxSlots and T("CROWN CASE") or (T("CASE") .. " " .. i))
	if shown then
		ui.Big:Show({ Kind = "Item", ItemId = shown.ItemId, Mutation = shown.Mutation })
		ui.DetailName.Text = shown.DisplayName
		ui.DetailRarity.Instance.Visible = true
		ui.DetailRarity:SetRarity(shown.Rarity)
		local mutation = shown.Mutation and shown.Mutation ~= "NORMAL" and (" · " .. string.upper(shown.Mutation)) or ""
		ui.DetailInfo.Text = kg(shown.WeightKg) .. mutation
	else
		ui.Big:Show(nil)
		ui.DetailName.Text = locked and said("The fifth case opens at yard stage " .. Rules.BonusStage) or T("EMPTY")
		ui.DetailRarity.Instance.Visible = false
		ui.DetailInfo.Text = ""
	end
	if preview then
		ui.DetailState:Set(Kit.T("PREVIEW", "ПРЕДПРОСМОТР"), Theme.Info)
	elseif row and row.Pinned then
		ui.DetailState:Set(T("PINNED"), ACCENT)
	elseif row then
		ui.DetailState:Set(row.Owned == false and T("RECORD") or T("AUTO"), Theme.Info)
	else
		ui.DetailState:Set(locked and T("LOCKED") or T("EMPTY"), Theme.Disabled)
	end
	ui.Remove.Instance.Visible = preview == nil
	ui.Remove:SetDisabled(not (row and row.Pinned))
	ui.PlacePreview.Instance.Visible = preview ~= nil
	local v = view()
	local near = v and v.Near == true
	if not near then
		ui.Hint.Text = T("Walk up to your showcase to change it")
		ui.Hint.TextColor3 = Theme.Danger
	else
		ui.Hint.Text = T("Tap a find to put it in the selected case.") .. " " .. T("Empty cases show your best finds automatically.")
		ui.Hint.TextColor3 = Theme.InkMuted
	end
end

local function sortedFinds(): { any }
	local list = {}
	local search = st.Search
	local filter = next(st.Rarities) ~= nil
	for uid, x in pairs(items()) do
		if type(x) == "table" and x.ItemUid == uid then
			local ok = true
			if filter and not st.Rarities[Rules.Rarity(x.ItemId)] then
				ok = false
			end
			if ok and search ~= "" then
				local name = string.lower(tostring(x.DisplayName or "") .. " " .. tostring(x.ItemId or ""))
				ok = string.find(name, search, 1, true) ~= nil
			end
			if ok then
				table.insert(list, x)
			end
		end
	end
	table.sort(list, Rules.Better)
	return list
end

function S.RefreshList(resetScroll: boolean?)
	if not ui then
		return
	end
	ui.Grid:SetItems(sortedFinds(), { ResetScroll = resetScroll == true })
end

refresh = function(snapshot: any?)
	if snapshot then
		st.Snapshot = snapshot
	end
	if not ui then
		return
	end
	if st.Selected > Rules.MaxSlots then
		st.Selected = 1
	end
	for _, t in ipairs(ui.Tiles) do
		paintTile(t)
	end
	S.RefreshDetail()
	S.RefreshList(false)
end
S.Refresh = refresh

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
	-- Case tiles.
	local tileH = landscape and 66 or (phone and 92 or 150)
	local n = Rules.MaxSlots
	local stripW = (phone or landscape) and w or math.min(w, 5 * 160 + 4 * gap)
	local tileW = math.floor((stripW - (n - 1) * gap) / n)
	ui.Strip.Position = UDim2.fromOffset(0, 0)
	ui.Strip.Size = UDim2.fromOffset(stripW, tileH)
	for i, t in ipairs(ui.Tiles) do
		t.Button.Position = UDim2.fromOffset((i - 1) * (tileW + gap), 0)
		t.Button.Size = UDim2.fromOffset(tileW, tileH)
		local nameH = landscape and 16 or (phone and 18 or 22)
		local holder = math.max(10, math.min(tileW - 10, tileH - nameH - (landscape and 4 or 12)))
		t.Holder.Position = UDim2.fromOffset(math.floor((tileW - holder) / 2), landscape and 2 or 6)
		t.Holder.Size = UDim2.fromOffset(holder, holder)
		t.Name.Position = UDim2.fromOffset(4, tileH - nameH - 2)
		t.Name.Size = UDim2.fromOffset(tileW - 8, nameH)
		t.Number.Position = UDim2.fromOffset(6, 2)
		t.Number.Size = UDim2.fromOffset(24, 20)
		t.Badge.Instance.AnchorPoint = Vector2.new(1, 0)
		t.Badge.Instance.Position = UDim2.new(1, -4, 0, 4)
		t.Lock.Position = UDim2.fromOffset(0, 0)
		t.Lock.Size = UDim2.new(1, 0, 1, -nameH)
	end
	local y = tileH + gap
	-- Detail panel: a side column on desktop, a strip on phones (hidden on landscape phones).
	local sideW = 0
	if not phone then
		sideW = math.clamp(math.floor(w * 0.3), 250, 320)
		ui.Detail.Visible = true
		ui.Detail.Position = UDim2.fromOffset(0, y)
		ui.Detail.Size = UDim2.fromOffset(sideW, h - y)
		local pw = sideW - 24
		local ph = math.min(pw, math.max(120, h - y - 230))
		ui.BigHolder.Position = UDim2.fromOffset(12, 12)
		ui.BigHolder.Size = UDim2.fromOffset(pw, ph)
		local cy = 12 + ph + 8
		ui.DetailTitle.Position = UDim2.fromOffset(12, cy)
		ui.DetailTitle.Size = UDim2.fromOffset(pw - 90, 18)
		ui.DetailState.Instance.AnchorPoint = Vector2.new(1, 0)
		ui.DetailState.Instance.Position = UDim2.new(1, -12, 0, cy - 2)
		cy += 20
		ui.DetailName.Position = UDim2.fromOffset(12, cy)
		ui.DetailName.Size = UDim2.fromOffset(pw, 26)
		cy += 28
		ui.DetailRarity.Instance.Position = UDim2.fromOffset(12, cy)
		ui.DetailInfo.Position = UDim2.fromOffset(110, cy)
		ui.DetailInfo.Size = UDim2.fromOffset(pw - 100, 20)
		cy += 28
		ui.Remove.Instance.Position = UDim2.fromOffset(12, cy)
		ui.Remove.Instance.Size = UDim2.fromOffset(pw, 42)
		ui.PlacePreview.Instance.Position = UDim2.fromOffset(12, cy)
		ui.PlacePreview.Instance.Size = UDim2.fromOffset(pw, 42)
		cy += 50
		ui.Hint.Position = UDim2.fromOffset(12, cy)
		ui.Hint.Size = UDim2.fromOffset(pw, math.max(20, h - y - cy - 8))
		sideW += gap
	elseif not landscape then
		local dh = 78
		ui.Detail.Visible = true
		ui.Detail.Position = UDim2.fromOffset(0, y)
		ui.Detail.Size = UDim2.fromOffset(w, dh)
		ui.BigHolder.Position = UDim2.fromOffset(8, 7)
		ui.BigHolder.Size = UDim2.fromOffset(64, 64)
		local bw = 104
		local tx = 80
		ui.DetailTitle.Position = UDim2.fromOffset(tx, 6)
		ui.DetailTitle.Size = UDim2.fromOffset(w - tx - bw - 16, 16)
		ui.DetailName.Position = UDim2.fromOffset(tx, 22)
		ui.DetailName.Size = UDim2.fromOffset(w - tx - bw - 16, 22)
		ui.DetailRarity.Instance.Position = UDim2.fromOffset(tx, 50)
		ui.DetailInfo.Position = UDim2.fromOffset(tx + 96, 50)
		ui.DetailInfo.Size = UDim2.fromOffset(math.max(20, w - tx - bw - 112), 20)
		ui.DetailState.Instance.AnchorPoint = Vector2.new(1, 0)
		ui.DetailState.Instance.Position = UDim2.new(1, -8, 0, 6)
		ui.Remove.Instance.Position = UDim2.new(1, -(bw + 8), 0, 32)
		ui.Remove.Instance.Size = UDim2.fromOffset(bw, 40)
		ui.PlacePreview.Instance.Position = UDim2.new(1, -(bw + 8), 0, 32)
		ui.PlacePreview.Instance.Size = UDim2.fromOffset(bw, 40)
		ui.Hint.Visible = false
		y += dh + gap
	else
		ui.Detail.Visible = false
	end
	ui.Hint.Visible = not phone
	-- Toolbar and grid (right of the side column on desktop).
	local x = sideW
	local gw = w - x
	local rowH = phone and 38 or 42
	local removeW = 0
	if landscape then
		removeW = 110
		ui.Remove.Instance.Parent = win.Body
		ui.Remove.Instance.Position = UDim2.fromOffset(w - removeW, y)
		ui.Remove.Instance.Size = UDim2.fromOffset(removeW, rowH)
	elseif ui.Remove.Instance.Parent ~= ui.Detail then
		ui.Remove.Instance.Parent = ui.Detail
	end
	ui.Search.Instance.Position = UDim2.fromOffset(x, y)
	ui.Search.Instance.Size = UDim2.fromOffset(gw - removeW - (removeW > 0 and gap or 0), rowH)
	y += rowH + gap
	local chipsH = phone and 32 or 36
	ui.Chips.Instance.Position = UDim2.fromOffset(x, y)
	ui.Chips.Instance.Size = UDim2.fromOffset(gw, chipsH)
	y += chipsH + gap
	ui.GridHost.Position = UDim2.fromOffset(x, y)
	ui.GridHost.Size = UDim2.fromOffset(gw, math.max(40, h - y))
	ui.Grid:Relayout()
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
local openToken = 0
function S._opened()
	openToken += 1
	local token = openToken
	local cached = Net.Cached()
	if cached then
		refresh(cached)
	end
	task.spawn(function()
		local snapshot = Net.Snapshot(1)
		if snapshot and openToken == token and win.IsOpen then
			refresh(snapshot)
		end
		-- "Near the showcase" can change while the window is open: re-check now and then.
		while openToken == token and win.IsOpen do
			task.wait(6)
			if openToken ~= token or not win.IsOpen then
				break
			end
			Net.Snapshot(5)
		end
	end)
end
function S._closed()
	openToken += 1
	st.PreviewUid = nil
end

Net.Changed:Connect(function(snapshot)
	if win and win.IsOpen then
		refresh(snapshot)
	end
end)

local function rebuildIfLanguageChanged()
	if win and ui and ui.Lang ~= Kit.Lang() and not win.IsOpen then
		ui.Grid:Destroy()
		for _, t in ipairs(ui.Tiles) do
			t.Slot:Destroy()
			t.Maid:Clean()
		end
		ui.Big:Destroy()
		win:Destroy()
		win, ui = nil, nil
		S.Window, S.UI = nil, nil
	end
end

-- arg: nil, a case number (1-5) or the page message (ignored).
function S.Open(arg: any?)
	rebuildIfLanguageChanged()
	build()
	local slot = tonumber(arg)
	if slot and slot >= 1 and slot <= Rules.MaxSlots then
		st.Selected = math.floor(slot)
	end
	win:Open()
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
