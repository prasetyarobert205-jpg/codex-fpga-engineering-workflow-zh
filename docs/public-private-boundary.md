# 公开与私有边界

[中文导航](README.md) · [安装](installation.md) · [证据与安全](safety-and-evidence.md)

## 可以进入公开仓库

- 13 个去项目化角色定义和权限；
- 可复用工程工作流；
- 空白 schema、Model Card、IP proof packet、finding ledger；
- 不包含本机路径的模板和确定性脚本；
- Xilinx/Pango/Anlogic 的通用识别与 fail-closed 规则；
- 公开官方资料支持的通用原则；
- 去标识且证据闭环的工作流改进。

## 必须留在本机或项目内

- 客户、项目和产品名称；
- 售后原始 PDF/DOCX/表格；
- 绝对项目路径和本机 EDA 安装路径；
- part、pin、电压、寄存器地址、时钟/复位关系等项目事实；
- 完整日志、波形、bitstream、私有 IP、加密源；
- 密钥、token、账号和凭据；
- 未完成根因闭环的一次性 workaround；
- 某个旧 snapshot 的“已通过”状态。

## 为什么公开仓库不复制本机 improvement evidence

本机治理账本可能包含历史路径、回滚 hash 和本地操作记录。公开包只提供空白账本模板，保留相同的持续改进能力，但不发布历史数据。

## 私有故障库

公开包提供：

- fault-case schema；
- 禁用的配置示例；
- 查询与校验脚本；
- `REUSABLE` 证据最低条件。

用户在本机配置私有目录；查询结果只保存去标识候选到当前项目 `codex_out/<run-id>/knowledge/`。匹配不能替代当前工程验证。
