# QUICK 示例

```text
使用 $run-fpga-workflow，以 QUICK 模式完成这个已明确授权、单时钟、接口和 latency 不变的局部 RTL 修复。
保护我现有改动；由架构师限定范围，唯一产品写入者做最小修改，在 codex_out 下运行隔离测试，再经过 verification review 和独立 final review。
除非证据显示可观察周期风险，否则不调用 Shadow 逐拍 reviewer。无法运行的 synthesis/STA 标为 UNVERIFIED。
```
