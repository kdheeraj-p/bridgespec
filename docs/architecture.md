# Architecture

## Design goal

BridgeSpec leaves target inference and verification in patched `llama.cpp` but
moves the drafter into a small HIP runtime optimized for one model and one GPU
architecture. This attacks scheduler, graph-rebuild, and tiny-dispatch overhead
without replacing the entire serving stack.

## MTP path

```text
target decode
  -> hidden row + committed token/position
  -> spec_hip_catchup() maintains sidecar K/V
  -> spec_hip_draft() performs three serial MTP steps
  -> full-vocabulary IDs returned to llama.cpp
  -> width-4 target verify
```

The MTP sidecar owns an F16 KV cache. Catch-up is KV-only: it omits Q,
attention, and FFN work whose outputs would be discarded. Draft logits use a
40,960-row Q4_0 head and an ID table maps the selected row back to the target's
248,320-token vocabulary.

## DFlash path

```text
target decode / prefill
  -> five selected layer-input features per token
  -> spec_dflash_chunk() encodes and injects DFlash state
  -> spec_dflash_draft() launches a captured HIP graph
  -> seven proposed IDs
  -> width-8 target verify
```

The sidecar implements the five-layer controller in HIP: Q4_K/Q6_K GEMV,
convolution gates, non-causal sliding-window attention, FFN, target-head top-k,
and selector lattice. The target head is sliced to 40,960 Q6_K rows; selector
IDs are remapped before leaving the DLL.

## Backend boundary

The current integration uses host-facing DLL calls. It is not the zero-copy
Vulkan/HIP design explored under `experiments/windows-interop/`. External
memory was proven bidirectionally on the test system and explicit HIP graphs
worked, while external semaphore behavior was not reliable enough to ship.

## Why width matters

Raw target decode was roughly 40-45 tok/s. Speculative throughput is governed
by useful progress per target verification cycle:

```text
throughput = (1 + accepted draft tokens per cycle) / cycle latency
```

MTP raises progress with a cheap three-token chain. DFlash can produce much
more progress on predictable code but requires an efficient width-8 verifier.
The `gfx1100` MMVQ patch tunes precisely that small-batch regime.

## Model specificity

The sidecars encode Qwen3.8-27B dimensions, quant types, layer count, head
layout, and vocabulary. Generalization requires a generated descriptor or
specialized build per architecture; it is not a matter of renaming a model.
