# Third-party notices

BridgeSpec is Copyright (c) 2026 kdheeraj-p and BridgeSpec contributors.

## llama.cpp and ggml

Some BridgeSpec source and the `llama.cpp` integration patch are based on or
modify [`llama.cpp`](https://github.com/ggml-org/llama.cpp) and ggml,
Copyright (c) 2023-2026 The ggml authors, licensed under the MIT License. The
exact license is preserved at [LICENSES/llama.cpp-MIT.txt](LICENSES/llama.cpp-MIT.txt).

The integration baseline is commit
`f5a7ec15da6add890a5624c0990714498df837a4` from
[`llama.cpp` PR #27342](https://github.com/ggml-org/llama.cpp/pull/27342).
That baseline includes work by Jian Chen, Zihan Zhang
([@SubSir](https://github.com/SubSir)), Xuan-Son Nguyen, and other
`llama.cpp`/ggml contributors. BridgeSpec modifications are represented by
the patches and this repository's history.

The off-by-default `LLAMA_SPEC_CHAIN_LEAN` experiment in the integration patch
is a modified adaptation of Patrick Walther's chained-MTP prototype in
[`llama.cpp` PR #27173](https://github.com/ggml-org/llama.cpp/pull/27173).
It remains covered by the upstream MIT license and is not claimed as an
original BridgeSpec concept.

## DFlash

DFlash 2 is credited to Inco AI, together with the original
[DFlash paper](https://arxiv.org/abs/2602.06036) and
[implementation](https://github.com/z-lab/dflash) by Jian Chen, Yesheng
Liang, and Zhijian Liu. The historical DFlash GGUF used for local tests was
published by
[`incoai/Qwen3.8-27B-DFlash2-GGUF`](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF)
and identified by its publisher as Apache-2.0. No DFlash model weight is
included in BridgeSpec.

## Models and draft vocabulary

Historical results used:

- The official [`Qwen3.8-27B`](https://huggingface.co/Qwen/Qwen3.8-27B)
  architecture and checkpoint from the Qwen team.
- [`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF),
  identified by its publisher as Apache-2.0.
- The 40,960-token draft vocabulary from
  [`syv-ai/qwen38-27b-rtx3090`](https://github.com/syv-ai/qwen38-27b-rtx3090/blob/c954724104a7856a07abb7031cc4af780ae7f5bf/prepare/draft_vocab_ids.json),
  commit `c954724104a7856a07abb7031cc4af780ae7f5bf`, Apache-2.0.

BridgeSpec's tools can convert user-supplied GGUFs and the ordered integer list
into local runtime assets. This source repository does not distribute model
weights, derived tensor blobs, the converted ID binary, or the JSON list.

If you redistribute generated artifacts, preserve the applicable source
license, immutable source revision, original model name, source and generated
hashes, extraction command, and a prominent modification notice. A copy of the
Apache License 2.0 is provided at [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt)
for convenience.

## Research and benchmark references

BridgeSpec also studied or benchmarked HipFire, Splizard's gfx1100 tinygrad
work, qwen38-mtp, LocalMaxxing, Laurent Zuijdwijk's adaptive-speculation fork,
and related `llama.cpp` PRs. Those projects are credited with exact links and
their roles in [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).

Unless explicitly identified above, their source code and assets are not
incorporated or redistributed here. Their inclusion in the acknowledgements
records prior art, methodology, or comparative evidence rather than code
provenance.

## Trademarks and non-endorsement

No endorsement by any acknowledged contributor, project, or organization is
implied. Product and project names remain the property of their respective
owners.

This is a practical provenance record, not legal advice.
