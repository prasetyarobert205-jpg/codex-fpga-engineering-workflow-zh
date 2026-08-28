[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Destination,
    [Parameter(Mandatory)]
    [string]$ProjectName,
    [Parameter(Mandatory)]
    [string]$TopModule,
    [string]$SimulationTopModule,
    [string]$Part = 'UNCONFIRMED_PART',
    [ValidateSet('AUTO', 'XILINX', 'PANGO', 'ANLOGIC')]
    [string]$Vendor = 'AUTO',
    [string]$Tool = 'UNCONFIRMED_TOOL',
    [string]$ToolVersion = 'UNCONFIRMED_VERSION',
    [switch]$AugmentExisting,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-Path $skillRoot 'assets\project-template'

if (Test-Path -LiteralPath $Destination) {
    $existing = Get-Item -LiteralPath $Destination
    if (-not $existing.PSIsContainer) { throw 'SCAFFOLD_CONFLICT: destination exists and is not a directory.' }
    if (-not $AugmentExisting -and (Get-ChildItem -LiteralPath $Destination -Force | Select-Object -First 1)) {
        throw 'SCAFFOLD_CONFLICT: destination is not empty; use -AugmentExisting only after reviewing its contents.'
    }
} else {
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
}
$root = (Resolve-Path -LiteralPath $Destination).Path

if ($Vendor -eq 'AUTO') {
    $Vendor = (& (Join-Path $PSScriptRoot 'detect-fpga-vendor.ps1') -ProjectRoot $root).vendor
}
if (-not $SimulationTopModule) { $SimulationTopModule = "tb_$TopModule" }
foreach ($value in @($ProjectName, $TopModule, $SimulationTopModule, $Part, $Vendor, $Tool, $ToolVersion)) {
    if ($value -match '[\r\n"]') { throw 'SCAFFOLD_INPUT_INVALID: project identity values may not contain quotes or newlines.' }
}

$directories = @(
    'document',
    'project\rtl',
    'project\ip',
    'project\sdc',
    'project\par',
    'project\script',
    'simulation\tb\case',
    'simulation\script',
    'linter\script',
    'release\output'
)
foreach ($relative in $directories) {
    [IO.Directory]::CreateDirectory((Join-Path $root $relative)) | Out-Null
}

function Copy-NewFile([string]$Source, [string]$Target) {
    if (Test-Path -LiteralPath $Target) {
        $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
        if ($sourceHash -ne $targetHash) { throw "SCAFFOLD_CONFLICT: refusing to overwrite '$Target'." }
        return
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Target)) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Target
}

Get-ChildItem -LiteralPath $templateRoot -Recurse -File | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($templateRoot, $_.FullName)
    Copy-NewFile $_.FullName (Join-Path $root $relative)
}

$settingsPath = Join-Path $root 'project\script\setting.bat'
if (-not (Test-Path -LiteralPath $settingsPath)) {
    $settings = @"
@echo off
set "PROJECT_NAME=$ProjectName"
set "TOP_MODULE=$TopModule"
set "SIM_TOP_MODULE=$SimulationTopModule"
set "FPGA_PART=$Part"
set "VENDOR=$Vendor"
exit /b 0
"@
    [IO.File]::WriteAllText($settingsPath, $settings, [Text.UTF8Encoding]::new($false))
}

$projectExtension = switch ($Vendor) { 'XILINX' { '.xpr' } 'PANGO' { '.pds' } 'ANLOGIC' { '.al' } default { '' } }
$canonicalProjectEntry = if ($projectExtension) { "project/par/$ProjectName$projectExtension" } else { 'UNCONFIRMED_CANONICAL_PROJECT' }

foreach ($relative in @('README.md', 'AGENTS.md', 'project\script\run.bat', 'simulation\script\run.bat', 'simulation\script\setting.txt')) {
    $path = Join-Path $root $relative
    if (Test-Path -LiteralPath $path) {
        $text = [IO.File]::ReadAllText($path).Replace('__PROJECT_NAME__', $ProjectName).Replace('__TOP_MODULE__', $TopModule).Replace('__SIM_TOP_MODULE__', $SimulationTopModule).Replace('__PART__', $Part).Replace('__VENDOR__', $Vendor).Replace('__TOOL__', $Tool).Replace('__TOOL_VERSION__', $ToolVersion).Replace('__CANONICAL_PROJECT_ENTRY__', $canonicalProjectEntry)
        [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    }
}

$result = [pscustomobject]@{
    schema_version = '0.3'
    status = 'SCAFFOLDED'
    root = $root
    project_name = $ProjectName
    top = $TopModule
    simulation_top = $SimulationTopModule
    part = $Part
    vendor = $Vendor
    tool = $Tool
    tool_version = $ToolVersion
    build_adapter = 'project/script/run.bat'
    simulation_adapter = 'simulation/script/run.bat'
    canonical_project_file = $canonicalProjectEntry
    note = 'The native BAT adapters intentionally fail closed until exact tool/version/project/part/simulator commands are confirmed. The real canonical vendor project file must be created directly under project/par without an extra container directory.'
}
if ($AsJson) { $result | ConvertTo-Json -Depth 5 } else { $result }
