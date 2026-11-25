# N final review — UPSTREAM-2AF30CCA

- Роль: `N`.
- Reviewer: `9ba7a8a6-9973-4bce-8a66-93acde030932`.
- Дата review: `2026-11-25`.
- Время review: `2026-11-25T17:44:15Z` / `2026-11-25T20:44:15+0300`.
- Candidate tip: `36e044b045bf18e35e3089a9527fc9c86c57ee88` (`D5`).
- Parent D4: `f6070dce04d053e268abc8d7e65e2f65f9e59847`.
- Code merge: `cc5f3e668ed66cba6cc862ab10e1b6ebc569c2b1` (`M`).
- Base/ours: `996eb9195b1790f954dd48f50be27893cae93937`.
- Upstream: `2af30ccaa0729177c4725ee2073f72bf550e2f86`.
- Merge-base: `d46f5f268f8ed797e83a5c63a69bffbd7a581cf6`.
- Verdict: `INTEGRATION_APPROVED`.
- Scope: upstream sync candidate D5.
- `MERGED`, commit, push, release и изменение refs не разрешены.

## C1–C10

| Критерий | Результат | Доказательство |
|---|---|---|
| C1 `code==TASK_IDEA/PLAN` | PASS | Code M не изменён; upstream delta — 4 commits/16 files, C1..C5 повторяют upstream, qwen35 и fork-якоря сохранены. D4/D5 docs-only. |
| C2 correctness | PASS | CUDA build rc=0, markers 29/29, hygiene rc=0; static acceptance 21/21 в D5 и post-D5 rerun 30/30; qwen35 source/normalized compile commands/host `.text` идентичны baseline/candidate. |
| C3 security | PASS | Нет новых сетевых входов, shell-вызовов, секретов, прав или dependencies. D5 меняет только docs/evidence; canonical leakcheck в static acceptance rc=0. |
| C4 fallback | PASS | 32k graph и eager fallback rc=0; resource transition FA v2 → barrier → default rc=0; qwen35/runtime/MTP не изменены. |
| C5 `DOC_IMPL==code` | PASS | `DOC_IMPL.md:3-5` соответствует setup/HIP/version hunks; D5 не меняет code. |
| C6 `DOC_IMPL==TASK_IDEA` | PASS | Scope и решения прежние: upstream hotfix, сохранение fork defaults, qwen35 untouched, отдельная runtime acceptance. |
| C7 evidence protocol refs/windows | PASS | Semantic `--run-checks` PASS 7/7, blockers=[], notRun=[], dirtyTreeAfter=false. 47/47 файлов evidence-index и хэшей совпали. Performance пересчитан из сырых token/ms. |
| C8 base/ancestry valid | PASS | Merge-base `d46f5f268`; ours/upstream являются предками D5. `C5=M` tree `d2d23a55…`; D5 tree `2a930d69…`; code diff M→D5 пуст; qwen35 diff пуст. |
| C9 no subagents/delegation recorded | PASS | `participants.json` и TASK_IDEA фиксируют A/H/N; N субагентов не запускал; reviewer независим от codeAuthor. |
| C10 no unapproved dependencies | PASS | Package manifests/lockfiles/CI не изменены; code delta ограничена 16 upstream-файлами; defaults CUDA/other backends сохранены. |

## Шесть architecture-вопросов

1. **Смысл алгоритмов.** PASS: version bump не меняет вычисления; install-folder fix создаёт каталог до записи; HIP RAM slack и HIP KV window/type изолированы в planner.
2. **Ownership/readiness буферов.** PASS: engine buffers/streams/graphs/kernels/ownership не изменены; qwen35 source и host `.text` идентичны.
3. **MTP/детерминизм/fallback.** PASS: MTP2 serve route baseline/candidate drafts `2/4`, ответы одинаковы, rc=0; graph/eager и FA/default fallback приняты.
4. **Независимость частей.** PASS: C1..C5 раздельны, M tree=C5, D4/D5 docs-only.
5. **Цена следующего merge.** PASS: 4 upstream commits/16 files, additive HIP fixes, fork delta локализована.
6. **Отдельная адаптация.** PASS: upstream применён напрямую, дополнительные hybrid/delta адаптации не требуются.

## Performance: независимый пересчёт

Сырые значения вычислены как `prompt_tokens / (prefill_ms / 1000)` и `generated / (gen_ms / 1000)`.

| окно | prompt | baseline pp / tg | candidate pp / tg | Δpp | Δtg | решение |
|---|---:|---:|---:|---:|---:|---|
| 160k | 139299 | 890.669957 / 15.942941 | 888.669856 / 15.797132 | -0.2246% | -0.9146% | `no_change` |
| 200k full | 202665 | 733.050480 / 12.870642 | 733.703326 / 12.484197 | +0.0891% | -3.0025% | вход в ревью с контролем порядка |
| 200k repeat | 202665 | 733.798962 / 12.543665 | 731.054061 / 12.263272 | -0.3741% | -2.2353% | вход в ревью с контролем порядка |
| 200k repeat2, candidate→baseline | 202665 | 734.309442 / 12.456638 | 732.986850 / 12.523779 | -0.1801% | +0.5390% | обратный порядок меняет знак tg |

Итог 200k: raw median tg `-2.24%`, order-adjusted `-1.58%`, обратная пара `+0.54%`. Предупреждение сохранено в `performance.json/.md`, `FULL_RUN_REPORT.md` и plan. Регрессия не подтверждена: знак меняется при обратном порядке, а qwen35 source/compile flags/host `.text` идентичны. Для upstream sync это допустимый `no_confirmed_regression`; оптимизационный `progress` не заявляется.

## Acceptance evidence

- Static: D5 `21/21`, post-D5 `30/30`.
- CUDA: configure/build/hygiene rc=0; markers `29/29`; mutation control rc=1.
- Build identity: normalized compile commands равны; host `.text` равен; source checks rc0; различия ограничены `STRATA_VERSION` и путём к исходникам.
- Smoke: 32k graph/eager rc=0.
- KV q4_0/fdec0: top1 `10/10`, top5 `44/50`, KL `0.0040518743917346` совпал с baseline.
- General hard: `16/22`, failures `cap3/five_words/idiom` совпали с baseline; needle24k PASS.
- MTP2 serve route: baseline/candidate drafts `2/4`, ответ `Контекст получен`, token diff 0, rc=0.
- MTP CLI diagnostic: `0xC0000409` одинаково на baseline/candidate; это не candidate regression, acceptance выполнен штатным serve launcher.
- Resources: FA/default rc=0; samples сохранены; barrier между конфигурациями чист.

## Waivers

| Waiver | Решение | Основание |
|---|---|---|
| `backends` | accepted `not-applicable` | HIP hardware/toolchain отсутствуют; upstream HIP logic покрыта static tests и N review. HIP runtime не заявляется. |
| `implementationCombinations` | accepted `not-applicable` | Upstream-only delta; hybrid/delta combinations отсутствуют. |
| `bisect` | accepted `not-applicable` | Регрессия не подтверждена; qwen35 source/.text identity и обратный A/B. |
| `rollback` | accepted `not-applicable` | Destructive rollback не требуется; promotion планируется ff-only с archive refs. |
| `large-diff-files` | accepted | Полный ours→candidate diff включает 258 fork commits; upstream delta — 4 commits/16 files. |
| `large-diff-lines` | accepted | Историческая fork delta доминирует; новый upstream code delta — 292/24 строки. |
| `global-state` | accepted | Эвристика находит существующие qwen35 constants/functions; qwen35 diff пуст. |
| `copy-paste` | accepted | Эвристика считает весь fork diff; нового copy-paste в upstream delta N не нашёл. |

Все waiver-записи содержат reviewer `9ba7a8a6…`, date `2026-11-25`, `manualVerdict=accepted`, reason/details и evidence revision D5.

## Два несоответствия инструмента: override проверяющего

### 1. Schema ↔ semantic gate: top-level `author`

- Semantic plan содержит `author=443fddf1-c6a1-4de1-a762-0b61e5ca941c`; semantic gate использует его для независимости author/reviewer.
- Canonical schema имеет `additionalProperties=false` и не объявляет `author`; schema gate возвращает только `unknown field author`.
- **Override accepted:** это расхождение metadata-контракта инструмента, не кода или evidence. Reviewer `9ba7a8a6…` независим от codeAuthor `b8bd12b8…`; semantic gate PASS. Schema/tool код не ослаблялся и не менялся.

### 2. Schema ↔ semantic gate: warning code

- Semantic plan использует exact `evidence-not-applicable:implementationCombinations`.
- Schema pattern допускает kebab-case; canonical plan использует alias `evidence-not-applicable:implementation-combinations`.
- **Override accepted:** alias представляет тот же waiver; evidence item, reviewer/date/manualVerdict и reason присутствуют. Проверка `implementationCombinations` не пропущена и не ослаблена.

Оба override закрыты настоящим reviewer-решением. A должен перенести их дословно в финальный promotion/gate log; если инструмент later синхронизирует schema и generator, постоянный fix можно внести отдельно без пересмотра code candidate.

## Ограничения

- HIP runtime не выполнялся; waiver scope-limited и не означает заявленную HIP runtime-совместимость.
- `tools/check` содержит идентичные main/candidate docs links/settings register ошибки; 9 широких шагов not-run из-за отсутствия cmake/pytest/Node/torch. Профильные inkling/setup/release/version tests выполнены rc=0; нового регресса нет.
- Performance warning 200k сохранён и не скрыт.
- Candidate worktree не менялся; commits/refs/build/GPU/tests этим review не выполнялись.

## Итог

`INTEGRATION_APPROVED` для upstream sync `UPSTREAM-2AF30CCA` на D5 `36e044b045bf18e35e3089a9527fc9c86c57ee88`. Код, evidence, performance warning, waivers и два tool override приняты. `MERGED` и публикация остаются отдельным решением A.
