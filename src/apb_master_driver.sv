class apb_master_driver extends uvm_driver #(apb_master_item);
  virtual apb_master_intf APB_VMINTF;
  `uvm_component_utils(apb_master_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_master_intf)::get(this, "", "APB_VMINTF", APB_VMINTF))
      `uvm_fatal("NOVIF", "virtual interface connection failed!")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      phase.raise_objection(this);
      drive_item(req);
      if (req.addr[31:28] == 4'b0000 && req.write)
        `uvm_info("DMA write", $sformatf("wait for the item done\n%s", req.sprint()), UVM_LOW)
      else if (req.addr[31:28] == 4'b0000 && !req.write)
        `uvm_info("DMA read", $sformatf("wait for the item done\n%s", req.sprint()), UVM_LOW)
      seq_item_port.item_done();
      phase.drop_objection(this);
    end
  endtask

  task drive_item(apb_master_item req_item);
    repeat (req_item.addr_delay) @(APB_VMINTF.master_cb);
    APB_VMINTF.master_cb.paddr <= req_item.addr;
    APB_VMINTF.master_cb.pwrite <= req_item.write;
    APB_VMINTF.master_cb.psel <= 1'b1;
    APB_VMINTF.master_cb.pwdata <= req_item.data;
    @(APB_VMINTF.master_cb);
    APB_VMINTF.master_cb.penable <= 1'b1;
    while (APB_VMINTF.master_cb.pready == 1'b0)
      @(APB_VMINTF.master_cb);
    if (!req_item.write)
      req_item.data = APB_VMINTF.master_cb.prdata;
    APB_VMINTF.master_cb.psel <= 1'b0;
    APB_VMINTF.master_cb.penable <= 1'b0;
  endtask
endclass
