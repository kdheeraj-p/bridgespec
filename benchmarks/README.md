# Local benchmark methodology and summary

These are controlled observations from the single Windows workstation listed
below. The repository retains a summary CSV, but not the raw per-request logs
or a public benchmark harness. Treat the numbers as a local research record,
not as a complete dataset or a claim of cross-machine reproducibility.

## Metric

`tok/s` is decode-only `timings.predicted_per_second` from `llama-server`
unless a row explicitly says otherwise. Prompt processing, model load, graph
capture, and time-to-first-token are excluded.

Acceptance is:

```text
draft_n_accepted / draft_n
```

Acceptance percentage alone is insufficient. A wide block with lower
percentage acceptance may accept more tokens per target verification cycle
than a narrow block with a higher percentage.

## Hardware and software

- Radeon RX 7900 XTX 24 GB, one GPU.
- Windows 11 Pro.
- AMD PRO driver 32.0.31041.1004.
- ROCm/HIP 7.2.60201 and Vulkan SDK 1.4.357.0.
- Qwen3.8-27B Q4_0 target; F16 or Q4_0 KV as recorded per row.
- One slot, greedy generation, reasoning off unless recorded otherwise.

## Evidence classes

### Controlled local MTP A/B

The headline MTP comparison used a counterbalanced stock-HIP-HIP-stock order,
two server processes per configuration, and five code plus five agentic
requests per configuration. Requests in a process are correlated; the report
therefore gives ranges rather than presenting all requests as independent
samples.

| Configuration | Workload | Mean tok/s | Range |
|---|---|---:|---:|
| Vulkan MTP | Code | 104.530 | 104.098-105.073 |
| HIP MTP sidecar | Code | **106.895** | 106.526-107.410 |
| Vulkan MTP | Agentic edit | 117.748 | 116.959-118.314 |
| HIP MTP sidecar | Agentic edit | **120.681** | 120.451-120.833 |

Outputs were byte-identical in this matrix. Context allocation was 16,384 and
target KV was F16.

### DFlash development high-water

| Workload | Median tok/s | Acceptance | Important caveat |
|---|---:|---:|---|
| Code | 109.448 | 66.76% | sequential same-process development run |
| Agentic edit | **146.040** | 95.52% | predictable fixed workload |
| Extended code | 112.677 | 68.96% | reasoning was off |
| Prose | 56.758 | 27.19% | demonstrates workload dependence |

These rows used 8K context, HIP target, F16 KV, `n_max=7` (width 8), greedy
sampling, and a 40,960-row head.

### Cache-correct DFlash candidate

When request cache reuse was disabled in the release-candidate process, the
recorded local observations were 84.2 from one code run, 111.8-112.4 across
three agentic runs, and 43.7 from one prose run. The single-run code and prose
figures do not establish run-to-run stability. Four forced full-reprefill
agentic diagnostics reached 134.5-138.7 tok/s but paid a large TTFT cost and
are not the default profile.

## RDNA3 MMVQ kernel evidence

- Width-8 verification: approximately 50.2 ms to 41.15 ms median (39.8 ms best).
- Width-4: 33.2 ms to 30.1 ms.
- Width-1: unchanged at approximately 24.7 ms.
- Focused CPU-vs-ROCm correctness: 192/192 cases across 23 MMVQ types.

The speedup came from tuning widths 2-8 for RDNA3 and folding gated-delta-net
channels into columns. It is not a universal GEMM result.

## Context curve

At a 131K allocation with Q4_0 KV, Vulkan MTP retained a modest advantage at
very deep positions: approximately 53.27 vs 50.56 tok/s near 98K, and 49.59 vs
46.35 near 127K. Around 49K the two were effectively tied in the frozen matrix.

## Reporting requirements for new runs

Every submitted result should record:

1. Commit and patch set.
2. GPU, driver, backend, and ROCm/Vulkan versions.
3. Exact target/drafter quant and hashes.
4. Context allocation and current token depth.
5. K/V types, batch size, slots, cache state, and reasoning state.
6. Sampling parameters.
7. Prompt hash or public prompt.
8. Per-run tok/s, draft attempted/accepted, output token count, and output hash.
9. Process ordering, warmup policy, and whether repeats share a process.

The machine-readable rows are in
[`data/qwen38-27b-rx7900xtx.csv`](data/qwen38-27b-rx7900xtx.csv).
