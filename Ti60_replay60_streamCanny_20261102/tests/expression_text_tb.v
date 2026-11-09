`timescale 1ns/1ps
module expression_text_tb;
reg[11:0]x,y;reg[2:0]cls;wire ink,panel;
cnn_expression_text #(.WIDTH(640),.HEIGHT(480),.SCALE(1))dut(x,y,cls,ink,panel);
reg masks[0:10239];integer c,xx,yy,checks=0;
initial begin
 $readmemh("assets/cnn_expression/label_masks.hex",masks);
 for(c=0;c<5;c=c+1)begin
 cls=c;
 for(yy=0;yy<16;yy=yy+1)for(xx=0;xx<128;xx=xx+1)begin
 x=256+xx;y=64+yy;#1;
 if(!panel||ink!==masks[c*2048+yy*128+xx])$fatal(1,"Chinese glyph mismatch");checks=checks+1;
 end end
 cls=7;x=256;y=64;#1;if(ink!==masks[0])$fatal(1,"invalid class fallback");
 x=255;#1;if(panel||ink)$fatal(1,"text outside panel");
 $display("PASS: Chinese expression OSD 10240 glyph pixels, all four names, unknown and invalid-ID fallback");$finish;
end
endmodule
