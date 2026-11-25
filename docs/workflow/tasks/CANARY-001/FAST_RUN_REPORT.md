# FAST_RUN_REPORT CANARY-001

- window: 32k
- prompt_tokens: 29242
- profile: KAT IQ4_XS, graph on, q4_0, MTP0, super-chunk8, att256, reserve512, FA v2 tile4
- baseline READ_WINDOWS=1: pp 1438.9 / 1446.4 / 1439.3; median 1439.3; spread 7.5 pp (0.52%)
- candidate READ_WINDOWS=2: pp 1445.5 / 1435.8 / 1432.6; median 1435.8; spread 12.9 pp (0.90%)
- delta median: -0.24%, в пределах шума
- tg baseline: 26.1 / 24.0 / 22.1; candidate: 25.5 / 23.5 / 25.5; generation только 6 токенов, speed comparison не используется
- sanity: все шесть прогонов rc=0, ответы получены
- decision: pass; fast-регресса нет, full-решение отдельно
- raw: `glm/2026-11-25_session/upstream-merge-tool/canary-001-fast/`
