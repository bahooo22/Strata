# qwen35 core evidence

База кода: `36e044b045bf18e35e3089a9527fc9c86c57ee88` (post-merge main). SourceRefs проверены на этом SHA.

## Границы

- `q36_main.cpp:5` → `strata::qwen35::run`.
- `q36_engine.cu:1515` загрузка `Model/Mat/Layer`.
- `q36_engine.cu:1719` `Engine`: буферы, sessions, graphs, hybrid, streams.
- `q36_engine.cu:4501` `Serve`: request/window orchestration.
- `q36_kernels.cuh`, `q36_fa.cuh`, `q36_fdec_decode.cuh`: device kernels/interfaces.
- MMQ и CPU pool вызываются через внешние interfaces; их внутренняя ownership требует отдельного inventory.

## Владение данными

| Объект | Владеет | Источник | Confidence |
|---|---|---|---|
| `Mat` | device weight pointer, type, shape | `q36_engine.cu:1366` | high |
| `Layer` | dense weights, expert layout, host/device blobs, slots | `q36_engine.cu:1372` | high |
| `Model` | geometry, layers, MTP, embeddings/head | `q36_engine.cu:1397` | high |
| `Engine` | activation arenas, KV views, streams, graphs, session vector | `q36_engine.cu:1719` | high |
| `Engine::Sess` | conv/S/KV/hlast/pos/live/imgs | `q36_engine.cu:1847` | high |
| `Engine::Hy` | slot_of/exp_in_slot, host cache, score, staging metadata | `q36_engine.cu:1888` | high |
| `Engine::GSet` | decode/verify/MTP graph execs | `q36_engine.cu:1769` | high |
| `Slot` | serve request state, sampling, draft, counters | `q36_engine.cu:4483` | high |

## Streams и синхронизации

- `Engine::st` — основной compute stream.
- `Engine::cst` — expert copy/prefetch stream.
- `ev_copy`, `ev_used`, `ev_route`, `ev_mread` — ordering между compute/copy/readers.
- `mread[2]` — host reader threads; destructor/stream_begin/stream_kick join перед reuse.
- `process()` синхронизирует stream перед повторным использованием pinned staging и после chunk.
- `moe_hybrid_cpu()` ждёт `ev_route` через `cudaEventQuery` busy-loop.
- MMQ prompt path делает D2H `rmax/count` и `cudaStreamSynchronize` на каждом layer.
- CUDA graphs хранят session-specific pointers; `copy_session` выполняет D2D copies и sync.

## Маршруты и fallback

| Путь | Условие | Fallback | Источник |
|---|---|---|---|
| FA prefill | `fa_layer == -2 || layer`, shape supported | cuBLAS QK/softmax/PV | `q36_engine.cu:2822-2876` |
| FDEC decode | KV_Q8/Q4, T<=4, fdec on | split-K attention | `q36_engine.cu:2924-2987` |
| MMQ prompt | layer_mmq и T>kGemmT | grouped/int8/P4 по поддержке | `q36_engine.cu:3037-3081` |
| Streamed grouped prompt | !use_mmq, T>kGemmT | native grouped | `q36_engine.cu:3082-3122` |
| Hybrid decode | lhy и rows/chunk policy | CPU pool + GPU slots | `q36_engine.cu:3029-3031`, `3410-3475` |
| Staging | cst/stage доступны | `layer_at(li).blobs` | `q36_engine.cu:3390-3392` |
| Graph | use_graph и graph key | eager body | `q36_engine.cu:3575-3607` |

## Известные ограничения

- Regex symbol index требует ручной проверки signatures/overloads.
- Lexical call graph не доказывает runtime dispatch; баннер и metrics обязательны.
- MMQ/CPU pool/fused interfaces находятся вне qwen35 и не полностью покрыты этим inventory.
- Нет runtime trace для подтверждения частоты fallback и hit-rate.
- Финальная модель должна быть привязана к post-merge SHA.
