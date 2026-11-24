# Upstream-merge candidate: quality evidence и waivers

Дата: 2026-11-24. Code candidate: `65ec7c975f39fc4edb4c3c7f446a5e60e3114247`.

## Quality: passed

General hard suite 32k выполнен через candidate server и candidate exe:

- rc=0;
- weighted score 16/22 = 72.7%;
- needle24k PASS, ответ `ЛАМПА`;
- failures: `cap3`, `idiom`, `five_words` — те же, что в эталонном smoke;
- raw JSONL: `E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-24_session/upstream-merge-prep/quality-32k/upstream-merge-raw.jsonl`;
- engine log: `E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-24_session/upstream-merge-prep/quality-32k/upstream-merge-kat-iq4xs-general.log`.

Score пересчитан из raw JSONL: сумма weights passed=16, total=22, rate=0.727. `git diff --check` остаётся formatting/static evidence и не используется как quality.

MTP2 diagnostic route-smoke завершён rc=0: 32k, prompt 29242, pp1136.5, tg27.0, answer `Контекст загружен`, drafts accepted 3/4. Лог: `E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-24_session/upstream-merge-prep/mtp2-route-32k.log`. Это diagnostic route smoke, не рабочий performance claim и не полная runtime route/fallback приёмка.

## Waivers / not-applicable

Следующие категории предложены как not-applicable для данного pre-merge CUDA candidate scope, но ещё не приняты. В plan они остаются not-run до reviewer/date/manualVerdict аналитика.

- `backends`: candidate build/profile — CUDA; HIP/SYCL/Metal вне этого merge scope.
- `implementationCombinations`: top-level decision `ours`; matrix не содержит `hybrid`/`delta`, поэтому комбинационная матрица не требуется.
- `bisect`: candidate не promoted в main; bisect процесса merge не выполняется на pre-merge этапе.
- `rollback`: candidate не promoted; откат обеспечивается локальными tags/branches, rollback drill не выполняется.

Reviewer waivers: pending аналитик `3568a3e2-cc53-4e0e-9673-b35d1dfbbca6`; date/manualVerdict будут заполнены только после его решения.

## Остаётся not-run / pending

`backends`, `bisect`, `rollback`, `implementationCombinations` — waiver pending; повторный semantic review и final acceptance — pending. Structured measured evidence покрывает correctness/quality/route/fallback/benchmarksResources/regression/targetCoverage для перечисленных профилей.
