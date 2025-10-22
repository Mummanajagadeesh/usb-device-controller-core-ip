// tb/tb_data_toggle.v
`timescale 1ns/1ps
`include "tb_common.v"

module tb_data_toggle;
  import usb_defs_pkg::*;

  reg clk;
  initial clk = 0;
  always #5 clk = ~clk;
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
  reg [7:0] payload [0:3];
  reg [7:0] recv [0:63];
  integer recv_len;

  initial begin
    host_pkt_valid=0; host_pid=0; host_addr=0; host_ep=0; host_data=0; host_data_valid=0; host_data_len=0; host_crc_err=0;
    do_reset();

    // Send two OUT transfers sequentially, expect data toggle to flip between DATA0 and DATA1 on IN responses
    payload[0]=8'h11; payload[1]=8'h22; payload[2]=8'h33; payload[3]=8'h44;

    // First OUT
    @(posedge clk); host_pkt_valid<=1; host_pid<=PID_OUT; host_addr<=0; host_ep<=EP1; host_data_len<=4; @(posedge clk); host_pkt_valid<=0;
    for (i=0;i<4;i=i+1) begin @(posedge clk); host_pkt_valid<=1; host_data_valid<=1; host_data<=payload[i]; @(posedge clk); host_pkt_valid<=0; host_data_valid<=0; end

    // IN request 1
    @(posedge clk); host_pkt_valid<=1; host_pid<=PID_IN; host_addr<=0; host_ep<=EP1; host_data_len<=0; @(posedge clk); host_pkt_valid<=0;
    recv_len=0; wait (host_tx_valid==1); integer exp_len1; exp_len1=host_tx_len;
    for (i=0;i<exp_len1;i=i+1) begin @(posedge clk); recv[i]=host_tx_data; recv_len=recv_len+1; end
    // record pid used
    reg [3:0] pid1; pid1 = host_tx_pid;

    // Second OUT (different payload)
    payload[0]=8'h55; payload[1]=8'h66;
    @(posedge clk); host_pkt_valid<=1; host_pid<=PID_OUT; host_addr<=0; host_ep<=EP1; host_data_len<=2; @(posedge clk); host_pkt_valid<=0;
    for (i=0;i<2;i=i+1) begin @(posedge clk); host_pkt_valid<=1; host_data_valid<=1; host_data<=payload[i]; @(posedge clk); host_pkt_valid<=0; host_data_valid<=0; end

    // IN request 2
    @(posedge clk); host_pkt_valid<=1; host_pid<=PID_IN; host_addr<=0; host_ep<=EP1; host_data_len<=0; @(posedge clk); host_pkt_valid<=0;
    recv_len=0; wait (host_tx_valid==1); integer exp_len2; exp_len2=host_tx_len;
    for (i=0;i<exp_len2;i=i+1) begin @(posedge clk); recv[i]=host_tx_data; recv_len=recv_len+1; end
    reg [3:0] pid2; pid2 = host_tx_pid;

    // Validate toggling: pid1 should be DATA0 and pid2 should be DATA1 (or vice versa depending on implementation initial)
    if (pid1 == pid2) begin
      $display("tb_data_toggle: FAIL - data PID did not toggle (pid1=%h pid2=%h)", pid1, pid2);
    end else begin
      $display("tb_data_toggle: PASS (pid1=%h pid2=%h)", pid1, pid2);
    end
    $finish;
  end

endmodule
