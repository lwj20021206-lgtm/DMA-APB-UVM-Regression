class dma_apb_base_test extends uvm_test;
  apb_device_env apb_device_env_1;
  UVM_FILE f_dma_read;
  UVM_FILE f_dma_write;

  `uvm_component_utils(dma_apb_base_test)

  function new(string name = "dma_apb_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void set_master_sequence(uvm_object_wrapper sequence_type);
    uvm_config_db#(uvm_object_wrapper)::set(
      this,
      "apb_device_env_1.apb_master_agent_1.apb_master_sequencer_1.main_phase",
      "default_sequence",
      sequence_type
    );
  endfunction

  function void set_slave_sequence(uvm_object_wrapper sequence_type);
    uvm_config_db#(uvm_object_wrapper)::set(
      this,
      "apb_device_env_1.apb_slave_agent_1.apb_slave_sequencer_1.run_phase",
      "default_sequence",
      sequence_type
    );
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_master_item::type_id::set_type_override(
      apb_device_master_item::get_type()
    );
    set_slave_sequence(apb_slave_basic_sequence::type_id::get());
    apb_device_env_1 = apb_device_env::type_id::create(
      "apb_device_env_1", this
    );
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    f_dma_read = $fopen("dma_read.txt", "w");
    f_dma_write = $fopen("dma_write.txt", "w");
    uvm_top.set_report_severity_id_file_hier(
      UVM_INFO, "DMA write", f_dma_write
    );
    uvm_top.set_report_severity_id_file_hier(
      UVM_INFO, "DMA read", f_dma_read
    );
    uvm_top.set_report_severity_id_action_hier(
      UVM_INFO, "DMA write", UVM_LOG | UVM_DISPLAY
    );
    uvm_top.set_report_severity_id_action_hier(
      UVM_INFO, "DMA read", UVM_LOG | UVM_DISPLAY
    );
  endfunction

endclass

class dma_apb_smoke_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_smoke_test)

  function new(string name = "dma_apb_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(apb_master_basic_sequence::type_id::get());
  endfunction
endclass

class dma_apb_register_direct_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_register_direct_test)

  function new(string name = "dma_apb_register_direct_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_register_direct_sequence::type_id::get());
  endfunction
endclass

class dma_apb_init_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_init_test)

  function new(string name = "dma_apb_init_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_init_sequence::type_id::get());
  endfunction
endclass

class dma_apb_copy_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_copy_test)

  function new(string name = "dma_apb_copy_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_copy_sequence::type_id::get());
  endfunction
endclass

class dma_apb_interrupt_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_interrupt_test)

  function new(string name = "dma_apb_interrupt_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_interrupt_sequence::type_id::get());
  endfunction
endclass

class dma_apb_target_wait_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_target_wait_test)

  function new(string name = "dma_apb_target_wait_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_target_wait_sequence::type_id::get());
    set_slave_sequence(apb_slave_coverage_sequence::type_id::get());
  endfunction
endclass

class dma_apb_wait_state_test extends dma_apb_target_wait_test;
  `uvm_component_utils(dma_apb_wait_state_test)

  function new(string name = "dma_apb_wait_state_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class dma_apb_busy_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_busy_test)

  function new(string name = "dma_apb_busy_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_busy_sequence::type_id::get());
  endfunction
endclass

class dma_apb_reset_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_reset_test)

  function new(string name = "dma_apb_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_reset_sequence::type_id::get());
  endfunction
endclass

class dma_apb_random_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_random_test)

  function new(string name = "dma_apb_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_random_sequence::type_id::get());
  endfunction
endclass

class dma_apb_full_coverage_test extends dma_apb_base_test;
  `uvm_component_utils(dma_apb_full_coverage_test)

  function new(string name = "dma_apb_full_coverage_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_master_sequence(dma_apb_full_coverage_sequence::type_id::get());
    set_slave_sequence(apb_slave_coverage_sequence::type_id::get());
  endfunction
endclass

// Backward-compatible name used by the original Makefile and examples.
class test extends dma_apb_smoke_test;
  `uvm_component_utils(test)

  function new(string name = "test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass
