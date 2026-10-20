-- Global Fix 1.2 onboarding: the core DOGROTS loop plus the active Mining Corner.
-- Real gameplay advances the important steps; advanced systems remain short information checkpoints.
local O={Version=3,LastStep=17}
local milestones={[1]='DogOwned',[2]='Assigned',[3]='Found',[4]='Sold',[5]='Levelled',[6]='Upgraded',[7]='MiningHit',[8]='StrengthTrain'}
local infoSteps={[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true}
local function positive(v)return type(v)=='number'and v==v and v>0 end
local function nonempty(v)return type(v)=='table'and next(v)~=nil end
local function experienced(p)
 local mining=type(p.Mining)=='table'and p.Mining or{}
 return nonempty(p.Dogs)or nonempty(p.DogDex)or positive((p.Stats or{}).TotalSellValue)
  or positive(p.TotalExcavations)or positive(mining.Hits)or (p.Level or 1)>1
end
function O.New()
 return {Version=O.Version,Status='Active',Step=0,Seen={}}
end
function O.Normalize(p)
 local t=p.Onboarding
 if type(t)~='table'then
  t=O.New();p.Onboarding=t
  if experienced(p)then t.Status='Complete';t.Step=O.LastStep;t.Migrated=true end
 end
 local oldVersion=tonumber(t.Version)or 0
 if oldVersion<O.Version and not t.Migrated then
  if t.Status=='Complete'or t.Status=='Skipped'then
   t.Version=O.Version;t.Step=O.LastStep
  else
   local oldStep=math.clamp(math.floor(tonumber(t.Step)or 0),0,14)
   t=O.New();t.Step=math.min(oldStep,7);p.Onboarding=t
  end
 end
 t.Version=O.Version
 if t.Status~='Active'and t.Status~='Complete'and t.Status~='Skipped'then t.Status='Active'end
 t.Step=math.clamp(math.floor(tonumber(t.Step)or 0),0,O.LastStep)
 if type(t.Seen)~='table'then t.Seen={}end
 return t
end
function O.Observe(p,now)
 local t=O.Normalize(p);local seen=t.Seen
 if nonempty(p.Dogs)then seen.DogOwned=true end
 for _,dog in pairs(p.Dogs or{})do
  if type(dog.AssignedSlot)=='string'and dog.AssignedSlot~=''then seen.Assigned=true;break end
 end
 if positive(p.TotalExcavations)or nonempty(p.Loot)or nonempty(p.Items)then seen.Found=true end
 if positive((p.Stats or{}).TotalSellValue)then seen.Sold=true end
 for _,level in pairs(p.Upgrades or{})do if positive(level)then seen.Upgraded=true;break end end
 if (p.Level or 1)>=2 then seen.Levelled=true end
 local mining=type(p.Mining)=='table'and p.Mining or{}
 if positive(mining.Hits)then seen.MiningHit=true end
 -- Step 8 (STRENGTH): any level of the UPGRADE TREE's STRENGTH branch (or Strength trained before it existed).
 local upgrades=type(p.Upgrades)=='table'and p.Upgrades or{}
 for _,id in ipairs({'IronGrip','HeavyLifter','TitanBack','Colossus','MountainBreaker'})do
  if positive(upgrades[id])then seen.StrengthTrain=true;break end
 end
 if positive(mining.Strength)then seen.StrengthTrain=true end
 if t.Status=='Active'and t.Step>0 then
  while milestones[t.Step]and seen[milestones[t.Step]]do t.Step+=1 end
 end
 if type(now)=='number'and t.Status=='Complete'and not t.CompletedAt and not t.Migrated then t.CompletedAt=now end
 return t
end
function O.View(p)
 local t=O.Normalize(p)
 return {Version=O.Version,Status=t.Status,Step=t.Step,Active=t.Status=='Active',ReadyAt=0}
end
function O.Apply(p,action,now)
 assert(action=='Start'or action=='Skip'or action=='Finish'or action=='Next','Unknown tutorial action')
 local t=O.Observe(p,now)
 if action=='Start'then
  if t.Status=='Active'and t.Step==0 then t.Step=1;O.Observe(p,now)end
 elseif action=='Next'then
  assert(t.Status=='Active'and infoSteps[t.Step],'Complete the current gameplay task first')
  t.Step+=1
 elseif action=='Skip'then
  if t.Status=='Active'then t.Status='Skipped';t.SkippedAt=now end
 else
  assert(t.Status=='Complete'or(t.Status=='Active'and t.Step==O.LastStep),'Finish the tutorial tasks first')
  t.Status='Complete';t.CompletedAt=t.CompletedAt or now
 end
 return O.View(p)
end
return O
