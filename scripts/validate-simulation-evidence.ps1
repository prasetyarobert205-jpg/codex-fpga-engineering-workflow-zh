[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidencePath,
    [string]$ExpectedSnapshotId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) { throw "Simulation evidence file not found: $EvidencePath" }
$raw = Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8
$schemaPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\run-fpga-workflow\references\schemas\simulation-evidence.schema.json'
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Simulation evidence schema not found: $schemaPath" }
if (-not (Test-Json -Json $raw -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'Simulation evidence does not satisfy the JSON Schema.' }
$evidence = $raw | ConvertFrom-Json
$required = @('schema_version','run_id','snapshot_id','evidence_profile','classification','compile_exit_code','elaboration_exit_code','run_exit_code')
$missing = @($required | Where-Object { $evidence.PSObject.Properties.Name -notcontains $_ })
if ($missing.Count -gt 0) { throw "Missing simulation-evidence fields: $($missing -join ', ')" }
if (-not [string]::IsNullOrWhiteSpace($ExpectedSnapshotId) -and $evidence.snapshot_id -ne $ExpectedSnapshotId) { throw "Stale snapshot: expected $ExpectedSnapshotId, found $($evidence.snapshot_id)." }
$hasWaveformState = $evidence.PSObject.Properties.Name -contains 'waveform_consistency'
$hasLegacyWaveform = $evidence.PSObject.Properties.Name -contains 'manual_waveform_consistent'
if ($hasWaveformState -and $hasLegacyWaveform) { throw 'New waveform_consistency and legacy manual_waveform_consistent are mutually exclusive.' }

if ($evidence.classification -eq 'SIMULATION_PASS') {
    $passRequired = @('tests_discovered','tests_executed','scoreboard_drained','comparisons','negative_canaries','proof_packets')
    $passMissing = @($passRequired | Where-Object { $evidence.PSObject.Properties.Name -notcontains $_ })
    if ($passMissing.Count -gt 0) { throw "Missing SIMULATION_PASS fields: $($passMissing -join ', ')" }
    if ($evidence.evidence_profile -ne 'FUNCTIONAL_ACCEPTANCE') { throw 'SIMULATION_PASS is valid only for the FUNCTIONAL_ACCEPTANCE profile.' }
    if ([string]::IsNullOrWhiteSpace($ExpectedSnapshotId)) { throw 'SIMULATION_PASS validation requires -ExpectedSnapshotId.' }
    if ($evidence.compile_exit_code -ne 0 -or $evidence.elaboration_exit_code -ne 0 -or $evidence.run_exit_code -ne 0) { throw 'SIMULATION_PASS requires zero compile, elaboration, and run exit codes.' }
    if ($evidence.tests_discovered -lt 1 -or $evidence.tests_executed -lt 1 -or $evidence.tests_executed -gt $evidence.tests_discovered) { throw 'SIMULATION_PASS requires one or more executed tests and executed <= discovered.' }
    if (-not $evidence.scoreboard_drained) { throw 'SIMULATION_PASS requires a drained scoreboard.' }
    if (@($evidence.comparisons).Count -lt 1) { throw 'SIMULATION_PASS requires cycle-indexed comparisons.' }
    if (@($evidence.negative_canaries).Count -lt 1 -or @($evidence.negative_canaries | Where-Object { -not $_.detected }).Count -gt 0) { throw 'SIMULATION_PASS requires at least one negative canary and all canaries detected.' }
    if (@($evidence.proof_packets).Count -lt 1) { throw 'SIMULATION_PASS requires a non-empty proof packet.' }
    if ($hasWaveformState) {
        if ($evidence.waveform_consistency -notin @('NOT_APPLICABLE','CONSISTENT')) { throw 'SIMULATION_PASS requires waveform_consistency NOT_APPLICABLE or CONSISTENT.' }
    } elseif ($hasLegacyWaveform) {
        if ($evidence.manual_waveform_consistent -ne $true) { throw 'Legacy SIMULATION_PASS requires manual_waveform_consistent=true.' }
    } else {
        throw 'SIMULATION_PASS requires explicit waveform applicability/consistency or the legacy true field.'
    }
    $evidenceDirectory = [IO.Path]::GetFullPath((Split-Path -Parent (Resolve-Path -LiteralPath $EvidencePath).Path))
    $proofPrefix = $evidenceDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    foreach ($proof in @($evidence.proof_packets)) {
        if ([IO.Path]::IsPathRooted([string]$proof)) { throw "Proof-packet path must be relative to the evidence directory: $proof" }
        $proofPath = [IO.Path]::GetFullPath((Join-Path $evidenceDirectory ([string]$proof -replace '/', [IO.Path]::DirectorySeparatorChar)))
        if (-not $proofPath.StartsWith($proofPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $proofPath -PathType Leaf)) { throw "Proof-packet file is missing or outside the evidence directory: $proof" }
        $cursor = Get-Item -LiteralPath $proofPath -Force
        while ($null -ne $cursor) {
            if ($cursor.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Proof-packet path must not traverse a reparse point: $($cursor.FullName)" }
            if ($cursor.FullName.Equals($evidenceDirectory, [StringComparison]::OrdinalIgnoreCase)) { break }
            $cursor = if ($cursor -is [IO.FileInfo]) { $cursor.Directory } else { $cursor.Parent }
        }
    }
} elseif ($evidence.evidence_profile -eq 'FUNCTIONAL_ACCEPTANCE' -and $evidence.classification -in @('DUT_FAIL','TESTBENCH_FAIL','REFERENCE_MODEL_FAIL','ASSERTION_FAIL')) {
    if ($evidence.PSObject.Properties.Name -notcontains 'first_failure' -or $null -eq $evidence.first_failure) { throw 'A non-pass classification requires first_failure evidence.' }
}
[pscustomobject]@{ status = 'VALID'; classification = $evidence.classification; snapshot_id = $evidence.snapshot_id }
