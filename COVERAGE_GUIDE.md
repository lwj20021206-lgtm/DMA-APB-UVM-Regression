# DMA-APB Coverage 与回归指南

> 面向第一次使用 VCS/UVM 跑 coverage regression 的读者。本文严格按当前仓库中的 `Makefile`、`top.sv`、monitor、coverage 组件和 testcase 解释，不以旧版脚本为准。

## 1. 先建立一个正确的心智模型

当前工程的整体流程可以概括为：

```text
所有 RTL/TB/coverage/test class
             |
             | make vcs_build（只编译一次）
             v
      simv + simv.vdb 设计信息
             |
             | make vcs_run TEST=<test> SEED=<seed>
             v
       一次仿真只运行一个 test
             |
             | -cm_name <TEST>_<SEED>
             v
       本次命中写入 simv.vdb
             |
             | 多个 test/seed 串行运行
             v
   Verdi 在 All Tests/Total 视图中看累计结果
```

请先记住三句话：

1. **把所有 test 编译进 `simv`，不等于一次仿真会运行所有 test。**
2. **每次 `simv` 进程的 covergroup 计数都从 0 开始；跨 test 累计发生在磁盘上的 `simv.vdb`，不是同一个 SystemVerilog 对象始终活着。**
3. **累计覆盖率是多次仿真命中点的并集，不是各次百分比的算术平均。**

例如，某 coverpoint 只有两个 bin：

```text
test A 只命中 bin0：50%
test B 只命中 bin1：50%
累计结果命中 bin0 + bin1：100%
```

累计结果显然不是 `(50% + 50%) / 2 = 50%`。

---

## 2. 不要把“正确性”和“覆盖率”混在一起

本工程同时有以下几套机制：

| 机制 | 回答的问题 | 当前工程中的来源 |
|---|---|---|
| Scoreboard | DUT结果是否正确 | `apb_device_scoreboard.sv` |
| UVM report | 仿真是否有error/fatal | `UVM_ERROR/UVM_FATAL` summary |
| Assertion | 时序/协议property是否违反 | `apb_device.v` 中的 P1～P6 |
| 功能覆盖率 | 验证计划关心的场景是否发生 | 9个SystemVerilog covergroup |
| 代码覆盖率 | RTL代码结构是否被激活 | VCS `-cm` 自动插桩 |
| FSDB波形 | 某次仿真的信号怎样变化 | `waveform.fsdb` |

它们之间不能相互替代：

- scoreboard PASS 不代表覆盖率已经足够；
- bin 命中不代表 DUT 结果正确；
- 代码覆盖率高不代表功能覆盖率高；
- 有 FSDB 波形不代表已启用 coverage；
- `WAVE=0` 只是关闭波形，不会关闭 coverage。

当前 `scripts/check_run.sh` 只负责判断仿真 PASS/FAIL，它会检查：

- simulator 退出码是否为 0；
- log 是否生成；
- 是否出现 `Simulation Failed.`；
- 是否出现 assertion failure；
- `UVM_ERROR : 0`和`UVM_FATAL : 0`是否存在。

**它目前没有设置覆盖率门槛。**因此 `make regression` PASS 只说明这13次仿真没有被正确性检查抓到错误，并不等于 coverage 达到了退出目标。

---

## 3. 两大类 coverage

### 3.1 VCS代码/断言覆盖率

`Makefile` 中的开关是：

```make
CM_FLAGS ?= -cm line+cond+tgl+fsm+branch+assert
```

| Metric | 大致含义 |
|---|---|
| `line` | 可执行语句/代码行是否执行过 |
| `cond` | 布尔条件及其子条件是否出现不同取值/组合 |
| `tgl` | 信号各bit是否出现 `0→1`和`1→0` |
| `fsm` | 工具识别到的状态和状态转移是否走过 |
| `branch` | `if/else/case`等分支是否走过 |
| `assert` | assertion是否被attempt、pass或fail |

编译阶段和运行阶段都带上了同一组 `CM_FLAGS`：

- 编译阶段：让 VCS 对设计插桩，建立覆盖模型；
- 运行阶段：开启计数并把命中数据写入 VDB。

当前没有使用 `-cm_hier` 限制代码覆盖范围，所以 Verdi 顶层视图可能同时看到 RTL、TB 甚至已编译库代码的统计。对 DUT 做签核分析时，应优先展开 `top.DUT`，不要把最顶层总百分比直接当成 DUT 代码覆盖率。

### 3.2 SystemVerilog功能覆盖率

功能覆盖率模型集中在：

```text
apb_device_src/apb_device_coverage_full.sv
```

它不是工具根据 RTL 自动推导出来的，而是验证人员显式定义：

```systemverilog
coverpoint ... {
  bins ...;
}

cross coverpoint_a, coverpoint_b;
```

然后在有意义的事件发生时调用：

```systemverilog
covergroup_instance.sample(...);
```

功能覆盖率回答的是“我在 testplan 中关心的场景是否被观察到”，例如：

- INIT/COPY是否都执行过；
- LEN=1、普通长度、LEN=16、非法长度是否出现过；
- COPY的equal/overlap/adjacent/disjoint是否出现过；
- 上下游APB读写是否遇到各种wait-state；
- interrupt和dma busy是否拉高和清零过。

---

## 4. 编译时到底发生了什么

### 4.1 `filelist.f`只列了`top.sv`

当前 `filelist.f` 的主要内容是：

```text
+incdir+.
top.sv
```

`top.sv` 再通过 `` `include `` 依次文本展开：

- `apb_device.v`；
- interface、item、driver、monitor、sequencer和agent；
- coverage、scoreboard和env；
- sequence和所有test class。

因此所有 test class 都在一次编译中进入同一个 `simv`，并通过UVM factory注册。

`Makefile` 里的 `SOURCE_FILES` 不是把这些文件再编译一次，它们只是 Make 的依赖列表：任何源码比 `simv` 新时，Make 会知道需要重编。

### 4.2 `make vcs_build`

命令：

```bash
make vcs_build
```

关键参数：

```text
-cm line+cond+tgl+fsm+branch+assert
-cm_dir simv.vdb
-o simv
```

编译阶段会生成：

| 产物 | 用途 |
|---|---|
| `simv` | 仿真可执行文件 |
| `simv.daidir/` | VCS/Verdi设计调试信息 |
| `csrc/` | VCS生成的编译中间文件 |
| `compile.log` | 编译日志 |
| `simv.vdb/` | 覆盖模型/设计信息，运行后再增加hit数据 |

编译完成仅代表“可以收集”，还没有激励运行，因此不能把它当成已经获得了有意义的coverage。

---

## 5. 一次test运行时发生了什么

例如：

```bash
make vcs_run TEST=dma_apb_copy_test SEED=7
```

Make先检查`simv`是否存在以及源码是否更新。如果需要，它会自动执行`vcs_build`，所以平时可以直接用`make vcs_run`。

真正的运行参数包括：

```text
+UVM_TESTNAME=dma_apb_copy_test
+ntb_random_seed=7
+DMA_RANDOM_OPS=40
-cm_dir simv.vdb
-cm_name dma_apb_copy_test_7
```

各参数的职责不同：

| 参数 | 作用 |
|---|---|
| `+UVM_TESTNAME` | 选择本次要创建的UVM test class |
| `+ntb_random_seed` | 控制SystemVerilog/UVM随机数序列 |
| `+DMA_RANDOM_OPS` | 控制`dma_apb_random_test`的随机操作数 |
| `-cm_dir` | 指定覆盖率数据库位置 |
| `-cm_name` | 给本次run在VDB中的test record命名 |

`+UVM_TESTNAME` 和 `-cm_name` 不是一件事：

- `+UVM_TESTNAME` 决定仿真里真正跑哪个test；
- `-cm_name` 只是覆盖数据库中这次运行的身份标签。

`top.sv` 调用：

```systemverilog
run_test();
```

UVM读取`+UVM_TESTNAME`，每次只创建一个`uvm_test_top`。所以“所有test都include了”不代表“所有test都跑了”。

运行完成后主要产物是：

- `sim.log`：当前单次仿真日志；
- `waveform.fsdb`：当`WAVE=1`时生成，下次单测会覆盖；
- `simv.vdb/`：增加一条名为`dma_apb_copy_test_7`的run record及其命中数据。

---

## 6. 功能覆盖率的真实采样链

本工程的coverage数据不是sequence直接写进covergroup的。Sequence负责生成激励，monitor/interface负责观察DUT真实行为，coverage再对观察结果分类。

### 6.1 上游已完成事务

```text
DUT上游APB
  → APB_MINTF
  → apb_master_monitor
  → aPort.write(item)
  → env.connect(coverage_full.master_imp)
  → write_apb_master_cov_full(item)
  → cg_master_access / cg_dma_command / cg_interrupt
```

master monitor 只在真正握手时发布 item：

```systemverilog
psel && penable && pready
```

因此这条链记录的是**已完成的CPU侧APB事务**，不是刚进入setup的请求。

`uvm_analysis_imp_decl(_apb_master_cov_full)` 生成带后缀的implementation port类型。当analysis port向`master_imp`write时，UVM最终回调：

```systemverilog
write_apb_master_cov_full(apb_master_item item)
```

### 6.2 下游请求

```text
DUT下游APB setup
  → APB_SINTF
  → apb_slave_monitor.aPort
  → coverage_full.slave_imp
  → write_apb_slave_cov_full(item)
  → cg_slave_request
```

采样条件是：

```systemverilog
psel && !penable
```

因此`cg_slave_request`只能证明DUT发出了下游请求，**不能证明请求最后完成**。

### 6.3 下游真正完成的事务

coverage组件不依赖slave monitor的`completed_ap`，而是通过virtual interface直接观察：

```systemverilog
slave_psel && slave_penable && slave_pready
```

完成后调用：

```systemverilog
cg_slave_completion.sample(...);
cg_apb_wait.sample(...);
```

所以：

- `cg_slave_request`：请求有没有发出；
- `cg_slave_completion`：请求有没有真正握手完成。

这两者之间的差异对定位wait-state、hang和事务丢失非常重要。

### 6.4 上下游wait、reset和白盒probe

coverage组件在`run_phase`fork了3个监控任务：

- `monitor_master_interface()`：上游wait、reset时机、busy时发起的访问；
- `monitor_slave_interface()`：下游wait和完成事务；
- `monitor_probe_interface()`：interrupt与DMA busy电平/跳变。

`top.sv`将白盒probe连到：

```systemverilog
COV_PROBE.interrupt = apb_device_int;
COV_PROBE.dma_busy  = DUT.is_dma_busy;
```

由于这里直接层次引用了DUT内部`is_dma_busy`，`cg_probe_state`和`cg_busy_attempt`包含白盒覆盖内容。

---

## 7. 9个covergroup分别记录什么

| Covergroup | 何时sample | 主要coverpoint/cross | 能证明什么 |
|---|---|---|---|
| `cg_master_access` | 每笔上游握手完成 | region、R/W、LEN值、写数据类、region×RW | CPU完成过哪些类型的访问 |
| `cg_dma_command` | 完成INIT/COPY写 | 命令、LEN类、COPY地址关系、INIT数据类、配置完整性及交叉 | 哪些DMA命令组合发生过 |
| `cg_interrupt` | 完成DMA_INT读/写 | 4类状态位、状态组合、W1C mask | CPU读到/尝试清除过哪些中断状态 |
| `cg_slave_request` | 下游setup | R/W、source/destination目标、写数据类 | DUT向下游发出了什么请求 |
| `cg_slave_completion` | 下游完整握手 | R/W、target、实际传输数据类 | 哪些下游事务真正完成 |
| `cg_apb_wait` | 上游或下游事务完成 | side、R/W、wait cycles及三维cross | 各方向遇到过哪些等待类别 |
| `cg_reset` | reset下降沿 | idle/setup/access | reset从哪种上游协议上下文发生 |
| `cg_probe_state` | reset释放后每拍 | interrupt/busy电平、上下沿、二者cross | 引脚和busy状态是否激活/恢复 |
| `cg_busy_attempt` | 每笔上游setup | busy×region×RW | CPU是否在busy时尝试过某类访问 |

有几个细节需要特别注意：

### 7.1 `cg_dma_command`的coverage配置模型

coverage内部维护了：

```text
cfg_src / cfg_dst / cfg_len
cfg_src_valid / cfg_dst_valid / cfg_len_valid
```

它只在已完成的SRC/DST/LEN写之后更新。INIT/COPY命令完成时，coverage利用这些值判断：

- 当前LEN属于哪一类；
- COPY的SRC/DST属于equal/overlap/adjacent/disjoint中哪一类；
- 命令发出时配置是否齐全。

这个模型只负责“分类”，不负责“判对错”，所以它不是scoreboard/reference model。

### 7.2 `cg_interrupt`不是interrupt引脚覆盖率

`cg_interrupt` 只在CPU访问DMA_INT寄存器时采样：

- 读操作中`item.data[3:0]`是读回状态；
- 写操作中`item.data[3:0]`是W1C mask；
- interrupt引脚的电平和跳变由`cg_probe_state`统计。

### 7.3 wait cycle怎么数

setup周期不计入wait cycle。进入access后：

- 第一个access周期`PREADY=1`：`zero_wait`；
- 一个access周期`PREADY=0`后再完成：`one_wait`；
- 2～3拍：`short_wait[]`；
- 4～7拍：`medium_wait`；
- 8拍以上：`long_wait`。

当前DUT的上游`PREADY`是寄存输出，正常时序下master-side `zero_wait` 可能结构上不可达，不应通过盲目增加seed强行追求。

---

## 8. bins、cross、`iff`、`ignore_bins`和`illegal_bins`

### 8.1 bin怎么命中

每次covergroup执行`sample()`时，工具会根据样本值增加对应bin的hit count。默认情况下，bin命中至少一次就算covered。

例如：

```systemverilog
bins zero    = {32'd0};
bins minimum = {32'd1};
bins normal_values[] = {[32'd2:32'd15]};
```

`normal_values[]` 会为2～15分别生成bin，而不是把整个范围当成一个bin。

### 8.2 cross不是“两边分别覆盖”

例如：

```systemverilog
X_REGION_RW: cross CP_REGION, CP_RW;
```

它要求在同一次sample中出现每种关心的组合：

```text
DIRECT read
DIRECT write
SRC read
SRC write
...
```

因此某个coverpoint的所有bin都命中，另一个coverpoint的所有bin也命中，并不保证cross已经命中所有组合。

cross也只能证明组合发生过。例如`COPY × LEN_TOO_LARGE`被命中，并不能单独证明“这笔COPY最终产生了invalid-length中断”。结果因果关系仍需scoreboard/assertion，或专门的命令×结果coverage模型。

### 8.3 `iff`

```systemverilog
coverpoint data iff (region == DMA_LEN && write)
```

`iff`是采样门控。`sample()`虽然被调用，但条件为0时这个coverpoint不采样。

### 8.4 `ignore_bins`

当前模型中：

```systemverilog
ignore_bins not_applicable = {REL_NOT_APPLICABLE};
```

被ignore的bin不参与覆盖率分母，也不代表错误。

### 8.5 `illegal_bins`

当前coverage代码没有`illegal_bins`。LEN=0和LEN>16是普通bin，这是有意的：负向测试本来就要产生非法长度，再检查DUT是否产生正确的中断。

`illegal_bins`不能代替scoreboard或assertion。

### 8.6 `option.per_instance`和`option.goal`

所有9个covergroup都设置：

```systemverilog
option.per_instance = 1;
option.goal = 100;
```

- `per_instance=1`：保存每个covergroup对象自己的结果；
- `goal=100`：报告的目标值是100%。

`goal=100`不会自动生成激励，也不会让当前回归在低于100%时自动fail。

当前每次test只创建一个：

```text
uvm_test_top.apb_device_env_1.coverage_full
```

`per_instance=1`也不负责跨test累计；跨test累计仍由VDB完成。

---

## 9. 单次log中的coverage与回归累计coverage

`apb_device_coverage_full.sv` 的 `report_phase()` 会打印9个covergroup的：

```systemverilog
get_inst_coverage()
```

这些百分比只属于**当前这一次仿真进程**。仿真退出后，这些SystemVerilog对象就消失了。

所以你可能看到：

```text
dma_apb_init_test log:
  DMA commands = 45%

dma_apb_copy_test log:
  DMA commands = 60%
```

但Verdi中选择所有test后的累计结果可能是85%或其他数值，取决于两次运行命中bin的重叠程度。

因此：

- 看单次test的表现：看该test的log；
- 看整个regression的累计结果：看`simv.vdb`的All Tests/Total视图。

---

## 10. `make regression`的真实脚本流程

命令：

```bash
make regression
```

当前`Makefile`内部顺序是：

```text
1. make clean
2. make vcs_build
3. 创建`regression_logs/`
4. 串行运行8个directed test，全部SEED=1
5. 串行dma_apb_random_test，SEED=1 2 3 4 5
6. 所有run写入同一simv.vdb
```

8个directed test是：

```text
dma_apb_smoke_test
dma_apb_register_direct_test
dma_apb_init_test
dma_apb_copy_test
dma_apb_interrupt_test
dma_apb_target_wait_test
dma_apb_busy_test
dma_apb_reset_test
```

然后执行5次：

```text
dma_apb_random_test_1
dma_apb_random_test_2
dma_apb_random_test_3
dma_apb_random_test_4
dma_apb_random_test_5
```

因此一轮完整默认回归是**13次仿真，只编译1次**。

注意：

- `dma_apb_full_coverage_test`已定义，但它不在默认`DIRECTED_TESTS`中；
- `dma_apb_wait_state_test`是`target_wait_test`的别名，默认不重复运行；
- 回归中使用`WAVE=0`，因此本轮不生成FSDB；
- 回归是串行的，不会有多个进程并发写同一VDB；
- shell使用`set -e`，首个失败会立即停止后续test。

完整回归后：

```text
regression_logs/<test>_<seed>.log
```

应该有13份log。可以简单检查：

```bash
find regression_logs -name '*.log' | wc -l
```

如果不是13，先检查回归是否在中途失败。

当前真正有效的回归入口是`make regression`。`scripts/regress.sh`仍保留了旧版`run-only`流程，当前Makefile不会调用它，请不要把它当作当前权威入口。

---

## 11. `simv.vdb`如何累计

编译和运行都显式指定：

```text
-cm_dir simv.vdb
```

每次运行再使用唯一名称：

```text
-cm_name <TEST>_<SEED>
```

所以13次运行属于同一个设计版本，但在VDB中有不同test record。Verdi可以显示单个test record，也可显示选中记录的累计结果。

当前简化流程把各run直接写进同一`simv.vdb`，因此不再额外运行URG merge。这个方法的前提是：

- 所有run来自同一个`simv`；
- coverage模型没有中途改变；
- 不并发写同一VDB；
- 每次run使用可区分的`-cm_name`。

如果以后需要并行回归/集群回归，正确方案是每个进程写独立VDB，之后再用URG合并，不要让多个进程同时改同一个`simv.vdb`。

---

## 12. 第一次完整回归怎么跑

### 12.1 启动

```bash
make regression
```

它本身会先`make clean`，所以你不需要再额外清理。

### 12.2 确认是否完整PASS

终端末尾应看到：

```text
Regression complete. Open coverage with:
  verdi -cov -covdir simv.vdb &
```

然后检查：

```bash
find regression_logs -name '*.log' | wc -l
```

默认应输出`13`。

### 12.3 打开覆盖率

```bash
verdi -cov -covdir simv.vdb &
```

Verdi版本不同时GUI名称会略有差异，但建议按以下顺序看：

1. 先找Tests/Test Records视图，确认能看到13个`TEST_SEED`记录；
2. 选择All Tests/Total/Merged类似的累计视图，不要停留在单个test；
3. 先看Functional Coverage下的9个covergroup；
4. 展开coverpoint和cross，看未命中bin的具体名称；
5. 再看Code Coverage，优先定位`top.DUT`下的line/branch/condition/toggle/FSM/assertion；
6. 对某个未覆盖项，反查它应该由哪个test/sequence触发。

### 12.4 回归默认没有波形

回归为了避免磁盘浪费使用`WAVE=0`。如果某个test/seed失败，应单独复现：

```bash
make vcs_run TEST=<failed_test> SEED=<failed_seed> WAVE=1
verdi -dbdir simv.daidir -ssf waveform.fsdb &
```

这个debug复现会继续更新当前`simv.vdb`，而且可能与失败run使用同名record。若需要保留
原回归数据库，应先备份；完成复现后的VDB只用于debug，不要直接作为signoff结果。

---

## 13. 一个能直观理解“累计”的小实验

先跑INIT：

```bash
make clean
make vcs_run TEST=dma_apb_init_test SEED=1 WAVE=0 LOG=init.log
verdi -cov -covdir simv.vdb &
```

记录当前`cg_dma_command`和COPY relation的coverage。

然后关闭或刷新Verdi，**不要clean**，再跑COPY：

```bash
make vcs_run TEST=dma_apb_copy_test SEED=2 WAVE=0 LOG=copy.log
verdi -cov -covdir simv.vdb &
```

这时：

- `simv`没有重新编译；
- `init.log`只包含INIT这次仿真；
- `copy.log`只包含COPY这次仿真；
- `simv.vdb`同时包含`dma_apb_init_test_1`和`dma_apb_copy_test_2`；
- All Tests视图中会新增COPY命令、地址关系、下游读/写请求与完成等命中。

最后执行：

```bash
make clean
```

`simv.vdb`被删除，累计结果也随之消失。这可以直观证明：累计依赖的是VDB，不是“已经include了所有test”。

---

## 14. 如何扩展回归

### 14.1 增加随机seed

```bash
make regression RANDOM_SEEDS="1 2 3 4 5 6 7 8 9 10"
```

### 14.2 增加每个seed的随机操作数

```bash
make regression RANDOM_OPS=100
```

注意：`RANDOM_OPS`没有进入当前`-cm_name`。如果你手工在同一VDB中使用相同TEST+SEED、只改RANDOM_OPS重跑，会产生同名test record风险。建议开新campaign或更换seed。

### 14.3 把full coverage test加入列表

```bash
make regression \
  DIRECTED_TESTS="dma_apb_smoke_test dma_apb_register_direct_test \
  dma_apb_init_test dma_apb_copy_test dma_apb_interrupt_test \
  dma_apb_target_wait_test dma_apb_busy_test dma_apb_reset_test \
  dma_apb_full_coverage_test"
```

不过`dma_apb_full_coverage_test`会串行重复大部分定向sequence，对已经跑完各独立directed test的默认回归来说，通常会增加时间而不是增加大量新coverage。

---

## 15. 不可违反的campaign原则

### 15.1 修改源码后重开campaign

如果修改了以下任意内容：

- RTL；
- TB/monitor/sequence/test；
- covergroup/bin/cross；
- `CM_FLAGS`；
- 影响编译或coverage的Makefile参数。

都应执行：

```bash
make clean
```

然后重新开始回归。普通`make vcs_run`虽然会在源码更新后重编`simv`，但不会先删除旧`simv.vdb`。不同设计/覆盖模型版本的数据不应混在同一campaign中。

`make regression`自带开头clean，因此是获取fresh result最简单的方式。

### 15.2 不要把相同TEST+SEED当成两个独立样本

当前`-cm_name`=“TEST_SEED”。相同TEST+SEED重跑时不能作为另一个可区分样本，而且不同VCS版本对同名record的替换/合并细节可能不同。

想获得新的随机贡献时，更换seed；想保留两个同seed实验时，应扩展Makefile的`-cm_name`加入RUN_ID。

### 15.3 不要并发写同一VDB

当前回归串行运行，因此安全。若以后并行化，每个进程应该写独立VDB，最后使用URG合并。

### 15.4 回归失败后不要直接信任残留VDB

失败run可能已写入部分coverage，而回归会在首个错误处停止。此时`simv.vdb`只是一个不完整campaign，可用于debug，不应用于signoff。

修复问题后应重新：

```bash
make regression
```

---

## 16. 如何处理coverage hole

看到uncovered bin时，不要立即粗暴增加seed。先把它归类：

### 16.1 激励缺失

场景合法可达，但当前sequence没有生成。

处理：增加定向sequence/test，一般比盲目增加seed更稳定。

### 16.2 采样链错误

波形中场景已发生，但bin不命中。

检查：

- 连接的是request还是completion analysis port；
- `sample()`是否被调用；
- `iff`是否把样本关掉；
- coverage侧的SRC/DST/LEN模型是否与当前事务同步；
- reset后coverage状态是否残留。

### 16.3 不可达或不合法组合

例如当前模型中已知：

- COPY LEN=1时，整数地址不可能形成严格forward/backward overlap；
- LEN=0时`classify_relation()`返回`REL_NOT_APPLICABLE`，所以LEN_ZERO×各有效relation的自动cross bin不可达；
- DUT上游PREADY是寄存输出，master-side zero-wait在当前协议实现下可能不可达；
- interrupt `overlap_only`可能因CPU读INT被busy阻塞，最后同时看到overlap+done。

对这类组合应以规格/数学证明为依据，使用cross级`ignore_bins`、Verdi waiver/exclusion或修改coverage模型。不应为了100%人工伪造不合法激励。

### 16.4 DUT bug

coverage hole或异常hit有时是DUT行为与计划不符，例如请求bin已命中，但completion bin始终不命中。此时应结合scoreboard和波形定位，不应先修coverage来隐藏问题。

---

## 17. 当前coverage model的已知边界

### 17.1 COPY LEN×地址关系cross包含不可达项

`X_COPY_LENGTH_RELATION` 会生成LEN类别和6种地址关系的组合。但LEN_ZERO和LEN_MINIMUM存在上述结构性不可达组合，因此这个cross未必能达到100%。要先分析分母，再决定补测或ignore/waive。

### 17.2 reset后coverage配置模型未清空

`cfg_src/cfg_dst/cfg_len`及valid位会在寄存写后更新，但当前reset监控只采样`cg_reset`，没有清除这些coverage状态。

因此同一次仿真中动态reset之后：

- DUT寄存器已经清零；
- coverage可能仍持有reset之前的SRC/DST/LEN；
- reset后DMA命令或slave target可能被旧配置误分类。

这是当前coverage model的已知限制，不是Verdi统计算法错误。

### 17.3 FSM coverage依赖工具识别

当前DMA控制主要由若干active flag组合表达，不是一个典型enum state寄存器。VCS是否能把它完整识别为FSM需以实际报告为准。FSM metric很低或没有可识别对象时，先检查提取结果，不要立即认为sequence一定没跑到状态。

---

## 18. 产物速查

| 产物 | 什么时候生成 | 是否累计 | 怎么用 |
|---|---|---|---|
| `simv` | 编译 | 不适用 | 执行仿真 |
| `simv.daidir/` | 编译 | 不适用 | Verdi设计/波形debug |
| `simv.vdb/` | 编译+每次运行 | 是 | `verdi -cov -covdir simv.vdb &` |
| `waveform.fsdb` | `WAVE=1`的单次run | 否，下次覆盖 | `verdi -dbdir simv.daidir -ssf waveform.fsdb &` |
| `sim.log` | 默认单次run | 否，下次覆盖 | 看UVM日志 |
| `regression_logs/` | 回归 | 每个run独立 | 复现test/seed和检查PASS |
| `dma_read.txt` / `dma_write.txt` | 每次test打开 | 否，以`w`覆盖 | 只保留最后一次run的对应report |

`make clean` 会删除上述仿真生成物。如果结果需要留档，应先备份`simv.vdb`、log和必要波形，再clean。

---

## 19. 完整回归验收清单

- [ ] `make regression` 最终退出码为0；
- [ ] 终端打印`Regression complete`；
- [ ] 根目录存在`simv`、`simv.daidir/`、`simv.vdb/`和`compile.log`；
- [ ] `regression_logs/`默认有13份log；
- [ ] 每份log中`UVM_ERROR : 0`和`UVM_FATAL : 0`；
- [ ] Verdi能看到13个唯一`TEST_SEED`record；
- [ ] 查看coverage时已选择All Tests/Total，不是某个单run；
- [ ] 能区分Functional Coverage和`top.DUT`的Code Coverage；
- [ ] 每个关键uncovered bin都已归类为激励缺失、采样问题、不可达/waiver或DUT bug；
- [ ] 未将中途失败留下的部分VDB用作最终签核结果。

---

## 20. FAQ

### Q1：是不是所有test一起include才能累计？

不是。Include决定哪些class和coverage模型存在于`simv`；`+UVM_TESTNAME`决定本次跑谁；VDB才负责保存多次run的累计结果。

### Q2：每换一个test需要重新编译吗？

不需要。所有test class已在同一`simv`中，只需改变`TEST=`。只有源码或编译参数改变才需要重编。

### Q3：定向test换seed会有很大差别吗？

不一定。定向sequence的主流量通常固定，但当前DUT内部delay和默认slave response仍可含随机性。对`dma_apb_random_test`来说，seed的影响最明显。

### Q4：为什么单次log的coverage比Verdi累计值低？

因为log只打印当前仿真中的covergroup对象，Verdi则可显示多个test record的命中并集。

### Q5：为什么回归没有`waveform.fsdb`？

因为回归每次run显式使用`WAVE=0`。这只节省波形空间，coverage仍写入`simv.vdb`。

### Q6：为什么增加了很多seed，cross仍然不到100%？

可能是sequence没有产生目标组合，也可能是组合在数学/协议上不可达，或sample条件不正确。必须先看具体bin名称和采样链，不能只看总百分比。

### Q7：coverage命中了，是不是scoreboard就不需要了？

不是。Coverage只说明场景发生；scoreboard才比较期望与实际结果。两者是并行且互补的。

---

## 21. 本工程的coverage目标与后续阅读

当前testplan建议：

- 功能覆盖率：100% planned legal bins；
- 关键cross：100%；
- line：≥95%；
- branch/condition/toggle：通常以≥90%为初始目标；
- FSM/assertion：按可识别/可达项做逐条评审。

详细test点、waiver和exit criteria请继续阅读：

- [`DMA_APB_Verification_Testplan.md`](./DMA_APB_Verification_Testplan.md)
- [`debug.md`](./debug.md)
- [`apb_device_src/apb_device_coverage_full.sv`](./apb_device_src/apb_device_coverage_full.sv)
- [`Makefile`](./Makefile)

Synopsys官方参考：

- [VCS/Verdi coverage与VDB/URG示例（Synopsys Verification Methodology Cookbook）](https://www.synopsys.com/content/dam/synopsys/partners/document/synopsys-verification-reference-methodology-cookbook-for-bluespec-risc-v-processors.pdf)
- [Synopsys VCS与Verdi coverage/debug整合概览](https://www.synopsys.com/content/dam/synopsys/gated-assets/verification/vcs-ds.pdf)
- [Synopsys Verdi产品页](https://www.synopsys.com/verification/debug/verdi.html)
