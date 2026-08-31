---
name: run-fpga-workflow
description: 面向明确的 FPGA/SoC FPGA 任务，运行证据驱动的需求、架构、RTL、官方 IP、CDC/RDC、时序、验证、厂商平台、物理实现和独立签核工作流；保持单一产品写入者、隔离输出、有限修复循环和可选逐拍 Shadow 审核。非 FPGA 任务不得触发。
---

# FPGA 证据驱动工程工作流

围绕一个冻结任务和一个集成 diff 协调专用 FPGA 角色。目标是得到可复现、可审查、可解释的工程证据，而不是最大化角色数量或检查数量。

## 授权、模式与声明边界

授权和风险是两件事。分析、诊断、评审、状态和计划默认只读；只有用户明确要求实现、修改、修复或构建时才进入写入阶段。

- `ANALYZE`：只读调查、架构或审核；不写文件。
- `QUICK`：用户已明确授权、局部、接口不变、单时钟域、低风险的小改。
- `FULL`：新 RTL、可观察时序、CDC/RDC、寄存器/IRQ/DMA、约束、厂商 IP、安全/能量输出、大型重构或范围不确定。

CDC/RDC、已发布寄存器、外部时序、厂商 IP/约束、安全输出或潜在数据丢失不得降级为 `QUICK`。`QUICK` 默认不调用 Shadow 逐拍审核。按任务类型读取[任务 profiles](references/task-profiles.md)。

选择能诚实支持当前结论的最小证据 profile：

- `DIAGNOSTIC_SMOKE`：定位路径/工具/库/编译问题，或证明 compile、elaboration 和有限运行；可以输出 `DIAGNOSTIC_ONLY`，但不能升级为 `SIMULATION_PASS`。
- `FUNCTIONAL_ACCEPTANCE`：仿真结果被用作 DUT 功能接受；要求独立 model/checker、scoreboard 排空、X/Z 策略、逐拍对齐和相关 negative canary。
- `SPECIALIST_ACCEPTANCE`：只启用当前声明需要的 formal、CDC/RDC、implementation/STA、电气或发布证据。

同时用一个 `claim_stage` 限定本轮声明：`PREFLIGHT`、`COMPILE`、`SIM_SMOKE`、`FUNCTIONAL_SIM`、`SYNTHESIS`、`IMPLEMENTATION_QOR`、`TIMING_CLOSURE`、`FORMAL`、`RELEASE`、`BOARD_PREP`。功耗默认 `NOT APPLICABLE`；只有用户明确要求，或真实功耗/热/安全/发布预算触发时才启用。

## 角色与写入权限

只调用任务合同确实需要的角色。

| 角色 | 责任 | 权限 |
|---|---|---|
| `fpga_architect` | 需求、工程身份、合同、影响锥、架构、预算、路由、验收 | 严格只读 |
| `fpga_engineer` | 产品 RTL、约束、平台 wrapper、官方 IP、构建流、物理实现、发布打包 | 唯一默认产品写入者 |
| `verification_engineer` | 验证计划、TB、model、assertion、scoreboard、回归 | 产品只读；验证资产顺序写入；不能自签 |
| `fpga_cdc_timing_reviewer` | 时钟/复位、CDC/RDC、约束、I/O 时序、STA、物理 QoR | 严格只读 |
| `fpga_interface_architect` | CSR、命令、IRQ、DMA、端序和固件契约 | 严格只读 |
| `fpga_vendor_platform_reviewer` | Xilinx/Pango/Anlogic 平台、原语、IP、target 和工具证据 | 严格只读 |
| `fpga_board_validation_engineer` | 电气和板级证据；物理动作由用户执行 | 严格只读 |
| `fpga_temporal_evidence_reviewer` | Shadow 逐拍与仿真证据复核 | 严格只读 |
| `fpga_reviewer` | 独立集成终审 | 严格只读 |
| `system_architect` | 条件性的跨 FPGA/硬件/固件架构 | 严格只读 |
| `hardware_datasheet` | 条件性的手册、电气、模型与页码证据 | 严格只读 |
| `independent_reviewer` | 条件性的跨领域或安全关键发布终审 | 严格只读 |
| `embedded_engineer` | 条件性的固件/驱动实现 | 顺序固件写入者 |

同一 checkout 绝不允许两个写入者并行。产品、固件和验证资产写入必须分批顺序执行；专项 reviewer 不修复自己的 finding，也不签核半完成代码。

## 核心流程

### 1. 建立项目事实

读取全部适用 `AGENTS.md`、需求、项目 SSOT、接口/寄存器唯一来源、相关 RTL/约束/TB/脚本、工具版本、报告和当前 diff。保留用户已有改动；事实分为 `CONFIRMED`、`INFERRED`、`UNKNOWN`，不得编造器件、引脚、电压、时钟/复位、寄存器、工具命令或结果。

用户提供身份卡或项目身份块时，读取[工程身份与动态任务](references/project-identity-and-task-delta.md)，把稳定 `project_identity` 与最新 `current_task/task_delta`、授权、长期保护项、requested claim 和 claim stage 分开。普通 follow-up 只刷新受影响 snapshot 和影响锥，不重复扫描整机。

需要 Codex 证据输出时，只写入 `<project-root>/codex_out/<run-id>/`。正式厂商 build 数据库/报告属于 `project/par`；正式 ModelSim/Questa 库、导出、日志和波形属于 `simulation/work`；正式发布产物属于 `release`。只有用户明确要求验证正式双击入口时，才串行运行那个 `run.bat`，不得绕过 BAT 后声称入口已验证。工程脚本工作读取[正式目录与一键工具流](references/project-layout-and-toolflow.md)。

### 2. 冻结合同与 snapshot

只创建当前任务确实需要的结构化工件。读取[工件合同](references/artifact-contracts.md)：

- `task-contract.json`
- `snapshot-manifest.json`
- `impact-manifest.json`
- `cycle-contract.json`（涉及可观察时序时）
- `verification-plan.json`（需要验证计划时）
- `ip-proof-packet.json`（涉及官方 IP 时）

所有报告、波形、finding 和 verdict 必须引用同一个 `snapshot_id`。源码、dirty diff、target、source list、define/include、parameter、constraint、工具视图或验证资产变化时，创建新 snapshot 并明确失效受影响证据。

### 3. 大工程分片

禁止 reviewer 盲目遍历大型仓库。索引只用于定位；逐拍审核限制为一个主时钟域和一个 transaction/dataflow impact cone，并包含反向 ready/backpressure 与所有耦合 sideband。

跨时钟域、共享 FIFO/RAM/仲裁、公共 package/macro/generate、未知黑盒、无稳定边界或上下文覆盖不足时返回 `NEEDS_PARTITION`，由架构师按 domain、transaction 或 shared resource 重新分片，再合并同一个 findings ledger。

### 4. 按需只读预审

- 功能和 checker：verification；
- 时钟/复位/CDC/RDC/Fmax/约束：CDC/timing；
- CSR/命令/IRQ/DMA：interface；
- IP/原语/target/脚本：vendor platform；
- 电气/手册/上板：board 或 datasheet。

主会话按证据解决冲突，不投票；输出一个统一实现合同。

### 5. 顺序实现

`ANALYZE` 跳过写入。`fpga_engineer` 是默认唯一产品写入者，每个批次只能激活一个主模式：

- `RTL_IMPLEMENTATION`
- `IP_INTEGRATION`
- `BUILD_FLOW`
- `PHYSICAL_IMPLEMENTATION`
- `RELEASE_PACKAGING`

每完成一个模块、影响锥、IP、时钟域或工具流批次，就冻结 diff/hash checkpoint；相关 reviewer 在同一 snapshot 上并行只读复核，主会话合并 findings，唯一实现者按稳定 finding ID 修复。IP 工作读取[官方 IP 集成](references/ip-integration.md)；只有 implementation QoR/时序闭合读取[物理实现闭环](references/physical-implementation.md)。

用户明确要求最小源码修改时，写入前先简短推演：根因、为何改此处、为何不扩大、接口/周期/时钟复位/错误语义是否变化、最小验证。只有可能改变已发布接口、latency、throughput、clock/reset/CDC、error 或安全行为时才暂停请求确认。

### 6. 确定性工具流与故障归属

只运行项目已确认的命令。正式入口为：

```text
project/script/run.bat [compile|build|clean]
simulation/script/run.bat [case] [gui|batch] [seed]
linter/script/run.bat [all|verilator|svlint]
```

正式 BAT 使用 `%~dp0`、路径引用、进程内 PATH、厂商原生 Tcl/DO/CLI 和真实退出码；不得依赖只在 Codex 进程可见的 `pwsh.exe`，不得写死某台机器的 `vivado.bat`、`vsim.exe`，不得修改全局 PATH、注册表或仿真库映射。`simulation/script` 默认只保留 `run.bat`、`setting.txt`、`src_list.txt`、`vsim.do`；生成导出、`modelsim.ini`、`.Xil`、库、日志和波形归 `simulation/work`。

正式归一化工程入口必须直接位于 `project/par/<project-name>.xpr|.pds|.al`，禁止额外 `par/vivado_project`、`par/build` 或随机容器。ModelSim/Questa 接受证据必须显示真实 compile、load/elaboration、run；XSim 不能替代。

先分类失败：`DUT_FAIL`、`TESTBENCH_FAIL`、`REFERENCE_MODEL_FAIL`、`ASSERTION_FAIL`、`SCRIPT_PATH_FAIL`、`COMPILE_ELAB_FAIL`、`TOOL_ENV_FAIL`、`VENDOR_LIBRARY_FAIL`、`BUILD_SCRIPT_FAIL`、`CONSTRAINT_STA_FAIL`、`TIMEOUT_HANG`、`INCONCLUSIVE`。只有 `DUT_FAIL` 直接路由产品 RTL。

厂商检测保持简单且 fail closed：Xilinx `.xpr/.xci`，Pango `.pds/.idf`，Anlogic `.al` 或带明确标记的 `.ipc`。冲突、未知或其他厂商停止并提示用户；正式工程一次只物化一个 adapter。库只允许使用准确版本的官方源和已验证 recipe，否则返回 `MISSING_VENDOR_LIBRARY`。

### 7. 仿真证据

验证资产作者报告原始结果但不能自签。功能接受读取[仿真证据与独立接受](references/simulation-evidence.md)。`SIMULATION_PASS` 要求需求追踪、独立 model/checker、逐拍 due cycle/window、scoreboard 排空、X/Z 策略、正确 compile/elaboration/run、完整 case/seed/tool 和被拒绝的相关 negative canary。波形不适用时可以明确记录 `NOT_APPLICABLE`；适用时必须与 checker/model 证据一致。日志结束、`$stop`、退出码 0、GUI 可见或波形“看起来正常”均不足。

当前请求或 verification plan 需要波形证据时，读取[按需、有界的波形观察](references/waveform-observation.md)。一次性 `DIAGNOSTIC_ONLY` 可以使用项目已有可追溯查询路径；只有波形证据要跨评审复用、进入 `FUNCTIONAL_ACCEPTANCE` 或支持正式签核时，才要求 typed trusted runner、完整执行工件图和包外冻结 root identity。机器专属的 wave-mcp、Python/WSL、转换器和绝对路径留在本地配置，不固化进共享 Skill。

### 8. Shadow 逐拍审核

`fpga_temporal_evidence_reviewer` 初始为 Shadow，只在 `STATIC_CYCLE`、`SIMULATION_EVIDENCE` 或 `COMBINED` 模式审核限定影响锥；不修改文件、不指导修复、不替代 CDC/STA、不签发整体 PASS。按 `pre-edge → RHS/priority → NBA commit → post-edge → combinational settle → next sampling edge` 推导，读取[逐拍证据审核](references/temporal-evidence-review.md)。

### 9. Finding 与有限收敛

`codex_out/<run-id>/review/findings-ledger.json` 使用稳定 ID，不用行号作为身份。writer 只能标记 `FIXED_PENDING_REVIEW`，不能自关 `VERIFIED_CLOSED`；冲突标记 `DISPUTED`。

最多三轮自动修复—复审：第一次无进展停止盲改并重建根因；连续两轮无进展停止；第三轮仍有 BLOCKER/HIGH 则停止。MEDIUM/LOW 默认不触发自动循环。

### 10. 集成终审

相关专项审核完成后，最后运行独立 `fpga_reviewer`。终审集成 task contract、claim stage、snapshot、专项报告、未关闭 BLOCKER/HIGH、冲突和声明边界；已有专项证据时抽样最高风险，不重复全部专项。最终 verdict 仅为 `PASS`、`PASS WITH CONDITIONS`、`FAIL`；未运行保持 `NOT RUN/UNVERIFIED`。

### 11. 私有故障库

私有故障库默认 `OFF`。只有用户明确提出售后/现场故障、跨部门归属未知、首次修复无进展后重建根因，或失败签名改变时，才选择 `AFTERSALES_TRIAGE`；普通开发、评审/签核和根因已冻结的实现阶段默认不查历史。`FORMAL_REUSE` 只返回 `REUSABLE`。

使用 `scripts/find-fpga-fault-case.ps1` 和[私有故障库规则](references/private-fault-library.md)。配置缺失、禁用、路径无效或格式不兼容时 fail closed，不猜路径或扫描磁盘。`REJECTED` 永不返回；最多输出 3～5 个去标识候选，不保存原始 query/filter、源正文、路径或 hash。匹配只是调查候选，必须用当前 target、版本、clock/reset、接口、IP mode、trigger、日志和报告重新验证。原始售后文档、客户信息和项目事实不得进入本 Skill、Memory、公开仓库或普通项目文档。

### 12. 轻量持续改进

核心验证和必要签核后做一次轻量改进审计，不扩大当前任务。只接纳用户明确规则、真实失败/修复、实际验证、独立复核或带版本官方资料。项目事实留项目 SSOT；可复用工作流进入 Skill；全局硬门禁进入用户 `AGENTS.md`；密钥、客户/项目事实和历史“已通过”状态禁止持久化。使用[公开空白改进账本](references/improvement-evidence.md)。

## 最小路由

- `ANALYZE`：architect → 必要只读专项；仅在用户要求签核 verdict 时调用 final reviewer。
- `QUICK`：architect → FPGA writer → verification review → final reviewer；Shadow 默认关闭。
- `FULL`：architect 与稳定工件 → 必要专项并行预审 → 顺序 writers → 隔离验证 → 受影响专项复审 → 可选 Shadow → final reviewer → 必要时跨领域 reviewer。

## 最终报告

报告模式和范围、事实/假设/未知项、冻结 snapshot、角色及结论、各写入批次文件、行为/latency/throughput、clock/reset/CDC/RDC、register/IRQ/DMA、vendor/target、精确命令和证据、失败分类、findings 状态、独立 verdict、未验证项、剩余风险、板级用户动作，以及任何持久工作流变更和回滚点。
