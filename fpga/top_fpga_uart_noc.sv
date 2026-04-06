// top_fpga_uart_noc.sv
//   Top-Level FPGA Wrapper for the 4-Core Mesh NoC + UART Bridge.
//   Architecture:
//   - Node 0 (0,0): UART Gateway. Injects commands from PC, ejects responses.
//   - Node 1, 2, 3: Auto-Echo Nodes. Automatically bounce received packets 
//                   back to Node 0, embedding their Source ID in the payload.

`timescale 1ns / 1ps

module top_fpga_uart_noc #(
    parameter integer CLK_FREQ      = 100_000_000,
    parameter integer BAUD_RATE     = 115_200,
    parameter integer PAYLOAD_BYTES = 3
)(
    input  logic clk,
    input  logic rst_n,     
    
    input  logic uart_rxd,  
    output logic uart_txd   
);

    // NoC Parameters
    localparam DATA_WIDTH  = 34;
    localparam COORD_WIDTH = 1;
    localparam TS_WIDTH    = 16;
    localparam CORE_DATA_W = 60; // 30-bit payload x 2 flits
    localparam NUM_NODES   = 4;

    // UART Subsystem Wires
    logic [7:0] rx_byte;
    logic       rx_byte_valid;
    
    logic       cmd_valid;
    logic [1:0] cmd_dest_node;
    logic [(PAYLOAD_BYTES*8)-1:0] cmd_payload;
    
    logic       fmt_valid;
    logic [1:0] fmt_src_node;
    logic [(PAYLOAD_BYTES*8)-1:0] fmt_payload;
    logic [TS_WIDTH-1:0]          fmt_latency;
    logic       fmt_busy;
    
    logic [7:0] tx_byte;
    logic       tx_byte_valid;
    logic       tx_ready;

    logic [1:0] const_payload_len;
    assign const_payload_len = 2'd3;

    // NoC Fabric Wires
    logic [3:0][CORE_DATA_W-1:0] core_tx_data;
    logic [3:0][COORD_WIDTH-1:0] core_tx_dest_x;
    logic [3:0][COORD_WIDTH-1:0] core_tx_dest_y;
    logic [3:0]                  core_tx_valid;
    logic [3:0]                  core_tx_ready;

    logic [3:0][CORE_DATA_W-1:0] core_rx_data;
    logic [3:0]                  core_rx_valid;
    logic [3:0]                  core_rx_ready;
    
    logic [3:0][TS_WIDTH-1:0]    latency_cycles;
    logic [3:0]                  latency_valid;

    // Instantiations
    
    uart_rx #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx(uart_rxd), .rx_data(rx_byte), .rx_valid(rx_byte_valid)
    );

    uart_cmd_parser #(.PAYLOAD_BYTES(PAYLOAD_BYTES)) u_parser (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_byte), .rx_valid(rx_byte_valid),
        .cmd_valid(cmd_valid), .cmd_dest_node(cmd_dest_node),
        .cmd_payload(cmd_payload), .cmd_payload_len()
    );

    uart_resp_formatter #(.PAYLOAD_BYTES(PAYLOAD_BYTES), .TS_WIDTH(TS_WIDTH)) u_fmt (
        .clk(clk), .rst_n(rst_n),
        .fmt_valid(fmt_valid), .fmt_src_node(fmt_src_node),
        .fmt_payload(fmt_payload), .fmt_payload_len(const_payload_len),
        .fmt_latency(fmt_latency),
        .tx_data(tx_byte), .tx_valid(tx_byte_valid), .tx_ready(tx_ready),
        .fmt_busy(fmt_busy)
    );

    uart_tx #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(tx_byte), .tx_valid(tx_byte_valid), .tx_ready(tx_ready),
        .tx(uart_txd)
    );

    mesh_fabric_noc #(
        .MESH_X(2), .MESH_Y(2), 
        .DATA_WIDTH(DATA_WIDTH), .COORD_WIDTH(COORD_WIDTH), .TS_WIDTH(TS_WIDTH)
    ) u_noc (
        .clk(clk), .rst_n(rst_n),
        .core_tx_data(core_tx_data), .core_tx_dest_x(core_tx_dest_x),
        .core_tx_dest_y(core_tx_dest_y), .core_tx_valid(core_tx_valid),
        .core_tx_ready(core_tx_ready),
        
        .core_rx_data(core_rx_data), .core_rx_valid(core_rx_valid),
        .core_rx_ready(core_rx_ready),
        
        .latency_cycles_out(latency_cycles), .latency_valid(latency_valid)
    );

    // NODE 0: The UART Gateway Logic
    
    // --- TX Injection (UART -> NoC) ---
    logic inj_busy;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_tx_valid[0] <= 1'b0;
            inj_busy         <= 1'b0;
        end else begin
            if (cmd_valid && !inj_busy) begin
                core_tx_valid[0]  <= 1'b1;
                core_tx_dest_x[0] <= cmd_dest_node[0];
                core_tx_dest_y[0] <= cmd_dest_node[1];
                // Pad the 24-bit UART payload into the 60-bit Core interface
                core_tx_data[0]   <= {36'd0, cmd_payload};
                inj_busy          <= 1'b1;
            end else if (core_tx_valid[0] && core_tx_ready[0]) begin
                core_tx_valid[0]  <= 1'b0;
                inj_busy          <= 1'b0;
            end
        end
    end

    // --- RX Ejection (NoC -> UART) ---
    assign fmt_valid = core_rx_valid[0] && !fmt_busy;
    assign core_rx_ready[0] = fmt_valid; 
    
    // Extract the embedded Source Node ID and payload from the bounced packet
    assign fmt_src_node = core_rx_data[0][25:24];
    assign fmt_payload  = core_rx_data[0][23:0];
    assign fmt_latency  = latency_cycles[0];

    // NODES 1, 2, 3: The Hardware Auto-Echo Nodes
    
    genvar i;
    generate
        for (i = 1; i < 4; i++) begin : gen_echo_nodes
            
            logic echoing;
            
            assign core_rx_ready[i] = !echoing;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    core_tx_valid[i] <= 1'b0;
                    echoing          <= 1'b0;
                end else begin
                    // Step 1: Packet Arrives
                    if (core_rx_valid[i] && !echoing) begin
                        // Embed our Node ID into bits [25:24] so Node 0 knows who replied
                        core_tx_data[i]   <= {34'd0, i[1:0], core_rx_data[i][23:0]};
                        core_tx_dest_x[i] <= 1'b0; // Hardcoded bounce back to Node 0 (0,0)
                        core_tx_dest_y[i] <= 1'b0;
                        core_tx_valid[i]  <= 1'b1;
                        echoing           <= 1'b1;
                    end 
                    // Step 2: Packet Injected back into NoC
                    else if (core_tx_valid[i] && core_tx_ready[i]) begin
                        core_tx_valid[i] <= 1'b0;
                        echoing          <= 1'b0;
                    end
                end
            end
            
        end
    endgenerate

endmodule
