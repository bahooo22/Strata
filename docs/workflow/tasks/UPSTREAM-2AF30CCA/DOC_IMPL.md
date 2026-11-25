# DOC_IMPL UPSTREAM-2AF30CCA

- math: version bump не меняет вычисления. HIP K/V window планируется как `min(context, 32768)`; RAM slack — `max(0.75 GiB, 5% экспертов)` с ограничением свободной RAM; выбранный K/V тип fp8/fp16 применяется только к HIP.
- code_map: `terminal/setup.py:write_config/write_run_script` создают install folder; `RAM_TIER_SLACK_GIB/FRAC` и `inkling_expert_flags` добавляют HIP RAM room; `HIP_KV_WINDOW_TOKENS`, `non_expert_gb`, `inkling_plan_kv` задают HIP window/type; version files обновляют Control/Terminal версии.
- algorithm_argumentation: upstream setup/HIP fixes изолированы от CUDA/других backend; qwen36 KAT/Huihui, expert build options и fork planner constants сохраняются; qwen35 не входит в delta. H package не меняет engine-код.
