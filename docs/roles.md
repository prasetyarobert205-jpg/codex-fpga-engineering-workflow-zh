# 角色与分工

[中文导航](README.md) · [架构](architecture.md) · [安装](installation.md) · [使用](usage.md)

## 13 个角色

| 角色 | 责任 | 权限 |
|---|---|---|
| `fpga_architect` | 工程身份、动态任务、架构、影响锥、预算、角色路由 | 只读 |
| `fpga_engineer` | RTL、官方 IP、构建流、物理实现或 release 的唯一产品写入者 | 条件写入 |
| `verification_engineer` | TB、assertion、独立模型、scoreboard、formal 资产 | 产品只读；验证资产顺序写入 |
| `fpga_temporal_evidence_reviewer` | Shadow 逐拍和仿真证据审查 | 只读 |
| `fpga_cdc_timing_reviewer` | CDC_STRUCTURE、STA_COVERAGE、PHYSICAL_QOR、TIMING_CLOSURE | 只读 |
| `fpga_interface_architect` | CSR、命令、IRQ、DMA 和固件兼容 | 只读 |
| `fpga_vendor_platform_reviewer` | IP、原语、wrapper、约束和 target | 只读 |
| `fpga_board_validation_engineer` | 安全上板步骤和仪器证据 | 只读 |
| `fpga_reviewer` | 独立集成终审 | 只读 |
| `system_architect` | 跨 FPGA/硬件/固件架构 | 条件只读 |
| `embedded_engineer` | FPGA 相关固件实现 | 条件顺序写入 |
| `hardware_datasheet` | 精确手册、电气、页码和器件证据 | 条件只读 |
| `independent_reviewer` | 跨领域或安全关键 release 终审 | 条件只读 |

## 实现者五种模式

| 模式 | 写入责任 | 不自动包含 |
|---|---|---|
| `RTL_IMPLEMENTATION` | RTL、wrapper、必要约束 | IP、P&R、release |
| `IP_INTEGRATION` | 官方配置、recipe、工程集成、proof packet | 网上下载配置或近似 stub |
| `BUILD_FLOW` | BAT/Tcl/DO、filelist、路径和库 | 为脚本失败修改 RTL |
| `PHYSICAL_IMPLEMENTATION` | 证据触发的 QoR 和时序闭环 | 随机 seed、全局 Pblock |
| `RELEASE_PACKAGING` | 明确授权的发布产物和 manifest | Flash 或上传 |

## 默认写入顺序

```text
产品 RTL/约束/IP/构建流
→ 可选固件批次
→ 可选验证资产批次
→ 隔离验证
→ 专项复审
→ final reviewer
```

同一 checkout 不存在两个同时写入者。finding 返回负责该文件的写入者，
修复后重新生成相关 snapshot 和证据。

## 功耗

功耗默认 `NOT APPLICABLE`。只有明确请求或真实功耗、热、安全、release
预算时才启用正式功耗证据。
