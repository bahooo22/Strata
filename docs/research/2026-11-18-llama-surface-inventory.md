# What Strata actually compiles out of llama.cpp (measured 2026-11-18)

Why: the MMQ port verdict needs a number, not a feeling. "The head mostly does not matter"
is only usable if the three dependency surfaces are counted and can be re-counted.

Measure: `glm/scripts/strata_llama_surface_inventory_2026-11-18.py` (selftest: 9 checks).
It reads `compile_commands.json` of each build tree - that file lists exactly the translation
units the build put to work - and classifies every unit by path prefix against two roots:
the engine root and `STRATA_GGML_DIR` from the same `CMakeCache.txt`. Anything outside both
roots aborts the measure instead of being silently bucketed.

Trees compared:

| | pin (`3cf03257f`) | new head (`llama.cpp` master) |
|---|---|---|
| tree | `F:\tmp\sync1622-build-strata` | `C:\Projects\Strata-3060Ti\engine-v2\build-api-v2` |
| translation units | 291 | 292 |
| from engine | 244 | 244 |
| from ggml | 40 | 41 |
| generated (trellis tq overlay) | 7 | 7 |

## Surface 1 - compiled out of llama.cpp

40/41 units, same shape in both trees: `ggml/src` 11, `ggml/src/ggml-cpu` 11,
`ggml-cpu/amx` 2, `ggml-cpu/arch/x86` 2, `ggml/src/ggml-cuda/template-instances` 14.

The CUDA part is 14 units and the list is byte-identical between the trees:
`mmq-instance-{q2_0, iq2_xxs, iq2_xs, iq2_s, iq3_xxs, iq3_s, iq4_nl, iq4_xs, q2_k, q4_k,
q5_1, q5_k, q6_k, q8_0}.cu`. Zero `mmvq-instance-*.cu` are compiled - decode does not use
the head's decode kernels at all.

Composition difference pin to head: `+ ggml/src/ggml-cpu/tiled/tiled.cpp`,
`+ ggml/src/ggml-cpu/tiled/tiled-kernel.cpp`, `- ggml/src/ggml-cpu/iqp.cpp`. All three are
CPU-side; no CUDA unit is added or removed.

## Surface 2 - frozen by the manual port

3 units carry the port, identical in both trees: `native_mmvq.cu` (Strata's own decode),
`mmq_kq_lib.cu` and `mmq_kq_loader.cpp` (the ABI bridge to the vendor DLL). Around them the
overlay generates 7 tq instances, and the engine's own CUDA surface is 48 units - all of that
is Strata code and no upstream commit changes it.

## Surface 3 - not involved

Recursively counted `.cu` files under `ggml/src/ggml-cuda`: pin 188 (120 instances + 68
kernels), head 208 (135 + 73). Compiled: 14 in both. Not compiled: 174 of 188 (pin),
194 of 208 (head) - 93 % of the head's CUDA tree.

## Caveat: the pin's recorded ggml root is gone

`F:\tmp\sync1622-build-strata\CMakeCache.txt` still says
`STRATA_GGML_DIR=C:/Projects/Strata-3060Ti/llama-3cf`, and that copy no longer exists on
disk. The measure substitutes the vendored pin `engine/third_party/strata-llama`
(commit `463940282`) and proves the substitution by name: 38 recorded ggml units, 0 of them
missing in the substitute. The pin binary carrier itself (`strata-q36.exe`, `strata_kq.dll`)
is intact; what is lost is the ability to reconfigure that tree without repointing
`STRATA_GGML_DIR` first.

## Consequence for the port decision

An `tg` regression on the new head cannot come from the head's CUDA code, because the head
contributes 14 compiled CUDA units and those 14 are the same files and names as on the pin.
The candidates are therefore limited to: the port's own `mmq_kq` ABI path, the config tables
and `tile_spec` argument shape the new head exposes, and compiler flags of the tree.
