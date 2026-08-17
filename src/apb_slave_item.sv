class apb_slave_item extends uvm_sequence_item;
  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit [3:0] addr_delay;
  rand bit [3:0] ready_delay;
  rand bit write;

  function new(string name = "apb_slave_item");
    super.new(name);
  endfunction

  `uvm_object_utils_begin(apb_slave_item)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(data, UVM_DEFAULT)
    `uvm_field_int(addr_delay, UVM_DEFAULT)
    `uvm_field_int(ready_delay, UVM_DEFAULT)
    `uvm_field_int(write, UVM_DEFAULT)
  `uvm_object_utils_end
endclass
