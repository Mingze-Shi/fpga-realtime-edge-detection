

module bank_switch #(
		parameter FB_NUM = 2,
        parameter REPLAY_ENABLE = 0,
		parameter MAX_VID_WIDTH = 1920,
		parameter MAX_VID_HIGHT = 1080,
		parameter START_ADDR= 0,
		parameter VID_DATA_WIDTH= 16,
		parameter AXI_DATA_WIDTH = 256
		
)

(
input	wire		ddr_clk,//!时钟
input	wire		rst_n,//!复位，低电平有效

input	wire		wr_sw,//!写bank切换请求信号,电平有效
input	wire		rd_sw,//!读bank切换请求信号,电平有效
input wire freeze_request,
input wire replay_request,replay_select,
input wire write_active,write_committed,commit_fault,
input wire [1:0] writing_bank,committed_bank,
output wire freeze_active,replay_ready,replay_select_ack,

output	reg	[1:0]	wr_bank,
output	reg	[1:0]	rd_bank,
output	reg			rd_sw_ack,
output	reg			wr_sw_ack,
output	reg[31:0] 	rd_start_addr,
output	reg[31:0]	wr_start_addr




);                       
localparam AXI_BYTE_NUMBER = AXI_DATA_WIDTH/8  ;
localparam FRAME_LEN =   MAX_VID_WIDTH*MAX_VID_HIGHT*VID_DATA_WIDTH/8 + 32'h200;  

localparam FRAME_1ST_START_ADDR = START_ADDR;
localparam FRAME_2ND_START_ADDR = FRAME_LEN + START_ADDR ;

localparam FRAME_3RD_START_ADDR = FRAME_LEN+ FRAME_2ND_START_ADDR;


	
	generate 
	if( FB_NUM == 1 ) begin : one_fb 
        assign freeze_active=0;assign replay_ready=0;assign replay_select_ack=0;
		always @( posedge ddr_clk or negedge rst_n ) 
		begin 
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;
				wr_sw_ack <= 1'b0;
				rd_sw_ack <= 1'b0;     
				rd_start_addr <= FRAME_1ST_START_ADDR; 
				wr_start_addr <= FRAME_1ST_START_ADDR; 
			end else begin 
				wr_bank <= 2'b00;
				rd_bank <= 2'b00;
				wr_sw_ack <= wr_sw;
				rd_sw_ack <= rd_sw;   
				rd_start_addr <= FRAME_1ST_START_ADDR;
				wr_start_addr <= FRAME_1ST_START_ADDR;
			end 
		end 

	end else if( FB_NUM == 2 ) begin :tow_fb
        assign freeze_active=0;assign replay_ready=0;assign replay_select_ack=0;
		reg			bank_sw_en = 1'b0;
		reg			bank_sw_en_d1 = 1'b0;
		wire		pos_bank_sw_en;
		always @( posedge ddr_clk )
		begin
			bank_sw_en <= wr_sw & rd_sw;
			bank_sw_en_d1 <= bank_sw_en;
		end
		assign pos_bank_sw_en = {bank_sw_en_d1,bank_sw_en} == 2'b01;
		
		always @( posedge ddr_clk or negedge rst_n)
		begin
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;      
				wr_start_addr <= FRAME_1ST_START_ADDR; 
				rd_start_addr <= FRAME_2ND_START_ADDR; 
			end else if( pos_bank_sw_en ) begin//必须两个bank同时切换
				wr_bank[0] <= ~wr_bank[0];
				rd_bank[0] <= wr_bank[0];
				rd_bank[1] <= 1'b0;
				wr_bank[1] <= 1'b0;      
				wr_start_addr <= wr_bank[0] ? FRAME_1ST_START_ADDR : FRAME_2ND_START_ADDR;
				rd_start_addr <= wr_bank[0] ? FRAME_2ND_START_ADDR : FRAME_1ST_START_ADDR; 
			end
		end
		
		always @( posedge ddr_clk )
		begin
			wr_sw_ack	 <= pos_bank_sw_en;
			rd_sw_ack	 <= pos_bank_sw_en;
		end
		
		
	end else if( FB_NUM == 3 ) begin :three_fb
		wire pos_wr_sw_en;
		wire pos_rd_sw_en;
		// Freeze the DDR read descriptor, not video clocks or AXI transactions.
		// The held read bank is never returned to the writer's spare pool.
		(* async_reg = "true", syn_preserve = 1 *) reg freeze_meta, freeze_sync;
        (* async_reg = "true" *) reg replay_meta,replay_sync,select_meta,select_sync;
        reg replay_active,select_active;
        reg [1:0] saved0,saved1;
        reg [2:0] committed_mask;
        assign freeze_active=freeze_sync;
        assign replay_ready=REPLAY_ENABLE && replay_active && !commit_fault;
        assign replay_select_ack=select_active;
		reg rd_pending;
		always @(posedge ddr_clk or negedge rst_n) begin
			if (!rst_n) begin
				freeze_meta <= 1'b0;
				freeze_sync <= 1'b0;
                replay_meta<=0;replay_sync<=0;select_meta<=0;select_sync<=0;
				rd_pending <= 1'b0;
			end else begin
				freeze_meta <= freeze_request;
				freeze_sync <= freeze_meta;
                replay_meta<=REPLAY_ENABLE && replay_request;replay_sync<=replay_meta;
                select_meta<=replay_select;select_sync<=select_meta;
				// Preserve a coincident read request across writer-priority arbitration.
				if (pos_rd_sw_en && pos_wr_sw_en) rd_pending <= 1'b1;
				else if (!pos_wr_sw_en && (pos_rd_sw_en || rd_pending)) rd_pending <= 1'b0;
			end
		end
		reg	[1:0] 	dirt_bank = 2'b10;
		reg			dirt_en = 1'b1;
		reg	[1:0]	clean_bank = 2'b00;
		reg			clean_en = 1'b0;
		reg			wr_sw_d1 = 1'b0;
		reg			rd_sw_d1 = 1'b0;
		always @( posedge ddr_clk )
		begin
				wr_sw_d1 <= wr_sw;
				rd_sw_d1 <= rd_sw;
		end
		assign pos_wr_sw_en = {wr_sw_d1,wr_sw} == 2'b01;
		assign pos_rd_sw_en = {rd_sw_d1,rd_sw} == 2'b01;
		
		always @( posedge ddr_clk )
		begin
			wr_sw_ack <= pos_wr_sw_en;
			rd_sw_ack <= pos_rd_sw_en;
		end
		always @( posedge ddr_clk or negedge rst_n)
		begin
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;
				dirt_bank <= 2'b10;
				dirt_en <= 1'b1;
				clean_en <= 1'b0;
				clean_bank <= 2'b00;    
                replay_active<=0;select_active<=0;saved0<=0;saved1<=0;committed_mask<=0;
				
				wr_start_addr <= FRAME_1ST_START_ADDR;
				rd_start_addr <= FRAME_2ND_START_ADDR; 
			end else begin
                if(REPLAY_ENABLE) begin
                    if(write_committed && committed_bank<3) committed_mask[committed_bank]<=1;
                    if(write_active && writing_bank<3) committed_mask[writing_bank]<=0;
                    if(!replay_active && replay_sync && freeze_sync && !commit_fault &&
                       clean_en && !dirt_en && rd_bank!=clean_bank &&
                       wr_bank!=rd_bank && wr_bank!=clean_bank &&
                       committed_mask[rd_bank] && committed_mask[clean_bank]) begin
                        saved0<=rd_bank;saved1<=clean_bank;
                        replay_active<=1;select_active<=0;
                    end
                end
                if( pos_wr_sw_en ) begin
						
				if( dirt_en ) begin
						wr_bank <= dirt_bank; 
						wr_start_addr <= (dirt_bank ==  2'b00) ? FRAME_1ST_START_ADDR :((dirt_bank == 2'b01)? FRAME_2ND_START_ADDR : FRAME_3RD_START_ADDR );
						clean_bank <= wr_bank;
						clean_en <= 1'b1;
						dirt_en	<= 1'b0;
				end else begin
						wr_bank <= wr_bank;
						clean_en <= clean_en;
				end
						
			end else if( (pos_rd_sw_en || rd_pending) && !freeze_sync && !replay_active && !replay_sync ) begin
				if( clean_en ) begin
						rd_bank <= clean_bank;   
						rd_start_addr <= (clean_bank ==  2'b00) ? FRAME_1ST_START_ADDR :((clean_bank == 2'b01)? FRAME_2ND_START_ADDR : FRAME_3RD_START_ADDR );
						dirt_bank <= rd_bank;
						dirt_en <= 1'b1;
						clean_en <= 1'b0;
				end else begin
						rd_bank <= rd_bank;
						dirt_en <= dirt_en;
				end
				clean_en <= 1'b0;
			end
                if(replay_active && (pos_rd_sw_en || rd_pending)) begin
                    if(!replay_sync) begin
                        // Restore original pool ownership before normal reads resume.
                        rd_bank<=saved0;
                        rd_start_addr<=saved0==0 ? FRAME_1ST_START_ADDR :
                            saved0==1 ? FRAME_2ND_START_ADDR:FRAME_3RD_START_ADDR;
                        clean_bank<=saved1;clean_en<=1;dirt_en<=0;
                        replay_active<=0;select_active<=0;
                    end else if(select_active!=select_sync && !commit_fault) begin
                        select_active<=select_sync;
                        rd_bank<=select_sync ? saved1:saved0;
                        rd_start_addr<=(select_sync ? saved1:saved0)==0 ? FRAME_1ST_START_ADDR :
                            (select_sync ? saved1:saved0)==1 ? FRAME_2ND_START_ADDR:FRAME_3RD_START_ADDR;
                    end
                end
            end
		end
						
	end
	endgenerate


endmodule
