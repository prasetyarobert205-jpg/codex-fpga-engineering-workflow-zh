# 私有故障库公开合成测试

本目录只包含 `SYNTH_*` / `PUBLIC_SYNTHETIC` 测试数据，不包含真实售后案例、客户资料、本机路径、源 hash 或已填写配置。

运行：

```powershell
pwsh -NoProfile -File tests/fault-library/run-fault-library-canaries.ps1
```

测试覆盖三种模式、`REJECTED`/畸形/重复 ID/伪 `REUSABLE` 排除、同症状不同责任域、敏感 Query/Filter 不回写、输出范围、Top-N、确定性和输出白名单 mutation。
