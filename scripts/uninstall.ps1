[CmdletBinding(SupportsShouldProcess)]
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
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Install manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.package -ne 'codex-fpga-engineering-workflow-zh' -or $manifest.scope -ne $Scope) { throw '安装清单身份或 scope 不匹配。' }

$rootPrefix = $targetRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$kept = 0
foreach ($entry in $manifest.files) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $targetRoot ($entry.relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe manifest path: $($entry.relativePath)" }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    if ($actual -ne $entry.sha256) {
        Write-Warning "Preserving modified file: $candidate"
        $kept++
        continue
    }
    if ($PSCmdlet.ShouldProcess($candidate, 'Remove unchanged installed file')) { Remove-Item -LiteralPath $candidate }
}

if ($kept -eq 0) {
    if ($PSCmdlet.ShouldProcess($manifestPath, 'Remove install manifest')) { Remove-Item -LiteralPath $manifestPath }
} else {
    Write-Warning "$kept modified file(s) were kept; manifest retained for audit."
}
Write-Host '卸载检查完成；没有递归删除任何目录树。'
