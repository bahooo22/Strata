# FULL_RUN_REPORT

| window | pairs | baseline pp | candidate pp | Δpp | baseline tg | candidate tg | Δtg | decision |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 160k | 1 | 890.7 | 888.7 | -0.22% | 15.9 | 15.8 | -0.91% | no_change |
| 200k | 3 | 733.8 | 733.0 | +0.02% | 12.5 | 12.5 | -1.58% | no_confirmed_regression |

Предупреждение: Порог 1.5% превышен оценкой с контролем порядка, но обратный порядок даёт противоположный знак; регрессия не подтверждена.

Сырые значения рассчитаны по `prompt_tokens/prefill_ms` и `generated/gen_ms`; порядок A/B зафиксирован в `evidence/acceptance/performance.json`.
