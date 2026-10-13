-- Studio-only diagnostics. Nothing runs unless a developer calls this module.
local QA = {}
local Rep = game:GetService("ReplicatedStorage")
local Storage = game:GetService("ServerStorage")
local Rig = require(Rep.DogRig)
local Animation = require(Rep.DogAnimationPlayer)
local Definitions = require(Rep.DogEconomy.DogDefinitions)
local gallery, players = nil, {}
local function ordered(ids)
    local list={}
    if ids then
        for _,id in ipairs(ids) do table.insert(list,{Id=id,Definition=assert(Definitions[id],id)}) end
    else
        for id,definition in pairs(Definitions) do table.insert(list,{Id=id,Definition=definition}) end
        table.sort(list,function(a,b)return a.Definition.Index<b.Definition.Index end)
    end
    return list
end
local function pose(player)
    local result={}
    for _,bone in ipairs(player.AllBones) do result[bone]=bone.Transform end
    return result
end
local function gap(a,b,excluded)
    local position,angle=0,0
    for bone,first in pairs(a) do
        local last=b[bone]
        if last and not (excluded and excluded[bone]) then
            position=math.max(position,(first.Position-last.Position).Magnitude)
            local _,r=(first:Inverse()*last):ToAxisAngle();angle=math.max(angle,math.abs(r))
        end
    end
    return position,angle
end
function QA.Run()
    assert(game:GetService("RunService"):IsStudio(),"Studio only")
    local results={Dogs=0,Clips=0,Bones=0,Failures={},RecoveredWorkLoops={},FittedWorkClips={},MissingRoles={},Chains={}}
    local work=require(Rep.DogEconomy.Config).Work
    local minCycle=work.MinCooldown+work.Duration
    for _,entry in ipairs(ordered()) do
        local clone,player
        local ok,err=pcall(function()
            local template=assert(Storage.DogTemplates:FindFirstChild(entry.Definition.VisualAsset),"missing model")
            clone=template:Clone()
            local prepared=assert(Rig.Prepare(clone,Vector3.new(8,5,8)),"invalid visible bounds")
            assert(prepared.Size.Y<=5.001 and prepared.Size.X<=8.001 and prepared.Size.Z<=8.001,"size outside envelope")
            player=Animation.new(clone,entry.Id)
            assert(#player.AllBones>0,"missing skeleton")
            results.Bones+=#player.AllBones
            for _,role in ipairs({"Idle","Walk","Work"}) do
                if not Animation.ResolveName(entry.Id,role) then table.insert(results.MissingRoles,entry.Id.."/"..role) end
            end
            for _,name in ipairs(player:GetClipNames()) do
                assert(player:Play(name,{FadeTime=0}),"invalid clip "..name)
                for bone in pairs(player.Clip.Tracks) do assert(player.Bones[bone],"unbound track "..name.."/"..bone) end
                for _,fraction in ipairs({0,.17,.51,.91,1}) do player:Sample(player.Clip.Duration*fraction) end
                results.Clips+=1
            end
            -- Kennel dogs dig continuously: the work loop plays at x1.0 for as long as the dog
            -- produces (nothing is squeezed into a 4 s window any more), a one-shot loop
            -- recovers to its first frame unless its seam is already closed.
            local workClip=Animation.ResolveName(entry.Id,"Work")
            if workClip then
                assert(player:Play(workClip,{Looped=true,FadeTime=0,Speed=1}),"work cannot play")
                if player.Recovery>0 then
                    local completionSeconds=(player.Clip.Duration+player.Recovery)/player.Speed
                    table.insert(results.FittedWorkClips,{Dog=entry.Id,Speed=player.Speed,CompletionSeconds=completionSeconds})
                    player:Sample(.0001);local first=pose(player)
                    player:Sample(player.Clip.Duration+player.Recovery-.0001)
                    local p,a=gap(first,pose(player))
                    assert(p<.015 and a<.015,"work loop teleports at seam")
                    table.insert(results.RecoveredWorkLoops,{Dog=entry.Id,Clip=workClip,PositionGap=p,AngleGap=a})
                end
            end
            -- The whole kennel chain (DogDigProfiles > folder attributes > candidates) plays,
            -- and accents fit between two finds at x1.0.
            local chain=assert(Animation.Chain(entry.Id),"no dig chain")
            assert(chain.Idle and chain.Loop,"dig chain without Idle/Loop")
            local names={chain.Idle,chain.Loop}
            for _,list in ipairs({chain.Start or {},chain.End or {},chain.Accent or {}}) do
                for _,name in ipairs(list) do table.insert(names,name) end
            end
            for _,name in ipairs(names) do assert(player:Play(name,{FadeTime=0}),"chain clip cannot play "..name) end
            local accent=chain.Accent and assert(Animation.SequenceDuration(entry.Id,chain.Accent),"accent cannot load")
            if accent then assert(accent<=minCycle+.0001,"accent longer than the shortest work cycle") end
            table.insert(results.Chains,{Dog=entry.Id,Idle=chain.Idle,Loop=chain.Loop,Start=chain.Start and table.concat(chain.Start,"+"),
                End=chain.End and table.concat(chain.End,"+"),Accent=chain.Accent and table.concat(chain.Accent,"+"),AccentSeconds=accent,Repeat=chain.Repeat})
            -- A state change must preserve the current pose at the start of its fade.
            local walk=assert(Animation.ResolveName(entry.Id,"Walk"),"walk unavailable")
            player:Play(walk,{FadeTime=0});player:Sample(player.Clip.Duration*.3)
            local before=pose(player)
            local hidden=table.clone(player.HiddenBones)
            local idle=assert(Animation.ResolveName(entry.Id,"Idle"),"idle unavailable")
            player:Play(idle,{FadeTime=.2});player:Sample(0,0)
            for bone in pairs(player.HiddenBones) do hidden[bone]=true end
            local p,a=gap(before,pose(player),hidden)
            assert(p<.001 and a<.002,"transition resets bind pose")
            player:Stop()
            for _,bone in ipairs(player.AllBones) do assert(bone.Transform==CFrame.identity,"stop did not reset") end
            results.Dogs+=1
        end)
        if player then player:Destroy() end
        if clone then clone:Destroy() end
        if not ok then table.insert(results.Failures,{Dog=entry.Id,Error=tostring(err)}) end
        if entry.Definition.Index%10==0 then task.wait() end
    end
    print("DOG_VISUAL_QA "..game:GetService("HttpService"):JSONEncode(results))
    return results
end
function QA.ClearGallery()
    for _,player in pairs(players) do player:Destroy() end
    table.clear(players)
    if gallery then gallery:Destroy();gallery=nil end
end
function QA.Gallery(ids,role)
    assert(game:GetService("RunService"):IsStudio(),"Studio only")
    QA.ClearGallery()
    gallery=Instance.new("Folder");gallery.Name="DogVisualQAGallery";gallery.Parent=workspace
    local cameras={}
    for i,entry in ipairs(ordered(ids)) do
        local model=assert(Storage.DogTemplates:FindFirstChild(entry.Definition.VisualAsset)):Clone()
        model.Name=entry.Id
        local prepared=assert(Rig.Prepare(model,Vector3.new(8,5,8)))
        local point=Vector3.new(((i-1)%10)*13,1000,math.floor((i-1)/10)*15)
        Rig.Place(model,point);model:SetAttribute("DogId",entry.Id);model.Parent=gallery
        local plate=Instance.new("Part");plate.Name=entry.Id.."_Stage";plate.Size=Vector3.new(11,.25,12)
        plate.Anchored=true;plate.Position=point-Vector3.new(0,.15,0);plate.Color=Color3.fromRGB(48,55,66);plate.Parent=gallery
        local text=Instance.new("BillboardGui");text.Size=UDim2.fromOffset(240,42)
        text.Adornee=model.PrimaryPart;text.StudsOffsetWorldSpace=Vector3.new(0,6,0);text.AlwaysOnTop=true;text.Parent=model
        local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
        label.Text=entry.Definition.Index.." · "..entry.Id;label.TextColor3=Color3.new(1,1,1);label.TextSize=18;label.Parent=text
        local player=Animation.new(model,entry.Id);players[entry.Id]=player
        local clip=Animation.ResolveName(entry.Id,role or "Walk") or Animation.ResolveName(entry.Id,"Idle")
        player:Play(clip,{Looped=true,FadeTime=0});player:Sample(player.Clip.Duration*.35)
        cameras[entry.Id]=CFrame.lookAt(point+Vector3.new(8,5,-12),point+Vector3.new(0,2.5,0))
    end
    return cameras
end
-- Visual review of the kennel dig chains (Studio, Run mode): the gallery dogs work through
-- DogAnimationPlayer:UpdateKennel exactly like kennel dogs on clients: DigStart, the loop,
-- an accent landing on every find (every `cycle` seconds), then storage "fills up" for
-- `rest` seconds (DigEnd -> Idle) and they start again. Returns a function that stops it.
--   require(game.ServerStorage.DogVisualQA).KennelPreview({"CoffeeDog","404Dog","MechaBark"},12)
function QA.KennelPreview(ids,cycle,rest,workSeconds)
    cycle=math.max(tonumber(cycle) or 12,4);rest=tonumber(rest) or 10;workSeconds=tonumber(workSeconds) or cycle*3
    local cameras=QA.Gallery(ids,"Idle")
    local states={}
    local started=workspace:GetServerTimeNow()
    for id,player in pairs(players) do
        player.Kennel=nil
        states[id]={Working=true,AssignedAt=started,NextWorkAt=started+4,WorkSequence=0,WorkCycle=cycle}
    end
    local connection
    connection=game:GetService("RunService").Heartbeat:Connect(function()
        if not gallery or not gallery.Parent then connection:Disconnect();return end
        local now=workspace:GetServerTimeNow()
        local phase=(now-started)%(workSeconds+rest)
        for id,player in pairs(players) do
            local info=states[id]
            local working=phase<workSeconds
            if working and not info.Working then info.NextWorkAt=now+4 end
            info.Working=working
            if working and now>=info.NextWorkAt then
                info.WorkSequence+=1;info.NextWorkAt+=cycle
            end
            player:UpdateKennel(info,now,true)
            player:Step(now)
        end
    end)
    return function() if connection then connection:Disconnect() end end,cameras
end
function QA.Sample(seconds,role)
    for id,player in pairs(players) do
        if role then
            local name=Animation.ResolveName(id,role)
            if name and player.Name~=name then player:Play(name,{Looped=true,FadeTime=0}) end
        end
        player:Sample(seconds)
    end
end
function QA.RunGait(ids,speed)
    return require(Storage.DogGaitQA).Run(ids,speed)
end
function QA.WalkSample(seconds,speed)
    speed=speed or 4
    for i,entry in ipairs(ordered()) do
        local player=players[entry.Id]
        if player and player.Gait then
            local model=player.Model
            local point=Vector3.new(((i-1)%10)*13,1000,math.floor((i-1)/10)*15)
            -- Keep a selected gallery's own stage as its travel origin.
            local plate=gallery:FindFirstChild(entry.Id.."_Stage")
            if plate then point=plate.Position+Vector3.new(0,.15,0) end
            Rig.Place(model,point+Vector3.new(0,0,-speed*seconds))
            model:SetAttribute("LocomotionSpeed",speed)
            local gait=player.Gait
            gait.LastTime=seconds;gait:Advance(seconds,speed)
            gait.Phase=(seconds*gait.Frequency)%1
            gait.RollDistance=seconds*speed
            local phase=if gait.Profile.Reverse and gait.Profile.Mode=="walk" then (1-gait.Phase)%1 else gait.Phase
            player:Sample(phase*player.Clip.Duration)
            gait:Apply(1)
        end
    end
end
return QA
