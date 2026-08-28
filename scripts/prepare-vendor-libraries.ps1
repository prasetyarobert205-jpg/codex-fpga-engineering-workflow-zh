[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][ValidateSet('XILINX', 'PANGO', 'ANLOGIC')][string]$Vendor,
    [Parameter(Mandatory)][string]$JobRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$settings = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'project\script\setting.psd1')
$localPath = Join-Path $root 'project\script\toolchain.local.psd1'
$local = if (Test-Path -LiteralPath $localPath -PathType Leaf) { Import-PowerShellDataFile -LiteralPath $localPath } else { @{} }
$required = @(if ($settings.ContainsKey('RequiredSimulationLibraries')) { @($settings.RequiredSimulationLibraries) } else { @() })
$mapped = if ($local.ContainsKey('SimulationLibraries')) { $local.SimulationLibraries } else { @{} }
$recipes = if ($local.ContainsKey('LibraryRecipes')) { $local.LibraryRecipes } else { @{} }
$prepared = [Collections.Generic.List[object]]::new()
$missing = [Collections.Generic.List[string]]::new()

function Test-SuccessCache([string]$Cache, [string]$LibraryName, [string]$SourceHash, [hashtable]$Recipe) {
    $markerPath = Join-Path $Cache 'recipe-result.json'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { return $false }
    try { $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
    if ($marker.exit_code -ne 0 -or $marker.name -ne $LibraryName -or $marker.vendor -ne $Vendor -or
        $marker.tool_version -ne $settings.ToolVersion -or $marker.device -ne $settings.Device -or
        $marker.simulator_version -ne $local.SimulatorVersion -or $marker.source_hash -ne $SourceHash) { return $false }
    foreach ($relative in @($Recipe.ExpectedOutputs)) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $Cache ([string]$relative)))
        $cachePrefix = $Cache.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $candidate.StartsWith($cachePrefix, [StringComparison]::OrdinalIgnoreCase) -or
            (-not (Test-Path -LiteralPath $candidate))) { return $false }
    }
    return $true
}

foreach ($name in $required) {
    $libraryName = [string]$name
    if ($mapped.ContainsKey($libraryName) -and (Test-Path -LiteralPath ([string]$mapped[$libraryName]) -PathType Container)) {
        $prepared.Add([ordered]@{ name = $libraryName; path = [IO.Path]::GetFullPath([string]$mapped[$libraryName]); source = 'configured-map' })
        continue
    }
    if (-not $recipes.ContainsKey($libraryName)) { $missing.Add($libraryName); continue }
    $recipe = $recipes[$libraryName]
    foreach ($field in @('Vendor','ToolVersion','Device','SimulatorVersion','OfficialSourceRoot','Command','Arguments','ExpectedOutputs')) {
        if (-not $recipe.ContainsKey($field) -or @($recipe[$field]).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]@($recipe[$field])[0])) {
            throw "Library recipe '$libraryName' is missing $field."
        }
    }
    if ($recipe.Vendor -ne $Vendor -or $recipe.ToolVersion -ne $settings.ToolVersion -or $recipe.Device -ne $settings.Device -or $recipe.SimulatorVersion -ne $local.SimulatorVersion) {
        throw "Library recipe '$libraryName' does not exactly match vendor/tool/device/simulator configuration."
    }
    $sourceRoot = [IO.Path]::GetFullPath([string]$recipe.OfficialSourceRoot)
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw "Official library source is unavailable: $sourceRoot" }
    $hashInput = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        ([IO.Path]::GetRelativePath($sourceRoot, $_.FullName) -replace '\\','/') + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    if ($hashInput.Count -eq 0) { throw "Official library source is empty: $sourceRoot" }
    $sourceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($hashInput -join "`n")))).ToLowerInvariant()
    $safeSegments = @($Vendor, $settings.ToolVersion, $settings.Device, $local.SimulatorVersion, $sourceHash) | ForEach-Object { ([string]$_ -replace '[^A-Za-z0-9_.-]', '_') }
    $cache = Join-Path $root ('codex_out\_cache\simlibs\' + ($safeSegments -join '\') + "\$libraryName")
    $cacheParent = Split-Path -Parent $cache
    New-Item -ItemType Directory -Path $cacheParent -Force | Out-Null

    if (-not (Test-SuccessCache -Cache $cache -LibraryName $libraryName -SourceHash $sourceHash -Recipe $recipe)) {
        if (Test-Path -LiteralPath $cache) {
            $invalid = "$cache.invalid-$([Guid]::NewGuid().ToString('N'))"
            Move-Item -LiteralPath $cache -Destination $invalid
        }
        $staging = "$cache.staging-$([Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        $arguments = @($recipe.Arguments | ForEach-Object { ([string]$_).Replace('{sourceRoot}', $sourceRoot).Replace('{outputRoot}', $staging).Replace('{library}', $libraryName) })
        & $recipe.Command @arguments 2>&1 | Tee-Object -FilePath (Join-Path $staging 'compile.log')
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            [IO.File]::WriteAllText((Join-Path $staging 'failure.json'), (([ordered]@{ name = $libraryName; exit_code = $code; status = 'FAILED' } | ConvertTo-Json) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
            throw "Official library recipe failed for $libraryName with exit code $code. The failed staging directory was not promoted."
        }
        foreach ($relative in @($recipe.ExpectedOutputs)) {
            $candidate = [IO.Path]::GetFullPath((Join-Path $staging ([string]$relative)))
            $stagingPrefix = $staging.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (-not $candidate.StartsWith($stagingPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate)) {
                throw "Library recipe '$libraryName' completed but expected output is missing: $relative. The staging directory was not promoted."
            }
        }
        $record = [ordered]@{ name = $libraryName; vendor = $Vendor; tool_version = $settings.ToolVersion; device = $settings.Device; simulator_version = $local.SimulatorVersion; source_hash = $sourceHash; expected_outputs = @($recipe.ExpectedOutputs); exit_code = 0 }
        [IO.File]::WriteAllText((Join-Path $staging 'recipe-result.json'), (($record | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $staging -Destination $cache
    }
    if (-not (Test-SuccessCache -Cache $cache -LibraryName $libraryName -SourceHash $sourceHash -Recipe $recipe)) {
        throw "Library cache validation failed after preparation: $libraryName"
    }
    $prepared.Add([ordered]@{ name = $libraryName; path = $cache; source = 'validated-recipe'; source_hash = $sourceHash })
}

$result = [ordered]@{
    schema_version = '1.0.0'
    status = if ($missing.Count -gt 0) { 'MISSING_VENDOR_LIBRARY' } elseif ($required.Count -eq 0) { 'NOT_REQUIRED' } else { 'PASS' }
    vendor = $Vendor
    libraries = @($prepared)
    missing = @($missing)
    preparation_checklist = @(
        'Use only official simulation sources matching the exact vendor tool and device family.',
        'Add an exact local recipe only after its command, expected outputs, and simulator compatibility are independently verified.',
        'Never substitute a nearby version or fabricate a primitive model.'
    )
}
[IO.File]::WriteAllText((Join-Path $JobRoot 'prepared-libraries.json'), (($result | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
[pscustomobject]$result
