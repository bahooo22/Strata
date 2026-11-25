# DECISION_RECORD

- decision: `MERGED`
- reason: upstream hotfix `2af30cca` принят после N `INTEGRATION_APPROVED`, semantic gate PASS 7/7 и ff-only promotion D5 `36e044b045bf18e35e3089a9527fc9c86c57ee88`.
- evidence: `docs/reports/2026-11-25-upstream-2af30cca-final-review.md`, `docs/reports/2026-11-25-upstream-2af30cca-acceptance.md`, `evidence/acceptance/summary.json`, archive tag `archive/upstream-2af30cca-36e044b04`.
- feedback: performance warning 200k сохранён; HIP runtime not-run; MTP CLI diagnostic одинаков на baseline/candidate, MTP2 serve route принят.
- workflow_note: generic state-machine требует optimization `progress` и три fast runs; для upstream sync утверждённый план допускает `no_change`/`no_confirmed_regression` и два smoke run. A закрыл задачу в `CLEANUP` по N verdict и semantic gate, без ослабления code/evidence проверок.
