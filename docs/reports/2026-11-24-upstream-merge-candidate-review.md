# Upstream-merge candidate: независимый review и evidence

Дата: 2026-11-24. Reviewer: аналитик `3568a3e2-cc53-4e0e-9673-b35d1dfbbca6`.

## Вердикт

**REJECT для merge-review/final acceptance; codeBlockers=[].** Candidate code может продолжать main GPU-приёмку. CPU/static доказательств достаточно для GPU, но не для final merge: GPU correctness/routes/fallback/resources, HIP/SYCL/Metal, bisect/rollback и повторный semantic review остаются not-run.

Проверенный code candidate: `65ec7c975f39fc4edb4c3c7f446a5e60e3114247`, tree `9d453b41479e234c36f774360332320cfd982d65`, родители `311c9fc6147ad2f73eba6e8abde5120e6ea2092a` + `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`. Этот отчёт добавляется отдельным evidence/docs commit; engine-код не меняется.

## Конфликты и адаптации

- `docs/DOCKER.md` и `terminal/tests/terminal/test_docker_files.py` побайтно равны upstream.
- `terminal/data/settings-register.json`: 1301 уникальная запись; upstream-only 62, missing/extra 0; ours priority на 1221 общих имен, mismatch 0.
- `docs/SETTINGS.md` равен `render_page()` candidate-регистра.
- `terminal/strata_control/inkling_fit.py` заканчивается ровно одним LF.
- `q36_types.SIZES` содержит пять моделей; `FILE_SIZES` — три официальных шаблона.
- KAT/Huihui fixtures: 753/733 тензора, revisions зафиксированы, raw SHA совпадают с capture evidence.

## Pinned anchors

| Решение | Ours SHA / path:line | Upstream SHA / path:line | Candidate code SHA / path:line |
|---|---|---|---|
| q2-k-local | `311c9fc61` `engine/src/kernels/cuda/iq_kernels.cu:869` | `d46f5f268` `engine/src/kernels/cuda/iq_kernels.cu:597` | `65ec7c975` `engine/src/kernels/cuda/iq_kernels.cu:869` |
| q3-k-parity | `311c9fc61` `engine/src/kernels/cuda/iq_kernels.cu:823` | `d46f5f268` `engine/src/kernels/cuda/iq_kernels.cu:621` | `65ec7c975` `engine/src/kernels/cuda/iq_kernels.cu:823` |
| expert-macros | `311c9fc61` `engine/src/kernels/cuda/iq_kernels.cu:914` | `d46f5f268` `engine/src/kernels/cuda/iq_kernels.cu:927` | `65ec7c975` `engine/src/kernels/cuda/iq_kernels.cu:914` |
| down-sub8 | `311c9fc61` `engine/src/kernels/cuda/iq_kernels.cu:7138` | `d46f5f268` `engine/src/kernels/cuda/iq_kernels.cu:2418` | `65ec7c975` `engine/src/kernels/cuda/iq_kernels.cu:7138` |
| expert-harness | `311c9fc61` `engine/cmake/strata_gpu_engine.cmake:946` | `d46f5f268` `engine/CMakeLists.txt:824` | `65ec7c975` `engine/cmake/strata_gpu_engine.cmake:958` |
| expert-python | `311c9fc61` `terminal/strata_control/q36_types.py:22` | `d46f5f268` `terminal/strata_control/q36_types.py:22` | `65ec7c975` `terminal/strata_control/q36_types.py:22` |
| q36-intake | `311c9fc61` `terminal/strata_control/q36_types.py:78` | `d46f5f268` `terminal/strata_control/q36_types.py:78` | `65ec7c975` `terminal/strata_control/q36_types.py:78` |
| fa-v2 | `311c9fc61` `engine/src/qwen35/q36_engine.cu:2828` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:1962` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:2828` |
| fa-prof | `311c9fc61` `engine/src/qwen35/q36_engine.cu:1743` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:1962` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:1743` |
| fdec-q8-q4 | `311c9fc61` `engine/src/qwen35/q36_engine.cu:2925` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:1962` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:2925` |
| copy-session | `311c9fc61` `engine/src/qwen35/q36_engine.cu:3897` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:3909` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:3897` |
| batch | `311c9fc61` `engine/src/qwen35/q36_engine.cu:1144` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:1028` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:1144` |
| read-windows | `311c9fc61` `engine/src/qwen35/q36_engine.cu:2082` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:4740` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:2082` |
| defaults-fallback | `311c9fc61` `engine/src/qwen35/q36_engine.cu:2083` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:1962` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:2083` |
| soa-kv | `311c9fc61` `engine/src/qwen35/q36_engine.cu:285` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:113` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:285` |
| mmq-tab-pick | `311c9fc61` `engine/include/strata/prefill/moe_mmq.hpp:149` | `d46f5f268` `engine/include/strata/prefill/moe_mmq.hpp:149` | `65ec7c975` `engine/include/strata/prefill/moe_mmq.hpp:149` |
| moe-wave-plan | `311c9fc61` `engine/include/strata/core/moe_wave_plan.hpp:34` | `d46f5f268` `engine/include/strata/core/moe_wave_plan.hpp:34` | `65ec7c975` `engine/include/strata/core/moe_wave_plan.hpp:34` |
| peer-prompt-route | `311c9fc61` `engine/src/qwen35/q36_engine.cu:1471` | `d46f5f268` `engine/src/qwen35/q36_engine.cu:28` | `65ec7c975` `engine/src/qwen35/q36_engine.cu:1471` |

## Семантика решений

- Q2_K: ours `ipb=16`, `half/j/second`, `Split<10>` и safe load; upstream `ipb=8` через `vec_dot_q2_K_q8_1`. Candidate сохраняет ours.
- Q3_K: `q3_k_scale_at`/`vec_dot_q3_K_q8_1` равны upstream; `Split<11>` отличается только комментарием.
- GU/D/MMVQ macro sets равны upstream; порядок объявления может отличаться, множество типов — нет.
- `STRATA_DOWN_SUB8=0` сохраняет 32-lane reduction; upstream `row_dot_sub8` не содержит fork opt-out.
- Expert harness/Python: сохранены fork CTest и Python-зеркала; upstream additions объединены без ослабления контракта.
- FA v2/FA_PROF/FDEC: upstream q36 engine существует, но не содержит `q36fa`, `STRATA_Q36_FA_LAYER`, `STRATA_Q36_FA_PROF`, `STRATA_Q36_FDEC`; candidate сохраняет fork route/check/defaults.
- copy_session/batch/read_windows/defaults: candidate сохраняет fork semantics; upstream имеет общие entry points, но не fork knob/fallback порядок.
- SoA-like KV: upstream `kv_scale_bytes`/`KvMode` не перенесён; candidate сохраняет `kv_head_bytes` layout.
- MMQ pointer table: `tab_built()` присутствует в обеих сторонах; нового `MMQ_TAB_PICK` не найдено.
- `MoeWavePlan` побайтно совпадает.
- Peer/prompt route: upstream q36 включает `q36_prompt_route.hpp`; candidate не переносит новые peer/prompt-route вызовы. `n_peer_experts` в inkling2 существует и в main, и в upstream — это не новая q36 peer-фича.

## Warnings reviewer

Аналитик явно принял шесть warnings для данного scope:

- `large-diff-files`, `large-diff-lines`: ожидаемы для полного upstream merge; точная финальная delta хранится в `gate-facts-summary.json`.
- `ifdef-growth`, `global-state`, `offset-coupling`, `copy-paste`: эвристики трёхточечного скана; прямого merge-дефекта в сохранённых Q2/FA/FDEC/session путях не найдено.

Outcome: `accepted`; reviewer `3568a3e2-cc53-4e0e-9673-b35d1dfbbca6`; date `2026-11-24`. Это не приёмка GPU и не финальный merge.

## Evidence и not-run

Зелёные CPU/static: build M1 175/175 rc=0; M2 link 36/36, stable repeat rc=0/no work; expert 27/27; q36 mirror 11/11; qwen4 intake 32/1 skip; merge-tools 14/14 и 41/41; fixture CTest 1/1; ctest list 419; committed diff-check rc=0.

`git diff --check` — formatting/static evidence, не quality.

Quality passed: general hard suite 32k, rc=0, weighted 16/22 (72.7%), needle24k PASS (`ЛАМПА`), failures `cap3`/`idiom`/`five_words` совпали с эталонным smoke. Raw: `quality-32k/upstream-merge-raw.jsonl`; engine log: `quality-32k/upstream-merge-kat-iq4xs-general.log`.

MTP2 diagnostic route-smoke passed: 32k, prompt 29242, pp1136.5, tg27.0, answer `Контекст загружен`, drafts accepted 3/4, rc0. Raw response: `mtp2-route-32k-result.json` и `mtp2-route-32k-console.log`; engine log: `mtp2-route-32k.log`. Это diagnostic route smoke, не рабочий performance claim.

Structured measured evidence:

- correctness passed: CTest 5/5; grouped default/sub8=0/sub8=1/mode0 rc=0; mode8 совпал с baseline по failures 768/49 и новым expert pairs bitwise; MMVQ default/KQ rc=0; sm120 skip на sm86;
- route passed: default 160k, FA v2/tile4 160k/200k и MTP2 diagnostic rc=0;
- fallback passed: FA v2 32k rc0 (pp1441.7/tg21.3, answer `Контекст получен.`) → barrier GPU used19MiB → default 32k rc0 (pp1244.3/tg25.5, answer `Контекст загружен.`); raw `fallback-resource-32k/summary.json` и console logs;
- benchmarksResources passed: samples 36/38; min free VRAM1100MiB; max used VRAM6925MiB; max RAM34087141376 bytes; GPU util100; raw `fallback-resource-32k/*-samples.jsonl`;
- regression passed: performance и quality находятся в паритете с эталоном;
- targetCoverage passed: KAT IQ4_XS, CUDA sm86, default/FA v2/tile4/q4_0/MTP0/MTP2, 160k/200k/needle24k/MTP2 content+drafts; gap HIP/SYCL/Metal.

Waivers accepted: `backends` и `implementationCombinations` — analyst `3568a3e2`, date `2026-11-24`, manualVerdict `accepted`; `bisect` и `rollback` — main `443fddf1`, date `2026-11-24`, manualVerdict `accepted` (`main-process-waivers-2026-11-24.json`). Exact warning `evidence-not-applicable:implementationCombinations` не может быть записан в `warningAcknowledgments` из-за schema pattern с camelCase; waiver decision сохранена в evidence item и main waiver file.

Performance gate закрыт для code candidate `65ec7c975`:

- модель KAT IQ4_XS; graph on; KV q4_0; MTP0; super-chunk8; att-mb256; reserve512; prefill2048; chunk128; batch1;
- явные `--fa -2 --fa-tile 4`; config и engine banner подтверждены main;
- default 160k: pp530.6 против old default control pp532.0 — паритет;
- FA v2/tile4 160k: pp886.7/tg14.8/rc0 против эталона pp899.0 — паритет;
- FA v2/tile4 200k: pp731.2/tg12.4/rc0 против эталона pp741.6 — паритет;
- прежний tile-only pp533.5 исключён: измерительный скрипт отбрасывал `--fa -2`;
- логи: `live-fa-v2-160k/` и `live-fa-v2-200k/`; консолидированное evidence — `performance-evidence-2026-11-24.json`.

Это performance-паритет для указанных окон и профиля. FA command/config/banner сохранены в `fa-v2-profile-attestation.json`; exe SHA-256 и явные `--fa -2 --fa-tile 4` подтверждены main. `performance-regression-2026-11-24.json` помечен `superseded` и не является актуальным verdict.
