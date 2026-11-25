# TASK_IDEA Q35-VRAM-RECLAIM

- goal: освободить VRAM под expert slots и измерить влияние на pp/tg без снижения качества.
- source: `engine/docs/profile-q36.md:101-112` — освобождение 336 MiB дало +6 слотов, +8% pp и +28% tg; текущая qwen35 allocation/placement логика.
- expected_effect: оценка +5–15% end-to-end; приёмка обязана подтвердить ≥5%.
- base_sha: `65a7012e5ab39dff8bbddd0b35de10764269f2b0`.
- branch: `task/Q35-VRAM-RECLAIM`.

## Алгоритм

1. H строит VRAM waterfall: KV, attention, activation, staging, MMQ arenas, expert slots, reserve.
2. Найти неиспользуемые MMQ/staging allocations при `use_mmq=false` и безопасно убрать их.
3. Оценить host KV offload как отдельный option, если audit покажет дефицит slots.
4. Сохранить fallback и текущий memory budget.

## Приёмка

- Slots/VRAM peaks до/после, 160k/200k pp/tg, quality/MTP2, fallback и cancel.
- Обязательный минимум +5% end-to-end; иначе архив.
