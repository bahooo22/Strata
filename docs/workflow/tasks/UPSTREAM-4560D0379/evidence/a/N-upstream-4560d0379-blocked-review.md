# UPSTREAM-4560D0379 — candidate review

Дата: 2026-11-28.
Роль: N.
Вердикт: `BLOCKED`.

Candidate build/runtime и architecture по существу проходят. Блокеры находятся в финальном merge plan и одной свидетельской сводке: row-level metadata осталась H-draft, один candidate anchor ведёт не на тот файл, а число skipped GPU-тестов занижено.

## Refs

- Ours/main: `34bd46b86641d4fe34b3ab523e31b816718347e1`.
- Upstream: `4560d03793482ef367294cfbd86a4df8d5679e72`, tag `v0.2.23`.
- Merge-base: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- Candidate: `E:/tmp/cand-upstream-4560d0379`, ветка `sync/upstream-0.2.23`.
- Immutable review HEAD: `94f2e6c190982ccc76187f274d635f118ffb3b67`.
- Runtime/build code HEAD: `2195f9b0f412d7e1f5447dad82a657e4db6904cc`.
- Финальный plan SHA-256: `68446755637ed48cdd5257fa28c37f6589f5d6ebc8b402d28ca3816d5fe5576f`.
- Executable SHA-256: `0da6657819dd13939982eb520cf68c0fb2f70a592c480c6853ba9e4ddf1d22b4`.

Candidate чист, является потомком ours и upstream. Delta `2195f9b0f..94f2e6c19` содержит только docs/evidence; code/runtime identity подтверждена.

## Что подтверждено

### Index, qwen35 и algorithms

- Evidence index: 396 уникальных записей; working tree и Git blobs HEAD совпали 396/396 по SHA/size. Вне index только сам `evidence-index.json`.
- Qwen35 byte parity candidate/ours: `git diff --quiet` rc=0.
- `upstream-code-algorithms.md` и `algorithm.json` соответствуют реальному upstream-коду: dot-x4 policy, split lend/stage pool, dual-layout reader, fused diagnostics, CMake/symbols, custom setup/hardware, MCP refresh, DFlash2, PDL, tail-skip и vision policy проверены по файлам и символам upstream `4560d0379`.
- Code algorithm diagram: 35 узлов; Mermaid parse/render PASS, console errors 0.

### Matrix и architecture

- Final matrix: 34 строки, 25 `ours` и 9 `upstream`; `hybrid/delta/defer/drop` не заявлены.
- Все 34 `commitRef` существуют и являются предками candidate.
- Независимо проверены 102 ours/upstream/candidate anchor locations; 101 корректен, один неверен (см. блокер).
- Architecture-контракты содержат boundary, ownership, streams/sync, fallback, compatibility, invariants и alternatives. Наш code adaptation `2195f9b0f` меняет только три Python-файла (`+8/-3`) и не добавляет globals, `#ifdef` или pointer-offset coupling.
- Альтернативы `copy-upstream-tree` и `ours-only` отклонены обоснованно: первая теряет 29 ours-only markers/qwen35 contracts, вторая не принимает upstream build/setup/MCP/settings fixes.

### Build и runtime

- CUDA configure/build rc=0; executable SHA/size совпали с `build-identity.json`.
- Markers 29/29, пропавших 0; mutation control сработал.
- Targeted unittest: `Ran 86`, `OK (skipped=2)`, failures/errors 0.
- Runtime raw reparse: 24 строки AB/BA, repeat 3+3, MTP2 и fallback; engine metrics и answer SHA/content SHA совпали без расхождений.
- 32k repeat 3+3 пересчёт: baseline/candidate pp `1513.85/1508.85`, tg `22.75/22.20`, Δpp `-0.330%`, Δtg `-2.418%`; initial pp-сигнал не повторён, exact answer parity сохранён.
- 160k: Δpp `-0.033%`, Δtg `0%`, exact parity.
- 200k: Δpp `+0.027%`, Δtg `+1.220%`, exact parity.
- MTP2 32k: exact parity, Δpp `+0.650%`, Δtg `+1.481%`.
- Quality: 12 задач, `16/22` у обеих сторон, score identical.
- Copy_session: resume `18000`, fresh `2000`; raw engine log подтверждает prefix/fresh.
- Fallback cuBLAS `--fa -1 --fa-tile 0`: 4/4 rc0, exact answer parity.
- Performance descriptive; speed progress не заявлен.

### GPU parity

- Raw CTest: 87 tests, 85 passed, 1 failed, 2 skipped.
- Failure `prefill_fused_q36_test: Q6_K + Q8_0 not covered by Qwen3.6 kernels` побайтово совпал с baseline main log.
- Это baseline-identical failure, а не регрессия candidate.

## Блокеры

### 1. Final plan сохранил H-draft metadata во всех 34 rows

Файл: `upstream-4560d0379-final-merge-plan.json`.

- `:435` — `errorBehavior: "Кандидат ещё не создан..."`.
- `:451` — `"Candidate build/runtime coverage not-run."`.
- `:500` — `measurementStatus: "not-measured"`.
- `:529` — `route.verified: false`.

Эти поля повторяются во всех 34 строках, хотя top-level acceptance на `:2-5` уже описывает реальный candidate `94f2e6c19` и завершённые build/runtime checks. Это противоречит фактическому candidate state и не позволяет считать final plan семантически финальным.

Требуется обновить row-level `contract.errorBehavior`, `coverage`, `resources`, `route.verified` и candidate evidence до реального `94f2e6c19`/`2195f9b0f` состояния либо явно отделить historical H-draft поля от candidate acceptance.

### 2. Неверный candidate anchor для `settings-upstream-register`

- `upstream-4560d0379-final-merge-plan.json:1348` указывает `94f2e6c19:docs/workflow/tasks/UPSTREAM-4560D0379/DOC_IMPL.md:10`.
- Реальный upstream anchor `STRATA_PF_SYNC_DEBUG` находится в candidate `engine/src/prefill/moe_fused_iq.cu:76,81,100` и `terminal/data/settings-register.json:38382`.

Anchor symbol в DOC_IMPL существует в других строках, но указанная location `:10` не является якорем и не доказывает candidate code/register. Нужно исправить `route.candidate` на фактический code/register location и повторить anchor audit.

### 3. Занижено число skipped GPU-тестов

- `evidence/runtime-2026-11-28/RUNTIME-ACCEPTANCE.md:21` и brief заявляют `1 skipped`.
- Raw `glm/2026-11-27_session/upstream-4560d0379-gpu-parity-ctest.log:14,20,185-186` показывает два skipped tests: `#303 prefill_fused_iq_test_sm75` и `#306 prefill_fused_iq_test_ws`.

Нужно исправить summary на `2 skipped` и привести все производные сводки к raw CTest. На code verdict это не влияет, но acceptance evidence должна быть точной.

## Принятые warning codes

N принимает следующие warnings как неблокирующие эвристики с указанным scope:

| Code | Решение | Основание |
|---|---|---|
| `copy-paste` | ACCEPT | `copyPasteWindows=35100` относится к массовому upstream/docs delta; наш adaptation patch ограничен 7 файлами `+141/-18`, code fix `2195f9b0f` — 3 файлами `+8/-3`, копирования fork-функции не обнаружено. |
| `global-state` | ACCEPT | Срабатывания относятся к upstream JS constants и Inkling globals; наш code delta не добавляет static/global state. |
| `ifdef-growth` | ACCEPT | `ifdefAdded=240` — upstream-wide delta; наш code delta и PATCH не добавляют `#ifdef/#ifndef`. |
| `large-diff-files` | ACCEPT | Candidate diff включает upstream v0.2.23 (399 файлов `+108085/-6137`) и сохранённую fork-историю; это ожидаемый merge scope, не рост нашего адаптера. |
| `large-diff-lines` | ACCEPT | Та же причина; qwen35 source byte-identical, markers 29/29, runtime parity сохранён. |
| `offset-coupling` | ACCEPT | Список содержит существующий qwen35/Inkling pointer arithmetic; наш adaptation commit не добавляет `reinterpret_cast`/offset coupling. |

Эти accept-решения должны быть записаны в `warningAcknowledgments` финального plan; пустой список на `:6392` сейчас не отражает ручной verdict N.

## N-A категории

| Категория | N verdict | Основание |
|---|---|---|
| `bisect` | ACCEPT `not-applicable` | Воспроизводимая runtime-регрессия не обнаружена: initial 32k pp-сигнал не повторён в repeat 3+3, tg переменчив; quality/exact parity сохранены. |
| `implementationCombinations` | ACCEPT `not-applicable` | В matrix нет `hybrid`/`delta`; отдельные combination runs не требуются. |
| `rollback` | ACCEPT `not-applicable` для pre-merge gate | Main не двигался, merge/push не выполнялись; отдельный candidate worktree и реальные content commits сохраняют pre-merge rollback path. Live rollback после merge неприменим. |

Schema ожидаемо ждёт `manualVerdict` для этих трёх категорий; данный отчёт фиксирует ручной verdict N, но не подменяет pending-поля плана.

## Architecture verdict по шести вопросам

1. Смысл алгоритмов upstream подтверждён кодом, не workflow-схемой.
2. Ownership буферов/state описан; наш adaptation engine source не меняет.
3. MTP2, exact answer parity и cuBLAS fallback подтверждены runtime.
4. Ours/upstream части разделены matrix rows; hybrid/delta не заявлены.
5. Цена следующего merge ограничена qwen35 byte parity, 29 markers и семифайловым adaptation patch.
6. Более простые альтернативы рассмотрены и отклонены с доказательствами.

Architecture по существу приемлем, но `APPROVED_UPSTREAM_4560D0379_CANDIDATE` не выдаётся из-за трёх блокеров выше.

## Требуемое закрытие

1. Обновить финальный plan до реального candidate state во всех 34 rows.
2. Исправить `settings-upstream-register` candidate anchor.
3. Исправить GPU parity skipped count `1 → 2` во всех производных summaries.
4. Записать принятые warning acknowledgments и N-A manual verdicts.
5. Повторить read-only semantic gate и короткую N проверку. GPU rerun для этих исправлений не требуется.

Candidate approval не разрешает main merge/push. Main остаётся нетронутым до отдельного явного разрешения.

## Ограничения проверки

Commits/tests/build/GPU/merge/push/subagents не запускались. Candidate и main не изменялись; записан только этот отчёт.
