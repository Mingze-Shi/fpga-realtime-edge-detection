// Frame completion follows AXI B responses, not the early bank descriptor pulse.
// Four metadata entries only; no image storage. Sequence subtraction handles wrap.
// fault is re-evaluated at every frame end and cleared at every frame start, so a
// single lost B response cannot freeze the video path until reset.
module frame_write_commit #(parameter ADDR_WIDTH=32)(
    input clk,rst_n,aw_accept,b_accept,frame_data_end,frame_begin,
    input [ADDR_WIDTH-1:0] frame_addr,
    output reg committed,
    output reg [ADDR_WIDTH-1:0] committed_addr,
    output reg fault
);
    reg [31:0] aw_sequence,b_sequence;
    // Explicit scalar registers: Efinity can otherwise infer a whole BRAM for
    // a four-entry address array even when an array style attribute is present.
    reg [31:0] target0,target1,target2,target3;
    reg [ADDR_WIDTH-1:0] address0,address1,address2,address3;
    reg [1:0] head,tail;
    reg [2:0] used;
    wire [31:0] head_target=head==0 ? target0:head==1 ? target1:head==2 ? target2:target3;
    wire [ADDR_WIDTH-1:0] head_address=head==0 ? address0:head==1 ? address1:head==2 ? address2:address3;
    wire pop=used!=0 && $signed(b_sequence-head_target)>=0;
    wire push=frame_data_end && (used<4 || pop);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            aw_sequence<=0;b_sequence<=0;head<=0;tail<=0;used<=0;
            committed<=0;committed_addr<=0;fault<=0;
        end else begin
            committed<=0;
            if(aw_accept) aw_sequence<=aw_sequence+1'b1;
            if(b_accept) b_sequence<=b_sequence+1'b1;
            // Re-evaluated at every frame end (overflow still sets it), and cleared
            // at every frame start so a drained backlog recovers without a reset.
            if(frame_data_end) fault<=~push;
            else if(frame_begin) fault<=1'b0;
            if(push) begin
                case(tail)
                    0:begin target0<=aw_sequence+aw_accept;address0<=frame_addr;end
                    1:begin target1<=aw_sequence+aw_accept;address1<=frame_addr;end
                    2:begin target2<=aw_sequence+aw_accept;address2<=frame_addr;end
                    3:begin target3<=aw_sequence+aw_accept;address3<=frame_addr;end
                endcase
                tail<=tail+1'b1;
            end
            if(pop) begin
                committed<=1;committed_addr<=head_address;head<=head+1'b1;
            end
            case({push,pop})
                2'b10:used<=used+1'b1;
                2'b01:used<=used-1'b1;
                default:used<=used;
            endcase
        end
    end
endmodule
