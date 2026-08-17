class apb_slave_agent extends uvm_agent;
  apb_slave_sequencer apb_slave_sequencer_1;
  apb_slave_driver apb_slave_driver_1;
  apb_slave_monitor apb_slave_monitor_1;
  virtual apb_slave_intf APB_VSINTF;
  `uvm_component_utils(apb_slave_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_slave_sequencer_1 = apb_slave_sequencer::type_id::create("apb_slave_sequencer_1", this);
    apb_slave_driver_1 = apb_slave_driver::type_id::create("apb_slave_driver_1", this);
    apb_slave_monitor_1 = apb_slave_monitor::type_id::create("apb_slave_monitor_1", this);
    if (!uvm_config_db#(virtual apb_slave_intf)::get(this, "", "APB_VSINTF", APB_VSINTF))
      `uvm_fatal("NOVIF", "virtual interface connection failed!")
    uvm_config_db#(virtual apb_slave_intf)::set(this, "apb_slave_monitor_1", "APB_VSINTF", APB_VSINTF);
    uvm_config_db#(virtual apb_slave_intf)::set(this, "apb_slave_driver_1", "APB_VSINTF", APB_VSINTF);
  endfunction

  function void connect_phase(uvm_phase phase);
    apb_slave_driver_1.seq_item_port.connect(apb_slave_sequencer_1.seq_item_export);
    apb_slave_monitor_1.aPort.connect(apb_slave_sequencer_1.aExport);
  endfunction
endclass
