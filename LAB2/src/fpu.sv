// Single-precision FPU: FADD.S / FSUB.S / FMIN.S / FMAX.S.
// Per the homework spec: inputs never produce NaN/inf/subnormal results and no
// overflow/underflow occurs; rounding is round-to-nearest, ties-to-even; an
// exactly-zero add/sub result returns +0.
module fpu (
    input  logic [1:0]  op,  // 0 FADD, 1 FSUB, 2 FMIN, 3 FMAX
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] y
);

    // ---------------- FADD / FSUB ----------------
    logic [31:0] bs;            // b with sign flipped for FSUB
    logic [30:0] mag_a, mag_b;
    logic        a_is_big;
    logic        sign_big, sign_small;
    logic [7:0]  exp_big, exp_small;
    logic [23:0] man_big, man_small;  // {hidden, frac}
    logic [7:0]  expd;
    logic [26:0] big_ext, small_ext, small_shifted;
    logic        sticky;
    logic [26:0] small_sh_st;
    logic        eff_sub;
    logic [27:0] sum;
    logic [4:0]  lz;
    logic [26:0] norm;
    logic [7:0]  exp_norm;
    logic [23:0] frac24;
    logic        g_bit, tie_lo;
    logic        inc;
    logic [24:0] rounded;
    logic [22:0] man_out;
    logic [7:0]  exp_out;
    logic [31:0] addsub_y;

    always_comb begin
        bs    = (op == 2'd1) ? {~b[31], b[30:0]} : b;
        mag_a = a[30:0];
        mag_b = bs[30:0];
        a_is_big = (mag_a >= mag_b);

        sign_big  = a_is_big ? a[31]  : bs[31];
        sign_small= a_is_big ? bs[31] : a[31];
        exp_big   = a_is_big ? a[30:23]  : bs[30:23];
        exp_small = a_is_big ? bs[30:23] : a[30:23];
        man_big   = a_is_big ? {|a[30:23],  a[22:0]}  : {|bs[30:23], bs[22:0]};
        man_small = a_is_big ? {|bs[30:23], bs[22:0]} : {|a[30:23],  a[22:0]};

        expd      = exp_big - exp_small;
        big_ext   = {man_big, 3'b000};
        small_ext = {man_small, 3'b000};

        if (expd >= 8'd27) begin
            small_shifted = 27'd0;
            sticky        = |man_small;
        end else begin
            small_shifted = small_ext >> expd[4:0];
            sticky        = |(small_ext & ~(27'h7FF_FFFF << expd[4:0]));
        end
        small_sh_st = {small_shifted[26:1], small_shifted[0] | sticky};

        eff_sub = sign_big ^ sign_small;
        sum     = eff_sub ? {1'b0, big_ext} - {1'b0, small_sh_st}
                          : {1'b0, big_ext} + {1'b0, small_sh_st};

        // leading-zero count of sum[26:0]
        lz = 5'd31;
        for (int i = 0; i < 27; i++)
            if (sum[i]) lz = 26 - i;  // last hit = MSB

        if (sum == 28'd0) begin
            addsub_y = 32'h0000_0000;  // exact zero -> +0
        end else begin
            if (sum[27]) begin
                // carry out of addition: shift right one, keep sticky
                norm     = {sum[27:2], sum[1] | sum[0]};
                exp_norm = exp_big + 8'd1;
            end else begin
                // massive cancellation only happens for expd<=1 where the
                // sticky bit is zero, so a plain left shift is exact
                norm     = sum[26:0] << lz;
                exp_norm = exp_big - {3'd0, lz};
            end
            frac24 = norm[26:3];
            g_bit  = norm[2];
            tie_lo = |norm[1:0];
            inc    = g_bit && (tie_lo || frac24[0]);
            rounded = {1'b0, frac24} + {24'd0, inc};
            if (rounded[24]) begin
                man_out = rounded[23:1];
                exp_out = exp_norm + 8'd1;
            end else begin
                man_out = rounded[22:0];
                exp_out = exp_norm;
            end
            addsub_y = {sign_big, exp_out, man_out};
        end
    end

    // ---------------- FMIN / FMAX ----------------
    // Order-preserving key: negative values map below positives, -0 < +0.
    logic [31:0] key_a, key_b;
    logic        a_le_b;
    always_comb begin
        key_a  = a[31] ? ~a : (a | 32'h8000_0000);
        key_b  = b[31] ? ~b : (b | 32'h8000_0000);
        a_le_b = (key_a <= key_b);
    end

    always_comb begin
        unique case (op)
            2'd0, 2'd1: y = addsub_y;
            2'd2:       y = a_le_b ? a : b;  // FMIN
            default:    y = a_le_b ? b : a;  // FMAX
        endcase
    end

endmodule
