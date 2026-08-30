[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('User', 'Project')][string]$Scope = 'User',
    [string]$ProjectPath,
    [switch]$InstallAgentsTemplate,
    [switch]$PlanOnly,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedRoot {
    param([string]$SelectedScope, [string]$SelectedProject)
    if ($SelectedScope -eq 'User') { return [IO.Path]::GetFullPath($env:USERPROFILE) }
    if ([string]::IsNullOrWhiteSpace($SelectedProject)) { throw '-ProjectPath is required for Project scope.' }
    if (-not (Test-Path -LiteralPath $SelectedProject -PathType Container)) { throw "Project path does not exist: $SelectedProject" }
    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SelectedProject).Path)
    if ($resolved.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals([IO.Path]::GetPathRoot($resolved).TrimEnd([IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Project scope 不能指向磁盘根目录。' }
    return $resolved
}

function Get-RelativePortablePath {
    param([string]$Base, [string]$Path)
    return ([IO.Path]::GetRelativePath($Base, $Path) -replace '\\', '/')
}

function Assert-SafeTargetPath {
    param([string]$Base, [string]$Candidate)
    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    $prefix = $baseFull + [IO.Path]::DirectorySeparatorChar
    if (-not $candidateFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe target path outside install root: $candidateFull" }
    $probe = $candidateFull
    while (-not (Test-Path -LiteralPath $probe)) {
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $probe) { throw "Cannot resolve safe target ancestor: $candidateFull" }
        $probe = $parent
    }
    $cursor = Get-Item -LiteralPath $probe -Force
    while ($null -ne $cursor -and -not $cursor.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals($baseFull, [StringComparison]::OrdinalIgnoreCase)) {
        if ($cursor.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Target path traverses a reparse point: $($cursor.FullName)" }
        $cursor = if ($cursor -is [IO.FileInfo]) { $cursor.Directory } else { $cursor.Parent }
    }
    if ($null -eq $cursor) { throw "Target path cannot be traced to install root: $candidateFull" }
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

function Write-AtomicUtf8Json([string]$Path, [object]$Value) {
    $json = ($Value | ConvertTo-Json -Depth 8) + [Environment]::NewLine
    $null = $json | ConvertFrom-Json
    $directory = Split-Path -Parent $Path
    $tempPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    try {
        $stream = [IO.FileStream]::new($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($tempPath, $Path, $null) }
        else { [IO.File]::Move($tempPath, $Path) }
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$targetRoot = Get-NormalizedRoot -SelectedScope $Scope -SelectedProject $ProjectPath
if ($Scope -eq 'User' -and -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $defaultCodexHome = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex')).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $configuredCodexHome = [IO.Path]::GetFullPath($env:CODEX_HOME).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $configuredCodexHome.Equals($defaultCodexHome, [StringComparison]::OrdinalIgnoreCase)) { throw 'NONDEFAULT_CODEX_HOME_UNVERIFIED：1.2.0 不猜测自定义 Codex home 下的角色/Skill 发现路径。' }
}
Assert-SafeInstallRoot -Root $targetRoot
$manifestRelative = '.codex/codex-fpga-engineering-workflow-zh.install.json'
$manifestPath = Join-Path $targetRoot ($manifestRelative -replace '/', [IO.Path]::DirectorySeparatorChar)

$deploymentMutex = $null
$deploymentMutexTaken = $false
if (-not $PlanOnly -and -not $WhatIfPreference) {
    $mutexHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($targetRoot.ToLowerInvariant()))).Substring(0, 24)
    $deploymentMutex = [Threading.Mutex]::new($false, "Local\CodexFpgaDeploy-$mutexHash")
    try { $deploymentMutexTaken = $deploymentMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $deploymentMutexTaken = $true }
    if (-not $deploymentMutexTaken) { $deploymentMutex.Dispose(); throw '同一部署根已有安装或卸载进程；不要并发重试。' }
}

try {
$mappings = [Collections.Generic.List[object]]::new()
$agentSource = Join-Path $packageRoot '.codex\agents'
Get-ChildItem -LiteralPath $agentSource -File -Filter '*.toml' | Sort-Object Name | ForEach-Object {
    $mappings.Add([pscustomobject]@{ Source = $_.FullName; Relative = ".codex/agents/$($_.Name)" })
}
foreach ($skillName in @('run-fpga-workflow','setup-fpga-workflow')) {
    $skillSource = Join-Path $packageRoot "skills\$skillName"
    Get-ChildItem -LiteralPath $skillSource -File -Recurse | Sort-Object FullName | ForEach-Object {
        $rel = Get-RelativePortablePath -Base $skillSource -Path $_.FullName
        $mappings.Add([pscustomobject]@{ Source = $_.FullName; Relative = ".agents/skills/$skillName/$rel" })
    }
}
if ($InstallAgentsTemplate) {
    $agentsTarget = if ($Scope -eq 'User') { '.codex/AGENTS.md' } else { 'AGENTS.md' }
    $mappings.Add([pscustomobject]@{ Source = (Join-Path $packageRoot 'templates\AGENTS.fpga.md'); Relative = $agentsTarget })
}

if (($mappings | Where-Object { $_.Relative -like '.codex/agents/*.toml' }).Count -ne 13) {
    throw 'Package must contain exactly 13 agent TOML files.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$plan = foreach ($mapping in $mappings) {
    $destination = Join-Path $targetRoot ($mapping.Relative -replace '/', [IO.Path]::DirectorySeparatorChar)
    Assert-SafeTargetPath -Base $targetRoot -Candidate $destination
    $sourceHash = (Get-FileHash -LiteralPath $mapping.Source -Algorithm SHA256).Hash
    $existing = Test-Path -LiteralPath $destination -PathType Leaf
    $same = $existing -and ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $sourceHash)
    if ($existing -and -not $same -and -not $Force) {
        throw "拒绝覆盖不同内容：$destination。请先审查差异；只有明确需要备份并替换时才使用 -Force。"
    }
    [pscustomobject]@{
        Source = $mapping.Source
        Relative = $mapping.Relative
        Destination = $destination
        SourceHash = $sourceHash
        Existing = $existing
        Same = $same
        Backup = if ($existing -and -not $same) { "$destination.backup-$timestamp" } else { $null }
    }
}

if ($PlanOnly) {
    $items = @($plan | ForEach-Object {
        [pscustomobject]@{
            relative_path = $_.Relative
            action = if ($_.Same) { 'UNCHANGED' } elseif ($_.Existing) { 'REPLACE_WITH_BACKUP' } else { 'CREATE' }
        }
    })
    [pscustomobject]@{
        status = 'PLAN_NO_CHANGES'
        scope = $Scope
        file_count = $items.Count
        create = @($items | Where-Object action -eq 'CREATE').Count
        unchanged = @($items | Where-Object action -eq 'UNCHANGED').Count
        replace_with_backup = @($items | Where-Object action -eq 'REPLACE_WITH_BACKUP').Count
        files = $items
    }
    return
}

$installed = [Collections.Generic.List[object]]::new()
foreach ($item in $plan) {
    if (-not $item.Same -and $PSCmdlet.ShouldProcess($item.Destination, 'Install workflow file')) {
        Assert-SafeInstallRoot -Root $targetRoot
        Assert-SafeTargetPath -Base $targetRoot -Candidate $item.Destination
        $parent = Split-Path -Parent $item.Destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Assert-SafeInstallRoot -Root $targetRoot
        Assert-SafeTargetPath -Base $targetRoot -Candidate $item.Destination
        if ($null -ne $item.Backup) {
            Assert-SafeTargetPath -Base $targetRoot -Candidate $item.Backup
            Copy-Item -LiteralPath $item.Destination -Destination $item.Backup
        }
        Assert-SafeTargetPath -Base $targetRoot -Candidate $item.Destination
        Copy-Item -LiteralPath $item.Source -Destination $item.Destination
    }
    if (-not $WhatIfPreference) {
        $installed.Add([pscustomobject]@{
            relativePath = $item.Relative
            sha256 = $item.SourceHash
            backupPath = if ($null -ne $item.Backup) { Get-RelativePortablePath -Base $targetRoot -Path $item.Backup } else { $null }
        })
    }
}

if (-not $WhatIfPreference -and $PSCmdlet.ShouldProcess($manifestPath, 'Write install manifest')) {
    Assert-SafeInstallRoot -Root $targetRoot
    Assert-SafeTargetPath -Base $targetRoot -Candidate $manifestPath
    $manifestParent = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $manifestParent -PathType Container)) { New-Item -ItemType Directory -Path $manifestParent -Force | Out-Null }
    Assert-SafeTargetPath -Base $targetRoot -Candidate $manifestPath
    $manifest = [ordered]@{
        schemaVersion = 1
        package = 'codex-fpga-engineering-workflow-zh'
        packageVersion = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()
        scope = $Scope
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        files = $installed
    }
    Write-AtomicUtf8Json -Path $manifestPath -Value $manifest
}

if ($WhatIfPreference) {
    Write-Host "预览完成：$Scope scope 将处理 $($mappings.Count) 个文件；当前没有写入。"
} else {
    Write-Host "已为 $Scope scope 安装 $($mappings.Count) 个文件。请运行 verify-install.ps1，并在核对后新开 Codex 会话。"
}
} finally {
    if ($deploymentMutexTaken) { try { $deploymentMutex.ReleaseMutex() } catch { } }
    if ($null -ne $deploymentMutex) { $deploymentMutex.Dispose() }
}
