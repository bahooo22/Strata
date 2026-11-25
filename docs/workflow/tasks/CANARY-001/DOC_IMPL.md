# DOC_IMPL CANARY-001

- math: изменяемый параметр — целое число decode windows между двумя prompt chunks. Это не изменение математики attention/experts; сравнение производится по pp/tg на одинаковых model/prompt/window/profile. Для 32k используется median и spread минимум трёх candidate runs.
- code_map: `engine/src/qwen35/q36_engine.cu` — knob `--read-windows` / `STRATA_Q36_READ_WINDOWS`, разрешение значения в `Engine::init`, цикл `window()` между prompt chunks. Engine-код candidate не изменяется.
- algorithm_argumentation: env 2 может изменить interleaving decode окон и латентность полного prompt, но ожидаемый эффект заранее неизвестен. Изолируется одна переменная; default 1 и env 2 сравниваются только в одинаковых окнах и профилях. Fallback/default semantics сохраняются.
