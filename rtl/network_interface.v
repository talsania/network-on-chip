// network_interface.v
//   Packetization and Measurement Unit acts as the bridge between a 
//   processing core and its local router.
//   - TX Path: Accepts wide raw data from the core, splits it into a 3-flit 
//     packet (Header, Body, Tail), and injects a generation timestamp.
//   - RX Path: Reassembles incoming 3-flit packets, extracts the raw data 
//     for the core, and calculates end-to-end latency using the timestamp.

`timescale 1ns / 1ps

module network_interface #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1,  
    parameter TS_WIDTH    = 16  // Width of latency timestamp
)(
    input  clk,
    input  rst_n,

    // Core Side Interface
    // A packet consists of 3 flits - Header, Body, Tail - each of DATA_WIDTH size.
    // Out of which, Header flit contains the timestamp which is not sent by core.
    // Flit Layout: [Dest X | Dest Y | Flit Type (2 bits) | Payload]
    // Flit Type  : 01=Head, 10=Body, 11=Tail

    input      [(DATA_WIDTH - (2*COORD_WIDTH) - 2)*2 - 1 : 0] core_tx_data,
    input      [COORD_WIDTH-1:0]                              core_tx_dest_x,
    input      [COORD_WIDTH-1:0]                              core_tx_dest_y,
    input                                                     core_tx_valid,
    output reg                                                core_tx_ready,

    output     [(DATA_WIDTH - (2*COORD_WIDTH) - 2)*2 - 1 : 0] core_rx_data,
    output reg                                                core_rx_valid,
    input                                                     core_rx_ready,

    // Router Side Interface
    output reg [DATA_WIDTH-1:0] router_tx_flit,
    output reg                  router_tx_valid,
    input                       router_tx_ready,

    input      [DATA_WIDTH-1:0] router_rx_flit,
    input                       router_rx_valid,
    output reg                  router_rx_ready,

    // Latency Measurement
    output reg [TS_WIDTH-1:0] latency_cycles_out,
    output reg                latency_valid
);

    localparam FLIT_TYPE_WIDTH = 2;
    localparam PAYLOAD_WIDTH   = DATA_WIDTH - (2 * COORD_WIDTH) - FLIT_TYPE_WIDTH;
    localparam CORE_DATA_WIDTH = PAYLOAD_WIDTH * 2; // Data spans Body and Tail flits

    localparam [FLIT_TYPE_WIDTH-1:0] TYPE_HEAD = 2'b01;
    localparam [FLIT_TYPE_WIDTH-1:0] TYPE_BODY = 2'b10;
    localparam [FLIT_TYPE_WIDTH-1:0] TYPE_TAIL = 2'b11;

    // Time Counter for latency
    reg [TS_WIDTH-1:0] ts_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ts_counter <= 0;
        else        ts_counter <= ts_counter + 1;
    end

    // TX PATH: Packetization State Machine
    localparam [1:0] TX_HEAD  = 2'd0,
                     TX_BODY  = 2'd1,
                     TX_TAIL  = 2'd2,
                     TX_CLOSE = 2'd3;

    reg [1:0] tx_state;

    reg [CORE_DATA_WIDTH-1:0] tx_data_reg;
    reg [COORD_WIDTH-1:0]     tx_dest_x_reg;
    reg [COORD_WIDTH-1:0]     tx_dest_y_reg;
   
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state        <= TX_HEAD;
            router_tx_valid <= 1'b0;
            core_tx_ready   <= 1'b1;
            router_tx_flit  <= 0;
        end else begin
            case (tx_state)
                TX_HEAD: begin
                    if (core_tx_valid && core_tx_ready) begin
                        tx_data_reg   <= core_tx_data;
                        tx_dest_x_reg <= core_tx_dest_x;
                        tx_dest_y_reg <= core_tx_dest_y;
                        
                        router_tx_valid <= 1'b1;
                        // Assemble Head: Coords + Type + Timestamp (with zero-padding)
                        router_tx_flit  <= {core_tx_dest_x, core_tx_dest_y, TYPE_HEAD, 
                                            {{(PAYLOAD_WIDTH-TS_WIDTH){1'b0}}, ts_counter}};

                        core_tx_ready <= 1'b0; // Lock out the core until packet is sent
                        tx_state      <= TX_BODY;
                    end
                end

                TX_BODY: begin
                    if (router_tx_ready) begin
                        // Assemble Body: Coords + Type + Upper half of data
                        router_tx_flit  <= {tx_dest_x_reg, tx_dest_y_reg, TYPE_BODY, 
                                            tx_data_reg[CORE_DATA_WIDTH-1 -: PAYLOAD_WIDTH]};
                        tx_state <= TX_TAIL;
                    end
                end

                TX_TAIL: begin
                    if (router_tx_ready) begin
                        // Assemble Tail: Coords + Type + Lower half of data
                        router_tx_flit  <= {tx_dest_x_reg, tx_dest_y_reg, TYPE_TAIL, 
                                            tx_data_reg[PAYLOAD_WIDTH-1 : 0]};
                        tx_state <= TX_CLOSE;
                    end
                end

                TX_CLOSE: begin
                    if (router_tx_ready) begin
                        // Close transmission
                        router_tx_valid <= 1'b0;
                        core_tx_ready   <= 1'b1;
                        tx_state        <= TX_HEAD;
                    end
                end

                default: tx_state       <= TX_HEAD;
            endcase
        end
    end

    // RX PATH: De-packetization & Latency Engine
    localparam [1:0] RX_HEAD = 2'd0,
                     RX_BODY = 2'd1,
                     RX_TAIL = 2'd2,
                     RX_PUSH = 2'd3;

    reg [1:0] rx_state;

    reg [CORE_DATA_WIDTH-1:0] rx_data_reg;
    wire [FLIT_TYPE_WIDTH-1:0] rx_flit_type;
    wire [PAYLOAD_WIDTH-1:0]   rx_payload;

    assign rx_flit_type = router_rx_flit[DATA_WIDTH-(2*COORD_WIDTH)-1 -: FLIT_TYPE_WIDTH];
    assign rx_payload   = router_rx_flit[PAYLOAD_WIDTH-1 : 0];
    assign core_rx_data = rx_data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state           <= RX_HEAD;
            router_rx_ready    <= 1'b1;
            core_rx_valid      <= 1'b0;
            latency_valid      <= 1'b0;
            latency_cycles_out <= 0;
        end else begin

            case (rx_state)
                RX_HEAD: begin
                    router_rx_ready <= 1'b1;
                    if (router_rx_valid && router_rx_ready && rx_flit_type == TYPE_HEAD) begin
                        // Extract generation timestamp and calculate latency
                        latency_cycles_out <= ts_counter - rx_payload[TS_WIDTH-1:0];
                        rx_state           <= RX_BODY;
                    end
                end

                RX_BODY: begin
                    if (router_rx_valid && router_rx_ready && rx_flit_type == TYPE_BODY) begin
                        // Latch upper half of data
                        rx_data_reg[CORE_DATA_WIDTH-1 -: PAYLOAD_WIDTH] <= rx_payload;
                        rx_state <= RX_TAIL;
                    end
                end

                RX_TAIL: begin
                    if (router_rx_valid && router_rx_ready && rx_flit_type == TYPE_TAIL) begin
                        // Latch lower half of data
                        rx_data_reg[PAYLOAD_WIDTH-1 : 0] <= rx_payload;
                            
                        // Packet fully reassembled, pause RX and push to core
                        router_rx_ready <= 1'b0; 
                        core_rx_valid   <= 1'b1;
                        latency_valid   <= 1'b1;
                        rx_state        <= RX_PUSH;
                    end
                end

                RX_PUSH: begin
                    if (core_rx_valid && core_rx_ready) begin
                        // Core accepted the data, open router gates for next packet
                        core_rx_valid   <= 1'b0;
                        latency_valid   <= 1'b0;
                        router_rx_ready <= 1'b1;
                        rx_state        <= RX_HEAD;
                    end
                end

                default: rx_state       <= RX_HEAD;
            endcase
        end
    end

endmodule
