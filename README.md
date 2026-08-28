# Codex FPGA 中文证据工程工作流

<div align="center">

![Codex FPGA 中文证据工程工作流](assets/hero.svg)

### 不是“让 AI 写一段能编译的 Verilog”，而是把 AI 放进真实 FPGA 工程流程

[![CI](https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh/actions/workflows/validate.yml/badge.svg)](https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh/actions/workflows/validate.yml)
[![MIT License](https://img.shields.io/badge/License-MIT-16a34a.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-2457c5.svg)](CHANGELOG.md)
[![中文](https://img.shields.io/badge/文档-简体中文-e11d48.svg)](docs/README.md)
[![FPGA](https://img.shields.io/badge/FPGA%20%2F%20SoC%20FPGA-工程工作流-7c3aed.svg)](docs/architecture.md)

**13 个专用角色 · 单一产品写入者 · 逐拍 RTL 推理 · 独立仿真审核 · CDC/RDC/STA · 官方 IP · 三厂商工具流 · 可双击 `run.bat`**

[60 秒开始](#60-秒开始) · [为什么值得使用](#这个项目的优势) · [架构](docs/architecture.md) · [角色](docs/roles.md) · [安装](docs/installation.md) · [提示词](docs/usage.md) · [证据与安全](docs/safety-and-evidence.md)

</div>

## 它解决什么问题

FPGA 的失败很少只存在于某一行 RTL。一个看似简单的修改，可能同时改变：

- 当前拍和下一拍的真实值；
- pipeline latency、throughput、valid/ready、stall/flush；
- FIFO 满空、同拍 push/pop、RAM 读延迟；
- reset release、CDC/RDC、脉冲丢失和多比特一致性；
- 约束覆盖、关键路径、布局距离、拥塞和扇出；
- 官方 IP 的工具版本、输出产品、仿真模型和 XDC；
- CSR、IRQ、DMA、固件 ABI 和错误恢复；
- 仿真 checker 是否只是“迎合 DUT”；
- `run.bat` 是否真的调用了用户需要的 Vivado/PDS/TD/ModelSim 流程。

通用代码 Agent 很容易生成“看起来合理”的 HDL，却没有回答这些工程问题。本工作流把 Codex 拆分为架构、实现、验证、CDC/时序、接口、厂商、板级、逐拍证据和独立终审角色，并把每个结论绑定到真实 snapshot 和证据层级。

> AI 可以更快地写代码，但只有工程合同、真实工具结果和独立审核，才能说明这段代码在目标器件、目标时钟和目标板卡上究竟证明了什么。

## 这个项目的优势

### 1. 一个产品写入者，多个独立监督者

不是让多个 Agent 同时修改同一 checkout。架构师先冻结合同，`fpga_engineer` 完成一个完整批次后冻结 diff/hash，相关 reviewer 并行只读复核，主会话合并一个 findings ledger，再由同一个实现者按稳定 finding ID 修复。

这样既能利用多角色视角，又避免多人抢写、循环修复和“审核者自己改完自己签”。

### 2. 真正按时钟拍理解 RTL

对 FSM、pipeline、valid/ready、FIFO/RAM、counter、reset/error recovery，不只做文本静态扫描，而是按：

```text
pre-edge
→ RHS/priority 读取旧值
→ NBA commit
→ post-edge
→ 组合稳定
→ 下一采样沿
```

跟踪 data、valid、ready、last、tag、error、stall、flush 和 in-flight token。大型工程按一个时钟域和一个 transaction impact cone 分片，超范围返回 `NEEDS_PARTITION`，不截断后声称审核完整。

### 3. 仿真不能给自己打分

验证资产作者可以写 TB、reference model、assertion 和 scoreboard，但不能独立签发自己资产的最终 `SIMULATION_PASS`。功能接受要求逐拍 due-cycle/window、scoreboard drain、X/Z policy 和至少一个能被 checker 捕获的 negative canary。

退出码 0、日志结束、`$stop` 或波形“看起来正常”都不能单独证明功能正确。

### 4. 流程严格度与声明匹配，不机械过度审核

| Profile | 证明什么 |
|---|---|
| `DIAGNOSTIC_SMOKE` | 路径、工具、compile、elaboration、有限运行 |
| `FUNCTIONAL_ACCEPTANCE` | 用仿真接受 DUT 功能 |
| `SPECIALIST_ACCEPTANCE` | formal、CDC/RDC、STA、电气或发布专项接受 |

compile/smoke 不自动触发完整 P&R、formal、功耗或 release；功耗默认 `NOT APPLICABLE`。只有当前声明依赖某种证据时，才启用对应门禁。

### 5. 官方 IP 有明确所有权和可复现路径

```text
当前 managed IP 且合同匹配
→ 复用

只缺 output products
→ 本机同版本官方工具增量生成

复制/旧 IP
→ 检查 source view 与 output ownership
→ staging/import 或官方重建

新 IP 且官方 Tcl/CLI 已确认
→ batch 生成

当前版本无法可靠脚本化
→ 官方 GUI 一次
→ 立即导出 recipe
```

互联网用于查同版本官方手册、参数和命令，不直接下载一个 XCI/IDF/IPC 当产品配置。

### 6. 物理实现从报告出发，不靠随机换 strategy 碰运气

只有 `IMPLEMENTATION_QOR` 或 `TIMING_CLOSURE` 才启用物理闭环：冻结 tool/part/source/constraint/seed/strategy，分类 logic depth、route delay、fanout、congestion、clocking、RAM/DSP/GT/IO 和 constraint 根因，一次改一个主变量，比较 WNS/TNS、hold、route status、资源和 runtime，改善才保留。

### 7. 正式工程目录和一键脚本可落地

新建或归一化工程使用：

```text
project/
project/par/
project/script/
simulation/
linter/
release/
codex_out/
```

禁止 `project2`、`par2`、`script2`。正式工程入口直接位于 `project/par/<name>.xpr|.pds|.al`。

用户入口：

```text
project\script\run.bat
simulation\script\run.bat
linter\script\run.bat
```

正式 BAT 使用 `%~dp0`、进程内 PATH、厂商原生 Tcl/DO/CLI 和真实退出码；不依赖 Codex 私有 `pwsh.exe`，不把本机绝对 `vivado.bat`、`vsim.exe` 写进公共模板。

### 8. Xilinx、Pango、Anlogic 三厂商边界清楚

根据 `.xpr/.xci`、`.pds/.idf`、`.al/带明确标记的 .ipc` 做简单 fail-closed 识别。冲突、未知或其他厂商停止并询问用户；一个正式工程只生成一个 adapter，不猜工具命令或库 recipe。

### 9. 能持续积累，但不会把猜测变成“经验”

工作流支持私有售后故障库：

```text
错误签名
→ 私有去标识案例候选
→ 当前工程重新核对
→ 根因/修复/验证闭环
→ 才能晋级复用
```

原始售后文档、客户信息和项目事实永远不进入公开仓库。公开包只提供 schema、配置模板和查询接口。

## 13 个角色

| 角色 | 核心责任 | 权限 |
|---|---|---|
| `fpga_architect` | 工程身份、动态任务、架构、预算、影响锥、验收和路由 | 只读 |
| `fpga_engineer` | RTL、官方 IP、构建流、物理实现、发布打包 | 唯一默认产品写入 |
| `verification_engineer` | TB、model、assertion、scoreboard、回归 | 验证资产顺序写入；不能自签 |
| `fpga_temporal_evidence_reviewer` | Shadow 逐拍与仿真证据审核 | 只读 |
| `fpga_cdc_timing_reviewer` | clock/reset、CDC/RDC、constraint、STA、QoR | 只读 |
| `fpga_interface_architect` | CSR、命令、IRQ、DMA、固件契约 | 只读 |
| `fpga_vendor_platform_reviewer` | Xilinx/Pango/Anlogic、原语、IP、wrapper、target | 只读 |
| `fpga_board_validation_engineer` | 安全上板步骤和仪器证据 | 只读 |
| `fpga_reviewer` | 独立集成终审 | 只读 |
| `system_architect` | 跨 FPGA/硬件/固件架构 | 条件只读 |
| `embedded_engineer` | FPGA 相关固件/驱动 | 条件顺序写入 |
| `hardware_datasheet` | 手册、电气、模型和页码证据 | 条件只读 |
| `independent_reviewer` | 跨领域或安全关键发布终审 | 条件只读 |

详细分工见[角色说明](docs/roles.md)。

## 60 秒开始

安装与脚手架需要 PowerShell 7；生成后的正式 `run.bat` 不依赖 Codex 私有 PowerShell。

```powershell
git clone https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh.git
cd codex-fpga-engineering-workflow-zh
pwsh -NoProfile -File .\scripts\validate-package.ps1
pwsh -NoProfile -File .\scripts\install.ps1 -Scope User -WhatIf
pwsh -NoProfile -File .\scripts\install.ps1 -Scope User
pwsh -NoProfile -File .\scripts\verify-install.ps1 -Scope User
```

安装后新开一个 Codex 会话，第一次只读使用：

```text
使用 $run-fpga-workflow，以 ANALYZE 模式只读检查当前 FPGA 工程。
自动识别厂商、工具版本、canonical 工程入口、top、时钟复位、正式 build/sim/lint 入口和未提交改动。
不要修改文件；结论区分 CONFIRMED、INFERRED、UNKNOWN；没有真实报告时标为 UNVERIFIED。
```

如果不想修改用户级配置，使用项目级安装：

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -Scope Project `
  -ProjectPath C:\path\to\your-fpga-project `
  -WhatIf
```

完整安装、冲突保护、备份和卸载见[安装指南](docs/installation.md)。

## 最小工程身份卡

用户通常只需要给出：

```text
工程根：
厂商/工具版本：UNKNOWN 时请自动查找
canonical .xpr/.pds/.al：UNKNOWN 时请自动查找
本次任务：
绝对不能修改：
```

后续问题通过 `task_delta` 更新，不必重复整张身份卡。

## 文档

| 文档 | 内容 |
|---|---|
| [中文导航](docs/README.md) | 所有文档入口 |
| [架构](docs/architecture.md) | 角色协作、工程身份、snapshot、生命周期和并行边界 |
| [项目优势](docs/advantages.md) | 与普通 AI 写 RTL、单 Agent 和纯 checklist 的差别 |
| [角色](docs/roles.md) | 13 个角色、权限和五种实现模式 |
| [安装](docs/installation.md) | User/Project scope、预览、备份、验证、升级、卸载 |
| [使用](docs/usage.md) | 可复制安装提示词、分析提示词和修改提示词 |
| [证据与安全](docs/safety-and-evidence.md) | 证据阶梯、声明边界、板级安全 |
| [公开与私有边界](docs/public-private-boundary.md) | 哪些可以进入 GitHub，哪些必须留在本机 |
| [能力等价范围](docs/capability-equivalence.md) | 与本机权限和能力一致的公开合同与允许差异 |

## 当前证据边界

仓库 CI 和 package validation 只能证明角色、Skill、schema、脚本语法、安装、工程 scaffold 和公开内容符合包合同；不能证明每个真实 EDA target、DUT 功能、CDC/RDC、STA、bitstream 或板卡已经通过。任何具体项目仍以当前源码、工具和报告为准。

## 参与

- 如果这个项目能减少一次 FPGA 现场偶发故障，请给仓库一个 Star；
- 在非机密真实工程中试用，并反馈它发现了什么、又漏掉了什么；
- 提交 Issue 说明角色缺口、工具兼容、误报或证据边界；
- 提交聚焦、可验证、不会削弱单写入和独立审核的改进。

[贡献指南](CONTRIBUTING.md) · [安全策略](SECURITY.md) · [MIT License](LICENSE)

---

<div align="center">

**让下一次 FPGA 修改，不只是“代码写完了”，而是“知道哪一拍发生了什么、哪份证据证明了什么”。**

[开始安装](docs/installation.md) · [复制提示词](docs/usage.md) · [查看角色](docs/roles.md) · [提交 Issue](https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh/issues)

</div>
