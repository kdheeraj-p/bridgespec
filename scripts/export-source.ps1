# SPDX-License-Identifier: MIT

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Revision = 'HEAD',
    [string] $OutputPath,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

$commitOutput = & git -C $repo rev-parse --verify --end-of-options "$Revision^{commit}" 2>$null
$revisionExit = $LASTEXITCODE
$commit = ($commitOutput -join '').Trim()
if ($revisionExit -ne 0 -or -not $commit) {
    throw "revision does not resolve to a commit: $Revision"
}
$shortOutput = & git -C $repo rev-parse --short=12 $commit
$shortExit = $LASTEXITCODE
$short = ($shortOutput -join '').Trim()
if ($shortExit -ne 0 -or -not $short) { throw 'failed to abbreviate commit ID' }
$workspaceChanges = & git -C $repo status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'failed to inspect workspace status' }
if ($workspaceChanges) {
    Write-Warning "Workspace changes are omitted; this archive contains commit $commit only."
}

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path -Parent $repo) "bridgespec-source-$short.zip"
}
$archive = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($archive) -ne '.zip') {
    throw 'source archive output must use the .zip extension'
}
if (Test-Path -LiteralPath $archive) {
    $existing = Get-Item -LiteralPath $archive -Force
    if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "refusing to replace a linked output path: $archive"
    }
    if (-not $Force) {
        throw "output already exists; pass -Force to replace it: $archive"
    }
}
$parent = Split-Path -Parent $archive
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw "output directory does not exist: $parent"
}

if ($PSCmdlet.ShouldProcess($archive, "archive tracked files from commit $commit")) {
    & git -C $repo archive `
        --format=zip `
        "--prefix=bridgespec-$short/" `
        "--output=$archive" `
        $commit
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
    Write-Host "Wrote tracked-source archive: $archive"
    Write-Host 'Inspect the archive before distributing it.'
}
