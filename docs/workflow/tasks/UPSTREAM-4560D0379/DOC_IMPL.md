# DOC_IMPL UPSTREAM-4560D0379

## Контракт пакета

Пакет не меняет candidate code. Он разделяет независимые ours/upstream решения в общих файлах и фиксирует границы, которые A должен сохранить при sync. Defaults и public API не меняются без отдельного обоснования. Qwen35/q36 якоря сохраняются полностью; upstream qwen35 delta пуст.

## `engine/src/prefill/moe_fused_iq.cu`

- ours владеет format support: IQ4_XS down в `GU256`, `d_covered`, setup/launch и opt-in IQ4_NL gate/up через `STRATA_PF_FUSED_Q4NL`.
- upstream владеет диагностикой: `STRATA_PF_SYNC_DEBUG` и `dbg_sync` после launch.
- Граница: diagnostic wrapper не меняет tensor layout, accumulator policy или dispatch predicate. При выключенном флаге stream sync не выполняется.
- Stream order: preparation → launch → `dbg_sync` (только opt-in) → существующий `ck(cudaGetLastError)`.
- Ownership: буферами по-прежнему владеет `experts_native`; diagnostic helper только читает pointer attributes и не сохраняет указатели.
- Fallback: неподдерживаемая geometry/dtype идёт по прежнему upstream/MMQ пути; ошибка нашей части не должна оставлять частично записанный output.
- Обязательные проверки: numeric parity для IQ4_XS/IQ4_NL, default-off bit parity, `STRATA_PF_SYNC_DEBUG=1` causality, CUDA/HIP build.

## `engine/CMakeLists.txt`

- ours добавляет whole-block parity pairs `q2_K/q4_K`, `q2_K/iq4_xs`, `q3_K/q3_K`, `q2_K/q2_K`, `iq3_xxs/q2_K`, `iq3_s/q2_K`.
- upstream добавляет version 0.1.70, `strata_symbols.cmake`, sm120/draft-rule tests и token-dependent dot-x4 policy.
- Ownership: CMake target/register lifecycle остаётся общим; наши pairs добавляются в существующий `STRATA_NATIVE_EXPERTS` block.
- Инварианты: `STRATA_Q6K_EXPERTS`, `STRATA_NATIVE_EXPERTS`, test geometry `2048x512`, timeout и environment сохраняются.
- Fallback: отключение native experts не должно регистрировать неподдерживаемые pairs.

## `terminal/setup.py`

- ours владеет KAT/Huihui pins, per-model `file`/`hf`, `own_file`, `own_size`, `own_hf` и их launch use sites.
- upstream владеет Ornith, custom-label/run_tag, hardware refresh, DFlash2 и improved setup failure hint.
- Граница: `install_own_path` выбирает официальный pinned file через `own_file`, размер через `own_size`, Hub repo через `own_hf`; upstream custom-build ветка может подменить фактический `gguf` на `_OWN_FIRST`, но не меняет official pin lookup.
- Ownership: пользовательские custom files не перезаписываются и не удаляются; официальный config и custom config имеют разные tags.
- Stream/order здесь не применим; порядок шагов setup: engine → model/vision/drafter → tokenizer → config.
- Fallback: при ошибке DFlash2 модель запускается без drafter; при отсутствии KAT/Huihui pin setup завершается ошибкой, а не использует шаблонное имя.
- Проверки: `test_setup_choices`, custom-label tests, Ornith catalog, KAT/Huihui pinned SHA/size, `check_qwen36_200k_launch.py`.

## `terminal/tools/strata_mcp.py`

- ours владеет одной строкой `own_size`: размер KAT/Huihui берётся из `setup.own_size`.
- upstream владеет stale-ok hardware refresh, custom model fields, Inkling legacy/offered/update metadata.
- Граница: MCP не дублирует pinned size и не вычисляет его по `fam.file`; setup остаётся единственным источником.
- Ownership: hardware cache защищён lock; refresh thread не меняет config files.
- Fallback: старый hardware cache возвращается сразу, refresh failure сохраняет прежний ответ.
- Проверки: MCP model table, own_size parity, hardware TTL/refresh, custom delete keep-files.

## `terminal/strata_control/inkling_fit.py`

- Наш diff — только удаление финальной пустой строки; семантического fork-патча нет.
- Берём upstream 0.2.23 lineup: SQv2-20, GSQ-RCO-IQ3_S, UD-Q4_K_XL, legacy installs и DFlash2 reserve.
- Defaults: предлагаемый lineup меняется upstream; A должен подтвердить это отдельными setup/planner tests, а не считать его ours-оптимизацией.

## Settings register и docs

- Вход: candidate code/env knobs после объединения.
- ours-only записей: 18; upstream-only: 153; общих изменённых: 787.
- `STRATA_Q36_FDEC`, `STRATA_Q36_FDEC_CHECK`, `STRATA_DOWN_SUB8` сохраняются; `STRATA_PF_SYNC_DEBUG` добавляется.
- Output: `terminal/data/settings-register.json` и `docs/SETTINGS.md` генерируются одним проходом `tools/settings_register.py`.
- Запрещено вручную копировать upstream JSON и терять fork entries.

## Документация и packaging

- `AGENTS.md`: upstream version line + ours Workflow v3.
- `README.md`: upstream Ornith/Inkling/release + ours fork notes/charts.
- `tools/packaging/README.md`: upstream version line + ours fork CI/gap notes.
- Ownership текста: факты upstream и факты форка не смешиваются в одну без provenance цифру.

## Qwen35/q36 guard

- upstream delta не трогает `engine/src/qwen35/**`.
- Candidate обязан пройти `git diff --exit-code OURS CANDIDATE -- engine/src/qwen35 engine/include/strata/qwen35`.
- Сохраняются FA/FDEC/expert-cache/P4/super-chunk/staging/copy_session/CLI contracts и 29 ours-only маркеров.
- Любое отличие — blocker, а не повод автоматически принять upstream.

## Combo/runtime acceptance

- upstream-only и ours-only базовые профили; candidate на том же железе и модели.
- 32k smoke, 160k/200k full, MTP on/off, FDEC/staging/fallback, KAT/Huihui, copy_session.
- Correctness: max_abs/cos и quality отдельно от pp/tg.
- Resources: raw token/ms, VRAM/RAM peaks, kernel launches/sync где доступны.
- Defaults: candidate default path должен остаться byte-identical, кроме явно принятых upstream catalog/build changes.

## Rollback

- Откатить только content commit конкретной matrix-строки; не делать force/reset main.
- Сохранить upstream parent и отдельный ours fallback commit.
- При регрессе qwen35, own_size/own_hf, fused dispatch или settings generation остановить candidate и вернуться к oursRef.
