// top_noc_fabric.sv
//   Top-level wrapper for the N-Core Mesh Network-on-Chip (NoC).
//   Instantiates (MESH_X * MESH_Y) Routers and Network Interfaces
//   and procedurally weaves the cross-coupling wires between adjacent nodes.

// Node Indexing mapping:
//   Node ID = (Y * MESH_X) + X
//   Example for 2x2:
//     Node 0 = (0,0) [Top Left]
//     Node 1 = (1,0) [Top Right]
//     Node 2 = (0,1) [Bottom Left]
//     Node 3 = (1,1) [Bottom Right]

`timescale 1ns / 1ps

module mesh_fabric_noc #(
    parameter MESH_X          = 2,
              MESH_Y          = 2,
              DATA_WIDTH      = 34,
              COORD_WIDTH     = 1,  
              FIFO_DEPTH      = 8,
              TS_WIDTH        = 16,
              FLIT_TYPE_WIDTH = 2,
              PAYLOAD_WIDTH   = DATA_WIDTH - (2 * COORD_WIDTH) - FLIT_TYPE_WIDTH,
              CORE_DATA_WIDTH = PAYLOAD_WIDTH * 2,
              NUM_NODES       = MESH_X * MESH_Y
)(
    input  logic clk,
    input  logic rst_n,

    // TX Ports (Core -> NoC)
    input  logic [NUM_NODES-1:0] [CORE_DATA_WIDTH-1:0] core_tx_data,
    input  logic [NUM_NODES-1:0] [COORD_WIDTH-1:0]     core_tx_dest_x,
    input  logic [NUM_NODES-1:0] [COORD_WIDTH-1:0]     core_tx_dest_y,
    input  logic [NUM_NODES-1:0]                       core_tx_valid,
    output logic [NUM_NODES-1:0]                       core_tx_ready,

    // RX Ports (NoC -> Core)
    output logic [NUM_NODES-1:0] [CORE_DATA_WIDTH-1:0] core_rx_data,
    output logic [NUM_NODES-1:0]                       core_rx_valid,
    input  logic [NUM_NODES-1:0]                       core_rx_ready,

    // Latency Measurement
    output logic [NUM_NODES-1:0] [TS_WIDTH-1:0]        latency_cycles_out,
    output logic [NUM_NODES-1:0]                       latency_valid
);

    // Internal Topology Wiring Matrix
    // mesh_tx_flit[X][Y][PORT]
    // Ports: 0=Local, 1=North, 2=South, 3=East, 4=West
    logic [4:0][DATA_WIDTH-1:0] mesh_rx_flit  [MESH_X][MESH_Y];
    logic [4:0]                 mesh_rx_valid [MESH_X][MESH_Y];
    logic [4:0]                 mesh_rx_ready [MESH_X][MESH_Y];

    logic [4:0][DATA_WIDTH-1:0] mesh_tx_flit  [MESH_X][MESH_Y];
    logic [4:0]                 mesh_tx_valid [MESH_X][MESH_Y];
    logic [4:0]                 mesh_tx_ready [MESH_X][MESH_Y];

    genvar x, y;
    generate
        for (x = 0; x < MESH_X; x++) begin : gen_col
            for (y = 0; y < MESH_Y; y++) begin : gen_row
                
                // Flattened Node ID for core port mapping
                localparam NODE = (y * MESH_X) + x;

                // Instantiate Network Interface (NI)
                network_interface #(
                    .DATA_WIDTH(DATA_WIDTH), 
                    .COORD_WIDTH(COORD_WIDTH), 
                    .TS_WIDTH(TS_WIDTH),
                    .FLIT_TYPE_WIDTH(FLIT_TYPE_WIDTH),
                    .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
                    .CORE_DATA_WIDTH(CORE_DATA_WIDTH)
                ) ni_inst (
                    .clk(clk), 
                    .rst_n(rst_n),
                    
                    // Connected to Top-Level Core Pins
                    .core_tx_data  (core_tx_data[NODE]),
                    .core_tx_dest_x(core_tx_dest_x[NODE]),
                    .core_tx_dest_y(core_tx_dest_y[NODE]),
                    .core_tx_valid (core_tx_valid[NODE]),
                    .core_tx_ready (core_tx_ready[NODE]),

                    .core_rx_data  (core_rx_data[NODE]),
                    .core_rx_valid (core_rx_valid[NODE]),
                    .core_rx_ready (core_rx_ready[NODE]),

                    // Connected to Router's Local Port [0]
                    .router_tx_flit  (mesh_rx_flit[x][y][0]),
                    .router_tx_valid (mesh_rx_valid[x][y][0]),
                    .router_tx_ready (mesh_rx_ready[x][y][0]),

                    .router_rx_flit  (mesh_tx_flit[x][y][0]),
                    .router_rx_valid (mesh_tx_valid[x][y][0]),
                    .router_rx_ready (mesh_tx_ready[x][y][0]),

                    .latency_cycles_out(latency_cycles_out[NODE]),
                    .latency_valid     (latency_valid[NODE])
                );

                // Instantiate Local Router
                router_5port #(
                    .DATA_WIDTH(DATA_WIDTH), 
                    .COORD_WIDTH(COORD_WIDTH), 
                    .FIFO_DEPTH(FIFO_DEPTH)
                ) router_inst (
                    .clk(clk), 
                    .rst_n(rst_n),
                    
                    // Static Hardware Coordinates
                    .router_x    (COORD_WIDTH'(x)),
                    .router_y    (COORD_WIDTH'(y)),

                    .rx_flit_arr (mesh_rx_flit[x][y]),
                    .rx_valid_arr(mesh_rx_valid[x][y]),
                    .rx_ready_arr(mesh_rx_ready[x][y]),

                    .tx_flit_arr (mesh_tx_flit[x][y]),
                    .tx_valid_arr(mesh_tx_valid[x][y]),
                    .tx_ready_arr(mesh_tx_ready[x][y])
                );

                // Mesh Wiring 
                
                // NORTH PORT [1] -> Connects to Router Above's SOUTH PORT [2]
                if (y > 0) begin
                    assign mesh_rx_flit[x][y][1]    = mesh_tx_flit[x][y-1][2]; 
                    assign mesh_rx_valid[x][y][1]   = mesh_tx_valid[x][y-1][2];
                    assign mesh_tx_ready[x][y-1][2] = mesh_rx_ready[x][y][1];
                end else begin
                    // North Edge Boundary Tie-off
                    assign mesh_rx_valid[x][y][1] = 1'b0;
                    assign mesh_rx_flit[x][y][1]  = '0;
                    assign mesh_tx_ready[x][y][1] = 1'b1; // Never stall if packet hits edge
                end

                // SOUTH PORT [2] -> Connects to Router Below's NORTH PORT [1]
                if (y < MESH_Y - 1) begin
                    assign mesh_rx_flit[x][y][2]    = mesh_tx_flit[x][y+1][1]; 
                    assign mesh_rx_valid[x][y][2]   = mesh_tx_valid[x][y+1][1];
                    assign mesh_tx_ready[x][y+1][1] = mesh_rx_ready[x][y][2];
                end else begin
                    // South Edge Boundary Tie-off
                    assign mesh_rx_valid[x][y][2] = 1'b0;
                    assign mesh_rx_flit[x][y][2]  = '0;
                    assign mesh_tx_ready[x][y][2] = 1'b1;
                end

                // EAST PORT [3] -> Connects to Router Right's WEST PORT [4]
                if (x < MESH_X - 1) begin
                    assign mesh_rx_flit[x][y][3]    = mesh_tx_flit[x+1][y][4]; 
                    assign mesh_rx_valid[x][y][3]   = mesh_tx_valid[x+1][y][4];
                    assign mesh_tx_ready[x+1][y][4] = mesh_rx_ready[x][y][3];
                end else begin
                    // East Edge Boundary Tie-off
                    assign mesh_rx_valid[x][y][3] = 1'b0;
                    assign mesh_rx_flit[x][y][3]  = '0;
                    assign mesh_tx_ready[x][y][3] = 1'b1;
                end

                // WEST PORT [4] -> Connects to Router Left's EAST PORT [3]
                if (x > 0) begin
                    assign mesh_rx_flit[x][y][4]    = mesh_tx_flit[x-1][y][3]; 
                    assign mesh_rx_valid[x][y][4]   = mesh_tx_valid[x-1][y][3];
                    assign mesh_tx_ready[x-1][y][3] = mesh_rx_ready[x][y][4];
                end else begin
                    // West Edge Boundary Tie-off
                    assign mesh_rx_valid[x][y][4] = 1'b0;
                    assign mesh_rx_flit[x][y][4]  = '0;
                    assign mesh_tx_ready[x][y][4] = 1'b1;
                end

            end
        end
    endgenerate

endmodule
