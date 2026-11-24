# Реестр улучшений Strata

Обновляется главной сессией в том же ходе, где получен результат. Статусы: `planned`, `analysis`, `candidate`, `blocked`, `defer`, `pr-open`, `done`, `not-relevant`.

| ID | Улучшение | Решение | Статус | Owner | Evidence / PR | Next action / блокер |
|---|---|---|---|---|---|---|
| TOOLS-MERGE | upstream merge gate/lifecycle/owner guard | ours, internal | fork-only | b8bd12b8 / main | unit 14/14; selftest 41/41; edge/leakcheck clean; PR #6950 закрыт по решению заказчика | не публиковать повторно |
| LAUNCH-OWN-SIZE | launch для GGUF с нестандартным именем | delta | done | main | `ba9ae196e`; health/API/connect/logs/stop OK | monitor 404 — отдельный блокер |
| REFACTOR-SRP | широкий рефакторинг engine/ownership | idea only | not-in-scope | main | `docs/plans/2026-11-24-upstream-safe-refactor.md` | только документ, без candidate/main |
| EXPERT-TYPES | полный routed-expert контракт 10/11/18/21 | delta к upstream | done | main / 3568a3e2 / b8bd12b8 | `a8ebf5d59`; patch SHA `017d5621`; CUDA/non-Q6K rc=0; CTest 5/5; grouped/MMVQ PASS; hygiene rc=0; markers 29/29 | HIP not-run с waiver только для этого patch; отдельная приёмка при появлении toolchain |
| UPSTREAM-MERGE | fork sync с upstream `d46f5f2` | matrix ours/upstream/delta/hybrid | done | helper b8bd12b8 / аналитик 3568a3e2 / main | `cc195b909`; merge-base `923e2df4d`; main ahead upstream `253/0`; analyst APPROVE; main gate pass; push rc=0 | RU+EN MD-отчёты; warning-code fix отдельным коммитом |
| INTEGRATION-COMBO | default/FA/FDEC/both snapshot | ours | done-snapshot | main / 3568a3e2 | 8/8 rc=0; raw audit 8/8; quality 16/22 + needle PASS; MTP2 answer Принято; eager/copy equal=True | no-regression без repeats не заявлен; HIP not-run; FA optional, FDEC/both не рекомендованы |
| FA-v2 | q36 FA v2 16x32 | ours | combo-reviewed | main / 3568a3e2 | combo 160k pp 579,1/tg 13,7; 200k pp 381,9/tg 11,0; review APPROVE optional snapshot | не default; upstream follow-up только по явному решению |
| FA-PROF-V | слот V в FA_PROF | delta к FA-v2 | not-standalone | main | `FA_PHASE(2)`, пять фаз | включить в FA candidate |
| FDEC-Q8 | decode MMA для upstream INT8 layout | delta | combo-regression | main / 3568a3e2 | combo MTP0/q4_0/graph: 160k tg 12,4 vs 13,2; 200k tg 9,8 vs 10,8; review не рекомендует FDEC/both | не заявлять улучшение в этой конфигурации; не default |
| FDEC-Q4 | decode MMA для rotated Q4 | defer | experiment-only | 3568a3e2 / main | наш q4 KL идентичен без FDEC; upstream Hadamard | experimentRef, Hadamard Q/inverse V, quality |
| FDEC-VERDICT | armed/no-route строка | delta к FDEC-Q8 | not-standalone | main | `e31f451b8` на форке | включить в FDEC q8 PR |
| FDEC-GOLDEN-Q8 | golden распаковки q8 | hybrid/часть FDEC-Q8 | analysis | main | 12288/0 на нашем header | использовать реальные upstream helpers; q8 evidence в PR |
| STAGING-ONE | один staging-буфер | delta | pr-open | main | #6902, CI success | ждать review, не дублировать |
| DOWN-SUB8 | opt-out 8-lane down | delta | pr-open | main | #6898, CI success | ждать review, не дублировать |
| Q4.5 | kit sync/ctx=max | not-relevant | done | main | tracked `packaging/kit` пуст; `ctx=max` только в docs-коммитах | отметить в основном плане; новый reproducer — отдельный дефект |
| Q5.5 | connect/logs/monitor/stop | ours | done | main | launch/connect/logs/stop OK; `ci-portable-verdict.md`; прямые monitor endpoints 404 — отдельный блокер | installer/source — отдельный QUICKSTART |
| QUICKSTART | три пути 1-click | ours | done | main | installer/source OK; Portable wrapper/inner/engine SHA; functional API/connect/logs/monitor/stop OK; HDD 200k 376,7/11,0, 160k 560,6/13,7 | HDD числа абсолютные, не SSD claim; models remain on D: |
| Q7 | Swift Qwen3.8 32k | ours/existing knobs | blocked | main / 3568a3e2 | A auto 9,8; B8192 18,2; B LM32768 ~63,3 tok/s, затем 503; C20 exit 2 без static expert-profile; build `exp/q7-native-spec0` | unblock: Swift profile + диагностика 503 + повтор C20; quality/C24/D/E not-run |

## Upstream publication protocol

- Issue/PR text is English; internal discussion and reports are Russian.
- Before drafting: read `.github/CONTRIBUTING.md`, `.github/pull_request_template.md`, `AGENTS.md` and applicable target-repo policies.
- Search open and closed issues/PRs for duplicates; use the required area prefix and one problem per PR.
- Validation is split into Passed / Failed / Not run; new behavior is opt-in and the default remains byte-identical.
- Build every touched backend and make no unverified claim. Re-snapshot refs and anchors against the current upstream SHA before posting.

## Upstream snapshot

- 2026-11-25 merge выполнен: upstream `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`, merge-base `923e2df4d`, main `cc195b909a1a6878a2a44bf9cabb1462e3d55d6a`; main ahead/behind к upstream `253/0`; push main и candidate-ветки rc=0.
- Refs и состояние дерева зафиксированы в `glm/2026-11-24_session/final-upstream-snapshot-2026-11-24.log`.
- Read-only supersession review `final-upstream-supersession-review-2026-11-24.md`: новый upstream не заменяет пакет целиком; перед merge нужен re-anchor анализ и повторная сборка/GPU-приёмка.
