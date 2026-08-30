[CmdletBinding()]
param([switch]$NoRuntimeCanaries)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$errors = [Collections.Generic.List[string]]::new()

function Add-CheckError([string]$Message) { $script:errors.Add($Message) }
function Get-PortablePath([string]$Path) { return ([IO.Path]::GetRelativePath($root, $Path) -replace '\\', '/') }

$required = @(
    '.codex-plugin/plugin.json', '.agents/plugins/marketplace.json', 'README.md', 'INSTALL_WITH_CODEX.md', 'AGENTS.md', 'LICENSE', 'THIRD_PARTY-NOTICES.md', 'VERSION', 'CAPABILITY-MANIFEST.json',
    'CHANGELOG.md', 'COMPATIBILITY.md', 'CONTRIBUTING.md', 'SECURITY.md', 'assets/hero.svg',
    'docs/README.md', 'docs/architecture.md', 'docs/advantages.md', 'docs/roles.md',
    'docs/installation.md', 'docs/usage.md', 'docs/safety-and-evidence.md', 'docs/public-private-boundary.md',
    'docs/waveform-observation.md',
    'docs/capability-equivalence.md',
    'templates/AGENTS.fpga.md', 'templates/fault-library.config.example.json',
    'skills/run-fpga-workflow/SKILL.md', 'skills/run-fpga-workflow/agents/openai.yaml',
    'skills/setup-fpga-workflow/SKILL.md', 'skills/setup-fpga-workflow/agents/openai.yaml', 'skills/setup-fpga-workflow/references/source.json',
    'skills/run-fpga-workflow/assets/icon.svg',
    'skills/run-fpga-workflow/references/artifact-contracts.md',
    'skills/run-fpga-workflow/references/task-profiles.md',
    'skills/run-fpga-workflow/references/temporal-evidence-review.md',
    'skills/run-fpga-workflow/references/simulation-evidence.md',
    'skills/run-fpga-workflow/references/waveform-observation.md',
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
    'scripts/bootstrap.ps1', 'scripts/deployment-doctor.ps1', 'scripts/prepare-wave-environment.ps1',
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
    '.github/workflows/validate.yml',
    'integrations/wave-mcp/README.md', 'integrations/wave-mcp/query_adapter.py',
    'integrations/wave-mcp/test_query_adapter.py', 'integrations/wave-mcp/validate_environment.py',
    'integrations/wave-mcp/environment.example.json', 'integrations/wave-mcp/tested-environment.json',
    'integrations/wave-mcp/requirements.txt', 'integrations/wave-mcp/requirements-tested.txt',
    'integrations/wave-mcp/LICENSE.wave-mcp'
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
    if (@($plugin.interface.defaultPrompt).Count -gt 3) { Add-CheckError '插件 defaultPrompt 超过 3 条。' }
}

try { $marketplace = Get-Content -LiteralPath (Join-Path $root '.agents\plugins\marketplace.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Add-CheckError 'marketplace.json 不是有效 JSON。'; $marketplace = $null }
if ($null -ne $marketplace) {
    if ($marketplace.name -ne 'codex-fpga-zh' -or $marketplace.interface.displayName -ne '中文 FPGA 工程工作流') { Add-CheckError 'Marketplace 名称或显示名不正确。' }
    if (@($marketplace.plugins).Count -ne 1) { Add-CheckError 'Marketplace 应只包含当前一个插件。' }
    else {
        $entry = $marketplace.plugins[0]
        if ($entry.name -ne 'codex-fpga-engineering-workflow-zh' -or $entry.source.source -ne 'url') { Add-CheckError 'Marketplace 插件名或 root URL source 不正确。' }
        if ($entry.source.url -ne 'https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh.git' -or $entry.source.ref -ne 'v1.2.0') { Add-CheckError 'Marketplace URL/ref 未冻结到 v1.2.0。' }
        if ($entry.policy.installation -ne 'AVAILABLE' -or $entry.policy.authentication -ne 'ON_INSTALL' -or [string]::IsNullOrWhiteSpace($entry.category)) { Add-CheckError 'Marketplace policy/category 不完整。' }
    }
}

try { $capability = Get-Content -LiteralPath (Join-Path $root 'CAPABILITY-MANIFEST.json') -Raw | ConvertFrom-Json }
catch { Add-CheckError 'CAPABILITY-MANIFEST.json 不是有效 JSON。'; $capability = $null }
if ($null -ne $capability) {
    if ($capability.package_version -ne $version) { Add-CheckError '能力清单版本与 VERSION 不一致。' }
    if ($capability.roles.count -ne 13 -or @($capability.roles.strict_read_only).Count -ne 10 -or @($capability.roles.conditional_sequential_writers).Count -ne 3) {
        Add-CheckError '能力清单角色权限计数不正确。'
    }
    if ($capability.skill_contract.files -ne 46 -or $capability.skill_contract.schemas -ne 11 -or $capability.skill_contract.deterministic_scripts -ne 6) {
        Add-CheckError '能力清单 Skill 文件、schema 或脚本计数不正确。'
    }
    if (@($capability.plugin_distribution.skills).Count -ne 2 -or -not $capability.plugin_distribution.github_marketplace -or $capability.plugin_distribution.marketplace_ref -ne 'v1.2.0' -or $capability.plugin_distribution.bootstrap_scripts -ne 3) { Add-CheckError '能力清单的 Plugin/部署合同不正确。' }
    if ($capability.plugin_distribution.default_user_install_overwrite -ne $false -or $capability.plugin_distribution.default_install_wsl -ne $false) { Add-CheckError '能力清单错误放宽了默认覆盖或 WSL 安装。' }
}

$skillText = Get-Content -LiteralPath (Join-Path $root 'skills\run-fpga-workflow\SKILL.md') -Raw
foreach ($reference in @(
    'references/task-profiles.md','references/artifact-contracts.md','references/temporal-evidence-review.md',
    'references/simulation-evidence.md','references/waveform-observation.md','references/project-layout-and-toolflow.md',
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

$setupSkill = Get-Content -LiteralPath (Join-Path $root 'skills\setup-fpga-workflow\SKILL.md') -Raw -Encoding UTF8
foreach ($token in @('setup-fpga-workflow','bootstrap.ps1','validate-package.ps1','references/source.json','PACKAGE_SOURCE_REQUIRED','不得回退到未固定的','WaveMode','PARTIAL_WSL_REQUIRED','不得自行执行','不修改注册表','新开 Codex 会话')) {
    if ($setupSkill -notmatch [regex]::Escape($token)) { Add-CheckError "部署 Skill 缺少合同：$token" }
}
$setupMetadata = Get-Content -LiteralPath (Join-Path $root 'skills\setup-fpga-workflow\agents\openai.yaml') -Raw -Encoding UTF8
if ($setupMetadata -notmatch 'allow_implicit_invocation:\s*false') { Add-CheckError '部署 Skill 必须禁止隐式调用。' }
$setupSource = Get-Content -LiteralPath (Join-Path $root 'skills\setup-fpga-workflow\references\source.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($setupSource.package -ne 'codex-fpga-engineering-workflow-zh' -or $setupSource.version -ne $version -or $setupSource.ref -ne 'v1.2.0' -or $setupSource.repository -ne 'https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh.git') { Add-CheckError '部署 Skill 的固定 source manifest 不正确。' }

$simulationSchema = Join-Path $root 'skills\run-fpga-workflow\references\schemas\simulation-evidence.schema.json'
function Test-SimulationSchema([hashtable]$Document) {
    try { return Test-Json -Json ($Document | ConvertTo-Json -Depth 12 -Compress) -SchemaFile $simulationSchema -ErrorAction SilentlyContinue }
    catch { return $false }
}
$diagNoWave = @{
    schema_version='0.3'; snapshot_id='s1'; classification='DIAGNOSTIC_ONLY'; evidence_profile='DIAGNOSTIC_SMOKE'
    requirements=@(); checker_results=@(); negative_canaries=@(); scoreboard_drained=$false
}
if (-not (Test-SimulationSchema $diagNoWave)) { Add-CheckError 'DIAGNOSTIC_ONLY 无波形工件应当合法。' }
$functionalBase = @{
    schema_version='0.3'; snapshot_id='s1'; classification='SIMULATION_PASS'; evidence_profile='FUNCTIONAL_ACCEPTANCE'
    requirements=@(@{id='R1';source='spec'}); checker_results=@(@{checker='scoreboard';requirement_id='R1';passed=$true})
    negative_canaries=@(@{name='late';detected=$true}); scoreboard_drained=$true; xz_policy='strict'; proof_packets=@('proof.json')
}
foreach ($state in @('NOT_APPLICABLE','CONSISTENT')) {
    $doc = $functionalBase.Clone(); $doc.waveform_consistency = $state
    if (-not (Test-SimulationSchema $doc)) { Add-CheckError "合法 waveform_consistency 被拒绝：$state" }
}
$diagMixed = $diagNoWave.Clone(); $diagMixed.waveform_consistency = 'INCONCLUSIVE'; $diagMixed.manual_waveform_consistent = $false
if (Test-SimulationSchema $diagMixed) { Add-CheckError '非 PASS 工件的新旧 waveform 字段也必须互斥。' }

$evidenceValidator = Join-Path $root 'scripts\validate-simulation-evidence.ps1'
if (-not $NoRuntimeCanaries) {
  $evidenceFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("fpga-simulation-evidence-" + [guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType Directory -Path $evidenceFixtureRoot -Force | Out-Null
    $diagnosticFixture = [ordered]@{
        schema_version='0.3'; run_id='diag1'; snapshot_id='diag-s1'; evidence_profile='DIAGNOSTIC_SMOKE'; classification='DIAGNOSTIC_ONLY'
        compile_exit_code=0; elaboration_exit_code=0; run_exit_code=0
        requirements=@(); checker_results=@(); negative_canaries=@(); scoreboard_drained=$false
    }
    $diagnosticPath = Join-Path $evidenceFixtureRoot 'diagnostic-evidence.json'
    [IO.File]::WriteAllText($diagnosticPath, (($diagnosticFixture | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    try { $null = & $evidenceValidator -EvidencePath $diagnosticPath -ExpectedSnapshotId diag-s1 }
    catch { Add-CheckError "最小 DIAGNOSTIC_ONLY 被正式 validator 过度拒绝：$($_.Exception.Message)" }
    [IO.File]::WriteAllText((Join-Path $evidenceFixtureRoot 'proof.json'), '{}', [Text.UTF8Encoding]::new($false))
    $evidenceFixture = [ordered]@{
        schema_version='0.3'; run_id='r1'; snapshot_id='s1'; evidence_profile='FUNCTIONAL_ACCEPTANCE'; classification='SIMULATION_PASS'
        compile_exit_code=0; elaboration_exit_code=0; run_exit_code=0; tests_discovered=1; tests_executed=1
        requirements=@(@{id='R1';source='spec'}); checker_results=@(@{checker='scoreboard';requirement_id='R1';passed=$true})
        scoreboard_drained=$true; comparisons=@(@{cycle=1;passed=$true}); negative_canaries=@(@{name='late';detected=$true})
        xz_policy='strict'; proof_packets=@('proof.json'); waveform_consistency='CONSISTENT'
    }
    $evidencePath = Join-Path $evidenceFixtureRoot 'simulation-evidence.json'
    [IO.File]::WriteAllText($evidencePath, (($evidenceFixture | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    try { $null = & $evidenceValidator -EvidencePath $evidencePath -ExpectedSnapshotId s1 }
    catch { Add-CheckError "canonical proof_packets 未同时通过 schema 与正式 validator：$($_.Exception.Message)" }
    Remove-Item -LiteralPath (Join-Path $evidenceFixtureRoot 'proof.json') -Force
    $missingProofRejected = $false
    try { $null = & $evidenceValidator -EvidencePath $evidencePath -ExpectedSnapshotId s1 }
    catch { $missingProofRejected = $true }
    if (-not $missingProofRejected) { Add-CheckError '正式 validator 未拒绝缺失的 proof_packets 工件。' }
  } finally {
    if (Test-Path -LiteralPath $evidenceFixtureRoot) { Remove-Item -LiteralPath $evidenceFixtureRoot -Recurse -Force }
  }
}
foreach ($state in @('CONTRADICTORY','INCONCLUSIVE')) {
    $doc = $functionalBase.Clone(); $doc.waveform_consistency = $state
    if (Test-SimulationSchema $doc) { Add-CheckError "不允许支持 PASS 的 waveform_consistency 被接受：$state" }
    $doc.manual_waveform_consistent = $true
    if (Test-SimulationSchema $doc) { Add-CheckError "新旧 waveform 字段冲突被接受：$state + legacy true" }
}
$legacy = $functionalBase.Clone(); $legacy.manual_waveform_consistent = $true
if (-not (Test-SimulationSchema $legacy)) { Add-CheckError 'Legacy manual_waveform_consistent=true 应保持兼容。' }
foreach ($state in @('NOT_APPLICABLE','CONSISTENT')) {
    foreach ($legacyValue in @($false,$true)) {
        $doc = $functionalBase.Clone(); $doc.waveform_consistency = $state; $doc.manual_waveform_consistent = $legacyValue
        if (Test-SimulationSchema $doc) { Add-CheckError "新旧 waveform 字段必须互斥：$state + legacy $legacyValue" }
    }
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

$installText = Get-Content -LiteralPath (Join-Path $root 'scripts\install.ps1') -Raw -Encoding UTF8
foreach ($token in @('run-fpga-workflow','setup-fpga-workflow','拒绝覆盖不同内容','WhatIfPreference','PlanOnly','REPLACE_WITH_BACKUP','Assert-SafeInstallRoot','Assert-SafeTargetPath','CodexFpgaDeploy','Write-AtomicUtf8Json')) {
    if ($installText -notmatch [regex]::Escape($token)) { Add-CheckError "安装器缺少合同：$token" }
}
if ($installText -notmatch [regex]::Escape('NONDEFAULT_CODEX_HOME_UNVERIFIED')) { Add-CheckError '安装器未对非默认 CODEX_HOME fail-closed。' }
$bootstrapText = Get-Content -LiteralPath (Join-Path $root 'scripts\bootstrap.ps1') -Raw -Encoding UTF8
$doctorText = Get-Content -LiteralPath (Join-Path $root 'scripts\deployment-doctor.ps1') -Raw -Encoding UTF8
$prepareWaveText = Get-Content -LiteralPath (Join-Path $root 'scripts\prepare-wave-environment.ps1') -Raw -Encoding UTF8
foreach ($token in @('validate-package.ps1','install.ps1','verify-install.ps1','deployment-doctor.ps1','PLAN_NO_CHANGES','UNVERIFIED_TRANSIENT','doctor.fresh_session_required','PARTIAL','global_path_modified')) {
    if ($bootstrapText -notmatch [regex]::Escape($token)) { Add-CheckError "bootstrap 缺少合同：$token" }
}
if ($bootstrapText -notmatch [regex]::Escape('NoRuntimeCanaries')) { Add-CheckError 'bootstrap WhatIf 未切换为纯静态包验证。' }
foreach ($token in @('PARTIAL_WSL_REQUIRED','PARTIAL_WSL2_REQUIRED','TOOL_ENV_ACCESS_DENIED','PARTIAL_PYTHON_REQUIRED','PACKAGES_READY_FST_QUERY_NOT_RUN','READY_0.1.1_LIVE','LOCAL_ENV_UNAVAILABLE','TOOL_ENV_IMPORT_FAIL','VALIDATED_SYNTHETIC_SMOKE','TOOL_VERSION_MISMATCH','INSTALL_ALREADY_RUNNING','ExistingWavePython','Wheelhouse','RunSmoke','expectedTransition','requirements-tested.txt','environment.local.json','global_library_mapping_modified','Threading.Mutex','Get-WslTimedArguments','--kill-after=5s','Remove-SafeSmokeTree','Write-AtomicUtf8Json','ToolRoot 不能是磁盘根目录','ToolRoot 必须位于插件/仓库根之外')) {
    if ($prepareWaveText -notmatch [regex]::Escape($token)) { Add-CheckError "wave 环境准备脚本缺少合同：$token" }
}
foreach ($pair in @(@('verify-install.ps1',(Get-Content -LiteralPath (Join-Path $root 'scripts\verify-install.ps1') -Raw -Encoding UTF8)),@('uninstall.ps1',(Get-Content -LiteralPath (Join-Path $root 'scripts\uninstall.ps1') -Raw -Encoding UTF8)),@('deployment-doctor.ps1',$doctorText))) {
    foreach ($token in @('Assert-SafeInstallRoot','Assert-SafeTargetPath','Test-AllowedInstalledRelativePath','Get-ExpectedRelativePaths','expected file-set')) {
        if ($pair[1] -notmatch [regex]::Escape($token)) { Add-CheckError "$($pair[0]) 缺少部署安全合同：$token" }
    }
}
if (($bootstrapText + $prepareWaveText + $doctorText) -match '(?im)^\s*(?:&\s*)?(?:wsl(?:\.exe)?\s+--install\b|sudo\b|apt(?:-get)?\s+install\b|setx\b)|SetEnvironmentVariable\s*\(') { Add-CheckError '部署脚本包含默认禁止的 WSL/系统包/全局环境安装动作。' }

$temporal = Get-Content -LiteralPath (Join-Path $root '.codex\agents\fpga_temporal_evidence_reviewer.toml') -Raw
foreach ($token in @('STATIC_CYCLE','SIMULATION_EVIDENCE','COMBINED','SHADOW','NEEDS_PARTITION')) {
    if ($temporal -notmatch $token) { Add-CheckError "逐拍 reviewer 缺少：$token" }
}
$verification = Get-Content -LiteralPath (Join-Path $root '.codex\agents\verification_engineer.toml') -Raw
if ($verification -notmatch '不得.*自签|不能.*自签') { Add-CheckError '验证资产作者自签边界缺失。' }

$improvement = Get-Content -LiteralPath (Join-Path $root 'skills\run-fpga-workflow\references\improvement-evidence.md') -Raw
if ($improvement -match '(?i)C:\\Users\\|D:\\|86158|backup-20\d{6}|历史“已通过”状态\s*：') { Add-CheckError '公开改进账本疑似包含本机历史或绝对路径。' }

$waveIntegration = Join-Path $root 'integrations\wave-mcp'
try { $testedWave = Get-Content -LiteralPath (Join-Path $waveIntegration 'tested-environment.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Add-CheckError 'tested-environment.json 不是有效 JSON。'; $testedWave = $null }
if ($null -ne $testedWave) {
    if ($testedWave.wave_mcp.version -ne '0.1.1' -or $testedWave.scope -ne 'ONE_PROJECT_DIAGNOSTIC_SMOKE') { Add-CheckError 'wave-mcp 实测环境版本或 scope 不正确。' }
    if ($testedWave.privacy.absolute_machine_paths_included -ne $false -or $testedWave.privacy.project_or_customer_paths_included -ne $false) { Add-CheckError 'wave-mcp 实测环境隐私声明不正确。' }
    if ($testedWave.wave_mcp.package_tree.file_count -ne 19 -or $testedWave.wave_mcp.package_tree.tree_algorithm -ne 'sha256(join(entries, LF))') { Add-CheckError 'wave-mcp package tree 的公开复算合同不完整。' }
    if ($testedWave.wave_mcp.direct_dependencies.mcp -ne '2.1.1' -or $testedWave.wave_mcp.direct_dependencies.pylibfst -ne '0.2.1' -or $testedWave.wave_mcp.direct_dependencies.pyslang -ne '11.0.0') { Add-CheckError 'wave-mcp 实测直接依赖版本不完整。' }
}
$waveRequirements = (Get-Content -LiteralPath (Join-Path $waveIntegration 'requirements.txt') -Raw -Encoding UTF8).Trim()
if ($waveRequirements -ne 'wave-mcp==0.1.1') { Add-CheckError 'wave-mcp 依赖未锁定到实际验证版本 0.1.1。' }
$testedRequirements = @(Get-Content -LiteralPath (Join-Path $waveIntegration 'requirements-tested.txt') -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
if (($testedRequirements -join "`n") -ne "wave-mcp==0.1.1`nmcp==2.1.1`npylibfst==0.2.1`npyslang==11.0.0") { Add-CheckError 'wave-mcp 重现实测依赖组合不匹配。' }
$waveAdapter = Get-Content -LiteralPath (Join-Path $waveIntegration 'query_adapter.py') -Raw -Encoding UTF8
foreach ($token in @('open_session','close_session','signal_info','signal_value_at','signal_values_in_range','transition_cap + 1','input_wave_sha256','normalize_window_start','OBSERVATION_ONLY','DIAGNOSTIC_ONLY')) {
    if ($waveAdapter -notmatch [regex]::Escape($token)) { Add-CheckError "wave-mcp adapter 缺少合同：$token" }
}
$workflowText = Get-Content -LiteralPath (Join-Path $root '.github\workflows\validate.yml') -Raw -Encoding UTF8
foreach ($token in @('py_compile','validate_environment.py','test_query_adapter.py','query_adapter.py --help')) {
    if ($workflowText -notmatch [regex]::Escape($token)) { Add-CheckError "GitHub CI 缺少 Python 集成检查：$token" }
}
$waveLicense = Get-Content -LiteralPath (Join-Path $waveIntegration 'LICENSE.wave-mcp') -Raw -Encoding UTF8
if ($waveLicense -notmatch 'Copyright \(C\) 2026 Tencent' -or $waveLicense -notmatch 'MIT') { Add-CheckError 'wave-mcp 第三方许可声明不完整。' }
$wavePublicText = @(
    Get-Content -LiteralPath (Join-Path $waveIntegration 'README.md') -Raw -Encoding UTF8
    Get-Content -LiteralPath (Join-Path $waveIntegration 'tested-environment.json') -Raw -Encoding UTF8
) -join "`n"
if ($wavePublicText -match '(?i)[A-Z]:\\|/mnt/[a-z]/|C:\\Users\\|D:\\PDS') { Add-CheckError 'wave-mcp 公开文档或实测清单包含机器/项目绝对路径。' }

$allTextFiles = Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
    ($_.Extension -in @('.md','.toml','.json','.yaml','.yml','.ps1','.psd1','.py','.svg','.txt','.template','.bat','.do') -or
    ($_.Name -like 'LICENSE*') -or $_.Name -in @('VERSION','.gitignore','.gitattributes')) -and $_.FullName -ne $PSCommandPath
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

$validationKind = if ($NoRuntimeCanaries) { '静态包验证' } else { '完整包验证' }
Write-Host "$validationKind 通过：版本 $version；13 个角色（10 只读、3 条件写入）；2 个插件 Skill；46 个 FPGA Skill 文件、11 个 schema、6 个确定性工程脚本；GitHub marketplace、3 个部署/环境脚本、按需波形观察、UTF-8、隐私和公开内容检查全部通过。"
