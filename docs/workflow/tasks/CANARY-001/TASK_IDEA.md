# TASK_IDEA CANARY-001

- goal: проверить workflow v3 на реальном эксперименте `STRATA_Q36_READ_WINDOWS=2` для KAT IQ4_XS.
- idea_algorithm: сравнить default 1 и env 2 на одном профиле graph on/q4_0/MTP0/super-chunk8/att256/reserve512/FA v2 tile4; fast 32k ≥3, full 160k/200k отдельно.
- constraints: engine-код не меняется; H готовит только experiment profile/PATCH/DOC_IMPL в task-worktree; N read-only; merge только при progress на обоих full-окнах.
- expected_effect: не задан заранее; canary проверяет процесс и честное merge/archive решение.
- baseline_full: 160k pp886.7/tg14.8; 200k pp731.2/tg12.4; baseline_32k снимается в том же окне перед экспериментом.
- base_sha: `4356a467780900923cbf83d92675790e7fbeb32a`
- branch: `task/CANARY-001`
