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
- `Makefile`、`scripts/`：一次编译、单测、回归、pass/fail 检查和 URG 合并。
- `out/`：运行后自动生成的 build、单测日志、波形和 coverage 数据。

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
make compile
make run TEST=dma_apb_copy_test SEED=1
```

查看全部 test：

```sh
make list-tests
```

单测结果位于：

```text
out/runs/normal/<TEST>_seed_<SEED>/sim.log
out/runs/normal/<TEST>_seed_<SEED>/coverage.vdb
```

脚本不仅检查 simulator 退出码，还要求 log 中 `UVM_ERROR : 0` 和
`UVM_FATAL : 0`，避免 DUT `$finish` 提前退出却被误判为 PASS。

## 回归与累计覆盖率

```sh
make regress
```

该命令只编译一次，随后运行全部定向 test，并对 `dma_apb_random_test` 使用默认
seed `1 2 3 4 5`。最后由 URG 合并同一版 `simv` 产生的 VDB：

```text
out/coverage/normal/merged.vdb
out/coverage/normal/report/dashboard.html
```

自定义随机种子和随机事务数：

```sh
make regress RANDOM_SEEDS="11 22 33" RANDOM_OPS=100
```

源码变化触发重新编译后，Makefile 会自动清理该 build variant 的旧 run/VDB，
防止不同版本的 coverage 被混合。

## 波形

无需 Verdi PLI 的 VPD：

```sh
make run TEST=dma_apb_busy_test SEED=1 WAVE=1
dve -vpd out/runs/vpd/dma_apb_busy_test_seed_1/waveform.vpd &
```

有 Verdi 时生成 FSDB：

```sh
make run TEST=dma_apb_copy_test SEED=1 FSDB=1 NOVAS_HOME=/path/to/verdi
verdi -ssf out/runs/fsdb/dma_apb_copy_test_seed_1/waveform.fsdb &
```

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
