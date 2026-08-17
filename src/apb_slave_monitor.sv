class apb_slave_monitor extends uvm_monitor;
  uvm_analysis_port #(apb_slave_item) aPort;
  uvm_analysis_port #(apb_slave_item) completed_ap;
  virtual apb_slave_intf APB_VSINTF;
  `uvm_component_utils(apb_slave_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    aPort = new("aPort", this);
    completed_ap = new("completed_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_slave_intf)::get(this, "", "APB_VSINTF", APB_VSINTF))
      `uvm_fatal("NOVIF", "virtual interface connection failed!")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(APB_VSINTF.monitor_cb);
      if (APB_VSINTF.monitor_cb.psel && !APB_VSINTF.monitor_cb.penable) begin
        apb_slave_item item = new("item");
        item.addr = APB_VSINTF.monitor_cb.paddr;
        item.write = APB_VSINTF.monitor_cb.pwrite;
        item.data = APB_VSINTF.monitor_cb.pwdata;
        aPort.write(item); //这一步是写给sequencer的
      end

      if (APB_VSINTF.monitor_cb.psel && APB_VSINTF.monitor_cb.penable &&
          APB_VSINTF.monitor_cb.pready) begin
        apb_slave_item completed_item = new("completed_item");
        completed_item.addr = APB_VSINTF.monitor_cb.paddr;
        completed_item.write = APB_VSINTF.monitor_cb.pwrite;
        completed_item.data = completed_item.write
                            ? APB_VSINTF.monitor_cb.pwdata
                            : APB_VSINTF.monitor_cb.prdata;
        completed_ap.write(completed_item);//这一步在socreboard的slave_complete回调函数实现
      end
    end
  endtask
endclass
