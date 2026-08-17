class apb_master_monitor extends uvm_monitor;
  uvm_analysis_port #(apb_master_item) aPort;
  uvm_analysis_port #(apb_master_item) request_ap;
  uvm_analysis_port #(apb_interrupt_item) interrupt_ap;
  virtual apb_master_intf APB_VMINTF;
  `uvm_component_utils(apb_master_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    aPort = new("aPort", this);
    request_ap = new("request_ap", this);
    interrupt_ap = new("interrupt_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_master_intf)::get(this, "", "APB_VMINTF", APB_VMINTF))
      `uvm_fatal("NOVIF", "virtual interface connection failed!")
  endfunction

  task run_phase(uvm_phase phase);
    bit previous_interrupt;

    previous_interrupt = 1'b0;
    forever begin
      @(APB_VMINTF.monitor_cb);

      if (!APB_VMINTF.monitor_cb.presetn) begin
        previous_interrupt = 1'b0;
      end
      else begin
        if ((APB_VMINTF.monitor_cb.interrupt === 1'b1) &&
            !previous_interrupt) begin
          apb_interrupt_item irq = new("irq_asserted");
          irq.asserted = 1'b1;
          irq.observed_at = $time;
          interrupt_ap.write(irq);
        end
        else if ((APB_VMINTF.monitor_cb.interrupt === 1'b0) &&
                 previous_interrupt) begin
          apb_interrupt_item irq = new("irq_cleared");
          irq.asserted = 1'b0;
          irq.observed_at = $time;
          interrupt_ap.write(irq);
        end

        previous_interrupt =
          (APB_VMINTF.monitor_cb.interrupt === 1'b1);
      end

      if (APB_VMINTF.monitor_cb.presetn && APB_VMINTF.monitor_cb.psel &&
          !APB_VMINTF.monitor_cb.penable) begin
        apb_master_item request = new("request");
        request.addr = APB_VMINTF.monitor_cb.paddr;
        request.write = APB_VMINTF.monitor_cb.pwrite;
        request.data = APB_VMINTF.monitor_cb.pwdata;
        request_ap.write(request);
      end

      if (APB_VMINTF.monitor_cb.psel && APB_VMINTF.monitor_cb.penable &&
          APB_VMINTF.monitor_cb.pready) begin
        apb_master_item item = new("item");
        item.addr = APB_VMINTF.monitor_cb.paddr;
        item.write = APB_VMINTF.monitor_cb.pwrite;
        item.data = item.write ? APB_VMINTF.monitor_cb.pwdata : APB_VMINTF.monitor_cb.prdata;
        aPort.write(item);
      end
    end
  endtask
endclass
