# IMPL_PLAN UPSTREAM-4560D0379

- status: `READY_FOR_N`; candidate code, commits, merge, tests, build и GPU не выполнялись.
- ours: `34bd46b86641d4fe34b3ab523e31b816718347e1`.
- upstream: `4560d03793482ef367294cfbd86a4df8d5679e72`, tag `v0.2.23`.
- merge-base: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- ahead/behind: `281/296`; upstream delta — 399 файлов, `+108085/-6137`.
- qwen35: `git diff --name-only 2af30cca..4560d0379 -- engine/src/qwen35` пуст.

## Принцип

Каждый наш патч и каждый upstream-патч в пересечённом файле получает отдельную matrix-строку. `ours` сохраняет fork-реализацию, `upstream` добавляет или заменяет независимую upstream-часть. `hybrid`, `delta`, `defer` и `drop` не заявляются: непроведённые combo/runtime evidence не выдаются за passed. Candidate остаётся `pending:sync/upstream-0.2.23`.

## Этапы candidate sync

1. A сохраняет этот некоммиченный пакет и `git diff --binary` во внешний raw-evidence до переключений.
2. A создаёт отдельный candidate-worktree от ours. Task-worktree H не переключается на sync-ветку.
3. A применяет upstream delta `2af30cca..4560d0379` content-коммитами. Каждая upstream matrix-строка получает реальный `commitRef`; общий merge-коммит не заменяет строчные refs.
4. A применяет `PATCH.diff` к upstream base. Patch содержит только предложенные адаптации наших якорей в семи файлах; settings register/docs перегенерируются, а не склеиваются вручную.
5. A выполняет `tools/settings_register.py --check`, затем при необходимости `--docs`, чтобы объединить 18 ours-only и 153 upstream-only записей. Итоговые `docs/SETTINGS.md` и `terminal/data/settings-register.json` должны быть согласованы.
6. A создаёт merge commit `M` с parents candidate-content/upstream и проверяет, что qwen35 побитово равен ours.
7. A повторяет anchor audit на candidateRef, обновляет `merge-plan.json`: `candidateRef`, реальные `commitRef`, evidence revision и даты.
8. A выполняет static/schema/matrix checks, сборку затронутых backend'ов, tests, correctness/quality, route/fallback и resource acceptance.
9. N выполняет независимый review. Main/push не выполняются без отдельного разрешения и зелёного финального gate.

## Порядок разрешения десяти пересечений

| Путь | Наши строки | Upstream строки | Действие |
|---|---|---|---|
| `AGENTS.md` | `agents-workflow` | `agents-version` | Сохранить Workflow v3; обновить version line. |
| `README.md` | `readme-fork-notes` | `readme-upstream-catalog` | Сохранить fork notes/charts; добавить Ornith/Inkling 0.2.23. |
| `docs/SETTINGS.md` | `settings-fork-knobs` | `settings-upstream-register` | Перегенерировать из candidate register. |
| `engine/CMakeLists.txt` | `cmake-expert-parity` | `cmake-upstream-build` | Сохранить parity pairs; взять version/symbols/sm120/dot-x4. |
| `engine/src/prefill/moe_fused_iq.cu` | `fused-format-support` | `fused-sync-debug` | Сохранить IQ4_XS/IQ4_NL; обернуть launches upstream `dbg_sync`. |
| `terminal/data/settings-register.json` | `settings-fork-knobs` | `settings-upstream-register` | Union входов, одна регенерация. |
| `terminal/setup.py` | `setup-kat-huihui` | `setup-upstream-features` | Сохранить pins/own_file/own_size/own_hf; взять Ornith/custom/hardware/DFlash2. |
| `terminal/strata_control/inkling_fit.py` | ours diff только whitespace | `inkling-upstream-lineup` | Взять upstream lineup; не переносить пустую строку как отдельный патч. |
| `terminal/tools/strata_mcp.py` | `mcp-own-size` | `mcp-upstream-features` | Сохранить own-size lookup; взять hardware/custom/Inkling metadata. |
| `tools/packaging/README.md` | `packaging-fork-notes` | `packaging-upstream-version` | Сохранить fork CI notes; обновить version line. |

## Anchor evidence и commitRefs

- `merge-profile.json` совместим с `upstream_merge.py matrix`.
- `merge-matrix.json` содержит 34 строки и плановый candidate-draft location.
- `anchor-evidence.json` фиксирует ours/upstream file:line, статус и команду для candidateRef.
- `evidence/anchors/*.txt` содержит сырой вывод `git grep`.
- `evidence/commit-coverage.json` отображает все 65 content-коммитов ours на matrix rows.
- Каждая строка имеет `commitRef=pending:<id>` до создания candidate. Перед приёмкой pending недопустим.

## Проверки A после N review

- JSON Schema: `tools/upstream_merge/merge-plan.schema.json`.
- Read-only matrix: `upstream_merge.py matrix` с candidateRef.
- Qwen35 guard: `git diff --exit-code OURS CANDIDATE -- engine/src/qwen35 engine/include/strata/qwen35`.
- Settings: `python tools/settings_register.py --check`.
- Launch: `python terminal/tools/check_qwen36_200k_launch.py`.
- Static: `python tools/check --strict`.
- Build/tests: CUDA и затронутые backend'ы; expert parity, q36 metadata, setup/MCP/planner tests.
- Runtime: 32k smoke, 160k/200k A/B, MTP on/off, FDEC/staging/fallback, KAT/Huihui, copy_session, resource peaks.
- Merge gate: только read-only до candidate; `--run-checks` выполняет A после N на точном candidateRef.

## Риски и rollback

- `setup.py` и `moe_fused_iq.cu` имеют реальные конфликтные зоны; слепой upstream overwrite недопустим.
- Settings register — generated artifact; ручная склейка может рассинхронизировать docs и code.
- Upstream 0.2.23 меняет public catalog/default planner; нужны setup/MCP regression tests.
- Любое отличие qwen35 от ours, потеря ours-only маркера, неверный own_size/own_hf или неподдерживаемый fused dispatch блокирует candidate.
- Rollback: откатить конкретный content commit matrix-строки, сохранить upstream parent и рабочий fallback; main не двигать. При сомнении вернуть candidate к ours и повторить sync с новым пакетом.
