// tb/tb_set_address.v
`timescale 1ns/1ps
`include "tb_common.v"

module tb_set_address;
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
  initial begin
    // init
    host_pkt_valid = 0; host_pid = 0; host_addr = 0; host_ep = 0; host_data=0; host_data_valid=0; host_data_len=0; host_crc_err=0;
    do_reset();

    // Build SET_ADDRESS request: bRequest=5, wValue = new address
    reg [7:0] setup_bytes [0:7];
    integer new_addr;
    new_addr = 7'd5;
    setup_bytes[0] = 8'h00; // bmRequestType (host->device)
    setup_bytes[1] = 8'h05; // SET_ADDRESS
    setup_bytes[2] = new_addr[7:0]; // wValue LSB
    setup_bytes[3] = 8'h00;
    setup_bytes[4] = 8'h00; setup_bytes[5] = 8'h00;
    setup_bytes[6] = 8'h00; setup_bytes[7] = 8'h00;

    // Send SETUP token + 8 bytes
    @(posedge clk);
    host_pkt_valid <= 1'b1; host_pid <= PID_SETUP; host_addr <= 7'd0; host_ep <= 4'd0; host_data_len <= 8;
    @(posedge clk);
    host_pkt_valid <= 1'b0;
    for (i=0;i<8;i=i+1) begin
      @(posedge clk);
      host_pkt_valid <= 1'b1;
      host_data_valid <= 1'b1;
      host_data <= setup_bytes[i];
      @(posedge clk);
      host_pkt_valid <= 1'b0; host_data_valid <= 1'b0;
    end

    // Allow a few cycles for DUT to update address register
    repeat (10) @(posedge clk);

    if (dbg_addr_reg == new_addr) begin
      $display("tb_set_address: PASS");
    end else begin
      $display("tb_set_address: FAIL - expected addr %0d got %0d", new_addr, dbg_addr_reg);
    end
    $finish;
  end

endmodule
