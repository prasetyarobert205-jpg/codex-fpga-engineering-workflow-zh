# 变更记录

版本遵循语义化版本。未执行的 EDA、DUT、CDC/STA、bitstream 和板级检查不因包版本发布而变成已验证。

## 1.0.1 - 2026-08-28

### 改进

- 重写根 README，先说明 FPGA 工程痛点和项目优势，再介绍安装与规则；
- 恢复完整 Mermaid 多角色协作流程图；
- 强化逐拍 RTL、验证独立、CDC/STA、官方 IP、物理实现和私有故障库的价值说明；
- 为 13 个角色增加“为什么有价值”的详细介绍；
- 扩充架构、项目优势和角色文档；
- 从面向用户的 README 和中文介绍中移除不需要的具体目录命名说明；
- 本次只更新对外文档与版本信息，不改变 13 个角色权限和 Skill 运行门禁。

## 1.0.0 - 2026-08-28

### 新增

- 建立独立全中文公开仓库；
- 同步本机实时 13 个 FPGA 角色的名称、读写权限和详细职责；
- 提供完整中文 `run-fpga-workflow` Skill、references、11 个 schema、6 个确定性 Skill 脚本、工程模板和三厂商 adapter 资产；
- 提供完整可选 `AGENTS.fpga.md` 门禁模板；
- 提供架构、优势、角色、安装、使用、证据安全、公开/私有边界中文文档；
- 提供 Xilinx/Pango/Anlogic fail-closed 厂商识别；
- 提供标准工程 scaffold、filelist、preflight、私有故障库查询接口；
- 提供中文 SVG 项目插图；
- 提供项目级和用户级安全安装、验证和卸载；
- 提供 GitHub Actions 包验证和 scaffold smoke。

### 安全边界

- 未发布本机 improvement evidence 历史、私人路径、客户/项目事实或售后原始文档；
- 公开仓库只包含空白改进账本和私有故障库 schema/config/query；
- 安装器默认拒绝覆盖不同内容，`AGENTS.md` 模板默认不安装；
- 角色权限保持 10 个严格只读、3 个条件顺序写入。
