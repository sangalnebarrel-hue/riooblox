-- CHAPTER II ONBOARDING · the ghost-dog guide (StarterPlayerScripts.HalloweenClient.Chapter2Guide, WP-H2; DESIGN §9
-- "Chapter II onboarding", §18). The server owns the steps (p.Underyard.Tutorial, player attribute UyTutorial: 0 = not
-- started, 1..6 = the step, -1 = done or skipped; Chapter2Config.Tutorial.Steps); this module shows them in the Underyard:
--   * THE GHOST PUP: a spectral Bell Pup with its lantern (a clone of ReplicatedStorage.MenuModels.HW_BellPup made
--     translucent with a moon-blue glow, animated by DogAnimationPlayer; AmbientFX's ghost dog when the template is
--     missing) floats a few studs ahead of the player along the way to the step's target (UnderyardRuntime.GuidePath:
--     round the bell tower, through the district gate), waits for a player who falls behind and circles the target
--     once the player is there
--   * the way: flowing violet chevrons on the ground, a marker over the target (step name + distance + bouncing arrow),
--     a Highlight on the target model (the hand-bell, the coffin shrine, the Mourner, Altar I), and a short camera
--     focus on it when a step begins (HalloweenClient.Cinema: refused while busy / a menu / mining; ReducedMotion = cuts)
--   * the CARD (own ScreenGui DOGROTS_Chapter2Guide, DisplayOrder 46, bottom centre, phone-safe): GHOST GUIDE · STEP n/6,
--     the step's title and text (Chapter2Config), a hint and a tip (UnderyardRuntime.GuideSteps), the step's progress
--     (Bell Shards earned / coffins opened), SHOW ME (focus + bark again), SKIP GUIDE (tap twice: C2Tutorial {Skip}),
--     a collapse button (a small pill keeps the step visible); the final card when the six steps are done
--   * step helpers: the practice ring step asks the server to check (C2Tutorial {Step = 4}) once the player stands in the
--     ring; a counted step that is satisfied but not advanced asks again after Guide.AutoCheck s; a failed / abandoned
--     practice trial shows "try again" on the card
--   * the two practice trials' BEGIN TRIAL prompts (Chapter2Tutorial's own, attribute UyTutorialTrial) are shown only
--     to a player on that step who is not in a trial (prompt.Enabled; ProximityPromptService is never touched)
-- Robustness: everything world-side is client-only and rebuilt on demand; the update runs in pcall at 20 Hz; the card is
-- hidden while a menu / modal / cinematic / HIDE UI / mining session / trial / the main tutorial owns the screen (the
-- world guidance stays, nothing is input-sinking: only the card's buttons are Active); requests time out after
-- Guide.Request s and never block the loop; leaving the zone hides everything, a respawn rebinds; the guide never
-- holds the camera or the controls itself (the focus is a Cinema shot with its guaranteed restore).
-- API: Chapter2Guide.Start(ctx) · .Stop() · .Step() -> current step · .ShowMe() · .State() (tests)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local G = {}
local player = Players.LocalPlayer
local C3 = Color3.fromRGB
local V3 = Vector3.new
local CF = CFrame.new
local WHITE = Color3.new(1, 1, 1)
local INK = C3(16, 12, 26)
local GLASS = C3(30, 18, 48)
local VIOLET = C3(170, 120, 255)
local VIOLET_HI = C3(205, 175, 255)
local MOON = C3(150, 200, 255)
local GOLD = C3(255, 206, 110)
local GREEN = C3(120, 255, 140)
local MUTED = C3(196, 186, 220)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local BODY = Font.fromEnum(Enum.Font.GothamMedium)
local LAYER = "DOGROTS_Chapter2Guide"
local STEP_OF_TRIAL = { Toll = 2, Mourner = 5 }

local started = false
local warned: { [string]: boolean } = {}
local stopFn: (() -> ())? = nil
local stateFn: (() -> any)? = nil
local showFn: (() -> ())? = nil

function G.Stop()
	if stopFn then
		(stopFn :: () -> ())()
	end
end
function G.State(): any
	return stateFn and (stateFn :: () -> any)() or {}
end
function G.Step(): number
	return math.floor(tonumber(player:GetAttribute("UyTutorial")) or 0)
end
function G.ShowMe()
	if showFn then
		(showFn :: () -> ())()
	end
end

function G.Start(ctx: any)
	if started then
		return
	end
	local Shared, Bus, FX, Audio = ctx.Shared, ctx.Bus, ctx.FX, ctx.Audio
	if not (Shared and Shared.Chapter2Enabled()) then
		return
	end
	local okR, R = pcall(function()
		return require(RS:WaitForChild("Halloween"):WaitForChild("UnderyardRuntime")) :: any
	end)
	local okC, Cfg2 = pcall(function()
		return require(RS.Halloween:WaitForChild("Chapter2Config")) :: any
	end)
	if not (okR and type(R) == "table" and okC and type(Cfg2) == "table") then
		warn("Chapter2Guide: UnderyardRuntime / Chapter2Config missing")
		return
	end
	started = true
	local Layout = R.Layout
	local GC = R.Config.Guide
	local Steps = Cfg2.Tutorial.Steps
	local TOTAL = #Steps
	local Loc: any = nil
	pcall(function()
		local folder = RS:FindFirstChild("Localization")
		local mod = folder and folder:FindFirstChild("UnderyardFX")
		Loc = mod and require(mod) :: any
	end)
	local function T(en: string): string
		if Shared.IsRussian() and Loc and Loc.UI then
			return Loc.UI[en] or en
		end
		return en
	end
	local function pair(p: any): string
		if type(p) == "table" then
			return Shared.L(p[1] or "", p[2])
		end
		return tostring(p or "")
	end
	local function CS(): any
		return ctx.Modules and ctx.Modules.Chapter2State
	end
	local function serverNow(): number
		local ok, t = pcall(function()
			return workspace:GetServerTimeNow()
		end)
		return ok and t or os.clock()
	end

	local conns: { RBXScriptConnection } = {}
	local busConns: { any } = {}
	local alive = true
	local world = Instance.new("Folder")
	world.Name = "Chapter2Guide"
	world.Parent = FX.Folder()

	---------------------------------------------------------------------------------------------------------------
	-- state
	---------------------------------------------------------------------------------------------------------------
	local st: any = {
		Step = 0, Shown = {}, Focused = {}, Collapsed = false, CollapseAt = 0, SkipArmed = 0, Busy = false, Final = nil,
		WasActive = false, TrialFail = nil, RingSince = nil, SatisfiedSince = nil, AskedAt = -1e9, PupMode = "Lead",
		Target = nil, TargetName = "", Path = {}, PathAt = -1e9, Hidden = true, CardShown = false,
	}
	local function mainGui(): any
		local pg = player:FindFirstChildOfClass("PlayerGui")
		return pg and pg:FindFirstChild("ScreenGui")
	end
	local function attr(name: string): any
		local g = mainGui()
		return g and g:GetAttribute(name)
	end
	local function serverStep(): number
		return math.floor(tonumber(player:GetAttribute("UyTutorial")) or 0)
	end
	local function inZone(): boolean
		return player:GetAttribute("UyInZone") == true
	end
	local function inTrial(): string
		local t = player:GetAttribute("UyTrial")
		return type(t) == "string" and t or ""
	end
	local function rootPart(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if r and r:IsA("BasePart") and hum and hum.Health > 0 then
			return r
		end
		return nil
	end
	-- the card is off while something else owns the screen (the world guidance stays)
	local function cardBlocked(): boolean
		if attr("OpenMenu") ~= nil or (tonumber(attr("ModalOwnerCount")) or 0) > 0 then
			return true
		end
		if attr("UIHidden") == true or attr("CinemaActive") == true or attr("MiningActive") == true then
			return true
		end
		if player:GetAttribute("TutorialActive") == true or inTrial() ~= "" then
			return true
		end
		return false
	end
	local function defOf(step: number): any
		return Steps[step]
	end
	local function guideOf(def: any): any
		return def and R.GuideSteps[def.Key] or nil
	end
	local function view(): any
		local cs = CS()
		local ok, v = pcall(function()
			return cs and cs.View and cs.View()
		end)
		return ok and v or nil
	end

	-- requests: never block the loop (Guide.Request s timeout)
	local function request(action: string, args: any): (boolean, any)
		local cs = CS()
		if not (cs and cs.Request) then
			return false, "Not ready"
		end
		local done, ok, res = false, false, "Timeout"
		task.spawn(function()
			local a, b = cs.Request(action, args)
			if not done then
				done, ok, res = true, a == true, b
			end
		end)
		local t0 = os.clock()
		while not done and os.clock() - t0 < GC.Request do
			task.wait(.1)
		end
		done = true
		return ok, res
	end

	---------------------------------------------------------------------------------------------------------------
	-- targets
	---------------------------------------------------------------------------------------------------------------
	local function uyRoot(): Instance?
		local d = workspace:FindFirstChild("DOGROTS_District")
		return d and d:FindFirstChild("40_Underyard")
	end
	local function square(): Instance?
		local r = uyRoot()
		return r and r:FindFirstChild("BellSquare")
	end
	local function anchorPos(name: string): Vector3
		local part = Layout.AnchorPart(name)
		if part then
			return part.Position
		end
		return Layout.Anchor(name) or Layout.Centre
	end
	local function myEchoes(): { BasePart }
		local out = {}
		for _, p in ipairs(CollectionService:GetTagged("HalloweenTarget")) do
			if p:IsA("BasePart") and p.Parent and p:GetAttribute("Kind") == "UyTutorialEcho" and p:GetAttribute("OwnerUserId") == player.UserId
				and p:GetAttribute("EndReason") == nil then
				table.insert(out, p)
			end
		end
		return out
	end
	local function dummyApi(): any
		local fx = ctx.Modules and ctx.Modules.UnderyardFX
		local ok, h = pcall(function()
			return fx and fx.Mourner and fx.Mourner()
		end)
		return ok and h or nil
	end
	-- -> position, highlight model?, ground point (the chevrons end there), label
	local function targetOf(def: any, from: Vector3): (Vector3, Instance?, string)
		local gs = guideOf(def)
		local kind = gs and gs.Target or "Ring"
		local sq = square()
		if kind == "Echo" then
			local best, bestD = nil, math.huge
			for _, p in ipairs(myEchoes()) do
				local d = (p.Position - from).Magnitude
				if d < bestD then
					best, bestD = p, d
				end
			end
			if best then
				return best.Position, nil, T("ECHO")
			end
			local bestA, bestAD = anchorPos("TutorialEcho_1"), math.huge
			for _, name in ipairs(gs.Anchors) do
				local p = anchorPos(name)
				local d = (p - from).Magnitude
				if d < bestAD then
					bestA, bestAD = p, d
				end
			end
			return bestA + V3(0, 1.6, 0), nil, T("ECHO")
		elseif kind == "HandBell" then
			local ring = sq and sq:FindFirstChild("PracticeRing")
			return anchorPos("TutorialBell") + V3(0, 1, 0), ring and ring:FindFirstChild("HandBell"), T("HAND-BELL")
		elseif kind == "Coffin" then
			return anchorPos("CoffinShrine"), sq and sq:FindFirstChild("CoffinShrine"), T("BLACK COFFIN")
		elseif kind == "Mourner" then
			local d = dummyApi()
			local model = d and d.Model and d.Model() or nil
			return anchorPos("Mourner") + V3(0, 1.4, 0), model, T("THE MOURNER")
		elseif kind == "Altar" then
			local altars = sq and sq:FindFirstChild("SealAltars")
			return anchorPos("SealAltar_1"), altars and altars:FindFirstChild("SealAltar_1"), T("ALTAR I")
		end
		return Layout.Square.PracticeRing.Centre + V3(0, 1, 0), nil, T("PRACTICE RING")
	end

	-- the way there: through the district's gate when the player is out of Bell Square, round the tower inside it
	local function wayTo(from: Vector3, to: Vector3): { Vector3 }
		local district = Layout.District(from) or "BellSquare"
		local gate = Layout.Gates[district]
		if district ~= "BellSquare" and gate then
			local g = gate.Position + V3(0, from.Y - gate.Position.Y, 0)
			local a = R.GuidePath(from, g)
			local b = R.GuidePath(g, to)
			for i = 2, #b do
				table.insert(a, b[i])
			end
			return a
		end
		return R.GuidePath(from, to)
	end

	---------------------------------------------------------------------------------------------------------------
	-- the ghost pup
	---------------------------------------------------------------------------------------------------------------
	local pup: any = nil -- {Model, Root?, Rig?, Anim?, Pos, Vel, Yaw, Light, Fade, Kind}
	local DogRig: any, AnimPlayer: any = nil, nil
	pcall(function()
		DogRig = require(RS:WaitForChild("DogRig", 5) :: ModuleScript)
		AnimPlayer = require(RS:WaitForChild("DogAnimationPlayer", 5) :: ModuleScript)
	end)
	local PUP_ID = "HW_BellPup"
	local function spectral(model: Instance)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CastShadow = false
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
				if d.Transparency < 1 then
					d.Transparency = math.max(d.Transparency, .35)
				end
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = math.max(d.Transparency, .4)
			elseif d:IsA("Light") then
				d.Enabled = false
			end
		end
	end
	local function buildPup(at: Vector3): any
		local menu = RS:FindFirstChild("MenuModels")
		local template = menu and menu:FindFirstChild(PUP_ID)
		local p: any = { Pos = at + V3(0, GC.Pup.Height, 0), Vel = Vector3.zero, Yaw = 0, Fade = 1, Clip = nil }
		if template and template:IsA("Model") and DogRig then
			local model = template:Clone()
			local ok = pcall(function()
				DogRig.Prepare(model, V3(3.2, 2.8, 4.2))
			end)
			if ok then
				spectral(model)
				model.Name = "UyGhostPup"
				model.Parent = world
				p.Model = model
				p.Kind = "Dog"
				if AnimPlayer then
					pcall(function()
						p.Anim = AnimPlayer.new(model, PUP_ID)
					end)
				end
			else
				model:Destroy()
			end
		end
		if not p.Model then
			local Ambient = ctx.Modules and ctx.Modules.AmbientFX
			local okG, rig = pcall(function()
				return Ambient and Ambient.Models and Ambient.Models.Ghost(world, { Color = C3(190, 225, 255), Core = MOON })
			end)
			if okG and rig then
				p.Rig = rig
				p.Model = rig.Model
				p.Kind = "Ghost"
			end
		end
		if not p.Model then
			return nil
		end
		local hl = Instance.new("Highlight")
		hl.Name = "PupGlow"
		hl.FillColor = C3(150, 215, 255)
		hl.OutlineColor = C3(220, 245, 255)
		hl.FillTransparency = .55
		hl.OutlineTransparency = .1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = p.Model
		p.Highlight = hl
		-- the lantern's glow: one light, moon blue
		local anchorPart = p.Model.PrimaryPart or p.Model:FindFirstChildWhichIsA("BasePart", true)
		if anchorPart and Shared.Quality() ~= "Low" then
			local l = Instance.new("PointLight")
			l.Color = MOON
			l.Range = 12
			l.Brightness = 1.3
			l.Shadows = false
			l.Parent = anchorPart
			p.Light = l
		end
		return p
	end
	local function playClip(p: any, name: string)
		if p.Anim and p.Clip ~= name then
			local ok, clip = pcall(function()
				return AnimPlayer.ResolveName(PUP_ID, name) or AnimPlayer.ResolveName(PUP_ID, "Idle")
			end)
			if ok and clip then
				pcall(function()
					p.Anim:Play(clip, { Looped = true })
				end)
			end
			p.Clip = name
		end
	end
	local function poofAt(pos: Vector3, big: boolean?)
		pcall(function()
			FX.Smoke(pos, C3(210, 240, 255), big and 4 or 2.6, 1.2)
			FX.Burst(pos, { Color = MOON, Color2 = VIOLET_HI, Count = big and 26 or 14, Speed = { 2, 7 }, Lifetime = { .5, 1.1 }, Size = { .3, .5, 0 } })
		end)
	end
	local function bark(pos: Vector3)
		pcall(Audio.Play, "GhostDogBark", pos, { Volume = .55, Pitch = 1.25 })
	end
	local function dropPup(poof: boolean)
		if not pup then
			return
		end
		local p = pup
		pup = nil
		if poof then
			poofAt(p.Pos, true)
		end
		pcall(function()
			if p.Rig then
				p.Rig:Destroy()
			else
				p.Model:Destroy()
			end
		end)
	end
	local function placePup(p: any, cf: CFrame)
		if p.Rig then
			local pose = nil
			pcall(function()
				local Ambient = ctx.Modules.AmbientFX
				pose = Ambient.Models.GhostPose(os.clock(), 0)
			end)
			p.Rig:Update(cf * CF(0, -1.5, 0), pose)
		elseif DogRig then
			DogRig.Place(p.Model, cf.Position, cf - cf.Position)
			if p.Anim then
				pcall(function()
					p.Anim:Step(serverNow())
				end)
			end
		end
	end

	local function pupStep(dt: number, me: Vector3, target: Vector3)
		if not pup then
			pup = buildPup(me + V3(2, 0, 2))
			if not pup then
				return
			end
			poofAt(pup.Pos, true)
			bark(pup.Pos)
		end
		local p = pup
		local goal, mode = R.PupGoal(st.Path, me, target, os.clock(), V3(p.Pos.X, me.Y, p.Pos.Z))
		st.PupMode = mode
		local want = V3(goal.X, math.max(goal.Y, Layout.Floor) + GC.Pup.Height, goal.Z)
		-- critically damped follow with a speed cap (smooth, never teleports across the plaza except when far off)
		local delta = want - p.Pos
		if delta.Magnitude > 120 then
			p.Pos = want
			p.Vel = Vector3.zero
			poofAt(want)
		else
			local k = 6
			local acc = delta * k * k - p.Vel * 2 * k
			p.Vel += acc * dt
			if p.Vel.Magnitude > GC.Pup.Speed then
				p.Vel = p.Vel.Unit * GC.Pup.Speed
			end
			p.Pos += p.Vel * dt
		end
		local bob = Shared.ReducedMotion() and 0 or math.sin(os.clock() * 2.2) * .35
		-- facing: along its flight, at the player while waiting, at the target while circling
		local look = p.Vel
		if mode == "Wait" then
			look = me - p.Pos
		elseif mode == "Circle" or look.Magnitude < .8 then
			look = (mode == "Circle" and target or me) - p.Pos
		end
		look = V3(look.X, 0, look.Z)
		if look.Magnitude > .1 then
			local yaw = math.atan2(-look.X, -look.Z)
			local diff = ((yaw - p.Yaw + math.pi) % (2 * math.pi)) - math.pi
			p.Yaw += diff * math.min(1, dt * 5)
		end
		local speed = p.Vel.Magnitude
		playClip(p, speed > 10 and "Run" or speed > 2.5 and "Walk" or "Idle")
		placePup(p, CF(p.Pos + V3(0, bob, 0)) * CFrame.Angles(0, p.Yaw, 0))
	end

	---------------------------------------------------------------------------------------------------------------
	-- the way on the ground, the marker, the highlight
	---------------------------------------------------------------------------------------------------------------
	local chevrons: { BasePart } = {}
	local function chevronPart(): BasePart
		local p = Instance.new("Part")
		p.Name = "GuideChevron"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size = V3(1.6, .06, .5)
		p.Material = Enum.Material.Neon
		p.Color = VIOLET
		p.Transparency = .25
		p.Parent = world
		return p
	end
	local function clearWay()
		for _, c in ipairs(chevrons) do
			c:Destroy()
		end
		table.clear(chevrons)
	end
	local function wayStep(show: boolean)
		if not show or #st.Path < 2 then
			for _, c in ipairs(chevrons) do
				c.Transparency = 1
			end
			return
		end
		local len = R.PathLength(st.Path)
		local stepLen = GC.Arrow.Step
		local maxN = math.floor(GC.Arrow.Max / stepLen)
		if Shared.Quality() == "Low" then
			maxN = math.floor(maxN * .6)
		end
		local offset = Shared.ReducedMotion() and 0 or (os.clock() * GC.Arrow.Speed) % stepLen
		local n = 0
		local from = 3.5
		local stopAt = len - 3
		for k = 0, maxN - 1 do
			local d = from + k * stepLen + offset
			if d > stopAt then
				break
			end
			n += 1
			local c = chevrons[n]
			if not c then
				c = chevronPart()
				chevrons[n] = c
			end
			local pos, dir = R.PathPoint(st.Path, d)
			local ground = V3(pos.X, Layout.Floor + .16, pos.Z)
			local flat = V3(dir.X, 0, dir.Z)
			flat = flat.Magnitude > .01 and flat.Unit or V3(0, 0, -1)
			local base = CFrame.lookAt(ground, ground + flat)
			-- a chevron = this bar, tilted; alternate sides read as ">" pairs along the way
			local side = (n % 2 == 0) and 1 or -1
			c.CFrame = base * CFrame.Angles(0, side * math.rad(38), 0) * CF(side * .42, 0, 0)
			local fade = math.clamp(d / 6, 0, 1) * math.clamp((stopAt - d) / 6, 0, 1)
			c.Transparency = 1 - (.2 + .6 * fade)
		end
		for i = n + 1, #chevrons do
			chevrons[i].Transparency = 1
		end
	end

	local marker: any = nil -- {Holder, Gui, Title, Dist, Arrow}
	local function ensureMarker(): any
		if marker and marker.Holder.Parent then
			return marker
		end
		local holder = Instance.new("Part")
		holder.Name = "GuideMarker"
		holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
		holder.Transparency = 1
		holder.Size = V3(.2, .2, .2)
		holder.Parent = world
		local bb = Instance.new("BillboardGui")
		bb.Name = "Marker"
		bb.Size = UDim2.fromOffset(190, 86)
		bb.StudsOffsetWorldSpace = V3(0, 4.2, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 600
		bb.LightInfluence = 0
		bb:SetAttribute("NoTranslate", true)
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0, 26)
		title.FontFace = FONT
		title.TextScaled = true
		title.TextColor3 = VIOLET_HI
		title.TextStrokeColor3 = INK
		title.TextStrokeTransparency = .1
		title:SetAttribute("NoTranslate", true)
		title.Parent = bb
		local dist = Instance.new("TextLabel")
		dist.Name = "Distance"
		dist.BackgroundTransparency = 1
		dist.Position = UDim2.fromOffset(0, 26)
		dist.Size = UDim2.new(1, 0, 0, 18)
		dist.FontFace = FONT
		dist.TextScaled = true
		dist.TextColor3 = WHITE
		dist.TextStrokeColor3 = INK
		dist.TextStrokeTransparency = .2
		dist:SetAttribute("NoTranslate", true)
		dist.Parent = bb
		local arrow = Instance.new("TextLabel")
		arrow.Name = "Arrow"
		arrow.BackgroundTransparency = 1
		arrow.AnchorPoint = Vector2.new(.5, 0)
		arrow.Position = UDim2.new(.5, 0, 0, 46)
		arrow.Size = UDim2.fromOffset(40, 34)
		arrow.FontFace = FONT
		arrow.TextScaled = true
		arrow.Text = "▼"
		arrow.TextColor3 = GOLD
		arrow.TextStrokeColor3 = INK
		arrow.TextStrokeTransparency = .1
		arrow:SetAttribute("NoTranslate", true)
		arrow.Parent = bb
		bb.Parent = holder
		marker = { Holder = holder, Gui = bb, Title = title, Dist = dist, Arrow = arrow }
		return marker
	end
	local function markerStep(target: Vector3, label: string, me: Vector3, show: boolean)
		if not show then
			if marker then
				marker.Gui.Enabled = false
			end
			return
		end
		local m = ensureMarker()
		m.Gui.Enabled = true
		m.Holder.CFrame = CF(target)
		if m.Title.Text ~= label then
			m.Title.Text = label
		end
		local d = (target - me).Magnitude
		m.Dist.Text = string.format(Shared.IsRussian() and "%d м" or "%d m", math.floor(d + .5))
		local bounce = Shared.ReducedMotion() and 0 or math.abs(math.sin(os.clock() * 4)) * 6
		m.Arrow.Position = UDim2.new(.5, 0, 0, 46 + bounce)
	end

	local highlight: Highlight? = nil
	local function highlightStep(model: Instance?, show: boolean)
		if not (show and model and model.Parent) then
			if highlight then
				highlight.Adornee = nil
				highlight.Enabled = false
			end
			return
		end
		if not (highlight and highlight.Parent) then
			local h = Instance.new("Highlight")
			h.Name = "GuideHighlight"
			h.FillColor = VIOLET
			h.OutlineColor = VIOLET_HI
			h.FillTransparency = .8
			h.OutlineTransparency = .15
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = world
			highlight = h
		end
		local h = highlight :: Highlight
		if h.Adornee ~= model then
			h.Adornee = model
		end
		h.Enabled = true
		h.OutlineTransparency = .15 + .25 * (.5 + .5 * math.sin(os.clock() * 3))
	end

	---------------------------------------------------------------------------------------------------------------
	-- camera focus (Cinema)
	---------------------------------------------------------------------------------------------------------------
	local function focus(target: Vector3)
		local Cinema = ctx.Modules and ctx.Modules.Cinema
		local r = rootPart()
		if not (Cinema and Cinema.Play and r) then
			return
		end
		if (target - r.Position).Magnitude > 220 then
			return -- far: the pup and the way are enough
		end
		local camPos = R.FocusFrom(target, r.Position, 15, 7)
		local shot = CFrame.lookAt(camPos, target + V3(0, 1.2, 0))
		pcall(Cinema.Play, {
			Id = "C2Guide", Duration = GC.Focus, Shot = function()
				return shot
			end, Letterbox = false, HideUI = false, LockControls = true, Skippable = true, SkipAfter = .3, Duck = false,
			BlendIn = .7, BlendOut = .6,
		})
	end

	---------------------------------------------------------------------------------------------------------------
	-- the card
	---------------------------------------------------------------------------------------------------------------
	local card: any = nil
	local function label(parent: Instance, name: string, font: Font, size: number, color: Color3, order: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.FontFace = font
		l.TextSize = size
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color
		l.Text = ""
		l.LayoutOrder = order
		l:SetAttribute("NoTranslate", true)
		l.Parent = parent
		return l
	end
	local function button(parent: Instance, name: string, text: string, color: Color3, order: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Active = true
		b.AutoButtonColor = true
		b.BackgroundColor3 = color
		b.Size = UDim2.new(.5, -5, 0, 44)
		b.FontFace = FONT
		b.TextSize = 17
		b.TextColor3 = WHITE
		b.TextStrokeColor3 = INK
		b.TextStrokeTransparency = .4
		b.Text = text
		b.LayoutOrder = order
		b:SetAttribute("NoTranslate", true)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = b
		local s = Instance.new("UIStroke")
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color = INK
		s.Thickness = 2
		s.Parent = b
		b.Parent = parent
		return b
	end

	local onShowMe, onSkip, onCollapse, onGotIt
	local function buildCard(): any
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return nil
		end
		local old = pg:FindFirstChild(LAYER)
		if old then
			old:Destroy()
		end
		local sg = Instance.new("ScreenGui")
		sg.Name = LAYER
		sg.DisplayOrder = 46
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		sg.Enabled = false
		pcall(function()
			sg.ScreenInsets = Enum.ScreenInsets.None
		end)
		sg:SetAttribute("NoTranslate", true)
		-- (no HideWithUI: this module follows UIHidden / CinemaActive itself, so HIDE UI can never resurrect a stale card)
		local frame = Instance.new("Frame")
		frame.Name = "Card"
		frame.AnchorPoint = Vector2.new(.5, 1)
		frame.BackgroundColor3 = GLASS
		frame.BackgroundTransparency = .08
		frame.Size = UDim2.fromOffset(440, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.Active = true
		frame.Parent = sg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 16)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = VIOLET
		stroke.Thickness = 2.5
		stroke.Parent = frame
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(C3(255, 255, 255), C3(185, 170, 215))
		grad.Rotation = 90
		grad.Parent = frame
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 16), UDim.new(0, 16), UDim.new(0, 12), UDim.new(0, 14)
		pad.Parent = frame
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 6)
		list.Parent = frame
		local scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = frame
		-- header: kicker + collapse
		local head = Instance.new("Frame")
		head.Name = "Head"
		head.BackgroundTransparency = 1
		head.Size = UDim2.new(1, 0, 0, 26)
		head.LayoutOrder = 1
		head.Parent = frame
		local kicker = label(head, "Kicker", FONT, 15, VIOLET_HI, 1)
		kicker.AutomaticSize = Enum.AutomaticSize.None
		kicker.Size = UDim2.new(1, -52, 1, 0)
		kicker.TextWrapped = false
		kicker.TextTruncate = Enum.TextTruncate.AtEnd
		local collapse = Instance.new("TextButton")
		collapse.Name = "Collapse"
		collapse.Active = true
		collapse.AnchorPoint = Vector2.new(1, .5)
		collapse.Position = UDim2.new(1, 6, .5, 0)
		collapse.Size = UDim2.fromOffset(44, 44)
		collapse.BackgroundTransparency = 1
		collapse.FontFace = FONT
		collapse.TextSize = 26
		collapse.TextColor3 = MUTED
		collapse.Text = "–"
		collapse:SetAttribute("NoTranslate", true)
		collapse.Parent = head
		local title = label(frame, "Title", FONT, 26, WHITE, 2)
		local text = label(frame, "Text", BODY, 17, C3(236, 230, 250), 3)
		local hint = label(frame, "Hint", BODY, 15, MUTED, 4)
		-- progress
		local prog = Instance.new("Frame")
		prog.Name = "Progress"
		prog.BackgroundTransparency = 1
		prog.Size = UDim2.new(1, 0, 0, 24)
		prog.LayoutOrder = 5
		prog.Parent = frame
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0, .5)
		bar.Position = UDim2.new(0, 0, .5, 0)
		bar.Size = UDim2.new(1, -96, 0, 12)
		bar.BackgroundColor3 = INK
		bar.Parent = prog
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(1, 0)
		bc.Parent = bar
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = GOLD
		fill.Parent = bar
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(1, 0)
		fc.Parent = fill
		local count = label(prog, "Count", FONT, 16, GOLD, 1)
		count.AutomaticSize = Enum.AutomaticSize.None
		count.AnchorPoint = Vector2.new(1, .5)
		count.Position = UDim2.new(1, 0, .5, 0)
		count.Size = UDim2.new(0, 90, 1, 0)
		count.TextXAlignment = Enum.TextXAlignment.Right
		local tip = label(frame, "Tip", BODY, 14, GOLD, 6)
		-- buttons
		local row = Instance.new("Frame")
		row.Name = "Buttons"
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 44)
		row.LayoutOrder = 7
		row.Parent = frame
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rl.Padding = UDim.new(0, 10)
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Parent = row
		local show = button(row, "ShowMe", T("SHOW ME"), C3(120, 70, 200), 1)
		local skip = button(row, "Skip", T("SKIP GUIDE"), C3(64, 52, 88), 2)
		local got = button(row, "GotIt", T("GOT IT"), C3(70, 150, 90), 3)
		got.Visible = false
		-- the collapsed pill
		local pill = Instance.new("TextButton")
		pill.Name = "Pill"
		pill.Active = true
		pill.AnchorPoint = Vector2.new(.5, 1)
		pill.Size = UDim2.fromOffset(300, 46)
		pill.BackgroundColor3 = GLASS
		pill.BackgroundTransparency = .08
		pill.FontFace = FONT
		pill.TextSize = 16
		pill.TextColor3 = WHITE
		pill.TextTruncate = Enum.TextTruncate.AtEnd
		pill.Visible = false
		pill:SetAttribute("NoTranslate", true)
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(1, 0)
		pc.Parent = pill
		local ps = Instance.new("UIStroke")
		ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ps.Color = VIOLET
		ps.Thickness = 2
		ps.Parent = pill
		pill.Parent = sg
		show.Activated:Connect(function()
			onShowMe()
		end)
		skip.Activated:Connect(function()
			onSkip()
		end)
		collapse.Activated:Connect(function()
			onCollapse(true)
		end)
		pill.Activated:Connect(function()
			onCollapse(false)
		end)
		got.Activated:Connect(function()
			onGotIt()
		end)
		sg.Parent = pg
		return { Gui = sg, Frame = frame, Kicker = kicker, Title = title, Text = text, Hint = hint, Progress = prog, Fill = fill, Count = count,
			Tip = tip, Show = show, Skip = skip, Got = got, Pill = pill, Scale = scale, Collapse = collapse, Key = nil }
	end

	-- layout: width and the bottom offset for the screen (phones: above the jump button / thumbstick)
	local function layoutCard(c: any)
		local cam = workspace.CurrentCamera
		local size = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local portrait = size.Y > size.X
		local w = math.clamp(size.X - 24, 280, 460)
		local bottom = touch and (portrait and 210 or 128) or 112
		c.Frame.Size = UDim2.fromOffset(w, 0)
		c.Frame.Position = UDim2.new(.5, 0, 1, -bottom)
		c.Pill.Position = UDim2.new(.5, 0, 1, -bottom)
		c.Pill.Size = UDim2.fromOffset(math.min(w, 340), 46)
		local small = size.X < 520 or size.Y < 430
		c.Title.TextSize = small and 22 or 26
		c.Text.TextSize = small and 15 or 17
		c.Hint.TextSize = small and 13 or 15
		c.Tip.TextSize = small and 13 or 14
		c.Small = small
	end

	-- fill the card for the step (or the final card)
	local function fillCard(c: any, step: number)
		local final = st.Final ~= nil
		local def = defOf(step)
		local gs = guideOf(def)
		local key = final and "Final" or tostring(step)
		local fresh = c.Key ~= key
		c.Key = key
		if final then
			c.Kicker.Text = T("GHOST GUIDE · COMPLETE")
			c.Title.Text = T("THE UNDERYARD IS YOURS")
			c.Text.Text = T("The pup returns to its bell. Break the Bell Seals one by one: each opens a new district.")
			c.Hint.Text = T("THE UNDERYARD window (rail) shows your seals, contracts, coffins and the journal.")
			c.Tip.Text = ""
			c.Progress.Visible = false
			c.Show.Visible, c.Skip.Visible, c.Got.Visible = false, false, true
		elseif def then
			c.Kicker.Text = string.format(T("GHOST GUIDE · STEP %d / %d"), step, TOTAL)
			c.Title.Text = pair(def.Title)
			c.Text.Text = pair(def.Text) .. "."
			local hint = gs and pair(gs.Hint) or ""
			if st.TrialFail and STEP_OF_TRIAL[st.TrialFail] == step then
				hint = T("Not this time. BEGIN TRIAL again: the guide waits for you.") .. " " .. hint
			end
			c.Hint.Text = hint
			c.Tip.Text = (gs and gs.Tip) and pair(gs.Tip) or ""
			c.Tip.Visible = c.Tip.Text ~= ""
			local have, need = R.GuideProgress(def, view())
			c.Progress.Visible = have ~= nil
			if have and need then
				c.Fill.Size = UDim2.fromScale(math.clamp(have / math.max(1, need), 0, 1), 1)
				c.Count.Text = string.format("%d / %d", have, need)
			end
			c.Show.Visible, c.Skip.Visible, c.Got.Visible = true, true, false
			if os.clock() >= st.SkipArmed then
				c.Skip.Text = T("SKIP GUIDE")
			end
		end
		c.Pill.Text = final and ("🐾  " .. T("THE UNDERYARD IS YOURS")) or ("🐾  " .. string.format(T("STEP %d/%d · %s"), step, TOTAL, def and pair(def.Title) or ""))
		if fresh then
			if c.Small and not final then
				st.CollapseAt = os.clock() + 14 -- small screens: the pill after a while
			else
				st.CollapseAt = math.huge
			end
			st.Collapsed = false
			if not Shared.ReducedMotion() then
				c.Scale.Scale = .9
				TweenService:Create(c.Scale, TweenInfo.new(.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end

	local function cardStep(step: number, show: boolean)
		if not show then
			if card and card.Gui.Parent then
				card.Gui.Enabled = false
			end
			st.CardShown = false
			return
		end
		if not (card and card.Gui.Parent) then
			card = buildCard()
			if not card then
				return
			end
		end
		local c = card
		layoutCard(c)
		fillCard(c, step)
		if os.clock() >= st.CollapseAt then
			st.Collapsed = true
			st.CollapseAt = math.huge
		end
		c.Frame.Visible = not st.Collapsed
		c.Pill.Visible = st.Collapsed
		c.Gui.Enabled = true
		st.CardShown = true
	end

	---------------------------------------------------------------------------------------------------------------
	-- buttons
	---------------------------------------------------------------------------------------------------------------
	onShowMe = function()
		local r = rootPart()
		local def = defOf(st.Step)
		if not (r and def) then
			return
		end
		local target = targetOf(def, r.Position)
		focus(target)
		if pup then
			bark(pup.Pos)
		end
	end
	showFn = function()
		pcall(onShowMe)
	end
	onSkip = function()
		if st.Busy then
			return
		end
		if os.clock() >= st.SkipArmed then
			st.SkipArmed = os.clock() + 3
			if card then
				card.Skip.Text = T("TAP AGAIN TO SKIP")
			end
			return
		end
		st.Busy = true
		st.SkippingAt = os.clock()
		if card then
			card.Skip.Text = T("SKIPPING...")
		end
		task.spawn(function()
			local ok, res = request("C2Tutorial", { Skip = true })
			st.Busy = false
			st.SkipArmed = 0
			if not ok then
				local msg = type(res) == "string" and res or "Try again"
				local cs = CS()
				local okT, txt = pcall(function()
					return cs and cs.T and cs.T(msg) or msg
				end)
				pcall(Bus.Fire, "Toast", { Text = okT and txt or msg, Kind = "error", NoTranslate = true })
			end
		end)
	end
	onCollapse = function(on: boolean)
		st.Collapsed = on
		st.CollapseAt = math.huge
	end
	onGotIt = function()
		st.Final = nil
		dropPup(true)
	end

	---------------------------------------------------------------------------------------------------------------
	-- the practice trials' prompts (shown on their step only)
	---------------------------------------------------------------------------------------------------------------
	local prompts: { [ProximityPrompt]: string } = {}
	local anchorsHooked: Instance? = nil
	local function trackPrompt(d: Instance)
		if d:IsA("ProximityPrompt") then
			local trial = d:GetAttribute("UyTutorialTrial")
			if type(trial) == "string" then
				prompts[d] = trial
			end
		end
	end
	local function promptsStep(step: number)
		local r = uyRoot()
		local anchors = r and r:FindFirstChild("Anchors")
		if anchors and anchors ~= anchorsHooked then
			anchorsHooked = anchors
			for _, d in ipairs(anchors:GetDescendants()) do
				trackPrompt(d)
			end
			table.insert(conns, anchors.DescendantAdded:Connect(trackPrompt))
		end
		local free = inTrial() == ""
		for prompt, trial in pairs(prompts) do
			if not prompt.Parent then
				prompts[prompt] = nil
			else
				local want = free and STEP_OF_TRIAL[trial] == step
				if prompt.Enabled ~= want then
					prompt.Enabled = want
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- step bookkeeping
	---------------------------------------------------------------------------------------------------------------
	local function onStepChanged(old: number, new: number)
		st.TrialFail = nil
		st.SatisfiedSince = nil
		st.RingSince = nil
		st.SkipArmed = 0
		local skipped = st.SkippedNow or os.clock() - (st.SkippingAt or -1e9) < 12
		if new == -1 and old >= 1 and st.WasActive and not skipped then
			st.Final = os.clock()
			pcall(Audio.Play, "SealComplete", nil, { Volume = .6, Pitch = 1.2 })
		elseif new >= 1 and old >= 1 and new > old then
			pcall(Audio.Play, "QuestDone", nil, { Volume = .7 })
			if pup then
				poofAt(pup.Pos)
				bark(pup.Pos)
			end
		end
		if new < 1 and not st.Final then
			dropPup(true)
		end
		st.SkippedNow = nil
	end

	-- a step whose condition holds but that did not advance (a lost signal): ask the server to check it
	local function autoCheck(step: number, def: any)
		local now = os.clock()
		if st.Busy or now - st.AskedAt < GC.AutoCheck * 2 then
			return
		end
		local due = false
		if def.Auto then
			local have, need = R.GuideProgress(def, view())
			if have and need and have >= need then
				st.SatisfiedSince = st.SatisfiedSince or now
				due = now - st.SatisfiedSince >= GC.AutoCheck
			else
				st.SatisfiedSince = nil
			end
		elseif def.Event == "Practice" then
			local r = rootPart()
			local ring = Layout.Square.PracticeRing
			local inside = r ~= nil and V3(r.Position.X - ring.Centre.X, 0, r.Position.Z - ring.Centre.Z).Magnitude <= ring.Radius
				and math.abs(r.Position.Y - ring.Centre.Y) < 12
			if inside then
				st.RingSince = st.RingSince or now
				due = now - st.RingSince >= 1.2
			else
				st.RingSince = nil
			end
		end
		if due then
			st.AskedAt = now
			st.Busy = true
			task.spawn(function()
				request("C2Tutorial", { Step = step })
				st.Busy = false
			end)
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- the loop
	---------------------------------------------------------------------------------------------------------------
	local acc = 0
	local lastStep = serverStep()
	st.Step = lastStep
	-- 20 Hz: the step, the card, the way, the marker, the prompts; the pup's goal (st.PupTarget) for the frame step
	local function step(_dt: number)
		local s = serverStep()
		if s ~= lastStep then
			local old = lastStep
			lastStep = s
			st.Step = s
			onStepChanged(old, s)
		end
		promptsStep(s)
		local r = rootPart()
		local active = s >= 1 and s <= TOTAL and inZone() and r ~= nil
		local final = st.Final ~= nil and inZone() and r ~= nil
		if not active and not final then
			-- out of the zone, dead or not on a step: nothing in the world, no card
			if pup then
				dropPup(false)
			end
			st.PupTarget = nil
			wayStep(false)
			markerStep(Vector3.zero, "", Vector3.zero, false)
			highlightStep(nil, false)
			cardStep(s, false)
			return
		end
		st.WasActive = st.WasActive or active
		local me = (r :: BasePart).Position
		if final then
			-- the pup circles the player a moment, then leaves (GOT IT, or after 20 s)
			if os.clock() - st.Final > 20 then
				st.Final = nil
				st.PupTarget = nil
				dropPup(true)
				cardStep(s, false)
				return
			end
			st.Path = { me, me }
			st.PupTarget = pup and (me + V3(3, 0, 3)) or nil
			wayStep(false)
			markerStep(me, "", me, false)
			highlightStep(nil, false)
			cardStep(s, not cardBlocked())
			return
		end
		local def = defOf(s)
		local target, model, name = targetOf(def, me)
		st.Target, st.TargetName = target, name
		if os.clock() - st.PathAt > .4 then
			st.PathAt = os.clock()
			st.Path = wayTo(me, target)
		end
		local inRun = inTrial() ~= ""
		local near = (V3(target.X, 0, target.Z) - V3(me.X, 0, me.Z)).Magnitude < 7
		st.PupTarget = target
		wayStep(not inRun and not near)
		markerStep(target, name, me, not inRun)
		highlightStep(model, not inRun)
		cardStep(s, not cardBlocked())
		autoCheck(s, def)
		-- a step seen for the first time: a short camera focus on its target (once per step per session)
		if not st.Focused[s] and not cardBlocked() and not inRun then
			st.Focused[s] = true
			task.delay(s == 1 and GC.ArriveDelay or .6, function()
				if alive and serverStep() == s and not cardBlocked() then
					local rr = rootPart()
					if rr then
						focus((targetOf(def, rr.Position)))
					end
				end
			end)
		end
	end

	-- every frame: the pup flies (smooth at any frame rate)
	local function pupFrame(dt: number)
		local target = st.PupTarget
		local r = rootPart()
		if not (target and r) then
			return
		end
		pupStep(dt, r.Position, target)
	end

	---------------------------------------------------------------------------------------------------------------
	-- wiring + teardown
	---------------------------------------------------------------------------------------------------------------
	local function stop()
		if not alive then
			return
		end
		alive = false
		started = false
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		table.clear(conns)
		for _, c in ipairs(busConns) do
			pcall(c.Disconnect)
		end
		table.clear(busConns)
		dropPup(false)
		clearWay()
		if card and card.Gui then
			card.Gui:Destroy()
		end
		card = nil
		world:Destroy()
		-- give the practice prompts back to their default (visible) state
		for prompt in pairs(prompts) do
			if prompt.Parent then
				prompt.Enabled = true
			end
		end
		table.clear(prompts)
	end
	stopFn = stop
	stateFn = function()
		return {
			Step = st.Step, Card = st.CardShown, Collapsed = st.Collapsed, Final = st.Final ~= nil, Pup = pup ~= nil, PupMode = st.PupMode,
			Target = st.Target, TargetName = st.TargetName, Chevrons = #chevrons, TrialFail = st.TrialFail, Busy = st.Busy,
			Prompts = (function()
				local out = {}
				for p, trial in pairs(prompts) do
					out[trial] = p.Enabled
				end
				return out
			end)(),
		}
	end

	table.insert(busConns, Bus.On("C2Signal", function(sig)
		if type(sig) ~= "table" then
			return
		end
		local d = sig.Data
		if sig.Kind == "C2Tutorial" and type(d) == "table" and d.Skipped then
			st.SkippedNow = true
		elseif sig.Kind == "C2Trial" and type(d) == "table" and STEP_OF_TRIAL[tostring(d.TrialId)] then
			if d.Kind == "Failed" or (d.Kind == "Left" and tonumber(d.UserId) == player.UserId) then
				st.TrialFail = tostring(d.TrialId)
			elseif d.Kind == "Start" then
				st.TrialFail = nil
			end
		elseif sig.Kind == "C2Shards" and type(d) == "table" and serverStep() == 1 and pup then
			-- a little cheer from the pup while the shards come in
			if os.clock() - (st.CheerAt or 0) > 4 then
				st.CheerAt = os.clock()
				bark(pup.Pos)
			end
		end
	end))
	table.insert(conns, player.CharacterAdded:Connect(function()
		-- a respawn: the pup comes back to the new character (rebuilt on the next step)
		dropPup(false)
		st.PathAt = -1e9
	end))
	local stFolder = RS.Halloween:FindFirstChild("State")
	if stFolder then
		table.insert(conns, stFolder:GetAttributeChangedSignal("HalloweenChapter2Enabled"):Connect(function()
			if not Shared.Chapter2Enabled() then
				stop()
			end
		end))
	end
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end
		acc += dt
		if acc >= .05 then
			local adt = math.min(acc, .25)
			acc = 0
			local ok, err = pcall(step, adt)
			if not ok and not warned.Step then
				warned.Step = true
				warn("Chapter2Guide step failed: " .. tostring(err))
			end
		end
		local ok2, err2 = pcall(pupFrame, math.min(dt, .1))
		if not ok2 and not warned.Pup then
			warned.Pup = true
			warn("Chapter2Guide pup failed: " .. tostring(err2))
		end
	end))
end

return G
