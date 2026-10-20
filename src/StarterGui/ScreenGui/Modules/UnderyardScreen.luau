-- THE UNDERYARD window (StarterGui.ScreenGui.Modules.UnderyardScreen; UI kit window, navigation key "Underyard", WP-L).
-- Routed by GUIIntegration.kitScreens: N.OpenPage("Underyard", arg) -> S.Open(arg). arg: nil | tab id | {Tab, Seal}
-- (case-insensitive): the seal altars send DogEconomyOpen("Underyard", {Tab = "Seals", Seal = i}) when the offering is
-- missing, the HALLOWEEN window's CHAPTER II card and the UNDERYARD rail tile open it without an argument.
-- Tabs:
--   seals       the 7 BELL SEALS: date lock with countdown, offering (catch-up discount, the guide's free offering),
--               OFFER / BEGIN TRIAL near the altar or start point else SHOW THE WAY, cleared / Gold, story, rewards
--   contracts   3 daily contracts (progress, CLAIM), the all-three bonus key, reset timer, the Toll Box exchange (daily cap),
--               today's Bell Shard efficiency (diminishing returns + rested pool)
--   coffin      keys and price, OPEN at the shrine (the opening itself is CoffinFX: request C2CoffinOpen), the exact
--               drop-rate table grouped by tier (Chapter2Rules.CoffinChance), duplicates, the last 10 results
--   dex         DEX II: H09-H16 (MenuModels previews, silhouettes, the Secret hides its name), milestones + CLAIM, OPEN DOGDEX
--   collection  Chapter II pickaxe skins / plot cosmetics / showcase finds owned vs missing with lazily built 3D previews,
--               fragments and THE TAILOR OF THE DEAD (craft with confirm); tap a card for its detail sheet
--   journal     the Event Journal: story entries EN/RU with REPLAY buttons (Bus events only: C2Replay {Id}, the
--               Chapter I guide, the brew finale); reading an entry marks it read (C2Journal)
-- Look: the HALLOWEEN window's custom kit skin in the Underyard palette (deep violet glass, moon-blue accents, candle
-- orange actions, sickly green progress); header chips Bell Shards + Coffin Keys; phones get the kit's full-screen sheet
-- and a slide-up detail sheet.
-- Data: the Chapter II view (Bus "StateChanged" View.Chapter2 / "C2Changed", every Request reply), the Halloween view (pickaxe
-- skins), player attributes (BellShards, CoffinKeys, LuckyDust, MoonCandy, UyInZone, UyTrial, UySealMask, UyTutorial,
-- HalloweenChapter1Complete) and RS.Halloween.State.Chapter2 (Phase / NextPhaseAt). Requests go to
-- RS.Halloween.Remotes.Request: C2Hello, C2SealOffer, C2TrialStart, C2ContractClaim, C2ContractBonus, C2Exchange,
-- C2CoffinOpen, C2DexClaim, C2Craft, C2Journal. Every rule (seal states, objective, badges, drop table) comes from
-- ReplicatedStorage.Halloween.UnderyardView; text from Localization.UnderyardUI (+ .Underyard); labels NoTranslate.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local Theme, Format, Motion = Kit.Theme, Kit.Format, Kit.Motion

local S: any = {}
S.Tabs = { "seals", "contracts", "coffin", "dex", "collection", "journal" }

local player = Players.LocalPlayer
local Halloween = RS:WaitForChild("Halloween", 10)
local function halloweenModule(name: string): any
	if not Halloween then
		return nil
	end
	local mod = Halloween:FindFirstChild(name) or Halloween:WaitForChild(name, 5)
	if not mod then
		return nil
	end
	local ok, m = pcall(require, mod)
	if not ok then
		warn("UnderyardScreen: " .. name .. ": " .. tostring(m))
		return nil
	end
	return m
end
local Shared = halloweenModule("Shared")
local Bus = halloweenModule("Bus")
local UV = halloweenModule("UnderyardView")
local UIcons = halloweenModule("UnderyardIcons")
local Layout = halloweenModule("UnderyardLayout")
local Cfg = UV and UV.Config or halloweenModule("Chapter2Config") or {}
local Rules = UV and UV.Rules or halloweenModule("Chapter2Rules")
local Waypoint = nil
do
	local mod = script:FindFirstChild("Waypoint")
	if mod then
		local ok, m = pcall(require, mod)
		Waypoint = ok and m or nil
	end
end
S.Waypoint = Waypoint

------------------------------------------------------------------------------------------------------------------------
-- Text (UnderyardView: Localization.UnderyardUI, then Localization.Underyard)
------------------------------------------------------------------------------------------------------------------------
local function lang(): string
	return Kit.Lang()
end
local function T(en: string): string
	return UV and UV.T(en, lang()) or en
end
local function F(en: string, ...: any): string
	if UV then
		return UV.F(en, lang(), ...)
	end
	local ok, out = pcall(string.format, en, ...)
	return ok and out or en
end
local function L(pair: any): string
	if UV then
		return UV.L(pair, lang())
	end
	return type(pair) == "table" and tostring(pair[1]) or tostring(pair or "")
end
-- server message -> (text, selfLocalized)
local function said(r: any): (string, boolean)
	local msg = type(r) == "table" and r.Message or r
	msg = tostring(msg or "")
	local out = UV and UV.Said(msg, lang())
	if out then
		return out, true
	end
	return msg, lang() ~= "ru"
end
local function upper(text: string): string
	return UV and UV.Upper(text) or string.upper(text)
end
local function num(n: any): string
	return Format.Number(math.floor(tonumber(n) or 0))
end
local function clock(sec: number): string
	return UV and UV.Clock(sec, lang()) or Format.Clock(sec)
end
S.T, S.F, S.L = T, F, L

------------------------------------------------------------------------------------------------------------------------
-- Palette (Chapter2Config.Palette + the HALLOWEEN window's glass)
------------------------------------------------------------------------------------------------------------------------
local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local VIOLET = C(150, 80, 230)
local VIOLET_HI = C(186, 140, 255)
local MOON = C(150, 200, 255)
local MOON_HI = C(206, 230, 255)
local SICKLY = C(120, 255, 140)
local CANDLE = C(255, 170, 80)
local BONE = C(230, 222, 200)
local GOLD = C(255, 204, 80)
local BLOOD = C(220, 50, 70)
local INK = C(14, 10, 26)
local BG_TOP, BG_BOTTOM = C(38, 28, 74), C(12, 9, 26)
local PANEL_TOP, PANEL_BOTTOM = C(52, 40, 96), C(28, 20, 56)
local PANEL_EDGE = C(112, 104, 196)
local TRACK = C(12, 8, 26)
local SOFT = C(218, 224, 255)
local MUTED = C(150, 150, 204)
local TAB_OFF = C(38, 30, 74)
local Z = 3
S.Palette = { Violet = VIOLET, Moon = MOON, Sickly = SICKLY, Candle = CANDLE, Gold = GOLD, Ink = INK }

local RARITY = {
	Common = C(176, 196, 214), Rare = Theme.Rarity.Rare, Epic = Theme.Rarity.Epic, Legendary = Theme.Rarity.Legendary,
	Mythic = Theme.Rarity.Mythic, Secret = Theme.Rarity.Secret,
}
local STATE_COLOR = { Waiting = C(96, 88, 140), Previous = C(78, 70, 120), Offer = CANDLE, Trial = MOON, Cleared = SICKLY, Gold = GOLD }

------------------------------------------------------------------------------------------------------------------------
-- UI helpers (dark Underyard glass on top of the kit components)
------------------------------------------------------------------------------------------------------------------------
local function textW(text: string, size: number): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(10000, 1000))
	end)
	if ok and v and v.X > 0 then
		return v.X
	end
	return (utf8.len(text) or #text) * size * 0.62
end

local function textH(text: string, size: number, width: number): number
	if text == "" then
		return 0
	end
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(math.max(10, width), 10000))
	end)
	if ok and v and v.Y > 0 then
		return math.ceil(v.Y) + 2
	end
	return math.ceil(textW(text, size) / math.max(10, width) + 0.5) * size * 1.2
end

local function place(o: any, x: number, y: number, w: number, h: number)
	o.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	o.Size = UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h)))
end

local function gradient(o: any, top: Color3, bottom: Color3, rotation: number?)
	local g = o:FindFirstChild("UyGradient")
	if not g then
		g = Kit.New("UIGradient", { Name = "UyGradient" }, o)
	end
	o.BackgroundColor3 = WHITE
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	return g
end

local function panel(parent: Instance, name: string, top: Color3?, bottom: Color3?, z: number?): any
	local f = Kit.New("Frame", { Name = name, BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = z or Z }, parent)
	Kit.Corner(f, 14)
	Kit.Stroke(f, PANEL_EDGE, 2, 0.2)
	gradient(f, top or PANEL_TOP, bottom or PANEL_BOTTOM)
	return f
end

local function txt(parent: Instance?, props: { [string]: any }): any
	local p = table.clone(props)
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	p.Color = p.Color or WHITE
	p.ZIndex = p.ZIndex or Z + 1
	return Kit.Text(parent, p)
end

local GLYPH = { Shard = "🔔", Key = "🗝", Coffin = "⚰", Dust = "✨", Fragment = "🧵", Seal = "🔔", Tombstone = "🪦", Relic = "💍", Eye = "👁",
	Lock = "🔒", Check = "✓", Star = "★", Bell = "🔔", Scroll = "📜", Skull = "💀", Ghost = "👻", Door = "🚪", Pickaxe = "⛏", Dog = "🐶",
	Crown = "👑", Book = "📖", Candy = "🍬", Bone = "🦴", Moon = "🌕", Cauldron = "🧪" }

-- a holder frame with a built icon (or its glyph when the icons are missing); returns frame, handle
local function icon(parent: Instance, name: string, kind: string, opts: { [string]: any }?, z: number?): (any, any)
	local f = Kit.New("Frame", { Name = name, BackgroundTransparency = 1, ZIndex = z or Z + 1 }, parent)
	local handle = nil
	if UIcons then
		local o = table.clone(opts or {})
		o.ZIndex = (z or Z + 1) + 1
		o.Size = o.Size or 40
		local ok, h = pcall(UIcons.New, f, kind, o)
		handle = ok and h or nil
	end
	if not handle then
		local g = txt(f, { Name = "Glyph", Text = GLYPH[kind] or "★", TextSize = 40, Scaled = true, MinTextSize = 6, AlignX = "Center", ZIndex = (z or Z + 1) + 1 })
		f:SetAttribute("UyGlyph", true)
		handle = {
			Glyph = g,
			Set = function(self, k)
				self.Glyph.Text = GLYPH[k] or "★"
				return self
			end,
		}
	end
	return f, handle
end
S.Icon = icon

local function button(parent: Instance, props: { [string]: any }): any
	local p = table.clone(props)
	p.ZIndex = p.ZIndex or Z + 2
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	return Kit.Button(parent, p)
end

local function bar(parent: Instance, name: string, color: Color3, height: number?): any
	return Kit.ProgressBar(parent, { Name = name, Color = color, Track = TRACK, Height = height or 18, TextSize = 13, NoTranslate = true, ZIndex = Z + 1 })
end

local function pill(parent: Instance, name: string, text: string, color: Color3, textColor: Color3?): any
	return Kit.Pill(parent, { Name = name, Text = text, Color = color, TextColor = textColor, Height = 24, TextSize = 13, PadX = 9,
		NoTranslate = true, ZIndex = Z + 2 })
end

local function scrollPage(page: Frame): any
	return Kit.New("ScrollingFrame", {
		Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
		ScrollBarThickness = 6, ScrollBarImageColor3 = PANEL_EDGE, ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, ZIndex = Z,
	}, page)
end

local function sectionTitle(parent: Instance, text: string, color: Color3?): any
	return txt(parent, { Name = "Heading", Text = text, TextSize = 20, Scaled = true, MinTextSize = 11, Color = color or WHITE, Stroke = 0.35 })
end

-- reward chips: a pill with the built icon and the amount / name (Chapter II reward rows)
local CHIP_COLOR = { Shards = C(104, 62, 168), Key = C(70, 72, 118), Dust = C(150, 112, 30), Fragments = C(118, 64, 150), Candy = C(200, 96, 20),
	Bones = C(120, 100, 80), Cash = C(70, 140, 60) }
local function chipLabel(row: any): (string, Color3)
	local kind = row.Kind
	if CHIP_COLOR[kind] then
		local n = tonumber(row.Amount) or 0
		return (kind == "Key" and n <= 1) and T("COFFIN KEY") or num(n), CHIP_COLOR[kind]
	end
	local rarity = UV and UV.RowRarity(row) or "Rare"
	local color = (RARITY[rarity] or VIOLET):Lerp(INK, 0.35)
	local name = upper(UV and UV.RowName(row, lang()) or tostring(row.Id))
	return name, color
end

local function chipRow(holder: any, rows: { any }, maxW: number, height: number?, center: boolean?): number
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local h = height or 26
	local x, y = 0, 0
	local placed = {}
	for i, row in ipairs(rows) do
		local text, color = chipLabel(row)
		local size = h >= 26 and 14 or 12
		local f = Kit.New("Frame", { Name = "Reward" .. i, BorderSizePixel = 0, BackgroundColor3 = color, ZIndex = Z + 3 }, holder)
		Kit.Corner(f, "pill")
		Kit.Stroke(f, INK, 1.5, 0.25)
		local kind, o: any = "Star", {}
		if UIcons then
			kind, o = UIcons.ForReward(row)
		end
		local ic = icon(f, "Icon", kind, { Size = h - 4, Color = o.Color, Glow = o.Glow }, Z + 4)
		place(ic, 2, 2, h - 4, h - 4)
		local label = txt(f, { Name = "Label", Text = text, TextSize = size, Scaled = true, MinTextSize = 7, ZIndex = Z + 5, Stroke = 0.45 })
		local w = math.ceil(textW(text, size)) + h + 10
		if maxW > 0 and w > maxW then
			w = maxW
		end
		place(label, h, 0, w - h - 8, h)
		if x > 0 and maxW > 0 and x + w > maxW then
			x, y = 0, y + h + 6
		end
		place(f, x, y, w, h)
		table.insert(placed, { F = f, X = x, Y = y, W = w })
		x += w + 6
	end
	if center and maxW > 0 then
		local lines = {}
		for _, p in ipairs(placed) do
			local line = lines[p.Y] or { Items = {}, Right = 0 }
			lines[p.Y] = line
			table.insert(line.Items, p)
			line.Right = math.max(line.Right, p.X + p.W)
		end
		for _, line in pairs(lines) do
			local dx = math.floor((maxW - line.Right) / 2)
			for _, p in ipairs(line.Items) do
				p.F.Position = UDim2.fromOffset(p.X + dx, p.Y)
			end
		end
	end
	return #rows > 0 and (y + h) or 0
end
S.ChipRow = chipRow

------------------------------------------------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------------------------------------------------
local st: any = { View = nil, HView = nil, Busy = {}, Tab = "seals", Amount = 10, HelloAt = -1e9, Read = {}, Sheet = nil }
S.State = st

local function view(): any
	return st.View or {}
end
local function hview(): any
	return st.HView or {}
end
local function now(): number
	return Kit.Now()
end
local function attr(name: string): any
	return player:GetAttribute(name)
end
local function root(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end
local function chapter2Enabled(): boolean
	if Shared and Shared.Chapter2Enabled then
		local ok, v = pcall(Shared.Chapter2Enabled)
		return ok and v == true
	end
	return false
end
local function eligible(): boolean
	return attr("HalloweenChapter1Complete") == true or (view().Chapter1 ~= nil and view().Chapter1.Complete == true)
end
local function inZone(): boolean
	local a = attr("UyInZone")
	if a ~= nil then
		return a == true
	end
	local r = root()
	return r ~= nil and Layout ~= nil and Layout.InZone(r.Position, 2)
end
local function inTrial(): boolean
	local t = attr("UyTrial")
	return type(t) == "string" and t ~= ""
end
local function shards(): number
	return tonumber(attr("BellShards")) or tonumber(view().Shards) or 0
end
local function keys(): number
	return tonumber(attr("CoffinKeys")) or tonumber(view().Keys) or 0
end
local function candy(): number
	return tonumber(attr("MoonCandy")) or tonumber(hview().Candy) or 0
end
local function anchorPos(name: string): Vector3?
	if not Layout then
		return nil
	end
	local part = Layout.AnchorPart(name)
	if part then
		return part.Position
	end
	return Layout.Anchor(name)
end
-- the client is a little stricter than the server (Proximity.Radius + Slack): the button lights where the server agrees
local function nearAnchor(name: string): boolean
	local r = root()
	local pos = anchorPos(name)
	local radius = ((Cfg.Proximity and Cfg.Proximity.Radius) or 16) + 2
	return r ~= nil and pos ~= nil and (r.Position - pos).Magnitude <= radius
end
local function ctx(): any
	return { Eligible = eligible(), InZone = inZone(), InTrial = inTrial(), Shards = shards(), Keys = keys(), Near = nearAnchor }
end
S.Ctx = ctx
local function nav(): any
	local ok, n = pcall(require, script.Parent.GUIIntegration)
	return ok and n or nil
end
local function audio(cue: string, opts: any?)
	if not Halloween then
		return
	end
	task.spawn(function()
		local mod = Halloween:FindFirstChild("Audio")
		if mod then
			local ok, A = pcall(require, mod)
			if ok and type(A) == "table" and A.Play and (not A.Has or A.Has(cue)) then
				pcall(A.Play, cue, nil, opts)
			end
		end
	end)
end
local function reduced(): boolean
	return Motion.Reduced() or (Shared ~= nil and Shared.ReducedMotion ~= nil and Shared.ReducedMotion()) or false
end
local function low(): boolean
	return Shared ~= nil and Shared.Low ~= nil and Shared.Low() or false
end

------------------------------------------------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------------------------------------------------
local win: any = nil
local ui: any = nil
local refreshAll: () -> ()
local revealTab: () -> ()

local function setViews(v: any)
	if type(v) ~= "table" then
		return
	end
	st.HView = v
	if type(v.Chapter2) == "table" then
		st.View = v.Chapter2
	end
end

local function invoke(action: string, args: any?): (boolean, any)
	local remotes = Halloween and Halloween:FindFirstChild("Remotes")
	local rf = remotes and remotes:FindFirstChild("Request")
	if not rf then
		return false, "Not ready"
	end
	local ok, a, b = pcall(function()
		return rf:InvokeServer(action, args or {})
	end)
	if not ok then
		return false, "Connection problem; try again"
	end
	if a and type(b) == "table" and type(b.View) == "table" then
		setViews(b.View)
		if Bus then
			Bus.Fire("StateChanged", { View = b.View })
		end
		if ui then
			refreshAll()
		end
	end
	return a == true, b
end
S.Invoke = invoke

local function toast(text: string, kind: string?, own: boolean?)
	Kit.Toast(text, { Kind = kind or "info", NoTranslate = own ~= false })
end

local function toastResult(ok: boolean, res: any, okText: string?)
	if ok then
		local text, own = okText, true
		if not text then
			text, own = said(res)
		end
		if text and text ~= "" then
			Kit.Toast(text, { Kind = "success", Sound = "Coin", NoTranslate = own })
		end
	else
		local text, own = said(res)
		if text == "" then
			text, own = T("Something went wrong, try again"), true
		end
		Kit.Toast(text, { Kind = "error", NoTranslate = own })
		audio("Deny")
	end
end

-- button-bound request: busy per action + key (two CLAIM buttons never block each other), a timeout that gives the
-- button back, toast, refresh
local REQUEST_TIMEOUT = 10
local function act(btn: any, key: string, action: string, args: any?, onOk: ((any) -> ())?, okText: string?)
	local busyKey = action .. ":" .. key
	if st.Busy[busyKey] then
		return
	end
	local token = {}
	st.Busy[busyKey] = token
	if btn then
		btn:SetBusy(true)
	end
	task.delay(REQUEST_TIMEOUT, function()
		if st.Busy[busyKey] == token then
			st.Busy[busyKey] = nil
			if btn then
				btn:SetBusy(false)
			end
			toast(T("No answer from the server. Try again."), "warn")
		end
	end)
	task.spawn(function()
		local ok, res = invoke(action, args)
		if st.Busy[busyKey] ~= token then
			return -- timed out: the late answer only refreshed the view
		end
		st.Busy[busyKey] = nil
		if btn then
			btn:SetBusy(false)
		end
		toastResult(ok, res, okText)
		if ok and onOk then
			onOk(res)
		end
		if ui then
			refreshAll()
		end
	end)
end

-- the reward card of the HALLOWEEN window (one reveal layer for both chapters; it knows the Chapter II rows)
local function hs(): any
	local mod = script.Parent:FindFirstChild("HalloweenScreen")
	if not mod then
		return nil
	end
	local ok, m = pcall(require, mod)
	return ok and type(m) == "table" and m or nil
end
local function reveal(title: string, rows: { any }?, kicker: string?)
	if type(rows) ~= "table" or #rows == 0 then
		return
	end
	local H = hs()
	if H and H.RewardReveal then
		local ok, err = pcall(H.RewardReveal, title, rows, { Kicker = kicker, Accent = VIOLET })
		if ok then
			return
		end
		warn("UnderyardScreen reward card: " .. tostring(err))
	end
	local parts = {}
	for _, row in ipairs(rows) do
		local text = chipLabel(row)
		table.insert(parts, text)
	end
	toast(title .. " · " .. table.concat(parts, " · "), "success")
end
S.Reveal = reveal

-- SHOW THE WAY: inside the Underyard a waypoint to the anchor (the window closes), outside the path to the church
local function churchDestination(): string
	local ok, D = pcall(function()
		return require(RS:WaitForChild("Navigation", 5):WaitForChild("Destinations", 5)) :: any
	end)
	if ok and type(D) == "table" and type(D.Resolve) == "function" and D.Resolve("Church") then
		return "Church"
	end
	return "DeadYard"
end
S.ChurchDestination = churchDestination
local function descend()
	local n = nav()
	if win and win.IsOpen then
		win:Close("way")
	end
	if n and n.Navigate then
		n.Navigate(churchDestination())
	end
	toast(T("Descend through the church in the Dead Yard"))
end
S.Descend = descend
local function showWay(anchor: string, label: string)
	if not inZone() then
		descend()
		return
	end
	local pos = anchorPos(anchor)
	if not (pos and Waypoint) then
		toast(T("The Underyard is not ready yet"), "warn")
		return
	end
	if win and win.IsOpen then
		win:Close("way")
	end
	if Waypoint.Show(pos, label, { Color = VIOLET_HI }) then
		audio("UiTab")
	end
end
S.ShowWay = showWay

------------------------------------------------------------------------------------------------------------------------
-- Dog previews (Kit.Preview kind "UyDog": MenuModels -> Models.EventDogs2 -> the built Dog icon)
------------------------------------------------------------------------------------------------------------------------
local function registerDogPreview(): string
	if S.PreviewKind then
		return S.PreviewKind
	end
	S.PreviewKind = "UyDog"
	Kit.Preview.Register("UyDog", function(spec, parent)
		local id = spec.DogId
		local models = RS:FindFirstChild("MenuModels")
		if models and models:FindFirstChild(id) then
			local okR, renderer = pcall(require, script.Parent.PreviewRenderer)
			if okR and renderer and renderer.Dog then
				local okD, v = pcall(renderer.Dog, parent, { DogId = id }, 0, 0, 128, 128, spec.Silhouette == true)
				if okD and v then
					return v
				end
			end
		end
		local folder = Halloween and Halloween:FindFirstChild("Models")
		local mod = folder and folder:FindFirstChild("EventDogs2")
		if mod then
			local okM, Dogs = pcall(require, mod)
			local okB, model = false, nil
			if okM and type(Dogs) == "table" and Dogs.Build then
				okB, model = pcall(Dogs.Build, id)
			end
			if okB and typeof(model) == "Instance" then
				local vp = Kit.New("ViewportFrame", { Name = "Preview", BackgroundTransparency = 1, Ambient = C(160, 160, 220), LightColor = C(230, 236, 255),
					LightDirection = Vector3.new(-1, -1, -0.6), Size = UDim2.fromScale(1, 1) })
				if spec.Silhouette then
					vp.ImageColor3 = Color3.new(0, 0, 0)
				end
				local cam = Instance.new("Camera")
				cam.FieldOfView = 30
				cam.Parent = vp
				vp.CurrentCamera = cam
				model.Parent = vp
				local okBox, cf, size = pcall(function()
					return (model :: any):GetBoundingBox()
				end)
				if okBox then
					local radius = size.Magnitude / 2
					local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05
					local dir = Vector3.new(-0.62, 0.32, -0.72).Unit
					cam.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position)
				end
				vp.Parent = parent
				return vp
			end
		end
		local holder = Kit.New("Frame", { Name = "Preview", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, parent)
		local _, h = icon(holder, "Dog", "Dog", { Size = 96, Color = spec.Silhouette and C(20, 16, 34) or nil, Outline = spec.Silhouette and C(90, 80, 140) or nil })
		local f = holder:FindFirstChild("Dog")
		if f then
			place(f, 14, 14, 100, 100)
			f.Size = UDim2.fromScale(0.8, 0.8)
			f.Position = UDim2.fromScale(0.1, 0.1)
		end
		local _ = h
		return holder
	end, function(spec)
		return tostring(spec.DogId) .. "|" .. (spec.Silhouette and "S" or "")
	end)
	return S.PreviewKind
end

-- a ViewportFrame framing `model` (3/4 view); returns frame, step(dt) (a slow turntable)
local function viewport(parent: Instance, model: Instance, z: number, pitch: number?): (any, any)
	local vp = Kit.New("ViewportFrame", { Name = "Preview3D", BackgroundTransparency = 1, Ambient = C(170, 166, 220), LightColor = C(240, 236, 255),
		LightDirection = Vector3.new(-1, -1.2, -0.6), Size = UDim2.fromScale(1, 1), ZIndex = z })
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	model.Parent = vp
	local okBox, cf, size = pcall(function()
		if model:IsA("Model") then
			return (model :: any):GetBoundingBox()
		end
		return (model :: any).CFrame, (model :: any).Size
	end)
	vp.Parent = parent
	if not okBox then
		return vp, function() end
	end
	local focus = cf.Position
	local dist = size.Magnitude / 2 / math.tan(math.rad(cam.FieldOfView / 2)) * 1.04
	local light0 = Vector3.new(-1, -1.2, -0.6)
	local p = math.rad(pitch or 16)
	local function at(a: number)
		local dir = Vector3.new(math.sin(a) * math.cos(p), math.sin(p), math.cos(a) * math.cos(p))
		cam.CFrame = CFrame.lookAt(focus + dir * dist, focus)
		vp.LightDirection = CFrame.Angles(0, a, 0) * light0
	end
	local spin = math.rad(-35)
	at(spin)
	return vp, function(dt: number)
		spin += dt * 0.8
		at(spin)
	end
end

-- a 3D model of a collection item (nil = the built icon); built on demand, never cached across windows
local function itemModel(item: any): Instance?
	local ok, model = false, nil
	if item.Kind == "Skin" then
		local mod = Halloween and Halloween:FindFirstChild("PickaxeSkins")
		if mod then
			local okM, Skins = pcall(require, mod)
			if okM and type(Skins) == "table" and Skins.Build then
				ok, model = pcall(Skins.Build, item.Id)
			end
		end
	elseif item.Kind == "Decor" then
		local folder = RS:FindFirstChild("Decor")
		local mod = folder and folder:FindFirstChild("DecorModels")
		if mod then
			local okM, Models = pcall(require, mod)
			if okM and type(Models) == "table" and Models.Get then
				ok, model = pcall(Models.Get, item.Id, 1)
			end
		end
	elseif item.Kind == "Find" then
		local economy = RS:FindFirstChild("DogEconomy")
		local mod = economy and economy:FindFirstChild("DiscoveryVisuals")
		if mod then
			local okM, Visuals = pcall(require, mod)
			if okM and type(Visuals) == "table" and Visuals.Clone then
				ok, model = pcall(Visuals.Clone, { ItemId = item.Id }, { NoScale = true })
			end
		end
	end
	if ok and typeof(model) == "Instance" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("ParticleEmitter") or d:IsA("Sound") or d:IsA("Light") or d:IsA("Beam") then
				d:Destroy()
			end
		end
		return model
	end
	return nil
end
S.ItemModel = itemModel

------------------------------------------------------------------------------------------------------------------------
-- Detail sheet (phones: slides up from the bottom; desktop: a centred card) over the window body
------------------------------------------------------------------------------------------------------------------------
local function closeSheet(reason: string?)
	local sh = st.Sheet
	st.Sheet = nil
	if not sh then
		return
	end
	if sh.Entry and Kit.Overlay and Kit.Overlay.Remove then
		Kit.Overlay.Remove(sh.Entry)
	end
	if sh.Conn then
		sh.Conn:Disconnect()
	end
	sh.Root:Destroy()
	local _ = reason
end
S.CloseSheet = closeSheet

-- spec = {Title, Sub, Rarity, Body, Kind (icon kind), Model? (Instance), Button = {Text, Style, Disabled, OnClick}?}
local function openSheet(spec: any)
	closeSheet("replaced")
	if not (win and win.IsOpen) then
		return
	end
	local L0 = win:GetLayout()
	local body = win.Body
	local rootF = Kit.New("Frame", { Name = "UySheet", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 40 }, body)
	local shade = Kit.New("TextButton", { Name = "Shade", Text = "", AutoButtonColor = false, BackgroundColor3 = INK, BackgroundTransparency = 0.45,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 40, Selectable = false }, rootF)
	local W0, H0 = L0.Width or 600, L0.Height or 400
	local phone = L0.Phone == true
	local landscape = L0.Landscape == true
	local pw = phone and W0 or math.min(560, W0 - 40)
	local ph = phone and math.floor(H0 * (landscape and 0.96 or 0.82)) or math.min(H0 - 40, 470)
	local card = panel(rootF, "Card", C(56, 42, 104), C(18, 12, 40), 41)
	card.Active = true
	card.ClipsDescendants = true
	local x0 = math.floor((W0 - pw) / 2)
	local y0 = phone and (H0 - ph) or math.floor((H0 - ph) / 2)
	place(card, x0, y0, pw, ph)
	local close = button(card, { Name = "Close", Text = "X", Style = "danger", TextSize = 18, ZIndex = 46, OnClick = function()
		closeSheet("button")
	end })
	place(close.Instance, pw - 52, 10, 42, 42)
	local side = (not phone) or landscape
	local previewS = side and math.min(math.floor(pw * 0.42), ph - 40) or math.min(pw - 40, math.floor(ph * 0.42))
	local holder = Kit.New("Frame", { Name = "PreviewHolder", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 42, ClipsDescendants = true }, card)
	Kit.Corner(holder, 14)
	local rc = RARITY[spec.Rarity or "Rare"] or VIOLET
	gradient(holder, rc:Lerp(C(40, 30, 80), 0.6), C(10, 8, 22))
	local step = nil
	if typeof(spec.Model) == "Instance" then
		local okV, _, fn = pcall(viewport, holder, spec.Model, 43)
		if okV then
			step = fn
		end
	elseif spec.Preview and type(spec.Preview) == "table" then
		local slot = Kit.Preview.Slot(holder)
		slot:Show(spec.Preview)
	end
	if not step and not spec.Preview then
		local f = icon(holder, "Art", spec.Kind or "Star", { Size = previewS, Color = spec.IconColor, Dim = spec.Dim }, 43)
		f.Size = UDim2.fromScale(0.74, 0.74)
		f.Position = UDim2.fromScale(0.13, 0.13)
	end
	local tx, ty, tw
	if side then
		place(holder, 16, 16, previewS, previewS)
		tx, ty, tw = previewS + 30, 18, pw - previewS - 30 - 60
	else
		place(holder, math.floor((pw - previewS) / 2), 16, previewS, previewS)
		tx, ty, tw = 16, previewS + 26, pw - 32
	end
	local title = txt(card, { Name = "Title", Text = spec.Title or "", TextSize = 22, Scaled = true, MinTextSize = 12, Stroke = 0.3, ZIndex = 44 })
	place(title, tx, ty, side and tw or tw - 50, 28)
	local tag = Kit.Pill(card, { Name = "Rarity", Text = T(string.upper(spec.Rarity or "Rare")), Color = rc, Height = 22, TextSize = 12, NoTranslate = true, ZIndex = 44 })
	local grad = Theme.RarityGradient[spec.Rarity or ""]
	if grad then
		tag:SetGradient(grad[1], grad[2])
	end
	tag.Instance.Position = UDim2.fromOffset(tx, ty + 32)
	local sub = txt(card, { Name = "Sub", Text = spec.Sub or "", TextSize = 14, Scaled = true, MinTextSize = 9, Color = MOON_HI, ZIndex = 44 })
	place(sub, tx, ty + 60, tw + (side and 44 or 0), 20)
	local buttonH = 46
	local bodyText = spec.Body or ""
	local bodyY = ty + 86
	local bodyH = math.max(20, ph - bodyY - buttonH - 28)
	local bodyL = txt(card, { Name = "Body", Text = bodyText, TextSize = 14, Wrap = true, AlignY = "Top", Color = SOFT, ZIndex = 44 })
	local fit = 14
	while fit > 10 and textH(bodyText, fit, tw + (side and 44 or 0)) > bodyH do
		fit -= 1
	end
	bodyL.TextSize = fit
	place(bodyL, tx, bodyY, tw + (side and 44 or 0), bodyH)
	if spec.Button then
		local b = spec.Button
		local btn
		btn = button(card, { Name = "Action", Text = b.Text or "", Style = b.Style or "primary", Color = b.Color, TextSize = 17, ZIndex = 45,
			OnClick = function()
				if b.OnClick then
					b.OnClick(btn)
				end
			end })
		btn:SetDisabled(b.Disabled == true)
		local bw = side and (pw - tx - 16) or (pw - 32)
		place(btn.Instance, side and tx or 16, ph - buttonH - 14, bw, buttonH)
	end
	local sh: any = { Root = rootF, Card = card, Spec = spec }
	shade.Activated:Connect(function()
		closeSheet("outside")
	end)
	if Kit.Overlay and Kit.Overlay.Push then
		sh.Entry = Kit.Overlay.Push({ Kind = "UySheet", Owner = win, Dismiss = function()
			if st.Sheet == sh then
				closeSheet("escape")
			end
		end })
	end
	if step and not reduced() then
		sh.Conn = RunService.RenderStepped:Connect(function(dt)
			if not card.Parent then
				return
			end
			local ok = pcall(step, dt)
			if not ok and sh.Conn then
				sh.Conn:Disconnect()
				sh.Conn = nil
			end
		end)
	end
	if not reduced() then
		local scale = Kit.New("UIScale", { Name = "Pop", Scale = 0.92 }, card)
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if phone then
			card.Position = UDim2.fromOffset(x0, H0)
			TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(x0, y0) }):Play()
		end
	end
	st.Sheet = sh
	audio("UiTab")
	return sh
end
S.OpenSheet = openSheet

------------------------------------------------------------------------------------------------------------------------
-- Pages: pages[id](page) -> P {Layout(L), Refresh(), Tick()?, Shown()?, Ready?}
------------------------------------------------------------------------------------------------------------------------
local pages: { [string]: any } = {}

---------------------------------------------------------------------------- SEALS
local ACTION_TEXT = {
	Locked = "FINISH CHAPTER I", Previous = "BREAK THE SEAL BEFORE", InTrial = "IN A TRIAL", Descend = "DESCEND", Offer = "OFFER",
	WayOffer = "SHOW THE WAY", Begin = "BEGIN TRIAL", Again = "PLAY AGAIN", WayTrial = "SHOW THE WAY", Doors = "TO THE DOORS",
}
local STATE_TEXT = { Waiting = "SEALED", Previous = "SEALED", Offer = "OFFERING", Trial = "READY", Cleared = "CLEARED", Gold = "GOLD" }

pages.seals = function(page: Frame)
	local P: any = { Cards = {}, Links = {}, Wide = false }
	local scroll = scrollPage(page)
	P.Scroll = scroll

	-- header: progress of the seven seals, the next opening, today's shard efficiency, the guide's step
	local head = panel(scroll, "Header", C(70, 46, 128), C(22, 14, 50))
	local headIcon, headArt = icon(head, "Icon", "Seal", { Size = 56, Glow = MOON })
	local headTitle = sectionTitle(head, T("BELL SEALS"), MOON_HI)
	local headCount = txt(head, { Name = "Count", Text = "", TextSize = 24, Scaled = true, MinTextSize = 10, AlignX = "Right", Color = SICKLY, Font = "numeric",
		Stroke = 0.3 })
	local segHolder = Kit.New("Frame", { Name = "Segments", BackgroundTransparency = 1, ZIndex = Z + 1 }, head)
	local segs = {}
	for i = 1, #(Cfg.Seals or {}) do
		local s = Kit.New("Frame", { Name = "Seg" .. i, BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = Z + 1 }, segHolder)
		Kit.Corner(s, 6)
		Kit.Stroke(s, INK, 1.5, 0.2)
		local n = txt(s, { Name = "Numeral", Text = Cfg.Seals[i].Numeral, TextSize = 13, Scaled = true, MinTextSize = 7, AlignX = "Center", ZIndex = Z + 2,
			Stroke = 0.4 })
		segs[i] = { Frame = s, Numeral = n }
	end
	local phaseLine = txt(head, { Name = "Phase", Text = "", TextSize = 15, Wrap = true, Color = SOFT, AlignY = "Top" })
	local rateLine = txt(head, { Name = "Rate", Text = "", TextSize = 14, Wrap = true, Color = MUTED, AlignY = "Top" })
	local guideLine = txt(head, { Name = "Guide", Text = "", TextSize = 14, Wrap = true, Color = CANDLE, AlignY = "Top" })
	local _ = headArt

	-- not eligible: the Chapter I checklist
	local lock = panel(scroll, "Locked", C(84, 44, 64), C(28, 14, 32))
	local lockIcon = icon(lock, "Icon", "Lock", { Size = 44 })
	local lockTitle = sectionTitle(lock, T("CHAPTER II IS SEALED"), CANDLE)
	local lockBody = txt(lock, { Name = "Body", Text = T("Finish Chapter I in the Dead Yard to break the seals below the church."), TextSize = 14, Wrap = true,
		Color = SOFT, AlignY = "Top" })
	local lockRows = {}
	for i, row in ipairs((Cfg.Chapter1 and Cfg.Chapter1.Checklist) or {}) do
		local r = Kit.New("Frame", { Name = "Check" .. i, BorderSizePixel = 0, BackgroundColor3 = C(20, 12, 34), BackgroundTransparency = 0.35, ZIndex = Z + 1 }, lock)
		Kit.Corner(r, 10)
		local mark, markArt = icon(r, "Mark", "Lock", { Size = 22 }, Z + 2)
		local text = txt(r, { Name = "Text", Text = L(row.Text), TextSize = 14, Wrap = true, Color = SOFT, ZIndex = Z + 2 })
		local value = txt(r, { Name = "Value", Text = "", TextSize = 14, Scaled = true, MinTextSize = 8, AlignX = "Right", Color = GOLD, Font = "numeric",
			ZIndex = Z + 2 })
		lockRows[i] = { Frame = r, Mark = mark, Art = markArt, Text = text, Value = value, Key = row.Key }
	end

	-- the seven seal cards and the chain links between their medals
	for i, def in ipairs(Cfg.Seals or {}) do
		local c: any = { Index = i, Def = def }
		c.Frame = panel(scroll, "Seal_" .. i)
		c.Frame.ClipsDescendants = true
		c.Flash = Kit.New("Frame", { Name = "Flash", BorderSizePixel = 0, BackgroundColor3 = MOON, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			ZIndex = Z + 6 }, c.Frame)
		Kit.Corner(c.Flash, 14)
		c.Medal, c.MedalArt = icon(c.Frame, "Medal", "Seal", { Size = 60, Glow = MOON })
		c.Numeral = txt(c.Medal, { Name = "Numeral", Text = def.Numeral, TextSize = 20, Scaled = true, MinTextSize = 9, AlignX = "Center", ZIndex = Z + 8,
			Stroke = 0.1, Position = UDim2.fromScale(0.2, 0.62), Size = UDim2.fromScale(0.6, 0.34) })
		local districtName = def.District == "*" and T("ALL DISTRICTS") or L(Layout and Layout.Names and Layout.Names[def.District] or def.District)
		c.Kicker = txt(c.Frame, { Name = "Kicker", Text = F("BELL SEAL %s", def.Numeral) .. " · " .. upper(districtName), TextSize = 13, Scaled = true,
			MinTextSize = 8, Color = MOON })
		c.Title = txt(c.Frame, { Name = "Title", Text = upper(L(def.Name)) .. " · " .. upper(L(def.Title)), TextSize = 20, Scaled = true, MinTextSize = 10,
			Stroke = 0.35 })
		c.State = pill(c.Frame, "State", "", STATE_COLOR.Waiting)
		c.Story = txt(c.Frame, { Name = "Story", Text = L(def.Text), TextSize = 14, Wrap = true, AlignY = "Top", Color = SOFT })
		c.RewardsLabel = txt(c.Frame, { Name = "RewardsLabel", Text = "", TextSize = 12, Scaled = true, MinTextSize = 8, Color = MUTED })
		c.Chips = Kit.New("Frame", { Name = "Rewards", BackgroundTransparency = 1, ZIndex = Z + 1 }, c.Frame)
		c.GoldIcon = icon(c.Frame, "GoldIcon", "Star", { Size = 18, Color = GOLD })
		c.Gold = txt(c.Frame, { Name = "Gold", Text = "", TextSize = 13, Scaled = true, MinTextSize = 8, Color = GOLD })
		c.CostIcon = icon(c.Frame, "CostIcon", "Shard", { Size = 24 })
		c.Cost = txt(c.Frame, { Name = "Cost", Text = "", TextSize = 18, Scaled = true, MinTextSize = 9, Color = WHITE, Font = "numeric", Stroke = 0.3, Rich = true })
		c.Discount = pill(c.Frame, "Discount", T("THE BELL REMEMBERS · -40%"), C(40, 120, 70))
		c.Button = button(c.Frame, { Name = "Action", Text = "", Style = "primary", Color = VIOLET, TextSize = 17, OnClick = function()
			P.Act(i)
		end })
		c.Hint = txt(c.Frame, { Name = "Hint", Text = "", TextSize = 12, Wrap = true, AlignX = "Center", AlignY = "Top", Color = MUTED })
		P.Cards[i] = c
		if i > 1 then
			local link = Kit.New("Frame", { Name = "Link" .. i, BorderSizePixel = 0, BackgroundColor3 = PANEL_EDGE, ZIndex = Z - 1 }, scroll)
			Kit.Corner(link, 3)
			P.Links[i] = link
		end
	end

	-- the seal's current state for this player (UnderyardView.SealState)
	function P.StateOf(i: number): any
		return UV.SealState(view(), i, now(), ctx())
	end

	function P.Act(i: number)
		local s = P.StateOf(i)
		local c = P.Cards[i]
		local def = Cfg.Seals[i]
		local a = s.Action
		if a == "Descend" then
			descend()
		elseif a == "Offer" then
			act(c.Button, tostring(i), "C2SealOffer", { Seal = i }, function()
				audio("SealIgnite")
				P.FlashCard(i, CANDLE)
			end)
		elseif a == "WayOffer" then
			showWay("SealAltar_" .. i, F("ALTAR %s", def.Numeral))
		elseif a == "Begin" or a == "Again" then
			act(c.Button, tostring(i), "C2TrialStart", { Seal = i }, function()
				if win and win.IsOpen then
					win:Close("trial") -- the trial HUD and its countdown take the screen
				end
			end, "")
		elseif a == "WayTrial" then
			showWay(s.Anchor, upper(L(def.Title)))
		elseif a == "Doors" then
			showWay("DoorCourt", upper(L(def.Title)))
		end
	end

	function P.FlashCard(i: number, color: Color3?)
		local c = P.Cards[i]
		if not c then
			return
		end
		c.Flash.BackgroundColor3 = color or MOON
		c.Flash.BackgroundTransparency = 0.55
		TweenService:Create(c.Flash, TweenInfo.new(reduced() and 0.2 or 0.9, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		local stroke = c.Frame:FindFirstChildWhichIsA("UIStroke")
		if stroke and not reduced() then
			stroke.Thickness = 5
			TweenService:Create(stroke, TweenInfo.new(0.9), { Thickness = 2 }):Play()
		end
	end

	-- scroll a seal card into view (the altar prompt opens the window on its seal)
	function P.Focus(i: number)
		local c = P.Cards[i]
		if not c then
			return
		end
		local y = c.Frame.Position.Y.Offset
		local maxY = math.max(0, scroll.CanvasSize.Y.Offset - scroll.AbsoluteSize.Y)
		scroll.CanvasPosition = Vector2.new(0, math.clamp(y - 8, 0, maxY))
		P.FlashCard(i)
	end

	-- one seal card at width w -> height
	local function layoutCard(c: any, w: number, wide: boolean): number
		local i = c.Index
		local storyH
		local y
		if wide then
			local medal = 64
			local aw = math.min(220, math.floor(w * 0.3))
			local ax = w - aw - 16
			local tx = 16 + medal + 14
			local tw = ax - tx - 14
			place(c.Medal, 16, 16, medal, medal)
			place(c.Kicker, tx, 14, tw, 18)
			place(c.Title, tx, 32, tw, 26)
			c.State.Instance.Position = UDim2.fromOffset(tx, 62)
			storyH = textH(c.Story.Text, 14, tw)
			place(c.Story, tx, 92, tw, storyH)
			y = 92 + storyH + 8
			place(c.RewardsLabel, tx, y, tw, 16)
			y += 18
			local chH = chipRow(c.Chips, c.Rows or {}, tw, 24)
			place(c.Chips, tx, y, tw, chH)
			y += chH + 6
			place(c.GoldIcon, tx, y, 18, 18)
			place(c.Gold, tx + 24, y, tw - 24, 18)
			y += 26
			-- the action column
			place(c.CostIcon, ax, 18, 26, 26)
			place(c.Cost, ax + 32, 18, aw - 32, 26)
			c.Discount.Instance.Position = UDim2.fromOffset(ax, 50)
			local by = c.Discount.Instance.Visible and 82 or 54
			if not c.Cost.Visible then
				by = 22
			end
			place(c.Button.Instance, ax, by, aw, 46)
			local hintH = textH(c.Hint.Text, 12, aw)
			place(c.Hint, ax, by + 52, aw, hintH)
			return math.max(y + 4, by + 52 + hintH + 14, 104)
		end
		local medal = 52
		local tx = 12 + medal + 12
		local tw = w - tx - 12
		place(c.Medal, 12, 12, medal, medal)
		place(c.Kicker, tx, 12, tw, 16)
		place(c.Title, tx, 28, tw, 24)
		c.State.Instance.Position = UDim2.fromOffset(tx, 56)
		storyH = textH(c.Story.Text, 14, w - 24)
		place(c.Story, 12, 86, w - 24, storyH)
		y = 86 + storyH + 8
		place(c.RewardsLabel, 12, y, w - 24, 16)
		y += 18
		local chH = chipRow(c.Chips, c.Rows or {}, w - 24, 24)
		place(c.Chips, 12, y, w - 24, chH)
		y += chH + 6
		place(c.GoldIcon, 12, y, 18, 18)
		place(c.Gold, 36, y, w - 48, 18)
		y += 26
		if c.Cost.Visible then
			place(c.CostIcon, 12, y, 24, 24)
			place(c.Cost, 42, y, math.min(160, w - 54), 24)
			if c.Discount.Instance.Visible then
				c.Discount.Instance.Position = UDim2.fromOffset(math.min(w - 12 - math.ceil(textW(c.Discount.Label.Text, 13)) - 18, 42 + 132), y)
				if c.Discount.Instance.Position.X.Offset < 42 + 96 then
					c.Discount.Instance.Position = UDim2.fromOffset(12, y + 28)
					y += 28
				end
			end
			y += 30
		end
		place(c.Button.Instance, 12, y, w - 24, 46)
		y += 52
		local hintH = textH(c.Hint.Text, 12, w - 24)
		place(c.Hint, 12, y, w - 24, hintH)
		local _ = i
		return y + hintH + 12
	end

	function P.Layout(Lw)
		local w = (Lw.Width or 600) - 12
		if w < 60 then
			return
		end
		P.LastL = Lw
		local wide = w >= 620
		P.Wide = wide
		local y = 2
		-- header
		local iconS = Lw.Phone and 44 or 56
		place(headIcon, 14, 12, iconS, iconS)
		local tx = 14 + iconS + 12
		local countW = Lw.Phone and 70 or 96
		place(headTitle, tx, 12, w - tx - countW - 20, 26)
		place(headCount, w - countW - 14, 12, countW, 28)
		local segW = w - tx - 16
		local n = #segs
		local gap = 6
		local sw = math.floor((segW - gap * (n - 1)) / math.max(1, n))
		place(segHolder, tx, 44, segW, 20)
		for i, s in ipairs(segs) do
			place(s.Frame, (i - 1) * (sw + gap), 0, sw, 20)
		end
		local lineY = math.max(70, 12 + iconS + 6)
		local phaseH = math.max(18, textH(phaseLine.Text, 15, w - 32))
		local rateH = math.max(16, textH(rateLine.Text, 14, w - 32))
		P.LineH = phaseH .. ":" .. rateH
		place(phaseLine, 16, lineY, w - 32, phaseH)
		place(rateLine, 16, lineY + phaseH + 2, w - 32, rateH)
		local guideY = lineY + phaseH + rateH + 4
		local guideH = guideLine.Text ~= "" and textH(guideLine.Text, 14, w - 32) or 0
		guideLine.Visible = guideH > 0
		place(guideLine, 16, guideY, w - 32, guideH)
		local headH = guideY + (guideH > 0 and guideH + 6 or 0) + 4
		place(head, 2, y, w, headH)
		y += headH + 10
		-- the lock card
		if lock.Visible then
			place(lockIcon, 14, 14, 40, 40)
			place(lockTitle, 64, 14, w - 80, 26)
			local bh = textH(lockBody.Text, 14, w - 80)
			place(lockBody, 64, 42, w - 80, bh)
			local ry = 42 + bh + 10
			for _, r in ipairs(lockRows) do
				local vw = Lw.Phone and 62 or 76
				local textW0 = w - 24 - 38 - vw - 12
				local rh = math.max(32, textH(r.Text.Text, 14, textW0) + 10)
				place(r.Frame, 12, ry, w - 24, rh)
				place(r.Mark, 8, math.floor((rh - 22) / 2), 22, 22)
				place(r.Text, 38, 5, textW0, rh - 10)
				place(r.Value, w - 24 - vw - 8, math.floor((rh - 24) / 2), vw, 24)
				ry += rh + 6
			end
			place(lock, 2, y, w, ry + 6)
			y += ry + 16
		end
		-- the cards
		for i, c in ipairs(P.Cards) do
			local h = layoutCard(c, w, wide)
			place(c.Frame, 2, y, w, h)
			c.Top = y
			if P.Links[i] then
				local prev = P.Cards[i - 1]
				local mx = 2 + (wide and 16 + 32 or 12 + 26) - 3
				local top = prev.Top + (prev.Frame.Size.Y.Offset or 0)
				place(P.Links[i], mx, top - 2, 6, y - top + 4)
			end
			y += h + 12
		end
		scroll.CanvasSize = UDim2.fromOffset(0, y + 4)
	end

	local function refreshCard(c: any, s: any)
		local i = c.Index
		local def = c.Def
		local color = STATE_COLOR[s.State] or MOON
		c.Last = s.State .. "|" .. s.Action
		c.State:Set(T(STATE_TEXT[s.State] or "SEALED"), color:Lerp(INK, 0.35), WHITE)
		if s.State == "Waiting" then
			c.State:Set(F("OPENS IN %s", clock(s.OpensIn)), color:Lerp(INK, 0.35), WHITE)
		end
		if c.MedalArt and c.MedalArt.Set then
			local dim = (s.State == "Waiting" or s.State == "Previous") and 0.5 or nil
			c.MedalArt:Set("Seal", { Size = 60, Color = s.State == "Gold" and C(200, 150, 40) or s.Cleared and C(60, 150, 90) or VIOLET, Glow = color, Dim = dim })
		end
		c.Numeral.TextColor3 = (s.State == "Waiting" or s.State == "Previous") and MUTED or WHITE
		local stroke = c.Frame:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = (s.State == "Trial" or s.State == "Offer") and color or s.Cleared and color:Lerp(PANEL_EDGE, 0.5) or PANEL_EDGE
		end
		-- rewards: first clear until cleared, then the repeat reward
		if s.Cleared then
			c.RewardsLabel.Text = T("REPEAT CLEAR")
			c.Rows = { { Kind = "Shards", Amount = def.Rewards.Repeat } }
		else
			c.RewardsLabel.Text = T("FIRST CLEAR")
			c.Rows = UV.FirstRewards(i)
		end
		local goldText = UV.GoldText(i, lang())
		c.Gold.Text = (s.Gold and ("✓ " .. T("GOLD") .. " · ") or (T("GOLD") .. ": ")) .. goldText .. (s.Gold and "" or (" · " .. F("+%d COFFIN KEYS", def.GoldRewards.Keys or 1)))
		c.Gold.TextColor3 = s.Gold and GOLD or C(220, 190, 120)
		-- offering cost (until offered)
		local showCost = s.State == "Offer" or s.State == "Waiting" or s.State == "Previous"
		c.Cost.Visible = showCost
		c.CostIcon.Visible = showCost
		if s.Covered then
			c.Cost.Text = T("FREE") .. "  <s>" .. num(s.Cost) .. "</s>"
		elseif s.Discount then
			c.Cost.Text = num(s.Cost) .. "  <s>" .. num(s.Full) .. "</s>"
		else
			c.Cost.Text = num(s.Cost)
		end
		c.Discount.Instance.Visible = showCost and s.Discount and not s.Covered
		-- the action
		local a = s.Action
		local text = T(ACTION_TEXT[a] or "")
		local style, disabled = "primary", false
		local hint = ""
		if a == "Opens" then
			text, disabled = F("OPENS IN %s", clock(s.OpensIn)), true
			hint = T("New seals open by date. Older trials, contracts and coffins are always open.")
		elseif a == "Previous" then
			text, disabled = F("BREAK SEAL %s FIRST", UV.Numeral(i - 1)), true
		elseif a == "Locked" or a == "InTrial" then
			disabled = true
		elseif a == "Need" then
			text, disabled = F("NEED %s MORE", num(s.Missing)), true
			hint = T("Earn Bell Shards: contracts, echoes, trials, the Gravekeeper and the Toll Box.")
		elseif a == "Offer" then
			style = "gold"
			hint = s.Covered and T("Your guide pays this first offering.") or F("Offer %d Bell Shards at Altar %s", s.Cost, def.Numeral)
		elseif a == "WayOffer" then
			hint = s.Covered and T("Your guide pays this first offering.") or F("Offer %d Bell Shards at Altar %s", s.Cost, def.Numeral)
		elseif a == "Begin" or a == "Again" then
			style = "success"
			hint = def.Trial and def.Trial.TimeLimit and def.Trial.TimeLimit > 0 and F("Time limit %s · party up to %d", clock(def.Trial.TimeLimit),
				(Cfg.Trials and Cfg.Trials.MaxParty) or 6) or ""
		elseif a == "WayTrial" then
			local anchor = UV.StartAnchor(i)
			local district = Layout and Layout.Names and Layout.Names[def.District]
			local where = (string.find(anchor, "^SealAltar_") or not district) and (F("ALTAR %s", def.Numeral) .. " · " .. T("BELL SQUARE"))
				or upper(L(district))
			hint = F("The trial starts at %s", where)
		elseif a == "Doors" then
			local d = view().Daily or {}
			hint = F("Doors today: %d / %d", tonumber(d.Doors) or 0, tonumber(d.DoorsMax) or (Cfg.Doors and Cfg.Doors.PerDay) or 3)
		elseif a == "Descend" then
			hint = T("The altars stand in Bell Square, below the church.")
		end
		c.Button:SetText(text)
		c.Button:SetStyle(style, style == "primary" and VIOLET or nil)
		c.Button:SetDisabled(disabled)
		c.Hint.Text = hint
	end

	function P.Refresh()
		local v = view()
		local okE = eligible()
		lock.Visible = not okE
		local c1 = v.Chapter1 or {}
		local values = {}
		for _, row in ipairs(c1.Checklist or {}) do
			values[row.Key] = row
		end
		for _, r in ipairs(lockRows) do
			local row = values[r.Key] or {}
			local done = row.Done == true
			r.Value.Text = F("%d / %d", math.min(tonumber(row.Value) or 0, tonumber(row.Goal) or 0), tonumber(row.Goal) or 0)
			r.Value.TextColor3 = done and SICKLY or GOLD
			if r.Art and r.Art.Set then
				r.Art:Set(done and "Check" or "Lock", { Size = 22, Color = done and SICKLY or nil })
			end
			r.Text.TextColor3 = done and SICKLY or SOFT
		end
		local cleared = 0
		local changed = false
		for i, c in ipairs(P.Cards) do
			local s = P.StateOf(i)
			if s.Cleared then
				cleared += 1
			end
			local before = c.Hint.Text
			refreshCard(c, s)
			if before ~= c.Hint.Text then
				changed = true
			end
			local seg = segs[i]
			if seg then
				local col = STATE_COLOR[s.State] or MOON
				gradient(seg.Frame, col:Lerp(WHITE, 0.2), col:Lerp(INK, 0.45))
				seg.Numeral.TextColor3 = (s.State == "Waiting" or s.State == "Previous") and MUTED or WHITE
			end
			if P.Links[i] then
				P.Links[i].BackgroundColor3 = P.Cards[i - 1] and P.StateOf(i - 1).Cleared and SICKLY:Lerp(PANEL_EDGE, 0.4) or PANEL_EDGE:Lerp(INK, 0.4)
			end
		end
		headCount.Text = F("%d / %d", cleared, #P.Cards)
		local o = UV.Objective(v, now(), ctx())
		local guide = ""
		if o.Kind == "Tutorial" then
			local title, line = UV.ObjectiveText(o, lang(), now())
			guide = title .. " · " .. line
		end
		if guideLine.Text ~= guide then
			guideLine.Text = guide
			changed = true
		end
		P.Ready = UV.Badges(v, hview(), now(), ctx()).seals
		P.Tick()
		if changed and P.LastL then
			P.Layout(P.LastL)
		end
	end

	function P.Tick()
		local t = now()
		local folder = Halloween and Halloween:FindFirstChild("State")
		local c2 = folder and folder:FindFirstChild("Chapter2")
		local nextAt = tonumber(c2 and c2:GetAttribute("NextPhaseAt")) or tonumber(view().NextPhaseAt) or 0
		if nextAt <= 0 and Rules then
			nextAt = Rules.NextPhaseAt(t, Cfg)
		end
		if nextAt > t then
			local phase = Rules and Rules.Phase(t, Cfg) or 0
			local nextSeal = Cfg.Seals[phase + 1]
			phaseLine.Text = F("BELL SEAL %s opens in %s", nextSeal and nextSeal.Numeral or "?", clock(nextAt - t))
		else
			phaseLine.Text = T("Every seal is open. The Last Bell waits.")
		end
		local d = view().Daily or {}
		local rate = math.floor((tonumber(d.Rate) or 1) * 100 + 0.5)
		local left = tonumber(d.TierLeft) or -1
		local rested = view().Rested and tonumber(view().Rested.Pool) or 0
		local line = F("Bell Shards today: %d%% efficiency", rate)
		if left > 0 then
			line ..= " · " .. F("%d more at this rate", math.floor(left))
		end
		if rested > 0 then
			line ..= " · " .. F("rested %d", rested)
		end
		rateLine.Text = line
		rateLine.TextColor3 = rate >= 100 and MUTED or CANDLE
		-- a line that wraps differently now (a longer countdown, another language) moves the cards below
		local Lw = P.LastL
		if Lw then
			local w = (Lw.Width or 600) - 12
			local key = math.max(18, textH(phaseLine.Text, 15, w - 32)) .. ":" .. math.max(16, textH(line, 14, w - 32))
			if key ~= P.LineH then
				P.Layout(Lw)
			end
		end
		-- countdowns + proximity: re-evaluate every card (cheap) and redraw the ones that changed
		for i, c in ipairs(P.Cards) do
			local s = P.StateOf(i)
			if c.Last ~= s.State .. "|" .. s.Action or s.State == "Waiting" or s.Action == "Opens" then
				refreshCard(c, s)
			end
		end
	end
	return P
end

---------------------------------------------------------------------------- CONTRACTS
local CONTRACT_ICON = { Perfect = { "Star", MOON }, Trial = { "Seal", MOON }, Echo = { "Bell", SICKLY }, Shards = { "Shard" }, BossDamage = { "Skull", BLOOD },
	Coffin = { "Coffin" }, Resonance = { "Bell", VIOLET_HI }, Ore = { "Pickaxe", SICKLY }, Revive = { "Ghost", MOON }, Door = { "Door", CANDLE },
	Spirit = { "Ghost", VIOLET_HI } }

pages.contracts = function(page: Frame)
	local P: any = {}
	local scroll = scrollPage(page)
	local head = panel(scroll, "Header", C(70, 46, 128), C(22, 14, 50))
	local headIcon = icon(head, "Icon", "Scroll", { Size = 48, Glow = VIOLET })
	local headTitle = sectionTitle(head, T("DAILY CONTRACTS"), MOON_HI)
	local headReset = txt(head, { Name = "Reset", Text = "", TextSize = 15, Scaled = true, MinTextSize = 9, Color = MUTED })
	local headInfo = txt(head, { Name = "Info", Text = F("Every contract pays %d Bell Shards at full value, even on a busy day.",
		(Cfg.Contracts and Cfg.Contracts.Reward and Cfg.Contracts.Reward.Shards) or 60), TextSize = 13, Wrap = true, AlignY = "Top", Color = SOFT })
	local rows = {}
	for i = 1, ((Cfg.Contracts and Cfg.Contracts.PerDay) or 3) + 3 do
		local card = panel(scroll, "Contract" .. i)
		card.Visible = false
		local badgeF = Kit.New("Frame", { Name = "Badge", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = Z + 1 }, card)
		Kit.Corner(badgeF, 12)
		Kit.Stroke(badgeF, INK, 2, 0.2)
		local art, artH = icon(badgeF, "Art", "Scroll", { Size = 44 }, Z + 2)
		local title = txt(card, { Name = "Title", Text = "", TextSize = 17, Scaled = true, MinTextSize = 9, Stroke = 0.45 })
		local progress = bar(card, "Progress", SICKLY, 18)
		local chips = Kit.New("Frame", { Name = "Rewards", BackgroundTransparency = 1, ZIndex = Z + 1 }, card)
		local claim
		claim = button(card, { Name = "Claim", Text = T("CLAIM"), Style = "success", TextSize = 17, OnClick = function()
			local row = rows[i].Row
			if not row then
				return
			end
			act(claim, row.Id, "C2ContractClaim", { Id = row.Id }, function()
				audio("Claim")
			end)
		end })
		rows[i] = { Frame = card, Badge = badgeF, Art = art, ArtH = artH, Title = title, Bar = progress, Chips = chips, Claim = claim }
	end
	-- the all-three bonus
	local bonus = panel(scroll, "Bonus", C(96, 60, 30), C(40, 20, 34))
	local bonusIcon = icon(bonus, "Icon", "Key", { Size = 48 })
	local bonusTitle = sectionTitle(bonus, T("CONTRACT BONUS"), CANDLE)
	local bonusInfo = txt(bonus, { Name = "Info", Text = T("Claim all three contracts of the day: 1 Coffin Key and one more Crooked Door opening today."),
		TextSize = 13, Wrap = true, AlignY = "Top", Color = SOFT })
	local bonusBtn
	bonusBtn = button(bonus, { Name = "Claim", Text = T("CLAIM"), Style = "success", TextSize = 17, OnClick = function()
		act(bonusBtn, "bonus", "C2ContractBonus", {}, function(res)
			reveal(T("CONTRACT BONUS"), res and res.Rewards, T("ALL CONTRACTS DONE"))
		end, "")
	end })
	-- the Toll Box
	local toll = panel(scroll, "TollBox", C(60, 40, 104), C(24, 16, 46))
	local tollIcon = icon(toll, "Icon", "Candy", { Size = 48 })
	local tollTitle = sectionTitle(toll, T("THE TOLL BOX"), CANDLE)
	local tollInfo = txt(toll, { Name = "Info", Text = F("%d Moon Candy buys 1 Bell Shard. Up to %d shards a day, never less after a busy day.",
		(Cfg.Exchange and Cfg.Exchange.CandyPerShard) or 25, (Cfg.Exchange and Cfg.Exchange.MaxPerDay) or 40), TextSize = 13, Wrap = true, AlignY = "Top",
		Color = SOFT })
	local tollBar = bar(toll, "Today", CANDLE, 16)
	local minus = button(toll, { Name = "Minus", Text = "-", Style = "secondary", TextSize = 20, OnClick = function()
		st.Amount = math.max(1, (st.Amount or 10) - 5)
		P.Refresh()
	end })
	local plus = button(toll, { Name = "Plus", Text = "+", Style = "secondary", TextSize = 20, OnClick = function()
		st.Amount = math.min((Cfg.Exchange and Cfg.Exchange.MaxPerRequest) or 40, (st.Amount or 10) + 5)
		P.Refresh()
	end })
	local maxBtn = button(toll, { Name = "Max", Text = T("MAX"), Style = "secondary", TextSize = 15, OnClick = function()
		P.MaxAmount()
		P.Refresh()
	end })
	local amount = txt(toll, { Name = "Amount", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Center", Font = "numeric", Stroke = 0.3,
		Color = WHITE })
	local price = txt(toll, { Name = "Price", Text = "", TextSize = 15, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = CANDLE })
	local buy
	buy = button(toll, { Name = "Buy", Text = T("BUY"), Style = "gold", TextSize = 18, OnClick = function()
		if not eligible() then
			return
		end
		if not inZone() then
			descend()
			return
		end
		if not nearAnchor("TollBox") then
			showWay("TollBox", T("THE TOLL BOX"))
			return
		end
		local n = P.Clamp(st.Amount or 10)
		if n <= 0 then
			return
		end
		act(buy, "toll", "C2Exchange", { Shards = n }, function()
			audio("CandyBig")
		end)
	end })
	-- today's efficiency
	local today = panel(scroll, "Today", C(44, 34, 84), C(20, 14, 42))
	local todayIcon = icon(today, "Icon", "Shard", { Size = 48 })
	local todayTitle = sectionTitle(today, T("BELL SHARDS TODAY"), MOON_HI)
	local todayRate = txt(today, { Name = "Rate", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Right", Font = "numeric", Stroke = 0.3,
		Color = SICKLY })
	local todayBar = bar(today, "Tier", MOON, 16)
	local todayInfo = txt(today, { Name = "Info", Text = "", TextSize = 13, Wrap = true, AlignY = "Top", Color = SOFT })

	function P.Clamp(n: number): number
		local d = view().Daily or {}
		local left = math.max(0, (tonumber(d.ExchangeMax) or (Cfg.Exchange and Cfg.Exchange.MaxPerDay) or 40) - (tonumber(d.Exchange) or 0))
		local per = (Cfg.Exchange and Cfg.Exchange.CandyPerShard) or 25
		local affordable = math.floor(candy() / per)
		return math.max(0, math.min(n, left, affordable, (Cfg.Exchange and Cfg.Exchange.MaxPerRequest) or 40))
	end
	function P.MaxAmount()
		st.Amount = math.max(1, P.Clamp((Cfg.Exchange and Cfg.Exchange.MaxPerRequest) or 40))
	end

	local lastW, lastPhone = 600, false
	function P.Layout(Lw)
		local w = (Lw.Width or 600) - 12
		if w < 60 then
			return
		end
		lastW, lastPhone = w, Lw.Phone == true
		local narrow = w < 560
		local y = 2
		place(headIcon, 14, 12, 44, 44)
		place(headTitle, 68, 12, w - 84, 26)
		place(headReset, 68, 40, w - 84, 20)
		local ih = textH(headInfo.Text, 13, w - 32)
		place(headInfo, 16, 68, w - 32, ih)
		local headH = 68 + ih + 12
		place(head, 2, y, w, headH)
		y += headH + 10
		for _, r in ipairs(rows) do
			if r.Frame.Visible then
				local rowH = narrow and 126 or 88
				local iconS = narrow and 48 or 60
				place(r.Frame, 2, y, w, rowH)
				place(r.Badge, 12, narrow and 12 or (rowH - iconS) / 2, iconS, iconS)
				place(r.Art, 4, 4, iconS - 8, iconS - 8)
				local tx = 12 + iconS + 12
				local claimW = narrow and 120 or 140
				local mid = w - tx - claimW - 24
				place(r.Title, tx, 12, narrow and w - tx - 12 or mid, 24)
				place(r.Bar.Instance, tx, narrow and 44 or 46, narrow and w - tx - 12 or mid * 0.62, 18)
				local chipX = narrow and tx or tx + mid * 0.62 + 12
				local chipW = narrow and (w - tx - claimW - 24) or mid * 0.38 - 12
				r.ChipW = chipW
				place(r.Chips, chipX, narrow and 80 or 44, chipW, 26)
				place(r.Claim.Instance, w - claimW - 12, narrow and 74 or (rowH - 44) / 2, claimW, 44)
				y += rowH + 10
			end
		end
		-- bonus
		local bw = w
		local infoW = narrow and bw - 32 or bw - 64 - 170
		local bih = textH(bonusInfo.Text, 13, infoW)
		place(bonusIcon, 12, 14, 48, 48)
		place(bonusTitle, 70, 12, bw - 86 - (narrow and 0 or 160), 26)
		place(bonusInfo, narrow and 16 or 70, narrow and 66 or 42, infoW, bih)
		local bonusH = narrow and (66 + bih + 60) or math.max(84, 42 + bih + 14)
		place(bonusBtn.Instance, narrow and 16 or bw - 160, narrow and bonusH - 54 or (bonusH - 46) / 2, narrow and bw - 32 or 144, 44)
		place(bonus, 2, y, bw, bonusH)
		y += bonusH + 10
		-- toll box
		local tih = textH(tollInfo.Text, 13, w - 92)
		place(tollIcon, 12, 14, 48, 48)
		place(tollTitle, 70, 12, w - 86, 26)
		place(tollInfo, 70, 42, w - 86, tih)
		local ty = 42 + tih + 10
		place(tollBar.Instance, 16, ty, w - 32, 16)
		ty += 26
		if narrow then
			place(minus.Instance, 16, ty, 52, 44)
			place(amount, 72, ty, w - 32 - 52 * 2 - 8 - 70, 26)
			place(price, 72, ty + 26, w - 32 - 52 * 2 - 8 - 70, 18)
			place(plus.Instance, w - 16 - 52 - 74, ty, 52, 44)
			place(maxBtn.Instance, w - 16 - 70, ty, 70, 44)
			ty += 52
			place(buy.Instance, 16, ty, w - 32, 46)
			ty += 56
		else
			place(minus.Instance, 16, ty, 52, 44)
			place(amount, 72, ty, 150, 26)
			place(price, 72, ty + 26, 150, 18)
			place(plus.Instance, 226, ty, 52, 44)
			place(maxBtn.Instance, 284, ty, 76, 44)
			place(buy.Instance, w - 16 - math.min(220, w - 392), ty, math.min(220, w - 392), 46)
			ty += 58
		end
		place(toll, 2, y, w, ty)
		y += ty + 10
		-- today
		place(todayIcon, 12, 14, 48, 48)
		local rw = narrow and 80 or 110
		place(todayTitle, 70, 12, w - 86 - rw, 26)
		place(todayRate, w - rw - 14, 12, rw, 30)
		place(todayBar.Instance, 70, 46, w - 86, 16)
		local dih = textH(todayInfo.Text ~= "" and todayInfo.Text or "x", 13, w - 32)
		place(todayInfo, 16, 72, w - 32, dih)
		local todayH = 72 + dih + 12
		place(today, 2, y, w, todayH)
		y += todayH + 10
		scroll.CanvasSize = UDim2.fromOffset(0, y + 4)
	end

	function P.Refresh()
		local v = view()
		local list = (v.Contracts and v.Contracts.List) or {}
		local day = Rules and Rules.Day(now()) or 0
		local stale = v.Contracts and v.Contracts.Day ~= nil and tonumber(v.Contracts.Day) ~= day
		if stale then
			list = {}
		end
		local changed = false
		local ready = 0
		local allClaimed = #list > 0
		for i, r in ipairs(rows) do
			local row = list[i]
			r.Row = row
			local vis = row ~= nil
			if r.Frame.Visible ~= vis then
				r.Frame.Visible = vis
				changed = true
			end
			if row then
				local ic = CONTRACT_ICON[row.Id] or { "Scroll" }
				if r.ArtH and r.ArtH.Set then
					r.ArtH:Set(ic[1], { Size = 44, Glow = ic[2] })
				end
				local col = ic[2] or VIOLET
				gradient(r.Badge, col:Lerp(WHITE, 0.15):Lerp(INK, 0.35), col:Lerp(INK, 0.7))
				r.Title.Text = UV.ContractText(row, lang())
				local done = (tonumber(row.Progress) or 0) >= (tonumber(row.Goal) or 1)
				r.Bar:SetValue(math.clamp((tonumber(row.Progress) or 0) / math.max(1, tonumber(row.Goal) or 1), 0, 1))
				r.Bar:SetText(F("%s / %s", num(row.Progress), num(row.Goal)))
				r.Bar:SetColor(done and SICKLY or MOON)
				chipRow(r.Chips, { { Kind = "Shards", Amount = (Cfg.Contracts and Cfg.Contracts.Reward and Cfg.Contracts.Reward.Shards) or 60 } }, r.ChipW or 200, 26)
				if row.Claimed then
					r.Claim:SetText(T("CLAIMED"))
					r.Claim:SetStyle("secondary")
					r.Claim:SetDisabled(true)
				elseif done then
					ready += 1
					r.Claim:SetText(T("CLAIM"))
					r.Claim:SetStyle("success")
					r.Claim:SetDisabled(false)
				else
					r.Claim:SetText(T("IN PROGRESS"))
					r.Claim:SetStyle("secondary")
					r.Claim:SetDisabled(true)
				end
				allClaimed = allClaimed and row.Claimed == true
			end
		end
		local bonusClaimed = not stale and v.Contracts and v.Contracts.AllClaimed == true
		if bonusClaimed then
			bonusBtn:SetText("✓ " .. T("CLAIMED"))
			bonusBtn:SetStyle("secondary")
			bonusBtn:SetDisabled(true)
		else
			bonusBtn:SetText(T("CLAIM"))
			bonusBtn:SetStyle(allClaimed and "success" or "secondary")
			bonusBtn:SetDisabled(not allClaimed)
			if allClaimed then
				ready += 1
			end
		end
		-- toll box
		local d = v.Daily or {}
		local maxDay = tonumber(d.ExchangeMax) or (Cfg.Exchange and Cfg.Exchange.MaxPerDay) or 40
		local used = (tonumber(d.Day) == day) and (tonumber(d.Exchange) or 0) or 0
		tollBar:SetValue(math.clamp(used / math.max(1, maxDay), 0, 1))
		tollBar:SetText(F("Today %d / %d", used, maxDay))
		local n = P.Clamp(st.Amount or 10)
		local per = (Cfg.Exchange and Cfg.Exchange.CandyPerShard) or 25
		local shown = math.max(1, st.Amount or 10)
		amount.Text = F("+%d BELL SHARDS", n > 0 and n or shown)
		price.Text = F("%d Candy · you have %s", (n > 0 and n or shown) * per, num(candy()))
		local full = used >= maxDay
		if not eligible() then
			buy:SetText(T("FINISH CHAPTER I"))
			buy:SetStyle("secondary")
			buy:SetDisabled(true)
		elseif not inZone() then
			buy:SetText(T("DESCEND"))
			buy:SetStyle("primary", VIOLET)
			buy:SetDisabled(false)
		elseif full then
			buy:SetText(T("FULL FOR TODAY"))
			buy:SetStyle("secondary")
			buy:SetDisabled(true)
		elseif n <= 0 then
			buy:SetText(T("NOT ENOUGH CANDY"))
			buy:SetStyle("secondary")
			buy:SetDisabled(true)
		elseif not nearAnchor("TollBox") then
			buy:SetText(T("SHOW THE WAY"))
			buy:SetStyle("primary", VIOLET)
			buy:SetDisabled(false)
		else
			buy:SetText(T("BUY"))
			buy:SetStyle("gold")
			buy:SetDisabled(false)
		end
		P.Near = nearAnchor("TollBox")
		-- today
		local rate = tonumber(d.Rate) or 1
		todayRate.Text = math.floor(rate * 100 + 0.5) .. "%"
		todayRate.TextColor3 = rate >= 1 and SICKLY or rate >= 0.3 and CANDLE or BLOOD
		local raw = (tonumber(d.Day) == day) and (tonumber(d.Raw) or 0) or 0
		local tiers = (Cfg.DailyReturns and Cfg.DailyReturns.Tiers) or {}
		local first = tiers[1] and tiers[1].Upto or 500
		todayBar:SetValue(math.clamp(raw / math.max(1, (tiers[2] and tiers[2].Upto) or first * 2), 0, 1))
		todayBar:SetText(F("%d earned today", raw))
		todayBar:SetColor(rate >= 1 and SICKLY or rate >= 0.3 and CANDLE or BLOOD)
		local rested = v.Rested and tonumber(v.Rested.Pool) or 0
		local info = F("The first %d shards of a day count in full, the next %d at 35%%, the rest at 10%%. Contracts, first clears and the Toll Box are never reduced.",
			first, ((tiers[2] and tiers[2].Upto) or 1000) - first)
		if rested > 0 then
			info ..= "\n" .. F("Rested: %d shards at 100%%", rested)
		end
		local before = todayInfo.Text
		todayInfo.Text = info
		if changed or before ~= info then
			P.Layout({ Width = lastW + 12, Phone = lastPhone })
		end
		P.Ready = ready
		P.Tick()
	end

	function P.Tick()
		headReset.Text = F("NEW CONTRACTS IN %s", clock(86400 - now() % 86400))
		if P.Near ~= nearAnchor("TollBox") then
			P.Refresh()
		end
	end
	return P
end

---------------------------------------------------------------------------- COFFIN
pages.coffin = function(page: Frame)
	local P: any = { Results = {} }
	local scroll = scrollPage(page)
	local price = (Cfg.Coffin and Cfg.Coffin.Price) or { Shards = 150, Keys = 1 }
	-- hero
	local hero = panel(scroll, "Hero", C(60, 30, 100), C(10, 6, 24))
	hero.ClipsDescendants = true
	local glow = Kit.New("Frame", { Name = "Glow", BorderSizePixel = 0, BackgroundColor3 = VIOLET, BackgroundTransparency = 0.7, ZIndex = Z + 1 }, hero)
	Kit.Corner(glow, "pill")
	local coffinArt, coffinH = icon(hero, "Coffin", "Coffin", { Size = 150 }, Z + 2)
	local heroKicker = txt(hero, { Name = "Kicker", Text = T("BELL SQUARE · THE SHRINE"), TextSize = 14, Scaled = true, MinTextSize = 8, Color = MOON })
	local heroTitle = txt(hero, { Name = "Title", Text = T("THE BLACK COFFIN"), TextSize = 32, Scaled = true, MinTextSize = 14, Stroke = 0.2 })
	local heroBody = txt(hero, { Name = "Body", Text = F("Open it at the shrine for %d Bell Shards and %d Coffin Key. Every chance is shown below; duplicates are converted, never wasted.",
		price.Shards, price.Keys), TextSize = 14, Wrap = true, AlignY = "Top", Color = SOFT })
	local keyIcon = icon(hero, "KeyIcon", "Key", { Size = 28 })
	local keyText = txt(hero, { Name = "Keys", Text = "", TextSize = 18, Scaled = true, MinTextSize = 9, Font = "numeric", Stroke = 0.3 })
	local shardIcon = icon(hero, "ShardIcon", "Shard", { Size = 28 })
	local shardText = txt(hero, { Name = "Shards", Text = "", TextSize = 18, Scaled = true, MinTextSize = 9, Font = "numeric", Stroke = 0.3 })
	local opened = txt(hero, { Name = "Opened", Text = "", TextSize = 13, Scaled = true, MinTextSize = 8, Color = MUTED })
	local openBtn
	openBtn = button(hero, { Name = "Open", Text = T("OPEN"), Style = "gold", TextSize = 19, OnClick = function()
		P.Open(openBtn)
	end })
	local reason = txt(hero, { Name = "Reason", Text = "", TextSize = 13, Wrap = true, AlignX = "Center", AlignY = "Top", Color = CANDLE })
	-- where keys come from
	local keysCard = panel(scroll, "KeySources")
	local keysTitle = sectionTitle(keysCard, T("COFFIN KEYS"), MOON_HI)
	local keysBody = txt(keysCard, { Name = "Body", Text = T("Keys come from the daily contract bonus, every Bell Seal (and its Gold), the Gravekeeper III-V, Bell Resonance, Crooked Doors and the Dex II. Never sold."),
		TextSize = 13, Wrap = true, AlignY = "Top", Color = SOFT })
	-- drop rates
	local rates = panel(scroll, "DropRates")
	local ratesTitle = sectionTitle(rates, T("DROP RATES"), MOON_HI)
	local ratesNote = txt(rates, { Name = "Note", Text = T("Exact chances of one opening. Duplicates convert into fragments, Lucky Dust or shards."), TextSize = 13,
		Wrap = true, AlignY = "Top", Color = MUTED })
	local table0 = UV.DropTable()
	local rateRows = {}
	local function addRow(kind: string, data: any)
		local f = Kit.New("Frame", { Name = "Rate" .. #rateRows + 1, BorderSizePixel = 0, BackgroundColor3 = kind == "Group" and C(40, 28, 78) or C(22, 16, 44),
			BackgroundTransparency = kind == "Group" and 0.05 or 0.3, ZIndex = Z + 1 }, rates)
		Kit.Corner(f, kind == "Group" and 9 or 7)
		local name = txt(f, { Name = "Name", Text = "", TextSize = kind == "Group" and 15 or 13, Scaled = true, MinTextSize = 8, ZIndex = Z + 2,
			Color = kind == "Group" and WHITE or SOFT, Stroke = kind == "Group" and 0.4 or nil })
		local pct = txt(f, { Name = "Chance", Text = "", TextSize = kind == "Group" and 15 or 13, Scaled = true, MinTextSize = 8, AlignX = "Right", ZIndex = Z + 2,
			Font = "numeric", Color = kind == "Group" and GOLD or MOON_HI })
		local odds = txt(f, { Name = "Odds", Text = "", TextSize = 12, Scaled = true, MinTextSize = 7, AlignX = "Right", ZIndex = Z + 2, Color = MUTED })
		local dot = Kit.New("Frame", { Name = "Dot", BorderSizePixel = 0, BackgroundColor3 = RARITY[data.Rarity or "Common"] or VIOLET, ZIndex = Z + 2 }, f)
		Kit.Corner(dot, "pill")
		table.insert(rateRows, { Frame = f, Name = name, Chance = pct, Odds = odds, Dot = dot, Kind = kind, Data = data })
	end
	for _, g in ipairs(table0.Groups) do
		addRow("Group", { Group = g, Rarity = (#g.Rows == 1 and g.Rows[1].Rarity) or (g.Rows[1] and g.Rows[1].Rarity) })
		if g.Tiers then
			for _, t in ipairs(g.Tiers) do
				addRow("Tier", { Tier = t, Rarity = t.Tier })
				for _, r in ipairs(t.Rows) do
					addRow("Row", { Row = r, Rarity = r.Rarity })
				end
			end
		elseif #g.Rows > 1 then
			for _, r in ipairs(g.Rows) do
				addRow("Row", { Row = r, Rarity = r.Rarity })
			end
		end
	end
	local totalLine = txt(rates, { Name = "Total", Text = "", TextSize = 14, Scaled = true, MinTextSize = 8, AlignX = "Right", Color = SICKLY, Font = "numeric" })
	-- duplicates
	local dups = panel(scroll, "Duplicates")
	local dupsTitle = sectionTitle(dups, T("DUPLICATES"), MOON_HI)
	local dupCfg = Cfg.Duplicates or { Decor = {}, Skin = {}, Find = {} }
	local dupsBody = txt(dups, { Name = "Body", Text = F("Plot cosmetic you own: %d fragments + %d Lucky Dust. Pickaxe skin you own: %d fragments + %d Lucky Dust. Showcase find you own: %d Bell Shards + %d Lucky Dust. Dogs are always dogs.",
		dupCfg.Decor.Fragments or 12, dupCfg.Decor.Dust or 400, dupCfg.Skin.Fragments or 25, dupCfg.Skin.Dust or 800, dupCfg.Find.Shards or 80,
		dupCfg.Find.Dust or 150), TextSize = 13, Wrap = true, AlignY = "Top", Color = SOFT })
	-- the last results
	local last = panel(scroll, "LastResults")
	local lastTitle = sectionTitle(last, T("LAST RESULTS"), MOON_HI)
	local lastEmpty = txt(last, { Name = "Empty", Text = T("No coffin opened yet."), TextSize = 14, Scaled = true, MinTextSize = 8, Color = MUTED })
	for i = 1, (Cfg.Coffin and Cfg.Coffin.Last) or 10 do
		local f = Kit.New("Frame", { Name = "Result" .. i, BorderSizePixel = 0, BackgroundColor3 = C(22, 16, 44), BackgroundTransparency = 0.25, ZIndex = Z + 1,
			Visible = false }, last)
		Kit.Corner(f, 9)
		local ic, ich = icon(f, "Icon", "Star", { Size = 26 }, Z + 2)
		local name = txt(f, { Name = "Name", Text = "", TextSize = 14, Scaled = true, MinTextSize = 8, ZIndex = Z + 2 })
		local tag = pill(f, "Tag", "", C(60, 60, 90))
		local when = txt(f, { Name = "When", Text = "", TextSize = 12, Scaled = true, MinTextSize = 7, AlignX = "Right", Color = MUTED, ZIndex = Z + 2 })
		P.Results[i] = { Frame = f, Icon = ic, IconH = ich, Name = name, Tag = tag, When = when }
	end

	function P.Open(btn: any)
		if not inZone() then
			descend()
			return
		end
		if not nearAnchor("CoffinShrine") then
			showWay("CoffinShrine", T("THE BLACK COFFIN"))
			return
		end
		-- the opening is a cinematic (CoffinFX, Cinema refuses while a kit window is open): close first, then ask
		if win and win.IsOpen then
			win:Close("coffin")
		end
		act(btn, "coffin", "C2CoffinOpen", {}, function(res)
			local cfx = player:FindFirstChildOfClass("PlayerScripts")
			local hc = cfx and cfx:FindFirstChild("HalloweenClient")
			if not (hc and hc:FindFirstChild("CoffinFX")) then
				-- no presentation module in this build: the reward card at once
				local rows = type(res) == "table" and (res.Rewards or (res.Result and { res.Result }) or (res.Row and { res.Row })) or nil
				reveal(T("THE BLACK COFFIN"), rows, T("THE COFFIN OPENS"))
			end
		end, "")
	end

	local lastW, lastPhone = 600, false
	function P.Layout(Lw)
		local w = (Lw.Width or 600) - 12
		if w < 60 then
			return
		end
		lastW, lastPhone = w, Lw.Phone == true
		local narrow = w < 600
		local y = 2
		-- hero
		local artS = narrow and math.min(130, w * 0.36) or math.min(190, w * 0.28)
		local tx = narrow and 16 or artS + 40
		local tw = w - tx - 16
		place(glow, (narrow and w - artS - 16 or 20) - 12, 6, artS + 24, artS + 24)
		place(coffinArt, narrow and w - artS - 16 or 20, 18, artS, artS)
		local textW0 = narrow and w - artS - 40 or tw
		place(heroKicker, tx, 16, textW0, 18)
		place(heroTitle, tx, 34, textW0, narrow and 34 or 40)
		local bodyY = narrow and math.max(artS + 24, 80) or 80
		local bodyW = narrow and w - 32 or tw
		local bh = textH(heroBody.Text, 14, bodyW)
		place(heroBody, tx, bodyY, bodyW, bh)
		local sy = bodyY + bh + 10
		place(keyIcon, tx, sy, 28, 28)
		place(keyText, tx + 34, sy, 110, 28)
		place(shardIcon, tx + 150, sy, 28, 28)
		place(shardText, tx + 184, sy, 130, 28)
		place(opened, tx, sy + 32, bodyW, 18)
		local by = sy + 56
		local bw = narrow and w - 32 or math.min(300, tw)
		place(openBtn.Instance, tx, by, bw, 50)
		local rh = textH(reason.Text, 13, bw)
		place(reason, tx, by + 56, bw, rh)
		local heroH = math.max(by + 56 + rh + 12, artS + 36)
		place(hero, 2, y, w, heroH)
		y += heroH + 10
		-- key sources
		local kh = textH(keysBody.Text, 13, w - 32)
		place(keysTitle, 16, 12, w - 32, 24)
		place(keysBody, 16, 40, w - 32, kh)
		place(keysCard, 2, y, w, 40 + kh + 12)
		y += 40 + kh + 22
		-- drop rates
		place(ratesTitle, 16, 12, w - 32, 24)
		local nh = textH(ratesNote.Text, 13, w - 32)
		place(ratesNote, 16, 40, w - 32, nh)
		local ry = 40 + nh + 10
		local oddsW = narrow and 0 or 120
		local pctW = narrow and 76 or 96
		for _, r in ipairs(rateRows) do
			local indent = r.Kind == "Group" and 0 or r.Kind == "Tier" and 14 or 28
			local h = r.Kind == "Group" and 30 or 24
			place(r.Frame, 12 + indent, ry, w - 24 - indent, h)
			local fw = w - 24 - indent
			place(r.Dot, 8, h / 2 - 5, 10, 10)
			place(r.Name, 24, 2, fw - 24 - pctW - oddsW - 12, h - 4)
			place(r.Chance, fw - pctW - oddsW - 8, 2, pctW, h - 4)
			r.Odds.Visible = oddsW > 0
			place(r.Odds, fw - oddsW - 6, 2, oddsW, h - 4)
			ry += h + (r.Kind == "Group" and 5 or 3)
		end
		place(totalLine, 12, ry + 2, w - 24, 20)
		ry += 30
		place(rates, 2, y, w, ry)
		y += ry + 10
		-- duplicates
		local dh = textH(dupsBody.Text, 13, w - 32)
		place(dupsTitle, 16, 12, w - 32, 24)
		place(dupsBody, 16, 40, w - 32, dh)
		place(dups, 2, y, w, 40 + dh + 12)
		y += 40 + dh + 22
		-- last results
		place(lastTitle, 16, 12, w - 32, 24)
		local ly = 44
		local any = false
		for _, r in ipairs(P.Results) do
			if r.Frame.Visible then
				any = true
				place(r.Frame, 12, ly, w - 24, 36)
				place(r.Icon, 6, 4, 28, 28)
				local whenW = narrow and 70 or 110
				local tagW = r.Tag.Instance.Visible and (math.ceil(textW(r.Tag.Label.Text, 13)) + 22) or 0
				place(r.Name, 40, 6, w - 24 - 40 - whenW - tagW - 20, 24)
				r.Tag.Instance.Position = UDim2.fromOffset(w - 24 - whenW - tagW - 10, 6)
				place(r.When, w - 24 - whenW - 8, 6, whenW, 24)
				ly += 40
			end
		end
		lastEmpty.Visible = not any
		place(lastEmpty, 16, ly, w - 32, 22)
		if not any then
			ly += 30
		end
		place(last, 2, y, w, ly + 8)
		y += ly + 18
		scroll.CanvasSize = UDim2.fromOffset(0, y + 4)
	end

	local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	local function ago(at: number): string
		local d = math.max(0, now() - (tonumber(at) or 0))
		if d < 60 then
			return T("just now")
		elseif d < 3600 then
			return F("%d min ago", math.floor(d / 60))
		elseif d < 86400 then
			return F("%d h ago", math.floor(d / 3600))
		end
		local t = os.date("!*t", math.floor(tonumber(at) or 0)) :: any
		return tostring(t.day) .. " " .. T(MONTHS[t.month] or "")
	end

	function P.Refresh()
		local v = view()
		local k, s = keys(), shards()
		local maxKeys = tonumber(v.MaxKeys) or (Cfg.Coffin and Cfg.Coffin.MaxKeys) or 12
		keyText.Text = F("%d / %d", k, maxKeys)
		keyText.TextColor3 = k >= price.Keys and WHITE or BLOOD
		shardText.Text = num(s)
		shardText.TextColor3 = s >= price.Shards and WHITE or BLOOD
		opened.Text = F("Coffins opened: %d", tonumber(v.Coffins and v.Coffins.Opened) or 0)
		local why = ""
		if not eligible() then
			openBtn:SetText(T("FINISH CHAPTER I"))
			openBtn:SetStyle("secondary")
			openBtn:SetDisabled(true)
		elseif inTrial() then
			openBtn:SetText(T("IN A TRIAL"))
			openBtn:SetStyle("secondary")
			openBtn:SetDisabled(true)
		elseif k < price.Keys then
			openBtn:SetText(T("NEED A COFFIN KEY"))
			openBtn:SetStyle("secondary")
			openBtn:SetDisabled(true)
			why = T("Claim all three contracts today for a key, or break a seal.")
		elseif s < price.Shards then
			openBtn:SetText(F("NEED %s MORE", num(price.Shards - s)))
			openBtn:SetStyle("secondary")
			openBtn:SetDisabled(true)
			why = T("Earn Bell Shards: contracts, echoes, trials, the Gravekeeper and the Toll Box.")
		elseif not inZone() then
			openBtn:SetText(T("DESCEND"))
			openBtn:SetStyle("primary", VIOLET)
			openBtn:SetDisabled(false)
			why = T("The shrine stands in Bell Square, below the church.")
		elseif not nearAnchor("CoffinShrine") then
			openBtn:SetText(T("SHOW THE WAY"))
			openBtn:SetStyle("primary", VIOLET)
			openBtn:SetDisabled(false)
			why = T("Walk up to the shrine to open the coffin.")
		else
			openBtn:SetText(T("OPEN THE COFFIN"))
			openBtn:SetStyle("gold")
			openBtn:SetDisabled(false)
		end
		local changed = reason.Text ~= why
		reason.Text = why
		P.Near = nearAnchor("CoffinShrine")
		-- drop rates
		for _, r in ipairs(rateRows) do
			local d = r.Data
			if r.Kind == "Group" then
				local g = d.Group
				local name = upper(L(g.Name))
				if #g.Rows == 1 and g.Rows[1].Amount ~= "" then
					name ..= "  " .. g.Rows[1].Amount
				elseif #g.Rows > 1 then
					name ..= "  ×" .. #g.Rows
				end
				r.Name.Text = name
				r.Chance.Text = UV.Percent(g.Chance)
				r.Odds.Text = F("1 in %s", UV.Odds(g.Chance))
			elseif r.Kind == "Tier" then
				r.Name.Text = upper(L(d.Tier.Name)) .. "  ×" .. #d.Tier.Rows
				r.Chance.Text = UV.Percent(d.Tier.Chance)
				r.Odds.Text = F("1 in %s", UV.Odds(d.Tier.Chance))
			else
				local row = d.Row
				r.Name.Text = L(row.Name) .. (row.Amount ~= "" and ("  " .. row.Amount) or "")
				r.Chance.Text = UV.Percent(row.Chance)
				r.Odds.Text = F("1 in %s", UV.Odds(row.Chance))
			end
		end
		totalLine.Text = F("TOTAL %s", UV.Percent(table0.Total))
		-- the last results
		local list = (v.Coffins and v.Coffins.Last) or {}
		for i, r in ipairs(P.Results) do
			local row = list[i]
			local vis = row ~= nil
			if r.Frame.Visible ~= vis then
				r.Frame.Visible = vis
				changed = true
			end
			if row then
				local kind, o: any = "Star", {}
				if UIcons then
					kind, o = UIcons.ForReward(row)
				end
				if r.IconH and r.IconH.Set then
					r.IconH:Set(kind, { Size = 26, Color = o.Color, Glow = o.Glow })
				end
				local amount = tonumber(row.Amount) or 0
				local name = upper(UV.RowName(row, lang()))
				if amount > 1 then
					name = num(amount) .. " " .. name
				end
				r.Name.Text = name
				local rarity = UV.RowRarity(row)
				r.Name.TextColor3 = (RARITY[rarity] or WHITE):Lerp(WHITE, 0.45)
				if row.Converted then
					r.Tag:Set(T("CONVERTED"), C(90, 70, 40), WHITE)
					r.Tag.Instance.Visible = true
				elseif (tonumber(row.Rank) or 1) >= 4 then
					r.Tag:Set(T(string.upper(rarity)), RARITY[rarity] or VIOLET, WHITE)
					r.Tag.Instance.Visible = true
				else
					r.Tag.Instance.Visible = false
				end
				r.When.Text = ago(row.At)
			end
		end
		if changed then
			P.Layout({ Width = lastW + 12, Phone = lastPhone })
		end
		P.Ready = UV.Badges(v, hview(), now(), ctx()).coffin
	end

	function P.Tick()
		if P.Near ~= nearAnchor("CoffinShrine") then
			P.Refresh()
		end
		if not reduced() and coffinH and coffinH.Instance then
			glow.BackgroundTransparency = 0.72 + 0.08 * math.sin(os.clock() * 2)
		end
	end
	return P
end

---------------------------------------------------------------------------- DEX II
pages.dex = function(page: Frame)
	local P: any = {}
	local scroll = scrollPage(page)
	local order = (Cfg.Dogs and Cfg.Dogs.Order) or {}
	local defs = (Cfg.Dogs and Cfg.Dogs.Defs) or {}
	local kind = registerDogPreview()

	local head = panel(scroll, "Progress", C(70, 46, 128), C(22, 14, 50))
	local headTitle = sectionTitle(head, T("THE UNDERYARD COLLECTION"), MOON_HI)
	local headCount = txt(head, { Name = "Count", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Right", Color = SICKLY, Font = "numeric",
		Stroke = 0.3 })
	local headBar = bar(head, "Bar", SICKLY, 18)
	local headInfo = txt(head, { Name = "Info", Text = T("Eight dogs live below the last bell: seals, the Black Coffin, the Gravekeeper's last stand and one hidden room hold them."),
		TextSize = 14, Wrap = true, Color = MUTED, AlignY = "Top" })
	local openDex = button(head, { Name = "OpenDex", Text = T("OPEN DOGDEX"), Style = "secondary", TextSize = 15, OnClick = function()
		S.OpenDogDex()
	end })

	local track = panel(scroll, "Milestones")
	local trackTitle = sectionTitle(track, T("DEX II MILESTONES"), CANDLE)
	local nodes = {}
	for i, tier in ipairs(Cfg.Dex2Rewards or {}) do
		local node = Kit.New("Frame", { Name = "Milestone" .. i, BorderSizePixel = 0, BackgroundColor3 = C(20, 14, 40), BackgroundTransparency = 0.3, ZIndex = Z + 1 }, track)
		Kit.Corner(node, 12)
		local circle = Kit.New("Frame", { Name = "Count", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = Z + 2 }, node)
		Kit.Corner(circle, "pill")
		Kit.Stroke(circle, INK, 2, 0.2)
		local count = txt(circle, { Name = "Text", Text = tostring(tier.Count), TextSize = 20, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = Z + 3,
			Stroke = 0.2 })
		local chips = Kit.New("Frame", { Name = "Chips", BackgroundTransparency = 1, ZIndex = Z + 1 }, node)
		local claim
		claim = button(node, { Name = "Claim", Text = T("CLAIM"), Style = "success", TextSize = 13, OnClick = function()
			act(claim, tostring(tier.Count), "C2DexClaim", { Count = tier.Count }, function(res)
				reveal(F("%d UNDERYARD DOGS FOUND", tier.Count), res and res.Rewards, T("DEX II REWARD"))
			end, "")
		end })
		nodes[i] = { Frame = node, Circle = circle, Count = count, Chips = chips, Claim = claim, Tier = tier }
	end

	local cards = {}
	for i, id in ipairs(order) do
		local def = defs[id] or {}
		local card = panel(scroll, "Dog_" .. id)
		local holder = Kit.New("TextButton", { Name = "PreviewHolder", Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = WHITE,
			ZIndex = Z + 1, ClipsDescendants = true }, card)
		Kit.Corner(holder, 12)
		gradient(holder, C(96, 80, 170), C(24, 16, 52))
		local slot = Kit.Preview.Slot(holder)
		local rarityName = Shared and select(1, Shared.Rarity(def.Rank or 2)) or "Rare"
		local code = pill(card, "Code", def.Code or ("H" .. (8 + i)), C(20, 14, 40))
		local rarity = Kit.Pill(card, { Name = "Rarity", Text = T(string.upper(rarityName)), Color = RARITY[rarityName] or VIOLET, Height = 22, TextSize = 12,
			NoTranslate = true, ZIndex = Z + 2 })
		local grad = Theme.RarityGradient[rarityName]
		if grad then
			rarity:SetGradient(grad[1], grad[2])
		end
		local name = txt(card, { Name = "Name", Text = "", TextSize = 17, Scaled = true, MinTextSize = 10, AlignX = "Center", Stroke = 0.4 })
		local ability = txt(card, { Name = "Ability", Text = "", TextSize = 12, Wrap = true, AlignX = "Center", AlignY = "Top", Color = SOFT })
		local status = txt(card, { Name = "Status", Text = "", TextSize = 12, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = MUTED })
		cards[i] = { Id = id, Def = def, Frame = card, Holder = holder, Slot = slot, Code = code, Rarity = rarity, RarityName = rarityName, Name = name,
			Ability = ability, Status = status, Secret = (def.Rank or 0) >= 6 }
		holder.Activated:Connect(function()
			P.Detail(i)
		end)
	end

	local function abilityText(c: any, has: boolean): string
		local info = UV.Dicts().Own.Dogs and UV.Dicts().Own.Dogs[c.Id]
		if c.Secret and not has then
			return T("A secret of the Underyard. Only a crowned few ever see it.")
		end
		if not info then
			return ""
		end
		return upper(L(info.Ability)) .. ": " .. L(info.Text)
	end

	function P.Detail(i: number)
		local c = cards[i]
		if not c then
			return
		end
		local has = (view().Dex2 and view().Dex2.Dex and view().Dex2.Dex[c.Id]) == true
		local sources = {}
		for _, pair in ipairs(UV.DogSources(c.Id)) do
			table.insert(sources, L(pair))
		end
		local hidden = c.Secret and not has
		openSheet({
			Title = hidden and "???" or upper(L(c.Def.Name)), Sub = (c.Def.Code or "") .. " · " .. (has and T("DISCOVERED") or T("NOT FOUND YET")),
			Rarity = c.RarityName, Body = abilityText(c, has) .. "\n\n" .. T("WHERE TO FIND IT") .. ": " .. table.concat(sources, " · "),
			Preview = { Kind = kind, DogId = c.Id, Silhouette = not has }, Kind = "Dog",
		})
	end

	local function layoutTrack(x: number, y: number, w: number): number
		place(trackTitle, 16, 12, w - 32, 26)
		local ny = 46
		for _, n in ipairs(nodes) do
			local chipW = w - 24 - 62 - 118
			local h = chipRow(n.Chips, n.Tier.Rows or {}, chipW, 24)
			local nh = math.max(60, h + 16)
			place(n.Frame, 12, ny, w - 24, nh)
			place(n.Circle, 8, nh / 2 - 22, 44, 44)
			place(n.Count, 4, 4, 36, 36)
			place(n.Chips, 62, 8, chipW, nh - 16)
			place(n.Claim.Instance, w - 24 - 112, nh / 2 - 19, 104, 38)
			ny += nh + 8
		end
		place(track, x, y, w, ny + 6)
		return ny + 6
	end

	function P.Layout(Lw)
		local w = (Lw.Width or 600) - 12
		if w < 60 then
			return
		end
		local wide = w >= 900
		local gridX, gridW, gridY = 2, w, 0
		local rw = wide and 380 or w
		local infoH = math.max(36, textH(headInfo.Text, 14, rw - 32))
		local headH = 74 + infoH + 56
		if wide then
			gridW = w - rw - 12
			local rx = 2 + gridW + 12
			place(head, rx, 2, rw, headH)
			local th = layoutTrack(rx, 2 + headH + 12, rw)
			gridY = 2
			P.SideBottom = 2 + headH + 12 + th
		else
			place(head, 2, 2, w, headH)
			local th = layoutTrack(2, 2 + headH + 12, w)
			gridY = 2 + headH + 12 + th + 12
			P.SideBottom = gridY
		end
		local hw = head.Size.X.Offset
		place(headTitle, 16, 12, hw - 136, 26)
		place(headCount, hw - 110, 12, 94, 28)
		place(headBar.Instance, 16, 48, hw - 32, 18)
		place(headInfo, 16, 74, hw - 32, infoH)
		place(openDex.Instance, 16, headH - 50, math.min(240, hw - 32), 40)
		local cols = gridW >= 700 and 4 or gridW >= 500 and 3 or 2
		local gap = 12
		local cw = math.floor((gridW - gap * (cols - 1)) / cols)
		local ph = math.floor(cw * 0.66)
		local abilityH = 40
		for _, c in ipairs(cards) do
			abilityH = math.max(abilityH, textH(c.Ability.Text ~= "" and c.Ability.Text or "x", 12, cw - 16))
		end
		local ch = ph + 62 + abilityH
		for i, c in ipairs(cards) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			place(c.Frame, gridX + col * (cw + gap), gridY + row * (ch + gap), cw, ch)
			place(c.Holder, 8, 8, cw - 16, ph)
			c.Code.Instance.Position = UDim2.fromOffset(14, 14)
			c.Rarity.Instance.AnchorPoint = Vector2.new(1, 0)
			c.Rarity.Instance.Position = UDim2.new(1, -14, 0, 14)
			place(c.Name, 8, ph + 12, cw - 16, 22)
			place(c.Ability, 8, ph + 36, cw - 16, abilityH)
			place(c.Status, 8, ch - 22, cw - 16, 16)
		end
		local rows = math.ceil(#cards / cols)
		scroll.CanvasSize = UDim2.fromOffset(0, math.max(gridY + rows * (ch + gap), P.SideBottom or 0) + 4)
		P.LastL = Lw
	end

	function P.Refresh()
		local v = view()
		local d2 = v.Dex2 or {}
		local dex = d2.Dex or {}
		local found = 0
		local textChanged = false
		for _, c in ipairs(cards) do
			local has = dex[c.Id] == true
			if has then
				found += 1
			end
			c.Slot:Show({ Kind = kind, DogId = c.Id, Silhouette = not has })
			local hidden = c.Secret and not has
			c.Name.Text = hidden and "???" or upper(L(c.Def.Name))
			c.Name.TextColor3 = has and WHITE or MUTED
			local a = abilityText(c, has)
			if a ~= c.Ability.Text then
				textChanged = true
			end
			c.Ability.Text = a
			c.Status.Text = has and ("✓ " .. T("DISCOVERED")) or T("NOT FOUND YET")
			c.Status.TextColor3 = has and SICKLY or MUTED
			local stroke = c.Frame:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = has and SICKLY or PANEL_EDGE
			end
		end
		local total = #cards
		local count = tonumber(d2.Count) or found
		headCount.Text = F("%d / %d", count, total)
		headBar:SetValue(total > 0 and count / total or 0)
		local claims = d2.Claims or {}
		local ready = 0
		for _, n in ipairs(nodes) do
			local claimed = claims[tostring(n.Tier.Count)] == true
			local can = count >= n.Tier.Count and not claimed and eligible()
			if can then
				ready += 1
			end
			gradient(n.Circle, (claimed and SICKLY or can and CANDLE or C(90, 70, 140)):Lerp(WHITE, 0.15), claimed and C(40, 140, 60) or can and C(190, 90, 20) or C(40, 26, 70))
			n.Count.Text = claimed and "✓" or tostring(n.Tier.Count)
			if claimed then
				n.Claim:SetText(T("CLAIMED"))
				n.Claim:SetStyle("secondary")
				n.Claim:SetDisabled(true)
			elseif can then
				n.Claim:SetText(T("CLAIM"))
				n.Claim:SetStyle("success")
				n.Claim:SetDisabled(false)
			else
				n.Claim:SetText(F("%d / %d", math.min(count, n.Tier.Count), n.Tier.Count))
				n.Claim:SetStyle("secondary")
				n.Claim:SetDisabled(true)
			end
		end
		P.Ready = ready
		if textChanged and P.LastL then
			P.Layout(P.LastL)
		end
	end
	return P
end

---------------------------------------------------------------------------- COLLECTION
pages.collection = function(page: Frame)
	local P: any = { Sections = {}, Built = {} }
	local scroll = scrollPage(page)
	local head = panel(scroll, "Tailor", C(80, 50, 120), C(26, 14, 48))
	local headIcon = icon(head, "Icon", "Fragment", { Size = 56 })
	local headTitle = sectionTitle(head, T("THE TAILOR OF THE DEAD"), CANDLE)
	local fragIcon = icon(head, "FragIcon", "Fragment", { Size = 26 })
	local fragText = txt(head, { Name = "Fragments", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, Font = "numeric", Stroke = 0.3 })
	local headInfo = txt(head, { Name = "Info", Text = F("Fragments from duplicates and the Black Coffin buy any plot cosmetic for %d and any pickaxe skin for %d. The Tailor never sews the Dex II secret skin.",
		(Cfg.Craft and Cfg.Craft.Decor) or 45, (Cfg.Craft and Cfg.Craft.Skin) or 90), TextSize = 13, Wrap = true, AlignY = "Top", Color = SOFT })

	local SECTIONS = {
		{ Id = "Skins", Title = "PICKAXE SKINS", Icon = "Pickaxe" },
		{ Id = "Decor", Title = "PLOT COSMETICS", Icon = "Tombstone" },
		{ Id = "Finds", Title = "SHOWCASE FINDS", Icon = "Relic" },
	}
	local col0 = UV.Collection(view(), hview())
	for _, spec in ipairs(SECTIONS) do
		local sec: any = { Spec = spec, Cards = {} }
		sec.Title = txt(scroll, { Name = spec.Id .. "Title", Text = T(spec.Title), TextSize = 20, Scaled = true, MinTextSize = 10, Color = MOON_HI, Stroke = 0.35 })
		sec.Count = txt(scroll, { Name = spec.Id .. "Count", Text = "", TextSize = 16, Scaled = true, MinTextSize = 9, AlignX = "Right", Color = SICKLY, Font = "numeric" })
		for i, item in ipairs(col0[spec.Id]) do
			local card = panel(scroll, spec.Id .. "_" .. item.Id)
			local holder = Kit.New("TextButton", { Name = "PreviewHolder", Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = WHITE,
				ZIndex = Z + 1, ClipsDescendants = true }, card)
			Kit.Corner(holder, 10)
			local rc = RARITY[item.Rarity or "Rare"] or VIOLET
			gradient(holder, rc:Lerp(C(40, 30, 80), 0.62), C(10, 8, 22))
			local art, artH = icon(holder, "Art", spec.Icon, { Size = 64, Color = spec.Id == "Finds" and rc or nil, Glow = spec.Id ~= "Finds" and rc or nil }, Z + 2)
			local lockF = icon(holder, "Lock", "Lock", { Size = 22 }, Z + 4)
			local rarity = Kit.Pill(card, { Name = "Rarity", Text = T(string.upper(item.Rarity or "Rare")), Color = rc, Height = 20, TextSize = 11, NoTranslate = true,
				ZIndex = Z + 3 })
			local grad = Theme.RarityGradient[item.Rarity or ""]
			if grad then
				rarity:SetGradient(grad[1], grad[2])
			end
			local name = txt(card, { Name = "Name", Text = upper(L(item.Name)), TextSize = 14, Scaled = true, MinTextSize = 8, AlignX = "Center", Stroke = 0.4 })
			local status = txt(card, { Name = "Status", Text = "", TextSize = 11, Scaled = true, MinTextSize = 7, AlignX = "Center", Color = MUTED })
			local craft
			craft = button(card, { Name = "Craft", Text = "", Style = "gold", TextSize = 14, OnClick = function()
				P.Craft(spec.Id, i, craft)
			end })
			local c: any = { Item = item, Frame = card, Holder = holder, Art = art, ArtH = artH, Lock = lockF, Rarity = rarity, Name = name, Status = status,
				Craft = craft }
			sec.Cards[i] = c
			holder.Activated:Connect(function()
				P.Detail(spec.Id, i)
			end)
		end
		table.insert(P.Sections, sec)
	end

	local function itemOf(sectionId: string, i: number): any
		local col = UV.Collection(view(), hview())
		return col[sectionId] and col[sectionId][i]
	end
	local function itemName(item: any): string
		-- plot cosmetics read as in the decor window (DecorCatalog names)
		if item.Kind == "Decor" then
			local ok, Catalog = pcall(function()
				return require(RS:WaitForChild("DogEconomy"):WaitForChild("DecorCatalog")) :: any
			end)
			local row = ok and Catalog and Catalog.Get and Catalog.Get(item.Id)
			if row then
				return upper(Catalog.ItemName(row, lang() == "ru"))
			end
		end
		return upper(L(item.Name))
	end

	function P.Craft(sectionId: string, i: number, btn: any)
		local item = itemOf(sectionId, i)
		if not item or item.Owned or not item.Cost or item.DexOnly then
			return
		end
		local fragments = tonumber(view().Fragments) or 0
		if fragments < item.Cost then
			toast(F("Need %d more fragments", item.Cost - fragments), "warn")
			return
		end
		local name = itemName(item)
		local confirm = Kit.Confirm(T("SEW IT?"), F("THE TAILOR OF THE DEAD sews %s for %d fragments. You keep it forever.", name, item.Cost),
			{ ConfirmText = T("CRAFT"), CancelText = T("CANCEL"), NoTranslate = true, Accent = VIOLET })
		confirm:Then(function(ok)
			if not ok then
				return
			end
			act(btn, item.Id, "C2Craft", { Id = item.Id }, function()
				closeSheet("crafted")
				reveal(T("THE TAILOR OF THE DEAD"), { { Kind = item.Kind, Id = item.Id, Amount = 1 } }, T("SEWN FOR YOU"))
			end, "")
		end)
	end

	function P.Detail(sectionId: string, i: number)
		local item = itemOf(sectionId, i)
		if not item then
			return
		end
		local body, source = "", ""
		if item.Kind == "Find" then
			local ok, Items = pcall(function()
				return require(RS:WaitForChild("DogEconomy"):WaitForChild("ItemDefinitions")) :: any
			end)
			local def = ok and type(Items) == "table" and Items[item.Id] or nil
			if def then
				body = (lang() == "ru" and def.DescriptionRU) or def.Description or ""
			end
			source = T("The Black Coffin and the Crooked Doors. A duplicate turns into shards and Lucky Dust.")
		elseif item.Kind == "Decor" then
			body = item.Size == "Large" and T("A large plot cosmetic with its own idle animation.") or T("A small plot cosmetic with its own idle animation.")
			source = T("The Black Coffin, Bell Seals, the Dex II or the Tailor of the Dead.")
		else
			body = T("A pickaxe skin only changes the look: every stat still comes from your real pickaxe.")
			source = item.DexOnly and T("Only the Dex II gives it: find all eight Underyard dogs.") or T("The Black Coffin, the Dex II, the Gravekeeper's last stand or the Tailor of the Dead.")
		end
		local model = itemModel(item)
		local fragments = tonumber(view().Fragments) or 0
		local btnSpec = nil
		if item.Owned then
			btnSpec = { Text = "✓ " .. T("OWNED"), Style = "success", Disabled = true }
		elseif item.Cost and not item.DexOnly then
			btnSpec = { Text = F("CRAFT · %d FRAGMENTS", item.Cost), Style = "gold", Disabled = fragments < item.Cost or not eligible(), OnClick = function(b)
				P.Craft(sectionId, i, b)
			end }
		end
		openSheet({
			Title = itemName(item), Sub = item.Owned and T("IN YOUR COLLECTION") or T("MISSING"), Rarity = item.Rarity, Body = body .. "\n\n" .. source,
			Model = model, Kind = sectionId == "Finds" and "Relic" or sectionId == "Decor" and "Tombstone" or "Pickaxe", Button = btnSpec, Dim = not item.Owned and 0.4 or nil,
		})
	end

	function P.Layout(Lw)
		local w = (Lw.Width or 600) - 12
		if w < 60 then
			return
		end
		P.LastL = Lw
		local y = 2
		place(headIcon, 14, 14, 52, 52)
		local fw = 120
		place(headTitle, 76, 14, w - 92 - fw, 26)
		place(fragIcon, w - fw - 14, 14, 26, 26)
		place(fragText, w - fw + 16, 14, fw - 30, 26)
		local ih = textH(headInfo.Text, 13, w - 92)
		place(headInfo, 76, 46, w - 92, ih)
		local headH = math.max(80, 46 + ih + 12)
		place(head, 2, y, w, headH)
		y += headH + 14
		local cols = w >= 860 and 5 or w >= 640 and 4 or w >= 460 and 3 or 2
		local gap = 10
		local cw = math.floor((w - gap * (cols - 1)) / cols)
		local ph = math.floor(cw * 0.72)
		local ch = ph + 100
		for _, sec in ipairs(P.Sections) do
			place(sec.Title, 4, y, w - 120, 26)
			place(sec.Count, w - 110, y, 106, 26)
			y += 32
			for i, c in ipairs(sec.Cards) do
				local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
				place(c.Frame, 2 + col * (cw + gap), y + row * (ch + gap), cw, ch)
				place(c.Holder, 6, 6, cw - 12, ph)
				place(c.Art, (cw - 12) / 2 - ph * 0.36, ph * 0.14, ph * 0.72, ph * 0.72)
				place(c.Lock, 6, ph - 28, 22, 22)
				c.Rarity.Instance.AnchorPoint = Vector2.new(1, 0)
				c.Rarity.Instance.Position = UDim2.new(1, -10, 0, 10)
				place(c.Name, 6, ph + 10, cw - 12, 20)
				place(c.Status, 6, ph + 32, cw - 12, 16)
				place(c.Craft.Instance, 8, ch - 46, cw - 16, 38)
			end
			y += math.ceil(#sec.Cards / cols) * (ch + gap) + 8
		end
		scroll.CanvasSize = UDim2.fromOffset(0, y + 4)
	end

	function P.Refresh()
		local v = view()
		local col = UV.Collection(v, hview())
		local fragments = tonumber(v.Fragments) or 0
		fragText.Text = num(fragments)
		for _, sec in ipairs(P.Sections) do
			local list = col[sec.Spec.Id] or {}
			local have = 0
			for i, c in ipairs(sec.Cards) do
				local item = list[i] or c.Item
				c.Item = item
				if item.Owned then
					have += 1
				end
				c.Name.Text = itemName(item)
				c.Lock.Visible = not item.Owned
				if c.ArtH and c.ArtH.Set and not c.Built then
					local rc = RARITY[item.Rarity or "Rare"] or VIOLET
					c.ArtH:Set(sec.Spec.Icon, { Size = 64, Color = sec.Spec.Id == "Finds" and rc or nil, Glow = sec.Spec.Id ~= "Finds" and rc or nil,
						Dim = (not item.Owned) and 0.45 or nil })
				end
				if c.VP then
					c.VP.ImageColor3 = item.Owned and WHITE or C(120, 112, 150)
				end
				local stroke = c.Frame:FindFirstChildWhichIsA("UIStroke")
				if stroke then
					stroke.Color = item.Owned and SICKLY or PANEL_EDGE
				end
				if item.Owned then
					c.Status.Text = "✓ " .. T("OWNED")
					c.Status.TextColor3 = SICKLY
					c.Craft:SetText(T("OWNED"))
					c.Craft:SetStyle("secondary")
					c.Craft:SetDisabled(true)
				elseif item.Kind == "Find" then
					c.Status.Text = T("BLACK COFFIN")
					c.Status.TextColor3 = MUTED
					c.Craft:SetText(T("DETAILS"))
					c.Craft:SetStyle("secondary")
					c.Craft:SetDisabled(false)
					c.Craft:SetOnClick(function()
						P.Detail(sec.Spec.Id, i)
					end)
				elseif item.DexOnly then
					c.Status.Text = T("DEX II 8 / 8")
					c.Status.TextColor3 = GOLD
					c.Craft:SetText(T("DEX II ONLY"))
					c.Craft:SetStyle("secondary")
					c.Craft:SetDisabled(true)
				else
					c.Status.Text = F("%d FRAGMENTS", item.Cost or 0)
					c.Status.TextColor3 = fragments >= (item.Cost or 0) and CANDLE or MUTED
					c.Craft:SetText(T("CRAFT"))
					c.Craft:SetStyle(fragments >= (item.Cost or 0) and "gold" or "secondary")
					c.Craft:SetDisabled(fragments < (item.Cost or 0) or not eligible())
				end
			end
			sec.Count.Text = F("%d / %d", have, #sec.Cards)
		end
		P.Ready = UV.Badges(v, hview(), now(), ctx()).collection
	end

	-- 3D previews: built the first time the tab is shown, one per frame, cards on screen first; the loop stops when
	-- the window closes or the tab changes and resumes on the next show
	local building = false
	function P.Shown()
		if building then
			return
		end
		building = true
		task.spawn(function()
			local list = {}
			for _, sec in ipairs(P.Sections) do
				for _, c in ipairs(sec.Cards) do
					if not c.Built then
						table.insert(list, c)
					end
				end
			end
			local top = scroll.AbsolutePosition.Y
			local bottom = top + scroll.AbsoluteSize.Y
			table.sort(list, function(a, b)
				local ay, by = a.Frame.AbsolutePosition.Y, b.Frame.AbsolutePosition.Y
				local aOn, bOn = ay < bottom and ay + a.Frame.AbsoluteSize.Y > top, by < bottom and by + b.Frame.AbsoluteSize.Y > top
				if aOn ~= bOn then
					return aOn
				end
				return ay < by
			end)
			for _, c in ipairs(list) do
				if not (win and win.IsOpen and st.Tab == "collection") then
					break
				end
				if not c.Built then
					c.Built = true
					local model = itemModel(c.Item)
					if model then
						local okV, vp = pcall(viewport, c.Holder, model, Z + 2, c.Item.Kind == "Find" and 30 or 18)
						if okV and vp then
							c.VP = vp
							c.Art.Visible = false
							vp.ImageColor3 = c.Item.Owned and WHITE or C(120, 112, 150)
						end
					end
				end
				task.wait()
			end
			building = false
		end)
	end
	return P
end

---------------------------------------------------------------------------- JOURNAL
pages.journal = function(page: Frame)
	local P: any = { Entries = {} }
	local scroll = scrollPage(page)
	local head = panel(scroll, "Header", C(70, 46, 128), C(22, 14, 50))
	local headIcon = icon(head, "Icon", "Eye", { Size = 52 })
	local headTitle = sectionTitle(head, T("EVENT JOURNAL"), MOON_HI)
	local headCount = txt(head, { Name = "Count", Text = "", TextSize = 20, Scaled = true, MinTextSize = 9, AlignX = "Right", Color = SICKLY, Font = "numeric" })
	local headInfo = txt(head, { Name = "Info", Text = T("Every story beat of both chapters. Replays never change your progress."), TextSize = 13, Wrap = true,
		AlignY = "Top", Color = MUTED })
	local journal = Cfg.Journal or { Order = {}, Entries = {} }
	for i, key in ipairs(journal.Order) do
		local def = journal.Entries[key] or {}
		local card = panel(scroll, "Entry_" .. key)
		local kindIcon = string.match(key, "^seal") and "Seal" or key == "chapter1" and "Moon" or key == "finale" and "Skull" or key == "assault" and "Bell" or "Eye"
		local ic, icH = icon(card, "Icon", kindIcon, { Size = 44, Glow = MOON })
		local title = txt(card, { Name = "Title", Text = "", TextSize = 18, Scaled = true, MinTextSize = 9, Stroke = 0.35 })
		local date = txt(card, { Name = "Date", Text = "", TextSize = 12, Scaled = true, MinTextSize = 7, AlignX = "Right", Color = MUTED })
		local new = pill(card, "New", T("NEW"), CANDLE)
		local body = txt(card, { Name = "Body", Text = "", TextSize = 14, Wrap = true, AlignY = "Top", Color = SOFT })
		local replays = {}
		for k, r in ipairs(UV.JournalReplays(key)) do
			local b
			b = button(card, { Name = "Replay" .. k, Text = T("REPLAY") .. " · " .. L(r.Label), Style = "secondary", TextSize = 13, OnClick = function()
				P.Replay(r, b)
			end })
			replays[k] = { Button = b, Spec = r }
		end
		P.Entries[i] = { Key = key, Def = def, Frame = card, Icon = ic, IconH = icH, KindIcon = kindIcon, Title = title, Date = date, New = new, Body = body,
			Replays = replays }
	end

	-- a replay: Bus events only (the cinematic modules listen); nothing is sent to the server
	function P.Replay(r: any, _b: any)
		if not Bus then
			return
		end
		if r.Bus == "CauldronClaimLocal" then
			-- the brew finale plays at the Haunted Cauldron (CauldronFX); empty rows = no reward card (A04 §11.A)
			local level = math.clamp(tonumber(hview().Cauldron and hview().Cauldron.Level) or 5, 1, 5)
			local d: any = { Level = level, Rows = {}, Reveal = function() end, FromWindow = true, Replay = true }
			Bus.Fire("CauldronClaimLocal", d)
			if d.Handled then
				if win and win.IsOpen then
					win:Close("replay")
				end
			else
				toast(T("Go to the Haunted Cauldron in the Dead Yard to replay the brew"), "info")
			end
			return
		end
		if win and win.IsOpen then
			win:Close("replay")
		end
		local data = table.clone(r.Data or {})
		data.Replay = true
		data.Source = "Journal"
		-- one beat later: the window has handed the camera and the controls back
		task.delay(0.25, function()
			Bus.Fire(r.Bus, data)
		end)
	end

	local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	local function dateText(at: any): string
		local n = tonumber(at) or 0
		if n <= 0 then
			return ""
		end
		local t = os.date("!*t", math.floor(n)) :: any
		return tostring(t.day) .. " " .. T(MONTHS[t.month] or "")
	end

	local lastL = nil
	function P.Layout(Lw)
		local w = (Lw.Width or 600) - 12
		if w < 60 then
			return
		end
		lastL = Lw
		local y = 2
		place(headIcon, 14, 12, 48, 48)
		place(headTitle, 72, 12, w - 88 - 90, 26)
		place(headCount, w - 100, 12, 86, 26)
		local ih = textH(headInfo.Text, 13, w - 88)
		place(headInfo, 72, 42, w - 88, ih)
		local headH = math.max(72, 42 + ih + 12)
		place(head, 2, y, w, headH)
		y += headH + 10
		local narrow = w < 560
		for _, e in ipairs(P.Entries) do
			place(e.Icon, 14, 14, 40, 40)
			local dateW = narrow and 70 or 110
			local newW = e.New.Instance.Visible and (math.ceil(textW(e.New.Label.Text, 13)) + 24) or 0
			place(e.Title, 64, 14, w - 64 - dateW - newW - 24, 24)
			e.New.Instance.Position = UDim2.fromOffset(w - dateW - newW - 14, 14)
			place(e.Date, w - dateW - 12, 16, dateW, 18)
			local bh = textH(e.Body.Text, 14, w - 80)
			place(e.Body, 64, 44, w - 80, bh)
			local by = 44 + bh + 10
			local bx = 64
			local any = false
			for _, r in ipairs(e.Replays) do
				if r.Button.Instance.Visible then
					any = true
					local bw = math.min(narrow and (w - 80) or 240, math.ceil(textW(r.Button.Caption and r.Button.Caption.Text or "", 13)) + 40)
					bw = math.max(bw, 150)
					if bx + bw > w - 12 then
						bx = 64
						by += 46
					end
					place(r.Button.Instance, bx, by, bw, 40)
					bx += bw + 8
				end
			end
			if any then
				by += 48
			end
			local h = math.max(70, by + 2)
			place(e.Frame, 2, y, w, h)
			y += h + 10
		end
		scroll.CanvasSize = UDim2.fromOffset(0, y + 4)
	end

	function P.Refresh()
		local v = view()
		local unlocked = v.Journal or {}
		local read = v.JournalRead or {}
		local count, unread = 0, 0
		local changed = false
		for _, e in ipairs(P.Entries) do
			local at = unlocked[e.Key]
			local open = at ~= nil
			if open then
				count += 1
			end
			local isNew = open and not read[e.Key] and not st.Read[e.Key]
			if isNew then
				unread += 1
			end
			local before = e.Body.Text .. tostring(e.New.Instance.Visible)
			e.Title.Text = open and upper(L(e.Def.Title)) or "???"
			e.Title.TextColor3 = open and WHITE or MUTED
			e.Body.Text = open and L(e.Def.Text) or UV.JournalHint(e.Key, lang())
			e.Body.TextColor3 = open and SOFT or MUTED
			e.Date.Text = open and dateText(at) or T("LOCKED")
			e.New.Instance.Visible = isNew
			if e.IconH and e.IconH.Set then
				e.IconH:Set(open and e.KindIcon or "Lock", { Size = 44, Glow = open and MOON or nil })
			end
			for _, r in ipairs(e.Replays) do
				r.Button.Instance.Visible = open
			end
			if before ~= e.Body.Text .. tostring(e.New.Instance.Visible) then
				changed = true
			end
		end
		headCount.Text = F("%d / %d", count, #P.Entries)
		P.Ready = unread
		if changed and lastL then
			P.Layout(lastL)
		end
	end

	-- reading the tab marks the new entries read (C2Journal, one at a time: the request budget is shared)
	local marking = false
	function P.Shown()
		if marking or not eligible() then
			return
		end
		marking = true
		task.spawn(function()
			local v = view()
			local unlocked, read = v.Journal or {}, v.JournalRead or {}
			local sent = 0
			for _, e in ipairs(P.Entries) do
				if unlocked[e.Key] ~= nil and not read[e.Key] and not st.Read[e.Key] and sent < 6 then
					st.Read[e.Key] = true
					sent += 1
					task.wait(0.6)
					if not (win and win.IsOpen) then
						st.Read[e.Key] = nil
						break
					end
					local ok = invoke("C2Journal", { Key = e.Key })
					if not ok then
						st.Read[e.Key] = nil
					end
				end
			end
			marking = false
		end)
	end
	return P
end

------------------------------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------------------------------
local TAB_TEXT = { seals = "SEALS", contracts = "CONTRACTS", coffin = "COFFIN", dex = "DEX II", collection = "COLLECTION", journal = "JOURNAL" }
local TAB_ALIAS = { seal = "seals", altar = "seals", altars = "seals", trials = "seals", trial = "seals", contract = "contracts", toll = "contracts",
	tollbox = "contracts", exchange = "contracts", blackcoffin = "coffin", coffins = "coffin", shrine = "coffin", dex2 = "dex", dogs = "dex",
	dogdex = "dex", tailor = "collection", cosmetics = "collection", skins = "collection", finds = "collection", story = "journal" }

local function tabOf(arg: any): string?
	local id = type(arg) == "table" and arg.Tab or arg
	if type(id) ~= "string" then
		return nil
	end
	id = string.lower(id)
	id = TAB_ALIAS[id] or id
	return TAB_TEXT[id] and id or nil
end
S.TabOf = tabOf

local function restyleTabs(tabs: any)
	function tabs._paint(self, instant)
		for id, entry in pairs(self.Buttons) do
			local on = id == self.Selected
			local goal = { BackgroundColor3 = on and VIOLET or TAB_OFF }
			if instant then
				entry.Face.BackgroundColor3 = goal.BackgroundColor3
			else
				Motion.Tween(entry.Face, Theme.Motion.Fast, goal)
			end
			entry.Caption.TextColor3 = on and WHITE or SOFT
			entry.Caption.TextStrokeColor3 = INK
			entry.Caption.TextStrokeTransparency = on and 0.35 or 1
			local stroke = entry.Face:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = on and MOON or PANEL_EDGE
				stroke.Transparency = on and 0 or 0.3
			end
		end
	end
	tabs:_paint(true)
	if tabs.Underline then
		tabs.Underline.BackgroundColor3 = MOON
	end
end

local function headerChip(parent: Instance, name: string, kind: string, color: Color3): any
	local chip = Kit.New("Frame", { Name = name, BorderSizePixel = 0, BackgroundColor3 = C(20, 14, 40), BackgroundTransparency = 0.12, AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = 5 }, parent)
	Kit.Corner(chip, "pill")
	Kit.Stroke(chip, color, 2, 0.1)
	local ic = icon(chip, "Icon", kind, { Size = 32 }, 6)
	local value = txt(chip, { Name = "Value", Text = "0", TextSize = 22, Scaled = true, MinTextSize = 8, Font = "numeric", Color = color, ZIndex = 7, Stroke = 0.4 })
	return { Frame = chip, Icon = ic, Value = value }
end

local function build()
	if ui then
		return ui
	end
	ui = { Lang = Kit.Lang(), Pages = {} }
	local tabs = {}
	for _, id in ipairs(S.Tabs) do
		table.insert(tabs, { Id = id, Text = T(TAB_TEXT[id]), NoTranslate = true })
	end
	win = Kit.Window.new({
		Key = "Underyard", Name = "UnderyardWindow", Title = T("THE UNDERYARD"), Subtitle = T("BENEATH THE LAST BELL"), Accent = VIOLET, Icon = "UnderyardGlyph",
		NoTranslate = true, MaxSize = Vector2.new(1140, 790), Tabs = tabs, Tab = "seals",
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			closeSheet("window")
		end,
		OnTab = function(id)
			st.Tab = id
			closeSheet("tab")
			local p = ui and ui.Pages[id]
			if p and p.Shown then
				p.Shown()
			end
			audio("UiTab")
		end,
	})
	S.Window = win
	-- the Underyard skin of the kit window: violet glass, a violet -> moon-blue header
	gradient(win.Card, BG_TOP, BG_BOTTOM)
	win.Cover.BackgroundColor3 = BG_BOTTOM
	win.CardStroke.Color = INK
	win.HeaderGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C(120, 70, 210)), ColorSequenceKeypoint.new(0.55, C(80, 60, 170)), ColorSequenceKeypoint.new(1, C(70, 130, 200)),
	})
	win.HeaderGradient.Rotation = 0
	local headerStroke = win.Header:FindFirstChildWhichIsA("UIStroke")
	if headerStroke then
		headerStroke.Color = INK
	end
	if win.Icon and win.Icon:IsA("TextLabel") then
		win.Icon.Text = "🔔"
		win.Icon.TextSize = 54
		local limit = win.Icon:FindFirstChildWhichIsA("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = 54
		end
		if UIcons then
			local ok = pcall(UIcons.New, win.Icon, "Seal", { Size = 56, ZIndex = (win.Icon.ZIndex or 4) + 1, Glow = MOON, FrameSize = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
			if ok then
				win.Icon.TextTransparency = 1
			end
		end
	end
	if win.Tabs then
		restyleTabs(win.Tabs)
	end
	-- the balances in the header (left of the close button): Bell Shards, Coffin Keys
	ui.Shards = headerChip(win.Header, "ShardsChip", "Shard", C(214, 176, 255))
	ui.Keys = headerChip(win.Header, "KeysChip", "Key", MOON_HI)
	local function placeChips(Lw)
		local headerH = win.Header.AbsoluteSize.Y > 0 and win.Header.AbsoluteSize.Y or (Lw.Phone and (Lw.Landscape and 50 or 58) or 74)
		local closeSize = Lw.Phone and math.min(44, headerH - 8) or 48
		local portrait = Lw.Phone and not Lw.Landscape
		local sw = portrait and 74 or Lw.Phone and 104 or 132
		local kw = portrait and 58 or Lw.Phone and 84 or 104
		local ch = Lw.Phone and 30 or 40
		local right = closeSize + (headerH - closeSize) / 2 + 10
		ui.Keys.Frame.Size = UDim2.fromOffset(kw, ch)
		ui.Keys.Frame.Position = UDim2.new(1, -right, 0.5, 0)
		ui.Shards.Frame.Size = UDim2.fromOffset(sw, ch)
		ui.Shards.Frame.Position = UDim2.new(1, -(right + kw + 6), 0.5, 0)
		for _, chip in ipairs({ ui.Shards, ui.Keys }) do
			local cw = chip.Frame.Size.X.Offset
			place(chip.Icon, 4, 2, ch - 4, ch - 4)
			place(chip.Value, ch, 2, cw - ch - 10, ch - 4)
		end
		local textX = win.Title.Position.X.Offset
		local titleSpan = -(textX + right + kw + 6 + sw + (portrait and 6 or 12))
		local short = T("UNDERYARD")
		win.Title.Text = portrait and short or T("THE UNDERYARD")
		local limit = win.Title:FindFirstChildWhichIsA("UITextSizeConstraint")
		if limit then
			limit.MinTextSize = portrait and 10 or 14
		end
		if portrait then
			win.Subtitle.Visible = false
			local th = win.Title.Size.Y.Offset
			win.Title.Position = UDim2.fromOffset(textX, math.floor((headerH - th) / 2))
		end
		win.Title.Size = UDim2.new(1, titleSpan, 0, win.Title.Size.Y.Offset)
		win.Subtitle.Size = UDim2.new(1, titleSpan, 0, win.Subtitle.Size.Y.Offset)
	end
	for _, id in ipairs(S.Tabs) do
		local ok, p = pcall(pages[id], win:Page(id))
		if ok then
			ui.Pages[id] = p
		else
			warn("UnderyardScreen: page " .. id .. " failed: " .. tostring(p))
		end
	end
	win.Resized:Connect(function(Lw)
		if (Lw.Width or 0) < 60 then
			return
		end
		closeSheet("resize")
		placeChips(Lw)
		for _, p in pairs(ui.Pages) do
			if p.Layout then
				local ok, err = pcall(p.Layout, Lw)
				if not ok then
					warn("UnderyardScreen layout: " .. tostring(err))
				end
			end
		end
		if win.IsOpen then
			refreshAll()
		end
		task.defer(revealTab)
	end)
	return ui
end

local function badges()
	if not (ui and win) then
		return
	end
	for _, id in ipairs(S.Tabs) do
		local p = ui.Pages[id]
		local n = p and tonumber(p.Ready) or 0
		local text = nil
		if n > 0 then
			text = (id == "coffin" or id == "collection") and "!" or n
		end
		win:SetBadge(id, text)
	end
end

refreshAll = function()
	if not ui then
		return
	end
	ui.Shards.Value.Text = Format.Short(shards(), 1)
	ui.Keys.Value.Text = tostring(keys())
	for id, p in pairs(ui.Pages) do
		if p.Refresh then
			local ok, err = pcall(p.Refresh)
			if not ok then
				warn("UnderyardScreen refresh " .. id .. ": " .. tostring(err))
			end
		end
	end
	badges()
end
S.Refresh = function()
	refreshAll()
end

function S._opened()
	local token = win.Token
	refreshAll()
	local maid = win.OpenMaid
	if Bus then
		maid:Give(Bus.On("StateChanged", function(d)
			if d and type(d.View) == "table" and d.View ~= st.HView then
				setViews(d.View)
				refreshAll()
			end
		end))
		maid:Give(Bus.On("C2Changed", function(d)
			if d and type(d.View) == "table" and d.View ~= st.View then
				st.View = d.View
				refreshAll()
			end
		end))
		maid:Give(Bus.On("C2Signal", function(d)
			if type(d) == "table" and (d.Kind == "C2Phase" or d.Kind == "C2Seal" or d.Kind == "C2Coffin" or d.Kind == "C2Contract") then
				task.defer(refreshAll)
			end
		end))
	end
	for _, a in ipairs({ "BellShards", "CoffinKeys", "LuckyDust", "MoonCandy", "UyInZone", "UyTrial", "UySealMask", "UyTutorial", "HalloweenChapter1Complete" }) do
		maid:Give(player:GetAttributeChangedSignal(a):Connect(function()
			if win.IsOpen then
				refreshAll()
			end
		end))
	end
	-- live timers and proximity: 2 Hz while open
	task.spawn(function()
		while win and win.IsOpen and win.Token == token do
			for _, p in pairs(ui.Pages) do
				if p.Tick then
					pcall(p.Tick)
				end
			end
			ui.Shards.Value.Text = Format.Short(shards(), 1)
			ui.Keys.Value.Text = tostring(keys())
			badges()
			task.wait(0.5)
		end
	end)
	-- a fresh Chapter II view (at most every 20 s: the request budget is shared with the HALLOWEEN window)
	if os.clock() - st.HelloAt > 20 and chapter2Enabled() then
		st.HelloAt = os.clock()
		task.spawn(function()
			local ok, res = invoke("C2Hello", {})
			if ok and type(res) == "table" and win.IsOpen and win.Token == token then
				refreshAll()
			end
		end)
	end
end

-- the DogDex window on the Underyard collection tab
function S.OpenDogDex()
	local mod = script.Parent:FindFirstChild("DogdexScreen")
	local ok, dex = false, nil
	if mod then
		ok, dex = pcall(require, mod)
	end
	if ok and type(dex) == "table" then
		if type(dex.OpenEvent) == "function" and pcall(dex.OpenEvent, Cfg.EventId or "Underyard2026") then
			return
		end
		if type(dex.Open) == "function" then
			pcall(dex.Open)
			return
		end
	end
	local n = nav()
	if n then
		n.OpenPage("DogDex")
	end
end

function revealTab()
	local tabs = win and win.Tabs
	local entry = tabs and tabs.Selected and tabs.Buttons and tabs.Buttons[tabs.Selected]
	local strip = tabs and tabs.Instance
	if not (entry and strip and strip:IsA("ScrollingFrame")) then
		return
	end
	local width = strip.AbsoluteSize.X
	if width < 40 then
		return
	end
	local left = entry.X or entry.Button.Position.X.Offset
	local right = left + (entry.W or entry.Button.Size.X.Offset)
	local x = strip.CanvasPosition.X
	if left < x then
		x = math.max(0, left - 12)
	elseif right > x + width then
		x = right - width + 12
	end
	if x ~= strip.CanvasPosition.X then
		strip.CanvasPosition = Vector2.new(x, 0)
	end
end

function S.Open(arg: any?, _page: any?)
	if not UV then
		Kit.Toast(Kit.T("The Underyard is not ready yet", "Поддворье ещё не готово"), { Kind = "warn", NoTranslate = true })
		return
	end
	if not chapter2Enabled() then
		Kit.Toast(T("Chapter II is closed"), { Kind = "warn", NoTranslate = true })
		return
	end
	if ui and ui.Lang ~= Kit.Lang() and not (win and win.IsOpen) then
		win:Destroy()
		ui, win = nil, nil
	end
	if Bus and st.HView == nil then
		local last = Bus.Last("StateChanged")
		if type(last) == "table" and type(last.View) == "table" then
			setViews(last.View)
		end
	end
	build()
	local tab = tabOf(arg) or st.Tab
	if tab and ui.Pages[tab] then
		win:SetTab(tab, false)
		st.Tab = tab
	end
	if not win.IsOpen then
		win:Open()
	end
	task.defer(revealTab)
	local p = ui.Pages[win.Tab or "seals"]
	if p and p.Shown then
		p.Shown()
	end
	local seal = type(arg) == "table" and tonumber(arg.Seal) or nil
	if seal and ui.Pages.seals then
		task.defer(function()
			if ui and ui.Pages.seals and ui.Pages.seals.Focus then
				ui.Pages.seals.Focus(math.floor(seal))
			end
		end)
	end
	audio("UiOpen")
end

function S.Close()
	if win and win.IsOpen then
		win:Close("close")
	end
end

function S.IsOpen(): boolean
	return win ~= nil and win.IsOpen
end

function S.Pages(): any
	return ui and ui.Pages or {}
end

-- the latest views pushed by HalloweenClient (kept while the window is closed so the first open is instant)
if Bus then
	Bus.On("StateChanged", function(d)
		if d and type(d.View) == "table" then
			setViews(d.View)
		end
	end)
	Bus.On("C2Changed", function(d)
		if d and type(d.View) == "table" then
			st.View = d.View
		end
	end)
end

return S
