-- Light and particle budget of the district: the one owner of every Light and ParticleEmitter under
-- DOGROTS_District (PlotMist included). Budgets come from ReplicatedStorage.Perf.Quality (the tier
-- in use; reduced motion uses the Low budget). A source with FXManaged=true on itself or an ancestor
-- belongs to the feature that built it and is left alone, as are LuckyVisual and MuseumLight.
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
 local tier=Quality.Reduced()and'Low'or Quality.Tier()
 local lightRadius,lightCount=Quality.Budget('LightRadius',tier),Quality.Budget('Lights',tier)
 local emitterRadius,emitterRate=Quality.Budget('EmitterRadius',tier),Quality.Budget('EmitterRate',tier)
 local event=RS.WorldEvents.State
 local blackout=event:GetAttribute('State')=='ACTIVE'and event:GetAttribute('EventId')=='BLACKOUT'
 local candidates={}
 for p in pairs(lights)do
  if not p:IsDescendantOf(map)then lights[p]=nil;continue end
  local pos=position(p);local d=pos and(pos-camera.CFrame.Position).Magnitude or math.huge
  p.Enabled=false
  local navigation=p.Parent and (p.Parent.Name=='WarmLens'or p.Parent.Name=='PortalEnergy')
  local king=p:GetAttribute('ServerKingLight')==true
  if d<(king and 260 or lightRadius)and (not blackout or navigation)then table.insert(candidates,{p,d,king})end
 end
 table.sort(candidates,function(a,b)if a[3]~=b[3]then return a[3]end;return a[2]<b[2]end)
 for i=1,math.min(#candidates,lightCount)do candidates[i][1].Enabled=true end
 local remaining=Quality.Budget('Particles',tier)
 for p,rate in pairs(emitters)do
  if not p:IsDescendantOf(map)then emitters[p]=nil;continue end
  local pos=position(p);local near=pos and(pos-camera.CFrame.Position).Magnitude<emitterRadius
  local amount=near and math.min(rate,emitterRate,remaining)or 0
  p.Rate=amount;p.Enabled=amount>0;remaining-=amount
 end
end)
