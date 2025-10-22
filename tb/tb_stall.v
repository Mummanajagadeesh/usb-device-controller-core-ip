// tb/tb_stall.v
`timescale 1ns/1ps
`include "tb_common.v"

module tb_stall;
  import usb_defs_pkg::*;

  reg clk; initial clk=0; always #5 clk=~clk;
  reg rst_n;

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

  task do_reset(); begin rst_n=0; repeat (5) @(posedge clk); rst_n=1; @(posedge clk); end endtask

  integer i;
  initial begin
    host_pkt_valid=0; host_pid=0; host_addr=0; host_ep=0; host_data=0; host_data_valid=0; host_data_len=0; host_crc_err=0;
    do_reset();

    // Issue unsupported control request bRequest=0xFF to EP0
    reg [7:0] setup_bytes [0:7];
    setup_bytes[0]=8'h00; setup_bytes[1]=8'hFF; setup_bytes[2]=8'h00; setup_bytes[3]=8'h00;
    setup_bytes[4]=8'h00; setup_bytes[5]=8'h00; setup_bytes[6]=8'h00; setup_bytes[7]=8'h00;

    @(posedge clk); host_pkt_valid<=1; host_pid<=PID_SETUP; host_addr<=0; host_ep<=0; host_data_len<=8; @(posedge clk); host_pkt_valid<=0;
    for (i=0;i<8;i=i+1) begin @(posedge clk); host_pkt_valid<=1; host_data_valid<=1; host_data<=setup_bytes[i]; @(posedge clk); host_pkt_valid<=0; host_data_valid<=0; end

    // expect STALL response (host_tx_pid == PID_STALL)
    wait (host_tx_valid==1);
    if (host_tx_pid == PID_STALL) $display("tb_stall: PASS");
    else $display("tb_stall: FAIL - expected STALL got pid=%h", host_tx_pid);
    $finish;
  end

endmodule
