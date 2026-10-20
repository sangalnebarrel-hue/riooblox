local Players=game:GetService('Players')
local Replicated=game:GetService('ReplicatedStorage')
local Lighting=game:GetService('Lighting')
local Config=require(Replicated.DogEconomy.Config)
local player=Players.LocalPlayer
local map=workspace:WaitForChild('DOGROTS_District')
-- Mutated dogs: ReplicatedStorage.MutationGlow (a distinct animated look per variant). Track infers the
-- kind from the container: kennel dogs also get the mutation tag, the dig spray / find bursts and, while
-- they dig in the mine, a beacon over their pit; it re-fits dogs whose parts stream in late.
local MutationGlow=require(Replicated:WaitForChild('MutationGlow'))
local tint=Instance.new('ColorCorrectionEffect');tint.Name='DogrotsLayerTint';tint.Parent=Lighting
-- The game ships no uploaded SFX: coin, sale and rare-find cues use MiningAudio's built-in recipes.
local MiningAudio=require(Replicated:WaitForChild('Mining'):WaitForChild('MiningAudio'))
local SoundConfig=require(Replicated:WaitForChild('WorldSoundConfig'))
local IncomeText=require(Replicated.DogEconomy:WaitForChild('IncomeText'))
local function layer()
 local i=player:GetAttribute('CurrentLayer')or 1;local c=Config.Layers[i].Color
 tint.TintColor=Color3.new(1,1,1):Lerp(Color3.fromRGB(c[1],c[2],c[3]),.06)
end
player:GetAttributeChangedSignal('CurrentLayer'):Connect(layer);layer()
local function decorate(dog)
 if not dog:IsA('Model')then return end
 MutationGlow.Track(dog)
 -- Titles are shown above the player now (PlayerTitles), not over the kennel dogs.
end
MutationGlow.Start()
for _,f in ipairs({map:WaitForChild('KennelDogs'),map['03_DogLine']:WaitForChild('ActiveDogs')})do f.ChildAdded:Connect(decorate);for _,dog in ipairs(f:GetChildren())do decorate(dog)end end
-- Yard display dogs (Economy.PlotShowcase: DogStorage.DisplaySlots.SlotN.DisplayDog).
task.spawn(function()
 local yards=map:WaitForChild('04_PlayerYards',30);if not yards then return end
 local function display(o)if o.Name=='DisplayDog'and o:IsA('Model')then decorate(o)end end
 yards.DescendantAdded:Connect(display)
 for _,o in ipairs(yards:GetDescendants())do display(o)end
end)

-- Findings are cosmetic projections of committed server instances. No client rolls.
local V=require(Replicated.DogEconomy.DiscoveryVisuals)
local Tween=game:GetService('TweenService')
local playerGui=player:WaitForChild('PlayerGui')
local gui=playerGui:FindFirstChild('ScreenGui')
while not gui do
 local child=playerGui.ChildAdded:Wait()
 if child.Name=='ScreenGui' then gui=child end
end
-- Dog income feedback: a pooled "+$X" over your own dog each time a dig pays, and a soft coin
-- tick. Server truth only (DogInventory LastYield / WorkSequence, mirrored by Runtime.Project).
-- At most 8 popups, only within 70 studs, bursts on one dog merge, Low FX keeps 3 and no rise,
-- ReducedMotion fades in place.
local POPUPS,RANGE=8,70
local popupHolder=Instance.new('Folder');popupHolder.Name='DOGROTS_IncomePopups';popupHolder.Parent=playerGui
local popupPool={}
local function lowFX()return player:GetAttribute('WorldEventFX')=='Low'or player:GetAttribute('LowFX')==true end
local function reduced()return player:GetAttribute('ReducedMotion')==true end
for i=1,POPUPS do
 local board=Instance.new('BillboardGui');board.Name='IncomePopup'..i;board.Size=UDim2.fromOffset(150,40);board.AlwaysOnTop=true;board.LightInfluence=0
 board.MaxDistance=RANGE;board.Enabled=false;board:SetAttribute('NoTranslate',true)
 local text=Instance.new('TextLabel');text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.Font=Enum.Font.FredokaOne
 text.TextScaled=true;text.TextColor3=Color3.fromRGB(132,255,57);text.Parent=board
 local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(23,43,76);stroke.Thickness=2.5;stroke.Parent=text
 board.Parent=popupHolder
 popupPool[i]={Gui=board,Text=text,Stroke=stroke,Model=nil,Amount=0,At=-math.huge,Tweens={}}
end
local coinAt=0
local function showIncome(model,amount)
 local root:BasePart?=model.PrimaryPart or(model:FindFirstChildWhichIsA('BasePart',true)::any)
 local camera=workspace.CurrentCamera
 if not root or not camera or(camera.CFrame.Position-root.Position).Magnitude>RANGE then return end
 local now=os.clock();local slot
 -- Merge a burst on the same dog into its live popup.
 for _,p in ipairs(popupPool)do if p.Model==model and now-p.At<.6 then slot=p;amount+=p.Amount;break end end
 if not slot then
  local limit=lowFX()and 3 or POPUPS;local oldest
  for i=1,limit do local p=popupPool[i];if not p.Gui.Enabled then slot=p;break end;if not oldest or p.At<oldest.At then oldest=p end end
  slot=slot or oldest
 end
 for _,t in ipairs(slot.Tweens)do t:Cancel()end;table.clear(slot.Tweens)
 local _,size=model:GetBoundingBox()
 local start=Vector3.new(0,math.clamp(size.Y*.5+1.2,1.5,8),0)
 slot.Model=model;slot.Amount=amount;slot.At=now
 slot.Gui.Adornee=root;slot.Gui.StudsOffsetWorldSpace=start
 slot.Text.Text=IncomeText.Get('Popup',IncomeText.Compact(amount));slot.Text.TextTransparency=0;slot.Stroke.Transparency=0
 slot.Gui.Size=UDim2.fromOffset(150,40);slot.Gui.Enabled=true
 local still=reduced()or lowFX()
 local function add(t)table.insert(slot.Tweens,t);t:Play();return t end
 if not still then
  add(Tween:Create(slot.Gui,TweenInfo.new(1.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{StudsOffsetWorldSpace=start+Vector3.new(0,2.4,0)}))
  slot.Gui.Size=UDim2.fromOffset(110,30)
  add(Tween:Create(slot.Gui,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(150,40)}))
 end
 local fade=TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.7)
 add(Tween:Create(slot.Text,fade,{TextTransparency=1}))
 local last=add(Tween:Create(slot.Stroke,fade,{Transparency=1}))
 local stamp=now
 last.Completed:Connect(function(state)
  if state==Enum.PlaybackState.Completed and slot.At==stamp then slot.Gui.Enabled=false;slot.Gui.Adornee=nil;slot.Model=nil end
 end)
 if now-coinAt>=.25 and not gui:GetAttribute('OpenMenu')then coinAt=now;MiningAudio.Play('Coin',nil,math.min(10,math.floor(math.log10(math.max(1,amount)))))end
end
local kennelDogs=map:WaitForChild('KennelDogs')
local eventDogs=nil -- RS.Halloween.Models.EventDogs, required on the first event-dog dig
local function watchDog(entry)
 if not entry:IsA('StringValue')then return end
 local lastSeq=entry:GetAttribute('WorkSequence')or 0
 local queued=false
 local function check()
  queued=false
  local seq=entry:GetAttribute('WorkSequence')or 0
  if seq==lastSeq then return end
  lastSeq=seq
  local yield=tonumber(entry:GetAttribute('LastYield'))or 0
  if yield<=0 or(entry:GetAttribute('AssignedSlot')or'')==''then return end
  local model=kennelDogs:FindFirstChild(entry.Name)
  if model and model:IsA('Model')and model:GetAttribute('OwnerUserId')==player.UserId then showIncome(model,yield)end
  -- NIGHT OF THE BURIED MOON event dogs flare their ability FX on each finished dig (client-only; BurstFX reuses one
  -- emitter per hook, makes no lights, does nothing beyond 120 studs / behind the camera, 40 % on Low / Reduced Motion)
  local id=model and model:GetAttribute('DogId')
  if type(id)=='string'and string.sub(id,1,3)=='HW_'then
   pcall(function()
    if not eventDogs then
     local hw=game:GetService('ReplicatedStorage'):FindFirstChild('Halloween')
     local m=hw and hw:FindFirstChild('Models')and hw.Models:FindFirstChild('EventDogs')
     eventDogs=m and require(m)or nil
    end
    if eventDogs then eventDogs.BurstFX(model,10,{Low=lowFX(),Reduced=reduced()})end
   end)
  end
 end
 -- Both attributes replicate together; read them once the frame's changes have landed.
 local function changed()if not queued then queued=true;task.defer(check)end end
 entry:GetAttributeChangedSignal('WorkSequence'):Connect(changed)
 entry:GetAttributeChangedSignal('LastYield'):Connect(changed)
end
task.spawn(function()
 local inventory=player:WaitForChild('DogInventory')
 inventory.ChildAdded:Connect(watchDog)
 for _,entry in ipairs(inventory:GetChildren())do watchDog(entry)end
end)
-- Sale chime: the wallet grows right after finds or old loot leave storage. With an uploaded Sell
-- sound (WorldSoundConfig) that cue plays (WorldSound throttles it against the NPC sale's own cue);
-- otherwise MiningAudio's built-in coin chime.
local soldAt=-math.huge
local lastItems,lastPending=player:GetAttribute('ItemCount')or 0,player:GetAttribute('PendingCash')or 0
player:GetAttributeChangedSignal('ItemCount'):Connect(function()
 local n=player:GetAttribute('ItemCount')or 0;if n<lastItems then soldAt=os.clock()end;lastItems=n
end)
player:GetAttributeChangedSignal('PendingCash'):Connect(function()
 local n=player:GetAttribute('PendingCash')or 0;if n<lastPending then soldAt=os.clock()end;lastPending=n
end)
task.spawn(function()
 local coins=player:WaitForChild('leaderstats'):WaitForChild('Coins')
 local lastCoins=coins.Value
 coins:GetPropertyChangedSignal('Value'):Connect(function()
  local value=coins.Value
  if value>lastCoins and os.clock()-soldAt<2 then
   soldAt=-math.huge
   local sell=SoundConfig.Cues and SoundConfig.Cues.Sell
   if sell and(tonumber(sell.Id)or 0)>0 then require(Replicated.WorldSound).Cue('Sell')else MiningAudio.Play('Buy')end
  end
  lastCoins=value
 end)
end)
local banner=Instance.new('TextLabel');banner.Name='DiscoveryToast';banner.AnchorPoint=Vector2.new(.5,0)
banner.Position=UDim2.fromScale(.5,.17);banner.Size=UDim2.fromScale(.55,.115);banner.BackgroundColor3=Color3.fromRGB(32,23,40)
banner.BackgroundTransparency=.12;banner.TextColor3=Color3.fromRGB(255,225,139);banner.TextStrokeTransparency=.5
banner.Font=Enum.Font.FredokaOne;banner.TextScaled=true;banner.TextWrapped=true;banner.Visible=false;banner.ZIndex=80;banner.Parent=gui
local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,12);corner.Parent=banner
local constraint=Instance.new('UITextSizeConstraint');constraint.MaxTextSize=24;constraint.MinTextSize=12;constraint.Parent=banner
local token=0;local recent={}
local function toast(message,seconds)
 if gui:GetAttribute('OpenMenu')then return end
 token+=1;local version=token;banner.Text=message;banner.Visible=true
 task.delay(seconds or 4,function()if version==token then banner.Visible=false end end)
end
gui:GetAttributeChangedSignal('OpenMenu'):Connect(function()if gui:GetAttribute('OpenMenu')then token+=1;banner.Visible=false end end)
-- Find reveal on the dig pit. The find rises out of the pit with a short pop, then spins slowly; a
-- rarity-coloured glow ring spreads and fades on the ground; Epic and better add a light beam above
-- it, Legendary / Secret one short sparkle burst. The name / weight billboard stays. Its parts are
-- welded to the model root and only the root is tweened (no per-frame Lua). Pooled: at most
-- REVEALS alive, the oldest is recycled, everything is cleared when a reveal ends.
-- ReducedMotion (player attribute or Roblox setting): no rise, spin, spread or sparkles.
-- Low FX (LowFX / WorldEventFX=Low / graphics quality <= 3): no beam, no sparkles, no spin.
local REVEALS=4
local revealFolder
local revealSlots={}
local function revealReduced()
 if reduced()then return true end
 local ok,value=pcall(function()return(game:GetService('GuiService')::any).ReducedMotionEnabled end)
 return ok and value==true
end
local function revealLowFX()
 if lowFX()then return true end
 local ok,level=pcall(function()return UserSettings():GetService('UserGameSettings').SavedQualityLevel.Value end)
 return ok and type(level)=='number'and level>0 and level<=3
end
local function effectPart(name,shape)
 local p=Instance.new('Part');p.Name=name;p.Shape=shape;p.Material=Enum.Material.Neon;p.Anchored=true
 p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 return p
end
local function releaseReveal(slot)
 slot.Token+=1;slot.Busy=false
 for _,t in ipairs(slot.Tweens)do t:Cancel()end;table.clear(slot.Tweens)
 if slot.Spin then slot.Spin:Cancel();slot.Spin=nil end
 if slot.Model then slot.Model:Destroy();slot.Model=nil end
 slot.Label.Enabled=false;slot.Label.Adornee=nil
 slot.Ring.Parent=nil;slot.Beam.Parent=nil;slot.Spark.Parent=nil
end
local function revealSlot()
 if not revealFolder or not revealFolder.Parent then
  revealFolder=Instance.new('Folder');revealFolder.Name='DOGROTS_FindReveals';revealFolder.Parent=workspace
  for _,slot in ipairs(revealSlots)do slot.Label.Parent=revealFolder end
 end
 local free,oldest
 for _,slot in ipairs(revealSlots)do
  if not slot.Busy then free=slot;break end
  if not oldest or slot.At<oldest.At then oldest=slot end
 end
 if not free and #revealSlots<REVEALS then
  free={Token=0,Tweens={},At=0}
  free.Ring=effectPart('RevealRing',Enum.PartType.Cylinder)
  free.Beam=effectPart('RevealBeam',Enum.PartType.Cylinder)
  free.Spark=effectPart('RevealSparkle',Enum.PartType.Block);free.Spark.Size=Vector3.one*.2;free.Spark.Transparency=1
  local emitter=Instance.new('ParticleEmitter');emitter.Enabled=false;emitter.Rate=0;emitter.LightEmission=1;emitter.LightInfluence=0
  emitter.Lifetime=NumberRange.new(.7,1.3);emitter.Speed=NumberRange.new(4,9);emitter.SpreadAngle=Vector2.new(180,180);emitter.Drag=3
  emitter.Acceleration=Vector3.new(0,-3,0);emitter.RotSpeed=NumberRange.new(-120,120)
  emitter.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.38),NumberSequenceKeypoint.new(1,0)})
  emitter.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.7,.2),NumberSequenceKeypoint.new(1,1)})
  emitter.Parent=free.Spark;free.Emitter=emitter
  local label=Instance.new('BillboardGui');label.Name='RevealLabel';label.Size=UDim2.fromOffset(230,66);label.MaxDistance=90;label.Enabled=false;label.Parent=revealFolder
  local text=Instance.new('TextLabel');text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.TextColor3=Color3.fromRGB(255,234,157);text.Font=Enum.Font.FredokaOne;text.TextSize=18;text.TextStrokeTransparency=.2;text.Parent=label
  free.Label=label;free.Text=text
  table.insert(revealSlots,free)
 end
 if not free then free=oldest;releaseReveal(free)end
 free.Busy=true;free.At=os.clock()
 return free
end
local function showReveal(model:Model,x,spawn)
 local slot=revealSlot();local stamp=slot.Token
 slot.Model=model
 local rarity=V.Rarity(x.ItemId);local rank=V.RarityRank[rarity]or 1;local color=V.RarityColor(rarity)
 -- NIGHT OF THE BURIED MOON finds: the ring / beam take the mutation's colour and the beam always shows
 local eventColor=V.MutationColors and V.MutationColors[string.upper(tostring(x.Mutation or''))]
 if eventColor then color=eventColor;rank=math.max(rank,string.upper(tostring(x.Mutation))=='ECLIPSED'and 6 or 5)end
 local still,low=revealReduced(),revealLowFX()
 local function add(t)table.insert(slot.Tweens,t);t:Play();return t end
 -- Root = the ground contact point: the recipe model's Root, or a new one under an old model.
 local box,size=V.Bounds(model)
 local root=model.PrimaryPart
 if not root then
  root=Instance.new('Part');root.Name='RevealRoot';root.Size=Vector3.one*.05;root.Transparency=1;root.Anchored=true
  root.CanCollide=false;root.CanTouch=false;root.CanQuery=false;root.CFrame=box*CFrame.new(0,-size.Y/2,0);root.Parent=model;model.PrimaryPart=root
 end
 local base=spawn.CFrame
 local final=base*CFrame.new(0,.3,0)
 model:PivotTo(still and final or base*CFrame.new(0,-math.max(1,size.Y)*1.1,0))
 model.Parent=revealFolder
 for _,p in ipairs(model:GetDescendants())do
  if p:IsA('BasePart')and p~=root then
   local weld=Instance.new('WeldConstraint');weld.Part0=root;weld.Part1=p;weld.Parent=p
   p.Massless=true;p.Anchored=false
  end
 end
 local function spin(step)
  if slot.Token~=stamp or not root.Parent then return end
  slot.Spin=Tween:Create(root,TweenInfo.new(2.6,Enum.EasingStyle.Linear),{CFrame=final*CFrame.Angles(0,step*2*math.pi/3,0)})
  slot.Spin.Completed:Connect(function(state)if state==Enum.PlaybackState.Completed then spin(step+1)end end)
  slot.Spin:Play()
 end
 if not still then
  local rise=add(Tween:Create(root,TweenInfo.new(.6,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{CFrame=final}))
  if not low then rise.Completed:Connect(function(state)if state==Enum.PlaybackState.Completed then spin(1)end end)end
 end
 -- Glow ring on the ground.
 local ring=slot.Ring;local diameter=math.clamp(math.max(size.X,size.Z)*1.8,3,10)
 local start=still and 1 or .35
 ring.Color=color;ring.Transparency=.2;ring.Size=Vector3.new(.06,diameter*start,diameter*start)
 ring.CFrame=base*CFrame.new(0,.05,0)*CFrame.Angles(0,0,math.pi/2);ring.Parent=revealFolder
 if not still then add(Tween:Create(ring,TweenInfo.new(.55,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(.06,diameter,diameter)}))end
 add(Tween:Create(ring,TweenInfo.new(2.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.8),{Transparency=1}))
 -- Light beam above Epic+ finds.
 if rank>=4 and not low then
  local beam=slot.Beam;local height=rank>=5 and 28 or 18;local width=rank>=5 and 1.6 or 1.1
  beam.Color=color;beam.Transparency=.45;beam.Size=Vector3.new(height,width,width)
  beam.CFrame=final*CFrame.new(0,size.Y+.4+height/2,0)*CFrame.Angles(0,0,math.pi/2);beam.Parent=revealFolder
  add(Tween:Create(beam,TweenInfo.new(2.6,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,1.2),{Transparency=1}))
 end
 -- One sparkle burst for Legendary / Secret.
 if rank>=5 and not low and not still then
  slot.Spark.CFrame=final*CFrame.new(0,size.Y/2,0);slot.Spark.Parent=revealFolder
  slot.Emitter.Color=ColorSequence.new(color:Lerp(Color3.new(1,1,1),.35),color)
  task.delay(.45,function()if slot.Token==stamp then slot.Emitter:Emit(rank>=6 and 34 or 24)end end)
 end
 slot.Label.Adornee=root;slot.Label.StudsOffsetWorldSpace=Vector3.new(0,size.Y+1.3,0)
 slot.Text.Text=x.DisplayName..'\n'..string.format('%.6g kg',x.WeightKg)..' · '..x.WeightTier;slot.Label.Enabled=true
 task.delay(x.TierIndex>=7 and 14 or 6,function()if slot.Token==stamp then releaseReveal(slot)end end)
end
Replicated:WaitForChild('DiscoveryReveal').OnClientEvent:Connect(function(x)
 if recent[x.ItemUid]then return end;recent[x.ItemUid]=true;task.delay(60,function()recent[x.ItemUid]=nil end)
 local model=V.Clone(x);if not model then return end
 local spawn=x.LootSpawn
 if type(spawn)~='table'or spawn.OwnerUserId~=player.UserId or typeof(spawn.CFrame)~='CFrame' then model:Destroy();return end
 -- This transform was resolved on the server from the current dog/kennel binding.
 -- Never fall back to the player's character, direction or camera.
 -- Halloween finds (Dead Yard ores / haunted dig spots) carry LootSpawn.Venue=='Halloween' and a world CFrame there.
 if spawn.Venue~='Halloween'then
  local yard
  for _,candidate in ipairs(map['04_PlayerYards']:GetChildren())do
   if candidate:GetAttribute('YardId')==spawn.YardId and candidate:GetAttribute('OwnerUserId')==player.UserId then yard=candidate;break end
  end
  if not yard or not yard:FindFirstChild(spawn.Slot)then model:Destroy();return end
 end
 local shown,err=pcall(showReveal,model,x,spawn)
 if not shown then warn('DOGROTS find reveal: '..tostring(err));model:Destroy()end
 if x.TierIndex>=4 or x.Mutation~='NORMAL' or x.Class=='Secret'then
  toast(x.Mutation..' '..x.DisplayName..'\n'..string.format('%.6g kg',x.WeightKg)..' · '..x.WeightTier..'\nCombined: 1 / '..string.format('%.4g',x.CombinedOdds),x.TierIndex>=7 and 7 or 4)
 end
 if not gui:GetAttribute('OpenMenu')and(x.TierIndex>=5 or x.Class=='Secret')then
  MiningAudio.Play('RareBreak')
  -- One short zoom, with no change to camera position or player controls.
  local camera=workspace.CurrentCamera
  if camera and x.TierIndex>=6 and not player:GetAttribute('ReducedMotion') and not camera:GetAttribute('DiscoveryZoom')then
   camera:SetAttribute('DiscoveryZoom',true);local original=camera:GetAttribute('SecretZoom')or camera.FieldOfView
   Tween:Create(camera,TweenInfo.new(.25),{FieldOfView=math.min(90,original+6)}):Play()
   task.delay(.4,function()if camera.Parent then Tween:Create(camera,TweenInfo.new(.5),{FieldOfView=original}):Play();task.delay(.6,function()camera:SetAttribute('DiscoveryZoom',nil)end)end end)
  end
  if x.TierIndex>=7 and not player:GetAttribute('ReducedMotion')then
   local humanoid=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
   if humanoid then task.spawn(function()
    local original=humanoid.CameraOffset
    for index=1,10 do if not humanoid.Parent then break end;humanoid.CameraOffset=original+Vector3.new(math.sin(index*4)*.09,math.cos(index*5)*.07,0)*(1-index/11);task.wait(.04)end
    if humanoid.Parent then humanoid.CameraOffset=original end
   end)end
  end
  if x.TierIndex>=9 then
   local bars={};for _,top in ipairs({true,false})do local b=Instance.new('Frame');b.BackgroundColor3=Color3.new();b.BorderSizePixel=0;b.Size=UDim2.fromScale(1,.07);b.Position=UDim2.fromScale(0,top and 0 or .93);b.ZIndex=75;b.Parent=gui;table.insert(bars,b)end
   task.delay(2,function()for _,b in ipairs(bars)do b:Destroy()end end)
  end
 end
end)
Replicated:WaitForChild('DiscoveryAnnouncement').OnClientEvent:Connect(function(x,global)
 toast((global and 'GLOBAL RECORD · ' or 'INCREDIBLE FIND · ')..x.DisplayName..'\n'..string.format('%.6g kg',x.WeightKg)..' · finder '..x.OriginalFinderUserId,6)
end)
