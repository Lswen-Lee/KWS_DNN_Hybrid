`timescale 1ns/1ps
// Protocol unit test: endpoints are explicit stimulus, NOT a DCIM arithmetic
// model. Full numerical RAM/DCIM/PoT integration is a separate S5-C gate.
module tb_dcim_layer_controller;
    logic clk=0, rst=1;
    always #4 clk=~clk;
    logic cmd_valid=0, cmd_ready, cmd_relu_enable=1;
    logic [2:0] cmd_layer_id=1, resident_layer_id=1;
    logic [14:0] cmd_src_base=0, cmd_dst_base=1000;
    logic [7:0] cmd_width=3, cmd_height=3;
    logic resident_valid=1, busy, done, error, fault;
    logic reader_cmd_valid, reader_cmd_ready=0, reader_done=0, reader_error=0;
    logic [14:0] reader_base;
    logic [7:0] reader_width, reader_height, reader_x, reader_y;
    logic reader_out_valid=0, reader_out_last=0, reader_out_ready;
    logic dcim_activation_valid, dcim_activation_ready=0;
    logic dcim_patch_valid, dcim_patch_ready=0, dcim_patch_done=0, dcim_error=0;
    logic raw_path_enable, dcim_source_error;
    logic [2:0] post_layer_id;
    logic post_relu_enable, post_valid=0, post_last=0, post_error=0, post_ready;
    logic [4:0] post_channel=0;
    logic writer_cmd_valid, writer_cmd_ready=0, writer_in_ready=0, writer_done=0, writer_error=0;
    logic [14:0] writer_base;
    logic [7:0] writer_width, writer_height, writer_x, writer_y;
    logic [5:0] writer_channel;
    logic writer_in_valid;
    dcim_layer_controller dut (.*);

    integer successes=0, rejections=0, faults=0, resets=0;
    integer patch_commands=0, reader_commands=0, writer_commands=0, activations=0, results=0;
    integer expected_x=0, expected_y=0;
    integer w=3, h=3, src=0, dst=1000, layer=1;
    bit old_done=0;
    bit stall_mode=1;
    bit withhold_reader_done=0, probe_mode=0;
    integer boundary_mode=0, nonrun_faults=0, duplicate_faults=0, excess_faults=0;
    integer boundaries=0, busy_probes=0, layer_commands=0;
    always @(posedge clk) if (!rst) begin
        if (done && (error || fault || old_done)) $fatal(1,"done pulse/error violation");
        old_done <= done;
        if(cmd_valid && cmd_ready) layer_commands++;
        if (writer_cmd_valid && writer_cmd_ready) begin
            writer_commands++;
            if (int'(writer_base)!=dst || int'(writer_width)!=w-2 || int'(writer_height)!=h-2)
                $fatal(1,"writer configuration mismatch");
        end
        if (dcim_patch_valid && dcim_patch_ready) patch_commands++;
        if (reader_cmd_valid && reader_cmd_ready) begin
            reader_commands++;
            if (int'(reader_base)!=src || int'(reader_width)!=w || int'(reader_height)!=h ||
                int'(reader_x)!=expected_x + ($test$plusargs("CORRUPT_EXPECTATION") ? 1 : 0) ||
                int'(reader_y)!=expected_y)
                $fatal(1,"reader coordinates mismatch");
        end
        if (dcim_activation_valid && dcim_activation_ready) activations++;
        if ((reader_out_valid && reader_out_ready) != (dcim_activation_valid && dcim_activation_ready))
            $fatal(1,"activation handshake mismatch");
        if ((post_valid && post_ready) != (writer_in_valid && writer_in_ready))
            $fatal(1,"result handshake mismatch");
        if (writer_in_valid && writer_in_ready) begin
            if (int'(writer_x)!=expected_x + ($test$plusargs("CORRUPT_WRITER") ? 1 : 0) ||
                int'(writer_y)!=expected_y || writer_channel!={1'b0,post_channel})
                $fatal(1,"output coordinate/tag mismatch");
            results++;
        end
        if (busy && raw_path_enable && (int'(post_layer_id)!=layer || !post_relu_enable))
            $fatal(1,"saved layer configuration mismatch");
    end

    task automatic tick(input integer n);
        repeat(n) @(negedge clk);
    endtask
    task automatic reset_all;
        @(negedge clk); rst=1; cmd_valid=0;
        reader_cmd_ready=0; reader_done=0; reader_error=0; reader_out_valid=0; reader_out_last=0;
        dcim_activation_ready=0; dcim_patch_ready=0; dcim_patch_done=0; dcim_error=0;
        post_valid=0; post_last=0; post_error=0; post_channel=0;
        writer_cmd_ready=0; writer_in_ready=0; writer_done=0; writer_error=0;
        resident_valid=1; resident_layer_id=3'(layer); old_done=0;
        tick(3); rst=0; tick(2);
        if (!cmd_ready || busy || done || fault || error) $fatal(1,"reset failed");
    endtask
    task automatic command;
        @(negedge clk);
        cmd_width=8'(w); cmd_height=8'(h); cmd_src_base=15'(src); cmd_dst_base=15'(dst);
        cmd_layer_id=3'(layer); cmd_valid=1;
        while(!cmd_ready) tick(1);
        tick(1); cmd_valid=0;
        // Mutate public configuration after handshake: DUT must use saved values.
        cmd_width=255; cmd_height=255; cmd_src_base=32767; cmd_dst_base=32767; cmd_layer_id=7;
    endtask
    // A busy command is deliberately withdrawn before IDLE; holding valid
    // until IDLE would correctly request a NEW command and is not a fault.
    task automatic busy_probe;
        integer before_commands;
        before_commands=layer_commands;
        cmd_valid=1; cmd_width=255; cmd_height=0; cmd_layer_id=7;
        cmd_src_base=32767;cmd_dst_base=32767;
        repeat(3) begin
            if(!busy || cmd_ready) $fatal(1,"busy command accepted");
            tick(1);
        end
        cmd_valid=0;
        if(layer_commands!=before_commands) $fatal(1,"busy command count changed");
        busy_probes++;
    endtask
    task automatic start_writer;
        while(!writer_cmd_valid) tick(1);
        if(probe_mode) busy_probe();
        tick(3);
        if (!writer_cmd_valid || dcim_patch_valid) $fatal(1,"writer command not held");
        writer_cmd_ready=1; tick(1); writer_cmd_ready=0;
    endtask
    task automatic start_patch;
        while(!dcim_patch_valid) tick(1);
        if(probe_mode) busy_probe();
        tick(2);
        if (!dcim_patch_valid || reader_cmd_valid) $fatal(1,"patch command not held");
        dcim_patch_ready=1; tick(1); dcim_patch_ready=0;
        while(!reader_cmd_valid) tick(1);
        if(probe_mode) busy_probe();
        tick(2);
        if (!reader_cmd_valid) $fatal(1,"reader command not held");
        reader_cmd_ready=1; tick(1); reader_cmd_ready=0;
    endtask
    task automatic send_input(input bit same_edge_done);
        for(integer i=0;i<108;i++) begin
            reader_out_valid=1; reader_out_last=(i==107);
            dcim_activation_ready=0;
            if(stall_mode && i%17==0) tick(2);
            dcim_activation_ready=1;
            if(same_edge_done && i==107) reader_done=1;
            tick(1);
        end
        reader_out_valid=0; reader_out_last=0; dcim_activation_ready=0; reader_done=0;
        if(!same_edge_done && !withhold_reader_done) begin tick(2); reader_done=1; tick(1); reader_done=0; end
    endtask
    task automatic send_results(input integer done_order, input bit early_writer);
        if(done_order==0) begin dcim_patch_done=1; tick(1); dcim_patch_done=0; end
        for(integer c=0;c<12;c++) begin
            post_valid=1; post_channel=5'(c); post_last=(c==11); writer_in_ready=0;
            if(stall_mode) tick(c==11 ? 5 : 1);
            if(dcim_patch_valid || done || int'(writer_x)!=expected_x || int'(writer_y)!=expected_y)
                $fatal(1,"advanced coordinates before output drain");
            writer_in_ready=1;
            if(c==11 && done_order==1) dcim_patch_done=1;
            if(c==11 && early_writer) writer_done=1;
            tick(1); dcim_patch_done=0; writer_done=0;
        end
        post_valid=0; post_last=0; writer_in_ready=0;
        if(done_order==2) begin tick(3); dcim_patch_done=1; tick(1); dcim_patch_done=0; end
    endtask
    task automatic run_layer(input integer iw, ih, ilayer, input bit early_writer);
        integer before_p, before_r, before_a, before_o, before_w;
        w=iw; h=ih; layer=ilayer; src=0; dst=w*h*12;
        case(boundary_mode)
            1: dst=32768-(w-2)*(h-2)*12;
            2: begin src=32768-w*h*12;dst=0; end
            3: begin src=(w-2)*(h-2)*12;dst=0; end
            default: ;
        endcase
        reset_all();
        before_p=patch_commands; before_r=reader_commands; before_a=activations;
        before_o=results; before_w=writer_commands;
        command(); if(probe_mode) busy_probe(); start_writer();
        for(integer y=0;y<h-2;y++) for(integer x=0;x<w-2;x++) begin
            expected_x=x; expected_y=y;
            start_patch(); if(probe_mode) busy_probe(); send_input(((x+y)%2)==0);
            send_results((x+y)%3,early_writer && x==w-3 && y==h-3);
        end
        if(!early_writer) begin
            if(probe_mode) busy_probe();
            tick(5); if(done || !busy) $fatal(1,"layer done before RAM commit");
            writer_done=1; tick(1); writer_done=0;
        end
        while(!done) tick(1);
        if(patch_commands-before_p!=(w-2)*(h-2) || reader_commands-before_r!=(w-2)*(h-2) ||
           activations-before_a!=(w-2)*(h-2)*108 || results-before_o!=(w-2)*(h-2)*12 ||
           writer_commands-before_w!=1) $fatal(1,"layer transaction counts mismatch");
        tick(2); if(done || busy) $fatal(1,"not idle after done");
        successes++;
        if(boundary_mode!=0) boundaries++;
    endtask
    // V1: reach the target through public transactions; hierarchy is read-only
    // to prove the intended state was actually exercised (never force state).
    task automatic nonrun_fault(input integer phase, kind);
        integer before_a,before_o,before_p,before_r,before_w;
        w=3;h=3;src=0;dst=1000;layer=1;reset_all();expected_x=0;expected_y=0;
        command(); while(!writer_cmd_valid) tick(1);
        if(phase>=1) start_writer();
        if(phase==2) begin dcim_patch_ready=1;tick(1);dcim_patch_ready=0; end
        if(phase==3) begin start_patch();send_input(0);send_results(0,0); end
        case(phase)
            0: if(dut.state!=dut.START_WRITER) $fatal(1,"V1 missed START_WRITER");
            1: if(dut.state!=dut.START_PATCH) $fatal(1,"V1 missed START_PATCH");
            2: if(dut.state!=dut.START_READER) $fatal(1,"V1 missed START_READER");
            3: if(dut.state!=dut.DRAIN_LAYER) $fatal(1,"V1 missed DRAIN_LAYER");
        endcase
        before_a=activations;before_o=results;before_p=patch_commands;
        before_r=reader_commands;before_w=writer_commands;
        // Ready high makes illegal command/data acceptance observable.
        writer_cmd_ready=1;reader_cmd_ready=1;dcim_patch_ready=1;writer_in_ready=1;
        case(kind)
            0: reader_error=1;
            1: writer_error=1;
            2: dcim_error=1;
            3: resident_valid=0;
            4: post_valid=1;
        endcase
        tick(1);
        if(!fault || !error || done || !dcim_source_error || activations!=before_a || results!=before_o ||
           patch_commands!=before_p || reader_commands!=before_r || writer_commands!=before_w)
            $fatal(1,"V1 failure phase=%0d kind=%0d",phase,kind);
        tick(3);
        if(!fault || error || done || cmd_ready || raw_path_enable) $fatal(1,"V1 fault not sticky");
        nonrun_faults++;
    endtask
    task automatic duplicate_or_excess(input integer kind);
        integer before_a,before_o;
        w=3;h=3;src=0;dst=1000;layer=1;reset_all();expected_x=0;expected_y=0;
        command();start_writer();start_patch();
        withhold_reader_done=(kind==3);
        send_input(0);withhold_reader_done=0;
        case(kind)
            0: begin
                if(!dut.reader_done_seen) $fatal(1,"V2 Reader first done not seen");
            end
            1: begin
                dcim_patch_done=1;tick(1);dcim_patch_done=0;tick(1);
                if(!dut.dcim_done_seen) $fatal(1,"V2 DCIM first done not seen");
            end
            2: begin
                send_results(1,1);
                if(dut.state!=dut.DRAIN_LAYER || !dut.writer_done_seen)
                    $fatal(1,"V2 Writer first done not saved in DRAIN");
            end
            3: if(dut.activation_count!=108 || dut.reader_done_seen)
                   $fatal(1,"V3 activation setup incorrect");
            4: begin
                send_results(3,0); // No DCIM done: remain RUN with 12 accepted outputs.
                if(dut.state!=dut.RUN_PATCH || dut.result_count!=12 || dut.dcim_done_seen)
                    $fatal(1,"V3 result setup incorrect");
            end
        endcase
        before_a=activations;before_o=results;
        case(kind)
            0: reader_done=1;
            1: dcim_patch_done=1;
            2: writer_done=1; // Consecutive high cycles are duplicate done events.
            3: begin reader_out_valid=1;reader_out_last=0;dcim_activation_ready=1; end
            4: begin post_valid=1;post_channel=12;post_last=0;writer_in_ready=1; end
        endcase
        tick(1);
        if(!fault || !error || done || activations!=before_a || results!=before_o)
            $fatal(1,"V2/V3 not rejected kind=%0d",kind);
        tick(3);
        if(!fault || error || done || raw_path_enable || cmd_ready) $fatal(1,"V2/V3 fault not sticky");
        if(kind<3) duplicate_faults++;else excess_faults++;
    endtask
    task automatic reject_config(input integer kind);
        integer before_w;
        w=3; h=3; src=0; dst=1000; layer=1; reset_all();
        case(kind)
            0: resident_valid=0;
            1: resident_layer_id=2;
            2: layer=0;
            3: w=2;
            4: h=0;
            5: dst=50;
            6: src=32700;
            7: dst=32760;
            8: begin w=255; h=255; end
            9: dcim_error=1;
        endcase
        before_w=writer_commands; command();
        while(!error) tick(1);
        if(fault || busy || !cmd_ready || writer_cmd_valid || reader_cmd_valid || dcim_patch_valid ||
           writer_commands!=before_w) $fatal(1,"invalid configuration activated endpoints");
        rejections++;
    endtask
    task automatic inject_fault(input integer kind);
        integer before_a,before_o;
        w=3; h=3; src=0; dst=1000; layer=1; reset_all();
        expected_x=0; expected_y=0; command(); start_writer(); start_patch();
        if(kind>=3 && kind<=6) send_input(0);
        before_a=activations; before_o=results;
        case(kind)
            0: begin reader_out_valid=1; reader_out_last=1; dcim_activation_ready=1; end
            1: reader_done=1;
            2: dcim_patch_done=1;
            3: begin post_valid=1; post_channel=1; writer_in_ready=1; end
            4: begin post_valid=1; post_channel=0; post_last=1; writer_in_ready=1; end
            5: begin post_valid=1; post_error=1; writer_in_ready=1; end
            6: writer_done=1;
            7: resident_valid=0;
            8: reader_error=1;
            9: writer_error=1;
            10: dcim_error=1;
        endcase
        tick(1);
        if(!fault || !error || !dcim_source_error || activations!=before_a || results!=before_o)
            $fatal(1,"fault not rejected before handshake kind=%0d",kind);
        tick(3);
        if(!fault || error || done || cmd_ready || raw_path_enable || writer_in_valid)
            $fatal(1,"fault must latch until shared reset");
        faults++;
    endtask
    initial begin
        run_layer(3,3,1,1); // writer_done concurrent with last accepted result
        run_layer(5,4,2,0); // done before/same/after final post result
        run_layer(30,15,1,0); // complete Conv2 control geometry
        run_layer(14,6,2,0); // complete Conv3 control geometry
        for(integer i=0;i<10;i++) reject_config(i);
        for(integer i=0;i<11;i++) inject_fault(i);
        // Reset in each public operation phase; no hierarchical state forcing.
        for(integer phase=0;phase<7;phase++) begin
            w=3;h=3;src=0;dst=1000;layer=1;reset_all(); expected_x=0;expected_y=0;
            command();
            if(phase>=1) while(!writer_cmd_valid) tick(1);
            if(phase>=2) start_writer();
            if(phase>=3) begin
                while(!dcim_patch_valid) tick(1);
                dcim_patch_ready=1;tick(1);dcim_patch_ready=0;
            end
            if(phase>=4) begin
                while(!reader_cmd_valid) tick(1);
                reader_cmd_ready=1;tick(1);reader_cmd_ready=0;
            end
            if(phase>=5) send_input(0);
            if(phase>=6) send_results(0,0);
            reset_all();tick(5);
            if(done || busy || writer_cmd_valid || dcim_patch_valid || reader_cmd_valid)
                $fatal(1,"stale transaction after reset");
            resets++;
        end
        stall_mode=0;
        run_layer(3,3,1,0); // post-reset/fault recovery, no data-path stalls
        for(integer p=0;p<4;p++) for(integer k=0;k<5;k++) nonrun_fault(p,k);
        for(integer k=0;k<5;k++) duplicate_or_excess(k);
        for(integer b=1;b<=3;b++) begin boundary_mode=b;run_layer(3,3,1,0); end
        boundary_mode=0;probe_mode=1;run_layer(3,3,1,0);probe_mode=0;
        if(nonrun_faults!=20 || duplicate_faults!=3 || excess_faults!=2 || boundaries!=3 || busy_probes!=6)
            $fatal(1,"V1-V5 coverage count mismatch");
        $display("PASS extensions nonrun_faults=%0d duplicate_done=%0d excess=%0d boundaries=%0d busy_probes=%0d",
                 nonrun_faults,duplicate_faults,excess_faults,boundaries,busy_probes);
        $display("PASS dcim_layer_controller layers=%0d rejected=%0d faults=%0d resets=%0d patches=%0d outputs=%0d",
                 successes,rejections,faults,resets,patch_commands,results);
        $finish;
    end
    initial begin #20000000; $fatal(1,"controller watchdog"); end
endmodule
