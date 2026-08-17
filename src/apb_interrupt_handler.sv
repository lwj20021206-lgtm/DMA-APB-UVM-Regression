class apb_interrupt_handler extends uvm_component;
  apb_master_sequencer sequencer;

  `uvm_component_utils(apb_interrupt_handler)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      wait (sequencer != null && sequencer.interrupt_pending);

      phase.raise_objection(this, "servicing APB device interrupt");
      begin
        apb_interrupt_sequence irq_sequence;
        irq_sequence = apb_interrupt_sequence::type_id::create(
          "irq_sequence"
        );
        irq_sequence.start(sequencer, null, 1000);
      end
      sequencer.interrupt_pending = 1'b0;
      sequencer.serviced_interrupt_count++;
      phase.drop_objection(this, "APB device interrupt serviced");
    end
  endtask
endclass
