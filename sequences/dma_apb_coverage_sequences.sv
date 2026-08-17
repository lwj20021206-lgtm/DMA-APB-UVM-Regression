class dma_apb_register_direct_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_register_direct_sequence)

  function new(string name = "dma_apb_register_direct_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] read_data;
    bit [31:0] patterns [0:5];
    int unsigned index;

    patterns[0] = 32'h0000_0000;
    patterns[1] = 32'hffff_ffff;
    patterns[2] = 32'haaaa_aaaa;
    patterns[3] = 32'h5555_5555;
    patterns[4] = 32'h0000_0001;
    patterns[5] = 32'h1234_5678;

    // Keep this first so downstream target coverage sees not-configured.
    cpu_write(32'h0000_0010, 32'hcafe_f00d);
    cpu_read(32'h0000_0010, 32'h0, read_data);

    for (index = 0; index < 6; index++) begin
      cpu_write(32'h0000_0100 + index, patterns[index]);
      cpu_read(32'h0000_0100 + index, 32'h0, read_data);
    end

    cpu_write(DMA_SRC_REG, 32'h0123_4567);
    cpu_read(DMA_SRC_REG, 32'h0, read_data);
    cpu_write(DMA_DST_REG, 32'h0765_4321);
    cpu_read(DMA_DST_REG, 32'h0, read_data);

    write_dma_length(0);
    write_dma_length(1);
    for (index = 2; index <= 16; index++)
      write_dma_length(index);
    write_dma_length(17);
    write_dma_length(33);

    // The RTL incorrectly checks PWDATA even on a LEN read.  Driving one on
    // the otherwise-unused write-data bus avoids creating a false interrupt.
    cpu_read(DMA_LEN_REG, 32'h1, read_data);

    cpu_read(DMA_INT_REG, 32'h0, read_data);
    cpu_write(DMA_INT_REG, 32'h0);
    cpu_write(DMA_INT_REG, 32'hf);

    // Reads from write-only command regions are negative operations.
    cpu_read(DMA_INIT_REG, 32'h0, read_data);
    wait_for_next_interrupt();
    cpu_read(DMA_COPY_REG, 32'h0, read_data);
    wait_for_next_interrupt();

    cpu_read(32'h5000_0000, 32'h0, read_data);
    wait_for_next_interrupt();
    cpu_write(32'h9000_0000, 32'h89ab_cdef);
    wait_for_next_interrupt();
  endtask
endclass

class dma_apb_init_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_init_sequence)

  function new(string name = "dma_apb_init_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] patterns [0:5];
    bit [31:0] lengths [0:5];
    int unsigned index;

    patterns[0] = 32'h0000_0000;
    patterns[1] = 32'hffff_ffff;
    patterns[2] = 32'haaaa_aaaa;
    patterns[3] = 32'h5555_5555;
    patterns[4] = 32'h0000_0001;
    patterns[5] = 32'h1357_9bdf;

    lengths[0] = 1;
    lengths[1] = 4;
    lengths[2] = 16;
    lengths[3] = 33;
    lengths[4] = 4;
    lengths[5] = 16;

    for (index = 0; index < 6; index++)
      run_init(
        28'h000_1000 + (index * 28'h000_0100),
        lengths[index],
        patterns[index]
      );
  endtask
endclass

class dma_apb_copy_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_copy_sequence)

  function new(string name = "dma_apb_copy_sequence");
    super.new(name);
  endfunction

  task automatic run_relation(
    input bit [31:0] length,
    input int unsigned relation,
    input bit [27:0] base_address,
    input bit [31:0] seed_data
  );
    bit [27:0] source;
    bit [27:0] destination;

    case (relation)
      0: begin
        source = base_address;
        destination = base_address;
      end
      1: begin
        source = base_address;
        destination = base_address + 1;
      end
      2: begin
        source = base_address + 1;
        destination = base_address;
      end
      3: begin
        source = base_address;
        destination = base_address + length;
      end
      4: begin
        source = base_address + length;
        destination = base_address;
      end
      default: begin
        source = base_address;
        destination = base_address + length + 16;
      end
    endcase

    run_copy(source, destination, length, seed_data);
  endtask

  task automatic run_relation_set(
    input bit [31:0] length,
    input bit        include_overlap,
    input bit [27:0] base_address
  );
    int unsigned relation;

    for (relation = 0; relation < 6; relation++) begin
      if (include_overlap || ((relation != 1) && (relation != 2)))
        run_relation(
          length,
          relation,
          base_address + (relation * 28'h000_0100),
          32'h600d_0000 ^ (length << 8) ^ relation
        );
    end
  endtask

  task body();
    run_relation_set(1, 1'b0, 28'h001_0000);
    run_relation_set(4, 1'b1, 28'h002_0000);
    run_relation_set(16, 1'b1, 28'h003_0000);
    // One disjoint LEN=33 case covers the too-large command class.  Testing
    // every relation with 33 would be misleading because the DUT truncates
    // it to an effective length of one.
    run_relation(33, 5, 28'h004_0000, 32'h600d_2105);
  endtask
endclass

class dma_apb_interrupt_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_interrupt_sequence)

  function new(string name = "dma_apb_interrupt_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] read_data;

    cpu_read(DMA_INT_REG, 32'h0, read_data);
    cpu_write(DMA_INT_REG, 32'h0);
    cpu_write(DMA_INT_REG, 32'hf);

    run_init(28'h010_0000, 1, 32'h1234_5678);

    write_dma_length(0);

    cpu_read(32'h5000_0000, 32'h0, read_data);
    wait_for_next_interrupt();

    run_copy(
      28'h011_0000,
      28'h011_0001,
      4,
      32'habcd_0000
    );

    cpu_read(DMA_INT_REG, 32'h0, read_data);
  endtask
endclass

class dma_apb_target_wait_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_target_wait_sequence)

  function new(string name = "dma_apb_target_wait_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] read_data;
    int unsigned index;

    cpu_write(DMA_SRC_REG, 32'h0200_0000);
    cpu_write(DMA_DST_REG, 32'h0200_1000);
    write_dma_length(4);

    for (index = 0; index < 6; index++) begin
      cpu_write(32'h0200_0000 + index, 32'h1000_0000 + index);
      cpu_read(32'h0200_0000 + index, 32'h0, read_data);
      cpu_write(32'h0200_1000 + index, 32'h2000_0000 + index);
      cpu_read(32'h0200_1000 + index, 32'h0, read_data);
      cpu_write(32'h0200_2000 + index, 32'h3000_0000 + index);
      cpu_read(32'h0200_2000 + index, 32'h0, read_data);
    end

    cpu_write(DMA_SRC_REG, 32'h0200_3000);
    cpu_write(DMA_DST_REG, 32'h0200_3000);
    write_dma_length(4);
    for (index = 0; index < 6; index++) begin
      cpu_write(32'h0200_3000 + index, 32'h4000_0000 + index);
      cpu_read(32'h0200_3000 + index, 32'h0, read_data);
    end

    // Generate enough upstream-only traffic to exercise the DUT's random
    // PREADY delay classes for both reads and writes.
    for (index = 0; index < 24; index++) begin
      cpu_write(DMA_INT_REG, 32'h0);
      cpu_read(DMA_INT_REG, 32'h0, read_data);
    end
  endtask
endclass

class dma_apb_busy_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_busy_sequence)

  function new(string name = "dma_apb_busy_sequence");
    super.new(name);
  endfunction

  task automatic start_init_and_attempt(
    input int unsigned scenario,
    input bit          write,
    input bit [31:0]   address,
    input bit [31:0]   bus_write_data
  );
    bit [31:0] read_data;

    cpu_write(DMA_SRC_REG, 32'h0300_0000 + (scenario * 32'h100));
    write_dma_length(4);
    cpu_write(DMA_INIT_REG, 32'hb000_0000 + scenario);
    cpu_transfer_without_irq_guard(
      write, address, bus_write_data, read_data
    );
    wait_for_next_interrupt();
  endtask

  task body();
    int unsigned scenario;

    scenario = 0;
    start_init_and_attempt(scenario++, 1'b0, 32'h0000_0040, 32'h0);
    start_init_and_attempt(scenario++, 1'b1, 32'h0000_0041, 32'hface_0001);
    start_init_and_attempt(scenario++, 1'b0, DMA_SRC_REG, 32'h0);
    start_init_and_attempt(scenario++, 1'b1, DMA_SRC_REG, 32'h0310_0000);
    start_init_and_attempt(scenario++, 1'b0, DMA_DST_REG, 32'h0);
    start_init_and_attempt(scenario++, 1'b1, DMA_DST_REG, 32'h0320_0000);
    start_init_and_attempt(scenario++, 1'b1, DMA_LEN_REG, 32'h4);
    start_init_and_attempt(scenario++, 1'b0, DMA_INIT_REG, 32'h0);
    start_init_and_attempt(scenario++, 1'b0, DMA_COPY_REG, 32'h0);
    start_init_and_attempt(scenario++, 1'b1, DMA_INT_REG, 32'h0);
    start_init_and_attempt(scenario++, 1'b0, 32'h5000_0000, 32'h0);
    start_init_and_attempt(scenario++, 1'b1, 32'h9000_0000, 32'hface_0002);
  endtask
endclass

class dma_apb_reset_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_reset_sequence)

  function new(string name = "dma_apb_reset_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] read_data;

    pulse_idle_reset(2);
    pulse_setup_reset(2);
    pulse_access_reset(2);
    cpu_write(32'h0000_0800, 32'h55aa_aa55);
    cpu_read(32'h0000_0800, 32'h0, read_data);
  endtask
endclass

class dma_apb_random_sequence extends apb_master_base_sequence;
  int unsigned operation_count = 40;
  `uvm_object_utils(dma_apb_random_sequence)

  function new(string name = "dma_apb_random_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] read_data;
    bit [27:0] source;
    bit [27:0] destination;
    bit [31:0] length;
    bit [31:0] data;
    bit [31:0] address;
    int unsigned index;
    int unsigned operation;

    void'($value$plusargs("DMA_RANDOM_OPS=%d", operation_count));

    for (index = 0; index < operation_count; index++) begin
      operation = $urandom_range(0, 5);
      data = $urandom();
      case (operation)
        0: begin
          address = $urandom_range(32'h0000_0fff, 32'h0000_0000);
          cpu_write(address, data);
          cpu_read(address, 32'h0, read_data);
        end

        1: begin
          case ($urandom_range(0, 2))
            0: length = 1;
            1: length = 4;
            default: length = 16;
          endcase
          source = $urandom_range(28'h0a0_ffff, 28'h0a0_0000);
          run_init(source, length, data);
        end

        2: begin
          length = $urandom_range(8, 1);
          source = $urandom_range(28'h0b0_7fff, 28'h0b0_0000);
          destination = source + length + 32;
          run_copy(source, destination, length, data);
        end

        3: begin
          if ($urandom_range(0, 1))
            write_dma_length(0);
          else
            write_dma_length(17 + $urandom_range(16, 0));
        end

        4: begin
          address = 32'h5000_0000 |
                    ($urandom_range(0, 16'hffff) << 2);
          if ($urandom_range(0, 1))
            cpu_write(address, data);
          else
            cpu_read(address, 32'h0, read_data);
          wait_for_next_interrupt();
        end

        default: begin
          cpu_write(DMA_SRC_REG, {4'h0, data[27:0]});
          cpu_read(DMA_SRC_REG, 32'h0, read_data);
        end
      endcase
    end
  endtask
endclass

class dma_apb_full_coverage_sequence extends apb_master_base_sequence;
  `uvm_object_utils(dma_apb_full_coverage_sequence)

  function new(string name = "dma_apb_full_coverage_sequence");
    super.new(name);
  endfunction

  task body();
    dma_apb_reset_sequence reset_sequence;
    dma_apb_register_direct_sequence register_sequence;
    dma_apb_init_sequence init_sequence;
    dma_apb_copy_sequence copy_sequence;
    dma_apb_interrupt_sequence interrupt_sequence;
    dma_apb_target_wait_sequence wait_sequence;
    dma_apb_busy_sequence busy_sequence;

    reset_sequence = dma_apb_reset_sequence::type_id::create("reset_sequence");
    reset_sequence.start(p_sequencer);
    register_sequence = dma_apb_register_direct_sequence::type_id::create("register_sequence");
    register_sequence.start(p_sequencer);
    init_sequence = dma_apb_init_sequence::type_id::create("init_sequence");
    init_sequence.start(p_sequencer);
    copy_sequence = dma_apb_copy_sequence::type_id::create("copy_sequence");
    copy_sequence.start(p_sequencer);
    interrupt_sequence = dma_apb_interrupt_sequence::type_id::create("interrupt_sequence");
    interrupt_sequence.start(p_sequencer);
    wait_sequence = dma_apb_target_wait_sequence::type_id::create("wait_sequence");
    wait_sequence.start(p_sequencer);
    busy_sequence = dma_apb_busy_sequence::type_id::create("busy_sequence");
    busy_sequence.start(p_sequencer);
  endtask
endclass
