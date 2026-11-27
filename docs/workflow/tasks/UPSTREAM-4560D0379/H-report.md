# H-report UPSTREAM-4560D0379

- verdict: `READY_FOR_N`.
- ours: `34bd46b86641d4fe34b3ab523e31b816718347e1`.
- upstream: `4560d03793482ef367294cfbd86a4df8d5679e72` (`v0.2.23`).
- merge-base: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- ahead/behind: `281/296`; upstream delta — 399 файлов, `+108085/-6137`.
- qwen35 upstream delta: пуст.

## Результат

- 34 matrix rows: 18 отдельных ours/upstream решений по десяти пересечениям и 16 групп остальных принятых fork-патчей.
- Все 65 content-коммитов ours отображены на matrix rows в `evidence/commit-coverage.json`.
- Свежий инвентарь добавившихся `STRATA_*` имён: 183; из них 29 отсутствуют в upstream.
- `upstream_merge.py matrix`: `readyForPlan=true`, все 34 якоря найдены.
- `merge-plan.json`: штатный JSON Schema — `pass`; `decision=ours`, `candidateRef=pending:sync/upstream-0.2.23`.
- `PATCH.diff`: 7 файлов, `+141/-18`; `git apply --numstat/--stat` и `git apply --check` на upstream-копии — pass.
- Settings register: ours-only 18, upstream-only 153, изменённых общих 787; вывод подлежит одной регенерации.

## Ключевые решения

- Сохранить Workflow v3, fork README/charts, FDEC/DOWN_SUB8/settings, expert parity tests, KAT/Huihui pins и `own_file/own_size/own_hf`.
- Сохранить IQ4_XS down и IQ4_NL gate/up; добавить upstream default-off `STRATA_PF_SYNC_DEBUG` поверх launches.
- Взять upstream CMake version/symbols/sm120/dot-x4, setup Ornith/custom/hardware/DFlash2, MCP refresh/custom metadata, Inkling lineup и packaging version.
- Не склеивать settings register вручную: A регенерирует JSON и `docs/SETTINGS.md` после объединения code knobs.
- qwen35 candidate обязан быть побитово равен ours.

## Блокеры

- Для N review пакетных блокеров нет.
- Для candidate acceptance: `candidateRef` ещё не создан; `commitRef=pending:*`; tests/build/GPU/runtime evidence и canonical leakcheck не запускались.
- `setup.py` и `moe_fused_iq.cu` требуют ручного conflict resolution по matrix; слепой upstream overwrite недопустим.

## Не запускалось

Commits, merge, push, tests, build, GPU, `merge-gate --run-checks`, subagents и новые сеансы. Main/candidate code и raw evidence не менялись; task-worktree содержит только некоммиченный пакет.

## Артефакты

- `IMPL_PLAN.md`
- `DOC_IMPL.md`
- `merge-profile.json`
- `merge-plan.json`
- `merge-matrix.json`
- `anchor-evidence.json`
- `PATCH.diff`
- `evidence-index.json`
- `evidence/**`

Жду ACK A.
