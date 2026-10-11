-- Active Mining: pure, server-authoritative rules (no Roblox services; unit-tested with Lune).
-- Persistent state lives in profile.Mining and is saved with the DOGROTS profile.
-- Timing circles ("targets") live in a RAM-only session table owned by the server.
--
-- ctx (built by Economy/Rules.MiningAction):
--   Now      os.time() of the request          Clock   server clock in seconds (GetServerTimeNow)
--   Random   function() -> [0,1)               Cash    current cash
--   Pay(n)   charge cash (errors if short)     Credit(n) add earned cash
--   AddXP(n) grant player XP                   Layer   deepest unlocked dig layer (1..5)
--   Session  RAM table for timing targets      Ping    player's network round trip (seconds)
-- Messages and errors are codes "M:KEY|arg|arg" localized by ReplicatedStorage.Mining.MiningText.
local Rules={}

local function int(v,default)
 v=tonumber(v);if v==nil or v~=v then return default end
 return math.floor(v)
end
local function code(key,...)
 local parts={'M:'..key}
 for _,a in ipairs({...})do table.insert(parts,tostring(a))end
 return table.concat(parts,'|')
end
Rules.Code=code
local function check(ok,key,...)if not ok then error(code(key,...),0)end end

-- v1 (MINING_POLISH_1) stored only the ore index; these were its ids in order.
local LEGACY_ORE_IDS={'Limestone','Copper','Iron','Quartz','Amethyst','Ruby','Emerald','Meteorite','VoidCrystal'}

function Rules.OreById(M,id)
 for i,ore in ipairs(M.Ores)do if ore.Id==id then return ore,i end end
 return nil,nil
end

local function oreMid(ore)return math.floor((ore.ValueMin+ore.ValueMax)/2)end

function Rules.New(M)
 local ore=M.Ores[1]
 return {Version=2,Strength=0,PickaxeOwned=0,PickaxeLevel=0,WeightOwned=0,WeightLevel=0,Hits=0,OresBroken=0,CoinsEarned=0,
  TrainingReps=0,OreIndex=1,OreId=ore.Id,OreMaxHP=ore.HP,OreHP=ore.HP,OreValue=oreMid(ore),OreEarned=0,OreSerial=1,
  Combo=0,BestOre=0,Collection={},LastHitAt=0,LastTrainAt=0,ActiveUntil=0,TrainingUntil=0,LastPayout=0,LastDamage=0,LastQuality=1,
  LastBreak=false,LastCrit=false,LastBrokenId='',LastBrokenValue=0}
end

-- Repairs / migrates a saved state in place and returns it.
function Rules.Normalize(m,M)
 if type(m)~='table'then m=Rules.New(M)end
 local pickCount,weightCount=#M.Pickaxes,#M.Weights
 m.Strength=math.clamp(int(m.Strength,0),0,M.MaxStrength)
 m.PickaxeOwned=math.clamp(int(m.PickaxeOwned,0),0,pickCount)
 m.PickaxeLevel=math.clamp(int(m.PickaxeLevel,0),0,m.PickaxeOwned)
 if m.PickaxeOwned>0 and m.PickaxeLevel==0 then m.PickaxeLevel=m.PickaxeOwned end
 m.WeightOwned=math.clamp(int(m.WeightOwned,0),0,weightCount)
 m.WeightLevel=math.clamp(int(m.WeightLevel,0),0,m.WeightOwned)
 if m.WeightOwned>0 and m.WeightLevel==0 then m.WeightLevel=m.WeightOwned end
 for _,key in ipairs({'Hits','OresBroken','CoinsEarned','TrainingReps','Combo','BestOre','LastPayout','LastDamage','LastBrokenValue'})do
  m[key]=math.max(0,int(m[key],0))
 end
 m.Combo=math.min(m.Combo,M.ComboCap)
 m.Collection=type(m.Collection)=='table'and m.Collection or{}
 for id,count in pairs(m.Collection)do
  if type(id)~='string'or not Rules.OreById(M,id)then m.Collection[id]=nil else m.Collection[id]=math.max(0,int(count,0))end
 end
 -- Ore identity: v2 saves OreId; v1 saved only an index into the old 9-ore list.
 local ore,index
 if type(m.OreId)=='string'then ore,index=Rules.OreById(M,m.OreId)end
 if not ore and (tonumber(m.Version)or 1)<2 then
  local legacy=LEGACY_ORE_IDS[int(m.OreIndex,1)]
  if legacy then ore,index=Rules.OreById(M,legacy)end
  -- v1 HP/values were tuned for a different table: start the migrated ore fresh.
  if ore then m.OreMaxHP=ore.HP;m.OreHP=ore.HP;m.OreValue=oreMid(ore);m.OreEarned=0 end
 end
 if not ore then ore,index=M.Ores[1],1;m.OreMaxHP=ore.HP;m.OreHP=ore.HP;m.OreValue=oreMid(ore);m.OreEarned=0 end
 m.OreId=ore.Id;m.OreIndex=index
 m.OreMaxHP=math.max(1,int(m.OreMaxHP,ore.HP))
 m.OreHP=math.clamp(int(m.OreHP,m.OreMaxHP),1,m.OreMaxHP)
 m.OreValue=math.max(1,int(m.OreValue,oreMid(ore)))
 m.OreEarned=math.max(0,int(m.OreEarned,0))
 m.OreSerial=math.max(1,int(m.OreSerial,1))
 m.LastHitAt=tonumber(m.LastHitAt)or 0;m.LastTrainAt=tonumber(m.LastTrainAt)or 0;m.ActiveUntil=tonumber(m.ActiveUntil)or 0
 m.TrainingUntil=tonumber(m.TrainingUntil)or 0
 m.LastQuality=math.clamp(int(m.LastQuality,1),1,2);m.LastBreak=m.LastBreak==true;m.LastCrit=m.LastCrit==true
 m.LastBrokenId=type(m.LastBrokenId)=='string'and m.LastBrokenId or''
 m.Version=2
 return m
end

-- Ore roll weights. Pickaxe "Luck" shifts weight towards the rarer end of the table.
function Rules.OreWeights(M,luck)
 luck=math.max(0,tonumber(luck)or 0)
 local n=#M.Ores;local out,total={},0
 for i,ore in ipairs(M.Ores)do
  local w=ore.Weight*(1+luck*M.LuckSpread*(i-1)/math.max(1,n-1))
  out[i]=w;total+=w
 end
 return out,total
end

function Rules.LayerMult(M,layer)
 return M.LayerValue[math.clamp(int(layer,1),1,#M.LayerValue)]
end

function Rules.RollOre(m,M,random,luck,layer)
 local weights,total=Rules.OreWeights(M,luck)
 local roll=random()*total;local index=#M.Ores
 for i,w in ipairs(weights)do roll-=w;if roll<=0 then index=i;break end end
 local ore=M.Ores[index]
 m.OreIndex=index;m.OreId=ore.Id;m.OreMaxHP=ore.HP;m.OreHP=ore.HP
 m.OreValue=math.max(1,math.floor((ore.ValueMin+(ore.ValueMax-ore.ValueMin)*random())*Rules.LayerMult(M,layer)+.5));m.OreEarned=0
 m.OreSerial+=1
 return ore,index
end

-- Damage multiplier from Strength above the equipped pickaxe's requirement.
function Rules.StrengthBonus(M,m,pick)
 local surplus=math.max(0,(m.Strength or 0)-(pick.Strength or 0))
 return 1+math.min(M.StrengthBonusMax,surplus*M.StrengthBonusPerPoint)
end

function Rules.HitDamage(M,m,pick,quality,combo,crit)
 local mult=Rules.StrengthBonus(M,m,pick)
 if quality==2 then mult*=pick.PerfectMult or M.PerfectMult end
 mult*=1+math.min(pick.ComboMax or 0,(combo or 0)*(pick.ComboStep or 0))
 if crit then mult*=pick.CritMult or 2 end
 return math.max(1,math.floor(pick.Damage*mult+.5))
end

-- Hits an average player needs for an ore with the given pickaxe (UI preview).
function Rules.HitsToBreak(M,m,pick,ore)
 return math.max(1,math.ceil(ore.HP/Rules.HitDamage(M,m,pick,1,0,false)))
end

-- TIMING TARGETS ------------------------------------------------------------------------------
-- One target per pickaxe "circle" slot. A target opens at SpawnAt and closes over Window seconds.
local function newTarget(s,slot,spawnAt,window)
 s.NextId=(s.NextId or 0)+1
 local t={Id=s.NextId,Slot=slot,SpawnAt=spawnAt,Window=window}
 s.Targets[slot]=t
 return t
end
-- Re-issues every slot. Ids of the replaced targets are remembered as stale, so a click that was
-- already in flight (e.g. right after a break) is answered harmlessly. Never opens a circle
-- before s.PauseUntil (the break pause).
function Rules.IssueTargets(s,M,pick,clock,delay)
 local stale={}
 for _,t in pairs(s.Targets or{})do stale[t.Id]=true end
 s.Stale=stale
 s.Targets={}
 local circles=math.max(1,int(pick.Circles,1))
 local stride=(pick.Window+M.Client.RespawnDelay)/circles
 local base=math.max(clock+(delay or .35),tonumber(s.PauseUntil)or 0)
 for slot=1,circles do newTarget(s,slot,base+(slot-1)*stride,pick.Window)end
 return s.Targets
end
function Rules.ViewTargets(s)
 local out={}
 for _,t in pairs(s and s.Targets or{})do table.insert(out,{Id=t.Id,Slot=t.Slot,SpawnAt=t.SpawnAt,Window=t.Window})end
 table.sort(out,function(a,b)return a.Slot<b.Slot end)
 return out
end
local function findTarget(s,id)
 id=int(id,-1)
 for slot,t in pairs(s.Targets or{})do if t.Id==id then return t,slot end end
 return nil,nil
end

-- ACTIONS --------------------------------------------------------------------------------------
-- Idempotent while a session is live: re-sending Begin only returns the current circles (the
-- client uses it to resync), so it can neither reset targets nor skip the break pause.
function Rules.Begin(m,M,ctx)
 local pick=M.Pickaxes[m.PickaxeLevel]
 check(pick~=nil,'NEED_PICKAXE')
 local s=ctx.Session
 local live=(m.ActiveUntil or 0)>=ctx.Now and next(s.Targets or{})~=nil
 m.ActiveUntil=ctx.Now+M.SessionSeconds;m.TrainingUntil=0;m.LastBreak=false
 if not live then m.Combo=0;Rules.IssueTargets(s,M,pick,ctx.Clock)end
 return code('STARTED')
end

function Rules.End(m,M,ctx)
 m.ActiveUntil=0;m.Combo=0
 if ctx and ctx.Session then ctx.Session.Targets={};ctx.Session.Stale={}end
 return code('ENDED')
end

-- args: Target (id), Quality (client-judged 1/2), Miss (true when the circle closed unclicked)
function Rules.Hit(m,M,ctx,args)
 local pick=M.Pickaxes[m.PickaxeLevel];check(pick~=nil,'NEED_PICKAXE')
 check((m.ActiveUntil or 0)>=ctx.Now,'SESSION_OVER')
 local s=ctx.Session;check(type(s)=='table','SESSION_OVER')
 local target,slot=findTarget(s,args.Target)
 if not target then
  -- A click for a circle of the previous ore (sent before the break reached the client).
  check(s.Stale and s.Stale[int(args.Target,-1)],'TARGET_GONE')
  return code('STALE')
 end
 local tm=M.Timing
 local elapsed=ctx.Clock-target.SpawnAt
 local ping=math.clamp(tonumber(ctx.Ping)or 0,0,1)
 local w=target.Window
 -- A circle that has not opened yet can be neither missed nor hit (keeps the break pause).
 check(elapsed>=-tm.ServerSlack,'TOO_EARLY')
 if args.Miss==true or elapsed>w+ping+tm.LateGrace then
  newTarget(s,slot,math.max(ctx.Clock,target.SpawnAt)+M.Client.RespawnDelay,pick.Window)
  m.Combo=0;m.ActiveUntil=ctx.Now+M.SessionSeconds
  return code(args.Miss==true and'MISS'or'TOO_LATE')
 end
 check(elapsed>=tm.GoodFrom*w-tm.ServerSlack,'TOO_EARLY')
 check(ctx.Clock-(m.LastHitAt or 0)>=M.MinHitGap,'NOT_READY')
 local claimed=int(args.Quality,1)==2 and 2 or 1
 local serverPerfect=elapsed>=tm.PerfectFrom*w-tm.ServerSlack and elapsed<=tm.PerfectTo*w+ping+tm.ServerSlack
 local quality=(claimed==2 and serverPerfect)and 2 or 1
 if ctx.Clock-(m.LastHitAt or 0)>M.ComboTimeout then m.Combo=0 end
 m.LastHitAt=ctx.Clock;m.ActiveUntil=ctx.Now+M.SessionSeconds
 local ore=M.Ores[m.OreIndex]
 local crit=ctx.Random()<(pick.CritChance or 0)
 local damage=Rules.HitDamage(M,m,pick,quality,m.Combo,crit)
 if quality==2 then m.Combo=math.min(M.ComboCap,m.Combo+1)else m.Combo=0 end
 local applied=math.min(m.OreHP,damage);m.OreHP-=applied;m.Hits+=1
 local total=math.floor(m.OreValue*(1+(pick.CoinBonus or 0))+.5)
 local remaining=math.max(0,total-m.OreEarned)
 local payout=math.min(remaining,math.max(1,math.floor(total*M.HitShare*applied/m.OreMaxHP)))
 local broke=m.OreHP<=0
 if broke then payout=remaining end
 payout=math.min(payout,math.max(0,(M.MaxCash or math.huge)-(ctx.Cash or 0)))
 if payout>0 then ctx.Credit(payout);m.OreEarned+=payout;m.CoinsEarned+=payout end
 m.LastPayout=payout;m.LastDamage=applied;m.LastQuality=quality;m.LastBreak=broke;m.LastCrit=crit
 if broke then
  m.OresBroken+=1;m.LastBrokenId=ore.Id;m.LastBrokenValue=m.OreEarned
  m.Collection[ore.Id]=(m.Collection[ore.Id]or 0)+1
  m.BestOre=math.max(m.BestOre,m.OreIndex)
  ctx.AddXP(M.BreakXP+M.BreakXPPerTier*(m.OreIndex-1))
  Rules.RollOre(m,M,ctx.Random,pick.Luck,ctx.Layer)
  -- Every circle pauses while the old pile crumbles and the new one rises.
  s.PauseUntil=ctx.Clock+M.Client.BreakPause
  Rules.IssueTargets(s,M,pick,ctx.Clock,M.Client.BreakPause)
  return code('BROKE',ore.Id,m.LastBrokenValue)
 end
 newTarget(s,slot,ctx.Clock+M.Client.RespawnDelay,pick.Window)
 return code(crit and'CRIT'or quality==2 and'PERFECT'or'HIT',payout)
end

function Rules.BuyPickaxe(m,M,ctx,level)
 level=int(level,0);check(level>=1 and level<=#M.Pickaxes,'BAD_ITEM')
 if level<=m.PickaxeOwned then
  local changed=level~=m.PickaxeLevel
  m.PickaxeLevel=level
  if changed and ctx.Session and (m.ActiveUntil or 0)>=ctx.Now then Rules.IssueTargets(ctx.Session,M,M.Pickaxes[level],ctx.Clock)end
  return code('EQUIPPED',M.Pickaxes[level].Id)
 end
 check(level==m.PickaxeOwned+1,'IN_ORDER')
 local def=M.Pickaxes[level]
 check(m.Strength>=def.Strength,'NEED_STRENGTH',def.Strength)
 check((ctx.Cash or 0)>=def.Price,'NEED_COINS',def.Price)
 ctx.Pay(def.Price)
 m.PickaxeOwned=level;m.PickaxeLevel=level
 ctx.AddXP(M.PickaxeXP*level)
 if ctx.Session and (m.ActiveUntil or 0)>=ctx.Now then Rules.IssueTargets(ctx.Session,M,def,ctx.Clock)end
 return code('BOUGHT',def.Id)
end

function Rules.BuyWeight(m,M,ctx,level)
 level=int(level,0);check(level>=1 and level<=#M.Weights,'BAD_ITEM')
 -- Choosing a weight at the rack counts as training activity: keep the weight in hand.
 if (m.TrainingUntil or 0)>=ctx.Now then m.TrainingUntil=ctx.Now+M.SessionSeconds end
 if level<=m.WeightOwned then m.WeightLevel=level;return code('WEIGHT_EQUIPPED',M.Weights[level].Id)end
 check(level==m.WeightOwned+1,'IN_ORDER')
 local def=M.Weights[level]
 check(m.Strength>=def.Strength,'NEED_STRENGTH',def.Strength)
 check((ctx.Cash or 0)>=def.Price,'NEED_COINS',def.Price)
 if def.Price>0 then ctx.Pay(def.Price)end
 m.WeightOwned=level;m.WeightLevel=level
 return code('WEIGHT_BOUGHT',def.Id)
end

-- A training session only shows the weight in the character's hands (MiningWorld); reps are
-- validated on their own.
function Rules.TrainBegin(m,M,ctx)
 m.TrainingUntil=ctx.Now+M.SessionSeconds;m.ActiveUntil=0;m.Combo=0
 if ctx.Session then ctx.Session.Targets={}end
 return code('TRAIN_STARTED')
end
function Rules.TrainEnd(m)
 m.TrainingUntil=0
 return code('ENDED')
end

function Rules.Train(m,M,ctx)
 local def=M.Weights[m.WeightLevel];check(def~=nil,'NEED_WEIGHT')
 check(m.Strength<math.min(def.Cap,M.MaxStrength),'WEIGHT_CAPPED')
 -- Rest + the shortest possible lift; a rep can never be scripted faster than a fast human.
 check(ctx.Clock-(m.LastTrainAt or 0)>=def.Cooldown*M.CooldownTolerance+M.MinLiftTime,'REST')
 -- Lifting ends any mining session (no interleaving reps with hits).
 m.ActiveUntil=0;m.Combo=0
 if ctx.Session then ctx.Session.Targets={};ctx.Session.Stale={}end
 m.LastTrainAt=ctx.Clock;m.TrainingReps+=1;m.TrainingUntil=ctx.Now+M.SessionSeconds
 local before=m.Strength
 m.Strength=math.min(def.Cap,M.MaxStrength,m.Strength+def.Gain)
 return code('TRAINED',m.Strength-before)
end

-- Single entry point used by Economy/Rules.
function Rules.Action(m,M,action,args,ctx)
 args=type(args)=='table'and args or{}
 if action=='MiningBegin'then return Rules.Begin(m,M,ctx)
 elseif action=='MiningEnd'then return Rules.End(m,M,ctx)
 elseif action=='MiningHit'then return Rules.Hit(m,M,ctx,args)
 elseif action=='MiningPickaxe'then return Rules.BuyPickaxe(m,M,ctx,args.Level)
 elseif action=='MiningWeight'then return Rules.BuyWeight(m,M,ctx,args.Level)
 elseif action=='MiningTrain'then return Rules.Train(m,M,ctx)
 elseif action=='MiningTrainBegin'then return Rules.TrainBegin(m,M,ctx)
 elseif action=='MiningTrainEnd'then return Rules.TrainEnd(m)
 end
 error(code('BAD_ACTION'),0)
end

return Rules
