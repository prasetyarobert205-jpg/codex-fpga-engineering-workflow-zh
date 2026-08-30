# 仿真证据与独立接受

## 按结论选择证据深度

- `DIAGNOSTIC_SMOKE`：定位 path/tool/library/compile 故障，或证明 compile/elaborate/有限运行；可以返回 `DIAGNOSTIC_ONLY`，独立 model、coverage、canary 在与诊断目标无关时不强制。
- `FUNCTIONAL_ACCEPTANCE`：应用本文件全部独立接受规则；只有必要证据齐全时才能签发 `SIMULATION_PASS`。
- `SPECIALIST_ACCEPTANCE`：formal、CDC/STA、电气或发布证据交给对应专项和 final reviewer，不把它们错误塞进 simulation PASS。

不得因为 smoke 有意不包含功能 oracle 而判 smoke 失败；也不得把 smoke 冒充功能接受。

## 可选波形观察

波形证据按 applicability 启用。用户/验证计划明确要求、checker/log/assertion 矛盾、first-failure 局部定位或关键/最终 case 人工复核时使用；普通 smoke、路径诊断和纯源码解释不强制读取波形。

波形探测只拥有 observed values 和执行/query receipts。需求或独立 model 拥有 expected，checker 拥有 comparison，逐拍 reviewer 只能给出 `INFERRED/UNKNOWN` 因果，final reviewer 集成最终结论。若当前结论依赖波形查询，应绑定同一 snapshot/run/case/seed，并记录真实 simulator/converter/query 过程、输入波形 hash、查询窗口、结果和局限。详细规则见[按需、有界的波形观察](waveform-observation.md)。

`COMPLETE`、`CROSS_REFERENCE_CONSISTENT`、GUI 可见或 observed values 匹配都不能单独建立 `SIMULATION_PASS`。波形不适用时记录 `NOT_APPLICABLE`；适用但缺失、截断或无法确认时为 `INCONCLUSIVE`；任何 `CONTRADICTORY` 立即撤销受影响的接受结论。

## 作者与审核者分离

`verification_engineer` 可在授权的顺序写入批次中创建或修复 TB、model、checker、assertion 和脚本；作者报告原始结果，但不能独立签发自己新写或修改资产的 `SIMULATION_PASS`。

Shadow `fpga_temporal_evidence_reviewer` 严格只读，审核冻结 snapshot 的逐拍证据，但不能签发整体产品 PASS。

## Model 独立性

每个设备、协议或参考 model 都需要 Model Card。适用时优先使用准确厂商模型；自定义 model 必须引用当前规格、接口合同、datasheet 或已确认事实。

下列内容不能作为独立证据：

- 把 DUT RTL 复制进 expected logic；
- checker 读取 DUT 内部状态来决定 expected latency/data；
- 观察 DUT 输出后修改 expected；
- 用 white-box force/bypass 证明被绕过功能；
- 使用其他器件/工具版本或近似 vendor primitive model。

未知行为保持 `UNKNOWN/UNVERIFIED`。

## Cycle-indexed 检查

在真实 acceptance edge（例如 `valid && ready`）采集 input payload、tag、configuration、reset context 和 expected due cycle/window。输出侧检测：early、late、missing、duplicate、reorder、data、metadata、status、error mismatch。

必须覆盖：

- 固定或可变 latency contract；
- stall 时 pipeline 是否冻结；
- reset/flush/abort 对 in-flight token 的处理；
- NBA/clocking-block 后无 race 采样；
- X/Z policy；
- FIFO/RAM/DSP/vendor model latency；
- PASS 前 scoreboard 完整 drain。

## Negative Canary

每个关键 checker 至少证明一种相关错误会被拒绝：提前/延后一拍、bit flip、drop、duplicate、reorder、stall 错推进、reset 泄漏、handshake 边界错误、FIFO under/overflow。只能注入 verification wrapper、bind、fault injector 或可丢弃 `codex_out` 变体。

正确设计必须通过，注入错误必须失败。如果 canary 也通过，正向结果不能接受。

## Proof Packet

波形观察适用时，保留最小因果窗口，通常从 input/config acceptance 前 2–4 拍，到最终 output/ack/error 后 2–4 拍。包含 clock/reset、接口 data/control/metadata、相关 FIFO flag/count、error/flush 和诊断必需的最少内部状态。

保存：

- 适用时的选定 waveform；
- `cycle-table.csv`；
- `expected-vs-actual.csv`；
- assertion/scoreboard summary；
- case、seed、tool/version、command、snapshot；
- 失败时 `first-failure.json`。

## 结果分类

只能返回其中一个：

```text
DUT_FAIL
TESTBENCH_FAIL
REFERENCE_MODEL_FAIL
ASSERTION_FAIL
SCRIPT_PATH_FAIL
COMPILE_ELAB_FAIL
TOOL_ENV_FAIL
VENDOR_LIBRARY_FAIL
TIMEOUT_HANG
INCONCLUSIVE
DIAGNOSTIC_ONLY
SIMULATION_PASS
```

`SIMULATION_PASS` 要求完整追踪、独立 model/checker、正确 compile/elaboration/run、checker 排空、必要逐拍证据和被拒绝的 negative canary。新工件用 `waveform_consistency=NOT_APPLICABLE` 表示当前结论不需要波形，用 `CONSISTENT` 表示被依赖的波形与其他证据一致；`INCONCLUSIVE` 或 `CONTRADICTORY` 不能支持 PASS。只含 `manual_waveform_consistent=true` 的旧工件继续兼容，但新旧字段互斥。人工证据一旦矛盾，立即撤销 PASS 并建立验证资产缺陷。
