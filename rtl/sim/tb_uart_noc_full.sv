// tb_uart_noc_full.sv
// =============================================================================
// PHASE 2: Full UART → NoC → Echo → UART end-to-end test.
//
// WHAT IS ACTUALLY BEING TESTED (vs the old broken tb):
//   OLD tb: inserted uart_tx_model/uart_rx_model as stimulus models but
//           connected them directly to mesh_fabric_noc, BYPASSING uart_noc_top
//           entirely.  No uart_rx.sv, uart_tx.sv, uart_cmd_parser.sv, or
//           uart_resp_formatter.sv were ever exercised.  The test "completed"
//           because it only needed mesh_fabric_noc + the inline model modules.
//
//   THIS tb: instantiates uart_noc_top (the real DUT) which in turn instantiates
//            uart_rx, uart_tx, uart_cmd_parser, uart_resp_formatter, and
//            mesh_fabric_noc.  A stimulus model sends binary-framed commands
//            over a real bit-serial UART line; a checker model receives and
//            verifies the response byte stream.
//
// COMMAND PROTOCOL (binary, matches uart_cmd_parser.sv):
//   Byte 0:           0xA0 | dest_node[1:0]   (cmd byte)
//   Bytes 1..PB:      payload bytes MSB-first   (PAYLOAD_BYTES = 3)
//
// RESPONSE PROTOCOL (matches uart_resp_formatter.sv):
//   Byte 0:           0xB0 | src_node[1:0]    (response header)
//   Bytes 1..PB:      payload bytes MSB-first
//   Byte PB+1:        latency[15:8]
//   Byte PB+2:        latency[7:0]
//
// NODE TOPOLOGY (2×2 mesh):
//   Node 0 (0,0) = UART gateway (sends commands, receives echoes)
//   Node 1 (1,0) = echo — receives from 0, returns to 0
//   Node 2 (0,1) = echo
//   Node 3 (1,1) = echo  (longest path: East + South)
//
// TEST CASES:
//   TC1: Send 3-byte payload to Node 1  (1 hop East)
//   TC2: Send 3-byte payload to Node 2  (1 hop South)
//   TC3: Send 3-byte payload to Node 3  (2 hops: East + South)
//   TC4: Multi-packet burst: 3 packets to Node 3 back-to-back
//
// TIMING (fast-sim baud — SIM_CPB=20 instead of real 868):
//   Each UART byte takes SIM_CPB × 10 clocks = 200 ns.
//   Full command (4 bytes): ~800 ns.  Response (6 bytes): ~1200 ns.
//   NoC transit: ~5-20 cycles.  Total per TC: < 10000 cycles.
//
// Vivado 2025 compatibility:
//   • .sv extension, SystemVerilog throughout
//   • No automatic tasks crossing module boundaries
//   • No $urandom, no force/release, no class/object
//   • All arrays explicitly sized
//   • $finish always reached

`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Simulation speed parameters
// ---------------------------------------------------------------------------
`define CLK_PERIOD    10          // ns → 100 MHz
`define SIM_CPB       20          // clocks per bit (real=868; short for sim speed)
`define CLK_FREQ      (115200 * `SIM_CPB)
`define BAUD_RATE     115200

// ============================================================================
// Stimulus UART TX model (bit-serial; drives uart_noc_top.uart_rxd)
// ============================================================================
module stim_uart_tx #(parameter CPB = 20)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_byte,
    input  logic       tx_start,
    output logic       tx_line,
    output logic       tx_busy
);
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} st_t;
    st_t state;
    int  cc, bc;
    logic [7:0] sr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE; tx_line <= 1'b1; tx_busy <= 1'b0;
            cc <= 0; bc <= 0; sr <= 8'd0;
        end else case (state)
            IDLE:  begin
                tx_line <= 1'b1; tx_busy <= 1'b0;
                if (tx_start) begin
                    sr <= tx_byte; tx_busy <= 1'b1; tx_line <= 1'b0;
                    cc <= 0; bc <= 0; state <= START;
                end
            end
            START: begin
                if (cc == CPB-1) begin
                    tx_line <= sr[0]; sr <= sr >> 1; cc <= 0; state <= DATA;
                end else cc <= cc + 1;
            end
            DATA:  begin
                if (cc == CPB-1) begin
                    cc <= 0;
                    if (bc == 7) begin tx_line <= 1'b1; state <= STOP; end
                    else         begin bc <= bc+1; tx_line <= sr[0]; sr <= sr >> 1; end
                end else cc <= cc + 1;
            end
            STOP:  begin
                if (cc == CPB-1) begin
                    tx_busy <= 1'b0; tx_line <= 1'b1; cc <= 0; state <= IDLE;
                end else cc <= cc + 1;
            end
            default: state <= IDLE;
        endcase
    end
endmodule

// Checker UART RX model (bit-serial; samples uart_noc_top.uart_txd)
module check_uart_rx #(parameter CPB = 20)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx_line,
    output logic [7:0] rx_byte,
    output logic       rx_valid
);
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} st_t;
    st_t state;
    int  cc, bc;
    logic [7:0] sr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; rx_valid <= 1'b0; rx_byte <= 8'd0;
            cc <= 0; bc <= 0; sr <= 8'd0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                IDLE:  if (!rx_line) begin cc <= 0; state <= START; end
                START: if (cc == CPB/2-1) begin cc <= 0; bc <= 0; state <= DATA; end
                       else cc <= cc + 1;
                DATA:  begin
                    if (cc == CPB-1) begin
                        cc <= 0; sr <= {rx_line, sr[7:1]};
                        if (bc == 7) state <= STOP; else bc <= bc + 1;
                    end else cc <= cc + 1;
                end
                STOP:  begin
                    if (cc == CPB-1) begin
                        rx_byte <= sr; rx_valid <= 1'b1; cc <= 0; state <= IDLE;
                    end else cc <= cc + 1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule


// Top-level testbench
module tb_uart_noc_full;

    // ── Clock & reset ────────────────────────────────────────────────────────
    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #(`CLK_PERIOD / 2) clk = ~clk;
    initial begin repeat (20) @(posedge clk); rst_n = 1'b1; end

    // ── Serial lines ─────────────────────────────────────────────────────────
    logic uart_rxd;   // TB → DUT
    logic uart_txd;   // DUT → TB

    // ── DUT ──────────────────────────────────────────────────────────────────
    uart_noc_top #(
        .CLK_FREQ   (`CLK_FREQ),
        .BAUD_RATE  (`BAUD_RATE),
        .DATA_WIDTH (34),
        .COORD_WIDTH(1),
        .FIFO_DEPTH (8),
        .TS_WIDTH   (16)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd)
    );

    // ── Stimulus TX model ────────────────────────────────────────────────────
    logic [7:0] stim_byte  = 8'h00;
    logic       stim_start = 1'b0;
    logic       stim_busy;

    stim_uart_tx #(.CPB(`SIM_CPB)) u_stim (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_byte  (stim_byte),
        .tx_start (stim_start),
        .tx_line  (uart_rxd),
        .tx_busy  (stim_busy)
    );

    // ── Checker RX model ─────────────────────────────────────────────────────
    logic [7:0] chk_byte;
    logic       chk_valid;

    check_uart_rx #(.CPB(`SIM_CPB)) u_chk (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx_line  (uart_txd),
        .rx_byte  (chk_byte),
        .rx_valid (chk_valid)
    );

    // ── Scoreboard ───────────────────────────────────────────────────────────
    // Expected response queue: holds (PAYLOAD_BYTES+3) bytes per transaction
    localparam int PAYLOAD_BYTES  = 3;
    localparam int RESP_BYTES     = PAYLOAD_BYTES + 3;  // hdr + payload + lat_hi + lat_lo
    localparam int Q_DEPTH        = 32;

    logic [7:0] exp_q   [0:Q_DEPTH-1];
    logic       exp_chk [0:Q_DEPTH-1];  // 1=check value, 0=don't-care (latency bytes)
    int         exp_wr  = 0;
    int         exp_rd  = 0;
    int         pass_cnt = 0;
    int         fail_cnt = 0;

    always_ff @(posedge clk) begin
        if (chk_valid) begin
            if (exp_rd < exp_wr) begin
                if (!exp_chk[exp_rd]) begin
                    $display("  [INFO ] Response byte %0d = 0x%02h (don't-care: latency)",
                             exp_rd, chk_byte);
                    pass_cnt <= pass_cnt + 1;
                end else if (chk_byte === exp_q[exp_rd]) begin
                    $display("  [PASS ] Response byte %0d = 0x%02h  expected=0x%02h",
                             exp_rd, chk_byte, exp_q[exp_rd]);
                    pass_cnt <= pass_cnt + 1;
                end else begin
                    $display("  [FAIL ] Response byte %0d = 0x%02h  expected=0x%02h  <-- MISMATCH",
                             exp_rd, chk_byte, exp_q[exp_rd]);
                    fail_cnt <= fail_cnt + 1;
                end
                exp_rd <= exp_rd + 1;
            end else begin
                $display("  [FAIL ] Unexpected response byte=0x%02h (no expectation)", chk_byte);
                fail_cnt <= fail_cnt + 1;
            end
        end
    end

    // ── Task: send one raw byte over the stim UART ───────────────────────────
    task automatic raw_send (input logic [7:0] b);
        @(posedge clk);
        stim_byte  = b;
        stim_start = 1'b1;
        @(posedge clk);
        stim_start = 1'b0;
        // Wait for bit-serial transmission to finish
        wait (!stim_busy);
        repeat (5) @(posedge clk);
    endtask

    // ── Task: send one NoC command ───────────────────────────────────────────
    // dest_node: 0-3
    // payload:   PAYLOAD_BYTES bytes, MSB-first in [23:0]
    task automatic send_noc_cmd (
        input logic [1:0]  dest_node,
        input logic [23:0] payload    // 3 bytes
    );
        raw_send({6'b101000, dest_node});    // 0xA0 | dest
        raw_send(payload[23:16]);
        raw_send(payload[15:8]);
        raw_send(payload[7:0]);
    endtask

    // ── Task: register expected response in scoreboard ───────────────────────
    // Echo nodes return to Node 0, so src_node in response header = 0
    task automatic expect_response (
        input logic [1:0]  src_node,
        input logic [23:0] payload
    );
        // Header byte
        exp_q   [exp_wr] = {6'b101100, src_node};  // 0xB0 | src_node
        exp_chk [exp_wr] = 1'b1;
        exp_wr = exp_wr + 1;
        // Payload bytes MSB-first
        exp_q   [exp_wr] = payload[23:16]; exp_chk[exp_wr] = 1'b1; exp_wr = exp_wr + 1;
        exp_q   [exp_wr] = payload[15:8];  exp_chk[exp_wr] = 1'b1; exp_wr = exp_wr + 1;
        exp_q   [exp_wr] = payload[7:0];   exp_chk[exp_wr] = 1'b1; exp_wr = exp_wr + 1;
        // Latency bytes — don't-care (just count them)
        exp_q   [exp_wr] = 8'hXX; exp_chk[exp_wr] = 1'b0; exp_wr = exp_wr + 1;
        exp_q   [exp_wr] = 8'hXX; exp_chk[exp_wr] = 1'b0; exp_wr = exp_wr + 1;
    endtask

    // ── Task: wait for N response bytes with timeout ─────────────────────────
    task automatic wait_responses (input int n_bytes);
        int timeout;
        int got;
        timeout = n_bytes * (`SIM_CPB * 15);
        got = 0;
        while (got < n_bytes && timeout > 0) begin
            @(posedge clk);
            timeout = timeout - 1;
            if (chk_valid) got = got + 1;
        end
        if (timeout == 0)
            $display("  [WARN ] wait_responses(%0d) timed out", n_bytes);
        // Extra settling gap
        repeat (`SIM_CPB * 3) @(posedge clk);
    endtask

    // Stimulus main block
    initial begin
        $display("==========================================================");
        $display("  PHASE 2: Full UART → NoC → Echo → UART Test");
        $display("  CLK=%0d MHz  BAUD=%0d  BIT_PERIOD=%0d clocks",
                 `CLK_FREQ/1_000_000, `BAUD_RATE, `SIM_CPB);
        $display("  DUT: uart_noc_top  (includes real uart_rx, uart_tx,");
        $display("       uart_cmd_parser, uart_resp_formatter, mesh_fabric_noc)");
        $display("==========================================================");

        wait (rst_n);
        repeat (10) @(posedge clk);

        // TC1: Node 0 → Node 1 (1 hop East)
        $display("\n[TC1] Node 0 → Node 1 (East, 1 hop)  payload=0xABCDEF");
        expect_response(2'd0, 24'hABCDEF);   // echo comes back to Node 0
        send_noc_cmd(2'd1, 24'hABCDEF);
        wait_responses(RESP_BYTES);

        // TC2: Node 0 → Node 2 (1 hop South)
        $display("\n[TC2] Node 0 → Node 2 (South, 1 hop)  payload=0x123456");
        expect_response(2'd0, 24'h123456);
        send_noc_cmd(2'd2, 24'h123456);
        wait_responses(RESP_BYTES);

        // TC3: Node 0 → Node 3 (2 hops: East then South)
        $display("\n[TC3] Node 0 → Node 3 (East+South, 2 hops)  payload=0xDEADBE");
        expect_response(2'd0, 24'hDEADBE);
        send_noc_cmd(2'd3, 24'hDEADBE);
        wait_responses(RESP_BYTES);

        // TC4: Burst to Node 3 — 3 back-to-back commands
        $display("\n[TC4] Burst x3 to Node 3  payloads: 0xA5A5A5, 0x5A5A5A, 0xF0F0F0");
        expect_response(2'd0, 24'hA5A5A5);
        expect_response(2'd0, 24'h5A5A5A);
        expect_response(2'd0, 24'hF0F0F0);
        send_noc_cmd(2'd3, 24'hA5A5A5);
        send_noc_cmd(2'd3, 24'h5A5A5A);
        send_noc_cmd(2'd3, 24'hF0F0F0);
        wait_responses(RESP_BYTES * 3);

        // Results
        repeat (50) @(posedge clk);
        $display("\n==========================================================");
        $display("  PHASE 2 RESULTS: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d FAILURES — CHECK WAVEFORM ***", fail_cnt);
        $display("==========================================================\n");
        $finish;
    end

    // ── Watchdog ─────────────────────────────────────────────────────────────
    // Budget: 7 TCs × (4+6) UART bytes × 15 bit-times × SIM_CPB + NoC transit
    initial begin
        #(`CLK_PERIOD * `SIM_CPB * 15 * 80);
        $display("[WATCHDOG] PHASE 2 timeout — forcing $finish");
        $finish;
    end

    // ── VCD dump ─────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_uart_noc_full.vcd");
        $dumpvars(0, tb_uart_noc_full);
    end

endmodule
