-- Drum, odds board and Aurion plaque text for DOG-O-MATIC, shared by the server (static pool,
-- dog symbols) and every client (per-player pool from RewardMachineInfo). Board rows and drum
-- faces are matched by PrizeIndex, never by list position.
local C=require(script.Parent.RewardMachineConfig)
local Odds=require(script.Parent.RewardMachineOdds)
local RunService=game:GetService("RunService")
local ServerStorage=RunService:IsServer() and game:GetService("ServerStorage") or nil
local T={FeaturedPeriod=600}
-- DogDefinitions requires this module for Aurion's description: load it lazily.
local function dogs()return require(script.Parent.DogEconomy.DogDefinitions)end
-- Sentences built from live odds pick their language here (labels get NoTranslate);
-- fixed labels go through ReplicatedStorage.Localization.Machine instead.
function T.IsRussian()
 local ok,locale=pcall(function()
  local player=game:GetService('Players').LocalPlayer;local LS=game:GetService('LocalizationService')
  if RunService:IsStudio()or not player then return LS.RobloxLocaleId end
  return player.LocaleId or LS.RobloxLocaleId
 end)
 return ok and type(locale)=='string'and locale:sub(1,2):lower()=='ru'
end
-- Russian numbers use a decimal comma (0,20%).
function T.L(en,ru)if T.IsRussian()then return (ru:gsub('(%d)%.(%d)','%1,%2'))end;return en end
function T.Own(label)label:SetAttribute('NoTranslate',true);return label end
T.RarityRu={Common='ОБЫЧНАЯ',Rare='РЕДКАЯ',Epic='ЭПИЧЕСКАЯ',Legendary='ЛЕГЕНДАРНАЯ',Mythic='МИФИЧЕСКАЯ',Secret='СЕКРЕТНАЯ'}
function T.Pct(fraction)return string.format('%.3g%%',(tonumber(fraction)or 0)*100)end
-- Odds disclosure lines for one pool row (dog tiers: each rarity, its dog count and the chance
-- of every single dog; Aurion: its event boost and base chance). Already localized; returns
-- no lines for other rows (their rarity word goes through the dictionary).
function T.OddsLines(row)
 local lines={};local pct=T.Pct
 if row.Kind=='DogTier'and type(row.Breakdown)=='table'then
  for _,part in ipairs(row.Breakdown)do
   local members=type(part.Members)=='table'and #part.Members or 0
   local rarity=tostring(part.Rarity or row.Rarity or'')
   if #row.Breakdown>1 then
    table.insert(lines,T.L(string.format('%s · %s · %d DOGS · %s EACH',rarity:upper(),pct(part.Chance),members,pct(part.EachChance)),
     string.format('%s · %s · СОБАК: %d · КАЖДАЯ %s',T.RarityRu[rarity]or rarity:upper(),pct(part.Chance),members,pct(part.EachChance))))
   else
    table.insert(lines,T.L(string.format('%s · %d DOGS · %s EACH',rarity:upper(),members,pct(part.EachChance)),
     string.format('%s · СОБАК: %d · КАЖДАЯ %s',T.RarityRu[rarity]or rarity:upper(),members,pct(part.EachChance))))
   end
  end
 elseif row.Jackpot and row.Multiplier then
  local base=pct((row.BaseUnits or 0)/(row.OddsDenominator or C.OddsDenominator))
  table.insert(lines,T.L(string.format('SECRET · RAINBOW x%g · BASE %s',row.Multiplier,base),string.format('СЕКРЕТНАЯ · РАДУГА x%g · ОБЫЧНО %s',row.Multiplier,base)))
 end
 return lines,#lines>0
end
-- The world event (Rainbow Rift) whose perks boost Aurion on the machine, from the shared definitions.
function T.BoostEvent()
 local ok,defs=pcall(function()return require(script.Parent.WorldEvents.WorldEventDefinitions)end)
 if not ok or type(defs)~='table'then return nil end
 for _,def in ipairs(defs.List or{})do
  local mult=type(def.Perks)=='table'and tonumber(def.Perks.MachineAurion)
  if def.Enabled~=false and mult and mult>1 then
   return {EventId=def.Id,Name=def.DisplayName,Multiplier=math.min(mult,C.EventBoostCap or 10)}
  end
 end
 return nil
end
-- Static pool (no per-player eligibility). `multiplier` > 1 applies an event boost to Aurion.
function T.Pool(multiplier)
 local rows=C.Rewards
 if multiplier and multiplier>1 then rows=Odds.Boost(rows,multiplier,C.EventBoostCap)end
 return Odds.Build(rows,C.OddsDenominator)
end
local function oneIn(units)
 if not units or units<=0 then return '—'end
 local n=C.OddsDenominator/units
 local s=n%1==0 and string.format('%d',n)or string.format('%.1f',n)
 return (s:reverse():gsub('(%d%d%d)(%d)','%1,%2'):reverse())
end
T.OneIn=oneIn
-- Aurion's real numbers: base and during the boosting event.
function T.AurionOdds()
 local base;for _,row in ipairs(T.Pool())do if row.Id=='Aurion'then base=row end end
 local event=T.BoostEvent();local boosted
 if event then for _,row in ipairs(T.Pool(event.Multiplier))do if row.Id=='Aurion'then boosted=row end end end
 return {
  Units=base and base.ChanceUnits or 0,ChanceText=base and base.ChanceText or 'Unavailable',OneIn=base and oneIn(base.ChanceUnits)or '—',
  EventId=event and event.EventId,EventName=event and event.Name,Multiplier=event and event.Multiplier,
  BoostUnits=boosted and boosted.ChanceUnits,BoostChanceText=boosted and boosted.ChanceText,BoostOneIn=boosted and oneIn(boosted.ChanceUnits),
 }
end
function T.Aurion()
 local a=T.AurionOdds()
 local text=a.ChanceText..' per spin (1 in '..a.OneIn..')'
 if a.Multiplier then text..=' · x'..string.format('%g',a.Multiplier)..' during '..a.EventName end
 return text
end
-- Every released dog of a tier row's rarities the machine may award, grouped by rank, sorted by Id.
-- The server additionally checks layer and asset readiness (RewardMachineService.TierMembers).
function T.TierMembers(row,accept)
 local groups={};local wanted={}
 for _,rank in ipairs(row.Ranks or{})do wanted[rank]=true end
 for id,def in pairs(dogs())do
  if wanted[def.Rank]and def.CanDropFromRoulette==true and id~='Aurion'and not def.Jackpot and not def.OG and def.Available~=false and not def.Reserved and(not accept or accept(def))then
   groups[def.Rank]=groups[def.Rank]or{};table.insert(groups[def.Rank],id)
  end
 end
 for _,list in pairs(groups)do table.sort(list)end
 return groups
end
-- The dog shown on a tier sector and as its preview: rotates every FeaturedPeriod seconds among
-- the members of the row's highest rarity (members = {[rank]={ids}} or a row with Breakdown).
function T.Featured(row,members,now)
 local list
 if type(row.Breakdown)=='table'then
  for _,part in ipairs(row.Breakdown)do if type(part.Members)=='table'and #part.Members>0 then list=part.Members end end
 elseif type(members)=='table'then
  local ranks=row.Ranks or{}
  for i=#ranks,1,-1 do local group=members[ranks[i]];if group and #group>0 then list=group;break end end
 end
 if not list or #list==0 then return nil end
 local turn=math.floor((now or os.time())/T.FeaturedPeriod)
 return list[(turn+(row.PrizeIndex or 0))%#list+1]
end
function T.FaceTitle(row)
 if not row then return '' end
 if row.Coins then return 'COIN BAG'end
 return row.Name or ''
end
function T.FaceSubtitle(row)
 if not row then return 'UNLOCK AT A DEEPER LAYER'end
 local chance=row.ChanceText or string.format('%.2f%%',(row.Chance or 0)*100)
 if row.Multiplier and row.Multiplier>1 then return 'x'..string.format('%g',row.Multiplier)..' · '..chance..' CHANCE'end
 return chance..' CHANCE'
end
function T.BoardRow(row)
 local chance=row.ChanceText or string.format('%.2f%%',(row.Chance or 0)*100)
 if row.Jackpot and row.Multiplier and row.Multiplier>1 then return 'RAINBOW x'..string.format('%g',row.Multiplier)..': '..row.Name..'  '..chance end
 return (row.Jackpot and 'ULTRA RARE: 'or '')..row.Name..'  '..chance
end
function T.Plaque(row)
 if not row then return 'AURION · ULTRA RARE · Unavailable'end
 if row.Multiplier and row.Multiplier>1 then return 'AURION · RAINBOW x'..string.format('%g',row.Multiplier)..' · '..row.ChanceText end
 return 'AURION · ULTRA RARE · '..row.ChanceText
end
local visibilityConnection
function T.SetupVisibility(rig)
 if not RunService:IsClient() or visibilityConnection then return end
 local drum=rig:FindFirstChild('SpinningDrum') or rig:WaitForChild('SpinningDrum',20)
 if not drum then return end
 local labels={}
 local function scanLabels()
  for i=1,#C.Rewards do
   if not labels[i] or not labels[i].Face.Parent then
    local face=drum:FindFirstChild('PrizeFace_'..i,true)
    local gui=face and face:FindFirstChild('Lettering')
    if face and face:IsA('BasePart') and gui and gui:IsA('SurfaceGui') then
     gui.AlwaysOnTop=true
     gui.Enabled=false
     gui.LightInfluence=0
     gui.MaxDistance=0
     labels[i]={Face=face,Gui=gui}
    end
   end
  end
 end
 scanLabels()
 local exclude={rig}
 local district=workspace:FindFirstChild('DOGROTS_District')
 if district then
  local plaza=district:FindFirstChild('27_RewardMachinePlaza')
  local oldMachine=plaza and plaza:FindFirstChild('RewardMachine')
  if oldMachine then table.insert(exclude,oldMachine) end
  local refresh=district:FindFirstChild('36_DistrictRefresh')
  local refreshMachine=refresh and refresh:FindFirstChild('RewardMachine')
  if refreshMachine then table.insert(exclude,refreshMachine) end
 end
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Exclude
 params.IgnoreWater=true
 params.RespectCanCollide=false
 params.FilterDescendantsInstances=exclude
 local player=game:GetService('Players').LocalPlayer
 local currentCharacter
 local baseIgnore=exclude
 local function checkVisible()
  local camera=workspace.CurrentCamera
  if not camera then return end
  local character=player.Character
  if character~=currentCharacter then
   currentCharacter=character
   local ignore=table.clone(exclude)
   if character then table.insert(ignore,character) end
   baseIgnore=ignore
  end
  local cameraPosition=camera.CFrame.Position
  for _,entry in pairs(labels) do
   local face=entry.Face
   local gui=entry.Gui
   if face.Parent and gui.Parent then
    -- Use the original surface (and its screenshot-like black plaque),
    -- hiding it only if world geometry lies between the camera and prize.
    -- The prize face is a forward-oriented plate; avoid testing its back edge.
    local towards=face.Position+face.CFrame.LookVector*(face.Size.Z*.5+.02)-cameraPosition
    gui.AlwaysOnTop=true
    params.FilterDescendantsInstances=baseIgnore
    local blocking=workspace:Raycast(cameraPosition,towards,params)
    local skips=0
    while blocking and blocking.Instance.Transparency>=0.98 and skips<10 do
     local ignore=table.clone(params.FilterDescendantsInstances)
     table.insert(ignore,blocking.Instance)
     params.FilterDescendantsInstances=ignore
     blocking=workspace:Raycast(cameraPosition,towards,params)
     skips+=1
    end
    gui.Enabled=(blocking==nil)
   end
  end
 end
 local elapsed=0
 local scanTime=0
 checkVisible()
 visibilityConnection=RunService.Heartbeat:Connect(function(dt)
  elapsed+=dt
  scanTime+=dt
  if scanTime>=1 then scanTime=0;scanLabels() end
  if elapsed<0.07 then return end
  elapsed=0
  checkVisible()
 end)
end
local function cloneDogModel(templateName)
 if not (RunService:IsServer() and ServerStorage) then return nil end
 local templates=ServerStorage:FindFirstChild('DogTemplates')
 local source=templates and templates:FindFirstChild(templateName)
 if not source then return nil end
 local model=source:Clone()
 for _,o in ipairs(model:GetDescendants())do
  if o:IsA('LuaSourceContainer') or o:IsA('ProximityPrompt') or o:IsA('Sound') or o:IsA('BillboardGui') or o:IsA('SurfaceGui') then
   o:Destroy()
  elseif o:IsA('BasePart') then
   o.Anchored=true;o.CanCollide=false;o.CanTouch=false;o.CanQuery=false
  end
 end
 local ok,rig=pcall(function()return require(script.Parent.DogRig)end)
 if ok and rig and rig.Prepare then pcall(function()rig.Prepare(model,Vector3.new(5,5,5))end) end
 return model
end
local function ensureDogSymbol(drum,index,templateName,scale)
 if not RunService:IsServer() then return end
 local sector=drum and drum:FindFirstChild('Sector_'..index)
 local symbol=sector and sector:FindFirstChild('RewardSymbol')
 if not (symbol and symbol:IsA('Model')) then return end
 if symbol:GetAttribute('DogTemplate')==templateName then return end
 local preview=cloneDogModel(templateName)
 if not preview then return end
 local target=symbol:GetPivot()
 for _,child in ipairs(symbol:GetChildren())do child:Destroy() end
 preview.Name='DogPreviewModel'
 preview.Parent=symbol
 local cf,size=preview:GetBoundingBox()
 local extent=math.max(size.X,size.Y,size.Z)
 if extent>0 then
  preview:ScaleTo(preview:GetScale()*(scale or 3.1)/extent)
  cf,size=preview:GetBoundingBox()
 end
 local targetCFrame=target*CFrame.new(0,-0.15,0)*CFrame.Angles(0,-math.pi/2,0)
 preview:PivotTo(targetCFrame*cf:Inverse()*preview:GetPivot())
 symbol:SetAttribute('DogTemplate',templateName)
end
-- Server: a rarity-tier sector shows one of its dogs, rotating every FeaturedPeriod seconds.
function T.ApplySymbols(rig,now)
 if not RunService:IsServer() or not ServerStorage then return end
 local drum=rig:FindFirstChild('SpinningDrum');if not drum then return end
 local templates=ServerStorage:FindFirstChild('DogTemplates')
 local defs=dogs()
 for prizeIndex,row in ipairs(C.Rewards)do
  if row.Kind=='DogTier'then
   local view=table.clone(row);view.PrizeIndex=prizeIndex
   local members=T.TierMembers(row,function(def)return templates~=nil and templates:FindFirstChild(def.VisualAsset or def.Id)~=nil end)
   local id=T.Featured(view,members,now)
   local def=id and defs[id]
   if def then ensureDogSymbol(drum,prizeIndex,def.VisualAsset or def.Id,3.0)end
  elseif row.Kind=='Dog'and row.Id~='Aurion'and defs[row.Id]then
   ensureDogSymbol(drum,prizeIndex,defs[row.Id].VisualAsset or row.Id,3.0)
  end
 end
end
-- keepSymbols: the server skips swapping sector dogs while the drum is mid-presentation.
function T.Apply(rig,pool,keepSymbols)
 pool=pool or T.Pool()
 local faces={}
 for _,row in ipairs(pool)do if row.PrizeIndex then faces[row.PrizeIndex]=row end end
 local board=rig:FindFirstChild('StatusBoard');local rows=board and board:FindFirstChild('OddsDisplay')and board.OddsDisplay:FindFirstChild('Rows')
 if rows then for i=1,#C.Rewards do local label=rows:FindFirstChild('Row'..i);local row=faces[i];if label then label.Visible=row~=nil;if row then label.Text=T.BoardRow(row)end end end end
 local drum=rig:FindFirstChild('SpinningDrum')
 if drum then
  for i=1,#C.Rewards do
   local face=drum:FindFirstChild('PrizeFace_'..i,true)
   local gui=face and face:FindFirstChild('Lettering')
   if gui and gui:FindFirstChild('Title') then gui.Title.Text=T.FaceTitle(C.Rewards[i]) end
   if gui and gui:FindFirstChild('Subtitle') then gui.Subtitle.Text=T.FaceSubtitle(faces[i]) end
   if gui and gui:IsA('SurfaceGui') then
    gui.AlwaysOnTop=RunService:IsClient()
    gui.LightInfluence=0
    gui.MaxDistance=0
    if RunService:IsServer() then gui.Enabled=true end
   end
  end
  if not keepSymbols then T.ApplySymbols(rig)end
 end
 if RunService:IsClient() then T.SetupVisibility(rig) end
 local aurion
 for _,row in ipairs(pool)do if row.Id=='Aurion'then aurion=row end end
 local rules=rig:FindFirstChild('TicketRules');local gui=rules and rules:FindFirstChild('Lettering')
 if gui then
  gui.Title.Text='FREE DOG TOKEN\nONE ACTIVATION'
  gui.Free.Text='FREE EVERY '..tostring(C.TicketRefillSeconds/3600)..' HOURS AFTER USE'
  gui.Capacity.Text=C.FreeOnly and('HOLDS '..C.TicketCapacity..' FREE DOG TOKEN')or 'MORE SPINS: LUCKY SPIN PACKS IN THE SHOP'
 end
 local displays=rig:FindFirstChild('RewardVitrines');local tower=displays and displays:FindFirstChild('TreasureTower')
 local plaque=tower and tower:FindFirstChild('PrizePlaque')
 if plaque and plaque:FindFirstChild('Lettering')then plaque.Lettering.Title.Text=T.Plaque(aurion)end
end
return T
