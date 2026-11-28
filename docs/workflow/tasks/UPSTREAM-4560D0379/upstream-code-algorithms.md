# Upstream code algorithms — UPSTREAM-4560D0379

- Диапазон: `2af30ccaa0729177c4725ee2073f72bf550e2f86..4560d03793482ef367294cfbd86a4df8d5679e72`.
- Candidate: `2195f9b0f412d7e1f5447dad82a657e4db6904cc`; upstream-код читается read-only, строки ниже относятся к upstream `4560d0379`.
- `engine/src/qwen35/**` upstream не изменял. Прямое влияние на qwen35 указано отдельно; общий файл ещё не доказывает реальный вызов из qwen35.
- Performance-числа — заявления upstream из кода/commit messages, не замеры H.

## Сводка

| Алгоритм | Upstream commit(s) | Основные файлы | qwen35 |
|---|---|---|---|
| CPU dot-x4 policy | `5bafbe3bcdb1409b4852a29c605c84ef8a83f2aa` | `engine/include/strata/quant/dot_x4_policy.hpp`, `engine/src/kernels/cpu/native_expert.cpp` | потенциальный shared CPU pool; прямой вызов из q36 не найден |
| Split lend reservation | `7ab0d923c275c15002ff82e02336220a2e97d824` | `engine/src/core/expert_source.cpp` | shared file tier; qwen35 route требует проверки |
| GGUF startup stage pool | `34cf13848e6c22a72f88339b6a4cb4bc579fd4fb` | `engine/src/core/expert_source.cpp` | shared file tier |
| Dual-layout `.strata` reader | `0420a656e11e24bccd5c4446eb10466884a3c715` | `engine/src/artifact/strata_reader.cpp`, `engine/include/strata/artifact/strata_layout.hpp` | нет прямой связи с qwen35 engine |
| Fused launch diagnostics | `fd5fc4aa76ecfda8491f7897be0797ac9da0069f` | `engine/src/prefill/moe_fused_iq.cu` | общий prefill; candidate сохраняет наши IQ4_XS/IQ4_NL launches |
| Build/symbol/policy | `4fd373cfea1f6ea7acfa4d640cab2fe21ef0aa1f`, `017b6b86519e588d8aa8e809ba4d57bda03ba740`, `402cd017e4925e9cb14be6c71c5a3938ebb620d9`, `5bafbe3bc...` | `engine/CMakeLists.txt`, `engine/cmake/strata_symbols.cmake` | сборка всех backend, включая qwen35 |
| Custom setup builds | `e28d9222fa326cdd09322cfcb3d2e0e5d04331c1` | `terminal/setup.py`, `terminal/strata_control/custom_models.py` | Terminal qwen36/custom, не engine qwen35 |
| Hardware snapshot/refresh | `82623cd60c04087e72a4c9020c8d69f9bd27933d` | `terminal/setup.py`, `terminal/tools/strata_mcp.py` | Terminal latency, не numerics |
| Inkling lineup/planner | `4adbc88135bba02005b2c3f60ef02bc0b86e2550` | `terminal/strata_control/inkling_fit.py`, `terminal/setup.py` | нет |
| DFlash2 drafter | `d9d285068fe055a68b8051a34cacf88db2ce01ae`, `402cd017e...` | `engine/src/inkling2/cuda/ink_dflash2*.cuh`, `ink_cuda_backend.cu` | нет |
| Programmatic dependent launch | `9a0b4653db929ab0df95bba3885bd4cc6d3df347` | `engine/src/inkling2/cuda/ink_pdl*.cuh`, `ink_runner.cuh` | нет |
| Inkling2 tail-skip | `fa48f00d34afc84d835598c8ee1c5728c246d6a6`, `0eebd25829caead1d579b52d92248b6dbc6e72dc` | `engine/src/inkling2/cuda/ink_tail_skip.cuh`, `ink_moe_cuda.cuh`, `ink_tail_kl.h` | нет |
| Vision reader policy | `e62e8448d83180965431db2e26c31999f11d1dce`, `56829a8b5cd7a406b54d6b17172bd55d703760b4` | `engine/src/inkling2/ink_vision_policy.h`, `terminal/strata_control/vision_reader.py` | общий Terminal policy для qwen36 vision, не qwen35 numerics |

## 1. CPU dot-x4: выбор 4-row kernel по числу токенов

- Commit: `5bafbe3bcdb1409b4852a29c605c84ef8a83f2aa`.
- File:line: `engine/include/strata/quant/dot_x4_policy.hpp:28-45`; call sites `engine/src/kernels/cpu/native_expert.cpp:736-740` и `:861-865`; loops `:752-767` и `:874-883`.
- Trigger/inputs: `STRATA_DOT_X4`, `STRATA_NO_DOT_X4`, `nt` — число токенов, разделяющих один expert в вызове; arithmetic flavour и поддержка типа.
- Mechanism:
  1. `dot_x4_mode()` читает env один раз: `NO` всегда выигрывает, `1`/`0` форсируют, иначе mode `-1`.
  2. `dot_x4_enabled(mode,nt)` при auto включает 4-row только при `nt >= 2`.
  3. Gate/up и down выбирают `DotX4Kernel`; x4-loop обрабатывает четыре строки за вызов, затем остаток идёт обычным 1-row dot.
  4. Арифметика и scale/SwiGLU остаются прежними; upstream заявляет bit-equality.
- Outputs: те же `ff[t][r]` и `out[t][r]`; меняется только kernel dispatch.
- Ownership: activation rows принадлежат caller, weights — blob caller; kernel не сохраняет указатели.
- Streams/threads: CPU threads caller; row prefetch остаётся перед loops, нового sync нет.
- Fallback: unsupported type/ISA или `nt=1` → 1-row dot; env `NO_DOT_X4` → всегда 1-row.
- Complexity: policy O(1), основная работа O(rows × nt × hidden); x4 сокращает повторные загрузки activation, не меняет асимптотику.
- qwen35: `q36_engine.cu` включает `native_expert.hpp`, но прямой `dot_x4` call site в qwen35 не найден; проверить CPU pool route, если он используется.
- Performance hypothesis: upstream сообщает ~15% потерь warm batched decode и ~8% short prompt при выключенном x4 на 2×RTX 5090; solo decode лучше с 1-row.
- Mandatory tests: `dot_x4_policy_test`, `dot_x4_test`, `cpu_dispatch_dump`, native expert parity, qwen35 CPU-pool A/B при реальном использовании.

## 2. FileExpertSource: частичная резервация stage lend regions

- Commit: `7ab0d923c275c15002ff82e02336220a2e97d824`.
- File:line: `engine/src/core/expert_source.cpp:357-372` parser процента; `:4143-4186` расчёт reserve; `:4316-4335` двухфазная append.
- Trigger/inputs: `STRATA_SPLIT_LEND_RESERVE`, RAM budget, `stage_lend_regions_`, `layer_blob_bytes_`, ranked complement.
- Mechanism:
  1. `full`/unset/`auto` → 100%; `0..100` → явный процент.
  2. Для каждого региона берётся prefix `ceil(region.size × percent / 100)` от highest slot.
  3. Его байты вычитаются из complement cap; complement заполняется горячими rank-экспертами.
  4. Stage lend regions добавляются двумя проходами: зарезервированный prefix, затем остаток, пока вмещается budget.
- Outputs: `offsets`, `bytes`, `stage_lent`, план RAM copy; непопавшие expert остаются mapped-file fallback.
- Ownership: RAM copy принадлежит `FileExpertSource`; GPU cache/slot ownership не меняется.
- Streams/threads: планирование до allocation/stream; async fill использует существующие stage buffers/events.
- Fallback: 0% отключает reserve; переполнение региона оставляет хвост на файле; default 100 сохраняет прежний prompt-friendly режим.
- Complexity: O(regions × pairs + ranked complement), память O(offsets + rank + prefix vectors).
- qwen35: shared file tier; факт использования qwen35 layer-split/resident mode нужно подтвердить route log.
- Performance hypothesis: upstream приводит +5.5..9% decode при 0%, но −5..17% cold prompt; поэтому default остаётся 100%.
- Mandatory tests: unit percent parser, 2-GPU RAM-budget placement, prompt/decode A/B, file fallback и отсутствие перерасхода budget.

## 3. FileExpertSource: сохранение GGUF stage pool после startup

- Commit: `34cf13848e6c22a72f88339b6a4cb4bc579fd4fb`.
- File:line: `engine/src/core/expert_source.cpp:2200-2202` zero-size guard; `:3051` begin; `:3128-3168` end/release.
- Trigger/inputs: Windows startup unbuffered reads, `role_ptr_` (experts.bin vs GGUF in place), `stage_blob_`.
- Mechanism:
  1. При failure unbuffered read `stage_blob_` обнуляется только для experts.bin; GGUF in place сохраняет размер pool.
  2. `end_startup_unbuffered()` вызывает `release_startup_stage()`.
  3. Для GGUF pool остаётся: `blob()` продолжает собирать эксперты в stage buffers; для experts.bin pool освобождается.
  4. `claim_stage()` отказывается выделять zero-byte buffer при неизвестном размере.
- Outputs: корректный lifetime stage buffers; устранён heap overrun после первого окна.
- Ownership: pool и `stage_mu_` принадлежат source; CUDA events защищают DMA до free.
- Streams/threads: `cudaDeviceSynchronize()` перед освобождением live stage buffers; lock сериализует claim/release.
- Fallback: pinned allocation failure → pageable; неизвестный blob size → `claim_stage=false`, а не zero-size allocation.
- Complexity: claim amortized O(1), eviction scan O(pool) только при заполнении; sync редок.
- qwen35: shared file tier, если qwen35 использует GGUF in-place source; иначе не влияет.
- Performance hypothesis: корректность/lifetime, не ускорение; возможное устранение crash/OOM.
- Mandatory tests: Windows GGUF in-place startup→first window, experts.bin control, zero-size guard, pinned/pageable fallback.

## 4. Artifact reader: 4 KiB/16 KiB layout и vision shard

- Commit: `0420a656e11e24bccd5c4446eb10466884a3c715`.
- File:line: `engine/src/artifact/strata_reader.cpp:45-49`, `:64-68`, `:119-142`, `:164-177`; helpers `engine/include/strata/artifact/strata_layout.hpp:45-80`, `:87-135`, `:143-160`.
- Trigger/inputs: `.strata` header frame, file size, manifest, Section 3 flags/length.
- Mechanism:
  1. Параллельно проверяются таблицы 0x10/4 KiB и 0x20/16 KiB: id, alignment, ranges, overlap.
  2. Обе strict или ни одна → отказ; ровно одна → выбранный layout.
  3. Section 3 count для 16 KiB берётся из manifest; допускается менее одной страницы padding; Hy4 без count обрезает zero tail.
  4. `is_vision_shard()` распознаёт profile или top-level `arch=inkling2_vision`.
  5. `read_section()` отклоняет выход за file size до allocation.
- Outputs: `StrataHeader`, expert directory, vram order, manifest; vision classification.
- Ownership: reader владеет FILE и vectors до `close()`; consumers получают copied bytes.
- Streams/threads: синхронный file I/O, GPU streams не затрагиваются.
- Fallback: старый 4 KiB путь сохранён; truncated/ambiguous/overlapping header fail-closed.
- Complexity: header O(S log S), S=6; Section 3 O(n); memory O(section bytes + manifest).
- qwen35: прямого вызова нет; изменение важно для Inkling SQv2/vision и общих loader contracts.
- Performance hypothesis: поддержка нового layout без ускорения qwen35; избегает лишних alloc на corrupted file.
- Mandatory tests: `strata_reader_layout_golden`, 4K/16K fixtures, ambiguous/truncated/overlap, padded Section 3, vision shard detection.

## 5. Fused MoE: per-launch STRATA_PF_SYNC_DEBUG

- Commit: `fd5fc4aa76ecfda8491f7897be0797ac9da0069f`.
- File:line: `engine/src/prefill/moe_fused_iq.cu:80-112`; call sites `:3927`, `:3931`, `:3934`, `:3986`.
- Trigger/inputs: `STRATA_PF_SYNC_DEBUG=1`, stream, stage, types, rows, experts, tile/grid, blob pointers.
- Mechanism:
  1. До sync собираются pointer memory kinds для batch blobs.
  2. После каждого eligible launch выполняется `cudaStreamSynchronize`.
  3. При ошибке печатается конкретный stage/pair/grid и memory type, затем process exits.
  4. При выключенном флаге helper возвращается сразу, bits и launches не меняются.
- Outputs: диагностическая атрибуция fault; числовой output не меняется.
- Ownership: helper не владеет буферами и не сохраняет pointers.
- Streams/threads: принудительный sync только в diagnostic mode; на HIP используется `hipPointerGetAttributes`.
- Fallback: off — обычный `ck(cudaGetLastError)`; on — fail-fast с точным launch.
- Complexity: O(batch experts) pointer queries + O(stream drain) при включении; off O(1).
- qwen35: общий prefill helper; candidate должен сохранить наши IQ4_XS/IQ4_NL dispatch и обернуть их тем же debug path.
- Performance hypothesis: off — нулевая цена; on — intentional stall, только диагностика.
- Mandatory tests: default-off bit parity, CUDA/HIP compile, injected launch fault, проверка stage/pair/grid в stderr.

## 6. CMake: symbols, sm120/draft-rule tests и token policy

- Commits: `4fd373cfea1f6ea7acfa4d640cab2fe21ef0aa1f`, `017b6b86519e588d8aa8e809ba4d57bda03ba740`, `402cd017e4925e9cb14be6c71c5a3938ebb620d9`, `5bafbe3bc...`.
- File:line: `engine/CMakeLists.txt:13`, `:35-40`, `:334-341`, `:511-519`.
- Mechanism:
  1. `STRATA_KEEP_SYMBOLS` добавляет host-only debug info; device code не получает `-G`.
  2. MSVC получает `/Z7` + `/DEBUG /OPT:REF /OPT:ICF`; code sections должны остаться byte-identical.
  3. Регистрируются header-only tests `ink_sm120_table_test`, `ink_draft_rule_test`, `sm75_series_test`, `dot_x4_policy_test`.
  4. Defaults: sm75 series on, dot-x4 auto от двух токенов, ONE drafter residency-first.
- Outputs: те же binaries при symbols off; при on — те же code sections + PDB/debug sidecar.
- Ownership: build system; runtime ownership не меняется.
- Streams/threads: не применимо.
- Fallback: symbols off сохраняет прежний release path; tests no-GPU.
- Complexity: configure-time O(1), сравнение symbols O(binary sections).
- qwen35: build/policy changes затрагивают сборку qwen35, но не qwen35 source.
- Performance hypothesis: runtime не меняется; улучшается crash symbolication.
- Mandatory tests: `keep_symbols.py check`, перечисленные CTest, clean CUDA/HIP/SYCL/Metal compile.

## 7. Terminal setup: custom builds и единый hardware snapshot

- Commits: `e28d9222fa326cdd09322cfcb3d2e0e5d04331c1`, `82623cd60c04087e72a4c9020c8d69f9bd27933d`.
- File:line: `terminal/setup.py:7814-7893` custom; `:1808-1829` CPU registry; `:5151-5191` video scope.
- Trigger/inputs: `--gguf-dir`, `--custom-label`, family/model, existing custom configs; Windows hardware read.
- Mechanism:
  1. `run_tag()` создаёт отдельный `<tag>custom-<name>`, не затрагивая official config.
  2. `custom_weight_bytes()` считает один файл или все shards; `custom_build()` временно подставляет ближайший published build с реальным размером в planner.
  3. `add_custom_fields()` пишет custom metadata и model alias; official config остаётся отдельным.
  4. `win_video_scope()` кэширует один `Win32_VideoController` read на поток; CPU name читается из registry без PowerShell.
- Outputs: custom run config/tag, placement от реального file size, единый hardware snapshot.
- Ownership: пользовательские files не перезаписываются; `_CUSTOM` — process-local state setup.
- Streams/threads: thread-local video scope; background MCP refresh использует lock.
- Fallback: unsupported custom family → error; registry unavailable → PowerShell; custom temp build не меняет published pins.
- Complexity: shard count O(shards), config O(keys), hardware O(adapters) один раз.
- qwen35: Terminal qwen36/custom path; candidate KAT/Huihui `own_file/own_size/own_hf` должны остаться единственным pinned source.
- Performance hypothesis: upstream сообщает устранение 12 s freeze на Windows и снижение PowerShell starts с четырёх до одного.
- Mandatory tests: custom label/run_tag, shard size, official config untouched, KAT/Huihui pins/context_fit, hardware TTL/mocks.

## 8. MCP: stale-ok hardware refresh и model table

- Commit: `82623cd60c04087e72a4c9020c8d69f9bd27933d`.
- File:line: `terminal/tools/strata_mcp.py:736-765` Inkling metadata; `:1139-1201` hardware cache/refresh/scope.
- Trigger/inputs: `hardware(fresh,stale_ok)`, TTL 600 s, cached snapshot, launch UI.
- Mechanism:
  1. Fresh cache возвращается сразу.
  2. Устаревший cache при `stale_ok` возвращается немедленно, запускается один background refresh.
  3. Lock/`_hw_refreshing` запрещают два refresh; exception сохраняет старый snapshot.
  4. `_hardware()` использует setup `win_video_scope`, чтобы один read покрыл всех consumers.
- Outputs: hardware dict + current disk free; model table с offered/credit/update_available.
- Ownership: cache принадлежит `Strata` instance; refresh thread не меняет configs.
- Streams/threads: daemon thread, lock только вокруг state flag; actual hardware read вне lock.
- Fallback: failed refresh оставляет старый cache; first read синхронный.
- Complexity: cached O(1), refresh O(hardware probe) один раз.
- qwen35: Terminal latency/model table, не engine.
- Performance hypothesis: убирает key-press stall после TTL; upstream приводит 12 s Windows case.
- Mandatory tests: TTL/stale-ok, single refresh, failure keeps cache, model table KAT/Huihui and Inkling legacy.

## 9. Inkling2 DFlash2: block-diffusion drafter с target verification

- Commits: `d9d285068fe055a68b8051a34cacf88db2ce01ae`, `402cd017e4925e9cb14be6c71c5a3938ebb620d9`.
- File:line: `engine/src/inkling2/cuda/ink_dflash2.cuh:10-15`, `:30-68`, `:145-166`, `:698-798`; selection `ink_dflash2_path.cuh:19-71`, `:119-148`, `:151-172`; backend `ink_cuda_backend.cu:493-563`.
- Trigger/inputs: sidecar `dflash2.safetensors`/env path, slots, VRAM, sm_cc, target taps, anchor tokens, context rings.
- Mechanism:
  1. Default — DFlash2; нет sidecar → plain decode без drafter, не fallback на DSpark.
  2. Residency-first сравнивает планы с/без drafter; explicit `--draft on`/force обходят veto.
  3. Пять non-causal sliding-window layers строят 8-row block: anchor + 7 mask rows; causal conv, attention к 2048-ring, SwiGLU.
  4. Head делает top-16 + full-vocab tail, rank-256 bilinear selector выдаёт 7 ids/confidence.
  5. Target model verifies draft; итоговый token — target greedy argmax.
- Outputs: draft ids/conf только; target-owned logits/tokens.
- Ownership: per-slot rings и scratch принадлежат drafter; target KV/state принадлежит runner; draft не сохраняет target pointers.
- Streams/threads: один runner stream; draft заканчивается `cudaStreamSynchronize` перед host copy; OOM/ring failure → plain slot.
- Fallback: missing sidecar, no screen, `sm<60`, failed alloc/ring → no drafter/plain decode; explicit unsupported file → load error.
- Complexity: O(B × 7 × layers × (attention window + FFN) + vocabulary screen); rings O(slots × window × KV).
- qwen35: нет, отдельный `strata-inkling` engine.
- Performance hypothesis: quality сохраняется target verification; speed зависит от draft acceptance и ring residency, требует separate A/B.
- Mandatory tests: sidecar pins/layout, sm60/sm80/24GB variants, residency veto, ring OOM, target-logit equality, acceptance/tg.

## 10. Programmatic dependent launch для Inkling2 decode graphs

- Commit: `9a0b4653db929ab0df95bba3885bd4cc6d3df347`.
- File:line: `engine/src/inkling2/cuda/ink_pdl.cuh:46-74`, `:139-196`, `:200-234`; registry `ink_pdl_kernels.cuh:17-103`; runner `ink_runner.cuh:6536`, `:6683`, `:6731`, `:6791`, `:6856`.
- Trigger/inputs: captured CUDA graph, registered downstream kernel, CUDA ≥12.3, sm_90+, env `STRATA_INK_PDL`.
- Mechanism:
  1. Clone graph; классифицировать kernel nodes и block counts.
  2. Eligible ordinary kernel→kernel edge заменяется programmatic edge на upstream launch-completion port.
  3. Downstream blocks стартуют раньше, но первый `INK_PDL_WAIT()` ждёт завершения upstream и visibility writes.
  4. Non-kernel edges и unregistered kernels остаются обычными.
- Outputs: тот же graph exec и numerics; изменён launch overlap.
- Ownership: graph принадлежит runner; helper не владеет buffers.
- Streams/threads: device `griddepcontrol.wait`, host graph rewrite до instantiate.
- Fallback: unsupported API/device/code or rewrite failure → original `cudaGraphInstantiate`.
- Complexity: O(E + V) graph rewrite; runtime arithmetic не меняется.
- qwen35: нет, Inkling2-only.
- Performance hypothesis: upstream сообщает ~+5% plain decode на RTX 5090; default только cc12 160..192 SM.
- Mandatory tests: token equality, registered/unregistered edges, CUDA 12.3/sm90 gate, fallback, 5090 tg.

## 11. Inkling2 tail-skip: dropping малых router slots

- Commits: `fa48f00d34afc84d835598c8ee1c5728c246d6a6`, `0eebd25829caead1d579b52d92248b6dbc6e72dc`.
- File:line: `engine/src/inkling2/cuda/ink_tail_skip.cuh:1-18`, `:35-69`, `:96-160`; router `ink_moe_cuda.cuh:216-339`; args `:4191-4260`; launch `:4303-4305`.
- Trigger/inputs: `STRATA_INK_TAIL_SKIP`/`--turbo`, visit mask, top-8 weights, rank threshold, cap, cold/hot tables.
- Mechanism:
  1. Exact top-8 выбирается как раньше: sigmoid+bias, tie по id.
  2. Для rank ≥ threshold и доли ≤ thr/cap slot помечается dropped; optional resident fallback подменяет expert.
  3. Dropped slot получает id `-1`, weight 0; MoE bin не читает и не вычисляет expert; reduction остаётся 8-slot.
  4. `renorm=1` пересчитывает kept sum; `renorm=0` сохраняет веса.
- Outputs: изменённые ids/weights и немного другие logits; opt-in.
- Ownership: router owns topk; expert tables read-only; counters atomics принадлежат backend.
- Streams/threads: router и bin в том же stream; table load до graph capture; config change сбрасывает graph cache.
- Fallback: off/mask miss/exact path; hybrid/EP исключены из basic tail-skip, extended hybrid commit добавляет отдельный doorbell path.
- Complexity: O(top-8) на токен; выигрыш — меньше expert reads/compute.
- qwen35: нет, Inkling2-only.
- Performance hypothesis: upstream приводит ~3% expert reads при KL≈1e-3 для turbo и ~16% при KL≈0.013 для turbo-max; это не H-замер.
- Mandatory tests: `--tail-kl`, default-off equality, visit/rank/cap boundaries, hybrid/EP, resident fallback, quality/tg.

## 12. Vision reader policy: CPU/GPU по backend и памяти

- Commits: `e62e8448d83180965431db2e26c31999f11d1dce`, `56829a8b5cd7a406b54d6b17172bd55d703760b4`.
- File:line: `engine/src/inkling2/ink_vision_policy.h:22-27`, `:45-90`; Terminal `terminal/strata_control/vision_reader.py:38-55`, `:228-278`; backend reserve `ink_cuda_backend.cu:569-592`.
- Trigger/inputs: `--vision-reader gpu|cpu|auto`, backend, main-card GiB, vision shard, idle seconds.
- Mechanism:
  1. Explicit ask выигрывает.
  2. Mac → GPU; Intel Arc → CPU unless asked; CUDA/HIP <23.5 GiB → CPU; ≥23.5 → GPU.
  3. CUDA backend резервирует weights + buffers 1024-token picture до expert placement.
  4. На одном дискретном NVIDIA reader включается первым picture и выключается после idle 120 s.
- Outputs: reader mode и reserve bytes; numerics картинок должны совпадать между CPU/GPU в допуске.
- Ownership: vision module владеет reader buffers; expert budget принадлежит backend; idle lifecycle — backend.
- Streams/threads: reader launch/elastic lifecycle на backend stream; idle timer освобождает VRAM.
- Fallback: CPU reader при small card/Intel/asked; отсутствие vision shard → images off/error according to path.
- Complexity: policy O(1), memory reserve O(weights + 1024-token activation).
- qwen35: engine Inkling2-only, но Terminal `vision_reader.py` — общий qwen rule; qwen35 numerics не затрагиваются.
- Performance hypothesis: CPU на малой карте сохраняет VRAM для experts; GPU даёт fraction-of-second vs seconds; требуется карточный A/B.
- Mandatory tests: `test_vision_reader`, `ink_vision_policy_test`, backend/memory matrix, elastic idle, CPU/GPU embedding cosine.

## Итог по qwen35

- Upstream source delta qwen35 пуст; candidate guard подтверждает byte-identical `engine/src/qwen35` и include.
- Потенциальное shared влияние есть только через file tier/CPU policy/build infrastructure; прямых новых вызовов из qwen35 для DFlash2/PDL/Inkling tail-skip/vision нет.
- Inkling2/DFlash2/PDL/tail-skip/vision — отдельный `strata-inkling` runtime. Их acceptance не заменяет qwen35 160k/200k, MTP, FDEC, KAT/Huihui и fallback проверки.
- Defaults: tail-skip и PDL остаются opt-in/device-gated; dot-x4 auto включается от двух токенов; DFlash2 становится default только в Inkling2 и может быть veto по residency.
