-- BELL SEAL VII · LAST BELL TRIAL · client (StarterPlayerScripts.HalloweenClient.Trials.Bell, WP-J; DESIGN §8.4 item 7,
-- §8.6 assault, §24.1 presenter contract, §24.2 "chain glow in the Last Bell Trial (J)").
-- Two layers:
-- * ARENA (boots once; every client within Seals2Config.Client.ArenaRange of the Black Bell Arena, members or not) reads
--   RS.Halloween.State.BellArena {Mode "" | "Trial" | "Assault", Wave, TollSerial, Chain, ChainSince, ChainHits,
--   ChainNeed, Pulse, Bright, Broken, WeakId, KeeperId, AttackSerial} (written by SealBell / Resonance; late joiners get
--   the live state):
--   - THE BELLKEEPER (Models.Seals2.Bellkeeper; the "Assault" variant while the Black Bell Assault rings) floats at
--     UnderyardLayout.Arena.Bellkeeper holding a rope stretched up to the Black Bell's waist (follows the bell's sway);
--     every toll it hauls the rope down (Bus "UyBellStrike" {Strength} swings the bell harder: UnderyardFX owns the
--     bell's pivot), the toll booms; every volley (AttackSerial) it raises its hand-bell and its lantern heart flares.
--   - wave 2: the ringing chain's ChainGlow band pulses on the server's pulse clock (bright = the window where a Perfect
--     counts) with a closing beat ring around the anchor that lands on each bright window, a hits / needed sign over it;
--     a broken chain shatters and its links vanish (restored when the arena empties).
--   - wave 3 (WeakId) the heart's cage opens and the heart throbs; hits flash it. Beaten (the weak point / the assault
--     target breaks): the Bellkeeper lets go of the rope, rises and comes apart into moths and violet ash.
-- * PRESENTER of the trial (Ids LastBell): wave banners, a marker on the ringing chain / the heart, the counted-hit
--   popups, HUD lines (tolls survived, chain hits, heart HP).
-- Client-local only; every touched world part is restored when the arena empties or the module stops; ReducedMotion:
-- no float / sway / shakes, poses jump.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals2View"))

local P = { Ids = { "LastBell" } }

local player = Players.LocalPlayer
local L = View.L
local Cfg = View.Config
local BC = Cfg.Bell
local CC = Cfg.Client
local SR = View.Rules
local Layout = View.Layout
local V3 = Vector3.new
local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = RGB(16, 12, 26)
local RUNE = RGB(170, 100, 255)
local VIOLET = RGB(150, 80, 230)
local VIOLET_HI = RGB(196, 150, 255)
local CANDLE = RGB(255, 170, 80)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local ACT = View.Base.Seals[7].Activity or {}

local DIRS = {
	N = { "NORTH", "СЕВЕРНАЯ" }, E = { "EAST", "ВОСТОЧНАЯ" }, S = { "SOUTH", "ЮЖНАЯ" }, W = { "WEST", "ЗАПАДНАЯ" },
}

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

local function rootPos(): Vector3?
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return root and (root :: BasePart).Position or nil
end

local function stage(): Instance?
	local st = Halloween:FindFirstChild("State")
	return st and st:FindFirstChild("BellArena") or nil
end

local function attr(name: string, d: any): any
	local f = stage()
	local v = f and f:GetAttribute(name)
	if v == nil then
		return d
	end
	return v
end

local function arenaModel(): Instance?
	local root = View.Root()
	return root and root:FindFirstChild("BlackBellArena") or nil
end

local function keeperGround(): Vector3
	local k = Layout.Arena.Bellkeeper
	return V3(k.X, Layout.Arena.Centre.Y, k.Z)
end

local function chainPos(key: string): Vector3
	local base = arenaModel()
	local m = base and base:FindFirstChild("ArenaChain_" .. key)
	if m and m:IsA("Model") then
		local p = m:GetPivot().Position
		return V3(p.X, Layout.Arena.Centre.Y, p.Z)
	end
	return Layout.Arena.Chains[key] or Layout.Arena.Centre
end
P.ChainPos = chainPos

-- the Black Bell's waist on the Bellkeeper's side (live: the bell sways)
local function ropeTop(): Vector3
	local base = arenaModel()
	local bell = base and base:FindFirstChild("BlackBell")
	local k = keeperGround()
	if bell and bell:IsA("Model") then
		local crown = bell:GetPivot()
		local waist = (crown * CFrame.new(0, -15.2, 0)).Position
		local d = V3(k.X - waist.X, 0, k.Z - waist.Z)
		return waist + (d.Magnitude > .1 and d.Unit or V3(0, 0, 1)) * 7.5
	end
	local b = Layout.Arena.Bell
	local d = V3(k.X - b.X, 0, k.Z - b.Z)
	return V3(b.X, b.Y - 3.4, b.Z) + (d.Magnitude > .1 and d.Unit or V3(0, 0, 1)) * 7.5
end

---------------------------------------------------------------------------------------------------------------------
-- arena state
---------------------------------------------------------------------------------------------------------------------
local arena: any = {
	Mode = "", Keeper = nil, Rope = nil, Chains = {}, Beat = nil, Sign = nil, LastToll = nil, LastAttack = nil, Broken = "",
	Defeated = false, Targets = {}, Folder = nil,
}

local function folder(): Instance
	local f = arena.Folder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "BellArena"
	nf.Parent = View.Folder()
	arena.Folder = nf
	return nf
end

local function plainPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = folder()
	return p
end

-- chains -------------------------------------------------------------------------------------------------------------
local function chainRec(key: string): any
	local rec = arena.Chains[key]
	if rec and rec.Model.Parent then
		return rec
	end
	local base = arenaModel()
	local m = base and base:FindFirstChild("ArenaChain_" .. key)
	if not m or not m:IsA("Model") then
		return nil
	end
	rec = { Model = m, Glow = {}, Links = {}, Broken = false }
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "ChainGlow" then
				table.insert(rec.Glow, { Part = d, Color = d.Color, Transparency = d.Transparency, Material = d.Material })
			elseif d.Position.Y > 7 then
				-- the chain links rising to the bell (above the bollard's cap)
				table.insert(rec.Links, d)
			end
		end
	end
	arena.Chains[key] = rec
	return rec
end

local function restoreChain(rec: any)
	for _, g in ipairs(rec.Glow) do
		if g.Part.Parent then
			g.Part.Color = g.Color
			g.Part.Transparency = g.Transparency
			g.Part.Material = g.Material
		end
	end
	for _, p in ipairs(rec.Links) do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	rec.Broken = false
end

local function setGlow(rec: any, color: Color3, transparency: number)
	for _, g in ipairs(rec.Glow) do
		if g.Part.Parent then
			g.Part.Color = color
			g.Part.Transparency = transparency
		end
	end
end

local function shatterChain(key: string, rec: any?)
	local pos = chainPos(key)
	audio("ChainBreak", pos + V3(0, 4, 0), { Volume = 1 })
	fx("Burst", pos + V3(0, 6, 0), { Color = RUNE, Color2 = WHITE, Count = 36, Speed = { 10, 20 } })
	fx("Shockwave", pos + V3(0, .3, 0), VIOLET, 10, .8)
	if rec then
		rec.Broken = true
		local top = ropeTop()
		for _, p in ipairs(rec.Links) do
			if p.Parent then
				p.LocalTransparencyModifier = 1
			end
		end
		-- a few links tumble down along the old chain line
		if not View.Reduced() then
			local count = View.Detail(10, 6, 3)
			for i = 1, count do
				local at = pos:Lerp(top, i / (count + 1)) + V3(0, 6, 0)
				local link = plainPart("FallingLink", V3(.6, 1.6, .9), RGB(40, 36, 48), Enum.Material.CorrodedMetal)
				link.CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 3, math.random() * 3, 0)
				local vel = V3((math.random() - .5) * 14, math.random() * 6, (math.random() - .5) * 14)
				local cf0 = link.CFrame
				View.Animate(1.3, function(a)
					local t = a * 1.3
					link.CFrame = cf0 + vel * t + V3(0, -40 * t * t, 0)
					link.Transparency = a * a
				end, function()
					link:Destroy()
				end)
			end
		end
		setGlow(rec, RGB(40, 30, 50), .4)
	end
end

-- the beat ring + hits sign of the ringing chain
local function beatParts(): any
	if arena.Beat then
		return arena.Beat
	end
	local n = View.Detail(20, 16, 12)
	local segs = {}
	for i = 1, n do
		local s = plainPart("BeatSegment", V3(1, .12, .3), WHITE, Enum.Material.Neon)
		s.Transparency = 1
		segs[i] = s
	end
	local anchor = plainPart("ChainSignAnchor", Vector3.one * .2, WHITE)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7, 2.2)
	gui.StudsOffset = V3(0, 10, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = anchor
	gui:SetAttribute("NoTranslate", true)
	gui.Parent = anchor
	local function label(y: number, h: number, col: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0, y)
		t.Size = UDim2.fromScale(1, h)
		t.FontFace = FONT
		t.TextScaled = true
		t.TextColor3 = col
		t.Text = ""
		t:SetAttribute("NoTranslate", true)
		local s = Instance.new("UIStroke")
		s.Color = INK
		s.Thickness = 2
		s.Parent = t
		t.Parent = gui
		return t
	end
	arena.Beat = { Segs = segs, Anchor = anchor, Gui = gui, Count = label(0, .6, WHITE), Hint = label(.6, .4, VIOLET_HI) }
	return arena.Beat
end

local function dropBeat()
	local b = arena.Beat
	arena.Beat = nil
	if b then
		for _, s in ipairs(b.Segs) do
			s:Destroy()
		end
		b.Anchor:Destroy()
	end
end

-- keeper -------------------------------------------------------------------------------------------------------------
local function dropKeeper()
	local k = arena.Keeper
	arena.Keeper = nil
	if k then
		k.Model:Destroy()
	end
	if arena.Rope then
		arena.Rope:Destroy()
		arena.Rope = nil
	end
end

local function buildKeeper(variant: string): any
	local okM, model = pcall(View.Models.Bellkeeper, { Variant = variant == "Assault" and "Assault" or nil, Lite = View.Quality() == "Low" })
	if not okM or not model then
		return nil
	end
	model.Parent = folder()
	local function sub(name: string): (Model?, CFrame?)
		local s = model:FindFirstChild(name)
		if s and s:IsA("Model") then
			return s, s:GetPivot()
		end
		return nil, nil
	end
	local ropeArm, ropeRel = sub("RopeArm")
	local bellArm, bellRel = sub("BellArm")
	local k: any = { Model = model, Variant = variant, PivotRel = model:GetPivot(), RopeArm = ropeArm, RopeRel = ropeRel, BellArm = bellArm,
		BellRel = bellRel, Pull = 0, Raise = 0, Flash = 0, Born = os.clock(), Cage = {}, Glow = {}, Heart = nil, Phase = math.random() * 6 }
	k.RopeHand = ropeArm and ropeArm:FindFirstChild("RopeHand") or nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Rope" then
				d.Transparency = 1 -- the stub: the presenter's rope goes all the way up
			elseif d.Name == "HeartCage" or d.Name == "HeartCap" then
				table.insert(k.Cage, { Part = d, T = d.Transparency })
			elseif d.Name == "Heart" then
				k.Heart = d
				k.HeartColor = d.Color
			elseif d.Name == "EyeL" or d.Name == "EyeR" or d.Name == "Crack" or d.Name == "Crown" then
				table.insert(k.Glow, { Part = d, Color = d.Color })
			end
		end
	end
	local rope = plainPart("BellRope", V3(.4, .4, 1), RGB(120, 92, 62), Enum.Material.Fabric)
	arena.Rope = rope
	-- appear: rising out of violet smoke
	local g = keeperGround()
	fx("Burst", g + V3(0, 2, 0), { Color = VIOLET, Color2 = INK, Count = 30, Speed = { 4, 10 }, Spread = 70, Direction = V3(0, 1, 0),
		Lifetime = { .8, 1.6 }, Size = { 1.5, 3, 0 } })
	audio("BossEmerge", g, { Volume = .8 })
	return k
end

local function targetHP(id: number): (number?, BasePart?)
	if id <= 0 then
		return nil, nil
	end
	local part = arena.Targets[id]
	if not part or not part.Parent then
		part = View.Target(id)
		arena.Targets[id] = part
	end
	if not part then
		return nil, nil
	end
	return num(part:GetAttribute("HP"), 0), part
end

-- the Bellkeeper is beaten: lets go of the rope, rises, comes apart into moths and ash
local function defeat()
	local k = arena.Keeper
	if not k or k.Defeat then
		return
	end
	k.Defeat = os.clock()
	arena.Defeated = true
	local base = k.Model:GetPivot()
	local pos = base.Position + V3(0, 8, 0)
	audio("BossDeath", pos, { Volume = 1 })
	audio("BellTollHuge", ropeTop(), { Volume = .9, Pitch = .8 })
	fx("Burst", pos, { Color = VIOLET_HI, Color2 = CANDLE, Count = 50, Speed = { 10, 24 } })
	fx("Shockwave", keeperGround() + V3(0, .3, 0), VIOLET, 22, 1.1)
	View.Bus.Fire("UyBellStrike", { Strength = 2.5 })
	pcall(View.MothSwarm, pos, pos + V3(0, 30, -10), { Count = 12, Seconds = 3, StopShort = 0 })
	if arena.Rope then
		arena.Rope:Destroy()
		arena.Rope = nil
	end
	local parts = {}
	for _, d in ipairs(k.Model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, { Part = d, T = d.Transparency })
		end
	end
	local model = k.Model
	View.Animate(2.4, function(a)
		model:PivotTo(base * CFrame.new(0, View.Ease(a) * 9, 0) * CFrame.Angles(0, a * 1.2, 0))
		for _, e in ipairs(parts) do
			e.Part.Transparency = e.T + (1 - e.T) * math.clamp(a * 1.3, 0, 1)
		end
	end, function()
		if arena.Keeper == k then
			dropKeeper()
		end
	end)
end

-- the arena empties: everything back the way the builder left it
local function teardown()
	-- the trial ends in the same breath as its heart breaks: still play the defeat
	local _, last = targetHP(arena.HitId or 0)
	if arena.Keeper and not arena.Keeper.Defeat and ((last and last:GetAttribute("EndReason") == "Broke") or arena.HitHP == 0) then
		defeat()
	end
	if arena.Keeper and not arena.Keeper.Defeat then
		local k = arena.Keeper
		local parts = {}
		for _, d in ipairs(k.Model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, { Part = d, T = d.Transparency })
			end
		end
		if arena.Rope then
			arena.Rope:Destroy()
			arena.Rope = nil
		end
		View.Animate(.9, function(a)
			for _, e in ipairs(parts) do
				e.Part.Transparency = e.T + (1 - e.T) * a
			end
		end, function()
			if arena.Keeper == k then
				dropKeeper()
			end
		end)
	end
	for key, rec in pairs(arena.Chains) do
		pcall(restoreChain, rec)
		arena.Chains[key] = nil
	end
	dropBeat()
	arena.Broken = ""
	arena.Defeated = false
	arena.Targets = {}
	arena.HitId, arena.HitHP = 0, nil
end

---------------------------------------------------------------------------------------------------------------------
-- per-frame arena step
---------------------------------------------------------------------------------------------------------------------
local function onToll(mode: string)
	local k = arena.Keeper
	if k then
		k.Pull = 1
	end
	local top = ropeTop()
	View.Bus.Fire("UyBellStrike", { Strength = mode == "Assault" and 2 or 1.4 })
	local pos = rootPos()
	local near = pos ~= nil and (pos - Layout.Arena.Centre).Magnitude <= Layout.Arena.Radius + 40
	audio(near and "BellTollHuge" or "BellTollFar", top, { Volume = near and .9 or .7 })
	fx("Light", top, VIOLET_HI, 60, 3, 1.2)
	if near and not View.Reduced() then
		local cinema = ctx and ctx.Modules and ctx.Modules.Cinema
		if cinema and cinema.Shake then
			pcall(cinema.Shake, .4, .5)
		else
			fx("Shake", .4, .5)
		end
	end
end

local function onAttack(kind: string)
	local k = arena.Keeper
	if k then
		k.Raise = 1
		k.Flash = math.max(k.Flash, .8)
	end
	local g = keeperGround() + V3(0, 9, 0)
	audio("LanternFlare", g, { Volume = .8 })
	audio(kind == "Circles" and "HazardWarn" or "BossRoar", g, { Volume = .5, Pitch = 1.3 })
	fx("Light", g, CANDLE, 30, 2.5, .9)
end

local function step(dt: number)
	local f = stage()
	local mode = f and f:GetAttribute("Mode") or ""
	if type(mode) ~= "string" then
		mode = ""
	end
	local cam = workspace.CurrentCamera
	local centre = Layout.Arena.Centre
	local inRange = cam ~= nil and (cam.CFrame.Position - centre).Magnitude <= CC.ArenaRange
	if mode ~= arena.Mode then
		local was = arena.Mode
		arena.Mode = mode
		if was ~= "" then
			teardown()
		end
		arena.LastToll = num(attr("TollSerial", 0))
		arena.LastAttack = num(attr("AttackSerial", 0))
		arena.Broken = tostring(attr("Broken", ""))
	end
	if mode == "" then
		return
	end
	local now = View.Shared.Now()
	local t = os.clock()
	local reduced = View.Reduced()
	-- serial events (tolls, volleys) even out of range: the toll is heard across the Underyard
	local toll = num(attr("TollSerial", 0))
	if arena.LastToll ~= nil and toll > arena.LastToll then
		onToll(mode)
	end
	arena.LastToll = toll
	local atk = num(attr("AttackSerial", 0))
	if arena.LastAttack ~= nil and atk > arena.LastAttack then
		onAttack(tostring(attr("Attack", "")))
	end
	arena.LastAttack = atk
	if not inRange then
		return
	end
	-- the keeper
	local wantVariant = mode == "Assault" and "Assault" or "Trial"
	if not arena.Defeated and (not arena.Keeper or arena.Keeper.Variant ~= wantVariant) then
		dropKeeper()
		arena.Keeper = buildKeeper(wantVariant)
	end
	local weakId = math.floor(num(attr("WeakId", 0)))
	local keeperId = math.floor(num(attr("KeeperId", 0)))
	local hitId = mode == "Assault" and keeperId or weakId
	local hp, part = targetHP(hitId)
	if hitId > 0 then
		arena.HitId, arena.HitHP = hitId, hp
	end
	local k = arena.Keeper
	if part and part:GetAttribute("EndReason") == "Broke" then
		defeat()
	elseif k and hp and k.LastHP and hp < k.LastHP then
		k.Flash = 1
	end
	if k then
		k.LastHP = hp or k.LastHP
	end
	if k and not k.Defeat then
		k.Pull = math.max(0, k.Pull - dt * 1.6)
		k.Raise = math.max(0, k.Raise - dt * 1.1)
		k.Flash = math.max(0, k.Flash - dt * 3)
		local rise = math.clamp((t - k.Born) / 1.2, 0, 1)
		local float = reduced and 0 or math.sin(t * 1.3 + k.Phase) * .35
		local sway = reduced and 0 or math.sin(t * .9 + k.Phase) * .03
		local g = keeperGround()
		local body = CFrame.new(g + V3(0, (1 - View.Ease(rise)) * -6 + float + .6, 0)) * CFrame.Angles(0, 0, sway)
		k.Model:PivotTo(body * k.PivotRel)
		-- haul: a quick down-stroke then the slow return
		local pull = k.Pull > .75 and (1 - k.Pull) / .25 or k.Pull / .75
		if k.RopeArm and k.RopeRel then
			k.RopeArm:PivotTo(body * k.RopeRel * CFrame.Angles(-.55 * pull, 0, 0))
		end
		if k.BellArm and k.BellRel then
			local r = k.Raise > .7 and (1 - k.Raise) / .3 or k.Raise / .7
			local ring = reduced and 0 or math.sin(t * 30) * .15 * k.Raise
			k.BellArm:PivotTo(body * k.BellRel * CFrame.Angles(-1.6 * r, 0, ring))
		end
		-- the rope from the hand up to the bell
		if arena.Rope then
			local a = k.RopeHand and k.RopeHand.Position or (body * CFrame.new(-1.6, 15, -.9)).Position
			local b = ropeTop()
			local len = (b - a).Magnitude
			if len > .5 then
				arena.Rope.Size = V3(.4, .4, len)
				arena.Rope.CFrame = CFrame.lookAt((a + b) / 2, b)
			end
		end
		-- heart: caged until the weak point opens (trial wave 3); the assault keeper's heart always burns
		local open = (mode == "Trial" and weakId > 0) or mode == "Assault"
		local beat = reduced and .5 or (.5 + .5 * math.sin(t * (open and 7 or 2.5)))
		if k.Heart then
			k.Heart.Color = (k.HeartColor or CANDLE):Lerp(WHITE, math.clamp(k.Flash + (open and beat * .45 or beat * .15), 0, 1))
		end
		for _, c in ipairs(k.Cage) do
			c.Part.Transparency = open and math.max(c.T, .85) or c.T
		end
		for _, e in ipairs(k.Glow) do
			e.Part.Color = e.Color:Lerp(WHITE, k.Flash)
		end
	end
	-- chains (trial wave 2)
	local broken = tostring(attr("Broken", ""))
	if broken ~= arena.Broken then
		for i = 1, #broken do
			local key = string.sub(broken, i, i)
			if not string.find(arena.Broken, key, 1, true) then
				shatterChain(key, chainRec(key))
			end
		end
		arena.Broken = broken
	end
	local active = mode == "Trial" and tostring(attr("Chain", "")) or ""
	for _, key in ipairs(BC.Chains.Order) do
		local rec = chainRec(key)
		if rec and not rec.Broken and string.find(broken, key, 1, true) then
			-- broken before we looked (late join / streamed in): hide it quietly
			rec.Broken = true
			for _, lp in ipairs(rec.Links) do
				if lp.Parent then
					lp.LocalTransparencyModifier = 1
				end
			end
			setGlow(rec, RGB(40, 30, 50), .4)
		end
		if rec and not rec.Broken then
			if key == active then
				local since = num(attr("ChainSince", now))
				local period = math.max(.2, num(attr("Pulse", ACT.PulsePeriod or 1.2)))
				local bright = math.clamp(num(attr("Bright", BC.Chains.Bright)), .05, 1)
				local tt = math.max(0, now - since)
				local phase = (tt % period) / period
				local on = phase <= bright
				setGlow(rec, on and WHITE:Lerp(RUNE, .25) or RUNE:Lerp(INK, .55), on and 0 or .35)
			else
				setGlow(rec, mode == "Trial" and RUNE:Lerp(INK, .45) or RUNE:Lerp(INK, .25), .3)
			end
		end
	end
	if active ~= "" then
		local b = beatParts()
		local pos = chainPos(active)
		b.Anchor.CFrame = CFrame.new(pos)
		local since = num(attr("ChainSince", now))
		local period = math.max(.2, num(attr("Pulse", ACT.PulsePeriod or 1.2)))
		local bright = math.clamp(num(attr("Bright", BC.Chains.Bright)), .05, 1)
		local phase = (math.max(0, now - since) % period) / period
		local on = phase <= bright
		-- dark part: the ring closes in; it lands on the anchor when the bright window opens
		local close = on and 0 or (1 - (phase - bright) / math.max(.01, 1 - bright))
		local r = 2.6 + close * 6
		local n = #b.Segs
		for i, s in ipairs(b.Segs) do
			local ang = (i - .5) / n * 2 * math.pi
			local at = pos + V3(math.cos(ang) * r, .2, math.sin(ang) * r)
			s.Size = V3(2 * math.pi * r / n * .6, .12, .3)
			s.CFrame = CFrame.lookAt(at, pos + V3(0, .2, 0)) * CFrame.Angles(0, math.pi / 2, 0)
			s.Color = on and WHITE or VIOLET_HI
			s.Transparency = on and 0 or .35
		end
		local hits, need = math.floor(num(attr("ChainHits", 0))), math.floor(num(attr("ChainNeed", 0)))
		b.Count.Text = need > 0 and (hits .. " / " .. need) or ""
		b.Hint.Text = L("PERFECT WHILE IT SHINES", "ИДЕАЛЬНО, ПОКА СИЯЕТ")
		b.Count.TextColor3 = on and WHITE or VIOLET_HI
	elseif arena.Beat then
		dropBeat()
	end
end

local function boot(c: any?)
	if booted then
		return
	end
	booted = true
	ctx = View.Ctx(c)
	if not View.Shared.Chapter2Enabled() then
		return
	end
	local warned = false
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not warned then
			warned = true
			warn("Trials.Bell: " .. tostring(err))
		end
	end)
end
P.Boot = boot

---------------------------------------------------------------------------------------------------------------------
-- presenter (LastBell)
---------------------------------------------------------------------------------------------------------------------
local active: any = nil -- {RunId, Maid, Wave, Mark, Tolls, TollsNeed, Chain, Hits, Need, Left, WeakId}

local function unmark(a: any)
	if a.Mark then
		View.Unmark(a.Mark)
		a.Mark = nil
	end
end

local function cleanup()
	local a = active
	active = nil
	if a then
		unmark(a)
		a.Maid.Clean()
	end
end

local WAVE_BANNERS = {
	{ { "WAVE 1 · SHOCKWAVE RINGS", "ВОЛНА 1 · УДАРНЫЕ КОЛЬЦА" }, { "When the bell tolls, run through the gaps in the rings",
		"Когда бьёт колокол, беги через просветы в кольцах" } },
	{ { "WAVE 2 · FOUR CHAINS", "ВОЛНА 2 · ЧЕТЫРЕ ЦЕПИ" }, { "Strike the ringing chain: only PERFECT hits while it shines count",
		"Бей звенящую цепь: считаются только ИДЕАЛЬНЫЕ удары, пока она сияет" } },
	{ { "WAVE 3 · THE HEART", "ВОЛНА 3 · СЕРДЦЕ" }, { "Burn the Bellkeeper's lantern heart and dodge the volleys",
		"Жги сердце-фонарь Звонаря и уворачивайся от залпов" } },
}

local function readData(a: any, data: any)
	if type(data) ~= "table" then
		return
	end
	a.Wave = num(data.Wave, a.Wave or 0)
	a.Tolls = num(data.Tolls, a.Tolls or 0)
	a.TollsNeed = num(data.TollsNeed, a.TollsNeed or BC.Rings.Tolls)
	a.Chain = type(data.Chain) == "string" and data.Chain or a.Chain
	a.Hits = num(data.ChainHits, a.Hits or 0)
	a.Need = num(data.ChainNeed, a.Need or 0)
	a.Left = num(data.ChainsLeft, a.Left or #BC.Chains.Order)
	a.WeakId = num(data.WeakId, a.WeakId or 0)
	a.WeakMax = num(data.WeakMax, a.WeakMax or 0)
end

function P.Start(c: any, run: any)
	boot(c)
	ctx = View.Ctx(c)
	cleanup()
	if type(run) ~= "table" then
		return
	end
	local a: any = { RunId = run.RunId, Maid = View.Maid(), Wave = 0 }
	active = a
	readData(a, run.Data)
	View.Banner(ctx, "LAST BELL TRIAL", "ИСПЫТАНИЕ ПОСЛЕДНЕГО КОЛОКОЛА", { Sub = { "The Bellkeeper pulls the rope...",
		"Звонарь тянет верёвку..." }, Color = View.Colors.Chain, Seconds = 3 })
end

function P.Update(_c: any, run: any)
	local a = active
	if not a or type(run) ~= "table" or run.RunId ~= a.RunId then
		return
	end
	readData(a, run.Data)
end

function P.Signal(c: any, kind: string, data: any, run: any)
	ctx = View.Ctx(c)
	local a = active
	if not a or type(data) ~= "table" then
		return
	end
	if run then
		readData(a, run.Data)
	end
	if kind == "BellWave" then
		a.Wave = num(data.Wave, a.Wave)
		local b = WAVE_BANNERS[a.Wave]
		if b then
			View.Banner(ctx, b[1][1], b[1][2], { Sub = b[2], Color = View.Colors.Chain, Seconds = 3 })
		end
		if a.Wave == 3 then
			unmark(a)
		end
	elseif kind == "ChainActive" then
		a.Chain = tostring(data.Key or "")
		a.Need = num(data.Need, a.Need)
		a.Hits = 0
		unmark(a)
		local dir = DIRS[a.Chain] or { a.Chain, a.Chain }
		a.Mark = View.Mark(ctx, chainPos(a.Chain) + V3(0, 7, 0), dir[1] .. " CHAIN", dir[2] .. " ЦЕПЬ")
		audio("ChainPulse", chainPos(a.Chain) + V3(0, 4, 0), { Volume = .8 })
	elseif kind == "ChainHit" then
		a.Hits = num(data.Hits, a.Hits)
		a.Need = num(data.Need, a.Need)
		local pos = chainPos(tostring(data.Key or a.Chain or "N")) + V3(0, 7, 0)
		if data.UserId == player.UserId then
			if data.Counted then
				fx("Popup", pos, "+1", WHITE, true)
				audio("ChainPulse", pos, { Volume = .7, Pitch = 1.2 })
			else
				fx("Popup", pos, L("ON THE SHINE!", "КОГДА СИЯЕТ!"), VIOLET_HI, false)
			end
		elseif data.Counted then
			fx("Popup", pos, "+1", VIOLET_HI, false)
		end
	elseif kind == "ChainBreak" then
		a.Left = num(data.Left, a.Left)
		a.Chain = ""
		unmark(a)
		if a.Left > 0 then
			View.Toast(ctx, "Chain broken · " .. a.Left .. " left", "Цепь сломана · осталось " .. a.Left, "success")
		end
	elseif kind == "WeakOpen" then
		a.WeakId = num(data.TargetId, a.WeakId)
		a.WeakMax = num(data.Max, a.WeakMax)
		unmark(a)
		a.Mark = View.Mark(ctx, keeperGround() + V3(0, BC.Burn.Height + 2, 0), "THE HEART", "СЕРДЦЕ")
		audio("WeakOpen", keeperGround() + V3(0, BC.Burn.Height, 0), { Volume = .9 })
	end
end

function P.Stop(c: any, run: any, _result: any)
	ctx = View.Ctx(c)
	local a = active
	if a and run and run.RunId and a.RunId ~= run.RunId then
		return
	end
	cleanup()
end

function P.HudLines(_run: any): { string }?
	local a = active
	if not a then
		return nil
	end
	local w = math.floor(a.Wave or 0)
	if w <= 0 then
		return { L("The Bellkeeper pulls the rope...", "Звонарь тянет верёвку...") }
	elseif w == 1 then
		return { L("Wave 1 / 3 · tolls survived", "Волна 1 / 3 · пережито ударов") .. ": " .. math.floor(a.Tolls or 0) .. " / " .. math.floor(a.TollsNeed or BC.Rings.Tolls),
			L("Run through the gaps in the rings", "Беги через просветы в кольцах") }
	elseif w == 2 then
		local dir = DIRS[a.Chain or ""]
		local lines = { L("Wave 2 / 3 · chains left", "Волна 2 / 3 · осталось цепей") .. ": " .. math.floor(a.Left or 0) }
		if dir then
			table.insert(lines, L(dir[1] .. " CHAIN", dir[2] .. " ЦЕПЬ") .. ": " .. math.floor(a.Hits or 0) .. " / " .. math.floor(a.Need or 0)
				.. " · " .. L("PERFECT while it shines", "ИДЕАЛЬНО, пока сияет"))
		end
		return lines
	end
	local hp, max = 0, a.WeakMax or 0
	local part = View.Target(a.WeakId)
	if part then
		hp = num(part:GetAttribute("HP"), 0)
		max = math.max(max, num(part:GetAttribute("MaxHP"), 0))
	end
	return { L("Wave 3 / 3 · the heart", "Волна 3 / 3 · сердце") .. ": " .. math.ceil(hp) .. " / " .. math.ceil(math.max(1, max)),
		L("Dodge the lines and circles", "Уворачивайся от линий и кругов") }
end

function P.Init(c: any)
	task.spawn(boot, c)
end

task.defer(function()
	task.wait(2)
	if not booted then
		boot(nil)
	end
end)

return P
