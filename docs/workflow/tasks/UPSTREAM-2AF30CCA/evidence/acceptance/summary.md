# Upstream 2af30cca acceptance

Вердикт: PASS.

| Проверка | Результат |
|---|---|
| performance | PASS |
| static | PASS |
| smoke | PASS |
| build | PASS |
| buildIdentity | PASS |
| kvQuality | PASS |
| kvQualityNoRegression | PASS |
| qualityGeneralRun | PASS |
| qualityGeneralNoRegression | PASS |
| needle | PASS |
| resourcesRun | PASS |
| resourcesCases | PASS |
| mtpRun | PASS |
| mtpDraftsParsed | PASS |
| mtpRouteActive | PASS |
| mtpAnswersEqual | PASS |

## Performance

| window | pairs | Δpp | Δtg | decision |
|---|---:|---:|---:|---|
| 160k | 1 | -0.22% | -0.91% | no_change |
| 200k | 3 | +0.02% | -1.58% | no_confirmed_regression |

## Quality

- General hard: 16/22 (0.727); baseline 16/22 (0.727).
- Failures: cap3, five_words, idiom; baseline: cap3, five_words, idiom.
- needle24k: PASS.

## MTP и ресурсы

- MTP accepted base/test: ['baseline 2/4', 'candidate 2/4']; token diff: 0.
- Resource cases rc: FA=0, default=0.

## Ограничения

- `tools/check`: docs links/settings register падают идентично на main/candidate; cmake/pytest/Node/torch шаги not-run.
- HIP: not-run без HIP toolchain/hardware; upstream HIP delta покрыта static tests и N review.
- MTP CLI diagnostic: `mtp_accept.py` упал 0xC0000409 одинаково на baseline/candidate; принятие выполнено через штатный serve launcher.
