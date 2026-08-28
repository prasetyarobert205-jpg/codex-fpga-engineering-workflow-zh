# FPGA 工作流公开改进证据账本

本文件是公开包的空白治理账本。它只用于记录去项目化、可追溯、可以公开的工作流改进证据；不得从作者本机复制私人历史记录。

禁止记录：客户/项目名称、绝对项目路径、器件/引脚/电压/地址/寄存器值、时钟/复位关系、密钥、日志正文、私有售后文档、历史“已通过”状态和一次性 workaround。

## 晋级条件

- 用户明确提出的跨项目规则可以作为候选，但持久写入仍需明确授权；
- 可复用工作流原则上需要两个独立任务的同类证据；
- 全局硬门禁原则上需要两个独立项目或 target 的同类证据；
- 必须有独立只读复核；
- 没有可追溯证据时标为 `UNVERIFIED`，不得晋级。

## 记录模板

```text
Evidence ID:
Date:
Candidate type: USER_PREFERENCE | PROJECT_FACT | TOOL_VENDOR_FACT | WORKFLOW | GLOBAL_GATE
Sanitized problem:
Independent evidence sources:
Failed approach:
Confirmed root cause:
Repair principle:
Validation performed:
Independent reviewer:
Applicability:
Counterexamples:
Public/private decision:
Promotion decision: REJECTED | UNVERIFIED | CANDIDATE | REUSABLE | GLOBAL_GATE
Rollback point:
```

本仓库初始不携带任何本机改进历史。用户或维护者只能添加已去标识、可公开、证据闭环的条目。
