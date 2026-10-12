-- WORLD EVENTS: what is happening now, what it gives you, what comes next (the schedule is
-- deterministic, so every client computes the same upcoming events), why it is worth staying,
-- and Aurion, the DOG-O-MATIC's ultra-rare prize.
local RS=game:GetService('ReplicatedStorage')
local package=RS:WaitForChild('WorldEvents')
local Definitions=require(package.WorldEventDefinitions);local Schedule=require(package.WorldEventSchedule)
local EventConfig=require(package.WorldEventConfig);local Price=require(RS.PriceFormat);local EconomyConfig=require(RS.DogEconomy.Config)
local V=require(script.Parent.PreviewRenderer);local MachineText=require(RS.RewardMachineText)
local S={}
local rarityColors={Common=Color3.fromRGB(125,219,48),Uncommon=Color3.fromRGB(38,164,243),Rare=Color3.fromRGB(161,103,242),Secret=Color3.fromRGB(247,73,112)}
local function hidden(def)return def.Rarity=='Secret'end
-- Start of the next scheduled cycle of `eventId` from cycle `from` on (about 100 h ahead at most).
local function nextStart(eventId,from)
 local period=Schedule.Period()
 for k=0,400 do
  local index=from+k
  if Schedule.Event(index)==eventId then return EventConfig.Epoch+index*period+EventConfig.NormalInterval+EventConfig.WarningDuration end
 end
 return nil
end
local rainbowColors=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,86,140)),ColorSequenceKeypoint.new(.25,Color3.fromRGB(255,176,52)),
 ColorSequenceKeypoint.new(.5,Color3.fromRGB(96,214,104)),ColorSequenceKeypoint.new(.75,Color3.fromRGB(66,170,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(184,104,255))})
function S.Build(c)
 local U,W,H=c.U,c.W,c.H;local P=U.Colors
 local sc=U.Scroll(c.Parent,'WorldEventsContent',0,0,W,H)
 local state=package:FindFirstChild('State')
 local now=workspace:GetServerTimeNow()
 local phase=state and state:GetAttribute('State')or'NORMAL'
 local current=state and Definitions.ById[state:GetAttribute('EventId')or'']
 local ends=state and state:GetAttribute('EndTimestamp')or now
 local period=Schedule.Period();local at=Schedule.At(math.floor(now))
 -- Calm phases: EndTimestamp is the warning (NORMAL) or the next calm (ENDING); count down to
 -- the next event's actual start instead.
 if phase=='NORMAL'then ends=at.StartTimestamp elseif phase~='ACTIVE'and phase~='WARNING'then ends=at.StartTimestamp+period end
 local y=0
 -- Daily + active play rewards: visible in the same place players already check events.
 local profile=c.Snapshot.Profile;local daily=profile.DailyRewards or {LastDay=-1,Streak=0};local play=profile.PlaytimeRewards or {StartedAt=now,Claims={}}
 local day=math.floor(now/86400);local canDaily=(tonumber(daily.LastDay)or-1)<day
 local nextStreak=(tonumber(daily.LastDay)or-1)==day-1 and((daily.Streak or 0)+1)or 1
 local dailyIndex=(nextStreak-1)%#EconomyConfig.DailyRewards+1;local dr=EconomyConfig.DailyRewards[dailyIndex]
 local cols=4;local gap=7;local rewardRows=math.ceil(#EconomyConfig.PlaytimeRewards/cols);local rewardsH=198+(rewardRows-1)*70
 local rewards=U.Panel(sc,'ReturnRewards',8,y,W-24,rewardsH,true)
 U.Gradient(rewards,Color3.fromRGB(243,236,255),Color3.fromRGB(255,248,225))
 U.Text(rewards,'DAILY + PLAYTIME REWARDS',14,8,W-52,31,23,P.text,true)
 local dailyText='DAY '..dailyIndex..' · '..Price.Coins(dr.Cash or 0)..' CASH'..((dr.Bones or 0)>0 and(' · +'..dr.Bones..' BONES')or'')..(dr.LuckyBlock and(' · '..dr.LuckyBlock:upper()..' LUCKY BLOCK')or'')
 U.Text(rewards,dailyText,14,42,W-190,30,16,P.text,true)
 U.Button(rewards,'DailyClaim',canDaily and'CLAIM DAILY'or'CLAIMED TODAY',W-166,37,148,39,canDaily and function()c.Send('DailyReward',{})end or nil,canDaily and P.green or P.panel).Caption.TextSize=13
 U.Text(rewards,'PLAYTIME · today\'s progress is saved across rejoins until the UTC day changes.',14,78,W-52,25,13,P.muted)
 local elapsed=math.max(0,(play.Accumulated or 0)+now-(play.StartedAt or now));local claims=play.Claims or {};local bw=(W-52-gap*(cols-1))/cols
 for i,row in ipairs(EconomyConfig.PlaytimeRewards)do
  local claimed=claims[tostring(i)]==true;local ready=elapsed>=row.Seconds
  local label=claimed and'CLAIMED'or ready and'CLAIM'or('IN '..Price.Clock(row.Seconds-elapsed))
  local caption=math.floor(row.Seconds/60)..' MIN · '..Price.Coins(row.Cash or 0)
  local col=(i-1)%cols;local rr=math.floor((i-1)/cols);local x=14+col*(bw+gap);local yy=108+rr*70
  U.Text(rewards,caption,x,yy,bw,24,12,P.text,true)
  U.Button(rewards,'Playtime'..i,label,x,yy+27,bw,38,(not claimed and ready)and function()c.Send('PlaytimeReward',{Tier=i})end or nil,claimed and P.panel or ready and P.green or P.blue).Caption.TextSize=11
 end
 y+=rewardsH+12
 -- Now.
 local hero=U.Panel(sc,'CurrentEvent',8,y,W-24,phase=='ACTIVE'and 300 or 170,true)
 local theme=current and current.ColorTheme or P.gold
 U.Gradient(hero,theme:Lerp(Color3.new(1,1,1),.55),Color3.fromRGB(255,251,242))
 local title,sub
 if phase=='ACTIVE'and current then title=(hidden(current)and'[ '..current.DisplayName..' ]'or current.DisplayName:upper());sub='HAPPENING NOW · ENDS IN '
 elseif phase=='WARNING'and current then title=hidden(current)and'[ WORLD STATE ERROR ]'or current.DisplayName:upper();sub='STARTS IN '
 else title='THE ISLAND IS CALM';sub='NEXT WORLD EVENT IN 'end
 U.Text(hero,title,16,8,W-56,40,30,P.text,true)
 local clock=U.Text(hero,sub..'--:--:--',16,48,W-56,28,19,P.muted,true)
 clock:SetAttribute('Deadline',ends);clock:SetAttribute('CountdownStyle','Clock');clock:SetAttribute('CountdownPrefix',sub)
 if phase=='ACTIVE'and current then
  U.Text(hero,current.Subtitle,16,78,W-56,26,16,P.text)
  local lines=Definitions.PerkLines(current)
  local half=math.ceil(#lines/2);local colW=(W-56)/2
  for i,text in ipairs(lines)do
   local col=i<=half and 0 or 1;local row=i<=half and i or i-half
   U.Text(hero,'✦ '..text,16+col*colW,104+(row-1)*26,colW-8,24,15,P.text,true)
  end
 else
  U.Text(hero,'World events change the island for everyone on the server: gravity, speed, the tongue\'s luck. Participate actively and stay for the end to earn a modest bonus.',16,78,W-56,80,16,P.text)
 end
 y+=(phase=='ACTIVE'and 300 or 170)+14
 -- Why wait.
 local why=U.Header(sc,'WhyWait',8,y,W-24,40);U.Text(why,'WHY WAIT FOR AN EVENT?',12,0,W-48,40,22,P.text,true);y+=48
 local reasons={{'Luck','RARER DOGS','The tongue brings Legendary, Mythic and Secret dogs more often during every event.'},
  {'Coins','END REWARD','Stay active and DIG during the event to qualify. End rewards are now a bonus, not an AFK income source.'},
  {'Events','THE WORLD CHANGES','Low gravity, zoomies, quakes, tractor beams: every event plays differently.'}}
 local cols=math.max(1,math.min(3,math.floor((W-10)/240)));local cw=(W-24-(cols-1)*12)/cols
 for i,row in ipairs(reasons)do
  local card=U.Panel(sc,'Reason'..i,8+(i-1)%cols*(cw+12),y+math.floor((i-1)/cols)*136,cw,124)
  U.Icon(card,row[1],10,10,46,P.gold);U.Text(card,row[2],64,10,cw-74,30,19,P.text,true)
  U.Text(card,row[3],12,58,cw-24,60,14,P.muted)
 end
 y+=math.ceil(#reasons/cols)*136+6
 -- Coming up.
 local up=U.Header(sc,'Upcoming',8,y,W-24,40);U.Text(up,'COMING UP',12,0,W-48,40,22,P.text,true);y+=48
 local first=at.Cycle+((phase=='NORMAL'or phase=='WARNING')and 0 or 1)
 for k=0,4 do
  local index=first+k
  local id=Schedule.Event(index);local def=Definitions.ById[id]
  if def then
   local start=EventConfig.Epoch+index*period+EventConfig.NormalInterval+EventConfig.WarningDuration
   local card=U.Panel(sc,'Upcoming'..k,8,y,W-24,66)
   local stripe=U.Frame(card,'Stripe',0,0,8,66,rarityColors[def.Rarity]or P.gold);U.Round(stripe,4)
   local name=hidden(def)and'??? · A SECRET EVENT'or def.DisplayName:upper()..' · '..string.upper(def.Rarity)
   U.Text(card,name,20,4,W*.55,30,19,P.text,true)
   local lines=hidden(def)and {'NOBODY KNOWS WHAT IT DOES'}or Definitions.PerkLines(def)
   U.Text(card,table.concat({lines[1]or'',lines[2]or''},'  ·  '),20,34,W-210,26,13,P.muted)
   local when=U.Text(card,'',W-200,4,170,58,18,P.text,true);when.TextXAlignment=Enum.TextXAlignment.Right
   when:SetAttribute('Deadline',start);when:SetAttribute('CountdownStyle','Clock');when:SetAttribute('CountdownPrefix','IN ')
   y+=74
  end
 end
 y+=6
 -- Aurion: the DOG-O-MATIC's secret prize, its real odds and the Rainbow Rift boost.
 local odds=MachineText.AurionOdds()
 local boostDef=odds.EventId and Definitions.ById[odds.EventId]
 local boosting=phase=='ACTIVE'and current~=nil and boostDef~=nil and current.Id==boostDef.Id
 local stacked=W<560
 local artW=stacked and W-40 or math.min(260,(W-24)*.42)
 local tx=stacked and 14 or artW+20;local tw=stacked and W-52 or W-artW-60;local ty=stacked and 164 or 10
 local prizeH=stacked and ty+246 or 272
 local prize=U.Panel(sc,'AurionPrize',8,y,W-24,prizeH,true)
 U.Gradient(prize,Color3.fromRGB(214,240,255),Color3.fromRGB(246,226,255))
 V.Dog(prize,'Aurion',8,8,artW,stacked and 150 or prizeH-16)
 U.Text(prize,'AURION',tx,ty,tw,40,30,P.text,true)
 -- Built from the live odds, so it localizes itself (NoTranslate).
 local en=string.format("The DOG-O-MATIC's secret prize: %s per spin (1 in %s).",odds.ChanceText,odds.OneIn)
 local ru=string.format('Секретный приз DOG-O-MATIC: %s за вращение (1 из %s).',odds.ChanceText,(odds.OneIn:gsub(',',' ')))
 if odds.Multiplier then
  en..=string.format(' During %s: x%g (1 in %s).',odds.EventName,odds.Multiplier,odds.BoostOneIn)
  ru..=string.format(' Во время Радужного разлома: x%g (1 из %s).',odds.Multiplier,(tostring(odds.BoostOneIn):gsub(',',' ')))
 end
 en..=' Every tenth dig it echoes an extra discovery roll.';ru..=' Каждая десятая раскопка даёт ещё один бросок на находку.'
 MachineText.Own(U.Text(prize,MachineText.L(en,ru),tx,ty+42,tw,98,15,P.text))
 if boostDef then
  local banner=U.Frame(prize,'AurionBoost',tx,ty+144,tw,36,P.blue);U.Round(banner,9);U.Stroke(banner,P.edge,2)
  local title,clock
  if boosting then
   banner.BackgroundColor3=Color3.new(1,1,1);U.New('UIGradient',{Color=rainbowColors},banner)
   title=U.Text(banner,string.format('AURION HOWLS · x%g CHANCE',odds.Multiplier),10,0,tw-120,36,16,Color3.new(1,1,1),true)
   clock=U.Text(banner,'',tw-112,0,104,36,15,Color3.new(1,1,1),true)
   clock:SetAttribute('Deadline',ends);clock:SetAttribute('CountdownStyle','Clock');clock:SetAttribute('CountdownPrefix','')
  else
   title=U.Text(banner,'NEXT '..boostDef.DisplayName:upper(),10,0,tw-120,36,15,Color3.new(1,1,1),true)
   clock=U.Text(banner,'',tw-112,0,104,36,15,Color3.new(1,1,1),true)
   local at2=nextStart(boostDef.Id,first)
   if at2 then clock:SetAttribute('Deadline',at2);clock:SetAttribute('CountdownStyle','Clock');clock:SetAttribute('CountdownPrefix','')else clock.Text='—'end
  end
  for _,label in ipairs({title,clock})do label.TextStrokeTransparency=0;label.TextStrokeColor3=P.edge;label.TextScaled=true;U.New('UITextSizeConstraint',{MaxTextSize=16,MinTextSize=9},label)end
  clock.TextXAlignment=Enum.TextXAlignment.Right
 end
 local bw=(tw-8)/2
 U.Button(prize,'FindMachine','FIND DOG-O-MATIC',tx,ty+188,bw,46,function()c.Go('DOG-O-MATIC PLAZA')end,P.blue).Caption.TextSize=15
 U.Button(prize,'GetSpins','GET LUCKY SPINS',tx+bw+8,ty+188,bw,46,function()c.State.CommerceJump='DOG-O-MATIC Spins';c.Show('Shop')end,boosting and P.red or P.purple).Caption.TextSize=15
 y+=prizeH+12
 U.Text(sc,'Events run on one schedule for every server: about every '..math.floor(period/60)..' minutes, '..math.floor(EventConfig.EventDuration/60)..' minutes each.',8,y,W-24,40,15,P.muted)
end
return S
