class apb_slave_driver extends uvm_driver #(apb_slave_item);
  virtual apb_slave_intf APB_VSINTF;
  `uvm_component_utils(apb_slave_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_slave_intf)::get(this, "", "APB_VSINTF", APB_VSINTF))
      `uvm_fatal("NOVIF", "virtual interface connection failed!")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      phase.raise_objection(this);
      drive_item(req);
      seq_item_port.item_done();
      phase.drop_objection(this);
    end
  endtask

  task drive_item(apb_slave_item req_item);
    repeat (req_item.ready_delay) @(APB_VSINTF.slave_cb);

    if (req_item.write != APB_VSINTF.slave_cb.pwrite)
      `uvm_fatal("SLVDIR", $sformatf(
        "Response direction (%0b) does not match DUT request (%0b)",
        req_item.write, APB_VSINTF.slave_cb.pwrite
      ))

    APB_VSINTF.slave_cb.pready <= 1'b1;
    if (!req_item.write)
      APB_VSINTF.slave_cb.prdata <= req_item.data;
    @(APB_VSINTF.slave_cb);
    APB_VSINTF.slave_cb.pready <= 1'b0;
  endtask
endclass
