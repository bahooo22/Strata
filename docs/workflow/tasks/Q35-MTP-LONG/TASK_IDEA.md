# TASK_IDEA Q35-MTP-LONG

- goal: измерить MTP1/2/3 и draft-vocab на длинном decode 160k/200k, где текущий performance profile использует MTP0.
- source: исторические 16k MTP2 42.1 tg против 35.3 без MTP; текущий MTP2 smoke drafts 2/4.
- expected_effect: оценка +5–20% tg; приёмка обязана подтвердить ≥5% без регресса pp/quality.
- base_sha: `3f01707a2295aae5bdb5dbb83bd42be4d2e185e9`.
- branch: `task/Q35-MTP-LONG`.

## Алгоритм

1. H описывает матрицу MTP0/1/2/3 и draft-vocab без изменения code defaults.
2. Отдельно измерить draft cost, verify cost, accepted/offered и token diff.
3. A после утверждения запускает длинные пары на одном build/profile.

## Приёмка

- 160k/200k, graph on, q4_0, super-chunk8, att256, reserve512, FA v2/tile4.
- tg/pp/TTFT, accept-rate, quality, MTP2 route, resources.
- Выигрыш <5% tg или quality regression — архив.
