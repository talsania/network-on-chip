// tb_top_noc.sv
//   Top-level integration testbench for the 4-core 2x2 Mesh NoC.

`timescale 1ns / 1ps

module tb_mesh_fabric_noc;

    parameter DATA_WIDTH  = 34,
              COORD_WIDTH = 1,
              FIFO_DEPTH  = 8,
              TS_WIDTH    = 16,
              PAYLOAD_W   = 30,
              CORE_DATA_W = 60;

    logic clk = 0;
    logic fab_rst_n;

    logic [3:0][CORE_DATA_W-1:0] fab_tx_data, fab_rx_data;
    logic [3:0][COORD_WIDTH-1:0] fab_tx_dest_x, fab_tx_dest_y;
    logic [3:0]                  fab_tx_valid, fab_tx_ready;
    logic [3:0]                  fab_rx_valid, fab_rx_ready;
    logic [3:0][TS_WIDTH-1:0]    fab_latency;
    logic [3:0]                  fab_lat_valid;

    mesh_fabric_noc #(
        .DATA_WIDTH(DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .TS_WIDTH(TS_WIDTH)
    ) fab_dut (
        .clk(clk), .rst_n(fab_rst_n),
        .core_tx_data(fab_tx_data), .core_tx_dest_x(fab_tx_dest_x),
        .core_tx_dest_y(fab_tx_dest_y), .core_tx_valid(fab_tx_valid),
        .core_tx_ready(fab_tx_ready),
        .core_rx_data(fab_rx_data), .core_rx_valid(fab_rx_valid),
        .core_rx_ready(fab_rx_ready),
        .latency_cycles_out(fab_latency), .latency_valid(fab_lat_valid)
    );

    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic pass_test(string name);
        $display("  PASS  %s", name);
        pass_cnt++;
    endtask

    task automatic fail_test(string name, string reason="");
        $display("  FAIL  %s  [%s]", name, reason);
        fail_cnt++;
    endtask

    task automatic begin_group(string name);
        $display("\n------------------------------------------------------------");
        $display("  %s", name);
        $display("------------------------------------------------------------");
    endtask
    
    task automatic node_to_coord(input int node, output logic [COORD_WIDTH-1:0] nx, ny);
        nx = node[0]; ny = node[1];
    endtask

    task automatic fab_reset();
        fab_rst_n     = 0;
        fab_tx_data   = 0; 
        fab_tx_dest_x = 0; 
        fab_tx_dest_y = 0;
        fab_tx_valid  = 0;         
        fab_rx_ready  = 4'b1111;
        repeat(10) @(negedge clk); 
        fab_rst_n     = 1;
        repeat(10) @(negedge clk);
        
        // Default to holding packets (Ready = 0). The testbench will selectively pop them.
        fab_rx_ready  = 4'b0000; 
    endtask

    task automatic fab_send(input int src_node, dst_node, input [CORE_DATA_W-1:0] data);
        logic [COORD_WIDTH-1:0] dx, dy;
        node_to_coord(dst_node, dx, dy);
        @(negedge clk);
        
        while (!fab_tx_ready[src_node]) @(negedge clk);
        
        fab_tx_data[src_node]   = data;
        fab_tx_dest_x[src_node] = dx;
        fab_tx_dest_y[src_node] = dy;
        fab_tx_valid[src_node]  = 1;
        
        @(negedge clk); 
        fab_tx_valid[src_node] = 0;
    endtask

    task automatic fab_wait_rx(input int node, input int timeout, output logic got_it, output logic [CORE_DATA_W-1:0] rx_payload, output logic [TS_WIDTH-1:0] lat);
        int t; 
        t = 0; 
        got_it     = 0;
        rx_payload = 0;
        lat        = 0;
        
        while (!fab_rx_valid[node] && t < timeout) begin 
            @(negedge clk); 
            t++; 
        end
        
        if (fab_rx_valid[node]) begin
            got_it     = 1;
            rx_payload = fab_rx_data[node];
            lat        = fab_latency[node]; 
            
            // Pop the packet by asserting ready for 1 cycle
            fab_rx_ready[node] = 1'b1;
            @(negedge clk); 
            fab_rx_ready[node] = 1'b0; 
        end
    endtask

    // MAIN TEST SEQUENCE
    initial begin
        $dumpfile("tb_mesh_fabric_noc.vcd");
        $dumpvars(0, tb_mesh_fabric_noc);

        $display("\n============================================================");
        $display("|                   4-Core Mesh NoC Test                   |");
        $display("============================================================");

        // GROUP A: Basic Topology Routing
        fab_reset(); 
        begin_group("GROUP A - Basic Topology Routing");
        
        begin : A1
            logic ok; 
            logic [59:0] pyld; 
            logic [15:0] lat;
            fab_send(0, 1, 60'hA1A1A1A1);
            fab_wait_rx(1, 50, ok, pyld, lat);
            if (ok && pyld === 60'hA1A1A1A1) 
                pass_test("A1: 1-Hop Routing (Node 0 -> Node 1)");
            else 
                fail_test("A1: 1-Hop Routing Failed", $sformatf("ok=%b, expected=%h, got=%h", ok, 60'hA1A1A1A1, pyld));
        end

        begin : A2
            logic ok; 
            logic [59:0] pyld; 
            logic [15:0] lat;
            fab_send(0, 3, 60'hA2A2A2A2);
            fab_wait_rx(3, 50, ok, pyld, lat);
            if (ok && pyld === 60'hA2A2A2A2) 
                pass_test("A2: 2-Hop Diagonal (Node 0 -> Node 3)");
            else 
                fail_test("A2: 2-Hop Diagonal Failed", $sformatf("ok=%b, expected=%h, got=%h", ok, 60'hA2A2A2A2, pyld));
        end

        begin : A3
            logic ok; 
            logic [59:0] pyld; 
            logic [15:0] lat;
            fab_send(2, 2, 60'hA3A3A3A3);
            fab_wait_rx(2, 50, ok, pyld, lat);
            if (ok && pyld === 60'hA3A3A3A3) 
                pass_test("A3: Self-Loop (Node 2 -> Node 2)");
            else 
                fail_test("A3: Self-Loop Failed", $sformatf("ok=%b, expected=%h, got=%h", ok, 60'hA3A3A3A3, pyld));
        end

        // GROUP B: Parallelism & Contention
        fab_reset(); 
        begin_group("GROUP B - Parallelism & Contention");
        
        begin : B1
            logic ok_0, ok_3; 
            logic [59:0] pyld_0, pyld_3; 
            logic [15:0] l_0, l_3;
            
            fab_send(0, 3, 60'h0000_3333);
            fab_send(3, 0, 60'h3333_0000);
            
            fab_wait_rx(3, 100, ok_3, pyld_3, l_3);
            fab_wait_rx(0, 100, ok_0, pyld_0, l_0);
            
            if (ok_0 && ok_3) 
                pass_test("B1: Simultaneous Bi-directional (0->3 and 3->0)");
            else 
                fail_test("B1: Bi-directional Collision", $sformatf("ok_0=%b (got %h), ok_3=%b (got %h)", ok_0, pyld_0, ok_3, pyld_3));
        end

        begin : B2
            logic ok_0, ok_1, ok_2, ok_3; 
            logic [59:0] p_0, p_1, p_2, p_3; 
            logic [15:0] l;
            
            fab_send(0, 1, 60'h0001);
            fab_send(1, 3, 60'h0013);
            fab_send(3, 2, 60'h0032);
            fab_send(2, 0, 60'h0020);
            
            fab_wait_rx(1, 100, ok_1, p_1, l);
            fab_wait_rx(3, 100, ok_3, p_3, l);
            fab_wait_rx(2, 100, ok_2, p_2, l);
            fab_wait_rx(0, 100, ok_0, p_0, l);
            
            if (ok_0 && ok_1 && ok_2 && ok_3) 
                pass_test("B2: Maximum Bijection (4 packets traversed simultaneously)");
            else 
                fail_test("B2: Bijection Failed - Network Bottlenecked", $sformatf("ok0=%b ok1=%b ok2=%b ok3=%b", ok_0, ok_1, ok_2, ok_3));
        end

        begin : B3
            logic ok_a, ok_b; 
            logic [59:0] p_a, p_b; 
            logic [15:0] l_a, l_b;
            
            fab_send(0, 3, 60'hAAAA);
            fab_send(2, 3, 60'hBBBB);
            
            fab_wait_rx(3, 150, ok_a, p_a, l_a);
            fab_wait_rx(3, 150, ok_b, p_b, l_b);
            
            if (ok_a && ok_b && (p_a ^ p_b) == (60'hAAAA ^ 60'hBBBB))
                pass_test("B3: Multi-hop Contention (0->3 and 2->3 routed safely)");
            else
                fail_test("B3: Contention caused dropped or corrupted packets", $sformatf("ok_a=%b (got %h), ok_b=%b (got %h)", ok_a, p_a, ok_b, p_b));
        end

        // GROUP C: End-to-End Backpressure & Flow Control
        fab_reset(); 
        begin_group("GROUP C - End-to-End Backpressure & Flow Control");
        
        begin : C
            int sent_count;
            int recv_count;
            logic stall_detected;

            sent_count = 0;
            recv_count = 0;
            stall_detected = 0;

            // Node 3 is stalled because fab_rx_ready[3] = 0 from reset
            
            // 1. Flood the network from Node 0
            for (int i = 0; i < 20 && !stall_detected; i++) begin
                begin : timeout_block
                    int tw; 
                    tw = 0;
                    while (!fab_tx_ready[0] && tw < 200) begin 
                        @(negedge clk); 
                        tw++; 
                    end
                    if (tw >= 200) begin
                        stall_detected = 1'b1; 
                    end else begin
                        fab_tx_data[0]   = 60'hC000_0000 + i;
                        fab_tx_dest_x[0] = 1; fab_tx_dest_y[0] = 1;
                        fab_tx_valid[0]  = 1;
                        @(negedge clk); 
                        fab_tx_valid[0] = 0;
                        sent_count++;
                    end
                end
            end

            if (stall_detected) 
                pass_test($sformatf("C1: Network properly backpressured Source after %0d packets", sent_count));
            else 
                fail_test("C1: Network failed to stall source during flood!", $sformatf("sent_count=%0d", sent_count));

            // 2. Wake up Node 3 and verify all queued packets drain correctly
            for (int i = 0; i < sent_count; i++) begin
                logic ok; logic [59:0] pyld; logic [15:0] lat;
                
                fab_wait_rx(3, 300, ok, pyld, lat);
                if (ok && pyld === (60'hC000_0000 + i)) begin
                    recv_count++;
                end else if (ok) begin
                    $display("  WARN  Payload mismatch: Expected %h, Got %h", (60'hC000_0000 + i), pyld);
                end
            end

            if (recv_count == sent_count)
                pass_test("C2: All stalled packets drained and data integrity preserved");
            else
                fail_test("C2: Packet loss or corruption during network drain", $sformatf("Sent: %0d, Recv: %0d", sent_count, recv_count));
        end

        // GROUP D: Latency Verification
        fab_reset(); 
        begin_group("GROUP D - Latency Verification");
        
        begin : D1
            logic ok; 
            logic [59:0] pyld; 
            logic [15:0] captured_latency;
            
            fab_send(0, 3, 60'hDEAD_BEEF);
            fab_wait_rx(3, 100, ok, pyld, captured_latency);
            
            if (ok && captured_latency > 0)
                pass_test($sformatf("D1: End-to-End Latency successfully measured (%0d cycles)", captured_latency));
            else
                fail_test("D1: Latency valid flag did not trigger at destination", $sformatf("ok=%b, latency=%0d", ok, captured_latency));
        end

        $display("\n============================================================");
        $display("|                 FINAL TEST SUMMARY                       |");
        $display("------------------------------------------------------------");
        $display("|  TOTAL PASSED : %-4d                                     |", pass_cnt);
        $display("|  TOTAL FAILED : %-4d                                     |", fail_cnt);
        $display("------------------------------------------------------------");
        if (fail_cnt == 0)
            $display("|                [PASS] ALL TESTS PASSED                   |");
        else
            $display("|            [FAIL] SOME TESTS FAILED - review above       |");
        $display("============================================================\n");
        $finish;
    end

    // Watchdog Timer
    initial begin
        #50_000;
        $display("\n[WATCHDOG] Simulation timeout - deadlocked or stalled indefinitely.");
        $finish;
    end

endmodule
