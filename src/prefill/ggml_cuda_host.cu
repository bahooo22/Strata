// src/prefill/ggml_cuda_host.cu - prompt-speed plan step 2b: the host-side symbols of llama.cpp's ggml-cuda that its MMQ
// and quantize code reference, for the MMQ kernels compiled into strata_mmq without the rest of ggml-cuda.cu.
#include "strata/core/emulate.hpp"
#include "common.cuh"
#if defined(STRATA_MMQ_API_V2)
// The checkout's ggml_backend_cuda_context owns a std::unique_ptr<ggml_cuda_stream_context> whose destructor
// this file instantiates; the complete type lives in graph.cuh (common.cuh only forward-declares it).
#include "graph.cuh"
#endif

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

[[noreturn]] void ggml_cuda_error(const char * stmt, const char * func, const char * file, int line, const char * msg) {
    std::fprintf(stderr, "ggml-cuda (strata mmq): %s: %s\n  in %s at %s:%d\n", msg, stmt, func, file, line);
    std::abort();
}

int ggml_cuda_get_device() {
    int id = 0;
    CUDA_CHECK(cudaGetDevice(&id));
    return id;
}

#if defined(GGML_USE_HIP)
namespace {

unsigned parse_hex(const std::string& value) {
    if (value.empty()) return 0;
    char* end = nullptr;
    const unsigned long parsed = std::strtoul(value.c_str(), &end, 16);
    return end == value.c_str() || *end != '\0' ? 0 : static_cast<unsigned>(parsed);
}

// Match GGML's AMD cc encoding: OFFSET_AMD + gfx major * 0x100 + minor/stepping.
// For example, gfx1100 maps to GGML_CUDA_CC_RDNA3 (0x01001100).
int ggml_cuda_parse_amd_id(const char* device_name) {
    if (device_name == nullptr) return GGML_CUDA_CC_OFFSET_AMD;

    std::string arch(device_name);
    if (arch.compare(0, 3, "gfx") == 0) arch.erase(0, 3);
    const size_t suffix = arch.find(':');
    if (suffix != std::string::npos) arch.resize(suffix);

    const size_t generic = arch.rfind("-generic");
    if (generic != std::string::npos && generic + 8 == arch.size()) arch.resize(generic);

    unsigned major = 0;
    unsigned minor = 0;
    const size_t separator = arch.find('-');
    if (separator != std::string::npos) {
        major = parse_hex(arch.substr(0, separator));
        minor = parse_hex(arch.substr(separator + 1)) * 0x10;
    } else if (arch.size() >= 3) {
        minor = parse_hex(arch.substr(arch.size() - 2));
        major = parse_hex(arch.substr(0, arch.size() - 2));
    }
    return GGML_CUDA_CC_OFFSET_AMD + static_cast<int>(major * 0x100 + minor);
}

}  // namespace
#endif

const ggml_cuda_device_info & ggml_cuda_info() {
    static ggml_cuda_device_info info = [] {
        ggml_cuda_device_info in = {};
        int n = 0;
        if (cudaGetDeviceCount(&n) != cudaSuccess) n = 0;
        n = n > GGML_CUDA_MAX_DEVICES ? GGML_CUDA_MAX_DEVICES : n;
        in.device_count = n;
        in.physical_device_count = n;
        for (int id = 0; id < n; ++id) {
            cudaDeviceProp prop;
            CUDA_CHECK(cudaGetDeviceProperties(&prop, id));
            auto & d = in.devices[id];
#if defined(GGML_USE_HIP)
            d.cc = ggml_cuda_parse_amd_id(prop.gcnArchName);
            if ((d.cc & 0xff00) == 0) {
                // Fall back to HIP's device version fields if its architecture name is unavailable.
                d.cc = GGML_CUDA_CC_OFFSET_AMD + prop.major * 0x100 + prop.minor * 0x10;
            }
            d.smpbo = prop.sharedMemPerBlock;
            d.integrated = false;
            d.supports_cooperative_launch = false;
            d.nsm = prop.multiProcessorCount;
            d.smpb = prop.sharedMemPerBlock;
            d.warp_size = prop.warpSize;
#else
            // #542: the fields MMQ's choices read come from cudaDeviceGetAttribute, which is ABI-stable: a
            // cudaDeviceProp filled by an older libcudart than the headers (a CUDA 13 build that links a CUDA 12
            // libcudart.so) is shifted - sharedMemPerBlockOptin read 1 there, and every i-quant lost MMQ (#420's
            // fits()).  In a matched build both give the same values.
            auto attr = [id](cudaDeviceAttr a) {
                int v = 0;
                CUDA_CHECK(cudaDeviceGetAttribute(&v, a, id));
                return v;
            };
            d.cc = 100 * strata::cc_major_of(attr(cudaDevAttrComputeCapabilityMajor)) +
                   10 * strata::cc_minor_of(attr(cudaDevAttrComputeCapabilityMinor));   // STRATA_EMULATE_CC
            d.smpbo = strata::smem_optin_of(attr(cudaDevAttrMaxSharedMemoryPerBlockOptin));
            d.integrated = attr(cudaDevAttrIntegrated) != 0;
            d.supports_cooperative_launch = attr(cudaDevAttrCooperativeLaunch) != 0;
            d.nsm = attr(cudaDevAttrMultiProcessorCount);
            d.smpb = (size_t) attr(cudaDevAttrMaxSharedMemoryPerBlock);
            d.warp_size = attr(cudaDevAttrWarpSize);
#endif
            d.vmm = false;
            d.total_vram = prop.totalGlobalMem;
            d.physical_device = id;
            d.physical_share_count = 1;
            d.virtual_index = 0;
        }
        return in;
    }();
    return info;
}

namespace {
// Buffers are kept and reused: MMQ asks for the same few sizes every launch (its stream-k fixup tiles).
struct CachingPool : ggml_cuda_pool {
    struct Buf { void * p; size_t size; bool used; };
    std::vector<Buf> bufs;
    std::mutex mu;
    void * alloc(size_t size, size_t * actual_size) override {
        std::lock_guard<std::mutex> lk(mu);
        for (auto & b : bufs)
            if (!b.used && b.size >= size) { b.used = true; *actual_size = b.size; return b.p; }
        void * p = nullptr;
        CUDA_CHECK(cudaMalloc(&p, size));
        bufs.push_back({p, size, true});
        *actual_size = size;
        return p;
    }
    void free(void * ptr, size_t) override {
        std::lock_guard<std::mutex> lk(mu);
        for (auto & b : bufs)
            if (b.p == ptr) { b.used = false; return; }
    }
    ~CachingPool() override {
        for (auto & b : bufs) cudaFree(b.p);
    }
};
}  // namespace

// The engine replaces ggml-cuda's pool with its own caching pool; the checkout's common.cuh passes the context
// as the first argument (after 57d04820d the context knows the stream), the pinned tree does not.
#if defined(STRATA_MMQ_API_V2)
std::unique_ptr<ggml_cuda_pool> ggml_backend_cuda_context::new_pool_for_device(ggml_backend_cuda_context&, int, int) {
#else
std::unique_ptr<ggml_cuda_pool> ggml_backend_cuda_context::new_pool_for_device(int, int) {
#endif
    return std::unique_ptr<ggml_cuda_pool>(new CachingPool());
}

#if defined(STRATA_MMQ_API_V2)
#if defined(GGML_CUDA_USE_PDL)
// The checkout's launch helper reaches PDL support through a symbol defined in ggml-cuda.cu, which
// the MMQ kit does not build; the definition copies the checkout's own body (env gate, per-device
// cache, PTX-version guard).
bool ggml_cuda_kernel_can_use_pdl(const void * kernel) {
    static const bool env_pdl_enabled = []() {
        const char * env = getenv("GGML_CUDA_PDL");
        return env == nullptr || std::atoi(env) != 0;
    }();
    if (!env_pdl_enabled) {
        return false;
    }

    const int device = ggml_cuda_get_device();

    struct cache_key {
        int          device;
        const void * kernel;

        bool operator==(const cache_key & other) const { return device == other.device && kernel == other.kernel; }
    };

    struct cache_key_hash {
        static size_t hash_mix(size_t x) {
            std::uint64_t       y = x;
            const std::uint64_t m = 0xe9846af9b1a615d;

            y ^= y >> 32;
            y *= m;
            y ^= y >> 32;
            y *= m;
            y ^= y >> 28;

            return static_cast<size_t>(y);
        }

        size_t operator()(const cache_key & key) const {
            size_t h = 42;
            h = hash_mix(h + key.device);
            h = hash_mix(h + reinterpret_cast<size_t>(key.kernel));
            return h;
        }
    };

    static std::mutex                                          cache_mutex;
    static std::unordered_map<cache_key, bool, cache_key_hash> cache;

    const cache_key             key = { device, kernel };
    std::lock_guard<std::mutex> lock(cache_mutex);
    const auto                  it = cache.find(key);
    if (it != cache.end()) {
        return it->second;
    }

    cudaFuncAttributes attr = {};
    CUDA_CHECK(cudaFuncGetAttributes(&attr, kernel));

    // PDL device-side primitives are emitted only for PTX versions >= 90; guard on the loaded
    // kernel's PTX version so forward-JIT'ed kernels do not opt into PDL.
    const bool can_use_pdl = attr.ptxVersion >= 90;
    cache.emplace(key, can_use_pdl);
    return can_use_pdl;
}
#endif // defined(GGML_CUDA_USE_PDL)

// The checkout moved the context constructor from common.cuh into ggml-cuda.cu, which the MMQ kit
// does not build; the definition copies the checkout's own body (device, name, stream context).
ggml_backend_cuda_context::ggml_backend_cuda_context(int device) :
    device(device),
    name(GGML_CUDA_NAME + std::to_string(device)),
    concurrent_stream_context(std::make_unique<ggml_cuda_stream_context>()) {
}
#endif

ggml_backend_cuda_context::~ggml_backend_cuda_context() {}
