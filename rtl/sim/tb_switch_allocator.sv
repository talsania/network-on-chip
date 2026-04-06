// tb_switch_allocator.sv
//   Testbench for the 5-port Switch Allocator.

`timescale 1ns / 1ps

module tb_switch_allocator;

    parameter DATA_WIDTH  = 34;
    parameter COORD_WIDTH = 1;

    logic clk;
    logic rst_n;
    logic [4:0][4:0]            input_reqs;
    logic [4:0][DATA_WIDTH-1:0] tx_flit_arr;
    logic [4:0]                 tx_valid_arr;
    logic [4:0]                 tx_ready_arr;
    logic [4:0][4:0]            output_grants;

    int pass_count;
    int fail_count;

    switch_allocator #(
        .DATA_WIDTH(DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .req_in(input_reqs),
        .tx_flit_arr(tx_flit_arr),   
        .tx_valid_arr(tx_valid_arr), 
        .tx_ready_arr(tx_ready_arr), 
        .grant_out(output_grants)
    );

    always #5 clk = ~clk;

    task check_port(input int port, input logic [4:0] expected, input string name);
        if (output_grants[port] === expected) begin
            $display("PASS  [%0t] %s : got %05b", $time, name, output_grants[port]);
            pass_count++;
        end else begin
            $display("FAIL  [%0t] %s : expected %05b, got %05b", $time, name, expected, output_grants[port]);
            fail_count++;
        end
    endtask

    task clear_reqs();
        input_reqs = 0;
    endtask

    task simulate_tail_flit(input int port);
        logic [DATA_WIDTH-1:0] temp_flit;
        
        temp_flit = tx_flit_arr[port];
        temp_flit[31:30] = 2'b11;       // TYPE_TAIL 
        tx_flit_arr[port] = temp_flit;
        
        tx_valid_arr[port]       = 1'b1;
        tx_ready_arr[port]       = 1'b1;
        @(negedge clk);
        tx_valid_arr[port]       = 1'b0;
        tx_ready_arr[port]       = 1'b0;
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        clear_reqs();
        tx_flit_arr  = 0;
        tx_valid_arr = 0;
        tx_ready_arr = 0;
        pass_count = 0;
        fail_count = 0;

        // 1. Reset
        @(negedge clk);
        rst_n = 0;
        @(negedge clk);
        rst_n = 1; 
        #1;
        check_port(0, 5'b00000, "Reset, No grants for Out 0");
        check_port(1, 5'b00000, "Reset, No grants for Out 1");

        // 2. Single Isolated Request (Input 0 requests Output 2)
        @(negedge clk);
        input_reqs[0] = 5'b00100; 
        #1;
        check_port(2, 5'b00001, "Isolated, In 0 wins Out 2");
        check_port(0, 5'b00000, "Isolated, Out 0 correctly empty");
        
        clear_reqs(); 
        simulate_tail_flit(2);

        // 3. Simultaneous Non-Conflicting (Bijection)
        input_reqs[0] = 5'b00001;
        input_reqs[1] = 5'b00010;
        input_reqs[2] = 5'b00100;
        input_reqs[3] = 5'b01000;
        input_reqs[4] = 5'b10000;
        #1;
        check_port(0, 5'b00001, "Bijection, In 0 wins Out 0");
        check_port(1, 5'b00010, "Bijection, In 1 wins Out 1");
        check_port(2, 5'b00100, "Bijection, In 2 wins Out 2");
        check_port(3, 5'b01000, "Bijection, In 3 wins Out 3");
        check_port(4, 5'b10000, "Bijection, In 4 wins Out 4");

        clear_reqs(); 
        
        tx_valid_arr = 5'b11111; 
        tx_ready_arr = 5'b11111;
        for(int k=0; k<5; k++) begin
            logic [DATA_WIDTH-1:0] temp_flit;
            temp_flit = tx_flit_arr[k];
            temp_flit[31:30] = 2'b11;
            tx_flit_arr[k] = temp_flit;
        end
        @(negedge clk);
        tx_valid_arr = 5'b00000; 
        tx_ready_arr = 5'b00000;

        // 4. Heavy Contention: Perfect Round-Robin Rotation
        @(negedge clk);
        rst_n = 0; 
        @(negedge clk);
        rst_n = 1;

        for (int i = 0; i < 5; i++) begin
            input_reqs[i] = 5'b00001; 
        end
        
        // Cycle 1
        #1; check_port(0, 5'b00001, "RR Cycle 1, In 0 wins");
        simulate_tail_flit(0);
 
        // Cycle 2
        #1; check_port(0, 5'b00010, "RR Cycle 2, In 1 wins");
        simulate_tail_flit(0);
        
        // Cycle 3
        #1; check_port(0, 5'b00100, "RR Cycle 3, In 2 wins");
        simulate_tail_flit(0); 
       
        // Cycle 4
        #1; check_port(0, 5'b01000, "RR Cycle 4, In 3 wins");
        simulate_tail_flit(0);
        
        // Cycle 5
        #1; check_port(0, 5'b10000, "RR Cycle 5, In 4 wins");
        simulate_tail_flit(0);
        
        // Cycle 6 
        #1; check_port(0, 5'b00001, "RR Cycle 6, Wrap around to In 0");
        
        clear_reqs(); 
        simulate_tail_flit(0);

        // 5. Independent Contention
        @(negedge clk);
        rst_n = 0; 
        @(negedge clk);
        rst_n = 1;

        input_reqs[2] = 5'b00001; 
        input_reqs[3] = 5'b00001; 
        
        input_reqs[0] = 5'b00010; 
        input_reqs[4] = 5'b00010; 

        // Cycle 1
        #1; 
        check_port(0, 5'b00100, "Indep C1, In 2 wins Out 0");
        check_port(1, 5'b00001, "Indep C1, In 0 wins Out 1");

        tx_valid_arr[0] = 1; tx_ready_arr[0] = 1; 
        tx_flit_arr[0][31:30] = 2'b11; 
        tx_valid_arr[1] = 1; tx_ready_arr[1] = 1; 
        tx_flit_arr[1][31:30] = 2'b11;
        @(negedge clk);
        tx_valid_arr = 0; tx_ready_arr = 0;

        // Cycle 2
        #1; 
        check_port(0, 5'b01000, "Indep C2, In 3 wins Out 0");
        check_port(1, 5'b10000, "Indep C2, In 4 wins Out 1");

        tx_valid_arr[0] = 1; tx_ready_arr[0] = 1; 
        tx_flit_arr[0][31:30] = 2'b11;
        tx_valid_arr[1] = 1; tx_ready_arr[1] = 1; 
        tx_flit_arr[1][31:30] = 2'b11;
        @(negedge clk);
        tx_valid_arr = 0; tx_ready_arr = 0;
                
        // Cycle 3 (Wrap around)
        #1; 
        check_port(0, 5'b00100, "Indep C3, Wrap back to In 2 for Out 0");
        check_port(1, 5'b00001, "Indep C3, Wrap back to In 0 for Out 1");

        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    // VCD Dumping
    initial begin
        $dumpfile("tb_switch_allocator.vcd");
        $dumpvars(0, tb_switch_allocator);
    end

endmodule
