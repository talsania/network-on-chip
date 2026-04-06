// tb_uart_bridge.sv
//   PHASE 2: Protocol Bridge Test (Parser & Formatter)
//  
//   PURPOSE: Verifies the NoC-to-UART bridging logic without needing the slow
//            physical UART bit-banging. We simulate the byte-level AXI-Stream 
//            handshakes directly.
//
//   TEST CASES:
//     TC1: Parser - Ignore garbage bytes before a valid command.
//     TC2: Parser - Standard command (0xA2 + 3 payload bytes).
//     TC3: Formatter - Standard response (0xB3 + 3 payload bytes + 2 latency bytes)
//     TC4: Formatter - Backpressure (simulating a busy UART TX mid-transmission).

`timescale 1ns / 1ps

module tb_uart_bridge;

    parameter integer PAYLOAD_BYTES = 3;
    parameter integer TS_WIDTH      = 16;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    // Parser Signals
    logic [7:0] rx_data = 0;
    logic       rx_valid = 0;
    logic       cmd_valid;
    logic [1:0] cmd_dest_node;
    logic [(PAYLOAD_BYTES*8)-1:0] cmd_payload;
    logic [$clog2(PAYLOAD_BYTES+1)-1:0] cmd_payload_len;

    // Formatter Signals
    logic       fmt_valid = 0;
    logic [1:0] fmt_src_node = 0;
    logic [(PAYLOAD_BYTES*8)-1:0] fmt_payload = 0;
    logic [$clog2(PAYLOAD_BYTES+1)-1:0] fmt_payload_len = PAYLOAD_BYTES;
    logic [TS_WIDTH-1:0] fmt_latency = 0;
    
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready = 1;
    logic       fmt_busy;

    int pass_cnt = 0;
    int fail_cnt = 0;

    uart_cmd_parser #(.PAYLOAD_BYTES(PAYLOAD_BYTES)) u_parser (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .cmd_valid(cmd_valid), .cmd_dest_node(cmd_dest_node),
        .cmd_payload(cmd_payload), .cmd_payload_len(cmd_payload_len)
    );

    uart_resp_formatter #(.PAYLOAD_BYTES(PAYLOAD_BYTES), .TS_WIDTH(TS_WIDTH)) u_formatter (
        .clk(clk), .rst_n(rst_n),
        .fmt_valid(fmt_valid), .fmt_src_node(fmt_src_node),
        .fmt_payload(fmt_payload), .fmt_payload_len(fmt_payload_len),
        .fmt_latency(fmt_latency),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .fmt_busy(fmt_busy)
    );

    // Helper Tasks
    task automatic send_rx_byte(input logic [7:0] b);
        @(negedge clk);
        rx_data  = b;
        rx_valid = 1'b1;
        @(negedge clk);
        rx_valid = 1'b0;
    endtask

    task automatic pass_test(string name);
        $display("  [PASS] %s", name);
        pass_cnt++;
    endtask

    task automatic fail_test(string name);
        $display("  [FAIL] %s", name);
        fail_cnt++;
    endtask

    // Stimulus
    initial begin
        $display("==========================================================");
        $display("  PHASE 2: Protocol Bridge (Parser & Formatter) Tests");
        $display("==========================================================");

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // TC1 & TC2: Parser Testing (Garbage Rejection + Valid Command)
        $display("\n--- Testing uart_cmd_parser ---");
        
        // 1. Send Garbage (Should not trigger anything)
        send_rx_byte(8'hFF);
        send_rx_byte(8'h42);
        @(negedge clk);
        if (cmd_valid === 1'b0) pass_test("Parser ignored garbage bytes");
        else fail_test("Parser triggered on garbage bytes");

        // 2. Send Valid Command: Dest=Node 2 (0xA2), Payload = "ABC" (0x41 0x42 0x43)
        send_rx_byte(8'hA2); // Header
        send_rx_byte(8'h41); // Payload Byte 1
        send_rx_byte(8'h42); // Payload Byte 2
        send_rx_byte(8'h43); // Payload Byte 3
        
        while (cmd_valid !== 1'b1) @(negedge clk); // Wait for processing
        if (cmd_dest_node === 2'd2 && cmd_payload === 24'h414243)
            pass_test("Parser correctly framed 0xA2 + 'ABC'");
        else
            fail_test("Parser failed to frame command properly");


        // TC3: Formatter Testing (Serialization)
        $display("\n--- Testing uart_resp_formatter ---");
        
        @(negedge clk);
        fmt_src_node = 2'd3;            // Source Node 3
        fmt_payload  = 24'h44_45_46;    // "DEF"
        fmt_latency  = 16'h1234;        // 4660 cycles
        fmt_valid    = 1'b1;
        @(negedge clk);
        fmt_valid    = 1'b0;

        // Expect Byte 0: Header (0xB0 | 3 = 0xB3)
        if (tx_valid && tx_data === 8'hB3) pass_test("Formatter output Byte 0: Header (0xB3)");
        else fail_test("Formatter header failed");
        @(negedge clk);

        // Expect Byte 1: Payload Hi (0x44)
        if (tx_valid && tx_data === 8'h44) pass_test("Formatter output Byte 1: Payload [23:16]");
        else fail_test("Formatter Payload Hi failed");
        @(negedge clk);

        // Expect Byte 2: Payload Mid (0x45)
        if (tx_valid && tx_data === 8'h45) pass_test("Formatter output Byte 2: Payload [15:8]");
        else fail_test("Formatter Payload Mid failed");
        @(negedge clk);

        // Expect Byte 3: Payload Lo (0x46)
        if (tx_valid && tx_data === 8'h46) pass_test("Formatter output Byte 3: Payload [7:0]");
        else fail_test("Formatter Payload Lo failed");
        @(negedge clk);

        // Expect Byte 4: Latency Hi (0x12)
        if (tx_valid && tx_data === 8'h12) pass_test("Formatter output Byte 4: Latency Hi");
        else fail_test("Formatter Latency Hi failed");
        @(negedge clk);

        // Expect Byte 5: Latency Lo (0x34)
        if (tx_valid && tx_data === 8'h34) pass_test("Formatter output Byte 5: Latency Lo");
        else fail_test("Formatter Latency Lo failed");
        @(negedge clk);

        if (!fmt_busy && !tx_valid) pass_test("Formatter cleanly exited busy state");
        else fail_test("Formatter hung in busy state");

        // TC4: Formatter Backpressure (UART TX is busy)
        $display("\n--- Testing Formatter Backpressure ---");
        
        @(negedge clk);
        fmt_src_node = 2'd1;
        fmt_payload  = 24'h99_88_77;
        fmt_latency  = 16'h000A;
        fmt_valid    = 1'b1;
        @(negedge clk);
        fmt_valid    = 1'b0;

        // Accept Header (0xB1)
        @(negedge clk);
        
        // UART TX gets busy and pulls ready LOW
        tx_ready = 1'b0; 
        
        repeat(3) @(negedge clk); // Wait a few cycles
        
        if (tx_valid && tx_data === 8'h99 && fmt_busy)
            pass_test("Formatter correctly held data steady while tx_ready was low");
        else
            fail_test("Formatter dropped data during UART backpressure");

        tx_ready = 1'b1; // UART recovers
        @(negedge clk); // 99 accepted
        @(negedge clk); // 88 accepted
        @(negedge clk); // 77 accepted
        @(negedge clk); // 00 accepted
        @(negedge clk); // 0A accepted
        
        if (!fmt_busy) pass_test("Formatter recovered from backpressure and finished");
        else fail_test("Formatter failed to recover from backpressure");

        $display("\n==========================================================");
        $display("  PHASE 2 RESULTS: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
        $display("==========================================================\n");
        $finish;
    end

endmodule
