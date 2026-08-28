[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [Parameter(Mandatory)]
    [string]$LibraryRoot,
    [Parameter(Mandatory)]
    [string]$OutputPath,
    [string]$ErrorSignature,
    [string]$Vendor,
    [string]$Tool,
    [string]$ToolVersion,
    [string]$Subsystem,
    [string]$Symptom,
    [switch]$IncludeNonReusable
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$library = (Resolve-Path -LiteralPath $LibraryRoot).Path
$codexRoot = [IO.Path]::GetFullPath((Join-Path $project 'codex_out'))
$outputFull = if ([IO.Path]::IsPathRooted($OutputPath)) {
    [IO.Path]::GetFullPath($OutputPath)
} else {
    [IO.Path]::GetFullPath((Join-Path $project $OutputPath))
}
$codexPrefix = $codexRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $outputFull.StartsWith($codexPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $outputFull.Equals($codexRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OUTPUT_SCOPE_FAIL: OutputPath must resolve strictly below '$codexRoot'."
}
if (Test-Path -LiteralPath $outputFull) {
    $outputItem = Get-Item -LiteralPath $outputFull -Force
    if (($outputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "OUTPUT_SCOPE_FAIL: existing OutputPath '$outputFull' may not be a reparse point."
    }
    if ($outputItem.PSIsContainer) {
        throw "OUTPUT_SCOPE_FAIL: existing OutputPath '$outputFull' must be a file, not a directory."
    }
}

$cursor = Split-Path -Parent $outputFull
while ($cursor -and $cursor.StartsWith($codexPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    if (Test-Path -LiteralPath $cursor) {
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "OUTPUT_SCOPE_FAIL: reparse-point output ancestor '$cursor' is not allowed."
        }
    }
    if ($cursor.Equals($codexRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
    $cursor = Split-Path -Parent $cursor
}
if (Test-Path -LiteralPath $codexRoot) {
    $codexItem = Get-Item -LiteralPath $codexRoot -Force
    if (($codexItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'OUTPUT_SCOPE_FAIL: codex_out may not be a reparse point.'
    }
}

$requiredStrings = @(
    'schema_version', 'case_id', 'status', 'confidentiality', 'vendor',
    'subsystem', 'normalized_error_signature', 'symptom', 'trigger',
    'root_cause', 'repair_principle'
)
$requiredArrays = @(
    'diagnostic_path', 'verification', 'applicability',
    'counterexamples', 'evidence_hashes'
)
$allowedStatus = @('IMPORTED', 'ROOT_CAUSE_CONFIRMED', 'FIX_VERIFIED', 'BOARD_CONFIRMED', 'REUSABLE', 'REJECTED')

function Get-CaseValidationErrors([object]$Case) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $names = @($Case.PSObject.Properties.Name)
    foreach ($field in $requiredStrings) {
        if ($names -notcontains $field) {
            $errors.Add("missing required field '$field'")
        } elseif ($Case.$field -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Case.$field)) {
            $errors.Add("field '$field' must be a non-empty string")
        }
    }
    foreach ($field in $requiredArrays) {
        if ($names -notcontains $field) {
            $errors.Add("missing required field '$field'")
        } elseif ($Case.$field -isnot [System.Array]) {
            $errors.Add("field '$field' must be an array")
        }
    }
    if ($names -contains 'schema_version' -and $Case.schema_version -ne '0.3') {
        $errors.Add("schema_version must equal '0.3'")
    }
    if ($names -contains 'status' -and $allowedStatus -notcontains $Case.status) {
        $errors.Add("status '$($Case.status)' is not allowed")
    }
    if ($names -contains 'status' -and $Case.status -eq 'REUSABLE') {
        foreach ($field in @('source_document', 'board_confirmation')) {
            if ($names -notcontains $field) {
                $errors.Add("REUSABLE case is missing required field '$field'")
            } elseif ($Case.$field -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Case.$field)) {
                $errors.Add("REUSABLE field '$field' must be a non-empty string")
            }
        }
        foreach ($field in @('verification', 'evidence_hashes', 'applicability')) {
            if ($names -contains $field -and $Case.$field -is [System.Array] -and @($Case.$field).Count -lt 1) {
                $errors.Add("REUSABLE field '$field' must contain at least one item")
            }
        }
    }
    return @($errors)
}

$cases = @()
$rejected = @()
foreach ($file in Get-ChildItem -LiteralPath $library -Recurse -Filter '*.json' -File) {
    $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    try {
        $case = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        $rejected += [pscustomobject]@{ source_hash = $sourceHash; reasons = @('invalid JSON') }
        continue
    }
    $validationErrors = @(Get-CaseValidationErrors $case)
    if ($validationErrors.Count -gt 0) {
        $rejected += [pscustomobject]@{ source_hash = $sourceHash; case_id = $case.case_id; reasons = $validationErrors }
        continue
    }
    if (-not $IncludeNonReusable -and $case.status -ne 'REUSABLE') { continue }
    $score = 0
    if ($ErrorSignature -and $case.normalized_error_signature -match [regex]::Escape($ErrorSignature)) { $score += 100 }
    if ($Vendor -and $case.vendor -eq $Vendor) { $score += 30 }
    if ($Tool -and $case.tool -eq $Tool) { $score += 20 }
    if ($ToolVersion -and $case.tool_version -eq $ToolVersion) { $score += 20 }
    if ($Subsystem -and $case.subsystem -eq $Subsystem) { $score += 20 }
    if ($Symptom -and $case.symptom -match [regex]::Escape($Symptom)) { $score += 10 }
    if ($score -gt 0) {
        $cases += [pscustomobject]@{
            case_id = $case.case_id
            status = $case.status
            score = $score
            vendor = $case.vendor
            tool = $case.tool
            tool_version = $case.tool_version
            subsystem = $case.subsystem
            normalized_error_signature = $case.normalized_error_signature
            symptom = $case.symptom
            applicability = @($case.applicability)
            counterexamples = @($case.counterexamples)
            evidence_hashes = @($case.evidence_hashes)
            source_hash = $sourceHash
        }
    }
}

$result = [ordered]@{
    schema_version = '0.3'
    status = 'CANDIDATES_ONLY_REVALIDATE_CURRENT_PROJECT'
    query = [ordered]@{
        error_signature = $ErrorSignature
        vendor = $Vendor
        tool = $Tool
        tool_version = $ToolVersion
        subsystem = $Subsystem
        symptom = $Symptom
    }
    matches = @($cases | Sort-Object -Property @{Expression = 'score'; Descending = $true}, @{Expression = 'case_id'; Descending = $false})
    rejected_entries = @($rejected)
}
$parent = Split-Path -Parent $outputFull
[IO.Directory]::CreateDirectory($parent) | Out-Null
[IO.File]::WriteAllText($outputFull, ($result | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$result
