#include "ggml.h"
#include "ggml-cpu.h"
#include <cmath>
#include <cstdio>

int main() {
    constexpr int width = 32;
    auto *context = ggml_init({ 2 * 1024 * 1024, nullptr, false });
    if (!context) return 1;
    auto *weights = ggml_new_tensor_2d(context, GGML_TYPE_F16, width, width);
    auto *inputs = ggml_new_tensor_2d(context, GGML_TYPE_F32, width, width);
    for (int i = 0; i < width * width; ++i) {
        static_cast<ggml_fp16_t *>(weights->data)[i] = ggml_fp32_to_fp16(i % (width + 1) == 0 ? 1.0f : 0.0f);
        static_cast<float *>(inputs->data)[i] = static_cast<float>(i % 11 - 5);
    }
    auto *output = ggml_mul_mat(context, weights, inputs);
    auto *graph = ggml_new_graph(context);
    ggml_build_forward_expand(graph, output);
    if (ggml_graph_compute_with_ctx(context, graph, 2) != GGML_STATUS_SUCCESS) return 2;
    for (int i = 0; i < width * width; ++i) {
        if (std::fabs(static_cast<float *>(output->data)[i] - static_cast<float *>(inputs->data)[i]) > 0.001f) return 3;
    }
    ggml_free(context);
    std::puts("The portable speech backend returned the expected 1,024 matrix values.");
}
