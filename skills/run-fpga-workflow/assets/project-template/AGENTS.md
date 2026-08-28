# 工程 FPGA 事实

## 稳定工程身份

工程：__PROJECT_NAME__

产品 top：__TOP_MODULE__

仿真 top：__SIM_TOP_MODULE__

厂商：__VENDOR__

工具：__TOOL__

工具版本：__TOOL_VERSION__

part：__PART__

canonical 工程入口：`__CANONICAL_PROJECT_ENTRY__`

正式入口：`project/script/run.bat`、`simulation/script/run.bat`、`linter/script/run.bat`

长期保护项：当前未记录；只添加跨任务稳定限制。

此块是稳定工程身份，不是全用途任务或授权卡。每个请求生成动态 task delta；普通 follow-up 只更新 snapshot/impact cone。

标准目录为 `project/`、`project/par/`、`project/script/`、`simulation/`、`linter/`、`release/`、`codex_out/`，禁止数字后缀。用户运行入口使用 BAT + 已确认厂商 Tcl/DO/CLI，不依赖 Codex 私有 `pwsh.exe`。正式 build 属于 `project/par`，正式 ModelSim/Questa 属于 `simulation/work`，Codex 诊断属于 `codex_out`。

生成厂商 IP 前，确认复制的 XCI/IDF/IPC 输出路径属于当前 checkout；旧配置在 `project/par` staging/import，或由当前版本官方工具 recipe 重建，禁止跨 checkout 生成。

正式 target 只允许一个直接位于 `project/par/__PROJECT_NAME__.xpr|.pds|.al` 的权威工程文件；禁止额外 `vivado_project`、`build` 或随机目录，也不得提前伪造空 marker。

正式 BAT 不嵌入绝对 tool executable，只配置工具根/环境、当前进程 PATH 和标准命令名，不持久修改 PATH。

工具链和有限运行使用 `DIAGNOSTIC_SMOKE`；仿真 DUT 接受才使用 `FUNCTIONAL_ACCEPTANCE`；formal/CDC/STA/电气/发布只启用相应 `SPECIALIST_ACCEPTANCE`。smoke 不是功能 `SIMULATION_PASS`。

在此记录权威 device、package、tool/version、clock/reset、constraint、interface、register source、已验证命令和验收条件。项目规则可收紧用户级门禁，不得削弱证据、安全、单写入和独立审核。
