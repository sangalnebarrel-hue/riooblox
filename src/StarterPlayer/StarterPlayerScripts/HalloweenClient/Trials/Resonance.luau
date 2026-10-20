-- BELL RESONANCE meter (StarterPlayerScripts.HalloweenClient.Trials.Resonance, WP-J; docs/halloween2/DESIGN.md §8.6).
-- Presenter-shaped (§24.1: Ids / Start / Update / Signal / Stop / HudLines) but not a trial: it boots once (the Trials
-- host's Start / Init, or on its own right after it is required) and runs for as long as the client lives, shown only
-- while the local player is in the Underyard.
-- * A compact card at the top centre (under the HUD strip: main ScreenGui attribute HwStripBottom / HUDFreeTop): BELL
--   RESONANCE + percent, a bar with the four milestone ticks (RESONANT TOLL 25% · KEYS 50% · ECHOES 75% · ASSAULT 100%;
--   reached ticks light up), value / goal + the next milestone; pills under it: the RESONANT TOLL buff timer, the
--   RESONANT ECHOES timer, the BLACK BELL ASSAULT countdown / time left. Reads RS.Halloween.State.Resonance + .Assault.
-- * Hidden while a menu is open, with HIDE UI, during a cinematic and during the player's own trial (UyTrial), so it never
--   competes with the trial HUD. Own ScreenGui "DOGROTS_Resonance" (DisplayOrder 47, HideWithUI); phone layouts from the
--   screen size; ReducedMotion: no pulses. Publishes the card's bottom edge as main ScreenGui attribute HwResonanceBottom.
-- * Signals C2Resonance {Kind = "Milestone" | "Key"} -> a tick flash + a localized toast.
-- * The RESONANT ECHO spots (Strike kind "UyResEcho"): a floating cracked bell shard in a rune ring on each target part
--   (Models.Seals2.Echo), a burst when one breaks.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals2View"))

local R = { Ids = {}, Always = true }

local L = View.L
local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = RGB(16, 12, 26)
local DEEP = RGB(34, 18, 52)
local VIOLET = RGB(150, 80, 230)
local VIOLET_HI = RGB(196, 150, 255)
local MOON = RGB(150, 200, 255)
local CANDLE = RGB(255, 170, 80)
local GOLD = RGB(255, 210, 110)
local BLOOD = RGB(232, 72, 96)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

local MILESTONE_SHORT = {
	Toll = { "TOLL", "ЗВОН" }, Keys = { "KEYS", "КЛЮЧИ" }, Echoes = { "ECHOES", "ЭХО" }, Assault = { "ASSAULT", "ШТУРМ" },
}
local MILESTONE_TOAST = {
	Toll = { "RESONANT TOLL: +25% streak shards in the Underyard for 5 min", "РЕЗОНИРУЮЩИЙ ЗВОН: +25% осколков за серии в Поддворье на 5 мин" },
	Keys = { "KEYS FOR THE FAITHFUL: a Coffin Key for everyone ringing the bell", "КЛЮЧИ ДЛЯ ВЕРНЫХ: ключ от гроба каждому, кто звонил в колокол" },
	Echoes = { "RESONANT ECHOES: six echoes wait in Bell Square for 3 min", "РЕЗОНИРУЮЩЕЕ ЭХО: шесть эхо ждут на Колокольной площади 3 мин" },
	Assault = { "THE BLACK BELL ASSAULT begins in 30 s: to the arena!", "ШТУРМ ЧЁРНОГО КОЛОКОЛА через 30 с: все на арену!" },
}

local booted = false
local ctx: any = nil

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds + .5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function stateFolder(name: string): Instance?
	local st = Halloween:FindFirstChild("State")
	return st and st:FindFirstChild(name) or nil
end

local function num(inst: Instance?, key: string): number
	local v = inst and inst:GetAttribute(key)
	return tonumber(v) or 0
end

---------------------------------------------------------------------------------------------------------------------
-- UI
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

local function corner(o: Instance, r: any)
	new("UICorner", { CornerRadius = r == "pill" and UDim.new(.5, 0) or UDim.new(0, r) }, o)
end

local function build(main: ScreenGui): any
	local u: any = {}
	local gui = new("ScreenGui", { Name = "DOGROTS_Resonance", DisplayOrder = 47, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = main.IgnoreGuiInset, Enabled = false })
	pcall(function()
		gui.ScreenInsets = main.ScreenInsets
	end)
	gui:SetAttribute("HideWithUI", true)
	gui:SetAttribute("NoTranslate", true)
	u.Gui = gui
	local card = new("Frame", { Name = "ResonanceCard", AnchorPoint = Vector2.new(.5, 0), BackgroundColor3 = DEEP, BackgroundTransparency = .12,
		BorderSizePixel = 0, Active = false }, gui)
	corner(card, 12)
	u.Stroke = new("UIStroke", { Color = VIOLET, Thickness = 2, Transparency = .1 }, card)
	new("UIGradient", { Color = ColorSequence.new(WHITE, RGB(190, 170, 220)), Rotation = 90 }, card)
	u.Card = card
	u.Title = label(card, { Name = "Title", Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true })
	u.Percent = label(card, { Name = "Percent", Text = "", TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = VIOLET_HI, TextScaled = true })
	local track = new("Frame", { Name = "Track", BackgroundColor3 = INK, BackgroundTransparency = .1, BorderSizePixel = 0 }, card)
	corner(track, "pill")
	u.Track = track
	local fill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, track)
	corner(fill, "pill")
	new("UIGradient", { Color = ColorSequence.new(VIOLET, MOON) }, fill)
	u.Fill = fill
	u.Ticks = {}
	for i, m in ipairs(View.Base.Resonance.Milestones) do
		local tick = new("Frame", { Name = "Tick" .. i, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(m.At, .5), Rotation = 45,
			BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 3 }, track)
		local s = new("UIStroke", { Color = VIOLET_HI, Thickness = 1.5 }, tick)
		local cap = label(card, { Name = "TickLabel" .. i, AnchorPoint = Vector2.new(.5, 0), Text = "", TextScaled = true, TextColor3 = VIOLET_HI,
			TextTransparency = .15 })
		u.Ticks[i] = { Frame = tick, Stroke = s, Label = cap, At = m.At, Kind = m.Kind }
	end
	u.Info = label(card, { Name = "Info", Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, TextColor3 = RGB(226, 212, 248) })
	-- pills under the card
	local pills = new("Frame", { Name = "Pills", AnchorPoint = Vector2.new(.5, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Top }, pills)
	u.Pills = pills
	local function pill(name: string, col: Color3, order: number): any
		local f = new("Frame", { Name = name, BackgroundColor3 = col:Lerp(INK, .55), BackgroundTransparency = .08, BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Visible = false }, pills)
		corner(f, "pill")
		new("UIStroke", { Color = col, Thickness = 1.5 }, f)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, f)
		local t = label(f, { Name = "Text", Text = "", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextColor3 = col:Lerp(WHITE, .45) })
		return { Frame = f, Text = t, Color = col }
	end
	u.Buff = pill("BuffPill", CANDLE, 1)
	u.Echo = pill("EchoPill", VIOLET_HI, 2)
	u.Assault = pill("AssaultPill", BLOOD, 3)
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
	local mc = View.Config.Client.Meter
	local left = tonumber(main:GetAttribute("HUDInnerLeft")) or 12
	local right = tonumber(main:GetAttribute("HUDInnerRight")) or (W - 12)
	if right - left < 200 then
		left, right = 12, W - 12
	end
	local w = math.floor(math.min(phone and mc.PhoneWidth or mc.Width, right - left - 16, W - 24))
	local h = phone and mc.PhoneHeight or mc.Height
	local cx = math.floor((left + right) / 2)
	local top = tonumber(main:GetAttribute("HwStripBottom"))
	if not top or top <= 0 then
		top = (tonumber(main:GetAttribute("HUDFreeTop")) or (phone and 56 or 72)) + 2
	end
	local y = math.floor(top + 6)
	u.Card.Position = UDim2.fromOffset(cx, y)
	u.Card.Size = UDim2.fromOffset(w, h)
	local pad = phone and 8 or 10
	local titleH = phone and 13 or 15
	u.Title.Position = UDim2.fromOffset(pad, 4)
	u.Title.Size = UDim2.fromOffset(math.floor(w * .66) - pad, titleH)
	u.Percent.Position = UDim2.fromOffset(math.floor(w * .66), 4)
	u.Percent.Size = UDim2.fromOffset(math.floor(w * .34) - pad, titleH)
	local trackH = phone and 7 or 9
	local trackY = 4 + titleH + 4
	u.Track.Position = UDim2.fromOffset(pad, trackY)
	u.Track.Size = UDim2.fromOffset(w - pad * 2, trackH)
	local tickS = trackH + 3
	for _, t in ipairs(u.Ticks) do
		t.Frame.Size = UDim2.fromOffset(tickS, tickS)
		t.Label.Visible = false
	end
	local infoY = trackY + trackH + 3
	u.Info.Position = UDim2.fromOffset(pad, infoY)
	u.Info.Size = UDim2.fromOffset(w - pad * 2, math.max(9, h - infoY - 3))
	local pillH = phone and 20 or 24
	u.Pills.Position = UDim2.fromOffset(cx, y + h + 5)
	u.Pills.Size = UDim2.fromOffset(math.max(w, W - 40), pillH)
	for _, p in ipairs({ u.Buff, u.Echo, u.Assault }) do
		p.Frame.Size = UDim2.fromOffset(0, pillH)
		p.Text.TextSize = phone and 12 or 14
	end
	u.Laid = Vector2.new(W, H)
	u.Bottom = y + h + 5 + pillH
end

---------------------------------------------------------------------------------------------------------------------
-- state -> UI
---------------------------------------------------------------------------------------------------------------------
local function nextMilestone(frac: number): any
	for _, m in ipairs(View.Base.Resonance.Milestones) do
		if frac + 1e-9 < m.At then
			return m
		end
	end
	return nil
end

local function refresh(u: any)
	local res, assault = stateFolder("Resonance"), stateFolder("Assault")
	local value, goal = num(res, "Value"), math.max(1, num(res, "Goal"))
	local frac = math.clamp(value / goal, 0, 1)
	local aState = assault and assault:GetAttribute("State") or ""
	if aState == "Countdown" or aState == "Active" then
		frac = 1
	end
	u.Title.Text = L("BELL RESONANCE", "РЕЗОНАНС КОЛОКОЛА")
	u.Percent.Text = string.format("%d%%", math.floor(frac * 100 + 1e-6))
	u.Fill.Size = UDim2.fromScale(frac, 1)
	local reached = num(res, "Milestone")
	for i, t in ipairs(u.Ticks) do
		local on = i <= reached or frac + 1e-9 >= t.At
		t.Frame.BackgroundColor3 = on and GOLD or INK
		t.Stroke.Color = on and GOLD:Lerp(WHITE, .3) or VIOLET_HI
	end
	local now = View.Shared.Now()
	local unix = os.time()
	if aState == "Countdown" then
		u.Info.Text = L("THE BLACK BELL ASSAULT IS COMING", "ШТУРМ ЧЁРНОГО КОЛОКОЛА БЛИЗКО")
	elseif aState == "Active" then
		u.Info.Text = L("THE BLACK BELL ASSAULT RINGS", "ИДЁТ ШТУРМ ЧЁРНОГО КОЛОКОЛА")
	else
		local nxt = nextMilestone(frac)
		local nums = View.Shared.Format(math.floor(value)) .. " / " .. View.Shared.Format(goal)
		if nxt and u.Card.AbsoluteSize.X >= 260 then
			u.Info.Text = nums .. "  ·  " .. L("NEXT", "ДАЛЕЕ") .. ": " .. View.Pair(nxt.Name)
		elseif nxt then
			u.Info.Text = nums .. "  ·  " .. View.Pair(MILESTONE_SHORT[nxt.Kind] or nxt.Name)
		else
			u.Info.Text = nums
		end
	end
	-- pills (compact words on narrow screens so the three fit one row)
	local narrow = (u.Laid and u.Laid.X or 1000) < 600
	local buff = num(res, "BuffUntil") - unix
	u.Buff.Frame.Visible = buff > 0
	if buff > 0 then
		u.Buff.Text.Text = (narrow and L("TOLL +25%", "ЗВОН +25%") or L("RESONANT TOLL +25%", "РЕЗОНИРУЮЩИЙ ЗВОН +25%")) .. " · " .. clock(buff)
	end
	local echo = num(res, "EchoUntil") - unix
	u.Echo.Frame.Visible = echo > 0
	if echo > 0 then
		u.Echo.Text.Text = (narrow and L("ECHOES", "ЭХО") or L("ECHOES IN BELL SQUARE", "ЭХО НА ПЛОЩАДИ")) .. " · " .. clock(echo)
	end
	if aState == "Countdown" then
		u.Assault.Frame.Visible = true
		local waiting = assault and assault:GetAttribute("Waiting") == true
		local waitText = narrow and L("ASSAULT · WAITING", "ШТУРМ · ОЖИДАНИЕ")
			or L("ASSAULT · THE BELL WAITS FOR THE TRIAL", "ШТУРМ · КОЛОКОЛ ЖДЁТ КОНЦА ИСПЫТАНИЯ")
		u.Assault.Text.Text = waiting and waitText or (L("ASSAULT IN", "ШТУРМ ЧЕРЕЗ") .. " " .. clock(num(assault, "StartsAt") - now))
	elseif aState == "Active" then
		u.Assault.Frame.Visible = true
		u.Assault.Text.Text = L("ASSAULT", "ШТУРМ") .. " · " .. clock(num(assault, "EndsAt") - now)
	elseif aState == "Won" then
		u.Assault.Frame.Visible = true
		u.Assault.Text.Text = L("THE BLACK BELL FELL", "ЧЁРНЫЙ КОЛОКОЛ ПАЛ")
	elseif aState == "Failed" then
		u.Assault.Frame.Visible = true
		u.Assault.Text.Text = L("THE BELL HELD", "КОЛОКОЛ УСТОЯЛ")
	else
		u.Assault.Frame.Visible = false
	end
end

local function pulse(u: any, index: number)
	local t = u.Ticks[index]
	if not t or View.Reduced() then
		return
	end
	local s = t.Frame.Size
	View.Animate(.6, function(a)
		local k = 1 + math.sin(a * math.pi) * .8
		t.Frame.Size = UDim2.fromOffset(s.X.Offset * k, s.Y.Offset * k)
	end, function()
		t.Frame.Size = s
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Resonant Echo visuals (Strike kind "UyResEcho")
---------------------------------------------------------------------------------------------------------------------
local echoes: { [BasePart]: any } = {}

local function dropEcho(part: BasePart)
	local e = echoes[part]
	echoes[part] = nil
	if e then
		e.Maid.Clean()
	end
end

local function addEcho(part: Instance)
	if not part:IsA("BasePart") or part:GetAttribute("Kind") ~= "UyResEcho" or echoes[part] then
		return
	end
	local maid = View.Maid()
	local lite = View.Quality() == "Low"
	local model = View.Models.Echo({ Lite = lite })
	model.Parent = View.Folder()
	maid.Give(model)
	local e = { Maid = maid, Model = model, Phase = math.random() * 6 }
	echoes[part] = e
	local reduced = View.Reduced()
	maid.Give(RunService.Heartbeat:Connect(function()
		if not part.Parent then
			dropEcho(part)
			return
		end
		local t = os.clock()
		local bob = reduced and 0 or math.sin(t * 2 + e.Phase) * .35
		local spin = reduced and 0 or t * .6
		model:PivotTo(part.CFrame * CFrame.new(0, bob, 0) * CFrame.Angles(0, spin, 0))
	end))
	maid.Give(part:GetAttributeChangedSignal("EndReason"):Connect(function()
		local fx = ctx and ctx.FX
		if fx and part:GetAttribute("EndReason") == "Broke" then
			pcall(fx.Burst, part.Position, { Color = VIOLET_HI, Color2 = MOON, Count = 26, Speed = { 8, 16 } })
			pcall(fx.Ring, part.Position - Vector3.new(0, 2.4, 0), VIOLET, 7, .6)
		end
		local audio = ctx and ctx.Audio
		if audio then
			pcall(audio.Play, "ChainBreak", part.Position, { Volume = .55, Pitch = 1.4 })
		end
		dropEcho(part)
	end))
	maid.Give(part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			dropEcho(part)
		end
	end))
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
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local main = playerGui:WaitForChild("ScreenGui", 60)
	if not main then
		return
	end
	local u: any = nil
	local okBuild, err = pcall(function()
		u = build(main)
		layout(u, main)
		refresh(u)
	end)
	if not okBuild then
		warn("Trials.Resonance: build failed: " .. tostring(err))
		if u and u.Gui then
			u.Gui:Destroy()
		end
		return
	end
	local function visible(): boolean
		if not Shared.Chapter2Enabled() or player:GetAttribute("UyInZone") ~= true then
			return false
		end
		if player:GetAttribute("HalloweenChapter1Complete") ~= true then
			return false
		end
		local trial = player:GetAttribute("UyTrial")
		if type(trial) == "string" and trial ~= "" then
			return false
		end
		return not View.Hidden()
	end
	local function apply()
		if not u.Gui.Parent then
			u.Gui.Parent = playerGui
		end
		local on = visible()
		u.Gui.Enabled = on
		if on then
			local size = main.AbsoluteSize
			if not u.Laid or u.Laid ~= size then
				layout(u, main)
			end
			refresh(u)
		end
		main:SetAttribute("HwResonanceBottom", on and u.Bottom or nil)
	end
	for _, a in ipairs({ "UyInZone", "UyTrial", "HalloweenChapter1Complete" }) do
		player:GetAttributeChangedSignal(a):Connect(apply)
	end
	for _, a in ipairs({ "OpenMenu", "UIHidden", "CinemaActive" }) do
		main:GetAttributeChangedSignal(a):Connect(apply)
	end
	for _, a in ipairs({ "HwStripBottom", "HUDFreeTop", "HUDInnerLeft", "HUDInnerRight" }) do
		main:GetAttributeChangedSignal(a):Connect(function()
			if u.Gui.Enabled then
				layout(u, main)
				refresh(u)
			end
		end)
	end
	main:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	View.Bus.On("C2Signal", function(sig)
		if type(sig) ~= "table" or sig.Kind ~= "C2Resonance" or type(sig.Data) ~= "table" then
			return
		end
		local d = sig.Data
		if d.Kind == "Milestone" then
			local m = View.Base.Resonance.Milestones[d.Index or 0]
			if m then
				pulse(u, d.Index)
				local msg = MILESTONE_TOAST[m.Kind]
				if msg and player:GetAttribute("UyInZone") == true then
					View.Toast(ctx, msg[1], msg[2], "success")
				end
			end
			if ctx.Audio and player:GetAttribute("UyInZone") == true then
				pcall(ctx.Audio.Play, "BellTollFar", nil, { Volume = .8 })
			end
		elseif d.Kind == "Key" then
			if (tonumber(d.Granted) or 0) > 0 then
				View.Toast(ctx, "+1 Coffin Key · the bell rang for you", "+1 ключ от гроба · колокол прозвонил для тебя", "success")
			elseif d.Capped then
				View.Toast(ctx, "You already got today's 2 resonance keys", "Ты уже получил сегодня 2 ключа резонанса", "info")
			end
		end
		apply()
	end)
	-- Resonant Echo spots
	for _, part in ipairs(CollectionService:GetTagged("HalloweenTarget")) do
		addEcho(part)
	end
	CollectionService:GetInstanceAddedSignal("HalloweenTarget"):Connect(function(part)
		task.defer(addEcho, part)
	end)
	-- attribute driven + a light timer for the countdown texts
	local function watch(name: string)
		task.spawn(function()
			local st = Halloween:WaitForChild("State", 60)
			local f = st and st:WaitForChild(name, 60)
			if f then
				f.AttributeChanged:Connect(function()
					if u.Gui.Enabled then
						refresh(u)
					end
				end)
			end
		end)
	end
	watch("Resonance")
	watch("Assault")
	task.spawn(function()
		while u.Gui do
			task.wait(.5)
			local ok, e = pcall(apply)
			if not ok then
				warn("Trials.Resonance: update failed: " .. tostring(e))
			end
		end
	end)
	apply()
end
R.Boot = boot

-- presenter contract (§24.1): no trial ids; Start / Init boot the widget once
function R.Init(c: any)
	task.spawn(boot, c)
end
function R.Start(c: any, _run: any?)
	task.spawn(boot, c)
end
function R.Update() end
function R.Signal() end
function R.Stop() end
function R.HudLines(): { string }?
	return nil
end

-- not every host starts presenters that own no trial: boot on our own once the client has settled
task.defer(function()
	task.wait(3)
	if not booted then
		boot(nil)
	end
end)

return R
