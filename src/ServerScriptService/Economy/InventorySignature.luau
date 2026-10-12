-- InventorySignature: tells Runtime.Project whether anything an inventory view shows has changed,
-- so the InventoryRevision player attribute only moves on a real change. Its readers
-- (InventoryController, ServiceMenusController, UpgradeTreeScreen, Economy.EquipmentWorld) refetch
-- or rebuild on every bump; a dog's dig (NextWorkAt, WorkSequence, MasteryXP, LastYield...) or
-- income alone no longer moves it.
-- Watched (cheap: table compares, no copies, no sorting of big collections):
--   finds   the uid set and, per find, Favorite, Tradeable, the RecordAtCreation flags and
--           "record check pending" (p.RecordJobs)
--   dogs    the uid set and, per dog, DogId, State, AssignedSlot, Variant, Locked, Favorite,
--           Mastery, AscensionLevel
--   blocks  owned Lucky Blocks (Tier, State, Slot, ReadyAt, Quantity) and LuckyCredits
--   the rest: Equipment.Rev (worn accessories, artifacts), display dogs, layers, storage
--           upgrades, reservations, listings and old loot stacks
-- API: local s = InventorySignature.new();  s:Changed(p) -> boolean (the first call is a change).
local S={}
S.__index=S
local EMPTY=table.freeze({})
local DOG_FIELDS={'DogId','State','AssignedSlot','Variant','Locked','Favorite','Mastery','AscensionLevel'}

function S.new()
 return setmetatable({Items={},ItemCount=0,Dogs={},DogCount=0,Blocks={},BlockCount=0,Rest=nil},S)
end
local function tableOr(v)return type(v)=='table'and v or EMPTY end
local function count(t)local n=0;for _ in pairs(t)do n+=1 end;return n end

-- One number per find: its flag bits.
local function itemCode(x,uid,jobs)
 local record=tableOr(x.RecordAtCreation);local job=jobs[x.ItemId]
 return (x.Favorite==true and 1 or 0)+(x.Tradeable==true and 2 or 0)+(record.Personal==true and 4 or 0)
  +(record.Server==true and 8 or 0)+(record.Global==true and 16 or 0)+(record.ImprovedGlobal==true and 32 or 0)
  +((type(job)=='table'and job.ItemUid==uid)and 64 or 0)
end
local function blockCode(b)
 b=tableOr(b)
 return table.concat({tostring(b.Tier),tostring(b.State),tostring(b.Slot),tostring(b.ReadyAt),tostring(b.Quantity)},'|')
end
-- Updates shadow[key] = code(value) for every entry of `map`; true when an entry was added,
-- removed or changed its code. countKey names the shadow's size field.
local function diffCodes(self,shadowKey,countKey,map,code,extra)
 local shadow=self[shadowKey];local changed,seen=false,0
 for key,value in pairs(map)do
  seen+=1
  local c=code(value,key,extra)
  local old=shadow[key]
  if old~=c then
   if old==nil then self[countKey]+=1 end
   shadow[key]=c;changed=true
  end
 end
 if seen<self[countKey]then
  for key in pairs(shadow)do if map[key]==nil then shadow[key]=nil;self[countKey]-=1 end end
  changed=true
 end
 return changed
end
local function diffDogs(self,dogs)
 local shadow=self.Dogs;local changed,seen=false,0
 for uid,d in pairs(dogs)do
  seen+=1
  local s=shadow[uid]
  if not s then s={};shadow[uid]=s;self.DogCount+=1;changed=true end
  d=tableOr(d)
  for _,field in ipairs(DOG_FIELDS)do
   local v=d[field]
   if s[field]~=v then s[field]=v;changed=true end
  end
 end
 if seen<self.DogCount then
  for uid in pairs(shadow)do if dogs[uid]==nil then shadow[uid]=nil;self.DogCount-=1 end end
  changed=true
 end
 return changed
end
-- Small scalars, one string.
local function rest(p)
 local up=tableOr(p.Upgrades);local display=tableOr(p.DisplayDogs)
 local units=0
 for _,stack in pairs(tableOr(p.Loot))do units+=tonumber(tableOr(stack).Count)or 0 end
 local credits={}
 for tier,n in pairs(tableOr(p.LuckyCredits))do table.insert(credits,tostring(tier)..'='..tostring(n))end
 table.sort(credits)
 local layers=0
 for _,open in pairs(tableOr(p.UnlockedLayers))do if open then layers+=1 end end
 return table.concat({tostring(tableOr(p.Equipment).Rev),tostring(display['1']),tostring(display['2']),tostring(display['3']),
  tostring(p.CurrentLayer),tostring(layers),tostring(up.Storage),tostring(up.DogStorage),tostring(up.Plot),
  tostring(count(tableOr(p.Reservations))),tostring(count(tableOr(p.ItemReservations))),tostring(count(tableOr(p.Listings))),
  tostring(units),table.concat(credits,',')},';')
end

function S:Changed(p)
 local items=diffCodes(self,'Items','ItemCount',tableOr(p.Items),itemCode,tableOr(p.RecordJobs))
 local dogs=diffDogs(self,tableOr(p.Dogs))
 local blocks=diffCodes(self,'Blocks','BlockCount',tableOr(p.OwnedBlocks),blockCode)
 local summary=rest(p)
 local other=summary~=self.Rest;self.Rest=summary
 return items or dogs or blocks or other
end
return S
