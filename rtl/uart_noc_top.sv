// uart_noc_top.sv
// Top-level: UART <-> 2x2 Mesh NoC test harness.
//
// Node mapping (matches mesh_fabric_noc):
//   Node 0 = (x=0, y=0)  -- UART gateway
//   Node 1 = (x=1, y=0)  -- echo back to Node 0
//   Node 2 = (x=0, y=1)  -- echo back to Node 0
//   Node 3 = (x=1, y=1)  -- echo back to Node 0
//
// User types:  SEND 3 HI<CR>
// Response  :  [Node 3] Received: HI | Latency: 42 cycles<CR><LF>
//
// Fixes vs previous version:
//   - Removed illegal parameter bit-selects  PAYLOAD_BYTES[$clog2...:0]
//   - Used localparam CNT_W to drive payload_len widths uniformly

`timescale 1ns / 1ps

module uart_noc_top #(
    parameter integer CLK_FREQ    = 100_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer DATA_WIDTH  = 34,
    parameter integer COORD_WIDTH = 1,
    parameter integer FIFO_DEPTH  = 8,
    parameter integer TS_WIDTH    = 16,
    // Derived -- keep in sync with mesh_fabric_noc
    parameter integer PAYLOAD_W     = DATA_WIDTH - (2*COORD_WIDTH) - 2, // 30 b
    parameter integer CORE_DATA_W   = PAYLOAD_W * 2,                     // 60 b
    parameter integer PAYLOAD_BYTES = PAYLOAD_W / 8                      // 3 B
)(
    input  logic clk,
    input  logic rst_n,
    input  logic uart_rxd,
    output logic uart_txd
);

    // Payload-length counter width -- localparam avoids bit-selects on parameters
    localparam integer CNT_W = $clog2(PAYLOAD_BYTES + 1);

    // 1. UART RX
    logic [7:0] rx_byte;
    logic       rx_byte_valid;

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (uart_rxd),
        .rx_data  (rx_byte),
        .rx_valid (rx_byte_valid)
    );

    // 2. Command parser
    logic                  cmd_valid;
    logic [1:0]            cmd_dest_node;
    logic [PAYLOAD_BYTES*8-1:0] cmd_payload;
    logic [CNT_W-1:0]      cmd_payload_len;

    uart_cmd_parser #(
        .PAYLOAD_BYTES (PAYLOAD_BYTES)
    ) u_parser (
        .clk             (clk),
        .rst_n           (rst_n),
        .rx_data         (rx_byte),
        .rx_valid        (rx_byte_valid),
        .cmd_valid       (cmd_valid),
        .cmd_dest_node   (cmd_dest_node),
        .cmd_payload     (cmd_payload),
        .cmd_payload_len (cmd_payload_len)
    );

    // 3. NoC fabric wires
    logic [3:0][CORE_DATA_W-1:0]  core_tx_data;
    logic [3:0][COORD_WIDTH-1:0]  core_tx_dest_x;
    logic [3:0][COORD_WIDTH-1:0]  core_tx_dest_y;
    logic [3:0]                   core_tx_valid;
    logic [3:0]                   core_tx_ready;

    logic [3:0][CORE_DATA_W-1:0]  core_rx_data;
    logic [3:0]                   core_rx_valid;
    logic [3:0]                   core_rx_ready;

    logic [3:0][TS_WIDTH-1:0]     latency_cycles_out;
    logic [3:0]                   latency_valid;

    // 4. mesh_fabric_noc
    mesh_fabric_noc #(
        .DATA_WIDTH  (DATA_WIDTH),
        .COORD_WIDTH (COORD_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .TS_WIDTH    (TS_WIDTH)
    ) u_noc (
        .clk                (clk),
        .rst_n              (rst_n),
        .core_tx_data       (core_tx_data),
        .core_tx_dest_x     (core_tx_dest_x),
        .core_tx_dest_y     (core_tx_dest_y),
        .core_tx_valid      (core_tx_valid),
        .core_tx_ready      (core_tx_ready),
        .core_rx_data       (core_rx_data),
        .core_rx_valid      (core_rx_valid),
        .core_rx_ready      (core_rx_ready),
        .latency_cycles_out (latency_cycles_out),
        .latency_valid      (latency_valid)
    );

    // 5. Node 0 TX controller
    //    dest_node bit layout:  bit1=Y, bit0=X  (matches mesh coordinates)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_tx_data[0]   <= '0;
            core_tx_dest_x[0] <= '0;
            core_tx_dest_y[0] <= '0;
            core_tx_valid[0]  <= 1'b0;
        end else begin
            if (cmd_valid && core_tx_ready[0]) begin
                core_tx_data[0]   <= {{(CORE_DATA_W - PAYLOAD_BYTES*8){1'b0}}, cmd_payload};
                core_tx_dest_x[0] <= cmd_dest_node[0:0];   // bit 0 = X
                core_tx_dest_y[0] <= cmd_dest_node[1:1];   // bit 1 = Y
                core_tx_valid[0]  <= 1'b1;
            end else if (core_tx_ready[0]) begin
                core_tx_valid[0]  <= 1'b0;
            end
        end
    end

    // 6. Nodes 1-3: echo controllers
    genvar n;
    generate
        for (n = 1; n < 4; n = n + 1) begin : gen_echo
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    core_tx_data[n]   <= '0;
                    core_tx_dest_x[n] <= '0;
                    core_tx_dest_y[n] <= '0;
                    core_tx_valid[n]  <= 1'b0;
                    core_rx_ready[n]  <= 1'b1;
                end else begin
                    core_rx_ready[n] <= 1'b1;
                    if (core_rx_valid[n] && core_rx_ready[n] && core_tx_ready[n]) begin
                        core_tx_data[n]   <= core_rx_data[n];
                        core_tx_dest_x[n] <= {COORD_WIDTH{1'b0}};
                        core_tx_dest_y[n] <= {COORD_WIDTH{1'b0}};
                        core_tx_valid[n]  <= 1'b1;
                    end else if (core_tx_ready[n]) begin
                        core_tx_valid[n]  <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    assign core_rx_ready[0] = 1'b1;

    // 7. RX arbiter
    logic                   fmt_valid;
    logic [1:0]             fmt_src_node;
    logic [PAYLOAD_BYTES*8-1:0] fmt_payload;
    logic [CNT_W-1:0]       fmt_payload_len;
    logic [TS_WIDTH-1:0]    fmt_latency;
    logic                   fmt_busy;

    // Constant payload length signal (all bytes valid from the formatter's view)
    localparam logic [CNT_W-1:0] FULL_LEN = CNT_W'(PAYLOAD_BYTES);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fmt_valid       <= 1'b0;
            fmt_src_node    <= 2'b00;
            fmt_payload     <= '0;
            fmt_payload_len <= '0;
            fmt_latency     <= '0;
        end else begin
            fmt_valid <= 1'b0;

            if (!fmt_busy) begin
                if (core_rx_valid[0]) begin
                    fmt_valid       <= 1'b1;
                    fmt_src_node    <= 2'd0;
                    fmt_payload     <= core_rx_data[0][PAYLOAD_BYTES*8-1:0];
                    fmt_payload_len <= FULL_LEN;
                    fmt_latency     <= latency_valid[0] ? latency_cycles_out[0] : '0;
                end else if (core_rx_valid[1]) begin
                    fmt_valid       <= 1'b1;
                    fmt_src_node    <= 2'd1;
                    fmt_payload     <= core_rx_data[1][PAYLOAD_BYTES*8-1:0];
                    fmt_payload_len <= FULL_LEN;
                    fmt_latency     <= latency_valid[1] ? latency_cycles_out[1] : '0;
                end else if (core_rx_valid[2]) begin
                    fmt_valid       <= 1'b1;
                    fmt_src_node    <= 2'd2;
                    fmt_payload     <= core_rx_data[2][PAYLOAD_BYTES*8-1:0];
                    fmt_payload_len <= FULL_LEN;
                    fmt_latency     <= latency_valid[2] ? latency_cycles_out[2] : '0;
                end else if (core_rx_valid[3]) begin
                    fmt_valid       <= 1'b1;
                    fmt_src_node    <= 2'd3;
                    fmt_payload     <= core_rx_data[3][PAYLOAD_BYTES*8-1:0];
                    fmt_payload_len <= FULL_LEN;
                    fmt_latency     <= latency_valid[3] ? latency_cycles_out[3] : '0;
                end
            end
        end
    end

    // 8. UART response formatter
    logic [7:0] fmt_tx_data;
    logic       fmt_tx_valid;
    logic       fmt_tx_ready;

    uart_resp_formatter #(
        .PAYLOAD_BYTES (PAYLOAD_BYTES),
        .TS_WIDTH      (TS_WIDTH)
    ) u_formatter (
        .clk             (clk),
        .rst_n           (rst_n),
        .fmt_valid       (fmt_valid),
        .fmt_src_node    (fmt_src_node),
        .fmt_payload     (fmt_payload),
        .fmt_payload_len (fmt_payload_len),
        .fmt_latency     (fmt_latency),
        .tx_data         (fmt_tx_data),
        .tx_valid        (fmt_tx_valid),
        .tx_ready        (fmt_tx_ready),
        .fmt_busy        (fmt_busy)
    );

    // 9. UART TX
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (fmt_tx_data),
        .tx_valid (fmt_tx_valid),
        .tx_ready (fmt_tx_ready),
        .tx       (uart_txd)
    );

endmodule
