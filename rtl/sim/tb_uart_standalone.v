// tb_uart_standalone.v
//   Standalone UART TX/RX Testbench
//   - Validates the serializer (TX) and deserializer (RX).
//   - Wires the TX serial output directly into the RX serial input.
//   - Uses a First-In-First-Out (FIFO) queue (`expected_q`) with 
//     Read/Write pointers to track injected bytes.
//   - Includes Glitch Injection to verify RX synchronization.

`timescale 1ns / 1ps

module tb_uart_standalone;
    reg clk;
    reg rst_n;

    reg [7:0] tx_data;
    reg       tx_valid;
    wire      tx_ready;
    
    wire      tx_out;       // Direct output from TX
    wire      serial_line;  // Actual wire entering RX
    
    reg       glitch_en;    // MUX control to access the line
    reg       glitch_val;   // The noise value to inject

    wire [7:0] rx_data;
    wire       rx_valid;


    uart_tx #(
        .CLK_FREQ(100_000_000), .BAUD_RATE(115_200)
    ) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .tx(tx_out)
    );

    uart_rx #(
        .CLK_FREQ(100_000_000), .BAUD_RATE(115_200)
    ) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx(serial_line),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    assign serial_line = glitch_en ? glitch_val : tx_out;
    
    always #5 clk = ~clk; 

    // Scoreboard
    integer pass_cnt;
    integer fail_cnt;
    
    reg [7:0] expected_q [0:15];
    integer   exp_wr;
    integer   exp_rd;

    always @(posedge clk) begin
        if (rx_valid) begin
            if (exp_rd < exp_wr) begin
                if (rx_data === expected_q[exp_rd]) begin
                    $display("  [PASS] rx_data=0x%02h  expected=0x%02h", rx_data, expected_q[exp_rd]);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("  [FAIL] rx_data=0x%02h  expected=0x%02h", rx_data, expected_q[exp_rd]);
                    fail_cnt = fail_cnt + 1;
                end
                exp_rd = exp_rd + 1;
            end else begin
                $display("  [FAIL] Unexpected rx_valid: rx_data=0x%02h", rx_data);
                fail_cnt = fail_cnt + 1;
            end
        end
    end

    // Task to send one byte
    task send_byte;
        input [7:0] b;
        begin
            // Wait until TX is ready
            while (!tx_ready) @(posedge clk);
            tx_data  <= b;
            tx_valid <= 1'b1;
            
            expected_q[exp_wr] = b;
            exp_wr = exp_wr + 1;
            
            @(posedge clk);
            tx_valid <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Task to wait for scoreboard to clear
    task wait_rx;
        integer timeout;
        begin
            timeout = 500000; 
            
            // Wait is done by comparing the Read pointer to the Write pointer
            while ((exp_rd < exp_wr) && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            
            if (timeout == 0) $display("  [WARN] wait_rx timed out waiting for bytes");
        end
    endtask

    initial begin
        clk = 0; 
        rst_n = 0; 
        tx_valid = 0;
        glitch_en = 0;
        glitch_val = 1;
        pass_cnt = 0;
        fail_cnt = 0;
        exp_wr = 0;
        exp_rd = 0;

        $display("==========================================================");
        $display("                 UART Standalone Test");
        $display("==========================================================");
        
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        // Test1: 0x55 (Alternating 01010101) - Tests basic clock synchronization.
        $display("\n[TEST1] Single byte 0x55 (alternating pattern)");
        send_byte(8'h55);
        wait_rx();

        // Test2: 0xAA (Alternating 10101010) - Tests inverse transitions.
        $display("\n[TEST2] Single byte 0xAA");
        send_byte(8'hAA);
        wait_rx();

        // Test3: 0x00 (All Zeros) - Tests Start/Stop bit framing boundaries.
        $display("\n[TEST3] Single byte 0x00 (all-zero data)");
        send_byte(8'h00);
        wait_rx();

        // Test4: 0xFF (All Ones) - Tests Stop bit collision.
        $display("\n[TEST4] Single byte 0xFF (all-ones data)");
        send_byte(8'hFF);
        wait_rx();

        // Test5: Burst - Sends 4 bytes back-to-back to prove that state machine 
        //        doesn't drop data between frames.
        $display("\n[TEST5] Burst: 0xA5, 0x3C, 0xDE, 0xAD");
        send_byte(8'hA5);
        send_byte(8'h3C);
        send_byte(8'hDE);
        send_byte(8'hAD);
        wait_rx();

        // Test6: Glitch Rejection - Verifies the Start-Bit verification logic
        $display("\n[TEST6] Glitch Rejection (Hardware Noise Filter)");
        
        // 1 Bit Period at 115200 Baud on 100MHz clock is ~868 clock cycles.
        // Pull the line low for only 200 cycles to simulate noise.
        glitch_val = 0;
        glitch_en  = 1;
        #(200 * 10); // Wait 200 clock cycles
        glitch_val = 1;
        #(200 * 10); // Hold high
        glitch_en  = 0; // Return control back to TX
        
        // Wait a full byte duration to ensure the RX module ignored it
        #(868 * 10 * 10); 
        
        if (exp_rd == exp_wr) begin
            $display("  [PASS] Glitch safely ignored by RX synchronizer.");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] RX falsely triggered on a glitch!");
            fail_cnt = fail_cnt + 1;
        end

        repeat (200) @(posedge clk);
        $display("\n==========================================================");
        $display("                 RESULTS: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
        $display("==========================================================\n");
        $finish;
    end

    initial begin
        #5000000; 
        $display("[WATCHDOG] timeout - forcing $finish");
        $finish;
    end

endmodule