-- Walk-up checks for yard services (server and client use the same rules).
--   A.CanUse(player, yard, target)  owner of the yard, alive, inside the target's interaction zone
--                                   (a part named in `zones`, child of the yard) and within A.Distance
--   A.OwnYard(player)               the yard the player owns (YardId + OwnerUserId), or nil
--   A.InYard(player, yard, margin)  owner of the yard and standing inside its grounds (plot decor)
-- ShowcaseAnchor / ShowcaseInteractionZone are created at runtime by Economy.YardCommerce.
local A={Distance=9}
local zones={StorageAnchor='StorageInteractionZone',SellAnchor='SellInteractionZone',UpgradeAnchor='UpgradeInteractionZone',ShowcaseAnchor='ShowcaseInteractionZone'}
A.Zones=zones
local function body(player)
 local character=player and player.Character
 local root=character and character:FindFirstChild('HumanoidRootPart')
 local hum=character and character:FindFirstChildOfClass('Humanoid')
 if root and hum and hum.Health>0 then return root end
 return nil
end
function A.CanUse(player,yard,target)
 local root=body(player)
 if not(target and yard and target:IsDescendantOf(yard)and root)then return false end
 if yard:GetAttribute('OwnerUserId')~=player.UserId then return false end
 local zone=yard:FindFirstChild(zones[target.Name]or'')
 if not zone then return false end
 local p=zone.CFrame:PointToObjectSpace(root.Position);local half=zone.Size/2
 return math.abs(p.X)<=half.X and math.abs(p.Y)<=half.Y and math.abs(p.Z)<=half.Z and (root.Position-target.Position).Magnitude<=A.Distance
end
function A.OwnYard(player)
 local map=workspace:FindFirstChild('DOGROTS_District');local yards=map and map:FindFirstChild('04_PlayerYards')
 if not(yards and player)then return nil end
 local id=player:GetAttribute('YardId')
 for _,yard in ipairs(yards:GetChildren())do
  if yard:GetAttribute('OwnerUserId')==player.UserId and(id==nil or yard:GetAttribute('YardId')==id)then return yard end
 end
 return nil
end
-- The yard grounds: the PlotFrame attribute (set by Economy.PlotDecorWorld) is the centre of the
-- YardFoundation looking at the service row; the fenced plot is 70 x 134 studs.
A.YardHalf=Vector3.new(36,40,69)
function A.InYard(player,yard,margin)
 local root=body(player)
 if not(root and yard and yard:GetAttribute('OwnerUserId')==player.UserId)then return false end
 local frame=yard:GetAttribute('PlotFrame')
 if typeof(frame)~='CFrame'then return false end
 local p=frame:PointToObjectSpace(root.Position);local m=margin or 0
 return math.abs(p.X)<=A.YardHalf.X+m and math.abs(p.Y)<=A.YardHalf.Y and math.abs(p.Z)<=A.YardHalf.Z+m
end
return A
