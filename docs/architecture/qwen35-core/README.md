# qwen35 core architecture

База кода: `36e044b045bf18e35e3089a9527fc9c86c57ee88` (post-merge main). Исходники qwen35 идентичны ours `996eb9195b1790f954dd48f50be27893cae93937` и code merge `cc5f3e668ed66cba6cc862ab10e1b6ebc569c2b1`.

## Что покрыто

- 27 классов/structs.
- 237 функций/методов/kernels.
- 300 лексических call edges.
- 659 sourceRef проверок, 0 ошибок.
- 5 Mermaid sources: class map, master interactions, prefill, decode/MTP, session/KV.

## Порядок чтения

1. `core-classes.mmd` — все классы и методы, статические зависимости.
2. `core-interactions.mmd` — мастер-блоксхема runtime-взаимодействий.
3. `prefill-flow.mmd` — prompt/super-chunk/MMQ/streaming/fallback.
4. `decode-mtp-flow.mmd` — decode/batch/MTP/verify/commit.
5. `session-kv-flow.mmd` — ownership и lifetime session state.
6. `evidence.md` — streams, синхронизации, fallback и unknowns.
7. `symbol-index.json` — машиночитаемый индекс с сигнатурами и sourceRefs.

## Ограничения

- Call edges лексические и medium-confidence; runtime dispatch подтверждается banner/metrics/tests.
- MMQ, CPU pool и fused interfaces вне qwen35 требуют отдельного inventory.
- Diagram source — `.mmd`; финальная мастер-схема дополнительно показывается в чате.
- Оценки улучшений находятся в `improvements.md` и не являются замерами.
