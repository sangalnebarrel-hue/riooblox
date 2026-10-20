-- NIGHT OF THE BURIED MOON first-visit guide (StarterPlayerScripts.HalloweenClient.Onboarding).
-- Starts the first time the player is inside THE DEAD YARD while View.Onboarded == false (and the main DOGROTS tutorial
-- is not running): 7 short cards (Moon Candy, the Curse, Haunted Dig Spots, Trick or Treat, the Blood Moon, the
-- Gravekeeper, the Event DogDex). Each card can focus the camera on its place (moderate tweens, cuts with reduced
-- motion), puts a world beacon + bouncing arrow there, outlines the model (Highlight) and rings the matching HUD
-- element (Bus "HUDFocus"). NEXT / SKIP; the end sends Request "Onboarded". Bus "Onboarding" {Replay = true} (HOW TO
-- PLAY in the window) shows it again. The card hides while a menu, a modal or the main tutorial is open.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local O = {}

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local PUMPKIN = C(255, 128, 24)
local PUMPKIN_HI = C(255, 176, 74)
local SOFT = C(226, 212, 248)
local INK = C(16, 8, 26)
local V = Vector3.new

-- Shots are {Eye, Focus} in world space (THE DEAD YARD layout); nil keeps the camera on the player.
local function steps(L)
	local moon = L.Moon and L.Moon.Position or V(380, 150, 650)
	local bell = L.Bell and L.Bell.Position or V(146, 0.5, 636)
	local cauldron = L.Cauldron and L.Cauldron.Center or V(128, 0.2, 612)
	local dig = (L.DigPoints and L.DigPoints[8]) or V(68, 0.2, 640)
	return {
		{ Key = "Candy", Glyph = "🍬", Title = "MOON CANDY", Body = "Everything you do in the Dead Yard drops candy. Watch it fly into your counter at the top.",
			Focus = "Candy", Shot = { Eye = V(52, 46, 548), Focus = V(128, 0, 640) } },
		{ Key = "Curse", Glyph = "💀", Title = "THE CURSE", Body = "Standing around raises your curse. Keep digging, mining and fighting: a high curse means less candy.",
			Focus = "Curse", Shot = { Eye = V(52, 46, 548), Focus = V(128, 0, 640) } },
		{ Key = "Spots", Glyph = "🪦", Title = "HAUNTED DIG SPOTS", Body = "During the Blood Moon cursed graves rise in the graveyard. Dig them with your pickaxe for candy and rare finds.",
			Shot = { Eye = dig + V(30, 26, -34), Focus = dig }, Marker = dig, Model = "Graveyard" },
		{ Key = "Cauldron", Glyph = "🧪", Title = "TRICK OR TREAT", Body = "Throw candy into the Haunted Cauldron for Pumpkin Lucky Blocks, or brew a big reward. Knock on the 7 doors once a day.",
			Shot = { Eye = cauldron + V(34, 22, 24), Focus = cauldron + V(-8, 3, -26) }, Marker = cauldron + V(0, 6, 0), Model = "Cauldron" },
		{ Key = "BloodMoon", Glyph = "🌕", Title = "THE BLOOD MOON", Body = "About every 15 minutes the moon turns red: +50% candy and haunted dig spots. The timer is at the top of your screen.",
			Focus = "Strip", Shot = { Eye = V(96, 8, 640), Focus = moon } },
		{ Key = "Boss", Glyph = "🔔", Title = "THE GRAVEKEEPER", Body = "Ring the Grave Bell at the pit to wake the boss. Beat him to unlock harder difficulties and better loot.",
			Shot = { Eye = V(128, 28, 612), Focus = V(134, -4, 668) }, Marker = bell + V(0, 5, 0), Model = "Pit" },
		{ Key = "Dex", Glyph = "📖", Title = "EVENT DOGDEX", Body = "8 Halloween dogs are hiding in pumpkins, brews and boss loot. Quests, the cauldron and everything else are in the HALLOWEEN menu.",
			Focus = "Tile", Final = true },
	}
end

function O.Start(ctx)
	if O.Started then
		return
	end
	O.Started = true
	local player = ctx.Player or Players.LocalPlayer
	local Bus, State, Shared = ctx.Bus, ctx.State, ctx.Shared
	local Layout = ctx.Layout or (Shared and Shared.Layout) or {}
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("ScreenGui", 60)
	if not gui then
		return
	end
	local modules = gui:WaitForChild("Modules", 30)
	local Kit = require(modules:WaitForChild("Kit"))
	local Dict = { UI = {}, Templates = {} }
	do
		local folder = RS:FindFirstChild("Localization")
		local m = folder and folder:FindFirstChild("Halloween")
		if m then
			local ok, d = pcall(require, m)
			if ok and type(d) == "table" then
				Dict = d
			end
		end
	end
	local function T(en)
		return Kit.Lang() == "ru" and (Dict.UI[en] or Dict.Exact and Dict.Exact[en]) or en
	end
	local function reduced()
		return Kit.Motion.Reduced() or (Shared and Shared.ReducedMotion())
	end
	local STEPS = steps(Layout)
	O.Steps = STEPS

	-- state
	local step = 0
	local running = false
	local replay = false
	local saved = nil -- camera before the guide
	local marker, beacon, highlight = nil, nil, nil

	------------------------------------------------------------------------------------------------------------------
	-- card (own ScreenGui above the HUD, below kit windows; hidden with menus / HIDE UI)
	------------------------------------------------------------------------------------------------------------------
	local layer = Kit.New("ScreenGui", { Name = "DOGROTS_HalloweenGuide", ResetOnSpawn = false, DisplayOrder = 45, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	pcall(function()
		layer.IgnoreGuiInset = true
		layer.ScreenInsets = Enum.ScreenInsets.None
	end)
	layer:SetAttribute("HideWithUI", true)
	layer:SetAttribute("NoTranslate", true)
	local card = Kit.New("Frame", { Name = "HalloweenGuide", AnchorPoint = Vector2.new(0.5, 1), BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 2 }, layer)
	Kit.Corner(card, 18)
	Kit.Stroke(card, PUMPKIN, 3, 0)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(76, 36, 112), C(28, 10, 44)) }, card)
	local pop = Kit.New("UIScale", { Name = "Pop" }, card)
	local glyphCircle = Kit.New("Frame", { Name = "Icon", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 3 }, card)
	Kit.Corner(glyphCircle, "pill")
	Kit.Stroke(glyphCircle, INK, 2, 0.1)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(255, 186, 96), C(196, 82, 12)) }, glyphCircle)
	local glyph = Kit.Text(glyphCircle, { Name = "Glyph", Text = "🎃", TextSize = 60, Scaled = true, MinTextSize = 8, AlignX = "Center", NoTranslate = true, ZIndex = 4,
		Position = UDim2.fromScale(0.14, 0.14), Size = UDim2.fromScale(0.72, 0.72) })
	local kicker = Kit.Text(card, { Name = "Kicker", Text = "", TextSize = 13, Scaled = true, MinTextSize = 8, Color = PUMPKIN_HI, NoTranslate = true, ZIndex = 3 })
	local title = Kit.Text(card, { Name = "Title", Text = "", TextSize = 24, Scaled = true, MinTextSize = 12, Color = WHITE, Stroke = 0.3, NoTranslate = true, ZIndex = 3 })
	local body = Kit.Text(card, { Name = "Body", Text = "", TextSize = 16, Wrap = true, AlignY = "Top", Color = SOFT, NoTranslate = true, ZIndex = 3 })
	local dots = {}
	for i = 1, #STEPS do
		local d = Kit.New("Frame", { Name = "Dot" .. i, BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 3 }, card)
		Kit.Corner(d, "pill")
		dots[i] = d
	end
	local nextBtn = Kit.Button(card, { Name = "Next", Text = T("NEXT"), Color = PUMPKIN, TextSize = 17, NoTranslate = true, ZIndex = 4 })
	local skipBtn = Kit.Button(card, { Name = "Skip", Text = T("SKIP"), Style = "ghost", TextSize = 15, NoTranslate = true, ZIndex = 4 })
	skipBtn.Caption.TextColor3 = SOFT
	layer.Parent = playerGui
	O.Card = card

	local function layout()
		local Base = require(modules.Kit.Base)
		local sx, sy, sw, sh = Base.SafeArea(layer)
		local touch = UserInputService.TouchEnabled
		local landscape = sw > sh * 1.25
		local small = math.min(sw, sh) < 500
		local w = math.min(small and (landscape and 440 or sw - 24) or 540, sw - 24)
		local h = small and (landscape and 128 or 196) or 182
		-- the card grows when the step's text needs another line (Russian runs ~20% longer)
		do
			local portrait = small and not landscape
			local iconW = (small and landscape) and 52 or 72
			local bodyW = portrait and (w - 32) or (w - iconW - 28 - 14)
			local bodyY = portrait and 98 or ((small and landscape) and 48 or 64)
			local bodySize = (small and landscape) and 13 or (small and 14 or 16)
			local btnH = (small and landscape) and 36 or 42
			local ok, size = pcall(function()
				return game:GetService("TextService"):GetTextSize(body.Text, bodySize, Enum.Font.FredokaOne, Vector2.new(math.max(40, bodyW), 1000))
			end)
			if ok and size then
				h = math.max(h, bodyY + math.ceil(size.Y) + 4 + btnH + 14)
			end
		end
		local bottom = touch and (not landscape and small and 235 or (small and 12 or 28)) or 26
		local cx = sx + sw / 2
		if small and landscape then
			-- phone landscape: centre the card in the HUD's free zone, clear of the left rail and the right buttons
			local innerL, innerR = gui:GetAttribute("HUDInnerLeft"), gui:GetAttribute("HUDInnerRight")
			if type(innerL) == "number" and type(innerR) == "number" and innerR - innerL >= w + 16 then
				local ox = gui.AbsolutePosition.X - layer.AbsolutePosition.X
				cx = math.clamp(ox + (innerL + innerR) / 2, sx + w / 2 + 12, sx + sw - w / 2 - 12)
			end
		end
		card.Position = UDim2.fromOffset(cx, sy + sh - bottom)
		card.Size = UDim2.fromOffset(w, h)
		local compact = small and landscape
		local icon = compact and 52 or 72
		glyphCircle.Position, glyphCircle.Size = UDim2.fromOffset(14, compact and 14 or 18), UDim2.fromOffset(icon, icon)
		local tx = icon + 28
		kicker.Position, kicker.Size = UDim2.fromOffset(tx, compact and 8 or 14), UDim2.fromOffset(w - tx - 14, 16)
		title.Position, title.Size = UDim2.fromOffset(tx, compact and 22 or 30), UDim2.fromOffset(w - tx - 14, compact and 24 or 30)
		local textLimit = title:FindFirstChildWhichIsA("UITextSizeConstraint")
		if textLimit then
			textLimit.MaxTextSize = compact and 19 or 24
		end
		body.TextSize = compact and 13 or (small and 14 or 16)
		local btnH = compact and 36 or 42
		local bodyY = compact and 48 or 64
		body.Position, body.Size = UDim2.fromOffset(tx, bodyY), UDim2.fromOffset(w - tx - 14, h - bodyY - btnH - 14)
		if small and not landscape then
			-- portrait: the text under the icon row, full width
			body.Position, body.Size = UDim2.fromOffset(16, 98), UDim2.fromOffset(w - 32, h - 98 - btnH - 16)
		end
		local nw = compact and 120 or 150
		nextBtn.Instance.Position, nextBtn.Instance.Size = UDim2.fromOffset(w - nw - 12, h - btnH - 10), UDim2.fromOffset(nw, btnH)
		-- SKIP as wide as its word (ПРОПУСТИТЬ is twice SKIP)
		local skipSize = compact and 13 or 15
		skipBtn.Caption.TextSize = skipSize
		local okW, size = pcall(function()
			return game:GetService("TextService"):GetTextSize(skipBtn.Caption.Text, skipSize, Enum.Font.FredokaOne, Vector2.new(1000, 100))
		end)
		local sw = math.clamp(math.ceil((okW and size.X or #skipBtn.Caption.Text * skipSize * 0.6)) + 30, 84, 170)
		local skipX = w - nw - 12 - sw - 6
		skipBtn.Instance.Position, skipBtn.Instance.Size = UDim2.fromOffset(skipX, h - btnH - 10), UDim2.fromOffset(sw, btnH)
		local dw, gap = compact and 14 or 18, 6
		if 16 + #dots * (dw + gap) + 6 > skipX then
			dw, gap = 8, 4 -- narrow card: smaller progress dots
		end
		-- no room left of SKIP (phone portrait, Russian): the kicker's "n / 7" already says where we are
		local roomForDots = 16 + #dots * (dw + gap) + 6 <= skipX
		for i, d in ipairs(dots) do
			d.Position = UDim2.fromOffset(16 + (i - 1) * (dw + gap), h - btnH / 2 - 14)
			d.Size = UDim2.fromOffset(dw, 6)
			d.Visible = roomForDots
		end
	end
	layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(layout)
	end)

	------------------------------------------------------------------------------------------------------------------
	-- world beacon / marker / highlight, camera
	------------------------------------------------------------------------------------------------------------------
	local function clearWorld()
		for _, o in ipairs({ marker, beacon, highlight }) do
			if o then
				o:Destroy()
			end
		end
		marker, beacon, highlight = nil, nil, nil
	end
	local function fxFolder()
		local FX = ctx.FX
		if FX and FX.Folder then
			local ok, f = pcall(FX.Folder)
			if ok and f then
				return f
			end
		end
		return workspace
	end
	local function showWorld(s)
		clearWorld()
		if s.Marker then
			local anchor = Instance.new("Part")
			anchor.Name = "HalloweenGuideMarker"
			anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
			anchor.Transparency = 1
			anchor.Size = V(1, 1, 1)
			anchor.CFrame = CFrame.new(s.Marker)
			local bb = Instance.new("BillboardGui")
			bb.Name = "Arrow"
			bb.AlwaysOnTop = true
			bb.Size = UDim2.fromOffset(150, 110)
			bb.StudsOffset = V(0, 6, 0)
			bb.MaxDistance = 400
			bb.LightInfluence = 0
			bb:SetAttribute("NoTranslate", true)
			local tag = Kit.Text(bb, { Name = "Label", Text = T(s.Title), TextSize = 20, Scaled = true, MinTextSize = 10, AlignX = "Center", Color = PUMPKIN_HI,
				NoTranslate = true, Size = UDim2.new(1, 0, 0, 30) })
			local tagStroke = Instance.new("UIStroke")
			tagStroke.Color = INK
			tagStroke.Thickness = 2
			tagStroke.Parent = tag
			local arrow = Kit.Text(bb, { Name = "Arrow", Text = "⬇️", TextSize = 60, Scaled = true, MinTextSize = 10, AlignX = "Center", NoTranslate = true,
				Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 70) })
			bb.Parent = anchor
			anchor.Parent = fxFolder()
			marker = anchor
			if not reduced() then
				TweenService:Create(arrow, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 44) }):Play()
			end
			-- beacon: a soft column of light where to go
			local col = Instance.new("Part")
			col.Name = "HalloweenGuideBeacon"
			col.Anchored, col.CanCollide, col.CanQuery, col.CanTouch, col.CastShadow = true, false, false, false, false
			col.Material = Enum.Material.Neon
			col.Color = PUMPKIN
			col.Shape = Enum.PartType.Cylinder
			col.Size = V(60, 2.2, 2.2)
			col.CFrame = CFrame.new(s.Marker + V(0, 26, 0)) * CFrame.Angles(0, 0, math.rad(90))
			col.Transparency = 0.6
			col.Parent = fxFolder()
			beacon = col
		end
		if s.Model then
			local district = workspace:FindFirstChild("DOGROTS_District")
			local yard = district and district:FindFirstChild("38_DeadYard")
			local model = yard and yard:FindFirstChild(s.Model)
			if model then
				local hl = Instance.new("Highlight")
				hl.Name = "HalloweenGuideHighlight"
				hl.FillTransparency = 1
				hl.OutlineColor = PUMPKIN
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.Occluded
				hl.Adornee = model
				hl.Parent = fxFolder()
				highlight = hl
			end
		end
	end

	local controls = nil
	local function setControls(on)
		pcall(function()
			if not controls then
				local mod = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
				controls = mod and require(mod):GetControls()
			end
			if controls then
				if on then
					controls:Enable()
				else
					controls:Disable()
				end
			end
		end)
	end
	local camTween = nil
	local function cameraTo(cf, instant)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		if camTween then
			camTween:Cancel()
			camTween = nil
		end
		if instant or reduced() then
			cam.CFrame = cf
			return
		end
		camTween = TweenService:Create(cam, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = cf })
		camTween:Play()
	end
	local function shot(s)
		local cam = workspace.CurrentCamera
		if not cam or not s.Shot or not (State and State.InZone and State.InZone()) then
			return false
		end
		if not saved then
			saved = { Type = cam.CameraType, Subject = cam.CameraSubject, CFrame = cam.CFrame }
			cam.CameraType = Enum.CameraType.Scriptable
			setControls(false)
		end
		cameraTo(CFrame.lookAt(s.Shot.Eye, s.Shot.Focus))
		return true
	end
	local function restoreCamera(instant)
		local cam = workspace.CurrentCamera
		if not saved or not cam then
			return
		end
		local back = saved
		saved = nil
		local function finish()
			if camTween then
				camTween:Cancel()
				camTween = nil
			end
			cam.CameraType = back.Type == Enum.CameraType.Scriptable and Enum.CameraType.Custom or back.Type
			if back.Subject then
				cam.CameraSubject = back.Subject
			end
			setControls(true)
		end
		if instant or reduced() then
			cam.CFrame = back.CFrame
			finish()
			return
		end
		cameraTo(back.CFrame)
		task.delay(1.35, finish)
	end

	------------------------------------------------------------------------------------------------------------------
	-- flow
	------------------------------------------------------------------------------------------------------------------
	local function blocked()
		return gui:GetAttribute("OpenMenu") ~= nil or (gui:GetAttribute("ModalOwnerCount") or 0) > 0 or player:GetAttribute("TutorialActive") == true
			or gui:GetAttribute("UIHidden") == true
	end
	local function render()
		local s = STEPS[step]
		if not s then
			return
		end
		glyph.Text = s.Glyph
		kicker.Text = string.format("%s · %d / %d", T("NIGHT OF THE BURIED MOON"), step, #STEPS)
		title.Text = T(s.Title)
		body.Text = T(s.Body)
		nextBtn:SetText(s.Final and T("LET'S GO!") or T("NEXT"))
		skipBtn.Instance.Visible = not s.Final
		for i, d in ipairs(dots) do
			d.BackgroundColor3 = i == step and PUMPKIN or (i < step and C(196, 160, 240) or C(112, 82, 152))
		end
		layout()
	end
	local function show(on)
		layer.Enabled = on
		if not on then
			Bus.Fire("HUDFocus", { Key = nil })
		end
	end
	local function enter(i)
		step = i
		local s = STEPS[i]
		if not s then
			return
		end
		render()
		Bus.Fire("HUDFocus", { Key = s.Focus })
		-- the controls are locked while a card is up: the server holds the curse for one card (first visit only, bounded)
		if not replay and State and State.Request then
			task.spawn(State.Request, "OnboardingStep", {})
		end
		local moved = shot(s)
		if not moved and saved then
			restoreCamera(false)
		end
		showWorld(s)
		if not reduced() then
			pop.Scale = 0.92
			TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		local A = ctx.Audio
		if A and A.Play then
			pcall(A.Play, i == 1 and "Unlock" or "UiTab")
		end
	end
	local function finish(skipped)
		if not running then
			return
		end
		running = false
		show(false)
		clearWorld()
		restoreCamera(false)
		Bus.Fire("HUDFocus", { Key = nil })
		local v = State and State.View
		if not replay and not (v and v.Onboarded) and State and State.Request then
			task.spawn(State.Request, "Onboarded", {})
		end
		replay = false
		if not skipped then
			local A = ctx.Audio
			if A and A.Play then
				pcall(A.Play, "Claim")
			end
		end
	end
	function O.Begin(isReplay)
		if running then
			return
		end
		running = true
		replay = isReplay == true
		show(not blocked())
		enter(1)
	end
	function O.Next()
		if not running then
			return
		end
		if step >= #STEPS then
			finish(false)
			-- the last card hands over to the window (Event DogDex tab)
			Bus.Fire("OpenWindow", { Tab = "dex" })
			return
		end
		enter(step + 1)
	end
	function O.Skip()
		finish(true)
	end
	function O.Running()
		return running
	end
	function O.Step()
		return step
	end
	nextBtn:SetOnClick(O.Next)
	skipBtn:SetOnClick(O.Skip)

	-- pause while a menu, a modal or the main tutorial is open (the camera goes back to the player meanwhile)
	local function visibility()
		if not running then
			return
		end
		local hide = blocked()
		if hide and layer.Enabled then
			show(false)
			clearWorld()
			restoreCamera(true)
		elseif not hide and not layer.Enabled then
			show(true)
			enter(step)
		end
	end
	for _, a in ipairs({ "OpenMenu", "ModalOwnerCount", "UIHidden" }) do
		gui:GetAttributeChangedSignal(a):Connect(visibility)
	end
	player:GetAttributeChangedSignal("TutorialActive"):Connect(visibility)
	player.CharacterRemoving:Connect(function()
		if running then
			clearWorld()
			restoreCamera(true)
		end
	end)

	-- when to start: first time inside the Dead Yard with Onboarded == false
	local function maybeStart()
		if running or O.Done then
			return
		end
		local v = State and State.View
		if not v or v.Onboarded ~= false then
			return
		end
		local inside = State.InZone and State.InZone()
		if not inside or player:GetAttribute("TutorialActive") == true then
			return
		end
		O.Done = true
		task.delay(1.5, function()
			O.Begin(false)
		end)
	end
	Bus.On("ZoneChanged", function(d)
		if d and d.Inside then
			maybeStart()
		end
	end)
	Bus.On("StateChanged", maybeStart)
	Bus.On("Ready", maybeStart)
	Bus.On("Onboarding", function(d)
		if type(d) == "table" and d.Replay then
			task.delay(0.4, function()
				O.Begin(true)
			end)
		end
	end)
	player:GetAttributeChangedSignal("TutorialActive"):Connect(maybeStart)
	task.defer(maybeStart)
end

return O
