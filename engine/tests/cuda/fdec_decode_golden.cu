// tests/cuda/fdec_decode_golden.cu - the FDEC decode's code unpackers (src/qwen35/q36_fdec_decode.cuh) against a host
// oracle, bit for bit.  What it pins: the byte selectors, the 0x80 bias removal (q8) and the n - 8 nibble offset (q4)
// that the row-split KV layout depends on; a wrong selector or offset is exactly the defect that once shipped
// (V codes read 32*vblk+8*t instead of the byte pair 64*w+8*g8).
//
// How: seeded words (splitmix64) go through the device unpackers; the host computes the same half2 pairs from the
// definition (a byte is int8, a nibble is n - 8) and the half BIT PATTERNS must match.  No golden file: the oracle is
// arithmetic, so the test carries no state that can rot.
//
//   fdec_decode_golden      check (exit 1 on a mismatch, 77 without a card)
#include "q36_fdec_decode.cuh"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cuda_runtime.h>

namespace {

__global__ void unpack_probe(const uint32_t* __restrict__ words, uint32_t* __restrict__ out_q8,
                             uint32_t* __restrict__ out_q4, int n) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    const uint32_t w = words[i];
    const uint32_t p8 = w ^ 0x80808080u;
    out_q8[2 * i + 0] = fdec_i8pair(p8, 0x4140);
    out_q8[2 * i + 1] = fdec_i8pair(p8, 0x4342);
    const uint32_t lo = w & 0x0F0F0F0Fu, hi = (w >> 4) & 0x0F0F0F0Fu;
    const uint32_t pc = __byte_perm(lo, hi, 0x5140);          // n0..n3 one per byte (low nibble first)
    out_q4[2 * i + 0] = fdec_nib_pair(pc, 0x4140);
    out_q4[2 * i + 1] = fdec_nib_pair(pc, 0x4342);
    const uint32_t lo2 = (w >> 16) & 0x0F0F0F0Fu, hi2 = (w >> 20) & 0x0F0F0F0Fu;
    const uint32_t pc2 = __byte_perm(lo2, hi2, 0x5140);
    out_q4[2 * n + 2 * i + 0] = fdec_nib_pair(pc2, 0x4140);
    out_q4[2 * n + 2 * i + 1] = fdec_nib_pair(pc2, 0x4342);
}

uint64_t splitmix64(uint64_t& s) {
    uint64_t z = (s += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

uint32_t half_bits_from_float(float f) {
    half h = __float2half_rn(f);
    return (uint32_t) __half_as_ushort(h);
}

}  // namespace

int main() {
    int devs = 0;
    if (cudaGetDeviceCount(&devs) != cudaSuccess || devs == 0) {
        std::printf("fdec_decode_golden: no CUDA device, skipped\n");
        return 77;
    }
    constexpr int N = 4096;
    uint32_t* words = (uint32_t*) std::malloc(sizeof(uint32_t) * N);
    uint32_t* q8 = (uint32_t*) std::malloc(sizeof(uint32_t) * 2 * N);
    uint32_t* q4 = (uint32_t*) std::malloc(sizeof(uint32_t) * 4 * N);
    uint64_t seed = 0x5EEDF0DEC0DEull;
    for (int i = 0; i < N; ++i) words[i] = (uint32_t) splitmix64(seed);
    uint32_t *dw = nullptr, *d8 = nullptr, *d4 = nullptr;
    if (cudaMalloc(&dw, sizeof(uint32_t) * N) != cudaSuccess ||
        cudaMalloc(&d8, sizeof(uint32_t) * 2 * N) != cudaSuccess ||
        cudaMalloc(&d4, sizeof(uint32_t) * 4 * N) != cudaSuccess) {
        std::printf("fdec_decode_golden: cudaMalloc failed\n");
        return 1;
    }
    cudaMemcpy(dw, words, sizeof(uint32_t) * N, cudaMemcpyHostToDevice);
    unpack_probe<<<(N + 255) / 256, 256>>>(dw, d8, d4, N);
    if (cudaDeviceSynchronize() != cudaSuccess) {
        std::printf("fdec_decode_golden: kernel failed: %s\n", cudaGetErrorString(cudaGetLastError()));
        return 1;
    }
    cudaMemcpy(q8, d8, sizeof(uint32_t) * 2 * N, cudaMemcpyDeviceToHost);
    cudaMemcpy(q4, d4, sizeof(uint32_t) * 4 * N, cudaMemcpyDeviceToHost);

    int bad = 0, checks = 0;
    for (int i = 0; i < N; ++i) {
        const uint32_t w = words[i];
        // q8: bytes 0,1 -> pair0, bytes 2,3 -> pair1 (the code is int8 after the bias is gone)
        const int8_t b0 = (int8_t) (w & 0xFFu), b1 = (int8_t) ((w >> 8) & 0xFFu);
        const int8_t b2 = (int8_t) ((w >> 16) & 0xFFu), b3 = (int8_t) ((w >> 24) & 0xFFu);
        const uint32_t e0 = half_bits_from_float((float) b0), e1 = half_bits_from_float((float) b1);
        const uint32_t e2 = half_bits_from_float((float) b2), e3 = half_bits_from_float((float) b3);
        const uint32_t g0 = q8[2 * i + 0], g1 = q8[2 * i + 1];
        ++checks;
        if ((g0 & 0xFFFFu) != e0 || (g0 >> 16) != e1 || (g1 & 0xFFFFu) != e2 || (g1 >> 16) != e3) {
            if (bad < 5)
                std::printf("q8 mismatch word %d: w=%08x got %08x %08x want %08x %08x\n", i, w, g0, g1,
                            e2 << 16 | e3, e0 << 16 | e1);
            ++bad;
        }
        // q4: nibbles in code order (low nibble of byte 0 first); first half: bytes 0,1; second: bytes 2,3
        for (int half_i = 0; half_i < 2; ++half_i) {
            const uint32_t src = w >> (16 * half_i);
            uint32_t want[4];
            for (int k = 0; k < 4; ++k) {
                const uint32_t nb = (src >> (4 * k)) & 0xFu;
                want[k] = half_bits_from_float((float) ((int) nb - 8));
            }
            const uint32_t pa = q4[half_i * 2 * N + 2 * i + 0], pb = q4[half_i * 2 * N + 2 * i + 1];
            ++checks;
            if ((pa & 0xFFFFu) != want[0] || (pa >> 16) != want[1] || (pb & 0xFFFFu) != want[2] ||
                (pb >> 16) != want[3]) {
                if (bad < 5)
                    std::printf("q4 mismatch word %d half %d: w=%08x got %08x %08x want %04x %04x %04x %04x\n", i,
                                half_i, w, pa, pb, want[0], want[1], want[2], want[3]);
                ++bad;
            }
        }
    }
    std::printf("fdec_decode_golden: %d checks, %d failed\n", checks, bad);
    return bad == 0 ? 0 : 1;
}
