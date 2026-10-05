# prog1: floating-point sort + accumulation.
# Sorts 16 fp32 values at DM[0x100..0x13C] ascending into DM[0x200..0x23C]
# (insertion sort; floats compared through the order-preserving int key),
# then accumulates the sorted array with FADD.S and stores partial sums.
# Exercises tight loops, taken/not-taken branches, load-use hazards and the
# FP pipeline in a realistic program.

start:
    addi  x5, x0, 0x100       # src base
    addi  x6, x0, 0x200       # dst base
    addi  x7, x0, 16          # N

    # copy src -> dst
    addi  x10, x0, 0          # i
copy_loop:
    slli  x11, x10, 2
    add   x12, x5, x11
    lw    x13, 0(x12)
    add   x14, x6, x11
    sw    x13, 0(x14)
    addi  x10, x10, 1
    blt   x10, x7, copy_loop

    # insertion sort on dst, comparing int keys of fp32 values
    addi  x10, x0, 1          # i = 1
outer:
    bge   x10, x7, sort_done
    slli  x11, x10, 2
    add   x12, x6, x11
    lw    x22, 0(x12)         # v = dst[i] (fp bits)
    add   x13, x22, x0
    jal   x15, make_key
    add   x17, x16, x0        # kv = key(v)
    add   x18, x10, x0        # j = i
inner:
    beq   x18, x0, insert
    addi  x19, x18, -1
    slli  x11, x19, 2
    add   x12, x6, x11
    lw    x13, 0(x12)         # dst[j-1]
    add   x20, x13, x0        # save bits
    jal   x15, make_key       # x16 = key(dst[j-1])
    bgeu  x17, x16, insert    # kv >= key -> position found (unsigned keys)
    slli  x11, x18, 2
    add   x14, x6, x11
    sw    x20, 0(x14)         # dst[j] = dst[j-1]
    add   x18, x19, x0
    j     inner
insert:
    slli  x11, x18, 2
    add   x12, x6, x11
    sw    x22, 0(x12)         # dst[j] = v
    addi  x10, x10, 1
    j     outer

    # x16 = order-preserving integer key of fp bits in x13 (clobbers x14)
make_key:
    srai  x14, x13, 31        # all ones if negative
    beq   x14, x0, pos_key
    xori  x16, x13, -1        # ~x
    jalr  x0, x15, 0
pos_key:
    lui   x14, 0x80000
    or    x16, x13, x14       # x | 0x80000000
    jalr  x0, x15, 0

sort_done:
    # accumulate sorted array with FADD.S, store running sums at 0x240+
    addi  x10, x0, 0
    addi  x24, x0, 0x240
    flw   f1, 0(x6)           # acc = dst[0]
    fsw   f1, 0(x24)
    addi  x10, x0, 1
acc_loop:
    bge   x10, x7, acc_done
    slli  x11, x10, 2
    add   x12, x6, x11
    flw   f2, 0(x12)
    fadd.s f1, f1, f2         # load-use on f2 + FP RAW on f1
    add   x14, x24, x11
    fsw   f1, 0(x14)
    addi  x10, x10, 1
    j     acc_loop
acc_done:

    # fmin/fmax scan over the source array
    flw   f3, 0(x5)
    flw   f4, 0(x5)
    addi  x10, x0, 1
mm_loop:
    bge   x10, x7, mm_done
    slli  x11, x10, 2
    add   x12, x5, x11
    flw   f5, 0(x12)
    fmin.s f3, f3, f5
    fmax.s f4, f4, f5
    addi  x10, x10, 1
    j     mm_loop
mm_done:
    addi  x25, x0, 0x280
    fsw   f3, 0(x25)
    fsw   f4, 4(x25)
    fsub.s f6, f4, f3
    fsw   f6, 8(x25)

halt:
    jal   x0, halt
