# Прогресс завершения Strata

Дата: 2026-11-24. Обновляется сразу после каждого подпункта.

| Этап | Статус | Owner | Зависимости | Acceptance / последнее evidence | Next action |
|---|---|---|---|---|---|
| 0. Upstream refresh + tools preflight | done | main | approval | fetch rc=0, upstream unchanged `6a6db7ff5`; 14 tests OK; selftest 41/41; edge rc=0; owner guard 0/2; AST/leakcheck/diff-check rc=0 | поддерживать snapshot |
| 0. Реестры | done | main | preflight | созданы `IMPROVEMENT_REGISTRY.md`, `PROGRESS.md`; `deep-cloud-owl.md` обновлён | поддерживать статусы сразу |
| 1. Merge tools | pr-open | b8bd12b8 / main | post-mutation fix | PR #6950; unit 14/14; selftest 41/41; edge/leakcheck clean | ждать CI/review |
| 2. Локальная приёмка | in-progress | main | existing binaries/artifact | Q5.5 done: launch/connect/logs/monitor/stop; Q4.5 not-relevant | installer/source, матрица обновлена |
| 3. Upstream analysis/scope | scope-comment | 3568a3e2 / main | refreshed refs | evidence/scope comments posted to existing #5467 and #3903; no duplicate PRs | ждать мейнтейнера |
| 4. FA candidate | blocked-scope | main | maintainer answer | — | follow-up к #5467 или отдельный candidate |
| 5. FDEC q8 candidate | blocked-scope | main | maintainer answer | — | stacked experiment/адаптация к #3903 |
| 6. Q4 experiment | planned | 3568a3e2 / main | experimentRef | — | Hadamard adapter + quality, не main |
| 7. Fork integration | planned | main | accepted candidates | — | default/FA/FDEC/both combo, ff-only |
| 8. Q7 | planned | main / 3568a3e2 | integrated binary | пути модели/pack зафиксированы | stop/go, A..E 32k, needle/QA |
| 9. Portable final | planned | main | Q7 verdict, kit artifact | target `G:/Strata/` | functional smoke + HDD A/B 160k/200k |

## Протокол

- `[ ]` не начат; `[~]` частично; `[x]` принят и проверен; `[x-неактуален]` доказанно не относится; `[blocked]` есть блокер; `[defer]` experiment only.
- Каждый переход требует evidence/commit/PR, owner и next action.
