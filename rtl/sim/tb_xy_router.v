// tb_xy_router.v
//   Testbench for xy_router. Exhaustively tests all 16 combinations of
//   (curr_x, curr_y) in the 2x2 mesh (coords 0..1) against every possible
//   (dest_x, dest_y), verifying correct one-hot port selection. Additional
//   directed tests confirm: X resolves before Y, North/South polarity, all four
//   corner-to-corner diagonal paths, and Local ejection at every node.
//   Purely combinational DUT — all checks use #1 propagation delay.

`timescale 1ns / 1ps

module tb_xy_router;

    parameter COORD_WIDTH = 1;
    parameter max_coord   = (1 << COORD_WIDTH);

    reg  [COORD_WIDTH-1:0] curr_x, curr_y, dest_x, dest_y;
    wire [4:0]             out_port_req;

    integer pass_count, fail_count;

    localparam PORT_LOCAL = 5'b00001;
    localparam PORT_NORTH = 5'b00010;
    localparam PORT_SOUTH = 5'b00100;
    localparam PORT_EAST  = 5'b01000;
    localparam PORT_WEST  = 5'b10000;

    xy_router #(.COORD_WIDTH(COORD_WIDTH)) dut (
        .curr_x(curr_x), .curr_y(curr_y),
        .dest_x(dest_x), .dest_y(dest_y),
        .out_port_req(out_port_req)
    );

    task check;
        input [4:0]   expected;
        input [4:0]   actual;
        input [299:0] name; 
        begin
            if (expected === actual) begin
                $display("PASS  [%0t] %0s : got %05b", $time, name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  [%0t] %0s : expected %05b, got %05b",
                          $time, name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task route;
        input [COORD_WIDTH-1:0] cx, cy, dx, dy;
        input [4:0]             expected;
        input [299:0]           name;
        begin
            curr_x = cx; curr_y = cy;
            dest_x = dx; dest_y = dy;
            #1; // Wait 1ns for combinational logic to settle
            check(expected, out_port_req, name);
        end
    endtask

    initial begin
        pass_count = 0; 
        fail_count = 0;
        curr_x = 0; 
        curr_y = 0; 
        dest_x = 0; 
        dest_y = 0;
        #1;

        $display("=== Starting XY Router Directed Tests ===");

        // Local Node Ejection (Destination matches Current Router)
        route(0,0, 0,0, PORT_LOCAL, "local (0,0)->(0,0)");
        route(1,0, 1,0, PORT_LOCAL, "local (1,0)->(1,0)");
        route(0,1, 0,1, PORT_LOCAL, "local (0,1)->(0,1)");
        route(1,1, 1,1, PORT_LOCAL, "local (1,1)->(1,1)");

        // X-Dimension Routing (Resolves East/West first)
        route(0,0, 1,0, PORT_EAST,  "east  (0,0)->(1,0)");
        route(1,0, 0,0, PORT_WEST,  "west  (1,0)->(0,0)");
        route(0,1, 1,1, PORT_EAST,  "east  (0,1)->(1,1)");
        route(1,1, 0,1, PORT_WEST,  "west  (1,1)->(0,1)");

        // Y-Dimension Routing (Resolves North/South after X matches)
        route(0,0, 0,1, PORT_SOUTH, "south (0,0)->(0,1)");
        route(0,1, 0,0, PORT_NORTH, "north (0,1)->(0,0)");
        route(1,0, 1,1, PORT_SOUTH, "south (1,0)->(1,1)");
        route(1,1, 1,0, PORT_NORTH, "north (1,1)->(1,0)");

        // Diagonal Routing (Should route X-dimension first)
        route(0,0, 1,1, PORT_EAST,  "diag  (0,0)->(1,1): X first -> East");
        route(1,0, 0,1, PORT_WEST,  "diag  (1,0)->(0,1): X first -> West");
        route(0,1, 1,0, PORT_EAST,  "diag  (0,1)->(1,0): X first -> East");
        route(1,1, 0,0, PORT_WEST,  "diag  (1,1)->(0,0): X first -> West");

        begin : exhaustive_functional_check
            integer cx, cy, dx, dy;
            reg [4:0] expected_port;
            reg [4:0] result; 

            for (cx = 0; cx < max_coord; cx = cx + 1) begin
                for (cy = 0; cy < max_coord; cy = cy + 1) begin
                    for (dx = 0; dx < max_coord; dx = dx + 1) begin
                        for (dy = 0; dy < max_coord; dy = dy + 1) begin
                            
                            curr_x = cx; curr_y = cy;
                            dest_x = dx; dest_y = dy;
                            #1;
                            result = out_port_req;

                            if      (dx > cx)  expected_port = PORT_EAST;
                            else if (dx < cx)  expected_port = PORT_WEST;
                            else if (dy > cy)  expected_port = PORT_SOUTH;
                            else if (dy < cy)  expected_port = PORT_NORTH;
                            else               expected_port = PORT_LOCAL;

                            if ((result == 0) || ((result & (result - 1)) != 0)) begin
                                $display("FAIL  [%0t] one-hot (%0d,%0d)->(%0d,%0d): %05b not one-hot", 
                                          $time, cx, cy, dx, dy, result);
                                fail_count = fail_count + 1;
                            end 
                            else if (result !== expected_port) begin
                                $display("FAIL  [%0t] Logic Error (%0d,%0d)->(%0d,%0d): Expected %05b, Got %05b", 
                                          $time, cx, cy, dx, dy, expected_port, result);
                                fail_count = fail_count + 1;
                            end 
                            else begin
                                pass_count = pass_count + 1;
                            end

                        end
                    end
                end
            end
        end

        // Simulation Results
        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    // Waveform Generation
    initial begin
        $dumpfile("tb_xy_router.vcd");
        $dumpvars(0, tb_xy_router);
    end

endmodule
