-- Active Mining tuning (shared by client and server; exposed as Config.Mining).
-- Balance model and the simulator: docs/MINING.md, tools/balance_sim.py.
local M={
 Version=3,
 StudioCheats=false,       -- F8 test panel in Studio also on a published place (writes the real DataStore!)
 MaxStrength=1100,          -- trained (legacy) + UPGRADE TREE strength is capped here
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
 -- Stone (p.Resources.Stone, spent on plot decor): a broken ore grants its Stone (Limestone 4,
 -- Coal 2, Copper 1; metals and gems pay Coins only), +StoneLayerBonus of that per dig layer
 -- beyond the first (Limestone 4/5/6/7/8 on layers 1-5). Rates: docs/BALANCE.md.
 StoneLayerBonus=.25,
 -- XP only for broken ores (no per-hit XP): BreakXP + BreakXPPerTier*(ore tier-1).
 BreakXP=2,BreakXPPerTier=1,PickaxeXP=12,
 -- Timing circles (fractions of the pickaxe Window): clicks before GoodFrom are "too early",
 -- PerfectFrom..PerfectTo is the gold band, after 1.0 the circle is missed.
 Timing={GoodFrom=.45,PerfectFrom=.72,PerfectTo=.93,ServerSlack=.06,LateGrace=.2},
 MinHitGap=.09,
 MinLiftTime=.4,           -- server floor for one lift of the tap minigame (on top of the weight rest)
 Client={RespawnDelay=.18,BreakPause=1.4,RepOverhead=1.0,HumanGap=.16},
 Ores={
  {Id='Limestone',Name='Limestone',RU='Известняк',Icon='🪨',Rarity='Common',RarityRU='Обычная',Weight=30,HP=12,ValueMin=125,ValueMax=165,Stone=4,
   Visual={Style='Plain',Rock={196,188,166},RockMaterial='Slate',Rock2={226,216,190},Speckle={150,140,120},Vein={240,232,214},Fossil={236,226,200}}},
  {Id='Coal',Name='Coal',RU='Уголь',Icon='⚫',Rarity='Common',RarityRU='Обычная',Weight=19,HP=16,ValueMin=170,ValueMax=200,Stone=2,
   Visual={Style='Nugget',Rock={70,68,66},RockMaterial='Slate',Accent={24,24,27},AccentMaterial='Basalt',Reflectance=0,Rock2={92,88,84},Speckle={40,40,44},Vein={150,110,60},Ember={255,120,40}}},
  {Id='Copper',Name='Copper Ore',RU='Медная руда',Icon='🟠',Rarity='Common',RarityRU='Обычная',Weight=14,HP=21,ValueMin=205,ValueMax=245,Stone=1,
   Visual={Style='Nugget',Rock={120,104,92},RockMaterial='Rock',Accent={214,118,58},AccentMaterial='Metal',Reflectance=.2,Rock2={140,122,104},Speckle={60,178,140},Vein={232,140,70}}},
  {Id='Iron',Name='Iron Ore',RU='Железная руда',Icon='⚙️',Rarity='Uncommon',RarityRU='Необычная',Weight=10.5,HP=27,ValueMin=250,ValueMax=295,
   Visual={Style='Banded',Rock={104,98,96},RockMaterial='Rock',Accent={196,206,222},AccentMaterial='Metal',Reflectance=.3,Rock2={126,112,104},Speckle={176,92,52},Vein={214,222,236}}},
  {Id='Gold',Name='Gold Vein',RU='Золотая жила',Icon='🟡',Rarity='Uncommon',RarityRU='Необычная',Weight=8,HP=34,ValueMin=300,ValueMax=400,
   Visual={Style='Nugget',Rock={104,92,78},RockMaterial='Rock',Accent={255,201,64},AccentMaterial='Foil',Reflectance=.35,Glow=.6,FX='Sparkle',Rock2={124,108,88},Speckle={255,226,120},Vein={255,214,90}}},
  {Id='Quartz',Name='Quartz',RU='Кварц',Icon='🔹',Rarity='Rare',RarityRU='Редкая',Weight=6,HP=44,ValueMin=475,ValueMax=625,
   Visual={Style='Crystal',Rock={150,148,150},RockMaterial='Slate',Accent={232,238,248},AccentMaterial='Glass',Crystals=8,CrystalTransparency=.2,Rock2={176,172,170},Speckle={220,230,240},Core={250,252,255},Vein={200,220,240}}},
  {Id='Amethyst',Name='Amethyst',RU='Аметист',Icon='🟣',Rarity='Rare',RarityRU='Редкая',Weight=4.5,HP=54,ValueMin=750,ValueMax=1000,
   Visual={Style='Crystal',Rock={92,84,98},RockMaterial='Slate',Accent={164,92,226},AccentMaterial='Glass',Core={208,150,255},Crystals=9,Glow=.8,Rock2={120,108,128},Speckle={200,150,255},Vein={190,120,250},Geode=true}},
  {Id='Ruby',Name='Ruby',RU='Рубин',Icon='❤️',Rarity='Epic',RarityRU='Эпическая',Weight=3.3,HP=68,ValueMin=1300,ValueMax=1700,
   Visual={Style='Crystal',Rock={88,74,72},RockMaterial='Slate',Accent={226,36,66},AccentMaterial='Glass',Core={255,96,120},Crystals=9,Glow=1,Rock2={112,92,88},Speckle={255,120,140},Vein={240,60,90},FX='Sparkle',FXColor={255,140,160}}},
  {Id='Emerald',Name='Emerald',RU='Изумруд',Icon='💚',Rarity='Epic',RarityRU='Эпическая',Weight=2.2,HP=84,ValueMin=2200,ValueMax=2900,
   Visual={Style='Crystal',Rock={74,86,78},RockMaterial='Slate',Accent={30,196,110},AccentMaterial='Glass',Core={120,255,170},Crystals=10,Glow=1,Rock2={96,112,100},Speckle={120,255,180},Vein={40,220,130},FX='Sparkle',FXColor={150,255,190}}},
  {Id='Diamond',Name='Diamond',RU='Алмаз',Icon='💎',Rarity='Legendary',RarityRU='Легендарная',Weight=1.3,HP=105,ValueMin=3750,ValueMax=4750,
   Visual={Style='Crystal',Rock={70,78,92},RockMaterial='Slate',Accent={170,236,255},AccentMaterial='Glass',Core={235,252,255},Crystals=11,Glow=1.4,FX='Sparkle',CrystalTransparency=.05,Rock2={92,102,120},Speckle={220,250,255},Vein={170,236,255},Prism=true}},
  {Id='Meteorite',Name='Meteorite',RU='Метеорит',Icon='☄️',Rarity='Mythic',RarityRU='Мифическая',Weight=.7,HP=135,ValueMin=6500,ValueMax=8500,
   Visual={Style='Meteor',Rock={46,40,40},RockMaterial='CrackedLava',Accent={255,120,40},Glow=1.6,FX='Ember',FXColor={255,150,60},Rock2={70,52,46},Speckle={255,200,90},Vein={255,90,30}}},
  {Id='VoidCrystal',Name='Void Crystal',RU='Кристалл Пустоты',Icon='🌌',Rarity='Secret',RarityRU='Секретная',Weight=.25,HP=180,ValueMin=12000,ValueMax=16000,
   Visual={Style='Void',Rock={34,22,52},RockMaterial='Basalt',Accent={176,80,255},AccentMaterial='Neon',Crystals=12,CrystalTransparency=.15,Glow=2,FX='Void',FXColor={200,130,255},Rock2={54,34,82},Speckle={240,200,255},Vein={120,240,255},Core={255,220,255}}},
 },
 -- Every pickaxe changes HOW you mine, not only damage:
 -- Window = seconds a circle takes to close, Circles = targets on the ore at once,
 -- Crit = server-rolled critical hits, Combo = stacking damage for consecutive perfect hits,
 -- Luck = rarer ores after each break, CoinBonus = more coins from every ore.
 -- DOGROTS pickaxe pack (v3): a starter + 15 themed pickaxes, bought in order. Theme = hit / crit
 -- effects (MiningClient.PickFX), Swing = character animation, Sound = sound kit (MiningAudio.Kits:
 -- Swing, Hit, Perfect, Crit, Draw, Break), Visual.Kind = procedural model (MiningModels.Pickaxe),
 -- FX = coarse 1..7 tier the older effects scale with. Saves from the 7-pickaxe list (v2) are mapped by
 -- MiningRules.Normalize (LEGACY_PICKAXES), never downgraded.
 Pickaxes={
  {Id='Wooden',Name='Wooden Pickaxe',RU='Деревянная кирка',Icon='🪵',Rarity='Common',Price=750,Strength=0,Damage=1,Window=1.05,Circles=1,
   CritChance=0,CritMult=2,Luck=0,CoinBonus=0,FX=1,Theme='Wood',Swing='Chop',Sound='Wood',Color={145,101,62},
   Trait='Many hits: learn to hit the circles',TraitRU='Много ударов: учись попадать в круги',
   Lore='Every legend starts with a stick.',LoreRU='Каждая легенда начинается с палки.',
   Visual={Kind='Classic',Shaft={132,90,52},Head={150,108,70},HeadMaterial='WoodPlanks',Trim={90,64,40}}},
  {Id='ButterflyNet',Name='Butterfly Catcher',RU='Сачок Ловец Бабочек',Icon='🦋',Rarity='Uncommon',Price=5000,Strength=10,Damage=2,Window=1.0,Circles=2,
   CritChance=.04,CritMult=2,ComboStep=.02,ComboMax=.2,Luck=.05,CoinBonus=0,FX=1,Theme='Butterfly',Swing='Scoop',Sound='Fairy',Color={120,214,255},Inspect=true,
   Trait='2 circles · glowing butterflies and fireflies fly out of every hit',TraitRU='2 круга · из каждого удара вылетают светящиеся бабочки и светлячки',
   Lore='A strange but charming net-pickaxe. Instead of a net, a magic glowing film where butterflies and fireflies flutter all the time. Light and fairy-tale.',
   LoreRU='Странный, но очаровательный сачок-кирка. Вместо обычной сетки — магическая светящаяся плёнка, в которой постоянно порхают бабочки и светлячки. Лёгкий и сказочный.',
   -- "Сачок Ловец Бабочек" concept look (MiningModels DESIGNS.Net, rarity from the sheet: Uncommon / Cute Weird);
   -- Polish=false: no generic pommel gem; Swing='Scoop' (MiningClient.Anim: a sweeping butterfly-catching
   -- scoop and the inspect that shows the film); IconViewport: the market tile shows the hoop (IconFocus /
   -- IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Net',Length=3.6,Shaft={188,224,246},ShaftMaterial='SmoothPlastic',Head={180,190,238},Film={136,192,255},Accent={124,200,244},
    Trim={136,206,70},Gold={246,204,86},Polish=false,IconViewport=true,PreviewDist=15,PreviewBase={0,.6,0,0,0,-24},IconFocus={0,2.98,0},IconDist=6.6}},
  {Id='LegoHand',Name='LEGO Hand',RU='LEGO-Рука',Icon='🧱',Rarity='Rare',Price=25000,Strength=25,Damage=3,Window=1.0,Circles=2,
   CritChance=.05,CritMult=2,ComboStep=.02,ComboMax=.2,Luck=.1,CoinBonus=.05,FX=2,Theme='Brick',Swing='Clack',Sound='Plastic',Color={255,206,30},Inspect=true,
   Trait='Hits rain plastic bricks and sparkles · +5% coins',TraitRU='Удары сыпят пластиковые кубики и искры · +5% монет',
   Lore='A giant minifig hand turned into a pickaxe. Classic plastic shine, bright and silly: simple, but full of charisma, always ready to build up new finds.',
   LoreRU='Огромная рука лего-человечка, превращённая в кирку. Классический пластиковый блеск, яркий и смешной дизайн. Простая, но максимально харизматичная кирка, всегда готовая к сборке новых находок!',
   -- "LEGO-Рука" concept look (MiningModels DESIGNS.Lego, rarity from the sheet: Rare / Meme); Polish=false: no
   -- generic pommel gem / aura (the hand has its own glow and sparkles); Swing='Clack' (MiningClient.Anim: a
   -- bouncy plastic slam and the ratchet-spin inspect); IconViewport: the market tile shows the 3D hand
   -- (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Lego',Length=4.4,Shaft={34,36,46},ShaftMaterial='SmoothPlastic',Head={255,200,24},Trim={222,32,36},Accent={28,98,214},
    White={242,242,236},Stud={255,150,32},Polish=false,IconViewport=true,PreviewDist=15,IconFocus={.75,2.9,0},IconDist=8.6}},
  {Id='SixSeven',Name='Pickaxe 67',RU='Кирка 67',Icon='6️⃣',Rarity='Epic',Price=100000,Strength=60,Damage=4,Window=.95,Circles=2,
   CritChance=.067,CritMult=2.67,PerfectMult=1.6,ComboStep=.03,ComboMax=.3,Luck=.15,CoinBonus=.1,FX=3,Theme='Digits',Swing='SixSeven',Sound='Digital',Color={235,40,52},Inspect=true,
   Trait='6.7% crits x2.67 · glitch hits · crits print a GIANT 67',TraitRU='Криты 6.7% x2.67 · глитч-удары · крит печатает ОГРОМНОЕ 67',
   Lore='A meme digit-pickaxe built round a big 6 and a big 7. Scratches, graffiti, stickers, chrome details and digital effects: an aggressive design, glitches and style.',
   LoreRU='Мемная цифро-кирка, построенная вокруг больших цифр 6 и 7. Царапины, граффити, стикеры, хромированные детали и цифровые эффекты. Сочетает агрессивный дизайн, глитч-эффекты и стильные детали.',
   -- "КИРКА 67" concept look (MiningModels DESIGNS.SixSeven, rarity from the sheet: Epic / Meme-Core); Polish=false: no
   -- generic pommel gem / aura (the head has its own red glow and sparks); Swing='SixSeven' (MiningClient.Anim: the
   -- glitching slam and the twirl inspect); IconViewport: the market tile shows the 3D head (IconFocus / IconDist);
   -- Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='SixSeven',Length=4.6,Shaft={26,24,28},ShaftMaterial='SmoothPlastic',Head={242,242,238},Black={26,24,28},Trim={235,40,52},Chrome={206,210,218},
    Polish=false,IconViewport=true,PreviewDist=15,IconFocus={0,2.45,0},IconDist=8.6}},
  {Id='GummyHorror',Name='Gummy Horror',RU='Мармеладный Ужас',Icon='🍬',Rarity='Epic',Price=400000,Strength=100,Damage=6,Window=.95,Circles=2,
   CritChance=.08,CritMult=2.2,PerfectMult=1.6,ComboStep=.03,ComboMax=.3,Luck=.2,CoinBonus=.15,FX=3,Theme='Gummy',Swing='Bounce',Sound='Squish',Color={255,46,160},Inspect=true,
   Trait='Sticky hits · caramel splashes · +15% coins',TraitRU='Липкие удары · карамельные брызги · +15% монет',
   Lore='A living gummy monster: sweet, but horribly sticky. This pickaxe craves new sweet victims... Sweetness can be terrifying.',
   LoreRU='Живой мармеладный монстр, который сладкий, но ужасающе липкий. Эта кирка жаждет новых сладких жертв... Сладость может быть ужасной.',
   -- "Кирка Мармеладный ужас" concept look (MiningModels DESIGNS.Gummy); Polish=false: no generic pommel gem / aura,
   -- IconViewport: the market tile shows the 3D head (IconFocus / IconDist); Inspect: T / gamepad Y / touch button.
   Visual={Kind='Gummy',Length=4.4,Shaft={160,124,108},ShaftMaterial='Wood',Head={255,46,160},Accent={150,232,40},Trim={255,226,50},Polish=false,IconViewport=true,PreviewDist=12.5,IconFocus={0,2.45,0},IconDist=6.4}},
  {Id='SlimeSlug',Name='Rotten Slime Slug',RU='Слизень-Гнилушка',Icon='🐌',Rarity='Epic',Price=1500000,Strength=150,Damage=8,Window=.92,Circles=3,
   CritChance=.09,CritMult=2.3,PerfectMult=1.7,ComboStep=.04,ComboMax=.4,Luck=.25,CoinBonus=.2,FX=4,Theme='Slime',Swing='Slurp',Sound='Slime',Color={136,180,70},Inspect=true,
   Trait='3 circles · eyes pop out on slime threads · rotten splats',TraitRU='3 круга · глаза вылетают на слизевых нитях · гнилостный сплэт',
   Lore='A nasty, living, slimy pickaxe with a fat slug living in it. It keeps oozing sticky goo, wriggles and stares at you with its weird eyes. Gross, but damn funny!',
   LoreRU='Мерзкая, живая, слизневая кирка, в которой обитает толстый слизень. Он постоянно выделяет липкую жижу, шевелится и смотрит на тебя своими странными глазами. Гадко, но чертовски забавно!',
   -- "Кирка Слизень-Гнилушка" concept look (MiningModels DESIGNS.Slug, rarity from the sheet: Epic / Мерзкая / Гнилостная);
   -- Polish=false: no generic pommel gem / aura (the slime has its own glow and falling drops); Swing='Slurp'
   -- (MiningClient.Anim: the sticky chop that pulls off the ore, and the inspect that shows the big eye and the shell);
   -- IconViewport: the market tile shows the 3D head (IconFocus / IconDist); Inspect: T / gamepad Y / touch button.
   -- Stats, price and slot unchanged.
   Visual={Kind='Slug',Length=4.8,Shaft={92,74,62},ShaftMaterial='Wood',Head={176,166,102},Accent={168,226,52},Trim={122,116,90},
    Polish=false,IconViewport=true,PreviewDist=15,IconFocus={0,2.55,0},IconDist=10.5}},
  {Id='AlarmClock',Name='Toothy Alarm Clock',RU='Зубастый Будильник',Icon='⏰',Rarity='Epic',Price=5000000,Strength=220,Damage=11,Window=.9,Circles=3,
   CritChance=.1,CritMult=2.3,PerfectMult=1.7,ComboStep=.04,ComboMax=.4,Luck=.3,CoinBonus=.25,FX=4,Theme='Alarm',Swing='Alarm',Sound='Alarm',Color={232,40,40},Inspect=true,
   Trait='3 circles · knife hands · rings and screams on every hit · flying clocks',TraitRU='3 круга · стрелки-ножи · звенит и орёт при каждом ударе · вылетающие часы',
   Lore='A living alarm clock that never wants you to stop. A huge mouth with sharp teeth, mad eyes and spinning hands. It rings, screams and bites everything in its way.',
   LoreRU='Живой будильник, который никогда не хочет, чтобы ты остановился. Огромный рот с острыми зубами, безумные глаза и вращающиеся стрелки. Звенит, орёт и кусает всё на своём пути.',
   -- "Зубастый Будильник" concept look (MiningModels DESIGNS.Alarm, rarity from the sheet: Epic); Polish=false: no
   -- generic pommel gem / aura (the clock has its own red glow, sparks and glowing pommel core); Swing='Alarm'
   -- (MiningClient.Anim: the ringing club slam and the wind-up / turn / ring inspect); IconViewport: the market tile
   -- shows the 3D head (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Alarm',Length=4.8,Shaft={38,36,40},ShaftMaterial='Metal',Head={224,32,36},Accent={244,226,206},Trim={246,196,82},
    Polish=false,IconViewport=true,PreviewDist=16,IconFocus={0,3.0,0},IconDist=10.5}},
  {Id='Ponycorn',Name='Ponycorn-Dolphoodle',RU='Понирог-Дельфудель',Icon='🦄',Rarity='Mythic',Price=15000000,Strength=300,Damage=15,Window=.88,Circles=3,
   CritChance=.12,CritMult=2.4,PerfectMult=1.8,ComboStep=.05,ComboMax=.5,Luck=.38,CoinBonus=.32,FX=5,Theme='Rainbow',Swing='Prance',Sound='Magic',Color={255,150,210},Inspect=true,
   Trait='Rainbow flashes, stars and hearts · +32% coins',TraitRU='Радужные вспышки, звёзды и сердечки · +32% монет',
   Lore='A magic pickaxe where pony kindness, unicorn magic, dolphin grace and poodle fluff became one. Made of dreams, rainbows and sweet magic.',
   LoreRU='Волшебная кирка, в которой слились доброта пони, магия единорога, грация дельфина и пушистое обаяние пуделя. Создана из снов, радуги и сладкого волшебства.',
   -- "Кирка Понирог-Дельфудель" concept look (MiningModels DESIGNS.Ponycorn, rarity from the sheet: Mythic);
   -- Polish=false: no generic pommel gem / orbit gems; IconViewport: the market tile shows the 3D head
   -- (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Ponycorn',Shaft={255,200,84},ShaftMaterial='Glass',Head={255,226,158},Accent={255,92,164},Fin={130,206,255},Trim={255,246,252},
    Polish=false,IconViewport=true,PreviewDist=15.5,IconFocus={0,2.6,0},IconDist=7.6}},
  {Id='Frankenzombie',Name='Zombie-Frankenstein',RU='Зомби-Франкенштейн',Icon='🧟',Rarity='Legendary',Price=40000000,Strength=380,Damage=20,Window=.86,Circles=3,
   CritChance=.14,CritMult=2.5,PerfectMult=1.8,ComboStep=.05,ComboMax=.5,Luck=.45,CoinBonus=.4,FX=5,Theme='Zombie',Swing='Franken',Sound='Electric',Color={110,160,110},Inspect=true,
   Trait='Electric spasm hits · blue lightning · shards and slime · +40% coins',TraitRU='Электрические удары-спазмы · синие молнии · осколки и слизь · +40% монет',
   Lore='A cursed pickaxe assembled from parts of dead bodies, old machines and forgotten experiments. Somewhere a spark of life still beats, somewhere the wires still twitch. It was never whole, and that is its power.',
   LoreRU='Проклятая кирка, собранная из частей мёртвых тел, старых машин и забытых экспериментов. Где-то ещё бьётся искра жизни, где-то дёргаются провода. Она никогда не была целой — и в этом её сила.',
   -- "Кирка Зомби-Франкенштейн" concept look (MiningModels DESIGNS.Zombie, rarity from the sheet: Legendary / Undead);
   -- Polish=false: no generic pommel gem / aura (the machine eye, the coil and the vial have their own glow);
   -- Swing='Franken' (MiningClient.Anim: the electric spasm slam and the seam-lightning inspect); IconViewport: the
   -- market tile shows the 3D head (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Zombie',Length=5,Shaft={232,220,186},ShaftMaterial='Limestone',Head={132,170,64},Accent={60,150,255},Trim={166,84,44},
    Dark={70,68,74},Slime={168,232,40},Flesh={186,112,112},Polish=false,IconViewport=true,PreviewDist=17,IconFocus={-.5,3.15,0},IconDist=13}},
  {Id='ClownChrono',Name='Clown Chronomord',RU='Клоун-Хрономорд',Icon='🤡',Rarity='Legendary',Price=100000000,Strength=470,Damage=27,Window=.85,Circles=3,
   CritChance=.16,CritMult=2.6,PerfectMult=1.85,ComboStep=.05,ComboMax=.55,Luck=.5,CoinBonus=.5,FX=6,Theme='Clown',Swing='Chrono',Sound='Clown',Color={214,58,58},Inspect=true,
   Trait='Tongue strikes · clocks running backwards · flying pocket watches · +50% coins',TraitRU='Удар языком · часы идут назад · летающие карманные часы · +50% монет',
   Lore='A mad pickaxe with a clown and a clock. Funny and creepy at the same time: bulging eyes, a long tongue, mechanical parts and clocks that never stop moving.',
   LoreRU='Безумная кирка с клоуном и часами. Выглядит одновременно смешно и жутко. Выпученные глаза, длинный язык, механические детали и постоянное движение часов.',
   -- "Клоун-Хрономорд" concept look (MiningModels DESIGNS.Clown, rarity from the sheet: Legendary / Cursed Funny);
   -- Polish=false: no generic pommel gem / aura (the clock has its own warm light and gold sparks); Swing='Chrono'
   -- (MiningClient.Anim: the big red-arc chop and the rewind / turn / laugh inspect); IconViewport: the market tile
   -- shows the 3D clown and clock (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Clown',Length=5,Shaft={240,226,200},ShaftMaterial='SmoothPlastic',Head={246,232,210},Accent={60,110,220},Trim={214,48,52},Gold={222,168,58},
    Polish=false,IconViewport=true,PreviewDist=18,IconFocus={0,2.75,0},IconDist=10}},
  {Id='NastyOctopus',Name='Nasty Octopus',RU='Мерзкий Спрут',Icon='🐙',Rarity='Legendary',Price=250000000,Strength=560,Damage=36,Window=.84,Circles=4,
   CritChance=.18,CritMult=2.7,PerfectMult=1.9,ComboStep=.05,ComboMax=.6,Luck=.58,CoinBonus=.6,FX=6,Theme='Ink',Swing='Octo',Sound='Wet',Color={74,132,240},Inspect=true,
   Trait='4 circles · water & ink splashes · tentacle-lash crits · +60% coins',TraitRU='4 круга · брызги воды и чернил · криты ударом щупальца · +60% монет',
   Lore='It watches. It drips. It digs. A grotesque octopus fused into a pickaxe: its single huge eye watches everything it digs, its tentacles writhe with unnatural life, dripping with seawater, ink and something darker. The deeper you go, the hungrier it gets.',
   LoreRU='Оно смотрит. Оно капает. Оно копает. Гротескный спрут, сросшийся с киркой: единственный огромный глаз следит за всем, что она копает, щупальца извиваются неестественной жизнью, с них капает морская вода, чернила и что-то потемнее. Чем глубже копаешь, тем голоднее она становится.',
   -- "Кирка Мерзкий Спрут" / GROSS OCTOPICK concept look (MiningModels DESIGNS.Octopus, rarity from the sheet: Legendary / Ocean Horror);
   -- Polish=false: no generic pommel gem / aura (the eye has its own warm light and the head its own drips); Swing='Octo'
   -- (MiningClient.Anim: the wet tentacle-lash chop and the curious-eye / cursed-pearl / ink-sac inspect); IconViewport: the
   -- market tile shows the 3D head with its eye (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Octopus',Length=5,Shaft={118,76,44},ShaftMaterial='Wood',Head={64,120,236},Accent={255,206,48},Trim={124,72,220},
    Sucker={232,112,230},Blade={198,188,214},Polish=false,IconViewport=true,PreviewDist=17,IconFocus={0,3.0,0},IconDist=9.6}},
  {Id='HandOfFate',Name='Hand of Fate',RU='Рука Судьбы',Icon='🖐️',Rarity='Legendary',Price=600000000,Strength=660,Damage=48,Window=.83,Circles=4,
   CritChance=.2,CritMult=2.8,PerfectMult=1.9,ComboStep=.06,ComboMax=.65,Luck=.66,CoinBonus=.72,FX=7,Theme='Fate',Swing='Fate',Sound='Doom',Color={160,90,220},Inspect=true,
   Trait='4 circles · the claws grab the ore · the cursed eye opens on a crit · +72% coins',TraitRU='4 круга · когти хватают руду · проклятый глаз раскрывается на крите · +72% монет',
   Lore='A living palm with a cursed eye that seems to control fate itself. Long claws, ever-moving fingers and a creepy animation make this pickaxe unique and unforgettable. It fits the world of DOGROTS perfectly and brings madness and mystery with it.',
   LoreRU='Живая ладонь с проклятым глазом, которая словно управляет судьбой. Длинные когти, постоянно движущиеся пальцы и жуткая анимация делают эту кирку уникальной и запоминающейся. Идеально вписывается в мир DOGROTS и добавляет атмосферу безумия и мистики.',
   -- "Кирка Рука Судьбы" concept look (MiningModels DESIGNS.Fate, rarity from the sheet: Legendary); Polish=false: no
   -- generic pommel gem / aura (the eye has its own purple light, motes and drips); Swing='Fate' (MiningClient.Anim: the
   -- grabbing claw slam and the open-hand / turn / fist inspect); IconViewport: the market tile shows the 3D palm with its
   -- eye (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Fate',Length=5,Shaft={215,181,186},ShaftMaterial='SmoothPlastic',Head={215,181,186},Accent={155,47,214},Trim={78,64,72},
    Bone={242,223,191},Iron={54,48,58},Polish=false,IconViewport=true,PreviewDist=17,IconFocus={0,2.75,0},IconDist=10.5}},
  {Id='Laughsaw',Name='Laughsaw',RU='Смехопила',Icon='🪚',Rarity='Legendary',Price=1200000000,Strength=760,Damage=65,Window=.82,Circles=4,
   CritChance=.22,CritMult=2.9,PerfectMult=2,ComboStep=.06,ComboMax=.7,Luck=.74,CoinBonus=.85,FX=7,Theme='Saw',Swing='Rip',Sound='Saw',Color={230,40,40},Inspect=true,
   Trait='Spinning blade · the grin opens on every hit · sparks and blood · +85% coins',TraitRU='Крутящийся диск · пасть раскрывается при ударе · искры и брызги · +85% монет',
   Lore='A mad pickaxe with a circular blade and a huge grin. The blade never stops spinning, and the mouth opens on every hit with a sinister laugh. Sparks, blood and a mechanical shriek make every strike a show.',
   LoreRU='Безумная кирка с циркулярным лезвием и огромной улыбкой. Лезвие постоянно вращается, рот раскрывается при ударе, издавая зловещий смех. Искры, кровь и механический визг делают каждый удар максимально эффектным.',
   -- "Кирка Смехопила" concept look (MiningModels DESIGNS.Saw, rarity from the sheet: Legendary); Polish=false: no
   -- generic pommel gem / aura (the saw has its own hub light and embers); Swing='Rip' (MiningClient.Anim: the
   -- grinding saw slam and the full-turn inspect); IconViewport: the market tile shows the 3D head and blade
   -- (IconFocus / IconDist); Inspect: T / gamepad Y / touch button. Stats, price and slot unchanged.
   Visual={Kind='Saw',Length=4.6,Shaft={36,32,36},ShaftMaterial='Slate',Head={226,30,36},Red2={150,16,22},Accent={226,222,216},Trim={36,32,36},
    Iron={148,144,146},Teeth={240,224,184},Blood={170,12,18},Glow={255,138,36},Polish=false,IconViewport=true,PreviewDist=15,IconFocus={.3,3.4,0},IconDist=8.4}},
  {Id='AnimeScythe',Name='Scarlet Anime Scythe',RU='Алая Аниме-Коса',Icon='🗡️',Rarity='Mythic',Price=2500000000,Strength=860,Damage=90,Window=.8,Circles=4,
   CritChance=.25,CritMult=3,PerfectMult=2,ComboStep=.07,ComboMax=.75,Luck=.82,CoinBonus=1,FX=7,Theme='Anime',Swing='Reap',Sound='Shing',Color={235,30,60},Inspect=true,
   Trait='Purple slash trails · glowing glyphs · x2 coins',TraitRU='Фиолетовые разрезы воздуха · светящиеся иероглифы · x2 монет',
   Lore='A mighty anime scythe full of demonic energy. Glowing violet glyphs, an aggressive silhouette and flashy moves. Rare, and very stylish.',
   LoreRU='Мощная аниме-коса с демонической энергией. Светящиеся фиолетовые иероглифы, агрессивный силуэт и эффектные анимации. Редкая и очень стильная кирка.',
   -- "Алая Аниме-Коса" concept look (MiningModels DESIGNS.Scythe, rarity from the sheet: Mythic / Anime);
   -- Polish=false: no generic pommel gem / orbit gems; IconViewport: the market tile shows the 3D head and
   -- blade (IconFocus / IconDist); Swing='Reap' (MiningClient.Anim); Inspect: T / gamepad Y / touch button.
   -- Stats, price and slot unchanged.
   Visual={Kind='Scythe',Length=5.6,Shaft={44,38,46},Head={226,26,42},Accent={176,64,240},Trim={238,198,248},Iron={132,124,134},
    Polish=false,IconViewport=true,PreviewDist=15,IconFocus={1.25,2.15,0},IconDist=10.2}},
  {Id='TwinClaws',Name='Twin Claws',RU='Когти-Близнецы',Icon='🐾',Rarity='Mythic',Price=5000000000,Strength=950,Damage=120,Window=.78,Circles=5,
   CritChance=.27,CritMult=3.2,PerfectMult=2.1,ComboStep=.07,ComboMax=.8,Luck=.9,CoinBonus=1.2,FX=7,Theme='Claws',Swing='Claw',Sound='Metal',Color={235,40,64},Inspect=true,
   Trait='5 circles · right-left claw combos · cross strike · +120% coins',TraitRU='5 кругов · комбо правой-левой · перекрёстный удар · +120% монет',
   Lore='Two claws. One will. They tear. They mine. They dominate. Claws that cut a path through stone as through enemies. More than a pickaxe: an instinct.',
   LoreRU='Два когтя. Одна воля. Разрывают. Добывают. Доминируют. Когти, что прокладывают путь сквозь камень, как сквозь врагов. Больше чем кирка. Это инстинкт.',
   -- "Кирка Когти-Близнецы" concept look (MiningModels twinGauntlet, rarity from the sheet: Mythic / Combat): a pair of
   -- voxel gauntlets, 右 right with scarlet accents (Accent), 左 left with violet accents (Trim); Swing='Claw'
   -- (MiningClient.Anim: right / left swipes, a cross strike, the claw hold and run poses, the crossed-arms inspect);
   -- IconViewport + PreviewPair: the market tile and preview show both gauntlets; Inspect: T / gamepad Y / touch button.
   -- Stats, price and slot unchanged.
   Visual={Kind='Claws',Grip='Glove',Shaft={34,32,40},Head={216,214,220},Claw={206,206,214},Accent={255,34,56},Trim={168,62,255},
    Polish=false,IconViewport=true,PreviewPair=1,PreviewBase={0,1.3,0,0,0,180},PreviewDist=10.5,IconFocus={0,.9,0},IconDist=6.6}},
  {Id='TVHead',Name='TV-Head',RU='ТВ-Башка',Icon='📺',Rarity='Mythic',Price=10000000000,Strength=1050,Damage=160,Window=.78,Circles=5,
   CritChance=.3,CritMult=3.5,PerfectMult=2.2,ComboStep=.08,ComboMax=.8,Luck=1,CoinBonus=1.5,FX=7,Theme='TV',Swing='Smash',Sound='Glitch',Color={150,255,90},Inspect=true,
   Trait='5 circles · pixel explosions · x2.5 coins',TraitRU='5 кругов · пиксельные взрывы · x2.5 монет',
   Lore='An old TV that still picks up channels... the wrong ones. Its static hits reality hard. It is always watching something... and it is you.',
   LoreRU='Старый телевизор, который до сих пор ловит... не те каналы. Его помехи больно бьют по реальности. Он всегда что-то смотрит... и это на тебя.',
   -- Retro Horror concept look (MiningModels DESIGNS.TV); Polish=false: no generic pommel gem / orbit gems,
   -- IconViewport: the market tile shows the 3D model; Inspect: T / gamepad Y / touch button (MiningClient.Tool).
   Visual={Kind='TV',Shaft={36,36,40},Head={112,101,93},Accent={160,255,96},Trim={50,48,50},Polish=false,IconViewport=true,PreviewDist=12.5}},
 },
 -- Russian rarity names of the pickaxe pack (shop / toasts).
 RarityRU={Common='Обычная',Uncommon='Необычная',Rare='Редкая',Epic='Эпическая',Legendary='Легендарная',Mythic='Мифическая'},
 -- STRENGTH: the weight rack (7 weights + the lifting minigame) is gone. Strength now comes from the
 -- STRENGTH branch of the UPGRADE TREE (DogEconomy.UpgradeTree: IRON GRIP, HEAVY LIFTER, TITAN BACK,
 -- COLOSSUS, MOUNTAIN BREAKER = 1,100 Strength in all). Strength a player trained at the rack before
 -- this update is kept and counts on top (MiningRules.Strength). Pickaxe Strength needs are unchanged.
 Weights={},
}
return M