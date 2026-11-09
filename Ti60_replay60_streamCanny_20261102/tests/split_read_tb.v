`timescale 1ns/1ps
// Checks the split read address sequence without a DDR model: only the AR
// channel matters. Split mode must emit one 15-beat burst per half line,
// alternating left slot / right slot; non-split mode must stay untouched.
module split_read_tb;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,start=0,split_enable=0;
reg [32:0] start_addr=0,split_addr=0;
reg [24:0] burst_len=30;
wire [32:0] araddr;wire [7:0] arlen;wire arvalid;reg arready=1;
wire [5:0] arid;wire [2:0] arsize;wire [1:0] arburst;wire arlock,arapcmd,arqos;wire [3:0] arcache;wire [2:0] arprot;
reg [511:0] rdata=0;reg rvalid=0,rlast=0;wire rready;wire [5:0] rid=0;reg [1:0] rresp=0;
wire bank_sw,rdvalid,rdempty;wire [511:0] rddata;wire rdswack=1'b1;
reg rd_fifo_rst_p=0;
wire [7:0] tblen;
reg [32:0] rec_addr[0:15];reg [7:0] rec_len[0:15];integer nrec=0;
integer i;
ddr_rd_buffer #(.BURST_LEN(127)) dut(
 .axi_clk(clk),.axi_clk_rst_n(rst_n),.start(start),.start_addr(start_addr),
 .burst_len(burst_len),.split_enable(split_enable),.split_addr(split_addr),
 .bank_sw_ack(rdswack),.bank_sw(bank_sw),
 .rd_fifo_rdclk(clk),.rd_fifo_rst_p(rd_fifo_rst_p),
 .rd_fifo_rdvalid(rdvalid),.rd_fifo_rddata(rddata),.rd_fifo_rdempty(rdempty),.rd_fifo_rden(1'b0),
 .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
 .arlock(arlock),.arvalid(arvalid),.arapcmd(arapcmd),.arqos(arqos),.arready(arready),
 .arcache(arcache),.arprot(arprot),
 .rid(rid),.rdata(rdata),.rlast(rlast),.rvalid(rvalid),.rready(rready),.rresp(rresp),
 .wr_fifo_rd_data_test(),.test_BURST_LEN(tblen));
// Minimal AXI read slave: one burst at a time, rlast after arlen+1 beats.
reg [7:0] beats=0;reg busy=0;
always @(posedge clk)begin
 if(arvalid&&arready)begin
  rec_addr[nrec]<=araddr;rec_len[nrec]<=arlen;nrec<=nrec+1;
  beats<=arlen;busy<=1;rvalid<=1;rlast<=(arlen==0);
 end else if(busy)begin
  if(rvalid&&rready)begin
   if(rlast)begin busy<=0;rvalid<=0;rlast<=0;end
   else begin beats<=beats-1'b1;rlast<=(beats==1);end
  end
 end
end
task tick;input integer q;begin repeat(q)@(posedge clk);end endtask
task frame;input split;input [32:0] a,b;input [24:0] len;begin
 split_enable=split;start_addr=a;split_addr=b;burst_len=len;nrec=0;
 @(negedge clk);rd_fifo_rst_p=1;tick(1);@(negedge clk);rd_fifo_rst_p=0;
 @(negedge clk);start=1;tick(1);@(negedge clk);start=0;
 tick(60);
end endtask
initial begin
 tick(3);rst_n=1;tick(3);
 frame(0,33'h1000,33'h2000,30);
 if(nrec!=1||rec_len[0]!=29||rec_addr[0]!==33'h1000)
  $fatal(1,"non-split burst wrong: n=%0d len=%0d addr=%h",nrec,rec_len[0],rec_addr[0]);
 frame(1,33'h1000,33'h2000,60);
 if(nrec!=4)$fatal(1,"split burst count %0d",nrec);
 if(rec_len[0]!=14||rec_addr[0]!==33'h1000)$fatal(1,"left half line0 %h",rec_addr[0]);
 if(rec_len[1]!=14||rec_addr[1]!==33'h2000+960)$fatal(1,"right half line0 %h",rec_addr[1]);
 if(rec_addr[2]!==33'h1000+1920)$fatal(1,"left half line1 %h",rec_addr[2]);
 if(rec_addr[3]!==33'h2000+1920+960)$fatal(1,"right half line1 %h",rec_addr[3]);
 $display("PASS: split read alternates 15-beat half-line bursts across two slots, non-split unchanged");
 $finish;
end
endmodule
