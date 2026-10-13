-- Rewards commit before presentation. Clients animate from the server clock.
-- Many players can activate at once: each player has their own in-flight lock, and the shared
-- world drum plays the committed results one after another (presentation queue). A result that
-- would wait longer than MaxQueueWait is revealed on the winner's own screen instead (Personal)
-- so nobody is refused because someone else is spinning. Presentation errors never turn a
-- committed reward into a failure, and the per-player lock is released on every path.
local RS=game:GetService('ReplicatedStorage');local Http=game:GetService('HttpService')
local district=workspace:WaitForChild('DOGROTS_District')
local rig=district:WaitForChild('37_AttractionRefresh'):WaitForChild('RewardMachineRig')
local machine=district:WaitForChild('27_RewardMachinePlaza'):WaitForChild('RewardMachine')
local prompt=assert(machine:FindFirstChild('RewardMachinePrompt',true),'Reward machine prompt missing')
local motion=require(RS.RewardMachineMotion);local config=require(RS.RewardMachineConfig);local Text=require(RS.RewardMachineText)
local service=require(script.Parent.Economy.RewardMachineService);local commerce=require(script.Parent.Economy.YardCommerce)
local center=rig.CameraHooks.DrumCenter.CFrame;local drum=rig.SpinningDrum
local remote=RS:FindFirstChild('RewardMachinePresentation')or Instance.new('RemoteEvent');remote.Name='RewardMachinePresentation';remote.Parent=RS
local MaxQueueWait,Gap,StaleLock=10,1,30
-- Tail: server time the last queued drum presentation ends. Angle: where that one stops.
local queue={Tail=0,Angle=0,Count=0}
local busyBy={};local playerAttempts={};local animated={}
-- Presentations currently counted in queue.Count (released exactly once: reveal or failure).
local counted=setmetatable({},{__mode='k'})
local function setSpinning(on)rig:SetAttribute('Spinning',on);machine:SetAttribute('Spinning',on)end
local function release(presentation)
 if not counted[presentation]then return end
 counted[presentation]=nil;queue.Count=math.max(0,queue.Count-1)
 if queue.Count==0 then setSpinning(false)end
end
local function clearPrize()local old=rig:FindFirstChild('CommittedPrize');if old then old:Destroy()end end
local Reveal=require(script.Parent.SecretReveal)
local function display(result,winner)
 clearPrize();local container=Instance.new('Model');container.Name='CommittedPrize';container.Parent=rig
 local focus=rig.CameraHooks.RevealFocus;local spawn=rig.CameraHooks.RewardSpawn
 rig.WorldResult.Lettering.Title.Text=(motion.UltraRare(result)and 'ULTRA RARE!  'or '')..result.Name
 local secret=result.Dog and Reveal.Has(result.Dog.DogId)
  and require(script.Parent.Economy.DogDefinitions)[result.Dog.DogId].Rank==6
 if secret then
  -- A Secret prize performs its arrival on the reward stand and stays as the prize.
  local ok,model=pcall(Reveal.Show,result.Dog.DogId,spawn.Position,CFrame.Angles(0,-math.pi/2,0).LookVector,
   {Venue='Machine',By=winner,Linger=false,Parent=container})
  if not ok or not model then secret=false end
 end
 if secret then
  -- Already on the stand (SecretReveal).
 elseif result.Dog then
  local def=require(script.Parent.Economy.DogDefinitions)[result.Dog.DogId]
  local source=def and game.ServerStorage.DogTemplates:FindFirstChild(def.VisualAsset)
  if source then
   local model=source:Clone();model.Name='WinningDog'
   for _,o in ipairs(model:GetDescendants())do
    if o:IsA('LuaSourceContainer')or o:IsA('ProximityPrompt')or o:IsA('Sound')or o:IsA('BillboardGui')or o:IsA('SurfaceGui')then o:Destroy()
    elseif o:IsA('BasePart')then o.Anchored=true;o.CanCollide=false;o.CanTouch=false;o.CanQuery=false end
   end
   local prepared=require(RS.DogRig).Prepare(model,Vector3.new(12,10,12))
   if prepared then
    local cf,size=model:GetBoundingBox();local target=CFrame.new(spawn.Position+Vector3.new(0,size.Y/2,0))*CFrame.Angles(0,-math.pi/2,0)
    model:PivotTo(target*cf:Inverse()*model:GetPivot());model.Parent=container
   else model:Destroy()end
  end
 elseif result.Item then
  local model=require(RS.DogEconomy.DiscoveryVisuals).Clone(result.Item)
  if model then local cf,size=model:GetBoundingBox();model:ScaleTo(model:GetScale()*math.min(3,11/math.max(size.X,size.Y,size.Z)));cf,size=model:GetBoundingBox();model:PivotTo(CFrame.new(spawn.Position+Vector3.new(0,size.Y/2,0))*cf:Inverse()*model:GetPivot());model.Parent=container end
 else
  -- Use the same authored reward models as the offer previews: embossed coins,
  -- a recognizable bone, and the labeled energy snack instead of generic balls.
  local model=require(RS.EconomyRewardVisuals).Build(result)
  if model then
   model.Name='Winning'..result.Kind
   for _,o in ipairs(model:GetDescendants())do
    if o:IsA('BasePart')then o.Anchored=true;o.CanCollide=false;o.CanTouch=false;o.CanQuery=false
    elseif o:IsA('TextLabel')or o:IsA('TextButton')then o.Font=Enum.Font.FredokaOne
    elseif o:IsA('LuaSourceContainer')or o:IsA('ProximityPrompt')or o:IsA('Sound')then o:Destroy()end
   end
   local cf,size=model:GetBoundingBox();local extent=math.max(size.X,size.Y,size.Z)
   if extent>0 then
    model:ScaleTo(model:GetScale()*12/extent);cf,size=model:GetBoundingBox()
    local target=spawn.CFrame*CFrame.new(0,size.Y/2,0)
    model:PivotTo(target*cf:Inverse()*model:GetPivot());model.Parent=container
   else model:Destroy()end
  end
 end
 local anchor=Instance.new('Part');anchor.Name='RewardLabel';anchor.Anchored=true;anchor.CanCollide=false;anchor.CanQuery=false;anchor.CanTouch=false;anchor.Transparency=1;anchor.Size=Vector3.one;anchor.CFrame=focus.CFrame*CFrame.new(0,13,0);anchor.Parent=container
 local gui=Instance.new('BillboardGui');gui.Enabled=false;gui.Size=UDim2.fromOffset(360,92);gui.MaxDistance=130;gui.AlwaysOnTop=false;gui.Parent=anchor
 local text=Instance.new('TextLabel');text.Size=UDim2.fromScale(1,1);text.BackgroundColor3=Color3.fromRGB(14,19,45);text.BackgroundTransparency=.12;text.Font=Enum.Font.FredokaOne;text.TextSize=27;text.TextWrapped=true;text.TextColor3=motion.Color(result);text.TextStrokeTransparency=.5
 text.Text=(motion.UltraRare(result)and 'ULTRA RARE!  'or '')..result.Name..'\n'..motion.Rarity(result):upper();text.Parent=gui
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,16);corner.Parent=text
end
-- The world part of one presentation: cue for every client, then the reveal at its end.
local function worldCue(player,result,presentation)
 local index=presentation.PrizeIndex
 local cue={Receipt=result.Receipt,Id=result.Id,Name=result.Name,Kind=result.Kind,Jackpot=result.Jackpot,Rarity=presentation.Rarity,Chance=result.Chance,ChanceText=result.ChanceText,
  TierName=result.TierName,EventBoost=result.EventBoost,WinnerName=player.DisplayName,WinnerUserId=player.UserId,Presentation=presentation}
 local payload=Http:JSONEncode(cue)
 setSpinning(true)
 rig:SetAttribute('SpinInfo',payload);rig:SetAttribute('WinnerUserId',player.UserId);remote:FireAllClients(cue)
 local winner=player.DisplayName
 task.delay(math.max(0,presentation.StartedAt-workspace:GetServerTimeNow()),function()
  pcall(function()rig.WorldResult.Lettering.Title.Text='ACTIVATING...'end)
 end)
 task.delay(math.max(0,presentation.StartedAt+presentation.Duration-workspace:GetServerTimeNow()),function()
  local success,err=pcall(function()
   local angle=motion.Target(index);drum:PivotTo(center*CFrame.Angles(0,0,angle));rig:SetAttribute('RestAngle',angle)
   rig:SetAttribute('LastReward',result.Name);machine:SetAttribute('LastReward',result.Name);display(result,winner)
  end)
  if not success then warn('Reward machine reveal deferred:',err)end
  release(presentation)
 end)
end
local function schedule(player,result,args)
 local index=tonumber(result.PrizeIndex)
 if not index or not config.Rewards[index]then index=1 end
 local serverNow=workspace:GetServerTimeNow();local requested=tonumber(args and args.StartedAt)
 if not requested or requested~=requested or requested<serverNow-1 or requested>serverNow+.15 then requested=serverNow end
 local startAt=queue.Tail>requested and queue.Tail+Gap or requested
 local presentation;local previousTail,previousAngle=queue.Tail,queue.Angle
 if startAt-serverNow>MaxQueueWait then
  presentation={StartedAt=serverNow,Duration=motion.QuickDuration,PrizeIndex=index,Rarity=motion.Rarity(result),StartAngle=0,Personal=true}
 else
  presentation={StartedAt=startAt,Duration=motion.Duration,PrizeIndex=index,Rarity=motion.Rarity(result),StartAngle=queue.Angle,Queued=startAt>requested+.05 or nil}
  queue.Tail=startAt+motion.Duration;queue.Angle=motion.Target(index);queue.Count+=1;counted[presentation]=true
 end
 result.Presentation=presentation;animated[result.Receipt]=presentation
 task.delay(120,function()animated[result.Receipt]=nil end)
 if presentation.Personal then return end
 local ok,err=pcall(worldCue,player,result,presentation)
 if not ok then
  -- The reward is already saved: show it on the winner's screen instead of failing.
  warn('Reward machine world cue failed:',err)
  pcall(release,presentation)
  -- Give the unused drum slot back when nothing was queued after it.
  if queue.Tail==presentation.StartedAt+presentation.Duration then queue.Tail,queue.Angle=previousTail,previousAngle end
  presentation.StartedAt=serverNow;presentation.Duration=motion.QuickDuration;presentation.Personal=true;presentation.Queued=nil
 end
end
-- Rule refusals are short sentences; a script error (path:line:) is never shown to players.
local function playerMessage(message)
 message=tostring(message or '')
 if message==''or message:find('^[%w%._ ]+:%d+:')or message:find('ServerScriptService%.')then return 'Activation unavailable; please retry'end
 return message
end
local function activate(player,args)
 local transport,ok,result=pcall(service.Request,player,'RewardMachineActivate',args,true)
 if not transport then return false,playerMessage(ok)end
 if not ok then return false,playerMessage(result)end
 if type(result)~='table'then return false,'Activation unavailable; please retry'end
 local shown=animated[result.Receipt]
 if shown then result.Presentation=shown;return true,result end
 if result.Duplicate or os.time()-(result.At or 0)>10 then return true,result end
 schedule(player,result,args)
 return true,result
end
service.WorldEligibility=function(player)local near=commerce.Near(player,prompt.Parent,18);return near,near and nil or 'Move closer to DOG-O-MATIC'end
service.RequestWorldSpin=function(player,args)
 local userId=player.UserId;local clock=os.clock()
 local since=busyBy[userId]
 if since and clock-since<StaleLock then return false,'Your previous activation is still being processed'end
 if clock-(playerAttempts[userId]or -5)<2 then return false,'Please wait before trying again'end
 playerAttempts[userId]=clock
 if not commerce.Near(player,prompt.Parent,18)then return false,'Move closer to DOG-O-MATIC'end
 busyBy[userId]=clock
 local ran,ok,result=xpcall(activate,function(err)return debug.traceback(tostring(err),2)end,player,args)
 if busyBy[userId]==clock then busyBy[userId]=nil end
 if not ran then warn('DOG-O-MATIC activation failed:',ok);return false,'Activation unavailable; please retry'end
 return ok,result
end
-- World board: base odds, or the boosted Aurion row while the event runs. Sector dogs rotate.
local boostKey,symbolsAt=nil,0
local function refreshBoard()
 local boost=service.EventBoost(os.time())
 local key=boost and(boost.EventId..':'..boost.Multiplier)or''
 if key~=boostKey then
  boostKey=key
  rig:SetAttribute('AurionBoost',boost and boost.Multiplier or nil);rig:SetAttribute('AurionBoostEvent',boost and boost.EventId or nil)
  rig:SetAttribute('AurionBoostEndsAt',boost and boost.EndsAt or nil)
  -- Sector dogs only change while the drum rests (clients animate it locally mid-spin).
  Text.Apply(rig,Text.Pool(boost and boost.Multiplier),queue.Count>0)
 elseif os.clock()-symbolsAt>=60 and queue.Count==0 then
  Text.ApplySymbols(rig)
 else return end
 symbolsAt=os.clock()
end
local okBoard,boardError=pcall(refreshBoard);if not okBoard then warn('Reward machine board deferred:',boardError)end
task.spawn(function()
 while true do
  task.wait(2)
  local ok,err=pcall(refreshBoard);if not ok then warn('Reward machine board deferred:',err)end
 end
end)
prompt.ActionText='ACTIVATE · 1 DOG TOKEN';prompt.ObjectText='DOG-O-MATIC';prompt.HoldDuration=0;prompt.Enabled=true
prompt.Triggered:Connect(function(player)if commerce.Near(player,prompt.Parent,18)then RS.DogEconomyOpen:FireClient(player,'RewardMachine')end end)
game.Players.PlayerRemoving:Connect(function(player)playerAttempts[player.UserId]=nil;busyBy[player.UserId]=nil;service.Forget(player.UserId)end)
print('DOGROTS_REWARD_MACHINE_READY')
