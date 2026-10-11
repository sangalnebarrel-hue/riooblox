-- Remote calls and local mining state for the Active Mining client.
local Http=game:GetService('HttpService')
local Net={}

function Net.new(ctx)
 local self:any={Targets={},LastResult=nil}
 local M,Text,Rules=ctx.M,ctx.Text,ctx.Rules
 local player=ctx.Player

 -- Names inside server messages: BROKE names an ore, BOUGHT/EQUIPPED a pickaxe, WEIGHT_* a weight.
 local function lookup(id,key)
  if key=='BROKE'then return(Rules.OreById(M,id))end
  if key=='BOUGHT'or key=='EQUIPPED'then for _,p in ipairs(M.Pickaxes)do if p.Id==id then return p end end end
  if key=='WEIGHT_BOUGHT'or key=='WEIGHT_EQUIPPED'then for _,w in ipairs(M.Weights)do if w.Id==id then return w end end end
  return nil
 end
 self.Lookup=lookup

 local function attr(name,default)
  local v=player:GetAttribute(name);if v==nil then return default end;return v
 end
 self.Attr=attr

 -- Current mining state from the attributes Runtime projects onto the player.
 function self.State()
  return {
   Strength=attr('MiningStrength',0),PickaxeLevel=attr('MiningPickaxe',0),PickaxeOwned=attr('MiningPickaxeOwned',0),
   WeightLevel=attr('MiningWeight',0),WeightOwned=attr('MiningWeightOwned',0),OreId=attr('MiningOreId','Limestone'),
   OreHP=attr('MiningOreHP',1),OreMaxHP=attr('MiningOreMaxHP',1),OreValue=attr('MiningOreValue',0),OreSerial=attr('MiningOreSerial',1),
   Hits=attr('MiningHitSerial',0),OresBroken=attr('MiningOresBroken',0),Combo=attr('MiningCombo',0),TrainingReps=attr('MiningTrainingReps',0),
   Layer=attr('MiningLayer',1),
  }
 end
 function self.Cash()
  local stats=player:FindFirstChild('leaderstats');local coins=stats and stats:FindFirstChild('Coins')
  return coins and coins.Value or 0
 end

 function self.SetTargets(list)
  local now=workspace:GetServerTimeNow()
  local out={}
  for _,t in ipairs(list)do
   if type(t)=='table'and tonumber(t.Id)and tonumber(t.SpawnAt)and tonumber(t.Window)then
    table.insert(out,{Id=t.Id,Slot=t.Slot or 1,SpawnAt=t.SpawnAt,Window=t.Window,LocalSpawn=os.clock()+(t.SpawnAt-now)})
   end
  end
  self.Targets=out
  if self.OnTargets then task.spawn(self.OnTargets,out)end
 end

 -- Returns ok, display message, raw result.
 function self.Invoke(action,args)
  local id=Http:GenerateGUID(false):gsub('-','')
  local transport,ok,result=pcall(function()return ctx.Remote:InvokeServer(action,args or{},id)end)
  if not transport then return false,Text.Get('CONNECTION'),nil end
  if not ok then return false,Text.Message(tostring(result),lookup),result end
  if type(result)=='table'then
   self.LastResult=result
   if type(result.MiningTargets)=='table'then self.SetTargets(result.MiningTargets)end
   local patch=result.StatePatch
   self.LastState=(type(patch)=='table'and type(patch.Mining)=='table')and patch.Mining or result.MiningState
  end
  local message=type(result)=='table'and result.Message or result
  return true,Text.Message(message,lookup),result
 end

 return self
end

return Net
