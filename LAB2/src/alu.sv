// Integer ALU: RV32I base ops, M-extension multiplies, B-subset and DSP ops.
// Operation encoding must match decoder.sv.
module alu (
    input  logic [4:0]  op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] y
);

    // --- op encoding (keep in sync with decoder.sv) ---
    localparam OP_ADD   = 5'd0,  OP_SUB   = 5'd1,  OP_SLL   = 5'd2,  OP_SLT   = 5'd3;
    localparam OP_SLTU  = 5'd4,  OP_XOR   = 5'd5,  OP_SRL   = 5'd6,  OP_SRA   = 5'd7;
    localparam OP_OR    = 5'd8,  OP_AND   = 5'd9,  OP_MUL   = 5'd10, OP_MULH  = 5'd11;
    localparam OP_MULHSU= 5'd12, OP_MULHU = 5'd13, OP_CLZ   = 5'd14, OP_CTZ   = 5'd15;
    localparam OP_CPOP  = 5'd16, OP_ROL   = 5'd17, OP_ROR   = 5'd18, OP_MIN   = 5'd19;
    localparam OP_MAX   = 5'd20, OP_MINU  = 5'd21, OP_MAXU  = 5'd22, OP_BSET  = 5'd23;
    localparam OP_BCLR  = 5'd24, OP_BEXT  = 5'd25, OP_DOTP4 = 5'd26, OP_SADD8 = 5'd27;
    localparam OP_SSUB8 = 5'd28, OP_ABS   = 5'd29, OP_CLIP8 = 5'd30, OP_COPYB = 5'd31;

    logic [4:0]         sh;
    logic [5:0]         shc;
    logic signed [31:0] sa, sb;
    logic signed [63:0] mul_ss, mul_su;
    logic        [63:0] mul_uu;

    // bit counters
    logic [5:0] clz_cnt, ctz_cnt, cpop_cnt;
    always_comb begin
        clz_cnt = 6'd32;
        for (int i = 0; i < 32; i++)
            if (a[i]) clz_cnt = 31 - i;   // last hit = MSB
        ctz_cnt = 6'd32;
        for (int i = 31; i >= 0; i--)
            if (a[i]) ctz_cnt = i;        // last hit = LSB
        cpop_cnt = '0;
        for (int i = 0; i < 32; i++)
            cpop_cnt = cpop_cnt + {5'd0, a[i]};
    end

    // DSP: per-byte signed SIMD and dot product
    logic signed [8:0]  badd [0:3], bsub [0:3];
    logic signed [15:0] prod [0:3];
    logic signed [17:0] dotp;
    logic [7:0]  sadd8_b [0:3], ssub8_b [0:3];
    always_comb begin
        dotp = '0;
        for (int i = 0; i < 4; i++) begin
            badd[i] = $signed({a[8*i+7], a[8*i +: 8]}) + $signed({b[8*i+7], b[8*i +: 8]});
            bsub[i] = $signed({a[8*i+7], a[8*i +: 8]}) - $signed({b[8*i+7], b[8*i +: 8]});
            prod[i] = $signed(a[8*i +: 8]) * $signed(b[8*i +: 8]);
            sadd8_b[i] = (badd[i] > 9'sd127) ? 8'h7F : (badd[i] < -9'sd128) ? 8'h80 : badd[i][7:0];
            ssub8_b[i] = (bsub[i] > 9'sd127) ? 8'h7F : (bsub[i] < -9'sd128) ? 8'h80 : bsub[i][7:0];
            dotp = dotp + prod[i];
        end
    end

    always_comb begin
        sh     = b[4:0];
        shc    = 6'd32 - {1'b0, sh};
        sa     = $signed(a);
        sb     = $signed(b);
        mul_ss = sa * sb;
        mul_su = sa * $signed({1'b0, b});  // signed x unsigned
        mul_uu = a * b;

        unique case (op)
            OP_ADD:    y = a + b;
            OP_SUB:    y = a - b;
            OP_SLL:    y = a << sh;
            OP_SLT:    y = {31'd0, sa < sb};
            OP_SLTU:   y = {31'd0, a < b};
            OP_XOR:    y = a ^ b;
            OP_SRL:    y = a >> sh;
            OP_SRA:    y = sa >>> sh;
            OP_OR:     y = a | b;
            OP_AND:    y = a & b;
            OP_MUL:    y = mul_ss[31:0];
            OP_MULH:   y = mul_ss[63:32];
            OP_MULHSU: y = mul_su[63:32];
            OP_MULHU:  y = mul_uu[63:32];
            OP_CLZ:    y = {26'd0, clz_cnt};
            OP_CTZ:    y = {26'd0, ctz_cnt};
            OP_CPOP:   y = {26'd0, cpop_cnt};
            OP_ROL:    y = (sh == 5'd0) ? a : ((a << sh) | (a >> shc));
            OP_ROR:    y = (sh == 5'd0) ? a : ((a >> sh) | (a << shc));
            OP_MIN:    y = (sa < sb) ? a : b;
            OP_MAX:    y = (sa > sb) ? a : b;
            OP_MINU:   y = (a < b) ? a : b;
            OP_MAXU:   y = (a > b) ? a : b;
            OP_BSET:   y = a | (32'd1 << sh);
            OP_BCLR:   y = a & ~(32'd1 << sh);
            OP_BEXT:   y = {31'd0, a[sh]};
            OP_DOTP4:  y = {{14{dotp[17]}}, dotp};
            OP_SADD8:  y = {sadd8_b[3], sadd8_b[2], sadd8_b[1], sadd8_b[0]};
            OP_SSUB8:  y = {ssub8_b[3], ssub8_b[2], ssub8_b[1], ssub8_b[0]};
            OP_ABS:    y = (a == 32'h8000_0000) ? 32'h7FFF_FFFF : (sa < 0 ? -a : a);
            OP_CLIP8:  y = (sa > 32'sd127) ? 32'd127 : (sa < -32'sd128) ? 32'hFFFF_FF80 : a;
            OP_COPYB:  y = b;
            default:   y = 32'd0;
        endcase
    end

endmodule
