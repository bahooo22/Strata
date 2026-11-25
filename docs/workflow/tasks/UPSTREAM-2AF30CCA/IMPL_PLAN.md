# IMPL_PLAN UPSTREAM-2AF30CCA

- implementation_algorithm: A применяет upstream delta `d46f5f2..2af30cca` в отдельном candidate-worktree обычными content commits C1..C5, затем создаёт merge commit M с parents C5/upstream и деревом C5. H не коммитит и не переключает task-worktree.
- code_parts: C1 version/packaging; C2 setup install folder; C3 HIP RAM slack; C4 HIP K/V window/choice; C5 upstream tests. qwen35 и fork qwen36/expert/planner/packaging якоря сохраняются.
- delegation: A создаёт task- и candidate-worktree, commits, tests/build/GPU; H готовит только некоммиченный evidence package; N выполняет read-only review.
- risks: чистый auto-merge не доказывает semantic parity; task-worktree H нельзя переключать на sync-ветку; GPU barrier blocked чужим Huihui 200k PID 8208; qwen35 delta отсутствует и любое отличие от main после merge является ошибкой.
- acceptance: каждая matrix-строка получает один реальный SHA; D2 содержит candidate-internal evidence; A после N review запускает CPU/static tests, CUDA build, 32k smoke, 160k/200k A/B, quality/MTP/fallback/resources.
- pinned_refs: ours `996eb9195b1790f954dd48f50be27893cae93937`; upstream `2af30ccaa0729177c4725ee2073f72bf550e2f86`; merge-base `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`.
- predicted_tree: `d2d23a55d707d553ecc52e14c7fbe27d0748f993`; текстовых конфликтов нет.
