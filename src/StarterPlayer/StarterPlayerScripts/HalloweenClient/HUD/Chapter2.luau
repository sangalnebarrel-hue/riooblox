-- CHAPTER II · THE UNDERYARD on the HUD (StarterPlayerScripts.HalloweenClient.HUD.Chapter2, WP-L). Started by
-- HalloweenClient.HUD with its helpers (env); everything here lives in the main ScreenGui.HUD (hides with menus and
-- HIDE UI) or in the HUD's fly layer:
--   * UnderyardObjective  one line under the Halloween strip: the current Bell Seal step / the guide step (UnderyardView
--                         .Objective) in the Underyard, "Descend through the church" in the Dead Yard once Chapter I is
--                         done. Tap: the Underyard window on that seal. Hidden in trials. Publishes ScreenGui attribute
--                         UyObjectiveBottom.
--   * QuickKeys           the Coffin Key pill in the currency bar while you are in the Underyard (U.PillSpecs "CoffinKeys").
--   * C2Announce          server-wide banners (§24.4): HollowKing / Mythic / FinaleClear / Assault (a toast when a menu
--                         hides the banner; your own Hollow King waits for the coffin's secret show).
--   * C2Shards / C2Key    shards / keys that fly into the Bell Shards / Coffin Key pills with a "+N" float.
--   * the UNDERYARD rail tile: built bell-seal art and a badge (UnderyardView.Badges: things to claim or play).
-- Reduced Motion: no flights, no pulses (floats only). Low quality: fewer flying icons.
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local M: any = { Started = false }

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local VIOLET = C(150, 80, 230)
local VIOLET_HI = C(196, 150, 255)
local MOON = C(150, 200, 255)
local GOLD = C(255, 200, 70)
local INK = C(16, 8, 26)
local SOFT = C(226, 218, 252)

function M.Start(H: any, env: any)
	if M.Started then
		return
	end
	local player, gui, hud, U, Kit, Bus, Shared = env.Player, env.Gui, env.Hud, env.U, env.Kit, env.Bus, env.Shared
	local label, new, textStroke, glass, audio = env.Label, env.New, env.TextStroke, env.Glass, env.Audio
	local reduced, low = env.Reduced, env.Low
	local folder = RS:FindFirstChild("Halloween")
	local function module(name: string): any
		local mod = folder and folder:FindFirstChild(name)
		if not mod then
			return nil
		end
		local ok, m = pcall(require, mod)
		return ok and type(m) == "table" and m or nil
	end
	local UV = module("UnderyardView")
	if not UV then
		return
	end
	local UIcons = module("UnderyardIcons") -- registers the Underyard kinds into Icons (Seal, Shard, Key, ...)
	local Layout = module("UnderyardLayout")
	local Cfg = UV.Config
	local function enabled(): boolean
		return Shared ~= nil and Shared.Chapter2Enabled ~= nil and Shared.Chapter2Enabled() == true
	end
	if not enabled() then
		return
	end
	M.Started = true
	local Icons = env.Icons
	local function art(holder: Instance, kind: string, opts: any): any
		if not Icons then
			return nil
		end
		local o = table.clone(opts or {})
		o.ZIndex = o.ZIndex or ((holder :: any).ZIndex + 1)
		local ok, h = pcall(Icons.New, holder, kind, o)
		return ok and h or nil
	end
	local function lang(): string
		return Kit.Lang()
	end
	local function T(en: string): string
		return UV.T(en, lang())
	end
	local function F(en: string, ...: any): string
		return UV.F(en, lang(), ...)
	end
	local function now(): number
		return Kit.Now()
	end

	-- the Chapter II view (Bus "C2Changed" / the Halloween view's Chapter2) and the Halloween view
	local cview: any, hview: any = nil, nil
	do
		local last = Bus.Last("StateChanged")
		if type(last) == "table" and type(last.View) == "table" then
			hview = last.View
			cview = type(last.View.Chapter2) == "table" and last.View.Chapter2 or nil
		end
		local lastC2 = Bus.Last("C2Changed")
		if type(lastC2) == "table" and type(lastC2.View) == "table" then
			cview = lastC2.View
		end
	end
	local function inUnderyard(): boolean
		return player:GetAttribute("UyInZone") == true
	end
	local function inTrial(): boolean
		local t = player:GetAttribute("UyTrial")
		return type(t) == "string" and t ~= ""
	end
	local function eligible(): boolean
		return player:GetAttribute("HalloweenChapter1Complete") == true or (cview ~= nil and cview.Chapter1 ~= nil and cview.Chapter1.Complete == true)
	end
	local function rootPart(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return (r and r:IsA("BasePart")) and r or nil
	end
	local function near(anchor: string): boolean
		local r = rootPart()
		if not (r and Layout) then
			return false
		end
		local part = Layout.AnchorPart and Layout.AnchorPart(anchor)
		local pos = part and part.Position or (Layout.Anchor and Layout.Anchor(anchor))
		local radius = ((Cfg.Proximity and Cfg.Proximity.Radius) or 16) + 2
		return typeof(pos) == "Vector3" and (r.Position - pos).Magnitude <= radius
	end
	local function ctx(): any
		return { Eligible = eligible(), InZone = inUnderyard(), InTrial = inTrial(), Shards = tonumber(player:GetAttribute("BellShards")) or 0,
			Keys = tonumber(player:GetAttribute("CoffinKeys")) or 0, Near = near }
	end
	local function nav(): any
		local modules = gui:FindFirstChild("Modules")
		local mod = modules and modules:FindFirstChild("GUIIntegration")
		if not mod then
			return nil
		end
		local ok, n = pcall(require, mod)
		return ok and n or nil
	end

	------------------------------------------------------------------------------------------------------------------
	-- 1. The objective line
	------------------------------------------------------------------------------------------------------------------
	local line = new("TextButton", { Name = "UnderyardObjective", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0), Visible = false, ZIndex = 20,
		Size = UDim2.fromOffset(420, 52) })
	line:SetAttribute("HUDEdge", "Top")
	line:SetAttribute("NoTranslate", true)
	Kit.Corner(line, 14)
	glass(line, VIOLET_HI, C(58, 34, 112), C(20, 12, 46))
	local lineIcon = new("Frame", { Name = "Icon", BackgroundTransparency = 1, ZIndex = 22 }, line)
	local lineArt = art(lineIcon, "Seal", { Size = 34, ZIndex = 22, Glow = MOON })
	local lineGlyph = label(lineIcon, { Name = "Glyph", Text = lineArt and "" or "🔔", TextSize = 26, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 23 })
	local lineTitle = label(line, { Name = "Title", Text = "", TextSize = 16, Scaled = true, MinTextSize = 8, Color = MOON, ZIndex = 22 })
	textStroke(lineTitle, INK, 1.5)
	local lineText = label(line, { Name = "Line", Text = "", TextSize = 14, Scaled = true, MinTextSize = 7, Color = SOFT, ZIndex = 22 })
	textStroke(lineText, INK, 1.5)
	local lineScale = new("UIScale", { Name = "HwPulse" }, line)
	line.Parent = hud
	M.Line = line
	local lineSeal: number? = nil
	line.Activated:Connect(function()
		local n = nav()
		if n and n.OpenPage then
			n.OpenPage("Underyard", { Tab = "Seals", Seal = lineSeal })
		end
	end)

	local function placeLine()
		local m = U.HUD
		if not (m and m.Layout and m.Layout.Free) then
			return
		end
		local f = m.Layout.Free
		local y = f.Top + 2
		local strip = tonumber(gui:GetAttribute("HwStripBottom"))
		if strip and strip > y then
			y = strip + 6
		end
		local fw = f.Right - f.Left
		local touch = m.Touch
		local w = math.min(touch and 320 or 440, fw - 16)
		local h = touch and 44 or 52
		line.Position = UDim2.fromOffset(math.floor((f.Left + f.Right) / 2), y)
		line.Size = UDim2.fromOffset(w, h)
		local icon = h - 12
		lineIcon.Position = UDim2.fromOffset(8, 6)
		lineIcon.Size = UDim2.fromOffset(icon, icon)
		lineGlyph.Size = UDim2.fromScale(1, 1)
		local tx = 8 + icon + 8
		lineTitle.Position = UDim2.fromOffset(tx, 4)
		lineTitle.Size = UDim2.fromOffset(w - tx - 10, math.floor(h * 0.42))
		lineText.Position = UDim2.fromOffset(tx, 4 + math.floor(h * 0.42))
		lineText.Size = UDim2.fromOffset(w - tx - 10, h - 8 - math.floor(h * 0.42))
		gui:SetAttribute("UyObjectiveBottom", line.Visible and (y + h) or nil)
	end
	local lastKey = ""
	local function updateLine()
		local show = false
		local o = nil
		if enabled() and not inTrial() and cview then
			local c = ctx()
			o = UV.Objective(cview, now(), c)
			if c.InZone then
				show = o.Kind ~= "Chapter1"
			elseif player:GetAttribute("HwInZone") == true then
				-- the Dead Yard: the way down once Chapter I is done
				show = o.Kind == "Descend"
			end
		end
		if show and o then
			local title, text = UV.ObjectiveText(o, lang(), now())
			lineTitle.Text, lineText.Text = title, text
			lineSeal = tonumber(o.Seal)
			local key = tostring(o.Kind) .. ":" .. tostring(o.Seal)
			if key ~= lastKey then
				lastKey = key
				if not reduced() and line.Visible then
					lineScale.Scale = 1.06
					TweenService:Create(lineScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end
			end
		end
		if line.Visible ~= show then
			line.Visible = show
			placeLine()
		end
	end
	for _, a in ipairs({ "HwStripBottom", "HUDFreeTop", "HUDInnerLeft", "HUDInnerRight" }) do
		gui:GetAttributeChangedSignal(a):Connect(function()
			task.defer(placeLine)
		end)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(placeLine)
	end)
	pcall(function()
		Kit.Tooltip(line, function()
			return T("Open the Underyard window"), T("THE UNDERYARD")
		end)
	end)

	------------------------------------------------------------------------------------------------------------------
	-- 2. The Coffin Key pill (in the Underyard)
	------------------------------------------------------------------------------------------------------------------
	local hasKeys = false
	for _, spec in ipairs(U.PillSpecs) do
		if spec.key == "CoffinKeys" then
			hasKeys = true
		end
	end
	if not hasKeys then
		table.insert(U.PillSpecs, (#U.PillSpecs), { key = "CoffinKeys", name = "QuickKeys", units = 2.6, title = "COFFIN KEYS",
			tip = "Open the Black Coffin in Bell Square with one. Never sold." })
	end
	local keysRoot, keysValue, keysIcon = env.Pill("QuickKeys", "🗝️", MOON, C(206, 228, 255))
	local keysArt = art(keysIcon, "Key", { Size = 40, FrameSize = UDim2.fromScale(1.04, 1.04), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5) })
	if keysArt then
		local g = keysIcon:FindFirstChild("Glyph")
		if g then
			g.TextTransparency = 1
		end
	end
	M.KeysPill = keysRoot
	local function keysChanged()
		local n = math.max(0, math.floor(tonumber(player:GetAttribute("CoffinKeys")) or 0))
		keysValue.Text = tostring(n)
		local value = inUnderyard() and math.max(n, 1) or 0
		local had = (keysRoot:GetAttribute("HUDValue") or 0) > 0
		keysRoot:SetAttribute("HUDValue", value)
		if had ~= (value > 0) then
			U.RequestHUDLayout(gui)
		end
	end
	player:GetAttributeChangedSignal("CoffinKeys"):Connect(keysChanged)
	keysChanged()
	pcall(function()
		Kit.Tooltip(keysRoot, function()
			return U.L("Open the Black Coffin in Bell Square with one. Never sold."), U.L("COFFIN KEYS")
		end)
	end)

	------------------------------------------------------------------------------------------------------------------
	-- 3. Server-wide announcements (Signal C2Announce, §24.4)
	------------------------------------------------------------------------------------------------------------------
	local ANNOUNCE = {
		HollowKing = { Title = "THE HOLLOW KING HAS RISEN", Sub = "%s pulled the Hollow King from the Black Coffin", Color = C(255, 120, 255), Icon = { "Seal", { Glow = GOLD } },
			Seconds = 5.5, Cue = "RewardSecret" },
		Mythic = { Title = "A MYTHIC FIND", Sub = "%s pulled %s from the Black Coffin", Color = C(255, 90, 140), Icon = { "Coffin", { Glow = C(255, 90, 140) } },
			Seconds = 4.5, Cue = "RareFind" },
		FinaleClear = { Title = "THE LAST BELL FALLS SILENT", Sub = "%s and the party broke the Gravekeeper's last stand", Color = GOLD, Icon = { "Seal", { Glow = GOLD } },
			Seconds = 5, Cue = "SealComplete" },
		Assault = { Title = "BLACK BELL ASSAULT", Sub = "The Black Bell is ringing: join the assault in the Black Bell Arena", Color = C(255, 80, 90),
			Icon = { "Seal", { Glow = C(255, 80, 90) } }, Seconds = 5, Cue = "BellToll" },
	}
	local function itemName(data: any): string
		if type(data.DogId) == "string" then
			return UV.RowName({ Kind = "Dog", Id = data.DogId }, lang())
		end
		if type(data.Item) == "table" then
			return UV.RowName(data.Item, lang())
		end
		if type(data.ItemId) == "string" then
			for _, kind in ipairs({ "Skin", "Decor", "Find" }) do
				local name = UV.RowName({ Kind = kind, Id = data.ItemId }, lang())
				if name ~= data.ItemId then
					return name
				end
			end
		end
		return ""
	end
	function M.Announce(data: any)
		if type(data) ~= "table" then
			return
		end
		local spec = ANNOUNCE[data.Kind]
		if not spec then
			return
		end
		local who = tostring(data.Name or "")
		local mine = tonumber(data.UserId) == player.UserId
		if who == "" then
			who = mine and player.DisplayName or "?"
		end
		local title = T(spec.Title)
		local sub
		if data.Kind == "Mythic" then
			local what = itemName(data)
			sub = F(spec.Sub, who, what ~= "" and what or T("A MYTHIC FIND"))
		elseif data.Kind == "Assault" then
			sub = T(spec.Sub)
		else
			sub = F(spec.Sub, who)
		end
		local function show()
			local menu = gui:GetAttribute("OpenMenu") ~= nil or gui:GetAttribute("UIHidden") == true
			if menu then
				Kit.Toast(title .. " · " .. sub, { Kind = "info", NoTranslate = true })
				return
			end
			H.Banner({ Title = title, Subtitle = sub, Style = "Underyard", Color = spec.Color, Icon = spec.Icon, Seconds = spec.Seconds, NoTranslate = true })
			audio(spec.Cue)
		end
		if mine and (data.Kind == "HollowKing" or data.Kind == "Mythic") then
			-- the coffin's own reveal (CoffinFX / the Secret arrival) plays first
			task.delay(data.Kind == "HollowKing" and 9 or 5, show)
		else
			show()
		end
	end

	------------------------------------------------------------------------------------------------------------------
	-- 4. Bell Shards / Coffin Keys flying into their pills
	------------------------------------------------------------------------------------------------------------------
	local flyLayer = env.FlyLayer
	local inFlight = 0
	local function centerOf(o: any): Vector2?
		if not (o and o:IsA("GuiObject") and o.Visible and o.AbsoluteSize.X > 2) then
			return nil
		end
		return o.AbsolutePosition - gui.AbsolutePosition + o.AbsoluteSize * Vector2.new(0.17, 0.5)
	end
	local function floatAt(at: Vector2, text: string, color: Color3)
		local l = label(flyLayer, { Name = "UyPlus", Text = text, TextSize = 22, AlignX = "Center", Color = color, Font = "numeric", ZIndex = 62,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(at.X, at.Y), Size = UDim2.fromOffset(110, 26) })
		textStroke(l, INK, 2)
		if reduced() then
			task.delay(1, function()
				l:Destroy()
			end)
			return
		end
		TweenService:Create(l, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(at.X, at.Y + 22), TextTransparency = 1 }):Play()
		task.delay(1.05, function()
			l:Destroy()
		end)
	end
	local function fly(kind: string, amount: number, target: any, color: Color3, cue: string)
		local to = centerOf(target)
		local visible = hud.Visible and gui:GetAttribute("OpenMenu") == nil and not gui:GetAttribute("UIHidden") and to ~= nil
		local text = "+" .. Kit.Format.Short(amount)
		local size = gui.AbsoluteSize
		local below = to and (to + Vector2.new(0, 26)) or Vector2.new(size.X * 0.5, size.Y * 0.18)
		if not visible or reduced() then
			floatAt(below, text, color)
			audio(cue)
			return
		end
		local from = Vector2.new(size.X * 0.5, size.Y * 0.55)
		local count = math.clamp(math.ceil(amount / (kind == "Key" and 1 or 25)), 1, low() and 3 or (kind == "Key" and 3 or 6))
		if inFlight > 16 then
			count = 1
		end
		local landed = 0
		for i = 1, count do
			inFlight += 1
			local f = new("Frame", { Name = "Uy" .. kind, BackgroundTransparency = 1, ZIndex = 61, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(from.X, from.Y), Size = UDim2.fromOffset(34, 34) }, flyLayer)
			if not art(f, kind, { Size = 34, ZIndex = 61 }) then
				label(f, { Name = "Glyph", Text = kind == "Key" and "🗝️" or "🔔", TextSize = 28, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 61,
					Size = UDim2.fromScale(1, 1) })
			end
			f.Rotation = math.random(-25, 25)
			local mid = from + Vector2.new(math.random(-70, 70), math.random(-80, -20))
			task.delay((i - 1) * 0.07, function()
				TweenService:Create(f, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(mid.X, mid.Y) }):Play()
				task.wait(0.24)
				TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(to.X, to.Y),
					Size = UDim2.fromOffset(18, 18), Rotation = f.Rotation + 140 }):Play()
				task.wait(0.45)
				f:Destroy()
				inFlight -= 1
				landed += 1
				audio(kind == "Key" and "Claim" or "CandyTick", { Pitch = 1 + landed * 0.05 })
				U.Pop(target)
				if landed == count then
					floatAt(below, text, color)
				end
			end)
		end
	end
	function M.Shards(data: any)
		local amount = math.floor(tonumber(type(data) == "table" and data.Amount) or 0)
		if amount > 0 then
			fly("Shard", amount, U.ChapterPills and U.ChapterPills.Shards, VIOLET_HI, "CandyBig")
		end
	end
	function M.Keys(data: any)
		local amount = math.floor(tonumber(type(data) == "table" and data.Amount) or 0)
		if amount > 0 then
			local target = keysRoot.Visible and keysRoot or nil
			if not target then
				for _, t in ipairs(U.QuickTiles or {}) do
					if t.key == "Underyard" and t.root.Visible then
						target = t.root
					end
				end
			end
			fly("Key", amount, target, MOON, "Unlock")
		end
	end

	------------------------------------------------------------------------------------------------------------------
	-- 5. The UNDERYARD rail tile: built art + badge
	------------------------------------------------------------------------------------------------------------------
	local function tile(): any
		for _, t in ipairs(U.QuickTiles or {}) do
			if t.key == "Underyard" then
				return t
			end
		end
		return nil
	end
	local function ensureTileArt()
		local t = tile()
		if not (t and t.icon) then
			return
		end
		if Icons and t.icon:IsA("ImageLabel") and t.icon.Image == "" and not t.icon:FindFirstChild("UyTileArt") then
			art(t.icon, "Seal", { Size = 56, Name = "UyTileArt", FrameSize = UDim2.fromScale(1.06, 1.06), Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5), Glow = MOON })
			local old = t.button:FindFirstChild("HwGlyph")
			if old and old:IsA("TextLabel") then
				old.TextTransparency = 1
			end
			local g = t.face and t.face:FindFirstChildWhichIsA("UIGradient")
			if g and not g:GetAttribute("UyNight") then
				g:SetAttribute("UyNight", true)
				g.Color = ColorSequence.new(C(120, 76, 214), C(30, 18, 72))
			end
		end
	end
	local function tileBadge()
		local t = tile()
		if not t then
			return
		end
		if not (cview and eligible()) then
			U.SetTileBadge("Underyard", "")
			return
		end
		local b = UV.Badges(cview, hview, now(), ctx())
		local total = tonumber(b.Total) or 0
		U.SetTileBadge("Underyard", total > 0 and tostring(math.min(total, 99)) or "", VIOLET)
	end
	M.TileBadge = tileBadge

	------------------------------------------------------------------------------------------------------------------
	-- wiring
	------------------------------------------------------------------------------------------------------------------
	Bus.On("C2Changed", function(d)
		if type(d) == "table" and type(d.View) == "table" then
			cview = d.View
			task.defer(updateLine)
			task.defer(tileBadge)
		end
	end)
	Bus.On("StateChanged", function(d)
		if type(d) == "table" and type(d.View) == "table" then
			hview = d.View
			if type(d.View.Chapter2) == "table" then
				cview = d.View.Chapter2
			end
			task.defer(updateLine)
			task.defer(tileBadge)
		end
	end)
	Bus.On("C2Signal", function(sig)
		if type(sig) ~= "table" then
			return
		end
		if sig.Kind == "C2Announce" then
			M.Announce(sig.Data)
		elseif sig.Kind == "C2Shards" then
			M.Shards(sig.Data)
		elseif sig.Kind == "C2Key" then
			M.Keys(sig.Data)
		end
		task.defer(updateLine)
	end)
	for _, a in ipairs({ "UyInZone", "UyTrial", "HwInZone", "HalloweenChapter1Complete", "BellShards", "UyTutorial", "UySealMask" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			task.defer(updateLine)
			if a == "UyInZone" then
				keysChanged()
			end
		end)
	end
	task.spawn(function()
		local last = 0
		while M.Started and gui.Parent do
			pcall(updateLine)
			local t = os.clock()
			if t - last > 2 then
				last = t
				pcall(tileBadge)
				pcall(ensureTileArt)
			end
			task.wait(0.5)
		end
	end)
	task.defer(function()
		placeLine()
		updateLine()
		tileBadge()
		ensureTileArt()
	end)
	local _ = UIcons
end

return M
