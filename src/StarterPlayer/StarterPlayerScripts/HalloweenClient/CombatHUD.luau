-- CHAPTER II Event HP on screen (StarterPlayerScripts.HalloweenClient.CombatHUD, docs/halloween2/DESIGN.md §10.3).
-- Shown only while the server says the local player is in combat (player attribute HwCombat, written by
-- ServerScriptService.Halloween.EventHP); built inside pcall when combat starts and torn down when it ends and on
-- CharacterRemoving (nothing is left behind: no overlay, no camera grade, no sound loop).
-- * Own ScreenGui DOGROTS_CombatHUD (DisplayOrder 48, HideWithUI, same insets as the main ScreenGui): hidden while a menu
--   is open, while HIDE UI is on and while a cinematic runs (main ScreenGui attributes OpenMenu / UIHidden / CinemaActive).
-- * EVENT HP bar, bottom centre above the hotbar (desktop) / above the touch controls (phones), centred between the HUD
--   attributes HUDInnerLeft / HUDInnerRight, lifted above the timing-hit EXIT button while a strike session runs
--   (MiningActive): big numerals "72 / 100", a tick every 10 HP, a pale damage chunk that trails the fill, a heart that
--   beats faster at low HP, a moon-blue shield segment, WEAKENED and SHIELD pills, the zone name.
-- * Hits (Signal Combat {Kind = "Hit"}): red edge vignette + bar jolt + fill flash (blue when a shield took it);
--   below 30% HP a heartbeat (Halloween Audio "CombatHeartbeat" when that cue exists, else "Heartbeat") with a pulsing
--   vignette.
-- * DOWNED overlay (HwDowned): desaturated camera grade, "DOWNED · WAIT FOR A REVIVE" (or "BEING REVIVED BY ..."), a
--   segmented bleed-out ring with the seconds left, the allies of the zone with distance and HP, and the SELF-REVIVE
--   button (H11 Mourning Shiba: HwSelfReviveAt, request C2SelfRevive; GuiButton.Activated through Kit.Button).
--   The overlay never sinks input (only the button is interactive).
-- * REVIVE progress ring for the reviver while holding a REVIVE prompt (client ProximityPromptService hold events).
-- Mobile first: phone layouts from the screen size, touch targets >= 44 px. ReducedMotion: no jolts / pulses / slides.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local CombatHUD = { Started = false }

local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = RGB(16, 12, 26)
local DEEP = RGB(34, 18, 52)
local VIOLET = RGB(150, 80, 230)
local VIOLET_HI = RGB(196, 150, 255)
local MOON = RGB(150, 200, 255)
local SICKLY = RGB(120, 255, 140)
local CANDLE = RGB(255, 170, 80)
local BLOOD = RGB(220, 40, 60)
local BONE = RGB(230, 222, 200)
local GOLD = RGB(255, 210, 110)

local function hpColor(frac: number): Color3
	if frac > .6 then
		return SICKLY:Lerp(RGB(90, 220, 120), (1 - frac) / .4)
	elseif frac > .3 then
		return CANDLE:Lerp(RGB(150, 230, 110), (frac - .3) / .3)
	end
	return BLOOD:Lerp(CANDLE, math.max(0, frac) / .3)
end

function CombatHUD.Start(ctx)
	if CombatHUD.Started then
		return
	end
	CombatHUD.Started = true
	local Shared, Bus, Audio, State = ctx.Shared, ctx.Bus, ctx.Audio, ctx.State
	local player = ctx.Player or Players.LocalPlayer
	local L = Shared.L
	local playerGui = player:WaitForChild("PlayerGui")
	local main = playerGui:WaitForChild("ScreenGui", 60)
	if not main then
		warn("CombatHUD: no main ScreenGui")
		return
	end
	local modules = main:WaitForChild("Modules", 30)
	local Kit = require(modules:WaitForChild("Kit"))
	local Rules = require(RS:WaitForChild("Halloween"):WaitForChild("CombatRules"))
	local NUMERIC = Kit.Theme.FontNumeric
	-- server replies (EventHP) in Russian through Localization.Combat, else the Halloween dictionary
	local Dict: any = {}
	pcall(function()
		local folder = RS:FindFirstChild("Localization")
		local m = folder and folder:FindFirstChild("Combat")
		Dict = m and require(m) or {}
	end)
	local function said(msg: any): string
		if type(msg) ~= "string" then
			return L("Connection problem; try again", "Проблема со связью, попробуй ещё раз")
		end
		if Kit.Lang() == "ru" then
			local exact = type(Dict.Exact) == "table" and Dict.Exact[msg]
			return exact or Shared.T(msg)
		end
		return msg
	end

	local function A(name: string): any
		return player:GetAttribute(name)
	end
	local function reduced(): boolean
		return Kit.Motion.Reduced() or Shared.ReducedMotion()
	end
	local function now(): number
		return Shared.Now()
	end
	local function new(class: string, props: any?, parent: Instance?): any
		return Kit.New(class, props, parent)
	end
	local function text(parent: Instance, props: any): TextLabel
		local p = table.clone(props)
		p.NoTranslate = true
		p.Color = p.Color or WHITE
		local l = Kit.Text(parent, p)
		local s = new("UIStroke", { Color = INK, Thickness = p.StrokeThickness or 2, LineJoinMode = Enum.LineJoinMode.Round,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
		s.Name = "HwStroke"
		return l
	end
	-- the Chapter II cue when the audio library has it (WP-P), else an existing one
	local function cue(preferred: string, fallback: string): string
		local ok, has = pcall(function()
			return Audio and Audio.Has and Audio.Has(preferred)
		end)
		return (ok and has) and preferred or fallback
	end
	local function heartbeatCue()
		return cue("CombatHeartbeat", "Heartbeat")
	end
	local function play(name: string, opts: any?)
		if Audio and Audio.Play then
			pcall(Audio.Play, name, nil, opts)
		end
	end
	-- the low-HP bed: a looped cue (HPLow) when it exists, else one-shot heartbeats from the refresh
	local function lowLoop(u: any, on: boolean)
		if on and u.LowLoop == nil and Audio and Audio.Loop and cue("HPLow", "") == "HPLow" then
			local ok, h = pcall(Audio.Loop, "HPLow", nil, { Volume = .8 })
			u.LowLoop = ok and h or false
		elseif not on and u.LowLoop ~= nil then
			local h = u.LowLoop
			u.LowLoop = nil
			if h then
				pcall(function()
					h:Stop(.6)
				end)
			end
		end
	end

	local ui: any = nil
	local building = false
	-- the HUD's pixel space: the main ScreenGui's (this layer copies its insets, so both have the same size)
	local function screenSize(): Vector2
		local size = main.AbsoluteSize
		if size.X < 10 and ui and ui.Gui then
			size = ui.Gui.AbsoluteSize
		end
		return size
	end
	-- Roblox touch controls (UITheme.TouchReserve maths): the jump button's left / top and the thumbstick's width
	local function touchReserve(W: number, H: number): (number?, number?, number?)
		if not UserInputService.TouchEnabled then
			return nil, nil, nil
		end
		local small = math.min(W, H) <= 500
		local size = small and 70 or 120
		local jx, jy = W - (size * 1.5 - 10), H - (small and size + 20 or size * 1.75)
		local touchGui = playerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if jump and jump:IsA("GuiObject") and jump.Visible and jump.AbsoluteSize.X > 0 then
			local origin = main.AbsolutePosition
			local x, y = jump.AbsolutePosition.X - origin.X, jump.AbsolutePosition.Y - origin.Y
			if x > W * .5 and y > H * .4 then
				jx, jy = math.min(jx, x), math.min(jy, y)
			end
		end
		return jx, jy, size * (small and 2.2 or 2)
	end
	-- "EVENT HP · THE PIT": the zone name arrives with Signal Combat {Kind = "Enter", Name}
	local zoneName = ""
	local function captionText(): string
		local head = L("EVENT HP", "ЗДОРОВЬЕ")
		return zoneName ~= "" and (head .. " · " .. zoneName) or head
	end

	---------------------------------------------------------------------------------------------------------------
	-- pieces
	---------------------------------------------------------------------------------------------------------------
	-- a ring of n rounded segments (bleed-out timer, revive progress); Set(frac, lit, dim)
	local function segRing(parent: Instance, n: number, z: number)
		local holder = new("Frame", { Name = "Ring", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, parent)
		local segs = {}
		local circumference = 2 * math.pi * .44
		for i = 1, n do
			local a = (i - 1) / n * math.pi * 2 - math.pi / 2
			local seg = new("Frame", { Name = "Seg", AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0,
				Position = UDim2.fromScale(.5 + math.cos(a) * .44, .5 + math.sin(a) * .44),
				Size = UDim2.fromScale(circumference / n * .62, .11), Rotation = math.deg(a) + 90, BackgroundColor3 = WHITE, ZIndex = z }, holder)
			Kit.Corner(seg, "pill")
			segs[i] = seg
		end
		local ring = { Holder = holder, Segs = segs }
		function ring.Set(frac: number, lit: Color3, dim: Color3)
			local k = math.clamp(frac, 0, 1) * n
			for i, seg in ipairs(segs) do
				local on = i <= math.ceil(k - 1e-6)
				seg.BackgroundColor3 = on and lit or dim
				seg.BackgroundTransparency = on and 0 or .55
			end
		end
		return ring
	end

	-- a heart from two discs and a turned square
	local function heart(parent: Instance, z: number)
		local box = new("Frame", { Name = "Heart", BackgroundTransparency = 1, ZIndex = z }, parent)
		local scale = new("UIScale", { Name = "Beat" }, box)
		local parts = {}
		for _, x in ipairs({ .3, .7 }) do
			local d = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(x, .36), Size = UDim2.fromScale(.48, .48),
				BorderSizePixel = 0, ZIndex = z }, box)
			Kit.Corner(d, "pill")
			table.insert(parts, d)
		end
		local tip = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .55), Size = UDim2.fromScale(.5, .5),
			Rotation = 45, BorderSizePixel = 0, ZIndex = z }, box)
		Kit.Corner(tip, 3)
		table.insert(parts, tip)
		local shine = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.3, .3), Size = UDim2.fromScale(.16, .16),
			BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = .25, ZIndex = z + 1 }, box)
		Kit.Corner(shine, "pill")
		local h = { Frame = box, Scale = scale, Parts = parts }
		function h.Color(c: Color3)
			for _, p in ipairs(parts) do
				p.BackgroundColor3 = c
			end
		end
		return h
	end

	local function pill(parent: Instance, name: string, color: Color3, z: number)
		local f = new("Frame", { Name = name, BackgroundColor3 = color, BackgroundTransparency = .08, BorderSizePixel = 0, Visible = false,
			AnchorPoint = Vector2.new(0, 1), ZIndex = z }, parent)
		Kit.Corner(f, "pill")
		Kit.Stroke(f, INK, 2, .1)
		local t = text(f, { Name = "Text", TextSize = 15, Scaled = true, MinTextSize = 9, AlignX = "Center", Font = NUMERIC, ZIndex = z + 1,
			Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 1, -4) })
		local scale = new("UIScale", { Name = "Pop" }, f)
		return { Frame = f, Text = t, Scale = scale }
	end

	---------------------------------------------------------------------------------------------------------------
	-- build / teardown
	---------------------------------------------------------------------------------------------------------------
	local function teardown()
		local u = ui
		ui = nil
		if not u then
			return
		end
		for _, c in ipairs(u.Conns) do
			c:Disconnect()
		end
		lowLoop(u, false)
		if u.Grade then
			u.Grade:Destroy()
		end
		-- a grade still fading out (or left by an earlier camera) never outlives the HUD
		local cam = workspace.CurrentCamera
		if cam then
			for _, c in ipairs(cam:GetChildren()) do
				if c.Name == "DOGROTS_CombatDowned" then
					c:Destroy()
				end
			end
		end
		if u.Gui then
			u.Gui:Destroy()
		end
	end

	local function build()
		local u: any = { Conns = {}, Shown = { HP = -1, Max = -1 }, Lag = 1, LagAt = 0, Display = 1, Ticks = {}, Allies = {}, Beat = 0,
			LastHit = 0, Born = os.clock() }
		ui = u
		local gui = new("ScreenGui", { Name = "DOGROTS_CombatHUD", DisplayOrder = 48, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			IgnoreGuiInset = main.IgnoreGuiInset })
		pcall(function()
			gui.ScreenInsets = main.ScreenInsets
		end)
		gui:SetAttribute("HideWithUI", true)
		gui:SetAttribute("NoTranslate", true)
		u.Gui = gui
		local root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
		u.Root = root

		-- edge vignette (hits, low HP)
		u.Edges = {}
		for _, e in ipairs({ { "Top", Vector2.new(0, 0), UDim2.new(1, 0, .22, 0), 90 }, { "Bottom", Vector2.new(0, 1), UDim2.new(1, 0, .22, 0), -90 },
			{ "Left", Vector2.new(0, 0), UDim2.new(.16, 0, 1, 0), 0 }, { "Right", Vector2.new(1, 0), UDim2.new(.16, 0, 1, 0), 180 } }) do
			local f = new("Frame", { Name = "Vignette" .. e[1], AnchorPoint = e[2], Position = UDim2.fromScale(e[2].X, e[2].Y), Size = e[3],
				BackgroundColor3 = BLOOD, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, root)
			new("UIGradient", { Rotation = e[4], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.6, .7),
				NumberSequenceKeypoint.new(1, 1) }) }, f)
			table.insert(u.Edges, f)
		end

		-- the EVENT HP bar
		local bar = new("Frame", { Name = "HPBar", AnchorPoint = Vector2.new(.5, 1), BackgroundColor3 = WHITE, BackgroundTransparency = .08,
			BorderSizePixel = 0, ZIndex = 10 }, root)
		Kit.Corner(bar, 16)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(58, 30, 86), RGB(20, 10, 32)) }, bar)
		Kit.Stroke(bar, VIOLET, 2, .05)
		u.Bar = bar
		u.BarScale = new("UIScale", { Name = "Pop" }, bar)
		u.Heart = heart(bar, 13)
		local track = new("Frame", { Name = "Track", BackgroundColor3 = RGB(30, 10, 24), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 11 }, bar)
		Kit.Corner(track, 9)
		Kit.Stroke(track, WHITE, 1.5, .65)
		u.Track = track
		u.LagFill = new("Frame", { Name = "Lag", BackgroundColor3 = RGB(255, 226, 196), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 12 }, track)
		Kit.Corner(u.LagFill, 9)
		u.Fill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 13 }, track)
		Kit.Corner(u.Fill, 9)
		u.FillGrad = new("UIGradient", { Rotation = 90 }, u.Fill)
		u.Shine = new("Frame", { Name = "Shine", BackgroundColor3 = WHITE, BackgroundTransparency = .78, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, .38, 0), Position = UDim2.fromScale(0, .08), ZIndex = 14 }, u.Fill)
		Kit.Corner(u.Shine, "pill")
		u.Flash = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
			ZIndex = 15 }, track)
		u.ShieldFill = new("Frame", { Name = "Shield", BackgroundColor3 = MOON, BackgroundTransparency = .12, BorderSizePixel = 0, Visible = false,
			ZIndex = 16 }, track)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(220, 240, 255), MOON) }, u.ShieldFill)
		u.TickHolder = new("Frame", { Name = "Ticks", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 17 }, track)
		u.Num = text(bar, { Name = "HP", TextSize = 30, Scaled = true, MinTextSize = 14, AlignX = "Right", Font = NUMERIC, ZIndex = 14 })
		u.NumMax = text(bar, { Name = "Max", TextSize = 17, Scaled = true, MinTextSize = 9, AlignX = "Left", Font = NUMERIC, ZIndex = 14,
			Color = RGB(214, 196, 240) })
		u.Caption = text(bar, { Name = "Zone", TextSize = 13, Scaled = true, MinTextSize = 7, AlignX = "Left", ZIndex = 14, Color = VIOLET_HI,
			StrokeThickness = 1.5 })
		u.Weak = pill(bar, "Weakened", RGB(122, 40, 160), 18)
		u.ShieldPill = pill(bar, "ShieldPill", RGB(60, 110, 190), 18)

		-- the DOWNED overlay: never Active, only the self-revive button takes input
		local downed = new("Frame", { Name = "Downed", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30 }, root)
		u.Downed = downed
		local dim = new("Frame", { Name = "Dim", BackgroundColor3 = INK, BackgroundTransparency = .45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
			ZIndex = 30 }, downed)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .1), NumberSequenceKeypoint.new(.4, .65),
			NumberSequenceKeypoint.new(.6, .65), NumberSequenceKeypoint.new(1, .1) }) }, dim)
		u.Dim = dim
		u.Title = text(downed, { Name = "Title", Text = L("DOWNED", "ПОВЕРЖЕН"), TextSize = 56, Scaled = true, MinTextSize = 20, AlignX = "Center",
			Color = RGB(255, 120, 140), ZIndex = 32, StrokeThickness = 3, AnchorPoint = Vector2.new(.5, .5) })
		u.Sub = text(downed, { Name = "Sub", TextSize = 22, Scaled = true, MinTextSize = 11, AlignX = "Center", Color = BONE, ZIndex = 32,
			AnchorPoint = Vector2.new(.5, .5) })
		local ringBox = new("Frame", { Name = "BleedOut", BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, .5), ZIndex = 32 }, downed)
		u.RingBox = ringBox
		u.BleedRing = segRing(ringBox, 36, 33)
		u.BleedText = text(ringBox, { Name = "Seconds", TextSize = 34, Scaled = true, MinTextSize = 12, AlignX = "Center", Font = NUMERIC, ZIndex = 34,
			Position = UDim2.fromScale(.2, .28), Size = UDim2.fromScale(.6, .34) })
		u.BleedLabel = text(ringBox, { Name = "Label", Text = L("BLEEDING OUT", "ИСТЕКАЕШЬ"), TextSize = 12, Scaled = true, MinTextSize = 7,
			AlignX = "Center", Color = RGB(255, 170, 190), ZIndex = 34, Position = UDim2.fromScale(.18, .6), Size = UDim2.fromScale(.64, .14) })
		local allies = new("Frame", { Name = "Allies", BackgroundColor3 = INK, BackgroundTransparency = .25, BorderSizePixel = 0, ZIndex = 32 }, downed)
		Kit.Corner(allies, 14)
		Kit.Stroke(allies, VIOLET, 2, .2)
		u.AllyBox = allies
		u.AllyTitle = text(allies, { Name = "Header", Text = L("ALLIES", "СОЮЗНИКИ"), TextSize = 15, Scaled = true, MinTextSize = 8, AlignX = "Left",
			Color = VIOLET_HI, ZIndex = 33 })
		for i = 1, 4 do
			local row = new("Frame", { Name = "Ally" .. i, BackgroundTransparency = 1, ZIndex = 33 }, allies)
			local dot = new("Frame", { Name = "Dot", BorderSizePixel = 0, ZIndex = 34, AnchorPoint = Vector2.new(0, .5) }, row)
			Kit.Corner(dot, "pill")
			local nameL = text(row, { Name = "Name", TextSize = 15, Scaled = true, MinTextSize = 8, AlignX = "Left", ZIndex = 34 })
			local distL = text(row, { Name = "Dist", TextSize = 14, Scaled = true, MinTextSize = 8, AlignX = "Right", Font = NUMERIC, ZIndex = 34,
				Color = RGB(214, 196, 240) })
			local hpBack = new("Frame", { Name = "HP", BackgroundColor3 = RGB(40, 14, 30), BorderSizePixel = 0, ZIndex = 34 }, row)
			Kit.Corner(hpBack, "pill")
			local hpFill = new("Frame", { Name = "Fill", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 35 }, hpBack)
			Kit.Corner(hpFill, "pill")
			u.Allies[i] = { Row = row, Dot = dot, Name = nameL, Dist = distL, Back = hpBack, Fill = hpFill }
		end
		u.NoAllies = text(allies, { Name = "Empty", Text = L("No allies in this fight", "В этом бою нет союзников"), TextSize = 14, Scaled = true,
			MinTextSize = 8, AlignX = "Center", Color = RGB(190, 176, 214), ZIndex = 33 })
		u.SelfButton = Kit.Button(downed, { Name = "SelfRevive", Text = L("SELF-REVIVE", "ПОДНЯТЬСЯ САМОМУ"), Style = "success", NoTranslate = true,
			AnchorPoint = Vector2.new(.5, 0), ZIndex = 36, OnClick = function()
				CombatHUD.SelfRevive()
			end })
		u.SelfButton.Instance.Visible = false
		u.SelfScale = new("UIScale", { Name = "Pulse" }, u.SelfButton.Instance)

		-- the reviver's progress ring
		local rr = new("Frame", { Name = "ReviveRing", BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, .5), Visible = false, ZIndex = 40 }, root)
		u.ReviveBox = rr
		local disc = new("Frame", { Name = "Back", BackgroundColor3 = INK, BackgroundTransparency = .3, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5),
			Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(.78, .78), ZIndex = 40 }, rr)
		Kit.Corner(disc, "pill")
		u.ReviveRing = segRing(rr, 28, 41)
		u.RevivePct = text(rr, { Name = "Pct", TextSize = 24, Scaled = true, MinTextSize = 10, AlignX = "Center", Font = NUMERIC, ZIndex = 42,
			Position = UDim2.fromScale(.22, .32), Size = UDim2.fromScale(.56, .36), Color = SICKLY })
		u.ReviveName = text(rr, { Name = "Who", TextSize = 18, Scaled = true, MinTextSize = 9, AlignX = "Center", ZIndex = 42, AnchorPoint = Vector2.new(.5, 0),
			Position = UDim2.new(.5, 0, 1, 6), Size = UDim2.new(2.4, 0, 0, 24) })

		-- a centred caption for one-shot moments (REVIVED!, YOU BLED OUT)
		u.Moment = text(root, { Name = "Moment", TextSize = 40, Scaled = true, MinTextSize = 16, AlignX = "Center", ZIndex = 45, AnchorPoint = Vector2.new(.5, .5),
			Position = UDim2.fromScale(.5, .38), Size = UDim2.new(.8, 0, 0, 52), Transparency = 1, StrokeThickness = 3 })
		u.Moment:FindFirstChild("HwStroke").Transparency = 1
		gui.Parent = playerGui
		return u
	end

	---------------------------------------------------------------------------------------------------------------
	-- layout (pixels of the main ScreenGui: the same insets, so the HUD attributes line up)
	---------------------------------------------------------------------------------------------------------------
	local function layout(u: any)
		local size = screenSize()
		local W, H = size.X, size.Y
		local phone = math.min(W, H) < 560
		local l = tonumber(main:GetAttribute("HUDInnerLeft")) or 12
		local r = tonumber(main:GetAttribute("HUDInnerRight")) or (W - 12)
		if r - l < 260 then
			l, r = 12, W - 12
		end
		local w = math.floor(math.clamp(r - l - 16, 240, phone and 380 or 470))
		local h = phone and 46 or 56
		local bottom = phone and 76 or 90
		if main:GetAttribute("MiningActive") == true then
			bottom = phone and 124 or 138 -- above the timing-hit hint and EXIT button
		end
		local cx = math.floor((l + r) / 2)
		cx = math.clamp(cx, w / 2 + 8, W - w / 2 - 8)
		-- phones: never under the thumbstick or the jump button (portrait screens lift the bar above them)
		local jx, jy, thumbW = touchReserve(W, H)
		if jx and jy and thumbW and (cx + w / 2 > jx - 6 or cx - w / 2 < thumbW) then
			bottom = math.max(bottom, H - jy + 8)
		end
		u.Bar.Size = UDim2.fromOffset(w, h)
		u.Bar.Position = UDim2.fromOffset(cx, H - bottom)
		u.BarY = H - bottom
		local pad = 8
		local hs = h - 14
		u.Heart.Frame.Position = UDim2.fromOffset(pad, 7)
		u.Heart.Frame.Size = UDim2.fromOffset(hs, hs)
		local numW = phone and 92 or 116
		local tx = pad + hs + 8
		u.Track.Position = UDim2.fromOffset(tx, math.floor(h * .3))
		u.Track.Size = UDim2.fromOffset(w - tx - numW - pad, math.floor(h * .42))
		local nx = w - numW - pad + 4
		u.Num.Position = UDim2.fromOffset(nx, 4)
		u.Num.Size = UDim2.fromOffset(math.floor(numW * .52), h - 8)
		u.NumMax.Position = UDim2.fromOffset(nx + math.floor(numW * .52) + 2, math.floor(h * .34))
		u.NumMax.Size = UDim2.fromOffset(math.floor(numW * .46), math.floor(h * .5))
		-- "EVENT HP · <zone>" in the strip above the track
		u.Caption.Position = UDim2.fromOffset(tx + 2, 2)
		u.Caption.Size = UDim2.fromOffset(w - tx - numW - pad - 4, math.floor(h * .3) - 3)
		local pillH = phone and 26 or 30
		u.Weak.Frame.Size = UDim2.fromOffset(phone and 132 or 156, pillH)
		u.Weak.Frame.Position = UDim2.fromOffset(4, -6)
		u.ShieldPill.Frame.Size = UDim2.fromOffset(phone and 104 or 120, pillH)
		u.ShieldPill.Frame.AnchorPoint = Vector2.new(1, 1)
		u.ShieldPill.Frame.Position = UDim2.new(1, -4, 0, -6)
		-- downed overlay: column in the middle; allies to the right on wide screens, under the ring on phones
		local ring = phone and 104 or 136
		local cy = math.floor(H * (phone and .36 or .4))
		u.Title.Position = UDim2.fromOffset(W / 2, cy - ring / 2 - (phone and 52 or 70))
		u.Title.Size = UDim2.fromOffset(math.min(W - 24, 560), phone and 42 or 60)
		u.Sub.Position = UDim2.fromOffset(W / 2, cy - ring / 2 - (phone and 18 or 26))
		u.Sub.Size = UDim2.fromOffset(math.min(W - 24, 560), phone and 22 or 28)
		u.RingBox.Position = UDim2.fromOffset(W / 2, cy + 6)
		u.RingBox.Size = UDim2.fromOffset(ring, ring)
		u.SelfButton.Instance.Size = UDim2.fromOffset(phone and 220 or 260, phone and 48 or 54)
		u.SelfButton.Instance.Position = UDim2.fromOffset(W / 2, cy + ring / 2 + 18)
		local aw = phone and math.min(W - 24, 300) or 250
		local rowH = phone and 24 or 28
		local ah = 30 + rowH * 4 + 8
		-- beside the column (the wider of the ring and the button), top-aligned with the ring, when it fits
		local sideX = W / 2 + math.max(ring / 2, u.SelfButton.Instance.Size.X.Offset / 2) + 24
		local sideW = math.min(aw, W - sideX - 12)
		if sideW >= 200 then
			aw = sideW
			u.AllyBox.AnchorPoint = Vector2.new(0, 0)
			u.AllyBox.Position = UDim2.fromOffset(sideX, cy + 6 - ring / 2)
		else
			-- narrow (portrait) screens: the list under the ring / button
			u.AllyBox.AnchorPoint = Vector2.new(.5, 0)
			local y = cy + ring / 2 + 18 + (u.SelfButton.Instance.Visible and (phone and 56 or 62) or 0)
			y = math.min(y, u.BarY - h - ah - 12)
			u.AllyBox.Position = UDim2.fromOffset(W / 2, math.max(cy + ring / 2 + 10, y))
		end
		u.AllyBox.Size = UDim2.fromOffset(aw, ah)
		u.AllyTitle.Position = UDim2.fromOffset(12, 4)
		u.AllyTitle.Size = UDim2.fromOffset(aw - 24, 22)
		u.NoAllies.Position = UDim2.fromOffset(12, 34)
		u.NoAllies.Size = UDim2.fromOffset(aw - 24, rowH)
		for i, row in ipairs(u.Allies) do
			row.Row.Position = UDim2.fromOffset(10, 28 + (i - 1) * rowH)
			row.Row.Size = UDim2.fromOffset(aw - 20, rowH)
			row.Dot.Position = UDim2.fromOffset(0, rowH / 2)
			row.Dot.Size = UDim2.fromOffset(10, 10)
			row.Name.Position = UDim2.fromOffset(16, 0)
			row.Name.Size = UDim2.fromOffset(aw - 20 - 16 - 110, rowH - 8)
			row.Back.Position = UDim2.fromOffset(16, rowH - 7)
			row.Back.Size = UDim2.fromOffset(aw - 20 - 16 - 60, 4)
			row.Dist.Position = UDim2.fromOffset(aw - 20 - 56, 0)
			row.Dist.Size = UDim2.fromOffset(56, rowH)
		end
		local rs = phone and 96 or 116
		u.ReviveBox.Size = UDim2.fromOffset(rs, rs)
		u.ReviveBox.Position = UDim2.fromOffset(W / 2, math.floor(H * .5))
		u.LaidW, u.LaidH, u.LaidMining = W, H, main:GetAttribute("MiningActive") == true
	end

	-- one 2-px tick every 10 HP (rebuilt when MaxHP changes)
	local function ticks(u: any, max: number)
		for _, t in ipairs(u.Ticks) do
			t:Destroy()
		end
		table.clear(u.Ticks)
		local n = math.floor((max - 1e-6) / 10)
		for i = 1, n do
			local f = new("Frame", { Name = "Tick", AnchorPoint = Vector2.new(.5, 0), Position = UDim2.fromScale(i * 10 / max, 0),
				Size = UDim2.new(0, i % 5 == 0 and 3 or 2, 1, 0), BackgroundColor3 = INK, BackgroundTransparency = i % 5 == 0 and .15 or .4,
				BorderSizePixel = 0, ZIndex = 17 }, u.TickHolder)
			table.insert(u.Ticks, f)
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- feedback
	---------------------------------------------------------------------------------------------------------------
	local function vignette(u: any, color: Color3, strength: number, dur: number)
		for _, e in ipairs(u.Edges) do
			e.BackgroundColor3 = color
			e.BackgroundTransparency = 1 - math.clamp(strength, 0, 1)
			TweenService:Create(e, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		end
	end

	local function moment(u: any, textEn: string, textRu: string, color: Color3, hold: number)
		local m = u.Moment
		m.Text = L(textEn, textRu)
		m.TextColor3 = color
		m.TextTransparency = 0
		local stroke = m:FindFirstChild("HwStroke")
		if stroke then
			stroke.Transparency = 0
		end
		local token = {}
		u.MomentToken = token
		task.delay(hold, function()
			if ui ~= u or u.MomentToken ~= token then
				return
			end
			TweenService:Create(m, TweenInfo.new(.4), { TextTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(.4), { Transparency = 1 }):Play()
			end
		end)
	end

	local function onHit(u: any, d: any)
		local amount = tonumber(d.Amount) or 0
		if amount <= 0 then
			return
		end
		local max = math.max(1, tonumber(d.Max) or 100)
		local absorbed = tonumber(d.Absorbed) or 0
		local shieldOnly = absorbed >= amount - 1e-3
		local strength = math.clamp(.25 + amount / max * 1.6, .25, .8)
		if d.Tick then
			strength *= .45
		end
		vignette(u, shieldOnly and MOON or BLOOD, strength, d.Tick and .35 or .6)
		if not d.Tick then
			play(cue("HPHit", "BossHurt"), { Volume = shieldOnly and .45 or .7, Pitch = shieldOnly and 1.3 or 1 })
		end
		u.Flash.BackgroundColor3 = shieldOnly and MOON or WHITE
		u.Flash.BackgroundTransparency = .25
		TweenService:Create(u.Flash, TweenInfo.new(.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		u.LastHit = os.clock()
		if not reduced() and not d.Tick then
			u.Bar.Rotation = (math.random() < .5 and -1 or 1) * (1 + amount / max * 6)
			TweenService:Create(u.Bar, TweenInfo.new(.3, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
			u.BarScale.Scale = 1.05
			TweenService:Create(u.BarScale, TweenInfo.new(.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- the per-frame refresh
	---------------------------------------------------------------------------------------------------------------
	local function hidden(): boolean
		return main:GetAttribute("OpenMenu") ~= nil or main:GetAttribute("UIHidden") == true or main:GetAttribute("CinemaActive") == true
	end

	local function setGrade(u: any, on: boolean)
		local cam = workspace.CurrentCamera
		if on and not u.Grade and cam then
			local g = new("ColorCorrectionEffect", { Name = "DOGROTS_CombatDowned", Saturation = 0, Contrast = 0, Brightness = 0,
				TintColor = WHITE }, cam)
			u.Grade = g
			TweenService:Create(g, TweenInfo.new(reduced() and 0 or .6), { Saturation = -.72, Contrast = .08, Brightness = -.04,
				TintColor = RGB(222, 214, 255) }):Play()
		elseif not on and u.Grade then
			local g = u.Grade
			u.Grade = nil
			TweenService:Create(g, TweenInfo.new(reduced() and 0 or .4), { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE }):Play()
			task.delay(.45, function()
				g:Destroy()
			end)
		end
	end

	local function allies(u: any, t: number)
		local zone = A("HwCombatZone")
		local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local list = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= player and pl:GetAttribute("HwCombat") == true and pl:GetAttribute("HwCombatZone") == zone then
				local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				local dist = (me and root) and (me.Position - root.Position).Magnitude or math.huge
				table.insert(list, { Player = pl, Dist = dist })
			end
		end
		table.sort(list, function(a, b)
			return a.Dist < b.Dist
		end)
		u.NoAllies.Visible = #list == 0
		for i, row in ipairs(u.Allies) do
			local e = list[i]
			row.Row.Visible = e ~= nil
			if e then
				local pl = e.Player
				local isDown = pl:GetAttribute("HwDowned") == true
				local hp = tonumber(pl:GetAttribute("HwHP")) or 0
				local max = math.max(1, tonumber(pl:GetAttribute("HwHPMax")) or 100)
				row.Name.Text = pl.DisplayName
				row.Name.TextColor3 = isDown and RGB(255, 140, 150) or BONE
				row.Dot.BackgroundColor3 = isDown and BLOOD or SICKLY
				row.Fill.Size = UDim2.fromScale(isDown and 0 or math.clamp(hp / max, 0, 1), 1)
				row.Fill.BackgroundColor3 = hpColor(hp / max)
				row.Dist.Text = e.Dist < 1e6 and L(string.format("%d m", math.floor(e.Dist + .5)), string.format("%d м", math.floor(e.Dist + .5))) or "—"
			end
		end
	end

	local function refresh(u: any, dt: number)
		local t = now()
		local clock = os.clock()
		u.Root.Visible = not hidden()
		local size = screenSize()
		local W, H = size.X, size.Y
		if W ~= u.LaidW or H ~= u.LaidH or (main:GetAttribute("MiningActive") == true) ~= u.LaidMining then
			layout(u)
		end
		local max = math.max(1, tonumber(A("HwHPMax")) or 100)
		local isDown = A("HwDowned") == true
		local hp = isDown and 0 or math.max(0, tonumber(A("HwHP")) or max)
		local shield = math.max(0, tonumber(A("HwShield")) or 0)
		if max ~= u.Shown.Max then
			u.Shown.Max = max
			ticks(u, max)
		end
		-- fill eases to the server value; the pale chunk waits .35 s, then drains
		local target = math.clamp(hp / max, 0, 1)
		local k = reduced() and 1 or (1 - math.exp(-dt * 14))
		u.Display += (target - u.Display) * k
		if target > u.Lag then
			u.Lag = target
		elseif target < u.Lag - 1e-4 then
			if clock - u.LastHit > .35 then
				u.Lag = math.max(target, u.Lag - dt * (reduced() and 10 or .9))
			end
		end
		u.Fill.Size = UDim2.fromScale(u.Display, 1)
		u.LagFill.Size = UDim2.fromScale(math.max(u.Lag, u.Display), 1)
		local col = hpColor(target)
		u.FillGrad.Color = ColorSequence.new(col:Lerp(WHITE, .25), col:Lerp(INK, .2))
		local shown = hp > 0 and math.ceil(hp - 1e-6) or 0
		u.Num.Text = tostring(shown)
		u.Num.TextColor3 = target < .3 and RGB(255, 150, 150) or WHITE
		u.NumMax.Text = "/ " .. tostring(math.floor(max + .5))
		u.Heart.Color(isDown and RGB(90, 70, 110) or col)
		-- shield: a moon-blue segment after the HP (pushed back inside the bar when it would overflow)
		if shield > 0 and not isDown then
			local sw = math.clamp(shield / max, 0, 1)
			local x = math.min(u.Display, 1 - sw)
			u.ShieldFill.Visible = true
			u.ShieldFill.Position = UDim2.fromScale(x, 0)
			u.ShieldFill.Size = UDim2.fromScale(sw, 1)
			u.ShieldPill.Frame.Visible = true
			u.ShieldPill.Text.Text = L("SHIELD ", "ЩИТ ") .. tostring(math.ceil(shield))
		else
			u.ShieldFill.Visible = false
			u.ShieldPill.Frame.Visible = false
		end
		local weak = (tonumber(A("HwWeakenedUntil")) or 0) - t
		u.Weak.Frame.Visible = weak > 0 and not isDown -- the downed overlay owns the screen
		if weak > 0 then
			u.Weak.Text.Text = L("WEAKENED ", "ОСЛАБЛЕН ") .. tostring(math.ceil(weak)) .. L("s", "с")
			u.Weak.Scale.Scale = reduced() and 1 or (1 + .04 * math.sin(clock * 6))
		end
		-- low HP: a faster heart, a heartbeat cue and a pulsing vignette
		local low = not isDown and target < .3
		local beatGap = .55 + target * 1.6
		lowLoop(u, low and not hidden())
		if low and clock - u.Beat >= beatGap then
			u.Beat = clock
			if not u.LowLoop then
				play(heartbeatCue(), { Volume = .35 + (.3 - target) })
			end
			vignette(u, BLOOD, .3 + (.3 - target), .5)
		end
		local beat = (low and not reduced()) and math.max(0, math.sin((clock - u.Beat) / beatGap * math.pi * 2)) or 0
		u.Heart.Scale.Scale = 1 + beat * .14
		-- DOWNED overlay
		u.Downed.Visible = isDown
		setGrade(u, isDown and not hidden())
		if isDown then
			local untilT = tonumber(A("HwDownedUntil")) or t
			local total = Rules.Config().DownedSeconds
			local left = math.max(0, untilT - t)
			local frac = left / math.max(1, total)
			u.BleedRing.Set(frac, BLOOD:Lerp(VIOLET_HI, frac), RGB(60, 30, 70))
			u.BleedText.Text = tostring(math.ceil(left))
			local by = tonumber(A("HwReviveBy")) or 0
			if by ~= 0 then
				local who = Players:GetPlayerByUserId(by)
				local name = who and who.DisplayName or "?"
				u.Sub.Text = L("BEING REVIVED BY ", "ТЕБЯ ПОДНИМАЕТ ") .. name
				u.Sub.TextColor3 = SICKLY
			else
				u.Sub.Text = L("WAIT FOR A REVIVE", "ДОЖДИСЬ, ПОКА ТЕБЯ ПОДНИМУТ")
				u.Sub.TextColor3 = BONE
			end
			if not reduced() then
				u.Title.Rotation = math.sin(clock * 1.6) * 1.2
			end
			local selfAt = tonumber(A("HwSelfReviveAt")) or 0
			local btn = u.SelfButton
			local wasVisible = btn.Instance.Visible
			btn.Instance.Visible = selfAt > 0
			if wasVisible ~= btn.Instance.Visible then
				layout(u)
			end
			if selfAt > 0 then
				local wait = selfAt - t
				if wait > 0 then
					btn:SetText(L("SELF-REVIVE IN ", "ПОДЪЁМ ЧЕРЕЗ ") .. tostring(math.ceil(wait)))
					btn:SetDisabled(true)
					u.SelfScale.Scale = 1
				else
					btn:SetText(L("SELF-REVIVE", "ПОДНЯТЬСЯ САМОМУ"))
					btn:SetDisabled(u.SelfBusy == true)
					u.SelfScale.Scale = reduced() and 1 or (1 + .05 * math.sin(clock * 7))
				end
			end
			if clock - (u.AllyAt or 0) > .25 then
				u.AllyAt = clock
				allies(u, t)
			end
		end
		-- the reviver's ring
		local hold = u.Hold
		if hold and hold.Prompt.Parent then
			local frac = math.clamp((os.clock() - hold.Start) / math.max(.05, hold.Duration), 0, 1)
			u.ReviveBox.Visible = true
			u.ReviveRing.Set(frac, SICKLY, RGB(40, 60, 50))
			local quarter = math.floor(frac * 4)
			if quarter > (hold.Tick or 0) and quarter < 4 then
				hold.Tick = quarter
				play(cue("ReviveTick", "CandyTick"), { Volume = .6, Pitch = 1 + quarter * .12 })
			end
			u.RevivePct.Text = tostring(math.floor(frac * 100)) .. "%"
			u.ReviveName.Text = L("REVIVING ", "ПОДНИМАЕШЬ ") .. hold.Name
		else
			u.ReviveBox.Visible = false
			u.Hold = nil
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- life cycle: built while HwCombat (and a character exists), torn down otherwise
	---------------------------------------------------------------------------------------------------------------
	local loop: RBXScriptConnection? = nil
	local leaving = false
	local function stopLoop()
		if loop then
			loop:Disconnect()
			loop = nil
		end
	end
	local function hardStop()
		stopLoop()
		leaving = false
		teardown()
	end
	local function ensure()
		if ui or building then
			return
		end
		building = true
		local ok, err = pcall(function()
			local u = build()
			layout(u)
			ticks(u, math.max(1, tonumber(A("HwHPMax")) or 100))
			u.Shown.Max = math.max(1, tonumber(A("HwHPMax")) or 100)
			local hp = A("HwDowned") == true and 0 or (tonumber(A("HwHP")) or u.Shown.Max)
			u.Display = math.clamp(hp / u.Shown.Max, 0, 1)
			u.Lag = u.Display
			u.Caption.Text = captionText()
			if not reduced() then
				local final = u.Bar.Position
				u.Bar.Position = final + UDim2.fromOffset(0, 90)
				TweenService:Create(u.Bar, TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = final }):Play()
			end
			table.insert(u.Conns, main:GetAttributeChangedSignal("HUDInnerLeft"):Connect(function()
				layout(u)
			end))
			table.insert(u.Conns, main:GetAttributeChangedSignal("HUDInnerRight"):Connect(function()
				layout(u)
			end))
		end)
		building = false
		if not ok then
			warn("CombatHUD: build failed: " .. tostring(err))
			teardown()
			return
		end
		stopLoop()
		loop = RunService.RenderStepped:Connect(function(dt)
			local u = ui
			if not u then
				stopLoop()
				return
			end
			local okR, errR = pcall(refresh, u, math.min(dt, .1))
			if not okR then
				warn("CombatHUD: refresh failed: " .. tostring(errR))
				hardStop()
			end
		end)
	end
	local function leave()
		local u = ui
		if not u or leaving then
			return
		end
		leaving = true
		setGrade(u, false)
		u.Downed.Visible = false
		if reduced() then
			hardStop()
			return
		end
		TweenService:Create(u.Bar, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = u.Bar.Position + UDim2.fromOffset(0, 90) }):Play()
		task.delay(.32, function()
			if ui == u and A("HwCombat") ~= true then
				hardStop()
			else
				leaving = false
			end
		end)
	end
	local function sync()
		if A("HwCombat") == true and player.Character then
			if leaving and ui then
				hardStop()
			end
			ensure()
		else
			leave()
		end
	end

	-- requests
	function CombatHUD.SelfRevive()
		local u = ui
		if not u or u.SelfBusy then
			return
		end
		u.SelfBusy = true
		u.SelfButton:SetBusy(true)
		task.spawn(function()
			local ok, res = false, nil
			if State and State.Request then
				ok, res = State.Request("C2SelfRevive", {})
			end
			if ui == u then
				u.SelfBusy = false
				u.SelfButton:SetBusy(false)
			end
			if not ok then
				Kit.Toast(said(res), { Kind = "error" })
			end
		end)
	end
	CombatHUD.IsBuilt = function(): boolean
		return ui ~= nil
	end

	for _, a in ipairs({ "HwCombat", "HwDowned" }) do
		player:GetAttributeChangedSignal(a):Connect(sync)
	end
	player:GetAttributeChangedSignal("HwDowned"):Connect(function()
		local u = ui
		if not u then
			return
		end
		if A("HwDowned") == true then
			play(cue("Downed", "Heartbeat"), { Volume = .7, Pitch = .8 })
			vignette(u, VIOLET, .7, .9)
		end
	end)
	player.CharacterRemoving:Connect(function()
		hardStop()
	end)
	player.CharacterAdded:Connect(function()
		task.defer(sync)
	end)

	-- server moments: hits, revive, bleed-out, wipe, zone names
	Bus.On("Signal", function(s)
		if type(s) ~= "table" or s.Kind ~= "Combat" or type(s.Data) ~= "table" then
			return
		end
		local d = s.Data
		local mine = tonumber(d.UserId) == player.UserId
		if d.Kind == "Enter" and mine then
			local n = d.Name
			zoneName = type(n) == "table" and L(tostring(n[1] or ""), tostring(n[2] or n[1] or "")) or (type(n) == "string" and n or "")
			task.defer(function()
				sync()
				if ui then
					ui.Caption.Text = captionText()
				end
			end)
			return
		end
		local u = ui
		if not u then
			return
		end
		if d.Kind == "Hit" and mine then
			onHit(u, d)
		elseif d.Kind == "Revive" and mine then
			vignette(u, SICKLY, .55, .8)
			moment(u, d.Self and "MOURNING VEIL!" or "REVIVED!", d.Self and "СКОРБНАЯ ВУАЛЬ!" or "ТЕБЯ ПОДНЯЛИ!", SICKLY, 1.1)
			play(cue("Revive", "Unlock"), { Volume = .7 })
		elseif d.Kind == "Revive" and tonumber(d.By) == player.UserId then
			moment(u, "ALLY REVIVED!", "СОЮЗНИК ПОДНЯТ!", SICKLY, .9)
			play("Claim", { Volume = .6 })
		elseif d.Kind == "BleedOut" and mine then
			moment(u, "YOU BLED OUT · WEAKENED", "ТЫ ИСТЁК КРОВЬЮ · ОСЛАБЛЕН", RGB(255, 140, 160), 2)
			vignette(u, VIOLET, .6, 1)
		elseif d.Kind == "Wipe" then
			moment(u, "THE PARTY HAS FALLEN", "ОТРЯД ПАЛ", RGB(255, 120, 140), 2)
			play("BellToll", { Volume = .5, Pitch = .7 })
		elseif d.Kind == "Shield" and mine then
			vignette(u, MOON, .35, .6)
			if not reduced() then
				u.ShieldPill.Scale.Scale = 1.25
				TweenService:Create(u.ShieldPill.Scale, TweenInfo.new(.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end)

	-- the reviver's progress ring (client hold events of the REVIVE prompts)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt:GetAttribute("HwRevive") ~= true or not ui then
			return
		end
		local target = Players:GetPlayerByUserId(tonumber(prompt:GetAttribute("HwTargetUserId")) or 0)
		ui.Hold = { Prompt = prompt, Start = os.clock(), Duration = prompt.HoldDuration, Name = target and target.DisplayName or "" }
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		if ui and ui.Hold and ui.Hold.Prompt == prompt then
			ui.Hold = nil
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if ui and ui.Hold and ui.Hold.Prompt == prompt then
			ui.Hold = nil
		end
	end)

	task.defer(sync)
end

return CombatHUD
