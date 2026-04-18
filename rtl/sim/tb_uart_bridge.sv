// tb_uart_bridge.sv
//   UART Protocol Bridge Testbench (Parser & Formatter)
//   - Validates the logical protocol bridging between the UART byte stream 
//     and the NoC parallel fabric.
//   - Parser Tests: Injects raw bytes directly into the parser's RX interface. 
//     Verifies it rejects garbage, catches the start frame, and correctly 
//     extracts the `is_binary` flag, destination node, and full payload.
//   - Formatter Tests: Injects parallel NoC flit data directly into the 
//     formatter. Verifies it correctly serializes the 8-byte sequence 
//     (Header, 5-byte Payload, 2-byte Latency).

`timescale 1ns / 1ps

module tb_uart_bridge;

    parameter integer PAYLOAD_BYTES = 5; 
    parameter integer TS_WIDTH      = 16;

    logic clk = 0;
    logic rst_n = 0;

    // Parser Signals
    logic [7:0] rx_data = 0;
    logic       rx_valid = 0;
    logic       cmd_valid;
    logic       cmd_is_binary;
    logic [1:0] cmd_dest_node;
    logic [(PAYLOAD_BYTES*8)-1:0] cmd_payload;
    logic [$clog2(PAYLOAD_BYTES+1)-1:0] cmd_payload_len;

    // Formatter Signals
    logic       fmt_valid = 0;
    logic       fmt_is_binary = 0; 
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

    // Variables for ASCII capture
    string ascii_out;
    int    ascii_bytes;
        
    uart_cmd_parser #(.PAYLOAD_BYTES(PAYLOAD_BYTES)) u_parser (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .cmd_valid(cmd_valid), 
        .cmd_is_binary(cmd_is_binary),
        .cmd_dest_node(cmd_dest_node),
        .cmd_payload(cmd_payload), .cmd_payload_len(cmd_payload_len)
    );

    uart_resp_formatter #(.PAYLOAD_BYTES(PAYLOAD_BYTES), .TS_WIDTH(TS_WIDTH)) u_formatter (
        .clk(clk), .rst_n(rst_n),
        .fmt_valid(fmt_valid), 
        .is_binary(fmt_is_binary),
        .fmt_src_node(fmt_src_node),
        .fmt_payload(fmt_payload), .fmt_payload_len(fmt_payload_len),
        .fmt_latency(fmt_latency),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .fmt_busy(fmt_busy)
    );

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

    always #5 clk = ~clk;

    initial begin
        $display("==========================================================");
        $display("      UART Protocol Bridge (Parser & Formatter) Tests");
        $display("==========================================================");

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // =========================================================
        // Test1: Garbage bytes before a valid command.
        // Test2: Standard binary command (0xA2 + 5 payload bytes).
        // =========================================================
        $display("\n--- Testing uart_cmd_parser ---");
        
        send_rx_byte(8'hFF);
        send_rx_byte(8'h42);
        @(negedge clk);
        if (cmd_valid === 1'b0) pass_test("Parser ignored garbage bytes");
        else fail_test("Parser triggered on garbage bytes");

        // Send Valid Command: 0xA2 + 5 Payload Bytes (ABCDE)
        send_rx_byte(8'hA2); // Header
        send_rx_byte(8'h41); // 'A'
        send_rx_byte(8'h42); // 'B'
        send_rx_byte(8'h43); // 'C'
        send_rx_byte(8'h44); // 'D'
        send_rx_byte(8'h45); // 'E'
        
        while (cmd_valid !== 1'b1) @(negedge clk); 
        if (cmd_dest_node === 2'd2 && cmd_payload === 40'h4142434445 && cmd_is_binary === 1'b1)
            pass_test("Parser correctly framed 0xA2 + 5-byte payload in BINARY mode");
        else
            fail_test("Parser failed to frame command properly");

        // ===========================================================================
        // Test3: Standard binary response (0xB3 + 5 payload bytes + 2 latency bytes).
        // ===========================================================================
        $display("\n--- Testing uart_resp_formatter ---");
        
        @(negedge clk);
        fmt_src_node  = 2'd3;               // Source Node 3
        fmt_payload   = 40'h11_22_44_45_46; // 5-Byte Payload
        fmt_latency   = 16'h1234;         
        fmt_is_binary = 1'b1;             
        fmt_valid     = 1'b1;
        @(negedge clk);
        fmt_valid     = 1'b0;

        while(!tx_valid) @(negedge clk);

        // Byte 0: Header (0xB0 | 3 = 0xB3)
        if (tx_data === 8'hB3) pass_test("Formatter output Byte 0: Header (0xB3)");
        else fail_test($sformatf("Formatter header failed, got %h", tx_data));
        @(negedge clk);

        // Byte 1: Payload [39:32] (0x11)
        if (tx_data === 8'h11) pass_test("Formatter output Byte 1: Payload B1");
        else fail_test($sformatf("Formatter Payload B1 failed, got %h", tx_data));
        @(negedge clk);

        // Byte 2: Payload [31:24] (0x22)
        if (tx_data === 8'h22) pass_test("Formatter output Byte 2: Payload B2");
        else fail_test($sformatf("Formatter Payload B2 failed, got %h", tx_data));
        @(negedge clk);

        // Byte 3: Payload [23:16] (0x44)
        if (tx_data === 8'h44) pass_test("Formatter output Byte 3: Payload B3");
        else fail_test($sformatf("Formatter Payload B3 failed, got %h", tx_data));
        @(negedge clk);

        // Byte 4: Payload [15:8] (0x45)
        if (tx_data === 8'h45) pass_test("Formatter output Byte 4: Payload B4");
        else fail_test($sformatf("Formatter Payload B4 failed, got %h", tx_data));
        @(negedge clk);

        // Byte 5: Payload [7:0] (0x46)
        if (tx_data === 8'h46) pass_test("Formatter output Byte 5: Payload B5");
        else fail_test($sformatf("Formatter Payload B5 failed, got %h", tx_data));
        @(negedge clk);

        // Byte 6: Latency High (0x12)
        if (tx_data === 8'h12) pass_test("Formatter output Byte 6: Latency High");
        else fail_test($sformatf("Formatter Latency High failed, got %h", tx_data));
        @(negedge clk);

        // Byte 7: Latency Low (0x34)
        if (tx_data === 8'h34) pass_test("Formatter output Byte 7: Latency Low");
        else fail_test($sformatf("Formatter Latency Low failed, got %h", tx_data));
        @(negedge clk);

        if (!fmt_busy && !tx_valid) pass_test("Formatter cleanly exited busy state");
        else fail_test("Formatter hung in busy state");

        // ===========================================================================
        // Test4: Backpressure (simulating a busy UART TX mid-transmission to prove 
        //        no data is dropped).
        // ===========================================================================
        $display("\n--- Testing Formatter Backpressure ---");
        
        @(negedge clk);
        fmt_src_node  = 2'd1;
        fmt_payload   = 40'h11_22_99_88_77;
        fmt_latency   = 16'h000A;
        fmt_is_binary = 1'b1;
        fmt_valid     = 1'b1;
        @(negedge clk);
        fmt_valid     = 1'b0;

        // Wait for Header (0xB1)
        while(!tx_valid) @(negedge clk);
        
        // Allow Header to go, putting Byte 1 (0x11) on the bus
        @(negedge clk); 
        
        // Pulls UART TX ready LOW
        tx_ready = 1'b0; 
        
        repeat(3) @(negedge clk); 
        
        if (tx_valid && tx_data === 8'h11 && fmt_busy)
            pass_test("Formatter correctly held data (0x11) steady while tx_ready was low");
        else
            fail_test($sformatf("Formatter dropped data during backpressure! Got %h", tx_data));

        tx_ready = 1'b1;
        
        // Get the remaining 7 bytes (11, 22, 99, 88, 77, 00, 0A)
        repeat(7) @(negedge clk); 
        
        if (!fmt_busy) pass_test("Formatter recovered from backpressure and finished");
        else fail_test("Formatter failed to recover from backpressure");

        // =========================================================
        // Test5: ASCII Formatter Verification        
        // =========================================================
        $display("\n--- Testing Formatter ASCII String Generation ---");
                
        @(negedge clk);
        fmt_src_node  = 2'd2;                 // Source Node 2
        fmt_payload   = 40'h41_42_43_44_45;   // "ABCDE"
        fmt_latency   = 16'h0005;             // 5 cycles
        fmt_is_binary = 1'b0;                 // ASCII mode
        fmt_valid     = 1'b1;
        @(negedge clk);
        fmt_valid     = 1'b0;
        
        while(!tx_valid) @(negedge clk);
        ascii_out = "";
        ascii_bytes = 0;
        
        // Loop to capture the entire string as it is transmitted byte-by-byte
        while(fmt_busy || tx_valid) begin
            if (tx_valid && tx_ready) begin
                ascii_out = {ascii_out, string'(tx_data)};
                ascii_bytes++;
            end
            @(negedge clk);
        end
        
        $display("  Captured String : %s", ascii_out);
        if (ascii_bytes == 30 && ascii_out == "[Node 2] ABCDE L: 0005 cycles\n") begin
            pass_test("Formatter generated perfect 30-Byte ASCII string!");
        end else begin
            fail_test($sformatf("ASCII String mismatch. Got %d bytes", ascii_bytes));
        end
                
        $display("\n==========================================================");
        $display("            PHASE 2 RESULTS: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
        $display("==========================================================\n");
        $finish;
    end

endmodule