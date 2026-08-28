# 项目优势

[中文导航](README.md) · [架构](architecture.md) · [角色](roles.md) · [使用](usage.md)

## 与“让 AI 写 Verilog”有什么不同

普通提示词常以“代码能生成、能编译”为完成标准。本项目把完成条件拆成多个不能互相冒充的证据层：源码审查、lint/elaboration、RTL 仿真、formal、CDC/RDC、综合、implementation/STA、仪器和板级结果。

它不会把：

- compile exit 0 写成“功能已通过”；
- 一段波形写成“CDC 安全”；
- bitstream 生成写成“可以安全上板”；
- 一份旧报告拿来签核新 diff；
- checker 与 DUT 同源仍叫“独立验证”。

## 与单一 Agent 有什么不同

单 Agent 同时设计、写代码、写测试、运行测试和宣布 PASS，容易产生确认偏差。本项目把写入和审核分开：

```text
架构与合同
→ 唯一产品实现者
→ 冻结 diff/hash
→ 专项只读审核
→ 验证作者产出原始结果
→ 独立仿真/逐拍审核
→ final reviewer 集成签核
```

reviewer 不改产品代码，作者不能关闭自己的 finding。

## 与“角色越多越好”有什么不同

13 个角色不是每次全部启动。普通路径诊断只需要 `DIAGNOSTIC_SMOKE`；一个局部接口不变小改可以 `QUICK`；CDC、官方 IP、寄存器、物理实现等风险才进入 `FULL` 和对应专项。未触发的功耗、formal、板级证据不会机械阻塞 compile/smoke。

## 与通用代码审查有什么不同

本工作流内建 FPGA 特有检查：

- NBA 旧值和同寄存器多赋值优先级；
- pipeline token、valid/data/sideband 对齐；
- backpressure payload 稳定；
- FIFO 同拍 push/pop、FWFT、满空边界；
- RAM read latency 和 read-during-write；
- CDC reconvergence、pulse visibility、reset release；
- constraint coverage 与结构正确性分开；
- 官方 IP source view 和跨 checkout 输出所有权；
- post-route logic/route/fanout/congestion 分类；
- ModelSim/Questa 真实 compile/load/run，而不是用其他 simulator 代替。

## 为什么不会无限拖慢大型工程

逐拍 reviewer 默认只接收一个主时钟域和一个 transaction impact cone。共享资源、跨域或无稳定边界时返回 `NEEDS_PARTITION`，由架构师重新分片。final reviewer 集成专项证据并抽样最高风险，不重复所有专项的全仓扫描。

## 为什么适合团队和长期项目

- 稳定 `project_identity` 减少重复发现；
- `current_task/task_delta` 让后续讨论跟随最新问题，而不是被首次身份卡锁死；
- findings ledger 保留稳定 ID，避免同一问题反复换名；
- 最多三轮自动修复，连续无进展就重建根因或停止；
- 私有故障库把真实售后经验变成候选线索，但必须在当前工程重新验证；
- 公开仓库不保存客户和项目事实。

## 适合哪些任务

- 读懂陌生 FPGA 工程；
- 最小修复 RTL/FSM/FIFO/pipeline；
- CDC/RDC 与复位问题；
- AXI-Stream、CSR、IRQ、DMA；
- 官方 Xilinx/Pango/Anlogic IP；
- Vivado/PDS/TD/ModelSim 脚本；
- 时序与布局布线收敛；
- 仿真假阳性和波形漏报；
- 安全上板计划和 ILA/SignalTap 观测设计；
- 发布结论的独立证据审核。
