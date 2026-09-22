`timescale 1ns/1ps
module tb_requantizer_int32_to_uint8_pot;
    logic clk=0, rst=1, in_valid=0;
    logic signed [31:0] accumulator=0;
    logic [4:0] shift_amount=0;
    wire out_valid;
    wire [7:0] output_uint8;
    requantizer_int32_to_uint8_pot dut (.*);
    wire [7:0] comb_uint8;
    requantizer_int32_to_uint8_pot_comb comb_dut (
        .accumulator(accumulator),.shift_amount(shift_amount),.output_uint8(comb_uint8)
    );
    always #4 clk=~clk;

    // Independent sign/magnitude, division/modulo reference (no DUT internals).
    function automatic [7:0] reference_value(input logic signed [31:0] a, input integer k);
        longint signed magnitude, denominator, q, r, result_value;
        begin
            magnitude=longint'(a);
            if(magnitude<0) magnitude=-magnitude;
            denominator=64'sd1 << k;
            q=magnitude/denominator;
            r=magnitude%denominator;
            if(2*r>denominator || (2*r==denominator && q%2==1)) q=q+1;
            if(a<0) q=-q;
            result_value=q+128;
            if(result_value<0) reference_value=0;
            else if(result_value>255) reference_value=255;
            else reference_value=8'(result_value);
        end
    endfunction
    logic [2:0] expected_valid=0;
    logic [7:0] expected_data [0:2];
    logic [7:0] supplied_golden=0;
    logic external_golden=0;
    integer checked=0, exported=0;
    always @(posedge clk) begin
        if(!rst && in_valid && comb_uint8 !==
            (external_golden ? supplied_golden : reference_value(accumulator,integer'(shift_amount))))
            $fatal(1,"combinational quantizer mismatch ACC=%0d shift=%0d",accumulator,shift_amount);
        if(rst) expected_valid=0;
        else begin
            expected_valid={expected_valid[1:0],in_valid};
            expected_data[2]=expected_data[1];
            expected_data[1]=expected_data[0];
            expected_data[0]=external_golden ? supplied_golden : reference_value(accumulator,integer'(shift_amount));
        end
        #1;
        if(out_valid !== expected_valid[2]) $fatal(1,"valid/latency/reset mismatch");
        if(rst && output_uint8!==0) $fatal(1,"reset data mismatch");
        if(out_valid) begin
            if(output_uint8!==expected_data[2])
                $fatal(1,"data mismatch check=%0d expected=%0d actual=%0d",checked,expected_data[2],output_uint8);
            checked=checked+1;
        end
    end
    task automatic send(input logic signed [31:0] a, input integer k, input bit valid_bit);
        if(k<0 || k>31) $fatal(1,"unsupported test shift");
        @(negedge clk);
        accumulator=a; shift_amount=5'(k); in_valid=valid_bit;
    endtask
    longint signed d, v;
    logic [31:0] random_state=32'h39e70b12;
    string vector_file;
    integer fd, count, file_a, file_k, file_q;
    initial begin
        repeat(3) @(negedge clk); rst=0;
        // Every shift, signed endpoints, zero, half-way and saturation edges.
        for(integer k=0;k<=31;k++) begin
            send(32'sh80000000,k,1); send(32'sh7fffffff,k,1);
            send(0,k,1); send(-1,k,1); send(1,k,1);
            d=64'sd1<<k;
            for(integer q=-130;q<=130;q++) begin
                for(integer delta=-1;delta<=1;delta++) begin
                    v=longint'(q)*d+d/2+longint'(delta);
                    if(v>=-64'sd2147483648 && v<=64'sd2147483647) send(32'(v),k,1);
                end
            end
        end
        // Per-cycle changing shifts, deterministic random ACC and bubbles.
        for(integer i=0;i<20000;i++) begin
            random_state=random_state ^ (random_state<<13);
            random_state=random_state ^ (random_state>>17);
            random_state=random_state ^ (random_state<<5);
            send($signed(random_state),integer'(random_state[9:5]),i%7!=0);
        end
        // Reset must cancel in-flight transactions, including in_valid=1.
        send(7808,8,1); send(-256,9,1);
        @(negedge clk); rst=1;
        repeat(2) @(negedge clk);
        rst=0; in_valid=0;
        send(7808,8,1); send(-256,9,1); send(2368,7,1);
        // Optional software-export golden vectors: decimal ACC, k, UINT8.
        if($value$plusargs("VECTORS=%s",vector_file)) begin
            fd=$fopen(vector_file,"r");
            if(fd==0) $fatal(1,"cannot open vectors");
            while(!$feof(fd)) begin
                count=$fscanf(fd,"%d %d %d\n",file_a,file_k,file_q);
                if(count==3) begin
                    if(file_k<0 || file_k>31 || file_q<0 || file_q>255) $fatal(1,"invalid vector");
                    send(32'(file_a),file_k,1);
                    external_golden=1; supplied_golden=8'(file_q);
                    exported=exported+1;
                end else if(!$feof(fd)) $fatal(1,"malformed vector");
            end
            $fclose(fd);
            if(exported!=26944) $fatal(1,"incomplete exported sample: %0d",exported);
        end
        repeat(5) send(0,0,0);
        @(negedge clk);
        if(out_valid) $fatal(1,"pipeline failed to drain");
        $display("PASS PoT pipeline + combinational requantizers: checked=%0d exported=%0d shifts=0..31 ties/saturation/bubbles/reset",checked,exported);
        $finish;
    end
    initial begin #3000000; $fatal(1,"timeout"); end
endmodule
