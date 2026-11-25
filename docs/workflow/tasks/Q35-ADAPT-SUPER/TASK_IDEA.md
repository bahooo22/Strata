# TASK_IDEA Q35-ADAPT-SUPER

- goal: подбирать super-chunk N по ctx, VRAM, expert slots и staging вместо фиксированного 8.
- source: `engine/src/qwen35/q36_engine.cu:3670-3707`; `engine/docs/profile-q36.md:171-190`, исторические N=4 дали +21–28% pp на 64k/96k/128k.
- expected_effect: оценка +5–15% pp на 160k/200k; приёмка обязана подтвердить ≥5%.
- base_sha: `316bb4a962832f0203dd7d52078b0b862ea2902f`.
- branch: `task/Q35-ADAPT-SUPER`.

## Алгоритм

1. H предлагает policy выбора N и отдельный diagnostic grid N=4/8/12/16.
2. Сохранить текущий N=8 как fallback и не менять default до зелёного A/B.
3. Учесть MTP overhead, cancellation, staging и expert slots.

## Приёмка

- 160k/200k, KAT IQ4_XS, graph on, q4_0, MTP0, att256, reserve512, FA v2/tile4.
- pp/tg/TTFT, VRAM/RAM, quality/MTP2, cancel.
- Выигрыш <5% pp — архив.
