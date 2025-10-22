// hw/usb_pktif.v
// Packet interface: receives token-level inputs from host (TB) and dispatches to endpoints
// For simplicity, host provides token-level signals and data bytes sequentially.
`timescale 1ns/1ps
// `include "usb_defs.v"

module usb_pktif (
  input  wire                   clk,
  input  wire                   rst_n,

  // From host (TB)
  input  wire                   host_pkt_valid, // high when a token or data byte is present
  input  wire [3:0]             host_pid,
  input  wire [6:0]             host_addr, // device address field from token
  input  wire [3:0]             host_ep,
  input  wire [7:0]             host_data, // used for data bytes (including SETUP)
  input  wire                   host_data_valid,
  input  wire [15:0]            host_data_len,
  input  wire                   host_crc_err,

  // Endpoint 0 interface
  output reg                    ep0_rx_valid,
  output reg  [3:0]             ep0_rx_pid,
  output reg  [6:0]             ep0_rx_addr,
  output reg  [3:0]             ep0_rx_ep,
  output reg  [7:0]             ep0_rx_data_in,
  output reg                    ep0_rx_data_valid,
  output reg  [15:0]            ep0_rx_data_len,
  input  wire                   ep0_tx_req,
  input  wire [3:0]             ep0_tx_pid,
  input  wire [15:0]            ep0_tx_len,
  input  wire [7:0]             ep0_tx_data [0:63],
  input  wire                   ep0_tx_ready,
  output reg                    ep0_tx_issue,

  // Endpoint 1 interface
  output reg                    ep1_rx_valid,
  output reg  [3:0]             ep1_rx_pid,
  output reg  [3:0]             ep1_rx_ep,
  output reg  [7:0]             ep1_rx_data_in,
  output reg                    ep1_rx_data_valid,
  output reg  [15:0]            ep1_rx_data_len,
  input  wire                   ep1_tx_req,
  input  wire [3:0]             ep1_tx_pid,
  input  wire [15:0]            ep1_tx_len,
  input  wire [7:0]             ep1_tx_data [0:63],
  input  wire                   ep1_tx_ready,
  output reg                    ep1_tx_issue,

  // Outgoing to host
  output reg                    host_tx_valid,
  output reg [3:0]              host_tx_pid,
  output reg [7:0]              host_tx_data,
  output reg [15:0]             host_tx_len
);

  import usb_defs_pkg::*;

  // Simple router FSM: when host sends a token, set rx_* signals for targeted EP,
  // forward data bytes, and if endpoint responds with tx_req, forward tx to host.

  typedef enum logic [1:0] {S_IDLE, S_RX_DATA, S_PROC_TX} state_t;
  state_t state;

  integer data_count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      host_tx_valid <= 1'b0;
      ep0_rx_valid <= 1'b0;
      ep1_rx_valid <= 1'b0;
      ep0_rx_data_valid <= 1'b0;
      ep1_rx_data_valid <= 1'b0;
      ep0_tx_issue <= 1'b0;
      ep1_tx_issue <= 1'b0;
      host_tx_len <= 16'd0;
    end else begin
      case (state)
        S_IDLE: begin
          host_tx_valid <= 1'b0;
          ep0_tx_issue <= 1'b0;
          ep1_tx_issue <= 1'b0;
          ep0_rx_data_valid <= 1'b0;
          ep1_rx_data_valid <= 1'b0;

          if (host_pkt_valid) begin
            // A token or data present. If token -> host_pid indicates token type.
            if (host_pid == PID_SETUP || host_pid == PID_OUT || host_pid == PID_IN) begin
              // send token header to appropriate EP
              if (host_ep == EP0) begin
                ep0_rx_valid <= 1'b1;
                ep0_rx_pid <= host_pid;
                ep0_rx_addr <= host_addr;
                ep0_rx_ep <= host_ep;
                // If there is data length >0, enter RX_DATA to stream bytes
                if (host_data_len > 0) begin
                  state <= S_RX_DATA;
                  data_count <= 0;
                end else begin
                  // no data stage; allow endpoint to respond if needed
                  state <= S_PROC_TX;
                end
              end else if (host_ep == EP1) begin
                ep1_rx_valid <= 1'b1;
                ep1_rx_pid <= host_pid;
                ep1_rx_ep <= host_ep;
                if (host_data_len > 0) begin
                  state <= S_RX_DATA;
                  data_count <= 0;
                end else begin
                  state <= S_PROC_TX;
                end
              end else begin
                // unknown ep -> ignore
                state <= S_IDLE;
              end
            end else if (host_pid == PID_DATA0 || host_pid == PID_DATA1) begin
              // data packet header; stream in bytes to previous targeted EP
              state <= S_RX_DATA;
              data_count <= 0;
            end else begin
              // other PIDs not explicitly handled; ignore
              state <= S_IDLE;
            end
          end
        end

        S_RX_DATA: begin
          // Host supplies data bytes sequentially using host_data_valid and host_data
          if (host_data_valid) begin
            // determine which EP is active from last header
            if (ep0_rx_valid) begin
              ep0_rx_data_valid <= 1'b1;
              ep0_rx_data_in <= host_data;
              ep0_rx_data_len <= host_data_len; // pass full length for context
            end else if (ep1_rx_valid) begin
              ep1_rx_data_valid <= 1'b1;
              ep1_rx_data_in <= host_data;
              ep1_rx_data_len <= host_data_len;
            end
            data_count = data_count + 1;
            if (data_count >= host_data_len) begin
              // finished
              state <= S_PROC_TX;
            end
          end
        end

        S_PROC_TX: begin
          // query endpoints: if they assert tx_req and tx_ready, forward
          if (ep0_tx_req && ep0_tx_ready) begin
            // stream ep0 tx_data of length ep0_tx_len to host (one byte per cycle)
            integer k;
            for (k=0;k<ep0_tx_len;k=k+1) begin
              host_tx_valid <= 1'b1;
              host_tx_pid <= ep0_tx_pid;
              host_tx_data <= ep0_tx_data[k];
              host_tx_len <= ep0_tx_len;
              @(posedge clk); // one cycle per byte
            end
            host_tx_valid <= 1'b0;
            ep0_tx_issue <= 1'b1;
          end else if (ep1_tx_req && ep1_tx_ready) begin
            integer m;
            for (m=0;m<ep1_tx_len;m=m+1) begin
              host_tx_valid <= 1'b1;
              host_tx_pid <= ep1_tx_pid;
              host_tx_data <= ep1_tx_data[m];
              host_tx_len <= ep1_tx_len;
              @(posedge clk);
            end
            host_tx_valid <= 1'b0;
            ep1_tx_issue <= 1'b1;
          end
          // clear rx_valid flags and return to idle
          ep0_rx_valid <= 1'b0;
          ep1_rx_valid <= 1'b0;
          ep0_rx_data_valid <= 1'b0;
          ep1_rx_data_valid <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
