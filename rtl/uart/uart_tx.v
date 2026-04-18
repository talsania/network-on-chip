// uart_tx.v
//   UART Transmitter 
//   - Serializes an 8-bit parallel data byte into a standard UART bitstream.
//   - Protocol: 8-N-1 (1 Start bit, 8 Data bits, No Parity, 1 Stop bit).
//   - Transmission order: LSB (Least Significant Bit) first.
//   - Configurable Clock Frequency and Baud Rate via parameters.

`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input        clk,
    input        rst_n,
    input  [7:0] tx_data,
    input        tx_valid,
    output       tx_ready,
    output reg   tx
);
    localparam BIT_TICK = CLK_FREQ / BAUD_RATE;
    
    reg [$clog2(BIT_TICK)-1:0] clk_cnt;
    reg [3:0] bit_cnt;
    reg [9:0] shift_reg;
    reg       state; 

    assign tx_ready = !state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= 0;
            tx      <= 1;
            clk_cnt <= 0;
            bit_cnt <= 0;
        end else begin
            case (state)
                0: begin
                    tx <= 1; // Line idles high
                    if (tx_valid) begin
                        // Frame: {Stop bit (1), Data, Start bit (0)}
                        shift_reg <= {1'b1, tx_data, 1'b0}; 
                        state     <= 1;
                        clk_cnt   <= BIT_TICK - 1;
                        bit_cnt   <= 0;
                    end
                end
                1: begin
                    tx <= shift_reg[0]; // Send the lowest bit
                    if (clk_cnt == 0) begin
                        clk_cnt <= BIT_TICK - 1;
                        if (bit_cnt == 9) begin
                            state <= 0; // Finished all 10 bits
                        end else begin
                            shift_reg <= {1'b1, shift_reg[9:1]}; // Shift right
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