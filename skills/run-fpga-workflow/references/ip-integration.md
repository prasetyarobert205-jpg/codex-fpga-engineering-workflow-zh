# 官方厂商 IP 集成

仅在新增、重生成、升级、复制、修复厂商 IP，或 IP output products、仿真模型、约束无法重现时读取本参考。

## 所有权

`fpga_engineer` 的 `IP_INTEGRATION` 模式是 versioned IP 配置和官方再生成 recipe 的唯一默认写入者。`fpga_vendor_platform_reviewer` 独立审核 IP 身份、工具/target、端口与时序契约、生成产物和 reopen 证据。任何角色都不得发明近似 primitive/IP model 作为正式模型。

## 最快决策顺序

1. 当前工程已管理的官方 IP 身份、状态、端口、参数、latency/reset 和 target 全部匹配时，直接复用。
2. 只缺 output products 时，用当前已确认工具增量生成。
3. 复制或旧配置先检查 source view 和 output ownership；在当前工程 staging/import，或用本机官方工具重建，禁止覆盖另一个 checkout。
4. 新 IP 且官方 Tcl/CLI recipe 已确认时，使用 batch 生成。
5. 当前版本的参数或官方接口无法由手册、本机 Help 或命令证明时，只操作官方 GUI 一次，立即导出可复现配置/recipe，以后转为脚本化流程。

联网资料只用于同版本官方手册、参数语义、命令、示例和已知限制；不得把网上找到的 XCI、IDF、IPC 直接复制为产品配置。

## 证据深度

### `IP_DISCOVERY`

- 确认 vendor、tool/version、part；
- 定位当前官方 IP 对象和配置；
- 比较 module/entity、port、width、parameter 和所需行为；
- 决定 reuse、regenerate、upgrade、recreate 或 GUI-once。

本阶段不生成 IP，也不签发接受结论。

### `IP_PREPARE`

- 通过本机官方工具创建或定制；
- 生成 XCI/IDF/IPC 或厂商等价 managed configuration；
- 工具支持时保存 versioned 官方 recipe；
- 只生成集成所需 output products。

### `IP_INTEGRATION_ACCEPTANCE`

- 必要时 clean regeneration；
- 唯一官方 IP identity/status；
- tool/version/part；
- port/width/parameter contract；
- latency、reset、busy、FIFO/RAM mode；
- output products 和适用的 OOC synthesis；
- IP 约束及 processing scope；
- 仿真模型、库、导出的 define/include；
- 关闭并重新打开 canonical 工程后 IP 仍处于 managed 状态；
- 明确 upgrade delta。

## 三厂商边界

- Xilinx/Vivado：优先使用本机 Catalog Tcl，例如 `create_ip`、已确认 `CONFIG`、`generate_target`、IP run/status 和工具导出的 IP Tcl；不得假设网上 XCI 兼容。
- Pango/PDS：使用当前版本官方 IPC/IP Generator、IDF 和已证明的导出 recipe；不得发明类似 Vivado 的 CLI。
- Anlogic/TD：使用当前版本官方 IP Generator、IPC/RTL/constraint 产物和已证明的 flow Tcl；不得跨版本推测命令。

GUI 自动化是一次性兜底，不是长期构建流。
