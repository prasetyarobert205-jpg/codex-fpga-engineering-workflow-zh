# 售后故障候选查询提示词

```text
使用 $run-fpga-workflow。这是一个 FPGA 或直接相关的售后/客户现场故障。
使用 AFTERSALES_TRIAGE，只读查询本机 local config 配置的私有故障库。
如果配置不存在、被禁用或目录无效，停止并报告；不要猜路径或扫描磁盘。

先整理当前 vendor/tool/version、part、subsystem、clock/reset/interface、
symptom/error signature、trigger/reproduction 和已有日志/波形/报告。

只返回 3～5 个去标识候选，给出 lifecycle、证据状态、相同点、差异点、
支持/反对证据、替代根因、反例、责任域候选和下一项区分测量。

历史案例不能证明当前根因，不能自动采用历史修复，也不能扩大写入、IP、
implementation、release 或板级权限。本轮不要修改产品文件。
```
