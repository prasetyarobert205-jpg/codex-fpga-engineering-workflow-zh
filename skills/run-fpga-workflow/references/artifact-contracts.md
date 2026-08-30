# 结构化工件合同

只在信息与当前任务相关时创建这些工件。实例放在 `codex_out/<run-id>/`，schema 位于 `references/schemas/`。工件用于组织和追踪证据，不能替代源码、elaboration、仿真、CDC/RDC、STA 或上板结果。

| 工件 | 生产者 | 用途 |
|---|---|---|
| `task-contract.json` | architect/coordinator | 工程身份、动态任务、授权、保护项、claim stage、范围、target、需求、验收证据和角色路由 |
| `snapshot-manifest.json` | coordinator | 被审核或执行的代码与工具视图的不可变身份 |
| `impact-manifest.json` | architect/indexer | 受影响 process、时钟/复位域、锥边界、sideband、测试和约束 |
| `cycle-contract.json` | architect | accepted/completed 事件、latency、throughput、stall/reset/flush/error 和对齐语义 |
| `verification-plan.json` | verification author | Requirement → Test → Checker → Cover 和独立性声明 |
| `run-manifest.json` | runner | 精确命令、cwd、工具/版本、target、parameter、seed、退出码和产物路径 |
| `simulation-evidence.json` | runner/reviewer | 逐拍 expected/observed、checker、canary 和结果分类 |
| 波形观察 bundle | 项目级 runner + 只读 reviewer | 可选的 selected-wave/query 证据、执行 receipt、实际覆盖信号/窗口和限制；跨评审复用时绑定包外冻结 root identity；不能充当 expected、因果或 PASS oracle |
| `findings-ledger.json` | coordinator | 跨 snapshot 与修复轮次的稳定 finding 生命周期 |
| Model Card | verification + datasheet reviewer | 设备、协议和参考模型的来源、假设与限制 |
| IP proof packet | FPGA engineer + vendor reviewer | 官方 IP 身份、生成方法、配置所有权、契约、output products、OOC、约束、仿真和 reopen 证据 |

## Snapshot 不变量

每份报告、波形、proof packet、finding、修复和 verdict 必须声明同一 `snapshot_id`。下面任一项变化时创建新 snapshot，并明确使受影响证据失效：

- 源文件或 dirty diff；
- target、top、source list；
- define/include、parameter、constraint；
- 工具或库视图；
- TB、model、checker、assertion 等验证资产。

## 稳定 Finding 身份

推荐格式：

```text
<clock-domain>/<module-or-contract>/<signal-or-path>/<trigger>
```

行号只是证据位置，不是 finding 身份。状态仅使用：

```text
OPEN
FIXED_PENDING_REVIEW
VERIFIED_CLOSED
DUPLICATE
DISPUTED
NOT_APPLICABLE
ACCEPTED_RISK
```

writer 可标记 `FIXED_PENDING_REVIEW`，不能自行标记 `VERIFIED_CLOSED`。只有出现新证据，或后续 diff 重新进入影响锥时才重开。

## 增量索引身份

`codex_out/index/` 的缓存键至少包含：schema version、target、top、source-list hash、include/define hash、parameter hash、source hash、constraint hash 和 dirty diff hash。索引可记录 module/entity/package/interface、instance/generate、process、clock/reset、signal read/write、assignment 类型和 test/constraint 关联。

索引永远不是 elaboration、CDC 安全、时序闭合或仿真正确性的证据。

## Schema 入口

- [任务合同](schemas/task-contract.schema.json)
- [Snapshot](schemas/snapshot-manifest.schema.json)
- [影响清单](schemas/impact-manifest.schema.json)
- [逐拍合同](schemas/cycle-contract.schema.json)
- [验证计划](schemas/verification-plan.schema.json)
- [运行清单](schemas/run-manifest.schema.json)
- [仿真证据](schemas/simulation-evidence.schema.json)
- [Finding 账本](schemas/findings-ledger.schema.json)
- [Model Card](schemas/model-card.schema.json)
- [IP proof packet](schemas/ip-proof-packet.schema.json)
- [故障案例](schemas/fault-case.schema.json)
