[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('InitConfig','ValidateCase','Query')][string]$Action = 'Query',
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$CasePath,
    [string]$ProjectRoot,
    [string]$Query,
    [string]$OutputPath,
    [ValidateSet('','OFF','AFTERSALES_TRIAGE','FORMAL_REUSE')][string]$Mode = '',
    [ValidateRange(3,5)][int]$TopN = 5,
    [string]$Vendor,
    [string]$Tool,
    [string]$ToolVersion,
    [string]$Subsystem,
    [string]$Trigger
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$queryEngine = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\run-fpga-workflow\scripts\find-fpga-fault-case.ps1'

function Write-JsonFile([string]$Path, [object]$Value) {
    $full = [IO.Path]::GetFullPath($Path)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $full)) | Out-Null
    [IO.File]::WriteAllText($full, (($Value | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Assert-FaultCase([object]$Case) {
    $required = @('schema_version','case_id','status','confidentiality','vendor','subsystem','normalized_error_signature','symptom','trigger','root_cause','diagnostic_path','repair_principle','verification','applicability','counterexamples','evidence_hashes')
    $missing = @($required | Where-Object { $Case.PSObject.Properties.Name -notcontains $_ })
    if ($missing.Count) { throw "Missing fault-case fields: $($missing -join ', ')" }
    if ($Case.status -notin @('IMPORTED','ROOT_CAUSE_CONFIRMED','FIX_VERIFIED','BOARD_CONFIRMED','REUSABLE','REJECTED')) { throw "Invalid fault-case status: $($Case.status)" }
    if ($Case.schema_version -ne '0.3') { throw 'Fault-case schema_version must equal 0.3.' }
    if ([string]$Case.case_id -notmatch '^(?:SYNTH_[A-Z0-9_.:-]+|CASE[_:-][A-Z0-9_.:-]+|P[0-9]{8,16})$') { throw 'Fault-case case_id must be a normalized opaque identifier.' }
    foreach ($field in @('case_id','confidentiality','vendor','subsystem','normalized_error_signature','symptom','trigger','root_cause','repair_principle')) {
        if ([string]::IsNullOrWhiteSpace([string]$Case.$field)) { throw "Fault case requires non-empty $field." }
    }
    foreach ($field in @('diagnostic_path','verification','applicability','counterexamples','evidence_hashes')) {
        if ($Case.$field -isnot [System.Array]) { throw "Fault-case field must be an array: $field." }
    }
    if ($Case.status -eq 'REUSABLE') {
        foreach ($field in @('source_document','root_cause','repair_principle','independent_review','board_confirmation')) {
            if ($Case.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Case.$field)) { throw "REUSABLE fault case requires non-empty $field." }
        }
        foreach ($field in @('verification','applicability','counterexamples','evidence_hashes')) {
            if (@($Case.$field).Count -lt 1) { throw "REUSABLE fault case requires non-empty $field." }
        }
        if ([string]$Case.board_confirmation -eq 'NOT_APPLICABLE' -or (([string]$Case.board_confirmation).StartsWith('NOT_APPLICABLE:', [StringComparison]::OrdinalIgnoreCase) -and [string]::IsNullOrWhiteSpace(([string]$Case.board_confirmation).Substring('NOT_APPLICABLE:'.Length)))) { throw 'REUSABLE board_confirmation requires evidence or NOT_APPLICABLE:<reason>.' }
    }
}

if ($Action -eq 'InitConfig') {
    if (-not $PSCmdlet.ShouldProcess($ConfigPath, 'Create or replace fault-library configuration')) { return }
    $config = [ordered]@{
        schema_version='1.1.0'; enabled=$false; private_library_root=''; default_mode='OFF'
        allow_after_sales_triage=$false; top_n=5; query_output_relative='codex_out/<run-id>/knowledge/matches.json'; copy_source_documents=$false
    }
    Write-JsonFile $ConfigPath $config
    return [pscustomobject]@{ status='EMPTY_LIBRARY'; config=[IO.Path]::GetFullPath($ConfigPath) }
}

if ($Action -eq 'ValidateCase') {
    if ([string]::IsNullOrWhiteSpace($CasePath) -or -not (Test-Path -LiteralPath $CasePath -PathType Leaf)) { throw '-CasePath must identify an existing JSON file.' }
    $case = Get-Content -LiteralPath $CasePath -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-FaultCase $case
    return [pscustomobject]@{ status='VALID'; case_id=$case.case_id }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw 'Query requires an existing -ProjectRoot.' }
if (-not (Test-Path -LiteralPath $queryEngine -PathType Leaf)) { throw 'Canonical fault-library query engine is missing.' }

$arguments = @{ProjectRoot=$ProjectRoot;ConfigPath=$ConfigPath}
if ($PSBoundParameters.ContainsKey('Mode') -and -not [string]::IsNullOrWhiteSpace($Mode)) { $arguments.Mode = $Mode }
if ($PSBoundParameters.ContainsKey('TopN')) { $arguments.TopN = $TopN }
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $arguments.OutputPath = $OutputPath }
foreach ($pair in @(@('Query',$Query),@('Vendor',$Vendor),@('Tool',$Tool),@('ToolVersion',$ToolVersion),@('Subsystem',$Subsystem),@('Trigger',$Trigger))) {
    if (-not [string]::IsNullOrWhiteSpace([string]$pair[1])) { $arguments[$pair[0]] = [string]$pair[1] }
}
& $queryEngine @arguments
