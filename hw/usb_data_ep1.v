// hw/usb_data_ep1.v
// Simple endpoint 1: FIFO-backed loopback. Handles OUT -> store in FIFO; IN -> return FIFO data
`timescale 1ns/1ps
// `include "usb_defs.v"

module usb_data_ep1 (
  input  wire                   clk,
  input  wire                   rst_n,

  // incoming token/data from pktif
  input  wire                   rx_valid,
  input  wire [3:0]             rx_pid,
  input  wire [3:0]             rx_ep,
  input  wire [7:0]             rx_data_in,
  input  wire                   rx_data_valid,
  input  wire [15:0]            rx_data_len,
  input  wire                   rx_crc_err,

  // outgoing packet to pktif
  output reg                    tx_req,
  output reg  [3:0]             tx_pid,
  output reg  [15:0]            tx_len,
  output reg  [7:0]             tx_data [0:63],
  output reg                    tx_ready,

  // debug/status
  output reg  [3:0]             fifo_level_out
);

  // FIFO implemented with regs
  localparam DEPTH = EP1_FIFO_DEPTH;
  reg [7:0] fifo [0:DEPTH-1];
  integer wr_ptr, rd_ptr;
  integer fifo_count;
  integer i;

  // data toggle: 0 => DATA0 expected, 1 => DATA1 expected
  reg data_toggle;

  // Initialize / main FIFO handling
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= 0;
      rd_ptr <= 0;
      fifo_count <= 0;
      data_toggle <= 1'b0;
      tx_ready <= 1'b0;
      tx_req <= 1'b0;
      fifo_level_out <= 0;
    end else begin
      // RX handling: OUT tokens with data payload are stored
      if (rx_valid && (rx_pid == PID_OUT || rx_pid == PID_DATA0 || rx_pid == PID_DATA1) && rx_ep == EP1 && rx_data_valid) begin
        // write bytes sequentially (TB will present bytes one by one)
        if (fifo_count < DEPTH) begin
          fifo[wr_ptr] <= rx_data_in;
          wr_ptr <= (wr_ptr + 1) % DEPTH;
          fifo_count <= fifo_count + 1;
        end else begin
          // overflow: we drop and indicate by not ACKing in pktif (pktif can NAK)
        end
      end

      // RX handling: IN token: prepare data if available
      if (rx_valid && rx_pid == PID_IN && rx_ep == EP1) begin
        if (fifo_count == 0) begin
          // nothing to send -> NAK (pktif will handle)
          tx_req <= 1'b0;
          tx_ready <= 1'b0;
          tx_len <= 16'd0;
        end else begin
          // prepare a packet up to MAX_PKT or until fifo empties
          integer send_cnt;
          send_cnt = (fifo_count > MAX_PKT) ? MAX_PKT : fifo_count;
          for (i = 0; i < send_cnt; i = i + 1) begin
            tx_data[i] <= fifo[rd_ptr];
            rd_ptr <= (rd_ptr + 1) % DEPTH;
          end
          // fix fifo_count and pointers properly
          fifo_count <= fifo_count - send_cnt;
          tx_len <= send_cnt;
          tx_pid <= data_toggle ? PID_DATA1 : PID_DATA0;
          data_toggle <= ~data_toggle;
          tx_req <= 1'b1;
          tx_ready <= 1'b1;
        end
      end else begin
        // clear one-cycle tx signals
        if (tx_ready) begin
          // keep ready for one cycle, then clear
          tx_ready <= 1'b0;
        end
      end

      // drive debug
      fifo_level_out <= fifo_count[3:0];
    end
  end

endmodule
