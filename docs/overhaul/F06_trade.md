# F6. Trade 2.0 — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `trade-titles` (основной)

**Сейчас.** RAM state machine in Engine (TradeRequest/Trade/CancelTrade, Engine.luau:270-355) driven by DogEconomyRequest actions TradeRequest/TradeCancel/Trade (Runtime.luau:432-438). Up to 6 dogs + 6 finds + Cash per side; version/lock/8 s review/confirm; fingerprints re-checked at commit; RAM-only fast commit; RefreshAll on every step. UI: EconomyScreens.Screens.Trade rebuilt every 5 s plus static TradePage; no search/filters/previews/push. Found: CRITICAL Confirm/Offer race via PaidPolicy yield (reproduced), invite griefing with forced window + control lock, non-atomic persistence, stale expiry, RefreshAll DoS, Ready timer restart, stale client selections, misleading estimates, no audit log, no tests.

**План.** Phase 0 (hotfix, ship first): in E:Trade Confirm capture version and R.Copy(t.Offers), set t.Committing=true before PaidPolicy.Allowed, re-check version after it, and commit from the copy; make repeated Ready a no-op; on trade steps refresh only participants.

Phase 1 (server, new Economy/TradeService.luau + pure Economy/TradeRules.luau + ReplicatedStorage/TradeConfig.luau):
- Invites[target]={Id,From,To,Expires=now+30}; TradeByUser set only on accept. Pair cooldown 15 s, max 3 outgoing, p.Settings.TradeRequests ('All'/'Off').
- Actions via Runtime.Request -> TradeService.Request(player,action,a,receiptId): TradeInvite{Target}, TradeRespond{InviteId,Accept}, TradeSet{Version,Dogs<=6,Items<=6,Cash}, TradeReady{Version,Ready}, TradeConfirm{Version}, TradeCancel{}. Keep old 'Trade'/'TradeRequest'/'TradeCancel' as thin adapters during rollout.
- Session: Version, Offers (uids, server prints, server values), Ready/Confirmed, ChangedAt/ChangedBy, Diff (added/removed per side), ConfirmAfter, LastActivity, Committing.
- Rules: any change resets Ready/Confirm; Ready allowed >=3 s after the last change; when both ready, ConfirmAfter=now+5 is set once; Confirm only at the current version.
- Eligibility reuses R.Dog(...,true)/I.Get(...,true), adds: no displayed dog / showcased item (warn or block), Favorite needs an explicit flag, PaidRandom policy checked at Set/Ready time and read from cache (non-yielding) at commit.
- Value: TradeValue.luau (shared, pure). Dog = (LinePrice or BasePrice) x variant bonus (Config.Variants) x mastery/ascension factor; item = ItemValuation.Price(x) live; optional cached Market median. Totals per side; imbalance >3x forces a warning modal + hold.
- Commit: Tx:Run({pk(a),pk(b),'tl:'..id}, transform, 'trade-'..id). Durable path = atomic DataStore write + audit doc {Users,At,Offers summary,Values,JobId}. The transform reuses the existing capacity / fingerprint / Pay / Credit / Transfer code. It appends p.TradeHistory (20) and counts CompletedTrades/TradePartners only for non-empty two-sided trades. After commit: Runtime.Refresh for both participants and push 'TradeClosed'.
- Sweep step in Runtime loopOnce every 2 s: invites 30 s, sessions idle 180 s, partner leave -> close with reason.
- Push 'TradeInvite', 'TradeState' (slim view: offers as card data, values, timers), 'TradeClosed' through Runtime.PushTo.

Phase 2 (client, new Modules/TradeScreen.luau Kit window Key='Trade' + Modules/TradeInviteToast.luau):
- Header: partner avatar, @username, level, title, idle timer.
- Two columns 'YOU GIVE' / 'YOU GET' with 6+6 slot cards (Kit.Preview dog/item), rarity glow, total value and a balance bar; CHANGED pills on diff.
- Picker: Kit.CardGrid (virtualized) with SearchBox, Chips (Dogs/Finds, rarity, mutation), SortSelect (value/rarity/newest), grouping of identical finds (xN with stepper), disabled cards with reasons (Locked, In kennel, Record check, Paid trading unavailable).
- Cash stepper (+10%/50%/MAX).
- One big state button: LOCK -> 5 s countdown ring (Kit.Countdown on server ConfirmAfter) -> CONFIRM (Hold 1 s); Kit.Confirm with Cards for imbalance or one-sided trades.
- Tabs PLAYERS (search, list of up to 59 with level/title/status, REQUEST) and HISTORY.
- Phone: tabs THEIRS/MINE/ADD. Updates only through Net.OnPush('TradeState').
- GUIIntegration routes 'Trade' to TradeScreen.Open(); DogEconomyOpen 'Trade' becomes a toast; PawpadController.renderTrade and Screens.Trade removed; TradePage kept hidden.
- Update OnboardingGuide step 15 text and add Localization/Trade.luau + AutoTranslate entries.

Phase 3 (tests): tests/trade.luau on tests/payments_lib/loader + memory store. Cover the invite does not lock, sweep, version reset, Ready no-restart, the race fix (yielding PolicyService stub), fingerprint change, capacity, paid policy, disconnect mid-trade, durable commit writes both profiles + log, idempotent replay, empty-trade stat rule.

**Файлы.** 
- `src/ServerScriptService/Economy/Engine.luau`
- `src/ServerScriptService/Economy/Runtime.luau`
- `src/ServerScriptService/Economy/RecordStats.luau`
- `src/ServerScriptService/Economy/ItemRules.luau`
- `src/ServerScriptService/Economy/Rules.luau`
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`
- `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `src/StarterGui/ScreenGui/Modules/Menus.luau`
- `src/StarterGui/ScreenGui/PawpadController.client.luau`
- `src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau`
- `src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Feedback.luau`

**Новые модули.** 
- `src/ServerScriptService/Economy/TradeService.luau`
- `src/ServerScriptService/Economy/TradeRules.luau`
- `src/ReplicatedStorage/TradeConfig.luau`
- `src/ReplicatedStorage/TradeValue.luau`
- `src/StarterGui/ScreenGui/Modules/TradeScreen.luau`
- `src/StarterGui/ScreenGui/Modules/TradeInviteToast.luau`
- `src/ReplicatedStorage/Localization/Trade.luau`
- `tests/trade.luau`

**Совместимость данных.** Trades are RAM-only today, so no saved trade data needs migration. New optional fields (p.TradeHistory, p.Stats.TradePartners, p.Settings.TradeRequests) are added nil-safe in Normalize, and existing CompletedTrades is kept. OwnerHistory Type='Trade' format unchanged. New durable keys 'tl:<32hex>' (<=50 chars) only for new trades. Keep the Engine.TradeByUser contract (lab/shelter/sell/snapshot and tests/lab.luau stub it). Old clients during rollout: keep the legacy 'Trade' action as an adapter for one release.

**Производительность.** Durable commit is about 6 Read + 11 UpdateAsync per trade (measured in the scratch simulation): fine for trades, but show a saving state and never hold other gameplay. Removing RefreshAll saves up to 60 Project calls per click. Push slim TradeState (~1-3 KB) instead of full 5 s snapshots. VirtualGrid caps instances regardless of 250 dogs / 1000 finds. Previews: Kit.Preview cache (PerFrame=2, MaxFree=48). Sweep is O(active trades).

**Объём.** L

**Риски.** Durable path latency/DataStore throttling (needs retry with the same request id and a clear UI state). Behaviour change for the TradeByUser consumers. Owner decisions on cash limits / tax / gifting / account-age gate (RMT and alt funneling). Value display can be read as a promise (label it 'estimate'). Exploit clients firing parallel requests: every state change must be serialized per trade (Committing / version checks everywhere). Localization coverage. Mobile layout of two columns + picker.


## Аудитор `data-network`

**Сейчас.** Engine.Trades и TradeByUser в RAM сервера. TradeRequest сразу блокирует обоих (до 240 с), из-за этого цель не может продавать и пользоваться лабораторией. Предложение: ≤6 собак, ≤6 находок, Cash. Version/Ready/Confirm с ConfirmDelay=8 с, проверки отпечатков. Подтверждение — fast RAM-транзакция по двум профилям, атомарности на диске нет. Второй стороне никто не сообщает об изменениях (Pawpad опрашивает раз в 8 с). Каждое действие Trade вызывает RefreshAll. Snapshot.Trade и Snapshot.Players.

**План.** Модуль Economy/TradeService.luau поверх Engine (Engine:Trade оставить для совместимости). 1) Приглашение — заявка {From,To,Expires=30 с} без TradeByUser; лимит 1 приглашение в 10 с на пару и до 3 висящих; сессия создаётся по 'TradeAccept'. 2) При каждом изменении — push 'Trade' обоим (Runtime.PushTo) с облегчённым видом {Id,Version,Users,Offers{Dogs/Items строки, Cash, Estimated},Ready,Confirmed,ConfirmAfter,Expires}. 3) Лимиты: находки ≤20, собаки ≤6 (в рамках clean ≤30); «количество» — группировка uid в UI, сервер проверяет точные uid. 4) Защита: Favorite, витринные и Locked-собаки без явного переключения не предлагаются; предупреждение о перекосе по Estimated с удержанием кнопки; любое изменение сбрасывает Ready и Confirmed (как сейчас); ConfirmDelay остаётся. 5) Durable-подтверждение: ключи {p:A, p:B, 'tradelog:'..tradeId}; ключ не из быстрых, поэтому _runDurable делает атомарный журнал обоих профилей и записи лога (Recover доведёт его после падения). 6) Refresh только для двух участников. 7) Отмена при выходе (Engine:Leave уже вызывает CancelTrade).

**Файлы.** 
- src/ServerScriptService/Economy/Engine.luau (TradeRequest/Trade/commit)
- src/ServerScriptService/Economy/Runtime.luau (ветки Trade*, RefreshAll→участники, стоимость, Snapshot.Trade)
- src/ServerScriptService/Economy/YardCommerce.luau / LabService.luau (проверки TradeByUser)
- src/StarterGui/ScreenGui/Modules/Net.luau (OnPush 'Trade')

**Новые модули.** 
- `src/ServerScriptService/Economy/TradeService.luau`
- клиентское окно Trade 2.0 (Kit)
- tests/trade.luau (журнальное подтверждение, повторы, отказы, гриф-сценарии)

**Совместимость данных.** Схема профиля не меняется: Stats.CompletedTrades и OwnerHistory Type='Trade' сохраняются. Необязательно p.TradeHistory (≤20) для UI. Ключи tradelog:<id> не удаляются, как и tx:.

**Производительность.** Исчезают RefreshAll и опрос раз в 8 с. Durable-подтверждение редкое, это допустимо. Журналы tx: и tradelog: копятся в DataStore (лимиты хранилища на опыт).

**Объём.** L

**Риски.** Durable-подтверждение сначала сохраняет оба грязных профиля (_settleLocked): это ~15–20 обращений к DataStore и несколько секунд при троттлинге, нужен понятный экран «сохраняем». Журнал у двух «китов» около 2,3 МБ, под защитой 3,5 МБ. Проверки PaidPolicy для платных предметов. Push, пришедший не по порядку, отбрасывать по Version.


## Аудитор `economy`

**Сейчас.** Engine:TradeRequest/Trade (RAM-only, 240 s expiry, level >= 5, Offer of <=6 dogs + <=6 items + Cash, Ready allowed 2 s after the last change, Confirm after an 8 s safety delay, fingerprints re-checked at commit, PaidRandom policy). The value shown is 'Estimated' = cash + stored item SellValue (Engine.luau:301, mint-time value) + dog LinePrice/BasePrice (line 306, ignores variant/mastery/ascension), while the collector pays the live ItemValuation.Price. Items have no lock (I.Normalize clears x.Locked); x.Favorite exists. The market has median prices (Market:Query Median24h/7d).

**План.** Add a pure ReplicatedStorage/DogEconomy/TradeValue.luau. Item(x) = ItemValuation.Price(x), the exact NPC value. Dog(d) = (LinePrice or BasePrice) x (1 + variant bonus + mastery x .0015 + ascension), the same terms as R.Bonus: move that pure formula into the shared module and have Rules.Bonus call it. Optional market reference = Median7d of the asset key, attached by the server and cached 60 s. The server computes per-asset values and side totals on Offer and stores them in t.Offers[uid].Values. The client shows two columns (mine / theirs), side totals, and a fairness bar min/max. Protection: when the ratio is < 0.5 and the losing side gives a high-value asset (reuse LabGenetics.ValueReasons) or a favorite or showcased item, require a hold-to-confirm. Quantity: group identical ItemIds client-side with a count stepper; the server still receives uids; raise the item limit 6 -> 12 (Runtime.clean allows 30).

**Файлы.** 
- src/ServerScriptService/Economy/Engine.luau (Offer values, limits)
- src/ServerScriptService/Economy/Rules.luau (R.Bonus via shared formula)
- src/ServerScriptService/Economy/Runtime.luau (tradeView)
- src/ReplicatedStorage/ItemValuation.luau (export rarity)
- trade UI modules (other subsystem)

**Новые модули.** 
- `ReplicatedStorage/DogEconomy/TradeValue.luau`

**Совместимость данных.** Trades are RAM-only: no save migration. Stats.CompletedTrades is unchanged.

**Производительность.** Value computation per offered asset (<=18 assets) per Offer; trivial. Avoid recomputing on every Snapshot.

**Объём.** M (economy part)

**Риски.** The dog value is an estimate, not a price: label it with ≈. Market medians can be wash-traded, so use only BuyNow sales and show them as a reference. More items per offer means larger Details copies in snapshots.


## Аудитор `item-models`

**Сейчас.** Trade (EconomyScreens.Trade:255-345) показывает находки только строками текста 'имя · вес · мутация', до 4 строк + '+N more'. Обе стороны отображаются одинаково. В offer.Details лежат полные копии предметов (Engine.luau:301), оценка — по замороженному x.SellValue.

**План.** Сторона моделей: две колонки ItemCard (мои / чужие) с Preview Kind='Item' Lod='Card' из offer.Details (ItemId, Mutation, WeightKg); при наведении или нажатии — Hero-превью; рамка и сортировка по ItemValuation.Rarity; фильтр по редкости и мутации по полному списку 16 ключей. Для подтверждения — крупные иконки всех предметов сделки (L1) на экране «Финальное подтверждение».

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Preview.luau`

**Новые модули.** 
- src/StarterGui/ScreenGui/Modules/TradeScreen.luau (если трейд выносится в Kit-окно)

**Совместимость данных.** Протокол трейда не меняется.

**Производительность.** ≤12 карточек L1 (≤240 частей) + 1 Hero.

**Объём.** M

**Риски.** Отображение чужих предметов зависит от состава offer.Details — если урезать payload, оставить там ItemId, Mutation, WeightKg, TierIndex. Не больше 12 viewport на экране.


## Аудитор `plots`

**Сейчас.** Trade offers validate items via I.Get(p,uid,true) (Engine L298-308, commit L336). There is no notion of showcased items.

**План.** With the F3 hook in ItemRules.Get(transfer), showcased items cannot be offered. The trade UI shows them disabled with 'ON SHOWCASE' and a 'remove from showcase' shortcut, which doubles as accidental-trade protection.

**Файлы.** 
- `src/ServerScriptService/Economy/ItemRules.luau`
- Trade UI module

**Совместимость данных.** None.

**Производительность.** None.

**Объём.** S

**Риски.** An in-flight trade that already contains an item placed on the showcase afterwards: ShowcaseSet must reject items reserved in an active trade (Engine.TradeByUser).


## Аудитор `ui`

**Сейчас.** Trade UI is split. The desktop HUD TRADE tile shows the static TradePage (player list + REQUEST TRADE, PawpadController.renderTrade). The trade session and the phone variant are EconomyScreens.Trade (legacy Menus, rebuilt every 5 s): two text summary cards, 3 step buttons (UPDATE OFFER / LOCK OFFER / FINAL CONFIRM after an 8 s review), a Cash TextBox, then long lists of text buttons '+ Name · Rarity · Variant' for every dog and find (no previews, search or filters). Invites arrive via DogEconomyOpen('Trade').

**План.** Kit TradeScreen, Key='Trade', for both entry points; remove the static TradePage and the compact split.
- Lobby: player cards with avatar and level gate, search box, REQUEST button.
- Session: two columns, 'YOU GIVE' (editable) and 'THEY GIVE' (read-only), with item/dog cards (Kit.Preview).
- Picker drawer with search, rarity chips, quantity and favourite/locked indicators (locked/working dogs disabled with reason).
- Value bars per side.
- Status rail: Editing → Locked → Review countdown (Kit.Countdown from ConfirmAfter) → Confirm (Hold-to-confirm 1 s).
- Changes since your last lock are highlighted with a pulse.
- Final Kit.Confirm lists the cards given and received.
- Prefer DogEconomyPush for trade updates instead of polling.
- Server actions stay unchanged: TradeRequest, Trade{Accept/Offer/Ready/Confirm}, TradeCancel.

**Файлы.** 
- src/StarterGui/ScreenGui/Modules/GUIIntegration.luau (Trade routes)
- src/StarterGui/ScreenGui/Modules/EconomyScreens.luau (Screens.Trade retire)
- src/StarterGui/ScreenGui/PawpadController.client.luau (renderTrade retire)
- src/ServerScriptService/Economy/Runtime.luau (PushTo trade state, optional)

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/TradeScreen.luau`

**Совместимость данных.** No profile changes.

**Производительность.** Removes the 5 s full rebuild; virtualised pickers.

**Объём.** L

**Риски.** The safety flow (version numbers, re-lock on change, 8 s review) must be preserved exactly. Snapshot.Players and Trade come from the full Snapshot; a push or dedicated query is better. Paid-item restrictions (PaidRandom) must be shown as disabled reasons.


## Аудитор `tooling-perf`

**Сейчас.** Trading exists in the economy (Market, YardCommerce, 'SAFE PLAYER TRADING' strings); the UI is old. Kit/Virtual and Kit/Preview provide pooled grids and previews. Every Runtime.Project bumps InventoryRevision and the old inventory refetches the full Snapshot.

**План.** Tooling/perf part: the trade window built on Kit/Virtual (pooled cells, search/filter done client-side on the cached Net.Snapshot), previews through Kit/Preview with the Quality viewport budget. Trade state changes arrive as DogEconomyPush deltas, not polling. Add Lune tests for the pure filter/sort/diff logic and for the confirmation state machine (two-step confirm, countdown, reset on any change), using economy_env with server Features if the trade protocol moves into Economy/Features.

**Файлы.** 
- src/StarterGui/ScreenGui/Modules (new TradeScreen on Kit)
- src/ServerScriptService/Economy/Market.luau / YardCommerce.luau (only if protocol changes)

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/TradeScreen.luau`
- src/StarterGui/ScreenGui/Modules/TradeLogic.luau (pure)
- `tests/trade.luau`

**Совместимость данных.** No change if the existing trade protocol is kept. Any new receipt/journal fields need Normalize defaults.

**Производительность.** No polling. The grid renders only visible cells. Previews built 2 per frame.

**Объём.** M (tooling/perf part S)

**Риски.** The large inventory snapshot size per push. Keep deltas small.
