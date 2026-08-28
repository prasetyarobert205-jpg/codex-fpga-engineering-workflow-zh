[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Get-CanonicalPath([string]$Path) {
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-ExcludedPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $relative = [IO.Path]::GetRelativePath($root, $full)
    if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('..\') -or $relative.StartsWith('../')) {
        throw "PATH_ESCAPE: '$full' resolves outside project root '$root'."
    }
    $segments = ($relative -replace '/', '\').Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
    $excluded = @('codex_out', 'release', 'old', 'backup', 'generated', '.runs', '.cache', 'work', 'logs', 'waves')
    foreach ($segment in $segments) {
        if ($excluded -contains $segment.ToLowerInvariant()) { return $true }
    }
    return $false
}

$root = Get-CanonicalPath $ProjectRoot
$scanRoots = @('project\par', 'project\ip', 'project\sdc') |
    ForEach-Object { Join-Path $root $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container }

if ($scanRoots.Count -eq 0) {
    throw 'UNKNOWN_VENDOR: none of project/par, project/ip, or project/sdc exists.'
}

$files = @($scanRoots | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -Recurse -File -ErrorAction Stop
} | Where-Object { -not (Test-ExcludedPath $_.FullName) })

$unsupported = @($files | Where-Object {
    $_.Extension.ToLowerInvariant() -in @('.qpf', '.qsf', '.gprj', '.ldf', '.prjx')
})
if ($unsupported.Count -gt 0) {
    $names = ($unsupported.FullName | ForEach-Object { [IO.Path]::GetRelativePath($root, $_) }) -join ', '
    throw "UNSUPPORTED_VENDOR: unsupported project evidence found: $names"
}

$evidence = [ordered]@{
    XILINX = [System.Collections.Generic.List[string]]::new()
    PANGO = [System.Collections.Generic.List[string]]::new()
    ANLOGIC = [System.Collections.Generic.List[string]]::new()
}
$authoritative = [ordered]@{
    XILINX = [System.Collections.Generic.List[string]]::new()
    PANGO = [System.Collections.Generic.List[string]]::new()
    ANLOGIC = [System.Collections.Generic.List[string]]::new()
}

foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    $isCanonicalProject = $relative -match '(?i)^project/par/[^/]+$'
    switch ($file.Extension.ToLowerInvariant()) {
        '.xpr' { $evidence.XILINX.Add($relative); if ($isCanonicalProject) { $authoritative.XILINX.Add($relative) } }
        '.xci' { $evidence.XILINX.Add($relative) }
        '.pds' { $evidence.PANGO.Add($relative); if ($isCanonicalProject) { $authoritative.PANGO.Add($relative) } }
        '.idf' { $evidence.PANGO.Add($relative) }
        '.al'  { $evidence.ANLOGIC.Add($relative); if ($isCanonicalProject) { $authoritative.ANLOGIC.Add($relative) } }
        '.ipc' {
            $reader = [IO.StreamReader]::new($file.FullName, $true)
            try {
                $buffer = New-Object char[] 16384
                $count = $reader.ReadBlock($buffer, 0, $buffer.Length)
                $header = -join $buffer[0..([Math]::Max(0, $count - 1))]
            } finally {
                $reader.Dispose()
            }
            if ($header -match '(?i)Anlogic|TD_Version|\bEG[0-9A-Za-z_-]+\b') {
                $evidence.ANLOGIC.Add($relative)
            }
        }
    }
}

$authoritativeVendors = @($authoritative.Keys | Where-Object { $authoritative[$_].Count -gt 0 })
$vendors = @(if ($authoritativeVendors.Count -gt 0) {
    # A canonical project file is stronger than imported/stale IP evidence.
    # Fallback IP suffixes are considered only when no canonical project exists.
    $authoritativeVendors
} else {
    @($evidence.Keys | Where-Object { $evidence[$_].Count -gt 0 })
})
if ($vendors.Count -eq 0) {
    throw 'UNKNOWN_VENDOR: no supported Xilinx, Pango, or Anlogic project/IP evidence was found.'
}
if ($vendors.Count -gt 1) {
    $detail = ($vendors | ForEach-Object { "$_=[$($evidence[$_] -join ', ')]" }) -join '; '
    throw "VENDOR_CONFLICT: evidence for multiple supported vendors was found: $detail"
}

$vendor = $vendors[0]
$projectFiles = @($authoritative[$vendor])
$requiresExplicitProject = $false
if ($projectFiles.Count -gt 1 -and $vendor -eq 'PANGO') {
    $preferred = @($projectFiles | Where-Object { $_.Replace('\', '/').ToLowerInvariant() -eq 'project/par/pds_script.pds' })
    if ($preferred.Count -eq 1) {
        $projectFiles = $preferred
    } else {
        $projectFiles = @()
        $requiresExplicitProject = $true
    }
} elseif ($projectFiles.Count -gt 1) {
    throw "TARGET_CONFLICT: multiple authoritative $vendor project files were found: $($projectFiles -join ', ')"
}

$result = [pscustomobject]@{
    schema_version = '0.3'
    status = 'DETECTED'
    vendor = $vendor
    project_root = $root
    authoritative_project = if ($projectFiles.Count -eq 1) { $projectFiles[0] } else { $null }
    requires_explicit_project_file = $requiresExplicitProject
    evidence = @($evidence[$vendor])
    adapter = $vendor.ToLowerInvariant()
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
} else {
    $result
}
