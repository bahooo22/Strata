# UPSTREAM-4560D0379 — metadata corrections after N review

Дата: 2026-11-28.
Review base: `94f2e6c190982ccc76187f274d635f118ffb3b67`.
N verdict: `BLOCKED`; отчёт сохранён как `evidence/a/N-upstream-4560d0379-blocked-review.md`.

## Исправления

1. Финальный merge plan больше не использует H-draft row metadata как candidate acceptance: `contract.errorBehavior`, `coverage`, `resources`, `route.verified` и candidate evidence обновлены до реального build/runtime состояния.
2. `settings-upstream-register.route.candidate` указывает на реальный `STRATA_PF_SYNC_DEBUG` anchor в `engine/src/prefill/moe_fused_iq.cu:76`.
3. GPU parity summary исправлен по raw CTest: 87 tests, 85 passed, 2 skipped, 1 failed. Skipped: `#303 prefill_fused_iq_test_sm75`, `#306 prefill_fused_iq_test_ws`; failure `#300 prefill_fused_q36_test` baseline-identical.
4. Warning acknowledgments и N-A manual verdicts будут записаны в финальный внешний plan после повторного N approval.

## Проверки

- Raw CTest: `upstream-4560d0379-gpu-parity-ctest.log:14,20,184-186`.
- Code/runtime delta не менялся; GPU rerun не требуется.
- Main merge/push не выполнялись.
