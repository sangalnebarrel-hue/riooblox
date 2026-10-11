-- Active Mining tuning (shared by client and server; exposed as Config.Mining).
-- Balance model and the simulator: docs/MINING.md, tools/balance_sim.py.
local M={
 Version=2,
 StudioCheats=false,       -- F8 test panel in Studio also on a published place (writes the real DataStore!)
 MaxStrength=1100,
 SessionSeconds=25,         -- a mining session stays open this long after the last hit
 CooldownTolerance=.8,      -- server accepts hits/reps at 80% of the nominal cooldown (latency)
 ComboTimeout=2.6,          -- seconds without a hit that reset the perfect-hit combo
 ComboCap=10,
 PerfectMult=1.5,
 HitShare=.35,              -- each hit pays this share of the ore value per 100% of its HP
 LuckSpread=3,              -- pickaxe luck L multiplies the rarest ore's weight by 1+L*3
 StrengthBonusPerPoint=.004,-- +0.4% damage per Strength above the pickaxe requirement
 StrengthBonusMax=.6,
 -- Ore value scales with the deepest dig layer the player has unlocked (dogs scale the same way),
 -- so mining stays a strong active bonus at every stage without replacing the dog loop.
 LayerValue={1,3,6,12,24},
 -- XP only for broken ores (no per-hit XP): BreakXP + BreakXPPerTier*(ore tier-1).
 BreakXP=2,BreakXPPerTier=1,PickaxeXP=12,
 -- Timing circles (fractions of the pickaxe Window): clicks before GoodFrom are "too early",
 -- PerfectFrom..PerfectTo is the gold band, after 1.0 the circle is missed.
 Timing={GoodFrom=.45,PerfectFrom=.72,PerfectTo=.93,ServerSlack=.06,LateGrace=.2},
 MinHitGap=.09,
 MinLiftTime=.4,           -- server floor for one lift of the tap minigame (on top of the weight rest)
 Client={RespawnDelay=.18,BreakPause=1.4,RepOverhead=1.0,HumanGap=.16},
 Ores={
  {Id='Limestone',Name='Limestone',RU='Известняк',Icon='🪨',Rarity='Common',RarityRU='Обычная',Weight=30,HP=16,ValueMin=40,ValueMax=55,
   Visual={Style='Plain',Rock={196,188,166},RockMaterial='Slate'}},
  {Id='Coal',Name='Coal',RU='Уголь',Icon='⚫',Rarity='Common',RarityRU='Обычная',Weight=19,HP=22,ValueMin=65,ValueMax=90,
   Visual={Style='Nugget',Rock={70,68,66},RockMaterial='Slate',Accent={24,24,27},AccentMaterial='Basalt',Reflectance=0}},
  {Id='Copper',Name='Copper Ore',RU='Медная руда',Icon='🟠',Rarity='Common',RarityRU='Обычная',Weight=14,HP=28,ValueMin=105,ValueMax=145,
   Visual={Style='Nugget',Rock={120,104,92},RockMaterial='Rock',Accent={214,118,58},AccentMaterial='Metal',Reflectance=.2}},
  {Id='Iron',Name='Iron Ore',RU='Железная руда',Icon='⚙️',Rarity='Uncommon',RarityRU='Необычная',Weight=10.5,HP=36,ValueMin=170,ValueMax=230,
   Visual={Style='Banded',Rock={104,98,96},RockMaterial='Rock',Accent={196,206,222},AccentMaterial='Metal',Reflectance=.3}},
  {Id='Gold',Name='Gold Vein',RU='Золотая жила',Icon='🟡',Rarity='Uncommon',RarityRU='Необычная',Weight=8,HP=46,ValueMin=300,ValueMax=400,
   Visual={Style='Nugget',Rock={104,92,78},RockMaterial='Rock',Accent={255,201,64},AccentMaterial='Foil',Reflectance=.35,Glow=.6,FX='Sparkle'}},
  {Id='Quartz',Name='Quartz',RU='Кварц',Icon='🔹',Rarity='Rare',RarityRU='Редкая',Weight=6,HP=58,ValueMin=475,ValueMax=625,
   Visual={Style='Crystal',Rock={150,148,150},RockMaterial='Slate',Accent={232,238,248},AccentMaterial='Glass',Crystals=8,CrystalTransparency=.2}},
  {Id='Amethyst',Name='Amethyst',RU='Аметист',Icon='🟣',Rarity='Rare',RarityRU='Редкая',Weight=4.5,HP=72,ValueMin=750,ValueMax=1000,
   Visual={Style='Crystal',Rock={92,84,98},RockMaterial='Slate',Accent={164,92,226},AccentMaterial='Glass',Core={208,150,255},Crystals=9,Glow=.8}},
  {Id='Ruby',Name='Ruby',RU='Рубин',Icon='❤️',Rarity='Epic',RarityRU='Эпическая',Weight=3.3,HP=90,ValueMin=1300,ValueMax=1700,
   Visual={Style='Crystal',Rock={88,74,72},RockMaterial='Slate',Accent={226,36,66},AccentMaterial='Glass',Core={255,96,120},Crystals=9,Glow=1}},
  {Id='Emerald',Name='Emerald',RU='Изумруд',Icon='💚',Rarity='Epic',RarityRU='Эпическая',Weight=2.2,HP=112,ValueMin=2200,ValueMax=2900,
   Visual={Style='Crystal',Rock={74,86,78},RockMaterial='Slate',Accent={30,196,110},AccentMaterial='Glass',Core={120,255,170},Crystals=10,Glow=1}},
  {Id='Diamond',Name='Diamond',RU='Алмаз',Icon='💎',Rarity='Legendary',RarityRU='Легендарная',Weight=1.3,HP=140,ValueMin=3750,ValueMax=4750,
   Visual={Style='Crystal',Rock={70,78,92},RockMaterial='Slate',Accent={170,236,255},AccentMaterial='Glass',Core={235,252,255},Crystals=11,Glow=1.4,FX='Sparkle',CrystalTransparency=.05}},
  {Id='Meteorite',Name='Meteorite',RU='Метеорит',Icon='☄️',Rarity='Mythic',RarityRU='Мифическая',Weight=.7,HP=180,ValueMin=6500,ValueMax=8500,
   Visual={Style='Meteor',Rock={46,40,40},RockMaterial='CrackedLava',Accent={255,120,40},Glow=1.6,FX='Ember',FXColor={255,150,60}}},
  {Id='VoidCrystal',Name='Void Crystal',RU='Кристалл Пустоты',Icon='🌌',Rarity='Secret',RarityRU='Секретная',Weight=.25,HP=240,ValueMin=12000,ValueMax=16000,
   Visual={Style='Void',Rock={34,22,52},RockMaterial='Basalt',Accent={176,80,255},AccentMaterial='Neon',Crystals=12,CrystalTransparency=.15,Glow=2,FX='Void',FXColor={200,130,255}}},
 },
 -- Every pickaxe changes HOW you mine, not only damage:
 -- Window = seconds a circle takes to close, Circles = targets on the ore at once,
 -- Crit = server-rolled critical hits, Combo = stacking damage for consecutive perfect hits,
 -- Luck = rarer ores after each break, CoinBonus = more coins from every ore.
 Pickaxes={
  {Id='Wooden',Name='Wooden Pickaxe',RU='Деревянная кирка',Icon='🪵',Price=600,Strength=0,Damage=1,Window=1.05,Circles=1,
   CritChance=0,CritMult=2,Luck=0,CoinBonus=0,FX=1,Color={145,101,62},
   Trait='Many hits: learn to hit the circles',TraitRU='Много ударов: учись попадать в круги',
   Visual={Shaft={132,90,52},Head={150,108,70},HeadMaterial='WoodPlanks',Trim={90,64,40}}},
  {Id='Stone',Name='Stone Pickaxe',RU='Каменная кирка',Icon='🪨',Price=7500,Strength=25,Damage=2,Window=1.0,Circles=1,
   CritChance=.05,CritMult=2,Luck=.1,CoinBonus=0,FX=2,Color={132,137,143},
   Trait='x2 damage · 5% crits · rarer ore more often',TraitRU='Урон x2 · криты 5% · чаще редкая руда',
   Visual={Shaft={128,88,50},Head={128,130,134},HeadMaterial='Slate',Trim={70,70,72}}},
  {Id='Iron',Name='Iron Pickaxe',RU='Железная кирка',Icon='⚙️',Price=45000,Strength=80,Damage=4,Window=.95,Circles=1,
   CritChance=.07,CritMult=2,ComboStep=.03,ComboMax=.3,Luck=.15,CoinBonus=.1,FX=3,Color={173,181,190},
   Trait='Combo: perfect streaks give up to +30% damage',TraitRU='Комбо: серия идеальных ударов до +30% урона',
   Visual={Shaft={110,76,46},Head={178,184,192},HeadMaterial='Metal',Trim={60,62,66}}},
  {Id='Steel',Name='Steel Pickaxe',RU='Стальная кирка',Icon='🛡️',Price=260000,Strength=180,Damage=6,Window=.9,Circles=2,
   CritChance=.09,CritMult=2,ComboStep=.04,ComboMax=.4,Luck=.25,CoinBonus=.15,FX=4,Color={118,154,176},
   Trait='2 circles at once · combo up to +40% · +15% coins',TraitRU='2 круга сразу · комбо до +40% · +15% монет',
   Visual={Shaft={58,62,70},ShaftMaterial='Metal',Head={140,170,190},HeadMaterial='DiamondPlate',Trim={30,34,40},GripMaterial='Leather'}},
  {Id='Crystal',Name='Crystal Pickaxe',RU='Кристальная кирка',Icon='💎',Price=1600000,Strength=340,Damage=11,Window=.85,Circles=2,
   CritChance=.12,CritMult=2.2,PerfectMult=1.8,ComboStep=.05,ComboMax=.5,Luck=.35,CoinBonus=.3,FX=5,Color={111,221,235},
   Trait='Perfect hit x1.8 · 12% crits · +30% coins',TraitRU='Идеальный удар x1.8 · криты 12% · +30% монет',
   Visual={Shaft={70,80,96},ShaftMaterial='Metal',Head={120,230,245},HeadMaterial='Glass',Trim={40,60,80},Glow={150,240,255},Gem={170,250,255},FX='Sparkle'}},
  {Id='Inferno',Name='Inferno Pickaxe',RU='Адская кирка',Icon='🔥',Price=12000000,Strength=580,Damage=24,Window=.8,Circles=3,
   CritChance=.18,CritMult=2.5,PerfectMult=1.8,ComboStep=.05,ComboMax=.6,Luck=.5,CoinBonus=.55,FX=6,Color={255,103,49},
   Trait='3 circles · fiery crits x2.5 · +55% coins',TraitRU='3 круга · огненные криты x2.5 · +55% монет',
   Visual={Shaft={40,30,30},ShaftMaterial='Metal',Head={255,96,40},HeadMaterial='CrackedLava',Trim={20,16,16},Glow={255,140,40},Spikes=3,SpikeColor={255,190,60},FX='Ember'}},
  {Id='Voidbreaker',Name='Voidbreaker',RU='Разломщик Пустоты',Icon='🌌',Price=95000000,Strength=900,Damage=125,Window=.8,Circles=3,
   CritChance=.25,CritMult=3,PerfectMult=2,ComboStep=.05,ComboMax=.6,Luck=.8,CoinBonus=1,FX=7,Color={184,75,255},
   Trait='Breaks ANY ore in 1-2 hits · x2 coins',TraitRU='Ломает ЛЮБУЮ руду за 1-2 удара · x2 монет',
   Visual={Shaft={24,16,36},ShaftMaterial='Metal',Head={150,60,255},HeadMaterial='Neon',Trim={60,30,90},Glow={200,120,255},Gem={240,200,255},Halo={190,110,255},FX='Void',Length=4.6,Span=1.8}},
 },
 -- First weight is free. Each weight trains Strength up to its Cap; the next weight needs
 -- Strength (and Coins) to unlock. Pickaxe Strength gates are each reachable with the weights.
 Weights={
  {Id='Dumbbell',Name='Light Dumbbell',RU='Лёгкая гантель',Icon='🥉',Price=0,Strength=0,Gain=1,Cap=40,Cooldown=1.0,Color={160,170,180},
   Visual={Shape='Dumbbell'}},
  {Id='Kettlebell',Name='Iron Kettlebell',RU='Железная гиря',Icon='⚫',Price=3000,Strength=25,Gain=1,Cap=100,Cooldown=1.05,Color={70,76,84},
   Visual={Shape='Kettlebell'}},
  {Id='Barbell',Name='Heavy Barbell',RU='Тяжёлая штанга',Icon='🏋️',Price=20000,Strength=75,Gain=2,Cap=200,Cooldown=1.1,Color={52,56,64},
   Visual={Shape='Barbell',Trim={200,40,40}}},
  {Id='SteelBlock',Name='Steel Block',RU='Стальной блок',Icon='🧱',Price=120000,Strength=170,Gain=3,Cap=380,Cooldown=1.15,Color={118,144,162},
   Visual={Shape='Block',Material='DiamondPlate'}},
  {Id='CrystalWeight',Name='Crystal Weight',RU='Кристальная гиря',Icon='💠',Price=750000,Strength=330,Gain=4,Cap=620,Cooldown=1.2,Color={95,218,232},
   Visual={Shape='Orb',Material='Glass',Transparency=.15,Glow={150,240,255},FX='Sparkle'}},
  {Id='InfernoCore',Name='Inferno Core',RU='Инферно-ядро',Icon='🔥',Price=5000000,Strength=560,Gain=5,Cap=940,Cooldown=1.25,Color={249,91,45},
   Visual={Shape='Orb',Material='CrackedLava',Glow={255,140,40},FX='Ember',Ring={255,170,60}}},
  {Id='VoidMass',Name='Void Mass',RU='Масса Пустоты',Icon='🌑',Price=38000000,Strength=880,Gain=6,Cap=1100,Cooldown=1.3,Color={60,24,96},
   Visual={Shape='Orb',Material='Basalt',Glow={190,110,255},FX='Void',Ring={176,80,255}}},
 },
}
return M
