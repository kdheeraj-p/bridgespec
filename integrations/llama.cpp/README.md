# `llama.cpp` integration

BridgeSpec is carried as a patch series because the source repository is
independently useful and the integration base is an in-flight `llama.cpp` PR,
not current master.

## Pinned base

```text
commit: f5a7ec15da6add890a5624c0990714498df837a4
source: ggml-org/llama.cpp PR #27342
```

The commit is reachable from the PR ref but is not advertised by current
master. Fetch it explicitly:

```powershell
git clone https://github.com/kdheeraj-p/llama.cpp.git .\external\llama.cpp
git -C .\external\llama.cpp remote add upstream https://github.com/ggml-org/llama.cpp.git
git -C .\external\llama.cpp fetch upstream `
  refs/pull/27342/head:refs/remotes/bridgespec/pr-27342
git -C .\external\llama.cpp checkout --detach `
  f5a7ec15da6add890a5624c0990714498df837a4
```

## Patches

1. `0001-qwen38-speculative-sidecar-integration.patch`
   - Sliced MTP head loading and remap support.
   - MTP and DFlash Windows DLL loading and sidecar calls.
   - Absolute-DLL-path enforcement plus MTP ABI 1 / DFlash ABI 2 handshakes.
   - Target-layer feature extraction for DFlash.
   - Runtime validation/fallback and diagnostic hooks.
   - Off-by-default native chain experiments retained from the research tree.
2. `0002-gfx1100-wide-mmvq-tuning.patch`
   - RDNA3 width 2-8 MMVQ launch tuning.
   - Gated-delta-net channel-to-column folding.
   - Focused backend correctness coverage.
3. `0003-vulkan-wide-verify-experiments.patch`
   - IQ4_XS width experiments and shader variants.
   - Archived for reproducibility; not applied by default because several
     paths were neutral or regressions.

The first two patches are the default research configuration. The first patch
is still too broad for upstreaming as one change; the clean upstream candidates
are the MMVQ tuning/tests and smaller integration pieces.

## Apply safely

```powershell
.\scripts\apply-llama-patches.ps1 `
  -LlamaCppPath .\external\llama.cpp `
  -WhatIf

.\scripts\apply-llama-patches.ps1 `
  -LlamaCppPath .\external\llama.cpp
```

The script requires the exact base and a clean checkout. It runs
`git apply --check` before mutation. Do not apply the patches to an unrelated
`llama.cpp` revision and resolve conflicts by guesswork; model-graph and
speculative APIs are changing quickly.

## Provenance

The patch base is MIT-licensed `llama.cpp`/ggml. See the root
[third-party notices](../../THIRD_PARTY_NOTICES.md) and
[`llama.cpp` license](../../LICENSES/llama.cpp-MIT.txt).
