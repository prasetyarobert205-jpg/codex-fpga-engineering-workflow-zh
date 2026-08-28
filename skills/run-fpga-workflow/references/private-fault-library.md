# 私有 FPGA 故障知识库

故障库用于证据辅助诊断，不是模型训练，也不能覆盖当前工程证据。

## 隐私边界

售后原始文档、客户/项目名称、绝对项目路径、器件/引脚/电压/寄存器事实、日志、凭据和专有源码必须留在用户明确配置的私有位置。不得复制到本 Skill、Memory、公开仓库或普通项目文档。

可选本机配置指向：

```text
~/.codex/private/fpga-fault-library/
```

或其他用户明确授权的目录。公开包只保存 schema、禁用的配置示例和查询逻辑。以 [fault-library.config.example.json](fault-library.config.example.json) 为起点；填写真实私有路径后的配置不得提交。

## 案例生命周期

```text
IMPORTED
ROOT_CAUSE_CONFIRMED
FIX_VERIFIED
BOARD_CONFIRMED
REUSABLE
REJECTED
```

只有根因确认、修复验证、适用边界和反例明确，并且具备用户确认的真实工程证据时，案例才能成为 `REUSABLE`。每个 `REUSABLE` 案例至少包含：

- 非空 source document reference；
- 至少一项 verification；
- 至少一个 evidence hash；
- 至少一条 applicability；
- 非空 board disposition。

若物理上板确实不适用，使用 `NOT_APPLICABLE:<原因>`，不能留空。

## 查询

使用 `scripts/find-fpga-fault-case.ps1`，提供 `ProjectRoot`、私有 `LibraryRoot`、严格位于该项目 `codex_out` 下的 `OutputPath`，以及 normalized error signature、vendor、tool/version、subsystem、symptom 和 trigger。

```powershell
pwsh -File scripts/find-fpga-fault-case.ps1 `
  -ProjectRoot C:\path\to\fpga-project `
  -LibraryRoot C:\private\fpga-fault-library `
  -OutputPath codex_out\run-001\knowledge\matches.json `
  -ErrorSignature "normalized error"
```

查询在匹配前验证案例字段、类型和 `REUSABLE` 最低证据；格式错误的条目被排除，并以 source hash 记录在 `rejected_entries`。输出路径及已有父目录不得是 reparse point。

只把去标识匹配元数据保存到：

```text
codex_out/<run-id>/knowledge/matches.json
```

每个匹配只是 hypothesis。应用前重新核对 target、tool/version、clock/reset、interface、IP mode、trigger、counterexample 和当前日志/报告。不得因为错误字符串相同就套用历史 workaround。

## 导入边界

在没有真实源格式前不提供猜测式通用 importer。用户提供 PDF、DOCX、Markdown 或表格后，应针对真实格式设计 importer，并保留 source hash 和可追溯性。
