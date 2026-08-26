# SPDX-License-Identifier: MIT

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $LlamaCppPath,

    [switch] $IncludeVulkanExperiments
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$llama = [IO.Path]::GetFullPath($LlamaCppPath)
$base = (Get-Content -LiteralPath (Join-Path $repo 'integrations\llama.cpp\BASE_REVISION') -Raw).Trim()

$inside = (& git -C $llama rev-parse --is-inside-work-tree 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') {
    throw "$llama is not a Git checkout"
}
$head = (& git -C $llama rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $base) {
    throw "llama.cpp must be checked out at $base; current HEAD is $head"
}
$dirty = & git -C $llama status --porcelain
if ($dirty) {
    throw 'llama.cpp has local changes. Apply BridgeSpec to a clean checkout.'
}

$patches = @(
    (Join-Path $repo 'integrations\llama.cpp\patches\0001-qwen38-speculative-sidecar-integration.patch'),
    (Join-Path $repo 'integrations\llama.cpp\patches\0002-gfx1100-wide-mmvq-tuning.patch')
)
if ($IncludeVulkanExperiments) {
    $patches += Join-Path $repo 'integrations\llama.cpp\patches\0003-vulkan-wide-verify-experiments.patch'
}

& git -C $llama apply --check @patches
if ($LASTEXITCODE -ne 0) { throw 'Patch-set check failed; nothing was applied' }

if ($PSCmdlet.ShouldProcess($llama, "apply $($patches.Count) BridgeSpec patch(es)")) {
    & git -C $llama apply @patches
    if ($LASTEXITCODE -ne 0) { throw 'Patch-set apply failed' }
    & git -C $llama status --short
}
