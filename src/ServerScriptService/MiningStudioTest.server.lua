-- Studio-only Active Mining test controls (press F8 in Play Solo). Live servers return at once
-- and expose nothing. Cheats only touch the local memory profile of an unpublished preview
-- (player attribute PreviewData) unless Config.Mining.StudioCheats is explicitly true.
local Run=game:GetService('RunService')
if not Run:IsStudio()then return end
local RS=game:GetService('ReplicatedStorage')
local Config=require(RS:WaitForChild('DogEconomy'):WaitForChild('Config'))
local MiningRules=require(RS:WaitForChild('Mining'):WaitForChild('MiningRules'))
local Runtime=require(script.Parent:WaitForChild('Economy'):WaitForChild('Runtime'))
local M=Config.Mining

local remote=Instance.new('RemoteFunction');remote.Name='MiningStudioControl';remote.Parent=RS:WaitForChild('Mining')
local last={}
remote.OnServerInvoke=function(player,action)
 if not Run:IsStudio()then return false,'Studio only'end
 if player:GetAttribute('PreviewData')~=true and M.StudioCheats~=true then
  return false,'Disabled: this Studio session saves to the real DataStore (set Mining.StudioCheats=true to allow)'
 end
 if type(action)~='string'then return false,'Invalid action'end
 if os.clock()-(last[player]or-10)<.3 then return false,'Please wait a moment'end
 last[player]=os.clock()
 if not Runtime.Ready(player)then return false,'Profile loading'end
 local key='p:'..player.UserId
 local ok,result=Runtime.Tx:Run({key},function(v)
  local p=v[key];if not p then error('No profile',0)end
  local m=MiningRules.Normalize(p.Mining,M);p.Mining=m
  if action=='cash'then p.Cash=math.min(Config.MaxCash,p.Cash+1000000);return'+1M Coins'
  elseif action=='cash100'then p.Cash=math.min(Config.MaxCash,p.Cash+100000000);return'+100M Coins'
  elseif action=='strength'then m.Strength=math.min(M.MaxStrength,m.Strength+100);return'Strength '..m.Strength
  elseif action=='all'then
   m.PickaxeOwned=#M.Pickaxes;m.PickaxeLevel=#M.Pickaxes;m.WeightOwned=#M.Weights;m.WeightLevel=#M.Weights;m.Strength=M.MaxStrength
   return'All pickaxes, weights and max Strength'
  elseif action=='rare'then
   local ore,index=MiningRules.OreById(M,'VoidCrystal')
   m.OreId=ore.Id;m.OreIndex=index;m.OreMaxHP=ore.HP;m.OreHP=ore.HP;m.OreValue=ore.ValueMax;m.OreEarned=0;m.OreSerial+=1
   return'Next ore: Void Crystal'
  elseif action=='layers'then
   for i=1,#Config.Layers do p.UnlockedLayers[tostring(i)]=true end
   return'All dig layers unlocked (ore value x'..M.LayerValue[#M.LayerValue]..' from the next ore)'
  elseif action=='reset'then p.Mining=MiningRules.New(M);return'Mining progress reset'
  end
  error('Unknown action',0)
 end)
 Runtime.Refresh(player)
 return ok,result
end
