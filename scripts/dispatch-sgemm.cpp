#include "llamafile/sgemm.h"

#if defined(_MSC_VER)
#include <intrin.h>
#include <windows.h>
#else
#include <cpuid.h>
#endif

extern "C" decltype(llamafile_sgemm) vyrra_avx2_sgemm;

static bool supports_fast_kernel() {
    // The F16 kernel uses both half conversion (F16C) and fused multiply-add (FMA).
    constexpr unsigned math_features = (1u << 29) | (1u << 12);
#if defined(_MSC_VER)
    if (!IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE)) return false;
    int registers[4] = {};
    __cpuid(registers, 1);
    if ((static_cast<unsigned>(registers[2]) & math_features) != math_features) return false;
    // MSVC /arch:AVX2 may also emit BMI and BMI2 instructions.
    __cpuidex(registers, 7, 0);
    constexpr unsigned bmi_features = (1u << 3) | (1u << 8);
    return (static_cast<unsigned>(registers[1]) & bmi_features) == bmi_features;
#else
    unsigned eax, ebx, ecx, edx;
    return __builtin_cpu_supports("avx2") && __get_cpuid(1, &eax, &ebx, &ecx, &edx)
        && (ecx & math_features) == math_features;
#endif
}

extern "C" bool llamafile_sgemm(const ggml_compute_params *params, int64_t m, int64_t n, int64_t k,
                               const void *a, int64_t lda, const void *b, int64_t ldb, void *c, int64_t ldc,
                               int a_type, int b_type, int c_type) {
    static const bool supported = supports_fast_kernel();
    // Returning false asks ggml to perform this operation with its baseline backend.
    return supported && vyrra_avx2_sgemm(params, m, n, k, a, lda, b, ldb, c, ldc, a_type, b_type, c_type);
}
