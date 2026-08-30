# 证据与安全

[中文导航](README.md) · [架构](architecture.md) · [使用](usage.md)

## 证据阶梯

```text
源码审查
→ lint / elaboration
→ RTL 仿真
→ formal
→ CDC/RDC
→ 综合
→ implementation / STA
→ 仪器测量
→ 板级结果
```

前一级不能自动替代后一级。

## 声明语言

- `CONFIRMED`：当前证据直接支持；
- `INFERRED`：明确假设下的推断；
- `UNKNOWN`：信息缺失或冲突；
- `NOT RUN`：当前没有执行；
- `UNVERIFIED`：证据缺失、旧、不可读或不足；
- `PASS`：当前 scope 的接受条件全部满足；
- `PASS WITH CONDITIONS`：有明确剩余条件；
- `FAIL`：接受条件失败或存在 BLOCKER/HIGH。

compile exit 0 不等于功能正确；仿真通过不等于 CDC 或时序闭合；bitstream
生成不等于安全上板。

## 仿真证据

功能接受需要：

- 与需求绑定的独立 checker/model；
- accepted edge 和 due cycle/window；
- data/valid/sideband/tag 对齐；
- scoreboard drain；
- X/Z policy；
- 相关 negative canary；
- 独立只读审核。

日志结束、`$stop` 或波形“看起来正常”不能单独构成 `SIMULATION_PASS`。

波形观察只证明冻结波形中的 observed values。波形不适用时记录 `NOT_APPLICABLE`；被功能结论依赖且与其他证据一致时记录 `CONSISTENT`；`INCONCLUSIVE` 或 `CONTRADICTORY` 不能支持 PASS。`COMPLETE`、GUI 可见、VCD/FST 查询一致和 trusted-runner 链完成都不会取代 requirement、expected、checker 或 negative canary。

## CDC/STA

异步 FIFO 的结构证据与约束覆盖分别判断。缺少时钟/约束时，timing coverage
是 `UNVERIFIED`，不能只凭这一点判 RTL 错误。动态仿真不替代 CDC/RDC/STA。

## 功耗

功耗默认 `NOT APPLICABLE`。启用时必须说明 activity 来源，例如默认假设、
用户设定、SAIF/VCD 或实测。功耗报告不是实际温升或供电安全的替代。

## 物理板卡

接线、上电、下载、Flash、运动、加热、激光、继电器、高压和仪器连接均由
具备条件的用户现场执行。角色只提供前置条件、步骤、预期读数、停止条件、
恢复方法和证据解释。该工作流不是功能安全认证。
