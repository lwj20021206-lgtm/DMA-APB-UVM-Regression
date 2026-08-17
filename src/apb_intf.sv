// Keep the upstream-master and downstream-slave interfaces as separate
// types.  A single interface containing both clocking blocks creates an
// output driver for both roles on every instance, which VCS reports as an
// illegal structural/procedural driver combination.
interface apb_master_intf(input logic pclk);
  logic presetn;
  logic [31:0] paddr, pwdata, prdata;
  logic pwrite, psel, penable, pready;
  logic interrupt;

  clocking master_cb @(posedge pclk);
    default input #1step output #0;
    output paddr, pwrite, psel, penable, pwdata;
    input prdata, pready;
  endclocking

  clocking monitor_cb @(posedge pclk);
    default input #1step;
    input presetn, paddr, pwrite, psel, penable;
    input pwdata, prdata, pready, interrupt;
  endclocking
endinterface

interface apb_slave_intf(input logic pclk);
  logic [31:0] paddr, pwdata, prdata;
  logic pwrite, psel, penable, pready;

  clocking slave_cb @(posedge pclk);
    default input #1step output #0;
    input paddr, pwrite, psel, penable, pwdata;
    output prdata, pready;
  endclocking

  clocking monitor_cb @(posedge pclk);
    default input #1step;
    input paddr, pwrite, psel, penable, pwdata, prdata, pready;
  endclocking
endinterface
