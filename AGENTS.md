# 贡献者与维护者规则

本仓库是可安装的全中文 Codex FPGA 工程工作流，不是某个 FPGA 产品工程。

- 公开内容不得包含客户名称、私人路径、密钥、板卡专属事实、售后原始文档或历史“已通过”状态。
- 13 个角色的名称、读写权限、单一产品写入者、reviewer 独立性和证据分层属于兼容性合同。
- 不得为了让 CI、仿真或构建变绿而降低 CDC/RDC、时序、电气、安全、许可证或独立签核门禁。
- 角色 TOML、Skill、reference、schema、脚本和模板修改必须最小、可审查；不得提交厂商生成数据库、IP output products、波形或本机工具路径。
- 根目录文档、`docs/` 和示例全部使用简体中文；HDL、工具命令、schema key、状态码和业界通用术语可以保留英文标识。
- `scripts/validate-package.ps1` 是提交前最低包验证；脚手架 smoke 只能证明目录、文件和确定性脚本阶段，不证明 DUT、CDC/STA、bitstream 或板卡。
- 正式生成工程使用 `project/`、`project/par/`、`project/script/`、`simulation/`、`linter/`、`release/`、`codex_out/`，禁止数字后缀标准目录。
- 用户双击入口使用 BAT + 已确认厂商 Tcl/DO/CLI；不得依赖 Codex 私有 `pwsh.exe`，不得在公开模板写死绝对工具 executable。
- 本仓库的 `templates/AGENTS.fpga.md` 是可选用户/项目门禁模板，安装器不得默认覆盖已有 `AGENTS.md`。
- `skills/run-fpga-workflow/references/improvement-evidence.md` 只保留公开空白模板，不得复制维护者本机治理历史。
