local RS=game:GetService('ReplicatedStorage');local Players=game:GetService('Players');local Http=game:GetService('HttpService');local Run=game:GetService('RunService')
local package=RS:WaitForChild('WorldEvents');local C=require(package.WorldEventConfig);local D=require(package.WorldEventDefinitions);local Schedule=require(package.WorldEventSchedule);local Modifiers=require(package.WorldEventModifiers);local Visuals=require(package.WorldEventObjects)
local Runtime=require(script.Parent.Economy.Runtime);local R=require(script.Parent.Economy.Rules);local I=require(script.Parent.Economy.ItemRules)
local stateFolder=package:WaitForChild('State');local fx=workspace:WaitForChild('WorldEventFX');local map=workspace:WaitForChild('DOGROTS_District');local rng=Random.new()
-- What the event does to the island (gravity, movement, the tongue, bones, the end reward).
local Gameplay=require(script.Parent.WorldEventGameplay)
-- DOG RUSH runaway pups: spawn rules (DogRush) and the saved progress / rewards (Features.DogRush).
local Rush=require(package:WaitForChild('DogRush'))
local RushProgress=require(script.Parent.Economy.Features.DogRush)
local S={Current=nil,Objects={},DebugState=nil,PupCooldown={},PupTouch={},PupCapped={},NextPup=0};local serial=0
local DigConfig=require(RS:WaitForChild('GlobalDigConfig'))
-- The Global Dig quarry sits behind the closed COMING SOON cover while GlobalDigConfig is
-- disabled; pickups placed there could never be reached. Site-only rewards then use the
-- Welcome Hub plaza (the client event stage) and the back district beside it.
local function points(siteOnly)
 local result={};local site=map:FindFirstChild('08_GlobalDigSite');local siteOpen=DigConfig.Enabled~=false
 local function collect(search)
  for _,o in ipairs(search:GetDescendants())do if o.Name=='WorldEventSpawnPoints'and(siteOpen or not(site and o:IsDescendantOf(site)))then
   for _,a in ipairs(o:GetChildren())do if a:IsA('BasePart')then table.insert(result,a)end end
  end end
 end
 if siteOnly and siteOpen and site then collect(site)
 elseif siteOnly then
  for _,name in ipairs({'32_WelcomeHub','31_BackDistrictExpansion'})do local area=map:FindFirstChild(name);if area then collect(area)end end
  if #result==0 then collect(map)end
 else collect(map)end
 return result
end
-- Checks shared by every pickup (prompt or touch): the event is live, the object is still there and
-- unclaimed, the profile is ready, the request budget allows it and the character is alive and close.
local function precheck(player,model,distance)
 local current=S.Current;local info=S.Objects[model]
 if not info or not current or current.State~='ACTIVE'or os.time()>=current.ActiveEndTimestamp or not model.Parent or os.time()>=info.Expires then return nil,'This event opportunity has ended'end
 if info.Claimed or info.Claiming then return nil,'This object has already been collected'end
 if not Runtime.Ready(player)or not Runtime.Allow(player,2)then return nil,'Please wait'end
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
 if not root or not hum or hum.Health<=0 or (root.Position-model:GetPivot().Position).Magnitude>distance then return nil,'Move closer'end
 return info,current,root
end
-- A free Lucky Block for the DOG RUSH golden chest, only when the block storage has room
-- (LuckyLifecycle.AddStored: a stored, non-paid block). Otherwise the chest pays extra bones.
local function addRushBlock(p,tier,count)
 local cap=require(RS:WaitForChild('LuckyLifecycleConfig')).InventoryCapacity or 0
 if R.Count(type(p.OwnedBlocks)=='table'and p.OwnedBlocks or {})+count>cap then return false end
 local ids=require(script.Parent.Economy.LuckyLifecycle).AddStored(p,tier,count,'DogRush',false)
 return type(ids)=='table'and #ids==count
end
-- DOG RUSH: catching a runaway pup (prompt or touch). Same validation and RAM claim as every pickup;
-- the reward, the per-event cap and the chests are Features.DogRush.Catch in the profile transaction.
function S.CatchPup(player,model)
 if os.clock()<(S.PupCooldown[player]or 0)then return false,'Please wait'end
 local info,current,root=precheck(player,model,Rush.Pups.Distance)
 if not info then return false,current end
 info.Claiming=true
 local generation=current.Generation;local now=os.time()
 local ok,result=Runtime.Tx:Run({'p:'..player.UserId},function(v)
  local p=v['p:'..player.UserId];Runtime.Engine:Authorize(p,player.UserId)
  R.Check(S.Current and S.Current.State=='ACTIVE'and S.Current.Generation==generation and os.time()<info.Expires and model.Parent and S.Objects[model]==info and not info.Claimed,'This event opportunity has ended')
  R.Check((root.Position-model:GetPivot().Position).Magnitude<=Rush.Pups.Distance,'Move closer')
  local claims=p.WorldEventClaims
  if not claims or claims.Generation~=generation then claims={Generation=generation,Count=0,Objects={}};p.WorldEventClaims=claims end
  R.Check(not claims.Objects[info.Id],'You already collected this reward')
  claims.Objects[info.Id]=true
  local reward=RushProgress.Catch(R,p,generation,now,addRushBlock)
  R.Validate(p);return reward
 end,'eventcollect:'..player.UserId..':'..info.Id)
 if ok then
  info.Claimed=true;info.Claiming=false;S.PupCooldown[player]=os.clock()+Rush.Pups.Cooldown
  if result.Caught>=Rush.Pups.PerEvent then S.PupCapped[player]=generation end
  local objectId=info.Id;local position=model:GetPivot().Position
  if model.Parent then model:Destroy()end;S.Objects[model]=nil
  player:SetAttribute('DogRushGeneration',generation);player:SetAttribute('DogRushPups',result.Caught)
  package.Signal:FireClient(player,{Kind='PupCaught',EventId=current.EventId,Reward=result,Position=position,ObjectId=objectId})
  -- Everyone nearby sees the happy burst (no reward details).
  for _,other in ipairs(Players:GetPlayers())do
   local otherRoot=other~=player and other.Character and other.Character:FindFirstChild('HumanoidRootPart')
   if otherRoot and (otherRoot.Position-position).Magnitude<120 then package.Signal:FireClient(other,{Kind='PupCaughtNearby',Position=position})end
  end
  if #result.Chests>0 then RS.RewardPresentation:FireClient(player,{Cue='Reward'})end
  task.defer(function()if player.Parent and Runtime.Ready(player)then Runtime.Refresh(player)end end)
 else
  info.Claiming=false
  if result=='You caught every pup you can this rush!'then S.PupCapped[player]=generation end
 end
 return ok,result
end
function S.Interact(player,model)
 local kind=S.Objects[model]and S.Objects[model].Kind
 if kind=='RunawayPup'then return S.CatchPup(player,model)end
 local info,current,root=precheck(player,model,C.Interactions.Distance)
 if not info then return false,current end
 -- The physical event object only exists on this server. Claim it in server RAM
 -- before the profile transaction so two players can never collect it twice,
 -- without paying for a global DataStore eventobject:<id> lock.
 info.Claiming=true
 local generation=current.Generation;local seed=rng:NextInteger(1,2147483646);local uid=Http:GenerateGUID(false):gsub('-','')
 local ok,result=Runtime.Tx:Run({'p:'..player.UserId},function(v)
  local p=v['p:'..player.UserId];Runtime.Engine:Authorize(p,player.UserId)
  R.Check(S.Current and S.Current.State=='ACTIVE'and S.Current.Generation==generation and os.time()<info.Expires and model.Parent and S.Objects[model]==info and not info.Claimed,'This event opportunity has ended')
  local claims=p.WorldEventClaims
  if not claims or claims.Generation~=generation then claims={Generation=generation,Count=0,Objects={}};p.WorldEventClaims=claims end
  R.Check(not claims.Objects[info.Id],'You already collected this reward')
  R.Check(os.time()>=(p.NextWorldEventCollect or 0)and claims.Count<C.Interactions.PerEvent,'Take a break from collecting')
  R.Check((root.Position-model:GetPivot().Position).Magnitude<=C.Interactions.Distance,'Move closer')
  claims.Objects[info.Id]=true;claims.Count+=1;p.NextWorldEventCollect=os.time()+C.Interactions.Cooldown
  local reward={Cash=C.Interactions.Cash,Bones=C.Interactions.Bones};R.Credit(p,reward.Cash);p.Bones+=reward.Bones
  local random=Random.new(seed);local roll=function()return random:NextNumber()end
  if I.Free(p)then local def,chance=I.Pick(p.CurrentLayer,roll,R.Team(p,os.time()))
   if def then local found=I.Mint(p,def,chance,uid,os.time(),roll,R.Team(p,os.time()));found.Origin='WorldEvent:'..current.EventId;reward.Item=R.Copy(found)end
  end
  R.Validate(p);return reward
 end,'eventcollect:'..player.UserId..':'..info.Id)
 if ok then
  info.Claimed=true;info.Claiming=false
  local objectId=info.Id;local position=model:GetPivot().Position
  -- Remove the pickup before any heavier profile/world projection. The reward is
  -- already committed to the RAM profile at this point.
  if model.Parent then model:Destroy()end;S.Objects[model]=nil
  package.Signal:FireClient(player,{Kind='Reward',EventId=current.EventId,Reward=result,Position=position,ObjectId=objectId})
  RS.RewardPresentation:FireClient(player,{Cue='Reward'})
  task.defer(function()if player.Parent and Runtime.Ready(player)then Runtime.Refresh(player)end end)
 else
  info.Claiming=false
 end
 return ok,result
end
function S.SpawnObject(kind,special)
 local current=S.Current;if not current or current.State~='ACTIVE'then return end
 local def=D.ById[current.EventId];local count=0;for model in pairs(S.Objects)do if model.Parent then count+=1 end end
 if count>=C.Interactions.MaxActive then return end
 local siteOnly=kind=='ChargedCrystal'or kind=='AlienDigZone'or special
 local candidates=points(siteOnly);if #candidates==0 then return end
 local point,surface
 local cast=RaycastParams.new();cast.FilterType=Enum.RaycastFilterType.Include;cast.FilterDescendantsInstances={map};cast.RespectCanCollide=true
 -- Anchors move with their district. Verify their current floor before placing a reward.
 for attempt=1,#candidates do
  local i=rng:NextInteger(1,#candidates);local candidate=table.remove(candidates,i)
  local hit=workspace:Raycast(candidate.Position+Vector3.new(0,3,0),Vector3.new(0,-15,0),cast)
  local occupied=false
  for object,info in pairs(S.Objects)do if object.Parent and info.Anchor==candidate then occupied=true;break end end
  if hit and hit.Normal.Y>.65 and not occupied then point=candidate;surface=hit.Position;break end
 end
 if not point then return end
 local model=Visuals.Build(kind,def.ColorTheme)
 if kind=='GiantBone'then model:ScaleTo(3)end
 model:PivotTo(point.CFrame+Vector3.new(0,1,0))
 local box,size=model:GetBoundingBox();local bottom=box.Position.Y-size.Y/2
 model:PivotTo(model:GetPivot()+Vector3.new(0,surface.Y+.06-bottom,0));model.Parent=fx
 model:SetAttribute('Grounded',true)
 local lifetime=kind=='AlienDigZone'and 15 or special and 25 or C.Interactions.ObjectLifetime
 local id=Http:GenerateGUID(false):gsub('-','');local expires=math.min(current.ActiveEndTimestamp,os.time()+lifetime)
 S.Objects[model]={Id=id,Expires=expires,Anchor=point,Local=point.CFrame:ToObjectSpace(model:GetPivot())};model:SetAttribute('EventObjectId',id);model:SetAttribute('ExpiresAt',expires)
 local prompt=Instance.new('ProximityPrompt');prompt.Name='WorldEventPickupPrompt';prompt.ActionText=kind=='TreasureSpot'and 'DIG'or 'COLLECT';prompt.ObjectText=kind:gsub('(%l)(%u)','%1 %2');prompt.HoldDuration=0;prompt.RequiresLineOfSight=false;prompt.MaxActivationDistance=12;prompt.Parent=model.PrimaryPart
 prompt.Triggered:Connect(function(player)local objectId=model:GetAttribute('EventObjectId');local ok,msg=S.Interact(player,model);if not ok then package.Signal:FireClient(player,{Kind='Hint',Message=tostring(msg),ObjectId=objectId})end end)
 model.Destroying:Connect(function()S.Objects[model]=nil end)
 return model
end
-- DOG RUSH: one runaway pup at a street point (WorldEvents.DogRush.PickSpawn). The floor under the
-- point is checked first (a street at street height, never a roof). Atomic streaming: a pup arrives
-- on a client whole. Caught with the prompt or by running into its CatchZone.
function S.SpawnPup(at)
 local current=S.Current;if not current or current.State~='ACTIVE'then return end
 local count=0;for model in pairs(S.Objects)do if model.Parent then count+=1 end end
 if count>=C.Interactions.MaxActive then return end
 local cast=RaycastParams.new();cast.FilterType=Enum.RaycastFilterType.Include;cast.FilterDescendantsInstances={map};cast.RespectCanCollide=true
 local hit=workspace:Raycast(at+Vector3.new(0,6,0),Vector3.new(0,-14,0),cast)
 if not hit or hit.Normal.Y<.65 or math.abs(hit.Position.Y-at.Y)>2.5 then return end
 local model=Visuals.Build('RunawayPup',D.ById[current.EventId].ColorTheme)
 model:PivotTo(CFrame.new(hit.Position+Vector3.new(0,1,0))*CFrame.Angles(0,rng:NextNumber(0,math.pi*2),0))
 local box,size=model:GetBoundingBox();local bottom=box.Position.Y-size.Y/2
 model:PivotTo(model:GetPivot()+Vector3.new(0,hit.Position.Y+.04-bottom,0))
 model.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
 local id=Http:GenerateGUID(false):gsub('-','');local expires=math.min(current.ActiveEndTimestamp,os.time()+Rush.Pups.Lifetime)
 S.Objects[model]={Id=id,Expires=expires,Kind='RunawayPup',Position=hit.Position}
 model:SetAttribute('EventObjectId',id);model:SetAttribute('ExpiresAt',expires);model:SetAttribute('Grounded',true)
 local prompt=Instance.new('ProximityPrompt');prompt.Name='WorldEventPickupPrompt';prompt.ActionText='CATCH';prompt.ObjectText='Runaway pup'
 prompt.HoldDuration=0;prompt.RequiresLineOfSight=false;prompt.MaxActivationDistance=10;prompt.Parent=model.PrimaryPart
 prompt.Triggered:Connect(function(player)
  local ok,msg=S.Interact(player,model)
  if not ok then package.Signal:FireClient(player,{Kind='Hint',Message=tostring(msg),ObjectId=id})end
 end)
 local zone=model:FindFirstChild('CatchZone')::BasePart?
 if zone then zone.Touched:Connect(function(part)
  local character=part.Parent;local player=character and Players:GetPlayerFromCharacter(character)
  if not player and character and character.Parent then player=Players:GetPlayerFromCharacter(character.Parent)end
  if not player then return end
  -- Cheap filters before the request budget: one try per 0.75 s, not after the per-event cap.
  local info=S.Objects[model];local live=S.Current
  if not info or info.Claimed or info.Claiming or not live or S.PupCapped[player]==live.Generation then return end
  if os.clock()<(S.PupTouch[player]or 0)or os.clock()<(S.PupCooldown[player]or 0)then return end
  S.PupTouch[player]=os.clock()+.75
  local ok,msg=S.CatchPup(player,model)
  if not ok and msg=='You caught every pup you can this rush!'then package.Signal:FireClient(player,{Kind='Hint',Message=msg})end
 end)end
 model.Destroying:Connect(function()S.Objects[model]=nil end)
 -- Parented last: the pup reaches clients complete (prompt included).
 model.Parent=fx
 return model
end
function S.PupTick(now)
 local current=S.Current
 if now<current.StartTimestamp+Rush.Pups.FirstAfter or now<(S.NextPup or 0)then return end
 local live,occupied=0,{}
 for model,info in pairs(S.Objects)do if model.Parent and info.Kind=='RunawayPup'then live+=1;table.insert(occupied,info.Position)end end
 local players=Players:GetPlayers()
 if live>=Rush.TargetPups(#players)then return end
 S.NextPup=now+Rush.Pups.SpawnEvery
 local near={}
 for _,player in ipairs(players)do local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');if root then table.insert(near,root.Position)end end
 local at=Rush.PickSpawn(function()return rng:NextNumber()end,near,occupied)
 if at then S.SpawnPup(at)end
end
-- The DOG RUSH chip (WorldEventGameplayFX) reads these: pups caught in this event's generation.
local function syncPups(player,current)
 local p=Runtime.Views[player.UserId];local d=p and type(p.DogRush)=='table'and p.DogRush or nil
 local caught=d and d.Generation==current.Generation and tonumber(d.Caught)or 0
 player:SetAttribute('DogRushGeneration',current.Generation);player:SetAttribute('DogRushPups',caught)
 if caught>=Rush.Pups.PerEvent then S.PupCapped[player]=current.Generation end
end
local function journal(player,current)
 if not Runtime.Ready(player)then return end
 local p=Runtime.Views[player.UserId];if p and p.WorldEventsSeen and p.WorldEventsSeen[current.EventId]then return end
 local ok,new=Runtime.Tx:Run({'p:'..player.UserId},function(v)
  local p=v['p:'..player.UserId];Runtime.Engine:Authorize(p,player.UserId);p.WorldEventsSeen=p.WorldEventsSeen or {}
  if p.WorldEventsSeen[current.EventId]then return false end
  p.WorldEventsSeen[current.EventId]={FirstSeen=os.time(),Rarity=D.ById[current.EventId].Rarity};R.Validate(p);return true
 end)
 if ok then Runtime.Refresh(player);if new then package.Signal:FireClient(player,{Kind='Discovered',EventId=current.EventId})end end
end
function S.Apply(nextState)
 local old=S.Current;local changed=not old or old.State~=nextState.State or old.Cycle~=nextState.Cycle or old.EventId~=nextState.EventId
 if not changed then return end
 local generation=nextState.Generation or tostring(nextState.Cycle)..':'..nextState.EventId
 if old and old.Generation~=generation then for model in pairs(S.Objects)do model:Destroy()end;S.Objects={}end
 nextState.Generation=generation;S.Current=nextState
 if nextState.State=='ACTIVE'then Modifiers.Set(nextState.EventId,nextState.ActiveEndTimestamp)
 else Modifiers.Set(nil);for model in pairs(S.Objects)do model:Destroy()end;fx:ClearAllChildren();S.Objects={}end
 local applied,err=pcall(Gameplay.Apply,nextState);if not applied then warn('WORLD EVENT gameplay apply:',err)end
 for k,v in pairs(nextState)do if type(v)=='string'or type(v)=='number'then stateFolder:SetAttribute(k,v)end end
 serial+=1;stateFolder:SetAttribute('Revision',serial)
 if nextState.State=='ACTIVE'then
  local def=D.ById[nextState.EventId];S.NextSpawn=0;S.NextPup=0;S.SignatureAt=nextState.StartTimestamp+def.SignatureSeconds;S.SignatureDone=false
  if def.Id==Rush.EventId then for _,p in ipairs(Players:GetPlayers())do syncPups(p,nextState)end end
  for _,p in ipairs(Players:GetPlayers())do task.spawn(journal,p,nextState)end
 end
 package:WaitForChild('Changed'):FireAllClients(nextState)
end
function S.Force(id,duration,warning)
 assert(Run:IsStudio() and C.Debug.EnabledInStudio,'Studio-only event controls')
 serial+=1;local now=os.time();local start=now+(warning or 0);local finish=start+(duration or C.EventDuration)
 if id=='stop'then S.DebugState={State='NORMAL',EventId='BONE_RAIN',Cycle=-serial,StartTimestamp=now+600,EndTimestamp=now+600,NextEventTimestamp=now+660,ActiveEndTimestamp=now+900,Hold=true};S.Apply(S.DebugState);return end
 assert(D.ById[id],'Unknown event');S.DebugState={State=(warning or 0)>0 and 'WARNING'or 'ACTIVE',EventId=id,Cycle=-serial,StartTimestamp=start,EndTimestamp=(warning or 0)>0 and start or finish,NextEventTimestamp=start,ActiveEndTimestamp=finish,Generation='dev:'..serial}
 S.Apply(R.Copy(S.DebugState))
end
function S.Tick()
 local now=os.time();local state
 if S.DebugState then
  state=R.Copy(S.DebugState)
  if not state.Hold then
   if now<state.StartTimestamp then state.State='WARNING';state.EndTimestamp=state.StartTimestamp
   elseif now<state.ActiveEndTimestamp then state.State='ACTIVE';state.EndTimestamp=state.ActiveEndTimestamp
   elseif now<state.ActiveEndTimestamp+C.TransitionDuration then state.State='ENDING';state.EndTimestamp=state.ActiveEndTimestamp+C.TransitionDuration
   else S.DebugState=nil;state=Schedule.At(now)end
  end
 else state=Schedule.At(now)end
 S.Apply(state)
 for model,info in pairs(S.Objects)do
  if not model.Parent or now>=info.Expires then if model.Parent then model:Destroy()else S.Objects[model]=nil end
  elseif info.Anchor and info.Anchor.Parent then model:PivotTo(info.Anchor.CFrame*info.Local)end
 end
 if S.Current.State=='ACTIVE'then
  local def=D.ById[S.Current.EventId]
  if now>=(S.NextSpawn or 0)then S.NextSpawn=now+C.Interactions.SpawnSeconds;if def.SpecialObjects then S.SpawnObject(def.SpecialObjects)end end
  if def.Id==Rush.EventId then S.PupTick(now)end
  if not S.SignatureDone and now>=(S.SignatureAt or math.huge)then
   S.SignatureDone=true;package.Signal:FireAllClients({Kind='Signature',EventId=def.Id,Duration=def.SignatureDuration})
   if def.Id=='BONE_RAIN'then S.SpawnObject('GiantBone',true)
   elseif def.Id=='CRYSTAL_STORM'then S.SpawnObject('ChargedCrystal',true)
   elseif def.Id=='UFO_INVASION'then S.SpawnObject('AlienDigZone',true)
   elseif def.Id=='TREASURE_FEVER'then for i=1,3 do S.SpawnObject('TreasureSpot',true)end end
  end
 end
end
function S.Start()
 if S.Started then return end;S.Started=true
 package.GetState.OnServerInvoke=function(player)if Runtime.Allow(player,1)then return S.Current end end
 Players.PlayerAdded:Connect(function(p)task.spawn(function()for i=1,60 do if not p.Parent then return end;if Runtime.Ready(p)then if S.Current.State=='ACTIVE'then journal(p,S.Current);if S.Current.EventId==Rush.EventId then syncPups(p,S.Current)end end;return end;task.wait(1)end end)end)
 Players.PlayerRemoving:Connect(function(p)S.PupCooldown[p]=nil;S.PupTouch[p]=nil;S.PupCapped[p]=nil end)
 if Run:IsStudio() then
  local control=Instance.new('BindableFunction');control.Name='WorldEventDebug';control.Parent=script;control.OnInvoke=S.Force
 end
 Gameplay.Start()
 S.Tick();task.spawn(function()while true do task.wait(1);local ok,err=pcall(S.Tick);if not ok then warn('WORLD EVENT scheduler retry:',err)end end end)
 game:BindToClose(function()Modifiers.Set(nil);fx:ClearAllChildren()end)
 print('DOGROTS_WORLD_EVENTS_READY')
end
return S
