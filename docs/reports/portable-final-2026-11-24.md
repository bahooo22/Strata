# Portable final: G:/Strata

Дата: 2026-11-24. Статус: **functional acceptance OK; HDD 200k/160k завершены**.

## Носитель

- Target: `G:/Strata` (HDD); модели не копировались, KAT IQ4_XS читается с `D:/Strata/models`.
- Wrapper artifact `kit-release-26`: 613 379 894 Б.
- SHA-256 wrapper: `615ecf87ba82f9a2864cf65b0b7f62541705da022a6773aa6fa2a2d990ea0434`.
- Внутренний `Strata-Portable-2026-11-23.zip`: 614 557 330 Б.
- SHA-256 inner: `a0337bd5c2196bb28c1481ba7e843fce2a0703513c0665f0c63ac652fcd3fed4`.
- Распаковано 946 файлов.
- `bin/strata-q36.exe`: 105 252 864 Б.
- SHA-256 engine: `fcdb3a89292c21b2aaa33b01bfe835628f2e16ddee5108f1dd6b8a69ccf59dac`.

## Functional acceptance

| Проверка | Результат |
|---|---|
| `START.bat -DryRun` | rc=0; окно 229376, KAT IQ4_XS, запуск ничего не стартовал |
| Штатный `smoke_kit.ps1 -Strata real` | rc=0; health/HTML/props зелёные |
| OpenAI `/v1/chat/completions` | HTTP 200, ответ `Да` |
| Anthropic `/v1/messages` | HTTP 200, ответ `Да` |
| `connect opencode --check` | rc=0; prompt `pong`, tool call `get_weather(Paris)` |
| `logs --output json` | rc=0; runtime activity получена |
| `monitor --once --output json` | rc=0; snapshot получен |
| Stop | rc=0; Portable processes отсутствуют, health недоступен, VRAM 0 MiB |

## Дефекты инструмента приёмки, исправленные до зелёного результата

- GitHub artifact API отдаёт 302 на signed blob URL; Authorization нельзя пересылать на redirect.
- Wrapper ZIP содержит внутренний Portable ZIP; распаковка должна раскрывать оба слоя.
- `bin/strata.exe` — engine, а terminal CLI находится в bundled Python + `strata_cli.cli:main`.
- Повторный smoke требует уникальный WorkDir, иначе stale `ready.json` даёт ложный отказ.

Эти дефекты относились к приёмному инструменту, не к собранному Portable engine.

## HDD benchmark

Идёт на том же `G:/Strata/bin/strata-q36.exe`, модель на D:, окна 200k затем 160k, graph on, MTP0, q4_0, super-chunk 8, att-mb 256, reserve 512, max-tokens 256.

| Окно | Prompt tokens | pp | tg | Prefill ms | Gen ms | rc | Ответ |
|---|---:|---:|---:|---:|---:|---:|---|
| 200k | 202 665 | 376,7 | 11,0 | 538 021 | 8 208 | 0 | `Принято` |
| 160k | 139 299 | 560,6 | 13,7 | 248 475 | 5 604 | 0 | `Принято.` |

Это **абсолютный HDD-вариант**, а не контролируемое A/B с исходной сборкой на G:. SSD-выводы по нему не делаются.

## Артефакты

- `glm/2026-11-24_session/portable-download-unpack-fixed.log`.
- `glm/2026-11-24_session/portable-unpack-only.log`.
- `glm/2026-11-24_session/portable-functional-summary.json`.
- `glm/2026-11-24_session/portable-smoke.log`.
- `glm/2026-11-24_session/portable-{openai,anthropic,connect,logs,monitor,stop}.log`.
- `glm/2026-11-24_session/portable-hdd/` — benchmark logs и summary.
