# 把仓库地址交给 Codex 安装

用户不需要先理解角色目录、Skill 路径或 wave-mcp 依赖。把仓库地址和下面的短提示词交给 Codex即可。

## 最短提示词

```text
请从这个仓库的 v1.3.0 安装中文 FPGA 工作流：
https://github.com/prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh

用户级部署 13 个 FPGA 角色和 Skill；已有可用 WSL/Python 时准备 wave-mcp 环境，没有 WSL 或缺少 python venv 时先告诉我需要什么。安装系统组件、覆盖已有不同文件或修改全局 PATH 前必须先问我。
```

Codex 应当固定 `v1.3.0`，先运行包验证和 `bootstrap.ps1 -WhatIf`，然后在已授权范围内使用 `WaveMode=Prepare` 安装并核对 SHA-256。未安装 WSL 时，角色安装仍可完成，最终状态为 `PARTIAL`。

## Codex Plugin Marketplace

Codex CLI 支持从 GitHub 仓库添加 marketplace：

```bash
codex plugin marketplace add prasetyarobert205-jpg/codex-fpga-engineering-workflow-zh --ref v1.3.0
codex plugin add codex-fpga-engineering-workflow-zh@codex-fpga-zh --json
```

安装插件后，新开会话并明确调用：

```text
使用 $setup-fpga-workflow，用户级安装 13 个 FPGA 角色；wave-mcp 先检测，WSL 不存在时不要自动安装。
```

## 不使用 Plugin CLI

Codex 也可以把仓库固定版本克隆到临时目录，然后执行：

```powershell
pwsh -NoProfile -File .\scripts\bootstrap.ps1 -Scope User -WaveMode Detect -WhatIf
pwsh -NoProfile -File .\scripts\bootstrap.ps1 -Scope User -WaveMode Detect
```

`-WhatIf` 不写入角色、Skill 或环境。正式安装默认不覆盖不同内容，也不会写入全局 `AGENTS.md`。

## 环境结果

```text
READY    角色、Skill 和请求的 wave 环境全部完成
PARTIAL  角色/Skill 已完成，但 WSL、Python 或 VCD 转换器需要用户处理
FAILED   包验证、角色安装或哈希核对失败
```

wave-mcp 只作为可选波形观察工具。安装完成不代表任何 DUT、仿真、CDC/RDC、STA 或板级功能已经通过。
