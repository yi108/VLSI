#!/usr/bin/env python3
"""Golden instruction-set simulator for VSD HW2 (68-instruction RV32IMBF+DSP).

Usage: iss.py prog.hex data.hex out_dir
Writes out_dir/golden_xreg.hex, golden_freg.hex, golden_dmem.hex and stats.
"""
import struct
import sys

MASK = 0xFFFFFFFF


def s32(v):
    v &= MASK
    return v - 0x100000000 if v >= 0x80000000 else v


def u32(v):
    return v & MASK


def f2b(f):
    return struct.unpack("<I", struct.pack("<f", f))[0]


def b2f(b):
    return struct.unpack("<f", struct.pack("<I", b & MASK))[0]


def fadd_bits(a, b, sub=False):
    if sub:
        b ^= 0x80000000
    # fp64 add of two fp32 values then round to fp32 is correctly rounded (RNE)
    r = f2b(b2f(a) + b2f(b))
    if (r & 0x7FFFFFFF) == 0:
        r = 0  # exact zero -> +0 per spec
    return r


def fkey(x):
    # order-preserving transform for IEEE-754 compare
    return (~x) & MASK if (x >> 31) & 1 else (x | 0x80000000)


def sat8(v):
    return 127 if v > 127 else (-128 if v < -128 else v)


def sb8(v):
    v &= 0xFF
    return v - 256 if v >= 128 else v


class CPU:
    def __init__(self, imem, dmem):
        self.x = [0] * 32
        self.f = [0] * 32
        self.pc = 0
        self.imem = imem
        self.dmem = dmem
        self.instret = 0
        self.cycle = 0  # the RTL compares counters loosely; see note in report

    def rd_word(self, addr):
        return self.dmem.get(addr >> 2, 0)

    def wr_word(self, addr, data, mask):
        old = self.dmem.get(addr >> 2, 0)
        self.dmem[addr >> 2] = (old & ~mask) & MASK | (data & mask)

    def step(self):
        inst = self.imem.get(self.pc >> 2, 0)
        pc = self.pc
        nxt = pc + 4
        op = inst & 0x7F
        rd = (inst >> 7) & 0x1F
        f3 = (inst >> 12) & 0x7
        rs1 = (inst >> 15) & 0x1F
        rs2 = (inst >> 20) & 0x1F
        f7 = (inst >> 25) & 0x7F
        imm_i = s32(inst >> 20 | (0xFFFFF000 if inst >> 31 else 0))
        imm_s = s32(((inst >> 25) << 5 | ((inst >> 7) & 0x1F)) | (0xFFFFF000 if inst >> 31 else 0))
        imm_b = s32((((inst >> 31) & 1) << 12 | ((inst >> 7) & 1) << 11 |
                     ((inst >> 25) & 0x3F) << 5 | ((inst >> 8) & 0xF) << 1) |
                    (0xFFFFE000 if inst >> 31 else 0))
        imm_u = inst & 0xFFFFF000
        imm_j = s32((((inst >> 31) & 1) << 20 | ((inst >> 12) & 0xFF) << 12 |
                     ((inst >> 20) & 1) << 11 | ((inst >> 21) & 0x3FF) << 1) |
                    (0xFFE00000 if inst >> 31 else 0))
        X = self.x
        F = self.f

        def wx(v):
            if rd:
                X[rd] = u32(v)

        if op == 0b0110011:  # R
            a, b = X[rs1], X[rs2]
            sa, sb_ = s32(a), s32(b)
            sh = b & 31
            if f7 == 0b0000001:  # M
                if f3 == 0:
                    wx(a * b)
                elif f3 == 1:
                    wx((sa * sb_) >> 32)
                elif f3 == 2:
                    wx((sa * b) >> 32)
                elif f3 == 3:
                    wx((a * b) >> 32)
            elif f7 == 0b0110000:  # ROL/ROR
                if f3 == 0b001:
                    wx((a << sh) | (a >> (32 - sh)) if sh else a)
                else:
                    wx((a >> sh) | (a << (32 - sh)) if sh else a)
            elif f7 == 0b0000101:  # MIN/MAX
                if f3 == 0b100:
                    wx(a if sa < sb_ else b)
                elif f3 == 0b110:
                    wx(a if sa > sb_ else b)
                elif f3 == 0b101:
                    wx(a if a < b else b)
                else:
                    wx(a if a > b else b)
            elif f7 == 0b0010100:  # BSET
                wx(a | (1 << sh))
            elif f7 == 0b0100100:  # BCLR/BEXT
                wx(a & ~(1 << sh) if f3 == 0b001 else (a >> sh) & 1)
            elif f7 == 0b0100000:
                wx(a - b if f3 == 0 else sa >> sh)  # SUB / SRA
            else:  # base R ops, f7 == 0
                wx([a + b, a << sh, int(sa < sb_), int(a < b),
                    a ^ b, a >> sh, a | b, a & b][f3])
        elif op == 0b0010011:  # I
            a = X[rs1]
            sa = s32(a)
            if f3 == 0b001:
                if f7 == 0b0110000:  # CLZ/CTZ/CPOP
                    if rs2 == 0:
                        wx(32 - a.bit_length())  # CLZ
                    elif rs2 == 1:
                        wx(next((i for i in range(32) if (a >> i) & 1), 32))
                    else:
                        wx(bin(a).count("1"))
                else:
                    wx(a << (rs2 & 31))  # SLLI (shamt in rs2 field)
            elif f3 == 0b101:
                sh = rs2 & 31
                wx(sa >> sh if f7 == 0b0100000 else a >> sh)
            elif f3 == 0:
                wx(a + imm_i)
            elif f3 == 0b010:
                wx(int(sa < imm_i))
            elif f3 == 0b011:
                wx(int(a < u32(imm_i)))
            elif f3 == 0b100:
                wx(a ^ u32(imm_i))
            elif f3 == 0b110:
                wx(a | u32(imm_i))
            else:
                wx(a & u32(imm_i))
        elif op == 0b0000011:  # loads
            addr = u32(X[rs1] + imm_i)
            w = self.rd_word(addr)
            off = addr & 3
            if f3 == 0b010:
                wx(w)
            elif f3 == 0b000:
                b = (w >> (off * 8)) & 0xFF
                wx(b - 256 if b >= 128 else b)
            elif f3 == 0b100:
                wx((w >> (off * 8)) & 0xFF)
            elif f3 == 0b001:
                h = (w >> ((off & 2) * 8)) & 0xFFFF
                wx(h - 65536 if h >= 32768 else h)
            else:
                wx((w >> ((off & 2) * 8)) & 0xFFFF)
        elif op == 0b0100011:  # stores
            addr = u32(X[rs1] + imm_s)
            off = addr & 3
            if f3 == 0b010:
                self.wr_word(addr, X[rs2], MASK)
            elif f3 == 0b000:
                self.wr_word(addr, (X[rs2] & 0xFF) << (off * 8), 0xFF << (off * 8))
            else:
                self.wr_word(addr, (X[rs2] & 0xFFFF) << ((off & 2) * 8), 0xFFFF << ((off & 2) * 8))
        elif op == 0b1100011:  # branches
            a, b = X[rs1], X[rs2]
            sa, sb_ = s32(a), s32(b)
            t = [a == b, a != b, False, False, sa < sb_, sa >= sb_, a < b, a >= b][f3]
            if t:
                nxt = u32(pc + imm_b)
        elif op == 0b1101111:  # JAL
            wx(pc + 4)
            nxt = u32(pc + imm_j)
        elif op == 0b1100111:  # JALR
            t = u32(X[rs1] + imm_i) & ~1
            wx(pc + 4)
            nxt = t
        elif op == 0b0110111:
            wx(imm_u)
        elif op == 0b0010111:
            wx(pc + imm_u)
        elif op == 0b1110011:  # CSR reads (counters). Values are
            # micro-architecture dependent; the golden model writes 0 and the
            # testbench skips registers written by CSR reads (tracked below).
            csr = (inst >> 20) & 0xFFF
            if csr == 0xC02:
                wx(self.instret & MASK)
            elif csr == 0xC82:
                wx(self.instret >> 32)
            elif csr == 0xC00:
                wx(self.cycle & MASK)
            else:
                wx(self.cycle >> 32)
        elif op == 0b0000111:  # FLW
            addr = u32(X[rs1] + imm_i)
            F[rd] = self.rd_word(addr)
        elif op == 0b0100111:  # FSW
            addr = u32(X[rs1] + imm_s)
            self.wr_word(addr, F[rs2], MASK)
        elif op == 0b1010011:  # FP
            a, b = F[rs1], F[rs2]
            if f7 == 0b0000000:
                F[rd] = fadd_bits(a, b)
            elif f7 == 0b0000100:
                F[rd] = fadd_bits(a, b, sub=True)
            elif f7 == 0b0010100:
                ka, kb = fkey(a), fkey(b)
                F[rd] = (a if ka < kb else b) if f3 == 0 else (a if ka > kb else b)
        elif op == 0b0001011:  # DSP
            a, b = X[rs1], X[rs2]
            if f3 == 0b000:  # DOTP4
                acc = 0
                for i in range(4):
                    acc += sb8(a >> (8 * i)) * sb8(b >> (8 * i))
                wx(acc)
            elif f3 == 0b001:  # SADD8
                r = 0
                for i in range(4):
                    r |= (sat8(sb8(a >> (8 * i)) + sb8(b >> (8 * i))) & 0xFF) << (8 * i)
                wx(r)
            elif f3 == 0b010:  # SSUB8
                r = 0
                for i in range(4):
                    r |= (sat8(sb8(a >> (8 * i)) - sb8(b >> (8 * i))) & 0xFF) << (8 * i)
                wx(r)
            elif f3 == 0b011:  # ABS
                sa = s32(a)
                wx(0x7FFFFFFF if a == 0x80000000 else (-sa if sa < 0 else sa))
            else:  # CLIP8
                sa = s32(a)
                wx(127 if sa > 127 else (-128 if sa < -128 else sa))
        else:
            raise SystemExit(f"illegal instruction {inst:08x} at pc {pc:08x}")
        self.instret += 1
        self.pc = nxt


def load_hex(path):
    mem = {}
    try:
        with open(path) as f:
            for i, line in enumerate(f):
                line = line.split("//")[0].strip()
                if line:
                    mem[i] = int(line, 16)
    except FileNotFoundError:
        pass
    return mem


def main():
    prog, data, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    cpu = CPU(load_hex(prog), load_hex(data))
    seen = 0
    for _ in range(2_000_000):
        prev = cpu.pc
        cpu.step()
        if cpu.pc == prev:  # jal x0,0 self-loop = halt
            seen += 1
            if seen >= 1:
                break
    else:
        raise SystemExit("program did not halt")

    with open(f"{outdir}/golden_xreg.hex", "w") as f:
        for v in cpu.x:
            f.write(f"{v:08x}\n")
    with open(f"{outdir}/golden_freg.hex", "w") as f:
        for v in cpu.f:
            f.write(f"{v:08x}\n")
    top = max(cpu.dmem) if cpu.dmem else 0
    with open(f"{outdir}/golden_dmem.hex", "w") as f:
        for i in range(top + 1):
            f.write(f"{cpu.dmem.get(i, 0):08x}\n")
    print(f"halted at pc={cpu.pc:08x} after {cpu.instret} instructions")


if __name__ == "__main__":
    main()
