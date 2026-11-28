# UPSTREAM-4560D0379 — candidate rereview

Дата: 2026-11-28.
Роль: N.
Вердикт: `APPROVED_UPSTREAM_4560D0379_CANDIDATE`.
Main merge/push: запрещены.

## Refs

- Предыдущий review HEAD: `94f2e6c190982ccc76187f274d635f118ffb3b67`.
- Новый immutable HEAD: `b689b2c2db7222b3d77d0173e11b42e6775fdb44`.
- Runtime/build code HEAD: `2195f9b0f412d7e1f5447dad82a657e4db6904cc`.
- Финальный plan SHA-256: `c5d15adfac50708a4d7898d4df1eac89cd793d474c63931076dc8bc0bba217e9`.
- Delta `94f2e6c19..b689b2c2d`: 4 docs/evidence файла, `+174/-3`; code/runtime delta пуст.

## Закрытие блокеров

1. **Stale H-draft metadata — CLOSED.** Во всех 34 rows отсутствуют `Кандидат ещё не создан`, `Candidate build/runtime coverage not-run` и `route.verified=false`. Coverage: 23 `measured`, 11 `declared`; resources: 23 `partial`, 11 `not-measured` с явным docs/workflow scope.
2. **Неверный settings anchor — CLOSED.** `settings-upstream-register.route.candidate` теперь `b689b2c2d:engine/src/prefill/moe_fused_iq.cu:76`. Повторная проверка всех 102 ours/upstream/candidate anchor locations: 0 расхождений.
3. **GPU parity skipped count — CLOSED.** `RUNTIME-ACCEPTANCE.md:21` и session static summary теперь указывают 87 tests, 85 passed, 2 skipped (`#303`, `#306`), 1 baseline-identical failure (`#300`), что совпадает с raw CTest.

## Индекс и gate

- Evidence index: 398 уникальных записей; working tree и Git blobs HEAD совпали 398/398 по SHA/size.
- Corrected semantic gate: trusted checks 3/3 PASS, HEAD/tree не изменились.
- Все 9 warnings имеют `outcome=accepted` и reviewer N.
- `bisect`, `implementationCombinations`, `rollback` имеют `manualVerdict=accepted`, status `not-applicable`, reviewer N и revision `b689b2c2d`.
- Единственные оставшиеся gate blockers — pending architecture review fields. Этот отчёт является независимым architecture verdict N.

Принятые warning codes: `copy-paste`, `global-state`, `ifdef-growth`, `large-diff-files`, `large-diff-lines`, `offset-coupling`, `evidence-not-applicable:bisect`, `evidence-not-applicable:implementation-combinations`, `evidence-not-applicable:rollback`.

N-A категории: `bisect` — `not-applicable`, `implementationCombinations` — `not-applicable`, `rollback` — `not-applicable` для pre-merge gate.

## Architecture verdict

1. Upstream algorithms соответствуют реальному коду `4560d0379`.
2. Ownership/state boundaries описаны; наш adaptation engine source не меняет.
3. MTP2, exact answer parity и cuBLAS fallback подтверждены runtime.
4. Ours/upstream части разделены matrix rows; hybrid/delta не заявлены.
5. Стоимость следующего merge ограничена qwen35 byte parity, 29 markers и минимальным adaptation patch.
6. Альтернативы `copy-upstream-tree` и `ours-only` отклонены обоснованно.

Новых противоречий в исправленном package не обнаружено. `APPROVED_UPSTREAM_4560D0379_CANDIDATE` не разрешает main merge/push; A должен записать этот architecture verdict в финальный plan и повторить gate перед отдельным решением о merge.

## Ограничения проверки

Commits/tests/build/GPU/merge/push/subagents не запускались. Candidate и main не изменялись; записан только этот отчёт.
