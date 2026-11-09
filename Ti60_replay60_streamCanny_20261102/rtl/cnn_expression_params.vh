// Generated from the completed augmented 240-epoch checkpoint.
function signed [31:0] expression_bias;
input [1:0] layer; input [3:0] channel;
begin expression_bias=0; case({layer,channel})
6'd0:expression_bias=32'sh000027b2;
6'd1:expression_bias=32'sh00008aa4;
6'd2:expression_bias=32'shffffa8b4;
6'd3:expression_bias=32'sh0000eab8;
6'd16:expression_bias=32'sh00000199;
6'd17:expression_bias=32'sh00000fe1;
6'd18:expression_bias=32'sh00000af5;
6'd19:expression_bias=32'sh00000ce0;
6'd20:expression_bias=32'shfffffeb9;
6'd21:expression_bias=32'sh000007b3;
6'd22:expression_bias=32'sh000009af;
6'd23:expression_bias=32'shfffff984;
6'd32:expression_bias=32'sh00000071;
6'd33:expression_bias=32'sh0000001c;
6'd34:expression_bias=32'shffffff3e;
6'd35:expression_bias=32'sh0000008e;
6'd36:expression_bias=32'shfffffe85;
6'd37:expression_bias=32'shffffffe0;
6'd38:expression_bias=32'shfffffc48;
6'd39:expression_bias=32'sh00000016;
6'd48:expression_bias=32'sh0000004f;
6'd49:expression_bias=32'shffffffe4;
6'd50:expression_bias=32'shffffffe3;
6'd51:expression_bias=32'shffffffa6;
6'd52:expression_bias=32'sh00000030;
default:expression_bias=0;endcase end endfunction
localparam integer CNN_SHIFT1=9;
localparam integer CNN_SHIFT2=10;
localparam integer CNN_SHIFT3=11;
localparam integer CNN_LOGIT_LEFT_SHIFT=2;
