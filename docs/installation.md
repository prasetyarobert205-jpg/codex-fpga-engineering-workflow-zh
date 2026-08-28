# 安装

[中文导航](README.md) · [最简使用](usage.md) · [公开与私有边界](public-private-boundary.md)

## 前置条件

- 支持自定义 agent 和 Skill 的 Codex 环境；
- PowerShell 7，用于包验证、安装、卸载和脚手架；
- Git，用于克隆和版本管理；
- 厂商 EDA 工具只在真实工程运行时需要。

安装脚本使用 PowerShell，不代表生成工程的正式 `run.bat` 依赖 Codex 私有 PowerShell。正式 BAT 使用已确认的厂商原生 Tcl/DO/CLI。

## 最推荐：让 Codex 帮你安装到当前工程

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
