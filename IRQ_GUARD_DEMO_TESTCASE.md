# 无 IRQ Guard 的中断仲裁对照用例（仅新增代码）

## 1. 追加到 `sequences/dma_apb_coverage_sequences.sv`

```systemverilog
// One child sequence owns exactly one APB item.  It deliberately contains no
// interrupt guard and no call to cpu_write/cpu_read/wait_for_next_interrupt.
class dma_apb_no_guard_item_sequence extends uvm_sequence #(apb_master_item);
  string     item_tag;
  bit        item_write;
  bit [31:0] item_address;
  bit [31:0] item_write_data;
  bit [31:0] item_read_data;

  `uvm_object_utils(dma_apb_no_guard_item_sequence)

  function new(string name = "dma_apb_no_guard_item_sequence");
    super.new(name);
  endfunction

  task body();
    apb_master_item item;

    item = apb_master_item::type_id::create(
      $sformatf("raw_%s", item_tag)
    );

    `uvm_info("NO_GUARD_ARB", $sformatf(
      "REQUEST %-18s write=%0b addr=0x%08h data=0x%08h",
      item_tag, item_write, item_address, item_write_data
    ), UVM_LOW)

    // start_item() waits only for sequencer arbitration.  There is no check
    // of interrupt_pending or interrupt_level before this request is queued.
    start_item(item);

    `uvm_info("NO_GUARD_ARB", $sformatf(
      "GRANT   %-18s write=%0b addr=0x%08h",
      item_tag, item_write, item_address
    ), UVM_LOW)

    item.addr        = item_address;
    item.write       = item_write;
    item.data        = item_write_data;
    item.addr_delay  = 0;
    item.ready_delay = 0;

    // finish_item() returns only after the driver calls item_done().  An IRQ
    // sequence cannot preempt this item after the driver has accepted it.
    finish_item(item);

    item_read_data = item.data;
    `uvm_info("NO_GUARD_ARB", $sformatf(
      "DONE    %-18s write=%0b addr=0x%08h read_data=0x%08h",
      item_tag, item_write, item_address, item_read_data
    ), UVM_LOW)
  endtask
endclass


class dma_apb_no_irq_guard_arbitration_sequence
  extends apb_master_base_sequence;

  localparam int CPU_PRIORITY = 100;

  `uvm_object_utils(dma_apb_no_irq_guard_arbitration_sequence)

  function new(
    string name = "dma_apb_no_irq_guard_arbitration_sequence"
  );
    super.new(name);
  endfunction

  task automatic raw_transfer(
    input  string     item_tag,
    input  bit        write,
    input  bit [31:0] address,
    input  bit [31:0] write_data,
    output bit [31:0] read_data
  );
    dma_apb_no_guard_item_sequence item_sequence;

    item_sequence = dma_apb_no_guard_item_sequence::type_id::create(
      $sformatf("%s_sequence", item_tag)
    );
    item_sequence.item_tag        = item_tag;
    item_sequence.item_write      = write;
    item_sequence.item_address    = address;
    item_sequence.item_write_data = write_data;

    // All normal CPU items use priority 100.  The existing IRQ handler starts
    // its status-read and W1C items at priority 1000.
    item_sequence.start(p_sequencer, this, CPU_PRIORITY);
    read_data = item_sequence.item_read_data;
  endtask

  task automatic raw_write(
    input string     item_tag,
    input bit [31:0] address,
    input bit [31:0] write_data
  );
    bit [31:0] unused_read_data;
    raw_transfer(
      item_tag, 1'b1, address, write_data, unused_read_data
    );
  endtask

  task automatic raw_read(
    input  string     item_tag,
    input  bit [31:0] address,
    output bit [31:0] read_data
  );
    raw_transfer(item_tag, 1'b0, address, 32'h0, read_data);
  endtask

  task body();
    bit          completed;
    bit          blocker_done;
    bit          blocker_in_access;
    bit          queued_cpu_start_called;
    bit          irq_pending_while_blocker_active;
    bit          irq_read_seen;
    bit          irq_read_before_queued_cpu;
    bit          irq_w1c_seen;
    bit          queued_cpu_setup_seen;
    bit [31:0]   interrupt_status;
    int unsigned interrupt_count_before;
    int unsigned prefill_index;
    int unsigned service_count_before;

    completed                      = 1'b0;
    blocker_done                   = 1'b0;
    blocker_in_access              = 1'b0;
    queued_cpu_start_called           = 1'b0;
    irq_pending_while_blocker_active  = 1'b0;
    irq_read_seen                     = 1'b0;
    irq_read_before_queued_cpu        = 1'b0;
    irq_w1c_seen                      = 1'b0;
    queued_cpu_setup_seen             = 1'b0;
    interrupt_count_before = p_sequencer.interrupt_count;
    service_count_before   = p_sequencer.serviced_interrupt_count;

    fork : scenario_or_watchdog
      begin : no_guard_scenario
        // Even configuration and the INIT command are raw accesses.  No
        // transaction in this testcase calls an IRQ-aware CPU helper.
        // Five DIRECT writes advance apb_slave_coverage_sequence so the first
        // INIT response uses its long-delay slot.  This creates a stable
        // window in which the low-priority CPU child requests first and the
        // later priority-1000 IRQ request must win arbitration.
        for (prefill_index = 0; prefill_index < 5; prefill_index++)
          raw_write(
            $sformatf("prefill_%0d", prefill_index),
            32'h0000_0c00 + prefill_index,
            32'h5a00_0000 + prefill_index
          );

        raw_write("cfg_src", DMA_SRC_REG, 32'h0700_0000);
        raw_write("cfg_len", DMA_LEN_REG, 32'd16);
        raw_write("start_init", DMA_INIT_REG, 32'h1357_9bdf);

        fork : arbitration_window
          begin : active_cpu_item
            // This DIRECT item enters the driver while INIT is busy.  It is
            // the non-preemptible current item in the arbitration experiment.
            raw_write(
              "active_blocker",
              32'h0000_0d00,
              32'ha5a5_0001
            );
            blocker_done = 1'b1;
          end

          begin : queued_cpu_item
            // Queue a second, low-priority CPU sequence while the blocker is
            // already in APB ACCESS and waiting for PREADY.
            forever begin
              @(p_sequencer.APB_VMINTF.monitor_cb);
              if (p_sequencer.APB_VMINTF.monitor_cb.psel &&
                  p_sequencer.APB_VMINTF.monitor_cb.penable &&
                  !p_sequencer.APB_VMINTF.monitor_cb.pready &&
                  (p_sequencer.APB_VMINTF.monitor_cb.paddr ==
                   32'h0000_0d00)) begin
                blocker_in_access = 1'b1;
                break;
              end
            end

            if (p_sequencer.interrupt_pending)
              `uvm_fatal("IRQ_TOO_EARLY",
                {"IRQ was already pending before the low-priority CPU ",
                 "request; this run cannot prove priority arbitration"})

            queued_cpu_start_called = 1'b1;
            raw_write(
              "queued_cpu",
              DMA_DST_REG,
              32'h0710_0000
            );
          end

          begin : observe_irq_queue
            wait (blocker_in_access && queued_cpu_start_called);
            wait (p_sequencer.interrupt_pending);
            if (!blocker_done)
              irq_pending_while_blocker_active = 1'b1;
          end

          begin : observe_grant_order_and_w1c
            // APB SETUP appears only after the corresponding sequence has
            // won arbitration and the driver has accepted its item.
            forever begin
              @(p_sequencer.APB_VMINTF.monitor_cb);
              if (p_sequencer.APB_VMINTF.monitor_cb.presetn &&
                  p_sequencer.APB_VMINTF.monitor_cb.psel &&
                  !p_sequencer.APB_VMINTF.monitor_cb.penable) begin
                if ((p_sequencer.APB_VMINTF.monitor_cb.paddr ==
                     DMA_INT_REG) &&
                    !p_sequencer.APB_VMINTF.monitor_cb.pwrite) begin
                  irq_read_seen = 1'b1;
                  if (!queued_cpu_setup_seen)
                    irq_read_before_queued_cpu = 1'b1;
                  `uvm_info("NO_GUARD_ARB",
                    "OBSERVE IRQ status-read SETUP", UVM_LOW)
                end

                if ((p_sequencer.APB_VMINTF.monitor_cb.paddr ==
                     DMA_DST_REG) &&
                    p_sequencer.APB_VMINTF.monitor_cb.pwrite) begin
                  queued_cpu_setup_seen = 1'b1;
                  `uvm_info("NO_GUARD_ARB",
                    "OBSERVE queued CPU SETUP", UVM_LOW)
                end

                if ((p_sequencer.APB_VMINTF.monitor_cb.paddr ==
                     DMA_INT_REG) &&
                    p_sequencer.APB_VMINTF.monitor_cb.pwrite &&
                    (p_sequencer.APB_VMINTF.monitor_cb.pwdata[3:0] !=
                     4'b0000)) begin
                  irq_w1c_seen = 1'b1;
                  `uvm_info("NO_GUARD_ARB", $sformatf(
                    "OBSERVE IRQ W1C SETUP data=0x%0h",
                    p_sequencer.APB_VMINTF.monitor_cb.pwdata[3:0]
                  ), UVM_LOW)
                end
              end

              if (queued_cpu_setup_seen && irq_w1c_seen)
                break;
            end
          end
        join

        if (!queued_cpu_start_called)
          `uvm_fatal("QUEUE_NOT_CREATED",
            "The low-priority CPU request was never queued")

        if (!irq_pending_while_blocker_active)
          `uvm_fatal("IRQ_NOT_QUEUED",
            "IRQ did not become pending while the blocker item was active")

        if (!irq_read_seen)
          `uvm_fatal("IRQ_READ_MISSING",
            "The handler never drove a DMA_INT status read")

        if (!irq_read_before_queued_cpu)
          `uvm_fatal("IRQ_PRIORITY_FAILED",
            {"The queued low-priority CPU item reached the driver before ",
             "the priority-1000 IRQ status read"})

        if (!irq_w1c_seen)
          `uvm_fatal("IRQ_W1C_MISSING",
            "The handler never drove a nonzero DMA_INT W1C write")

        // This is an end-of-test observer, not an interrupt guard: every CPU
        // item above has already been requested without checking IRQ state.
        wait ((p_sequencer.interrupt_count > interrupt_count_before) &&
              (p_sequencer.serviced_interrupt_count >
               service_count_before));
        uvm_wait_for_nba_region();
        wait (!p_sequencer.interrupt_pending &&
              !p_sequencer.interrupt_level);

        // A final raw read proves that the handler's W1C operation cleared
        // DMA_INT.  This read also has no IRQ guard.
        raw_read("final_int_read", DMA_INT_REG, interrupt_status);
        if (interrupt_status[3:0] !== 4'b0000)
          `uvm_fatal("IRQ_NOT_CLEARED", $sformatf(
            "DMA_INT remained 0x%0h after handler service",
            interrupt_status[3:0]
          ))

        completed = 1'b1;
      end

      begin : watchdog
        repeat (5000) @(p_sequencer.APB_VMINTF.monitor_cb);
        if (!completed)
          `uvm_fatal("IRQ_ARB_TIMEOUT",
            "No-guard traffic or interrupt service did not complete")
      end
    join_any
    disable scenario_or_watchdog;
  endtask
endclass
```

## 2. 追加到 `tests/dma_apb_tests.sv`

```systemverilog
class dma_apb_no_irq_guard_arbitration_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_no_irq_guard_arbitration_test)

  function new(
    string name = "dma_apb_no_irq_guard_arbitration_test",
    uvm_component parent = null
  );
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(
      dma_apb_no_irq_guard_arbitration_sequence::type_id::get()
    );
    set_slave_sequence(
      apb_slave_coverage_sequence::type_id::get()
    );
  endfunction
endclass
```
