// uart_resp_formatter.sv
//   Dual-Protocol UART Response Formatter
// 
// Functionality:
//   - Acts as the bridge between the NoC ejection port and the UART TX module.
//   - Takes wide, parallel NoC flit payloads (with metadata) and serializes 
//     them into byte-by-byte streams for UART transmission.
//   - Automatically formats the output into one of two protocols based on the 
//     `is_binary` flag attached to the incoming packet:
//
//   1. ASCII Mode (is_binary = 0):
//      - Generates a 30-byte human-readable string.
//      - Format: "[Node X] <5-Byte Payload> L: <4-Digit Hex Latency> cycles\n"
//      - Uses an internal Hex-to-ASCII converter to make latency human-readable.
//
//   2. Binary Mode (is_binary = 1):
//      - Generates a fast, machine-parsable 8-byte hex packet.
//      - Byte 0    : Header (0xB0) logically OR'd with the Source Node ID (0-3).
//      - Bytes 1-5 : The raw 5-byte payload.
//      - Bytes 6-7 : The 16-bit packet traversal latency (Big-Endian).
//
// Interface Protocol:
//   - Utilizes a `fmt_busy` flag to backpressure the NoC if a packet arrives 
//     while the UART is still transmitting the previous one.
//   - Honors `tx_ready` from the UART TX module to pause serialization if 
//     the physical line cannot keep up.
// =============================================================================

`timescale 1ns / 1ps

module uart_resp_formatter #(
    parameter integer PAYLOAD_BYTES = 5,
    parameter integer TS_WIDTH      = 16
)(
    input  logic                               clk,
    input  logic                               rst_n,

    input  logic                               fmt_valid,
    input  logic                               is_binary,
    input  logic [1:0]                         fmt_src_node,
    input  logic [(PAYLOAD_BYTES*8)-1:0]       fmt_payload,
    input  logic [2:0]                         fmt_payload_len,
    input  logic [TS_WIDTH-1:0]                fmt_latency,

    output logic [7:0]                         tx_data,
    output logic                               tx_valid,
    input  logic                               tx_ready,
    
    output logic                               fmt_busy
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SEND_BIN,
        ST_SEND_ASCII
    } state_t;

    state_t state;
    
    // 5 bits is enough to count up to 31 (we need to reach 29 for ASCII)
    logic [4:0] byte_idx; 
    
    // Binary: [0xB0|ID] + [5 Payload] + [2 Latency] = 8 Bytes
    logic [63:0] bin_buffer; 
    
    // ASCII Buffer: expanded to 30 bytes (240 bits)
    logic [239:0] ascii_buffer; 

    // Helper: Hex to ASCII (for latency printing)
    function [7:0] hex2ascii(input [3:0] hex);
        hex2ascii = (hex <= 9) ? (8'h30 + hex) : (8'h37 + hex);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            fmt_busy <= 1'b0;
            tx_valid <= 1'b0;
            tx_data  <= '0;
            byte_idx <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx_valid <= 1'b0;
                    if (fmt_valid && !fmt_busy) begin
                        fmt_busy <= 1'b1;
                        byte_idx <= '0;
                        
                        if (is_binary) begin
                            bin_buffer <= { {4'hB, 2'b00, fmt_src_node}, fmt_payload, fmt_latency };
                            state      <= ST_SEND_BIN;
                        end else begin
                            // Exactly 30 bytes (240 bits)
                            ascii_buffer <= { 
                                8'h5B, 8'h4E, 8'h6F, 8'h64, 8'h65, 8'h20, // "[Node "
                                8'h30 + {6'd0, fmt_src_node}, 8'h5D, 8'h20, // "X] "
                                fmt_payload, // 5 Bytes
                                8'h20, 8'h4C, 8'h3A, 8'h20, // " L: "
                                hex2ascii(fmt_latency[15:12]), hex2ascii(fmt_latency[11:8]),
                                hex2ascii(fmt_latency[7:4]), hex2ascii(fmt_latency[3:0]), // 4 Bytes (Hex)
                                8'h20, 8'h63, 8'h79, 8'h63, 8'h6C, 8'h65, 8'h73, 8'h0A // " cycles\n"
                            };
                            state <= ST_SEND_ASCII;
                        end
                    end
                end

                ST_SEND_BIN: begin
                    if (tx_ready && !tx_valid) begin
                        tx_data  <= bin_buffer[63:56]; 
                        bin_buffer <= {bin_buffer[55:0], 8'h00}; 
                        tx_valid <= 1'b1;
                    end else if (tx_ready && tx_valid) begin
                        // 8 Bytes total (index 0 to 7)
                        if (byte_idx == 7) begin
                            tx_valid <= 1'b0;
                            fmt_busy <= 1'b0;
                            state    <= ST_IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1;
                            tx_data  <= bin_buffer[63:56];
                            bin_buffer <= {bin_buffer[55:0], 8'h00};
                        end
                    end
                end

                ST_SEND_ASCII: begin
                    if (tx_ready && !tx_valid) begin
                        tx_data  <= ascii_buffer[239:232];
                        ascii_buffer <= {ascii_buffer[231:0], 8'h00};
                        tx_valid <= 1'b1;
                    end else if (tx_ready && tx_valid) begin
                        // 30 Bytes total (index 0 to 29)
                        if (byte_idx == 29) begin 
                            tx_valid <= 1'b0;
                            fmt_busy <= 1'b0;
                            state    <= ST_IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1;
                            tx_data  <= ascii_buffer[239:232];
                            ascii_buffer <= {ascii_buffer[231:0], 8'h00};
                        end
                    end
                end
            endcase
        end
    end
endmodule