// input_buffer_fifo.v
//   Synchronous circular FIFO used as the input buffer at each of the 5 input ports
//   of a NoC router. Stores incoming flits during congestion or arbitration stalls.
//   Strictly adheres to Valid/Ready handshake semantics to prevent flit duplication.

`timescale 1ns / 1ps

module input_buffer_fifo #(
    parameter DATA_WIDTH = 34,
    parameter DEPTH      = 8,
    parameter PTR_WIDTH  = $clog2(DEPTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] data_in,
    output wire                  full,

    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] data_out,
    output wire                  empty
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_WIDTH-1:0]  wr_ptr, rd_ptr;
    reg [PTR_WIDTH:0]    count;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign data_out = mem[rd_ptr];

    wire write_allow = wr_en && !full;
    wire read_allow  = rd_en && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else begin
            if (write_allow) begin
                mem[wr_ptr] <= data_in;
                wr_ptr      <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1;
            end

            if (read_allow) begin
                rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1;
            end

            case ({write_allow, read_allow})
                2'b10:   count <= count + 1;
                2'b01:   count <= count - 1;
                default: count <= count;
            endcase
        end
    end

endmodule
