[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$excludedSegments = @('codex_out', 'release', 'old', 'backup', '.git', '.runs', '.cache', 'work', 'generated')

function Test-ExcludedPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $relative = [IO.Path]::GetRelativePath($root, $full) -replace '\\', '/'
    $segments = $relative.Split('/', [StringSplitOptions]::RemoveEmptyEntries)
    return [bool]($segments | Where-Object { $_ -in $excludedSegments -or $_.EndsWith('.runs', [StringComparison]::OrdinalIgnoreCase) -or $_.EndsWith('.cache', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
}

function Get-Files([string]$Base, [string[]]$Extensions) {
    if (-not (Test-Path -LiteralPath $Base -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Base -Recurse -File | Where-Object {
        -not (Test-ExcludedPath $_.FullName) -and $_.Extension.ToLowerInvariant() -in $Extensions
    } | Sort-Object FullName)
}

function Add-Evidence([hashtable]$Map, [string]$Vendor, [string]$Kind, [IO.FileInfo]$File) {
    $Map[$Vendor].Add([ordered]@{
        kind = $Kind
        path = ([IO.Path]::GetRelativePath($root, $File.FullName) -replace '\\', '/')
    })
}

$evidence = @{
    XILINX = [Collections.Generic.List[object]]::new()
    PANGO = [Collections.Generic.List[object]]::new()
    ANLOGIC = [Collections.Generic.List[object]]::new()
}

$parRoot = Join-Path $root 'project\par'
foreach ($file in Get-Files -Base $parRoot -Extensions @('.xpr')) { Add-Evidence $evidence XILINX 'project-file' $file }
foreach ($file in Get-Files -Base $parRoot -Extensions @('.pds')) { Add-Evidence $evidence PANGO 'project-file' $file }
foreach ($file in Get-Files -Base $parRoot -Extensions @('.al')) { Add-Evidence $evidence ANLOGIC 'project-file' $file }

$primaryVendors = @($evidence.Keys | Where-Object { $evidence[$_].Count -gt 0 } | Sort-Object)
if ($primaryVendors.Count -eq 0) {
    $fallbackRoots = @((Join-Path $root 'project\ip'), (Join-Path $root 'project\rtl'))
    foreach ($base in $fallbackRoots) {
        foreach ($file in Get-Files -Base $base -Extensions @('.xci')) { Add-Evidence $evidence XILINX 'ip-fallback' $file }
        foreach ($file in Get-Files -Base $base -Extensions @('.idf')) { Add-Evidence $evidence PANGO 'ip-fallback' $file }
        foreach ($file in Get-Files -Base $base -Extensions @('.ipc')) {
            $stream = [IO.File]::OpenRead($file.FullName)
            try {
                $length = [Math]::Min(65536, [int]$stream.Length)
                $buffer = [byte[]]::new($length)
                [void]$stream.Read($buffer, 0, $length)
                $header = [Text.Encoding]::UTF8.GetString($buffer)
            } finally { $stream.Dispose() }
            if ($header -match '(?i)(anlogic|\bTD[_ .-]?(version|tool|software)?\b|\bEG[0-9A-Z][0-9A-Z_-]*\b)') {
                Add-Evidence $evidence ANLOGIC 'ip-fallback-with-marker' $file
            }
        }
    }
}

$unsupported = [Collections.Generic.List[object]]::new()
foreach ($file in Get-Files -Base $parRoot -Extensions @('.qpf', '.qsf', '.lpf', '.ldf', '.syn')) {
    $unsupported.Add([ordered]@{
        path = ([IO.Path]::GetRelativePath($root, $file.FullName) -replace '\\', '/')
        extension = $file.Extension.ToLowerInvariant()
    })
}

$vendors = @($evidence.Keys | Where-Object { $evidence[$_].Count -gt 0 } | Sort-Object)
$status = if ($unsupported.Count -gt 0) {
    'UNSUPPORTED_VENDOR'
} elseif ($vendors.Count -gt 1) {
    'VENDOR_CONFLICT'
} elseif ($vendors.Count -eq 0) {
    'UNKNOWN_VENDOR'
} else {
    'DETECTED'
}

$result = [ordered]@{
    schema_version = '1.0.0'
    status = $status
    vendor = if ($status -eq 'DETECTED') { $vendors[0] } else { $null }
    evidence = @($vendors | ForEach-Object { [ordered]@{ vendor = $_; files = @($evidence[$_]) } })
    unsupported_evidence = @($unsupported)
    message = switch ($status) {
        'DETECTED' { "Detected exactly one supported vendor: $($vendors[0])." }
        'VENDOR_CONFLICT' { "Detected multiple supported vendors: $($vendors -join ', '). Select one target and remove stale project/IP markers." }
        'UNSUPPORTED_VENDOR' { 'Detected a project marker outside Xilinx, Pango, and Anlogic. Add support explicitly before generating an adapter.' }
        default { 'No authoritative Xilinx, Pango, or Anlogic project/IP marker was found.' }
    }
}

$json = $result | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $fullOutput = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $fullOutput
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($fullOutput, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
$result
