local RS=game:GetService('ReplicatedStorage');local Http=game:GetService('HttpService')
local R=require(script.Parent.Rules);local I=require(script.Parent.ItemRules);local Stats=require(script.Parent.RecordStats);local Value=require(RS.ItemValuation)
local Access=require(RS.PlotInteractionAccess);local Protection=require(script.Parent.ItemProtection)
local S={Quotes={}};local function runtime()return require(script.Parent.Runtime)end
function S.Yard(player)
 local id=player:GetAttribute('YardId');local map=workspace:FindFirstChild('DOGROTS_District')
 if not map then return end
 for _,yard in ipairs(map['04_PlayerYards']:GetChildren())do if yard:GetAttribute('YardId')==id and yard:GetAttribute('OwnerUserId')==player.UserId then return yard end end
end
function S.Near(player,target,distance)
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
 return target and root and hum and hum.Health>0 and (root.Position-target.Position).Magnitude<=(distance or 18)
end
function S.Visit(player)
 local yard=S.Yard(player);R.Check(yard and Access.CanUse(player,yard,yard:FindFirstChild('SellAnchor')),'Visit the collector in your own yard')
 return yard
end
function S.StorageVisit(player)
 local yard=S.Yard(player);R.Check(yard and Access.CanUse(player,yard,yard:FindFirstChild('StorageAnchor')),'Visit DOG STORAGE in your own yard');return yard
end
-- UPGRADE TREE purchases (Features.UpgradeTree: TreeUpgrade and the old Upgrade action) work
-- anywhere: the tree replaced the yard DOG TRAINING counter and the Paw Market estate terminal, so
-- no visit is required. Kept for old callers; it only checks that the node exists.
function S.UpgradeVisit(_player,kind)
 R.Check(type(kind)=='string'and require(RS.DogEconomy.UpgradeTree).Nodes[kind]~=nil,'Unknown upgrade')
 return true
end
-- Inventory discoveries are unique ItemUid entries, not client-controlled quantities.
-- {Uids={...}, IncludeFavorites=true?}: favourites stay out of a bulk sale unless the player
-- explicitly includes them.
function S.ValidBulkArgs(a)
 if type(a)~='table'or type(a.Uids)~='table'then return false end
 for k,v in pairs(a)do if k~='Uids'and not(k=='IncludeFavorites'and type(v)=='boolean')then return false end end
 local n=#a.Uids;if n<1 or n>1000 then return false end
 local seen,count={},0
 for k,uid in pairs(a.Uids)do
  if not R.Int(k,1,n)or type(uid)~='string'or #uid<1 or #uid>100 or seen[uid]then return false end
  seen[uid]=true;count+=1
 end
 return count==n
end
local function owned(p,uid)
 local x=p.Items and p.Items[uid]
 return x~=nil and x.ItemUid==uid and x.OwnerUserId==p.UserId
end
-- Collector sales ask Economy.ItemProtection in the 'Sell' context: favourites are kept unless the
-- request says IncludeFavorites=true (then the Favorite protector is skipped).
local function saleRules(a)
 return 'Sell',(type(a)=='table'and a.IncludeFavorites==true)and{Favorite=true}or nil
end
-- -> true when a sale would take the find; false[, reason] when it is not owned or a protector keeps
-- it (ignore = protectors to skip, {Favorite=true} for IncludeFavorites).
function S.CanSell(p,uid,ignore)
 if not owned(p,uid)then return false end
 local reason=Protection.Reason(p,uid,'Sell',ignore)
 if reason then return false,reason end
 return true
end
-- Sells the owned, unprotected finds of a.Uids; protected ones stay (SkippedProtected counts them).
function S.BulkSell(player,a,receipt)
 R.Check(S.ValidBulkArgs(a),'Choose unique item IDs (up to 1000)')
 local rt=runtime();local context,ignore=saleRules(a)
 return rt.Tx:Run({'p:'..player.UserId},function(v)
  S.Visit(player)
  local p=v['p:'..player.UserId];rt.Engine:Authorize(p,player.UserId)
  R.Check(not rt.Engine.TradeByUser[player.UserId],'Finish your trade before selling')
  local total,sold,skipped,kept=0,{},0,nil
  for _,uid in ipairs(a.Uids)do
   if owned(p,uid)then
    local protected=Protection.Reason(p,uid,context,ignore)
    if protected then skipped+=1;kept=kept or protected
    else
     local item=I.Get(p,uid,false)
     local price=Value.Price(item) -- Server is authoritative for price.
     total+=price
     local job=p.RecordJobs and p.RecordJobs[item.ItemId]
     if job and job.ItemUid==uid then p.RecordJobs[item.ItemId]=nil end
     p.Items[uid]=nil
     table.insert(sold,uid)
    end
   end
  end
  R.Check(#sold>0,kept or'No items selected')
  R.Credit(p,total);local xp=R.AddXP(p,math.clamp(math.floor(math.sqrt(total)*2),5,250));Stats.Sale(p,total);p.LastSaleAt=os.time();R.Validate(p)
  return {Count=#sold,Cash=total,XPGranted=xp,SoldUids=sold,SkippedProtected=skipped,Message='Sold '..#sold..' items for '..total..' Coins · +'..xp..' XP',
   FastSale={Cash=p.Cash,ItemCount=I.Count(p.Items),SoldUids=R.Copy(sold),Stats=R.Copy(p.Stats),LastSaleAt=p.LastSaleAt,XP=p.XP,Level=p.Level}}
 end,receipt)
end

function S.Request(player,action,a,receipt)
 if action=='BulkSell'then return S.BulkSell(player,a,receipt)end
 local rt=runtime();local yard=S.Visit(player)
 if action=='SellQuote'then
  -- {All=true} appraises up to 20 sellable finds, {Uids={...}} the chosen 1–20; protected finds are
  -- left out (SkippedProtected) and NPCSell checks them again at the sale.
  local p=rt.Engine:Get(player.UserId);local rows,total={},0;local seen={}
  local context,ignore=saleRules(a);local skipped,kept=0,nil
  local function consider(uid)
   local protected=Protection.Reason(p,uid,context,ignore)
   if protected then skipped+=1;kept=kept or protected else table.insert(rows,{Uid=uid})end
  end
  if a.All then
   for uid in pairs(p.Items)do if #rows<20 and owned(p,uid)then consider(uid)end end
  else
   R.Check(type(a.Uids)=='table'and #a.Uids>0 and #a.Uids<=20,'Choose 1–20 finds')
   for _,uid in ipairs(a.Uids)do
    R.Check(type(uid)=='string'and not seen[uid],'Duplicate item');seen[uid]=true
    R.Check(owned(p,uid),'Item no longer exists');consider(uid)
   end
  end
  R.Check(#rows>0,kept or'No items selected')
  for _,row in ipairs(rows)do
   local x=I.Get(p,row.Uid,false)
   row.Price,row.Breakdown=Value.Price(x);row.Name=x.DisplayName;total+=row.Price
  end
  local token=Http:GenerateGUID(false):gsub('-','');S.Quotes[player.UserId]={Token=token,Rows=rows,Total=total,Expires=os.time()+60,Yard=yard,Context=context,Ignore=ignore}
  return true,{Token=token,Rows=rows,Total=total,Expires=os.time()+60,SkippedProtected=skipped}
 end
 if action=='NPCSell'then
  local quote=S.Quotes[player.UserId]
  R.Check(quote and quote.Token==a.Token and os.time()<quote.Expires and quote.Yard==yard,'Quote expired; request a new appraisal')
  local ok,result=rt.Tx:Run({'p:'..player.UserId},function(v)
   S.Visit(player);local p=v['p:'..player.UserId];rt.Engine:Authorize(p,player.UserId)
   local total=0
   for _,row in ipairs(quote.Rows)do
    R.Check(owned(p,row.Uid),'Item no longer exists')
    local protected=Protection.Reason(p,row.Uid,quote.Context,quote.Ignore);R.Check(not protected,protected)
    local x=I.Get(p,row.Uid,false);local price=Value.Price(x)
    R.Check(price==row.Price,'Find changed; request a new appraisal')
    total+=price;p.Items[row.Uid]=nil
   end
   R.Credit(p,total);local xp=R.AddXP(p,math.clamp(math.floor(math.sqrt(total)*2),5,250));Stats.Sale(p,total);p.LastSaleAt=os.time();R.Validate(p)
   return {Message='Sold '..#quote.Rows..' finds for '..total..' Coins · +'..xp..' XP',Cash=total,XPGranted=xp,Count=#quote.Rows}
  end,receipt)
  if ok then S.Quotes[player.UserId]=nil;RS.RewardPresentation:FireClient(player,{Cue='Sell',Message=result.Message})end
  return ok,result
 end
 return false,'Unknown collector action'
end
function S.TryOpen(player,yard,target,page)
 local rt=runtime()
 if not rt.Ready(player)or not Access.CanUse(player,yard,target)or not rt.Allow(player,1)then return false end
 RS.DogEconomyOpen:FireClient(player,page);return true
end
function S.Start()
 require(script.Parent.PlotShowcase).Start()
 local function prompt(yard,target,title,page,action)
  if not target then return end
  local p=Instance.new('ProximityPrompt');p.Name='YardInteraction';p.ActionText=action;p.ObjectText=title
  p.MaxActivationDistance=Access.Distance;p.RequiresLineOfSight=true;p.HoldDuration=.15;p.Parent=target
  p.Triggered:Connect(function(player)S.TryOpen(player,yard,target,page)end)
 end
 for _,yard in workspace.DOGROTS_District['04_PlayerYards']:GetChildren()do if yard:GetAttribute('YardId')then
  prompt(yard,yard:FindFirstChild('SellAnchor'),'SELL · YOUR FINDS','Collector','SELL FINDS')
  -- The yard workshop opens the UPGRADE TREE (its sign is relabelled to match).
  prompt(yard,yard:FindFirstChild('UpgradeAnchor'),'UPGRADE TREE','UpgradeTree','OPEN UPGRADES')
  local workshop=yard:FindFirstChild('Workshop');local sign=workshop and workshop:FindFirstChild('ServiceTitle')
  local lettering=sign and sign:FindFirstChild('Lettering');local text=lettering and lettering:FindFirstChildWhichIsA('TextLabel')
  if text then text.Text='UPGRADE TREE'end
  prompt(yard,yard:FindFirstChild('StorageAnchor'),'DOG STORAGE','Storage','MANAGE DOGS')
 end end
 game.Players.PlayerRemoving:Connect(function(p)S.Quotes[p.UserId]=nil end)
end
return S
