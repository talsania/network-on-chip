// uart_rx.v
//   UART Receiver  
//   - Deserializes an incoming standard UART bitstream into an 8-bit parallel byte.
//   - Protocol: 8-N-1 (1 Start bit, 8 Data bits, No Parity, 1 Stop bit).
//   - Reception order: LSB (Least Significant Bit) first.
//   - Configurable Clock Frequency and Baud Rate via parameters.
//   - Timing: Uses 2-stage synchronizer and a 0.5x bit-period offset upon detecting the 
//             Start bit to ensure all subsequent data bits are sampled perfectly, 
//             preventing framing errors.

`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input            clk,
    input            rst_n,
    input            rx,
    output reg [7:0] rx_data,
    output reg       rx_valid
);
    localparam BIT_TICK = CLK_FREQ / BAUD_RATE;

    // 2-Stage Synchronizer
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end
 
    // RX State Machine           
    reg [$clog2(BIT_TICK * 2)-1:0] clk_cnt;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    
    localparam IDLE = 2'b00, START_WAIT = 2'b01, RX_BITS = 2'b10;
    reg [1:0] state; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            rx_valid <= 0;
            clk_cnt  <= 0;
            bit_cnt  <= 0;
            rx_data  <= 0;
        end else begin
            rx_valid <= 0;
            case (state)
                IDLE: begin 
                    if (!rx_sync2) begin // Start bit detected
                        state   <= START_WAIT;
                        // Wait 0.5 bit periods to reach the middle of D0
                        clk_cnt <= (BIT_TICK / 2) - 1; 
                    end
                end
                
                START_WAIT: begin
                    if (clk_cnt == 0) begin
                        if (!rx_sync2) begin 
                            state   <= RX_BITS;
                            clk_cnt <= BIT_TICK - 1;
                            bit_cnt <= 0;
                        end else begin
                            state   <= IDLE; 
                        end
                    end else begin
                        clk_cnt <= clk_cnt - 1;
                    end
                end
                                                         
                RX_BITS: begin 
                    if (clk_cnt == 0) begin
                        if (bit_cnt == 8) begin
                            state    <= IDLE;
                            rx_data  <= shift_reg;
                            rx_valid <= 1; 
                        end else begin
                            clk_cnt   <= BIT_TICK - 1;
                            shift_reg <= {rx_sync2, shift_reg[7:1]};
                            bit_cnt   <= bit_cnt + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt - 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule