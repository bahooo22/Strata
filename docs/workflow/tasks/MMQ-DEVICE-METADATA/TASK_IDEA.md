# TASK_IDEA MMQ-DEVICE-METADATA

- goal: проверить и, только после отдельной приёмки, убрать host round-trip `rmax/count` и `cudaStreamSynchronize` из MMQ prompt path qwen35.
- source: `engine/src/qwen35/q36_engine.cu:3042-3049`; ranked hypothesis #4 в `docs/architecture/qwen35-core/improvements.md`.
- expected_effect: оценка +1–3% end-to-end pp на KAT IQ4_XS, 160k/200k; это не замер и не optimization progress.
- base_sha: `c5e4212c610f908390f1341bc53bdd2f53813058`.
- branch: `task/MMQ-DEVICE-METADATA`; experiment branch создаёт A только после утверждения плана.
- worktree: `E:/tmp/workflow-mmq-device-metadata`.

## Алгоритм эксперимента

1. H читает полный MMQ prompt path, контракт `MMQ::Product.max_rows/bounds`, route count/scatter и graph capture/replay.
2. H предлагает минимальный device-side metadata вариант: conservative upper bound либо graph-safe device metadata без D2H `rmax/count`.
3. Сохранить точный fallback на текущий host-readback путь и не менять публичные defaults без отдельного доказательства.
4. A после утверждения пользователя создаёт experiment candidate; N проверяет code/evidence; A выполняет build/tests/GPU/quality.

## Инварианты

- Численные outputs, maxr/bounds и row coverage совпадают с baseline.
- Нет OOB, пропущенных routed entries, illegal memory access или зависимости от host `hpin[10]`.
- CUDA graph capture/replay остаётся корректным; hybrid scores и session state не меняются.
- Fallback на текущий путь сохраняется при неподдерживаемой форме или ошибке metadata.

## Приёмка

- Profile: KAT IQ4_XS, RTX 3060 Ti 8 GiB, graph on, q4_0, MTP0, super-chunk8, att256, reserve512, FA v2/tile4.
- Окна: 160k и 200k; 32k только sanity.
- Numeric parity: maxr bounds, outputs, greedy/quality; graph capture/replay.
- Performance: отдельные baseline/candidate пары; эффект больше 1.5% повторять, шум не объявлять progress.
- Quality/MTP2/resources и fallback обязательны; raw evidence в `glm/2026-11-25_session/mmq-device-metadata/`.

## Границы

- В задачу не входят adaptive rebalance, super-chunk, stream depth и CPU handoff.
- H не делает commits, tests, build, GPU, push или merge; только некоммиченный пакет в task-worktree.
- Реализация начинается после личного утверждения пользователем плана H и независимого review N.
