-- THE TRIAL OF THE TOLL · client presenter (StarterPlayerScripts.HalloweenClient.Trials.Toll, WP-H2; DESIGN §9
-- "Chapter II onboarding" step 2, §24.1 presenter contract). The server trial (ServerScriptService.Halloween.
-- Chapter2Tutorial) puts an owner-only hand-bell target (Strike kind UyTollBell) on the practice ring's hand-bell; only a
-- Perfect hit counts. This presenter shows the bell's side of it:
--   * the real hand-bell of the practice ring (40_Underyard ... PracticeRing.HandBell; a client bell where it is
--     missing) swings on every toll and rings a rising little melody (Halloween Audio "Toll"); an off-beat hit gives a
--     dull clank, a small shake and an "ON THE BEAT!" hint
--   * five bell pips over the bell light up gold toll by toll, with the rule underneath ("only a PERFECT rings it")
--   * the win: three quick tolls, a golden burst, the bell settles; everything is restored on Stop (any result)
-- Signals used (C2Trial, TrialId "Toll"): Start / Score / Tick (generic) and Toll {Count, Goal, Counted}.
-- Presenter contract (§24.1): {Ids, Start(ctx, run), Update(ctx, run), Signal(ctx, kind, data, run), Stop(ctx, run, result),
-- HudLines(run)}; ctx = the Halloween client ctx + ctx.Trials helpers (Banner / Toast / Mark ...), all used defensively.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local P = { Ids = { "Toll" } }
local player = Players.LocalPlayer
local C3 = Color3.fromRGB
local V3 = Vector3.new
local CF = CFrame.new
local GOLD = C3(255, 206, 110)
local DIM = C3(70, 58, 96)
local INK = C3(16, 12, 26)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local MELODY = { 1, 1.12, 1.26, 1.335, 1.5, 1.68 } -- D minor-ish rising steps of the hand-bell (pitch multipliers)

local active: any = nil -- {RunId, Bell = {Model, Parts, Rest, Pivot, Own}, Gui, Pips, Angle, Vel, Count, Goal, Bind}

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

local function anchorPos(): Vector3
	local okL, L = pcall(function()
		return require(RS:WaitForChild("Halloween", 5):WaitForChild("UnderyardLayout", 5)) :: any
	end)
	if okL and L then
		local part = L.AnchorPart("TutorialBell")
		if part then
			return part.Position
		end
		return L.Anchor("TutorialBell") or V3(0, 2.5, 2472)
	end
	return V3(0, 2.5, 2472)
end

-- the practice ring's hand-bell model (streamed in), else a small client bell at the anchor
local function findBell(ctx: any): any
	local district = workspace:FindFirstChild("DOGROTS_District")
	local root = district and district:FindFirstChild("40_Underyard")
	local model: Instance? = nil
	if root then
		local square = root:FindFirstChild("BellSquare")
		local ring = square and square:FindFirstChild("PracticeRing")
		model = ring and ring:FindFirstChild("HandBell") or root:FindFirstChild("HandBell", true)
	end
	local own = false
	if not (model and model:IsA("Model")) then
		own = true
		local at = anchorPos()
		local m = Instance.new("Model")
		m.Name = "UyHandBell"
		local bronze = C3(170, 132, 70)
		local function part(name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			if shape then
				p.Shape = shape
			end
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = Enum.Material.Metal
			p.Parent = m
			return p
		end
		local top = at + V3(0, 1.7, 0)
		part("BellLoop", V3(.3, .5, .5), CF(top) * CFrame.Angles(0, 0, math.pi / 2), INK, Enum.PartType.Cylinder)
		for i, row in ipairs({ { .25, .55 }, { .5, .72 }, { .8, .82 }, { 1.05, 1.0 }, { 1.25, 1.2 } }) do
			part("BellBody", V3(.28, row[2], row[2]), CF(top - V3(0, row[1], 0)) * CFrame.Angles(0, 0, math.pi / 2), bronze:Lerp(INK, (i % 2) * .15),
				Enum.PartType.Cylinder)
		end
		part("BellClapper", V3(.26, .26, .26), CF(top - V3(0, 1.45, 0)), INK, Enum.PartType.Ball)
		m.Parent = ctx.FX and ctx.FX.Folder() or workspace
		model = m
	end
	local m = model :: Model
	local parts, rest = {}, {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(rest, (d :: BasePart).CFrame)
		end
	end
	local ok, cf, size = pcall(function()
		return m:GetBoundingBox()
	end)
	local pivot = ok and CF((cf :: CFrame).Position + V3(0, (size :: Vector3).Y / 2, 0)) or CF(anchorPos() + V3(0, 1.7, 0))
	local rel = {}
	for i, r in ipairs(rest) do
		rel[i] = pivot:ToObjectSpace(r)
	end
	return { Model = m, Parts = parts, Rest = rest, Rel = rel, Pivot = pivot, Own = own }
end

local function poseBell(bell: any, angle: number, roll: number)
	local cfs = table.create(#bell.Parts)
	local swing = bell.Pivot * CFrame.Angles(angle, 0, roll)
	for i = 1, #bell.Parts do
		cfs[i] = swing * bell.Rel[i]
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(bell.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(bell.Parts) do
			p.CFrame = cfs[i]
		end
	end
end

local function restoreBell(bell: any)
	if not bell then
		return
	end
	if bell.Own then
		bell.Model:Destroy()
		return
	end
	for i, p in ipairs(bell.Parts) do
		if p.Parent then
			p.CFrame = bell.Rest[i]
		end
	end
end

-- five pips + the rule, floating over the bell
local function buildGui(ctx: any, pivot: CFrame, goal: number): (BillboardGui, { Frame })
	local holder = Instance.new("Part")
	holder.Name = "UyTollPips"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
	holder.Transparency = 1
	holder.Size = V3(.2, .2, .2)
	holder.CFrame = pivot + V3(0, 2.6, 0)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Pips"
	bb.Size = UDim2.fromOffset(260, 74)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb:SetAttribute("NoTranslate", true)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 40)
	row.Parent = bb
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row
	local pips = {}
	for i = 1, goal do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.fromOffset(32, 32)
		pip.BackgroundColor3 = DIM
		pip.LayoutOrder = i
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(.5, 0)
		corner.Parent = pip
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.Thickness = 2
		stroke.Parent = pip
		local scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = pip
		-- a little bell glyph: crown + dome + lip
		local dome = Instance.new("Frame")
		dome.Name = "Dome"
		dome.AnchorPoint = Vector2.new(.5, .5)
		dome.Position = UDim2.fromScale(.5, .48)
		dome.Size = UDim2.fromScale(.46, .46)
		dome.BackgroundColor3 = INK
		dome.BackgroundTransparency = .35
		local dc = Instance.new("UICorner")
		dc.CornerRadius = UDim.new(.5, 0)
		dc.Parent = dome
		dome.Parent = pip
		local lip = Instance.new("Frame")
		lip.Name = "Lip"
		lip.AnchorPoint = Vector2.new(.5, .5)
		lip.Position = UDim2.fromScale(.5, .7)
		lip.Size = UDim2.fromScale(.62, .12)
		lip.BackgroundColor3 = INK
		lip.BackgroundTransparency = .35
		lip.BorderSizePixel = 0
		lip.Parent = pip
		pip.Parent = row
		table.insert(pips, pip)
	end
	local rule = Instance.new("TextLabel")
	rule.Name = "Rule"
	rule.BackgroundTransparency = 1
	rule.Position = UDim2.fromOffset(0, 44)
	rule.Size = UDim2.new(1, 0, 0, 26)
	rule.FontFace = FONT
	rule.TextScaled = true
	rule.Text = T(ctx, "ONLY A PERFECT RINGS THE BELL")
	rule.TextColor3 = C3(236, 226, 255)
	rule.TextStrokeColor3 = INK
	rule.TextStrokeTransparency = .2
	rule:SetAttribute("NoTranslate", true)
	rule.Parent = bb
	bb.Parent = holder
	holder.Parent = ctx.FX and ctx.FX.Folder() or workspace
	return bb, pips
end

local function setPips(a: any, count: number)
	for i, pip in ipairs(a.Pips) do
		local lit = i <= count
		local want = lit and GOLD or DIM
		if pip.BackgroundColor3 ~= want then
			pip.BackgroundColor3 = want
			if lit then
				local pop = pip:FindFirstChild("Pop")
				if pop then
					(pop :: UIScale).Scale = 1.45
					TweenService:Create(pop, TweenInfo.new(.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end
			end
		end
	end
end

local function play(ctx: any, cue: string, where: any, opts: any)
	local A = ctx and ctx.Audio
	if A and A.Play then
		pcall(A.Play, cue, where, opts)
	end
end

local function swing(a: any, strength: number)
	a.Vel += strength
end

local function cleanup()
	local a = active
	active = nil
	if not a then
		return
	end
	if a.Bind then
		a.Bind:Disconnect()
	end
	restoreBell(a.Bell)
	if a.Gui and a.Gui.Parent then
		local holder = a.Gui.Parent
		holder:Destroy()
	end
end

function P.Start(ctx: any, run: any)
	cleanup()
	local okBell, bell = pcall(findBell, ctx)
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or {}
	local goal = tonumber(data.Goal) or tonumber(run and run.Goal) or 5
	local a: any = { RunId = run and run.RunId, Bell = okBell and bell or nil, Angle = 0, Vel = 0, Roll = 0, Count = tonumber(data.Count) or 0,
		Goal = goal, Ctx = ctx }
	active = a
	if a.Bell then
		local okGui, gui, pips = pcall(buildGui, ctx, a.Bell.Pivot, goal)
		if okGui then
			a.Gui, a.Pips = gui, pips
			setPips(a, a.Count)
		end
		-- a damped pendulum (the strike gives it velocity), posed every frame while it moves
		a.Bind = RunService.Heartbeat:Connect(function(dt)
			if active ~= a then
				return
			end
			local k, damp = 26, 3.2
			a.Vel += (-k * a.Angle - damp * a.Vel) * dt
			a.Angle += a.Vel * dt
			a.Roll *= math.exp(-dt * 4)
			if math.abs(a.Angle) > 1e-3 or math.abs(a.Vel) > 1e-3 or math.abs(a.Roll) > 1e-3 then
				pcall(poseBell, a.Bell, a.Angle, a.Roll)
			end
		end)
	end
	local Trials = ctx and ctx.Trials
	if Trials and Trials.Banner then
		pcall(Trials.Banner, "TRIAL OF THE TOLL", "ИСПЫТАНИЕ ЗВОНА", { Sub = { "Ring the hand-bell with 5 PERFECT hits", "Позвони в колокольчик 5 идеальными ударами" } })
	end
end

function P.Update(_ctx: any, run: any)
	local a = active
	if not a or type(run) ~= "table" then
		return
	end
	local data = type(run.Data) == "table" and run.Data or {}
	local count = tonumber(data.Count)
	if count and count ~= a.Count then
		a.Count = count
		if a.Pips then
			setPips(a, count)
		end
	end
end

function P.Signal(ctx: any, kind: string, data: any, _run: any)
	local a = active
	if kind ~= "Toll" or not a or type(data) ~= "table" then
		return
	end
	local pos = a.Bell and a.Bell.Pivot.Position - V3(0, 1, 0) or anchorPos()
	local reduced = ctx and ctx.Shared and ctx.Shared.ReducedMotion()
	if data.Counted then
		a.Count = tonumber(data.Count) or (a.Count + 1)
		if a.Pips then
			setPips(a, a.Count)
		end
		swing(a, reduced and 1.2 or 3.4)
		play(ctx, "Toll", pos, { Pitch = MELODY[math.clamp(a.Count, 1, #MELODY)], Volume = 1 })
		pcall(function()
			ctx.FX.Ring(V3(pos.X, 0, pos.Z), GOLD, 7, .7)
			ctx.FX.Burst(pos, { Color = GOLD, Color2 = C3(255, 240, 200), Count = 14, Speed = { 2, 6 }, Lifetime = { .4, .8 }, Size = { .25, .4, 0 },
				Acceleration = V3(0, 1, 0) })
		end)
	else
		a.Roll += (math.random() < .5 and -1 or 1) * (reduced and .03 or .09)
		swing(a, reduced and .3 or .8)
		play(ctx, "Toll", pos, { Pitch = .62, Volume = .45 })
		pcall(function()
			ctx.FX.Popup(pos + V3(0, 3, 0), T(ctx, "ON THE BEAT!"), C3(255, 150, 170), false)
		end)
	end
end

function P.Stop(ctx: any, _run: any, result: any)
	local a = active
	if a and (result == "Won" or (type(result) == "table" and result.Kind == "Won")) then
		local pos = a.Bell and a.Bell.Pivot.Position - V3(0, 1, 0) or anchorPos()
		-- the closing flourish: three quick tolls up the scale, a golden burst
		for i, pitch in ipairs({ 1.5, 1.68, 2 }) do
			task.delay((i - 1) * .16, function()
				play(ctx, "Toll", pos, { Pitch = pitch, Volume = .9 })
			end)
		end
		swing(a, 4)
		pcall(function()
			ctx.FX.Burst(pos, { Color = GOLD, Color2 = C3(200, 160, 255), Count = 36, Speed = { 4, 11 }, Lifetime = { .6, 1.3 }, Size = { .35, .6, 0 } })
			ctx.FX.Ring(V3(pos.X, 0, pos.Z), GOLD, 12, 1)
		end)
		task.delay(1.6, function()
			if active == a then
				cleanup()
			end
		end)
		return
	end
	cleanup()
end

function P.HudLines(run: any): { string }?
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or {}
	local count = tonumber(data.Count) or 0
	local goal = tonumber(data.Goal) or 5
	local ctx = active and active.Ctx or nil
	return { string.format(T(ctx, "Tolls on the beat: %d / %d"), count, goal), T(ctx, "Only a PERFECT hit rings the bell") }
end

function P.Active(): boolean
	return active ~= nil
end

return P
