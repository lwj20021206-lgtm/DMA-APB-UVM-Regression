class apb_slave_basic_sequence extends uvm_sequence #(apb_slave_item);
  reg [31:0] memory [bit[31:0]];
  bit [31:0] read_data;
  apb_slave_item item;
  `uvm_object_utils(apb_slave_basic_sequence)
  `uvm_declare_p_sequencer(apb_slave_sequencer)

  function new(string name = "apb_slave_basic_sequence");
    super.new(name);
  endfunction

  task body();
    forever begin
      p_sequencer.fifo.get(item);
      if (starting_phase != null) starting_phase.raise_objection(this);

      req = apb_slave_item::type_id::create("req");
      start_item(req);
      if (item.write) begin
        if (!req.randomize() with {
              write == 1'b1;
              addr == local::item.addr;
              data == local::item.data;
            })
          `uvm_fatal("SLVRAND", "Unable to randomize APB slave write response")
      end
      else begin
        read_data = memory.exists(item.addr) ? memory[item.addr] : 0;
        if (!req.randomize() with {
              write == 1'b0;
              addr == local::item.addr;
              data == local::read_data;
            })
          `uvm_fatal("SLVRAND", "Unable to randomize APB slave read response")
      end
      finish_item(req);

      if (item.write)
        memory[item.addr] = item.data;

      if (starting_phase != null) starting_phase.drop_objection(this);
    end
  endtask
endclass
