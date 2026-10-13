-- Feature registry: the hook points the new game systems plug into, so each system lives in
-- its own ModuleScript under ServerScriptService.Economy.Features and no central list has to be
-- edited when one is added. Every feature module returns a table with any of:
--   Name            string, for logs
--   Order           number, lower runs first (default 100)
--   Normalize(R,p,now)                 fill defaults / migrate saved data (end of Rules.Normalize)
--   Validate(R,p)                      structural checks after every transaction (Rules.Validate);
--                                      must never reject data that Normalize would heal
--   Action(R,p,action,a,now,random)    return nil when the action is not this feature's, else
--                                      message[, extra] (extra fields are merged into the reply)
--   Snapshot(R,p,view,now)             add read-only fields to the client snapshot table `view`
-- Feature data may be absent on profiles that did not pass Rules.Normalize (e.g. offline
-- estimates): every reader must be nil-safe. Stat bonuses (upgrade tree, accessories, artifacts)
-- go through ReplicatedStorage.DogEconomy.Bonuses, not through this registry.
local Registry={Modules={}}
local folder=script.Parent:FindFirstChild('Features')
if folder then
 for _,m in ipairs(folder:GetChildren())do
  if m:IsA('ModuleScript')then
   local ok,feature=pcall(require,m)
   if ok and type(feature)=='table'then
    feature.Name=feature.Name or m.Name
    table.insert(Registry.Modules,feature)
   else
    warn('DOGROTS feature '..m.Name..' failed to load: '..tostring(feature))
   end
  end
 end
end
table.sort(Registry.Modules,function(a,b)
 local x,y=a.Order or 100,b.Order or 100
 if x~=y then return x<y end
 return a.Name<b.Name
end)

function Registry.Normalize(R,p,now)
 for _,f in ipairs(Registry.Modules)do if f.Normalize then f.Normalize(R,p,now)end end
end
function Registry.Validate(R,p)
 for _,f in ipairs(Registry.Modules)do if f.Validate then f.Validate(R,p)end end
end
function Registry.Action(R,p,action,a,now,random)
 for _,f in ipairs(Registry.Modules)do
  if f.Action then
   local message,extra=f.Action(R,p,action,a,now,random)
   if message~=nil then return message,extra end
  end
 end
 return nil
end
function Registry.Snapshot(R,p,view,now)
 for _,f in ipairs(Registry.Modules)do
  if f.Snapshot then
   local ok,err=pcall(f.Snapshot,R,p,view,now)
   if not ok then warn('DOGROTS feature '..f.Name..' snapshot: '..tostring(err))end
  end
 end
end
return Registry
