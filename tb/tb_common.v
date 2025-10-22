// tb/tb_common.v
`timescale 1ns/1ps
// `include "../hw/usb_defs.v"

module tb_common;
  import usb_defs_pkg::*;

  // Clock generator
  reg clk;
  initial clk = 0;
  always #5 clk = ~clk; // 100MHz-ish (10ns period)

  // Reset
  reg rst_n;
  task do_reset();
    begin
      rst_n = 0;
      repeat (5) @(posedge clk);
      rst_n = 1;
      @(posedge clk);
    end
  endtask

  // Host-driver signals to DUT
  reg host_pkt_valid;
  reg [3:0] host_pid;
  reg [6:0] host_addr;
  reg [3:0] host_ep;
  reg [7:0] host_data;
  reg host_data_valid;
  reg [15:0] host_data_len;
  reg host_crc_err;

  // DUT outputs (device -> host)
  wire host_tx_valid;
  wire [3:0] host_tx_pid;
  wire [7:0] host_tx_data;
  wire [15:0] host_tx_len;

  // DUT instance signals (to be connected by each TB)

  // Helper tasks to send tokens and data
  task host_send_token(input [3:0] pid, input [6:0] addr, input [3:0] ep, input [15:0] dlen);
    begin
      @(posedge clk);
      host_pkt_valid <= 1'b1;
      host_pid <= pid;
      host_addr <= addr;
      host_ep <= ep;
      host_data_len <= dlen;
      host_crc_err <= 1'b0;
      // token present for one cycle
      @(posedge clk);
      host_pkt_valid <= 1'b0;
      host_pid <= 4'h0;
    end
  endtask

  task host_send_data_bytes(input [7:0] data_arr[], input integer len);
    integer i;
    begin
      for (i=0;i<len;i=i+1) begin
        @(posedge clk);
        host_pkt_valid <= 1'b1;
        host_data_valid <= 1'b1;
        host_data <= data_arr[i];
        @(posedge clk);
        host_pkt_valid <= 1'b0;
        host_data_valid <= 1'b0;
      end
    end
  endtask

  // capture host -> device responses
  // wait for host_tx_valid and collect bytes
  task capture_host_tx(output reg [7:0] outbuf[], output integer out_len);
    integer idx;
    integer expected;
    begin
      out_len = 0;
      // wait for host_tx_valid high
      wait (host_tx_valid == 1);
      // read host_tx_len to know how many bytes expected
      @(posedge clk);
      expected = host_tx_len;
      idx = 0;
      while (idx < expected) begin
        if (host_tx_valid) begin
          outbuf[idx] = host_tx_data;
          idx = idx + 1;
        end
        @(posedge clk);
      end
      out_len = idx;
    end
  endtask

  // smaller helper to convert integer to byte array
  task int_to_bytes(input integer val, output reg [7:0] outb[]);
    begin
      outb[0] = val & 8'hFF;
    end
  endtask

endmodule
