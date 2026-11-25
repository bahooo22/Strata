# Прогресс завершения Strata

Дата: 2026-11-25. Обновляется сразу после каждого подпункта.

| Этап | Статус | Owner | Зависимости | Acceptance / последнее evidence | Next action |
|---|---|---|---|---|---|
| 0. Upstream refresh + tools preflight | done | main | approval | upstream `2af30cca` (+4), merge-base `d46f5f2`, candidate `36e044b0`; preflight/unit/selftest/edge PASS | следующий refresh — read-only audit |
| 0. Реестры | done | main | preflight | созданы `IMPROVEMENT_REGISTRY.md`, `PROGRESS.md`; `deep-cloud-owl.md` обновлён | поддерживать статусы сразу |
| 1. Merge tools | fork-only | b8bd12b8 / main | post-mutation fix | unit 16/16; selftest 42/42; edge/leakcheck clean; PR #6950 закрыт по решению заказчика | не публиковать повторно; инструмент остаётся в форке |
| 1.1 RU+EN merge docs | done | main | accepted merge tool | `document` генерирует MD по upstream commits, matrix decisions, conflicts, adaptations, evidence и waivers; реальный отчёт 291/697/18/4/4 | поддерживать генератор и включать отчёты в candidate |
| 1.2 Workflow v3 | done | A/H/N | approved plan | unit 6/6; hook selftest 7/7; cutover выполнен; CANARY-001 дошёл до CLEANUP с ARCHIVED/no_change; архивная ветка `301eda3ba` сохранена на GitHub | поддерживать guard/state; отдельная задача launch #18 остаётся |
| 2. Локальная приёмка | done | main | existing binaries/artifact | Q5.5 done; installer setup build rc=0, hygiene rc=0, marker 29/29, smoke health OK/answer Да | поддерживать evidence; Portable отдельно |
| 3. Upstream analysis/scope | analysis-done | 3568a3e2 / main | refreshed refs | anchors/evidence собраны; временные комментарии в #5467/#3903 удалены; duplicate PR не создавались | публикация остановлена; follow-up только по явному решению |
| 3.1 Экспертные типы 10/11/18/21 | done | main / 3568a3e2 / b8bd12b8 | main `a8ebf5d59` | CUDA/non-Q6K rc=0; CTest 5/5; grouped/MMVQ PASS; hygiene rc=0; markers 29/29; review APPROVE | HIP not-run с waiver; quality/MTP smoke, затем Portable |
| 4. FA candidate | blocked-scope | main | maintainer answer | — | follow-up к #5467 или отдельный candidate |
| 5. FDEC q8 candidate | blocked-scope | main | maintainer answer | — | stacked experiment/адаптация к #3903 |
| 6. Q4 experiment | planned | 3568a3e2 / main | experimentRef | — | Hadamard adapter + quality, не main |
| 7. Fork integration | done-snapshot | main | accepted candidates | 8/8 combo rc=0; eager/copy equal=True; quality 16/22 + needle PASS; MTP2 answer Принято; review APPROVE snapshot | no-regression без repeats не заявлен; HIP not-run; Portable final |
| 8. Q7 | blocked | main / 3568a3e2 | integrated binary | A auto 9,8; B8192 18,2; B LM32768 ~63,3 tok/s, затем 503; C20 exit 2 без static expert-profile | unblock: Swift profile + диагностика 503 + повтор C20; quality/C24/D/E not-run |
| 9. Portable final | done | main | Q7 verdict, kit artifact | functional OK; HDD 200k pp 376,7/tg 11,0; 160k pp 560,6/tg 13,7; VRAM 0 | абсолютный HDD-вариант; финальный completion audit |
| 10. Upstream merge `d46f5f2` | done | helper → аналитик → helper → main | upstream `d46f5f2` | atomic candidate `cc195b909`; analyst APPROVE; main gate pass; performance/quality/MTP2/fallback/resources приняты; push main+candidate rc=0; RU+EN MD и warning-code fix приняты | поддерживать refs и generated reports |
| 11. Upstream merge `2af30cca` | done | A/H/N | upstream `2af30cca` | candidate `36e044b045bf18e35e3089a9527fc9c86c57ee88`; N CODE_APPROVED; static 21/21; CUDA markers 29/29; 160k/200k A/B, quality, MTP2 route, resources приняты; performance warning сохранён | поддерживать refs; улучшения — отдельный TASK_IDEA |

## Протокол

- `[ ]` не начат; `[~]` частично; `[x]` принят и проверен; `[x-неактуален]` доказанно не относится; `[blocked]` есть блокер; `[defer]` experiment only.
- Каждый переход требует evidence/commit/PR, owner и next action.
| 12. qwen35 core architecture | done | main | post-merge SHA | 27 классов/237 символов/300 call edges; 659/659 sourceRefs; пять Mermaid sources; master-схема в docs/architecture/qwen35-core | поддерживать sourceRefs при изменениях ядра |
| 13. Пять ускорений qwen35 | analysis-done | main | architecture audit + порог 5% | ranked shortlist опубликован; #4 (+1–3%) и #5 (+1–4%) исключены; первый candidate #2 adaptive super-chunk | новый TASK_IDEA для #2 и обязательная приёмка ≥5% end-to-end |
