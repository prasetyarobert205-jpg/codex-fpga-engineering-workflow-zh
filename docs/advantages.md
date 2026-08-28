# 项目优势

[中文导航](README.md) · [整体架构](architecture.md) · [角色](roles.md) · [使用](usage.md)

## 一句话优势

这套工作流的核心优势不是“角色更多”，而是让 AI 在 FPGA 工程中遵守真实的时序语义、专业分工、证据边界和独立审核。

## 与普通 AI 写 RTL 的区别

| 普通 AI 辅助方式 | 本工作流 |
|---|---|
| 根据局部代码直接生成修改 | 先建立工程事实、任务合同和影响锥 |
| 一个 Agent 同时设计、实现、测试和宣布 PASS | 作者、专项 reviewer 和 final reviewer 分离 |
| 只关注语法和 compile | 关注逐拍语义、接口对齐、CDC/RDC、constraint 和真实工具证据 |
| 仿真退出码 0 就认为通过 | 功能接受要求独立 model/checker、scoreboard drain 和 negative canary |
| 全仓扫描或只看局部片段 | 大工程按 clock domain 和 transaction cone 分片 |
| 厂商 IP 和命令靠经验猜 | 使用当前版本官方工具、手册和可复现 recipe |
| P&R 不好就换 seed/strategy | 冻结基线、分类根因、一次改一个变量、比较后保留或回滚 |
| 历史报错相似就套修复 | 故障库只提供候选，必须在当前工程重新验证 |

## 优势一：真正按时钟拍理解 RTL

FPGA 问题经常来自“代码读起来没错，但实际在另一拍发生”。工作流要求按：

```text
pre-edge
→ 旧值 RHS/priority
→ NBA commit
→ post-edge
→ 组合稳定
→ 下一采样沿
```

检查 pipeline token、data/valid/sideband、stall/flush、FIFO/RAM、FSM、counter、reset release 和 first/last transaction。这是普通代码审查最容易缺失的能力。

## 优势二：多个角色监督，但只有一个产品实现者

多角色只读分析可以并行，产品源码写入保持顺序和唯一。每个批次冻结 diff/hash，所有 reviewer 审核同一 snapshot，finding 统一合并后再由同一实现者修复。

这样减少：

- 多 Agent 相互覆盖；
- 反复循环修改；
- 审核基线不一致；
- reviewer 自己修、自己签；
- 工具流问题误改 RTL。

## 优势三：验证资产也需要被审核

验证工程师负责 TB、model、checker、assertion 和 scoreboard，但不能独立签发自己的最终 `SIMULATION_PASS`。

功能接受会检查：

- model 是否独立于 DUT；
- accepted edge 和 due cycle/window；
- early/late/drop/duplicate/reorder；
- data 与 metadata 对齐；
- scoreboard 是否排空；
- X/Z policy；
- checker 是否能抓住 negative canary；
- 人工波形是否与自动结论一致。

这直接针对“自动仿真说正确，人工看波形却发现错误”的常见问题。

## 优势四：CDC 结构、约束和 STA 分开判断

工作流不会把缺少约束直接等同于 RTL 一定错误，也不会用 false path 掩盖结构问题。

它分别检查：

```text
跨域结构是否正确
时钟和复位关系是否明确
同步器/FIFO/handshake 语义是否匹配
约束是否覆盖真实路径
STA 是否对当前 snapshot 有效
```

因此可以更准确地区分 `DUT_FAIL`、constraint coverage 缺口和工具环境问题。

## 优势五：官方 IP 有明确责任人和证据路径

官方 IP 不是“工具能生成就算完成”。工作流还检查：

- vendor、tool/version、part；
- IP identity、port、width、parameter；
- latency、reset、busy、FIFO/RAM mode；
- output products、OOC、constraint；
- simulation model/library、define/include；
- source view 与 output ownership；
- close/reopen 后是否仍为 managed IP；
- upgrade delta。

联网资料用于查官方证据，不直接复制产品 IP 配置。

## 优势六：时序和布局布线优化可复现

物理实现只在实际 claim 和报告需要时启用。它先冻结 baseline，再判断问题来自 logic、route、fanout、congestion、clocking、RAM/DSP/GT/IO placement 或 constraint；一次修改一个主变量并比较结果。

这比不断更换 strategy、随机加 Pblock 或盲目插拍更容易复现和回滚。

## 优势七：专业但不过度

三种 evidence profile 让流程跟随结论用途：

- `DIAGNOSTIC_SMOKE`：只证明工具、compile、elaboration 或有限运行；
- `FUNCTIONAL_ACCEPTANCE`：仿真用于正式功能接受；
- `SPECIALIST_ACCEPTANCE`：只启用当前声明需要的专业证据。

未触发的 formal、P&R、功耗和板级检查不会机械阻塞小任务。功耗默认 `NOT APPLICABLE`。

## 优势八：大型工程有范围控制

逐拍 reviewer 默认只审核一个主时钟域和一个 transaction impact cone；跨域、共享资源或无稳定边界时返回 `NEEDS_PARTITION`，而不是无限扫描或截断后声称完整。

final reviewer 集成专项证据并抽样最高风险，不重复每个专项的全部工作。

## 优势九：能够积累真实经验，但不会把猜测固化

私有故障库支持把售后问题整理为：症状、trigger、根因、失败尝试、修复原则、验证、适用范围和反例。

只有根因和修复验证闭环的案例才能成为候选经验；每次仍需在当前工程重新验证。客户和项目原始资料不进入公开仓库。

## 适合的工程场景

- 读懂大型陌生 FPGA 工程；
- 最小修复 RTL/FSM/FIFO/RAM/pipeline；
- CDC/RDC 与 reset release；
- AXI-Stream、CSR、IRQ、DMA；
- Xilinx/Pango/Anlogic 官方 IP；
- Vivado/PDS/TD/ModelSim 工具流；
- 仿真假阳性、checker 漏报和波形错位；
- WNS/TNS、拥塞、高扇出和物理实现；
- ILA/SignalTap、示波器和安全上板计划；
- 需要独立发布结论的长期项目。
