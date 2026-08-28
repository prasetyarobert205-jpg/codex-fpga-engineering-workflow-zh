[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('InitConfig', 'ValidateCase', 'Query')][string]$Action = 'Query',
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$CasePath,
    [string]$ProjectRoot,
    [string]$Query,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$requiredFields = @('case_id','status','source_document','confidentiality','vendor','tool','subsystem','normalized_error_signature','symptom','trigger','root_cause','diagnostic_path','failed_attempts','repair_principle','verification','board_confirmation','applicability','counterexamples','keywords','evidence_hashes')
$allowedStatus = @('IMPORTED','ROOT_CAUSE_CONFIRMED','FIX_VERIFIED','BOARD_CONFIRMED','REUSABLE','REJECTED')

function Write-JsonFile([string]$Path, [object]$Value) {
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($full, (($Value | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Assert-FaultCase([object]$Case) {
    $missing = @($requiredFields | Where-Object { $Case.PSObject.Properties.Name -notcontains $_ })
    if ($missing.Count -gt 0) { throw "Missing fault-case fields: $($missing -join ', ')" }
    if ($Case.status -notin $allowedStatus) { throw "Invalid fault-case status: $($Case.status)" }
    foreach ($field in @('case_id','source_document','confidentiality','vendor','subsystem','normalized_error_signature','symptom','trigger')) {
        if ([string]::IsNullOrWhiteSpace([string]$Case.$field)) { throw "Fault case requires non-empty $field." }
    }
    foreach ($field in @('diagnostic_path','failed_attempts','verification','applicability','counterexamples','keywords','evidence_hashes')) {
        if ($Case.$field -is [string] -or $null -eq $Case.$field) { throw "Fault-case field must be an array: $field." }
    }
    if ($Case.status -eq 'REUSABLE') {
        foreach ($field in @('root_cause','repair_principle','independent_review','board_confirmation')) {
            if ($Case.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Case.$field)) { throw "REUSABLE fault case requires non-empty $field." }
        }
        foreach ($field in @('verification','applicability','counterexamples','evidence_hashes')) {
            if (@($Case.$field).Count -lt 1) { throw "REUSABLE fault case requires non-empty $field." }
        }
        if ([string]$Case.board_confirmation -eq 'NOT_APPLICABLE' -or ([string]$Case.board_confirmation).StartsWith('NOT_APPLICABLE:', [StringComparison]::OrdinalIgnoreCase) -and [string]::IsNullOrWhiteSpace(([string]$Case.board_confirmation).Substring('NOT_APPLICABLE:'.Length))) {
            throw 'REUSABLE fault case board_confirmation must contain evidence or NOT_APPLICABLE:<reason>.'
        }
    }
}

if ($Action -eq 'InitConfig') {
    if ((Test-Path -LiteralPath $ConfigPath) -and -not $PSCmdlet.ShouldProcess($ConfigPath, 'Replace fault-library configuration')) { return }
    $config = [ordered]@{ schema_version = '1.0.0'; enabled = $false; library_root = ''; allowed_status = @('ROOT_CAUSE_CONFIRMED','FIX_VERIFIED','BOARD_CONFIRMED','REUSABLE') }
    Write-JsonFile -Path $ConfigPath -Value $config
    [pscustomobject]@{ status = 'EMPTY_LIBRARY'; config = [IO.Path]::GetFullPath($ConfigPath) }
    return
}

if ($Action -eq 'ValidateCase') {
    if ([string]::IsNullOrWhiteSpace($CasePath) -or -not (Test-Path -LiteralPath $CasePath -PathType Leaf)) { throw '-CasePath must identify an existing JSON file.' }
    $case = Get-Content -LiteralPath $CasePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-FaultCase -Case $case
    [pscustomobject]@{ status = 'VALID'; case_id = $case.case_id }
    return
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw 'Query requires an existing -ProjectRoot.' }
$projectRootFull = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$codexOut = [IO.Path]::GetFullPath((Join-Path $projectRootFull 'codex_out'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
    $OutputPath = Join-Path $codexOut "$runId\knowledge\matches.json"
}
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$outputPrefix = $codexOut.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $outputFull.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Query output must stay beneath project-root codex_out: $outputFull" }
$cursorPath = if (Test-Path -LiteralPath $outputFull) { $outputFull } else { Split-Path -Parent $outputFull }
while (-not [string]::IsNullOrWhiteSpace($cursorPath) -and $cursorPath.StartsWith($codexOut, [StringComparison]::OrdinalIgnoreCase)) {
    if (Test-Path -LiteralPath $cursorPath) {
        $cursorItem = Get-Item -LiteralPath $cursorPath -Force
        if ($cursorItem.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Query output path must not traverse an existing reparse point: $cursorPath" }
    }
    if ($cursorPath.Equals($codexOut, [StringComparison]::OrdinalIgnoreCase)) { break }
    $cursorPath = Split-Path -Parent $cursorPath
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    $result = [ordered]@{ status = 'EMPTY_LIBRARY'; message = 'Private fault-library configuration does not exist.'; matches = @() }
} else {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.enabled -or [string]::IsNullOrWhiteSpace([string]$config.library_root) -or -not (Test-Path -LiteralPath $config.library_root -PathType Container)) {
        $result = [ordered]@{ status = 'EMPTY_LIBRARY'; message = 'Private fault library is disabled, unconfigured, or unavailable.'; matches = @() }
    } else {
        $terms = @(([string]$Query).ToLowerInvariant().Split(' ', [StringSplitOptions]::RemoveEmptyEntries))
        $invalidCaseCount = 0
        $matches = foreach ($file in Get-ChildItem -LiteralPath $config.library_root -File -Filter '*.json' -Recurse) {
            try { $case = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; Assert-FaultCase -Case $case } catch { $invalidCaseCount++; continue }
            if ($case.status -notin @($config.allowed_status)) { continue }
            $haystack = (@($case.normalized_error_signature, $case.symptom, $case.trigger, $case.root_cause, $case.subsystem, $case.vendor) + @($case.keywords)) -join ' '
            $score = @($terms | Where-Object { $haystack.ToLowerInvariant().Contains($_) }).Count
            if ($terms.Count -eq 0 -or $score -gt 0) {
                [ordered]@{ case_id = $case.case_id; status = $case.status; confidence = if ($case.status -eq 'REUSABLE') {'REUSABLE_CANDIDATE'} else {'UNVERIFIED_LEAD'}; vendor = $case.vendor; subsystem = $case.subsystem; normalized_error_signature = $case.normalized_error_signature; score = $score }
            }
        }
        $result = [ordered]@{ status = 'CANDIDATE_MATCHES'; message = 'Matches are diagnostic leads and require current-project verification.'; invalid_case_count = $invalidCaseCount; matches = @($matches | Sort-Object -Property @{Expression='score';Descending=$true}, case_id) }
    }
}
Write-JsonFile -Path $outputFull -Value $result
[pscustomobject]$result
