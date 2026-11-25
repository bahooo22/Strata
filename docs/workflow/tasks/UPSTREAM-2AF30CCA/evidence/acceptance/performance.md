# Upstream performance acceptance

| window | pairs | baseline pp | candidate pp | Δpp | baseline tg | candidate tg | Δtg | raw median tg | aggregation | decision |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 160k | 1 | 890.7 | 888.7 | -0.22% | 15.9 | 15.8 | -0.91% | -0.91% | median of paired deltas | no_change |
| 200k | 3 | 733.8 | 733.0 | +0.02% | 12.5 | 12.5 | -1.58% | -2.24% | order-adjusted difference-in-differences | no_confirmed_regression |

Предупреждение: Порог 1.5% превышен оценкой с контролем порядка, но обратный порядок даёт противоположный знак; регрессия не подтверждена.

## Пары 200k

| label | order | Δpp | Δtg |
|---|---|---:|---:|
| full | baseline->candidate | +0.09% | -3.00% |
| repeat | baseline->candidate | -0.37% | -2.24% |
| repeat2 | candidate->baseline | -0.18% | +0.54% |
