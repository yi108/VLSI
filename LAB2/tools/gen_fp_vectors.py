#!/usr/bin/env python3
"""Generate FPU test vectors (FADD/FSUB/FMIN/FMAX) with golden results.

Per the homework spec, operands are normal numbers or +/-0, and no result
overflows/underflows into inf/subnormal range. Each output line is a 128-bit
hex word: {30'b0, op[1:0], a[31:0], b[31:0], expected[31:0]}.
"""
import random
import struct
import sys


def f2b(f):
    return struct.unpack("<I", struct.pack("<f", f))[0]


def b2f(b):
    return struct.unpack("<f", struct.pack("<I", b & 0xFFFFFFFF))[0]


def fadd_bits(a, b, sub=False):
    if sub:
        b ^= 0x80000000
    r = f2b(b2f(a) + b2f(b))
    if (r & 0x7FFFFFFF) == 0:
        r = 0
    return r


def fkey(x):
    return (~x) & 0xFFFFFFFF if (x >> 31) else (x | 0x80000000)


def rand_fp(rng, lo_exp=64, hi_exp=190):
    # normal number with exponent limited so sums stay in range
    s = rng.getrandbits(1)
    e = rng.randint(lo_exp, hi_exp)
    m = rng.getrandbits(23)
    return (s << 31) | (e << 23) | m


def main():
    out = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
    rng = random.Random(1234)
    vecs = []

    directed = [
        (0x3F800000, 0x3F800000), (0x3F800000, 0xBF800000),
        (0x80000000, 0x00000000), (0x80000000, 0x80000000),
        (0x00000000, 0x00000000), (0x3F800001, 0x33800000),
        (0x3F800000, 0x33800000), (0x4CBEBC20, 0x3F800000),
        (0x3DCCCCCD, 0x3E4CCCCD), (0x42F6E979, 0xC2F6E979),
        (0x4E800000, 0x4E800000), (0x34000001, 0x34000000),
        (0x3F800000, 0xB3800000), (0x40490FDB, 0xC0490FDA),
    ]
    for a, b in directed:
        for op in range(4):
            vecs.append((op, a, b))

    for _ in range(n):
        op = rng.randint(0, 3)
        a = rand_fp(rng)
        # bias towards close exponents to stress cancellation/alignment
        mode = rng.randint(0, 3)
        if mode == 0:
            b = rand_fp(rng)
        elif mode == 1:
            ea = (a >> 23) & 0xFF
            e = min(max(ea + rng.randint(-2, 2), 1), 254)
            b = (rng.getrandbits(1) << 31) | (e << 23) | rng.getrandbits(23)
        elif mode == 2:  # same magnitude, maybe opposite sign (exact zero)
            b = a ^ (rng.getrandbits(1) << 31)
        else:  # zero operand
            b = rng.getrandbits(1) << 31
        if rng.randint(0, 9) == 0:
            a, b = (rng.getrandbits(1) << 31), b
        vecs.append((op, a, b))

    with open(out, "w") as f:
        for op, a, b in vecs:
            if op == 0:
                exp = fadd_bits(a, b)
            elif op == 1:
                exp = fadd_bits(a, b, sub=True)
            elif op == 2:
                exp = a if fkey(a) <= fkey(b) else b
            else:
                exp = b if fkey(a) <= fkey(b) else a
            f.write(f"{op:08x}{a:08x}{b:08x}{exp:08x}\n")
    print(f"{len(vecs)} vectors -> {out}")


if __name__ == "__main__":
    main()
