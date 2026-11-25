# Пять улучшений qwen35 — ranked shortlist

Дата: 2026-11-25. База кода: `36e044b045bf18e35e3089a9527fc9c86c57ee88` (post-merge main). Профиль оценки: KAT IQ4_XS, RTX 3060 Ti 8 GiB, 160k/200k, graph on, q4_0, MTP0, super-chunk8, att256, reserve512, FA v2/tile4. Все проценты — оценки, не замеры; эффекты перекрываются и не складываются.

Правило отбора: улучшения с приростом производительности ниже 5% не рассматриваются для реализации. Гипотезы с верхним диапазоном ниже 5% исключаются до plan/code/build/GPU; диапазоны, пересекающие 5%, допускаются только с планом приёмки, который должен подтвердить не менее 5% end-to-end.

| Rank | Гипотеза | Phase effect | End-to-end | Confidence | Риск |
|---:|---|---|---:|---|---|
| 1 | Adaptive expert-slot rebalance/prefetch по runtime `L/U`, recent routing и ctx | MoE tg +5–12% | +3–8% tg, +1–3% pp | medium | средний: swaps, slot displacement, лишний H2D |
| 2 | Adaptive super-chunk по ctx/VRAM/slots/staging | prefill +5–10% | +3–7% pp | medium | средний: память, MTP overhead, cancellation |
| 3 | Adaptive stream depth 2→3/4 с ticket/lifetime guards | H2D overlap +4–9% | +2–6% pp | medium | средний: VRAM, late write, cache pollution |
| 4 | Device-side MMQ route metadata без D2H `rmax/count` | route/sync +2–5% | +1–3% pp | high | низкий-средний: bounds/maxr contract |
| 5 | Event-driven CPU MoE handoff вместо busy-wait | host wait +2–6% | +1–4% tg | medium | низкий-средний: wake latency, pool scheduling |

## 1. Adaptive expert-slot rebalance/prefetch

| Поле | Содержание |
|---|---|
| Механизм | Собирать per-layer `L` (expert-token load) и `U` (unique experts), выбирать resident slots и prefetch по недавнему окну маршрутизации, ctx и доступной VRAM; сохранить exact fallback на текущую политику. |
| Источник | `engine/src/qwen35/q36_engine.cu:3484-3530` — every32/max8/halving; `engine/src/qwen35/q36_engine.cu:3313-3406` — whole-layer double-buffer prefetch. Внешний аналог: AdaOffload, offline cost model + online `L/U`; SGLang RFC #50336, frequency hot set и slot displacement. |
| Ожидаемый эффект | MoE tg +5–12%; end-to-end +3–8% tg и +1–3% pp на 160k/200k. Это диапазон гипотезы, не перенос внешних процентов. |
| Confidence | medium |
| Риски | Частые swaps увеличивают H2D и latency; вытеснение hot experts снижает hit-rate; scores могут зависеть от traffic; возможны просадки quality/MTP и нехватка VRAM. |
| Проверка | Отдельный experiment branch; hit/miss, swaps, transferred bytes, arrival/use, pp/tg 160k/200k, quality, MTP2, resource peaks; сравнение с fixed-slot control в том же окне. |
| Условия отката | Архив, если end-to-end выигрыш меньше шума 1.5%, swaps/H2D растут без hit-rate выигрыша, quality/MTP расходятся или появляется OOM/illegal access. |

## 2. Adaptive super-chunk

| Поле | Содержание |
|---|---|
| Механизм | Выбирать `super_n` по ctx, свободным expert slots, staging memory и MTP overhead вместо фиксированного значения 8; сохранить текущий путь как fallback. |
| Источник | `engine/src/qwen35/q36_engine.cu:3670-3707`; `docs/profile-q36.md:171-190`, исторические N=4 дали +21–28% pp на 64k/96k/128k. Внешний аналог: AdaOffload переключает prefill policy по длине и стоимости transfer/compute. |
| Ожидаемый эффект | Prefill +5–10%; end-to-end +3–7% pp на 160k/200k. Исторический выигрыш N=4 не считается прогнозом для рабочих окон. |
| Confidence | medium |
| Риски | `xsuper/hsuper` и staging растут с N; MTP по под-чанкам добавляет overhead; cancellation и session boundaries усложняются; при нехватке slots возможен OOM. |
| Проверка | Отдельные N на 160k и 200k, VRAM/RAM peaks, TTFT, cancel, MTP2, bitwise greedy; A/B только одного изменённого параметра. |
| Условия отката | Архив, если выигрыш pp ниже шума, tg/quality/MTP ухудшаются, peak memory превышает бюджет или cancellation становится некорректной. |

## 3. Adaptive stream depth

| Поле | Содержание |
|---|---|
| Механизм | Проверить 3/4 staging buffers и prefetch depth вместо двух; явные ticket/lifetime guards и bounded wait; fallback на два буфера. |
| Источник | `engine/src/qwen35/q36_engine.cu:3313-3406` — два staging buffers и prefetch следующего слоя. Внешний аналог: Megatron Core GTP, per-weight prefetch chains и ticket buffer cache; SGLang RFC #50336 сообщает о примерно 10% slowdown при чрезмерном prefetch. |
| Ожидаемый эффект | H2D overlap +4–9%; end-to-end +2–6% pp на 160k/200k. |
| Confidence | medium |
| Риски | Дополнительная VRAM/staging memory; late write/use-after-free; cache pollution; лишние копии могут замедлить throughput; graph capture и fallback усложняются. |
| Проверка | H2D bytes, overlap, arrival/use, late-write guard, VRAM, pp/tg, long-prompt quality; отдельные depth=2/3/4 точки. |
| Условия отката | Архив, если depth>2 не даёт end-to-end выигрыша сверх шума, повышает H2D/VRAM без overlap или ломает lifetime/graph invariants. |

## 4. Device-side MMQ route metadata

| Поле | Содержание |
|---|---|
| Механизм | Вычислять bounds/maxr на device и запускать MMQ с conservative upper bound либо graph-safe device metadata; убрать host round-trip `rmax/count`. |
| Источник | `engine/src/qwen35/q36_engine.cu:3042-3049` — D2H `rmax/count` и `cudaStreamSynchronize` на каждом prompt layer. Внешний аналог: llama.cpp issue #29949, `LRU_DECIDE/LRU_FILL` внутри compute graph без per-step D2H expert ids. |
| Ожидаемый эффект | Route/sync +2–5%; end-to-end +1–3% pp на 160k/200k. |
| Confidence | high |
| Риски | Неверный maxr/bounds даёт OOB или пропуск строк; conservative bound может увеличить работу; graph capture/replay и hybrid scores требуют отдельной проверки. |
| Проверка | Numeric parity, maxr bounds, graph capture/replay, pp, correctness; сравнение с текущим host-readback path на одинаковом prompt. |
| Условия отката | Архив при любом расхождении outputs/bounds, graph failure, illegal access или end-to-end эффекте ниже шума. |

## 5. Event-driven CPU MoE handoff

| Поле | Содержание |
|---|---|
| Механизм | Заменить busy-loop `cudaEventQuery(ev_route)` на event/callback или condition-variable handoff; сохранить короткий spin только при измеренном выигрыше. |
| Источник | `engine/src/qwen35/q36_engine.cu:3424-3475` — busy-loop перед CPU pool. Внешний аналог: NVIDIA CUDA guidance рекомендует events/streams; AdaOffload использует spin polling для CPU worker tails, поэтому слепой отказ от spin не обоснован. |
| Ожидаемый эффект | Host wait +2–6%; end-to-end +1–4% tg на 160k/200k. |
| Confidence | medium |
| Риски | Wake latency может съесть выигрыш; pool scheduling и host contention; callback/context lifetime; короткий decode может выигрывать от spin. |
| Проверка | CPU wait time, wake latency, tg, pool utilization, long decode; отдельные spin/event варианты. |
| Условия отката | Архив, если wake latency превышает экономию busy-wait, tg не растёт или появляются зависания/потеря событий. |

## Решение по порогу 5%

- #4 Device-side MMQ route metadata: исключён, верхний диапазон +1–3% pp ниже 5%. Carrier-план H сохранён как evidence, но code/build/GPU не запускаются.
- #5 Event-driven CPU MoE handoff: исключён, верхний диапазон +1–4% tg ниже 5%.
- #1, #2 и #3 остаются кандидатами только потому, что их диапазоны пересекают 5%; любой из них требует отдельного плана с обязательной приёмкой ≥5% end-to-end.

## Рекомендация

- Максимальный ожидаемый эффект: #1, но у него выше стоимость и риск.
- Первый practical candidate после порога 5%: #2 Adaptive super-chunk — исторические замеры N=4 дали +21–28% pp на меньших окнах, carrier текущего main подходит, а риск локальнее, чем у #1.
- #3 тестировать отдельным A/B; #1 — только после отдельного сравнения риска и ожидаемого эффекта.
- Следующий шаг — новый `TASK_IDEA` workflow v3 для #2, без реализации до утверждения пользователя.
