// tb/tb_get_descriptor.v
`timescale 1ns/1ps
`include "tb_common.v"

module tb_get_descriptor;
  import usb_defs_pkg::*;

  // Clk / reset
  reg clk;
  initial clk = 0;
  always #5 clk = ~clk;
  reg rst_n;

  // Host->DUT signals
  reg host_pkt_valid;
  reg [3:0] host_pid;
  reg [6:0] host_addr;
  reg [3:0] host_ep;
  reg [7:0] host_data;
  reg host_data_valid;
  reg [15:0] host_data_len;
  reg host_crc_err;

  // Device->Host
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

  // helper tasks
  task do_reset();
    begin
      rst_n = 0;
      repeat (5) @(posedge clk);
      rst_n = 1;
      @(posedge clk);
    end
  endtask

  integer i;
  reg [7:0] expected [0:17];
  reg [7:0] recv [0:63];
  integer recv_len;

  initial begin
    // setup
    host_pkt_valid = 0; host_pid = 0; host_addr = 0; host_ep = 0; host_data = 0;
    host_data_valid = 0; host_data_len = 0; host_crc_err = 0;
    do_reset();

    // Build a standard GET_DESCRIPTOR (device) SETUP packet (bRequest=6)
    // We will send token PID_SETUP, followed by 8 setup bytes, then expect DATA stage from device
    // Setup bytes (bmRequestType, bRequest, wValue LSB, wValue MSB, wIndex LSB, wIndex MSB, wLength LSB, wLength MSB)
    reg [7:0] setup_bytes [0:7];
    setup_bytes[0] = 8'h80; // bmRequestType (device to host)
    setup_bytes[1] = 8'h06; // GET_DESCRIPTOR
    setup_bytes[2] = 8'h00; // wValue LSB -> descriptor index 0
    setup_bytes[3] = 8'h01; // wValue MSB -> descriptor type Device (1)
    setup_bytes[4] = 8'h00; setup_bytes[5] = 8'h00;
    setup_bytes[6] = 8'hFF; // ask large length (255) to force truncation to actual descriptor length
    setup_bytes[7] = 8'h00;

    // expected device descriptor (same as in hw/usb_ctrl_ep0.v)
    expected[0]=8'h12; expected[1]=8'h01; expected[2]=8'h10; expected[3]=8'h01;
    expected[4]=8'h00; expected[5]=8'h00; expected[6]=8'h00; expected[7]=8'h40;
    expected[8]=8'h34; expected[9]=8'h12; expected[10]=8'h78; expected[11]=8'h56;
    expected[12]=8'h00; expected[13]=8'h01; expected[14]=8'h01; expected[15]=8'h02;
    expected[16]=8'h03; expected[17]=8'h01;

    // Send SETUP token to EP0
    @(posedge clk);
    host_pkt_valid <= 1'b1;
    host_pid <= PID_SETUP;
    host_addr <= 7'd0;
    host_ep <= 4'd0;
    host_data_len <= 16'd8;
    @(posedge clk);
    host_pkt_valid <= 1'b0;

    // send 8 setup bytes (host_data_valid sequential)
    for (i=0;i<8;i=i+1) begin
      @(posedge clk);
      host_pkt_valid <= 1'b1;
      host_data_valid <= 1'b1;
      host_data <= setup_bytes[i];
      @(posedge clk);
      host_pkt_valid <= 1'b0;
      host_data_valid <= 1'b0;
    end

    // now wait for device to produce data (host_tx_valid). capture all bytes
    recv_len = 0;
    wait (host_tx_valid == 1'b1);
    integer expected_len;
    expected_len = host_tx_len;
    for (i=0;i<expected_len;i=i+1) begin
      @(posedge clk);
      recv[i] = host_tx_data;
      recv_len = recv_len + 1;
    end

    // compare
    integer mismatch;
    mismatch = 0;
    for (i=0;i<recv_len;i=i+1) begin
      if (recv[i] !== expected[i]) begin
        mismatch = 1;
        $display("tb_get_descriptor: FAIL - byte %0d mismatch exp=%02h got=%02h", i, expected[i], recv[i]);
      end
    end
    if (mismatch == 0) begin
      $display("tb_get_descriptor: PASS");
    end
    $finish;
  end

endmodule
