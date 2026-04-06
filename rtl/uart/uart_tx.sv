// uart_tx.sv
// 8N1 UART transmitter.
// Vivado 2025 compatible SystemVerilog.
//
// Interface (matches uart_noc_top.sv instantiation):
//   .clk      clock
//   .rst_n    active-low synchronous reset
//   .tx_data  [7:0] byte to transmit
//   .tx_valid byte presented (must hold until tx_ready)
//   .tx_ready 1 when idle and accepting new byte  (registered output)
//   .tx       serial output line (idle-high)
//
// tx_ready is de-asserted one cycle after tx_valid is sampled, and
// re-asserted one cycle after the stop bit completes.

`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    output logic       tx         // serial line
);

    // Baud-rate divider: counts from 0 to BIT_PERIOD-1
    localparam integer BIT_PERIOD = CLK_FREQ / BAUD_RATE;
    localparam integer CNT_W      = $clog2(BIT_PERIOD + 1);

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
    logic              baud_tick;

    assign baud_tick = (baud_cnt == CNT_W'(BIT_PERIOD - 1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            baud_cnt  <= '0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            tx        <= 1'b1;
            tx_ready  <= 1'b1;
        end else begin
            case (state)

                IDLE: begin
                    tx       <= 1'b1;
                    tx_ready <= 1'b1;
                    baud_cnt <= '0;
                    if (tx_valid) begin
                        shift_reg <= tx_data;
                        tx_ready  <= 1'b0;
                        tx        <= 1'b0;   // start bit
                        state     <= START;
                    end
                end

                START: begin
                    if (baud_tick) begin
                        baud_cnt <= '0;
                        tx       <= shift_reg[0];
                        bit_idx  <= 3'd0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_tick) begin
                        baud_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;   // stop bit
                            state <= STOP;
                        end else begin
                            bit_idx   <= bit_idx + 1'b1;
                            shift_reg <= {1'b0, shift_reg[7:1]};
                            tx        <= shift_reg[1];
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_tick) begin
                        baud_cnt <= '0;
                        tx_ready <= 1'b1;
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
