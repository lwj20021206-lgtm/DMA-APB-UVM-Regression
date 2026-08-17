`ifndef APB_DEVICE_COVERAGE_FULL_SV
`define APB_DEVICE_COVERAGE_FULL_SV

// This file expects uvm_pkg, uvm_macros.svh, the split APB interfaces,
// apb_master_item and apb_slave_item to be declared first.

`uvm_analysis_imp_decl(_apb_master_cov_full)
`uvm_analysis_imp_decl(_apb_slave_cov_full)

// Optional white-box probes.  Connecting this interface enables coverage of
// the interrupt output itself, DMA busy state and accesses attempted while
// busy.  The transaction-level coverage does not depend on it.
interface apb_device_cov_probe_if(input logic pclk);
  logic presetn;
  logic interrupt;
  logic dma_busy;

  clocking monitor_cb @(posedge pclk);
    default input #1step;
    input presetn, interrupt, dma_busy;
  endclocking
endinterface

class apb_device_coverage_full extends uvm_component;

  `uvm_component_utils(apb_device_coverage_full)

  localparam bit [3:0] DIRECT_ADDR = 4'h0;
  localparam bit [3:0] DMA_SRC     = 4'h1;
  localparam bit [3:0] DMA_DST     = 4'h2;
  localparam bit [3:0] DMA_LEN     = 4'h3;
  localparam bit [3:0] DMA_INIT    = 4'h4;
  localparam bit [3:0] DMA_COPY    = 4'h8;
  localparam bit [3:0] DMA_INT     = 4'hf;

  typedef enum bit {
    CMD_INIT,
    CMD_COPY
  } dma_command_e;

  typedef enum bit [2:0] {
    LEN_ZERO,
    LEN_MINIMUM,
    LEN_NORMAL,
    LEN_MAXIMUM,
    LEN_TOO_LARGE
  } length_class_e;

  typedef enum bit [2:0] {
    REL_EQUAL,
    REL_FORWARD_OVERLAP,
    REL_BACKWARD_OVERLAP,
    REL_FORWARD_ADJACENT,
    REL_BACKWARD_ADJACENT,
    REL_DISJOINT,
    REL_NOT_APPLICABLE
  } address_relation_e;

  typedef enum bit [2:0] {
    DATA_ZERO,
    DATA_ALL_ONES,
    DATA_AAAA,
    DATA_5555,
    DATA_ONE_HOT,
    DATA_OTHER
  } data_class_e;

  typedef enum bit [2:0] {
    TARGET_SOURCE,
    TARGET_DESTINATION,
    TARGET_BOTH,
    TARGET_OTHER,
    TARGET_NOT_CONFIGURED
  } slave_target_e;

  typedef enum bit [1:0] {
    RESET_WHILE_IDLE,
    RESET_DURING_SETUP,
    RESET_DURING_ACCESS
  } reset_context_e;

  // Transaction inputs.  Both are implementation ports: a connected
  // analysis_port.write() calls the matching write_* function below.
  uvm_analysis_imp_apb_master_cov_full #(
    apb_master_item,
    apb_device_coverage_full
  ) master_imp;

  uvm_analysis_imp_apb_slave_cov_full #(
    apb_slave_item,
    apb_device_coverage_full
  ) slave_imp;

  // Optional virtual interfaces are used for wait-state, completed-slave
  // transfer and reset coverage.  Transaction coverage still works without
  // these handles.
  virtual apb_master_intf APB_VMINTF;
  virtual apb_slave_intf APB_VSINTF;
  virtual apb_device_cov_probe_if COV_PROBE;
  bit have_master_vif;
  bit have_slave_vif;
  bit have_cov_probe;

  // Small coverage-side configuration model.  It remembers the most recent
  // completed writes to SRC, DST and LEN so INIT/COPY can be classified.
  bit [27:0] cfg_src;
  bit [27:0] cfg_dst;
  bit [31:0] cfg_len;
  bit        cfg_src_valid;
  bit        cfg_dst_valid;
  bit        cfg_len_valid;

  // ---------------- Master command/access coverage ----------------
  covergroup cg_master_access with function sample(
    bit [3:0]      region,
    bit            write,
    bit [31:0]     data,
    data_class_e   data_class
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_REGION: coverpoint region {
      bins direct   = {DIRECT_ADDR};
      bins dma_src  = {DMA_SRC};
      bins dma_dst  = {DMA_DST};
      bins dma_len  = {DMA_LEN};
      bins dma_init = {DMA_INIT};
      bins dma_copy = {DMA_COPY};
      bins dma_int  = {DMA_INT};
      bins reserved = {[4'h5:4'h7], [4'h9:4'he]};
    }

    CP_RW: coverpoint write {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    // The invalid values are normal bins because negative tests are expected
    // to generate them and then check the corresponding interrupt.
    CP_DMA_LEN_VALUE: coverpoint data
      iff (region == DMA_LEN && write) {
      bins zero            = {32'd0};
      bins minimum         = {32'd1};
      bins normal_values[] = {[32'd2:32'd15]};
      bins maximum         = {32'd16};
      bins too_large       = {[32'd17:$]};
    }

    CP_WRITE_DATA_CLASS: coverpoint data_class iff (write) {
      bins zero      = {DATA_ZERO};
      bins all_ones  = {DATA_ALL_ONES};
      bins aaaa      = {DATA_AAAA};
      bins five_five = {DATA_5555};
      bins one_hot   = {DATA_ONE_HOT};
      bins other     = {DATA_OTHER};
    }

    X_REGION_RW: cross CP_REGION, CP_RW;
  endgroup

  // ---------------- Stateful DMA command coverage ----------------
  covergroup cg_dma_command with function sample(
    dma_command_e     command,
    length_class_e    length_class,
    address_relation_e relation,
    data_class_e      init_data_class,
    bit               configuration_ready
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_COMMAND: coverpoint command {
      bins initialization = {CMD_INIT};
      bins copy           = {CMD_COPY};
    }

    CP_LENGTH_CLASS: coverpoint length_class {
      bins zero       = {LEN_ZERO};
      bins minimum    = {LEN_MINIMUM};
      bins normal     = {LEN_NORMAL};
      bins maximum    = {LEN_MAXIMUM};
      bins too_large  = {LEN_TOO_LARGE};
    }

    CP_COPY_ADDRESS_RELATION: coverpoint relation
      iff (command == CMD_COPY) {
      bins equal             = {REL_EQUAL};
      bins forward_overlap   = {REL_FORWARD_OVERLAP};
      bins backward_overlap  = {REL_BACKWARD_OVERLAP};
      bins forward_adjacent  = {REL_FORWARD_ADJACENT};
      bins backward_adjacent = {REL_BACKWARD_ADJACENT};
      bins disjoint          = {REL_DISJOINT};
      ignore_bins not_applicable = {REL_NOT_APPLICABLE};
    }

    CP_INIT_DATA_CLASS: coverpoint init_data_class
      iff (command == CMD_INIT) {
      bins zero      = {DATA_ZERO};
      bins all_ones  = {DATA_ALL_ONES};
      bins aaaa      = {DATA_AAAA};
      bins five_five = {DATA_5555};
      bins one_hot   = {DATA_ONE_HOT};
      bins other     = {DATA_OTHER};
    }

    CP_CONFIGURATION_READY: coverpoint configuration_ready {
      bins missing_configuration = {1'b0};
      bins ready                 = {1'b1};
    }

    X_COMMAND_LENGTH: cross CP_COMMAND, CP_LENGTH_CLASS;
    X_COMMAND_CONFIGURATION: cross CP_COMMAND, CP_CONFIGURATION_READY;
    X_COPY_LENGTH_RELATION: cross CP_LENGTH_CLASS,
                                  CP_COPY_ADDRESS_RELATION
      iff (command == CMD_COPY);
  endgroup

  // ---------------- Interrupt status/clear coverage ----------------
  // dma_int[3:0] = {invalid_op, invalid_length, overlap, done}
  covergroup cg_interrupt with function sample(
    bit       write,
    bit [3:0] interrupt_bits
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_INT_ACCESS: coverpoint write {
      bins status_read = {1'b0};
      bins w1c_write   = {1'b1};
    }

    CP_STATUS_DONE: coverpoint interrupt_bits[0] iff (!write) {
      bins inactive = {1'b0};
      bins active   = {1'b1};
    }

    CP_STATUS_OVERLAP: coverpoint interrupt_bits[1] iff (!write) {
      bins inactive = {1'b0};
      bins active   = {1'b1};
    }

    CP_STATUS_INVALID_LENGTH: coverpoint interrupt_bits[2] iff (!write) {
      bins inactive = {1'b0};
      bins active   = {1'b1};
    }

    CP_STATUS_INVALID_OP: coverpoint interrupt_bits[3] iff (!write) {
      bins inactive = {1'b0};
      bins active   = {1'b1};
    }

    CP_STATUS_COMBINATION: coverpoint interrupt_bits iff (!write) {
      bins none                = {4'b0000};
      bins done_only           = {4'b0001};
      bins overlap_only        = {4'b0010};
      bins invalid_length_only = {4'b0100};
      bins invalid_op_only     = {4'b1000};
      bins multiple_causes     = default;
    }

    CP_CLEAR_DONE: coverpoint interrupt_bits[0] iff (write) {
      bins not_requested = {1'b0};
      bins requested     = {1'b1};
    }

    CP_CLEAR_OVERLAP: coverpoint interrupt_bits[1] iff (write) {
      bins not_requested = {1'b0};
      bins requested     = {1'b1};
    }

    CP_CLEAR_INVALID_LENGTH: coverpoint interrupt_bits[2] iff (write) {
      bins not_requested = {1'b0};
      bins requested     = {1'b1};
    }

    CP_CLEAR_INVALID_OP: coverpoint interrupt_bits[3] iff (write) {
      bins not_requested = {1'b0};
      bins requested     = {1'b1};
    }
  endgroup

  // ---------------- DUT downstream request coverage ----------------
  // The existing slave monitor publishes requests in APB setup phase.  This
  // group therefore proves which requests were issued, not that they completed.
  covergroup cg_slave_request with function sample(
    bit            write,
    slave_target_e target,
    data_class_e   write_data_class
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_DIRECTION: coverpoint write {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    CP_TARGET: coverpoint target {
      bins source         = {TARGET_SOURCE};
      bins destination    = {TARGET_DESTINATION};
      bins both_ranges    = {TARGET_BOTH};
      bins other          = {TARGET_OTHER};
      bins not_configured = {TARGET_NOT_CONFIGURED};
    }

    CP_WRITE_DATA: coverpoint write_data_class iff (write) {
      bins zero      = {DATA_ZERO};
      bins all_ones  = {DATA_ALL_ONES};
      bins aaaa      = {DATA_AAAA};
      bins five_five = {DATA_5555};
      bins one_hot   = {DATA_ONE_HOT};
      bins other     = {DATA_OTHER};
    }

    X_DIRECTION_TARGET: cross CP_DIRECTION, CP_TARGET;
  endgroup

  // ---------------- Completed downstream transfer coverage ----------------
  // This group is sampled from APB_VSINTF at PSEL && PENABLE && PREADY.
  covergroup cg_slave_completion with function sample(
    bit            write,
    slave_target_e target,
    data_class_e   transfer_data_class
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_DIRECTION: coverpoint write {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    CP_TARGET: coverpoint target {
      bins source         = {TARGET_SOURCE};
      bins destination    = {TARGET_DESTINATION};
      bins both_ranges    = {TARGET_BOTH};
      bins other          = {TARGET_OTHER};
      bins not_configured = {TARGET_NOT_CONFIGURED};
    }

    CP_TRANSFER_DATA: coverpoint transfer_data_class {
      bins zero      = {DATA_ZERO};
      bins all_ones  = {DATA_ALL_ONES};
      bins aaaa      = {DATA_AAAA};
      bins five_five = {DATA_5555};
      bins one_hot   = {DATA_ONE_HOT};
      bins other     = {DATA_OTHER};
    }

    X_DIRECTION_TARGET: cross CP_DIRECTION, CP_TARGET;
  endgroup

  // ---------------- APB wait-state coverage ----------------
  covergroup cg_apb_wait with function sample(
    bit          slave_side,
    bit          write,
    int unsigned wait_cycles
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_SIDE: coverpoint slave_side {
      bins upstream_master_side = {1'b0};
      bins downstream_slave_side = {1'b1};
    }

    CP_DIRECTION: coverpoint write {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    CP_WAIT_CYCLES: coverpoint wait_cycles {
      bins zero_wait = {0};
      bins one_wait  = {1};
      bins short_wait[] = {[2:3]};
      bins medium_wait  = {[4:7]};
      bins long_wait    = {[8:$]};
    }

    X_SIDE_DIRECTION_WAIT: cross CP_SIDE, CP_DIRECTION, CP_WAIT_CYCLES;
  endgroup

  // ---------------- Reset timing coverage ----------------
  covergroup cg_reset with function sample(reset_context_e reset_kind);
    option.per_instance = 1;
    option.goal = 100;

    CP_RESET_CONTEXT: coverpoint reset_kind {
      bins while_idle   = {RESET_WHILE_IDLE};
      bins during_setup = {RESET_DURING_SETUP};
      bins during_access = {RESET_DURING_ACCESS};
    }
  endgroup

  // ---------------- Optional interrupt/busy pin coverage ----------------
  covergroup cg_probe_state with function sample(
    bit interrupt,
    bit dma_busy
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_INTERRUPT_LEVEL: coverpoint interrupt {
      bins low  = {1'b0};
      bins high = {1'b1};
    }

    CP_INTERRUPT_TRANSITION: coverpoint interrupt {
      bins assertion = (1'b0 => 1'b1);
      bins clearing  = (1'b1 => 1'b0);
    }

    CP_DMA_BUSY_LEVEL: coverpoint dma_busy {
      bins idle   = {1'b0};
      bins active = {1'b1};
    }

    CP_DMA_BUSY_TRANSITION: coverpoint dma_busy {
      bins start_dma  = (1'b0 => 1'b1);
      bins finish_dma = (1'b1 => 1'b0);
    }

    X_INTERRUPT_BUSY_LEVEL: cross CP_INTERRUPT_LEVEL, CP_DMA_BUSY_LEVEL;
  endgroup

  covergroup cg_busy_attempt with function sample(
    bit       dma_busy,
    bit [3:0] region,
    bit       write
  );
    option.per_instance = 1;
    option.goal = 100;

    CP_BUSY: coverpoint dma_busy {
      bins idle   = {1'b0};
      bins active = {1'b1};
    }

    CP_REGION: coverpoint region {
      bins direct   = {DIRECT_ADDR};
      bins dma_src  = {DMA_SRC};
      bins dma_dst  = {DMA_DST};
      bins dma_len  = {DMA_LEN};
      bins dma_init = {DMA_INIT};
      bins dma_copy = {DMA_COPY};
      bins dma_int  = {DMA_INT};
      bins reserved = {[4'h5:4'h7], [4'h9:4'he]};
    }

    CP_RW: coverpoint write {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    X_BUSY_REGION_RW: cross CP_BUSY, CP_REGION, CP_RW;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);

    master_imp = new("master_imp", this);
    slave_imp  = new("slave_imp", this);

    cg_master_access   = new();
    cg_dma_command     = new();
    cg_interrupt       = new();
    cg_slave_request   = new();
    cg_slave_completion = new();
    cg_apb_wait        = new();
    cg_reset           = new();
    cg_probe_state     = new();
    cg_busy_attempt    = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    have_master_vif = uvm_config_db#(virtual apb_master_intf)::get(
      this, "", "APB_VMINTF", APB_VMINTF
    );
    have_slave_vif = uvm_config_db#(virtual apb_slave_intf)::get(
      this, "", "APB_VSINTF", APB_VSINTF
    );
    have_cov_probe = uvm_config_db#(virtual apb_device_cov_probe_if)::get(
      this, "", "COV_PROBE", COV_PROBE
    );

    if (!have_master_vif)
      `uvm_warning("COVNOVIF", "No APB_VMINTF: master wait/reset coverage is disabled")
    if (!have_slave_vif)
      `uvm_warning("COVNOVIF", "No APB_VSINTF: slave completion/wait coverage is disabled")
    if (!have_cov_probe)
      `uvm_warning("COVNOPROBE", "No COV_PROBE: interrupt-pin and DMA-busy coverage is disabled")
  endfunction

  function automatic length_class_e classify_length(bit [31:0] length);
    if (length == 0)
      return LEN_ZERO;
    if (length == 1)
      return LEN_MINIMUM;
    if (length < 16)
      return LEN_NORMAL;
    if (length == 16)
      return LEN_MAXIMUM;
    return LEN_TOO_LARGE;
  endfunction

  function automatic data_class_e classify_data(bit [31:0] data);
    if (data == 32'h0000_0000)
      return DATA_ZERO;
    if (data == 32'hffff_ffff)
      return DATA_ALL_ONES;
    if (data == 32'haaaa_aaaa)
      return DATA_AAAA;
    if (data == 32'h5555_5555)
      return DATA_5555;
    if ($onehot(data))
      return DATA_ONE_HOT;
    return DATA_OTHER;
  endfunction

  function automatic address_relation_e classify_relation();
    longint unsigned src_start;
    longint unsigned dst_start;
    longint unsigned src_end;
    longint unsigned dst_end;

    if (!cfg_src_valid || !cfg_dst_valid || !cfg_len_valid || cfg_len == 0)
      return REL_NOT_APPLICABLE;

    src_start = cfg_src;
    dst_start = cfg_dst;
    src_end   = src_start + cfg_len;
    dst_end   = dst_start + cfg_len;

    if (src_start == dst_start)
      return REL_EQUAL;

    if (src_start < dst_start) begin
      if (src_end > dst_start)
        return REL_FORWARD_OVERLAP;
      if (src_end == dst_start)
        return REL_FORWARD_ADJACENT;
      return REL_DISJOINT;
    end

    if (dst_end > src_start)
      return REL_BACKWARD_OVERLAP;
    if (dst_end == src_start)
      return REL_BACKWARD_ADJACENT;
    return REL_DISJOINT;
  endfunction

  function automatic slave_target_e classify_slave_target(bit [27:0] address);
    bit in_source;
    bit in_destination;
    longint unsigned src_end;
    longint unsigned dst_end;

    if (!cfg_src_valid && !cfg_dst_valid)
      return TARGET_NOT_CONFIGURED;

    if (cfg_len_valid && cfg_len > 0 && cfg_len <= 16) begin
      src_end = longint'(cfg_src) + cfg_len;
      dst_end = longint'(cfg_dst) + cfg_len;
      in_source = cfg_src_valid && address >= cfg_src && address < src_end;
      in_destination = cfg_dst_valid && address >= cfg_dst && address < dst_end;
    end
    else begin
      in_source = cfg_src_valid && address == cfg_src;
      in_destination = cfg_dst_valid && address == cfg_dst;
    end

    if (in_source && in_destination)
      return TARGET_BOTH;
    if (in_source)
      return TARGET_SOURCE;
    if (in_destination)
      return TARGET_DESTINATION;
    return TARGET_OTHER;
  endfunction

  // Called by the master analysis implementation port.
  function void write_apb_master_cov_full(apb_master_item item);
    bit [3:0] region;

    region = item.addr[31:28];

    cg_master_access.sample(
      region,
      item.write,
      item.data,
      classify_data(item.data)
    );

    if (item.write) begin
      case (region)
        DMA_SRC: begin
          cfg_src = item.data[27:0];
          cfg_src_valid = 1'b1;
        end

        DMA_DST: begin
          cfg_dst = item.data[27:0];
          cfg_dst_valid = 1'b1;
        end

        DMA_LEN: begin
          cfg_len = item.data;
          cfg_len_valid = 1'b1;
        end

        DMA_INIT: begin
          cg_dma_command.sample(
            CMD_INIT,
            classify_length(cfg_len),
            REL_NOT_APPLICABLE,
            classify_data(item.data),
            cfg_src_valid && cfg_len_valid
          );
        end

        DMA_COPY: begin
          cg_dma_command.sample(
            CMD_COPY,
            classify_length(cfg_len),
            classify_relation(),
            DATA_OTHER,
            cfg_src_valid && cfg_dst_valid && cfg_len_valid
          );
        end

        default: begin
        end
      endcase
    end

    if (region == DMA_INT)
      cg_interrupt.sample(item.write, item.data[3:0]);
  endfunction

  // Called by the existing setup-phase slave monitor.  It measures requests
  // issued by the DUT; completed transactions are measured from APB_VSINTF.
  function void write_apb_slave_cov_full(apb_slave_item item);
    cg_slave_request.sample(
      item.write,
      classify_slave_target(item.addr[27:0]),
      classify_data(item.data)
    );
  endfunction

  task run_phase(uvm_phase phase);
    fork
      begin
        if (have_master_vif)
          monitor_master_interface();
      end

      begin
        if (have_slave_vif)
          monitor_slave_interface();
      end

      begin
        if (have_cov_probe)
          monitor_probe_interface();
      end
    join
  endtask

  task monitor_master_interface();
    bit          in_transfer;
    bit          previous_resetn;
    bit          transfer_write;
    int unsigned wait_cycles;
    reset_context_e reset_context;

    in_transfer = 1'b0;
    previous_resetn = 1'b1;
    wait_cycles = 0;

    forever begin
      @(APB_VMINTF.monitor_cb);

      if (previous_resetn && !APB_VMINTF.monitor_cb.presetn) begin
        if (!APB_VMINTF.monitor_cb.psel)
          reset_context = RESET_WHILE_IDLE;
        else if (!APB_VMINTF.monitor_cb.penable)
          reset_context = RESET_DURING_SETUP;
        else
          reset_context = RESET_DURING_ACCESS;

        cg_reset.sample(reset_context);
      end

      if (!APB_VMINTF.monitor_cb.presetn) begin
        in_transfer = 1'b0;
        wait_cycles = 0;
      end
      else if (APB_VMINTF.monitor_cb.psel &&
               !APB_VMINTF.monitor_cb.penable) begin
        in_transfer = 1'b1;
        transfer_write = APB_VMINTF.monitor_cb.pwrite;
        wait_cycles = 0;

        if (have_cov_probe)
          cg_busy_attempt.sample(
            COV_PROBE.monitor_cb.dma_busy,
            APB_VMINTF.monitor_cb.paddr[31:28],
            APB_VMINTF.monitor_cb.pwrite
          );
      end
      else if (in_transfer && APB_VMINTF.monitor_cb.psel &&
               APB_VMINTF.monitor_cb.penable) begin
        if (APB_VMINTF.monitor_cb.pready) begin
          cg_apb_wait.sample(1'b0, transfer_write, wait_cycles);
          in_transfer = 1'b0;
        end
        else begin
          wait_cycles++;
        end
      end

      previous_resetn = APB_VMINTF.monitor_cb.presetn;
    end
  endtask

  task monitor_probe_interface();
    forever begin
      @(COV_PROBE.monitor_cb);
      if (COV_PROBE.monitor_cb.presetn)
        cg_probe_state.sample(
          COV_PROBE.monitor_cb.interrupt,
          COV_PROBE.monitor_cb.dma_busy
        );
    end
  endtask

  task monitor_slave_interface();
    bit          in_transfer;
    bit          transfer_write;
    bit [27:0]   transfer_address;
    int unsigned wait_cycles;
    bit [31:0]   transfer_data;

    in_transfer = 1'b0;
    wait_cycles = 0;

    forever begin
      @(APB_VSINTF.monitor_cb);

      if (have_master_vif && !APB_VMINTF.monitor_cb.presetn) begin
        in_transfer = 1'b0;
        wait_cycles = 0;
      end
      else if (APB_VSINTF.monitor_cb.psel &&
               !APB_VSINTF.monitor_cb.penable) begin
        in_transfer = 1'b1;
        transfer_write = APB_VSINTF.monitor_cb.pwrite;
        transfer_address = APB_VSINTF.monitor_cb.paddr[27:0];
        wait_cycles = 0;
      end
      else if (in_transfer && APB_VSINTF.monitor_cb.psel &&
               APB_VSINTF.monitor_cb.penable) begin
        if (APB_VSINTF.monitor_cb.pready) begin
          transfer_data = transfer_write
                        ? APB_VSINTF.monitor_cb.pwdata
                        : APB_VSINTF.monitor_cb.prdata;

          cg_apb_wait.sample(1'b1, transfer_write, wait_cycles);
          cg_slave_completion.sample(
            transfer_write,
            classify_slave_target(transfer_address),
            classify_data(transfer_data)
          );

          in_transfer = 1'b0;
        end
        else begin
          wait_cycles++;
        end
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);

    `uvm_info("DMA_APB_COVERAGE", $sformatf(
      {"Coverage summary:\n",
       "  master access    = %0.2f%%\n",
       "  DMA commands     = %0.2f%%\n",
       "  interrupts       = %0.2f%%\n",
       "  slave requests   = %0.2f%%\n",
       "  slave completions= %0.2f%%\n",
       "  APB waits        = %0.2f%%\n",
       "  reset contexts   = %0.2f%%\n",
       "  interrupt/busy   = %0.2f%%\n",
       "  busy attempts    = %0.2f%%"},
      cg_master_access.get_inst_coverage(),
      cg_dma_command.get_inst_coverage(),
      cg_interrupt.get_inst_coverage(),
      cg_slave_request.get_inst_coverage(),
      cg_slave_completion.get_inst_coverage(),
      cg_apb_wait.get_inst_coverage(),
      cg_reset.get_inst_coverage(),
      cg_probe_state.get_inst_coverage(),
      cg_busy_attempt.get_inst_coverage()
    ), UVM_LOW)
  endfunction

endclass

`endif
