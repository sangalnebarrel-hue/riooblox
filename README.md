# DOGROTS

Готовый плейс: **`build/DOGROTS_MINING.rbxl`**. Открой его в Roblox Studio и опубликуй, как обычно.

**Большое обновление** (навигация, новый UI и сумка, витрина находок, 108 новых моделей находок,
глубокая шахта, обмен 2.0, Dog Rush, украшения участка, «Скрыть UI», титулы, баланс камня и кирок,
ядерная мутационная машина): что сделано и как проверить — **`docs/OVERHAUL.md`**.
Аудит и план — `docs/OVERHAUL_PLAN.md`.

| Путь | Что там |
|---|---|
| `build/DOGROTS_MINING.rbxl` | Готовый плейс |
| `backup/DOGROTS_MINING_5_before_overhaul.rbxl` | Плейс до большого обновления (также git-тег `pre-overhaul-v5`) |
| `place/DOGROTS_base.rbxl` | Исходный плейс, с которого собирается сборка |
| `src/` | Все скрипты по структуре Roblox (Rojo-имена: `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript) |
| `docs/` | Документация: `OVERHAUL.md` (обзор обновления) и по системам (`MINE`, `LAB`, `TRADE`, `UI`, `NAVIGATION`, `TITLES`, `DOG_RUSH`, `PLOT_COSMETICS`, `ITEM_MODELS`, `BALANCE`, `MINING`, `ECONOMY`, …) |
| `tools/` | Сборщик `.rbxl`, проверка через Lune и luau-lsp, симулятор баланса, `qa/` — рендер 3D-моделей в PNG без Studio |
| `tests/` | Юнит- и интеграционные тесты (Lune), `fixtures/` — сохранение старого игрока |

Сборка и проверки: `./tools/check.sh` (требования — в начале скрипта).
