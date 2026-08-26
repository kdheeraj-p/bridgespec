# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string] $LlamaCppPath,
    [switch] $BuildSidecars,
    [string] $RocmPath = $(if ($env:HIP_PATH) { $env:HIP_PATH } else { 'C:\Program Files\AMD\ROCm\7.2' })
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = [Collections.Generic.List[string]]::new()
$forbiddenPublishedPath = '(?i)(^|/)(?:\.env(?:\..*)?|id_(?:rsa|dsa|ecdsa|ed25519)|credentials(?:\..*)?|secrets?(?:\..*)?)$|(^|/)(?:logs?|transcripts?|captures?|dumps?)(?:/|$)|(^|/)(?:server|request|response|chat|conversation|transcript)[^/]*\.(?:json|jsonl|ndjson|txt|md)$|\.(?:gguf|safetensors|pt|pth|onnx|ckpt|bin|dll|exe|pdb|obj|lib|hsaco|so|dylib|a|o|wasm|zip|7z|rar|tar|gz|bz2|xz|log|jsonl|ndjson|sqlite|sqlite3|db|npy|npz|pkl|pickle|joblib|h5|hdf5|raw|dat)$'

function Test-NulBytePrefix([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = [byte[]]::new(8192)
        $count = $stream.Read($buffer, 0, $buffer.Length)
        return $count -gt 0 -and [Array]::IndexOf($buffer, [byte]0, 0, $count) -ge 0
    } finally {
        $stream.Dispose()
    }
}

Write-Host 'Checking tracked-source candidates for oversized or prohibited files'
$candidates = & git -C $repo ls-files --cached --others --exclude-standard
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed' }
$large = foreach ($relative in $candidates) {
    $candidate = Join-Path $repo $relative
    if ($relative.Replace('\', '/') -match $forbiddenPublishedPath) {
        $failures.Add("prohibited source candidate: $relative")
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $item = Get-Item -LiteralPath $candidate
        if ($item.Length -gt 20MB) { $item }
        if (Test-NulBytePrefix $candidate) {
            $failures.Add("binary source candidate: $relative")
        }
    }
}
foreach ($file in $large) { $failures.Add("oversized file: $($file.FullName) ($($file.Length) bytes)") }

Write-Host 'Scanning the source tree for private paths and common credential markers'
$patterns = 'C:[\\/]+Users[\\/]+[^\\/\s\x22\x27<>]+|/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|\.lmstudio|github_pat_[A-Za-z0-9_]{20,}|gh[opsu]_[A-Za-z0-9]{20,}|hf_[A-Za-z0-9]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|Bearer[\x20\t]+[A-Za-z0-9._~+/-]{20,}|-----BEGIN\x20(?:[A-Z]+\x20)?PRIVATE\x20KEY-----'
$scanFiles = foreach ($relative in $candidates) {
    if ($relative.Replace('\', '/') -eq 'scripts/verify-source.ps1') { continue }
    $candidate = Join-Path $repo $relative
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate }
}
$scan = if ($scanFiles) { Select-String -LiteralPath $scanFiles -Pattern $patterns } else { @() }
if ($scan) {
    $formatted = $scan | ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line)" }
    $failures.Add("private/secret scan matches:`n$($formatted -join "`n")")
}

Write-Host 'Scanning every reachable Git revision for private paths and credential markers'
$historySecretMatches = [Collections.Generic.HashSet[string]]::new()
$commits = & git -C $repo rev-list --all
if ($LASTEXITCODE -ne 0) {
    $failures.Add('git rev-list failed during history secret scan')
} else {
    foreach ($commit in $commits) {
        $historyScan = & git -C $repo grep -I -n -P -e $patterns $commit -- . ':(exclude)scripts/verify-source.ps1' 2>$null
        $grepExit = $LASTEXITCODE
        if ($grepExit -eq 0) {
            foreach ($match in $historyScan) { [void]$historySecretMatches.Add($match) }
        } elseif ($grepExit -ne 1) {
            $failures.Add("git grep failed for revision $commit with exit code $grepExit")
        }
    }
}
if ($historySecretMatches.Count) {
    $failures.Add("private/secret matches in Git history:`n$(@($historySecretMatches) -join "`n")")
}

Write-Host 'Checking all reachable Git objects for oversized or prohibited binary/model files'
$historyLines = & git -C $repo rev-list --objects --all
if ($LASTEXITCODE -ne 0) {
    $failures.Add('git rev-list --objects failed during history object scan')
} else {
    $objectIds = [Collections.Generic.HashSet[string]]::new()
    $objectPaths = @{}
    foreach ($line in $historyLines) {
        if ($line -notmatch '^(?<oid>[0-9a-f]+)(?: (?<path>.+))?$') { continue }
        $oid = $Matches.oid
        [void]$objectIds.Add($oid)
        if ($Matches.path) {
            if (-not $objectPaths.ContainsKey($oid)) {
                $objectPaths[$oid] = [Collections.Generic.List[string]]::new()
            }
            $objectPaths[$oid].Add($Matches.path)
        }
    }
    $objectInfo = $objectIds | & git -C $repo cat-file --batch-check='%(objectname) %(objecttype) %(objectsize)'
    if ($LASTEXITCODE -ne 0) {
        $failures.Add('git cat-file failed during history object scan')
    } else {
        $historyObjectMatches = [Collections.Generic.HashSet[string]]::new()
        foreach ($info in $objectInfo) {
            if ($info -notmatch '^(?<oid>[0-9a-f]+) blob (?<size>\d+)$') { continue }
            $oid = $Matches.oid
            $size = [int64]$Matches.size
            $paths = if ($objectPaths.ContainsKey($oid)) { @($objectPaths[$oid]) } else { @('<unknown path>') }
            if ($size -gt 20MB) {
                [void]$historyObjectMatches.Add("oversized historical blob $oid ($size bytes): $($paths -join ', ')")
            }
            foreach ($path in $paths) {
                if ($path -match $forbiddenPublishedPath) {
                    [void]$historyObjectMatches.Add("prohibited historical file $oid ($size bytes): $path")
                }
            }
        }
        if ($historyObjectMatches.Count) {
            $failures.Add("binary/model files in Git history:`n$(@($historyObjectMatches) -join "`n")")
        }
    }
}

Write-Host 'Checking every reachable Git revision for binary content'
$binaryHistory = & git -C $repo log --all --numstat --format=
if ($LASTEXITCODE -ne 0) {
    $failures.Add('git log failed during history binary scan')
} else {
    $binaryHistoryPaths = [Collections.Generic.HashSet[string]]::new()
    foreach ($line in $binaryHistory) {
        if ($line -match '^-\s+-\s+(?<path>.+)$') {
            [void]$binaryHistoryPaths.Add($Matches.path)
        }
    }
    if ($binaryHistoryPaths.Count) {
        $failures.Add("binary content detected in Git history:`n$(@($binaryHistoryPaths) -join "`n")")
    }
}

Write-Host 'Parsing Python tools'
$pythonFiles = Get-ChildItem -LiteralPath (Join-Path $repo 'tools') -Filter '*.py' -File
foreach ($file in $pythonFiles) {
    & python -c "import ast,pathlib,sys; p=pathlib.Path(sys.argv[1]); ast.parse(p.read_text(encoding='utf-8'), filename=str(p))" $file.FullName
    if ($LASTEXITCODE -ne 0) { $failures.Add("Python parse failed: $($file.FullName)") }
}

Write-Host 'Checking relative Markdown links'
& python (Join-Path $repo 'tools\check_markdown_links.py') $repo
if ($LASTEXITCODE -ne 0) { $failures.Add('Markdown link check failed') }

Write-Host 'Parsing PowerShell scripts'
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo 'scripts') -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($error in $errors) { $failures.Add("PowerShell parse failed: $($file.Name): $error") }
}

if ($LlamaCppPath) {
    Write-Host 'Checking default patch set against llama.cpp'
    try {
        & (Join-Path $PSScriptRoot 'apply-llama-patches.ps1') `
            -LlamaCppPath $LlamaCppPath `
            -WhatIf
        & (Join-Path $PSScriptRoot 'apply-llama-patches.ps1') `
            -LlamaCppPath $LlamaCppPath `
            -IncludeVulkanExperiments `
            -WhatIf
    } catch {
        $failures.Add("llama.cpp patch check failed: $_")
    }
}

if ($BuildSidecars) {
    Write-Host 'Building both HIP sidecars'
    try {
        & (Join-Path $PSScriptRoot 'build-sidecars.ps1') -RocmPath $RocmPath
    } catch {
        $failures.Add("sidecar build failed: $_")
    }
}

if ($failures.Count) {
    throw "source verification failed with $($failures.Count) issue(s):`n$($failures -join "`n")"
}
Write-Host 'SOURCE VERIFIED'
