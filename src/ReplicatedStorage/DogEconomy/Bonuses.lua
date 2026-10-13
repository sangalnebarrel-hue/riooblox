-- One stat pipeline for every new bonus source (upgrade tree, player accessories, dog artifacts,
-- ...). Shared by server and client so menus show exactly the numbers the server applies.
-- Sources are ModuleScripts in ReplicatedStorage.DogEconomy.BonusSources, each returning
--   {Name=string, Global=function(p,now,add) end, Dog=function(p,d,now,add) end}
-- and calling add(key, amount) for the stats below. Both functions are optional and must be
-- pure (read the profile, never write it) and nil-safe (feature data may be missing).
--
-- Stat keys (amounts are fractions: .10 = +10%, unless stated):
--   DigSpeed      dog work speed            (Rules.Cooldown; speed beyond the cooldown floor turns into extra loot rolls)
--   Luck          rare loot / item luck     (Rules.Dig rare-loot weight, ItemRules luck)
--   Income        value of what dogs dig    (additive with other Income sources, applied at dig/mint time)
--   MoneyMult     money multiplier          (each source multiplies: total factor = product of (1+x))
--   RareFind      chance to find items      (ItemRules item chance)
--   ItemMutation  item mutation chance      (ItemRules.Mutation, non-NORMAL rows)
--   DogPower      dog efficiency            (multiplies the dog's power budget)
--   Storage       extra loot + item storage (flat units, not a fraction)
--   DepthSpeed    depth progress speed      (depth system)
--   XP            XP gained
--   Offline       offline earnings
--   DogMutation   chance that a new dog is mutated (conveyor, lab rerolls)
-- Apply rule: totals are applied OUTSIDE the legacy capped brackets (SetBonus/SellValue caps) and
-- are stored on loot/items when they are created; nothing reads live bonuses at sale time.
local B={}
B.Keys={'DigSpeed','Luck','Income','MoneyMult','RareFind','ItemMutation','DogPower','Storage','DepthSpeed','XP','Offline','DogMutation'}
B.Sources={}

local function load()
 local folder=script.Parent:FindFirstChild('BonusSources')
 if not folder then return end
 local modules=folder:GetChildren()
 table.sort(modules,function(a,b)return a.Name<b.Name end)
 for _,m in ipairs(modules)do
  if m:IsA('ModuleScript')then
   local ok,source=pcall(require,m)
   if ok and type(source)=='table'then source.Name=source.Name or m.Name;table.insert(B.Sources,source)
   else warn('DOGROTS bonus source '..m.Name..' failed: '..tostring(source))end
  end
 end
end
load()

local function blank()
 local t={MoneyMultFactor=1}
 for _,k in ipairs(B.Keys)do t[k]=0 end
 return t
end
local function adder(t)
 return function(key,amount)
  amount=tonumber(amount)or 0
  if amount~=amount or amount==0 or t[key]==nil then return end
  if key=='MoneyMult'then t.MoneyMultFactor*=1+amount end
  t[key]+=amount
 end
end

-- Player-wide totals (upgrade tree, accessories, ...).
function B.Global(p,now)
 local t=blank()
 if type(p)~='table'then return t end
 local add=adder(t)
 for _,s in ipairs(B.Sources)do
  if s.Global then local ok,err=pcall(s.Global,p,now,add);if not ok then warn('DOGROTS bonus '..s.Name..': '..tostring(err))end end
 end
 return t
end
-- Totals that apply to one dog only (artifacts on that dog, ...).
function B.Dog(p,d,now)
 local t=blank()
 if type(p)~='table'or type(d)~='table'then return t end
 local add=adder(t)
 for _,s in ipairs(B.Sources)do
  if s.Dog then local ok,err=pcall(s.Dog,p,d,now,add);if not ok then warn('DOGROTS bonus '..s.Name..': '..tostring(err))end end
 end
 return t
end
-- Global + one dog. `global` may be passed in to avoid recomputing it for every dog in a tick.
function B.For(p,d,now,global)
 global=global or B.Global(p,now)
 local dog=B.Dog(p,d,now)
 local t=blank()
 for _,k in ipairs(B.Keys)do t[k]=global[k]+dog[k]end
 t.MoneyMultFactor=global.MoneyMultFactor*dog.MoneyMultFactor
 return t
end
-- The factor dug value is multiplied by: (1+Income) * MoneyMult factor * (1+DogPower).
function B.ValueFactor(t)
 return (1+math.max(-.9,t.Income))*t.MoneyMultFactor*(1+math.max(-.9,t.DogPower))
end
return B
