# 证据触发的物理实现

只在 `IMPLEMENTATION_QOR`、`TIMING_CLOSURE`，或真实 post-place/post-route 报告显示物理问题时读取。普通源码审查、compile、simulation smoke 或无关 RTL 小改不得机械启用本流程。

## 闭环

1. 冻结工具/版本、part、源码/约束 snapshot、seed 和 strategy。
2. 建立 synth/place/route 基线报告。
3. 对最高影响 failing path 或 implementation bottleneck 分类。
4. 一次只改变一个主变量。
5. 重跑必要 implementation stage。
6. 比较 WNS/TNS、hold、route status、congestion、resource 和 runtime。
7. 有证据改善才保留，否则回滚。
8. 只在有限修复预算内重复。

## 分类与归属

```text
logic depth
route delay / placement distance
high fanout
congestion
clocking
RAM/DSP/GT/IO placement
CDC-adjacent physical path
constraint coverage or precedence
```

- logic depth：RTL、算法或 pipeline contract；
- route/fanout/congestion：placement、replication 或限定物理修改；
- RAM/DSP/GT/IO 距离：架构、寄存器使用或有依据的 placement；
- constraint defect：修约束，不换 strategy 掩盖；
- 少量 post-route 失败：条件性 post-route physical optimization。

不得默认换 seed/strategy、增加全局 Pblock、对全设计 floorplan、重复 phys-opt、复制全部高扇出寄存器或盲目插拍。不存在跨器件通用的逻辑级数或 slack 阈值。

## 功耗边界

功耗默认 `NOT APPLICABLE`。只有用户明确要求，或真实功耗/热/安全/发布预算触发时才运行正式功耗分析。启用时必须说明 activity 来源：默认假设、用户设定、SAIF/VCD 或测量；功耗不应成为所有任务的机械阻塞门。
