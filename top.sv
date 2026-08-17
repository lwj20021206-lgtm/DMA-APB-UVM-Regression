`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "apb_device.v"
`include "src/apb_intf.sv"
`include "src/apb_master_item.sv"
`include "src/apb_interrupt_item.sv"
`include "src/apb_master_driver.sv"
`include "src/apb_master_monitor.sv"
`include "src/apb_master_sequencer.sv"
`include "src/apb_interrupt_sequence.sv"
`include "src/apb_interrupt_handler.sv"
`include "src/apb_master_agent.sv"
`include "src/apb_master_base_sequence.sv"
`include "src/apb_master_basic_sequence.sv"
`include "src/apb_slave_item.sv"
`include "src/apb_slave_driver.sv"
`include "src/apb_slave_monitor.sv"
`include "src/apb_slave_sequencer.sv"
`include "src/apb_slave_agent.sv"
`include "src/apb_slave_basic_sequence.sv"
`include "sequences/apb_slave_coverage_sequence.sv"
`include "sequences/dma_apb_coverage_sequences.sv"
`include "apb_device_src/apb_device_master_item.sv"
`include "apb_device_src/apb_device_coverage_full.sv"
`include "apb_device_src/apb_device_scoreboard.sv"
`include "apb_device_src/apb_device_env.sv"
`include "test.sv"

module top;
  parameter CYCLE = 10;
  logic clk;
  wire apb_device_int;

  initial begin
    clk = 0;
    forever #(CYCLE/2) clk = ~clk;
  end

  apb_master_intf APB_MINTF(clk);
  apb_slave_intf APB_SINTF(clk);
  apb_device_cov_probe_if COV_PROBE(clk);

  assign APB_MINTF.interrupt = apb_device_int;
  assign COV_PROBE.presetn = APB_MINTF.presetn;
  assign COV_PROBE.interrupt = apb_device_int;
  assign COV_PROBE.dma_busy = DUT.is_dma_busy;

  APB_DEVICE DUT(
    .pclk(APB_MINTF.pclk), .presetn(APB_MINTF.presetn),
    .paddr(APB_MINTF.paddr), .pwrite(APB_MINTF.pwrite),
    .psel(APB_MINTF.psel), .penable(APB_MINTF.penable),
    .pwdata(APB_MINTF.pwdata), .prdata(APB_MINTF.prdata),
    .pready(APB_MINTF.pready),
    .slave_paddr(APB_SINTF.paddr), .slave_pwrite(APB_SINTF.pwrite),
    .slave_psel(APB_SINTF.psel), .slave_penable(APB_SINTF.penable),
    .slave_pwdata(APB_SINTF.pwdata), .slave_prdata(APB_SINTF.prdata),
    .slave_pready(APB_SINTF.pready), .apb_device_int(apb_device_int)
  );

  initial begin
    uvm_config_db#(virtual apb_master_intf)::set(
      null, "uvm_test_top.apb_device_env_1", "APB_VMINTF", APB_MINTF
    );
    uvm_config_db#(virtual apb_slave_intf)::set(
      null, "uvm_test_top.apb_device_env_1", "APB_VSINTF", APB_SINTF
    );
    uvm_config_db#(virtual apb_device_cov_probe_if)::set(
      null, "uvm_test_top.apb_device_env_1", "COV_PROBE", COV_PROBE
    );
    run_test();
  end

`ifdef ENABLE_FSDB
  initial begin
    string fsdb_file;
    if ($test$plusargs("DUMP_FSDB")) begin
      if (!$value$plusargs("FSDB_FILE=%s", fsdb_file))
        fsdb_file = "waveform.fsdb";
      $fsdbDumpfile(fsdb_file);
      $fsdbDumpvars(0, top, "+all");
    end
  end
`endif

`ifdef ENABLE_VPD
  initial begin
    string vpd_file;
    if ($test$plusargs("DUMP_VPD")) begin
      if (!$value$plusargs("VPD_FILE=%s", vpd_file))
        vpd_file = "waveform.vpd";
      $vcdplusfile(vpd_file);
      $vcdpluson(0, top);
      $vcdplusmemon();
    end
  end
`endif

  initial begin
    #10ms;
    `uvm_fatal("TIMEOUT", "Simulation exceeded 10 ms")
  end
endmodule
