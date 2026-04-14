`timescale 1ns / 1ps

module top_fpga_uart_stream_noc #(
    parameter integer CLK_FREQ      = 100_000_000,
    parameter integer BAUD_RATE     = 115_200,
    parameter integer PAYLOAD_BYTES = 5  // INCREASED to 5 bytes (40 bits) for RGB + Address
)(
    input  logic clk,           // 100 MHz board clock
    input  logic rst_n,         // Active-low reset
    input  logic btn_stream,    // Button to trigger the 4096-packet image stream
    
    input  logic uart_rxd,      // UART RX (from PC)
    output logic uart_txd       // UART TX (to PC)
);

    // NoC Parameters
    localparam DATA_WIDTH  = 34;
    localparam COORD_WIDTH = 1;
    localparam TS_WIDTH    = 16;
    localparam CORE_DATA_W = 60; // We have 60 bits of payload capacity!
    localparam NUM_NODES   = 4;

    // =========================================================================
    // UART Subsystem Wires
    // =========================================================================
    logic [7:0] rx_byte;
    logic       rx_byte_valid;
    
    logic       cmd_valid;
    logic       cmd_is_binary; 
    logic [1:0] cmd_dest_node;
    logic [(PAYLOAD_BYTES*8)-1:0] cmd_payload;
    
    logic       fmt_valid;
    logic [1:0] fmt_src_node;
    logic [(PAYLOAD_BYTES*8)-1:0] fmt_payload;
    logic [TS_WIDTH-1:0]          fmt_latency;
    logic       fmt_busy;
    logic       fmt_is_binary;

    logic [7:0] tx_byte;
    logic       tx_byte_valid;
    logic       tx_ready;

    logic [2:0] const_payload_len;
    assign const_payload_len = 3'd5; // Send 5 bytes per packet

    // =========================================================================
    // NoC Fabric Wires
    // =========================================================================
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

    // =========================================================================
    // UART Instantiations
    // =========================================================================
    uart_rx #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx(uart_rxd), .rx_data(rx_byte), .rx_valid(rx_byte_valid)
    );

    uart_cmd_parser #(.PAYLOAD_BYTES(PAYLOAD_BYTES)) u_parser (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_byte), .rx_valid(rx_byte_valid),
        .cmd_valid(cmd_valid), 
        .cmd_is_binary(cmd_is_binary), 
        .cmd_dest_node(cmd_dest_node),
        .cmd_payload(cmd_payload), .cmd_payload_len()
    );

    uart_resp_formatter #(.PAYLOAD_BYTES(PAYLOAD_BYTES), .TS_WIDTH(TS_WIDTH)) u_fmt (
        .clk(clk), .rst_n(rst_n),
        .fmt_valid(fmt_valid), 
        .is_binary(fmt_is_binary),
        .fmt_src_node(fmt_src_node),
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

    // =========================================================================
    // NoC Instantiation
    // =========================================================================
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

    // =========================================================================
    // NODE 0 (0,0): RGB Image ROM & UART TX Injection
    // =========================================================================
    
    logic [11:0] rom_addr;
    wire  [23:0] rom_data_out; 
    (* rom_style = "block" *) logic [23:0] image_rom [0:4095];
    
    initial $readmemh("image_64x64_rgb.mem", image_rom);
    assign rom_data_out = image_rom[rom_addr];

    logic streaming;
    logic inj_busy;
    
    logic btn_stream_q;
    always_ff @(posedge clk) btn_stream_q <= btn_stream;
    wire start_stream = btn_stream && !btn_stream_q;

    // --- TX Injection (UART / ROM -> NoC) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_tx_valid[0] <= 1'b0;
            inj_busy         <= 1'b0;
            streaming        <= 1'b0;
            rom_addr         <= '0;
        end else begin
            if (start_stream && !streaming) begin
                streaming <= 1'b1;
                rom_addr  <= '0;
            end

            if (streaming && !inj_busy) begin
                core_tx_valid[0]  <= 1'b1;
                core_tx_dest_x[0] <= 1'b1; 
                core_tx_dest_y[0] <= 1'b1;
                
                // Pack 60-bit Payload: {19-bit Pad, Bit 40: is_binary=1, Bits 39:0: Addr+RGB}
                core_tx_data[0]   <= {19'd0, 1'b1, 4'h0, rom_addr, rom_data_out};
                inj_busy          <= 1'b1;
                
            end else if (cmd_valid && !inj_busy && !streaming) begin
                core_tx_valid[0]  <= 1'b1;
                core_tx_dest_x[0] <= cmd_dest_node[0];
                core_tx_dest_y[0] <= cmd_dest_node[1];
                
                // Pack 60-bit Payload: {19-bit Pad, Bit 40: cmd_is_binary, Bits 39:0: Untouched PC Ping Data}
                core_tx_data[0]   <= {19'd0, cmd_is_binary, cmd_payload}; 
                inj_busy          <= 1'b1;
                
            end else if (core_tx_valid[0] && core_tx_ready[0]) begin
                core_tx_valid[0] <= 1'b0;
                inj_busy         <= 1'b0;
                
                if (streaming) begin
                    if (rom_addr == 12'd4095) streaming <= 1'b0; 
                    else rom_addr <= rom_addr + 1'b1;
                end
            end
        end
    end

    // --- RX Ejection (NoC -> UART) ---
    assign fmt_valid = core_rx_valid[0] && !fmt_busy;
    assign core_rx_ready[0] = fmt_valid; 
    
    assign fmt_is_binary = core_rx_data[0][40];
    assign fmt_src_node  = core_rx_data[0][42:41];
    assign fmt_payload   = core_rx_data[0][39:0]; 
    assign fmt_latency   = latency_cycles[0];

    // =========================================================================
    // NODES 1, 2, 3: Hardware Auto-Echo Nodes
    // =========================================================================
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
                    if (core_rx_valid[i] && !echoing) begin
                        // Stamp Node ID at [42:41], Preserve is_binary at [40], Preserve Payload at [39:0]
                        core_tx_data[i]   <= {17'd0, i[1:0], core_rx_data[i][40:0]};
                        core_tx_dest_x[i] <= 1'b0; 
                        core_tx_dest_y[i] <= 1'b0;
                        core_tx_valid[i]  <= 1'b1;
                        echoing           <= 1'b1;
                    end 
                    else if (core_tx_valid[i] && core_tx_ready[i]) begin
                        core_tx_valid[i] <= 1'b0;
                        echoing          <= 1'b0;
                    end
                end
            end
        end
    endgenerate

endmodule