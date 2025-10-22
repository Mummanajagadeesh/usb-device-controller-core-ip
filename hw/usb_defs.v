// hw/usb_defs.v
// Shared definitions for USB project
`ifndef USB_DEFS_V
`define USB_DEFS_V

// Using SystemVerilog features for convenience
package usb_defs_pkg;
  // PIDs (4-bit)
  localparam logic [3:0] PID_OUT   = 4'h1;
  localparam logic [3:0] PID_IN    = 4'h9;
  localparam logic [3:0] PID_SETUP = 4'h2;
  localparam logic [3:0] PID_DATA0 = 4'h3;
  localparam logic [3:0] PID_DATA1 = 4'hB;
  localparam logic [3:0] PID_ACK   = 4'h2; // simplified reuse
  localparam logic [3:0] PID_NAK   = 4'hA;
  localparam logic [3:0] PID_STALL = 4'hE;

  // Endpoint constants
  localparam int EP0 = 0;
  localparam int EP1 = 1;

  // Sizes
  localparam int MAX_PKT = 64;
  localparam int EP1_FIFO_DEPTH = 16; // entries
  localparam int ADDR_WIDTH = 7;

  // Status codes for test reporting
  typedef enum logic [1:0] {OK = 2'b00, ERR = 2'b01, STALLED = 2'b10} status_t;
endpackage

`endif
