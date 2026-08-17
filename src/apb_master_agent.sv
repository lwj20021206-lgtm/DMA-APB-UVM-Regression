class apb_master_agent extends uvm_agent;
  apb_master_sequencer apb_master_sequencer_1;
  apb_master_driver apb_master_driver_1;
  apb_master_monitor apb_master_monitor_1;
  apb_interrupt_handler apb_interrupt_handler_1;
  virtual apb_master_intf APB_VMINTF;
  uvm_analysis_port #(apb_master_item) aPort;
  uvm_analysis_port #(apb_master_item) request_ap;
  uvm_analysis_port #(apb_interrupt_item) interrupt_ap;
  `uvm_component_utils(apb_master_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    aPort = new("aPort", this);
    request_ap = new("request_ap", this);
    interrupt_ap = new("interrupt_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_master_sequencer_1 = apb_master_sequencer::type_id::create("apb_master_sequencer_1", this);
    apb_master_driver_1 = apb_master_driver::type_id::create("apb_master_driver_1", this);
    apb_master_monitor_1 = apb_master_monitor::type_id::create("apb_master_monitor_1", this);
    apb_interrupt_handler_1 = apb_interrupt_handler::type_id::create(
      "apb_interrupt_handler_1", this
    );
    if (!uvm_config_db#(virtual apb_master_intf)::get(this, "", "APB_VMINTF", APB_VMINTF))
      `uvm_fatal("NOVIF", "virtual interface connection failed!")
    uvm_config_db#(virtual apb_master_intf)::set(this, "apb_master_monitor_1", "APB_VMINTF", APB_VMINTF);
    uvm_config_db#(virtual apb_master_intf)::set(this, "apb_master_driver_1", "APB_VMINTF", APB_VMINTF);
    apb_master_sequencer_1.APB_VMINTF = APB_VMINTF;
  endfunction

  function void connect_phase(uvm_phase phase);
    apb_master_driver_1.seq_item_port.connect(apb_master_sequencer_1.seq_item_export);
    apb_master_monitor_1.aPort.connect(aPort);
    apb_master_monitor_1.request_ap.connect(request_ap);
    apb_master_monitor_1.interrupt_ap.connect(
      apb_master_sequencer_1.interrupt_imp
    );
    apb_master_monitor_1.interrupt_ap.connect(interrupt_ap);
    apb_interrupt_handler_1.sequencer = apb_master_sequencer_1;
  endfunction
endclass
