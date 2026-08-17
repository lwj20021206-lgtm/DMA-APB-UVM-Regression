`uvm_analysis_imp_decl(_apb_irq_seqr)

class apb_master_sequencer extends uvm_sequencer #(apb_master_item);
  virtual apb_master_intf APB_VMINTF;
  uvm_analysis_imp_apb_irq_seqr #(
    apb_interrupt_item,
    apb_master_sequencer
  ) interrupt_imp;
  bit interrupt_pending;
  bit interrupt_level;
  int unsigned interrupt_count;
  int unsigned serviced_interrupt_count;

  `uvm_component_utils(apb_master_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    interrupt_imp = new("interrupt_imp", this);
    interrupt_pending = 1'b0;
    interrupt_level = 1'b0;
    interrupt_count = 0;
    serviced_interrupt_count = 0;
    set_arbitration(SEQ_ARB_STRICT_FIFO);
  endfunction

  function void write_apb_irq_seqr(apb_interrupt_item irq);
    interrupt_level = irq.asserted;
    if (irq.asserted) begin
      interrupt_pending = 1'b1;
      interrupt_count++;
    end
  endfunction
endclass
