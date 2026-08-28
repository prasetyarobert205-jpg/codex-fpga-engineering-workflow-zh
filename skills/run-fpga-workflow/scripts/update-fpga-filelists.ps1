[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$detectScript = Join-Path $PSScriptRoot 'detect-fpga-vendor.ps1'
if (-not (Test-Path -LiteralPath $detectScript)) { $detectScript = Join-Path $PSScriptRoot 'detect-vendor.ps1' }
$vendorResult = & $detectScript -ProjectRoot $root

function Test-ExcludedPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $relative = [IO.Path]::GetRelativePath($root, $full)
    if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('..\') -or $relative.StartsWith('../')) {
        throw "PATH_ESCAPE: '$full' resolves outside project root '$root'."
    }
    $segments = ($relative -replace '/', '\').Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
    $excluded = @('codex_out', 'release', 'old', 'backup', 'generated', '.runs', '.cache', 'work', 'logs', 'waves')
    foreach ($segment in $segments) {
        if ($excluded -contains $segment.ToLowerInvariant()) { return $true }
    }
    return $false
}

function Get-Relative([string]$Path) {
    return [IO.Path]::GetRelativePath($root, $Path).Replace('\', '/')
}

function Get-Files([string[]]$Roots, [string[]]$Extensions) {
    return @($Roots | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | ForEach-Object {
        Get-ChildItem -LiteralPath $_ -Recurse -File -ErrorAction Stop
    } | Where-Object {
        ($Extensions -contains $_.Extension.ToLowerInvariant()) -and -not (Test-ExcludedPath $_.FullName)
    } | Sort-Object FullName -Unique)
}

function Get-TextPrefix([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    if ($text.Length -gt 65536) { return $text.Substring(0, 65536) }
    return $text
}

function Write-AtomicLines([string]$Path, [string[]]$Lines) {
    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $normalized = @($Lines | Where-Object { $_ -ne $null } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    $newText = if ($normalized.Count) { ($normalized -join [Environment]::NewLine) + [Environment]::NewLine } else { '' }
    $oldText = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { $null }
    if ($oldText -ceq $newText) { return $false }
    $temp = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
    [IO.File]::WriteAllText($temp, $newText, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $Path, $true)
    return $true
}

function Assert-NoDuplicateUnits([System.IO.FileInfo[]]$Files, [string]$View) {
    $definitions = @{}
    foreach ($file in $Files) {
        $text = Get-TextPrefix $file.FullName
        $matches = [regex]::Matches($text, '(?im)^\s*(?:module|interface|entity)\s+([A-Za-z_][A-Za-z0-9_$]*)')
        foreach ($match in $matches) {
            $name = $match.Groups[1].Value.ToLowerInvariant()
            $relative = Get-Relative $file.FullName
            if ($definitions.ContainsKey($name)) {
                $first = $definitions[$name]
                if ($first.StartsWith('project/ip/', [StringComparison]::OrdinalIgnoreCase) -and
                    $relative.StartsWith('project/ip/', [StringComparison]::OrdinalIgnoreCase)) {
                    throw "IP_MODEL_OVERRIDE_REQUIRED: design unit '$name' appears in '$first' and '$relative' in the $View view. Add project/script/ip-model-map.psd1 with an explicit synthesis-to-simulation mapping, for example @{'$first'='$relative'}."
                }
                throw "DUPLICATE_DESIGN_UNIT: '$name' appears in '$first' and '$relative' in the $View view."
            }
            $definitions[$name] = $relative
        }
    }
}

$rtlRoot = Join-Path $root 'project\rtl'
$ipRoot = Join-Path $root 'project\ip'
$tbRoot = Join-Path $root 'simulation\tb'
$hdlExt = @('.v', '.sv', '.vhd', '.vhdl')
$headerExt = @('.vh', '.svh')
$rtlHdl = @(Get-Files @($rtlRoot) $hdlExt)
$ipHdl = @(Get-Files @($ipRoot) $hdlExt)
$tbHdl = @(Get-Files @($tbRoot) $hdlExt)
$headers = @(Get-Files @($rtlRoot, $ipRoot, $tbRoot) $headerExt)

$ipExtension = switch ($vendorResult.vendor) {
    'XILINX' { '.xci' }
    'PANGO' { '.idf' }
    'ANLOGIC' { '.ipc' }
    default { throw "UNSUPPORTED_VENDOR: $($vendorResult.vendor)" }
}
$ipConfigs = @(Get-Files @($ipRoot) @($ipExtension))

$ipByPath = @{}
foreach ($file in $ipHdl) { $ipByPath[$file.FullName.ToLowerInvariant()] = $file }
$pairMap = @{}
$simulationModelPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$autoSimModels = @($ipHdl | Where-Object { $_.BaseName -match '(?i)_sim$' })
foreach ($simFile in $autoSimModels) {
    [void]$simulationModelPaths.Add($simFile.FullName)
    $baseName = $simFile.BaseName -replace '(?i)_sim$', ''
    $candidates = @($ipHdl | Where-Object {
        $_.DirectoryName.Equals($simFile.DirectoryName, [StringComparison]::OrdinalIgnoreCase) -and
        $_.BaseName.Equals($baseName, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($candidates.Count -eq 1) {
        $pairMap[$candidates[0].FullName.ToLowerInvariant()] = $simFile
    } elseif ($candidates.Count -gt 1) {
        throw "IP_MODEL_OVERRIDE_REQUIRED: '$((Get-Relative $simFile.FullName))' has multiple possible synthesis peers. Add project/script/ip-model-map.psd1 with one explicit mapping."
    }
}

$overridePath = Join-Path $root 'project\script\ip-model-map.psd1'
if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
    $overrides = Import-PowerShellDataFile -LiteralPath $overridePath
    foreach ($synthesisRelative in $overrides.Keys) {
        $simulationRelative = [string]$overrides[$synthesisRelative]
        $synthesisPath = [IO.Path]::GetFullPath((Join-Path $root ($synthesisRelative -replace '/', '\')))
        $simulationPath = [IO.Path]::GetFullPath((Join-Path $root ($simulationRelative -replace '/', '\')))
        if (-not $ipByPath.ContainsKey($synthesisPath.ToLowerInvariant()) -or -not $ipByPath.ContainsKey($simulationPath.ToLowerInvariant())) {
            throw "IP_MODEL_OVERRIDE_INVALID: '$synthesisRelative'='$simulationRelative' must reference two active HDL files under project/ip."
        }
        if ($synthesisPath.Equals($simulationPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "IP_MODEL_OVERRIDE_INVALID: synthesis and simulation paths must differ for '$synthesisRelative'."
        }
        $pairMap[$synthesisPath.ToLowerInvariant()] = $ipByPath[$simulationPath.ToLowerInvariant()]
        [void]$simulationModelPaths.Add($simulationPath)
    }
}

$buildIpHdl = @($ipHdl | Where-Object { -not $simulationModelPaths.Contains($_.FullName) })
$buildHdl = @($rtlHdl + $buildIpHdl)
Assert-NoDuplicateUnits $buildHdl 'build'

$orderedHdl = @()
$orderFile = Join-Path $root 'project\script\source-order.txt'
$explicitOrder = @()
if (Test-Path -LiteralPath $orderFile) {
    $explicitOrder = @(Get-Content -LiteralPath $orderFile -Encoding utf8 |
        ForEach-Object { ($_ -split '#', 2)[0].Trim() } |
        Where-Object { $_ })
}

if ($explicitOrder.Count -gt 0) {
    $map = @{}
    foreach ($file in $buildHdl) { $map[(Get-Relative $file.FullName).ToLowerInvariant()] = $file }
    foreach ($entry in $explicitOrder) {
        $key = $entry.Replace('\', '/').ToLowerInvariant()
        if (-not $map.ContainsKey($key)) { throw "SOURCE_ORDER_MISSING: '$entry' is not an active build HDL source." }
        $orderedHdl += $map[$key]
        $map.Remove($key)
    }
    if ($map.Count -gt 0) {
        throw "SOURCE_ORDER_INCOMPLETE: source-order.txt omits: $(@($map.Keys | Sort-Object) -join ', ')"
    }
} else {
    $vhdl = @($buildHdl | Where-Object { $_.Extension.ToLowerInvariant() -in @('.vhd', '.vhdl') })
    $packages = @($buildHdl | Where-Object { (Get-TextPrefix $_.FullName) -match '(?im)^\s*(package|interface)\s+[A-Za-z_]' })
    if ($vhdl.Count -gt 1 -or $packages.Count -gt 1) {
        throw 'SOURCE_ORDER_REQUIRED: multiple VHDL or package/interface units require explicit project/script/source-order.txt.'
    }
    $packagePaths = @($packages.FullName)
    $orderedHdl = @($packages | Sort-Object FullName) + @($buildHdl | Where-Object { $packagePaths -notcontains $_.FullName } | Sort-Object FullName)
}

$pairedSimulationPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$simulationProjectHdl = @()
foreach ($file in $orderedHdl) {
    $key = $file.FullName.ToLowerInvariant()
    if ($pairMap.ContainsKey($key)) {
        $simulationProjectHdl += $pairMap[$key]
        [void]$pairedSimulationPaths.Add($pairMap[$key].FullName)
    } else {
        $simulationProjectHdl += $file
    }
}
$simulationProjectHdl += @($ipHdl | Where-Object {
    $simulationModelPaths.Contains($_.FullName) -and -not $pairedSimulationPaths.Contains($_.FullName)
} | Sort-Object FullName)
$simulationHdl = @($simulationProjectHdl + $tbHdl)
Assert-NoDuplicateUnits $simulationHdl 'simulation'

$includeLines = @($headers | ForEach-Object { Get-Relative (Split-Path -Parent $_.FullName) } | Sort-Object -Unique | ForEach-Object { "+incdir+$_" })
$projectLines = @($includeLines + ($orderedHdl | ForEach-Object { Get-Relative $_.FullName }) + ($ipConfigs | ForEach-Object { Get-Relative $_.FullName }))
$simulationLines = @($includeLines + ($simulationProjectHdl | ForEach-Object { Get-Relative $_.FullName }) + ($tbHdl | ForEach-Object { Get-Relative $_.FullName }))
$lintLines = @($includeLines + ($orderedHdl | ForEach-Object { Get-Relative $_.FullName }))

$targets = [ordered]@{
    project = Join-Path $root 'project\script\src_list.txt'
    simulation = Join-Path $root 'simulation\script\src_list.txt'
    lint = Join-Path $root 'linter\script\lint_list.txt'
}
$changed = [ordered]@{}
$changed.project = Write-AtomicLines $targets.project $projectLines
$changed.simulation = Write-AtomicLines $targets.simulation $simulationLines
$changed.lint = Write-AtomicLines $targets.lint $lintLines

$result = [pscustomobject]@{
    schema_version = '0.3'
    vendor = $vendorResult.vendor
    authoritative_project = $vendorResult.authoritative_project
    project_sources = $projectLines.Count
    simulation_sources = $simulationLines.Count
    lint_sources = $lintLines.Count
    ip_model_pairs = $pairMap.Count
    changed = $changed
    outputs = [ordered]@{
        project = Get-Relative $targets.project
        simulation = Get-Relative $targets.simulation
        lint = Get-Relative $targets.lint
    }
}

if ($AsJson) { $result | ConvertTo-Json -Depth 6 } else { $result }
