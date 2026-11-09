

`timescale 1ps/1ps
module ddr_buffer #(
parameter AXI_DATA_WIDTH = 512, //!AXI接口位宽
parameter REPLAY_ENABLE = 0,
parameter REPLAY_FRAMES = 2,
parameter SELECT_BITS = $clog2(REPLAY_FRAMES),
parameter AXI_ADDR_WIDTH = 33,  //!AXI地址位宽
parameter WR_FIFO_DEPTH	= 1024, //!Write fifo depth   
parameter RD_FIFO_DEPTH = 1024, //!read fifo depth
parameter FB_NUM			= 	3,//2 buffer ,3 buffer   
parameter MAX_VID_WIDTH		=	1920 ,//video width 
parameter MAX_VID_HIGHT		=	1080 ,//wideo height
parameter START_ADDR				=	33'h000201900,
parameter BURST_LEN       = 8'd15,
parameter I_VID_WIDTH = 16,
parameter AXI_STRB_WIDTH = AXI_DATA_WIDTH/8//!总共的字节数量，= AXI_DATA_WIDTH/8

) (

input 											axi_clk,
input                       wr_clk_rst_n,
input wire freeze_request,
input wire replay_request,
input wire                                split_request,
input wire [SELECT_BITS-1:0] replay_select,
output wire freeze_active,replay_ready,
output wire [SELECT_BITS-1:0] replay_select_ack,
input                       axi_clk_rst_n,
input                       rd_clk_rst_n,
input 											rd_start,
input											wr_start, // pulse signal 

// input		[AXI_ADDR_WIDTH-1:0]				start_wr_addr,
// input		[AXI_ADDR_WIDTH-1:0]				start_rd_addr,
input 		[31:0] 								wr_busrt_len,
input 		[31:0] 								rd_burst_len,
output		[7:0] test_cnt ,

input                     wr_fifo_rst_p,
input											wr_fifo_wrclk,
input											wr_fifo_wren,
output											wr_fifo_wrfull,
input	 [AXI_DATA_WIDTH-1:0]					wr_fifo_wrdata, 
input											rd_fifo_rdclk,
input                       rd_fifo_rst_p,
output											rd_fifo_rdvalid,
output	 [AXI_DATA_WIDTH-1:0] 					rd_fifo_rddata,
output wire										rd_fifo_rdempty,
input	 wire									rd_fifo_rden,

output 	[5:0] 									awid,
output  [AXI_ADDR_WIDTH-1:0] 					awaddr,
output  [8-1:0] 					awlen,
output  [2:0] 									awsize,
output  [1:0] 									awburst,
output  [3:0] 									awcache,
output [2:0]                    awprot,
output  										awlock,
output  										awvalid,
output  										awcobuf,
output  										awapcmd,
output  										awallstrb,
output  										awqos,
input 											awready,

output [5:0] 									arid,
output  [AXI_ADDR_WIDTH-1:0] 					araddr,
output  [8-1:0] 					arlen,
output  [2:0] 									arsize,
output  [1:0] 									arburst,
output  										arlock,
output  										arvalid,
output  										arapcmd,
output 											arqos,
input 											arready,
output  [3:0] 									arcache,
output [2:0]                    arprot,
output  [AXI_DATA_WIDTH-1:0] 					wdata,  
output	[31:0]									test_wdata,
output	[31:0]									test_rdata,
output  [AXI_STRB_WIDTH-1:0] 					wstrb,
output  										wlast,
output  										wvalid,
input 											wready,

input [5:0] 									rid,
input [AXI_DATA_WIDTH-1:0] 						rdata,
input 											rlast,
input 											rvalid,
output  										rready,
input [1:0] 									rresp,
output[31:0]									wr_fifo_rd_data_test,
input [5:0] 									bid,
input 											bvalid,
output  										bready,

output [7:0] test_BURST_LEN
);
assign test_BURST_LEN = BURST_LEN;

//=============================================================
//reg define 
//=============================================================   


//=============================================================
//wire define 
//============================================================= 



wire		                        wr_sw_ack           ;
wire		                        wr_sw 		          ;
wire		                        rd_sw			          ;
wire		                        rd_sw_ack           ;
wire		[AXI_ADDR_WIDTH-1:0]		wr_start_addr       ;
wire		[AXI_ADDR_WIDTH-1:0]    rd_start_addr       ;
wire [31:0] live_addr; 
wire frame_committed,commit_fault;
wire slot_ready,slot_begin;
wire read_slot_ready;
reg [31:0] captured_frame_words;
// Hold the first accepted stable capture length throughout live/frozen replay.
// Oversized/empty frames are rejected by frame_buffer. A genuine capture-length
// change used to need a reset and froze the picture; eight consecutive rejected
// frames now re-arm the latch so the new stable length is adopted instead.
reg [2:0] size_mismatch = 'd0;
always @(posedge axi_clk or negedge axi_clk_rst_n)
 if(!axi_clk_rst_n) size_mismatch<=3'd0;
 else if(wr_start)
   size_mismatch<=write_size_ok ? 3'd0 : (size_mismatch==3'd7 ? 3'd7 : size_mismatch+3'd1);
wire size_resync=(size_mismatch==3'd7);
always @(posedge axi_clk or negedge axi_clk_rst_n)
 if(!axi_clk_rst_n) captured_frame_words<=0;
 else if(size_resync) captured_frame_words<=0;
 else if(slot_begin && captured_frame_words==0) captured_frame_words<=wr_busrt_len;
wire write_size_ok=(captured_frame_words==0 || wr_busrt_len==captured_frame_words);
wire guarded_write_start=wr_start && (FB_NUM<10 || write_size_ok);
(* async_reg="true" *) reg rd_period_meta,rd_period_sync;
reg rd_period_d;
always @(posedge axi_clk or negedge axi_clk_rst_n)
 if(!axi_clk_rst_n)begin rd_period_meta<=0;rd_period_sync<=0;rd_period_d<=0;end
 else begin rd_period_meta<=rd_start;rd_period_sync<=rd_period_meta;rd_period_d<=rd_period_sync;end
reg read_launch;
always @(posedge axi_clk or negedge axi_clk_rst_n)
 if(!axi_clk_rst_n)read_launch<=0;
 else read_launch<=rd_period_sync && !rd_period_d;
wire guarded_read_start=FB_NUM>=10 ? (read_launch && read_slot_ready):rd_start;

wire [1:0] wr_bank,rd_bank;
wire [AXI_ADDR_WIDTH-1:0] committed_addr;
localparam FRAME_STRIDE=MAX_VID_WIDTH*MAX_VID_HIGHT*I_VID_WIDTH/8+32'h200;
wire [1:0] writing_bank=awaddr<START_ADDR+FRAME_STRIDE ? 0:
    awaddr<START_ADDR+2*FRAME_STRIDE ? 1:2;
wire [1:0] committed_bank=committed_addr<START_ADDR+FRAME_STRIDE ? 0:
    committed_addr<START_ADDR+2*FRAME_STRIDE ? 1:2;

//=============================================================  
//RTL                                                     
//=============================================================  



ddr_wr_buffer1 # (
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .WR_FIFO_DEPTH(WR_FIFO_DEPTH),
    .SLOT_GUARD(FB_NUM>=10),
    .BURST_LEN (BURST_LEN        )
  )

  u_ddr_wr_buffer (//_inst
    .axi_clk(axi_clk),
    .rst_n(axi_clk_rst_n),//(rst_n),
    .start(guarded_write_start),
    .slot_ready(slot_ready),.slot_begin(slot_begin),
    .frame_committed(frame_committed),.committed_addr(committed_addr),.commit_fault(commit_fault),
    .start_addr(wr_start_addr),//(0),//
    .total_burst_len(wr_busrt_len[24:0]),
/*i*/.bank_sw_ack	(wr_sw_ack   	),
/*o*/.bank_sw 		  (wr_sw  		 	),
    .test_cnt(test_cnt),
    .wr_fifo_rst_p(wr_fifo_rst_p),
    .wr_fifo_wrclk(wr_fifo_wrclk),
    .wr_fifo_wren(wr_fifo_wren),
    .wr_fifo_wrfull(wr_fifo_wrfull),
    .wr_fifo_wrdata(wr_fifo_wrdata),
    .awid(awid),
    .awaddr(awaddr),
    .awlen(awlen),
    .awsize(awsize),
    .awburst(awburst),
    .awcache(awcache),
    .awlock(awlock),
    .awvalid(awvalid),
    .awcobuf(awcobuf),
    .awapcmd(awapcmd),
    .awallstrb(awallstrb),
    .awprot (awprot ),
    .awqos(awqos),
    .awready(awready),
    .wdata(wdata),
    .wstrb(wstrb),
    .wlast(wlast),
    .wvalid(wvalid),
    .wready(wready),
	  .bid	( bid			),
    .bvalid	( bvalid		),
    .bready	( bready		)
  );


assign test_wdata = wdata[32:0];
assign test_rdata = rdata[32:0];
//=============================================================================================
// FIFO RD_PROCESSING
//=============================================================================================
ddr_rd_buffer # (
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .RD_FIFO_DEPTH(RD_FIFO_DEPTH),
    .BURST_LEN (BURST_LEN        )
  )
  ddr_rd_buffer_inst (
    .axi_clk(axi_clk),
    .axi_clk_rst_n(axi_clk_rst_n),
    .start(guarded_read_start),
    .start_addr(rd_start_addr),//(0),//
    .burst_len(FB_NUM>=10 ? captured_frame_words[24:0]:rd_burst_len[24:0]),
    .split_enable(FB_NUM>=10 && split_request),
    .split_addr(live_addr[AXI_ADDR_WIDTH-1:0]),
    .rd_fifo_rdclk(rd_fifo_rdclk),
    .rd_fifo_rst_p (rd_fifo_rst_p),
    .rd_fifo_rdvalid(rd_fifo_rdvalid),
    .rd_fifo_rddata(rd_fifo_rddata),
    .rd_fifo_rdempty(rd_fifo_rdempty),
    .rd_fifo_rden(rd_fifo_rden),
/*i*/.bank_sw_ack	(rd_sw_ack   	),
/*o*/.bank_sw 		  (rd_sw  		 	),
    .arid(arid),
    .araddr(araddr),
    .arlen(arlen),
    .arsize(arsize),
    .arburst(arburst),
    .arlock(arlock),
    .arvalid(arvalid),
    .arapcmd(arapcmd),
    .arqos(arqos),
    .arready(arready),
    .arprot (arprot ),
    .arcache(arcache),
    .rid(rid),
    .rdata(rdata),
    .rlast(rlast),
    .rvalid(rvalid),
    .rready(rready),
    .rresp(rresp),
    .wr_fifo_rd_data_test(wr_fifo_rd_data_test)
  );
//===================================================================================== 
//
//===================================================================================== 
  


generate if(FB_NUM>=10) begin : six_frame
localparam SLOT_BITS=$clog2(FB_NUM);
function [SLOT_BITS-1:0] slot_of;
 input [AXI_ADDR_WIDTH-1:0] address;
 integer n;
 begin
  slot_of=0;
  for(n=1;n<FB_NUM;n=n+1) if(address>=START_ADDR+n*FRAME_STRIDE)slot_of=n;
 end
endfunction
wire [SLOT_BITS-1:0] ws,rs;
wire [31:0] wa,ra;
reg rd_sw_d;
wire bootstrap_boundary=rd_period_sync && !rd_period_d && !read_slot_ready;

always @(posedge axi_clk or negedge axi_clk_rst_n)
 if(!axi_clk_rst_n)rd_sw_d<=0;else rd_sw_d<=rd_sw;
replay6_slots #(.STRIDE(FRAME_STRIDE),.START_ADDR(START_ADDR),.HISTORY_FRAMES(REPLAY_FRAMES)) u_slots(
 .clk(axi_clk),.rst_n(axi_clk_rst_n),.read_boundary((rd_sw&&!rd_sw_d)||bootstrap_boundary),
 .freeze_request(freeze_request),.replay_request(replay_request),.delay_mode(split_request),.selection(replay_select),
 .write_begin(slot_begin),.write_done(frame_committed),.fault(commit_fault),
 .committed_slot(slot_of(committed_addr)),.reading_slot(slot_of(araddr)),
 .write_ready(slot_ready),.write_slot(ws),.read_slot(rs),
 .frozen(freeze_active),.replay_ready(replay_ready),.selection_ack(replay_select_ack),
 .write_address(wa),.read_address(ra),.live_address(live_addr),.read_ready(read_slot_ready));
assign wr_start_addr=wa;assign rd_start_addr=ra;
assign wr_sw_ack=1'b1;assign rd_sw_ack=1'b1;
end else begin : legacy_frames
assign slot_ready=1'b1;
assign live_addr=wr_start_addr;
assign read_slot_ready=1'b1;
bank_switch #(
		.FB_NUM					( FB_NUM),
        .REPLAY_ENABLE(REPLAY_ENABLE),
		.MAX_VID_WIDTH 	( MAX_VID_WIDTH),
		.MAX_VID_HIGHT 	( MAX_VID_HIGHT),
		.START_ADDR			(	START_ADDR 	),
		.VID_DATA_WIDTH	(I_VID_WIDTH	),
		.AXI_DATA_WIDTH (AXI_DATA_WIDTH )
)
  u_bank_sw
(
/*i*/.ddr_clk		(axi_clk	),
/*i*/.rst_n			(axi_clk_rst_n),
              .freeze_request (freeze_request),
              .replay_request(replay_request),.replay_select(replay_select),
              .write_active(awvalid && awready),.writing_bank(writing_bank),
              .write_committed(frame_committed),.committed_bank(committed_bank),.commit_fault(commit_fault),
              .freeze_active(freeze_active),.replay_ready(replay_ready),.replay_select_ack(replay_select_ack),
              	
/*i*/.wr_sw			(wr_sw),
/*i*/.rd_sw			(rd_sw),
                
/*o*/.wr_bank		(wr_bank	),
/*o*/.rd_bank		(rd_bank	),
/*o*/.rd_sw_ack	(rd_sw_ack),
/*o*/.wr_sw_ack (wr_sw_ack),
/*o*/.rd_start_addr(rd_start_addr),
/*o*/.wr_start_addr(wr_start_addr)
);



end endgenerate
endmodule
