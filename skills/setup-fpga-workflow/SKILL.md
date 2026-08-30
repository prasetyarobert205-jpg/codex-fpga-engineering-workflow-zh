---
name: setup-fpga-workflow
description: 从 codex-fpga-engineering-workflow-zh 插件或 GitHub checkout 安全部署、升级、检查或卸载 13 个 FPGA 角色、run-fpga-workflow Skill 和可选 wave-mcp 本地环境。只有用户明确要求安装、部署、升级、检查环境或卸载时使用。
---

# 部署中文 FPGA 工作流

本 Skill 只负责安装与环境准备，不分析或修改 FPGA 产品工程。不得隐式调用；用户必须明确要求安装、部署、升级、检查环境或卸载。

## 找到包源码根

先从当前 `SKILL.md` 所在目录向上两级寻找完整插件根，要求以下文件同时存在：

```text
.codex-plugin/plugin.json
VERSION
scripts/bootstrap.ps1
scripts/validate-package.ps1
```

如果当前 Skill 是由 `install.ps1` 独立复制到用户/项目目录，上述两级路径不会包含完整仓库。这时读取同目录下的 `references/source.json`，要求 package/version/repository/ref 完整且版本一致，然后：

1. 检查 Git 可用；
2. 在系统临时目录创建新的唯一 checkout；
3. 从 `source.json` 的 repository 克隆并固定到精确 ref；
4. 核对 checkout 的 `VERSION`、`.codex-plugin/plugin.json` 和 package validation；
5. 只从该冻结 checkout 执行 bootstrap/doctor/uninstall；
6. 完成后删除临时 checkout。

不得从相似目录猜测包根，不得回退到未固定的 `main`。source manifest 缺失、网络不可用或 ref 不存在时返回 `PACKAGE_SOURCE_REQUIRED`，并给用户明确恢复条件。

## 默认部署合同

除非用户明确选择其他范围：

```text
Scope                  = User
InstallAgentsTemplate  = false
WaveMode               = Detect
Force                  = false
InstallWsl             = false
```

- `Scope=User` 安装到当前用户 Codex 目录；`Scope=Project` 必须给出明确项目根。
- 默认安装 13 个角色、`run-fpga-workflow` 和本部署 Skill。
- 不默认覆盖不同内容；出现冲突时列出路径并停止。
- 不默认写入或替换用户已有的全局 `AGENTS.md`。
- 不修改注册表、全局 PATH、全局 ModelSim/Questa library mapping 或 FPGA 产品工程。
- 不下载完整 wave-mcp Git 仓库、虚拟机镜像或 WSL 发行版。
- `User` scope 当前只支持默认 Windows 用户布局；检测到指向其他目录的 `CODEX_HOME` 时返回 `NONDEFAULT_CODEX_HOME_UNVERIFIED`，不得猜测角色与 Skill 的重定向规则。此时可选择明确的 Project scope。

## 执行顺序

1. 在插件根运行 `pwsh -NoProfile -File scripts/validate-package.ps1`。
2. 运行 bootstrap 的 `-WhatIf`，向用户报告角色、Skill、wave 环境和目标目录计划。
3. 用户当前请求已经明确授权普通用户级安装时，可以继续正式安装；`-Force`、覆盖全局 `AGENTS.md`、安装 WSL、管理员权限或系统重启始终需要单独明确确认。
4. 正式运行：

```powershell
pwsh -NoProfile -File scripts/bootstrap.ps1 `
  -Scope User `
  -WaveMode Detect
```

5. 安装后运行 `scripts/verify-install.ps1` 和 `scripts/deployment-doctor.ps1`。
6. 报告 `READY`、`PARTIAL` 或 `FAILED`，并列出真实已执行阶段。
7. 提醒用户新开 Codex 会话，让新角色和 Skill 被重新发现。

## wave-mcp

`WaveMode`：

- `Skip`：不检查、不安装；
- `Detect`：只读检查 WSL2/发行版/Python/已存在环境；
- `Prepare`：仅当已存在可用 WSL2 发行版时，在用户选择的工具根创建独立 venv 并安装 `requirements-tested.txt`。

用户只要求安装角色时保持 `Detect`；用户明确要求同时部署环境时，先以 `Prepare -WhatIf` 预览，再在现有 WSL/Python 条件满足时执行 `Prepare`。

WSL 或发行版不存在时返回 `USER_ACTION_REQUIRED`，展示建议命令，但不得自行执行 `wsl --install`。用户明确授权系统安装后，由主会话单独执行并处理可能的重启；重启后重新运行 bootstrap。

默认使用发行版的 `python3`。如果它缺少 `venv/ensurepip`，返回 `PARTIAL_PYTHON_VENV_REQUIRED`；用户可以在单独确认后安装发行版的 venv 包，或通过 `-WslPython <现有 Python 命令/绝对路径>` 选择已有独立 Python。部署脚本自身不得运行 sudo/apt。

已有完整 wave-mcp venv 时可用 `-ExistingWavePython <venv/bin/python>` 做现场版本核对并复用；离线或企业代理环境可用 `-Wheelhouse <Windows 目录>` 安装本地 wheel。不得把 wheelhouse、venv 或机器路径提交到公共仓库。

提供 `vcd2fst` 路径不等于转换器已验证。只有显式 `-RunWaveSmoke` 完成合成 VCD→FST→wave-mcp 查询后，状态才能是 `READY_WITH_VCD_CONVERTER`；仅版本和 import 成功时为 `PACKAGES_READY_FST_QUERY_NOT_RUN`，不能写成查询 READY。

wave 环境最多声明：

```text
PACKAGES_READY_FST_QUERY_NOT_RUN
READY_WITH_VCD_CONVERTER
PARTIAL_WSL_REQUIRED
PARTIAL_PYTHON_REQUIRED
PARTIAL_VCD_CONVERTER_MISSING
```

不得因为 wave 环境缺失而撤销已经成功的角色/Skill 安装；整体状态使用 `PARTIAL`。

## 升级和卸载

- 升级先验证现有 install manifest；不同内容或用户修改必须停止，不得静默 `-Force`。
- 卸载调用 `scripts/uninstall.ps1`，只删除 manifest 中仍与安装 hash 一致的文件；保留用户修改。
- 不递归删除用户目录、工具根、WSL 发行版或第三方环境。
