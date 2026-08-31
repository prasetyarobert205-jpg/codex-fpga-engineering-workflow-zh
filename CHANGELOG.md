# 变更记录

版本遵循语义化版本。未执行的 EDA、DUT、CDC/STA、bitstream 和板级检查不因包版本发布而变成已验证。

## 1.3.0 - 2026-08-31

### 新增

- 私有故障库增加 `OFF / AFTERSALES_TRIAGE / FORMAL_REUSE` 三种查询模式；
- README 第 8 节增加按需触发、本机配置和跨部门分诊入口；
- 新增售后故障知识库文档，以及查询、转换和案例晋级三个中文提示词；
- 新增全合成 fault-library 正向、hard-negative、隐私和 mutation canary。

### 修复

- 收敛两套不一致的配置示例，生成 canonical `1.1.0` 禁用配置，同时兼容读取 v1.2.1 `library_root`；
- `REJECTED` 无条件排除，重复 case ID fail closed，`FORMAL_REUSE` 只返回证据完整的 `REUSABLE`；
- 增加 Trigger、Top-N 和输出范围检查；未授权 `OutputPath` 时只返回 stdout，不强制写项目文件；
- 查询输出改为固定白名单，不保存原始 query/filter、matched terms、源正文、路径或 hash；
- `REUSABLE` schema/脚本最低门统一要求根因、修复、verification、evidence、applicability、counterexample、独立复核和 board disposition。

### 隐私与边界

- 仓库只包含 `SYNTH_* / PUBLIC_SYNTHETIC` 测试数据，不包含真实售后 case、客户资料、本机路径、已填写 local config 或 review 报告；
- 公开包只提供转换提示词，不发布真实格式专用 importer；
- 历史匹配仍只是调查候选，不能替代当前工程证据或扩大任何修改权限。

## 1.2.1 - 2026-08-31

### 修复

- 修复 `setup-fpga-workflow` 在当前 Codex 插件会话中不可发现的问题；
- 将部署 Skill 恢复为正常自动发现，仍只在用户明确提出安装、部署、升级、检查或卸载请求时执行；
- Skill 被加载不构成写入授权，`WhatIf`、冲突拒绝、WSL/系统安装确认和全局路径保护保持不变。

### 证据

- `v1.2.0` 的 Marketplace、Plugin cache 和 `run-fpga-workflow` 已实际加载；
- `codex debug prompt-input` 证明 explicit-only 的 setup Skill 没有进入模型上下文，因此发布 1.2.1 补丁，而不移动旧 tag。

## 1.2.0 - 2026-08-30

### 新增

- 新增 repo marketplace，使 Codex CLI 可从 GitHub URL/`owner/repo@v1.2.0` 发现插件；
- 新增显式调用的 `$setup-fpga-workflow`，负责预览、安装、检查和卸载路由；
- 新增 `bootstrap.ps1`、`deployment-doctor.ps1` 和 `prepare-wave-environment.ps1`；
- 用户只需提供仓库地址和短提示词即可部署 13 个角色、两个 Skill，并检测或准备可选 wave-mcp venv；
- 支持复用精确版本的已有 venv、受限网络 wheelhouse、同一工具根互斥锁和 pip 超时分类；
- 可选合成 VCD→FST→wave-mcp smoke；doctor 会现场复核 Python 包版本和 converter SHA-256；
- 新增根级 `INSTALL_WITH_CODEX.md`，提供 marketplace 和无需 Plugin CLI 的两条安装路径。

### 安全边界

- 默认不覆盖不同内容，不安装全局 `AGENTS.md`，不使用 `-Force`；
- 默认只检测 WSL，不自动执行 `wsl --install`、sudo/apt、管理员操作或系统重启；
- wave-mcp 环境只写入用户选择的独立工具根，不修改全局 PATH、注册表或 ModelSim library mapping；
- WSL/Python/转换器缺失返回 `PARTIAL/USER_ACTION_REQUIRED`，不影响已成功的角色与 Skill 安装。

### 保持不变

- 仍是 13 个角色（10 个严格只读、3 个条件顺序写入），没有第 14 个 wave 角色；
- wave 工具仍只拥有 observed values，不拥有 expected、root cause 或 `SIMULATION_PASS`。

## 1.1.0 - 2026-08-30

### 新增

- 同步本机当前 FPGA 工作流的按需波形观察边界，但不新增平行角色；
- 新增中文 `waveform-observation` Skill reference 和用户文档；
- 新增 Tencent/wave-mcp 0.1.1 可选集成：公开 API point/range adapter、依赖锁定、脱敏环境模板、实测环境摘要和 MIT 许可；
- 增加一次性诊断与跨评审/功能接受证据的分层：前者可轻量查询，后者才要求 trusted runner、typed receipts 和包外 root identity；
- 增加 `waveform_consistency` 四态并保留 legacy-only `manual_waveform_consistent=true` 兼容。

### 修复

- 解除“所有 `SIMULATION_PASS` 都必须人工看波形”的旧过度约束；
- 新旧波形字段完全互斥，防止 `CONTRADICTORY/INCONCLUSIVE` 被 legacy 字段绕过；
- 统一 simulation evidence 的 canonical `proof_packets` 字段并加入正式 validator canary；
- 正式 validator 按 profile/classification 分层，最小 `DIAGNOSTIC_ONLY` 不再被功能 PASS 字段过度阻塞；
- wave-mcp receipt 绑定实际 FST SHA-256、校验窗口起点语义并记录直接依赖；GitHub CI 覆盖 Python/manifest/unit smoke；
- 明确 `COMPLETE`、`CROSS_REFERENCE_CONSISTENT`、GUI 可见和波形匹配均不能单独产生 `SIMULATION_PASS`。

### 边界

- 本版本不复制完整 wave-mcp 仓库、虚拟环境、二进制工具或本机绝对路径；
- 公开实测只覆盖一个 Xilinx/ModelSim/selected VCD→FST/wave-mcp 0.1.1 诊断链，不宣称三厂商、多格式或官方 IP 功能签核已验证；
- 13 个角色的名称、读写权限、单一产品写入者和独立审核边界保持不变。

## 1.0.1 - 2026-08-28

### 改进

- 重写根 README，先说明 FPGA 工程痛点和项目优势，再介绍安装与规则；
- 恢复完整 Mermaid 多角色协作流程图；
- 强化逐拍 RTL、验证独立、CDC/STA、官方 IP、物理实现和私有故障库的价值说明；
- 为 13 个角色增加“为什么有价值”的详细介绍；
- 扩充架构、项目优势和角色文档；
- 从面向用户的 README 和中文介绍中移除不需要的具体目录命名说明；
- 本次只更新对外文档与版本信息，不改变 13 个角色权限和 Skill 运行门禁。

## 1.0.0 - 2026-08-28

### 新增

- 建立独立全中文公开仓库；
- 同步本机实时 13 个 FPGA 角色的名称、读写权限和详细职责；
- 提供完整中文 `run-fpga-workflow` Skill、references、11 个 schema、6 个确定性 Skill 脚本、工程模板和三厂商 adapter 资产；
- 提供完整可选 `AGENTS.fpga.md` 门禁模板；
- 提供架构、优势、角色、安装、使用、证据安全、公开/私有边界中文文档；
- 提供 Xilinx/Pango/Anlogic fail-closed 厂商识别；
- 提供标准工程 scaffold、filelist、preflight、私有故障库查询接口；
- 提供中文 SVG 项目插图；
- 提供项目级和用户级安全安装、验证和卸载；
- 提供 GitHub Actions 包验证和 scaffold smoke。

### 安全边界

- 未发布本机 improvement evidence 历史、私人路径、客户/项目事实或售后原始文档；
- 公开仓库只包含空白改进账本和私有故障库 schema/config/query；
- 安装器默认拒绝覆盖不同内容，`AGENTS.md` 模板默认不安装；
- 角色权限保持 10 个严格只读、3 个条件顺序写入。
