-- Sampled source motion in the imported Bone.CFrame bind space.
-- Clips are shared; playback, transitions and recovery belong to each model.
--
-- Roles: Idle, Walk, Work (= Loop) and the kennel dig chain Start, End, Find, Action.
-- Every role resolves ReplicatedStorage.DogDigProfiles > the clip folder's <Role>Clip
-- attribute > the candidate names below (see Player.ResolveName / Player.Chain).
-- Play options: StartTime, Speed, Looped, FadeTime (crossfade seconds, default .18 after a
-- clip), MatchFrom (enter a looped clip at the frame closest to the current pose), Next =
-- {name, options} (played when this one-shot ends), NoStep (do not sample immediately).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = ReplicatedStorage:WaitForChild("DogAnimationClips")
local WalkGait = require(ReplicatedStorage:WaitForChild("DogWalkGait"))
local Player = {}
Player.__index = Player
local cache = {}
local failed = {}
local roleCandidates = {
    Idle = {"Idle", "IDLE", "Sleep", "Idle_Day", "Idle_Night"},
    Walk = {"Walk", "WALK", "Waddle", "Levitate_Walk"},
    Work = {"DigLoop", "DIG_LOOP", "Dig_Loop", "Dig", "DIG_WAVE", "Dig_Cast", "Drinking"},
    Start = {"DigStart", "Dig_Start", "DIG_START"},
    End = {"DigEnd", "Dig_End", "DIG_END"},
    Find = {"DigFind", "Find"},
    Action = {},
}
roleCandidates.Loop = roleCandidates.Work
Player.RoleCandidates = roleCandidates
-- Names that resolve as a role before an exact clip of that name (the original protocol).
local implicitRoles = {Idle = true, Walk = true, Work = true}
local DEFAULT_FADES = {Start = .25, Loop = .15, Direct = .35, Accent = .2, Return = .2, End = .2, Idle = .3, Stop = .35}
local HOP_FADE = .1 -- between the clips of one authored sequence (their poses already join)
local START_WINDOW = 2.5 -- a kennel model younger than this plays its DigStart
local END_WAIT = 3.5 -- the longest wait for a loop boundary before DigEnd
local MAX_ACCENT = 12 -- accents are authored <= DogDigProfiles.MinCycle; never schedule longer
local MAX_ADAPTIVE_FADE = .7 -- AdaptiveFade: a posture change of 105 degrees or more fades this long
local DEGREES_PER_SECOND = 150
local SEAMLESS_DEGREES = 3 -- AdaptiveFade: a join this close is cut, not blended
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function smooth(a) a = math.clamp(a, 0, 1); return a * a * (3 - 2 * a) end
local function angleOf(cf)
    local _, angle = cf:ToAxisAngle()
    angle = math.abs(angle) % (2 * math.pi)
    return if angle > math.pi then 2 * math.pi - angle else angle
end

local Profiles = {Dogs = {}, Fades = DEFAULT_FADES}
do
    local module = ReplicatedStorage:WaitForChild("DogDigProfiles", 10)
    local ok, loaded = pcall(function() return module and require(module) end)
    if ok and type(loaded) == "table" and type(loaded.Dogs) == "table" then
        Profiles = loaded
    elseif module then
        warn("DogDigProfiles unavailable", loaded)
    end
end
Player.Profiles = Profiles

local function folderOf(dogId)
    return type(dogId) == "string" and Library:FindFirstChild(dogId) or nil
end
local function hasClip(folder, name)
    local source = type(name) == "string" and folder:FindFirstChild(name)
    return source ~= nil and source ~= false and source:IsA("ModuleScript")
end
local function listOf(value)
    if type(value) == "string" then return {value} end
    if type(value) == "table" then return value end
    return nil
end
local function profileKey(role)
    return if role == "Work" then "Loop" else role
end

function Player.ResolveName(dogId, role)
    local folder = folderOf(dogId)
    if not folder then return nil end
    local profile = Profiles.Dogs[dogId]
    if profile then
        local value = profile[profileKey(role)]
        if value == false then return nil end
        local list = listOf(value)
        if list and hasClip(folder, list[1]) then return list[1] end
    end
    local mapped = folder:GetAttribute((if role == "Loop" then "Work" else role) .. "Clip")
    if type(mapped) == "string" and hasClip(folder, mapped) then return mapped end
    for _, name in ipairs(roleCandidates[role] or {role}) do
        if hasClip(folder, name) then return name end
    end
    return nil
end

-- Every clip of a role, in play order (a profile may list a sequence of authored clips).
function Player.ResolveChain(dogId, role)
    local folder = folderOf(dogId)
    if not folder then return nil end
    local profile = Profiles.Dogs[dogId]
    local value = profile and profile[profileKey(role)]
    if value == false then return nil end
    local list = listOf(value)
    if list then
        local names = {}
        for _, name in ipairs(list) do
            if hasClip(folder, name) then table.insert(names, name) end
        end
        if #names == #list and #names > 0 then return names end
    end
    local single = Player.ResolveName(dogId, role)
    return single and {single} or nil
end

-- The kennel dig chain of a dog: {Idle, Loop, Start?, End?, Accent?, Repeat, Every, Fades}.
local chains = {}
function Player.Chain(dogId)
    local cached = chains[dogId]
    if cached ~= nil then return cached or nil end
    if not folderOf(dogId) then chains[dogId] = false; return nil end
    local profile = Profiles.Dogs[dogId] or {}
    local fades = table.clone(DEFAULT_FADES)
    for key, value in pairs(Profiles.Fades or {}) do if finite(value) then fades[key] = value end end
    for key, value in pairs(type(profile.Fade) == "table" and profile.Fade or {}) do if finite(value) then fades[key] = value end end
    local action = Player.ResolveChain(dogId, "Action")
    local chain = {
        Idle = Player.ResolveName(dogId, "Idle"),
        Loop = Player.ResolveName(dogId, "Work"),
        Start = Player.ResolveChain(dogId, "Start"),
        End = Player.ResolveChain(dogId, "End"),
        Accent = action or Player.ResolveChain(dogId, "Find"),
        Repeat = action ~= nil and profile.Repeat == true,
        Every = if action then 1 else math.max(1, math.floor(tonumber(profile.FindEvery) or 1)),
        Fades = fades,
    }
    chain.Loop = chain.Loop or chain.Idle
    chain.Idle = chain.Idle or chain.Loop
    -- Clips that may sink the hind paws while digging get the ground lift (see ComputeLift).
    chain.Lifted = {}
    for _, list in ipairs({{chain.Loop}, chain.Start or {}, chain.End or {}, chain.Accent or {}}) do
        for _, name in ipairs(list) do if name ~= chain.Idle then chain.Lifted[name] = true end end
    end
    chains[dogId] = chain
    return chain
end

-- A clip name passed by a VisualAsset-named caller (MenuModels clones) maps to its economy Id.
local visualIds
function Player.DogIdFor(name)
    if type(name) ~= "string" or folderOf(name) then return name end
    if not visualIds then
        visualIds = {}
        local ok, definitions = pcall(function()
            return require(ReplicatedStorage:WaitForChild("DogEconomy"):WaitForChild("DogDefinitions"))
        end)
        if ok and type(definitions) == "table" then
            for id, definition in pairs(definitions) do
                if type(definition) == "table" and type(definition.VisualAsset) == "string" then visualIds[definition.VisualAsset] = id end
            end
        end
    end
    return visualIds[name] or name
end

local function sourceFor(dogId, name)
    local folder = folderOf(dogId)
    if not folder or type(name) ~= "string" then return nil end
    local resolved = if implicitRoles[name] then Player.ResolveName(dogId, name) else nil
    if not resolved and hasClip(folder, name) then resolved = name end
    resolved = resolved or Player.ResolveName(dogId, name)
    if not resolved then return nil end
    return folder:FindFirstChild(resolved), resolved
end

local SEAM_ANGLE, SEAM_POSITION = .02, .01
local function loadClip(dogId, name)
    local source, resolved = sourceFor(dogId, name)
    if not source then return nil end
    if cache[source] then return cache[source] end
    if failed[source] then return nil end
    local ok, raw = pcall(require, source)
    if not ok or type(raw) ~= "table" or not finite(raw.duration) or raw.duration <= 0
        or not finite(raw.fps) or raw.fps <= 0 or type(raw.tracks) ~= "table" then
        failed[source] = true
        warn("Invalid dog clip", dogId, resolved)
        return nil
    end
    local clip = {Duration = raw.duration, Looped = raw.loop == true, FPS = raw.fps,
        Tracks = {}, Hidden = raw.hidden, SourceName = resolved, Frames = 0, Extent = 0}
    for bone, values in pairs(raw.tracks) do
        local frames = table.create(#values)
        for i, value in ipairs(values) do
            if #value ~= 7 then failed[source] = true; return nil end
            for _, n in ipairs(value) do if not finite(n) then failed[source] = true; return nil end end
            local q = math.sqrt(value[4]^2 + value[5]^2 + value[6]^2 + value[7]^2)
            if q < .00001 then failed[source] = true; return nil end
            frames[i] = CFrame.new(value[1], value[2], value[3], value[4]/q, value[5]/q, value[6]/q, value[7]/q)
            clip.Extent = math.max(clip.Extent, math.abs(value[1]), math.abs(value[2]), math.abs(value[3]))
        end
        if #frames > 0 then clip.Tracks[bone] = frames; clip.Frames = math.max(clip.Frames, #frames) end
    end
    -- A closed seam (last frame == first frame on every track, same visibility) repeats
    -- without the recovery blend, which would otherwise hold the pose for a moment.
    local closed = true
    for bone, frames in pairs(clip.Tracks) do
        local first, last = frames[1], frames[#frames]
        if (first.Position - last.Position).Magnitude > SEAM_POSITION * math.max(1, clip.Extent)
            or angleOf(first:Inverse() * last) > SEAM_ANGLE then closed = false; break end
        local visibility = clip.Hidden and clip.Hidden[bone]
        if type(visibility) == "table" and visibility[1] ~= visibility[#visibility] then closed = false; break end
    end
    clip.SeamClosed = closed
    cache[source] = clip
    return clip
end
Player.LoadClip = loadClip

-- One clip decode per call, so a new dog's whole chain loads over a few frames instead of
-- one long hitch on first use (the large clips take 10-20 ms each on desktop).
local preloadQueue, preloadHead, preloadTail = {}, 1, 0
function Player.Preload(dogId, names)
    for _, name in ipairs(names or {}) do
        preloadTail += 1
        preloadQueue[preloadTail] = {dogId, name}
    end
end
function Player.PreloadChain(dogId)
    local chain = Player.Chain(dogId)
    if not chain then return end
    local names = {chain.Loop, chain.Idle}
    for _, list in ipairs({chain.Start or {}, chain.End or {}, chain.Accent or {}}) do
        for _, name in ipairs(list) do table.insert(names, name) end
    end
    Player.Preload(dogId, names)
end
function Player.PumpPreload(count)
    count = count or 1
    while count > 0 and preloadHead <= preloadTail do
        local item = preloadQueue[preloadHead]
        preloadQueue[preloadHead] = nil
        preloadHead += 1
        local source = sourceFor(item[1], item[2])
        if source and not cache[source] and not failed[source] then
            loadClip(item[1], item[2])
            count -= 1
        end
    end
    if preloadHead > preloadTail then preloadHead, preloadTail = 1, 0 end
    return preloadTail - preloadHead + 1
end

-- True once every named clip is decoded (or known to be broken): no first-use hitch left.
function Player.IsLoaded(dogId, names)
    for _, name in ipairs(names or {}) do
        local source = sourceFor(dogId, name)
        if source and not cache[source] and not failed[source] then return false end
    end
    return true
end

-- Seconds of a sequence of clips at x1.0 (nil when one of them cannot be loaded).
function Player.SequenceDuration(dogId, names)
    local total = 0
    for _, name in ipairs(names or {}) do
        local clip = loadClip(dogId, name)
        if not clip then return nil end
        total += clip.Duration
    end
    return total
end

function Player.GetWorkSpeed(dogId, name, workDuration)
    local clip = loadClip(dogId, name)
    if not clip or clip.Looped or not finite(workDuration) or workDuration <= 0 then return 1 end
    local recovery = if clip.SeamClosed then 0 else math.clamp(clip.Duration * .2, .2, .6)
    -- Complete the authored action AND its recovery before the work window ends.
    -- Shorter actions keep their original cadence; true loops keep their speed.
    return math.max(1, (clip.Duration + recovery) / workDuration)
end

function Player.new(model, dogId)
    local self = setmetatable({Model = model, DogId = Player.DogIdFor(dogId or model:GetAttribute("DogId") or model.Name),
        Bones = {}, BoneGroups = {}, AllBones = {}, HiddenBones = {}, PreLook = {}}, Player)
    self:RefreshRig()
    return self
end

-- Scale of the rig relative to the clips' template scale, and its visible height. Players
-- driven by DogAnimations cache these (CacheScale) and refresh them on change; the others
-- re-read them every sample as before.
function Player:RefreshScale()
    local baseScale = self.Model:GetAttribute("AnimationBaseScale") or 1
    self.ScaleFactor = self.Model:GetScale() / math.max(baseScale, .00001)
    local size = self.Model:GetAttribute("VisualSize")
    self.VisualHeight = if typeof(size) == "Vector3" then size.Y else nil
    return self.ScaleFactor
end
function Player:GetScaleFactor()
    if self.CacheScale and self.ScaleFactor then return self.ScaleFactor end
    local baseScale = self.Model:GetAttribute("AnimationBaseScale") or 1
    return self.Model:GetScale() / math.max(baseScale, .00001)
end

function Player:RefreshRig()
    table.clear(self.Bones); table.clear(self.BoneGroups); table.clear(self.AllBones)
    for _, child in ipairs(self.Model:GetDescendants()) do
        if child:IsA("Bone") then
            self.Bones[child.Name] = self.Bones[child.Name] or child
            local group = self.BoneGroups[child.Name] or {}
            self.BoneGroups[child.Name] = group
            table.insert(group, child); table.insert(self.AllBones, child)
        end
    end
    local depths = {}
    for _, bone in ipairs(self.AllBones) do
        local ancestor, depth = bone.Parent, 0
        while ancestor and ancestor ~= self.Model do depth += 1; ancestor = ancestor.Parent end
        depths[bone] = depth
    end
    table.sort(self.AllBones, function(a,b) return depths[a] < depths[b] end)
    -- Look targets: the single top bone (turns the whole skinned dog), neck and heads.
    self.TopBone = nil
    for _, bone in ipairs(self.AllBones) do
        if bone.Parent and bone.Parent:IsA("BasePart") then self.TopBone = bone; break end
    end
    self.LookHeads = {}
    for name, group in pairs(self.BoneGroups) do
        local lower = string.lower(name)
        if lower == "head" or lower == "head_c" or lower == "head_l" or lower == "head_r" or string.match(lower, "^pup_%d+_head$") then
            for _, bone in ipairs(group) do table.insert(self.LookHeads, bone) end
        end
    end
    self.LookNeck = self.Bones.Neck or self.Bones.neck
    self:CollectParts()
    self:RefreshScale()
    -- Bones can stream in after the first measurement; measure again with the full rig
    -- (the lift cache is keyed by the bone count, so a partial rig never poisons it).
    if self.Clip then self.Lift = if self:UsesLift(self.Clip) then self:ComputeLift(self.Clip) else nil end
    if self.Clip then
        local previous=self.Gait
        self.Gait=WalkGait.new(self)
        if self.Gait and previous then
            for _,key in ipairs({"Phase","LastTime","FitSpeed","FitFrequency","RollDistance"}) do self.Gait[key]=previous[key] end
        end
    end
end

-- Part-built dogs (DogPartRig, e.g. the NIGHT OF THE BURIED MOON event dogs): bones only deform skinned meshes,
-- so every BasePart with the attributes DogBone (bone name) and DogBoneOffset (its CFrame in that bone's rest space,
-- template units) is moved with its bone by ApplyParts (anchored copies: kennels, previews, reveals, cinematics).
-- Models without the DogPartRig attribute keep the plain bones-only path at no cost.
-- Level of detail (client, Step only; Sample / Stop / viewports / no camera always move every part):
--   * parts follow their bones every frame within PART_FULL studs of the camera, at PART_NEAR_HZ up to PART_NEAR, at
--     PART_MID_HZ up to PART_MID, at PART_FAR_HZ beyond, and not at all while the dog is behind the camera; throttled
--     rigs start out of step, and beyond PART_NEAR they share a per-frame part budget (a rig over
--     budget waits a frame);
--   * tiny DogDetail trims are hidden (LocalTransparencyModifier) and not moved beyond PART_DETAIL_RANGE or on Low;
--   * baked DogLight lights (their parent carries SelfManagedFX, so WorldDetailQuality leaves them alone; saved
--     Enabled = false) shine only within PART_LIGHT_RANGE and never on Low quality.
-- Low quality = the base rule of WorldDetailQuality: WorldEventFX "Low", or unset on a touch device, or LowFX.
local PART_FULL, PART_NEAR, PART_MID, PART_NEAR_HZ, PART_MID_HZ, PART_FAR_HZ = 20, 40, 90, 30, 15, 5
local PART_DETAIL_RANGE, PART_LIGHT_RANGE, PART_BUDGET = 50, 40, 1600
Player.PartLOD = {Full = PART_FULL, Near = PART_NEAR, Mid = PART_MID, NearHz = PART_NEAR_HZ, MidHz = PART_MID_HZ,
    FarHz = PART_FAR_HZ, Detail = PART_DETAIL_RANGE,
    Light = PART_LIGHT_RANGE, Budget = PART_BUDGET}
Player.PartStats = {Moved = 0, Applies = 0, Skipped = 0} -- running totals (tests / profiling)
local partFrame = {Now = nil, Moved = 0}
local partQuality = {At = -math.huge, Low = false}
local function partLow()
    local t = os.clock()
    if t - partQuality.At > 1 then
        partQuality.At = t
        local ok, low = pcall(function()
            local player = game:GetService("Players").LocalPlayer
            if not player then return false end
            local choice = player:GetAttribute("WorldEventFX")
            return choice == "Low" or (choice == nil and game:GetService("UserInputService").TouchEnabled)
                or player:GetAttribute("LowFX") == true
        end)
        partQuality.Low = ok and low == true
    end
    return partQuality.Low
end
Player.PartLow = partLow

function Player:CollectParts()
    if self.Model:GetAttribute("DogPartRig") ~= true then
        self.RigParts = nil
        return
    end
    local list = self.RigParts or {}
    table.clear(list)
    local lights = {}
    for _, part in ipairs(self.Model:GetDescendants()) do
        if part:IsA("BasePart") then
            local name = part:GetAttribute("DogBone")
            local bone = type(name) == "string" and self.Bones[name] or nil
            local offset = bone and part:GetAttribute("DogBoneOffset")
            if typeof(offset) == "CFrame" then
                table.insert(list, {Part = part, Bone = bone, Name = name, Offset = offset, Anchored = part.Anchored,
                    Detail = part:GetAttribute("DogDetail") == true})
            end
        elseif part:IsA("Light") and part:GetAttribute("DogLight") then
            table.insert(lights, part)
        end
    end
    self.RigParts = list
    self.RigLights = lights
    self.PartScale = nil -- scaled offsets are rebuilt on the next apply
    self.DetailShown, self.LightsOn = nil, nil
    -- Parts that stream in later join on the next frame; parts that leave drop out.
    if not self.PartWatch then
        local function recollect(child)
            if self.PartsPending or not child:IsA("BasePart") or child:GetAttribute("DogBone") == nil then return end
            self.PartsPending = true
            task.defer(function()
                self.PartsPending = false
                if self.RigParts and self.Model.Parent then self:CollectParts() end
            end)
        end
        self.PartWatch = self.Model.DescendantAdded:Connect(recollect)
        self.PartLeave = self.Model.DescendantRemoving:Connect(recollect)
    end
end

-- LOD toggles: tiny trims shown / hidden, baked lights on / off (only on a change)
function Player:SetPartDetail(shown)
    if self.DetailShown == shown then return end
    self.DetailShown = shown
    local modifier = if shown then 0 else 1
    for _, r in ipairs(self.RigParts or {}) do
        if r.Detail then pcall(function() r.Part.LocalTransparencyModifier = modifier end) end
    end
end
function Player:SetPartLights(on)
    if self.LightsOn == on then return end
    self.LightsOn = on
    for _, light in ipairs(self.RigLights or {}) do
        if light.Parent then light.Enabled = on end
    end
end

-- now = the Step time (seconds); force = move every part now (Sample outside Step, Stop).
function Player:ApplyParts(now, force)
    local list = self.RigParts
    if not list or #list == 0 then return end
    local detail = true
    local far, lod = false, false
    local inWorld = self.Model:IsDescendantOf(workspace)
    if not force and now and inWorld then
        local camera = workspace.CurrentCamera
        local root = self.Model.PrimaryPart
        if camera and root then
            local eye = camera.CFrame
            local offset = root.CFrame.Position - eye.Position
            local dist = offset.Magnitude
            local low = Player.PartLow() -- (a field, so tests / settings can override it)
            self:SetPartLights(not low and dist <= PART_LIGHT_RANGE)
            detail = not low and dist <= PART_DETAIL_RANGE
            if dist > 12 and eye.LookVector:Dot(offset / dist) < .2 then
                Player.PartStats.Skipped += 1
                return -- behind the camera: the pose catches up when it comes back into view
            end
            local interval = if dist <= PART_FULL then 0 elseif dist <= PART_NEAR then 1 / PART_NEAR_HZ
                elseif dist <= PART_MID then 1 / PART_MID_HZ else 1 / PART_FAR_HZ
            local last = self.PartsAt
            if interval > 0 and last and now >= last and now - last < interval then
                Player.PartStats.Skipped += 1
                return
            end
            if partFrame.Now ~= now then partFrame.Now, partFrame.Moved = now, 0 end
            lod = true
            far = dist > PART_NEAR
            if far and partFrame.Moved >= PART_BUDGET then
                Player.PartStats.Skipped += 1
                return
            end
        end
    end
    self:SetPartDetail(detail)
    -- a random phase on the first throttled apply keeps rigs out of step (no frame where every far dog moves at once)
    self.PartsAt = if lod and far and not self.PartsAt then now - math.random() / PART_MID_HZ else now
    local scale = self:GetScaleFactor()
    if self.PartScale ~= scale then
        -- offsets in the rig's current scale, rebuilt only when the scale changes
        self.PartScale = scale
        for _, r in ipairs(list) do
            local o = r.Offset
            r.Scaled = if scale == 1 then o else CFrame.new(o.Position * scale) * o.Rotation
        end
    end
    local world = self.PartWorld or {}
    self.PartWorld = world
    table.clear(world)
    -- AllBones is sorted by depth: every parent is solved before its children (part rigs have unique bone names).
    for _, bone in ipairs(self.AllBones) do
        local parent = bone.Parent
        if parent then
            local base = if parent:IsA("Bone") then world[parent.Name] elseif parent:IsA("BasePart") then parent.CFrame else nil
            if base then world[bone.Name] = base * bone.CFrame * bone.Transform end
        end
    end
    local parts, frames = self.MoveParts or {}, self.MoveFrames or {}
    self.MoveParts, self.MoveFrames = parts, frames
    local n = 0
    for _, r in ipairs(list) do
        local frame = world[r.Name]
        if frame and r.Anchored and (detail or not r.Detail) then
            n += 1
            parts[n] = r.Part
            frames[n] = frame * r.Scaled
        end
    end
    for i = n + 1, #parts do parts[i] = nil; frames[i] = nil end
    if n == 0 then return end
    Player.PartStats.Moved += n
    Player.PartStats.Applies += 1
    if lod then partFrame.Moved += n end
    local moved = false
    if inWorld then
        self.BulkMove = self.BulkMove or function()
            workspace:BulkMoveTo(self.MoveParts, self.MoveFrames, Enum.BulkMoveMode.FireCFrameChanged)
        end
        moved = pcall(self.BulkMove)
    end
    if not moved then
        for i = 1, n do
            local part = parts[i]
            if part.Parent then part.CFrame = frames[i] end
        end
    end
end

function Player:GetClipNames()
    local names = {}
    local folder = Library:FindFirstChild(self.DogId)
    if folder then
        for _, source in ipairs(folder:GetChildren()) do
            if source:IsA("ModuleScript") then table.insert(names, source.Name) end
        end
    end
    table.sort(names)
    return names
end

function Player:Stop()
    table.clear(self.PreLook)
    self.Clip, self.Name, self.BlendFrom = nil, nil, nil
    self.Gait = nil
    self.Queue = nil
    table.clear(self.HiddenBones)
    for _, bone in ipairs(self.AllBones) do
        if bone.Parent then bone.Transform = CFrame.identity end
    end
    self:ApplyParts(nil, true)
end

function Player:SetOptions(options)
    local speed = finite(options.Speed) and math.clamp(options.Speed, .05, 5) or 1
    if self.Speed and self.Speed ~= speed then
        local elapsed = math.max(0, workspace:GetServerTimeNow() - self.StartTime)
        self.PhaseOffset = (self.PhaseOffset or 0) + elapsed * (self.Speed - speed)
    end
    self.Speed = speed
    self.Looped = if options.Looped == nil then self.Clip.Looped else options.Looped == true
    -- A one-shot has an authored exit pose. Preserve the entire action, then
    -- recover smoothly before repeating it in a kennel (never teleport at wrap).
    -- A one-shot whose last frame is its first repeats directly.
    self.Recovery = if self.Looped and not self.Clip.Looped and not self.Clip.SeamClosed
        then math.clamp(self.Clip.Duration * .2, .2, .6) else 0
end

-- Seconds into the clip (x Speed), before wrapping.
function Player:Elapsed(now)
    if not self.Clip then return 0 end
    now = now or workspace:GetServerTimeNow()
    return math.max(0, (now - self.StartTime) * (self.Speed or 1) + (self.PhaseOffset or 0))
end
-- A one-shot that is not looped is done once its last frame is reached (it then holds it).
function Player:IsDone(now)
    if not self.Clip then return true end
    if self.Looped then return false end
    return self:Elapsed(now) >= self.Clip.Duration
end
-- Seconds until a one-shot ends, or until the current repetition of a looped clip ends.
function Player:Remaining(now)
    if not self.Clip then return 0 end
    local elapsed = self:Elapsed(now)
    local speed = self.Speed or 1
    if not self.Looped then return math.max(0, self.Clip.Duration - elapsed) / speed end
    local period = self.Clip.Duration + (self.Recovery or 0)
    return (period - elapsed % period) / speed
end

-- Some dig clips lower the whole rig (root and hind paws) below the bind pose, which
-- pushed those dogs into the ground while digging. Measure, per frame, how far the hind
-- paws drop below their resting height and lift the rig by that amount. Deliberate
-- dives (sharks swimming through the dirt) drop far deeper and are left untouched.
-- The result depends only on the breed, the clip and the rig's scale, so five kennels of
-- the same dog measure it once.
local liftCache = setmetatable({}, {__mode = "k"})
function Player:UsesLift(clip)
    local chain = Player.Chain(self.DogId)
    if chain and chain.Lifted[clip.SourceName] then return true end
    return Player.ResolveName(self.DogId, "Work") == clip.SourceName
end
function Player:ComputeLift(clip)
    local bones = {}
    for _, bone in ipairs(self.AllBones) do if bone.Parent then table.insert(bones, bone) end end
    local ok, key = pcall(function()
        local size = self.Model:GetAttribute("VisualSize")
        return string.format("%s|%d|%.4f|%.3f", tostring(self.DogId), #bones, self:GetScaleFactor(), typeof(size) == "Vector3" and size.Y or -1)
    end)
    if not ok then return nil end
    local byClip = liftCache[clip]
    if byClip and byClip[key] ~= nil then return byClip[key] or nil end
    byClip = byClip or {}; liftCache[clip] = byClip
    local measured, lift = pcall(function()
        local pivot = self.Model:GetPivot()
        local scale = self:GetScaleFactor()
        if #bones < 4 then return false end
        local function pose(frame)
            local world = {}
            for _, bone in ipairs(bones) do
                local parent = bone.Parent
                local parentFrame = world[parent] or (parent:IsA("BasePart") and parent.CFrame) or nil
                if not parentFrame then return nil end
                local transform = CFrame.identity
                local frames = frame and clip.Tracks[bone.Name]
                if frames then
                    local p = frames[math.min(frame, #frames)]
                    transform = CFrame.new(p.Position * scale) * p.Rotation
                end
                world[bone] = parentFrame * bone.CFrame * transform
            end
            return world
        end
        local rest = pose(nil)
        if not rest then return false end
        local low, high = math.huge, -math.huge
        local candidates = {}
        for _, bone in ipairs(bones) do
            local p = pivot:PointToObjectSpace(rest[bone].Position)
            low, high = math.min(low, p.Y), math.max(high, p.Y)
            if bone.Parent:IsA("Bone") then table.insert(candidates, {Bone = bone, Y = p.Y, Z = p.Z}) end
        end
        local height = math.max((self.Model:GetAttribute("VisualSize") or Vector3.new(0, high - low, 0)).Y, .1)
        if #candidates < 4 then return false end
        table.sort(candidates, function(a, b) return a.Y < b.Y end)
        local paws = {candidates[1], candidates[2], candidates[3], candidates[4]}
        table.sort(paws, function(a, b) return a.Z > b.Z end)
        local hind = {paws[1], paws[2]}
        local frameCount = 0
        for _, frames in pairs(clip.Tracks) do frameCount = math.max(frameCount, #frames) end
        local values, worst = table.create(frameCount, 0), 0
        for f = 1, frameCount do
            local world = pose(f)
            if not world then return false end
            -- Both hind paws must be below rest: one paw scooping dirt is a normal dig.
            local drop = math.huge
            for _, paw in ipairs(hind) do
                drop = math.min(drop, paw.Y - pivot:PointToObjectSpace(world[paw.Bone].Position).Y)
            end
            values[f] = math.max(0, drop - height * .01)
            worst = math.max(worst, values[f])
        end
        if worst < height * .02 or worst > height * .25 then return false end
        return values
    end)
    byClip[key] = measured and lift or false
    return byClip[key] or nil
end

-- Phase matching: the frame of `clip` whose body pose (root, spine, neck, head and legs)
-- is closest to `pose` (bone -> Transform). Used to enter a loop without a visible jump
-- when the previous clip ends somewhere else in the loop's cycle.
local coreCache = setmetatable({}, {__mode = "k"})
local CORE_PATTERNS = {"^root$", "^body$", "^hips?$", "^pelvis$", "^chest$", "^torso$", "^spine", "^neck", "^head$",
    "leg", "shin", "paw", "foot", "thigh", "^front", "^rear", "upper", "lower"}
local function coreNames(clip)
    local names = coreCache[clip]
    if names then return names end
    names = {}
    for name in pairs(clip.Tracks) do
        local lower = string.lower(name)
        for _, pattern in ipairs(CORE_PATTERNS) do
            if string.find(lower, pattern) then table.insert(names, name); break end
        end
    end
    if #names < 3 then
        names = {}
        for name in pairs(clip.Tracks) do table.insert(names, name) end
    end
    table.sort(names)
    while #names > 24 do table.remove(names) end
    coreCache[clip] = names
    return names
end
Player.CoreNames = coreNames
-- With `sourceClip` (a one-shot that has just ended) its authored last frame is the pose:
-- the result is the same for every dog of the breed and is cached; otherwise the current
-- bone transforms are compared.
local matchCache = setmetatable({}, {__mode = "k"})
-- The body pose to compare against `clip`, per track name in template space (`all` compares
-- every track of the clip instead of the body bones).
function Player:CorePose(clip, pose, sourceClip, all)
    local current = {}
    local names = coreNames(clip)
    if all then
        names = {}
        for name in pairs(clip.Tracks) do table.insert(names, name) end
    end
    if sourceClip then
        for _, name in ipairs(names) do
            local frames = sourceClip.Tracks[name]
            current[name] = if frames then frames[#frames] else CFrame.identity
        end
    else
        local scale = math.max(self:GetScaleFactor(), .00001)
        for _, name in ipairs(names) do
            local bone = self.Bones[name]
            local cf = bone and pose[bone]
            if cf then current[name] = CFrame.new(cf.Position / scale) * cf.Rotation end
        end
    end
    return current
end
-- Largest body-bone rotation (degrees) between `current` (CorePose) and frame `index` of clip.
function Player.PoseGap(clip, index, current)
    local worst = 0
    for name, cf in pairs(current) do
        local frames = clip.Tracks[name]
        if frames then worst = math.max(worst, angleOf(cf.Rotation:Inverse() * frames[math.clamp(index, 1, #frames)].Rotation)) end
    end
    return math.deg(worst)
end
function Player:MatchPhase(clip, pose, sourceClip)
    local byTarget = sourceClip and matchCache[clip]
    if byTarget and byTarget[sourceClip] then return byTarget[sourceClip] end
    local weight = 1 / math.max(clip.Extent, .001)
    local current = self:CorePose(clip, pose, sourceClip)
    if next(current) == nil then return nil end
    local best, bestIndex = math.huge, 1
    for index = 1, clip.Frames do
        local cost = 0
        for name, cf in pairs(current) do
            local frames = clip.Tracks[name]
            local target = frames[math.min(index, #frames)]
            cost += angleOf(cf.Rotation:Inverse() * target.Rotation) + (cf.Position - target.Position).Magnitude * weight
            if cost >= best then break end
        end
        if cost < best then best, bestIndex = cost, index end
    end
    local phase = (bestIndex - 1) / clip.FPS
    if sourceClip then
        matchCache[clip] = matchCache[clip] or setmetatable({}, {__mode = "k"})
        matchCache[clip][sourceClip] = phase
    end
    return phase
end

function Player:Play(name, options)
    options = options or {}
    local clip = loadClip(self.DogId, name)
    if not clip then return false end
    local now = workspace:GetServerTimeNow()
    local previousClip = self.Clip
    local previous = previousClip ~= nil
    -- A one-shot that has reached its end holds its authored last frame: match from that.
    local settledSource = if previousClip and not self.Looped and self:IsDone(now) then previousClip else nil
    local blend = {}
    for _, bone in ipairs(self.AllBones) do
        -- Blend from the animated pose, not from the stare's turn on top of it.
        if bone.Parent and not self.HiddenBones[bone] then blend[bone] = self.PreLook[bone] or bone.Transform end
    end
    self.Clip, self.Name = clip, name
    self.Queue = nil
    self.StartTime = finite(options.StartTime) and options.StartTime or now
    self.Speed, self.PhaseOffset = nil, 0
    self.BlendStartedAt = now
    self.BlendDuration = if options.FadeTime == nil then (previous and .18 or 0) else math.max(0, options.FadeTime)
    -- A culled dog's bones hold a stale pose: nobody sees this change, so it cuts (and it is
    -- not stepped again until it is back in view).
    if self.Culled then self.BlendDuration = 0 end
    self.BlendFrom = if self.BlendDuration > 0 then blend else nil
    self:SetOptions(options)
    if options.MatchFrom and self.Looped and previous then
        local phase = self:MatchPhase(clip, blend, settledSource)
        if phase then self.StartTime = now - phase / self.Speed end
    end
    -- AdaptiveFade: an authored join (every track within a few degrees) cuts straight in, since
    -- blending from a frozen pose would only lag behind the new motion; a real posture change
    -- gets a crossfade that grows with the gap (up to .7 s), so changing between differently
    -- authored families (a lying idle, a standing dig) never snaps.
    if options.AdaptiveFade and previous and not self.Culled then
        local elapsed = math.max(0, (now - self.StartTime) * self.Speed)
        local t = if self.Looped then elapsed % (clip.Duration + self.Recovery) else math.min(elapsed, clip.Duration)
        local index = math.floor(math.min(t, clip.Duration) * clip.FPS) + 1
        local body = self:CorePose(clip, blend, settledSource)
        if next(body) ~= nil then
            local degrees = Player.PoseGap(clip, index, body)
            if degrees < SEAMLESS_DEGREES and Player.PoseGap(clip, index, self:CorePose(clip, blend, settledSource, true)) < SEAMLESS_DEGREES then
                self.BlendDuration, self.BlendFrom = 0, nil
            else
                local fade = math.min(MAX_ADAPTIVE_FADE, degrees / DEGREES_PER_SECOND)
                if fade > self.BlendDuration then
                    self.BlendDuration = fade
                    self.BlendFrom = blend
                end
            end
        end
    end
    self.Gait = WalkGait.new(self)
    self.Lift = if self:UsesLift(clip) then self:ComputeLift(clip) else nil
    local nextPlay = options.Next
    if type(nextPlay) == "table" and (nextPlay[1] or nextPlay.Name) then
        local at = options.NextAt
        if not finite(at) then
            at = if self.Looped then now + self:Remaining(now) else self.StartTime + clip.Duration / self.Speed
        end
        self.Queue = {Name = nextPlay[1] or nextPlay.Name, Options = nextPlay[2] or nextPlay.Options or {}, At = at, Tag = nextPlay.Tag}
    end
    if options.NoStep ~= true then self:Step() end
    return true
end

-- Starts the queued follow-up clip once its time has come (also called while culled).
function Player:Advance(now)
    local advanced = false
    for _ = 1, 8 do
        local queued = self.Queue
        if not queued or not finite(queued.At) or now < queued.At then break end
        self.Queue = nil
        local options = table.clone(queued.Options)
        if options.StartTime == nil then options.StartTime = queued.At end
        options.NoStep = true
        if not self:Play(queued.Name, options) then break end
        advanced = true
    end
    return advanced
end

function Player:Sample(seconds, blendAlpha)
    local clip = self.Clip
    if not clip then return end
    seconds = math.max(0, seconds)
    local period = clip.Duration + self.Recovery
    local t = if self.Looped then seconds % period else math.min(seconds, clip.Duration)
    local recovery = if t > clip.Duration and self.Recovery > 0 then smooth((t - clip.Duration) / self.Recovery) else 0
    local f = math.min(t, clip.Duration) * clip.FPS
    local index, alpha = math.floor(f) + 1, f % 1
    local scale = self:GetScaleFactor()
    local blend = blendAlpha or 1
    local hide
    -- Clear omitted tracks during a transition as well; old jaw/prop poses must
    -- not leak into the next clip. Missing streamed bones are safely skipped.
    for name, group in pairs(self.BoneGroups) do
        local frames = clip.Tracks[name]
        local pose = CFrame.identity
        local hidden = false
        if frames then
            local a, b = frames[math.min(index, #frames)], frames[math.min(index + 1, #frames)]
            pose = a:Lerp(b, alpha)
            if recovery > 0 then pose = pose:Lerp(frames[1], recovery) end
            local visibility = clip.Hidden and clip.Hidden[name]
            hidden = visibility and visibility[math.min(index, #visibility)] == true
            if recovery > .5 and visibility then hidden = visibility[1] == true end
            pose = CFrame.new(pose.Position * scale) * pose.Rotation
        end
        for _, bone in ipairs(group) do
            if bone.Parent then
                if hidden then
                    bone.Transform = pose
                    hide = hide or {}
                    hide[bone] = true
                    self.HiddenBones[bone] = true
                else
                    local old = self.BlendFrom and self.BlendFrom[bone]
                    bone.Transform = if old and blend < 1 then old:Lerp(pose, blend) else pose
                    self.HiddenBones[bone] = nil
                end
            end
        end
    end
    if self.Lift then
        local a, b = self.Lift[math.min(index, #self.Lift)], self.Lift[math.min(index + 1, #self.Lift)]
        local lift = (a + (b - a) * alpha) * (1 - recovery) * blend
        if lift > 0 then
            local up = self.Model:GetPivot().UpVector * lift
            for _, bone in ipairs(self.AllBones) do
                local parent = bone.Parent
                if parent and parent:IsA("BasePart") then
                    bone.Transform = CFrame.new((parent.CFrame * bone.CFrame):VectorToObjectSpace(up)) * bone.Transform
                end
            end
        end
    end
    -- Apply visibility after every animated parent has reached this frame.
    -- Bone transforms have no scale channel. Park independent FX beneath the
    -- model in world-up space, without a 100,000-stud skinned render envelope.
    if hide then
        local height = (if self.CacheScale then self.VisualHeight else nil)
            or (self.Model:GetAttribute("VisualSize") or Vector3.new(6, 6, 6)).Y
        local target = self.Model:GetPivot().Position - Vector3.yAxis * math.max(12, height * 3)
        for _, bone in ipairs(self.AllBones) do
            if hide[bone] and bone.Parent then
                local parent = bone.Parent
                local parentFrame = if parent:IsA("Bone") then parent.TransformedWorldCFrame else parent.CFrame
                local restWorld = parentFrame * bone.CFrame
                bone.Transform = CFrame.new(restWorld:PointToObjectSpace(target)) * bone.Transform.Rotation
            end
        end
    end
    if self.RigParts and not self.InStep then self:ApplyParts(nil, true) end
end

local UP = Vector3.yAxis
local function turn(bone, axis, angle, pre)
    if bone and bone.Parent and math.abs(angle) > 1e-4 then
        pre[bone] = pre[bone] or bone.Transform
        bone.Transform *= CFrame.fromAxisAngle(bone.TransformedWorldCFrame:VectorToObjectSpace(axis), angle)
    end
end
-- self.Look = {Target=Vector3 (world), Body=0..1, Head=0..1, Ground=Vector3? (pivot space), Bow=radians?}
-- Turns the whole solved pose about the dog's own feet toward Target (Body), then the
-- neck and heads (Head). Only Bone.Transform changes: nothing replicates or sticks, and
-- the next Sample rebuilds every bone. Bone axes differ between imports, so every
-- rotation is a world axis converted into the bone's space.
function Player:ApplyLook()
    local look, top = self.Look, self.TopBone
    if not look or not top or not top.Parent or not top.Parent:IsA("BasePart") then return end
    local pivot = self.Model:GetPivot()
    local ground = look.Ground or self.Model:GetAttribute("GroundLocal") or Vector3.zero
    local d = pivot:PointToObjectSpace(look.Target) - ground
    if d.X * d.X + d.Z * d.Z < .01 then return end
    -- Dogs face pivot -Z; this yaw turns -Z onto the target.
    local yaw = math.atan2(-d.X, -d.Z) * (look.Body or 0)
    if math.abs(yaw) > 1e-4 then
        local rotation = CFrame.new(ground) * CFrame.fromAxisAngle(UP, yaw) * CFrame.new(-ground)
        local bind = pivot:ToObjectSpace(top.Parent.CFrame * top.CFrame)
        self.PreLook[top] = self.PreLook[top] or top.Transform
        top.Transform = bind:Inverse() * rotation * bind * top.Transform
    end
    local weight = look.Head or 0
    if weight <= 0 then return end
    local forward = pivot:VectorToWorldSpace(CFrame.fromAxisAngle(UP, yaw).LookVector)
    forward = Vector3.new(forward.X, 0, forward.Z)
    if forward.Magnitude < 1e-3 then return end
    forward = forward.Unit
    for i, head in ipairs(self.LookHeads or {}) do
        if head.Parent then
            local to = look.Target - head.TransformedWorldCFrame.Position
            local flat = Vector3.new(to.X, 0, to.Z)
            if flat.Magnitude > 1e-3 then
                local side = math.clamp(math.atan2(forward:Cross(flat.Unit).Y, forward:Dot(flat.Unit)), -math.rad(70), math.rad(70)) * weight
                local pitch = math.clamp(math.atan2(to.Y, flat.Magnitude), math.rad(-20), math.rad(35)) * weight - (look.Bow or 0)
                local right = CFrame.fromAxisAngle(UP, side):VectorToWorldSpace(forward):Cross(UP).Unit
                if i == 1 and self.LookNeck then
                    turn(self.LookNeck, UP, side * .4, self.PreLook); turn(self.LookNeck, right, pitch * .4, self.PreLook)
                    side *= .6; pitch *= .6
                end
                turn(head, UP, side, self.PreLook); turn(head, right, pitch, self.PreLook)
            end
        end
    end
end

function Player:Step(now)
    if not self.Clip then return end
    now = now or workspace:GetServerTimeNow()
    -- Before PreLook is cleared: a queued clip blends from the last animated pose.
    if self.Queue then self:Advance(now) end
    table.clear(self.PreLook)
    self.InStep = true
    local blend = if self.BlendFrom then smooth((now - self.BlendStartedAt) / math.max(.001, self.BlendDuration)) else 1
    local locomotion = self.Gait and self.Model:GetAttribute("LocomotionSpeed")
    if self.Gait and finite(locomotion) then
        self:Sample(self.Gait:Advance(now,locomotion),blend)
        self.Gait:Apply(blend)
    else
        self:Sample(math.max(0, (now - self.StartTime) * self.Speed + (self.PhaseOffset or 0)), blend)
    end
    if blend >= 1 then self.BlendFrom = nil end
    self:ApplyEventHead(now)
    -- After the gait IK and the event head bob: the solved pose turns rigidly.
    if self.Look then self:ApplyLook() end
    self.InStep = false
    if self.RigParts then self:ApplyParts(now) end
end

-- The world-event state is resolved once per frame (per distinct `now`), not per dog.
local eventFrame = {At = nil, Active = false}
function Player.EventFrame(now)
    if eventFrame.At ~= now then
        eventFrame.At = now
        local events = ReplicatedStorage:FindFirstChild("WorldEvents")
        local state = events and events:FindFirstChild("State")
        eventFrame.Active = state ~= nil and state:GetAttribute("State") == "ACTIVE"
        eventFrame.EventId = if eventFrame.Active then state:GetAttribute("EventId") else nil
        local camera = workspace.CurrentCamera
        eventFrame.Camera = camera and camera.CFrame.Position
    end
    return eventFrame
end

function Player:ApplyEventHead(now)
    local frame = Player.EventFrame(now)
    if not frame.Active or self.Model:GetAttribute("WorkState") == "DIGGING" then return end
    if frame.Camera and (frame.Camera - self.Model:GetPivot().Position).Magnitude > 180 then return end
    local phase = now % 9
    if phase > 1.2 then return end
    local head = self.Bones.Head or self.Bones.head
    if head and head.Parent then
        local eventId = frame.EventId
        local amount = math.sin(phase / 1.2 * math.pi) * .10
        -- Use actual bind-space directions; imported Z-up and authored Y-up
        -- skeletons should both look up, rather than roll sideways.
        local modelFrame = self.Model:GetPivot()
        local rest = head.WorldCFrame
        local right = rest:VectorToObjectSpace(modelFrame.RightVector)
        local up = rest:VectorToObjectSpace(modelFrame.UpVector)
        if eventId == "BONE_RAIN" or eventId == "UFO_INVASION" then
            head.Transform *= CFrame.fromAxisAngle(right, -amount)
        elseif eventId == "BLACKOUT" or eventId == "NULL_HOUR" then
            head.Transform *= CFrame.fromAxisAngle(up, amount)
        elseif eventId == "DOG_RUSH" then
            head.Transform *= CFrame.fromAxisAngle(rest:VectorToObjectSpace(-modelFrame.LookVector), amount)
        end
    end
end

-- Kennel work driver -------------------------------------------------------------------------
-- A kennel dog digs for as long as it produces: Idle -> Start -> Loop ... -> End -> Idle, and
-- an accent (DogDigProfiles Find/Action) ends exactly at each find (NextWorkAt). Everything
-- is derived from replicated server state, so every client shows the same thing:
--   info = {Working = bool, NextWorkAt = unix seconds?, WorkSequence = n?, WorkCycle = s?,
--           AssignedAt = server time?}
-- Call every frame (also while the dog is culled: `visible` false skips sampling and the
-- phase match). Step() samples; UpdateKennel only decides and queues clips.
local function sequenceOptions(names, firstOptions, after)
    local nextPlay = after
    for i = #names, 2, -1 do
        nextPlay = {names[i], {FadeTime = HOP_FADE, Looped = false, AdaptiveFade = true, Next = nextPlay}, Tag = "Hop"}
    end
    local options = table.clone(firstOptions)
    options.Looped = false
    options.Next = nextPlay
    return options
end

-- Start time of the accent that ends on the coming find (NextWorkAt), or of the next copy
-- of a repeating action, and the accent's length. An accent that began less than LATE ago
-- still counts (it starts a little into its first clip); `joining` accepts any copy that is
-- running right now, so a client that streams in shows the same frame as the others.
local LATE = .35
local accentDurations = {}
function Player:KennelAccentStart(chain, info, now, joining)
    local accent = chain.Accent
    local nextAt = info.NextWorkAt
    if not accent or not finite(nextAt) or nextAt <= 0 or not finite(now) then return nil end
    local durations = accentDurations[self.DogId] or {}
    accentDurations[self.DogId] = durations
    local duration = durations[accent]
    if duration == nil then
        -- The accent clips arrive through the preload queue (one decode per frame); until then
        -- the dog just keeps its loop.
        if not Player.IsLoaded(self.DogId, accent) then return nil end
        duration = Player.SequenceDuration(self.DogId, accent) or false
        durations[accent] = duration
    end
    if not duration or duration <= .05 or duration > MAX_ACCENT then return nil end
    local tolerance = if joining then duration - 1e-6 else math.min(LATE, duration / 2)
    local previousFind = if finite(info.WorkCycle) and info.WorkCycle > 0 then nextAt - info.WorkCycle else nil
    local start
    if chain.Repeat then
        -- Copies end at NextWorkAt, NextWorkAt - D, NextWorkAt - 2D ...: the earliest one
        -- that has not started yet (or started less than `tolerance` ago).
        local copies = math.floor((nextAt - now + tolerance) / duration + 1e-9)
        if copies < 1 then return nil end
        start = nextAt - copies * duration
        if previousFind and start < previousFind - .05 then
            start += math.ceil((previousFind - .05 - start) / duration) * duration
            if start > nextAt - duration + 1e-6 then return nil end
        end
    else
        if ((tonumber(info.WorkSequence) or 0) + 1) % chain.Every ~= 0 then return nil end
        start = nextAt - duration
        if start < now - tolerance then return nil end
        if previousFind and start < previousFind - .05 then return nil end
    end
    return start, duration
end

local function returnPlay(chain)
    return {chain.Loop, {FadeTime = chain.Fades.Return, Looped = true, MatchFrom = true, AdaptiveFade = true}, Tag = "Return"}
end

function Player:QueueAccent(chain, start, now, visible, fade)
    local k = self.Kennel
    -- fade 0 = a client joining mid-accent: nothing has been shown yet, so nothing to blend.
    local options = sequenceOptions(chain.Accent, {FadeTime = fade, StartTime = start, AdaptiveFade = fade > 0}, returnPlay(chain))
    k.AccentAt = start
    if start <= now then
        options.NoStep = not visible
        self:Play(chain.Accent[1], options)
    else
        self.Queue = {Name = chain.Accent[1], Options = options, At = start, Tag = "Accent"}
    end
end

function Player:EnterKennelWork(chain, info, now, visible)
    local fades = chain.Fades
    local fresh = finite(info.AssignedAt) and now - info.AssignedAt < START_WINDOW and now >= info.AssignedAt - 1
    if fresh then
        if chain.Start then
            -- Just assigned: settle in the rest pose, then DigStart into the loop.
            self:Play(chain.Idle, {FadeTime = 0, Looped = true, NoStep = not visible})
            self:Play(chain.Start[1], sequenceOptions(chain.Start, {FadeTime = fades.Start, AdaptiveFade = true, NoStep = not visible},
                {chain.Loop, {FadeTime = fades.Loop, Looped = true, MatchFrom = true, AdaptiveFade = true}, Tag = "Loop"}))
        else
            -- No lead-in: start on the loop; the first accent is scheduled from the next find.
            self:Play(chain.Loop, {FadeTime = 0, Looped = true, StartTime = info.AssignedAt, NoStep = not visible})
        end
        return
    end
    -- Joining or streaming in mid-work: an accent that is running now plays from its own
    -- start; otherwise the loop runs at a phase every client derives from AssignedAt.
    if chain.Accent then
        local start, duration = self:KennelAccentStart(chain, info, now, true)
        if start and duration and start <= now and now < start + duration then
            self:Play(chain.Loop, {FadeTime = 0, Looped = true, StartTime = info.AssignedAt or 0, NoStep = true})
            self:QueueAccent(chain, start, now, visible, 0)
            return
        end
    end
    self:Play(chain.Loop, {FadeTime = 0, Looped = true, StartTime = if finite(info.AssignedAt) then info.AssignedAt else 0, NoStep = not visible})
end

function Player:BeginKennelWork(chain, now, visible)
    local fades = chain.Fades
    if chain.Start then
        self:Play(chain.Start[1], sequenceOptions(chain.Start, {FadeTime = fades.Start, AdaptiveFade = true, NoStep = not visible},
            {chain.Loop, {FadeTime = fades.Loop, Looped = true, MatchFrom = true, AdaptiveFade = true}, Tag = "Loop"}))
    elseif not (self.Clip and self.Clip.SourceName == chain.Loop and self.Looped) then
        self:Play(chain.Loop, {FadeTime = fades.Direct, Looped = true, MatchFrom = true, AdaptiveFade = true, NoStep = not visible})
    else
        self.Queue = nil
    end
end

function Player:StopKennelWork(chain, now, visible)
    local fades = chain.Fades
    local rest = {chain.Idle, {FadeTime = fades.Idle, Looped = true, MatchFrom = true, AdaptiveFade = true}, Tag = "Rest"}
    -- Leave on a boundary when it comes soon: authored DigEnds start where the loop (or the
    -- running one-shot) ends.
    local at = now
    if self.Clip and (self.Queue == nil or self.Queue.Tag ~= "Hop") then
        local remaining = self:Remaining(now)
        if remaining <= END_WAIT then at = now + remaining end
    elseif self.Clip and self.Queue then
        at = self.Queue.At or now -- finish the authored sequence that is playing
    end
    if chain.End then
        local options = sequenceOptions(chain.End, {FadeTime = fades.End, AdaptiveFade = true}, rest)
        self.Queue = {Name = chain.End[1], Options = options, At = at, Tag = "End"}
    elseif self.Clip and self.Clip.SourceName == chain.Idle and self.Looped then
        self.Queue = nil -- already resting (a working-idle dog)
    else
        self.Queue = {Name = chain.Idle, Options = {FadeTime = fades.Stop, Looped = true, MatchFrom = true, AdaptiveFade = true}, At = at, Tag = "Rest"}
    end
    if at <= now then
        self:Advance(now)
        if visible and self.Clip then self:Step(now) end
    end
end

function Player:UpdateKennel(info, now, visible)
    local chain = Player.Chain(self.DogId)
    if not chain or not chain.Loop then return end
    now = now or workspace:GetServerTimeNow()
    self.Culled = not visible
    local k = self.Kennel
    local first = k == nil
    if first then k = {}; self.Kennel = k end
    -- Queued follow-ups run on time even while the dog is culled (Step is skipped then).
    if not first and self.Queue then self:Advance(now) end
    if info.Working then
        if first then
            k.Mode = "Work"; k.AccentAt = nil
            self:EnterKennelWork(chain, info, now, visible)
        elseif k.Mode ~= "Work" then
            k.Mode = "Work"; k.AccentAt = nil
            self:BeginKennelWork(chain, now, visible)
        end
        if chain.Accent then
            local queued = self.Queue
            local start = self:KennelAccentStart(chain, info, now, false)
            -- A queued accent for an old NextWorkAt (the deadline moved) is dropped.
            if queued and queued.Tag == "Accent" and queued.At ~= start then self.Queue = nil; queued = nil; k.AccentAt = nil end
            if start and start ~= k.AccentAt then
                local onLoop = self.Clip and self.Clip.SourceName == chain.Loop and self.Looped and queued == nil
                -- With Repeat the next copy follows the previous one directly.
                local backToBack = queued and queued.Tag == "Return" and math.abs(queued.At - start) < .05
                if onLoop or backToBack then
                    self:QueueAccent(chain, start, now, visible, if backToBack then HOP_FADE else chain.Fades.Accent)
                end
            end
        end
    else
        if first then
            k.Mode = "Rest"
            self:Play(chain.Idle, {FadeTime = 0, Looped = true, StartTime = if finite(info.AssignedAt) then info.AssignedAt else nil, NoStep = not visible})
        elseif k.Mode ~= "Rest" then
            k.Mode = "Rest"; k.AccentAt = nil
            if self.Queue and self.Queue.Tag == "Accent" then self.Queue = nil end
            self:StopKennelWork(chain, now, visible)
        end
    end
    -- Catch up a sequence that should already be further along (a culled dog, or a client that
    -- joined in the middle of a multi-clip accent), so every client is on the same clip.
    if self.Queue then self:Advance(now) end
    if first and visible and self.Clip then self:Step(now) end
end

function Player:Destroy()
    self:Stop()
    if self.PartWatch then self.PartWatch:Disconnect(); self.PartWatch = nil end
    if self.PartLeave then self.PartLeave:Disconnect(); self.PartLeave = nil end
    self.RigParts = nil
    table.clear(self.Bones); table.clear(self.BoneGroups); table.clear(self.AllBones)
end
return Player
