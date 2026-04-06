// tb_network_interface.v
//   Tests TX packetization, RX de-packetization, Latency Calculation, 
//   bi-directional flow control/backpressure (stalling), post-stall data integrity verification.

`timescale 1ns / 1ps

module tb_network_interface;

    parameter DATA_WIDTH  = 34;
    parameter COORD_WIDTH = 1;  
    parameter TS_WIDTH    = 16;
    
    localparam FLIT_TYPE_WIDTH = 2;
    localparam PAYLOAD_WIDTH   = DATA_WIDTH - (2 * COORD_WIDTH) - FLIT_TYPE_WIDTH; // 30
    localparam CORE_DATA_WIDTH = PAYLOAD_WIDTH * 2; // 60

    localparam [FLIT_TYPE_WIDTH-1:0] TYPE_HEAD = 2'b01;
    localparam [FLIT_TYPE_WIDTH-1:0] TYPE_BODY = 2'b10;
    localparam [FLIT_TYPE_WIDTH-1:0] TYPE_TAIL = 2'b11;

    reg clk;
    reg rst_n;

    // Core Side Interfaces
    reg  [CORE_DATA_WIDTH-1:0] core_tx_data;
    reg  [COORD_WIDTH-1:0]     core_tx_dest_x;
    reg  [COORD_WIDTH-1:0]     core_tx_dest_y;
    reg                        core_tx_valid;
    wire                       core_tx_ready;

    wire [CORE_DATA_WIDTH-1:0] core_rx_data;
    wire                       core_rx_valid;
    reg                        core_rx_ready;

    // Router Side Interfaces
    wire [DATA_WIDTH-1:0]      router_tx_flit;
    wire                       router_tx_valid;
    reg                        router_tx_ready;

    reg  [DATA_WIDTH-1:0]      router_rx_flit;
    reg                        router_rx_valid;
    wire                       router_rx_ready;

    // Latency
    wire [TS_WIDTH-1:0]        latency_cycles_out;
    wire                       latency_valid;

    integer pass_count, fail_count;

    network_interface #(
        .DATA_WIDTH(DATA_WIDTH), .COORD_WIDTH(COORD_WIDTH), .TS_WIDTH(TS_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        
        .core_tx_data(core_tx_data),
        .core_tx_dest_x(core_tx_dest_x),
        .core_tx_dest_y(core_tx_dest_y),
        .core_tx_valid(core_tx_valid),
        .core_tx_ready(core_tx_ready),
        
        .core_rx_data(core_rx_data),
        .core_rx_valid(core_rx_valid),
        .core_rx_ready(core_rx_ready),
        
        .router_tx_flit(router_tx_flit),
        .router_tx_valid(router_tx_valid),
        .router_tx_ready(router_tx_ready),
        
        .router_rx_flit(router_rx_flit),
        .router_rx_valid(router_rx_valid),
        .router_rx_ready(router_rx_ready),
        
        .latency_cycles_out(latency_cycles_out),
        .latency_valid(latency_valid)
    );

    always #5 clk = ~clk;

    task reset_system;
        begin
            core_tx_data   = 0;
            core_tx_dest_x = 0;
            core_tx_dest_y = 0;
            core_tx_valid  = 0;
            core_rx_ready  = 1;
            
            router_tx_ready = 1;
            router_rx_flit  = 0;
            router_rx_valid = 0;
            
            rst_n = 1;
            #1;
            rst_n = 0;
            @(negedge clk);
            @(negedge clk);
            rst_n = 1;
        end
    endtask

    initial begin
        clk = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_system();
        $display("=== Starting Network Interface Tests ===");

        // TEST 1: TX Packetization
        @(negedge clk);
        core_tx_data   = {30'h1AAA_AAAA, 30'h3555_5555}; 
        core_tx_dest_x = 1'b1;
        core_tx_dest_y = 1'b0;
        core_tx_valid  = 1'b1;
        
        @(negedge clk);
        core_tx_valid  = 1'b0; 

        // Wait for hardware to assert router_tx_valid
        while(!router_tx_valid) @(negedge clk);
        if (router_tx_flit[DATA_WIDTH-1 : PAYLOAD_WIDTH] === 4'b1001) begin // X=1, Y=0, Type=01
            $display("PASS [%0t] Test 1, TX Head Flit formatted correctly", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 1, TX Head Flit malformed. Got %h", $time, router_tx_flit); 
            fail_count = fail_count + 1;
        end

        @(negedge clk);
        while(!router_tx_valid) @(negedge clk);
        if (router_tx_flit === {1'b1, 1'b0, TYPE_BODY, 30'h1AAA_AAAA}) begin
            $display("PASS [%0t] Test 1, TX Body Flit formatted correctly", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 1, TX Body Flit malformed", $time); 
            fail_count = fail_count + 1;
        end

        @(negedge clk);
        while(!router_tx_valid) @(negedge clk);
        if (router_tx_flit === {1'b1, 1'b0, TYPE_TAIL, 30'h3555_5555}) begin
            $display("PASS [%0t] Test 1, TX Tail Flit formatted correctly", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 1, TX Tail Flit malformed", $time); 
            fail_count = fail_count + 1;
        end
        @(negedge clk);

        // TEST 2: RX De-packetization & Latency Math
        reset_system();
        @(negedge clk);
        
        // Inject Head
        router_rx_valid = 1'b1;
        router_rx_flit  = {1'b0, 1'b1, TYPE_HEAD, {(PAYLOAD_WIDTH-TS_WIDTH){1'b0}}, (dut.ts_counter - 16'd15)};
        @(negedge clk);

        // Inject Body
        router_rx_flit = {1'b0, 1'b1, TYPE_BODY, 30'h3FFF_FFFF};
        @(negedge clk);

        // Inject Tail
        router_rx_flit = {1'b0, 1'b1, TYPE_TAIL, 30'h0000_0000};
        @(negedge clk);
        router_rx_valid = 1'b0;

        // Verify Latency
        if (latency_valid && latency_cycles_out === 16'd15) begin
            $display("PASS [%0t] Test 2, Latency correctly calculated as 15 cycles", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 2, Latency failed. Expected 15, Got %0d", $time, latency_cycles_out); 
            fail_count = fail_count + 1;
        end

        // Verify Core received reassembled payload
        if (core_rx_valid && core_rx_data === {30'h3FFF_FFFF, 30'h0000_0000}) begin
            $display("PASS [%0t] Test 2, RX Data reassembled correctly", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 2, RX Data reassembly failed", $time); 
            fail_count = fail_count + 1;
        end
        @(negedge clk);

        // TEST 3: TX Flow Control (Router stalls the NI)
        //         router_tx_ready is pulled LOW midway 
        reset_system();
        @(negedge clk);
        core_tx_data   = {30'h3777_7777, 30'h3333_3333}; 
        core_tx_dest_x = 0; core_tx_dest_y = 0;
        core_tx_valid  = 1'b1;
        
        @(negedge clk);
        core_tx_valid  = 1'b0;

        // Wait for Head to transmit
        while (!router_tx_valid) @(negedge clk);
        @(negedge clk); // Allow Head to pass, Body is now on the bus
        
        // Before Body flit goes out, router stalls
        router_tx_ready = 1'b0;
        @(negedge clk);
        @(negedge clk); // Hold stall for 2 cycles

        if (router_tx_valid && router_tx_flit[DATA_WIDTH-(2*COORD_WIDTH)-1 : PAYLOAD_WIDTH] === TYPE_BODY) begin
            $display("PASS [%0t] Test 3, NI correctly held Body Flit during stall", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 3, NI dropped Body flit during stall", $time); 
            fail_count = fail_count + 1;
        end

        // Release Stall
        router_tx_ready = 1'b1;

        while (!router_tx_valid) @(negedge clk);
        if (router_tx_flit === {1'b0, 1'b0, TYPE_BODY, 30'h3777_7777}) begin
            $display("PASS [%0t] Test 3, Body Flit transmitted correctly after stall", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 3, Body Flit corrupted after stall. Got %h", $time, router_tx_flit); 
            fail_count = fail_count + 1;
        end
        @(negedge clk);

        while (!router_tx_valid) @(negedge clk);
        if (router_tx_flit === {1'b0, 1'b0, TYPE_TAIL, 30'h3333_3333}) begin
            $display("PASS [%0t] Test 3, Tail Flit transmitted correctly after stall", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 3, Tail Flit corrupted after stall. Got %h", $time, router_tx_flit); 
            fail_count = fail_count + 1;
        end
        @(negedge clk);

        // TEST 4: RX Flow Control (Core stalls the NI)
        reset_system();
        core_rx_ready = 1'b0; // Core is busy
        @(negedge clk);

        // Inject Head, Body, Tail
        router_rx_valid = 1'b1;
        router_rx_flit  = {1'b0, 1'b1, TYPE_HEAD, 30'd0}; @(negedge clk);
        router_rx_flit  = {1'b0, 1'b1, TYPE_BODY, 30'h1111_2222}; @(negedge clk);
        router_rx_flit  = {1'b0, 1'b1, TYPE_TAIL, 30'h3333_4444}; @(negedge clk);
        router_rx_valid = 1'b0;

        #1;
        if (router_rx_ready === 1'b0 && core_rx_valid === 1'b1) begin
            $display("PASS [%0t] Test 4, NI correctly stalled network while waiting for core", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 4, Flow control failed. router_rx_ready=%b", $time, router_rx_ready); 
            fail_count = fail_count + 1;
        end

        core_rx_ready = 1'b1;

        #1;
        if (core_rx_valid && core_rx_data === {30'h1111_2222, 30'h3333_4444}) begin
            $display("PASS [%0t] Test 4, Core received correct, uncorrupted data after stall", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 4, Data corrupted after stall! Got %h", $time, core_rx_data); 
            fail_count = fail_count + 1;
        end

        @(negedge clk);
        
        #1;
        if (router_rx_ready === 1'b1 && core_rx_valid === 1'b0) begin
            $display("PASS [%0t] Test 4, NI successfully recovered to HEAD state after core read", $time); 
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0t] Test 4, Recovery failed.", $time); 
            fail_count = fail_count + 1;
        end

        // Simulation Summary
        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    initial begin
        $dumpfile("tb_network_interface.vcd");
        $dumpvars(0, tb_network_interface);
    end

endmodule
