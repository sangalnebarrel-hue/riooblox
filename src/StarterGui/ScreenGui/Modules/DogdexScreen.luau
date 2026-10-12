-- DOGDEX window (UI kit, docs/UIKIT.md; spec §8).
--   COLLECTION  every species (#1-#100 and the bonus dogs): discovered ones with their base stats,
--               undiscovered ones as a dark silhouette with their rarity and "???"; progress header,
--               search (name or number), sort (number, rarity, name, income, efficiency) and filters
--               (found / missing, favourites, owned, rarity).
--   REWARDS     the collection reward track (DogEconomy.DexRewards): what each tier pays, a progress
--               bar and CLAIM buttons with the server's states (Snapshot.Features.Dogdex).
--   ENTRY       a stacked window for one species: preview, base stats with explanations (a Normal,
--               mastery-0 dog at your depth, from the server's income model), the variants you have
--               collected, your copies (opens MY DOGS), the ability and where to get it.
-- Entry points (GUIIntegration): N.OpenPage('DogDex') / N.OpenScreen('DogDex' | 'DexEntry') on every
-- device; VIEW IN DEX of MY DOGS opens the entry over MY DOGS. Requests: DexClaim, DexFavorite (Modules.Net).
local RS = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Info = require(script.Parent.DogInfo)
local Dict = require(RS:WaitForChild("Localization"):WaitForChild("Dogs"))
local Economy = RS:WaitForChild("DogEconomy")
local Config = require(Economy:WaitForChild("Config"))
local Defs = require(Economy:WaitForChild("DogDefinitions"))
local Rewards = require(Economy:WaitForChild("DexRewards"))
local Theme, Format = Kit.Theme, Kit.Format
local P = Theme.Colors
local ACCENT = Color3.fromRGB(92, 142, 250) -- UITheme.WindowSpecs.DogDex
local GREEN_TEXT = Color3.fromRGB(74, 170, 22)
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
local function fixed(n: any, decimals: number): string
	return string.format("%." .. decimals .. "f", tonumber(n) or 0)
end
local function pct(fraction: any): string
	local v = (tonumber(fraction) or 0) * 100
	if math.abs(v) < 0.05 then
		return "0%"
	end
	return "+" .. (v >= 10 and string.format("%.0f", v) or string.format("%.1f", v)) .. "%"
end
local function blockName(tier: string): string
	local names = {
		Common = T("Common Lucky Block"),
		Rare = T("Rare Lucky Block"),
		Epic = T("Epic Lucky Block"),
		Legendary = T("Legendary Lucky Block"),
		Mythic = T("Mythic Lucky Block"),
		Secret = T("Secret Lucky Block"),
	}
	return names[tier] or tier
end
local function titleName(tier: any): string
	local names = {
		["DOG SPOTTER"] = T("DOG SPOTTER"),
		["DOG COLLECTOR"] = T("DOG COLLECTOR"),
		["DOGDEX EXPERT"] = T("DOGDEX EXPERT"),
		["DOG SCHOLAR"] = T("DOG SCHOLAR"),
		["DOG LEGEND"] = T("DOG LEGEND"),
		["DOGDEX MASTER"] = T("DOGDEX MASTER"),
	}
	local name = tier.TitleName or tier.Title or ""
	return names[name] or name
end
local function variantName(v: string): string
	local names = {
		Normal = T("NORMAL"),
		Shiny = T("SHINY"),
		Golden = T("GOLDEN"),
		Corrupted = T("CORRUPTED"),
		Glitched = T("GLITCHED"),
		Void = T("VOID"),
	}
	return names[v] or string.upper(v)
end
local function rarityName(r: string): string
	local names = {
		Common = T("COMMON"),
		Rare = T("RARE"),
		Epic = T("EPIC"),
		Legendary = T("LEGENDARY"),
		Mythic = T("MYTHIC"),
		Secret = T("SECRET"),
	}
	return names[r] or string.upper(r)
end

local function layerName(name: string?): string
	local names = {
		Backyard = T("Backyard"),
		Caverns = T("Caverns"),
		["Ancient Ruins"] = T("Ancient Ruins"),
		["Cursed Depths"] = T("Cursed Depths"),
		["THE VOID"] = T("THE VOID"),
	}
	return names[name or ""] or tostring(name or "?")
end

-- What a tier pays, as one line ("🦴 25 Bones · $45K Coins · Rare Lucky Block · Title").
local function rewardParts(tier: any, coins: number?): { string }
	local parts = {}
	table.insert(parts, F("🦴 %d Bones", tier.Bones or 0))
	if coins and coins > 0 then
		table.insert(parts, F("💰 %s Coins", short(coins)))
	end
	if tier.Block then
		if (tier.Block.Count or 1) > 1 then
			table.insert(parts, F("🎁 %d × %s", tier.Block.Count, blockName(tier.Block.Tier)))
		else
			table.insert(parts, "🎁 " .. blockName(tier.Block.Tier))
		end
	end
	if tier.Title then
		table.insert(parts, F("🏷 Title “%s”", titleName(tier)))
	end
	return parts
end
S.RewardParts = rewardParts

-- Translated dog names (hidden labels translated by DOGROTS_AutoTranslateUI).
local probes: { [string]: any } = {}
local function dogName(id: string?): string
	local probe = id and probes[id]
	if probe and probe.Parent then
		return probe.Text
	end
	local def = id and Defs[id]
	return def and def.DisplayName or tostring(id or "")
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st: any = {
	Search = "",
	Filter = {}, -- Found, Missing, Favorite, Owned
	Rarities = {},
	Sort = "number",
	Desc = false,
	Snapshot = nil,
	Entries = {},
	List = {},
	Entry = nil, -- DogId shown in the entry window
	Claiming = false,
	Rows = {},
	Count = 0,
}
S.State = st
local ui: any = nil
local win: any = nil
local entryWin: any = nil
local ew: any = nil
local openToken = 0

local function profile(): any
	return st.Snapshot and st.Snapshot.Profile or nil
end
local function dexView(): any
	local features = st.Snapshot and st.Snapshot.Features
	return type(features) == "table" and features.Dogdex or nil
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
local function navigate(destination: string)
	local ok, N = pcall(function()
		return require(script.Parent.GUIIntegration)
	end)
	if ok and N and type(N.Navigate) == "function" then
		N.Navigate(destination)
	end
end

------------------------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------------------------
local function names(): any
	local out = {}
	for id in pairs(probes) do
		out[id] = dogName(id)
	end
	return out
end

local function filterAndSort(): { any }
	local filter = {
		Query = Info.Fold(st.Search),
		Found = st.Filter.Found,
		Missing = st.Filter.Missing,
		Favorite = st.Filter.Favorite,
		Owned = st.Filter.Owned,
		Rarities = st.Rarities,
	}
	local list = {}
	for _, e in ipairs(st.Entries) do
		if Info.MatchSpecies(e, filter) then
			table.insert(list, e)
		end
	end
	return Info.SortSpecies(list, st.Sort, st.Desc)
end

local function entryOf(id: string?): any
	for _, e in ipairs(st.Entries) do
		if e.Id == id then
			return e
		end
	end
	return nil
end

local function cardData(e: any): any
	local def = e.Def
	local stats = nil
	if e.Found and e.Stats then
		stats = { { Text = "$" .. short(e.Stats.C) }, { Text = "x" .. fixed(e.Stats.E, 2), Color = (tonumber(e.Stats.E) or 0) >= 3 and P.gold or nil } }
	end
	local number = def.MuseumExcluded and T("BONUS") or string.format("#%03d", def.Index or 0)
	return {
		Id = e.Id,
		Name = e.Found and def.DisplayName or "???",
		Rarity = def.Rarity,
		Preview = { Kind = "Dog", DogId = def.Id, Variant = "Normal", Silhouette = not e.Found },
		Stats = stats,
		Subtitle = e.Found and "" or T("Not discovered yet"),
		Count = e.Owned > 1 and e.Owned or nil,
		Badge = number,
		BadgeColor = def.MuseumExcluded and P.gold or (e.Found and ACCENT or Theme.Disabled),
		Tag = e.Favorite and "★" or nil,
		TagColor = e.Favorite and P.gold or nil,
	}
end

------------------------------------------------------------------------------------------------
-- Reward claims
------------------------------------------------------------------------------------------------
local refresh: (snapshot: any?) -> ()
local refreshRewards: () -> ()

local function celebrate(count: number)
	local row = ui and ui.RewardRows[count]
	if not row then
		return
	end
	row.Scale.Scale = 1.3
	Kit.Motion.Tween(row.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	row.Flash.BackgroundTransparency = 0.2
	Kit.Motion.Tween(row.Flash, 0.6, { BackgroundTransparency = 1 })
end

function S.Claim(count: number, button: any?): boolean
	if st.Claiming then
		return false
	end
	st.Claiming = true
	if button then
		button:SetBusy(true)
	end
	local ok, result = Net.Request("DexClaim", { Count = count })
	st.Claiming = false
	if button then
		button:SetBusy(false)
	end
	if ok then
		local reward = type(result) == "table" and result.DexReward or nil
		local tier = Rewards.Get(count)
		local text
		if reward and tier then
			text = F("Reward for %d dogs: %s", count, table.concat(rewardParts(tier, reward.Coins), " · "))
		else
			text = said(type(result) == "table" and result.Message or result)
		end
		Kit.Toast(text, { Kind = "success", NoTranslate = true, Duration = 4 })
		celebrate(count)
		if not (type(result) == "table" and result.StateSnapshot) then
			task.spawn(function()
				Net.Snapshot(0)
			end)
		end
	else
		Kit.Toast(said(type(result) == "table" and result.Message or result), { Kind = "error" })
		task.spawn(function()
			Net.Snapshot(0)
		end)
	end
	return ok
end

function S.ClaimAll()
	if st.Claiming then
		return
	end
	local ready = {}
	for _, row in ipairs(st.Rows) do
		if row.State == "ready" then
			table.insert(ready, row.Count)
		end
	end
	task.spawn(function()
		ui.ClaimAll:SetBusy(true)
		for _, count in ipairs(ready) do
			if not S.Claim(count) then
				break
			end
		end
		ui.ClaimAll:SetBusy(false)
		refreshRewards()
	end)
end

------------------------------------------------------------------------------------------------
-- Window: COLLECTION and REWARDS
------------------------------------------------------------------------------------------------
local relayout: () -> ()
local refreshList: (resetScroll: boolean?) -> ()

local function buildRewardRow(parent: Instance, tier: any): any
	local r: any = { Tier = tier }
	local root = panel(parent, "Tier_" .. tier.Count, Theme.White)
	r.Root = root
	r.Flash = Kit.New("Frame", { Name = "Flash", BackgroundColor3 = P.gold, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = Z + 1 }, root)
	Kit.Corner(r.Flash, Theme.Radius.Card)
	r.Medal = Kit.New("Frame", { Name = "Medal", BackgroundColor3 = Theme.Disabled, BorderSizePixel = 0, ZIndex = Z + 2 }, root)
	Kit.Corner(r.Medal, "pill")
	r.MedalStroke = Kit.Stroke(r.Medal, P.edge, 3)
	r.Scale = Kit.New("UIScale", { Name = "Pop" }, r.Medal)
	r.Number = label(r.Medal, { Name = "Count", Text = tostring(tier.Count), TextSize = 24, Font = "numeric", AlignX = "Center", Color = Theme.White, Stroke = 0.2, Scaled = true, MinTextSize = 12, ZIndex = Z + 3 })
	r.Title = label(root, { Name = "Title", TextSize = 18, Scaled = true, MinTextSize = 11, ZIndex = Z + 2 })
	r.Gift = label(root, { Name = "Rewards", TextSize = 14, Color = Theme.InkMuted, Wrap = true, AlignY = "Top", ZIndex = Z + 2 })
	r.Bar = Kit.ProgressBar(root, { Name = "Progress", Value = 0, Height = 12, Color = ACCENT, ZIndex = Z + 2, NoTranslate = true })
	r.Button = Kit.Button(root, {
		Name = "Claim",
		Text = T("CLAIM"),
		Style = "success",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			task.spawn(function()
				S.Claim(tier.Count, r.Button)
				refreshRewards()
			end)
		end,
	})
	return r
end

local function build()
	if win then
		return
	end
	win = Kit.Window.new({
		Key = "DogDex",
		Title = T("DOGDEX"),
		Subtitle = T("Discover every dog and earn collection rewards"),
		Accent = ACCENT,
		Icon = "DogDex",
		NoTranslate = true,
		MaxSize = Vector2.new(1120, 780),
		Tabs = {
			{ Id = "collection", Text = T("COLLECTION"), NoTranslate = true },
			{ Id = "rewards", Text = T("REWARDS"), NoTranslate = true },
		},
		Tab = "collection",
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			S._closed()
		end,
		OnTab = function()
			relayout()
		end,
	})
	S.Window = win
	ui = { RewardRows = {}, Lang = Kit.Lang() }
	S.UI = ui
	local collection = win:Page("collection")
	local rewards = win:Page("rewards")
	ui.Collection, ui.RewardsPage = collection, rewards
	-- Hidden name probes.
	local probeFrame = Kit.New("Frame", { Name = "NameProbes", BackgroundTransparency = 1, Visible = false, Size = UDim2.fromOffset(1, 1) }, win.Body)
	local pending = false
	for _, def in ipairs(Info.Species) do
		local probe = Kit.New("TextLabel", { Name = def.Id, Text = def.DisplayName, BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1) }, probeFrame)
		probes[def.Id] = probe
		probe:GetPropertyChangedSignal("Text"):Connect(function()
			if pending then
				return
			end
			pending = true
			task.delay(0.2, function()
				pending = false
				if win and win.IsOpen then
					refresh(nil)
				end
			end)
		end)
	end
	ui.Probes = probes
	-- COLLECTION: progress header.
	ui.Header = panel(collection, "Progress", Theme.White)
	ui.CountText = label(ui.Header, { Name = "Count", TextSize = 30, Font = "numeric", Scaled = true, MinTextSize = 14 })
	ui.CountLabel = label(ui.Header, { Name = "CountLabel", Text = T("DISCOVERED"), TextSize = 14, Color = Theme.InkMuted, Scaled = true, MinTextSize = 9 })
	ui.Bar = Kit.ProgressBar(ui.Header, { Name = "Bar", Value = 0, Height = 22, Color = ACCENT, ZIndex = Z + 1, NoTranslate = true })
	ui.NextText = label(ui.Header, { Name = "Next", TextSize = 14, Color = Theme.InkMuted, Scaled = true, MinTextSize = 9 })
	ui.GoRewards = Kit.Button(ui.Header, {
		Name = "GoRewards",
		Text = T("REWARDS ›"),
		Style = "gold",
		TextSize = 15,
		ZIndex = Z + 1,
		NoTranslate = true,
		OnClick = function()
			win:SetTab("rewards")
		end,
	})
	-- COLLECTION: toolbar.
	ui.Search = Kit.SearchBox(collection, {
		Name = "Search",
		Placeholder = T("Search by name or number"),
		ZIndex = Z,
		OnChange = function(text)
			st.Search = text
			refreshList(true)
		end,
	})
	ui.Sort = Kit.SortSelect(collection, {
		Name = "Sort",
		Options = {
			{ Id = "number", Text = T("NUMBER"), NoTranslate = true, Descending = false },
			{ Id = "rarity", Text = T("RARITY"), NoTranslate = true },
			{ Id = "name", Text = T("NAME"), NoTranslate = true, Descending = false },
			{ Id = "income", Text = T("INCOME"), NoTranslate = true },
			{ Id = "efficiency", Text = T("EFFICIENCY"), NoTranslate = true },
		},
		Selected = "number",
		Descending = false,
		ZIndex = Z,
		OnChange = function(id, desc)
			st.Sort, st.Desc = id, desc
			refreshList(true)
		end,
	})
	local chipOptions = {
		{ Id = "f:Found", Text = T("FOUND"), Color = P.green, NoTranslate = true },
		{ Id = "f:Missing", Text = T("MISSING"), Color = Theme.Disabled, NoTranslate = true },
		{ Id = "f:Owned", Text = T("OWNED"), Color = ACCENT, NoTranslate = true },
		{ Id = "f:Favorite", Text = T("★ FAVOURITES"), Color = P.gold, NoTranslate = true },
	}
	for _, rarity in ipairs(Info.Rarities) do
		table.insert(chipOptions, { Id = "r:" .. rarity, Text = string.upper(rarity), Color = Theme.RarityColor(rarity) })
	end
	ui.Chips = Kit.Chips(collection, {
		Name = "Filters",
		Multi = true,
		Options = chipOptions,
		TextSize = 14,
		ZIndex = Z,
		OnChange = function(selected)
			local filter, rarities = {}, {}
			for _, id in ipairs(selected) do
				local kind, key = string.match(id, "^(%a):(.+)$")
				if kind == "f" then
					filter[key] = true
				elseif kind == "r" then
					rarities[key] = true
				end
			end
			st.Filter, st.Rarities = filter, rarities
			refreshList(true)
		end,
	})
	ui.GridHost = Kit.New("Frame", { Name = "GridHost", BackgroundTransparency = 1, ZIndex = Z }, collection)
	ui.Grid = Kit.CardGrid(ui.GridHost, {
		Name = "DexGrid",
		Kind = "Dog",
		CardSize = Vector2.new(164, 214),
		RowHeight = 78,
		ZIndex = Z,
		Map = cardData,
		Key = function(e)
			return e.Id
		end,
		OnClick = function(e)
			S.OpenEntry(e.Id, { Stack = true })
		end,
		Empty = { Icon = "DogDex", Title = T("NO DOGS MATCH"), Body = T("Try another search or filter."), NoTranslate = true },
	})
	-- REWARDS.
	ui.RewardHead = panel(rewards, "RewardHeader", Theme.White)
	ui.RewardCount = label(ui.RewardHead, { Name = "Count", TextSize = 22, Scaled = true, MinTextSize = 12 })
	ui.RewardBar = Kit.ProgressBar(ui.RewardHead, { Name = "Bar", Value = 0, Height = 20, Color = P.gold, ZIndex = Z + 1, NoTranslate = true })
	ui.RewardHint = label(ui.RewardHead, { Name = "Hint", TextSize = 14, Color = Theme.InkMuted, Scaled = true, MinTextSize = 9 })
	ui.ClaimAll = Kit.Button(ui.RewardHead, {
		Name = "ClaimAll",
		Text = T("CLAIM ALL"),
		Style = "success",
		TextSize = 16,
		ZIndex = Z + 1,
		NoTranslate = true,
		OnClick = function()
			S.ClaimAll()
		end,
	})
	ui.Track = Kit.New("ScrollingFrame", {
		Name = "Track",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = ACCENT,
		ZIndex = Z,
	}, rewards)
	for _, tier in ipairs(Rewards.Tiers) do
		ui.RewardRows[tier.Count] = buildRewardRow(ui.Track, tier)
	end
	ui.RewardNote = label(ui.Track, {
		Name = "Note",
		Text = T("The museum count includes every dog you have ever discovered (#1-#100). Rewards you claimed before stay claimed."),
		TextSize = 13,
		Color = Theme.InkMuted,
		Wrap = true,
		AlignY = "Top",
	})
	win.Resized:Connect(function()
		relayout()
	end)
end

local function layoutRewards(w: number, h: number, phone: boolean)
	local y = 0
	local headH = phone and 92 or 84
	ui.RewardHead.Position = UDim2.fromOffset(0, y)
	ui.RewardHead.Size = UDim2.fromOffset(w, headH)
	local claimW = phone and 120 or 160
	ui.RewardCount.Position = UDim2.fromOffset(14, 8)
	ui.RewardCount.Size = UDim2.fromOffset(w - claimW - 40, 26)
	ui.RewardBar.Instance.Position = UDim2.fromOffset(14, 38)
	ui.RewardBar.Instance.Size = UDim2.fromOffset(w - claimW - 40, 20)
	ui.RewardHint.Position = UDim2.fromOffset(14, 62)
	ui.RewardHint.Size = UDim2.fromOffset(w - claimW - 40, phone and 24 or 18)
	ui.ClaimAll.Instance.Position = UDim2.new(1, -(claimW + 12), 0.5, -22)
	ui.ClaimAll.Instance.Size = UDim2.fromOffset(claimW, 44)
	y += headH + 8
	ui.Track.Position = UDim2.fromOffset(0, y)
	ui.Track.Size = UDim2.fromOffset(w, math.max(40, h - y))
	local rowW = w - 10
	local medal = phone and 52 or 60
	local buttonW = phone and 100 or 136
	local textX = medal + 24
	local textW = rowW - textX - buttonW - 20
	local rowY = 0
	for _, tier in ipairs(Rewards.Tiers) do
		local r = ui.RewardRows[tier.Count]
		local giftH = textHeight(r.Gift.Text ~= "" and r.Gift.Text or "x", 14, textW)
		local rowH = math.max(phone and 88 or 80, 30 + giftH + 22)
		r.Root.Position = UDim2.fromOffset(0, rowY)
		r.Root.Size = UDim2.fromOffset(rowW, rowH)
		r.Medal.Position = UDim2.fromOffset(12, math.floor((rowH - medal) / 2))
		r.Medal.Size = UDim2.fromOffset(medal, medal)
		r.Number.Position = UDim2.fromOffset(6, 6)
		r.Number.Size = UDim2.new(1, -12, 1, -12)
		r.Title.Position = UDim2.fromOffset(textX, 8)
		r.Title.Size = UDim2.fromOffset(textW, 24)
		r.Gift.Position = UDim2.fromOffset(textX, 34)
		r.Gift.Size = UDim2.fromOffset(textW, giftH)
		r.Bar.Instance.Position = UDim2.fromOffset(textX, rowH - 20)
		r.Bar.Instance.Size = UDim2.fromOffset(textW, 12)
		r.Button.Instance.Position = UDim2.new(1, -(buttonW + 12), 0.5, -21)
		r.Button.Instance.Size = UDim2.fromOffset(buttonW, 42)
		rowY += rowH + 8
	end
	local noteH = textHeight(ui.RewardNote.Text, 13, rowW - 8)
	ui.RewardNote.Position = UDim2.fromOffset(4, rowY + 4)
	ui.RewardNote.Size = UDim2.fromOffset(rowW - 8, noteH)
	ui.Track.CanvasSize = UDim2.fromOffset(0, rowY + noteH + 12)
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
	local rowH = phone and 40 or 42
	local y = 0
	-- Progress header.
	if landscape then
		-- One compact row: count + bar + rewards button; the search row follows.
		local headH = 40
		ui.Header.Position = UDim2.fromOffset(0, y)
		ui.Header.Size = UDim2.fromOffset(w, headH)
		ui.CountText.Position = UDim2.fromOffset(10, 4)
		ui.CountText.Size = UDim2.fromOffset(92, 32)
		ui.CountLabel.Visible = false
		ui.NextText.Visible = false
		local goW = 128
		ui.Bar.Instance.Position = UDim2.fromOffset(110, 10)
		ui.Bar.Instance.Size = UDim2.fromOffset(math.max(60, w - 110 - goW - 24), 20)
		ui.GoRewards.Instance.Position = UDim2.new(1, -(goW + 6), 0, 4)
		ui.GoRewards.Instance.Size = UDim2.fromOffset(goW, 32)
		y += headH + gap
	else
		local headH = phone and 76 or 70
		ui.Header.Position = UDim2.fromOffset(0, y)
		ui.Header.Size = UDim2.fromOffset(w, headH)
		local countW = phone and 96 or 130
		local goW = phone and 112 or 150
		ui.CountText.Position = UDim2.fromOffset(12, 6)
		ui.CountText.Size = UDim2.fromOffset(countW, 36)
		ui.CountLabel.Visible = true
		ui.CountLabel.Position = UDim2.fromOffset(12, 44)
		ui.CountLabel.Size = UDim2.fromOffset(countW, 18)
		local barX = countW + 24
		local barW = math.max(60, w - barX - goW - 24)
		ui.Bar.Instance.Position = UDim2.fromOffset(barX, 12)
		ui.Bar.Instance.Size = UDim2.fromOffset(barW, 22)
		ui.NextText.Visible = true
		ui.NextText.Position = UDim2.fromOffset(barX, 40)
		ui.NextText.Size = UDim2.fromOffset(barW, phone and 28 or 20)
		ui.GoRewards.Instance.Position = UDim2.new(1, -(goW + 10), 0.5, -21)
		ui.GoRewards.Instance.Size = UDim2.fromOffset(goW, 42)
		y += headH + gap
	end
	-- Toolbar.
	local sortW = phone and (landscape and 190 or 160) or 220
	ui.Search.Instance.Position = UDim2.fromOffset(0, y)
	ui.Search.Instance.Size = UDim2.fromOffset(w - sortW - gap, rowH)
	ui.Sort.Instance.Position = UDim2.fromOffset(w - sortW, y)
	ui.Sort.Instance.Size = UDim2.fromOffset(sortW, rowH)
	y += rowH + gap
	local chipsH = phone and 34 or 36
	ui.Chips.Instance.Position = UDim2.fromOffset(0, y)
	ui.Chips.Instance.Size = UDim2.fromOffset(w, chipsH)
	y += chipsH + gap
	ui.GridHost.Position = UDim2.fromOffset(0, y)
	ui.GridHost.Size = UDim2.fromOffset(w, math.max(40, h - y))
	ui.Grid:Relayout()
	layoutRewards(w, h, phone)
end

refreshRewards = function()
	if not ui then
		return
	end
	local rows, count = Info.RewardRows(dexView(), profile())
	st.Rows, st.Count = rows, count
	local ready, nextLocked = Info.RewardSummary(rows)
	for _, row in ipairs(rows) do
		local r = ui.RewardRows[row.Count]
		local tier = row.Tier
		r.State = row.State
		local title = F("%d DOGS", tier.Count)
		if tier.Full then
			title = title .. " · " .. T("FULL COLLECTION")
		end
		r.Title.Text = title
		r.Gift.Text = table.concat(rewardParts(tier, row.Coins), "   ")
		r.Bar:SetValue(math.clamp(count / tier.Count, 0, 1))
		r.Bar:SetText(string.format("%d / %d", math.min(count, tier.Count), tier.Count))
		r.Bar.Instance.Visible = row.State == "locked"
		if row.State == "claimed" then
			r.Medal.BackgroundColor3 = P.green
			r.Button:SetText(T("CLAIMED ✓"))
			r.Button:SetStyle("secondary")
			r.Button:SetDisabled(true)
			r.Root.BackgroundColor3 = Theme.Lighten(P.green, 0.85)
		elseif row.State == "ready" then
			r.Medal.BackgroundColor3 = P.gold
			r.Button:SetText(T("CLAIM"))
			r.Button:SetStyle("success")
			r.Button:SetDisabled(st.Claiming)
			r.Root.BackgroundColor3 = Theme.Lighten(P.gold, 0.82)
		else
			r.Medal.BackgroundColor3 = Theme.Disabled
			r.Button:SetText(F("%d MORE", row.Missing))
			r.Button:SetStyle("secondary")
			r.Button:SetDisabled(true)
			r.Root.BackgroundColor3 = Theme.White
		end
	end
	ui.RewardCount.Text = F("%d / %d DOGS DISCOVERED", count, Rewards.Total)
	local nextTier = nextLocked and nextLocked.Tier or nil
	if nextTier then
		ui.RewardBar:SetValue(math.clamp(count / nextTier.Count, 0, 1))
		ui.RewardBar:SetText(string.format("%d / %d", count, nextTier.Count))
		ui.RewardHint.Text = F("%d more dogs for the next reward", nextTier.Count - count)
	else
		ui.RewardBar:SetValue(1)
		ui.RewardBar:SetText(string.format("%d / %d", count, Rewards.Total))
		ui.RewardHint.Text = ready > 0 and T("Claim your rewards!") or T("Every reward is yours. Amazing collection!")
	end
	ui.ClaimAll:SetDisabled(ready == 0 or st.Claiming)
	ui.ClaimAll:SetText(ready > 1 and F("CLAIM ALL (%d)", ready) or T("CLAIM ALL"))
	win:SetBadge("rewards", ready > 0 and tostring(ready) or nil)
	-- Collection header.
	local dex = dexView()
	ui.CountText.Text = string.format("%d / %d", count, Rewards.Total)
	ui.Bar:SetValue(math.clamp(count / Rewards.Total, 0, 1))
	local bonus, bonusTotal = dex and tonumber(dex.Bonus) or 0, dex and tonumber(dex.BonusTotal) or 0
	ui.Bar:SetText(bonusTotal > 0 and F("BONUS DOGS %d / %d", bonus, bonusTotal) or "")
	if ready > 0 then
		ui.NextText.Text = F("%d rewards ready to claim!", ready)
		ui.NextText.TextColor3 = GREEN_TEXT
		ui.GoRewards:SetText(T("CLAIM ›"))
		ui.GoRewards:SetStyle("success")
	elseif nextTier then
		ui.NextText.Text = F("Next reward at %d dogs: %d to go", nextTier.Count, nextTier.Count - count)
		ui.NextText.TextColor3 = Theme.InkMuted
		ui.GoRewards:SetText(T("REWARDS ›"))
		ui.GoRewards:SetStyle("gold")
	else
		ui.NextText.Text = T("Every reward is yours. Amazing collection!")
		ui.NextText.TextColor3 = Theme.InkMuted
		ui.GoRewards:SetText(T("REWARDS ›"))
		ui.GoRewards:SetStyle("gold")
	end
	win:SetTitle(T("DOGDEX"), F("%d / %d discovered · %d rewards ready", count, Rewards.Total, ready))
	local layout = win:GetLayout()
	layoutRewards(layout.Width, layout.Height, layout.Phone)
end

refreshList = function(resetScroll: boolean?)
	if not ui then
		return
	end
	local list = filterAndSort()
	st.List = list
	ui.Grid:SetItems(list, { ResetScroll = resetScroll == true })
end

local refreshEntry: () -> ()

refresh = function(snapshot: any?)
	if snapshot then
		st.Snapshot = snapshot
	end
	if not ui or not st.Snapshot then
		return
	end
	st.Entries = Info.SpeciesEntries(profile(), dexView(), names())
	refreshList(false)
	refreshRewards()
	if entryWin and entryWin.IsOpen then
		refreshEntry()
	end
end
S.Refresh = refresh

------------------------------------------------------------------------------------------------
-- ENTRY window (one species)
------------------------------------------------------------------------------------------------
local SPECIES_STATS = {
	{ Id = "income", Label = "COINS / MIN", Tip = "Coins a Normal, mastery-0 copy earns per minute at your current depth, with your bonuses.", Key = "C" },
	{ Id = "efficiency", Label = "EFFICIENCY", Tip = "Its income compared with a plain Common dog (x1.00).", Key = "E" },
	{ Id = "speed", Label = "DIGS / MIN", Tip = "How many digs it makes per minute.", Key = "D" },
	{ Id = "luck", Label = "LUCK", Tip = "Extra chance of rare loot in every roll.", Key = "L" },
	{ Id = "finds", Label = "FINDS / MIN", Tip = "Discoveries (items for your bag) per minute.", Key = "F" },
	{ Id = "power", Label = "RARITY POWER", Tip = "Rarer dogs multiply the value of every loot roll.", Key = "power" },
}
S.SpeciesStats = SPECIES_STATS
local function speciesValue(id: string, stats: any, def: any): string
	if id == "power" then
		return "x" .. tostring(Info.Power(def))
	end
	if not stats then
		return "???"
	end
	if id == "income" then
		return "$" .. short(stats.C)
	elseif id == "efficiency" then
		return "x" .. fixed(stats.E, 2)
	elseif id == "speed" then
		return fixed(stats.D, 1)
	elseif id == "luck" then
		return pct((tonumber(stats.L) or 0) / 100)
	elseif id == "finds" then
		return fixed(stats.F, 2)
	end
	return "—"
end

local layoutEntry: () -> ()

local function buildEntry()
	entryWin = Kit.Window.new({
		Key = "DexEntry",
		Title = T("DOGDEX ENTRY"),
		Subtitle = "",
		Accent = ACCENT,
		Icon = "DogDex",
		Stack = true,
		NoTranslate = true,
		MaxSize = Vector2.new(900, 760),
		OnClose = function()
			st.Entry = nil
		end,
	})
	S.EntryWindow = entryWin
	ew = { Stats = {}, Dots = {}, Sources = {}, Lang = Kit.Lang() }
	S.EntryUI = ew
	local body = entryWin.Body
	ew.Scroll = Kit.New("ScrollingFrame", {
		Name = "EntryScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = ACCENT,
		ZIndex = Z,
	}, body)
	-- Hero (left column on desktop, top of the scroll on phones).
	ew.Hero = panel(body, "Hero", Theme.White)
	ew.Glow = Kit.New("Frame", { Name = "Glow", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, ew.Hero)
	Kit.Corner(ew.Glow, Theme.Radius.Card - 4)
	ew.Gradient = Kit.New("UIGradient", { Rotation = 90 }, ew.Glow)
	ew.Holder = Kit.New("Frame", { Name = "PreviewHolder", BackgroundTransparency = 1, ZIndex = Z + 2 }, ew.Hero)
	ew.Slot = Kit.Preview.Slot(ew.Holder)
	ew.Number = Kit.Pill(ew.Hero, { Name = "Number", Text = "#000", Color = ACCENT, Height = 24, TextSize = 14, Font = "numeric", ZIndex = Z + 3, NoTranslate = true })
	ew.Name = Kit.Text(ew.Hero, { Name = "DogName", TextSize = 26, Scaled = true, MinTextSize = 14, AlignX = "Center", ZIndex = Z + 2 })
	ew.Tags = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, ZIndex = Z + 2 }, ew.Hero)
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, ew.Tags)
	ew.Rarity = Kit.RarityTag(ew.Tags, "Common", { Height = 24, TextSize = 14, LayoutOrder = 1, ZIndex = Z + 3 })
	ew.Status = Kit.Pill(ew.Tags, { Name = "Status", Text = "", Color = P.green, Height = 24, TextSize = 13, LayoutOrder = 2, ZIndex = Z + 3, NoTranslate = true })
	ew.Prev = Kit.Button(ew.Hero, {
		Name = "Prev",
		Text = "‹",
		Style = "secondary",
		TextSize = 24,
		ZIndex = Z + 3,
		NoTranslate = true,
		OnClick = function()
			S.Step(-1)
		end,
	})
	ew.Next = Kit.Button(ew.Hero, {
		Name = "Next",
		Text = "›",
		Style = "secondary",
		TextSize = 24,
		ZIndex = Z + 3,
		NoTranslate = true,
		OnClick = function()
			S.Step(1)
		end,
	})
	ew.Fav = Kit.Button(ew.Hero, {
		Name = "Favorite",
		Text = "☆",
		Style = "secondary",
		TextSize = 20,
		ZIndex = Z + 3,
		NoTranslate = true,
		OnClick = function()
			local e = entryOf(st.Entry)
			if not (e and e.Found) then
				return
			end
			task.spawn(function()
				ew.Fav:SetBusy(true)
				local ok, result = Net.Request("DexFavorite", { Id = e.Id, Enabled = not e.Favorite })
				ew.Fav:SetBusy(false)
				if ok then
					Kit.Toast(e.Favorite and T("Removed from favourites") or T("Added to favourites"), { Kind = "success", NoTranslate = true })
				else
					Kit.Toast(said(type(result) == "table" and result.Message or result), { Kind = "error" })
				end
			end)
		end,
	})
	-- Sections inside the scroll.
	local function heading(name: string): any
		return label(ew.Scroll, { Name = name, TextSize = 17, Color = ACCENT })
	end
	ew.StatsTitle = heading("StatsTitle")
	ew.StatsNote = label(ew.Scroll, { Name = "StatsNote", TextSize = 13, Color = Theme.InkMuted, Wrap = true, AlignY = "Top" })
	for _, spec in ipairs(SPECIES_STATS) do
		local row = Kit.New("TextButton", { Name = "Stat_" .. spec.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, ew.Scroll)
		Kit.Corner(row, Theme.Radius.Small)
		Kit.Stroke(row, P.edge, 1, 0.82)
		local info = Kit.New("Frame", { Name = "Info", BackgroundColor3 = Theme.Colors.secondary, BorderSizePixel = 0, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(8, 7), ZIndex = Z + 2 }, row)
		Kit.Corner(info, "pill")
		label(info, { Name = "Glyph", Text = "i", TextSize = 13, AlignX = "Center", Font = "numeric", Color = ACCENT, ZIndex = Z + 3 })
		local name = label(row, { Name = "Label", Text = T(spec.Label), TextSize = 14, Color = Theme.InkMuted, Scaled = true, MinTextSize = 9, Position = UDim2.fromOffset(32, 0), Size = UDim2.new(0.6, -32, 0, 32), ZIndex = Z + 2 })
		local value = label(row, { Name = "Value", TextSize = 17, Font = "numeric", AlignX = "Right", Scaled = true, MinTextSize = 10, Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.4, -10, 0, 32), ZIndex = Z + 2 })
		local tip = label(row, { Name = "Tip", TextSize = 13, Color = Theme.InkMuted, Wrap = true, AlignY = "Top", Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 0), ZIndex = Z + 2 })
		tip.Visible = false
		row.Activated:Connect(function()
			ew.OpenTip = ew.OpenTip ~= spec.Id and spec.Id or nil
			layoutEntry()
		end)
		Kit.Tooltip(row, function()
			return T(spec.Tip), T(spec.Label)
		end)
		ew.Stats[spec.Id] = { Root = row, Label = name, Value = value, Tip = tip, Spec = spec }
	end
	ew.VariantTitle = heading("VariantTitle")
	for _, v in ipairs(Info.Variants) do
		local dot = Kit.New("Frame", { Name = "Variant_" .. v, BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z + 1 }, ew.Scroll)
		Kit.Corner(dot, Theme.Radius.Small)
		local circle = Kit.New("Frame", { Name = "Dot", BackgroundColor3 = Theme.VariantColor(v), BorderSizePixel = 0, ZIndex = Z + 2 }, dot)
		Kit.Corner(circle, "pill")
		local stroke = Kit.Stroke(circle, P.edge, 2, 0.2)
		local check = label(circle, { Name = "Check", Text = "✓", TextSize = 16, AlignX = "Center", Color = Theme.White, Stroke = 0.3, ZIndex = Z + 3 })
		local name = label(dot, { Name = "Name", Text = variantName(v), TextSize = 12, AlignX = "Center", Scaled = true, MinTextSize = 8, ZIndex = Z + 2 })
		ew.Dots[v] = { Root = dot, Circle = circle, Stroke = stroke, Check = check, Name = name }
	end
	ew.OwnTitle = heading("OwnTitle")
	ew.OwnText = label(ew.Scroll, { Name = "OwnText", TextSize = 15, Wrap = true, AlignY = "Top" })
	ew.OwnButton = Kit.Button(ew.Scroll, {
		Name = "SeeInMyDogs",
		Text = T("SEE IN MY DOGS"),
		Style = "primary",
		TextSize = 15,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			S.SeeInMyDogs(st.Entry)
		end,
	})
	ew.AbilityTitle = label(ew.Scroll, { Name = "AbilityTitle", TextSize = 17, Color = ACCENT })
	ew.AbilityText = Kit.Text(ew.Scroll, { Name = "AbilityText", TextSize = 15, Wrap = true, AlignY = "Top", ZIndex = Z + 1 })
	ew.SourceTitle = heading("SourceTitle")
	for i = 1, 5 do
		local row = Kit.New("Frame", { Name = "Source" .. i, BackgroundColor3 = Theme.SurfaceAlt, BorderSizePixel = 0, ZIndex = Z + 1 }, ew.Scroll)
		Kit.Corner(row, Theme.Radius.Small)
		local title = label(row, { Name = "Title", TextSize = 15, Scaled = true, MinTextSize = 10, ZIndex = Z + 2 })
		local sub = label(row, { Name = "Sub", TextSize = 13, Color = Theme.InkMuted, Scaled = true, MinTextSize = 9, ZIndex = Z + 2 })
		local go = Kit.Button(row, { Name = "Go", Text = T("SHOW THE WAY"), Style = "primary", TextSize = 13, ZIndex = Z + 2, NoTranslate = true })
		ew.Sources[i] = { Root = row, Title = title, Sub = sub, Go = go }
	end
	entryWin.Resized:Connect(function()
		layoutEntry()
	end)
end

local function sourceRow(source: any): (string, string, string?)
	if source.Key == "Line" then
		local chance = tonumber(source.Chance) or 0
		local odds = chance > 0 and Format.Number(math.max(1, math.floor(1 / chance + 0.5))) or "?"
		return T("DOG LINE"), F("About 1 in %s dogs on the tongue", odds), "Factory"
	elseif source.Key == "Lucky" then
		local tiers = {}
		for _, tier in ipairs(source.Tiers or {}) do
			table.insert(tiers, rarityName(tier))
		end
		return T("LUCKY BLOCKS"), F("From %s blocks", table.concat(tiers, ", ")), nil
	elseif source.Key == "Machine" then
		return T("DOG-O-MATIC"), T("A possible prize of the machine"), "DOG-O-MATIC PLAZA"
	elseif source.Key == "Jackpot" then
		return T("DOG-O-MATIC JACKPOT"), T("Exclusive: only the machine's jackpot gives it"), "DOG-O-MATIC PLAZA"
	end
	return T("TRADES & MARKET"), T("Get it from other players"), nil
end
S.SourceRow = sourceRow

local function heroMode(): string
	local layout = entryWin:GetLayout()
	if layout.Phone then
		return layout.Landscape and "landscape" or "portrait"
	end
	return "side"
end

refreshEntry = function()
	if not ew or not st.Entry then
		return
	end
	local e = entryOf(st.Entry)
	local def = Defs[st.Entry]
	if not def then
		return
	end
	local found = e and e.Found or false
	local dex = dexView()
	ew.Current = e
	local gradient = Theme.RarityGradient[def.Rarity]
	local top = gradient and gradient[1] or Theme.RarityColor(def.Rarity)
	ew.Gradient.Color = ColorSequence.new(top:Lerp(Theme.White, found and 0.4 or 0.75), Theme.White)
	ew.Slot:Show({ Kind = "Dog", DogId = def.Id, Variant = "Normal", Silhouette = not found })
	ew.Number:Set(def.MuseumExcluded and T("BONUS") or string.format("#%03d", def.Index or 0), def.MuseumExcluded and P.gold or ACCENT)
	ew.Name.Text = found and def.DisplayName or "???"
	ew.Rarity:SetRarity(def.Rarity)
	ew.Status:Set(found and T("DISCOVERED") or T("NOT DISCOVERED"), found and P.green or Theme.Disabled)
	ew.Fav.Instance.Visible = found
	ew.Fav:SetText(e and e.Favorite and "★" or "☆")
	ew.Fav:SetStyle(e and e.Favorite and "gold" or "secondary")
	entryWin:SetTitle(found and T("DOGDEX ENTRY") or T("UNDISCOVERED DOG"), def.MuseumExcluded and T("Bonus dog: not part of the 100") or F("Dog #%03d of %d", def.Index or 0, Rewards.Total))
	-- Base stats.
	ew.StatsTitle.Text = T("BASE STATS")
	local layer = Config.Layers[math.clamp(tonumber(dex and dex.Layer) or 1, 1, #Config.Layers)]
	ew.StatsNote.Text = found and F("A Normal dog at mastery 0 digging alone at your depth (%s), with your bonuses.", layerName(layer and layer.Name)) or T("Discover this dog to reveal its stats.")
	local stats = found and e and e.Stats or nil
	for _, spec in ipairs(SPECIES_STATS) do
		local r = ew.Stats[spec.Id]
		r.Value.Text = speciesValue(spec.Id, stats, def)
		r.Value.TextColor3 = (stats or spec.Id == "power") and Theme.Ink or Theme.InkMuted
	end
	-- Variants.
	local variants = dex and dex.VariantDex and dex.VariantDex[def.Id]
	if variants == nil then
		local p = profile()
		variants = p and p.VariantDex and p.VariantDex[def.Id]
	end
	local set, n = Info.VariantsOf(variants)
	ew.VariantTitle.Text = F("VARIANTS COLLECTED · %d / %d", n, #Info.Variants)
	for name, dot in pairs(ew.Dots) do
		local on = set[name] == true
		dot.Circle.BackgroundColor3 = on and Theme.VariantColor(name) or Theme.White
		dot.Circle.BackgroundTransparency = on and 0 or 0.2
		dot.Stroke.Transparency = on and 0.2 or 0.6
		dot.Check.Visible = on
		dot.Name.TextColor3 = on and Theme.Ink or Theme.InkMuted
	end
	-- Your dogs.
	ew.OwnTitle.Text = T("YOUR DOGS")
	local owned = e and e.Owned or 0
	if owned > 0 then
		ew.OwnText.Text = F("You own %d · best mastery %d", owned, e.BestMastery or 0)
	elseif found then
		ew.OwnText.Text = T("You have discovered it but own none right now.")
	else
		ew.OwnText.Text = T("Not discovered yet.")
	end
	ew.OwnButton.Instance.Visible = owned > 0
	-- Ability.
	ew.AbilityTitle.Visible = found
	ew.AbilityText.Visible = found
	if found then
		local okCatalog, catalog = pcall(function()
			return require(RS:WaitForChild("MuseumCatalog"))
		end)
		local ability = okCatalog and type(catalog) == "table" and catalog.AbilityLabel and catalog.AbilityLabel(def.Ability or "") or tostring(def.Ability or "")
		ew.AbilityTitle.Text = ru() and T("ABILITY") or ("ABILITY · " .. ability)
		ew.AbilityText.Text = def.Signature or ""
	end
	-- Where to get it.
	ew.SourceTitle.Text = T("WHERE TO GET IT")
	local sources = Info.Sources(def)
	for i, row in ipairs(ew.Sources) do
		local source = sources[i]
		row.Root.Visible = source ~= nil
		if source then
			local title, sub, destination = sourceRow(source)
			row.Title.Text = title
			row.Sub.Text = sub
			row.Go.Instance.Visible = destination ~= nil
			row.Go:SetOnClick(destination and function()
				navigate(destination)
			end or nil)
		end
	end
	-- Prev / next inside the current list.
	local list = (win and win.IsOpen and #st.List > 0) and st.List or st.Entries
	local index = 0
	for i, item in ipairs(list) do
		if item.Id == def.Id then
			index = i
			break
		end
	end
	ew.Prev:SetDisabled(index <= 1)
	ew.Next:SetDisabled(index == 0 or index >= #list)
	layoutEntry()
end

layoutEntry = function()
	if not ew then
		return
	end
	local layout = entryWin:GetLayout()
	local w, h = layout.Width, layout.Height
	if w < 2 then
		return
	end
	local mode = heroMode()
	local gap = 12
	local heroW, scrollX, scrollW
	if mode == "side" or mode == "landscape" then
		heroW = mode == "side" and math.floor(math.min(330, w * 0.4)) or math.floor(math.min(260, w * 0.36))
		ew.Hero.Parent = entryWin.Body
		ew.Hero.Position = UDim2.fromOffset(0, 0)
		ew.Hero.Size = UDim2.fromOffset(heroW, h)
		scrollX = heroW + gap
		scrollW = w - scrollX
	else
		heroW = w
		ew.Hero.Parent = ew.Scroll
		scrollX = 0
		scrollW = w
	end
	ew.Scroll.Position = UDim2.fromOffset(scrollX, 0)
	ew.Scroll.Size = UDim2.fromOffset(scrollW, h)
	-- Hero content.
	local heroH
	local preview
	if mode == "portrait" then
		preview = math.min(200, w - 120)
	elseif mode == "landscape" then
		preview = math.min(heroW - 24, h - 150)
	else
		preview = math.min(heroW - 32, h - 210, 280)
	end
	preview = math.max(80, preview)
	local px = math.floor((heroW - preview) / 2)
	ew.Glow.Position = UDim2.fromOffset(px, 12)
	ew.Glow.Size = UDim2.fromOffset(preview, preview)
	ew.Holder.Position = UDim2.fromOffset(px + 6, 18)
	ew.Holder.Size = UDim2.fromOffset(preview - 12, preview - 12)
	ew.Number.Instance.Position = UDim2.fromOffset(px + 8, 18)
	local y = 12 + preview + 8
	ew.Name.Position = UDim2.fromOffset(10, y)
	ew.Name.Size = UDim2.fromOffset(heroW - 20, 32)
	y += 36
	ew.Tags.Position = UDim2.fromOffset(10, y)
	ew.Tags.Size = UDim2.fromOffset(heroW - 20, 26)
	y += 34
	local navW = 52
	ew.Prev.Instance.Position = UDim2.fromOffset(10, y)
	ew.Prev.Instance.Size = UDim2.fromOffset(navW, 40)
	ew.Next.Instance.Position = UDim2.fromOffset(heroW - 10 - navW, y)
	ew.Next.Instance.Size = UDim2.fromOffset(navW, 40)
	ew.Fav.Instance.Position = UDim2.fromOffset(math.floor(heroW / 2 - 30), y)
	ew.Fav.Instance.Size = UDim2.fromOffset(60, 40)
	y += 48
	heroH = mode == "portrait" and y or h
	if mode == "portrait" then
		ew.Hero.Position = UDim2.fromOffset(0, 0)
		ew.Hero.Size = UDim2.fromOffset(heroW - 8, heroH)
	end
	-- Sections.
	local inner = scrollW - 10
	local sy = mode == "portrait" and heroH + 12 or 0
	ew.StatsTitle.Position = UDim2.fromOffset(2, sy)
	ew.StatsTitle.Size = UDim2.fromOffset(inner, 22)
	sy += 24
	local noteH = textHeight(ew.StatsNote.Text, 13, inner - 4)
	ew.StatsNote.Position = UDim2.fromOffset(2, sy)
	ew.StatsNote.Size = UDim2.fromOffset(inner - 4, noteH)
	sy += noteH + 4
	for _, spec in ipairs(SPECIES_STATS) do
		local r = ew.Stats[spec.Id]
		local open = ew.OpenTip == spec.Id
		local tipH = 0
		if open then
			r.Tip.Text = T(spec.Tip)
			tipH = textHeight(r.Tip.Text, 13, inner - 20) + 6
		end
		r.Tip.Visible = open
		r.Tip.Size = UDim2.new(1, -20, 0, tipH)
		r.Root.Position = UDim2.fromOffset(0, sy)
		r.Root.Size = UDim2.fromOffset(inner, 32 + tipH)
		sy += 32 + tipH + 5
	end
	sy += 8
	ew.VariantTitle.Position = UDim2.fromOffset(2, sy)
	ew.VariantTitle.Size = UDim2.fromOffset(inner, 22)
	sy += 26
	local count = #Info.Variants
	local cols = inner >= 420 and count or 3
	local cellW = math.floor((inner - (cols - 1) * 6) / cols)
	local cellH = 66
	for i, v in ipairs(Info.Variants) do
		local dot = ew.Dots[v]
		local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
		dot.Root.Position = UDim2.fromOffset(col * (cellW + 6), sy + line * (cellH + 6))
		dot.Root.Size = UDim2.fromOffset(cellW, cellH)
		dot.Circle.Position = UDim2.new(0.5, -17, 0, 6)
		dot.Circle.Size = UDim2.fromOffset(34, 34)
		dot.Name.Position = UDim2.fromOffset(4, 44)
		dot.Name.Size = UDim2.new(1, -8, 0, 18)
	end
	sy += math.ceil(count / cols) * (cellH + 6) + 8
	ew.OwnTitle.Position = UDim2.fromOffset(2, sy)
	ew.OwnTitle.Size = UDim2.fromOffset(inner, 22)
	sy += 26
	local ownW = ew.OwnButton.Instance.Visible and math.max(80, inner - 190) or inner
	ew.OwnText.Position = UDim2.fromOffset(2, sy)
	ew.OwnText.Size = UDim2.fromOffset(ownW - 6, 40)
	ew.OwnButton.Instance.Position = UDim2.fromOffset(inner - 180, sy)
	ew.OwnButton.Instance.Size = UDim2.fromOffset(180, 40)
	sy += 48
	if ew.AbilityTitle.Visible then
		ew.AbilityTitle.Position = UDim2.fromOffset(2, sy)
		ew.AbilityTitle.Size = UDim2.fromOffset(inner, 22)
		sy += 26
		local abilityH = textHeight(ew.AbilityText.Text, 15, inner - 4)
		ew.AbilityText.Position = UDim2.fromOffset(2, sy)
		ew.AbilityText.Size = UDim2.fromOffset(inner - 4, abilityH)
		sy += abilityH + 10
	end
	ew.SourceTitle.Position = UDim2.fromOffset(2, sy)
	ew.SourceTitle.Size = UDim2.fromOffset(inner, 22)
	sy += 26
	local goW = 132
	for _, row in ipairs(ew.Sources) do
		if row.Root.Visible then
			row.Root.Position = UDim2.fromOffset(0, sy)
			row.Root.Size = UDim2.fromOffset(inner, 54)
			local textW = inner - 24 - (row.Go.Instance.Visible and goW + 8 or 0)
			row.Title.Position = UDim2.fromOffset(12, 5)
			row.Title.Size = UDim2.fromOffset(textW, 22)
			row.Sub.Position = UDim2.fromOffset(12, 28)
			row.Sub.Size = UDim2.fromOffset(textW, 20)
			row.Go.Instance.Position = UDim2.new(1, -(goW + 8), 0.5, -18)
			row.Go.Instance.Size = UDim2.fromOffset(goW, 36)
			sy += 60
		end
	end
	ew.Scroll.CanvasSize = UDim2.fromOffset(0, sy + 12)
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
function S._opened()
	openToken += 1
	local token = openToken
	local cached = Net.Cached()
	if cached then
		refresh(cached)
	end
	relayout()
	task.spawn(function()
		local snapshot = Net.Snapshot(2)
		if snapshot and openToken == token and win.IsOpen then
			refresh(snapshot)
		end
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
end

Net.Changed:Connect(function(snapshot)
	if (win and win.IsOpen) or (entryWin and entryWin.IsOpen) then
		refresh(snapshot)
	end
end)

-- Labels are localized when a window is built: after a language change (LocaleId) the closed
-- windows are rebuilt on the next open.
local function rebuildIfLanguageChanged()
	if win and ui and ui.Lang ~= Kit.Lang() and not win.IsOpen and not (entryWin and entryWin.IsOpen) then
		ui.Grid:Destroy()
		win:Destroy()
		win, ui = nil, nil
		S.Window, S.UI = nil, nil
	end
	if entryWin and ew and ew.Lang ~= Kit.Lang() and not entryWin.IsOpen then
		ew.Slot:Destroy()
		entryWin:Destroy()
		entryWin, ew = nil, nil
		S.EntryWindow, S.EntryUI = nil, nil
	end
end

-- opts: {Tab = "collection" | "rewards"}
function S.Open(opts: any?)
	rebuildIfLanguageChanged()
	build()
	local o = opts or {}
	if o.Tab then
		win:SetTab(o.Tab, true)
	end
	win:Open()
end

function S.Close()
	if entryWin and entryWin.IsOpen then
		entryWin:Close("api")
	end
	if win and win.IsOpen then
		win:Close("api")
	end
end

function S.IsOpen(): boolean
	return win ~= nil and win.IsOpen
end

-- The entry of one species. opts.Stack: over whatever kit window is open (MY DOGS); otherwise the
-- Dogdex window opens first and the entry stacks over it.
function S.OpenEntry(dogId: string, opts: any?)
	local def = Defs[dogId]
	if not def then
		return
	end
	rebuildIfLanguageChanged()
	build()
	local o = opts or {}
	local top = Kit.Window.Top()
	if not (o.Stack and top and top.IsOpen) then
		if not win.IsOpen then
			win:Open()
		end
	end
	if not entryWin then
		buildEntry()
	end
	st.Entry = dogId
	ew.OpenTip = nil
	if st.Snapshot == nil then
		local cached = Net.Cached()
		if cached then
			refresh(cached)
		end
	end
	if #st.Entries == 0 then
		st.Entries = Info.SpeciesEntries(profile(), dexView(), names())
	end
	if not entryWin.IsOpen then
		entryWin:Open()
	end
	refreshEntry()
	ew.Scroll.CanvasPosition = Vector2.zero
	if not st.Snapshot then
		task.spawn(function()
			local snapshot = Net.Snapshot(2)
			if snapshot and entryWin.IsOpen then
				refresh(snapshot)
			end
		end)
	end
end

-- Next / previous species in the current list.
function S.Step(direction: number)
	local list = (win and win.IsOpen and #st.List > 0) and st.List or st.Entries
	for i, item in ipairs(list) do
		if item.Id == st.Entry then
			local target = list[i + direction]
			if target then
				st.Entry = target.Id
				ew.OpenTip = nil
				refreshEntry()
				ew.Scroll.CanvasPosition = Vector2.zero
				if win and win.IsOpen then
					ui.Grid:ScrollToKey(target.Id, true)
				end
			end
			return
		end
	end
end

-- MY DOGS filtered to this species.
function S.SeeInMyDogs(dogId: string?)
	if not dogId then
		return
	end
	local ok, Dogs = pcall(function()
		return require(script.Parent.DogsScreen)
	end)
	if not (ok and Dogs) then
		return
	end
	if entryWin and entryWin.IsOpen then
		entryWin:Close("dogs")
	end
	Dogs.Open({ Species = dogId })
end

-- Menus fallback (legacy 'DogDex' / 'DexEntry' screens): opens the windows instead.
function S.Build(c: any)
	task.defer(function()
		if c and c.Page == "DexEntry" then
			local id = S.ResolveEntry(c.State)
			if id then
				S.OpenEntry(id)
				return
			end
		end
		S.Open()
	end)
end

-- The species id of a legacy DexEntry request: SelectedDexBonus (a bonus DogId) or SelectedDexIndex
-- (#1-#100). preferIndex: the fields are the shared Menus state (the museum exhibits set only the
-- index there, so an older bonus id may be stale).
function S.ResolveEntry(state: any, preferIndex: boolean?): string?
	state = state or {}
	local bonus = type(state.SelectedDexBonus) == "string" and Defs[state.SelectedDexBonus] and state.SelectedDexBonus or nil
	local index = tonumber(state.SelectedDexIndex)
	local byIndex = nil
	if index then
		for _, def in ipairs(Info.Species) do
			if def.Index == index and not def.MuseumExcluded then
				byIndex = def.Id
			end
		end
	end
	if preferIndex then
		return byIndex or bonus
	end
	return bonus or byIndex
end

return S
