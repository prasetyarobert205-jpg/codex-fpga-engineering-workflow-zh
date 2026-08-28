# 逐拍时序证据审核

非平凡同步 RTL、FSM、pipeline、valid/ready、FIFO、RAM、counter、reset release 或仿真时序声明时读取。

## 先限定范围

审核一个主时钟域和一个 transaction/dataflow impact cone。从最近的未修改、合同明确输入边界或寄存器开始，在最近的未修改、合同明确输出边界或寄存器结束。

必须包含 payload 和全部耦合 control/sideband：valid、ready、last、keep、id、tag、user、error、enable、stall、flush、abort、reset、FIFO/RAM status、FSM、counter、timeout 和反向 backpressure。

出现以下情况返回 `NEEDS_PARTITION`，不得静默截断：

- impact cone 跨时钟域；
- shared FIFO/RAM/仲裁或全局 reset/enable 逃逸；
- package、macro、function、generate、parameter 或 black-box 行为未解析；
- 找不到稳定合同边界；
- 当前上下文无法覆盖整个 cone。

CDC 分别输出 source-domain 和 destination-domain 表；crossing structure 和约束由 CDC reviewer 签核。

## 时钟沿语义

每个相关边沿按以下顺序推导：

1. `Pre-edge`：当前寄存器和稳定输入；
2. `RHS/Priority`：事件条件、赋值优先级和 NBA RHS，全部读取 pre-edge 旧值；
3. `NBA Commit`：解析全部 active assignment 后的 next register；
4. `Post-edge`：新寄存器值；
5. `Combinational Settle`：delta cycle 后的稳定输出；
6. `Next Sampling Edge`：真正观察该值的下游采样沿。

固定表：

| Domain | Edge | Reset | Pre-edge State | Inputs | Event | RHS/Priority | NBA Next | Post-edge State | Stable Output | Token/Stage |
|---|---|---|---|---|---|---|---|---|---|---|

## 必查场景

- reset assertion、release 和首个 accepted item；
- first、steady-state、last transaction；
- pipeline fill、bubble、stall、resume、flush、drain；
- 同时条件和一个寄存器多次赋值；
- counter `N-1/N/N+1` 和 wrap；
- backpressure 时 payload/metadata 稳定；
- FIFO 同拍 push/pop、empty/full/count、wrap、FWFT 与 registered output；
- RAM read latency、output register、byte enable 和文档化 read-during-write mode；
- timeout、abort、error injection 和 recovery。

仿真波形只证明实际执行的 stimulus、seed、snapshot 和配置；不能替代逐沿推理、checker 独立性、CDC/RDC 或 STA。
