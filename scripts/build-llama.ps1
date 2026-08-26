# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $LlamaCppPath,

    [ValidateSet('HIP', 'Vulkan')]
    [string] $Backend = 'HIP',

    [string] $RocmPath = $(if ($env:HIP_PATH) { $env:HIP_PATH } else { 'C:\Program Files\AMD\ROCm\7.2' }),
    [string] $Architecture = 'gfx1100',
    [string] $BuildDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = [IO.Path]::GetFullPath($LlamaCppPath)
if (-not (Test-Path -LiteralPath (Join-Path $source 'CMakeLists.txt') -PathType Leaf)) {
    throw "llama.cpp source tree not found at $source"
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { throw 'cmake was not found on PATH' }
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $source ("build-bridgespec-" + $Backend.ToLowerInvariant())
}
$build = [IO.Path]::GetFullPath($BuildDirectory)

if ($Backend -eq 'HIP') {
    $clang = Join-Path $RocmPath 'bin\clang.exe'
    $clangxx = Join-Path $RocmPath 'bin\clang++.exe'
    if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) { throw 'ninja was not found on PATH' }
    foreach ($compiler in @($clang, $clangxx)) {
        if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "ROCm compiler not found: $compiler" }
    }
    $env:PATH = (Join-Path $RocmPath 'bin') + ';' + $env:PATH
    # Windows PowerShell 5.1 can misquote a native argument containing the
    # spaced ROCm path and concatenate every following -D option into its
    # value. Forward-slash CMake paths plus an argument array keep each option
    # atomic across Windows PowerShell and PowerShell 7.
    $rocmCmake = $RocmPath.Replace('\', '/')
    $clangCmake = $clang.Replace('\', '/')
    $clangxxCmake = $clangxx.Replace('\', '/')
    $configureArguments = @(
        '-S', $source,
        '-B', $build,
        '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release',
        "-DCMAKE_C_COMPILER:FILEPATH=$clangCmake",
        "-DCMAKE_CXX_COMPILER:FILEPATH=$clangxxCmake",
        "-DCMAKE_PREFIX_PATH:PATH=$rocmCmake",
        '-DGGML_HIP=ON',
        '-DGGML_VULKAN=OFF',
        "-DGPU_TARGETS=$Architecture",
        '-DGGML_OPENMP=OFF',
        '-DLLAMA_CURL=OFF',
        '-DLLAMA_BUILD_TESTS=ON',
        '-DLLAMA_BUILD_EXAMPLES=ON'
    )
    & cmake @configureArguments
} else {
    & cmake -S $source -B $build -G 'Visual Studio 17 2022' `
        -DGGML_VULKAN=ON `
        -DGGML_HIP=OFF `
        -DLLAMA_CURL=OFF `
        -DLLAMA_BUILD_TESTS=ON `
        -DLLAMA_BUILD_EXAMPLES=ON
}
if ($LASTEXITCODE -ne 0) { throw 'llama.cpp configure failed' }

$cache = Join-Path $build 'CMakeCache.txt'
$requiredBackendFlag = if ($Backend -eq 'HIP') { 'GGML_HIP' } else { 'GGML_VULKAN' }
if (-not (Test-Path -LiteralPath $cache -PathType Leaf) -or
    -not (Select-String -LiteralPath $cache -Pattern "^${requiredBackendFlag}:BOOL=ON$" -Quiet)) {
    throw "CMake completed without enabling the requested $Backend backend"
}

if ($Backend -eq 'HIP') {
    & cmake --build $build --target llama-server test-backend-ops --parallel 4
} else {
    & cmake --build $build --config Release --target llama-server test-backend-ops --parallel 4
}
if ($LASTEXITCODE -ne 0) { throw 'llama.cpp build failed' }
