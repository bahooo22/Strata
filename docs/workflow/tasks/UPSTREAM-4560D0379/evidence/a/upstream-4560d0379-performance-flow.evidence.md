# UPSTREAM-4560D0379 — performance-flow evidence

Дата: 2026-11-28. Scenario skill: `flow-visualizer`; формат: Mermaid. Вопрос: где может возникать разница baseline/candidate, если upstream не менял `engine/src/qwen35/**`.

Диаграмма: [upstream-4560d0379-performance-flow.mmd](upstream-4560d0379-performance-flow.mmd).

## Подтверждённые факты

| Факт | Evidence | Confidence |
|---|---|---|
| Baseline main `34bd46b86`, candidate runtime/build HEAD `2195f9b0f`, docs-only review tip `58ac34a62` | `upstream-4560d0379-candidate-merge-result-2026-11-28.json`, `msg-58ac34a62.txt` | high |
| Upstream `4560d0379` не менял `engine/src/qwen35/**` | `UPSTREAM-4560D0379-PREFLIGHT-2026-11-28.md`; `git diff --name-only 2af30cca..4560d0379 -- engine/src/qwen35` пуст | high |
| Upstream изменил shared engine/build paths, включая `prefill/moe_fused_iq.cu`, CMake, expert source, artifact reader, dot-x4 policy | preflight overlap list; H `DOC_IMPL.md:7-16,65-70` | high |
| Baseline и candidate exe различны | baseline SHA `abde197a…`, candidate SHA `0da66578…`; build identity | high |
| 32k profile/env/prompt tokens идентичны | `32k-*.engine-config.json`; engine logs: 11242 prompt tokens, 64 generated | high |
| 32k exact answer parity | все четыре `contentSha256` равны `bd0b78ad…` | high |
| 160k exact answer parity | все четыре `contentSha256` равны `b5b05d2f…` | high |
| Первая 200k серия невалидна | `upstream-4560d0379-runtime-200k-short-master/README.md`; master содержал 430080 chars | high |

## Измерения

| Окно | Baseline pp/tg | Candidate pp/tg | Δ median | Tokens | Статус |
|---|---:|---:|---:|---:|---|
| 32k | 1551.05 / 23.55 | 1518.75 / 22.50 | pp -2.082%, tg -4.459% | 64 | 2 runs/side, exact parity |
| 160k | 908.35 / 16.30 | 908.05 / 16.30 | pp -0.033%, tg 0.000% | 256 | 2 runs/side, exact parity |
| 200k | — | — | — | 256 | истинный prompt 616000 chars, выполняется |

Raw: `upstream-4560d0379-runtime/summary.json`, `ledger.jsonl`, `*.engine.log`, `*.answer.json`, `*.resources.json`.

## Карта изменений

1. **Terminal/server** — upstream менял request handling, custom models, settings и packaging. Для 32k profile/env и prompt tokens совпали, поэтому это менее вероятная причина engine pp/tg, но остаётся зоной проверки.
2. **qwen35 engine source** — подтверждённо идентичен. Алгоритмическая регрессия внутри `q36_engine.cu` маловероятна без wrapper/build эффекта.
3. **Shared prefill/build** — изменён upstream; главная гипотеза для небольшого устойчивого сдвига.
4. **CUDA kernels/link layout** — бинарники разные; одинаковый source не гарантирует одинаковый link/layout/оптимизацию.
5. **Стенд/шум** — 32k имеет всего две точки на side; thermal, clocks, pagefile и host cache не контролировались достаточно.

## Гипотезы и следующие проверки

| ID | Гипотеза | Confidence | Проверка |
|---|---|---|---|
| H1 | 32k delta — шум/thermal/state | medium | repeat 32k 3+3, clock/temperature snapshot |
| H2 | shared prefill/build/link | medium | сравнить compile/link maps и горячие shared symbols; perf trace при повторении |
| H3 | server/tokenizer/profile | low | configs и prompt tokens уже совпали; проверить request timing отдельно |
| H4 | qwen35 algorithm regression | low | source diff пуст; требуется доказательство wrapper/shared path |
| H5 | harness/measurement defect | low | parser уже исправлен; невалидная 200k серия исключена |

## Ограничения

- Настоящий 200k AB/BA ещё выполняется.
- Нет profiler trace, инструкционного счётчика или link-map diff.
- 32k decode — 64 токенов; это диагностика, не окончательный speed verdict.
- Диаграмма локализует гипотезы, но не доказывает первопричину.
