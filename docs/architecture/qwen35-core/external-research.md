# Внешнее исследование: MoE offload/prefetch/overlap

Дата: 2026-11-25. Источники — первичные статьи, RFC/issues и документация. Проценты внешних систем не переносятся на RTX 3060 Ti без собственного A/B.

## AdaOffload — Multi-GPU MoE Inference with Adaptive Expert Offloading

- URL: https://arxiv.org/html/2611.10219v1
- Механизм: offline cost model по expert-token load `L` и unique experts `U`; online async instrumented policy selection; decode выбирает долю cache-miss экспертов для fetch против CPU; prefill переключается между next-layer full prefetch и hybrid.
- Наблюдения: adaptive policy достигает 94.8%/99.2% лучшего fixed policy при concurrency 1/8; prefill switch около 128–400 tokens зависит от hardware; instrumentation стоит 1.3–6.6%.
- Применимо: обоснование adaptive super-chunk/stream policy и expert-slot policy по реальным `L/U`, а не фиксированным every32/max8.
- Не применимо напрямую: multi-GPU HTP/NUMA и модели 284B–753B; проценты 1.9–15.5× не являются оценкой для нашей 35B/8 GiB конфигурации.

## SGLang RFC #50336 — Multi-GPU Partial Expert Offload

- URL: https://github.com/sgl-project/sglang/issues/50336
- Механизм: Paged Experts, GPU slots, host experts, exact fallback; обсуждаются copy-engine transfers, frequency hot set + LRU, cross-layer prefetch и graph-safe lifetime.
- Наблюдения: decode-only frequency selection снизила cold-expert activation с 15.6→12.2% и 16.0→14.4%; prefetch на 1/2 слоя вперёд успевал вовремя в 77%/94%, но реально использовался в 47%/44%; увеличение prefetch 8/8→16/12 замедлило throughput примерно на 10%.
- Применимо: адаптивная residency политика, метрики arrival/use/bytes/displacement, double-buffer depth и обязательный exact fallback.
- Ограничение: RFC и исторические измерения custom eight-B200 стека, не upstream implementation и не single-GPU benchmark.

## llama.cpp issue #29949 — GPU-resident LRU inside compute graph

- URL: https://github.com/ggml-org/llama.cpp/issues/29949
- Механизм: рабочая реализация в commit `c81901a57`; `LRU_DECIDE` читает router ids и обновляет LRU на GPU, `LRU_FILL` грузит pinned host experts в slots; нет per-step D2H readback expert ids.
- Наблюдения автора: 9.7→37–50 t/s на 24 GiB 7900 XTX, hit 66.9–96%; perplexity 1.4290→1.4292; greedy 12/12 deterministic.
- Применимо: device-side route metadata и graph-safe expert cache; подтверждает направление удаления host sync.
- Ограничение: issue open, реализация не merged; другие GPU/модель/кванты; проценты не переносить.

## vLLM issue #41447 — MoE Active Expert Management

- URL: https://github.com/vllm-project/vllm/issues/41447
- Механизм proposal: fixed GPU expert slots, dynamic `expert_to_slot`, LRU/frequency eviction, hot expert cache.
- Статус: closed `NOT_PLANED`/stale; demo repo, часть конфигураций падает на cache startup.
- Применимо: только как описание контракта slot mapping; не как доказательство принятой реализации или скорости.

## Megatron Core GTP — prefetch chain + ticket buffer cache

- URL: https://docs.nvidia.com/megatron-core/developer-guide/0.19.2/apidocs/core/core.tensor_parallel.generalized_tensor_parallelism.html
- Механизм: per-weight prefetch chains, ticket-based buffer pool, отдельные GRAPHED/UNGRAPHED chains и streams, ownership/lifetime guards.
- Применимо: проектирование stream depth и staging buffer reuse без late-write/use-after-free; graph capture/replay safety.
- Ограничение: training/GTP all-gather, не inference expert offload.

## NVIDIA CUDA guidance

- URL: https://docs.nvidia.com/cuda/archive/13.4.1/pdf/CUDA_C_Best_Practices_Guide.pdf
- URL: https://docs.nvidia.com/deeplearning/tensorrt/10.x.x/performance/measurement-techniques.html
- Применимо: разделять transfer/compute/wait, использовать events и streams, измерять end-to-end, а не изолированный copy; busy-wait допустим только при доказанном выигрыше и контроле CPU.

## Вывод для пяти гипотез

1. Device-side metadata имеет сильную внешнюю поддержку и убирает реальный host sync в нашем MMQ prompt path.
2. Adaptive residency/prefetch должен использовать runtime `L/U`, arrival/use и exact fallback; внешние данные предупреждают о регрессии от чрезмерного prefetch.
3. Stream depth/super-chunk надо оценивать совместно с VRAM/KV budget и end-to-end, не по copy benchmark.
4. Busy-wait не автоматически плох: AdaOffload использует spin polling для CPU worker tails, но это отдельный контур; наш `cudaEventQuery` надо мерить отдельно.
5. Все внешние проценты — ориентиры для механизма, не прогноз для Strata.
