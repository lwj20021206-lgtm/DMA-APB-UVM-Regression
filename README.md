# DMA-APB UVM Regression

这是基于原 DMA-APB TB 整理出的独立回归工程。所有 testcase 在一次 VCS
编译中进入同一个 `simv`，运行时通过 `+UVM_TESTNAME` 选择，不需要为每个用例
重新编译。

## 目录定位

- `apb_device.v`：DUT；旧固定事务自检默认关闭。
- `src/`：interface、master/slave agent、item、driver、monitor、sequencer、IRQ
  handler，以及可复用 master base sequence。
- `sequences/`：coverage-driven master sequences 和定向 slave response sequence。
- `tests/dma_apb_tests.sv`：所有 UVM testcase。
- `apb_device_src/apb_device_scoreboard.sv`：寄存器、下游传输、reference memory
  与中断检查。
- `apb_device_src/apb_device_coverage_full.sv`：功能覆盖率模型。
- `top.sv`：DUT/TB 顶层和可选波形控制。
- `Makefile`、`scripts/check_run.sh`：一次编译、单测、串行回归和 pass/fail 检查。
- `COVERAGE_GUIDE.md`：从第一次跑回归开始，讲解 coverage 的采样、存储、累计与 Verdi 查看方法。
- `simv.vdb`、`regression_logs/`、`waveform.fsdb`：仿真后在工程根目录生成的 coverage、回归日志和单测波形。

## 已修复的兼容问题

- 仲裁枚举使用 UVM 1.1d 的 `SEQ_ARB_STRICT_FIFO`。
- 原来的单一 `apb_intf` 拆为 `apb_master_intf` 和 `apb_slave_intf`，避免未使用的
  clocking output 与 DUT 端口形成多驱动。
- clocking block 使用 `default input #1step output #0`。
- `run_test()` 不再写死 test 名称。
- Makefile 显式编译 UVM 1.1d，不再混用 `-ntb_opts uvm-1.2`。
- scoreboard 已补充 INIT/COPY 写只读区域的非法读中断预测。

## Testcase

| Test | 重点内容 |
|---|---|
| `dma_apb_smoke_test` | direct、INIT、COPY、基础异常和 IRQ 冒烟 |
| `dma_apb_register_direct_test` | direct 数据类、SRC/DST/LEN/INT、LEN 全值、非法区域 |
| `dma_apb_init_test` | INIT 长度类和 6 种初始化数据模式 |
| `dma_apb_copy_test` | COPY equal、前后重叠、前后相邻、disjoint 与长度类 |
| `dma_apb_interrupt_test` | none、done、invalid-length、invalid-op、overlap+done、W1C |
| `dma_apb_target_wait_test` | slave target 分类及 master/slave wait-state |
| `dma_apb_busy_test` | DMA busy 时发起安全的寄存器/direct/非法访问 |
| `dma_apb_reset_test` | idle/setup/access 三种动态 reset 与 reset 后基本传输 |
| `dma_apb_random_test` | 受约束的安全随机场景；seed 会改变事务组合 |
| `dma_apb_full_coverage_test` | 顺序执行全部定向 sequence，便于单次快速观察 |

`test` 保留为 `dma_apb_smoke_test` 的兼容别名。

## 编译与单测

默认 `UVM_HOME` 已设为实验环境里的 UVM 1.1d `src` 路径。若实际路径不同，命令行
覆盖即可。

```sh
make vcs_build
make vcs_run TEST=dma_apb_copy_test SEED=1
```

`make vcs_run` 会在需要时自动完成编译，因此平时也可以只执行第二条命令。单测默认生成：

```text
sim.log
waveform.fsdb
simv.vdb
```

其中 `sim.log` 和 `waveform.fsdb` 会被下一次单测覆盖；`simv.vdb` 会按
`<TEST>_<SEED>` 保存本次 coverage record，并与此前同一 campaign 的结果累计。

脚本不仅检查 simulator 退出码，还要求 log 中 `UVM_ERROR : 0` 和
`UVM_FATAL : 0`，避免 DUT `$finish` 提前退出却被误判为 PASS。

## 回归与累计覆盖率

```sh
make regression
```

该命令只编译一次，随后运行全部定向 test，并对 `dma_apb_random_test` 使用默认
seed `1 2 3 4 5`，总计 13 次仿真。每次 run 使用唯一的 `-cm_name`，串行写入同一个
`simv.vdb`；因此当前简化流程不需要额外运行 URG merge。回归日志位于：

```text
regression_logs/<TEST>_<SEED>.log
```

查看累计覆盖率：

```sh
verdi -cov -covdir simv.vdb &
```

自定义随机种子和随机事务数：

```sh
make regression RANDOM_SEEDS="11 22 33" RANDOM_OPS=100
```

`make regression` 开始时会自动 clean，保证这是一个新 campaign。若手动连续执行
`make vcs_run`，可以有意累计 coverage；但修改 RTL、TB、covergroup 或覆盖选项后，
应先执行 `make clean`，不要把不同版本的数据混入同一个 VDB。

coverage 的完整底层原理、9 组功能覆盖模型、单次与累计结果的区别、Verdi 阅读顺序和
常见误区，见 [Coverage Guide](COVERAGE_GUIDE.md)。

## 波形

单测默认生成 FSDB：

```sh
make vcs_run TEST=dma_apb_copy_test SEED=1
verdi -dbdir simv.daidir -ssf waveform.fsdb &
```

回归默认使用 `WAVE=0`，避免 13 次仿真反复覆盖同一个大波形文件；关闭波形不会关闭
coverage 采集。

## Coverage waiver

当前 DUT/模型下以下 bin 不应靠增加 seed 强行追到 100%：

- command × LEN=0：DUT 的 5-bit LEN 会下溢，scoreboard 将该命令判为非法。
- command × missing configuration：属于测试激励自身错误。
- COPY LEN=1 × forward/backward overlap：整数地址下不可达。
- interrupt `overlap_only`：CPU 读 INT 要等 DMA 完成，此时 done 已同时置位。
- master-side zero-wait：DUT 的 PREADY 是寄存器，首个 access 周期必有等待。
- busy × INIT/COPY write：上一条 DMA 结束后 LEN 已归零，会形成危险的 LEN=0 命令。
- busy × LEN/INT read：在 DMA 最后一拍会读到更新前的旧值，与当前
  scoreboard 的完成后模型不同。
- reset during DMA：当前 scoreboard 尚未实现 reset 时清空未完成期望队列的模型。

`LEN=33` 用于覆盖 command 的 too-large 类：coverage 记录原始 33，DUT 和
scoreboard 使用低 5 位的有效长度 1；sequence 会先处理 invalid-length IRQ，再发
INIT/COPY。COPY 只保留一个 disjoint 场景，不会用截断后的长度去伪造
overlap/adjacent 关系覆盖。
