-- Feature registry: the hook points the new game systems plug into, so each system lives in
-- its own ModuleScript under ServerScriptService.Economy.Features and no central list has to be
-- edited when one is added (docs/OVERHAUL.md, "Контракты для систем переработки").
--
-- Data hooks (inside the profile transaction; pure, no yields, no world access):
--   Name            string, for logs (default: the ModuleScript name)
--   Order           number, lower runs first (default 100)
--   Normalize(R,p,now)                 fill defaults / migrate saved data (end of Rules.Normalize)
--   Validate(R,p)                      structural checks after every transaction (Rules.Validate);
--                                      must never reject data that Normalize would heal
--   Action(R,p,action,a,now,random)    return nil when the action is not this feature's, else
--                                      message[, extra] (extra fields are merged into the reply)
--   Snapshot(R,p,view,now)             add read-only fields to snapshot.Features (`view`)
--
-- Request hooks (Runtime.Request, DogEconomyRequest). They apply to the actions the feature lists:
--   Actions = {Name=true, ...}         the action names it owns (any truthy value). Registry.Owner
--                                      answers who owns a name; tests/feature_hooks.luau fails when
--                                      two features own one name or a feature shadows a legacy one.
--   Cost(action) -> tokens             token-bucket price of one request (default 1; the bucket
--                                      holds 8 and refills 1.5 per second, shared by every remote)
--   Gate(player,action,a,Runtime)      world checks BEFORE the profile transaction (near a stand or
--                                      a console, own yard...). Refuse by raising (Rules.Check) or by
--                                      returning a message string; nil/true lets the request through
--   Request(player,action,a,receiptId,Runtime) -> ok, result
--                                      a fully custom path (like LabService.Request). Without it the
--                                      action runs Engine:Action -> Rules.Action -> Registry.Action
--   Reply = 'Snapshot' | 'Patch' | 'None'   (or {[action]=mode}; default 'Snapshot')
--                                      what a successful table reply carries: the full StateSnapshot
--                                      (today's behaviour), StatePatch = Patch(...), or nothing
--   Patch(player,action,result,p) -> table   the light reply of Reply='Patch' (p = the refreshed
--                                      Runtime view); a failing or missing Patch falls back to a
--                                      full snapshot
--   Project(player,p,Runtime)          called at the end of every Runtime.Project (each feature in
--                                      its own pcall): publish player / yard attributes, writing an
--                                      attribute only when its value changes
-- Common validation (rate limit, profile Ready, clean args, a 32-hex request id) always runs first.
-- A feature without these fields behaves exactly as before: its actions reach Registry.Action.
-- Feature data may be absent on profiles that did not pass Rules.Normalize (e.g. offline
-- estimates): every reader must be nil-safe. Stat bonuses (upgrade tree, accessories, artifacts)
-- go through ReplicatedStorage.DogEconomy.Bonuses, not through this registry.
local Registry={Modules={},Owners={},Collisions={}}
local REPLY={Snapshot=true,Patch=true,None=true}
local warnedAt={}
-- One warning per feature and hook every 30 s: a hook that fails on every tick must not flood.
local function report(feature,hook,err)
 local key=feature.Name..'.'..hook
 if os.clock()-(warnedAt[key]or -60)>=30 then warnedAt[key]=os.clock();warn('DOGROTS feature '..key..': '..tostring(err))end
end
local function sort()
 table.sort(Registry.Modules,function(a,b)
  local x,y=a.Order or 100,b.Order or 100
  if x~=y then return x<y end
  return a.Name<b.Name
 end)
end
-- Registers a feature table (the Features folder below, or a test). An action already owned by
-- another feature keeps its first owner; the clash is listed in Registry.Collisions.
function Registry.Add(feature)
 assert(type(feature)=='table'and type(feature.Name)=='string','A feature needs a Name')
 table.insert(Registry.Modules,feature);sort()
 if type(feature.Actions)=='table'then
  for action,owned in pairs(feature.Actions)do if owned then
   local owner=Registry.Owners[action]
   if owner and owner~=feature then
    table.insert(Registry.Collisions,{Action=action,Owner=owner.Name,Feature=feature.Name})
    warn('DOGROTS feature '..feature.Name..' also claims '..tostring(action)..', owned by '..owner.Name)
   else Registry.Owners[action]=feature end
  end end
 end
 return feature
end
local folder=script.Parent:FindFirstChild('Features')
if folder then
 for _,m in ipairs(folder:GetChildren())do
  if m:IsA('ModuleScript')then
   local ok,feature=pcall(require,m)
   if ok and type(feature)=='table'then
    feature.Name=feature.Name or m.Name
    Registry.Add(feature)
   else
    warn('DOGROTS feature '..m.Name..' failed to load: '..tostring(feature))
   end
  end
 end
end

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

-- The feature that declared `action` in its Actions, or nil.
function Registry.Owner(action)
 return type(action)=='string'and Registry.Owners[action]or nil
end
-- Token price of one request for `action` (1 unless its owner prices it).
function Registry.Cost(action)
 local f=Registry.Owner(action)
 if not(f and f.Cost)then return 1 end
 local ok,cost=pcall(f.Cost,action)
 if ok and type(cost)=='number'and cost==cost and cost>=0 and cost<=8 then return cost end
 report(f,'Cost',ok and('bad cost '..tostring(cost))or cost)
 return 1
end
-- Raises the refusal of the owner's Gate (its error or the message it returned).
function Registry.Gate(player,action,a,runtime)
 local f=Registry.Owner(action)
 if not(f and f.Gate)then return end
 local refusal=f.Gate(player,action,a,runtime)
 if type(refusal)=='string'then error(refusal,0)end
end
-- Reply mode of a successful request for `action`.
function Registry.Reply(action)
 local f=Registry.Owner(action);local mode=f and f.Reply
 if type(mode)=='table'then mode=mode[action]end
 return REPLY[mode]and mode or'Snapshot'
end
-- StatePatch of a Reply='Patch' action, or nil (the caller then sends a full snapshot).
function Registry.Patch(player,action,result,p)
 local f=Registry.Owner(action)
 if not(f and f.Patch)then return nil end
 local ok,patch=pcall(f.Patch,player,action,result,p)
 if ok and type(patch)=='table'then return patch end
 report(f,'Patch',ok and'no patch table'or patch)
 return nil
end
-- End of Runtime.Project: every feature's Project hook, each protected on its own.
function Registry.Project(player,p,runtime)
 for _,f in ipairs(Registry.Modules)do
  if f.Project then
   local ok,err=pcall(f.Project,player,p,runtime)
   if not ok then report(f,'Project',err)end
  end
 end
end
return Registry
