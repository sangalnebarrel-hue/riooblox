local Audio=require(game.ReplicatedStorage.RewardAudio)
local RS=game:GetService('ReplicatedStorage');local Http=game:GetService('HttpService');local Run=game:GetService('RunService');local Marketplace=game:GetService('MarketplaceService');local Players=game:GetService('Players')
local Motion=require(RS:WaitForChild('RewardMachineMotion'));local Definitions=require(RS.DogEconomy.DogDefinitions)
local C=require(RS.LuckyBlockConfig);local Visual=require(RS.LuckyBlockVisuals);local V=require(script.Parent.PreviewRenderer);local S={};local clearWorldPrediction,refreshMachineInfo
local Tween=game:GetService('TweenService');local Format=require(RS.PriceFormat);local Text=require(RS.RewardMachineText)
local function request(c,action,args,done)
 local s=c.State;if s.RewardBusy then return end;s.RewardBusy=true;s.RewardMessage='Please wait…';c.Draw()
 task.spawn(function()
  local transport,ok,value=pcall(function()return RS.RewardRequest:InvokeServer(action,args or {})end)
  s.RewardBusy=false
  if transport and ok then s.RewardMessage=nil;if done then done(value)end
  else
   if action=='RewardMachineActivate'then clearWorldPrediction(c,true)end
   s.RewardMessage=transport and tostring(value)or 'Connection interrupted. Retry to check the saved result.'
   s.RewardMessageAt=os.clock();s.NoticeDismissed=nil
   -- A refusal means the machine state changed (tokens, storage, reset): show fresh info at once.
   if action=='RewardMachineActivate'then refreshMachineInfo(c)end
  end
  if not c.Gui or c.Gui.Parent then c.Draw()end
 end)
end
-- Re-read RewardMachineInfo without the busy guard or the 'Please wait…' message.
refreshMachineInfo=function(c)
 local s=c.State;if s.MachineInfoRefreshing then return end;s.MachineInfoRefreshing=true
 task.spawn(function()
  local transport,ok,value=pcall(function()return RS.RewardRequest:InvokeServer('RewardMachineInfo',{})end)
  s.MachineInfoRefreshing=nil
  if transport and ok and type(value)=='table'then s.RewardMachineInfo=value end
  if not c.Gui or c.Gui.Parent then c.Draw()end
 end)
end
-- Odds change only when an event boost starts or ends (the server mirrors it on the rig).
task.defer(function()
 local map=workspace:WaitForChild('DOGROTS_District',30);local area=map and map:WaitForChild('37_AttractionRefresh',30)
 local rig=area and area:WaitForChild('RewardMachineRig',30);if not rig then return end
 rig:GetAttributeChangedSignal('AurionBoost'):Connect(function()
  local ok,menus=pcall(function()return require(script.Parent.Menus).Active end)
  if ok and menus and(menus.page=='RewardMachine'or menus.page=='TicketShop')then menus:FetchRewardMachine(true)end
 end)
end)
local function block(parent,tier,x,y,w,h)
 local model=Visual.Build(tier);local view=V.Scene(parent,model,x,y,w,h);model:Destroy();return view
end
local function preview(c,parent,row,x,y,w,h)
 if row.Kind=='DogTier'then
  if row.Featured then V.Dog(parent,row.Featured,x,y,w,h)else c.U.Center(parent,row.Name or'DOG',x,y,w,h,22,c.U.Colors.purple,true)end
 elseif row.Dog or row.Kind=='Dog'then V.Dog(parent,row.Dog or row.Id,x,y,w,h)
 elseif row.Item or row.Kind=='Item'then V.Item(parent,row.Item or {ItemId=row.Id,Mutation='NORMAL',WeightMultiplier=1},x,y,w,h)
 else local model=require(RS.EconomyRewardVisuals).Build(row);if model then V.Scene(parent,model,x,y,w,h);model:Destroy()else c.U.Center(parent,row.Name or row.Kind,x,y,w,h,27,c.U.Colors.gold,true)end end
end
local seenMachine={}
local function beginWorldPrediction(c,requestId)
 local at=workspace:GetServerTimeNow();local finish=at+Motion.Duration
 c.State.WorldSpinUntil=finish
 Players.LocalPlayer:SetAttribute('RewardMachinePendingAt',at)
 Players.LocalPlayer:SetAttribute('RewardMachinePendingRequest',requestId)
 if c.Gui then c.Gui:SetAttribute('RewardMachineActiveUntil',finish);c.Gui:SetAttribute('RewardMachineActive',true)end
 return at
end
clearWorldPrediction=function(c,failed)
 Players.LocalPlayer:SetAttribute('RewardMachinePendingAt',nil);Players.LocalPlayer:SetAttribute('RewardMachinePendingRequest',nil)
 if failed then
  c.State.WorldSpinUntil=nil
  if c.Gui then c.Gui:SetAttribute('RewardMachineActiveUntil',0);c.Gui:SetAttribute('RewardMachineActive',false)end
 end
end
-- One line under a reward that explains what happened beyond the prize itself (localized here).
function S.ResultDetail(result)
 local storage=type(result.Storage)=='table'and result.Storage
 local L=Text.L
 if storage and storage.Kind=='Dogs'then
  local n,cap=tonumber(storage.Count)or 0,tonumber(storage.Capacity)or 0
  return L(string.format('Dog storage %d / %d · sell or manage dogs to make room',n,cap),string.format('Собак %d / %d · продай или освободи место',n,cap))
 elseif storage and storage.Kind=='Items'then
  local n,cap=tonumber(storage.Count)or 0,tonumber(storage.Capacity)or 0
  return L(string.format('Bag %d / %d · sell items to make room',n,cap),string.format('Предметов %d / %d · продай лишнее, чтобы освободить место',n,cap))
 end
 if(tonumber(result.Coins)or 0)>0 then
  local coins=Format.Number(result.Coins)
  return L('Energy Snack is full · +'..coins..' Coins instead','Энергетический перекус на максимуме · вместо него +'..coins..' монет')
 end
 if(tonumber(result.Reserved)or 0)>0 then return L('Energy Snack timer is full · the extra time waits in reserve','Таймер перекуса заполнен · лишнее время ждёт в запасе')end
 if result.Jackpot and result.Multiplier then
  local x=string.format('%g',result.Multiplier)
  return L('Won during Rainbow Rift · x'..x..' chance','Выигрыш во время Радужного разлома · шанс x'..x)
 end
 return nil
end
function S.PresentWorld(c,result)
 local receipt=result.Receipt or result.Request
 if receipt and seenMachine[receipt]then return end
 if receipt then seenMachine[receipt]=true end
 local gui=c.Gui or script.Parent.Parent;local U=c.U;local p=result.Presentation
 local finish=type(p)=='table'and tonumber(p.StartedAt)and tonumber(p.Duration)and(p.StartedAt+p.Duration)or workspace:GetServerTimeNow()
 c.State.WorldSpinUntil=finish;c.State.WorldSpinStart=type(p)=='table'and tonumber(p.StartedAt)or nil
 c.State.WorldSpinPersonal=type(p)=='table'and p.Personal==true or nil
 gui:SetAttribute('RewardMachineActiveUntil',finish);gui:SetAttribute('RewardMachineActive',finish>workspace:GetServerTimeNow())
 local detail=S.ResultDetail(result);local toastH=detail and 126 or 104
 local function showToast()
  if not gui.Parent or not gui:GetAttribute('RewardMachineWorldOpen')then return end
  local old=gui:FindFirstChild('RewardMachineRewardToast');if old then old:Destroy()end
  local toast=U.Panel(gui,'RewardMachineRewardToast',0,0,420,toastH);toast.ZIndex=80;toast.AnchorPoint=Vector2.new(.5,1)
  local scale=U.New('UIScale',{},toast)
  toast:SetAttribute('Receipt',receipt);toast:SetAttribute('RewardMachineStartedAt',p and p.StartedAt);toast:SetAttribute('RewardMachineDuration',p and p.Duration);toast:SetAttribute('RevealedAt',workspace:GetServerTimeNow())
  U.Gradient(toast,Color3.fromRGB(255,245,183),Color3.fromRGB(238,218,255))
  local name=result.Dog and result.Dog.DisplayName or result.Name or result.Item and result.Item.DisplayName or'Reward'
  local rarity=result.Rarity or(p and p.Rarity)or Motion.Rarity(result)
  U.Text(toast,Motion.UltraRare(result)and'ULTRA RARE!'or'REWARD FOUND!',98,5,278,20,16,U.Colors.purple,true)
  U.Text(toast,name,98,27,278,47,23,U.Colors.text,true)
  U.Text(toast,tostring(rarity):upper()..' · SAVED',98,80,196,18,15,U.Colors.muted,true)
  if detail then local line=Text.Own(U.Text(toast,detail,10,102,400,20,14,result.Storage and U.Colors.red or U.Colors.purple,true));line.Name='Detail';line.TextScaled=true;U.New('UITextSizeConstraint',{MaxTextSize=14,MinTextSize=9},line)end
  preview(c,toast,result,4,7,90,90)
  U.Button(toast,'Collect','COLLECT',302,70,110,30,function()toast:Destroy()end,U.Colors.green)
  local function layout()
   if not gui:GetAttribute('RewardMachineWorldOpen')then toast:Destroy();return end
   local left,top,width,height=U.SafeArea(gui)
   scale.Scale=math.min(1,(width-28)/420)
   local rail=gui:GetAttribute('RewardMachineRailHeight')or(width<600 and 132 or 94)
   local notices=gui:GetAttribute('RewardMachineNoticeHeight')or 0
   -- Short landscape phones cannot fit rail + notices + toast: the notices wait behind the toast.
   local crowded=notices>0 and top+height-14-rail-notices-10<top+toastH*scale.Scale+8
   gui:SetAttribute('RewardMachineNoticesHidden',crowded)
   toast.Position=UDim2.fromOffset(left+width/2,math.max(top+toastH*scale.Scale+8,top+height-14-rail-(crowded and 0 or notices)-10))
   toast.Visible=gui:GetAttribute('OpenMenu')=='RewardMachine'and not gui:GetAttribute('RewardMachineOddsOpen')
  end
  local events={gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(layout),gui:GetAttributeChangedSignal('RewardMachineRailHeight'):Connect(layout),gui:GetAttributeChangedSignal('RewardMachineNoticeHeight'):Connect(layout),gui:GetAttributeChangedSignal('RewardMachineWorldOpen'):Connect(layout),gui:GetAttributeChangedSignal('RewardMachineOddsOpen'):Connect(layout)}
  toast.Destroying:Connect(function()for _,event in ipairs(events)do event:Disconnect()end;if gui.Parent then gui:SetAttribute('RewardMachineNoticesHidden',false)end end);layout()
  scale.Scale*=.92;Tween:Create(scale,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=scale.Scale/.92}):Play()
  Audio.Cue(Motion.UltraRare(result)and'burst'or'reveal')
  task.delay(detail and 10 or 8,function()if toast.Parent then toast:Destroy()end end)
 end
 local function finishSpin()
  if not gui.Parent then return end
  local left=finish-workspace:GetServerTimeNow();if left>0 then task.delay(left,finishSpin);return end
  if c.State.WorldSpinUntil==finish then c.State.WorldSpinUntil=nil;c.State.WorldSpinPersonal=nil;c.State.WorldSpinStart=nil;gui:SetAttribute('RewardMachineActive',false)end
  c.State.WorldOddsOpen=false
  c.State.RewardMachineLastReward=result
  c.Draw();showToast()
 end
 task.delay(math.max(0,finish-workspace:GetServerTimeNow()),finishSpin)
 c.Draw()
end
-- The original opening card: 2 s block shake, then the dog. Used for non-dog rewards and as the
-- fallback when the Lucky roulette (LuckyReel) cannot run.
local function classic(c:any,result:any,overlay:any)
 Audio.Cue('buy');local U=c.U
 local box=U.Modal(overlay,'RewardCard','OPENING…',580,480)
 local heading=box:FindFirstChild('Label');if heading then heading.Name='RewardStatus'end
 local title=U.Center(box,result.Tier:upper()..' LUCKY BLOCK',20,66,540,44,24,U.TextGold,true)
 local art=U.New('Frame',{Name='OpeningArt',Position=UDim2.fromOffset(30,110),Size=UDim2.fromOffset(520,230),BackgroundTransparency=1},box)
 local view=block(art,result.Tier,0,0,520,225);local state='opening';local t=0;local phase=-1;local skip,done
 local function reveal()
  if state~='opening'then return end;state='revealed';art.Rotation=0
  if heading then heading.Text='REWARD SAVED'end
  if skip then skip.Visible=false end;if done then done.Visible=true;U.SetButtonEnabled(done,true)end
  Audio.Cue('burst');Audio.Cue('reveal');art:ClearAllChildren();preview(c,art,result,0,0,520,225)
  title.Text=result.Dog and(result.Dog.DisplayName..' · '..result.Dog.Variant)or result.Name or'REWARD SAVED'
  U.Center(box,'Saved to your collection',20,352,540,34,19,U.Colors.muted)
 end
 skip=U.Button(box,'Skip','SKIP / REVEAL',30,405,520,46,reveal,U.Colors.gold)
 done=U.Button(box,'Done','DONE',30,405,520,46,function()if state=='revealed'then overlay:Destroy()end end,U.Colors.green)
 done.Visible=false;U.SetButtonEnabled(done,false)
 local con;con=Run.RenderStepped:Connect(function(dt)
  if not overlay.Parent or state~='opening'then con:Disconnect();return end
  t+=dt;local nextPhase=math.floor(t/.5)
  if nextPhase~=phase then phase=nextPhase;Audio.Cue(phase<3 and'shake'or'crack')end
  art.Rotation=math.sin(t*35)*math.min(8,2+phase*2)
  if t>=1.5 then art.Rotation=0;view.ImageColor3=Color3.fromRGB(255,225,170)end
  if t>=2 then reveal()end
 end)
 return{Reveal=reveal,Close=function()overlay:Destroy()end}
end
local reelLoaded,Reel=false,nil
local function luckyReel()
 if not reelLoaded then
  reelLoaded=true
  local ok,module=pcall(require,script.Parent:WaitForChild('LuckyReel',5))
  if ok and type(module)=='table'then Reel=module else warn('[RewardScreens] LuckyReel unavailable: '..tostring(module))end
 end
 return Reel
end
task.defer(function()local reel=luckyReel();if reel then pcall(reel.Warm)end end)
function S.Present(c,result)
 if result.Kind=='Block'or result.Cue=='Pickup'then return end
 if not result.Tier then return S.PresentWorld(c,result)end
 local gui=script.Parent.Parent;local Navigation=require(script.Parent.GUIIntegration)
 -- Lucky Block dog: the CS:GO-style roulette, landing on the server's dog. It owns the receipt
 -- (BeginReward/EndReward) and falls back to the classic card on any error.
 local reel=type(result.Dog)=='table'and result.Dog.DogId~=nil and luckyReel()
 if reel then
  local ok,handle=pcall(reel.Present,{U=c.U,Gui=gui,Navigation=Navigation,
   Preview=function(parent,x,y,w,h)preview(c,parent,result,x,y,w,h)end,
   Block=function(parent,x,y,w,h)return block(parent,result.Tier,x,y,w,h)end,
   Classic=function(overlay)return classic(c,result,overlay)end},result)
  if ok then return handle end
  warn('[RewardScreens] LuckyReel failed: '..tostring(handle))
 end
 local rewardEpoch=Navigation.BeginReward(result.Receipt or result.BlockUid);if not rewardEpoch then return end
 local old=gui:FindFirstChild('RewardReveal');if old then old:Destroy()end
 local overlay=c.U.New('Frame',{Name='RewardReveal',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=100,Active=true},gui)
 overlay.Destroying:Connect(function()task.defer(function()Navigation.EndReward(rewardEpoch)end)end)
 return classic(c,result,overlay)
end
local ticketPrices={};local ticketLoading={};local ticketRetry={}
-- Bought DOG TOKENS count once the machine sells them and Roblox allows this account to use them.
local function usablePaid(info)
 if info.FreeOnly~=false or info.PaidRandomAllowed~=true then return 0 end
 return tonumber(info.PaidTickets)or 0
end
local function clockText(seconds)
 seconds=math.max(0,math.ceil(seconds));return string.format('%02d:%02d:%02d',math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end
local function infoOrLoad(c)
 local s=c.State;local U=c.U
 if s.RewardMachineInfo then return s.RewardMachineInfo end
 U.Center(c.Parent,s.RewardMessage or'Getting your DOG TOKEN…',10,40,c.W-20,85,22,U.Colors.muted,true)
 if not s.RewardBusy and not s.MachineLoadFailed then
  s.MachineLoadFailed=true;request(c,'RewardMachineInfo',{},function(v)s.RewardMachineInfo=v;s.MachineLoadFailed=nil end)
 elseif not s.RewardBusy then U.Button(c.Parent,'Retry','TRY AGAIN',20,146,c.W-40,48,function()s.MachineLoadFailed=nil;c.Draw()end,U.Colors.blue)end
end
local function wallet(c,parent,info)
 local U,W,P=c.U,c.W,c.U.Colors
 local free=tonumber(info.FreeTickets)or math.min(1,tonumber(info.Tickets)or 0)
 local paid=tonumber(info.PaidTickets)or 0;local total=free+usablePaid(info)
 local at=tonumber(info.NextFreeTicketAt or info.NextTicketAt)or 0
 local narrow=W<480;local height=narrow and 244 or c.Mobile and 210 or 172
 local panel=U.Panel(parent,'TicketWallet',8,4,W-24,height)
 U.Gradient(panel,Color3.fromRGB(220,188,255),Color3.fromRGB(255,228,111))
 local badge=U.Frame(panel,'TicketBalance',14,14,116,132,P.gold);U.Round(badge,14);U.Stroke(badge,P.edge,3)
 U.Center(badge,'DOG TOKEN',5,7,106,28,16,P.text,true)
 local balance=U.Center(badge,U.Fmt(total),5,36,106,69,44,P.text,true);balance.TextWrapped=false;balance.TextScaled=true
 U.New('UITextSizeConstraint',{MinTextSize=14,MaxTextSize=44},balance)
 local heading=free>0 and(narrow and'READY TO\nACTIVATE!'or'READY TO ACTIVATE!')or(narrow and'NEXT FREE\nDOG TOKEN'or'NEXT FREE DOG TOKEN')
 U.Text(panel,heading,146,12,W-184,narrow and 62 or 40,narrow and 24 or 26,P.text,true)
 local clock=U.Text(panel,free>0 and'Next refill starts after use.'or clockText(at-c.Now()),147,narrow and 78 or 56,W-188,narrow and 64 or c.Mobile and 53 or 36,free>0 and 17 or 27,P.text,true)
 if free==0 and at>0 then clock:SetAttribute('Deadline',at);clock:SetAttribute('CountdownStyle','Clock')end
 U.Text(panel,'FREE '..free..' / 1'..(paid>0 and('  ·  BOUGHT '..paid)or''),narrow and 14 or 147,narrow and 152 or c.Mobile and 116 or 98,W-(narrow and 52 or 188),28,18,P.purple,true)
 U.Text(panel,'Free every 5 hours after use. Stores one free DOG TOKEN; bought tokens never expire.',14,narrow and 190 or c.Mobile and 162 or 139,W-52,narrow and 44 or c.Mobile and 40 or 27,16,P.text)
 return height+19,total,free,paid
end
-- An info poll that landed inside the 7 s reset says CanSpin=false (ReasonCode Cooldown). That
-- refusal ends with the reset: the button is ready again at NextSpinAt without waiting for the
-- next poll, and the screen redraws itself at that moment (polls and redraws are ~5 s apart).
local function canSpin(info,cooling)
 return info.CanSpin~=false or(info.ReasonCode=='Cooldown'and not cooling)
end
local function redrawAfterReset(c,info)
 local s=c.State;local at=tonumber(info.NextSpinAt)or 0
 if s.ResetRedrawAt==at then return end
 s.ResetRedrawAt=at
 task.delay(math.max(0,at-c.Now())+.05,function()if s.ResetRedrawAt==at then c.Draw()end end)
end
local function prizeRarity(row)
 local def=row.Kind=='Dog'and Definitions[row.Id]
 return row.Rarity or(def and def.Rarity)or({Cash='Coins',Bones='Bones',Boost='Boost'})[row.Kind]or row.Kind or'Reward'
end
-- One-line labels whose translation may be longer: shrink instead of clipping.
local function fit(label,maxSize,minSize)
 label.TextScaled=true;label.TextWrapped=true
 local constraint=Instance.new('UITextSizeConstraint');constraint.MaxTextSize=maxSize;constraint.MinTextSize=minSize or 9;constraint.Parent=label
 return label
end
-- Disclosure lines under one odds row (see RewardMachineText.OddsLines); other rows show their
-- rarity word, which the dictionary translates.
local function oddsLines(row)
 local lines,owned=Text.OddsLines(row)
 if not owned then lines={prizeRarity(row):upper()}end
 return lines,owned
end
local function oddsLabel(label,owned)if owned then Text.Own(label)end;return label end
local rainbowColors=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,86,140)),ColorSequenceKeypoint.new(.25,Color3.fromRGB(255,176,52)),
 ColorSequenceKeypoint.new(.5,Color3.fromRGB(96,214,104)),ColorSequenceKeypoint.new(.75,Color3.fromRGB(66,170,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(184,104,255))})
local function rainbow(frame)
 frame.BackgroundColor3=Color3.new(1,1,1)
 local old=frame:FindFirstChildWhichIsA('UIGradient');if old then old:Destroy()end
 local gradient=Instance.new('UIGradient');gradient.Color=rainbowColors;gradient.Offset=Vector2.new(-.3,0);gradient.Parent=frame
 local tween=Tween:Create(gradient,TweenInfo.new(2.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Offset=Vector2.new(.3,0)})
 tween:Play();frame.Destroying:Connect(function()tween:Cancel()end)
 return gradient
end
local function boostTitle(boost)return string.format('AURION HOWLS · x%g CHANCE',tonumber(boost.Multiplier)or 1)end
-- Which refusal this is, so the notice can offer the action that fixes it.
local function reasonCode(info,message)
 if info and message==info.UnavailableReason and info.ReasonCode then return info.ReasonCode end
 message=tostring(message or'')
 if message:find('Move closer',1,true)then return 'TooFar'
 elseif message:find('dogs. Sell',1,true)then return 'DogsHardCap'
 elseif message:find('items. Sell',1,true)then return 'ItemsHardCap'
 elseif message:find('still recharging',1,true)then return 'Recharging'
 elseif message:find('Paid random tickets',1,true)then return 'PaidRestricted'
 elseif message:find('Please wait',1,true)then return 'Wait'end
 return 'Retry'
end
local function noticeActions(c,code)
 local N=require(script.Parent.GUIIntegration)
 if code=='DogsHardCap'then return {{'MANAGE DOGS',function()c.Show('Dogs')end},{'DOG SHELTER',function()N.Navigate('Dog Shelter')end}}
 elseif code=='ItemsHardCap'then return {{'MY ITEMS',function()c.Show('Collection')end}}
 elseif code=='Recharging'then return {{'GET TOKENS',function()c.Show('TicketShop')end}}
 elseif code=='PaidRestricted'then return {{'TOKEN INFO',function()c.Show('TicketShop')end}}
 elseif code=='TooFar'then return {{'FIND DOG-O-MATIC',function()N.Navigate('DOG-O-MATIC PLAZA')end}}
 elseif code=='Retry'then return {{'TRY AGAIN',function()c.State.RewardMessage=nil;c.State.NoticeDismissed=nil;refreshMachineInfo(c)end}}end
 return {}
end
-- Rainbow boost and refusal notices sit just above the control rail, persistently (the rail
-- itself is redrawn on every refresh). Both are sized for phones and desktops.
local function noticeHost(c)
 local gui=c.Gui;if not gui then return nil end
 local host=gui:FindFirstChild('RewardMachineNotices')
 if host then return host end
 host=c.U.New('Frame',{Name='RewardMachineNotices',BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,1),Size=UDim2.fromOffset(300,0),ZIndex=72,Visible=false},gui)
 c.U.New('UIListLayout',{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),VerticalAlignment=Enum.VerticalAlignment.Bottom,HorizontalAlignment=Enum.HorizontalAlignment.Center},host)
 local events={}
 local function sync()
  if not gui:GetAttribute('RewardMachineWorldOpen')then host:Destroy();return end
  host.Visible=gui:GetAttribute('OpenMenu')=='RewardMachine'and not gui:GetAttribute('RewardMachineOddsOpen')and not gui:GetAttribute('RewardMachineNoticesHidden')and #host:GetChildren()>1
 end
 for _,name in ipairs({'RewardMachineWorldOpen','RewardMachineOddsOpen','OpenMenu','RewardMachineNoticesHidden'})do table.insert(events,gui:GetAttributeChangedSignal(name):Connect(sync))end
 host.Destroying:Connect(function()for _,event in ipairs(events)do event:Disconnect()end;if gui.Parent then gui:SetAttribute('RewardMachineNoticeHeight',0)end end)
 return host
end
local function popIn(frame)
 local scale=Instance.new('UIScale');scale.Scale=.9;scale.Parent=frame
 Tween:Create(scale,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
end
local function boostNotice(c,host,boost,width)
 local U=c.U;local key=tostring(boost.EventId)..':'..tostring(boost.Multiplier)..':'..width
 local frame=host:FindFirstChild('BoostNotice')
 if frame and frame:GetAttribute('Key')==key then return frame end
 if frame then frame:Destroy()end
 frame=U.Frame(host,'BoostNotice',0,0,width,40,Color3.new(1,1,1));frame.LayoutOrder=1;frame.ZIndex=73;frame:SetAttribute('Key',key)
 U.Round(frame,12);U.Stroke(frame,U.Colors.edge,3);rainbow(frame)
 local title=fit(U.Text(frame,boostTitle(boost),12,0,width-112,40,width<420 and 15 or 18,Color3.new(1,1,1),true),width<420 and 15 or 18);title.ZIndex=74
 title.TextStrokeTransparency=0;title.TextStrokeColor3=U.Colors.edge
 local clock=U.Text(frame,'',width-104,0,92,40,15,Color3.new(1,1,1),true);clock.ZIndex=74;clock.TextXAlignment=Enum.TextXAlignment.Right
 clock.TextStrokeTransparency=0;clock.TextStrokeColor3=U.Colors.edge
 task.spawn(function()
  while clock.Parent do
   local left=math.max(0,(tonumber(boost.EndsAt)or 0)-c.Now())
   clock.Text='ENDS '..string.format('%02d:%02d',math.floor(left/60),math.floor(left)%60)
   if left<=0 then refreshMachineInfo(c);break end
   task.wait(1)
  end
 end)
 popIn(frame);return frame
end
local function refusalNotice(c,host,message,code,width)
 local U=c.U;local P=U.Colors;local narrow=width<460
 local actions=noticeActions(c,code)
 local key=message..'|'..code..'|'..width
 local frame=host:FindFirstChild('RefusalNotice')
 if frame and frame:GetAttribute('Key')==key then return frame end
 if frame then frame:Destroy()end
 local buttonsW=#actions>0 and(#actions*124+(#actions-1)*6)or 0
 local height=narrow and(#actions>0 and 98 or 58)or 60
 frame=U.Frame(host,'RefusalNotice',0,0,width,height,Color3.fromRGB(255,244,246));frame.LayoutOrder=2;frame.ZIndex=73;frame:SetAttribute('Key',key)
 U.Round(frame,12);U.Stroke(frame,P.red,3)
 local stripe=U.Frame(frame,'Stripe',6,8,5,height-16,P.red);stripe.ZIndex=74;U.New('UICorner',{CornerRadius=UDim.new(.5,0)},stripe)
 local textW=narrow and width-56 or width-56-buttonsW-8
 local label=U.Text(frame,message,16,narrow and 4 or 2,textW,narrow and 50 or 56,narrow and 15 or 16,P.text,true);label.ZIndex=74
 label.TextYAlignment=Enum.TextYAlignment.Center;U.New('UITextSizeConstraint',{MinTextSize=11,MaxTextSize=narrow and 15 or 16},label);label.TextScaled=true
 local close=U.Button(frame,'Dismiss','×',width-38,8,30,30,function()c.State.NoticeDismissed=message;local old=host:FindFirstChild('RefusalNotice');if old then old:Destroy()end;c.Draw()end,P.red)
 close.ZIndex=75
 for i,action in ipairs(actions)do
  local w=narrow and math.min(150,(width-32-(#actions-1)*6)/#actions)or 124
  local x=narrow and 16+(i-1)*(w+6)or width-44-buttonsW+(i-1)*130
  local y=narrow and 56 or 12
  local button=U.Button(frame,'Action'..i,action[1],x,y,w,36,action[2],i==1 and P.blue or P.gold);button.ZIndex=75;button.Caption.TextSize=13
 end
 popIn(frame);return frame
end
local function renderNotices(c,info,spinning)
 local gui=c.Gui;if not gui then return end
 local s=c.State
 local message,code
 local recent=s.RewardMessage and s.RewardMessageAt and os.clock()-s.RewardMessageAt<15 and not s.RewardBusy
 if not spinning then
  if recent then message=s.RewardMessage;code=reasonCode(info,message)
  elseif info.CanSpin==false and info.UnavailableReason and info.ReasonCode~='Cooldown'then message=info.UnavailableReason;code=info.ReasonCode or reasonCode(info,message)end
 end
 if message and(message==s.NoticeDismissed or code=='Wait')then message=nil end
 local boost=type(info.ActiveBoost)=='table'and info.ActiveBoost or nil
 local host=gui:FindFirstChild('RewardMachineNotices')
 if not message and not boost then
  if host then host:Destroy()end
  return nil
 end
 host=noticeHost(c);if not host then return nil end
 local left,top,width,height=c.U.SafeArea(gui)
 local wide=width>=600;local W=math.max(260,math.min(wide and 760 or 380,width-28));local scale=math.min(1,(width-28)/W)
 local noticeW=math.floor(W*scale)
 local rail=gui:GetAttribute('RewardMachineRailHeight')or(wide and 94 or 132)
 local total=0
 if boost then boostNotice(c,host,boost,noticeW);total+=40 else local old=host:FindFirstChild('BoostNotice');if old then old:Destroy()end end
 if message then local frame=refusalNotice(c,host,message,code,noticeW);total+=(total>0 and 6 or 0)+frame.Size.Y.Offset
 else local old=host:FindFirstChild('RefusalNotice');if old then old:Destroy()end end
 host.Size=UDim2.fromOffset(noticeW,total)
 host.Position=UDim2.fromOffset(left+width/2,top+height-14-rail-8)
 host.Visible=gui:GetAttribute('OpenMenu')=='RewardMachine'and not gui:GetAttribute('RewardMachineOddsOpen')and not gui:GetAttribute('RewardMachineNoticesHidden')
 gui:SetAttribute('RewardMachineNoticeHeight',total+8)
 return message
end
function S.WorldRewardMachine(c)
 local U,W,H,s=c.U,c.W,c.H,c.State;local P=U.Colors;local wide=W>=600
 local panel=U.Panel(c.Parent,'WorldControls',0,0,W,H)
 U.Round(panel,15);U.Gradient(panel,Color3.fromRGB(255,248,219),Color3.fromRGB(234,220,255))
 local close=U.Button(panel,'Close','X',W-40,6,32,32,c.Close,P.red);close:SetAttribute('KitSound','')
 local info=s.RewardMachineInfo
 if not info then
  U.Text(panel,'Loading your DOG TOKEN…',12,12,W-68,36,20,P.muted)
  if not s.RewardBusy and not s.MachineLoadFailed then s.MachineLoadFailed=true;request(c,'RewardMachineInfo',{},function(v)s.RewardMachineInfo=v;s.MachineLoadFailed=nil end)end
  return
 end
 local free=tonumber(info.FreeTickets)or math.min(1,tonumber(info.Tickets)or 0);local total=free+usablePaid(info)
 local serverNow=workspace:GetServerTimeNow()
 local spinning=(s.WorldSpinUntil or 0)>serverNow;local cooling=(tonumber(info.NextSpinAt)or 0)>c.Now()
 local allowed=canSpin(info,cooling);if cooling then redrawAfterReset(c,info)end
 local ready=total>0 and allowed and info.InRange~=false and not cooling and not spinning and not s.RewardBusy
 U.Text(panel,U.Fmt(total)..' DOG TOKEN',12,wide and 9 or 24,wide and 190 or 131,28,wide and 23 or 18,P.text,true)
 U.Text(panel,'FREE · '..free..' / 1',wide and 12 or 145,wide and 36 or 26,wide and 190 or W-195,23,wide and 15 or 13,P.purple,true)
 local at=tonumber(info.NextFreeTicketAt or info.NextTicketAt)or 0
 local spinText='Watch the reward drum!'
 if spinning and s.WorldSpinPersonal then spinText='Drum busy · your reward appears here'
 elseif spinning and(s.WorldSpinStart or 0)>serverNow then spinText='Your turn on the drum is next'end
 local statusText=spinning and spinText or free>0 and'FREE READY · 1 / 5H'or'Free in '..clockText(at-c.Now())
 local noticeShown=renderNotices(c,info,spinning)
 local status=U.Text(panel,(not noticeShown and not spinning and s.RewardMessage)or statusText,12,wide and 63 or 52,wide and 190 or W-24,wide and 23 or 20,13,P.muted)
 if not spinning and free==0 and at>0 and(noticeShown or not s.RewardMessage)then status:SetAttribute('Deadline',at);status:SetAttribute('CountdownStyle','Clock');status:SetAttribute('CountdownPrefix','Free in ')end
 local label=spinning and'ACTIVATING…'or s.RewardBusy and'PLEASE WAIT…'or info.InRange==false and'VISIT DOG-O-MATIC'or total==0 and'NO DOG TOKEN'or cooling and'RESETTING…'or not allowed and'UNAVAILABLE'or'ACTIVATE · 1 TOKEN'
 local spinX,spinY,spinW,spinH=wide and 214 or 12,wide and 18 or 80,wide and math.min(260,W-452)or W-170,wide and 58 or 40
 local spin=U.Button(panel,'Spin',label,spinX,spinY,spinW,spinH,ready and function()
  s.SpinRequest=s.SpinRequest or Http:GenerateGUID(false):gsub('-','')
  s.NoticeDismissed=nil
  local startedAt=beginWorldPrediction(c,s.SpinRequest)
  request(c,'RewardMachineActivate',{Request=s.SpinRequest,StartedAt=startedAt},function(v)
   s.SpinRequest=nil
   for _,key in ipairs({'Tickets','FreeTickets','PaidTickets','NextTicketAt','NextFreeTicketAt','NextSpinAt'})do if v[key]~=nil then info[key]=v[key]end end
   S.PresentWorld(c,v);clearWorldPrediction(c,false)
  end)
 end or nil,P.green)
 spin.Caption.TextSize=wide and 19 or W<320 and 12 or 14
 U.Text(panel,'DOG-O-MATIC',wide and W-222 or 12,wide and 9 or 4,wide and 178 or W-65,wide and 29 or 19,wide and 18 or 13,P.purple,true)
 local odds=U.Button(panel,'Odds','CHANCES',wide and W-222 or W-146,wide and 50 or 80,wide and 85 or 60,wide and 34 or 40,function()s.WorldOddsOpen=not s.WorldOddsOpen;c.Draw()end,info.ActiveBoost and P.red or P.blue)
 local tickets=U.Button(panel,'TicketShop','TOKENS',wide and W-129 or W-78,wide and 50 or 80,wide and 113 or 66,wide and 34 or 40,not spinning and function()c.Show('TicketShop')end or nil,P.gold)
 odds.Caption.TextSize=wide and 14 or 10;tickets.Caption.TextSize=wide and 16 or 12
 if c.Gui then
  local old=c.Gui:FindFirstChild('RewardMachineOddsOverlay');local previous=old and old:FindFirstChild('OddsList',true);local savedScroll=previous and previous.CanvasPosition
  local redraw=old~=nil -- a refresh of an open dialog: no second open motion
  if old then old:Destroy()end
  c.Gui:SetAttribute('RewardMachineOddsOpen',s.WorldOddsOpen==true)
  if s.WorldOddsOpen then
   local _,_,width,height=U.SafeArea(c.Gui);local ow=math.min(430,width-28);local oh=math.min(420,height-28)
   -- Kit dialog shade (faded in on the first draw only; refreshes redraw the dialog in place).
   local overlay=U.New('Frame',{Name='RewardMachineOddsOverlay',Size=UDim2.fromScale(1,1),BackgroundColor3=U.Backdrop,BackgroundTransparency=redraw and .4 or 1,Active=true,ZIndex=85},c.Gui)
   if not redraw then require(script.Parent.Kit.Motion).Tween(overlay,.18,{BackgroundTransparency=.4})end
   local window=U.Modal(overlay,'OddsWindow','REWARD CHANCES',ow,oh,redraw)
   U.Button(window,'CloseOdds','X',ow-52,14,40,40,function()s.WorldOddsOpen=false;c.Draw()end,P.red):SetAttribute('KitSound','')
   local sc=U.Scroll(window,'OddsList',12,75,ow-24,oh-89)
   local y=0
   U.Text(sc,'Every activation uses these exact chances, for free and bought DOG TOKENS.',5,y,ow-48,38,14,P.muted);y+=42
   if info.ActiveBoost then
    local strip=U.Frame(sc,'BoostStrip',5,y,ow-48,32,P.purple);U.Round(strip,8);rainbow(strip)
    local text=fit(U.Center(strip,boostTitle(info.ActiveBoost),4,0,ow-56,32,15,Color3.new(1,1,1),true),15);text.TextStrokeTransparency=0;text.TextStrokeColor3=P.edge
    y+=40
   end
   for i,row in ipairs(info.Rewards or{})do
    local lines,owned=oddsLines(row)
    U.Text(sc,row.Name or row.Kind,5,y,ow-140,30,18,P.text,true).Name='Reward'..i
    U.Text(sc,string.format('%.6g%%',(row.Chance or 0)*100),ow-125,y,83,30,20,row.Multiplier and P.red or P.purple,true).TextXAlignment=Enum.TextXAlignment.Right
    for j,line in ipairs(lines)do oddsLabel(fit(U.Text(sc,line,5,y+29+(j-1)*19,ow-60,19,14,P.muted),14),owned)end
    y+=29+#lines*19+12
   end
   if savedScroll then sc.CanvasPosition=savedScroll end
  end
 end
end
function S.RewardMachine(c)
 local info=infoOrLoad(c);if not info then return end
 local U,s,W,H=c.U,c.State,c.W,c.H;local P=U.Colors
 local sc=U.Scroll(c.Parent,'MachineRewards',0,0,W,H)
 local y,total=wallet(c,sc,info)
 local cooling=(tonumber(info.NextSpinAt)or 0)>c.Now()
 local allowed=canSpin(info,cooling);if cooling then redrawAfterReset(c,info)end
 local ready=total>0 and allowed and info.InRange~=false and not cooling and not s.RewardBusy
 local label=s.RewardBusy and'ACTIVATING…'or info.InRange==false and'VISIT DOG-O-MATIC'or total==0 and'WAITING FOR A DOG TOKEN'or cooling and'MACHINE RESETTING…'or not allowed and'ACTIVATION UNAVAILABLE'or'ACTIVATE · 1 TOKEN'
 U.Button(sc,'Spin',label,8,y,W-24,55,ready and function()
  s.SpinRequest=s.SpinRequest or Http:GenerateGUID(false):gsub('-','')
  local startedAt=beginWorldPrediction(c,s.SpinRequest)
  request(c,'RewardMachineActivate',{Request=s.SpinRequest,StartedAt=startedAt},function(v)
   s.SpinRequest=nil
   for _,key in ipairs({'Tickets','FreeTickets','PaidTickets','NextTicketAt','NextFreeTicketAt'})do if v[key]~=nil then info[key]=v[key]end end
   S.Present(c,v);clearWorldPrediction(c,false)
  end)
 end or nil,ready and P.green or P.purple);y+=66
 U.Button(sc,'TicketShop',info.FreeOnly==false and'DOG TOKENS · LUCKY SPINS'or'FREE DOG TOKEN INFO',8,y,W-24,42,function()c.Show('TicketShop')end,P.gold);y+=49
 if info.InRange==false then U.Button(sc,'FindRewardMachine','FIND DOG-O-MATIC',8,y,W-24,42,function()require(script.Parent.GUIIntegration).Navigate('DOG-O-MATIC PLAZA')end,P.blue);y+=51 end
 local message=s.RewardMessage or not allowed and info.UnavailableReason
 if message and message~=''then U.Text(sc,tostring(message),12,y,W-32,48,17,not s.RewardMessage and(total==0 or cooling)and P.muted or P.red);y+=54 end
 if info.ActiveBoost then
  local strip=U.Frame(sc,'BoostStrip',8,y,W-24,40,P.purple);U.Round(strip,10);rainbow(strip)
  local text=fit(U.Center(strip,boostTitle(info.ActiveBoost),6,0,W-36,40,19,Color3.new(1,1,1),true),19);text.TextStrokeTransparency=0;text.TextStrokeColor3=P.edge
  y+=50
 end
 U.Section(sc,'YOUR POSSIBLE REWARDS',8,y,W-24,38);y+=46
 U.Text(sc,'One DOG TOKEN gives one random reward. Exact chances are shown below.',12,y,W-32,45,16,P.muted);y+=49
 local cols=c.Mobile and 2 or 4;local cw=(W-24-(cols-1)*12)/cols
 for i,row in ipairs(info.Rewards or{})do
  local rarity=prizeRarity(row);local tone=U.Rarity[rarity]or({Cash=P.gold,Bones=P.blue,Boost=P.green})[row.Kind]or P.purple
  local card=U.Panel(sc,'Reward'..i,8+(i-1)%cols*(cw+12),y+math.floor((i-1)/cols)*225,cw,213,true)
  local art=U.Frame(card,'Art',6,6,cw-12,90,tone:Lerp(Color3.new(1,1,1),.78));U.Round(art,10)
  preview(c,art,row,4,1,cw-20,88)
  U.Center(card,row.Name or row.Kind,7,99,cw-14,34,18,P.text,true)
  local lines,owned=oddsLines(row)
  oddsLabel(fit(U.Center(card,table.concat(lines,'\n'),7,134,cw-14,42,13,P.muted,true),13),owned)
  local chance=U.Badge(card,string.format('%.6g%%',(row.Chance or 0)*100),8,180,cw-16,row.Multiplier and P.red or tone);chance.Name='Chance'
 end
end
function S.TicketShop(c)
 local info=infoOrLoad(c);if not info then return end
 local U,W=c.U,c.W;local P=U.Colors
 local sc=U.Scroll(c.Parent,'DogTokenInfo',0,0,W,c.H)
 local y=wallet(c,sc,info)
 U.Text(sc,'Use one DOG TOKEN to activate the world machine and receive one random reward. View REWARD CHANCES before activating.',12,y,W-32,60,18,P.text);y+=66
 U.Text(sc,'Your next free DOG TOKEN arrives 5 hours after use, including time away. Free tokens are always used before bought ones.',12,y,W-32,60,17,P.muted);y+=68
 if info.FreeOnly==false then
  U.Section(sc,'LUCKY SPIN PACKS',8,y,W-24,38);y+=46
  -- ProductPricing reports a refused or failed prompt here.
  if c.State.CommerceMessage then U.Text(sc,c.State.CommerceMessage,12,y,W-32,40,16,P.red);y+=44 end
  local Pricing=require(script.Parent.ProductPricing)
  local cols=math.max(1,math.min(3,math.floor((W-10)/230)));local cw=(W-24-(cols-1)*12)/cols
  local products=info.TicketProducts or {}
  for i,row in ipairs(products)do
   local card=U.Panel(sc,'Spins_'..row.Key,8+(i-1)%cols*(cw+12),y+math.floor((i-1)/cols)*172,cw,160,true)
   U.Icon(card,row.Key,10,10,64,P.gold)
   U.Text(card,row.Name or row.Key,82,12,cw-92,30,21,P.text,true)
   U.Text(card,U.Fmt(row.Count)..(row.Count==1 and' DOG TOKEN'or' DOG TOKENS'),82,44,cw-92,26,17,P.purple,true)
   local label,action='UNAVAILABLE',nil
   if row.CanPurchase then label,action=Pricing.Quote(c,sc,{Key=row.Key,Id=row.ProductId,Enabled=true,Route='RewardMachineProduct'})end
   U.Button(card,'Buy',label,10,104,cw-20,44,action,P.purple).Caption.TextSize=16
   if not row.CanPurchase and row.UnavailableReason then U.Text(card,row.UnavailableReason,10,76,cw-20,26,13,P.muted)end
  end
  y+=math.ceil(#products/cols)*172+4
  -- Paid random items: the exact odds a bought token rolls, before purchase.
  U.Section(sc,'REWARD CHANCES · EVERY TOKEN',8,y,W-24,38);y+=46
  local aurion
  for _,row in ipairs(info.Rewards or{})do
   if row.Id=='Aurion'then aurion=row end
   U.Text(sc,row.Name or row.Kind,16,y,W-150,24,16,P.text,true)
   U.Text(sc,string.format('%.6g%%',(row.Chance or 0)*100),W-130,y,100,24,16,row.Multiplier and P.red or P.purple,true).TextXAlignment=Enum.TextXAlignment.Right
   y+=24
   local lines,owned=oddsLines(row)
   for _,line in ipairs(lines)do oddsLabel(fit(U.Text(sc,line,24,y,W-60,18,13,P.muted),13),owned);y+=18 end
   y+=6
  end
  y+=6
  local odds=Text.AurionOdds()
  local chance=aurion and aurion.ChanceText or odds.ChanceText;local oneIn=aurion and Text.OneIn(aurion.ChanceUnits)or odds.OneIn
  local en=string.format('Aurion: %s per spin (1 in %s).',chance,oneIn)
  local ru=string.format('Аурион: %s за вращение (1 из %s).',chance,(oneIn:gsub(',',' ')))
  if odds.Multiplier then
   en..=string.format(' During %s: x%g (%s).',odds.EventName,odds.Multiplier,odds.BoostChanceText)
   ru..=string.format(' Во время Радужного разлома: x%g (%s).',odds.Multiplier,odds.BoostChanceText)
  end
  Text.Own(U.Text(sc,Text.L(en,ru),12,y,W-32,44,15,P.text));y+=48
  U.Text(sc,'Paid tokens are delivered after Roblox confirms payment and only work where Roblox allows paid random items.',12,y,W-32,44,15,P.muted);y+=50
 else
  U.Text(sc,'No Coins, Bones, Robux or items are needed. Extra activations cannot be purchased.',12,y,W-32,68,17,P.text);y+=77
 end
 U.Button(sc,'BackToRewardMachine','BACK TO DOG-O-MATIC',8,y,W-24,45,function()c.Show('RewardMachine')end,P.purple)
end
return S
