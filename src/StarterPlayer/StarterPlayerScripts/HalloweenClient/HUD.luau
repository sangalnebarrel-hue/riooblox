-- NIGHT OF THE BURIED MOON HUD (StarterPlayerScripts.HalloweenClient.HUD). Lives in the game's main ScreenGui.HUD so it
-- hides with menus and slides away with HIDE UI (HUDEdge = "Top"), and is laid out from UITheme's HUD maths (U.HUD):
--   * MoonCandyPill / MoonCursePill in the currency bar (U.PillSpecs, inserted by the UITheme patch; added here when
--     missing): candy counter roll-up + pop, candy icons that fly from the world (Bus "CandyGain") into the counter,
--     a "+N" float, a multiplier corner badge; curse % with a purple -> blood red meter and ghosts at high curse.
--   * HalloweenStrip (top centre of the free zone, under the currency bar / offline notice / DogRush chip): Blood Moon
--     warning "BLOOD MOON RISES IN 30s" / "BLOOD MOON · 2:10", server Candy Rush x2 timer, and the SERVER EXORCISM bar
--     with its milestone badges. HalloweenBossBar under it while THE GRAVEKEEPER fights (merged into the strip on phone
--     landscape). The strip publishes ScreenGui attribute HwStripBottom (its bottom, ScreenGui pixels) for other HUDs.
--   * DOGROTS_HalloweenBanner (own ScreenGui): big banners from Bus "Banner" {Title, Subtitle, Color, Style, Seconds}.
--   * Bus "Toast" -> Kit.Toast (server English is translated by Localization.Halloween), Signal QuestComplete toasts,
--     Signal Milestone banners, Signal Rush end, rail tile badge (claimable quests / "!" during Blood Moon and boss).
--   * Bus "HUDFocus" {Key = "Candy"|"Curse"|"Strip"|"Boss"|"Tile"|nil}: onboarding highlight ring + pointer.
--   * Russian ActionText / ObjectText of the Dead Yard's server prompts (World.Prompt sets attribute HalloweenPrompt).
--   * CHAPTER II (child module HUD.Chapter2, WP-L): the Underyard objective line, the Coffin Key pill, C2Announce banners,
--     Bell Shard / key fly-ins, the UNDERYARD rail tile art + badge.
--   * Studio only: F7 debug panel (Request "Debug" {Cmd}).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local H = {}
H.Pills = {}

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local PUMPKIN = C(255, 128, 24)
local PUMPKIN_HI = C(255, 176, 74)
local PURPLE = C(122, 62, 200)
local PURPLE_HI = C(176, 120, 246)
local NEON = C(120, 255, 110)
local BLOOD = C(200, 30, 50)
local GHOST = C(140, 215, 255)
local GOLD = C(255, 200, 70)
local DEEP = C(40, 16, 60)
local INK = C(16, 8, 26)
local SOFT = C(226, 212, 248)

function H.Start(ctx)
	if H.Started then
		return
	end
	H.Started = true
	local player = ctx.Player or Players.LocalPlayer
	local Shared, Config, Bus, State = ctx.Shared, ctx.Config, ctx.Bus, ctx.State
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("ScreenGui", 60)
	if not gui then
		warn("Halloween HUD: no ScreenGui")
		return
	end
	local modules = gui:WaitForChild("Modules", 30)
	local hud = gui:WaitForChild("HUD", 30)
	local U = require(modules:WaitForChild("UITheme"))
	local Kit = require(modules:WaitForChild("Kit"))
	local Motion = Kit.Motion
	-- built vector icons (RS.Halloween.Icons); nil = the emoji fallback
	local Icons = nil
	do
		local mod = RS:WaitForChild("Halloween"):FindFirstChild("Icons")
		if mod then
			local okI, m = pcall(require, mod)
			Icons = okI and type(m) == "table" and m.New and m or nil
		end
	end
	H.Icons = Icons
	-- an icon filling `holder` (hides the holder's emoji label `glyph` when the icon exists)
	local function iconIn(holder, kind, opts, glyph)
		if not Icons or not holder then
			return nil
		end
		local o = table.clone(opts or {})
		o.ZIndex = o.ZIndex or (holder.ZIndex + 1)
		o.Size = o.Size or 40
		local okN, h = pcall(Icons.New, holder, kind, o)
		if not okN then
			return nil
		end
		if glyph then
			glyph.TextTransparency = 1
			glyph:SetAttribute("HwIconised", true)
		end
		return h
	end
	H.IconIn = iconIn
	local Dict = { UI = {}, Templates = {}, Exact = {}, Patterns = {} }
	do
		local folder = RS:FindFirstChild("Localization")
		local m = folder and folder:FindFirstChild("Halloween")
		local ok, d = false, nil
		if m then
			ok, d = pcall(require, m)
		end
		if ok and type(d) == "table" then
			Dict = d
		end
	end
	local function ru()
		return Kit.Lang() == "ru"
	end
	-- Chapter II labels (Localization.UnderyardUI / .Underyard through UnderyardView) when the Halloween table has none
	local UV = nil
	do
		local mod = RS:WaitForChild("Halloween"):FindFirstChild("UnderyardView")
		if mod then
			local okV, m = pcall(require, mod)
			UV = okV and type(m) == "table" and m or nil
		end
	end
	local function T(en)
		return ru() and (Dict.UI[en] or Dict.Exact[en] or (UV and UV.T(en, "ru"))) or en
	end
	local function F(en, ...)
		local fmt = ru() and Dict.Templates[en] or en
		if type(fmt) == "table" then
			local n = 0
			for i = 1, select("#", ...) do
				local v = select(i, ...)
				if type(v) == "number" then
					n = v
					break
				end
			end
			fmt = Dict.Plural and Dict.Plural(n, fmt[1], fmt[2], fmt[3]) or fmt[3]
		end
		local ok, out = pcall(string.format, fmt, ...)
		return ok and out or en
	end
	local function translate(text)
		if Dict.Translate then
			local out = Dict.Translate(text, Kit.Lang())
			if out then
				return out, true
			end
		end
		return text, not ru()
	end
	H.T, H.F, H.Translate = T, F, translate
	local function reduced()
		return Motion.Reduced() or (Shared and Shared.ReducedMotion())
	end
	local function low()
		return Shared and Shared.Low()
	end
	local function now()
		return Kit.Now()
	end
	local function clock(sec)
		return Kit.Format.Clock(math.max(0, math.ceil(sec)), Kit.Lang())
	end
	local function new(class, props, parent)
		return Kit.New(class, props, parent)
	end
	local function label(parent, props)
		local p = table.clone(props)
		if p.NoTranslate == nil then
			p.NoTranslate = true
		end
		p.Color = p.Color or WHITE
		return Kit.Text(parent, p)
	end
	local function textStroke(l, color, thickness)
		local s = l:FindFirstChild("HwTextStroke") or new("UIStroke", { Name = "HwTextStroke" }, l)
		s.Color = color or INK
		s.Thickness = thickness or 2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.LineJoinMode = Enum.LineJoinMode.Round
		return s
	end
	local function glass(f, rim, top, bottom)
		f.BackgroundColor3 = WHITE
		f.BackgroundTransparency = 0.1
		f.BorderSizePixel = 0
		local g = f:FindFirstChild("HwGlass") or new("UIGradient", { Name = "HwGlass", Rotation = 90 }, f)
		g.Color = ColorSequence.new(top or C(72, 34, 104), bottom or C(30, 12, 46))
		Kit.Stroke(f, rim or PUMPKIN, 2, 0.05)
		return g
	end
	local stateFolder = RS:WaitForChild("Halloween"):WaitForChild("State")
	local function folder(name)
		return stateFolder:FindFirstChild(name)
	end
	local function attrs(name)
		local f = folder(name)
		return f and f:GetAttributes() or {}
	end
	local function inZone()
		local a = player:GetAttribute("HwInZone")
		if a ~= nil then
			return a == true
		end
		return State and State.InZone and State.InZone() or false
	end
	local function view()
		return (State and State.View) or {}
	end
	local function audio(cue, opts)
		local A = ctx.Audio
		if A and A.Play then
			pcall(A.Play, cue, nil, opts)
		end
	end

	-- the screen module registers its Bus listeners (OpenWindow) and the kit route exists even without the patch
	task.spawn(function()
		local okN, N = pcall(require, modules:WaitForChild("GUIIntegration", 10))
		if okN and type(N) == "table" and type(N.KitScreens) == "table" then
			N.KitScreens.Halloween = N.KitScreens.Halloween or "HalloweenScreen"
		end
		local screen = modules:WaitForChild("HalloweenScreen", 10)
		if screen then
			pcall(require, screen)
		end
	end)

	--------------------------------------------------------------------------------------------------------------------
	-- 1. Currency pills (MoonCandyPill / MoonCursePill), laid out by U.LayoutHUD through U.PillSpecs
	--------------------------------------------------------------------------------------------------------------------
	local function hasSpec(key)
		for _, spec in ipairs(U.PillSpecs) do
			if spec.key == key then
				return true
			end
		end
		return false
	end
	if not hasSpec("MoonCandy") then
		table.insert(U.PillSpecs, #U.PillSpecs, { key = "MoonCandy", name = "MoonCandyPill", units = 3, always = true, title = "MOON CANDY" })
	end
	if not hasSpec("MoonCurse") then
		table.insert(U.PillSpecs, #U.PillSpecs, { key = "MoonCurse", name = "MoonCursePill", units = 3.6, title = "CURSE" })
	end
	local function pill(name, glyph, rim, valueColor)
		local old = hud:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local root = new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(138, 46), Visible = false, ZIndex = 10 })
		new("UIScale", { Name = "CandyHUDScale" }, root) -- U.LayoutHUD drives the first UIScale of a pill root
		local face = new("Frame", { Name = "HwPillFace", Size = UDim2.fromScale(1, 1), ZIndex = 10 }, root)
		Kit.Corner(face, "pill")
		glass(face, rim, C(78, 38, 112), C(28, 10, 44))
		local shine = new("Frame", { Name = "Shine", BackgroundColor3 = WHITE, BackgroundTransparency = 0.86, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.new(1, -24, 0.38, 0), ZIndex = 11 }, face)
		Kit.Corner(shine, "pill")
		local iconHolder = new("Frame", { Name = "IconHolder", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(40, 40),
			ZIndex = 13 }, root)
		local icon = label(iconHolder, { Name = "Glyph", Text = glyph, TextSize = 30, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 13 })
		local value = label(root, { Name = "Value", Text = "0", TextSize = 28, Scaled = true, MinTextSize = 10, Color = valueColor, Font = "numeric", ZIndex = 13,
			Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -58, 1, 0) })
		textStroke(value, INK, 2)
		root.Parent = hud
		return root, value, iconHolder, face
	end
	local candyRoot, candyValue, candyIcon = pill("MoonCandyPill", "🍬", PUMPKIN, C(255, 214, 140))
	local curseRoot, curseValue, curseIcon, curseFace = pill("MoonCursePill", "💀", PURPLE_HI, C(232, 196, 255))
	H.Pills.Candy, H.Pills.Curse = candyRoot, curseRoot
	-- the built candy / skull art in the pill sockets (a touch larger than the 40 px socket, like the base coin)
	local candyArt = iconIn(candyIcon, "Candy", { Size = 42, FrameSize = UDim2.fromScale(1.06, 1.06), Position = UDim2.fromScale(.47, .5),
		AnchorPoint = Vector2.new(.5, .5) }, candyIcon:FindFirstChild("Glyph"))
	local curseArt = iconIn(curseIcon, "Skull", { Size = 40, FrameSize = UDim2.fromScale(1.04, 1.04), Position = UDim2.fromScale(.5, .5),
		AnchorPoint = Vector2.new(.5, .5), Glow = C(196, 120, 255) }, curseIcon:FindFirstChild("Glyph"))
	H.Art = { Candy = candyArt, Curse = curseArt }
	-- the curse meter (like the LEVEL pill's slim bar)
	curseValue.Size = UDim2.new(1, -58, 0, 30)
	curseValue.Position = UDim2.fromOffset(48, 1)
	local meter = new("Frame", { Name = "Meter", BackgroundColor3 = C(14, 6, 22), BackgroundTransparency = 0.1, BorderSizePixel = 0, Position = UDim2.fromOffset(48, 31),
		Size = UDim2.new(1, -62, 0, 8), ZIndex = 12 }, curseRoot)
	Kit.Corner(meter, "pill")
	Kit.Stroke(meter, WHITE, 1, 0.65)
	local meterFill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 13 }, meter)
	Kit.Corner(meterFill, "pill")
	local meterGrad = new("UIGradient", { Rotation = 0 }, meterFill)
	-- multiplier corner badge on the candy pill
	local mult = label(candyRoot, { Name = "Mult", Text = "", TextSize = 13, AlignX = "Center", Font = "numeric", ZIndex = 16, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -8), Size = UDim2.fromOffset(40, 18) })
	mult.BackgroundTransparency = 0
	mult.BackgroundColor3 = C(46, 150, 60)
	Kit.Corner(mult, "pill")
	Kit.Stroke(mult, WHITE, 1.5, 0)
	mult.Visible = false

	pcall(function()
		Kit.Tooltip(candyRoot, function()
			local m = tonumber(player:GetAttribute("HwCandyMult")) or 1
			local body = T("Earn it in THE DEAD YARD: perfect hits, ore, haunted dig spots, houses, the boss and quests. Spend it at the cauldron.")
			if math.abs(m - 1) > 0.01 then
				body = body .. "\n" .. F("Right now: x%s candy", string.format("%.2g", m))
			end
			return body, T("MOON CANDY")
		end)
		Kit.Tooltip(curseRoot, function()
			return T("The curse rises while you idle in the Dead Yard. Above 80% you earn less candy. Dig, mine, knock and fight to lift it."), T("CURSE")
		end)
	end)

	-- counter: roll up 0.5 s (Quad out), snap down; candy icons in flight hold the counter until they land
	local shown = new("NumberValue", { Name = "HwCandyShown" }, candyRoot)
	shown.Changed:Connect(function(v)
		candyValue.Text = Kit.Format.Short(math.floor(v + 0.5))
	end)
	local candyTween = nil
	local flying = 0
	local target = tonumber(player:GetAttribute("MoonCandy")) or tonumber(view().Candy) or 0
	local function setCandy(n, pop)
		if candyTween then
			candyTween:Cancel()
			candyTween = nil
		end
		if n <= shown.Value or reduced() then
			shown.Value = n
			candyValue.Text = Kit.Format.Short(math.floor(n + 0.5))
		else
			candyTween = TweenService:Create(shown, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = n })
			candyTween:Play()
		end
		if pop then
			U.Pop(candyIcon)
		end
	end
	shown.Value = target
	candyValue.Text = Kit.Format.Short(target)
	local function candyChanged()
		local n = tonumber(player:GetAttribute("MoonCandy")) or target
		local up = n > target
		target = n
		if flying <= 0 then
			setCandy(n, up)
		end
	end
	player:GetAttributeChangedSignal("MoonCandy"):Connect(candyChanged)

	local function multChanged()
		local m = tonumber(player:GetAttribute("HwCandyMult")) or 1
		mult.Visible = math.abs(m - 1) > 0.01
		mult.Text = "x" .. string.format("%.2g", m)
		mult.BackgroundColor3 = m > 1 and C(46, 150, 60) or BLOOD
		if mult.Visible then
			U.Pop(mult)
		end
	end
	player:GetAttributeChangedSignal("HwCandyMult"):Connect(multChanged)
	multChanged()

	-- curse
	local ghosts = {}
	local lastGhost = 0
	local function curseColor(c)
		return PURPLE_HI:Lerp(BLOOD, math.clamp((c - 40) / 60, 0, 1))
	end
	local function curseChanged()
		local c = math.clamp(tonumber(player:GetAttribute("MoonCurse")) or 0, 0, 100)
		curseValue.Text = math.floor(c + 0.5) .. "%"
		curseValue.TextColor3 = c >= 80 and C(255, 120, 120) or C(232, 196, 255)
		meterFill.Size = UDim2.fromScale(c / 100, 1)
		meterFill.Visible = c > 0.5
		local col = curseColor(c)
		meterGrad.Color = ColorSequence.new(PURPLE_HI, col)
		local stroke = curseFace:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = c >= 70 and C(255, 80, 90) or PURPLE_HI
		end
		curseIcon.Glyph.Text = c >= 70 and "☠️" or "💀"
		if curseArt then
			-- the skull's eyes burn hotter with the curse (4 steps: the art is rebuilt only when the step changes)
			local step = c >= 85 and 3 or c >= 70 and 2 or c >= 40 and 1 or 0
			local eyes = { C(196, 120, 255), C(236, 110, 220), C(255, 80, 90), C(255, 40, 40) }
			curseArt:Set("Skull", { Size = 40, Glow = eyes[step + 1], Color = step >= 2 and C(240, 214, 214) or nil })
		end
		local show = inZone() or c > 0.5
		local value = show and math.max(c, 1) or 0
		local had = (curseRoot:GetAttribute("HUDValue") or 0) > 0
		curseRoot:SetAttribute("HUDValue", value)
		if had ~= (value > 0) then
			U.RequestHUDLayout(gui)
		end
	end
	player:GetAttributeChangedSignal("MoonCurse"):Connect(curseChanged)
	player:GetAttributeChangedSignal("HwInZone"):Connect(curseChanged)
	curseChanged()
	-- ghosts rising from the curse pill at high curse (UI particles; budgeted, off with reduced motion)
	local function spawnGhost()
		if #ghosts >= (low() and 2 or 5) or not curseRoot.Visible or not hud.Visible then
			return
		end
		local g
		local fade = { TextTransparency = 1 }
		if Icons then
			-- a built ghost in a CanvasGroup (the whole drawing fades as one)
			g = new("CanvasGroup", { Name = "Ghost", BackgroundTransparency = 1, ZIndex = 9, GroupTransparency = 0.1,
				Position = UDim2.new(math.random() * 0.7 + 0.1, 0, 0.3, 0), Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0.5, 0.5) }, curseRoot)
			Icons.New(g, "Ghost", { Size = 20, ZIndex = 9, Glow = C(200, 140, 255) })
			fade = { GroupTransparency = 1 }
		else
			g = label(curseRoot, { Name = "Ghost", Text = "👻", TextSize = 18, Scaled = true, MinTextSize = 6, AlignX = "Center", ZIndex = 9,
				Position = UDim2.new(math.random() * 0.7 + 0.1, 0, 0.3, 0), Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5) })
			g.TextTransparency = 0.15
		end
		g.Rotation = math.random(-20, 20)
		table.insert(ghosts, g)
		local t = 1.4 + math.random() * 0.6
		fade.Position = g.Position + UDim2.fromOffset(math.random(-14, 14), 46)
		fade.Rotation = g.Rotation + math.random(-30, 30)
		TweenService:Create(g, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), fade):Play()
		task.delay(t, function()
			local i = table.find(ghosts, g)
			if i then
				table.remove(ghosts, i)
			end
			g:Destroy()
		end)
	end

	--------------------------------------------------------------------------------------------------------------------
	-- 2. The event strip + the boss bar
	--------------------------------------------------------------------------------------------------------------------
	local strip = new("Frame", { Name = "HalloweenStrip", AnchorPoint = Vector2.new(0.5, 0), Visible = false, ZIndex = 20, Size = UDim2.fromOffset(460, 70) })
	strip:SetAttribute("HUDEdge", "Top")
	Kit.Corner(strip, 16)
	glass(strip, PUMPKIN, C(70, 32, 104), C(26, 10, 40))
	local stripPop = new("UIScale", { Name = "HwPulse" }, strip)
	local title = label(strip, { Name = "Title", Text = "", TextSize = 20, Scaled = true, MinTextSize = 10, ZIndex = 22 })
	textStroke(title, INK, 2)
	-- the mode's built icon left of the title (moon / ghost / candy / skull)
	local titleIconHolder = new("Frame", { Name = "TitleIcon", BackgroundTransparency = 1, ZIndex = 22 }, strip)
	local titleIcon = iconIn(titleIconHolder, "Ghost", { Size = 26, ZIndex = 23 })
	titleIconHolder.Visible = titleIcon ~= nil
	local function stripTitle(kind, opts, text, emoji)
		if titleIcon then
			titleIcon:Set(kind, opts or {})
			title.Text = text
		else
			title.Text = emoji .. " " .. text
		end
	end
	local timer = label(strip, { Name = "Timer", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Right", Color = GOLD, Font = "numeric", ZIndex = 22 })
	textStroke(timer, INK, 2)
	local track = new("Frame", { Name = "Track", BackgroundColor3 = C(14, 6, 22), BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 21 }, strip)
	Kit.Corner(track, "pill")
	Kit.Stroke(track, WHITE, 1.5, 0.6)
	local fill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 22 }, track)
	Kit.Corner(fill, "pill")
	local fillGrad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(200, 255, 190), C(60, 200, 80)) }, fill)
	local barText = label(track, { Name = "Text", Text = "", TextSize = 12, Scaled = true, MinTextSize = 7, AlignX = "Center", Font = "numeric", ZIndex = 25 })
	local barTag = label(track, { Name = "Tag", Text = "", TextSize = 12, Scaled = true, MinTextSize = 7, Font = "numeric", ZIndex = 25,
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0.17, -8, 1, 0) })
	textStroke(barTag, INK, 1.5)
	textStroke(barText, INK, 1.5)
	local milestoneBadges = {}
	local milestones = (Config.Exorcism and Config.Exorcism.Milestones) or {}
	local MILESTONE_GLYPH = { CandyRush = "🍬", Block = "🎃", Mutation = "🧬", Boss = "💀" }
	-- the built icon of a milestone kind (strip badges, the milestone burst)
	function H.MilestoneIcon(kind)
		if kind == "CandyRush" then
			return "Candy", {}
		elseif kind == "Block" then
			return "Pumpkin", {}
		elseif kind == "Mutation" then
			return "Potion", { Glow = C(190, 110, 255) }
		elseif kind == "Boss" then
			return "Skull", { Glow = C(255, 70, 80) }
		end
		return "Star", {}
	end
	for i, m in ipairs(milestones) do
		local b = new("Frame", { Name = "Milestone" .. i, AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 23 }, track)
		Kit.Corner(b, "pill")
		Kit.Stroke(b, INK, 1.5, 0)
		local g = new("UIGradient", { Name = "Tone", Rotation = 90 }, b)
		local glyph = label(b, { Name = "Glyph", Text = MILESTONE_GLYPH[m.Kind] or "⭐", TextSize = 14, Scaled = true, MinTextSize = 6, AlignX = "Center", ZIndex = 24,
			Position = UDim2.fromScale(0.15, 0.15), Size = UDim2.fromScale(0.7, 0.7) })
		local kind, opts = H.MilestoneIcon(m.Kind)
		local art = iconIn(b, kind, { Size = 22, ZIndex = 24, FrameSize = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), Glow = opts.Glow, Color = opts.Color, Outline = opts.Outline }, glyph)
		local pop = new("UIScale", { Name = "Pop" }, b)
		milestoneBadges[i] = { Frame = b, Tone = g, Glyph = glyph, Def = m, Art = art, Pop = pop }
	end
	strip.Parent = hud
	pcall(function()
		Kit.Tooltip(strip, function()
			local e = attrs("Exorcism")
			local reached = tonumber(e.Milestone) or 0
			local nextM = milestones[reached + 1]
			local body = T("Every candy and objective in the Dead Yard banishes souls for the whole server.")
			if nextM then
				body = body .. "\n" .. F("Next: %s souls · %s", Kit.Format.Number(nextM.At or 0), T(nextM.Name or ""))
			end
			return body, T("SERVER EXORCISM")
		end)
	end)

	local boss = new("Frame", { Name = "HalloweenBossBar", AnchorPoint = Vector2.new(0.5, 0), Visible = false, ZIndex = 20, Size = UDim2.fromOffset(560, 50) })
	boss:SetAttribute("HUDEdge", "Top")
	Kit.Corner(boss, 14)
	glass(boss, BLOOD, C(96, 22, 40), C(34, 6, 20))
	local bossBadge = new("Frame", { Name = "Numeral", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 22 }, boss)
	Kit.Corner(bossBadge, "pill")
	Kit.Stroke(bossBadge, INK, 2, 0)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(255, 110, 110), C(150, 10, 30)) }, bossBadge)
	local bossNumeral = label(bossBadge, { Name = "Text", Text = "I", TextSize = 20, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 23,
		Position = UDim2.fromScale(0.1, 0.1), Size = UDim2.fromScale(0.8, 0.8) })
	textStroke(bossNumeral, INK, 2)
	local bossName = label(boss, { Name = "Name", Text = T("THE GRAVEKEEPER"), TextSize = 16, Scaled = true, MinTextSize = 8, ZIndex = 22 })
	textStroke(bossName, INK, 2)
	local bossPhase = label(boss, { Name = "Phase", Text = "", TextSize = 12, Scaled = true, MinTextSize = 7, AlignX = "Center", ZIndex = 23 })
	bossPhase.BackgroundTransparency = 0
	bossPhase.BackgroundColor3 = C(30, 10, 20)
	Kit.Corner(bossPhase, "pill")
	local bossTimer = label(boss, { Name = "Timer", Text = "", TextSize = 16, Scaled = true, MinTextSize = 8, AlignX = "Right", Color = GOLD, Font = "numeric", ZIndex = 22 })
	textStroke(bossTimer, INK, 2)
	local armorTrack = new("Frame", { Name = "Armor", BackgroundColor3 = C(14, 4, 10), BorderSizePixel = 0, ZIndex = 21 }, boss)
	Kit.Corner(armorTrack, "pill")
	Kit.Stroke(armorTrack, WHITE, 1.5, 0.6)
	local armorFill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 22 }, armorTrack)
	Kit.Corner(armorFill, "pill")
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(255, 120, 120), C(170, 16, 40)) }, armorFill)
	local armorText = label(armorTrack, { Name = "Text", Text = "", TextSize = 12, Scaled = true, MinTextSize = 7, AlignX = "Center", Font = "numeric", ZIndex = 24 })
	textStroke(armorText, INK, 1.5)
	local shield = label(boss, { Name = "Shield", Text = "🛡️", TextSize = 20, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 24 })
	shield.Visible = false
	-- hit feedback (BossFX publishes BossHit / BossPlateCrack / BossKillingBlow): a pale "damage chunk" trails the armor
	-- down after each hit, heavy hits jolt the bar, weak points / crits flash the fill, big hits float their damage
	local bossPop = new("UIScale", { Name = "HwHitPop" }, boss)
	local armorLag = new("Frame", { Name = "Lag", BackgroundColor3 = C(255, 226, 196), BackgroundTransparency = 0.05, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		ZIndex = 22 }, armorTrack)
	Kit.Corner(armorLag, "pill")
	armorFill.ZIndex = 23
	local armorFlash = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		ZIndex = 23 }, armorFill)
	Kit.Corner(armorFlash, "pill")
	boss.Parent = hud
	local lagShown, lagPending, lagTween = 1, false, nil
	local function setArmor(frac)
		frac = math.clamp(frac, 0, 1)
		armorFill.Size = UDim2.fromScale(frac, 1)
		if frac >= lagShown - 1e-4 or not boss.Visible then
			if lagTween then
				lagTween:Cancel()
				lagTween = nil
			end
			lagShown = frac
			armorLag.Size = UDim2.fromScale(frac, 1)
		elseif not lagPending then
			lagPending = true
			task.delay(0.35, function()
				lagPending = false
				local cur = armorFill.Size.X.Scale
				lagTween = TweenService:Create(armorLag, TweenInfo.new(reduced() and 0 or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromScale(cur, 1) })
				lagTween:Play()
				lagShown = cur
			end)
		end
	end
	local merged = false -- phone landscape: the boss bar folds into the strip (mode "boss")
	local stripMode = ""
	-- the same feedback on the merged strip's bar: a flash layer inside the strip fill
	local stripFlash = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		ZIndex = 23 }, fill)
	Kit.Corner(stripFlash, "pill")
	-- whole-track flashes (the killing blow / death land on an empty fill)
	local function trackFlash(parent)
		local f = new("Frame", { Name = "TrackFlash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
			ZIndex = 23 }, parent)
		Kit.Corner(f, "pill")
		return f
	end
	local armorTrackFlash, stripTrackFlash = trackFlash(armorTrack), trackFlash(track)
	-- which bar shows the boss right now: the separate boss bar, the merged strip, or none
	local function hitTarget()
		if boss.Visible then
			return { Frame = boss, Pop = bossPop, Track = armorTrack, Fill = armorFill, Flash = armorFlash, TrackFlash = armorTrackFlash }
		end
		if strip.Visible and stripMode == "boss" then
			return { Frame = strip, Pop = stripPop, Track = track, Fill = fill, Flash = stripFlash, TrackFlash = stripTrackFlash }
		end
		return nil
	end
	local function flashFill(tg, color, strength, whole)
		local f = whole and tg.TrackFlash or tg.Flash
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1 - strength
		TweenService:Create(f, TweenInfo.new(whole and 0.6 or 0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	end
	local function jolt(tg, power)
		if reduced() then
			return
		end
		tg.Frame.Rotation = (math.random() < 0.5 and -1 or 1) * 1.8 * power
		TweenService:Create(tg.Frame, TweenInfo.new(0.3, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		tg.Pop.Scale = 1 + 0.045 * power
		TweenService:Create(tg.Pop, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	local lastFloat = 0
	local function floatDamage(tg, n, color)
		if reduced() or os.clock() - lastFloat < 0.12 or not tg.Track.Parent then
			return
		end
		lastFloat = os.clock()
		local origin = gui.AbsolutePosition
		local x = tg.Track.AbsolutePosition.X - origin.X + tg.Track.AbsoluteSize.X * tg.Fill.Size.X.Scale
		local y = tg.Track.AbsolutePosition.Y - origin.Y
		local l = label(hud, { Name = "HwBossDamage", Text = "-" .. Kit.Format.Short(math.floor(n), 1), TextSize = 18, AlignX = "Center", Color = color, Font = "numeric",
			ZIndex = 30, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(80, 22) })
		textStroke(l, INK, 2)
		TweenService:Create(l, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(x + math.random(-10, 10), y - 26),
			TextTransparency = 1 }):Play()
		task.delay(0.75, function()
			l:Destroy()
		end)
	end
	Bus.On("BossHit", function(d)
		local tg = hitTarget()
		if type(d) ~= "table" or not tg then
			return
		end
		if d.Weak then
			flashFill(tg, C(255, 214, 90), 0.85)
		elseif d.Crit then
			flashFill(tg, WHITE, 0.7)
		else
			flashFill(tg, WHITE, 0.35)
		end
		if d.Heavy then
			jolt(tg, d.Weak and 1.3 or 1)
		end
		if (tonumber(d.Damage) or 0) > 0 and (d.Heavy or (tonumber(d.Share) or 0) >= 0.005) then
			floatDamage(tg, tonumber(d.Damage), d.Weak and C(255, 220, 100) or d.Crit and WHITE or C(255, 150, 150))
		end
	end)
	Bus.On("BossPlateCrack", function()
		local tg = hitTarget()
		if tg then
			flashFill(tg, C(255, 170, 80), 0.6)
			jolt(tg, 0.6)
		end
	end)
	-- the killing blow and the death's first beat land while the bar is held after Defeated (see H.BossHoldUntil)
	Bus.On("BossKillingBlow", function(d)
		local tg = hitTarget()
		if tg then
			flashFill(tg, WHITE, 0.9, true)
			jolt(tg, type(d) == "table" and d.Mine and 2 or 1.4)
		end
	end)
	Bus.On("BossDeath", function(d)
		-- the emptied bar flares gold and the damage chunk drains at once
		local tg = hitTarget()
		if tg and type(d) == "table" and d.Stage == "Stagger" then
			if tg.Frame == boss then
				setArmor(0)
			end
			flashFill(tg, GOLD, 0.95, true)
			jolt(tg, 1.2)
		end
	end)
	local function bossActive(b)
		local s = tostring(b.State or "Idle")
		if s == "" or s == "Idle" or s == "Defeated" or s == "Escaped" or s == "Cooldown" or s == "Ended" then
			return false
		end
		return (tonumber(b.MaxArmor) or 0) > 0
	end
	H.BossActive = bossActive

	-- rectangles inside the strip / bar for the current size
	local function layoutStrip(w, h, touch)
		local pad = touch and 10 or 14
		local rowH = touch and 22 or 26
		local tw = math.floor((w - pad * 2) * (merged and 0.62 or 0.64))
		local iw = titleIcon and (rowH + 2) or 0
		titleIconHolder.Position, titleIconHolder.Size = UDim2.fromOffset(pad - 2, (touch and 5 or 7) - 1), UDim2.fromOffset(rowH + 2, rowH + 2)
		title.Position, title.Size = UDim2.fromOffset(pad + iw + 2, touch and 5 or 7), UDim2.fromOffset(tw - iw - 2, rowH)
		timer.Position, timer.Size = UDim2.fromOffset(pad + tw + 4, touch and 5 or 7), UDim2.fromOffset(w - pad * 2 - tw - 4, rowH)
		local barH = touch and 16 or 20
		track.Position = UDim2.fromOffset(pad + 4, h - barH - (touch and 8 or 11))
		track.Size = UDim2.fromOffset(w - pad * 2 - 8, barH)
		local bs = barH + (touch and 6 or 8)
		for _, m in ipairs(milestoneBadges) do
			local goal = (Config.Exorcism and Config.Exorcism.Goal) or 5000
			local f = math.clamp((m.Def.At or 0) / goal, 0, 1)
			m.Frame.Size = UDim2.fromOffset(bs, bs)
			m.Frame.Position = UDim2.new(f, f >= 0.999 and -bs / 2 + 2 or 0, 0.5, 0)
		end
	end
	local function layoutBoss(w, h, touch)
		local s = h - 10
		bossBadge.Position, bossBadge.Size = UDim2.fromOffset(6, 5), UDim2.fromOffset(s, s)
		local x = s + 14
		local topH = touch and 14 or 18
		-- top row: name · phase chip · timer, right to left; a narrow bar (phone portrait) drops the name, the numeral says who
		local timerW = touch and 48 or 60
		local tx = w - timerW - 10
		local phaseW = math.min(math.floor((w - x) * 0.32), 120)
		local px = tx - 6 - phaseW
		local nameW = px - 6 - x
		bossName.Visible = nameW >= 96
		if not bossName.Visible then
			px, phaseW = x, tx - 6 - x
		end
		bossName.Position, bossName.Size = UDim2.fromOffset(x, 4), UDim2.fromOffset(math.max(0, nameW), topH)
		bossPhase.Position, bossPhase.Size = UDim2.fromOffset(px, 4), UDim2.fromOffset(phaseW, topH)
		bossTimer.Position, bossTimer.Size = UDim2.fromOffset(tx, 4), UDim2.fromOffset(timerW, topH)
		armorTrack.Position = UDim2.fromOffset(x, topH + 9)
		armorTrack.Size = UDim2.fromOffset(w - x - 12, h - topH - 15)
		shield.Position, shield.Size = UDim2.fromOffset(w - 36, topH + 5), UDim2.fromOffset(h - topH - 8, h - topH - 8)
	end

	local function placeAll()
		local m = U.HUD
		if not m or not m.Layout then
			return
		end
		local f = m.Layout.Free
		local origin = gui.AbsolutePosition
		local y = f.Top + 2
		local notice = hud:FindFirstChild("OfflineEarningsNotice")
		if notice and notice:IsA("GuiObject") and notice.Visible then
			y = math.max(y, notice.AbsolutePosition.Y - origin.Y + notice.AbsoluteSize.Y + 6)
		end
		local rush = playerGui:FindFirstChild("DOGROTS_DogRushHUD")
		local chip = rush and rush.Enabled and rush:FindFirstChild("PupChip")
		if chip and chip:IsA("GuiObject") and chip.Visible then
			y = math.max(y, chip.AbsolutePosition.Y - origin.Y + chip.AbsoluteSize.Y + 6)
		end
		local cx = math.floor((f.Left + f.Right) / 2)
		local fw = f.Right - f.Left
		local touch = m.Touch
		merged = (m.Height or 1000) < 420
		local w = math.min(touch and 320 or 470, fw - 16)
		local h = touch and 58 or 72
		strip.Position, strip.Size = UDim2.fromOffset(cx, y), UDim2.fromOffset(w, h)
		layoutStrip(w, h, touch)
		local bottom = y + (strip.Visible and h or 0)
		local bw = math.min(touch and 340 or 560, fw - 16)
		local bh = touch and 40 or 50
		boss.Position, boss.Size = UDim2.fromOffset(cx, bottom + (strip.Visible and 6 or 0)), UDim2.fromOffset(bw, bh)
		layoutBoss(bw, bh, touch)
		if boss.Visible then
			bottom = bottom + 6 + bh
		end
		gui:SetAttribute("HwStripBottom", bottom)
	end
	H.Place = placeAll
	for _, a in ipairs({ "HUDFreeTop", "HUDInnerLeft", "HUDInnerRight", "HUDIncomeSlot" }) do
		gui:GetAttributeChangedSignal(a):Connect(function()
			task.defer(placeAll)
		end)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(placeAll)
	end)
	task.spawn(function()
		local notice = hud:WaitForChild("OfflineEarningsNotice", 20)
		if notice then
			notice:GetPropertyChangedSignal("Visible"):Connect(placeAll)
		end
	end)

	-- what the strip shows now
	local pulse = nil
	local function setPulse(on)
		if on and not pulse and not reduced() then
			pulse = TweenService:Create(stripPop, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.035 })
			pulse:Play()
		elseif not on and pulse then
			pulse:Cancel()
			pulse = nil
			stripPop.Scale = 1
		end
	end
	local function setBar(value, colorTop, colorBottom)
		fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
		fill.Visible = value > 0.002
		fillGrad.Color = ColorSequence.new(colorTop, colorBottom)
	end
	local bossWasOn = false
	local function updateStrip()
		local t = now()
		local moon = Shared and Shared.BloodMoonState(t) or { State = "NORMAL" }
		local serverRush = tonumber(stateFolder:GetAttribute("ServerRushUntil")) or 0
		local b = attrs("Boss")
		-- the difficulty V finale (BossFinale) keeps the fight at 0 armor: FinaleFX's own panel replaces the Gravekeeper bar
		local finale = tostring(b.Mode or "") == "Finale" or tostring(attrs("Finale").State or "") ~= ""
		local fighting = bossActive(b) and not finale
		-- Defeated: the emptied bar holds ~3 s so the killing blow and the death's first beat land on it
		if fighting then
			bossWasOn = true
		elseif bossWasOn then
			bossWasOn = false
			if tostring(b.State) == "Defeated" then
				H.BossHoldUntil = os.clock() + 3.2
			end
		end
		local held = not fighting and os.clock() < (H.BossHoldUntil or 0)
		fighting = fighting or held
		local zone = inZone()
		local e = attrs("Exorcism")
		local goal = tonumber(e.Goal) or (Config.Exorcism and Config.Exorcism.Goal) or 5000
		local souls = tonumber(e.Souls) or 0
		local reached = tonumber(e.Milestone) or 0
		local mode
		if merged and fighting and zone then
			mode = "boss"
		elseif moon.State == "WARNING" then
			mode = "warning"
		elseif moon.State == "ACTIVE" then
			mode = "moon"
		elseif moon.State == "ENDING" and zone then
			mode = "fade"
		elseif serverRush > t then
			mode = "rush"
		elseif zone or os.clock() < (H.ExorcismShowUntil or 0) then
			mode = "exorcism" -- in the zone, or everywhere for a few seconds after a server milestone
		else
			mode = "none"
		end
		local show = mode ~= "none" and mode ~= "fade" or (mode == "fade" and zone)
		show = show and (zone or mode == "warning" or mode == "moon" or mode == "rush" or (mode == "exorcism" and os.clock() < (H.ExorcismShowUntil or 0)))
		local stroke = strip:FindFirstChildWhichIsA("UIStroke")
		if mode == "warning" then
			local left = math.max(0, math.ceil((moon.StartTimestamp or t) - t))
			stripTitle("Moon", { State = "Blood" }, T("BLOOD MOON RISES IN"), "🌕")
			timer.Text = left < 60 and F("%ds", left) or clock(left)
			timer.TextColor3 = C(255, 110, 110)
			if stroke then
				stroke.Color = BLOOD
			end
		elseif mode == "moon" then
			local narrow = strip.AbsoluteSize.X > 0 and strip.AbsoluteSize.X < 380
			stripTitle("Moon", { State = "Blood" }, T("BLOOD MOON") .. (narrow and "" or (" · " .. T("+50% CANDY"))), "🩸")
			timer.Text = clock((moon.ActiveEndTimestamp or t) - t)
			timer.TextColor3 = C(255, 110, 110)
			if stroke then
				stroke.Color = BLOOD
			end
		elseif mode == "fade" then
			stripTitle("Moon", { State = "Fading" }, T("THE BLOOD MOON FADES"), "🌘")
			timer.Text = ""
		elseif mode == "rush" then
			stripTitle("Candy", nil, T("SERVER CANDY RUSH x2"), "🍬")
			timer.Text = clock(serverRush - t)
			timer.TextColor3 = GOLD
			if stroke then
				stroke.Color = PUMPKIN
			end
		elseif mode == "boss" then
			local d = (Config.Boss and Config.Boss.Difficulties or {})[tonumber(b.Difficulty) or 1] or {}
			stripTitle("Skull", { Glow = C(255, 70, 80) }, (d.Numeral or "") .. " · " .. (held and T("DEFEATED") or tostring(H.PhaseName(b))), "💀")
			local ends = tonumber(b.EndsAt) or 0
			timer.Text = (ends > t and not held) and clock(ends - t) or ""
			timer.TextColor3 = C(255, 110, 110)
			if stroke then
				stroke.Color = BLOOD
			end
		else
			stripTitle("Ghost", { Glow = NEON }, T("SERVER EXORCISM"), "👻")
			timer.Text = Kit.Format.Number(souls) .. " / " .. Kit.Format.Number(goal)
			timer.TextColor3 = GHOST
			if stroke then
				stroke.Color = PUMPKIN
			end
		end
		if stroke and os.clock() < (H.StripFlashUntil or 0) then
			stroke.Color = H.StripFlashColor or NEON -- a milestone flash holds the rim colour
		end
		setPulse(mode == "warning")
		if mode == "boss" then
			barTag.Text = ""
			local max = math.max(1, tonumber(b.MaxArmor) or 1)
			local armor = held and 0 or (tonumber(b.Armor) or 0)
			setBar(armor / max, C(255, 120, 120), C(170, 16, 40))
			barText.Text = Kit.Format.Short(math.floor(armor), 1) .. " / " .. Kit.Format.Short(math.floor(max), 1)
		else
			setBar(souls / math.max(1, goal), C(200, 255, 190), C(60, 200, 80))
			barText.Text = ""
			barTag.Text = (mode ~= "exorcism" and track.AbsoluteSize.X > 280) and ("👻 " .. math.floor(souls / math.max(1, goal) * 100) .. "%") or ""
		end
		for i, m in ipairs(milestoneBadges) do
			m.Frame.Visible = mode ~= "boss"
			local done = i <= reached
			local nextOne = i == reached + 1
			local top = done and NEON or nextOne and PUMPKIN or C(110, 80, 150)
			local bottom = done and C(40, 140, 60) or nextOne and C(190, 80, 10) or C(50, 26, 80)
			m.Tone.Color = ColorSequence.new(top:Lerp(WHITE, 0.25), bottom)
			m.Glyph.Text = done and "✓" or (MILESTONE_GLYPH[m.Def.Kind] or "⭐")
			if m.Art then
				local kind, opts = H.MilestoneIcon(m.Def.Kind)
				if done then
					m.Art:Set("Check", {})
				else
					m.Art:Set(kind, { Glow = opts.Glow, Color = opts.Color, Dim = (not nextOne) and 0.35 or nil })
				end
			end
		end
		-- the boss bar (separate unless merged)
		local bossShow = fighting and zone and not merged
		if bossShow then
			local d = (Config.Boss and Config.Boss.Difficulties or {})[tonumber(b.Difficulty) or 1] or {}
			bossNumeral.Text = d.Numeral or "?"
			bossPhase.Text = held and T("DEFEATED") or H.PhaseName(b)
			local max = math.max(1, tonumber(b.MaxArmor) or 1)
			local a = held and 0 or math.clamp(tonumber(b.Armor) or 0, 0, max)
			setArmor(a / max)
			armorText.Text = T("ARMOR") .. " " .. Kit.Format.Short(math.floor(a), 1) .. " / " .. Kit.Format.Short(math.floor(max), 1)
			local ends = tonumber(b.EndsAt) or 0
			bossTimer.Text = (ends > t and not held) and clock(ends - t) or ""
			local shielded = not held and (b.Shield == true or (tonumber(b.Shield) or 0) > 0)
			shield.Visible = shielded
			armorFill.BackgroundTransparency = shielded and 0.4 or 0
			-- what to do right now: smash the skeleton pack while the shield is up, hit the weak point while it is open
			local weakLeft = held and 0 or (tonumber(b.WeakOpenUntil) or 0) - t
			if shielded and (tonumber(b.ShieldNeed) or 0) > 0 then
				armorText.Text = T("SHIELD · SMASH THE SKELETONS") .. " " .. tostring(math.max(0, tonumber(b.ShieldLeft) or 0))
			elseif weakLeft > 0 then
				armorText.Text = T("WEAK POINT OPEN!") .. " " .. clock(weakLeft)
				armorFill.BackgroundTransparency = (math.floor(t * 4) % 2 == 0) and 0 or 0.35
			end
		end
		local changed = (strip.Visible ~= show) or (boss.Visible ~= bossShow) or (stripMode ~= mode)
		strip.Visible = show
		boss.Visible = bossShow
		stripMode = mode
		if changed then
			placeAll()
		end
	end
	H.PhaseName = function(b)
		local name = b.PhaseName
		if type(name) ~= "string" or name == "" then
			local phase = tonumber(b.Phase) or 0
			for _, p in ipairs((Config.Boss and Config.Boss.Phases) or {}) do
				if p.Id == phase then
					name = p.Name
				end
			end
		end
		return T(name or "")
	end
	H.UpdateStrip = updateStrip

	--------------------------------------------------------------------------------------------------------------------
	-- 3. Rail tile: badge + glyph fallback
	--------------------------------------------------------------------------------------------------------------------
	local function tile()
		for _, t in ipairs(U.QuickTiles or {}) do
			if t.key == "Halloween" then
				return t
			end
		end
		return nil
	end
	local function ensureGlyph()
		local t = tile()
		if not t or not t.icon then
			return
		end
		if Icons and t.icon:IsA("ImageLabel") and t.icon.Image == "" then
			-- the built jack-o'-lantern inside the tile's icon slot (it rides the tile's hover / press motion)
			if not t.icon:FindFirstChild("HwTileArt") then
				iconIn(t.icon, "Pumpkin", { Size = 56, Name = "HwTileArt", FrameSize = UDim2.fromScale(1.06, 1.06), Position = UDim2.fromScale(.5, .5),
					AnchorPoint = Vector2.new(.5, .5) })
			end
			local old = t.button:FindFirstChild("HwGlyph")
			if old and old:IsA("TextLabel") and old.TextTransparency < 1 then
				old.TextTransparency = 1
			end
			-- a night-purple face: the orange jack-o'-lantern reads on it (an orange face swallowed it)
			local g = t.face and t.face:FindFirstChildWhichIsA("UIGradient")
			if g and not g:GetAttribute("HwNight") then
				g:SetAttribute("HwNight", true)
				g.Color = ColorSequence.new(C(150, 84, 214), C(58, 22, 92))
			end
			return
		end
		if t.icon:IsA("ImageLabel") and t.icon.Image == "" and not t.button:FindFirstChild("HwGlyph") then
			local g = label(t.button, { Name = "HwGlyph", Text = "🎃", TextSize = 60, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 15,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.72, 0.72) })
			g:SetAttribute("NoTranslate", true)
		end
	end
	local function tileBadge()
		local t = now()
		local moon = Shared and Shared.BloodMoonState(t) or { State = "NORMAL" }
		local v = view()
		local ready = 0
		for _, q in ipairs(v.Quests and v.Quests.List or {}) do
			if not q.Claimed and (q.Progress or 0) >= (q.Goal or 1) then
				ready += 1
			end
		end
		if bossActive(attrs("Boss")) or moon.State == "ACTIVE" or moon.State == "WARNING" then
			U.SetTileBadge("Halloween", "!", U.Colors.red)
		elseif ready > 0 then
			U.SetTileBadge("Halloween", tostring(ready), C(214, 110, 18))
		else
			U.SetTileBadge("Halloween", "")
		end
	end
	H.TileBadge = tileBadge

	--------------------------------------------------------------------------------------------------------------------
	-- 4. Big banners (own ScreenGui at 30 % height; never over menus / HIDE UI / the DogRush banner)
	--------------------------------------------------------------------------------------------------------------------
	local STYLE = {
		BloodMoon = { Color = C(235, 40, 60), Glyph = "🌕", Band = C(60, 0, 12) },
		Boss = { Color = C(255, 70, 70), Glyph = "💀", Band = C(40, 0, 10) },
		Exorcism = { Color = C(120, 255, 140), Glyph = "👻", Band = C(10, 40, 30) },
		Rush = { Color = C(255, 170, 40), Glyph = "🍬", Band = C(60, 24, 0) },
		Event = { Color = C(255, 140, 40), Glyph = "🎃", Band = C(40, 14, 60) },
		Underyard = { Color = C(190, 140, 255), Glyph = "🔔", Band = C(24, 10, 52) }, -- Chapter II announcements (WP-L)
	}
	local STYLE_ICON = {
		BloodMoon = { "Moon", { State = "Blood" } }, Boss = { "Skull", { Glow = C(255, 70, 80) } }, Exorcism = { "Ghost", { Glow = NEON } },
		Rush = { "Candy", {} }, Event = { "Pumpkin", {} }, Underyard = { "Seal", { Glow = C(150, 200, 255) } },
	}
	local banner = nil
	local function buildBanner()
		if banner then
			return banner
		end
		local layer = new("ScreenGui", { Name = "DOGROTS_HalloweenBanner", ResetOnSpawn = false, DisplayOrder = 41, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
		pcall(function()
			layer.IgnoreGuiInset = true
			layer.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		end)
		layer:SetAttribute("HideWithUI", true)
		layer:SetAttribute("NoTranslate", true)
		local f = new("Frame", { Name = "Banner", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
			Size = UDim2.new(0.92, 0, 0, 170), Visible = false }, layer)
		local pop = new("UIScale", { Name = "Pop" }, f)
		local band = new("Frame", { Name = "Band", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.new(1.1, 0, 0.82, 0),
			BackgroundColor3 = C(30, 0, 10), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 1 }, f)
		new("UIGradient", { Name = "Fade", Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.22, 0.25),
			NumberSequenceKeypoint.new(0.78, 0.25), NumberSequenceKeypoint.new(1, 1) }) }, band)
		local line1 = new("Frame", { Name = "LineTop", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.07), Size = UDim2.new(0.62, 0, 0, 3),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2 }, f)
		local line2 = line1:Clone()
		line2.Name = "LineBottom"
		line2.Position = UDim2.fromScale(0.5, 0.88)
		line2.Parent = f
		for _, l in ipairs({ line1, line2 }) do
			new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, l)
		end
		local titleL = label(f, { Name = "Title", Text = "", TextSize = 84, Scaled = true, MinTextSize = 22, AlignX = "Center", ZIndex = 4,
			Position = UDim2.new(0.12, 0, 0, 18), Size = UDim2.new(0.76, 0, 0, 92) }) -- clear of the two glyphs
		local ts = textStroke(titleL, C(30, 4, 14), 5)
		local tg = new("UIGradient", { Rotation = 90 }, titleL)
		local sub = label(f, { Name = "Subtitle", Text = "", TextSize = 28, Scaled = true, MinTextSize = 12, AlignX = "Center", ZIndex = 4,
			Position = UDim2.new(0.1, 0, 0, 112), Size = UDim2.new(0.8, 0, 0, 34) })
		textStroke(sub, C(20, 4, 14), 3)
		local left = label(f, { Name = "GlyphL", Text = "", TextSize = 64, Scaled = true, MinTextSize = 10, AlignX = "Center", ZIndex = 4, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.05, 0.4), Size = UDim2.fromOffset(72, 72) })
		local right = left:Clone()
		right.Name = "GlyphR"
		right.Position = UDim2.fromScale(0.95, 0.4)
		right.Parent = f
		layer.Parent = playerGui
		-- built art in the two glyph slots (the labels keep turning: the art turns with them)
		local leftArt = iconIn(left, "Pumpkin", { Size = 72, ZIndex = 5 })
		local rightArt = iconIn(right, "Pumpkin", { Size = 72, ZIndex = 5 })
		banner = { Layer = layer, Frame = f, Pop = pop, Band = band, Title = titleL, TitleStroke = ts, Grad = tg, Sub = sub, Left = left, Right = right, Lines = { line1, line2 },
			LeftArt = leftArt, RightArt = rightArt,
			Serial = 0 }
		gui:GetAttributeChangedSignal("OpenMenu"):Connect(function()
			if gui:GetAttribute("OpenMenu") ~= nil then
				f.Visible = false
			end
		end)
		gui:GetAttributeChangedSignal("UIHidden"):Connect(function()
			if gui:GetAttribute("UIHidden") then
				f.Visible = false
			end
		end)
		return banner
	end
	function H.Banner(data)
		if type(data) ~= "table" then
			return
		end
		if gui:GetAttribute("OpenMenu") ~= nil or gui:GetAttribute("UIHidden") then
			return
		end
		local rushHud = playerGui:FindFirstChild("DOGROTS_DogRushHUD")
		local rushBanner = rushHud and rushHud:FindFirstChild("Banner")
		if rushBanner and rushBanner:IsA("GuiObject") and rushBanner.Visible then
			return
		end
		local b = buildBanner()
		local style = STYLE[data.Style or "Event"] or STYLE.Event
		local color = typeof(data.Color) == "Color3" and data.Color or style.Color
		b.Serial += 1
		local serial = b.Serial
		local titleText, own = translate(tostring(data.Title or ""))
		local subText, ownSub = translate(tostring(data.Subtitle or ""))
		if data.NoTranslate then
			own, ownSub = true, true
		end
		b.Title:SetAttribute("NoTranslate", own)
		b.Sub:SetAttribute("NoTranslate", ownSub)
		b.Title.Text = titleText
		b.Sub.Text = subText
		b.Sub.Visible = subText ~= ""
		b.Grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.55)), ColorSequenceKeypoint.new(0.55, color:Lerp(WHITE, 0.1)),
			ColorSequenceKeypoint.new(1, color) })
		b.TitleStroke.Color = (style.Band or C(30, 0, 10)):Lerp(INK, 0.4)
		b.Band.BackgroundColor3 = style.Band or C(30, 0, 10)
		for _, l in ipairs(b.Lines) do
			l.BackgroundColor3 = color:Lerp(WHITE, 0.3)
		end
		local glyph = data.Glyph or style.Glyph
		b.Left.Text, b.Right.Text = glyph, glyph
		-- data.Icon = {kind, opts}: a built icon of its own (Chapter II announcements)
		local art = b.LeftArt and ((type(data.Icon) == "table" and data.Icon) or ((not data.Glyph) and STYLE_ICON[data.Style or "Event"])) or nil
		for _, h in ipairs({ b.LeftArt, b.RightArt }) do
			if h then
				h.Instance.Visible = art ~= nil
				if art then
					h:Set(art[1], art[2])
				end
			end
		end
		if art then
			b.Left.Text, b.Right.Text = "", ""
		end
		b.Frame.Visible = true
		b.Title.TextTransparency, b.Sub.TextTransparency = 0, 0
		if reduced() then
			b.Pop.Scale = 1
		else
			b.Pop.Scale = 0.45
			TweenService:Create(b.Pop, TweenInfo.new(0.42, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			b.Left.Rotation, b.Right.Rotation = -30, 30
			TweenService:Create(b.Left, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Rotation = -12 }):Play()
			TweenService:Create(b.Right, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Rotation = 12 }):Play()
		end
		Kit.Sound.Play("Notify", { Pitch = 0.8 })
		local seconds = tonumber(data.Seconds) or 3.5
		task.delay(seconds, function()
			if b.Serial ~= serial then
				return
			end
			if reduced() then
				b.Frame.Visible = false
				return
			end
			TweenService:Create(b.Pop, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
			TweenService:Create(b.Title, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			TweenService:Create(b.Sub, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			task.delay(0.26, function()
				if b.Serial == serial then
					b.Frame.Visible = false
				end
			end)
		end)
	end
	Bus.On("Banner", H.Banner)

	--------------------------------------------------------------------------------------------------------------------
	-- 5. Candy icons that fly from the world into the counter (Bus "CandyGain" {Amount, From, Source, Big})
	--------------------------------------------------------------------------------------------------------------------
	local flyLayer = new("Frame", { Name = "HalloweenFly", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60 }, gui)
	flyLayer:SetAttribute("NoTranslate", true)
	local function pillCenter()
		local origin = gui.AbsolutePosition
		return candyRoot.AbsolutePosition - origin + candyRoot.AbsoluteSize * Vector2.new(0.17, 0.5)
	end
	local function screenPoint(pos)
		local cam = workspace.CurrentCamera
		if typeof(pos) == "Vector3" and cam then
			local ok, p, onScreen = pcall(function()
				return cam:WorldToScreenPoint(pos)
			end)
			if ok and p and onScreen and p.Z > 0 then
				return Vector2.new(p.X, p.Y) - gui.AbsolutePosition
			end
		end
		local size = gui.AbsoluteSize
		return Vector2.new(size.X * 0.5, size.Y * 0.55)
	end
	local function floatText(amount)
		local origin = gui.AbsolutePosition
		local at = candyRoot.AbsolutePosition - origin + Vector2.new(candyRoot.AbsoluteSize.X * 0.6, candyRoot.AbsoluteSize.Y + 2)
		local l = label(flyLayer, { Name = "Plus", Text = "+" .. Kit.Format.Short(amount), TextSize = 22, AlignX = "Center", Color = C(255, 214, 120),
			Font = "numeric", ZIndex = 62, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(at.X, at.Y), Size = UDim2.fromOffset(90, 26) })
		textStroke(l, INK, 2)
		if reduced() then
			task.delay(0.9, function()
				l:Destroy()
			end)
			return
		end
		TweenService:Create(l, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(at.X, at.Y + 22), TextTransparency = 1 }):Play()
		task.delay(0.95, function()
			l:Destroy()
		end)
	end
	local inFlight = 0
	function H.CandyGain(data)
		local amount = math.floor(tonumber(type(data) == "table" and data.Amount) or 0)
		if amount <= 0 then
			return
		end
		local visible = hud.Visible and candyRoot.Visible and gui:GetAttribute("OpenMenu") == nil and not gui:GetAttribute("UIHidden")
		-- Played = the source already sounded its pickup (dig spots, ores, perfect hits): no second big chime here
		local quiet = data.Played == true
		if not visible or reduced() then
			floatText(amount)
			if not quiet then
				audio(amount >= 10 and "CandyBig" or "CandyTick")
			end
			return
		end
		local from = screenPoint(data.From)
		local to = pillCenter()
		local count = math.clamp(math.ceil(amount / 3), 1, (low() and 3 or 6))
		if inFlight > 18 then
			count = 1
		end
		flying += 1
		local landed = 0
		for i = 1, count do
			inFlight += 1
			local icon
			if Icons then
				icon = new("Frame", { Name = "Candy", BackgroundTransparency = 1, ZIndex = 61, AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(from.X, from.Y), Size = UDim2.fromOffset(data.Big and 40 or 32, data.Big and 40 or 32) }, flyLayer)
				local tint = (i % 3 == 0) and C(150, 90, 230) or (i % 3 == 1) and PUMPKIN or C(90, 200, 110)
				Icons.New(icon, "Candy", { Size = data.Big and 40 or 32, ZIndex = 61, Color = tint })
			else
				icon = label(flyLayer, { Name = "Candy", Text = "🍬", TextSize = 34, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 61,
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(from.X, from.Y), Size = UDim2.fromOffset(data.Big and 40 or 32, data.Big and 40 or 32) })
			end
			icon.Rotation = math.random(-30, 30)
			local spread = Vector2.new(math.random(-60, 60), math.random(-70, -20))
			local mid = from + spread
			local delayT = (i - 1) * 0.06
			task.delay(delayT, function()
				TweenService:Create(icon, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(mid.X, mid.Y) }):Play()
				task.wait(0.22)
				TweenService:Create(icon, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(20, 20), Rotation = icon.Rotation + 160,
				}):Play()
				task.wait(0.42)
				icon:Destroy()
				inFlight -= 1
				landed += 1
				audio("CandyTick", { Pitch = 1 + landed * 0.06 })
				U.Pop(candyIcon)
				if landed == count then
					flying -= 1
					floatText(amount)
					if (data.Big or amount >= 10) and not quiet then
						audio("CandyBig")
					end
					if flying <= 0 then
						flying = 0
						setCandy(target, true)
					end
				end
			end)
		end
		-- never hold the counter forever (attribute arrives late / icons destroyed)
		task.delay(2, function()
			if flying > 0 then
				flying = math.max(0, flying - 1)
				if flying == 0 then
					setCandy(target, true)
				end
			end
		end)
	end
	Bus.On("CandyGain", H.CandyGain)

	--------------------------------------------------------------------------------------------------------------------
	-- 5c. CHAPTER II (WP-L): HUD.Chapter2 with the helpers above
	--------------------------------------------------------------------------------------------------------------------
	do
		local mod = script:FindFirstChild("Chapter2")
		if mod then
			local okC, err = pcall(function()
				require(mod).Start(H, { Player = player, Gui = gui, Hud = hud, U = U, Kit = Kit, Bus = Bus, Shared = Shared, Icons = Icons, Label = label,
					New = new, TextStroke = textStroke, Glass = glass, Audio = audio, FlyLayer = flyLayer, Reduced = reduced, Low = low, Pill = pill })
			end)
			if not okC then
				warn("Halloween HUD Chapter II: " .. tostring(err))
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------------
	-- 5b. Server Exorcism milestone: the whole server's moment on the HUD (ZoneFX plays the world part in the Dead Yard)
	--     the strip shows for everyone, the reached badge pops with a ring and soul motes, a shimmer runs along the bar,
	--     the strip rim flashes neon and the screen edges glow green (red for the Gravekeeper). ReducedMotion: colours only.
	--------------------------------------------------------------------------------------------------------------------
	local edgeGlow = nil
	function H.MilestoneBurst(index, kind)
		local col = kind == "Boss" and C(255, 80, 90) or NEON
		H.ExorcismShowUntil = os.clock() + 7
		H.StripFlashUntil, H.StripFlashColor = os.clock() + 1.6, col
		updateStrip()
		placeAll()
		-- screen edges: two soft green bands (top / bottom) that breathe in and out once
		if not edgeGlow then
			edgeGlow = {}
			for i, y in ipairs({ 0, 1 }) do
				local f = new("Frame", { Name = "HwMilestoneEdge" .. i, BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 59,
					AnchorPoint = Vector2.new(0, y), Position = UDim2.fromScale(0, y), Size = UDim2.fromScale(1, 0.22) }, flyLayer)
				new("UIGradient", { Name = "Fade", Rotation = y == 0 and 90 or 270,
					Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, f)
				edgeGlow[i] = f
			end
		end
		for _, f in ipairs(edgeGlow) do
			f.BackgroundColor3 = col
			f.BackgroundTransparency = 0.25
			TweenService:Create(f, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		end
		if reduced() then
			return
		end
		TweenService:Create(stripPop, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.07 }):Play()
		task.delay(0.12, function()
			TweenService:Create(stripPop, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
		-- the shimmer: a bright band sweeping the filled bar twice
		for k = 0, 1 do
			task.delay(0.15 + k * 0.55, function()
				if not fill.Parent then
					return
				end
				local band = new("Frame", { Name = "HwShimmer", BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.15, ZIndex = 23,
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.1, 0.5), Size = UDim2.new(0.16, 0, 1, 0) }, fill)
				new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.1),
					NumberSequenceKeypoint.new(1, 1) }) }, band)
				TweenService:Create(band, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1.1, 0.5) }):Play()
				task.delay(0.55, function()
					band:Destroy()
				end)
			end)
		end
		local m = milestoneBadges[index]
		if not (m and m.Frame and m.Frame.Visible and m.Frame.AbsoluteSize.X > 2) then
			return
		end
		m.Pop.Scale = 2.1
		TweenService:Create(m.Pop, TweenInfo.new(0.55, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local origin = gui.AbsolutePosition
		local center = m.Frame.AbsolutePosition - origin + m.Frame.AbsoluteSize / 2
		-- a ring that grows out of the badge
		local ring = new("Frame", { Name = "HwMilestoneRing", BackgroundTransparency = 1, ZIndex = 62, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y), Size = UDim2.fromOffset(16, 16) }, flyLayer)
		Kit.Corner(ring, "pill")
		local rs = Kit.Stroke(ring, col, 4, 0)
		TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quart), { Size = UDim2.fromOffset(150, 150) }):Play()
		TweenService:Create(rs, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Transparency = 1, Thickness = 1 }):Play()
		task.delay(0.75, function()
			ring:Destroy()
		end)
		-- soul motes bursting out (frame particles)
		local n = low() and 8 or 16
		for k = 1, n do
			local a = (k / n) * math.pi * 2 + math.random() * 0.4
			local dist = 50 + math.random() * 70
			local size = 5 + math.random() * 6
			local mote = new("Frame", { Name = "HwSoul", BorderSizePixel = 0, BackgroundColor3 = (k % 3 == 0) and WHITE or col, ZIndex = 63,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(center.X, center.Y), Size = UDim2.fromOffset(size, size) }, flyLayer)
			Kit.Corner(mote, "pill")
			local to = center + Vector2.new(math.cos(a) * dist, math.sin(a) * dist * 0.7 - 20)
			local t = 0.6 + math.random() * 0.35
			TweenService:Create(mote, TweenInfo.new(t, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(to.X, to.Y),
				BackgroundTransparency = 1, Size = UDim2.fromOffset(size * 0.4, size * 0.4) }):Play()
			task.delay(t + 0.05, function()
				mote:Destroy()
			end)
		end
	end

	--------------------------------------------------------------------------------------------------------------------
	-- 6. Toasts, signals
	--------------------------------------------------------------------------------------------------------------------
	Bus.On("Toast", function(data)
		if type(data) ~= "table" or type(data.Text) ~= "string" or data.Text == "" then
			return
		end
		local text, own = data.Text, data.NoTranslate == true
		if not own then
			text, own = translate(data.Text)
		end
		local kind = data.Kind
		if kind ~= "success" and kind ~= "error" and kind ~= "warn" then
			kind = "info"
		end
		Kit.Toast(text, { Kind = kind, NoTranslate = own })
	end)
	local QUEST_TEXT = {}
	for _, q in ipairs((Config.Quests and Config.Quests.Pool) or {}) do
		QUEST_TEXT[q.Id] = q
	end
	Bus.On("Signal", function(sig)
		if type(sig) ~= "table" then
			return
		end
		local kind, data = sig.Kind, sig.Data
		if kind == "QuestComplete" and type(data) == "table" then
			local def = QUEST_TEXT[data.Id] or {}
			local text = data.Text or def.Text or data.Id or ""
			local goal = data.Goal or def.Goal or 0
			local line = string.find(text, "%%d") and F(text, goal) or T(text)
			Kit.Toast("✅ " .. T("QUEST DONE") .. " · " .. line, { Kind = "success", NoTranslate = true, Sound = false })
			audio("QuestDone")
			tileBadge()
		elseif kind == "Milestone" and type(data) == "table" then
			local SHORT = { CandyRush = "SERVER CANDY RUSH x2", Block = "A PUMPKIN BLOCK FOR THE EXORCISTS", Mutation = "EVENT MUTATIONS x2", Boss = "THE GRAVEKEEPER RISES" }
			H.Banner({ Title = T("EXORCISM MILESTONE"), Subtitle = T(data.Name or SHORT[data.Kind] or ""), Style = data.Kind == "Boss" and "Boss" or "Exorcism",
				Seconds = 4.5, NoTranslate = true })
			audio("ExorcismMilestone")
			pcall(H.MilestoneBurst, tonumber(data.Index) or 0, data.Kind)
		elseif kind == "Rush" and type(data) == "table" and data.Ended then
			Kit.Toast("⚡ " .. T("Your Candy Rush is over"), { Kind = "info", NoTranslate = true })
		elseif kind == "Exorcism" or kind == "BloodMoon" or kind == "View" then
			task.defer(updateStrip)
			task.defer(tileBadge)
		end
	end)
	Bus.On("StateChanged", function()
		tileBadge()
		curseChanged()
	end)

	--------------------------------------------------------------------------------------------------------------------
	-- 7. Onboarding focus ring (Bus "HUDFocus" {Key})
	--------------------------------------------------------------------------------------------------------------------
	local focus = new("Frame", { Name = "HalloweenFocus", BackgroundTransparency = 1, Visible = false, ZIndex = 70 }, gui)
	focus:SetAttribute("NoTranslate", true)
	Kit.Corner(focus, 18)
	local focusStroke = Kit.Stroke(focus, NEON, 4, 0)
	local pointer = label(focus, { Name = "Pointer", Text = "👆", TextSize = 40, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 71, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.fromOffset(44, 44) })
	local focusKey = nil
	local focusPulse = nil
	local function focusTarget(key)
		if key == "Candy" then
			return candyRoot
		elseif key == "Curse" then
			return curseRoot
		elseif key == "Strip" then
			return strip
		elseif key == "Boss" then
			return boss
		elseif key == "Tile" or key == "Halloween" then
			local t = tile()
			return t and t.root
		end
		return nil
	end
	local function placeFocus()
		local target = focusTarget(focusKey)
		if not target or not target.Visible or not hud.Visible then
			focus.Visible = false
			return
		end
		local origin = gui.AbsolutePosition
		local p, s = target.AbsolutePosition - origin, target.AbsoluteSize
		focus.Position = UDim2.fromOffset(p.X - 6, p.Y - 6)
		focus.Size = UDim2.fromOffset(s.X + 12, s.Y + 12)
		focus.Visible = true
		-- the pointer below the target, or to its right for the rail tile
		if focusKey == "Tile" or focusKey == "Halloween" then
			pointer.Text = "👈"
			pointer.AnchorPoint = Vector2.new(0, 0.5)
			pointer.Position = UDim2.new(1, 8, 0.5, 0)
		else
			pointer.Text = "👆"
			pointer.AnchorPoint = Vector2.new(0.5, 0)
			pointer.Position = UDim2.new(0.5, 0, 1, 6)
		end
	end
	function H.Focus(key)
		focusKey = key
		if focusPulse then
			focusPulse:Cancel()
			focusPulse = nil
		end
		if not key then
			focus.Visible = false
			return
		end
		placeFocus()
		focusStroke.Transparency = 0
		if not reduced() then
			focusPulse = TweenService:Create(focusStroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })
			focusPulse:Play()
		end
	end
	Bus.On("HUDFocus", function(data)
		H.Focus(type(data) == "table" and data.Key or nil)
	end)

	--------------------------------------------------------------------------------------------------------------------
	-- 8. Russian prompts of the Dead Yard (server prompts are never auto-translated)
	--------------------------------------------------------------------------------------------------------------------
	local function localizePrompt(prompt)
		if not prompt:IsA("ProximityPrompt") or not ru() then
			return
		end
		-- [WP-F] Chapter II prompts (the church DESCEND, the Underyard) carry their own Russian: Chapter2State owns them
		if prompt:GetAttribute("ActionTextRU") ~= nil or prompt:GetAttribute("ObjectTextRU") ~= nil then
			return
		end
		for _, prop in ipairs({ "ActionText", "ObjectText" }) do
			local key = "HwEnglish" .. prop
			local en = prompt:GetAttribute(key) or prompt[prop]
			if prompt:GetAttribute(key) == nil then
				prompt:SetAttribute(key, en)
			end
			local text = translate(en)
			if text ~= prompt[prop] then
				prompt[prop] = text
			end
		end
	end
	task.spawn(function()
		local district = workspace:WaitForChild("DOGROTS_District", 60)
		local yard = district and district:WaitForChild("38_DeadYard", 60)
		if not yard then
			return
		end
		for _, d in ipairs(yard:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				localizePrompt(d)
			end
		end
		yard.DescendantAdded:Connect(function(d)
			if d:IsA("ProximityPrompt") then
				task.defer(localizePrompt, d)
			end
		end)
	end)

	--------------------------------------------------------------------------------------------------------------------
	-- 9. Studio debug panel (F7)
	--------------------------------------------------------------------------------------------------------------------
	if RunService:IsStudio() and (Config.Studio == nil or Config.Studio.DebugPanel ~= false) then
		local panelGui = nil
		local function buildDebug()
			local layer = new("ScreenGui", { Name = "DOGROTS_HalloweenDebug", ResetOnSpawn = false, DisplayOrder = 96, Enabled = false })
			layer:SetAttribute("NoTranslate", true)
			local card = new("Frame", { Name = "Card", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(330, 510) }, layer)
			Kit.Corner(card, 16)
			glass(card, PUMPKIN, C(60, 26, 90), C(22, 8, 34))
			local head = label(card, { Name = "Title", Text = "🎃 HALLOWEEN DEBUG (F7)", TextSize = 18, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 28) })
			textStroke(head, INK, 2)
			local cmds = {
				{ "+500 CANDY", { Cmd = "Candy", N = 500 } }, { "+5K CANDY", { Cmd = "Candy", N = 5000 } }, { "CURSE 0", { Cmd = "Curse", N = 0 } },
				{ "CURSE 90", { Cmd = "Curse", N = 90 } }, { "BLOOD MOON (WARN)", { Cmd = "BloodMoon" } }, { "BLOOD MOON NOW", { Cmd = "BloodMoonNow" } },
				{ "MOON: SCHEDULE", { Cmd = "BloodMoonStop" } }, { "+800 SOULS", { Cmd = "Souls", N = 800 } }, { "RESET DAILY", { Cmd = "ResetDaily" } },
				{ "ALL SKINS", { Cmd = "Skins" } }, { "EVENT DOG", { Cmd = "Dog" } }, { "PUMPKIN BLOCK", { Cmd = "Block", Tier = "Pumpkin" } },
				{ "CURSED BLOCK", { Cmd = "Block", Tier = "Cursed Pumpkin" } }, { "BREW READY", { Cmd = "Brew" } }, { "RUSH REFILL", { Cmd = "Rush" } },
				{ "GUIDE AGAIN", { Cmd = "Onboarding" } }, { "BOSS I", { Cmd = "Boss", Difficulty = 1 } }, { "BOSS III", { Cmd = "Boss", Difficulty = 3 } },
				{ "BOSS V", { Cmd = "Boss", Difficulty = 5 } }, { "TEST BANNER", "banner" }, { "TEST CANDY FLY", "fly" },
				{ "TEST MILESTONE", "milestone" }, { "TEST REWARD CARD", "reward" }, { "TEST BREW FINALE", "finale" },
			}
			for i, c in ipairs(cmds) do
				local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
				local b
				b = Kit.Button(card, { Name = "Cmd" .. i, Text = c[1], Style = type(c[2]) == "table" and "secondary" or "gold", TextSize = 13, NoTranslate = true,
					Position = UDim2.fromOffset(12 + col * 156, 42 + row * 38), Size = UDim2.fromOffset(150, 32), OnClick = function()
						if c[2] == "banner" then
							H.Banner({ Title = "THE BLOOD MOON RISES", Subtitle = "+50% candy · haunted dig spots", Style = "BloodMoon", Seconds = 4 })
						elseif c[2] == "fly" then
							local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
							H.CandyGain({ Amount = 12, From = root and root.Position, Big = true })
						elseif c[2] == "milestone" then
							Bus.Fire("Signal", { Kind = "Milestone", Data = { Index = 2, Kind = "Block", Name = "PUMPKIN BLOCK FOR EVERYONE", Souls = 2500 } })
						elseif c[2] == "reward" then
							Bus.Fire("RewardReveal", { Title = "8 EVENT DOGS FOUND", Rows = { { Kind = "Candy", Amount = 400 }, { Kind = "Block", Id = "Cursed Pumpkin", Amount = 1 },
								{ Kind = "Skin", Id = "SoulReaper" }, { Kind = "Title", Id = "BuriedMoon2026" } } })
						elseif c[2] == "finale" then
							Bus.Fire("CauldronClaimLocal", { Level = 5, Test = true, Rows = (Config.Rewards and Config.Rewards.Treat5) or {} })
						else
							b:SetBusy(true)
							local ok, res = State.Request("Debug", c[2])
							b:SetBusy(false)
							local msg = type(res) == "table" and res.Message or tostring(res)
							Kit.Toast("[debug] " .. tostring(msg), { Kind = ok and "success" or "error", NoTranslate = true })
						end
					end })
			end
			layer.Parent = playerGui
			return layer
		end
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or input.KeyCode ~= Enum.KeyCode.F7 then
				return
			end
			panelGui = panelGui or buildDebug()
			panelGui.Enabled = not panelGui.Enabled
		end)
	end

	--------------------------------------------------------------------------------------------------------------------
	-- Ticker + start
	--------------------------------------------------------------------------------------------------------------------
	local function onBoss()
		updateStrip()
		tileBadge()
	end
	for _, name in ipairs({ "Exorcism", "Boss", "BloodMoon", "Finale" }) do
		local f = folder(name)
		if f then
			f.AttributeChanged:Connect(onBoss)
		end
	end
	stateFolder:GetAttributeChangedSignal("ServerRushUntil"):Connect(updateStrip)
	player:GetAttributeChangedSignal("HwInZone"):Connect(updateStrip)
	stateFolder:GetAttributeChangedSignal("Enabled"):Connect(function()
		if stateFolder:GetAttribute("Enabled") == false then
			H.SetEnabled(false)
		end
	end)
	function H.SetEnabled(on)
		H.Disabled = not on
		strip.Visible = on and strip.Visible
		boss.Visible = on and boss.Visible
		candyRoot:SetAttribute("HUDValue", 0)
		curseRoot:SetAttribute("HUDValue", 0)
		for _, spec in ipairs(U.PillSpecs) do
			if spec.key == "MoonCandy" then
				spec.always = on
			end
		end
		if not on then
			candyRoot.Visible, curseRoot.Visible = false, false
			U.SetTileBadge("Halloween", "")
		end
		U.RequestHUDLayout(gui)
	end
	task.spawn(function()
		local last = 0
		while H.Started and not H.Disabled do
			local t = os.clock()
			pcall(updateStrip)
			if t - last > 2 then
				last = t
				pcall(tileBadge)
				pcall(ensureGlyph)
				if focusKey then
					placeFocus()
				end
			end
			local c = tonumber(player:GetAttribute("MoonCurse")) or 0
			if c >= ((Config.Curse and Config.Curse.Thresholds and Config.Curse.Thresholds.Vignette) or 70) and not reduced() and t - lastGhost > (low() and 1.4 or 0.7) then
				lastGhost = t
				pcall(spawnGhost)
			end
			task.wait(0.25)
		end
	end)
	hud:GetPropertyChangedSignal("Visible"):Connect(function()
		if focusKey then
			placeFocus()
		end
	end)
	U.RequestHUDLayout(gui)
	task.defer(function()
		placeAll()
		updateStrip()
		tileBadge()
		ensureGlyph()
	end)
end

return H
