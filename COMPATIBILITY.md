# 兼容性与验证边界

包版本：**1.0.0**

## 包格式

- 插件清单：`.codex-plugin/plugin.json`
- 13 个角色：`.codex/agents/*.toml`
- Skill：`skills/run-fpga-workflow/`
- 用户/项目安装目标：`.agents/skills/run-fpga-workflow/`
- 可选门禁模板：`templates/AGENTS.fpga.md`

## 支持范围

- Windows + PowerShell 7 的包验证、安装、卸载和工程 scaffold；
- Xilinx Vivado、Pango PDS、Anlogic TD 的确定性标记识别；
- ModelSim/Questa 正式目录和真实 compile/load/run 合同；
- Verilog、SystemVerilog、VHDL/VHDL-2008 filelist 发现；
- Codex 自定义角色和 Skill 的用户级或项目级部署。

## 仍需按项目验证

- Fresh-session 的具体 Codex 版本发现行为；
- 每个 Pango/Anlogic/Vivado 版本的真实 CLI 和官方库；
- DUT 功能、CDC/RDC、STA、物理 QoR、功耗、bitstream 和板卡；
- 第三方 simulator、许可证服务器和厂商 IP 导出差异。

包验证通过只能证明包结构、脚本语法、schema、模板和安装合同；不能替代真实 EDA 证据。
