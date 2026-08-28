function Invoke-ConfiguredAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExpectedVendor,
        [Parameter(Mandatory)][ValidateSet('compile', 'build', 'clean', 'simulate', 'lint')][string]$Action,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$Case,
        [string]$Mode,
        [string]$Seed,
        [ValidateSet('all', 'verilator', 'svlint')]
        [string]$LintTool = 'all'
    )

    $cfgPath = Join-Path $ProjectRoot 'project\script\toolchain.local.psd1'
    $cfg = Import-PowerShellDataFile -LiteralPath $cfgPath
    if ($cfg.Vendor.ToString().ToUpperInvariant() -ne $ExpectedVendor) {
        throw "TARGET_CONFLICT: selected adapter $ExpectedVendor does not match toolchain vendor '$($cfg.Vendor)'."
    }
    $prefix = switch ($Action) {
        'simulate' { 'Simulation' }
        'lint' {
            switch ($LintTool) {
                'verilator' { 'Verilator' }
                'svlint' { 'SvLint' }
                default { 'Lint' }
            }
        }
        default { (Get-Culture).TextInfo.ToTitleCase($Action) }
    }
    $executable = $cfg[$prefix + 'Executable']
    $arguments = @($cfg[$prefix + 'Arguments'])
    if (-not $executable) { throw "TOOL_ENV_FAIL: $prefix executable is not configured." }

    $settings = Import-PowerShellDataFile -LiteralPath (Join-Path $ProjectRoot 'project\script\setting.psd1')
    $detected = & (Join-Path $PSScriptRoot 'detect-vendor.ps1') -ProjectRoot $ProjectRoot
    $tokens = [ordered]@{
        '{PROJECT_ROOT}' = $ProjectRoot
        '{PROJECT_FILE}' = if ($settings.VendorProjectFile) { Join-Path $ProjectRoot $settings.VendorProjectFile } elseif ($detected.authoritative_project) { Join-Path $ProjectRoot $detected.authoritative_project } else { '' }
        '{TOP}' = $settings.TopModule
        '{CASE}' = $Case
        '{MODE}' = $Mode
        '{SEED}' = $Seed
        '{SOURCE_LIST}' = Join-Path $ProjectRoot 'project\script\src_list.txt'
        '{SIM_SOURCE_LIST}' = Join-Path $ProjectRoot 'simulation\script\src_list.txt'
        '{LINT_LIST}' = Join-Path $ProjectRoot 'linter\script\lint_list.txt'
        '{LINT_TOOL}' = $LintTool
        '{OUTPUT_DIR}' = $OutputDir
    }
    $resolvedArgs = @($arguments | ForEach-Object {
        $value = $_.ToString()
        foreach ($token in $tokens.GetEnumerator()) { $value = $value.Replace($token.Key, [string]$token.Value) }
        $value
    })

    [IO.Directory]::CreateDirectory($OutputDir) | Out-Null
    $stdout = Join-Path $OutputDir 'stdout.log'
    $stderr = Join-Path $OutputDir 'stderr.log'
    $command = @($executable) + $resolvedArgs
    [IO.File]::WriteAllLines((Join-Path $OutputDir 'command.txt'), $command, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $OutputDir 'tool-version.txt'), "$($cfg.ToolName) $($cfg.ToolVersion)", [Text.UTF8Encoding]::new($false))

    # Use the job directory so vendor scratch, local mappings, and transient databases
    # do not leak into the project root. Recipes receive absolute project/source tokens.
    $process = Start-Process -FilePath $executable -ArgumentList $resolvedArgs -WorkingDirectory $OutputDir -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    [pscustomobject]@{
        schema_version = '0.3'
        status = if ($process.ExitCode -eq 0) { 'COMMAND_COMPLETED' } else { 'COMMAND_FAILED' }
        classification = if ($process.ExitCode -eq 0) { 'UNVERIFIED_REQUIRES_REPORT_REVIEW' } else { if ($Action -eq 'simulate') { 'INCONCLUSIVE' } else { 'BUILD_SCRIPT_FAIL' } }
        vendor = $ExpectedVendor
        action = $Action
        case = if ($Action -eq 'simulate') { $Case } else { $null }
        lint_tool = if ($Action -eq 'lint') { $LintTool } else { $null }
        exit_code = $process.ExitCode
        output_dir = $OutputDir
    }
}
