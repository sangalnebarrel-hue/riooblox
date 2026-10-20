-- THE MOURNER · client presenter (StarterPlayerScripts.HalloweenClient.Trials.Mourner, WP-H2; DESIGN §9 "Chapter II
-- onboarding" step 5, §10.2, §24.1 presenter contract). The server trial (ServerScriptService.Halloween.Chapter2Tutorial)
-- puts the player in their own Event HP zone and telegraphs three attacks through EventHP.Hazard (CombatFX draws the
-- telegraphs and the HP bar is CombatHUD's); this presenter is the Mourner's side of the fight:
--   * the practice dummy (HalloweenClient.UnderyardFX.Mourner(): Models.Mourner on its pedestal) turns to the player,
--     winds up and strikes in time with each telegraph (Circle: arms overhead, slam; Line: draws back, thrusts; Ring:
--     arms out, a wailing spin) and recoils when an attack is dodged
--   * a callout per attack ("CIRCLE · STEP OUT", "LINE · STEP ASIDE", "RING · FIND THE GAP") and, for the Ring, a green
--     SAFE marker in its gap; "DODGED!" / "HIT!" verdicts; the dodge pips over the dummy (2 per round)
--   * the open heart: a marker "STRIKE · PERFECT" on the weak spot with the time it stays open, "ONLY A PERFECT!" on a
--     Good hit, the ribs closing when it runs out; the win: the dummy collapses, a violet burst, the bell
--   * downed: the ghost guide's revive countdown (the server revives after 3 s; no bleed-out here)
-- Signals (C2Trial, TrialId "Mourner"): Start / Score / Tick (generic) and MournerAttack {Attack, Index, Cycle,
-- ImpactAt, Telegraph, Target, Gap?, Retry?}, MournerResult {Outcome, Dodges, Need, Next, Cycle}, WeakOpen {Until,
-- TargetId}, WeakHit, WeakMiss, WeakClose, Downed {ReviveAt}, Revived {Next}, Far.
-- Presenter contract (§24.1): {Ids, Start(ctx, run), Update(ctx, run), Signal(ctx, kind, data, run), Stop(ctx, run,
-- result), HudLines(run)}; ctx = the Halloween client ctx + ctx.Trials helpers (Banner / Toast / Mark ...), used
-- defensively: without them the presenter shows its own world text. Everything is torn down on Stop.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local P = { Ids = { "Mourner" } }
local player = Players.LocalPlayer
local C3 = Color3.fromRGB
local V3 = Vector3.new
local CF = CFrame.new
local VIOLET = C3(190, 140, 255)
local GREEN = C3(120, 255, 140)
local RED = C3(255, 110, 140)
local GOLD = C3(255, 206, 110)
local DIM = C3(70, 58, 96)
local INK = C3(16, 12, 26)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

-- the attacks: callout, the dummy's wind-up / strike acts (Models.Mourner states)
local ATTACKS = {
	Circle = { Text = { "CIRCLE · STEP OUT OF IT", "КРУГ · ВЫЙДИ ИЗ НЕГО" }, Wind = "WindCircle", Strike = "StrikeCircle", Color = C3(255, 120, 150) },
	Line = { Text = { "LINE · STEP ASIDE", "ЛИНИЯ · ШАГНИ В СТОРОНУ" }, Wind = "WindLine", Strike = "StrikeLine", Color = C3(255, 170, 90) },
	Ring = { Text = { "RING · FIND THE GAP", "КОЛЬЦО · НАЙДИ ПРОХОД" }, Wind = "WindRing", Strike = "StrikeRing", Color = C3(190, 140, 255) },
}
P.Attacks = ATTACKS

local active: any = nil

local loc: any = nil
local function T(ctx: any, en: string): string
	local Shared = ctx and ctx.Shared
	if not (Shared and Shared.IsRussian()) then
		return en
	end
	if loc == nil then
		local ok, m = pcall(function()
			return require(RS:WaitForChild("Localization", 5):WaitForChild("UnderyardFX", 5)) :: any
		end)
		loc = ok and type(m) == "table" and m or false
	end
	return (loc and loc.UI and loc.UI[en]) or en
end

local function L(ctx: any, pair: { string }): string
	local Shared = ctx and ctx.Shared
	if Shared and Shared.IsRussian() and pair[2] then
		return pair[2]
	end
	return pair[1]
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and t or os.clock()
end

local function dummy(ctx: any): any
	local fx = ctx and ctx.Modules and ctx.Modules.UnderyardFX
	local ok, h = pcall(function()
		return fx and fx.Mourner and fx.Mourner()
	end)
	return ok and h or nil
end

local function centre(run: any): Vector3
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or {}
	if typeof(data.Centre) == "Vector3" then
		return data.Centre
	end
	local okL, Lay = pcall(function()
		return require(RS:WaitForChild("Halloween"):WaitForChild("UnderyardLayout")) :: any
	end)
	return okL and Lay and Lay.Square.Mourner or V3(0, 0, 2462)
end

local function heartPos(a: any): Vector3
	local d = dummy(a.Ctx)
	if d and d.Heart then
		local ok, p = pcall(d.Heart)
		if ok and typeof(p) == "Vector3" then
			return p
		end
	end
	return a.Centre + V3(0, 4.4, 0)
end

local function play(ctx: any, cue: string, where: any, opts: any)
	local A = ctx and ctx.Audio
	if A and A.Play then
		pcall(A.Play, cue, where, opts)
	end
end

local function fx(ctx: any, fn: (any) -> ())
	local F = ctx and ctx.FX
	if F then
		pcall(fn, F)
	end
end

local function myRoot(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

---------------------------------------------------------------------------------------------------------------------
-- world text over the dummy: the dodge pips + a callout line
---------------------------------------------------------------------------------------------------------------------
local function newHolder(name: string, pos: Vector3, parent: Instance): Part
	local h = Instance.new("Part")
	h.Name = name
	h.Anchored, h.CanCollide, h.CanQuery, h.CanTouch, h.CastShadow = true, false, false, false, false
	h.Transparency = 1
	h.Size = V3(.2, .2, .2)
	h.CFrame = CF(pos)
	h.Parent = parent
	return h
end

local function buildBoard(a: any, need: number)
	local ctx = a.Ctx
	local parent = ctx.FX and ctx.FX.Folder() or workspace
	local holder = newHolder("UyMournerBoard", a.Centre + V3(0, 10.2, 0), parent)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Board"
	bb.Size = UDim2.fromOffset(300, 96)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb:SetAttribute("NoTranslate", true)
	local callout = Instance.new("TextLabel")
	callout.Name = "Callout"
	callout.BackgroundTransparency = 1
	callout.Size = UDim2.new(1, 0, 0, 34)
	callout.FontFace = FONT
	callout.TextScaled = true
	callout.Text = ""
	callout.TextColor3 = VIOLET
	callout.TextStrokeColor3 = INK
	callout.TextStrokeTransparency = .1
	callout:SetAttribute("NoTranslate", true)
	local cs = Instance.new("UIScale")
	cs.Name = "Pop"
	cs.Parent = callout
	callout.Parent = bb
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(0, 38)
	caption.Size = UDim2.new(1, 0, 0, 18)
	caption.FontFace = FONT
	caption.TextScaled = true
	caption.Text = T(ctx, "DODGES THIS ROUND")
	caption.TextColor3 = C3(220, 210, 240)
	caption.TextStrokeColor3 = INK
	caption.TextStrokeTransparency = .2
	caption:SetAttribute("NoTranslate", true)
	caption.Parent = bb
	local row = Instance.new("Frame")
	row.Name = "Pips"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, 60)
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Parent = bb
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
	local pips = {}
	for i = 1, need do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.LayoutOrder = i
		pip.Size = UDim2.fromOffset(26, 26)
		pip.Rotation = 45
		pip.BackgroundColor3 = DIM
		local st = Instance.new("UIStroke")
		st.Color = INK
		st.Thickness = 2
		st.Parent = pip
		local sc = Instance.new("UIScale")
		sc.Name = "Pop"
		sc.Parent = pip
		pip.Parent = row
		table.insert(pips, pip)
	end
	bb.Parent = holder
	a.Board, a.Callout, a.Caption, a.Pips = holder, callout, caption, pips
end

local function setPips(a: any, n: number)
	for i, pip in ipairs(a.Pips or {}) do
		local lit = i <= n
		local want = lit and GREEN or DIM
		if pip.BackgroundColor3 ~= want then
			pip.BackgroundColor3 = want
			local pop = pip:FindFirstChild("Pop")
			if lit and pop then
				(pop :: UIScale).Scale = 1.5
				TweenService:Create(pop, TweenInfo.new(.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end
end

local function say(a: any, text: string, color: Color3, seconds: number?)
	local c = a.Callout
	if not c then
		return
	end
	a.SayToken = (a.SayToken or 0) + 1
	local token = a.SayToken
	c.Text = text
	c.TextColor3 = color
	c.TextTransparency = 0
	c.TextStrokeTransparency = .1
	local pop = c:FindFirstChild("Pop")
	if pop and not (a.Ctx.Shared and a.Ctx.Shared.ReducedMotion()) then
		(pop :: UIScale).Scale = 1.3
		TweenService:Create(pop, TweenInfo.new(.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	task.delay(seconds or 2.2, function()
		if active == a and a.SayToken == token and c.Parent then
			TweenService:Create(c, TweenInfo.new(.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- the SAFE marker in the Ring's gap, the heart's marker
---------------------------------------------------------------------------------------------------------------------
local function clearGap(a: any)
	if a.Gap then
		a.Gap:Destroy()
		a.Gap = nil
	end
end

local function showGap(a: any, angleDeg: number, inner: number, outer: number, untilAt: number)
	clearGap(a)
	local ctx = a.Ctx
	local th = math.rad(angleDeg)
	local r = (inner + outer) / 2
	local c = a.Centre
	local pos = V3(c.X + math.cos(th) * r, c.Y + .25, c.Z + math.sin(th) * r)
	local m = Instance.new("Model")
	m.Name = "UyMournerGap"
	local outward = V3(math.cos(th), 0, math.sin(th))
	-- three chevrons pointing out of the ring through the gap + a soft disc
	local disc = newHolder("GapDisc", pos, m)
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = V3(.1, 4.2, 4.2)
	disc.CFrame = CF(pos) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Material = Enum.Material.Neon
	disc.Color = GREEN
	disc.Transparency = .65
	for k = -1, 1 do
		local p = pos + outward * (k * 1.4)
		local look = CFrame.lookAt(p, p + outward)
		for _, side in ipairs({ -1, 1 }) do
			local bar = newHolder("GapChevron", p, m)
			bar.Size = V3(.25, .08, 1.3)
			bar.CFrame = look * CFrame.Angles(0, side * math.rad(40), 0) * CF(0, 0, .45)
			bar.Material = Enum.Material.Neon
			bar.Color = GREEN
			bar.Transparency = .1
		end
	end
	local bbHolder = newHolder("GapLabel", pos + V3(0, 2.4, 0), m)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 34)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb:SetAttribute("NoTranslate", true)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = FONT
	t.TextScaled = true
	t.Text = T(ctx, "SAFE")
	t.TextColor3 = GREEN
	t.TextStrokeColor3 = INK
	t.TextStrokeTransparency = .1
	t:SetAttribute("NoTranslate", true)
	t.Parent = bb
	bb.Parent = bbHolder
	m.Parent = ctx.FX and ctx.FX.Folder() or workspace
	a.Gap = m
	local token = a.Gap
	task.delay(math.max(.5, untilAt - serverNow() + .3), function()
		if a.Gap == token then
			clearGap(a)
		end
	end)
end

local function clearHeartMark(a: any)
	if a.HeartMark then
		pcall(function()
			a.HeartMark:Destroy()
		end)
		a.HeartMark = nil
	end
end

local function markHeart(a: any, untilAt: number)
	clearHeartMark(a)
	local ctx = a.Ctx
	local pos = heartPos(a)
	local Trials = ctx.Trials
	if Trials and Trials.Mark then
		local ok, h = pcall(Trials.Mark, pos, "STRIKE · PERFECT", "УДАР · ИДЕАЛЬНО", { Color = VIOLET, Height = 2.6, MaxDistance = 120 })
		if ok and h then
			a.HeartMark = h
		end
	end
	if not a.HeartMark then
		local holder = newHolder("UyHeartMark", pos, ctx.FX and ctx.FX.Folder() or workspace)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(200, 44)
		bb.StudsOffsetWorldSpace = V3(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb:SetAttribute("NoTranslate", true)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.FontFace = FONT
		t.TextScaled = true
		t.Text = T(ctx, "STRIKE · PERFECT")
		t.TextColor3 = VIOLET
		t.TextStrokeColor3 = INK
		t.TextStrokeTransparency = .1
		t:SetAttribute("NoTranslate", true)
		t.Parent = bb
		bb.Parent = holder
		a.HeartMark = holder
	end
	a.WeakUntil = untilAt
end

---------------------------------------------------------------------------------------------------------------------
-- the attack beats on the dummy (wind-up across the telegraph, the strike at the impact)
---------------------------------------------------------------------------------------------------------------------
local function attackBeat(a: any, data: any)
	local spec = ATTACKS[tostring(data.Attack)]
	if not spec then
		return
	end
	local ctx = a.Ctx
	local impact = tonumber(data.ImpactAt) or (serverNow() + 2)
	local lead = math.max(.3, impact - serverNow())
	local d = dummy(ctx)
	local strikeDur = data.Attack == "Ring" and .7 or .4
	if d then
		pcall(d.Act, spec.Wind, math.max(.25, lead - .2), 1)
	end
	a.Beat = (a.Beat or 0) + 1
	local beat = a.Beat
	task.delay(math.max(0, lead - .2), function()
		if active ~= a or a.Beat ~= beat then
			return
		end
		local dd = dummy(ctx)
		if dd then
			pcall(dd.Act, spec.Strike, strikeDur, .25)
		end
		local where = a.Centre + V3(0, 3, 0)
		if data.Attack == "Ring" then
			play(ctx, "Toll", where, { Pitch = .55, Volume = .9 })
		else
			play(ctx, "BossSlam", where, { Pitch = 1.35, Volume = .45 })
		end
	end)
	say(a, L(ctx, spec.Text), spec.Color, lead + .4)
	play(ctx, "GhostWoo", a.Centre + V3(0, 6, 0), { Pitch = data.Attack == "Ring" and .7 or .85, Volume = .6 })
	if data.Attack == "Ring" and tonumber(data.Gap) then
		local okR, R = pcall(function()
			return require(RS:WaitForChild("Halloween"):WaitForChild("UnderyardRuntime")) :: any
		end)
		local mc = okR and R and R.Config.Mourner or { RingInner = 3.6, RingOuter = 13 }
		showGap(a, tonumber(data.Gap) :: number, mc.RingInner, mc.RingOuter, impact)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- contract
---------------------------------------------------------------------------------------------------------------------
-- keepDummy: the dummy plays its collapse (UnderyardFX ends it by itself), nothing resets it here
local function cleanup(keepDummy: boolean?)
	local a = active
	active = nil
	if not a then
		return
	end
	if a.Bind then
		a.Bind:Disconnect()
	end
	clearGap(a)
	clearHeartMark(a)
	if a.Board then
		a.Board:Destroy()
	end
	local d = dummy(a.Ctx)
	if d then
		if d.Face then
			pcall(d.Face, nil)
		end
		if d.Reset and not keepDummy then
			pcall(d.Reset)
		end
	end
end

function P.Start(ctx: any, run: any)
	cleanup()
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or {}
	local need = tonumber(data.Need) or 2
	local a: any = { RunId = run and run.RunId, Ctx = ctx, Centre = centre(run), Need = need, Dodges = tonumber(data.Dodges) or 0, Phase = data.Phase,
		WeakUntil = tonumber(data.WeakUntil) or 0 }
	active = a
	pcall(buildBoard, a, need)
	setPips(a, a.Dodges)
	-- the dummy keeps its eyes on the player for the whole run
	a.Bind = RunService.Heartbeat:Connect(function()
		if active ~= a then
			return
		end
		local d = dummy(ctx)
		local r = myRoot()
		if d and d.Face and r then
			pcall(d.Face, r.Position)
		end
		if a.WeakUntil > 0 and a.Caption then
			local left = a.WeakUntil - serverNow()
			if left > 0 then
				a.Caption.Text = string.format(T(ctx, "HEART OPEN · %d s"), math.ceil(left))
			end
		end
	end)
	local Trials = ctx and ctx.Trials
	if Trials and Trials.Banner then
		pcall(Trials.Banner, "THE MOURNER", "ПЛАКАЛЬЩИК", { Sub = { "Dodge 2 attacks, then strike its heart with a PERFECT",
			"Уклонись от 2 атак, затем ударь в сердце ИДЕАЛЬНО" } })
	end
	say(a, T(ctx, "WATCH THE GLOW"), VIOLET, 2.4)
	play(ctx, "GhostWoo", a.Centre + V3(0, 6, 0), { Pitch = .75, Volume = .7 })
	if a.Phase == "Weak" and a.WeakUntil > serverNow() then
		markHeart(a, a.WeakUntil)
	end
end

function P.Update(_ctx: any, run: any)
	local a = active
	if not a or type(run) ~= "table" then
		return
	end
	local data = type(run.Data) == "table" and run.Data or {}
	local dodges = tonumber(data.Dodges)
	if dodges and dodges ~= a.Dodges then
		a.Dodges = dodges
		setPips(a, dodges)
	end
	if data.Phase == "Weak" and not a.HeartMark and tonumber(data.WeakUntil) and (tonumber(data.WeakUntil) :: number) > serverNow() then
		markHeart(a, tonumber(data.WeakUntil) :: number)
	end
end

function P.Signal(ctx: any, kind: string, data: any, _run: any)
	local a = active
	if not a or type(data) ~= "table" then
		return
	end
	local reduced = ctx and ctx.Shared and ctx.Shared.ReducedMotion()
	if kind == "MournerAttack" then
		attackBeat(a, data)
	elseif kind == "MournerResult" then
		clearGap(a)
		a.Dodges = tonumber(data.Dodges) or a.Dodges
		setPips(a, a.Dodges)
		local d = dummy(ctx)
		if data.Outcome == "Dodged" then
			say(a, T(ctx, "DODGED!"), GREEN, 1.4)
			play(ctx, "Sparkle", a.Centre + V3(0, 4, 0), { Volume = .6, Pitch = 1.2 })
			if d then
				pcall(d.Hurt)
			end
		else
			say(a, T(ctx, "HIT! LEAVE THE GLOW BEFORE IT FILLS"), RED, 2)
		end
		if data.Next == "Again" then
			task.delay(1.5, function()
				if active == a then
					say(a, T(ctx, "DODGE 2 IN ONE ROUND · AGAIN!"), GOLD, 2.4)
					setPips(a, 0)
				end
			end)
		end
	elseif kind == "WeakOpen" then
		local untilAt = tonumber(data.Until) or (serverNow() + 15)
		markHeart(a, untilAt)
		say(a, T(ctx, "ITS HEART IS OPEN!"), VIOLET, 2.6)
		fx(ctx, function(F)
			F.Burst(heartPos(a), { Color = VIOLET, Color2 = C3(255, 255, 255), Count = 24, Speed = { 3, 8 }, Lifetime = { .5, 1 }, Size = { .3, .5, 0 } })
		end)
	elseif kind == "WeakMiss" then
		say(a, T(ctx, "ONLY A PERFECT HIT COUNTS!"), RED, 1.8)
		fx(ctx, function(F)
			F.Popup(heartPos(a) + V3(0, 1.5, 0), T(ctx, "ONLY A PERFECT!"), RED, false)
		end)
		if not reduced then
			local d = dummy(ctx)
			if d then
				pcall(d.Act, "Hurt", .35, 0)
				task.delay(.36, function()
					local dd = dummy(ctx)
					if active == a and dd then
						pcall(dd.Act, "Open", .25, math.huge)
					end
				end)
			end
		end
	elseif kind == "WeakClose" then
		clearHeartMark(a)
		a.WeakUntil = 0
		if a.Caption then
			a.Caption.Text = T(ctx, "DODGES THIS ROUND")
		end
		say(a, T(ctx, "TOO SLOW · ONE MORE ATTACK"), GOLD, 2.4)
	elseif kind == "WeakHit" then
		clearHeartMark(a)
		a.WeakUntil = 0
		say(a, T(ctx, "THE MOURNER FALLS!"), GOLD, 3)
		local pos = heartPos(a)
		fx(ctx, function(F)
			F.Burst(pos, { Color = VIOLET, Color2 = GOLD, Count = 46, Speed = { 5, 14 }, Lifetime = { .6, 1.4 }, Size = { .35, .6, 0 } })
			F.Ring(V3(pos.X, a.Centre.Y + .2, pos.Z), VIOLET, 12, 1)
		end)
		play(ctx, "WeakPointHit", pos, { Volume = 1 })
		play(ctx, "Toll", pos, { Pitch = .8, Volume = .9 })
	elseif kind == "Downed" then
		say(a, T(ctx, "DOWNED · THE GHOST PUP LIFTS YOU UP"), C3(150, 200, 255), 3)
	elseif kind == "Revived" then
		say(a, T(ctx, "BACK ON YOUR PAWS!"), GREEN, 1.8)
		fx(ctx, function(F)
			local r = myRoot()
			if r then
				F.Burst(r.Position, { Color = C3(150, 200, 255), Count = 20, Speed = { 2, 6 }, Lifetime = { .5, 1 }, Size = { .3, .5, 0 } })
			end
		end)
	elseif kind == "Far" then
		say(a, T(ctx, "COME BACK INTO THE RING"), GOLD, 2.6)
	end
end

function P.Stop(_ctx: any, _run: any, result: any)
	local a = active
	local won = result == "Won" or (type(result) == "table" and result.Kind == "Won")
	if a and won then
		-- the dummy's collapse is UnderyardFX's (the heart left with reason "Won"); a moment to watch it, then tidy up
		clearGap(a)
		clearHeartMark(a)
		task.delay(2.5, function()
			if active == a then
				cleanup(true)
			end
		end)
		return
	end
	cleanup()
end

function P.HudLines(run: any): { string }?
	local a = active
	local ctx = a and a.Ctx or nil
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or {}
	local dodges = tonumber(data.Dodges) or 0
	local need = tonumber(data.Need) or 2
	if data.Phase == "Weak" then
		return { T(ctx, "Its heart is open: strike it with a PERFECT hit") }
	end
	return { string.format(T(ctx, "Dodges this round: %d / %d"), dodges, need), T(ctx, "Step out of the glowing telegraphs") }
end

function P.Active(): boolean
	return active ~= nil
end

return P
