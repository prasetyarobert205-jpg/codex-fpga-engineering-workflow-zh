# __PROJECT_NAME__

FPGA 正式工程骨架：top `__TOP_MODULE__`，厂商 `__VENDOR__`，工具 `__TOOL__ __TOOL_VERSION__`，part `__PART__`。稳定身份位于项目 `AGENTS.md`；每个用户请求提供动态 task delta。

## 一键入口

- `project\script\run.bat`：compile/build 选定厂商工程；
- `simulation\script\run.bat`：运行配置的 simulation case；
- `linter\script\run.bat`：运行配置的 linter。

正式双击路径使用 BAT + 已确认厂商 Tcl/DO/CLI，不依赖 Codex 私有 PowerShell。`project\script` 放 BAT、项目设置、canonical list 和一个厂商 Tcl/CLI；`simulation\script` 默认只放四个标准文件，生成导出和 simulator 数据库进入 `simulation\work`。

脚手架占位符 fail closed，直到准确 target、工具版本、part、simulator 和库 recipe 被确认。正式厂商数据库/报告归 `project/par`；正式 ModelSim/Questa work/export/log/wave 归 `simulation/work`；Codex 实验、索引和 review packet 归 `codex_out`。

权威 launcher 最终必须直接位于 `project/par/__PROJECT_NAME__.xpr|.pds|.al`。额外 `vivado_project`、`build` 或随机容器不属于标准布局；脚手架不创建假工程文件。

标准目录为 `project`、`project/par`、`project/script`、`simulation`、`linter`、`release`、`codex_out`，禁止数字后缀。任何脚本都不得猜厂商 CLI 或静默替换工具/库版本。
