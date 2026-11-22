# CI: Kit build на 0.2.19 + наши патчи (23.11)

Итог: **SUCCESS**, run 45079366259, коммит `d3db2dc20`.

Прогоны и починки по порядку:

| run | шаг | итог | причина | фикс |
|---|---|---|---|---|
| 45075439888 | selftest | FAIL | TextGate: относительный `-KitSrc` не совпадал с абсолютными префиксами (Checked=0) | `59b28a62b` |
| 45076067657 | selftest | FAIL | `commits_with_marker` 12 вместо 16 | `87b6ccd14` |
| 45077097455 | сборка | FAIL | сборка в `strata/engine/build-kit`, workflow искал `strata/build-kit` | `6ad8df8d7` |
| 45078379455 | сборка | FAIL | 2 устаревших маркера MTP/MMQ 0.2.16 (апстрим 0.2.19 переписал путь) | `d3db2dc20` |
| **45079366259** | всё | **SUCCESS** | selftest + сборка + маркеры | — |

Изменения в реестре маркеров (Q3.2): base c6f6427d9, head 57944d38e, 166 наших немержевых
коммитов, 27 маркеров после удаления двух устаревших; selftest `patch_markers` 44/44.
Дополнительно в этой серии: правило доливайки `serve/server_parts` (0.2.19), отпуск
`engine_component.py` (C:\Windows в docstring/фолбэке Hyper-V), `-RepoSrc strata\terminal`.
