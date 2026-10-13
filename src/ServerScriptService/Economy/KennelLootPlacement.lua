-- Where a new find is revealed (DiscoveryReveal LootSpawn): at the dog that found it.
-- On the surface that is the kennel pit's LootSpawn marker. While the owner digs in the mine
-- (CurrentLayer >= 2, the dog works at its worksite in that level) and the owner is down there
-- too (character inside the yard's mine, MineLayout.Contains), the find appears beside the dog in
-- the mine; otherwise it "comes up the rope" at the surface pit.
local Replicated=game:GetService('ReplicatedStorage')
local S={}
local mineLayout=nil
local function layoutModule()
 if mineLayout==nil then
  local ok,module=pcall(function()return require(Replicated:WaitForChild('Mine'):WaitForChild('MineLayout'))end)
  mineLayout=ok and module or false
 end
 return mineLayout or nil
end
function S.Marker(slot)
 local ground=slot:FindFirstChild('DarkExcavation',true)
 if not ground or not ground:IsA('BasePart')then return end
 local marker=ground:FindFirstChild('LootSpawn')
 if not marker then marker=Instance.new('Attachment');marker.Name='LootSpawn';marker.Parent=ground end
 if not marker:IsA('Attachment')then return end
 marker.Position=Vector3.new(0,ground.Size.Y/2+.12,0)
 return marker
end
-- The mine reveal CFrame for a dog of `slotName` when the owner (player) is in the mine, else nil.
function S.MineSpawn(player,p,yard,slotName)
 local Layout=layoutModule()
 local layer=Layout and Layout.LayerNumber(p and p.CurrentLayer)or 1
 if not Layout or layer<2 then return nil end
 local index=tonumber(tostring(slotName):match('^DigSlot_(%d+)$'))
 local layout=index and Layout.ForYard(yard)
 local site=layout and layout:Worksite(layer,index)
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if not site or not root or not root:IsA('BasePart')then return nil end
 if not layout:Contains(root.Position)then return nil end
 return site.Loot+Vector3.new(0,.12,0),layer
end
function S.Resolve(player,p,item)
 if item.OwnerUserId~=player.UserId or item.OriginalFinderUserId~=player.UserId then return end
 local uid=item.SourceDogUid or(type(item.ItemUid)=='string'and item.ItemUid:match('^([^:]+):%d+:%d+$'))
 local dog=uid and p.Dogs[uid]
 if not dog or dog.OwnerUserId~=player.UserId or type(dog.AssignedSlot)~='string'or not dog.AssignedSlot:match('^DigSlot_[1-5]$')then return end
 local yard=require(script.Parent.YardCommerce).Yard(player)
 local slot=yard and yard:FindFirstChild(dog.AssignedSlot)
 if not slot or slot:GetAttribute('Unlocked')==false then return end
 local ok,mineCF,layer=pcall(S.MineSpawn,player,p,yard,dog.AssignedSlot)
 if ok and mineCF then
  return {CFrame=mineCF,DogUid=uid,Slot=dog.AssignedSlot,YardId=yard:GetAttribute('YardId'),OwnerUserId=player.UserId,MineLayer=layer}
 end
 local marker=S.Marker(slot);if not marker then return end
 return {CFrame=marker.WorldCFrame,DogUid=uid,Slot=dog.AssignedSlot,YardId=yard:GetAttribute('YardId'),OwnerUserId=player.UserId}
end
return S
