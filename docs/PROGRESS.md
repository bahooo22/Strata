# Прогресс завершения Strata

Дата: 2026-11-24. Обновляется сразу после каждого подпункта.

| Этап | Статус | Owner | Зависимости | Acceptance / последнее evidence | Next action |
|---|---|---|---|---|---|
| 0. Upstream refresh + tools preflight | done | main | approval | fetch rc=0, upstream unchanged `6a6db7ff5`; 14 tests OK; selftest 41/41; edge rc=0; owner guard 0/2; AST/leakcheck/diff-check rc=0 | поддерживать snapshot |
| 0. Реестры | done | main | preflight | созданы `IMPROVEMENT_REGISTRY.md`, `PROGRESS.md`; `deep-cloud-owl.md` обновлён | поддерживать статусы сразу |
| 1. Merge tools | fork-only | b8bd12b8 / main | post-mutation fix | unit 14/14; selftest 41/41; edge/leakcheck clean; PR #6950 закрыт по решению заказчика | не публиковать повторно; инструмент остаётся в форке |
| 2. Локальная приёмка | in-progress | main | existing binaries/artifact | Q5.5 done; installer worktree готов, setup tests 17/17, acceptance-скрипт проверен | setup --build, marker 29/29, hygiene, smoke |
| 3. Upstream analysis/scope | analysis-done | 3568a3e2 / main | refreshed refs | anchors/evidence собраны; временные комментарии в #5467/#3903 удалены; duplicate PR не создавались | публикация остановлена; follow-up только по явному решению |
| 4. FA candidate | blocked-scope | main | maintainer answer | — | follow-up к #5467 или отдельный candidate |
| 5. FDEC q8 candidate | blocked-scope | main | maintainer answer | — | stacked experiment/адаптация к #3903 |
| 6. Q4 experiment | planned | 3568a3e2 / main | experimentRef | — | Hadamard adapter + quality, не main |
| 7. Fork integration | ready-to-run | main | accepted candidates | `8e2f2af94`, `11ff82f93`, `4d47b170f`, `bc46d7b1d`, `0c21904e7`, `e31f451b8` уже в main; upstream q36 delta пуста; combo-runner готов | default/FA/FDEC/both на свежем exe 160k/200k; отдельный merge не выполнять |
| 8. Q7 | in-progress | main / 3568a3e2 | integrated binary | A: health OK, но 18 432/32 771 за 3578 s (~5,2 tok/s), timeout до decode; B layer-major speed-only запущена | stop/go по B; C..E только после прохождения pp/tg |
| 9. Portable final | planned | main | Q7 verdict, kit artifact | target `G:/Strata/` | functional smoke + HDD A/B 160k/200k |

## Протокол

- `[ ]` не начат; `[~]` частично; `[x]` принят и проверен; `[x-неактуален]` доказанно не относится; `[blocked]` есть блокер; `[defer]` experiment only.
- Каждый переход требует evidence/commit/PR, owner и next action.
