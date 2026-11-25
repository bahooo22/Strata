# FULL_RUN_REPORT CANARY-001

- profile: KAT IQ4_XS, graph on, q4_0, MTP0, super-chunk8, att256, reserve512, FA v2 tile4, READ_WINDOWS=2
- 160k: prompt 139299, pp896.6, tg15.9, rc0; baseline pp886.7/tg14.8; delta pp +1.12%, tg +7.43%
- 200k: prompt 202665, pp735.7, tg12.5, rc0; baseline pp731.2/tg12.4; delta pp +0.62%, tg +0.81%
- noise rule: 1–1.5% pp сначала считается шумом до повторной серии; оба pp-улучшения в этом диапазоне
- decision: no_change на обоих full-окнах
- raw: `glm/2026-11-25_session/upstream-merge-tool/canary-001-full/`
