-- Main DOGROTS tutorial, version 4 (docs/halloween2/TUTORIAL.md; the track is ReplicatedStorage.TutorialConfig).
-- 0 Welcome -> 1 buy a dog -> 2 assign it -> 3 first dig -> 4 collect the find (INVENTORY) -> 5 sell -> 6 UPGRADE TREE
-- -> 7 LAYERS -> 8 the ore quarry -> 9 STRENGTH -> 10 a Lucky Pad (+ a free Common block) -> 11 the Mutation Lab
-- -> 12 the DOGDEX -> 13 TRADE -> 14 done. Pure rules over p.Onboarding:
--   {Version=4, Status='Active'|'Complete'|'Skipped', Step=0..14, StepAt=unix, Seen={[flag]=true},
--    Skipped={['n']=true}, FreeBlock?, FreeBlockFull?, Migrated?, From?, CompletedAt?, SkippedAt?}
-- Gameplay steps complete from profile state (Observe, which Rules.Validate runs after every transaction); view
-- steps from a client "Seen" for the current step; place steps from an "Arrive" the service has checked against
-- the character's server position. SkipStep moves on after SkipAfter seconds, so no step is ever a dead end.
-- Players who finished, skipped or were migrated as veterans are never pulled back into the tutorial.
local TC=require(game:GetService('ReplicatedStorage'):WaitForChild('TutorialConfig'))
local LuckyConfig=require(game:GetService('ReplicatedStorage'):WaitForChild('LuckyLifecycleConfig'))
local O={Version=TC.Version,LastStep=TC.LastStep,Config=TC}
local ACTIONS={Start=true,Skip=true,Finish=true,Seen=true,Arrive=true,SkipStep=true,Claim=true}
O.Actions=ACTIONS
local function positive(v)return type(v)=='number'and v==v and v>0 end
local function nonempty(v)return type(v)=='table'and next(v)~=nil end
local function count(t)local n=0;for _ in pairs(type(t)=='table'and t or{})do n+=1 end;return n end
local function experienced(p)
 local mining=type(p.Mining)=='table'and p.Mining or{}
 return nonempty(p.Dogs)or nonempty(p.DogDex)or positive((p.Stats or{}).TotalSellValue)
  or positive(p.TotalExcavations)or positive(mining.Hits)or (p.Level or 1)>1
end
O.Experienced=experienced
function O.New()
 return {Version=O.Version,Status='Active',Step=0,Seen={},Skipped={}}
end
-- Old step (any version below 4) -> version-4 step for a player who was still in the tutorial.
function O.MapOldStep(oldVersion,oldStep)
 local step=math.floor(tonumber(oldStep)or 0)
 -- versions 1-2 had their own numbering; version 3 already moved those players to min(step, 7) of its track
 if oldVersion<3 then step=math.min(math.clamp(step,0,14),7)end
 step=math.clamp(step,0,17)
 return TC.MigrateV3[step]or 0
end
-- Heals the record and migrates older versions. `now` is optional (Observe sets StepAt with it).
function O.Normalize(p,now)
 local t=p.Onboarding
 if type(t)~='table'then
  t=O.New();p.Onboarding=t
  if experienced(p)then t.Status='Complete';t.Step=O.LastStep;t.Migrated=true end
 end
 local oldVersion=tonumber(t.Version)or 0
 if oldVersion>O.Version then
  -- a newer build wrote this record (rollback): keep it as it is; View clamps what it reports
  if type(t.Seen)~='table'then t.Seen={}end
  if type(t.Skipped)~='table'then t.Skipped={}end
  return t
 end
 if oldVersion<O.Version then
  if t.Migrated or t.Status=='Complete'then
   -- veterans and finished players stay finished, whatever the old record held
   t.Status='Complete';t.Step=O.LastStep
  elseif t.Status=='Skipped'then
   t.Step=O.LastStep
  else
   t.Status='Active';t.Step=O.MapOldStep(oldVersion,t.Step);t.StepAt=nil
  end
  t.From=oldVersion;t.Version=O.Version
 end
 if t.Status~='Active'and t.Status~='Complete'and t.Status~='Skipped'then t.Status='Active'end
 t.Step=math.clamp(math.floor(tonumber(t.Step)or 0),0,O.LastStep)
 if t.Status~='Active'then t.Step=O.LastStep end
 if type(t.Seen)~='table'then t.Seen={}end
 if type(t.Skipped)~='table'then t.Skipped={}end
 if t.StepAt~=nil and not positive(t.StepAt)then t.StepAt=nil end
 if type(now)=='number'and t.StepAt==nil then t.StepAt=now end
 return t
end
-- Flags proven by the profile itself (never reset: a sold dog does not undo "bought a dog").
function O.Evidence(p,seen)
 if nonempty(p.Dogs)then seen.DogOwned=true end
 for _,dog in pairs(p.Dogs or{})do
  if type(dog)=='table'and type(dog.AssignedSlot)=='string'and dog.AssignedSlot~=''then seen.Assigned=true;break end
 end
 if positive(p.TotalExcavations)or nonempty(p.Loot)or nonempty(p.Items)then seen.Found=true end
 local stats=type(p.Stats)=='table'and p.Stats or{}
 if positive(stats.TotalSellValue)then seen.Sold=true;seen.Inventory=true end
 local upgrades=type(p.Upgrades)=='table'and p.Upgrades or{}
 for _,level in pairs(upgrades)do if positive(level)then seen.Upgraded=true;break end end
 local layers=type(p.UnlockedLayers)=='table'and p.UnlockedLayers or{}
 if layers['2']then seen.Layers=true end
 local mining=type(p.Mining)=='table'and p.Mining or{}
 if positive(mining.Hits)then seen.MiningHit=true end
 -- STRENGTH: any level of the UPGRADE TREE's STRENGTH branch (or Strength trained before it existed)
 for _,id in ipairs(TC.StrengthNodes)do if positive(upgrades[id])then seen.StrengthTrain=true;break end end
 if positive(mining.Strength)then seen.StrengthTrain=true end
 -- LUCKY BLOCKS: a block on a pad, or any block ever opened
 for _,block in pairs(type(p.OwnedBlocks)=='table'and p.OwnedBlocks or{})do
  if type(block)=='table'and(block.State=='Placed'or block.State=='Ready')then seen.LuckyPad=true;break end
 end
 for _,n in pairs(type(p.LuckyOpened)=='table'and p.LuckyOpened or{})do if positive(n)then seen.LuckyPad=true;break end end
 -- LAB: the first (free) mutation or any experiment
 local lab=type(p.Lab)=='table'and p.Lab or{}
 if lab.TutorialComplete==true or positive(lab.Experiments)then seen.Lab=true end
 if nonempty(p.DexClaims)then seen.DogDex=true end
 if positive(stats.CompletedTrades)then seen.Trade=true end
 return seen
end
-- Is step `index` done for this record?
function O.StepDone(t,index)
 local step=TC.Steps[index]
 return step~=nil and step.Flag~=nil and t.Seen[step.Flag]==true
end
local function advance(t,now)
 t.Step=math.min(O.LastStep,t.Step+1);t.StepAt=now
end
function O.Observe(p,now)
 local t=O.Normalize(p,now)
 if tonumber(t.Version)~=O.Version then return t end
 -- Observe runs on every tick and transaction: finished players (most of them) skip the profile scan
 if t.Status=='Active'then O.Evidence(p,t.Seen)end
 if t.Status=='Active'and t.Step>0 then
  local guard=0
  while t.Step<O.LastStep and O.StepDone(t,t.Step)and guard<=O.LastStep do advance(t,now);guard+=1 end
 end
 if type(now)=='number'and t.Status=='Complete'and not t.CompletedAt and not t.Migrated then t.CompletedAt=now end
 return t
end
-- What the client sees (player attributes, request replies). now: unix seconds (Skippable).
function O.View(p,now)
 local t=O.Normalize(p)
 local step=math.clamp(math.floor(tonumber(t.Step)or 0),0,O.LastStep)
 local active=t.Status=='Active'and tonumber(t.Version)==O.Version
 local at=tonumber(t.StepAt)or 0
 local def=TC.Steps[step]or{}
 return {Version=O.Version,Status=t.Status,Step=step,Active=active,ReadyAt=0,StepAt=at,Kind=def.Kind,Id=def.Id,
  Skippable=active and TC.CanSkipStep(step,at,tonumber(now)or at)or false,FreeBlock=t.FreeBlock==true}
end
-- The free Common block (once, cap aware). add(p, tier, count, origin, paid) -> {uid} is LuckyLifecycle.AddStored.
function O.GrantFreeBlock(p,t,now,add)
 if t.FreeBlock or t.FreeBlockFull then return nil end
 if count(p.OwnedBlocks)>=(LuckyConfig.InventoryCapacity or 60)then
  t.FreeBlockFull=true;return {Granted=false,Reason='Full'}
 end
 local ids=add(p,TC.FreeBlock.Tier,1,TC.FreeBlock.Origin,false)
 t.FreeBlock=true;t.FreeBlockAt=now
 return {Granted=true,Tier=TC.FreeBlock.Tier,Uid=type(ids)=='table'and ids[1]or nil}
end
-- action: Start | Skip | Finish | Seen {Key} | Arrive {Key} | SkipStep | Claim.
-- opts (server facts the service checked outside the profile): Near (Arrive: the character is in range),
-- NoPad (Claim: the player has no Lucky Pad to walk to), AddBlock (LuckyLifecycle.AddStored).
function O.Apply(p,action,now,args,opts)
 assert(ACTIONS[action],'Unknown tutorial action')
 args=type(args)=='table'and args or{};opts=type(opts)=='table'and opts or{}
 local t=O.Observe(p,now)
 -- a record from a newer build (rollback) is never driven by this one
 assert(tonumber(t.Version)==O.Version,'The tutorial is not running')
 local extra={}
 if action=='Start'then
  if t.Status=='Active'and t.Step==0 then advance(t,now);O.Observe(p,now)end
 elseif action=='Skip'then
  if t.Status=='Active'then t.Status='Skipped';t.SkippedAt=now;t.Step=O.LastStep end
 elseif action=='Finish'then
  assert(t.Status=='Complete'or(t.Status=='Active'and t.Step==O.LastStep),'Finish the tutorial tasks first')
  t.Status='Complete';t.CompletedAt=t.CompletedAt or now
 elseif action=='Seen'or action=='Arrive'then
  assert(t.Status=='Active','The tutorial is not running')
  local step=TC.Steps[t.Step]
  local kind=action=='Seen'and'View'or'Arrive'
  if step and step.Kind==kind and args.Key==step.Key then
   if action=='Arrive'then
    assert(opts.Near==true,args.Key=='Lab'and'Walk up to the Mutation Lab'or'Walk up to a Lucky Pad in your yard')
    if args.Key=='LuckyPad'and opts.AddBlock then extra.FreeBlock=O.GrantFreeBlock(p,t,now,opts.AddBlock)end
   end
   t.Seen[step.Flag]=true;O.Observe(p,now)
  else
   -- a late report for a step that is already behind us is harmless; anything else is not this step
   local index=TC.StepOfKey(args.Key)
   assert(index~=nil and index<t.Step,'This is not the current tutorial step')
  end
 elseif action=='SkipStep'then
  assert(t.Status=='Active','The tutorial is not running')
  assert(t.Step>=1 and t.Step<O.LastStep,'This step cannot be skipped')
  assert(TC.CanSkipStep(t.Step,t.StepAt,now),'Keep trying a little longer before skipping')
  t.Skipped[tostring(t.Step)]=true;advance(t,now);O.Observe(p,now)
 elseif action=='Claim'then
  assert(t.Status=='Active','The tutorial is not running')
  local index=TC.StepOfKey('LuckyPad')
  assert(t.Step==index,'This is not the current tutorial step')
  assert(opts.NoPad==true or TC.CanSkipStep(t.Step,t.StepAt,now),'Walk to a Lucky Pad in your yard to claim it')
  if opts.AddBlock then extra.FreeBlock=O.GrantFreeBlock(p,t,now,opts.AddBlock)end
  t.Seen.LuckyPad=true;O.Observe(p,now)
 end
 local view=O.View(p,now)
 for k,v in pairs(extra)do view[k]=v end
 return view
end
-- Pure range check used by the service: is `position` within `radius` of any of `points`?
function O.WithinAny(position,points,radius)
 if typeof(position)~='Vector3'or type(points)~='table'then return false end
 for _,point in ipairs(points)do
  if typeof(point)=='Vector3'and(position-point).Magnitude<=radius then return true end
 end
 return false
end
return O
