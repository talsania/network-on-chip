// uart_rx.sv
// 8N1 UART receiver with mid-bit sampling.
// Vivado 2025 compatible SystemVerilog.
//
// Interface (matches uart_noc_top.sv instantiation):
//   .clk       clock
//   .rst_n     active-low reset
//   .rx        serial input line  (idle-high)
//   .rx_data   [7:0] received byte (valid for one cycle when rx_valid=1)
//   .rx_valid  pulses high for exactly one clock when a byte is received

`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_valid
);

    localparam integer BIT_PERIOD  = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_PERIOD = BIT_PERIOD / 2;
    localparam integer CNT_W       = $clog2(BIT_PERIOD + 1);

    typedef enum logic [1:0] {
        IDLE  = 2'd0,
        START = 2'd1,
        DATA  = 2'd2,
        STOP  = 2'd3
    } state_t;

    state_t            state;
    logic [CNT_W-1:0]  baud_cnt;
    logic [2:0]        bit_idx;
    logic [7:0]        shift_reg;

    // Double-flop synchroniser for rx input (metastability protection)
    logic rx_s0, rx_s1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_s0 <= 1'b1; rx_s1 <= 1'b1; end
        else        begin rx_s0 <= rx;    rx_s1 <= rx_s0; end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            baud_cnt  <= '0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;  // default: one-cycle pulse

            case (state)

                IDLE: begin
                    if (!rx_s1) begin  // falling edge = start bit
                        baud_cnt <= '0;
                        state    <= START;
                    end
                end

                // Wait half a bit-period to sample in the middle of bit 0
                START: begin
                    if (baud_cnt == CNT_W'(HALF_PERIOD - 1)) begin
                        baud_cnt <= '0;
                        bit_idx  <= 3'd0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_cnt == CNT_W'(BIT_PERIOD - 1)) begin
                        baud_cnt  <= '0;
                        shift_reg <= {rx_s1, shift_reg[7:1]};  // LSB first
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_cnt == CNT_W'(BIT_PERIOD - 1)) begin
                        // Only accept if stop bit is high (framing check)
                        if (rx_s1) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end
                        baud_cnt <= '0;
                        state    <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
