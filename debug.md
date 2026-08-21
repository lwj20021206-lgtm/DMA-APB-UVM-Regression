# DMA-APB Debug 记录：连续 COPY 指令

> 本文件专门记录“第一次 DMA COPY 运行期间，CPU 发出第二条 COPY，但第一次 COPY 结束后没有再次观察到 `dma_copy_active_p1/p2`”这一波形问题。分析基于当前 `apb_device.v`，并使用原始 RTL 做了最小对照仿真。

## 1. 波形现象

观察到的大致过程为：

```text
CPU发送第一条COPY
        ↓
等待pready_delay减到0
        ↓
上游PREADY拉高，第一条COPY命令完成APB握手
        ↓
dma_copy_active_p1/p2开始运行
        ↓
CPU发出第二条COPY
        ↓
由于is_dma_busy=1，第二条COPY保持PSEL/PENABLE并等待
        ↓
第一条COPY完成，PREADY再次拉高
        ↓
波形中没有再次看到dma_copy_active_p1/p2
```

最初需要确认的问题是：第二条 COPY 是否被 busy 逻辑直接丢弃。

## 2. 正常 COPY 启动条件

COPY 命令的地址译码为：

```verilog
assign is_dma_copy =
    psel & (paddr[31:28] == DMA_COPY) & (pwrite == 1);
```

`dma_copy_active_p1` 的启动条件为：

```verilog
always @(posedge pclk or negedge presetn) begin
    if (~presetn)
        dma_copy_active_p1 <= 0;
    else if (is_dma_copy && pready == 1)
        dma_copy_active_p1 <= 1;
    else if (dma_copy_active_p2 && slave_pready == 1 && dma_len > 1)
        dma_copy_active_p1 <= 1;
    else if (dma_copy_active_p1 && slave_pready == 1)
        dma_copy_active_p1 <= 0;
end
```

从这段主功能逻辑看，只要第二条 COPY 一直保持到 `PREADY=1`，它本来应该在后续时钟沿重新拉高 `dma_copy_active_p1`。

## 3. `PREADY` 为什么会等待第一条 COPY 完成

非 direct-read 的上游响应条件是：

```verilog
else if (!is_dma_read && psel && penable &&
         pready_delay == 0 && !is_dma_busy)
    pready <= 1;
```

第一条 COPY 运行时 `is_dma_busy=1`，所以第二条事务不能立即获得 `PREADY`。APB master 必须保持第二条事务的：

```text
PSEL、PENABLE、PADDR、PWRITE、PWDATA
```

第一条 COPY 最后一次下游传输完成后，`is_dma_busy` 解除，第二条事务才满足上游 `PREADY` 条件。

这里的 `PREADY` 只有在当前存在 `PSEL && PENABLE` 时才会产生，所以它不是单独的 DMA-done 输出；它本来应当作为当前第二条 APB 事务的响应。

## 4. 实际根因：DUT 内置自检执行 `$finish`

DUT 在文件末尾保存上一笔已完成 APB 事务的地址：

```verilog
always @(posedge pclk or negedge presetn) begin
    if (~presetn)
        pre_addr <= 0;
    else if (psel && penable && pready)
        pre_addr <= paddr;
end
```

同时存在一段禁止前 10 笔随机事务连续访问相同完整地址的自检：

```verilog
always @(*) begin
    if (random_cnt != 0 && random_cnt < 11)
    if (psel && penable && pready)
    if (paddr == pre_addr) begin
        $display(
            "Simulation Failed. Address of APB-transfer[%0d] "
            "is the same with address of APB-transfer[%0d].",
            random_cnt+1, random_cnt
        );
        $finish;
    end
end
```

如果两条 COPY 使用相同的完整地址，例如：

```text
第一条COPY：PADDR = 32'h8000_0000
第二条COPY：PADDR = 32'h8000_0000
```

那么第一条命令握手后：

```text
pre_addr = 32'h8000_0000
```

第二条 COPY 在 busy 期间一直保持相同地址。第一条 COPY 结束、`PREADY` 再次变成 1 时，自检条件同时成立：

```text
random_cnt != 0
random_cnt < 11
PSEL && PENABLE && PREADY
PADDR == pre_addr
```

于是自检立即执行 `$finish`。

## 5. 为什么波形中看不到第二次 P1/P2

关键在于 `PREADY` 使用非阻塞赋值，而地址重复检查使用组合逻辑：

```text
第一条COPY最后一次下游传输完成
        ↓
is_dma_busy变成0
        ↓
时钟沿执行 pready <= 1
        ↓
NBA更新后，PREADY在当前仿真时刻变成1
        ↓
always @(*) 地址重复检查立即重新执行
        ↓
发现第二条PADDR == pre_addr
        ↓
立即执行$finish
        ↓
仿真没有机会进入下一个posedge
        ↓
is_dma_copy && pready无法在时钟沿启动第二次P1
```

因此看到的是：

```text
PREADY最后拉高
P1/P2没有再次拉高
波形在该位置结束
```

这不是主 copy 状态机正常地丢弃了第二条命令，而是 DUT 内嵌的测试逻辑提前终止了仿真。

日志中应当能找到：

```text
Simulation Failed. Address of APB-transfer[N]
is the same with address of APB-transfer[N-1].
```

## 6. 最小对照仿真结果

使用当前原始 `apb_device.v`，依次配置 SRC、DST、LEN，然后连续两次写相同 COPY 地址，能够复现：

```text
第一条COPY：P1/P2正常运行
第一条COPY结束：第二条事务对应的PREADY出现
随后打印Address ... is the same ...
RTL执行$finish
第二条P1/P2没有出现
```

屏蔽这段地址重复自检后，使用相同激励可以观察到：

```text
第二条COPY获得PREADY
下一拍dma_copy_active_p1 = 1
随后dma_copy_active_p2 = 1
```

这证明 busy/PREADY 主路径本身会接受第二条 COPY；当前波形中状态没有重新启动的直接原因是 `$finish`。

## 7. 独立的第二个问题：`dma_len` 已经变成 0

第一条 COPY 每完成一次目标写操作都会执行：

```verilog
else if ((dma_init_active || dma_copy_active_p2) && slave_pready)
    dma_len <= dma_len - 1;
```

所以第一条 COPY 全部完成后：

```text
dma_len = 0
```

即使屏蔽 `$finish` 并成功启动第二条 COPY，如果 CPU 没有重新配置 `DMA_LEN`，第二次任务也不会按照原来的长度正常复制。最小仿真中第二条 COPY 只经历了一次 P1/P2，然后 `dma_len` 从 0 下溢为 31。

因此正确启动另一条独立 COPY 前，应重新配置需要的寄存器：

```text
写DMA_SRC
写DMA_DST
写DMA_LEN
写DMA_COPY
```

## 8. Debug 时应检查的信号

遇到相同现象时，建议同时查看：

| 信号 | 检查内容 |
|---|---|
| `paddr`、`pre_addr` | 两条 COPY 的完整 32 bit 地址是否相同 |
| `random_cnt` | 第二条事务发生时是否位于 `1～10` |
| `psel/penable/pready` | `$finish` 条件是否同时成立 |
| 仿真日志 | 是否出现 `Address ... is the same ...` |
| `dma_len` | 第一条 COPY 后是否已经减到 0 |
| `is_dma_copy` | 第二条握手期间地址和 `pwrite` 是否仍能正确译码 |
| `dma_copy_active_p1/p2` | 仿真是否在下一时钟沿到来前已经结束 |

如果两条 COPY 的完整 `paddr` 不同，或者 `random_cnt` 不在 `1～10`，则上述地址重复自检不会触发，需要继续检查 `is_dma_copy`、`pwrite`、复位和仿真日志中的其他 `$finish` 条件。

## 9. 后续处理建议

### 临时验证方法

- 查看日志确认是否由地址重复检查结束仿真。
- 为了观察状态机，可暂时让两个 COPY 使用不同的低 28 bit 地址；DUT 只使用 `paddr[31:28]` 译码，因此它们仍然会被识别为 COPY。
- 第二次 COPY 前重新配置 SRC、DST 和 LEN。

### 正式优化方向

- 将 `random_cnt/pre_addr/golden_data/$finish` 等面向特定测试流程的检查从 DUT 中移出。
- 把这些检查放入 UVM scoreboard、test 或 assertion，避免验证逻辑改变 DUT 的功能行为。
- 如果规格允许连续 DMA 命令，进一步定义 busy 期间的排队、拒绝或等待机制。

---

# 第二部分：代码走读发现的 Bug 与疑点清单

> 整理于 2026-08-16。来源：对 `apb_device.v` 及 UVM 环境（scoreboard / sequencer / interrupt handler / env / coverage）的通读分析。
> 分类：A. RTL Bug（含已确认与推演待验证）；B. RTL 疑点/风格；C. 验证环境问题。
> 推演结论均附定向验证方法，验证前在 testplan 中保持 Planned 状态。

## A. RTL Bug

### BUG-01：`invalid_value_of_length` 缺少 `pwrite` 判断（已确认）

- **位置**：`apb_device.v:140`
- **现象**：读 DMA_LEN 时 `pwdata` 无功能含义，若残留值 >16（上一笔写遗留），会误触发 invalid-length 中断。
- **影响**：scoreboard 按"仅写触发"建模，该场景一旦出现即 mismatch；软件侧收到虚假中断。
- **状态**：已记录于 [后续优化方案.md](./后续优化方案.md) 优化项 1（含修复代码）。
- **验证**：定向测试——写 LEN=17（触发一次中断并清除）后读 DMA_LEN，观察 `dma_int[2]` 是否再次置位。

### BUG-02：DIRECT outstanding 的完成被 INIT/COPY 状态机误消费（COPY 已确认）

- **位置**：状态机 `apb_device.v:184-211`、选择器 `:300-331`、装载器 `:273-286`、busy 解码 `:122`。
- **已确认的触发链**：`fill_source()` 的 DIRECT write 已被上游 CPU 接受，但下游仍处于 `slave_psel=1, slave_penable=1, slave_pwrite=1, slave_pready=0`。CPU 继续发 COPY 并置位 `dma_copy_active_p1`后，旧 DIRECT 的 `slave_pready` 被 COPY 状态机误当成 COPY read 完成，从而 `p1→p2`，真正的 COPY read 从未发出。
- **波形证据**：观察到的 `slave_paddr=0x10300`、`slave_pwdata=0x600d0103` 精确对应 COPY sequence 发命令前 `fill_source()` 的 DIRECT write，不是上一笔 COPY 的尾写。最小定向仿真也复现了“DIRECT write 完成后直接进 COPY write，COPY read 为 0 笔”。
- **第 280 行不是 bug**：COPY 组合选择器虽已算出下一笔应为 read，但旧 DIRECT 处于 wait-state 时，地址/方向/数据必须保持不变。因此第 280 行冻结下游信号是正确 APB 行为，放开它反而会破坏正在等待的 DIRECT write。
- **机制**：状态机的完成条件只认 `slave_pready`，不区分"这笔完成属于谁"：
  - **LEN=1 INIT** + direct 尾单挂起：尾单完成拍满足 `init_active && slave_pready && dma_len==1` → `dma_init_active` 清零、`dma_len` 1→0；选择器 INIT 分支 `!(dma_len==1 & slave_pready)` 同时失效 → 落到 else 分支 → 总线回空闲。**INIT 一笔传输都没发就结束，但 done 中断照常置位**（`dma_init_copy_done` 当拍为 1）。
  - **LEN=1 COPY** + 尾单挂起：尾单完成拍被当成读相位完成 → `p2` 启动、读被跳过，写出去的是 `dma_init_value` 中的陈旧数据。
- **根因窗口**：`is_dma_busy` 中错误的 DIRECT 豁免使 INIT/COPY 能在 DIRECT outstanding 期间被接受（原设计意图、修复和权衡见 BUG-03）。
- **scoreboard 捕捉能力**（恰好都能抓）：INIT 丢失 → 预期队列残留 → check_phase 报 "expected downstream transfers did not complete"；COPY 跳读 → 第一笔 actual（写）对预期（读）方向 mismatch；中断侧 model 与 RTL 不一致 → DMA_INT 读回 mismatch。
- **验证**：固定较长的 slave ready delay，执行 `DIRECT write(source) → COPY LEN=1`；正确下游顺序必须严格为 `DIRECT write → COPY read → COPY write`。INIT 同结构风险另用 LEN=1 定向测试确认。

### BUG-03：`is_dma_busy` 的 DIRECT 豁免——设计意图、实际缺口与修复权衡（根因已确认）

- **位置与实际语义**：`apb_device.v:122`。原表达式将 `dma_direct_active & !slave_pready` 放在取反的“豁免”里；单独存在 DIRECT outstanding 时，它不会使 `is_dma_busy=1`。因此第 362 行仍可拉高上游 `pready`，CPU 获准继续发命令，形成 BUG-02 的 owner 冲突。同一豁免还会使 INIT 刚启动、DIRECT 尾单未结账的窗口内 busy 异常为 0，上游 SRC/DST/LEN 写可改动正在排队的 DMA 配置。
- **原设计可能想获得的好处**：这很像在尝试实现 posted DIRECT write——DUT 先保存地址/数据并立即回复 CPU，下游写在后台完成。理论上可隐藏下游 wait-state，并让 CPU 在等待期间访问不使用下游总线的 SRC/DST/LEN 等寄存器。`dma_direct_active/dma_direct_cnt` 也像是对一笔 outstanding 事务的尝试性记录。
- **为什么当前实现不成立**：要正确 posted，bridge 必须有完整的 request buffer/FIFO、“缓冲是否有空位”的上游 backpressure，以及下游 `DIRECT/INIT/COPY_READ/COPY_WRITE` owner。当前 RTL 只有 active/count，没有对后续地址/数据和完成事件做完整归属；第二笔 DIRECT 可被提前回复却无处保存，COPY 也可误吃旧 DIRECT ready。因此这是“有 posted 的性能意图，但缺少仲裁与 owner 的未完成实现”。
- **当前小型 DUT 的高效修法**：把 DIRECT outstanding 从豁免改为顶层 busy 条件：

  ```systemverilog
  assign is_dma_busy =
      (dma_direct_active & !slave_pready) |
      dma_copy_active_p1 |
      ((dma_init_active | dma_copy_active_p2) &
       !(dma_len == 1 & slave_pready));
  ```

  下游 DIRECT 尚未 ready 时，`is_dma_busy=1` 使第 362 行不能拉高上游 `pready`；CPU 必须保持当前 DIRECT 请求，根本无法发 COPY。下游完成后 active 清零、上游 DIRECT 才完成，随后 COPY 从空闲下游总线正常启动。
- **行为改变/代价**：DIRECT write 从 posted 变成 non-posted，上游延迟会包含下游 wait-state，CPU 不能在这段时间配置独立 DMA 寄存器，吞吐率下降。收益是在不增加 FIFO/owner 的前提下恢复严格顺序和数据正确性，并同时防止连续 DIRECT write 丢失。对当前验证型小 DUT，这个权衡更合理。
- **无内部死锁**：下游 DIRECT 完成不依赖上游 `pready`；`slave_pready` 到来后 `dma_direct_active` 清零，`dma_direct_cnt` 暂时阻止旧请求被重复下发，上游握手后 count 再清回 0。若下游永远不给 ready，上游一直等待属于正常 APB backpressure，不是内部环路死锁。
- **不应采用的局部修法**：不要放开第 280 行的 wait-state 冻结，那会违反 APB 稳定性；不要只在第 196 行增加 `!dma_direct_active`，否则上游可能已握手而 COPY 状态没启动，命令会静默丢失；也不要把 `dma_direct_cnt` 无条件 OR 进 busy，因为 count 需要后续上游握手清除，可形成自锁。
- **完整安全修复的边界**：上述最小修法针对当前 bug 和当前 slave 激励有效；RTL 内部仍有多处只看裸 `slave_pready`。若要完整支持 APB 允许的 idle/setup 阶段 `PREADY=1`，需要统一使用 `slave_psel && slave_penable && slave_pready`，修正 `slave_penable` 生成，并以 owner 限定 COPY read/write 的状态转移、数据采样、LEN/DST 更新和 done 中断。

### BUG-04：同拍 W1C 与新事件竞争，新事件丢失（推演，待验证）

- **位置**：`apb_device.v:144-149`
- **机制**：`dma_int_nxt` 组合逻辑中 W1C 分支优先；W1C 与新事件同拍成立时只做 `dma_int & ~pwdata`，不并入 `dma_int_update`。done / invalid 类事件多为单拍脉冲，一旦丢失不可恢复。
- **影响**：Testplan INT-010；随机流量下撞拍概率大增 → scoreboard 预期与 RTL 实际不一致 → 偶发 mismatch，极难定位。
- **验证**：定向测试——COPY 最后一笔完成拍同时发 W1C，检查 done 是否丢失。
- **建议**：设计评审确定优先级（通常新事件不应被 W1C 吞掉，`dma_int_nxt = (dma_int & ~pwdata) | dma_int_update` 是常见修法）。

## B. RTL 疑点 / 风格问题

| 编号 | 位置 | 内容 |
|---|---|---|
| SUS-01 | `apb_device.v:122` | `is_dma_busy` 表达式优先级完全靠默认规则（`!` > `&` > `|`），无括号，意图难读。建议加括号或改写 |
| SUS-02 | `apb_device.v:280` | 装载条件中 `is_dma_write` 被 `!is_dma_busy` 管了两次（内层 + 外层），读方向只被外层管一次；功能等价于 `(is_dma_read \| is_dma_write) & !is_dma_busy & !dma_direct_active`。多次修改叠出来的痕迹 |
| SUS-03 | `apb_device.v:144-149、:258-266` | `dma_int_nxt` / `prdata_nxt` 组合逻辑无默认赋值，工具会推断锁存器；当前被时序更新 guard 挡住未见明显错误，建议补默认值 |
| SUS-04 | `apb_device.v:50、:65` | `MEM[0:1023]`、`int_status` 声明后从未使用；TB 侧 `apb_master_item.ready_delay`、`apb_slave_item.addr_delay` 也未使用。保留作扩展或清理 |
| SUS-05 | `apb_device.v:138` | done 中断每笔下游完成都置位（SPEC-TBD-01），非仅最后一笔；当前 scoreboard 按此建模，待规格确认 |

## C. 验证环境问题（TB）

| 编号 | 位置 | 内容 | 修法建议 |
|---|---|---|---|
| TB-01 | `apb_device_scoreboard.sv` | scoreboard 无 reset 建模：中途注入 reset 后预期队列 / 中断模型 / reference memory / model_src/dst/len 以及 src_valid/dst_valid/len_valid 均不清空 → check_phase 假错，且 valid 残留会误判"已配置"（详见下方补充说明） | 加 reset 回调（与 `reset_inject_phase` knob 配套实现，见 [覆盖率bin分析与随机模型规划.md](../覆盖率bin分析与随机模型规划.md) §5.3）；回调中一并清 valid |
| TB-02 | `apb_interrupt_handler.sv:22` | `interrupt_pending` 竞争窗口：handler 清 pending 与 monitor 置新 pending 竞争 → 中断丢失 → `wait_for_next_interrupt` 挂死到 1ms timeout。定向测试碰不到，随机流量必现 | 清 pending 前重新检查电平，或改为"计数 + 电平"双状态 |
| TB-03 | `apb_device_env.sv:58` | `reset_phase` 只在仿真开始时执行一次，环境无中途注入 reset 能力 → `cg_reset` 的 during_setup / during_access bins 不可达，RST-002~004 无法执行 | 加 `reset_inject_phase` knob |
| TB-04 | 根目录 `apb_device.v` | 根目录旧版 DUT 的 legacy 自检未用 `ifdef` 包裹，谁用谁复现第一部分记录的 `$finish` 问题；权威版本为 `DMA-APB/apb_device.v` | 删除或同步根目录旧文件 |

### 补充说明：valid 标志为何只有置位没有清除（2026-08-18）

- **代码事实**：`src_valid/dst_valid/len_valid` 全文件只有三处 `= 1'b1`（对应 SRC/DST/LEN 三个寄存器写分支），没有任何 `= 0`、reset 回调或 check_phase 清除；初始 0 来自 class 成员默认初始化（`bit` 构造时为 0）。
- **语义**：valid 表示"**曾配置过**"而非"当前配置有效"，单调置 1、永不回 0。
- **与 RTL 的对齐**：`dma_src/dma_dst/dma_len` 只在复位时清除，RTL 不存在"取消配置"机制，故 DUT 的配置状态同样是单调的；DMA 对寄存器的消耗（`dma_src++` / `dma_len--`，`apb_device.v:218/237`）由 scoreboard 的 `model_src++` / `model_len--` 镜像，地址模型始终与 DUT 指针同步。
- **两层检查分工**："从未配置就发命令"由 valid 检查（INIT/COPY 分支的 fail）接住，仅在测试初期可触发；"配置被消耗后重发"由 `model_len == 0` / `model_len > 16` 检查接住——两层合起来覆盖全部时序。
- **唯一不一致点**：复位注入。RTL 复位把配置寄存器归 0，而 scoreboard valid 残留为 1 → 复位后未重新配置即发命令，scoreboard 会按旧地址 enqueue 预期、与 DUT 从 0 地址发起的行为 mismatch。处理方式见 TB-01 修法。
- **面试口径**："valid 是'曾配置过'标志，单调置 1 是刻意对齐 RTL——配置寄存器只在复位清除，不存在取消配置；配置被消耗的场景由 model_len--/model_src++ 镜像后经合法性检查接住。唯一边界是复位，已列入 reset 建模计划。"

## D. 关联文档

- [后续优化方案.md](./后续优化方案.md)：BUG-01 的修复代码与验证补充
- [DMA_APB_Verification_Testplan.md](./DMA_APB_Verification_Testplan.md)：SPEC-TBD-03/05、INT-010、BUSY-006/007、RST-002~004
- [../覆盖率bin分析与随机模型规划.md](../覆盖率bin分析与随机模型规划.md)：TB-01/02/03 的加固计划与面试防守要点
