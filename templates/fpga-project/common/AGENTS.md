# FPGA 工程规则

## 稳定工程身份

- 工程：`__PROJECT_NAME__`
- 产品 top：`__TOP_MODULE__`
- 仿真 top：`__SIMULATION_TOP__`
- 厂商：`__VENDOR__`
- 工具/版本：`__TOOL__ __TOOL_VERSION__`
- 器件/package：`__DEVICE__ __PACKAGE__`
- canonical launcher：`__CANONICAL_PROJECT_ENTRY__`
- 正式入口：`project/script/run.bat`、`simulation/script/run.bat`、`linter/script/run.bat`
- 长期保护项：当前未记录；只在此处增加跨任务稳定限制。

身份块用于减少重复发现，不是全用途任务或授权卡。每个新请求生成动态 task delta；普通 follow-up 只更新 snapshot 和 impact cone。

- 项目规格、target 文件、约束、寄存器唯一来源和当前报告是权威事实。
- 同一 checkout 只有一个产品源码写入者，reviewer 保持只读。
- 同步时序变更按 pre-edge、旧值 RHS、NBA commit、组合稳定、下一采样沿推导。
- 未经合同批准，不改变 latency、throughput、backpressure、data/sideband 对齐、reset、flush、abort 和 error 语义。
- 正式 build 状态进入 `project/par`；正式 ModelSim/Questa 状态进入 `simulation/work`；Codex 诊断进入 `codex_out`。
- 标准目录固定为 `project/`、`project/par/`、`project/script/`、`simulation/`、`linter/`、`release/`、`codex_out/`；禁止数字后缀。
- `project/script` 只放 `run.bat`、`setting.bat`、`src_list.txt` 和一个已确认厂商 Tcl/CLI。`simulation/script` 默认只放 `run.bat`、`setting.txt`、`src_list.txt`、`vsim.do`；生成文件和日志进入 `simulation/work`。
- 只运行项目确认命令。未执行为 `NOT RUN`；证据缺失或不可读为 `UNVERIFIED`。
- compile/elaboration/有限运行使用 `DIAGNOSTIC_SMOKE`；只有声明依赖功能、formal、CDC/STA、电气或发布时才启用完整证据。
- 成为正式 target 时，只在 `project/par` 根创建一个真实 `__PROJECT_NAME__.xpr|.pds|.al`；禁止额外 `vivado_project`、`build` 或随机容器，也不得提前伪造 marker。
- BAT 只配置工具根/环境和当前进程 PATH，按标准命令名调用；不写死绝对 executable，不持久修改 PATH。
- 官方 IP 优先复用 managed IP、增量生成、检查 source view 后 staging/import、使用本机同版本官方 Tcl/CLI；GUI 是一次性兜底并导出 recipe。正式 source list 禁止近似 stub。
- 功耗默认 `NOT APPLICABLE`。
