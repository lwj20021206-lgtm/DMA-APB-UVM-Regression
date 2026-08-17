class apb_master_base_sequence extends uvm_sequence #(apb_master_item);
  localparam bit [31:0] DIRECT_BASE = 32'h0000_0000;
  localparam bit [31:0] DMA_SRC_REG = 32'h1000_0000;
  localparam bit [31:0] DMA_DST_REG = 32'h2000_0000;
  localparam bit [31:0] DMA_LEN_REG = 32'h3000_0000;
  localparam bit [31:0] DMA_INIT_REG = 32'h4000_0000;
  localparam bit [31:0] DMA_COPY_REG = 32'h8000_0000;
  localparam bit [31:0] DMA_INT_REG = 32'hf000_0000;

  int unsigned expected_interrupt_services;

  `uvm_object_utils(apb_master_base_sequence)
  `uvm_declare_p_sequencer(apb_master_sequencer)

  function new(string name = "apb_master_base_sequence");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    if (p_sequencer == null)
      `uvm_fatal("NOSEQR", "DMA sequence requires apb_master_sequencer")

    expected_interrupt_services =
      p_sequencer.serviced_interrupt_count;

    if (starting_phase != null)
      starting_phase.raise_objection(this);
  endtask

  task post_body();
    if (starting_phase != null)
      starting_phase.drop_objection(this);
    super.post_body();
  endtask

  task automatic wait_for_interrupt_idle();
    uvm_wait_for_nba_region();
    wait (!p_sequencer.interrupt_pending &&
          !p_sequencer.interrupt_level);
  endtask

  task automatic wait_for_next_interrupt();
    expected_interrupt_services++;
    wait (p_sequencer.serviced_interrupt_count >=
          expected_interrupt_services);
    wait_for_interrupt_idle();
  endtask

  task automatic cpu_transfer_impl(
    input  bit        guard_interrupt,
    input  bit        write,
    input  bit [31:0] address,
    input  bit [31:0] bus_write_data,
    output bit [31:0] read_data
  );
    apb_master_item item;

    if (guard_interrupt)
      wait_for_interrupt_idle();

    item = apb_master_item::type_id::create("cpu_item");
    start_item(item);
    item.addr = address;
    item.write = write;
    item.data = bus_write_data;
    item.addr_delay = 0;
    item.ready_delay = 0;
    finish_item(item);
    read_data = item.data;
  endtask

  task automatic cpu_transfer(
    input  bit        write,
    input  bit [31:0] address,
    input  bit [31:0] bus_write_data,
    output bit [31:0] read_data
  );
    cpu_transfer_impl(
      1'b1, write, address, bus_write_data, read_data
    );
  endtask

  // Used only by the busy test.  The item is submitted immediately after a
  // DMA command, so its setup phase can be observed while the DUT is busy.
  task automatic cpu_transfer_without_irq_guard(
    input  bit        write,
    input  bit [31:0] address,
    input  bit [31:0] bus_write_data,
    output bit [31:0] read_data
  );
    cpu_transfer_impl(
      1'b0, write, address, bus_write_data, read_data
    );
  endtask

  task automatic cpu_write(
    input bit [31:0] address,
    input bit [31:0] write_data
  );
    bit [31:0] unused;
    cpu_transfer(1'b1, address, write_data, unused);
  endtask

  task automatic cpu_read(
    input  bit [31:0] address,
    input  bit [31:0] bus_write_data,
    output bit [31:0] read_data
  );
    cpu_transfer(1'b0, address, bus_write_data, read_data);
  endtask

  task automatic write_dma_length(input bit [31:0] length);
    cpu_write(DMA_LEN_REG, length);
    if ((length == 0) || (length > 16))
      wait_for_next_interrupt();
  endtask

  task automatic run_init(
    input bit [27:0] source,
    input bit [31:0] length,
    input bit [31:0] init_data
  );
    cpu_write(DMA_SRC_REG, {4'h0, source});
    write_dma_length(length);
    cpu_write(DMA_INIT_REG, init_data);
    wait_for_next_interrupt();
  endtask

  task automatic fill_source(
    input bit [27:0] source,
    input bit [4:0]  length,
    input bit [31:0] seed_data
  );
    int unsigned index;

    for (index = 0; index < length; index++)
      cpu_write(
        DIRECT_BASE | (source + index),
        seed_data ^ (32'h0101_0101 * index)
      );
  endtask

  task automatic run_copy(
    input bit [27:0] source,
    input bit [27:0] destination,
    input bit [31:0] coverage_length,
    input bit [31:0] seed_data
  );
    bit [4:0] actual_length;

    actual_length = coverage_length[4:0];
    if (actual_length == 0)
      `uvm_fatal("BADLEN", "run_copy cannot execute a zero effective length")

    cpu_write(DMA_SRC_REG, {4'h0, source});
    cpu_write(DMA_DST_REG, {4'h0, destination});
    write_dma_length(coverage_length);
    fill_source(source, actual_length, seed_data);
    cpu_write(DMA_COPY_REG, 32'h0);
    wait_for_next_interrupt();
  endtask

  task automatic pulse_idle_reset(input int unsigned low_cycles = 2);
    if (low_cycles < 1)
      `uvm_fatal("BADRST", "Reset pulse must be at least one clock long")
    wait_for_interrupt_idle();
    wait (!p_sequencer.APB_VMINTF.psel &&
          !p_sequencer.APB_VMINTF.pready);
    @(negedge p_sequencer.APB_VMINTF.pclk);
    p_sequencer.APB_VMINTF.presetn <= 1'b0;
    repeat (low_cycles) @(p_sequencer.APB_VMINTF.monitor_cb);
    @(negedge p_sequencer.APB_VMINTF.pclk);
    p_sequencer.APB_VMINTF.presetn <= 1'b1;
    repeat (2) @(p_sequencer.APB_VMINTF.monitor_cb);
  endtask

  // Reset-context helpers intentionally use the side-effect-free DMA_INT read
  // address.  The request has no downstream transfer, so reset can cancel it
  // without leaving an expected-slave entry in the scoreboard.
  task automatic pulse_setup_reset(input int unsigned low_cycles = 2);
    if (low_cycles < 1)
      `uvm_fatal("BADRST", "Reset pulse must be at least one clock long")
    wait_for_interrupt_idle();
    wait (!p_sequencer.APB_VMINTF.psel &&
          !p_sequencer.APB_VMINTF.pready);

    @(p_sequencer.APB_VMINTF.master_cb);
    p_sequencer.APB_VMINTF.master_cb.paddr <= DMA_INT_REG;
    p_sequencer.APB_VMINTF.master_cb.pwrite <= 1'b0;
    p_sequencer.APB_VMINTF.master_cb.pwdata <= 32'h0;
    p_sequencer.APB_VMINTF.master_cb.psel <= 1'b1;
    p_sequencer.APB_VMINTF.master_cb.penable <= 1'b0;

    @(p_sequencer.APB_VMINTF.monitor_cb);
    @(negedge p_sequencer.APB_VMINTF.pclk);
    p_sequencer.APB_VMINTF.presetn <= 1'b0;
    @(p_sequencer.APB_VMINTF.monitor_cb);
    p_sequencer.APB_VMINTF.master_cb.psel <= 1'b0;
    p_sequencer.APB_VMINTF.master_cb.penable <= 1'b0;
    repeat (low_cycles - 1)
      @(p_sequencer.APB_VMINTF.monitor_cb);
    @(negedge p_sequencer.APB_VMINTF.pclk);
    p_sequencer.APB_VMINTF.presetn <= 1'b1;
    repeat (2) @(p_sequencer.APB_VMINTF.monitor_cb);
  endtask

  task automatic pulse_access_reset(input int unsigned low_cycles = 2);
    if (low_cycles < 1)
      `uvm_fatal("BADRST", "Reset pulse must be at least one clock long")
    wait_for_interrupt_idle();
    wait (!p_sequencer.APB_VMINTF.psel &&
          !p_sequencer.APB_VMINTF.pready);

    @(p_sequencer.APB_VMINTF.master_cb);
    p_sequencer.APB_VMINTF.master_cb.paddr <= DMA_INT_REG;
    p_sequencer.APB_VMINTF.master_cb.pwrite <= 1'b0;
    p_sequencer.APB_VMINTF.master_cb.pwdata <= 32'h0;
    p_sequencer.APB_VMINTF.master_cb.psel <= 1'b1;
    p_sequencer.APB_VMINTF.master_cb.penable <= 1'b0;

    @(p_sequencer.APB_VMINTF.monitor_cb);
    p_sequencer.APB_VMINTF.master_cb.penable <= 1'b1;
    @(negedge p_sequencer.APB_VMINTF.pclk);
    p_sequencer.APB_VMINTF.presetn <= 1'b0;
    @(p_sequencer.APB_VMINTF.monitor_cb);
    p_sequencer.APB_VMINTF.master_cb.psel <= 1'b0;
    p_sequencer.APB_VMINTF.master_cb.penable <= 1'b0;
    repeat (low_cycles - 1)
      @(p_sequencer.APB_VMINTF.monitor_cb);
    @(negedge p_sequencer.APB_VMINTF.pclk);
    p_sequencer.APB_VMINTF.presetn <= 1'b1;
    repeat (2) @(p_sequencer.APB_VMINTF.monitor_cb);
  endtask
endclass
