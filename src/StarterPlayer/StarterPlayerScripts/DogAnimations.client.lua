local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")
local AnimationPlayer = require(ReplicatedStorage:WaitForChild("DogAnimationPlayer"))
local DogLook = require(ReplicatedStorage:WaitForChild("DogLook"))
local library = ReplicatedStorage:WaitForChild("DogAnimationClips")
local district = workspace:WaitForChild("DOGROTS_District")
local active = district:WaitForChild("03_DogLine"):WaitForChild("ActiveDogs")
local tracked = {}

-- Conveyor and reveal dogs play the clip the server names (AnimationName/StartedAt/Looped/
-- Speed). Kennel dogs get a role ("Work"/"Idle") plus the work timing and run the dig chain
-- of DogAnimationPlayer:UpdateKennel; their status line is written here, every client
-- counting down to the same NextWorkAt (the server no longer rewrites it every second).
local GENERIC_FADE = .25 -- posture changes on the tongue (walk <-> idle, arrival clips)
local CLIENT_STALL = 12 -- a deadline this far in the past means the server stopped ticking
local NEAR = 30 -- always animate dogs this close to the camera, even behind it
local LABEL_DISTANCE = 80 -- kennel labels render within 55 studs (BillboardGui.MaxDistance)
local KENNEL_KEYS = {AnimationName = true, Producing = true, NextWorkAt = true, WorkSequence = true,
    WorkCycle = true, AssignedAt = true, StorageFull = true, FindsFull = true}

-- Kennel status text --------------------------------------------------------------------------
local texts = {
    DIGGING = {"DIGGING"}, FIND_IN = {"DIGGING · FIND IN %ds"}, RESTING = {"RESTING"}, STORAGE_FULL = {"STORAGE FULL"},
    FINDS_FULL = {"DIGGING · FINDS FULL"},
}
do
    local folder = ReplicatedStorage:WaitForChild("Localization", 10)
    local module = folder and folder:FindFirstChild("Animations")
    local ok, dictionary = pcall(function() return module and require(module) end)
    if ok and type(dictionary) == "table" and type(dictionary.Kennel) == "table" then
        for key, row in pairs(dictionary.Kennel) do
            if type(row) == "table" and type(row[1]) == "string" then texts[key] = row end
        end
    end
end
local russian = false
local function readLocale()
    local ok, locale = pcall(function()
        if RunService:IsStudio() then return LocalizationService.RobloxLocaleId end
        local player = Players.LocalPlayer
        return player and player.LocaleId or LocalizationService.RobloxLocaleId
    end)
    russian = ok and type(locale) == "string" and locale:sub(1, 2):lower() == "ru"
end
readLocale()
if Players.LocalPlayer then Players.LocalPlayer:GetPropertyChangedSignal("LocaleId"):Connect(readLocale) end
LocalizationService:GetPropertyChangedSignal("RobloxLocaleId"):Connect(readLocale)
local function text(key, value)
    local row = texts[key]
    local template = russian and row[2] or row[1]
    return if value ~= nil then string.format(template, value) else template
end
local STATUS_COLORS = {
    Digging = Color3.fromRGB(150, 230, 160), Resting = Color3.fromRGB(190, 205, 225), Full = Color3.fromRGB(255, 175, 95),
}

local function isWorking(info, now)
    if info.AnimationName ~= "Work" or info.Producing == false then return false end
    local deadline = info.NextWorkAt
    return not (type(deadline) == "number" and deadline > 0 and now > deadline + CLIENT_STALL)
end

local function updateLabel(entry, now)
    local label = entry.StatusLabel
    if not label or not label.Parent then
        local gui = entry.Model:FindFirstChild("SleepLabel")
        label = gui and gui:FindFirstChild("StatusLabel")
        entry.StatusLabel = label
        if not label or not label:IsA("TextLabel") then return end
    end
    local info, value, color = entry.Info, nil, nil
    if info.Working and info.FindsFull == true then
        -- A full item bag never stops the dig (coins keep coming); it only finds no items.
        value, color = text("FINDS_FULL"), STATUS_COLORS.Full
    elseif info.Working then
        local left = if type(info.NextWorkAt) == "number" then math.ceil(info.NextWorkAt - now) else 0
        value = if left >= 1 and left < 3600 then text("FIND_IN", left) else text("DIGGING")
        color = STATUS_COLORS.Digging
    elseif info.StorageFull == true then
        value, color = text("STORAGE_FULL"), STATUS_COLORS.Full
    else
        value, color = text("RESTING"), STATUS_COLORS.Resting
    end
    if label.Text ~= value then label.Text = value end
    if label.TextColor3 ~= color then label.TextColor3 = color end
end

-- Tracking -------------------------------------------------------------------------------------
local function detach(model)
    local entry = tracked[model]
    if not entry then return end
    tracked[model] = nil
    for _, connection in ipairs(entry.Connections) do connection:Disconnect() end
    entry.Player:Destroy()
end

local function attach(model, kennel)
    if not model:IsA("Model") or tracked[model] then return end
    local dogId = AnimationPlayer.DogIdFor(model:GetAttribute("DogId") or model.Name)
    if not library:FindFirstChild(dogId) then return end
    local animation = AnimationPlayer.new(model,dogId)
    -- Kennel and conveyor rigs are scaled once on the server before they replicate.
    animation.CacheScale = true
    local size = model:GetAttribute("VisualSize")
    local entry = {Model=model,Player=animation,Connections={},Phase=math.random(0,7),Kennel=kennel,
        Radius=if typeof(size) == "Vector3" then size.Magnitude/2 else 6}
    tracked[model] = entry
    local function sync()
        local name = model:GetAttribute("AnimationName")
        if typeof(name) ~= "string" or name == "" then
            -- Nothing to play: hold the last pose (a visible dog never snaps to its bind pose).
            entry.Hold = true
            return
        end
        entry.Hold = false
        local started = model:GetAttribute("AnimationStartedAt") or workspace:GetServerTimeNow()
        if animation.Name ~= name or animation.StartTime ~= started then
            local fade = model:GetAttribute("AnimationFade")
            animation:Play(name,{StartTime=started,Speed=model:GetAttribute("AnimationSpeed") or 1,
                Looped=model:GetAttribute("AnimationLooped"),
                FadeTime=if type(fade) == "number" then fade elseif animation.Clip then GENERIC_FADE else 0})
        elseif animation.Clip then
            animation:SetOptions({Speed=model:GetAttribute("AnimationSpeed") or 1,
                Looped=model:GetAttribute("AnimationLooped")})
        end
    end
    local pending = false
    local function scheduleSync()
        if pending or kennel then return end
        pending = true
        task.defer(function()
            pending = false
            if tracked[model] == entry then sync() end
        end)
    end
    -- One rig refresh per model per frame, however many bones stream in.
    local rigPending = false
    local function refreshRig()
        if rigPending then return end
        rigPending = true
        task.defer(function()
            rigPending = false
            if tracked[model] == entry then animation:RefreshRig(); scheduleSync() end
        end)
    end
    if kennel then
        local info = {}
        for key in pairs(KENNEL_KEYS) do info[key] = model:GetAttribute(key) end
        entry.Info = info
        AnimationPlayer.PreloadChain(dogId)
    end
    table.insert(entry.Connections,model.AttributeChanged:Connect(function(attribute)
        if kennel and KENNEL_KEYS[attribute] then
            entry.Info[attribute] = model:GetAttribute(attribute)
        elseif attribute == "AnimationBaseScale" or attribute == "VisualSize" then
            animation:RefreshScale()
            local visual = model:GetAttribute("VisualSize")
            entry.Radius = if typeof(visual) == "Vector3" then visual.Magnitude/2 else 6
        elseif not kennel and (attribute == "AnimationName" or attribute == "AnimationStartedAt" or attribute == "AnimationSpeed"
            or attribute == "AnimationLooped" or attribute == "LocomotionSpeed") then
            scheduleSync()
        end
    end))
    table.insert(entry.Connections,model.DescendantAdded:Connect(function(child)
        if child:IsA("Bone") then refreshRig() end
    end))
    table.insert(entry.Connections,model.DescendantRemoving:Connect(function(child)
        if child:IsA("Bone") then refreshRig() end
    end))
    table.insert(entry.Connections,model.Destroying:Connect(function() detach(model) end))
    if kennel then
        local now = workspace:GetServerTimeNow()
        entry.Info.Working = isWorking(entry.Info, now)
        animation:UpdateKennel(entry.Info, now, true)
        updateLabel(entry, now)
    else
        sync()
    end
end

local kennels = district:WaitForChild("KennelDogs")
local function watch(folder, kennel)
    folder.ChildAdded:Connect(function(model) attach(model, kennel) end)
    folder.ChildRemoved:Connect(detach)
    for _, model in ipairs(folder:GetChildren()) do attach(model, kennel) end
end
watch(active, false)
watch(kennels, true)
-- Secret arrivals staged off the tongue (SecretReveal); the server creates the folder.
local reveals = workspace:FindFirstChild("DOGROTS_SecretReveals")
if reveals then watch(reveals, false) else
    local waiting
    waiting = workspace.ChildAdded:Connect(function(child)
        if child.Name == "DOGROTS_SecretReveals" and child:IsA("Folder") then waiting:Disconnect(); watch(child, false) end
    end)
end

-- Bone animation for every kennel and conveyor dog each frame is the heaviest client loop in
-- the game. Off-screen dogs are not sampled (unless a crossfade is still running), distant
-- dogs update at a lower rate (gait time stays continuous) and the world-event state is
-- read once per frame. Kennel decisions still run for every dog so timing stays exact.
local function viewHalfAngle(camera)
    if not camera then return math.pi end
    local vertical = math.rad(math.clamp(camera.FieldOfView, 1, 120)) / 2
    local viewport = camera.ViewportSize
    local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
    -- The screen's corner direction plus a margin: dogs entering the view are already posed.
    local half = math.atan(math.tan(vertical) * math.sqrt(1 + aspect * aspect)) + math.rad(12)
    return half
end
local frame = 0
local nextLabels = 0
RunService.PreSimulation:Connect(function()
    debug.profilebegin("DogAnimations")
    frame += 1
    local now = workspace:GetServerTimeNow()
    AnimationPlayer.EventFrame(now)
    AnimationPlayer.PumpPreload(1)
    local camera = workspace.CurrentCamera
    local cameraFrame = camera and camera.CFrame
    local origin = cameraFrame and cameraFrame.Position
    local forward = cameraFrame and cameraFrame.LookVector
    local halfAngle = viewHalfAngle(camera)
    local labels = now >= nextLabels
    if labels then nextLabels = now + .25 end
    for model, entry in pairs(tracked) do
        local root = model.PrimaryPart
        local position = if root then root.Position else model:GetPivot().Position
        local distance, visible = 0, true
        if origin then
            local offset = position - origin
            distance = offset.Magnitude
            if distance > NEAR then
                local slack = math.asin(math.min(1, entry.Radius / distance))
                visible = offset:Dot(forward) / distance >= math.cos(math.min(math.pi, halfAngle + slack))
            end
        end
        local animation = entry.Player
        if entry.Kennel then
            debug.profilebegin("DogAnimations.Kennel")
            entry.Info.Working = isWorking(entry.Info, now)
            animation:UpdateKennel(entry.Info, now, visible)
            if labels and distance <= LABEL_DISTANCE then updateLabel(entry, now) end
            debug.profileend()
        end
        local interval = 1
        if distance > 320 then interval = 8 elseif distance > 160 then interval = 3 end
        -- THE DOG's stare (DogLook): dogs turn on every frame, then hold at the usual rate.
        local body, head, target, bow, moving
        if DogLook.Current then
            moving = (model:GetAttribute("LocomotionSpeed") or 0) > .1
            body, head, target, bow = DogLook.For(model, entry, position, moving)
        end
        if body then
            local look = entry.Look or {}
            look.Target, look.Body, look.Head, look.Bow = target, body, head, bow
            entry.Look = look
            animation.Look = look
            -- Settled once the turn is done and the walking cap (DogLook's MoveScale) has eased.
            local cap = entry.MoveScale or 1
            if head < 1 or bow ~= 0 or body < cap - 1e-3 or cap ~= (moving and .4 or 1) then interval = 1 end
        elseif animation.Look then
            animation.Look = nil
            interval = 1
        end
        if not entry.Hold and (visible or animation.BlendFrom ~= nil)
            and (interval == 1 or (frame + entry.Phase) % interval == 0) then
            debug.profilebegin("DogAnimations.Step")
            animation:Step(now)
            debug.profileend()
        end
    end
    debug.profileend()
end)
