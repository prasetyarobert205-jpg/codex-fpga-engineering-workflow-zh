# 私有故障案例晋级复核提示词

```text
只读复核一个 IMPORTED 私有故障案例，不修改案例、项目或全局配置。
检查源引用/hash、根因证据、修复对应关系、修复前失败/修复后通过、替代根因、
回退或负向canary、vendor/tool/version/part/clock/reset/interface/trigger、
适用范围、反例、独立复核和用户确认的真实工程/板级处置。

只能建议 KEEP_IMPORTED / PROMOTE_TO_ROOT_CAUSE_CONFIRMED /
PROMOTE_TO_FIX_VERIFIED / PROMOTE_TO_BOARD_CONFIRMED / PROMOTE_TO_REUSABLE /
REJECT / NEEDS_MORE_EVIDENCE。原文“已解决”或“通过”不能自动晋级。

输出 CONFIRMED、INFERRED、UNKNOWN、支持证据、阻止晋级的缺口和建议状态。
任何实际晋级仍需独立写入授权。
```
