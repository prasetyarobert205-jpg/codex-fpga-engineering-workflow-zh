# 第三方软件声明

## Tencent/wave-mcp

- 上游：<https://github.com/Tencent/wave-mcp>
- 已测试版本：`0.1.1`
- 上游许可证：MIT
- 版权所有：Copyright (C) 2026 Tencent. All rights reserved.

本仓库没有复制完整 wave-mcp 源码、wheel、虚拟环境或离线 bundle。`integrations/wave-mcp/query_adapter.py` 是本仓库编写的公开 API 调用适配层；依赖安装由 `wave-mcp==0.1.1` 提供。

上游 MIT 许可文本副本见 [`integrations/wave-mcp/LICENSE.wave-mcp`](integrations/wave-mcp/LICENSE.wave-mcp)。

## GTKWave vcd2fst

本仓库不分发 `vcd2fst` 二进制。环境模板只允许用户引用自己安装并确认许可/版本的转换器。已有 FST 时不需要该工具。

## 免责声明

第三方项目名称和链接仅用于兼容性、许可和可选集成说明，不表示 Tencent、GTKWave 或其他维护者认可、赞助或签核本 FPGA 工作流。
