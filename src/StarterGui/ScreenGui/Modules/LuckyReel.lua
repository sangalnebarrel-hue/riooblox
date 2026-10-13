-- LuckyReel: the CS:GO-style roulette shown when one of your Lucky Blocks opens.
-- Presentation only. The server has already rolled and saved the dog; the reel always lands on
-- result.Dog.DogId and never guesses. Fillers follow RewardService.Pool's maths (each rarity's
-- share of RewardPools[tier] split evenly between its droppable dogs), so rarer dogs fly past
-- less often. Timing contract (see LuckyShow.Timing):
--   * the overlay pops in at max(now, LuckyChargeAt + Charge), i.e. exactly at the pad's burst;
--   * Secret results carry RevealAt (server time of the yard cinematic): the reel lands by
--     RevealAt-1.2, shows WATCH YOUR YARD and closes at RevealAt-0.2.
-- The top level only defines functions so the pure maths can be tested outside Roblox.
local R={}

R.CardW=124;R.CardH=172;R.Pitch=136
R.ArtW=112;R.ArtH=104
R.StartIndex=5;R.TailCards=6
R.Lead=.32;R.Settle=.3;R.MinSpin=.9
R.MaxDistinct=10
R.MaxWidth=900;R.MaxWidthLow=640;R.MinWidth=440
R.WindowH=210;R.StageH=340
R.Banner={'NICE!','RARE!','EPIC!','LEGENDARY!','MYTHIC!!','SECRET!!!'}

-------------------------------------------------------------------------------------------------
-- Pure maths (no Roblox services). Tested by work/lucky/reel/smoke.luau.
-------------------------------------------------------------------------------------------------

-- RewardService.Pool on the client: rows {Id,Name,Rank,Weight,Chance} sorted by Id.
-- `has(id,def)` can drop dogs whose model is missing on this client.
function R.BuildPool(tier,pools,defs,has)
 local weights=pools[tier]
 if type(weights)~='table'then return{},0 end
 local groups={}
 for id,def in pairs(defs)do
  if type(def)=='table'and def.CanDropFromLuckyBlock==true and not def.OG and type(def.Rank)=='number'
   and(not has or has(id,def))then
   groups[def.Rank]=groups[def.Rank]or{};table.insert(groups[def.Rank],def)
  end
 end
 local pool,total={},0
 for rank,members in pairs(groups)do
  local groupWeight=weights[rank]or 0
  if groupWeight>0 then
   local weight=groupWeight/#members
   for _,def in ipairs(members)do table.insert(pool,{Id=def.Id,Name=def.DisplayName,Rank=rank,Weight=weight})end
   total+=groupWeight
  end
 end
 table.sort(pool,function(a,b)return a.Id<b.Id end)
 for _,row in ipairs(pool)do row.Chance=total>0 and row.Weight/total or 0 end
 return pool,total
end

function R.Pick(rows,total,rand)
 local n=rand()*total
 for _,row in ipairs(rows)do n-=row.Weight;if n<0 then return row end end
 return rows[#rows]
end

-- Up to `limit` distinct filler dogs, drawn by weight without replacement (one cached model each).
function R.Plan(pool,total,rand,limit)
 local left=table.clone(pool);local set,sum,remaining={},0,total
 while #set<limit and #left>0 and remaining>1e-9 do
  local n=rand()*remaining;local pick=#left
  for i,row in ipairs(left)do n-=row.Weight;if n<0 then pick=i;break end end
  local row=table.remove(left,pick)
  remaining-=row.Weight;sum+=row.Weight;table.insert(set,row)
 end
 return set,sum
end

-- The strip: entries[1..count] of dog ids, the server's dog at `winner`, and (when the pool has a
-- rarer dog than the winner) a rarer "near miss" right after it.
function R.Strip(o)
 local entries={};local rand=o.Rand
 local function filler()
  if #o.Set==0 then return o.WinnerId end
  return R.Pick(o.Set,o.SetTotal,rand).Id
 end
 for i=1,o.Count do entries[i]=filler()end
 local nearMiss=nil;local best=o.WinnerRank
 for _,row in ipairs(o.Pool)do if row.Rank>best then best=row.Rank end end
 if best>o.WinnerRank then
  local top={}
  for _,row in ipairs(o.Pool)do if row.Rank==best then table.insert(top,row)end end
  nearMiss=top[math.clamp(math.floor(rand()*#top)+1,1,#top)].Id
 end
 entries[o.Winner]=o.WinnerId
 for _,i in ipairs({o.Winner-1,o.Winner+1})do
  if i>=1 and i<=o.Count then
   for _=1,6 do if entries[i]~=o.WinnerId then break end;entries[i]=filler()end
  end
 end
 if nearMiss and o.Winner+1<=o.Count then entries[o.Winner+1]=nearMiss end
 return entries,nearMiss
end

-- Where the strip starts and stops. Offsets are in logical pixels: card i's centre sits under the
-- marker when the strip offset s == i*Pitch. The final offset keeps the marker inside the winner
-- card (|jitter|+overshoot <= 46% of a card), leaning toward the near miss when there is one.
function R.Layout(o)
 local P,CW=R.Pitch,R.CardW
 local rand=o.Rand;local exponent=o.Exponent or 3.2
 local jitter
 if o.NearMiss then jitter=(.18+rand()*.18)*CW else jitter=(rand()*2-1)*.36*CW end
 local overshoot=0
 if not o.Reduced and o.D>0 then overshoot=math.max(0,math.min(.1*CW,.46*CW-jitter))end
 local spinCards
 if o.D>0 then
  local speed=o.Low and 2800 or 3600
  spinCards=math.clamp(math.floor(speed*o.D/(exponent*P)+.5),6,56)
 else spinCards=2 end
 local winner=R.StartIndex+spinCards
 local finish=winner*P+jitter
 return{Winner=winner,Count=winner+R.TailCards,Jitter=jitter,Overshoot=overshoot,Exponent=exponent,
  StartS=o.D>0 and R.StartIndex*P or finish,EndS=finish,D=o.D,Settle=o.D>0 and(o.Settle or R.Settle)or 0}
end

-- Strip offset at time t (seconds since the strip started moving): ease-out 1-(1-u)^exponent
-- slightly past the stop, then a short smoothstep settle back onto it.
function R.Offset(L,t)
 if L.D<=0 or t>=L.D+L.Settle then return L.EndS end
 if t<=0 then return L.StartS end
 if t<L.D then
  local u=t/L.D
  return L.StartS+(L.EndS+L.Overshoot-L.StartS)*(1-(1-u)^L.Exponent)
 end
 local v=(t-L.D)/math.max(L.Settle,1e-3)
 return L.EndS+L.Overshoot*(1-v*v*(3-2*v))
end

-- Visible strip indices for offset s and window width w (logical px).
function R.Visible(s,w,count)
 local half=w/2+R.CardW/2
 return math.max(1,math.ceil((s-half)/R.Pitch)),math.min(count,math.floor((s+half)/R.Pitch))
end
function R.PoolSize(maxWidth)return math.floor((maxWidth+R.CardW)/R.Pitch)+2 end

-- When the overlay starts and how long the strip may spin (all server time).
-- Mode: 'spin' (normal), 'static' (Secret that arrived too late to spin: land at once),
-- 'none' (the Secret cinematic is about to start: no overlay at all).
function R.Timeline(o)
 local now=o.Now;local start=now
 if type(o.ChargeAt)=='number'and now-o.ChargeAt<=10 then
  start=math.clamp(o.ChargeAt+o.Charge,now,now+o.Charge+.1)
 end
 local lead,settle=o.Lead or R.Lead,o.Settle or R.Settle
 local d=o.Desired;local mode='spin';local closeAt=nil
 if type(o.RevealAt)=='number'then
  closeAt=o.RevealAt-.2
  local room=(o.RevealAt-1.2)-(start+lead+settle)
  if room<d then d=room end
  if d<R.MinSpin then d=0;mode='static'end
  if closeAt-start<.6 then mode='none'end
 end
 return{Start=start,Wait=start-now,D=d,LandAt=start+lead+d+(d>0 and settle or 0),CloseAt=closeAt,Mode=mode}
end

-------------------------------------------------------------------------------------------------
-- Runtime (client)
-------------------------------------------------------------------------------------------------

local deps=nil
local function D()
 if deps then return deps end
 -- Bounded waits: Present runs inside the RewardPresentation handler and must never hang it.
 local RS=game:GetService('ReplicatedStorage')
 local function need(parent,name)
  local child=parent and parent:WaitForChild(name,8)
  if not child then error('LuckyReel: missing '..name)end
  return child
 end
 local lucky=need(RS,'Lucky')
 local loaded={RS=RS,Players=game:GetService('Players'),Run=game:GetService('RunService'),Tween=game:GetService('TweenService'),
  Content=game:GetService('ContentProvider'),UIS=game:GetService('UserInputService'),
  Show=require(need(lucky,'LuckyShow')),Audio=require(need(lucky,'LuckyAudio')),
  Config=require(need(RS,'LuckyBlockConfig')),
  Defs=require(need(need(RS,'DogEconomy'),'DogDefinitions')),
  Rig=require(need(RS,'DogRig')),Profile=require(need(RS,'DogRenderProfile'))}
 deps=loaded
 return loaded
end

local WHITE=Color3.new(1,1,1)
local NAVY=Color3.fromRGB(23,43,76)
local GOLD=Color3.fromRGB(249,180,35)
local VOID=Color3.fromRGB(150,72,255)
local CYAN=Color3.fromRGB(70,255,226)

-- Card faces per rank: light top -> rarity bottom. Mythic is gold->crimson, Secret void->pink.
local function cardColors(Show,rank)
 if rank==5 then return Color3.fromRGB(255,214,120),Show.UI[5]end
 if rank==6 then return Color3.fromRGB(46,18,82),Show.UI[6]end
 local c=Show.UI[rank]or Show.UI[1];return c:Lerp(WHITE,.62),c
end

-- Prepared bind-pose dog models, one per dog id, shared by every reel (bounded LRU).
local templates={}
local listeners={}
local function framing(prepared)
 local center=(prepared.Low+prepared.High)/2;local size=prepared.Size
 local distance=math.max(size.Y,size.X/math.max(.2,R.ArtW/R.ArtH))/(2*math.tan(math.rad(16)))*1.12+size.Z*.5
 return CFrame.lookAt(center+Vector3.new(.22,.18,-1).Unit*math.max(distance,2),center)
end
local function evict(keep)
 local n=0;for _ in pairs(templates)do n+=1 end
 if n<=28 then return end
 local list={}
 for id,t in pairs(templates)do if t.State~='loading'and not keep[id]then table.insert(list,{Id=id,Used=t.Used or 0})end end
 table.sort(list,function(a,b)return a.Used<b.Used end)
 for i=1,math.min(#list,n-24)do
  local t=templates[list[i].Id];templates[list[i].Id]=nil
  if t and t.Model then t.Model:Destroy()end
 end
end
local function ensure(id)
 local t=templates[id]
 if t then t.Used=os.clock();return t end
 local d=D();local def=d.Defs[id];local models=d.RS:FindFirstChild('MenuModels')
 local source=def and models and models:FindFirstChild(def.VisualAsset or id)
 if not source then return nil end -- not cached: MenuModels replicates asynchronously
 local entry={State='loading',Used=os.clock()};templates[id]=entry
 task.spawn(function()
  pcall(function()d.Content:PreloadAsync({source})end)
  local ok,model,camera=pcall(function()
   local copy=source:Clone()
   for _,item in ipairs(copy:GetDescendants())do
    if item:IsA('LuaSourceContainer')or item:IsA('ProximityPrompt')or item:IsA('Sound')or item:IsA('BillboardGui')
     or item:IsA('SurfaceGui')or item:IsA('ParticleEmitter')or item:IsA('Light')or item:IsA('Beam')or item:IsA('Trail')then item:Destroy()end
   end
   local prepared=d.Rig.Prepare(copy,Vector3.new(7,5,8))
   if not prepared then copy:Destroy();return nil,nil end
   return copy,framing(prepared)
  end)
  if templates[id]~=entry then if ok and model then model:Destroy()end;return end
  if ok and model then entry.State='ready';entry.Model=model;entry.Camera=camera else entry.State='failed'end
  for fn in pairs(listeners)do task.spawn(fn,id)end
 end)
 return entry
end

-- Filler plans, made as early as possible (during the pad charge) so models are warm.
local plans={}
local function poolFor(tier)
 local d=D();local models=d.RS:FindFirstChild('MenuModels')
 local canonical=d.Config.Canonical and d.Config.Canonical(tier)or tier
 local pool,total=R.BuildPool(canonical,d.Config.RewardPools,d.Defs,function(_,def)
  return models~=nil and models:FindFirstChild(def.VisualAsset or def.Id)~=nil
 end)
 -- MenuModels not replicated yet: keep the real odds and show placeholder cards.
 if #pool==0 then pool,total=R.BuildPool(canonical,d.Config.RewardPools,d.Defs)end
 return pool,total
end
local function planFor(uid,tier)
 local p=uid and plans[uid]
 if p and p.Tier==tier then return p end
 local pool,total=poolFor(tier)
 local rng=Random.new()
 local set,sum=R.Plan(pool,total,function()return rng:NextNumber()end,R.MaxDistinct)
 p={Tier=tier,Pool=pool,Total=total,Set=set,SetTotal=sum,At=os.clock()}
 if uid then
  plans[uid]=p
  local keys={};for key in pairs(plans)do table.insert(keys,key)end
  if #keys>4 then
   table.sort(keys,function(a,b)return plans[a].At<plans[b].At end)
   for i=1,#keys-4 do plans[keys[i]]=nil end
  end
 end
 local keep={};for _,row in ipairs(set)do keep[row.Id]=true end
 evict(keep)
 for _,row in ipairs(set)do ensure(row.Id)end
 return p
end
local function tierOf(uid)
 local player=D().Players.LocalPlayer
 if player and player:GetAttribute('LuckyBlockOpeningUid')==uid then
  local tier=player:GetAttribute('LuckyBlockOpeningTier');if type(tier)=='string'then return tier end
 end
 local folder=workspace:FindFirstChild('OwnedLuckyBlocks')
 if folder then
  for _,model in ipairs(folder:GetChildren())do
   if model:GetAttribute('OwnedBlockUid')==uid then return model:GetAttribute('LuckyBlockTier')end
  end
 end
 return nil
end

local warmed=false
-- Start preparing filler models as soon as an open is predicted (E on the pad or the OPEN
-- button) or the pad charge starts. Safe to call many times.
function R.Warm()
 if warmed then return end
 local player=D().Players.LocalPlayer
 if not player then return end
 warmed=true
 local function prepare(attribute)
  local uid=player:GetAttribute(attribute)
  if type(uid)~='string'or uid==''then return end
  task.spawn(function()
   local ok,err=pcall(function()
    local tier=tierOf(uid)
    if type(tier)=='string'then planFor(uid,tier)end
   end)
   if not ok then warn('[LuckyReel] warm: '..tostring(err))end
  end)
 end
 player:GetAttributeChangedSignal('LuckyBlockOpeningUid'):Connect(function()prepare('LuckyBlockOpeningUid')end)
 player:GetAttributeChangedSignal('LuckyChargeUid'):Connect(function()prepare('LuckyChargeUid')end)
end

-------------------------------------------------------------------------------------------------
-- One presentation
-------------------------------------------------------------------------------------------------

local function build(ctx,result,overlay,o,cleanups)
 local d=D();local U=ctx.U;local Show=d.Show;local Audio=d.Audio;local gui=ctx.Gui
 local dog=result.Dog;local def=d.Defs[dog.DogId]
 local rank=o.Rank;local low,reduced=o.Low,o.Reduced
 local tierRank=Show.Rank(result.Tier)
 local tierColor=Show.World[tierRank];local rarityColor=Show.UI[rank];local worldColor=Show.World[rank]
 local secretMode=o.Timeline.CloseAt~=nil
 local dogName=dog.DisplayName or(def and def.DisplayName)or tostring(dog.DogId)
 local P,CW,CH=R.Pitch,R.CardW,R.CardH
 local maxWidth=low and R.MaxWidthLow or R.MaxWidth
 local touch=d.UIS.TouchEnabled
 local rng=Random.new()
 local function rand()return rng:NextNumber()end
 local alive=true
 local connections={}
 local function connect(signal,fn)local c=signal:Connect(fn);table.insert(connections,c);return c end
 table.insert(cleanups,function()for _,c in ipairs(connections)do c:Disconnect()end end)
 local function tween(obj,props,time,style,direction)
  local tw=d.Tween:Create(obj,TweenInfo.new(time,style or Enum.EasingStyle.Quad,direction or Enum.EasingDirection.Out),props);tw:Play();return tw
 end

 -- Strip data -----------------------------------------------------------------------------
 local plan=planFor(result.BlockUid,result.Tier)
 local dExp=rank>=5 and 3.7 or 3.2
 local hasNearMiss=false
 for _,row in ipairs(plan.Pool)do if row.Rank>rank then hasNearMiss=true;break end end
 local L=R.Layout({D=o.Timeline.D,Low=low,Reduced=reduced,NearMiss=hasNearMiss,Rand=rand,Exponent=dExp})
 local entries,nearMiss=R.Strip({Set=plan.Set,SetTotal=plan.SetTotal,Pool=plan.Pool,WinnerId=dog.DogId,WinnerRank=rank,
  Count=L.Count,Winner=L.Winner,Rand=rand})
 ensure(dog.DogId);if nearMiss then ensure(nearMiss)end

 -- Overlay layers ---------------------------------------------------------------------------
 local dim=U.New('Frame',{Name='Dim',Size=UDim2.fromScale(1,1),BackgroundColor3=WHITE,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1},overlay)
 U.New('UIGradient',{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(12,16,40),tierColor:Lerp(Color3.new(),.72)),
  Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,.15)})},dim)
 tween(dim,{BackgroundTransparency=.42},.25)
 local flash=U.New('Frame',{Name='Flash',Size=UDim2.fromScale(1,1),BackgroundColor3=WHITE,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=60},overlay)
 local function doFlash(color,strength,time)
  if low or reduced then return end
  flash.BackgroundColor3=color;flash.BackgroundTransparency=1-strength
  tween(flash,{BackgroundTransparency=1},time or .4)
 end

 local stage=U.New('Frame',{Name='LuckyReelStage',AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,ZIndex=5,
  Size=UDim2.fromOffset(maxWidth,R.StageH)},overlay)
 local stageScale=U.New('UIScale',{},stage)
 local width=maxWidth;local stageBase=UDim2.fromScale(.5,.5)
 local function layout()
  local left,top,w,h=U.SafeArea(gui)
  local s=math.min(1,(h-12)/R.StageH,(w-12)/R.MinWidth)
  width=math.clamp((w-12)/math.max(s,.05),R.MinWidth,maxWidth)
  stage.Size=UDim2.fromOffset(width,R.StageH)
  stageBase=UDim2.fromOffset(left+w/2,top+h/2);stage.Position=stageBase
  stageScale.Scale=s
 end
 layout();connect(gui:GetPropertyChangedSignal('AbsoluteSize'),layout)

 local winY=56;local winCY=winY+R.WindowH/2
 -- Rays behind the window (land flourish) live under it.
 local backFX=U.New('Frame',{Name='BackFX',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=1},stage)
 local window=U.New('Frame',{Name='ReelWindow',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,winCY),
  Size=UDim2.new(0,0,0,R.WindowH),BackgroundColor3=Color3.fromRGB(26,34,70),BorderSizePixel=0,ClipsDescendants=true,ZIndex=3},stage)
 U.New('UICorner',{CornerRadius=UDim.new(0,18)},window)
 local windowStroke=U.New('UIStroke',{Color=NAVY,Thickness=4},window)
 local glow=U.New('Frame',{Name='TierGlow',Size=UDim2.fromScale(1,1),BackgroundColor3=tierColor,BorderSizePixel=0,ZIndex=1},window)
 U.New('UIGradient',{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.62),NumberSequenceKeypoint.new(1,1)})},glow)
 local stripLayer=U.New('Frame',{Name='Strip',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=2},window)
 for side=0,1 do
  local fade=U.New('Frame',{Name=side==0 and'FadeLeft'or'FadeRight',AnchorPoint=Vector2.new(side,0),Position=UDim2.fromScale(side,0),
   Size=UDim2.new(0,96,1,0),BackgroundColor3=Color3.fromRGB(26,34,70),BorderSizePixel=0,ZIndex=9},window)
  U.New('UIGradient',{Transparency=NumberSequence.new(side==0 and 0 or 1,side==0 and 1 or 0)},fade)
 end
 local shine=U.New('Frame',{Name='Shine',Size=UDim2.new(1,0,0,40),BackgroundColor3=WHITE,BackgroundTransparency=.88,BorderSizePixel=0,ZIndex=9},window)
 U.New('UIGradient',{Rotation=90,Transparency=NumberSequence.new(0,1)},shine)

 -- Centre marker: gold needle with diamonds above and below the window.
 local marker=U.New('Frame',{Name='Marker',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,winCY),Size=UDim2.fromOffset(6,R.WindowH+10),
  BackgroundColor3=GOLD,BorderSizePixel=0,ZIndex=12,Visible=false},stage)
 U.New('UICorner',{CornerRadius=UDim.new(0,3)},marker)
 local markerStroke=U.New('UIStroke',{Color=NAVY,Thickness=2},marker)
 for _,y in ipairs({winY-4,winY+R.WindowH+4})do
  local gem=U.New('Frame',{Name='MarkerGem',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,y),Size=UDim2.fromOffset(22,22),Rotation=45,
   BackgroundColor3=GOLD,BorderSizePixel=0,ZIndex=13},stage)
  U.New('UICorner',{CornerRadius=UDim.new(0,4)},gem);U.New('UIStroke',{Color=NAVY,Thickness=3},gem)
  gem.Visible=false
  connect(marker:GetPropertyChangedSignal('Visible'),function()gem.Visible=marker.Visible end)
 end

 local title=U.Center(stage,result.Tier:upper()..' LUCKY BLOCK',0,0,10,48,34,WHITE,true)
 title.Name='ReelTitle';title.AnchorPoint=Vector2.new(.5,0);title.Position=UDim2.new(.5,0,0,0);title.Size=UDim2.new(1,0,0,48);title.ZIndex=14
 title.TextWrapped=false;title.TextScaled=true
 U.New('UITextSizeConstraint',{MaxTextSize=34,MinTextSize=14},title)
 U.New('UIStroke',{Color=NAVY,Thickness=3,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},title)
 U.New('UIGradient',{Rotation=90,Color=ColorSequence.new(WHITE,tierColor:Lerp(WHITE,.25))},title)
 title.TextTransparency=1;tween(title,{TextTransparency=0},.25)

 local fx=U.New('Frame',{Name='FrontFX',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=20},stage)

 local state='intro'
 local skip
 local function setSkip(visible)if skip then skip.Visible=visible end end

 -- Particles (UI frames) ----------------------------------------------------------------------
 local particles={};local maxParticles=low and 40 or 110
 local function particle(parent,x,y,vx,vy,color,size,life,gravity,round)
  if #particles>=maxParticles then return end
  local obj=U.New('Frame',{Name='Spark',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(x,y),
   Size=UDim2.fromOffset(size,round and size or size*.55),BackgroundColor3=color,BorderSizePixel=0,ZIndex=21},parent)
  if round then U.New('UICorner',{CornerRadius=UDim.new(.5,0)},obj)else U.New('UIStroke',{Color=NAVY,Thickness=1.5,Transparency=.2},obj)end
  table.insert(particles,{Obj=obj,X=x,Y=y,VX=vx,VY=vy,R=rand()*360,VR=(rand()-.5)*720,Life=life,Age=0,G=gravity})
 end
 local function updateParticles(dt)
  for i=#particles,1,-1 do
   local p=particles[i];p.Age+=dt
   if p.Age>=p.Life or not p.Obj.Parent then p.Obj:Destroy();table.remove(particles,i)
   else
    p.VY+=p.G*dt;local drag=1-math.min(.9,1.6*dt);p.VX*=drag;if p.G==0 then p.VY*=drag end
    p.X+=p.VX*dt;p.Y+=p.VY*dt
    p.Obj.Position=UDim2.fromOffset(p.X,p.Y);p.Obj.Rotation=p.R+p.VR*p.Age
    local f=p.Age/p.Life;p.Obj.BackgroundTransparency=f>.6 and(f-.6)/.4 or 0
   end
  end
 end
 local confettiColors={WHITE,GOLD,worldColor,Show.Accent[rank],Color3.fromRGB(125,219,48),Color3.fromRGB(38,164,243)}
 local function burst(parent,x,y,count,speed,colors,gravity)
  count=math.max(1,math.floor(count*(low and .4 or 1)))
  for _=1,count do
   local a=rand()*math.pi*2;local v=speed*(.45+rand()*.75)
   particle(parent,x,y,math.cos(a)*v,math.sin(a)*v-speed*.35,colors[math.floor(rand()*#colors)+1],6+rand()*8,.8+rand()*.7,gravity,rand()<.3)
  end
 end
 local function ring(parent,x,y,color,from,to,time,thickness)
  local obj=U.New('Frame',{Name='Ring',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(0,x,0,y),Size=UDim2.fromOffset(from,from),
   BackgroundTransparency=1,ZIndex=19},parent)
  U.New('UICorner',{CornerRadius=UDim.new(.5,0)},obj)
  local stroke=U.New('UIStroke',{Color=color,Thickness=thickness or 6},obj)
  tween(obj,{Size=UDim2.fromOffset(to,to)},time,Enum.EasingStyle.Quart)
  tween(stroke,{Transparency=1,Thickness=1},time)
  task.delay(time+.05,function()obj:Destroy()end)
 end
 -- Sunburst: full-length bars through a centre; rotated every frame by the stepper.
 local rayBars={}
 local function rays(parent,position,length,count,color,transparency,spin,z)
  local holder=U.New('Frame',{Name='Rays',Position=position,Size=UDim2.fromOffset(0,0),BackgroundTransparency=1,ZIndex=z or 1},parent)
  for i=1,count do
   local bar=U.New('Frame',{Name='Ray',AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(length*.11,length),BackgroundColor3=color,
    BorderSizePixel=0,ZIndex=z or 1,Rotation=(i-1)*180/count},holder)
   U.New('UIGradient',{Rotation=90,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),
    NumberSequenceKeypoint.new(.5,transparency),NumberSequenceKeypoint.new(1,1)})},bar)
   table.insert(rayBars,{Obj=bar,Base=(i-1)*180/count,Spin=spin})
  end
  return holder
 end

 -- Cards ------------------------------------------------------------------------------------
 local cards={};local free={}
 local poolSize=R.PoolSize(maxWidth)
 local function release(card)
  if card.Clone then
   -- A clone destroyed with the stage (after the reveal) has a locked Parent: never pool it.
   local clone=card.Clone;card.Clone=nil
   if pcall(function()clone.Parent=nil end)then
    free[card.Id]=free[card.Id]or{};table.insert(free[card.Id],clone)
   end
  end
 end
 local function attach(card)
  if card.Clone or not card.Id then return end
  local t=templates[card.Id]
  if t and t.State=='ready'and t.Model then
   t.Used=os.clock()
   local list=free[card.Id];local clone=list and table.remove(list)or t.Model:Clone()
   if clone then
    clone.Parent=card.Art;card.Clone=clone;card.Cam.CFrame=t.Camera
    card.Mystery.Visible=false;return
   end
  end
  card.Mystery.Visible=true
 end
 for k=1,poolSize do
  local frame=U.New('Frame',{Name='ReelCard',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(CW,CH),
   BackgroundColor3=WHITE,BorderSizePixel=0,Visible=false,ZIndex=3},stripLayer)
  U.New('UICorner',{CornerRadius=UDim.new(0,14)},frame)
  local stroke=U.New('UIStroke',{Color=NAVY,Thickness=3},frame)
  local grad=U.New('UIGradient',{Rotation=90},frame)
  local scale=U.New('UIScale',{},frame)
  local halo=U.New('Frame',{Name='Halo',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(CW/2,70),Size=UDim2.fromOffset(92,92),
   BackgroundColor3=WHITE,BackgroundTransparency=.5,BorderSizePixel=0,ZIndex=3},frame)
  U.New('UICorner',{CornerRadius=UDim.new(.5,0)},halo)
  local art=U.New('ViewportFrame',{Name='Art',Position=UDim2.fromOffset((CW-R.ArtW)/2,18),Size=UDim2.fromOffset(R.ArtW,R.ArtH),
   BackgroundTransparency=1,ZIndex=4},frame)
  d.Profile.ApplyViewport(art)
  local cam=U.New('Camera',{FieldOfView=32},art);art.CurrentCamera=cam
  local mystery=U.New('TextLabel',{Name='Mystery',Text='?',Position=UDim2.fromOffset(0,18),Size=UDim2.fromOffset(CW,R.ArtH),BackgroundTransparency=1,
   FontFace=U.FontFace,TextSize=64,TextColor3=WHITE,TextTransparency=.15,ZIndex=5},frame)
  U.New('UIStroke',{Color=NAVY,Thickness=3,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},mystery)
  local stripe=U.New('Frame',{Name='RarityStripe',Position=UDim2.fromOffset(14,7),Size=UDim2.fromOffset(CW-28,7),BorderSizePixel=0,ZIndex=5},frame)
  U.New('UICorner',{CornerRadius=UDim.new(0,4)},stripe);U.New('UIStroke',{Color=NAVY,Thickness=1.5},stripe)
  local name=U.New('TextLabel',{Name='DogName',Text='',Position=UDim2.fromOffset(6,124),Size=UDim2.fromOffset(CW-12,42),BackgroundTransparency=1,
   FontFace=U.FontFace,TextScaled=true,TextWrapped=true,TextColor3=WHITE,ZIndex=6},frame)
  U.New('UITextSizeConstraint',{MaxTextSize=17,MinTextSize=9},name)
  U.New('UIStroke',{Color=NAVY,Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},name)
  local shade=U.New('Frame',{Name='Shade',Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(8,10,26),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=8},frame)
  U.New('UICorner',{CornerRadius=UDim.new(0,14)},shade)
  cards[k]={Frame=frame,Stroke=stroke,Grad=grad,Scale=scale,Halo=halo,Art=art,Cam=cam,Mystery=mystery,Stripe=stripe,Name=name,Shade=shade}
 end
 local function assign(card,i)
  card.Index=i
  local id=entries[i]
  if card.Id==id then return end
  release(card);card.Id=id
  local info=d.Defs[id];local r=Show.Rank(info and info.Rank or 1)
  local top,bottom=cardColors(Show,r)
  card.Grad.Color=ColorSequence.new(top,bottom)
  card.Stripe.BackgroundColor3=Show.World[r]
  card.Halo.BackgroundColor3=r==6 and VOID or WHITE
  card.Halo.BackgroundTransparency=r==6 and .35 or .5
  card.Name.Text=info and info.DisplayName or tostring(id)
  attach(card)
 end
 local function onReady(id)
  if not alive then return end
  for _,card in ipairs(cards)do if card.Id==id and not card.Clone then attach(card)end end
 end
 listeners[onReady]=true
 table.insert(cleanups,function()listeners[onReady]=nil end)

 local landed=false
 local used={}
 local function render(s)
  local lo,hi=R.Visible(s,width,L.Count)
  table.clear(used)
  for i=lo,hi do
   local k=i%poolSize+1;local card=cards[k]
   if card.Index~=i then assign(card,i)end
   used[k]=true
   local x=i*P-s
   card.Frame.Position=UDim2.new(.5,x,.5,0)
   if not card.Frame.Visible then card.Frame.Visible=true end
   if not landed then
    local near=math.max(0,1-math.abs(x)/P);card.Scale.Scale=1+.07*near*near
   end
  end
  for k,card in ipairs(cards)do if not used[k]and card.Frame.Visible then card.Frame.Visible=false;card.Index=nil end end
 end
 local function cardAt(i)local card=cards[i%poolSize+1];return card.Index==i and card or nil end

 -- Intro: the tier block pops, cracks and shatters while the window opens ----------------------
 local blockView=nil;local shattered=false
 if ctx.Block then
  local ok,view=pcall(ctx.Block,stage,width/2-105,winCY-105,210,210)
  if ok and view then
   blockView=view;view.AnchorPoint=Vector2.new(.5,.5);view.Position=UDim2.new(.5,0,0,winCY);view.ZIndex=15
   U.New('UIScale',{Scale=.6},view)
  end
 end
 if not o.Charged then Audio.Play('Burst',nil,tierRank)end
 Audio.Play('Whoosh',nil,1.5)
 doFlash(WHITE,.75,.35)

 local winnerLabel,youGot,banner
 local function shardBurst()
  local cx=width/2
  for i=1,(low and 6 or 14)do
   local a=(i/(low and 6 or 14))*math.pi*2+rand()*.4;local v=320+rand()*360
   particle(fx,cx,winCY,math.cos(a)*v,math.sin(a)*v-160,i%3==0 and Show.Accent[tierRank]or tierColor,12+rand()*14,.55+rand()*.35,900,false)
  end
  ring(fx,cx,winCY,tierColor,60,low and 380 or 560,.45,8)
 end

 -- Landing flourish -----------------------------------------------------------------------------
 local nextAt,nextAction=nil,nil
 local closeLocal=nil
 local t0=os.clock()
 if secretMode then closeLocal=t0+(o.Timeline.CloseAt-o.Timeline.Start)end
 local shakeUntil,shakeAmp=0,0
 local flicker=0
 local markerPulse=0

 local reveal,watch
 local function land(quiet)
  if landed or state=='revealed'or state=='watch'then return end
  landed=true;state='landed'
  render(L.EndS)
  setSkip(false)
  local winner=cardAt(L.Winner)
  for _,card in ipairs(cards)do
   if card~=winner and card.Frame.Visible then tween(card.Shade,{BackgroundTransparency=.5},.3);tween(card.Scale,{Scale=.94},.3)end
  end
  if winner then
   winner.Frame.ZIndex=6
   winner.Stroke.Color=rank>=3 and worldColor or GOLD;winner.Stroke.Thickness=5
   winner.Scale.Scale=1.02;tween(winner.Scale,{Scale=1.14},reduced and .15 or .45,reduced and Enum.EasingStyle.Quad or Enum.EasingStyle.Back)
  end
  local cx=width/2
  if not quiet then
   Audio.Play('Land',nil,rank)
   if rank>=6 then Audio.Play('Void',nil)end
   ring(fx,cx,winCY,worldColor,CW,low and 420 or 700,.6,rank>=4 and 10 or 6)
   if rank>=4 and not low then task.delay(.12,function()if alive then ring(fx,cx,winCY,Show.Accent[rank],CW,520,.55,5)end end)end
   burst(fx,cx,winCY,8+rank*7,420+rank*60,confettiColors,700)
   if rank>=3 then doFlash(rank>=5 and worldColor or WHITE,rank>=5 and .7 or .5,.45)end
   if rank>=5 then task.delay(.18,function()if alive then doFlash(WHITE,.45,.3)end end)end
   if rank>=4 and not reduced then shakeUntil=os.clock()+(rank>=5 and .55 or .35);shakeAmp=rank>=5 and 9 or 5 end
  end
  if rank>=2 then
   local holder=rays(backFX,UDim2.new(.5,0,0,winCY),low and 520 or 760,low and 5 or 9,worldColor,rank>=4 and .25 or .45,rank>=5 and 26 or 14,1)
   for _,bar in ipairs(holder:GetChildren())do if bar:IsA('GuiObject')then bar.BackgroundTransparency=1;tween(bar,{BackgroundTransparency=0},.3)end end
  end
  if rank>=6 and not quiet then
   -- Void tear: a black rift opens across the needle, sucks sparks in and flickers the reel.
   local tear=U.New('Frame',{Name='VoidTear',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,winCY),Size=UDim2.fromOffset(6,0),Rotation=7,
    BackgroundColor3=Color3.fromRGB(4,0,12),BorderSizePixel=0,ZIndex=18},stage)
   U.New('UICorner',{CornerRadius=UDim.new(.5,0)},tear)
   U.New('UIStroke',{Color=VOID,Thickness=5},tear)
   local inner=U.New('Frame',{Name='Rim',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(1,10,1,10),
    BackgroundTransparency=1,ZIndex=18},tear)
   U.New('UICorner',{CornerRadius=UDim.new(.5,0)},inner);U.New('UIStroke',{Color=CYAN,Thickness=2,Transparency=.2},inner)
   tween(tear,{Size=UDim2.fromOffset(low and 40 or 64,R.WindowH+80)},.28,Enum.EasingStyle.Back)
   task.delay(.75,function()if tear.Parent then tween(tear,{Size=UDim2.fromOffset(4,R.WindowH+120)},.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In)end end)
   task.delay(1.1,function()if tear.Parent then tear:Destroy()end end)
   for i=1,(low and 8 or 18)do
    local a=i/(low and 8 or 18)*math.pi*2;local r0=180+rand()*60
    particle(fx,cx+math.cos(a)*r0,winCY+math.sin(a)*r0,-math.cos(a)*r0*2.6,-math.sin(a)*r0*2.6,i%2==0 and VOID or CYAN,7,.38,0,true)
   end
   task.delay(.4,function()if alive then ring(fx,cx,winCY,VOID,30,low and 460 or 760,.7,12);burst(fx,cx,winCY,30,620,{VOID,CYAN,WHITE,Show.UI[6]},500)end end)
   flicker=reduced and 0 or .55
  end
  -- Near miss: the rarer card that almost stopped under the needle.
  local miss=nearMiss and cardAt(L.Winner+1)
  if miss and not quiet then
   local tag=U.Center(fx,'SO CLOSE!',0,0,CW+20,26,18,WHITE,true)
   tag.Name='NearMissTag';tag.ZIndex=23;tag.Rotation=-6;tag.AnchorPoint=Vector2.new(.5,.5)
   tag.Position=UDim2.new(.5,(L.Winner+1)*P-L.EndS,0,winCY-CH/2-2)
   U.New('UIStroke',{Color=NAVY,Thickness=2.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},tag)
   tag.TextTransparency=1;tween(tag,{TextTransparency=0},.25)
   if not reduced then miss.Frame.Rotation=5;tween(miss.Frame,{Rotation=0},.6,Enum.EasingStyle.Elastic)end
  end
  -- Rarity banner over the title and the dog's name under the reel.
  tween(title,{TextTransparency=1},.15)
  banner=U.Center(stage,R.Banner[rank],0,0,10,70,58,WHITE,true)
  banner.Name='RarityBanner';banner.AnchorPoint=Vector2.new(.5,.5);banner.Position=UDim2.new(.5,0,0,22);banner.Size=UDim2.new(1,0,0,74)
  banner.ZIndex=22;banner.TextWrapped=false;banner.TextScaled=true;banner.Rotation=reduced and 0 or-3
  U.New('UITextSizeConstraint',{MaxTextSize=rank>=5 and 64 or 54,MinTextSize=18},banner)
  U.New('UIStroke',{Color=NAVY,Thickness=4,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},banner)
  local top=rank==6 and CYAN or WHITE
  U.New('UIGradient',{Rotation=90,Color=ColorSequence.new({ColorSequenceKeypoint.new(0,top),ColorSequenceKeypoint.new(.45,rarityColor:Lerp(WHITE,.2)),ColorSequenceKeypoint.new(1,worldColor)})},banner)
  local bannerScale=U.New('UIScale',{Scale=reduced and 1 or .2},banner)
  if not reduced then tween(bannerScale,{Scale=1},.45,Enum.EasingStyle.Back)end
  youGot=U.Center(stage,'YOU GOT',0,0,10,22,18,Color3.fromRGB(215,226,245),true)
  youGot.Name='YouGot';youGot.AnchorPoint=Vector2.new(.5,0);youGot.Position=UDim2.new(.5,0,0,winY+R.WindowH+12);youGot.Size=UDim2.new(1,0,0,22);youGot.ZIndex=14
  winnerLabel=U.Center(stage,dogName,0,0,10,44,32,WHITE,true)
  winnerLabel.Name='WinnerName';winnerLabel.AnchorPoint=Vector2.new(.5,0);winnerLabel.Position=UDim2.new(.5,0,0,winY+R.WindowH+32);winnerLabel.Size=UDim2.new(1,-20,0,44)
  winnerLabel.ZIndex=14;winnerLabel.TextWrapped=false;winnerLabel.TextScaled=true
  U.New('UITextSizeConstraint',{MaxTextSize=32,MinTextSize=14},winnerLabel)
  U.New('UIStroke',{Color=NAVY,Thickness=3,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},winnerLabel)
  U.New('UIGradient',{Rotation=90,Color=ColorSequence.new(WHITE,rarityColor:Lerp(WHITE,.15))},winnerLabel)
  -- What happens next.
  local hold=quiet and .35 or(Show.Timing.Land+(rank>=5 and .5 or 0))*(low and .85 or 1)
  if secretMode then
   nextAt=math.min(os.clock()+hold,closeLocal and(closeLocal-.9)or math.huge);nextAction=function()watch()end
  else nextAt=os.clock()+hold;nextAction=function()reveal()end end
 end

 -- Secret: hand the stage to the yard cinematic --------------------------------------------------
 watch=function()
  if state=='watch'or state=='revealed'then return end
  if not landed then land(true)end
  state='watch'
  for _,card in ipairs(cards)do tween(card.Shade,{BackgroundTransparency=.3},.3)end
  if youGot then youGot.Visible=false end
  if winnerLabel then tween(winnerLabel,{Position=UDim2.new(.5,0,0,winY-2)},.3)end
  if banner then tween(banner,{TextTransparency=1},.2)end
  local big=U.Center(stage,'WATCH YOUR YARD!',0,0,10,60,46,WHITE,true)
  big.Name='WatchYourYard';big.AnchorPoint=Vector2.new(.5,.5);big.Position=UDim2.new(.5,0,0,winCY+6);big.Size=UDim2.new(1,-40,0,64)
  big.ZIndex=22;big.TextWrapped=false;big.TextScaled=true
  U.New('UITextSizeConstraint',{MaxTextSize=50,MinTextSize=18},big)
  U.New('UIStroke',{Color=NAVY,Thickness=4,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},big)
  U.New('UIGradient',{Rotation=90,Color=ColorSequence.new(CYAN,Show.UI[6])},big)
  local sub=U.Center(stage,'Your Secret dog is arriving in your yard!',0,0,10,26,20,WHITE,true)
  sub.Name='WatchHint';sub.AnchorPoint=Vector2.new(.5,0);sub.Position=UDim2.new(.5,0,0,winCY+44);sub.Size=UDim2.new(1,-40,0,26);sub.ZIndex=22
  U.New('UIStroke',{Color=NAVY,Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},sub)
  local s=U.New('UIScale',{Scale=reduced and 1 or .4},big)
  if not reduced then tween(s,{Scale=1},.4,Enum.EasingStyle.Back)end
  Audio.Play('Reveal',nil,6)
  setSkip(true)
  if skip then local caption=skip:FindFirstChild('Caption');if caption then caption.Text='SKIP'end end
  nextAt=closeLocal or(os.clock()+1.5);nextAction=function()overlay:Destroy()end
 end

 -- Reveal card (the classic card, upgraded): rays, rarity badge, bounce-in, confetti ------------
 reveal=function()
  if state=='revealed'then return end
  -- The strip stops for good: no late landing, ticks or flash over the reveal card.
  state='revealed';landed=true;nextAt=nil;nextAction=nil
  for _,card in ipairs(cards)do card.Clone=nil end -- destroyed with the stage below
  if stage.Parent then stage:Destroy()end
  local box=U.Modal(overlay,'RewardCard','REWARD SAVED',580,480);box.ZIndex=10
  local heading=box:FindFirstChild('Label');if heading then heading.Name='RewardStatus'end
  local fit=box:FindFirstChildWhichIsA('UIScale')
  if fit and not reduced then local target=fit.Scale;fit.Scale=target*.7;tween(fit,{Scale=target},.38,Enum.EasingStyle.Back)end
  local variant=tostring(dog.Variant or'Normal')
  local titleText=U.Center(box,dogName..' · '..variant,20,66,540,44,26,rarityColor,true)
  titleText.Name='RewardTitle'
  U.New('UIStroke',{Color=NAVY,Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual},titleText)
  local panel=U.New('Frame',{Name='RevealGlow',Position=UDim2.fromOffset(30,110),Size=UDim2.fromOffset(520,215),BackgroundColor3=WHITE,
   BorderSizePixel=0,ClipsDescendants=true,ZIndex=3},box)
  U.New('UICorner',{CornerRadius=UDim.new(0,16)},panel);U.New('UIStroke',{Color=NAVY,Thickness=3},panel)
  local top,bottom=cardColors(Show,rank)
  U.New('UIGradient',{Rotation=90,Color=ColorSequence.new(top:Lerp(WHITE,rank==6 and 0 or .45),bottom:Lerp(WHITE,rank==6 and 0 or .25))},panel)
  rays(panel,UDim2.fromOffset(260,108),620,low and 5 or 9,rank==6 and VOID or WHITE,rank==6 and .3 or .35,18,4)
  local art=U.New('Frame',{Name='OpeningArt',Position=UDim2.fromOffset(0,0),Size=UDim2.fromOffset(520,215),BackgroundTransparency=1,ZIndex=6},panel)
  local pop=U.New('UIScale',{Scale=reduced and 1 or .25},art)
  if ctx.Preview then pcall(ctx.Preview,art,0,0,520,215)end
  if not reduced then tween(pop,{Scale=1},.55,Enum.EasingStyle.Back)end
  local rarity=(def and def.Rarity or dog.Rarity or Show.Rarities[rank]or'Common'):upper()
  local badge=U.Badge(box,rarity,215,333,150,rarityColor);badge.Name='RarityBadge';badge.ZIndex=12
  for _,item in ipairs(badge:GetDescendants())do if item:IsA('GuiObject')then item.ZIndex=13 end end
  local saved=U.Center(box,'Saved to your collection',20,364,540,32,19,U.Colors.muted);saved.Name='SavedHint'
  U.Button(box,'Done','DONE',30,405,520,46,function()if state=='revealed'then overlay:Destroy()end end,U.Colors.green)
  local layer=U.New('Frame',{Name='Confetti',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=30},box)
  if rank>=2 then
   for _=1,math.floor((6+rank*6)*(low and .4 or 1))do
    particle(layer,30+rand()*520,40+rand()*30,(rand()-.5)*260,-120-rand()*220,confettiColors[math.floor(rand()*#confettiColors)+1],7+rand()*7,1.4+rand()*.8,520,rand()<.25)
   end
  end
  Audio.Play('Reveal',nil,rank)
 end

 -- Skip: straight to the reveal (or, for a Secret, to WATCH YOUR YARD / close) -------------------
 local function doSkip()
  if state=='revealed'then return end
  if state=='watch'then overlay:Destroy();return end
  if secretMode then watch()else reveal()end
 end
 skip=U.Button(stage,'Skip','SKIP',0,0,180,46,doSkip,GOLD)
 skip.AnchorPoint=Vector2.new(.5,0);skip.Position=UDim2.new(.5,0,0,winY+R.WindowH+24);skip.ZIndex=16

 -- ESC / death / another menu handing control back: finish instead of spinning under the HUD.
 connect(gui:GetAttributeChangedSignal('OpenMenu'),function()
  if gui:GetAttribute('OpenMenu')~='Reward'and state~='revealed'then
   task.defer(function()if alive and state~='revealed'then if secretMode then overlay:Destroy()else reveal()end end end)
  end
 end)

 -- Frame stepper ---------------------------------------------------------------------------------
 local lastIndex=math.floor((L.StartS+P/2)/P)
 local lastTick=0;local tickGap=touch and .1 or .05
 local ended=false
 local stepper
 local function step(dt)
  local now=os.clock();local t=now-t0
  -- intro
  if t<.6 then
   local open=math.clamp((t-.05)/.35,0,1)
   local e=reduced and open or(1+2.70158*(open-1)^3+1.70158*(open-1)^2)
   window.Size=UDim2.new(math.max(0,e),0,0,R.WindowH)
   if open>0 and not marker.Visible then marker.Visible=true end
   if blockView then
    local s=blockView:FindFirstChildWhichIsA('UIScale')
    if t<.12 then if s then s.Scale=.6+.55*(t/.12)end;blockView.Rotation=reduced and 0 or math.sin(t*90)*6
    else
     if not shattered then shattered=true;shardBurst();Audio.Play('Crack',nil)end
     local k=math.clamp((t-.12)/.25,0,1)
     if s then s.Scale=1.15+.45*k end;blockView.Rotation=0;blockView.ImageTransparency=k
     if k>=1 then blockView:Destroy();blockView=nil end
    end
   end
  elseif window.Size.X.Scale~=1 then window.Size=UDim2.new(1,0,0,R.WindowH)
  end
  if blockView and t>=.6 then blockView:Destroy();blockView=nil end
  -- strip
  if state=='intro'and t>=R.Lead then state='spin'end
  if not landed and state~='revealed'then
   local tm=math.max(0,t-R.Lead)
   local s=R.Offset(L,tm)
   render(s)
   local idx=math.floor((s+P/2)/P)
   if idx~=lastIndex then
    lastIndex=idx;markerPulse=1
    if now-lastTick>=tickGap then
     lastTick=now
     local u=L.D>0 and math.clamp(tm/L.D,0,1)or 1
     Audio.Play('Tick',nil,.95+.8*u*u)
    end
   end
   if tm>=L.D+L.Settle then land(false)end
  end
  -- marker pulse
  if markerPulse>0 then
   markerPulse=math.max(0,markerPulse-dt*7)
   marker.Size=UDim2.fromOffset(6+4*markerPulse,R.WindowH+10)
   markerStroke.Color=NAVY:Lerp(WHITE,markerPulse*.6)
  end
  -- shake (UI only; never the camera)
  if now<shakeUntil then
   local k=(shakeUntil-now)/.5
   stage.Position=stageBase+UDim2.fromOffset((rand()-.5)*2*shakeAmp*k,(rand()-.5)*2*shakeAmp*k)
  elseif stage.Parent and stage.Position~=stageBase then stage.Position=stageBase end
  -- void flicker
  if flicker>0 then
   flicker=math.max(0,flicker-dt)
   local on=math.floor(flicker*16)%2==0
   window.BackgroundColor3=on and Color3.fromRGB(4,0,12)or Color3.fromRGB(46,18,82)
   windowStroke.Color=on and VOID or NAVY
   if flicker<=0 then window.BackgroundColor3=Color3.fromRGB(26,34,70);windowStroke.Color=VOID end
  end
  for _,bar in ipairs(rayBars)do if bar.Obj.Parent then bar.Obj.Rotation=bar.Base+t*bar.Spin*(reduced and .3 or 1)end end
  updateParticles(dt)
  if nextAt and now>=nextAt then local action=nextAction;nextAt=nil;nextAction=nil;if action then action()end end
  if closeLocal and state~='revealed'and now>=closeLocal then overlay:Destroy()end
 end
 local function stop()
  if ended then return end
  ended=true;alive=false
  for _,c in ipairs(connections)do c:Disconnect()end
  table.clear(connections)
  for _,fn in ipairs(cleanups)do pcall(fn)end
  for _,list in pairs(free)do for _,clone in ipairs(list)do clone:Destroy()end end
  table.clear(free)
  for _,p in ipairs(particles)do p.Obj:Destroy()end
  table.clear(particles)
 end
 table.insert(cleanups,function()if stepper then stepper:Disconnect()end end)
 stepper=d.Run.RenderStepped:Connect(function(dt)
  if not overlay.Parent then stop();return end
  local ok,err=pcall(step,dt)
  if not ok then
   warn('[LuckyReel] '..tostring(err))
   if state=='revealed'then stepper:Disconnect();return end
   state='revealed' -- no 'saved' toast when the classic card takes over
   stop()
   if o.OnError then o.OnError()end
  end
 end)
 overlay.Destroying:Connect(function()
  if state~='revealed'and state~='watch'and not secretMode and ctx.Navigation and ctx.Navigation.Notify then
   pcall(ctx.Navigation.Notify,dogName..' · Saved to your collection')
  end
  stop()
 end)
 render(L.StartS)
 return{Skip=doSkip,Close=function()overlay:Destroy()end,Stop=stop}
end

local claimed={}
-- Present a Lucky Block result. ctx = {U, Gui, Navigation, Preview(parent,x,y,w,h),
-- Block(parent,x,y,w,h) -> ViewportFrame, Classic(overlay) -> old reveal flow}.
-- Returns {Reveal, Close} like RewardScreens.Present, or nil when the receipt was already shown.
function R.Present(ctx,result)
 local d=D();local Show=d.Show;local nav=ctx.Navigation
 local receipt=result.Receipt or result.BlockUid
 if receipt and(claimed[receipt]or(type(nav.SeenRewards)=='table'and nav.SeenRewards[receipt]))then return nil end
 R.Warm()
 local dog=result.Dog;local def=d.Defs[dog.DogId]
 local rank=Show.Rank(def and def.Rank or dog.Rarity or 1)
 local low,reduced=Show.Low(),Show.ReducedMotion()
 local player=d.Players.LocalPlayer
 local chargeAt=player and player:GetAttribute('LuckyChargeAt')
 local charged=player~=nil and player:GetAttribute('LuckyChargeUid')==result.BlockUid and type(chargeAt)=='number'
 local desired=(low and Show.Timing.ReelLow or Show.Timing.Reel)+(rank>=5 and(low and .5 or .8)or 0)
 local timeline=R.Timeline({Now=workspace:GetServerTimeNow(),ChargeAt=charged and chargeAt or nil,Charge=Show.Timing.Charge,
  RevealAt=type(result.RevealAt)=='number'and result.RevealAt or nil,Desired=desired})
 if receipt then claimed[receipt]=true end
 if timeline.Mode=='none'then
  -- Too late to spin: the yard cinematic is the reveal. Leave a toast so the drop is never silent.
  local name=dog.DisplayName or(def and def.DisplayName)or tostring(dog.DogId)
  if nav.Notify then pcall(nav.Notify,name..' · Saved to your collection')end
  return nil
 end
 local session=nil;local skipEarly,cancelled=false,false
 local handle={}
 function handle.Reveal()if session then(session.Skip or session.Reveal)()else skipEarly=true end end
 function handle.Close()cancelled=true;if session then session.Close()end end
 local function begin()
  if cancelled then return end
  local epoch=nav.BeginReward(receipt);if not epoch then return end
  local gui=ctx.Gui
  local old=gui:FindFirstChild('RewardReveal');if old then old:Destroy()end
  local overlay=ctx.U.New('Frame',{Name='RewardReveal',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=100,Active=true},gui)
  overlay.Destroying:Connect(function()task.defer(function()nav.EndReward(epoch)end)end)
  local cleanups={}
  local function fallback()
   for _,fn in ipairs(cleanups)do pcall(fn)end
   if not overlay.Parent then return end
   local ok,err=pcall(function()overlay:ClearAllChildren();session=ctx.Classic(overlay)end)
   if not ok then warn('[LuckyReel] classic reveal failed: '..tostring(err));overlay:Destroy()end
  end
  local ok,res=pcall(build,ctx,result,overlay,{Rank=rank,Low=low,Reduced=reduced,Timeline=timeline,Charged=charged,OnError=fallback},cleanups)
  if ok then
   session=res
   if skipEarly then res.Skip()end
  else
   warn('[LuckyReel] '..tostring(res))
   fallback()
  end
 end
 if timeline.Wait>.03 then task.delay(timeline.Wait,begin)else begin()end
 return handle
end

return R
