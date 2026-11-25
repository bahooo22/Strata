# REVIEW_REPORT UPSTREAM-2AF30CCA

- Роль: `N`.
- Reviewer: `9ba7a8a6-9973-4bce-8a66-93acde030932`.
- Дата review: `2026-11-25`.
- Время review: `2026-11-25T15:39:10Z` / `2026-11-25T18:39:10+0300`.
- Candidate tip: `033ee300a2fdefb66fab56e0a877baf0afb90abd` (`D2`).
- Code merge: `cc5f3e668ed66cba6cc862ab10e1b6ebc569c2b1` (`M`).
- Docs D1: `c8c939c05a4ef26de6daf55ec27c1677e97b916`.
- Base/ours: `996eb9195b1790f954dd48f50be27893cae93937`.
- Upstream: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- Merge-base: `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`.
- Verdict: `R_DOC`.
- Failed criterion: `C7`.
- Code candidate `M`: статически одобряется, не отклоняется.
- Final evidence candidate `D2`: отклоняется до исправления документации/evidence.
- `INTEGRATION_APPROVED`, `MERGED`, commit/push/release не разрешены.

## C1–C10

| Критерий | Результат | Доказательство |
|---|---|---|
| C1 `code==TASK_IDEA/PLAN` | PASS | `TASK_IDEA.md:13-45` и `PLAN.md:13-50` требуют upstream delta 4 commits/16 files, сохранения fork-якорей и qwen35. Фактический `git diff ours..C5` — 16 файлов, 292 добавления/24 удаления; multiset изменённых строк полностью совпал с `git diff merge-base..upstream`. |
| C2 correctness | PASS (static) | C1..C5 повторяют upstream content commits; M имеет tree C5. Setup/HIP hunks соответствуют upstream. Tests добавлены, но не запускались; runtime acceptance остаётся за A. |
| C3 security | PASS | Изменены только version/docs/setup/planner/tests. Нет новых сетевых входов, shell-вызовов, секретов, прав или зависимостей. `mkdir` использует существующие install/config paths. |
| C4 fallback | PASS | HIP RAM slack применяется только при `backend=="hip"`, card+RAM, без SSD и без `full_vram` (`terminal/setup.py:10586-10595`). `inkling_plan_kv` возвращает `{}` для non-HIP (`terminal/setup.py:10620-10630`). qwen35/runtime/MTP не изменены. |
| C5 `DOC_IMPL==code` | PASS | `DOC_IMPL.md:3-5` соответствует `write_config/write_run_script` (`terminal/setup.py:7555-7565`), HIP slack (`:10572-10595`), HIP KV window/type (`terminal/strata_control/inkling_fit.py:26-27,206-228`; `terminal/setup.py:10620-10630`) и version bump. |
| C6 `DOC_IMPL==TASK_IDEA` | PASS | Оба документа задают тот же scope: 4 upstream commits, 16 files, qwen35 untouched, KAT/Huihui/expert/planner/packaging anchors сохраняются, runtime acceptance отдельно. |
| C7 evidence protocol refs/windows | **FAIL** | Refs, ancestry, trees и windows зафиксированы верно, но semantic evidence неполон: все 10 пар `oursAlgorithm/upstreamAlgorithm` в `evidence/provisional-merge-plan.json` идентичны; D1 RU/EN повторяют одну и ту же строку в обеих algorithm-колонках. Это не доказывает различие алгоритмов ours/upstream и нарушает обязательное semantic review правило. |
| C8 base/ancestry valid | PASS | `merge-base ours upstream=d46f5f268`; оба refs являются предками D2. `C5=M` tree `d2d23a55…`; M parents `9ec1982ff`/`2af30cca`; D1/D2 меняют только docs. qwen35 diff пуст. |
| C9 no subagents/delegation recorded | PASS | `docs/workflow/participants.json:3-5` фиксирует A/H/N; `TASK_IDEA.md:3-5` и H package verification фиксируют роли. N субагентов не запускал; self-approval отсутствует. |
| C10 no unapproved dependencies | PASS | Delta ограничена 16 заявленными файлами; package manifests, lockfiles, CI и внешние сервисы не изменены. |

## Блокирующий дефект evidence

`evidence/provisional-merge-plan.json` содержит одинаковые строки в парах:

- `:50-51` release-version-bump;
- `:260-261` setup-install-folder;
- `:470-471` setup-hip-ram-slack;
- `:680-681` hip-kv-window-choice;
- `:890-891` qwen36-catalog-preserve;
- `:1100-1101` expert-build-preserve;
- `:1310-1311` fork-planner-base;
- `:1520-1521` packaging-fork-notes;
- `:1730-1731` upstream-tests;
- `:1940-1941` qwen35-no-delta.

D1 `docs/upstream-merges/2af30ccaa072-cc5f3e668ed6-2026-11-25.ru.md:20-29` и `.en.md:20-29` переносят эту одинаковоту в колонки «Алгоритм ours/upstream». `DOC_IMPL.md` описывает результат корректно, но не заменяет per-row semantic matrix.

### Обязательные исправления

1. Заполнить различные `oursAlgorithm` и `upstreamAlgorithm` для каждой matrix-строки. Минимальное содержание:
   - release: ours `Control 0.1.67 / Terminal 0.2.21`; upstream `Control 0.1.68 / Terminal 0.2.21.1`, app/engine packages без изменений.
   - install folder: ours не создаёт parent перед первым config; upstream создаёт `STRATA_INSTALL_DIR`, `write_config.parent` и `home()`.
   - HIP RAM slack: ours без HIP-specific slack; upstream `max(0.75 GiB, 5% expert GiB)`, bounded free RAM, только HIP/card+RAM/no SSD.
   - HIP KV: ours планирует полный context/прежний KV type; upstream `min(ctx,32768)` и выбранный fp8/fp16 только для HIP.
   - qwen36: ours содержит KAT/Huihui IQ4_XS; upstream эти записи не содержит.
   - expert build: ours сохраняет `STRATA_Q6K_EXPERTS`, `STRATA_NATIVE_EXPERTS`, `q36_expert_info_test`; upstream delta меняет только version line.
   - planner base: ours сохраняет `VRAM_SAFETY_GB/KV_CARD_HEADROOM_GB/FREE_RAM_MARGIN_GB`; upstream добавляет HIP window, не меняя fork constants.
   - packaging: ours сохраняет fork sections; upstream обновляет version line.
   - tests: ours сохраняет существующие tests; upstream добавляет setup/HIP/release regression coverage.
   - qwen35: ours и upstream не имеют delta; candidate обязан быть побитово равен ours.
2. Перегенерировать RU+EN D1 из исправленного plan.
3. Создать новый docs-only commit после D2, обновить candidate manifest/evidence-index/hashes и повторить N review на новом final tip. Code M/tree `d2d23a55…` менять нельзя.
4. Не выдавать исправленный documentation commit за новую code acceptance: code diff `M→new tip` по `engine/terminal/tools` должен остаться пуст.

## Шесть architecture-вопросов

### 1. Смысл алгоритмов

- Version bump не меняет вычисления: Control `0.1.68`, Terminal `0.2.21.1`, app/engine packages остаются `0.2.21/0.1.67`.
- Install-folder fix создаёт родительский каталог до атомарной записи config/run script.
- HIP RAM slack добавляет RAM cap room только для HIP card+RAM/no SSD: `max(0.75 GiB, 5% экспертов)`, ограниченный свободной RAM.
- HIP KV planner считает `min(context,32768)` токенов на slot и выбранный fp8/fp16; pooled K/V растёт по требованию и при заполнении карты переходит в host-mapped pinned memory.

### 2. Ownership/readiness буферов

Engine buffers, ownership, readiness, streams, graphs, kernels и qwen35 не изменены. Delta касается только setup/planner/version/docs/tests; поэтому buffer lifetime и readiness invariants остаются прежними. HIP-комментарии описывают существующий pool growth/spill, а не новый ownership-механизм.

### 3. MTP/детерминизм/fallback

MTP, decode, deterministic seeds, CUDA graphs и runtime fallback не затронуты. HIP-изменения изолированы в planner и не меняют CUDA/SYCL/Metal/CPU. Fallback pool→host остаётся существующим поведением HIP engine; новый автоматический failover не добавляется.

### 4. Независимость частей

Пять частей разделены на C1..C5: version/packaging, install folder, HIP RAM slack, HIP KV window/type, tests. M не вносит code diff относительно C5. Hybrid/delta адаптации не требуются; каждая часть может ревьюиться и откатываться отдельно.

### 5. Цена следующего merge

Низкая: upstream delta — 4 commits/16 files, candidate применяет ровно те же изменённые строки. Fork delta остаётся в `terminal/setup.py`, `terminal/strata_control/inkling_fit.py`, `engine/CMakeLists.txt` и packaging docs. Будущие конфликты вероятны в основном в planner/setup, но HIP-изменения additive и backend-scoped; qwen35 guard остаётся пустым.

### 6. Отдельная адаптация

Дополнительная адаптация не требуется: upstream fixes применены напрямую, fork-якоря сохранены. Отдельное ручное ревью понадобится только если будущий upstream снова изменит те же planner constants, qwen36 catalog, expert build options или packaging fork sections.

## Дополнительные проверки

- Upstream: `4` commits, `16` files.
- Candidate code delta: `16` files, `292/24`; changed-line multiset равен upstream.
- `C5` tree = `M` tree = `d2d23a55d707d553ecc52e14c7fbe27d0748f993`.
- M parents: `9ec1982ff3a75e2b5698fefc83af77a8973b71c0` и `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- D1/D2 после M изменяют только docs; code diff по `engine/terminal/tools` пуст.
- qwen35 diff `ours→D2` пуст.
- KAT/Huihui, `STRATA_Q6K_EXPERTS`, `STRATA_NATIVE_EXPERTS`, `q36_expert_info_test`, `VRAM_SAFETY_GB`, `KV_CARD_HEADROOM_GB`, `FREE_RAM_MARGIN_GB` сохранены.
- `evidence-index.json`: 30/30 файлов и хэшей совпали до записи этого review; хэш `REVIEW_REPORT.md` после review нужно обновить.
- `git diff --check ours..C5` чист. Outer `git diff --check ours..D2` отмечает строки `+ ` внутри сохранённых `.diff` artifacts; это содержимое patch, не whitespace дефект code delta. Gate должен исключить stored diff files либо зафиксировать override, не меняя их semantics.

## Итог

`R_DOC`: код `M` статически корректен, но final evidence `D2` не готов к `CODE_APPROVED`. После исправления algorithm descriptions, регенерации D1 и нового docs-only tip необходим повторный N review. Build/tests/GPU/quality/full windows остаются `not-run`; настоящее решение о sync/merge принимает A только после полной приёмки.
