// Jump/branch unit: resolves control flow in the EX stage using forwarded
// operands and produces the redirect target.
module jb_unit (
    input  logic        is_branch,
    input  logic        is_jal,
    input  logic        is_jalr,
    input  logic [2:0]  funct3,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] pc,
    input  logic [31:0] imm,
    output logic        taken,
    output logic [31:0] target
);

    logic br_cond;

    always_comb begin
        unique case (funct3)
            3'b000:  br_cond = (rs1_data == rs2_data);                     // BEQ
            3'b001:  br_cond = (rs1_data != rs2_data);                     // BNE
            3'b100:  br_cond = ($signed(rs1_data) <  $signed(rs2_data));   // BLT
            3'b101:  br_cond = ($signed(rs1_data) >= $signed(rs2_data));   // BGE
            3'b110:  br_cond = (rs1_data <  rs2_data);                     // BLTU
            3'b111:  br_cond = (rs1_data >= rs2_data);                     // BGEU
            default: br_cond = 1'b0;
        endcase

        taken  = is_jal || is_jalr || (is_branch && br_cond);
        target = is_jalr ? ((rs1_data + imm) & 32'hFFFF_FFFE)
                         : (pc + imm);
    end

endmodule
