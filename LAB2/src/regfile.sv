// General-purpose register file, 32 x 32-bit.
// HARD_ZERO=1: x0 wired to zero (integer RF). HARD_ZERO=0: float RF (f0 writable).
// Read ports bypass a same-cycle write so an instruction in ID sees the value
// being retired by the instruction in WB.
module regfile #(
    parameter HARD_ZERO = 1
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [4:0]  raddr1,
    input  logic [4:0]  raddr2,
    output logic [31:0] rdata1,
    output logic [31:0] rdata2,
    input  logic        we,
    input  logic [4:0]  waddr,
    input  logic [31:0] wdata
);

    logic [31:0] mem [0:31];

    wire wr_en = we && !(HARD_ZERO && waddr == 5'd0);

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) mem[i] <= 32'd0;
        end else if (wr_en) begin
            mem[waddr] <= wdata;
        end
    end

    always_comb begin
        rdata1 = (HARD_ZERO && raddr1 == 5'd0) ? 32'd0 :
                 (wr_en && waddr == raddr1)    ? wdata : mem[raddr1];
        rdata2 = (HARD_ZERO && raddr2 == 5'd0) ? 32'd0 :
                 (wr_en && waddr == raddr2)    ? wdata : mem[raddr2];
    end

endmodule
