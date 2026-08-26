# Artifact preparation

BridgeSpec source contains no model weights. `tools/prepare_assets.py` creates
the runtime inputs from GGUFs already present on the user's machine.

The generated files shown below are output contracts, not bundled repository
assets. Keep them outside source archives and do not upload a raw workspace ZIP.

## Dependencies

```powershell
python -m pip install -e .\external\llama.cpp\gguf-py
```

Use the `gguf-py` package from the same pinned `llama.cpp` tree. The tools also
require NumPy.

## Draft vocabulary

The sidecars use exactly 40,960 unique IDs. Supply JSON (a raw array or
`{"ids": [...]}`) or little-endian int32. If the GGUF already embeds
`qwen35.nextn.draft_vocab_ids`, `--ids` may be omitted.

The historical list came from syv-ai commit
`c954724104a7856a07abb7031cc4af780ae7f5bf`. It is an external Apache-2.0 input
and is not copied into this repository.

## MTP contract

Input expectations:

- Qwen3.8-27B target GGUF.
- One next-token block (`blk.64` on the tested model).
- Q4_0 target embedding and quantized target/output machinery compatible with
  llama.cpp's Qwen3.8 conversion.

Output:

```text
mtp/
├── <target>-bridgespec.gguf   full target + sliced/requantized MTP head
├── drafter_manifest.json     17 tensor descriptors
├── drafter_weights.bin       approximately 1.07 GB
└── draft_head_ids.bin        exactly 163,840 bytes
```

The tool gathers 40,960 output-head rows, converts draft-only two-dimensional
weights in the next-token block to Q4_0, embeds the ID table into the GGUF, and
extracts the sidecar blob. The target trunk is copied without requantization.
The optional `--model-name` value is a filename only; directory and drive
components are rejected so the generated GGUF remains under `--output`.

## DFlash contract

Input expectations:

- Q4_0 Qwen3.8-27B target GGUF with a Q6_K output head.
- Five-layer Qwen3.8 DFlash2 Q4_K_M GGUF containing exactly 81 tensors.

Output:

```text
dflash/
├── dflash_manifest.json       81 tensor descriptors
├── dflash_weights.bin         approximately 1.13 GB
├── drafter_manifest.json      target embedding descriptor
├── drafter_weights.bin        Q4_0 token embedding, approximately 715 MB
├── target_head_sliced.bin     172,032,000 bytes
└── draft_head_ids.bin         163,840 bytes
```

`--full-head` additionally emits the roughly 1.04 GB full head for diagnostic
comparison. It is not the recommended profile.

## Validation

```powershell
python .\tools\validate_assets.py mtp .\artifacts\mtp --hash
python .\tools\validate_assets.py dflash .\artifacts\dflash --hash
```

The `--hash` option streams every blob and can take time. Save hashes alongside
benchmark results, not in a shared source commit containing private model
paths.

## Licensing and provenance

Generated blobs are derivatives of their source models. If you redistribute
them, record the original repository and revision, license, source hash,
generated hash, command, tool revision, and modification notice. BridgeSpec's
`.gitignore` blocks the common artifact extensions by default.
