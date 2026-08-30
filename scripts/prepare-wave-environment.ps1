[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Detect', 'Prepare')][string]$Mode = 'Detect',
    [string]$Distro = 'Ubuntu',
    [string]$WslPython = 'python3',
    [string]$ExistingWavePython,
    [string]$ToolRoot,
    [string]$Vcd2FstPath,
    [string]$Wheelhouse,
    [switch]$RunSmoke,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Complete-Result($Result) {
    $object = [pscustomobject]$Result
    if ($AsJson) { $object | ConvertTo-Json -Depth 8 } else { $object }
}

function Invoke-NativeProbe {
    param(
        [string]$FileName,
        [string[]]$Arguments,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 30
    )
    try {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $FileName
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $killRequested = $false
            try { $process.Kill($true); $killRequested = $true } catch { }
            if ($killRequested) { [void]$process.WaitForExit(5000) }
            $output = if ($process.HasExited) { @($stdoutTask.GetAwaiter().GetResult(), $stderrTask.GetAwaiter().GetResult()) -join "`n" } else { 'Process timed out and could not be confirmed terminated.' }
            $process.Dispose()
            return [pscustomobject]@{ ExitCode = 124; Output = @(($output -split '\r?\n') | Where-Object { $_ }); TimedOut = $true }
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        $process.Dispose()
        $output = @($stdout, $stderr) -join "`n"
        [pscustomobject]@{ ExitCode = $exitCode; Output = @(($output -split '\r?\n') | Where-Object { $_ }); TimedOut = $false }
    } catch {
        [pscustomobject]@{ ExitCode = 1; Output = @($_.Exception.Message); TimedOut = $false }
    }
}

function Assert-NoReparseInExistingPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $probe = $full
    while (-not (Test-Path -LiteralPath $probe)) {
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $probe) { throw "Cannot resolve ToolRoot ancestor: $full" }
        $probe = $parent
    }
    $cursor = Get-Item -LiteralPath $probe -Force
    while ($null -ne $cursor) {
        if ($cursor.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "ToolRoot traverses a reparse point: $($cursor.FullName)" }
        $cursor = if ($cursor -is [IO.FileInfo]) { $cursor.Directory } else { $cursor.Parent }
    }
}

function Remove-SafeSmokeTree([string]$Root) {
    $full = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not (Split-Path -Parent $full).Equals($temp, [StringComparison]::OrdinalIgnoreCase)) { throw "Smoke cleanup parent mismatch: $full" }
    if ((Split-Path -Leaf $full) -notmatch '^codex-fpga-wave-smoke-[0-9a-f]{32}$') { throw "Smoke cleanup basename mismatch: $full" }
    if (-not (Test-Path -LiteralPath $full)) { return }
    $rootItem = Get-Item -LiteralPath $full -Force
    if ($rootItem.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Smoke root became a reparse point; refusing recursive cleanup: $full" }
    $items = @(Get-ChildItem -LiteralPath $full -Force -Recurse)
    foreach ($item in @($items | Where-Object { $_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) })) {
        Remove-Item -LiteralPath $item.FullName -Force
    }
    foreach ($item in @($items | Where-Object { -not $_.PSIsContainer -and -not $_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) })) {
        if (Test-Path -LiteralPath $item.FullName) { Remove-Item -LiteralPath $item.FullName -Force }
    }
    foreach ($item in @($items | Where-Object { $_.PSIsContainer -and -not $_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) } | Sort-Object { $_.FullName.Length } -Descending)) {
        if (Test-Path -LiteralPath $item.FullName) {
            $current = Get-Item -LiteralPath $item.FullName -Force
            if ($current.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { Remove-Item -LiteralPath $current.FullName -Force }
            else { Remove-Item -LiteralPath $current.FullName -Force }
        }
    }
    $rootCurrent = Get-Item -LiteralPath $full -Force
    if ($rootCurrent.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Smoke root changed to a reparse point before final removal: $full" }
    Remove-Item -LiteralPath $full -Force
}

function Write-AtomicUtf8Json([string]$Path, [object]$Value) {
    $json = ($Value | ConvertTo-Json -Depth 10) + [Environment]::NewLine
    $null = $json | ConvertFrom-Json
    $directory = Split-Path -Parent $Path
    $tempPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    try {
        $stream = [IO.FileStream]::new($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($tempPath, $Path, $null) }
        else { [IO.File]::Move($tempPath, $Path) }
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

function Invoke-WslProbe {
    param(
        [System.Management.Automation.CommandInfo]$Wsl,
        [string[]]$Arguments,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 30
    )
    try {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $Wsl.Source
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $killRequested = $false
            try { $process.Kill($true); $killRequested = $true } catch { }
            if ($killRequested) { [void]$process.WaitForExit(5000) }
            $output = if ($process.HasExited) { @($stdoutTask.GetAwaiter().GetResult(), $stderrTask.GetAwaiter().GetResult()) -join "`n" } else { 'WSL process timed out and could not be confirmed terminated.' }
            $process.Dispose()
            return [pscustomobject]@{ ExitCode = 124; Output = @(($output -split '\r?\n') | Where-Object { $_ }); TimedOut = $true }
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        $process.Dispose()
        $output = @($stdout, $stderr) -join "`n"
        [pscustomobject]@{ ExitCode = $exitCode; Output = @(($output -split '\r?\n') | Where-Object { $_ }); TimedOut = $false }
    } catch {
        [pscustomobject]@{ ExitCode = 1; Output = @($_.Exception.Message); TimedOut = $false }
    }
}

function Get-WslTimedArguments {
    param([string]$DistroName, [int]$LinuxTimeoutSeconds, [string[]]$CommandArguments)
    $fullArguments = [Collections.Generic.List[string]]::new()
    foreach ($value in @('-d', $DistroName, '-e', 'timeout', '--signal=TERM', '--kill-after=5s', "$($LinuxTimeoutSeconds)s")) { $fullArguments.Add([string]$value) }
    foreach ($value in $CommandArguments) { $fullArguments.Add([string]$value) }
    return [string[]]$fullArguments.ToArray()
}

if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
    $localBase = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:LOCALAPPDATA } else { $env:USERPROFILE }
    $ToolRoot = Join-Path $localBase 'codex-fpga-tools\wave-mcp'
}
$toolRootFull = [IO.Path]::GetFullPath($ToolRoot)
$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$toolRootTrimmed = $toolRootFull.TrimEnd([IO.Path]::DirectorySeparatorChar)
$driveRootTrimmed = [IO.Path]::GetPathRoot($toolRootFull).TrimEnd([IO.Path]::DirectorySeparatorChar)
$packagePrefix = $packageRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($toolRootTrimmed.Equals($driveRootTrimmed, [StringComparison]::OrdinalIgnoreCase)) { throw 'ToolRoot 不能是磁盘根目录。' }
if ($toolRootFull.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase) -or $toolRootTrimmed.Equals($packageRoot.TrimEnd([IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'ToolRoot 必须位于插件/仓库根之外，避免提交 venv 或机器清单。' }
Assert-NoReparseInExistingPath -Path $toolRootFull
$requirements = Join-Path $packageRoot 'integrations\wave-mcp\requirements-tested.txt'

$result = [ordered]@{
    schema_version = 'fpga-wave-environment-setup-1.0'
    mode = $Mode
    status = 'DETECTING'
    distro = $Distro
    tool_root = $toolRootFull
    wsl = 'UNKNOWN'
    wsl_kernel = $null
    python = 'UNKNOWN'
    python_command = $WslPython
    wave_mcp = 'NOT_CHECKED'
    converter = 'NOT_CONFIGURED'
    global_path_modified = $false
    global_library_mapping_modified = $false
    next_action = $null
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($null -eq $wsl) {
    $result.status = 'PARTIAL_WSL_REQUIRED'
    $result.wsl = 'NOT_AVAILABLE'
    $result.next_action = "取得用户明确授权后运行：wsl --install -d $Distro；完成可能的重启后重新运行 bootstrap。"
    Complete-Result $result
    return
}

$kernelProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @('uname', '-r')) -TimeoutSeconds 30
if ($kernelProbe.ExitCode -ne 0) {
    $kernelDetail = $kernelProbe.Output -join ' '
    $kernelDetailNormalized = $kernelDetail -replace "`0", '' -replace '[\x01-\x1F]', ''
    if ($kernelDetailNormalized -match '(?i)E_ACCESSDENIED|access is denied|拒绝访问') {
        $result.status = 'TOOL_ENV_ACCESS_DENIED'
        $result.wsl = 'ACCESS_DENIED'
        $result.next_action = '当前 Codex/sandbox 无权启动 WSL；调整当前会话权限后重试，不要因此重装发行版。'
    } else {
        $result.status = 'PARTIAL_WSL_DISTRO_REQUIRED'
        $result.wsl = 'DISTRO_NOT_READY'
        $result.next_action = "取得用户明确授权后安装或修复 WSL 发行版 $Distro，然后重新运行 bootstrap。"
    }
    $result.detail = $kernelProbe.Output
    Complete-Result $result
    return
}
$result.wsl = 'READY'
$kernelLines = @($kernelProbe.Output | Where-Object { $_ -and $_ -notmatch '^wsl:' })
$result.wsl_kernel = if ($kernelLines.Count) { $kernelLines[0].Trim() } else { 'UNKNOWN' }
if ($result.wsl_kernel -notmatch '(?i)WSL2') {
    $result.status = 'PARTIAL_WSL2_REQUIRED'
    $result.wsl = 'WSL2_NOT_CONFIRMED'
    $result.next_action = '当前 kernel 未证明为 WSL2；确认发行版版本并升级到 WSL2 后重试。'
    Complete-Result $result
    return
}

$pythonProbeCommand = if (-not [string]::IsNullOrWhiteSpace($ExistingWavePython)) { $ExistingWavePython } else { $WslPython }
$pythonProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @($pythonProbeCommand, '--version')) -TimeoutSeconds 30
if ($pythonProbe.ExitCode -ne 0) {
    $result.status = 'PARTIAL_PYTHON_REQUIRED'
    $result.python = 'NOT_AVAILABLE'
    $result.next_action = "在 $Distro 中安装项目确认的 Python 3 和 venv 支持，或用 -ExistingWavePython 指向已有环境；本脚本不执行 sudo/apt。"
    Complete-Result $result
    return
}
$pythonLines = @($pythonProbe.Output | Where-Object { $_ -and $_ -notmatch '^wsl:' })
$result.python = if ($pythonLines.Count) { $pythonLines[0].Trim() } else { 'UNKNOWN' }

if ($Mode -eq 'Detect') {
    $manifestPath = Join-Path $toolRootFull 'environment.local.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            Assert-NoReparseInExistingPath -Path $manifestPath
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not [IO.Path]::GetFullPath([string]$manifest.tool_root).TrimEnd([IO.Path]::DirectorySeparatorChar).Equals($toolRootTrimmed, [StringComparison]::OrdinalIgnoreCase)) { throw 'local manifest tool_root 与当前请求不一致。' }
            if ([string]$manifest.distro -ne $Distro) { throw 'local manifest distro 与当前请求不一致。' }
            if ([string]::IsNullOrWhiteSpace([string]$manifest.python_wsl)) { throw 'local manifest 缺少 python_wsl。' }
            if (-not [string]::IsNullOrWhiteSpace($ExistingWavePython) -and [string]$manifest.python_wsl -ne $ExistingWavePython) { throw 'ExistingWavePython 与 local manifest python_wsl 不一致。' }
            $liveVersionScript = "import importlib.metadata as m,json; print(json.dumps({'wave-mcp':m.version('wave-mcp'),'mcp':m.version('mcp'),'pylibfst':m.version('pylibfst'),'pyslang':m.version('pyslang')}))"
            $liveProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @([string]$manifest.python_wsl, '-c', $liveVersionScript)) -TimeoutSeconds 30
            if ($liveProbe.ExitCode -ne 0) { throw "本地 wave Python 无法执行版本探针：$($liveProbe.Output -join ' ')" }
            $live = (($liveProbe.Output -join "`n").Trim() | ConvertFrom-Json)
            $expected = [ordered]@{ 'wave-mcp' = '0.1.1'; mcp = '2.1.1'; pylibfst = '0.2.1'; pyslang = '11.0.0' }
            $mismatch = @($expected.GetEnumerator() | Where-Object { [string]$live.($_.Key) -ne [string]$_.Value })
            if ($mismatch.Count) { throw "本地 wave Python 版本不匹配：$(@($mismatch | ForEach-Object { "$($_.Key)=$($live.($_.Key))" }) -join ', ')" }
            $liveImportScript = "import wave_mcp.server,mcp,pylibfst,pyslang; print('IMPORT_OK')"
            $liveImportProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @([string]$manifest.python_wsl, '-c', $liveImportScript)) -TimeoutSeconds 30
            if ($liveImportProbe.ExitCode -ne 0 -or ($liveImportProbe.Output -join "`n") -notmatch 'IMPORT_OK') { throw '本地 wave Python/native import probe 失败。' }
            $livePythonProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @([string]$manifest.python_wsl, '--version')) -TimeoutSeconds 30
            if ($livePythonProbe.ExitCode -ne 0) { throw '本地 wave Python 版本命令失败。' }
            $livePythonLines = @($livePythonProbe.Output | Where-Object { $_ -and $_ -notmatch '^wsl:' })
            $result.python = if ($livePythonLines.Count) { $livePythonLines[0].Trim() } else { 'UNKNOWN' }
            $result.python_command = [string]$manifest.python_wsl
            $result.wave_mcp = 'READY_0.1.1_LIVE'
            $result.converter = if ($manifest.converter.status) { [string]$manifest.converter.status } else { 'NOT_CONFIGURED' }
            if ($result.converter -ne 'NOT_CONFIGURED') {
                $converterPath = [string]$manifest.converter.path
                if (-not (Test-Path -LiteralPath $converterPath -PathType Leaf)) { throw '本地 converter 文件不存在。' }
                $converterHash = (Get-FileHash -LiteralPath $converterPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($converterHash -ne [string]$manifest.converter.sha256) { throw '本地 converter SHA-256 与 manifest 不匹配。' }
            }
            $result.status = if ($result.converter -eq 'VALIDATED_SYNTHETIC_SMOKE' -and $manifest.smoke.status -eq 'PASS') { 'READY_WITH_VCD_CONVERTER' } else { 'PACKAGES_READY_FST_QUERY_NOT_RUN' }
            $result.next_action = if ($result.status -eq 'READY_WITH_VCD_CONVERTER') { '本地 Python 版本和 converter hash 现场核对通过；真实工程仍需项目级证据。' } else { '本地 Python 版本现场核对通过；转换器未达到已验证 smoke 状态。' }
        } catch {
            $result.status = 'LOCAL_ENV_UNAVAILABLE'
            $result.wave_mcp = 'UNKNOWN'
            $result.detail = $_.Exception.Message
            $result.next_action = '审查本地 manifest、Python 和 converter；Detect 不会自动修复或覆盖。'
        }
    } else {
        $result.status = 'READY_TO_PREPARE'
        $result.wave_mcp = 'NOT_INSTALLED_BY_THIS_PACKAGE'
        $result.next_action = '运行 -Mode Prepare 创建独立 venv；不会修改全局 PATH。'
    }
    Complete-Result $result
    return
}

if (-not (Test-Path -LiteralPath $requirements -PathType Leaf)) { throw "缺少锁定依赖文件：$requirements" }
if ($WhatIfPreference) {
    $result.status = 'PLAN_NO_CHANGES'
    $result.wave_mcp = 'WOULD_CREATE_OR_REFRESH_VENV'
    $result.next_action = '去掉 -WhatIf 后才会创建工具目录、venv 和本地环境清单。'
    Complete-Result $result
    return
}

if (-not $PSCmdlet.ShouldProcess($toolRootFull, '创建独立 wave-mcp Python 环境')) {
    $result.status = 'CANCELLED'
    Complete-Result $result
    return
}

$mutexHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($toolRootFull.ToLowerInvariant()))).Substring(0, 24)
$mutex = [Threading.Mutex]::new($false, "Local\CodexFpgaWave-$mutexHash")
if (-not $mutex.WaitOne(0)) {
    $mutex.Dispose()
    $result.status = 'INSTALL_ALREADY_RUNNING'
    $result.wave_mcp = 'NOT_CHANGED'
    $result.next_action = '同一工具根已有安装进程；等待其结束，不要并发重试。确认没有进程后再处理残留状态。'
    Complete-Result $result
    return
}

try {
    New-Item -ItemType Directory -Path $toolRootFull -Force | Out-Null
    $rootDrive = [IO.Path]::GetPathRoot($toolRootFull).TrimEnd('\')
    $drive = Get-PSDrive -Name $rootDrive.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($null -ne $drive) { $result.free_bytes_before = [int64]$drive.Free }

$toolPathProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @('wslpath', '-a', '-u', $toolRootFull)) -TimeoutSeconds 30
$requirementsProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @('wslpath', '-a', '-u', $requirements)) -TimeoutSeconds 30
if ($toolPathProbe.ExitCode -ne 0 -or $requirementsProbe.ExitCode -ne 0) {
    throw '无法把 Windows 工具路径转换为 WSL 路径。'
}
$wslToolRoot = ($toolPathProbe.Output -join "`n").Trim()
$wslRequirements = ($requirementsProbe.Output -join "`n").Trim()
$wslVenv = "$wslToolRoot/venv-wave-mcp"
$venvPythonWsl = "$wslVenv/bin/python"
$environmentSource = 'CREATED_VENV'
if (-not [string]::IsNullOrWhiteSpace($ExistingWavePython)) {
    $venvPythonWsl = $ExistingWavePython
    $environmentSource = 'REUSED_EXISTING_VENV'
} else {
    $venv = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 110 -CommandArguments @($WslPython, '-m', 'venv', $wslVenv)) -TimeoutSeconds 120
    if ($venv.ExitCode -ne 0) {
        $result.status = if ($venv.TimedOut -or $venv.ExitCode -eq 124) { 'TOOL_ENV_TIMEOUT' } else { 'PARTIAL_PYTHON_VENV_REQUIRED' }
        $result.wave_mcp = 'NOT_INSTALLED'
        $result.next_action = '当前 Python 缺少 venv 支持或工具目录不可写；审查 WSL 输出后修复，或提供 -ExistingWavePython。'
        $result.detail = $venv.Output
        Complete-Result $result
        return
    }

    $pipCommand = @($venvPythonWsl, '-m', 'pip', 'install', '--disable-pip-version-check')
    if (-not [string]::IsNullOrWhiteSpace($Wheelhouse)) {
        $wheelhouseFull = [IO.Path]::GetFullPath($Wheelhouse)
        if (-not (Test-Path -LiteralPath $wheelhouseFull -PathType Container)) { throw "Wheelhouse 不存在：$wheelhouseFull" }
        Assert-NoReparseInExistingPath -Path $wheelhouseFull
        $wheelhouseProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @('wslpath', '-a', '-u', $wheelhouseFull)) -TimeoutSeconds 30
        if ($wheelhouseProbe.ExitCode -ne 0) { throw '无法把 Wheelhouse 转换为 WSL 路径。' }
        $wslWheelhouse = ($wheelhouseProbe.Output -join "`n").Trim()
        $pipCommand += @('--no-index', '--find-links', $wslWheelhouse)
        $environmentSource = 'CREATED_VENV_LOCAL_WHEELHOUSE'
    }
    $pipCommand += @('--requirement', $wslRequirements)
    $pip = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 590 -CommandArguments $pipCommand) -TimeoutSeconds 600
    if ($pip.ExitCode -ne 0) {
        $result.status = if ($pip.TimedOut -or $pip.ExitCode -eq 124) { 'TOOL_ENV_TIMEOUT' } else { 'TOOL_ENV_FAIL' }
        $result.wave_mcp = 'INSTALL_FAILED'
        $result.next_action = '检查网络/代理、Python wheel 兼容性或用 -Wheelhouse 指向离线 wheel；不得把环境失败路由为 DUT_FAIL。'
        $result.detail = $pip.Output
        Complete-Result $result
        return
    }
}

$versionScript = "import importlib.metadata as m,json; print(json.dumps({'wave-mcp':m.version('wave-mcp'),'mcp':m.version('mcp'),'pylibfst':m.version('pylibfst'),'pyslang':m.version('pyslang')}))"
$versionsProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @($venvPythonWsl, '-c', $versionScript)) -TimeoutSeconds 30
if ($versionsProbe.ExitCode -ne 0) {
    $result.status = 'TOOL_ENV_FAIL'
    $result.wave_mcp = 'VERSION_PROBE_FAILED'
    $result.detail = $versionsProbe.Output
    $result.next_action = '目标 Python 缺少 wave-mcp 或直接依赖；使用 requirements-tested.txt 安装，或选择正确的 ExistingWavePython。'
    Complete-Result $result
    return
}
$versions = (($versionsProbe.Output -join "`n").Trim() | ConvertFrom-Json)
$expectedVersions = [ordered]@{ 'wave-mcp' = '0.1.1'; mcp = '2.1.1'; pylibfst = '0.2.1'; pyslang = '11.0.0' }
$versionMismatch = @($expectedVersions.GetEnumerator() | Where-Object { [string]$versions.($_.Key) -ne [string]$_.Value })
if ($versionMismatch.Count -gt 0) {
    $result.status = 'TOOL_VERSION_MISMATCH'
    $result.wave_mcp = 'REJECTED'
    $result.detail = @($versionMismatch | ForEach-Object { "$($_.Key): expected=$($_.Value), actual=$($versions.($_.Key))" })
    $result.next_action = '使用 requirements-tested.txt 创建匹配环境；不得把近似版本记录为已验证组合。'
    Complete-Result $result
    return
}
$importScript = "import wave_mcp.server,mcp,pylibfst,pyslang; print('IMPORT_OK')"
$importProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @($venvPythonWsl, '-c', $importScript)) -TimeoutSeconds 30
if ($importProbe.ExitCode -ne 0 -or ($importProbe.Output -join "`n") -notmatch 'IMPORT_OK') {
    $result.status = 'TOOL_ENV_IMPORT_FAIL'
    $result.wave_mcp = 'IMPORT_FAILED'
    $result.detail = $importProbe.Output
    $result.next_action = '包元数据匹配但 Python/native 模块无法 import；检查 wheel/ABI，不得声明查询环境 READY。'
    Complete-Result $result
    return
}

$converter = [ordered]@{ status = 'NOT_CONFIGURED'; path = $null; sha256 = $null }
if (-not [string]::IsNullOrWhiteSpace($Vcd2FstPath)) {
    $converterPath = [IO.Path]::GetFullPath($Vcd2FstPath)
    if (-not (Test-Path -LiteralPath $converterPath -PathType Leaf)) { throw "vcd2fst 不存在：$converterPath" }
    Assert-NoReparseInExistingPath -Path $converterPath
    $converter.status = 'CONFIGURED_UNVERIFIED'
    $converter.path = $converterPath
    $converter.sha256 = (Get-FileHash -LiteralPath $converterPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

$smoke = [ordered]@{ requested = [bool]$RunSmoke; status = 'NOT_RUN'; fst_sha256 = $null; query_status = $null }
if ($RunSmoke) {
    if ($converter.status -eq 'NOT_CONFIGURED') {
        $smoke.status = 'VCD_CONVERTER_REQUIRED'
    } else {
        $smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-fpga-wave-smoke-" + [guid]::NewGuid().ToString('N'))
        $smokeRootFull = [IO.Path]::GetFullPath($smokeRoot)
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $smokeRootFull.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe wave smoke root.' }
        try {
            New-Item -ItemType Directory -Path $smokeRootFull -Force | Out-Null
            $vcdPath = Join-Path $smokeRootFull 'synthetic.vcd'
            $fstPath = Join-Path $smokeRootFull 'synthetic.fst'
            $vcdLines = @(
                '$date','  deployment synthetic smoke','$end','$version','  codex-fpga-workflow','$end',
                '$timescale 1ps $end','$scope module tb $end','$var wire 1 ! clk $end','$var wire 1 " data $end',
                '$upscope $end','$enddefinitions $end','#0','0!','0"','#5000','1!','#10000','0!','1"','#15000','1!','#20000','0!','$end'
            )
            [IO.File]::WriteAllLines($vcdPath, $vcdLines, [Text.UTF8Encoding]::new($false))
            $converterProbe = Invoke-NativeProbe -FileName $converterPath -Arguments @($vcdPath, $fstPath) -TimeoutSeconds 120
            if ($converterProbe.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $fstPath -PathType Leaf)) { throw "vcd2fst smoke failed: $($converterProbe.Output -join ' ')" }

            $smokePathProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @('wslpath', '-a', '-u', $smokeRootFull)) -TimeoutSeconds 30
            $adapterPath = Join-Path $packageRoot 'integrations\wave-mcp\query_adapter.py'
            $adapterPathProbe = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 20 -CommandArguments @('wslpath', '-a', '-u', $adapterPath)) -TimeoutSeconds 30
            if ($smokePathProbe.ExitCode -ne 0 -or $adapterPathProbe.ExitCode -ne 0) { throw '无法把 smoke/adapter 路径转换为 WSL 路径。' }
            $wslSmoke = ($smokePathProbe.Output -join "`n").Trim()
            $wslAdapter = ($adapterPathProbe.Output -join "`n").Trim()
            $build = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 110 -CommandArguments @($venvPythonWsl, '-m', 'wave_mcp.cli.build_session', '--fst', "$wslSmoke/synthetic.fst", '--top', 'tb', '--out', "$wslSmoke/session", '--no-netlist')) -TimeoutSeconds 120
            if ($build.ExitCode -ne 0) { throw "wave session smoke failed: $($build.Output -join ' ')" }
            $query = Invoke-WslProbe -Wsl $wsl -Arguments (Get-WslTimedArguments -DistroName $Distro -LinuxTimeoutSeconds 110 -CommandArguments @($venvPythonWsl, $wslAdapter, '--session', "$wslSmoke/session", '--signal', 'tb.data', '--start-ps', '0', '--end-ps', '20000', '--transition-cap', '8', '--output', "$wslSmoke/query.json")) -TimeoutSeconds 120
            if ($query.ExitCode -ne 0) { throw "wave query smoke failed: $($query.Output -join ' ')" }
            $queryPath = Join-Path $smokeRootFull 'query.json'
            $queryReceipt = Get-Content -LiteralPath $queryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $fstSha = (Get-FileHash -LiteralPath $fstPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $normalized = @($queryReceipt.normalized_values)
            $expectedTransition = $normalized.Count -eq 2 -and $normalized[0].time_units -eq 0 -and $normalized[0].value -eq '0' -and $normalized[1].time_units -eq 10000 -and $normalized[1].value -eq '1'
            if ($queryReceipt.status -ne 'COMPLETE' -or -not $queryReceipt.boundary.consistent -or $queryReceipt.input_wave_sha256 -ne $fstSha -or -not $expectedTransition) { throw 'wave query smoke receipt/value timeline mismatch.' }
            $converter.status = 'VALIDATED_SYNTHETIC_SMOKE'
            $smoke.status = 'PASS'
            $smoke.fst_sha256 = $fstSha
            $smoke.query_status = $queryReceipt.status
        } catch {
            $smoke.status = 'FAIL'
            $smoke.detail = $_.Exception.Message
        } finally {
            Remove-SafeSmokeTree -Root $smokeRootFull
        }
    }
}

$environmentStatus = if ($converter.status -eq 'VALIDATED_SYNTHETIC_SMOKE') {
    'READY_WITH_VCD_CONVERTER'
} elseif ($RunSmoke -and $smoke.status -eq 'VCD_CONVERTER_REQUIRED') {
    'PARTIAL_VCD_CONVERTER_REQUIRED'
} elseif ($RunSmoke -and $smoke.status -eq 'FAIL') {
    'PARTIAL_WAVE_SMOKE_FAILED'
} else {
    'PACKAGES_READY_FST_QUERY_NOT_RUN'
}
$localManifest = [ordered]@{
    schema_version = 'fpga-wave-local-environment-1.0'
    status = $environmentStatus
    distro = $Distro
    wsl_kernel = $result.wsl_kernel
    tool_root = $toolRootFull
    python_wsl = $venvPythonWsl
    base_python_command = $WslPython
    environment_source = $environmentSource
    wave_mcp = [ordered]@{
        version = $versions.'wave-mcp'
        direct_dependencies = [ordered]@{ mcp = $versions.mcp; pylibfst = $versions.pylibfst; pyslang = $versions.pyslang }
    }
    converter = $converter
    smoke = $smoke
    policy = [ordered]@{
        global_path_modified = $false
        global_library_mapping_modified = $false
        install_wsl_automatically = $false
        claim_ceiling = 'LOCAL_TOOL_DISCOVERY_ONLY'
    }
    verified_at_utc = [DateTime]::UtcNow.ToString('o')
}
$manifestPath = Join-Path $toolRootFull 'environment.local.json'
Assert-NoReparseInExistingPath -Path $toolRootFull
if (Test-Path -LiteralPath $manifestPath) { Assert-NoReparseInExistingPath -Path $manifestPath }
Write-AtomicUtf8Json -Path $manifestPath -Value $localManifest

$result.status = $localManifest.status
$result.wave_mcp = "READY_$($versions.'wave-mcp')"
$result.converter = $converter.status
$result.environment_manifest = $manifestPath
$result.next_action = if ($converter.status -eq 'VALIDATED_SYNTHETIC_SMOKE') { '合成 VCD→FST→wave-mcp smoke 已通过；真实项目仍需项目级证据。' } elseif ($converter.status -eq 'CONFIGURED_UNVERIFIED') { '包和 import 已核对，转换器已记录但未跑 query smoke；使用 -RunSmoke 后才能声明 READY。' } else { '包和 import 已核对，但尚未执行真实 FST query；提供转换器并使用 -RunSmoke，或在项目级运行 FST 查询。' }
Complete-Result $result
} finally {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
