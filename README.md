# DOGROTS — активная добыча (мини-шахта)

Готовый плейс: **`build/DOGROTS_MINING.rbxl`**. Открой его в Roblox Studio и опубликуй, как обычно.

| Путь | Что там |
|---|---|
| `place/DOGROTS_base.rbxl` | Исходный плейс, с которого собирается сборка |
| `src/` | Все изменённые и новые скрипты, по структуре Roblox (Rojo-имена: `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript) |
| `docs/MINING.md` | Описание механики, баланс, обучение, список изменений, чек-лист проверки |
| `tools/` | Сборщик `.rbxl`, проверка через Lune и luau-lsp, симулятор баланса |
| `tests/` | Юнит-тесты правил добычи (Lune) |

Сборка и проверки: `./tools/check.sh` (подробнее в `docs/MINING.md`, раздел 6).
