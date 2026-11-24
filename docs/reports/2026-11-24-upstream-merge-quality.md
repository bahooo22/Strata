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

MTP2 route-smoke запущен отдельно; его результат в этот quality report не включён и не объявляется passed.

## Waivers / not-applicable

Следующие категории не применяются к данному pre-merge CUDA candidate scope. Они не объявляются passed; в plan используются `not-applicable` с reviewer/date/manualVerdict.

- `backends`: candidate build/profile — CUDA; HIP/SYCL/Metal вне этого merge scope.
- `implementationCombinations`: top-level decision `ours`; matrix не содержит `hybrid`/`delta`, поэтому комбинационная матрица не требуется.
- `bisect`: candidate не promoted в main; bisect процесса merge не выполняется на pre-merge этапе.
- `rollback`: candidate не promoted; откат обеспечивается локальными tags/branches, rollback drill не выполняется.

Reviewer waivers: main `443fddf1-c6a1-4de1-a762-0b61e5ca941c`; date `2026-11-24`; manualVerdict `accepted`.

## Остаётся not-run

GPU correctness, runtime route/fallback, VRAM/RAM resources и полный benchmark matrix, regression, target coverage, MTP2 route-smoke result, повторный semantic review и final acceptance.
