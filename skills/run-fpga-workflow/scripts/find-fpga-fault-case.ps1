[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [string]$ConfigPath,
    [string]$LibraryRoot,
    [string]$OutputPath,
    [ValidateSet('OFF','AFTERSALES_TRIAGE','FORMAL_REUSE')][string]$Mode = 'OFF',
    [ValidateRange(3,5)][int]$TopN = 5,
    [string]$Query,
    [string]$ErrorSignature,
    [string]$Vendor,
    [string]$Tool,
    [string]$ToolVersion,
    [string]$Subsystem,
    [string]$Symptom,
    [string]$Trigger,
    [ValidateSet('QUERY_DISABLED','CONFIG_MISSING','CONFIG_INVALID','CONFIG_UNAVAILABLE')][string]$DisabledReason = 'QUERY_DISABLED',
    [switch]$IncludeNonReusable
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$modeExplicit = $PSBoundParameters.ContainsKey('Mode')
$topNExplicit = $PSBoundParameters.ContainsKey('TopN')
if ($IncludeNonReusable) { $Mode = 'AFTERSALES_TRIAGE'; $modeExplicit = $true }

function Get-Tokens([string]$Text) {
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ($Text.ToLowerInvariant() -split '[\s,，;；、|/\\:：()（）\[\]{}]+')) {
        $token = $part.Trim()
        if ($token.Length -ge 2 -and $seen.Add($token)) { $tokens.Add($token) }
    }
    return @($tokens)
}

function Get-CaseValidationErrors([object]$Case) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $names = @($Case.PSObject.Properties.Name)
    foreach ($field in @('schema_version','case_id','status','confidentiality','vendor','subsystem','normalized_error_signature','symptom','trigger','root_cause','repair_principle')) {
        if ($names -notcontains $field -or $Case.$field -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Case.$field)) { $errors.Add("invalid required string '$field'") }
    }
    foreach ($field in @('diagnostic_path','verification','applicability','counterexamples','evidence_hashes')) {
        if ($names -notcontains $field -or $Case.$field -isnot [System.Array]) { $errors.Add("invalid required array '$field'") }
    }
    if ($Case.schema_version -ne '0.3') { $errors.Add('schema_version must equal 0.3') }
    if ([string]$Case.case_id -notmatch '^(?:SYNTH_[A-Z0-9_.:-]+|CASE[_:-][A-Z0-9_.:-]+|P[0-9]{8,16})$') { $errors.Add('case_id must be a normalized opaque identifier') }
    if ($Case.status -notin @('IMPORTED','ROOT_CAUSE_CONFIRMED','FIX_VERIFIED','BOARD_CONFIRMED','REUSABLE','REJECTED')) { $errors.Add('invalid status') }
    if ($Case.status -eq 'REUSABLE') {
        foreach ($field in @('source_document','root_cause','repair_principle','independent_review','board_confirmation')) {
            if ($names -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Case.$field)) { $errors.Add("REUSABLE missing '$field'") }
        }
        foreach ($field in @('verification','applicability','counterexamples','evidence_hashes')) {
            if (@($Case.$field).Count -lt 1) { $errors.Add("REUSABLE empty '$field'") }
        }
        if ([string]$Case.board_confirmation -eq 'NOT_APPLICABLE' -or
            (([string]$Case.board_confirmation).StartsWith('NOT_APPLICABLE:', [StringComparison]::OrdinalIgnoreCase) -and
             [string]::IsNullOrWhiteSpace(([string]$Case.board_confirmation).Substring('NOT_APPLICABLE:'.Length)))) {
            $errors.Add('REUSABLE board_confirmation requires evidence or NOT_APPLICABLE:<reason>')
        }
    }
    return @($errors)
}

function Add-FieldScore([string]$Name, [string]$Text, [string[]]$Tokens, [int]$Weight, [ref]$Score, [System.Collections.Generic.HashSet[string]]$Fields) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $lower = $Text.ToLowerInvariant()
    foreach ($token in $Tokens) {
        if ($lower.Contains($token)) { $Score.Value += $Weight; $null = $Fields.Add($Name) }
    }
}

function Get-OptionalValue([object]$Object, [string]$Name, $Default = $null) {
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function Get-SafeEnum([object]$Value, [string[]]$Allowed, [string]$Default = 'UNKNOWN') {
    $text = [string]$Value
    if ($text -in $Allowed) { return $text }
    return $Default
}

function Get-SafeDomains([object[]]$Values) {
    $allowed = @('FPGA_RTL_CANDIDATE','FPGA_PROTOCOL_INTERFACE_CANDIDATE','FIRMWARE_CANDIDATE','HOST_SOFTWARE_CANDIDATE','HARDWARE_ELECTRICAL_CANDIDATE','CONFIGURATION_CANDIDATE','PROCESS_CANDIDATE','MOTION_MECHANICAL_CANDIDATE','PRINTING_PROCESS_CANDIDATE','ENVIRONMENT_CANDIDATE','MIXED','UNKNOWN')
    $safe = @($Values | ForEach-Object { Get-SafeEnum $_ $allowed 'UNKNOWN' } | Select-Object -Unique)
    if ($safe.Count -eq 0) { return @('UNKNOWN') }
    return $safe
}

function Get-SafeSubsystem([object]$Value) {
    $parts = @(([string]$Value) -split '\+')
    $safe = @(Get-SafeDomains $parts)
    if ($safe -contains 'UNKNOWN') { return 'UNKNOWN' }
    return ($safe -join '+')
}

function Get-ConfigState([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return [pscustomobject]@{ supplied=$false; valid=$false; reason='QUERY_DISABLED'; config=$null } }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{ supplied=$true; valid=$false; reason='CONFIG_MISSING'; config=$null } }
    try { $config = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ supplied=$true; valid=$false; reason='CONFIG_INVALID'; config=$null } }
    $names = @($config.PSObject.Properties.Name)
    $valid = $false
    if ([string]$config.schema_version -eq '1.1.0') {
        $valid = $names -contains 'enabled' -and $config.enabled -is [bool] -and
            $names -contains 'private_library_root' -and $config.private_library_root -is [string] -and
            $names -contains 'default_mode' -and $config.default_mode -is [string] -and $config.default_mode -in @('OFF','AFTERSALES_TRIAGE','FORMAL_REUSE') -and
            $names -contains 'allow_after_sales_triage' -and $config.allow_after_sales_triage -is [bool] -and
            $names -contains 'top_n' -and ($config.top_n -is [int] -or $config.top_n -is [long]) -and [int]$config.top_n -ge 3 -and [int]$config.top_n -le 5 -and
            $names -contains 'query_output_relative' -and $config.query_output_relative -is [string] -and
            $names -contains 'copy_source_documents' -and $config.copy_source_documents -is [bool] -and $config.copy_source_documents -eq $false
    } elseif ([string]$config.schema_version -eq '1.0.0') {
        $valid = $names -contains 'enabled' -and $config.enabled -is [bool] -and
            $names -contains 'library_root' -and $config.library_root -is [string] -and
            ($names -notcontains 'allowed_status' -or ($config.allowed_status -is [System.Array] -and @($config.allowed_status) -notcontains 'REJECTED'))
    }
    $reason = if ($valid) { 'QUERY_DISABLED' } else { 'CONFIG_INVALID' }
    return [pscustomobject]@{ supplied=$true; valid=$valid; reason=$reason; config=$config }
}

function Publish-Result([object]$Result) {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { return }
    $codexRoot = [IO.Path]::GetFullPath((Join-Path $project 'codex_out'))
    $outputFull = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path $project $OutputPath)) }
    $prefix = $codexRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $outputFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $outputFull.Equals($codexRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OUTPUT_SCOPE_FAIL: output must resolve strictly below project codex_out.' }
    if (Test-Path -LiteralPath $codexRoot) {
        $codexItem = Get-Item -LiteralPath $codexRoot -Force
        if (($codexItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OUTPUT_SCOPE_FAIL: project codex_out may not be a reparse point.' }
    }
    if (Test-Path -LiteralPath $outputFull) {
        $item = Get-Item -LiteralPath $outputFull -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'OUTPUT_SCOPE_FAIL: existing output must be a regular file.' }
    }
    $cursor = Split-Path -Parent $outputFull
    while ($cursor -and $cursor.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OUTPUT_SCOPE_FAIL: reparse-point output ancestor.' }
        }
        if ($cursor.Equals($codexRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = Split-Path -Parent $cursor
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $outputFull)) | Out-Null
    [IO.File]::WriteAllText($outputFull, ($Result | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}

$configState = Get-ConfigState $ConfigPath
if ($configState.supplied) {
    if (-not $configState.valid) {
        $Mode = 'OFF'
        $DisabledReason = $configState.reason
    } elseif (-not [bool]$configState.config.enabled) {
        $Mode = 'OFF'
        $DisabledReason = 'QUERY_DISABLED'
    } else {
        $config = $configState.config
        if ([string]$config.schema_version -eq '1.1.0') {
            if (-not $modeExplicit) { $Mode = [string]$config.default_mode }
            if (-not $topNExplicit) { $TopN = [int]$config.top_n }
            if ($Mode -eq 'AFTERSALES_TRIAGE' -and -not [bool]$config.allow_after_sales_triage) { $Mode='OFF'; $DisabledReason='QUERY_DISABLED' }
            $LibraryRoot = [string]$config.private_library_root
        } else {
            if (-not $modeExplicit) { $Mode = 'FORMAL_REUSE' }
            if ($Mode -eq 'AFTERSALES_TRIAGE') { $Mode='OFF'; $DisabledReason='QUERY_DISABLED' }
            $LibraryRoot = [string]$config.library_root
        }
        if ($Mode -ne 'OFF' -and ([string]::IsNullOrWhiteSpace($LibraryRoot) -or -not (Test-Path -LiteralPath $LibraryRoot -PathType Container))) {
            $Mode = 'OFF'
            $DisabledReason = 'CONFIG_UNAVAILABLE'
        }
    }
}

if ($Mode -eq 'OFF') {
    $disabled = [ordered]@{ schema_version='0.4'; status=$DisabledReason; mode='OFF'; candidate_only=$true; query_token_count=0; raw_query_stored=$false; filters_supplied=[ordered]@{}; library_files_scanned=0; match_count=0; matches=@(); rejected_entries=@(); warning='Private fault-library query is disabled or unavailable.' }
    Publish-Result $disabled
    return [pscustomobject]$disabled
}

if ([string]::IsNullOrWhiteSpace($LibraryRoot) -or -not (Test-Path -LiteralPath $LibraryRoot -PathType Container)) { throw 'LIBRARY_UNAVAILABLE: enabled mode requires an existing LibraryRoot.' }
$library = (Resolve-Path -LiteralPath $LibraryRoot).Path
if (((Get-Item -LiteralPath $library -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'LIBRARY_REPARSE_POINT_BLOCKED' }
$nestedReparse = @(Get-ChildItem -LiteralPath $library -Force -Recurse | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
if ($nestedReparse.Count -gt 0) { throw 'LIBRARY_REPARSE_POINT_BLOCKED: nested reparse point detected.' }

$queryText = @($Query,$ErrorSignature,$Symptom,$Trigger | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
$tokens = @(Get-Tokens $queryText)
if ($tokens.Count -eq 0) { throw 'QUERY_HAS_NO_USABLE_TOKENS' }

$files = @(Get-ChildItem -LiteralPath $library -Filter '*.json' -File -Recurse)
$idCounts = @{}
foreach ($file in $files) {
    try { $candidate = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    $id = [string]$candidate.case_id
    if (-not [string]::IsNullOrWhiteSpace($id)) { $key=$id.ToLowerInvariant(); if (-not $idCounts.ContainsKey($key)){$idCounts[$key]=0}; $idCounts[$key]++ }
}
$duplicates = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $idCounts.GetEnumerator()) { if ($entry.Value -gt 1) { $null=$duplicates.Add([string]$entry.Key) } }

$candidateMatches = [System.Collections.Generic.List[object]]::new()
$rejected = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    try { $case = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop }
    catch { $rejected.Add([pscustomobject]@{ reasons=@('invalid JSON') }); continue }
    $caseId = [string]$case.case_id
    $validationErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($error in @(Get-CaseValidationErrors $case)) { $validationErrors.Add($error) }
    if (-not [string]::IsNullOrWhiteSpace($caseId) -and $duplicates.Contains($caseId)) { $validationErrors.Add('duplicate case_id') }
    if ($validationErrors.Count) {
        $rejected.Add([pscustomobject]@{ reasons=@($validationErrors) })
        continue
    }
    if ($case.status -eq 'REJECTED') { continue }
    if ($Mode -eq 'FORMAL_REUSE' -and $case.status -ne 'REUSABLE') { continue }

    $score = 0
    $fields = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    Add-FieldScore 'signature' ([string]$case.normalized_error_signature) $tokens 30 ([ref]$score) $fields
    Add-FieldScore 'symptom' ([string]$case.symptom) $tokens 20 ([ref]$score) $fields
    Add-FieldScore 'trigger' ([string]$case.trigger) $tokens 20 ([ref]$score) $fields
    Add-FieldScore 'root_cause_claim' ([string]$case.root_cause) $tokens 12 ([ref]$score) $fields
    Add-FieldScore 'diagnostic_path' ((@($case.diagnostic_path)-join ' ')) $tokens 12 ([ref]$score) $fields
    Add-FieldScore 'repair_claim' ([string]$case.repair_principle) $tokens 8 ([ref]$score) $fields
    Add-FieldScore 'keywords' ((@(Get-OptionalValue $case 'keywords' @())-join ' ')) $tokens 12 ([ref]$score) $fields
    Add-FieldScore 'counterexamples' ((@($case.counterexamples)-join ' ')) $tokens 6 ([ref]$score) $fields
    if ($Vendor -and $case.vendor -eq $Vendor) { $score+=25; $null=$fields.Add('vendor') }
    if ($Tool -and (Get-OptionalValue $case 'tool' '') -eq $Tool) { $score+=15; $null=$fields.Add('tool') }
    if ($ToolVersion -and (Get-OptionalValue $case 'tool_version' '') -eq $ToolVersion) { $score+=15; $null=$fields.Add('tool_version') }
    if ($Subsystem -and $case.subsystem -eq $Subsystem) { $score+=20; $null=$fields.Add('subsystem') }
    if ($score -le 0) { continue }
    $safeSourceStatus = if ([string]::IsNullOrWhiteSpace([string](Get-OptionalValue $case 'source_status' ''))) { 'NOT_RECORDED' } else { 'SOURCE_STATUS_RECORDED' }
    $safeRootCauseState = Get-SafeEnum (Get-OptionalValue $case 'root_cause_state' '') @('UNKNOWN','CLAIMED_UNVERIFIED','CLAIMED','CONFIRMED') 'UNKNOWN'
    $safeValidationState = Get-SafeEnum (Get-OptionalValue $case 'validation_state' '') @('UNKNOWN','NOT_RECORDED','NOT_CONFIRMED','PASS_CLAIMED','FAIL_CLAIMED','VERIFIED') 'UNKNOWN'
    $safeSubsystem = Get-SafeSubsystem $case.subsystem
    $safeDomains = @(Get-SafeDomains @(Get-OptionalValue $case 'domain_candidates' @()))
    $safeOwner = Get-SafeEnum (Get-OptionalValue $case 'primary_owner_candidate' '') @('FPGA_RTL_CANDIDATE','FPGA_PROTOCOL_INTERFACE_CANDIDATE','FIRMWARE_CANDIDATE','HOST_SOFTWARE_CANDIDATE','HARDWARE_ELECTRICAL_CANDIDATE','CONFIGURATION_CANDIDATE','PROCESS_CANDIDATE','MOTION_MECHANICAL_CANDIDATE','PRINTING_PROCESS_CANDIDATE','ENVIRONMENT_CANDIDATE','CROSS_DOMAIN_TRIAGE','OWNER_UNKNOWN','UNKNOWN') 'UNKNOWN'
    $candidateMatches.Add([pscustomobject]@{
        case_id=$caseId; lifecycle=[string]$case.status; source_status=$safeSourceStatus
        root_cause_state=$safeRootCauseState; validation_state=$safeValidationState
        subsystem=$safeSubsystem; domain_candidates=$safeDomains
        primary_owner_candidate=$safeOwner; candidate_only=$true
        score=$score; matched_fields=@($fields|Sort-Object)
    })
}

$selected = @($candidateMatches | Sort-Object -Property @{Expression='score';Descending=$true}, @{Expression='case_id';Descending=$false} | Select-Object -First $TopN)
$result = [ordered]@{
    schema_version='0.4'; status='CANDIDATES_ONLY_REVALIDATE_CURRENT_PROJECT'; mode=$Mode; candidate_only=$true
    query_token_count=$tokens.Count; raw_query_stored=$false
    filters_supplied=[ordered]@{vendor=[bool]$Vendor;tool=[bool]$Tool;tool_version=[bool]$ToolVersion;subsystem=[bool]$Subsystem;trigger=[bool]$Trigger}
    library_files_scanned=$files.Count; match_count=$selected.Count; matches=$selected; rejected_entries=@($rejected)
    warning='Historical matches are investigation candidates and do not prove the current-project root cause.'
}
Publish-Result $result
[pscustomobject]$result
