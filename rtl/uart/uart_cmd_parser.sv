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

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_ASCII_NODE,
        ST_PAYLOAD
    } state_t;

    state_t state;
    logic [$clog2(PAYLOAD_BYTES+1)-1:0] byte_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            cmd_valid     <= 1'b0;
            cmd_is_binary <= 1'b0;
            cmd_dest_node <= '0;
            cmd_payload   <= '0;
            byte_cnt      <= '0;
        end else begin
            cmd_valid <= 1'b0; 

            case (state)
                ST_IDLE: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h73 || rx_data == 8'h53) begin
                            cmd_is_binary <= 1'b0;
                            state         <= ST_ASCII_NODE;
                        end else if (rx_data[7:4] == 4'hA) begin
                            cmd_is_binary <= 1'b1;
                            cmd_dest_node <= rx_data[1:0];
                            byte_cnt      <= '0;
                            state         <= ST_PAYLOAD;
                        end
                    end
                end

                ST_ASCII_NODE: begin
                    if (rx_valid) begin
                        if (rx_data >= 8'h30 && rx_data <= 8'h33) begin
                            cmd_dest_node <= rx_data[1:0];
                            byte_cnt      <= '0;
                            state         <= ST_PAYLOAD;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                ST_PAYLOAD: begin
                    if (rx_valid) begin
                        cmd_payload <= {cmd_payload[(PAYLOAD_BYTES-1)*8-1 : 0], rx_data};
                        if (byte_cnt == PAYLOAD_BYTES - 1) begin
                            cmd_valid <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule