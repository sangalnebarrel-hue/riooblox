-- Shared client access to the economy server for the new screens (Kit windows).
--   Net.Request(action, args)  -> ok, result     one DogEconomyRequest call with a fresh request id;
--                                                a reply carrying StateSnapshot refreshes the cache
--   Net.Snapshot(maxAge)       -> snapshot|nil  cached Runtime.Snapshot, refetched when older than
--                                                maxAge seconds (default 4); concurrent callers share one fetch
--   Net.Cached()               -> snapshot|nil  last snapshot without any request
--   Net.Changed:Connect(fn(snapshot))            fires whenever a newer snapshot arrives
--   Net.OnPush(kind, fn(data)) -> connection     DogEconomyPush notifications of one kind
-- Requests never throw: transport errors come back as false, message.
local RS=game:GetService('ReplicatedStorage')
local Http=game:GetService('HttpService')
local Net={}
local remote=RS:WaitForChild('DogEconomyRequest')
local cache,cachedAt=nil,-math.huge
local fetching=nil
local changed=Instance.new('BindableEvent')
Net.Changed=changed.Event

local function publish(snapshot)
 if type(snapshot)~='table'then return end
 cache=snapshot;cachedAt=os.clock()
 changed:Fire(snapshot)
end
Net.Publish=publish

function Net.Request(action,args)
 local id=(Http:GenerateGUID(false):gsub('-',''))
 local transport,ok,result=pcall(function()return remote:InvokeServer(action,args or {},id)end)
 if not transport then return false,'Connection problem; try again'end
 if ok and type(result)=='table'and type(result.StateSnapshot)=='table'then
  publish(result.StateSnapshot)
 end
 return ok==true,result
end

function Net.Snapshot(maxAge)
 maxAge=maxAge or 4
 if cache and os.clock()-cachedAt<=maxAge then return cache end
 if fetching then
  local deadline=os.clock()+15
  while fetching and os.clock()<deadline do task.wait()end
  return cache
 end
 fetching=true
 local transport,ok,result=pcall(function()return remote:InvokeServer('Snapshot',{},nil)end)
 fetching=nil
 if transport and ok and type(result)=='table'then publish(result)end
 return cache
end
function Net.Cached()return cache end

local pushHandlers={}
function Net.OnPush(kind,fn)
 pushHandlers[kind]=pushHandlers[kind]or {}
 local list=pushHandlers[kind]
 table.insert(list,fn)
 return {Disconnect=function()
  local i=table.find(list,fn);if i then table.remove(list,i)end
 end}
end
task.spawn(function()
 local push=RS:WaitForChild('DogEconomyPush',60)
 if not push then return end
 push.OnClientEvent:Connect(function(kind,data)
  for _,fn in ipairs(table.clone(pushHandlers[kind]or {}))do task.spawn(fn,data)end
 end)
end)
return Net
