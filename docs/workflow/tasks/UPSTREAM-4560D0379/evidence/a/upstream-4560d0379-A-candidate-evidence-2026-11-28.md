# UPSTREAM-4560D0379 — A candidate evidence

Дата: 2026-11-28. Candidate tip: `2195f9b0f412d7e1f5447dad82a657e4db6904cc`; runtime/build HEAD совпадает с tip, docs-only closure будет отдельным commit.

## Build

- Clean build `b18taaofd`: configure `rc=0`, build `rc=0` за 1196 с.
- Executable `F:/tmp/upstream-0.2.23-build/strata-q36.exe`, SHA-256 `0da6657819dd13939982eb520cf68c0fb2f70a592c480c6853ba9e4ddf1d22b4`.
- Hygiene `rc=0`; markers 29/29, пропавших 0; mutation control сработал.
- Первый запуск `b9ork8gjz` отклонён до сборки из-за отсутствующего stale default PinCache; повтор использовал явный `F:/tmp/q35-route-selector-build/CMakeCache.txt` и отдельный log prefix.

## Static/tests

- Qwen35 parity к main: diff пуст.
- Reverse patch-check: PASS.
- Ours-only markers: 29/29.
- Settings register: 1445 записей, 18 ours-only + 153 upstream-only, `--check` PASS.
- Scoped whitespace gate: PASS; raw diffs исключены как byte-preserving evidence.
- Targeted unittest: `Ran 86 tests`, `OK (skipped=2)`.
- Baseline main имел те же три failures в setup/MCP tests; candidate fix `2195f9b0f` адаптировал tests и добавил KAT/Huihui `context_fit`.

## Baseline blockers

- `check_qwen36_200k_launch.py` одинаково падает на main/candidate из-за отсутствующих локальных tokenizer; это внешний стенд, не регрессия merge.
- `check_links.py` одинаково падает на main/candidate для `packaging/kit/README.en.md` и `.github/workflows/docker-images.yml`.
- `tools/check --strict` не может выполнить cmake/pytest/torch/Node steps в текущем окружении; docs failure совпадает с main.

## Metadata/N

- H metadata closure: candidateRef `2195f9b0f`, 34 matrix rows, pending commitRefs 0, evidence index 80/80.
- Closure schema PASS; candidate anchor matrix 34 строки `readyForPlan=true`; canonical leakcheck PASS.
- N package verdict `APPROVED_UPSTREAM_4560D0379_PACKAGE`, SHA-256 `bfbe2871ef9fdcc31c459534fe1085bcafb3d2b0ec86094794070a725de5dd94`.

## Не запускалось

CUDA runtime/GPU, C++ tests, semantic merge-gate, main merge и push. Candidate acceptance остаётся pending до этих этапов и N candidate review.
