# F10. Титулы — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `trade-titles` (основной)

**Сейчас.** No titles above characters. 'Collection titles' are p.Cosmetics keys (Dex*, Finds*, Discovery:*, Set*, Event*, Prestige*, Supporter*, legacy kennel cosmetics) equipped via action 'Cosmetic' into p.EquippedCosmetic. That value is shown only as a BillboardGui over every kennel dog (DogKennelService:196 -> EconomyVisuals.client.luau:27-37, MaxDistance 40). Only Dex titles have readable names (DexRewards.TitleName). No achievement registry; scattered claim ledgers. The Server King exists only as a monument avatar. Existing character overhead: default Roblox name (NameDisplayDistance 100), EquipmentWorld hats/face/back accessories. MaxPlayers 60, StreamingEnabled.

**План.** 1) ReplicatedStorage/DogEconomy/TitleDefinitions.luau (shared, pure):
- entries {Id, Text, TextRu, Icon, Rarity ('Common'..'Secret'/'Supporter'), Color/Gradient from Kit.Theme.Rarity/RarityGradient, Category, Order, Requires}.
- Requires kinds: Stat path >= Min (e.g. 'Stats.TotalFinds'), Custom ('MuseumCount','UniqueFinds','MaxLayer','PlotLevel'), Cosmetic key (legacy mapping), Dynamic ('ServerKing'; not saved, not equipable).
- Functions Titles.Earned(p,def) and Titles.Progress(p,def) -> current, goal (same shape as PlotCatalog.Earned/Requirement).
- Starter set mapped to real fields: TREASURE HUNTER (Stats.TotalFinds>=1000), RELIC SEEKER (Stats.SecretFinds>=1), LEGENDARY DIGGER (Stats.TotalDigs>=50000 and Stats.BestTier>=8), ORE BREAKER / STONE TITAN (Mining.OresBroken 500/10000), VOID WALKER (UnlockedLayers['5']), REBORN I-V (Prestige), MAD SCIENTIST (Lab.Experiments>=100), DOG SPOTTER..DOG MASTER (existing Dex10..Dex100 cosmetics / MuseumCount), TRUSTED TRADER (CompletedTrades>=25 and TradePartners>=10), MOGUL (Lifetime.TotalCoinsEarned), VETERAN (Lifetime.TotalPlaytimeSeconds), EVENT CHAMPION (Event1..5), SUPPORTER (SupporterTitle/EventSupporter/Lifetime.SupportRobux>0), plus a name map for every legacy Finds*/Discovery:*/Set*/Prestige* key.

2) Economy/Features/Titles.luau (FeatureRegistry):
- Normalize creates p.Titles={Version=1,Equipped='',Unlocked={},New={},CheckedAt=0}.
- One-time migration: if p.EquippedCosmetic is a collection title, set Equipped to the mapped id. Do NOT change EquippedCosmetic (PlotRules migration + kennel badges).
- Evaluation is throttled (now-CheckedAt>=10) and adds Unlocked[id]=now and New[id]=true.
- Validate: structure only. Action 'TitleEquip' {Id or ''} requires Unlocked. Snapshot adds view.Titles={Equipped,Unlocked,New,Progress for the top N locked}.

3) Runtime.Project: player:SetAttribute('TitleId', equipped) (replicates only on change); push 'TitleUnlocked' once per new id (RAM dedupe). CommunityService.RefreshKing: SetAttribute('ServerKing', true/false) when the king changes.

4) Client StarterPlayerScripts/TitleTags.client.luau:
- One pooled BillboardGui per player, parented under PlayerGui (client-only, no server replication), Adornee=Head.
- StudsOffsetWorldSpace = head.Size.Y/2 + 2.3 + hat height (character:FindFirstChild(EquipmentWorld.Prefix..'Hat') bounding box). Size in studs (shrinks with distance), LightInfluence 0, AlwaysOnTop false, MaxDistance 60 (Low FX 35).
- Only the nearest 12 (mobile 8) re-evaluated every 0.5 s.
- Rarity gradient; one shared shimmer tween only for Legendary+ within 30 studs and not ReducedMotion.
- Streaming-safe: CharacterAdded/Removing, WaitForChild('Head',5), Head.AncestryChanged releases to pool.
- Optional combined nameplate: locally set Humanoid.DisplayDistanceType=None and draw name+title in the same billboard so there is one overhead element per player; fall back to the default name on failure.
- Respects client attribute TitleDisplay ('All'/'Mine'/'Off', new Settings entry) and Hide UI (F9).

5) UI Modules/TitlesScreen.luau (Kit Key='Titles'):
- CardGrid by rarity; locked cards show a progress bar from Titles.Progress; EQUIP/UNEQUIP; live preview of the billboard; NEW badges cleared via 'TitleSeen'.
- Entry from COSMETICS: replace PlotShopScreen.luau:67-77 list with an OPEN TITLES button. Also from Dogdex/finds reward toasts.

6) Declutter: EconomyVisuals shows kennel badges only for C.Cosmetics kennel items (GoldenKennel/CyberKennel/VoidAura); titles leave the dogs.

7) Tests: tests/titles.luau covers conditions, migration from EquippedCosmetic/Cosmetics, the equip guard, the throttle, and the TradePartners anti-farm rule.

**Файлы.** 
- `src/ServerScriptService/Economy/Runtime.luau`
- `src/ServerScriptService/Economy/CommunityService.luau`
- `src/ServerScriptService/Economy/Rules.luau`
- `src/ServerScriptService/Economy/RecordStats.luau`
- `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau`
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- `src/StarterGui/ScreenGui/PawpadRuntime.client.luau`
- `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `src/ReplicatedStorage/DogEconomy/DexRewards.luau`
- `src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau`

**Новые модули.** 
- `src/ReplicatedStorage/DogEconomy/TitleDefinitions.luau`
- `src/ServerScriptService/Economy/Features/Titles.luau`
- `src/StarterPlayer/StarterPlayerScripts/TitleTags.client.luau`
- `src/StarterGui/ScreenGui/Modules/TitlesScreen.luau`
- `src/ReplicatedStorage/Localization/Titles.luau`
- `tests/titles.luau`

**Совместимость данных.** All existing unlocks live in p.Cosmetics (survives MegaReset) and stay the source of truth for legacy titles. The new p.Titles is additive, nil-safe and reconstructible from Cosmetics + stats. Add 'Titles' to the MegaReset carry list (Rules.Normalize:56) to keep Equipped. Never rewrite p.EquippedCosmetic: PlotRules.Normalize reads it for profiles without PlotProgressionVersion, and kennel badges use it. Old profiles without new stats (TradePartners) simply have 0 progress; history that was never recorded is not invented (same rule as RecordStats).

**Производительность.** Evaluation throttled to once per 10 s per profile inside existing transactions (cheap numeric reads). One string attribute per player, changes only on equip. Client: at most 12 active billboards (8 mobile), pooled and never rebuilt; distance check 2 Hz; no per-frame work except an optional shimmer on <=3 nearby Legendary titles. No server-side BillboardGuis, so no replication or streaming cost.

**Объём.** M

**Риски.** Clutter with the default name, hats and 60 players: needs culling and a setting. Farmable conditions (CompletedTrades with alts, empty trades): use unique-partner/value-gated stats. Rarity colours must match Kit.Theme (tests/uikit.luau checks theme sync). Translations for every title. Server King attribute flips every 15 s at most. Do not let F8 decor keys in p.Cosmetics be treated as titles (see F8).


## Аудитор `data-network`

**Сейчас.** Титулы уже есть как ключи p.Cosmetics (Dex10..Dex100 с именами из DexRewards.TitleNames, Finds<n>, Set<name>, Prestige<n>, Event<i>, Discovery:<set>:<Normal|Heavy>). Надеваются действием 'Cosmetic' {Kind} → p.EquippedCosmetic (то же поле используют кеннели GoldenKennel/CyberKennel/VoidAura/FounderPlaque). Показываются только над собаками в кеннелях (атрибут EquippedCosmetic у модели, EconomyVisuals), не над персонажем.

**План.** Модуль Features/Titles.luau + ReplicatedStorage/TitleDefinitions.luau ({Id, Name, NameRU, Rarity, Color, Rule}). p.Titles={Version=1, Earned={[id]=unixTime}, Equipped=''}. Normalize: идемпотентный перенос из p.Cosmetics (старый ключ → ID титула) и проверка достижений по уже существующим счётчикам (Stats.TotalFinds/SecretFinds/CompletedTrades, Lifetime.*, Mining.OresBroken, количество DogDex, Prestige, Level, рекорды). Полученный титул не отзывается. Validate: Equipped=='' или Earned[Equipped]. Действие 'TitleEquip' {Id}. Проекция: атрибуты игрока TitleId/TitleRarity в Runtime.Project; клиентский модуль рисует BillboardGui над головой (отсечение по дистанции, без серверного BillboardGui). Push 'TitleEarned' для тоста. EquippedCosmetic оставить кеннелям (PlotRules переносит из него старые скины).

**Файлы.** 
- src/ServerScriptService/Economy/Runtime.luau (атрибуты титула в Project)
- src/ServerScriptService/Economy/Rules.luau (ветка 'Cosmetic' — не путать с TitleEquip)
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`

**Новые модули.** 
- `src/ServerScriptService/Economy/Features/Titles.luau`
- `src/ReplicatedStorage/TitleDefinitions.luau`
- `src/StarterPlayer/StarterPlayerScripts/OverheadTitles.client.luau`

**Совместимость данных.** Ключи p.Cosmetics не удалять. ID титулов только добавляются. Новое поле необязательно и заполняется переносом.

**Производительность.** Атрибуты на Player реплицируются всем — всего 2–3 атрибута. Billboard на клиенте с отсечением.

**Объём.** M

**Риски.** Проверка правил в Normalize идёт на каждом тике, поэтому только O(1) по счётчикам, без прохода по находкам. Пересечение с действием 'Cosmetic', которое надевает любой имеющийся ключ.


## Аудитор `economy`

**Сейчас.** Titles exist as p.Cosmetics keys + p.EquippedCosmetic: Finds* (RecordClaim), Dex*, Set*, Prestige*, Event*, Discovery:* and shop titles; the Rules.Action 'Cosmetic' equips owned ones. There is no overhead display and no rarity/colour metadata.

**План.** Add a pure ReplicatedStorage/TitleCatalog.luau: {Id, Name, Rarity, Color, Criteria(p)} over economy stats: Lifetime.TotalCoinsEarned (e.g. 'Legendary Digger'), Stats.SecretFinds/TotalFinds/BiggestSale ('Treasure Hunter'), Mining.OresBroken/Collection.VoidCrystal/PickaxeOwned ('Void Miner'), the Dogdex count ('Dog Master'), Prestige, CompletedTrades. Feature module Features/Titles.luau with p.Titles={Version=1, Earned={[id]=at}, Equipped=id}; Normalize migrates the existing p.Cosmetics title keys idempotently. Titles are cosmetic only (no BonusSource) unless the owner wants a deliberate stat.

**Файлы.** 
- src/ServerScriptService/Economy/Rules.luau (Cosmetic action compatibility)
- `src/ServerScriptService/Economy/RecordStats.luau`
- `src/ServerScriptService/Economy/LifetimeStats.luau`

**Новые модули.** 
- `ReplicatedStorage/TitleCatalog.luau`
- `ServerScriptService/Economy/Features/Titles.luau`

**Совместимость данных.** Keep p.Cosmetics and EquippedCosmetic readable (old clients/UI); Titles is additive.

**Производительность.** Evaluate the criteria on relevant actions or once per minute, not every tick.

**Объём.** S (economy part)

**Риски.** Criteria based on cumulative coins become trivial after F11/F7 raise income: use rank-relative or multi-condition criteria.


## Аудитор `digging-depth`

**Сейчас.** Данные для достижений глубины уже есть: UnlockedLayers, CurrentLayer, p.Stats.Depths[k].Finds/BestValue, p.TotalExcavations, Stats.TotalDigs.

**План.** Титулы глубины: «Caver» (слой 2 открыт), «Ruin Raider» (3), «Cursed Delver» (4), «Void Walker» (5), «Legendary Digger» (TotalExcavations ≥ N или Depths[5].Finds ≥ N), «Treasure Hunter» (редкие находки на глубине). Источник — только серверные поля выше; выдача в системе титулов F10.

**Файлы.** 
- `/home/user/riooblox/src/ServerScriptService/Economy/RecordStats.luau`

**Совместимость данных.** Только чтение существующих полей.

**Производительность.** Нет.

**Объём.** S (часть, касающаяся этой подсистемы)

**Риски.** Старые профили: Stats.Depths заполнялся с момента появления RecordStats — история до этого не восстанавливается (так и задумано в RecordStats).


## Аудитор `item-models`

**Сейчас.** Титулы за находки уже есть: ItemSetClaim даёт p.Cosmetics['Discovery:SET:Normal|Heavy'] (ItemRules:212); статистика p.Stats (TotalFinds, SecretFinds, BestTier), p.Collection.

**План.** Предоставить данные для условий достижений: 'Treasure Hunter' — Collection ≥N, 'Legendary Digger' — находка Legendary+ (по ItemValuation.Rarity), Secret-находки; цвета редкости титулов брать из Theme.ItemRarity.

**Файлы.** 
- `src/ServerScriptService/Economy/RecordStats.luau`
- `src/ReplicatedStorage/ItemValuation.luau`

**Совместимость данных.** Аддитивно; для старых игроков засчитывать по Collection.

**Производительность.** Нет.

**Объём.** S

**Риски.** Счётчики в Stats ведутся только с Stats.Since — старые находки учитывать по Collection/PersonalRecords.


## Аудитор `plots`

**Сейчас.** Titles are p.Cosmetics keys (Dex10..., Set..., Finds..., Prestige...). They are equipped through the 'Cosmetic' action into p.EquippedCosmetic, which they share with legacy kennel cosmetics, shown above the player's KENNEL DOGS (EconomyVisuals L27-36), and listed in PlotShopScreen L68-76. PlotRules.Normalize reads EquippedCosmetic for its legacy migration (L14).

**План.** F10 owns a new p.Titles / EquippedTitle, migrated from the p.Cosmetics title keys. Remove the titles list from PlotShopScreen. Optionally show the equipped title under the name on the plot owner billboard (MapAmbience updateOwnerBillboard). Keep the PlotRules legacy read of EquippedCosmetic untouched.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau`
- `src/ServerScriptService/MapAmbience.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`

**Совместимость данных.** Do not repurpose EquippedCosmetic semantics for old profiles without migration; PlotProgressionVersion nil profiles still read it.

**Производительность.** None.

**Объём.** S

**Риски.** Legacy kennel cosmetics and titles share one field.


## Аудитор `lab`

**Сейчас.** No titles; the lab records p.Lab.Experiments and p.Lab.FirstDiscoveries['MUTATION:<Variant>'] (written for any lab result dog incl. ascend/recipe outputs).

**План.** Feed lab achievements into the title system: e.g. 'Mad Scientist' (N rerolls via new p.Lab.Rerolls), 'Void Master' (first Void from a reroll - record a separate p.Lab.FirstDiscoveries['REROLL:Void'] in LabRules.Reroll), 'Geneticist' (all 6 variants from the machine). Use a server event/callback after a committed reroll rather than polling.

**Файлы.** 
- `src/ServerScriptService/Economy/LabRules.luau`
- `src/ServerScriptService/Economy/LabService.luau`

**Совместимость данных.** New counters only (p.Lab.Rerolls, REROLL:* discovery keys); old data untouched.

**Производительность.** None.

**Объём.** S

**Риски.** Old FirstDiscoveries['MUTATION:x'] mixes ascend/recipe results; do not grant reroll titles retroactively from it without a clear rule.


## Аудитор `ui`

**Сейчас.** Titles exist only as Dogdex/collection rewards in p.Cosmetics (DexRewards.TitleNames) and p.EquippedCosmetic. They are displayed by EconomyVisuals as a BillboardGui 'EconomyCosmetic' over the player's DOGS (kennel and dog-line models), not over the character. They are equipped from COSMETICS.

**План.** UI side:
- TitlesScreen (Kit) reachable from a profile/Settings button: list of titles with rarity colour and gradient, earned/locked state, requirement progress bars, EQUIP button.
- Nameplate: a client builds one pooled BillboardGui per nearby character (MaxDistance about 60, AlwaysOnTop false) from a replicated player attribute EquippedTitle set by the server, with a rarity gradient and Fredoka text marked NoTranslate (localized names come from the title catalogue).
- Nameplates hide on UIHidden and are capped in count for low-end devices.

**Файлы.** 
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- `src/ReplicatedStorage/DogEconomy/DexRewards.luau`
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/TitlesScreen.luau`
- `src/StarterPlayer/StarterPlayerScripts/TitleNameplates.client.luau`

**Совместимость данных.** Reuse p.Cosmetics keys for owned titles; new optional p.EquippedTitle (default none) so EquippedCosmetic semantics stay intact.

**Производительность.** Pooled billboards, distance-limited.

**Объём.** M

**Риски.** Character streaming (StreamingEnabled) means nameplates must attach on CharacterAdded/stream-in. Keep the existing dog cosmetic billboard behaviour or migrate it explicitly.


## Аудитор `events-nav`

**Сейчас.** No titles. Event identity data exists: WorldEventsSeen (13 ids with Rarity) and the end-reward ledger. Cosmetics like 'EventSupporter' exist in ShopDefinitions as a 'cosmetic title' Product.

**План.** Expose event achievements to the Titles system:
- 'Rush Runner' / 'Stampede Master' from EventPass.Lifetime.Caught thresholds;
- 'Golden Catcher' from Golden catches;
- 'Storm Chaser' for seeing all non-secret events (WorldEventsSeen count);
- 'NULL Witness' for NULL_HOUR.
Grant them server-side inside the EventPass Action/Tx through the Titles feature API (e.g. Titles.Grant(p,id)). Event pass top tiers award seasonal titles.

**Файлы.** 
- src/ServerScriptService/Economy/Features/EventPass.luau (new)
- src/ServerScriptService/WorldEventService.luau (journal can call Titles check)

**Новые модули.** 
- (Titles module owned by the titles subsystem; events only call it)

**Совместимость данных.** Titles derived from existing WorldEventsSeen can be granted retroactively in Normalize for old players.

**Производительность.** None.

**Объём.** S

**Риски.** Avoid double sources of truth: derive what is derivable and store only grants.


## Аудитор `tooling-perf`

**Сейчас.** No overhead titles. Text in the world is caught by AutoTranslateUI (connection per label, RU pattern pass) and PlaceTypography (forces FredokaOne unless KeepFont). Dog billboards use BillboardGui with MaxDistance 80.

**План.** Tooling/perf part: one BillboardGui per character created by the server (or the client for remote characters) with MaxDistance <=60, LightInfluence 0, AlwaysOnTop false, NoTranslate=true (text localized from Localization/Titles via the title id) and KeepFont if a special font is used. Rarity shimmer via a UIGradient whose Offset is animated only for the nearest few players (Perf/Scheduler 15 Hz, Lod by distance), not per frame for everyone. A Lune test for title unlock rules (achievements) in economy_env.

**Файлы.** 
- src/ServerScriptService/EquipmentAvatar.server.luau (character decoration hook)
- src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau (no change if NoTranslate is used)

**Новые модули.** 
- `src/ReplicatedStorage/Titles/TitleDefinitions.luau`
- `src/ServerScriptService/Economy/Features/Titles.luau`
- `src/StarterPlayer/StarterPlayerScripts/TitleBillboards.client.luau`
- `src/ReplicatedStorage/Localization/Titles.luau`
- `tests/titles.luau`

**Совместимость данных.** Earned/equipped titles as a new field via Features.Normalize. Achievements computed from existing stats (Stats, LifetimeStats, DogDex) so old players get titles they already earned.

**Производительность.** <=1 billboard per player; gradient animation limited to the nearest few.

**Объём.** M (tooling part S)

**Риски.** Without NoTranslate the AutoTranslate pattern pass runs on every title change. Engine Highlight limits are not involved.
