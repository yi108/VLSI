#!/usr/bin/env python3
"""Tiny RISC-V assembler for VSD HW2 (RV32I + M + B-subset + F-subset + DSP + CSR).

Supports exactly the 68 instructions of the homework, labels, and the
directives .word / .float / .org (instruction section only).

Usage: asm.py prog.s prog.hex
"""
import re
import struct
import sys

REGS = {f"x{i}": i for i in range(32)}
ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21,
    "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}
REGS.update(ABI)
FREGS = {f"f{i}": i for i in range(32)}
FABI = {}
for i in range(8):
    FABI[f"ft{i}"] = i
FABI.update({"fs0": 8, "fs1": 9})
for i in range(8):
    FABI[f"fa{i}"] = 10 + i
for i in range(10):
    FABI[f"fs{i+2}"] = 18 + i
for i in range(4):
    FABI[f"ft{i+8}"] = 28 + i
FREGS.update(FABI)


def xreg(s):
    return REGS[s.strip()]


def freg(s):
    return FREGS[s.strip()]


def parse_imm(s, labels, pc=None):
    s = s.strip()
    if s in labels:
        return labels[s]
    if s.startswith("%hi(") and s.endswith(")"):
        v = parse_imm(s[4:-1], labels)
        return ((v + 0x800) >> 12) & 0xFFFFF
    if s.startswith("%lo(") and s.endswith(")"):
        v = parse_imm(s[4:-1], labels)
        lo = v & 0xFFF
        return lo - 0x1000 if lo >= 0x800 else lo
    return int(s, 0)


def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(imm, rs2, rs1, f3):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | \
        (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0b1100011


def enc_u(imm, rd, op):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | op


def enc_j(imm, rd):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | \
        (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0b1101111


R_OPS = {
    "add": (0b0000000, 0b000), "sub": (0b0100000, 0b000), "sll": (0b0000000, 0b001),
    "slt": (0b0000000, 0b010), "sltu": (0b0000000, 0b011), "xor": (0b0000000, 0b100),
    "srl": (0b0000000, 0b101), "sra": (0b0100000, 0b101), "or": (0b0000000, 0b110),
    "and": (0b0000000, 0b111),
    "mul": (0b0000001, 0b000), "mulh": (0b0000001, 0b001),
    "mulhsu": (0b0000001, 0b010), "mulhu": (0b0000001, 0b011),
    "rol": (0b0110000, 0b001), "ror": (0b0110000, 0b101),
    "min": (0b0000101, 0b100), "max": (0b0000101, 0b110),
    "minu": (0b0000101, 0b101), "maxu": (0b0000101, 0b111),
    "bset": (0b0010100, 0b001), "bclr": (0b0100100, 0b001), "bext": (0b0100100, 0b101),
}
I_OPS = {
    "addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100,
    "ori": 0b110, "andi": 0b111,
}
LOADS = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORES = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCHES = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101,
            "bltu": 0b110, "bgeu": 0b111}
UNARY_B = {"clz": 0b00000, "ctz": 0b00001, "cpop": 0b00010}
CSRS = {"rdcycle": 0xC00, "rdcycleh": 0xC80, "rdinstret": 0xC02, "rdinstreth": 0xC82}
DSP = {"dotp4": 0b000, "sadd8": 0b001, "ssub8": 0b010, "abs": 0b011, "clip8": 0b100}


def assemble(lines):
    # pass 1: labels
    labels = {}
    insts = []  # (pc, mnemonic, args, line_no)
    pc = 0
    for ln, raw in enumerate(lines, 1):
        line = raw.split("#")[0].strip()
        if not line:
            continue
        while ":" in line:
            lbl, line = line.split(":", 1)
            labels[lbl.strip()] = pc
            line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mn = parts[0].lower()
        args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
        if mn == ".org":
            pc = int(args[0], 0)
            insts.append((pc, mn, args, ln))
            continue
        insts.append((pc, mn, args, ln))
        pc += 4

    out = {}

    def emit(addr, word):
        out[addr] = word & 0xFFFFFFFF

    for pc, mn, args, ln in insts:
        try:
            if mn == ".org":
                continue
            if mn == ".word":
                emit(pc, int(args[0], 0))
                continue
            if mn == ".float":
                emit(pc, struct.unpack("<I", struct.pack("<f", float(args[0])))[0])
                continue
            if mn in R_OPS:
                f7, f3 = R_OPS[mn]
                emit(pc, enc_r(f7, xreg(args[2]), xreg(args[1]), f3, xreg(args[0]), 0b0110011))
            elif mn in I_OPS:
                emit(pc, enc_i(parse_imm(args[2], labels), xreg(args[1]), I_OPS[mn], xreg(args[0]), 0b0010011))
            elif mn in ("slli", "srli", "srai"):
                sh = parse_imm(args[2], labels) & 0x1F
                f7 = 0b0100000 if mn == "srai" else 0
                f3 = 0b001 if mn == "slli" else 0b101
                emit(pc, enc_r(f7, sh, xreg(args[1]), f3, xreg(args[0]), 0b0010011))
            elif mn in UNARY_B:
                emit(pc, enc_r(0b0110000, UNARY_B[mn], xreg(args[1]), 0b001, xreg(args[0]), 0b0010011))
            elif mn in LOADS:
                m = re.match(r"(-?\w+)\((\w+)\)", args[1])
                emit(pc, enc_i(parse_imm(m.group(1), labels), xreg(m.group(2)), LOADS[mn], xreg(args[0]), 0b0000011))
            elif mn in STORES:
                m = re.match(r"(-?\w+)\((\w+)\)", args[1])
                emit(pc, enc_s(parse_imm(m.group(1), labels), xreg(args[0]), xreg(m.group(2)), STORES[mn], 0b0100011))
            elif mn in BRANCHES:
                off = parse_imm(args[2], labels) - pc
                emit(pc, enc_b(off, xreg(args[1]), xreg(args[0]), BRANCHES[mn]))
            elif mn == "jal":
                if len(args) == 1:
                    args = ["ra", args[0]]
                off = parse_imm(args[1], labels) - pc
                emit(pc, enc_j(off, xreg(args[0])))
            elif mn == "j":
                off = parse_imm(args[0], labels) - pc
                emit(pc, enc_j(off, 0))
            elif mn == "jalr":
                if len(args) == 1:
                    emit(pc, enc_i(0, xreg(args[0]), 0, 1, 0b1100111))
                else:
                    m = re.match(r"(-?\w+)\((\w+)\)", args[1])
                    if m:
                        emit(pc, enc_i(parse_imm(m.group(1), labels), xreg(m.group(2)), 0, xreg(args[0]), 0b1100111))
                    else:
                        emit(pc, enc_i(parse_imm(args[2], labels), xreg(args[1]), 0, xreg(args[0]), 0b1100111))
            elif mn == "lui":
                emit(pc, enc_u(parse_imm(args[1], labels), xreg(args[0]), 0b0110111))
            elif mn == "auipc":
                emit(pc, enc_u(parse_imm(args[1], labels), xreg(args[0]), 0b0010111))
            elif mn in CSRS:
                emit(pc, enc_i(CSRS[mn], 0, 0b010, xreg(args[0]), 0b1110011))
            elif mn == "flw":
                m = re.match(r"(-?\w+)\((\w+)\)", args[1])
                emit(pc, enc_i(parse_imm(m.group(1), labels), xreg(m.group(2)), 0b010, freg(args[0]), 0b0000111))
            elif mn == "fsw":
                m = re.match(r"(-?\w+)\((\w+)\)", args[1])
                emit(pc, enc_s(parse_imm(m.group(1), labels), freg(args[0]), xreg(m.group(2)), 0b010, 0b0100111))
            elif mn == "fadd.s":
                emit(pc, enc_r(0b0000000, freg(args[2]), freg(args[1]), 0b111, freg(args[0]), 0b1010011))
            elif mn == "fsub.s":
                emit(pc, enc_r(0b0000100, freg(args[2]), freg(args[1]), 0b111, freg(args[0]), 0b1010011))
            elif mn == "fmin.s":
                emit(pc, enc_r(0b0010100, freg(args[2]), freg(args[1]), 0b000, freg(args[0]), 0b1010011))
            elif mn == "fmax.s":
                emit(pc, enc_r(0b0010100, freg(args[2]), freg(args[1]), 0b001, freg(args[0]), 0b1010011))
            elif mn in DSP:
                rs2 = xreg(args[2]) if len(args) > 2 else 0
                emit(pc, enc_r(0b0000000, rs2, xreg(args[1]), DSP[mn], xreg(args[0]), 0b0001011))
            elif mn == "nop":
                emit(pc, enc_i(0, 0, 0, 0, 0b0010011))
            elif mn == "li":  # pseudo: lui+addi or addi
                v = parse_imm(args[1], labels) & 0xFFFFFFFF
                sv = v - 0x100000000 if v >= 0x80000000 else v
                if -2048 <= sv < 2048:
                    emit(pc, enc_i(sv, 0, 0, xreg(args[0]), 0b0010011))
                else:
                    raise ValueError("li out of addi range; use lui/addi explicitly")
            elif mn == "mv":
                emit(pc, enc_i(0, xreg(args[1]), 0, xreg(args[0]), 0b0010011))
            else:
                raise ValueError(f"unknown mnemonic '{mn}'")
        except Exception as e:
            raise SystemExit(f"line {ln}: {e}")
    return out, labels


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src) as f:
        out, _ = assemble(f.readlines())
    top = max(out) if out else 0
    with open(dst, "w") as f:
        for a in range(0, top + 4, 4):
            f.write(f"{out.get(a, 0):08x}\n")


if __name__ == "__main__":
    main()
