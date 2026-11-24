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

Waivers accepted:

- `backends` и `implementationCombinations`: analyst `3568a3e2-cc53-4e0e-9673-b35d1dfbbca6`, date `2026-11-24`, manualVerdict `accepted`;
- `bisect` и `rollback`: main `443fddf1-c6a1-4de1-a762-0b61e5ca941c`, date `2026-11-24`, manualVerdict `accepted` (`main-process-waivers-2026-11-24.json`).

Exact warning `evidence-not-applicable:implementationCombinations` не записывается в `warningAcknowledgments` из-за schema pattern с camelCase; waiver decision сохранена в evidence item и main waiver file.

## Остаётся not-run / pending

Повторный semantic review и final acceptance — pending. Structured measured evidence покрывает correctness/quality/route/fallback/benchmarksResources/regression/targetCoverage; fallback/resource raw logs находятся в `fallback-resource-32k/`.
