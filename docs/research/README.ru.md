# Research notes: designs measured and not applied (RU)

Заметки об изменениях движка, которые были разобраны и (где возможно) измерены на
референсной машине форка: RTX 3060 Ti 8 ГБ, 32 ГиБ RAM, MoE-модель 35B-A3B, у которой
16.34 ГиБ routed-экспертов лежат в оперативной памяти (hybrid-режим). Часть идей здесь
отклонена, но полезна на других конфигурациях; другие — готовые проекты для желающих.

| Файл | Тип | Кратко | Почему здесь |
| --- | --- | --- | --- |
| [routing-sync.ru.md](routing-sync.ru.md) | идея | Убрать `cudaStreamSynchronize` на слое ради `rmax` | Помогает только когда все эксперты в VRAM; при hybrid тот же sync несёт `rcnt` для score слотов |
| [mtp-only-prompt.ru.md](mtp-only-prompt.ru.md) | идея | Промпт MTP-блока через MMQ + staging вместо CPU-пула | Нужны основные слои целиком в VRAM, то есть модель, чьи эксперты влезают; с 16.34 ГиБ в 8 ГБ недостижимо |
| [llama-h2d-overlap.ru.md](llama-h2d-overlap.ru.md) | закрыто | Перекрыть H2D экспертов с вычислениями в llama.cpp | Потолок +3-7 % pp (заглядывания на слой нет); upstream master уже даёт +7.2-8.5 %/+7.1 %, а на 128k нет VRAM под второй staging-слот |
| [mmvq-crossover.ru.md](mmvq-crossover.ru.md) | закрыто | Crossover MMVQ/MMQ для `MUL_MAT_ID` на 9-32 токена | На n=9 время в 1.63-1.81 раза больше, чем на n=8, но профиль работает на n=1 (decode) и n=2048/8192 (prefill), поэтому порог не тронут; `test-crossover.patch` рядом |
| [rejected-levers.ru.md](rejected-levers.ru.md) | замеры | Флаги и ядра, которые пробовали и стало медленнее | Числа, чтобы никто не повторял |
| [super-chunk.ru.md](super-chunk.ru.md) | применено | Слой-мажорный prefill: эксперты слоя стейджатся один раз на N чанков | N=4 даёт +25/+28/+21 % pp на 64k/96k/128k; при N=1 бит-в-бит |
| [audit-fork-2026-11-04.ru.md](audit-fork-2026-11-04.ru.md) | аудит | Где теряется время в форке: доставка весов экспертов, а не GPU-ядра | Измеренный рычаг — размер чанка prefill (96k: 573.8 -> 1094.3 pp на 2048); переход движка на upstream master — no-go |

Применённые оптимизации — в `engine/docs/profile-q36.md` и в истории коммитов
(`pacc` при T ≤ 8, L2-порядок split-K, per-layer pinned арена, `--att-mb`,
профилировщик, route count+scan, pinned/профиль llama; super-chunk —
[super-chunk.ru.md](super-chunk.ru.md)).

Методика во всех заметках: один GPU-прогон за раз, полный GGUF (KAT IQ4_XS), память
+1003 МГц, медианы трёх прогонов, первый прогон серии отбрасывается как шум прогрева.
