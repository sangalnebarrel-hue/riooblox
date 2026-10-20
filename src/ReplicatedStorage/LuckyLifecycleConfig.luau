local C={
 Version=1,InventoryCapacity=60,PlacementSlots=3,VisualScale=.68,
 OpenSeconds={Common=15,Uncommon=25,Rare=40,Epic=55,Legendary=75,Mythic=100,['Brainrot God']=125,Secret=150},
 InteractionDistance=18,CrackAt=.55,BurstAt=.9,RetrySeconds=6,
}
-- Event tiers (LuckyBlockConfig.EventTiers, from ReplicatedStorage.Halloween.Config.PumpkinBlocks): placing a tier
-- without an OpenSeconds entry would error.
local ok,Blocks=pcall(function()return require(script.Parent:WaitForChild('LuckyBlockConfig'))end)
if ok and type(Blocks)=='table'and type(Blocks.EventTiers)=='table'then
 for tier,def in pairs(Blocks.EventTiers)do C.OpenSeconds[tier]=tonumber(def.OpenSeconds)or 60 end
end
return C
