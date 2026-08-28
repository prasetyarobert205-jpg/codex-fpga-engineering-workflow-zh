# 中文文档导航

[返回仓库首页](../README.md)

本仓库不维护重复的英文文档树。角色名称、状态码、工具命令、HDL 和 schema key 保留业界英文标识，其余说明以简体中文为主。

| 文档 | 内容 |
|---|---|
| [架构](architecture.md) | 工程身份、动态任务、单写入者、snapshot、检查点和生命周期 |
| [项目优势](advantages.md) | 为什么它不同于普通 AI 写 RTL、单 Agent 和纯 checklist |
| [角色与分工](roles.md) | 13 个角色、权限、实现者五种模式、写入顺序和终审 |
| [安装](installation.md) | URL 交给 Codex、User/Project scope、预览、冲突保护、升级和卸载 |
| [使用](usage.md) | 最简单的安装提示词、首次分析提示词、最小修改提示词和专业任务示例 |
| [工程目录与存放位置](project-layout.md) | RTL、IP、约束、厂商工程、仿真、release 和 Codex 输出分别放在哪里 |
| [证据与安全](safety-and-evidence.md) | 证据阶梯、声明语言、CDC/STA/功耗和板级边界 |
| [公开与私有边界](public-private-boundary.md) | GitHub 可以包含什么，哪些信息必须留在本机 |
| [能力等价范围](capability-equivalence.md) | 与本机权限和能力保持一致的机器可核对合同 |

推荐新用户顺序：

```text
安装
→ 新开 Codex 会话
→ ANALYZE 只读进入工程
→ 确认工程身份和任务范围
→ 再决定是否授权修改
```
