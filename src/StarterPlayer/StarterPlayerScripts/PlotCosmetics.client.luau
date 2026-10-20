-- Plot cosmetics on the client (docs/PLOT_COSMETICS.md).
-- 1. MY BEST FINDS rarity effects: every stand is tagged DogrotsShowcase (PlotAppearance). Within
--    FX_RANGE of the camera (the two nearest stands at most) each filled case gets its tier effect:
--      Common / Uncommon  soft light strip at the base
--      Rare               + a blue glow ring
--      Epic               + a purple light beam
--      Legendary          + a gold beam and sparkles
--      Mythic / Secret    + an animated aura (counter-rotating rings, colour cycle)
--    and the exhibits turn slowly. Effects are client parts in one folder, rebuilt only when a
--    case changes (attribute ExhibitToken); the 30 Hz animation runs only while a stand is near.
--    Reduced motion (Roblox setting / ReducedMotion attribute) or low FX (LowFX attribute, low
--    graphics quality): static strip + ring + beam, no particles, no turning.
-- 2. Plot decor walk-up: on your own yard, every decor slot within MARKER_RANGE gets a DECORATE
--    prompt (owner only: visitors never get one) and empty slots show a subtle dashed ring with a
--    "+". The prompt opens the DECOR window on that slot (Modules.DecorScreen via GUIIntegration).
--    Slot positions come from the yard attributes PlotFrame / PlotMirror (Economy.PlotDecorWorld),
--    filled slots from Decor_<slot>, so nothing waits for streamed parts.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local Economy = ReplicatedStorage:WaitForChild("DogEconomy")
local Rules = require(Economy:WaitForChild("ShowcaseRules"))
local Catalog = require(Economy:WaitForChild("DecorCatalog"))

local FX_RANGE = 80
local MAX_STANDS = 2
local MARKER_RANGE = 40
local MARKER_DROP = 46
local SPIN = math.rad(22) -- exhibit turn, radians per second
local TAG = "DogrotsShowcase"

local fxFolder = Instance.new("Folder")
fxFolder.Name = "PlotCosmeticsFX"
fxFolder.Parent = workspace

local function reduced(): boolean
	if player:GetAttribute("ReducedMotion") == true then
		return true
	end
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end
local function lowFX(): boolean
	if player:GetAttribute("LowFX") == true or player:GetAttribute("WorldEventFX") == "Low" then
		return true
	end
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return ok and type(level) == "number" and level > 0 and level <= 3
end

-- Prompts are drawn by Roblox (not translated by AutoTranslate): same locale rule as Kit.Lang.
local function russian(): boolean
	local ok, locale = pcall(function()
		local LocalizationService = game:GetService("LocalizationService")
		if RunService:IsStudio() then
			return LocalizationService.RobloxLocaleId
		end
		return player.LocaleId ~= "" and player.LocaleId or LocalizationService.RobloxLocaleId
	end)
	return ok and type(locale) == "string" and string.lower(string.sub(locale, 1, 2)) == "ru"
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	return p
end

------------------------------------------------------------------------------------------------
-- 1. Showcase rarity effects
------------------------------------------------------------------------------------------------
type CaseFX = {
	Case: Model,
	Token: any,
	Folder: Folder,
	Tier: string,
	Center: Vector3,
	Rings: { { Part: BasePart, Radius: number, Height: number, Index: number, Count: number, Dir: number } },
	Beam: BasePart?,
	Aura: boolean,
	Color: Color3,
}
type StandFX = { Stand: Model, Cases: { [Model]: CaseFX }, Conns: { RBXScriptConnection } }

local stands: { [Model]: boolean } = {}
local active: { [Model]: StandFX } = {}
local animate: RBXScriptConnection? = nil
local clock = 0

local TIERS = { Common = 1, Uncommon = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Secret = 5 }

local function clearCase(fx: CaseFX)
	fx.Folder:Destroy()
	local exhibit = fx.Case:FindFirstChild("Exhibit")
	local rest = exhibit and exhibit:GetAttribute("RestPivot")
	if exhibit and exhibit:IsA("Model") and typeof(rest) == "CFrame" then
		exhibit:PivotTo(rest)
	end
end

local function buildCase(case: Model): CaseFX?
	local platform = case:FindFirstChild("Platform")
	if not (platform and platform:IsA("BasePart")) or case:GetAttribute("Filled") ~= true then
		return nil
	end
	local tier = case:GetAttribute("Effect")
	tier = type(tier) == "string" and TIERS[tier] and tier or "Common"
	local level = TIERS[tier]
	local color = Rules.Colors[tier] or Rules.Colors.Common
	local low = lowFX() or reduced()
	local folder = Instance.new("Folder")
	folder.Name = case.Name
	local base = platform.CFrame
	local center = (base * CFrame.new(0, 1.3, 0)).Position
	local fx: CaseFX = { Case = case, Token = case:GetAttribute("ExhibitToken"), Folder = folder, Tier = tier, Center = center, Rings = {}, Beam = nil, Aura = level >= 5 and not low, Color = color }
	-- Soft light strip under the platform edge.
	part("Strip", Vector3.new(3.15, 0.08, 3.15), base * CFrame.new(0, -0.17, 0), color, 0.35).Parent = folder
	if level >= 2 then
		local count = low and 6 or 10
		for i = 1, count do
			local p = part("Ring", Vector3.new(0.12, 0.12, 0.85), CFrame.new(), color, 0.25)
			p.Parent = folder
			table.insert(fx.Rings, { Part = p, Radius = 1.75, Height = 0.35, Index = i, Count = count, Dir = 1 })
		end
		if level >= 5 then
			for i = 1, count do
				local p = part("Aura", Vector3.new(0.1, 0.1, 0.7), CFrame.new(), color:Lerp(Color3.new(1, 1, 1), 0.35), 0.3)
				p.Parent = folder
				table.insert(fx.Rings, { Part = p, Radius = 1.55, Height = 2.6, Index = i, Count = count, Dir = -1 })
			end
		end
	end
	if level >= 3 then
		local glass = case:FindFirstChild("CaseCap")
		local top = glass and glass:IsA("BasePart") and glass.Position.Y + 0.2 or center.Y + 3
		local height = level >= 4 and 14 or 10
		local beamColor = level == 4 and Color3.fromRGB(255, 214, 90) or color
		local beam = part("Beam", Vector3.new(height, 0.55, 0.55), CFrame.new(center.X, top + height / 2, center.Z) * CFrame.Angles(0, 0, math.pi / 2), beamColor, 0.72, Enum.PartType.Cylinder)
		beam.Parent = folder
		fx.Beam = beam
	end
	if level >= 4 and not low then
		local glass = case:FindFirstChild("CaseGlass")
		if glass and glass:IsA("BasePart") then
			local attachment = Instance.new("Attachment")
			attachment.Name = "PlotCosmeticsSparkles"
			attachment.Parent = glass
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkles.Color = ColorSequence.new(level >= 5 and color or Color3.fromRGB(255, 220, 110))
			sparkles.LightEmission = 1
			sparkles.Rate = level >= 5 and 7 or 4
			sparkles.Lifetime = NumberRange.new(0.8, 1.4)
			sparkles.Speed = NumberRange.new(0.3, 0.9)
			sparkles.SpreadAngle = Vector2.new(180, 180)
			sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
			sparkles.Parent = attachment
			-- The emitter lives on the server's glass part: the folder cleanup removes it too.
			folder.Destroying:Connect(function()
				attachment:Destroy()
			end)
		end
	end
	-- Static ring layout (also the first frame of the animation).
	for _, r in ipairs(fx.Rings) do
		local a = (r.Index / r.Count) * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * r.Radius, r.Height - 1.3, math.sin(a) * r.Radius)
		r.Part.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
	end
	folder.Parent = fxFolder
	return fx
end

local function syncStand(s: StandFX)
	local cases = s.Stand:FindFirstChild("Cases")
	local seen: { [Model]: boolean } = {}
	if cases then
		for _, case in ipairs(cases:GetChildren()) do
			if case:IsA("Model") then
				seen[case] = true
				local fx = s.Cases[case]
				local token = case:GetAttribute("ExhibitToken")
				local filled = case:GetAttribute("Filled") == true
				if fx and (fx.Token ~= token or not filled or fx.Tier ~= case:GetAttribute("Effect")) then
					clearCase(fx)
					s.Cases[case] = nil
					fx = nil
				end
				if not fx and filled then
					local built = buildCase(case)
					if built then
						s.Cases[case] = built
					end
				end
			end
		end
	end
	for case, fx in pairs(s.Cases) do
		if not seen[case] or not case.Parent then
			clearCase(fx)
			s.Cases[case] = nil
		end
	end
end

local function step(dt: number)
	clock += dt
	if clock < 1 / 30 then
		return
	end
	local t = os.clock()
	local still = reduced()
	clock = 0
	for _, s in pairs(active) do
		for _, fx in pairs(s.Cases) do
			if not still then
				local exhibit = fx.Case:FindFirstChild("Exhibit")
				local rest = exhibit and exhibit:GetAttribute("RestPivot")
				if exhibit and exhibit:IsA("Model") and typeof(rest) == "CFrame" then
					local pivot = CFrame.new(fx.Center)
					exhibit:PivotTo(pivot * CFrame.Angles(0, t * SPIN, 0) * pivot:Inverse() * rest)
				end
				for _, r in ipairs(fx.Rings) do
					local a = (r.Index / r.Count) * math.pi * 2 + t * 0.6 * r.Dir
					local bob = math.sin(t * 1.6 + r.Height) * 0.12
					local pos = fx.Center + Vector3.new(math.cos(a) * r.Radius, r.Height - 1.3 + bob, math.sin(a) * r.Radius)
					r.Part.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)) * r.Dir)
				end
				local beam = fx.Beam
				if beam then
					beam.Transparency = 0.66 + math.sin(t * 2.2) * 0.08
				end
				if fx.Aura then
					local hue = fx.Tier == "Secret" and (t * 0.12) % 1 or nil
					local color = hue and Color3.fromHSV(hue, 0.55, 1) or fx.Color:Lerp(Color3.new(1, 1, 1), 0.25 + 0.2 * math.sin(t * 3))
					for _, r in ipairs(fx.Rings) do
						r.Part.Color = color
					end
					if beam then
						beam.Color = color
					end
				end
			end
		end
	end
end

local function setAnimating(on: boolean)
	if on and not animate then
		animate = RunService.Heartbeat:Connect(step)
	elseif not on and animate then
		animate:Disconnect()
		animate = nil
	end
end

local function deactivate(stand: Model)
	local s = active[stand]
	if not s then
		return
	end
	for _, fx in pairs(s.Cases) do
		clearCase(fx)
	end
	for _, c in ipairs(s.Conns) do
		c:Disconnect()
	end
	active[stand] = nil
end

local function activate(stand: Model)
	if active[stand] then
		return
	end
	local s: StandFX = { Stand = stand, Cases = {}, Conns = {} }
	active[stand] = s
	local pending = false
	local function resync()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if active[stand] == s then
				syncStand(s)
			end
		end)
	end
	-- Case attributes change when the owner edits the showcase; parts stream in with the stand.
	table.insert(s.Conns, stand.DescendantAdded:Connect(resync))
	table.insert(s.Conns, stand.DescendantRemoving:Connect(resync))
	local cases = stand:FindFirstChild("Cases")
	if cases then
		for _, case in ipairs(cases:GetChildren()) do
			table.insert(s.Conns, case.AttributeChanged:Connect(resync))
		end
	end
	syncStand(s)
end

local function standPosition(stand: Model): Vector3?
	local ok, pivot = pcall(stand.GetPivot, stand)
	return ok and pivot.Position or nil
end

-- 2 Hz: which stands are near the camera (no per-frame work while idle).
local function scanStands()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local from = camera.CFrame.Position
	local near = {}
	for stand in pairs(stands) do
		-- Only real yards: stand previews in viewports (PlotShopScreen, UpgradeTreeScreen) carry the tag too.
		if stand.Parent and stand:IsDescendantOf(workspace) then
			local pos = standPosition(stand)
			local distance = pos and (pos - from).Magnitude or math.huge
			if distance <= FX_RANGE then
				table.insert(near, { Stand = stand, Distance = distance })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.Distance < b.Distance
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(MAX_STANDS, #near) do
		keep[near[i].Stand] = true
	end
	for stand in pairs(active) do
		if not keep[stand] or not stand:IsDescendantOf(workspace) then
			deactivate(stand)
		end
	end
	for stand in pairs(keep) do
		activate(stand)
	end
	setAnimating(next(active) ~= nil)
end

local function addStand(instance: Instance)
	if instance:IsA("Model") then
		stands[instance] = true
	end
end
for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
	addStand(instance)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(addStand)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
	stands[instance :: Model] = nil
	deactivate(instance :: Model)
end)

------------------------------------------------------------------------------------------------
-- 2. Decor slot markers and DECORATE prompts (own yard only)
------------------------------------------------------------------------------------------------
type Marker = { Part: Part, Prompt: ProximityPrompt, Ring: Frame?, Tween: Tween?, Filled: boolean }
local markers: { [string]: Marker } = {}
local markerYard: Model? = nil

local function ownYard(): Model?
	local map = workspace:FindFirstChild("DOGROTS_District")
	local yards = map and map:FindFirstChild("04_PlayerYards")
	if not yards then
		return nil
	end
	local id = player:GetAttribute("YardId")
	for _, yard in ipairs(yards:GetChildren()) do
		if yard:IsA("Model") and yard:GetAttribute("OwnerUserId") == player.UserId and (id == nil or yard:GetAttribute("YardId") == id) then
			return yard
		end
	end
	return nil
end

local function openDecor(slotId: string)
	local gui = player:FindFirstChild("PlayerGui")
	local screen = gui and gui:FindFirstChild("ScreenGui")
	local modules = screen and screen:FindFirstChild("Modules")
	local integration = modules and modules:FindFirstChild("GUIIntegration")
	if integration then
		local ok, N = pcall(require, integration)
		if ok and type(N) == "table" and type(N.OpenPage) == "function" then
			N.OpenPage("Decor", slotId)
			return
		end
	end
	local module = modules and modules:FindFirstChild("DecorScreen")
	if module then
		local ok, screenModule = pcall(require, module)
		if ok and type(screenModule) == "table" then
			screenModule.Open(slotId)
		end
	end
end

local function ringGui(p: Part, large: boolean): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DecorMarker"
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(200, 200)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = MARKER_DROP + 10
	gui.Parent = p
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Parent = gui
	local dashes = large and 24 or 14
	for i = 1, dashes do
		local a = (i / dashes) * math.pi * 2
		local dash = Instance.new("Frame")
		dash.AnchorPoint = Vector2.new(0.5, 0.5)
		dash.Position = UDim2.fromScale(0.5 + math.cos(a) * 0.45, 0.5 + math.sin(a) * 0.45)
		dash.Size = UDim2.fromScale(large and 0.07 or 0.12, 0.035)
		dash.Rotation = math.deg(a) + 90
		dash.BorderSizePixel = 0
		dash.BackgroundColor3 = Color3.fromRGB(255, 236, 170)
		dash.BackgroundTransparency = 0.15
		dash.Parent = ring
	end
	local plus = Instance.new("TextLabel")
	plus.Name = "Plus"
	plus.AnchorPoint = Vector2.new(0.5, 0.5)
	plus.Position = UDim2.fromScale(0.5, 0.5)
	plus.Size = UDim2.fromScale(large and 0.22 or 0.45, large and 0.22 or 0.45)
	plus.BackgroundTransparency = 1
	plus.Text = "+"
	plus.TextScaled = true
	plus.Font = Enum.Font.FredokaOne
	plus.TextColor3 = Color3.fromRGB(255, 244, 210)
	plus.TextTransparency = 0.1
	plus:SetAttribute("NoTranslate", true)
	plus.Parent = gui
	return ring
end

local function dropMarker(id: string)
	local m = markers[id]
	if m then
		if m.Tween then
			m.Tween:Cancel()
		end
		m.Part:Destroy()
		markers[id] = nil
	end
end
local function dropAll()
	for id in pairs(markers) do
		dropMarker(id)
	end
end

local function makeMarker(yard: Model, slot: any, cf: CFrame, filled: boolean): Marker
	local large = slot.Size == "Large"
	local size = large and 9 or 2.6
	local p = Instance.new("Part")
	p.Name = "DecorSlot_" .. slot.Id
	p.Size = Vector3.new(size, 0.05, size)
	p.CFrame = cf * CFrame.new(0, 0.22, 0)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, large and 3 or 2.2, 0)
	attachment.Parent = p
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DecorPrompt"
	local ru = russian()
	prompt.ActionText = ru and "УКРАСИТЬ" or "DECORATE"
	prompt.ObjectText = Catalog.SlotName(slot, ru)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = large and 11 or 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = attachment
	prompt.Triggered:Connect(function()
		if markerYard == yard and yard:GetAttribute("OwnerUserId") == player.UserId then
			openDecor(slot.Id)
		end
	end)
	local m: Marker = { Part = p, Prompt = prompt, Ring = nil, Tween = nil, Filled = filled }
	if not filled then
		local ring = ringGui(p, large)
		m.Ring = ring
		if not reduced() then
			local tween = TweenService:Create(ring, TweenInfo.new(14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
			tween:Play()
			m.Tween = tween
		end
	end
	p.Parent = fxFolder
	return m
end

-- The server's EDIT SHOWCASE prompt (Economy.YardCommerce) is drawn by Roblox: localize it here.
local function localizeShowcasePrompt(yard: Model)
	if not russian() then
		return
	end
	local anchor = yard:FindFirstChild("ShowcaseAnchor")
	local prompt = anchor and anchor:FindFirstChild("YardInteraction")
	if prompt and prompt:IsA("ProximityPrompt") and prompt.ActionText == "EDIT SHOWCASE" then
		prompt.ActionText = "ИЗМЕНИТЬ ВИТРИНУ"
		prompt.ObjectText = "МОИ ЛУЧШИЕ НАХОДКИ"
	end
end

local function scanSlots()
	local yard = ownYard()
	if yard ~= markerYard then
		dropAll()
		markerYard = yard
	end
	if yard then
		localizeShowcasePrompt(yard)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local frame = yard and yard:GetAttribute("PlotFrame")
	local sx = yard and yard:GetAttribute("PlotMirror")
	if not (yard and root and root:IsA("BasePart") and typeof(frame) == "CFrame") then
		dropAll()
		return
	end
	local from = root.Position
	for _, slot in ipairs(Catalog.Slots) do
		local cf = Catalog.SlotCFrame(frame, type(sx) == "number" and sx or 1, slot)
		local distance = (cf.Position - from).Magnitude
		local filled = yard:GetAttribute("Decor_" .. slot.Id) ~= nil
		local m = markers[slot.Id]
		if m and (distance > MARKER_DROP or m.Filled ~= filled) then
			dropMarker(slot.Id)
			m = nil
		end
		if not m and distance <= MARKER_RANGE then
			markers[slot.Id] = makeMarker(yard, slot, cf, filled)
		end
	end
end

------------------------------------------------------------------------------------------------
-- Scheduler: one cheap 2 Hz loop for both (no per-frame work while nothing is near).
------------------------------------------------------------------------------------------------
task.spawn(function()
	while true do
		local ok, err = pcall(scanStands)
		if not ok then
			warn("DOGROTS showcase FX: " .. tostring(err))
		end
		ok, err = pcall(scanSlots)
		if not ok then
			warn("DOGROTS decor markers: " .. tostring(err))
		end
		task.wait(0.5)
	end
end)
