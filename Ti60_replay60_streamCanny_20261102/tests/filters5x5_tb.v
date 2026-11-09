`timescale 1ns/1ps
module filters5x5_tb;
    localparam W=20,H=14;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,hs=0,vs=0;
    reg [11:0] x=0,y=0;
    reg [7:0] pixel=0;
    wire md,mh,mv,gd,gv;
    wire [11:0] mx,my,gx,gy;
    wire [7:0] median;
    wire [8:0] gaussian;
    median5x5 #(.WIDTH(W)) m(clk,rst_n,de,hs,vs,x,y,pixel,md,mh,mv,mx,my,median);
    gaussian5x5 #(.WIDTH(W)) g(clk,rst_n,de,vs,x,y,pixel,gd,gv,gx,gy,gaussian);
    reg [7:0] image[0:W*H-1];
    reg [7:0] em[0:W*H-1],eg[0:W*H-1];
    integer weights[0:4];integer values[0:24];
    integer frame,r,c,a,b,t,sum,index,seen_m=0,seen_g=0;
    reg [17:0] dp=0,hp=0,vp=0;
    reg [11:0] xp[0:17],yp[0:17];
    integer s;
    always @(posedge clk) if(rst_n) begin
        for(s=17;s>0;s=s-1)begin xp[s]=xp[s-1];yp[s]=yp[s-1];end
        xp[0]=x;yp[0]=y;dp={dp[16:0],de};hp={hp[16:0],hs};vp={vp[16:0],vs};
        #1;
        if({md,mh,mv}!=={dp[17],hp[17],vp[17]})$fatal(1,"median sync latency");
        if({gd,gv}!=={dp[3],vp[3]})$fatal(1,"Gaussian sync latency");
        if(md)begin
            if(mx!==xp[17] || my!==yp[17])$fatal(1,"median coordinates");
            if(median!==em[my*W+mx])$fatal(1,"median frame=%0d x=%0d y=%0d got=%0d expected=%0d",frame,mx,my,median,em[my*W+mx]);
            seen_m=seen_m+1;
        end
        if(gd)begin
            if(gx!==xp[3] || gy!==yp[3])$fatal(1,"Gaussian coordinates");
            if(gx>=4 && gy>=4)begin
                if(gaussian!=={1'b1,eg[gy*W+gx]})$fatal(1,"Gaussian pixel");
            end else if(gaussian[8]!==0)$fatal(1,"Gaussian incomplete window valid");
            seen_g=seen_g+1;
        end
    end
    initial begin
        weights[0]=1;weights[1]=4;weights[2]=6;weights[3]=4;weights[4]=1;
        repeat(4)@(negedge clk);rst_n=1;
        for(frame=0;frame<4;frame=frame+1)begin
            for(r=0;r<H;r=r+1)for(c=0;c<W;c=c+1)begin
                case(frame)
                    0:image[r*W+c]=8'd255;
                    1:image[r*W+c]=(r==7 && c==10)?255:0;
                    2:image[r*W+c]=((r*17+c*13)%11==0)?255:64;
                    3:image[r*W+c]=$random;
                endcase
            end
            for(r=0;r<H;r=r+1)for(c=0;c<W;c=c+1)begin
                em[r*W+c]=image[r*W+c];eg[r*W+c]=0;
                if(r>=4 && c>=4)begin
                    sum=0;
                    for(a=0;a<5;a=a+1)for(b=0;b<5;b=b+1)begin
                        values[a*5+b]=image[(r-4+a)*W+c-4+b];
                        sum=sum+values[a*5+b]*weights[a]*weights[b];
                    end
                    for(a=0;a<25;a=a+1)for(b=a+1;b<25;b=b+1)
                        if(values[a]>values[b])begin t=values[a];values[a]=values[b];values[b]=t;end
                    em[r*W+c]=values[12];eg[r*W+c]=(sum+128)>>8;
                end
            end
            @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;
            for(r=0;r<H;r=r+1)begin
                for(c=0;c<W;c=c+1)begin
                    @(negedge clk);de=1;x=c;y=r;pixel=image[r*W+c];
                    if((r+c)%7==0)begin @(negedge clk);de=0;repeat(2)@(negedge clk);end
                end
                @(negedge clk);de=0;hs=1;repeat(3)@(negedge clk);hs=0;
            end
            repeat(25)@(negedge clk);
        end
        if(seen_m!=4*W*H || seen_g!=4*W*H)$fatal(1,"lost pixels");
        $display("PASS: exact 5x5 median/Gaussian, borders, frame changes, gaps and sync");$finish;
    end
endmodule
