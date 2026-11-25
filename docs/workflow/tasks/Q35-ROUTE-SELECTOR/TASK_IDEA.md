# TASK_IDEA Q35-ROUTE-SELECTOR

- goal: адаптировать upstream per-layer route selector `q36_layer_route` для qwen35 без MMQ: fused → int8 → grouped по слою, типу и форме.
- source: upstream `engine/src/qwen35/q36_engine.cu:2012-2041`; fork `engine/src/qwen35/q36_engine.cu:2146,3082-3115`.
- expected_effect: оценка +5–15% pp на 160k/200k; приёмка обязана подтвердить ≥5% end-to-end.
- base_sha: `91120267f0d55da976cce99aa464cd2bf9b6b164`.
- branch: `task/Q35-ROUTE-SELECTOR`.

## Алгоритм

1. H читает upstream route selector, наш P0/P1/P4 и `q36_prompt_route.hpp`.
2. Предложить минимальную адаптацию без восстановления MMQ и без смены публичного default.
3. Сохранить exact fallback на текущий int8/grouped path.
4. A после утверждения создаёт candidate; N проверяет routing, parity и fallback.

## Приёмка

- KAT IQ4_XS, graph on, q4_0, MTP0, super-chunk8, att256, reserve512, FA v2/tile4.
- 160k/200k A/B; route counts, outputs, pp/tg, quality/MTP2/resources.
- Любой выигрыш ниже 5% архивируется.
