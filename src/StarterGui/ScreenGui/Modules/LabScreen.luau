-- Genetics Lab window (UI kit, docs/UIKIT.md). Three obvious steps:
--   1 PICK A DOG     every species of the catalogue (owned ones first), search, rarity chips, sort; tapping an
--                    owned species lists your copies with their state and one-tap fixes (unlock, remove from kennel)
--   2 CHOOSE ACTION  big cards: MUTATE, GENE TARGETING, EXTRACT DNA, ASCEND, RECIPES, each with its inputs, cost,
--                    what you get and the odds, computed by ReplicatedStorage.LabGenetics (the server's own rules)
--   3 CONFIRM        the server preview in a kit modal (consumed dogs as cards, hold-to-confirm for valuable dogs),
--                    then the chamber cinematic (LabPresentation) and the result card with the cooldown.
-- Entry points: the terminal prompt (DogEconomyOpen 'Lab'), N.OpenPage('Lab') / N.OpenScreen('Lab') (GUIIntegration
-- routes them to LabScreen.Open) and Menus' legacy 'Lab' page (LabScreen.Build opens the window).
-- Server protocol: LabInfo / LabPreview / LabCommit (Economy.LabService). Text: Localization.Lab (self-localized,
-- labels carry NoTranslate; dog and item names stay translatable for DOGROTS_AutoTranslateUI).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Kit=require(script.Parent.Kit)
local C=require(RS.LabConfig)
local G=require(RS.LabGenetics)
local Access=require(RS.LabAccess)
local Audio=require(RS.LabAudioConfig)
local Defs=require(RS.DogEconomy.DogDefinitions)
local ItemDefs=require(RS.DogEconomy.ItemDefinitions)
local Base=require(RS.DogEconomy.Config)
local Dict=require(RS:WaitForChild('Localization'):WaitForChild('Lab'))
local Theme,Format=Kit.Theme,Kit.Format
local P=Theme.Colors
local ACCENT=P.purple
local Z=3

local S={}
S.Destination='Mutation lab' -- DistrictGuide name of the lab (N.Navigate)

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function ru()return Kit.Lang()=='ru'end
local function T(en)
 if ru()then return Dict.UI[en]or Dict.Exact[en]or en end
 return en
end
local function F(en,...)
 local pattern=en
 if ru()then pattern=Dict.Templates[en]or en end
 return string.format(pattern,...)
end
-- A server reply in the player's language (exact entries, then the lab patterns).
local function said(text)
 text=tostring(text or'')
 if not ru()then return text end
 local exact=Dict.Exact[text]or Dict.UI[text]
 if exact then return exact end
 for _,rule in ipairs(Dict.Patterns)do
  local out,n=string.gsub(text,rule[1],rule[2])
  if n>0 then return out end
 end
 return text
end
local function dnaName(key)return T(C.DNA[key]or tostring(key))end
local function variantName(v)return T(v or'Normal')end
local function itemName(id)local def=ItemDefs[id];return T(def and def.DisplayName or tostring(id))end
local probes={} -- DogId -> hidden TextLabel holding the (auto-translated) display name
-- A dog's name as the player sees it on the cards (for self-localized sentences).
local function dogName(id)
 local probe=probes[id]
 if probe and probe.Parent then return probe.Text end
 local def=Defs[id];return def and def.DisplayName or tostring(id)
end
local function pct(x)
 x=tonumber(x)or 0
 if x>=10 then return string.format('%.0f%%',x)elseif x>=1 then return string.format('%.1f%%',x)elseif x>0 then return string.format('%.2f%%',x)end
 return '0%'
end
local function hex(c)return Theme.Hex(c)end
local function colored(text,color)return '<font color="'..hex(color)..'">'..text..'</font>'end

-- Lower-case for search, Cyrillic included (string.lower only folds ASCII).
local function fold(s)
 local out={}
 for _,code in utf8.codes(tostring(s or''))do
  if code>=0x410 and code<=0x42F then code+=0x20 elseif code==0x401 then code=0x451 elseif code>=65 and code<=90 then code+=32 end
  table.insert(out,utf8.char(code))
 end
 return table.concat(out)
end

-- Upper-case, Cyrillic included.
local function upper(s)
 local out={}
 for _,code in utf8.codes(tostring(s or''))do
  if code>=0x430 and code<=0x44F then code-=0x20 elseif code==0x451 then code=0x401 elseif code>=97 and code<=122 then code-=32 end
  table.insert(out,utf8.char(code))
 end
 return table.concat(out)
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st:any={
 View='loading',Step=1,Species=nil,DogUid=nil,Action=nil,Catalyst=nil,Stabilizer=nil,RecipeKey=nil,Picks={},
 Search='',Rarities={},OwnedOnly=false,Sort='owned',Desc=true,
 Info=nil,Snapshot=nil,Busy=false,CooldownEndsAt=0,Result=nil,Message=nil,Owned={},Ready={},Confirming=false,OpenToken=0,
}
S.State=st
local ui:any=nil
local win:any=nil

local SPECIES={}
for _,def in pairs(Defs)do if type(def)=='table'and def.Id and def.Rank then table.insert(SPECIES,def)end end
table.sort(SPECIES,function(a,b)return(a.Index or 0)<(b.Index or 0)end)
local RARITIES={'Common','Rare','Epic','Legendary','Mythic','Secret'}
local VARIANT_RANK={};for i,v in ipairs(Base.Variants)do VARIANT_RANK[v.Name]=i end

local ACTIONS={
 {Id='Mutation',Proc='Mutation',Title='MUTATE',Glyph='🧪',Color=P.purple,Desc='Reroll the variant. Your dog always survives.',Confirm='START MUTATION'},
 {Id='Targeting',Proc='Targeting',Title='GENE TARGETING',Glyph='🎯',Color=P.blue,Desc='A catalyst pushes the odds toward one variant.',Confirm='START MUTATION'},
 {Id='Extraction',Proc='Extraction',Title='EXTRACT DNA',Glyph='🧬',Color=P.red,Desc='Split this dog into DNA for recipes. The dog is consumed.',Confirm='EXTRACT'},
 {Id='Ascend',Proc='Fusion',Title='ASCEND',Glyph='⬆',Color=P.gold,Desc='Merge 2 copies into this dog: +1 Ascension, more income.',Confirm='MERGE'},
 {Id='Recipes',Proc='Fusion',Title='RECIPES',Glyph='📖',Color=P.green,Desc='Combine dogs, DNA and catalysts into a new dog.',Confirm='START'},
}
local ACTION_BY={};for _,a in ipairs(ACTIONS)do ACTION_BY[a.Id]=a end

local function profile()return st.Snapshot and st.Snapshot.Profile or nil end
local function dogsOf(p)return type(p)=='table'and type(p.Dogs)=='table'and p.Dogs or{}end
local function labOf(p)return type(p)=='table'and type(p.Lab)=='table'and p.Lab or{DNA={},Tier=1}end
local function dnaOf(p)local l=labOf(p);return type(l.DNA)=='table'and l.DNA or{}end
local function tier()
 if st.Info and st.Info.Tier then return st.Info.Tier end
 return labOf(profile()).Tier or 1
end
local function selectedDog()
 local d=st.DogUid and dogsOf(profile())[st.DogUid]
 return type(d)=='table'and d or nil
end
local function cooling()return Kit.Now()<(st.CooldownEndsAt or 0)end

local NetModule=nil
local function net()
 NetModule=NetModule or require(script.Parent.Net)
 return NetModule
end
local function nav()
 local ok,n=pcall(require,script.Parent.GUIIntegration)
 return ok and n or nil
end
local function request(action,args)
 local ok,result=net().Request(action,args)
 return ok,result
end
local function toast(text,kind)Kit.Toast(text,{Kind=kind or'info',NoTranslate=true})end
local function cue(name)
 local lab=Access.Model()
 local anchor=lab and lab:FindFirstChild('AudioAnchor')
 if name=='Console'and anchor then Audio.Play(name,anchor)else Audio.Play(name,nil)end
end

------------------------------------------------------------------------------------------------
-- Small builders
------------------------------------------------------------------------------------------------
local function place(o,x,y,w,h)
 o.Position=UDim2.fromOffset(math.floor(x),math.floor(y))
 o.Size=UDim2.fromOffset(math.max(0,math.floor(w)),math.max(0,math.floor(h)))
end
local function label(parent,props)
 props.NoTranslate=props.NoTranslate~=false
 props.ZIndex=props.ZIndex or Z+1
 props.Size=props.Size or UDim2.fromOffset(10,10)
 return Kit.Text(parent,props)
end
local function panel(parent,name,z,color)
 local f=Kit.New('Frame',{Name=name,BackgroundColor3=color or Theme.White,BorderSizePixel=0,ZIndex=z or Z},parent)
 Kit.Corner(f,Theme.Radius.Card)
 Kit.Stroke(f,P.edge,2,.6)
 return f
end
local function frame(parent,name,z)
 return Kit.New('Frame',{Name=name,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=z or Z,Size=UDim2.fromOffset(10,10)},parent)
end

-- "6.5K coins · 5 bones · 2 Common DNA" with the parts the player cannot afford in red.
local function costText(cost)
 local p=profile();local parts={}
 local cash,bones=tonumber(p and p.Cash)or 0,tonumber(p and p.Bones)or 0
 local red=P.red
 if(cost.Cash or 0)>0 then
  local t=F('%s coins',Format.Short(cost.Cash,1))
  table.insert(parts,cash>=cost.Cash and t or colored(t,red))
 end
 if(cost.Bones or 0)>0 then
  local t=F('%d bones',cost.Bones)
  table.insert(parts,bones>=cost.Bones and t or colored(t,red))
 end
 local dna=dnaOf(p)
 for _,k in ipairs(G.SortedKeys(cost.DNA))do
  local t=F('%d %s',cost.DNA[k],dnaName(k))
  table.insert(parts,(tonumber(dna[k])or 0)>=cost.DNA[k]and t or colored(t,red))
 end
 if #parts==0 then return T('FREE')end
 return table.concat(parts,' · ')
end
local function affordable(cost)
 local p=profile();if not p then return false,T('Loading…')end
 if(tonumber(p.Cash)or 0)<(cost.Cash or 0)then return false,T('Not enough coins')end
 if(tonumber(p.Bones)or 0)<(cost.Bones or 0)then return false,T('Not enough bones')end
 local dna=dnaOf(p)
 for _,k in ipairs(G.SortedKeys(cost.DNA))do
  if(tonumber(dna[k])or 0)<cost.DNA[k]then return false,F('Not enough %s',dnaName(k))end
 end
 return true,nil
end
local function rewardsText(rewards,plus)
 local parts={}
 for _,k in ipairs(G.SortedKeys(rewards))do table.insert(parts,(plus and'+'or'')..tostring(rewards[k])..' '..dnaName(k))end
 return table.concat(parts,' · ')
end
local function sourcesText(id)
 local names={DogLine=T('DOG LINE'),LuckyBlock=T('Lucky Blocks'),DogOMatic=T('DOG-O-MATIC'),Excavation=T('deep excavations'),ServerArrival=T('a rare server arrival')}
 local list={}
 for _,k in ipairs(G.Sources(id))do table.insert(list,names[k]or k)end
 if #list==0 then return T('Not owned yet')end
 return F('Not owned · find it at %s',table.concat(list,', '))
end
local REASON_WORDS={Rarity='Epic or rarer',Variant='mutated variant',Ascension='ascended',Mastery='high mastery',Collectible='collectible edition',LabMade='lab-made',Artifacts='wears artifacts'}
local function reasonsText(reasons)
 local list={}
 for _,r in ipairs(reasons or{})do table.insert(list,T(REASON_WORDS[r]or r))end
 return table.concat(list,', ')
end
local STATUS={Walking='ON THE WAY',Locked='LOCKED',Kennel='IN KENNEL',Busy='WORKING',Favorite='FAVORITE',Display='ON DISPLAY',Unavailable='UNAVAILABLE',Missing='GONE'}

-- Odds bar: coloured segments by chance + a legend of the mutated rows.
local function oddsBar(parent,z)
 local o:any={}
 o.Root=frame(parent,'Odds',z)
 o.Track=Kit.New('Frame',{Name='Track',BackgroundColor3=P.secondary,BorderSizePixel=0,ZIndex=z+1,ClipsDescendants=true},o.Root)
 Kit.Corner(o.Track,'pill')
 o.Segments={}
 for i,v in ipairs(Base.Variants)do
  o.Segments[v.Name]=Kit.New('Frame',{Name='Seg_'..v.Name,BackgroundColor3=G.VariantColor(v.Name),BorderSizePixel=0,ZIndex=z+2,LayoutOrder=i},o.Track)
 end
 o.Legend=label(o.Root,{Name='Legend',TextSize=14,Rich=true,Color=Theme.InkMuted,Scaled=true,MinTextSize=9,ZIndex=z+1})
 function o.Set(chances,w)
  place(o.Track,0,0,w,12)
  local x=0;local parts={}
  local shown={}
  for _,c in ipairs(chances or{})do shown[c.Name]=c.Percent end
  for _,v in ipairs(Base.Variants)do
   local seg=o.Segments[v.Name];local share=(shown[v.Name]or 0)/100
   local width=share>0 and math.max(3,math.floor(w*share+.5))or 0
   if v.Name=='Normal'then seg.BackgroundColor3=Color3.fromRGB(196,214,226)end
   place(seg,x,0,width,12);x+=width
   if v.Name~='Normal'and(shown[v.Name]or 0)>0 then table.insert(parts,colored(variantName(v.Name)..' '..pct(shown[v.Name]),Theme.Darken(G.VariantColor(v.Name),.25)))end
  end
  o.Legend.Text=table.concat(parts,'  ')
  place(o.Legend,0,16,w,18)
 end
 return o
end

------------------------------------------------------------------------------------------------
-- Data: species list, owned copies
------------------------------------------------------------------------------------------------
local function computeOwned()
 local by,ready={},{}
 local p=profile()
 for _,d in pairs(dogsOf(p))do
  if type(d)=='table'and d.DogId then
   by[d.DogId]=by[d.DogId]or{};table.insert(by[d.DogId],d)
   if G.Check(p,d)then ready[d.DogId]=(ready[d.DogId]or 0)+1 end
  end
 end
 st.Owned,st.Ready=by,ready
end
local function bestVariant(list)
 local best='Normal'
 for _,d in ipairs(list or{})do if(VARIANT_RANK[d.Variant or'Normal']or 1)>(VARIANT_RANK[best]or 1)then best=d.Variant end end
 return best
end
local function speciesCard(def)
 local owned=st.Owned[def.Id];local n=owned and #owned or 0;local ready=st.Ready[def.Id]or 0
 local stats
 if n>0 then stats={{Text='×'..n},{Text=F('%d READY',ready),Color=ready>0 and P.green or Theme.Disabled}}
 else stats={{Text=T('NOT OWNED')}}end
 return {Id=def.Id,Name=def.DisplayName,Rarity=def.Rarity,Preview={Kind='Dog',DogId=def.Id,Variant=bestVariant(owned)},
  Stats=stats,Selected=st.Species==def.Id,Disabled=n==0,DisabledReason=n==0 and sourcesText(def.Id)or nil,
  Subtitle=n>0 and F('Owned %d · ready %d',n,ready)or sourcesText(def.Id)}
end
local function matchesSearch(def,query)
 if query==''then return true end
 local hay=fold(def.DisplayName..' '..def.Id)
 local probe=ui and ui.Probes[def.Id]
 if probe then hay=hay..' '..fold(probe.Text)end
 return string.find(hay,query,1,true)~=nil
end
local function filteredSpecies()
 local query=fold(st.Search or''):gsub('^%s+',''):gsub('%s+$','')
 local list={}
 local anyRarity=next(st.Rarities)~=nil
 for _,def in ipairs(SPECIES)do
  local owned=st.Owned[def.Id]
  if(not anyRarity or st.Rarities[def.Rarity])and(not st.OwnedOnly or owned)and matchesSearch(def,query)then table.insert(list,def)end
 end
 local sort,desc=st.Sort,st.Desc
 table.sort(list,function(a,b)
  local x,y
  if sort=='name'then
   x,y=fold(a.DisplayName),fold(b.DisplayName)
   if x~=y then if desc then return x>y end;return x<y end
  elseif sort=='rarity'then
   if a.Rank~=b.Rank then if desc then return a.Rank>b.Rank end;return a.Rank<b.Rank end
  else
   local oa,ob=st.Owned[a.Id]and #st.Owned[a.Id]or 0,st.Owned[b.Id]and #st.Owned[b.Id]or 0
   if(oa>0)~=(ob>0)then return oa>0 end
   local ra,rb=st.Ready[a.Id]or 0,st.Ready[b.Id]or 0
   if(ra>0)~=(rb>0)then return ra>0 end
   if a.Rank~=b.Rank then if desc then return a.Rank>b.Rank end;return a.Rank<b.Rank end
  end
  return(a.Index or 0)<(b.Index or 0)
 end)
 return list
end
local function copiesOf(id)
 local p=profile();local list=table.clone(st.Owned[id]or{})
 table.sort(list,function(a,b)
  local ka,kb=G.Check(p,a)and 1 or 0,G.Check(p,b)and 1 or 0
  if ka~=kb then return ka>kb end
  local aa,ab=tonumber(a.AscensionLevel)or 0,tonumber(b.AscensionLevel)or 0
  if aa~=ab then return aa>ab end
  local va,vb=VARIANT_RANK[a.Variant or'Normal']or 1,VARIANT_RANK[b.Variant or'Normal']or 1
  if va~=vb then return va>vb end
  local ma,mb=tonumber(a.Mastery)or 0,tonumber(b.Mastery)or 0
  if ma~=mb then return ma>mb end
  return a.DogUid<b.DogUid
 end)
 return list
end
local function dogCard(d,selected)
 local p=profile()
 local ok,code,message=G.Check(p,d)
 local stats={{Text='★'..math.floor(tonumber(d.Mastery)or 0)}}
 if(tonumber(d.AscensionLevel)or 0)>0 then table.insert(stats,{Text='A'..d.AscensionLevel,Color=P.gold})end
 table.insert(stats,ok and{Text=T('READY'),Color=P.green}or{Text=T(STATUS[code]or'UNAVAILABLE'),Color=Theme.Disabled})
 return {Id=d.DogUid,Name=d.DisplayName or(Defs[d.DogId]and Defs[d.DogId].DisplayName)or d.DogId,Rarity=d.Rarity or(Defs[d.DogId]and Defs[d.DogId].Rarity),
  Variant=d.Variant,Preview={Kind='Dog',DogId=d.DogId,Variant=d.Variant},Stats=stats,Selected=selected==true,
  Disabled=not ok,DisabledReason=not ok and said(message)or nil}
end

------------------------------------------------------------------------------------------------
-- Action evaluation (what each card shows, and the preview arguments)
------------------------------------------------------------------------------------------------
local function rows()return st.Info and st.Info.VariantRows or Base.Variants end
local function groupById(groups,id)
 for _,g in ipairs(groups)do if g.ItemId==id then return g end end
 return nil
end
local function recipeRows()
 local out={}
 for _,row in ipairs(st.Info and st.Info.Recipes or{})do if row.RecipeId~='ASCEND'then table.insert(out,row)end end
 return out
end
local function recipeByKey(key)
 for _,row in ipairs(recipeRows())do if row.Key==key then return row end end
 return nil
end
local function missingText(m)
 if m.Kind=='Dog'then
  local name=dogName(m.DogId)
  if(m.MinimumMastery or 0)>0 then return F('Needs a ready %s with mastery %d+',name,m.MinimumMastery)end
  return F('Needs a ready %s',name)
 elseif m.Kind=='Tag'then return F('Needs a ready dog with %s genes',dnaName(m.Tag))
 elseif m.Kind=='Item'then return F('Needs %s (%d/%d)',itemName(m.ItemId),m.Have,m.Need)
 elseif m.Kind=='DNA'then return F('Needs %s (%d/%d)',dnaName(m.Key),m.Have,m.Need)end
 return T('Something is missing')
end

local function evaluate(id)
 local action=ACTION_BY[id];local proc=G.Procedure(action.Proc)
 local p=profile();local d=selectedDog()
 local e={Id=id,Action=action}
 if not p then e.Reason=T('Loading…');return e end
 local needTier=proc and proc.Tier or 1
 if tier()<needTier then
  e.Locked=true;e.Reason=F('Unlocks at player level %d',proc and proc.Level or 1);return e
 end
 if id~='Recipes'and not d then e.Reason=T('Pick a dog first');return e end
 if id=='Mutation'or id=='Targeting'then
  local stabilizers=G.Stabilizers(p);local stab=st.Stabilizer and groupById(stabilizers,st.Stabilizer)
  local bonus=stab and stab.Bonus or 0
  e.Stabilizers=stabilizers;e.Stab=stab
  local target,catalyst=nil,nil
  if id=='Targeting'then
   local catalysts=G.Catalysts(p);e.Catalysts=catalysts
   catalyst=st.Catalyst and groupById(catalysts,st.Catalyst)or catalysts[1]
   if catalyst then st.Catalyst=catalyst.ItemId;target=catalyst.Affinity end
   e.Catalyst=catalyst
  end
  local stability=G.Stability(id,d,bonus)
  e.Chances=G.Chances(rows(),target,stability,bonus)
  e.Stability=stability
  local free=id=='Mutation'and not(st.Info and st.Info.TutorialComplete)and not labOf(p).TutorialComplete
  e.Cost=free and{Cash=0,Bones=0,DNA={}}or G.Cost(id,d)
  e.Free=free
  e.Gain=T('Dog survives · new variant')
  if(d.Variant or'Normal')~='Normal'then e.Warning=F('Your %s variant can be lost: rerolls usually land on Normal.',variantName(d.Variant))end
  if id=='Targeting'and not catalyst then e.Reason=T('Needs an affinity catalyst: dig up Golden Scarabs, Shiny Marbles, Cursed Bones…')end
  local items={};if catalyst then items={catalyst.Uids[1]}end
  e.Args={Procedure=id,Uids={d.DogUid},PrimaryUid=d.DogUid,Items=items,StabilizerUid=stab and stab.Uids[1]or''}
 elseif id=='Extraction'then
  e.Cost=G.Cost('Extraction',d);e.Rewards=G.Extraction(d)
  e.Gain=F('You get %s',rewardsText(e.Rewards,true))
  e.Warning=T('This dog is consumed.')
  e.Consumes={d}
  e.Args={Procedure='Extraction',Uids={d.DogUid},PrimaryUid=d.DogUid,Items={},StabilizerUid=''}
 elseif id=='Ascend'then
  local level=tonumber(d.AscensionLevel)or 0
  e.Cost=G.Cost('Ascend',d)
  local maxLevel=#Base.Ascension-1
  local dups,blocked=G.Duplicates(p,d)
  e.Duplicates=dups;e.Blocked=blocked
  if level>=maxLevel then e.Reason=T('Maximum Ascension reached');e.Gain=F('Ascension %d (max)',level)
  else
   e.Gain=F('Ascension %d → %d · income +%d%%',level,level+1,math.floor(((Base.Ascension[level+2]or 0)-(Base.Ascension[level+1]or 0))*100+.5))
   if #dups<2 then
    e.Reason=blocked>0 and F('Needs 2 ready copies of this dog with Ascension %d+ (ready %d, busy %d)',level,#dups,blocked)or F('Needs 2 more copies of this dog with Ascension %d+ (you have %d)',level,#dups)
   else
    e.Consumes={dups[1],dups[2]}
    e.Args={Procedure='Fusion',RecipeId='ASCEND',Uids={d.DogUid,dups[1].DogUid,dups[2].DogUid},PrimaryUid=d.DogUid,Items={},StabilizerUid=''}
   end
  end
 elseif id=='Recipes'then
  local list=recipeRows();e.Recipes=list
  if not st.Info then e.Reason=T('Loading…');return e end
  if #list==0 then e.Reason=T('No recipes unlocked yet');return e end
  local row=st.RecipeKey and recipeByKey(st.RecipeKey)
  e.Recipe=row
  if not row then e.Reason=T('Choose a recipe below');return e end
  local cost={Cash=row.Costs and row.Costs.Cash or 0,Bones=row.Costs and row.Costs.Bones or 0,DNA=row.RequiredDNA or{}}
  if row.Done then e.Reason=T('Already discovered (one-time recipe)');return e end
  local pick=st.Picks[row.Key]
  if row.Known then
   local fill=G.FillRecipe(p,row,st.DogUid)
   e.Fill=fill
   if pick then fill={Uids=pick.Uids,Items=pick.Items,Missing={}};e.Manual=true end
   e.Cost=cost
   e.Gain=F('%s chance of success',pct(row.SuccessChance or 0))
   if #fill.Missing>0 then e.Reason=missingText(fill.Missing[1])end
   local consumes={}
   for _,uid in ipairs(fill.Uids)do local dog=dogsOf(p)[uid];if dog then table.insert(consumes,dog)end end
   e.Consumes=consumes
   e.Args={Procedure=row.Procedure,RecipeId=row.RecipeId,Uids=fill.Uids,PrimaryUid=fill.Uids[1],Items=fill.Items,StabilizerUid=''}
  else
   e.Cost={Cash=0,Bones=0,DNA={}}
   e.Gain=T('Unknown result · the recipe DNA is taken automatically')
   if not pick or #pick.Uids<2 then e.Reason=T('Tap EXPERIMENT and choose the dogs and catalysts')
   else
    local consumes={}
    for _,uid in ipairs(pick.Uids)do local dog=dogsOf(p)[uid];if dog then table.insert(consumes,dog)end end
    e.Consumes=consumes
    e.Args={Procedure=row.Procedure,RecipeId='DISCOVER',Uids=pick.Uids,PrimaryUid=pick.Uids[1],Items=pick.Items,StabilizerUid=''}
   end
  end
 end
 if e.Cost and not e.Reason then
  local ok,why=affordable(e.Cost)
  if not ok then e.Reason=why end
 end
 return e
end

------------------------------------------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------------------------------------------
local refresh,layout,setView,goStep,renderBar,renderActions,renderPanel,renderSteps,openConfirm,showResult,loadInfo

------------------------------------------------------------------------------------------------
-- Instances panel rows (a card + a fix / pick button)
------------------------------------------------------------------------------------------------
local function rowCreate(cell:any)
 local holder=frame(cell,'CardHolder',cell.ZIndex+1)
 local card=Kit.DogCard.new(holder)
 local o:any={Holder=holder,Card=card,Dog=nil}
 o.Button=Kit.Button(cell,{Name='RowAction',Text='',Style='success',TextSize=15,ZIndex=cell.ZIndex+3,NoTranslate=true,Size=UDim2.fromOffset(96,40)})
 card.OnClick=function()
  local d=o.Dog
  if d then S.PickDog(d.DogUid)end
 end
 return o
end
local function rowLayout(o,w,h)
 local bw=w<420 and 96 or 112
 place(o.Holder,0,0,w-bw-8,h)
 o.Card:Layout(w-bw-8,h)
 place(o.Button.Instance,w-bw,(h-40)/2,bw,40)
end
local function rowBind(o,d)
 o.Dog=d
 local p=profile()
 o.Card:Bind(dogCard(d,st.DogUid==d.DogUid))
 local ok,code=G.Check(p,d)
 local fix=not ok and G.Fix(code,d)
 local button=o.Button
 button:SetBusy(false)
 if ok then
  button:SetText(st.DogUid==d.DogUid and T('PICKED')or T('PICK'));button:SetStyle('success');button:SetDisabled(false)
  button:SetOnClick(function()S.PickDog(d.DogUid)end)
 elseif fix then
  button:SetText(T(fix.Text));button:SetStyle('gold');button:SetDisabled(false)
  button:SetOnClick(function()
   if button.Busy then return end
   button:SetBusy(true);cue('Select')
   local done,result=request(fix.Action,fix.Args)
   button:SetBusy(false)
   if done then toast(T('Done! The dog is ready for the lab.'),'success')
   else toast(said(result),'error');cue('Deny')end
  end)
 else
  button:SetText(T(STATUS[code]or'UNAVAILABLE'));button:SetStyle('secondary');button:SetDisabled(true)
  button:SetOnClick(nil)
 end
end

------------------------------------------------------------------------------------------------
-- Action cards
------------------------------------------------------------------------------------------------
local function chipsOptions(groups,kind)
 local list={}
 if kind=='stab'then table.insert(list,{Id='none',Text=T('NO CRYSTAL'),NoTranslate=true})end
 for _,g in ipairs(groups)do
  local text
  if kind=='stab'then text=F('%s +%d ×%d',itemName(g.ItemId),g.Bonus,#g.Uids)
  else text=F('%s ×%d → %s',itemName(g.ItemId),#g.Uids,variantName(g.Affinity.Mutation))end
  table.insert(list,{Id=g.ItemId,Text=text,NoTranslate=true,Color=kind=='cat'and G.VariantColor(g.Affinity.Mutation)or nil})
 end
 return list
end
local function signature(groups)
 local parts={}
 for _,g in ipairs(groups or{})do table.insert(parts,g.ItemId..'='..#g.Uids)end
 return table.concat(parts,',')..'|'..Kit.Lang()
end

local function makeCard(action,parent)
 local c:any={Action=action}
 local root=Kit.New('TextButton',{Name='Action_'..action.Id,Text='',AutoButtonColor=false,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=Z+1},parent)
 c.Root=root
 c.Face=Kit.New('Frame',{Name='Face',BackgroundColor3=Theme.White,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=Z+1},root)
 Kit.Corner(c.Face,Theme.Radius.Card)
 c.Stroke=Kit.Stroke(c.Face,P.edge,2,.6)
 c.Stripe=Kit.New('Frame',{Name='Stripe',BackgroundColor3=action.Color,BorderSizePixel=0,ZIndex=Z+2},root)
 Kit.Corner(c.Stripe,'pill')
 c.IconBack=Kit.New('Frame',{Name='IconBack',BackgroundColor3=Theme.Lighten(action.Color,.75),BorderSizePixel=0,ZIndex=Z+2},root)
 Kit.Corner(c.IconBack,'pill')
 c.Icon=label(c.IconBack,{Name='Glyph',Text=action.Glyph,TextSize=22,AlignX='Center',Size=UDim2.fromScale(1,1),ZIndex=Z+3})
 c.Title=label(root,{Name='Title',Text=T(action.Title),TextSize=20,Scaled=true,MinTextSize=12,ZIndex=Z+3})
 c.Pill=Kit.Pill(root,{Name='State',Text='',Height=22,TextSize=12,ZIndex=Z+3,NoTranslate=true,AnchorPoint=Vector2.new(1,0)})
 c.Desc=label(root,{Name='Desc',Text=T(action.Desc),TextSize=14,Color=Theme.InkMuted,Wrap=true,AlignY='Top',ZIndex=Z+3})
 c.Cost=label(root,{Name='Cost',TextSize=15,Rich=true,Scaled=true,MinTextSize=10,ZIndex=Z+3})
 c.Gain=label(root,{Name='Gain',TextSize=15,Rich=true,Wrap=true,AlignY='Top',Color=Color3.fromRGB(58,132,20),ZIndex=Z+3})
 c.Warn=label(root,{Name='Warning',TextSize=14,Wrap=true,AlignY='Top',Color=Theme.Darken(P.red,.1),ZIndex=Z+3})
 if action.Id=='Mutation'or action.Id=='Targeting'then c.Odds=oddsBar(root,Z+3)end
 c.Options=frame(root,'Options',Z+3)
 c.Veil=Kit.New('Frame',{Name='LockVeil',BackgroundColor3=P.edge,BackgroundTransparency=.45,BorderSizePixel=0,Visible=false,ZIndex=Z+8,Size=UDim2.fromScale(1,1)},root)
 Kit.Corner(c.Veil,Theme.Radius.Card)
 c.VeilText=label(c.Veil,{Name='Lock',Text='',TextSize=18,AlignX='Center',Color=Theme.White,Stroke=.3,Size=UDim2.fromScale(1,1),ZIndex=Z+9})
 -- Per-action options (shown while the card is selected).
 local o=c.Options
 if action.Id=='Mutation'or action.Id=='Targeting'then
  if action.Id=='Targeting'then
   c.CatLabel=label(o,{Name='CatalystLabel',Text=T('CATALYST'),TextSize=13,Color=Theme.InkMuted,ZIndex=Z+4})
   c.CatChips=Kit.Chips(o,{Name='Catalysts',ZIndex=Z+4,AllowNone=false,TextSize=14,Options={},OnChange=function(id)
    if id then st.Catalyst=id;cue('Select');renderActions();renderBar()end
   end})
   c.CatEmpty=label(o,{Name='NoCatalyst',Text='',TextSize=14,Wrap=true,AlignY='Top',Color=Theme.InkMuted,ZIndex=Z+4})
  end
  c.StabLabel=label(o,{Name='StabilizerLabel',Text=T('OPTIONAL STABILIZER CRYSTAL'),TextSize=13,Color=Theme.InkMuted,ZIndex=Z+4})
  c.StabChips=Kit.Chips(o,{Name='Stabilizers',ZIndex=Z+4,AllowNone=false,Selected='none',TextSize=14,Options={},OnChange=function(id)
   st.Stabilizer=(id~='none')and id or nil;cue('Select');renderActions();renderBar()
  end})
 elseif action.Id=='Extraction'then
  c.Uses=label(o,{Name='UsedIn',TextSize=14,Wrap=true,AlignY='Top',Color=Theme.InkMuted,ZIndex=Z+4})
 elseif action.Id=='Ascend'then
  c.DupLabel=label(o,{Name='DupLabel',Text=T('THESE COPIES ARE MERGED (CHEAPEST FIRST)'),TextSize=13,Color=Theme.InkMuted,ZIndex=Z+4})
  c.DupHolders,c.DupCards={},{}
  for i=1,2 do
   local h=frame(o,'Copy'..i,Z+4)
   c.DupHolders[i]=h
   c.DupCards[i]=Kit.DogCard.new(h)
  end
 elseif action.Id=='Recipes'then
  c.RecipeRows={}
 end
 root.Activated:Connect(function()
  local e=c.Eval
  if e and e.Locked then toast(e.Reason,'warn');cue('Deny');return end
  if st.Action~=action.Id then
   st.Action=action.Id
   if action.Id=='Recipes'and not(st.RecipeKey and recipeByKey(st.RecipeKey))then S.SuggestRecipe()end
   cue('Select');renderActions();renderBar()
  end
 end)
 return c
end

-- One recipe row inside the RECIPES card.
local function recipeRow(c,row)
 local r:any=c.RecipeRows[row.Key]
 if r then return r end
 r={}
 local f=Kit.New('Frame',{Name='Recipe_'..row.Key,BackgroundColor3=Theme.SurfaceAlt,BorderSizePixel=0,ZIndex=Z+4},c.Options)
 Kit.Corner(f,Theme.Radius.Field)
 r.Root=f
 r.Stroke=Kit.Stroke(f,ACCENT,2,1)
 r.Name=label(f,{Name='Name',TextSize=17,Scaled=true,MinTextSize=11,ZIndex=Z+5})
 r.Badge=Kit.Pill(f,{Name='Chance',Text='',Height=20,TextSize=12,Color=P.green,ZIndex=Z+5,NoTranslate=true,AnchorPoint=Vector2.new(1,0)})
 -- Dog names stay translatable (AutoTranslate splits "A · B").
 r.Dogs=label(f,{Name='Dogs',TextSize=14,Scaled=true,MinTextSize=9,Color=Theme.Ink,NoTranslate=false,ZIndex=Z+5})
 r.Info=label(f,{Name='Info',TextSize=13,Rich=true,Wrap=true,AlignY='Top',Color=Theme.InkMuted,ZIndex=Z+5})
 r.Missing=label(f,{Name='Missing',TextSize=13,Scaled=true,MinTextSize=9,Color=Theme.Darken(P.red,.1),ZIndex=Z+5})
 r.Use=Kit.Button(f,{Name='Use',Text=T('AUTO-FILL'),Style='primary',TextSize=15,ZIndex=Z+6,NoTranslate=true,OnClick=function()
  local current=r.Row
  if not current then return end
  st.Action='Recipes';st.RecipeKey=current.Key
  if not current.Known then S.OpenPicker(current)
  else st.Picks[current.Key]=nil;cue('Select');renderActions();renderBar()end
 end})
 r.Edit=Kit.Button(f,{Name='Edit',Text=T('CHOOSE'),Style='secondary',TextSize=14,ZIndex=Z+6,NoTranslate=true,OnClick=function()
  local current=r.Row
  if current then st.Action='Recipes';st.RecipeKey=current.Key;S.OpenPicker(current)end
 end})
 c.RecipeRows[row.Key]=r
 return r
end

local function updateRecipeRow(r,row,w,selected)
 r.Row=row
 local p=profile()
 r.Name.Text=row.Known and T(row.Name)or T(row.Secret and'CLASSIFIED BLOODLINE'or'UNIDENTIFIED RECIPE')
 r.Stroke.Transparency=selected and 0 or 1
 local lines={}
 local dogs=''
 if row.Known then
  local names={}
  for _,id in ipairs(row.RequiredDogIds or{})do local def=Defs[id];table.insert(names,def and def.DisplayName or id)end
  for _,tag in ipairs(row.RequiredGeneticTags or{})do table.insert(names,dnaName(tag))end
  dogs=table.concat(names,' · ')
  table.insert(lines,F('Makes: %s %s',variantName(row.OutputMutation),dogName(row.OutputDogId)))
  local need={}
  for _,k in ipairs(G.SortedKeys(row.RequiredDNA))do table.insert(need,row.RequiredDNA[k]..' '..dnaName(k))end
  for id,n in pairs(row.RequiredItems or{})do table.insert(need,n..' '..itemName(id))end
  if(row.MinimumMastery or 0)>0 then table.insert(need,F('mastery %d+',row.MinimumMastery))end
  table.insert(lines,F('Needs: %s',table.concat(need,' · ')))
  table.insert(lines,F('Cost: %s',costText({Cash=row.Costs and row.Costs.Cash or 0,Bones=row.Costs and row.Costs.Bones or 0,DNA={}})))
  r.Badge:Set(pct(row.SuccessChance or 0),P.green)
  r.Badge:SetVisible(true)
  local fill=G.FillRecipe(p,row,st.DogUid)
  r.Missing.Text=row.Done and T('Already discovered (one-time recipe)')or(#fill.Missing>0 and missingText(fill.Missing[1])or'')
  r.Use:SetText((selected and not st.Picks[row.Key])and T('SELECTED')or T('AUTO-FILL'))
  r.Use:SetDisabled(row.Done==true)
  r.Edit.Instance.Visible=not row.Done
 else
  dogs=F('%d dogs',row.DogCount or 2)
  table.insert(lines,'"'..T(row.Hint or'')..'"')
  table.insert(lines,T('Pick the dogs and catalysts you think fit; the DNA it needs is taken automatically.'))
  r.Badge:SetVisible(false)
  local pick=st.Picks[row.Key]
  r.Missing.Text=pick and F('Your try: %d dogs, %d catalysts',#pick.Uids,#pick.Items)or''
  r.Missing.TextColor3=pick and Theme.InkMuted or Theme.Darken(P.red,.1)
  r.Use:SetText(T('EXPERIMENT'));r.Use:SetDisabled(row.Done==true)
  r.Edit.Instance.Visible=false
 end
 if row.Known then r.Missing.TextColor3=Theme.Darken(P.red,.1)end
 r.Dogs.Text=dogs
 r.Info.Text=table.concat(lines,'\n')
 -- Layout
 local narrow=w<440
 local bw=narrow and 0 or 132
 local infoH=row.Known and 56 or 58
 place(r.Name,10,6,w-20-80,22)
 r.Badge.Instance.Position=UDim2.new(1,-8,0,7)
 place(r.Dogs,10,28,w-20-bw,18)
 place(r.Info,10,48,w-20-bw,infoH)
 local y=48+infoH
 place(r.Missing,10,y,w-20-bw,16)
 y+=18
 if narrow then
  local half=(w-30)/2
  if r.Edit.Instance.Visible then place(r.Use.Instance,10,y+2,half,38);place(r.Edit.Instance,20+half,y+2,half,38)
  else place(r.Use.Instance,10,y+2,w-20,38)end
  y+=44
 else
  place(r.Use.Instance,w-bw-6,30,bw-4,38)
  if r.Edit.Instance.Visible then place(r.Edit.Instance,w-bw-6,74,bw-4,34)end
 end
 local h=math.max(y+6,narrow and 0 or 116)
 r.Root.Visible=true
 return h
end

-- Renders one card for width w; returns its height.
local function renderCard(c,e,w,selected)
 c.Eval=e
 local narrow=w<460
 local pad=14
 local x=pad+52
 c.Stroke.Color=selected and ACCENT or P.edge
 c.Stroke.Thickness=selected and 3 or 2
 c.Stroke.Transparency=selected and 0 or .6
 place(c.Stripe,6,12,5,40)
 place(c.IconBack,pad+2,12,42,42)
 c.Title.Text=T(c.Action.Title)
 place(c.Title,x,10,w-x-130,26)
 c.Pill.Instance.Position=UDim2.new(1,-12,0,12)
 local pillText,pillColor
 if e.Locked then pillText,pillColor=T('LEVEL LOCKED'),Theme.Disabled
 elseif c.Action.Id=='Extraction'then pillText,pillColor=T('DOG CONSUMED'),P.red
 elseif c.Action.Id=='Ascend'then pillText,pillColor=T('COPIES CONSUMED'),P.gold
 elseif c.Action.Id=='Recipes'then pillText,pillColor=T('DOGS CONSUMED'),P.green
 elseif e.Free then pillText,pillColor=T('FREE TRY'),P.green
 else pillText,pillColor=T('DOG SURVIVES'),P.green end
 c.Pill:Set(pillText,pillColor)
 c.Desc.Text=T(c.Action.Desc)
 local descH=narrow and 36 or 20
 place(c.Desc,x,36,w-x-pad,descH)
 local y=36+descH+6
 local textW=w-x-pad
 if e.Locked then
  c.Cost.Visible=false;c.Gain.Visible=false;c.Warn.Visible=false;c.Options.Visible=false
  if c.Odds then c.Odds.Root.Visible=false end
  c.Veil.Visible=true;c.VeilText.Text='🔒 '..tostring(e.Reason or'')
  local h=y+8
  return math.max(h,96)
 end
 c.Veil.Visible=false
 c.Cost.Visible=e.Cost~=nil
 if e.Cost then c.Cost.Text=colored(T('Cost:'),Theme.InkMuted)..' '..costText(e.Cost);place(c.Cost,x,y,textW,20);y+=22 end
 c.Gain.Visible=e.Gain~=nil
 if e.Gain then
  local gainH=(c.Action.Id=='Extraction'and narrow)and 38 or 20
  c.Gain.Text=e.Gain;place(c.Gain,x,y,textW,gainH);y+=gainH+2
 end
 if c.Odds then
  c.Odds.Root.Visible=e.Chances~=nil
  if e.Chances then place(c.Odds.Root,x,y+2,textW,36);c.Odds.Set(e.Chances,textW);y+=40 end
 end
 local warn=e.Warning
 if selected and e.Reason then warn=e.Reason end
 c.Warn.Visible=warn~=nil
 if warn then
  local h=narrow and 36 or 20
  c.Warn.Text='⚠ '..warn;place(c.Warn,x,y,textW,h);y+=h+2
 end
 -- Options of the selected card.
 local o=c.Options
 o.Visible=selected
 if not selected then return y+10 end
 -- Narrow cards give the options the full width (no indent under the icon).
 local ox=narrow and pad or x
 local ow=w-ox-pad
 local oy=0
 local id=c.Action.Id
 if id=='Mutation'or id=='Targeting'then
  if id=='Targeting'then
   local cats=e.Catalysts or{}
   local sig=signature(cats)
   if c.CatSig~=sig then c.CatSig=sig;c.CatChips:SetOptions(chipsOptions(cats,'cat'))end
   if e.Catalyst then c.CatChips:SetSelected(e.Catalyst.ItemId,true)end
   c.CatLabel.Text=T('CATALYST');place(c.CatLabel,0,oy,ow,16);oy+=18
   c.CatChips.Instance.Visible=#cats>0
   c.CatEmpty.Visible=#cats==0
   if #cats>0 then place(c.CatChips.Instance,0,oy,ow,36);oy+=40
   else
    local names={}
    for itemId in pairs(C.Affinities)do table.insert(names,itemName(itemId))end
    table.sort(names)
    c.CatEmpty.Text=F('No catalysts yet. Dig up one of: %s.',table.concat(names,', '))
    place(c.CatEmpty,0,oy,ow,52);oy+=54
   end
  end
  local stabs=e.Stabilizers or{}
  local sig=signature(stabs)
  if c.StabSig~=sig then c.StabSig=sig;c.StabChips:SetOptions(chipsOptions(stabs,'stab'))end
  c.StabChips:SetSelected(e.Stab and e.Stab.ItemId or'none',true)
  c.StabLabel.Text=#stabs>0 and T('OPTIONAL STABILIZER CRYSTAL')or T('OPTIONAL STABILIZER CRYSTAL · none owned (Quartz, Living Crystal, Crystal of Time)')
  place(c.StabLabel,0,oy,ow,16);oy+=18
  c.StabChips.Instance.Visible=#stabs>0
  if #stabs>0 then place(c.StabChips.Instance,0,oy,ow,36);oy+=40 end
  local strange=e.Stability and G.StrangeChance(e.Stability)or 0
  if c.StabNote==nil then c.StabNote=label(o,{Name='StabilityNote',TextSize=13,Color=Theme.InkMuted,ZIndex=Z+4})end
  c.StabNote.Text=F('Stability %d%% · Strange DNA side find %s',math.floor(e.Stability or 0),pct(strange))
  place(c.StabNote,0,oy,ow,16);oy+=18
 elseif id=='Extraction'then
  local d=selectedDog()
  local uses={}
  for _,k in ipairs(G.SortedKeys(e.Rewards))do
   local names=G.RecipeUses(st.Info and st.Info.Recipes,k)
   if #names>0 then
    local translated={}
    for _,n in ipairs(names)do table.insert(translated,T(n))end
    table.insert(uses,F('%s → %s',dnaName(k),table.concat(translated,', ')))
   end
  end
  local text=#uses>0 and F('Used in recipes: %s',table.concat(uses,'; '))or T('DNA is spent by gene targeting and recipes. Undiscovered recipes may need any sample.')
  if d and #G.Artifacts(profile(),d.DogUid)>0 then text=text..'\n'..F('%d artifacts return to your inventory.',#G.Artifacts(profile(),d.DogUid))end
  c.Uses.Text=text
  place(c.Uses,0,oy,ow,52);oy+=54
 elseif id=='Ascend'then
  local dups=e.Duplicates or{}
  c.DupLabel.Visible=#dups>0
  local cw=math.floor((ow-8)/2)
  if #dups>0 then place(c.DupLabel,0,oy,ow,16);oy+=18 end
  for i=1,2 do
   local d=dups[i]
   c.DupHolders[i].Visible=d~=nil and #dups>=2
   if d and #dups>=2 then
    place(c.DupHolders[i],(i-1)*(cw+8),oy,cw,64)
    c.DupCards[i]:Layout(cw,64)
    c.DupCards[i]:Bind(dogCard(d,false))
   end
  end
  if #dups>=2 then oy+=70 end
 elseif id=='Recipes'then
  local list=e.Recipes or{}
  local seen={}
  for _,row in ipairs(list)do
   local r=recipeRow(c,row);seen[row.Key]=true
   local h=updateRecipeRow(r,row,ow,st.RecipeKey==row.Key)
   place(r.Root,0,oy,ow,h);oy+=h+8
  end
  for key,r in pairs(c.RecipeRows)do if not seen[key]then r.Root.Visible=false end end
  if #list==0 then
   if c.NoRecipes==nil then c.NoRecipes=label(o,{Name='NoRecipes',TextSize=14,Wrap=true,Color=Theme.InkMuted,ZIndex=Z+4})end
   c.NoRecipes.Visible=true;c.NoRecipes.Text=T('No recipes unlocked yet');place(c.NoRecipes,0,oy,ow,20);oy+=22
  elseif c.NoRecipes then c.NoRecipes.Visible=false end
 end
 place(o,ox,y+2,ow,oy)
 return y+oy+12
end

------------------------------------------------------------------------------------------------
-- Window construction (once)
------------------------------------------------------------------------------------------------
local function stepPill(parent,index)
 local o:any={}
 o.Root=Kit.New('TextButton',{Name='Step'..index,Text='',AutoButtonColor=false,BackgroundColor3=Theme.White,BorderSizePixel=0,ZIndex=Z+1},parent)
 Kit.Corner(o.Root,'pill')
 o.Stroke=Kit.Stroke(o.Root,P.edge,2,.6)
 o.Circle=Kit.New('Frame',{Name='Circle',BackgroundColor3=P.secondary,BorderSizePixel=0,ZIndex=Z+2},o.Root)
 Kit.Corner(o.Circle,'pill')
 o.Number=label(o.Circle,{Name='Number',Text=tostring(index),TextSize=16,AlignX='Center',Font='numeric',Size=UDim2.fromScale(1,1),ZIndex=Z+3})
 o.Label=label(o.Root,{Name='Caption',Text='',TextSize=15,Scaled=true,MinTextSize=10,ZIndex=Z+2})
 return o
end

function S.ChipOptions()
 local list={{Id='owned',Text=T('OWNED'),Color=P.green,NoTranslate=true}}
 for _,r in ipairs(RARITIES)do table.insert(list,{Id=r,Text=T(string.upper(r)),Color=Theme.RarityColor(r),NoTranslate=true})end
 return list
end
function S.SortOptions()
 return {{Id='owned',Text=T('OWNED FIRST'),NoTranslate=true},{Id='rarity',Text=T('RARITY'),NoTranslate=true},{Id='name',Text=T('NAME'),Descending=false,NoTranslate=true}}
end
-- Texts set once at build time follow the player's language (LocaleId can change in a session).
function S.Localize()
 if not ui then return end
 ui.Lang=Kit.Lang()
 win:SetTitle(T('GENETICS LAB'),T('Pick a dog · choose an action · confirm'))
 ui.Search.Box.PlaceholderText=T('Search dogs')
 ui.Chips:SetOptions(S.ChipOptions())
 ui.Sort:SetOptions(S.SortOptions())
 ui.SplashTitle.Text=T('A LITTLE SCIENCE. A BIG UPGRADE.')
 ui.SplashGo:SetText(T('SHOW THE WAY'))
 ui.LoadingRetry:SetText(T('RETRY'))
 ui.ResultAgain:SetText(T('AGAIN'))
 ui.ResultNew:SetText(T('NEW EXPERIMENT'))
 ui.ResultTimer.Props.Prefix=T('Chamber ready in ');ui.ResultTimer.Props.DoneText=T('Chamber ready')
 ui.BarTimer.Props.Prefix=T('Chamber cooling down ')
 for _,c in pairs(ui.Cards)do
  if c.DupLabel then c.DupLabel.Text=T('THESE COPIES ARE MERGED (CHEAPEST FIRST)')end
  for _,r in pairs(c.RecipeRows or{})do r.Edit:SetText(T('CHOOSE'))end
 end
end

local function build()
 if ui then return ui end
 ui={Probes={},Cards={}}
 S.UI=ui
 win=Kit.Window.new({Key='Lab',Name='LabWindow',Title=T('GENETICS LAB'),Subtitle=T('Pick a dog · choose an action · confirm'),Accent=ACCENT,Icon='Lab',NoTranslate=true,MaxSize=Vector2.new(1120,780),
  OnOpen=function()S.OnOpen()end,OnClose=function(_,reason)S.OnClose(reason)end})
 S.Window=win
 local body=win.Body
 -- Hidden translated copies of every dog name: Russian search uses what AutoTranslate shows on the cards.
 local probeFrame=Kit.New('Frame',{Name='NameProbes',BackgroundTransparency=1,Visible=false,Size=UDim2.fromOffset(1,1)},body)
 for _,def in ipairs(SPECIES)do
  ui.Probes[def.Id]=Kit.New('TextLabel',{Name=def.Id,Text=def.DisplayName,BackgroundTransparency=1,Size=UDim2.fromOffset(1,1)},probeFrame)
  probes[def.Id]=ui.Probes[def.Id]
 end
 -- Progress header
 ui.Steps=frame(body,'Steps',Z)
 ui.StepPills={stepPill(ui.Steps,1),stepPill(ui.Steps,2),stepPill(ui.Steps,3)}
 ui.StepPills[1].Root.Activated:Connect(function()if st.View=='steps'and st.Step>1 then goStep(1)end end)
 ui.StepPills[2].Root.Activated:Connect(function()if st.View=='steps'and st.Step==1 and(selectedDog()or st.Action=='Recipes')then goStep(2)end end)
 ui.Dna=Kit.Button(ui.Steps,{Name='DnaBank',Text='🧬 DNA',Style='secondary',TextSize=15,ZIndex=Z+1,NoTranslate=true,OnClick=function()S.ShowDNA()end})
 ui.LevelPill=Kit.Pill(ui.Steps,{Name='LabLevel',Text='',Height=26,TextSize=13,Color=ACCENT,ZIndex=Z+1,NoTranslate=true})
 -- Views
 ui.Views=frame(body,'Views',Z)
 -- 1 PICK
 local pick=frame(ui.Views,'PickView',Z);ui.Pick=pick
 ui.Search=Kit.SearchBox(pick,{Name='LabSearch',Placeholder=T('Search dogs'),ZIndex=Z+1,OnChange=function(text)st.Search=text;S.RefreshGrid(true)end})
 ui.Chips=Kit.Chips(pick,{Name='LabRarity',Multi=true,ZIndex=Z+1,TextSize=14,Options=S.ChipOptions(),OnChange=function(list)
  st.Rarities={};st.OwnedOnly=false
  for _,id in ipairs(list)do if id=='owned'then st.OwnedOnly=true else st.Rarities[id]=true end end
  S.RefreshGrid(true)
 end})
 ui.Sort=Kit.SortSelect(pick,{Name='LabSort',ZIndex=Z+1,Selected='owned',Options=S.SortOptions(),
  OnChange=function(id,desc)st.Sort,st.Desc=id,desc;S.RefreshGrid(true)end})
 ui.GridHost=frame(pick,'GridHost',Z)
 ui.Grid=Kit.CardGrid(ui.GridHost,{Name='Species',Kind='Dog',ZIndex=Z+1,CardSize=Vector2.new(150,200),Map=speciesCard,
  Key=function(def)return def.Id end,
  OnClick=function(def)S.OpenSpecies(def.Id)end,
  Empty={Title=Kit.Word('NO_RESULTS'),Body=Kit.Word('TRY_FILTERS')}})
 -- Copies panel
 local panelFrame=panel(pick,'Copies',Z+5,Theme.Surface)
 ui.Panel=panelFrame
 ui.PanelBack=Kit.Button(panelFrame,{Name='Back',Text='‹',Style='secondary',TextSize=22,ZIndex=Z+7,NoTranslate=true,OnClick=function()st.Species=nil;S.RefreshGrid(false);renderPanel();layout()end})
 ui.PanelTitle=label(panelFrame,{Name='Title',TextSize=20,Scaled=true,MinTextSize=12,NoTranslate=false,ZIndex=Z+7})
 ui.PanelRarity=Kit.RarityTag(panelFrame,'Common',{Height=20,TextSize=12,ZIndex=Z+7})
 ui.PanelSub=label(panelFrame,{Name='Sub',TextSize=14,Color=Theme.InkMuted,Scaled=true,MinTextSize=9,ZIndex=Z+7})
 ui.PanelYield=label(panelFrame,{Name='Yield',TextSize=13,Rich=true,Wrap=true,AlignY='Top',Color=Theme.InkMuted,ZIndex=Z+7})
 ui.PanelHint=label(panelFrame,{Name='Hint',TextSize=16,Wrap=true,AlignX='Center',Color=Theme.InkMuted,ZIndex=Z+7})
 ui.Copies=Kit.VirtualList(panelFrame,{Name='CopyList',RowHeight=76,Gap=6,Padding=6,ZIndex=Z+6,
  Key=function(d)return d.DogUid end,
  Create=function(cell)return rowCreate(cell)end,
  Bind=function(o,d)rowBind(o,d)end,
  Layout=function(o,w,h)rowLayout(o,w,h)end,
  Destroy=function(o)o.Card:Destroy();o.Button:Destroy()end})
 -- 2 ACTION
 local action=frame(ui.Views,'ActionView',Z);ui.Action=action
 ui.DogPanel=panel(action,'SelectedDog',Z)
 ui.DogHolder=frame(ui.DogPanel,'Preview',Z+1)
 ui.DogSlot=Kit.Preview.Slot(ui.DogHolder)
 ui.DogName=label(ui.DogPanel,{Name='DogName',TextSize=22,Scaled=true,MinTextSize=12,NoTranslate=false,ZIndex=Z+2})
 ui.DogRarity=Kit.RarityTag(ui.DogPanel,'Common',{Height=20,TextSize=12,ZIndex=Z+2})
 ui.DogVariant=Kit.VariantTag(ui.DogPanel,'Normal',{Height=20,TextSize=12,ZIndex=Z+2,ShowNormal=true})
 ui.DogStats=label(ui.DogPanel,{Name='Stats',TextSize=14,Rich=true,Wrap=true,AlignY='Top',Color=Theme.Ink,ZIndex=Z+2})
 ui.DogValue=Kit.Pill(ui.DogPanel,{Name='Valuable',Text='',Height=20,TextSize=11,Color=P.gold,ZIndex=Z+2,NoTranslate=true})
 ui.DogChange=Kit.Button(ui.DogPanel,{Name='Change',Text=T('CHANGE DOG'),Style='secondary',TextSize=15,ZIndex=Z+2,NoTranslate=true,OnClick=function()goStep(1)end})
 ui.DogEmpty=label(ui.DogPanel,{Name='NoDog',TextSize=15,Wrap=true,AlignX='Center',Color=Theme.InkMuted,ZIndex=Z+2})
 ui.ActionScroll=Kit.New('ScrollingFrame',{Name='Actions',BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=6,ScrollBarImageColor3=ACCENT,
  CanvasSize=UDim2.new(),ScrollingDirection=Enum.ScrollingDirection.Y,VerticalScrollBarInset=Enum.ScrollBarInset.ScrollBar,ZIndex=Z},action)
 for _,a in ipairs(ACTIONS)do ui.Cards[a.Id]=makeCard(a,ui.ActionScroll)end
 -- RESULT
 local result=frame(ui.Views,'ResultView',Z);ui.Result=result
 ui.ResultCard=panel(result,'ResultCard',Z+1)
 ui.ResultScale=Kit.New('UIScale',{Name='Pop'},ui.ResultCard)
 ui.ResultGlow=Kit.New('Frame',{Name='Glow',BackgroundColor3=Theme.White,BorderSizePixel=0,ZIndex=Z+1},ui.ResultCard)
 Kit.Corner(ui.ResultGlow,Theme.Radius.Card)
 ui.ResultGradient=Kit.New('UIGradient',{Rotation=90},ui.ResultGlow)
 ui.ResultHolder=frame(ui.ResultCard,'Preview',Z+2)
 ui.ResultSlot=Kit.Preview.Slot(ui.ResultHolder)
 ui.ResultHead=label(ui.ResultCard,{Name='Headline',TextSize=34,Scaled=true,MinTextSize=16,AlignX='Center',Stroke=.2,ZIndex=Z+3})
 ui.ResultName=label(ui.ResultCard,{Name='DogName',TextSize=20,Scaled=true,MinTextSize=11,AlignX='Center',NoTranslate=false,ZIndex=Z+3})
 ui.ResultBody=label(ui.ResultCard,{Name='Body',TextSize=16,Rich=true,Wrap=true,AlignX='Center',AlignY='Top',Color=Theme.InkMuted,ZIndex=Z+3})
 ui.ResultTimer=Kit.Countdown(ui.ResultCard,{Name='Cooldown',TextSize=15,AlignX='Center',Color=Theme.InkMuted,ZIndex=Z+3,
  Prefix=T('Chamber ready in '),DoneText=T('Chamber ready'),EndsAt=0})
 ui.ResultAgain=Kit.Button(ui.ResultCard,{Name='Again',Text=T('AGAIN'),Style='success',ZIndex=Z+3,NoTranslate=true,OnClick=function()S.Again()end})
 ui.ResultNew=Kit.Button(ui.ResultCard,{Name='NewDog',Text=T('NEW EXPERIMENT'),Style='secondary',ZIndex=Z+3,NoTranslate=true,OnClick=function()
  st.Result=nil;st.Action=nil;setView('steps');goStep(1)
 end})
 -- SPLASH (away from the terminal) and LOADING
 local splash=frame(ui.Views,'SplashView',Z);ui.Splash=splash
 ui.SplashIcon=Kit.Icon(splash,'Lab',{Color=Theme.White,ZIndex=Z+1})
 ui.SplashTitle=label(splash,{Name='Title',Text=T('A LITTLE SCIENCE. A BIG UPGRADE.'),TextSize=28,Scaled=true,MinTextSize=16,AlignX='Center',ZIndex=Z+1})
 ui.SplashBody=label(splash,{Name='Body',Text='',TextSize=17,Wrap=true,AlignX='Center',AlignY='Top',Color=Theme.InkMuted,ZIndex=Z+1})
 ui.SplashTiles={}
 for i,key in ipairs({'PICK A DOG','CHOOSE AN ACTION','CONFIRM'})do
  local tile=panel(splash,'How'..i,Z+1)
  local n=Kit.New('Frame',{Name='Circle',BackgroundColor3=ACCENT,BorderSizePixel=0,ZIndex=Z+2,Size=UDim2.fromOffset(30,30),Position=UDim2.fromOffset(10,10)},tile)
  Kit.Corner(n,'pill')
  label(n,{Name='Number',Text=tostring(i),TextSize=16,AlignX='Center',Color=Theme.White,Font='numeric',Size=UDim2.fromScale(1,1),ZIndex=Z+3})
  local t=label(tile,{Name='Caption',Text=T(key),TextSize=16,Scaled=true,MinTextSize=10,ZIndex=Z+2})
  ui.SplashTiles[i]={Root=tile,Caption=t,Key=key}
 end
 ui.SplashGo=Kit.Button(splash,{Name='ShowTheWay',Text=T('SHOW THE WAY'),Style='primary',Color=ACCENT,ZIndex=Z+1,NoTranslate=true,OnClick=function()
  local n=nav()
  if win then win:Close('navigate')end
  if n and n.Navigate then n.Navigate(S.Destination)end
 end})
 ui.SplashDna=label(splash,{Name='DnaSummary',TextSize=15,AlignX='Center',Color=Theme.InkMuted,ZIndex=Z+1})
 local loading=frame(ui.Views,'LoadingView',Z);ui.Loading=loading
 ui.LoadingText=label(loading,{Name='Text',Text='',TextSize=19,Wrap=true,AlignX='Center',Color=Theme.InkMuted,ZIndex=Z+1})
 ui.LoadingRetry=Kit.Button(loading,{Name='Retry',Text=T('RETRY'),Style='primary',ZIndex=Z+1,NoTranslate=true,OnClick=function()S.Open()end})
 -- Sticky bottom bar
 ui.Bar=panel(body,'ActionBar',Z+2)
 ui.BarTitle=label(ui.Bar,{Name='Title',TextSize=18,Scaled=true,MinTextSize=11,ZIndex=Z+3})
 ui.BarSub=label(ui.Bar,{Name='Sub',TextSize=14,Rich=true,Scaled=true,MinTextSize=9,Color=Theme.InkMuted,ZIndex=Z+3})
 ui.BarTimer=Kit.Countdown(ui.Bar,{Name='Cooldown',TextSize=14,Color=Theme.Darken(P.gold,.2),ZIndex=Z+3,Prefix=T('Chamber cooling down '),DoneText='',EndsAt=0,
  OnDone=function()task.defer(function()renderBar()end)end})
 ui.BarBack=Kit.Button(ui.Bar,{Name='Back',Text=Kit.Word('BACK'),Style='secondary',ZIndex=Z+3,OnClick=function()
  if st.Step>1 then goStep(st.Step-1)end
 end})
 ui.BarGo=Kit.Button(ui.Bar,{Name='Primary',Text='',Style='success',ZIndex=Z+3,NoTranslate=true,OnClick=function()S.Primary()end})
 ui.Lang=Kit.Lang()
 win.Resized:Connect(function()layout()end)
 win.Maid:Give(net().Changed:Connect(function(snapshot)
  if win and win.IsOpen then st.Snapshot=snapshot;refresh()end
 end))
 return ui
end

------------------------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------------------------
renderSteps=function()
 if not ui then return end
 local lay=win:GetLayout()
 local phone=lay.Phone
 local labels=phone and{'DOG','ACTION','CONFIRM'}or{'PICK A DOG','CHOOSE AN ACTION','CONFIRM'}
 local current=st.Step
 if st.View=='result'then current=4 end
 if st.Confirming then current=3 end
 for i,o in ipairs(ui.StepPills)do
  local done=i<current;local on=i==current
  o.Label.Text=T(labels[i])
  o.Root.BackgroundColor3=on and ACCENT or Theme.White
  o.Stroke.Transparency=on and 0 or .6
  o.Label.TextColor3=on and Theme.White or(done and Theme.Ink or Theme.InkMuted)
  o.Label.TextStrokeTransparency=on and .4 or 1
  o.Circle.BackgroundColor3=on and Theme.White or(done and P.green or P.secondary)
  o.Number.Text=done and'✓'or tostring(i)
  o.Number.TextColor3=on and ACCENT or(done and Theme.White or Theme.InkMuted)
 end
 local total=0
 for _,n in pairs(dnaOf(profile()))do total+=tonumber(n)or 0 end
 ui.Dna:SetText('🧬 '..Format.Short(total,0))
 ui.LevelPill:Set(F('LAB LEVEL %d/%d',tier(),#C.Procedures),ACCENT)
end

renderPanel=function()
 if not ui then return end
 local id=st.Species
 local def=id and Defs[id]
 local has=def~=nil
 ui.PanelTitle.Visible=has;ui.PanelRarity:SetVisible(has);ui.PanelSub.Visible=has;ui.PanelYield.Visible=has and not ui.PanelShort
 ui.Copies.Instance.Visible=has
 ui.PanelHint.Visible=not has
 if not has then
  ui.PanelHint.Text=T('Tap a dog you own to see your copies.\n\nDimmed dogs are not owned yet: tap them to see where to find them.')
  ui.Copies:SetItems({})
  return
 end
 local copies=copiesOf(id)
 ui.PanelTitle.Text=def.DisplayName
 ui.PanelRarity:SetRarity(def.Rarity)
 ui.PanelSub.Text=F('Owned %d · ready %d',#copies,st.Ready[id]or 0)
 local sample={DogId=id,Variant='Normal',Mastery=0,AscensionLevel=0}
 local genes={}
 for _,tag in ipairs(G.Tags(id))do table.insert(genes,dnaName(tag))end
 ui.PanelYield.Text=F('Genes: %s',table.concat(genes,', '))..'\n'..F('Extract DNA gives about: %s',rewardsText(G.Extraction(sample),true))
 ui.Copies:SetItems(copies)
end

local function renderDogPanel(lay,w,h,compact)
 local d=selectedDog()
 local p=profile()
 ui.DogEmpty.Visible=d==nil
 for _,o in ipairs({ui.DogHolder,ui.DogName,ui.DogStats})do o.Visible=d~=nil end
 ui.DogRarity:SetVisible(d~=nil);ui.DogVariant:SetVisible(d~=nil)
 ui.DogChange:SetText(d and T('CHANGE DOG')or T('PICK A DOG'))
 if not d then
  ui.DogSlot:Show(nil);ui.DogValue:SetVisible(false)
  ui.DogEmpty.Text=T('No dog picked. Recipes choose their own dogs; other actions need a dog.')
  if compact then place(ui.DogEmpty,10,8,w-140,h-16);place(ui.DogChange.Instance,w-128,(h-40)/2,118,40)
  else place(ui.DogEmpty,12,20,w-24,120);place(ui.DogChange.Instance,12,h-56,w-24,44)end
  return
 end
 ui.DogSlot:Show({Kind='Dog',DogId=d.DogId,Variant=d.Variant})
 ui.DogName.Text=d.DisplayName or d.DogId
 ui.DogRarity:SetRarity(d.Rarity or(Defs[d.DogId]and Defs[d.DogId].Rarity))
 ui.DogVariant:SetVariant(d.Variant)
 local genes={}
 for _,tag in ipairs(G.Tags(d))do table.insert(genes,dnaName(tag))end
 local level=tonumber(d.AscensionLevel)or 0
 ui.DogStats.Text=F('Mastery %d · Ascension %d/%d',math.floor(tonumber(d.Mastery)or 0),level,#Base.Ascension-1)..'\n'..F('Genes: %s',table.concat(genes,', '))
 local reasons=G.ValueReasons(p,d)
 ui.DogValue:SetVisible(#reasons>0)
 if #reasons>0 then ui.DogValue:Set(T('VALUABLE')..' · '..reasonsText(reasons),P.gold)end
 if compact then
  local s=h-16
  place(ui.DogHolder,8,8,s,s)
  local x=s+18
  local bw=w<420 and 96 or 128
  place(ui.DogName,x,6,w-x-bw-14,24)
  ui.DogRarity.Instance.Position=UDim2.fromOffset(x,32);ui.DogVariant.Instance.Position=UDim2.fromOffset(x+92,32)
  place(ui.DogStats,x,54,w-x-bw-14,h-58)
  ui.DogValue.Instance.Visible=false
  place(ui.DogChange.Instance,w-bw-8,(h-40)/2,bw,40)
 else
  local s=math.min(w-24,math.max(90,h-230))
  place(ui.DogHolder,(w-s)/2,10,s,s)
  local y=s+16
  place(ui.DogName,12,y,w-24,26);y+=30
  ui.DogRarity.Instance.Position=UDim2.fromOffset(12,y);ui.DogVariant.Instance.Position=UDim2.fromOffset(110,y);y+=26
  ui.DogValue.Instance.Position=UDim2.fromOffset(12,y);if #reasons>0 then y+=26 end
  place(ui.DogStats,12,y,w-24,58)
  place(ui.DogChange.Instance,12,h-54,w-24,44)
 end
end

renderActions=function()
 if not ui or not win then return end
 local scroll=ui.ActionScroll
 local w=math.floor(ui.ActionWidth or 400)-10
 local y=0
 for _,a in ipairs(ACTIONS)do
  local c=ui.Cards[a.Id]
  local e=evaluate(a.Id)
  local h=renderCard(c,e,w,st.Action==a.Id)
  place(c.Root,0,y,w,h)
  y+=h+10
 end
 scroll.CanvasSize=UDim2.fromOffset(0,y)
end

renderBar=function()
 if not ui then return end
 local title,sub,go,goText,goStyle='','',false,'',nil
 ui.BarBack.Instance.Visible=st.View=='steps'and st.Step>1
 local timer=false
 if st.View~='steps'then
  ui.Bar.Visible=false
  return
 end
 ui.Bar.Visible=true
 if st.Step==1 then
  local d=selectedDog()
  title=T('STEP 1 · PICK A DOG')
  sub=d and T('Dog picked: tap NEXT to choose what to do with it.')or T('Tap a dog you own. Dimmed dogs are not owned yet.')
  goText=T('NEXT');go=d~=nil
 else
  if not st.Action then
   title=T('STEP 2 · CHOOSE AN ACTION');sub=T('Tap a card to see what it costs and what you get.')
   goText=T('REVIEW');go=false
  else
   local e=evaluate(st.Action)
   title=T(ACTION_BY[st.Action].Title)
   sub=e.Reason and colored('⚠ '..e.Reason,Theme.Darken(P.red,.1))or(e.Cost and(T('Cost:')..' '..costText(e.Cost))or'')
   goText=T('REVIEW & CONFIRM');go=e.Args~=nil and e.Reason==nil
   if cooling()then timer=true;go=false end
  end
  goStyle='success'
 end
 ui.BarTitle.Text=title;ui.BarSub.Text=sub
 ui.BarSub.Visible=not timer;ui.BarTimer.Instance.Visible=timer
 if timer then ui.BarTimer:SetEndsAt(st.CooldownEndsAt)end
 ui.BarGo:SetText(goText);ui.BarGo:SetStyle(goStyle or'success');ui.BarGo:SetDisabled(not go)
end

local function renderSplash()
 if not ui then return end
 local message=st.Message
 ui.SplashBody.Text=message and said(message)or T('The lab works at the genetics terminal inside the Mutation Lab. Walk up to it and press USE GENETICS LAB.')
 local total,types=0,0
 for _,n in pairs(dnaOf(profile()))do if(tonumber(n)or 0)>0 then total+=n;types+=1 end end
 ui.SplashDna.Text=F('Your DNA bank: %d samples of %d kinds',total,types)
 for _,t in ipairs(ui.SplashTiles)do t.Caption.Text=T(t.Key)end
end

------------------------------------------------------------------------------------------------
-- Layout (explicit pixels from the window body size; re-run on resize and view changes)
------------------------------------------------------------------------------------------------
layout=function()
 if not ui or not win then return end
 local lay=win:GetLayout()
 local W,H=lay.Width,lay.Height
 if W<10 or H<10 then return end
 local phone=lay.Phone;local landscape=lay.Landscape;local portrait=phone and not landscape
 -- Header (landscape phones have no height to spare: the bar title names the step instead)
 if ui.Lang~=Kit.Lang()then S.Localize()end
 local stepsH=phone and(landscape and 0 or 40)or 46
 local showSteps=st.View~='splash'and st.View~='loading'and stepsH>0
 ui.Steps.Visible=showSteps
 place(ui.Steps,0,0,W,math.max(stepsH,1))
 local rightW=phone and 84 or 270
 local dnaW=phone and 80 or 110
 ui.LevelPill.Instance.Visible=not phone
 ui.LevelPill.Instance.AnchorPoint=Vector2.new(1,.5)
 ui.LevelPill.Instance.Position=UDim2.new(0,W-dnaW-8,0,stepsH/2)
 local gap=6
 local pw=math.floor((W-rightW-gap*2)/3)
 for i,o in ipairs(ui.StepPills)do
  place(o.Root,(i-1)*(pw+gap),2,pw,math.max(stepsH-4,1))
  local cs=math.max(stepsH-12,1)
  place(o.Circle,5,4,cs,cs)
  place(o.Label,cs+12,4,pw-cs-18,cs)
 end
 -- Bar: one row (summary | back | main button); portrait phones stack the summary above the buttons.
 local barH=portrait and 104 or(phone and 56 or 66)
 local barVisible=st.View=='steps'
 ui.BarBack.Instance.Visible=barVisible and st.Step>1
 place(ui.Bar,0,H-barH,W,barH)
 if landscape then
  ui.Dna.Instance.Parent=ui.Bar
 else
  ui.Dna.Instance.Parent=ui.Steps
  place(ui.Dna.Instance,W-dnaW,2,dnaW,math.max(stepsH-4,1))
 end
 if portrait then
  local backVisible=ui.BarBack.Instance.Visible
  local backW=backVisible and 104 or 0
  place(ui.BarTitle,12,6,W-24,22)
  place(ui.BarSub,12,28,W-24,18)
  place(ui.BarTimer.Instance,12,28,W-24,18)
  place(ui.BarBack.Instance,8,52,math.max(backW,1),46)
  place(ui.BarGo.Instance,8+(backVisible and backW+8 or 0),52,W-16-(backVisible and backW+8 or 0),46)
 else
  local goW=phone and 190 or 240
  local backW=phone and 84 or 120
  local inset=phone and 6 or 7
  place(ui.BarGo.Instance,W-goW-8,inset,goW,barH-inset*2)
  place(ui.BarBack.Instance,W-goW-backW-14,inset,backW,barH-inset*2)
  local used=goW+(ui.BarBack.Instance.Visible and backW+6 or 0)
  if landscape then
   place(ui.Dna.Instance,W-used-dnaW-20,inset,dnaW,barH-inset*2)
   used+=dnaW+6
  end
  local textW=W-used-30
  place(ui.BarTitle,12,5,textW,barH*.42)
  place(ui.BarSub,12,barH*.46,textW,barH*.44)
  place(ui.BarTimer.Instance,12,barH*.46,textW,barH*.44)
 end
 -- Views
 local top=showSteps and stepsH+8 or 0
 local bottom=barVisible and(H-barH-8)or H
 local vh=bottom-top
 place(ui.Views,0,top,W,vh)
 ui.Pick.Visible=st.View=='steps'and st.Step==1
 ui.Action.Visible=st.View=='steps'and st.Step==2
 ui.Result.Visible=st.View=='result'
 ui.Splash.Visible=st.View=='splash'
 ui.Loading.Visible=st.View=='loading'
 -- 1 PICK
 place(ui.Pick,0,0,W,vh)
 local tbH
 if portrait then
  local sortW=math.min(160,math.floor(W*.42))
  place(ui.Search.Instance,0,0,W-sortW-8,40)
  place(ui.Sort.Instance,W-sortW,0,sortW,40)
  place(ui.Chips.Instance,0,46,W,36)
  tbH=86
 else
  local searchW=math.min(phone and 190 or 260,math.floor(W*.28))
  local sortW=phone and 160 or 210
  local h=phone and 40 or 42
  place(ui.Search.Instance,0,0,searchW,h)
  place(ui.Sort.Instance,W-sortW,0,sortW,h)
  place(ui.Chips.Instance,searchW+8,0,W-searchW-sortW-16,h)
  tbH=h+6
 end
 local gy=tbH+4
 local gh=vh-gy
 local side=not phone and W>=760
 local panelW=side and math.clamp(math.floor(W*.34),300,380)or W
 local panelH=gh
 if side then
  place(ui.GridHost,0,gy,W-panelW-10,gh)
  place(ui.Panel,W-panelW,gy,panelW,gh)
  ui.Panel.Visible=true
  ui.PanelBack.Instance.Visible=false
 else
  -- Phones: the copies sheet covers the whole step (toolbar included) and has a back button.
  place(ui.GridHost,0,gy,W,gh)
  place(ui.Panel,0,0,W,vh)
  panelH=vh
  ui.Panel.Visible=st.Species~=nil
  ui.PanelBack.Instance.Visible=true
 end
 ui.Grid.Instance.Size=UDim2.fromScale(1,1)
 ui.Grid:Relayout()
 -- Copies panel interior
 local px=ui.PanelBack.Instance.Visible and 56 or 12
 place(ui.PanelBack.Instance,8,8,40,40)
 place(ui.PanelTitle,px,8,panelW-px-100,26)
 ui.PanelRarity.Instance.Position=UDim2.fromOffset(panelW-96,12)
 place(ui.PanelSub,px,34,panelW-px-12,18)
 local short=panelH<240
 ui.PanelShort=short
 ui.PanelYield.Visible=st.Species~=nil and not short
 place(ui.PanelYield,12,56,panelW-24,34)
 place(ui.PanelHint,16,40,panelW-32,160)
 local listY=short and 56 or 94
 place(ui.Copies.Instance,4,listY,panelW-8,panelH-listY-4)
 ui.Copies:Relayout()
 -- 2 ACTION
 place(ui.Action,0,0,W,vh)
 local twoColumns=W>=640
 if twoColumns then
  local lw=math.clamp(math.floor(W*.3),220,300)
  place(ui.DogPanel,0,0,lw,vh)
  place(ui.ActionScroll,lw+10,0,W-lw-10,vh)
  ui.ActionWidth=W-lw-10
  if st.View=='steps'and st.Step==2 then renderDogPanel(lay,lw,vh,false)end
 else
  local dh=portrait and 96 or 84
  place(ui.DogPanel,0,0,W,dh)
  place(ui.ActionScroll,0,dh+8,W,vh-dh-8)
  ui.ActionWidth=W
  if st.View=='steps'and st.Step==2 then renderDogPanel(lay,W,dh,true)end
 end
 if st.View=='steps'and st.Step==2 then renderActions()end
 -- RESULT
 place(ui.Result,0,0,W,vh)
 local cw=math.min(W,560);local ch=math.min(vh,phone and vh or 600)
 place(ui.ResultCard,(W-cw)/2,(vh-ch)/2,cw,ch)
 ui.ResultCard.AnchorPoint=Vector2.zero
 place(ui.ResultGlow,4,4,cw-8,ch*.5)
 local ps=math.min(phone and(landscape and 110 or 150)or 200,ch*.42)
 local buttonsH=phone and 46 or 50
 if landscape then
  -- Side by side: preview left, text right.
  place(ui.ResultHolder,16,(ch-ps)/2-20,ps,ps)
  local x=ps+28;local tw=cw-x-14
  place(ui.ResultHead,x,10,tw,40)
  place(ui.ResultName,x,50,tw,24)
  place(ui.ResultBody,x,76,tw,ch-76-buttonsH-40)
  place(ui.ResultTimer.Instance,x,ch-buttonsH-34,tw,22)
 else
  place(ui.ResultHolder,(cw-ps)/2,14,ps,ps)
  local y=ps+20
  place(ui.ResultHead,14,y,cw-28,44);y+=46
  place(ui.ResultName,14,y,cw-28,24);y+=26
  place(ui.ResultBody,14,y,cw-28,ch-y-buttonsH-46)
  place(ui.ResultTimer.Instance,14,ch-buttonsH-40,cw-28,22)
 end
 local half=math.floor((cw-36)/2)
 if ui.ResultAgain.Instance.Visible then
  place(ui.ResultAgain.Instance,12,ch-buttonsH-12,half,buttonsH)
  place(ui.ResultNew.Instance,24+half,ch-buttonsH-12,half,buttonsH)
 else
  place(ui.ResultNew.Instance,12,ch-buttonsH-12,cw-24,buttonsH)
 end
 -- SPLASH
 place(ui.Splash,0,0,W,vh)
 local sw=math.min(W-16,640)
 local sx=(W-sw)/2
 local icon=phone and(landscape and 0 or 84)or 112
 ui.SplashIcon.Visible=icon>0
 local y=phone and 8 or 20
 if icon>0 then place(ui.SplashIcon,(W-icon)/2,y,icon,icon);y+=icon+8 end
 place(ui.SplashTitle,sx,y,sw,phone and 32 or 40);y+=phone and 36 or 46
 local bodyH=phone and 58 or 54
 place(ui.SplashBody,sx,y,sw,bodyH);y+=bodyH+6
 local tileW=math.floor((sw-16)/3);local tileH=50
 for i,t in ipairs(ui.SplashTiles)do
  place(t.Root,sx+(i-1)*(tileW+8),y,tileW,tileH)
  place(t.Caption,46,6,tileW-52,tileH-12)
 end
 y+=tileH+(phone and 10 or 18)
 local goW=math.min(sw,320)
 place(ui.SplashGo.Instance,(W-goW)/2,y,goW,phone and 46 or 54);y+=(phone and 46 or 54)+8
 place(ui.SplashDna,sx,y,sw,22)
 -- LOADING
 place(ui.Loading,0,0,W,vh)
 place(ui.LoadingText,16,vh*.3,W-32,60)
 place(ui.LoadingRetry.Instance,(W-220)/2,vh*.3+70,220,46)
 renderSteps()
 renderBar()
end

------------------------------------------------------------------------------------------------
-- Flow
------------------------------------------------------------------------------------------------
setView=function(view)
 st.View=view
 if view=='splash'then renderSplash()end
 layout()
end

goStep=function(step)
 st.Step=step
 st.View='steps'
 if step==1 then S.RefreshGrid(false);renderPanel()end
 cue('Step')
 layout()
end

function S.RefreshGrid(reset)
 if not ui then return end
 ui.Grid:SetItems(filteredSpecies(),reset and{ResetScroll=true}or nil)
end

refresh=function()
 if not ui then return end
 computeOwned()
 if st.DogUid and not selectedDog()then st.DogUid=nil;if st.Step==2 and st.Action~='Recipes'then st.Action=nil end end
 -- Manual recipe picks that no longer exist are dropped.
 for key,pick in pairs(st.Picks)do
  for _,uid in ipairs(pick.Uids)do if not dogsOf(profile())[uid]then st.Picks[key]=nil;break end end
 end
 S.RefreshGrid(false)
 renderPanel()
 if st.View=='splash'then renderSplash()end
 layout()
end

function S.OpenSpecies(id)
 st.Species=id
 cue('Select')
 S.RefreshGrid(false)
 renderPanel()
 layout()
 -- One ready copy: pick it straight away.
 local ready={}
 for _,d in ipairs(st.Owned[id]or{})do if G.Check(profile(),d)then table.insert(ready,d)end end
 if #(st.Owned[id]or{})==1 and #ready==1 then S.PickDog(ready[1].DogUid)end
end

-- The recipe the RECIPES card opens on: the first one the player can fill right now, else the first known one.
function S.SuggestRecipe()
 local p=profile();local first,known=nil,nil
 for _,row in ipairs(recipeRows())do
  first=first or row.Key
  if row.Known and not row.Done then
   known=known or row.Key
   if #G.FillRecipe(p,row,st.DogUid).Missing==0 then st.RecipeKey=row.Key;return end
  end
 end
 st.RecipeKey=known or first
end

function S.PickDog(uid)
 local d=dogsOf(profile())[uid]
 if not d then return end
 local ok,_,message=G.Check(profile(),d)
 if not ok then toast(said(message),'warn');cue('Deny');return end
 if st.DogUid~=uid then
  st.DogUid=uid;st.Stabilizer=nil
  if st.Action~='Recipes'then st.Action=nil end
 end
 st.Species=d.DogId
 goStep(2)
end

-- The DNA bank: every sample with its amount and the known recipes that use it.
function S.ShowDNA()
 local dna=dnaOf(profile())
 local keys={}
 for _,k in ipairs(G.SortedKeys(dna))do if(tonumber(dna[k])or 0)>0 then table.insert(keys,k)end end
 local rowsH=math.max(1,#keys)*26
 Kit.Modal({Title=T('DNA BANK'),Body=T('DNA comes from EXTRACT DNA. Gene targeting and recipes spend it.'),NoTranslate=true,NoCancel=true,Accent=ACCENT,
  ContentHeight=math.min(rowsH,260),Content=function(f,w)
   local scroll=Kit.New('ScrollingFrame',{Name='DnaRows',BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),CanvasSize=UDim2.fromOffset(0,rowsH),ScrollBarThickness=4,ZIndex=f.ZIndex},f)
   if #keys==0 then
    label(scroll,{Name='Empty',Text=T('No DNA yet. Extract a dog you do not need.'),TextSize=15,Color=Theme.InkMuted,Size=UDim2.fromOffset(w,24),ZIndex=f.ZIndex+1})
   end
   for i,k in ipairs(keys)do
    local uses=G.RecipeUses(st.Info and st.Info.Recipes,k)
    local translated={}
    for _,n in ipairs(uses)do table.insert(translated,T(n))end
    label(scroll,{Name='Row_'..k,Text=dnaName(k)..(#translated>0 and('  · '..table.concat(translated,', '))or''),TextSize=15,Scaled=true,MinTextSize=9,Position=UDim2.fromOffset(0,(i-1)*26),Size=UDim2.fromOffset(w-80,24),ZIndex=f.ZIndex+1})
    label(scroll,{Name='Amount_'..k,Text=Format.Number(dna[k]),Font='numeric',TextSize=16,AlignX='Right',Position=UDim2.fromOffset(w-80,(i-1)*26),Size=UDim2.fromOffset(72,24),ZIndex=f.ZIndex+1})
   end
  end})
end

------------------------------------------------------------------------------------------------
-- Recipe picker (stacked window): choose the dogs and catalysts of a recipe or an experiment
------------------------------------------------------------------------------------------------
function S.OpenPicker(row)
 if not row then return end
 local p=profile()
 local need=row.DogCount or 2
 local pick=st.Picks[row.Key]
 local chosen,items={},{}
 if pick then for _,u in ipairs(pick.Uids)do chosen[u]=true end;for _,u in ipairs(pick.Items)do items[u]=true end
 elseif row.Known then
  local fill=G.FillRecipe(p,row,st.DogUid)
  for _,u in ipairs(fill.Uids)do chosen[u]=true end
  for _,u in ipairs(fill.Items)do items[u]=true end
 end
 local picker=Kit.Window.new({Key='LabPicker',Name='LabPicker',Stack=true,Title=row.Known and T(row.Name)or T('EXPERIMENT'),
  Subtitle=row.Known and F('Choose %d dogs and the catalysts',need)or T(row.Hint or''),Accent=ACCENT,Icon='Lab',NoTranslate=true,MaxSize=Vector2.new(960,720)})
 local body=picker.Body
 local list={}
 for _,d in pairs(dogsOf(p))do if type(d)=='table'and G.Check(p,d)then table.insert(list,d)end end
 table.sort(list,function(a,b)
  if a.DogId~=b.DogId then return(Defs[a.DogId]and Defs[a.DogId].Index or 0)<(Defs[b.DogId]and Defs[b.DogId].Index or 0)end
  return G.ValueScore(p,a)<G.ValueScore(p,b)
 end)
 local function count(t)local n=0;for _ in pairs(t)do n+=1 end;return n end
 local status=label(body,{Name='Status',TextSize=15,Rich=true,Scaled=true,MinTextSize=9,ZIndex=Z+1})
 local grid
 local function render()
  status.Text=F('Dogs %d/%d · catalysts %d',count(chosen),need,count(items))
  if grid then grid:Refresh()end
 end
 grid=Kit.CardGrid(body,{Name='PickerDogs',Kind='Dog',ZIndex=Z+1,CardSize=Vector2.new(140,190),Key=function(d)return d.DogUid end,
  Map=function(d)return dogCard(d,chosen[d.DogUid])end,
  OnClick=function(d)
   if chosen[d.DogUid]then chosen[d.DogUid]=nil
   elseif count(chosen)<need then chosen[d.DogUid]=true
   else toast(F('This recipe takes %d dogs',need),'warn');return end
   cue('Select');render()
  end,
  Empty={Title=T('No ready dogs'),Body=T('Unlock dogs or take them out of kennels first.')}})
 picker.Maid:Give(grid)
 local catalystGroups={}
 for _,x in pairs(type(p.Items)=='table'and p.Items or{})do
  if type(x)=='table'and not x.Favorite and x.Tradeable~=false and C.Stabilizers[x.ItemId]==nil then
   local g=catalystGroups[x.ItemId]
   if not g then g={ItemId=x.ItemId,Uids={}};catalystGroups[x.ItemId]=g end
   table.insert(g.Uids,x.ItemUid)
  end
 end
 local options={}
 for id,g in pairs(catalystGroups)do table.sort(g.Uids);table.insert(options,{Id=id,Text=F('%s ×%d',itemName(id),#g.Uids),NoTranslate=true})end
 table.sort(options,function(a,b)return a.Text<b.Text end)
 local selectedItems={}
 for uid in pairs(items)do
  for id,g in pairs(catalystGroups)do if table.find(g.Uids,uid)then table.insert(selectedItems,id)end end
 end
 local itemsLabel=label(body,{Name='ItemsLabel',Text=T('CATALYSTS (one of each kind)'),TextSize=13,Color=Theme.InkMuted,ZIndex=Z+1})
 local chips=Kit.Chips(body,{Name='PickerItems',Multi=true,ZIndex=Z+1,TextSize=14,Options=options,Selected=selectedItems,OnChange=function(ids)
  items={}
  for i,id in ipairs(ids)do if i<=4 then items[catalystGroups[id].Uids[1]]=true end end
  render()
 end})
 picker.Maid:Give(chips)
 local noItems=label(body,{Name='NoItems',Text=T('No finds to add. Catalysts come from digging.'),TextSize=14,Color=Theme.InkMuted,ZIndex=Z+1})
 noItems.Visible=#options==0;chips.Instance.Visible=#options>0
 local use=Kit.Button(body,{Name='Use',Text=T('USE THESE'),Style='success',ZIndex=Z+2,NoTranslate=true,OnClick=function()
  if count(chosen)<2 then toast(T('Choose at least 2 dogs'),'warn');cue('Deny');return end
  local uids,its={},{}
  for u in pairs(chosen)do table.insert(uids,u)end
  for u in pairs(items)do table.insert(its,u)end
  table.sort(uids);table.sort(its)
  st.Picks[row.Key]={Uids=uids,Items=its}
  st.Action='Recipes';st.RecipeKey=row.Key
  cue('Confirm')
  picker:Close('done')
  renderActions();renderBar()
 end})
 picker.Maid:Give(use)
 local function place2()
  local lay=picker:GetLayout();local W,H=lay.Width,lay.Height
  if W<10 then return end
  place(status,4,0,W-8,24)
  local chipsH=#options>0 and 36 or 22
  local bottomH=58
  place(grid.Instance,0,28,W,H-28-chipsH-24-bottomH)
  grid:Relayout()
  local y=H-bottomH-chipsH-22
  place(itemsLabel,4,y,W-8,18)
  place(chips.Instance,0,y+20,W,chipsH)
  place(noItems,4,y+20,W-8,chipsH)
  place(use.Instance,(W-260)/2,H-50,260,46)
 end
 picker.Resized:Connect(place2)
 picker.Closed:Connect(function()task.defer(function()picker:Destroy()end)end)
 grid:SetItems(list)
 picker:Open()
 place2()
 render()
end

------------------------------------------------------------------------------------------------
-- Preview → confirm → commit → cinematic → result
------------------------------------------------------------------------------------------------
local function planCards(plan)
 local p=profile();local cards={}
 local uids=plan.Destructive and plan.Consumed or{plan.PrimaryUid}
 for _,uid in ipairs(uids or{})do
  local d=dogsOf(p)[uid]
  if d then
   local data=dogCard(d,false)
   data.Disabled=false;data.DisabledReason=nil
   local reasons=plan.Valuable and plan.Valuable[uid]
   if reasons and #reasons>0 then data.Badge=T('VALUABLE');data.BadgeColor=P.gold end
   cards[#cards+1]=data
  end
 end
 return cards
end

local function confirmBody(plan,e)
 local lines={}
 table.insert(lines,T('Cost:')..' '..(plan.Cash>0 and F('%s coins',Format.Short(plan.Cash,1))or T('FREE'))..(plan.Bones>0 and(' · '..F('%d bones',plan.Bones))or''))
 if next(plan.DNA or{})then table.insert(lines,T('DNA used:')..' '..rewardsText(plan.DNA,false))end
 if plan.Procedure=='Mutation'or plan.Procedure=='Targeting'then
  table.insert(lines,T('Your dog survives. Its variant is rerolled with these odds:'))
 elseif plan.Procedure=='Extraction'then
  table.insert(lines,F('You get %s',rewardsText(plan.Rewards or{},true)))
  table.insert(lines,T('This dog is consumed forever.'))
 elseif plan.RecipeId=='ASCEND'then
  table.insert(lines,F('Ascension %d → %d. These 2 copies are consumed:',plan.OutputAscension-1,plan.OutputAscension))
 else
  if plan.Hidden then table.insert(lines,F('Unknown bloodline · %s chance of success',pct(plan.SuccessChance)))
  else
   table.insert(lines,F('Makes: %s %s',variantName(plan.OutputMutation),dogName(plan.OutputDogId))..' · '..F('%s chance of success',pct(plan.SuccessChance)))
  end
  table.insert(lines,T('On success these dogs are consumed. On failure they survive and half the DNA comes back.'))
 end
 if plan.Artifacts and plan.Artifacts>0 then table.insert(lines,F('%d artifacts return to your inventory.',plan.Artifacts))end
 if plan.HighValue then
  local reasons,seen={},{}
  for _,list in pairs(plan.Valuable or{})do for _,r in ipairs(list)do if not seen[r]then seen[r]=true;table.insert(reasons,r)end end end
  table.sort(reasons)
  table.insert(lines,F('Valuable: %s. Hold the button to confirm.',reasonsText(reasons)))
 end
 local _=e
 return table.concat(lines,'\n')
end

local function play(result)
 local n=nav()
 local epoch=nil
 if n and n.BeginReward then
  local ok,value=pcall(n.BeginReward,result.Token)
  if ok then epoch=value end
 end
 -- SKIP button over the cinematic.
 local skip=nil
 local okSkip,err=pcall(function()
  skip=Kit.Button(Kit.Overlay.Top(),{Name='LabSkip',Text=T('SKIP')..' ▸',Style='secondary',ZIndex=20,NoTranslate=true,
   AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-24,1,-28),Size=UDim2.fromOffset(150,46),
   OnClick=function()require(script.Parent.LabPresentation).Skip()end})
 end)
 if not okSkip then warn('Lab skip button: '..tostring(err))end
 local ok,playErr=pcall(function()require(script.Parent.LabPresentation).Play(result)end)
 if not ok then warn('Lab presentation: '..tostring(playErr))end
 if skip then skip:Destroy()end
 if n and n.EndReward and epoch then pcall(n.EndReward,epoch)end
 local owner=n and n.Owner
 if owner==nil or owner=='HUD'or owner=='Reward'then
  showResult(result)
 else
  st.Result=result;st.View='result'
 end
end

local function commit(plan)
 st.Busy=true;ui.BarGo:SetBusy(true)
 local args={Token=plan.Token,Confirm=true,Acknowledge=plan.HighValue and plan.Token or nil}
 local ok,result=request('LabCommit',args)
 if not ok and tostring(result)=='Connection problem; try again'then
  -- Same token: the server answers from its history if the first try landed.
  task.wait(1)
  ok,result=request('LabCommit',args)
 end
 st.Busy=false;ui.BarGo:SetBusy(false)
 if not ok then
  toast(said(result),'error');cue('Deny')
  if tostring(result)=='Chamber cooling down'then st.CooldownEndsAt=Kit.Now()+C.Cooldown;renderBar()end
  return
 end
 if type(result)~='table'then return end
 st.CooldownEndsAt=Kit.Now()+C.Cooldown
 if type(result.Dog)=='table'and st.DogUid==nil and result.Dog.DogUid then st.DogUid=result.Dog.DogUid end
 cue('Confirm')
 task.spawn(play,result)
end

openConfirm=function(plan,e)
 local action=ACTION_BY[st.Action]
 local title
 if plan.Procedure=='Mutation'then title=T('REROLL THE VARIANT?')
 elseif plan.Procedure=='Targeting'then title=T('GENE TARGETING?')
 elseif plan.Procedure=='Extraction'then title=T('EXTRACT DNA?')
 elseif plan.RecipeId=='ASCEND'then title=T('ASCEND THIS DOG?')
 else title=plan.Hidden and T('RUN THE EXPERIMENT?')or T('CREATE THIS DOG?')end
 local cards=planCards(plan)
 local withOdds=plan.Chances~=nil
 st.Confirming=true;renderSteps()
 cue('Step')
 local modal=Kit.Modal({Title=title,Body=confirmBody(plan,e),Cards=cards,CardKind='Dog',NoTranslate=true,Accent=action and action.Color or ACCENT,
  Danger=plan.Destructive==true or plan.Reroll==true,Hold=plan.HighValue and 1.2 or 0,
  ConfirmText=T(action and action.Confirm or'CONFIRM'),ConfirmStyle=(plan.Destructive or plan.Reroll)and'danger'or'success',Width=560,
  ContentHeight=withOdds and 40 or nil,Content=withOdds and function(f,w)
   local bar=oddsBar(f,f.ZIndex)
   place(bar.Root,0,2,w,36)
   bar.Set(plan.Chances,w)
  end or nil})
 modal:Then(function(confirmed)
  st.Confirming=false;renderSteps()
  if confirmed then commit(plan)end
 end)
end

function S.Primary()
 if st.Busy or not ui then return end
 if st.View~='steps'then return end
 if st.Step==1 then
  if selectedDog()then goStep(2)end
  return
 end
 if not st.Action then return end
 if cooling()then toast(T('The chamber is cooling down'),'warn');return end
 local e=evaluate(st.Action)
 if e.Reason or not e.Args then if e.Reason then toast(e.Reason,'warn')end;cue('Deny');return end
 st.Busy=true;ui.BarGo:SetBusy(true)
 local ok,plan=request('LabPreview',e.Args)
 st.Busy=false;ui.BarGo:SetBusy(false)
 if not ok or type(plan)~='table'then
  local text=tostring(plan)
  toast(said(text),'error');cue('Deny')
  if text=='Enter Mutation Lab and approach the genetics terminal'then st.Message=text;setView('splash')end
  return
 end
 openConfirm(plan,e)
end

showResult=function(result)
 build()
 st.Result=result
 local d=result.Dog
 local before=result.BeforeDog
 local procedure=result.Procedure
 local head,headColor,body={},Theme.Ink,{}
 local preview=nil
 if procedure=='Mutation'or procedure=='Targeting'then
  local after=d and d.Variant or'Normal'
  local was=before and before.Variant or'Normal'
  headColor=Theme.Darken(G.VariantColor(after),.15)
  if after~=was and after~='Normal'then head=upper(variantName(after))..'!'
  elseif after==was then head=F('STILL %s',upper(variantName(after)))
  else head=upper(variantName(after))end
  table.insert(body,F('%s → %s',colored(variantName(was),Theme.Darken(G.VariantColor(was),.2)),colored(variantName(after),Theme.Darken(G.VariantColor(after),.2))))
  if after=='Normal'and was=='Normal'then table.insert(body,T('No mutation this time. Try again, or use gene targeting for better odds.'))end
  preview=d
 elseif procedure=='Extraction'then
  head=T('DNA EXTRACTED');headColor=Theme.Darken(P.red,.05)
  preview=before
 elseif result.RecipeId=='ASCEND'then
  head=F('ASCENSION %d!',d and d.AscensionLevel or 0);headColor=Theme.Darken(P.gold,.2)
  preview=d
  table.insert(body,T('Two copies merged into this dog. Its income grows with every Ascension.'))
 else
  if result.Success then
   head=result.FirstDiscovery and T('NEW DISCOVERY!')or T('NEW DOG CREATED!')
   headColor=Theme.Darken(G.VariantColor(d and d.Variant),.15)
   preview=d
  else
   head=T('UNSTABLE RESULT');headColor=Theme.InkMuted
   preview=d
   table.insert(body,T('All dogs survived and half the DNA came back. Coins, bones and catalysts were used.'))
  end
 end
 if next(result.DNA or{})then table.insert(body,F('DNA: %s',rewardsText(result.DNA,true)))end
 local consumed=#(result.Consumed or{})
 if consumed>0 then table.insert(body,F('Dogs used: %d',consumed))end
 if(result.ReturnedArtifacts or 0)>0 then table.insert(body,F('%d artifacts returned to your inventory.',result.ReturnedArtifacts))end
 ui.ResultHead.Text=head;ui.ResultHead.TextColor3=headColor
 ui.ResultName.Text=preview and(preview.DisplayName or preview.DogId)or''
 ui.ResultBody.Text=table.concat(body,'\n')
 local tint=preview and G.VariantColor(preview.Variant)or ACCENT
 ui.ResultGradient.Color=ColorSequence.new(tint:Lerp(Theme.White,.35),Theme.White)
 ui.ResultSlot:Show(preview and{Kind='Dog',DogId=preview.DogId,Variant=preview.Variant}or nil)
 ui.ResultTimer:SetEndsAt(st.CooldownEndsAt)
 local again=d~=nil and dogsOf(profile())[d.DogUid]~=nil and(procedure=='Mutation'or procedure=='Targeting')
 ui.ResultAgain.Instance.Visible=again
 ui.ResultNew:SetText(T('NEW EXPERIMENT'))
 if not win.IsOpen then win:Open()end
 setView('result')
 if not Kit.Motion.Reduced()then
  ui.ResultScale.Scale=.86
  Kit.Motion.Tween(ui.ResultScale,.28,{Scale=1},Enum.EasingStyle.Back)
 end
 cue(((d and C.HighValueVariants[d.Variant])or result.FirstDiscovery)and'Rare'or'Reveal')
 -- The recipe book may have changed (a discovery); the cooldown is fresh.
 task.spawn(function()loadInfo(true)end)
end

function S.Again()
 local result=st.Result
 st.Result=nil
 local d=result and result.Dog
 if d and dogsOf(profile())[d.DogUid]then
  st.DogUid=d.DogUid;st.Action=result.Procedure=='Targeting'and'Targeting'or'Mutation'
  setView('steps');goStep(2)
 else
  setView('steps');goStep(1)
 end
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
loadInfo=function(quiet)
 local ok,info=request('LabInfo',{})
 if ok and type(info)=='table'then
  st.Info=info
  if info.CooldownEndsAt then
   local remaining=math.max(0,(tonumber(info.CooldownEndsAt)or 0)-(tonumber(info.Now)or 0))
   st.CooldownEndsAt=math.max(st.CooldownEndsAt or 0,Kit.Now()+remaining)
  end
  return true
 end
 if not quiet then st.Message=tostring(info)end
 return false
end

function S.OnOpen()
 st.OpenToken=(st.OpenToken or 0)+1
end
function S.OnClose(reason)
 st.Confirming=false
 if reason~='navigation'then
  Kit.Preview.Purge()
  -- The result card is shown once; the next visit starts from the steps.
  if st.View=='result'then st.View='steps';st.Result=nil end
 end
end

-- Opens the lab window (any entry point). At the terminal: loads the lab; elsewhere: the way there.
function S.Open()
 build()
 local player=Players.LocalPlayer
 local atTerminal=player~=nil and Access.CanUse(player)
 if not win.IsOpen then win:Open()end
 st.Snapshot=net().Cached()or st.Snapshot
 computeOwned()
 if not atTerminal then
  st.Message=nil
  setView('splash')
  task.spawn(function()
   local snapshot=net().Snapshot(4)
   if snapshot then st.Snapshot=snapshot;renderSplash()end
  end)
  return
 end
 st.View='loading';ui.LoadingText.Text=T('Connecting to the genetics terminal…');ui.LoadingRetry.Instance.Visible=false
 layout()
 local token=st.OpenToken
 task.spawn(function()
  local snapshot=net().Snapshot(2)
  if snapshot then st.Snapshot=snapshot end
  local ok=loadInfo(false)
  if token~=st.OpenToken or not win.IsOpen then return end
  if not ok then
   local text=tostring(st.Message or'')
   if text=='Enter Mutation Lab and approach the genetics terminal'then setView('splash');return end
   ui.LoadingText.Text=said(text);ui.LoadingRetry.Instance.Visible=true
   return
  end
  st.Message=nil
  cue('Console')
  computeOwned()
  if st.DogUid and not selectedDog()then st.DogUid=nil end
  st.View='steps'
  if st.Step==2 and not selectedDog()and st.Action~='Recipes'then st.Step=1 end
  refresh()
  goStep(st.Step)
 end)
end

function S.Close()
 if win and win.IsOpen then win:Close('close')end
end

-- Hooks for the runtime emulation tests (scratch harness): show a view / a result card directly.
function S.ShowResult(result)showResult(result)end
function S.SetView(view)setView(view)end

-- Legacy Menus page ('Lab' in EconomyScreens): the window replaces it.
function S.Build(c)
 local _=c
 task.defer(S.Open)
end

return S
