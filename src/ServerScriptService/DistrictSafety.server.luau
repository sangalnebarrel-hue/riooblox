-- Recover characters after an accidental fall off a floating island.
-- The yard mines hang below the island (levels down to Y -160, docs/MINE.md): a character inside
-- a mine chamber or shaft (MineLayout.Find) is where it should be and is never recovered.
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local spawnPoint=workspace:WaitForChild("DistrictSpawn")
local MineLayout=require(RS:WaitForChild("Mine"):WaitForChild("MineLayout"))
local yards=workspace:WaitForChild("DOGROTS_District"):WaitForChild("04_PlayerYards")
local cooldown={}
Players.PlayerRemoving:Connect(function(p) cooldown[p]=nil end)
local function inMine(position)
 local ok,inside=pcall(function()return MineLayout.Find(yards,position)~=nil end)
 return ok and inside==true
end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<0.25 then return end;elapsed=0
 for _,player in Players:GetPlayers() do
  local char=player.Character
  local root=char and char:FindFirstChild("HumanoidRootPart")
  local hum=char and char:FindFirstChildOfClass("Humanoid")
  if root and hum and hum.Health>0 and root.Position.Y < -85 and os.clock()-(cooldown[player] or -10)>3 and not inMine(root.Position) then
   cooldown[player]=os.clock()
   local destination=player.RespawnLocation or spawnPoint
   char:PivotTo(destination.CFrame+Vector3.new(0,5,0))
   root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
  end
 end
end)
print("DOGROTS_FALL_RECOVERY_READY")
