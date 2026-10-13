-- District places behind the persistent NavigationAnchors (Parts with a Target ObjectValue; the
-- server's NavigationSync keeps their CFrames on the targets). Used by DistrictTravel, World,
-- the world events and the district map. The full destination list with categories, aliases and
-- the routes of "SHOW THE WAY" lives in ReplicatedStorage.Navigation (Destinations, RouteGraph).
local map=workspace:WaitForChild('DOGROTS_District')
local nav=map:WaitForChild('NavigationAnchors')
local Destinations=require(script.Parent:WaitForChild('Navigation'):WaitForChild('Destinations'))
local Routing={}
Routing.Destinations=Destinations
-- The 13 anchored district places (same keys, names and order as before).
Routing.Locations={
 {Key='Shelter',Name='Dog Shelter',Detail='Sell extra dogs and find them a new home'},
 {Key='Feedback',Name='Developer mailbox',Detail='Send ideas and wishes to the developers'},
 {Key='DogLine',Name='THE DOG',Detail='Follow the tongue to find your next dog'},
 {Key='PlayerYards',Name='Your yard',Detail='Your dogs, digging and workshop'},
 {Key='WelcomeHub',Name='Welcome plaza',Detail='Arrival, community and DOG EXPRESS'},
 {Key='DogDex',Name='DogDex museum',Detail='100 good boys to discover'},
 {Key='MutationLab',Name='Mutation lab',Detail='Variants, ascension and research'},
 {Key='GlobalDigSite',Name='Global event',Detail='COMING SOON',Sealed=true},
 {Key='RewardMachine',Name='DOG-O-MATIC PLAZA',Detail='DOG-O-MATIC rewards and odds'},
 {Key='Shops',Name='Paw market',Detail='Equipment, cosmetics and supplies'},
 {Key='DogPark',Name='Leaderboard Plaza',Detail='All-time records and the social court'},
 {Key='PortalRuins',Name='Digging layers',Detail='Discover the underground layers'},
 {Key='TheVoid',Name='The Void',Detail='SEALED / FUTURE AREA',Sealed=true},
}
-- Destination key of a key, display name or alias ("Factory", "Mutation lab", "THE DOG"...).
function Routing.Resolve(name)
 return Destinations.Resolve(name)
end
function Routing.Anchor(key)
 local mirror=nav:FindFirstChild(key)
 local ref=mirror and mirror:FindFirstChild('Target')
 return ref and ref.Value or mirror
end
local function yardOf(player)
 local yards=map:FindFirstChild('04_PlayerYards')
 local id=player and player:GetAttribute('YardId')
 if not yards or id==nil then return nil end
 for _,yard in yards:GetChildren() do if yard:GetAttribute('YardId')==id then return yard end end
 return nil
end
function Routing.Position(key,player)
 if key=='PlayerYards' and player then
  local yard=yardOf(player)
  local spawn=yard and yard:FindFirstChild('YardSpawn')
  if spawn and spawn:IsA('BasePart') then return spawn.Position end
  -- The yard may not be streamed in on this client: the server stores the spawn on the player.
  local stored=player:GetAttribute('YardSpawnPosition')
  if typeof(stored)=='Vector3' then return stored end
 end
 local a=Routing.Anchor(key);return a and a:IsA('BasePart') and a.Position or nil
end
function Routing.Bounds()
 local low,high=Vector3.new(math.huge,0,math.huge),Vector3.new(-math.huge,0,-math.huge)
 for _,loc in Routing.Locations do local p=Routing.Position(loc.Key);if p then low=low:Min(p);high=high:Max(p) end end
 return low-Vector3.new(100,0,100),high+Vector3.new(100,0,100)
end
return Routing
