class apb_slave_sequencer extends uvm_sequencer #(apb_slave_item);
  uvm_analysis_export #(apb_slave_item) aExport;
  uvm_tlm_analysis_fifo #(apb_slave_item) fifo;
  `uvm_component_utils(apb_slave_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    aExport = new("aExport", this);
    fifo = new("fifo", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    aExport.connect(fifo.analysis_export);
  endfunction
endclass
