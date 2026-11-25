# DECISION_RECORD

- decision: `ARCHIVED`
- reason: пользователь установил порог 5%; ожидаемый эффект #4 составляет +1–3% pp, поэтому эксперимент исключён до реализации.
- evidence: H package 9/9, JSON/leakcheck/apply --check PASS; `docs/architecture/qwen35-core/improvements.md`; raw report `glm/2026-11-25_session/mmq-device-metadata/h-package-report.json`.
- feedback: code/build/GPU/commits в эксперименте не выполнялись; carrier-выбор отменён как ненужный. Следующий candidate — #2 adaptive super-chunk с приёмкой ≥5% end-to-end.
