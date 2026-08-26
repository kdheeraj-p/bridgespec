# Roadmap

## P0: make the runtime safe to embed

- Replace global singleton state with opaque per-instance handles.
- Add `free`, `reset`, `save`, `restore`, `fork`, `rewind`, and `shift` APIs.
- Make initialization transactional and leak-free.
- Reject invalid DFlash positions instead of silently skipping a chunk.
- Add stronger model hashes and manifest schema/version checks.
- Add CI for source compilation, patch application, static scans, and synthetic
  artifact-tool tests.

## P1: make results reproducible outside one workstation

- Publish public prompt fixtures whose licenses permit redistribution.
- Add a benchmark runner with counterbalancing, warmup, hashes, and CSV output.
- Rebase clean MMVQ and sidecar patches onto current `llama.cpp`.
- Validate another RX 7900 XTX, then other RDNA3 SKUs.
- Validate Linux ROCm without changing benchmark claims retroactively.

## P2: generalize beyond Qwen3.8-27B

- Generate model descriptors from GGUF metadata instead of hard-coded sizes.
- Add architecture adapters for other MTP/DFlash-compatible models.
- Support configurable quant families and vocabulary slices.
- Build an acceptance-aware router between MTP, DFlash, n-gram, and plain
  target paths.

## P3: attack the remaining target verifier

- Upstream and extend RDNA3 MMVQ small-batch tuning.
- Explore persistent verify graphs and wider target kernels without losing
  width-one performance.
- Revisit Vulkan/HIP external-memory integration after reliable cross-API
  synchronization exists on Windows.
- Measure end-to-end energy, TTFT, and latency distributions—not only tok/s.

The project will not advertise 170/200/220 tok/s as achieved until a retained,
reproducible run demonstrates it. Those values were projections at earlier
stages of the cost model, not measurements.
