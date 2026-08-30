# 兼容性与验证边界

包版本：**1.2.0**

## 包格式

- 插件清单：`.codex-plugin/plugin.json`
- 13 个角色：`.codex/agents/*.toml`
- Skill：`skills/run-fpga-workflow/`、`skills/setup-fpga-workflow/`
- 用户/项目安装目标：`.agents/skills/<skill-name>/`
- GitHub marketplace：`.agents/plugins/marketplace.json`
- 可选门禁模板：`templates/AGENTS.fpga.md`

## 支持范围

- Windows + PowerShell 7 的包验证、安装、卸载和工程 scaffold；
- Xilinx Vivado、Pango PDS、Anlogic TD 的确定性标记识别；
- ModelSim/Questa 正式目录和真实 compile/load/run 合同；
- Verilog、SystemVerilog、VHDL/VHDL-2008 filelist 发现；
- Codex 自定义角色和 Skill 的用户级或项目级部署。
- 按需波形观察、波形可选性 Schema、项目级 trusted-runner 证据边界；
- wave-mcp 0.1.1 的可选 point/range 公开 API 适配层和脱敏环境模板；
- GitHub 地址、Plugin Marketplace 或 `bootstrap.ps1` 驱动的角色/Skill 部署；
- 已有 WSL 发行版上的可选 wave-mcp venv 准备与本地 environment manifest。

## 仍需按项目验证

- Fresh-session 的具体 Codex 版本发现行为；
- 每个 Pango/Anlogic/Vivado 版本的真实 CLI 和官方库；
- DUT 功能、CDC/RDC、STA、物理 QoR、功耗、bitstream 和板卡；
- 第三方 simulator、许可证服务器和厂商 IP 导出差异。
- 第二个独立波形工程、Pango/Anlogic 实际查询链、WDB/FSDB/native WLF 直接读取、完整 X/Z/aggregate 和官方 IP 功能接受；
- 自动安装 WSL 发行版、系统重启恢复和无用户确认的管理员操作；
- 未配置 `vcd2fst` 时的 VCD→FST 能力。
- 非默认 `CODEX_HOME` 下的用户级角色与 `.agents` Skill 联合发现路径；1.2.0 对此 fail-closed，建议使用明确 Project scope。

包验证通过只能证明包结构、脚本语法、schema、模板和安装合同；不能替代真实 EDA 证据。
