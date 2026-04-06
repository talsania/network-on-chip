// tb_router_5port.sv 
//   Comprehensive testbench for verifying the 5-port NoC router node.
//   Written specifically for a 2x2 mesh architecture where COORD_WIDTH = 1.
//   Validates edge-case physical routing (corner nodes), max theoretical 
//   parallel throughput, 5-way arbiter contention, and flow control.

`timescale 1ns / 1ps

module tb_router_5port;

    parameter DATA_WIDTH  = 34;
    parameter COORD_WIDTH = 1; 
    parameter FIFO_DEPTH  = 8;
    
    localparam PAYLOAD_W  = DATA_WIDTH - (2 * COORD_WIDTH); 

    // Coordinates of the Router Under Test (RUT)
    logic [COORD_WIDTH-1:0] router_x;
    logic [COORD_WIDTH-1:0] router_y;

    logic clk;
    logic rst_n;
    
    logic [4:0][DATA_WIDTH-1:0] rx_flit;
    logic [4:0]                 rx_valid;
    logic [4:0]                 rx_ready;   
    logic [4:0][DATA_WIDTH-1:0] tx_flit;  
    logic [4:0]                 tx_valid; 
    logic [4:0]                 tx_ready;

    int pass_count = 0;
    int fail_count = 0;

    router_5port #(
        .DATA_WIDTH(DATA_WIDTH), .COORD_WIDTH(COORD_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk         (clk), 
        .rst_n       (rst_n),
        .router_x    (router_x), 
        .router_y    (router_y),
        
        .rx_flit_arr (rx_flit),
        .rx_valid_arr(rx_valid),
        .rx_ready_arr(rx_ready),
        
        .tx_flit_arr (tx_flit),
        .tx_valid_arr(tx_valid),
        .tx_ready_arr(tx_ready)
    );

    always #5 clk = ~clk;

    task automatic check_tx(input int port, input logic [COORD_WIDTH-1:0] exp_x, input logic [COORD_WIDTH-1:0] exp_y, input logic [PAYLOAD_W-1:0] exp_pay, input string name);
        logic [DATA_WIDTH-1:0] expected_flit;
        int timeout = 10; 
        begin
            expected_flit = {exp_x, exp_y, exp_pay};
            
            while (tx_valid[port] !== 1'b1 && timeout > 0) begin
                @(negedge clk);
                timeout--;
            end

            if (tx_valid[port] === 1'b1 && tx_flit[port] === expected_flit) begin
                $display("PASS  [%0t] %s : Port %0d transmitted correctly", $time, name, port);
                pass_count++;
            end else begin
                $display("FAIL  [%0t] %s : Port %0d mismatch. Expected valid=1, flit=%h. Got valid=%b, flit=%h", 
                          $time, name, port, expected_flit, tx_valid[port], tx_flit[port]);
                fail_count++;
            end
        end
    endtask

    task automatic reset_router();
        begin
            rx_flit  = 0;
            rx_valid = 0;
            tx_ready = {5{1'b1}}; 
            rst_n = 1'b1;
            #1;
            rst_n = 1'b0;
            @(negedge clk);
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        clk = 0;
        router_x = 0; router_y = 0;
        reset_router();

        $display("=== Starting 5-port Router node Tests ===");

        // TEST 1: Corner Routing Validations
        @(negedge clk);
        
        // Router at (0,0) -> Send East to (1,0)
        router_x = 1'b0; router_y = 1'b0;
        rx_flit[0] = {1'b1, 1'b0, 32'hC000_EAE0}; 
        rx_valid[0] = 1'b1;
        @(negedge clk); rx_valid[0] = 1'b0;
        check_tx(3, 1'b1, 1'b0, 32'hC000_EAE0, "Test 1, Corner (0,0) -> East");
        @(negedge clk);

        // Router at (1,1) -> Send North to (1,0)
        router_x = 1'b1; router_y = 1'b1;
        rx_flit[0] = {1'b1, 1'b0, 32'hC000_00A0}; rx_valid[0] = 1'b1;
        @(negedge clk); rx_valid[0] = 1'b0;
        check_tx(1, 1'b1, 1'b0, 32'hC000_00A0, "Test 1, Corner (1,1) -> North");
        @(negedge clk);

        // Router at (1,0) -> Send West to (0,0)
        router_x = 1'b1; router_y = 1'b0;
        rx_flit[0] = {1'b0, 1'b0, 32'hC000_00E5}; rx_valid[0] = 1'b1;
        @(negedge clk); rx_valid[0] = 1'b0;
        check_tx(4, 1'b0, 1'b0, 32'hC000_00E5, "Test 1, Corner (1,0) -> West");
        @(negedge clk);

        // Router at (1,0) -> Send South to (1,1)
        router_x = 1'b1; router_y = 1'b0;
        rx_flit[0] = {1'b1, 1'b1, 32'hC000_50E5}; rx_valid[0] = 1'b1;
        @(negedge clk); rx_valid[0] = 1'b0;
        check_tx(2, 1'b1, 1'b1, 32'hC000_50E5, "Test 1, Corner (1,0) -> South");
        @(negedge clk);

        // TEST 2: Maximum Throughput Bijection 
        // Evaluate the crossbar switch's ability to handle parallel transfers. 
        // A 2x2 node only has 3 valid targets (Local + 2 neighbors), 
        // a 3-way bijection is the maximum possible parallel throughput.
        router_x = 1'b0; router_y = 1'b0;
        @(negedge clk);
        
        rx_flit[0] = {1'b1, 1'b0, 32'hCAAA_1111}; rx_valid[0] = 1'b1; // Local(0) -> East(3)
        rx_flit[3] = {1'b0, 1'b1, 32'hCBBB_2222}; rx_valid[3] = 1'b1; // EastRx(3) -> South(2)
        rx_flit[2] = {1'b0, 1'b0, 32'hCCCC_3333}; rx_valid[2] = 1'b1; // SouthRx(2)-> Local(0)
        
        @(negedge clk);
        rx_valid = 0; 
        
        check_tx(3, 1'b1, 1'b0, 32'hCAAA_1111, "Test 2, 3-Way Parallel (Local->East)");
        check_tx(2, 1'b0, 1'b1, 32'hCBBB_2222, "Test 2, 3-Way Parallel (EastRx->South)");
        check_tx(0, 1'b0, 1'b0, 32'hCCCC_3333, "Test 2, 3-Way Parallel (SouthRx->Local)");
        @(negedge clk);

        // TEST 3: 5-Way Contention 
        // Force an intentional 5-way collision. 
        // All 5 input ports are injected with a flit simultaneously, and 
        // All 5 flits want to route to the East port (3). 
        reset_router();
        router_x = 1'b0; router_y = 1'b0;
        
        @(negedge clk);
        for(int i=0; i<5; i++) begin
            logic [31:0] safe_payload;
            safe_payload = 32'hC000_0000 + i;
            rx_flit[i]  = {1'b1, 1'b0, safe_payload}; 
            rx_valid[i] = 1;
        end
        
        @(negedge clk);
        rx_valid = 0;

        for(int i=0; i<5; i++) begin
            #1; 
            if (tx_valid[3]) begin
                $display("PASS  [%0t] Test 3, 5-Way Contention - East Port transmitted Payload: %h", $time, tx_flit[3][PAYLOAD_W-1:0]);
                pass_count++;
            end else begin
                $display("FAIL  [%0t] Test 3, East Port failed to transmit during contention cycle %0d", $time, i);
                fail_count++;
            end
            @(negedge clk); 
        end


        // TEST 4: Output Stalling (Downstream Flow Control)
        // Check router's ability to block output (downstream) if input flit is 
        // sent, but tx_ready signal is pulled low. 
        reset_router();
        tx_ready[3] = 1'b0; 
        
        @(negedge clk);
        rx_flit[0]  = {1'b1, 1'b0, 32'hDEAD_BEEF};
        rx_valid[0] = 1'b1;
        @(negedge clk);
        rx_valid[0] = 1'b0;        
        
        repeat(3) @(negedge clk); 

        if (tx_valid[3] === 1'b1) begin
            $display("PASS  [%0t] Test 4, Flow Control Stall - Valid held high while ready is low", $time);
            pass_count++;
        end else begin
            $display("FAIL  [%0t] Test 4, Flow Control Stall - Valid dropped unexpectedly", $time);
            fail_count++;
        end

        tx_ready[3] = 1'b1; // Release the stall
        check_tx(3, 1'b1, 1'b0, 32'hDEAD_BEEF, "Test 4, Flow Control Stall - Flit released successfully");
        @(negedge clk);


        // TEST 5: Input FIFO Full (Upstream Backpressure)
        // Block an output, then continuously send flits in the direction 
        // of the blocked port until fifo is full. Once the last flit is written, 
        // the router must drop its rx_ready[0] signal.
        reset_router();
        tx_ready[3] = 1'b0; // Block output to East
        
        for (int i=0; i<8; i++) begin
            @(negedge clk);
            #1;
            begin
                logic [31:0] safe_payload;
                safe_payload = 32'hC000_0000 + i;
                rx_flit[0] = {1'b1, 1'b0, safe_payload};
                rx_valid[0] = 1'b1;
            end
        end

        @(negedge clk);
        @(negedge clk);
        rx_valid[0] = 1'b0; 
        
        #1; 
        
        if (rx_ready[0] === 1'b0) begin
            $display("PASS  [%0t] Test 5, FIFO Full - rx_ready correctly dropped to 0", $time);
            pass_count++;
        end else begin
            $display("FAIL  [%0t] Test 5, FIFO Full - rx_ready stayed high even though FIFO is full", $time);
            fail_count++;
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
        $dumpfile("tb_router_5port.vcd");
        $dumpvars(0, tb_router_5port);
    end

endmodule
