-- MY BEST FINDS stand contents (the stand itself: PlotAppearance.Showcase). Trophy copies are
-- presentation only; they never consume or create inventory.
--   Cases: ShowcaseRules.Layout(p) - the finds the player pinned (Features.Showcase) and, in every
--          other case, the automatic pick (owned finds and find records, rarest first).
--   Dog:   the best dog the player owns, on the round plinth.
-- Runs on every Runtime.Project, so each case is rebuilt only when its token changes. Case
-- attributes (Rarity, Effect, Mutation, Filled, Pinned) drive the client rarity effects
-- (StarterPlayerScripts.PlotCosmetics); every exhibit carries RestPivot for its slow turn.
local S={}
local RS=game:GetService('ReplicatedStorage')
local Defs=require(RS.DogEconomy.DogDefinitions)
local Config=require(RS.DogEconomy.Config)
local Rules=require(RS.DogEconomy.ShowcaseRules)
local function rank(d)return (Defs[d.DogId]or{}).Rank or table.find(Config.Rarities,d.Rarity)or 0 end
local function better(a,b,key)
 if not b then return true end
 local av,bv=tonumber(a[key])or 0,tonumber(b[key])or 0
 return av>bv or av==bv and tostring(a.ItemUid or a.DogUid)<tostring(b.ItemUid or b.DogUid)
end
-- Legacy selection (records + inventory): best find, best relic and best dog.
function S.Select(p)
 local stats=p.Stats or {};local find,relic=stats.BestShowcaseFind,stats.BestShowcaseRelic
 local function offer(x)
  if not x or not x.ItemId then return end
  if x.Class=='Artifact'or x.Class=='Special'or x.Class=='Secret'then if better(x,relic,'SellValue')then relic=x end
  elseif better(x,find,'SellValue')then find=x end
 end
 offer(stats.MostValuable);offer(stats.Heaviest);offer(stats.Rarest)
 for _,x in pairs(p.Items or {})do offer(x)end
 for _,x in ipairs(p.DiscoveryFeed or {})do offer(x)end
 return {Find=find,Dog=S.BestDog(p),Relic=relic}
end
function S.BestDog(p)
 local dog
 for _,d in pairs(p.Dogs or {})do if d.OwnerUserId==p.UserId and d.State~='Walking'then
  local dr=rank(d);local br=dog and rank(dog)or -1
  if dr>br or dr==br and(better(d,dog,'Mastery'))then dog=d end
 end end
 return dog
end
local function bounds(model)
 local lo,hi=Vector3.one*math.huge,Vector3.one*-math.huge
 for _,p in ipairs(model:GetDescendants())do if p:IsA('BasePart')and p.Transparency<1 then
  for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do local q=p.CFrame:PointToWorldSpace(p.Size*Vector3.new(x,y,z)/2);lo=lo:Min(q);hi=hi:Max(q)end end end
 end end
 return lo,hi
end
local function strip(model)
 for _,o in ipairs(model:GetDescendants())do
  if o:IsA('LuaSourceContainer')or o:IsA('LayerCollector')or o:IsA('ProximityPrompt')or o:IsA('Sound')or o:IsA('ParticleEmitter')then o:Destroy()
  elseif o:IsA('BasePart')then o.Anchored=true;o.CanCollide=false;o.CanTouch=false;o.CanQuery=false end
 end
end
-- Scales model to fit box (Vector3) and stands it centred on the top of `surface`.
local function fit(model,surface,box)
 model:PivotTo(CFrame.identity);local lo,hi=bounds(model);local size=hi-lo
 if size.Y<=0 or size.Y==math.huge or size.X==math.huge then return false end
 model:ScaleTo(model:GetScale()*math.min(box.X/math.max(.01,size.X),box.Y/math.max(.01,size.Y),box.Z/math.max(.01,size.Z)))
 lo,hi=bounds(model)
 model:PivotTo(surface.CFrame*CFrame.new(-(lo.X+hi.X)/2,surface.Size.Y/2+.04-lo.Y,-(lo.Z+hi.Z)/2))
 return true
end
local function itemModel(row,surface)
 local visuals=require(RS.DogEconomy.DiscoveryVisuals)
 -- Full detail for the showcase (the second argument is ignored by older DiscoveryVisuals).
 local ok,model=pcall(function()return(visuals.Clone::any)({ItemId=row.ItemId,Mutation=row.Mutation,WeightKg=row.WeightKg},{Lod=0})end)
 if not ok or not model then return nil end
 strip(model)
 local box=surface:GetAttribute('ExhibitSize')
 if typeof(box)~='Vector3'then box=Vector3.new(2.2,2.3,2.2)end
 if not fit(model,surface,box)then model:Destroy();return nil end
 model.Name='Exhibit';model:SetAttribute('PlotShowcase',true);model:SetAttribute('RestPivot',model:GetPivot())
 model:SetAttribute('ItemId',row.ItemId)
 return model
end
local TINT={Shiny=Color3.fromRGB(210,235,255),Golden=Color3.fromRGB(255,193,44),Corrupted=Color3.fromRGB(188,56,81),Glitched=Color3.fromRGB(210,87,255),Void=Color3.fromRGB(104,38,164)}
local function dogModel(row,surface)
 local def=Defs[row.DogId];local templates=game:GetService('ServerStorage'):FindFirstChild('DogTemplates')
 local source=def and templates and templates:FindFirstChild(def.VisualAsset or row.DogId)
 local model=source and source:Clone()
 if not model then return nil end
 strip(model)
 if not fit(model,surface,Vector3.new(3.6,3.9,3.6))then model:Destroy();return nil end
 if TINT[row.Variant]then for _,o in model:GetDescendants()do if o:IsA('BasePart')then o.Color=o.Color:Lerp(TINT[row.Variant],.38)end end end
 model.Name='Exhibit';model:SetAttribute('PlotShowcase',true);return model
end
local function plate(case,row)
 local nameplate=case:FindFirstChild('Nameplate');local gui=nameplate and nameplate:FindFirstChild('Plate')
 if not gui then return end
 local name,rarity,weight=gui:FindFirstChild('ItemName'),gui:FindFirstChild('Rarity'),gui:FindFirstChild('Weight')
 if name then name.Text=row and row.DisplayName or'YOUR NEXT RECORD AWAITS'end
 if rarity then
  rarity.Text=row and string.upper(row.Rarity)or''
  rarity.TextColor3=row and(Rules.Colors[row.Effect]or Rules.Colors[row.Rarity])or Color3.new(1,1,1)
 end
 if weight then weight.Text=row and string.format('%.4g kg',row.WeightKg)or''end
end
function S.Clear(yard)
 S.Reconcile(yard,{UserId=0,Dogs={},Items={},Stats={}})
end
function S.Reconcile(yard,p)
 local deco=yard:FindFirstChild('PlotDevelopment');local stand=deco and deco:FindFirstChild('BestFinds');if not stand then return end
 local cases=stand:FindFirstChild('Cases')
 if cases then
  local layout=Rules.Layout(p)
  for _,case in ipairs(cases:GetChildren())do
   local i=case:GetAttribute('Slot');local row=type(i)=='number'and layout.Slots[i]or nil
   local surface=case:FindFirstChild('Platform')
   local token=row and table.concat({row.Uid,row.ItemId,row.Mutation,string.format('%.6g',row.WeightKg)},':')or'empty'
   if surface and case:GetAttribute('ExhibitToken')~=token then
    local old=case:FindFirstChild('Exhibit');if old then old:Destroy()end
    local model=row and itemModel(row,surface)
    if model then model.Parent=case end
    case:SetAttribute('ExhibitToken',token)
    plate(case,row)
   end
   -- Cheap attribute writes (only on change): the client effects follow them.
   local function put(k,v)if case:GetAttribute(k)~=v then case:SetAttribute(k,v)end end
   put('Filled',row~=nil);put('Rarity',row and row.Rarity or nil);put('Effect',row and row.Effect or nil)
   put('Mutation',row and row.Mutation or nil);put('Pinned',row and row.Pinned or false);put('ItemUid',row and row.Uid or nil)
  end
 end
 local slots=stand:FindFirstChild('Slots');local slot=slots and slots:FindFirstChild('Dog')
 if slot then
  local row=S.BestDog(p)
  local token=row and tostring(row.DogUid)..':'..tostring(row.Variant)or'empty'
  if slot:GetAttribute('ExhibitToken')~=token then
   local old=slot:FindFirstChild('Exhibit');if old then old:Destroy()end
   local model=row and dogModel(row,slot)
   if model then model.Parent=slot end
   slot:SetAttribute('ExhibitToken',token)
  end
 end
end
return S
