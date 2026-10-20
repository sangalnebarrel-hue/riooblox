-- THE GRAVEKEEPER client presentation (StarterPlayerScripts.HalloweenClient.BossFX). Client only, purely visual.
-- * Renders the boss: a client-local rig built from RS.Halloween.Models.Boss (Motor6D bones, procedural animation driven
--   by the server's Mode attribute: rise / idle / walk / windup / impact / roar / burrow / erupt / stagger / enrage / death /
--   escape), following Workspace.HalloweenLive.Boss.BossRig.BossRoot (or State.Boss.BossCF) with smoothing.
-- * Entrance cinematic (moderate): ground cracks, rocks fly, fog bursts away, green flame pillars, light shake, bass cues,
--   an optional 4 s camera shot for spectators (skipped with ReducedMotion / any input / during other camera owners /
--   while a timing-hit session (MiningActive) or a menu is open, so no circle expires off screen).
-- * Attack telegraphs (growing ground decals: circle / cone), impacts (shockwaves, glowing cracks, debris, bone chips,
--   cursed smoke, moderate distance-scaled shake), knockback for the local character (server Signal Knock).
-- * Minion / prop visuals on the Strike targets (Workspace.HalloweenLive.Targets, attrs Kind/TargetId): skeleton dogs
--   (gait, bite lunge, spawn from the ground, shatter), grave mounds (rise, rumble on hits, skeleton hands from fakes,
--   eruption), cursed rocks (sky fall with telegraph, landing, countdown pulse, explosion, shard hurled into the boss).
-- * Armor plates (State.Boss.Plates / PlateWear: shatter + regrow, 3 crack stages revealed at wear 3 / 6 / 8), weak points
--   (WeakSlots / WeakOpenUntil) + the weak-point digger (your best yard dog, spectral, digs the weak point with you: Bus
--   StrikeBegin Extra.Companion; an event dog runs its Models.EventDogs ability FX), the skeleton shield dome with soul tethers, hit numbers, phase / enrage / defeat / escape /
--   reward banners via Bus "Banner".
-- * Hit reactions: every hit on a plate / weak point (Bus StrikeSwing, also other players' swings) kicks the struck bone away
--   from the hitter and whips the body + head after it (additive, decaying), flashes the plate (Highlight); perfect / crit /
--   weak-point hits hold the rig still for the hit-stop; a glowing crack where a perfect hit landed.
-- * Open weak points read as the brightest thing on the boss: gold / orange / white model parts (Models.Boss), an
--   always-on-top gold Highlight with a white outline, a gold light, a camera-facing spinning reticle and an always-on-top
--   "x3" tag with the seconds left; faster pulse + pumpkin red for the last 2 s; the soul fire dims while the heart is open.
-- * THE GRAVE BELL rings the boss up (Rise): the bell swings (BellSwing / BellPivot contract or the GraveBell part names) and
--   tolls 3 times (shockwave rings, dust from the frame, chains kick, the yard's lanterns gutter), glowing cracks run from
--   the bell down into the pit, fog rises, then the rise cinematic; the camera shot frames the bell, then the pit.
-- * Staged death: killing blow (hit-stop + slow motion, white flash, "KILLING BLOW!" for the hitter) -> stagger -> collapse
--   -> soul burst (the soul flies to the moon) -> bones scatter -> moon flare (+ every lantern flares), moderate camera.
-- Bus events for the HUD (fired here): BossHit {Damage, Weak, Crit, Quality, Slot, Armor, MaxArmor, Share, Heavy},
-- BossPlateCrack {Slot, Stage, Wear}, BossKillingBlow {Mine}, BossDeath {Stage = Stagger|Collapse|SoulBurst|Scatter|MoonFlare}.
-- Honours Shared.Quality() (Low: no flame particles, fewer debris / lights / scattered bones, no 3D reticle) and
-- Shared.ReducedMotion() (no camera shot, no shake, no screen flash; smaller bell swing, still reticle).
-- Everything lives in workspace.DOGROTS_HalloweenFX (SelfManagedFX).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local BossFX = {}

local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local PI = math.pi

local GREEN = RGB(120, 255, 110)
local GREEN_HOT = RGB(206, 255, 196)
local PURPLE = RGB(176, 92, 240)
local PURPLE_DEEP = RGB(104, 36, 196)
local BLOOD = RGB(220, 40, 60)
local BONE = RGB(222, 210, 178)
local STONE = RGB(84, 86, 100)
local DIRT = RGB(70, 54, 44)
local CURSE = RGB(150, 60, 220)
local GOLD = RGB(255, 200, 70) -- weak points only (gold / pumpkin / white appear nowhere else on the boss)
local GOLD_HOT = RGB(255, 236, 150)
local PUMPKIN = RGB(255, 128, 24)
local WHITE = Color3.new(1, 1, 1)
local DUST = RGB(150, 132, 112)
local TOLL = RGB(176, 140, 255) -- the bell's sound-wave rings

local function rand(a: number, b: number): number
	return a + (b - a) * math.random()
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function backOut(t: number): number
	t = math.clamp(t, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function BossFX.Start(ctx)
	local Shared, Config, Layout, Bus, FX, Audio = ctx.Shared, ctx.Config, ctx.Layout, ctx.Bus, ctx.FX, ctx.Audio
	local player = ctx.Player or Players.LocalPlayer
	local L = Shared.L
	local Halloween = RS:WaitForChild("Halloween")
	local Models = require(Halloween:WaitForChild("Models"):WaitForChild("Boss"))
	local stateFolder = Halloween:WaitForChild("State"):WaitForChild("Boss")
	local B = Config.Boss
	local FLOOR = Layout.Pit.FloorY
	local PIT = Layout.Pit.Center

	local function A(name: string): any
		return stateFolder:GetAttribute(name)
	end
	local function now(): number
		return Shared.Now()
	end
	local function low(): boolean
		return Shared.Low()
	end
	local function myRoot(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return (r and r:IsA("BasePart")) and r or nil
	end
	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or PIT
	end
	local function nearPit(extra: number?): boolean
		local r = myRoot()
		local p = r and r.CFrame.Position or camPos()
		return (Vector3.new(p.X - PIT.X, 0, p.Z - PIT.Z)).Magnitude < 70 + (extra or 0) or Shared.InZone(p, 10)
	end
	-- moderate, distance-scaled shake
	local function shakeAt(pos: Vector3, amount: number, duration: number?, range: number?)
		local d = (camPos() - pos).Magnitude
		local k = math.clamp(1 - d / (range or 90), 0, 1)
		if k > .02 then
			FX.Shake(amount * k, duration or .45)
		end
	end
	local function play(cue: string, where: any?, opts: any?)
		if Audio and Audio.Play then
			pcall(Audio.Play, cue, where, opts)
		end
	end
	local function banner(title: string, subtitle: string?, color: Color3?, seconds: number?)
		Bus.Fire("Banner", { Title = title, Subtitle = subtitle, Color = color or GREEN, Style = "Boss", Seconds = seconds or 3.5, NoTranslate = true })
	end
	local function reduced(): boolean
		return Shared.ReducedMotion()
	end
	-- screen flash: none at all with ReducedMotion (FX.Flash would only halve it)
	local function flash(color: Color3, strength: number, duration: number)
		if not reduced() then
			FX.Flash(color, strength, duration)
		end
	end
	-- time-driven cue lists (bell summon, rise, death): stepped by the main loop and BossFX.Debug.Step (so they also run in
	-- the offline tests). cues = {{seconds, fn}}; tl.Cancelled = true drops the rest
	local timelines = {}
	local function timeline(cues: { { any } }): any
		table.sort(cues, function(a, b)
			return a[1] < b[1]
		end)
		local tl = { T0 = os.clock(), Cues = cues, I = 1 }
		table.insert(timelines, tl)
		return tl
	end
	local function stepTimelines()
		local t = os.clock()
		for i = #timelines, 1, -1 do
			local tl = timelines[i]
			while not tl.Cancelled and tl.I <= #tl.Cues and t - tl.T0 >= tl.Cues[tl.I][1] do
				local cue = tl.Cues[tl.I]
				tl.I += 1
				local ok, err = pcall(cue[2])
				if not ok then
					warn("Halloween BossFX cue: " .. tostring(err))
				end
			end
			if tl.Cancelled or tl.I > #tl.Cues then
				table.remove(timelines, i)
			end
		end
	end
	-- attachment world position (works offline too, where WorldPosition is not emulated)
	local function attPos(att: Attachment): Vector3
		local parent = att.Parent
		if parent and parent:IsA("BasePart") then
			return (parent.CFrame * att.CFrame).Position
		end
		return att.CFrame.Position
	end
	local function floorAt(p: Vector3): Vector3
		return Vector3.new(p.X, FLOOR + .06, p.Z)
	end
	-- the pit's real walkable height under p (arena floor, terrace ring, ramps; Models.Boss.Surface, the same maths the
	-- server places the rocks with)
	local function groundAt(p: Vector3): Vector3
		local y = Models.Surface and Models.Surface(Layout, p.X, p.Z) or FLOOR
		return Vector3.new(p.X, y, p.Z)
	end

	---------------------------------------------------------------------------------------------------------------
	-- the boss rig
	---------------------------------------------------------------------------------------------------------------
	local boss = nil -- {Model, Rig, Root, Cur = {bone = CFrame}, Pos, Yaw, Y, Flames, Lights, Plates, Weak, ...}
	local anim = { Mode = "", ModeAt = 0, Attack = "", Impact = 0, ImpactKind = "", Yoff = -40, Phase = 0, Death = nil, Shield = nil,
		HoldUntil = 0, SlowUntil = 0 } -- hit-stop (rig frozen) / slow motion (after the killing blow), os.clock
	local deathTL = nil -- the running death timeline

	local function eachPart(root: Instance, fn)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				fn(d)
			end
		end
	end

	local function destroyBoss()
		anim.Mode, anim.ModeAt, anim.Death = "", 0, nil
		anim.HoldUntil, anim.SlowUntil = 0, 0
		if deathTL then
			deathTL.Cancelled = true
			deathTL = nil
		end
		if boss then
			-- weak-point reticles live in the FX folder (highlight, light and tag go with the model)
			for _, w in pairs(boss.Weak) do
				if w.FX and w.FX.Model then
					w.FX.Model:Destroy()
				end
				w.FX = nil
			end
			if boss.ShieldDome then
				boss.ShieldDome:Destroy()
			end
			if boss.Model then
				boss.Model:Destroy()
			end
			for _, b in pairs(boss.Tethers or {}) do
				b:Destroy()
			end
		end
		boss = nil
	end

	local function buildBoss()
		if boss then
			return boss
		end
		local model = Models.Build()
		model.Name = "TheGravekeeper"
		local rig = Models.Rig(model)
		local b = { Model = model, Rig = rig, Root = rig.Root, Cur = {}, Pos = nil, Yaw = 0, Flames = {}, Lights = {}, Plates = {}, Weak = {},
			Eyes = {}, Tethers = {}, GaitPhase = 0, LastStep = 0, Visible = true }
		-- plates / weak groups, eyes, flame emitters, lights
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("Plate") then
				local parts = {}
				eachPart(d, function(p)
					parts[p] = p.Transparency
				end)
				b.Plates[d:GetAttribute("Slot")] = { Group = d, Parts = parts, Shown = true, Wear = 0 }
			elseif d:IsA("Model") and d:GetAttribute("Weak") then
				local parts = {}
				local core = nil
				eachPart(d, function(p)
					parts[p] = true
					p.Transparency = 1
					if p.Name == "WeakCore" then
						core = p
					end
				end)
				b.Weak[d:GetAttribute("Slot")] = { Group = d, Parts = parts, Shown = false, Core = core }
			elseif d:IsA("BasePart") and (d.Name == "Eye" or d.Name == "EyeCore" or d.Name == "EyeHalo") then
				table.insert(b.Eyes, d)
			elseif d:IsA("BasePart") and (d.Name == "SoulCore" or d.Name == "SoulGlow" or d.Name == "SoulHalo") then
				-- the soul fire in the ribcage (dimmed while the heart weak point is open)
				b.Soul = b.Soul or {}
				b.Soul[d] = d.Transparency
			elseif d:IsA("PointLight") then
				table.insert(b.Lights, d)
				d:SetAttribute("BaseBrightness", d.Brightness)
				local keep = d.Parent and (d.Parent.Name == "SoulLight" or d.Parent.Name == "EyeLight")
				if low() and not keep then
					d.Enabled = false
				end
			elseif d:IsA("Attachment") then
				if d.Name == "FlamePoint" and not low() then
					local purple = d:GetAttribute("Color") == "Purple"
					local s = d:GetAttribute("Size") or 1
					local e = Instance.new("ParticleEmitter")
					e:SetAttribute("HwParticlePriority", true) -- the boss never loses its flames to the particle budget
					e.Texture = FX.Textures.Fire
					e.Color = purple and ColorSequence.new(RGB(232, 196, 255), PURPLE_DEEP) or ColorSequence.new(GREEN_HOT, RGB(40, 200, 90))
					e.LightEmission = 1
					e.LightInfluence = 0
					e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 1.4), NumberSequenceKeypoint.new(.5, s * 1.1), NumberSequenceKeypoint.new(1, 0) })
					e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .3), NumberSequenceKeypoint.new(.6, .5), NumberSequenceKeypoint.new(1, 1) })
					e.Lifetime = NumberRange.new(.45, .8)
					e.Speed = NumberRange.new(3, 6)
					e.SpreadAngle = Vector2.new(12, 12)
					e.Acceleration = Vector3.new(0, 6, 0)
					e.Rate = (Shared.Quality() == "Medium" and 7 or 13) * s
					e.RotSpeed = NumberRange.new(-60, 60)
					e.Parent = d
					table.insert(b.Flames, e)
				elseif d.Name == "Core" then
					b.CoreAtt = d
				elseif d.Name == "Mouth" then
					b.MouthAtt = d
				elseif d.Name == "TailTip" then
					b.TailAtt = d
				elseif string.sub(d.Name, 1, 3) == "Paw" then
					b.Paws = b.Paws or {}
					b.Paws[d.Name] = d
				elseif d.Name == "PlateCenter" then
					b.PlateAtt = b.PlateAtt or {}
					b.PlateAtt[d:GetAttribute("Slot")] = d
				elseif d.Name == "WeakCenter" then
					b.WeakAtt = b.WeakAtt or {}
					b.WeakAtt[d:GetAttribute("Slot")] = d
				end
			end
		end
		b.EyeColors = {}
		for _, e in ipairs(b.Eyes) do
			b.EyeColors[e] = e.Color
		end
		-- embers drifting off the body (one emitter on the soul core)
		if b.CoreAtt and not low() then
			local e = Instance.new("ParticleEmitter")
			e:SetAttribute("HwParticlePriority", true)
			e.Texture = FX.Textures.Sparkle
			e.Color = ColorSequence.new(GREEN, PURPLE)
			e.LightEmission = 1
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(1, 0) })
			e.Lifetime = NumberRange.new(1.4, 2.4)
			e.Speed = NumberRange.new(2, 5)
			e.SpreadAngle = Vector2.new(70, 70)
			e.Acceleration = Vector3.new(0, 3, 0)
			e.Rate = 10
			e.Parent = b.CoreAtt
			table.insert(b.Flames, e)
		end
		model.Parent = FX.Folder()
		boss = b
		return b
	end

	-- where the server says the boss stands (ground centre + yaw)
	local function serverCF(): CFrame?
		local live = workspace:FindFirstChild("HalloweenLive")
		local f = live and live:FindFirstChild("Boss")
		local rig = f and f:FindFirstChild("BossRig")
		local root = rig and rig:FindFirstChild("BossRoot")
		if root and root:IsA("BasePart") and root.CFrame.Position.Y > FLOOR - 30 then
			return root.CFrame
		end
		local cf = A("BossCF")
		if typeof(cf) == "CFrame" then
			return cf
		end
		return nil
	end

	local function yawOf(cf: CFrame): number
		local look = cf.LookVector
		return math.atan2(-look.X, -look.Z)
	end

	local function setLights(mult: number)
		if not boss then
			return
		end
		for _, l in ipairs(boss.Lights) do
			l.Brightness = (l:GetAttribute("BaseBrightness") or 1) * mult
		end
	end

	local function setFlameRate(mult: number)
		if not boss then
			return
		end
		for _, e in ipairs(boss.Flames) do
			if not e:GetAttribute("BaseRate") then
				e:SetAttribute("BaseRate", e.Rate)
			end
			e.Rate = e:GetAttribute("BaseRate") * mult
		end
	end

	local function eyesTo(color: Color3?)
		if not boss then
			return
		end
		for _, e in ipairs(boss.Eyes) do
			local c = color and (e.Name == "EyeCore" and color:Lerp(Color3.new(1, 1, 1), .5) or color) or boss.EyeColors[e]
			FX.Tween(e, .6, { Color = c })
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- procedural animation
	---------------------------------------------------------------------------------------------------------------
	local BONES = {}
	for _, j in ipairs(Models.Joints) do
		table.insert(BONES, j[1])
	end
	local function R(x: number?, y: number?, z: number?): CFrame
		return ANG(x or 0, y or 0, z or 0)
	end

	-- target pose for the current mode (all angles in radians; +X pitch = nose / leg forward-up)
	local function pose(mode: string, t: number, ma: number, moving: number): { [string]: CFrame }
		local P = {}
		local breath = math.sin(t * 1.7)
		-- idle base
		P.Chest = R(breath * .025, 0, 0)
		P.Neck = R(-.05 + math.sin(t * 1.7 + .6) * .035, math.sin(t * .45) * .12, 0)
		P.Head = R(math.sin(t * 1.1) * .03, math.sin(t * .6 + 1) * .1, math.sin(t * .37) * .04)
		P.Jaw = R(-.04 - math.max(0, math.sin(t * .9)) * .1)
		for i = 1, 4 do
			P["Tail" .. i] = R(.05 * i * math.sin(t * .8), math.sin(t * 2.0 - i * .7) * (.08 + i * .03), 0)
		end
		-- walking gait (diagonal pairs)
		if moving > .05 then
			local ph = anim.Gait
			local a = math.sin(ph) * .32 * moving
			local bend = math.max(0, -math.sin(ph)) * .55 * moving
			local bend2 = math.max(0, math.sin(ph)) * .55 * moving
			P.ArmR = R(a, 0, 0)
			P.ForeR = R(-bend, 0, 0)
			P.PawR = R(bend * .6, 0, 0)
			P.ArmL = R(-a, 0, 0)
			P.ForeL = R(-bend2, 0, 0)
			P.PawL = R(bend2 * .6, 0, 0)
			P.ThighL = R(-a * .9, 0, 0)
			P.ShinL = R(bend * .8, 0, 0)
			P.FootL = R(-bend * .5, 0, 0)
			P.ThighR = R(a * .9, 0, 0)
			P.ShinR = R(bend2 * .8, 0, 0)
			P.FootR = R(-bend2 * .5, 0, 0)
			P.Chest = P.Chest * R(0, math.sin(ph) * .05 * moving, math.sin(ph) * .03 * moving)
			P.Neck = P.Neck * R(math.sin(ph * 2) * .04 * moving, 0, 0)
		end
		local attack = anim.Attack
		if mode == "Windup" then
			local k = smooth(ma / math.max(.3, (A("ModeUntil") or 0) - (A("ModeAt") or 0)))
			if attack == "Slam" or attack == "Stomp" then
				local lift = attack == "Stomp" and 1.15 or 1
				P.Pelvis = R(.2 * k * lift, 0, 0)
				P.Chest = R(.12 * k, 0, 0)
				P.ArmR = R(1.0 * k * lift, 0, -.15 * k)
				P.ArmL = R(1.0 * k * lift, 0, .15 * k)
				P.ForeR = R(-.95 * k, 0, 0)
				P.ForeL = R(-.95 * k, 0, 0)
				P.PawR = R(-.3 * k, 0, 0)
				P.PawL = R(-.3 * k, 0, 0)
				P.ThighR = R(-.25 * k, 0, 0)
				P.ThighL = R(-.25 * k, 0, 0)
				P.ShinR = R(.3 * k, 0, 0)
				P.ShinL = R(.3 * k, 0, 0)
				P.Neck = R(.35 * k, 0, 0)
				P.Head = R(.25 * k, 0, 0)
				P.Jaw = R(-.55 * k)
				P.Tail1 = R(.5 * k, 0, 0)
			else -- Sweep: wind the head and the right claw back to the side
				P.Chest = R(0, .2 * k, 0)
				P.Neck = R(.1 * k, .55 * k, 0)
				P.Head = R(0, .3 * k, -.15 * k)
				P.Jaw = R(-.45 * k)
				P.ArmR = R(.7 * k, .3 * k, -.5 * k)
				P.ForeR = R(-.6 * k, 0, 0)
				P.Pelvis = R(.06 * k, -.12 * k, 0)
			end
		end
		-- impact recoil (after an Impact event)
		local since = t - anim.Impact
		if since >= 0 and since < 1.1 then
			local k = 1 - smooth(since / 1.1)
			local kind = anim.ImpactKind
			if kind == "Slam" or kind == "Stomp" then
				P.Pelvis = R(-.1 * k, 0, 0)
				P.Chest = R(-.08 * k, 0, 0)
				P.ArmR = R(-.15 * k, 0, 0)
				P.ArmL = R(-.15 * k, 0, 0)
				P.Neck = R(-.35 * k, 0, 0)
				P.Head = R(-.25 * k, 0, 0)
				P.Jaw = R(-.35 * k)
			elseif kind == "Sweep" then
				P.Chest = R(0, -.25 * k, 0)
				P.Neck = R(.05 * k, -.7 * k, 0)
				P.Head = R(0, -.35 * k, .15 * k)
				P.ArmR = R(.5 * k, -.6 * k, .3 * k)
				P.Jaw = R(-.3 * k)
			end
		end
		if mode == "Roar" or mode == "Enrage" or mode == "Rise" then
			local k = mode == "Rise" and smooth((ma - 3.2) / .8) or smooth(ma / .5)
			local tremble = math.sin(t * 38) * .02 * k
			P.Pelvis = R(.08 * k, 0, 0)
			P.Chest = R(.1 * k + tremble, 0, 0)
			P.Neck = R(.5 * k, tremble, 0)
			P.Head = R(.32 * k, 0, tremble)
			P.Jaw = R(-.75 * k)
			P.Tail1 = R(.5 * k, 0, 0)
			P.Tail2 = R(.3 * k, math.sin(t * 9) * .2 * k, 0)
		elseif mode == "Burrow" or mode == "Escape" then
			local k = smooth(ma / .8)
			local dig = math.sin(t * 16)
			P.Pelvis = R(-.45 * k, 0, 0)
			P.Neck = R(-.6 * k, 0, 0)
			P.Head = R(-.35 * k, 0, 0)
			P.ArmR = R(.6 * k + dig * .5 * k, 0, 0)
			P.ArmL = R(.6 * k - dig * .5 * k, 0, 0)
			P.ForeR = R(-.6 * k, 0, 0)
			P.ForeL = R(-.6 * k, 0, 0)
			P.Jaw = R(-.3 * k)
		elseif mode == "Erupt" then
			local k = 1 - smooth((ma - .4) / 1.6)
			P.Pelvis = R(.3 * k, 0, 0)
			P.Neck = R(.55 * k, 0, 0)
			P.Head = R(.3 * k, 0, 0)
			P.Jaw = R(-.7 * k)
			P.ArmR = R(.9 * k, 0, -.2 * k)
			P.ArmL = R(.9 * k, 0, .2 * k)
			P.ForeR = R(-.7 * k, 0, 0)
			P.ForeL = R(-.7 * k, 0, 0)
		elseif mode == "Stagger" then
			local wob = math.sin(t * 5)
			P.Pelvis = R(-.12, 0, .04 * wob)
			P.Neck = R(-.45, .1 * wob, 0)
			P.Head = R(-.2, 0, .25 + .05 * wob)
			P.Jaw = R(-.35)
			P.ForeR = R(.25, 0, 0)
			P.ForeL = R(.3, 0, 0)
			P.ShinR = R(.2, 0, 0)
			P.ShinL = R(.25, 0, 0)
		elseif mode == "Death" then
			-- staged: killing-blow recoil (h, 0-.8 s: head thrown back, jaw wide) -> stagger (s, .3-2.8 s: trembling, knees
			-- buckling, head lolling) -> collapse (d, 1.7-2.8 s: sprawled on the floor)
			local h = smooth(ma / .2) * (1 - smooth((ma - .35) / .45))
			local s = smooth((ma - .3) / .45) * (1 - smooth((ma - 1.7) / 1.1))
			local d = smooth((ma - 1.7) / 1.1)
			local wob = math.sin(t * 6.5)
			local trem = math.sin(t * 31) * .03 * s
			P.Pelvis = R(.05 * h - .14 * s - .08 * d, 0, .05 * wob * s + .1 * d)
			P.Chest = R(-.16 * h - .06 * s + trem - .1 * d, 0, .04 * wob * s - .08 * d)
			P.Neck = R(-.55 * h - .5 * s - .7 * d, .12 * wob * s + .2 * d, .1 * h)
			P.Head = R(-.35 * h - .25 * s - .35 * d, 0, .12 * h + (.28 + .06 * wob) * s + .3 * d)
			P.Jaw = R(-.85 * h - .45 * s - .8 * d)
			P.ArmR = R(-.3 * h + .15 * s - .2 * d, 0, -.2 * h - .08 * s - .75 * d)
			P.ArmL = R(-.3 * h + .1 * s - .2 * d, 0, .2 * h + .08 * s + .75 * d)
			P.ForeR = R(.35 * s + .2 * d, 0, .3 * d)
			P.ForeL = R(.4 * s + .2 * d, 0, -.3 * d)
			P.ThighR = R(-.12 * s - .4 * d, 0, -.6 * d)
			P.ThighL = R(-.15 * s - .4 * d, 0, .6 * d)
			P.ShinR = R(.35 * s + .9 * d, 0, 0)
			P.ShinL = R(.4 * s + .9 * d, 0, 0)
			for i = 1, 4 do
				P["Tail" .. i] = R((i == 1 and .4 or .2) * h - .1 * s - .15 * d, .2 * d + math.sin(t * 9 - i) * .15 * s, 0)
			end
		end
		return P
	end

	-- vertical offset of the whole rig (rise / burrow / erupt / death / escape)
	local function yOffset(mode: string, ma: number, t: number): number
		if mode == "Rise" then
			return -27 * (1 - backOut((ma - 1.8) / 3.0))
		elseif mode == "Burrow" or mode == "Escape" then
			return -30 * smooth((ma - .5) / 1.9)
		elseif mode == "Underground" then
			return -45
		elseif mode == "Erupt" then
			return -28 * (1 - backOut(ma / .7))
		elseif mode == "Death" then
			-- knees buckle a little during the stagger, the body drops in the collapse, the remains sink at the end
			local d = smooth((ma - 1.7) / 1.1)
			return -1.2 * smooth((ma - .5) / 1.0) * (1 - d) - 5.5 * d - 10 * smooth((ma - 5) / 2.2)
		elseif mode == "Windup" and (anim.Attack == "Slam" or anim.Attack == "Stomp") then
			return 1.2 * smooth(ma / .6)
		end
		return math.sin(t * 1.7) * .12
	end

	-- per-hit flinch: additive, decaying bone kicks on top of the pose (snap in 0.05 s, damped wobble out); applied to the
	-- Motor6D transforms only, never stored in boss.Cur, so nothing accumulates
	local flinches = {}
	local function addFlinch(bone: string, x: number, y: number, z: number, delay: number?)
		table.insert(flinches, { Bone = bone, At = os.clock() + (delay or 0), X = x, Y = y, Z = z })
		if #flinches > 18 then
			table.remove(flinches, 1)
		end
	end
	local function flinchPose(t: number): { [string]: CFrame }
		local out = {}
		for i = #flinches, 1, -1 do
			local f = flinches[i]
			local e = t - f.At
			if e > .5 then
				table.remove(flinches, i)
			elseif e >= 0 then
				local k = e < .05 and math.sin(e / .05 * PI / 2) or math.exp(-(e - .05) * 9) * math.cos((e - .05) * 21)
				out[f.Bone] = (out[f.Bone] or CF()) * ANG(f.X * k, f.Y * k, f.Z * k)
			end
		end
		return out
	end
	local stepWeakFX -- (defined with the weak points below)

	local lastAnim = os.clock()
	local function stepBoss(dt: number)
		if not boss then
			return
		end
		local t = os.clock()
		-- hit-stop: the rig holds still for a perfect / heavy hit and the killing blow; slow motion right after the kill
		if t < (anim.HoldUntil or 0) then
			return
		end
		if t < (anim.SlowUntil or 0) then
			dt *= .25
		end
		local mode = anim.Mode
		local ma = now() - (anim.ModeAt or now())
		-- position (smoothed) and yaw
		local cf = serverCF()
		if cf then
			local target = cf.Position
			local yaw = yawOf(cf)
			if not boss.Pos or (target - boss.Pos).Magnitude > 25 or mode == "Erupt" or mode == "Underground" then
				boss.Pos = target
				boss.Yaw = yaw
			else
				local k = 1 - math.exp(-dt * 6)
				local before = boss.Pos
				boss.Pos = boss.Pos:Lerp(target, k)
				local diff = (yaw - boss.Yaw + PI) % (2 * PI) - PI
				boss.Yaw += diff * (1 - math.exp(-dt * 5))
				local v = (boss.Pos - before).Magnitude / math.max(dt, 1e-3)
				boss.Speed = (boss.Speed or 0) * .85 + v * .15
			end
		end
		if not boss.Pos then
			boss.Pos = Vector3.new(PIT.X, FLOOR, PIT.Z)
		end
		local moving = math.clamp(((boss.Speed or 0) - .4) / 3, 0, 1)
		if mode ~= "Walk" and mode ~= "Idle" then
			moving = 0
		end
		anim.Gait = (anim.Gait or 0) + dt * (2.4 + 2 * moving) * moving * 1.6
		-- footsteps
		if moving > .3 then
			local stepIndex = math.floor(anim.Gait / PI)
			if stepIndex ~= boss.LastStep then
				boss.LastStep = stepIndex
				local paws = boss.Paws or {}
				local paw = (stepIndex % 2 == 0) and (paws.PawFR or paws.PawHL) or (paws.PawFL or paws.PawHR)
				if paw then
					local p = attPos(paw)
					play("BossStep", p)
					FX.Ring(floorAt(p), RGB(110, 96, 86), 4, .5, { Thickness = .1, Transparency = .4, Material = Enum.Material.SmoothPlastic })
					if not low() then
						FX.Smoke(p + V3(0, .5, 0), RGB(96, 84, 78), 2.2, 1)
					end
					shakeAt(p, .12, .25, 30)
				end
			end
		end
		local y = yOffset(mode, ma, t)
		anim.Yoff = y
		local rootCF = CF(boss.Pos + V3(0, y, 0)) * ANG(0, boss.Yaw, 0) * CF(0, 1, 0)
		boss.Root.CFrame = rootCF
		-- bones
		local target = pose(mode, t, ma, moving)
		local k = 1 - math.exp(-dt * ((mode == "Windup" or mode == "Death") and 7 or 9))
		if t - anim.Impact < .15 then
			k = 1 - math.exp(-dt * 22)
		end
		local fl = flinchPose(t)
		for _, name in ipairs(BONES) do
			local m = boss.Rig.Motors[name]
			if m then
				local goal = target[name] or CF()
				local cur = boss.Cur[name] or CF()
				cur = cur:Lerp(goal, k)
				boss.Cur[name] = cur
				local kick = fl[name]
				m.Transform = kick and cur * kick or cur
			end
		end
		-- shield dome follows
		if boss.ShieldDome then
			local pulse = .5 + .5 * math.sin(t * 3)
			boss.ShieldDome.CFrame = CF(boss.Pos + V3(0, 11, 0))
			boss.ShieldDome.Transparency = .55 + pulse * .2
			if boss.ShieldRing then
				boss.ShieldRing.CFrame = CF(floorAt(boss.Pos) + V3(0, .1, 0)) * ANG(0, t * .6, PI / 2)
			end
		end
		-- weak points pulse (+ highlight, light, reticle, tag)
		stepWeakFX(t)
		local _ = lastAnim
	end

	---------------------------------------------------------------------------------------------------------------
	-- plates, weak points, shield, eyes (from attributes)
	---------------------------------------------------------------------------------------------------------------
	local function platePos(slot: string): Vector3
		if boss and boss.PlateAtt and boss.PlateAtt[slot] then
			return attPos(boss.PlateAtt[slot])
		end
		local def = Models.Slots.Plates[slot]
		local cf = serverCF() or CF(PIT)
		return (cf * CF(def and def.Pos or V3(0, 12, 0))).Position
	end
	local function weakPos(slot: string): Vector3
		if boss and boss.WeakAtt and boss.WeakAtt[slot] then
			return attPos(boss.WeakAtt[slot])
		end
		local def = Models.Slots.Weak[slot]
		local cf = serverCF() or CF(PIT)
		return (cf * CF(def and def.Pos or V3(0, 12, 0))).Position
	end
	local function corePos(): Vector3
		if boss and boss.CoreAtt then
			return attPos(boss.CoreAtt)
		end
		return (serverCF() or CF(PIT)).Position + V3(0, 12, 0)
	end

	local function showPlate(slot: string, on: boolean, fx: boolean)
		local pl = boss and boss.Plates[slot]
		if not pl or pl.Shown == on then
			return
		end
		pl.Shown = on
		for p, base in pairs(pl.Parts) do
			if on then
				p.Transparency = 1
				FX.Tween(p, .7, { Transparency = base })
			else
				p.Transparency = 1
			end
		end
		if fx then
			local pos = platePos(slot)
			if on then
				FX.Burst(pos, { Color = PURPLE, Color2 = GREEN, Count = 24, Speed = { 2, 6 }, Lifetime = { .6, 1.1 }, Size = { .5, .9, 0 } })
				FX.Light(pos, PURPLE, 14, 2, .8)
				play("LanternFlare", pos)
			else
				FX.Debris(pos, STONE, Enum.Material.Slate, 16, 34, { MaxSize = 1.6, Floor = FLOOR + .3 })
				FX.Debris(pos, RGB(54, 54, 68), Enum.Material.Slate, 8, 26, { MaxSize = 1.1, Floor = FLOOR + .3 })
				FX.Burst(pos, { Color = PURPLE, Color2 = GREEN, Count = 30, Speed = { 8, 18 }, Lifetime = { .4, .9 }, Size = { .6, 1.1, 0 } })
				FX.Smoke(pos, RGB(90, 80, 110), 4, 1.4)
				FX.Light(pos, GREEN, 18, 3, .7)
				play("ArmorBreak", pos)
				shakeAt(pos, .45, .4, 70)
			end
		end
	end

	-- crack stages: wear (0..9) at which stage 1 / 2 / 3 of the plate's CrackStage parts shows
	local CRACK_AT = { 3, 6, 8 }
	local function crackStage(wear: number): number
		local s = 0
		for i, at in ipairs(CRACK_AT) do
			if wear >= at then
				s = i
			end
		end
		return s
	end
	local function setWear(slot: string, wear: number, fx: boolean?)
		local pl = boss and boss.Plates[slot]
		if not pl or pl.Wear == wear then
			return
		end
		local before = crackStage(pl.Wear or 0)
		pl.Wear = wear
		local stage = pl.Shown and crackStage(wear) or 0
		for p in pairs(pl.Parts) do
			if p.Name == "GlowCrack" then
				p.Color = GREEN:Lerp(GREEN_HOT, math.clamp(wear / 9, 0, 1))
			elseif p.Name == "PlateFace" then
				p.Color = STONE:Lerp(RGB(44, 40, 48), math.clamp(wear / 12, 0, 1))
			elseif p.Name == "CrackStage" then
				p.Transparency = stage >= (tonumber(p:GetAttribute("Stage")) or 9) and 0 or 1
			end
		end
		-- the plate cracks a stage further: chips, a green spit of light, a crack sound (lower per stage)
		if fx and stage > before then
			local pos = platePos(slot)
			FX.Debris(pos, STONE, Enum.Material.Slate, 3 + stage * 2, 16, { MaxSize = .7, Floor = FLOOR + .3 })
			FX.Burst(pos, { Color = GREEN_HOT, Color2 = GREEN, Count = 6 + stage * 4, Speed = { 4, 9 }, Lifetime = { .25, .6 }, Size = { .3, .6, 0 } })
			FX.Light(pos, GREEN, 10 + stage * 3, 1.5 + stage * .5, .45)
			play("PlateCrack", pos, { Pitch = 1.15 - stage * .12, Volume = .6 + stage * .15 })
			Bus.Fire("BossPlateCrack", { Slot = slot, Stage = stage, Wear = wear })
		end
	end

	local function syncPlates()
		local st = A("State")
		-- a local end sequence owns the rig (death / escape): the server's final mask ("111111" once clearPlates ran) must
		-- not grow the shattered plates back or wipe the cracks mid-sequence. A new fight builds a fresh rig anyway.
		if not boss or anim.Mode == "Death" or anim.Mode == "Escape" or st == "Defeated" or st == "Escaped" then
			return
		end
		local mask = tostring(A("Plates") or "")
		local wear = tostring(A("PlateWear") or "")
		local fighting = st == "Fight" or st == "Rising"
		-- the attribute is the source of truth (it may arrive before or after the PlateBreak / PlateRegrow events):
		-- changes during a fight play the shatter / regrow FX, the very first sync (joining mid-fight) does not
		local fx = fighting and boss.PlatesSynced == true
		local t = os.clock()
		for i, slot in ipairs(Models.Slots.PlateOrder) do
			local on = (not fighting) or string.sub(mask, i, i) ~= "0"
			if mask == "" then
				on = true
			end
			local w = tonumber(string.sub(wear, i, i)) or 0
			local pl = boss.Plates[slot]
			-- a plate growing back / a crack count dropping by attribute alone waits one sync tick (the PlateRegrow event
			-- shows real regrowth at once): the end-of-fight mask + wear can land a moment before State leaves "Fight"
			if pl and fx and on and (not pl.Shown or w < (pl.Wear or 0)) then
				pl.SettleAt = pl.SettleAt or t
				if t - pl.SettleAt < .15 then
					continue
				end
			elseif pl then
				pl.SettleAt = nil
			end
			showPlate(slot, on, fx)
			setWear(slot, w, fx)
		end
		boss.PlatesSynced = true
	end

	---------------------------------------------------------------------------------------------------------------
	-- weak-point readability: while open, a weak point is the brightest, most distinct thing on the boss (gold core,
	-- pumpkin glow, white rim from Models.Boss) + an always-on-top gold Highlight with a white outline (seen through the
	-- ribs, flames and fog), a gold light, a camera-facing spinning reticle (gold arcs + white ticks, pulled toward the
	-- camera so the ribs don't bury it) and an always-on-top "x3" tag with the seconds left. The last 2 s: faster pulse,
	-- pumpkin red. The soul fire in the ribcage dims while the heart is open.
	---------------------------------------------------------------------------------------------------------------
	local WEAK_MULT = (B.WeakPoints and B.WeakPoints.Mult) or 3
	local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)

	local function closeWeakFX(w, fade: boolean?)
		local fx = w.FX
		w.FX = nil
		if not fx then
			return
		end
		if fx.HL then
			if fade then
				FX.Tween(fx.HL, .3, { FillTransparency = 1, OutlineTransparency = 1 })
				Debris:AddItem(fx.HL, .35)
			else
				fx.HL:Destroy()
			end
		end
		if fx.Light then
			fx.Light:Destroy()
		end
		if fx.Tag then
			fx.Tag:Destroy()
		end
		if fx.Model then
			if fade then
				for _, rp in ipairs(fx.Parts) do
					FX.Tween(rp.Part, .25, { Transparency = 1 })
				end
				Debris:AddItem(fx.Model, .3)
			else
				fx.Model:Destroy()
			end
		end
	end

	local function openWeakFX(slot: string, w)
		closeWeakFX(w, false)
		if not boss then
			return
		end
		local fx = { Parts = {}, Born = os.clock(), HitAt = -10, Left = -1 }
		w.FX = fx
		local hl = Instance.new("Highlight")
		hl.Name = "WeakHighlight"
		hl.Adornee = w.Group
		hl.FillColor = GOLD
		hl.OutlineColor = WHITE
		hl.FillTransparency = .62
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = w.Group
		fx.HL = hl
		if not low() and w.Core then
			local l = Instance.new("PointLight")
			l.Name = "WeakLight"
			l.Color = GOLD
			l.Range = 10
			l.Brightness = 1.5
			l.Shadows = false
			l.Parent = w.Core
			fx.Light = l
		end
		local def = Models.Slots.Weak[slot]
		local r = (def and def.Radius or 2.2) * 1.3
		if not low() then
			-- 3D reticle: 4 gold arcs (2 pieces each) + 4 white ticks crossing the ring
			local m = Instance.new("Model")
			m.Name = "WeakReticle_" .. slot
			m.Parent = FX.Folder()
			fx.Model = m
			for i = 0, 3 do
				for j = 0, 1 do
					local p = FX.Part({ Size = V3(r * .42, .28, .2), Color = GOLD, Transparency = .05, Parent = m })
					p.Name = "ReticleArc"
					table.insert(fx.Parts, { Part = p, A = i * PI / 2 + PI / 4 + (j - .5) * .42, R = r, Kind = "Arc" })
				end
				local tick = FX.Part({ Size = V3(.26, r * .45, .14), Color = WHITE, Transparency = 0, Parent = m })
				tick.Name = "ReticleTick"
				table.insert(fx.Parts, { Part = tick, A = i * PI / 2, R = r, Kind = "Tick" })
			end
		end
		-- always-on-top tag: x3 + seconds left (a ring too on Low, where the 3D reticle is skipped)
		local att = boss.WeakAtt and boss.WeakAtt[slot]
		if att then
			local g = Instance.new("BillboardGui")
			g.Name = "WeakTag"
			g.AlwaysOnTop = true
			g.LightInfluence = 0
			g.MaxDistance = 150
			g.Size = UDim2.new(r * 1.1, 34, r * 1.1, 34)
			g:SetAttribute("NoTranslate", true)
			if low() then
				local ring = Instance.new("Frame")
				ring.Name = "Ring"
				ring.AnchorPoint = Vector2.new(.5, .5)
				ring.Position = UDim2.fromScale(.5, .5)
				ring.Size = UDim2.fromScale(.92, .92)
				ring.BackgroundTransparency = 1
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(.5, 0)
				corner.Parent = ring
				local st = Instance.new("UIStroke")
				st.Color = GOLD
				st.Thickness = 3
				st.Parent = ring
				ring.Parent = g
				fx.Ring = st
			end
			local function label(name: string, text: string, size: UDim2, pos: UDim2, color: Color3): TextLabel
				local t = Instance.new("TextLabel")
				t.Name = name
				t.AnchorPoint = Vector2.new(.5, .5)
				t.BackgroundTransparency = 1
				t.Size = size
				t.Position = pos
				t.FontFace = FONT
				t.TextScaled = true
				t.Text = text
				t.TextColor3 = color
				t:SetAttribute("NoTranslate", true)
				local st = Instance.new("UIStroke")
				st.Thickness = 2
				st.Color = RGB(40, 16, 8)
				st.Parent = t
				t.Parent = g
				return t
			end
			label("Mult", "x" .. tostring(WEAK_MULT), UDim2.fromScale(.5, .34), UDim2.fromScale(.5, .5), GOLD_HOT)
			fx.Count = label("Left", "", UDim2.fromScale(.32, .24), UDim2.fromScale(.5, .9), WHITE)
			g.Adornee = att
			g.Parent = att
			fx.Tag = g
		end
	end

	local function setSoulDim(k: number)
		if not boss or not boss.Soul or boss.SoulDim == k then
			return
		end
		boss.SoulDim = k
		for p, base in pairs(boss.Soul) do
			FX.Tween(p, .35, { Transparency = base + (1 - base) * k * (p.Name == "SoulCore" and .78 or .9) })
		end
	end

	stepWeakFX = function(t: number)
		if not boss then
			return
		end
		local left = (A("WeakOpenUntil") or 0) - now()
		local urgent = left < 2
		local cam = workspace.CurrentCamera
		local camP = cam and cam.CFrame.Position or camPos()
		local rm = reduced()
		for slot, w in pairs(boss.Weak) do
			if w.Shown then
				local pulse = .5 + .5 * math.sin(t * (urgent and 17 or 9))
				for p in pairs(w.Parts) do
					if p.Name == "WeakGlow" then
						p.Transparency = .3 + pulse * .3
					elseif p.Name == "WeakRing" then
						p.Transparency = .68 + pulse * .22
					end
				end
				local fx = w.FX
				if fx then
					local hitK = math.clamp(1 - (t - fx.HitAt) / .2, 0, 1)
					local col = urgent and PUMPKIN or GOLD
					if fx.HL then
						fx.HL.FillColor = col:Lerp(WHITE, hitK)
						fx.HL.FillTransparency = (.7 - pulse * .2) * (1 - hitK) + .08 * hitK
						fx.HL.OutlineColor = urgent and GOLD_HOT or WHITE
					end
					if fx.Light then
						fx.Light.Brightness = 1.1 + pulse * .9 + hitK * 2.5
					end
					if fx.Ring then
						fx.Ring.Color = col
						fx.Ring.Transparency = .1 + pulse * .3
					end
					local secs = math.max(0, math.ceil(left))
					if fx.Count and secs ~= fx.Left then
						fx.Left = secs
						fx.Count.Text = tostring(secs)
						fx.Count.TextColor3 = urgent and PUMPKIN or WHITE
					end
					if fx.Model then
						-- face the camera, pulled a few studs toward it (in front of the ribs), shrink in, spin, breathe
						local c = weakPos(slot)
						local to = camP - c
						local dist = to.Magnitude
						local at = dist > .1 and c + to.Unit * math.min(3, dist * .3) or c
						local face = Models.Look(at, camP)
						local age = t - fx.Born
						local intro = 1 + 1.3 * (1 - smooth(age / .35))
						local spin = rm and 0 or age * (urgent and 2.6 or 1.1)
						local breathe = rm and 1 or 1 + .07 * math.sin(t * (urgent and 14 or 6))
						local scale = intro * breathe * (1 + .18 * hitK)
						for _, rp in ipairs(fx.Parts) do
							local a = rp.A + spin
							local rr = rp.R * scale
							local pcf = face * CF(math.cos(a) * rr, math.sin(a) * rr, 0)
							if rp.Kind == "Arc" then
								rp.Part.CFrame = pcf * ANG(0, 0, a + PI / 2)
								rp.Part.Color = col:Lerp(WHITE, hitK)
								rp.Part.Transparency = .05 + pulse * .25
							else
								rp.Part.CFrame = pcf * ANG(0, 0, a - PI / 2)
								rp.Part.Color = urgent and GOLD_HOT or WHITE
							end
						end
					end
				end
			end
		end
	end

	local function syncWeak()
		if not boss then
			return
		end
		local open = (A("WeakOpenUntil") or 0) > now() and anim.Mode ~= "Death" and anim.Mode ~= "Escape"
		local list = {}
		for s in string.gmatch(tostring(A("WeakSlots") or ""), "[^,]+") do
			list[s] = true
		end
		local opened = nil
		for slot, w in pairs(boss.Weak) do
			local on = open and list[slot] == true
			if on ~= w.Shown then
				w.Shown = on
				for p in pairs(w.Parts) do
					local goal = 1
					if on then
						goal = (p.Name == "WeakGlow") and .45 or (p.Name == "WeakRing" and .8 or 0)
					end
					FX.Tween(p, .35, { Transparency = goal })
				end
				if on then
					local pos = weakPos(slot)
					FX.Cracks(pos, V3(0, -1, 0), GOLD, 5, 1.6)
					FX.Burst(pos, { Color = GOLD_HOT, Color2 = PUMPKIN, Count = 26, Speed = { 4, 10 }, Lifetime = { .5, 1 } })
					FX.Light(pos, GOLD, 22, 4, .8)
					openWeakFX(slot, w)
					opened = opened or pos
				else
					closeWeakFX(w, true)
				end
			end
		end
		if opened then
			play("WeakOpen", opened)
		end
		local heart = boss.Weak.Heart
		setSoulDim((heart and heart.Shown) and 1 or 0)
	end

	local function syncShield()
		if not boss then
			return
		end
		local up = A("Shield") == true
		if up and not boss.ShieldDome then
			local dome = FX.Part({ Class = "Part", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CF(boss.Pos or PIT), Color = PURPLE,
				Material = Enum.Material.ForceField, Transparency = .6 })
			FX.Tween(dome, .8, { Size = Vector3.one * 36 }, Enum.EasingStyle.Back)
			local ring = FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Size = V3(.2, 30, 30), Color = PURPLE_DEEP, Transparency = .5,
				CFrame = CF(floorAt(boss.Pos or PIT)) * ANG(0, 0, PI / 2) })
			boss.ShieldDome, boss.ShieldRing = dome, ring
			ring.Parent = dome
			play("BossEnrage", boss.Pos, { Volume = .6, Pitch = 1.3 })
			FX.Light((boss.Pos or PIT) + V3(0, 10, 0), PURPLE, 40, 3, 1)
		elseif not up and boss.ShieldDome then
			local dome = boss.ShieldDome
			boss.ShieldDome, boss.ShieldRing = nil, nil
			FX.Tween(dome, .35, { Size = Vector3.one * 44, Transparency = 1 })
			Debris:AddItem(dome, .4)
			FX.Shockwave(floorAt(boss.Pos or PIT), PURPLE, 26, .8)
			FX.Flash(PURPLE, .25, .35)
			play("ArmorBreak", boss.Pos, { Pitch = .7 })
			shakeAt(boss.Pos or PIT, .6, .5, 90)
			for _, b in pairs(boss.Tethers) do
				b:Destroy()
			end
			boss.Tethers = {}
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- ground telegraphs
	---------------------------------------------------------------------------------------------------------------
	local telegraphs = {}

	local function disc(parent: Instance, pos: Vector3, radius: number, color: Color3, tr: number, h: number)
		return FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Size = V3(h or .08, radius * 2, radius * 2), Color = color, Transparency = tr,
			CFrame = CF(pos) * ANG(0, 0, PI / 2), Parent = parent })
	end

	local function ringOutline(parent: Instance, pos: Vector3, radius: number, color: Color3, n: number, from: number?, to: number?)
		local parts = {}
		local a0, a1 = from or 0, to or PI * 2
		for i = 0, n - 1 do
			local a = a0 + (a1 - a0) * (i + .5) / n
			local seg = (a1 - a0) / n * radius * 1.05
			local p = pos + V3(math.cos(a) * radius, 0, math.sin(a) * radius)
			local part = FX.Part({ Size = V3(.5, .14, seg), Color = color, Transparency = .1,
				CFrame = CF(p) * ANG(0, -a, 0), Parent = parent })
			table.insert(parts, part)
		end
		return parts
	end

	-- circle (Slam / Stomp / rocks) or cone (Sweep): rim + filling disc growing to the full size at impact time
	-- (groundY: drawn on that surface instead of the arena floor, e.g. a rock on the terrace ring)
	local function telegraph(kind: string, pos: Vector3, radius: number, impactAt: number, dir: Vector3?, angle: number?, color: Color3?,
		groundY: number?)
		local model = Instance.new("Model")
		model.Name = "BossTelegraph"
		model.Parent = FX.Folder()
		local col = color or BLOOD
		local base = groundY and Vector3.new(pos.X, groundY + .06, pos.Z) or floorAt(pos)
		local tg = { Model = model, Kind = kind, Pos = base, Radius = radius, ImpactAt = impactAt, Start = now(), Fill = {}, Color = col }
		if kind == "Cone" then
			local d = (dir and Vector3.new(dir.X, 0, dir.Z).Magnitude > .01) and Vector3.new(dir.X, 0, dir.Z).Unit or V3(0, 0, -1)
			local half = math.rad((angle or 120) / 2)
			local center = math.atan2(d.Z, d.X)
			tg.Center, tg.Half = center, half
			ringOutline(model, base, radius, col, 18, center - half, center + half)
			for _, s in ipairs({ -1, 1 }) do
				local a = center + half * s
				local tip = base + V3(math.cos(a) * radius, 0, math.sin(a) * radius)
				FX.Part({ Size = V3(.45, .14, radius), Color = col, Transparency = .1, CFrame = Models.Look((base + tip) / 2, tip), Parent = model })
			end
			for i = 1, 14 do
				local a = center - half + (2 * half) * (i - .5) / 14
				local tip = base + V3(math.cos(a) * radius, 0, math.sin(a) * radius)
				local w = 2 * half / 14 * radius * 1.1
				local p = FX.Part({ Class = "WedgePart", Size = V3(w, .06, radius), Color = col, Transparency = .62,
					CFrame = Models.Look((base + tip) / 2 + V3(0, .02, 0), tip + V3(0, .02, 0)), Parent = model })
				p:SetAttribute("Len", radius)
				p:SetAttribute("A", a)
				table.insert(tg.Fill, p)
			end
		else
			ringOutline(model, base, radius, col, math.clamp(math.floor(radius * 2.2), 14, 40))
			tg.Disc = disc(model, base, radius, col, .78, .05)
			tg.Grow = disc(model, base + V3(0, .03, 0), .2, col:Lerp(Color3.new(1, 1, 1), .15), .45, .06)
			-- skull rune in the middle
			FX.Part({ Size = V3(radius * .5, .1, .3), Color = col, Transparency = .3, CFrame = CF(base + V3(0, .05, 0)) * ANG(0, PI / 4, 0), Parent = model })
			FX.Part({ Size = V3(radius * .5, .1, .3), Color = col, Transparency = .3, CFrame = CF(base + V3(0, .05, 0)) * ANG(0, -PI / 4, 0), Parent = model })
		end
		table.insert(telegraphs, tg)
		return tg
	end

	local function stepTelegraphs()
		local t = now()
		for i = #telegraphs, 1, -1 do
			local tg = telegraphs[i]
			local total = math.max(.2, tg.ImpactAt - tg.Start)
			local k = math.clamp((t - tg.Start) / total, 0, 1)
			if tg.Grow then
				local r = math.max(.2, tg.Radius * k)
				tg.Grow.Size = V3(.06, r * 2, r * 2)
			end
			for _, p in ipairs(tg.Fill) do
				local len = (p:GetAttribute("Len") or tg.Radius) * math.max(.05, k)
				local a = p:GetAttribute("A") or 0
				local tip = tg.Pos + V3(math.cos(a) * len, .02, math.sin(a) * len)
				p.Size = V3(p.Size.X * 0 + (2 * tg.Half / 14 * len * 1.1), .06, len)
				p.CFrame = Models.Look((tg.Pos + tip) / 2 + V3(0, .02, 0), tip)
			end
			-- pulse the rim faster as the impact nears
			local pulse = .5 + .5 * math.sin(t * (8 + 18 * k))
			for _, p in ipairs(tg.Model:GetChildren()) do
				if p:IsA("BasePart") and p ~= tg.Disc and p ~= tg.Grow and not table.find(tg.Fill, p) then
					p.Transparency = .05 + pulse * .25
				end
			end
			if t >= tg.ImpactAt + .15 or tg.Done then
				tg.Model:Destroy()
				table.remove(telegraphs, i)
			end
		end
	end

	local function clearTelegraphs()
		for _, tg in ipairs(telegraphs) do
			tg.Model:Destroy()
		end
		table.clear(telegraphs)
	end

	-- the big impact recipe: shockwave, glowing cracks, debris, bone chips, cursed smoke, light, sound, shake
	local function impact(pos: Vector3, radius: number, color: Color3?, heavy: boolean?, groundY: number?)
		local base = groundY and Vector3.new(pos.X, groundY + .06, pos.Z) or floorAt(pos)
		local col = color or GREEN
		FX.Shockwave(base + V3(0, .2, 0), col, radius, .7)
		FX.Cracks(base + V3(0, .02, 0), V3(0, 1, 0), col, radius * .9, 2.2)
		if heavy and not low() then
			FX.Cracks(base + V3(radius * .3, .02, radius * .2), V3(0, 1, 0), PURPLE, radius * .6, 2)
		end
		FX.Debris(base + V3(0, .6, 0), RGB(64, 60, 72), Enum.Material.Slate, heavy and 20 or 12, heavy and 40 or 30, { MaxSize = 1.4, Floor = base.Y + .25 })
		FX.Debris(base + V3(0, .6, 0), BONE, Enum.Material.SmoothPlastic, heavy and 8 or 5, 26, { MaxSize = .7, Floor = base.Y + .25 })
		FX.Burst(base + V3(0, 1, 0), { Texture = FX.Textures.Smoke, Color = CURSE, Color2 = RGB(40, 20, 60), Count = heavy and 16 or 10,
			Speed = { radius * .5, radius * 1.1 }, Lifetime = { .8, 1.6 }, Size = { 2, 4, 6 }, Transparency = { .35, 1 }, LightEmission = .2, Drag = 3,
			Spread = 80, Direction = V3(0, 1, 0), Shape = "Disc" })
		FX.Burst(base + V3(0, .5, 0), { Color = BONE, Color2 = col, Count = 18, Speed = { 10, 22 }, Lifetime = { .4, .9 }, Size = { .4, .7, 0 } })
		FX.Light(base + V3(0, 3, 0), col, radius * 2, 3, .8)
		play(heavy and "BossSlam" or "RockImpact", base)
		shakeAt(base, heavy and .8 or .5, heavy and .6 or .4, heavy and 110 or 70)
	end

	---------------------------------------------------------------------------------------------------------------
	-- strike-target visuals: skeletons, mounds, rocks
	---------------------------------------------------------------------------------------------------------------
	local visuals = {} -- [TargetId] = {Kind, Model, Rig?, Part, ...}
	local rockFalls = {} -- [Key] = {Model, Telegraph, From, To, Start, LandAt, Landed}
	local rockByTarget = {}

	local function targetsFolder(): Instance?
		local live = workspace:FindFirstChild("HalloweenLive")
		return live and live:FindFirstChild("Targets")
	end

	local function newSkeleton(id: any, part: BasePart)
		local m = Models.Skeleton(tonumber(part:GetAttribute("Seed")) or tonumber(id) or 1)
		local rig = Models.Rig(m)
		m.Parent = FX.Folder()
		local cf = part.CFrame
		local pos = Vector3.new(cf.Position.X, FLOOR, cf.Position.Z)
		local v = { Kind = "BossSkeleton", Model = m, Rig = rig, Part = part, Pos = pos, Yaw = yawOf(cf), Spawn = os.clock(), Cur = {}, Gait = 0 }
		-- claws out of the ground
		FX.Burst(pos + V3(0, .5, 0), { Texture = FX.Textures.Smoke, Color = DIRT, Color2 = RGB(40, 30, 26), Count = 8, Speed = { 2, 5 }, Lifetime = { .6, 1.1 },
			Size = { 1.5, 2.5, 3 }, Transparency = { .3, 1 }, LightEmission = 0 })
		FX.Debris(pos + V3(0, .4, 0), DIRT, Enum.Material.Ground, 6, 16, { MaxSize = .8, Floor = FLOOR + .2 })
		play("SkeletonRattle", pos)
		return v
	end

	local function stepSkeleton(v, dt: number, t: number)
		if not v.Part or not v.Part.Parent then
			return
		end
		local cf = v.Part.CFrame
		local goal = Vector3.new(cf.Position.X, FLOOR, cf.Position.Z)
		local before = v.Pos
		v.Pos = v.Pos:Lerp(goal, 1 - math.exp(-dt * 10))
		local want = yawOf(cf)
		local diff = (want - v.Yaw + PI) % (2 * PI) - PI
		v.Yaw += diff * (1 - math.exp(-dt * 8))
		local speed = (v.Pos - before).Magnitude / math.max(dt, 1e-3)
		v.Speed = (v.Speed or 0) * .8 + speed * .2
		local moving = math.clamp(v.Speed / 6, 0, 1)
		v.Gait += dt * 12 * moving
		local rise = math.clamp((os.clock() - v.Spawn) / .7, 0, 1)
		local y = -3.5 * (1 - backOut(rise))
		local lunge = 0
		if v.LungeAt and t - v.LungeAt < .45 then
			lunge = math.sin((t - v.LungeAt) / .45 * PI)
		end
		v.Rig.Root.CFrame = CF(v.Pos + V3(0, y + math.abs(math.sin(v.Gait)) * .15 * moving, 0)) * ANG(0, v.Yaw, 0) * CF(0, .5, -lunge * .8)
		local a = math.sin(v.Gait) * .6 * moving
		local P = {
			LegFR = R(a, 0, 0), LegHL = R(a, 0, 0), LegFL = R(-a, 0, 0), LegHR = R(-a, 0, 0),
			Head = R(math.sin(t * 6 + (v.Spawn % 3)) * .08 + lunge * .35, math.sin(t * 2.3) * .15, 0),
			Jaw = R(-.15 - math.max(0, math.sin(t * 7)) * .25 - lunge * .5),
			Tail = R(.2, math.sin(t * 9) * .4, 0),
			Body = R(lunge * -.15, 0, math.sin(v.Gait) * .04 * moving),
		}
		for name, m in pairs(v.Rig.Motors) do
			local cur = v.Cur[name] or CF()
			cur = cur:Lerp(P[name] or CF(), 1 - math.exp(-dt * 14))
			v.Cur[name] = cur
			m.Transform = cur
		end
	end

	local function shatterModel(m: Model, color: Color3, count: number)
		local parts = {}
		eachPart(m, function(p)
			if p.Transparency < .9 and p.Size.Magnitude > .3 then
				table.insert(parts, p)
			end
		end)
		local n = math.min(#parts, low() and 6 or count)
		for _ = 1, n do
			local p = parts[math.random(1, math.max(1, #parts))]
			if p then
				FX.Debris(p.CFrame.Position, p.Color, p.Material, 1, 22, { MaxSize = math.min(1.2, p.Size.Magnitude * .5), Floor = FLOOR + .2 })
			end
		end
		local _ = color
	end

	local function removeVisual(id: any, how: string?)
		local v = visuals[id]
		if not v then
			return
		end
		visuals[id] = nil
		local pos = v.Pos or (v.Model and v.Model:GetPivot().Position) or PIT
		if v.Kind == "BossSkeleton" then
			if how ~= "Silent" then
				shatterModel(v.Model, BONE, 14)
				FX.Debris(pos + V3(0, 2, 0), BONE, Enum.Material.SmoothPlastic, 12, 24, { MaxSize = .8, Floor = FLOOR + .2 })
				FX.Burst(pos + V3(0, 2, 0), { Texture = FX.Textures.Smoke, Color = how == "Collapse" and CURSE or GREEN, Color2 = RGB(30, 20, 40), Count = 10,
					Speed = { 2, 6 }, Lifetime = { .7, 1.3 }, Size = { 1.5, 3, 4 }, Transparency = { .35, 1 }, LightEmission = .3 })
				FX.Burst(pos + V3(0, 2, 0), { Color = GREEN, Color2 = BONE, Count = 16, Speed = { 6, 14 }, Lifetime = { .3, .7 } })
				play("SkeletonBreak", pos)
			end
			v.Model:Destroy()
		elseif v.Kind == "BossMound" then
			if how ~= "Silent" then
				FX.Debris(pos + V3(0, 1, 0), DIRT, Enum.Material.Ground, 14, 26, { MaxSize = 1.3, Floor = FLOOR + .2 })
				FX.Smoke(pos + V3(0, 1, 0), RGB(90, 76, 66), 4, 1.4)
				play("DigSoil", pos)
			end
			local m = v.Model
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then
					FX.Tween(p, .8, { CFrame = p.CFrame - V3(0, 3, 0), Transparency = 1 })
				end
			end
			Debris:AddItem(m, .9)
		elseif v.Kind == "CursedRock" then
			if how ~= "Silent" then
				FX.Debris(pos + V3(0, 2, 0), RGB(54, 46, 62), Enum.Material.Basalt, 16, 34, { MaxSize = 1.5, Floor = pos.Y + .2 })
				FX.Burst(pos + V3(0, 2, 0), { Color = PURPLE, Color2 = GREEN, Count = 24, Speed = { 8, 18 }, Lifetime = { .4, .8 } })
				play("OreBreak", pos)
			end
			v.Model:Destroy()
		end
		if v.Light then
			v.Light:Destroy()
		end
	end

	local function newMound(id: any, part: BasePart)
		local index = part:GetAttribute("Index") or part:GetAttribute("Seed") or tonumber(id) or 1
		local m = Models.Mound(tonumber(index) or 1)
		local pp = part.CFrame.Position
		local pos = Vector3.new(pp.X, FLOOR, pp.Z)
		m:PivotTo(CF(pos - V3(0, 2.6, 0)) * ANG(0, (tonumber(id) or 1) * 1.7, 0))
		m.Parent = FX.Folder()
		local v = { Kind = "BossMound", Model = m, Part = part, Pos = pos, Spawn = os.clock(), Base = CF(pos) * ANG(0, (tonumber(id) or 1) * 1.7, 0) }
		FX.Debris(pos + V3(0, .5, 0), DIRT, Enum.Material.Ground, 8, 18, { MaxSize = 1, Floor = FLOOR + .2 })
		FX.Smoke(pos + V3(0, .8, 0), RGB(90, 76, 66), 3.5, 1.2)
		play("DigSoil", pos, { Pitch = .7 })
		return v
	end

	local function stepMound(v, t: number)
		local rise = math.clamp((os.clock() - v.Spawn) / .8, 0, 1)
		local quake = 0
		if v.QuakeAt and t - v.QuakeAt < .6 then
			quake = (1 - (t - v.QuakeAt) / .6) * (v.QuakeReal and .35 or .15)
		end
		local jitter = V3(math.sin(t * 41 + v.Pos.X) * quake, 0, math.cos(t * 37 + v.Pos.Z) * quake)
		v.Model:PivotTo(v.Base * CF(jitter + V3(0, -2.6 * (1 - smooth(rise)) + math.sin(t * 2 + v.Pos.X) * .04, 0)))
	end

	local function newRockVisual(id: any, part: BasePart, key: any)
		local fall = key and rockFalls[key]
		if not fall then
			-- the target replicated before the RockLand event: adopt the fall that landed here
			local best, bestD = nil, 3.5
			for k, f in pairs(rockFalls) do
				local d = (Vector3.new(f.To.X, 0, f.To.Z) - Vector3.new(part.CFrame.Position.X, 0, part.CFrame.Position.Z)).Magnitude
				if f.Model and d < bestD then
					best, bestD, key = f, d, k
				end
			end
			fall = best
		end
		local m
		if fall and fall.Model then
			m = fall.Model
			fall.Model = nil
		else
			m = Models.Rock(tonumber(id) or 1)
			m.Parent = FX.Folder()
		end
		-- on the surface the server landed it on (target attribute Ground; terrace rocks sit at -4, floor rocks at -8)
		local pp = part.CFrame.Position
		local g = part:GetAttribute("Ground")
		local pos = typeof(g) == "Vector3" and g or groundAt(pp)
		m:PivotTo(CF(pos) * ANG(0, (tonumber(id) or 1) * 2.1, 0))
		local v = { Kind = "CursedRock", Model = m, Part = part, Pos = pos, Spawn = os.clock(), Key = key, ExplodeAt = fall and fall.ExplodeAt }
		local holder = m:FindFirstChild("Core") or m.PrimaryPart
		if holder and not low() then
			local l = Instance.new("PointLight")
			l.Color = PURPLE
			l.Range = 12
			l.Brightness = 1.2
			l.Shadows = false
			l.Parent = holder
			v.Light = l
		end
		v.Glow = {}
		eachPart(m, function(p)
			if p.Name == "GlowCrack" or p.Name == "CoreGlow" then
				table.insert(v.Glow, p)
				p:SetAttribute("BaseT", p.Transparency)
			end
		end)
		return v
	end

	local function stepRock(v, t: number)
		if not v.ExplodeAt then
			return
		end
		local left = v.ExplodeAt - t
		local k = math.clamp(1 - left / ((B.Rocks and B.Rocks.ExplodeAfter) or 9), 0, 1)
		local speed = 2 + k * 14
		local pulse = .5 + .5 * math.sin(t * speed)
		for _, p in ipairs(v.Glow) do
			local base = p:GetAttribute("BaseT") or 0
			p.Transparency = math.clamp(base - pulse * .3 * k, 0, 1)
		end
		if v.Light then
			v.Light.Brightness = 1.2 + pulse * 3 * k
			v.Light.Color = PURPLE:Lerp(BLOOD, k * .6)
		end
		if k > .6 and v.Model.PrimaryPart then
			local j = (k - .6) * .25
			v.Model:PivotTo(CF(v.Pos + V3(math.sin(t * 50) * j, 0, math.cos(t * 47) * j)) * ANG(0, (tonumber(v.Key) or 1) * 2.1, 0))
		end
	end

	local function syncTargets()
		local folder = targetsFolder()
		local seen = {}
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				if part:IsA("BasePart") then
					local kind = part:GetAttribute("Kind")
					local id = part:GetAttribute("TargetId")
					local ending = part:GetAttribute("EndReason")
					if ending ~= nil and visuals[id] and not visuals[id].PendingHow then
						-- Strike keeps a removed part ~0.6 s with its EndReason: "Broke" = smashed, anything else = collapse
						visuals[id].PendingHow = ending == "Broke" and "Break" or (ending == "Explode" and "Silent" or "Collapse")
					end
					if id ~= nil and ending == nil and (kind == "BossSkeleton" or kind == "BossMound" or kind == "CursedRock") then
						seen[id] = true
						if not visuals[id] then
							if kind == "BossSkeleton" then
								visuals[id] = newSkeleton(id, part)
							elseif kind == "BossMound" then
								visuals[id] = newMound(id, part)
							else
								visuals[id] = newRockVisual(id, part, rockByTarget[id])
							end
						else
							visuals[id].Part = part
						end
					end
				end
			end
		end
		for id, v in pairs(visuals) do
			if not seen[id] then
				removeVisual(id, v.PendingHow or (v.Kind == "BossSkeleton" and "Break" or nil))
			end
		end
	end

	local function clearVisuals()
		for id in pairs(visuals) do
			removeVisual(id, "Silent")
		end
		for key, f in pairs(rockFalls) do
			if f.Model then
				f.Model:Destroy()
			end
			rockFalls[key] = nil
		end
		table.clear(rockByTarget)
	end

	-- a rock falling from the sky toward its telegraph circle (on the real surface: arena floor or terrace ring)
	local function startRockFall(key: any, pos: Vector3, landAt: number, radius: number?)
		local m = Models.Rock(tonumber(key) or 1)
		m.Parent = FX.Folder()
		local to = groundAt(pos)
		local fall = { Key = key, Model = m, To = to, LandAt = landAt, Start = now(), Radius = radius or 4.5,
			From = Vector3.new(pos.X + 14, FLOOR + 95, pos.Z - 26) }
		fall.Telegraph = telegraph("Circle", pos, fall.Radius, landAt, nil, nil, PURPLE, to.Y)
		m:PivotTo(CF(fall.From))
		local core = m:FindFirstChild("Core")
		if not low() and core then
			local a0 = Instance.new("Attachment")
			a0.Position = V3(0, 1.4, 0)
			a0.Parent = core
			local a1 = Instance.new("Attachment")
			a1.Position = V3(0, -1.4, 0)
			a1.Parent = core
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Color = ColorSequence.new(GREEN, PURPLE)
			tr.LightEmission = 1
			tr.Lifetime = .45
			tr.Transparency = NumberSequence.new(.1, 1)
			tr.FaceCamera = true
			tr.Parent = core
		end
		play("RockWhistle", pos)
		rockFalls[key] = fall
	end

	local function stepRockFalls(t: number)
		for key, f in pairs(rockFalls) do
			if f.Model and not f.Landed then
				local dur = math.max(.4, f.LandAt - f.Start)
				local k = math.clamp((t - f.Start) / dur, 0, 1)
				local p = f.From:Lerp(f.To, k * k)
				f.Model:PivotTo(CF(p) * ANG(t * 3, t * 2.2, 0))
				if k >= 1 then
					f.Landed = true
					impact(f.To, f.Radius + .5, PURPLE, false, f.To.Y)
					f.Model:PivotTo(CF(f.To) * ANG(0, (tonumber(key) or 1) * 2.1, 0))
				end
			elseif f.Landed and not f.Model and t - f.LandAt > 2 then
				rockFalls[key] = nil
			elseif f.Landed and f.Model and t - f.LandAt > 4 then
				-- no target ever arrived for it (streaming / missed event): let it crumble
				f.Model:Destroy()
				rockFalls[key] = nil
			end
		end
	end

	-- a shard hurled from a broken rock into the boss
	local function shard(from: Vector3, damage: number?)
		local p = FX.Part({ Class = "Part", Size = V3(1.2, 1.2, 2.4), Color = PURPLE, CFrame = CF(from + V3(0, 2, 0)) })
		local a0 = Instance.new("Attachment")
		a0.Position = V3(0, 0, 1)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = V3(0, 0, -1)
		a1.Parent = p
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(PURPLE, GREEN)
		tr.LightEmission = 1
		tr.Lifetime = .3
		tr.Parent = p
		local start = os.clock()
		local origin = from + V3(0, 2, 0)
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local k = math.clamp((os.clock() - start) / .55, 0, 1)
			local goal = corePos()
			local mid = (origin + goal) / 2 + V3(0, 10, 0)
			local a = origin:Lerp(mid, k)
			local b = mid:Lerp(goal, k)
			local pos = a:Lerp(b, k)
			p.CFrame = Models.Look(pos, pos + (b - a))
			if k >= 1 then
				conn:Disconnect()
				p:Destroy()
				FX.Burst(goal, { Color = PURPLE, Color2 = GREEN_HOT, Count = 30, Speed = { 8, 20 }, Lifetime = { .3, .7 }, Size = { .6, 1.2, 0 } })
				FX.Light(goal, PURPLE, 26, 4, .6)
				FX.Popup(goal + V3(0, 6, 0), "-" .. Shared.Format(damage or 0), PURPLE, true)
				play("WeakPointHit", goal)
				shakeAt(goal, .3, .3, 60)
			end
		end)
	end

	-- skeleton hands bursting out of a fake mound
	local function hands(pos: Vector3)
		for i = 1, low() and 2 or 4 do
			local m = Models.Hand(i)
			local a = i / 4 * PI * 2 + rand(-.3, .3)
			local base = pos + V3(math.cos(a) * 1.8, 0, math.sin(a) * 1.8)
			local cfEnd = CF(base) * ANG(0, -a, 0) * ANG(rand(-.3, .3), 0, rand(-.35, .35))
			m:PivotTo(cfEnd * CF(0, -3.4, 0))
			m.Parent = FX.Folder()
			local start = os.clock() + i * .06
			local conn
			conn = RunService.Heartbeat:Connect(function()
				local k = os.clock() - start
				if k < 0 then
					return
				end
				local up = backOut(math.clamp(k / .35, 0, 1))
				local down = smooth((k - 1.6) / .6)
				m:PivotTo(cfEnd * CF(0, -3.4 + 3.4 * up - 3.6 * down, 0) * ANG(0, 0, math.sin(k * 14) * .12 * (1 - down)))
				if k > 2.3 then
					conn:Disconnect()
					m:Destroy()
				end
			end)
		end
		FX.Burst(pos + V3(0, 1, 0), { Texture = FX.Textures.Smoke, Color = CURSE, Color2 = RGB(40, 16, 60), Count = 12, Speed = { 3, 8 },
			Lifetime = { .8, 1.5 }, Size = { 2, 4, 5 }, Transparency = { .3, 1 }, LightEmission = .3 })
		FX.Debris(pos + V3(0, 1, 0), DIRT, Enum.Material.Ground, 12, 24, { MaxSize = 1.1, Floor = FLOOR + .2 })
		play("SkeletonRattle", pos)
		play("Cackle", pos, { Volume = .7 })
	end

	---------------------------------------------------------------------------------------------------------------
	-- entrance cinematic
	---------------------------------------------------------------------------------------------------------------
	local cameraBusy = false
	-- the player is busy with the camera of their own: a timing-hit session (HalloweenStrike / the Mining Corner publish
	-- MiningActive on the main GUI; its circles are projected through the camera and expire as misses off screen) or an
	-- open menu / modal
	local function cameraLocked(): boolean
		local ok, locked = pcall(function()
			local pg = player:FindFirstChildOfClass("PlayerGui")
			local main = pg and pg:FindFirstChild("ScreenGui")
			return main ~= nil and (main:GetAttribute("MiningActive") == true or main:GetAttribute("OpenMenu") ~= nil
				or (tonumber(main:GetAttribute("ModalOwnerCount")) or 0) > 0)
		end)
		return ok and locked == true
	end
	-- a short scripted camera shot: goalAt(e) -> CFrame (e = seconds since the shot started), eased in from and back out
	-- to the player's camera; any key / click / tap skips it. Never with ReducedMotion, while a timing session or a menu
	-- owns the camera (cameraLocked, also checked every frame), for another camera owner, outside the zone, or (unless
	-- allowPit) for fighters in the pit. Returns true when the shot started.
	local function cameraShot(duration: number, goalAt: (number) -> CFrame, allowPit: boolean?): boolean
		if cameraBusy or Shared.ReducedMotion() or cameraLocked() then
			return false
		end
		local cam = workspace.CurrentCamera
		if not cam or cam.CameraType ~= Enum.CameraType.Custom then
			return false
		end
		local r = myRoot()
		if not allowPit and r and Layout.InPit(r.CFrame.Position) then
			return false -- fighters keep their camera
		end
		if not Shared.InZone(r and r.CFrame.Position or camPos(), 0) then
			return false
		end
		cameraBusy = true
		cam.CameraType = Enum.CameraType.Scriptable
		local startCF = cam.CFrame
		local t0 = os.clock()
		local done = false
		local inputConn
		local function finish()
			if done then
				return
			end
			done = true
			if inputConn then
				inputConn:Disconnect()
			end
			RunService:UnbindFromRenderStep("DOGROTS_BossShot")
			if cam.CameraType == Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Custom
			end
			cameraBusy = false
		end
		inputConn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1 then
				finish()
			end
		end)
		RunService:BindToRenderStep("DOGROTS_BossShot", Enum.RenderPriority.Camera.Value + 1, function()
			if done then
				return
			end
			if cameraLocked() then
				-- a timing session / menu started during the shot: hand the camera straight back
				finish()
				return
			end
			local e = os.clock() - t0
			local k
			if e < 1 then
				k = smooth(e)
			elseif e < duration - .8 then
				k = 1
			else
				k = 1 - smooth((e - (duration - .8)) / .8)
			end
			local ok, goal = pcall(goalAt, math.min(e, duration))
			if ok and typeof(goal) == "CFrame" then
				cam.CFrame = startCF:Lerp(goal, k)
			end
			if e >= duration then
				finish()
			end
		end)
		return true
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE GRAVE BELL rings the Gravekeeper up. The bell model (Workspace.DOGROTS_District.38_DeadYard...GraveBell, built
	-- by Pit.lua) swings on its axle: the parts of its sub-model "Swing" (or "BellSwing") about the model's PrimaryPart
	-- (the axle, X axis) or an Attachment "BellPivot", or (older builds) the parts named Bell{Crown,Shoulder,Waist,Flare,
	-- Lip,Glow,Clapper} + the BellSkull model about the top of the bell; "...Clapper..." parts lag and overshoot, the pull
	-- rope (BellRope* / BellSally*) follows the lever, Neon "...Glow / Rune / Glyph..." parts flare and the bell's own key
	-- light pulses on every toll (Brightness only). Client-local, restored exactly afterwards (and when the event switches
	-- off). Streamed out / missing: the FX still play.
	---------------------------------------------------------------------------------------------------------------
	local BELL_SWING = { BellCrown = true, BellShoulder = true, BellWaist = true, BellFlare = true, BellLip = true, BellGlow = true,
		BellClapper = true, BellSkull = true }
	local BELL_PERIOD = 1.8 -- full swing: the clapper strikes at every extreme (0, 0.9, 1.8 s)
	local BELL_TOLLS = { .1, .9, 1.8 }
	local bell = nil -- {Recs = {{Part, CF0, Clapper}}, Glow = {{Part, Color}}, Pivot, Center, T0, Amp}

	local function findBell(): Model?
		local district = workspace:FindFirstChild("DOGROTS_District")
		local yard = district and district:FindFirstChild("38_DeadYard")
		if not yard then
			return nil
		end
		local pit = yard:FindFirstChild("Pit")
		local m = pit and pit:FindFirstChild("GraveBell")
		if not m then
			m = yard:FindFirstChild("GraveBell", true)
		end
		return (m and m:IsA("Model")) and m or nil
	end
	-- world-space top of a part (any rotation)
	local function topOf(p: BasePart): number
		local cf, s = p.CFrame, p.Size
		return cf.Position.Y + math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
	end
	local function stopBell()
		local b = bell
		bell = nil
		if not b then
			return
		end
		for _, list in ipairs({ b.Recs, b.Rope }) do
			for _, rec in ipairs(list) do
				if rec.Part.Parent then
					rec.Part.CFrame = rec.CF0
				end
			end
		end
		for _, g in ipairs(b.Glow) do
			if g.Part.Parent then
				g.Part.Color = g.Color
			end
		end
		for _, l in ipairs(b.Lights) do
			if l.Light.Parent then
				l.Light.Brightness = l.Base
			end
		end
	end
	local function startBell()
		stopBell()
		local m = findBell()
		if not m then
			return nil
		end
		local recs, inSwing = {}, {}
		local function add(p: Instance)
			if p:IsA("BasePart") and not inSwing[p] then
				inSwing[p] = true
				table.insert(recs, { Part = p, CF0 = p.CFrame, Clapper = string.find(p.Name, "Clapper") ~= nil })
			end
		end
		-- the swinging assembly: Model "Swing" (PrimaryPart = the axle, Pit.lua) / "BellSwing", or the old bell's part names
		local swing = m:FindFirstChild("Swing") or m:FindFirstChild("BellSwing")
		if swing then
			add(swing)
			for _, d in ipairs(swing:GetDescendants()) do
				add(d)
			end
		else
			for _, c in ipairs(m:GetChildren()) do
				if BELL_SWING[c.Name] then
					add(c)
					for _, d in ipairs(c:GetDescendants()) do
						add(d)
					end
				end
			end
		end
		if #recs == 0 then
			return nil
		end
		local sum, top = V3(0, 0, 0), -math.huge
		local body = 0
		for _, rec in ipairs(recs) do
			if rec.Part.Material == Enum.Material.Metal or rec.Part.Material == Enum.Material.Neon then
				sum += rec.Part.CFrame.Position
				body += 1
			end
			top = math.max(top, topOf(rec.Part))
		end
		local center = body > 0 and sum / body or recs[1].Part.CFrame.Position
		-- pivot: the swing model's PrimaryPart (axle along its X axis), an Attachment "BellPivot", or the top of the bell
		local pivot = CF(center.X, top, center.Z)
		local axle = (swing and swing:IsA("Model")) and (swing.PrimaryPart or swing:FindFirstChild("SwingPivot")) or nil
		local pa = m:FindFirstChild("BellPivot", true)
		if axle and axle:IsA("BasePart") then
			pivot = axle.CFrame
		elseif pa and pa:IsA("Attachment") and pa.Parent and pa.Parent:IsA("BasePart") then
			pivot = pa.Parent.CFrame * pa.CFrame
		elseif swing and swing.Name == "Swing" then
			return nil -- StreamingEnabled: the axle has not streamed in yet, so no swing (the FX still play)
		end
		-- glows that flare on each toll (bell rune band, clapper core, the dais rune ring / well), lights that pulse (the
		-- bell's own key light; HwLantern / HwBrazier lights belong to AmbientFX), the pull rope that follows the lever
		local glow, lights, rope = {}, {}, {}
		local ropeTop, ropeLow = nil, math.huge
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				local n = d.Name
				if d.Material == Enum.Material.Neon and (string.find(n, "Glow") or string.find(n, "Rune") or string.find(n, "Glyph")) then
					table.insert(glow, { Part = d, Color = d.Color })
				end
				if not inSwing[d] and (string.find(n, "^BellRope") or string.find(n, "^BellSally")) then
					table.insert(rope, { Part = d, CF0 = d.CFrame })
					local cf, sz = d.CFrame, d.Size
					local hy = math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
					ropeLow = math.min(ropeLow, cf.Position.Y - hy)
					if not ropeTop or cf.Position.Y + hy > ropeTop.Y then
						-- the highest end of the long axis
						local axis = (sz.X >= sz.Y and sz.X >= sz.Z) and cf.RightVector * sz.X / 2 or ((sz.Y >= sz.Z) and cf.UpVector * sz.Y / 2 or cf.LookVector * sz.Z / 2)
						ropeTop = cf.Position + (axis.Y >= 0 and axis or -axis)
					end
				end
			elseif (d:IsA("SpotLight") or d:IsA("PointLight") or d:IsA("SurfaceLight")) and d.Parent
				and not (d.Parent:GetAttribute("HwLantern") or d.Parent:GetAttribute("HwBrazier") or d.Parent:GetAttribute("HwCandle")) then
				table.insert(lights, { Light = d, Base = d.Brightness })
			end
		end
		bell = { Recs = recs, Glow = glow, Lights = lights, Rope = ropeTop and rope or {}, RopeTop = ropeTop, RopeLow = ropeLow, Pivot = pivot,
			Center = center, T0 = os.clock(), Amp = math.rad(reduced() and 9 or 24) }
		return bell
	end
	-- damped pendulum: yanked to one side, swings through 3 extremes, settles by ~3.4 s
	local function bellAngle(e: number, amp: number): number
		if e <= 0 then
			return 0
		end
		return amp * smooth(e / .12) * math.exp(-e * .35) * (1 - smooth((e - 2.0) / 1.4)) * math.cos(2 * PI * e / BELL_PERIOD)
	end
	local function stepBell()
		local b = bell
		if not b then
			return
		end
		local e = os.clock() - b.T0
		if e > 3.5 then
			stopBell()
			return
		end
		local inv = b.Pivot:Inverse()
		local rot = b.Pivot * ANG(bellAngle(e, b.Amp), 0, 0) * inv
		local rotC = b.Pivot * ANG(bellAngle(e - .12, b.Amp * 1.3), 0, 0) * inv
		for _, rec in ipairs(b.Recs) do
			if rec.Part.Parent then
				rec.Part.CFrame = (rec.Clapper and rotC or rot) * rec.CF0
			end
		end
		-- the pull rope follows the lever (its top end rides along, the coil on the ground stays)
		if b.RopeTop then
			local delta = (rot * CF(b.RopeTop)).Position - b.RopeTop
			local span = math.max(.5, b.RopeTop.Y - b.RopeLow)
			for _, rec in ipairs(b.Rope) do
				if rec.Part.Parent then
					local w = math.clamp((rec.CF0.Position.Y - b.RopeLow) / span, 0, 1)
					rec.Part.CFrame = rec.CF0 + delta * w
				end
			end
		end
		local glowK = 0
		for _, at in ipairs(BELL_TOLLS) do
			if e >= at then
				glowK = math.max(glowK, math.exp(-(e - at) * 3.2))
			end
		end
		for _, g in ipairs(b.Glow) do
			if g.Part.Parent then
				g.Part.Color = g.Color:Lerp(GREEN_HOT, glowK)
			end
		end
		for _, l in ipairs(b.Lights) do
			if l.Light.Parent then
				l.Light.Brightness = l.Base * (1 + 1.5 * glowK)
			end
		end
	end

	-- slow rising fog puffs (smoke particles)
	local function fogPuff(at: Vector3, count: number)
		FX.Burst(at, { Texture = FX.Textures.Smoke, Color = RGB(150, 136, 186), Color2 = RGB(70, 60, 96), Count = count, Speed = { .8, 2.4 }, Spread = 35,
			Direction = V3(0, 1, 0), Acceleration = V3(0, 1.2, 0), Lifetime = { 2.2, 3.4 }, Size = { 3, 6, 8 }, Transparency = { .62, 1 }, LightEmission = .05,
			Drag = .6 })
	end

	-- the summon: 3 tolls (shockwave rings, light, dust + chips from the frame, chains kick, the yard's lanterns gutter),
	-- glowing cracks running from the bell down into the pit, rising fog; returns the cues (merged into the rise timeline)
	-- and the bell framing for the camera shot
	local function bellCues(center: Vector3): ({ { any } }, CFrame?)
		local b = startBell()
		local base = Vector3.new(Layout.Bell.Position.X, Layout.Bell.Position.Y, Layout.Bell.Position.Z)
		local body = b and b.Center or base + V3(0, 5.5, 0)
		local top = b and b.Pivot.Position or base + V3(0, 8, 0)
		local q = Shared.Quality()
		local puffs = low() and 2 or (q == "Medium" and 4 or 7)
		local cues = {}
		local function toll(i: number, k: number)
			play("BellToll", body, { Pitch = ({ 1, .96, .91 })[i] or 1 })
			-- pressure wave over the ground + a ripple ring spreading from the bell's mouth
			FX.Ring(base + V3(0, .1, 0), TOLL, 22 * k, 1.2, { Thickness = .1, Transparency = .55, Material = Enum.Material.SmoothPlastic })
			if not low() then
				FX.Ring(body - V3(0, 1.4, 0), RGB(206, 190, 255), 9 * k, .7, { Height = 0, Thickness = .1, Transparency = .3 })
			end
			FX.Light(body, i == 3 and GREEN or PURPLE, 34, 4.5 * k, 1)
			FX.Burst(top + V3(0, .6, 0), { Texture = FX.Textures.Smoke, Color = DUST, Color2 = RGB(90, 80, 70), Count = 9, Speed = { 1, 3 }, Spread = 60,
				Direction = V3(0, -1, 0), Acceleration = V3(0, -7, 0), Lifetime = { .9, 1.5 }, Size = { .5, 1.1, 1.6 }, Transparency = { .4, 1 }, LightEmission = 0,
				Drag = 1 })
			FX.Debris(top, RGB(82, 62, 48), Enum.Material.Wood, 3, 8, { MaxSize = .35, Floor = base.Y + .2 })
			Bus.Fire("ChainKick", { Position = body, Radius = 40, Strength = 1.4 * k })
			-- every lantern in the yard gutters with the toll (AmbientFX: negative flare = dim)
			Bus.Fire("LanternFlare", { Position = body, Radius = 170, Strength = -.85, Seconds = .3 })
			shakeAt(body, .3 * k, .45, 70)
		end
		for i, at in ipairs(BELL_TOLLS) do
			local k = 1 - (i - 1) * .15
			table.insert(cues, { at, function()
				toll(i, k)
			end })
			table.insert(cues, { at + .22, function() -- a second flicker right after
				Bus.Fire("LanternFlare", { Position = body, Radius = 170, Strength = -.7, Seconds = .22 })
			end })
		end
		table.insert(cues, { .05, function()
			play("BellCreak", top)
		end })
		-- cracks race from the bell down the pit wall to its centre
		local from = Vector3.new(base.X, 0, base.Z)
		local to = Vector3.new(center.X, 0, center.Z)
		local side = V3(-(to - from).Z, 0, (to - from).X)
		side = side.Magnitude > .01 and side.Unit or V3(1, 0, 0)
		local n = low() and 5 or 9
		for i = 1, n do
			local f = i / (n + 1)
			table.insert(cues, { .15 + i * .13, function()
				local g = groundAt(from:Lerp(to, f) + side * ((i % 2 == 0) and 1.4 or -1.4))
				FX.Cracks(g + V3(0, .05, 0), V3(0, 1, 0), i % 2 == 0 and PURPLE or GREEN, 4 + f * 4, 3.4)
				if i % 3 == 1 then
					play("GroundCrack", g, { Volume = .7 })
					FX.Debris(g + V3(0, .3, 0), RGB(64, 60, 72), Enum.Material.Slate, 3, 12, { MaxSize = .6, Floor = g.Y + .1 })
				end
			end })
		end
		-- fog rises around the bell, along the rim, then in the pit
		table.insert(cues, { .3, function()
			for i = 1, puffs do
				local a = i / puffs * PI * 2
				fogPuff(base + V3(math.cos(a) * 5, .6, math.sin(a) * 5), 3)
			end
		end })
		table.insert(cues, { 1.0, function()
			for i = 1, math.max(1, math.floor(puffs / 2)) do
				fogPuff(groundAt(from:Lerp(to, i / (puffs + 1))) + V3(0, .6, 0), 3)
			end
		end })
		table.insert(cues, { 1.5, function()
			for i = 1, puffs do
				local a = i / puffs * PI * 2 + .4
				fogPuff(groundAt(center + V3(math.cos(a) * 13, 0, math.sin(a) * 13)) + V3(0, .6, 0), 3)
			end
		end })
		-- the power surges back: lanterns flare green as the boss breaks out
		table.insert(cues, { 2.4, function()
			Bus.Fire("LanternFlare", { Position = center, Radius = 200, Strength = .8, Seconds = 1.4, Color = GREEN })
		end })
		local shot = b and Models.Look(body + V3(-4.5, 1.8, -10.5), body + V3(0, -.6, 0)) or nil
		return cues, shot
	end

	local riseTL = nil
	local function riseCinematic(data: any)
		local center = Vector3.new(PIT.X, FLOOR, PIT.Z)
		if typeof(data.Position) == "Vector3" then
			center = Vector3.new(data.Position.X, FLOOR, data.Position.Z)
		end
		local cues, bellShot = bellCues(center)
		local function add(at: number, fn)
			table.insert(cues, { at, fn })
		end
		add(1.2, function()
			play("BossBurrow", center, { Volume = .8, Pitch = .7 })
		end)
		add(1.95, function()
			play("Thunder", nil, { Volume = .5 })
		end)
		-- ground cracks spreading out from the centre (the bell's crack chain arrives)
		for i = 1, low() and 4 or 9 do
			add(1.25 + i * .09, function()
				local a = rand(0, PI * 2)
				local r = rand(2, 16)
				FX.Cracks(center + V3(math.cos(a) * r, .04, math.sin(a) * r), V3(0, 1, 0), i % 2 == 0 and PURPLE or GREEN, rand(6, 11), 5)
			end)
		end
		-- fog bursts away + green flame pillars
		add(1.45, function()
			FX.Ring(center + V3(0, .3, 0), RGB(140, 120, 170), 34, 1.6, { Thickness = .3, Transparency = .5, Material = Enum.Material.SmoothPlastic })
			for i = 1, low() and 6 or 14 do
				local a = i / 14 * PI * 2
				local p = center + V3(math.cos(a) * 8, 1.2, math.sin(a) * 8)
				FX.Burst(p, { Texture = FX.Textures.Smoke, Color = RGB(150, 140, 170), Color2 = RGB(60, 50, 80), Count = 5,
					Speed = { 14, 24 }, Spread = 15, Direction = V3(math.cos(a), .15, math.sin(a)), Lifetime = { 1, 1.8 }, Size = { 3, 6, 8 },
					Transparency = { .3, 1 }, LightEmission = .1, Drag = 2 })
			end
			for i = 1, 4 do
				local a = i / 4 * PI * 2 + PI / 4
				FX.Beam(center + V3(math.cos(a) * 13, 0, math.sin(a) * 13), i % 2 == 0 and PURPLE or GREEN, 22, 4.5)
			end
			FX.Light(center + V3(0, 4, 0), GREEN, 60, 3, 2.5)
		end)
		-- rocks fly
		add(1.6, function()
			FX.Debris(center + V3(0, 1, 0), RGB(64, 60, 72), Enum.Material.Slate, 26, 46, { MaxSize = 2.2, Floor = FLOOR + .3 })
			FX.Debris(center + V3(0, 1, 0), DIRT, Enum.Material.Ground, 20, 38, { MaxSize = 1.6, Floor = FLOOR + .3 })
			FX.Debris(center + V3(0, 1, 0), BONE, Enum.Material.SmoothPlastic, 10, 32, { MaxSize = 1, Floor = FLOOR + .3 })
		end)
		add(1.8, function()
			play("BossEmerge", center)
			FX.Shake(.6, 1.2)
		end)
		add(4.6, function()
			play("BossRoar", center)
			FX.Shockwave(center + V3(0, .4, 0), GREEN, 30, 1.1)
			flash(GREEN, .18, .5)
			FX.Shake(.8, 1.2)
		end)
		-- camera (spectators in the zone, not the fighters in the pit): the bell first, then the pit as the boss breaks out
		add(.05, function()
			local pitShot = Layout.Boss.Camera
			local pitCF = Models.Look(pitShot.Eye, pitShot.Focus)
			cameraShot(bellShot and 5.6 or 4.8, function(e)
				local pit = pitCF * CF(0, 0, -math.max(0, e - (bellShot and 1.3 or 0)) * .6)
				if not bellShot then
					return pit
				end
				return bellShot:Lerp(pit, smooth((e - 1.25) / 1.1))
			end)
		end)
		if riseTL then
			riseTL.Cancelled = true
		end
		riseTL = timeline(cues)
	end

	---------------------------------------------------------------------------------------------------------------
	-- DOGS DIG THE WEAK POINTS: when YOU dig an open weak point, a spectral copy of your best assigned yard dog (server
	-- StrikeBegin Extra.Companion; MenuModels clone like the dig-spot companion) rises at the boss's flank under that
	-- weak point and digs with you: dig loop, dirt + soul spray, a soul tether into the weak point, and on every hit that
	-- lands (BossEvent Hit) a pounce with a claw slash across the weak point + the bonus. No dog in the team: nothing.
	---------------------------------------------------------------------------------------------------------------
	local GHOST = RGB(150, 215, 255)
	local DOG_SIZE = Vector3.new(6, 4.8, 6) -- a bit bigger than the dig-spot companion: it reads next to a 26-stud boss
	local digger = nil -- {Model, Parts, Highlight, Anim, Part, Slot, Side, Pos, Yaw, Bonus, NextPuff, PounceAt, Beam, Born}
	local DogRig, DogAnim = nil, nil
	local function dogLibs()
		if DogRig == nil then
			DogRig, DogAnim = false, false
			pcall(function()
				local r = RS:FindFirstChild("DogRig")
				DogRig = r and require(r) or false
			end)
			pcall(function()
				local a = RS:FindFirstChild("DogAnimationPlayer")
				DogAnim = a and require(a) or false
			end)
		end
		return DogRig or nil, DogAnim or nil
	end

	-- the dog's ground spot: beside the body under the weak point, on the digger's side; facing the weak point
	local function diggerSpot(g): (Vector3, number)
		local cf = (boss and boss.Pos) and (CF(boss.Pos) * ANG(0, boss.Yaw, 0)) or serverCF() or CF(PIT)
		local def = Models.Slots.Weak[g.Slot]
		local lz = math.clamp(def and def.Pos.Z or 0, -12.5, 9)
		local at = (cf * CF(g.Side * 8.4, 0, lz)).Position
		local wp = weakPos(g.Slot)
		local look = Vector3.new(wp.X - at.X, 0, wp.Z - at.Z)
		local yaw = look.Magnitude > .1 and math.atan2(-look.X, -look.Z) or 0
		return Vector3.new(at.X, FLOOR, at.Z), yaw
	end

	local function removeDigger(fade: boolean?)
		local g = digger
		digger = nil
		if not g then
			return
		end
		if g.FX then
			pcall(g.FX.Stop)
			g.FX = nil
		end
		if g.Beam then
			g.Beam:Destroy()
		end
		if g.Model and g.Model.Parent then
			if fade then
				FX.Smoke(g.Pos + V3(0, 1.5, 0), GHOST, 3, 1.2)
				for _, p in ipairs(g.Parts) do
					FX.Tween(p, .5, { Transparency = 1 })
				end
				if g.Highlight then
					FX.Tween(g.Highlight, .5, { FillTransparency = 1, OutlineTransparency = 1 })
				end
				Debris:AddItem(g.Model, .6)
			else
				g.Model:Destroy()
			end
		end
		if g.Anim then
			pcall(function()
				g.Anim:Stop()
			end)
		end
	end

	local function spawnDigger(part: BasePart?, slot: string, info: any, bonus: number)
		removeDigger(false)
		local Rig, Anim = dogLibs()
		local menu = RS:FindFirstChild("MenuModels")
		local template = (type(info) == "table" and type(info.Asset) == "string" and menu) and menu:FindFirstChild(info.Asset) or nil
		if not (Rig and boss and Models.Slots.Weak[slot] and template and template:IsA("Model")) then
			return nil
		end
		local model = template:Clone()
		local ok = pcall(function()
			Rig.Prepare(model, DOG_SIZE)
		end)
		if not ok then
			model:Destroy()
			return nil
		end
		-- the side of the body the digger stands on
		local r = myRoot()
		local rel = r and (CF(boss.Pos) * ANG(0, boss.Yaw, 0)):PointToObjectSpace(r.CFrame.Position) or V3(1, 0, 0)
		local g = { Model = model, Part = part, Slot = slot, Side = rel.X >= 0 and 1 or -1, Bonus = bonus, NextPuff = 0, PounceAt = -10,
			Born = os.clock() }
		g.Pos, g.Yaw = diggerSpot(g)
		Rig.Place(model, g.Pos - V3(0, 2.5, 0), ANG(0, g.Yaw, 0))
		g.Parts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				d.CastShadow = false
				d.Transparency = math.max(d.Transparency, .38)
				table.insert(g.Parts, d)
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = math.max(d.Transparency, .4)
			end
		end
		local hl = Instance.new("Highlight")
		hl.FillColor = GHOST
		hl.OutlineColor = GREEN_HOT
		hl.FillTransparency = .55
		hl.OutlineTransparency = .1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
		g.Highlight = hl
		model.Name = "WeakPointDigger"
		model.Parent = FX.Folder()
		-- soul tether: dog -> weak point (follows both)
		local wa = boss.WeakAtt and boss.WeakAtt[slot]
		local root = model.PrimaryPart
		if wa and root then
			local a0 = Instance.new("Attachment")
			a0.Name = "Tether"
			a0.Position = V3(0, 1, 0)
			a0.Parent = root
			local beam = Instance.new("Beam")
			beam.Attachment0, beam.Attachment1 = a0, wa
			beam.Color = ColorSequence.new(GHOST, GREEN)
			beam.LightEmission = 1
			beam.Transparency = NumberSequence.new(.5, .85)
			beam.Width0, beam.Width1 = .3, .8
			beam.FaceCamera = true
			beam.CurveSize0, beam.CurveSize1 = 4, -2
			beam.Segments = 12
			beam.Parent = root
			g.Beam = beam
		end
		if Anim then
			pcall(function()
				local id = info.Id or (Anim.DogIdFor and Anim.DogIdFor(info.Asset))
				g.Anim = Anim.new(model, id)
				local clip = Anim.ResolveName(id, "Work") or Anim.ResolveName(id, "Idle")
				if clip then
					g.Anim:Play(clip, { Looped = true })
				end
			end)
		end
		FX.Smoke(g.Pos + V3(0, 1.2, 0), GHOST, 3.4, 1.2)
		FX.Burst(g.Pos + V3(0, 1.5, 0), { Color = GHOST, Color2 = GREEN, Count = 18, Speed = { 3, 9 }, Lifetime = { .5, 1 }, Size = { .3, .55, 0 } })
		FX.Debris(g.Pos + V3(0, .5, 0), DIRT, Enum.Material.Ground, 8, 18, { MaxSize = .8, Floor = FLOOR + .2 })
		play("GhostWoo", g.Pos, { Volume = .5 })
		if bonus > 0 then
			FX.Popup(g.Pos + V3(0, 5, 0), L("YOUR DOG DIGS IN! +", "ТВОЯ СОБАКА КОПАЕТ! +") .. math.floor(bonus * 100 + .5) .. "%", GHOST, true)
		end
		-- an event dog brings its ability FX (Models.EventDogs HwFX_* hooks): looping at .7, a burst on every pounce
		local dogId = type(info) == "table" and tostring(info.Id or info.Asset or "") or ""
		if string.sub(dogId, 1, 3) == "HW_" then
			pcall(function()
				local mod = Halloween:WaitForChild("Models"):FindFirstChild("EventDogs")
				local ED = mod and require(mod)
				g.FX = (ED and ED.StartFX) and ED.StartFX(model, { Low = low(), Intensity = .7 }) or nil
				if g.FX then
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("ParticleEmitter") and d.Name == "HwFXEmitter" then
							d:SetAttribute("HwParticlePriority", true) -- the player's own digger: never governed away
						end
					end
				end
			end)
		end
		digger = g
		return g
	end

	-- a hit landed: the dog pounces at the weak point, claws across it, soil + soul spray
	local function diggerPounce(g)
		g.PounceAt = os.clock()
		if g.FX then
			pcall(g.FX.Burst, 12)
		end
		local wp = weakPos(g.Slot)
		local from = g.Pos + V3(0, 1.4, 0)
		local dir = wp - from
		dir = dir.Magnitude > .1 and dir.Unit or V3(0, 1, 0)
		for i = -1, 1 do
			local slash = FX.Part({ Size = V3(.16, 3.4 - math.abs(i) * .6, .1), Color = i == 0 and GREEN_HOT or GHOST, Transparency = .1,
				CFrame = Models.Look(wp - dir * .8, wp + dir) * CF(i * .55, 0, 0) * ANG(0, 0, .6 + i * .12) })
			FX.Tween(slash, .32, { Transparency = 1, Size = slash.Size * V3(1, 1.25, 1) })
			Debris:AddItem(slash, .4)
		end
		FX.Burst(wp, { Color = GHOST, Color2 = GREEN_HOT, Count = 12, Speed = { 5, 12 }, Lifetime = { .3, .6 }, Size = { .3, .5, 0 } })
		if not low() then
			FX.Burst(from, { Color = GREEN, Color2 = GHOST, Count = 8, Speed = { 18, 28 }, Spread = 12, Direction = dir, Lifetime = { .35, .6 },
				Acceleration = V3(0, 0, 0), Size = { .25, .4, 0 } })
			FX.Burst(g.Pos + V3(0, .6, 0), { Texture = FX.Textures.Smoke, Color = DIRT, Color2 = RGB(40, 30, 26), Count = 5, Speed = { 2, 5 },
				Lifetime = { .5, .9 }, Size = { 1, 1.8, 2.4 }, Transparency = { .35, 1 }, LightEmission = 0 })
		end
		FX.Debris(g.Pos + V3(0, .5, 0), DIRT, Enum.Material.Ground, 5, 16, { MaxSize = .6, Floor = FLOOR + .2 })
		FX.Debris(g.Pos + V3(0, .5, 0), BONE, Enum.Material.SmoothPlastic, 2, 14, { MaxSize = .4, Floor = FLOOR + .2 })
		play("DigSoil", g.Pos, { Volume = .35, Pitch = 1.1 })
	end

	local function stepDigger(dt: number)
		local g = digger
		if not g then
			return
		end
		local w = boss and boss.Weak[g.Slot]
		local gone = g.Part ~= nil and (not g.Part.Parent or g.Part:GetAttribute("EndReason") ~= nil)
		if not w or not w.Shown or gone or (A("WeakOpenUntil") or 0) <= now() then
			removeDigger(true)
			return
		end
		-- follow the walking / turning boss (smoothed), rise out of the ground, pounce on hits
		local goal, yaw = diggerSpot(g)
		local k = 1 - math.exp(-dt * 8)
		g.Pos = g.Pos:Lerp(goal, k)
		local diff = (yaw - g.Yaw + PI) % (2 * PI) - PI
		g.Yaw += diff * k
		local rise = backOut(math.clamp((os.clock() - g.Born) / .6, 0, 1))
		local p = math.clamp((os.clock() - g.PounceAt) / .42, 0, 1)
		local hop = p < 1 and math.sin(p * PI) or 0
		local fwd = CF(0, 0, 0) * ANG(0, g.Yaw, 0)
		local off = fwd:VectorToWorldSpace(V3(0, 0, -1.3 * hop)) + V3(0, -2.5 * (1 - rise) + 1.5 * hop, 0)
		if DogRig then
			DogRig.Place(g.Model, g.Pos + off, ANG(0, g.Yaw, 0) * ANG(.35 * hop, 0, 0))
		end
		if g.Anim then
			pcall(function()
				g.Anim:Step(workspace:GetServerTimeNow())
			end)
		end
		if g.Beam then
			local since = os.clock() - g.PounceAt
			local flare = math.clamp(1 - since / .5, 0, 1)
			g.Beam.Transparency = NumberSequence.new(.5 - .35 * flare, .85 - .3 * flare)
			g.Beam.Width1 = .8 + .9 * flare
		end
		local t = os.clock()
		if t >= g.NextPuff then
			g.NextPuff = t + .6 + math.random() * .35
			if not low() then
				FX.Debris(g.Pos + V3(0, .4, 0), DIRT, Enum.Material.Ground, 2, 10, { MaxSize = .35, Floor = FLOOR + .2 })
			end
		end
	end

	Bus.On("StrikeBegin", function(d)
		if type(d) ~= "table" or d.Kind ~= "BossWeak" then
			return
		end
		local slot = tostring(d.Variant or (d.Part and d.Part:GetAttribute("Slot")) or "")
		if digger and digger.Part == d.Part and digger.Slot == slot then
			return -- the same weak point again: the dog keeps digging
		end
		local extra = type(d.Extra) == "table" and d.Extra or {}
		local ok, err = pcall(spawnDigger, d.Part, slot, extra.Companion, tonumber(extra.DogBonus) or 0)
		if not ok then
			warn("Halloween BossFX digger: " .. tostring(err))
		end
	end)
	Bus.On("StrikeEnd", function(d)
		if type(d) == "table" and d.Kind == "BossWeak" and digger and (d.Part == nil or d.Part == digger.Part) then
			removeDigger(true)
		end
	end)

	---------------------------------------------------------------------------------------------------------------
	-- HIT REACTIONS: every hit on a plate / weak point (ours and other players' swings) kicks the struck bone away from the
	-- hitter (hanging limbs swing back from the joint), the chest follows, the neck + head whip after it and the jaw snaps;
	-- the plate flashes white (one reused Highlight), an open weak point flares white. Perfect / crit / weak-point hits of
	-- our own hold the rig still for the hit-stop first.
	---------------------------------------------------------------------------------------------------------------
	local HANGING = { ArmL = true, ArmR = true, ForeL = true, ForeR = true, PawL = true, PawR = true }
	local function slotOf(part: Instance?): string?
		if typeof(part) ~= "Instance" then
			return nil
		end
		local s = part:GetAttribute("Variant") or part:GetAttribute("Slot")
		return type(s) == "string" and s or nil
	end
	local function hitReact(slot: string, from: Vector3?, amp: number, delay: number?)
		if not boss then
			return
		end
		local def = Models.Slots.Plates[slot] or Models.Slots.Weak[slot]
		if not def then
			return
		end
		local weak = Models.Slots.Weak[slot] ~= nil
		local at = weak and weakPos(slot) or platePos(slot)
		local rel = (CF(boss.Pos or PIT) * ANG(0, boss.Yaw or 0, 0)):VectorToObjectSpace(at - (from or camPos()))
		rel = V3(rel.X, 0, rel.Z)
		rel = rel.Magnitude > .05 and rel.Unit or V3(0, 0, 1)
		local d0 = delay or 0
		local a = amp * (HANGING[def.Bone] and -1 or 1) * (def.Bone == "Pelvis" and .45 or 1)
		-- +X pitch tips the top of a bone toward +Z (away from a hitter in front), -Z roll tips it toward +X
		addFlinch(def.Bone, rel.Z * a, -rel.X * a * .35, -rel.X * a, d0)
		if def.Bone ~= "Chest" then
			addFlinch("Chest", rel.Z * amp * .3, 0, -rel.X * amp * .3, d0)
		end
		addFlinch("Neck", -rel.Z * amp * .45, rel.X * amp * .3, rel.X * amp * .3, d0 + .04)
		addFlinch("Head", -rel.Z * amp * .35, 0, -rel.X * amp * .4, d0 + .07)
		addFlinch("Jaw", -amp * 1.4, 0, 0, d0 + .02)
		if weak then
			addFlinch("Pelvis", rel.Z * amp * .2, 0, -rel.X * amp * .2, d0)
		end
	end
	local function flashPlate(group: Instance, strength: number)
		if not boss then
			return
		end
		local hl = boss.HitHL
		if not hl or not hl.Parent then
			hl = Instance.new("Highlight")
			hl.Name = "HitFlash"
			hl.FillColor = WHITE
			hl.OutlineColor = GREEN_HOT
			hl.DepthMode = Enum.HighlightDepthMode.Occluded
			hl.FillTransparency = 1
			hl.OutlineTransparency = 1
			hl.Parent = boss.Model
			boss.HitHL = hl
		end
		hl.Adornee = group
		hl.FillTransparency = 1 - .7 * strength
		hl.OutlineTransparency = 1 - .8 * strength
		FX.Tween(hl, .16, { FillTransparency = 1, OutlineTransparency = 1 })
	end
	local function rootOf(userId: any): Vector3?
		local ok, pos = pcall(function()
			local other = Players:GetPlayerByUserId(tonumber(userId) or 0)
			local ch = other and other.Character
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			return (r and r:IsA("BasePart")) and r.CFrame.Position or nil
		end)
		return ok and pos or nil
	end

	Bus.On("StrikeSwing", function(d)
		if type(d) ~= "table" or (d.Kind ~= "BossPlate" and d.Kind ~= "BossWeak") or d.Miss or not boss or anim.Mode == "Death" then
			return
		end
		local slot = slotOf(d.Part)
		if not slot then
			return
		end
		local weak = d.Kind == "BossWeak"
		local remote = d.Remote == true
		local hold = remote and 0 or (tonumber(d.HitStop) or 0)
		if weak and not remote then
			hold = math.max(hold, .05)
		end
		if hold > 0 then
			anim.HoldUntil = math.max(anim.HoldUntil or 0, os.clock() + hold)
		end
		local from
		if remote then
			from = rootOf(d.UserId)
		else
			local r = myRoot()
			from = r and r.CFrame.Position or nil
		end
		hitReact(slot, from, .1 * (d.Perfect and 1.5 or 1) * (weak and 1.8 or 1) * (remote and .55 or 1), hold)
		if weak then
			local w = boss.Weak[slot]
			if w and w.FX then
				w.FX.HitAt = os.clock() + hold
			end
		else
			local pl = boss.Plates[slot]
			if pl and pl.Shown then
				flashPlate(pl.Group, d.Perfect and 1 or (remote and .35 or .6))
			end
		end
		-- a perfect hit of ours leaves a glowing crack where the pickaxe landed
		if d.Perfect and not remote and typeof(d.Position) == "Vector3" and not low() then
			FX.Cracks(d.Position, typeof(d.Normal) == "Vector3" and d.Normal or nil, weak and GOLD or GREEN, weak and 2.6 or 2, .7)
		end
	end)

	---------------------------------------------------------------------------------------------------------------
	-- THE DEATH: killing blow (hit-stop + slow-motion recoil, white flash, FOV punch; "KILLING BLOW!" for the hitter) ->
	-- stagger (death roar, flames sputter, eyes flicker, bone chips, knees buckle) -> collapse (floor impact) -> soul burst
	-- (the soul tears out of the ribcage and flies to the moon) -> bones scatter (real rig parts fly, bounce and fade, the
	-- rest crumbles) -> moon flare (the moon blazes, every lantern in the yard flares). A moderate camera shot (also for the
	-- fighters in the pit, never during a timing session / menu, skippable) frames the fall from the north rim.
	---------------------------------------------------------------------------------------------------------------
	local lastKillHit = -10 -- os.clock of our hit that took the last armor (BossEvent Hit with Armor 0)
	local scatter = {} -- {Part, V, R, T, Life, Base, Floor}
	local scattered = {} -- [part] = true (left out of the crumble fade)
	local soul = nil -- {Part, Glow, From, Born, Dur, Pos}
	local moonFlare = nil -- {Model, Core, Halo, Ring, Born, Dur}
	local MOON_DIR = (function()
		local d = Layout.Moon.Position - (Layout.Gate.Center + V3(0, 6, 0))
		return d.Magnitude > 1 and d.Unit or V3(.8, .5, 0).Unit
	end)()
	local MOON_TAN = Layout.Moon.Radius / math.max(1, (Layout.Moon.Position - (Layout.Gate.Center + V3(0, 6, 0))).Magnitude)
	local function deathStage(stage: string)
		Bus.Fire("BossDeath", { Stage = stage })
	end

	local function scatterBones()
		if not boss then
			return
		end
		local core = corePos()
		local pool = {}
		for _, p in ipairs(boss.Model:GetDescendants()) do
			if p:IsA("BasePart") and p ~= boss.Root and p.Name ~= "Bone" and p.Transparency < .5 and p.Material ~= Enum.Material.Neon
				and p.Size.Magnitude > 1.6 then
				table.insert(pool, p)
			end
		end
		local n = math.min(#pool, low() and 8 or (Shared.Quality() == "Medium" and 16 or 28))
		for i = 1, n do
			local j = math.random(i, #pool)
			pool[i], pool[j] = pool[j], pool[i]
			local p = pool[i]
			p.Anchored = true
			local w = p:FindFirstChild("W")
			if w then
				w:Destroy()
			end
			local pos = p.CFrame.Position
			local out = V3(pos.X - core.X, 0, pos.Z - core.Z)
			out = out.Magnitude > .1 and out.Unit or V3(rand(-1, 1), 0, rand(-1, 1) + .01).Unit
			scattered[p] = true
			table.insert(scatter, { Part = p, V = out * rand(10, 24) + V3(0, rand(14, 26), 0), R = V3(rand(-6, 6), rand(-6, 6), rand(-6, 6)), T = 0,
				Life = rand(2.2, 3.2), Base = p.Transparency, Floor = groundAt(pos).Y })
		end
	end
	local function stepScatter(dt: number)
		for i = #scatter, 1, -1 do
			local s = scatter[i]
			s.T += dt
			local p = s.Part
			if not p.Parent or s.T >= s.Life then
				table.remove(scatter, i)
				if p.Parent then
					p.Transparency = 1
				end
			else
				s.V += V3(0, -70 * dt, 0)
				local cf = p.CFrame
				local pos = cf.Position + s.V * dt
				local half = math.min(p.Size.X, p.Size.Y, p.Size.Z) * .5
				if pos.Y < s.Floor + half then
					pos = V3(pos.X, s.Floor + half, pos.Z)
					s.V = V3(s.V.X * .45, math.abs(s.V.Y) * .28, s.V.Z * .45)
					s.R *= .6
				end
				p.CFrame = CF(pos) * (cf - cf.Position) * ANG(s.R.X * dt, s.R.Y * dt, s.R.Z * dt)
				p.Transparency = s.Base + (1 - s.Base) * math.clamp((s.T - s.Life * .65) / (s.Life * .35), 0, 1)
			end
		end
	end

	-- the soul: a hot green orb + glow + trail, arcing from the ribcage up into the moon (as drawn by BloodMoonFX: camera
	-- + Layout.Moon direction)
	local function launchSoul(from: Vector3)
		if soul and soul.Part.Parent then
			soul.Part:Destroy()
		end
		local orb = FX.Part({ Class = "Part", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.6, Color = GREEN_HOT, CFrame = CF(from) })
		orb.Name = "BossSoul"
		local glow = FX.Part({ Class = "Part", Shape = Enum.PartType.Ball, Size = Vector3.one * 6, Color = GREEN, Transparency = .55,
			Material = Enum.Material.ForceField, CFrame = CF(from), Parent = orb })
		if not low() then
			local a0 = Instance.new("Attachment")
			a0.Position = V3(0, .9, 0)
			a0.Parent = orb
			local a1 = Instance.new("Attachment")
			a1.Position = V3(0, -.9, 0)
			a1.Parent = orb
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Color = ColorSequence.new(GREEN_HOT, PURPLE)
			tr.LightEmission = 1
			tr.Lifetime = .6
			tr.Transparency = NumberSequence.new(.1, 1)
			tr.FaceCamera = true
			tr.Parent = orb
			local l = Instance.new("PointLight")
			l.Color = GREEN
			l.Range = 24
			l.Brightness = 3
			l.Shadows = false
			l.Parent = orb
		end
		soul = { Part = orb, Glow = glow, From = from, Born = os.clock(), Dur = 1.4, Pos = from }
	end
	local function stepSoul()
		local s = soul
		if not s then
			return
		end
		local e = (os.clock() - s.Born) / s.Dur
		if e >= 1 or not s.Part.Parent then
			if s.Part.Parent then
				s.Part:Destroy()
			end
			soul = nil
			return
		end
		local to = camPos() + MOON_DIR * 200
		local mid = s.From:Lerp(to, .3) + V3(0, 30, 0)
		local k = e * e
		local p = s.From:Lerp(mid, k):Lerp(mid:Lerp(to, k), k)
		s.Pos = p
		s.Part.CFrame = CF(p)
		s.Glow.CFrame = CF(p)
		s.Glow.Transparency = .55 + .35 * e
	end

	-- the moon blazes: hot core + expanding halo + shock ring over the moon's disc (camera + Layout.Moon direction, like
	-- BloodMoonFX draws it), every lantern in the yard flares green
	local function startMoonFlare()
		if moonFlare then
			moonFlare.Model:Destroy()
		end
		local m = Instance.new("Model")
		m.Name = "MoonFlare"
		m.Parent = FX.Folder()
		local core = FX.Part({ Class = "Part", Shape = Enum.PartType.Ball, Size = Vector3.one, Color = RGB(230, 255, 230), Transparency = .2, Parent = m })
		local halo = FX.Part({ Class = "Part", Shape = Enum.PartType.Ball, Size = Vector3.one, Color = GREEN, Transparency = .5, Parent = m })
		local ring = FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Size = Vector3.one, Color = GREEN_HOT, Transparency = .3, Parent = m })
		moonFlare = { Model = m, Core = core, Halo = halo, Ring = ring, Born = os.clock(), Dur = 2.4 }
		Bus.Fire("LanternFlare", { Position = PIT, Radius = 260, Strength = 1.3, Seconds = 2.4, Color = GREEN_HOT })
		flash(RGB(220, 255, 230), .2, .9)
		play("MoonFlare")
	end
	local function stepMoonFlare()
		local f = moonFlare
		if not f then
			return
		end
		local e = (os.clock() - f.Born) / f.Dur
		if e >= 1 or not f.Model.Parent then
			f.Model:Destroy()
			moonFlare = nil
			return
		end
		local cp = camPos()
		local dist = 220
		local pos = cp + MOON_DIR * dist
		local r0 = dist * MOON_TAN
		local face = Models.Look(pos, cp)
		local swell = math.sin(math.min(1, e * 1.6) * PI / 2)
		f.Core.CFrame = face
		f.Core.Size = Vector3.one * r0 * 2 * (1.02 + .12 * swell)
		f.Core.Transparency = .15 + .85 * smooth((e - .35) / .65)
		f.Halo.CFrame = face * CF(0, 0, 2)
		f.Halo.Size = Vector3.one * r0 * 2 * (1.25 + 1.5 * e)
		f.Halo.Transparency = .45 + .55 * e
		f.Ring.CFrame = face * ANG(0, PI / 2, 0)
		f.Ring.Size = V3(.6, r0 * 2 * (1.1 + 2.6 * e), r0 * 2 * (1.1 + 2.6 * e))
		f.Ring.Transparency = .25 + .75 * e
	end

	-- the death camera: from the north rim (the boss camera side), a slow orbit, tilting up after the soul at the end
	local function deathCamera(t0: number): boolean
		if not boss then
			return false
		end
		local center = boss.Pos or Vector3.new(PIT.X, FLOOR, PIT.Z)
		local north = Layout.Boss.Camera.Eye - Layout.Boss.Camera.Focus
		north = V3(north.X, 0, north.Z)
		north = north.Magnitude > .1 and north.Unit or V3(0, 0, -1)
		local left = math.max(2.4, 5.2 - (os.clock() - t0))
		return cameraShot(left, function(e)
			local a = -.7 - e * .06 -- north-west of the boss: a 3/4 profile of the fall, the moon up to the left
			local dir = V3(north.X * math.cos(a) - north.Z * math.sin(a), 0, north.X * math.sin(a) + north.Z * math.cos(a))
			local eye = center + dir * 40 + V3(0, 24, 0)
			local focus = center + V3(0, 6, 0)
			if soul then
				focus = focus:Lerp(soul.Pos, smooth((os.clock() - soul.Born) / soul.Dur) * .3)
			end
			return Models.Look(eye, focus)
		end, true)
	end

	local function startDeath(mine: boolean)
		if not boss or deathTL then
			return
		end
		anim.Mode, anim.ModeAt = "Death", now()
		anim.Death = os.clock()
		clearTelegraphs()
		for _, w in pairs(boss.Weak) do
			if w.Shown then
				w.Shown = false
				for p in pairs(w.Parts) do
					FX.Tween(p, .25, { Transparency = 1 })
				end
				closeWeakFX(w, true)
			end
		end
		setSoulDim(0)
		-- killing blow: the rig freezes for a beat, then recoils in slow motion
		anim.HoldUntil = os.clock() + .28
		anim.SlowUntil = os.clock() + .8
		local t0 = os.clock()
		local camStarted = false
		local function tryCamera()
			if not camStarted and boss then
				camStarted = deathCamera(t0)
			end
		end
		local cues = {
			{ 0, function()
				local core = corePos()
				play("KillBlow", core)
				flash(WHITE, mine and .55 or .35, .35)
				FX.Punch(mine and 1.4 or .9)
				FX.Light(core, GREEN_HOT, 60, 6, .6)
				FX.Burst(core, { Color = WHITE, Color2 = GREEN_HOT, Count = 40, Speed = { 16, 34 }, Lifetime = { .25, .6 }, Size = { .6, 1.2, 0 } })
				FX.Shockwave(floorAt(boss and boss.Pos or PIT) + V3(0, .3, 0), GREEN_HOT, 22, .6)
				shakeAt(core, mine and .7 or .5, .45, 120)
				if mine then
					FX.Popup(core + V3(0, 7, 0), L("KILLING BLOW!", "СМЕРТЕЛЬНЫЙ УДАР!"), GOLD_HOT, true)
				end
				Bus.Fire("BossKillingBlow", { Mine = mine })
			end },
			{ .5, function()
				if not boss then
					return
				end
				play("BossDeath", boss.Pos)
				setFlameRate(.35)
				eyesTo(WHITE)
				FX.Debris(corePos(), BONE, Enum.Material.SmoothPlastic, 8, 18, { MaxSize = .7, Floor = FLOOR + .2 })
				deathStage("Stagger")
			end },
			{ .95, function()
				if boss then
					eyesTo(GREEN)
					play("BossStep", boss.Pos, { Pitch = .8 })
					FX.Ring(floorAt(boss.Pos), DUST, 10, .6, { Thickness = .12, Transparency = .45, Material = Enum.Material.SmoothPlastic })
					shakeAt(boss.Pos, .25, .3, 70)
				end
			end },
			{ 1.45, function()
				if boss then
					eyesTo(RGB(120, 160, 110))
					play("BossStep", boss.Pos, { Pitch = .72 })
					FX.Debris(corePos(), BONE, Enum.Material.SmoothPlastic, 6, 16, { MaxSize = .6, Floor = FLOOR + .2 })
					shakeAt(boss.Pos, .3, .3, 70)
				end
			end },
			{ 2.75, function()
				if not boss then
					return
				end
				impact(boss.Pos, 16, GREEN, true)
				FX.Ring(floorAt(boss.Pos), DUST, 30, 1.4, { Thickness = .3, Transparency = .5, Material = Enum.Material.SmoothPlastic })
				FX.Smoke(floorAt(boss.Pos) + V3(0, 2, 0), RGB(110, 100, 96), 9, 2.2)
				deathStage("Collapse")
			end },
			{ 3.1, function()
				if not boss then
					return
				end
				setFlameRate(0)
				eyesTo(RGB(30, 30, 34))
				setLights(.15)
				local core = corePos()
				FX.Burst(core, { Color = GREEN_HOT, Color2 = PURPLE, Count = 60, Speed = { 10, 26 }, Lifetime = { .8, 1.6 }, Size = { .8, 1.4, 0 } })
				FX.Shockwave(core, GREEN_HOT, 18, .8)
				FX.Light(core, GREEN_HOT, 70, 6, 1.4)
				FX.Beam(floorAt(boss.Pos), GREEN, 60, 2.5)
				flash(GREEN_HOT, .25, .5)
				play("SoulBurst", core)
				shakeAt(core, .35, .5, 120)
				launchSoul(core)
				for p in pairs(boss.Soul or {}) do
					p.Transparency = 1
				end
				deathStage("SoulBurst")
			end },
			{ 3.25, function()
				if not boss then
					return
				end
				scatterBones()
				play("BoneScatter", boss.Pos)
				-- the rest crumbles: bones fade and sink
				local m = boss.Model
				for _, p in ipairs(m:GetDescendants()) do
					if p:IsA("BasePart") and p.Transparency < 1 and not scattered[p] then
						task.delay(math.random() * 1.4, function()
							if p.Parent then
								FX.Tween(p, 1.3, { Transparency = 1 })
							end
						end)
					end
				end
				shatterModel(m, BONE, 26)
				deathStage("Scatter")
			end },
			{ 4.5, function()
				startMoonFlare()
				deathStage("MoonFlare")
			end },
			{ 7.0, function()
				destroyBoss()
			end },
		}
		for _, at in ipairs({ .45, .8, 1.2, 1.6 }) do
			table.insert(cues, { at, tryCamera })
		end
		deathTL = timeline(cues)
		deathTL.Mine = mine
	end

	---------------------------------------------------------------------------------------------------------------
	-- events
	---------------------------------------------------------------------------------------------------------------
	local PHASE_HINT = {
		[1] = { "Break its stone armor with timing hits!", "Разбей каменную броню точными ударами!" },
		[2] = { "It burrowed! Dig the REAL grave mound!", "Он зарылся! Раскопай НАСТОЯЩИЙ могильный холм!" },
		[3] = { "Smash the skeleton dogs to break its shield!", "Разбей собак-скелетов, чтобы снять щит!" },
		[4] = { "Break the cursed rocks - hurl the shards back!", "Разбей проклятые камни - швырни осколки в него!" },
		[5] = { "Weak points open - dig them for x3 damage!", "Открылись слабые места - бей их для x3 урона!" },
	}
	local PHASE_RU = { AWAKENING = "ПРОБУЖДЕНИЕ", BURROW = "ПОДКОП", ["SKELETON PACK"] = "СТАЯ СКЕЛЕТОВ", ["CURSED ROCKS"] = "ПРОКЛЯТЫЕ КАМНИ",
		ENRAGED = "ЯРОСТЬ" }
	local DIFF_RU = { EASY = "ЛЕГКО", UNEASY = "НЕСПОКОЙНО", NIGHTMARE = "КОШМАР", HELL = "АД", ["???"] = "???" }

	local function inArena(): boolean
		return nearPit(10)
	end

	local function onEvent(d: any)
		if type(d) ~= "table" then
			return
		end
		local kind = d.Kind
		local local_ = inArena()
		if kind == "Rise" then
			local name = tostring(d.Name or "")
			local sub = tostring(d.Numeral or "") .. " · " .. L(name, DIFF_RU[name])
			if d.Reason == "Exorcism" then
				sub = sub .. " · " .. L("THE EXORCISM WOKE IT", "ЭКЗОРЦИЗМ РАЗБУДИЛ ЕГО")
			end
			banner(L("THE GRAVEKEEPER RISES", "СМОТРИТЕЛЬ КЛАДБИЩА ВОССТАЛ"), sub, GREEN, 4.5)
			if local_ then
				buildBoss()
				anim.Mode, anim.ModeAt = "Rise", now()
				riseCinematic(d)
			end
		elseif not local_ and kind ~= "Defeated" and kind ~= "Escaped" and kind ~= "Reward" and kind ~= "Knock" and kind ~= "Hit" then
			return
		end
		if kind == "Phase" then
			local p = tonumber(d.Phase) or 1
			local hint = PHASE_HINT[p]
			local name = tostring(d.Name or "")
			if p > 1 then
				banner(L("PHASE ", "ФАЗА ") .. p .. " · " .. L(name, PHASE_RU[name]), hint and L(hint[1], hint[2]) or nil, p == 5 and BLOOD or PURPLE, 3.2)
			end
		elseif kind == "Attack" then
			if d.Stage == "Telegraph" then
				anim.Attack = d.Attack
				local pos = typeof(d.Position) == "Vector3" and d.Position or PIT
				if d.Attack == "Sweep" then
					telegraph("Cone", pos, tonumber(d.Radius) or 20, tonumber(d.ImpactAt) or now() + 1, d.Direction, tonumber(d.Angle) or 120, BLOOD)
				else
					telegraph("Circle", pos, tonumber(d.Radius) or 12, tonumber(d.ImpactAt) or now() + 1.2, nil, nil, d.Attack == "Stomp" and PURPLE or BLOOD)
				end
				play("BossRoar", pos, { Volume = .35, Pitch = 1.25 })
			else
				anim.Impact, anim.ImpactKind = os.clock(), d.Attack or ""
				local pos = typeof(d.Position) == "Vector3" and d.Position or PIT
				if d.Attack == "Sweep" then
					local dir = typeof(d.Direction) == "Vector3" and d.Direction or V3(0, 0, -1)
					for i = 1, 3 do
						impact(pos + dir * (5 + i * 4.5), 4, BLOOD, false)
					end
					play("BossSlam", pos, { Pitch = 1.2 })
				else
					impact(pos, tonumber(d.Radius) or 12, d.Attack == "Stomp" and PURPLE or GREEN, true)
				end
			end
		elseif kind == "Knock" then
			local r = myRoot()
			if r and typeof(d.Velocity) == "Vector3" then
				r.AssemblyLinearVelocity = d.Velocity
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum:ChangeState(Enum.HumanoidStateType.Freefall)
				end
			end
			FX.Flash(CURSE, .22, .35)
			FX.Shake(.45, .35)
			if (tonumber(d.Curse) or 0) > 0 and r then
				FX.Popup(r.CFrame.Position + V3(0, 3, 0), "+" .. math.floor(d.Curse) .. " " .. L("CURSE", "ПРОКЛЯТИЕ"), CURSE, false)
			end
			play("Whisper", nil, { Volume = .6 })
		elseif kind == "Burrow" then
			if d.Stage == "Dive" then
				play("BossBurrow", typeof(d.Position) == "Vector3" and d.Position or PIT)
				local p = typeof(d.Position) == "Vector3" and d.Position or PIT
				task.delay(.6, function()
					FX.Debris(floorAt(p) + V3(0, 1, 0), DIRT, Enum.Material.Ground, 24, 36, { MaxSize = 1.8, Floor = FLOOR + .3 })
					FX.Smoke(floorAt(p) + V3(0, 1, 0), RGB(96, 82, 70), 8, 2)
					FX.Cracks(floorAt(p), V3(0, 1, 0), GREEN, 14, 3)
					shakeAt(p, .5, .8, 90)
				end)
			end
		elseif kind == "MoundHit" then
			local v = visuals[d.TargetId]
			local pos = typeof(d.Position) == "Vector3" and d.Position or (v and v.Pos) or PIT
			if v then
				v.QuakeAt, v.QuakeReal = os.clock(), d.Real == true
			end
			if d.Real then
				play("BossBurrow", pos, { Volume = .5, Pitch = .6 })
				FX.Burst(floorAt(pos) + V3(0, 1.5, 0), { Texture = FX.Textures.Smoke, Color = RGB(110, 96, 80), Count = 6, Speed = { 3, 7 }, Lifetime = { .6, 1 },
					Size = { 2, 3, 4 }, Transparency = { .4, 1 }, LightEmission = 0 })
				FX.Light(floorAt(pos) + V3(0, 1, 0), GREEN, 12, 1.5, .5)
				shakeAt(pos, .25, .3, 30)
			else
				play("DigBone", pos)
				FX.Debris(floorAt(pos) + V3(0, 1.5, 0), BONE, Enum.Material.SmoothPlastic, 4, 14, { MaxSize = .5, Floor = FLOOR + .2 })
			end
		elseif kind == "FakeMound" then
			local pos = typeof(d.Position) == "Vector3" and floorAt(d.Position) or PIT
			local v = visuals[d.TargetId]
			if v then
				v.PendingHow = "Fake"
			end
			hands(pos)
			if d.UserId == player.UserId then
				banner(L("A FAKE!", "ОБМАНКА!"), L("Something else is buried here...", "Здесь закопано что-то другое..."), CURSE, 2)
			end
		elseif kind == "Erupt" then
			local pos = typeof(d.Position) == "Vector3" and floorAt(d.Position) or PIT
			for id, v in pairs(visuals) do
				if v.Kind == "BossMound" then
					removeVisual(id, "Collapse")
				end
			end
			buildBoss()
			anim.Mode, anim.ModeAt = "Erupt", now()
			if boss then
				boss.Pos = Vector3.new(pos.X, FLOOR, pos.Z)
			end
			impact(pos, 12, d.Found and GREEN or BLOOD, true)
			FX.Debris(pos + V3(0, 1, 0), DIRT, Enum.Material.Ground, 30, 50, { MaxSize = 2.2, Floor = FLOOR + .3 })
			play("BossEmerge", pos)
			play("BossRoar", pos, { Delay = .3 })
			if d.Found then
				FX.Popup(pos + V3(0, 14, 0), "-" .. Shared.Format(tonumber(d.Damage) or 0), GREEN, true)
				banner(L("FOUND IT!", "НАШЁЛ!"), L("The Gravekeeper is dragged out of its grave!", "Смотрителя вытащили из могилы!"), GREEN, 2.4)
			end
		elseif kind == "Skeletons" then
			play("SkeletonRattle", PIT, { Volume = 1 })
			play("Howl", PIT, { Volume = .6 })
		elseif kind == "Shield" then
			if d.Up == false then
				banner(L("SHIELD BROKEN!", "ЩИТ РАЗБИТ!"), L("Hit the Gravekeeper now!", "Бей Смотрителя!"), GREEN, 2.4)
			end
		elseif kind == "SkeletonDown" then
			if d.Collapse and type(d.List) == "table" then
				for _, row in ipairs(d.List) do
					local v = visuals[row.TargetId]
					if v then
						v.PendingHow = "Collapse"
					end
				end
			end
		elseif kind == "Bite" then
			local v = visuals[d.TargetId]
			if v then
				v.LungeAt = os.clock()
			end
			play("SkeletonRattle", typeof(d.Position) == "Vector3" and d.Position or nil, { Volume = .5, Pitch = 1.4 })
			if d.UserId == player.UserId then
				FX.Flash(BLOOD, .18, .25)
			end
		elseif kind == "Rocks" then
			if type(d.Rocks) == "table" then
				for _, r in ipairs(d.Rocks) do
					if typeof(r.Position) == "Vector3" then
						startRockFall(r.Key, r.Position, tonumber(r.LandAt) or now() + 1.6, tonumber(r.Radius))
					end
				end
			end
			if (tonumber(d.Wave) or 1) == 1 then
				play("Thunder", nil, { Volume = .6 })
			end
		elseif kind == "RockLand" then
			if d.TargetId ~= nil then
				rockByTarget[d.TargetId] = d.Key
				local fall = rockFalls[d.Key]
				if fall then
					fall.ExplodeAt = tonumber(d.ExplodeAt)
				end
				local v = visuals[d.TargetId]
				if v and v.Kind == "CursedRock" then
					v.ExplodeAt = tonumber(d.ExplodeAt)
				end
			end
		elseif kind == "RockShard" then
			local v = visuals[d.TargetId]
			if v then
				v.PendingHow = "Break"
			end
			shard(typeof(d.From) == "Vector3" and groundAt(d.From) or PIT, tonumber(d.Damage))
		elseif kind == "RockExplode" then
			local pos = typeof(d.Position) == "Vector3" and (groundAt(d.Position) + V3(0, .06, 0)) or PIT
			local v = visuals[d.TargetId]
			if v then
				v.PendingHow = "Silent"
			end
			FX.Shockwave(pos + V3(0, .4, 0), PURPLE, 9, .7)
			FX.Burst(pos + V3(0, 2, 0), { Texture = FX.Textures.Smoke, Color = CURSE, Color2 = RGB(30, 10, 40), Count = 16, Speed = { 6, 14 },
				Lifetime = { .8, 1.6 }, Size = { 2.5, 5, 7 }, Transparency = { .3, 1 }, LightEmission = .3 })
			FX.Debris(pos + V3(0, 2, 0), RGB(54, 46, 62), Enum.Material.Basalt, 18, 40, { MaxSize = 1.5, Floor = pos.Y + .2 })
			FX.Light(pos + V3(0, 3, 0), PURPLE, 26, 4, .7)
			play("RockImpact", pos, { Pitch = .75 })
			shakeAt(pos, .55, .45, 70)
		elseif kind == "Enrage" then
			buildBoss()
			anim.Mode, anim.ModeAt = "Enrage", now()
			banner(L("THE GRAVEKEEPER IS ENRAGED!", "СМОТРИТЕЛЬ В ЯРОСТИ!"), L("Weak points open - dig them for x3 damage!", "Открылись слабые места - x3 урон!"), BLOOD, 3.2)
			play("BossEnrage", boss and boss.Pos or PIT)
			FX.Flash(BLOOD, .3, .5)
			FX.Shake(1.0, 1.2)
			FX.Shockwave(floorAt(boss and boss.Pos or PIT) + V3(0, .4, 0), BLOOD, 34, 1)
			eyesTo(BLOOD)
			setLights(1.6)
			setFlameRate(1.8)
		elseif kind == "WeakPoint" then
			if d.Open then
				play("Heartbeat", boss and boss.Pos or PIT, { Volume = .8 })
			end
		elseif kind == "PlateBreak" then
			showPlate(tostring(d.Slot), false, true)
			if d.UserId == player.UserId then
				FX.Popup(platePos(tostring(d.Slot)) + V3(0, 3, 0), L("ARMOR SHATTERED!", "БРОНЯ РАЗБИТА!"), PURPLE, true)
			end
		elseif kind == "PlateRegrow" then
			showPlate(tostring(d.Slot), true, true)
		elseif kind == "Hit" then
			local pos
			if d.Weak then
				pos = weakPos(tostring(d.Slot))
			else
				pos = platePos(tostring(d.Slot))
			end
			local n = tonumber(d.Damage) or 0
			-- HUD feedback (boss bar shake / damage chunk) + the killing blow (our hit took the last armor; the server's
			-- Defeated follows on its next step, or already arrived)
			local maxArmor = tonumber(A("MaxArmor")) or 0
			local armor = tonumber(d.Armor)
			local share = maxArmor > 0 and n / maxArmor or 0
			Bus.Fire("BossHit", { Damage = n, Weak = d.Weak == true, Crit = d.Crit == true, Quality = d.Quality, Slot = d.Slot, Armor = armor,
				MaxArmor = maxArmor, Share = share, Heavy = d.Crit == true or d.Weak == true or share >= .02 })
			if armor and armor <= 0 and n > 0 then
				lastKillHit = os.clock()
				if deathTL and not deathTL.Mine and os.clock() - deathTL.T0 < 1.2 then
					deathTL.Mine = true
					FX.Popup(corePos() + V3(0, 7, 0), L("KILLING BLOW!", "СМЕРТЕЛЬНЫЙ УДАР!"), GOLD_HOT, true)
				end
			end
			if n > 0 then
				-- the strike client already pops the number; weak points get the extra x3 stamp + glow
				if d.Weak then
					FX.Popup(pos + V3(0, 4.5, 0), L("WEAK POINT x3!", "СЛАБОЕ МЕСТО x3!"), GREEN_HOT, true)
					play("WeakPointHit", pos)
					FX.Cracks(pos, V3(0, -1, 0), GREEN, 3, .8)
					FX.Light(pos, GREEN, 16, 3, .4)
					-- your dog dug with you: pounce + claw slash + its share of the damage
					local g = digger
					if g and g.Slot == tostring(d.Slot) then
						diggerPounce(g)
						local bonus = tonumber(d.DogBonus) or 0
						if bonus > 0 then
							FX.Popup(g.Pos + V3(0, 4.2, 0), L("DOG +", "СОБАКА +") .. math.floor(bonus * 100 + .5) .. "%", GHOST, false)
						end
					end
				elseif not low() then
					FX.Debris(pos, STONE, Enum.Material.Slate, 3, 14, { MaxSize = .6, Floor = FLOOR + .3 })
				end
			elseif d.Weak == false and n == 0 then
				FX.Popup(pos + V3(0, 3, 0), L("NO EFFECT", "НЕТ ЭФФЕКТА"), PURPLE, false)
			end
		elseif kind == "Defeated" then
			local top = type(d.Top) == "table" and d.Top or {}
			local names = {}
			for i, row in ipairs(top) do
				if i <= 3 then
					table.insert(names, tostring(row.Name or "?"))
				end
			end
			banner(L("THE GRAVEKEEPER FALLS!", "СМОТРИТЕЛЬ ПОВЕРЖЕН!"), #names > 0 and (L("Top: ", "Лучшие: ") .. table.concat(names, ", ")) or nil, GREEN, 4.5)
			if local_ and boss then
				startDeath(os.clock() - lastKillHit < 1.5)
			end
		elseif kind == "Escaped" then
			local why = d.Reason == "Empty" and L("Everyone left the pit.", "Все покинули яму.")
				or (d.Reason == "Disabled" and "" or L("Time ran out - it burrowed away.", "Время вышло - он зарылся."))
			if d.Reason ~= "Disabled" then
				banner(L("THE GRAVEKEEPER ESCAPED", "СМОТРИТЕЛЬ СБЕЖАЛ"), why, PURPLE, 3.5)
			end
			if boss then
				anim.Mode, anim.ModeAt = "Escape", now()
				play("BossBurrow", boss.Pos)
				task.delay(.6, function()
					if boss then
						FX.Debris(floorAt(boss.Pos) + V3(0, 1, 0), DIRT, Enum.Material.Ground, 24, 36, { MaxSize = 1.8, Floor = FLOOR + .3 })
						FX.Smoke(floorAt(boss.Pos) + V3(0, 1, 0), RGB(96, 82, 70), 8, 2)
					end
				end)
				task.delay(3.4, destroyBoss)
			end
			clearTelegraphs()
		elseif kind == "Reward" then
			local parts = {}
			if (tonumber(d.Candy) or 0) > 0 then
				table.insert(parts, "+" .. Shared.Format(d.Candy) .. " " .. L("CANDY", "КОНФЕТ"))
			end
			if (tonumber(d.Bones) or 0) > 0 then
				table.insert(parts, "+" .. Shared.Format(d.Bones) .. " " .. L("BONES", "КОСТЕЙ"))
			end
			local ROW_RU = { ["CURSED PUMPKIN"] = "ПРОКЛЯТАЯ ТЫКВА", ["ECLIPSED FIND"] = "НАХОДКА ЗАТМЕНИЯ" }
			for _, row in ipairs(type(d.Rewards) == "table" and d.Rewards or {}) do
				if type(row) == "table" and row.Kind ~= "Candy" and row.Kind ~= "Bones" then
					local name = tostring(row.Name or row.Id or row.Kind)
					table.insert(parts, (row.Kind == "Dog" and "🐶 " or "") .. L(name, ROW_RU[name]))
				elseif type(row) == "table" and row.Converted and (tonumber(row.Amount) or 0) > 0 then
					table.insert(parts, "+" .. Shared.Format(row.Amount) .. " " .. (row.Kind == "Bones" and L("BONES", "КОСТЕЙ") or L("CANDY", "КОНФЕТ")))
				end
			end
			local title = d.Full and L("BOSS REWARD", "НАГРАДА ЗА БОССА") or L("CONSOLATION", "УТЕШИТЕЛЬНЫЙ ПРИЗ")
			if d.Unlocked then
				local def = B.Difficulties[tonumber(d.Unlocked) or 0]
				title = title .. " · " .. L("UNLOCKED ", "ОТКРЫТО ") .. tostring(def and def.Numeral or d.Unlocked)
			end
			task.delay(4.6, function()
				banner(title, table.concat(parts, "  ·  "), RGB(255, 200, 70), 4)
				Bus.Fire("CandyGain", { Amount = tonumber(d.Candy) or 0, Source = "Boss", Big = true })
				play("TreasureReveal")
			end)
		end
	end

	Bus.On("Signal", function(s)
		if type(s) == "table" and s.Kind == "BossEvent" then
			local ok, err = pcall(onEvent, s.Data)
			if not ok then
				warn("Halloween BossFX: " .. tostring(err))
			end
		end
	end)

	-- the strike client reports our own hits on boss targets: chips + a little crack where the pickaxe landed
	local lastHurt = -10
	Bus.On("StrikeResult", function(r)
		if type(r) ~= "table" then
			return
		end
		local kind = r.Kind
		if kind ~= "BossPlate" and kind ~= "BossWeak" and kind ~= "BossMound" and kind ~= "BossSkeleton" and kind ~= "CursedRock" then
			return
		end
		-- heavy hits on the body: a crit holds the rig a beat longer and kicks harder; crits / weak-point hits make it grunt
		if (kind == "BossPlate" or kind == "BossWeak") and boss and anim.Mode ~= "Death" and (tonumber(r.Damage) or 0) > 0 then
			local slot = slotOf(r.Part)
			if r.Crit and slot then
				anim.HoldUntil = math.max(anim.HoldUntil or 0, os.clock() + .06)
				local root = myRoot()
				hitReact(slot, root and root.CFrame.Position or nil, .16, .06)
			end
			if (r.Crit or kind == "BossWeak") and os.clock() - lastHurt > .6 then
				lastHurt = os.clock()
				play("BossHurt", (boss.Pos or PIT) + V3(0, 14, 0), { Volume = .55 })
			end
		end
		local p = typeof(r.Position) == "Vector3" and r.Position or nil
		if not p then
			return
		end
		if kind == "BossSkeleton" then
			FX.Debris(p, BONE, Enum.Material.SmoothPlastic, 3, 14, { MaxSize = .4, Floor = FLOOR + .2 })
		elseif kind == "BossMound" then
			FX.Debris(p, DIRT, Enum.Material.Ground, 4, 16, { MaxSize = .7, Floor = FLOOR + .2 })
		elseif kind == "CursedRock" then
			FX.Burst(p, { Color = PURPLE, Count = 6, Speed = { 4, 9 }, Lifetime = { .2, .5 } })
		end
	end)

	---------------------------------------------------------------------------------------------------------------
	-- main loop
	---------------------------------------------------------------------------------------------------------------
	local ACTIVE = { Rising = true, Fight = true }
	local lastSync = 0
	local lastPhase = 0
	local function syncMode()
		local st = A("State")
		local mode = A("Mode") or ""
		if ACTIVE[st] then
			if not boss and inArena() then
				buildBoss()
			end
			-- server mode drives the animation unless a local sequence (death / escape) owns it
			if anim.Mode ~= "Death" and anim.Mode ~= "Escape" then
				if mode ~= anim.Mode then
					anim.Mode = mode
					anim.ModeAt = A("ModeAt") or now()
				end
			end
			anim.Attack = A("Attack") ~= "" and A("Attack") or anim.Attack
			local phase = A("Phase") or 0
			if phase ~= lastPhase then
				if phase >= 5 and lastPhase < 5 and boss then
					eyesTo(BLOOD)
					setLights(1.6)
					setFlameRate(1.8)
				end
				lastPhase = phase
			end
		elseif st == "Idle" or st == nil then
			if boss and anim.Mode ~= "Death" and anim.Mode ~= "Escape" then
				destroyBoss()
			end
			if next(visuals) then
				clearVisuals()
			end
			lastPhase = 0
		end
		if boss then
			syncPlates()
			syncWeak()
			syncShield()
		end
	end

	-- soul tethers from skeleton dogs to the shielded boss
	local function syncTethers()
		if not boss or not boss.ShieldDome or not boss.CoreAtt or low() then
			if boss and next(boss.Tethers) and not boss.ShieldDome then
				for _, b in pairs(boss.Tethers) do
					b:Destroy()
				end
				boss.Tethers = {}
			end
			return
		end
		for id, v in pairs(visuals) do
			if v.Kind == "BossSkeleton" and not boss.Tethers[id] then
				local core = v.Model:FindFirstChild("Body")
				local bone = core and core:FindFirstChild("Bone")
				local att = bone and bone:FindFirstChild("Core")
				if att then
					local beam = Instance.new("Beam")
					beam.Attachment0 = att
					beam.Attachment1 = boss.CoreAtt
					beam.Color = ColorSequence.new(PURPLE, GREEN)
					beam.LightEmission = 1
					beam.Transparency = NumberSequence.new(.35, .7)
					beam.Width0, beam.Width1 = .25, .7
					beam.FaceCamera = true
					beam.CurveSize0 = 6
					beam.Segments = 12
					beam.Parent = boss.CoreAtt.Parent
					boss.Tethers[id] = beam
				end
			end
		end
		for id, beam in pairs(boss.Tethers) do
			if not visuals[id] then
				beam:Destroy()
				boss.Tethers[id] = nil
			end
		end
	end

	stateFolder.AttributeChanged:Connect(function()
		if Shared.Enabled() then
			syncMode()
		end
	end)

	-- cue lists + the free-running set pieces (bell swing, scattered bones, the soul, the moon flare)
	local function stepSequences(dt: number)
		stepTimelines()
		stepBell()
		stepScatter(dt)
		stepSoul()
		stepMoonFlare()
	end
	local function stopSequences()
		for _, tl in ipairs(timelines) do
			tl.Cancelled = true
		end
		table.clear(timelines)
		stopBell()
		table.clear(scatter)
		table.clear(scattered)
		if soul then
			soul.Part:Destroy()
			soul = nil
		end
		if moonFlare then
			moonFlare.Model:Destroy()
			moonFlare = nil
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		if not Shared.Enabled() then
			if boss then
				destroyBoss()
			end
			if next(visuals) then
				clearVisuals()
			end
			clearTelegraphs()
			if digger then
				removeDigger(false)
			end
			if bell or soul or moonFlare or next(timelines) or next(scatter) then
				stopSequences()
			end
			return
		end
		local t = now()
		if os.clock() - lastSync > .2 then
			lastSync = os.clock()
			syncMode()
			syncTargets()
			syncTethers()
		end
		do
			local ok, err = pcall(stepSequences, dt)
			if not ok then
				warn("Halloween BossFX sequence: " .. tostring(err))
			end
		end
		if boss then
			local ok, err = pcall(stepBoss, dt)
			if not ok then
				warn("Halloween BossFX anim: " .. tostring(err))
			end
		end
		stepTelegraphs()
		stepRockFalls(t)
		if digger then
			local ok, err = pcall(stepDigger, dt)
			if not ok then
				warn("Halloween BossFX digger: " .. tostring(err))
				removeDigger(false)
			end
		end
		for _, v in pairs(visuals) do
			if v.Kind == "BossSkeleton" then
				stepSkeleton(v, dt, t)
			elseif v.Kind == "BossMound" then
				stepMound(v, t)
			elseif v.Kind == "CursedRock" then
				stepRock(v, t)
			end
		end
	end)

	-- offline smoke tests (tools/hw_test_wp8.luau) drive the module through these
	BossFX.Debug = {
		Event = onEvent,
		Sync = function()
			syncMode()
			syncTargets()
			syncTethers()
		end,
		Step = function(dt: number)
			stepSequences(dt)
			if boss then
				stepBoss(dt)
			end
			stepTelegraphs()
			stepRockFalls(now())
			stepDigger(dt)
			for _, v in pairs(visuals) do
				if v.Kind == "BossSkeleton" then
					stepSkeleton(v, dt, now())
				elseif v.Kind == "BossMound" then
					stepMound(v, now())
				elseif v.Kind == "CursedRock" then
					stepRock(v, now())
				end
			end
		end,
		Boss = function()
			return boss
		end,
		Visuals = visuals,
		Telegraphs = telegraphs,
		Anim = anim,
		Digger = function()
			return digger
		end,
		CameraLocked = cameraLocked,
		CameraShot = cameraShot,
		Timelines = timelines,
		Flinches = flinches,
		Scatter = scatter,
		Bell = function()
			return bell
		end,
		Soul = function()
			return soul
		end,
		MoonFlare = function()
			return moonFlare
		end,
		Death = function()
			return deathTL
		end,
		StopSequences = stopSequences,
	}

	-- preload the rig the first time the player reaches the pit (no hitch when it rises), joining mid-fight works too
	task.spawn(function()
		while true do
			task.wait(1)
			if Shared.Enabled() and ACTIVE[A("State")] and not boss and inArena() then
				buildBoss()
				syncMode()
			end
		end
	end)
	syncMode()
end

return BossFX
