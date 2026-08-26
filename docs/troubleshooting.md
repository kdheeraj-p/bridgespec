# Troubleshooting

## Sidecar DLL does not load

- Put `<ROCm>\bin` at the front of `PATH` before starting `llama-server`.
- Confirm the DLL architecture is `gfx1100` and the expected exports exist.
- Confirm server and sidecar are both 64-bit.
- Use absolute paths for the DLL and artifact directory.
- Look for the explicit sidecar activation or refusal message in stderr.

## Server is unexpectedly 20-60 tok/s

1. Check for another `llama-server` or GPU workload.
2. Inspect dedicated vs shared GPU memory. Spill over PCIe can be severe.
3. Confirm the request actually sends `temperature: 0` and `top_k: 1`.
4. Confirm the sidecar activated rather than falling back.
5. Record draft attempts and acceptance; prose and sampled reasoning may have a
   much lower yield than structured code.
6. Confirm cache/context settings match the benchmark you are comparing.

## Artifact validation fails

- Do not mix an ID table from one preparation run with a differently ordered
  sliced head.
- MTP needs 17 tensors; DFlash needs 81 controller tensors plus one target
  embedding tensor.
- The DFlash target head must be Q6_K with 4,200 bytes per 5,120-wide row.
- The ID binary must be exactly 163,840 bytes.

## Deep context crashes or slows down

- Ensure `LLAMA_SPEC_HIP_MAX_POS >= context allocation`.
- Do not exceed 131,072 in the current sources.
- Use `--no-context-shift` and `--ctx-checkpoints 0`.
- Check VRAM before blaming attention; the 24 GB card has little headroom at
  large KV allocations.
- Re-test a fresh request after the deep request to catch state recovery bugs.

## Patch will not apply

Fetch upstream PR #27342 and check out the exact base revision. Current master
is not a supported patch target. Ensure the checkout is clean and patch files
remain LF-normalized.

## Output differs at temperature zero

Quantized GPU reductions can flip near ties, and the stock baseline itself was
not byte-stable on every tie-heavy prompt. Compare against repeated baseline
runs, capture logits/tie margins when possible, and separate draft-token parity
from target-committed output correctness.
