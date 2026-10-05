// Immediate extender: rebuilds the sign-extended immediate for each format.
module imm_ext (
    input  logic [31:0] inst,
    input  logic [2:0]  imm_type,  // 0:I 1:S 2:B 3:U 4:J
    output logic [31:0] imm
);

    always_comb begin
        unique case (imm_type)
            3'd0: imm = {{20{inst[31]}}, inst[31:20]};                                        // I
            3'd1: imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};                            // S
            3'd2: imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};   // B
            3'd3: imm = {inst[31:12], 12'd0};                                                 // U
            3'd4: imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}; // J
            default: imm = 32'd0;
        endcase
    end

endmodule
