`uvm_analysis_imp_decl(_master_request_sb)
`uvm_analysis_imp_decl(_master_complete_sb)
`uvm_analysis_imp_decl(_slave_complete_sb)
`uvm_analysis_imp_decl(_interrupt_sb)

class apb_device_scoreboard extends uvm_scoreboard;
  typedef enum bit [1:0] {
    EXP_DIRECT,
    EXP_INIT,
    EXP_COPY_READ,
    EXP_COPY_WRITE
  } expected_kind_e;

  typedef struct {
    expected_kind_e kind;
    bit             write;
    bit [27:0]      address;
    bit [31:0]      data;
  } expected_slave_transfer_t;

  localparam bit [3:0] DIRECT_ADDR = 4'h0;
  localparam bit [3:0] DMA_SRC     = 4'h1;
  localparam bit [3:0] DMA_DST     = 4'h2;
  localparam bit [3:0] DMA_LEN     = 4'h3;
  localparam bit [3:0] DMA_INIT    = 4'h4;
  localparam bit [3:0] DMA_COPY    = 4'h8;
  localparam bit [3:0] DMA_INT     = 4'hf;

  uvm_analysis_imp_master_request_sb #(
    apb_master_item,
    apb_device_scoreboard
  ) master_request_imp;
  uvm_analysis_imp_master_complete_sb #(
    apb_master_item,
    apb_device_scoreboard
  ) master_complete_imp;
  uvm_analysis_imp_slave_complete_sb #(
    apb_slave_item,
    apb_device_scoreboard
  ) slave_complete_imp;
  uvm_analysis_imp_interrupt_sb #(
    apb_interrupt_item,
    apb_device_scoreboard
  ) interrupt_imp;

  expected_slave_transfer_t expected_slave_q[$];
  bit [31:0] copy_read_data_q[$];
  bit [31:0] reference_memory[bit [27:0]];

  bit [27:0] model_src;
  bit [27:0] model_dst;
  bit [4:0]  model_len;
  bit        src_valid;
  bit        dst_valid;
  bit        len_valid;
  bit [3:0]  expected_interrupt;
  bit        interrupt_pin_level;

  int unsigned checked_master_transfers;
  int unsigned checked_slave_transfers;
  int unsigned error_count;

  `uvm_component_utils(apb_device_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    master_request_imp = new("master_request_imp", this);
    master_complete_imp = new("master_complete_imp", this);
    slave_complete_imp = new("slave_complete_imp", this);
    interrupt_imp = new("interrupt_imp", this);
  endfunction

  function void fail(string message);
    error_count++;
    `uvm_error("DMA_APB_SB", message)
  endfunction

  function automatic bit is_reserved_region(bit [3:0] region);
    return !(region inside {
      DIRECT_ADDR, DMA_SRC, DMA_DST, DMA_LEN,
      DMA_INIT, DMA_COPY, DMA_INT
    });
  endfunction

  function automatic bit copy_overlaps(
    bit [27:0] source,
    bit [27:0] destination,
    bit [4:0] length
  );
    longint unsigned source_end;
    longint unsigned destination_end;

    source_end = longint'(source) + length;
    destination_end = longint'(destination) + length;

    return ((source < destination) && (source_end > destination)) ||
           ((source > destination) && (destination_end > source));
  endfunction

  function void enqueue_transfer(
    expected_kind_e kind,
    bit             write,
    bit [27:0]      address,
    bit [31:0]      data = 32'h0
  );
    expected_slave_transfer_t expected;

    expected.kind = kind;
    expected.write = write;
    expected.address = address;
    expected.data = data;
    expected_slave_q.push_back(expected);
  endfunction

  // Setup-phase upstream requests arrive early enough to predict direct
  // downstream transfers, which can complete before the upstream write does.
  function void write_master_request_sb(apb_master_item item);
    bit [3:0] region;

    region = item.addr[31:28];

    if (region == DIRECT_ADDR)
      enqueue_transfer(
        EXP_DIRECT, item.write, item.addr[27:0], item.data
      );

    // INIT and COPY are write-only command regions.  The RTL reports a read
    // from either one through the same invalid-operation interrupt used for
    // reserved regions.
    if (is_reserved_region(region) ||
        (!item.write && (region inside {DMA_INIT, DMA_COPY})))
      expected_interrupt[3] = 1'b1;

    if (region == DMA_COPY && item.write && src_valid && dst_valid &&
        len_valid && copy_overlaps(model_src, model_dst, model_len))
      expected_interrupt[1] = 1'b1;
  endfunction

  function void write_master_complete_sb(apb_master_item item);
    bit [3:0] region;
    bit [31:0] expected_data;
    int unsigned transfer_index;

    checked_master_transfers++;
    region = item.addr[31:28];

    case (region)
      DIRECT_ADDR: begin
        if (!item.write) begin
          expected_data = reference_memory.exists(item.addr[27:0])
                        ? reference_memory[item.addr[27:0]] : 32'h0;
          if (item.data !== expected_data)
            fail($sformatf(
              "Direct read mismatch at 0x%07h: expected 0x%08h, got 0x%08h",
              item.addr[27:0], expected_data, item.data
            ));
        end
      end

      DMA_SRC: begin
        if (item.write) begin
          model_src = item.data[27:0];
          src_valid = 1'b1;
        end
        else if (item.data !== {4'h0, model_src})
          fail($sformatf(
            "DMA_SRC read mismatch: expected 0x%08h, got 0x%08h",
            {4'h0, model_src}, item.data
          ));
      end

      DMA_DST: begin
        if (item.write) begin
          model_dst = item.data[27:0];
          dst_valid = 1'b1;
        end
        else if (item.data !== {4'h0, model_dst})
          fail($sformatf(
            "DMA_DST read mismatch: expected 0x%08h, got 0x%08h",
            {4'h0, model_dst}, item.data
          ));
      end

      DMA_LEN: begin
        if (item.write) begin
          model_len = item.data[4:0];
          len_valid = 1'b1;
          if (item.data == 0 || item.data > 16)
            expected_interrupt[2] = 1'b1;
        end
        else if (item.data !== {27'h0, model_len})
          fail($sformatf(
            "DMA_LEN read mismatch: expected 0x%08h, got 0x%08h",
            {27'h0, model_len}, item.data
          ));
      end

      DMA_INIT: begin
        if (item.write) begin
          if (!src_valid || !len_valid)
            fail("DMA INIT issued before SRC/LEN were configured");
          else if (model_len == 0 || model_len > 16)
            fail($sformatf(
              "DMA INIT issued with unsupported model length %0d", model_len
            ));
          else begin
            for (transfer_index = 0;
                 transfer_index < model_len;
                 transfer_index++)
              enqueue_transfer(
                EXP_INIT,
                1'b1,
                model_src + transfer_index,
                item.data
              );
          end
        end
      end

      DMA_COPY: begin
        if (item.write) begin
          if (!src_valid || !dst_valid || !len_valid)
            fail("DMA COPY issued before SRC/DST/LEN were configured");
          else if (model_len == 0 || model_len > 16)
            fail($sformatf(
              "DMA COPY issued with unsupported model length %0d", model_len
            ));
          else begin
            for (transfer_index = 0;
                 transfer_index < model_len;
                 transfer_index++) begin
              enqueue_transfer(
                EXP_COPY_READ,
                1'b0,
                model_src + transfer_index
              );
              enqueue_transfer(
                EXP_COPY_WRITE,
                1'b1,
                model_dst + transfer_index
              );
            end
          end
        end
      end

      DMA_INT: begin
        if (item.write)
          expected_interrupt &= ~item.data[3:0];
        else if (item.data[3:0] !== expected_interrupt)
          fail($sformatf(
            "DMA_INT read mismatch: expected 0x%0h, got 0x%0h",
            expected_interrupt, item.data[3:0]
          ));
      end

      default: begin
      end
    endcase
  endfunction

  function void write_slave_complete_sb(apb_slave_item item);
    expected_slave_transfer_t expected;
    bit [31:0] expected_data;

    checked_slave_transfers++;

    if (expected_slave_q.size() == 0) begin
      fail($sformatf(
        "Unexpected downstream transfer: write=%0b addr=0x%07h data=0x%08h",
        item.write, item.addr[27:0], item.data
      ));
      if (item.write)
        reference_memory[item.addr[27:0]] = item.data;
      return;
    end

    expected = expected_slave_q.pop_front();

    if (item.write !== expected.write)
      fail($sformatf(
        "Downstream direction mismatch at 0x%07h: expected write=%0b, got %0b",
        expected.address, expected.write, item.write
      ));

    if (item.addr[27:0] !== expected.address)
      fail($sformatf(
        "Downstream address mismatch: expected 0x%07h, got 0x%07h",
        expected.address, item.addr[27:0]
      ));

    if (!item.write) begin
      expected_data = reference_memory.exists(item.addr[27:0])
                    ? reference_memory[item.addr[27:0]] : 32'h0;
      if (item.data !== expected_data)
        fail($sformatf(
          "Downstream read mismatch at 0x%07h: expected 0x%08h, got 0x%08h",
          item.addr[27:0], expected_data, item.data
        ));

      if (expected.kind == EXP_COPY_READ)
        copy_read_data_q.push_back(item.data);
    end
    else begin
      case (expected.kind)
        EXP_DIRECT, EXP_INIT: expected_data = expected.data;

        EXP_COPY_WRITE: begin
          if (copy_read_data_q.size() == 0) begin
            fail("COPY write completed without a preceding COPY read");
            expected_data = item.data;
          end
          else
            expected_data = copy_read_data_q.pop_front();
        end

        default: expected_data = expected.data;
      endcase

      if (item.data !== expected_data)
        fail($sformatf(
          "Downstream write mismatch at 0x%07h: expected 0x%08h, got 0x%08h",
          item.addr[27:0], expected_data, item.data
        ));

      reference_memory[item.addr[27:0]] = item.data;
    end

    case (expected.kind)
      EXP_INIT: begin
        model_src++;
        model_len--;
        expected_interrupt[0] = 1'b1;
      end

      EXP_COPY_READ: model_src++;

      EXP_COPY_WRITE: begin
        model_dst++;
        model_len--;
        expected_interrupt[0] = 1'b1;
      end

      default: begin
      end
    endcase
  endfunction

  function void write_interrupt_sb(apb_interrupt_item irq);
    interrupt_pin_level = irq.asserted;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    if (expected_slave_q.size() != 0)
      fail($sformatf(
        "%0d expected downstream transfers did not complete",
        expected_slave_q.size()
      ));

    if (copy_read_data_q.size() != 0)
      fail($sformatf(
        "%0d COPY read results were not consumed by writes",
        copy_read_data_q.size()
      ));

    if (expected_interrupt != 0)
      fail($sformatf(
        "Interrupt status was not completely serviced: 0x%0h",
        expected_interrupt
      ));

    if (interrupt_pin_level)
      fail("Interrupt pin remained asserted at end of test");
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("DMA_APB_SB", $sformatf(
      {"Scoreboard summary: master=%0d, slave=%0d, errors=%0d, ",
       "memory locations=%0d"},
      checked_master_transfers,
      checked_slave_transfers,
      error_count,
      reference_memory.num()
    ), UVM_LOW)
  endfunction
endclass
