// hw/usb_addr_reg.v
`timescale 1ns/1ps
module usb_addr_reg (
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire                   wr_en,
  input  wire [6:0]             wr_addr,
  output reg  [6:0]             addr_out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr_out <= 7'd0;
    end else if (wr_en) begin
      addr_out <= wr_addr;
    end
  end

endmodule
