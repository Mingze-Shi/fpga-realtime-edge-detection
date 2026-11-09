// Partial contour: 64x64 samples pooled into 16x16 cells, any detailed 6x6 patch.
module taffy_photo_match #(parameter integer ROI_X=448,ROI_Y=28,SAMPLE_STEP=16,
 // 以下为识别松紧度参数。数值越松，越容易判定成功，但也越容易误判。
 // 改 EDGE_THRESHOLD / CELL_MIN_EDGES 时必须用同样数值重跑
 // tools/make_contour_template.py，否则参考块与实时轮廓抽取规则不一致。
 parameter integer EDGE_THRESHOLD=24,   // 水平+垂直灰度和达到该值算轮廓点
 parameter integer CELL_MIN_EDGES=2,    // 4x4 采样格内至少几个轮廓点才置 1
 parameter integer MIN_DETAIL=6,        // 6x6 块内最少轮廓格数（低于则视为空白）
 parameter integer MAX_DETAIL=28,       // 6x6 块内最多轮廓格数（高于则视为糊成一片）
 parameter integer MIN_VARIATION=3,     // 水平/垂直方向最少变化次数（排除单条直线）
 parameter integer MAX_MISMATCH=8,      // 36 格中允许不同的最大格数：越小要求重合度越高
 parameter integer CONFIRM_FRAMES=3     // 连续多少帧通过才确认成功
)(
 input clk,rst_n,enable,de,vs,input [11:0] x,y,input [7:0] gray,
 output reg matched,result_valid,output reg [21:0] last_error
);
 localparam SIDE=64*SAMPLE_STEP,REFS=33;
 localparam IDLE=0,LOAD=1,DETAIL=2,READ_REF=3,COUNT_DIFF=4,COMPARE=5;
 wire [11:0] dx=x-ROI_X,dy=y-ROI_Y;
 wire sample=enable && de && x>=ROI_X && y>=ROI_Y && dx<SIDE && dy<SIDE &&
  dx%SAMPLE_STEP==SAMPLE_STEP/2 && dy%SAMPLE_STEP==SAMPLE_STEP/2;
 wire [5:0] sx=dx/SAMPLE_STEP,sy=dy/SAMPLE_STEP;
 reg vs_previous,malformed;
 reg [12:0] samples;
 reg [7:0] previous_gray,previous_row[0:63];
 reg [4:0] cell_count[0:15];
 reg [255:0] contour,frame_contour;
 wire [7:0] horizontal=sx==0 ? 8'd0:(gray>=previous_gray ? gray-previous_gray:previous_gray-gray);
 wire [7:0] vertical=sy==0 ? 8'd0:(gray>=previous_row[sx] ? gray-previous_row[sx]:previous_row[sx]-gray);
 wire is_edge=({1'b0,horizontal}+{1'b0,vertical})>=EDGE_THRESHOLD;
 wire [4:0] count_next=(sx[1:0]==0 && sy[1:0]==0) ? {4'b0,is_edge}:cell_count[sx[5:2]]+{4'b0,is_edge};
 reg [2:0] state;
 reg [1:0] streak;
 reg [2:0] detail_row;
 reg [5:0] detail_n,detail_h,detail_v;
 reg [2:0] distance_rows[0:5];
 integer ri;
 reg [3:0] scan_x,scan_y;
 reg [5:0] reference_index,best_distance;
 reg [35:0] patch,reference_q,references[0:REFS-1];
 initial $readmemh("assets/taffy/contour_patches.hex",references);
 always @(posedge clk) if(state==READ_REF) reference_q<=references[reference_index];
 wire [7:0] offset={scan_y,4'b0}+{4'b0,scan_x};
 wire [255:0] shifted=frame_contour>>offset;
 wire [35:0] next_patch={shifted[85:80],shifted[69:64],shifted[53:48],shifted[37:32],shifted[21:16],shifted[5:0]};
 // Count six bits with a balanced tree, then register each row result.
 function [2:0] pop6;
  input [5:0] value;reg [1:0] a,b,c;
  begin
   a={1'b0,value[0]}+{1'b0,value[1]};
   b={1'b0,value[2]}+{1'b0,value[3]};
   c={1'b0,value[4]}+{1'b0,value[5]};
   pop6={1'b0,a}+{1'b0,b}+{1'b0,c};
  end
 endfunction
 wire [35:0] detail_shifted=patch>>(detail_row*6);
 wire [5:0] row_bits=detail_shifted[5:0];
 wire [5:0] n_total=detail_n+pop6(row_bits);
 wire [5:0] h_total=detail_h+pop6({1'b0,(row_bits[4:0]^row_bits[5:1])});
 wire [5:0] v_total=detail_v+(detail_row<5 ? pop6(row_bits^detail_shifted[11:6]):3'd0);
 wire [35:0] diff_bits=patch^reference_q;
 wire [3:0] d01={1'b0,distance_rows[0]}+{1'b0,distance_rows[1]};
 wire [3:0] d23={1'b0,distance_rows[2]}+{1'b0,distance_rows[3]};
 wire [3:0] d45={1'b0,distance_rows[4]}+{1'b0,distance_rows[5]};
 wire [5:0] distance={2'b0,d01}+{2'b0,d23}+{2'b0,d45};
 task finish_result;
  input good;input [5:0] error;
  begin
   result_valid<=1;last_error<={16'b0,error};state<=IDLE;
   if(good) begin if(streak<3) streak<=streak+1'b1;matched<=streak>=CONFIRM_FRAMES-1;end
   else begin streak<=0;matched<=0;end
  end
 endtask
 task advance_patch;
  begin
   if(scan_x==10 && scan_y==10) finish_result(0,best_distance);
   else begin
    if(scan_x==10) begin scan_x<=0;scan_y<=scan_y+1'b1;end
    else scan_x<=scan_x+1'b1;
    state<=LOAD;
   end
  end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   vs_previous<=0;malformed<=0;samples<=0;previous_gray<=0;
   contour<=0;frame_contour<=0;state<=IDLE;streak<=0;
   scan_x<=0;scan_y<=0;reference_index<=0;patch<=0;best_distance<=36;
   matched<=0;result_valid<=0;last_error<=0;
   detail_row<=0;detail_n<=0;detail_h<=0;detail_v<=0;
   for(ri=0;ri<6;ri=ri+1) distance_rows[ri]<=0;
  end else begin
   vs_previous<=vs;
   if(!enable) begin
    samples<=0;malformed<=0;contour<=0;state<=IDLE;
    streak<=0;matched<=0;result_valid<=0;last_error<=0;
   end else if(vs && !vs_previous) begin
    if(samples==4096 && !malformed && state==IDLE) begin
     frame_contour<=contour;scan_x<=0;scan_y<=0;best_distance<=36;state<=LOAD;
    end else begin state<=IDLE;result_valid<=0;matched<=0;streak<=0;end
    samples<=0;malformed<=0;contour<=0;
   end else begin
    if(sample) begin
     if(samples>=4096 || {1'b0,sy,sx}!=samples) malformed<=1;
     if(samples<4097) samples<=samples+1'b1;
     previous_gray<=gray;previous_row[sx]<=gray;
     cell_count[sx[5:2]]<=count_next;
     if(sx[1:0]==3 && sy[1:0]==3) contour[{sy[5:2],sx[5:2]}]<=count_next>=CELL_MIN_EDGES;
    end
    case(state)
     LOAD: begin
      patch<=next_patch;detail_row<=0;detail_n<=0;detail_h<=0;detail_v<=0;state<=DETAIL;
     end
     DETAIL: begin
      detail_n<=n_total;detail_h<=h_total;detail_v<=v_total;
      if(detail_row==5) begin
       if(n_total>=MIN_DETAIL && n_total<=MAX_DETAIL && h_total>=MIN_VARIATION && v_total>=MIN_VARIATION) begin reference_index<=0;state<=READ_REF;end
       else advance_patch;
      end else detail_row<=detail_row+1'b1;
     end
     READ_REF: state<=COUNT_DIFF;
     COUNT_DIFF: begin
      for(ri=0;ri<6;ri=ri+1) distance_rows[ri]<=pop6(diff_bits[ri*6+:6]);
      state<=COMPARE;
     end
     COMPARE: begin
      if(distance<best_distance) best_distance<=distance;
      if(distance<=MAX_MISMATCH) finish_result(1,distance);
      else if(reference_index==REFS-1) advance_patch;
      else begin reference_index<=reference_index+1'b1;state<=READ_REF;end
     end
     default: state<=IDLE;
    endcase
   end
  end
 end
endmodule
