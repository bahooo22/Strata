# TASK_IDEA Q35-PREFIX-CACHE

- goal: перенести/адаптировать upstream q36 GDN checkpoints и resume-prefix для длинных многоходовых диалогов.
- source: upstream q36 `1687-1764,2274-2335,4952-4983,5092-5119`; текущий fork q36 этих путей не имеет.
- expected_effect: оценка +20–80% TTFT на повторном prefix; отдельный long-dialog сценарий обязателен.
- base_sha: `5fb5f913dd7f63b6b09b5ef9a3e1db9c8414833a`.
- branch: `task/Q35-PREFIX-CACHE`.

## Алгоритм

1. H читает upstream checkpoint/resume contract, текущий session/KV/GDN state и server RESUME protocol.
2. Предложить минимальный перенос без изменения single-prompt 160k/200k path.
3. Сохранить fallback на полный prefill и корректную инвалидацию suffix state.
4. A после утверждения создаёт candidate; N проверяет ownership, lifetime, images/MTP и fallback.

## Приёмка

- Многоходовый диалог с общим system/tools/document prefix, edit/regenerate и branch.
- reused tokens, TTFT, pp/tg, quality, RAM/VRAM, MTP2 и cancel.
- Single-prompt 160k/200k regression gate обязателен.
