#!/usr/bin/env python3
"""Minimal RV32I disassembler, used to check hand-written test programs.

Usage: rvdis.py tb/tb_foo.vhd ...   (disassembles every x"XXXXXXXX" literal
       that appears in a PROG array, printed next to its source comment)
"""
import re
import sys

R = {(0, 0): "add", (0, 0x20): "sub", (1, 0): "sll", (2, 0): "slt", (3, 0): "sltu",
     (4, 0): "xor", (5, 0): "srl", (5, 0x20): "sra", (6, 0): "or", (7, 0): "and"}
I = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}
LD = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
ST = {0: "sb", 1: "sh", 2: "sw"}
BR = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}


def sx(v, bits):
    return v - (1 << bits) if v >> (bits - 1) & 1 else v


def dis(w):
    op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
    rs1, rs2, f7 = (w >> 15) & 31, (w >> 20) & 31, w >> 25
    i_imm = sx(w >> 20, 12)
    if op == 0x33:
        return f"{R.get((f3, f7), '???')} x{rd}, x{rs1}, x{rs2}"
    if op == 0x13:
        if f3 == 1:
            return f"slli x{rd}, x{rs1}, {rs2}"
        if f3 == 5:
            return f"{'srai' if f7 == 0x20 else 'srli'} x{rd}, x{rs1}, {rs2}"
        return f"{I[f3]} x{rd}, x{rs1}, {i_imm}"
    if op == 0x03:
        return f"{LD.get(f3, '???')} x{rd}, {i_imm}(x{rs1})"
    if op == 0x23:
        imm = sx((f7 << 5) | rd, 12)
        return f"{ST.get(f3, '???')} x{rs2}, {imm}(x{rs1})"
    if op == 0x63:
        imm = sx(((w >> 31) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 0x3F) << 5)
                 | (((w >> 8) & 0xF) << 1), 13)
        return f"{BR.get(f3, '???')} x{rs1}, x{rs2}, {imm:+d}"
    if op == 0x37:
        return f"lui x{rd}, 0x{w >> 12:x}"
    if op == 0x17:
        return f"auipc x{rd}, 0x{w >> 12:x}"
    if op == 0x6F:
        imm = sx(((w >> 31) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11)
                 | (((w >> 21) & 0x3FF) << 1), 21)
        return f"jal x{rd}, {imm:+d}"
    if op == 0x67:
        return f"jalr x{rd}, {i_imm}(x{rs1})"
    if op == 0x0F:
        return "fence"
    if op == 0x73:
        return "ecall" if w == 0x73 else "ebreak" if w == 0x100073 else "system?"
    return "???"


for path in sys.argv[1:]:
    print(f"== {path}")
    text = open(path).read()
    m = re.search(r"constant PROG\s*:[^(]*\((.*?)\n\s*\);", text, re.S)
    if not m:
        print("   (no PROG array)")
        continue
    idx = 0
    for line in m.group(1).splitlines():
        h = re.search(r'x"([0-9A-Fa-f]{8})"', line)
        if h:
            c = line.split("--", 1)[1].strip() if "--" in line else ""
            print(f"  [{idx:2}] {h.group(1)}  {dis(int(h.group(1), 16)):28} | {c}")
            idx += 1
