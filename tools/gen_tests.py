#!/usr/bin/env python3
"""Generate the pipeline-level testbenches in tb/.

Each test is written as RV32I assembly. This script
  1. assembles it (no hand-encoded hex),
  2. runs it on a small instruction-set simulator (the golden model),
  3. checks the simulator agrees with the values written in the test below,
  4. writes tb/<name>.vhd, which runs the program on pipeline_top and
     compares the register file against those values.

Usage: python3 tools/gen_tests.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASK = 0xFFFFFFFF

# ----------------------------------------------------------------------------
# Assembler
# ----------------------------------------------------------------------------
R_OPS = {"add": (0, 0), "sub": (0, 0x20), "sll": (1, 0), "slt": (2, 0),
         "sltu": (3, 0), "xor": (4, 0), "srl": (5, 0), "sra": (5, 0x20),
         "or": (6, 0), "and": (7, 0)}
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SH_OPS = {"slli": (1, 0), "srli": (5, 0), "srai": (5, 0x20)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}


def reg(tok):
    m = re.fullmatch(r"x(\d+)", tok)
    if not m or int(m.group(1)) > 31:
        raise ValueError(f"bad register {tok!r}")
    return int(m.group(1))


def num(tok):
    return int(tok, 0)


def check_range(v, bits, what):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= v <= hi:
        raise ValueError(f"{what} {v} does not fit in {bits} signed bits")


def enc_i(imm, rs1, f3, rd, op):
    check_range(imm, 12, "I-immediate")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3):
    check_range(imm, 12, "S-immediate")
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | 0x23


def enc_b(off, rs2, rs1, f3):
    check_range(off, 13, "branch offset")
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63


def enc_j(off, rd):
    check_range(off, 21, "jump offset")
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) \
        | (((o >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def parse_mem(tok):
    m = re.fullmatch(r"(-?\w+)\((x\d+)\)", tok)
    if not m:
        raise ValueError(f"bad memory operand {tok!r}")
    return num(m.group(1)), reg(m.group(2))


def assemble(lines):
    """lines: list of 'asm  # comment'. Returns [(addr, word, asm, comment)]."""
    # Pass 1: labels and addresses
    items, labels, addr = [], {}, 0
    for raw in lines:
        asm, _, comment = raw.partition("#")
        asm, comment = asm.strip(), comment.strip()
        while ":" in asm:
            label, _, asm = asm.partition(":")
            labels[label.strip()] = addr
            asm = asm.strip()
        if not asm:
            continue
        if asm.startswith(".org"):
            target = num(asm.split()[1])
            while addr < target:
                items.append((addr, "nop", "padding"))
                addr += 4
            continue
        items.append((addr, asm, comment))
        addr += 4

    def target(tok, pc):
        return labels[tok] - pc if tok in labels else num(tok)

    # Pass 2: encode
    out = []
    for pc, asm, comment in items:
        mn, _, rest = asm.partition(" ")
        a = [t.strip() for t in rest.split(",")] if rest else []
        if mn == "nop":
            w = 0x13
        elif mn in R_OPS:
            f3, f7 = R_OPS[mn]
            w = (f7 << 25) | (reg(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x33
        elif mn in I_OPS:
            w = enc_i(num(a[2]), reg(a[1]), I_OPS[mn], reg(a[0]), 0x13)
        elif mn in SH_OPS:
            f3, f7 = SH_OPS[mn]
            w = (f7 << 25) | (num(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x13
        elif mn in LOADS:
            off, rs1 = parse_mem(a[1])
            w = enc_i(off, rs1, LOADS[mn], reg(a[0]), 0x03)
        elif mn in STORES:
            off, rs1 = parse_mem(a[1])
            w = enc_s(off, reg(a[0]), rs1, STORES[mn])
        elif mn in BRANCHES:
            w = enc_b(target(a[2], pc), reg(a[1]), reg(a[0]), BRANCHES[mn])
        elif mn == "jal":
            w = enc_j(target(a[1], pc), reg(a[0]))
        elif mn == "jalr":
            off, rs1 = parse_mem(a[1])
            w = enc_i(off, rs1, 0, reg(a[0]), 0x67)
        elif mn in ("lui", "auipc"):
            w = ((num(a[1]) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | (0x37 if mn == "lui" else 0x17)
        elif mn == "fence":
            w = 0x0FF0000F
        elif mn == "ecall":
            w = 0x00000073
        elif mn == "ebreak":
            w = 0x00100073
        else:
            raise ValueError(f"unknown instruction {asm!r}")
        out.append((pc, w, asm, comment))
    return out


# ----------------------------------------------------------------------------
# Instruction-set simulator (golden model)
# ----------------------------------------------------------------------------
def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def simulate(prog, max_steps=10000):
    """Run until the 'halt' self-loop. Returns (regs, steps)."""
    imem = {pc: w for pc, w, _, _ in prog}
    x, mem, pc = [0] * 32, {}, 0
    for steps in range(max_steps):
        w = imem.get(pc, 0x13)
        if w == 0x0000006F:          # jal x0, 0  == halt
            return x, steps
        op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
        rs1, rs2, f7 = (w >> 15) & 31, (w >> 20) & 31, w >> 25
        a, b = x[rs1], x[rs2]
        nxt, res = pc + 4, None
        if op in (0x33, 0x13):
            imm = sx(w >> 20, 12) & MASK
            bb = b if op == 0x33 else imm
            sh = bb & 31
            sub = op == 0x33 and f7 == 0x20
            res = {0: (a - bb) if sub else (a + bb),
                   1: a << sh,
                   2: int(sx(a, 32) < sx(bb, 32)),
                   3: int(a < bb),
                   4: a ^ bb,
                   5: (sx(a, 32) >> sh) if f7 == 0x20 else (a >> sh),
                   6: a | bb,
                   7: a & bb}[f3]
        elif op == 0x37:
            res = w & 0xFFFFF000
        elif op == 0x17:
            res = pc + (w & 0xFFFFF000)
        elif op == 0x6F:
            res = pc + 4
            nxt = pc + sx(((w >> 31) << 20) | (((w >> 12) & 0xFF) << 12)
                          | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)
        elif op == 0x67:
            res = pc + 4
            nxt = (a + sx(w >> 20, 12)) & ~1
        elif op == 0x63:
            taken = {0: a == b, 1: a != b, 4: sx(a, 32) < sx(b, 32),
                     5: sx(a, 32) >= sx(b, 32), 6: a < b, 7: a >= b}[f3]
            if taken:
                nxt = pc + sx(((w >> 31) << 12) | (((w >> 7) & 1) << 11)
                              | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)
        elif op == 0x03:
            addr = (a + sx(w >> 20, 12)) & MASK
            n = {0: 1, 1: 2, 2: 4, 4: 1, 5: 2}[f3]
            v = sum(mem.get(addr + i, 0) << (8 * i) for i in range(n))
            res = sx(v, 8 * n) if f3 in (0, 1) else v
        elif op == 0x23:
            addr = (a + sx(((w >> 25) << 5) | ((w >> 7) & 31), 12)) & MASK
            for i in range({0: 1, 1: 2, 2: 4}[f3]):
                mem[addr + i] = (b >> (8 * i)) & 0xFF
        # FENCE / ECALL / EBREAK: no architectural effect here
        if res is not None and rd != 0:
            x[rd] = res & MASK
        pc = nxt & MASK
    raise RuntimeError("program did not reach halt")


# ----------------------------------------------------------------------------
# Test definitions
#   prog   : assembly; 'halt: jal x0, halt' is appended automatically
#   expect : {reg: value} checked against both the golden model and the DUT
#   extra  : optional VHDL checks run after the register checks
# ----------------------------------------------------------------------------
TESTS = {}


def test(name, desc, prog, expect, extra="", stim=None):
    TESTS[name] = dict(desc=desc, prog=prog, expect=expect, extra=extra, stim=stim)


test("tb_r_type", "All 10 R-type instructions", [
    "addi x1, x0, 20",
    "addi x2, x0, 7",
    "add  x3, x1, x2       # 27",
    "sub  x4, x1, x2       # 13",
    "and  x5, x1, x2       # 4",
    "or   x6, x1, x2       # 23",
    "xor  x7, x1, x2       # 19",
    "sll  x8, x1, x2       # 20 << 7 = 2560",
    "srl  x9, x1, x2       # 0",
    "sra  x10, x1, x2      # 0",
    "slt  x11, x2, x1      # 7 < 20 -> 1",
    "sltu x12, x2, x1      # 1",
    "addi x13, x0, -4",
    "sra  x14, x13, x2     # -4 >>> 7 = -1",
    "slt  x15, x13, x2     # signed: -4 < 7 -> 1",
    "sltu x16, x13, x2     # unsigned: 0xFFFFFFFC < 7 -> 0",
    "srl  x17, x13, x2     # logical: 0x01FFFFFF",
], {1: 20, 2: 7, 3: 27, 4: 13, 5: 4, 6: 23, 7: 19, 8: 2560, 9: 0, 10: 0,
    11: 1, 12: 1, 13: -4, 14: -1, 15: 1, 16: 0, 17: 0x01FFFFFF})

test("tb_i_type", "All 9 I-type ALU instructions", [
    "addi  x1, x0, 100",
    "addi  x2, x1, -10     # 90",
    "slti  x3, x1, 200     # 1",
    "slti  x4, x1, 50      # 0",
    "sltiu x5, x1, -1      # 100 < 0xFFFFFFFF -> 1",
    "xori  x6, x1, 255     # 0x64 ^ 0xFF = 155",
    "ori   x7, x1, 15      # 111",
    "andi  x8, x1, 240     # 96",
    "slli  x9, x1, 2       # 400",
    "srli  x10, x1, 2      # 25",
    "srai  x11, x1, 2      # 25",
    "addi  x12, x0, -4",
    "srai  x13, x12, 1     # -2",
    "srli  x14, x12, 1     # 0x7FFFFFFE",
    "sltiu x15, x0, 1      # 1",
    "sltiu x16, x0, 0      # 0",
    "xori  x17, x12, -1    # NOT(-4) = 3",
], {1: 100, 2: 90, 3: 1, 4: 0, 5: 1, 6: 155, 7: 111, 8: 96, 9: 400, 10: 25,
    11: 25, 12: -4, 13: -2, 14: 0x7FFFFFFE, 15: 1, 16: 0, 17: 3})

test("tb_lui_auipc", "LUI and AUIPC", [
    "lui   x1, 0xDEADB     # 0xDEADB000",
    "auipc x2, 0x4         # PC 0x04 + 0x4000",
    "auipc x3, 0x0         # PC 0x08",
    "lui   x4, 0xFFFFF",
    "lui   x5, 0x0",
    "addi  x6, x1, 0x7EF   # LUI result forwarded: 0xDEADB7EF",
], {1: 0xDEADB000, 2: 0x4004, 3: 0x8, 4: 0xFFFFF000, 5: 0, 6: 0xDEADB7EF})

test("tb_jal_jalr", "JAL, JALR, link register, call/return", [
    "jal  x1, t1           # x1 = 0x04",
    "addi x29, x0, 1       # must be skipped",
    "addi x29, x0, 2       # must be skipped",
    "t1: addi x10, x1, 0   # link value forwarded from EX/MEM -> 4",
    "addi x5, x0, 33",
    "jalr x2, 15(x5)       # 33+15 = 48 = 0x30; x2 = 0x18",
    "addi x29, x0, 3       # must be skipped",
    "addi x29, x0, 4       # must be skipped",
    ".org 0x30",
    "addi x11, x0, 1",
    "addi x12, x2, 0       # 0x18",
    "addi x6, x0, 0x51",
    "jalr x0, 0(x6)        # 0x51 -> bit 0 cleared -> 0x50",
    "addi x29, x0, 5       # must be skipped",
    ".org 0x50",
    "jal  x1, func         # call",
    "addi x13, x13, 1      # after return: 5 + 1",
    "jal  x0, halt",
    "func: addi x13, x0, 5",
    "jalr x0, 0(x1)        # return",
], {1: 0x54, 2: 0x18, 10: 4, 11: 1, 12: 0x18, 13: 6, 29: 0})

test("tb_branch", "All 6 branch instructions, taken", [
    "addi x1, x0, 5",
    "addi x2, x0, 5",
    "addi x3, x0, 10",
    "addi x4, x0, -1",
    "beq  x1, x2, L1",
    "addi x28, x0, 1       # ERROR if executed",
    "L1: addi x10, x0, 1",
    "bne  x1, x3, L2",
    "addi x28, x0, 2",
    "L2: addi x11, x0, 1",
    "blt  x1, x3, L3",
    "addi x28, x0, 3",
    "L3: addi x12, x0, 1",
    "bge  x3, x1, L4",
    "addi x28, x0, 4",
    "L4: addi x13, x0, 1",
    "bltu x1, x3, L5",
    "addi x28, x0, 5",
    "L5: addi x14, x0, 1",
    "bgeu x3, x1, L6",
    "addi x28, x0, 6",
    "L6: addi x15, x0, 1",
    "blt  x4, x1, L7       # signed: -1 < 5",
    "addi x28, x0, 7",
    "L7: addi x16, x0, 1",
    "bgeu x4, x1, L8       # unsigned: 0xFFFFFFFF >= 5",
    "addi x28, x0, 8",
    "L8: addi x17, x0, 1",
], {10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 28: 0})

test("tb_branch_not_taken", "All 6 branch instructions, not taken", [
    "addi x1, x0, 5",
    "addi x2, x0, 10",
    "addi x3, x0, -1",
    "beq  x1, x2, fail",
    "addi x10, x0, 1",
    "bne  x1, x1, fail",
    "addi x11, x0, 1",
    "blt  x2, x1, fail",
    "addi x12, x0, 1",
    "bge  x1, x2, fail",
    "addi x13, x0, 1",
    "bltu x2, x1, fail",
    "addi x14, x0, 1",
    "bgeu x1, x2, fail",
    "addi x15, x0, 1",
    "bltu x3, x1, fail     # unsigned: 0xFFFFFFFF is not < 5",
    "addi x16, x0, 1",
    "bge  x3, x1, fail     # signed: -1 is not >= 5",
    "addi x17, x0, 1",
    "jal  x0, halt",
    "fail: addi x29, x0, 1",
], {10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 29: 0})

test("tb_branch_loop", "Backward loop: trains the predictor, predicted-taken path, exit mispredict", [
    "addi x20, x0, 256",
    "addi x1, x0, 4        # loop counter",
    "addi x2, x0, 0",
    "loop: addi x2, x2, 3",
    "addi x1, x1, -1",
    "sw   x1, 0(x20)",
    "lw   x5, 0(x20)",
    "bne  x5, x0, loop     # load-use stall while predicted-taken branch is in ID",
    "addi x6, x0, 1",
    "addi x7, x0, 3",
    "loop2: addi x7, x7, -1",
    "bne  x7, x0, loop2    # tight 2-instruction loop",
    "addi x8, x0, 1",
], {1: 0, 2: 12, 5: 0, 6: 1, 7: 0, 8: 1})

test("tb_consecutive_branches", "Back-to-back branches, and branches in the shadow of a taken branch", [
    "addi x1, x0, 5",
    "addi x2, x0, 5",
    "addi x3, x0, 10",
    "beq  x1, x2, L1       # taken",
    "bne  x1, x3, bad      # in the shadow: must be flushed",
    "addi x29, x0, 2",
    "L1: bne x1, x3, L2    # taken, right after a taken branch",
    "beq  x1, x1, bad      # in the shadow: must be flushed",
    "L2: beq x1, x3, bad   # not taken",
    "bne  x1, x2, bad      # not taken, back-to-back",
    "addi x10, x0, 99",
    "jal  x0, halt",
    "bad: addi x29, x0, 1",
], {10: 99, 29: 0})

test("tb_branch_with_forwarding", "Branch operands supplied by the forwarding paths", [
    "addi x1, x0, 5",
    "addi x2, x1, 0        # x2 = x1 (EX/MEM forward)",
    "beq  x1, x2, ok1      # x1 from MEM/WB, x2 from EX/MEM",
    "addi x29, x0, 1",
    "ok1: addi x10, x0, 1",
    "addi x3, x0, 7",
    "nop",
    "bne  x3, x0, ok2      # x3 from MEM/WB",
    "addi x29, x0, 2",
    "ok2: addi x11, x0, 1",
], {10: 1, 11: 1, 29: 0})

test("tb_load_store", "Word, halfword and byte loads/stores", [
    "addi x20, x0, 256     # data base address",
    "lui  x1, 0x12345",
    "addi x1, x1, 0x678    # 0x12345678",
    "sw   x1, 0(x20)",
    "lw   x2, 0(x20)       # 0x12345678",
    "sh   x1, 4(x20)",
    "lh   x3, 4(x20)       # 0x5678",
    "lui  x6, 0x8          # 0x8000",
    "sh   x6, 8(x20)",
    "lh   x4, 8(x20)       # sign-extended 0xFFFF8000",
    "lhu  x5, 8(x20)       # zero-extended 0x00008000",
    "addi x6, x0, -1",
    "sb   x6, 12(x20)",
    "lb   x7, 12(x20)      # -1",
    "lbu  x8, 12(x20)      # 255",
], {2: 0x12345678, 3: 0x5678, 4: 0xFFFF8000, 5: 0x8000, 6: -1, 7: -1, 8: 255})

test("tb_all_loads", "All 5 load variants with sign/zero extension", [
    "lui  x1, 0xABCD1",
    "addi x1, x1, 0x234    # 0xABCD1234",
    "addi x20, x0, 256",
    "sw   x1, 0(x20)",
    "lw   x10, 0(x20)      # 0xABCD1234",
    "lh   x2, 0(x20)       # 0x00001234",
    "lh   x3, 2(x20)       # 0xFFFFABCD",
    "lhu  x4, 0(x20)       # 0x00001234",
    "lhu  x5, 2(x20)       # 0x0000ABCD",
    "lb   x6, 0(x20)       # 0x00000034",
    "lb   x7, 2(x20)       # 0xFFFFFFCD",
    "lbu  x8, 0(x20)       # 0x34",
    "lbu  x9, 2(x20)       # 0xCD",
    "lb   x11, 1(x20)      # 0x12",
    "lb   x12, 3(x20)      # 0xFFFFFFAB",
], {10: 0xABCD1234, 2: 0x1234, 3: 0xFFFFABCD, 4: 0x1234, 5: 0xABCD, 6: 0x34,
    7: 0xFFFFFFCD, 8: 0x34, 9: 0xCD, 11: 0x12, 12: 0xFFFFFFAB})

test("tb_all_stores", "All 3 store variants", [
    "addi x20, x0, 256",
    "addi x1, x0, 0xAA",
    "addi x2, x0, 0xBB",
    "addi x3, x0, 0xCC",
    "addi x4, x0, 0xDD",
    "sb   x1, 0(x20)",
    "sb   x2, 1(x20)",
    "sb   x3, 2(x20)",
    "sb   x4, 3(x20)",
    "lw   x5, 0(x20)       # 0xDDCCBBAA",
    "lui  x6, 0x1",
    "addi x6, x6, 0x234    # 0x1234",
    "sh   x6, 4(x20)",
    "lhu  x7, 4(x20)       # 0x1234",
    "lw   x10, 4(x20)      # 0x00001234 (upper half untouched)",
    "sh   x6, 6(x20)",
    "lw   x11, 4(x20)      # 0x12341234",
    "lui  x12, 0x8         # 0x8000",
    "sh   x12, 8(x20)",
    "lh   x8, 8(x20)       # 0xFFFF8000",
    "lhu  x9, 8(x20)       # 0x00008000",
    "sw   x5, 12(x20)",
    "lw   x13, 12(x20)     # 0xDDCCBBAA",
], {5: 0xDDCCBBAA, 7: 0x1234, 10: 0x1234, 11: 0x12341234, 8: 0xFFFF8000,
    9: 0x8000, 13: 0xDDCCBBAA})

test("tb_hazard_raw", "RAW dependency chains resolved by forwarding", [
    "addi x1, x0, 10",
    "addi x1, x1, 5        # EX/MEM forward",
    "addi x1, x1, 3        # EX/MEM forward -> 18",
    "addi x2, x0, 100",
    "addi x3, x0, 0",
    "add  x4, x2, x3       # x2 MEM/WB, x3 EX/MEM -> 100",
    "addi x5, x0, 1",
    "add  x6, x5, x5       # 2",
    "add  x7, x5, x6       # x5 MEM/WB, x6 EX/MEM -> 3",
    "add  x8, x6, x7       # 5",
    "addi x21, x0, 9",
    "nop",
    "nop",
    "add  x22, x21, x21    # 3 apart: register-file write-through -> 18",
], {1: 18, 4: 100, 6: 2, 7: 3, 8: 5, 22: 18})

test("tb_hazard_load_use", "Load-use stalls (ALU, store data, branch consumers)", [
    "addi x1, x0, 42",
    "addi x20, x0, 256",
    "sw   x1, 0(x20)",
    "lw   x2, 0(x20)",
    "add  x3, x2, x2       # load-use: 1 bubble -> 84",
    "lw   x4, 0(x20)",
    "addi x5, x0, 8",
    "add  x6, x4, x5       # 2 apart: MEM/WB forward, no stall -> 50",
    "addi x7, x0, -128",
    "sb   x7, 4(x20)",
    "lb   x8, 4(x20)",
    "add  x9, x8, x8       # load-use on a sign-extended byte -> -256",
    "lw   x10, 0(x20)",
    "sw   x10, 8(x20)      # load-use on store data",
    "lw   x11, 8(x20)      # 42",
    "lw   x12, 0(x20)",
    "beq  x12, x1, ok      # load-use on a branch operand",
    "addi x29, x0, 1",
    "ok: addi x13, x0, 1",
], {2: 42, 3: 84, 6: 50, 8: -128, 9: -256, 11: 42, 13: 1, 29: 0})

test("tb_forwarding", "Each forwarding path and priority rule", [
    "addi x1, x0, 50",
    "add  x2, x0, x1       # rs2 from EX/MEM -> 50",
    "addi x3, x0, 7",
    "add  x4, x3, x0       # rs1 from EX/MEM -> 7",
    "addi x5, x0, 20",
    "addi x6, x0, 1",
    "add  x7, x5, x0       # rs1 from MEM/WB -> 20",
    "addi x8, x0, 15",
    "addi x9, x0, 0",
    "add  x10, x0, x8      # rs2 from MEM/WB -> 15",
    "addi x11, x0, 3",
    "addi x12, x0, 4",
    "add  x13, x11, x12    # rs1 MEM/WB + rs2 EX/MEM -> 7",
    "addi x14, x0, 99",
    "addi x15, x0, 256",
    "sw   x14, 0(x15)      # address EX/MEM, store data MEM/WB",
    "lw   x16, 0(x15)      # 99",
    "addi x17, x0, 1",
    "addi x17, x0, 2",
    "add  x18, x17, x0     # both stages hold x17: newest (EX/MEM) wins -> 2",
    "addi x0, x0, 5        # write to x0 is discarded",
    "add  x19, x0, x0      # x0 must not be forwarded -> 0",
], {2: 50, 4: 7, 7: 20, 10: 15, 13: 7, 16: 99, 18: 2, 19: 0})

test("tb_store_forward", "Store followed by load of the same address", [
    "addi x1, x0, 77",
    "addi x20, x0, 256",
    "sw   x1, 0(x20)",
    "addi x2, x0, 88",
    "sw   x2, 4(x20)",
    "lw   x3, 0(x20)       # 77",
    "lw   x4, 4(x20)       # 88",
    "addi x5, x0, 123",
    "sw   x5, 8(x20)       # store data forwarded from EX/MEM",
    "lw   x6, 8(x20)       # load directly after store -> 123",
], {3: 77, 4: 88, 6: 123})

test("tb_overflow_edge", "Integer overflow and shift edge cases", [
    "lui  x1, 0x80000",
    "addi x1, x1, -1       # 0x7FFFFFFF (INT_MAX)",
    "add  x2, x1, x1       # 0xFFFFFFFE",
    "addi x3, x0, 1",
    "add  x4, x1, x3       # INT_MAX + 1 wraps to 0x80000000",
    "slli x5, x1, 5        # 0xFFFFFFE0",
    "sub  x6, x4, x3       # INT_MIN - 1 wraps to 0x7FFFFFFF",
    "lui  x9, 0x80000",
    "srai x10, x9, 1       # 0xC0000000",
    "srli x11, x9, 31      # 1",
    "sltu x12, x9, x3      # 0x80000000 <u 1 -> 0",
    "slt  x13, x9, x3      # INT_MIN < 1 -> 1",
    "add  x14, x9, x9      # 0",
], {1: 0x7FFFFFFF, 2: 0xFFFFFFFE, 4: 0x80000000, 5: 0xFFFFFFE0, 6: 0x7FFFFFFF,
    10: 0xC0000000, 11: 1, 12: 0, 13: 1, 14: 0})

test("tb_fence_system", "FENCE, ECALL and EBREAK execute as NOPs", [
    "addi x1, x0, 5",
    "fence",
    "addi x2, x0, 10",
    "ecall",
    "addi x3, x0, 20",
    "ebreak",
    "addi x4, x0, 30",
], {1: 5, 2: 10, 3: 20, 4: 30})

test("tb_pipeline_stall_count", "Exact bubble counts: load-use = 1, taken jump = 2", [
    "addi x1, x0, 42",
    "addi x20, x0, 256",
    "sw   x1, 0(x20)",
    "lw   x2, 0(x20)",
    "add  x3, x2, x2       # load-use: written 2 cycles after x2",
    "addi x4, x0, 1",
    "addi x5, x4, 1        # forwarded: written 1 cycle after x4",
    "jal  x6, next         # jump to the next instruction",
    "next: addi x7, x0, 1  # written 3 cycles after x6 (2 flushed slots)",
], {2: 42, 3: 84, 5: 2, 6: 0x20, 7: 1}, extra="""
        check_cond(wcycle(3) - wcycle(2) = 2,
                   "load-use should insert exactly 1 bubble, gap was "
                   & integer'image(wcycle(3) - wcycle(2)), errors);
        check_cond(wcycle(5) - wcycle(4) = 1,
                   "forwarded RAW should not stall, gap was "
                   & integer'image(wcycle(5) - wcycle(4)), errors);
        check_cond(wcycle(7) - wcycle(6) = 3,
                   "jump should cost 2 bubbles, gap was "
                   & integer'image(wcycle(7) - wcycle(6)), errors);""")

test("tb_full_fibonacci", "End-to-end: Fibonacci(10) = 55", [
    "addi x1, x0, 0        # a = 0",
    "addi x2, x0, 1        # b = 1",
    "addi x3, x0, 10       # n = 10",
    "addi x4, x0, 0        # i = 0",
    "loop: bge x4, x3, exit",
    "add  x5, x1, x2       # tmp = a + b",
    "add  x1, x2, x0       # a = b",
    "add  x2, x5, x0       # b = tmp",
    "addi x4, x4, 1        # i++",
    "jal  x0, loop",
    "exit: sw x1, 256(x0)  # store Fib(10)",
    "lw   x6, 256(x0)",
], {1: 55, 2: 89, 4: 10, 6: 55})

test("tb_reset", "Reset mid-run returns PC to 0 and re-executes cleanly", [
    "addi x1, x0, 1",
    "addi x2, x0, 2",
    "addi x3, x0, 3",
    "addi x4, x0, 4",
    "addi x5, x0, 5",
], {1: 1, 2: 2, 3: 3, 4: 4, 5: 5}, stim="""
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for 10 * CLK_PERIOD;
        check_cond(unsigned(dbg_pc) > 0, "PC not advancing", errors);

        -- Reset again, mid-run
        wait until falling_edge(clk);
        rst <= '1';
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        check_cond(dbg_pc = x"00000000", "PC not reset to 0", errors);
        check_cond(dbg_reg_we = '0', "register write during reset", errors);

        -- Clear the shadow copy so the re-run must write everything again
        clear_regs <= '1';
        wait until falling_edge(clk);
        clear_regs <= '0';
        rst <= '0';
        wait for 30 * CLK_PERIOD;""")


# ----------------------------------------------------------------------------
# VHDL emission
# ----------------------------------------------------------------------------
TEMPLATE = """\
-- =============================================================================
-- {name}.vhd  —  {desc}
--
-- GENERATED by tools/gen_tests.py from the assembly below. Edit the program
-- there and re-run the script; expected values come from its ISA simulator.
--
{listing}
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tb_pkg.all;

entity {name} is
end entity {name};

architecture sim of {name} is
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal dbg_pc     : std_logic_vector(31 downto 0);
    signal dbg_instr  : std_logic_vector(31 downto 0);
    signal dbg_reg_we : std_logic;
    signal dbg_reg_wa : std_logic_vector(4 downto 0);
    signal dbg_reg_wd : std_logic_vector(31 downto 0);

    -- Shadow register file built from the write-back port, plus the cycle
    -- (counted from reset release) of each register's latest write.
    signal regs       : reg_array_t := (others => (others => '0'));
    signal wcycle     : int_array_t := (others => -1);
    signal cycle      : integer := 0;
    signal clear_regs : std_logic := '0';

    constant PROG : prog_t := (
{prog}
    );
    constant HEX_FILE : string := write_hex("/tmp/{name}.hex", PROG);

begin
    clk <= not clk after CLK_PERIOD / 2;

    dut: entity work.pipeline_top
        generic map (MEM_DEPTH => 256, IMEM_INIT => HEX_FILE)
        port map (clk => clk, rst => rst,
                  dbg_pc => dbg_pc, dbg_instr => dbg_instr,
                  dbg_reg_we => dbg_reg_we,
                  dbg_reg_wa => dbg_reg_wa,
                  dbg_reg_wd => dbg_reg_wd);

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cycle <= 0;
            else
                cycle <= cycle + 1;
            end if;
            if clear_regs = '1' then
                regs   <= (others => (others => '0'));
                wcycle <= (others => -1);
            elsif dbg_reg_we = '1' and unsigned(dbg_reg_wa) /= 0 then
                regs(to_integer(unsigned(dbg_reg_wa)))   <= dbg_reg_wd;
                wcycle(to_integer(unsigned(dbg_reg_wa))) <= cycle;
            end if;
        end if;
    end process;

    process
        variable errors : natural := 0;
    begin
{stim}

{checks}
{extra}
        finish_test("{name}", errors);
        wait;
    end process;
end architecture sim;
"""

DEFAULT_STIM = """\
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for {cycles} * CLK_PERIOD;"""


def emit(name, t):
    prog = assemble(t["prog"] + ["halt: jal x0, halt   # end of program"])
    regs, steps = simulate(prog)

    for r, v in t["expect"].items():
        if regs[r] != v & MASK:
            sys.exit(f"{name}: golden model gives x{r} = 0x{regs[r]:08X}, "
                     f"test expects 0x{v & MASK:08X}")

    width = max(len(a) for _, _, a, _ in prog)
    listing = "\n".join(
        f"--   0x{pc:02X}: {asm:<{width}}" + (f"  # {c}" if c else "")
        for pc, _, asm, c in prog)
    body = ",\n".join(f'        {i:2} => x"{w:08X}"' for i, (_, w, _, _) in enumerate(prog))
    checks = "\n".join(
        f'        check_reg(regs, {r}, x"{v & MASK:08X}", "x{r}", errors);'
        for r, v in sorted(t["expect"].items()))
    # Generous bound: every instruction could cost a stall plus a flush.
    cycles = 4 * steps + 20
    stim = t["stim"].strip("\n") if t["stim"] else DEFAULT_STIM.format(cycles=cycles)

    text = TEMPLATE.format(name=name, desc=t["desc"], listing=listing, prog=body,
                           checks=checks, extra=t["extra"].strip("\n"), stim=stim)
    with open(os.path.join(ROOT, "tb", name + ".vhd"), "w") as f:
        f.write(text)
    print(f"{name:28} {len(prog):3} instrs, {steps:4} executed, {len(t['expect'])} checks")


if __name__ == "__main__":
    for n, t in TESTS.items():
        emit(n, t)
