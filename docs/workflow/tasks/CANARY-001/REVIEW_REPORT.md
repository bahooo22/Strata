# REVIEW_REPORT CANARY-001

- Роль: `N`.
- Reviewer: `9ba7a8a6-9973-4bce-8a66-93acde030932`.
- Дата review: `2026-11-25`.
- Время review: `2026-11-25T01:31:00Z` / `2026-11-25T04:31:00+0300`.
- Base: `4356a467780900923cbf83d92675790e7fbeb32a`.
- Branch: `task/CANARY-001`.
- Verdict: `CODE_APPROVED`.
- Rejection code: отсутствует.
- Scope: только code/fast 32k. `INTEGRATION_APPROVED`, `MERGED`, полные 160k/200k и публикация не одобрены.

## C1–C10

| Критерий | Результат | Доказательство |
|---|---|---|
| C1 `code==DOC_IDEA` | PASS | `TASK_IDEA.md:3-9` задаёт единственную переменную `STRATA_Q36_READ_WINDOWS=2` против default 1 и запрет engine-правок. `PATCH.diff:1-155` содержит только `IMPL_PLAN.md`, `DOC_IMPL.md`, `experiment-profile.json`; `git diff base..task/CANARY-001 -- engine terminal tools` пуст. |
| C2 correctness | PASS | Шесть fast-прогонов завершились rc0; все console-логи содержат `answer ok: 'Контекст получен.'`; prompt 29242, generation 6. `FAST_RUN_REPORT.md:6-11`, `metrics-fast.json:11-64`, raw `rw1/rw2-32k-*.log`. |
| C3 security | PASS | Engine-код, сетевой контракт, права, секреты и зависимости не менялись. Эксперимент использует существующий локальный integer env knob. В patch нет новых входов, shell-команд, путей вне заявленного профиля или зависимостей. |
| C4 fallback | PASS | Default остаётся `read_windows=1`; candidate включает env 2 только на время прогона. Knob разрешён в диапазоне 0..64 и разрешается один раз в `Engine::init` (`engine/src/qwen35/q36_engine.cu:1805,2082`). Дополнительные `window()` вызываются только при `n_active>0` и `done<fresh` (`engine/src/qwen35/q36_engine.cu:4875-4878`); автоматический failover и default semantics не меняются. |
| C5 `DOC_IMPL==code` | PASS | `DOC_IMPL.md:3-5` совпадает с фактическим кодом: knob `--read-windows`/`STRATA_Q36_READ_WINDOWS` (`engine/src/qwen35/q36_engine.cu:2082,5135`), перенос в `Serve` (`engine/src/qwen35/q36_engine.cu:4511-4516`), цикл между prompt chunks (`engine/src/qwen35/q36_engine.cu:4875-4878`). |
| C6 `DOC_IMPL==DOC_IDEA` | PASS | Обе документы описывают один параметр, одинаковый профиль KAT IQ4_XS / graph on / q4_0 / MTP0 / super-chunk8 / att256 / reserve512 / FA v2 tile4, отсутствие engine-патча и разделение fast/full. `TASK_IDEA.md:3-8`, `IMPL_PLAN.md:3-8`, `DOC_IMPL.md:3-5`. |
| C7 fast-run protocol >=3x32k | PASS | 3 baseline + 3 candidate, окно 32768, prompt 29242, один exe/model/server-root. Пересчёт из raw: baseline pp 1438.9/1446.4/1439.3, median 1439.3, spread 7.5 (0.52%); candidate 1445.5/1435.8/1432.6, median 1435.8, spread 12.9 (0.90%); delta -0.243% ≈ -0.24%, шум. `metrics-fast.json:3-64`, `FAST_RUN_REPORT.md:3-12`. |
| C8 base valid/re-based | PASS | `main`, `task/CANARY-001` и base имеют HEAD `4356a467…`; `git merge-base --is-ancestor base task/CANARY-001` rc0; `git rev-list --left-right --count main...task/CANARY-001` = `0 0`; code diff пуст. Worktree содержит только untracked `docs/workflow/tasks/CANARY-001/`. |
| C9 no subagents and delegation recorded | PASS | `participants.json:3-5` фиксирует A=`443fddf1…`, H=`b8bd12b8…`, N=`9ba7a8a6…`; `events.jsonl:2-12` фиксирует init/TASK_IDEA/H artifacts/fast metrics. Текущий review делегирован A; N субагентов не запускал и self-approval не делает. |
| C10 no unapproved dependencies | PASS | `PATCH.diff` не меняет package manifests, lockfiles, imports, CI, workflow hooks или внешние сервисы. Используются существующие model/exe/server-root и уже имеющийся `psutil` в run-скрипте. |

## Проверка profile и raw evidence

- Фактическая команда fast-run: `glm/2026-11-25_session/upstream-merge-tool/canary_fast_runs.py:47-51`; она явно передаёт `--fa -2 --fa-tile 4`, `--super-chunk 8`, `--mtp 0`, `--kv-type q4_0`, `--ctx 32768`, `--att 256`, `--reserve 512`, graph и server-root.
- Промежуточный runner не теряет отрицательный `--fa`: `glm/scripts/run_one_160k_2026-11-20.py:72-79`.
- Exe SHA-256: `4d6be23e7ce2506a7ad6ec3c79b56cebee125e1c615cd67e751b327f46a12b05`; совпадает с `glm/2026-11-24_session/upstream-merge-prep/build-exe-sha256.txt:2`.
- Model SHA-256: `3db4507e8c2336e5444dbdb56da7fed45a7597f10c0f53299b998d1f5bba280a`.
- Хэши зарегистрированных TASK_IDEA/IMPL_PLAN/PATCH/DOC_IMPL/FAST_RUN_REPORT совпали с `state.json`; добавленные файлы `PATCH.diff` побайтно совпадают с содержимым `IMPL_PLAN.md`, `DOC_IMPL.md`, `experiment-profile.json`.

## Примечания по evidence

- В `rw1-32k-3.log` и `rw2-32k-1.log` сохранились только хвосты knob-строк (`cli (default 0)` / `(default -1)`). Это ограничение захвата лога, а не смена профиля: launch-скрипт и runner детерминированно передают `--fa -2 --fa-tile 4`, остальные логи содержат полные строки, pp соответствует FA v2. Для будущих full runs желательно сохранять config/banner без усечения.
- `tg` не используется для speed decision: generation составляет 6 токенов. Fast verdict основан на pp median/spread и sanity rc0/answer.
- Полные 160k/200k не запускались. Их отсутствие не является блокером `CODE_APPROVED`, но запрещает любой вывод о `progress`, `INTEGRATION_APPROVED` или `MERGED`.

## Итог

`CODE_APPROVED` для CANARY-001 в fast/code scope. Следующий допустимый шаг — только отдельные full 160k и 200k по workflow v3; merge требует `progress` на обоих окнах. Иначе задача архивируется. Настоящий review не разрешает commit, merge, push, release или изменение default.
