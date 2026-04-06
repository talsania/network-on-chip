// crossbar_switch.sv
//   Purely combinational 5x5 multiplexer matrix. Routes flit data from any of
//   the 5 input FIFOs (Local, North, South, East, West) to any of the 5 output
//   ports. Each output port has a dedicated 5-to-1 mux whose select line is the
//   one-hot grant vector produced by that port's Round-Robin Arbiter. Up to 5
//   simultaneous non-conflicting transfers are supported per cycle. No registers;
//   output is valid within one combinational delay of the arbiter grant settling.

`timescale 1ns / 1ps

module crossbar_switch #(
    parameter DATA_WIDTH = 34
)(
    input  logic [4:0][DATA_WIDTH-1:0] fifo_data_in,
    input  logic [4:0][4:0]            arbiter_sel,
    output logic [4:0][DATA_WIDTH-1:0] router_data_out
);

    genvar i;

    generate
        for (i = 0; i < 5; i = i + 1) begin: switch_muxes
            
            assign router_data_out[i] = 
                ({DATA_WIDTH{arbiter_sel[i][0]}} & fifo_data_in[0]) |
                ({DATA_WIDTH{arbiter_sel[i][1]}} & fifo_data_in[1]) |
                ({DATA_WIDTH{arbiter_sel[i][2]}} & fifo_data_in[2]) |
                ({DATA_WIDTH{arbiter_sel[i][3]}} & fifo_data_in[3]) |
                ({DATA_WIDTH{arbiter_sel[i][4]}} & fifo_data_in[4]);
                
        end
    endgenerate

endmodule
