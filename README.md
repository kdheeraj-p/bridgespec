# BridgeSpec

[![Source checks](https://github.com/kdheeraj-p/bridgespec/actions/workflows/source-checks.yml/badge.svg)](https://github.com/kdheeraj-p/bridgespec/actions/workflows/source-checks.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Experimental AMD RDNA3 speculative decoding for `llama.cpp`: HIP MTP and
DFlash drafter sidecars, tooling for generated sliced vocabulary heads, and
tuned small-batch MMVQ kernels for `gfx1100`.

> **Status: research preview.** The validated system is Windows 11, one RX
> 7900 XTX, ROCm 7.2, and Qwen3.8-27B. It is not a general-purpose inference
> runtime yet. Model weights and compiled binaries are deliberately not
> distributed.

BridgeSpec grew out of a practical question: if a 7900 XTX can decode this
model at roughly the same raw rate as a competing GPU, where does speculative
throughput disappear? The project isolates that loss at the drafter/runtime
boundary, moves the serial drafter into HIP, and tunes the target verifier for
RDNA3's small, wide batches.

## What is included

- A Qwen3.8-27B MTP HIP sidecar with external KV state and a three-token draft.
- A five-layer DFlash HIP sidecar with graph-captured block drafting.
- Tooling to generate a 40,960-row sliced draft head and deterministic
  full-vocabulary ID remap from user-supplied models.
- A pinned `llama.cpp` integration patch set.
- `gfx1100` MMVQ tuning for verification widths 2-8 and focused correctness
  tests.
- Parameterized tools to produce all runtime assets from user-supplied GGUFs.
- A controlled local benchmark summary, methodology, failures, and operational
  limits.
- Two standalone Windows Vulkan/HIP interop experiments. The production
  sidecars are host-mediated; they do **not** currently use zero-copy interop.

## Results at a glance

All values below are decode-only token rates on one RX 7900 XTX. Prompt
processing and time-to-first-token are excluded. Workload, cache state,
context, and acceptance materially affect the result.

| Evidence class | Configuration | Code | Agentic edit | Prose |
|---|---:|---:|---:|---:|
| Controlled local A/B | Vulkan MTP control | 104.5 | 117.7 | - |
| Controlled local A/B | Vulkan target + HIP MTP | **106.9** | **120.7** | - |
| Development high-water | Tuned HIP DFlash | **109.4** | **146.0** | 56.8 |
| Cache-correct release candidate | HIP DFlash | 84.2 | 111.8-112.4 | 43.7 |

The 146 tok/s result is a fixed-prompt development high-water with 95.5%
acceptance. It is not production-wide throughput; the prose counterexample is
shown beside it intentionally. The strongest public comparison is the
counterbalanced MTP A/B: 10 correlated requests per configuration and workload,
two process launches per configuration, with byte-identical outputs.

See [the benchmark guide](benchmarks/README.md) and the local-summary
[CSV](benchmarks/data/qwen38-27b-rx7900xtx.csv) before quoting a number. The
repository does not include the raw per-request logs or a public benchmark
harness, so these measurements are not a claim of cross-machine
reproducibility.

> **Publishing source:** do not upload a raw ZIP of a development workspace.
> Ignored model artifacts, external checkouts, build products, and DLLs can be
> included accidentally and may embed local paths. Use GitHub's source archive
> or [`scripts/export-source.ps1`](scripts/export-source.ps1), which archives
> only tracked files from a selected commit.

## Which profile should I use?

| Profile | Best fit | Validated shape | Important trade-off |
|---|---|---|---|
| MTP sidecar | General code, reasoning, prose, daily use | Vulkan target, `n=3` | Smaller uplift, strongest workload floor |
| DFlash sidecar | Predictable edits and structured code | HIP target, block 8 | Large upside when acceptance is high; weak prose floor |
| Plain target | Debugging and correctness control | Vulkan or HIP | Approximately 40-45 tok/s on this model |

Do not co-reside the two 27B profiles on a 24 GB card. Shared-memory spill can
reduce throughput dramatically without producing an obvious out-of-memory
error.

## Architecture

```text
OpenAI-compatible client
          |
          v
patched llama-server
          |
          +---- target prefill / target verification (Vulkan or HIP)
          |                       |
          |              hidden features + positions
          |                       |
          |                       v
          |              BridgeSpec C sidecar ABI
          |                       |
          |              HIP MTP or DFlash drafter
          |                       |
          +<------------- proposed token IDs
          |
          v
target accepts only the verified prefix
```

The drafter proposes; the target remains authoritative. A rejected draft does
not change the model's intended output. That protects committed tokens, but it
does not make state bugs harmless: cache restore, sequence forking, context
shift, and multi-slot operation remain unsupported until the sidecar gets a
real lifecycle API.

Read [Architecture](docs/architecture.md) and
[State and correctness](docs/correctness.md) for the detailed contracts.

## Tested platform

| Component | Tested value |
|---|---|
| OS | Windows 11 Pro |
| GPU | Radeon RX 7900 XTX 24 GB (`gfx1100`, wave32) |
| AMD driver | PRO 32.0.31041.1004 |
| ROCm/HIP SDK | 7.2.60201 |
| HIP compiler | clang 21 |
| Vulkan SDK | 1.4.357.0 |
| CMake / Ninja | 4.4.2 / 1.13.2 |
| Python | 3.12.10 |
| C++ toolchain | Visual Studio 2022 Build Tools + Windows SDK |

Other GPUs, Linux, multiple GPUs, multiple slots, and later ROCm versions are
not yet validated. The kernels contain Qwen3.8-27B dimensions; they are not
drop-in kernels for arbitrary models.

## Quick start

### 1. Install prerequisites

Install:

- Git, Python 3.10+, CMake, Ninja, and Visual Studio 2022 Build Tools.
- The AMD HIP SDK / ROCm 7.2 for Windows.
- The Vulkan SDK if you want the MTP/Vulkan target profile.
- Enough free disk for a source checkout, a 16 GB target GGUF, model-derived
  artifacts, and build output.

Clone BridgeSpec:

```powershell
git clone https://github.com/kdheeraj-p/bridgespec.git
Set-Location .\bridgespec
```

### 2. Fetch the pinned `llama.cpp` base and apply patches

The integration is based on an intermediate commit from upstream PR #27342,
not current `master`. Fetch the PR ref explicitly:

```powershell
git clone https://github.com/kdheeraj-p/llama.cpp.git .\external\llama.cpp
git -C .\external\llama.cpp remote add upstream https://github.com/ggml-org/llama.cpp.git
git -C .\external\llama.cpp fetch upstream `
  refs/pull/27342/head:refs/remotes/bridgespec/pr-27342
git -C .\external\llama.cpp checkout --detach `
  f5a7ec15da6add890a5624c0990714498df837a4

.\scripts\apply-llama-patches.ps1 `
  -LlamaCppPath .\external\llama.cpp
```

The default applies the sidecar integration and `gfx1100` MMVQ tuning. Pass
`-IncludeVulkanExperiments` only when reproducing rejected/unfinished Vulkan
experiments.

### 3. Build the sidecars and patched server

```powershell
.\scripts\build-sidecars.ps1 `
  -RocmPath 'C:\Program Files\AMD\ROCm\7.2'

# HIP target: required for the DFlash profile.
.\scripts\build-llama.ps1 `
  -LlamaCppPath .\external\llama.cpp `
  -Backend HIP

# Vulkan target: validated daily-driver target for the MTP profile.
.\scripts\build-llama.ps1 `
  -LlamaCppPath .\external\llama.cpp `
  -Backend Vulkan
```

The sidecar build is source-only and produces DLLs under `out/`, which is
ignored by Git.

### 4. Prepare model-derived assets

Install the matching `gguf-py` from the pinned `llama.cpp` checkout:

```powershell
python -m pip install -e .\external\llama.cpp\gguf-py
```

Historical runs used the Apache-2.0 draft vocabulary published by `syv-ai` at
commit `c954724104a7856a07abb7031cc4af780ae7f5bf`. BridgeSpec does not bundle
the list or its converted binary:

```powershell
New-Item -ItemType Directory -Force .\artifacts | Out-Null
Invoke-WebRequest `
  'https://raw.githubusercontent.com/syv-ai/qwen38-27b-rtx3090/c954724104a7856a07abb7031cc4af780ae7f5bf/prepare/draft_vocab_ids.json' `
  -OutFile .\artifacts\draft_vocab_ids.json
```

Prepare MTP assets and an MTP-ready target GGUF:

```powershell
python .\tools\prepare_assets.py mtp `
  --target D:\models\Qwen3.8-27B-Q4_0.gguf `
  --ids .\artifacts\draft_vocab_ids.json `
  --output .\artifacts\mtp

python .\tools\validate_assets.py mtp .\artifacts\mtp
```

Prepare DFlash assets:

```powershell
python .\tools\prepare_assets.py dflash `
  --target D:\models\Qwen3.8-27B-Q4_0.gguf `
  --draft D:\models\Qwen3.8-27B-DFlash2-Q4_K_M.gguf `
  --ids .\artifacts\draft_vocab_ids.json `
  --output .\artifacts\dflash

python .\tools\validate_assets.py dflash .\artifacts\dflash
```

The tools read local model files and create local derivative blobs. Review the
target, drafter, and vocabulary licenses yourself. See
[Artifact preparation](docs/artifact-preparation.md) for exact files, sizes,
and failure modes.

### 5. Run MTP

Use the Vulkan build's `llama-server.exe`, the GGUF created by the `mtp`
preparation command, and the MTP DLL:

```powershell
.\scripts\launch-mtp.example.ps1 `
  -Server .\external\llama.cpp\build-bridgespec-vulkan\bin\Release\llama-server.exe `
  -Model .\artifacts\mtp\Qwen3.8-27B-Q4_0-bridgespec.gguf `
  -Sidecar .\out\spec_hip_sidecar.dll `
  -Artifacts .\artifacts\mtp `
  -Context 16384 `
  -KvType q4_0 `
  -Port 8081
```

For the recorded controlled 16K/F16 A/B shape, pass `-KvType f16`. The
preserved daily profile used `q4_0` KV to reduce VRAM use.

### 6. Run DFlash

Use the HIP build and keep the DFlash GGUF on CPU (`-ngld 0`); the sidecar
loads the extracted HIP weights:

```powershell
.\scripts\launch-dflash.example.ps1 `
  -Server .\external\llama.cpp\build-bridgespec-hip\bin\llama-server.exe `
  -TargetModel D:\models\Qwen3.8-27B-Q4_0.gguf `
  -DraftModel D:\models\Qwen3.8-27B-DFlash2-Q4_K_M.gguf `
  -Sidecar .\out\spec_dflash_sidecar.dll `
  -Artifacts .\artifacts\dflash `
  -Context 16384 `
  -Port 8082
```

Run only one 27B profile at a time on a 24 GB GPU.

### 7. Send a smoke request

```powershell
$body = @{
  model = 'Qwen3.8-27B-BridgeSpec-MTP'
  messages = @(@{ role = 'user'; content = 'Write merge sort in Python.' })
  temperature = 0
  top_k = 1
  max_tokens = 256
} | ConvertTo-Json -Depth 5

Invoke-RestMethod `
  -Uri http://127.0.0.1:8081/v1/chat/completions `
  -Method Post `
  -ContentType 'application/json' `
  -Body $body
```

Greedy sampling is used for deterministic parity comparisons and peak
acceptance. Sampling temperature can materially reduce speculative acceptance
and tok/s.

## Runtime invariants

Every supported launch uses:

```text
-np 1
--no-context-shift
--ctx-checkpoints 0
--cache-ram 0
--no-cache-idle-slots
```

These are correctness constraints, not cosmetic tuning. The current sidecars
are process-singletons with no reset/save/restore/fork/shift/free API. Prompt
cache restore, context shifting, multiple slots, and sequence forks can desync
sidecar state.

The integration validates model dimensions and permanently disables a sidecar
after a runtime error. The target still verifies committed tokens, but fallback
is a degraded safety path—not a substitute for the runtime invariants above.

## Patch set

| Patch | Default | Status |
|---|---:|---|
| `0001-qwen38-speculative-sidecar-integration.patch` | Yes | Research integration; also contains off-by-default native chain experiments |
| `0002-gfx1100-wide-mmvq-tuning.patch` | Yes | Cleanest upstream candidate; widths 2-8 + focused tests |
| `0003-vulkan-wide-verify-experiments.patch` | No | Archived negative/incomplete experiments |

All patches apply to the exact revision in
[`BASE_REVISION`](integrations/llama.cpp/BASE_REVISION). They are intentionally
not advertised against current `llama.cpp` master.

## Known limitations

- Qwen3.8-27B dimensions and tensor layouts are hard-coded.
- Windows + `gfx1100` is the only validated platform.
- Sidecars are singleton and non-thread-safe.
- State lifecycle operations are not implemented.
- The integrated path is host-mediated, not Vulkan/HIP zero-copy.
- DFlash throughput is highly workload- and cache-dependent.
- The MTP parity replay reached 997/999 tokens; DFlash reached 1,587/1,589.
  Near-tie quantization differences can alter draft guesses while target
  verification preserves committed-token correctness.
- The source retains some instrumentation and experimental code by design.
- No official prebuilt binaries or model derivatives are published.

See [Troubleshooting](docs/troubleshooting.md) and
[Negative results](docs/negative-results.md) before opening a performance bug.

## Repository map

```text
src/                         HIP sidecars and kernels
include/bridgespec/          C ABI declaration
integrations/llama.cpp/      pinned patch series and integration notes
tools/                       GGUF preparation and artifact validation
scripts/                     safe Windows build/apply/launch examples
benchmarks/                  public data and methodology
experiments/windows-interop/ standalone interop feasibility spikes
docs/                        architecture, operations, findings, roadmap
LICENSES/                    third-party license texts
```

## Documentation

- [Acknowledgements and research references](ACKNOWLEDGEMENTS.md)
- [Architecture](docs/architecture.md)
- [Artifact preparation](docs/artifact-preparation.md)
- [Windows build and integration](docs/windows-build.md)
- [State, correctness, and safety](docs/correctness.md)
- [Benchmark methodology](benchmarks/README.md)
- [Research findings](docs/findings.md)
- [Negative results](docs/negative-results.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Roadmap](docs/roadmap.md)

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Performance PRs intended for
independent reproduction need a pinned base, exact command, workload, context,
KV type, acceptance, per-run numbers, and correctness comparison. A tok/s
number without those fields is not actionable.

Security and unsafe runtime-state issues should follow
[SECURITY.md](SECURITY.md).

## Acknowledgements

BridgeSpec builds on the work of the `llama.cpp`/ggml community, the Qwen
team, the DFlash authors and Inco AI, and the wider AMD local-inference
community. We specifically credit HipFire, Splizard's gfx1100 work,
qwen38-mtp, syv-ai, LocalMaxxing, and the upstream llama.cpp experiments that
helped shape or test this investigation.

See [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md) for named contributors, exact
repositories, and the distinction between incorporated source/data and
independent research references.

## License and attribution

Original BridgeSpec source is MIT licensed. The `llama.cpp` integration
modifies MIT-licensed `llama.cpp`/ggml code. Model artifacts and the historical
draft vocabulary are external Apache-2.0 inputs and are not included.

Read [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and `LICENSES/` for exact
credit and provenance. Acknowledgement does not imply endorsement by any
named contributor, project, or organization.

Development used AI-assisted coding, analysis, and documentation under human
direction. Performance claims in this repository are tied to retained local
measurements and are labeled by evidence quality; speculative projections are
not presented as measured results.
