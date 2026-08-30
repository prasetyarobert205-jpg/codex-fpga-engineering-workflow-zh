[CmdletBinding()]
param(
    [ValidateSet('User', 'Project')][string]$Scope = 'User',
    [string]$ProjectPath
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
if ($null -eq $readMutex) { throw 'INSTALL_ALREADY_RUNNING：部署根正在变化，verify 不签发结果。' }
try {
$manifestPath = Join-Path $targetRoot '.codex\codex-fpga-engineering-workflow-zh.install.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "找不到安装清单：$manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$expectedVersion = (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION') -Raw).Trim()
if ($manifest.schemaVersion -ne 1 -or $manifest.package -ne 'codex-fpga-engineering-workflow-zh' -or $manifest.scope -ne $Scope -or $manifest.packageVersion -ne $expectedVersion) { throw '安装清单 schema/package/scope/version 不匹配。' }
if (@($manifest.files).Count -lt 62 -or @($manifest.files).Count -gt 63) { throw "安装清单文件数不正确：$(@($manifest.files).Count)" }
$duplicatePaths = @($manifest.files | Group-Object relativePath | Where-Object Count -gt 1)
if ($duplicatePaths.Count) { throw "安装清单包含重复路径：$($duplicatePaths.Name -join ', ')" }
$manifestPaths = @($manifest.files | ForEach-Object { [string]$_.relativePath })
$templatePath = if ($Scope -eq 'User') { '.codex/AGENTS.md' } else { 'AGENTS.md' }
$expectedPaths = Get-ExpectedRelativePaths -PackageRoot (Split-Path -Parent $PSScriptRoot) -SelectedScope $Scope -IncludeTemplate ($manifestPaths -contains $templatePath)
$missingEntries = @($expectedPaths | Where-Object { $_ -notin $manifestPaths })
$unexpectedEntries = @($manifestPaths | Where-Object { $_ -notin $expectedPaths })
if ($missingEntries.Count -or $unexpectedEntries.Count) { throw "安装清单与 expected file-set 不一致；missing=$($missingEntries -join ', '); unexpected=$($unexpectedEntries -join ', ')" }
$errors = [Collections.Generic.List[string]]::new()
foreach ($entry in $manifest.files) {
    if ([string]$entry.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "Manifest SHA-256 无效：$($entry.relativePath)" }
    if (-not (Test-AllowedInstalledRelativePath -Relative ([string]$entry.relativePath) -SelectedScope $Scope)) { throw "Manifest contains a non-package path: $($entry.relativePath)" }
    $path = Join-Path $targetRoot ($entry.relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    Assert-SafeTargetPath -Base $targetRoot -Candidate $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("Missing: $path"); continue }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) { $errors.Add("Modified: $path") }
}
$agents = Get-ChildItem -LiteralPath (Join-Path $targetRoot '.codex\agents') -File -Filter '*.toml' -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -in @('fpga_architect','fpga_engineer','verification_engineer','fpga_temporal_evidence_reviewer','fpga_cdc_timing_reviewer','fpga_interface_architect','fpga_vendor_platform_reviewer','fpga_board_validation_engineer','fpga_reviewer','system_architect','embedded_engineer','hardware_datasheet','independent_reviewer') }
if ($agents.Count -ne 13) { $errors.Add("Expected 13 workflow agent files; found $($agents.Count).") }
$skillPath = Join-Path $targetRoot '.agents\skills\run-fpga-workflow\SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { $errors.Add("缺少 Skill：$skillPath") }
$setupSkillPath = Join-Path $targetRoot '.agents\skills\setup-fpga-workflow\SKILL.md'
if (-not (Test-Path -LiteralPath $setupSkillPath -PathType Leaf)) { $errors.Add("缺少部署 Skill：$setupSkillPath") }
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_ }; throw '安装核对失败。' }
Write-Host '已安装文件与清单 SHA-256 全部一致。Fresh-session 的 Codex 发现行为仍需在新会话做只读 canary。'
} finally {
    try { $readMutex.ReleaseMutex() } catch { }
    $readMutex.Dispose()
}
