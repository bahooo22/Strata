# Прогресс завершения Strata

Дата: 2026-11-24. Обновляется сразу после каждого подпункта.

| Этап | Статус | Owner | Зависимости | Acceptance / последнее evidence | Next action |
|---|---|---|---|---|---|
| 0. Upstream refresh + tools preflight | done | main | approval | fetch rc=0, upstream unchanged `6a6db7ff5`; 14 tests OK; selftest 41/41; edge rc=0; owner guard 0/2; AST/leakcheck/diff-check rc=0 | поддерживать snapshot |
| 0. Реестры | done | main | preflight | созданы `IMPROVEMENT_REGISTRY.md`, `PROGRESS.md`; `deep-cloud-owl.md` обновлён | поддерживать статусы сразу |
| 1. Merge tools | fork-only | b8bd12b8 / main | post-mutation fix | unit 14/14; selftest 41/41; edge/leakcheck clean; PR #6950 закрыт по решению заказчика | не публиковать повторно; инструмент остаётся в форке |
| 2. Локальная приёмка | done | main | existing binaries/artifact | Q5.5 done; installer setup build rc=0, hygiene rc=0, marker 29/29, smoke health OK/answer Да | поддерживать evidence; Portable отдельно |
| 3. Upstream analysis/scope | analysis-done | 3568a3e2 / main | refreshed refs | anchors/evidence собраны; временные комментарии в #5467/#3903 удалены; duplicate PR не создавались | публикация остановлена; follow-up только по явному решению |
| 3.1 Экспертные типы 10/11/18/21 | candidate-build | main / 3568a3e2 / b8bd12b8 | main `20f7e077c` | candidate `exp/expert-types-full`; patch SHA `bbe334f7`; static 27/27; compile-fix `Split<10>::sc uint8_t` | повторная CUDA build, GPU parity/sub8/mode0/8, review, commit/ff-only |
| 4. FA candidate | blocked-scope | main | maintainer answer | — | follow-up к #5467 или отдельный candidate |
| 5. FDEC q8 candidate | blocked-scope | main | maintainer answer | — | stacked experiment/адаптация к #3903 |
| 6. Q4 experiment | planned | 3568a3e2 / main | experimentRef | — | Hadamard adapter + quality, не main |
| 7. Fork integration | reviewed-snapshot | main | accepted candidates | 8/8 combo rc=0; eager/batch2/session copy equal=True; review APPROVE code/default snapshot, REJECT полный no-regression/quality | не заявлять no-regression; quality/MTP/eager/fallback/backend gaps явно перечислены; отдельный merge не выполнять |
| 8. Q7 | blocked | main / 3568a3e2 | integrated binary | A auto 9,8; B8192 18,2; B LM32768 ~63,3 tok/s, затем 503; C20 exit 2 без static expert-profile | unblock: Swift profile + диагностика 503 + повтор C20; quality/C24/D/E not-run |
| 9. Portable final | planned | main | Q7 verdict, kit artifact | target `G:/Strata/` | functional smoke + HDD A/B 160k/200k |

## Протокол

- `[ ]` не начат; `[~]` частично; `[x]` принят и проверен; `[x-неактуален]` доказанно не относится; `[blocked]` есть блокер; `[defer]` experiment only.
- Каждый переход требует evidence/commit/PR, owner и next action.
