`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    06:25:58 08/12/2017
// Design Name:
// Module Name:    ctx
// Project Name:
// Target Devices:
// Tool versions:
// Description:    WRAM bus snooper for SA1.
//                 Mirrors SNES WRAM writes into PSRAM at $F50000-$F6FFFF
//                 so the MCU can read WRAM without interrupting gameplay.
//                 Stripped-down version of sd2snes_base ctx.v (WRAM only).
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module ctx(
  input clkin,
  input reset,
  input [23:0] SNES_ADDR,   // requested address from SNES
  input [7:0] SNES_PA,      // peripheral address from SNES
  input SNES_WR_end_PRE,        // WRITE from SNES
  input SNES_PAWR_end_PRE,      // PAWR from SNES
  input SNES_PARD_end_PRE,      // PARD from SNES
  input [7:0] SNES_DATA_IN_PRE,

  output OE_WR_ENABLE,
  output OE_PAWR_ENABLE,
  output OE_PARD_ENABLE,

  output BUS_WRQ,
  input BUS_RDY,

  output [23:0] ROM_ADDR,   // Address to request from SRAM0
  output [15:0] ROM_DATA,   // Data to write to SRAM0
  output        ROM_WORD_ENABLE
);

reg [7:0] SNES_DATA_IN; always @(posedge clkin) SNES_DATA_IN <= SNES_DATA_IN_PRE;
reg       SNES_WR_end; always @(posedge clkin) SNES_WR_end <= SNES_WR_end_PRE;
reg       SNES_PAWR_end; always @(posedge clkin) SNES_PAWR_end <= SNES_PAWR_end_PRE;
reg       SNES_PARD_end; always @(posedge clkin) SNES_PARD_end <= SNES_PARD_end_PRE;

//-------------------
// handle WRAM writes - upper 7b ignored
//-------------------
reg [23:0] WRAM_ADDR;

// bank $00-$3F,$80-$BF shadow RAM
reg IS_WRAM_SHADOW_ADDR_r; initial IS_WRAM_SHADOW_ADDR_r = 0;
reg IS_WRAM_BANK_ADDR_r; initial IS_WRAM_BANK_ADDR_r = 0;
reg IS_WRAM_PA_ADDR_r; initial IS_WRAM_PA_ADDR_r = 0;
assign IS_WRAM_SHADOW_ADDR = !SNES_ADDR[22] && (SNES_ADDR[15:13] == 3'h0);
assign IS_WRAM_SHADOW = SNES_WR_end && IS_WRAM_SHADOW_ADDR_r;
assign IS_WRAM_BANK_ADDR = ({SNES_ADDR[23:17],1'b0} == 8'h7E);
assign IS_WRAM_BANK = SNES_WR_end && IS_WRAM_BANK_ADDR_r;
assign IS_WRAM_PA_ADDR = (SNES_PA == 8'h80);
assign IS_WRAM_PA = SNES_PAWR_end && IS_WRAM_PA_ADDR_r;

assign IS_WRAM_ADDR = IS_WRAM_SHADOW_ADDR_r | IS_WRAM_BANK_ADDR_r | IS_WRAM_PA_ADDR_r;
assign IS_WRAM = IS_WRAM_SHADOW | IS_WRAM_BANK | IS_WRAM_PA;

// flop register state
always @(posedge clkin) begin
  if (reset) begin
    WRAM_ADDR <= 0;

    IS_WRAM_SHADOW_ADDR_r <= 0;
    IS_WRAM_BANK_ADDR_r <= 0;
    IS_WRAM_PA_ADDR_r <= 0;
  end
  else begin
    IS_WRAM_SHADOW_ADDR_r <= IS_WRAM_SHADOW_ADDR;
    IS_WRAM_BANK_ADDR_r <= IS_WRAM_BANK_ADDR;
    IS_WRAM_PA_ADDR_r <= IS_WRAM_PA_ADDR;

    if (SNES_PAWR_end | SNES_PARD_end) begin
      if      (SNES_PA == 8'h80) WRAM_ADDR[16: 0] <= WRAM_ADDR[16:0] + 1'b1;
    end
    if (SNES_PAWR_end) begin
      if      (SNES_PA == 8'h81) WRAM_ADDR[ 7: 0] <= SNES_DATA_IN;
      else if (SNES_PA == 8'h82) WRAM_ADDR[15: 8] <= SNES_DATA_IN;
      else if (SNES_PA == 8'h83) WRAM_ADDR[23:16] <= SNES_DATA_IN;
    end
  end
end

//-------------------
// generate address
//-------------------
wire [23:0] SRAM_SNES_ADDR;
assign SRAM_SNES_ADDR[23:0] = 24'hF50000 + ( IS_WRAM_SHADOW ? SNES_ADDR[12:0]
                                            : IS_WRAM_BANK   ? SNES_ADDR[16:0]
                                            :                  WRAM_ADDR[16:0]);

assign IS_WRITE = IS_WRAM;

// flop request
reg REQ;
initial REQ = 1'b0;
reg [23:0] ADDR;
initial ADDR = 24'h0;
reg [15:0] DATA;
initial DATA = 16'h0000;

always @(posedge clkin) begin
  if (IS_WRITE) begin
    REQ <= 1;
    ADDR[23:0] <= SRAM_SNES_ADDR[23:0];
    DATA[15:0] <= {SNES_DATA_IN, SNES_DATA_IN};
  end
  else begin
    REQ <= 0;
  end
end

// assign outputs
assign BUS_WRQ = REQ & BUS_RDY;
assign ROM_ADDR[23:0] = ADDR[23:0];
assign ROM_DATA[15:0] = DATA[15:0];
assign ROM_WORD_ENABLE = 1'b0; // always byte writes for WRAM

assign OE_WR_ENABLE = (IS_WRAM_SHADOW_ADDR_r || IS_WRAM_BANK_ADDR_r);
assign OE_PAWR_ENABLE = IS_WRAM_PA_ADDR_r;
assign OE_PARD_ENABLE = 1'b0; // WRAM DMA reads update address but we don't need data

endmodule
