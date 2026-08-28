[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ProjectName,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z_][A-Za-z0-9_$]*$')][string]$TopModule,
    [Parameter(Mandatory)][ValidateSet('XILINX', 'PANGO', 'ANLOGIC')][string]$Vendor,
    [string]$ToolVersion = 'UNVERIFIED',
    [string]$Device = 'UNVERIFIED',
    [string]$Package = 'UNVERIFIED',
    [string]$SimulationTop,
    [string]$DefaultSimulationCase = 'smoke',
    [switch]$WithIp,
    [switch]$WithLintBlackBox,
    [switch]$WithGolden
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$templateRoot = Join-Path $packageRoot 'templates\fpga-project'
$destinationFull = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationFull) {
    if (-not (Test-Path -LiteralPath $destinationFull -PathType Container)) { throw "Destination is not a directory: $destinationFull" }
    if (Get-ChildItem -LiteralPath $destinationFull -Force | Select-Object -First 1) { throw "Destination must be new or empty: $destinationFull" }
}
if ([string]::IsNullOrWhiteSpace($SimulationTop)) { $SimulationTop = "tb_$TopModule" }

$vendorSpec = switch ($Vendor) {
    'XILINX' { @{ Extension = '.xpr'; Tool = 'Vivado' } }
    'PANGO' { @{ Extension = '.pds'; Tool = 'PDS' } }
    'ANLOGIC' { @{ Extension = '.al'; Tool = 'TD' } }
}
$canonicalProjectEntry = "project/par/$ProjectName$($vendorSpec.Extension)"
$tokens = [ordered]@{
    '__PROJECT_NAME__' = $ProjectName
    '__TOP_MODULE__' = $TopModule
    '__VENDOR__' = $Vendor
    '__TOOL__' = $vendorSpec.Tool
    '__TOOL_VERSION__' = $ToolVersion
    '__DEVICE__' = $Device
    '__PACKAGE__' = $Package
    '__SIMULATION_TOP__' = $SimulationTop
    '__DEFAULT_CASE__' = $DefaultSimulationCase
    '__PROJECT_EXTENSION__' = $vendorSpec.Extension
    '__CANONICAL_PROJECT_ENTRY__' = $canonicalProjectEntry
}

function Expand-Template([string]$Source, [string]$Target) {
    $text = [IO.File]::ReadAllText($Source, [Text.UTF8Encoding]::new($false, $true))
    foreach ($entry in $tokens.GetEnumerator()) { $text = $text.Replace([string]$entry.Key, [string]$entry.Value) }
    $parent = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Target, $text, [Text.UTF8Encoding]::new($false))
}

if (-not $PSCmdlet.ShouldProcess($destinationFull, "Create $Vendor FPGA project scaffold")) { return }
New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
$directories = @(
    'document', 'project/rtl', 'project/sdc', 'project/par', 'project/script',
    'simulation/tb/case', 'simulation/script',
    'linter/script', 'release/output'
)
if ($WithIp) { $directories += @('project/ip/synth','project/ip/sim') }
if ($WithLintBlackBox) { $directories += 'linter/lint_bb' }
if ($WithGolden) { $directories += 'release/golden' }
foreach ($relative in $directories) { New-Item -ItemType Directory -Path (Join-Path $destinationFull ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)) -Force | Out-Null }

Expand-Template (Join-Path $templateRoot 'common\README.md.template') (Join-Path $destinationFull 'README.md')
Expand-Template (Join-Path $templateRoot 'common\AGENTS.md') (Join-Path $destinationFull 'AGENTS.md')
Expand-Template (Join-Path $templateRoot 'common\.gitignore.template') (Join-Path $destinationFull '.gitignore')
Expand-Template (Join-Path $templateRoot 'common\setting.bat.template') (Join-Path $destinationFull 'project\script\setting.bat')
Expand-Template (Join-Path $templateRoot 'common\build-run.bat.template') (Join-Path $destinationFull 'project\script\run.bat')
Expand-Template (Join-Path $templateRoot 'common\simulation-run.bat.template') (Join-Path $destinationFull 'simulation\script\run.bat')
Expand-Template (Join-Path $templateRoot 'common\simulation-setting.txt.template') (Join-Path $destinationFull 'simulation\script\setting.txt')
Expand-Template (Join-Path $templateRoot 'common\vsim.do.template') (Join-Path $destinationFull 'simulation\script\vsim.do')
Expand-Template (Join-Path $templateRoot 'common\lint-run.bat.template') (Join-Path $destinationFull 'linter\script\run.bat')

foreach ($relative in @('project\script\src_list.txt','simulation\script\src_list.txt','linter\script\lint_list.txt')) {
    [IO.File]::WriteAllText((Join-Path $destinationFull $relative), '', [Text.UTF8Encoding]::new($false))
}

$target = [ordered]@{
    schema_version = '1.0.0'
    target_id = "$ProjectName-$($Vendor.ToLowerInvariant())"
    vendor = $Vendor
    tool = @{ name = $vendorSpec.Tool; version = $ToolVersion; project_file = $null }
    top = $TopModule
    device = $Device
    package = $Package
    simulation = @{ top = $SimulationTop; default_case = $DefaultSimulationCase; required_libraries = @() }
    selected_adapter = @{ build = 'project/script/run.bat'; simulation = 'simulation/script/run.bat' }
    canonical_project_file = $canonicalProjectEntry
    status = 'UNVERIFIED'
}
[IO.File]::WriteAllText((Join-Path $destinationFull 'project\target.fpga.json'), (($target | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    status = 'SCAFFOLDED_UNVERIFIED'
    project_root = $destinationFull
    vendor = $Vendor
    build_adapter = 'project/script/run.bat'
    simulation_adapter = 'simulation/script/run.bat'
    canonical_project_file = $canonicalProjectEntry
    next_step = "Create the real depth-0 $canonicalProjectEntry with a confirmed native Tcl/CLI recipe beside project/script/run.bat, configure simulation/script/vsim.do, then double-click run.bat. Do not add an extra project container under par."
}
