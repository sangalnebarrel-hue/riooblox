-- BELL SEAL V · CROOKED DOORS · client (StarterPlayerScripts.HalloweenClient.Trials.Doors, WP-J; DESIGN §8.4 item 5,
-- §24.1 presenter contract, §24.2: "door leaves opening (J)").
-- Two layers:
-- * WORLD (boots once: the Trials host's Init / Start, or on its own a moment after it is required; everyone sees it):
--   - the four leaves of Crooked Row's door wall (models Door_i_Leaf, pivot = hinge, OpenAngle x OpenSign): a door creaks
--     open on C2Door "Open" (your opening) / "Swing" (someone else's, nearby), light of the outcome's colour spills out of
--     the doorway, then it creaks shut (DoorHold) with a slam. Refunded openings slam at once.
--   - H13 MOTH SWARM: the hint lamp of the marked door (DoorHintLamp, attribute DoorHint = i) lights up and moths flutter
--     round it (C2Door "Hint" / "State" {Hint}); cleared as soon as you open a door.
--   - a small sign in front of the wall: openings left today (UyDoorsLeft / UyDoorsMax) and the Seal V door outcomes
--     (UySealVProgress, UySealMask), within Seals2Config.Client.DoorSignRadius.
--   - THE DOORKEEPER (Strike kind "UyDoorkeeper"): the walking door (Models.Seals2.Doorkeeper) rises out of the court on
--     its target part, idles, flinches on hits, falls apart when beaten / sinks when the fight ends otherwise. Members of
--     the fight see its telegraphed attacks animated (C2Trial "DoorkeeperAttack") and its stuck window after a SLAM.
--   - THE HIDDEN ROOM (C2Door "Rare" / "Chest" / "RareEnd"): a visit timer over the hoard, chest lids (RareChest_i.Lid,
--     pivot LidHinge, OpenAngle about X) fly open with what the server granted, everything closes again after the visit.
-- * PRESENTER of the two door fights (Ids DoorChallenge, Doorkeeper): banners, the Door Court rim (red while you are
--   outside it: leaving the court fails the challenge), wave names, the Doorkeeper's stuck window, HUD lines.
-- Everything is client-local, pcall'd, and restored / destroyed on Stop or when its record ends (guaranteed teardown);
-- ReducedMotion: doors and lids jump to their poses, no sway, no shakes.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals2View"))

local P = { Ids = { "DoorChallenge", "Doorkeeper" } }

local player = Players.LocalPlayer
local L = View.L
local Cfg = View.Config
local DC = Cfg.Doors
local CC = Cfg.Client
local DK = DC.Doorkeeper
local CH = DC.Challenge
local Layout = View.Layout
local COL = View.Colors
local RGB = Color3.fromRGB
local V3 = Vector3.new
local WHITE = Color3.new(1, 1, 1)
local INK = RGB(16, 12, 26)
local VIOLET = RGB(150, 80, 230)
local VIOLET_HI = RGB(196, 150, 255)
local GOLD = RGB(255, 210, 110)
local BLOOD = RGB(232, 72, 96)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

local WAVES = {
	Stomp = { "STOMP", "ТОПОТ" },
	Cross = { "CROSSFIRE", "ПЕРЕКРЁСТНЫЙ ОГОНЬ" },
	Ripple = { "RIPPLE", "РЯБЬ" },
	Lanes = { "LANES", "ДОРОЖКИ" },
	Finale = { "THE LAST DANCE: FIND THE SAFE PATH", "ПОСЛЕДНИЙ ТАНЕЦ: НАЙДИ БЕЗОПАСНЫЙ ПУТЬ" },
}
local ATTACKS = {
	Slam = { "SLAM", "УДАР" }, Sweep = { "SWEEP", "РАЗМАХ" }, Ring = { "QUAKE", "СОТРЯСЕНИЕ" }, Charge = { "CHARGE", "ТАРАН" },
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

local function cameraNear(pos: Vector3, dist: number): boolean
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - pos).Magnitude <= dist
end

---------------------------------------------------------------------------------------------------------------------
-- world lookups (40_Underyard.CrookedRow; streamed parts may be missing: everything is optional)
---------------------------------------------------------------------------------------------------------------------
local function crooked(): Instance?
	local root = View.Root()
	return root and root:FindFirstChild("CrookedRow") or nil
end

local function modelNamed(name: string, base: Instance?): Model?
	if not base then
		return nil
	end
	local hit = base:FindFirstChild(name, true)
	if hit and hit:IsA("Model") then
		return hit
	end
	for _, d in ipairs(base:GetDescendants()) do
		if d.Name == name and d:IsA("Model") then
			return d
		end
	end
	return nil
end

local function doorPos(i: number): Vector3
	local p = Layout.Crooked.Doors[i] or Layout.Crooked.Doors[1]
	return V3(p.X, 4.5, p.Z + 1)
end

local function courtCentre(): Vector3
	return Layout.Crooked.Court.Centre
end

---------------------------------------------------------------------------------------------------------------------
-- door leaves
---------------------------------------------------------------------------------------------------------------------
local leaves: { [number]: any } = {} -- door -> {Model, Angle, Anim, Token}

local function leafOf(i: number): any
	local rec = leaves[i]
	if rec and rec.Model.Parent then
		return rec
	end
	local m = modelNamed("Door_" .. i .. "_Leaf", crooked())
	if not m then
		return nil
	end
	rec = { Model = m, Angle = 0 }
	leaves[i] = rec
	return rec
end

local function openAngle(m: Model): number
	return math.rad(num(m:GetAttribute("OpenAngle"), DC.OpenAngle)) * num(m:GetAttribute("OpenSign"), -1)
end

local function poseLeaf(rec: any, to: number, seconds: number, done: (() -> ())?)
	if rec.Anim then
		rec.Anim.Stop(false)
		rec.Anim = nil
	end
	local m = rec.Model
	local rest = View.Rest(m)
	if not rest then
		return
	end
	local from = rec.Angle or 0
	rec.Anim = View.Animate(seconds, function(a)
		rec.Angle = from + (to - from) * View.Ease(a)
		View.Pivot(m, rest * CFrame.Angles(0, rec.Angle, 0))
	end, function()
		rec.Anim = nil
		if done then
			done()
		end
	end)
end

local function closeDoor(i: number, fast: boolean?)
	local rec = leafOf(i)
	if not rec then
		return
	end
	rec.Token = nil
	if math.abs(rec.Angle or 0) < 1e-3 then
		return
	end
	poseLeaf(rec, 0, fast and .25 or CC.DoorOpenTime * 1.2, function()
		audio("DoorSlam", doorPos(i), { Volume = fast and 1 or .8 })
		fx("Burst", doorPos(i) - V3(0, 3.5, -1), { Color = RGB(120, 110, 130), Count = 10, Speed = { 3, 7 }, Spread = 60,
			Direction = V3(0, 1, 0), Lifetime = { .5, .9 }, Size = { .8, 1.4, 0 }, Acceleration = V3(0, 2, 0) })
	end)
end

-- a door creaks open (outcome colour pours out), holds, then shuts
local function swing(i: number, outcome: string?, own: boolean)
	local pos = doorPos(i)
	local col = (outcome and COL[outcome]) or VIOLET
	audio("DoorCreak", pos, { Volume = own and 1 or .6 })
	local rec = leafOf(i)
	if rec then
		local token = {}
		rec.Token = token
		poseLeaf(rec, openAngle(rec.Model), CC.DoorOpenTime)
		task.delay(CC.DoorOpenTime + CC.DoorHold, function()
			if rec.Token == token then
				closeDoor(i)
			end
		end)
	end
	if outcome then
		fx("Light", pos + V3(0, 0, -1), col, own and 24 or 16, own and 3 or 2, CC.DoorOpenTime + CC.DoorHold)
		fx("Burst", pos, { Color = col, Color2 = WHITE, Count = own and 28 or 12, Speed = { 5, 12 }, Spread = 45,
			Direction = V3(0, .3, 1), Lifetime = { .6, 1.2 } })
	end
end

---------------------------------------------------------------------------------------------------------------------
-- H13 hint lamp
---------------------------------------------------------------------------------------------------------------------
local hint: any = nil -- {Door, Part, Saved, Light, Cloud}

local function lampOf(i: number): BasePart?
	local base = crooked()
	if not base then
		return nil
	end
	for _, d in ipairs(base:GetDescendants()) do
		if d.Name == "DoorHintLamp" and d:IsA("BasePart") and d:GetAttribute("DoorHint") == i then
			return d
		end
	end
	return nil
end

local function clearHint()
	local h = hint
	hint = nil
	if not h then
		return
	end
	pcall(function()
		if h.Part and h.Saved then
			h.Part.Material = h.Saved.Material
			h.Part.Color = h.Saved.Color
			h.Part.Transparency = h.Saved.Transparency
		end
		if h.Light then
			h.Light:Destroy()
		end
		if h.Cloud then
			h.Cloud.Destroy()
		end
	end)
end

local function setHint(door: number?, announce: boolean)
	door = tonumber(door)
	if hint and hint.Door == door then
		return
	end
	clearHint()
	if not door or door < 1 or door > DC.Count then
		return
	end
	local part = lampOf(door)
	local h: any = { Door = door, Part = part }
	hint = h
	local col = COL.Moth
	local pos = doorPos(door) + V3(0, 6, 1)
	if part then
		local hc = part:GetAttribute("HintColor")
		col = typeof(hc) == "Color3" and hc or GOLD
		pos = part.Position
		h.Saved = { Material = part.Material, Color = part.Color, Transparency = part.Transparency }
		part.Material = Enum.Material.Neon
		part.Color = col
		part.Transparency = 0
		local light = Instance.new("PointLight")
		light.Name = "DOGROTS_DoorHintLight"
		light.Color = col
		light.Range = 16
		light.Brightness = 2.4
		light.Shadows = false
		light.Parent = part
		h.Light = light
	end
	local okCloud, cloud = pcall(View.MothCloud, pos, { Count = 8 })
	h.Cloud = okCloud and cloud or nil
	audio("Moths", pos, { Volume = .8 })
	if announce then
		local from = rootPos()
		if from then
			pcall(View.MothSwarm, from, pos, { Count = 7, Seconds = 2.4, StopShort = 2 })
		end
		View.Toast(ctx, "Your Moth Hound's moths circle door " .. door, "Мотыльки твоей Мотыльковой гончей кружат у двери " .. door, "info")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the sign in front of the wall
---------------------------------------------------------------------------------------------------------------------
local sign: any = nil

local function sealVCleared(): boolean
	local mask = player:GetAttribute("UySealMask")
	return type(mask) == "string" and string.sub(mask, DC.CountsFor, DC.CountsFor) == "1"
end

local function buildSign(): any
	local doors = Layout.Crooked.Doors
	local x = 0
	for _, d in ipairs(doors) do
		x += d.X
	end
	x /= math.max(1, #doors)
	local anchor = Instance.new("Part")
	anchor.Name = "DoorSignAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * .2
	anchor.CFrame = CFrame.new(x, 4.6, Layout.Crooked.WallZ + 2)
	anchor.Parent = View.Folder()
	local gui = Instance.new("BillboardGui")
	gui.Name = "DOGROTS_DoorSign"
	gui.Size = UDim2.fromScale(8.5, 2.6)
	gui.LightInfluence = 0
	gui.MaxDistance = CC.DoorSignRadius
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = anchor
	gui:SetAttribute("NoTranslate", true)
	gui.Parent = anchor
	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = RGB(34, 18, 52)
	card.BackgroundTransparency = .15
	card.BorderSizePixel = 0
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(.12, 0)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = VIOLET
	stroke.Thickness = 2
	stroke.Parent = card
	local function line(name: string, y: number, h: number, col: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(.05, y)
		t.Size = UDim2.fromScale(.9, h)
		t.FontFace = FONT
		t.TextScaled = true
		t.TextColor3 = col
		t.Text = ""
		t:SetAttribute("NoTranslate", true)
		local s = Instance.new("UIStroke")
		s.Color = INK
		s.Thickness = 1.5
		s.Parent = t
		t.Parent = card
		return t
	end
	local s = { Anchor = anchor, Gui = gui, Card = card, Stroke = stroke }
	s.Title = line("Title", .06, .3, VIOLET_HI)
	s.Doors = line("Doors", .38, .28, WHITE)
	s.Seal = line("Seal", .68, .26, RGB(226, 212, 248))
	return s
end

local function refreshSign()
	if not sign then
		return
	end
	local left = num(player:GetAttribute("UyDoorsLeft"), -1)
	local max = num(player:GetAttribute("UyDoorsMax"), 0)
	local progress = num(player:GetAttribute("UySealVProgress"), 0)
	local need = (View.Base.Seals[DC.CountsFor].Activity or {}).Outcomes or 3
	sign.Title.Text = L("CROOKED DOORS", "КРИВЫЕ ДВЕРИ")
	if left < 0 then
		sign.Doors.Text = L("WALK UP TO THE DOORS", "ПОДОЙДИ К ДВЕРЯМ")
		sign.Doors.TextColor3 = WHITE
	elseif left <= 0 then
		sign.Doors.Text = L("NO OPENINGS LEFT · BACK TOMORROW", "ОТКРЫТИЙ НЕ ОСТАЛОСЬ · ПРИХОДИ ЗАВТРА")
		sign.Doors.TextColor3 = RGB(190, 170, 200)
	else
		sign.Doors.Text = L("OPENINGS TODAY", "ОТКРЫТИЙ СЕГОДНЯ") .. ": " .. left .. " / " .. math.max(max, left)
		sign.Doors.TextColor3 = GOLD
	end
	if sealVCleared() then
		sign.Seal.Text = L("SEAL V BROKEN · NEXT CLEAR", "ПЕЧАТЬ V СЛОМАНА · ДО ПОВТОРА") .. ": " .. (progress % need) .. " / " .. need
	else
		sign.Seal.Text = L("SEAL V · DOOR OUTCOMES", "ПЕЧАТЬ V · ИСХОДЫ ДВЕРЕЙ") .. ": " .. math.min(progress, need) .. " / " .. need
	end
end

---------------------------------------------------------------------------------------------------------------------
-- THE DOORKEEPER (every viewer)
---------------------------------------------------------------------------------------------------------------------
local keepers: { [BasePart]: any } = {}

local function keeperById(id: any): any
	id = tonumber(id)
	for part, rec in pairs(keepers) do
		if part:GetAttribute("TargetId") == id then
			return rec
		end
	end
	return nil
end

local function dropKeeper(part: BasePart)
	local rec = keepers[part]
	keepers[part] = nil
	if rec then
		rec.Maid.Clean()
	end
end

-- the keeper falls apart (beaten) or sinks (the fight ended otherwise); the client model is gone after it
local function keeperExit(part: BasePart, reason: any)
	local rec = keepers[part]
	if not rec or rec.Exiting then
		return
	end
	rec.Exiting = true
	local model = rec.Model
	local base = rec.Base or (rec.Part.CFrame - V3(0, DK.Height, 0))
	local pos = base.Position + V3(0, DK.Height, 0)
	if reason == "Broke" then
		audio("ArmorBreak", pos, { Volume = 1 })
		audio("DoorSlam", pos, { Volume = .9, Pitch = .7 })
		fx("Burst", pos, { Color = VIOLET_HI, Color2 = GOLD, Count = 40, Speed = { 10, 22 } })
		fx("Shockwave", base.Position + V3(0, .3, 0), VIOLET, 14, .8)
		local pieces = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local away = (d.Position - pos)
				local dir = away.Magnitude > .01 and away.Unit or V3(0, 1, 0)
				table.insert(pieces, { Part = d, CF = d.CFrame, Vel = dir * (8 + math.random() * 10) + V3(0, 10 + math.random() * 8, 0),
					Spin = V3(math.random() - .5, math.random() - .5, math.random() - .5) * 8 })
			end
		end
		View.Animate(1.4, function(a)
			local t = a * 1.4
			for _, pc in ipairs(pieces) do
				local p = pc.CF.Position + pc.Vel * t + V3(0, -30 * t * t, 0)
				pc.Part.CFrame = CFrame.new(p) * (pc.CF - pc.CF.Position) * CFrame.Angles(pc.Spin.X * t, pc.Spin.Y * t, pc.Spin.Z * t)
				pc.Part.Transparency = math.max(pc.Part.Transparency, a * a)
			end
		end, function()
			dropKeeper(part)
		end)
	else
		audio("BossBurrow", pos, { Volume = .7 })
		fx("Burst", base.Position + V3(0, .5, 0), { Color = RGB(90, 80, 100), Count = 18, Speed = { 4, 9 }, Spread = 70,
			Direction = V3(0, 1, 0) })
		View.Animate(1.1, function(a)
			model:PivotTo(base * CFrame.new(0, -DK.Height * 2.2 * View.Ease(a), 0) * rec.PivotRel)
		end, function()
			dropKeeper(part)
		end)
	end
end

local function addKeeper(part: Instance)
	if not part:IsA("BasePart") or part:GetAttribute("Kind") ~= "UyDoorkeeper" or keepers[part] then
		return
	end
	local maid = View.Maid()
	local okM, model = pcall(View.Models.Doorkeeper, { Lite = View.Quality() == "Low" })
	if not okM or not model then
		return
	end
	model.Parent = View.Folder()
	maid.Give(model)
	local armL, armR = model:FindFirstChild("ArmL"), model:FindFirstChild("ArmR")
	local rec: any = { Part = part, Model = model, Maid = maid, Born = os.clock(), Phase = math.random() * 6, Flash = 0, Lunge = 0,
		-- built on the origin = its ground centre: pivots relative to the ground frame
		PivotRel = model:GetPivot(), ArmL = armL, ArmR = armR, ArmLRel = armL and (armL :: Model):GetPivot() or nil,
		ArmRRel = armR and (armR :: Model):GetPivot() or nil,
		LastHP = num(part:GetAttribute("HP"), 1), Eyes = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "EyeL" or d.Name == "EyeR" or d.Name == "Mouth" or d.Name == "Crack") then
			table.insert(rec.Eyes, { Part = d, Color = d.Color })
		end
	end
	keepers[part] = rec
	local ground = part.Position - V3(0, DK.Height, 0)
	audio("BossEmerge", ground, { Volume = .8 })
	audio("DoorCreak", ground, { Volume = .7, Pitch = .8 })
	fx("Shockwave", ground + V3(0, .3, 0), VIOLET, 12, .9)
	fx("Burst", ground + V3(0, 1, 0), { Color = RGB(110, 96, 120), Color2 = VIOLET, Count = 26, Speed = { 6, 12 }, Spread = 70,
		Direction = V3(0, 1, 0) })
	local reduced = View.Reduced()
	maid.Give(RunService.Heartbeat:Connect(function(dt)
		if rec.Exiting then
			return
		end
		if not part.Parent then
			keeperExit(part, "Fled")
			return
		end
		local pos = part.Position
		if not cameraNear(pos, 260) then
			return
		end
		local now = View.Shared.Now()
		local t = os.clock()
		local look = part.CFrame.LookVector
		local face = V3(look.X, 0, look.Z)
		local atk = rec.Attack
		if atk and typeof(atk.Target) == "Vector3" then
			local d = atk.Target - pos
			if V3(d.X, 0, d.Z).Magnitude > 1 then
				face = V3(d.X, 0, d.Z)
			end
		end
		if face.Magnitude < .01 then
			face = V3(0, 0, -1)
		end
		local g = V3(pos.X, pos.Y - DK.Height, pos.Z)
		rec.Yaw = rec.Yaw or math.atan2(-face.X, -face.Z)
		local want = math.atan2(-face.X, -face.Z)
		local dy = (want - rec.Yaw + math.pi) % (2 * math.pi) - math.pi
		rec.Yaw += dy * math.min(1, dt * 6)
		-- poses
		local rise = math.clamp((t - rec.Born) / .9, 0, 1)
		local lift = reduced and 0 or (1 - View.Ease(rise)) * -DK.Height * 1.6
		local sway = reduced and 0 or math.sin(t * 1.6 + rec.Phase) * .05
		local bob = reduced and 0 or math.sin(t * 3.2 + rec.Phase) * .15
		local pitch, lunge, hop = 0, 0, 0
		local armA, armB = (reduced and 0 or math.sin(t * 1.6 + rec.Phase) * .15), (reduced and 0 or -math.sin(t * 1.6 + rec.Phase) * .15)
		local armYaw = 0
		if atk then
			local tele = math.max(.2, atk.Impact - atk.Start)
			local k = math.clamp((now - atk.Start) / tele, 0, 1) -- wind-up 0..1
			local after = now - atk.Impact -- seconds after impact
			if after > .9 then
				rec.Attack = nil
			elseif atk.Kind == "Slam" then
				if after < 0 then
					armA, armB = -2.4 * View.Ease(k), -2.4 * View.Ease(k)
					pitch = .12 * k
				else
					local s = math.clamp(after / .15, 0, 1)
					armA, armB = -2.4 + 2.9 * s, -2.4 + 2.9 * s
					pitch = .12 - .32 * s
				end
			elseif atk.Kind == "Sweep" then
				if after < 0 then
					armYaw = 1.4 * View.Ease(k)
					armB = -1.2 * k
				else
					local s = math.clamp(after / .25, 0, 1)
					armYaw = 1.4 - 3 * s
					armB = -1.2
				end
			elseif atk.Kind == "Ring" then
				if after < 0 then
					hop = math.sin(k * math.pi * .5) * 2.4 * k
					armA, armB = -1.2 * k, -1.2 * k
				else
					hop = math.max(0, 2.4 - after * 20)
				end
			elseif atk.Kind == "Charge" then
				if after < 0 then
					pitch = -.18 * k
				else
					lunge = math.max(0, 1 - math.abs(after - .2) / .5) * 9
					pitch = .2
				end
			end
		end
		-- stuck after a slam (members know the window; others see it through the attack signal too)
		local stuck = rec.StuckUntil and now < rec.StuckUntil and now >= (rec.StuckFrom or 0)
		local tilt = 0
		if stuck then
			tilt = reduced and .12 or (.16 + math.sin(t * 18) * .03)
		end
		rec.Flash = math.max(0, rec.Flash - dt * 4)
		local body = CFrame.new(g + V3(0, lift + bob + hop, 0)) * CFrame.Angles(0, rec.Yaw, 0) * CFrame.new(0, 0, -lunge)
			* CFrame.Angles(-pitch, 0, sway + tilt)
		if rec.Flash > 0 and not reduced then
			body *= CFrame.new((math.random() - .5) * .3 * rec.Flash, 0, (math.random() - .5) * .3 * rec.Flash)
		end
		rec.Base = CFrame.new(g) * CFrame.Angles(0, rec.Yaw, 0)
		model:PivotTo(body * rec.PivotRel)
		if rec.ArmL and rec.ArmLRel then
			rec.ArmL:PivotTo(body * rec.ArmLRel * CFrame.Angles(armA, -armYaw * .3, 0))
		end
		if rec.ArmR and rec.ArmRRel then
			rec.ArmR:PivotTo(body * rec.ArmRRel * CFrame.Angles(armB, armYaw, 0))
		end
		local glow = stuck and .55 + math.sin(t * 20) * .45 or rec.Flash
		for _, e in ipairs(rec.Eyes) do
			e.Part.Color = e.Color:Lerp(stuck and RGB(120, 220, 255) or WHITE, math.clamp(glow, 0, 1))
		end
	end))
	maid.Give(part:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = num(part:GetAttribute("HP"), 0)
		if hp < rec.LastHP then
			rec.Flash = 1
		end
		rec.LastHP = hp
	end))
	maid.Give(part:GetAttributeChangedSignal("EndReason"):Connect(function()
		keeperExit(part, part:GetAttribute("EndReason"))
	end))
	maid.Give(part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			keeperExit(part, part:GetAttribute("EndReason") or "Fled")
		end
	end))
end

---------------------------------------------------------------------------------------------------------------------
-- THE HIDDEN ROOM
---------------------------------------------------------------------------------------------------------------------
local rare: any = nil -- {Door, Until, Maid, Lids = {[i] = {Model, Angle, Anim}}, Gui, Label}

local function rareRoom(): Model?
	return modelNamed("RareRoom", crooked())
end

local function chestModel(i: number): Model?
	return modelNamed("RareChest_" .. i, rareRoom())
end

local function chestPos(i: number): Vector3
	local m = chestModel(i)
	if m then
		return m:GetPivot().Position
	end
	local off = DC.Rare.Chests[i] or { 0, 3, -6 }
	return Layout.Crooked.RareRoom.Centre + V3(off[1], off[2], off[3])
end

local function lidOf(i: number): any
	local lids = rare and rare.Lids
	if not lids then
		return nil
	end
	local rec = lids[i]
	if rec and rec.Model.Parent then
		return rec
	end
	local chest = chestModel(i)
	local lid = chest and chest:FindFirstChild("Lid")
	if not lid or not lid:IsA("Model") then
		return nil
	end
	rec = { Model = lid, Angle = 0 }
	lids[i] = rec
	return rec
end

local function poseLid(rec: any, to: number, seconds: number)
	if rec.Anim then
		rec.Anim.Stop(false)
	end
	local rest = View.Rest(rec.Model)
	if not rest then
		return
	end
	local from = rec.Angle or 0
	local axis = rec.Model:GetAttribute("OpenAxis") or "X"
	rec.Anim = View.Animate(seconds, function(a)
		local k = a < 1 and View.Ease(a) or 1
		-- a little overshoot on the way up
		if to > from and not View.Reduced() then
			k = math.min(1.08, k + math.sin(a * math.pi) * .08)
		end
		rec.Angle = from + (to - from) * k
		local ang = axis == "Z" and CFrame.Angles(0, 0, rec.Angle) or CFrame.Angles(-rec.Angle, 0, 0)
		View.Pivot(rec.Model, rest * ang)
	end, function()
		rec.Anim = nil
	end)
end

local function rareEnd()
	local r = rare
	if not r then
		return
	end
	rare = nil
	r.Maid.Clean()
	-- the lids close behind the visitor
	for _, rec in pairs(r.Lids) do
		if rec.Model.Parent and math.abs(rec.Angle or 0) > 1e-3 then
			poseLid(rec, 0, .6)
		end
	end
end

local function rareStart(door: number, chests: number, untilAt: number)
	rareEnd()
	local maid = View.Maid()
	local r: any = { Door = door, Until = untilAt, Maid = maid, Lids = {}, Chests = chests, Opened = {} }
	rare = r
	View.Banner(ctx, "THE HIDDEN ROOM", "ТАЙНАЯ КОМНАТА", { Sub = { "Open the three chests", "Открой три сундука" }, Color = COL.Rare,
		Seconds = 3 })
	audio("Teleport", nil, { Volume = .8 })
	audio("TreasureReveal", nil, { Volume = .7 })
	-- the visit timer over the hoard
	local c = Layout.Crooked.RareRoom.Centre
	local anchor = Instance.new("Part")
	anchor.Name = "RareTimerAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * .2
	anchor.CFrame = CFrame.new(c + V3(0, 8.5, -4))
	anchor.Parent = View.Folder()
	maid.Give(anchor)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(9, 1.6)
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.Adornee = anchor
	gui:SetAttribute("NoTranslate", true)
	gui.Parent = anchor
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = FONT
	t.TextScaled = true
	t.TextColor3 = GOLD
	t:SetAttribute("NoTranslate", true)
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = 2
	s.Parent = t
	t.Parent = gui
	r.Label = t
	local function tick()
		local left = math.max(0, math.floor(r.Until - View.Shared.Now() + .5))
		local opened = 0
		for _ in pairs(r.Opened) do
			opened += 1
		end
		t.Text = L("CHESTS", "СУНДУКИ") .. " " .. opened .. " / " .. r.Chests .. "  ·  " .. string.format("%d:%02d", left // 60, left % 60)
	end
	tick()
	task.spawn(function()
		while rare == r do
			pcall(tick)
			task.wait(.5)
		end
	end)
end

local function rareChest(index: number, rewards: any)
	local r = rare
	if not r then
		return
	end
	r.Opened[index] = true
	local pos = chestPos(index)
	local rec = lidOf(index)
	if rec then
		poseLid(rec, math.rad(num(rec.Model:GetAttribute("OpenAngle"), 70)), .55)
	end
	local special = false
	local lines = {}
	for _, row in ipairs(type(rewards) == "table" and rewards or {}) do
		if type(row) == "table" then
			table.insert(lines, View.RewardLine(row))
			if row.Kind == "Find" or row.Kind == "Dog" or row.Kind == "Key" then
				special = true
			end
		end
	end
	audio("CoffinLid", pos, { Volume = .7 })
	audio(special and "RareFind" or "RewardOpen", pos, { Volume = .9 })
	fx("Burst", pos + V3(0, 1, 0), { Color = GOLD, Color2 = WHITE, Count = special and 40 or 24, Speed = { 6, 14 }, Spread = 40,
		Direction = V3(0, 1, 0) })
	fx("Light", pos + V3(0, 2, 0), GOLD, 18, 3, 1.6)
	if special and ctx and ctx.FX and ctx.FX.Beam then
		pcall(ctx.FX.Beam, pos, GOLD, 18, 2.4)
	end
	for k, line in ipairs(lines) do
		task.delay((k - 1) * .35, function()
			fx("Popup", pos + V3(0, 3 + k * .2, 0), line, GOLD, special)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- C2Door signals
---------------------------------------------------------------------------------------------------------------------
local function rewardSummary(rows: any): string?
	local out = {}
	for _, row in ipairs(type(rows) == "table" and rows or {}) do
		if type(row) == "table" then
			table.insert(out, View.RewardLine(row))
		end
	end
	return #out > 0 and table.concat(out, " · ") or nil
end

local function onDoor(d: any)
	local kind = d.Kind
	if kind == "State" then
		if num(d.Left, 0) > 0 and d.Hint then
			setHint(d.Hint, true)
		elseif not d.Hint then
			clearHint()
		end
		refreshSign()
	elseif kind == "Hint" then
		setHint(d.Door or d.Hint, true)
	elseif kind == "Open" then
		clearHint()
		local outcome = d.Outcome
		local door = num(d.Door, 1)
		swing(door, outcome, true)
		local loc = View.Loc().UI
		local title = loc.Outcomes[outcome] or { tostring(outcome), tostring(outcome) }
		local sub = loc.OutcomeLines[outcome]
		if outcome == "Reward" then
			local summary = rewardSummary(d.Rewards)
			sub = summary and { summary, summary } or sub
			audio("RewardOpen", doorPos(door), { Volume = .9 })
		elseif outcome == "MiniBoss" then
			audio("BossRoar", doorPos(door), { Volume = .7, Pitch = 1.25 })
		elseif outcome == "Challenge" then
			audio("HazardWarn", nil, { Volume = .7 })
		elseif outcome == "Rare" then
			audio("RareFind", doorPos(door), { Volume = .8 })
		end
		View.Banner(ctx, title[1], title[2], { Sub = sub, Color = COL[outcome] or VIOLET, Seconds = 3 })
		if d.Counted then
			local need = num(d.Need, 3)
			local p = num(d.Progress, 0)
			local shown = (p > 0 and p % need == 0) and need or p % need
			View.Toast(ctx, "Seal V: " .. shown .. " / " .. need .. " door outcomes", "Печать V: " .. shown .. " / " .. need .. " исходов дверей",
				"success")
		end
		refreshSign()
	elseif kind == "Swing" then
		swing(num(d.Door, 1), d.Outcome, false)
	elseif kind == "Refund" then
		closeDoor(num(d.Door, 1), true)
		refreshSign()
	elseif kind == "Outcome" then
		local need = num(d.Need, 3)
		local p = num(d.Progress, 0)
		if d.Won and d.Counted then
			local shown = (p > 0 and p % need == 0) and need or p % need
			View.Toast(ctx, "The door yields · Seal V: " .. shown .. " / " .. need, "Дверь сдалась · Печать V: " .. shown .. " / " .. need,
				"success")
		elseif d.Won then
			View.Toast(ctx, "The door yields", "Дверь сдалась", "success")
		else
			View.Toast(ctx, "The door won this time: it does not count", "На этот раз победила дверь: исход не засчитан", "info")
		end
		refreshSign()
	elseif kind == "Rare" then
		rareStart(num(d.Door, 1), num(d.Chests, 3), num(d.Until, View.Shared.Now() + DC.Rare.Visit))
	elseif kind == "Chest" then
		rareChest(num(d.Index, 1), d.Rewards)
	elseif kind == "RareEnd" then
		rareEnd()
		View.Toast(ctx, "Back in Crooked Row", "Снова на Кривой улице", "info")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- world boot
---------------------------------------------------------------------------------------------------------------------
local function boot(c: any?)
	if booted then
		return
	end
	booted = true
	ctx = View.Ctx(c)
	if not View.Shared.Chapter2Enabled() then
		return
	end
	View.Bus.On("C2Signal", function(sig)
		if type(sig) == "table" and sig.Kind == "C2Door" and type(sig.Data) == "table" then
			local ok, err = pcall(onDoor, sig.Data)
			if not ok then
				warn("Trials.Doors: " .. tostring(err))
			end
		end
	end)
	for _, part in ipairs(CollectionService:GetTagged("HalloweenTarget")) do
		pcall(addKeeper, part)
	end
	CollectionService:GetInstanceAddedSignal("HalloweenTarget"):Connect(function(part)
		task.defer(function()
			pcall(addKeeper, part)
		end)
	end)
	-- the sign: built lazily near the wall, refreshed by the player's door attributes
	local wall = V3(Layout.Crooked.Court.Centre.X, 0, Layout.Crooked.WallZ)
	for _, a in ipairs({ "UyDoorsLeft", "UyDoorsMax", "UySealVProgress", "UySealMask" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			pcall(refreshSign)
		end)
	end
	player:GetAttributeChangedSignal("UyInZone"):Connect(function()
		if player:GetAttribute("UyInZone") ~= true then
			clearHint()
			if rare then
				rareEnd()
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				local pos = rootPos()
				local near = pos ~= nil and player:GetAttribute("UyInZone") == true
					and V3(pos.X - wall.X, 0, pos.Z - wall.Z).Magnitude <= CC.DoorSignRadius + 20
				if near and not sign then
					sign = buildSign()
					refreshSign()
				elseif not near and sign then
					sign.Anchor:Destroy()
					sign = nil
				end
				if rare and player:GetAttribute("UyRareRoom") == 0 and View.Shared.Now() > rare.Until + 2 then
					rareEnd()
				end
			end)
			if not ok then
				warn("Trials.Doors: " .. tostring(err))
			end
		end
	end)
end
P.Boot = boot

---------------------------------------------------------------------------------------------------------------------
-- presenter (DoorChallenge / Doorkeeper)
---------------------------------------------------------------------------------------------------------------------
local active: any = nil -- {RunId, TrialId, Maid, Wave, Out, Segments, TargetId, StuckUntil}

local function cleanup()
	local a = active
	active = nil
	if a then
		a.Maid.Clean()
	end
end

-- the Door Court rim: neon segments on the cobbles (red while you are outside)
local function buildRim(a: any, centre: Vector3, radius: number)
	local n = View.Detail(40, 28, 18)
	local folder = Instance.new("Folder")
	folder.Name = "DoorCourtRim"
	folder.Parent = View.Folder()
	a.Maid.Give(folder)
	a.Segments = {}
	local arc = 2 * math.pi * radius / n
	for i = 1, n do
		local ang = (i - .5) / n * 2 * math.pi
		local p = Instance.new("Part")
		p.Name = "RimSegment"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = COL.Challenge
		p.Transparency = .35
		p.Size = V3(arc * .62, .12, .45)
		local at = centre + V3(math.cos(ang) * radius, .18, math.sin(ang) * radius)
		p.CFrame = CFrame.lookAt(at, centre + V3(0, .18, 0)) * CFrame.Angles(0, math.pi / 2, 0)
		p.Parent = folder
		table.insert(a.Segments, p)
	end
end

function P.Start(c: any, run: any)
	boot(c)
	ctx = View.Ctx(c)
	cleanup()
	if type(run) ~= "table" then
		return
	end
	local maid = View.Maid()
	local data = type(run.Data) == "table" and run.Data or {}
	local a: any = { RunId = run.RunId, TrialId = run.TrialId, Maid = maid, Wave = nil, Out = false, TargetId = num(data.TargetId, 0),
		StuckUntil = num(data.StaggerUntil, 0) }
	active = a
	if run.TrialId == "DoorChallenge" then
		View.Banner(ctx, "DOOR CHALLENGE", "ИСПЫТАНИЕ ДВЕРИ", { Sub = { "Survive 25 seconds in the Door Court", "Продержись 25 секунд во Дворе дверей" },
			Color = COL.Challenge, Seconds = 3 })
		local centre = typeof(data.Center) == "Vector3" and data.Center or courtCentre()
		local radius = num(data.Radius, CH.Radius)
		local leave = num(data.LeaveRadius, CH.LeaveRadius)
		pcall(buildRim, a, centre, radius)
		local blink = 0
		maid.Give(RunService.Heartbeat:Connect(function(dt)
			local pos = rootPos()
			if not pos then
				return
			end
			local dist = V3(pos.X - centre.X, 0, pos.Z - centre.Z).Magnitude
			local out = dist > radius
			if out and not a.Out then
				View.Toast(ctx, "Back into the Door Court!", "Вернись во Двор дверей!", "warning")
				audio("HazardWarn", nil, { Volume = .6 })
			end
			a.Out = out
			a.Danger = out and math.clamp((dist - radius) / math.max(1, leave - radius), 0, 1) or 0
			blink += dt
			for i, seg in ipairs(a.Segments or {}) do
				local base = out and (.1 + .3 * (.5 + .5 * math.sin(blink * 12 + i))) or (.35 + .2 * math.sin(blink * 3 + i * .4))
				seg.Transparency = View.Reduced() and (out and .1 or .35) or base
				seg.Color = out and BLOOD or COL.Challenge
			end
		end))
	else
		View.Banner(ctx, "THE DOORKEEPER", "ПРИВРАТНИК", { Sub = { "After its SLAM it is stuck: your hits count x2",
			"После УДАРА он застревает: твои удары считаются x2" }, Color = COL.MiniBoss, Seconds = 3.2 })
		audio("BossRoar", typeof(data.Keeper) == "Vector3" and data.Keeper or courtCentre(), { Volume = .8, Pitch = 1.2 })
	end
end

function P.Update(_c: any, run: any)
	local a = active
	if not a or type(run) ~= "table" or run.RunId ~= a.RunId then
		return
	end
	local data = type(run.Data) == "table" and run.Data or {}
	a.TargetId = num(data.TargetId, a.TargetId)
	a.StuckUntil = math.max(a.StuckUntil or 0, num(data.StaggerUntil, 0))
end

function P.Signal(c: any, kind: string, data: any, run: any)
	ctx = View.Ctx(c)
	local a = active
	if type(data) ~= "table" then
		return
	end
	if kind == "DoorWave" then
		if a then
			a.Wave = data.Wave
		end
		if data.Wave == "Finale" then
			local w = WAVES.Finale
			View.Banner(ctx, w[1], w[2], { Color = COL.Challenge, Seconds = 2.2 })
		end
	elseif kind == "DoorkeeperReady" then
		if a then
			a.TargetId = num(data.TargetId, a.TargetId)
		end
	elseif kind == "DoorkeeperAttack" then
		local now = View.Shared.Now()
		local rec = keeperById(data.TargetId or (a and a.TargetId) or (run and run.Data and run.Data.TargetId))
		if not rec then
			for _, r in pairs(keepers) do
				if a and r.Part:GetAttribute("TargetId") == a.TargetId then
					rec = r
				end
			end
		end
		local impact = num(data.ImpactAt, now + 1.3)
		if rec then
			rec.Attack = { Kind = data.Attack, Start = now, Impact = impact, Target = data.Target }
			if data.StaggerUntil then
				rec.StuckFrom, rec.StuckUntil = impact, num(data.StaggerUntil, impact)
			end
		end
		if a and data.StaggerUntil then
			a.StuckFrom, a.StuckUntil = impact, num(data.StaggerUntil, impact)
		end
		local name = ATTACKS[data.Attack or ""]
		local at = typeof(data.Target) == "Vector3" and data.Target or nil
		if name and at then
			fx("Popup", at + V3(0, 5, 0), L(name[1], name[2]) .. "!", COL.MiniBoss, false)
		end
		task.delay(math.max(0, impact - now), function()
			if active ~= a then
				return
			end
			local where = at or courtCentre()
			if data.Attack == "Slam" or data.Attack == "Ring" then
				audio("BossSlam", where, { Volume = .8, Pitch = 1.15 })
				local root = rootPos()
				if root and (root - where).Magnitude < 30 and not View.Reduced() then
					fx("Shake", .35, .3)
				end
			elseif data.Attack == "Charge" then
				audio("BossStep", where, { Volume = .9 })
			else
				audio("DoorCreak", where, { Volume = .6, Pitch = 1.4 })
			end
			if data.StaggerUntil and a then
				local r2 = keeperById(a.TargetId)
				local head = r2 and r2.Part.Position + V3(0, DK.Height * .6, 0) or where + V3(0, 8, 0)
				fx("Popup", head, L("STUCK! HITS x2", "ЗАСТРЯЛ! УДАРЫ x2"), RGB(120, 220, 255), true)
			end
		end)
	end
end

function P.Stop(c: any, run: any, result: any)
	ctx = View.Ctx(c)
	local a = active
	if a and run and run.RunId and a.RunId ~= run.RunId then
		return
	end
	local won = result == "Won" or (type(result) == "table" and (result.Kind == "Won" or result.Result == "Won"))
	if a and a.TrialId == "DoorChallenge" and won then
		local centre = courtCentre()
		fx("Shockwave", centre + V3(0, .3, 0), COL.Challenge, CH.Radius, 1)
	end
	cleanup()
end

function P.HudLines(run: any): { string }?
	local a = active
	if not a then
		return nil
	end
	local now = View.Shared.Now()
	if a.TrialId == "DoorChallenge" then
		local lines = {}
		if a.Out then
			table.insert(lines, L("BACK INTO THE COURT!", "ВЕРНИСЬ ВО ДВОР!"))
		else
			table.insert(lines, L("Stay inside the Door Court", "Оставайся во Дворе дверей"))
		end
		local w = a.Wave and WAVES[a.Wave]
		if w then
			table.insert(lines, L("Wave", "Волна") .. ": " .. L(w[1], w[2]))
		end
		return lines
	end
	local lines = {}
	if a.StuckUntil and now < a.StuckUntil and now >= (a.StuckFrom or 0) then
		table.insert(lines, L("STUCK! Your hits count x2", "ЗАСТРЯЛ! Твои удары считаются x2") .. string.format(" · %.1f", a.StuckUntil - now))
	else
		table.insert(lines, L("Dodge the SLAM, then strike while it is stuck", "Увернись от УДАРА и бей, пока он застрял"))
	end
	local part = View.Target(a.TargetId ~= 0 and a.TargetId or (run and run.Data and run.Data.TargetId))
	if part then
		local hp, max = num(part:GetAttribute("HP"), 0), math.max(1, num(part:GetAttribute("MaxHP"), 1))
		table.insert(lines, L("The Doorkeeper", "Привратник") .. ": " .. math.ceil(hp) .. " / " .. math.ceil(max))
	end
	return lines
end

-- the host may call Init for presenters; otherwise the world layer boots on its own
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
