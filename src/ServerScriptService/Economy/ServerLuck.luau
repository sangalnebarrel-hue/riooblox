-- Server luck (Lucky Server / Super / Ultra / MAX LUCK): multiplies the tongue's Legendary,
-- Mythic and Secret odds (dogs and Lucky Blocks) for everyone on this server. The running
-- timer lives in this server's memory, like the tongue itself, and is mirrored on
-- ReplicatedStorage.ServerLuckState for every client's HUD, shop and celebration.
-- An active world event adds its own tongue luck on top (WorldEventDefinitions Perks).
--
-- Paid time is never RAM-only: every Robux purchase is saved in the buyer's profile as a
-- credit, p.ServerLuckCredits[purchaseId] = {Multiplier, Queued, Active, Server, At, Name}:
--   Queued  seconds not started yet (the pool was full, or the server that ran them is gone)
--   Active  seconds started on server `Server` and still running there (synced every 30 s)
-- * The receipt transaction adds the credit (QueueCredit) together with the purchase mark.
-- * SyncFor/ActivateFor starts queued time while the pool has room (nothing is cut off; the
--   rest waits), and re-queues time that was running on a server that shut down or crashed
--   when the buyer joins another server.
-- * Release: a buyer who leaves gives their running time to the server they leave (it keeps
--   lifting the tongue for everyone there); when the server shuts down it goes back to the
--   credit and restarts on the buyer's next server.
-- The pool is accounted in value = (multiplier - 1) x seconds, so converting between
-- multipliers keeps every bought second; credits are consumed first in, first out.
local RS=game:GetService('ReplicatedStorage')
local Players=game:GetService('Players')
local Config=require(RS.DogEconomy.Config)
local Modifiers=require(RS.WorldEvents.WorldEventModifiers)
local S={Multiplier=1,EndsAt=0,By='',Consumed=0,LastAt=0,Entries={}}
local MAX_STACK=10
local state=RS:FindFirstChild('ServerLuckState')
if not state then state=Instance.new('Folder');state.Name='ServerLuckState';state.Parent=RS end
S.State=state
local function publish(by,added,multiplier)
 state:SetAttribute('Multiplier',S.Multiplier);state:SetAttribute('EndsAt',math.floor(S.EndsAt));state:SetAttribute('By',S.By)
 state:SetAttribute('LastBy',by or '');state:SetAttribute('LastMultiplier',multiplier or S.Multiplier);state:SetAttribute('LastSeconds',added or 0)
 -- Seq last: clients celebrate when it changes.
 state:SetAttribute('Seq',(state:GetAttribute('Seq')or 0)+1)
end
local function cap()return (Config.ServerLuck or {}).MaxSeconds or 7200 end
function S.Current(now)
 now=now or os.time()
 return now<S.EndsAt and S.Multiplier or 1
end
-- Moves the consumed-value counter up to `now`.
function S.Advance(now)
 now=now or os.time()
 if S.Multiplier>1 then
  local untilTime=math.min(now,S.EndsAt)
  if untilTime>S.LastAt then S.Consumed+=(S.Multiplier-1)*(untilTime-S.LastAt)end
 end
 if now>S.LastAt then S.LastAt=now end
end
-- Seconds of `multiplier` luck that can start right now without passing MaxSeconds.
function S.Room(multiplier,now)
 multiplier=math.clamp(tonumber(multiplier)or 1,1,10);now=now or os.time()
 if multiplier<=1 then return 0 end
 local current=S.Current(now);local remaining=math.max(0,S.EndsAt-now)
 if multiplier>=current then
  local carried=current>1 and remaining*(current-1)/(multiplier-1)or 0
  return math.max(0,math.floor(cap()-carried))
 end
 return math.max(0,math.floor((cap()-remaining)*(current-1)/(multiplier-1)))
end
--[[ S.Add(multiplier, seconds, byName, source): a stronger (or equal) boost takes over and carries
 the weaker one's remaining time over at its value; a weaker boost extends the stronger one by its
 equivalent value. Stored time never passes Config.ServerLuck.MaxSeconds: only what fits starts
 now and the number of started seconds is returned (callers keep the rest as a credit).
 source = '<userId>:<creditId>' to account a paid credit (see Remaining). ]]
function S.Add(multiplier,seconds,byName,source)
 multiplier=math.clamp(tonumber(multiplier)or 1,1,10);seconds=math.floor(math.max(0,tonumber(seconds)or 0))
 if multiplier<=1 or seconds<=0 then return 0 end
 local now=os.time();S.Advance(now)
 local take=math.min(seconds,S.Room(multiplier,now))
 if take<=0 then return 0 end
 local current=S.Current(now);local remaining=math.max(0,S.EndsAt-now)
 if multiplier>=current then
  local carried=current>1 and remaining*(current-1)/(multiplier-1)or 0
  S.Multiplier=multiplier;S.EndsAt=now+carried+take
 else
  S.EndsAt+=take*(multiplier-1)/(current-1)
 end
 S.By=tostring(byName or '')
 if type(source)=='string'then
  -- First in, first out: this segment is used up once the pool has consumed everything
  -- that was in it, including this segment.
  local entry=S.Entries[source]or{Multiplier=multiplier,Segments={}}
  entry.Multiplier=multiplier
  table.insert(entry.Segments,{Done=S.Consumed+(S.Multiplier-1)*(S.EndsAt-now),Value=(multiplier-1)*take})
  S.Entries[source]=entry
 end
 publish(S.By,take,multiplier)
 local presentation=RS:FindFirstChild('RewardPresentation')
 if presentation then presentation:FireAllClients({Announcement=string.upper(S.By)..' ACTIVATED x'..multiplier..' SERVER LUCK!',Tier='Secret'})end
 return take
end
-- Seconds (at the credit's multiplier) of an accounted source still running in the pool.
function S.Remaining(source,now)
 local entry=S.Entries[source];if not entry then return 0 end
 S.Advance(now or os.time())
 local left,kept=0,{}
 for _,segment in ipairs(entry.Segments)do
  local value=math.clamp(segment.Done-S.Consumed,0,segment.Value)
  if value>0 then left+=value;table.insert(kept,segment)end
 end
 entry.Segments=kept
 if #kept==0 then S.Entries[source]=nil;return 0 end
 return left/math.max(1e-6,entry.Multiplier-1)
end
-- Rank multipliers for the tongue right now: {[rank]=multiplier}. Server luck lifts every rank
-- in Config.ServerLuck.Ranks; a world event's LineLuck does the same and its SecretLine lifts
-- Secrets once more.
function S.Ranks(now)
 now=now or os.time()
 local luck=S.Current(now)
 local event=Modifiers.Active(now)
 local perks=event and event.Perks or {}
 local lineLuck=perks.LineLuck or 1
 local out={}
 for _,rank in ipairs((Config.ServerLuck or {}).Ranks or {4,5,6})do out[rank]=luck*lineLuck end
 out[6]=(out[6]or 1)*(perks.SecretLine or 1)
 -- Stacked (MAX LUCK during NULL HOUR) never runs away: at most x10 on any rarity.
 for rank,value in pairs(out)do out[rank]=math.min(value,MAX_STACK)end
 return out
end

-- ===== Paid credits (profile side) =====
local function number(v)return type(v)=='number'and v==v and v>-math.huge and v<math.huge end
local function credits(p)
 local c=type(p.ServerLuckCredits)=='table'and p.ServerLuckCredits or {}
 p.ServerLuckCredits=c
 return c
end
-- Called inside the receipt transaction. Idempotent per credit id.
function S.QueueCredit(p,id,multiplier,seconds,now,name)
 assert(type(id)=='string'and #id>0 and #id<=120,'Invalid server luck credit')
 multiplier=math.clamp(tonumber(multiplier)or 1,1,10);seconds=math.floor(tonumber(seconds)or 0)
 assert(multiplier>1 and seconds>0,'Invalid server luck reward')
 local c=credits(p)
 if type(c[id])~='table'then c[id]={Multiplier=multiplier,Queued=seconds,Active=0,At=now,Name=type(name)=='string'and name:sub(1,40)or nil}end
 return c[id]
end
-- Total paid seconds a profile still holds (queued + running), for UI and checks.
function S.CreditSeconds(p)
 local total=0
 for _,row in pairs(type(p.ServerLuckCredits)=='table'and p.ServerLuckCredits or {})do
  if type(row)=='table'then total+=math.max(0,tonumber(row.Queued)or 0)+math.max(0,tonumber(row.Active)or 0)end
 end
 return total
end
-- Brings one buyer's credits in line with this server. Runs inside a RAM transaction of that
-- profile: the pool is only touched at the very end, after every check, so nothing after it
-- can fail (and the transaction cannot roll it back).
local function syncCredits(p,uid,session,now,name)
 local c=type(p.ServerLuckCredits)=='table'and p.ServerLuckCredits or nil
 if not c then return 0 end
 local order={}
 for id,row in pairs(c)do
  if type(row)=='table'and number(row.Multiplier)and row.Multiplier>1 then
   row.Queued=math.max(0,math.floor(tonumber(row.Queued)or 0));row.Active=math.max(0,math.floor(tonumber(row.Active)or 0))
   if row.Server~=session then
    -- Started on a server that is gone (shutdown or crash): restart the rest here.
    row.Queued+=row.Active;row.Active=0;row.Server=nil
   else
    row.Active=math.floor(S.Remaining(tostring(uid)..':'..tostring(id),now)+.5)
    if row.Active<=0 then row.Active=0;row.Server=nil end
   end
   if row.Queued<=0 and row.Active<=0 then c[id]=nil
   elseif row.Queued>0 then table.insert(order,id)end
  end
 end
 table.sort(order,function(a,b)
  local x,y=tonumber(c[a].At)or 0,tonumber(c[b].At)or 0
  if x~=y then return x<y end
  return tostring(a)<tostring(b)
 end)
 local started=0
 for _,id in ipairs(order)do
  local row=c[id]
  local take=S.Add(row.Multiplier,row.Queued,row.Name or name,tostring(uid)..':'..tostring(id))
  if take>0 then
   row.Queued-=take;row.Server=session;started+=take
   row.Active=math.floor(S.Remaining(tostring(uid)..':'..tostring(id),now)+.5)
  end
 end
 return started
end
-- Starts / re-syncs a connected buyer's credits. RAM transaction only (the profile must be
-- loaded here). Returns ok, seconds started.
function S.SyncFor(runtime,player,timeout)
 local uid=player.UserId;local key='p:'..uid
 if not(runtime.Tx.Loaded and runtime.Tx.Loaded[key])then return false,'Profile not loaded'end
 local session=runtime.Engine.Session;local now=os.time();local name=player.DisplayName
 return runtime.Tx:Run({key},function(v)
  local p=v[key]
  if type(p)~='table'or type(p.ServerLuckCredits)~='table'or not(p.Session and p.Session.Id==session)then return 0 end
  return syncCredits(p,uid,session,now,name)
 end,nil,timeout~=nil and{Timeout=timeout}or nil)
end
S.ActivateFor=S.SyncFor
-- Every 30 s from the economy loop: buyers with credits only (non-blocking).
function S.SyncAll(runtime)
 for uid in pairs(runtime.Loaded or {})do
  local player=Players:GetPlayerByUserId(uid)
  local p=runtime.Tx.Cache and runtime.Tx.Cache['p:'..uid]
  if player and type(p)=='table'and type(p.ServerLuckCredits)=='table'and next(p.ServerLuckCredits)~=nil then
   S.SyncFor(runtime,player,0)
  end
 end
end
-- The buyer is leaving. closing=true (server shutdown): unconsumed running time goes back to
-- the credit and restarts on their next server. Otherwise it stays with this server.
function S.Release(runtime,uid,closing)
 local prefix=tostring(uid)..':'
 local running=false
 for source in pairs(S.Entries)do if source:sub(1,#prefix)==prefix then running=true;break end end
 if not running then return true end
 local key='p:'..uid;local session=runtime.Engine.Session;local now=os.time()
 local ok,err=true,nil
 if runtime.Tx.Loaded and runtime.Tx.Loaded[key]then
  ok,err=runtime.Tx:Run({key},function(v)
   local p=v[key];local c=type(p)=='table'and type(p.ServerLuckCredits)=='table'and p.ServerLuckCredits or {}
   for id,row in pairs(c)do
    if type(row)=='table'and row.Server==session then
     row.Active=closing and math.floor(S.Remaining(prefix..tostring(id),now)+.5)or 0
     if row.Active<=0 then row.Active=0;row.Server=nil end
     if (tonumber(row.Queued)or 0)<=0 and row.Active<=0 then c[id]=nil end
    end
   end
   return true
  end,nil,{Timeout=10})
 end
 for source in pairs(S.Entries)do if source:sub(1,#prefix)==prefix then S.Entries[source]=nil end end
 return ok,err
end
publish('',0,1)
return S
