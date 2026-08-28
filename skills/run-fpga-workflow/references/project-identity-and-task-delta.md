# 工程身份基线与动态任务

用户提供 FPGA 工程身份卡、首次打开新工程/target，或后续请求改变当前任务时读取。身份卡用于减少发现成本，不是冻结的全用途规格，也不授予宽泛写入或外部操作权限。

## 稳定工程身份

只归一化相对稳定的事实：

```text
project_root
canonical_project_entry
vendor
tool / tool_version
part
product_top / simulation_top
build / simulation / lint entrypoints
long-term protected boundaries
board boundary
```

用户填写内容在被工程或工具确认前属于 declared intent。项目专属事实留在项目 `AGENTS.md`/SSOT，不进入用户级角色、Skill 文本、Memory 或跨项目默认值。

## 动态任务状态

每个实质性 follow-up 派生：

```text
current_task
task_delta.relation = INITIAL | SUPPLEMENTS | SUPERSEDES | EXPANDS | NARROWS
authorization
protected_work
requested_claim
claim_stage
impact cone
role routing with mode and reason
```

最新明确请求更新当前任务，但不会静默移除长期保护项，也不会自动授权 clean/overwrite、IP 重生成、implementation、release、外部发布或物理板卡动作。这些能力必须出现在当前 task contract。

## 增量刷新

同一工程的普通 follow-up 不重复扫描整机或机械重发开场报告，只刷新变化文件、受影响锥、耦合验证资产、约束、IP、脚本和证据。

以下事实实质变化时刷新工程身份：

- 工程根或 canonical entry；
- vendor、part、product top 或 board revision；
- tool/IP version；
- source/constraint target view；
- requested claim stage；
- 会改变 target 或工具视图的 baseline branch/commit。

普通代码提交或同一 target 内澄清只更新 snapshot。

## 优先级

```text
安全和跨项目硬门禁
项目 SSOT 与当前观测证据
用户最新明确请求
稳定身份卡默认值
历史与推断
```

发生冲突时报告冲突，不静默选择。如果身份卡声明的工具版本与真实命令报告不一致，停止版本敏感的 IP/implementation 接受。

## Claim stage

保留三种证据 profile，并用下列一个阶段限定：

```text
PREFLIGHT
COMPILE
SIM_SMOKE
FUNCTIONAL_SIM
SYNTHESIS
IMPLEMENTATION_QOR
TIMING_CLOSURE
FORMAL
RELEASE
BOARD_PREP
```

compile/smoke 不自动启用无关 CDC/STA/P&R/formal/release。功耗默认 `NOT APPLICABLE`。
