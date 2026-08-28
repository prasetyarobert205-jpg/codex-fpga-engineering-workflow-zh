[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$errors = [Collections.Generic.List[string]]::new()

function Add-CheckError([string]$Message) { $script:errors.Add($Message) }
function Get-PortablePath([string]$Path) { return ([IO.Path]::GetRelativePath($root, $Path) -replace '\\', '/') }

$required = @(
    '.codex-plugin/plugin.json', 'README.md', 'AGENTS.md', 'LICENSE', 'VERSION', 'CAPABILITY-MANIFEST.json',
    'CHANGELOG.md', 'COMPATIBILITY.md', 'CONTRIBUTING.md', 'SECURITY.md', 'assets/hero.svg',
    'docs/README.md', 'docs/architecture.md', 'docs/advantages.md', 'docs/roles.md',
    'docs/installation.md', 'docs/usage.md', 'docs/safety-and-evidence.md', 'docs/public-private-boundary.md',
    'docs/capability-equivalence.md',
    'templates/AGENTS.fpga.md', 'templates/fault-library.config.example.json',
    'skills/run-fpga-workflow/SKILL.md', 'skills/run-fpga-workflow/agents/openai.yaml',
    'skills/run-fpga-workflow/assets/icon.svg',
    'skills/run-fpga-workflow/references/artifact-contracts.md',
    'skills/run-fpga-workflow/references/task-profiles.md',
    'skills/run-fpga-workflow/references/temporal-evidence-review.md',
    'skills/run-fpga-workflow/references/simulation-evidence.md',
    'skills/run-fpga-workflow/references/project-layout-and-toolflow.md',
    'skills/run-fpga-workflow/references/project-identity-and-task-delta.md',
    'skills/run-fpga-workflow/references/ip-integration.md',
    'skills/run-fpga-workflow/references/physical-implementation.md',
    'skills/run-fpga-workflow/references/private-fault-library.md',
    'skills/run-fpga-workflow/references/improvement-evidence.md',
    'skills/run-fpga-workflow/scripts/detect-fpga-vendor.ps1',
    'skills/run-fpga-workflow/scripts/find-fpga-fault-case.ps1',
    'skills/run-fpga-workflow/scripts/initialize-fpga-simlibs.ps1',
    'skills/run-fpga-workflow/scripts/invoke-fpga-preflight.ps1',
    'skills/run-fpga-workflow/scripts/new-fpga-project.ps1',
    'skills/run-fpga-workflow/scripts/update-fpga-filelists.ps1',
    'scripts/install.ps1', 'scripts/verify-install.ps1', 'scripts/uninstall.ps1',
    'scripts/detect-vendor.ps1', 'scripts/update-filelists.ps1', 'scripts/preflight-project.ps1',
    'scripts/prepare-vendor-libraries.ps1', 'scripts/new-fpga-project.ps1', 'scripts/fault-library.ps1',
    'scripts/validate-simulation-evidence.ps1',
    'templates/fpga-project/common/README.md.template',
    'templates/fpga-project/common/AGENTS.md',
    'templates/fpga-project/common/build-run.bat.template',
    'templates/fpga-project/common/simulation-run.bat.template',
    'templates/fpga-project/common/simulation-setting.txt.template',
    'templates/fpga-project/common/vsim.do.template',
    'templates/fpga-project/common/lint-run.bat.template',
    'templates/fpga-project/common/setting.bat.template',
    '.github/workflows/validate.yml'
)

foreach ($rel in $required) {
    $path = Join-Path $root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-CheckError "缺少必需文件：$rel" }
}

$expectedNames = @(
    'fpga_architect','fpga_engineer','verification_engineer','fpga_temporal_evidence_reviewer',
    'fpga_cdc_timing_reviewer','fpga_interface_architect','fpga_vendor_platform_reviewer',
    'fpga_board_validation_engineer','fpga_reviewer','system_architect','embedded_engineer',
    'hardware_datasheet','independent_reviewer'
)
$readOnlyExpected = @(
    'fpga_architect','fpga_temporal_evidence_reviewer','fpga_cdc_timing_reviewer',
    'fpga_interface_architect','fpga_vendor_platform_reviewer','fpga_board_validation_engineer',
    'fpga_reviewer','system_architect','hardware_datasheet','independent_reviewer'
)
$agentFiles = @(Get-ChildItem -LiteralPath (Join-Path $root '.codex\agents') -File -Filter '*.toml')
if ($agentFiles.Count -ne 13) { Add-CheckError "应有 13 个角色 TOML，实际为 $($agentFiles.Count)。" }
$seen = @{}
foreach ($file in $agentFiles) {
    try { $text = [IO.File]::ReadAllText($file.FullName, [Text.UTF8Encoding]::new($false, $true)) }
    catch { Add-CheckError "角色文件不是严格 UTF-8：$($file.Name)"; continue }
    $match = [regex]::Match($text, '(?m)^name\s*=\s*"([^"]+)"\s*$')
    if (-not $match.Success) { Add-CheckError "角色缺少 name：$($file.Name)"; continue }
    $name = $match.Groups[1].Value
    if ($name -ne $file.BaseName) { Add-CheckError "角色名与文件名不一致：$($file.Name) -> $name" }
    if ($seen.ContainsKey($name)) { Add-CheckError "角色名重复：$name" } else { $seen[$name] = $true }
    $isReadOnly = $text -match '(?m)^sandbox_mode\s*=\s*"read-only"\s*$'
    if ($name -in $readOnlyExpected -and -not $isReadOnly) { Add-CheckError "只读角色缺少 read-only sandbox：$name" }
    if ($name -notin $readOnlyExpected -and $isReadOnly) { Add-CheckError "条件写入角色被错误设为只读：$name" }
    if ($text -notmatch '[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]') { Add-CheckError "角色没有中文说明：$name" }
}
foreach ($name in $expectedNames) { if (-not $seen.ContainsKey($name)) { Add-CheckError "缺少角色：$name" } }

$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { Add-CheckError "VERSION 不是语义化版本：$version" }
try { $plugin = Get-Content -LiteralPath (Join-Path $root '.codex-plugin\plugin.json') -Raw | ConvertFrom-Json }
catch { Add-CheckError 'plugin.json 不是有效 JSON。'; $plugin = $null }
if ($null -ne $plugin) {
    if ($plugin.name -ne 'codex-fpga-engineering-workflow-zh') { Add-CheckError '插件名称不匹配。' }
    if ($plugin.version -ne $version) { Add-CheckError '插件版本与 VERSION 不一致。' }
    if ($plugin.license -ne 'MIT' -or $plugin.skills -ne './skills/') { Add-CheckError '插件 license 或 skills 路径不正确。' }
    foreach ($unsupported in @('apps','mcpServers','hooks')) {
        if ($plugin.PSObject.Properties.Name -contains $unsupported) { Add-CheckError "插件清单包含未配置字段：$unsupported" }
    }
}

try { $capability = Get-Content -LiteralPath (Join-Path $root 'CAPABILITY-MANIFEST.json') -Raw | ConvertFrom-Json }
catch { Add-CheckError 'CAPABILITY-MANIFEST.json 不是有效 JSON。'; $capability = $null }
if ($null -ne $capability) {
    if ($capability.package_version -ne $version) { Add-CheckError '能力清单版本与 VERSION 不一致。' }
    if ($capability.roles.count -ne 13 -or @($capability.roles.strict_read_only).Count -ne 10 -or @($capability.roles.conditional_sequential_writers).Count -ne 3) {
        Add-CheckError '能力清单角色权限计数不正确。'
    }
    if ($capability.skill_contract.files -ne 45 -or $capability.skill_contract.schemas -ne 11 -or $capability.skill_contract.deterministic_scripts -ne 6) {
        Add-CheckError '能力清单 Skill 文件、schema 或脚本计数不正确。'
    }
}

$skillText = Get-Content -LiteralPath (Join-Path $root 'skills\run-fpga-workflow\SKILL.md') -Raw
foreach ($reference in @(
    'references/task-profiles.md','references/artifact-contracts.md','references/temporal-evidence-review.md',
    'references/simulation-evidence.md','references/project-layout-and-toolflow.md',
    'references/project-identity-and-task-delta.md','references/ip-integration.md',
    'references/physical-implementation.md','references/private-fault-library.md',
    'references/improvement-evidence.md'
)) {
    if ($skillText -notmatch [regex]::Escape($reference)) { Add-CheckError "Skill 未引用：$reference" }
}
foreach ($token in @(
    'ANALYZE','QUICK','FULL','DIAGNOSTIC_SMOKE','FUNCTIONAL_ACCEPTANCE','SPECIALIST_ACCEPTANCE',
    'RTL_IMPLEMENTATION','IP_INTEGRATION','BUILD_FLOW','PHYSICAL_IMPLEMENTATION','RELEASE_PACKAGING',
    'project/par','simulation/work','codex_out','最多三轮','NEEDS_PARTITION'
)) {
    if ($skillText -notmatch [regex]::Escape($token)) { Add-CheckError "Skill 缺少关键合同：$token" }
}

$schemaFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'skills\run-fpga-workflow\references\schemas') -File -Filter '*.schema.json')
if ($schemaFiles.Count -ne 11) { Add-CheckError "应有 11 个 JSON Schema，实际为 $($schemaFiles.Count)。" }
foreach ($schema in $schemaFiles) {
    try { $null = Get-Content -LiteralPath $schema.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Add-CheckError "无效 JSON Schema：$($schema.Name)" }
}

$parseTargets = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psd1') }
foreach ($target in $parseTargets) {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($target.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in $parseErrors) { Add-CheckError "PowerShell 语法错误：$(Get-PortablePath $target.FullName)：$($parseError.Message)" }
}

$buildBat = Get-Content -LiteralPath (Join-Path $root 'templates\fpga-project\common\build-run.bat.template') -Raw
$simBat = Get-Content -LiteralPath (Join-Path $root 'templates\fpga-project\common\simulation-run.bat.template') -Raw
foreach ($pair in @(@('build',$buildBat),@('simulation',$simBat))) {
    if ($pair[1] -notmatch [regex]::Escape('%~dp0')) { Add-CheckError "$($pair[0]) BAT 未使用 %~dp0。" }
    if ($pair[1] -match '(?i)pwsh|powershell|\.ps1|\.psd1') { Add-CheckError "$($pair[0]) 正式 BAT 仍依赖 PowerShell。" }
    if ($pair[1] -match '(?i)VIVADO_BAT|MODELSIM_EXE|[A-Z]:\\[^\r\n"]+\.(exe|bat)') { Add-CheckError "$($pair[0]) BAT 写死绝对 executable。" }
}
foreach ($removed in @('vendor-build.bat.template','vendor-sim.bat.template')) {
    if (Test-Path -LiteralPath (Join-Path $root "templates\fpga-project\common\$removed")) { Add-CheckError "仍存在废弃模板：$removed" }
}

$scaffoldText = Get-Content -LiteralPath (Join-Path $root 'scripts\new-fpga-project.ps1') -Raw
foreach ($canonical in @('project/rtl','project/par','project/script','simulation/script','linter/script','release/output')) {
    if ($scaffoldText -notmatch [regex]::Escape($canonical)) { Add-CheckError "脚手架缺少标准目录：$canonical" }
}
if ($scaffoldText -match '(?i)(project2|par2|script2|scriptC)') { Add-CheckError '脚手架包含数字或临时后缀标准目录。' }
if ($scaffoldText -notmatch 'canonical_project_file') { Add-CheckError '脚手架未报告 canonical project file。' }

$temporal = Get-Content -LiteralPath (Join-Path $root '.codex\agents\fpga_temporal_evidence_reviewer.toml') -Raw
foreach ($token in @('STATIC_CYCLE','SIMULATION_EVIDENCE','COMBINED','SHADOW','NEEDS_PARTITION')) {
    if ($temporal -notmatch $token) { Add-CheckError "逐拍 reviewer 缺少：$token" }
}
$verification = Get-Content -LiteralPath (Join-Path $root '.codex\agents\verification_engineer.toml') -Raw
if ($verification -notmatch '不得.*自签|不能.*自签') { Add-CheckError '验证资产作者自签边界缺失。' }

$improvement = Get-Content -LiteralPath (Join-Path $root 'skills\run-fpga-workflow\references\improvement-evidence.md') -Raw
if ($improvement -match '(?i)C:\\Users\\|D:\\|86158|backup-20\d{6}|历史“已通过”状态\s*：') { Add-CheckError '公开改进账本疑似包含本机历史或绝对路径。' }

$allTextFiles = Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
    ($_.Extension -in @('.md','.toml','.json','.yaml','.yml','.ps1','.psd1','.svg','.txt','.template','.bat','.do') -or
    $_.Name -in @('LICENSE','VERSION','.gitignore','.gitattributes')) -and $_.FullName -ne $PSCommandPath
}
foreach ($file in $allTextFiles) {
    try { $content = [IO.File]::ReadAllText($file.FullName, [Text.UTF8Encoding]::new($false, $true)) }
    catch { Add-CheckError "文件不是严格 UTF-8：$(Get-PortablePath $file.FullName)"; continue }
    if ($content -match '(?i)(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|AKIA[0-9A-Z]{16})') {
        Add-CheckError "疑似密钥：$(Get-PortablePath $file.FullName)"
    }
    if ($content -match '(?i)C:\\Users\\86158|D:\\PDS|hosonsoft') {
        Add-CheckError "疑似本机/私人路径：$(Get-PortablePath $file.FullName)"
    }
}

foreach ($forbidden in @('README.zh-CN.md','README.en.md','docs/en','docs/zh-CN')) {
    if (Test-Path -LiteralPath (Join-Path $root ($forbidden -replace '/', [IO.Path]::DirectorySeparatorChar))) {
        Add-CheckError "全中文仓库不应保留重复语言树：$forbidden"
    }
}

foreach ($doc in @('README.md','AGENTS.md','CHANGELOG.md','COMPATIBILITY.md','CONTRIBUTING.md','SECURITY.md')) {
    $text = Get-Content -LiteralPath (Join-Path $root $doc) -Raw
    if ($text -notmatch '[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]') { Add-CheckError "根文档缺少中文：$doc" }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "错误：$_" -ForegroundColor Red }
    throw "包验证失败，共 $($errors.Count) 项。"
}

Write-Host "包验证通过：版本 $version；13 个角色（10 只读、3 条件写入）；11 个 schema；完整中文 Skill/references；确定性脚本、原生 BAT/DO 模板、UTF-8、隐私和公开内容检查全部通过。"
