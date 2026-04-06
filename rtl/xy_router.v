// xy_router.v
//   Purely combinational XY routing unit. Compares the destination coordinates
//   carried in the Header flit against the current router's static coordinates
//   and asserts a one-hot 5-bit output port request. X dimension is resolved
//   first (route East or West until dest_x == curr_x), then Y (route North or
//   South until dest_y == curr_y). When both match the flit has reached its
//   destination router and the Local port is selected for ejection.
//   Port encoding: Local=5'b00001, North=5'b00010, South=5'b00100,
//                  East=5'b01000, West=5'b10000.

`timescale 1ns / 1ps

module xy_router #(
    parameter COORD_WIDTH = 1
)(
    input  wire [COORD_WIDTH-1:0] curr_x, curr_y, dest_x, dest_y,
    output reg  [4:0]             out_port_req
);

    localparam PORT_LOCAL = 5'b00001,
               PORT_NORTH = 5'b00010,
               PORT_SOUTH = 5'b00100,
               PORT_EAST  = 5'b01000,
               PORT_WEST  = 5'b10000;

    always @(*) begin
        if      (dest_x > curr_x) out_port_req = PORT_EAST;
        else if (dest_x < curr_x) out_port_req = PORT_WEST;
        else if (dest_y > curr_y) out_port_req = PORT_SOUTH;
        else if (dest_y < curr_y) out_port_req = PORT_NORTH;
        else                      out_port_req = PORT_LOCAL;
    end

endmodule
