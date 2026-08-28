[CmdletBinding()]
param(
    [ValidateSet('User', 'Project')][string]$Scope = 'User',
    [string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$targetRoot = if ($Scope -eq 'User') {
    [IO.Path]::GetFullPath($env:USERPROFILE)
} else {
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { throw '-ProjectPath is required for Project scope.' }
    [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectPath).Path)
}
$manifestPath = Join-Path $targetRoot '.codex\codex-fpga-engineering-workflow-zh.install.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "找不到安装清单：$manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$errors = [Collections.Generic.List[string]]::new()
foreach ($entry in $manifest.files) {
    $path = Join-Path $targetRoot ($entry.relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("Missing: $path"); continue }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) { $errors.Add("Modified: $path") }
}
$agents = Get-ChildItem -LiteralPath (Join-Path $targetRoot '.codex\agents') -File -Filter '*.toml' -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -in @('fpga_architect','fpga_engineer','verification_engineer','fpga_temporal_evidence_reviewer','fpga_cdc_timing_reviewer','fpga_interface_architect','fpga_vendor_platform_reviewer','fpga_board_validation_engineer','fpga_reviewer','system_architect','embedded_engineer','hardware_datasheet','independent_reviewer') }
if ($agents.Count -ne 13) { $errors.Add("Expected 13 workflow agent files; found $($agents.Count).") }
$skillPath = Join-Path $targetRoot '.agents\skills\run-fpga-workflow\SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { $errors.Add("缺少 Skill：$skillPath") }
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_ }; throw '安装核对失败。' }
Write-Host '已安装文件与清单 SHA-256 全部一致。Fresh-session 的 Codex 发现行为仍需在新会话做只读 canary。'
