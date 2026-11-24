# Скрипты форка: живая приёмка Q5.5

Дата: 2026-11-24. main `ba9ae196e`. Стенд: RTX 3060 Ti 8 GiB, 32 GiB RAM, Windows 11.

| Скрипт / путь | Статус | Evidence | Ограничение |
|---|---|---|---|
| `START-HERE.bat --check` | done | GPU/RAM/AVX2 распознаны | — |
| `UPDATE.bat --update` | done | rc=0; pull своего remote; модели up to date; engine пересобран из source=local | venv cmake launcher был сломан, починен force-reinstall |
| `build-verify.bat` | not-relevant | rc=2 «путь не найден»: цел в старую E:-раскладку | помечен LEGACY; живой эквивалент — UPDATE/setup.py --build |
| `setup.sh` | not-run | Windows-only стенд | Unix-путь не проверен |
| `strata.py launch --model-path KAT...` | done | `ba9ae196e`; health `loaded:true`; engine log подтверждает KAT GGUF; OpenAI ответ «Okay» | preset-name показывает UD-Q4_K_XL, но actual native path — KAT |
| `strata.py connect opencode --check --output json` | done | rc=0; prompt `pong`; tool call `get_weather(city=Paris)` | проверяет сервер, не устанавливает OpenCode |
| `strata.py logs --follow` | done | rc=124 от таймаута после 12 с; видны queued/admitted/first_token/finished | таймаут ожидаем для follow |
| `strata.py launch --stop` | done | rc=0; `Stopped ud-q4_k_xl-32k`; процессов нет | — |
| `/api-monitor`, `/api/requests` | blocked | оба 404 даже после `--set api_monitor=true` на installed engine 0.1.65 | нужен engine/server с monitor API или точный флаг конфигурации |
| Q4.5 `kit/ sync`, `ctx=max` | not-relevant | tracked packaging/kit пуст; ctx=max только в docs-коммитах | новый reproducer — отдельный дефект |

## Вывод

Launch/connect/logs/stop работают на форке с произвольным именем GGUF после `ba9ae196e`.
Monitor API в установленном engine 0.1.65 недоступен — это отдельный блокер, не скрытый PASS.
Installer/source QUICKSTART и Portable на `G:/Strata/` проверяются следующими этапами.
