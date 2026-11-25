# UPSTREAM-2AF30CCA — план v5 подготовки fork candidate

## Статус

План v5 подготовлен для утверждения пользователем. Worktree, merge, commit, push, tests, build и GPU не выполнялись. Субагенты не запускались.

## Роли

- A `443fddf1`: создаёт task-worktree и task-ветку, сохраняет пакет H во внешний raw-evidence, создаёт отдельный detached candidate-worktree и sync-ветку уже там, выполняет content commits `C1..C5`, merge commit `M`, docs commits `D1/D2`, CPU/static tests, CUDA build и GPU acceptance.
- H `b8bd12b8`: после создания worktree готовит только некоммиченные `IMPL_PLAN.md`, `DOC_IMPL.md`, `PATCH.diff`, `merge-profile.json`, draft matrix/anchor evidence. H не создаёт commits/sync-ветку, не запускает Python tests/selftest/build/GPU.
- N `9ba7a8a6`: независимый read-only review candidate и evidence.

## Pinned refs и прогноз

- ours/baseSha: `996eb9195b1790f954dd48f50be27893cae93937`
- upstream: `2af30ccaa0729177c4725ee2073f72bf550e2f86`
- previousUpstream/merge-base: `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`
- ahead/behind: `258/4`
- delta: 4 коммита, 16 файлов; `engine/src/qwen35/*` в delta не затронут.
- прогноз `git merge-tree --write-tree`: tree `d2d23a55d707d553ecc52e14c7fbe27d0748f993`, rc=0, текстовых конфликтов нет.
- predicted tree сохраняет qwen35, IQ4_XS-KAT/Huihui, expert build options и fork planner constants; upstream setup/HIP fixes применяются.

## Решения матрицы

| ID | Decision | Файлы/якоря | Основание |
|---|---|---|---|
| release-version-bump | upstream | `engine/CMakeLists.txt:13`, `terminal/strata_cli/__init__.py:15`, `docs/data/release.json:6-7`, `tools/packaging/README.md:4`, version tests | Control 0.1.68 / Terminal 0.2.21.1; app и engine packages остаются 0.2.21/0.1.67 |
| setup-install-folder | upstream | `terminal/setup.py:write_config`, `write_run_script`; `test_write_config_makes_the_folder`, `test_write_run_script_makes_the_folder` | #7012 |
| setup-hip-ram-slack | upstream | `RAM_TIER_SLACK_GIB/FRAC`, `inkling_expert_flags(...)`, call site `10943` | HIP RAM cap fix; другие backend не меняются |
| hip-kv-window-choice | upstream | `HIP_KV_WINDOW_TOKENS`, `non_expert_gb`, `inkling_plan_kv`; `test_inkling_fit_hip_window.py` | HIP 32K K/V window и выбранный тип |
| qwen36-catalog-preserve | ours | `terminal/setup.py:804` `IQ4_XS-KAT`, `:807` `IQ4_XS-Huihui` | upstream не содержит эти fork-модели |
| expert-build-preserve | ours | `engine/CMakeLists.txt:142` `STRATA_Q6K_EXPERTS`, `:178` `STRATA_NATIVE_EXPERTS`, `:486` `q36_expert_info_test` | upstream delta меняет только version line |
| fork-planner-base | ours | `inkling_fit.py:VRAM_SAFETY_GB`, `KV_CARD_HEADROOM_GB`, `FREE_RAM_MARGIN_GB` | наши CUDA/desktop/RAM правила сохраняются |
| packaging-fork-notes | ours | `tools/packaging/README.md` fork sections | version line обновляется upstream, fork docs сохраняются |
| upstream-tests | upstream | `test_inkling_fit_free.py`, new `test_inkling_fit_hip_window.py`, `test_setup_config.py`, version/release tests | upstream regression coverage |
| qwen35-no-delta | ours | `engine/src/qwen35/*`, `engine/include/strata/qwen35/*` | predicted tree побитово равен main |

`hybrid/defer/drop` не требуются: auto-merge чист, semantic overlap закрывается раздельными `ours`/`upstream` строками.

## CommitRefs и evidence

- H только предлагает mapping; реальные SHA создаёт A.
- Пакет H остаётся некоммиченным в `E:/tmp/workflow-upstream-2af30cca`. A сохраняет файлы и `git diff` во внешний raw-evidence до любых переключений.
- A создаёт отдельный detached candidate-worktree `E:/tmp/workflow-upstream-2af30cca-candidate` от baseSha и только там ветку `sync/upstream-2af30cca`. Task-worktree H не переключается и не очищается до переноса evidence.
- A применяет reviewed delta обычными content commits: `C1` version/packaging, `C2` setup install folder, `C3` HIP RAM slack, `C4` HIP K/V window/choice, `C5` upstream tests.
- После `C5` A выполняет `git merge --no-ff --no-commit upstream` и создаёт `M` с parents `C5`/upstream; дерево `M` должно совпасть с `C5`.
- Один реальный SHA на matrix-строку: release=`C1`, setup-folder=`C2`, hip-ram=`C3`, hip-kv=`C4`, qwen36-preserve=`C4`, expert-preserve=`C1`, planner-base=`C4`, packaging-notes=`C1`, tests=`C5`, qwen35-guard=`M`.
- `D1` — RU+EN merge report по provisional plan candidate `M`.
- `D2` — candidate-internal anchor evidence, conflict decisions, проверяемые artifacts/logs, `IMPL_PLAN.md`, `DOC_IMPL.md`, `PATCH.diff`, evidence index. `D2` является final candidate tip; evidence plan ссылается на revision `D2`.
- Внешние final matrix/plan — derived output после чистого `D2`; они не заменяют candidate-internal evidence.

## Команды по ролям после утверждения

### A: создание worktree и task-ветки

```text
git -C C:/Projects/Strata-3060Ti/engine worktree add --detach E:/tmp/workflow-upstream-2af30cca 996eb9195b1790f954dd48f50be27893cae93937
git -C E:/tmp/workflow-upstream-2af30cca switch -c task/UPSTREAM-2AF30cca
```

### H: некоммиченный пакет

H читает pinned refs/diff, пишет только task-файлы и draft evidence. Допустимы `git diff`, `git grep`, `git show`, `sha256sum`, `python -m json.tool`, canonical leakcheck и `git apply --check PATCH.diff`. Запрещены commits, sync-ветка, Python tests/selftest, build и GPU.

### A: сохранение пакета H и отдельный candidate-worktree

```text
# A сохраняет некоммиченный пакет H и diff во внешний raw-evidence до переключений
cp -a E:/tmp/workflow-upstream-2af30cca/docs/workflow/tasks/UPSTREAM-2AF30cca E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-25_session/upstream-2af30cca/h-package/
git -C E:/tmp/workflow-upstream-2af30cca diff --binary > E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-25_session/upstream-2af30cca/h-package.diff
git -C C:/Projects/Strata-3060Ti/engine worktree add --detach E:/tmp/workflow-upstream-2af30cca-candidate 996eb9195b1790f954dd48f50be27893cae93937
git -C E:/tmp/workflow-upstream-2af30cca-candidate switch -c sync/upstream-2af30cca
# A применяет reviewed content changes и создаёт C1..C5 в candidate-worktree
git merge --no-ff --no-commit 2af30ccaa0729177c4725ee2073f72bf550e2f86
# A проверяет дерево и создаёт M с parents C5/upstream
# A создаёт D1/D2 с candidate-internal evidence
```

Task-worktree H не переключается на sync-ветку и не очищается до завершения переноса evidence.

## Anchor-проверки

```text
git ls-files -u
git -c core.whitespace=cr-at-eol diff --cached --check
git diff --exit-code 996eb9195b1790f954dd48f50be27893cae93937 HEAD -- engine/src/qwen35 engine/include/strata/qwen35
git grep -n -F 'IQ4_XS-KAT' HEAD -- terminal/setup.py
git grep -n -F 'IQ4_XS-Huihui' HEAD -- terminal/setup.py
git grep -n -F 'STRATA_Q6K_EXPERTS' HEAD -- engine/CMakeLists.txt
git grep -n -F 'STRATA_NATIVE_EXPERTS' HEAD -- engine/CMakeLists.txt
git grep -n -F 'HIP_KV_WINDOW_TOKENS' HEAD -- terminal/strata_control/inkling_fit.py
git grep -n -F 'RAM_TIER_SLACK_GIB' HEAD -- terminal/setup.py
git grep -n -F 'PRODUCT_VERSION = "0.2.21.1"' HEAD -- terminal/strata_cli/__init__.py
M=$(git rev-parse HEAD)
git merge-base --is-ancestor 996eb9195b1790f954dd48f50be27893cae93937 "$M"
git merge-base --is-ancestor 2af30ccaa0729177c4725ee2073f72bf550e2f86 "$M"
git diff --exit-code "$M^1" "$M"
git rev-list --parents -n 1 "$M"
```

## Проверки A после N review

- CPU/static: `test_inkling_fit_free`, `test_inkling_fit_hip_window`, `test_setup_config`, `test_release_manifest`, version tests, merge-tools selftest.
- CUDA build и `tools/check --strict`.
- 32k smoke, 160k/200k A/B, quality/MTP/fallback/resources.
- Независимый N review до любого продвижения main.

## Риски и blockers

- GPU barrier blocked чужим Huihui 200k run PID 8208; не прерывать.
- Main worktree dirty только workflow state/events/task dir; H не трогает его.
- Нельзя переключать task-worktree H на sync-ветку: некоммиченный пакет может загрязнить C1..C5. Candidate создаётся в отдельном worktree.
- Чистый auto-merge не доказывает сохранение fork defaults; A обязан проверить anchors и tree.
- Любое отличие qwen35 от main после merge — ошибка candidate.
- До утверждения v5 выполнять worktree/merge/commit/tests/build/GPU нельзя.
