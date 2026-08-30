[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('User', 'Project')][string]$Scope = 'User',
    [string]$ProjectPath,
    [switch]$InstallAgentsTemplate,
    [ValidateSet('Skip', 'Detect', 'Prepare')][string]$WaveMode = 'Detect',
    [string]$WaveToolRoot,
    [Alias('Distro')][string]$WslDistro = 'Ubuntu',
    [string]$WslPython = 'python3',
    [string]$ExistingWavePython,
    [string]$Vcd2FstPath,
    [string]$Wheelhouse,
    [switch]$RunWaveSmoke,
    [switch]$Force,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$savedWhatIf = $WhatIfPreference
try {
    $WhatIfPreference = $false
    $validationArgs = @{}
    if ($savedWhatIf) { $validationArgs.NoRuntimeCanaries = $true }
    $null = & (Join-Path $PSScriptRoot 'validate-package.ps1') @validationArgs
} finally {
    $WhatIfPreference = $savedWhatIf
}
$installArgs = @{ Scope = $Scope; InstallAgentsTemplate = $InstallAgentsTemplate; Force = $Force }
if ($Scope -eq 'Project') {
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { throw '-ProjectPath is required for Project scope.' }
    $installArgs.ProjectPath = $ProjectPath
}

$waveResult = [pscustomobject]@{ status = 'SKIPPED'; next_action = $null }
if ($WhatIfPreference) {
    $installPlan = & (Join-Path $PSScriptRoot 'install.ps1') @installArgs -PlanOnly
    if ($WaveMode -ne 'Skip') {
        $waveArgs = @{ Mode = if ($WaveMode -eq 'Prepare') { 'Prepare' } else { 'Detect' }; Distro = $WslDistro; WslPython = $WslPython }
        if (-not [string]::IsNullOrWhiteSpace($WaveToolRoot)) { $waveArgs.ToolRoot = $WaveToolRoot }
        if (-not [string]::IsNullOrWhiteSpace($Vcd2FstPath)) { $waveArgs.Vcd2FstPath = $Vcd2FstPath }
        if (-not [string]::IsNullOrWhiteSpace($ExistingWavePython)) { $waveArgs.ExistingWavePython = $ExistingWavePython }
        if (-not [string]::IsNullOrWhiteSpace($Wheelhouse)) { $waveArgs.Wheelhouse = $Wheelhouse }
        if ($RunWaveSmoke) { $waveArgs.RunSmoke = $true }
        $waveResult = & (Join-Path $PSScriptRoot 'prepare-wave-environment.ps1') @waveArgs -WhatIf
    }
    $preview = [pscustomobject]@{
        schema_version = 'fpga-workflow-bootstrap-1.0'
        status = 'PLAN_NO_CHANGES'
        package_version = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()
        scope = $Scope
        install_agents_template = [bool]$InstallAgentsTemplate
        install_plan = $installPlan
        wave_mode = $WaveMode
        wave = $waveResult
        global_path_modified = $false
        global_library_mapping_modified = $false
    }
    if ($AsJson) { $preview | ConvertTo-Json -Depth 10 } else { $preview }
    return
}

if (-not $PSCmdlet.ShouldProcess($Scope, '部署中文 FPGA 角色和 Skill')) { return }
& (Join-Path $PSScriptRoot 'install.ps1') @installArgs
& (Join-Path $PSScriptRoot 'verify-install.ps1') -Scope $Scope -ProjectPath $ProjectPath

if ($WaveMode -ne 'Skip') {
    $waveArgs = @{ Mode = if ($WaveMode -eq 'Prepare') { 'Prepare' } else { 'Detect' }; Distro = $WslDistro; WslPython = $WslPython }
    if (-not [string]::IsNullOrWhiteSpace($WaveToolRoot)) { $waveArgs.ToolRoot = $WaveToolRoot }
    if (-not [string]::IsNullOrWhiteSpace($Vcd2FstPath)) { $waveArgs.Vcd2FstPath = $Vcd2FstPath }
    if (-not [string]::IsNullOrWhiteSpace($ExistingWavePython)) { $waveArgs.ExistingWavePython = $ExistingWavePython }
    if (-not [string]::IsNullOrWhiteSpace($Wheelhouse)) { $waveArgs.Wheelhouse = $Wheelhouse }
    if ($RunWaveSmoke) { $waveArgs.RunSmoke = $true }
    $waveResult = & (Join-Path $PSScriptRoot 'prepare-wave-environment.ps1') @waveArgs
}

$doctorArgs = @{ Scope = $Scope; WslDistro = $WslDistro; WslPython = $WslPython }
if ($Scope -eq 'Project') { $doctorArgs.ProjectPath = $ProjectPath }
if (-not [string]::IsNullOrWhiteSpace($WaveToolRoot)) { $doctorArgs.WaveToolRoot = $WaveToolRoot }
if (-not [string]::IsNullOrWhiteSpace($ExistingWavePython)) { $doctorArgs.ExistingWavePython = $ExistingWavePython }
if ($WaveMode -eq 'Prepare') { $doctorArgs.RequireWave = $true }
if ($WaveMode -eq 'Skip') { $doctorArgs.SkipWaveProbe = $true }
$doctor = & (Join-Path $PSScriptRoot 'deployment-doctor.ps1') @doctorArgs

$overall = if ($doctor.status -eq 'FAILED') { 'FAILED' } elseif ($doctor.status -eq 'UNVERIFIED_TRANSIENT') { 'PARTIAL' } elseif ($WaveMode -eq 'Prepare' -and $waveResult.status -ne 'READY_WITH_VCD_CONVERTER') { 'PARTIAL' } else { 'READY' }
$result = [pscustomobject]@{
    schema_version = 'fpga-workflow-bootstrap-1.0'
    status = $overall
    package_version = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()
    scope = $Scope
    roles = [pscustomobject]@{ expected = 13; found = $doctor.roles_found; status = if ($doctor.roles_found -eq 13) { 'READY' } else { 'FAILED' } }
    skills = [pscustomobject]@{ run_fpga_workflow = $doctor.run_skill; setup_fpga_workflow = $doctor.setup_skill }
    wave = $waveResult
    global_path_modified = $false
    global_library_mapping_modified = $false
    product_project_modified = $false
    fresh_session_required = [bool]$doctor.fresh_session_required
    next_action = if ($overall -eq 'PARTIAL') { $waveResult.next_action } else { '新开 Codex 会话后使用 $run-fpga-workflow。' }
}
if ($AsJson) { $result | ConvertTo-Json -Depth 10 } else { $result }
