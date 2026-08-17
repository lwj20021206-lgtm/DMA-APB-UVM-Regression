class apb_interrupt_sequence extends uvm_sequence #(apb_master_item);
  bit [3:0] serviced_status;

  `uvm_object_utils(apb_interrupt_sequence)

  function new(string name = "apb_interrupt_sequence");
    super.new(name);
  endfunction

  task body();
    apb_master_item read_status;
    apb_master_item clear_status;

    read_status = apb_master_item::type_id::create("read_status");
    start_item(read_status, 1000);
    if (!read_status.randomize() with {
          addr == 32'hf000_0000;
          write == 1'b0;
          data == 32'h0000_0000;
          addr_delay == 0;
        })
      `uvm_fatal("IRQRAND", "Unable to randomize DMA interrupt-status read")
    finish_item(read_status);

    serviced_status = read_status.data[3:0];
    `uvm_info("IRQ_SERVICE", $sformatf(
      "CPU read DMA_INT status 0x%0h", serviced_status
    ), UVM_MEDIUM)

    if (serviced_status != 4'b0000) begin
      clear_status = apb_master_item::type_id::create("clear_status");
      start_item(clear_status, 1000);
      if (!clear_status.randomize() with {
            addr == 32'hf000_0000;
            write == 1'b1;
            data == local::serviced_status;
            addr_delay == 0;
          })
        `uvm_fatal("IRQRAND", "Unable to randomize DMA interrupt W1C write")
      finish_item(clear_status);
    end
  endtask
endclass
