local Players=game:GetService("Players")
local DataStoreService=game:GetService("DataStoreService")
local Http=game:GetService("HttpService")
local Run=game:GetService("RunService")
local Replicated=game:GetService("ReplicatedStorage")
local Storage=game:GetService("ServerStorage")
local Tx=require(script.Parent.Transactions)
local Engine=require(script.Parent.Engine)
local Rules=require(script.Parent.Rules)
local Config=require(script.Parent.Config)
local I=require(script.Parent.ItemRules)
local Messaging=game:GetService('MessagingService')
local Definitions=require(script.Parent.DogDefinitions)
local Offline=require(script.Parent.OfflineEarnings)
local Runtime={Loaded={},Views={},Closing=false,Push=nil::RemoteEvent?}
local session=Http:GenerateGUID(false)
local rng=Random.new()
local function guid()return Http:GenerateGUID(false):gsub('%-','')end
local memory=Run:IsStudio() and game.GameId==0
local store={Data={}}
if memory then
 warn('DOGROTS: LOCAL STUDIO PREVIEW. Persistence uses memory because this place is unpublished. Live servers NEVER fall back to memory.')
 function store:Read(k)return Rules.Copy(self.Data[k])end
 function store:Update(k,fn)local v=fn(Rules.Copy(self.Data[k]));if v~=nil then self.Data[k]=Rules.Copy(v)end;return Rules.Copy(v)end
else
 local db=require(script.Parent.StoreKeys).Wrap(DataStoreService:GetDataStore('DOGROTS_ECONOMY_V1'))
 local options=Instance.new('DataStoreGetOptions');options.UseCache=false
 local function retry(fn)
  local errorMessage
  for attempt=1,3 do local ok,value=pcall(fn);if ok then return value end;errorMessage=value;task.wait(attempt*.6) end
  error('DataStore unavailable: '..tostring(errorMessage))
 end
 function store:Read(k)return retry(function()return db:GetAsync(k,options)end)end
 function store:Update(k,fn)
  return retry(function()return db:UpdateAsync(k,function(v)
   local nextValue=fn(v)
   if nextValue and #Http:JSONEncode(nextValue)>3500000 then error('Record capacity exceeded')end
   return nextValue
  end)end)
 end
end
local supplyBatch,supplyLimit={},{}
for id,d in pairs(Definitions)do
 local key='supply:'..id;local limit=math.max(0,tonumber(d.LimitedSupply)or 0);supplyLimit[key]=limit
 if limit>0 then supplyBatch[key]=1 elseif d.SupplyType=='Permanent'then supplyBatch[key]=32 else supplyBatch[key]=8 end
end
Runtime.Tx=Tx.new(store,os.time,guid,{
 SupplyBatch=function(key)return supplyBatch[key]or 8 end,
 SupplyLimit=function(key)return supplyLimit[key]or 0 end,
})
Runtime.PendingEvents={}
function Runtime.AccumulateEvent(amount)
 amount=math.max(0,math.floor(tonumber(amount)or 0));if amount==0 then return Runtime.EventTotal or 0 end
 local key='event:'..Rules.Week(os.time());Runtime.PendingEvents[key]=(Runtime.PendingEvents[key]or 0)+amount
 Runtime.EventTotal=(Runtime.EventTotal or 0)+amount;return Runtime.EventTotal
end
function Runtime.FlushEvents()
 for key,delta in pairs(Runtime.PendingEvents)do if delta>0 then
  Runtime.PendingEvents[key]=math.max(0,(Runtime.PendingEvents[key]or 0)-delta)
  local ok,value=pcall(function()return Runtime.Tx:AddCounter(key,'Total',delta)end)
  if ok then
   if key=='event:'..Rules.Week(os.time())then Runtime.EventTotal=(value.Total or 0)+(Runtime.PendingEvents[key]or 0)end
  else Runtime.PendingEvents[key]=(Runtime.PendingEvents[key]or 0)+delta;warn('DOGROTS global dig batch deferred:',value)end
 end end
end
Runtime.Engine=Engine.new(Runtime.Tx,{Now=os.time,Guid=guid,Random=function()return rng:NextNumber()end,Session=session,
 Connected=function(id)local p=Players:GetPlayerByUserId(id);return p~=nil and not Runtime.Closing and not p:GetAttribute('EconomyLeaving')end,
 AssetReady=function(id)local d=Definitions[id];local template=d and Storage.DogTemplates:FindFirstChild(d.VisualAsset);return template and template:IsA('Model') and template:FindFirstChild('RootPart',true)~=nil end})
-- Market deliveries for players on other servers land in their inbox; ping their server.
local INBOX_TOPIC='DOGROTS_INBOX_V1'
Runtime.Engine.Market.OnInbox=function(ids)
 if memory then return end
 for _,id in ipairs(ids)do task.spawn(function()pcall(function()Messaging:PublishAsync(INBOX_TOPIC,{UserId=id,Source=session})end)end)end
end
local function folder(parent,name,class)
 local f=parent:FindFirstChild(name);if not f then f=Instance.new(class or 'Folder');f.Name=name;f.Parent=parent end;return f
end

-- Mining state for the client UI and for ServerScriptService.MiningWorld (which mirrors it onto the
-- yard's MiningCorner for every player). MiningRevision changes last, once per real change.
local miningSignatures=setmetatable({},{__mode='k'})
local function projectMining(player,p)
 local m=type(p.Mining)=='table'and p.Mining or{}
 local ore=(Config.Mining and Config.Mining.Ores or{})[tonumber(m.OreIndex)or 1]
 local values={
  MiningStrength=tonumber(m.Strength)or 0,MiningPickaxe=tonumber(m.PickaxeLevel)or 0,MiningPickaxeOwned=tonumber(m.PickaxeOwned)or 0,
  MiningWeight=tonumber(m.WeightLevel)or 0,MiningWeightOwned=tonumber(m.WeightOwned)or 0,MiningOreIndex=tonumber(m.OreIndex)or 1,
  MiningOreId=ore and ore.Id or'Limestone',MiningOreName=ore and(ore.Name or ore.Id)or'Ore',MiningOreHP=tonumber(m.OreHP)or 0,
  MiningOreMaxHP=tonumber(m.OreMaxHP)or 1,MiningOreValue=tonumber(m.OreValue)or 0,MiningOreSerial=tonumber(m.OreSerial)or 1,
  MiningHitSerial=tonumber(m.Hits)or 0,MiningOresBroken=tonumber(m.OresBroken)or 0,MiningCoinsEarned=tonumber(m.CoinsEarned)or 0,
  MiningLastPayout=tonumber(m.LastPayout)or 0,MiningLastDamage=tonumber(m.LastDamage)or 0,MiningLastQuality=tonumber(m.LastQuality)or 1,
  MiningLastBreak=m.LastBreak==true,MiningLastCrit=m.LastCrit==true,MiningCombo=tonumber(m.Combo)or 0,
  MiningBrokenId=type(m.LastBrokenId)=='string'and m.LastBrokenId or'',MiningBrokenValue=tonumber(m.LastBrokenValue)or 0,
  MiningTrainingReps=tonumber(m.TrainingReps)or 0,MiningActiveUntil=tonumber(m.ActiveUntil)or 0,MiningTrainingUntil=tonumber(m.TrainingUntil)or 0,MiningLayer=Rules.MaxUnlockedLayer(p),
 }
 local parts={}
 for key,value in pairs(values)do player:SetAttribute(key,value);table.insert(parts,key..'='..tostring(value))end
 table.sort(parts);local signature=table.concat(parts,';')
 if miningSignatures[player]~=signature then
  miningSignatures[player]=signature
  player:SetAttribute('MiningRevision',(player:GetAttribute('MiningRevision')or 0)+1)
 end
 -- Stored Stone (p.Resources.Stone) for the mining HUD, the pickaxe market and plot decor.
 local stone=type(p.Resources)=='table'and tonumber(p.Resources.Stone)or 0
 player:SetAttribute('Stone',stone==stone and math.max(0,math.floor(stone))or 0)
end

function Runtime.Project(player,p)
 if not player.Parent or not p then return end
 Rules.UpdateLevel(p)
 Runtime.Views[player.UserId]=p
 local previous=Runtime.SeenFinds or {};Runtime.SeenFinds=previous
 local seen=previous[player.UserId] or {};previous[player.UserId]=seen
 local retained={}
 for _,x in ipairs(p.DiscoveryFeed or {})do retained[x.ItemUid]=true;if not seen[x.ItemUid]then
  seen[x.ItemUid]=true
  if os.time()-x.FoundAt<30 then
   local spawn=require(script.Parent.KennelLootPlacement).Resolve(player,p,x)
   if spawn then local payload=Rules.Copy(x);payload.LootSpawn=spawn;Replicated.DiscoveryReveal:FireClient(player,payload)end
   if (x.TierIndex>=8 or x.Class=='Secret') and os.clock()-(Runtime.LastAnnouncement or -60)>=15 then
    Runtime.LastAnnouncement=os.clock();Replicated.DiscoveryAnnouncement:FireAllClients(x,false)
   end
  end
 end end
 previous[player.UserId]=retained
 local stats=folder(player,'leaderstats');folder(stats,'Coins','IntValue').Value=p.Cash
 folder(player,'Bones','IntValue').Value=p.Bones
 local inv=folder(player,'DogInventory')
 for _,entry in ipairs(inv:GetChildren())do if not p.Dogs[entry.Name] then entry:Destroy()end end
 for uid,d in pairs(p.Dogs)do
  local entry=folder(inv,uid,'StringValue');entry.Value=d.DisplayName
  for key,value in pairs(d)do
   if type(value)=='string' or type(value)=='number' or type(value)=='boolean' then entry:SetAttribute(key,value)end
  end
  entry:SetAttribute('OwnerHistory',Http:JSONEncode(d.OwnerHistory))
 end
 local levelFloor=Config.XPForLevel(p.Level);local nextFloor=Config.XPForLevel(math.min(Config.MaxLevel,p.Level+1))
  player:SetAttribute('Level',p.Level);player:SetAttribute('XP',math.max(0,p.XP-levelFloor));player:SetAttribute('XPRequired',p.Level>=Config.MaxLevel and 0 or math.max(1,nextFloor-levelFloor));player:SetAttribute('CurrentLayer',p.CurrentLayer)
 player:SetAttribute('LayerName',Config.Layers[p.CurrentLayer].Name);player:SetAttribute('Bones',p.Bones)
 projectMining(player,p)
 player:SetAttribute('EventTokens',p.EventTokens);player:SetAttribute('WeeklyMeta',Rules.Meta(os.time()))
 player:SetAttribute('GlobalDigTotal',Runtime.EventTotal or 0)
 player:SetAttribute('DogDexCount',Rules.Count(p.DogDex));player:SetAttribute('MuseumDexCount',Rules.MuseumCount(p));player:SetAttribute('DogCapacity',Rules.Capacity(p))
 player:SetAttribute('InventoryCapacity',Rules.Capacity(p));player:SetAttribute('YardLevel',1+(p.Upgrades.Plot or 0))
 player:SetAttribute('EconomyReady',true);player:SetAttribute('PreviewData',memory)
 local tutorial=require(script.Parent.OnboardingRules).View(p)
 player:SetAttribute('TutorialVersion',tutorial.Version);player:SetAttribute('TutorialStep',tutorial.Step)
 player:SetAttribute('TutorialActive',tutorial.Active);player:SetAttribute('TutorialStatus',tutorial.Status)
 player:SetAttribute('TutorialReadyAt',tutorial.ReadyAt)
 local value,count=0,0;for _,s in pairs(p.Loot)do value+=s.Value;count+=s.Count end
 player:SetAttribute('PendingCash',value);player:SetAttribute('LootCount',count)
 -- Dog income (HUD chip, Yard card) and storage state (HUD, kennel labels): one model, Rules.IncomeModel.
 local now=os.time();local storage=Rules.Storage(p,now)
 player:SetAttribute('ItemCount',storage.ItemCount);player:SetAttribute('ItemCapacity',storage.ItemCapacity)
 player:SetAttribute('ItemFull',storage.ItemFull);player:SetAttribute('LootFull',storage.LootFull);player:SetAttribute('LootCapacity',storage.LootCapacity)
 local okIncome,income=pcall(Rules.IncomeModel,p,now,{AssignedOnly=true})
 if okIncome then player:SetAttribute('IncomePerMinute',math.floor(income.PerMinute+.5))else warn('DOGROTS income estimate failed:',income)end
 local available,active=0,0
 for _,b in pairs(p.OwnedBlocks or{})do if b.State=='Placed'or b.State=='Ready'then active+=1 else available+=1 end end
 for _,count in pairs(p.LuckyCredits or{})do available+=math.max(0,count)end
 player:SetAttribute('OwnedBlockCount',available+active);player:SetAttribute('AvailableBlockCount',available);player:SetAttribute('ActiveBlockCount',active)
 for key in pairs(Config.Supplies)do player:SetAttribute('SupplyExpires_'..key,require(script.Parent.SupplyRules).EndAt(p,key))end
 -- Personal luck tiers (LUCK tab) for the buff HUD.
 local luck=require(script.Parent.LuckRules)
 for tier in ipairs(Config.LuckTiers or {})do player:SetAttribute('LuckExpires_'..tier,luck.EndAt(p,tier))end
 player:SetAttribute('InventoryRevision',(player:GetAttribute('InventoryRevision')or 0)+1)
 player:SetAttribute('LatestFoundItem',p.DiscoveryFeed[1] and (p.DiscoveryFeed[1].DisplayName..' · '..string.format('%.4g kg',p.DiscoveryFeed[1].WeightKg)) or 'No finds yet')
 require(script.Parent.PlotDevelopment).Reconcile(player,p)
 if Runtime.Kennels then Runtime.Kennels.Reconcile(player,p)end
 require(script.Parent.PlotShowcase).Reconcile(player,p)
end
function Runtime.Refresh(player)
 if not player or not Runtime.Loaded[player.UserId] then return end
 local ok,p=pcall(function()return Runtime.Engine:Get(player.UserId)end)
 if ok then Runtime.Project(player,p)else warn('DOGROTS refresh deferred:',p)end
end
local function salePatch(p,fast)
 fast=type(fast)=='table'and fast or{}
 local loot=type(fast.Loot)=='table'and fast.Loot or p.Loot or{}
 local pending,lootCount=0,0
 for _,stack in pairs(loot)do pending+=stack.Value or 0;lootCount+=stack.Count or 0 end
 local patch={Cash=tonumber(fast.Cash)or p.Cash,ItemCount=tonumber(fast.ItemCount)or I.Count(p.Items),PendingCash=pending,LootCount=lootCount,Loot=Rules.Copy(loot),XP=tonumber(fast.XP)or p.XP,Level=tonumber(fast.Level)or p.Level}
 if type(fast.SoldUids)=='table'then patch.SoldUids=Rules.Copy(fast.SoldUids)end
 return patch
end
function Runtime.RefreshSale(player,fast)
 if not player or not Runtime.Loaded[player.UserId]then return nil end
 local p=Runtime.Views[player.UserId]
 if not p or type(fast)~='table'then
  local ok,loaded=pcall(function()return Runtime.Engine:Get(player.UserId)end)
  if not ok then warn('DOGROTS sale refresh deferred:',loaded);return nil end
  p=loaded;Runtime.Views[player.UserId]=p;fast={}
 else
  if type(fast.Cash)=='number'then p.Cash=fast.Cash end
  if type(fast.XP)=='number'then p.XP=fast.XP end
  if type(fast.Level)=='number'then p.Level=fast.Level end
  Rules.UpdateLevel(p)
  if type(fast.SoldUids)=='table'then for _,uid in ipairs(fast.SoldUids)do p.Items[uid]=nil end end
  if type(fast.Loot)=='table'then p.Loot=Rules.Copy(fast.Loot)end
  if type(fast.Stats)=='table'then p.Stats=Rules.Copy(fast.Stats)end
  if type(fast.LastSaleAt)=='number'then p.LastSaleAt=fast.LastSaleAt end
 end
 local patch=salePatch(p,fast)
 local stats=folder(player,'leaderstats');folder(stats,'Coins','IntValue').Value=patch.Cash
 player:SetAttribute('PendingCash',patch.PendingCash);player:SetAttribute('LootCount',patch.LootCount)
 local levelFloor=Config.XPForLevel(p.Level);local nextFloor=Config.XPForLevel(math.min(Config.MaxLevel,p.Level+1))
 player:SetAttribute('Level',p.Level);player:SetAttribute('XP',math.max(0,p.XP-levelFloor));player:SetAttribute('XPRequired',p.Level>=Config.MaxLevel and 0 or math.max(1,nextFloor-levelFloor))
 player:SetAttribute('ItemCount',patch.ItemCount)
 player:SetAttribute('InventoryRevision',(player:GetAttribute('InventoryRevision')or 0)+1)
 return patch
end

function Runtime.RefreshMining(player,fast)
 if not player or not Runtime.Loaded[player.UserId]then return nil end
 local p=Runtime.Views[player.UserId]
 if not p or type(fast)~='table'then
  local ok,loaded=pcall(function()return Runtime.Engine:Get(player.UserId)end)
  if not ok then warn('DOGROTS mining refresh deferred:',loaded);return nil end
  p=loaded;Runtime.Views[player.UserId]=p;fast={}
 else
  if type(fast.Cash)=='number'then p.Cash=fast.Cash end
  if type(fast.XP)=='number'then p.XP=fast.XP end
  if type(fast.Level)=='number'then p.Level=fast.Level end
  if type(fast.MiningState)=='table'then p.Mining=Rules.Copy(fast.MiningState)end
  if type(fast.Resources)=='table'then p.Resources=Rules.Copy(fast.Resources)end
  if type(fast.Onboarding)=='table'then p.Onboarding=Rules.Copy(fast.Onboarding)end
 end
 Rules.UpdateLevel(p)
 local stats=folder(player,'leaderstats');folder(stats,'Coins','IntValue').Value=p.Cash
 projectMining(player,p)
 local levelFloor=Config.XPForLevel(p.Level);local nextFloor=Config.XPForLevel(math.min(Config.MaxLevel,p.Level+1))
 player:SetAttribute('Level',p.Level);player:SetAttribute('XP',math.max(0,p.XP-levelFloor));player:SetAttribute('XPRequired',p.Level>=Config.MaxLevel and 0 or math.max(1,nextFloor-levelFloor))
 local tutorial=require(script.Parent.OnboardingRules).View(p)
 player:SetAttribute('TutorialVersion',tutorial.Version);player:SetAttribute('TutorialStep',tutorial.Step);player:SetAttribute('TutorialActive',tutorial.Active);player:SetAttribute('TutorialStatus',tutorial.Status)
 return {Cash=p.Cash,Mining=Rules.Copy(p.Mining),Level=p.Level,XP=math.max(0,p.XP-levelFloor),XPRequired=p.Level>=Config.MaxLevel and 0 or math.max(1,nextFloor-levelFloor)}
end

function Runtime.RefreshAll()for _,p in ipairs(Players:GetPlayers())do Runtime.Refresh(p)end end
Runtime.Draining={}
-- Applies market results that other servers left for this player (see Market inbox).
function Runtime.DrainInbox(player)
 if not player or not Runtime.Loaded[player.UserId]or Runtime.Draining[player.UserId]then return end
 local id=player.UserId;Runtime.Draining[id]=true
 local transport,ok,result=pcall(function()return Runtime.Engine.Market:DrainInbox(id)end)
 Runtime.Draining[id]=nil
 if transport and ok and type(result)=='table'and (result.Applied or 0)>0 then Runtime.Refresh(player)
 elseif not transport or not ok then warn('DOGROTS inbox deferred:',transport and result or ok)end
end
function Runtime.Ready(player)return Runtime.Loaded[player.UserId] and player:GetAttribute('EconomyReady') and not Runtime.Closing end
-- Rare discoveries use the same durable mint transaction as ordinary ownership.
-- No client action can schedule or grant an arrival.
local nextArrival=os.time()+Config.SpecialDiscovery.ArrivalInterval
local pendingArrival=nil
function Runtime.SpecialTick(now)
 if pendingArrival and (not Runtime.Loaded[pendingArrival.UserId]or now>pendingArrival.CreatedAt+120)then pendingArrival=nil end
 for id,p in pairs(Runtime.Views)do
  if p.SpecialDiscoveries and p.SpecialDiscoveries.LongDogPending and Rules.Free(p)then
   local operation='excavation-'..tostring(p.SpecialDiscoveries.LongDogFoundAt or p.TotalExcavations or 0)
   local transport,ok,result=pcall(function()return Runtime.Engine:GrantSpecial(id,'LongDog',operation)end)
   if transport and ok then
    local player=Players:GetPlayerByUserId(id)
    if player then
     Runtime.Refresh(player)
     -- It first stretches out of the pit for everyone; the discovery toast follows.
     local shown,model=pcall(Runtime.RevealExcavation,player,'LongDog')
     local toastAfter=(shown and model)and math.max(0,require(script.Parent.Parent.SecretReveal).Hold('LongDog')-.8)or 0
     task.delay(toastAfter,function()
      if player.Parent then Replicated.RewardPresentation:FireClient(player,{Cue='Reveal',Message=result.Message,Dog=result.Dog})end
     end)
    end
   end
  end
 end
 if now>=nextArrival then
  nextArrival=now+Config.SpecialDiscovery.ArrivalInterval
  if not pendingArrival and rng:NextNumber()<Config.SpecialDiscovery.ArrivalChance then
   local eligible={}
   for id,p in pairs(Runtime.Views)do
    if Runtime.Loaded[id]and p.UnlockedLayers['5']and p.Prestige>=1 and Rules.Free(p)and now-((p.SpecialDiscoveries or {}).LastArrivalAt or 0)>=86400 then table.insert(eligible,id)end
   end
   table.sort(eligible)
   if #eligible>0 then pendingArrival={UserId=eligible[rng:NextInteger(1,#eligible)],Operation='arrival-'..guid(),CreatedAt=now}end
  end
 end
 if pendingArrival and Runtime.Loaded[pendingArrival.UserId]then
  local arrival=pendingArrival
  local transport,ok,result=pcall(function()return Runtime.Engine:GrantSpecial(arrival.UserId,'TheDog',arrival.Operation)end)
  if transport and ok then
   pendingArrival=nil;Runtime.RefreshAll()
   Replicated.RewardPresentation:FireAllClients({Announcement='THE DOG HAS ARRIVED',Tier='Secret'})
   local player=Players:GetPlayerByUserId(arrival.UserId)
   if player then Replicated.RewardPresentation:FireClient(player,{Cue='Reveal',Message=result.Message,Dog=result.Dog})end
  end
 end
end
-- The Secret arrival of a dug-up dog, staged on one of the owner's dig slots.
function Runtime.RevealExcavation(player,dogId)
 local yard=require(script.Parent.YardCommerce).Yard(player);if not yard then return end
 -- An unlocked, empty pit if there is one, so it does not stand inside a resident dog.
 local slot
 for _,s in ipairs(yard:GetDescendants())do
  if s.Name:match('^DigSlot_%d+$')and s:GetAttribute('Unlocked')~=false and typeof(s:GetAttribute('DigCenter'))=='Vector3'then
   if not s:GetAttribute('AssignedDogUid')then slot=s;break end
   slot=slot or s
  end
 end
 local spawn=yard:FindFirstChild('YardSpawn',true)
 local ground=slot and slot:GetAttribute('DigCenter')or (spawn and spawn.Position)
 if not ground then return end
 -- Stand on the pit's visible top, as DogKennelService does.
 local pit=slot and slot:FindFirstChild('DarkExcavation')
 if pit and pit:IsA('BasePart')then ground=Vector3.new(ground.X,pit.Position.Y+pit.Size.Y/2,ground.Z)
 elseif slot then ground+=Vector3.new(0,((slot:GetAttribute('DigSize')or Vector3.new(12,.4,12)).Y)/2,0)end
 local toward=(spawn and spawn.Position or ground+Vector3.zAxis)-ground
 return require(script.Parent.Parent.SecretReveal).Show(dogId,ground+Vector3.new(0,.04,0),toward,{Venue='Excavation',By=player.DisplayName})
end
local buckets={};local marketQueries={}
local function allow(player,cost)
 local now=os.clock();local b=buckets[player] or {Tokens=8,At=now};buckets[player]=b
 b.Tokens=math.min(8,b.Tokens+(now-b.At)*1.5);b.At=now
 if b.Tokens<cost then return false end;b.Tokens-=cost;return true
end
Runtime.Allow=allow
local function clean(value,depth)
 if depth>3 then return false end
 local kind=typeof(value)
 if kind=='string' then return #value<=120
 elseif kind=='number' then return value==value and math.abs(value)<=Config.MaxCash
 elseif kind=='boolean' or kind=='nil' then return true
 elseif kind=='table' then local n=0;for k,v in pairs(value)do n+=1;if n>30 or (type(k)~='string' and type(k)~='number') or not clean(v,depth+1) then return false end end;return true end
 return false
end
function Runtime.Snapshot(player)
 local p=Runtime.Views[player.UserId];Rules.Check(p,'Loading profile')
 local view=Rules.Copy(p);view.Session=nil;view.RecordJobs=nil
 local sellable={}
 if not Runtime.Engine.TradeByUser[player.UserId]then
  local commerce=require(script.Parent.YardCommerce)
  for uid in pairs(p.Items or{})do if commerce.CanSell(p,uid)then sellable[uid]=true end end
 end
 for _,b in pairs(view.OwnedBlocks or {})do
  if b.Pool then
   local total=0;for _,row in ipairs(b.Pool)do total+=row.Weight end
   b.Odds={};for _,row in ipairs(b.Pool)do
    local def=Definitions[row.Id]
    table.insert(b.Odds,{Id=row.Id,Name=def and def.DisplayName or row.Id,Rarity=def and def.Rarity or 'Legacy',Rank=def and def.Rank or row.Rank,Chance=total>0 and row.Weight/total or 0})
   end
  end
  b.Seed=nil;b.Pool=nil;b.Variants=nil
 end
  local dex={};for id in pairs(p.DogDex)do local d=Definitions[id];if d and not d.Reserved and d.Available then dex[id]=Rules.Copy(d)end end
 -- Trades 2.0 (docs/TRADE.md): expired invitations and idle sessions are pruned, then the session as
 -- this player sees it (Engine.TradeView) and the online players with their invitation state.
 Runtime.Engine:PruneTrades()
 local tradeView=Runtime.Engine:TradeView(player.UserId)
 local online=Runtime.TradePlayers(player)
 -- Per-dog stats and team income from the shared model (Rules.IncomeModel), the same numbers the
 -- HUD shows and offline earnings use. Luck is the real rare-loot luck (fraction, +0.25 = +25%).
 local okModel,model=pcall(Rules.IncomeModel,p,os.time())
 if not okModel then warn('DOGROTS income model failed:',model);model={PerMinute=0,Dogs={}}end
 local dogStats={};local income=model.PerMinute/60
 for uid,m in pairs(model.Dogs)do
  dogStats[uid]={Cooldown=m.Cooldown,Cycle=m.Cycle,Luck=m.LuckPct/100,LuckPct=m.LuckPct,MaxDepth=p.CurrentLayer,CoinsPerMin=m.CoinsPerMin,
   DigsPerMin=m.DigsPerMin,Efficiency=m.Efficiency,LootPerMin=m.LootPerMin,ItemsPerMin=m.ItemsPerMin,ItemFindsPerMin=m.ItemFindsPerMin,Rolls=m.Rolls,Working=m.Assigned}
 end
 local features={};Rules.Features.Snapshot(Rules,p,features,os.time())
 return {Features=features,Profile=view,OfflineEarnings=Offline.Report(view),Meta=Rules.Meta(os.time()),Week=Rules.Week(os.time()),EventTotal=Runtime.EventTotal or 0,
  SellableItems=sellable,DogStats=dogStats,IncomeEstimate=income,IncomePerMinute=model.PerMinute,Storage=Rules.Storage(p,os.time()),EventEnds=345600+(Rules.Week(os.time())+1)*604800,Trade=tradeView,Players=online,Preview=memory,Now=os.time(),Dex=dex,GlobalRecords=Runtime.GlobalRecords or {},ServerRecords=Runtime.ServerRecords or {}}
end
function Runtime.Request(player,action,a,requestId)
 local requestCost=action=='MarketQuery'and 3 or action=='MiningHit'and .25 or action=='MiningTrain'and .5 or 1
 if not allow(player,requestCost)then return false,'Please wait a moment' end
 if not Runtime.Ready(player)then return false,'Your saved profile is still loading' end
 local validArgs=action=='BulkSell'and require(script.Parent.YardCommerce).ValidBulkArgs(a)or action~='BulkSell'and clean(a or {},0)
 if type(action)~='string'or #action>40 or not validArgs then return false,'Invalid request'end
 a=a or {}
 local ok,success,result=pcall(function()
  if action=='Snapshot' then return true,Runtime.Snapshot(player)end
  if action=='MarketQuery' then
   Rules.Check(os.clock()-(marketQueries[player] or -10)>=5,'Market refresh is available every 5 seconds')
   marketQueries[player]=os.clock()
   return true,Runtime.Engine.Market:Query(a)
  end
  Rules.Check(type(requestId)=='string' and requestId:match('^[a-fA-F0-9]+$') and #requestId==32,'Invalid request ID')
  local receiptId=tostring(player.UserId)..':'..requestId:sub(1,26)
  if action=='DistrictTravel'then return require(script.Parent.DistrictTravel).Request(player,a)end
  if action=='Tutorial'then return require(script.Parent.OnboardingService).Request(Runtime,player,a,receiptId)end
  if action=='LabInfo'or action=='LabPreview'or action=='LabCommit'then return require(script.Parent.LabService).Request(player,action,a,receiptId)end
  if action:sub(1,6)=='Mining'then
   local map=workspace:FindFirstChild('DOGROTS_District');local yards=map and map:FindFirstChild('04_PlayerYards');local yard
   if yards then for _,candidate in ipairs(yards:GetChildren())do if candidate:GetAttribute('OwnerUserId')==player.UserId and candidate:GetAttribute('YardId')==player:GetAttribute('YardId')then yard=candidate;break end end end
   local corner=yard and yard:FindFirstChild('MiningCorner');local anchor=corner and(corner:FindFirstChild('MiningPad')or corner:FindFirstChildWhichIsA('BasePart'))
   local hrp=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   -- Ending a session must always work (respawn, teleport), so it skips the distance check.
   if action~='MiningEnd'and action~='MiningTrainEnd'then
    Rules.Check(yard and anchor and hrp and(hrp.Position-anchor.Position).Magnitude<=32,'Stand at your Mining Corner')
   end
   local session=require(script.Parent.MiningSessions).Get(player.UserId)
   if action=='MiningHit'then
    -- Cheap RAM pre-check: only live, open circles of a live session pay for a profile
    -- transaction (same order of checks as MiningRules.Hit).
    local id=tonumber(a.Target);local target
    for _,t in pairs(session.Targets or{})do if t.Id==id then target=t end end
    local view=Runtime.Views[player.UserId];local mining=view and view.Mining
    if type(mining)=='table'and(tonumber(mining.ActiveUntil)or 0)<os.time()then return false,'M:SESSION_OVER'end
    if not target then
     if session.Stale and id and session.Stale[id]then
      -- An in-flight click on the previous ore: harmless, answered from RAM.
      local MiningRules=require(game:GetService('ReplicatedStorage'):WaitForChild('Mining'):WaitForChild('MiningRules'))
      return true,{Message='M:STALE',MiningTargets=MiningRules.ViewTargets(session)}
     end
     return false,'M:TARGET_GONE'
    end
    if workspace:GetServerTimeNow()<target.SpawnAt-Config.Mining.Timing.ServerSlack then return false,'M:TOO_EARLY'end
   end
   local ping=0;pcall(function()ping=player:GetNetworkPing()end)
   -- Hits and reps are single-use by design (circle ids / rest timer): no receipt slots needed.
   local receipt=if action=='MiningHit'or action=='MiningTrain'then nil else receiptId
   return Runtime.Engine:MiningAction(player.UserId,action,a,receipt,session,ping)
  end
  local engine,id=Runtime.Engine,player.UserId
  local commerce=require(script.Parent.YardCommerce)
  if action=='SellItem'then return false,'Sell finds with the collector in your own yard'end
  if action=='SellQuote'or action=='NPCSell'or action=='BulkSell'then return commerce.Request(player,action,a,receiptId)end
  if action=='SellLoot'then commerce.Visit(player)end
  if action=='BuyPlotSkin'or action=='ClaimPlotSkin'then require(script.Parent.PlotDevelopment).VisitShop(player)end
  if action=='DisplayDog'then commerce.StorageVisit(player)end
  if action=='ClaimOffline'then return engine:ClaimOffline(id,a,receiptId)
  elseif action=='List' then return engine.Market:Create(id,a,receiptId)
  elseif action=='BuyListing' then return engine.Market:Buy(id,a,receiptId)
  elseif action=='Bid' then return engine.Market:Bid(id,a,receiptId)
  elseif action=='CancelListing' then return engine.Market:Close(a.DogId,a.Id,id,receiptId)
  elseif action=='Roll' then return engine:Roll(id,a.Mode,receiptId)
  elseif action=='EventClaim' then return engine:EventClaim(id,a,receiptId)
  elseif action=='TradeRequest' then return true,engine:TradeRequest(id,a.Target)
  elseif action=='TradeCancel' then return true,engine:TradeCancel(id,a)
  elseif action=='Trade' then return true,engine:Trade(id,a.Action,a)
  else return engine:Action(id,action,a,receiptId)end
 end)
 if not ok then return false,tostring(success)end
 if action~='Snapshot' and action~='MarketQuery' then
  local fastSale=action=='BulkSell'or action=='SellLoot'
  local miningAction=type(action)=='string'and action:sub(1,6)=='Mining'
  local patch
  if miningAction and success then patch=Runtime.RefreshMining(player,type(result)=='table'and result or nil)
  elseif miningAction then
   -- A rejected mining swing changes no profile state.
  elseif fastSale and success then patch=Runtime.RefreshSale(player,type(result)=='table'and result.FastSale or nil)
  elseif fastSale then
   -- Rejected sales do not need any world/profile projection.
  elseif action=='BuyListing'or action=='CancelListing'or action=='Bid'then Runtime.RefreshAll()
  elseif action=='Trade'or action=='TradeRequest'or action=='TradeCancel'then
   -- Trade steps change no profile; a completed trade changed both.
   if success and type(result)=='table'and result.CompletedWith then
    Runtime.Refresh(player);local partner=Players:GetPlayerByUserId(result.CompletedWith);if partner then Runtime.Refresh(partner)end
   end
  else Runtime.Refresh(player)end
  if success and action~='LabInfo'and action~='LabPreview'then
   if miningAction then
    if type(result)~='table'then result={Message=tostring(result)}end
    result.StatePatch=patch
   elseif fastSale then
    if type(result)~='table'then result={Message=tostring(result)}end
    patch=patch or salePatch(Runtime.Views[player.UserId],result.FastSale)
    if action=='BulkSell'and type(result.SoldUids)=='table'and not patch.SoldUids then patch.SoldUids=Rules.Copy(result.SoldUids)end
    result.FastSale=nil;result.StatePatch=patch
   elseif type(result)=='table'then
    result.StateSnapshot=Runtime.Snapshot(player)
   end
  end
 end
 return success,result
end
-- variant: the conveyor dog's server-rolled Variant attribute (DogLineSpawner), never a client value.
function Runtime.BuyLine(player,dogId,uid,variant)
 if not Runtime.Ready(player) or not allow(player,2)then return false,'Please wait' end
 local ok,result=Runtime.Engine:BuyLine(player.UserId,dogId,uid,nil,variant)
 if ok then
  Runtime.Refresh(player)
  local previous=type(result)=='table'and result.PreviousOwner
  if previous and previous~=player.UserId then local old=Players:GetPlayerByUserId(previous);if old then Runtime.Refresh(old)end end
 end
 return ok,result
end
function Runtime.Deliver(player,uid)
 local ok,result=Runtime.Engine:Deliver(player.UserId,uid)
 if ok then Runtime.Refresh(player)end;return ok,result
end
local function announce(x,global)
 if not x or not I.Definitions[x.ItemId]then return end
 if x.TierIndex>=8 or x.Class=='Secret' or (global and x.RecordAtCreation and x.RecordAtCreation.ImprovedGlobal) then
  if os.clock()-(Runtime.LastAnnouncement or -60)<15 and x.Class~='Secret'then return end
  Runtime.LastAnnouncement=os.clock();Replicated.DiscoveryAnnouncement:FireAllClients(x,global)
 end
end
-- Weight records. Server-session records live in RAM only; global candidates are
-- batched and merged with one UpdateAsync per depth (Runtime.FlushRecords).
Runtime.ServerBook={};Runtime.RecordQueue={};Runtime.RecordsReadAt={};Runtime.AnnounceQueue={}
function Runtime.PumpAnnouncements()
 local queue=Runtime.AnnounceQueue
 while queue[1] and os.clock()-queue[1].At>90 do table.remove(queue,1)end
 local nextRow=queue[1];if not nextRow then return end
 if nextRow.X.Class=='Secret' or os.clock()-(Runtime.LastAnnouncement or -60)>=15 then
  table.remove(queue,1);announce(nextRow.X,true)
 end
end
Runtime.GlobalRecords=Runtime.GlobalRecords or {};Runtime.ServerRecords=Runtime.ServerRecords or {}
function Runtime.CollectRecords(id)
 -- Timeout=0: a profile whose lock is held (a Robux receipt waiting on DataStore) is retried next
 -- pass; waiting here would pause the economy loop (every player's tick) for up to LockWait.
 local transport,ok,result=pcall(function()return Runtime.Engine:Records(id,Runtime.ServerBook,{Timeout=0})end)
 if not(transport and ok and type(result)=='table')then return 0 end
 local count=0
 for depth,rows in pairs(result.Server or {})do
  local book=Runtime.ServerBook[depth]or{};Runtime.ServerBook[depth]=book
  for itemId,row in pairs(rows)do
   if not book[itemId]or row.WeightKg>book[itemId].WeightKg then book[itemId]=row;Runtime.ServerRecords[itemId]=row end
  end
 end
 for itemId,x in pairs(result.Jobs or {})do
  count+=1
  local queue=Runtime.RecordQueue[x.Depth]or{};Runtime.RecordQueue[x.Depth]=queue
  local pending=queue[itemId]
  if not pending or x.WeightKg>pending.Row.WeightKg then
   queue[itemId]={Row={WeightKg=x.WeightKg,ItemUid=x.ItemUid,Finder=x.OriginalFinderUserId,At=x.FoundAt},Job=x}
  end
 end
 return count
end
function Runtime.FlushRecords()
 if Runtime.FlushingRecords then return end;Runtime.FlushingRecords=true
 -- The guard is always released: one failing step must not stop record batches (and the
 -- shutdown flush) for the rest of the server's life.
 local batchOk,batchError=pcall(function()
 for depth,queue in pairs(Runtime.RecordQueue)do if next(queue)then
  Runtime.RecordQueue[depth]={}
  local candidates={};for itemId,entry in pairs(queue)do candidates[itemId]=entry.Row end
  local ok,improved,book=pcall(function()return Runtime.Tx:MergeRecords('records:'..depth,candidates)end)
  if not ok then
   local current=Runtime.RecordQueue[depth]
   for itemId,entry in pairs(queue)do local c=current[itemId];if not c or entry.Row.WeightKg>c.Row.WeightKg then current[itemId]=entry end end
   warn('DOGROTS record batch deferred:',improved)
  else
   for itemId,row in pairs(book or {})do Runtime.GlobalRecords[itemId]=row end
   Runtime.RecordsReadAt[depth]=os.time()
   for itemId,info in pairs(improved or {})do
    local x=Rules.Copy(queue[itemId].Job);x.RecordAtCreation=x.RecordAtCreation or {}
    x.RecordAtCreation.Global=true;if info.Previous then x.RecordAtCreation.ImprovedGlobal=true end
    -- Batched records arrive together; queue the banners so the 15 s cooldown spaces them out.
    table.insert(Runtime.AnnounceQueue,{X=x,At=os.clock()})
    if not memory and (x.TierIndex>=8 or x.Class=='Secret' or x.RecordAtCreation.ImprovedGlobal)then
     local payload={ItemId=x.ItemId,DisplayName=x.DisplayName,WeightKg=x.WeightKg,WeightTier=x.WeightTier,TierIndex=x.TierIndex,Class=x.Class,OriginalFinderUserId=x.OriginalFinderUserId,RecordAtCreation=x.RecordAtCreation,Source=session}
     task.spawn(function()pcall(function()Messaging:PublishAsync('DOGROTS_WEIGHT_RECORDS_V2',payload)end)end)
    end
    local finder=x.OriginalFinderUserId
    if finder and Runtime.Loaded[finder]then
     local okFlag=pcall(function()return Runtime.Tx:Run({'p:'..finder},function(v)
      local p=v['p:'..finder];if not p then return false end
      I.Normalize(p);local held=p.Items[x.ItemUid]
      if held then held.RecordAtCreation=held.RecordAtCreation or {};held.RecordAtCreation.Global=true;if info.Previous then held.RecordAtCreation.ImprovedGlobal=true end end
      return true
     end)end)
     local player=okFlag and Players:GetPlayerByUserId(finder);if player then pcall(Runtime.Refresh,player)end
    end
   end
  end
 end end
 end)
 Runtime.FlushingRecords=false
 if not batchOk then warn('DOGROTS record batch failed:',batchError)end
end
-- Keeps the global record board fresh for display: one depth per call (≈2 reads/min).
function Runtime.ReadNextRecordDepth()
 local oldest,depth=math.huge,nil
 for d=1,5 do local at=Runtime.RecordsReadAt[d]or 0;if at<oldest then oldest,depth=at,d end end
 if not depth or os.time()-oldest<120 then return end
 Runtime.RecordsReadAt[depth]=os.time()
 local ok,book=pcall(function()return Runtime.Tx:Read('records:'..depth)end)
 if ok then for itemId,row in pairs(book or {})do Runtime.GlobalRecords[itemId]=row end end
end
-- Server -> client notifications for the new systems (trade invites, case results, level-ups...):
-- DogEconomyPush:FireClient(player, kind, data). Created before anything can fire it.
function Runtime.PushTo(player,kind,data)
 local push=Runtime.Push
 if push and player and player.Parent then push:FireClient(player,kind,data)end
end
-- TRADES 2.0 (docs/TRADE.md). The online players as `player` sees them in the trade window: the
-- fields of the old list plus the invitation state (Engine.TradeRelation: InviteIn, InviteOut,
-- Cooldown, CanInvite, Block).
function Runtime.TradePlayers(player)
 local engine=Runtime.Engine;local id=player.UserId;local out={}
 local mine=Runtime.Views[id];local myLevel=mine and mine.Level or player:GetAttribute('Level')or 1
 for _,other in ipairs(Players:GetPlayers())do if other~=player and Runtime.Ready(other)then
  local view=Runtime.Views[other.UserId];local level=other:GetAttribute('Level')or 1
  local row={Id=other.UserId,Name=other.DisplayName,Username=other.Name,Level=level,Status=engine.TradeByUser[other.UserId]and'Trading'or'Online',
   Trades=view and view.Stats and view.Stats.CompletedTrades or 0,Listings=view and Rules.Count(view.Listings or{})or 0}
  for key,value in pairs(engine:TradeRelation(id,other.UserId,myLevel,level))do row[key]=value end
  table.insert(out,row)
 end end
 return out
end
-- Engine.OnTrade: pushes the new trade state to one player (DogEconomyPush 'Trade' = {Event, Trade =
-- Engine.TradeView or nil, Players, Now}); an incoming invitation also sends 'TradeInvite', so the
-- invitee gets a popup and no window opens by force. Event.Names holds the display names involved.
function Runtime.PushTrade(id,event)
 local player=Players:GetPlayerByUserId(id);if not(player and Runtime.Loaded[id])then return end
 local payload=Rules.Copy(event);payload.Names={}
 for _,key in ipairs({'By','From','To'})do
  local uid=payload[key];local other=type(uid)=='number'and Players:GetPlayerByUserId(uid)
  if other then payload.Names[tostring(uid)]=other.DisplayName end
 end
 local sender=type(payload.From)=='number'and Runtime.Views[payload.From];if sender then payload.FromLevel=sender.Level end
 local listed,list=pcall(Runtime.TradePlayers,player)
 Runtime.PushTo(player,'Trade',{Event=payload,Trade=Runtime.Engine:TradeView(id),Players=listed and list or nil,Now=os.time()})
 if payload.Kind=='Invite'and payload.To==id then Runtime.PushTo(player,'TradeInvite',payload)end
end
Runtime.Engine.OnTrade=Runtime.PushTrade
function Runtime.Start()
 if Runtime.Started then return end;Runtime.Started=true
 local push=Replicated:FindFirstChild('DogEconomyPush')or Instance.new('RemoteEvent');push.Name='DogEconomyPush';push.Parent=Replicated;Runtime.Push=push
 require(script.Parent.PurchaseService).Start(Runtime)
 local eventKey='event:'..Rules.Week(os.time());local okEvent,event=pcall(function()return Runtime.Tx:Read(eventKey)end)
 Runtime.EventTotal=okEvent and event and event.Total or 0
 if not memory then pcall(function()Messaging:SubscribeAsync('DOGROTS_WEIGHT_RECORDS_V2',function(message)
  local x=message.Data;if type(x)=='table' and x.Source~=session then announce(x,true)end
 end)end)end
 Replicated.DogEconomyRequest.OnServerInvoke=Runtime.Request
 if not memory then pcall(function()Messaging:SubscribeAsync(INBOX_TOPIC,function(message)
  local data=message.Data;local id=type(data)=='table'and tonumber(data.UserId)
  local player=id and Players:GetPlayerByUserId(id);if player then task.spawn(Runtime.DrainInbox,player)end
 end)end)end
 -- Releases a profile when its player leaves or the server closes: Leave clears the session
 -- and checkpoints playtime, FlushProfile saves. A save that found committed writes in
 -- DataStore ("Resynced": RAM re-read them) dropped the leave mutation, so it is applied and
 -- saved again. Every step is protected so cleanup always runs. Returns saveOK, message.
 function Runtime.ReleaseProfile(uid,closing,timeout)
  local released,releaseError=pcall(require(script.Parent.ServerLuck).Release,Runtime,uid,closing)
  if not released then warn('DOGROTS server luck release failed:',uid,releaseError)end
  local saveOK,saveResult=false,'Profile was not saved'
  for _=1,3 do
   local alive,leaveOK,leaveResult=pcall(Runtime.Engine.Leave,Runtime.Engine,uid,{Timeout=timeout})
   if not alive or not leaveOK then warn('DOGROTS leave mutation failed:',uid,alive and leaveResult or leaveOK)end
   local called,flushOK,flushResult=pcall(Runtime.Tx.FlushProfile,Runtime.Tx,uid)
   if called then saveOK,saveResult=flushOK,flushResult else saveOK,saveResult=false,flushOK end
   if not(saveOK and saveResult=='Resynced')then break end
  end
  return saveOK,saveResult
 end
 local function added(player)
  player:SetAttribute('EconomyReady',false)
  local ok,result
  -- A quick rejoin can arrive before the previous server has released the session.
  for attempt=1,6 do
   ok,result=Runtime.Engine:Join(player.UserId)
   if ok or not player.Parent or not tostring(result):lower():find('another server',1,true)then break end
   task.wait(2.5)
  end
  if not player.Parent then if ok then pcall(Runtime.ReleaseProfile,player.UserId,Runtime.Closing,10)end;return end
  if not ok then player:Kick('Your data is protected. Please rejoin shortly. '..tostring(result));return end
  Runtime.Loaded[player.UserId]=true
  local shown,showError=pcall(Runtime.Refresh,player)
  if not shown then warn('DOGROTS first refresh failed:',player.UserId,showError)end
  task.spawn(Runtime.DrainInbox,player)
 end
 Players.PlayerAdded:Connect(added)
 for _,p in ipairs(Players:GetPlayers())do task.spawn(added,p)end
 Players.PlayerRemoving:Connect(function(p)
  p:SetAttribute('EconomyLeaving',true)
  local uid=p.UserId
  -- A quick rejoin to this server can load a new session for uid while this release yields (lock
  -- wait, slow save): that session keeps its profile in RAM and its runtime state.
  local function rejoined()local current=Players:GetPlayerByUserId(uid);return current~=nil and current~=p end
  if Runtime.Loaded[uid] then
   -- A receipt may hold the profile lock while it waits on DataStore: give Leave time.
   local called,saveOK,saveResult=pcall(Runtime.ReleaseProfile,uid,Runtime.Closing,30)
   if not(called and saveOK)then warn('DOGROTS final profile save deferred:',uid,called and saveResult or saveOK)
   elseif not rejoined()then Runtime.Tx:UnloadProfile(uid)end
  end
  buckets[p]=nil;marketQueries[p]=nil
  if rejoined()then return end
  Runtime.Loaded[uid]=nil;Runtime.Views[uid]=nil;if Runtime.SeenFinds then Runtime.SeenFinds[uid]=nil end
  Runtime.Draining[uid]=nil;if Runtime.TickWarnings then Runtime.TickWarnings[uid]=nil end
 end)
 game:BindToClose(function()
  Runtime.Closing=true;local remaining=0
  for _,p in ipairs(Players:GetPlayers())do if Runtime.Loaded[p.UserId]then
   remaining+=1;task.spawn(function()
    local called,ok,err=pcall(Runtime.ReleaseProfile,p.UserId,true,10)
    if not called or not ok then warn('DOGROTS shutdown save failed:',p.UserId,called and err or ok)end
    remaining-=1
   end)
  end end
  local untilTime=os.clock()+25;while remaining>0 and os.clock()<untilTime do task.wait(.1)end
  -- Player data first: retry any dirty profile left behind by a failed release save before the
  -- community counter and the record batch spend what is left of the 30 s budget, then save
  -- the record flags that batch may set on items (only profiles that are dirty again).
  local function flushProfiles()
   local ok,summary=pcall(function()return Runtime.Tx:FlushAllProfiles()end)
   if not ok then warn('DOGROTS final shutdown flush failed:',summary)
   elseif summary and next(summary.Failed or{})then for key,err in pairs(summary.Failed)do warn('DOGROTS final profile save deferred:',key,err)end end
  end
  flushProfiles()
  pcall(Runtime.FlushEvents);pcall(Runtime.FlushRecords)
  flushProfiles()
 end)
 -- The economy loop renews sessions, autosaves and drives every timed system, and Robux
 -- receipts need a live session. Every step runs in its own pcall (errors are logged at
 -- most every 30 s per step) so one exception can never stop it again, and a watchdog
 -- starts a fresh loop if this one stops beating (a step that yields forever).
 local stepWarnings,lastServerLuckSync={},0
 -- In-flight guards for the steps that run beside the loop (shared by every loop generation).
 local specialRunning,settling=false,false
 local function step(name,fn,...)
  local result=table.pack(pcall(fn,...))
  if not result[1]and os.clock()-(stepWarnings[name]or -60)>=30 then
   stepWarnings[name]=os.clock();warn('DOGROTS economy step "'..name..'" failed:',result[2])
  end
  return table.unpack(result,1,result.n)
 end
 local function isDue(id)
  local p=Runtime.Views[id];if not p then return false end
  local due=not p.Session or (tonumber(p.Session.Expires)or 0)-os.time()<90
  for _,dog in pairs(p.Dogs or {})do if dog.AssignedSlot~='' and os.time()>=(dog.NextWorkAt or math.huge)then due=true end end
  return due
 end
 local function loopOnce()
  local ids={};for id in pairs(Runtime.Loaded)do table.insert(ids,id)end
  if Runtime.Kennels then step('work visuals',Runtime.Kennels.UpdateWorkVisuals)end
  local tickIds={}
  for _,id in ipairs(ids)do
   -- A view that cannot be read is ticked anyway: TickAll renews its session.
   local known,due=step('schedule',isDue,id)
   if not known or due then table.insert(tickIds,id)end
  end
  if #tickIds>0 then
   local called,ok,result=step('tick',Runtime.Engine.TickAll,Runtime.Engine,tickIds)
   if called and ok and type(result)=='table'then
    Runtime.LastTick=os.time();step('global dig',Runtime.AccumulateEvent,result.Contribution or 0)
    Runtime.TickWarnings=Runtime.TickWarnings or {}
    local failed,skipped=result.Failed or {},result.Skipped or {}
    for id,err in pairs(failed)do
     if os.clock()-(Runtime.TickWarnings[id]or -60)>=60 then Runtime.TickWarnings[id]=os.clock();warn('DOGROTS tick deferred for',id,err)end
    end
    for _,id in ipairs(tickIds)do local p=Players:GetPlayerByUserId(id);if p and not failed[id]and not skipped[id]then step('refresh',Runtime.Refresh,p)end end
   elseif called then warn('DOGROTS tick deferred:',result)end
  end
  -- Global Dig is one shared key for every server: batch it every 30 seconds.
  if os.time()-(Runtime.LastEventFlush or 0)>=30 then Runtime.LastEventFlush=os.time();task.spawn(Runtime.FlushEvents)end
  if os.time()-(Runtime.LastInboxPoll or 0)>=120 then
   Runtime.LastInboxPoll=os.time()
   task.spawn(function()for _,player in ipairs(Players:GetPlayers())do Runtime.DrainInbox(player)end end)
  end
  if os.time()-(Runtime.LastAutosave or 0)>=60 then
   Runtime.LastAutosave=os.time();task.spawn(function()
    local ok,summary=pcall(function()return Runtime.Tx:FlushAllProfiles()end)
    if not ok then warn('DOGROTS autosave failed:',summary)
    elseif summary and next(summary.Failed or{})then for key,err in pairs(summary.Failed)do warn('DOGROTS profile autosave deferred:',key,err)end end
    -- Profiles whose PlayerRemoving save had to be retried can leave RAM once
    -- a later autosave succeeds. Active profiles stay resident.
    local unload={}
    for key in pairs(Runtime.Tx.Loaded)do
     if type(key)=='string'and key:sub(1,2)=='p:'and not Runtime.Tx.Dirty[key]then
      local uid=tonumber(key:sub(3));if uid and not Runtime.Loaded[uid]then table.insert(unload,key)end
     end
    end
    for _,key in ipairs(unload)do pcall(Runtime.Tx.UnloadProfile,Runtime.Tx,key)end
   end)
  end
  -- Special grants and market settlement are journaled DataStore transactions: they run beside
  -- the loop, one at a time, so a slow DataStore never pauses digging and session renewal.
  if os.time()-(Runtime.LastSpecial or 0)>=10 and not specialRunning then
   Runtime.LastSpecial=os.time();specialRunning=true
   task.spawn(function()step('special discoveries',Runtime.SpecialTick,os.time());specialRunning=false end)
  end
  -- Record checks are RAM-only now; items leave "record check pending" within ~5 s.
  if os.time()-(Runtime.LastRecords or 0)>=5 then
   Runtime.LastRecords=os.time()
   for _,id in ipairs(ids)do
    local called,count=step('records',Runtime.CollectRecords,id)
    if called and (tonumber(count)or 0)>0 then local player=Players:GetPlayerByUserId(id);if player then step('refresh',Runtime.Refresh,player)end end
   end
  end
  if os.time()-(Runtime.LastRecordFlush or 0)>=60 then Runtime.LastRecordFlush=os.time();task.spawn(Runtime.FlushRecords)end
  step('announcements',Runtime.PumpAnnouncements)
  if os.time()-(Runtime.LastRecordRead or 0)>=30 then Runtime.LastRecordRead=os.time();task.spawn(Runtime.ReadNextRecordDepth)end
  if os.time()-(Runtime.LastSettlement or 0)>=20 and not settling then
   Runtime.LastSettlement=os.time();settling=true
   task.spawn(function()
    local ok,count=pcall(function()return Runtime.Engine.Market:Due()end)
    settling=false
    if not ok then warn('DOGROTS settlement deferred:',count)elseif (count or 0)>0 then step('refresh all',Runtime.RefreshAll)end
   end)
  end
  -- Paid server luck lives in each buyer's profile as a credit: keep the saved remainder in
  -- step with this server's timer and start queued time when there is room.
  if os.time()-lastServerLuckSync>=30 then
   lastServerLuckSync=os.time();task.spawn(step,'server luck credits',require(script.Parent.ServerLuck).SyncAll,Runtime)
  end
 end
 Runtime.LoopGeneration=0
 local function startLoop()
  Runtime.LoopGeneration+=1;local generation=Runtime.LoopGeneration;Runtime.LoopBeat=os.clock()
  task.spawn(function()
   while not Runtime.Closing and Runtime.LoopGeneration==generation do
    task.wait(Config.TickSeconds)
    if Runtime.Closing or Runtime.LoopGeneration~=generation then break end
    Runtime.LoopBeat=os.clock()
    step('loop',loopOnce)
   end
  end)
 end
 startLoop()
 task.spawn(function()
  while not Runtime.Closing do
   task.wait(5)
   local silent=os.clock()-(Runtime.LoopBeat or 0)
   if not Runtime.Closing and silent>20 then
    warn('DOGROTS economy loop silent for',math.floor(silent),'s; starting a fresh loop')
    startLoop()
   end
  end
 end)
 print('DOGROTS_ECONOMY_READY',memory and 'STUDIO_MEMORY' or 'RAM_FIRST_PERSISTENT','GLOBAL_FIX_1',require(script.Parent.Config).BalanceVersion)
end
return Runtime
