# FPGA 任务类型与路由

仅在任务属于相应类型时加载本参考；不要为无关任务扩展上下文。

## RTL 数据通路或状态机

- Lead：明确输入输出契约、吞吐、延迟、背压、缓存深度、数值精度、溢出/饱和和错误恢复。
- 预审：verification + CDC/timing；若有外部 IO 再加 platform/board。
- 写入：`fpga_engineer` 修改 RTL、必要约束和构建文件。
- 验收：定向/边界/随机背压/复位测试；状态机非法状态恢复。若修改可能影响综合结构、Fmax、约束或目标器件，综合与 STA 是签核证据；工具不可用时必须标为 `UNVERIFIED`，不得给出无条件 `PASS`。
- 对非平凡时序、流水线、FIFO/RAM、valid/ready 或 reset/error 语义，建立 snapshot、impact cone 和 cycle contract；FULL 或高风险任务可在基线审核后调用 Shadow `fpga_temporal_evidence_reviewer`。QUICK 默认不调用。
- 单时钟、小范围并不自动等于 QUICK；只要可观察 latency、throughput、stall/flush/reset/error 或 data/valid/sideband 对齐发生变化，就进入 FULL。仅路径、注释、局部脚本或不改变可观察契约的最小实现可保持 QUICK。
- 工具/路径诊断和 smoke run 使用 DIAGNOSTIC_SMOKE 即可；只有 FUNCTIONAL_ACCEPTANCE 才要求完整 independent model/checker/canary 证据，formal、CDC/STA、电气或发布按需使用 SPECIALIST_ACCEPTANCE。
- 逐拍审查限制为一个主时钟域和一个 transaction cone，包含反向 ready 与 sideband；超范围返回 `NEEDS_PARTITION`。

## 寄存器、命令、IRQ 或 DMA

- 优先找到单一寄存器来源；推荐由 YAML/SystemRDL 等生成 RTL、固件头文件和文档，禁止分别手改多份定义。
- CSR 用于低频配置/状态；高频命令考虑 mailbox/command queue；大数据使用 DMA/stream，不把所有交互都塞进海量 CSR。
- 预审：register/interface + verification；跨域时加 CDC/timing。
- 必查：地址、对齐、宽度、端序、字节使能、复位值、RO/RW/W1C/RC/self-clear、保留位、读写副作用、版本 ID、原子快照。
- W1C 清除与同周期新事件的竞争优先级必须显式定义并测试；默认设计目标是不吞掉新事件，但不得跳过现有协议或用户确认。IRQ 的 raw/status、mask、ack/clear、reassert 与并发事件语义必须形成契约。
- DMA 必查对齐、边界、所有权、背压、缓存一致性、超时、中止与恢复。

## CDC、复位或时序问题

- 预审：CDC/timing + verification；厂商原语/时钟资源相关时加 platform/board。
- 单比特电平、脉冲、多比特控制、计数器和数据流分别选择同步器、握手/toggle、Gray 或 async FIFO。
- 检查 reconvergence、复位释放、脉冲可见性、数据稳定窗口、同步器属性和 MTBF 假设。
- false path/multicycle 不能掩盖结构错误；结构正确与约束正确分别给证据。

模式按声明分层：`CDC_STRUCTURE`、`STA_COVERAGE`、`PHYSICAL_QOR`、
`TIMING_CLOSURE`。异步 FIFO 缺少约束时分别报告结构证据与 timing
coverage；不能直接归类 DUT_FAIL。compile/smoke 不触发完整 P&R。功耗默认
NOT APPLICABLE。

## 官方 IP 集成

- 写入：`fpga_engineer / IP_INTEGRATION`；审核：vendor platform。
- 先做 `IP_DISCOVERY`：复用 managed IP、增量生成、staging/import、官方
  Tcl/CLI 重建或 GUI-once 五选一。
- 新 IP 优先使用本机同版本官方 Tcl/CLI；互联网用于官方文档/参数/命令，
  不直接提供产品 XCI/IDF/IPC。
- 只有 `IP_INTEGRATION_ACCEPTANCE` 才要求完整 proof packet、OOC、XDC、
  simulation model 和 canonical project reopen。
- 端口、位宽、latency、reset、busy 和 FIFO/RAM mode 是设计契约，不能因
  官方工具生成成功而省略。

## 物理实现和时序收敛

- 只在 `IMPLEMENTATION_QOR/TIMING_CLOSURE` 或真实 routed 报告触发。
- 冻结基线，分类 logic/route/fanout/congestion/clocking/RAM-DSP-GT-IO/
  constraint 根因，一次改变一个主变量并比较后保留或回滚。
- 不默认换 seed/strategy、全局 Pblock、连续 phys-opt、复制全部高扇出
  寄存器或插入流水线。
- power 默认 NOT APPLICABLE；只有明确功耗/热/安全/release 预算才启用。

## 多厂商平台迁移

- 公共层：寄存器/命令、协议、调度、数据格式、缓存/运动状态机、编码器位置计算和故障管理。
- 平台层：PLL/时钟缓冲、IOBUF/LVDS、IDDR/ODDR/SERDES/IODELAY、BRAM/FIFO/DDR、收发器/PCIe、启动 Flash、片上调试、引脚和时序约束。
- 为同一接口提供 portable baseline 与 vendor-optimized implementation，由 target 选择文件列表。
- 禁止在 common RTL 到处散落厂商条件编译；禁止为每家厂商复制完整产品 RTL 或维护长期厂商分支。
- 每个厂商/器件/板卡是独立构建 target，可保留原生 EDA 工程，但共享公共 RTL 和验证。验收矩阵逐 target 记录器件、工具版本、命令、状态和报告路径。
- 自动脚本第一阶段只识别 Xilinx `.xpr/.xci`、Pango `.pds/.idf`、Anlogic `.al/带明确标记的 .ipc`；冲突、未知或其他厂商必须 fail closed。正式工程一次只物化一个厂商 adapter。

## 喷头、编码器与运动同步

- 明确位置/时间基准、编码器分辨率、方向、滤波、丢脉冲/反向处理、触发延迟与机械误差预算。
- 明确打印数据吞吐、行缓存、DDR/DMA、喷印窗口、nozzle mapping、脉冲宽度与安全禁止条件。
- 任何手册参数必须给出准确型号、文档版本、页码/表格；相似型号不能替代。
- 仿真、逻辑分析、示波器测量、空载/假负载测试和真实喷头测试分阶段进行。

## 文件所有权与并行边界

- 产品 RTL/约束/构建脚本：默认仅 `fpga_engineer` 写。
- 固件/驱动：只有接口契约明确要求时由 `embedded_engineer` 在 FPGA 写入结束后的独立批次写；不得与其他写入者共用同一 checkout 并行。
- TB/assertion/reference model：`verification_engineer` 可写，但默认与产品写入顺序执行。只有用户明确同意、文件完全不重叠并使用独立 worktree/分支时才能并行写，且签核前必须先集成为一个 diff。
- 报告和临时输出：每个角色独立目录，所有 Codex 过程文件统一放在项目根目录 `codex_out/<run-id>/`。
- 厂商 IP 生成目录、二进制数据库、加密源、工程 cache：默认不手改、不提交；只有 `IP_INTEGRATION` 可通过官方工具写 versioned 配置/recipe 和正式 output products。
- 寄存器源文件修改前必须确认它是唯一来源；生成物应由既有生成器更新。

## 终审最低证据

- 需求与验收条件明确，或未知项被列为阻塞条件。
- diff 与用户已有改动区分清楚。
- 受影响测试有真实结果；失败/跳过/未运行没有被隐藏。
- CDC/RDC、约束、综合、STA 按变更影响提供真实报告或明确标为未验证。
- 对可能影响时序、约束或目标器件的变更，缺少综合/STA 证据时最多给出带条件结论；不得把工具不可用等同于通过。
- FPGA、固件、硬件/手册之间的接口定义一致。
- 安全输出和上板步骤有人工确认门。
- 仿真 PASS 具有独立 model/checker 来源、逐拍 due-cycle/window 证据、negative canary 和独立只读审核；验证资产作者不能自签。
- 所有工件、报告和 findings ledger 引用同一冻结 snapshot；旧报告不得签核新代码。
