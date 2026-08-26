# Security policy

## Supported versions

Only the current `main` branch is maintained. BridgeSpec is a research preview
and should not be exposed directly to untrusted networks.

## Reporting

Report a vulnerability privately through GitHub's security-advisory feature
for `kdheeraj-p/bridgespec`. Do not attach proprietary prompts, model weights,
credentials, or complete server logs to a public issue.

Useful details include the commit, platform, minimal reproduction, expected
impact, and whether the issue crosses the local-process trust boundary.

## Scope notes

- Example launchers bind to `127.0.0.1` and provide no authentication.
- Keep the server executable, sidecar DLL, ROCm runtime, and all of their
  parent directories user-controlled and not writable by untrusted accounts.
  The launchers resolve these paths and run from the server directory to reduce
  current-directory DLL planting risk; they do not make hostile paths safe.
- The sidecar C ABI accepts raw pointers and assumes the patched host validates
  dimensions and lifecycle.
- Model and artifact parsers operate on trusted local files; hardening against
  adversarial GGUF/manifest input is incomplete.
- Sidecar fallback protects target-token verification but is not a memory
  safety boundary.

## Publication hygiene

Do not publish a raw ZIP of a development workspace. Ignored directories can
contain model derivatives, external source checkouts, compiled binaries, logs,
or machine-specific paths even when `git status` is clean. Publish a GitHub
source archive or run `scripts/export-source.ps1`; both operate on a reviewed
Git commit rather than the surrounding workspace. Inspect the resulting
archive before distributing it.
