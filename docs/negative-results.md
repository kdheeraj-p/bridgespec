# Negative and null results

Recording failed ideas prevents repeated benchmark folklore.

| Experiment | Result | Lesson |
|---|---|---|
| DFlash2 vs MTP at depth 3 on early Vulkan profile | Tie near 90 tok/s | Earlier DFlash loss was an `n=4` + `p_min` artifact |
| Native Vulkan chain/fusion | Slower | Saved submits did not repay graph rebuild/allocation costs |
| Q4_0 weight-stationary verifier rewrite | Null | Compiler/path had already captured most intended reuse |
| Force K-quant wide path to GEMM | Regression | Alternative route was also poorly tuned for the shape |
| Halve K-quant rows/workgroup at wide width | Regression | Wrong bottleneck for that drafter path |
| Full GQA group-of-six attention staging | Regression | LDS footprint reduced occupancy |
| HIP graph for already-pipelined MTP drafts | Small expected gain | Wall-GPU gap was only about 0.09 ms |
| Full 248K DFlash head | Rejected | More VRAM/compute without enough acceptance benefit |
| Plain `n_max=16` in llama.cpp | Not a real B16 path | Controller trained block and verifier scaling constrain it |
| [HipFire](https://github.com/warpfront/hipfire) Windows one-shot/resident tests at [`3307ccf`](https://github.com/warpfront/hipfire/commit/3307ccf635822ef7ab3ac19b6ff98cb3ba6deb01) (local observation, 2026-08-26) | 28-40 tok/s | The referenced structured-code record did not reproduce on those tested Windows artifacts |
| MMQ/rocBLAS routing alone | No win | Both candidate paths were poorly matched before MMVQ tuning |
| Gate+up fusion at wide columns | Regression | Increased compute pressure outweighed dispatch reduction |

The archived Vulkan patch preserves the exact experimental change; it is not a
recommendation to enable every branch.
