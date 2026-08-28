[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$toolchainPath = Join-Path $root 'project\script\toolchain.local.psd1'
if (-not (Test-Path -LiteralPath $toolchainPath -PathType Leaf)) {
    throw 'TOOL_ENV_FAIL: toolchain.local.psd1 is missing.'
}
$cfg = Import-PowerShellDataFile -LiteralPath $toolchainPath
$required = @($cfg.RequiredSimulationLibraries)
if ($required.Count -eq 0) {
    $result = [pscustomobject]@{ schema_version = '0.3'; status = 'NO_VENDOR_LIBRARIES_REQUIRED'; libraries = @() }
    if ($AsJson) { $result | ConvertTo-Json -Depth 4 } else { $result }
    exit 0
}

$cacheRoot = Join-Path $root ('codex_out\_cache\simlibs\{0}\{1}\{2}\{3}\{4}' -f
    $cfg.Vendor, $cfg.ToolVersion, $cfg.Family, $cfg.SimulatorVersion, $cfg.OfficialLibrarySourceHash)
$expanded = @{}
foreach ($name in $required) {
    $configured = $cfg.SimulationLibraryPaths[$name]
    if ($configured) { $expanded[$name] = $configured.Replace('{CACHE_ROOT}', $cacheRoot) }
}
$missing = @($required | Where-Object { -not $expanded.ContainsKey($_) -or -not (Test-Path -LiteralPath $expanded[$_] -PathType Container) })

if ($missing.Count -gt 0) {
    $recipe = $cfg.OfficialLibraryRecipe
    $source = $cfg.OfficialLibrarySource
    if (-not $cfg.RecipeValidated -or -not $recipe -or -not $source -or
        -not (Test-Path -LiteralPath $recipe -PathType Leaf) -or
        -not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "MISSING_VENDOR_LIBRARY: $($missing -join ', '). Exact official source and a previously validated recipe are required."
    }
    [IO.Directory]::CreateDirectory($cacheRoot) | Out-Null
    & $recipe -OfficialSource $source -Destination $cacheRoot -Vendor $cfg.Vendor -ToolVersion $cfg.ToolVersion -Family $cfg.Family -SimulatorVersion $cfg.SimulatorVersion
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "VENDOR_LIBRARY_FAIL: official recipe returned exit code $LASTEXITCODE."
    }
    $missing = @($required | Where-Object { -not $expanded.ContainsKey($_) -or -not (Test-Path -LiteralPath $expanded[$_] -PathType Container) })
    if ($missing.Count -gt 0) {
        throw "VENDOR_LIBRARY_FAIL: recipe completed but libraries remain missing: $($missing -join ', ')."
    }
}

$result = [pscustomobject]@{
    schema_version = '0.3'
    status = 'VENDOR_LIBRARIES_READY'
    cache_root = $cacheRoot
    libraries = @($required | ForEach-Object { [pscustomobject]@{ name = $_; path = $expanded[$_] } })
}
if ($AsJson) { $result | ConvertTo-Json -Depth 6 } else { $result }
