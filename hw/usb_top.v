// hw/usb_top.v
// Top-level integration: connects pktif, ctrl ep0, data ep1, addr reg
`timescale 1ns/1ps
// `include "usb_defs.v"

module usb_top (
  input  wire                   clk,
  input  wire                   rst_n,

  // host / testbench interface
  input  wire                   host_pkt_valid,
  input  wire [3:0]             host_pid,
  input  wire [6:0]             host_addr,
  input  wire [3:0]             host_ep,
  input  wire [7:0]             host_data,
  input  wire                   host_data_valid,
  input  wire [15:0]            host_data_len,
  input  wire                   host_crc_err,

  // host receive (device -> host) outputs (driven by pktif)
  output wire                   host_tx_valid,
  output wire [3:0]             host_tx_pid,
  output wire [7:0]             host_tx_data,
  output wire [15:0]            host_tx_len,

  // debug
  output wire [6:0]             dbg_addr_reg,
  output wire [3:0]             dbg_ep1_fifo_level
);

  // Internal wires
  // pktif <-> ep0
  wire ep0_rx_valid, ep0_rx_data_valid;
  wire [3:0] ep0_rx_pid;
  wire [6:0] ep0_rx_addr;
  wire [3:0] ep0_rx_ep;
  wire [7:0] ep0_rx_data_in;
  wire [15:0] ep0_rx_data_len;
  wire ep0_tx_req;
  wire [3:0] ep0_tx_pid;
  wire [15:0] ep0_tx_len;
  wire [7:0] ep0_tx_data [0:63];
  wire ep0_tx_ready;
  wire ep0_tx_issue;

  // pktif <-> ep1
  wire ep1_rx_valid, ep1_rx_data_valid;
  wire [3:0] ep1_rx_pid;
  wire [3:0] ep1_rx_ep;
  wire [7:0] ep1_rx_data_in;
  wire [15:0] ep1_rx_data_len;
  wire ep1_tx_req;
  wire [3:0] ep1_tx_pid;
  wire [15:0] ep1_tx_len;
  wire [7:0] ep1_tx_data [0:63];
  wire ep1_tx_ready;
  wire ep1_tx_issue;

  // Address reg wires
  wire addr_wr_en;
  wire [6:0] addr_wr_val;
  wire [6:0] addr_out;

  // Instantiate ctrl ep0
  usb_ctrl_ep0 ep0 (
    .clk(clk), .rst_n(rst_n),
    .rx_valid(ep0_rx_valid), .rx_pid(ep0_rx_pid),
    .rx_addr(ep0_rx_addr), .rx_ep(ep0_rx_ep),
    .rx_data_in(ep0_rx_data_in), .rx_data_valid(ep0_rx_data_valid),
    .rx_data_len(ep0_rx_data_len), .rx_crc_err(host_crc_err),

    .tx_req(ep0_tx_req), .tx_pid(ep0_tx_pid),
    .tx_len(ep0_tx_len), .tx_ready(ep0_tx_ready),
    .tx_data(ep0_tx_data),

    .addr_wr_en(addr_wr_en), .addr_wr_val(addr_wr_val)
  );

  // Instantiate data ep1
  usb_data_ep1 ep1 (
    .clk(clk), .rst_n(rst_n),
    .rx_valid(ep1_rx_valid), .rx_pid(ep1_rx_pid), .rx_ep(ep1_rx_ep),
    .rx_data_in(ep1_rx_data_in), .rx_data_valid(ep1_rx_data_valid),
    .rx_data_len(ep1_rx_data_len), .rx_crc_err(host_crc_err),
    .tx_req(ep1_tx_req), .tx_pid(ep1_tx_pid),
    .tx_len(ep1_tx_len), .tx_data(ep1_tx_data), .tx_ready(ep1_tx_ready),
    .fifo_level_out(dbg_ep1_fifo_level)
  );

  // Address register
  usb_addr_reg addr_reg (
    .clk(clk), .rst_n(rst_n),
    .wr_en(addr_wr_en),
    .wr_addr(addr_wr_val),
    .addr_out(addr_out)
  );

  // Pktif
  usb_pktif pktif (
    .clk(clk), .rst_n(rst_n),
    .host_pkt_valid(host_pkt_valid),
    .host_pid(host_pid),
    .host_addr(host_addr),
    .host_ep(host_ep),
    .host_data(host_data),
    .host_data_valid(host_data_valid),
    .host_data_len(host_data_len),
    .host_crc_err(host_crc_err),

    .ep0_rx_valid(ep0_rx_valid),
    .ep0_rx_pid(ep0_rx_pid),
    .ep0_rx_addr(ep0_rx_addr),
    .ep0_rx_ep(ep0_rx_ep),
    .ep0_rx_data_in(ep0_rx_data_in),
    .ep0_rx_data_valid(ep0_rx_data_valid),
    .ep0_rx_data_len(ep0_rx_data_len),

    .ep0_tx_req(ep0_tx_req),
    .ep0_tx_pid(ep0_tx_pid),
    .ep0_tx_len(ep0_tx_len),
    .ep0_tx_data(ep0_tx_data),
    .ep0_tx_ready(ep0_tx_ready),
    .ep0_tx_issue(ep0_tx_issue),

    .ep1_rx_valid(ep1_rx_valid),
    .ep1_rx_pid(ep1_rx_pid),
    .ep1_rx_ep(ep1_rx_ep),
    .ep1_rx_data_in(ep1_rx_data_in),
    .ep1_rx_data_valid(ep1_rx_data_valid),
    .ep1_rx_data_len(ep1_rx_data_len),

    .ep1_tx_req(ep1_tx_req),
    .ep1_tx_pid(ep1_tx_pid),
    .ep1_tx_len(ep1_tx_len),
    .ep1_tx_data(ep1_tx_data),
    .ep1_tx_ready(ep1_tx_ready),
    .ep1_tx_issue(ep1_tx_issue),

    .host_tx_valid(host_tx_valid),
    .host_tx_pid(host_tx_pid),
    .host_tx_data(host_tx_data),
    .host_tx_len(host_tx_len)
  );

  // debug outputs
  assign dbg_addr_reg = addr_out;

endmodule
