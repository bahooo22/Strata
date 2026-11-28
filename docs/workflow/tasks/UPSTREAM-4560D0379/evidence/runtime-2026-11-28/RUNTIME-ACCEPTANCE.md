# UPSTREAM-4560D0379 — runtime acceptance

- Candidate runtime/build HEAD: `2195f9b0f`; evidence review base: `135ddea4e`.

| window | baseline pp/tg | candidate pp/tg | Δpp | Δtg | answer parity |
|---|---:|---:|---:|---:|---|
| 32k | 1551.05/23.55 | 1518.75/22.50 | -2.082% | -4.459% | True |
| 160k | 908.35/16.30 | 908.05/16.30 | -0.033% | +0.000% | True |
| 200k | 746.10/12.30 | 746.30/12.45 | +0.027% | +1.220% | True |

## Дополнительные gates

- 32k repeat 3+3: True; Δpp -0.330%, Δtg -2.418%.
- MTP2 32k: True; exact answer parity.
- Quality general: True; 12 задач, 16/22 у обеих сторон.
- Copy_session: True; prefix 18000, fresh 2000, tokens equal.

## Ограничения

- Performance является descriptive; speed progress не заявляется.
- GPU parity: 85 passed, 1 skipped, 1 baseline-identical failure (Q6_K+Q8_0).
- Полный protocol edge matrix и full engine sanitizer не запускались по baseline blockers.
- Main merge/push не выполнялись.

## Fallback cuBLAS

- `--fa -1 --fa-tile 0`, 32k AB/BA: exact answer parity.
- Baseline pp/tg: 1480.10/21.65; candidate: 1475.95/22.95.
- Performance является descriptive; fallback acceptance подтверждает корректность, не speed progress.
