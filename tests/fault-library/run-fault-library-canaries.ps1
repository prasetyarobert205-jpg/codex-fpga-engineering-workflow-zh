[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$engine = Join-Path $repo 'skills\run-fpga-workflow\scripts\find-fpga-fault-case.ps1'
$wrapper = Join-Path $repo 'scripts\fault-library.ps1'
$library = Join-Path $PSScriptRoot 'fixtures'
$expectedIds = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'canaries.json') -Raw -Encoding utf8 | ConvertFrom-Json)
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ('codex-fpga-fault-canary-' + [Guid]::NewGuid().ToString('N'))
$project = Join-Path $tempRoot 'project'
[IO.Directory]::CreateDirectory($project) | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Id, [bool]$Passed, [string]$Message = '') {
    $results.Add([pscustomobject]@{ id=$Id; passed=$Passed; message=$Message })
}
function Invoke-Engine([string]$Mode, [string]$Query, [hashtable]$Extra = @{}) {
    $parameters = @{ProjectRoot=$project;LibraryRoot=$library;Mode=$Mode;Query=$Query;TopN=5}
    foreach ($entry in $Extra.GetEnumerator()) { $parameters[$entry.Key] = [string]$entry.Value }
    return & $engine @parameters
}
function Assert-Whitelist([object]$Object) {
    $topAllowed = @('schema_version','status','mode','candidate_only','query_token_count','raw_query_stored','filters_supplied','library_files_scanned','match_count','matches','rejected_entries','warning')
    $matchAllowed = @('case_id','lifecycle','source_status','root_cause_state','validation_state','subsystem','domain_candidates','primary_owner_candidate','candidate_only','score','matched_fields')
    foreach ($name in @($Object.PSObject.Properties.Name)) { if ($name -notin $topAllowed) { throw "unexpected top-level field: $name" } }
    foreach ($match in @($Object.matches)) {
        foreach ($name in @($match.PSObject.Properties.Name)) { if ($name -notin $matchAllowed) { throw "unexpected match field: $name" } }
        if ($match.lifecycle -eq 'REJECTED') { throw 'REJECTED match returned' }
    }
}
function Test-Throws([scriptblock]$Action) {
    try { & $Action | Out-Null; return $false } catch { return $true }
}

try {
    $off = & $engine -ProjectRoot $project -LibraryRoot (Join-Path $tempRoot 'does-not-exist') -Mode OFF -Query 'ignored'
    Add-Result 'MODE_OFF_NO_SCAN' ($off.status -eq 'QUERY_DISABLED' -and $off.library_files_scanned -eq 0 -and $off.match_count -eq 0)

    $defaultOff = & $engine -ProjectRoot $project -LibraryRoot $library -Query 'fifo backpressure'
    Add-Result 'ENGINE_DEFAULT_OFF' ($defaultOff.status -eq 'QUERY_DISABLED' -and $defaultOff.library_files_scanned -eq 0 -and $defaultOff.match_count -eq 0)

    $triage = Invoke-Engine 'AFTERSALES_TRIAGE' 'fifo backpressure'
    Add-Result 'TRIAGE_RETURNS_IMPORTED' (@($triage.matches.case_id) -contains 'SYNTH_FPGA_IMPORTED')

    $formalImported = Invoke-Engine 'FORMAL_REUSE' 'fifo backpressure'
    Add-Result 'FORMAL_EXCLUDES_IMPORTED' ($formalImported.match_count -eq 0)

    $formal = Invoke-Engine 'FORMAL_REUSE' 'synthformalreuseonly'
    Add-Result 'FORMAL_RETURNS_VALID_REUSABLE' ($formal.match_count -eq 1 -and $formal.matches[0].case_id -eq 'SYNTH_VALID_REUSABLE')

    $rejected = Invoke-Engine 'AFTERSALES_TRIAGE' 'synthrejectedonly'
    Add-Result 'REJECTED_ALWAYS_EXCLUDED' ($rejected.match_count -eq 0)

    $malformed = Invoke-Engine 'AFTERSALES_TRIAGE' 'synthmalformedonly'
    Add-Result 'MALFORMED_EXCLUDED' ($malformed.match_count -eq 0 -and @($malformed.rejected_entries).Count -ge 4)

    $duplicate = Invoke-Engine 'AFTERSALES_TRIAGE' 'synthduplicateonly'
    $duplicateRejects = @($duplicate.rejected_entries | Where-Object { @($_.reasons) -contains 'duplicate case_id' }).Count
    $duplicateRejectedJson = $duplicate.rejected_entries | ConvertTo-Json -Depth 6
    Add-Result 'DUPLICATE_ID_FAIL_CLOSED' ($duplicate.match_count -eq 0 -and $duplicateRejects -eq 2 -and -not $duplicateRejectedJson.Contains('SYNTH_DUPLICATE'))

    $fake = Invoke-Engine 'FORMAL_REUSE' 'synthfakereusableonly'
    Add-Result 'FAKE_REUSABLE_EXCLUDED' ($fake.match_count -eq 0)

    $generic = Invoke-Engine 'AFTERSALES_TRIAGE' 'synthetic output corruption under load'
    $genericOwners = @($generic.matches.primary_owner_candidate | Select-Object -Unique)
    Add-Result 'HARD_NEGATIVE_BOTH_DOMAINS' (@($generic.matches.case_id) -contains 'SYNTH_FPGA_IMPORTED' -and @($generic.matches.case_id) -contains 'SYNTH_NONLOGIC_IMPORTED' -and $genericOwners.Count -ge 2)

    $fpga = Invoke-Engine 'AFTERSALES_TRIAGE' 'fifo backpressure ready late'
    Add-Result 'HARD_NEGATIVE_FPGA_RANK' ($fpga.matches[0].case_id -eq 'SYNTH_FPGA_IMPORTED')

    $nonlogic = Invoke-Engine 'AFTERSALES_TRIAGE' 'power droop reset glitch'
    Add-Result 'HARD_NEGATIVE_NONLOGIC_RANK' ($nonlogic.matches[0].case_id -eq 'SYNTH_NONLOGIC_IMPORTED')

    $prompt = Invoke-Engine 'AFTERSALES_TRIAGE' 'synthpromptinjectiononly'
    $promptJson = $prompt | ConvertTo-Json -Depth 10
    Add-Result 'SOURCE_PROMPT_NOT_EXECUTED' ($prompt.mode -eq 'AFTERSALES_TRIAGE' -and -not $promptJson.Contains('SYNTH_PROMPT_OVERRIDE_001') -and -not $promptJson.Contains('SYNTH_PRIVATE_') -and $prompt.matches[0].subsystem -eq 'UNKNOWN' -and $prompt.matches[0].primary_owner_candidate -eq 'UNKNOWN')

    $privateQuery = 'fifo SYNTH_PRIVATE_QUERY_7F2A'
    $private = Invoke-Engine 'AFTERSALES_TRIAGE' $privateQuery
    $privateJson = $private | ConvertTo-Json -Depth 10
    Add-Result 'PRIVATE_QUERY_NOT_WRITTEN' ($private.raw_query_stored -eq $false -and $private.PSObject.Properties.Name -notcontains 'query_sha256' -and -not $privateJson.Contains('SYNTH_PRIVATE_QUERY_7F2A'))

    $filters = Invoke-Engine 'AFTERSALES_TRIAGE' 'fifo' @{Vendor='SYNTH_PRIVATE_VENDOR';ToolVersion='SYNTH_PRIVATE_TOOL';Subsystem='SYNTH_PRIVATE_SUBSYSTEM'}
    $filterJson = $filters | ConvertTo-Json -Depth 10
    Add-Result 'PRIVATE_FILTERS_NOT_WRITTEN' (-not $filterJson.Contains('SYNTH_PRIVATE_VENDOR') -and -not $filterJson.Contains('SYNTH_PRIVATE_TOOL') -and -not $filterJson.Contains('SYNTH_PRIVATE_SUBSYSTEM'))

    $validOutput = 'codex_out\fault-canary\matches.json'
    & $engine -ProjectRoot $project -LibraryRoot $library -Mode AFTERSALES_TRIAGE -Query 'fifo' -OutputPath $validOutput | Out-Null
    $outsideBlocked = Test-Throws { & $engine -ProjectRoot $project -LibraryRoot $library -Mode AFTERSALES_TRIAGE -Query 'fifo' -OutputPath 'outside.json' }
    $rootBlocked = Test-Throws { & $engine -ProjectRoot $project -LibraryRoot $library -Mode AFTERSALES_TRIAGE -Query 'fifo' -OutputPath 'codex_out' }
    Add-Result 'OUTPUT_SCOPE_ENFORCED' ((Test-Path -LiteralPath (Join-Path $project $validOutput)) -and $outsideBlocked -and $rootBlocked)

    $topLowBlocked = Test-Throws { & $engine -ProjectRoot $project -LibraryRoot $library -Mode AFTERSALES_TRIAGE -Query 'fifo' -TopN 2 }
    $topHighBlocked = Test-Throws { & $engine -ProjectRoot $project -LibraryRoot $library -Mode AFTERSALES_TRIAGE -Query 'fifo' -TopN 6 }
    $repeat = Invoke-Engine 'AFTERSALES_TRIAGE' 'synthetic output corruption under load'
    $deterministic = ((@($generic.matches.case_id) -join ',') -eq (@($repeat.matches.case_id) -join ','))
    $canonicalAccepted = $true
    try { Assert-Whitelist $generic } catch { $canonicalAccepted = $false }
    $privacyMutation = $generic | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $privacyMutation.matches[0] | Add-Member -NotePropertyName matched_terms -NotePropertyValue @('SYNTH_PRIVATE_QUERY_7F2A')
    $privacyMutationCaught = Test-Throws { Assert-Whitelist $privacyMutation }
    $rejectedMutation = $generic | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $rejectedMutation.matches[0].lifecycle = 'REJECTED'
    $rejectedMutationCaught = Test-Throws { Assert-Whitelist $rejectedMutation }
    Add-Result 'TOPN_DETERMINISM_AND_MUTATION' ($topLowBlocked -and $topHighBlocked -and $deterministic -and $canonicalAccepted -and $privacyMutationCaught -and $rejectedMutationCaught)

    $canonicalConfig = Join-Path $tempRoot 'fault-library.config.local.json'
    & $wrapper -Action InitConfig -ConfigPath $canonicalConfig -WhatIf | Out-Null
    Add-Result 'CONFIG_WHATIF_NO_WRITE' (-not (Test-Path -LiteralPath $canonicalConfig))
    & $wrapper -Action InitConfig -ConfigPath $canonicalConfig | Out-Null
    $configObject = Get-Content -LiteralPath $canonicalConfig -Raw -Encoding utf8 | ConvertFrom-Json
    $disabledByConfig = & $wrapper -Action Query -ConfigPath $canonicalConfig -ProjectRoot $project -Mode AFTERSALES_TRIAGE -Query 'fifo'
    Add-Result 'CONFIG_CANONICAL_DISABLED' ($configObject.schema_version -eq '1.1.0' -and $configObject.enabled -eq $false -and $configObject.default_mode -eq 'OFF' -and $disabledByConfig.status -eq 'QUERY_DISABLED')

    $engineDisabled = & $engine -ProjectRoot $project -ConfigPath $canonicalConfig -Mode AFTERSALES_TRIAGE -Query 'fifo'
    $engineInvalidPath = Join-Path $tempRoot 'engine-invalid-config.json'
    $engineInvalidConfig = [ordered]@{schema_version='1.1.0';enabled='false';private_library_root=$library;default_mode='AFTERSALES_TRIAGE';allow_after_sales_triage=$true;top_n=5;query_output_relative='codex_out/<run-id>/knowledge/matches.json';copy_source_documents=$false}
    [IO.File]::WriteAllText($engineInvalidPath, ($engineInvalidConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $engineInvalid = & $engine -ProjectRoot $project -ConfigPath $engineInvalidPath -Mode AFTERSALES_TRIAGE -Query 'fifo'
    Add-Result 'ENGINE_CONFIG_DISABLED_INVALID' ($engineDisabled.status -eq 'QUERY_DISABLED' -and $engineDisabled.library_files_scanned -eq 0 -and $engineInvalid.status -eq 'CONFIG_INVALID' -and $engineInvalid.library_files_scanned -eq 0)

    $configObject.enabled = $true
    $configObject.allow_after_sales_triage = $true
    $configObject.private_library_root = $library
    [IO.File]::WriteAllText($canonicalConfig, ($configObject | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $triageByConfig = & $wrapper -Action Query -ConfigPath $canonicalConfig -ProjectRoot $project -Mode AFTERSALES_TRIAGE -Query 'fifo backpressure'
    Add-Result 'CONFIG_CANONICAL_TRIAGE' (@($triageByConfig.matches.case_id) -contains 'SYNTH_FPGA_IMPORTED')
    $engineTriage = & $engine -ProjectRoot $project -ConfigPath $canonicalConfig -Mode AFTERSALES_TRIAGE -Query 'fifo backpressure'
    Add-Result 'ENGINE_CONFIG_TRIAGE' (@($engineTriage.matches.case_id) -contains 'SYNTH_FPGA_IMPORTED')

    $legacyConfig = Join-Path $tempRoot 'fault-library.legacy.json'
    $legacy = [ordered]@{schema_version='1.0.0';enabled=$true;library_root=$library;allowed_status=@('REUSABLE')}
    [IO.File]::WriteAllText($legacyConfig, ($legacy | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $legacyResult = & $wrapper -Action Query -ConfigPath $legacyConfig -ProjectRoot $project -Query 'synthformalreuseonly'
    Add-Result 'CONFIG_LEGACY_COMPATIBLE' ($legacyResult.match_count -eq 1 -and $legacyResult.matches[0].case_id -eq 'SYNTH_VALID_REUSABLE')

    $validCaseAccepted = $true
    try { & $wrapper -Action ValidateCase -ConfigPath $canonicalConfig -CasePath (Join-Path $library 'synth-valid-reusable.json') | Out-Null } catch { $validCaseAccepted = $false }
    $fakeCaseBlocked = Test-Throws { & $wrapper -Action ValidateCase -ConfigPath $canonicalConfig -CasePath (Join-Path $library 'synth-fake-reusable.json') }
    $unsafeId = Get-Content -LiteralPath (Join-Path $library 'synth-fpga-imported.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $unsafeId.case_id = 'SYNTH PRIVATE CUSTOMER'
    $unsafeIdPath = Join-Path $tempRoot 'unsafe-id.json'
    [IO.File]::WriteAllText($unsafeIdPath, ($unsafeId | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    $unsafeIdBlocked = Test-Throws { & $wrapper -Action ValidateCase -ConfigPath $canonicalConfig -CasePath $unsafeIdPath }
    Add-Result 'VALIDATE_CASE_CONSISTENT' ($validCaseAccepted -and $fakeCaseBlocked -and $unsafeIdBlocked)

    $baseCase = Get-Content -LiteralPath (Join-Path $library 'synth-fpga-imported.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $badDiagnostic = $baseCase | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $badDiagnostic.diagnostic_path = 123
    $badDiagnosticPath = Join-Path $tempRoot 'bad-diagnostic.json'
    [IO.File]::WriteAllText($badDiagnosticPath, ($badDiagnostic | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    $badVerification = $baseCase | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $badVerification.verification = [pscustomobject]@{value='not-an-array'}
    $badVerificationPath = Join-Path $tempRoot 'bad-verification.json'
    [IO.File]::WriteAllText($badVerificationPath, ($badVerification | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    $badDiagnosticBlocked = Test-Throws { & $wrapper -Action ValidateCase -ConfigPath $canonicalConfig -CasePath $badDiagnosticPath }
    $badVerificationBlocked = Test-Throws { & $wrapper -Action ValidateCase -ConfigPath $canonicalConfig -CasePath $badVerificationPath }
    Add-Result 'VALIDATE_CASE_ARRAY_TYPES' ($badDiagnosticBlocked -and $badVerificationBlocked)

    $schemaPath = Join-Path $repo 'skills\run-fpga-workflow\references\schemas\fault-case.schema.json'
    $validReusablePath = Join-Path $library 'synth-valid-reusable.json'
    $fakeReusablePath = Join-Path $library 'synth-fake-reusable.json'
    $bareBoard = Get-Content -LiteralPath $validReusablePath -Raw -Encoding utf8 | ConvertFrom-Json
    $bareBoard.board_confirmation = 'NOT_APPLICABLE'
    $bareBoardPath = Join-Path $tempRoot 'bare-board.json'
    [IO.File]::WriteAllText($bareBoardPath, ($bareBoard | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    $schemaValid = Test-Json -Json (Get-Content -LiteralPath $validReusablePath -Raw -Encoding utf8) -SchemaFile $schemaPath -ErrorAction SilentlyContinue
    $schemaFakeBlocked = -not (Test-Json -Json (Get-Content -LiteralPath $fakeReusablePath -Raw -Encoding utf8) -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
    $schemaBadDiagnosticBlocked = -not (Test-Json -Json (Get-Content -LiteralPath $badDiagnosticPath -Raw -Encoding utf8) -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
    $schemaBadVerificationBlocked = -not (Test-Json -Json (Get-Content -LiteralPath $badVerificationPath -Raw -Encoding utf8) -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
    $schemaBareBoardBlocked = -not (Test-Json -Json (Get-Content -LiteralPath $bareBoardPath -Raw -Encoding utf8) -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
    $scriptBareBoardBlocked = Test-Throws { & $wrapper -Action ValidateCase -ConfigPath $canonicalConfig -CasePath $bareBoardPath }
    Add-Result 'SCHEMA_SCRIPT_CONSISTENCY' ($schemaValid -and $schemaFakeBlocked -and $schemaBadDiagnosticBlocked -and $schemaBadVerificationBlocked -and $schemaBareBoardBlocked -and $scriptBareBoardBlocked)

    $configObject.top_n = 3
    [IO.File]::WriteAllText($canonicalConfig, ($configObject | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $configTopN = & $wrapper -Action Query -ConfigPath $canonicalConfig -ProjectRoot $project -Mode AFTERSALES_TRIAGE -Query 'synthetic'
    $cliTopN = & $wrapper -Action Query -ConfigPath $canonicalConfig -ProjectRoot $project -Mode AFTERSALES_TRIAGE -TopN 4 -Query 'synthetic'
    Add-Result 'CONFIG_TOPN_PRECEDENCE' ($configTopN.match_count -eq 3 -and $cliTopN.match_count -eq 4)

    $invalidConfigResults = @()
    foreach ($invalid in @(
        [ordered]@{schema_version='1.1.0';enabled='false';private_library_root=$library;default_mode='AFTERSALES_TRIAGE';allow_after_sales_triage=$true;top_n=5;copy_source_documents=$false},
        [ordered]@{schema_version='9.9.9';enabled=$true;private_library_root=$library;default_mode='AFTERSALES_TRIAGE';allow_after_sales_triage=$true;top_n=5;copy_source_documents=$false},
        [ordered]@{schema_version='1.1.0';enabled=$true;private_library_root=$library;default_mode='AFTERSALES_TRIAGE';allow_after_sales_triage=$true;top_n=2;copy_source_documents=$false},
        [ordered]@{schema_version='1.1.0';enabled=$true;private_library_root=$library;default_mode='AFTERSALES_TRIAGE';allow_after_sales_triage='false';top_n=5;copy_source_documents=$false}
    )) {
        $invalidPath = Join-Path $tempRoot ('invalid-config-' + $invalidConfigResults.Count + '.json')
        [IO.File]::WriteAllText($invalidPath, ($invalid | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        $invalidConfigResults += & $wrapper -Action Query -ConfigPath $invalidPath -ProjectRoot $project -Query 'fifo'
    }
    Add-Result 'CONFIG_INVALID_FAIL_CLOSED' (@($invalidConfigResults | Where-Object { $_.status -ne 'CONFIG_INVALID' -or $_.library_files_scanned -ne 0 }).Count -eq 0)

    $missingConfigResult = & $wrapper -Action Query -ConfigPath (Join-Path $tempRoot 'missing-config.json') -ProjectRoot $project -Query 'fifo'
    $unavailableConfig = [ordered]@{schema_version='1.1.0';enabled=$true;private_library_root=(Join-Path $tempRoot 'missing-library');default_mode='FORMAL_REUSE';allow_after_sales_triage=$false;top_n=5;query_output_relative='codex_out/<run-id>/knowledge/matches.json';copy_source_documents=$false}
    $unavailablePath = Join-Path $tempRoot 'unavailable-config.json'
    [IO.File]::WriteAllText($unavailablePath, ($unavailableConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $unavailableResult = & $wrapper -Action Query -ConfigPath $unavailablePath -ProjectRoot $project -Query 'fifo'
    Add-Result 'CONFIG_MISSING_UNAVAILABLE' ($missingConfigResult.status -eq 'CONFIG_MISSING' -and $missingConfigResult.library_files_scanned -eq 0 -and $unavailableResult.status -eq 'CONFIG_UNAVAILABLE' -and $unavailableResult.library_files_scanned -eq 0)

    $actualIds = @($results.id | Sort-Object)
    $expectedSorted = @($expectedIds | Sort-Object)
    if (($actualIds -join ',') -ne ($expectedSorted -join ',')) { throw 'canary coverage does not match canaries.json' }
    $failed = @($results | Where-Object { -not $_.passed })
    if ($failed.Count) { $failed | Format-Table -AutoSize | Out-String | Write-Host; throw "fault-library canary failed: $($failed.id -join ', ')" }
    [pscustomobject]@{ status='ASSERTIONS_SATISFIED'; test_count=$results.Count; passed=$results.Count; failed=0 }
}
finally {
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('codex-fpga-fault-canary-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
