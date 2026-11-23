// q36_fdec_decode.cuh - the code unpackers the FDEC decode kernel shares (q36_engine.cu) and the golden test
// (tests/cuda/fdec_decode_golden.cu) checks: a KV code word becomes half2 pairs for mma.m16n8k16.
//
// KV_Q8: one byte per key, signed (the caller removes the 0x80 bias before calling).  KV_Q4: one nibble per key,
// value n - 8.  Both use the mantissa trick: a half 0x6400|n reads as 1024 + n (representable exactly up to 2048),
// so HSUB2 by 1032 gives n - 8 and by 1152 gives (byte - 128) for the biased q8 codes.
#pragma once
#include <cuda_fp16.h>
#include <cstdint>

// the q4_0 KV type value (engine's KvType enum: KV_Q4 = 4); the header stays free of the engine's enum
constexpr int kFdecQ4Type = 4;

// q8: four biased bytes -> half2 (b0 - 128, b1 - 128) for the byte pair the selector names (0x4140: bytes 0,1)
__device__ __forceinline__ uint32_t fdec_i8pair(uint32_t w, uint32_t sel) {
    uint32_t x = __byte_perm(w, 0x64646464u, sel);
    half2 h = __hsub2(*reinterpret_cast<half2*>(&x), __float2half2_rn(1152.0f));
    return *reinterpret_cast<uint32_t*>(&h);
}

// q4: four nibble codes one per byte -> half2 (n0 - 8, n1 - 8) for the byte pair the selector names
__device__ __forceinline__ uint32_t fdec_nib_pair(uint32_t x, uint32_t sel) {
    uint32_t h = __byte_perm(x, 0x64646464u, sel);
    half2 v = __hsub2(*reinterpret_cast<half2*>(&h), __float2half2_rn(1032.0f));
    return *reinterpret_cast<uint32_t*>(&v);
}

__device__ __forceinline__ uint32_t fdec_mul2(uint32_t x, half2 s) {
    half2 h = __hmul2(*reinterpret_cast<half2*>(&x), s);
    return *reinterpret_cast<uint32_t*>(&h);
}

// one 4-code unit -> a half2 code pair: q8 codes are bytes (the 0x80 bias removed by the caller), q4 codes are
// nibbles widened to bytes by the caller (__byte_perm with 0x5140)
__device__ __forceinline__ uint32_t fdec_code_pair(uint32_t x, int td, uint32_t sel) {
    return td == kFdecQ4Type ? fdec_nib_pair(x, sel) : fdec_i8pair(x, sel);
}
