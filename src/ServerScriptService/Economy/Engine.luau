local PaidPolicy=require(script.Parent.PaidItemPolicy)
local R=require(script.Parent.Rules)
local Lifetime=require(script.Parent.LifetimeStats)
local C=require(script.Parent.Config)
local D=require(script.Parent.DogDefinitions)
local Market=require(script.Parent.Market)
local I=require(script.Parent.ItemRules)
local Offline=require(script.Parent.OfflineEarnings)
local ServerLuck=require(script.Parent.ServerLuck)
local ShowcaseRules=require(game:GetService('ReplicatedStorage').DogEconomy.ShowcaseRules)
local E={};E.__index=E
local function pk(id) return 'p:'..id end
function E.new(tx,options)
 local self=setmetatable({Tx=tx,Now=options.Now,Guid=options.Guid,Random=options.Random,Session=options.Session,
  Connected=options.Connected or function()return true end,AssetReady=options.AssetReady or function(id)return D[id] and D[id].Available end,
  Trades={},TradeByUser={},TradeInvites={},TradeCooldowns={}},E)
 self.Market=Market.new(tx,self.Now,self.Guid,function(p,id)self:Authorize(p,id)end)
 return self
end
function E:Authorize(p,id)
 R.Check(p and p.UserId==id and p.Session and p.Session.Id==self.Session and p.Session.Expires>self.Now(),"Profile session unavailable")
 R.Check(self.Connected(id),"Player disconnected")
end
function E:Join(id)
 return self.Tx:Run({pk(id)},function(v)
  local p=R.Normalize(v[pk(id)],id,self.Now());v[pk(id)]=p
  R.Check(not p.Session or p.Session.Id==self.Session or p.Session.Expires<=self.Now(),"Account is active on another server. Retry shortly.")
  Offline.Join(p,self.Now(),self.Session)
  local play=p.PlaytimeRewards or {};local day=math.floor(self.Now()/86400)
  if play.Day~=day then play={Day=day,Accumulated=0,Claims={}}end
  play.StartedAt=self.Now();play.Session=self.Session;play.Claims=play.Claims or {};p.PlaytimeRewards=play
  p.Stats.SessionFinds=0
  p.Session={Id=self.Session,Expires=self.Now()+C.SessionSeconds,StatsAt=self.Now()};p.LastDig=self.Now()
  for _,d in pairs(p.Dogs) do if d.State=="Walking" then d.State="Inventory" end end
  R.Validate(p);return "Loaded"
 end)
end
-- options (optional) go to Tx:Run, e.g. {Timeout=30}: PlayerRemoving waits longer for a
-- receipt that holds the profile lock, so the session is released instead of left to expire.
-- A player who is connected again (a quick rejoin to this server loaded a new session with the
-- same server session id while the old release waited for the lock or a save) is not leaving:
-- the old release must not end the new session.
function E:Leave(id,options)
 if self.Connected(id)then return true,"Rejoined"end
 pcall(self.CancelTrade,self,id,'Left')
 local ok,result=self.Tx:Run({pk(id)},function(v)
  if self.Connected(id)then return "Rejoined"end
  local p=v[pk(id)];if p and p.Session and p.Session.Id==self.Session then
    local now=self.Now();local play=p.PlaytimeRewards
    if type(play)=='table'and play.Day==math.floor(now/86400)then
     play.Accumulated=(play.Accumulated or 0)+math.max(0,now-(play.StartedAt or now));play.StartedAt=now
    end
    Lifetime.Checkpoint(p,now);Offline.Checkpoint(p,now);p.Session=nil
   end
  return "Saved"
 end,nil,options)
 if ok and result~="Rejoined"and self.OnProfileReleased then pcall(self.OnProfileReleased,id)end
 return ok,result
end
function E:Get(id) return self.Tx:Read(pk(id)) end
function E:Action(id,action,args,request)
 local now=self.Now()
 return self.Tx:Run({pk(id)},function(v)
  local p=v[pk(id)];self:Authorize(p,id);R.Normalize(p,id,now)
  if action=='BuyPlotSkin'or action=='ClaimPlotSkin'then require(script.Parent.PlotDevelopment).VisitShop(game.Players:GetPlayerByUserId(id))end
  local message,extra=R.Action(p,action,args,now,self.Random);Offline.Checkpoint(p,now);R.Validate(p)
  local result={Message=message}
  if type(extra)=='table'then for k,x in pairs(extra)do if k~='Message'then result[k]=x end end end
  if action:sub(1,6)=='Mining'then result.MiningState=R.Copy(p.Mining);result.Cash=p.Cash;result.XP=p.XP;result.Level=p.Level end
  if action=='SellLoot'then
   local pending,lootCount=0,0
   for _,stack in pairs(p.Loot or{})do pending+=stack.Value or 0;lootCount+=stack.Count or 0 end
   result.FastSale={Cash=p.Cash,ItemCount=I.Count(p.Items),PendingCash=pending,LootCount=lootCount,Loot=R.Copy(p.Loot or{}),Stats=R.Copy(p.Stats),LastSaleAt=p.LastSaleAt,XP=p.XP,Level=p.Level}
  end
  return result
 end,request)
end
-- Active Mining runs often (one request per timing circle), so it skips the full profile
-- Normalize / Offline.Checkpoint / Validate pass of E:Action: TickAll normalizes every second and
-- mining touches only Cash, XP, p.Mining and p.Resources (Stone from broken ores).
-- session = RAM timing targets (Economy.MiningSessions).
function E:MiningAction(id,action,args,request,session,ping)
 local now=self.Now()
 return self.Tx:Run({pk(id)},function(v)
  local p=v[pk(id)];self:Authorize(p,id)
  local message=R.MiningAction(p,action,args,now,self.Random,session,ping)
  R.Check(R.Int(p.Cash,0,C.MaxCash),"Invalid wallet")
  local onboarding=require(script.Parent.OnboardingRules).Observe(p,now)
  return {Message=message,MiningState=R.Copy(p.Mining),Cash=p.Cash,XP=p.XP,Level=p.Level,Onboarding=R.Copy(onboarding),Resources=R.Copy(p.Resources),
   MiningTargets=require(game:GetService('ReplicatedStorage').Mining.MiningRules).ViewTargets(session)}
 end,request)
end
function E:ClaimOffline(id,args,request)
 local now=self.Now()
 return self.Tx:Run({pk(id)},function(v)
  local p=v[pk(id)];self:Authorize(p,id)
  local result=Offline.Claim(p,args.PendingId,now);R.Validate(p);return result
 end,request)
end
function E:Tick(id)
 local now=self.Now()
 return self.Tx:Run({pk(id)},function(v)
  local p=v[pk(id)];self:Authorize(p,id);R.Normalize(p,id,now)
  Lifetime.Checkpoint(p,now);p.Session.Expires=now+C.SessionSeconds
  local contribution=R.Dig(p,now,self.Random);Offline.Checkpoint(p,now)
  R.Validate(p);return {Contribution=contribution,Week=R.Week(now)}
 end)
end
function E:TickAll(ids)
 -- One RAM transaction per player: a single broken profile can no longer stop
 -- digging (and session renewal) for everybody else on the server. A profile whose lock
 -- is held (a Robux receipt or another durable transaction waiting on DataStore) is
 -- skipped this second (Timeout=0) instead of stalling or killing the server loop.
 local now=self.Now();local contribution,failed,skipped=0,{},{}
 local busy=self.Tx.BusyMessage or "Account is busy; retry shortly"
 for _,id in ipairs(ids) do
  local ok,result=self.Tx:Run({pk(id)},function(v)
   local p=v[pk(id)]
   -- Renew whenever this server owns the session, even if a stalled tick let it
   -- lapse in RAM; otherwise the player would be locked out until rejoining.
   if not (p and self.Connected(id) and p.Session and p.Session.Id==self.Session) then return 0 end
   R.Normalize(p,id,now);Lifetime.Checkpoint(p,now);p.Session.Expires=now+C.SessionSeconds
   local amount=R.Dig(p,now,self.Random);Offline.Checkpoint(p,now);R.Validate(p)
   return amount
  end,nil,{Timeout=0})
  if ok then contribution+=tonumber(result)or 0
  elseif result==busy then skipped[id]=true
  else failed[id]=tostring(result)end
 end
 return true,{Contribution=contribution,Week=R.Week(now),Failed=failed,Skipped=skipped}
end
function E:EventClaim(id,a,request)
 if require(game.ReplicatedStorage.GlobalDigConfig).Enabled==false then return false,'Global Dig is coming soon'end
 local now=self.Now();local key='event:'..R.Week(now)
 R.Check(R.Int(a.Milestone,1,5),"Invalid milestone")
 return self.Tx:Run({pk(id),key},function(v)
  local p=v[pk(id)];self:Authorize(p,id);R.Normalize(p,id,now)
  local e=v[key] or {Total=0};local i=a.Milestone
  R.Check(e.Total>=C.EventMilestones[i] and p.Event.Contribution>=C.EventPersonal[i],"More community and personal contribution required")
  R.Check(not p.Event.Claims[tostring(i)],"Already claimed")
  p.Event.Claims[tostring(i)]=true;p.Bones+=i*10;p.EventTokens+=i*25;p.Cosmetics['Event'..i]=true
  return {Message="Event reward claimed"}
 end,request)
end
-- A dog's share of its rarity's line budget. Ordinary dogs split it evenly;
-- Secrets carry a LineWeight so the rarest of them (THE DOG) stays the rarest.
local function lineShare(def)return def.LineWeight or 1 end
-- Every rarity can walk the shared line for every player; price is the only gate.
-- maxRank leaves out the rarer groups (their budget is not redistributed).
function E:LineOdds(maxRank)
 local choices,total,groups={},0,{}
 -- Server luck and an active world event lift the rare groups (ServerLuck.Ranks).
 local luck=ServerLuck.Ranks(self.Now())
 for id,def in pairs(D) do if def.CanSpawnOnLine==true and def.Rank<=(maxRank or #C.Rarities) and self.AssetReady(id) and R.Available(def,self.Now()) then
  groups[def.Rank]=groups[def.Rank]or{};table.insert(groups[def.Rank],def)
 end end
 -- Each rarity owns one probability budget regardless of how many dogs it contains.
 for rank=1,#C.Rarities do
  local members=groups[rank]
  if members then
   table.sort(members,function(a,b)return a.Id<b.Id end)
   local shares=0;for _,def in ipairs(members)do shares+=lineShare(def)end
   for _,def in ipairs(members)do
    local weight=(C.Weights[rank]or 0)*lineShare(def)/shares*(luck[rank]or 1)
    if weight>0 then total+=weight;table.insert(choices,{Id=def.Id,Rank=rank,Weight=weight,Ceiling=total})end
   end
  end
 end
 return choices,total
end
function E:Choose(maxRank)
 local choices,total=self:LineOdds(maxRank)
 if total==0 then return nil end
 local roll=self.Random()*total;for _,v in ipairs(choices) do if roll<v.Ceiling then return v.Id end end
 return choices[#choices].Id
end
-- One line dog of the given rarity, for the conveyor's overdue-rarity guarantee.
function E:ChooseRank(rank)
 local members,shares={},0
 for id,def in pairs(D)do if def.Rank==rank and def.CanSpawnOnLine==true and self.AssetReady(id) and R.Available(def,self.Now())then table.insert(members,def);shares+=lineShare(def)end end
 if #members==0 then return nil end
 table.sort(members,function(a,b)return a.Id<b.Id end)
 local roll=self.Random()*shares
 for _,def in ipairs(members)do roll-=lineShare(def);if roll<0 then return def.Id end end
 return members[#members].Id
end
-- Called only by server discovery/arrival orchestration, never by an economy remote action.
-- An arrival's operation ID must remain stable while retrying storage/capacity failures.
function E:GrantSpecial(id,dogId,operation)
 R.Check(dogId=='LongDog'or dogId=='TheDog','Unknown special discovery')
 R.Check(type(operation)=='string'and #operation>0 and #operation<=80,'Invalid special operation')
 R.Check(self.AssetReady(dogId),'Special dog asset unavailable')
 -- Arrival GUIDs are server-wide identities; short prefixes stay within DataStore's 50-character key limit.
 local key=dogId=='TheDog'and'sa:'..operation or'sl:'..id..':'..operation
 R.Check(#key<=50,'Special operation key is too long')
 local uid=self.Guid();local now=self.Now()
 return self.Tx:Run({pk(id),'supply:'..dogId,key},function(v)
  local p=v[pk(id)];self:Authorize(p,id);R.Normalize(p,id,now)
  if v[key]then R.Check(v[key].UserId==id,'This arrival belongs to another player');return v[key]end
  p.SpecialDiscoveries=p.SpecialDiscoveries or{}
  if dogId=='LongDog'then
   R.Check(p.SpecialDiscoveries.LongDogPending==true,'No excavation discovery pending')
  else
   R.Check(p.UnlockedLayers['5']and p.Prestige>=1,'Reach THE VOID and Prestige 1')
   R.Check(now-(p.SpecialDiscoveries.LastArrivalAt or 0)>=C.SpecialAcquisition.TheDog.ClaimCooldown,'Arrival reward cooldown')
  end
  local supply=v['supply:'..dogId]or{};v['supply:'..dogId]=supply
  local dog=R.Mint(p,dogId,uid,supply,now,self.Random,dogId=='LongDog'and'Excavation'or'ServerArrival')
  if dogId=='LongDog'then p.SpecialDiscoveries.LongDogPending=nil
  else p.SpecialDiscoveries.LastArrivalAt=now end
  dog.PricePaid=0
  local result={UserId=id,Dog=R.Copy(dog),DogUid=uid,DogId=dogId,At=now,Message='Discovered '..dog.DisplayName}
  v[key]=result;R.Validate(p);return result
 end)
end
-- variant: the server-rolled variant of the conveyor dog (DogLineSpawner model attribute). It only
-- applies to a first purchase; a rebuy keeps the dog's saved variant.
function E:BuyLine(id,dogId,uid,request,variant)
 R.Check(self.AssetReady(dogId),"Dog asset unavailable")
 R.Check(variant==nil or(type(variant)=="string"and R.VariantNames[variant]==true),"Invalid variant")
 local key='line:'..uid;local order=self.Tx:Read(key);local old=order and order.Owner
 local keys={pk(id),key,'supply:'..dogId};if old and old~=id then table.insert(keys,pk(old)) end
 local now=self.Now()
 return self.Tx:Run(keys,function(v)
  local p=v[pk(id)];self:Authorize(p,id)
  R.Check(R.Available(D[dogId],now),"This dog is not available")
  local current=v[key];R.Check((current and current.Owner)==old,"Another player bought this dog; try again")
  R.Check(R.Free(p),"Dog storage full")
  local price=current and current.NextPrice or D[dogId].LinePrice or D[dogId].BasePrice;local dog
  if current then
   R.Check(current.State=="Walking" and current.DogId==dogId and old~=id,"Dog cannot be rebought")
   local from=v[pk(old)];dog=from and from.Dogs[uid]
   R.Check(dog and dog.State=="Walking","Dog already delivered")
   R.Pay(p,price);R.Credit(from,math.floor((dog.PricePaid or 0)*.9),false);from.Dogs[uid]=nil;R.Transfer(dog,p,now,"Rebuy")
  else
   R.Pay(p,price);local supply=v['supply:'..dogId] or {};v['supply:'..dogId]=supply
   dog=R.Mint(p,dogId,uid,supply,now,self.Random,"DogLine",variant)
  end
  dog.State="Walking";dog.PricePaid=price
  R.AddXP(p,15+10*(D[dogId].Rank or 1))
  v[key]={Owner=id,DogId=dogId,State="Walking",NextPrice=math.min(C.MaxCash,math.ceil(price*1.3))}
  R.Validate(p)
  return {Dog=R.Copy(dog),NextPrice=v[key].NextPrice,PreviousOwner=old}
 end,request)
end
function E:Deliver(id,uid)
 return self.Tx:Run({pk(id),'line:'..uid},function(v)
  local p=v[pk(id)];local d=p and p.Dogs[uid];local order=v['line:'..uid]
  R.Check(order and order.Owner==id and d,"Delivery owner changed")
  d.State="Inventory";order.State="Delivered";return "Delivered"
 end)
end
function E:Roll(id,mode,request)
 R.Check(mode~='LuckyBlock','Visit the tongue or Lucky Blocks in Shop')
 R.Check(mode=="LuckyBlock" or mode=="EventRoll","Invalid roll")
 -- Event Tokens are the Global Dig currency, and dog income earns them even while the player is
 -- away: like EventClaim, the token roll (100 tokens -> a dog) is closed while Global Dig is.
 if mode=="EventRoll"and require(game.ReplicatedStorage.GlobalDigConfig).Enabled==false then return false,'Global Dig is coming soon'end
 local current=self:Get(id);self:Authorize(current,id)
 -- Secrets only come from the tongue and blocks, never from a token roll.
 local dogId=self:Choose(5);R.Check(dogId,"No assets available")
 local uid=self.Guid();local now=self.Now()
 return self.Tx:Run({pk(id),'supply:'..dogId},function(v)
  local p=v[pk(id)];self:Authorize(p,id);R.Normalize(p,id,now)
  if mode=="EventRoll" then R.Check(p.EventTokens>=100,"Requires 100 Event Tokens");p.EventTokens-=100
  else R.Pay(p,600,2) end
  local s=v['supply:'..dogId] or {};v['supply:'..dogId]=s
  local d=R.Mint(p,dogId,uid,s,now,self.Random,mode);d.PricePaid=mode=="LuckyBlock" and 600 or 0
  return {Message="Found "..d.DisplayName.." · "..d.Variant,DogUid=uid}
 end,request)
end
------------------------------------------------------------------------------------------------
-- TRADES 2.0 (docs/TRADE.md). Everything lives in RAM: a server restart cancels invitations and
-- sessions, and saved profiles never hold trade state.
--   Invitations (self.TradeInvites[id] = {Id, From, To, Created, Expires}) lock nobody: the target
--   keeps selling, using the lab and the shelter until they accept. A decline, an expiry or a
--   withdrawal starts a sender->target cooldown (self.TradeCooldowns['from>to'] = until).
--   Sessions (self.Trades[tradeId], self.TradeByUser[userId] = tradeId) start when the invitee
--   accepts; while one exists both players are "trading" (YardCommerce, LabService and
--   ShelterService refuse their actions). Any offer change resets both READY flags; after both
--   READY a countdown (TradeRules.ConfirmDelay) runs; then both press CONFIRM and the second
--   confirm runs one transaction over both profiles (receipt id trade-<id>).
--   PruneTrades (every trade call and every snapshot) drops expired invitations and cooldowns and
--   idle or orphaned sessions, so nothing lingers in RAM.
--   self.OnTrade(userId, event) (set by Runtime) pushes every change to the players concerned.
------------------------------------------------------------------------------------------------
local TradeRules=require(game:GetService('ReplicatedStorage'):WaitForChild('DogEconomy'):WaitForChild('TradeRules'))
E.TradeRules=TradeRules
local function pairKey(from,to)return tostring(from)..'>'..tostring(to)end
local function fingerprint(d)
 return table.concat({d.DogUid,d.DogId,d.Variant,d.Edition,tostring(d.SerialNumber),tostring(d.Mastery),tostring(d.AscensionLevel),d.AssignedSlot,d.State},'|')
end
local function itemPrint(x)return table.concat({x.ItemUid,x.ItemId,tostring(x.WeightKg),x.Mutation},"|")end
-- What the trade view shows of an offered dog / find (the full records stay in the profiles).
local DOG_VIEW={'DogUid','DogId','DisplayName','Rarity','Variant','Mastery','AscensionLevel','Edition','SerialNumber','OG','Origin','CreatedAt','PaidRandom'}
local ITEM_VIEW={'ItemUid','ItemId','DisplayName','Depth','Class','SetId','BaseDropChance','WeightKg','WeightTier','TierIndex','Mutation','SellValue','FoundAt','OriginalFinderUserId','RecordAtCreation','PaidRandom'}
local function slim(x,fields)local out={};for _,k in ipairs(fields)do out[k]=R.Copy(x[k])end;return out end
local function emptyOffer()return {Dogs={},Items={},Cash=0,Prints={},ItemPrints={},Details={},Estimated=0,Value=0}end
-- A dog / find its owner may give away: R.Dog (owned, delivered, unlocked, not working in a
-- kennel) and I.Get (owned, tradeable, no record check pending), the shelter's rules (not on
-- display, not reserved) and, for finds, the favourite star (item locking is disabled, so the
-- star is what protects a find).
local function tradeDog(p,uid)
 local dog=R.Dog(p,uid,true)
 for _,shown in pairs(p.DisplayDogs or {})do R.Check(shown~=uid,"Remove this dog from its display first")end
 R.Check(not(p.Reservations and p.Reservations[uid]),"Dog is reserved")
 return dog
end
local function tradeItem(p,uid)
 local x=I.Get(p,uid,true)
 R.Check(not x.Favorite,"Remove this find from favourites first")
 R.Check(not ShowcaseRules.IsPinned(p,uid),"This find is in your showcase. Take it out of MY BEST FINDS first")
 R.Check(not(p.ItemReservations and p.ItemReservations[uid]),"Find is reserved")
 return x
end
-- nil, or the user whose storage cannot take the trade and which storage ('Dogs' | 'Items').
local function capacityProblem(users,profiles,offers)
 for i=1,2 do
  local p,give,take=profiles[i],offers[i],offers[3-i]
  if R.Count(p.Dogs)-#give.Dogs+#take.Dogs+R.Count(p.Reservations or {})>R.Capacity(p)then return users[i],'Dogs'end
  if I.Count(p.Items)-#give.Items+#take.Items+I.Count(p.ItemReservations)>I.Capacity(p)then return users[i],'Items'end
 end
 return nil
end
local function fullMessage(owner,kind,viewer)
 if kind=='Dogs'then return owner==viewer and"Your dog storage is full"or"Your partner's dog storage is full"end
 return owner==viewer and"Your find storage is full"or"Your partner's find storage is full"
end
local function partnerOf(t,id)return t.Users[1]==id and t.Users[2]or t.Users[1]end
local function both(t,set)return set[tostring(t.Users[1])]==true and set[tostring(t.Users[2])]==true end
local function findInvite(self,from,to)
 for _,inv in pairs(self.TradeInvites)do if inv.From==from and inv.To==to and inv.Expires>self.Now()then return inv end end
 return nil
end
function E:_tradeEvent(users,event)
 local push=self.OnTrade;if type(push)~='function'then return end
 for _,user in ipairs(users)do
  local ok,err=pcall(push,user,event)
  if not ok then warn('DOGROTS trade push failed:',err)end
 end
end
function E:_endTrade(t,kind,by,extra)
 for _,user in ipairs(t.Users)do if self.TradeByUser[user]==t.Id then self.TradeByUser[user]=nil end end
 self.Trades[t.Id]=nil
 local event={Kind=kind,Trade=t.Id,By=by,Users=R.Copy(t.Users)}
 for k,v in pairs(extra or {})do event[k]=v end
 self:_tradeEvent(t.Users,event)
end
function E:_dropInvite(inv,reason,cooldown)
 self.TradeInvites[inv.Id]=nil
 -- An expiry counts from the moment it expired, even when the prune runs later.
 if cooldown then self.TradeCooldowns[pairKey(inv.From,inv.To)]=(reason=='Expired'and inv.Expires or self.Now())+TradeRules.InviteCooldown end
 self:_tradeEvent({inv.From,inv.To},{Kind='InviteGone',Invite=inv.Id,From=inv.From,To=inv.To,Reason=reason})
end
-- Drops expired invitations (an expiry counts as a decline for the cooldown), finished cooldowns
-- and sessions whose players left or that sat idle for TradeRules.SessionIdle seconds.
function E:PruneTrades()
 local now=self.Now()
 for key,untilAt in pairs(self.TradeCooldowns)do if untilAt<=now then self.TradeCooldowns[key]=nil end end
 for _,inv in pairs(self.TradeInvites)do
  if inv.Expires<=now then self:_dropInvite(inv,'Expired',true)
  elseif not(self.Connected(inv.From)and self.Connected(inv.To))then self:_dropInvite(inv,'Left',false)end
 end
 for _,t in pairs(self.Trades)do
  if not t.Committing then
   if not(self.Connected(t.Users[1])and self.Connected(t.Users[2]))then self:_endTrade(t,'Left')
   elseif t.Expires<=now then self:_endTrade(t,'Expired')end
  end
 end
 for user,tid in pairs(self.TradeByUser)do if not self.Trades[tid]then self.TradeByUser[user]=nil end end
end
-- Ends this player's session (TradeCancel, Leave). reason 'Left' (Leave) also drops every
-- invitation from or to the player.
function E:CancelTrade(id,reason)
 local tid=self.TradeByUser[id];local t=tid and self.Trades[tid]
 if t and not t.Committing then self:_endTrade(t,reason=='Left'and'Left'or'Cancelled',id)end
 if reason=='Left'then
  for _,inv in pairs(self.TradeInvites)do if inv.From==id or inv.To==id then self:_dropInvite(inv,'Left',false)end end
 end
end
-- TradeCancel: ends the session, or (no session) withdraws this player's invitations (all of them,
-- or the one to a.Target). A withdrawal starts the same cooldown as a decline.
function E:TradeCancel(id,a)
 a=type(a)=='table'and a or {}
 self:PruneTrades()
 local tid=self.TradeByUser[id];local t=tid and self.Trades[tid]
 if t then
  R.Check(not t.Committing,"Trade is committing")
  self:_endTrade(t,'Cancelled',id)
  return {Message="Trade cancelled"}
 end
 local withdrawn=0
 for _,inv in pairs(self.TradeInvites)do
  if inv.From==id and(a.Target==nil or inv.To==a.Target)then withdrawn+=1;self:_dropInvite(inv,'Withdrawn',true)end
 end
 return {Message=withdrawn>0 and"Invitation withdrawn"or"Trade cancelled"}
end
-- How `id` sees `other` in the player list: pending invitations both ways, the cooldown, and why an
-- invitation is impossible now (Block: 'Level' | 'TheirLevel' | 'Trading' | 'Busy' | 'Sent' |
-- 'Cooldown'). The caller passes the levels (no profile copies).
function E:TradeRelation(id,other,myLevel,theirLevel)
 local now=self.Now();local row={}
 for _,inv in pairs(self.TradeInvites)do
  if inv.Expires>now then
   if inv.From==other and inv.To==id then row.InviteIn={Id=inv.Id,Expires=inv.Expires,In=inv.Expires-now}
   elseif inv.From==id and inv.To==other then row.InviteOut={Id=inv.Id,Expires=inv.Expires,In=inv.Expires-now}end
  end
 end
 local wait=(self.TradeCooldowns[pairKey(id,other)]or 0)-now
 if wait>0 then row.Cooldown=wait end
 local block=nil
 if(tonumber(myLevel)or 1)<C.TradeLevel then block='Level'
 elseif(tonumber(theirLevel)or 1)<C.TradeLevel then block='TheirLevel'
 elseif self.TradeByUser[id]then block='Trading'
 elseif self.TradeByUser[other]then block='Busy'
 elseif row.InviteIn then block=nil
 elseif row.InviteOut then block='Sent'
 elseif wait>0 then block='Cooldown'end
 row.CanInvite=block==nil;row.Block=block
 return row
end
function E:TradeRequest(id,target)
 self:PruneTrades()
 R.Check(R.Int(target,-9007199254740991,9007199254740991) and target~=0 and target~=id and self.Connected(target),"Choose an online player")
 R.Check(not self.TradeByUser[id],"Finish your current trade first")
 R.Check(not self.TradeByUser[target],"That player is busy in another trade")
 local mine,theirs=self:Get(id),self:Get(target)
 R.Check(mine and theirs and (mine.Level or 1)>=C.TradeLevel and (theirs.Level or 1)>=C.TradeLevel,"Trading unlocks at level "..C.TradeLevel.." for both players")
 -- They invited you first: inviting them back accepts their invitation.
 local reverse=findInvite(self,target,id)
 if reverse then return self:_acceptInvite(id,reverse)end
 R.Check(not findInvite(self,id,target),"Invitation already sent")
 local now=self.Now()
 local wait=(self.TradeCooldowns[pairKey(id,target)]or 0)-now
 R.Check(wait<=0,"Wait "..math.ceil(wait).."s before inviting this player again")
 local pending=0;for _,inv in pairs(self.TradeInvites)do if inv.From==id then pending+=1 end end
 R.Check(pending<TradeRules.MaxInvites,"You already have "..TradeRules.MaxInvites.." pending invitations")
 local inv={Id=self.Guid(),From=id,To=target,Created=now,Expires=now+TradeRules.InviteSeconds}
 self.TradeInvites[inv.Id]=inv
 self:_tradeEvent({target,id},{Kind='Invite',Invite=inv.Id,From=id,To=target,Expires=inv.Expires,In=TradeRules.InviteSeconds})
 return {Message="Trade invitation sent",Invite=R.Copy(inv)}
end
-- The invitation an Accept / Decline means: a.Invite (id), a.From (sender) or the newest one.
function E:_inviteFor(id,a)
 local best=nil;local now=self.Now()
 for _,inv in pairs(self.TradeInvites)do
  if inv.To==id and inv.Expires>now and(a.Invite==nil or inv.Id==a.Invite)and(a.From==nil or inv.From==a.From)then
   if not best or inv.Created>best.Created then best=inv end
  end
 end
 R.Check(best,"This invitation has expired")
 return best
end
function E:_acceptInvite(id,inv)
 local now=self.Now()
 R.Check(inv.To==id and inv.Expires>now,"This invitation has expired")
 R.Check(self.Connected(inv.From),"That player left the server")
 R.Check(not self.TradeByUser[id],"Finish your current trade first")
 R.Check(not self.TradeByUser[inv.From],"That player is busy in another trade")
 local a,b=self:Get(inv.From),self:Get(id)
 R.Check(a and b and (a.Level or 1)>=C.TradeLevel and (b.Level or 1)>=C.TradeLevel,"Trading unlocks at level "..C.TradeLevel.." for both players")
 self.TradeInvites[inv.Id]=nil
 local t={Id=self.Guid(),Users={inv.From,id},Version=1,Seq=1,Offers={},Ready={},Confirmed={},Inviter=inv.From,Accepted=true,
  StartedAt=now,UpdatedAt=now,Expires=now+TradeRules.SessionIdle,ConfirmDelay=TradeRules.ConfirmDelay}
 for _,user in ipairs(t.Users)do t.Offers[tostring(user)]=emptyOffer()end
 self.Trades[t.Id]=t;self.TradeByUser[inv.From]=t.Id;self.TradeByUser[id]=t.Id
 -- Both players are busy now: their other invitations end.
 for _,other in pairs(self.TradeInvites)do
  if other.From==id or other.To==id or other.From==inv.From or other.To==inv.From then self:_dropInvite(other,'Busy',false)end
 end
 self:_tradeEvent(t.Users,{Kind='Started',Trade=t.Id,By=id,From=inv.From,To=id})
 return {Message="Trade accepted",Trade=self:TradeView(id)}
end
-- The session as `id` sees it: the trade record (offers with slim Details, Ready, Confirmed,
-- Version...; the fields the old window read) plus Me / Partner, the merged Details, the
-- seconds left (ConfirmIn, ReviewIn, ExpiresIn), the limits and the value check (Fairness).
function E:TradeView(id)
 local tid=self.TradeByUser[id];local t=tid and self.Trades[tid];if not t then return nil end
 local now=self.Now();local view=R.Copy(t);local other=partnerOf(t,id)
 view.Details={};for _,offer in pairs(view.Offers)do for uid,x in pairs(offer.Details or {})do view.Details[uid]=x end end
 view.Me=id;view.Partner=other;view.Now=now;view.Committing=t.Committing==true
 view.ConfirmIn=t.ConfirmAfter and math.max(0,t.ConfirmAfter-now)or nil
 view.ReviewIn=math.max(0,(t.UpdatedAt or now)+TradeRules.ReviewSeconds-now)
 view.ExpiresIn=math.max(0,t.Expires-now)
 view.Limits={Dogs=TradeRules.MaxDogs,Items=TradeRules.MaxItems,ConfirmDelay=TradeRules.ConfirmDelay,ReviewSeconds=TradeRules.ReviewSeconds,WarnRatio=TradeRules.WarnRatio}
 local mine,theirs=t.Offers[tostring(id)],t.Offers[tostring(other)]
 view.Fairness=TradeRules.Fairness(mine and mine.Value or 0,theirs and theirs.Value or 0)
 return view
end
function E:_commitTrade(t)
 local left,right=t.Users[1],t.Users[2];local now=self.Now()
 local a,b=t.Offers[tostring(left)],t.Offers[tostring(right)]
 t.Committing=true
 local ok,result=self.Tx:Run({pk(left),pk(right)},function(v)
  local p,q=v[pk(left)],v[pk(right)];self:Authorize(p,left);self:Authorize(q,right)
  I.Normalize(p);I.Normalize(q)
  local owner,kind=capacityProblem(t.Users,{p,q},{a,b})
  if owner then error('TRADE_FULL:'..kind..':'..tostring(owner),0)end
  for _,side in ipairs({{p,a},{q,b}})do
   for _,uid in ipairs(side[2].Dogs)do R.Check(fingerprint(tradeDog(side[1],uid))==side[2].Prints[uid],"A dog changed; review the offer again")end
   for _,uid in ipairs(side[2].Items)do R.Check(itemPrint(tradeItem(side[1],uid))==side[2].ItemPrints[uid],"A find changed; review the offer again")end
  end
  R.Pay(p,a.Cash);R.Pay(q,b.Cash);R.Credit(p,b.Cash,false);R.Credit(q,a.Cash,false)
  local outgoingA,outgoingB={},{}
  for _,uid in ipairs(a.Dogs) do outgoingA[uid]=p.Dogs[uid];p.Dogs[uid]=nil end
  for _,uid in ipairs(b.Dogs) do outgoingB[uid]=q.Dogs[uid];q.Dogs[uid]=nil end
  for uid,d in pairs(outgoingA) do R.Check(not q.Dogs[uid],"Duplicate DogUid");R.Transfer(d,q,now,"Trade") end
  for uid,d in pairs(outgoingB) do R.Check(not p.Dogs[uid],"Duplicate DogUid");R.Transfer(d,p,now,"Trade") end
  local itemsA,itemsB={},{}
  for _,uid in ipairs(a.Items)do itemsA[uid]=p.Items[uid];p.Items[uid]=nil end
  for _,uid in ipairs(b.Items)do itemsB[uid]=q.Items[uid];q.Items[uid]=nil end
  for _,x in pairs(itemsA)do I.Transfer(q,x)end;for _,x in pairs(itemsB)do I.Transfer(p,x)end
  -- Old profiles may have a Stats table without the counter.
  for _,x in ipairs({p,q})do x.Stats.CompletedTrades=(tonumber(x.Stats.CompletedTrades)or 0)+1 end
  R.Validate(p);R.Validate(q);return {Message="Trade completed"}
 end,'trade-'..t.Id)
 t.Committing=false
 return ok,result
end
-- Trade{Action=...}: Accept / Decline (an invitation: a.Invite or a.From, default the newest);
-- Offer {Dogs, Items, Cash} (replaces the whole offer), Ready {Version}, Unready, Confirm {Version}.
function E:Trade(id,action,a)
 a=type(a)=='table'and a or {}
 self:PruneTrades()
 if action=="Accept" then return self:_acceptInvite(id,self:_inviteFor(id,a))end
 if action=="Decline" then self:_dropInvite(self:_inviteFor(id,a),'Declined',true);return {Message="Invitation declined"}end
 local t=self.Trades[self.TradeByUser[id]];R.Check(t and t.Expires>self.Now(),"Trade expired")
 R.Check(not t.Committing,"Trade is committing")
 local now=self.Now();local key=tostring(id);local other=partnerOf(t,id)
 local function changed(message)
  t.Seq=(t.Seq or 0)+1;t.Expires=now+TradeRules.SessionIdle
  self:_tradeEvent(t.Users,{Kind='Changed',Trade=t.Id,By=id,Action=action})
  return {Message=message,Trade=self:TradeView(id)}
 end
 if action=="Offer" then
  local dogs,items,cash=a.Dogs or {},a.Items or {},a.Cash or 0
  R.Check(type(dogs)=="table" and type(items)=="table" and R.Int(cash,0,C.MaxCash) and R.Count(dogs)==#dogs and R.Count(items)==#items,"Invalid offer")
  R.Check(#dogs<=TradeRules.MaxDogs,"Maximum "..TradeRules.MaxDogs.." dogs per trade")
  R.Check(#items<=TradeRules.MaxItems,"Maximum "..TradeRules.MaxItems.." finds per trade")
  local p=self:Get(id);self:Authorize(p,id);I.Normalize(p);R.Check(p.Cash>=cash,"Not enough Cash")
  local offer=emptyOffer();offer.Cash=cash;local seen={};local value=cash
  for _,uid in ipairs(items)do
   R.Check(not seen[uid],"Duplicate ItemUid");seen[uid]=true;local x=tradeItem(p,uid)
   local view=slim(x,ITEM_VIEW);view.Value=TradeRules.ItemValue(x);view.Rarity=TradeRules.ItemRarity(x)
   table.insert(offer.Items,uid);offer.ItemPrints[uid]=itemPrint(x);offer.Details[uid]=view;value+=view.Value
  end
  for _,uid in ipairs(dogs) do
   R.Check(not seen[uid],"Duplicate DogUid");seen[uid]=true;local dog=tradeDog(p,uid)
   R.Check(not dog.PaidRandom or (PaidPolicy.Allowed(t.Users[1])and PaidPolicy.Allowed(t.Users[2])),'Paid-item trading is unavailable for a participant')
   local view=slim(dog,DOG_VIEW);view.Value=TradeRules.DogValue(dog);view.Rarity=TradeRules.DogRarity(dog)
   table.insert(offer.Dogs,uid);offer.Prints[uid]=fingerprint(dog);offer.Details[uid]=view;value+=view.Value
  end
  -- The policy lookup can yield: the session must still be the same one.
  R.Check(self.Trades[t.Id]==t and not t.Committing,"Trade expired")
  offer.Value=value;offer.Estimated=value
  t.Offers[key]=offer
  t.Version+=1;t.Ready={};t.Confirmed={};t.ConfirmAfter=nil;t.UpdatedAt=now
  return changed("Offer updated")
 elseif action=="Ready" then
  R.Check(a.Version==t.Version,"Offer changed; review it again")
  local mine,theirs=t.Offers[key],t.Offers[tostring(other)]
  R.Check(mine and theirs and (#mine.Dogs+#mine.Items+#theirs.Dogs+#theirs.Items+mine.Cash+theirs.Cash)>0,"Add something to the trade first")
  R.Check(now-(t.UpdatedAt or 0)>=TradeRules.ReviewSeconds,"Review the newest offer for a moment before locking")
  local first,second=self:Get(t.Users[1]),self:Get(t.Users[2])
  if first and second then
   I.Normalize(first);I.Normalize(second)
   local owner,kind=capacityProblem(t.Users,{first,second},{t.Offers[tostring(t.Users[1])],t.Offers[tostring(t.Users[2])]})
   if owner then error(fullMessage(owner,kind,id),0)end
  end
  t.Ready[key]=true;t.Confirmed={}
  if both(t,t.Ready) and not t.ConfirmAfter then t.ConfirmAfter=now+TradeRules.ConfirmDelay end
  return changed(both(t,t.Ready)and"Both ready. Confirm when the countdown ends"or"Ready. Waiting for your partner")
 elseif action=="Unready" then
  t.Ready[key]=nil;t.Confirmed={};t.ConfirmAfter=nil
  return changed("You are no longer ready")
 elseif action=="Confirm" then
  R.Check(a.Version==t.Version,"Offer changed; review it again")
  R.Check(both(t,t.Ready),"Both players must press READY first")
  R.Check(t.ConfirmAfter and now>=t.ConfirmAfter,"Safety countdown is still running")
  t.Confirmed[key]=true
  if not both(t,t.Confirmed) then return changed("Confirmed. Waiting for your partner")end
  local version=t.Version
  local hasPaid=false;for _,offer in pairs(t.Offers)do for _,asset in pairs(offer.Details)do if asset.PaidRandom then hasPaid=true end end end
  R.Check(not hasPaid or (PaidPolicy.Allowed(t.Users[1])and PaidPolicy.Allowed(t.Users[2])),'Paid-item trading is unavailable for a participant')
  -- The policy lookup can yield: commit only the exact offers both players confirmed.
  R.Check(self.Trades[t.Id]==t and not t.Committing and t.Version==version and both(t,t.Confirmed),"Offer changed; review it again")
  local ok,result=self:_commitTrade(t)
  if ok then
   self:_endTrade(t,'Completed',id,{Offers=R.Copy(t.Offers)})
   if type(result)~='table'then result={Message=tostring(result)}end
   result.CompletedWith=other
   return result
  end
  -- Nothing moved: both players review again.
  t.Ready={};t.Confirmed={};t.ConfirmAfter=nil;t.Seq=(t.Seq or 0)+1
  local kind,owner=tostring(result):match('^TRADE_FULL:(%a+):(%-?%d+)$')
  local function say(viewer)return kind and fullMessage(tonumber(owner),kind,viewer)or tostring(result)end
  self:_tradeEvent({other},{Kind='Failed',Trade=t.Id,By=id,Message=say(other)})
  self:_tradeEvent({id},{Kind='Failed',Trade=t.Id,By=id,Message=say(id)})
  error(say(id),0)
 end
 error("Invalid trade action",0)
end
-- RAM-only: hands this profile's pending record checks to the server batch.
-- Server-session records are decided here against the in-memory server book;
-- global records are merged by Runtime.FlushRecords with one UpdateAsync per depth.
-- options go to Tx:Run: the economy loop passes {Timeout=0}, so a profile whose lock is held
-- (a Robux receipt waiting on DataStore) is retried next pass instead of stalling every tick.
function E:Records(id,serverBook,options)
 local profile=self:Get(id);if not profile then return true,{Jobs={},Server={}}end
 I.Normalize(profile)
 if not next(profile.RecordJobs)then return true,{Jobs={},Server={}}end
 serverBook=serverBook or {}
 return self.Tx:Run({pk(id)},function(v)
  local p=v[pk(id)];I.Normalize(p);self:Authorize(p,id)
  local jobs,server={},{}
  for itemId,x in pairs(p.RecordJobs)do
   local depth=x.Depth;local mine=server[depth];local book=serverBook[depth]
   local previous=(mine and mine[itemId])or(book and book[itemId])
   if not previous or x.WeightKg>previous.WeightKg then
    server[depth]=mine or {}
    server[depth][itemId]={WeightKg=x.WeightKg,ItemUid=x.ItemUid,Finder=x.OriginalFinderUserId,At=x.FoundAt}
    x.RecordAtCreation=x.RecordAtCreation or {};x.RecordAtCreation.Server=true
    local held=p.Items[x.ItemUid]
    if held then held.RecordAtCreation=held.RecordAtCreation or {};held.RecordAtCreation.Server=true end
   end
   jobs[itemId]=R.Copy(x);p.RecordJobs[itemId]=nil
  end
  return {Jobs=jobs,Server=server}
 end,nil,options)
end
return E
