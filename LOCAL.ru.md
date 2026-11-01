# Локальные изменения этого форка

Upstream: `https://github.com/Niko1221/Strata` (версия 0.2.8, engine 0.1.54).
Ветка форка — `q8-kv`; локальные коммиты поверх 0.2.8:

| Коммит | Что |
| --- | --- |
| `30ecea71` | подсказка `--mtp 0` и `STRATA_MMQ_KQ=0` в ошибке нехватки VRAM |
| `16d4a122` | страж `qwen35moe` не требует MTP-ключ: сторонние GGUF читаются |
| `a1589144` | загрузчик q36 принимает IQ4_XS в `ssm_alpha/beta` |
| `ea60ce21` | резерв VRAM стал флагом `--vram-reserve-mib` |
| `83f02fea` | квантованный q8_0 KV-кэш флагом `--kv-type` |
| `5fa0f445` | KV-типы q4_0, q5_0, q5_1 (раскладки ggml, единый байтовый буфер) |

## Сборка

`..\harness\scripts\build_strata.bat` собирает `strata` и `strata-q36` в `build\`, `ggml` берётся
из соседнего git-клона `..\llama.cpp` (`-DSTRATA_GGML_DIR`). Для проверки переноса —
`build-verify.bat`.

## Две копии llama.cpp

- `third_party\llama.cpp` — vendored-снимок upstream `3cf03257` без `.git`, не отслеживается
  (`.gitignore`); из него собран `build\bin\llama-server.exe`.
- `..\llama.cpp` — тот же коммит с git-историей; поставщик `ggml` для сборки движка.

Обе нужны; удаление клона ломает воспроизводимость (CMake скачает заново).

## Что добавлено по KV и MTP

- `--kv-type fp32|q8_0|q5_1|q5_0|q4_0`; на 48k q4_0 даёт +72 % к fp32 (20.5 → 35.3 tok/s);
- `--mtp 2 --draft-vocab 8192` — лучший профиль MTP (42.1 tok/s на 16k, 38.9 на 48k);
- Q5-файл с `ssm` в Q5_K требует перепаковки в Q8_0 (`harness\..\artifacts\glm\scripts\repack_ssm_q8.py`).

Детали — `..\harness\docs\kv-quantization.md`, `..\harness\docs\mtp-vs-not.md`.
