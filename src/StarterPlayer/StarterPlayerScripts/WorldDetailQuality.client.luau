-- Light and particle budget of the district: the one owner of every Light and ParticleEmitter under
-- DOGROTS_District (PlotMist included). Budgets come from ReplicatedStorage.Perf.Quality (the tier
-- in use; reduced motion uses the Low budget) minus what other systems claimed (Quality.Claim):
-- the nearest lights and emitters get it first. A source with FXManaged=true on itself or an
-- ancestor belongs to the feature that built it (which claims its share) and is left alone, as are
-- LuckyVisual and MuseumLight. Properties are written only when they change.
local map=workspace:WaitForChild('DOGROTS_District');local RS=game:GetService('ReplicatedStorage')
local Perf=RS:WaitForChild('Perf');local Quality=require(Perf:WaitForChild('Quality'));local Scheduler=require(Perf:WaitForChild('Scheduler'))
local lights,emitters={},{}
local function exempt(p)
 if p:GetAttribute('MuseumLight')or p:GetAttribute('FXManaged')then return true end
 local o=p.Parent
 while o and o~=map do if o:GetAttribute('LuckyVisual')or o:GetAttribute('FXManaged')then return true end;o=o.Parent end
 return false
end
local function position(p)
 local o=p.Parent
 if o and o:IsA('Attachment')then return o.WorldPosition end
 return o and o:IsA('BasePart')and o.Position or nil
end
local function add(p)
 local light=p:IsA('PointLight')or p:IsA('SpotLight')or p:IsA('SurfaceLight')
 if not(light or p:IsA('ParticleEmitter'))or exempt(p)then return end
 if light then lights[p]=true;p.Shadows=false else emitters[p]=p.Rate end
end
for _,o in map:GetDescendants()do add(o)end
map.DescendantAdded:Connect(add)
Scheduler.Every(2.5,'WorldDetailQuality',function()
 local camera=workspace.CurrentCamera;if not camera then return end
 local origin=camera.CFrame.Position
 local tier=Quality.Reduced()and'Low'or Quality.Tier()
 -- Lights and Particles are shared budgets: what FXManaged features claimed is not WDQ's to spend.
 local lightRadius,lightCount=Quality.Budget('LightRadius',tier),Quality.Available('Lights',tier)
 local emitterRadius,emitterRate=Quality.Budget('EmitterRadius',tier),Quality.Budget('EmitterRate',tier)
 local event=RS.WorldEvents.State
 local blackout=event:GetAttribute('State')=='ACTIVE'and event:GetAttribute('EventId')=='BLACKOUT'
 local candidates,lit={},{}
 for p in pairs(lights)do
  if not p:IsDescendantOf(map)then lights[p]=nil;continue end
  local pos=position(p);local d=pos and(pos-origin).Magnitude or math.huge
  local navigation=p.Parent and (p.Parent.Name=='WarmLens'or p.Parent.Name=='PortalEnergy')
  local king=p:GetAttribute('ServerKingLight')==true
  if d<(king and 260 or lightRadius)and (not blackout or navigation)then table.insert(candidates,{p,d,king})end
 end
 table.sort(candidates,function(a,b)if a[3]~=b[3]then return a[3]end;return a[2]<b[2]end)
 for i=1,math.min(#candidates,lightCount)do lit[candidates[i][1]]=true end
 for p in pairs(lights)do local on=lit[p]==true;if p.Enabled~=on then p.Enabled=on end end
 -- Ambient emitters (PlotMist included) get the particle budget nearest first.
 local near,rates={},{}
 for p in pairs(emitters)do
  if not p:IsDescendantOf(map)then emitters[p]=nil;continue end
  local pos=position(p);local d=pos and(pos-origin).Magnitude
  if d and d<emitterRadius then table.insert(near,{p,d})end
 end
 table.sort(near,function(a,b)return a[2]<b[2]end)
 local remaining=Quality.Available('Particles',tier)
 for _,e in ipairs(near)do local amount=math.min(emitters[e[1]],emitterRate,remaining);rates[e[1]]=amount;remaining-=amount end
 for p in pairs(emitters)do
  local amount=rates[p]or 0
  if p.Rate~=amount then p.Rate=amount end
  if p.Enabled~=(amount>0)then p.Enabled=amount>0 end
 end
end)
