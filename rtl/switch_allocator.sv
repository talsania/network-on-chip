// switch_allocator.sv
//   Resolves routing conflicts using 5 independent Round-Robin arbiters.
//   Takes in 5 one-hot request vectors (from the 5 input ports' XY routers)
//   and transposes them to generate 5 one-hot grant vectors (for the crossbar).

`timescale 1ns / 1ps

// Sub-Module: 5-Bit Round-Robin Arbiter
module round_robin_arbiter #(
    parameter PORTS = 5
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             release_lock,
    input  logic [PORTS-1:0] req,
    output logic [PORTS-1:0] grant
);

    logic [PORTS-1:0] mask_reg;
    logic [PORTS-1:0] masked_req;
    logic [PORTS-1:0] masked_grant;
    logic [PORTS-1:0] unmasked_grant;
    logic [PORTS-1:0] next_grant;
    logic [PORTS-1:0] locked_grant;
    logic             is_locked;

    // Mask off requests from ports that have recently been granted
    assign masked_req = req & mask_reg;

    // Simple Fixed-Priority Arbiters
    // (The equation "req & ~(req - 1)" keeps the lowest-order '1' bit active)
    assign masked_grant   = masked_req & ~(masked_req - 1);
    assign unmasked_grant = req & ~(req - 1);

    // Grant request based on masked_grant 
    // If the mask blocked everything (everyone currently requesting has already had a turn), it ignores the mask and wraps around, finding the lowest-order bit in the raw 'req' instead
    assign next_grant = (masked_req == 0) ? unmasked_grant : masked_grant;

    // Output the locked grant if a packet is currently in flight
    assign grant = is_locked ? locked_grant : next_grant;

    // Update the rotating priority mask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_reg     <= {PORTS{1'b1}}; // Reset: All ports have equal priority
            locked_grant <= 0;
            is_locked    <= 0;
        end else begin
            if (is_locked) begin

                // Unlock when the TAIL flit successfully transfers
                if (release_lock) begin
                    is_locked    <= 0;
                    locked_grant <= 0;

                    // Rotate priority mask as round robin suggests
                    mask_reg     <= ~(locked_grant | (locked_grant - 1));
                end

            end else begin
                if (next_grant != 0) begin
                    if (release_lock) begin
                        
                        // 1-flit packet transferred instantly, update mask but don't lock
                        mask_reg <= ~(next_grant | (next_grant - 1));
                    
                    end else begin
                    
                        // Lock onto the new priority for the duration of the packet
                        is_locked    <= 1'b1;
                        locked_grant <= next_grant;
                    end
                end
            end
        end
    end

endmodule

// Top-Level Module: Switch Allocator Matrix
module switch_allocator #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1
)(
    input  logic clk,
    input  logic rst_n,
    
    input  logic [4:0][4:0] req_in,
    
    input  logic [4:0][DATA_WIDTH-1:0] tx_flit_arr,
    input  logic [4:0]                 tx_valid_arr,
    input  logic [4:0]                 tx_ready_arr,

    output logic [4:0][4:0] grant_out
);

    localparam FLIT_TYPE_WIDTH = 2;
    localparam logic [FLIT_TYPE_WIDTH-1:0] TYPE_TAIL = 2'b11;

    genvar out_port, in_port;

    generate
        for (out_port = 0; out_port < 5; out_port = out_port + 1) begin : gen_arbiters
            
            logic [4:0] arb_req;
            logic [4:0] arb_grant;
            logic       release_lock;

            // Transpose the request matrix
            for (in_port = 0; in_port < 5; in_port = in_port + 1) begin : gen_transpose
                assign arb_req[in_port] = req_in[in_port][out_port];
            end

            // Detect if a TAIL flit is successfully leaving this output port
            assign release_lock = tx_valid_arr[out_port] && 
                                  tx_ready_arr[out_port] && 
                                  (((tx_flit_arr[out_port] >> (DATA_WIDTH - (2*COORD_WIDTH) - FLIT_TYPE_WIDTH)) & 2'b11) == TYPE_TAIL);

            round_robin_arbiter #(
                .PORTS(5)
            ) arbiter_inst (
                .clk  (clk),
                .rst_n(rst_n),
                .release_lock(release_lock),
                .req  (arb_req),
                .grant(arb_grant)
            );

            assign grant_out[out_port] = arb_grant;
            
        end
    endgenerate

endmodule
