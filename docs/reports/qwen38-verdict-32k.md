# Qwen3.8-Flash-Next Swift IQ3_XXS: вердикт 32k

Дата: 2026-11-24. Статус: **blocked**, 32k не принят на текущем стенде.

## Конфигурация стенда

- GPU: RTX 3060 Ti 8 GiB; RAM: 32 GiB; Windows 11.
- Носители: C: и D: — SATA SSD; G: — SATA HDD.
- GGUF: `D:/Strata/models/swift-qwen38/swift-IQ3_XXS`, два шарда ~76 GiB.
- Pack: `C:/Strata/swift-qwen38-data/packs/swift-iq3_xxs`, experts ~42,9 GiB.
- Exe: `F:/tmp/q7-spec0-build/strata.exe`, commit `d1296726e`; локальная ветка удалена после blocked-эксперимента, commit сохранён tag `archive/q7-native-spec0-d1296726e`.
- Окно: 32 768 prompt-токенов + 512 generation; ctx 33 536.
- Общие флаги: `--spec 0`, `--kv q4_0`, `--mmap-experts`, `--expert-cache auto`, `--mtp 0`, `--prefill 2048`.
- Для валидного layer-major A/B используется `--expert-cache auto --vram-reserve-mib 512`: явный cache 1024 не проверяет VRAM и оставлял 0 MiB, поэтому layer-major отключался.
- Opt-in: `STRATA_ALLOW_NATIVE_SPEC0=1`; DFlash2 для Swift исключён терминалом.
- Для B..E: `STRATA_PREFILL_LAYER_MAJOR=1`, `STRATA_PREFILL_LM_TOKENS=32768`; fit ограничивает супер-чанк по VRAM.

## Результаты

| Точка | Маршрут | Prompt | Prefill | Decode | Качество | Итог |
|---|---|---:|---:|---:|---|---|
| A | `STRATA_PREFILL_LAYER_MAJOR=0` | 18 432/32 771 за 3 578 s | ~5,2 tok/s по прогрессу, финальная строка отсутствует | not-run | not-run | timeout монитора до decode |
| B | `STRATA_PREFILL_LAYER_MAJOR=1`, speed-only | 32 768 | not-run | not-run | not-run | остановлена: `layer-major off`, 0 MiB free |
| A auto | layer-major=0, speed-only, cache auto, reserve 512 MiB | 2 048/32 771 за ~401 s | mean 9,8 tok/s | not-run | not-run | stop/go: pp < 100 |
| B 8192 | layer-major=1, default super-chunk 8192 | 8 192/32 771 | mean 18,2 tok/s | not-run | not-run | остановлена: четыре чтения experts |
| B 8k smoke | layer-major=1, `STRATA_PREFILL_LM_TOKENS=8192`, ctx 8512 | 8 145 за 457,5 s | ~17,8 tok/s | not-run | not-run | engine exit/503 после capture; 40,5 ГБ streamed |
| B LM32768 | layer-major=1, `STRATA_PREFILL_LM_TOKENS=32768` | 32 766 за 517,8 s | ~63,3 tok/s | not-run | not-run | 503 после capture; pp < 100 |
| C20 | B + resident 20 GiB, speed-only | 32 768 | not-run | not-run | not-run | exit 2: нет static expert-profile |
| C24 | B + resident 24 GiB | — | — | — | — | not-run: тот же missing profile |
| D | C + PLE row-cache/inflight | — | — | — | — | not-run |
| E | D + `--kv-grow` | — | — | — | — | not-run |

A: `glm/2026-11-24_session/q7-swift-32k/q7-swift-32k-official-A.log`.
A auto: `glm/2026-11-24_session/q7-swift-32k/q7-swift-32k-A-auto-speed-A.log`.
B8192: `glm/2026-11-24_session/q7-swift-32k/q7-swift-32k-B-auto-speed-B.log`.
B LM32768: `glm/2026-11-24_session/q7-swift-32k/q7-swift-32k-B-lm32-speed-B.log`.
C20: `glm/2026-11-24_session/q7-swift-32k/q7-swift-32k-C20-speed-C20.log`.
8k smoke: `glm/2026-11-24_session/q7-swift-32k/q7-swift-8k-B.log`, summary `q7-swift-8k-summary.md`.

## Что уже доказано

- `--spec 0` больше не создаёт verifier ширины 0: используется one-token verify window.
- Сервер поднимается, health OK, prompt 32k реально читается.
- Диагностический 8k smoke также поднялся и завершил prefill 8145 токенов за 457,5 s, но после успешного one-token capture engine завершился и сервер вернул 503; decode/tg не получены.
- `--expert-cache auto --vram-reserve-mib 512` дал 86 слотов и 1206 MiB свободного VRAM; явный cache 1024 оставлял 0 MiB.
- A без layer-major не проходит порог pp >= 100 даже по частичному прогрессу.
- 10–15 tok/s из сохранённых отчётов относятся к q36 KAT/Huihui, не к Swift.
- Предыдущий замер Swift 22.11: 5 207 prompt-токенов, pp 7,2, tg 2,0.

## Stop/go

Порог плана: pp >= 100, tg >= 0,7, осмысленный ответ, needle 3×2 и QA subset.

B LM32768 — решающая диагностика layer-major. Она дала ~63,3 tok/s prefill и затем 503 после capture one-token window; decode/tg не измерены. Повторный 8k smoke воспроизвёл тот же post-capture exit/503, поэтому блокер не сводится к размеру окна. C20 не стартует: resident mode требует static `--expert-profile`, которого нет в Swift data. C24/D/E не запускались по той же причине.

Unblock conditions:
1. Получить или сформировать static Swift expert-profile и повторить C20.
2. Объяснить 503 после verify capture: engine log заканчивается успешным capture, сервер сообщает `process exited; status unavailable`, fatal GPU/ERR строки нет.
3. После снятия блокеров повторить 32k speed, затем needle 3×2 и QA subset.

## Ограничения

- На A свободный VRAM был почти нулевым; это может дополнительно снижать decode.
- A не завершил ни один запрос, поэтому pp/tg и качество не заявляются.
- Частичный прогресс A не является финальным pp; он использован только для stop/go.
- B LM32768 имеет финальный prefill, но не имеет decode/quality; 503 остаётся отдельным блокером.
- C20/C24/D/E и needle/QA — not-run, а не отрицательный результат.
