# prog0: exercises all 68 instructions of the VSD HW2 ISA, including
# forwarding chains, load-use hazards, taken/not-taken branches and
# FP corner cases. Results are left in registers and stored to DM at 0x200+.

start:
    # ---------- U-type / I-type basics (with back-to-back deps) ----------
    lui   x1, 0x12345           # x1 = 0x12345000
    addi  x1, x1, 0x678         # x1 = 0x12345678 (forward)
    auipc x2, 0x1               # x2 = pc + 0x1000
    addi  x3, x0, -100
    addi  x4, x0, 77
    add   x5, x1, x3
    sub   x6, x5, x4            # back-to-back forward
    sll   x7, x6, x4            # shamt = 77 & 31 = 13
    slt   x8, x3, x4            # 1 (signed)
    sltu  x9, x3, x4            # 0 (unsigned: big vs 77)
    xor   x10, x1, x3
    srl   x11, x10, x4
    sra   x12, x3, x4
    or    x13, x1, x4
    and   x14, x1, x3
    slti  x15, x3, -99          # 1
    sltiu x16, x3, -99          # 1 (unsigned compare)
    xori  x17, x1, -1
    ori   x18, x3, 0x0F0
    andi  x19, x1, 0x7F0
    slli  x20, x1, 9
    srli  x21, x1, 9
    srai  x22, x3, 3

    # ---------- M extension (corner values) ----------
    lui   x23, 0x80000          # x23 = 0x80000000
    addi  x24, x0, -1
    mul   x25, x23, x24
    mulh  x26, x23, x24
    mulhsu x27, x24, x24        # (-1) s * 0xFFFFFFFF u
    mulhu x28, x24, x24
    mul   x29, x4, x3

    # ---------- store M results ----------
    addi  x30, x0, 0x200
    sw    x25, 0(x30)
    sw    x26, 4(x30)
    sw    x27, 8(x30)
    sw    x28, 12(x30)

    # ---------- B subset ----------
    clz   x25, x4               # 77 -> 25
    ctz   x26, x20
    cpop  x27, x1
    addi  x28, x0, 4
    rol   x29, x1, x28
    ror   x31, x1, x28
    rol   x5, x1, x0            # rotate by 0
    min   x6, x3, x4
    max   x7, x3, x4
    minu  x8, x3, x4
    maxu  x9, x3, x4
    bset  x10, x4, x28
    bclr  x11, x4, x28
    bext  x12, x4, x28
    sw    x29, 16(x30)
    sw    x31, 20(x30)

    # ---------- DSP ----------
    lui   x13, 0x7F80F          # x13 = 0x7F80F000
    addi  x13, x13, 0x7F1       # 0x7F80F7F1... build SIMD operands
    lui   x14, 0x01810
    addi  x14, x14, 0x102       # 0x01810102
    dotp4 x15, x13, x14
    sadd8 x16, x13, x14
    ssub8 x17, x13, x14
    abs   x18, x23              # abs(0x80000000) = 0x7FFFFFFF
    abs   x19, x3               # abs(-100)
    addi  x20, x0, 200
    clip8 x21, x20              # 127
    addi  x20, x0, -200
    clip8 x22, x20              # -128
    clip8 x25, x4               # 77 (in range)
    sw    x15, 24(x30)
    sw    x16, 28(x30)
    sw    x17, 32(x30)

    # ---------- loads/stores, all sizes, load-use hazards ----------
    sw    x1, 36(x30)
    lw    x26, 36(x30)
    add   x27, x26, x4          # load-use hazard (1 bubble)
    sb    x3, 41(x30)           # byte offset 1
    sb    x1, 42(x30)           # byte offset 2
    sh    x3, 46(x30)           # half offset 2
    lb    x28, 41(x30)
    lbu   x29, 41(x30)
    lh    x31, 46(x30)
    lhu   x5, 46(x30)
    lb    x6, 42(x30)
    lw    x7, 40(x30)
    lhu   x8, 40(x30)

    # ---------- branches ----------
    beq   x4, x4, L1            # taken
    addi  x9, x0, 0x111         # skipped
L1: bne   x4, x4, L2            # not taken
    addi  x9, x0, 0x222         # executed
L2: blt   x3, x4, L3            # taken (signed)
    addi  x10, x0, 0x333        # skipped
L3: bge   x3, x4, L4            # not taken
    addi  x10, x0, 0x444        # executed
L4: bltu  x3, x4, L5            # not taken (0xFF..9C > 77)
    addi  x11, x0, 0x555        # executed
L5: bgeu  x3, x4, L6            # taken
    addi  x11, x0, 0x666        # skipped
L6: blt   x4, x3, L7            # not taken
    addi  x12, x0, 0x777        # executed
L7: bgeu  x4, x3, L8            # not taken
    addi  x13, x0, 0x888        # executed
L8: beq   x4, x3, L9            # not taken
    addi  x14, x0, 0x999        # executed
L9: bne   x3, x4, L10           # taken
    addi  x15, x0, 0xAA         # skipped
L10:

    # ---------- jal / jalr ----------
    jal   x1, func              # call
    addi  x16, x16, 1           # executed after return
    jal   x17, L11              # plain jump, link in x17
    addi  x16, x16, 64          # skipped
L11:
    auipc x18, 0
    addi  x18, x18, 17          # odd target: base+17 -> jalr clears LSB
    jalr  x19, x18, 0           # jumps to (auipc+17)&~1 = auipc+16
    addi  x16, x16, 128         # skipped (jalr lands after this)
    addi  x16, x16, 2           # landing point
    j     L12
func:
    addi  x16, x0, 100
    jalr  x0, x1, 0             # return
L12:

    # ---------- CSR counters (values are overwritten before compare) ----------
    rdcycle    x20
    rdcycleh   x21
    rdinstret  x22
    rdinstreth x23
    sltu  x24, x20, x22         # consume them
    addi  x20, x0, 11
    addi  x21, x0, 12
    addi  x22, x0, 13
    addi  x23, x0, 14
    addi  x24, x0, 15

    # ---------- F extension ----------
    addi  x28, x0, 0x100        # float data pool
    flw   f1, 0(x28)            # 1.0
    flw   f2, 4(x28)            # 2.5
    fadd.s f3, f1, f2           # 3.5 (back-to-back FP forward)
    fsub.s f4, f3, f2           # 1.0
    fsub.s f5, f1, f1           # exact zero -> +0
    fmin.s f6, f2, f4
    fmax.s f7, f2, f4
    flw   f8, 8(x28)            # -2.5
    fmin.s f9, f8, f2
    fmax.s f10, f8, f2
    flw   f11, 12(x28)          # 1.0 + 1ulp
    fadd.s f12, f1, f11
    flw   f13, 16(x28)          # 2^-24 -> tie rounding
    fadd.s f14, f1, f13         # 1.0 (ties-to-even)
    fadd.s f15, f11, f13        # rounds up
    flw   f16, 20(x28)          # 1e8
    fadd.s f17, f16, f1         # big + small
    fsub.s f18, f16, f1
    flw   f19, 24(x28)          # 0.1
    flw   f20, 28(x28)          # 0.2
    fadd.s f21, f19, f20        # 0.3 (rounded)
    fsub.s f22, f19, f20        # -0.1
    flw   f0, 32(x28)           # 5.75 (f0 is NOT hardwired to zero)
    fadd.s f23, f0, f1          # 6.75
    fsub.s f24, f20, f19        # 0.1 (cancellation)
    fmin.s f25, f5, f22
    fmax.s f26, f5, f22
    flw   f27, 36(x28)          # -0.0
    fmin.s f28, f27, f5         # min(-0,+0) = -0
    fmax.s f29, f27, f5         # max(-0,+0) = +0
    fadd.s f30, f27, f27        # -0 + -0 -> +0 per spec
    fsub.s f31, f8, f8          # +0

    # FP load-use + FSW store-data forwarding
    flw   f1, 40(x28)           # 1234.5678
    fsw   f1, 64(x28)           # immediately store it back (hazard)
    fadd.s f2, f1, f1
    fsw   f2, 68(x28)
    fsw   f3, 72(x28)
    fsw   f5, 76(x28)
    fsw   f21, 80(x28)

    # ---------- store a few more results ----------
    sw    x9,  48(x30)
    sw    x10, 52(x30)
    sw    x11, 56(x30)
    sw    x12, 60(x30)
    sw    x13, 64(x30)
    sw    x14, 68(x30)
    sw    x16, 72(x30)
    sw    x27, 76(x30)

halt:
    jal   x0, halt              # self-loop: testbench detects 0x0000006F
