-- THE BLACK BELL ASSAULT · client (StarterPlayerScripts.HalloweenClient.Trials.Assault, WP-J; DESIGN §8.6, §24.1, §24.4).
-- The server raid (Resonance.luau) replicates RS.Halloween.State.Assault {State "" | "Countdown" | "Active" | "Won" |
-- "Failed", StartsAt, EndsAt, HP, MaxHP, Attackers, Waiting}; every raider runs a solo Seals trial "Assault" (so the
-- Trials host starts this presenter for them). The Bellkeeper, its rope and tolls are drawn by Trials.Bell (arena layer).
-- This module (boots once, like Trials.Resonance; Init / Start or on its own):
--   * the RAID BAR (own ScreenGui "DOGROTS_Assault", DisplayOrder 46, HideWithUI): THE BELLKEEPER, HP bar with the
--     three phase marks, time left, raiders, YOUR HITS n / MinHits (player attribute UyAssaultHits). Shown while the raid
--     is active and you are in the Black Bell Arena or raiding; the result (fell / held) for a few seconds after.
--     Placed under the resonance meter (main ScreenGui attribute HwResonanceBottom) or the HUD strip; phone layout.
--   * the last five seconds of the countdown as big numbers (in the Underyard), with a tick.
--   * the ARENA BEACON: a violet pillar of light over the arena during the countdown and the raid (in the Underyard).
--   * THE BELL FALLS (Won, near the arena): the Black Bell drops from the gallows onto the arena floor — a client copy
--     falls while the real bell is hidden locally (LocalTransparencyModifier, its lights off); both restored when the
--     result ends. ReducedMotion: no fall, no shakes.
--   * C2Resonance "Reward" {Won, Hits}: a short toast (the reward rows themselves arrive through the reward UI).
-- Announcements (C2Announce Kind "Assault") are the HUD's (WP-L), not shown here.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals2View"))

local P = { Ids = { "Assault" }, Always = true }

local player = Players.LocalPlayer
local L = View.L
local Cfg = View.Config
local AC = Cfg.Resonance.Assault
local CC = Cfg.Client
local Layout = View.Layout
local V3 = Vector3.new
local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = RGB(16, 12, 26)
local DEEP = RGB(34, 18, 52)
local VIOLET = RGB(150, 80, 230)
local VIOLET_HI = RGB(196, 150, 255)
local BLOOD = RGB(232, 72, 96)
local GOLD = RGB(255, 210, 110)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

local ctx: any = nil
local booted = false

local function audio(cue: string, where: any?, opts: any?)
	local a = ctx and ctx.Audio
	if a and a.Play then
		pcall(a.Play, cue, where, opts)
	end
end

local function fx(name: string, ...: any)
	local f = ctx and ctx.FX
	local fn = f and f[name]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

local function num(v: any, d: number?): number
	return tonumber(v) or d or 0
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds + .5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function assaultFolder(): Instance?
	local st = Halloween:FindFirstChild("State")
	return st and st:FindFirstChild("Assault") or nil
end

local function aState(): string
	local f = assaultFolder()
	local s = f and f:GetAttribute("State")
	return type(s) == "string" and s or ""
end

local function raiding(): boolean
	local trial = player:GetAttribute("UyTrial")
	return type(trial) == "string" and string.sub(trial, 1, 8) == "Assault:"
end

local function inArena(): boolean
	return player:GetAttribute("UyInZone") == true and player:GetAttribute("UyDistrict") == "BlackBellArena"
end

---------------------------------------------------------------------------------------------------------------------
-- the raid bar
---------------------------------------------------------------------------------------------------------------------
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local o: any = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local p = table.clone(props)
	p.BackgroundTransparency = 1
	p.FontFace = FONT
	p.TextColor3 = p.TextColor3 or WHITE
	local l = new("TextLabel", p, parent)
	l:SetAttribute("NoTranslate", true)
	new("UIStroke", { Color = INK, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	return l
end

local function build(main: ScreenGui): any
	local u: any = {}
	local gui = new("ScreenGui", { Name = "DOGROTS_Assault", DisplayOrder = 46, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = main.IgnoreGuiInset, Enabled = false })
	pcall(function()
		gui.ScreenInsets = main.ScreenInsets
	end)
	gui:SetAttribute("HideWithUI", true)
	gui:SetAttribute("NoTranslate", true)
	u.Gui = gui
	local card = new("Frame", { Name = "RaidCard", AnchorPoint = Vector2.new(.5, 0), BackgroundColor3 = DEEP, BackgroundTransparency = .1,
		BorderSizePixel = 0, Active = false, Visible = false }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	u.Stroke = new("UIStroke", { Color = BLOOD, Thickness = 2 }, card)
	u.Card = card
	u.Title = label(card, { Name = "Title", Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, TextColor3 = VIOLET_HI })
	u.Time = label(card, { Name = "Time", Text = "", TextXAlignment = Enum.TextXAlignment.Right, TextScaled = true })
	local track = new("Frame", { Name = "Track", BackgroundColor3 = INK, BorderSizePixel = 0 }, card)
	new("UICorner", { CornerRadius = UDim.new(.5, 0) }, track)
	u.Track = track
	local fill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, track)
	new("UICorner", { CornerRadius = UDim.new(.5, 0) }, fill)
	new("UIGradient", { Color = ColorSequence.new(BLOOD, VIOLET) }, fill)
	u.Fill = fill
	u.Marks = {}
	for i, ph in ipairs(AC.Phases) do
		if ph.Above and ph.Above > 0 then
			local m = new("Frame", { Name = "PhaseMark" .. i, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(ph.Above, .5),
				Size = UDim2.new(0, 2, 1, 4), BackgroundColor3 = WHITE, BackgroundTransparency = .25, BorderSizePixel = 0, ZIndex = 3 }, track)
			table.insert(u.Marks, m)
		end
	end
	u.HP = label(track, { Name = "HP", Text = "", Size = UDim2.fromScale(1, 1), TextScaled = true, ZIndex = 4 })
	u.Info = label(card, { Name = "Info", Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, TextColor3 = RGB(226, 212, 248) })
	-- the countdown numbers (centre screen, never input-sinking)
	u.Count = label(gui, { Name = "Countdown", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .38), Size = UDim2.fromOffset(220, 120),
		Text = "", TextScaled = true, TextColor3 = VIOLET_HI, Visible = false })
	u.CountSub = label(gui, { Name = "CountdownSub", AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, .38, 64),
		Size = UDim2.fromOffset(420, 28), Text = "", TextScaled = true, Visible = false })
	gui.Parent = main.Parent
	return u
end

local function layout(u: any, main: ScreenGui)
	local size = main.AbsoluteSize
	local W, H = size.X, size.Y
	if W <= 0 or H <= 0 then
		return
	end
	local phone = W < 700 or H < 500
	local left = tonumber(main:GetAttribute("HUDInnerLeft")) or 12
	local right = tonumber(main:GetAttribute("HUDInnerRight")) or (W - 12)
	if right - left < 220 then
		left, right = 12, W - 12
	end
	local w = math.floor(math.min(phone and 270 or 380, right - left - 16, W - 24))
	local h = phone and 54 or 58
	local cx = math.floor((left + right) / 2)
	local top = tonumber(main:GetAttribute("HwResonanceBottom"))
	if not top or top <= 0 then
		top = tonumber(main:GetAttribute("HwStripBottom"))
	end
	if not top or top <= 0 then
		top = (tonumber(main:GetAttribute("HUDFreeTop")) or (phone and 56 or 72)) + 2
	end
	local y = math.floor(top + 6)
	u.Card.Position = UDim2.fromOffset(cx, y)
	u.Card.Size = UDim2.fromOffset(w, h)
	local pad = phone and 8 or 10
	local titleH = phone and 13 or 15
	u.Title.Position = UDim2.fromOffset(pad, 4)
	u.Title.Size = UDim2.fromOffset(math.floor(w * .68) - pad, titleH)
	u.Time.Position = UDim2.fromOffset(math.floor(w * .68), 4)
	u.Time.Size = UDim2.fromOffset(math.floor(w * .32) - pad, titleH)
	local trackH = phone and 14 or 16
	local trackY = 4 + titleH + 4
	u.Track.Position = UDim2.fromOffset(pad, trackY)
	u.Track.Size = UDim2.fromOffset(w - pad * 2, trackH)
	local infoY = trackY + trackH + 3
	u.Info.Position = UDim2.fromOffset(pad, infoY)
	u.Info.Size = UDim2.fromOffset(w - pad * 2, math.max(9, h - infoY - 3))
	u.Count.Size = UDim2.fromOffset(phone and 150 or 220, phone and 90 or 120)
	u.CountSub.Size = UDim2.fromOffset(math.min(W - 24, 420), phone and 22 or 28)
	u.CountSub.Position = UDim2.new(.5, 0, .38, phone and 48 or 64)
	u.Laid = size
end

local function refresh(u: any)
	local f = assaultFolder()
	local state = aState()
	local now = View.Shared.Now()
	local hp, max = num(f and f:GetAttribute("HP"), 0), math.max(1, num(f and f:GetAttribute("MaxHP"), 1))
	local frac = math.clamp(hp / max, 0, 1)
	local hits = math.floor(num(player:GetAttribute("UyAssaultHits"), 0))
	local raiders = math.floor(num(f and f:GetAttribute("Attackers"), 0))
	local narrow = u.Card.AbsoluteSize.X < 330
	u.Title.Text = narrow and L("THE BELLKEEPER", "ЗВОНАРЬ") or L("THE BELLKEEPER · BLACK BELL ASSAULT", "ЗВОНАРЬ · ШТУРМ ЧЁРНОГО КОЛОКОЛА")
	if state == "Active" then
		u.Fill.Size = UDim2.fromScale(frac, 1)
		u.HP.Text = string.format("%d%%", math.ceil(frac * 100 - 1e-6))
		u.Time.Text = clock(num(f and f:GetAttribute("EndsAt"), now) - now)
		local mine = hits >= AC.MinHits and (L("YOUR HITS", "ТВОИ УДАРЫ") .. " " .. hits .. " ✓")
			or (L("YOUR HITS", "ТВОИ УДАРЫ") .. " " .. hits .. " / " .. AC.MinHits)
		u.Info.Text = L("RAIDERS", "ШТУРМУЮТ") .. " " .. raiders .. "  ·  " .. mine
		u.Stroke.Color = BLOOD
	elseif state == "Won" then
		u.Fill.Size = UDim2.fromScale(0, 1)
		u.HP.Text = ""
		u.Time.Text = ""
		u.Info.Text = L("THE BLACK BELL FALLS", "ЧЁРНЫЙ КОЛОКОЛ ПАДАЕТ")
		u.Stroke.Color = GOLD
	elseif state == "Failed" then
		u.Fill.Size = UDim2.fromScale(frac, 1)
		u.HP.Text = string.format("%d%%", math.ceil(frac * 100 - 1e-6))
		u.Time.Text = "0:00"
		u.Info.Text = L("THE BELL HELD", "КОЛОКОЛ УСТОЯЛ")
		u.Stroke.Color = VIOLET
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the arena beacon
---------------------------------------------------------------------------------------------------------------------
local beacon: any = nil

local function setBeacon(on: boolean)
	if on and not beacon then
		local c = Layout.Arena.Centre
		local parts = {}
		local function pillar(d: number, transparency: number, color: Color3)
			local p = Instance.new("Part")
			p.Name = "AssaultBeacon"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Shape = Enum.PartType.Cylinder
			p.Material = Enum.Material.Neon
			p.Color = color
			p.Transparency = transparency
			p.Size = V3(260, d, d)
			p.CFrame = CFrame.new(c + V3(0, 130 + 60, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			p.Parent = View.Folder()
			table.insert(parts, p)
		end
		pillar(5, .45, VIOLET_HI)
		pillar(12, .8, VIOLET)
		beacon = { Parts = parts, T0 = os.clock() }
	elseif not on and beacon then
		for _, p in ipairs(beacon.Parts) do
			p:Destroy()
		end
		beacon = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- THE BELL FALLS
---------------------------------------------------------------------------------------------------------------------
local drop: any = nil -- {Clone, Hidden = {{Part, LTM}}, Lights = {{Light, Enabled}}}

local function realBell(): Model?
	local root = View.Root()
	local arena = root and root:FindFirstChild("BlackBellArena")
	local bell = arena and arena:FindFirstChild("BlackBell")
	return bell and bell:IsA("Model") and bell or nil
end

local function restoreBell()
	local d = drop
	drop = nil
	if not d then
		return
	end
	if d.Anim then
		d.Anim.Stop(false)
	end
	for _, h in ipairs(d.Hidden) do
		if h.Part.Parent then
			h.Part.LocalTransparencyModifier = h.LTM
		end
	end
	for _, l in ipairs(d.Lights) do
		if l.Light.Parent then
			l.Light.Enabled = l.Enabled
		end
	end
	if d.Clone then
		local clone = d.Clone
		local parts = {}
		for _, x in ipairs(clone:GetDescendants()) do
			if x:IsA("BasePart") then
				table.insert(parts, { Part = x, T = x.Transparency })
			end
		end
		View.Animate(.8, function(a)
			for _, e in ipairs(parts) do
				e.Part.Transparency = e.T + (1 - e.T) * a
			end
		end, function()
			clone:Destroy()
		end)
	end
end

local function bellFalls()
	if drop or View.Reduced() then
		audio("BellTollHuge", Layout.Arena.Bell, { Volume = 1, Pitch = .6 })
		return
	end
	local cam = workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - Layout.Arena.Centre).Magnitude > CC.ArenaRange then
		return
	end
	local bell = realBell()
	if not bell then
		return
	end
	local okC, clone = pcall(function()
		return bell:Clone()
	end)
	if not okC or not clone then
		return
	end
	local d: any = { Clone = clone, Hidden = {}, Lights = {} }
	drop = d
	for _, x in ipairs(clone:GetDescendants()) do
		if x:IsA("BasePart") then
			x.Anchored = true
			x.CanCollide = false
			x.CanQuery = false
			x.CanTouch = false
		end
	end
	for _, a in ipairs({ "UySwing", "UySwingAmp", "UySwingPeriod" }) do
		clone:SetAttribute(a, nil)
	end
	clone.Name = "FallingBlackBell"
	clone.Parent = View.Folder()
	for _, x in ipairs(bell:GetDescendants()) do
		if x:IsA("BasePart") then
			table.insert(d.Hidden, { Part = x, LTM = x.LocalTransparencyModifier })
			x.LocalTransparencyModifier = 1
		elseif x:IsA("Light") then
			table.insert(d.Lights, { Light = x, Enabled = x.Enabled })
			x.Enabled = false
		end
	end
	local from = bell:GetPivot()
	-- the crown sits ~22.8 above the lip: land the lip on the floor, tipped a little
	local lipDrop = from.Position.Y - 22.8 - Layout.Arena.Centre.Y
	local to = CFrame.new(from.Position - V3(0, lipDrop, 0)) * CFrame.Angles(.12, .4, .08)
	audio("BellCreak", from.Position, { Volume = 1 })
	audio("ChainBreak", from.Position, { Volume = 1, Pitch = .7 })
	d.Anim = View.Animate(1.15, function(a)
		local k = a * a
		clone:PivotTo(from:Lerp(to, k))
	end, function()
		d.Anim = nil
		local ground = Layout.Arena.Centre + V3(0, .3, 0)
		audio("BellTollHuge", ground + V3(0, 10, 0), { Volume = 1, Pitch = .55 })
		audio("BossSlam", ground, { Volume = 1, Pitch = .7 })
		fx("Shockwave", ground, VIOLET, 46, 1.4)
		fx("Burst", ground + V3(0, 2, 0), { Color = RGB(120, 110, 130), Color2 = VIOLET, Count = 60, Speed = { 12, 30 }, Spread = 80,
			Direction = V3(0, 1, 0), Lifetime = { .8, 1.6 }, Size = { 1.5, 3, 0 } })
		fx("Light", ground + V3(0, 8, 0), VIOLET_HI, 80, 4, 1.6)
		local cinema = ctx and ctx.Modules and ctx.Modules.Cinema
		if cinema and cinema.Shake then
			pcall(cinema.Shake, 1, .9)
		else
			fx("Shake", 1, .9)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- boot
---------------------------------------------------------------------------------------------------------------------
local function boot(c: any?)
	if booted then
		return
	end
	booted = true
	ctx = View.Ctx(c)
	local Shared = View.Shared
	if not Shared.Chapter2Enabled() then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui")
	local main = playerGui:WaitForChild("ScreenGui", 60)
	if not main then
		return
	end
	local u: any = nil
	local okBuild, err = pcall(function()
		u = build(main)
		layout(u, main)
	end)
	if not okBuild then
		warn("Trials.Assault: build failed: " .. tostring(err))
		if u and u.Gui then
			u.Gui:Destroy()
		end
		return
	end
	local lastState = aState()
	local lastCount = -1
	local resultUntil = 0
	local function apply()
		if not u.Gui.Parent then
			u.Gui.Parent = playerGui
		end
		local state = aState()
		if state ~= lastState then
			local was = lastState
			lastState = state
			if state == "Won" then
				resultUntil = os.clock() + AC.ResultHold
				pcall(bellFalls)
			elseif state == "Failed" then
				resultUntil = os.clock() + AC.ResultHold
				if inArena() then
					audio("TrialFail", nil, { Volume = .8 })
				end
			end
			if was == "Won" and state ~= "Won" then
				pcall(restoreBell)
			end
		end
		local inZone = player:GetAttribute("UyInZone") == true
		setBeacon(inZone and (state == "Countdown" or state == "Active"))
		local hidden = View.Hidden()
		local showCard = not hidden and ((state == "Active" and (inArena() or raiding()))
			or ((state == "Won" or state == "Failed") and os.clock() < resultUntil and (inArena() or raiding())))
		-- the last seconds of the countdown
		local f = assaultFolder()
		local left = state == "Countdown" and (num(f and f:GetAttribute("StartsAt"), 0) - Shared.Now()) or 99
		local waiting = f and f:GetAttribute("Waiting") == true
		local showCount = not hidden and inZone and state == "Countdown" and not waiting and left <= 5.5 and left > 0
		u.Gui.Enabled = showCard or showCount
		u.Card.Visible = showCard
		u.Count.Visible = showCount
		u.CountSub.Visible = showCount
		if showCard then
			if not u.Laid or u.Laid ~= main.AbsoluteSize then
				layout(u, main)
			end
			refresh(u)
		end
		if showCount then
			local n = math.max(1, math.ceil(left - .05))
			u.Count.Text = tostring(n)
			u.CountSub.Text = L("THE BLACK BELL WAKES", "ЧЁРНЫЙ КОЛОКОЛ ПРОБУЖДАЕТСЯ")
			if n ~= lastCount then
				lastCount = n
				audio("TrialTick", nil, { Volume = .7, Pitch = 1 + (5 - n) * .06 })
				if not View.Reduced() then
					-- each number lands with a small punch
					local base = u.Count.Size
					View.Animate(.25, function(a)
						local k = 1 + (1 - a) * .35
						u.Count.Size = UDim2.fromOffset(base.X.Offset * k, base.Y.Offset * k)
					end, function()
						u.Count.Size = base
					end)
				end
			end
		else
			lastCount = -1
		end
		-- the beacon breathes
		if beacon and not View.Reduced() then
			local k = .5 + .5 * math.sin((os.clock() - beacon.T0) * 2)
			beacon.Parts[1].Transparency = .35 + .25 * k
		end
	end
	for _, a in ipairs({ "UyInZone", "UyDistrict", "UyTrial", "UyAssaultHits" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			pcall(apply)
		end)
	end
	for _, a in ipairs({ "OpenMenu", "UIHidden", "CinemaActive" }) do
		main:GetAttributeChangedSignal(a):Connect(function()
			pcall(apply)
		end)
	end
	for _, a in ipairs({ "HwResonanceBottom", "HwStripBottom", "HUDFreeTop", "HUDInnerLeft", "HUDInnerRight" }) do
		main:GetAttributeChangedSignal(a):Connect(function()
			if u.Card.Visible then
				layout(u, main)
			end
		end)
	end
	View.Bus.On("C2Signal", function(sig)
		if type(sig) ~= "table" or sig.Kind ~= "C2Resonance" or type(sig.Data) ~= "table" or sig.Data.Kind ~= "Reward" then
			return
		end
		local d = sig.Data
		local hits = math.floor(num(d.Hits, 0))
		if d.Won then
			View.Toast(ctx, "THE BLACK BELL FALLS · your hits: " .. hits, "ЧЁРНЫЙ КОЛОКОЛ ПАЛ · твоих ударов: " .. hits, "success")
		else
			View.Toast(ctx, "The bell held · your hits: " .. hits, "Колокол устоял · твоих ударов: " .. hits, "info")
		end
	end)
	-- 10 Hz: the countdown and the raid clock
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < .1 then
			return
		end
		acc = 0
		local ok, e = pcall(apply)
		if not ok then
			warn("Trials.Assault: " .. tostring(e))
		end
	end)
	pcall(apply)
end
P.Boot = boot

---------------------------------------------------------------------------------------------------------------------
-- presenter (the raider's own "Assault" run)
---------------------------------------------------------------------------------------------------------------------
local active: any = nil

function P.Init(c: any)
	task.spawn(boot, c)
end

function P.Start(c: any, run: any)
	task.spawn(boot, c)
	ctx = View.Ctx(c)
	if type(run) ~= "table" or run.TrialId ~= "Assault" then
		return
	end
	active = { RunId = run.RunId }
	View.Banner(ctx, "THE BLACK BELL ASSAULT", "ШТУРМ ЧЁРНОГО КОЛОКОЛА", { Sub = { "Strike the Bellkeeper with everyone: " .. AC.MinHits
		.. " hits earn the rewards", "Бей Звонаря вместе со всеми: " .. AC.MinHits .. " ударов дают награду" }, Color = View.Colors.Resonance,
		Seconds = 3.2 })
	audio("TrialStart", nil, { Volume = .8 })
end

function P.Update() end
function P.Signal() end

function P.Stop(_c: any, run: any, _result: any)
	if active and run and run.RunId and active.RunId ~= run.RunId then
		return
	end
	active = nil
end

function P.HudLines(_run: any): { string }?
	if not active then
		return nil
	end
	local hits = math.floor(num(player:GetAttribute("UyAssaultHits"), 0))
	return {
		L("Your hits", "Твои удары") .. ": " .. hits .. " / " .. AC.MinHits .. (hits >= AC.MinHits and " ✓" or ""),
		L("The whole arena raids together", "Вся арена штурмует вместе"),
	}
end

task.defer(function()
	task.wait(3)
	if not booted then
		boot(nil)
	end
end)

return P
