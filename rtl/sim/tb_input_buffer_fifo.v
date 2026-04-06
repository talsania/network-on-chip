// tb_input_buffer_fifo.v
//   Testbench for input_buffer_fifo. Verifies: reset behaviour, sequential writes,
//   sequential reads, full assertion and write-blocking, empty assertion and
//   read-blocking, simultaneous read+write (count stability), and wrap-around of
//   circular pointers.

`timescale 1ns / 1ps

module tb_input_buffer_fifo;

    parameter DATA_WIDTH = 34;
    parameter DEPTH      = 8;

    reg                  clk;
    reg                  rst_n;
    reg                  wr_en;
    reg  [DATA_WIDTH-1:0] data_in;
    reg                  rd_en;
    wire [DATA_WIDTH-1:0] data_out;
    wire                  full;
    wire                  empty;

    integer i;
    integer pass_count;
    integer fail_count;

    input_buffer_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .data_in  (data_in),
        .full     (full),
        .rd_en    (rd_en),
        .data_out (data_out),
        .empty    (empty)
    );

    always #5 clk = ~clk;

    task check;
        input [DATA_WIDTH-1:0] expected;
        input [DATA_WIDTH-1:0] actual;
        input [399:0]          test_name;
        begin
            if (expected === actual) begin
                $display("PASS  [%0t] %s : got %0h", $time, test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  [%0t] %s : expected %0h, got %0h", $time, test_name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk        = 0;
        rst_n      = 0;
        wr_en      = 0;
        rd_en      = 0;
        data_in    = 0;
        pass_count = 0;
        fail_count = 0;

        // 1. Reset check
        @(negedge clk); rst_n = 0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;
        check(1, empty, "empty after reset");
        check(0, full,  "not full after reset");

        // 2. FWFT Immediate Visibility (without asserting rd_en)
        @(negedge clk);
        data_in = 34'hBEEF_CAFE;
        wr_en   = 1;
        @(posedge clk); #1;
        wr_en   = 0;
        check(34'hBEEF_CAFE, data_out, "FWFT: Data visible without rd_en");
        
        rd_en = 1;          // Clear this test case
        @(posedge clk); #1;
        rd_en = 0;

        // 3. Write DEPTH flits  ->  should assert full
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            data_in = i + 34'hA00_0000;
            wr_en   = 1;
            @(posedge clk); #1;
        end
        wr_en = 0;
        check(0, empty, "not empty after full write");
        check(1, full,  "full after DEPTH writes");

        // 4. Attempt extra write while full  ->  count must not change
        @(negedge clk);
        data_in = 34'hDEAD_BEEF;
        wr_en   = 1;
        @(posedge clk); #1;
        wr_en = 0;
        check(1, full, "still full after blocked write");

        // 5. Read all DEPTH flits  ->  check data order (FIFO)
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            check(i + 34'hA00_0000, data_out, "read data in order");

            rd_en = 1;
            @(posedge clk); #1;            
            rd_en = 0;
        end
        check(1, empty, "empty after reading all flits");
        check(0, full,  "not full after draining");

        // 6. Attempt read while empty  ->  empty must stay asserted
        @(negedge clk);
        rd_en = 1;
        @(posedge clk); #1;
        rd_en = 0;
        check(1, empty, "still empty after blocked read");

        // 7. Simultaneous read + write  ->  count stays same
        @(negedge clk); data_in = 34'h1_2345_6789; wr_en = 1;
        @(posedge clk); #1; wr_en = 0;

        @(negedge clk);
        data_in = 34'h2_ABCD_EF01;
        wr_en   = 1;
        rd_en   = 1;
        @(posedge clk); #1;
        wr_en = 0; rd_en = 0;
        check(0, empty, "not empty after simultaneous rw");
        check(0, full,  "not full after simultaneous rw");
        check(34'h2_ABCD_EF01, data_out, "Data after simultaneous rw");

        // 8. Wrap-around: fill, drain, fill again
        rd_en = 1;
        @(posedge clk); #1; rd_en = 0;

        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk); data_in = i + 34'hB00_0000; wr_en = 1;
            @(posedge clk); #1;
        end
        wr_en = 0;
        check(1, full, "full after wrap-around refill");

        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk); 
            check(i + 34'hB00_0000, data_out, "wrap-around read order");

            rd_en = 1;
            @(posedge clk); #1;
            rd_en = 0;
        end
        check(1, empty, "empty after wrap-around drain");

        // 9. Strict NoC Handshake: RW while FULL
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk); 
            data_in = i + 34'hC00_0000; 
            wr_en = 1;
            @(posedge clk); #1;
        end
        wr_en = 0;
        
        @(negedge clk);
        data_in = 34'hDEAD_C0DE;
        wr_en   = 1;
        rd_en   = 1;
        @(posedge clk); #1;
        wr_en = 0; 
        rd_en = 0;
        
        check(0, full, "FIFO no longer full after RW on full");
        for (i = 1; i < DEPTH; i = i + 1) begin
            @(negedge clk); 
            rd_en = 1;
            @(posedge clk); #1; 
            rd_en = 0;
        end
        check(1, empty, "FIFO empty, ensuring dropped write wasn't queued");

        // 10. Strict NoC Handshake: RW while EMPTY
        @(negedge clk);
        data_in = 34'hABCD_FACE;
        wr_en   = 1;
        rd_en   = 1; 
        @(posedge clk); #1;
        wr_en = 0; 
        rd_en = 0;
        
        check(0, empty, "FIFO not empty after RW on empty");
        check(34'hABCD_FACE, data_out, "Data safely written despite invalid read request");
        
        @(negedge clk); 
        rd_en = 1;
        @(posedge clk); #1; 
        rd_en = 0;

        // Summary
        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    initial begin
        $dumpfile("tb_input_buffer_fifo.vcd");
        $dumpvars(0, tb_input_buffer_fifo);
    end

endmodule
