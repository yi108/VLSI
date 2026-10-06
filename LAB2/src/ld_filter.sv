// Load data filter: aligns and extends data returned by the data memory.
module ld_filter (
    input  logic [31:0] rdata,   // raw word from DM
    input  logic [1:0]  offset,  // byte address offset
    input  logic [2:0]  funct3,  // 000 LB 001 LH 010 LW/FLW 100 LBU 101 LHU
    output logic [31:0] ldata
);

    logic [7:0]  b;
    logic [15:0] h;

    always_comb begin
        b = rdata[8*offset +: 8];
        h = offset[1] ? rdata[31:16] : rdata[15:0];
        unique case (funct3)
            3'b000:  ldata = {{24{b[7]}}, b};
            3'b100:  ldata = {24'd0, b};
            3'b001:  ldata = {{16{h[15]}}, h};
            3'b101:  ldata = {16'd0, h};
            default: ldata = rdata;
        endcase
    end

endmodule
