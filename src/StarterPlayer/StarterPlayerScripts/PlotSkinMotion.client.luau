-- Cosmetic animation stays on the client and is distance capped. PlotMist emitters are not touched
-- here: WorldDetailQuality owns every district emitter (one owner, one particle budget).
local Scheduler=require(game:GetService('ReplicatedStorage'):WaitForChild('Perf'):WaitForChild('Scheduler'))
local yards=workspace:WaitForChild('DOGROTS_District'):WaitForChild('04_PlayerYards')
local active={}
local function register(p)
 if p:IsA('BasePart')and p:GetAttribute('PlotFloat')then active[p]={Base=p.CFrame,Phase=p.Position.X*.17+p.Position.Z*.13}end
end
for _,p in ipairs(yards:GetDescendants())do register(p)end
yards.DescendantAdded:Connect(function(p)if p:IsA('BasePart')then task.defer(function()if p.Parent then register(p)end end)end end)
Scheduler.Every(30,'PlotSkinMotion',function()
 local camera=workspace.CurrentCamera;if not camera then return end
 local now=os.clock()
 for p,data in pairs(active)do
  if not p:IsDescendantOf(yards)then active[p]=nil
  elseif(camera.CFrame.Position-data.Base.Position).Magnitude<230 then p.CFrame=data.Base+Vector3.new(0,math.sin(now*.75+data.Phase)*.38,0)end
 end
end)
