
`timescale 1ps/1ps
module ddr_rd_buffer #(
parameter AXI_DATA_WIDTH = 512, //!AXI接口位宽
parameter AXI_ADDR_WIDTH = 33,  //!AXI地址位宽
parameter RD_FIFO_DEPTH = 1024, //!read fifo depth
parameter BURST_LEN       = 15

) (

input 								            axi_clk,
input 								            axi_clk_rst_n,
input 								            start,//!电平有效。

input		[AXI_ADDR_WIDTH-1:0]	            start_addr,
input		[24:0]								burst_len,
input wire                                     split_enable,
input wire [AXI_ADDR_WIDTH-1:0]                split_addr,
input wire                                     bank_sw_ack	,
output  wire                                     bank_sw 		  ,

input											rd_fifo_rdclk,
input                                           rd_fifo_rst_p,
output	reg										rd_fifo_rdvalid ='d0,
output	 [AXI_DATA_WIDTH-1:0] 				    rd_fifo_rddata,
output wire										rd_fifo_rdempty,
input	 wire									rd_fifo_rden,

output [5:0] 									    arid,
output  [AXI_ADDR_WIDTH-1:0] 	                    araddr,
output  [8-1:0] 						            arlen,
output  [2:0] 										arsize,
output  [1:0] 										arburst,
output  											arlock,
output reg 											arvalid,
output  											arapcmd,
output 												arqos,
input 												arready,
output  [3:0] 								        arcache,
output [2:0]                                        arprot,

input [5:0] 									rid,
input [AXI_DATA_WIDTH-1:0] 						rdata,
input 											rlast,
input 											rvalid,
output  reg										rready,
input [1:0] 									rresp,
output[31:0]									wr_fifo_rd_data_test,

output [7:0] test_BURST_LEN
);
assign test_BURST_LEN = BURST_LEN;
localparam AXSIZE_WTH = $clog2(AXI_DATA_WIDTH/8);//!内部数据
localparam RD_USEDW_WITH = $clog2(RD_FIFO_DEPTH) ;
localparam ADDR_SHIFT_BITS = $clog2(AXI_DATA_WIDTH/8);
reg 										ddr_rd_valid;                      
reg [AXI_DATA_WIDTH-1:0] 					ddr_rd_data;     
wire [RD_USEDW_WITH   :0]					rd_fifo_wrusedw;   
 
reg	 [AXI_ADDR_WIDTH-1:0] 					ddr_addr	= 'd0;  
reg	[8-1:0]					                ddr_arlen = 'd0; 
reg			[2:0]							start_sync = 'd0;
wire [AXI_ADDR_WIDTH-1:0] 					nx_ddr_addr;
wire										rd_addr_en	;
reg	[24:0]									burst_len_r = 'd0;
reg											burst_last ='d0;
reg [AXI_ADDR_WIDTH-1:0] 					start_addr_r = 'd0;
reg                                         split_enable_r = 'd0;
reg [AXI_ADDR_WIDTH-1:0]                    split_addr_r = 'd0;
reg                                         sync_r0 = 'd0;
reg                                         sync_r1 = 'd0;
reg                                         sync_r2 = 'd0;
reg [8-1:0]                                 first_burst_cnt = 'd0;
reg	[8-1:0] 			                    last_burst_cnt = 'd0;
reg [24:0]                                  align_burst_num = 'd0;
reg [24:0]                                  burst_num = 'd0;
reg [24:0]                                  total_burst_num = 'd0;

//wire pos_start;
always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
	if( !axi_clk_rst_n )			start_sync <= 'd0;
	else 				    start_sync <= {start_sync[1:0],start};
end

assign pos_start = start_sync[1:0] == 2'b01;
always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
	if( !axi_clk_rst_n ) begin
		sync_r0 <= 1'b0;
		sync_r1 <= 1'b0;
		sync_r2 <= 1'b0;
	end else begin 
		sync_r0 <= pos_start;
		sync_r1 <= sync_r0;
		sync_r2 <= sync_r1;
	end 
end

always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
	if( !axi_clk_rst_n ) begin
			// cfg_alen_r   <= cfg_alen;
			burst_len_r<= 'd0;
			start_addr_r <= 'd0;
	end else begin
			burst_len_r  <= pos_start ? burst_len   : burst_len_r ;
			// cfg_alen_r   <= pos_start ? cfg_alen    :cfg_alen_r;
			start_addr_r <= pos_start ? start_addr  :start_addr_r;
	end
end

wire [12-ADDR_SHIFT_BITS:0]     first_4k_burst_len = {1'b0,~start_addr_r[11:ADDR_SHIFT_BITS]} + 1'b1;
wire [31:0]                     last_4k_burst_len  = burst_len_r - first_4k_burst_len;


// Split at the nearest aligned burst boundary, then use full bursts.
// Clamp the first burst to the complete frame size; short frames need ONE
// burst, not an underflowed middle-burst count. All divisions are constants.
wire [24:0] first_aligned_words=((first_4k_burst_len-1'b1) & BURST_LEN)+1'b1;
wire [24:0] first_frame_words=burst_len_r<first_aligned_words ? burst_len_r:first_aligned_words;
wire [24:0] remaining_frame_words=burst_len_r-first_frame_words;
always @(posedge axi_clk or negedge axi_clk_rst_n)begin
 if(!axi_clk_rst_n)begin first_burst_cnt<=0;last_burst_cnt<=0;align_burst_num<=0;burst_num<=0;end
 else begin
  first_burst_cnt<=first_frame_words==0 ? 0:first_frame_words-1'b1;
  last_burst_cnt<=(remaining_frame_words % (BURST_LEN+1))==0 ? BURST_LEN:
                  (remaining_frame_words % (BURST_LEN+1))-1'b1;
  align_burst_num<=remaining_frame_words;
  burst_num<=burst_len_r==0 ? 0:1+(remaining_frame_words+BURST_LEN)/(BURST_LEN+1);
 end
end

//====================================================================================
//address process
always @(posedge axi_clk or negedge axi_clk_rst_n) 
begin
	if (!axi_clk_rst_n) 									ddr_addr <= 'd0;
	else if( sync_r2 )						                ddr_addr <= start_addr_r;
	else if (rd_addr_en) 						            ddr_addr <= nx_ddr_addr;
    
end 
assign nx_ddr_addr =  ddr_addr + {({1'b0,ddr_arlen}+9'd1),{ADDR_SHIFT_BITS{1'b0}} };  

// Split read: one 15-beat burst per half line, alternating between the frozen
// slot (left) and the newest committed slot (right). 15 beats * 64 B = 960 B and
// 30 beats = one 1920-pixel line, so burst 2k is line k left and 2k+1 is right.
always @(posedge axi_clk or negedge axi_clk_rst_n)
begin
    if(!axi_clk_rst_n) begin split_enable_r <= 1'b0; split_addr_r <= 'd0; end
    else if(pos_start) begin split_enable_r <= split_enable; split_addr_r <= split_addr; end
end
reg [11:0] split_line = 'd0;
reg        split_half = 1'b0;
reg [24:0] split_beats = 'd0;
reg        split_stop = 1'b0;
always @(posedge axi_clk or negedge axi_clk_rst_n)
begin
    if(!axi_clk_rst_n) begin
        split_line <= 'd0; split_half <= 1'b0; split_beats <= 'd0; split_stop <= 1'b0;
    end else if(sync_r2) begin
        split_line <= 'd0; split_half <= 1'b0; split_beats <= 'd0; split_stop <= 1'b0;
    end else if(rd_addr_en) begin
        split_half <= ~split_half;
        if(split_half) split_line <= split_line + 1'b1;
        split_beats <= split_beats + 25'd15;
        if(split_beats + 25'd15 >= burst_len_r) split_stop <= 1'b1;
    end
end
// The row offset is accumulated (+1920 B per line) instead of multiplied, so the
// AR address path is one add plus a mux and carries no DSP multiplier. split_line
// is kept only as a state/debug counter.
reg [AXI_ADDR_WIDTH-1:0] split_row_base = 'd0;
always @(posedge axi_clk or negedge axi_clk_rst_n)
begin
    if(!axi_clk_rst_n) split_row_base <= 'd0;
    else if(sync_r2) split_row_base <= 'd0;
    else if(rd_addr_en && split_half) split_row_base <= split_row_base + 32'd1920;
end
wire [AXI_ADDR_WIDTH-1:0] split_offset =
    split_row_base + (split_half ? 32'd960 : 32'd0);
wire [AXI_ADDR_WIDTH-1:0] split_araddr =
    (split_half ? split_addr_r : start_addr_r) + split_offset;
wire read_stop = split_enable_r ? split_stop : ddr_read_stop;


//=====================================================================================

//ddr alen process
always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
 	if( !axi_clk_rst_n )  							        total_burst_num <= 0;
 	else if(sync_r2)					                    total_burst_num <= 0;//( w_wr_sync0 )
 	else if( rd_addr_en )					                total_burst_num <= total_burst_num + 1'b1;
end 

always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
    if( !axi_clk_rst_n )								    burst_last <= 1'b0;
    else if( sync_r2 )					                    burst_last <= 1'b0;	
    else if(rd_addr_en && burst_num == total_burst_num+2 )  burst_last <= 1'b1;
    else if(rd_addr_en && burst_num == total_burst_num+1)   burst_last <= 1'b0;
end 

always @( posedge axi_clk or negedge axi_clk_rst_n  )
begin
    if( !axi_clk_rst_n ) 							            ddr_arlen 	<= BURST_LEN;//cfg_alen;
    else if( sync_r2 )						                    ddr_arlen 	<= first_burst_cnt;	 
    else if(rd_addr_en && burst_num == total_burst_num+2)		ddr_arlen	<= last_burst_cnt;//(rd_addr_en && burst_last) 
    else if( rd_addr_en )					                    ddr_arlen 	<= BURST_LEN;//cfg_alen_r;	
end


assign arapcmd  = 1'b0;  
assign arlock   = 1'b0;  
assign arqos    = 1'b0; 
assign arid     = 6'h00;
assign arsize   = AXSIZE_WTH;
assign arlen	= split_enable_r ? 8'd14 : ddr_arlen;
assign arburst  = 2'b01;
assign araddr   = split_enable_r ? split_araddr : ddr_addr;   
assign arprot       = 3'd2;
assign arcache 		= 4'd3; 


assign rd_addr_en = arvalid & arready;

always @(posedge axi_clk or negedge axi_clk_rst_n )											
begin
	if( !axi_clk_rst_n )							ddr_rd_valid <= 1'b0;
	else											ddr_rd_valid <= rvalid;				
end 			

always @( posedge axi_clk )
begin
    ddr_rd_data <= rdata;
end

//==========================================================================================
reg [1:0] state = 2'd0;
reg rd_req = 0;
reg ddr_read_stop = 'd0;
always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
    if( !axi_clk_rst_n )
        ddr_read_stop <= 1'b0;
    else if( sync_r2 )
        ddr_read_stop <= 1'b0;
    else if( rd_addr_en && (total_burst_num+1'b1==burst_num) )
        ddr_read_stop <= 1'b1;
end
assign bank_sw = read_stop;

always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
    if( !axi_clk_rst_n )
        rd_req <= 1'b0;
    else if(RD_FIFO_DEPTH < rd_fifo_wrusedw + BURST_LEN + 5)//( rd_fifo_wrusedw > 512  )//
        rd_req <= 1'b0;
    else 
        rd_req <= 1'b1;
end


always @( posedge axi_clk or negedge axi_clk_rst_n )
begin
    if( !axi_clk_rst_n ) begin
        arvalid <= 1'b0;
        rready <= 1'b0;
        state <= 'd0;
    end else if(rd_fifo_rst_p) begin
        state <= 2'd0;
        arvalid <= 1'b0;
        rready <= 1'b0;
    end else begin
        rready <= 1'b1;
        case(state )
        2'd0 : begin
            state <= sync_r2 ? 2'd1 : 2'd0;
        end
        2'd1 : begin
            if( rd_req ) begin
                state <= 2'd2;
                arvalid <= 1'b1;
            end
        end
        2'd2 : begin
            if( arready) begin
                state <= 2'd3;
                arvalid <= 1'b0;
                rready <= 1'b1;
            end
        end
        2'd3 : begin
            if( rvalid & rlast) begin//rready & 
                if( read_stop )
                    state <= 2'd0;
                else 
                    state <= 2'd1;
            end
        end
        default :;
    
        endcase
end
end


wire										rd_fifo_wr_full;
wire [RD_USEDW_WITH   :0] 					rd_fifo_rdusedw;
	DC_FIFO
# (
  	.FIFO_MODE  ( "Normal"    	 ), //"Normal"; //"ShowAhead"
    .DATA_WIDTH ( AXI_DATA_WIDTH ),
    .FIFO_DEPTH ( RD_FIFO_DEPTH  )
  ) u_rd_fifo(   
  //System Signal
  /*i*/.Reset   (	(~axi_clk_rst_n)	|| rd_fifo_rst_p		), 
  /*i*/.WrClk   (axi_clk			), 
  /*i*/.WrEn    (ddr_rd_valid		), 
  /*o*/.WrDNum  (rd_fifo_wrusedw	), 
  /*o*/.WrFull  (rd_fifo_wr_full 	), 
  /*i*/.WrData  (ddr_rd_data 		), 
  /*i*/.RdClk   (rd_fifo_rdclk		), 
  /*i*/.RdEn    (rd_fifo_rden		), 
  /*o*/.RdDNum  (rd_fifo_rdusedw	), 
  /*o*/.RdEmpty (rd_fifo_rdempty	), 
  /*o*/.RdData  (rd_fifo_rddata		)  
);

always @( posedge axi_clk )
begin
    rd_fifo_rdvalid <=   rd_fifo_rden;
end



endmodule