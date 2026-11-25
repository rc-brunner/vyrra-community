#include "whisper.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    std::ifstream file(argv[2], std::ios::binary | std::ios::ate);
    if (!file) return 2;
    const auto length = static_cast<std::streamsize>(file.tellg());
    file.seekg(0);
    std::vector<float> samples(length / sizeof(float));
    if (!file.read(reinterpret_cast<char *>(samples.data()), length)) return 3;
    auto config = whisper_context_default_params();
    config.use_gpu = false;
    config.flash_attn = false;
    auto *ctx = whisper_init_from_file_with_params(argv[1], config);
    if (!ctx) return 4;
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = 4;
    params.language = "auto";
    params.no_context = true;
    params.print_progress = false;
    params.print_realtime = false;
    const auto start = std::chrono::steady_clock::now();
    if (whisper_full(ctx, params, samples.data(), static_cast<int>(samples.size()))) return 5;
    std::string result;
    for (int i = 0; i < whisper_full_n_segments(ctx); ++i) result += whisper_full_get_segment_text(ctx, i);
    std::cout << "Decoded synthetic speech in " << std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count() << " s: " << result << std::endl;
    whisper_print_timings(ctx);
    whisper_free(ctx);
    return result.find("blue notebook") != std::string::npos && result.find("design review") != std::string::npos ? 0 : 6;
}
