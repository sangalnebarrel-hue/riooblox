local C={}
C.Version=4
C.BalanceVersion="2026-10-10.MINING_POLISH_1"
C.StartingCash=4200
C.MaxCash=9000000000000000
C.MaxDogs=250
C.TickSeconds=1
C.Work={Duration=4,BaseCooldown=20,MasteryReduction=.12,MinCooldown=6,MaxCooldown=30}
C.UpgradeEffects={Dig=.04,Storage=25,Kennel=.015,Plot=.025,DogStorage=20,Ability=.02}
C.Rarities={"Common","Rare","Epic","Legendary","Mythic","Secret"}
C.Power={1,1.3,1.7,2.3,3.1,4.2}
C.Prices={3500,22000,140000,900000,6500000,55000000}
-- Per-spawn rarity odds on the tongue (sum 100), tuned to Steal a Brainrot's real-time
-- feel at ~5.6 dogs/min: Legendary ~7 min, Mythic ~24 min, a Secret ~2 h per server.
C.Weights={60.5,27,9,2.6,.75,.15}
-- How the Secret budget is shared on the tongue (per mille). THE DOG is the legend:
-- ~1 in 95,000 line dogs, roughly once per 280 hours of one server.
C.SecretLineWeights={Cubedog=240,Dogdogdogdog=210,Spiderdog=160,WrongDog=120,NuclearPug=85,
 LongDog=50,['404Dog']=60,UnfinishedDog=38,DivineDog=30,TheDog=7}
-- What a Secret costs on the tongue (BasePrice stays C.Prices[6] for every other use).
-- Like Steal a Brainrot, the rarer it walks, the more it costs.
C.SecretLinePrices={Cubedog=55000000,Dogdogdogdog=65000000,Spiderdog=75000000,WrongDog=90000000,NuclearPug=110000000,
 LongDog=125000000,['404Dog']=145000000,UnfinishedDog=180000000,DivineDog=220000000,TheDog=450000000}
-- Rarity is not tied to depth: the conveyor is shared by players at every depth.
C.DogMinLayer={1,1,1,1,1,1}
-- rank=seconds: a soft safety net (~3x the natural interval) for a quiet server, not a
-- schedule. Secrets are never guaranteed.
C.LineGuarantee={[4]=1200,[5]=4500}
C.SpecialAcquisition={LongDog={MinLayer=4,Chance=1/20000},TheDog={MinLayer=5,MinPrestige=1,Interval=900,Chance=1/1000,ClaimCooldown=86400}}
-- THE DOG now arrives on the tongue (SecretLineWeights) with its cinematic; the old
-- silent straight-to-inventory server arrival is off (ArrivalChance=0, code kept).
-- LONG DOG walks the tongue too (SecretLineWeights); digging it up is off (LongDogChance=0;
-- a discovery already pending still resolves).
C.SpecialDiscovery={LongDogChance=0,LongDogMinLayer=4,ArrivalInterval=900,ArrivalChance=0}
C.Retire={1,5,20,80,300,1200}
C.Variants={
 {Name="Normal",Weight=9150,Bonus=0},{Name="Shiny",Weight=550,Bonus=.03},
 {Name="Golden",Weight=200,Bonus=.06},{Name="Corrupted",Weight=70,Bonus=.10},
 {Name="Glitched",Weight=25,Bonus=.12},{Name="Void",Weight=5,Bonus=.15},
}
C.Diminishing={1,.35,.10,.03,.01}
C.Ascension={0,.03,.06,.10}
C.Weeks={"Dachshund","Undead","Cyber","Food"}
C.Layers={
 {Name="Backyard",Depth="0–10m",Cost=0,Level=1,Hardness=1,Color={126,169,80},Event="Golden Soil",
  Loot={{"Old Sneaker","Junk",33,6},{"Buried Lunch","Food",22.67,15},{"Chewed Bone","Bone",18.67,21},{"Dry Seed Pod","Dry",11.33,24},{"Golden Tag","Gold",9.33,60},{"Tiny Treasure Pouch","Treasure",4.23,120},{"Buried Compass","Artifact",.77,750}}},
 {Name="Caverns",Depth="10–50m",Cost=16000,Level=5,Hardness=1.2,Color={176,143,107},Event="Retro Cache",
  Loot={{"Dry Quartz","Dry",21.33,15},{"Fossil Bone","Bone",19.33,24},{"Iron Deposit","Heavy",17.33,38},{"Gold Nugget","Gold",15.33,52},{"Underground Pearl","Water",12,38},{"Miner Relic","Artifact",8.67,90},{"Crystal Cache","Treasure",5.17,225},{"Sealed Geode","Unknown",.84,900}}},
 {Name="Ancient Ruins",Depth="50–150m",Cost=120000,Level=12,Hardness=1.5,Color={54,192,231},Event="Data Rain",
  Loot={{"Stone Tablet","Artifact",28.67,65},{"Royal Cache","Treasure",21.33,75},{"Ancient Coin","Gold",16.33,95},{"Sealed Relic","Unknown",12,120},{"Forgotten Memory","Digital",8,100},{"Preserved Feast","Food",5,90},{"Statue Fragment","Heavy",5.33,150},{"Fallen Star Relic","Space",3.34,300}}},
 {Name="Cursed Depths",Depth="150–500m",Cost=900000,Level=22,Hardness=2,Color={167,61,210},Event="Cleanse Surge",
  Loot={{"Corrupted Scrap","Corrupted",28.67,120},{"Cursed Bone","Bone",21.33,130},{"Contraband Cache","Contraband",17.33,180},{"Burning Ember","Energy",12,170},{"Obsidian Idol","Artifact",10,250},{"Cursed Vault","Treasure",6.33,400},{"Unknown Heart","Unknown",2.67,800},{"Dark Meteor","Space",1.67,1700}}},
 {Name="THE VOID",Depth="500m+",Cost=8000000,Level=35,Hardness=2.5,Color={72,41,124},Event="Void Eclipse",
  Loot={{"Void Dust","Void",28.67,250},{"Black Star","Space",21.33,340},{"Reality Data","Digital",15,300},{"Unknown Signal","Unknown",12,400},{"Solar Fragment","Energy",10,450},{"Void Tide Pearl","Water",6.67,500},{"Lost Planet Cache","Treasure",4.67,1000},{"First Echo","Artifact",1.66,3000}}},
}
-- Global Fix 1: ordinary finds feel valuable immediately, but progression purchases scale with them.
-- Values are multiplied after the layer tables so every existing dog ability keeps the same loot pool.
C.LootValueScale={5.33,6,6.67,7.33,8}
for layerIndex,layer in ipairs(C.Layers)do
 local scale=C.LootValueScale[layerIndex]or 1
 for _,loot in ipairs(layer.Loot)do loot[4]=math.max(1,math.floor(loot[4]*scale))end
end
C.Upgrades={
 Dig={Base=4500,Factor=2.05,Max=10,LevelBase=2,LevelStep=3},
 Storage={Base=3500,Factor=2.00,Max=10,LevelBase=2,LevelStep=3},
 Kennel={Base=6500,Factor=2.10,Max=10,LevelBase=3,LevelStep=4},
 Plot={Base=8000,Factor=2.35,Max=8,LevelBase=3,LevelStep=4},
 DogStorage={Base=6000,Factor=2.10,Max=10,LevelBase=4,LevelStep=4},
 Ability={Base=15000,Factor=2.25,Max=6,LevelBase=6,LevelStep=5},
}
-- Coin prices of boosts follow the economy (ReplicatedStorage.DogEconomy.BoostPricing): a share
-- of what the team earns during the boost (IncomeShare × Seconds × income per second), never
-- below Cash × LayerScale[deepest unlocked layer]. Robux bundles scale their coins the same way.
C.BoostPricing={LayerScale={1,3,8,20,50},PeakHalfLife=6*3600}
-- Luck lives in its own tab (LUCK). The Supplies shop sells the other three.
C.SupplyOrder={"GoldenBiscuit","EnergySnack","StorageCrate"}
C.Supplies={
 -- No longer sold: kept so saved timers and Donut Corgi's treats keep working.
 LuckyTreat={Name="Lucky Treat",Order=9,Cash=6000,Seconds=600,MaxSeconds=3600,Effect="Luck",Magnitude=.12,Hidden=true,IncomeShare=.05,
  EffectText="+12% base rare-find weight",
  Description="Boosts Artifact, Treasure, Rare and Space weights in ordinary digging."},
 GoldenBiscuit={Name="Golden Biscuit",Order=1,Cash=6000,Seconds=600,MaxSeconds=3600,Effect="Value",Magnitude=.20,IncomeShare=.09,
  EffectText="+20% Coins from ordinary loot",
  Description="Ordinary loot your dogs dig is worth 20% more Coins. Stacks on top of every other value bonus."},
 EnergySnack={Name="Energy Snack",Order=2,Cash=5000,Seconds=600,MaxSeconds=3600,Effect="Speed",Magnitude=.25,IncomeShare=.09,
  EffectText="+25% digging speed",
  Description="Shorter rests between digs for the whole team. Stacks with other speed bonuses up to the team speed cap."},
 StorageCrate={Name="Storage Crate",Order=3,Cash=4000,Seconds=600,MaxSeconds=3600,Effect="Storage",Magnitude=100,IncomeShare=.04,
  EffectText="+100 ordinary-loot spaces",
  Description="Holds more ordinary finds until you sell. Does not add dog or item slots. Existing loot stays safe when it expires."},
}
-- Personal luck (LUCK tab): Nx LUCK = +N×100% weight on rare loot in ordinary digging and a
-- bigger chance of rare discoveries. Every tier has its own timer; the highest active one counts.
C.LuckTiers={
 {Tier=1,Name="1x LUCK",Bonus=1,Cash=9000,IncomeShare=.04,Seconds=600,MaxSeconds=3600},
 {Tier=2,Name="2x LUCK",Bonus=2,Cash=25000,IncomeShare=.10,Seconds=600,MaxSeconds=3600},
 {Tier=3,Name="3x LUCK",Bonus=3,Cash=70000,IncomeShare=.20,Seconds=600,MaxSeconds=3600},
 {Tier=4,Name="4x LUCK",Bonus=4,Cash=200000,IncomeShare=.35,Seconds=600,MaxSeconds=3600},
 {Tier=5,Name="5x LUCK",Bonus=5,Cash=600000,IncomeShare=.55,Seconds=600,MaxSeconds=3600},
}
-- Rare discoveries (items under 1% base chance) gain this much chance per luck tier.
C.LuckItemBoost=.4
-- Server luck (Robux): multiplies the tongue's Legendary/Mythic/Secret odds for everyone here.
C.ServerLuck={Ranks={4,5,6},MaxSeconds=7200}
C.Cosmetics={GoldenKennel={Cash=50000},CyberKennel={Cash=250000},VoidAura={Cash=1000000,Bones=100},FounderPlaque={Cash=100000}}
-- Levels are now real progression gates instead of a cosmetic counter.
C.MaxLevel=50
function C.XPForLevel(level)
 level=math.clamp(math.floor(tonumber(level)or 1),1,C.MaxLevel)
 if level<=1 then return 0 end
 return math.floor(90*((level-1)^1.65))
end
function C.LevelFromXP(xp)
 xp=math.max(0,tonumber(xp)or 0)
 local level=1
 while level<C.MaxLevel and xp>=C.XPForLevel(level+1)do level+=1 end
 return level
end
function C.UpgradeLevel(kind,currentLevel)
 local d=C.Upgrades[kind];if not d then return 1 end
 return math.max(1,(d.LevelBase or 1)+(math.max(0,currentLevel or 0))*(d.LevelStep or 0))
end
C.TradeLevel=5
C.PrestigeLevel=35
C.PrestigeBaseCost=12000000
-- One-time launch migration. Old profiles become a clean fresh profile and receive a Lucky Block.
C.MegaResetVersion=1
C.MegaResetGiftTier='Epic'  
C.MegaResetGiftCount=1
C.DailyRewards={
 {Cash=1500},{Cash=2500},{Cash=4000,Bones=2},{Cash=6000,Bones=3},
 {Cash=9000,Bones=4},{Cash=13000,Bones=5},{Cash=18000,Bones=8,LuckyBlock='Common'},
}
C.PlaytimeRewards={
 {Seconds=5*60,Cash=800},{Seconds=15*60,Cash=1500},
 {Seconds=30*60,Cash=2500,Bones=2},{Seconds=60*60,Cash=5000,Bones=3},
 {Seconds=90*60,Cash=7500,Bones=4},{Seconds=120*60,Cash=11000,Bones=5},
 {Seconds=180*60,Cash=18000,Bones=8},{Seconds=240*60,Cash=28000,Bones=12},
}
-- Active Mining: a hands-on yard loop beside the kennels.
C.Mining={
 Ores={
  {Name='Limestone',RU='Известняк',Icon='🪨',Weight=34,HP=14,ValueMin=320,ValueMax=470,Color={168,165,150}},
  {Name='Copper',RU='Медная руда',Icon='🟤',Weight=24,HP=22,ValueMin=640,ValueMax=930,Color={184,105,63}},
  {Name='Iron',RU='Железная руда',Icon='⚙️',Weight=17,HP=34,ValueMin=1180,ValueMax=1680,Color={105,112,121}},
  {Name='Quartz',RU='Кварц',Icon='🔹',Weight=10,HP=48,ValueMin=2200,ValueMax=3150,Color={220,222,232}},
  {Name='Amethyst',RU='Аметистовая жила',Icon='🟣',Weight=7,HP=66,ValueMin=4300,ValueMax=6200,Color={150,82,205}},
  {Name='Ruby',RU='Рубиновая жила',Icon='❤️',Weight=4.5,HP=82,ValueMin=8600,ValueMax=12000,Color={210,45,74}},
  {Name='Emerald',RU='Изумрудная жила',Icon='💚',Weight=2.2,HP=105,ValueMin=18000,ValueMax=25000,Color={36,190,112}},
  {Name='Meteorite',RU='Метеоритная руда',Icon='☄️',Weight=1,HP=130,ValueMin=42000,ValueMax=59000,Color={55,62,73}},
  {Name='VoidCrystal',RU='Кристалл Пустоты',Icon='🌌',Weight=.3,HP=160,ValueMin=104000,ValueMax=145000,Color={110,54,190}},
 },
 Pickaxes={
  {Name='Wooden Pickaxe',RU='Деревянная кирка',Icon='🪵',Price=600,Strength=0,Damage=1,Cooldown=.78,FX=1,Color={145,101,62}},
  {Name='Stone Pickaxe',RU='Каменная кирка',Icon='🪨',Price=8000,Strength=15,Damage=2,Cooldown=.70,FX=2,Color={132,137,143}},
  {Name='Iron Pickaxe',RU='Железная кирка',Icon='⚙️',Price=45000,Strength=45,Damage=4,Cooldown=.62,FX=3,Color={173,181,190}},
  {Name='Steel Pickaxe',RU='Стальная кирка',Icon='🛡️',Price=240000,Strength=95,Damage=7,Cooldown=.54,FX=4,Color={118,154,176}},
  {Name='Crystal Pickaxe',RU='Кристальная кирка',Icon='💎',Price=1500000,Strength=180,Damage=13,Cooldown=.46,FX=5,Color={111,221,235}},
  {Name='Inferno Pickaxe',RU='Адская кирка',Icon='🔥',Price=11000000,Strength=320,Damage=26,Cooldown=.38,FX=6,Color={255,103,49}},
  {Name='Voidbreaker',RU='Разломщик Пустоты',Icon='🌌',Price=90000000,Strength=520,Damage=62,Cooldown=.30,FX=7,Color={184,75,255}},
 },
 Weights={
  {Name='Starter Dumbbell',RU='Лёгкая гиря',Icon='🥉',Price=0,Strength=0,Gain=1,Cap=25,Cooldown=1.15,Color={160,170,180}},
  {Name='Iron Kettlebell',RU='Железная гиря',Icon='⚫',Price=3000,Strength=15,Gain=2,Cap=55,Cooldown=1.05,Color={92,100,110}},
  {Name='Heavy Plate',RU='Тяжёлая плита',Icon='⬛',Price=18000,Strength=40,Gain=3,Cap=110,Cooldown=.95,Color={72,78,87}},
  {Name='Steel Block',RU='Стальной блок',Icon='🧱',Price=100000,Strength=80,Gain=5,Cap=190,Cooldown=.88,Color={118,144,162}},
  {Name='Crystal Weight',RU='Кристальная гиря',Icon='💠',Price=650000,Strength=150,Gain=8,Cap=300,Cooldown=.80,Color={95,218,232}},
  {Name='Inferno Core',RU='Инферно-ядро',Icon='🔥',Price=4500000,Strength=260,Gain=12,Cap=450,Cooldown=.72,Color={249,91,45}},
  {Name='Void Mass',RU='Масса Пустоты',Icon='🌑',Price=35000000,Strength=400,Gain=18,Cap=700,Cooldown=.65,Color={160,66,235}},
 },
}
C.EventGoal=100000
C.EventMilestones={1000,5000,20000,50000,100000}
C.EventPersonal={25,100,300,700,1500}
C.MaxListingsPerDog=150
C.MaxAuctions=1500
C.SessionSeconds=180
C.AuctionDurations={300,3600,86400}
return C
