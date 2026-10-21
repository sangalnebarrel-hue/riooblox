# DOGROTS — HALLOWEEN PART II · THE UNDERYARD

Готовый плейс: **`build/DOGROTS_HALLOWEEN_PART2_THE_UNDERYARD.rbxl`** (лежит в репозитории вместе с
`build/build_report.json`; сборка пересоздаёт оба из исходника). Откройте файл в Roblox Studio, проверьте и опубликуйте
как обычно.

| Путь | Что там |
|---|---|
| `place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl` | исходный плейс (Глава I). Сборка его только читает и никогда не перезаписывает |
| `src/` | все скрипты плейса по структуре Roblox (имена Rojo: `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript), включая офлайн-сборщики мира в `src/ServerStorage/` |
| `tools/` | `check.sh`, сборщик `place_build.luau` + шимы `sim.luau`, офлайн-правки мира `edits/*.luau`, проверки `verify.luau` / `verify_world.luau` / `analyze_diff.py` / `compare_places.luau` (готовый плейс против исходника), модель темпа Главы II `chapter2_pacing.luau`, рендер превью, экспорт русских строк `export_ru_csv.luau` |
| `tests/` | юнит-, интеграционные и безголовые UI-тесты на Lune |
| `docs/HALLOWEEN_PART2.md` | **главный документ обновления**: механики, изменённые и новые файлы, интерфейсы, локация, награды, шансы, сохранения, флаги, календарь, проверка в Studio, ограничения |
| `docs/halloween2/` | `DESIGN.md` (проектный контракт), `CHAPTER1_BALANCE.md`, `BOSS.md`, `TUTORIAL.md`, `SHELTER_TEST.md`, `DOGROTS_RU_HALLOWEEN_PART2.csv` (русские строки Part II для облачной таблицы локализации) |
| `docs/*.md` | описания прежних систем игры (экономика, добыча, лаборатория, снаряжение и др.) |

## Сборка и проверка

Нужны lune 0.10.x, luau-lsp 1.53.0 с `globalTypes.d.luau` той же версии и python3.

```bash
LUNE=/путь/к/lune LUAU_LSP=/путь/к/luau-lsp LUAU_DEFS=/путь/к/globalTypes.d.luau ./tools/check.sh
# BASE=<исходный.rbxl> OUT=<результат.rbxl> меняют вход и выход
# (по умолчанию place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl -> build/DOGROTS_HALLOWEEN_PART2_THE_UNDERYARD.rbxl)
```

`check.sh` делает шесть шагов:

1. записывает `src/` в плейс;
2. запускает офлайн-сборщики мира: звук, собаки H09–H16, церковь, THE UNDERYARD, календарь;
3. компилирует и проверяет бюджеты мира;
4. сравнивает результат с исходником (`compare_places.luau`);
5. прогоняет все тесты `tests/*.luau` (20 старых падений исходного плейса не считаются ошибкой, новое — считается);
6. печатает только новые диагностики luau-lsp.

Подробности — в `docs/HALLOWEEN_PART2.md`, разделы 0 и 12.
