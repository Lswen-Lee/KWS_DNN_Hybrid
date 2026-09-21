`timescale 1ns/1ps
module tb_kws_postprocess_pot;
    logic clk=0,rst=1; always #4 clk=~clk;
    logic in_valid=0,in_frame_start=0,in_frame_last=0;
    logic signed [31:0] accumulator=0;
    logic [4:0] shift_amount=1;
    logic relu_enable=0,pool_enable=0;
    logic [7:0] pool_input_width=4,pool_input_height=4;
    logic [4:0] pool_input_channels=2;
    wire out_valid,out_frame_done;
    wire [7:0] output_uint8;
    wire [4:0] output_channel; wire [6:0] output_y,output_x;
    kws_postprocess_pot dut (.*);
    integer expected[0:31],pixels[0:31];
    integer received=0,total=0,checks=0;
    function automatic integer q(input integer i,input logic relu_on);
        integer v,mag,z;
        v=i*5-73; mag=v<0 ? -v : v; z=mag/2;
        if(mag%2==1 && z%2==1) z++;
        z=(v<0 ? -z : z)+128;
        return relu_on && z<128 ? 128 : z;
    endfunction
    always @(posedge clk) begin
        if(!rst && out_valid) begin
            if(received>=total || int'(output_uint8)!=expected[received] || out_frame_done!==(received==total-1))
                $fatal(1,"postprocess output=%0d expected=%0d idx=%0d done=%0d",output_uint8,expected[received],received,out_frame_done);
            if(pool_enable && (int'(output_channel)!=received/4 || int'(output_y)!=(received%4)/2 || int'(output_x)!=received%2))
                $fatal(1,"pool coordinates mismatch");
            received++; checks++;
        end
    end
    task automatic run_frame(input logic pool_on,relu_on);
        @(negedge clk); rst=1; in_valid=0;
        repeat(3) @(negedge clk); rst=0;
        pool_enable=pool_on; relu_enable=relu_on; received=0; total=pool_on ? 8 : 32;
        for(integer i=0;i<32;i++) pixels[i]=q(i,relu_on);
        if(pool_on) begin
            for(integer c=0;c<2;c++) for(integer y=0;y<2;y++) for(integer x=0;x<2;x++) begin
                expected[c*4+y*2+x]=0;
                for(integer dy=0;dy<2;dy++) for(integer dx=0;dx<2;dx++)
                    if(pixels[c*16+(y*2+dy)*4+x*2+dx]>expected[c*4+y*2+x])
                        expected[c*4+y*2+x]=pixels[c*16+(y*2+dy)*4+x*2+dx];
            end
        end else for(integer i=0;i<32;i++) expected[i]=pixels[i];
        for(integer i=0;i<32;i++) begin
            @(negedge clk); in_valid=1; accumulator=i*5-73; in_frame_start=i==0; in_frame_last=i==31;
            if(i%3==2) begin @(negedge clk); in_valid=0; end
        end
        @(negedge clk); in_valid=0;
        repeat(12) @(negedge clk);
        if(received!=total) $fatal(1,"missing frame outputs");
    endtask
    initial begin
        run_frame(0,0); run_frame(0,1); run_frame(1,0); run_frame(1,1);
        $display("PASS PoT postprocess %0d outputs, nearest-even/ReLU/pool/frame tags/bubbles",checks);
        $finish;
    end
endmodule
