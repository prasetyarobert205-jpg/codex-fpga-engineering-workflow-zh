# 最简使用与提示词

[中文导航](README.md) · [安装](installation.md) · [架构](architecture.md) · [角色](roles.md)

## 把仓库地址交给 Codex 部署

```text
请从这个仓库的 v1.2.0 安装中文 FPGA 工作流：
https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh

用户级部署 13 个 FPGA 角色和 Skill；已有可用 WSL/Python 时用 WaveMode=Prepare 准备 wave-mcp 环境。先做 WhatIf；安装系统组件、覆盖已有不同文件、写入全局 AGENTS.md 或修改全局 PATH 前必须先问我。
```

安装插件后也可以明确调用：

```text
使用 $setup-fpga-workflow，用户级部署角色和 Skill；WaveMode=Detect，不自动安装 WSL。
```

## 安装后最简单的一句话

```text
使用 $run-fpga-workflow，以 ANALYZE 模式只读检查当前 FPGA 工程；自动识别厂商、工具版本、工程入口、top、时钟复位、脚本和当前问题，不修改文件，不猜测缺失信息。
```

用户不需要手工指定 13 个角色；Skill 会按任务路由必要角色。

## 第一次进入工程的推荐提示词

```text
使用 $run-fpga-workflow，以 ANALYZE 模式进入这个 FPGA 工程。

工程根：C:\我的工程
厂商/工具版本：UNKNOWN 时请自动查找
canonical .xpr/.pds/.al：UNKNOWN 时请自动查找

本次任务：先只读了解工程和当前问题。
绝对不能修改：任何文件。

自动识别 product top、simulation top、clock/reset、正式 build/sim/lint 入口和未提交改动。
结论区分 CONFIRMED、INFERRED、UNKNOWN；没有当前报告时标为 UNVERIFIED。
最后只告诉我最关键的未知项和下一步。
```

## 最小修改提示词

```text
使用 $run-fpga-workflow。

工程根：C:\我的工程
任务：修复 [问题描述]
允许：只修改与根因直接相关的 RTL 和必要测试文件
禁止：不改接口、不改寄存器、不重生成 IP、不改时钟频率、不改变 latency、不生成 bitstream
成功标准：通过工程已有的相关仿真用例

先根据源码做简短修改推演：根因、为什么改这个位置、为什么不扩大、对 latency/throughput/clock/reset/CDC/error 的影响和最小验证；然后直接实施最小修改。
未运行的综合、STA、CDC/RDC 和上板结果标为 UNVERIFIED。
```

## 正式 `run.bat` 诊断

```text
使用 $run-fpga-workflow，profile=DIAGNOSTIC_SMOKE，claim_stage=COMPILE。
只诊断 project/script/run.bat 的路径、工具、IP、filelist、compile 和退出码。
必须通过该 BAT 本身运行，不得绕过入口；不要修改产品 RTL，不跑 P&R、功耗或 release。
```

## 功能仿真接受

```text
使用 $run-fpga-workflow，profile=FUNCTIONAL_ACCEPTANCE，claim_stage=FUNCTIONAL_SIM。
按真实 accepted edge 建立 cycle-indexed scoreboard，检查 latency、early/late/drop/duplicate/reorder、data 和 sideband；scoreboard 必须排空，定义 X/Z policy，并证明相关 negative canary 会被 checker 拒绝。验证资产作者不能自签。
```

## 波形首差异诊断

```text
使用 $run-fpga-workflow，profile=DIAGNOSTIC_SMOKE，claim_stage=SIM_SMOKE。
当前 checker/log 在 [时间/周期/transaction] 首次失败。根据需求、TB/checker 和影响锥，只读取 first failure 前后必要的 clock/reset/data/valid/ready/sideband/FIFO/FSM/error 信号。
波形工具只提供 observed，不生成 expected 或 root cause；记录波形 hash、工具版本、查询窗口、cap、退出状态和限制。一次性诊断不强制建设完整 trusted runner。
```

## 可跨评审复用的波形证据

```text
使用 $run-fpga-workflow，把当前关键 case 的波形证据交给 temporal/final reviewer 重放。
使用项目级 trusted runner 记录 simulator/converter/query 的真实 argv/cwd/exit、snapshot/case/seed、stage inputs/outputs、required queries 和工件 hash；把 root identity 保存在 bundle 外。
即使查询 COMPLETE，也不得签 SIMULATION_PASS，除非独立 model/checker、scoreboard、X/Z、negative canary 和其他功能接受条件全部满足。
```

## 官方 IP

```text
使用 $run-fpga-workflow，FULL / IP_INTEGRATION。
确认本机厂商工具版本、part、现有 managed IP、端口/参数/latency/reset 契约。
依次考虑复用、增量生成、staging/import、官方 Tcl/CLI、官方 GUI 一次性兜底并导出 recipe。
不要从网上复制 XCI/IDF/IPC，不使用近似 primitive model。
```

## CDC/RDC

```text
使用 $run-fpga-workflow，以 ANALYZE 模式审核这个 CDC/RDC 问题。
分别说明 source/destination clock 和 reset，识别 crossing 类型、同步结构、reconvergence、reset release、约束和 timing coverage。
异步 FIFO 的结构证据与 STA/约束覆盖分开报告；缺少约束不等于 RTL 一定错误。
```

## 物理实现和时序

```text
使用 $run-fpga-workflow，claim_stage=TIMING_CLOSURE，主模式 PHYSICAL_IMPLEMENTATION。
冻结 tool/version、part、源码、约束、seed、strategy 和 baseline 报告。
分类最高影响路径为 logic、route、fanout、congestion、clocking、RAM/DSP/GT/IO 或 constraint；一次只改变一个主变量，重跑并比较 WNS/TNS/hold/route status/resources/runtime，改善才保留。
不要默认换 seed、全局 Pblock 或盲目插拍。
```

## 代码评审

```text
使用 $run-fpga-workflow，只读评审当前 FPGA diff。
先列 findings，按 BLOCKER/HIGH/MEDIUM/LOW 排序；每项包含文件、行号、触发条件、逐拍影响和建议修复。
重点检查 data/valid/sideband 对齐、NBA 旧值、FIFO/RAM 边界、CDC/RDC、constraint、官方 IP 和验证独立性。
不要修改文件。
```

## 后续对话不需要重复身份卡

工程根、canonical entry、part、top 和工具版本未变时，用户直接说新任务即可：

```text
继续使用当前工程身份。上一任务结束；新任务是只读定位 simulation/script/run.bat 为什么没有进入 ModelSim。不要改 RTL。
```

Skill 应生成 `task_delta=SUPERSEDES` 或对应关系，只刷新相关脚本和证据。
