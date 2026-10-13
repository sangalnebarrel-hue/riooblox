local Players = game:GetService("Players")
local Storage = game:GetService("ServerStorage")
local Replicated = game:GetService("ReplicatedStorage")
local map = workspace:WaitForChild("DOGROTS_District")
local yards = map:WaitForChild("04_PlayerYards")
local residents = map:WaitForChild("KennelDogs")
local templates = Storage:WaitForChild("DogTemplates")
local remote = Replicated:WaitForChild("DogKennelRequest")
local open = Replicated:WaitForChild("DogKennelOpen")
local Runtime=require(script.Parent.Economy.Runtime)
local Http=game:GetService("HttpService")
local Definitions=require(Replicated.DogEconomy.DogDefinitions)
local Rig=require(Replicated.DogRig)
-- Dogs dig DOWN (docs/MINE.md): while the owner's CurrentLayer is 2..5 each assigned dog stands
-- at its worksite in that level of the yard's mine (MineLayout), otherwise on its surface pit.
local MineLayout=require(Replicated:WaitForChild("Mine"):WaitForChild("MineLayout"))
local Service = {}
local cooldown = {}
local connections = {}
-- Kennel dogs replicate a role and the work timing; every client plays the dig chain and
-- counts the label down itself (DogAnimations). Attributes are written only on change:
--   AnimationName "Work" while producing, "Idle" otherwise (WorkState DIGGING/RESTING)
--   Producing     false when loot storage is full (Rules.Storage LootFull) or the work tick has stalled
--   StorageFull   why it is not producing
--   FindsFull     the item bag is full (Rules.Storage ItemFull): the dog keeps digging and earning
--                 coins (R.Dig pays loot into the wallet), it only finds no items
--   NextWorkAt, WorkSequence, WorkCycle (seconds between finds), AssignedAt (model created)
local STALL_GRACE=3
local advancedAt=setmetatable({},{__mode="k"})
local function put(model,key,value)
    if model:GetAttribute(key)~=value then model:SetAttribute(key,value) end
end
local function economy(name)
    return require(script.Parent.Economy:FindFirstChild(name))
end
-- Rules.Storage (economy) -> {LootUnits,LootCapacity,ItemCount,ItemCapacity,LootFull,ItemFull}.
-- Returns lootFull (the dog cannot produce), itemFull (it digs and earns, but finds no items).
-- Until it exists (or if it fails) storage never blocks the animation.
local function storageState(profile,now)
    if type(profile)~="table" then return false,false end
    local ok,result=pcall(function()
        local Rules=economy("Rules")
        return type(Rules.Storage)=="function" and Rules.Storage(profile,now) or nil
    end)
    if not ok or type(result)~="table" then return false,false end
    return result.LootFull==true,result.ItemFull==true
end
local function workCycles(profile)
    local cycles={}
    pcall(function()
        local Rules=economy("Rules")
        local duration=economy("Config").Work.Duration
        local team=Rules.Team(profile,os.time())
        for uid,d in pairs(profile.Dogs) do
            if d.AssignedSlot~="" then
                local ok,seconds=pcall(Rules.Cooldown,profile,d,team)
                if ok and type(seconds)=="number" and seconds==seconds then cycles[uid]=seconds+duration end
            end
        end
    end)
    return cycles
end
local function applyWorkState(model,now,full,findsFull)
    local deadline=model:GetAttribute("NextWorkAt")
    -- A deadline that has not moved for a few seconds after it passed means the economy tick
    -- is not running for this player (session lock, failed transaction): show it resting.
    local stalled=type(deadline)=="number" and deadline>0 and now>deadline+STALL_GRACE and now>(advancedAt[model] or 0)+STALL_GRACE
    local producing=not stalled and not full
    put(model,"Producing",producing)
    put(model,"StorageFull",full==true)
    put(model,"FindsFull",findsFull==true)
    put(model,"WorkState",producing and "DIGGING" or "RESTING")
    local role=producing and "Work" or "Idle"
    if model:GetAttribute("AnimationName")~=role then
        model:SetAttribute("AnimationStartedAt",workspace:GetServerTimeNow())
        model:SetAttribute("AnimationName",role)
    end
end

local function yardFor(player)
    for _, yard in ipairs(yards:GetChildren()) do
        if yard:GetAttribute("OwnerUserId") == player.UserId then return yard end
    end
end
local function entryFor(player, uid)
    local inventory = player:FindFirstChild("DogInventory")
    local entry = inventory and inventory:FindFirstChild(uid)
    if entry and entry:IsA("StringValue") and entry:GetAttribute("OwnerUserId") == player.UserId then return entry end
end
local function clearEntry(entry)
    local uid = entry.Name
    local owner = entry:GetAttribute("OwnerUserId")
    for _, dog in ipairs(residents:GetChildren()) do
        if dog:GetAttribute("DogUid") == uid and dog:GetAttribute("OwnerUserId") == owner then dog:Destroy() end
    end
    for _, yard in ipairs(yards:GetChildren()) do
        for _, slot in ipairs(yard:GetChildren()) do
            if slot:GetAttribute("AssignedDogUid") == uid and slot:GetAttribute("AssignedOwnerUserId") == owner then
                slot:SetAttribute("AssignedDogUid", nil)
                slot:SetAttribute("AssignedOwnerUserId", nil)
                slot:SetAttribute("AssignedDogName", nil)
            end
        end
    end
    entry:SetAttribute("AssignedSlot", "")
    entry:SetAttribute("State", "Inventory")
end
-- The mine worksite of a slot on a layer (nil on the surface or when the yard has no layout).
local function worksite(slot, layer)
    if (tonumber(layer) or 1)<2 then return nil end
    local index=tonumber(slot.Name:match("^DigSlot_(%d+)$"))
    local layout=index and MineLayout.ForYard(slot.Parent)
    return layout and layout:Worksite(layer,index) or nil
end
Service.Worksite=worksite
local function prepare(entry, slot, layer)
    local id = entry:GetAttribute("DogId")
    local template = templates:FindFirstChild(Definitions[id] and Definitions[id].VisualAsset or id or "")
    local floor = slot:FindFirstChild("KennelFloor")
    local back = slot:FindFirstChild("KennelBack")
    if not template or not template:IsA("Model") or not floor or not back then return nil end
    local dog = template:Clone()
    local digSize=slot:GetAttribute("DigSize") or Vector3.new(12,.4,12)
    local usableWidth=math.max(2, math.min(digSize.X,digSize.Z)-2)
    local prepared=Rig.Prepare(dog, Vector3.new(usableWidth,4.2,usableWidth))
    if not prepared then dog:Destroy();return nil end
    local root,low,high,ground=prepared.Root,prepared.Low,prepared.High,prepared.Ground
    for _,child in ipairs(dog:GetDescendants()) do
        if child:IsA("ProximityPrompt") then child:Destroy() end
    end
    local excavation=slot:FindFirstChild("DarkExcavation")
    local center=slot:GetAttribute("DigCenter") or (excavation and excavation.Position)
    if typeof(center)~="Vector3"then dog:Destroy();return nil end
    local forward=center-floor.Position;forward=Vector3.new(forward.X,0,forward.Z)
    if forward.Magnitude<.01 then forward=floor.Position-back.Position;forward=Vector3.new(forward.X,0,forward.Z)end
    if forward.Magnitude < .01 then forward=Vector3.new(0,0,-1) end
    forward=forward.Unit
    local halfExtent=(math.abs(forward.X)*digSize.X+math.abs(forward.Z)*digSize.Z)/2
    local bodyDepth=high.Z-low.Z
    local inset=math.max(0,halfExtent-bodyDepth/2-1)
    local position=center-forward*inset
    local surface=excavation and (excavation.Position.Y+excavation.Size.Y/2) or (center.Y+digSize.Y/2)
    position=Vector3.new(position.X,surface+.04,position.Z)
    local site=worksite(slot,layer)
    if site then
        -- In the mine: the dog's nose at the dig face, facing the ore vein (floor liner is .1 thick).
        forward=site.Face.LookVector
        position=site.Face.Position-forward*(bodyDepth/2)+Vector3.new(0,.14,0)
    end
    dog:SetAttribute("MinePlacement",MineLayout.DogPlacement(site and layer or 1))
    dog:PivotTo(CFrame.new(position)*CFrame.lookAt(Vector3.zero,forward)*CFrame.new(-ground))
    dog.Name=entry.Name
    dog:SetAttribute("DogId",id); dog:SetAttribute("DogUid",entry.Name)
    dog:SetAttribute("OwnerUserId",entry:GetAttribute("OwnerUserId"))
    dog:SetAttribute("AssignedSlot",slot.Name); dog:SetAttribute("State","Resting")
    dog:SetAttribute("GroundLocal",ground)
    -- Clients play DigStart only for a model this fresh; later viewers join mid-work.
    dog:SetAttribute("AssignedAt",workspace:GetServerTimeNow())
    dog:SetAttribute("AnimationStartedAt",workspace:GetServerTimeNow())
    dog:SetAttribute("AnimationLooped",true)
    dog:SetAttribute("AnimationSpeed",1)
    dog:SetAttribute("AnimationName","Idle")
    local anchor=Instance.new("Attachment");anchor.Name="SleepLabelAnchor"
    anchor.Position=root.CFrame:PointToObjectSpace(position+Vector3.new(0,4.8,0));anchor.Parent=root
    local label=Instance.new("BillboardGui");label.Name="SleepLabel";label.Adornee=anchor
    label.Size=UDim2.fromOffset(190,46);label.MaxDistance=55;label.AlwaysOnTop=false;label.Parent=dog
    local dogName=entry:GetAttribute("DisplayName") or entry.Value
    dog:SetAttribute("DogName",dogName)
    local text=Instance.new("TextLabel");text.Name="NameLabel";text.Size=UDim2.fromScale(1,.56);text.BackgroundTransparency=1
    text.Font=Enum.Font.GothamBold;text.TextSize=16;text.TextColor3=Color3.fromRGB(205,230,255)
    text.TextStrokeTransparency=.4;text.TextTruncate=Enum.TextTruncate.AtEnd;text.Text=dogName;text.Parent=label
    -- The status line is written (and localized) by every client: it counts down each second.
    local status=Instance.new("TextLabel");status.Name="StatusLabel";status.Position=UDim2.fromScale(0,.56);status.Size=UDim2.fromScale(1,.44)
    status.BackgroundTransparency=1;status.Font=Enum.Font.GothamBold;status.TextScaled=true;status.TextColor3=Color3.fromRGB(150,230,160)
    status.TextStrokeTransparency=.4;status:SetAttribute("NoTranslate",true);status.Text="";status.Parent=label
    local limit=Instance.new("UITextSizeConstraint");limit.MaxTextSize=13;limit.MinTextSize=8;limit.Parent=status
    return dog
end


function Service.Reconcile(player,profile)
    local yard=yardFor(player)
    if not yard then return end
    for _,slot in ipairs(yard:GetChildren()) do
        if slot.Name:match("^DigSlot_%d+$") then
            slot:SetAttribute("AssignedDogUid",nil);slot:SetAttribute("AssignedOwnerUserId",nil);slot:SetAttribute("AssignedDogName",nil)
        end
    end
    -- Where the dogs work now: a model standing elsewhere (the owner changed the dig layer) is
    -- rebuilt fresh at the new place, so every client restarts its dig animation there.
    local layer=MineLayout.LayerNumber(profile.CurrentLayer) or 1
    local placement=MineLayout.DogPlacement(layer)
    for _,model in ipairs(residents:GetChildren()) do
        if model:GetAttribute("OwnerUserId")==player.UserId then
            local dog=profile.Dogs[model:GetAttribute("DogUid")]
            if not dog or dog.AssignedSlot=="" or dog.AssignedSlot~=model:GetAttribute("AssignedSlot")
                or (model:GetAttribute("MinePlacement") or "Surface")~=placement then model:Destroy() end
        end
    end
    local now=os.time()
    local full,findsFull=storageState(profile,now)
    local cycles=workCycles(profile)
    for uid,d in pairs(profile.Dogs) do if d.AssignedSlot~="" then
        local slot=yard:FindFirstChild(d.AssignedSlot);local entry=player.DogInventory:FindFirstChild(uid)
        if slot and entry then
            local model=residents:FindFirstChild(uid)
            local fresh=false
            if not model then
                local ok,result=pcall(prepare,entry,slot,layer)
                if ok and result then model=result;fresh=true else warn("Kennel asset unavailable",d.DogId) end
            end
            if model then
                -- Work timing first, then the role: a new model replicates complete.
                local deadline=d.NextWorkAt or 0
                if fresh or model:GetAttribute("NextWorkAt")~=deadline then advancedAt[model]=now end
                put(model,"NextWorkAt",deadline);put(model,"WorkSequence",d.WorkSequence or 0)
                if cycles[uid] then put(model,"WorkCycle",cycles[uid]) end
                put(model,"Variant",d.Variant);put(model,"Mastery",d.Mastery)
                put(model,"EquippedCosmetic",profile.EquippedCosmetic)
                applyWorkState(model,now,full,findsFull)
                if fresh then model.Parent=residents end
                slot:SetAttribute("AssignedDogUid",uid);slot:SetAttribute("AssignedOwnerUserId",player.UserId);slot:SetAttribute("AssignedDogName",d.DisplayName)
            end
        end
    end end
end
function Service.Handle(player,action,uid,slotName)
    if not Runtime.Ready(player) then return false,"Profile loading" end
    if not Runtime.Allow(player,.5) then return false,"Please wait" end
    if action~="Assign" and action~="Remove" then return false,"Invalid kennel operation" end
    if action=="Assign" then
        local yard=yardFor(player);local slot=type(slotName)=="string" and yard and yard:FindFirstChild(slotName)
        local entry=type(uid)=="string" and entryFor(player,uid)
        if not slot or not entry then return false,"Dog or kennel unavailable" end
        local ok,probe=pcall(prepare,entry,slot)
        if not ok or not probe then return false,"Dog asset unavailable" end
        probe:Destroy()
    end
    local ok,result=Runtime.Request(player,action,{Uid=uid,Slot=slotName},Http:GenerateGUID(false):gsub("%-",""))
    if ok then Runtime.Refresh(player) end
    return ok,type(result)=="table" and result.Message or result
end
-- Every Config.TickSeconds (Runtime, before the economy tick). Reconcile only runs on a
-- refresh, so storage and stalls are re-checked here; nothing is written unless it changed.
function Service.UpdateWorkVisuals()
 local now=os.time();local stateByOwner={}
 for _,model in ipairs(residents:GetChildren())do
  local owner=model:GetAttribute("OwnerUserId")
  local state=owner~=nil and stateByOwner[owner] or nil
  if owner~=nil and state==nil then
   local full,findsFull=storageState(Runtime.Views[owner],now)
   state={full,findsFull};stateByOwner[owner]=state
  end
  applyWorkState(model,now,state~=nil and state[1],state~=nil and state[2])
 end
end
function Service.Start()
    if Service.Started then return end;Service.Started=true
    Runtime.Kennels=Service
    remote.OnServerInvoke=Service.Handle
    Players.PlayerRemoving:Connect(function(player)
        for _,dog in ipairs(residents:GetChildren())do if dog:GetAttribute("OwnerUserId")==player.UserId then dog:Destroy()end end
    end)
    for _,yard in ipairs(yards:GetChildren()) do
        yard:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
            task.defer(function()
                local player=Players:GetPlayerByUserId(yard:GetAttribute("OwnerUserId") or 0)
                if player then Runtime.Refresh(player) end
            end)
        end)
        for _,slot in ipairs(yard:GetChildren()) do
            local floor=slot:FindFirstChild("KennelFloor");local back=slot:FindFirstChild("KennelBack")
            if slot.Name:match("^DigSlot_%d+$") and floor and back then
                local a=Instance.new("Attachment");a.Name="KennelInteraction"
                local direction=(floor.Position-back.Position).Unit
                a.Position=floor.CFrame:PointToObjectSpace(floor.Position+direction*3.8+Vector3.new(0,1.5,0));a.Parent=floor
                local prompt=Instance.new("ProximityPrompt");prompt.ActionText="MANAGE";prompt.ObjectText="DIG KENNEL "..slot.Name:match("%d+$")
                prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=false;prompt.Parent=a
                prompt.Enabled=slot:GetAttribute("Unlocked")~=false
                prompt.Triggered:Connect(function(player)
                    if slot:GetAttribute("Unlocked")==false then return end
                    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if yard:GetAttribute("OwnerUserId")==player.UserId and root and (root.Position-a.WorldPosition).Magnitude<=14 and Runtime.Allow(player,1) then open:FireClient(player,slot.Name) end
                end)
            end
        end
    end
    Runtime.RefreshAll()
    print("DOGROTS_KENNELS_READY: persistent dig assignments")
end
return Service
