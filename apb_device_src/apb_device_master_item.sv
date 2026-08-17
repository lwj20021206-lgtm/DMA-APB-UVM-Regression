class apb_device_master_item extends apb_master_item;
  function new(string name = "apb_device_master_item");
    super.new(name);
  endfunction

  constraint c_feature {
    addr[31:28] inside {[4'b0000:4'b0100], 4'b1000, 4'b1111};
    (addr[31:28] == 4'b0100) -> (write == 1'b1);
    (addr[31:28] == 4'b1000) -> (write == 1'b1);
  }

  `uvm_object_utils(apb_device_master_item)
endclass
