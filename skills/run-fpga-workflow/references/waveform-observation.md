# 按需、有界的波形观察

只在波形证据确实能支持当前仿真结论时启用。本能力属于现有 `DIAGNOSTIC_SMOKE` 或 `FUNCTIONAL_ACCEPTANCE` 中的可选证据分区，不是第四种 profile，也不是所有仿真的通用硬门。

## 触发条件

以下任一条件成立时可以启用：

- 用户或 verification plan 明确要求波形证据；
- 当前 checker/log/assertion 矛盾需要定位；
- first-failure 的时间、周期或 transaction 需要局部因果窗口；
- 关键/最终 case 需要人工 GUI 复核。

否则标记为 `NOT_APPLICABLE`，继续当前适用任务。波形、转换器或查询 adapter 不可用时返回 `INCONCLUSIVE` 或真实工具环境分类，不能自动归为 `DUT_FAIL`。

## 所有权边界

```text
需求 / 独立 model    -> expected
波形观察             -> observed + receipts
checker              -> comparison
temporal reviewer    -> INFERRED / UNKNOWN 因果
final reviewer       -> 集成 verdict
```

波形 probe 不得输出 expected、确认 root cause、`DUT_PASS` 或 `SIMULATION_PASS`。

## 查询计划

required signal/window 应来自需求、TB/checker、当前 diff、first-failure 和 transaction impact cone；若 backpressure、ready、sideband 会影响接受，也必须进入影响锥。保留绝对时间和 clock identity，不能把无关时钟域事件强行换算成同一 cycle index。

大型回归从可信 first-failure anchor 开始，只扩展相关窗口。小型关键 case 可以保留完整原生波形，但 AI 仍只读取必要信号和窗口。信号数量、位宽、窗口、transition 与输出大小属于当前项目/case 资源预算，不在公开 Skill 中设固定值。

当 backend 没有可靠截断标志且 range 完整性重要时，使用 `C+1`：返回 `0..C` 条在 receipt 检查后可以视为完整，返回 `C+1` 条必须为 `INCONCLUSIVE / QUERY_RESULT_TRUNCATED_OR_OVER_BUDGET`。需要窗口起始保持值时，单独查询 `point(start)`，并记录同时间更新的边界语义。

## 可信执行边界

一次性 `DIAGNOSTIC_ONLY` 可以直接使用项目已有可追溯查询路径，但至少记录 snapshot、case/seed、工具/版本、命令/退出码、输入波形 hash、查询窗口和限制。

当波形证据需要跨评审复用、长期保存、进入 `FUNCTIONAL_ACCEPTANCE` 或支持正式签核时，使用项目级 trusted runner 绑定：

- snapshot、case、seed、top、source/define/parameter 视图；
- simulator/converter/query 工具身份、argv、cwd 和退出语义；
- stage inputs/outputs、波形与 query/result 内容 hash；
- required query 完成情况和项目资源预算；
- bundle 外独立冻结的 root identity，或等价不可自签证据。

优先使用按用途分开的 typed receipts，不建设一个无边界的万能 validator。`DIAGNOSTIC_CHAIN_COMPLETE`、`COMPLETE` 或 `CROSS_REFERENCE_CONSISTENT` 只证明所声明的执行/观察分区，不会提升 evidence profile。

## 厂商 IP 与模型

若 observed 或 expected 行为依赖厂商 IP，必须使用当前工程、当前工具版本和当前配置对应的官方仿真模型来确认 mode、latency、reset 和 flow-control。项目行为近似模型可以支持明确限定的诊断 smoke，但其结果不能自动继承到官方 IP 功能接受。

## GUI sidecar

用户或计划要求关键/最终 case 人工复核时，打开配置的 simulator GUI。进程启动、窗口可见和用户确认分别记录；GUI 状态不能改变 compile、batch、checker 或功能 verdict。

## 本地环境

wave-mcp 源码、Python/WSL 环境、转换器和机器路径保存在用户控制的本地工具目录或项目配置中；每次 evidence run 重新记录版本和实现 hash。不得把完整第三方仓库、虚拟环境、绝对路径或全局 PATH/library mapping 打包进本 Skill。
