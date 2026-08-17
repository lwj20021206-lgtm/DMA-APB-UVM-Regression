class apb_interrupt_item extends uvm_sequence_item;
  bit asserted;
  time observed_at;

  `uvm_object_utils_begin(apb_interrupt_item)
    `uvm_field_int(asserted, UVM_DEFAULT)
    `uvm_field_int(observed_at, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "apb_interrupt_item");
    super.new(name);
  endfunction
endclass
