// tb/tb_ep1_loopback.v
`timescale 1ns/1ps
`include "tb_common.v"

module tb_ep1_loopback;
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

  integer i, j;
  reg [7:0] tx_payload [0:63];
  reg [7:0] rx_buf [0:63];
  integer rx_len;

  initial begin
    // init
    host_pkt_valid=0; host_pid=0; host_addr=0; host_ep=0; host_data=0; host_data_valid=0; host_data_len=0; host_crc_err=0;
    do_reset();

    // Directed test: send OUT to EP1 with payload 8 bytes, then issue IN and expect same bytes
    integer len;
    len = 8;
    for (i=0;i<len;i=i+1) tx_payload[i] = i + 8'hA1;

    // Send OUT token header
    @(posedge clk);
    host_pkt_valid <= 1'b1; host_pid <= PID_OUT; host_addr <= 7'd0; host_ep <= EP1; host_data_len <= len;
    @(posedge clk);
    host_pkt_valid <= 1'b0;

    // send data bytes (DATA0 assumed)
    for (i=0;i<len;i=i+1) begin
      @(posedge clk);
      host_pkt_valid <= 1'b1;
      host_data_valid <= 1'b1;
      host_data <= tx_payload[i];
      @(posedge clk);
      host_pkt_valid <= 1'b0; host_data_valid <= 1'b0;
    end

    // Now request IN
    @(posedge clk);
    host_pkt_valid <= 1'b1; host_pid <= PID_IN; host_addr <= 7'd0; host_ep <= EP1; host_data_len <= 0;
    @(posedge clk);
    host_pkt_valid <= 1'b0;

    // capture response bytes
    rx_len = 0;
    wait (host_tx_valid == 1);
    integer expected_len;
    expected_len = host_tx_len;
    for (i=0;i<expected_len;i=i+1) begin
      @(posedge clk);
      rx_buf[i] = host_tx_data;
      rx_len = rx_len + 1;
    end

    // compare
    integer mismatch;
    mismatch = 0;
    if (rx_len != len) begin
      $display("tb_ep1_loopback: FAIL - length mismatch exp=%0d got=%0d", len, rx_len);
      $finish;
    end
    for (i=0;i<len;i=i+1) begin
      if (rx_buf[i] !== tx_payload[i]) begin
        mismatch = 1;
        $display("tb_ep1_loopback: FAIL - byte %0d mismatch exp=%02h got=%02h", i, tx_payload[i], rx_buf[i]);
      end
    end
    if (!mismatch) $display("tb_ep1_loopback: PASS");
    $finish;
  end

endmodule
