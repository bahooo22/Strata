# Безопасный мерж upstream

Инструмент: `tools/upstream_merge/upstream_merge.py`.

## Принцип

Мерж выполняется только по матрице решений. Инструмент не принимает решения за человека и не пушит изменения без явного `--yes --push`. Для полного цикла A/H/N используйте [workflow v3](workflow/README.md).

## Команды

```text
python tools/upstream_merge/upstream_merge.py preflight --repo . --ours main --upstream upstream/main
python tools/upstream_merge/upstream_merge.py preflight --repo . --fetch
python tools/upstream_merge/upstream_merge.py matrix --repo . --profile tools/upstream_merge/merge_profile.example.json --out merge-matrix.json
python tools/upstream_merge/upstream_merge.py prepare --repo . --branch sync/upstream-0.2.21 --yes
python tools/upstream_merge/upstream_merge.py experiment --repo . --branch opt/example --yes
python tools/upstream_merge/upstream_merge.py status --repo .
python tools/upstream_merge/upstream_merge.py check --repo . --plan merge-plan.json --format both
python tools/upstream_merge/upstream_merge.py document --repo . --plan merge-plan.json --out-dir docs/upstream-merges --conflict-decisions conflict-decisions.json
python tools/upstream_merge/upstream_merge.py promote --repo . --branch opt/example --plan merge-plan.json --report-out merge-promote.json --yes
python tools/upstream_merge/upstream_merge.py promote --repo . --branch opt/example --plan merge-plan.json --report-out merge-promote.json --yes --push --pr --delete-local
python tools/upstream_merge/upstream_merge.py abort --repo . --yes
python tools/upstream_merge/upstream_merge.py selftest
```

## Безопасность

- `preflight` без `--fetch` только читает refs и дерево.
- `matrix` строит черновик: наличие якоря не определяет `full/partial/none`; нужны явный статус, evidence и ручной review.
- `prepare` без `--yes` ничего не меняет.
- `prepare --yes` создаёт локальный backup tag, sync-ветку и запускает `merge --no-ff --no-commit`.
- `check` и `promote` сначала валидируют `tools/upstream_merge/merge-plan.schema.json`, затем семантику `merge_gate`: refs, ancestry, dirty tree, anchors, evidence, warnings и независимое review.
- Современный план обязан содержать все 14 категорий evidence; `anchorMethod`/`anchorEvidence` обязательны, `anchorStatus=missing` блокируется.
- Каждый `implementationCombinations` run имеет собственные `status=passed`, `revision` и непустой `evidence`; `anchorStatus=removed` допускается только для `drop` с полной upstream-заменой.
- `abort --yes` выполняет только `git merge --abort`.
- Push требует явного `--yes --push`; PR дополнительно требует `--pr` и `gh`.

## MD-отчёт по merge

`document` читает pinned refs из `merge-plan.json`, перечисляет upstream commits от merge-base до upstream, их файлы и исходные сообщения, затем связывает изменения с matrix decisions, conflicts и additional adaptations. Результат сохраняется в `docs/upstream-merges/<upstream>-<candidate>-<дата>.ru.md` и `.en.md`.

Английский отчёт содержит переводные заголовки и решения, а исходные русские rationale/algorithm fields сохраняет как source text; commit messages upstream остаются дословно. Команда не меняет refs и не коммитит файлы — сгенерированные MD нужно проверить и включить в candidate отдельным commit.

## Жизненный цикл эксперимента

- `experiment --yes` создаёт отдельную ветку от `main`.
- Эксперимент коммитится в своей ветке.
- Успешный эксперимент проходит `check --run-checks`.
- `promote --yes` требует `--report-out`, включает полный gate-отчёт, создаёт backup tag и переводит `main` через `--ff-only`.
- До изменения refs записывается `promote-started`; финальный отчёт включает gate, cleanup errors и recovery metadata.
- При сбое tag/switch/merge инструмент откатывает созданные tag/ветку и возвращает recovery-отчёт.
- `--push` отправляет `main` и экспериментальную ветку атомарно через `--atomic`.
- `--pr` создаёт PR через `gh`; без `gh` команда отклоняется до изменения main.
- `--delete-local` удаляет только локальную ветку и только после успешного push; remote-ветка остаётся.

## Владелец сборок и прогонов

Проектный hook `.qoder/settings.json` вызывает `tools/upstream_merge/owner_guard.ps1`. Он получает `session_id` из PreToolUse и разрешает build/test команды только сеансу `443fddf1-c6a1-4de1-a762-0b61e5ca941c`. Остальные сеансы получают блокирующий отказ. Эти два файла — локальная обвязка сеанса и не включаются в upstream PR.

## Порядок

1. Preflight и матрица «наш патч vs апстрим».
2. Ручное сравнение алгоритмов, контрактов, маршрута, ресурсов и совместимости.
3. Заполнение `merge-plan.json`.
4. `prepare --yes` в отдельной sync-ветке.
5. Разрешение конфликтов по матрице.
6. Сборка, тесты, correctness/quality и контрольные точки.
7. `check --run-checks`.
8. Переход `main` через `--ff-only` только после зелёного гейта.

## Текущий sync `2af30cca`

- ours/base: `996eb9195b1790f954dd48f50be27893cae93937`.
- upstream: `2af30ccaa0729177c4725ee2073f72bf550e2f86`; merge-base: `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`.
- candidate/main: `36e044b045bf18e35e3089a9527fc9c86c57ee88`; code merge: `cc5f3e668ed66cba6cc862ab10e1b6ebc569c2b1`; qwen35 diff пуст.
- N review: `CODE_APPROVED`; static 21/21; CUDA build rc=0; markers 29/29.
- Runtime: 32k graph/eager, 160k/200k A/B, KV quality, general hard 16/22, needle24k, MTP2 route, resources PASS.
- Performance warning: 200k raw median tg -2.24%, order-adjusted -1.58%, обратная пара +0.54%; регрессия не подтверждена.
- Not-run: HIP runtime; `tools/check` сохраняет идентичные main/candidate baseline docs-ошибки и отсутствующие cmake/pytest/Node/torch.
- Raw evidence: `glm/2026-11-25_session/upstream-2af30cca/`; candidate evidence: `docs/workflow/tasks/UPSTREAM-2AF30CCA/`.

## Текущий sync `4560d0379` (v0.2.23)

- ours/base: `34bd46b86641d4fe34b3ab523e31b816718347e1`.
- upstream: `4560d03793482ef367294cfbd86a4df8d5679e72`; merge-base: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- accepted candidate/main: `c54211739bf8998c0c1d5730494f78a0b77c7b7a`; qwen35 diff пуст; backup tag `upstream-0.2.23-premerge-2026-11-28`.
- N review: `APPROVED_UPSTREAM_4560D0379_CANDIDATE`; 34 matrix rows; 102 anchor locations; schema и semantic merge-gate `--run-checks` PASS, blockers 0/notRun 0.
- Build/tests: CUDA rc=0, markers 29/29; targeted unittest Ran 86/skipped 2/failures 0; GPU parity 85 passed, 2 skipped, 1 baseline-identical failure.
- Runtime: 32k/160k/200k AB/BA exact parity; repeat 3+3; MTP2; quality 16/22 identical; copy_session resume 18000/fresh 2000; cuBLAS fallback `--fa -1` 4/4 rc0 exact parity.
- Performance descriptive; speed progress не заявляется. HIP/SYCL/Metal/CPU и full engine sanitizer not-run.
- Push `origin/main` rc=0; main и origin/main равны `c54211739`.
- Raw evidence: `glm/2026-11-27_session/upstream-4560d0379-FINAL-ACCEPTANCE-2026-11-28.md`; candidate evidence: `docs/workflow/tasks/UPSTREAM-4560D0379/`.
- Generated RU+EN report: `docs/upstream-merges/4560d0379348-c54211739bf8-2026-11-28.ru.md` и `.en.md`.
