-- TITLES window (Kit, Key = "Titles"; GUIIntegration routes N.OpenPage("Titles") here). Built once:
--   * a live preview: your avatar with your equipped title drawn exactly as above your head
--     (ReplicatedStorage.TitleBadge, animated while the window is open), REMOVE, and the unlocked count;
--   * category chips (ALL, OWNED, every category) and a rarity / progress / name sort;
--   * a virtual grid of title cards: unlocked = colourful with EQUIP (EQUIPPED for the worn one),
--     locked = dimmed with a progress bar and how to get it; Secret titles stay "???" until unlocked.
-- Data: snapshot.Features.Titles (Economy.Features.Titles) through Modules.Net; equipping sends
-- 'TitleEquip' {Id}. The server checks everything again.
-- Screen.Watch() (started by PlayerTitles) shows "NEW TITLE UNLOCKED: ..." toasts: it diffs the
-- unlocked set of every snapshot Net publishes and fetches one when the TitleCount attribute grows.
-- Self-localized: Localization.Titles (Exact + Window) and the definitions' RU names.
--   Screen.Open(categoryId?), Screen.Close(), Screen.IsOpen(), Screen.Items(view, category, sort, desc)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Titles = require(RS:WaitForChild("DogEconomy"):WaitForChild("TitleDefinitions"))
local Badge = require(RS:WaitForChild("TitleBadge"))
local Dict = require(RS:WaitForChild("Localization"):WaitForChild("Titles"))

local Theme = Kit.Theme
local P = Theme.Colors
local ACCENT = Color3.fromRGB(249, 180, 35)
local Z = 3
local player = Players.LocalPlayer

local Screen = {}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function lang(): string
	return Kit.Lang()
end
local function T(en: string): string
	if lang() == "ru" then
		return Dict.Exact[en] or Dict.Window[en] or en
	end
	return en
end
Screen.T = T
local function serverText(message: any): string
	local text = type(message) == "table" and tostring(message.Message or "") or tostring(message or "")
	return T(text)
end
local function short(n: number): string
	return Kit.Format.Short(math.max(0, math.floor(n or 0)))
end
local function progressText(def: any, value: number, target: number): string
	if def.Format == "hours" then
		local h = T("h")
		return string.format("%d%s / %d%s", math.floor(value / 3600), h, math.floor(target / 3600), h)
	end
	return short(math.min(value, target)) .. " / " .. short(target)
end

------------------------------------------------------------------------------------------------
-- State and the item list (pure)
------------------------------------------------------------------------------------------------
local st: any = {
	Equipped = "",
	Unlocked = {},
	Progress = {},
	Loaded = false,
	Category = "all",
	Sort = "rarity",
	Desc = true,
	Busy = false,
}
local ui: any = nil

local function readSnapshot(snapshot: any): boolean
	local t = type(snapshot) == "table" and type(snapshot.Features) == "table" and snapshot.Features.Titles or nil
	if type(t) ~= "table" then
		return false
	end
	st.Equipped = type(t.Equipped) == "string" and t.Equipped or ""
	st.Unlocked = type(t.Unlocked) == "table" and t.Unlocked or {}
	st.Progress = type(t.Progress) == "table" and t.Progress or {}
	st.Loaded = true
	return true
end

-- view = {Equipped, Unlocked, Progress}; category "all" | "owned" | a category id;
-- sort "rarity" | "progress" | "name". Returns card items.
function Screen.Items(view: any, category: string?, sort: string?, desc: boolean?): { any }
	local unlockedSet = type(view.Unlocked) == "table" and view.Unlocked or {}
	local progress = type(view.Progress) == "table" and view.Progress or {}
	local items = {}
	local function add(def: any)
		local unlocked = unlockedSet[def.Id] ~= nil
		local pr = progress[def.Id]
		local value = type(pr) == "table" and tonumber(pr.Value) or (unlocked and 1 or 0)
		local target = type(pr) == "table" and tonumber(pr.Target) or def.Target or 1
		local ready = not unlocked and not def.Legacy and value >= target
		table.insert(items, {
			Id = def.Id,
			Def = def,
			Unlocked = unlocked or ready,
			Ready = ready,
			Equipped = view.Equipped == def.Id,
			Value = value,
			Target = math.max(1, target),
			Hidden = def.Hidden == true and not (unlocked or ready),
		})
	end
	for _, def in ipairs(Titles.List) do
		add(def)
	end
	local legacy = {}
	for id in pairs(unlockedSet) do
		local def = Titles.Get(id)
		if def and def.Legacy then
			table.insert(legacy, def)
		end
	end
	table.sort(legacy, function(a, b)
		return a.Id < b.Id
	end)
	for _, def in ipairs(legacy) do
		add(def)
	end
	category = category or "all"
	if category ~= "all" then
		local kept = {}
		for _, item in ipairs(items) do
			if (category == "owned" and item.Unlocked) or item.Def.Category == category then
				table.insert(kept, item)
			end
		end
		items = kept
	end
	local l = lang()
	local function name(item: any): string
		return item.Hidden and "~" or Titles.Text(item.Def, l)
	end
	sort = sort or "rarity"
	local flip = desc ~= false
	table.sort(items, function(a, b)
		if a.Equipped ~= b.Equipped then
			return a.Equipped
		end
		if sort == "name" then
			local x, y = name(a), name(b)
			if x ~= y then
				if flip then
					return x > y
				end
				return x < y
			end
		elseif sort == "progress" then
			local x = a.Unlocked and 2 or math.clamp(a.Value / a.Target, 0, 1)
			local y = b.Unlocked and 2 or math.clamp(b.Value / b.Target, 0, 1)
			if x ~= y then
				if flip then
					return x > y
				end
				return x < y
			end
		end
		local ra, rb = Titles.Rank(a.Def), Titles.Rank(b.Def)
		if ra ~= rb then
			if flip then
				return ra > rb
			end
			return ra < rb
		end
		if a.Unlocked ~= b.Unlocked then
			return a.Unlocked
		end
		local oa, ob = a.Def.Order or 0, b.Def.Order or 0
		if oa ~= ob then
			return oa < ob
		end
		return a.Id < b.Id
	end)
	return items
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
	p.NoTranslate = true
	return Kit.Text(parent, p)
end
local function rarityText(rarity: string?): string
	return Titles.RarityText(rarity, lang())
end

-- One title card (a VirtualGrid cell).
local function createCard(frame: Frame): any
	local c: any = {}
	local root = panel(frame, "TitleCard", Theme.White)
	root.Size = UDim2.new(1, 0, 1, 0)
	c.Root = root
	c.Stripe = Kit.New("Frame", { Name = "Stripe", BorderSizePixel = 0, BackgroundColor3 = ACCENT, ZIndex = Z + 1 }, root)
	Kit.Corner(c.Stripe, 4)
	c.StripeGradient = Kit.New("UIGradient", { Enabled = false }, c.Stripe)
	c.Icon = label(root, { Name = "Icon", Text = "", TextSize = 40, Scaled = true, MinTextSize = 14, AlignX = "Center", ZIndex = Z + 2 })
	c.Icon:SetAttribute("KeepFont", true)
	c.BadgeHolder = Kit.New("Frame", { Name = "BadgeHolder", BackgroundTransparency = 1, ZIndex = Z + 2 }, root)
	c.Badge = Badge.new(c.BadgeHolder, { ZIndex = Z + 2, Stroke = 0.8 })
	c.Name = label(root, { Name = "HiddenName", Text = "", TextSize = 18, Scaled = true, MinTextSize = 10, Color = Theme.InkMuted })
	c.Name.Visible = false
	c.Rarity = label(root, { Name = "Rarity", Text = "", TextSize = 13, Scaled = true, MinTextSize = 9, Font = "numeric" })
	c.Category = label(root, { Name = "Category", Text = "", TextSize = 13, Scaled = true, MinTextSize = 9, AlignX = "Right", Color = Theme.InkMuted })
	c.How = label(root, { Name = "How", Text = "", TextSize = 14, Wrap = true, AlignY = "Top", Color = Theme.Ink })
	c.Bar = Kit.ProgressBar(root, { Name = "Progress", Value = 0, Height = 18, Color = ACCENT, ZIndex = Z + 2, NoTranslate = true, TextSize = 12 })
	c.Button = Kit.Button(root, {
		Name = "Equip",
		Text = T("EQUIP"),
		Style = "gold",
		TextSize = 16,
		ZIndex = Z + 2,
		NoTranslate = true,
		OnClick = function()
			if c.Item then
				Screen.Equip(c.Item.Id, c.Button)
			end
		end,
	})
	c.Veil = Kit.New("Frame", { Name = "LockVeil", BackgroundColor3 = Theme.White, BackgroundTransparency = 0.38, BorderSizePixel = 0, ZIndex = Z + 4, Visible = false }, root)
	Kit.Corner(c.Veil, Theme.Radius.Small)
	c.Lock = label(c.Veil, { Name = "Lock", Text = "🔒", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Center", ZIndex = Z + 5 })
	c.Lock:SetAttribute("KeepFont", true)
	return c
end

local function layoutCard(c: any, w: number, h: number)
	local pad = 10
	c.Stripe.Position = UDim2.fromOffset(pad, 6)
	c.Stripe.Size = UDim2.fromOffset(w - pad * 2, 5)
	c.Icon.Position = UDim2.fromOffset(pad, 16)
	c.Icon.Size = UDim2.fromOffset(44, 44)
	local x = pad + 50
	c.TextX, c.TextW = x, w - x - pad
	c.BadgeHolder.Position = UDim2.fromOffset(x, 18)
	c.Name.Position = UDim2.fromOffset(x, 18)
	c.Name.Size = UDim2.fromOffset(c.TextW, 26)
	c.Veil.Position = UDim2.fromOffset(x - 4, 14)
	c.Veil.Size = UDim2.fromOffset(c.TextW + 6, 36)
	c.Lock.Position = UDim2.new(1, -26, 0, 4)
	c.Lock.Size = UDim2.fromOffset(22, 26)
	c.Rarity.Position = UDim2.fromOffset(x, 48)
	c.Rarity.Size = UDim2.fromOffset(math.floor(c.TextW * 0.5), 16)
	c.Category.Position = UDim2.fromOffset(x + math.floor(c.TextW * 0.5), 48)
	c.Category.Size = UDim2.fromOffset(c.TextW - math.floor(c.TextW * 0.5), 16)
	c.How.Position = UDim2.fromOffset(pad, 70)
	c.How.Size = UDim2.fromOffset(w - pad * 2, math.max(18, h - 70 - 52))
	c.Bar.Instance.Position = UDim2.fromOffset(pad, h - 30)
	c.Bar.Instance.Size = UDim2.fromOffset(w - pad * 2, 18)
	c.Button.Instance.Position = UDim2.fromOffset(pad, h - 44)
	c.Button.Instance.Size = UDim2.fromOffset(w - pad * 2, 36)
	c.W, c.H = w, h
	if c.Aspect then
		c.SizeBadge()
	end
end

local function bindCard(c: any, item: any)
	c.Item = item
	local def = item.Def
	local l = lang()
	local colors = Titles.Colors(def)
	local style = Titles.Style(def)
	-- Rarity stripe: colour or gradient (grey while locked).
	if item.Unlocked then
		c.Stripe.BackgroundColor3 = style.Gradient and Theme.White or colors[1]
		c.StripeGradient.Enabled = style.Gradient == true
		if style.Gradient then
			local points = {}
			for i, color in ipairs(colors) do
				table.insert(points, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), color))
			end
			c.StripeGradient.Color = ColorSequence.new(points)
		end
	else
		c.Stripe.BackgroundColor3 = Theme.Disabled
		c.StripeGradient.Enabled = false
	end
	c.Root.BackgroundColor3 = item.Equipped and Color3.fromRGB(255, 248, 225) or Theme.White
	if item.Hidden then
		c.Icon.Text = "❓"
		c.Badge:Set(nil)
		c.Name.Visible = true
		c.Name.Text = T("SECRET TITLE")
		c.How.Text = T("Keep exploring to reveal it.")
		c.Aspect = nil
	else
		c.Icon.Text = def.Icon or ""
		c.Name.Visible = false
		local aspect = c.Badge:Set(def, l)
		c.Aspect = aspect
		c.SizeBadge = function()
			local hgt = 30
			local wid = math.floor(hgt * aspect)
			if wid > (c.TextW or 150) then
				wid = c.TextW or 150
				hgt = math.max(16, math.floor(wid / aspect))
			end
			c.BadgeHolder.Size = UDim2.fromOffset(wid, hgt)
		end
		c.SizeBadge()
		c.How.Text = item.Ready and T("READY! Equip it.") or Titles.How(def, l)
	end
	c.Rarity.Text = rarityText(def.Rarity)
	c.Rarity.TextColor3 = Theme.RarityColor(def.Rarity)
	local cat = Titles.CategoryById[def.Category]
	c.Category.Text = cat and ((cat.Icon or "") .. " " .. (l == "ru" and cat.RU or cat.Text)) or ""
	c.Veil.Visible = not item.Unlocked
	c.Icon.TextTransparency = item.Unlocked and 0 or 0.45
	if item.Unlocked then
		c.Bar.Instance.Visible = false
		c.Button.Instance.Visible = true
		if item.Equipped then
			c.Button:SetText(T("EQUIPPED"))
			c.Button:SetStyle("secondary")
			c.Button:SetDisabled(true)
		else
			c.Button:SetText(T("EQUIP"))
			c.Button:SetStyle("gold")
			c.Button:SetDisabled(false)
		end
	else
		c.Button.Instance.Visible = false
		c.Bar.Instance.Visible = not item.Hidden and not def.Legacy
		c.Bar:SetValue(math.clamp(item.Value / item.Target, 0, 1), true)
		c.Bar:SetText(progressText(def, item.Value, item.Target))
	end
end

------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------
local refresh: () -> ()
local relayout: () -> ()

local function chipOptions(): { any }
	local l = lang()
	local options = {
		{ Id = "all", Text = T("ALL"), Color = ACCENT, NoTranslate = true },
		{ Id = "owned", Text = "✓ " .. T("OWNED"), Color = P.green, NoTranslate = true },
	}
	for _, cat in ipairs(Titles.Categories) do
		table.insert(options, { Id = cat.Id, Text = (cat.Icon or "") .. " " .. (l == "ru" and cat.RU or cat.Text), Color = P.blue, NoTranslate = true })
	end
	return options
end

local function build()
	if ui then
		return
	end
	ui = { Lang = lang() }
	local win = Kit.Window.new({
		Key = "Titles",
		Title = T("TITLES"),
		Subtitle = T("Earn titles with achievements and wear one above your head"),
		Accent = ACCENT,
		Icon = "Star",
		NoTranslate = true,
		MaxSize = Vector2.new(1100, 780),
		OnOpen = function()
			if ui.PreviewBadge then
				ui.PreviewBadge:SetAnimated(true)
			end
		end,
		OnClose = function()
			if ui.PreviewBadge then
				ui.PreviewBadge:SetAnimated(false)
			end
		end,
	})
	ui.Window = win
	local body = win.Body
	-- Preview stage: a dusk sky, your head shot and the title above it.
	ui.Stage = Kit.New("Frame", { Name = "PreviewStage", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = Z, ClipsDescendants = true }, body)
	Kit.Corner(ui.Stage, Theme.Radius.Card)
	Kit.Stroke(ui.Stage, P.edge, 2, 0.4)
	Kit.New("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 52, 104)), ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 88, 160)) }),
		Rotation = 90,
	}, ui.Stage)
	ui.Head = Kit.New("ImageLabel", {
		Name = "Head",
		BackgroundColor3 = Color3.fromRGB(230, 236, 250),
		BackgroundTransparency = 0.2,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = Z + 1,
	}, ui.Stage)
	Kit.Corner(ui.Head, "pill")
	ui.PreviewHolder = Kit.New("Frame", { Name = "PreviewTitle", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), ZIndex = Z + 2 }, ui.Stage)
	ui.PreviewBadge = Badge.new(ui.PreviewHolder, { ZIndex = Z + 2, Stroke = 1.2 })
	ui.NoTitle = label(ui.Stage, { Name = "NoTitle", Text = T("NO TITLE"), TextSize = 20, Scaled = true, MinTextSize = 10, AlignX = "Center", Color = Color3.fromRGB(220, 226, 245), Stroke = 0.4, AnchorPoint = Vector2.new(0.5, 1), ZIndex = Z + 2 })
	-- Info panel.
	ui.Info = panel(body, "Info", Theme.White)
	ui.InfoTitle = label(ui.Info, { Name = "Heading", Text = T("YOUR TITLE"), TextSize = 14, Scaled = true, MinTextSize = 9, Color = Theme.InkMuted })
	ui.InfoName = label(ui.Info, { Name = "Name", Text = "", TextSize = 22, Scaled = true, MinTextSize = 11 })
	ui.InfoHint = label(ui.Info, { Name = "Hint", Text = "", TextSize = 14, Wrap = true, AlignY = "Top", Color = Theme.InkMuted })
	ui.Remove = Kit.Button(ui.Info, {
		Name = "Remove",
		Text = T("REMOVE"),
		Style = "secondary",
		TextSize = 15,
		ZIndex = Z + 1,
		NoTranslate = true,
		OnClick = function()
			Screen.Equip("", ui.Remove)
		end,
	})
	ui.Count = label(ui.Info, { Name = "Count", Text = "", TextSize = 16, Scaled = true, MinTextSize = 9, Font = "numeric", AlignX = "Right" })
	ui.CountBar = Kit.ProgressBar(ui.Info, { Name = "CountBar", Value = 0, Height = 14, Color = ACCENT, ZIndex = Z + 1, NoTranslate = true })
	-- Toolbar.
	ui.Chips = Kit.Chips(body, {
		Name = "Categories",
		Options = chipOptions(),
		Selected = st.Category,
		AllowNone = false,
		TextSize = 14,
		ZIndex = Z,
		OnChange = function(id)
			st.Category = id or "all"
			refresh()
			if ui.Grid then
				ui.Grid:SetItems(ui.Items or {}, { ResetScroll = true })
			end
		end,
	})
	ui.Sort = Kit.SortSelect(body, {
		Name = "Sort",
		Options = {
			{ Id = "rarity", Text = T("RARITY"), NoTranslate = true },
			{ Id = "progress", Text = T("PROGRESS"), NoTranslate = true },
			{ Id = "name", Text = T("NAME"), NoTranslate = true, Descending = false },
		},
		Selected = st.Sort,
		Descending = st.Desc,
		ZIndex = Z,
		OnChange = function(id, desc)
			st.Sort, st.Desc = id, desc
			refresh()
		end,
	})
	ui.Status = label(body, { Name = "Status", Text = T("Loading your titles..."), TextSize = 16, AlignX = "Center", Color = Theme.InkMuted, ZIndex = Z + 6 })
	ui.Status.Visible = false
	-- Grid.
	ui.GridHost = Kit.New("Frame", { Name = "GridHost", BackgroundTransparency = 1, ZIndex = Z }, body)
	ui.Grid = Kit.VirtualGrid(ui.GridHost, {
		Name = "TitleGrid",
		CellSize = Vector2.new(236, 182),
		Gap = 10,
		Padding = 6,
		ZIndex = Z,
		Create = createCard,
		Layout = layoutCard,
		Bind = bindCard,
		Key = function(item)
			return item.Id
		end,
		Empty = { Icon = "Star", Title = T("NO TITLES HERE YET"), Body = T("Try another category."), NoTranslate = true },
	})
	win.Resized:Connect(function()
		relayout()
	end)
	-- Live: every newer snapshot and the projected equipped title.
	win.Maid:Give(Net.Changed:Connect(function(snapshot)
		if readSnapshot(snapshot) and win.IsOpen then
			refresh()
		end
	end))
	win.Maid:Give(player:GetAttributeChangedSignal("TitleId"):Connect(function()
		local id = player:GetAttribute("TitleId")
		if type(id) == "string" and id ~= st.Equipped then
			st.Equipped = id
			if win.IsOpen then
				refresh()
			end
		end
	end))
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
	local phone, landscape = layout.Phone, layout.Landscape
	local gap = phone and 6 or 10
	local y = 0
	local stageH, infoH
	if landscape then
		stageH = 92
		local stageW = math.min(300, math.floor(w * 0.42))
		ui.Stage.Position = UDim2.fromOffset(0, 0)
		ui.Stage.Size = UDim2.fromOffset(stageW, stageH)
		ui.Info.Position = UDim2.fromOffset(stageW + gap, 0)
		ui.Info.Size = UDim2.fromOffset(w - stageW - gap, stageH)
		infoH = stageH
		y = stageH + gap
	elseif phone then
		stageH = 104
		ui.Stage.Position = UDim2.fromOffset(0, 0)
		ui.Stage.Size = UDim2.fromOffset(w, stageH)
		infoH = 78
		ui.Info.Position = UDim2.fromOffset(0, stageH + gap)
		ui.Info.Size = UDim2.fromOffset(w, infoH)
		y = stageH + gap + infoH + gap
	else
		stageH = 136
		local stageW = math.min(380, math.floor(w * 0.42))
		ui.Stage.Position = UDim2.fromOffset(0, 0)
		ui.Stage.Size = UDim2.fromOffset(stageW, stageH)
		ui.Info.Position = UDim2.fromOffset(stageW + gap, 0)
		ui.Info.Size = UDim2.fromOffset(w - stageW - gap, stageH)
		infoH = stageH
		y = stageH + gap
	end
	-- Stage: head shot at the bottom centre, the title above it.
	local headSize = math.floor(stageH * 0.5)
	ui.Head.Position = UDim2.new(0.5, 0, 1, -8)
	ui.Head.Size = UDim2.fromOffset(headSize, headSize)
	ui.StageTitleBottom = stageH - 8 - headSize - 6
	ui.PreviewHolder.Position = UDim2.new(0.5, 0, 0, ui.StageTitleBottom)
	ui.NoTitle.Position = UDim2.new(0.5, 0, 0, ui.StageTitleBottom)
	ui.NoTitle.Size = UDim2.fromOffset(math.floor(ui.Stage.Size.X.Offset * 0.8), math.floor(ui.StageTitleBottom * 0.5))
	ui.StageW = ui.Stage.Size.X.Offset
	-- Info.
	local iw = ui.Info.Size.X.Offset
	local removeW = phone and 96 or 120
	ui.InfoTitle.Position = UDim2.fromOffset(12, 6)
	ui.InfoTitle.Size = UDim2.fromOffset(iw - removeW - 36, 16)
	ui.InfoName.Position = UDim2.fromOffset(12, 22)
	ui.InfoName.Size = UDim2.fromOffset(iw - removeW - 36, phone and 22 or 28)
	ui.Remove.Instance.Position = UDim2.new(1, -(removeW + 10), 0, 8)
	ui.Remove.Instance.Size = UDim2.fromOffset(removeW, 34)
	local compact = infoH < 100
	ui.InfoHint.Visible = not compact
	ui.InfoHint.Position = UDim2.fromOffset(12, 54)
	ui.InfoHint.Size = UDim2.fromOffset(iw - 24, math.max(16, infoH - 54 - 30))
	ui.Count.Position = UDim2.fromOffset(12, infoH - 26)
	ui.Count.Size = UDim2.fromOffset(110, 18)
	ui.CountBar.Instance.Position = UDim2.fromOffset(130, infoH - 24)
	ui.CountBar.Instance.Size = UDim2.fromOffset(math.max(40, iw - 142), 14)
	-- Toolbar.
	local rowH = phone and 38 or 40
	local sortW = phone and 150 or 200
	ui.Chips.Instance.Position = UDim2.fromOffset(0, y + math.floor((rowH - 36) / 2))
	ui.Chips.Instance.Size = UDim2.fromOffset(w - sortW - gap, 36)
	ui.Sort.Instance.Position = UDim2.fromOffset(w - sortW, y)
	ui.Sort.Instance.Size = UDim2.fromOffset(sortW, rowH)
	y += rowH + gap
	ui.GridHost.Position = UDim2.fromOffset(0, y)
	ui.GridHost.Size = UDim2.fromOffset(w, math.max(40, h - y))
	ui.Status.Position = UDim2.fromOffset(0, y + 20)
	ui.Status.Size = UDim2.fromOffset(w, 30)
	ui.Grid:Relayout()
	if ui.PreviewAspect then
		ui.SizePreview()
	end
end

local function paintPreview()
	local def = st.Equipped ~= "" and Titles.Get(st.Equipped) or nil
	local l = lang()
	if def then
		local aspect = ui.PreviewBadge:Set(def, l)
		ui.PreviewAspect = aspect
		ui.SizePreview = function()
			local maxW = math.floor((ui.StageW or 300) * 0.92)
			local hgt = math.max(18, math.min(40, math.floor((ui.StageTitleBottom or 60) * 0.62)))
			local wid = math.floor(hgt * aspect)
			if wid > maxW then
				wid = maxW
				hgt = math.max(14, math.floor(wid / aspect))
			end
			ui.PreviewHolder.Size = UDim2.fromOffset(wid, hgt)
		end
		ui.SizePreview()
		ui.PreviewHolder.Visible = true
		ui.NoTitle.Visible = false
		ui.PreviewBadge:SetAnimated(ui.Window.IsOpen)
		ui.InfoName.Text = (def.Icon or "") .. " " .. Titles.Text(def, l)
		ui.InfoName.TextColor3 = Titles.Colors(def)[1]:Lerp(Theme.Ink, 0.45)
		ui.InfoHint.Text = T("Everyone nearby sees it above your head.")
		ui.Remove:SetDisabled(false)
	else
		ui.PreviewBadge:Set(nil)
		ui.PreviewAspect = nil
		ui.PreviewHolder.Visible = false
		ui.NoTitle.Visible = true
		ui.InfoName.Text = T("NO TITLE")
		ui.InfoName.TextColor3 = Theme.InkMuted
		ui.InfoHint.Text = T("Pick an unlocked title below to show it above your head.")
		ui.Remove:SetDisabled(true)
	end
end

refresh = function()
	if not ui then
		return
	end
	local view = { Equipped = st.Equipped, Unlocked = st.Unlocked, Progress = st.Progress }
	local all = Screen.Items(view, "all", "rarity", true)
	local owned = 0
	for _, item in ipairs(all) do
		if item.Unlocked then
			owned += 1
		end
	end
	ui.Count.Text = owned .. " / " .. #all
	ui.CountBar:SetValue(#all > 0 and owned / #all or 0)
	ui.Items = Screen.Items(view, st.Category, st.Sort, st.Desc)
	ui.Grid:SetItems(ui.Items)
	ui.Status.Visible = not st.Loaded
	paintPreview()
end

------------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------------
function Screen.Equip(id: string, button: any?)
	if st.Busy then
		return
	end
	st.Busy = true
	if button then
		button:SetBusy(true)
	end
	task.spawn(function()
		local ok, result = Net.Request("TitleEquip", { Id = id })
		st.Busy = false
		if button then
			button:SetBusy(false)
		end
		if ok then
			st.Equipped = id
			if type(result) == "table" and type(result.StateSnapshot) == "table" then
				readSnapshot(result.StateSnapshot)
			end
			Kit.Toast(serverText(result), { Kind = "success", NoTranslate = true })
		else
			Kit.Toast(serverText(result), { Kind = "error", NoTranslate = true })
		end
		if ui then
			refresh()
		end
	end)
end

function Screen.Open(category: any?)
	build()
	if type(category) == "string" and (category == "all" or category == "owned" or Titles.CategoryById[category]) then
		st.Category = category
		ui.Chips:SetSelected(category, true)
	end
	readSnapshot(Net.Cached())
	local attr = player:GetAttribute("TitleId")
	if type(attr) == "string" then
		st.Equipped = attr
	end
	ui.Window:Open()
	relayout()
	refresh()
	local firstOpen = not st.Opened
	st.Opened = true
	task.spawn(function()
		local snapshot = Net.Snapshot(firstOpen and 0 or 3)
		if not ui.Window.IsOpen then
			return
		end
		if snapshot and readSnapshot(snapshot) then
			refresh()
		elseif not st.Loaded then
			ui.Status.Visible = true
			ui.Status.Text = T("Could not load your titles. Try again.")
		end
	end)
end

function Screen.Close()
	if ui and ui.Window.IsOpen then
		ui.Window:Close("close")
	end
end

function Screen.IsOpen(): boolean
	return ui ~= nil and ui.Window.IsOpen == true
end

------------------------------------------------------------------------------------------------
-- NEW TITLE UNLOCKED toasts
------------------------------------------------------------------------------------------------
local watching = false
function Screen.Watch()
	if watching then
		return
	end
	watching = true
	local known: { [string]: boolean }? = nil
	local function diff(snapshot: any)
		local t = type(snapshot) == "table" and type(snapshot.Features) == "table" and snapshot.Features.Titles or nil
		if type(t) ~= "table" or type(t.Unlocked) ~= "table" then
			return
		end
		if not known then
			-- The first snapshot is the baseline: titles you already had are not news.
			local base = {}
			for id in pairs(t.Unlocked) do
				base[id] = true
			end
			known = base
			return
		end
		local fresh = {}
		for id in pairs(t.Unlocked) do
			if not (known :: any)[id] then
				(known :: any)[id] = true
				local def = Titles.Get(id)
				if def then
					table.insert(fresh, def)
				end
			end
		end
		table.sort(fresh, function(a, b)
			return Titles.Rank(a) > Titles.Rank(b)
		end)
		local l = lang()
		for i, def in ipairs(fresh) do
			if i <= 3 then
				Kit.Toast(T("NEW TITLE UNLOCKED: ") .. (def.Icon or "") .. " " .. Titles.Text(def, l), { Kind = "success", NoTranslate = true, Duration = 4.5 })
			end
		end
		if #fresh > 3 then
			Kit.Toast(T("NEW TITLES UNLOCKED") .. ": +" .. (#fresh - 3) .. " " .. T("more"), { Kind = "success", NoTranslate = true, Duration = 4.5 })
		end
	end
	Net.Changed:Connect(diff)
	local last = player:GetAttribute("TitleCount")
	player:GetAttributeChangedSignal("TitleCount"):Connect(function()
		local n = player:GetAttribute("TitleCount")
		if type(n) == "number" and type(last) == "number" and n > last then
			task.spawn(Net.Snapshot, 0)
		end
		last = n
	end)
	task.spawn(function()
		diff(Net.Cached() or Net.Snapshot(30))
	end)
end

-- For the emulation harness and debugging.
function Screen.Internals(): any
	return ui, st
end

return Screen
