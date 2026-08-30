# 安装

[中文导航](README.md) · [最简使用](usage.md) · [公开与私有边界](public-private-boundary.md)

## 前置条件

- 支持自定义 agent 和 Skill 的 Codex 环境；
- PowerShell 7，用于包验证、安装、卸载和脚手架；
- Git，用于克隆和版本管理；
- 厂商 EDA 工具只在真实工程运行时需要。

安装脚本使用 PowerShell，不代表生成工程的正式 `run.bat` 依赖 Codex 私有 PowerShell。正式 BAT 使用已确认的厂商原生 Tcl/DO/CLI。

## 最推荐：让 Codex 帮你安装到当前工程

如果希望用户级一键部署，优先阅读根目录的 [把仓库地址交给 Codex 安装](../INSTALL_WITH_CODEX.md)。仓库从 `v1.2.0` 起同时提供 Plugin Marketplace、显式部署 Skill 和 bootstrap。

把以下提示词发给 Codex：

```text
请把这个 FPGA 中文工作流以 Project scope 安装到我当前的 FPGA 工程：
https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh

先克隆到独立目录，阅读 README、LICENSE 和安装脚本；运行 validate-package.ps1；
然后使用 install.ps1 -Scope Project -ProjectPath <当前工程根> -WhatIf 预览。
列出将写入的角色和 Skill；发现任何已有不同内容时停止，不使用 -Force。
我确认后再正式安装并运行 verify-install.ps1。
不要修改 RTL、约束、IP、仿真文件或厂商工程。完成后提醒我新开 Codex 会话。
```

Project scope 不修改其他工程和用户级全局角色，适合第一次试用。

## 手工克隆和验证

```powershell
git clone https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh.git
cd codex-fpga-engineering-workflow-zh
pwsh -NoProfile -File .\scripts\validate-package.ps1
```

## 项目级安装

先预览：

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -Scope Project `
  -ProjectPath C:\path\to\fpga-project `
  -WhatIf
```

确认后安装和核对：

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -Scope Project `
  -ProjectPath C:\path\to\fpga-project

pwsh -NoProfile -File .\scripts\verify-install.ps1 `
  -Scope Project `
  -ProjectPath C:\path\to\fpga-project
```

## 用户级安装

希望所有 FPGA 项目都可发现时使用。先预览：

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -Scope User -WhatIf
```

正式安装：

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -Scope User
pwsh -NoProfile -File .\scripts\verify-install.ps1 -Scope User
```

目标包括：

```text
<UserProfile>/.codex/agents/*.toml
<UserProfile>/.agents/skills/run-fpga-workflow/**
<UserProfile>/.agents/skills/setup-fpga-workflow/**
```

安装器默认拒绝覆盖不同内容。不要为了省事直接使用 `-Force`；先审查差异。明确使用 `-Force` 时，安装器必须为被替换文件创建时间戳备份。

## 可选安装完整 FPGA AGENTS 门禁

默认不覆盖用户或项目已有 `AGENTS.md`。只有明确需要时使用：

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -Scope Project `
  -ProjectPath C:\path\to\fpga-project `
  -InstallAgentsTemplate `
  -WhatIf
```

审查后再移除 `-WhatIf`。用户级同样可以 `-InstallAgentsTemplate`，但这属于跨项目持久门禁，必须先查看差异。

## 新工程脚手架

```powershell
pwsh -NoProfile -File .\scripts\new-fpga-project.ps1 `
  -Destination C:\work\my-fpga `
  -ProjectName my-fpga `
  -TopModule top `
  -Vendor XILINX
```

也支持 `PANGO`、`ANLOGIC`。脚手架生成标准目录、入口 BAT、setting、filelist、`vsim.do` 和稳定工程身份，但不会伪造真正 `.xpr/.pds/.al` 或厂商命令。

## 可选 wave-mcp 环境

bootstrap 默认只检测，不安装 WSL。已有 WSL 发行版时，可以让仓库在用户工具目录创建独立 venv：

```powershell
pwsh -NoProfile -File .\scripts\bootstrap.ps1 `
  -Scope User `
  -WaveMode Prepare `
  -WaveToolRoot C:\path\to\codex-fpga-tools `
  -WslPython python3
```

也可以手工创建：

```bash
python3 -m venv <LOCAL_TOOL_ROOT>/venv-wave-mcp
<LOCAL_TOOL_ROOT>/venv-wave-mcp/bin/python -m pip install \
  -r integrations/wave-mcp/requirements-tested.txt
```

`requirements-tested.txt` 用于重现公开实测组合；`requirements.txt` 只锁 wave-mcp 主版本，适合单独探索直接依赖兼容性。复制 `environment.example.json` 到工具目录外的本地清单，例如 `environment.local.json`，填写当前命令和版本/hash；不要把真实绝对路径提交到公共仓库。已有可用环境时无需重复安装，只需每次证据运行重新确认版本和实现 hash。

`WaveMode=Detect` 完全只读；`WaveMode=Prepare` 只在已存在的 WSL 发行版与 Python 上准备 venv。WSL 不存在时返回 `PARTIAL_WSL_REQUIRED` 并给出建议，不执行 `wsl --install`。未配置 `vcd2fst` 时仍可查询已有 FST，但 VCD→FST 保持未配置。

如果发行版默认 `python3` 缺少 `venv/ensurepip`，脚本返回 `PARTIAL_PYTHON_VENV_REQUIRED`。可以在用户单独授权后安装对应发行版 venv 包，或用 `-WslPython` 指向已经存在且支持 `python -m venv` 的独立 Python。

已经有完整 wave-mcp venv 时，可用 `-ExistingWavePython <venv/bin/python>` 复用并核对版本；受限网络可以用 `-Wheelhouse <Windows 目录>` 从本地 wheel 安装。仓库本身不携带 wheelhouse 或 venv。

仅提供 `-Vcd2FstPath` 时转换器状态为 `CONFIGURED_UNVERIFIED`。再加 `-RunWaveSmoke`，脚本会在系统临时目录执行合成 VCD→FST→wave-mcp 查询并清理工件；只有该链通过才报告 `READY_WITH_VCD_CONVERTER`。

参见：[wave-mcp 可选集成](../integrations/wave-mcp/README.md)。

## 新会话发现

安装和 verify 完成后新开 Codex 会话。首次用无害只读 canary：

```text
使用 $run-fpga-workflow，以 ANALYZE 模式列出可用 FPGA 角色和读写权限。
不要修改文件，也不要运行 EDA 工具。
```

## 升级

1. 阅读 [CHANGELOG](../CHANGELOG.md) 和 [COMPATIBILITY](../COMPATIBILITY.md)；
2. 运行新版 package validation；
3. 使用相同 Scope 执行 `-WhatIf`；
4. 审查差异和备份计划；
5. 明确决定是否 `-Force`；
6. 运行 verify；
7. 新会话做只读 canary。

## 卸载

```powershell
pwsh -NoProfile -File .\scripts\uninstall.ps1 -Scope User -WhatIf
pwsh -NoProfile -File .\scripts\uninstall.ps1 -Scope User
```

卸载只删除 manifest 中记录且 hash 未变化的文件；用户修改过的文件保留。项目级卸载增加 `-Scope Project -ProjectPath ...`。
