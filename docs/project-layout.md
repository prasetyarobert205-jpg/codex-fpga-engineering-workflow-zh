# FPGA 工程目录与文件存放位置

[中文导航](README.md) · [整体架构](architecture.md) · [安装](installation.md) · [使用](usage.md)

本工作流新建和正式整理的 FPGA 工程统一使用以下标准目录结构，用于区分产品源码、厂商工程、仿真资产、正式输出和 Codex 临时文件。只有外部旧工程在只读分析或导入阶段可以暂时保持原布局；进入正式整理阶段后，应使用本标准目录结构。

## 标准目录结构

```text
<fpga-project>/
├─ README.md
├─ AGENTS.md
├─ .gitignore
│
├─ document/                 # 需求、接口、寄存器、设计说明和验证计划
│
├─ project/
│  ├─ rtl/                   # 产品 Verilog/SystemVerilog/VHDL 源码
│  ├─ ip/                    # 厂商 IP 配置、wrapper 和可复现生成 recipe
│  ├─ sdc/                   # 时钟、I/O、时序例外等约束
│  ├─ par/                   # 厂商工程、综合/实现数据库、日志和报告
│  └─ script/                # 用户正式编译/构建入口和维护型 Tcl/CLI
│
├─ simulation/
│  ├─ tb/                    # testbench、checker、model、assertion
│  │  └─ case/               # 不同功能、边界和回归用例
│  ├─ script/                # 仿真入口、setting、source list、vsim.do
│  └─ work/                  # 正式仿真库、导出文件、日志、WLF 和波形
│
├─ linter/
│  ├─ lint_bb/               # lint 所需 black-box 声明，可选
│  └─ script/                # lint 入口和 lint_list.txt
│
├─ release/
│  ├─ golden/                # 受保护的 golden image，可选
│  └─ output/                # 经审核后交付的 bit/bin/mcs 和清单
│
└─ codex_out/                # Codex 诊断、索引、临时构建和审查证据
```

## 各目录放什么

| 目录 | 建议存放内容 | 不建议放入 |
|---|---|---|
| `document/` | 需求、接口协议、寄存器说明、时钟复位说明、验证计划、手册引用 | 厂商运行数据库、波形、临时日志 |
| `project/rtl/` | 产品 RTL、公共 package/interface、平台 wrapper | 自动生成 cache、仿真 work 库 |
| `project/ip/` | XCI/IDF/IPC 等可版本化配置、IP wrapper、官方生成 recipe | 另一工程的绝对输出路径、无法重建的临时产物 |
| `project/sdc/` | 主时钟、生成时钟、I/O delay、clock group、必要例外约束 | 为了让报告变绿而加入的宽泛 false path |
| `project/par/` | Vivado/PDS/TD 工程、综合/布局布线数据库、原生日志和报告 | Codex mutation、临时 review 副本 |
| `project/script/` | `run.bat`、项目 setting、canonical source list、厂商 Tcl/CLI | `.Xil`、工程数据库、自动导出库、波形 |
| `simulation/tb/` | TB、reference model、checker、assertion、scoreboard | 产品综合源和厂商实现数据库 |
| `simulation/script/` | `run.bat`、`setting.txt`、`src_list.txt`、`vsim.do` | ModelSim work 库、WLF、自动生成日志 |
| `simulation/work/` | ModelSim/Questa work、`modelsim.ini`、compile/load/run 日志、WLF、波形 | 需要长期手工维护的正式脚本 |
| `linter/` | lint 配置、black box 和 lint source list | 综合、实现或仿真大型数据库 |
| `release/output/` | 经过审核的 bit/bin/mcs、版本说明、hash、manifest | 未确认来源的临时构建产物 |
| `codex_out/` | Codex 索引、诊断副本、临时库、mutation、findings 和 proof packet | 正式产品源、正式 release、用户长期维护脚本 |

## 常见输出应该放在哪里

| 操作 | 输出位置 |
|---|---|
| 厂商综合、实现、时序分析 | `project/par/` |
| 正式 ModelSim/Questa 编译和运行 | `simulation/work/` |
| lint 日志和报告 | `linter/` 对应输出目录或项目既有位置 |
| 经审核的配置文件和交付产物 | `release/output/` |
| 受保护的 golden image | `release/golden/` |
| Codex 临时测试、索引、审查和故障复现 | `codex_out/<run-id>/` |

## 脚本目录为什么要保持简洁

`project/script/` 和 `simulation/script/` 是用户直接查看和运行的入口层。把数据库、自动导出脚本、work 库、日志和波形混在这里，会导致：

- 用户难以判断哪个文件需要维护；
- 复制工程后携带旧路径和旧库映射；
- 工具隐式输出污染 source list 和脚本；
- Codex 诊断文件与正式用户结果混淆。

因此，脚本目录只保存人工维护入口和配置；运行过程文件进入对应正式输出目录，Codex 自己创建的临时内容进入 `codex_out/`。

## 正式输出与 Codex 输出的区别

```text
用户正式运行的厂商工程和实现结果
→ project/par/

用户正式运行的仿真库、日志和波形
→ simulation/work/

经过审核后需要交付的文件
→ release/output/

Codex 为诊断、索引、变体和审查创建的内容
→ codex_out/<run-id>/
```

这样可以保证用户双击正式脚本时得到的位置稳定，也可以在调试结束后安全清理 Codex 过程文件，而不会误删正式工程结果。
