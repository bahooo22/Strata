# Полный routed-expert контракт 10/11/18/21

Дата: 2026-11-24. Статус: **CUDA/non-Q6K candidate принят reviewer; HIP not-run с waiver**.

## Кандидат

- Ветка: `exp/expert-types-full`.
- База candidate: `20f7e077cf582b3a6d4eb65f4659c01a103c1a69`; актуальный main на момент отчёта: `84246fc87e8e9120023d34cdd4403e05ef457653`.
- Итоговый patch: `expert-types-final-q2fix-2026-11-24.patch`.
- SHA-256 patch: `017d562152e87600fa422887f95db2f32b490c922e20496cfc193eec9ca33b7a`.
- Diff: 9 файлов, `+233/-53`.
- Стенд: RTX 3060 Ti 8 GiB, RAM 32 GiB, Windows 11, CUDA 13.3, MSVC 14.51.

## Что изменено

- `Q3_K`: upstream `q3_k_scale_at`, `vec_dot_q3_K_q8_1`, `Fmt<11>` ipb=8 и `Split<11>`; тип добавлен в GU/down/MMVQ/fused dispatch.
- `Q2_K`: сохранён локальный `Fmt<10>` ipb=16; исправлены safe load, dot и `Split<10>`; тип добавлен в down/fused dispatch.
- `IQ3_XXS`/`IQ3_S`: добавлены в down и LDS/sub16; fused GU получил staging/sign masks для IQ3_XXS.
- Python-зеркала `q36_types.py` и `qwen4_intake.py` синхронизированы с CUDA/HIP macros; `VECTOR` дополнен IQ4_NL.
- Тесты: grouped-матрица 4×4 на 2048×512, MMVQ 10/11, sm120 shifted pairs, четыре synthetic CTest и `down_sub8_off`.

## Найденные и исправленные дефекты candidate

1. CUDA compile: `Split<10>::W::sc` был `int[]`, параметр dot — `const uint8_t*`; тип исправлен на `uint8_t`.
2. GPU parity: локальный Q2_K dot читал четыре q8_1 блока на один вызов. Исправлена карта ipb=16:
   - `half=iqs>>3`, `j=(iqs>>1)&3`, `second=iqs&1`;
   - weight `qs+32*half+16*second`, shift `2*j`;
   - scale `scales[iqs]`;
   - q8 block `iqs>>1`, words `4*second..4*second+3`.
3. CPU-проверка карты: 100 случайных блоков, 0 расхождений с dequant-reference.

## Evidence

| Проверка | Результат |
|---|---|
| Static contract | 27/27, violations 0 |
| Python mirror | rc=0 |
| `qwen4_intake` | 32 tests: candidate 2 старых SYCL/MMVQ failures, main 3; новая CUDA/HIP mismatch исправлена, новых failures нет |
| CUDA build | rc=0 |
| Новые CTest | 5/5 PASS |
| grouped default | rc=0 |
| grouped `STRATA_DOWN_SUB8=0/1` | rc=0 / rc=0 |
| grouped `STRATA_EXP_MODE=0` | rc=0 |
| grouped `STRATA_EXP_MODE=8` | те же 768 failures и 49 IQ4_XS/IQ4_NL failures, что baseline; новые пары bitwise equal |
| `iq_multi_parity` | rc=0, Q2_K/Q3_K bitwise old kernel |
| `STRATA_KQ_SPLIT=1 iq_multi_parity` | rc=0 |
| `nvfp4_decode_sm120_test` | skip rc=77: нужен Blackwell sm_120a/sm_121a |
| HIP compile | not-run: configure остановился `Failed to find HIP root directory`; hipcc/ROCm/clang++ отсутствуют |
| non-Q6K compile | rc=0 |
| non-Q6K runtime | CTest 5/5, grouped default и MMVQ default rc=0 |

## Ограничения

- Полный `test_q36_types` даёт 10/11 OK и один старый drift каталога `IQ4_XS-KAT/Huihui` против `q36_types.SIZES`; он не входит в пакет.
- `qwen4_intake` unit не запускался: в системном Python нет `numpy`; CUDA/HIP таблицы проверены static contract.
- Mode8 IQ4_XS/IQ4_NL — подтверждённый baseline-дефект, не regression пакета.
- Independent final review `3568a3e2`, 2026-11-24: APPROVE текущего patch `017d5621` как CUDA/non-Q6K candidate. Non-Q6 build/runtime выполнены; HIP configure не прошёл из-за отсутствующего root, HIP WAIVER GRANTED только для этого patch.

## Следующие gates

1. Commit candidate, rebase на актуальный main, `--ff-only`, push main.
2. Quality/MTP smoke на финальном binary.
3. Portable final остаётся последним GPU-этапом.
4. При появлении HIP toolchain выполнить отдельную compile/runtime приёмку.
