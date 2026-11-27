# H-report UPSTREAM-4560D0379

- verdict: `READY_FOR_N`.
- ours: `34bd46b86641d4fe34b3ab523e31b816718347e1`.
- upstream: `4560d03793482ef367294cfbd86a4df8d5679e72` (`v0.2.23`).
- merge-base: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- ahead/behind: `281/296`; upstream delta — 399 файлов, `+108085/-6137`.
- qwen35 upstream delta: пуст.

## Результат

- 34 matrix rows: 18 отдельных ours/upstream решений по десяти пересечениям и 16 групп остальных принятых fork-патчей.
- Все 66 content-коммитов ours отображены на matrix rows в `evidence/commit-coverage.json`.
- Свежий инвентарь добавившихся `STRATA_*` имён: 183; из них 29 отсутствуют в upstream.
- `upstream_merge.py matrix`: `readyForPlan=true`, все 34 якоря найдены.
- `merge-plan.json`: штатный JSON Schema — `pass`; `decision=ours`, `candidateRef=2195f9b0f412d7e1f5447dad82a657e4db6904cc`.
- `PATCH.diff`: 7 файлов, `+141/-18`; `git apply --numstat/--stat` и `git apply --check` на upstream-копии — pass.
- Settings register в candidate: 1445 записей; 18 ours-only + 153 upstream-only сохранены, `--check` PASS.

## Ключевые решения

- Сохранить Workflow v3, fork README/charts, FDEC/DOWN_SUB8/settings, expert parity tests, KAT/Huihui pins и `own_file/own_size/own_hf`.
- Сохранить IQ4_XS down и IQ4_NL gate/up; добавить upstream default-off `STRATA_PF_SYNC_DEBUG` поверх launches.
- Взять upstream CMake version/symbols/sm120/dot-x4, setup Ornith/custom/hardware/DFlash2, MCP refresh/custom metadata, Inkling lineup и packaging version.
- Settings register не склеивался вручную: candidate JSON и `docs/SETTINGS.md` регенерированы одним штатным проходом.
- qwen35 candidate побитово равен ours.

## Блокеры

- Для N review пакетных блокеров нет.
- Для candidate acceptance: metadata closure завершена; tests/build/GPU/runtime evidence и semantic merge-gate не запускались.
- `setup.py` и `moe_fused_iq.cu` требуют ручного conflict resolution по matrix; слепой upstream overwrite недопустим.

## Metadata closure

- candidateRef: `2195f9b0f412d7e1f5447dad82a657e4db6904cc`.
- parents: `34bd46b86641d4fe34b3ab523e31b816718347e1` и `4560d03793482ef367294cfbd86a4df8d5679e72`.
- candidate diff: 480 файлов, `+158245/-7524`, 4 binary-like.
- qwen35 parity: `git diff --exit-code 34bd46b86641d4fe34b3ab523e31b816718347e1 2195f9b0f412d7e1f5447dad82a657e4db6904cc -- engine/src/qwen35 engine/include/strata/qwen35` — PASS, diff пуст.
- reverse patch-check: PASS.
- ours-only markers: 29/29.
- settings register: 1445 записей; 18 ours-only + 153 upstream-only сохранены; `--check` PASS.
- scoped whitespace: PASS.
- 34 matrix rows получили реальные commitRefs; candidate anchors подтверждены read-only.
- [A-gate](file:///E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-27_session/upstream-4560d0379-A-gate-2026-11-28.json) и [candidate merge message](file:///E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-27_session/msg-42a0bc266.txt).
- N package verdict: `APPROVED_UPSTREAM_4560D0379_PACKAGE`, report SHA-256 `bfbe2871ef9fdcc31c459534fe1085bcafb3d2b0ec86094794070a725de5dd94`.
- Acceptance остаётся `pending`, gateResult `not-run`; package approval не является candidate acceptance.

## Candidate follow-up

- tip: `2195f9b0f412d7e1f5447dad82a657e4db6904cc`; parent: `42a0bc266c5e940436042bdf8680f5ae89224b73`.
- fix: 3 файла, `+8/-3`; `own_path_fit` сохраняет KAT/Huihui `context_fit`, два fork test expectation обновлены.
- matrix rows `setup-kat-huihui` и `mcp-own-size` получили `commitRef=2195f9b0f412d7e1f5447dad82a657e4db6904cc`.
- coverage: 66 content-коммитов; follow-up commit добавлен отдельной записью.
- A сообщил targeted unittest: Ran 86, OK (skipped=2); H этот тест не запускал.
- candidate diff к ours: 480 файлов, `+158245/-7524`.

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
