# AI 按需读取 FPGA 波形

本工作流可以把波形作为 AI 辅助验证的 observed evidence，但不会把波形工具当成 expected oracle 或功能签核器。

## 解决什么问题

传统 AI 仿真辅助常见两种错误：

1. 只看到日志结束或退出码 0，就宣布功能通过；
2. 从头遍历大型波形，既慢又容易把无关信号解释成根因。

本工作流改为：

```text
需求 / 独立 model -> expected
checker            -> expected vs observed comparison
波形工具           -> selected observed values
temporal reviewer  -> 有证据的 INFERRED / UNKNOWN 因果
final reviewer     -> 最终结论
```

波形工具只能回答“冻结波形中实际记录了什么”，不能单独回答“设计是否满足需求”。

## 什么时候读取波形

默认不启用。以下场景才启用：

- 用户明确要求看波形；
- checker/log/assertion 出现矛盾；
- 需要定位 first failure；
- 关键/最终 case 需要人工 GUI 复核。

普通 compile smoke、路径错误、工具缺失和纯 RTL 解释不需要波形。

## 完整导出还是选择性导出

两种方式并不冲突：

- 小型关键 case：可以保留完整 WLF/VCD/FST，方便事后重放；AI 仍选择性读取信号和窗口。
- 大型长回归：优先在仿真阶段记录相关层级，或在 first failure 后重跑并扩大影响锥，避免生成和遍历无界波形。

查询计划来自：需求、TB/checker、当前 diff、first-failure、时钟域和 transaction impact cone。不要设置脱离项目的全局固定 signal/window/cap。

## wave-mcp 可选集成

[Tencent/wave-mcp](https://github.com/Tencent/wave-mcp) 是 MIT 许可的 RTL 波形调试 MCP Server。它读取 FST，并可结合 SystemVerilog 源码做层次、信号、值和静态连接分析；它不运行仿真器。

本仓库没有复制完整 wave-mcp 源码，只提供：

- 一个基于公开 API 的最小 point/range 查询 adapter；
- 可移植环境模板；
- 已脱敏的实测环境记录；
- 依赖版本与第三方许可声明。

目录见 [`integrations/wave-mcp/`](../integrations/wave-mcp/README.md)。

## 本机实测提取范围

公开记录来自一次项目级 `DIAGNOSTIC_SMOKE`，只保留去项目化能力结论：

```text
host path     : Windows -> WSL2 Ubuntu
Python        : 3.13.6
wave-mcp      : 0.1.1
direct deps   : mcp 2.1.1 / pylibfst 0.2.1 / pyslang 11.0.0
wave format   : selected ModelSim VCD -> FST
query surface : open/close session, signal_info,
                signal_value_at, signal_values_in_range
```

实测点查询与 0–200000ps 范围内的标量 clock 查询，共 53 条记录，与独立 VCD 解析逐条一致。该证据只证明这条诊断查询链，不证明 DUT 功能、三厂商、其他格式、官方 IP 或板级行为。

## C+1 与起始值

当 backend 没有可靠 truncation 标志时，请求 `C+1` 条：

```text
0..C 条  -> 可在 receipt 检查后视为完整
C+1 条   -> INCONCLUSIVE / QUERY_RESULT_TRUNCATED_OR_OVER_BUDGET
```

range API 不一定返回窗口起点的保持值。需要起始状态时同时执行：

```text
point(start)
+
range(start, end)
```

并记录同一 timestamp 更新的边界语义。

当前最小 adapter 按 wave-mcp 0.1.1 的公开语义处理起点：`point(start)` 是 start 时刻最后一次已生效的值，range 包含 `[start,end]` 内的变化；若 range 在 start 同时刻的最后一项与 point 不一致、point 缺值、位宽/四态值非法或时间倒序，则返回 `INCONCLUSIVE`，不能标为 `COMPLETE`。

## 功能接受边界

以下信息仍然不能单独产生 `SIMULATION_PASS`：

- wave-mcp 返回 `COMPLETE`；
- VCD 与 FST 查询一致；
- GUI 看起来正常；
- 仿真器退出码为 0；
- TB 打印 PASS marker。

功能接受仍需要 requirement、独立 model/checker、逐拍 comparison、scoreboard drain、X/Z policy、negative canary、正确工具退出和独立终审。

波形不适用时，使用：

```json
{"waveform_consistency": "NOT_APPLICABLE"}
```

波形被依赖且一致时使用：

```json
{"waveform_consistency": "CONSISTENT"}
```

`CONTRADICTORY` 或 `INCONCLUSIVE` 不能支持功能 PASS。

## 官方 IP

FST/VCD 只是容器。若 expected 依赖 FIFO/RAM/PLL 等官方 IP 的 mode、latency、reset 或 busy 语义，必须确认当前 XCI/IDF/IPC、当前工具版本和官方仿真模型。项目行为模型只能支持标明范围的诊断，不能冒充官方模型签核。

## GUI

内部快速验证默认 batch，不自动打开 GUI。用户要求或关键/最终 case 时再打开原生 simulator GUI。进程启动、窗口可见和用户确认分别记录，并且都不能改变功能 verdict。
