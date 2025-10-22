// tb/tb_reset.v
`timescale 1ns/1ps
// `include "tb_common.v"

module tb_reset;
  import usb_defs_pkg::*;
  // instantiate tb_common by inheritance using `include` trick: we'll re-declare necessary wires and instantiate top

  // bring in clk/rst from tb_common
  reg clk;
  reg rst_n;
  initial clk = 0;
  always #5 clk = ~clk;

  // DUT interface signals
  reg host_pkt_valid;
  reg [3:0] host_pid;
  reg [6:0] host_addr;
  reg [3:0] host_ep;
  reg [7:0] host_data;
  reg host_data_valid;
  reg [15:0] host_data_len;
  reg host_crc_err;

  wire host_tx_valid;
  wire [3:0] host_tx_pid;
  wire [7:0] host_tx_data;
  wire [15:0] host_tx_len;
  wire [6:0] dbg_addr_reg;
  wire [3:0] dbg_ep1_fifo_level;

  // instantiate DUT
  usb_top dut (
    .clk(clk), .rst_n(rst_n),
    .host_pkt_valid(host_pkt_valid),
    .host_pid(host_pid),
    .host_addr(host_addr),
    .host_ep(host_ep),
    .host_data(host_data),
    .host_data_valid(host_data_valid),
    .host_data_len(host_data_len),
    .host_crc_err(host_crc_err),

    .host_tx_valid(host_tx_valid),
    .host_tx_pid(host_tx_pid),
    .host_tx_data(host_tx_data),
    .host_tx_len(host_tx_len),

    .dbg_addr_reg(dbg_addr_reg),
    .dbg_ep1_fifo_level(dbg_ep1_fifo_level)
  );

  // RE-USE helper tasks (redeclare here)
  task do_reset();
    begin
      rst_n = 0;
      repeat (5) @(posedge clk);
      rst_n = 1;
      @(posedge clk);
    end
  endtask

  task host_send_token(input [3:0] pid, input [6:0] addr, input [3:0] ep, input [15:0] dlen);
    begin
      @(posedge clk);
      host_pkt_valid <= 1'b1;
      host_pid <= pid;
      host_addr <= addr;
      host_ep <= ep;
      host_data_len <= dlen;
      host_crc_err <= 1'b0;
      @(posedge clk);
      host_pkt_valid <= 1'b0;
    end
  endtask

  initial begin
    // init
    host_pkt_valid = 0; host_pid = 0; host_addr = 0; host_ep = 0;
    host_data = 0; host_data_valid = 0; host_data_len = 0; host_crc_err = 0;
    // Apply reset
    do_reset();
    // Check defaults
    #10;
    if (dbg_addr_reg !== 7'd0) begin
      $display("tb_reset: FAIL - addr default not zero (%0d)", dbg_addr_reg);
      $finish;
    end
    if (dbg_ep1_fifo_level !== 0) begin
      $display("tb_reset: FAIL - ep1 fifo not empty (%0d)", dbg_ep1_fifo_level);
      $finish;
    end
    $display("tb_reset: PASS");
    $finish;
  end

endmodule
