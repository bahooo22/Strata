# Прогресс завершения Strata

Дата: 2026-11-24. Обновляется сразу после каждого подпункта.

| Этап | Статус | Owner | Зависимости | Acceptance / последнее evidence | Next action |
|---|---|---|---|---|---|
| 0. Upstream refresh + tools preflight | done | main | approval | начальный fetch rc=0; финальный upstream `d46f5f2` (+276), merge-base `923e2df4d`, ahead/behind `240/291`; merge не выполнялся | новый upstream только read-only audit; merge по отдельному разрешению |
| 0. Реестры | done | main | preflight | созданы `IMPROVEMENT_REGISTRY.md`, `PROGRESS.md`; `deep-cloud-owl.md` обновлён | поддерживать статусы сразу |
| 1. Merge tools | fork-only | b8bd12b8 / main | post-mutation fix | unit 14/14; selftest 41/41; edge/leakcheck clean; PR #6950 закрыт по решению заказчика | не публиковать повторно; инструмент остаётся в форке |
| 2. Локальная приёмка | done | main | existing binaries/artifact | Q5.5 done; installer setup build rc=0, hygiene rc=0, marker 29/29, smoke health OK/answer Да | поддерживать evidence; Portable отдельно |
| 3. Upstream analysis/scope | analysis-done | 3568a3e2 / main | refreshed refs | anchors/evidence собраны; временные комментарии в #5467/#3903 удалены; duplicate PR не создавались | публикация остановлена; follow-up только по явному решению |
| 3.1 Экспертные типы 10/11/18/21 | done | main / 3568a3e2 / b8bd12b8 | main `a8ebf5d59` | CUDA/non-Q6K rc=0; CTest 5/5; grouped/MMVQ PASS; hygiene rc=0; markers 29/29; review APPROVE | HIP not-run с waiver; quality/MTP smoke, затем Portable |
| 4. FA candidate | blocked-scope | main | maintainer answer | — | follow-up к #5467 или отдельный candidate |
| 5. FDEC q8 candidate | blocked-scope | main | maintainer answer | — | stacked experiment/адаптация к #3903 |
| 6. Q4 experiment | planned | 3568a3e2 / main | experimentRef | — | Hadamard adapter + quality, не main |
| 7. Fork integration | done-snapshot | main | accepted candidates | 8/8 combo rc=0; eager/copy equal=True; quality 16/22 + needle PASS; MTP2 answer Принято; review APPROVE snapshot | no-regression без repeats не заявлен; HIP not-run; Portable final |
| 8. Q7 | blocked | main / 3568a3e2 | integrated binary | A auto 9,8; B8192 18,2; B LM32768 ~63,3 tok/s, затем 503; C20 exit 2 без static expert-profile | unblock: Swift profile + диагностика 503 + повтор C20; quality/C24/D/E not-run |
| 9. Portable final | done | main | Q7 verdict, kit artifact | functional OK; HDD 200k pp 376,7/tg 11,0; 160k pp 560,6/tg 13,7; VRAM 0 | абсолютный HDD-вариант; финальный completion audit |

## Протокол

- `[ ]` не начат; `[~]` частично; `[x]` принят и проверен; `[x-неактуален]` доказанно не относится; `[blocked]` есть блокер; `[defer]` experiment only.
- Каждый переход требует evidence/commit/PR, owner и next action.
