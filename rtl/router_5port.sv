// router_5port.sv
//   Top-level wrapper for a 5-port NoC router node designed for a 2D mesh topology.
//   It integrates 5 input FIFOs for buffering, 5 XY routing units for coordinate-based 
//   path calculation, a 5x5 round-robin switch allocator for conflict resolution, 
//   and a combinational crossbar switch to physically route flits from inputs to 
//   outputs based on arbiter grants. 
//   Port indices: 0=Local, 1=North, 2=South, 3=East, 4=West

`timescale 1ns / 1ps

module router_5port #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1,
    parameter FIFO_DEPTH  = 8
)(
    input  logic clk,
    input  logic rst_n,
    
    input  logic [COORD_WIDTH-1:0] router_x,
    input  logic [COORD_WIDTH-1:0] router_y,

    input  logic [4:0] [DATA_WIDTH-1:0] rx_flit_arr,
    input  logic [4:0]                  rx_valid_arr,
    output logic [4:0]                  rx_ready_arr,

    output logic [4:0] [DATA_WIDTH-1:0] tx_flit_arr,
    output logic [4:0]                  tx_valid_arr,
    input  logic [4:0]                  tx_ready_arr
);

    logic [4:0][DATA_WIDTH-1:0] fifo_data_out;
    logic [4:0]                 fifo_empty;
    logic [4:0]                 fifo_rd_en;
    
    logic [4:0][4:0]            raw_xy_reqs;
    logic [4:0][4:0]            masked_reqs;
    logic [4:0][4:0]            crossbar_grants;

    //  1: Input Buffers & Route Calculation
    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : gen_input_s
            
            logic fifo_full;
            
            input_buffer_fifo #(
                .DATA_WIDTH(DATA_WIDTH), 
                .DEPTH(FIFO_DEPTH)
            ) in_fifo (
                .clk     (clk),
                .rst_n   (rst_n),
                .wr_en   (rx_valid_arr[i]),
                .data_in (rx_flit_arr[i]),
                .full    (fifo_full),
                .rd_en   (fifo_rd_en[i]),
                .data_out(fifo_data_out[i]),
                .empty   (fifo_empty[i]) 
            );

            assign rx_ready_arr[i] = ~fifo_full;
            
            logic [COORD_WIDTH-1:0] dest_x;
            logic [COORD_WIDTH-1:0] dest_y;
            
            assign dest_x = fifo_data_out[i][DATA_WIDTH-1 : DATA_WIDTH-COORD_WIDTH];
            assign dest_y = fifo_data_out[i][DATA_WIDTH-COORD_WIDTH-1 : DATA_WIDTH-(2*COORD_WIDTH)];

            xy_router #(.COORD_WIDTH(COORD_WIDTH)) xy_inst (
                .curr_x      (router_x),
                .curr_y      (router_y),
                .dest_x      (dest_x),
                .dest_y      (dest_y),
                .out_port_req(raw_xy_reqs[i])
            );

            assign masked_reqs[i] = fifo_empty[i] ? 5'b00000 : raw_xy_reqs[i];

        end
    endgenerate

    //  2: Switch Allocation (Arbitration)
    switch_allocator allocator_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .req_in   (masked_reqs),
        .tx_flit_arr  (tx_flit_arr),   
        .tx_valid_arr (tx_valid_arr),  
        .tx_ready_arr (tx_ready_arr),  
        .grant_out(crossbar_grants)
    );

    //  3: Data Traversal (Crossbar)
    crossbar_switch #(
        .DATA_WIDTH(DATA_WIDTH)
    ) crossbar_inst (
        .fifo_data_in   (fifo_data_out),
        .arbiter_sel    (crossbar_grants),
        .router_data_out(tx_flit_arr)
    );

    //  4: Output Flow Control & FIFO POP Logic
    genvar out_port, in_port;

    generate
        for (out_port = 0; out_port < 5; out_port = out_port + 1) begin: gen_tx_valid   
            assign tx_valid_arr[out_port] = (crossbar_grants[out_port] != 5'b0) && 
                                            |(crossbar_grants[out_port] & ~fifo_empty);
        end

        for (in_port = 0; in_port < 5; in_port = in_port + 1) begin: gen_fifo_rd
            assign fifo_rd_en[in_port] = 
                (crossbar_grants[0][in_port] & tx_ready_arr[0]) |
                (crossbar_grants[1][in_port] & tx_ready_arr[1]) |
                (crossbar_grants[2][in_port] & tx_ready_arr[2]) |
                (crossbar_grants[3][in_port] & tx_ready_arr[3]) |
                (crossbar_grants[4][in_port] & tx_ready_arr[4]); 
        end
    endgenerate
   
endmodule
