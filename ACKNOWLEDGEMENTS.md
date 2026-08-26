# Acknowledgements

BridgeSpec exists because a large open-source local-inference community made
the models, runtimes, algorithms, kernels, measurements, and debugging clues
available to study. This page distinguishes source or data incorporated into
BridgeSpec from work that informed the investigation.

## Upstream code and data

| Project or contributor | Contribution to BridgeSpec |
|---|---|
| [`llama.cpp` and ggml](https://github.com/ggml-org/llama.cpp) | The inference runtime, model implementation, and Vulkan/HIP backends that BridgeSpec modifies. The integration is pinned to an intermediate revision of [DFlash2 PR #27342](https://github.com/ggml-org/llama.cpp/pull/27342), with work by Jian Chen, Zihan Zhang ([@SubSir](https://github.com/SubSir)), Xuan-Son Nguyen, and the wider llama.cpp community. |
| [Patrick Walther](https://github.com/PatrickWalther) | The off-by-default `LLAMA_SPEC_CHAIN_LEAN` experiment is a modified adaptation of the chained-MTP prototype in [llama.cpp PR #27173](https://github.com/ggml-org/llama.cpp/pull/27173). It is not claimed as an original BridgeSpec concept. |
| [syv-ai/qwen38-27b-rtx3090](https://github.com/syv-ai/qwen38-27b-rtx3090) | Published the ordered 40,960-token draft vocabulary used by the historical sliced-head experiments. BridgeSpec fetches the list from a pinned revision and does not redistribute it. |
| [Qwen team](https://github.com/QwenLM/Qwen3) and [Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B) | The base model architecture and checkpoint. Historical GGUF measurements used the quant published by [Unsloth](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF). |
| [Inco AI](https://inco.ai/) | Published [DFlash 2](https://inco.ai/blog/dflash2/) and the [Qwen3.8-27B DFlash2 checkpoint](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2) used to generate local test assets. |

Exact licenses, revisions, and redistribution boundaries are recorded in
[Third-party notices](THIRD_PARTY_NOTICES.md).

## Research and engineering references

The following projects supplied prior art, comparative implementations,
benchmark targets, or experimental ideas. Unless the table above or the
third-party notices explicitly says otherwise, BridgeSpec does **not** contain
their source code.

| Project or contributor | How the work informed BridgeSpec |
|---|---|
| Jian Chen, Yesheng Liang, and Zhijian Liu | The [DFlash paper](https://arxiv.org/abs/2602.06036) and [Z Lab implementation](https://github.com/z-lab/dflash) established block-diffusion speculative decoding. BridgeSpec's HIP DFlash sidecar independently implements the required tensor semantics for its llama.cpp integration. |
| [HipFire](https://github.com/warpfront/hipfire) | An architectural and benchmarking reference for RDNA-native HIP inference, graph execution, wide-block verification, and DFlash on AMD GPUs. Credit includes Kaden Schutt, `alpineq`, and the contributors documented in HipFire's [prior-art record](https://github.com/warpfront/hipfire/blob/master/PRIOR-ART.md). BridgeSpec contains no HipFire source. |
| Quentin Quaadgras ([@Splizard](https://github.com/Splizard)) | The [`tinygrad-qwen38`](https://github.com/Splizard/tinygrad-qwen38) gfx1100 work informed kernel exploration around AMD GEMV, packed dot products, weight decoding, LDS lookup tables, and persistent workgroups. BridgeSpec's llama.cpp kernels are independent implementations. |
| [`sudoingX/qwen38-mtp`](https://github.com/sudoingX/qwen38-mtp) and its contributors | Early community recipes, benchmark methodology, and measurements for Qwen3.8's built-in MTP path. Splizard's [benchmark fork](https://github.com/Splizard/qwen38-mtp) supplied additional AMD comparison data. |
| [SnoopsDev](https://github.com/SnoopsDev) | The AMD Vulkan MMVQ investigation in [llama.cpp PR #25666](https://github.com/ggml-org/llama.cpp/pull/25666) was studied and benchmarked while isolating wide-verification behavior. Its patch is not incorporated into BridgeSpec. |
| [kashif](https://github.com/kashif) | The suffix-decoding work in [llama.cpp PR #26283](https://github.com/ggml-org/llama.cpp/pull/26283) was evaluated as a related agentic-workload path. Its patch is not incorporated into BridgeSpec. |
| [LocalMaxxing](https://localmaxxing.com/) and [`localmaxxing-cli`](https://github.com/LottoLottoLotto/localmaxxing-cli) | Public hardware results supplied external comparison points and motivated independent reproduction attempts, including the [Qwen3.8-27B RX 7900 XTX run](https://localmaxxing.com/en/models/Qwen/Qwen3.8-27B?run=cmt1ff27w00ydmv01drv7z4np). All BridgeSpec results were measured locally. |
| [Laurent Zuijdwijk's llama.cpp fork](https://github.com/LaurentZuijdwijk/llama.cpp) | A later comparative implementation of acceptance-driven adaptive speculation and wide-batch Vulkan tuning. It was not source material for the existing BridgeSpec implementation. |
| [tinygrad](https://github.com/tinygrad/tinygrad), [AMD ROCm/HIP](https://github.com/ROCm/HIP), and [Khronos Vulkan](https://github.com/KhronosGroup/Vulkan-Docs) | Open runtimes, APIs, documentation, and tooling that made the kernel and interop investigation possible. |

## Scope and endorsement

Acknowledgement means that a project materially contributed code, data,
prior art, methodology, or a comparison point. It does not imply endorsement
of BridgeSpec by any named person or organization, nor endorsement by
BridgeSpec of every claim made by a referenced project.

BridgeSpec's original HIP sidecars, artifact tooling, RDNA3 tuning,
integration changes, validation work, and Windows measurements are published
under this repository's license. See Git history and the third-party notices
for the boundary between original and upstream work.
