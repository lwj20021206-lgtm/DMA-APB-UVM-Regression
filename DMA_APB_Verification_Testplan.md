# DMA-APB DUT Verification Test Plan

## 文档控制

| 项目 | 内容 |
|---|---|
| 文档名称 | DMA-APB DUT Verification Test Plan |
| 文档编号 | DMA-APB-TP-001 |
| 版本 | v1.0 |
| 状态 | Draft / Baseline |
| DUT | `APB_DEVICE` |
| 验证语言/方法学 | SystemVerilog / UVM |
| 编制日期 | 2026-08-10 |
| 编制人 | TBD |
| 审核人 | TBD |

### 修订记录

| 版本 | 日期 | 修订内容 | 修订人 |
|---|---|---|---|
| v1.0 | 2026-08-10 | 建立首版验证范围、测试点、checker与coverage映射 | TBD |

## 1. 文档目的

本文档定义 `APB_DEVICE` 的功能验证范围、验证策略、测试点、预期结果、检查机制、覆盖率模型及退出准则，用于指导测试开发、回归执行和覆盖率收敛。

本文档以当前 `apb_device.v` 的可观察行为为基线。若RTL行为与正式设计规格不一致，应优先更新规格、登记设计问题，并据最终规格调整预期结果，不能仅为了使测试通过而修改scoreboard。

## 2. 验证目标

验证以下内容：

- 上游APB接口能够正确完成direct access、寄存器访问和DMA命令访问；
- DMA INIT能够按照SRC、LEN和初始化值产生正确的下游写传输；
- DMA COPY能够按照SRC、DST和LEN产生正确的读写序列及复制数据；
- 非法操作、非法长度、地址重叠和DMA完成状态能够正确进入中断状态；
- `DMA_INT` W1C、中断引脚和CPU中断服务流程行为正确；
- DUT在下游wait state、上游阻塞、back-to-back访问和复位场景下行为正确；
- 所有已完成的下游传输在地址、方向、数据、顺序和次数上均符合reference model；
- APB协议断言无失败，功能覆盖率和代码覆盖率达到退出目标。

## 3. 验证范围

### 3.1 范围内

- 上游APB slave接口；
- 下游APB master接口；
- direct read/write数据通路；
- DMA SRC、DST、LEN、INIT、COPY和INT区域；
- DMA INIT/COPY控制及数据通路；
- 中断状态、W1C及中断调度；
- busy期间CPU访问；
- 上下游wait state；
- idle、APB事务和DMA执行期间复位；
- 功能覆盖率、断言覆盖率和代码覆盖率。

### 3.2 范围外

- 多时钟域与CDC验证；
- 低功耗、UPF和电源状态验证；
- DFT、scan和MBIST；
- 门级时序仿真；
- 软件驱动及操作系统级验证；
- 未提供规格的吞吐率、功耗和面积指标。

## 4. 参考资料

| 编号 | 资料 | 用途 |
|---|---|---|
| REF-01 | `apb_device.v` | 当前DUT实现基线 |
| REF-02 | `src/apb_intf.sv` | APB接口和clocking block定义 |
| REF-03 | `apb_device_src/apb_device_scoreboard.sv` | Reference model与检查实现 |
| REF-04 | `apb_device_src/apb_device_coverage_full.sv` | 功能覆盖率实现 |
| REF-05 | AMBA APB Protocol Specification | APB协议规则，版本TBD |

## 5. DUT概述

### 5.1 数据通路

```text
UVM APB Master / CPU
          |
          | 上游APB
          v
     APB_DEVICE DUT
          |
          | 下游APB
          v
UVM Reactive Slave / Memory Model
```

DUT在上游表现为APB slave，在下游表现为APB master。CPU既可以通过direct区域访问下游memory，也可以配置DMA寄存器并启动INIT或COPY。

### 5.2 地址区域

| `PADDR[31:28]` | 名称 | 合法方向 | 功能 |
|---:|---|---|---|
| `4'h0` | DIRECT | R/W | 低28位映射为下游地址 |
| `4'h1` | DMA_SRC | R/W | DMA源/INIT起始地址 |
| `4'h2` | DMA_DST | R/W | DMA COPY目的地址 |
| `4'h3` | DMA_LEN | R/W | DMA传输长度 |
| `4'h4` | DMA_INIT | W | 写入初始化值并启动INIT |
| `4'h8` | DMA_COPY | W | 启动COPY，写数据无功能含义 |
| `4'hf` | DMA_INT | R/W1C | 中断状态读取和清除 |
| `4'h5～7`、`4'h9～e` | RESERVED | 无 | 非法操作 |

### 5.3 中断状态

| 位 | 名称 | 当前RTL置位条件 | 清除方式 |
|---:|---|---|---|
| `[0]` | done | INIT写完成或COPY目的写完成 | W1C |
| `[1]` | overlap | COPY源/目的范围发生前向或后向重叠 | W1C |
| `[2]` | invalid_length | LEN为0或大于16 | W1C |
| `[3]` | invalid_op | 访问未定义区域或非法命令方向 | W1C |

`apb_device_int` 为中断状态寄存器的按位或结果。

## 6. 待确认规格与验证假设

以下内容必须在设计评审中确认。确认前，scoreboard按照当前RTL行为建模，同时将差异作为design issue记录。

| ID | 待确认内容 | 当前RTL行为 | 建议规格方向 |
|---|---|---|---|
| SPEC-TBD-01 | done中断的准确时刻 | 每个INIT写或COPY目的写完成时均可置位 | 建议仅最后一笔完成时表示DMA done |
| SPEC-TBD-02 | overlap后的COPY是否执行 | 置位overlap，但COPY仍继续 | 明确继续、拒绝或终止策略 |
| SPEC-TBD-03 | 非法LEN是否更新寄存器 | 置位中断，同时低5位仍写入LEN | 建议非法写不修改原值 |
| SPEC-TBD-04 | 地址步长单位 | SRC/DST每次加1 | 明确地址单位为byte还是word |
| SPEC-TBD-05 | DMA busy期间CPU访问 | 上游访问通过wait state等待DMA结束 | 建议至少允许INT/STATUS访问 |
| SPEC-TBD-06 | direct write完成语义 | 上游响应与下游写完成未严格绑定 | 明确是否允许posted write |
| SPEC-TBD-07 | SRC/DST/LEN高位处理 | SRC/DST截断为28位，LEN截断为5位 | 明确截断、报错或保留行为 |
| SPEC-TBD-08 | 地址回绕 | 28位地址自然回绕 | 明确是否允许或应产生错误 |
| SPEC-TBD-09 | 错误响应 | 接口无`PSLVERR` | 明确所有错误仅通过中断报告 |

## 7. 验证环境与检查策略

### 7.1 UVM组件

| 组件 | 作用 |
|---|---|
| APB master agent | 产生CPU访问，监控上游请求、完成事务和interrupt边沿 |
| Interrupt handler | 在当前APB事务边界启动高优先级ISR sequence |
| APB slave agent | 响应DUT下游请求，并维护reactive memory |
| Scoreboard | 建模寄存器、memory和预期下游传输，比较地址/方向/数据/顺序/次数 |
| Functional coverage | 采集命令、LEN、地址关系、中断、wait state、reset和busy场景 |
| Assertions | 检查APB控制、稳定性、握手和复位规则 |

### 7.2 中断调度策略

- 已进入APB setup/access的事务不允许被中断sequence强行取消；
- 当前事务完成后，interrupt sequence以高优先级取得master sequencer；
- CPU读取`DMA_INT`获取原因；
- CPU使用读回状态作为W1C mask；
- 中断清除后，普通CPU sequence继续执行；
- scoreboard检查中断状态读回值、W1C结果和最终引脚状态。

### 7.3 Scoreboard检查层次

1. 上游setup请求用于提前预测direct下游访问。
2. 上游完成事务用于更新寄存器模型、创建INIT/COPY预期序列和检查读回值。
3. 下游完成事务逐笔与预期队列比较。
4. Reference memory检查下游读数据并记录所有完成写。
5. COPY读数据进入临时队列，随后的目的写必须使用相同数据。
6. 测试结束时预期队列、COPY临时数据和中断状态必须全部清空。

### 7.4 计划增加的验证控制项

为了稳定地产生并发及异常时序场景，后续testbench应提供以下可配置knob：

| 配置项 | 用途 | 关联测试点 |
|---|---|---|
| `auto_irq_service_en` | 允许关闭自动ISR，以产生多原因累积及延迟清除 | INT-005、INT-010 |
| `irq_service_delay` | 控制CPU从观察到interrupt到启动ISR的延迟 | INT-012、INT-013 |
| `slave_ready_delay_min/max` | 控制下游0 wait、短等待及长等待 | DIR-009、COPY-012/013、SAPB-007 |
| `reset_inject_phase` | 在idle/setup/access/INIT/COPY指定阶段注入reset | RST-002～009 |
| `max_apb_wait_cycles` | 检测永久阻塞并给出明确timeout | BUSY-008 |
| `enable_negative_commands` | 允许绕过合法transaction约束产生reserved/非法方向访问 | REG-007～009 |

## 8. 详细功能测试点

优先级定义：P0为smoke/基本功能，P1为主要功能与边界，P2为鲁棒性与覆盖率收敛。

本节测试点已建立对应的定向及随机testcase；在真实VCS回归完成并归档log/coverage之前，对应测试点仍不标记为closed。已知不可达或与当前RTL/scoreboard语义冲突的bin见`README.md`中的Coverage waiver。

### 8.1 Reset测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| RST-001 | 上电复位 | 初始拉低`presetn`后释放 | 寄存器、状态机、中断和APB输出回到复位值 | Scoreboard + assertion | reset idle | P0 |
| RST-002 | idle期间复位 | 无APB/DMA活动时复位 | 无虚假下游传输及中断 | Monitor + scoreboard | reset idle | P1 |
| RST-003 | 上游setup期间复位 | `PSEL=1,PENABLE=0`时复位 | 当前事务取消，接口回到idle | Assertion + scoreboard | reset setup | P1 |
| RST-004 | 上游access/wait期间复位 | `PSEL=1,PENABLE=1,PREADY=0`时复位 | 当前事务取消，无错误完成采样 | Assertion + scoreboard | reset access | P1 |
| RST-005 | 下游setup/access期间复位 | DUT已发起下游传输时复位 | 下游控制信号回到复位状态 | Assertion + monitor | slave reset phase | P1 |
| RST-006 | INIT执行期间复位 | INIT尚未完成时复位 | DMA停止；寄存器/中断按规格复位 | Scoreboard reset model | reset × INIT busy | P1 |
| RST-007 | COPY读阶段复位 | source read阶段复位 | 不产生残留destination write | Scoreboard expected queue | reset × COPY read | P1 |
| RST-008 | COPY写阶段复位 | destination write阶段复位 | 当前/后续行为符合规格，无悬挂事务 | Scoreboard + assertion | reset × COPY write | P1 |
| RST-009 | 中断有效时复位 | `apb_device_int=1`时复位 | INT状态和引脚清零 | Pin monitor + register read | interrupt × reset | P1 |

### 8.2 上游APB与Direct Access测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| DIR-001 | 默认地址读取 | 读取未初始化direct地址 | 返回0 | Reference memory | direct read | P0 |
| DIR-002 | 基本写后读 | 写随机数据后读同一地址 | 读回写入数据 | Scoreboard | direct R/W | P0 |
| DIR-003 | 多地址独立性 | 对多个地址写不同数据后乱序读取 | 各地址数据互不影响 | Reference memory | address diversity | P1 |
| DIR-004 | 数据典型值 | 写0、全1、AAAA、5555、one-hot和随机值 | 数据无位错误 | Scoreboard | data classes | P1 |
| DIR-005 | 低28位地址映射 | 改变direct地址低28位 | 下游地址等于`PADDR[27:0]` | Downstream scoreboard | target other | P0 |
| DIR-006 | 地址边界 | 访问`0`、低位边界和`28'hfff_ffff` | 地址与数据正确，无非预期回绕 | Scoreboard | address boundary | P1 |
| DIR-007 | back-to-back访问 | 连续R/R、R/W、W/R、W/W | 每笔事务只完成一次，数据正确 | Assertion + scoreboard | region × RW | P1 |
| DIR-008 | 上游wait state | 覆盖0、1、2～3、4～7、8拍以上等待 | 控制/地址/写数据稳定 | Wait coverage + SVA | master wait bins | P1 |
| DIR-009 | 下游wait state传播 | direct read时随机延迟下游PREADY | 上游读仅在有效数据后完成 | Scoreboard + SVA | slave wait bins | P1 |
| DIR-010 | direct write完成语义 | 下游写长延迟 | 上游响应和下游完成关系符合规格 | Timeline checker | master/slave completion | P1 |

### 8.3 DMA寄存器访问测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| REG-001 | SRC读写 | 写SRC后读回 | 返回低28位配置值 | Register model | SRC R/W | P0 |
| REG-002 | DST读写 | 写DST后读回 | 返回低28位配置值 | Register model | DST R/W | P0 |
| REG-003 | LEN合法读写 | 写1～16后读回 | 返回对应低5位值 | Register model | LEN legal bins | P0 |
| REG-004 | 配置覆盖写 | 同一寄存器连续写不同值 | 后写值生效 | Register model | back-to-back writes | P1 |
| REG-005 | SRC/DST高位 | 写高4位非零数据 | 按规格截断或报错 | Register model | address high bits | P1 |
| REG-006 | LEN高位 | 写32位高位非零数据 | 按规格处理并产生正确中断 | Register + interrupt model | LEN too large | P1 |
| REG-007 | INIT区域非法读 | 对`4'h4`执行read | 产生invalid-op，无DMA启动 | Interrupt + downstream monitor | invalid op | P1 |
| REG-008 | COPY区域非法读 | 对`4'h8`执行read | 产生invalid-op，无DMA启动 | Interrupt + downstream monitor | invalid op | P1 |
| REG-009 | 保留区域访问 | 遍历`5～7`和`9～e`区域 | 每类访问产生invalid-op | Interrupt model | reserved × R/W | P1 |

### 8.4 LEN边界与非法长度测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| LEN-001 | 长度0 | 写LEN=0 | invalid-length置位 | Interrupt model | LEN zero | P0 |
| LEN-002 | 最小合法长度 | 写LEN=1并执行INIT/COPY | 恰好1个元素完成 | Transfer counter | LEN minimum | P0 |
| LEN-003 | 普通合法长度 | LEN取2、3及随机2～15 | 恰好LEN个元素完成 | Transfer counter | LEN normal bins | P1 |
| LEN-004 | 最大合法长度 | LEN=16 | 恰好16个元素完成 | Transfer counter | LEN maximum | P0 |
| LEN-005 | 刚超界 | LEN=17 | invalid-length置位 | Interrupt model | LEN too large | P0 |
| LEN-006 | 大值/全1 | LEN取31、32、`ffff_ffff` | 中断及寄存器副作用符合规格 | Register + interrupt model | too-large classes | P1 |
| LEN-007 | 非法LEN后启动命令 | 写非法LEN后执行INIT/COPY | 按规格拒绝、执行截断值或报错 | Scoreboard + issue tracking | command × invalid LEN | P1 |

### 8.5 DMA INIT测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| INIT-001 | 基本INIT | 配置SRC、LEN=4，写INIT数据 | 从SRC开始连续4次下游写 | Expected transfer queue | INIT × normal LEN | P0 |
| INIT-002 | LEN=1 | 最小长度INIT | 仅1次写，地址和数据正确 | Transfer counter | INIT × LEN1 | P0 |
| INIT-003 | LEN=16 | 最大长度INIT | 16次写，无多写/少写 | Transfer counter | INIT × LEN16 | P0 |
| INIT-004 | INIT数据模式 | 0、全1、AAAA、5555、one-hot、随机 | 每笔写数据等于INIT值 | Scoreboard | INIT data class | P1 |
| INIT-005 | 地址递增 | 随机SRC与LEN | 地址序列为`SRC+i` | Scoreboard | target source | P0 |
| INIT-006 | 下游等待 | 每笔写随机ready delay | 请求保持稳定且不丢传输 | SVA + scoreboard | slave write wait | P1 |
| INIT-007 | 完成状态 | 执行完整INIT | done/interrupt时序符合规格 | Interrupt model | INIT × done | P0 |
| INIT-008 | 连续INIT | 完成后重新配置SRC/LEN再启动 | 两次任务相互独立 | Scoreboard | command repetition | P1 |
| INIT-009 | 地址末端 | SRC靠近28位最大值且LEN跨界 | 回绕/错误行为符合规格 | Scoreboard | address wrap | P2 |

### 8.6 DMA COPY测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| COPY-001 | 基本COPY | 初始化source，配置SRC/DST/LEN=4并COPY | 目的区域等于源区域 | Reference memory | COPY × normal LEN | P0 |
| COPY-002 | LEN=1 | 单元素COPY | 1次读后1次写 | Transfer sequence checker | COPY × LEN1 | P0 |
| COPY-003 | LEN=16 | 最大长度COPY | 16组read/write，无丢失 | Transfer counter | COPY × LEN16 | P0 |
| COPY-004 | 读写顺序 | 任意合法LEN | 每个元素必须先source read再destination write | Expected queue | read/write direction | P0 |
| COPY-005 | 数据完整性 | source使用典型值及随机值 | 写数据等于对应read返回数据 | COPY data queue | data classes | P0 |
| COPY-006 | SRC=DST | 两地址相等 | 数据保持正确，overlap位按规格 | Scoreboard + interrupt | relation equal | P1 |
| COPY-007 | 前向重叠 | `SRC<DST<SRC+LEN` | overlap置位；数据/执行策略符合规格 | Scoreboard + interrupt | forward overlap | P1 |
| COPY-008 | 后向重叠 | `DST<SRC<DST+LEN` | overlap置位；数据/执行策略符合规格 | Scoreboard + interrupt | backward overlap | P1 |
| COPY-009 | 前向相邻 | `DST=SRC+LEN` | 不产生overlap，COPY正确 | Scoreboard | forward adjacent | P1 |
| COPY-010 | 后向相邻 | `SRC=DST+LEN` | 不产生overlap，COPY正确 | Scoreboard | backward adjacent | P1 |
| COPY-011 | 完全分离 | 两区域无相交 | 不产生overlap，COPY正确 | Scoreboard | disjoint | P0 |
| COPY-012 | 下游读等待 | source read随机ready delay | read控制保持且数据采集一次 | SVA + scoreboard | read wait bins | P1 |
| COPY-013 | 下游写等待 | destination write随机ready delay | 写控制和数据保持稳定 | SVA + scoreboard | write wait bins | P1 |
| COPY-014 | 连续COPY | 每次重新配置SRC/DST/LEN | 每条命令独立完成 | Scoreboard | repeated COPY | P1 |
| COPY-015 | 地址末端 | SRC/DST靠近28位最大值 | 回绕/错误符合规格 | Scoreboard | address wrap | P2 |

### 8.7 Interrupt与W1C测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| INT-001 | done中断 | 完成INIT或COPY | status[0]及引脚有效 | Register + pin monitor | done active | P0 |
| INT-002 | overlap中断 | 执行重叠COPY | status[1]有效 | Interrupt model | overlap active | P0 |
| INT-003 | invalid-length中断 | 写0或大于16 | status[2]有效 | Interrupt model | invalid length active | P0 |
| INT-004 | invalid-op中断 | 访问reserved/非法方向 | status[3]有效 | Interrupt model | invalid op active | P0 |
| INT-005 | 多原因累积 | 清除前依次触发多个原因 | 状态位按OR累积 | Interrupt model | multiple causes | P1 |
| INT-006 | 单bit W1C | 分别写`1,2,4,8` | 只清除对应位 | Register model | clear each bit | P0 |
| INT-007 | 多bit W1C | 写多个有效位 | mask中的有效位清除 | Register model | clear mask | P1 |
| INT-008 | W1C写0 | 写`0` | 状态保持不变 | Register model | clear not requested | P1 |
| INT-009 | 清除未置位bit | mask包含未置位位 | 已置位的非mask位保持 | Register model | partial clear | P1 |
| INT-010 | 置位与清除同拍 | 新事件和W1C并发 | 优先级符合规格，事件不丢失 | Directed timing test | set × clear | P1 |
| INT-011 | 引脚转换 | 触发后清除全部状态 | 引脚出现0→1→0 | Pin coverage | IRQ transitions | P0 |
| INT-012 | CPU中断服务 | 中断到来时启动ISR sequence | 读状态、W1C、恢复普通sequence | Sequencer counter + scoreboard | interrupt service | P0 |
| INT-013 | 事务中发生中断 | 普通APB access尚未完成时触发 | 当前事务完成后再进入ISR | APB timeline checker | busy attempt | P1 |

### 8.8 Busy与并发访问测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| BUSY-001 | INIT期间direct读 | INIT busy时发起direct read | 等待/拒绝/并发行为符合规格 | Timeline + scoreboard | busy × direct read | P1 |
| BUSY-002 | INIT期间direct写 | INIT busy时发起direct write | 当前DMA不被破坏 | Timeline + scoreboard | busy × direct write | P1 |
| BUSY-003 | COPY期间读INT | COPY busy时读取INT | 响应策略符合规格 | Wait checker | busy × INT read | P0 |
| BUSY-004 | COPY期间W1C | COPY busy时清中断 | 清除和新事件优先级正确 | Interrupt model | busy × INT write | P1 |
| BUSY-005 | busy期间修改SRC/DST/LEN | DMA执行中发配置写 | 当前/下一任务配置归属符合规格 | Register snapshots | busy × register write | P1 |
| BUSY-006 | busy期间再次INIT | INIT/COPY运行时发INIT | 排队、等待或拒绝策略符合规格 | Command tracker | busy × INIT | P1 |
| BUSY-007 | busy期间再次COPY | INIT/COPY运行时发COPY | 不允许成功握手后静默丢命令 | Command tracker | busy × COPY | P1 |
| BUSY-008 | 长时间下游阻塞 | 下游PREADY长时间为0 | 上下游无协议违例，触发测试超时保护 | SVA + timeout | long wait | P2 |

### 8.9 下游APB协议测试

| TP ID | 验证目标 | 激励/约束 | 预期结果 | 检查机制 | 覆盖点 | 优先级 |
|---|---|---|---|---|---|---:|
| SAPB-001 | setup/access顺序 | 观察所有下游请求 | setup后进入access | SVA | request/completion | P0 |
| SAPB-002 | wait期间稳定性 | access且PREADY=0 | 地址、方向、写数据保持 | SVA | wait bins | P0 |
| SAPB-003 | 单次完成采样 | PREADY完成一笔传输 | monitor只发布一次completion | Transaction counter | completion | P0 |
| SAPB-004 | reactive读响应 | DUT发read，slave返回memory值 | DUT采样正确数据 | Scoreboard | read completion | P0 |
| SAPB-005 | reactive写响应 | DUT发write，slave记录数据 | memory仅在完成后更新 | Scoreboard | write completion | P0 |
| SAPB-006 | 响应方向一致 | sequence响应item与DUT请求方向相同 | 不出现read/write误判 | Driver fatal check | direction × target | P0 |
| SAPB-007 | 随机延迟分布 | ready delay覆盖0～15 | 各wait bin均命中 | Functional coverage | wait cycles | P1 |

## 9. Assertion计划

| Assertion ID | 检查内容 | 适用接口 | 优先级 |
|---|---|---|---:|
| APB-A-001 | `PSEL=0`时`PENABLE=0` | 上游/下游 | P0 |
| APB-A-002 | setup后下一阶段进入access或复位 | 上游/下游 | P0 |
| APB-A-003 | wait期间`PADDR/PWRITE/PWDATA/PSEL/PENABLE`稳定 | 上游/下游 | P0 |
| APB-A-004 | 完成只在`PSEL&&PENABLE&&PREADY`发生 | 上游/下游 | P0 |
| APB-A-005 | reset期间控制输出回到非活动值 | 上游/下游 | P1 |
| DMA-A-001 | 合法INIT下游写次数等于LEN | 下游 | P0 |
| DMA-A-002 | 合法COPY读写次数均等于LEN | 下游 | P0 |
| DMA-A-003 | COPY每次write前存在匹配read | 下游 | P0 |
| DMA-A-004 | busy期间当前DMA配置不被非预期覆盖 | 内部/probe | P1 |
| INT-A-001 | `apb_device_int == |dma_int` | 中断 | P0 |
| INT-A-002 | W1C只清除mask指定状态位 | 中断 | P0 |

## 10. Functional Coverage计划

| Covergroup | 主要coverpoint/cross | 对应测试点 |
|---|---|---|
| `cg_master_access` | 区域、R/W、LEN值、写数据类型、区域×R/W | DIR、REG、LEN |
| `cg_dma_command` | INIT/COPY、LEN分类、地址关系、INIT数据、配置完整性 | INIT、COPY、LEN |
| `cg_interrupt` | 状态读取、四类原因、组合状态、W1C mask | INT |
| `cg_slave_request` | 下游请求方向、source/destination范围、写数据 | INIT、COPY、SAPB |
| `cg_slave_completion` | 真正完成的方向、目标和传输数据 | DIR、INIT、COPY |
| `cg_apb_wait` | 上游/下游、R/W、等待周期分类 | DIR、COPY、SAPB |
| `cg_reset` | idle、setup、access阶段reset | RST |
| `cg_probe_state` | interrupt/busy电平及转换 | INT、BUSY |
| `cg_busy_attempt` | busy×访问区域×R/W | BUSY |

### 10.1 覆盖率目标

| 类型 | 目标 | 说明 |
|---|---:|---|
| 功能覆盖率 | 100% planned legal bins | 非法/不可达bin必须评审后ignore或waive |
| 关键cross覆盖率 | 100% | 命令×LEN、COPY LEN×地址关系等 |
| 断言覆盖率 | 100% attempt，100% pass | 所有关键property必须被触发 |
| Line coverage | ≥95% | 排除仿真专用和不可达代码 |
| Branch/condition coverage | ≥90% | 未覆盖项逐条评审 |
| Toggle coverage | ≥90% | 配置/数据路径重点分析 |
| FSM coverage | 100% state/transition | 若工具可识别DMA控制状态 |

## 11. 测试用例规划

| Testcase | 覆盖范围 | 类型 | 建议seed数 | 状态 |
|---|---|---|---:|---|
| `dma_apb_smoke_test` / `test` | direct、INIT、COPY、invalid LEN、invalid op、ISR smoke | Directed smoke | 1 | Implemented |
| `dma_apb_register_direct_test` | direct数据类、SRC/DST/LEN/INT、reserved区域 | Directed | 1 | Implemented |
| `dma_apb_init_test` | INIT长度类、初始化数据类和wait state | Directed | 1 | Implemented |
| `dma_apb_copy_test` | COPY长度、数据顺序和6类地址关系 | Directed | 1 | Implemented |
| `dma_apb_interrupt_test` | 四类中断、组合状态和W1C | Directed | 1 | Implemented |
| `dma_apb_busy_test` | busy期间的安全CPU访问；命令写作waiver | Directed | 1 | Implemented |
| `dma_apb_reset_test` | idle动态复位；DMA中途复位待scoreboard reset model | Directed | 1 | Partially implemented |
| `dma_apb_target_wait_test` / `dma_apb_wait_state_test` | 上下游等待周期和slave target类别 | Directed + random | 1 | Implemented |
| `dma_apb_random_test` | 安全混合direct/register/DMA流量 | Constrained random | ≥5 seeds | Implemented |
| `dma_apb_full_coverage_test` | 一次串行执行所有定向sequence | Directed | 1 | Implemented |

## 12. 回归策略

| 回归层级 | 内容 | 触发时机 | 通过条件 |
|---|---|---|---|
| Smoke | `test`，基本direct/INIT/COPY/ISR | 每次提交 | 0 UVM_ERROR/FATAL，断言全通过 |
| Feature | 各独立directed testcase | 每日 | 所有P0/P1测试通过 |
| Random | 多seed混合流量 | Nightly | 无新增失败，覆盖率持续增长 |
| Reset/Stress | reset、长wait、busy冲突 | Nightly/Weekly | 无hang、timeout和协议错误 |
| Coverage closure | 定向补洞与waiver审查 | Milestone | 达到退出覆盖率目标 |

所有失败必须保存：随机seed、测试名、仿真器版本、编译参数、UVM log、波形和coverage数据库。

## 13. Entry Criteria

- DUT接口及寄存器映射冻结或变更受控；
- 所有SPEC-TBD项已有临时验证假设；
- UVM环境能够完成编译和smoke运行；
- master/slave agent、scoreboard和coverage连接完成；
- 仿真器支持UVM、SVA和covergroup；
- 回归脚本能够保存seed、log和coverage结果。

## 14. Exit Criteria

- 所有P0和P1测试点已实现并通过；
- Nightly regression连续通过，具体连续次数由项目定义；
- 无未关闭的UVM_ERROR、UVM_FATAL或assertion failure；
- Scoreboard不存在未消费的预期事务、COPY数据或未处理中断；
- 功能覆盖率、关键cross、代码覆盖率和断言覆盖率达到第10.1节目标；
- 所有coverage hole均已补测或完成书面waiver；
- 所有P0/P1 design issue已关闭或获得签核；
- Test Plan、testcase、coverage和bug记录之间可追踪。

## 15. Test Plan评审检查表

- [ ] 每个功能需求至少对应一个正向测试点；
- [ ] 每个错误条件至少对应一个负向测试点；
- [ ] 每个测试点都有明确的预期结果和checker；
- [ ] 所有关键边界值均有定向测试；
- [ ] 所有功能覆盖bin都能追溯到测试点；
- [ ] Scoreboard与coverage职责清晰：scoreboard判对错，coverage判是否发生；
- [ ] reset、wait state、busy和interrupt并发场景已经覆盖；
- [ ] SPEC-TBD项已由设计/架构人员确认；
- [ ] 不可达coverage已记录原因并审核；
- [ ] 回归、退出准则和交付物已得到项目成员认可。
