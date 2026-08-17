class apb_slave_coverage_sequence extends uvm_sequence #(apb_slave_item);
  bit [31:0] memory [bit [31:0]];
  int unsigned read_response_count;
  int unsigned write_response_count;

  `uvm_object_utils(apb_slave_coverage_sequence)
  `uvm_declare_p_sequencer(apb_slave_sequencer)

  function new(string name = "apb_slave_coverage_sequence");
    super.new(name);
  endfunction

  function automatic int unsigned next_ready_delay(bit write);
    int unsigned response_index;

    if (write) begin
      response_index = write_response_count;
      write_response_count++;
    end
    else begin
      response_index = read_response_count;
      read_response_count++;
    end

    case (response_index % 6)
      0: return 0;
      1: return 1;
      2: return 2;
      3: return 3;
      4: return 5;
      default: return 9;
    endcase
  endfunction

  task body();
    apb_slave_item observed_request;
    bit [31:0] response_data;
    int unsigned response_delay;

    forever begin
      p_sequencer.fifo.get(observed_request);
      response_delay = next_ready_delay(observed_request.write);
      response_data = memory.exists(observed_request.addr)
                    ? memory[observed_request.addr] : 32'h0;

      req = apb_slave_item::type_id::create("coverage_response");
      start_item(req);
      if (observed_request.write) begin
        if (!req.randomize() with {
              write == 1'b1;
              addr == local::observed_request.addr;
              data == local::observed_request.data;
              ready_delay == local::response_delay;
              addr_delay == 0;
            })
          `uvm_fatal("SLVRAND", "Unable to create directed slave write response")
      end
      else begin
        if (!req.randomize() with {
              write == 1'b0;
              addr == local::observed_request.addr;
              data == local::response_data;
              ready_delay == local::response_delay;
              addr_delay == 0;
            })
          `uvm_fatal("SLVRAND", "Unable to create directed slave read response")
      end
      finish_item(req);

      if (observed_request.write)
        memory[observed_request.addr] = observed_request.data;
    end
  endtask
endclass
