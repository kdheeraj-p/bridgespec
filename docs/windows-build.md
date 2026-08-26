# Windows build and integration

## Toolchain

The tested build used ROCm/HIP 7.2, Visual Studio 2022 Build Tools, Windows
SDK, CMake, Ninja, and Vulkan SDK 1.4.357.0.

## Sidecar build

```powershell
.\scripts\build-sidecars.ps1 `
  -RocmPath 'C:\Program Files\AMD\ROCm\7.2' `
  -Architecture gfx1100
```

Equivalent direct commands:

```powershell
& 'C:\Program Files\AMD\ROCm\7.2\bin\hipcc.exe' `
  --offload-arch=gfx1100 -O3 -std=c++17 -shared `
  .\src\mtp\sidecar.hip -o .\out\spec_hip_sidecar.dll

& 'C:\Program Files\AMD\ROCm\7.2\bin\hipcc.exe' `
  --offload-arch=gfx1100 -O3 -std=c++17 -shared `
  .\src\dflash\dflash_sidecar.hip -o .\out\spec_dflash_sidecar.dll
```

Warnings about `dllexport` in the device pass and MSVC's `fopen/getenv`
deprecation were present in the validated build.

## Focused hardening tests

The manifest test is host-only; the argmax guard test requires the AMD GPU:

```powershell
$hipcc = 'C:\Program Files\AMD\ROCm\7.2\bin\hipcc.exe'
New-Item -ItemType Directory -Force .\out | Out-Null
& $hipcc -O2 -std=c++17 .\src\mtp\artifact_manifest_test.cpp `
  -o .\out\artifact_manifest_test.exe
& $hipcc --offload-arch=gfx1100 -O2 -std=c++17 `
  .\src\mtp\argmax_guard_test.hip -o .\out\argmax_guard_test.exe
.\out\artifact_manifest_test.exe
.\out\argmax_guard_test.exe
```

## Patched `llama.cpp`

Follow [the integration README](../integrations/llama.cpp/README.md), then:

```powershell
.\scripts\build-llama.ps1 -LlamaCppPath .\external\llama.cpp -Backend HIP
.\scripts\build-llama.ps1 -LlamaCppPath .\external\llama.cpp -Backend Vulkan
```

The HIP target build disables Vulkan and OpenMP and targets `gfx1100`. The
Vulkan target build is the validated MTP daily-driver profile. Even in that
profile, ROCm's `bin` directory must be on `PATH` so Windows can resolve the HIP
runtime when loading the sidecar DLL.

## Expected exports

MTP:

```text
spec_hip_release_abi
spec_hip_check
spec_hip_init
spec_hip_catchup
spec_hip_draft
```

DFlash:

```text
spec_dflash_release_abi
spec_dflash_check
spec_dflash_init
spec_dflash_chunk
spec_dflash_draft
```

Use `dumpbin /exports <dll>` from a Visual Studio Developer shell when
diagnosing a load failure.

## Apply-check failure

The patches are revision-pinned. If `git apply --check` fails:

1. Confirm the exact `BASE_REVISION`.
2. Confirm the checkout is clean.
3. Confirm Git did not rewrite the patch as CRLF.
4. Do not apply it to current master and manually choose conflict sides.
