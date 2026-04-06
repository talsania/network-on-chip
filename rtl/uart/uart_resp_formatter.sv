// uart_resp_formatter.sv
// Formats a received NoC payload + metadata into a UART byte stream.
//
// Output byte stream for each received packet:
//   Byte 0:      0xB0 | src_node[1:0]   (response header)
//   Bytes 1..N:  payload bytes MSB-first
//   Byte N+1:    latency high byte
//   Byte N+2:    latency low byte
//
// Interface (matches uart_noc_top.sv):
//   .fmt_valid        pulse: new packet to format
//   .fmt_src_node     [1:0]
//   .fmt_payload      [PAYLOAD_BYTES*8-1:0]
//   .fmt_payload_len  [$clog2(PAYLOAD_BYTES+1)-1:0]
//   .fmt_latency      [TS_WIDTH-1:0]
//   .tx_data          [7:0]  → uart_tx
//   .tx_valid                → uart_tx
//   .tx_ready                ← uart_tx
//   .fmt_busy         held high while serialising (gate new fmt_valid from arbiter)

`timescale 1ns / 1ps

module uart_resp_formatter #(
    parameter integer PAYLOAD_BYTES = 3,
    parameter integer TS_WIDTH      = 16
)(
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       fmt_valid,
    input  logic [1:0]                 fmt_src_node,
    input  logic [PAYLOAD_BYTES*8-1:0] fmt_payload,
    input  logic [$clog2(PAYLOAD_BYTES+1)-1:0] fmt_payload_len,
    input  logic [TS_WIDTH-1:0]        fmt_latency,

    output logic [7:0]                 tx_data,
    output logic                       tx_valid,
    input  logic                       tx_ready,

    output logic                       fmt_busy
);

    // Total bytes to send: 1 header + PAYLOAD_BYTES + 2 latency = PAYLOAD_BYTES+3
    localparam integer TOTAL_BYTES = PAYLOAD_BYTES + 3;
    localparam integer IDX_W       = $clog2(TOTAL_BYTES + 1);

    // Build a flat byte array at capture time: [hdr, p2, p1, p0, lat_hi, lat_lo]
    // Byte index 0 = first to send
    localparam integer FRAME_BYTES = 1 + PAYLOAD_BYTES + 2;  // = TOTAL_BYTES

    logic [7:0]       frame [0:FRAME_BYTES-1];
    logic [IDX_W-1:0] byte_idx;
    logic             sending;

    // fmt_busy: high from capture until last byte is accepted
    assign fmt_busy = sending;

    // tx_valid: high whenever we have a byte to send
    assign tx_valid = sending;
    assign tx_data  = frame[byte_idx];

    integer k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending  <= 1'b0;
            byte_idx <= '0;
            for (k = 0; k < FRAME_BYTES; k = k + 1)
                frame[k] <= 8'd0;
        end else begin
            if (!sending && fmt_valid) begin
                // Capture response frame
                frame[0] <= {6'b101100, fmt_src_node};  // 0xB0 | src_node

                // Payload bytes: MSB-first
                for (k = 0; k < PAYLOAD_BYTES; k = k + 1)
                    frame[1 + k] <= fmt_payload[(PAYLOAD_BYTES - 1 - k)*8 +: 8];

                // Latency: high byte then low byte
                frame[1 + PAYLOAD_BYTES]     <= fmt_latency[TS_WIDTH-1 -: 8];
                frame[1 + PAYLOAD_BYTES + 1] <= fmt_latency[7:0];

                byte_idx <= '0;
                sending  <= 1'b1;
            end else if (sending && tx_ready) begin
                // uart_tx accepted current byte
                if (byte_idx == IDX_W'(FRAME_BYTES - 1)) begin
                    sending <= 1'b0;
                end else begin
                    byte_idx <= byte_idx + 1'b1;
                end
            end
        end
    end

endmodule
