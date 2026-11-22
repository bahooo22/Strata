# llama.cpp: апдейт форка, сборка апстрима, сравнение с Strata (Q0.2–Q0.3)

Дата: 2026-11-22.

## Форк (C:\Projects\Strata-3060Ti\llama.cpp)

- До: master 2ba6f5c83 (наших 71 коммит поверх старого апстрима; работы .github/workflows были удалены владельцем форка).
- `git fetch upstream master` → upstream/master = 8d60873df (upstream..master = 71, master..upstream = 157).
- Наши коммиты сохранены веткой **fork/pre-upstream-2026-11-22** (запушена).
- Merge: master = **5d623a0e5**, конфликты 16:
  - 15 × `.github/workflows/*` (modify/delete) — сохранено удаление (решение владельца форка);
  - `src/llama-mmap.cpp` — принята версия апстрима (fallback buffered I/O на EFAULT/EINVAL/**EIO**, seek по `read_offset`, дочитывание `to_read`); наша версия была упрощённой копией того же фикса.
- Запушено: master 5d623a0e5, ветка fork/pre-upstream-2026-11-22.

## Сборка апстрима (для сравнения, форк не тронут)

- Worktree: `G:/Research/llama/upstream` (upstream/master, detached), сборка `G:/Research/llama/build-upstream`.
- Скрипт: `glm/scripts/build_llama_upstream_2026-11-22.bat`.
  - Первая ошибка: `nvml.h: No such file` → заголовок/lib нашлись в `F:/CUDA/cuda-13.3-kit`; путь добавлен.
  - Вторая: `nvcc fatal: A single input file is required...` → `/I путь` в `CMAKE_CUDA_FLAGS` nvcc принимает за входные файлы; исправлено на `-IF:/CUDA/cuda-13.3-kit/include` без пробела. Третья сборка: 309/309 OK.
- Итог: **llama-server 1.0.0-dev, build 492, commit 8d60873df**, MSVC 19.51, CUDA 13.3, arch 86, GGML_CUDA=ON, targets llama-server (+bin/llama-server.exe).
- Флаги для сравнения подтверждены: `-fa`, `-nkvo`, `-ctk/-ctv`, `-ncmoe/--n-cpu-moe`.

## Сравнительный прогон (KAT IQ4_XS, промпт E:/tmp/master.txt, окно 160k)

Скрипт: `glm/scripts/run_llama_160k_2026-11-22.py` (тот же master.txt, 440 000 знаков; pp/tg из `llama_perf_context_print`).

| движок | режим | pp tok/s | tg tok/s | примечание |
|---|---|---|---|---|
| Strata 0.2.18+наши | 160k, att-mb 256, kv q4_0, super-chunk 8 | 899,9–901,7 | 15,2 | замеры 22.11 (ранее) |
| Strata MAP | то же + STRATA_Q36_EXPERT_CACHE_MB | 986,0 | 12,0 | |
| Strata FA tile4 | 16x32, профиль | см. fa-v2.md | — | под вопросом до прогона |
| llama-server 8d60873df | -ngl 99, -ncmoe 40/41, -nkvo, kv q4_0, -fa on | **159,9** | **4,04** | 139 278 ток.; 871,0 с prefill, 122 ток. за 29,9 с; ответ «Понял.» |

## Вывод

- На одном и том же промпте и окне (~160k) Strata 0.2.18+наши быстрее llama-server в **5,6 раза по prefill**
  (900 против 160 tok/s) и в **3,8 раза по декоду** (15,2 против 4,04 tok/s).
- Причина: у llama.cpp эксперты 40 из 41 слоя живут в CPU (`--n-cpu-moe`), и каждый чанк prefill тащит их через
  PCIe; у Страты — гибрид с пиннингом, int8/fused prompt-эксперты и super-chunk. Даже тюнинг ncmoe вниз
  (больше экспертов на 8 ГБ) не закрывает разрыв: модель 19 ГБ в VRAM не влезает.
- llama-портфель не обновляем: llama-server (build 492 / 8d60873df) остаётся справочным движком для сравнений.
- Идеи из llama.cpp ≥5 % для наших Q1/Q2 не выявлены: FA-ядро у них fattn-mma (ldmatrix + переиспользование
  B-фрагментов), но наш разрыв с ними объясняется не attention, а маршрутом экспертов; переносить нечего.
