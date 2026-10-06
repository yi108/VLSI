// Instruction decoder: translates a fetched instruction into the control
// bundle used by the rest of the pipeline.
module decoder (
    input  logic [31:0] inst,

    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd,
    output logic        uses_rs1,   // reads integer rs1
    output logic        uses_rs2,   // reads integer rs2
    output logic        uses_frs1,  // reads float rs1
    output logic        uses_frs2,  // reads float rs2
    output logic        rf_we,      // writes integer rd
    output logic        frf_we,     // writes float rd

    output logic [4:0]  alu_op,     // encoding shared with alu.sv
    output logic [1:0]  opa_sel,    // 0: rs1, 1: pc, 2: zero
    output logic        opb_sel,    // 0: rs2, 1: imm
    output logic [2:0]  imm_type,   // 0:I 1:S 2:B 3:U 4:J

    output logic        is_load,
    output logic        is_store,
    output logic        store_fp,   // FSW: store data comes from the float RF
    output logic [2:0]  mem_f3,     // size/sign for DM access

    output logic        is_branch,
    output logic        is_jal,
    output logic        is_jalr,

    output logic        is_fpu,
    output logic [1:0]  fpu_op,     // 0 FADD, 1 FSUB, 2 FMIN, 3 FMAX

    output logic        is_csr,
    output logic [11:0] csr_addr,

    output logic        wb_mem      // writeback selects load data
);

    // keep in sync with alu.sv
    localparam OP_ADD   = 5'd0,  OP_SUB   = 5'd1,  OP_SLL   = 5'd2,  OP_SLT   = 5'd3;
    localparam OP_SLTU  = 5'd4,  OP_XOR   = 5'd5,  OP_SRL   = 5'd6,  OP_SRA   = 5'd7;
    localparam OP_OR    = 5'd8,  OP_AND   = 5'd9,  OP_MUL   = 5'd10, OP_MULH  = 5'd11;
    localparam OP_MULHSU= 5'd12, OP_MULHU = 5'd13, OP_CLZ   = 5'd14, OP_CTZ   = 5'd15;
    localparam OP_CPOP  = 5'd16, OP_ROL   = 5'd17, OP_ROR   = 5'd18, OP_MIN   = 5'd19;
    localparam OP_MAX   = 5'd20, OP_MINU  = 5'd21, OP_MAXU  = 5'd22, OP_BSET  = 5'd23;
    localparam OP_BCLR  = 5'd24, OP_BEXT  = 5'd25, OP_DOTP4 = 5'd26, OP_SADD8 = 5'd27;
    localparam OP_SSUB8 = 5'd28, OP_ABS   = 5'd29, OP_CLIP8 = 5'd30, OP_COPYB = 5'd31;

    logic [6:0] opcode, f7;
    logic [2:0] f3;

    always_comb begin
        opcode   = inst[6:0];
        f3       = inst[14:12];
        f7       = inst[31:25];
        rs1      = inst[19:15];
        rs2      = inst[24:20];
        rd       = inst[11:7];

        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;
        uses_frs1 = 1'b0;
        uses_frs2 = 1'b0;
        rf_we     = 1'b0;
        frf_we    = 1'b0;
        alu_op    = OP_ADD;
        opa_sel   = 2'd0;
        opb_sel   = 1'b0;
        imm_type  = 3'd0;
        is_load   = 1'b0;
        is_store  = 1'b0;
        store_fp  = 1'b0;
        mem_f3    = f3;
        is_branch = 1'b0;
        is_jal    = 1'b0;
        is_jalr   = 1'b0;
        is_fpu    = 1'b0;
        fpu_op    = 2'd0;
        is_csr    = 1'b0;
        csr_addr  = inst[31:20];
        wb_mem    = 1'b0;

        unique case (opcode)
            7'b0110011: begin  // R-type: base, M, B-subset
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                rf_we    = 1'b1;
                unique case (f7)
                    7'b0000001: alu_op = OP_MUL + {3'd0, f3[1:0]};  // MUL..MULHU = 10..13
                    7'b0100000: alu_op = (f3 == 3'b000) ? OP_SUB : OP_SRA;
                    7'b0110000: alu_op = (f3 == 3'b001) ? OP_ROL : OP_ROR;
                    7'b0000101: begin                        // MIN/MINU/MAX/MAXU
                        unique case (f3)
                            3'b100:  alu_op = OP_MIN;
                            3'b101:  alu_op = OP_MINU;
                            3'b110:  alu_op = OP_MAX;
                            default: alu_op = OP_MAXU;
                        endcase
                    end
                    7'b0010100: alu_op = OP_BSET;
                    7'b0100100: alu_op = (f3 == 3'b001) ? OP_BCLR : OP_BEXT;
                    default: begin                           // f7 == 0: base ops
                        unique case (f3)
                            3'b000:  alu_op = OP_ADD;
                            3'b001:  alu_op = OP_SLL;
                            3'b010:  alu_op = OP_SLT;
                            3'b011:  alu_op = OP_SLTU;
                            3'b100:  alu_op = OP_XOR;
                            3'b101:  alu_op = OP_SRL;
                            3'b110:  alu_op = OP_OR;
                            default: alu_op = OP_AND;
                        endcase
                    end
                endcase
            end

            7'b0010011: begin  // I-type ALU + shifts + CLZ/CTZ/CPOP
                uses_rs1 = 1'b1;
                rf_we    = 1'b1;
                opb_sel  = 1'b1;
                unique case (f3)
                    3'b000: alu_op = OP_ADD;
                    3'b010: alu_op = OP_SLT;
                    3'b011: alu_op = OP_SLTU;
                    3'b100: alu_op = OP_XOR;
                    3'b110: alu_op = OP_OR;
                    3'b111: alu_op = OP_AND;
                    3'b001: begin
                        if (f7 == 7'b0110000) begin  // CLZ/CTZ/CPOP (unary)
                            unique case (rs2)
                                5'd0:    alu_op = OP_CLZ;
                                5'd1:    alu_op = OP_CTZ;
                                default: alu_op = OP_CPOP;
                            endcase
                        end else begin
                            alu_op = OP_SLL;  // SLLI (shamt is in imm[4:0])
                        end
                    end
                    default: alu_op = (f7 == 7'b0100000) ? OP_SRA : OP_SRL;
                endcase
            end

            7'b0000011: begin  // integer loads
                uses_rs1 = 1'b1;
                rf_we    = 1'b1;
                opb_sel  = 1'b1;
                is_load  = 1'b1;
                wb_mem   = 1'b1;
            end

            7'b0100011: begin  // integer stores
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                opb_sel  = 1'b1;
                imm_type = 3'd1;
                is_store = 1'b1;
            end

            7'b1100011: begin  // branches
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                imm_type  = 3'd2;
                is_branch = 1'b1;
            end

            7'b1101111: begin  // JAL
                rf_we    = 1'b1;
                imm_type = 3'd4;
                is_jal   = 1'b1;
            end

            7'b1100111: begin  // JALR
                uses_rs1 = 1'b1;
                rf_we    = 1'b1;
                is_jalr  = 1'b1;
            end

            7'b0110111: begin  // LUI
                rf_we    = 1'b1;
                opa_sel  = 2'd2;
                opb_sel  = 1'b1;
                imm_type = 3'd3;
                alu_op   = OP_COPYB;
            end

            7'b0010111: begin  // AUIPC
                rf_we    = 1'b1;
                opa_sel  = 2'd1;
                opb_sel  = 1'b1;
                imm_type = 3'd3;
                alu_op   = OP_ADD;
            end

            7'b1110011: begin  // CSR counter reads
                rf_we  = 1'b1;
                is_csr = 1'b1;
            end

            7'b0000111: begin  // FLW
                uses_rs1 = 1'b1;
                frf_we   = 1'b1;
                opb_sel  = 1'b1;
                is_load  = 1'b1;
                wb_mem   = 1'b1;
            end

            7'b0100111: begin  // FSW
                uses_rs1  = 1'b1;
                uses_frs2 = 1'b1;
                opb_sel   = 1'b1;
                imm_type  = 3'd1;
                is_store  = 1'b1;
                store_fp  = 1'b1;
            end

            7'b1010011: begin  // FADD.S / FSUB.S / FMIN.S / FMAX.S
                uses_frs1 = 1'b1;
                uses_frs2 = 1'b1;
                frf_we    = 1'b1;
                is_fpu    = 1'b1;
                unique case (f7)
                    7'b0000000: fpu_op = 2'd0;
                    7'b0000100: fpu_op = 2'd1;
                    default:    fpu_op = (f3 == 3'b000) ? 2'd2 : 2'd3;
                endcase
            end

            7'b0001011: begin  // DSP
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                rf_we    = 1'b1;
                unique case (f3)
                    3'b000:  alu_op = OP_DOTP4;
                    3'b001:  alu_op = OP_SADD8;
                    3'b010:  alu_op = OP_SSUB8;
                    3'b011:  alu_op = OP_ABS;
                    default: alu_op = OP_CLIP8;
                endcase
            end

            default: ;  // treated as NOP
        endcase
    end

endmodule
