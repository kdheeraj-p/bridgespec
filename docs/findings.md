# Research findings

## 1. The card was not the raw-decode bottleneck

Raw 27B decode stayed around 40-46 tok/s across the compared stacks. The large
gains came from producing more verified tokens per expensive target pass, not
from doubling raw target bandwidth.

## 2. A confidence gate can disable useful speculation

`--spec-draft-p-min 0.75` suppressed attempts even when the drafts that were
made remained accurate. Removing the gate raised short-context throughput and
nearly doubled one deep-context result. The right metric is accepted progress
per wall-clock cycle, not drafter confidence in isolation.

## 3. Width four was a Vulkan boundary, not a drafting law

Both MTP and DFlash fell sharply when the verify width crossed five on the
original Vulkan path. Profiling isolated quantized matrix-vector behavior and
driver/compiler sensitivity. That explained why deeper speculation looked
intrinsically bad in early tests.

## 4. Sliced draft heads are correct but dispatch floors matter

A 40,960-row head removes most vocabulary rows from the drafter. Target
verification makes missed draft-vocabulary tokens a speed cost rather than a
target-output quality change. On Vulkan the improvement was only about 2%
because small-dispatch floors dominated; the same artifact remained useful in
the HIP sidecars for VRAM and compute.

## 5. KV-only catch-up deletes provably dead work

For MTP catch-up rows, only K/V side effects are consumed. Removing Q,
attention, and FFN cut catch-up from about 1.49/1.38 ms wall/GPU to 0.69/0.56
ms and contributed approximately +1.3 code / +3.1 agentic tok/s in the local
isolation A/B.

## 6. HIP/Vulkan switching was inexpensive; scheduler structure was not

The measured API-switch tax was tens of microseconds. The expensive part was
repeated Vulkan graph/submission structure for serial drafts. A small HIP
sidecar captured most drafter work while retaining the target backend.

## 7. Wide verification required RDNA3-specific small-batch tuning

The upstream MMVQ heuristic was strongly tuned for batch one. Widths 2-8 fell
to underoccupied launch shapes, and a gated-delta-net projection walked the
same weights once per channel. Tuning launch geometry and folding channels
reduced width-8 verify substantially while leaving width one unchanged.

## 8. Speculation is a routing problem

DFlash's 146 tok/s agentic result and 56.8 tok/s prose result came from the same
basic stack. A deployable system should route predictable edits/code toward
wide DFlash and use MTP or plain target for low-yield prose and deep-context
workloads.
