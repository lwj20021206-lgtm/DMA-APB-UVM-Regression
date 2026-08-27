# IRQ Guard 最小对照用例（仅新增代码）

## 1. 追加到 `sequences/dma_apb_coverage_sequences.sv`

```systemverilog
class dma_apb_irq_guard_demo_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_irq_guard_demo_sequence)

  function new(string name = "dma_apb_irq_guard_demo_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] unused_read_data;

    // CASE 1: IRQ已经可见时，cpu_transfer内部guard能够生效。
    // 这里先故意等到pending=1，再调用cpu_transfer。它会停在
    // wait_for_interrupt_idle()，直到handler读取并清除DMA_INT。
    // 波形中0x0000_0a00的DIRECT写应当出现在DMA_INT读/清除之后。
    `uvm_info("IRQ_GUARD_DEMO",
      "CASE1: guarded transfer starts while IRQ is already pending",
      UVM_LOW)

    cpu_write(DMA_SRC_REG, 32'h0600_0000);
    write_dma_length(4);
    cpu_write(DMA_INIT_REG, 32'h1111_1111);
    wait (p_sequencer.interrupt_pending);
    cpu_transfer(
      1'b1, 32'h0000_0a00, 32'haaaa_0001, unused_read_data
    );
    // 对齐base sequence内部的ISR服务计数。此时服务已完成，
    // 所以这个wait会立即通过。
    wait_for_next_interrupt();

    // CASE 2: 只使用cpu_transfer内部的interrupt guard。
    // INIT上游刚握手完时，下游DMA还没有产生IRQ，所以guard
    // 会看到pending=0/level=0并直接放行。DIRECT事务会先进入
    // 上游APB并等待DMA结束；稍后IRQ到来也不能打断已在driver
    // 中的事务。这是guard的关键边界：它只检查“当下”的IRQ。
    `uvm_info("IRQ_GUARD_DEMO",
      "CASE2: immediate guarded transfer; future IRQ is not predicted",
      UVM_LOW)

    cpu_write(DMA_SRC_REG, 32'h0610_0000);
    write_dma_length(4);
    cpu_write(DMA_INIT_REG, 32'h2222_2222);
    cpu_transfer(
      1'b1, 32'h0000_0b00, 32'hbbbb_0002, unused_read_data
    );
    wait_for_next_interrupt();

    // CASE 3: 显式跳过interrupt guard。
    // 这个API完全不查pending/level，用于故意构造busy期间访问。
    // 本case在IRQ拉高前就提交DIRECT事务，确保它已经进入driver；
    // 后到的高优先级ISR只能等待当前APB item完成。
    `uvm_info("IRQ_GUARD_DEMO",
      "CASE3: immediate transfer without IRQ guard",
      UVM_LOW)

    cpu_write(DMA_SRC_REG, 32'h0620_0000);
    write_dma_length(4);
    cpu_write(DMA_INIT_REG, 32'h3333_3333);
    cpu_transfer_without_irq_guard(
      1'b1, 32'h0000_0c00, 32'hcccc_0003, unused_read_data
    );
    wait_for_next_interrupt();
  endtask
endclass
```

## 2. 追加到 `tests/dma_apb_tests.sv`

```systemverilog
class dma_apb_irq_guard_demo_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_irq_guard_demo_test)

  function new(
    string name = "dma_apb_irq_guard_demo_test",
    uvm_component parent = null
  );
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(
      dma_apb_irq_guard_demo_sequence::type_id::get()
    );
    set_slave_sequence(
      apb_slave_coverage_sequence::type_id::get()
    );
  endfunction
endclass
```
