-- Six public block tiers. Every reward row is a rarity probability, not a per-dog weight.
-- Version 5: dog mutation (variant) odds changed (Config.Variants); blocks frozen earlier keep theirs.
local C={Version=5}
C.Rarities={'Common','Rare','Epic','Legendary','Mythic','Secret'}
C.LegacyAliases={Uncommon='Rare',['Brainrot God']='Mythic'}
C.Stream={SlotLength=12,EmptySlots=3,Speed=6,BlockChance=.25,MaxActive=8}
C.SpawnWeights={54,28,12,4.5,1.25,.25} -- sums to 100; inaccessible tiers are omitted and normalized
-- Blocks are not tied to depth either; kept for older readers of this table.
C.MinLayer={Common=1,Rare=1,Epic=1,Legendary=1,Mythic=1,Secret=1,Uncommon=1,['Brainrot God']=1}
C.ConveyorPrices={Common=5000,Rare=22000,Epic=120000,Legendary=750000,Mythic=5000000,Secret=45000000}
C.RewardPools={
 Common={85,13,2,0,0,0},Rare={28,62,9,1,0,0},Epic={0,32,61,6.5,0.5,0},
 Legendary={0,0,29,65,5.9,0.1},Mythic={0,0,0,58,41.5,0.5},Secret={0,0,0,0,92,8}}
-- Old stored blocks retain their seed and frozen pool; unplaced legacy credits use the mapped tier.
for old,new in pairs(C.LegacyAliases)do C.ConveyorPrices[old]=C.ConveyorPrices[new];C.RewardPools[old]=C.RewardPools[new]end
C.VisualConfig={Colors={Color3.fromRGB(200,202,201),Color3.fromRGB(37,166,255),Color3.fromRGB(184,64,255),Color3.fromRGB(255,191,48),Color3.fromRGB(255,51,100),Color3.fromRGB(155,58,255)},MaxParticles=8}
C.PitySettings={Enabled=false,After=20,Step=.02,Cap=.15,GoodRank=4}
C.AnnouncementSettings={MinimumRank=5,Cooldown=15}
C.RobuxProducts={
 {Key='CommonBlock',Tier='Common',Count=1,Id=0},{Key='RareBlock',Tier='Rare',Count=1,Id=0},
 {Key='EpicBlock',Tier='Epic',Count=1,Id=0},{Key='LegendaryBlock',Tier='Legendary',Count=1,Id=0},
 {Key='MythicBlock',Tier='Mythic',Count=1,Id=0},{Key='RarePack3',Tier='Rare',Count=3,Id=0},
 {Key='EpicPack5',Tier='Epic',Count=5,Id=0},{Key='LegendaryPack10',Tier='Legendary',Count=10,Id=0}}
C.Sounds={Ambience='lucky/ambience',Spawn='lucky/spawn',Buy='lucky/buy',Shake='lucky/shake',Crack='lucky/crack',Burst='lucky/burst',Reveal='lucky/reveal'}
-- Event tiers (NIGHT OF THE BURIED MOON): never in Rarities/SpawnWeights/RewardPools/RobuxProducts (no conveyor, no
-- Robux, no roulette). Their reward rows are frozen into each block when it is granted (Economy.EventBlocks), the
-- model is ReplicatedStorage.Halloween.Models.Pumpkin (LuckyShowStyle routes the client show to PumpkinBlockFX).
-- Rank only drives colours and sorting. Tier ids are saved data: never rename them.
C.EventTiers={
 Pumpkin={Rank=4,Style='Pumpkin',Event='BuriedMoon2026',Rewards='Pumpkin',TradeValue=600000,Tradeable=false,OpenSeconds=45,GhostChance=.3},
 ['Cursed Pumpkin']={Rank=5,Style='CursedPumpkin',Event='BuriedMoon2026',Rewards='CursedPumpkin',TradeValue=4000000,Tradeable=false,OpenSeconds=75,GhostChance=1},
}
do -- the event config is the source of truth when present (ReplicatedStorage.Halloween.Config.PumpkinBlocks)
 local folder=game:GetService('ReplicatedStorage'):FindFirstChild('Halloween')
 local module=folder and folder:FindFirstChild('Config')
 local ok,hw=pcall(function()return module and require(module)end)
 local blocks=ok and type(hw)=='table'and hw.PumpkinBlocks
 if type(blocks)=='table'and type(blocks.Tiers)=='table'then
  for tier,def in pairs(blocks.Tiers)do
   local row=C.EventTiers[tier]or{Event=hw.EventId}
   for k,v in pairs(def)do row[k]=v end
   if blocks.Tradeable~=nil then row.Tradeable=blocks.Tradeable==true end
   C.EventTiers[tier]=row
  end
 end
end
function C.Canonical(tier)return C.LegacyAliases[tier]or tier end
function C.Rank(tier)
 tier=C.Canonical(tier)
 local ev=C.EventTiers[tier]
 return table.find(C.Rarities,tier)or(ev and ev.Rank)or nil
end
function C.IsEvent(tier)return type(tier)=='string'and C.EventTiers[tier]~=nil end
return C
