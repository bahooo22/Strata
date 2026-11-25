# IMPL_PLAN CANARY-001

- implementation_algorithm: engine-код не меняется. Сравнить default `STRATA_Q36_READ_WINDOWS=1` и candidate env `STRATA_Q36_READ_WINDOWS=2` на одном профиле KAT IQ4_XS / graph on / q4_0 / MTP0 / super-chunk8 / att256 / reserve512 / FA v2 tile4. Сначала baseline 32k в том же окне, затем candidate 32k ≥3, после этого отдельные full 160k и 200k.
- code_parts: только `docs/workflow/tasks/CANARY-001/experiment-profile.json`; engine patch отсутствует. Параметр читается существующим knob `STRATA_Q36_READ_WINDOWS` в q36 engine.
- delegation: H готовит profile/PATCH/DOC_IMPL; A выполняет прогоны и метрики; N выполняет read-only review C1–C10; self-approval запрещён.
- risks: expected effect не задан; малые pp/tg дельты могут быть шумом; full merge разрешён только при progress на обоих 160k и 200k.
- preflight: model, exe и server-root `C:/Projects/Strata-3060Ti/engine/terminal` существуют; GPU/build/commit/push/merge H не выполнял.
- acceptance: fast 32k — минимум 3 candidate runs и сравнение с same-window baseline; full — отдельные 160k/200k, merge только при progress на обоих; no_change/regress/critical_risk архивируются.
