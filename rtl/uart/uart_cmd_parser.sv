// uart_cmd_parser.sv
// Parses the simple text command:   SEND <node> <payload_bytes><CR>
//
// Protocol (all ASCII, CR = 0x0D terminates):
//   "SEND 3 AB\r"
//    ^^^^   ^  ^^
//    verb   |  raw hex payload chars (PAYLOAD_BYTES * 2 hex digits)
//           dest node digit (0-3)
//
// Simpler binary protocol actually used in testbench:
//   Byte 0: command byte  0xA0 | dest_node[1:0]
//   Bytes 1..PAYLOAD_BYTES: raw payload bytes
//
// This matches what tb_uart_noc drives:
//   send_byte(8'hA0 | dest);   // cmd
//   send_byte(payload_hi);
//   send_byte(payload_lo);     // only PAYLOAD_BYTES=3 bytes but we use 2 for simplicity
//
// Interface (matches uart_noc_top.sv):
//   .rx_data         [7:0]               from uart_rx
//   .rx_valid                            from uart_rx
//   .cmd_valid                           pulses one cycle when command complete
//   .cmd_dest_node   [1:0]              destination node index 0-3
//   .cmd_payload     [PAYLOAD_BYTES*8-1:0]  payload bytes
//   .cmd_payload_len [$clog2(PAYLOAD_BYTES+1)-1:0]  always PAYLOAD_BYTES

`timescale 1ns / 1ps

module uart_cmd_parser #(
    parameter integer PAYLOAD_BYTES = 3
)(
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic [7:0]                rx_data,
    input  logic                      rx_valid,

    output logic                      cmd_valid,
    output logic [1:0]                cmd_dest_node,
    output logic [PAYLOAD_BYTES*8-1:0] cmd_payload,
    output logic [$clog2(PAYLOAD_BYTES+1)-1:0] cmd_payload_len
);

    localparam integer CNT_W = $clog2(PAYLOAD_BYTES + 1);

    // Binary framing:
    //   State 0: wait for command byte (top nibble 0xA = 4'hA means "send")
    //   State 1..PAYLOAD_BYTES: collect payload bytes
    logic [CNT_W-1:0]         byte_cnt;   // 0 = expecting cmd, 1..PB = payload
    logic [PAYLOAD_BYTES*8-1:0] payload_r;
    logic [1:0]               dest_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt      <= '0;
            payload_r     <= '0;
            dest_r        <= 2'd0;
            cmd_valid     <= 1'b0;
            cmd_dest_node <= 2'd0;
            cmd_payload   <= '0;
            cmd_payload_len <= '0;
        end else begin
            cmd_valid <= 1'b0;   // default: pulse only

            if (rx_valid) begin
                if (byte_cnt == '0) begin
                    // Command byte: expect 0xA0 | dest[1:0]
                    if (rx_data[7:2] == 6'b101000) begin   // 0xA0..0xA3
                        dest_r   <= rx_data[1:0];
                        byte_cnt <= CNT_W'(1);
                    end
                    // else: garbage — stay in byte 0 wait
                end else begin
                    // Payload bytes: MSB first, shift left
                    payload_r <= {payload_r[PAYLOAD_BYTES*8-9:0], rx_data};

                    if (byte_cnt == CNT_W'(PAYLOAD_BYTES)) begin
                        // Last payload byte received
                        cmd_dest_node   <= dest_r;
                        cmd_payload     <= {payload_r[PAYLOAD_BYTES*8-9:0], rx_data};
                        cmd_payload_len <= CNT_W'(PAYLOAD_BYTES);
                        cmd_valid       <= 1'b1;
                        byte_cnt        <= '0;
                    end else begin
                        byte_cnt <= byte_cnt + 1'b1;
                    end
                end
            end
        end
    end

endmodule
