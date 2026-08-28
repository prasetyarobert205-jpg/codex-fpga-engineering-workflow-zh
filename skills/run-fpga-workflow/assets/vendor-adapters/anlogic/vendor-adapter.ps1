[CmdletBinding()]
param([string]$Action, [string]$ProjectRoot, [string]$OutputDir, [string]$Case, [string]$Mode, [string]$Seed, [string]$LintTool)
$ExpectedVendor = 'ANLOGIC'
. (Join-Path $PSScriptRoot 'adapter-common.ps1')
Invoke-ConfiguredAdapter -ExpectedVendor $ExpectedVendor -Action $Action -ProjectRoot $ProjectRoot -OutputDir $OutputDir -Case $Case -Mode $Mode -Seed $Seed -LintTool $LintTool
