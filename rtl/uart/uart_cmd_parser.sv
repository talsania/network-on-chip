// uart_cmd_parser.sv
//   Dual-Protocol UART Command Parser
//   - Acts as the bridge between the raw UART RX byte stream and the NoC fabric.
//   - Automatically detects and routes two distinct protocols on the fly:
//   1. ASCII Mode:
//      - Trigger: Lowercase 's' (0x73) or uppercase 'S' (0x53).
//      - Node ID: The immediate next byte must be an ASCII digit '0'-'3' (0x30-0x33).
//      - Payload: The subsequent N bytes are captured as the payload.
//      - Output : Asserts cmd_valid with cmd_is_binary = 0.
//   2. Binary Mode:
//      - Trigger: A single hex byte where the upper nibble is 0xA (e.g., 0xA1).
//      - Node ID: Extracted directly from the lower nibble of the trigger byte.
//      - Payload: The subsequent N bytes are captured as the raw binary payload.
//      - Output : Asserts cmd_valid with cmd_is_binary = 1.

`timescale 1ns / 1ps

module uart_cmd_parser #(
    parameter integer PAYLOAD_BYTES = 5
)(
    input  logic                               clk,
    input  logic                               rst_n,

    input  logic [7:0]                         rx_data,
    input  logic                               rx_valid,

    output logic                               cmd_valid,
    output logic                               cmd_is_binary, 
    output logic [1:0]                         cmd_dest_node,
    output logic [(PAYLOAD_BYTES*8)-1:0]       cmd_payload,
    output logic [$clog2(PAYLOAD_BYTES+1)-1:0] cmd_payload_len 
);

    assign cmd_payload_len = PAYLOAD_BYTES;

    localparam IDLE       = 2'b00,
               ASCII_NODE = 2'b01,
               PAYLOAD    = 2'b10;

    logic [1:0] state;
    logic [$clog2(PAYLOAD_BYTES+1)-1:0] byte_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            cmd_valid     <= 0;
            cmd_is_binary <= 0;
            cmd_dest_node <= 0;
            cmd_payload   <= 0;
            byte_cnt      <= 0;
        end else begin
            cmd_valid <= 0; 

            case (state)
                IDLE: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h73 || rx_data == 8'h53) begin
                            cmd_is_binary <= 0;
                            state         <= ASCII_NODE;
                        end else if (rx_data[7:4] == 4'hA) begin
                            cmd_is_binary <= 1'b1;
                            cmd_dest_node <= rx_data[1:0];
                            byte_cnt      <= 0;
                            state         <= PAYLOAD;
                        end
                    end
                end

                ASCII_NODE: begin
                    if (rx_valid) begin
                        if (rx_data >= 8'h30 && rx_data <= 8'h33) begin
                            cmd_dest_node <= rx_data[1:0];
                            byte_cnt      <= 0;
                            state         <= PAYLOAD;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                PAYLOAD: begin
                    if (rx_valid) begin
                        cmd_payload <= {cmd_payload[(PAYLOAD_BYTES-1)*8-1 : 0], rx_data};
                        if (byte_cnt == PAYLOAD_BYTES - 1) begin
                            cmd_valid <= 1'b1;
                            state     <= IDLE;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule