# Локальные изменения этого форка

Upstream: `https://github.com/Niko1221/Strata` (версия 0.2.10, база `ffa80d73`).
Ветка форка — `main`. Локальные коммиты поверх апстрима:

| Коммит | Что |
| --- | --- |
| `86200712` | подсказка `--mtp 0` и `STRATA_MMQ_KQ=0` в ошибке нехватки VRAM |
| `b8d4b58d` | страж `qwen35moe` не требует MTP-ключ: сторонние GGUF читаются |
| `143d5be4` | загрузчик q36 принимает IQ4_XS в `ssm_alpha/beta` |
| `414b9cde` | резерв VRAM стал флагом `--vram-reserve-mib` |
| `91725ec7` | квантованный q8_0 KV-кэш флагом `--kv-type` |
| `28f39156` | KV-типы q4_0, q5_0, q5_1 (раскладки ggml, единый байтовый буфер) |
| `912ea835` | заметки форка: ветка `q8-kv`, сборка с `STRATA_GGML_DIR`, `build-verify.bat` |
| `4af27c19` | `strata verify` логирует residency prior при старте |
| `8852b327` | `/v1/models` отдаёт `chat_template_caps` в meta |
| `976226a9` | serve: подсказки при старте — VRAM, CUDA, layout, флаги, краш |
| `2e1c2a04` | q36: диагностика OOM при экспертных буферах |
| `2fe24691` | serve: отказ batch-допуска — ошибка, а не завершённый запрос (#3040) |
| `2033a9dc` | q36: диагностика OOM для слотов экспертов и staging |
| `4f0b1248` | serve: читать вывод движка с `errors="replace"` |
| `59855142` | q36: профилировщик attention/GDN/MoE и отчёт (пул, reserve, hybrid-rows, attention-буфер) |
| `3ae7d409` | q36: per-request детерминизм — снимок размещения экспертов (#4604) |
| `aea22e2f` | serve: тест флага `strata_deterministic` в `sampling_keys` |
| `efec68e7` | q36: размер attention-буфера — env-флаг `STRATA_Q36_ATT_MB` |
| `c9ca876d` | q36: профиль запроса в serve-DONE; заметки форка на двух языках |
| `a00ab004` | q36: флаг `--att-mb` — размер attention-буфера без пересборки |
| `bbc034d4` | q36: pacc под T≤8 и L2-порядок split-K — 96k tg +28 % |
| `227ba006` | q36: профиль запроса — total, голова, quant и фазы MTP |
| `4b679a76` | q36: pinned host-арена экспертов по слоям — 96k pp +73 % |
| `53a8f8ca` | q36: доля pinned-арены — флаг `STRATA_Q36_PINNED_LAYERS` |
| `4569b243` | q36: count+scan маршрутизации в одном блоке — 96k pp 567–569 |

## Сборка

`..\harness\scripts\build_strata.bat` собирает `strata` и `strata-q36` в `build\`, `ggml` берётся
из соседнего git-клона `..\llama.cpp` (`-DSTRATA_GGML_DIR`). Для проверки переноса —
`build-verify.bat` (25 целей).

## Python и `.venv`

Один интерпретатор для сборки, тестов и `setup.py` — системный `C:\Program Files\Python314`
(Python 3.14.5); `.venv` в корне движка создан только на нём (пакеты из `requirements.txt`
и `requirements-build.txt`, cmake 4.4.3 и ninja 1.13.2 внутри). Тесты —
`.venv\Scripts\python.exe -m unittest`. Рантайм Qoder (3.15) и PyManager в проекте
не используются.

## Две копии llama.cpp

- `third_party\llama.cpp` — vendored-снимок upstream `3cf03257` без `.git`, не отслеживается
  (`.gitignore`); из него собран `build\bin\llama-server.exe`.
- `..\llama.cpp` — тот же коммит с git-историей; поставщик `ggml` для сборки движка.

Обе нужны; удаление клона ломает воспроизводимость (CMake скачает заново).

## Что добавлено по KV и MTP

- `--kv-type fp32|q8_0|q5_1|q5_0|q4_0`; на 48k q4_0 даёт +72 % к fp32 (20.5 → 35.3 tok/s);
- `--mtp 2 --draft-vocab 8192` — лучший профиль MTP (42.1 tok/s на 16k, 38.9 на 48k);
- Q5-файл с `ssm` в Q5_K требует перепаковки в Q8_0 (`harness\..\artifacts\glm\scripts\repack_ssm_q8.py`).

## Замеры и профили запуска

Итоговые профили 16/64/80/96/128k (Страта и llama.cpp), сетка `ncmoe`, `--prefill/--ub`,
профиль q36 и сравнение KV — `..\docs\measurements\` и `..\harness\reports\`.
Быстрый каталог документации — `..\docs\index.html` (открывается локально, без сервера).

Детали — `..\harness\docs\kv-quantization.md`, `..\harness\docs\mtp-vs-not.md`.

Исследовательские заметки (EN/RU) — `docs\research\`: идеи, не применимые к 8 ГБ
(sync `rmax`, MTP-only промпт), итог overlap H2D для llama.cpp (закрыто: upstream master даёт +7.2–8.5 %), crossover MMVQ/MMQ (закрыто: порог 8 не трогаем), аудит форка от
2026-11-04 (рычаг — чанк prefill; engine-on-master — no-go) и таблица отклонённых рычагов
с числами.
