[CmdletBinding()]
param(
    [ValidateSet('User', 'Project')][string]$Scope = 'User',
    [string]$ProjectPath,
    [string]$WaveToolRoot,
    [Alias('Distro')][string]$WslDistro = 'Ubuntu',
    [string]$WslPython = 'python3',
    [string]$ExistingWavePython,
    [switch]$RequireWave,
    [switch]$SkipWaveProbe,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-SafeTargetPath {
    param([string]$Base, [string]$Candidate)
    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    $prefix = $baseFull + [IO.Path]::DirectorySeparatorChar
    if (-not $candidateFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe manifest path: $candidateFull" }
    $probe = $candidateFull
    while (-not (Test-Path -LiteralPath $probe)) {
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $probe) { throw "Unsafe manifest ancestor: $candidateFull" }
        $probe = $parent
    }
    $cursor = Get-Item -LiteralPath $probe -Force
    while ($null -ne $cursor -and -not $cursor.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals($baseFull, [StringComparison]::OrdinalIgnoreCase)) {
        if ($cursor.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Manifest path traverses a reparse point: $($cursor.FullName)" }
        $cursor = if ($cursor -is [IO.FileInfo]) { $cursor.Directory } else { $cursor.Parent }
    }
    if ($null -eq $cursor) { throw "Manifest path cannot be traced to root: $candidateFull" }
}
function Test-AllowedInstalledRelativePath([string]$Relative, [string]$SelectedScope) {
    $path = $Relative -replace '\\', '/'
    $agentNames = @('fpga_architect','fpga_engineer','verification_engineer','fpga_temporal_evidence_reviewer','fpga_cdc_timing_reviewer','fpga_interface_architect','fpga_vendor_platform_reviewer','fpga_board_validation_engineer','fpga_reviewer','system_architect','embedded_engineer','hardware_datasheet','independent_reviewer')
    if ($path -in @($agentNames | ForEach-Object { ".codex/agents/$_.toml" })) { return $true }
    if ($path.StartsWith('.agents/skills/run-fpga-workflow/', [StringComparison]::Ordinal) -or $path.StartsWith('.agents/skills/setup-fpga-workflow/', [StringComparison]::Ordinal)) { return $path -notmatch '(^|/)\.\.(/|$)' }
    return ($SelectedScope -eq 'User' -and $path -eq '.codex/AGENTS.md') -or ($SelectedScope -eq 'Project' -and $path -eq 'AGENTS.md')
}
function Assert-SafeInstallRoot([string]$Root) {
    $full = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $drive = [IO.Path]::GetPathRoot($full).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($full.Equals($drive, [StringComparison]::OrdinalIgnoreCase)) { throw '安装根不能是磁盘根目录。' }
    $item = Get-Item -LiteralPath $full -Force
    $cursor = $item
    while ($null -ne $cursor) {
        if ($cursor.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "安装根或祖先不能是 reparse point：$($cursor.FullName)" }
        $cursor = $cursor.Parent
    }
}
function Get-ExpectedRelativePaths([string]$PackageRoot, [string]$SelectedScope, [bool]$IncludeTemplate) {
    $paths = [Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath (Join-Path $PackageRoot '.codex\agents') -File -Filter '*.toml' | Sort-Object Name | ForEach-Object { $paths.Add(".codex/agents/$($_.Name)") }
    foreach ($skillName in @('run-fpga-workflow','setup-fpga-workflow')) {
        $skillRoot = Join-Path $PackageRoot "skills\$skillName"
        Get-ChildItem -LiteralPath $skillRoot -File -Recurse | Sort-Object FullName | ForEach-Object { $paths.Add(".agents/skills/$skillName/$(([IO.Path]::GetRelativePath($skillRoot,$_.FullName) -replace '\\','/'))") }
    }
    if ($IncludeTemplate) { $paths.Add($(if ($SelectedScope -eq 'User') { '.codex/AGENTS.md' } else { 'AGENTS.md' })) }
    return @($paths)
}
function Enter-DeploymentReadMutex([string]$Root) {
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Root).ToLowerInvariant()))).Substring(0, 24)
    $mutex = [Threading.Mutex]::new($false, "Local\CodexFpgaDeploy-$hash")
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { $mutex.Dispose(); return $null }
        return $mutex
    } catch {
        $mutex.Dispose()
        throw
    }
}
$targetRoot = if ($Scope -eq 'User') {
    [IO.Path]::GetFullPath($env:USERPROFILE)
} else {
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { throw '-ProjectPath is required for Project scope.' }
    [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectPath).Path)
}
if ($Scope -eq 'Project' -and $targetRoot.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals([IO.Path]::GetPathRoot($targetRoot).TrimEnd([IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Project scope 不能指向磁盘根目录。' }
if ($Scope -eq 'User' -and -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $defaultCodexHome = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex')).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $configuredCodexHome = [IO.Path]::GetFullPath($env:CODEX_HOME).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $configuredCodexHome.Equals($defaultCodexHome, [StringComparison]::OrdinalIgnoreCase)) { throw 'NONDEFAULT_CODEX_HOME_UNVERIFIED' }
}
Assert-SafeInstallRoot -Root $targetRoot
$readMutex = Enter-DeploymentReadMutex -Root $targetRoot
if ($null -eq $readMutex) {
    $busyResult = [pscustomobject]@{
        schema_version = 'fpga-workflow-doctor-1.0'
        status = 'UNVERIFIED_TRANSIENT'
        scope = $Scope
        target_root = $targetRoot
        manifest_valid = $false
        roles_found = 0
        run_skill = $false
        setup_skill = $false
        wave = [pscustomobject]@{ status = 'NOT_CHECKED'; next_action = '等待部署进程结束后重试。' }
        issues = @('INSTALL_ALREADY_RUNNING')
        fresh_session_required = $false
    }
    if ($AsJson) { $busyResult | ConvertTo-Json -Depth 10 } else { $busyResult }
    return
}

try {
$expectedNames = @(
    'fpga_architect','fpga_engineer','verification_engineer','fpga_temporal_evidence_reviewer',
    'fpga_cdc_timing_reviewer','fpga_interface_architect','fpga_vendor_platform_reviewer',
    'fpga_board_validation_engineer','fpga_reviewer','system_architect','embedded_engineer',
    'hardware_datasheet','independent_reviewer'
)
$manifestPath = Join-Path $targetRoot '.codex\codex-fpga-engineering-workflow-zh.install.json'
$issues = [Collections.Generic.List[string]]::new()
$manifestValid = $false
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedVersion = (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION') -Raw).Trim()
        if ($manifest.schemaVersion -ne 1 -or $manifest.package -ne 'codex-fpga-engineering-workflow-zh' -or $manifest.scope -ne $Scope -or $manifest.packageVersion -ne $expectedVersion) { throw 'manifest schema/package/scope/version mismatch' }
        if (@($manifest.files).Count -lt 62 -or @($manifest.files).Count -gt 63) { throw "manifest file count invalid: $(@($manifest.files).Count)" }
        $duplicatePaths = @($manifest.files | Group-Object relativePath | Where-Object Count -gt 1)
        if ($duplicatePaths.Count) { throw "manifest duplicate paths: $($duplicatePaths.Name -join ', ')" }
        $manifestPaths = @($manifest.files | ForEach-Object { [string]$_.relativePath })
        $templatePath = if ($Scope -eq 'User') { '.codex/AGENTS.md' } else { 'AGENTS.md' }
        $expectedPaths = Get-ExpectedRelativePaths -PackageRoot (Split-Path -Parent $PSScriptRoot) -SelectedScope $Scope -IncludeTemplate ($manifestPaths -contains $templatePath)
        $missingEntries = @($expectedPaths | Where-Object { $_ -notin $manifestPaths })
        $unexpectedEntries = @($manifestPaths | Where-Object { $_ -notin $expectedPaths })
        if ($missingEntries.Count -or $unexpectedEntries.Count) { throw "manifest expected file-set mismatch; missing=$($missingEntries -join ', '); unexpected=$($unexpectedEntries -join ', ')" }
        foreach ($entry in $manifest.files) {
            if ([string]$entry.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "manifest SHA-256 invalid: $($entry.relativePath)" }
            if (-not (Test-AllowedInstalledRelativePath -Relative ([string]$entry.relativePath) -SelectedScope $Scope)) { throw "Manifest contains a non-package path: $($entry.relativePath)" }
            $path = Join-Path $targetRoot ($entry.relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
            Assert-SafeTargetPath -Base $targetRoot -Candidate $path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $issues.Add("Missing: $($entry.relativePath)"); continue }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) { $issues.Add("Modified: $($entry.relativePath)") }
        }
        $manifestValid = $issues.Count -eq 0
    } catch {
        $issues.Add("Invalid install manifest: $($_.Exception.Message)")
    }
} else {
    $issues.Add('Install manifest missing')
}

$agents = @(Get-ChildItem -LiteralPath (Join-Path $targetRoot '.codex\agents') -File -Filter '*.toml' -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -in $expectedNames })
$runSkill = Test-Path -LiteralPath (Join-Path $targetRoot '.agents\skills\run-fpga-workflow\SKILL.md') -PathType Leaf
$setupSkill = Test-Path -LiteralPath (Join-Path $targetRoot '.agents\skills\setup-fpga-workflow\SKILL.md') -PathType Leaf
if ($agents.Count -ne 13) { $issues.Add("Expected 13 roles; found $($agents.Count)") }
if (-not $runSkill) { $issues.Add('run-fpga-workflow skill missing') }
if (-not $setupSkill) { $issues.Add('setup-fpga-workflow skill missing') }

$wave = if ($SkipWaveProbe) {
    [pscustomobject]@{ status = 'SKIPPED'; next_action = $null }
} else {
    $waveArgs = @{ Mode = 'Detect'; Distro = $WslDistro; WslPython = $WslPython }
    if (-not [string]::IsNullOrWhiteSpace($ExistingWavePython)) { $waveArgs.ExistingWavePython = $ExistingWavePython }
    if (-not [string]::IsNullOrWhiteSpace($WaveToolRoot)) { $waveArgs.ToolRoot = $WaveToolRoot }
    & (Join-Path $PSScriptRoot 'prepare-wave-environment.ps1') @waveArgs
}
$waveReady = $wave.status -eq 'READY_WITH_VCD_CONVERTER'
if ($RequireWave -and -not $waveReady) { $issues.Add("Required wave environment is not ready: $($wave.status)") }

$roleReady = $manifestValid -and $agents.Count -eq 13 -and $runSkill -and $setupSkill
$status = if (-not $roleReady) { 'FAILED' } elseif ($RequireWave -and -not $waveReady) { 'PARTIAL' } else { 'READY' }
$result = [pscustomobject]@{
    schema_version = 'fpga-workflow-doctor-1.0'
    status = $status
    scope = $Scope
    target_root = $targetRoot
    manifest_valid = $manifestValid
    roles_found = $agents.Count
    run_skill = $runSkill
    setup_skill = $setupSkill
    wave = $wave
    issues = @($issues)
    fresh_session_required = $roleReady
}
if ($AsJson) { $result | ConvertTo-Json -Depth 10 } else { $result }
} finally {
    try { $readMutex.ReleaseMutex() } catch { }
    $readMutex.Dispose()
}
