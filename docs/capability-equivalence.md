# 与本机能力和权限的等价范围

[中文导航](README.md) · [角色](roles.md) · [公开与私有边界](public-private-boundary.md)

本仓库以维护者 2026-08-30 的本机 FPGA 角色和 Skill 为能力基线。等价目标不是逐字复制私人文件，而是公开后不降低角色权限、工程门禁、工具流能力和证据边界。

## 保持一致

- 13 个角色名称；
- 10 个严格只读角色；
- 3 个条件顺序写入角色；
- 单一默认产品源码写入者；
- verification author 不得自签；
- Shadow temporal reviewer；
- ANALYZE/QUICK/FULL；
- 三种 evidence profile；
- 十种 claim stage；
- 五种 `fpga_engineer` 模式；
- 最多三轮自动修复；
- project identity + task delta；
- official IP、逐拍仿真、CDC/RDC、STA、P&R、板级和 final review 能力；
- 标准工程目录和原生 BAT 工具流；
- Xilinx/Pango/Anlogic 识别；
- 私有故障库 schema/config/query 能力；
- 46 个 Skill 文件、11 个 schema、6 个确定性 Skill 脚本；
- 按需波形观察、波形可选性状态、observed/expected/checker 分权和本地 wave-mcp 可选集成边界。

机器可读清单见 [CAPABILITY-MANIFEST.json](../CAPABILITY-MANIFEST.json)。

## 允许的公开差异

- 将英文内部说明翻译成中文；
- 调整 reference 结构以降低每轮上下文；
- 把本机 improvement evidence 历史替换为空白公开账本；
- 删除本机绝对路径、回滚 hash、客户/项目和售后原始数据；
- 把私有目录改为禁用配置示例；
- 增加公开 README、文档、SVG 和 GitHub CI。

这些差异不改变权限和能力；它们防止公开仓库泄漏本机数据。

## 不允许的未来回退

若未来版本出现以下变化，属于兼容性破坏：

- reviewer 获得产品写权限；
- 产品源出现多个默认并行写入者；
- verification author 可以自签；
- smoke 被允许冒充功能 PASS；
- 删除 CDC/RDC、STA、独立终审或逐拍证据边界；
- 正式脚本重新依赖 Codex 私有 PowerShell或绝对 executable；
- 允许近似厂商 IP 模型进入正式产品源；
- 私有售后文档进入公共仓库。
