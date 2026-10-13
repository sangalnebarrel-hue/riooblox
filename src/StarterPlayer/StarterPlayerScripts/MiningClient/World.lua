-- Renders the Active Mining corner of every yard on this client: the ore pile (built from the
-- owner's ore id + serial so every player sees the same pile), its shrink as HP drops, hit and
-- break effects for other players' mining, localized prompts/signs and the owner-only prompts.
local Players=game:GetService('Players')
local TweenService=game:GetService('TweenService')
local World={}

local RARE_FROM=7 -- ore index from which a reveal pillar + chime plays (Amethyst and rarer)

function World.new(ctx)
 local self:any={Views={}}
 local player=ctx.Player
 local M,Text,Models,Audio=ctx.M,ctx.Text,ctx.Models,ctx.Audio
 local function fx()return ctx.FX end

 local function oreDef(id)
  local ore,index=ctx.Rules.OreById(M,id);if ore then return ore,index end
  return M.Ores[1],1
 end
 self.OreDef=oreDef
 local function oreColor(def)
  local v=def.Visual or{};return Models.RGB(v.Accent or v.Rock)
 end
 self.OreColor=oreColor
 local function rockColor(def)return Models.RGB((def.Visual or{}).Rock)end

 local function isOwner(corner)
  return corner and corner:GetAttribute('OwnerUserId')==player.UserId
 end
 self.IsOwner=isOwner
 function self.MyCorner()
  for corner,_ in pairs(self.Views)do if isOwner(corner)and corner.Parent then return corner end end
  local map=workspace:FindFirstChild('DOGROTS_District');local yards=map and map:FindFirstChild('04_PlayerYards')
  if yards then
   for _,yard in ipairs(yards:GetChildren())do
    local corner=yard:FindFirstChild('MiningCorner')
    if corner and isOwner(corner)then return corner end
   end
  end
  return nil
 end

 -- PILE ---------------------------------------------------------------------------------------
 local function pileCF(view)
  local core=view.Core
  local root=core and core:FindFirstChild('OreRoot')
  if not root then return nil end
  local rot=core.CFrame-core.CFrame.Position
  return CFrame.new(root.WorldPosition)*rot
 end
 local function targetScale(view,state)
  local corner=view.Corner
  local hp=state and state.OreHP or corner:GetAttribute('OreHP')or 1
  local max=math.max(1,state and state.OreMaxHP or corner:GetAttribute('OreMaxHP')or 1)
  return .55+.45*math.clamp(hp/max,0,1)
 end
 self.TargetScale=targetScale
 local function setScale(view,scale,time)
  local model=view.Pile;if not model or not model.Parent then return end
  if view.ScaleTween then view.ScaleTween:Cancel()end
  local value=view.ScaleValue
  if time and time>0 then
   view.ScaleTween=TweenService:Create(value,TweenInfo.new(time,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Value=scale})
   view.ScaleTween:Play()
  else value.Value=scale end
 end
 local function destroyPile(view)
  if view.Pile then view.Pile:Destroy();view.Pile=nil end
  for _,sat in ipairs(view.Sats or{})do sat.Model:Destroy()end
  view.Sats={}
  view.HitPoints={}
 end
 -- Satellite outcrops (Attachments OreSat* on the core, written by MiningWorld): the same ore in
 -- smaller piles around the main one. Their hit points join the main pile's, so the timing
 -- circles spread over the whole dig site. Low FX keeps them only on the player's own corner.
 local function buildSats(view,def,serial,owner,index)
  view.Sats={}
  local core=view.Core;if not core then return end
  if fx().Low()and not isOwner(view.Corner)then return end
  for _,att in ipairs(core:GetChildren())do
   local i=att:IsA('Attachment')and tonumber(string.match(att.Name,'^OreSat(%d+)$'))
   if i then
    local scale=att:GetAttribute('Scale')or .45
    local cf=CFrame.new(att.WorldPosition)*CFrame.Angles(0,(i*1.7)%(math.pi*2),0)
    local model,points=Models.Ore(def,serial*7919+(owner%100003)+index+i*131,cf,scale,true)
    model.Name='OreSat_'..i
    for _,d in ipairs(model:GetDescendants())do
     if d:IsA('ParticleEmitter')then d.Rate*=.4 elseif d:IsA('PointLight')then d:Destroy()end
    end
    model.Parent=fx().Folder
    table.insert(view.Sats,{Model=model,BaseCF=model:GetPivot()})
    for _,a in ipairs(points)do table.insert(view.HitPoints,a)end
   end
  end
 end
 -- state (optional) overrides the corner attributes with a fresher server response.
 local function buildPile(view,grow,state)
  destroyPile(view)
  local corner=view.Corner
  local cf=pileCF(view);if not cf then return end
  local def,index=oreDef(state and state.OreId or corner:GetAttribute('OreId'))
  local serial=state and state.OreSerial or corner:GetAttribute('OreSerial')or 0
  local owner=corner:GetAttribute('OwnerUserId')or 0
  local model,points=Models.Ore(def,serial*7919+(owner%100003)+index,cf,1)
  model.Name='OrePile_'..(corner.Parent and corner.Parent.Name or'Yard')
  if fx().Low()then
   for _,d in ipairs(model:GetDescendants())do
    if d:IsA('ParticleEmitter')then d.Rate=d.Rate*.3 elseif d:IsA('PointLight')then d.Range*=.7 end
   end
  end
  model.Parent=fx().Folder
  view.Pile=model;view.HitPoints=points;view.Def=def;view.Index=index;view.Serial=serial
  view.BaseCF=model:GetPivot()
  buildSats(view,def,serial,owner,index)
  if not view.ScaleValue then
   view.ScaleValue=Instance.new('NumberValue');view.ScaleValue.Value=1
   view.ScaleValue.Changed:Connect(function(v)
    if v<=.01 then return end
    local m=view.Pile;if m and m.Parent then pcall(function()m:ScaleTo(v)end)end
    -- Satellites shrink less than the main pile (they are the "rest of the vein").
    local k=.5+v*.5
    for _,sat in ipairs(view.Sats or{})do if sat.Model.Parent then pcall(function()sat.Model:ScaleTo(k)end)end end
   end)
  end
  if grow then
   view.ScaleValue.Value=.05;pcall(function()model:ScaleTo(.05)end)
   for _,sat in ipairs(view.Sats)do pcall(function()sat.Model:ScaleTo(.05)end)end
   setScale(view,targetScale(view,state),.65)
  else
   view.ScaleValue.Value=targetScale(view,state);pcall(function()model:ScaleTo(view.ScaleValue.Value)end)
   local k=.5+view.ScaleValue.Value*.5
   for _,sat in ipairs(view.Sats)do pcall(function()sat.Model:ScaleTo(k)end)end
  end
  self.UpdateLabel(view,state)
 end

 -- Every chunk of the old pile (and its satellites) flies apart.
 local function shatterModel(model)
  local center=model:GetPivot().Position+Vector3.new(0,3,0)
  for _,d in ipairs(model:GetDescendants())do
   if d:IsA('BasePart')and d.Transparency<1 then
    d.Anchored=false;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true
    local dir=(d.Position-center);dir=dir.Magnitude>.01 and dir.Unit or Vector3.new(0,1,0)
    d.AssemblyLinearVelocity=(dir+Vector3.new(0,.9,0)).Unit*(16+math.random()*14)
    d.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*14
    TweenService:Create(d,TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.5),{Transparency=1}):Play()
   elseif d:IsA('ParticleEmitter')then d.Enabled=false
   elseif d:IsA('PointLight')then d.Enabled=false end
  end
  task.delay(1.3,function()model:Destroy()end)
 end
 local function shatter(view)
  local model=view.Pile;if not model then return end
  view.Pile=nil
  shatterModel(model)
  for _,sat in ipairs(view.Sats or{})do shatterModel(sat.Model)end
  view.Sats={}
 end

 -- Break + rebuild sequence (also used by the owner's Mine module, which passes the fresh
 -- server state so the new pile does not wait for attribute replication).
 function self.PlayBreak(view,local2D,state)
  if not view.Core then return end -- streamed out: the pile is rebuilt when the core returns
  local def=view.Def or oreDef(view.Corner:GetAttribute('BrokenId'))
  local cf=pileCF(view)
  local center=(cf and cf.Position or view.Core.Position)+Vector3.new(0,3.2,0)
  local color=oreColor(def)
  view.Breaking=true -- the break pause: syncCore must not rebuild the pile meanwhile
  shatter(view)
  local F=fx()
  F.Burst(center,{Color=color,Count=40,Speed=NumberRange.new(14,30),Spread=Vector2.new(180,180),Lifetime=NumberRange.new(.5,1.1)})
  F.Burst(center,{Color=Color3.fromRGB(255,214,80),Color2=Color3.fromRGB(255,170,40),Count=26,Speed=NumberRange.new(10,22),Spread=Vector2.new(60,60),Direction=Vector3.new(0,1,0),Acceleration=Vector3.new(0,-40,0)})
  F.Ring(center-Vector3.new(0,2.6,0),color,18,.7)
  F.Chunks(center,rockColor(def),Enum.Material.Slate,10,Vector3.new(0,1,0),24)
  local index=view.Index or 1
  if local2D then
   Audio.Play(index>=RARE_FROM and'RareBreak'or'Break')
   F.Shake(.7);F.Flash(color,.25)
  else
   Audio.Play('Break',view.Core)
  end
  view.Serial=state and state.OreSerial or view.Corner:GetAttribute('OreSerial')or 0
  task.delay(M.Client.BreakPause*.55,function()
   view.Breaking=nil
   if not view.Corner.Parent or self.Views[view.Corner]~=view then return end
   buildPile(view,true,state)
   local _,newIndex=oreDef(state and state.OreId or view.Corner:GetAttribute('OreId'))
   if newIndex>=RARE_FROM and cf then
    F.Pillar(cf.Position,oreColor(view.Def),local2D and 46 or 30)
    if local2D then Audio.Play('RareBreak')end
   end
   if local2D and self.OnNewOre then self.OnNewOre(view)end
  end)
 end

 -- A point on the pile that faces the given world position (for circles and hit effects).
 function self.HitPoint(view,towards,avoid)
  local best,bestScore=nil,-math.huge
  for _,att in ipairs(view.HitPoints or{})do
   if att.Parent then
    local pos=att.WorldPosition
    local normal=att:GetAttribute('Normal');normal=typeof(normal)=='Vector3'and normal or Vector3.new(0,1,0)
    local facing=towards and normal:Dot((towards-pos).Unit)or 0
    local score=facing+math.random()*.9
    if avoid and avoid[att]then score-=2 end
    if score>bestScore then best,bestScore=att,score end
   end
  end
  return best
 end
 -- point (optional): the hit point that was struck; the pile (main or satellite) it sits on wobbles.
 function self.Wobble(view,strength,point)
  local model,base=view.Pile,view.BaseCF
  if point then
   for _,sat in ipairs(view.Sats or{})do if point:IsDescendantOf(sat.Model)then model,base=sat.Model,sat.BaseCF end end
  end
  if not model or not model.Parent then return end
  base=base or model:GetPivot()
  local s=(strength or 1)*.35
  model:PivotTo(base*CFrame.new((math.random()-.5)*s,0,(math.random()-.5)*s)*CFrame.Angles(0,0,(math.random()-.5)*.06*(strength or 1)))
  task.delay(.06,function()if model.Parent then model:PivotTo(base)end end)
 end

 -- LABEL ------------------------------------------------------------------------------------
 function self.UpdateLabel(view,state)
  local corner=view.Corner;local core=view.Core;if not core then return end
  local g=view.Label
  if not g then
   g=Instance.new('BillboardGui');g.Name='OreLabel';g.Size=UDim2.fromOffset(230,58);g.StudsOffsetWorldSpace=Vector3.new(0,6.4,0)
   g.AlwaysOnTop=true;g.LightInfluence=0;g.MaxDistance=70;g:SetAttribute('NoTranslate',true)
   local name=Instance.new('TextLabel');name.Name='OreName';name.BackgroundTransparency=1;name.Size=UDim2.new(1,0,0,30)
   name.FontFace=ctx.U.FontFace;name.TextScaled=true;name.TextStrokeTransparency=0;name.TextStrokeColor3=ctx.U.Colors.edge;name.Parent=g
   local back=Instance.new('Frame');back.Name='Bar';back.Position=UDim2.new(.1,0,0,34);back.Size=UDim2.new(.8,0,0,14)
   back.BackgroundColor3=Color3.fromRGB(23,43,76);back.BorderSizePixel=0;back.Parent=g
   local c1=Instance.new('UICorner');c1.CornerRadius=UDim.new(1,0);c1.Parent=back
   local fill=Instance.new('Frame');fill.Name='Fill';fill.Size=UDim2.fromScale(1,1);fill.BorderSizePixel=0;fill.Parent=back
   local c2=Instance.new('UICorner');c2.CornerRadius=UDim.new(1,0);c2.Parent=fill
   g.Adornee=core;g.Parent=fx().Folder;view.Label=g
  end
  local def=oreDef(state and state.OreId or corner:GetAttribute('OreId'))
  local hp=state and state.OreHP or corner:GetAttribute('OreHP')or def.HP
  local max=math.max(1,state and state.OreMaxHP or corner:GetAttribute('OreMaxHP')or def.HP)
  local owned=(corner:GetAttribute('OwnerUserId')or 0)~=0
  local nameLabel=g:FindFirstChild('OreName')::TextLabel;local bar=g:FindFirstChild('Bar')::Frame;local fill=bar:FindFirstChild('Fill')::Frame
  nameLabel.Text=(def.Icon or'')..' '..Text.Name(def)
  nameLabel.TextColor3=oreColor(def):Lerp(Color3.new(1,1,1),.35)
  bar.Visible=owned
  fill.Size=UDim2.fromScale(math.clamp(hp/max,0,1),1)
  fill.BackgroundColor3=hp/max<.3 and Color3.fromRGB(247,73,112)or hp/max<.6 and Color3.fromRGB(249,180,35)or Color3.fromRGB(125,219,48)
 end

 -- PROMPTS / SIGNS --------------------------------------------------------------------------
 local function localizePrompt(p)
  if p.Name=='MiningOrePrompt'then p.ActionText=Text.Get('PROMPT_MINE');p.ObjectText=Text.Get('OBJ_ORE')
  elseif p.Name=='MiningPickaxeShopPrompt'then p.ActionText=Text.Get('PROMPT_SHOP');p.ObjectText=Text.Get('OBJ_SHOP')
  elseif p.Name=='MiningStrengthPrompt'then p.ActionText=Text.Get('PROMPT_TRAIN');p.ObjectText=Text.Get('OBJ_RACK')end
 end
 local function applyPromptAccess(view)
  local owner=isOwner(view.Corner)
  local busy=(ctx.Mine and ctx.Mine.Active)or(ctx.Gym and ctx.Gym.Active)
  for p in pairs(view.Prompts)do
   local want=owner and not busy
   if p.Enabled~=want then p.Enabled=want end
  end
 end
 self.RefreshPrompts=function()for _,view in pairs(self.Views)do applyPromptAccess(view)end end
 local function localizeSigns(corner)
  local board=corner:FindFirstChild('MiningPickaxeShop');local face=board and board:FindFirstChild('Face')
  local frame=face and face:FindFirstChildWhichIsA('Frame')
  if frame then
   face:SetAttribute('NoTranslate',true)
   if frame:FindFirstChild('Title')then frame.Title.Text=Text.Get('PICKAXES')end
   if frame:FindFirstChild('Sub')then frame.Sub.Text=Text.Get('TAP_SIGN')end
  end
  local gym=corner:FindFirstChild('StrengthSign');local gface=gym and gym:FindFirstChild('Face')
  local gframe=gface and gface:FindFirstChildWhichIsA('Frame')
  if gframe then
   gface:SetAttribute('NoTranslate',true)
   if gframe:FindFirstChild('Title')then gframe.Title.Text=Text.Get('STRENGTH')end
   if gframe:FindFirstChild('Sub')then gframe.Sub.Text=Text.L('Lift weights','Поднимай гири')end
  end
 end
 -- Locked weights on the owner's rack look dim.
 local function updateRack(view)
  local owned=isOwner(view.Corner)and(view.Corner:GetAttribute('WeightOwned')or 0)or 99
  for _,m in ipairs(view.Corner:GetChildren())do
   local level=m:IsA('Model')and m:GetAttribute('WeightLevel')
   if level then
    local locked=level>owned
    for _,d in ipairs(m:GetDescendants())do
     if d:IsA('BasePart')then
      if d:GetAttribute('BaseTransparency')==nil then d:SetAttribute('BaseTransparency',d.Transparency)end
      d.LocalTransparencyModifier=locked and .65 or 0
     end
    end
   end
  end
 end

 local KIND={MiningOrePrompt='Ore',MiningOreClick='Ore',MiningPickaxeShopPrompt='Shop',MiningPickaxeShopClick='Shop',
  MiningStrengthPrompt='Gym',MiningStrengthClick='Gym'}
 local attach -- defined below
 -- Prompts are resolved from the prompt itself, so E works even for pieces that streamed in
 -- after the corner was attached.
 game:GetService('ProximityPromptService').PromptTriggered:Connect(function(prompt)
  local kind=KIND[prompt.Name];if not kind or not prompt:IsA('ProximityPrompt')then return end
  local corner=prompt:FindFirstAncestor('MiningCorner');if not corner then return end
  if not self.Views[corner]then attach(corner)end
  self.Trigger(kind,corner)
 end)
 local function trigger(kind,corner)
  if not isOwner(corner)then if ctx.Hud then ctx.Hud.Toast(Text.Get('NOT_YOURS'),ctx.U.Colors.red)end;return end
  if kind=='Ore'and ctx.Mine then ctx.Mine.Enter(corner)
  elseif kind=='Shop'and ctx.Shop then ctx.Shop.Open(corner)
  elseif kind=='Gym'and ctx.Gym then ctx.Gym.Enter(corner)end
 end
 self.Trigger=trigger

 -- VIEWS --------------------------------------------------------------------------------------
 local function onHit(view)
  local corner=view.Corner
  local serial=corner:GetAttribute('HitSerial')or 0
  local previous=view.HitSerial or 0
  view.HitSerial=serial
  if serial<=previous then return end
  -- A big jump is a profile load / yard hand-over, not a swing.
  if serial-previous>3 or(corner:GetAttribute('OwnerUserId')or 0)==0 then return end
  -- The owner's own session draws its hits itself (instantly, without network delay).
  if isOwner(corner)and ctx.Mine and ctx.Mine.Active then return end
  if ctx.Anim then ctx.Anim.RemoteHit(corner)end
  local cam=workspace.CurrentCamera
  if not cam or not view.Core or(cam.CFrame.Position-view.Core.Position).Magnitude>90 then return end
  local att=self.HitPoint(view,cam.CFrame.Position)
  if att and view.Def then
   local tier=M.Pickaxes[corner:GetAttribute('PickaxeLevel')or 1]
   fx().Hit(att.WorldPosition,att:GetAttribute('Normal'),oreColor(view.Def),Enum.Material.Slate,tier and tier.FX or 1,corner:GetAttribute('HitQuality'),corner:GetAttribute('HitCrit'),true,tier and tier.Theme)
   self.Wobble(view,.6,att)
   Audio.Play(corner:GetAttribute('HitCrit')and'Crit'or'Hit',view.Core,tier and tier.FX or 1,tier and tier.Sound)
  end
 end
 local function onOre(view)
  local corner=view.Corner
  local serial=corner:GetAttribute('OreSerial')or 0
  local breaks=corner:GetAttribute('BreakSerial')or 0
  local broke=breaks-(view.BreakSerial or 0)==1 and(corner:GetAttribute('OwnerUserId')or 0)~=0
  view.BreakSerial=breaks
  if serial==view.Serial then
   if view.Pile then setScale(view,targetScale(view),.18)end
   self.UpdateLabel(view);return
  end
  if broke and view.Pile and view.Serial~=0 then
   if isOwner(corner)and ctx.Mine and ctx.Mine.Active then return end -- Mine plays it with full feedback
   self.PlayBreak(view,false)
  else
   buildPile(view,false)
  end
 end
 self.SyncOre=onOre
 -- Owner session: apply a fresh server state immediately (HP shrink + label).
 function self.ApplyState(view,state)
  if not view or not state then return end
  if view.Pile then setScale(view,targetScale(view,state),.16)end
  self.UpdateLabel(view,state)
 end

 -- StreamingEnabled: the MiningCorner model can reach this client long before its parts (players
 -- spawn ~260 studs away), and parts stream out and back in. So the view exists as soon as the
 -- model does, every piece is registered when it arrives, and the pile is built whenever the
 -- ore core is present (and removed when it streams out). Nothing here waits or gives up.
 local function syncCore(view)
  if self.Views[view.Corner]~=view then return end
  local core=view.Corner:FindFirstChild('MiningOreCore')
  local ready=core and core:IsA('BasePart')and core:FindFirstChild('OreRoot')~=nil
  if ready then
   if view.Core~=core then
    destroyPile(view);view.Core=core
    if view.Label then view.Label.Adornee=core end
   end
   if not view.Pile and not view.Breaking then buildPile(view,false)end
  elseif view.Core then
   view.Breaking=nil
   destroyPile(view);view.Core=nil
   if view.Label then view.Label.Adornee=nil end
   if ctx.Mine and ctx.Mine.Corner==view.Corner then ctx.Mine.Exit('streamed')end
  end
 end
 local function register(view,d)
  local corner=view.Corner
  if d:IsA('ProximityPrompt')and KIND[d.Name]then
   if view.Prompts[d]then return end
   view.Prompts[d]=d:GetPropertyChangedSignal('Enabled'):Connect(function()applyPromptAccess(view)end)
   localizePrompt(d)
  elseif d:IsA('ClickDetector')and KIND[d.Name]then
   if view.Clicks[d]then return end
   view.Clicks[d]=d.MouseClick:Connect(function(who)
    if who~=player then return end
    if (ctx.Mine and ctx.Mine.Active)or(ctx.Gym and ctx.Gym.Active)or ctx.MenuOpen()then return end
    trigger(KIND[d.Name],corner)
   end)
  end
 end
 local function unregister(view,d)
  local c=view.Prompts[d]or view.Clicks[d]
  if c then c:Disconnect();view.Prompts[d]=nil;view.Clicks[d]=nil end
 end
 -- Pieces arrive in bursts: refresh signs, rack, prompt access and the pile once per burst.
 local function queueRefresh(view)
  if view.RefreshQueued then return end
  view.RefreshQueued=true
  task.defer(function()
   view.RefreshQueued=false
   if self.Views[view.Corner]~=view then return end
   localizeSigns(view.Corner);updateRack(view);applyPromptAccess(view);syncCore(view)
  end)
 end

 function attach(corner)
  if self.Views[corner]or not corner:IsDescendantOf(workspace)then return self.Views[corner]end
  local view={Corner=corner,Core=nil,Prompts={},Clicks={},Connections={},HitPoints={},Serial=-1,
   HitSerial=corner:GetAttribute('HitSerial')or 0,BreakSerial=corner:GetAttribute('BreakSerial')or 0}
  self.Views[corner]=view
  for _,d in ipairs(corner:GetDescendants())do register(view,d)end
  -- Cue sounds parented to the core come and go on every hit; they are not corner pieces.
  local function piece(d)return not(d:IsA('Sound')or d:IsA('SoundEffect'))end
  table.insert(view.Connections,corner.DescendantAdded:Connect(function(d)if piece(d)then register(view,d);queueRefresh(view)end end))
  table.insert(view.Connections,corner.DescendantRemoving:Connect(function(d)if piece(d)then unregister(view,d);queueRefresh(view)end end))
  localizeSigns(corner);updateRack(view);applyPromptAccess(view);syncCore(view)
  -- One update changes several attributes; read them together once they have all arrived.
  local orePending=false
  local function queueOre()
   if orePending then return end
   orePending=true
   task.defer(function()orePending=false;if self.Views[corner]==view then onOre(view)end end)
  end
  for _,name in ipairs({'OreSerial','OreHP','OreId','BreakSerial'})do
   table.insert(view.Connections,corner:GetAttributeChangedSignal(name):Connect(queueOre))
  end
  local reps=corner:GetAttribute('TrainSerial')or 0
  table.insert(view.Connections,corner:GetAttributeChangedSignal('Training'):Connect(function()
   if ctx.Anim then ctx.Anim.RemoteTraining(corner,false)end
  end))
  table.insert(view.Connections,corner:GetAttributeChangedSignal('TrainSerial'):Connect(function()
   local now=corner:GetAttribute('TrainSerial')or 0
   local step=now-reps;reps=now
   if ctx.Anim and step>=1 and step<=3 then ctx.Anim.RemoteTraining(corner,true)end
  end))
  if ctx.Anim then ctx.Anim.RemoteTraining(corner,false)end
  table.insert(view.Connections,corner:GetAttributeChangedSignal('HitSerial'):Connect(function()onHit(view)end))
  -- Other miners hold their pickaxe ready while their session is open.
  table.insert(view.Connections,corner:GetAttributeChangedSignal('Active'):Connect(function()
   if ctx.Anim and ctx.Anim.RemoteActive then ctx.Anim.RemoteActive(corner)end
  end))
  table.insert(view.Connections,corner:GetAttributeChangedSignal('OwnerUserId'):Connect(function()
   applyPromptAccess(view);updateRack(view);if view.Core then buildPile(view,false)end
  end))
  table.insert(view.Connections,corner:GetAttributeChangedSignal('WeightOwned'):Connect(function()updateRack(view)end))
  table.insert(view.Connections,corner.AncestryChanged:Connect(function()
   if not corner:IsDescendantOf(workspace)then self.Detach(corner)end
  end))
  if ctx.Log then ctx.Log('corner attached: '..corner:GetFullName()..' (ore core streamed in: '..tostring(view.Core~=nil)..')')end
  return view
 end
 function self.Detach(corner)
  local view=self.Views[corner];if not view then return end
  self.Views[corner]=nil
  for _,c in ipairs(view.Connections)do c:Disconnect()end
  for _,c in pairs(view.Prompts)do c:Disconnect()end
  for _,c in pairs(view.Clicks)do c:Disconnect()end
  destroyPile(view)
  if view.Label then view.Label:Destroy()end
  if view.ScaleValue then view.ScaleValue:Destroy()end
  if ctx.Mine and ctx.Mine.Corner==corner then ctx.Mine.Exit()end
  if ctx.Gym and ctx.Gym.Corner==corner then ctx.Gym.Exit()end
 end
 function self.View(corner)return corner and self.Views[corner]end

 function self.Start()
  task.spawn(function()
   local map=workspace:WaitForChild('DOGROTS_District')
   local yards=map:WaitForChild('04_PlayerYards')
   local function watchYard(yard)
    local existing=yard:FindFirstChild('MiningCorner')
    if existing then task.spawn(attach,existing)end
    yard.ChildAdded:Connect(function(child)if child.Name=='MiningCorner'then task.spawn(attach,child)end end)
   end
   for _,yard in ipairs(yards:GetChildren())do watchYard(yard)end
   yards.ChildAdded:Connect(watchYard)
  end)
  -- Players who finished the tutorial before mining existed get one nudge per session.
  task.spawn(function()
   local hint=Instance.new('BillboardGui');hint.Name='MiningNewHint';hint.Size=UDim2.fromOffset(240,44);hint.StudsOffsetWorldSpace=Vector3.new(0,5.5,0)
   hint.AlwaysOnTop=true;hint.LightInfluence=0;hint.MaxDistance=160;hint.Enabled=false;hint:SetAttribute('NoTranslate',true)
   local label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.FontFace=ctx.U.FontFace
   label.TextScaled=true;label.TextColor3=ctx.U.Colors.gold;label.TextStrokeTransparency=0;label.TextStrokeColor3=ctx.U.Colors.edge
   label.Text=Text.Get('NEW_FEATURE');label.Parent=hint;hint.Parent=fx().Folder
   local toasted=false
   while true do
    task.wait(1)
    local fresh=(player:GetAttribute('MiningHitSerial')or 0)==0 and player:GetAttribute('TutorialActive')~=true
     and player:GetAttribute('EconomyReady')==true
    local corner=if fresh then self.MyCorner()else nil
    local sign=if corner then corner:FindFirstChild('MiningPickaxeShop')else nil
    hint.Adornee=sign;hint.Enabled=sign~=nil and not(ctx.Mine and ctx.Mine.Active)
    if sign and not toasted and ctx.Hud then toasted=true;task.delay(4,function()ctx.Hud.Toast(Text.Get('NEW_FEATURE_TOAST'),ctx.U.Colors.gold,6)end)end
    if (player:GetAttribute('MiningHitSerial')or 0)>0 and toasted then hint.Enabled=false end
   end
  end)
 end

 return self
end

return World
