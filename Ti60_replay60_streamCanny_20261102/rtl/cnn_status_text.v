// Small combinational ASCII OSD; no video memory and no added sync latency.
module cnn_status_text #(parameter integer WIDTH=1920,HEIGHT=1080,
    parameter integer SCALE=WIDTH>=640 ? 4:1)
(input [11:0] x,y,input matched,valid_result,output ink,panel);
    localparam integer LEFT=(WIDTH-60*SCALE)/2,TOP=HEIGHT>=256 ? 64:16;
    wire [11:0] dx=x-LEFT,dy=y-TOP;
    wire [11:0] tx=dx/SCALE,ty=dy/SCALE;
    wire [79:0] message=matched ? "CNN TARGET":valid_result ? "CNN OTHER ":"CNN WAIT  ";
    wire [7:0] character=message[79-(tx/6)*8-:8];
    reg [34:0] glyph;
    always @* begin
        case(character)
        "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
        "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
        "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
        "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
        "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
        "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
        "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
        "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
        "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
        "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
        "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
        default:glyph=0;
        endcase
    end
    assign panel=x>=LEFT && dx<60*SCALE && y>=TOP && dy<9*SCALE;
    assign ink=panel && ty>=1 && ty<8 && (tx%6)<5 && glyph[34-(ty-1)*5-(tx%6)];
endmodule
