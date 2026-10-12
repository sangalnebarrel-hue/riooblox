-- The single owner of MarketplaceService.ProcessReceipt, and the game-pass entitlement sync.
--
-- Developer products: every catalog that sells them is registered once (RegisterCatalog) and
-- indexed by product ID at startup. Rows that share an ID are one product only when they are
-- the same offer and its aliases (Alias = the primary's Key); the receipt then grants the
-- primary. Unknown or genuinely ambiguous IDs are never guessed: they stay pending and are
-- reported loudly (startup audit + every receipt).
--
-- A receipt is ONE durable transaction on {p:<buyer>, purchase:<PurchaseId>}: the grant, the
-- TOP SUPPORTERS total (Lifetime.SupportRobux) and the purchase mark are written together, so
-- a re-delivered receipt can never grant twice and a granted one is never left uncounted.
-- PurchaseGranted is returned only after that transaction is saved. Before it runs, the
-- receipt waits (bounded) for the buyer's profile to load, and receipts of one player run one
-- at a time. Every decision is logged with its reason ("[DOGROTS receipt] ...").
--
-- Studio test without Robux (server command bar, Play mode):
--   game.ServerStorage.DOGROTS_HandleReceipt:Invoke({PlayerId=<id>,ProductId=<id>,
--     PurchaseId='studio-1',CurrencyType=Enum.CurrencyType.Robux,CurrencySpent=67})
-- (or require(game.ServerScriptService.Economy.PurchaseService).HandleReceipt{...} from a
-- server script). Docs: docs/PAYMENTS.md.
local Marketplace=game:GetService('MarketplaceService');local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage');local RunService=game:GetService('RunService')
local Definitions=require(script.Parent.ShopDefinitions);local R=require(script.Parent.Rules)
local Lifetime=require(script.Parent.LifetimeStats)
local Support=require(script.Parent.SupportReceipts)
local Commerce=require(script.Parent.CommerceProducts)
local TicketPurchases=require(script.Parent.RoulettePurchases)
local MAX_ID=9007199254740990
local Service={Catalogs={},PassCatalogs={},Handlers={},Queues={},Log={},Runtime=nil::any,Index=nil::any,Started=false,
 -- Seconds a receipt may wait: for the buyer's profile to load, for this player's earlier
 -- receipts, and for the profile lock inside the transaction.
 ProfileWait=60,QueueWait=60,LockWait=45,
 -- Back-off between UserOwnsGamePassAsync attempts (seconds x attempt).
 PassRetryDelay=1.5}

local function present(player,payload)
 local remote=RS:FindFirstChild('RewardPresentation')
 if remote and player.Parent then remote:FireClient(player,payload)end
end
local function loud(message)
 warn(message)
 -- Make configuration errors impossible to miss while testing in Studio.
 if RunService:IsStudio()then task.spawn(error,message,0)end
end

-- ===== Catalogs and the product index =====
-- catalog = {Kind, Source, Rows=function()->list, Filter=function(row)->is a product row?,
--            Sold=function(row)->offered for sale now? (audit only)}
-- handler = {Record=<purchase record Kind>, Grant=function(p,product,context)->result,
--            After=function(runtime,player,product,result,outcome)}  (After runs after the save)
-- Adding a future catalog (e.g. Robux cases) is one call to RegisterCatalog.
function Service.RegisterCatalog(catalog,handler)
 assert(type(catalog)=='table'and type(catalog.Kind)=='string'and type(catalog.Rows)=='function','Invalid catalog')
 table.insert(Service.Catalogs,catalog)
 if handler then Service.Handlers[catalog.Kind]=handler end
 Service.Index=nil
end
Service.RegisterCatalog({Kind='Commerce',Source='CommerceConfig',
 Rows=function()return require(RS.CommerceConfig).Products end,Sold=function(r)return r.Enabled==true end},
 {Record='Commerce',Grant=Commerce.Grant,After=Commerce.After})
Service.RegisterCatalog({Kind='Tickets',Source='RewardMachineConfig',
 Rows=function()return require(RS.RewardMachineConfig).TicketProducts or {}end,Sold=function(r)return r.Enabled==true end},
 {Record='RouletteTickets',Grant=TicketPurchases.Grant,After=TicketPurchases.After})
Service.RegisterCatalog({Kind='Block',Source='LuckyBlockConfig',
 Rows=function()return require(RS.LuckyBlockConfig).RobuxProducts or {}end},
 {Record='Block',
  Grant=function(p,product)
   require(script.Parent.LuckyLifecycle).AddStored(p,product.Tier,product.Count,'Purchase',true)
   return {Message='Lucky Blocks added to Inventory',Tier=product.Tier,Count=product.Count}
  end,
  After=function(_,player,product)present(player,{Credits=true,Tier=product.Tier,Count=product.Count})end})
Service.RegisterCatalog({Kind='Cosmetic',Source='ShopDefinitions',
 Rows=function()return Definitions end,Filter=function(r)return r.Kind=='Product'end},
 {Record='Cosmetic',
  Grant=function(p,product)
   local reward=product.Rewards
   -- This catalog grants guaranteed cosmetics.
   R.Check(reward and type(reward.Cosmetic)=='string','Invalid product reward')
   p.Cosmetics=type(p.Cosmetics)=='table'and p.Cosmetics or {};p.Cosmetics[reward.Cosmetic]=true
   return {Message=tostring(product.Name or reward.Cosmetic)..' unlocked'}
  end,
  After=function(_,player,_,result)present(player,{Cue='Reward',Message=type(result)=='table'and result.Message or nil})end})
-- Feature catalogs: an Economy.Features module that sells developer products exports
-- Catalogs(register) and is registered here, at load, before Start builds the index
-- (Features.Equipment: Robux case keys).
for _,feature in ipairs(R.Features and R.Features.Modules or {})do
 if type(feature.Catalogs)=='function'then
  local ok,err=pcall(feature.Catalogs,Service.RegisterCatalog)
  if not ok then warn('[DOGROTS commerce] catalog of feature '..tostring(feature.Name)..' failed: '..tostring(err))end
 end
end
-- Game passes (none configured today: every Kind='Pass' row has Id=0).
table.insert(Service.PassCatalogs,{Source='ShopDefinitions',Rows=function()return Definitions end,Filter=function(r)return r.Kind=='Pass'end})

local function same(a,b)
 if type(a)~='table'or type(b)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
function Service.BuildIndex()
 local byId,problems,notes={},{},{}
 for _,catalog in ipairs(Service.Catalogs)do
  local ok,rows=pcall(catalog.Rows)
  if not ok or type(rows)~='table'then
   table.insert(problems,'catalog '..tostring(catalog.Source)..' could not be read: '..tostring(rows));rows={}
  end
  for _,row in ipairs(rows)do
   if type(row)=='table'and R.Int(row.Id,1,MAX_ID)and(not catalog.Filter or catalog.Filter(row))then
    local entry=byId[row.Id]or{Id=row.Id,Rows={}};byId[row.Id]=entry
    table.insert(entry.Rows,{Row=row,Kind=catalog.Kind,Source=catalog.Source,Sold=catalog.Sold==nil or catalog.Sold(row)==true})
   end
  end
 end
 for id,entry in pairs(byId)do
  local first=entry.Rows[1]
  if #entry.Rows==1 then
   entry.Product,entry.Kind,entry.Source=first.Row,first.Kind,first.Source
  else
   local canon=first.Row.Alias or first.Row.Key;local one=canon~=nil
   for _,r in ipairs(entry.Rows)do
    if r.Kind~=first.Kind or r.Source~=first.Source or(r.Row.Alias or r.Row.Key)~=canon then one=false end
   end
   if one then
    local primary=first
    for _,r in ipairs(entry.Rows)do if r.Row.Key==canon and not r.Row.Alias then primary=r end end
    entry.Product,entry.Kind,entry.Source,entry.Aliases=primary.Row,primary.Kind,primary.Source,{}
    for _,r in ipairs(entry.Rows)do if r~=primary then
     table.insert(entry.Aliases,tostring(r.Row.Key))
     if not same(r.Row.Rewards,primary.Row.Rewards)or r.Row.Supply~=primary.Row.Supply or r.Row.Seconds~=primary.Row.Seconds then
      table.insert(notes,('%s.%s has the same product ID %d as %s but different rewards; receipts grant %s'):format(r.Source,tostring(r.Row.Key),id,tostring(primary.Row.Key),tostring(primary.Row.Key)))
     end
    end end
    table.insert(notes,('product ID %d: %s.%s (aliases %s resolve to it)'):format(id,primary.Source,tostring(primary.Row.Key),table.concat(entry.Aliases,', ')))
   else
    local names={}
    for _,r in ipairs(entry.Rows)do table.insert(names,r.Source..'.'..tostring(r.Row.Key))end
    entry.Ambiguous=true
    entry.Problem=('product ID %d is shared by different offers: %s'):format(id,table.concat(names,', '))
    table.insert(problems,entry.Problem)
   end
  end
 end
 Service.Index={ById=byId,Problems=problems,Notes=notes}
 return Service.Index
end
function Service.Resolve(productId)
 local index=Service.Index or Service.BuildIndex()
 return index.ById[productId]
end
-- Is any (id=nil) or this developer product ID resolvable to a grant?
function Service.Configured(id)
 local index=Service.Index or Service.BuildIndex()
 if id==nil then
  for _,entry in pairs(index.ById)do if not entry.Ambiguous then return true end end
  return false
 end
 local entry=index.ById[id]
 return entry~=nil and not entry.Ambiguous
end

-- ===== Receipts =====
local function validReceipt(receipt)
 return type(receipt)=='table'and R.Int(receipt.PlayerId,1,MAX_ID)and R.Int(receipt.ProductId,1,MAX_ID)
  and type(receipt.PurchaseId)=='string'and #receipt.PurchaseId>0 and #receipt.PurchaseId<=100
  and receipt.CurrencyType==Enum.CurrencyType.Robux and R.Int(receipt.CurrencySpent,0,9000000000000000)
end
local function profileLoaded(runtime,player)
 if runtime.Closing then return false end
 if type(runtime.Loaded)=='table'then return runtime.Loaded[player.UserId]==true end
 return runtime.Ready(player)==true
end
-- Roblox re-delivers a pending receipt mostly when the buyer joins, exactly while the profile
-- is still loading: wait for it instead of failing at once.
local function waitForProfile(runtime,player)
 local deadline=os.clock()+Service.ProfileWait
 while not profileLoaded(runtime,player)do
  if runtime.Closing then return false,'server is shutting down; Roblox retries on the next server'end
  if not player.Parent then return false,'buyer left before their profile loaded; Roblox retries when they join'end
  if os.clock()>=deadline then return false,'profile did not load within '..Service.ProfileWait..' s'end
  task.wait(.5)
 end
 return true
end
-- One receipt per player at a time, first come first served.
local function enterQueue(uid)
 local q=Service.Queues[uid]
 if not q then q={Next=0,Serving=1,Gone={}};Service.Queues[uid]=q end
 q.Next+=1;local ticket=q.Next
 local deadline=os.clock()+Service.QueueWait
 while q.Serving~=ticket do
  if os.clock()>=deadline then q.Gone[ticket]=true;return nil end
  task.wait(.1)
 end
 return ticket
end
local function leaveQueue(uid,ticket)
 local q=Service.Queues[uid]
 if not q or q.Serving~=ticket then return end
 q.Serving+=1
 while q.Gone[q.Serving]do q.Gone[q.Serving]=nil;q.Serving+=1 end
 if q.Serving>q.Next then Service.Queues[uid]=nil end
end

-- Grants one resolved receipt. Returns decision ('GRANTED'|'PENDING'), reason, loud.
function Service.Grant(runtime,player,entry,receipt)
 local handler=Service.Handlers[entry.Kind]
 if not handler then return 'PENDING','no grant handler for '..tostring(entry.Kind),true end
 local uid=player.UserId;local pkey='p:'..uid;local rkey='purchase:'..receipt.PurchaseId
 local product=entry.Product;local amount=receipt.CurrencySpent;local now=os.time()
 local outcome=nil
 local ok,result=runtime.Tx:Run({pkey,rkey},function(v)
  outcome=nil
  local old=v[rkey]
  if old~=nil then
   -- Already granted (by this code, the old code, or another server): never again.
   R.Check(type(old)=='table'and old.User==uid and old.Product==product.Id,'Receipt mismatch')
   outcome={Fresh=false,Counted=old.Counted==true}
   if old.Result~=nil then return old.Result end
   return 'Already granted'
  end
  local p=v[pkey];runtime.Engine:Authorize(p,uid)
  p=R.Normalize(p,uid,now);v[pkey]=p
  -- A broken invariant elsewhere in the profile must not block a paid grant forever; the
  -- grant itself is still validated whenever the profile was valid before it.
  local wasValid,invalid=pcall(R.Validate,p)
  local granted=handler.Grant(p,product,{Now=now,PurchaseId=receipt.PurchaseId,Player=player,Receipt=receipt})
  Lifetime.Add(p,'SupportRobux',amount)
  if wasValid then R.Validate(p)end
  v[rkey]={Kind=handler.Record or entry.Kind,User=uid,Product=product.Id,Key=product.Key,At=now,Result=granted,Amount=amount,Counted=true}
  outcome={Fresh=true,Counted=true,Invalid=not wasValid and tostring(invalid)or nil}
  return granted
 end,nil,{Timeout=Service.LockWait})
 if not ok then return 'PENDING','grant transaction failed: '..tostring(result),true end
 outcome=outcome or{Fresh=false,Counted=true}
 -- Legacy receipts (granted by the old code, never acknowledged) still need their count.
 if not outcome.Counted and not Support.Record(runtime,receipt)then
  return 'PENDING','granted earlier; legacy supporter total still pending',true
 end
 local shown,showError=pcall(function()if handler.After then handler.After(runtime,player,product,result,outcome)end end)
 if not shown then warn('[DOGROTS receipt] presentation failed (the grant is saved):',showError)end
 local refreshed,refreshError=pcall(runtime.Refresh,player)
 if not refreshed then warn('[DOGROTS receipt] refresh failed (the grant is saved):',refreshError)end
 local what=entry.Source..'.'..tostring(product.Key)
 if not outcome.Fresh then return 'GRANTED','already granted earlier: '..what end
 return 'GRANTED','granted '..what..(outcome.Invalid and(' (profile had an earlier validation issue: '..outcome.Invalid..')')or'')
end
function Service.Decide(receipt)
 local runtime=Service.Runtime
 if not runtime then return 'PENDING','economy has not started yet',true end
 if not validReceipt(receipt)then return 'PENDING','invalid receipt fields',true end
 local entry=Service.Resolve(receipt.ProductId)
 if not entry then return 'PENDING','unknown product ID: it is in no catalog (add it to the config; never delete a sold ID)',true end
 if entry.Ambiguous then return 'PENDING',entry.Problem..'; fix the config so the ID resolves to one grant',true end
 local player=Players:GetPlayerByUserId(receipt.PlayerId)
 if not player then return 'PENDING','buyer is not in this server; Roblox retries when they join'end
 local loaded,why=waitForProfile(runtime,player)
 if not loaded then return 'PENDING',why end
 local uid=player.UserId
 local ticket=enterQueue(uid)
 if not ticket then return 'PENDING','earlier receipts of this player are still running'end
 local ok,decision,reason,isLoud=pcall(Service.Grant,runtime,player,entry,receipt)
 leaveQueue(uid,ticket)
 if not ok then return 'PENDING','grant error: '..tostring(decision),true end
 return decision,reason,isLoud
end
local function remember(receipt,decision,reason)
 table.insert(Service.Log,1,{At=os.time(),Decision=decision,Reason=reason,PlayerId=receipt.PlayerId,ProductId=receipt.ProductId,PurchaseId=receipt.PurchaseId})
 while #Service.Log>50 do table.remove(Service.Log)end
end
-- The ProcessReceipt callback (also callable directly for tests). Never throws.
function Service.HandleReceipt(receipt)
 local ok,decision,reason,isLoud=pcall(Service.Decide,receipt)
 if not ok then decision,reason,isLoud='PENDING','handler error: '..tostring(decision),true end
 local info=type(receipt)=='table'and receipt or {}
 local line=('[DOGROTS receipt] %s · player %s · product %s · purchase %s · %s'):format(
  decision,tostring(info.PlayerId),tostring(info.ProductId),tostring(info.PurchaseId),tostring(reason))
 if isLoud then warn(line)else print(line)end
 pcall(remember,info,decision,reason)
 if decision=='GRANTED'then return Enum.ProductPurchaseDecision.PurchaseGranted end
 return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ===== Game passes: ownership is an entitlement, never a one-time grant =====
function Service.PassList()
 local list,seen={},{}
 for _,catalog in ipairs(Service.PassCatalogs)do
  local ok,rows=pcall(catalog.Rows)
  for _,row in ipairs(ok and type(rows)=='table'and rows or {})do
   if type(row)=='table'and R.Int(row.Id,1,MAX_ID)and(not catalog.Filter or catalog.Filter(row))and not seen[row.Id]then
    seen[row.Id]=true;table.insert(list,{Id=row.Id,Row=row,Source=catalog.Source})
   end
  end
 end
 return list
end
-- true/false when Roblox answered, nil when it could not be asked (never counts as "not owned").
local function ownsPass(userId,passId)
 for attempt=1,3 do
  local ok,owns=pcall(function()return Marketplace:UserOwnsGamePassAsync(userId,passId)end)
  if ok then return owns==true end
  if attempt<3 then task.wait(attempt*Service.PassRetryDelay)end
 end
 return nil
end
-- Sets p.Passes[tostring(id)]=true (idempotent, never removed) and applies the benefits.
function Service.GrantPasses(runtime,player,ids)
 if #ids==0 then return true,0 end
 local key='p:'..player.UserId
 local ok,result=runtime.Tx:Run({key},function(v)
  local p=v[key];runtime.Engine:Authorize(p,player.UserId)
  p.Passes=type(p.Passes)=='table'and p.Passes or {}
  local added=0
  for _,id in ipairs(ids)do local k=tostring(id);if p.Passes[k]~=true then p.Passes[k]=true;added+=1 end end
  require(script.Parent.Features.Passes).Apply(p)
  return added
 end,nil,{Timeout=30})
 if ok then
  pcall(runtime.Refresh,player)
  if (tonumber(result)or 0)>0 then print(('[DOGROTS passes] %d game pass entitlement(s) saved for player %d'):format(result,player.UserId))end
 else warn('[DOGROTS passes] entitlement save deferred for player',player.UserId,result)end
 return ok,result
end
function Service.SyncPasses(runtime,player,onlyId)
 local owned={}
 for _,pass in ipairs(Service.PassList())do
  if onlyId==nil or pass.Id==onlyId then
   local owns=ownsPass(player.UserId,pass.Id)
   if owns then table.insert(owned,pass.Id)
   elseif owns==nil then warn('[DOGROTS passes] could not check pass',pass.Id,'for player',player.UserId,'(kept as is; retried next join)')end
  end
 end
 return Service.GrantPasses(runtime,player,owned)
end

function Service.Start(runtime)
 if Service.Started then return end;Service.Started=true;Service.Runtime=runtime
 local index=Service.BuildIndex()
 -- One receipt callback owns every developer product in this experience.
 Marketplace.ProcessReceipt=Service.HandleReceipt
 Marketplace.PromptGamePassPurchaseFinished:Connect(function(player,passId,purchased)
  if not purchased then return end
  task.spawn(function()
   local known=false
   for _,pass in ipairs(Service.PassList())do if pass.Id==passId then known=true end end
   if not known then warn('[DOGROTS passes] purchased pass',passId,'is not configured in any pass catalog');return end
   if not waitForProfile(runtime,player)then return end
   -- The server-side purchase event is Roblox's own confirmation; the join sync re-checks.
   Service.GrantPasses(runtime,player,{passId})
  end)
 end)
 local function added(player)
  task.spawn(function()
   if not waitForProfile(runtime,player)then return end
   local passes=#Service.PassList()>0
   if passes then pcall(Service.SyncPasses,runtime,player)end
   -- Paid server luck saved in the profile (queued, or interrupted by a shutdown) restarts here.
   local ok,err=pcall(require(script.Parent.ServerLuck).ActivateFor,runtime,player)
   if not ok then warn('[DOGROTS commerce] server luck credits deferred:',err)end
  end)
 end
 Players.PlayerAdded:Connect(added);for _,p in ipairs(Players:GetPlayers())do added(p)end
 if RunService:IsStudio()then
  -- Studio-only test hook (ServerStorage never replicates; live servers never create it).
  local storage=game:GetService('ServerStorage')
  local hook=storage:FindFirstChild('DOGROTS_HandleReceipt')or Instance.new('BindableFunction')
  hook.Name='DOGROTS_HandleReceipt';hook.OnInvoke=Service.HandleReceipt;hook.Parent=storage
 end
 for _,problem in ipairs(index.Problems)do loud('[DOGROTS commerce] ERROR: '..problem..' - receipts for it stay pending until fixed')end
 task.spawn(Service.Audit)
end
-- Startup self-check (Output only): every sold product ID must exist, be on sale, belong to
-- this experience and resolve to exactly one grant.
function Service.Audit()
 local index=Service.Index or Service.BuildIndex()
 for _,note in ipairs(index.Notes)do print('[DOGROTS commerce] '..note)end
 local ids={}
 for id,entry in pairs(index.ById)do
  local sold=false
  for _,r in ipairs(entry.Rows)do if r.Sold then sold=true end end
  if sold then table.insert(ids,id)end
 end
 table.sort(ids)
 -- GetProductInfoAsync alone does not prove that the product belongs to THIS game.
 -- GetDeveloperProductsAsync lists products registered to the current experience.
 local owned,ownedNames=nil,{}
 do
  local pageOk,pages=pcall(function()return Marketplace:GetDeveloperProductsAsync()end)
  if pageOk then
   local found={}
   local scanOk,scanError=pcall(function()
    while true do
     for _,item in ipairs(pages:GetCurrentPage())do
      local id=tonumber(item.ProductId or item.Id)
      if id then found[id]=true;ownedNames[id]=item.Name end
     end
     if pages.IsFinished then break end
     pages:AdvanceToNextPageAsync()
    end
   end)
   if scanOk then owned=found
   else warn('[DOGROTS commerce] Could not scan Developer Products of this experience: '..tostring(scanError))end
  else warn('[DOGROTS commerce] Could not list Developer Products of this experience: '..tostring(pages))end
 end
 local bad=0
 for _,id in ipairs(ids)do
  local entry=index.ById[id];local key=entry.Ambiguous and ('ID '..id)or(entry.Source..'.'..tostring(entry.Product.Key))
  local invalid=entry.Ambiguous==true
  if owned and not owned[id]then
   invalid=true
   loud(('[DOGROTS commerce] %s: product %d is NOT registered in this Experience. Create or copy the right Developer Product ID in Creator Hub.'):format(key,id))
  end
  local ok,info=pcall(function()return Marketplace:GetProductInfoAsync(id,Enum.InfoType.Product)end)
  if not ok or type(info)~='table'then
   invalid=true
   warn(('[DOGROTS commerce] %s: product %d not found or lookup failed (%s)'):format(key,id,tostring(info)))
  elseif info.IsForSale==false then
   invalid=true
   warn(('[DOGROTS commerce] %s: product %d (%s) is not for sale'):format(key,id,tostring(info.Name)))
  elseif not entry.Ambiguous and type(entry.Product.Robux)=='number'and info.PriceInRobux~=entry.Product.Robux then
   print(('[DOGROTS commerce] %s: Roblox price R$%s (config note says %d); buyers pay the Roblox price'):format(key,tostring(info.PriceInRobux),entry.Product.Robux))
  end
  if invalid then bad+=1 end
  task.wait(.2)
 end
 -- Products sold in Creator Hub but missing from every catalog can never be granted.
 if owned then
  for id in pairs(owned)do
   if not index.ById[id]then
    loud(('[DOGROTS commerce] Creator Hub product %d (%s) is in no catalog: its receipts stay pending. Add it to a config (keep retired IDs with Enabled=false).'):format(id,tostring(ownedNames[id])))
   end
  end
 end
 print(('[DOGROTS commerce] %d/%d products passed available checks'):format(#ids-bad,#ids))
 if not owned then warn('[DOGROTS commerce] Experience ownership was NOT verified: review Creator Hub > Monetization > Developer Products')end
end
return Service
