# UPSTREAM-4560D0379 — read-only package review

Дата: 2026-11-28.
Роль: N.
Вердикт: `APPROVED_UPSTREAM_4560D0379_PACKAGE`.

Package approval не разрешает merge/push и не заменяет candidate build/runtime gate.

## Refs и состояние

- Ours/main: `34bd46b86641d4fe34b3ab523e31b816718347e1`.
- Upstream: `4560d03793482ef367294cfbd86a4df8d5679e72`, tag `v0.2.23`.
- Merge-base: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- Ahead/behind: `281/296`.
- Upstream delta: 399 файлов, `+108085/-6137`.
- Task-worktree: `E:/tmp/workflow-upstream-4560d0379`, ветка `task/UPSTREAM-4560D0379`, HEAD `34bd46b86`; tracked-изменений нет, только 81 untracked package-файл.
- Candidate: `pending:sync/upstream-0.2.23`; commits/merge/tests/build/GPU/runtime не выполнялись.

## Evidence index и package copy

- `evidence-index.json`: 80 уникальных записей.
- Session package и task-worktree copy: 80/80 SHA/size совпали.
- A-gate: `records=80`, `shaSizeMismatches=0`, `missing=0`, `extra=0`.
- В package 81 файл; вне index только сам `evidence-index.json`.
- Conflict markers: 0 во всех 81 файлах.
- `evidence/qwen35-upstream-delta.txt` существует и намеренно пуст.

## Matrix и anchors

- `merge-matrix.json`: 34 строки — 18 отдельных ours/upstream решений по 10 пересечениям и 16 ours-групп остальных fork-патчей.
- Решения: 25 `ours`, 9 `upstream`; `hybrid/delta/defer/drop` не заявлены.
- Все 34 строки имеют `candidateDraft.draftOnly=true`, pending candidate ref и `commitRefPlan=pending:*`.
- Независимо проверены все 68 ours/upstream anchors: file-level и symbol/line anchors найдены в закреплённых refs, 0 расхождений.
- `evidence/commit-coverage.json`: 65 уникальных content-коммитов, все являются предками ours, все primaryRow существуют в matrix.
- `merge-plan.json`: 34 matrix rows, acceptance `pending`, gateResult `not-run`, architecture review `N-pending`.

## Содержательные решения

- `AGENTS.md`: сохраняется Workflow v3, принимается upstream version line.
- `README.md`: сохраняются fork notes/charts, принимаются Ornith/Inkling/release каталог.
- `engine/CMakeLists.txt`: сохраняются whole-block expert parity pairs, принимаются upstream version/symbols/sm120/dot-x4.
- `engine/src/prefill/moe_fused_iq.cu`: сохраняются IQ4_XS down и IQ4_NL gate/up; upstream `dbg_sync` остаётся default-down диагностикой после launch.
- `terminal/setup.py`: сохраняются KAT/Huihui pins и `own_file/own_size/own_hf`; принимаются Ornith/custom/hardware/DFlash2/error-hint.
- `terminal/tools/strata_mcp.py`: сохраняется единственный `setup.own_size` lookup; принимаются upstream refresh/custom/Inkling metadata.
- Settings register/docs не склеиваются вручную: одна регенерация после объединения code knobs. Evidence: 18 ours-only, 153 upstream-only, 787 changed common.
- Packaging README: сохраняются fork CI/gap notes, принимается upstream version line.

## PATCH.diff и qwen35

- `PATCH.diff`: 7 файлов, `+141/-18`, 27 hunks.
- Файлы: `AGENTS.md`, `README.md`, `engine/CMakeLists.txt`, `engine/src/prefill/moe_fused_iq.cu`, `terminal/setup.py`, `terminal/tools/strata_mcp.py`, `tools/packaging/README.md`.
- Все 27 hunk contexts независимо найдены в upstream blobs; 0 расхождений.
- A-gate `git apply --check` на upstream-копии: PASS.
- Upstream qwen35 delta относительно merge-base пуст; PATCH.diff не трогает qwen35.
- Candidate qwen35 byte parity с ours пока не проверен, поскольку candidateRef отсутствует; обязательный guard сформулирован в `IMPL_PLAN.md:21,54` и `DOC_IMPL.md:65-70`.

## Pending, риски и следующий этап

- `merge-plan.json:2-5`: acceptance `pending`, gateResult `not-run`.
- `merge-plan.json:60`: candidateRef `pending:sync/upstream-0.2.23`.
- `merge-plan.json:135-191`: build/tests/correctness/quality/runtime/backends/fallback/route честно `not-run`.
- `IMPL_PLAN.md:50-60` перечисляет обязательные post-N проверки: schema/matrix, qwen35 guard, settings register, launch static, strict static, build/tests/runtime и финальный gate.
- `IMPL_PLAN.md:62-68` и `DOC_IMPL.md:80-84` задают риски и rollback по отдельным content commits с сохранением upstream parent и ours fallback.
- Stage 1 merge требует отдельного решения по opt-in manual `fused`; package approval этого решения не даёт.

Блокеров package review не найдено. Следующий допустимый этап — только создание A отдельного candidate-worktree/content commits по matrix и последующая candidate acceptance; merge/push без отдельного разрешения запрещены.

## Ограничения проверки

Commits/tests/build/GPU/merge/push/subagents и `merge-gate --run-checks` не запускались. Candidate и main не изменялись; записан только этот отчёт.
