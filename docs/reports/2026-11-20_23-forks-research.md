# Форки Strata: разведка внешних решений (Q0.1)

Дата: 2026-11-22. Клоны: `G:\Research\forks\` (`git clone --depth 1`). Все — MIT, кроме XeStrata (LGPL-3.0-or-later + MIT на унаследованное).
Наш кейс: одна RTX 3060 Ti 8 ГБ, 32 ГБ RAM, Windows, форк 0.2.18, Qwen3.6-35B-A3B IQ4_XS.

| форк | активность | что даёт (конкретно) | лицензия | берём/нет |
|---|---|---|---|---|
| **XeStrata** (MistVVK) | 2026-10-30, апстрим 0.2.8 | Перепис CUDA→SYCL/L0 (Intel Arc, AMD RDNA2+, NVIDIA через contrib-llvm); XMX/WMMA-блоки; «experimental speed projection» (меняет ответы); low-RAM mode | LGPL-3.0-or-later + MIT | **1/5** — к CUDA неприменим, LGPL не даёт влить правки обратно |
| **Strata-V100** (jmnargi) | 2026-11-21, v0.1.45.8…13 | Volta sm_70; FP16-экспертный prefill `STRATA_PF_WMMA` (+8,6…19,7 % prompt 2K–64K); int8 KV; streamed KV; **фикс Q5_0 expert-dot** (err 2,4–3,2e-2 → 1,25–1,3e-2); методика A-B-A-B | MIT | **2/5** — база 0.1.45; взять Q5_0-фикс, если гоним Q5_0-паки |
| **Lamina** (eddoursul) | 2026-11-21, живой | Свой движок 0.3.2 RTX 30/40/50: доп. GPU как экспертные тиры + **адаптивный тир с decay и префетчем экспертов след. слоя**; verify-windows (CPU/GPU/тиры параллельно); **свой MTP-драфт 0,8 ГБ, дообученный на выходе движка**; `--prompt-split`, `--hc-q8` (−50 % VRAM), `--kv int8/k8v4/q4_0`, `--kv-grow`; 35B-A3B ~22 ГБ RAM на одной карте; Windows-бинарники | MIT | **4/5** — ближе всех к нашему кейсу |
| **CacheKV-kinoyu** | 2026-11-22, мержит 0.2.19 | KV+состояние диалогов на SSD: RAM-first, вытеснение >60k токенов, кэп 12 ГиБ, восстановление по префиксу, `--conversation-cache-persist`, детект порчи; prefill 62k **36,2 с → 2,5–4,2 с** | MIT | **3/5** — идея наша, но диск-тир только Linux |
| **4gbVramStrata** (RandoTeam) | 2026-11-21, CI Windows 36 тестов | Движок `src/fourgbvram` (0.1.45-poly.10): GGUF mmap, эксперты в page-cache, слоты горячих на GPU; замер **4 ГБ + 32 ГБ DDR4**: Clover 43,2 tok/s decode / 546 prefill; 8-бит KV; `--vram-reserve-mib`; quality gate 22 промпта + SHA-256 | MIT | **3/5** — единственный мерил «мало VRAM + 32 ГБ RAM» |
| **StrataPool** (fragtion) | 2026-11-22, 0.1.64 | Слой-сплит по TCP между ПК (+25–30 % на паре 3060 12GB+5060 8GB); parked conversations; несёт невлитые PR (PLE page cache 45x read amplification, IQ1_M AVX2); **Windows-находка: при 770 МиБ свободной VRAM Windows спиллит VRAM в RAM — 168K prefill 1100→500 tok/s** | MIT | **2/5** — для одной карты не нужен; забрать находку про reserve и PR по одному |
| **StrataGP** (gputier) | 2026-11-15 | **Пустышка с 2026-10-17: кода нет** (diff v0.1.45..main = docs/FORK.md). Журнал PR и отрицательных результатов: scale-pack MTP accept 0,660→0,648 (шум); `STRATA_PF_FUSED` +7,5…17,5 % prefill, но другие токены KL 6,9e-5 | MIT | **1/5** — только «чего не делать» |
| **lighttransport/Strata** | 2026-11-20, 0.1.57 | `strata-glm` (GLM-5.3 321B) и `strata-m3`: Q23-квант + REAP-прунинг (224/288→95 ГБ); **streamed prefill +50 %**; **`--kv-host`**: FP8 K/V в host-RAM + VRAM block-cache, 256–512K контекст (12,8 tok/s @128K на V100 32 ГБ); `--speed max` (top-2, VRAM-эксперты, 56 vs 23–28 tok/s, качество 36–39/46 vs 41/46); Vulkan-раннер; свой замер 320B @8 ГБ VRAM = 0,30 tok/s | MIT | **2/5** — модели недоступны; забрать идеи KV-host, streamed prefill, speed-тиры |

## Идеи, достойные проверки у нас

1. **Lamina: префетч экспертов слоя i+1 с decay-тиром** — пересекается с нашим A6 (Q2) и D1 для MAP. Добавить decay вместо чистого LRU в A6.
2. **Lamina: MTP-драфт 0,8 ГБ, дообученный на выходе движка** — у нас MTP выключен на 0.2.18 из-за цены VRAM; маленький тюненый драфт может изменить расклад.
3. **Lamina `--hc-q8` + int8/k8v4 KV** — освободить VRAM под слоты экспертов (≈1000 экспертов на 1 ГиБ).
4. **CacheKV: парковка длинных диалогов на SSD** (порог 60k, LRU, persist) — снять Linux-only ограничение. Кандидат в Q2/Q7, после A-серии.
5. **StrataPool: держать VRAM-reserve ≥1 ГБ** при дисплее на 3060 Ti — иначе Windows спиллит VRAM и prefill падает вдвое. Проверить нашу границу reserve.
6. **4gbVram: арифметика «влезет/не влезет» для установщика** (dense + KV + MiB/эксперт), quality gate 22 промпта + SHA движка перед мержем — кандидаты в kit/recommend и CI (Q3/Q4).
7. **lighttransport: streamed prefill** (догрузка экспертов перекрывается вычислением) — у нас prefill упирается в PCIe/RAM; идея пересекается с A3/A6, учесть порядок.
8. **lighttransport: `--kv-host` (FP8 K/V в host-RAM)** — путь к 256–512K на 8 ГБ VRAM; дорого по сложности, только после FA v2.
9. **V100: фикс Q5_0 expert-dot** — применим, если пойдут Unsloth-паки с Q5_0 down; KAT/Huihui IQ4_XS не затронуты.
10. **XeStrata low-RAM mode** (нехватку RAM добирает VRAM) — у нас обратная полярность (гибрид уже есть), пропускаем.

Важное: LGPL XeStrata — правки в его файлы нельзя влить в MIT-дерево; идеи читать можно, код — нет.
