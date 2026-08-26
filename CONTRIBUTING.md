# Contributing to BridgeSpec

BridgeSpec is a research preview. Small, reviewable changes with complete
measurements are preferred over large performance bundles.

## Before opening a change

1. Open an issue describing the model, GPU, backend, and bottleneck.
2. Separate correctness, integration, and performance changes.
3. Keep model weights, generated blobs, logs with private prompts, and compiled
   binaries out of Git.
4. Run `scripts/verify-source.ps1`.
5. Apply patches to a clean pinned `llama.cpp` tree and build both affected
   targets.

## Performance evidence

Include:

- Exact commits and command lines.
- GPU, driver, ROCm/Vulkan, model quant, and model hashes.
- Context allocation/depth, KV type, slots, cache state, and sampling.
- Public prompt or prompt hash.
- Warmup and process order.
- Every run, not only the best run.
- Draft attempted/accepted and accepted progress per cycle.
- Target output comparison and relevant backend tests.

Label a same-process fixed-prompt result as such. Do not generalize structured
code acceptance to prose, reasoning, or long-context workloads.

## Code style

- C++17/HIP, explicit dimensions, and checked host-side API failures.
- Keep kernels independently testable where practical.
- Add an SPDX identifier to new source files.
- Update docs and artifact schemas with behavior changes.
- Do not silently broaden the supported-platform table.

By contributing, you agree that your contribution may be distributed under
the repository's MIT license and that you have the right to submit it.
