# Workflow v3

Регламент для участниц A/H/N без субагентов и self-approval. Инструмент: `tools/workflow/workflow.py`.

## Роли

- A — главная/архитектор/интегратор: TASK_IDEA, прогоны, коммиты, push, merge и очистка.
- H — helper: IMPL_PLAN, PATCH и DOC_IMPL в отдельной task-ветке.
- N — аналитик: read-only REVIEW_REPORT по C1–C10.

Текущие session id хранятся в `participants.json`. До cutover действуют старые роли; после cutover guard использует новый реестр.

## Команды

```text
python tools/workflow/workflow.py init --task-id TASK-001 --base-sha HEAD --branch task/TASK-001
python tools/workflow/workflow.py status --task-id TASK-001
python tools/workflow/workflow.py record --task-id TASK-001 --name TASK_IDEA --path docs/workflow/tasks/TASK-001/TASK_IDEA.md --author A
python tools/workflow/workflow.py metrics --task-id TASK-001 --file docs/workflow/tasks/TASK-001/metrics.json
python tools/workflow/workflow.py review --task-id TASK-001 --verdict CODE_APPROVED --report docs/workflow/tasks/TASK-001/REVIEW_REPORT.md
python tools/workflow/workflow.py transition --task-id TASK-001 --to G1
python tools/workflow/workflow.py validate --task-id TASK-001
```

`init` создаёт полный набор MD-шаблонов и `metrics.template.json`. Артефакты регистрируются с SHA-256; изменение файла после регистрации блокирует validate.

## Гейты

| Gate | Обязательно |
|---|---|
| G0 | baseline и task созданы |
| G1 | TASK_IDEA от A |
| G2 | IMPL_PLAN от H |
| G3 | PATCH и DOC_IMPL от H |
| G4 | fast 32k ≥3 и FAST_RUN_REPORT |
| G5 | REVIEW_REPORT от N, C1–C10 true, CODE_APPROVED |
| UPSTREAM_PR_CHECK | full 160k/200k, progress на обоих, INTEGRATION_REPORT approved |
| MERGED | UPSTREAM_PR_CHECK pass |
| ARCHIVED | no_change/regress/critical_risk на любом full-окне |
| CLEANUP | локальные ветки/worktree удалены |

Пропуск gate, self-approval, неверный author, отсутствующий artifact, чужой baseline window/profile и одновременная запись блокируются.

## Метрики

Fast run — 32k, минимум три прогона. Full run — 160k и 200k отдельно, по одному прогону. Нельзя сравнивать разные окна или профили.

Merge разрешён только при `progress` на 160k И 200k. `no_change` архивируется. Регресс 32k при progress full является флагом для анализа, а не автоматическим approve.

Raw-логи хранятся в `glm/YYYY-MM-DD_session`; в docs попадают проверенные сводки.

## Qoder

A/H/N — отдельные сеансы в одном workspace. H работает в task-worktree, N читает candidate read-only, A применяет approved diff в main.

Qoder блокирует forwarding делегированной задачи, поэтому маршрут такой: A→H, H→A, A→N, N→A. Перед отправкой A проверяет target через `read_chat_session` и `wait_chat_sessions timeoutMs=0`, затем использует `callbackMode=supervise`.

`qoder-settings.json` содержит подготовленную конфигурацию hooks. Она активируется на cutover; до этого действует старый owner guard.
