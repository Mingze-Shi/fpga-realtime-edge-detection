
/////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2013-2021 Efinix Inc. All rights reserved.
//
// Description:
// Example top file for ti60f225 dev kit OOB design
//
// Language:  Verilog 2001
//Ti60f225_sc431hai2hdmi_v6：
//使用了最新版本的framebuffer_v3;
// ------------------------------------------------------------------------------

/////////////////////////////////////////////////////////////////////////////////
//`define SOFT_TAP 1
`include "ddr3_controller/ddr3_parameter.vh"
// `include "define.v"

module ti60f225_oob_top #(

	parameter                       RANK_RATIO         = 1,       // # of unique CS outputs per rank
	parameter                       ASYN_AXI_CLK       = `ASYN_AXI_CLK, 
	parameter                       RANKS              = `RANKS,
	parameter                       CK_WIDTH           = `CK_WIDTH,       // # of CK/CK# outputs to memory   
	parameter                       CKE_WIDTH          = `CKE_WIDTH,       // # of cke outputs
	parameter                       CS_WIDTH           = `CS_WIDTH,       // # of unique CS outputs
	parameter                       BANK_WIDTH         = `BANK_WIDTH,       // # of bank bits
	parameter                       ROW_WIDTH          = `ROW_WIDTH,       // DRAM address bus width
	parameter                       COL_WIDTH          = `COL_WIDTH,      // column address width
	parameter                       DM_WIDTH           = `DM_WIDTH,       // # of DM (data mask)
	parameter                       DQS_WIDTH          = `DQS_WIDTH,       // # of DQS (strobe)
	parameter                       DQ_WIDTH           = `DQ_WIDTH,      // # of DQ (data)
	parameter                       ODT_WIDTH          = `ODT_WIDTH,
	parameter                       DQ_CNT_WIDTH       = `DQ_CNT_WIDTH,       // = ceil(log2(DQ_WIDTH))
	parameter                       DQS_CNT_WIDTH      = `DQS_CNT_WIDTH,       // = ceil(log2(DQS_WIDTH))  
	parameter                       DRAM_WIDTH         = `DRAM_WIDTH,       // # of DQ per DQS   
	parameter                       DATA_WIDTH         = `DATA_WIDTH,
	parameter                       ADDR_WIDTH         = `ADDR_WIDTH,    
	parameter                       AXI_ID_WIDTH       = `AXI_ID_WIDTH,
	parameter                       AXI_ADDR_WIDTH     = `AXI_ADDR_WIDTH,
	parameter                       AXI_DATA_WIDTH     = `AXI_DATA_WIDTH
)
(

  (* syn_peri_port = 0 *) input jtag_inst1_CAPTURE,
  (* syn_peri_port = 0 *) input jtag_inst1_DRCK,
  (* syn_peri_port = 0 *) input jtag_inst1_RESET,
  (* syn_peri_port = 0 *) input jtag_inst1_RUNTEST,
  (* syn_peri_port = 0 *) input jtag_inst1_SEL,
  (* syn_peri_port = 0 *) input jtag_inst1_SHIFT,
  (* syn_peri_port = 0 *) input jtag_inst1_TCK,
  (* syn_peri_port = 0 *) input jtag_inst1_TDI,
  (* syn_peri_port = 0 *) input jtag_inst1_TMS,
  (* syn_peri_port = 0 *) input jtag_inst1_UPDATE,
  (* syn_peri_port = 0 *) output jtag_inst1_TDO,

   //Clocks 
	input	wire	KEY0_N,
    input wire KEY1_N,
    input wire KEY2_N,
    input wire KEY3_N,
    input	wire	i_mipi_rx_pclk,
    input wire  vid_clk_dvi2,
    input wire hdmi_tx_slow_clk,
    input wire CLK_5M,
    input  wire CLK_25M,
	output  wire    pll_inst1_RSTN,
	input	wire	i_pll_locked,
	input 	wire  	pll_locked,
	output  wire    pll_inst4_RSTN,
	input   wire    pll_inst4_LOCKED,
	output  wire  	USER_PLL_RSTN,
    output 	wire 	DDR3_PLL_RSTN,
	input 	wire  	user_pll_locked,
    //CSI Interface
    input	 wire		io_cam_sda_IN,
    output wire   io_cam_sda_OUT,
    output wire		io_cam_sda_OE,

    output io_cam_scl_OUT,
    input io_cam_scl_IN,
    output io_cam_scl_OE,

    output	wire		Sensor_RST,
    
    input	wire		i_cam_ck_LP_P_IN,
    input	wire		i_cam_ck_LP_N_IN,
    output	wire		o_cam_ck_HS_TERM,
    output	wire		o_cam_ck_HS_ENA,
    input	wire		i_cam_ck_CLKOUT,
    
    input	wire	[7:0]			cam_d0_HS_IN,
    input	  wire		      cam_d0_LP_P_IN,
    input	  wire		      cam_d0_LP_N_IN,
    output	wire		      cam_d0_HS_TERM,
    output	wire		      cam_d0_HS_ENA,
    output	wire		      cam_d0_RST,
    output	wire		      cam_d0_FIFO_RD,
    input	  wire		      cam_d0_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d1_HS_IN,
    input	  wire		        cam_d1_LP_P_IN,
    input	  wire		        cam_d1_LP_N_IN,
    output	wire		        cam_d1_HS_TERM,
    output	wire		        cam_d1_HS_ENA,
    output	wire		        cam_d1_RST,
    output	wire		        cam_d1_FIFO_RD,
    input	  wire		        cam_d1_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d2_HS_IN,
    input	  wire		        cam_d2_LP_P_IN,
    input	  wire		        cam_d2_LP_N_IN,
    output	wire		        cam_d2_HS_TERM,
    output	wire		        cam_d2_HS_ENA,
    output	wire		        cam_d2_RST,
    output	wire		        cam_d2_FIFO_RD,
    input	  wire		        cam_d2_FIFO_EMPTY,  
   
    input 	wire	[7:0]			cam_d3_HS_IN,
    input	  wire		        cam_d3_LP_P_IN,
    input	  wire		        cam_d3_LP_N_IN,
    output	wire		        cam_d3_HS_TERM,
    output	wire		        cam_d3_HS_ENA,
    output	wire		        cam_d3_RST,
    output	wire		        cam_d3_FIFO_RD,
    input	  wire		        cam_d3_FIFO_EMPTY,

	
	input 					tx_cal_clk_90edge,
  	input 					rx_cal_clk,
  	input 					tx_cal_clk,
	input                              core_clk,     // CORE CLK @ 100MHz
	input                              sdram_clk,    // SDRAM CK @ 400MHz
	// PLL status flags  
	output [2:0]                       pll_shift,  
	output [4:0]                       pll_shift_sel,
	output                             pll_shift_ena,  
	// memory interface ports
	output                             ddr_ck_hi,
	output                             ddr_ck_lo,
	output                             ddr_reset_n,
	output [CKE_WIDTH-1:0]             ddr_cke,     
	output [ROW_WIDTH-1:0]             ddr_addr,
	output [BANK_WIDTH-1:0]            ddr_ba,
	output                             ddr_cas_n,
 
	output [CS_WIDTH*RANK_RATIO-1:0]   ddr_cs_n,
	output                             ddr_ras_n,
	output                             ddr_we_n,
	
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_hi,
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_lo,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_hi,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_lo,
	
	output [DQS_WIDTH-1:0]             ddr_dqs_oe,
	output [DQS_WIDTH-1:0]             ddr_dqs_oe_n,
	output [DQ_WIDTH-1:0]              ddr_dq_oe,  
	output [DQS_WIDTH-1:0]             ddr_dqs_out_hi,
	output [DQS_WIDTH-1:0]             ddr_dqs_out_lo,
	output [DQ_WIDTH-1:0]              ddr_dq_out_hi,
	output [DQ_WIDTH-1:0]              ddr_dq_out_lo,
	output [DM_WIDTH-1:0]              ddr_dm_hi,
	output [DM_WIDTH-1:0]              ddr_dm_lo,
	output [ODT_WIDTH-1:0]             ddr_odt,

       //LED
       output [7:0] led,

       // hdmi interface

    output tmds_tx_clk_TX_OE,
    output [9:0] tmds_tx_clk_TX_DATA,
    output tmds_tx_clk_TX_RST,
    output tmds_tx_data0_TX_OE,
    output [9:0] tmds_tx_data0_TX_DATA,
    output tmds_tx_data0_TX_RST,
    output tmds_tx_data1_TX_OE,
    output [9:0] tmds_tx_data1_TX_DATA,
    output tmds_tx_data1_TX_RST,
    output tmds_tx_data2_TX_OE,
    output [9:0] tmds_tx_data2_TX_DATA,
    output tmds_tx_data2_TX_RST


);

function integer log2;
	input	integer	val;
	integer	i;
	begin
		log2 = 0;
		for (i=0; 2**i<val; i=i+1)
			log2 = i+1;
	end
endfunction


//===============================================================================
//localparam
//===============================================================================
localparam WR_FIFO_DEPTH  = 1024;
localparam RD_FIFO_DEPTH  = 1024;

// localparam	MAX_HRES		= 12'd1920;
// localparam	MAX_VRES		= 12'd1080;
// localparam	HSP			= 8'd2;
// localparam	HBP			= 8'd88;
// localparam	HFP			= 8'd120;
// localparam	VSP			= 8'd2;
// localparam	VBP			= 8'd20;
// localparam	VFP			= 8'd20;

localparam HACT     = 1920;
localparam HFP      = 88;
localparam HSP      = 44;
localparam HBP      = 148;

localparam VACT     = 1080;
localparam VFP      = 4;
localparam VSP      = 5;
localparam VBP      = 36;
//===============================================================================
//signal
//===============================================================================
   
wire                              app_sr_active;
wire                              app_ref_ack;
wire                              app_zq_ack;
wire                              cal_done;

// Slave Interface Write Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_awid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_awaddr;
wire [7:0]                        s_axi_awlen;
wire [2:0]                        s_axi_awsize;
wire [1:0]                        s_axi_awburst;
wire [0:0]                        s_axi_awlock;
wire [3:0]                        s_axi_awcache;
wire [2:0]                        s_axi_awprot;
wire                              s_axi_awvalid;
wire                              s_axi_awready;
// Slave Interface Write Data Ports
wire [AXI_DATA_WIDTH-1:0]         s_axi_wdata;
wire [(AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb;
wire                              s_axi_wlast;
wire                              s_axi_wvalid;
wire                              s_axi_wready;
// Slave Interface Write Response Ports
wire                              s_axi_bready;
wire [AXI_ID_WIDTH-1:0]           s_axi_bid;
wire [1:0]                        s_axi_bresp;
wire                              s_axi_bvalid;
// Slave Interface Read Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_arid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_araddr;
wire [7:0]                        s_axi_arlen;
wire [2:0]                        s_axi_arsize;
wire [1:0]                        s_axi_arburst;
wire [0:0]                        s_axi_arlock;
wire [3:0]                        s_axi_arcache;
wire [2:0]                        s_axi_arprot;
wire                              s_axi_arvalid;
wire                              s_axi_arready;
// Slave Interface Read Data Ports
wire                              s_axi_rready;
wire [AXI_ID_WIDTH-1:0]           s_axi_rid;
wire [AXI_DATA_WIDTH-1:0]         s_axi_rdata;
wire [1:0]                        s_axi_rresp;
wire                              s_axi_rlast;
wire                              s_axi_rvalid;




////////////////////////////////////////////////////////////////
// System & Debugger
wire    w_arstn;
// wire	w_sysclk_mcu_arstn;
// wire	w_sysclk_mcu_arst;
wire	w_mipi_rx_pclk_arstn;
wire	w_mipi_rx_pclk_arst;

wire		       w_mipi_rx_vs;
wire		       w_mipi_rx_hs;
wire	       w_mipi_rx_de;
wire	[63:0]			w_mipi_rx_data	;

wire					io_systemReset;



//===================================================================================================
//reset module
//===================================================================================================

assign w_arstn = KEY0_N & i_pll_locked & pll_locked & user_pll_locked;
assign pll_inst1_RSTN  		= KEY0_N;
assign USER_PLL_RSTN      		= KEY0_N;
assign DDR3_PLL_RSTN 		= KEY0_N;
assign pll_inst4_RSTN = KEY0_N;
reset_ctrl
#(
	.NUM_RST		(2),
	.CYCLE			(1),
	.IN_RST_ACTIVE	(4'b00),
	.OUT_RST_ACTIVE	(4'b10)
)
inst_reset_ctrl
(
	.i_arst		({2{w_arstn}}),//({{4{i_pll_locked}},                  {2{KEY0_N}}}),
	.i_clk			({2{i_mipi_rx_pclk}}),
	.o_srst		({w_mipi_rx_pclk_arst, w_mipi_rx_pclk_arstn})
);



reg [25:0] cnt = 'd0;
always @( posedge core_clk)
begin 
       cnt <= cnt + 1'b1;
end
assign led[0]  = cal_done ? cnt[24] : 1'b0;

//========================================================================================================
//MIPI RX
//========================================================================================================
wire i_mipi_clk ;
assign i_mipi_clk = core_clk;

		assign	cam_d0_RST		= 1'b0;
		assign	cam_d1_RST		= 1'b0;
		assign  cam_d2_RST = 1'b0;
    assign  cam_d3_RST = 1'b0;
	
wire [31:0] mipi_debug_out;
		

		csi_rx_controller inst_efx_csi2_rx
		(
              .reset_n			(KEY0_N),
              .clk				(i_mipi_clk),
              .reset_byte_HS_n	(KEY0_N),
              .clk_byte_HS		  (i_cam_ck_CLKOUT),
              .reset_pixel_n		(w_mipi_rx_pclk_arstn),
              .clk_pixel			  (i_mipi_rx_pclk),
              
              .Rx_LP_CLK_P		  (i_cam_ck_LP_P_IN),
              .Rx_LP_CLK_N		  (i_cam_ck_LP_N_IN),
              .Rx_HS_enable_C		(o_cam_ck_HS_ENA),
              .LVDS_termen_C		(o_cam_ck_HS_TERM),
              
              .Rx_LP_D_P			({cam_d3_LP_P_IN, cam_d2_LP_P_IN, cam_d1_LP_P_IN, cam_d0_LP_P_IN}),//(r_mipi_rx_data_LP_P_IN_2P),
              .Rx_LP_D_N			({cam_d3_LP_N_IN, cam_d2_LP_N_IN, cam_d1_LP_N_IN, cam_d0_LP_N_IN}),//(r_mipi_rx_data_LP_N_IN_2P),
              .Rx_HS_D_0			(cam_d0_HS_IN),//(r_mipi_rx_data_HS_IN_2P[0*8+:8]),
              .Rx_HS_D_1			(cam_d1_HS_IN),//(r_mipi_rx_data_HS_IN_2P[1*8+:8]),
              .Rx_HS_D_2			(cam_d2_HS_IN),
              .Rx_HS_D_3			(cam_d3_HS_IN),
              .Rx_HS_D_4 (8'b0),
              .Rx_HS_D_5 (8'b0),
              .Rx_HS_D_6 (8'b0),
              .Rx_HS_D_7 (8'b0),
              .Rx_HS_enable_D		({cam_d3_HS_ENA    ,cam_d2_HS_ENA    ,cam_d1_HS_ENA    ,cam_d0_HS_ENA    }),//( w_cam_d_HS_ENA),
              .LVDS_termen_D		({cam_d3_HS_TERM   ,cam_d2_HS_TERM   ,cam_d1_HS_TERM   ,cam_d0_HS_TERM   }),
              .fifo_rd_enable		({cam_d3_FIFO_RD   ,cam_d2_FIFO_RD   ,cam_d1_FIFO_RD   ,cam_d0_FIFO_RD   }),
              .fifo_rd_empty		({cam_d3_FIFO_EMPTY,cam_d2_FIFO_EMPTY,cam_d1_FIFO_EMPTY,cam_d0_FIFO_EMPTY}),
              .DLY_enable_D		       (),
              .DLY_inc_D			(),
															.u_dly_enable_D		(4'b0000),
              .u_dly_inc_D		       (),
              
              .axi_clk			(1'b0),
              .axi_reset_n		       (1'b0),
              .axi_awaddr			(6'b0),
              .axi_awvalid		       (1'b0),
              .axi_awready		       (),
              .axi_wdata			(32'b0),
              .axi_wvalid			(1'b0),
              .axi_wready			(),
              
              .axi_bvalid			(),
              .axi_bready			(1'b0),
              .axi_araddr			(6'b0),
              .axi_arvalid		       (1'b0),
              .axi_arready		       (),
              .axi_rdata			(),
              .axi_rvalid			(),
              .axi_rready			(1'b1),
              
              .hsync_vc0			(w_mipi_rx_hs),
              .hsync_vc1			(),
              .hsync_vc2			(),
              .hsync_vc3			(),
              .vsync_vc0			(w_mipi_rx_vs),
              .vsync_vc1			(),
              .vsync_vc2			(),
              .vsync_vc3			(),
              .vc				(),
              .word_count			(),
              .shortpkt_data_field        (),
              .datatype			(),
              .pixel_per_clk		(),
              .pixel_data			(w_mipi_rx_data),
              .pixel_data_valid	       (w_mipi_rx_de),
              .irq				(),
              .mipi_debug_out(mipi_debug_out)
		);

//     wire		       w1_mipi_rx_vs;
// wire		       w1_mipi_rx_hs;
// wire	       w1_mipi_rx_de;
// wire	[39:0]			w1_mipi_rx_data	;
// sensor_clipper  sensor_clipper_inst (
//     .clk(i_mipi_rx_pclk),
//     .i_vs(w_mipi_rx_vs),
//     .i_hs(w_mipi_rx_hs),
//     .i_de(w_mipi_rx_de),
//     .i_dat(w_mipi_rx_data[39:0]),

//     .o_hs(w1_mipi_rx_hs),
//     .o_vs(w1_mipi_rx_vs),
//     .o_de(w1_mipi_rx_de),
//     .o_dat(w1_mipi_rx_data)
   
//   );


wire mdebug_pixel_fifo_full     = mipi_debug_out[0] ;
wire mdebug_pixel_fifo_empty    = mipi_debug_out[1] ;
wire mdebug_crc_error           = mipi_debug_out[2] ;
wire mdebug_ecc_1bit_error      = mipi_debug_out[3] ;
wire mdebug_ecc_2bit_error      = mipi_debug_out[4] ;
wire mdebug_undersize_pkt_error = mipi_debug_out[5] ;
wire mdebug_line_vc0_error      = mipi_debug_out[6] ;
wire mdebug_frame_vc0_error    = mipi_debug_out[10];   
wire mdebug_receive_error      = mipi_debug_out[14];


//========================================================================================================
//
//========================================================================================================
		

//*************** imx219 config********************/
// mipi_config_imx219_top u_config_imx219(
// 										.i_sys_clk(CLK_5M)    	,    /////48M 
// 										.sys_rstn(vid_rst_n )    ,
// 										.o_sen_rst_n(o_cam_rstn)  	,
										
										// .o_iic_sda_OE(io_cam_sda_OE) ,
										// .i_iic_sda(io_cam_sda_IN)   	,
										// .o_iic_sda(io_cam_sda_OUT)   	,
										// .o_iic_scl(io_cam_scl)    	
										// ); 	

wire scl_padoen_o;
wire sda_padoen_o;


reg [15:0] i2c_rst_cnt = '0;

always @( posedge CLK_5M or negedge w_arstn )
begin
    if( !w_arstn )
       i2c_rst_cnt <= 'd0;
    else 
       i2c_rst_cnt <= i2c_rst_cnt[15] ? i2c_rst_cnt : i2c_rst_cnt + 1'b1;
end
wire i2c_rst_n = i2c_rst_cnt[15];

i2c_master_ctrl_top u2_i2c_master_ctrl_top(
  /*i*/.clk			(CLK_5M		),
  /*i*/.rst_n			(i2c_rst_n		),
  /*i*/.scl_pad_i     (io_cam_scl_IN),//(1'b1),
  /*o*/.scl_pad_o     (io_cam_scl_OUT),
  /*o*/.scl_padoen_o  (scl_padoen_o),
  /*i*/.sda_pad_i     (io_cam_sda_IN),
  /*o*/.sda_pad_o     (io_cam_sda_OUT),
  /*o*/.sda_padoen_o  (sda_padoen_o)
  
  );
assign Sensor_RST = ~w_arstn;
assign io_cam_scl_OE = ~scl_padoen_o;
assign io_cam_sda_OE = ~sda_padoen_o;

//=====================================================================================
//frame buffer
//=====================================================================================
wire [7:0] 	ch0_r;
wire [15:0]    rawdata_2pix;
wire [7:0]    ch0_b;
assign ch0_b = 8'b0;
wire ch0_vs;
wire ch0_hs;
wire ch0_de;

wire  [16-1:0] m_axis_tdata;
wire           m_axis_tvalid;
wire           m_axis_tready;
wire           m_axis_tlast;
wire           m_axis_tuser;
wire  fifo_rd_period;
wire freeze_requested;
wire compare_request;
wire replay_requested,freeze_ack,replay_ack;
wire [5:0] replay_select,replay_selection_ack;
// IMX219
  frame_buffer #(
.I_VID_WIDTH         (32),
.O_VID_WIDTH         (16),
.START_ADDR          (32'h00000        ),
.AXI_DATA_WIDTH      ( AXI_DATA_WIDTH	),
.AXI_ADDR_WIDTH      ( AXI_ADDR_WIDTH	),
.WR_FIFO_DEPTH	      ( 1024		),    
.RD_FIFO_DEPTH 	      ( 1024 	),
.BURST_LEN  	        (127),
.FB_NUM                 (64),
.REPLAY_FRAMES(60),
.REPLAY_ENABLE        (1),
.MAX_VID_WIDTH	      (960) ,
.MAX_VID_HIGHT	      (1080),
.O_FRAME_WIDTH      (960),
.O_FRAME_HEIGHT     (1080)

)checker0(
       .axi_clk		(core_clk 	        ),
       .rst_n			(vid_rst_n   ),
       .freeze_request (freeze_requested),
       .replay_request(replay_requested),.replay_select(replay_select),
       .split_request(compare_request),
       .freeze_active(freeze_ack),.replay_ready(replay_ack),.replay_select_ack(replay_selection_ack),

/*i*/.i_clk			(i_mipi_rx_pclk      ),
/*i*/.i_vs			(w_mipi_rx_vs	),
/*i*/.i_de			(w_mipi_rx_de & w_mipi_rx_hs	),
/*i*/.vin 			({w_mipi_rx_data[9:2],w_mipi_rx_data[19:12],w_mipi_rx_data[29:22],w_mipi_rx_data[39:32]}	),
                     
/*i*/.o_clk			(vid_clk_dvi2),//(i_mipi_rx_pclk	),                  
/*i*/.fifo_rd_period(fifo_rd_period),//(fifo_rd_period  ),

    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tuser  (m_axis_tuser),
    .m_axis_tlast  (m_axis_tlast),
	

       .awid			(s_axi_awid	),      
       .awaddr		(s_axi_awaddr	),
       .awlen			(s_axi_awlen	),
       .awsize		(s_axi_awsize	),
       .awburst		(s_axi_awburst),
       .awprot    (s_axi_awprot ),
       .awcache   (s_axi_awcache),
       .awlock		(s_axi_awlock	),
       .awvalid		(s_axi_awvalid),
       .awready		(s_axi_awready),

       .arid			(s_axi_arid	  ),
       .araddr		(s_axi_araddr	),
       .arlen			(s_axi_arlen	),
       .arsize		(s_axi_arsize	),
       .arburst 	(s_axi_arburst),

       .arprot    (s_axi_arprot ),
       .arcache   (s_axi_arcache),
       .arlock 		(s_axi_arlock	),
       .arvalid		(s_axi_arvalid),
       .arready		(s_axi_arready),

       .wdata			(s_axi_wdata	),
       .wstrb			(s_axi_wstrb	),
       .wlast			(s_axi_wlast	),
       .wvalid		(s_axi_wvalid	),
       .wready		(s_axi_wready	),


       .rid			  (s_axi_rid	),
       .rdata			(s_axi_rdata	),
       .rlast			(s_axi_rlast	),
       .rvalid 		(s_axi_rvalid	),
       .rready		(s_axi_rready	),
       .rresp			(s_axi_rresp	),

       .bid			  (s_axi_bid	),
       .bvalid		(s_axi_bvalid	),
       .bready	  (s_axi_bready	)
);

		    
		    
cvo_axi # (
    .SYMBOL_WIDTH(8),
    .SYMBOL_NUM(1),
    .PIXEL_NUM(2),
    .HSYNC_POL(1),
    .VSYNC_POL(1),
    .FIFO_DEPTH(1024),
    .FIFO_ALMOST_FULL(1000),
    .MAX_H_VALID(1920),
    .MAX_V_VALID(1080)
  )
  cvo_axi_inst (
    .o_clk          (vid_clk_dvi2   ),
    .rst_n          (vid_rst_n      ),
    .fifo_rd_period (fifo_rd_period ),
    .s_axi_clk      (vid_clk_dvi2   ),
    .s_axis_tdata   (m_axis_tdata   ),
    .s_axis_tvalid  (m_axis_tvalid  ),
    .s_axis_tready  (m_axis_tready  ),
    .s_axis_tlast   (m_axis_tlast   ),
    .s_axis_tuser   (m_axis_tuser   ),
    .H_FRONT_PORCH  (HFP            ),
    .H_SYNC         (HSP            ),
    .H_VALID        (HACT           ),
    .H_BACK_PORCH   (HBP            ),
    .V_FRONT_PORCH  (VFP            ),
    .V_SYNC         (VSP            ),
    .V_VALID        (VACT           ),
    .V_BACK_PORCH   (VBP            ),
     .vout          ({rawdata_2pix}  ),
    .o_hs           (ch0_hs         ),
    .o_vs           (ch0_vs         ),
    .o_de           (ch0_de         )
  );		       


ddr3_top                 u_ddr3_top
(

.axi_clk                (core_clk            ),
.core_clk               (core_clk            ),
.sdram_clk              (sdram_clk           ),  
.rx_cal_clk             (rx_cal_clk          ),
.tx_cal_clk             (tx_cal_clk          ),
.tx_cal_clk_90edge      (tx_cal_clk_90edge   ),
.rstn                   (w_arstn             ),      
.pll_shift              (pll_shift           ),
.pll_shift_sel          (pll_shift_sel       ),
.pll_shift_ena          (pll_shift_ena       ),       
///////////////DDR BUS
.ddr_ck_hi              (ddr_ck_hi           ),
.ddr_ck_lo              (ddr_ck_lo           ),
.ddr_cke                (ddr_cke             ),    
.ddr_reset_n            (ddr_reset_n         ),
.ddr_cs_n               (ddr_cs_n            ),
.ddr_ras_n              (ddr_ras_n           ),
.ddr_cas_n              (ddr_cas_n           ),
.ddr_we_n               (ddr_we_n            ),     
.ddr_addr               (ddr_addr            ),
.ddr_ba                 (ddr_ba              ),

.ddr_dqs_oe             (ddr_dqs_oe          ),
.ddr_dqs_oe_n           (ddr_dqs_oe_n        ),
.ddr_dq_oe              (ddr_dq_oe           ),
.ddr_dqs_in_hi          (ddr_dqs_in_hi       ),
.ddr_dqs_in_lo          (ddr_dqs_in_lo       ),
.ddr_dq_in_hi           (ddr_dq_in_hi        ),
.ddr_dq_in_lo           (ddr_dq_in_lo        ),

.ddr_dqs_out_hi         (ddr_dqs_out_hi      ),
.ddr_dqs_out_lo         (ddr_dqs_out_lo      ),
.ddr_dq_out_hi          (ddr_dq_out_hi       ),
.ddr_dq_out_lo          (ddr_dq_out_lo       ),

.ddr_dm_hi              (ddr_dm_hi           ),
.ddr_dm_lo              (ddr_dm_lo           ),
.ddr_odt                (ddr_odt             ),

// Application interface ports
.app_sr_req                     (1'b0),
.app_ref_req                    (1'b0),
.app_zq_req                     (1'b0),
.app_sr_active                  (app_sr_active),
.app_ref_ack                    (app_ref_ack),
.app_zq_ack                     (app_zq_ack),

// Slave Interface Write Address Ports
.s_axi_awid                     (s_axi_awid        ),
.s_axi_awaddr                   (s_axi_awaddr      ),
.s_axi_awlen                    (s_axi_awlen       ),
.s_axi_awsize                   (s_axi_awsize      ),
.s_axi_awburst                  (s_axi_awburst     ),
.s_axi_awlock                   (s_axi_awlock      ),
.s_axi_awcache                  (s_axi_awcache     ),
.s_axi_awprot                   (s_axi_awprot      ),
.s_axi_awqos                    (4'h0              ),
.s_axi_awvalid                  (s_axi_awvalid     ),
.s_axi_awready                  (s_axi_awready     ),
// Slave Interface Write Data Ports
.s_axi_wdata                    (s_axi_wdata       ),
.s_axi_wstrb                    (s_axi_wstrb       ),
.s_axi_wlast                    (s_axi_wlast       ),
.s_axi_wvalid                   (s_axi_wvalid      ),
.s_axi_wready                   (s_axi_wready      ),
// Slave Interface Write Response Ports
.s_axi_bid                      (s_axi_bid         ),
.s_axi_bresp                    (s_axi_bresp       ),
.s_axi_bvalid                   (s_axi_bvalid      ),
.s_axi_bready                   (s_axi_bready      ),
// Slave Interface Read Address Ports
.s_axi_arid                     (s_axi_arid        ),
.s_axi_araddr                   (s_axi_araddr      ),
.s_axi_arlen                    (s_axi_arlen       ),
.s_axi_arsize                   (s_axi_arsize      ),
.s_axi_arburst                  (s_axi_arburst     ),
.s_axi_arlock                   (s_axi_arlock      ),
.s_axi_arcache                  (s_axi_arcache     ),
.s_axi_arprot                   (s_axi_arprot      ),
.s_axi_arqos                    (4'h0              ),
.s_axi_arvalid                  (s_axi_arvalid     ),
.s_axi_arready                  (s_axi_arready     ),
// Slave Interface Read Data Ports
.s_axi_rid                      (s_axi_rid         ),
.s_axi_rdata                    (s_axi_rdata       ),
.s_axi_rresp                    (s_axi_rresp       ),
.s_axi_rlast                    (s_axi_rlast       ),
.s_axi_rvalid                   (s_axi_rvalid      ),
.s_axi_rready                   (s_axi_rready      ),
//DEBUG       
.wrlvl_dq_check                 (wrlvl_dq_check    ) ,
.rd_level_dqs_check             (rd_level_dqs_check) ,
.init_cur_state                 (init_cur_state    ) ,
.idelay_ld                      (idelay_ld         ) ,
.mpr_rdlvl_dly                  (mpr_rdlvl_dly     ) ,
.cal_done                       (cal_done          ) 
);

//***************************************************************************
// debayer
//***************************************************************************


wire        rgb_vs;
wire        rgb_hs;
wire        rgb_de;
wire        rgb_valid;
wire [47:0] rgb_datax2;

// rgb_sharpen -> rgb_ccm -> rgb_saturate 之间的中间信号。
// 拆成 shp_* / ccm_* / rgb_* 三级是为了让下游的 hdmi_tx_* 消费块一行都不用改:
// 消费块看到的输入名还是 rgb_*, 只是驱动者从 rgb_sharpen 换成了 rgb_saturate。
wire        shp_vs;
wire        shp_hs;
wire        shp_de;
wire        shp_valid;
wire [47:0] shp_datax2;

// rgb_ccm 的输出 —— 只在 rgb_ccm 与 rgb_saturate 之间走线
wire        ccm_vs;
wire        ccm_hs;
wire        ccm_de;
wire        ccm_valid;
wire [47:0] ccm_datax2;

wire [15:0] r_gain;
wire [15:0] g_gain;
wire [15:0] b_gain;

//***************************************************************************
// RAW 域黑电平校正 (Black Level Correction)
//   详见 rtl/debayer/raw_data_blc.v 文件头。要点:
//     - 位置必须在 debayer / 白平衡增益之前
//     - 零延迟组合逻辑, 不改变标志与数据的相对拍数
//
//   *** P_BLACK 由 20 改成 17 (2026-10-06), 这是"黑处红色噪点"的根治 ***
//   病因: 20 比真实基底高约 3 级, 最先被打死的是 B 通道 —— 它本来信号最小,
//   减掉一个偏大的常数后直接归零。用当天抓的 rawdata.hex 实测 (最暗 8% 的块):
//     减 20: 编码域 R/G/B = 25.7 / 22.1 / 0.3    <- B 整体为 0
//     减 17: 编码域 R/G/B = 38.9 / 41.7 / 13.9   <- B 回来了
//   B 归零的后果是暗部变成"暗红/暗黄": R/G 还有二十几级信号, B 却是 0, 于是
//   R 与 G 各自的噪声 (经 gamma 底部约 15 级/线性级的斜率放大) 直接表现为
//   红绿颗粒 —— 这就是用户看到的"黑的地方出现红色噪点"。改 17 后暗部块内的
//   红点率由 0.218% 降到 0.046%。
//
//   17 的依据是**结构性、跨帧稳定**的: 该帧最暗块的码值直方图是
//     16:72   17:1820   18:676   19:15   (16 以下一个像素都没有)
//   16 是硬地板 (传感器基底的下边界), 17 是众数, 取 17。
//
//   *** 与 isp_matlab 的 P.BLACK = 20 已经不一致 ***
//   isp_build_params.m:21 写的是 20, 注释"实测该 sensor 最低 21"是**上一帧**的
//   观察 —— 那一帧大概没有真正的全黑区, 于是把最暗的场景内容 21 当成了基底。
//   跑 MATLAB 定点模型与 RTL 的逐位对拍之前, 必须把 isp_build_params.m 的
//   P.BLACK 也改成 17 (isp_core.m:37 / verify_isp_chain.m:74 会跟着走),
//   否则两边从第一级就开始漂。
//
//   注意 .i_data 的字节交换要跟原来喂给 debayer 的写法保持一致,
//   BLC 只是把两个字节各减一次, 与字节序无关, 但下游约定不能变。
//***************************************************************************
wire        blc_vs;
wire        blc_hs;
wire        blc_de;
wire        blc_valid;
wire [15:0] blc_rawdata;

raw_data_blc # (
    .P_DEPTH(8),
    .P_BLACK(8'd17)
  )
  raw_data_blc_inst (
    .i_vs     (ch0_vs                                ),
    .i_hs     (ch0_hs                                ),
    .i_de     (ch0_de                                ),
    .i_valid  (ch0_de                                ),  // 与 .raw_valid_i 同源
    .i_data   ({rawdata_2pix[7:0],rawdata_2pix[15:8]}),
    .o_vs     (blc_vs                                ),
    .o_hs     (blc_hs                                ),
    .o_de     (blc_de                                ),
    .o_valid  (blc_valid                             ),
    .o_data   (blc_rawdata                           )
  );

//***************************************************************************
// RAW 域同色保边降噪 (NR)
//   详见 rtl/isp/raw_nr_top.v 文件头。要点:
//     - 位置在 BLC 之后、debayer/WB 之前: 本工程 WB 是 demosaic 之后的 RGB 域
//       增益, 所以这里的噪声幅度是传感器原生单位, 阈值可以是一个常数。
//     - 算法不含在 raw_nr_top 里, 它只是协议适配层; 真正的窗口和算法
//       (isp_line_window.v / isp_dpc_nr.v) 是逐字复用的既有模块, 与
//       isp_matlab/isp_core.m 逐位对齐过。
//     - 本轮 DPC 关闭 (P_DPC_TH = 16'hFFFF), 只要降噪。
//     - 本模块把画面整体推迟 2 行 + 4 拍, vs/hs/de/valid 与数据一起平移,
//       相对关系不变, debayer 内部的错拍标定 (SKIP_WORDS/SKIP_LINES) 继续成立。
//***************************************************************************
wire        nr_vs;
wire        nr_hs;
wire        nr_de;
wire        nr_valid;
wire [15:0] nr_rawdata;
wire        nr_bypass;
raw_nr_top # (
    // .P_BYPASS   (0      ),
    // P_NR_TH: 邻居相似度阈值 (RAW 8bit LSB)。邻居与中心相差 <= TH 才参与加权平均,
    //   否则用中心顶替; 外加一道强边缘否决 P_NR_EDGE。
    //   *** 算法已于 2026-10-07 改过, 不再是"5 样本跨度 <= TH"的二值门控 ***
    //   实测 (rawdata.hex, 1920x1080 真实拍摄, 全帧 sigma = 1.33 LSB):
    //     旧版 TH=3          -> 改动 22.8% 像素, 强边缘(rng>=30) 0.00% 被改
    //     新版 TH=3 + EDGE=16 -> 改动 44.5%,      强边缘 0.00% 被改
    //     加噪恢复 RMSE: sigma=1 时 0.918 (旧 1.000);
    //                    sigma=2 时 1.801 (旧 1.997);  sigma=3 时 2.876 (旧 3.006)
    //   *** TH 不要往上调 ***: TH=6 在低噪声下**反而更差** (sigma=1 时 1.014 差于
    //   旧版 0.925), 因为它会把真实细节当成"相似邻居"一起平均掉。
    //   *** TH 的有效上界是 1023 *** —— 门控比较的是两个 10 位值之差。曾经误设成
    //   3000 让门控恒真 = 满强度 NR 作用于 100% 像素, 强边缘 87.8% 被改, 那就是
    //   当时"开 NR 反而画面变差"的病因。
    //   *** 正确预期仍然是"看不出效果" ***: sigma 只有 1.33 LSB, 净收益约 0.1 LSB,
    //   8 位显示上不可见。它在这里的作用是"不添乱", 不是"降噪"。想要可见的降噪
    //   要么上层域(经 WB/gamma 后幅度被放大的地方), 要么时域多帧 —— 都要另做。
    //   *** 不要照抄 isp_params.vh 的 21/23/45 *** —— 那是兄弟工程 AWB 域的值
    //   (已乘过白平衡增益), 拿到这里会把整幅抹平。详见 raw_nr_top.v 文件头。
    .P_NR_TH    (16'd3   ),
    // P_NR_EDGE: 强边缘否决门限。5 个十字样本极差 > 它则整像素原样输出。
    //   这道必须有 —— 光靠逐邻居相似度, 边缘斜坡上的侧向邻居仍会被放进来平均,
    //   抹掉 1~2 LSB。实测没有它时 TH=3 改 4.1% 的强边缘、TH=6 改 27.8%;
    //   16 是实测最优点(再小 8/12 会在高噪声下误伤平坦区, 再大 24/30 否决失效)。
    .P_NR_EDGE  (16'd16  ),
    .P_DPC_TH   (16'hFFFF)      // 关。实测全帧无坏点: max(ce-邻居极值)=26,
                                // 任何 >=27 的阈值都 0 触发; 而降到能触发的
                                // 24/16 改的是文字边缘本身, 只会把字抹糊。
  )
  raw_nr_top_inst (
    .i_pclk   (vid_clk_dvi2),
    .i_arstn  (vid_rst_n   ),
    .P_BYPASS (nr_bypass   ),
    .i_vs     (blc_vs      ),
    .i_hs     (blc_hs      ),
    .i_valid  (blc_valid   ),
    .i_data   (blc_rawdata ),
    .o_vs     (nr_vs       ),
    .o_hs     (nr_hs       ),
    .o_de     (nr_de       ),
    .o_valid  (nr_valid    ),
    .o_data   (nr_rawdata  )
  );

// debayer 的原始输出 -> 锐化模块的输入 (必须在下面用之前声明, 否则会被当成
// 隐式线网再和显式声明撞车)
wire        db_vs;
wire        db_hs;
wire        db_de;
wire        db_valid;
wire [47:0] db_datax2;

// 数字曝光档位: 由 u_camera_sobel 在模式 1 下用 SW1/SW2 调节。
//   档 1: 白平衡增益整体减半 —— 作用在线性域、gamma 之前, 高光还有救;
//   档 2/3: 再叠加输出端右移 1/2 位, 合计约 1/4 与 1/8。
wire [1:0] expo_shift;
wire       expo_pre  = |expo_shift;
wire [1:0] expo_post = (expo_shift<=2'd1) ? 2'd0 : expo_shift-2'd1;

debayer_top_wbg_2to1 # (
    .GAMMA_BYPASS(0)
  )
  debayer_top_wbg_2to1_inst (
    .in_pclk(vid_clk_dvi2),
    .in_rstn(vid_rst_n),
    .raw_vs_i     (nr_vs       ),
    .raw_hs_i     (nr_hs       ),
    .raw_de_i     (nr_de       ),
    .raw_valid_i  (nr_valid    ),
    .raw_datax4_i (nr_rawdata  ),
    //***********************************************************************
    // WB 默认增益 (Q2.14, 1.0 = 16384)
    //
    // 原本三个默认值都是 16384 = 1.0, 而 r_gain/g_gain/b_gain 来自 VIO、上电为 0,
    // 所以实际增益恒为 1.0/1.0/1.0 —— 等于**完全没做白平衡**, 画面压着一层品红纱,
    // 这是"图像发雾"的最大单项来源。
    //
    // 下面三个值由**标定当时那一帧** rawdata.hex 统计得出 (可复现, 换场景就重算):
    //   按 np.fromfile(dtype=np.uint8).reshape(1080,1920) 读入
    //   (注意**不是** .reshape(1920,1080).T —— gen_gamma_mem.m 用的是
    //    fread(fid,[W,H]) + .' 的列主序语义), 减 P_BLACK=20 后分通道取均值:
    //     R = 16.18 / G = 11.67 / B = 16.22
    //   灰度世界相对增益: R=0.721 / G=1.000 / B=0.719
    //   再按 p99.9 白点归一化到 255 得 S=1.509, 绝对增益:
    //     R = 1.0880 -> 17826
    //     G = 1.5087 -> 24718
    //     B = 1.0851 -> 17778
    //   三个值都落在 wb_gain_3ch.v:79-80 的 [0.4, 2.5] 钳位内, 不触发饱和分支。
    //
    // *** 这一轮不动这三个值 ***
    //   用户反馈"白色正常", 白平衡没有可抱怨的地方, 就不该去动已经停表的值;
    //   同轮改的 P_BLACK 会让三个通道各多出 (20-17)=3 级基底, 经下面这三个
    //   增益后是 R+3.3 / G+4.5 / B+3.3 —— 通道间只差 1.2 级, 可以忽略。
    //
    // *** 但要留意: 当天新抓的 rawdata.hex 比例与上面这组对不上 ***
    //   同一读法、同一 P_BLACK, 新帧算出的 R/G/B 均值是 18.61 / 16.20 / 4.73,
    //   即 B 只有 G 的 29%; 而上面那组是 R=16.18 / G=11.67 / B=16.22, R 与 B
    //   都比 G 高。两者结构完全不同, 只可能是**场景不同**(新帧更像暖色场景),
    //   不是文件读错 —— 已用象限均值交叉验证过 CFA 相位(两个 G 平面差 0.04)。
    //   所以这几行的统计**不能**拿新帧去覆盖。
    //   真要重标白平衡, 正确做法是拍一张**白纸/灰卡**填满画面; 拿灰世界去猜一个
    //   很可能是单色的场景会得出"B 要提 2.6 倍"这种荒谬值。
    //
    // *** 这是"单场景停表值" ***
    //   换场景或换光照时, G 通道 1.509 倍的曝光提升可能过曝。
    //   根本解法是整帧统计 (3A) -> 寄存器写入路径, 见
    //   debayer_top_wbg_2to1.v:49-50 的 TODO。
    //
    // 保留 |x_gain ? x_gain : default 结构: VIO 一旦写入非零值就覆盖默认值,
    // 在线可调性不受影响 (r_gain/g_gain/b_gain 由 VIO 驱动)。
    //***********************************************************************
    .wb_r_gain      (|r_gain? r_gain : (16'd17826 >> expo_pre)),   // 1.0880
    .wb_g_gain      (|g_gain? g_gain : (16'd24718 >> expo_pre)),   // 1.5087
    .wb_b_gain      (|b_gain? b_gain : (16'd17778 >> expo_pre)),   // 1.0851

    .rgb_vs_o     (db_vs       ),
    .rgb_hs_o     (db_hs       ),
    .rgb_de_o     (db_de       ),
    .rgb_valid_o  (db_valid    ),
    .rgb_datax2_o (db_datax2   )
  );

//***************************************************************************
// RGB 域亮度反锐化掩模 (unsharp mask)
//   详见 rtl/debayer/rgb_sharpen.v 文件头。要点:
//     - 位置在 demosaic + WB + gamma **之后**, 消费块之前。
//       *** 理由不是"避免暗部被放大" *** —— 上一版是这么写的, 那是错的:
//       gamma 前 g(L + K*d_lin) 与 gamma 后 g(L) + K*g'(L)*d_lin 一阶恒等,
//       暗部放大倍数一样 (详见 rgb_saturate.v 文件头第四节)。
//       真正的理由: (1) 与 rgb_saturate 共用同一个编码域 Y 定义;
//       (2) 编码域近似感知均匀, 在这里定"多少算过冲"更贴近肉眼。
//     - 同一个亮度 delta 加给 R/G/B 三通道, 只锐化亮度、不动色相, 避免彩边。
//     - 本模块把画面整体推迟 4 拍, vs/hs/de/valid 与数据一起平移, 相对关系不变。
//     - P_SHARP_GAIN 是 Q2.14 的锐化强度: 8192 = 0.5。过冲就调小 (4096),
//       太软就调大 (12288)。P_BYPASS=1 可整体旁路 (延迟链不变, 只 mux 数据)。
//***************************************************************************
  wire sharpen_bypass;
rgb_sharpen # (
    .P_SHARP_GAIN (16'd95535    ),
    // .P_BYPASS     (1'b0        ),
    .X_CNT_WIDTH  (10          )
  )
  rgb_sharpen_inst (
    .i_pclk   (vid_clk_dvi2),
    .i_arstn  (vid_rst_n   ),
    .P_BYPASS (sharpen_bypass ),
    .i_vs     (db_vs       ),
    .i_hs     (db_hs       ),
    .i_de     (db_de       ),
    .i_valid  (db_valid    ),
    .i_datax2 (db_datax2   ),
    .o_vs     (shp_vs      ),
    .o_hs     (shp_hs      ),
    .o_de     (shp_de      ),
    .o_valid  (shp_valid   ),
    .o_datax2 (shp_datax2  )
  );

//***************************************************************************
// 3x3 色彩校正矩阵 (CCM) —— 色相调节
//   详见 rtl/debayer/rgb_ccm.v 文件头。要点:
//
//   *** 为什么这一级在这里 (rgb_sharpen 之后, rgb_saturate 之前) ***
//     - 必须在 rgb_saturate **之前**: rgb_saturate 的输出直连 hdmi_tx_slow_clk
//       (148.5MHz, 6.734 ns) 的采样寄存器, 9 个乘法器放那儿会当场压爆那条路径
//       (rgb_saturate 自己就是因为组合太深翻过车的, 见上面 2026-10-06 排障记录)。
//       放在这里它拿到的是完整的一个 vid_clk_dvi2 周期 (13.468 ns)。
//     - 放在 gamma **之后**而不是色度学上"正确"的 gamma 之前: 本工程的 gamma
//       打包在 debayer_top_wbg_2to1 内部, 插在那里要改那个模块, 而模块内部
//       标志与数据的错拍 (2P 级 vs 第 3 级) 正是 SKIP_WORDS=2/SKIP_LINES=2
//       标定过的 —— 见 debayer_top_wbg_2to1.v:15-21 那条红线。插在模块**输出
//       之后**, 内部错拍完全不动。代价: 矩阵作用在 gamma 编码域而不是线性光,
//       对"按肉眼把色相拧到位"这个用法反而更直接 (你旋转的就是你看到的)。
//     - 延迟安全性: vid_clk_dvi2 (13.468ns) 与 hdmi_tx_slow_clk (6.734ns) 同源
//       USER_PLL, 严格 2:1 同相 (ti60f225_oob.sdc:11-12), 所以整数拍延迟 = 零采样
//       相位偏移; 下游 hdmi_tx_* 消费块只有 {rgb_vs_r,rgb_vs}==2'b01 的同步上升沿
//       检测 + vid_cnt 重装, **没有绝对拍数假设**。唯一红线: 5 个信号同拍。
//
//   *** 默认是恒等矩阵 —— 插进去画面逐字节不变 ***
//     这是先确认"没踩时序/延迟的坑"的对照点。填了非恒等系数之后, 改一次重综合一次。
//   *** 上板若看到彩色噪声 *** 把 .P_BYPASS 改成 1'b1 重综合, 能立刻定位是不是
//     这一级 (旁路走同一级寄存器, 延迟不变)。
//
//   系数从哪来:  rtl/debayer/sim/ccm_gen.py
//       python ccm_gen.py --hue 20        # 出一组 Q2.14 系数 (theta>0 = 色相朝红)
//       python ccm_gen.py --table         # 打印 -30..+30 度的现成参数表
//     theta=+20 的首选起点 (治"红偏橘", 实测橙色 24.6 度 -> 8.7 度):
//       M_RR=16885 M_RG= 3851 M_RB=-4352
//       M_GR=-1126 M_GG=15054 M_GB= 2456
//       M_BR= 4491 M_BG=-3344 M_BB=15237
//
//   *** 但它治不了"偏橘"的主因 *** —— 那一步的实测是白平衡 (现默认增益给出
//   R/G/B 均值 78.7/84.4/48.4, 整体黄偏约 20 度; 灰世界要求约 14254/16048/40960)。
//   先用 VIO 的 vio0_r/g/b_gain 在线把灰/白物体调成中性, **再**动 CCM 系数。
//   拿 CCM 去盖白平衡的错, 只会把误差混进矩阵里, 以后拆不开。
//***************************************************************************
  wire ccm_bypass;
rgb_ccm # (
    .M_RR      (16'sd16885),   // Q2.14 恒等矩阵: 16384 = 1.0, 其余为 0
    .M_RG      (16'sd3851   ),   // *** 恒等矩阵逐位等于直通 (已穷举 2^24 验证) ***
    .M_RB      (-16'sd4352   ),
    .M_GR      (-16'sd1126   ),
    .M_GG      (16'sd15054),
    .M_GB      (16'sd2456    ),
    .M_BR      (16'sd4491    ),
    .M_BG      (-16'sd3344   ),
    .M_BB      (16'sd15237)//,
    // .P_BYPASS  (1'b1      )    // 1 = 只 mux 数据, 延迟链不变
  )
  rgb_ccm_inst (
    .i_pclk   (vid_clk_dvi2),
    .i_arstn  (vid_rst_n   ),
    .P_BYPASS (ccm_bypass  ),
    .i_vs     (shp_vs      ),
    .i_hs     (shp_hs      ),
    .i_de     (shp_de      ),
    .i_valid  (shp_valid   ),
    .i_datax2 (shp_datax2  ),
    .o_vs     (ccm_vs      ),
    .o_hs     (ccm_hs      ),
    .o_de     (ccm_de      ),
    .o_valid  (ccm_valid   ),
    .o_datax2 (ccm_datax2  )
  );

//***************************************************************************
// RGB 域饱和度 (色度增益) + 暗部色度门控
//   详见 rtl/debayer/rgb_saturate.v 文件头。要点:
//     - 病因 (红不够红): 白平衡正常 (灰/白物体是中性色), 但红色"不够红、发灰发橙"
//       —— 这不是增益问题, 是**色度幅度不足** (主要是双线性 demosaic 的过度平滑)。
//     - 算法: Y = (77R+150G+29B+128)>>8, out_c = clamp(Y + round((c-Y)*S/2^14)),
//       只拉伸色度、保持 Y, 所以 *** 中性色恒不受影响 ***, 不会动已经调好的白平衡。
//     - 病因 (黑处红色噪点, 本轮新增的用法): gamma 底部斜率约 15 级/线性级,
//       暗部 R 与 G 各自的噪声在编码域是 ±15 级, 于是 R-G 抖动能到 ±20 —— 屏幕上
//       就是暗处的彩色颗粒。色度 ×S 等于把这份抖动也 ×S, 所以暗部必须让 S < 1。
//       处方: S 随亮度走 —— Y<=P_Y_LO 用 P_SAT_GAIN_LO, Y>=P_Y_HI 用 P_SAT_GAIN,
//       中间线性插值。标定实测 (rawdata.hex 整帧, 暗部 R-G 高频分量 std):
//         无门控 3.48  ->  S_LO=0.50/Y_LO=32/Y_HI=80 得到 1.61 (暗部色度噪声减半)
//       而 Y >= P_Y_HI 的像素被改动的个数是 **0** —— 门控完全不碰中间调,
//       这是 tb_rgb_saturate.v 检查 4 断言的机器可验红线。
//
//     - 位置在 gamma 之后。*** 注意理由不是"避免暗部被放大" *** —— 上一版是这么
//       写的, 那是错的 (gamma 前 d_lin*S*slope 与 gamma 后 d_lin*slope*S 恒等,
//       暗部放大倍数就是同一个 S)。真正的理由: (1) 与 rgb_sharpen 共用同一个
//       编码域 Y 定义; (2) 编码域近似感知均匀, 保 Y 拉伸对应视觉亮度不变。
//       暗部那个真问题由上面的亮度门控解决, 不是靠挪位置。
//     - *** 1 拍流水 (2026-10-06 改) ***。上一版是零延迟组合逻辑, 上板时序翻车:
//       综合报 10 条失败路径, 最差 slack -5.881 ns。实测根因是这个模块的组合深度
//       —— 数据路径 12.038 ns 里它占 8.26 ns (48 级逻辑), 而这里的下游
//       hdmi_tx_* 那一块用 148.5MHz 的 hdmi_tx_slow_clk 采 rgb_datax2,
//       所以整条 Y->门控->delta->adj->钳位 链都得塞进 6.734 ns。
//       资源从来不是问题 (Memory Block 149/256、XLR 37%、DSP 22/160)。
//       现在把寄存器切在 sat_delta 与 adj_ch 之间, 输入侧回到本模块自己的
//       13.468 ns 周期里, 输出侧只剩加/钳位。详见 rgb_saturate.v 第六节。
//       *** 四个标志与数据同步延迟 1 拍 ***, 相对错拍不变 (红线说的正是"相对"),
//       而 rgb_vs/hs/de/valid/datax2 的唯一消费者就是下面那个 hdmi_tx_* 块,
//       同源同拍, 所以画面只是晚 1 个 vid_clk_dvi2 周期出现, 相对关系一个没变。
//     - 16384 = 1.0 = 逐位直通 (恒等式, 已穷举 2^24 验证)。太灰就往上调 P_SAT_GAIN,
//       高饱和红色发闷就往下调; 暗部还有彩色颗粒就把 P_SAT_GAIN_LO 再调小。
//       P_BYPASS=1 可整体摘掉这一级 (走同一级寄存器, 拍数不变)。
//     - 参数, 不是 VIO: 现有 VIO 核的 4 个输出 (r/g/b_gain + gamma_sel) 已全部占用,
//       加探针必须在 Efinity 的 Debugger wizard 里重新生成核, 改 RTL 改不出来。
//
// *** 2026-10-06 排障记录: 这一级确实把画面搞坏过, 病因是时序不是算法 ***
//   现象: 用户上板反馈"添加了饱和处理之后, 画面完全变成了彩色噪声"; 把本模块
//         P_BYPASS 置 1 之后"现在没有噪点了" —— 至此确认坏在**本模块算出来的
//         那一路数据**上。
//
//   >>> 决定性推论: 旁路走的**不是**另一条路, 是同一级寄存器的另一个抽头 <<<
//   末尾那行是   o_datax2 = P_BYPASS ? r_dat : {w_pix_o, w_pix_e};
//   r_dat 和 w_pix_e/w_pix_o 都是**同一个 always 块、同一拍**打出来的寄存器。
//   所以旁路与直通的**延迟严格相同** —— 换成旁路能变的东西只有数据的值, 不可能是
//   相位、也不可能是拍数。这就把"下游 vid_cnt 偶/奇像素选错相位"那一类猜测
//   (ti60f225_oob_top.v 里 148.5MHz 采 rgb_datax2 的那块) 整个排除掉了。
//
//   已排除的:
//     - 不是数值削波。按 wb_gain_3ch.v:104 的 Q2.14 与 gamma_lut_v1.v:8 的表把
//       rawdata.hex 整帧跑一遍: CFA 采样点被 WB 顶到 511 的只有 0.14%, 至少一个
//       平面到 255 的像素 0.33%。把 G 增益从 1.509 降到 1.0 也只把这 0.217%
//       降到 0 —— 削波与画面好坏无关。
//     - 不是资源: Memory Block 149/256、XLR 37%、DSP 22/160。
//     - 不是算法/字节序。逐位核过: sat_front 的 44 位打包与 sat_back 的解包对齐,
//       adj_ch 的借位判溢正确, {B,G,R} 且 R 在最低字节与顶层
//       {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= rgb_datax2[23:0] 一致。
//       拿文件头第六节那个 R=230/G=120/B=100 的例子手算: Y=151, S=1.30,
//       out = 254/111/85, 与算法定义相符。
//     *** 注意 check_rgb_saturate.py 是照抄 RTL 写的, 两者一起错时对拍全绿 ——
//         它证明不了算术对, 只能证明两处写法一致。所以上面那条是**手算**结论,
//         不是对拍结论。这条坑见 isp_matlab 的既有教训。***
//
//   算法对 + 数据错 + 延迟无关 => 只剩一个解释: **计算路径没收敛, r_f_e/r_f_o
//   被采到了错的值。** 这条路径的预算只有本模块自己一个 13.468 ns 周期
//   (vid_clk_dvi2), 因为下游 hdmi_tx_* 那块是 148.5MHz 采样, 更紧。
//   *** 注意: 从改 1 拍流水那次到现在, outflow/ 下**从来没生成过** place/route
//   报告, 用户几次跑的都是只有 Synthesis。所以"修复后时序到底过没过"这件事
//   我一次都没有数据, 全靠推算。 ***
//
//   >>> 本轮的处置: 把这条路径上最重的一块删掉 <<<
//   sat_gain_at 原来写的是   sat_gain_at = P_SAT_GAIN_LO + num / (P_Y_HI-P_Y_LO);
//   —— 那是在**赌**综合器认出除数是常数、把它优化成移位。赌输了就是这条路径上
//   最重的组合块。现在改成写死的 >> P_RAMP_SHIFT (见 rgb_saturate.v 的
//   P_RAMP_SHIFT / P_RAMP_HALF), 综合器没有别的选择, 只能是移位。
//   这是**删减**不是新增: 除法的行为与移位逐位相同 (P_Y_HI-P_Y_LO = 64 = 2^6),
//   只是不再依赖综合器的优化能力。
//
//   >>> 如果彩色噪声又回来了 <<<
//   那就说明瓶颈不在那个除法, 而是路径整体还是太长。下一步**不要**再猜:
//   请跑**完整流程 (Place & Route / Bitstream), 不要只跑 Synthesis** —— 只有完整
//   流程才会生成 outflow/ti60f225_oob.timing.rpt, 那份报告里能直接看到是哪条
//   路径、多少级逻辑、差多少 ns。拿到它之前任何 RTL 改动都是盲改。
//
//   补充 (与本次故障无关, 但下次重新标定时要记住): 按 rawdata.hex 整帧统计
//   gamma 后的 Y (每 2x2 一个采样, 共 518400 点): 均值 78.9 / p50 67 / p99 170,
//   其中 Y<=32 只占 2.62%、32<Y<96 占 77.04%、Y>=96 占 20.33%。也就是门控真正
//   卖力的区域只有 2.6% 的像素, 而 77% 的画面落在斜坡上 (Y=48->S=0.70,
//   Y=64->0.90, Y=80->1.10)。这帧 raw p50 只有 13/11/5 (BLC 后中位数贴到 0),
//   非常暗 —— 想重新标 P_Y_LO/P_Y_HI 的话, 请按上面这组**实测分布**来, 不要再
//   拍脑袋定"暗部阈值"。
//***************************************************************************
  wire sat_bypass;
rgb_saturate # (
    .P_SAT_GAIN     (16'd21299  ),   // Q2.14, 1.30  中间调及以上的色度增益
    .P_SAT_GAIN_LO  (16'd8192   ),   // Q2.14, 0.50  暗部 (Y<=P_Y_LO) 的色度增益
    .P_Y_LO         (8'd32      ),   // 暗部门控下限
    .P_Y_HI         (8'd96      ),   // 暗部门控上限; 与 P_Y_LO 之差 = 64 = 2^6
    // R 通道的额外色度增益 = 1 + 2^-P_RED_SHIFT, 只对 R > Y 的像素生效
    //   *** 2026-10-06: 由 2 改成 0 (关闭), 色相改由上面的 rgb_ccm 接管 ***
    //   为什么关掉而不是留着: 这一条与 CCM 都动色相, 两处叠加会互相盖 ——
    //   调 CCM 系数时看到的色相变化不是 CCM 单独造成的, 标定没法做。
    //   色相只由一处负责, 这里让路。
    //   原委 (留档): 本参数把红色像素往红的方向推 1.5~3.3 度, 幅度有限且破坏
    //   Y 守恒; 它治不了"偏橘"的主因 (那是白平衡)。详见 rgb_saturate.v 文件头五之二。
    //   0 = 关闭 (与没有这个功能逐位相同); 1 = x1.5; 2 = x1.25; 3 = x1.125
    //   注意: 关掉之后 rgb_saturate.v 检查 1 的红线 (S=16384 必须逐位直通) 重新成立。
    .P_RED_SHIFT    (0          )//,
    // 0 = 打开饱和度; 上板若再看到彩色噪声, 把它改成 1'b1 就能整级摘掉
    // (旁路走同一级寄存器, 所以摘掉不改延迟, 只换数据来源)
    // .P_BYPASS       (1'b0       )
  )
  rgb_saturate_inst (
    .i_pclk   (vid_clk_dvi2),
    .i_arstn  (vid_rst_n   ),
    .P_BYPASS (sat_bypass  ),
    .i_vs     (ccm_vs      ),
    .i_hs     (ccm_hs      ),
    .i_de     (ccm_de      ),
    .i_valid  (ccm_valid   ),
    .i_datax2 (ccm_datax2  ),
    .o_vs     (rgb_vs      ),
    .o_hs     (rgb_hs      ),
    .o_de     (rgb_de      ),
    .o_valid  (rgb_valid   ),
    .o_datax2 (rgb_datax2  )
  );


// debayer_top_2to1 debayer_top
// (
// 	.in_pclk		  (vid_clk_dvi2),//(i_mipi_rx_pclk ),
// 	.in_rstn		  (vid_rst_n	),
	
// 	.raw_vs_i		  (ch0_vs		      ),
// 	.raw_hs_i		  (ch0_hs		      ),
// 	.raw_de_i		  (ch0_de		      ),
// 	.raw_valid_i	(ch0_de	        ),
// 	.raw_datax4_i	({ch0_b,rawdata_2pix}	),
// 	.r_gain       (|r_gain? r_gain:255 ),
//   .g_gain       (|g_gain? g_gain:255 ),
//   .b_gain       (|b_gain? b_gain:255 ),
// 	.rgb_vs_o		  (rgb_vs         ),
// 	.rgb_hs_o		  (rgb_hs         ),
// 	.rgb_de_o		  (rgb_de         ),
// 	.rgb_valid_o	(rgb_valid      ),
// 	.rgb_datax2_o (rgb_datax2     )//b,g,r,b,g,r
// );
reg rgb_vs_r = 'd0;
always @( posedge hdmi_tx_slow_clk )
begin
  rgb_vs_r <= rgb_vs;
end
assign pos_vs = {rgb_vs_r,rgb_vs} == 2'b01;
reg vid_cnt = 'd0;
reg [7:0] hdmi_tx_rdata ;
reg [7:0] hdmi_tx_gdata ;
reg [7:0] hdmi_tx_bdata ;
reg hdmi_tx_vs;
reg hdmi_tx_hs;
reg hdmi_tx_de;
always @( posedge hdmi_tx_slow_clk )
begin
    if( pos_vs )
      vid_cnt <= 1'b1;
    else if( rgb_de )
      vid_cnt <= ~vid_cnt ;

    if( vid_cnt )
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= rgb_datax2[23:0];
    else 
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= rgb_datax2[47:24];

  hdmi_tx_vs <= rgb_vs;
  hdmi_tx_hs <= rgb_hs;
  hdmi_tx_de <= rgb_de;
end
//==============================================================================
// MIPI DSI
//==============================================================================
// signal 

wire w_confdone = 1'b1;

reg [26:0] dly_cnt = 'd0;

always @( posedge vid_clk_dvi2 or negedge w_arstn )
begin
  if( !w_arstn )
    dly_cnt <= 'd0;
  else if( w_confdone )
    dly_cnt <= dly_cnt[26] ? dly_cnt :(dly_cnt + 1'b1);
  else 
    dly_cnt <= 'd0;
end 

assign vid_rst_n = dly_cnt[26];




wire hs;
wire vs;
wire de;
wire [7:0] rgb_r;
wire [7:0] rgb_g;
wire [7:0] rgb_b;
  
  // color_bar_rgb #(
  // .HS_POLORY 		(1'b1		),
  // .VS_POLORY 		(1'b1		),
  // .H_FRONT_PORCH 	(HFP		),///2
  // .H_SYNC 		(HSP		),//
  // .H_VALID 		(MAX_HRES	),//
  // .H_BACK_PORCH 	(HBP		),//
  // .V_FRONT_PORCH 	(VFP		),
  // .V_SYNC 		(VSP		),
  // .V_VALID 		(MAX_VRES	),
  // .V_BACK_PORCH 	(VBP		),
  // .TEST_MODE 		(2'd2)
  // )u_color_bar_rgb1(
  // /*i*/.clk	(vid_clk_dvi2),//(vid_clk),
  // /*i*/.rst_n	(vid_rst_n),
  // /*o*/.hs	(hs),
  // /*o*/.vs	(vs),
  // /*o*/.de	(de),
  // // /*O*/.h_cnt (h_cnt),
  // // /*O*/.v_cnt (v_cnt),
  // /*o*/.rgb_r	(rgb_r),    //像素数据、红色分量
  // /*o*/.rgb_g	(rgb_g),    //像素数据、绿色分量
  // /*o*/.rgb_b (rgb_b)    //像素数据、蓝色分量
  
  // );

//=================================================================================
//hdmi tx ctrl 
//=================================================================================
wire                            video_hs;
wire                            video_vs;
wire                            video_de;
wire[7:0]                       video_r;
wire[7:0]                       video_g;
wire[7:0]                       video_b;

assign tmds_tx_data0_TX_OE = 1'b1;
assign tmds_tx_data1_TX_OE = 1'b1;
assign tmds_tx_data2_TX_OE = 1'b1;
assign tmds_tx_clk_TX_OE   = 1'b1;

assign tmds_tx_data0_TX_RST = 1'b0;
assign tmds_tx_data1_TX_RST = 1'b0;
assign tmds_tx_data2_TX_RST = 1'b0;
assign tmds_tx_clk_TX_RST   = 1'b0;

// 	  color_bar color_bar_m0(
// 	.clk(hdmi_tx_slow_clk),
// 	.rst(~vid_rst_n),
// 	.hs(video_hs),
// 	.vs(video_vs),
// 	.de(video_de),
// 	.rgb_r(video_r),
// 	.rgb_g(video_g),
// 	.rgb_b(video_b)
// );

wire [9:0] tmds_data0;
wire [9:0] tmds_data1;
wire [9:0] tmds_data2;
wire [9:0] tmds_clk ;
wire [7:0] gamma_rdata ;
wire [7:0] gamma_gdata ;
wire [7:0] gamma_bdata ;
wire gamma_valid;
wire gamma_hs;
wire gamma_vs;
wire gamma_sel;

wire [7:0] con_rdata ;
wire [7:0] con_gdata ;
wire [7:0] con_bdata ;
wire con_de;
wire con_hs;
wire con_vs;
wire con_sel;

wire [7:0] BRIGHT_SIG    ;
wire CONTRAST_SIG_G;
wire CONTRAST_SIG_R;
wire [7:0] CONTRAST_G    ;
wire CONTRAST_SIG_B;
wire [7:0] BRIGHT        ;
wire [7:0] CONTRAST_R    ;


wire CONTRAST_B    ;



wire sobel_de, sobel_hs, sobel_vs;
wire [7:0] sobel_gray;
wire [7:0] sobel_red, sobel_green, sobel_blue;
// Digital exposure: the extra output-domain shift for levels 2 and 3 (see expo_post).
wire [7:0] cam_red   = hdmi_tx_rdata >> expo_post;
wire [7:0] cam_green = hdmi_tx_gdata >> expo_post;
wire [7:0] cam_blue  = hdmi_tx_bdata >> expo_post;
sc431_sobel_video #(
    .REPLAY_FRAMES(60),.AUTO_REPLAY(1),.PLAY_FRAMES(6),.CANNY_ENABLE(1),.CANNY_STREAM_ENABLE(1),.CANNY_WIDTH(640),.CANNY_HEIGHT(480),.CANNY_MEDIAN_ENABLE(1),.SNAPSHOT_ENABLE(1),.PHOTO_MATCH_ENABLE(1),.EXPRESSION_ENABLE(0),.CNN_ENABLE(1),.CNN_EXPRESSION_ENABLE(1)) u_camera_sobel (
    .clk(hdmi_tx_slow_clk), .rst_n(vid_rst_n),
    .increase_n(KEY1_N), .decrease_n(KEY2_N), .mode_n(KEY3_N),
    .de_in(hdmi_tx_de), .hs_in(hdmi_tx_hs), .vs_in(hdmi_tx_vs),
    .red_in(cam_red), .green_in(cam_green), .blue_in(cam_blue),
    .de_out(sobel_de), .hs_out(sobel_hs), .vs_out(sobel_vs), .gray_out(sobel_gray),
    .red_out(sobel_red), .green_out(sobel_green), .blue_out(sobel_blue),
    .freeze_requested(freeze_requested),.replay_requested(replay_requested),.compare_request(compare_request),.replay_select(replay_select),
    .freeze_ack(freeze_ack),.replay_ack(replay_ack),.replay_selection_ack(replay_selection_ack),
    .expo_shift(expo_shift)
);
capture_dvi_compat dvi_encoder_m0
(
	.pixelclk      		(hdmi_tx_slow_clk          ),// system clock
	.rst_p         		(~vid_rst_n       ),// reset
    .i_bdata(sobel_blue),
    .i_gdata(sobel_green),
    .i_rdata(sobel_red),
    .i_de(sobel_de),
    .i_hs(sobel_hs),
    .i_vs(sobel_vs),
	
  .video_format     (2'b00),
  .video_VIC        (7'd16),
	.audio_L (24'b0),
  .audio_R (24'b0),
  .audio_valid (1'b0),
  .audio_N                (20'd6144),
  .audio_CTS              (20'd148500),
  .audio_sample_frequency (4'b0010),
  .audio_word_length (4'b1011),

	.tmds_data0    		(tmds_data0),
  .tmds_data1    		(tmds_data1),
  .tmds_data2    		(tmds_data2),
  .tmds_clk      	  (tmds_clk  )
);
assign led[1] = w_arstn;
assign led[2] = i2c_rst_n;
assign led[3] = mdebug_receive_error;
assign led[4] = mdebug_crc_error;
assign led[5] = mdebug_ecc_2bit_error;
assign led[6] = vid_rst_n;
assign led[7] = rgb_vs;
assign tmds_tx_clk_TX_DATA   = ~tmds_clk;
assign tmds_tx_data0_TX_DATA = ~tmds_data0;
assign tmds_tx_data1_TX_DATA = ~tmds_data1;
assign tmds_tx_data2_TX_DATA = ~tmds_data2;

debug_edb_top debug_edb_top_inst (
    .bscan_CAPTURE      ( jtag_inst1_CAPTURE  ),
    .bscan_DRCK         ( jtag_inst1_DRCK     ),
    .bscan_RESET        ( jtag_inst1_RESET    ),
    .bscan_RUNTEST      ( jtag_inst1_RUNTEST  ),
    .bscan_SEL          ( jtag_inst1_SEL      ),
    .bscan_SHIFT        ( jtag_inst1_SHIFT    ),
    .bscan_TCK          ( jtag_inst1_TCK      ),
    .bscan_TDI          ( jtag_inst1_TDI      ),
    .bscan_TMS          ( jtag_inst1_TMS      ),
    .bscan_UPDATE       ( jtag_inst1_UPDATE   ),
    .bscan_TDO          ( jtag_inst1_TDO      ),
    .vio0_clk           ( vid_clk_dvi2        ),
    .vio0_r_gain        ( r_gain              ),
    .vio0_g_gain        ( g_gain              ),
    .vio0_b_gain        ( b_gain              ),

    .vio0_ccm_bypass    (ccm_bypass ),
    .vio0_sat_bypass    (sat_bypass    ),
    .vio0_sharpen_bypass(sharpen_bypass),
    .vio0_nr_bypass     (nr_bypass),
    .la0_clk            ( vid_clk_dvi2        ),
    .la0_ch0_g          ( rawdata_2pix[7:0]         ),
    .la0_ch0_b          ( ch0_b               ),
    .la0_ch0_de         ( ch0_de              ),
    .la0_cal_done       ( cal_done            )
);

endmodule

