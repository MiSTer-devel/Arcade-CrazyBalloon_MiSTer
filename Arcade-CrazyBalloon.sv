//============================================================================
//  Arcade: CrazyBalloon
//
//  Mike Coates 
//
//  version 001 initial release - 15/06/2020
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

`ifdef USE_SDRAM
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,
`endif

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);


///////// Default values for ports not used in this core /////////

assign USER_OUT = '1;

assign AUDIO_S   = 1;

assign VGA_F1    = 0;
assign VGA_SCALER= 0;

// Use in Gorf to drive rank lights (1-6 = rank lights, 7 = joystick on/off ?)
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign {FB_PAL_CLK, FB_FORCE_BLANK, FB_PAL_ADDR, FB_PAL_DOUT, FB_PAL_WR} = '0;

wire [1:0] ar = status[20:19];

assign VIDEO_ARX = (!ar) ? ((status[2])  ? 8'd4 : 8'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? ((status[2])  ? 8'd3 : 8'd4) : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"A.CRBALLOON;;",
   "OOR,CRT H adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
   "OSV,CRT V adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H0OJK,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Start 1P,Start 2P,Coin;",
	"jn,Start,Select,R;",
	"jp,Start,Select,R;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_vid;
reg  [1:0] clk_div = 2'd0;
wire cpu_clk = clk_div[1];		// 2.49675 Mhz
wire pix_clk = clk_div[0];		// 4.9935  Mhz
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),			// 39.948 Mhz
	.outclk_1(clk_sys), 			// 9.987 Mhz
	.locked(pll_locked)
);

// Divider for other clocks (7474 and 74161 on PCB)
always @(posedge clk_sys) begin
	clk_div <= clk_div + 1'b1;
end

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;
wire [15:0] joy1, joy2;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;


wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({1'd0,direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joy1),
	.joystick_1(joy2)
);


// Dip switches from MRA file
reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;



// Combined buttons
wire B1_S = joy1[4];
wire B2_S = joy1[5] | joy2[4];
wire B1_C = joy1[6];

wire B1_U = joy1[3];
wire B1_D = joy1[2];
wire B1_L = joy1[1];
wire B1_R = joy1[0];

wire B2_U = joy2[3];
wire B2_D = joy2[2];
wire B2_L = joy2[1];
wire B2_R = joy2[0];


wire hblank, vblank;
wire hs, vs;
wire [1:0] r,g,b;

wire [ 3:0] hoffset, voffset;
assign { voffset, hoffset } = status[31:24];

wire no_rotate = status[2] | direct_video;
wire rotate_ccw = 1;
screen_rotate screen_rotate (.*);

arcade_video #(260,6) arcade_video
(
	.*,

	.clk_video(clk_vid),
	.ce_pix(pix_clk),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[5:3])
);

wire [15:0] audio;
assign AUDIO_L = audio;
assign AUDIO_R = audio;

CRAZYBALLOON crazy 
(
	.O_VIDEO_R(r),
	.O_VIDEO_G(g),
	.O_VIDEO_B(b),
	.O_HSYNC(hs),
	.O_VSYNC(vs),
	.O_HBLANK(hblank),
	.O_VBLANK(vblank),
	.I_H_OFFSET(hoffset),
	.I_V_OFFSET(voffset),

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr && !ioctl_index),
	.dn_ld(ioctl_download),

	.O_AUDIO(audio),

	.dipsw1(sw[0]),
	.in0({~B2_R,~B2_L,~B2_D,~B2_U,~B1_R,~B1_L,~B1_D,~B1_U}),
	.in1({1'd0,B1_C,~B2_S,~B1_S,1'd1,1'd1,1'd1,1'd1}),
	
	.RESET(RESET | ioctl_download | status[0] | buttons[1]),
	.PIX_CLK(pix_clk),
	.CPU_CLK(cpu_clk),
	.CLK(clk_sys)
);

endmodule

