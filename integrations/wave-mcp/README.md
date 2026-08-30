# wave-mcp 可选集成

本目录提供面向 FPGA 工作流的最小 wave-mcp 接入面，不包含完整第三方源码、虚拟环境、二进制包或本机绝对路径。

上游项目：<https://github.com/Tencent/wave-mcp>

上游许可：MIT，见 [LICENSE.wave-mcp](LICENSE.wave-mcp)。

## 包含内容

| 文件 | 作用 |
|---|---|
| `query_adapter.py` | 使用 wave-mcp 公开 API 执行 `point(start) + C+1 range`，只输出 `OBSERVATION_ONLY/DIAGNOSTIC_ONLY` receipt |
| `requirements.txt` | 兼容安装入口，只锁本集成实际验证的 `wave-mcp==0.1.1` |
| `requirements-tested.txt` | 重现实测组合，额外锁定实际运行的 `mcp/pylibfst/pyslang` 直接依赖 |
| `environment.example.json` | 可复制到用户机器本地工具目录的脱敏配置模板 |
| `tested-environment.json` | 从本机真实链提取、去除绝对路径和项目事实后的环境与结果边界 |
| `LICENSE.wave-mcp` | Tencent/wave-mcp 的 MIT 许可文本 |

## 安装位置建议

不要把 Python venv 或 wave-mcp 源码复制进 FPGA 产品仓库。建议在用户控制的工具根中建立独立目录，例如：

```text
<LOCAL_TOOL_ROOT>/wave-mcp/
<LOCAL_TOOL_ROOT>/venv-wave-mcp/
<LOCAL_TOOL_ROOT>/trusted-wave/environment.json
```

`<LOCAL_TOOL_ROOT>` 由用户或机器配置决定；公开 Skill、项目模板和 `AGENTS.md` 不应写死某台机器的路径。

安装示例（Linux/WSL Python）：

```bash
python3 -m venv <LOCAL_TOOL_ROOT>/venv-wave-mcp
<LOCAL_TOOL_ROOT>/venv-wave-mcp/bin/python -m pip install \
  -r integrations/wave-mcp/requirements-tested.txt
```

要探索与更新直接依赖兼容性时可改用 `requirements.txt`；要重现 2026-08-30 的已验证组合时使用 `requirements-tested.txt`。这两个文件都只描述 Python 包，不包含虚拟环境或二进制。已有可用环境时只需记录版本和实现 hash，不要重复安装。

## 准备 session

wave-mcp 只消费波形，不运行仿真器。先用当前项目的正式或诊断流程产生 FST；只有 VCD 时再按本机配置调用 `vcd2fst`。

可以使用上游 `wave-session`/`prepare_session`，也可以生成只含当前 FST 的 session。无论使用哪种方式，证据运行都应额外记录：

- FST SHA-256；
- session manifest SHA-256；
- wave-mcp 版本、server hash、package tree hash；
- case/seed/top/snapshot；
- 查询 signal/window/cap；
- 真实进程退出码与 receipt。

## 最小查询

```bash
python integrations/wave-mcp/query_adapter.py \
  --session sessions/current-case \
  --signal top_tb.dut.valid \
  --start-ps 100000 \
  --end-ps 200000 \
  --transition-cap 1024 \
  --output codex_out/run-id/query/valid.json
```

结果状态：

```text
COMPLETE      当前窗口的 observed query 完成
INCONCLUSIVE 查询缺失、错误、截断或超出预算
```

无论状态如何，adapter 都不会输出 `SIMULATION_PASS`、expected 或确认 root cause。

`tested-environment.json` 中的 package-tree hash 只覆盖已安装 `wave_mcp` 包目录下按相对 POSIX 路径排序的 `**/*.py`；每项为 `<relative-path>:<full-file-sha256>`，以 LF 拼接后再做 SHA-256。清单 validator 只证明公开 JSON 的结构与声明自洽，输出 `MANIFEST_VALID`，不是现场环境已经核验；真实 evidence run 仍需重算版本、直接依赖和实现 hash。

## 使用边界

- 一次性 `DIAGNOSTIC_ONLY` 可以轻量使用，只要记录必要的 snapshot/tool/hash/window/exit/limitation。
- 跨评审复用或功能接受应使用项目级 trusted runner、typed receipts 和包外冻结 root identity。
- 行为模型的波形不能冒充官方 IP 语义；涉及官方 IP mode/latency/reset 时必须使用当前官方配置/模型。
- 当前公开实测只覆盖一个 Xilinx/ModelSim/VCD→FST/wave-mcp 0.1.1 诊断链；不宣称其他厂商、格式或功能签核已验证。
