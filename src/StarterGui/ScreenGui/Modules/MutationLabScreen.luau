-- NUCLEAR MUTATION window (the lab's cooling tower; UI kit, Key 'Lab'; docs/LAB.md, docs/UIKIT.md). LabConfig.SimpleMode routes
-- N.OpenPage/OpenScreen('Lab') here (GUIIntegration.openLab); the old Modules.LabScreen stays as the rollback.
--   1 CHOOSE A DOG  your dogs (rarest first, variant tag, search); dogs that cannot enter the machine are
--                   greyed out with the reason, blocked ones that a tap can fix (locked, kennel...) say so
--   2 MUTATE        big preview, current mutation, every possible result as a chip (odds % + income bonus,
--                   the server's LabInfo odds: world events and upgrades included), cost (or FREE), one big
--                   MUTATE button (hold-to-confirm when the dog is already mutated: it can lose it)
--   then            LabPreview + LabCommit, the window closes, Modules.LabPresentation plays the machine,
--                   and the result card offers MUTATE AGAIN (same dog, new cost), CHOOSE ANOTHER DOG, CLOSE.
-- Text: Localization.Lab (UI / Templates, self-localized; labels carry NoTranslate). Server replies go
-- through said() and stay translatable for the shared ones (busy, saving...).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Kit=require(script.Parent.Kit)
local C=require(RS.LabConfig)
local G=require(RS.LabGenetics)
local Access=require(RS.LabAccess)
local Audio=require(RS.LabAudioConfig)
local Defs=require(RS.DogEconomy.DogDefinitions)
local Base=require(RS.DogEconomy.Config)
local Dict=require(RS:WaitForChild('Localization'):WaitForChild('Lab'))
local Theme,Format=Kit.Theme,Kit.Format
local P=Theme.Colors
local ACCENT=Color3.fromRGB(38,190,150)
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
local function upper(s)
 local out={}
 for _,code in utf8.codes(tostring(s or''))do
  if code>=0x430 and code<=0x44F then code-=0x20 elseif code==0x451 then code=0x401 elseif code>=97 and code<=122 then code-=32 end
  table.insert(out,utf8.char(code))
 end
 return table.concat(out)
end
local function fold(s)
 local out={}
 for _,code in utf8.codes(tostring(s or''))do
  if code>=0x410 and code<=0x42F then code+=0x20 elseif code==0x401 then code=0x451 elseif code>=65 and code<=90 then code+=32 end
  table.insert(out,utf8.char(code))
 end
 return table.concat(out)
end
local function variantName(v)return upper(T(v or'Normal'))end
local function pct(x)
 x=tonumber(x)or 0
 if x>=10 then return string.format('%.0f%%',x)elseif x>=1 then return string.format('%.1f%%',x)elseif x>0 then return string.format('%.1f%%',x)end
 return '0%'
end
local function colored(text,color)return '<font color="'..Theme.Hex(color)..'">'..text..'</font>'end
local STATUS={Locked='LOCKED',Kennel='IN KENNEL',Busy='WORKING',Favorite='FAVORITE',Walking='ON THE WAY',Display='ON DISPLAY',Unavailable='UNAVAILABLE'}

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st:any={View='loading',Uid=nil,Search='',Info=nil,Snapshot=nil,Busy=false,CooldownEndsAt=0,Result=nil,Launching=false,OpenToken=0}
S.State=st
local ui:any=nil
local win:any=nil
local NetModule=nil
local function net()NetModule=NetModule or require(script.Parent.Net);return NetModule end
local PresentationModule=nil
local function presentation()PresentationModule=PresentationModule or require(script.Parent.LabPresentation);return PresentationModule end
local function nav()local ok,n=pcall(require,script.Parent.GUIIntegration);return ok and n or nil end
local function profile()return st.Snapshot and st.Snapshot.Profile or nil end
local function dogsOf(p)return type(p)=='table'and type(p.Dogs)=='table'and p.Dogs or{}end
local function selected()local d=st.Uid and dogsOf(profile())[st.Uid];return type(d)=='table'and d or nil end
local function cooling()return Kit.Now()<(st.CooldownEndsAt or 0)end
local function toast(text,kind,server)Kit.Toast(text,{Kind=kind or'info',NoTranslate=server~=true})end
local function cue(name)
 local lab=Access.Model();local anchor=lab and lab:FindFirstChild('InteractionAnchor')
 Audio.Play(name,name=='Console'and anchor or nil)
end
local function rarityOf(d)local def=Defs[d.DogId];return def and def.Rarity or d.Rarity or'Common'end
-- Hidden copies of every dog name (DOGROTS_AutoTranslateUI translates them): search in the player's language.
local probes={}
local function shownName(d)local probe=probes[d.DogId];return probe and probe.Parent and probe.Text or''end

-- Odds of a reroll: the server's (LabInfo.Odds: world events and the DogMutation bonus included), else base.
local function odds()
 local rows=st.Info and st.Info.Odds
 if type(rows)=='table'and #rows>0 then return rows end
 local base=G.Chances(Base.Variants,nil,C.Stability.Mutation,0)
 for i,row in base do row.Bonus=Base.Variants[i].Bonus end
 return base
end
local function cost(d)
 if st.Info and st.Info.TutorialComplete==false then return {Cash=0,Bones=0,Free=true}end
 local c=G.Cost('Mutation',d);return {Cash=c.Cash,Bones=c.Bones,Free=false}
end
local function affordable(c)
 local p=profile();if not p then return true end
 return(tonumber(p.Cash)or 0)>=c.Cash and(tonumber(p.Bones)or 0)>=c.Bones
end
local function costText(c)
 if c.Free then return T('FREE')end
 local p=profile();local cash,bones=tonumber(p and p.Cash)or math.huge,tonumber(p and p.Bones)or math.huge
 local a='💰 '..Format.Short(c.Cash,1);local b='🦴 '..tostring(c.Bones)
 if cash<c.Cash then a=colored(a,P.red)end
 if bones<c.Bones then b=colored(b,P.red)end
 return a..'   '..b
end
local function mutated(d)return d and(d.Variant or'Normal')~='Normal'end

------------------------------------------------------------------------------------------------
-- Builders
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
local function frame(parent,name,z)
 return Kit.New('Frame',{Name=name,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=z or Z,Size=UDim2.fromOffset(10,10)},parent)
end
local function panel(parent,name,z,color)
 local f=Kit.New('Frame',{Name=name,BackgroundColor3=color or Theme.White,BorderSizePixel=0,ZIndex=z or Z},parent)
 Kit.Corner(f,Theme.Radius.Card);Kit.Stroke(f,P.edge,2,.6)
 return f
end

-- One chip per possible result: colour bar, name, chance, income bonus; "NOW" marks the dog's variant.
local function oddsChips(parent)
 local o={Root=frame(parent,'Odds',Z+1),Chips={}}
 for i,v in ipairs(Base.Variants)do
  local chip=Kit.New('Frame',{Name='Chip_'..v.Name,BackgroundColor3=Theme.White,BorderSizePixel=0,ZIndex=Z+2,LayoutOrder=i},o.Root)
  Kit.Corner(chip,Theme.Radius.Small)
  local stroke=Kit.Stroke(chip,Theme.VariantColor(v.Name),2,.2)
  local bar=Kit.New('Frame',{Name='Bar',BackgroundColor3=Theme.VariantColor(v.Name),BorderSizePixel=0,ZIndex=Z+3},chip)
  Kit.Corner(bar,Theme.Radius.Small)
  local name=label(chip,{Name='Name',TextSize=14,Scaled=true,MinTextSize=8,AlignX='Center',Color=Theme.Darken(Theme.VariantColor(v.Name),.45),ZIndex=Z+3})
  local chance=label(chip,{Name='Chance',TextSize=22,Scaled=true,MinTextSize=10,AlignX='Center',Font='numeric',ZIndex=Z+3})
  local bonus=label(chip,{Name='Bonus',TextSize=13,Scaled=true,MinTextSize=8,AlignX='Center',Color=Theme.InkMuted,ZIndex=Z+3})
  local now=Kit.Pill(chip,{Name='Now',Text='',Height=16,TextSize=10,Color=P.edge,ZIndex=Z+4,NoTranslate=true})
  o.Chips[v.Name]={Root=chip,Stroke=stroke,Bar=bar,Name=name,Chance=chance,Bonus=bonus,Now=now}
 end
 function o.Set(rows,current)
  local by={};for _,r in ipairs(rows)do by[r.Name]=r end
  for name,c in o.Chips do
   local r=by[name]
   c.Name.Text=variantName(name)
   c.Chance.Text=pct(r and r.Percent or 0)
   local b=tonumber(r and r.Bonus)or 0
   c.Bonus.Text=b>0 and F('+%d%% income',math.floor(b*100+.5))or T('no bonus')
   c.Now:Set(T('NOW'),P.edge);c.Now:SetVisible(name==(current or'Normal'))
   c.Stroke.Thickness=name==(current or'Normal')and 3 or 2
  end
 end
 function o.Layout(w,h,columns)
  place(o.Root,0,0,w,h)
  local n=#Base.Variants;local cols=columns or n;local rows=math.ceil(n/cols);local gap=8
  local cw=(w-gap*(cols-1))/cols;local ch=(h-gap*(rows-1))/rows
  for i,v in ipairs(Base.Variants)do
   local c=o.Chips[v.Name];local col=(i-1)%cols;local row=math.floor((i-1)/cols)
   place(c.Root,col*(cw+gap),row*(ch+gap),cw,ch)
   place(c.Bar,4,4,cw-8,6)
   place(c.Name,4,12,cw-8,ch*.22)
   place(c.Chance,4,12+ch*.22,cw-8,ch*.38)
   place(c.Bonus,4,12+ch*.62,cw-8,ch*.24)
   c.Now.Instance.Position=UDim2.new(1,-4,0,-6);c.Now.Instance.AnchorPoint=Vector2.new(1,0)
  end
 end
 return o
end

------------------------------------------------------------------------------------------------
-- Cards of step 1
------------------------------------------------------------------------------------------------
local function eligible(d)
 local p=profile();local ok,code,message=G.Check(p,d)
 return ok,code,message
end
local function cardData(d)
 local ok,code,message=eligible(d)
 local fix=not ok and G.Fix(code,d)
 local badge=nil
 if not ok and STATUS[code]then badge=T(STATUS[code])end
 return {
  Id=d.DogUid,Name=d.DisplayName or(Defs[d.DogId]and Defs[d.DogId].DisplayName)or d.DogId,Rarity=rarityOf(d),Variant=d.Variant,
  Preview={Kind='Dog',DogId=d.DogId,Variant=d.Variant},
  Badge=badge,BadgeColor=fix and P.gold or P.edge,
  Disabled=not ok and not fix,DisabledReason=(not ok and not fix)and said(message)or nil,
  Selected=d.DogUid==st.Uid,
 }
end
local function dogList()
 local list={};local q=fold(st.Search or'')
 for _,d in pairs(dogsOf(profile()))do
  if type(d)=='table'and d.DogUid then
   if q==''or string.find(fold(d.DisplayName or d.DogId),q,1,true)or string.find(fold(shownName(d)),q,1,true)then table.insert(list,d)end
  end
 end
 table.sort(list,function(a,b)
  local ra,rb=Theme.RarityOrder(rarityOf(a)),Theme.RarityOrder(rarityOf(b))
  if ra~=rb then return ra>rb end
  local va,vb=Theme.VariantRank[a.Variant or'Normal']or 1,Theme.VariantRank[b.Variant or'Normal']or 1
  if va~=vb then return va>vb end
  local na,nb=tostring(a.DisplayName or a.DogId),tostring(b.DisplayName or b.DogId)
  if na~=nb then return na<nb end
  return a.DogUid<b.DogUid
 end)
 return list
end

------------------------------------------------------------------------------------------------
-- Views
------------------------------------------------------------------------------------------------
local layout,setView,renderMutate,showResult

local function build()
 if ui then return ui end
 ui={}
 S.UI=ui
 win=Kit.Window.new({Key='Lab',Name='MutationLabWindow',Title=T('NUCLEAR MUTATION'),Subtitle=T('Choose a dog · press MUTATE'),Accent=ACCENT,Icon='Lab',NoTranslate=true,MaxSize=Vector2.new(1000,720),
  OnOpen=function()st.OpenToken+=1 end,OnClose=function(_,reason)S.OnClose(reason)end})
 S.Window=win
 local body=win.Body
 local probeFrame=Kit.New('Frame',{Name='NameProbes',BackgroundTransparency=1,Visible=false,Size=UDim2.fromOffset(1,1)},body)
 for id,def in pairs(Defs)do
  if type(def)=='table'and type(def.DisplayName)=='string'then
   probes[id]=Kit.New('TextLabel',{Name=tostring(id),Text=def.DisplayName,BackgroundTransparency=1,Size=UDim2.fromOffset(1,1)},probeFrame)
  end
 end
 ui.Views=frame(body,'Views',Z)
 -- 1 CHOOSE A DOG
 local pick=frame(ui.Views,'PickView',Z);ui.Pick=pick
 ui.PickTitle=label(pick,{Name='Step',Text=T('1 · CHOOSE A DOG'),TextSize=21,Scaled=true,MinTextSize=12,Color=Theme.Ink})
 ui.Search=Kit.SearchBox(pick,{Name='MachineSearch',Placeholder=T('Search dogs'),ZIndex=Z+1,OnChange=function(text)st.Search=text;S.RefreshGrid(true)end})
 ui.GridHost=frame(pick,'GridHost',Z)
 ui.Grid=Kit.CardGrid(ui.GridHost,{Name='Dogs',Kind='Dog',ZIndex=Z+1,CardSize=Vector2.new(150,200),Map=cardData,
  Key=function(d)return d.DogUid end,OnClick=function(d)S.Pick(d.DogUid)end,
  Empty={Icon='Dogs',Title=T('You have no dogs yet'),Body=T('Adopt dogs on the dog line or open lucky blocks.')}})
 -- 2 MUTATE
 local mut=frame(ui.Views,'MutateView',Z);ui.Mutate=mut
 ui.DogPanel=panel(mut,'Dog',Z)
 ui.DogHolder=frame(ui.DogPanel,'Preview',Z+1)
 ui.DogSlot=Kit.Preview.Slot(ui.DogHolder)
 ui.DogName=label(ui.DogPanel,{Name='DogName',TextSize=24,Scaled=true,MinTextSize=12,AlignX='Center',NoTranslate=false,ZIndex=Z+2})
 ui.DogRarity=Kit.RarityTag(ui.DogPanel,'Common',{Height=22,TextSize=12,ZIndex=Z+2})
 ui.DogVariant=Kit.VariantTag(ui.DogPanel,'Normal',{Height=22,TextSize=12,ZIndex=Z+2,ShowNormal=true})
 ui.Back=Kit.Button(mut,{Name='Back',Text='‹ '..T('CHOOSE ANOTHER DOG'),Style='secondary',TextSize=15,ZIndex=Z+2,NoTranslate=true,OnClick=function()S.Choose()end})
 ui.OddsTitle=label(mut,{Name='OddsTitle',Text=T('POSSIBLE RESULTS'),TextSize=17,Scaled=true,MinTextSize=10,Color=Theme.InkMuted})
 ui.Odds=oddsChips(mut)
 ui.CostLabel=label(mut,{Name='Cost',TextSize=22,Rich=true,Scaled=true,MinTextSize=11,AlignX='Center'})
 ui.Warning=Kit.Pill(mut,{Name='Warning',Text='',Height=28,TextSize=14,Color=P.red,ZIndex=Z+2,NoTranslate=true})
 ui.Fix=Kit.Button(mut,{Name='Fix',Text='',Style='gold',ZIndex=Z+2,NoTranslate=true,OnClick=function()S.FixBlock()end})
 ui.Go=Kit.Button(mut,{Name='Mutate',Text=T('MUTATE'),Style='success',TextSize=28,ZIndex=Z+2,NoTranslate=true,OnClick=function()S.Mutate(st.Uid)end})
 ui.Timer=Kit.Countdown(mut,{Name='Cooldown',TextSize=15,AlignX='Center',Color=Theme.Darken(P.gold,.25),ZIndex=Z+2,Prefix=T('Machine ready in '),DoneText='',EndsAt=0,
  OnDone=function()task.defer(function()if ui then renderMutate()end end)end})
 -- RESULT
 local res=frame(ui.Views,'ResultView',Z);ui.Result=res
 ui.ResultCard=panel(res,'ResultCard',Z+1)
 ui.ResultScale=Kit.New('UIScale',{Name='Pop'},ui.ResultCard)
 ui.ResultGlow=Kit.New('Frame',{Name='Glow',BackgroundColor3=Theme.White,BorderSizePixel=0,ZIndex=Z+1},ui.ResultCard)
 Kit.Corner(ui.ResultGlow,Theme.Radius.Card)
 ui.ResultGradient=Kit.New('UIGradient',{Rotation=90},ui.ResultGlow)
 ui.ResultHolder=frame(ui.ResultCard,'Preview',Z+2)
 ui.ResultSlot=Kit.Preview.Slot(ui.ResultHolder)
 ui.ResultHead=label(ui.ResultCard,{Name='Headline',TextSize=36,Scaled=true,MinTextSize=16,AlignX='Center',Stroke=.2,ZIndex=Z+3})
 ui.ResultName=label(ui.ResultCard,{Name='DogName',TextSize=20,Scaled=true,MinTextSize=11,AlignX='Center',NoTranslate=false,ZIndex=Z+3})
 ui.ResultBody=label(ui.ResultCard,{Name='Body',TextSize=17,Rich=true,Wrap=true,AlignX='Center',AlignY='Top',Color=Theme.InkMuted,ZIndex=Z+3})
 ui.Again=Kit.Button(ui.ResultCard,{Name='Again',Text=T('MUTATE AGAIN'),Style='success',TextSize=22,ZIndex=Z+3,NoTranslate=true,OnClick=function()S.Again()end})
 ui.AgainTimer=Kit.Countdown(ui.ResultCard,{Name='AgainCooldown',TextSize=14,AlignX='Center',Color=Theme.Darken(P.gold,.25),ZIndex=Z+3,Prefix=T('Machine ready in '),DoneText='',EndsAt=0,
  OnDone=function()task.defer(function()if ui and st.View=='result'then S.RenderAgain()end end)end})
 ui.Other=Kit.Button(ui.ResultCard,{Name='Another',Text=T('CHOOSE ANOTHER DOG'),Style='secondary',TextSize=16,ZIndex=Z+3,NoTranslate=true,OnClick=function()S.Choose()end})
 ui.Close=Kit.Button(ui.ResultCard,{Name='Close',Text=T('CLOSE'),Style='ghost',TextSize=16,ZIndex=Z+3,NoTranslate=true,OnClick=function()if win then win:Close('close')end end})
 -- SPLASH (away from the console) and LOADING
 local splash=frame(ui.Views,'SplashView',Z);ui.Splash=splash
 ui.SplashIcon=Kit.Icon(splash,'Lab',{ZIndex=Z+1,Color=ACCENT})
 ui.SplashTitle=label(splash,{Name='Title',Text=T('THE NUCLEAR TOWER'),TextSize=30,Scaled=true,MinTextSize=16,AlignX='Center'})
 ui.SplashBody=label(splash,{Name='Body',Text=T('Walk up to the console in front of the nuclear tower and press START MUTATION.'),TextSize=18,Wrap=true,AlignX='Center',AlignY='Top',Color=Theme.InkMuted})
 ui.SplashGo=Kit.Button(splash,{Name='ShowTheWay',Text=T('SHOW THE WAY'),Style='primary',Color=ACCENT,ZIndex=Z+1,NoTranslate=true,OnClick=function()
  local n=nav();if win then win:Close('navigate')end
  if n and n.Navigate then n.Navigate(S.Destination)end
 end})
 local loading=frame(ui.Views,'LoadingView',Z);ui.Loading=loading
 ui.LoadingText=label(loading,{Name='Text',Text='',TextSize=19,Wrap=true,AlignX='Center',Color=Theme.InkMuted})
 ui.LoadingRetry=Kit.Button(loading,{Name='Retry',Text=T('RETRY'),Style='primary',ZIndex=Z+1,NoTranslate=true,OnClick=function()S.Open()end})
 win.Resized:Connect(function()layout()end)
 win.Maid:Give(net().Changed:Connect(function(snapshot)
  if win and win.IsOpen then
   st.Snapshot=snapshot
   if st.View=='pick'then S.RefreshGrid(false)elseif st.View=='mutate'then renderMutate()end
  end
 end))
 return ui
end

layout=function()
 if not(ui and win)then return end
 local L=win:GetLayout();local w,h=L.Width,L.Height
 if w<10 or h<10 then return end
 local phone=L.Phone
 place(ui.Views,0,0,w,h)
 for _,v in{ui.Pick,ui.Mutate,ui.Result,ui.Splash,ui.Loading}do place(v,0,0,w,h)end
 -- Pick
 if phone and w<560 then
  place(ui.PickTitle,2,0,w-4,30);place(ui.Search.Instance,0,34,w,40);place(ui.GridHost,0,82,w,h-82)
 else
  local sw=math.min(320,w*.42)
  place(ui.PickTitle,2,4,w-sw-16,36);place(ui.Search.Instance,w-sw,0,sw,42);place(ui.GridHost,0,52,w,h-52)
 end
 -- Mutate: the button sits at the bottom; above it the timer, the cost and the warning; the odds take the rest.
 local portrait=w<620
 local compact=h<440
 local bh=compact and 56 or(portrait and 60 or 78)
 local costH=compact and 26 or 32
 local warnH=30
 local function rightColumn(x,rw,top,bottom)
  place(ui.Go.Instance,x,bottom-bh,rw,bh);place(ui.Fix.Instance,x,bottom-bh,rw,bh)
  place(ui.Timer.Instance,x,bottom-bh-20,rw,18)
  local yCost=bottom-bh-20-costH
  place(ui.CostLabel,x,yCost,rw,costH)
  local yWarn=yCost-warnH
  ui.Warning.Instance.Position=UDim2.new(0,x+rw/2,0,yWarn);ui.Warning.Instance.AnchorPoint=Vector2.new(.5,0)
  local titleH=compact and 18 or 22
  place(ui.OddsTitle,x+2,top,rw-4,titleH)
  local oh=math.max(56,yWarn-6-(top+titleH+4))
  local cols=(compact and rw>=420)and 6 or 3
  ui.Odds.Layout(rw,math.min(oh,cols==6 and 110 or 210),cols)
  ui.Odds.Root.Position=UDim2.fromOffset(x,top+titleH+4)
 end
 if portrait then
  local backH=38
  place(ui.Back.Instance,0,h-backH,w,backH)
  local bottom=h-backH-6
  -- Room for the odds first; the dog preview gets what is left (but stays visible).
  local need=bh+20+costH+warnH+6+22+4+150
  local ph=math.floor(math.max(110,math.min(h*.36,w*.62,bottom-need)))
  place(ui.DogPanel,0,0,w,ph)
  place(ui.DogHolder,8,4,w-16,ph-58);place(ui.DogName,10,ph-54,w-20,26)
  ui.DogRarity.Instance.Position=UDim2.new(.5,-6,0,ph-26);ui.DogRarity.Instance.AnchorPoint=Vector2.new(1,0)
  ui.DogVariant.Instance.Position=UDim2.new(.5,6,0,ph-26);ui.DogVariant.Instance.AnchorPoint=Vector2.new(0,0)
  rightColumn(0,w,ph+8,bottom)
 else
  local lw=math.floor(w*.4)
  place(ui.DogPanel,0,0,lw,h)
  local nameH=compact and 26 or 32
  place(ui.DogHolder,10,10,lw-20,h-(compact and 74 or 110));place(ui.DogName,12,h-(compact and 62 or 96),lw-24,nameH)
  ui.DogRarity.Instance.Position=UDim2.new(0,lw/2-6,0,h-(compact and 32 or 58));ui.DogRarity.Instance.AnchorPoint=Vector2.new(1,0)
  ui.DogVariant.Instance.Position=UDim2.new(0,lw/2+6,0,h-(compact and 32 or 58));ui.DogVariant.Instance.AnchorPoint=Vector2.new(0,0)
  local x=lw+16;local rw=w-x
  local backH=compact and 34 or 40
  place(ui.Back.Instance,x,0,math.min(300,rw),backH)
  rightColumn(x,rw,backH+(compact and 6 or 12),h)
 end
 -- Result: one column, or preview left and text right on short landscape screens.
 local wide=w>=620 and h<520
 if wide then
  local cw=w;local ch=h
  place(ui.ResultCard,0,0,cw,ch);place(ui.ResultGlow,0,0,cw,ch)
  local lw=math.floor(cw*.42)
  place(ui.ResultHolder,10,10,lw-20,ch-20)
  local x=lw+6;local rw=cw-x-14
  local y=10
  place(ui.ResultHead,x,y,rw,40);y+=42
  place(ui.ResultName,x,y,rw,22);y+=24
  local buttons=60+8+44
  place(ui.ResultBody,x,y,rw,math.max(30,ch-y-buttons-30))
  place(ui.AgainTimer.Instance,x,ch-buttons-24,rw,18)
  place(ui.Again.Instance,x,ch-buttons-4,rw,58)
  local half=(rw-10)/2
  place(ui.Other.Instance,x,ch-46,half,42);place(ui.Close.Instance,x+half+10,ch-46,half,42)
 else
  local cw=math.min(w,phone and w or 560);local ch=h
  place(ui.ResultCard,(w-cw)/2,0,cw,ch)
  place(ui.ResultGlow,0,0,cw,ch)
  local buttons=(phone and 62 or 66)+10+48+10
  local pv=math.floor(math.max(90,math.min(ch*.36,cw*.62,ch-buttons-150)))
  place(ui.ResultHolder,(cw-pv*1.3)/2,10,pv*1.3,pv)
  local y=pv+14
  place(ui.ResultHead,14,y,cw-28,phone and 40 or 48);y+=phone and 42 or 50
  place(ui.ResultName,14,y,cw-28,24);y+=26
  place(ui.ResultBody,18,y,cw-36,math.max(36,ch-y-buttons-24))
  place(ui.AgainTimer.Instance,14,ch-buttons-20,cw-28,18)
  place(ui.Again.Instance,14,ch-buttons,cw-28,phone and 62 or 66)
  local half=(cw-28-10)/2
  place(ui.Other.Instance,14,ch-58,half,48);place(ui.Close.Instance,14+half+10,ch-58,half,48)
 end
 -- Splash / loading
 local icon=compact and 56 or 96
 local sy=math.max(6,(h-(icon+12+40+8+70+12+54))/2)
 place(ui.SplashIcon,(w-icon)/2,sy,icon,icon);sy+=icon+12
 place(ui.SplashTitle,20,sy,w-40,40);sy+=48
 place(ui.SplashBody,30,sy,w-60,70);sy+=82
 place(ui.SplashGo.Instance,(w-math.min(280,w-20))/2,sy,math.min(280,w-20),54)
 place(ui.LoadingText,20,h*.38,w-40,60)
 place(ui.LoadingRetry.Instance,(w-200)/2,h*.38+70,200,48)
end

setView=function(view)
 st.View=view
 if not ui then return end
 ui.Pick.Visible=view=='pick';ui.Mutate.Visible=view=='mutate';ui.Result.Visible=view=='result'
 ui.Splash.Visible=view=='splash';ui.Loading.Visible=view=='loading'
 if win then
  if view=='pick'then win:SetTitle(T('NUCLEAR MUTATION'),T('1 · CHOOSE A DOG'))
  elseif view=='mutate'then win:SetTitle(T('NUCLEAR MUTATION'),T('2 · PRESS MUTATE'))
  elseif view=='result'then win:SetTitle(T('NUCLEAR MUTATION'),T('RESULT'))
  else win:SetTitle(T('NUCLEAR MUTATION'),T('Choose a dog · press MUTATE'))end
 end
 layout()
end

function S.RefreshGrid(reset)
 if not ui then return end
 ui.Grid:SetItems(dogList(),{ResetScroll=reset==true})
end

renderMutate=function()
 if not ui then return end
 local d=selected()
 if not d then setView('pick');S.RefreshGrid(true);return end
 ui.DogSlot:Show({Kind='Dog',DogId=d.DogId,Variant=d.Variant})
 ui.DogName.Text=d.DisplayName or d.DogId
 ui.DogRarity:SetRarity(rarityOf(d));ui.DogVariant:SetVariant(d.Variant or'Normal')
 ui.Odds.Set(odds(),d.Variant)
 local c=cost(d)
 ui.CostLabel.Text=c.Free and colored(T('FIRST TRY FREE'),Theme.Darken(P.green,.25))or(T('Cost')..':  '..costText(c))
 local ok,code,message=eligible(d)
 local fix=not ok and G.Fix(code,d)
 ui.Warning:SetVisible(false)
 if mutated(d)then ui.Warning:Set('⚠ '..F('Can lose %s',variantName(d.Variant)),P.red);ui.Warning:SetVisible(true)end
 ui.Fix.Instance.Visible=fix~=nil and fix~=false
 ui.Go.Instance.Visible=not ui.Fix.Instance.Visible
 if fix then ui.Fix:SetText(T(fix.Text))end
 ui.Go.Props.Hold=mutated(d)and 1.2 or 0
 ui.Go:SetText(mutated(d)and T('HOLD TO MUTATE')or T('MUTATE'))
 ui.Go:SetPrice(nil)
 local disabled=(not ok and not fix)or cooling()or not affordable(c)
 ui.Go:SetDisabled(disabled)
 ui.Timer:SetEndsAt(cooling()and st.CooldownEndsAt or 0)
 ui.Timer.Instance.Visible=cooling()
 if not ok and not fix then ui.Warning:Set(said(message),P.red);ui.Warning:SetVisible(true)end
 if ok and not affordable(c)then ui.Warning:Set(said('Not enough Coins or Bones'),P.red);ui.Warning:SetVisible(true)end
end

------------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------------
function S.Pick(uid)
 st.Uid=uid;cue('Select')
 setView('mutate');renderMutate()
end
function S.Choose()
 if st.View=='result'then presentation().Release()end
 st.Result=nil
 setView('pick');S.RefreshGrid(false)
end
function S.FixBlock()
 local d=selected();if not d or st.Busy then return end
 local _,code=eligible(d);local fix=G.Fix(code,d);if not fix then return end
 st.Busy=true;ui.Fix:SetBusy(true)
 local ok,result=net().Request(fix.Action,fix.Args)
 st.Busy=false;ui.Fix:SetBusy(false)
 if not ok then toast(said(result),'error',true);cue('Deny');return end
 local snapshot=type(result)=='table'and result.StateSnapshot or net().Snapshot(0)
 if snapshot then st.Snapshot=snapshot end
 renderMutate()
end

local function play(result)
 local n=nav();local epoch=nil
 st.Launching=true
 if n and n.BeginReward then local ok,value=pcall(n.BeginReward,result.Token);if ok then epoch=value end end
 st.Launching=false
 local ok,err=pcall(function()presentation().Play(result)end)
 if not ok then warn('Mutation machine cinematic: '..tostring(err))end
 if n and n.EndReward and epoch then pcall(n.EndReward,epoch)end
 showResult(result)
end

-- Preview + commit of one mutation; the window closes and the machine plays.
function S.Mutate(uid)
 if st.Busy or not uid then return end
 local d=dogsOf(profile())[uid]
 if not d then return end
 if cooling()then toast(T('The machine is cooling down'),'warn');cue('Deny');return end
 local c=cost(d)
 if not affordable(c)then toast(said('Not enough Coins or Bones'),'error',true);cue('Deny');return end
 st.Busy=true
 local button=st.View=='result'and ui.Again or ui.Go
 button:SetBusy(true)
 local ok,plan=net().Request('LabPreview',{Procedure='Mutation',Uids={uid}})
 if not ok or type(plan)~='table'then
  st.Busy=false;button:SetBusy(false)
  local text=tostring(plan);toast(said(text),'error',true);cue('Deny')
  if text=='Walk up to the Mutation Machine console'then setView('splash')end
  return
 end
 -- The variant changed since the button was armed: ask for the held confirmation now.
 if plan.HighValue and not mutated(d)then
  button:SetBusy(false)
  local confirmed=Kit.Confirm(T('MUTATE THIS DOG?'),F('Your %s variant can be lost: rerolls usually land on Normal.',T(plan.FromVariant or'Normal')),
   {Danger=true,Hold=1.2,ConfirmText=T('MUTATE'),NoTranslate=true}):Await()
  if not confirmed then st.Busy=false;return end
  button:SetBusy(true)
 end
 local args={Token=plan.Token,Confirm=true,Acknowledge=plan.HighValue and plan.Token or nil}
 local done,result=net().Request('LabCommit',args)
 if not done and tostring(result)=='Connection problem; try again'then
  task.wait(1);done,result=net().Request('LabCommit',args)
 end
 st.Busy=false;button:SetBusy(false)
 if not done or type(result)~='table'then
  toast(said(result),'error',true);cue('Deny')
  if tostring(result)=='Chamber cooling down'then st.CooldownEndsAt=Kit.Now()+C.Cooldown;renderMutate()end
  return
 end
 st.CooldownEndsAt=Kit.Now()+C.Cooldown
 if st.Info then st.Info.TutorialComplete=true end
 if type(result.StateSnapshot)=='table'then st.Snapshot=result.StateSnapshot end
 st.Uid=uid
 cue('Confirm')
 task.spawn(play,result)
end
function S.Again()
 local d=selected()
 if not d then S.Choose();return end
 S.Mutate(d.DogUid)
end

function S.RenderAgain()
 local d=selected()
 if not(ui and d)then ui.Again.Instance.Visible=false;return end
 local c=cost(d)
 ui.Again.Instance.Visible=true
 ui.Again.Props.Hold=mutated(d)and 1.2 or 0
 ui.Again:SetText(mutated(d)and T('HOLD: MUTATE AGAIN')or T('MUTATE AGAIN'))
 ui.Again:SetPrice(c.Free and T('FREE')or Format.Short(c.Cash,1)..' · 🦴'..c.Bones)
 local ok=eligible(d)
 ui.Again:SetDisabled(cooling()or not affordable(c)or not ok)
 ui.AgainTimer:SetEndsAt(cooling()and st.CooldownEndsAt or 0)
 ui.AgainTimer.Instance.Visible=cooling()
end

showResult=function(result)
 build()
 st.Result=result
 local d=result.Dog;local before=result.BeforeDog
 local after=d and d.Variant or'Normal';local was=before and before.Variant or'Normal'
 local color=Theme.VariantColor(after)
 local head,body
 local rows=odds();local normal=100
 for _,r in ipairs(rows)do if r.Name=='Normal'then normal=r.Percent end end
 local lines={}
 if after=='Normal'then
  head=T('STABLE — NO MUTATION');color=Theme.InkMuted
  if was=='Normal'then table.insert(lines,T('So close!'))
  else table.insert(lines,F('%s → %s',colored(variantName(was),Theme.Darken(Theme.VariantColor(was),.25)),colored(variantName(after),Theme.Darken(Theme.VariantColor(after),.3))))end
  table.insert(lines,F('Next try: %s chance of a mutation',pct(100-normal)))
 else
  head=after==was and F('STILL %s!',variantName(after))or(variantName(after)..'!')
  table.insert(lines,F('%s → %s',colored(variantName(was),Theme.Darken(Theme.VariantColor(was),.25)),colored(variantName(after),Theme.Darken(color,.25))))
  local bonus=0;for _,v in ipairs(Base.Variants)do if v.Name==after then bonus=v.Bonus end end
  if bonus>0 then table.insert(lines,F('Income +%d%%',math.floor(bonus*100+.5)))end
  table.insert(lines,colored('⚠ '..F('Mutating again can lose %s',variantName(after)),Theme.Darken(P.red,.1)))
 end
 ui.ResultHead.Text=head;ui.ResultHead.TextColor3=after=='Normal'and Theme.Ink or Theme.Darken(color,.2)
 ui.ResultName.Text=d and(d.DisplayName or d.DogId)or''
 ui.ResultBody.Text=table.concat(lines,'\n')
 ui.ResultGradient.Color=ColorSequence.new(color:Lerp(Theme.White,.4),Theme.White)
 ui.ResultSlot:Show(d and{Kind='Dog',DogId=d.DogId,Variant=after}or nil)
 if d then st.Uid=d.DogUid end
 if not win.IsOpen then win:Open()end
 setView('result')
 S.RenderAgain()
 if not Kit.Motion.Reduced()then
  ui.ResultScale.Scale=.86
  Kit.Motion.Tween(ui.ResultScale,.28,{Scale=1},Enum.EasingStyle.Back)
 end
 -- The cooldown and the free first try come from the server again.
 task.spawn(function()S.LoadInfo(true);if st.View=='result'then S.RenderAgain()end end)
end

function S.LoadInfo(quiet)
 local ok,info=net().Request('LabInfo',{})
 if ok and type(info)=='table'then
  st.Info=info
  if info.CooldownEndsAt then
   local remaining=math.max(0,(tonumber(info.CooldownEndsAt)or 0)-(tonumber(info.Now)or 0))
   st.CooldownEndsAt=math.max(st.CooldownEndsAt or 0,Kit.Now()+remaining)
  end
  return true,nil
 end
 if not quiet then st.Message=tostring(info)end
 return false,tostring(info)
end

function S.OnClose(reason)
 -- The cinematic takes navigation (N.BeginReward closes the window): the dog stays for the result card.
 if st.Launching or presentation().Playing then return end
 if st.View=='result'then presentation().Release();st.Result=nil;st.View='mutate'end
 if reason~='navigation'then Kit.Preview.Purge()end
end

-- Opens the window (any entry point). At the console: loads the machine; elsewhere: the way there.
function S.Open()
 build()
 local player=Players.LocalPlayer
 local atConsole=player~=nil and Access.CanUse(player)
 if not win.IsOpen then win:Open()end
 st.Snapshot=net().Cached()or st.Snapshot
 if not atConsole then setView('splash');return end
 setView('loading');ui.LoadingText.Text=T('Connecting to the machine…');ui.LoadingRetry.Instance.Visible=false
 local token=st.OpenToken
 task.spawn(function()
  local snapshot=net().Snapshot(2)
  if snapshot then st.Snapshot=snapshot end
  local ok,message=S.LoadInfo(false)
  if token~=st.OpenToken or not win.IsOpen then return end
  if not ok then
   if message=='Walk up to the Mutation Machine console'then setView('splash');return end
   ui.LoadingText.Text=said(message);ui.LoadingRetry.Instance.Visible=true
   return
  end
  cue('Console')
  if st.Uid and selected()and st.View~='result'then setView('mutate');renderMutate()
  else setView('pick');S.RefreshGrid(true)end
 end)
end
function S.Close()if win and win.IsOpen then win:Close('close')end end
-- Hooks for tests / tools.
function S.ShowResult(result)showResult(result)end
function S.SetView(view)setView(view)end

return S
