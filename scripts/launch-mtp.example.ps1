# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Model,
    [Parameter(Mandatory)] [string] $Sidecar,
    [Parameter(Mandatory)] [string] $Artifacts,
    [string] $RocmPath = $(if ($env:HIP_PATH) { $env:HIP_PATH } else { 'C:\Program Files\AMD\ROCm\7.2' }),
    [ValidateSet('q4_0', 'f16')] [string] $KvType = 'q4_0',
    [ValidateRange(512, 131072)] [int] $Context = 16384,
    [ValidateRange(1, 65535)] [int] $Port = 8081
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$conflicting = @(
    'LLAMA_SPEC_HIP_SIDECAR', 'LLAMA_SPEC_HIP_WEIGHTS', 'LLAMA_DRAFT_HEAD_IDS',
    'LLAMA_SPEC_HIP_DFLASH', 'LLAMA_SPEC_HIP_DFLASH_DIR', 'LLAMA_SPEC_CHAIN_LEAN',
    'LLAMA_SPEC_DUMP', 'LLAMA_SPEC_HIP_DEBUG', 'LLAMA_SPEC_HIP_FAULT_BADID',
    'LLAMA_SPEC_HIP_FULL_CATCHUP', 'LLAMA_SPEC_HIP_FULL_HEAD',
    'LLAMA_SPEC_HIP_NOEXTRACT', 'LLAMA_SPEC_HIP_NODRAFT', 'LLAMA_SPEC_HIP_P_MIN',
    'LLAMA_SPEC_HIP_MAX_POS'
)
$originalEnvironment = @{}
foreach ($name in @('PATH') + $conflicting) {
    $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    $originalEnvironment[$name] = [pscustomobject]@{
        Exists = $null -ne $item
        Value = if ($null -ne $item) { $item.Value } else { $null }
    }
}
$locationPushed = $false
try {
foreach ($name in $conflicting) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
$Server = [IO.Path]::GetFullPath($Server)
$Model = [IO.Path]::GetFullPath($Model)
$Sidecar = [IO.Path]::GetFullPath($Sidecar)
$Artifacts = [IO.Path]::GetFullPath($Artifacts)
$RocmPath = [IO.Path]::GetFullPath($RocmPath)
$required = @(
    $Server,
    $Model,
    $Sidecar,
    (Join-Path $Artifacts 'drafter_manifest.json'),
    (Join-Path $Artifacts 'drafter_weights.bin'),
    (Join-Path $Artifacts 'draft_head_ids.bin')
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file not found: $path" }
}
$listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if ($listener) { throw "TCP port $Port is already in use by PID(s): $($listener.OwningProcess -join ', ')" }
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'python was not found on PATH' }
& python (Join-Path $repo 'tools\validate_assets.py') mtp $Artifacts
if ($LASTEXITCODE -ne 0) { throw 'MTP artifact validation failed' }
$hipRuntime = Join-Path $RocmPath 'bin\amdhip64_7.dll'
if (-not (Test-Path -LiteralPath $hipRuntime -PathType Leaf)) { throw "ROCm HIP runtime not found: $hipRuntime" }
$env:PATH = (Join-Path $RocmPath 'bin') + ';' + $env:PATH
Push-Location -LiteralPath (Split-Path -Parent $Server)
$locationPushed = $true
$devices = (& $Server --list-devices 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0 -or $devices -notmatch 'Vulkan0') {
    throw 'This MTP example requires a Vulkan-enabled llama-server exposing Vulkan0'
}
$env:LLAMA_SPEC_HIP_SIDECAR = [IO.Path]::GetFullPath($Sidecar)
$env:LLAMA_SPEC_HIP_WEIGHTS = [IO.Path]::GetFullPath($Artifacts)
$env:LLAMA_DRAFT_HEAD_IDS = [IO.Path]::GetFullPath((Join-Path $Artifacts 'draft_head_ids.bin'))
$env:LLAMA_SPEC_HIP_MAX_POS = [string]$Context

& $Server `
    -m $Model `
    --device Vulkan0 `
    -ngl 999 `
    --fit off `
    -c $Context `
    -np 1 `
    --no-context-shift `
    --ctx-checkpoints 0 `
    --cache-ram 0 `
    --no-cache-idle-slots `
    -fa on `
    -ctk $KvType `
    -ctv $KvType `
    --jinja `
    -bs `
    --reasoning off `
    --spec-type draft-mtp `
    --spec-draft-device Vulkan0 `
    --spec-draft-ngl all `
    --spec-draft-n-max 3 `
    --spec-draft-p-min 0 `
    --host 127.0.0.1 `
    --port $Port `
    --alias Qwen3.8-27B-BridgeSpec-MTP
if ($LASTEXITCODE -ne 0) { throw "llama-server exited with code $LASTEXITCODE" }
} finally {
    if ($locationPushed) { Pop-Location }
    foreach ($name in @('PATH') + $conflicting) {
        $previous = $originalEnvironment[$name]
        $value = if ($previous.Exists) { [string]$previous.Value } else { $null }
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
}
