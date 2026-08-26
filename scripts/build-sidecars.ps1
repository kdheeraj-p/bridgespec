# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string] $RocmPath = $(if ($env:HIP_PATH) { $env:HIP_PATH } else { 'C:\Program Files\AMD\ROCm\7.2' }),
    [string] $Architecture = 'gfx1100',
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'out' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
$hipcc = Join-Path $RocmPath 'bin\hipcc.exe'

if (-not (Test-Path -LiteralPath $hipcc -PathType Leaf)) {
    throw "hipcc was not found at $hipcc. Pass -RocmPath explicitly."
}
foreach ($source in @(
    (Join-Path $repo 'src\mtp\sidecar.hip'),
    (Join-Path $repo 'src\dflash\dflash_sidecar.hip')
)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "source file not found: $source" }
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

$targets = @(
    @{
        Name = 'MTP'
        Source = Join-Path $repo 'src\mtp\sidecar.hip'
        Output = Join-Path $output 'spec_hip_sidecar.dll'
    },
    @{
        Name = 'DFlash'
        Source = Join-Path $repo 'src\dflash\dflash_sidecar.hip'
        Output = Join-Path $output 'spec_dflash_sidecar.dll'
    }
)

foreach ($target in $targets) {
    Write-Host "Building $($target.Name) sidecar for $Architecture"
    & $hipcc `
        "--offload-arch=$Architecture" `
        -O3 `
        -std=c++17 `
        -shared `
        $target.Source `
        -o $target.Output
    if ($LASTEXITCODE -ne 0) {
        throw "$($target.Name) sidecar build failed with exit code $LASTEXITCODE"
    }
}

Get-ChildItem -LiteralPath $output -Filter '*.dll' |
    Select-Object Name, Length, LastWriteTime
