// tb_crossbar_switch.sv
//   Testbench for crossbar_switch. Because the DUT is purely combinational,
//   all checks are done with a small #1 propagation delay after driving inputs —
//   no clock needed for correctness. 
//   Tests: each one-hot grant selects the correct FIFO for every
//   output port, all 5 output ports route simultaneously and independently,
//   zero-grant (no bits set) outputs zero data, and changing grants mid-sim
//   immediately propagates.

`timescale 1ns / 1ps

module tb_crossbar_switch;

    parameter DATA_WIDTH = 34;

    logic [4:0][DATA_WIDTH-1:0] fifo_data_in;
    logic [4:0][4:0]            arbiter_sel;
    logic [4:0][DATA_WIDTH-1:0] router_data_out;

    integer pass_count, fail_count;
    integer i, j;

    crossbar_switch #(.DATA_WIDTH(DATA_WIDTH)) dut (
        .fifo_data_in(fifo_data_in),
        .arbiter_sel(arbiter_sel),
        .router_data_out(router_data_out)
    );

    task check;
        input [DATA_WIDTH-1:0] expected, actual;
        input string name;
        begin
            if (expected === actual) begin
                $display("PASS  [%0t] %s : got %0h", 
                          $time, name, actual);
                pass_count++;
            end else begin
                $display("FAIL  [%0t] %s : expected %0h, got %0h", 
                          $time, name, expected, actual);
                fail_count++;
            end
        end
    endtask

    task drive_all_zero_grants;
        begin
            for (int k = 0; k < 5; k++) begin
                arbiter_sel[k] = 5'b00000;
            end
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;

        fifo_data_in[0] = 34'h0_AAAA_0000;
        fifo_data_in[1] = 34'h1_BBBB_1111;
        fifo_data_in[2] = 34'h2_CCCC_2222;
        fifo_data_in[3] = 34'h3_DDDD_3333;
        fifo_data_in[4] = 34'h0_EEEE_4444;

        drive_all_zero_grants();
        #1;

        // 1. Exhaustive Sweep: Test EVERY output against EVERY input
        for (i = 0; i < 5; i++) begin
            for (j = 0; j < 5; j++) begin
                drive_all_zero_grants();
                arbiter_sel[i] = (1 << j);
                #1;
                check(fifo_data_in[j], router_data_out[i], $sformatf("Sweep, out%0d = in%0d", i, j));
            end
        end

        // 2. All 5 outputs active simultaneously (no conflicts — bijection)
        for (i = 0; i < 5; i++) begin
            arbiter_sel[i] = (1 << i);
        end
        #1;
        check(fifo_data_in[0], router_data_out[0], "sim, out0 = in0");
        check(fifo_data_in[1], router_data_out[1], "sim, out1 = in1");
        check(fifo_data_in[2], router_data_out[2], "sim, out2 = in2");
        check(fifo_data_in[3], router_data_out[3], "sim, out3 = in3");
        check(fifo_data_in[4], router_data_out[4], "sim, out4 = in4");

        // 3. Rotate grants
        arbiter_sel[0] = 5'b10000;
        arbiter_sel[1] = 5'b00001;
        arbiter_sel[2] = 5'b00010;
        arbiter_sel[3] = 5'b00100;
        arbiter_sel[4] = 5'b01000;
        #1;
        check(fifo_data_in[4], router_data_out[0], "rotate, out0 = in4");
        check(fifo_data_in[0], router_data_out[1], "rotate, out1 = in0");
        check(fifo_data_in[1], router_data_out[2], "rotate, out2 = in1");
        check(fifo_data_in[2], router_data_out[3], "rotate, out3 = in2");
        check(fifo_data_in[3], router_data_out[4], "rotate, out4 = in3");

        // 4. Zero grant -> Zero output
        drive_all_zero_grants(); #1;
        for (i = 0; i < 5; i++) begin
            check({DATA_WIDTH{1'b0}}, router_data_out[i], $sformatf("zero grant, out%0d", i));
        end

        // 5. Dynamic: change grant mid-simulation, output follows immediately
        arbiter_sel[0] = 5'b00001; #1;
        check(fifo_data_in[0], router_data_out[0], "dynamic, out0 = in0 before change");
        arbiter_sel[0] = 5'b01000; #1;
        check(fifo_data_in[3], router_data_out[0], "dynamic, out0 = in3 after change");

        // 6. Broadcast: Multiple outputs reading the same input simultaneously
        for (i = 0; i < 5; i++) begin
            arbiter_sel[i] = 5'b00100;
        end
        #1;
        for (i = 0; i < 5; i++) begin
            check(fifo_data_in[2], router_data_out[i], $sformatf("bcast, out%0d = in2", i));
        end

        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    initial begin
        $dumpfile("tb_crossbar_switch.vcd");
        $dumpvars(0, tb_crossbar_switch);
    end

endmodule
