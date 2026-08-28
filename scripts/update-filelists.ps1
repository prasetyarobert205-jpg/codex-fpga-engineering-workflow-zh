[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [ValidateSet('XILINX', 'PANGO', 'ANLOGIC')][string]$Vendor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$excluded = @('codex_out', 'release', 'old', 'backup', '.git', '.runs', '.cache', 'work', 'logs', 'waves', 'generated')

function Test-Excluded([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $relative = [IO.Path]::GetRelativePath($root, $full) -replace '\\', '/'
    return [bool]($relative.Split('/', [StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_ -in $excluded -or $_.EndsWith('.runs', [StringComparison]::OrdinalIgnoreCase) -or $_.EndsWith('.cache', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
}
function Get-Relative([string]$Path) { ([IO.Path]::GetRelativePath($root, $Path) -replace '\\', '/') }
function Get-ListRelative([string]$Base, [string]$Path) { ([IO.Path]::GetRelativePath($Base, $Path) -replace '\\', '/') }
function Get-Files([string[]]$Roots, [string[]]$Extensions) {
    $files = foreach ($base in $Roots) {
        if (Test-Path -LiteralPath $base -PathType Container) {
            Get-ChildItem -LiteralPath $base -File -Recurse | Where-Object {
                -not (Test-Excluded $_.FullName) -and $_.Extension.ToLowerInvariant() -in $Extensions
            }
        }
    }
    return @($files | Sort-Object { Get-Relative $_.FullName })
}
function Test-DependencySensitive([IO.FileInfo[]]$Files) {
    if ($Files.Count -le 1) { return $false }
    if (@($Files | Where-Object { $_.Extension.ToLowerInvariant() -in @('.vhd','.vhdl') }).Count -gt 1) { return $true }
    foreach ($file in $Files) {
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($text -match '(?im)^\s*(package|interface)\b|\bimport\s+[A-Za-z_][A-Za-z0-9_]*::') { return $true }
    }
    return $false
}
function Resolve-CompileOrder([IO.FileInfo[]]$Files, [string]$OrderPath, [string]$Label) {
    if ($Files.Count -eq 0) { return @() }
    $declared = @(if (Test-Path -LiteralPath $OrderPath -PathType Leaf) {
        @(Get-Content -LiteralPath $OrderPath -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    } else { @() })
    $actualMap = @{}
    foreach ($file in $Files) { $actualMap[(Get-Relative $file.FullName).ToLowerInvariant()] = $file }
    if ($declared.Count -gt 0) {
        $ordered = [Collections.Generic.List[IO.FileInfo]]::new()
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($relative in $declared) {
            $key = ($relative -replace '\\','/').ToLowerInvariant()
            if (-not $actualMap.ContainsKey($key)) { throw "$Label compile order references a missing or out-of-scope file: $relative" }
            if (-not $seen.Add($key)) { throw "$Label compile order contains a duplicate: $relative" }
            $ordered.Add($actualMap[$key])
        }
        $missing = @($actualMap.Keys | Where-Object { -not $seen.Contains($_) })
        if ($missing.Count -gt 0) { throw "$Label compile order omits: $($missing -join ', ')" }
        return @($ordered)
    }
    if (Test-DependencySensitive -Files $Files) {
        throw "$Label dependency order is not safe to infer. Export the authoritative vendor/project order to $([IO.Path]::GetRelativePath($root, $OrderPath) -replace '\\','/')."
    }
    return @($Files | Sort-Object { Get-Relative $_.FullName })
}
function Assert-NoDuplicateUnits([IO.FileInfo[]]$Files) {
    $owners = @{}
    foreach ($file in $Files) {
        foreach ($unit in Get-DesignUnitNames -File $file) {
            if ($owners.ContainsKey($unit) -and $owners[$unit] -ne $file.FullName) { throw "Duplicate design unit '$unit': $(Get-Relative $owners[$unit]) and $(Get-Relative $file.FullName)" }
            $owners[$unit] = $file.FullName
        }
    }
}
function Get-DesignUnitNames([IO.FileInfo]$File) {
    $text = [IO.File]::ReadAllText($File.FullName)
    return @([regex]::Matches($text, '(?im)^\s*(?:module|interface|package|entity)\s+([A-Za-z_][A-Za-z0-9_$]*)') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
}
function Write-StableList([string]$Path, [string[]]$Lines) {
    $normalized = @($Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $content = if ($normalized.Count -gt 0) { ($normalized -join "`n") + "`n" } else { '' }
    $old = if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::ReadAllText($Path) -replace "`r`n", "`n" } else { $null }
    if ($old -eq $content) { return $false }
    if ($PSCmdlet.ShouldProcess($Path, 'Update deterministic file list')) {
        $parent = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $temporary = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
        [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    return $true
}

if ([string]::IsNullOrWhiteSpace($Vendor)) {
    $detection = & (Join-Path $PSScriptRoot 'detect-vendor.ps1') -ProjectRoot $root
    if ($detection.status -ne 'DETECTED') { throw $detection.message }
    $Vendor = $detection.vendor
}

$hdl = @('.v','.sv','.vhd','.vhdl')
$headers = @('.vh','.svh')
$ipExtension = switch ($Vendor) { 'XILINX' { '.xci' } 'PANGO' { '.idf' } 'ANLOGIC' { '.ipc' } }
$rtlRoot = Join-Path $root 'project\rtl'
$ipRoot = Join-Path $root 'project\ip'
$synthIpRoot = Join-Path $ipRoot 'synth'
$simIpRoot = Join-Path $ipRoot 'sim'
$tbRoot = Join-Path $root 'simulation\tb'

$ipConfigs = @(Get-Files -Roots @($ipRoot) -Extensions @($ipExtension))
$configStems = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($config in $ipConfigs) { [void]$configStems.Add([IO.Path]::GetFileNameWithoutExtension($config.Name)) }
$rootIpHdl = if (Test-Path -LiteralPath $ipRoot -PathType Container) { @(Get-ChildItem -LiteralPath $ipRoot -File | Where-Object { $_.Extension.ToLowerInvariant() -in $hdl }) } else { @() }
$rootSynth = [Collections.Generic.List[IO.FileInfo]]::new()
$rootModels = [Collections.Generic.List[IO.FileInfo]]::new()
$unclassified = [Collections.Generic.List[string]]::new()
foreach ($file in $rootIpHdl) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($stem.EndsWith('_sim', [StringComparison]::OrdinalIgnoreCase) -and $configStems.Contains($stem.Substring(0, $stem.Length - 4))) {
        $rootModels.Add($file)
    } elseif ($configStems.Contains($stem)) {
        $rootSynth.Add($file)
    } else {
        $unclassified.Add((Get-Relative $file.FullName))
    }
}
if ($unclassified.Count -gt 0) { throw "Root-level project/ip HDL must match a vendor IP config as <name>.* or <name>_sim.*; otherwise place it under synth/ or sim/: $($unclassified -join ', ')" }
$productRaw = @(Get-Files -Roots @($rtlRoot, $synthIpRoot) -Extensions $hdl) + @($rootSynth)
$modelsRaw = @(Get-Files -Roots @($simIpRoot) -Extensions $hdl) + @($rootModels)
$testbenchRaw = @(Get-Files -Roots @($tbRoot) -Extensions $hdl)
$product = @(Resolve-CompileOrder -Files $productRaw -OrderPath (Join-Path $root 'document\source-order.txt') -Label 'Product')
Assert-NoDuplicateUnits -Files $product
$modelUnits = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($model in $modelsRaw) { foreach ($unit in Get-DesignUnitNames -File $model) { [void]$modelUnits.Add($unit) } }
$simulationProduct = [Collections.Generic.List[IO.FileInfo]]::new()
foreach ($file in $product) {
    $units = @(Get-DesignUnitNames -File $file)
    $overlap = @($units | Where-Object { $modelUnits.Contains($_) })
    if ($overlap.Count -eq 0) { $simulationProduct.Add($file); continue }
    if ($overlap.Count -ne $units.Count) { throw "Simulation model partially replaces design units in $(Get-Relative $file.FullName); split the file or provide an explicit model boundary." }
}
$simulationRaw = @($simulationProduct + $modelsRaw + $testbenchRaw)
$simulation = @(Resolve-CompileOrder -Files $simulationRaw -OrderPath (Join-Path $root 'document\simulation-source-order.txt') -Label 'Simulation')
Assert-NoDuplicateUnits -Files $simulation

$projectHeaders = @(Get-Files -Roots @($rtlRoot, $synthIpRoot) -Extensions $headers)
$simulationHeaders = @(Get-Files -Roots @($rtlRoot, $synthIpRoot, $simIpRoot, $tbRoot) -Extensions $headers)
$projectIncludes = @($projectHeaders | ForEach-Object { Get-Relative $_.Directory.FullName } | Sort-Object -Unique)
$simulationIncludes = @($simulationHeaders | ForEach-Object { Get-Relative $_.Directory.FullName } | Sort-Object -Unique)
$projectListBase = Join-Path $root 'project\par'
$simulationListBase = Join-Path $root 'simulation\work'
$projectLines = @($projectIncludes | ForEach-Object { "+incdir+$(Get-ListRelative $projectListBase (Join-Path $root ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)))" }) + @($product | ForEach-Object { Get-ListRelative $projectListBase $_.FullName }) + @($ipConfigs | ForEach-Object { Get-ListRelative $projectListBase $_.FullName })
$simulationLines = @($simulationIncludes | ForEach-Object { "+incdir+$(Get-ListRelative $simulationListBase (Join-Path $root ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)))" }) + @($simulation | ForEach-Object { Get-ListRelative $simulationListBase $_.FullName })

$changes = [ordered]@{}
$changes.project_sources = Write-StableList (Join-Path $root 'project\script\src_list.txt') $projectLines
$changes.simulation_sources = Write-StableList (Join-Path $root 'simulation\script\src_list.txt') $simulationLines
$changes.lint_sources = Write-StableList (Join-Path $root 'linter\script\lint_list.txt') @($product | ForEach-Object { Get-Relative $_.FullName })

[pscustomobject]@{
    status = 'UPDATED'
    vendor = $Vendor
    product_source_count = $product.Count
    testbench_source_count = $testbenchRaw.Count
    simulation_model_count = $modelsRaw.Count
    vendor_ip_count = $ipConfigs.Count
    lint_source_count = $product.Count
    changed = $changes
}
