// tb_uart_standalone.sv
// =============================================================================
// PHASE 1: Standalone UART TX → RX loopback test.
//
// PURPOSE: Verify uart_tx.sv and uart_rx.sv work correctly BEFORE connecting
//          them to the NoC.  Tests at realistic 100 MHz / 115200 baud but uses
//          a shortened BIT_PERIOD for simulation speed (SIM_BIT_PERIOD=87 →
//          corresponds to 10 MHz / 115200 if BIT_PERIOD ≈ 87).
//          Both TX and RX are parameterised identically so the ratio is correct.
//
// TEST CASES:
//   TC1: Single byte 0x55 (alternating pattern, easy to see on wave)
//   TC2: Single byte 0xAA (inverse)
//   TC3: 0x00 (all zeros — all-zero data bits, tests start/stop framing)
//   TC4: 0xFF (all ones — tests stop-bit collision edge)
//   TC5: Burst of 4 back-to-back bytes: 0xA5, 0x3C, 0xDE, 0xAD
//
// PASS/FAIL: $display reports each check; final tally at end.
//            $finish always called — never hangs.
//
// Vivado 2025:
//   • .sv extension — uses SystemVerilog throughout
//   • No automatic tasks across module boundaries
//   • No force/release
//   • No $random (uses explicit constants)
//   • Watchdog always fires $finish
// =============================================================================

`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Sim-speed parameters:
//   CLK_PERIOD = 10 ns → 100 MHz
//   SIM_BIT_PERIOD = 87 → baud divider (shortens sim from real 868 clocks)
//   Both TX and RX use the same SIM_BIT_PERIOD so sampling is aligned.
// ---------------------------------------------------------------------------
`define CLK_PERIOD    10
`define SIM_CPB       87    // clocks per bit (real 100MHz/115200 ≈ 868; /10 for speed)
`define CLK_FREQ      (115200 * `SIM_CPB)   // "virtual" clock frequency
`define BAUD_RATE     115200

module tb_uart_standalone;

    // Clock & reset
    logic clk = 0;
    logic rst_n = 0;

    always #(`CLK_PERIOD / 2) clk = ~clk;

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1;
    end

    // DUT: uart_tx and uart_rx wired in loopback
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready;
    logic       serial_line;

    logic [7:0] rx_data;
    logic       rx_valid;

    uart_tx #(
        .CLK_FREQ  (`CLK_FREQ),
        .BAUD_RATE (`BAUD_RATE)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready),
        .tx       (serial_line)
    );

    uart_rx #(
        .CLK_FREQ  (`CLK_FREQ),
        .BAUD_RATE (`BAUD_RATE)
    ) u_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (serial_line),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    // Scoreboard
    int pass_cnt = 0;
    int fail_cnt = 0;

    // Mailbox-style: store expected bytes in a small queue
    logic [7:0] expected_q [0:15];
    int         exp_wr = 0;
    int         exp_rd = 0;

    // Check on rx_valid
    always_ff @(posedge clk) begin
        if (rx_valid) begin
            if (exp_rd < exp_wr) begin
                if (rx_data === expected_q[exp_rd]) begin
                    $display("  [PASS] rx_data=0x%02h  expected=0x%02h",
                             rx_data, expected_q[exp_rd]);
                    pass_cnt <= pass_cnt + 1;
                end else begin
                    $display("  [FAIL] rx_data=0x%02h  expected=0x%02h  <-- MISMATCH",
                             rx_data, expected_q[exp_rd]);
                    fail_cnt <= fail_cnt + 1;
                end
                exp_rd <= exp_rd + 1;
            end else begin
                $display("  [FAIL] Unexpected rx_valid: rx_data=0x%02h (no expectation)", rx_data);
                fail_cnt <= fail_cnt + 1;
            end
        end
    end

    // Task: send one byte and register it in the scoreboard
    task automatic send_byte (input logic [7:0] b);
        // Wait until TX is ready
        while (!tx_ready) @(posedge clk);
        @(posedge clk);
        tx_data  = b;
        tx_valid = 1'b1;
        @(posedge clk);
        tx_valid = 1'b0;
        // Register expectation
        expected_q[exp_wr] = b;
        exp_wr = exp_wr + 1;
        // Wait for TX to complete before returning (caller can overlap if needed)
        @(posedge clk);
    endtask

    // Task: wait for N bytes to arrive at RX (with timeout)
    task automatic wait_rx (input int n_bytes);
        int       target;
        int       timeout;
        int       received;
        target   = exp_rd + n_bytes;
        timeout  = n_bytes * (`SIM_CPB * 15);  // 15 bit-times per byte
        received = 0;
        while (received < n_bytes && timeout > 0) begin
            @(posedge clk);
            timeout = timeout - 1;
            if (rx_valid) received = received + 1;
        end
        if (timeout == 0)
            $display("  [WARN] wait_rx(%0d) timed out after %0d cycles", n_bytes, n_bytes*`SIM_CPB*15);
    endtask

    // Stimulus
    initial begin
        tx_data  = 8'h00;
        tx_valid = 1'b0;

        $display("==========================================================");
        $display("  PHASE 1: UART Standalone Loopback Test");
        $display("  CLK=%0d MHz  BAUD=%0d  BIT_PERIOD=%0d clocks",
                 `CLK_FREQ / 1_000_000, `BAUD_RATE, `SIM_CPB);
        $display("==========================================================");

        wait (rst_n);
        repeat (5) @(posedge clk);

        // TC1: 0x55 — alternating 01010101
        $display("\n[TC1] Single byte 0x55 (alternating pattern)");
        send_byte(8'h55);
        wait_rx(1);
        repeat (`SIM_CPB * 2) @(posedge clk);

        // TC2: 0xAA — inverse alternating
        $display("\n[TC2] Single byte 0xAA");
        send_byte(8'hAA);
        wait_rx(1);
        repeat (`SIM_CPB * 2) @(posedge clk);

        // TC3: 0x00 — all zeros (data bits all low, start bit same polarity)
        $display("\n[TC3] Single byte 0x00 (all-zero data)");
        send_byte(8'h00);
        wait_rx(1);
        repeat (`SIM_CPB * 2) @(posedge clk);

        // TC4: 0xFF — all ones (data bits all high, merges with stop bit)
        $display("\n[TC4] Single byte 0xFF (all-ones data)");
        send_byte(8'hFF);
        wait_rx(1);
        repeat (`SIM_CPB * 2) @(posedge clk);

        // TC5: Burst of 4 bytes back-to-back
        $display("\n[TC5] Burst: 0xA5, 0x3C, 0xDE, 0xAD");
        send_byte(8'hA5);
        send_byte(8'h3C);
        send_byte(8'hDE);
        send_byte(8'hAD);
        wait_rx(4);
        repeat (`SIM_CPB * 4) @(posedge clk);

        // Results
        repeat (20) @(posedge clk);
        $display("\n==========================================================");
        $display("  PHASE 1 RESULTS: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
        $display("==========================================================\n");
        $finish;
    end

    // Watchdog
    initial begin
        // 200 bit-times × 10 bytes × safety margin
        #(`CLK_PERIOD * `SIM_CPB * 200);
        $display("[WATCHDOG] PHASE 1 timeout — forcing $finish");
        $finish;
    end

    // VCD
    initial begin
        $dumpfile("tb_uart_standalone.vcd");
        $dumpvars(0, tb_uart_standalone);
    end

endmodule
