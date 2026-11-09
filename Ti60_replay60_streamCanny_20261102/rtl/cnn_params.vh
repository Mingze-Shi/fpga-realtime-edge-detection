// Generated from cnn/model_float.pt. Signed int8 weights, uint8 activations.
function signed [31:0] cnn_bias;
 input [1:0] layer; input [3:0] channel;
 begin cnn_bias=0; case ({layer,channel})
6'd0: cnn_bias=32'sh00000445;
6'd1: cnn_bias=32'shfffff226;
6'd2: cnn_bias=32'shffffe1fe;
6'd3: cnn_bias=32'sh00002463;
6'd16: cnn_bias=32'shffffee36;
6'd17: cnn_bias=32'sh00000c6d;
6'd18: cnn_bias=32'shfffff69f;
6'd19: cnn_bias=32'shfffff063;
6'd20: cnn_bias=32'sh00000792;
6'd21: cnn_bias=32'shfffff15a;
6'd22: cnn_bias=32'sh0000025b;
6'd23: cnn_bias=32'shfffff627;
6'd32: cnn_bias=32'shfffffa21;
6'd33: cnn_bias=32'shfffff8c2;
6'd34: cnn_bias=32'sh00001928;
6'd35: cnn_bias=32'sh000015f9;
6'd36: cnn_bias=32'shfffffc37;
6'd37: cnn_bias=32'shfffff893;
6'd38: cnn_bias=32'shfffff8e3;
6'd39: cnn_bias=32'shfffffbf1;
6'd48: cnn_bias=32'shfffffe57;
6'd49: cnn_bias=32'sh0000033d;
default: cnn_bias=0; endcase end endfunction
localparam integer CNN_SHIFT1=7;
localparam integer CNN_SHIFT2=9;
localparam integer CNN_SHIFT3=10;
