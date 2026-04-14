`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_valid
);
    localparam BIT_TICK = CLK_FREQ / BAUD_RATE;
    
    logic [$clog2(BIT_TICK)-1:0] clk_cnt;
    logic [3:0] bit_cnt;
    logic [7:0] shift_reg;
    logic       state; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= 0;
            rx_valid <= 0;
            clk_cnt  <= 0;
            bit_cnt  <= 0;
        end else begin
            rx_valid <= 0;
            case (state)
                0: begin // IDLE
                    if (!rx) begin // Start bit detected
                        state   <= 1;
                        clk_cnt <= BIT_TICK / 2; // Sample in middle
                    end
                end
                1: begin // RX BITS
                    if (clk_cnt == 0) begin
                        clk_cnt <= BIT_TICK - 1;
                        if (bit_cnt == 8) begin
                            state    <= 0;
                            bit_cnt  <= 0;
                            rx_data  <= shift_reg;
                            rx_valid <= 1; // STOP bit (ignored validity check for simplicity)
                        end else begin
                            shift_reg <= {rx, shift_reg[7:1]};
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