// include/strata/prefill/mmq_kq_abi.hpp - the interface between the engine (src/prefill/moe_mmq.cu) and strata_kq, the
// shared library with the K-quant MMQ prompt kernels (src/prefill/mmq_kq_lib.cu).  Bump the version when a function's
// meaning changes; the argument block (ggml's mmq_args) is checked by its size.
#pragma once

// 2: llama.cpp's mmq_args changed after the pinned tree (tile_spec/ntj/J_best instead of expert_bounds/
// ncols_max/ncols_opt) and mul_mat_q_case takes prec_src1.  sizeof(mmq_args) is part of strata_kq_abi()'s
// return value, so a mismatching pair refuses to load; the version bump documents the format change.
#define STRATA_KQ_ABI_VERSION 2

#if defined(_WIN32)
#define STRATA_KQ_LIB_NAME "strata_kq.dll"
#else
#define STRATA_KQ_LIB_NAME "libstrata_kq.so"
#endif

extern "C" {
typedef int (*strata_kq_abi_fn)();
typedef int (*strata_kq_init_fn)(int device);
typedef int (*strata_kq_run_fn)(int device, int ggml_type, const void* mmq_args, void* stream);
}

// the engine's side (src/prefill/mmq_kq_loader.cpp)
namespace strata::prefill::mmq::kq {
/// STRATA_MMQ_KQ=1: the K-quant experts' prompt products through MMQ (opt-in: other rounding than the FP16 path).
bool wanted();
/// wanted() and the library is open and started on every GPU (the first call opens it and says what happened).
bool available();
/// One product on the current GPU: 0 = launched, else an error (-1: no library or not this type).
int run(int ggml_type, const void* mmq_args, void* stream);
/// sizeof(mmq_args) on the engine's side (moe_mmq.cu), checked against the library's.
int abi_args_size();
}  // namespace strata::prefill::mmq::kq
