# 正式 FPGA 工程目录与一键工具流

新建或正式归一化工程默认使用下列目录；更严格的项目 SSOT 优先：

```text
<root>/
├─ README.md
├─ AGENTS.md
├─ .gitignore
├─ document/
├─ project/
│  ├─ rtl/
│  ├─ ip/                  # 使用时才创建
│  ├─ sdc/
│  ├─ par/
│  │  ├─ <project-name>.xpr|.pds|.al
│  │  └─ <project-name>.* 厂商数据库/报告
│  └─ script/
│     ├─ run.bat
│     ├─ setting.bat
│     ├─ src_list.txt
│     └─ 一个已确认厂商 Tcl/CLI flow
├─ simulation/
│  ├─ tb/case/
│  ├─ work/                # 正式 ModelSim/Questa 运行态
│  └─ script/
│     ├─ run.bat
│     ├─ setting.txt
│     ├─ src_list.txt
│     └─ vsim.do
├─ linter/
│  ├─ lint_bb/             # 使用时才创建
│  └─ script/
│     ├─ run.bat
│     └─ lint_list.txt
├─ release/
│  ├─ golden/              # 需要时才创建
│  └─ output/
└─ codex_out/              # 仅 Codex 诊断/审查，Git 忽略
```

`project`、`project/par`、`project/script` 是标准名称；禁止 `project2`、`par2`、`script2`、`scriptC`。外部旧工程可以作为导入源，但新生成的 canonical output 使用无后缀标准目录。

canonical launcher 必须是 `project/par` 的直接子文件：`<name>.xpr`、`<name>.pds` 或 `<name>.al`。同名厂商数据库直接位于 `project/par`。新工程若生成 `project/par/vivado_project/<name>.xpr`、`par/build` 或随机 job 容器，目录合同 FAIL。

可见 `script` 根保持干净。`project/script` 只放入口 BAT、项目设置、canonical list 和唯一厂商维护型 Tcl/CLI。`simulation/script` 默认且优先只放四个文件；自动导出的 `compile.do`、`modelsim.ini`、`.Xil`、库、日志、WLF 和波形全部属于运行态，进入 `simulation/work`。

## 一键入口合同

每个 `run.bat`：

- 用 `%~dp0` 定位；
- 所有路径加引号；
- 调用已确认的厂商原生 Tcl/DO/CLI；
- 传播真实非零退出码；
- 不依赖调用者 CWD 或 Codex 私有 `pwsh.exe`；
- 不修改全局 PATH、注册表或库映射；
- 启动工具前切到 `project/par` 或 `simulation/work`，避免 `.Xil`、journal、临时约束和数据库污染脚本目录。

正式 BAT 不写死绝对 executable。`setting.bat` 只保存项目确认的工具根或环境 selector，在当前 BAT 进程 prepend PATH，使用 `where` 检查 `vivado`、`vsim` 等标准命令，再按名字调用。

每次 build/sim/lint：

1. 解析工程根；
2. 检测唯一支持厂商；
3. 原子更新 canonical filelist；
4. preflight target、source、tool、library、case 和输入；
5. 创建或更新正式输出，Codex 诊断变体使用唯一 `codex_out/<run-id>`；
6. 调用唯一 adapter；
7. 记录命令、工具版本、脱敏环境、日志、退出码和结果分类。

ModelSim/Questa 必须执行真实 compiler 和 simulator stage。双击默认 GUI，`batch` 支持自动 smoke。Xilinx IP 仿真先生成 output products 并执行 `export_ip_user_files`；根据当前 Vivado 实际导出产物调用，不猜文件名。若 Windows 只生成 shell driver + `compile.do`，由 ModelSim 执行 `compile.do`，先创建需要的 `modelsim_lib` 父目录，使用 job-local `modelsim.ini`，compile 失败后不得继续 load。

检查导出命令是否保留项目 define/include。确认某版本遗漏时，可在官方 IP 模型编译后，由标准 `vsim.do` 按 canonical RTL/TB list 和已确认 define 重编译项目代码；禁止用近似 IP model。

复制或旧 XCI/IDF/IPC 在生成前必须核对是否携带另一 checkout 的输出路径；在当前 `project/par` staging/import，或用已确认版本的官方 Catalog/Tcl recipe 重建，禁止跨 checkout 覆盖。

## Filelist 合同

- `src_list.txt`：项目 HDL 与选定厂商 IP 配置；
- simulation list：项目 HDL、明确的厂商仿真模型和 TB；
- lint list：仅可 lint HDL。

路径使用工程相对路径、forward slash、稳定顺序、去重并验证存在。header 生成 include-dir，不作为独立 compile unit。重复 module/entity 失败。多个 package/interface 或 VHDL 依赖无法安全判断时，要求明确 `source-order.txt`，不得猜顺序。

## 厂商合同

- Xilinx：权威 `.xpr`，无工程文件时才以 `.xci` 补充；
- Pango：权威 `.pds`；多个 `.pds` 时优先 `project/par/pds_script.pds`，否则要求明确 `VendorProjectFile`；无工程文件时才以 `.idf` 补充；
- Anlogic：权威 `.al`；无工程文件时仅接受带明确 Anlogic/TD/EG 标记的 `.ipc`。

多厂商、其他厂商或无证据均在 adapter 生成前停止。Pango/Anlogic 命令必须来自已确认项目 recipe 或本机工具配置。

## 厂商库

只有 vendor、tool version、family、simulator/version、官方 source 和已验证 recipe 全部准确时才自动编译。Codex cache 位于：

```text
codex_out/_cache/simlibs/<vendor>/<tool-version>/<family>/<simulator-version>/<source-hash>/
```

否则返回 `MISSING_VENDOR_LIBRARY` 和准备清单。

## 清理

PASS 后可清理大型可丢弃 Codex 诊断目录，但保留 manifest、日志、报告和 proof packet。FAIL 保留完整 job。正式 `project/par` 或 `simulation/work` 清理必须是明确 formal clean，并验证解析后的精确目标；Codex 诊断清理只能作用于已确认 `codex_out` 内路径。
