# qwen35 core — архитектурное понимание

База кода: `36e044b045bf18e35e3089a9527fc9c86c57ee88` (post-merge main).

## Граница

Ядро qwen35 принимает GGUF qwen35moe, загружает геометрию и веса, управляет recurrent/KV состоянием сессий, выполняет prefill/decode/MTP и отдаёт токены через `serve` протокол. Вход — `q36_main.cpp:5` → `strata::qwen35::run`; orchestration — `Engine` и `Serve` в `q36_engine.cu`.

## Основные части

- `Model/Mat/Layer` владеют GGUF metadata, device weights и expert layout.
- `Engine` владеет activation arenas, streams, graphs, session vector, hybrid slots и staging buffers.
- `Engine::Sess` владеет conv/S/KV/hlast/pos/live/imgs; `select()` подключает выбранную сессию к текущим указателям.
- `Engine::Hy` описывает GPU expert slots, host cache и routing scores.
- `Engine::GSet` хранит decode/verify/MTP graph execs с указателями текущей сессии.
- `Serve` управляет request/session slots, sampling, batch windows и MTP proposals.

## Runtime-пути

1. **Prefill:** `Serve::request` → `Engine::process` → `forward/forward_super` → `layer` → mixer (attention или GDN) → router/MoE → shared expert → `moe_end` → head. Для streamed experts `stream_begin/kick/take/done` перекрывают H2D со счётной частью.
2. **Decode/batch:** `Serve::window/window_plain/window_mtp` → `step_rows/run_rows` → `forward` → `commit_rows`; session state обновляется через batch tables.
3. **MTP:** `spec_step` → `forward_mtp` draft → verify window через main model → `commit` принятых строк; `window_mtp` делает proposals для нескольких slots.

## Владение данными и синхронизации

- Основной compute stream — `Engine::st`; expert copy/prefetch stream — `Engine::cst`.
- `ev_copy/ev_used/ev_route/ev_mread` задают порядок между compute, copy и host reader threads.
- Pinned staging переиспользуется только после stream sync; `moe_hybrid_cpu` ждёт routing event busy-loop.
- MMQ prompt path делает D2H `rmax/count` и stream sync на каждом layer.
- CUDA graphs хранят session-specific pointers; `copy_session` выполняет D2D copies и sync.

## Фактические маршруты и fallback

- FA prefill включается явно (`fa_layer=-2`/конкретный слой); при неподдерживаемой форме остаётся cuBLAS QK/softmax/PV.
- FDEC decode работает только для KV_Q8/Q4, T≤4 и включённого флага; иначе split-K attention.
- MoE prompt выбирает MMQ, streamed grouped, int8/P4 либо hybrid rows по поддержке и форме; hybrid CPU pool дополняет GPU slots.
- Staging может отсутствовать по VRAM; тогда используются обычные expert blobs.
- Graph capture отключается для профилирования и fallback-путей.

## Горячие места

Исторический профиль `docs/profile-q36.md`: MoE 86–91% времени, attention 3–9%, GDN ~5%. Поэтому primary improvements должны целиться в MoE, expert transfer, host sync и scheduling, а не только в attention kernels.

## Уверенность и пробелы

Структура и вызовы подтверждены кодом и sourceRefs. Лексический call graph не доказывает частоту runtime dispatch; hit/miss, fallback frequency и resource peaks требуют отдельных замеров. MMQ/CPU pool/fused interfaces находятся вне qwen35 и покрыты частично.
