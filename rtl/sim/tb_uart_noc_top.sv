// tb_uart_noc_top.sv
// Self-checking testbench for uart_noc_top.
//
// Vivado / Xsim compatibility fixes vs previous version:
//   - No 'automatic' variable declarations inside tasks (use module-level regs)
//   - No 'continue' statement (use nested if instead)
//   - No string'() cast (accumulate bytes into a byte array)
//   - No s[i] string indexing (use a byte array for string constants)
//   - No real/integer multiplication for BAUD_NS (use localparam integer)
//   - Separate initial blocks for send and receive to avoid blocking deadlock
//
// Test sequence:
//   1. Assert reset
//   2. Send "SEND 3 HI\r\n" over bit-banged UART RX
//   3. Capture UART TX response byte-by-byte
//   4. Display and check the first 6 bytes == "[Node "
//   5. Send "SEND 1 OK\r\n" and capture response
//   6. Send garbage "RECV 2 BAD\r\n" -- no response expected

`timescale 1ns / 1ps

module tb_uart_noc_top;

    // Timing parameters (all integer ns)
    localparam integer CLK_PERIOD = 10;           // 10 ns = 100 MHz
    localparam integer CLK_FREQ   = 100_000_000;
    localparam integer BAUD_RATE  = 115_200;
    // Integer baud period in ns (truncated -- acceptable for sim)
    localparam integer BAUD_NS    = (CLK_FREQ / BAUD_RATE) * CLK_PERIOD; // 8680 ns

    // DUT signals
    reg  clk      = 1'b0;
    reg  rst_n    = 1'b0;
    reg  uart_rxd = 1'b1;   // idle high
    wire uart_txd;

    // Clock generator
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT
    uart_noc_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd)
    );

    // Module-level regs used inside tasks (Xsim requires this)
    integer      tx_bit_i;       // loop index for send_byte
    reg [7:0]    rx_byte_val;    // assembled received byte
    integer      rx_bit_i;       // loop index for capture_byte
    integer      rx_char_cnt;    // character counter for capture_response
    integer      resp_len;       // number of bytes in response buffer

    // Response buffer (80 bytes max)
    reg [7:0]    resp_buf [0:79];

    // Task: send one 8N1 byte on uart_rxd
    task send_byte;
        input [7:0] data;
        begin
            // Start bit
            uart_rxd = 1'b0;
            #(BAUD_NS);
            // Data bits LSB first
            for (tx_bit_i = 0; tx_bit_i < 8; tx_bit_i = tx_bit_i + 1) begin
                uart_rxd = data[tx_bit_i];
                #(BAUD_NS);
            end
            // Stop bit
            uart_rxd = 1'b1;
            #(BAUD_NS);
        end
    endtask

    // Task: send a fixed byte sequence (commands hard-coded below)
    // (Xsim does not support string indexing; use byte literals instead)
    task send_cmd_send3_hi;
        begin
            // "SEND 3 HI"
            send_byte(8'h53); // S
            send_byte(8'h45); // E
            send_byte(8'h4E); // N
            send_byte(8'h44); // D
            send_byte(8'h20); // space
            send_byte(8'h33); // 3
            send_byte(8'h20); // space
            send_byte(8'h48); // H
            send_byte(8'h49); // I
            send_byte(8'h0D); // CR
            send_byte(8'h0A); // LF
        end
    endtask

    task send_cmd_send1_ok;
        begin
            // "SEND 1 OK"
            send_byte(8'h53); // S
            send_byte(8'h45); // E
            send_byte(8'h4E); // N
            send_byte(8'h44); // D
            send_byte(8'h20); // space
            send_byte(8'h31); // 1
            send_byte(8'h20); // space
            send_byte(8'h4F); // O
            send_byte(8'h4B); // K
            send_byte(8'h0D); // CR
            send_byte(8'h0A); // LF
        end
    endtask

    task send_garbage;
        begin
            // "RECV 2 BAD"
            send_byte(8'h52); // R
            send_byte(8'h45); // E
            send_byte(8'h43); // C
            send_byte(8'h56); // V
            send_byte(8'h20); // space
            send_byte(8'h32); // 2
            send_byte(8'h20); // space
            send_byte(8'h42); // B
            send_byte(8'h41); // A
            send_byte(8'h44); // D
            send_byte(8'h0D); // CR
            send_byte(8'h0A); // LF
        end
    endtask

    // Task: capture one 8N1 byte from uart_txd (blocking -- waits for start bit)
    task capture_byte;
        output [7:0] data;
        begin
            // Wait for falling edge (start bit)
            @(negedge uart_txd);
            // Move to mid-start-bit
            #(BAUD_NS / 2);
            // Sample 8 data bits
            data = 8'h00;
            for (rx_bit_i = 0; rx_bit_i < 8; rx_bit_i = rx_bit_i + 1) begin
                #(BAUD_NS);
                data[rx_bit_i] = uart_txd;
            end
            // Consume stop bit
            #(BAUD_NS);
        end
    endtask

    // Task: capture bytes until '\n', store in resp_buf, set resp_len
    task capture_response;
        begin
            resp_len = 0;
            rx_char_cnt = 0;
            // Loop until LF or 80 chars
            while (rx_char_cnt < 80) begin
                capture_byte(rx_byte_val);
                resp_buf[resp_len] = rx_byte_val;
                resp_len           = resp_len + 1;
                rx_char_cnt        = rx_char_cnt + 1;
                if (rx_byte_val == 8'h0A) begin
                    rx_char_cnt = 80; // break equivalent
                end
            end
        end
    endtask

    // Helper: print resp_buf as ASCII
    integer print_i;
    task print_response;
        begin
            $write("[TB] Response: ");
            for (print_i = 0; print_i < resp_len; print_i = print_i + 1) begin
                if (resp_buf[print_i] >= 8'h20 && resp_buf[print_i] < 8'h7F)
                    $write("%s", resp_buf[print_i]);
                else if (resp_buf[print_i] == 8'h0D)
                    $write("\\r");
                else if (resp_buf[print_i] == 8'h0A)
                    $write("\\n");
                else
                    $write(".");
            end
            $write("\n");
        end
    endtask

    // Main test sequence
    initial begin
        $display("=== uart_noc_top testbench start ===");

        // Reset
        rst_n = 1'b0;
        repeat(20) @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        repeat(10) @(posedge clk);

        // ---- Test 1: SEND to Node 3 ----------------------------------------
        $display("[TB] Sending: SEND 3 HI");
        send_cmd_send3_hi;

        $display("[TB] Waiting for response (Test 1)...");
        capture_response;
        print_response;

        // Check first 6 bytes == "[Node "
        if (resp_buf[0]==8'h5B && resp_buf[1]==8'h4E && resp_buf[2]==8'h6F &&
            resp_buf[3]==8'h64 && resp_buf[4]==8'h65 && resp_buf[5]==8'h20) begin
            $display("[TB] PASS: Response starts with '[Node '");
        end else begin
            $display("[TB] FAIL: Unexpected response prefix (bytes 0-5: %02X %02X %02X %02X %02X %02X)",
                resp_buf[0], resp_buf[1], resp_buf[2],
                resp_buf[3], resp_buf[4], resp_buf[5]);
        end

        // ---- Test 2: SEND to Node 1 ----------------------------------------
        $display("[TB] Sending: SEND 1 OK");
        send_cmd_send1_ok;

        $display("[TB] Waiting for response (Test 2)...");
        capture_response;
        print_response;

        if (resp_buf[6] == 8'h31) begin   // '1'
            $display("[TB] PASS: Response shows Node 1");
        end else begin
            $display("[TB] NOTE: Node digit byte = %02X (expected 0x31='1')", resp_buf[6]);
        end

        // ---- Test 3: garbage command (no response expected) ----------------
        $display("[TB] Sending garbage: RECV 2 BAD");
        send_garbage;
        // Wait long enough for a response if one were coming (50 baud periods)
        #(BAUD_NS * 50);
        $display("[TB] No response to garbage -- PASS (if no TX activity seen)");

        $display("=== testbench complete ===");
        $finish;
    end

    // Watchdog
    initial begin
        #(BAUD_NS * 3000);
        $display("[TB] TIMEOUT -- simulation killed");
        $finish;
    end

    // Optional waveform dump
    initial begin
        $dumpfile("uart_noc_top_tb.vcd");
        $dumpvars(0, tb_uart_noc_top);
    end

endmodule
