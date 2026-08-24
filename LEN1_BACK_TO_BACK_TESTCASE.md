# LEN=1 尾拍连续命令复现用例（仅新增代码）

> 这两个 case 用于复现“上一条 LEN=1 DMA 结束时，下一条 INIT/COPY 未重新配置 LEN 就已在上游等待”的问题。当前 RTL/Scoreboard 下它们是预期失败的 bug-reproduction case，不要加入默认 `DIRECTED_TESTS`。

## 1. 追加到 `sequences/dma_apb_coverage_sequences.sv`

```systemverilog
class dma_apb_len1_then_init_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_len1_then_init_sequence)

  function new(string name = "dma_apb_len1_then_init_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] unused_read_data;

    cpu_write(DMA_SRC_REG, 32'h0500_0000);
    write_dma_length(1);

    // 第一条 INIT 上游握手完成后，不等 ISR，立即把第二条
    // INIT 放到上游 APB。中间故意不重新写 DMA_LEN。
    cpu_write(DMA_INIT_REG, 32'h1111_1111);
    cpu_transfer_without_irq_guard(
      1'b1,
      DMA_INIT_REG,
      32'h2222_2222,
      unused_read_data
    );

    wait_for_next_interrupt();
  endtask
endclass

class dma_apb_len1_then_copy_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_len1_then_copy_sequence)

  function new(string name = "dma_apb_len1_then_copy_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] unused_read_data;

    cpu_write(DMA_SRC_REG, 32'h0510_0000);
    cpu_write(DMA_DST_REG, 32'h0520_0000);

    // 预先给第一条 INIT 结束后的 source+1 位置放入可识别数据。
    cpu_write(32'h0510_0001, 32'hcafe_0001);
    write_dma_length(1);

    // 第一条 LEN=1 INIT 将 DUT 内部 LEN 减为 0；第二条 COPY
    // 在不重新写 LEN 的情况下立即排到上游总线。
    cpu_write(DMA_INIT_REG, 32'h3333_3333);
    cpu_transfer_without_irq_guard(
      1'b1,
      DMA_COPY_REG,
      32'h0000_0000,
      unused_read_data
    );

    wait_for_next_interrupt();
  endtask
endclass
```

## 2. 追加到 `tests/dma_apb_tests.sv`

```systemverilog
class dma_apb_len1_then_init_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_len1_then_init_test)

  function new(
    string name = "dma_apb_len1_then_init_test",
    uvm_component parent = null
  );
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(
      dma_apb_len1_then_init_sequence::type_id::get()
    );
  endfunction
endclass

class dma_apb_len1_then_copy_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_len1_then_copy_test)

  function new(
    string name = "dma_apb_len1_then_copy_test",
    uvm_component parent = null
  );
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(
      dma_apb_len1_then_copy_sequence::type_id::get()
    );
  endfunction
endclass
```

## 3. 单独运行

```bash
make vcs_run TEST=dma_apb_len1_then_init_test SEED=1
make vcs_run TEST=dma_apb_len1_then_copy_test SEED=1
```

## 4. 当前预期结果

```text
dma_apb_len1_then_init_test:
  Scoreboard报告第二条INIT使用model_len=0；
  DUT的5位LEN从0下溢到31，产生超出预期的下游写。

dma_apb_len1_then_copy_test:
  Scoreboard报告第二条COPY使用model_len=0；
  DUT可出现一组COPY读/写以及失去COPY phase归属的额外下游读。
```
