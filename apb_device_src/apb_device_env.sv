class apb_device_env extends uvm_env;
  apb_master_agent apb_master_agent_1;
  apb_slave_agent apb_slave_agent_1;
  apb_device_coverage_full coverage_full;
  apb_device_scoreboard scoreboard;
  virtual apb_master_intf APB_VMINTF;
  virtual apb_slave_intf APB_VSINTF;
  virtual apb_device_cov_probe_if COV_PROBE;
  bit have_cov_probe;
  `uvm_component_utils(apb_device_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_master_agent_1 = apb_master_agent::type_id::create("apb_master_agent_1", this);
    apb_slave_agent_1 = apb_slave_agent::type_id::create("apb_slave_agent_1", this);
    coverage_full = apb_device_coverage_full::type_id::create(
      "coverage_full", this
    );
    scoreboard = apb_device_scoreboard::type_id::create("scoreboard", this);

    if (!uvm_config_db#(virtual apb_master_intf)::get(this, "", "APB_VMINTF", APB_VMINTF))
      `uvm_fatal("NOVIF", "virtual master interface connection failed!")
    uvm_config_db#(virtual apb_master_intf)::set(this, "apb_master_agent_1", "APB_VMINTF", APB_VMINTF);
    uvm_config_db#(virtual apb_master_intf)::set(this, "coverage_full", "APB_VMINTF", APB_VMINTF);

    if (!uvm_config_db#(virtual apb_slave_intf)::get(this, "", "APB_VSINTF", APB_VSINTF))
      `uvm_fatal("NOVIF", "virtual slave interface connection failed!")
    uvm_config_db#(virtual apb_slave_intf)::set(this, "apb_slave_agent_1", "APB_VSINTF", APB_VSINTF);
    uvm_config_db#(virtual apb_slave_intf)::set(this, "coverage_full", "APB_VSINTF", APB_VSINTF);

    have_cov_probe = uvm_config_db#(
      virtual apb_device_cov_probe_if
    )::get(this, "", "COV_PROBE", COV_PROBE);
    if (have_cov_probe)
      uvm_config_db#(virtual apb_device_cov_probe_if)::set(
        this, "coverage_full", "COV_PROBE", COV_PROBE
      );
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    apb_master_agent_1.aPort.connect(coverage_full.master_imp);
    apb_master_agent_1.aPort.connect(scoreboard.master_complete_imp);
    apb_master_agent_1.request_ap.connect(scoreboard.master_request_imp);
    apb_master_agent_1.interrupt_ap.connect(scoreboard.interrupt_imp);
    apb_slave_agent_1.apb_slave_monitor_1.aPort.connect(
      coverage_full.slave_imp
    );
    apb_slave_agent_1.apb_slave_monitor_1.completed_ap.connect(
      scoreboard.slave_complete_imp
    );
  endfunction

  task reset_phase(uvm_phase phase);
    phase.raise_objection(this);
    APB_VMINTF.presetn <= 1'b0;
    APB_VMINTF.master_cb.psel <= 1'b0;
    APB_VMINTF.master_cb.penable <= 1'b0;
    APB_VSINTF.slave_cb.pready <= 1'b0;
    APB_VSINTF.slave_cb.prdata <= 32'h0;
    @(APB_VMINTF.master_cb);
    APB_VMINTF.presetn <= 1'b1;
    @(APB_VMINTF.master_cb);
    phase.drop_objection(this);
  endtask
endclass
