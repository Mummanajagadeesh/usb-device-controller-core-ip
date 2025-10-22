// hw/usb_ctrl_ep0.v
// Control endpoint 0: handles SETUP, GET_DESCRIPTOR (device), SET_ADDRESS
`timescale 1ns/1ps
// `include "usb_defs.v"

module usb_ctrl_ep0 (
  input  wire                   clk,
  input  wire                   rst_n,

  // Incoming packet from token interface
  input  wire                   rx_valid,
  input  wire [3:0]             rx_pid,
  input  wire [6:0]             rx_addr, // device address field in token
  input  wire [3:0]             rx_ep,
  input  wire [7:0]             rx_data_in, // data stage bytes (for SETUP)
  input  wire                   rx_data_valid,
  input  wire [15:0]            rx_data_len,
  input  wire                   rx_crc_err,

  // Outgoing packet interface (to pktif)
  output reg                    tx_req,
  output reg  [3:0]             tx_pid,
  output reg  [15:0]            tx_len,
  output reg  [7:0]             tx_data [0:63],
  output reg                    tx_ready,

  // address register write interface
  output reg                    addr_wr_en,
  output reg  [6:0]             addr_wr_val
);

//   import usb_defs_pkg::*;

  // Local descriptor ROM (Device descriptor 18 bytes)
  localparam int DEV_DESC_LEN = 18;
  reg [7:0] dev_desc [0:DEV_DESC_LEN-1];

  initial begin
    // USB Device Descriptor (example values)
    dev_desc[0] = 8'h12; // bLength
    dev_desc[1] = 8'h01; // bDescriptorType (Device)
    dev_desc[2] = 8'h10; // bcdUSB LSB (1.1 -> 0x0110)
    dev_desc[3] = 8'h01; // bcdUSB MSB
    dev_desc[4] = 8'h00; // bDeviceClass
    dev_desc[5] = 8'h00; // bDeviceSubClass
    dev_desc[6] = 8'h00; // bDeviceProtocol
    dev_desc[7] = 8'h40; // bMaxPacketSize0 = 64
    dev_desc[8] = 8'h34; // idVendor LSB (example)
    dev_desc[9] = 8'h12; // idVendor MSB
    dev_desc[10]= 8'h78; // idProduct LSB
    dev_desc[11]= 8'h56; // idProduct MSB
    dev_desc[12]= 8'h00; // bcdDevice LSB
    dev_desc[13]= 8'h01; // bcdDevice MSB
    dev_desc[14]= 8'h01; // iManufacturer
    dev_desc[15]= 8'h02; // iProduct
    dev_desc[16]= 8'h03; // iSerialNumber
    dev_desc[17]= 8'h01; // bNumConfigurations
  end

  // Simple state machine
  typedef enum logic [2:0] {IDLE, SETUP_RECEIVE, DATA_IN_STAGE, STATUS_STAGE, SEND_STALL} state_t;
  state_t state, next_state;

  // buffer for setup packet (8 bytes)
  reg [7:0] setup_buf [0:7];
  integer setup_idx;
  integer i;

  // internal outputs
  reg [15:0] send_len;
  reg [7:0]  send_data_local [0:63];
  reg        have_response;

  // Decode SETUP (we expect rx_pid == PID_SETUP and rx_data_valid bytes)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      setup_idx <= 0;
      tx_req <= 1'b0;
      tx_ready <= 1'b0;
      addr_wr_en <= 1'b0;
      have_response <= 1'b0;
    end else begin
      state <= next_state;
      // default clears
      addr_wr_en <= 1'b0;
      tx_ready <= 1'b0;
      if (rx_data_valid && rx_pid == PID_SETUP && state == IDLE) begin
        // accumulate 8 bytes
        if (setup_idx < 8) begin
          setup_buf[setup_idx] <= rx_data_in;
          setup_idx <= setup_idx + 1;
        end
      end
    end
  end

  always_comb begin
    next_state = state;
    tx_req = 1'b0;
    tx_pid = PID_NAK;
    tx_len = 16'd0;
    have_response = 1'b0;
    addr_wr_val = 7'd0;
    case (state)
      IDLE: begin
        setup_idx = 0;
        if (rx_pid == PID_SETUP && rx_data_valid) begin
          next_state = SETUP_RECEIVE;
        end else begin
          next_state = IDLE;
        end
      end

      SETUP_RECEIVE: begin
        // we assume full 8-byte setup arrived in setup_buf (TB sends accordingly)
        // Parse bmRequestType, bRequest, wValue, wIndex, wLength
        // setup_buf[0] = bmRequestType
        // setup_buf[1] = bRequest
        // setup_buf[2] = wValue LSB
        // setup_buf[3] = wValue MSB
        // setup_buf[6] = wLength LSB
        // setup_buf[7] = wLength MSB
        if (setup_buf[1] == 8'h06) begin
          // GET_DESCRIPTOR
          // wValue MSB indicates descriptor type, LSB index
          if (setup_buf[3] == 8'h01) begin
            // Device descriptor requested
            // Prepare to send min(wLength, DEV_DESC_LEN) bytes
            send_len = (setup_buf[7]*256 + setup_buf[6]) < DEV_DESC_LEN ? (setup_buf[7]*256 + setup_buf[6]) : DEV_DESC_LEN;
            for (i=0;i<send_len;i=i+1) send_data_local[i] = dev_desc[i];
            tx_pid = PID_DATA0;
            tx_req = 1'b1;
            tx_len = send_len;
            have_response = 1'b1;
            next_state = STATUS_STAGE; // after data stage return status (ACK from host)
          end else begin
            // unsupported descriptor
            next_state = SEND_STALL;
          end
        end else if (setup_buf[1] == 8'h05) begin
          // SET_ADDRESS
          // wValue LSB contains address
          addr_wr_val = setup_buf[2][6:0];
          // write occurs at the status stage completion (per USB spec)
          tx_pid = PID_ACK; // status stage: device must ACK
          tx_req = 1'b1;
          tx_len = 16'd0;
          have_response = 1'b1;
          next_state = IDLE;
          // latch address immediately to addr_wr_en (for our simple model)
          addr_wr_en = 1'b1;
        end else begin
          // Not implemented other requests -> STALL
          next_state = SEND_STALL;
        end
      end

      SEND_STALL: begin
        tx_pid = PID_STALL;
        tx_req = 1'b1;
        tx_len = 16'd0;
        next_state = IDLE;
      end

      STATUS_STAGE: begin
        // For simplicity, we assume host acknowledges the data and we go to IDLE
        next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  // Drive tx_data outputs when tx_req asserted
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_ready <= 1'b0;
    end else begin
      if (have_response) begin
        // copy to outputs
        for (i=0;i<64;i=i+1) begin
          if (i < tx_len)
            tx_data[i] <= send_data_local[i];
          else
            tx_data[i] <= 8'h00;
        end
        tx_ready <= 1'b1;
      end else begin
        tx_ready <= 1'b0;
      end
    end
  end

endmodule
