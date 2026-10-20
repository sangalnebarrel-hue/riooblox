-- DOG RUSH stampede (client only, docs/DOG_RUSH.md). Packs of real dogs (MenuModels clones playing
-- their Run clip) gallop along the district's streets: the DOG EXPRESS lanes, the north end of
-- MainBoulevard, the south garden loop and the open south half of the boulevard. Nothing here is
-- attached to the player: a dog's place is a pure function of the server clock and the event's
-- StartTimestamp (ReplicatedStorage.WorldEvents.DogRush), so every client sees the same pack at the
-- same place. Street heights are sampled once per route sample (no per-frame raycasts).
-- Budgets: at most WorldEventConfig.FX.<quality>.Dogs clones (14 / 8 / 3), only dogs within VIEW studs
-- of the camera are parented and animated (far ones at a lower rate), clones are built lazily one per
-- frame and kept for the whole event. Dust puffs (none on Low), emotion bubbles (pool of 4) and an
-- occasional bark near the camera. One Heartbeat while the event runs; it idles at 4 Hz when no dog
-- is in view. Reduced Motion: no bubbles rising, softer dust.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Tween = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Rush = require(script.Parent.DogRush)
local V = require(script.Parent.WorldEventObjects)

local S = {}
S.View = 180 -- studs from the camera
S.NearAnimate = 90 -- full-rate animation inside this distance
S.DogHeight = 3.4
S.LeaderHeight = 4.4

local C = Color3.fromRGB
local player = Players.LocalPlayer
local EMOTES = { "❤️", "❗", "🎵", "💨", "😆", "⭐", "❤️", "🐾" }
local BARK = "rbxasset://sounds/volume_slider.ogg"

local st: any = nil -- the running stampede

local function reduced(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

------------------------------------------------------------------------------------------------
-- Street heights: one raycast per route sample, once per session (misses keep the street height).
------------------------------------------------------------------------------------------------
local refined: { [string]: { [number]: boolean } } = {} -- samples with a measured height (this session)
local function refineStep(tried: { [string]: { [number]: boolean } }, budget: number): boolean
	local map = workspace:FindFirstChild("DOGROTS_District")
	if not map then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	params.RespectCanCollide = true
	for _, route in ipairs(Rush.RouteList) do
		local known = refined[route.Id]
		if not known then
			known = {}
			refined[route.Id] = known
		end
		local seen = tried[route.Id]
		if not seen then
			seen = {}
			tried[route.Id] = seen
		end
		for i = 1, route.Count do
			if not known[i] and not seen[i] then
				if budget <= 0 then
					return false
				end
				budget -= 1
				seen[i] = true
				local hit = workspace:Raycast(Vector3.new(route.X[i], Rush.StreetY + 6, route.Z[i]), Vector3.new(0, -12, 0), params)
				if hit and hit.Normal.Y > 0.7 and math.abs(hit.Position.Y - Rush.StreetY) <= 2.5 then
					route.Y[i] = hit.Position.Y
					known[i] = true
				end
				-- A miss (street not streamed in here) keeps the street height; the next event retries it.
			end
		end
	end
	return true
end

------------------------------------------------------------------------------------------------
-- Dogs
------------------------------------------------------------------------------------------------
local function sanitize(m: Model)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		elseif d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("ClickDetector") then
			d:Destroy()
		end
	end
end

-- A little flag on the leader's back: pole, cloth and a golden knob (parts of the clone, so the
-- clone's PivotTo carries them; the cloth waves).
local function addFlag(m: Model, box: CFrame, extents: Vector3): any
	local pivot = m:GetPivot()
	local height = extents.Y
	local poleBase = box * CFrame.new(0, height * 0.15, extents.Z * 0.18)
	local poleH = height * 0.95
	local pole = V.Part(m, "RushFlagPole", Vector3.zero, Vector3.new(0.16, poleH, 0.16), C(120, 82, 48))
	pole.CFrame = poleBase * CFrame.new(0, poleH / 2, 0)
	local knob = V.Part(m, "RushFlagKnob", Vector3.zero, Vector3.one * 0.36, C(255, 210, 70), Enum.Material.Neon)
	knob.Shape = Enum.PartType.Ball
	knob.CFrame = poleBase * CFrame.new(0, poleH + 0.12, 0)
	local cloth = V.Part(m, "RushFlag", Vector3.zero, Vector3.new(0.06, height * 0.34, height * 0.5), C(255, 128, 40))
	local clothLocal = CFrame.new(0, poleH - height * 0.2, height * 0.25)
	cloth.CFrame = poleBase * clothLocal
	local stripe = V.Part(m, "RushFlagStripe", Vector3.zero, Vector3.new(0.07, height * 0.08, height * 0.5), C(255, 236, 160), Enum.Material.Neon)
	stripe.CFrame = cloth.CFrame
	return {
		Cloth = cloth,
		Stripe = stripe,
		Local = pivot:ToObjectSpace(poleBase) * CFrame.new(0, poleH - height * 0.2, 0),
		Offset = CFrame.new(0, 0, height * 0.25),
	}
end

local function buildDog(dog: any)
	local folder = RS:FindFirstChild("MenuModels")
	local animModule = RS:FindFirstChild("DogAnimationPlayer")
	if not folder or not animModule then
		dog.Failed = true
		return
	end
	local template = folder:FindFirstChild(dog.Name)
	if not (template and template:IsA("Model")) then
		dog.Failed = true
		return
	end
	local okPlayer, Animator = pcall(require, animModule)
	if not okPlayer then
		dog.Failed = true
		return
	end
	local m = template:Clone()
	sanitize(m)
	if not m:GetAttribute("AnimationBaseScale") then
		m:SetAttribute("AnimationBaseScale", m:GetScale())
	end
	local target = dog.Leader and S.LeaderHeight or S.DogHeight
	local _, size = m:GetBoundingBox()
	if size.Y > 0 and size.X > 0 then
		m:ScaleTo(m:GetScale() * math.min(target / size.Y, target * 1.25 / size.X))
	end
	local box, extents = m:GetBoundingBox()
	dog.Foot = m:GetPivot():PointToObjectSpace(box.Position - Vector3.new(0, extents.Y / 2, 0))
	if dog.Leader then
		dog.Flag = addFlag(m, box, extents)
	end
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	dog.Parts = parts
	dog.Root = m.PrimaryPart or parts[1]
	dog.Model = m
	local okAnim, anim = pcall(Animator.new, m, dog.Name)
	if okAnim and anim then
		local start = workspace:GetServerTimeNow() - dog.Slot * 0.23
		local playing = false
		pcall(function()
			playing = anim:Play("Run", { Looped = true, Speed = 1.1, StartTime = start, FadeTime = 0 })
			if not playing then
				playing = anim:Play("RUN", { Looped = true, Speed = 1.1, StartTime = start, FadeTime = 0 })
			end
			if not playing then
				playing = anim:Play("Walk", { Looped = true, Speed = 1.9, StartTime = start, FadeTime = 0 })
			end
		end)
		if playing then
			dog.Anim = anim
		else
			pcall(function()
				anim:Destroy()
			end)
		end
	end
end

local function setVisible(dog: any, visible: boolean)
	if dog.Visible == visible or not dog.Model then
		return
	end
	dog.Visible = visible
	dog.Model.Parent = visible and st.Folder or nil
	dog.Alpha = nil
end

local function setAlpha(dog: any, alpha: number)
	alpha = math.floor(alpha * 20 + 0.5) / 20
	if dog.Alpha == alpha then
		return
	end
	dog.Alpha = alpha
	local hide = 1 - alpha
	for _, p in ipairs(dog.Parts) do
		p.LocalTransparencyModifier = hide
	end
end

------------------------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------------------------
local function bark(parent: Instance?, pitch: number)
	if not st or st.Sounds >= 3 then
		return
	end
	local function shot(speed: number, volume: number, delay: number)
		task.delay(delay, function()
			if not st then
				return
			end
			local s = Instance.new("Sound")
			s.SoundId = BARK
			s.Volume = volume
			s.PlaybackSpeed = speed
			s.RollOffMinDistance = 10
			s.RollOffMaxDistance = 90
			local distortion = Instance.new("DistortionSoundEffect")
			distortion.Level = 0.45
			distortion.Parent = s
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain = 8
			eq.MidGain = 2
			eq.HighGain = -16
			eq.Parent = s
			s.Parent = (parent and parent.Parent) and parent or SoundService
			st.Sounds += 1
			s.Ended:Once(function()
				s:Destroy()
			end)
			s.Destroying:Once(function()
				if st then
					st.Sounds = math.max(0, st.Sounds - 1)
				end
			end)
			s:Play()
			game:GetService("Debris"):AddItem(s, 2)
		end)
	end
	shot(0.42 * pitch, 0.32, 0)
	shot(0.5 * pitch, 0.28, 0.17)
end

local function makeBubble(folder: Instance): any
	local gui = Instance.new("BillboardGui")
	gui.Name = "RushEmote"
	gui.Size = UDim2.fromScale(2.2, 2.2)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Enabled = false
	gui:SetAttribute("NoTranslate", true)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label:SetAttribute("NoTranslate", true)
	label:SetAttribute("KeepFont", true)
	label.Parent = gui
	gui.Parent = folder
	return { Gui = gui, Label = label, Busy = false }
end

local function emote(dog: any, text: string?)
	if not st or not dog.Visible or not dog.Root then
		return
	end
	local bubble = nil
	for _, b in ipairs(st.Bubbles) do
		if not b.Busy then
			bubble = b
			break
		end
	end
	if not bubble then
		return
	end
	bubble.Busy = true
	local gui, label = bubble.Gui, bubble.Label
	gui.Adornee = dog.Root
	label.Text = text or EMOTES[math.random(1, #EMOTES)]
	label.TextTransparency = 0
	local top = dog.Leader and 3.6 or 2.9
	gui.StudsOffsetWorldSpace = Vector3.new(0, top, 0)
	gui.Enabled = true
	local life = 1.3
	if reduced() then
		Tween:Create(label, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	else
		gui.Size = UDim2.fromScale(0.6, 0.6)
		Tween:Create(gui, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(2.2, 2.2) }):Play()
		Tween:Create(gui, TweenInfo.new(life, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, top + 1.8, 0) }):Play()
		Tween:Create(label, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	end
	task.delay(life + 0.05, function()
		gui.Enabled = false
		gui.Adornee = nil
		bubble.Busy = false
	end)
end

local function makeDust(folder: Instance): any
	local anchor = V.Part(folder, "RushDust", Vector3.new(0, -500, 0), Vector3.one, C(214, 190, 150))
	anchor.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(C(222, 200, 160), C(190, 165, 130))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.9, 1.6)
	e.Speed = NumberRange.new(1.5, 4)
	e.SpreadAngle = Vector2.new(70, 20)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Drag = 2
	e.LightEmission = 0.05
	e.Rate = 0
	e.Parent = anchor
	return { Part = anchor, Emitter = e }
end

------------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------------
local function qualityLevel(budget: any): number
	local dogs = budget and budget.Dogs or 8
	return dogs >= 14 and 3 or dogs >= 8 and 2 or 1
end

local function update()
	local s = st
	if not s then
		return
	end
	local clock = os.clock()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- Refine street heights a little at a time until every streamed sample is known.
	if not s.Refined then
		s.Refined = refineStep(s.Tried, 60)
	end
	if clock < s.SleepUntil then
		return
	end
	s.Frame += 1
	local now = workspace:GetServerTimeNow()
	local elapsed = now - s.Start
	local camPos = camera.CFrame.Position
	local arrival = math.clamp((clock - s.Born) / 2.5, 0, 1)
	local departure = s.Ending and math.clamp((clock - s.Ending) / 4, 0, 1) or 0
	local alpha = arrival * (1 - departure)
	local anyVisible = false
	local built = false
	local view, near = S.View, S.NearAnimate
	local surging = Rush.Surging(elapsed)
	for _, pack in ipairs(s.Packs) do
		local route, lead = Rush.PackDistance(pack.Index, now, s.Start)
		local packVisible = false
		local packNear = math.huge
		for _, dog in ipairs(pack.Dogs) do
			local lateral, back = Rush.Slot(dog.Slot, now)
			local x, y, z, tx, tz = Rush.Sample(route, lead + back)
			x, z = x - tz * lateral, z + tx * lateral
			local dx, dy, dz = x - camPos.X, y - camPos.Y, z - camPos.Z
			local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
			if dist <= view and alpha > 0 and not dog.Failed then
				if not dog.Model and not built then
					built = true
					buildDog(dog)
				end
				if dog.Model then
					setVisible(dog, true)
					packVisible = true
					anyVisible = true
					packNear = math.min(packNear, dist)
					local far = dist > near
					-- Far dogs move every other frame and animate at 15 Hz.
					if not far or (s.Frame + dog.Slot) % 2 == 0 then
						local at = Vector3.new(x, y, z)
						local frame = CFrame.lookAt(at, at + Vector3.new(tx, 0, tz)) * CFrame.new(-dog.Foot)
						dog.Model:PivotTo(frame)
						if dog.Flag then
							local wave = reduced() and 0 or math.sin(now * (surging and 14 or 9) + dog.Slot) * 0.35
							local cf = dog.Model:GetPivot() * dog.Flag.Local * CFrame.Angles(0, wave, 0) * dog.Flag.Offset
							dog.Flag.Cloth.CFrame = cf
							dog.Flag.Stripe.CFrame = cf
						end
					end
					if dog.Anim and (not far or clock - (dog.LastStep or 0) >= 1 / 15) then
						dog.LastStep = clock
						dog.Anim:Step(now)
					end
					setAlpha(dog, alpha * math.clamp((view - dist) / 15, 0, 1))
				end
			else
				setVisible(dog, false)
			end
		end
		-- Dust behind the pack while it is in view.
		if pack.Dust then
			if packVisible then
				local x, y, z = Rush.Sample(route, lead - 7)
				pack.Dust.Part.Position = Vector3.new(x, y + 0.4, z)
				pack.Dust.Emitter.Rate = (surging and 26 or 14) * alpha * (reduced() and 0.5 or 1)
			else
				pack.Dust.Emitter.Rate = 0
			end
		end
		-- An occasional bark when the pack runs past the camera.
		if packVisible and packNear < 40 and clock >= (pack.NextBark or 0) then
			pack.NextBark = clock + math.random(55, 90) / 10
			bark(pack.Dogs[1].Root, 0.9 + math.random() * 0.25)
		end
	end
	-- Emotions: a bubble over a random dog in view every couple of seconds.
	if anyVisible and clock >= s.NextEmote and not s.Ending then
		s.NextEmote = clock + (surging and 0.5 or 1.4 + math.random() * 1.2)
		local candidates = {}
		for _, pack in ipairs(s.Packs) do
			for _, dog in ipairs(pack.Dogs) do
				if dog.Visible and dog.Root and (dog.Root.Position - camPos).Magnitude < 75 then
					table.insert(candidates, dog)
				end
			end
		end
		if #candidates > 0 then
			emote(candidates[math.random(1, #candidates)])
		end
	end
	if not anyVisible and not built then
		-- Nothing in view: check again in a quarter of a second.
		s.SleepUntil = clock + 0.25
	end
	if s.Ending and departure >= 1 then
		for _, pack in ipairs(s.Packs) do
			for _, dog in ipairs(pack.Dogs) do
				setVisible(dog, false)
			end
		end
	end
end

function S.Begin(def: any, state: any, budget: any)
	S.Stop()
	if not def or def.Id ~= Rush.EventId then
		return
	end
	local start = tonumber(state and state.StartTimestamp) or workspace:GetServerTimeNow()
	local folder = Instance.new("Folder")
	folder.Name = "DOGROTS_DogRushStampede"
	folder.Parent = workspace
	local level = qualityLevel(budget)
	local budgetDogs = math.min(14, budget and budget.Dogs or 8)
	local packs = {}
	for _, row in ipairs(Rush.PacksFor(level, budgetDogs)) do
		local pack = { Index = row.Index, Dogs = {} }
		local names = { row.Pack.Leader }
		for _, n in ipairs(row.Pack.Dogs) do
			table.insert(names, n)
		end
		for slot = 1, row.Size do
			table.insert(pack.Dogs, { Name = names[slot], Slot = slot, Leader = slot == 1, Visible = false })
		end
		if level >= 2 then
			pack.Dust = makeDust(folder)
		end
		table.insert(packs, pack)
	end
	st = {
		Def = def,
		Start = start,
		Folder = folder,
		Packs = packs,
		Born = os.clock(),
		Ending = nil,
		SleepUntil = 0,
		Frame = 0,
		NextEmote = os.clock() + 2,
		Bubbles = {},
		Sounds = 0,
		Refined = false,
		Tried = {},
	}
	for _ = 1, (level >= 2 and 4 or 2) do
		table.insert(st.Bubbles, makeBubble(folder))
	end
	st.Connection = Run.Heartbeat:Connect(update)
end

-- The event's signature moment (ALPHA STAMPEDE): the packs already sprint by the clock (DogRush.Distance);
-- this adds the cheering: bubbles over the dogs in view and a burst of dust.
function S.Surge(_duration: number?)
	local s = st
	if not s then
		return
	end
	s.SleepUntil = 0
	local shown = 0
	for _, pack in ipairs(s.Packs) do
		if pack.Dust and pack.Dust.Emitter.Rate > 0 then
			pack.Dust.Emitter:Emit(reduced() and 8 or 24)
		end
		for _, dog in ipairs(pack.Dogs) do
			if dog.Visible and shown < #s.Bubbles then
				shown += 1
				emote(dog, dog.Leader and "❗" or "❤️")
			end
		end
		if pack.Dogs[1] and pack.Dogs[1].Visible then
			bark(pack.Dogs[1].Root, 1.1)
		end
	end
	s.NextEmote = os.clock() + 0.6
end

-- World position of the pack leader nearest to the camera (nil when the stampede is not running).
function S.LeaderPosition(): Vector3?
	local s = st
	if not s then
		return nil
	end
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local now = workspace:GetServerTimeNow()
	local best, bestDist = nil, math.huge
	for _, pack in ipairs(s.Packs) do
		local route, lead = Rush.PackDistance(pack.Index, now, s.Start)
		local x, y, z = Rush.Sample(route, lead)
		local at = Vector3.new(x, y, z)
		local dist = (at - camPos).Magnitude
		if dist < bestDist then
			best, bestDist = at, dist
		end
	end
	return best
end

function S.Running(): boolean
	return st ~= nil
end

function S.End()
	if st and not st.Ending then
		st.Ending = os.clock()
		st.SleepUntil = 0
	end
end

function S.Stop()
	local s = st
	if not s then
		return
	end
	st = nil
	if s.Connection then
		s.Connection:Disconnect()
	end
	for _, pack in ipairs(s.Packs) do
		for _, dog in ipairs(pack.Dogs) do
			if dog.Anim then
				pcall(function()
					dog.Anim:Destroy()
				end)
			end
			if dog.Model then
				dog.Model:Destroy()
			end
		end
	end
	s.Folder:Destroy()
end

return S
