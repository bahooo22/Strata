# TASK_IDEA UPSTREAM-2AF30CCA

- owner: A `443fddf1-c6a1-4de1-a762-0b61e5ca941c`
- helper: H `b8bd12b8-6374-404d-a27b-d1937edfbc11`
- reviewer: N `9ba7a8a6-9973-4bce-8a66-93acde030932`
- baseSha: `996eb9195b1790f954dd48f50be27893cae93937`
- oursRef: `996eb9195b1790f954dd48f50be27893cae93937`
- upstreamRef: `2af30ccaa0729177c4725ee2073f72bf550e2f86`
- previousUpstream: `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`
- branch: `sync/upstream-2af30cca`
- worktree: `E:/tmp/workflow-upstream-2af30cca`

## Задача

Подготовить fork candidate для upstream delta `d46f5f2..2af30cca`: 4 коммита, 16 файлов. Ядро `engine/src/qwen35/*` не затронуто.

## Наши изменения в delta-файлах

- `engine/CMakeLists.txt` — expert types/build definitions.
- `terminal/setup.py` — qwen36 KAT/Huihui IQ4_XS launch.
- `terminal/strata_control/inkling_fit.py` — наше текущее правило планирования.
- `tools/packaging/README.md` — документация форка.

## Что должен сделать H

1. Сначала составить план действий и вернуть его A; не выполнять работу до утверждения плана пользователем.
2. После утверждения создать отдельный worktree/ветку от baseSha.
3. Заполнить `merge-plan.json` и anchor matrix: `ours/upstream/delta/hybrid/defer/drop`, якоря, алгоритмы, контракты, маршруты, ресурсы, совместимость, evidence.
4. Сохранить наши qwen36/expert-type/packaging изменения; взять upstream version bump и Terminal/HIP fixes.
5. Каждое решение оформить отдельным коммитом с реальным `commitRef`.
6. Подготовить `IMPL_PLAN.md`, `PATCH.diff`, `DOC_IMPL.md`, RU+EN MD-отчёт и полный evidence package.
7. Вернуть A branch tip, diff, plan, artifacts, команды и ограничения.

## Ограничения

- Субагенты запрещены.
- H не коммитит в main, не пушит, не мержит, не собирает и не запускает GPU.
- Не использовать force-push, `reset --hard`, amend или слепой cherry-pick.
- Не создавать upstream PR.
- Дефолты и публичные контракты сохраняются.
- GPU barrier сейчас blocked: чужой Huihui 200k run PID 8208; не прерывать.

## Приёмка A

Merge-gate, сборка CUDA, Python tests, `tools/check --strict`, marker/conflict/leakcheck, 32k smoke, 160k/200k A/B, quality/MTP/fallback/resources, независимое N review. Upstream sync принимается по совместимости и отсутствию регресса, не по speed progress.
