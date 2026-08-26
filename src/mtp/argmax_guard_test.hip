// SPDX-License-Identifier: MIT
#include "kernels.hip"

#include <limits>

static int check_hip(hipError_t error, const char * operation) {
    if (error == hipSuccess) return 0;
    std::fprintf(stderr, "%s: %s\n", operation, hipGetErrorString(error));
    return 1;
}

int main() {
    static constexpr int N = 4096;
    static constexpr int VOCAB = 8192;
    static constexpr int NPARTS = (N + 2047) / 2048;
    int failures = 0;

    std::vector<float> logits(N, std::numeric_limits<float>::quiet_NaN());
    std::vector<int> remap(N);
    for (int i = 0; i < N; ++i) remap[i] = i + 100;

    float * logits_d = nullptr, * pmax_d = nullptr;
    int * pidx_d = nullptr, * remap_d = nullptr, * out_d = nullptr;
    failures += check_hip(hipMalloc(&logits_d, N * sizeof(float)), "hipMalloc logits");
    failures += check_hip(hipMalloc(&pmax_d, NPARTS * sizeof(float)), "hipMalloc pmax");
    failures += check_hip(hipMalloc(&pidx_d, NPARTS * sizeof(int)), "hipMalloc pidx");
    failures += check_hip(hipMalloc(&remap_d, N * sizeof(int)), "hipMalloc remap");
    failures += check_hip(hipMalloc(&out_d, sizeof(int)), "hipMalloc out");
    if (failures != 0) return 1;
    failures += check_hip(hipMemcpy(logits_d, logits.data(), N * sizeof(float), hipMemcpyHostToDevice), "copy logits");
    failures += check_hip(hipMemcpy(remap_d, remap.data(), N * sizeof(int), hipMemcpyHostToDevice), "copy remap");
    argmax_partial<<<NPARTS, 256>>>(logits_d, N, pmax_d, pidx_d);
    argmax_final<<<1, 1>>>(pmax_d, pidx_d, NPARTS, N, remap_d, VOCAB, out_d);
    int output = 0;
    failures += check_hip(hipMemcpy(&output, out_d, sizeof(int), hipMemcpyDeviceToHost), "read all-NaN result");
    if (output != -1) {
        std::fprintf(stderr, "all-NaN argmax returned %d, expected -1\n", output);
        ++failures;
    }

    // A finite logit below the old -1e30 sentinel must still be selected.
    logits[3073] = -1e35f;
    failures += check_hip(hipMemcpy(logits_d, logits.data(), N * sizeof(float), hipMemcpyHostToDevice), "copy mixed logits");
    argmax_partial<<<NPARTS, 256>>>(logits_d, N, pmax_d, pidx_d);
    argmax_final<<<1, 1>>>(pmax_d, pidx_d, NPARTS, N, remap_d, VOCAB, out_d);
    failures += check_hip(hipMemcpy(&output, out_d, sizeof(int), hipMemcpyDeviceToHost), "read finite result");
    if (output != remap[3073]) {
        std::fprintf(stderr, "mixed argmax returned %d, expected %d\n", output, remap[3073]);
        ++failures;
    }

    // An invalid chained token must produce zeros instead of indexing before or
    // after the embedding table.
    block_q4_0 * embedding_d = nullptr;
    float * row_d = nullptr;
    int invalid_row = -1;
    failures += check_hip(hipMalloc(&embedding_d, sizeof(block_q4_0)), "hipMalloc embedding");
    failures += check_hip(hipMalloc(&row_d, 32 * sizeof(float)), "hipMalloc row");
    failures += check_hip(hipMemset(embedding_d, 0, sizeof(block_q4_0)), "clear embedding");
    failures += check_hip(hipMemcpy(out_d, &invalid_row, sizeof(int), hipMemcpyHostToDevice), "copy invalid row");
    deq_row_q4_0<<<1, 32>>>(embedding_d, out_d, row_d, 32, 1);
    std::vector<float> row(32, 1.0f);
    failures += check_hip(hipMemcpy(row.data(), row_d, row.size() * sizeof(float), hipMemcpyDeviceToHost), "read guarded row");
    for (const float value : row) {
        if (value != 0.0f) { ++failures; break; }
    }

    failures += check_hip(hipFree(row_d), "hipFree row");
    failures += check_hip(hipFree(embedding_d), "hipFree embedding");
    failures += check_hip(hipFree(out_d), "hipFree out");
    failures += check_hip(hipFree(remap_d), "hipFree remap");
    failures += check_hip(hipFree(pidx_d), "hipFree pidx");
    failures += check_hip(hipFree(pmax_d), "hipFree pmax");
    failures += check_hip(hipFree(logits_d), "hipFree logits");
    if (failures == 0) std::puts("argmax_guard_test: PASS");
    return failures == 0 ? 0 : 1;
}
