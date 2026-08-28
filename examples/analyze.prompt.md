# ANALYZE 示例

```text
使用 $run-fpga-workflow，以 ANALYZE 模式只读审核当前 CDC warning，不修改文件。
读取项目规则、clock/reset 来源、RTL crossing、constraint 和真实 CDC/STA 报告。
区分 CONFIRMED、INFERRED、UNKNOWN；按严重度输出 finding 和缺失证据。
不要压低 warning，也不要在没有当前报告时声称 timing closure。
```
