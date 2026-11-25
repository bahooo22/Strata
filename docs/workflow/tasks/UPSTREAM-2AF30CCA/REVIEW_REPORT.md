# REVIEW_REPORT UPSTREAM-2AF30CCA

- Роль: `N`.
- Reviewer: `9ba7a8a6-9973-4bce-8a66-93acde030932`.
- Дата review: `2026-11-25`.
- Время review: `2026-11-25T15:46:20Z` / `2026-11-25T18:46:20+0300`.
- Candidate tip: `dcb524a6fe06f25fc0ba951d2017bb28ec9d07d1` (`D3`).
- Предыдущий tip: `033ee300a2fdefb66fab56e0a877baf0afb90abd` (`D2`).
- Code merge: `cc5f3e668ed66cba6cc862ab10e1b6ebc569c2b1` (`M`).
- Docs D1: `c8c939c05a4ef26de6daf55ec27c1677e97b916`.
- Base/ours: `996eb9195b1790f954dd48f50be27893cae93937`.
- Upstream: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- Merge-base: `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`.
- Verdict: `CODE_APPROVED`.
- Rejection code: отсутствует.
- Scope: code/evidence candidate D3.
- `INTEGRATION_APPROVED`, `MERGED`, commit/push/release не разрешены.

## C1–C10

| Критерий | Результат | Доказательство |
|---|---|---|
| C1 `code==TASK_IDEA/PLAN` | PASS | Scope прежний: upstream delta 4 commits/16 files, C1..C5 повторяют upstream, M tree=C5, qwen35 и fork-якоря сохранены. D3 не меняет `engine/terminal/tools`. |
| C2 correctness | PASS (static) | Code M не изменён с прошлого review; setup/HIP/version hunks соответствуют upstream. Tests присутствуют, но не запускались; runtime acceptance остаётся за A. |
| C3 security | PASS | D3 меняет только docs/evidence. В code delta нет новых сетевых входов, shell-вызовов, секретов, прав или зависимостей. |
| C4 fallback | PASS | HIP RAM slack и KV choice остаются HIP-only; non-HIP получает прежний путь. qwen35/runtime/MTP не изменены. |
| C5 `DOC_IMPL==code` | PASS | `DOC_IMPL.md:3-5` по-прежнему соответствует `terminal/setup.py:7555-7565,10572-10595,10620-10630` и `terminal/strata_control/inkling_fit.py:26-27,206-228`. |
| C6 `DOC_IMPL==TASK_IDEA` | PASS | Scope и решения не изменились: 4 upstream commits, 16 files, qwen35 untouched, KAT/Huihui/expert/planner/packaging anchors сохраняются. |
| C7 evidence protocol refs/windows | **PASS** | Все 10 пар `oursAlgorithm/upstreamAlgorithm` в `evidence/provisional-merge-plan.json` теперь непусты и различны. RU+EN D1 содержат обе строки каждой пары. `evidence-index.json`: 30/30 файлов и хэшей совпали до записи этого review. Refs/trees/ancestry/windows остаются корректными. |
| C8 base/ancestry valid | PASS | `merge-base ours upstream=d46f5f268`; оба refs являются предками D3. `C5=M` tree `d2d23a55…`; M parents `9ec1982ff`/`2af30cca`; D3 docs-only, tree `6de5ff47…`; qwen35 diff пуст. |
| C9 no subagents/delegation recorded | PASS | `docs/workflow/participants.json:3-5` и `TASK_IDEA.md:3-5` сохраняют A/H/N. N субагентов не запускал; self-approval отсутствует. |
| C10 no unapproved dependencies | PASS | D3 не меняет dependencies; code delta ограничена 16 заявленными upstream-файлами. |

## Закрытие прежнего `R_DOC`

Предыдущий review D2 имел хэш `44fb670e5605dc096bb0a1ed0e4e4549f128020364a07b14f895f188e13ac37b` и rejection `R_DOC` только из-за одинаковых algorithm-строк.

D3 исправляет ровно этот дефект:

- 10/10 пар `oursAlgorithm/upstreamAlgorithm` различны и описывают конкретные механизмы ours/upstream.
- RU+EN D1 перегенерированы и содержат обе строки каждой пары.
- `candidate-manifest.json` и `evidence-index.json` обновлены; прежний `R_DOC` сохранён как история в commit D3.
- Code merge `M`, tree `d2d23a55…`, qwen35 и fork defaults не менялись.

## Шесть architecture-вопросов

1. **Смысл алгоритмов.** Подтверждён: version bump не меняет вычисления; install-folder fix создаёт каталог до записи; HIP RAM slack добавляет `max(0.75 GiB, 5% expert GiB)` только для HIP/card+RAM/no SSD; HIP KV planner считает `min(ctx,32768)` и выбранный fp8/fp16.
2. **Ownership/readiness буферов.** Подтверждён: engine buffers, streams, graphs, kernels, ownership/readiness и qwen35 не изменены. HIP pool growth/spill — существующее поведение, не новый механизм.
3. **MTP/детерминизм/fallback.** Подтверждён: MTP/decode/seeds/graphs/runtime fallback не затронуты; HIP-изменения изолированы в planner, CUDA/SYCL/Metal/CPU сохраняются.
4. **Независимость частей.** Подтверждена: C1..C5 раздельны, M не вносит code diff относительно C5, hybrid/delta адаптации нет.
5. **Цена следующего merge.** Остаётся низкой: 4 upstream commits/16 files, additive HIP fixes, fork delta локализована в setup/planner/CMake/packaging, qwen35 guard пуст.
6. **Отдельная адаптация.** Не требуется: upstream применён напрямую, fork-якоря сохранены; ручное ревью нужно только при будущем изменении тех же зон.

## Проверенные факты

- Upstream delta: `4` commits, `16` files.
- Candidate code delta: `16` files, `292/24`; changed-line multiset равен upstream.
- `C5` tree = `M` tree = `d2d23a55d707d553ecc52e14c7fbe27d0748f993`.
- D3 tree: `6de5ff475537bee6d26cc846734a6c2b478172a0`; отличается от M только docs/evidence.
- D2→D3: шесть файлов — RU/EN D1, REVIEW_REPORT, candidate-manifest, evidence-index, provisional-merge-plan; code diff пуст.
- qwen35 diff `ours→D3` пуст.
- KAT/Huihui, `STRATA_Q6K_EXPERTS`, `STRATA_NATIVE_EXPERTS`, `q36_expert_info_test`, `VRAM_SAFETY_GB`, `KV_CARD_HEADROOM_GB`, `FREE_RAM_MARGIN_GB` сохранены.
- `git diff --check ours..C5` чист; conflict markers в code/docs отсутствуют.
- Stored `.diff` artifacts по-прежнему содержат валидные строки `+ `; outer whitespace gate должен исключать их либо использовать documented override.

## Ограничения

- Build/tests/GPU/quality/fallback/resources/full 160k/200k остаются `not-run`.
- `candidate-manifest.json` на D3 содержит исторический `review.verdict=R_DOC`; после записи `CODE_APPROVED` A должен обновить review metadata и хэш нового `REVIEW_REPORT.md` в manifest/evidence-index.
- Настоящий review одобряет только code/evidence candidate. Sync/merge/integration требует отдельных A checks и явного решения.

## Итог

`CODE_APPROVED` для `UPSTREAM-2AF30CCA` на tip `dcb524a6f`. Прежний `R_DOC` закрыт. `INTEGRATION_APPROVED` и `MERGED` не объявляются.
