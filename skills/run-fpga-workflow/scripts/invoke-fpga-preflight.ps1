[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [ValidateSet('Validate', 'Compile', 'Build', 'Clean', 'Simulate', 'Lint')]
    [string]$Action = 'Validate',
    [string]$Case,
    [ValidateSet('all', 'verilator', 'svlint')]
    [string]$LintTool = 'all',
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$detectScript = Join-Path $PSScriptRoot 'detect-fpga-vendor.ps1'
if (-not (Test-Path -LiteralPath $detectScript)) { $detectScript = Join-Path $PSScriptRoot 'detect-vendor.ps1' }
$vendor = & $detectScript -ProjectRoot $root

$settingsPath = Join-Path $root 'project\script\setting.psd1'
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw 'SCRIPT_PATH_FAIL: project/script/setting.psd1 is missing.'
}
$settings = Import-PowerShellDataFile -LiteralPath $settingsPath
if ($settings.Vendor -and $settings.Vendor.ToString().ToUpperInvariant() -ne $vendor.vendor) {
    throw "TARGET_CONFLICT: setting.psd1 Vendor '$($settings.Vendor)' differs from detected '$($vendor.vendor)'."
}
if ($vendor.requires_explicit_project_file) {
    if (-not $settings.VendorProjectFile) {
        throw 'TARGET_CONFLICT: multiple Pango .pds files were found and no project/par/pds_script.pds exists. Set VendorProjectFile in project/script/setting.psd1 to the authoritative .pds file.'
    }
    $explicitProject = Join-Path $root $settings.VendorProjectFile
    if (-not (Test-Path -LiteralPath $explicitProject -PathType Leaf) -or [IO.Path]::GetExtension($explicitProject).ToLowerInvariant() -ne '.pds') {
        throw "TARGET_CONFLICT: configured VendorProjectFile '$($settings.VendorProjectFile)' is not an existing Pango .pds file."
    }
}

$requiredLists = @(
    'project/script/src_list.txt',
    'simulation/script/src_list.txt',
    'linter/script/lint_list.txt'
)
foreach ($relative in $requiredLists) {
    $listPath = Join-Path $root ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) {
        throw "SCRIPT_PATH_FAIL: required filelist '$relative' is missing."
    }
    foreach ($line in Get-Content -LiteralPath $listPath -Encoding utf8) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('+incdir+')) { continue }
        $resolved = Join-Path $root ($entry -replace '/', '\')
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "SCRIPT_PATH_FAIL: '$relative' references missing '$entry'."
        }
    }
}

$adapterPath = Join-Path $PSScriptRoot 'vendor-adapter.ps1'
if (-not (Test-Path -LiteralPath $adapterPath -PathType Leaf)) {
    throw 'SCRIPT_PATH_FAIL: the selected project/script/ai_run/vendor-adapter.ps1 is missing.'
}

$toolchainPath = Join-Path $root 'project\script\toolchain.local.psd1'
$toolchain = $null
if ($Action -ne 'Validate') {
    if (-not (Test-Path -LiteralPath $toolchainPath -PathType Leaf)) {
        throw 'TOOL_ENV_FAIL: copy toolchain.local.psd1.example to toolchain.local.psd1 and enter confirmed local tool commands.'
    }
    $toolchain = Import-PowerShellDataFile -LiteralPath $toolchainPath
    if ($toolchain.Vendor -and $toolchain.Vendor.ToString().ToUpperInvariant() -ne $vendor.vendor) {
        throw "TARGET_CONFLICT: toolchain vendor '$($toolchain.Vendor)' differs from detected '$($vendor.vendor)'."
    }
}

$exeKey = switch ($Action) {
    'Compile' { 'CompileExecutable' }
    'Build' { 'BuildExecutable' }
    'Simulate' { 'SimulationExecutable' }
    'Lint' {
        switch ($LintTool) {
            'verilator' { 'VerilatorExecutable' }
            'svlint' { 'SvLintExecutable' }
            default { 'LintExecutable' }
        }
    }
    default { $null }
}
if ($exeKey) {
    $exe = $toolchain[$exeKey]
    if (-not $exe) { throw "TOOL_ENV_FAIL: '$exeKey' is not configured." }
    $resolvedExe = if ([IO.Path]::IsPathRooted($exe)) { $exe } else { (Get-Command $exe -ErrorAction SilentlyContinue).Source }
    if (-not $resolvedExe -or -not (Test-Path -LiteralPath $resolvedExe -PathType Leaf)) {
        throw "TOOL_ENV_FAIL: configured $exeKey '$exe' was not found."
    }
}

if ($Action -eq 'Simulate') {
    $selectedCase = if ($Case) { $Case } else { $settings.DefaultSimulationCase }
    if (-not $selectedCase) { throw 'TESTBENCH_FAIL: no simulation case was supplied or configured.' }
    $caseCandidates = @('.sv', '.v', '.sim') | ForEach-Object { Join-Path $root "simulation\tb\case\$selectedCase$_" }
    if (-not ($caseCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)) {
        throw "TESTBENCH_FAIL: simulation case '$selectedCase' does not exist as .sv, .v, or .sim."
    }
}

$result = [pscustomobject]@{
    schema_version = '0.3'
    status = 'PREFLIGHT_OK'
    action = $Action
    vendor = $vendor.vendor
    authoritative_project = $vendor.authoritative_project
    top = $settings.TopModule
    case = if ($Action -eq 'Simulate') { if ($Case) { $Case } else { $settings.DefaultSimulationCase } } else { $null }
    lint_tool = if ($Action -eq 'Lint') { $LintTool } else { $null }
}
if ($AsJson) { $result | ConvertTo-Json -Depth 5 } else { $result }
