`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    output logic       tx
);
    localparam BIT_TICK = CLK_FREQ / BAUD_RATE;
    
    logic [$clog2(BIT_TICK)-1:0] clk_cnt;
    logic [3:0] bit_cnt;
    logic [9:0] shift_reg;
    logic       state; 

    assign tx_ready = !state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= 0;
            tx      <= 1;
            clk_cnt <= 0;
            bit_cnt <= 0;
        end else begin
            case (state)
                0: begin
                    tx <= 1;
                    if (tx_valid) begin
                        shift_reg <= {1'b1, tx_data, 1'b0}; // Stop, Data, Start
                        state     <= 1;
                        clk_cnt   <= BIT_TICK - 1;
                        bit_cnt   <= 0;
                    end
                end
                1: begin
                    tx <= shift_reg[0];
                    if (clk_cnt == 0) begin
                        clk_cnt <= BIT_TICK - 1;
                        if (bit_cnt == 9) begin
                            state <= 0;
                        end else begin
                            shift_reg <= {1'b1, shift_reg[9:1]};
                            bit_cnt   <= bit_cnt + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt - 1;
                    end
                end
            endcase
        end
    end
endmodule