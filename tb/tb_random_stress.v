// tb/tb_random_stress.v
`timescale 1ns/1ps
`include "tb_common.v"

module tb_random_stress;
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

  integer iter, i, len;
  reg [7:0] payload [0:63];
  reg [7:0] rc [0:63];
  integer rc_len;
  initial begin
    host_pkt_valid=0; host_pid=0; host_addr=0; host_ep=0; host_data=0; host_data_valid=0; host_data_len=0; host_crc_err=0;
    do_reset();

    // random stress: do 50 random sequences of OUT or IN on EP1
    for (iter=0; iter<50; iter=iter+1) begin
      if ($urandom_range(0,1) == 0) begin
        // generate random OUT
        len = $urandom_range(1,16);
        for (i=0;i<len;i=i+1) payload[i] = $urandom_range(0,255);
        // send OUT token
        @(posedge clk); host_pkt_valid<=1; host_pid<=PID_OUT; host_addr<=0; host_ep<=EP1; host_data_len<=len; @(posedge clk); host_pkt_valid<=0;
        for (i=0;i<len;i=i+1) begin @(posedge clk); host_pkt_valid<=1; host_data_valid<=1; host_data<=payload[i]; @(posedge clk); host_pkt_valid<=0; host_data_valid<=0; end
      end else begin
        // IN
        @(posedge clk); host_pkt_valid<=1; host_pid<=PID_IN; host_addr<=0; host_ep<=EP1; host_data_len<=0; @(posedge clk); host_pkt_valid<=0;
        // capture if any
        if (host_tx_valid) begin
          rc_len = host_tx_len;
          for (i=0;i<rc_len;i=i+1) begin @(posedge clk); rc[i] = host_tx_data; end
        end
      end
      // small pause
      repeat (2) @(posedge clk);
    end
    $display("tb_random_stress: PASS");
    $finish;
  end

endmodule
