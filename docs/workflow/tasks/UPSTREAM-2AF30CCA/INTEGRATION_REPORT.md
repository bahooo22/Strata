# INTEGRATION_REPORT

- fast_32k_dynamics: candidate graph и eager fallback rc=0.
- full_160k_dynamics: одна пара, Δpp/Δtg в пределах шума 1.5%.
- full_200k_dynamics: три пары, включая обратный порядок; регрессия не подтверждена, предупреждение сохранено.
- quality_general_32k: 16/22; baseline 16/22; needle24k PASS.
- kv_quality_q4_0_fdec0: top-1 10/10, top-5 44/50.
- mtp2: accepted base/test ['baseline 2/4', 'candidate 2/4']; token diff 0.
- resources_32k: FA rc=0, default rc=0.
- verdict: INTEGRATION_APPROVED.
- limitations: HIP not-run; `tools/check` имеет идентичные main/candidate baseline docs-ошибки и not-run шаги; MTP CLI diagnostic упал одинаково на baseline/candidate, поэтому принятие использован штатный serve launcher.
