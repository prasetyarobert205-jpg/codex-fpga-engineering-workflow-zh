[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [ValidateSet('Build', 'Simulation', 'Lint')][string]$Purpose,
    [ValidateSet('XILINX', 'PANGO', 'ANLOGIC')][string]$ExpectedVendor,
    [string]$CommandName,
    [string[]]$PreparedLibraryNames = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$issues = [Collections.Generic.List[string]]::new()
$detection = & (Join-Path $PSScriptRoot 'detect-vendor.ps1') -ProjectRoot $root
if ($detection.status -ne 'DETECTED') { $issues.Add($detection.message) }
elseif (-not [string]::IsNullOrWhiteSpace($ExpectedVendor) -and $detection.vendor -ne $ExpectedVendor) {
    $issues.Add("Configured vendor $ExpectedVendor does not match detected vendor $($detection.vendor).")
}

$requiredLists = switch ($Purpose) {
    'Build' { @(@{ Path='project/script/src_list.txt'; NonEmpty=$true }) }
    'Simulation' { @(@{ Path='simulation/script/src_list.txt'; NonEmpty=$true }) }
    'Lint' { @(@{ Path='linter/script/lint_list.txt'; NonEmpty=$true }) }
}
$requiredEntryPoints = switch ($Purpose) {
    'Build' { @('project/script/run.bat','project/script/setting.bat') }
    'Simulation' { @('simulation/script/run.bat','simulation/script/setting.txt','simulation/script/vsim.do') }
    'Lint' { @('linter/script/run.bat') }
}
foreach ($relative in $requiredEntryPoints) {
    if (-not (Test-Path -LiteralPath (Join-Path $root ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)) -PathType Leaf)) {
        $issues.Add("Missing entry-point file: $relative")
    }
}
$listBase = switch ($Purpose) {
    'Build' { Join-Path $root 'project\par' }
    'Simulation' { Join-Path $root 'simulation\work' }
    'Lint' { $root }
}
foreach ($listSpec in $requiredLists) {
    $relativeList = [string]$listSpec.Path
    $listPath = Join-Path $root ($relativeList -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) { $issues.Add("Missing file list: $relativeList"); continue }
    $usableEntries = 0
    foreach ($line in Get-Content -LiteralPath $listPath -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        $usableEntries++
        if ($trimmed.StartsWith('+incdir+')) {
            $include = $trimmed.Substring(8)
            $candidate = [IO.Path]::GetFullPath((Join-Path $listBase ($include -replace '/', [IO.Path]::DirectorySeparatorChar)))
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { $issues.Add("Include directory does not exist: $include") }
        } else {
            $candidate = [IO.Path]::GetFullPath((Join-Path $listBase ($trimmed -replace '/', [IO.Path]::DirectorySeparatorChar)))
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { $issues.Add("File list entry does not exist: $trimmed") }
        }
    }
    if ($listSpec.NonEmpty -and $usableEntries -eq 0) { $issues.Add("File list is empty: $relativeList") }
}

$command = [string]$CommandName
if ([string]::IsNullOrWhiteSpace($command)) {
    $issues.Add('TOOL_ENV_FAIL: provide the project-confirmed canonical command name with -CommandName; this helper does not guess Pango/Anlogic commands.')
} elseif ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) {
    $issues.Add("TOOL_ENV_FAIL: configured command is unavailable: $command")
}

if ($Purpose -eq 'Simulation') {
    $simulationSetting = Join-Path $root 'simulation\script\setting.txt'
    if (Test-Path -LiteralPath $simulationSetting -PathType Leaf) {
        $settingText = [IO.File]::ReadAllText($simulationSetting)
        if ($settingText -notmatch '(?m)^\s*set\s+sim_top\s+\S+') { $issues.Add('Simulation top is not configured in simulation/script/setting.txt.') }
    }
    foreach ($library in $PreparedLibraryNames) {
        if ([string]::IsNullOrWhiteSpace([string]$library)) { $issues.Add('MISSING_VENDOR_LIBRARY: an empty prepared-library name was provided.') }
    }
}

$status = if ($issues.Count -eq 0) { 'PASS' } elseif ($issues | Where-Object { $_ -match 'MISSING_VENDOR_LIBRARY' }) { 'MISSING_VENDOR_LIBRARY' } else { 'UNVERIFIED' }
[pscustomobject]@{
    schema_version = '1.0.0'
    purpose = $Purpose
    status = $status
    vendor = $detection.vendor
    command = $command
    issues = @($issues)
    preparation_checklist = @(
        'Install or select the exact vendor tool and simulator version required by the project.',
        'Configure the project-local BAT setting with a verified tool root/environment and pass the canonical command name to this helper.',
        'Map only official simulation libraries that match the vendor, family, tool, and simulator version.',
        'Re-run the one-click wrapper; do not substitute approximate primitive models.'
    )
}
