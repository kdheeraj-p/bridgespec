# State, correctness, and operational safety

## What target verification guarantees

The target model verifies every proposed token and commits only the accepted
prefix. An incorrect draft normally costs acceptance and speed rather than
changing the final token selected by the target.

This guarantee has boundaries. A desynchronized cache, wrong target features,
or invalid lifecycle transition can corrupt later draft state, crash the
process, or produce unstable behavior. Target verification is not permission
to ignore runtime state.

## Required invariants

- One server slot and one sequence: `-np 1`.
- No context shifting: `--no-context-shift`.
- No prompt-cache reuse: `--cache-ram 0 --no-cache-idle-slots`.
- No context checkpoints: `--ctx-checkpoints 0`.
- No sequence fork, save, restore, rewind, or migration.
- `LLAMA_SPEC_HIP_MAX_POS` must be at least the server context and at most
  131,072 for the current implementation.
- The target, drafter, ID table, and extracted manifests must come from the
  same model family and preparation run.

## ABI validation and fallback

MTP exposes release ABI 1 and checks embedding width and sliced-head row count.
DFlash exposes release ABI 2 and validates the encoded feature width and block
size. The patched host refuses missing or mismatched ABI exports before
initialization. Runtime errors disable the sidecar permanently for the process;
target-only/fallback behavior is intended to preserve request correctness at
reduced speed.

Fallback is deliberately loud. Treat any fallback log as an operational fault,
not a normal performance mode.

## Replay evidence

- MTP: 332/333 exact draft cycles and 997/999 draft tokens in the captured
  replay set.
- DFlash: 226/227 exact cycles and 1,587/1,589 draft tokens.

The few disagreements were near-tie draft choices under different cache
precision/order. They did not alter target-verified output in the fixed
workloads. New changes should repeat both token-level replay and end-to-end
target output comparison.

## Known lifecycle debt

The current DLLs are singleton, non-thread-safe, and lack explicit
`reset/free/save/restore/fork/shift` operations. Partial initialization can
also leak allocations. A production-quality runtime needs an opaque handle per
sequence, explicit teardown, and transactional initialization.

## Minimum release gate

1. Validate generated artifact manifests and byte sizes.
2. Confirm the expected sidecar activation line in server logs.
3. Run a fixed greedy control and compare the output hash.
4. Run a warm throughput smoke test.
5. Reject deployment if VRAM spill, fallback, or another server process is
   present.
6. Run a deep-context probe if the launch context changed.
