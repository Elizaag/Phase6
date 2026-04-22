#!/usr/bin/env python3
"""
It was very tedious to format the code properly, especially the encoders and dictionaries, to make it more readable. 
Therefore, I used GPT to help format the code and improve its readability.
Run:
  python assembler.py <base_path> <file.s>
Example:
  python assembler.py . add_shift.s
"""

from __future__ import annotations
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

# Helpers

def strip_comment(line: str) -> str:
    line = line.split("#", 1)[0]
    line = line.split(";", 1)[0]
    return line.strip()

def is_blank(line: str) -> bool:
    return not line.strip()

def split_operands(ops: str) -> List[str]:
    # Splits by comma, ignoring whitespace
    return [o.strip() for o in ops.split(",") if o.strip()]

def parse_imm(s: str) -> int:
    s = s.strip()
    if s.lower().startswith(("0x", "-0x", "+0x")):
        return int(s, 16)
    return int(s, 10)

def sign_check(value: int, bits: int, what: str = "imm") -> None:
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if value < lo or value > hi:
        raise ValueError(f"{what} out of range for {bits}-bit signed: {value}")

def ucheck(value: int, bits: int, what: str = "field") -> None:
    lo = 0
    hi = (1 << bits) - 1
    if value < lo or value > hi:
        raise ValueError(f"{what} out of range for {bits}-bit unsigned: {value}")

def hex32(x: int) -> str:
    return f"0x{x & 0xFFFFFFFF:08x}"

# Registers [cite: 83, 84]

REG: Dict[str, int] = {
    **{f"x{i}": i for i in range(32)},
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}

def reg_num(tok: str) -> int:
    t = tok.strip().lower()
    if t not in REG:
        raise ValueError(f"Unknown register: {tok}")
    return REG[t]

# Encoders

# R-type: [funct7 | rs2 | rs1 | funct3 | rd | opcode] [cite: 76]
def enc_r(opcode: int, rd: int, funct3: int, rs1: int, rs2: int, funct7: int) -> int:
    ucheck(opcode, 7, "opcode"); ucheck(rd, 5, "rd"); ucheck(funct3, 3, "funct3")
    ucheck(rs1, 5, "rs1"); ucheck(rs2, 5, "rs2"); ucheck(funct7, 7, "funct7")
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

# I-type: [imm[11:0] | rs1 | funct3 | rd | opcode] [cite: 76]
def enc_i(opcode: int, rd: int, funct3: int, rs1: int, imm: int) -> int:
    sign_check(imm, 12, "imm[11:0]")
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)

# I-type Shift (slli, srli, srai): [funct7 | shamt | rs1 | funct3 | rd | opcode] [cite: 73]
def enc_i_shift(opcode: int, rd: int, funct3: int, rs1: int, shamt: int, funct7: int) -> int:
    ucheck(shamt, 5, "shamt"); ucheck(funct7, 7, "funct7")
    imm = ((funct7 & 0x7F) << 5) | (shamt & 0x1F)
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)

# S-type: [imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode] [cite: 76]
def enc_s(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    sign_check(imm, 12, "imm[11:0]")
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0  = imm & 0x1F
    return ((imm11_5 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((imm4_0 & 0x1F) << 7) | (opcode & 0x7F)

# B-type: [imm[12]|imm[10:5]|rs2|rs1|funct3|imm[4:1]|imm[11]|opcode] [cite: 76]
def enc_b(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    sign_check(imm, 13, "branch imm")
    if imm % 2 != 0: raise ValueError(f"Branch offset must be multiple of 2, got {imm}")
    imm &= 0x1FFF
    bit12    = (imm >> 12) & 0x1
    bits10_5 = (imm >> 5)  & 0x3F
    bits4_1  = (imm >> 1)  & 0xF
    bit11    = (imm >> 11) & 0x1
    return (bit12 << 31) | (bits10_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | (bits4_1 << 8) | (bit11 << 7) | (opcode & 0x7F)

# U-type: [imm[31:12] | rd | opcode] [cite: 76]
def enc_u(opcode: int, rd: int, imm: int) -> int:
    # imm input is the upper 20 bits (0..0xFFFFF)
    ucheck(imm, 20, "u-imm") 
    return ((imm & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

# J-type: [imm[20]|imm[10:1]|imm[11]|imm[19:12] | rd | opcode] [cite: 76]
def enc_j(opcode: int, rd: int, imm: int) -> int:
    sign_check(imm, 21, "jump imm")
    if imm % 2 != 0: raise ValueError(f"Jump offset must be multiple of 2, got {imm}")
    imm &= 0x1FFFFF
    bit20     = (imm >> 20) & 0x1
    bits10_1  = (imm >> 1)  & 0x3FF
    bit11     = (imm >> 11) & 0x1
    bits19_12 = (imm >> 12) & 0xFF
    return (bit20 << 31) | (bits19_12 << 12) | (bit11 << 20) | (bits10_1 << 21) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)

# Assembler Classes

@dataclass
class InstrRecord:
    lineno: int
    mnemonic: str
    operands: List[str]
    addr: int

@dataclass
class DataRecord:
    lineno: int
    directive: str
    args: str
    addr: int

class Assembler:
    def __init__(self) -> None:
        self.text_base = 0x00400000
        self.data_base = 0x10010000
        self.labels: Dict[str, int] = {}
        self.global_label: Optional[str] = None
        self.instrs: List[InstrRecord] = []
        self.data_words: List[int] = []   # collected .word values from .data section
        self.pc: int = 0

    # --- Utilities ---

    def resolve_val(self, token: str, current_pc: int) -> int:
        token = token.strip()
        
        # Macros %hi(sym), %lo(sym)
        if token.startswith("%hi("):
            sym = token[4:-1].strip()
            if sym not in self.labels: raise ValueError(f"Unknown label: {sym}")
            addr = self.labels[sym]
            return (addr + 0x800) >> 12
        if token.startswith("%lo("):
            sym = token[4:-1].strip()
            if sym not in self.labels: raise ValueError(f"Unknown label: {sym}")
            return self.labels[sym] & 0xFFF

        if token in self.labels:
            return self.labels[token]

        # Try parsing integer (0x... or 123)
        try:
            return parse_imm(token)
        except ValueError:
            pass

        # Try Label+Offset (e.g., "start+4")
        m = re.match(r"^([A-Za-z_]\w*)([+-]\d+|[+-]0x[0-9a-fA-F]+)$", token)
        if m:
            base, off = m.group(1), m.group(2)
            if base not in self.labels: raise ValueError(f"Unknown label: {base}")
            return self.labels[base] + parse_imm(off)

        raise ValueError(f"Cannot resolve '{token}'")

    def parse_mem(self, op: str, current_pc: int) -> Tuple[int, int]:
        # imm(rs1)
        m = re.match(r"^(.*)\(([^)]+)\)$", op)
        if not m: raise ValueError(f"Invalid memory operand: {op}")
        imm_s, rs1_s = m.group(1).strip(), m.group(2).strip()
        rs1 = reg_num(rs1_s)
        imm = 0 if not imm_s else self.resolve_val(imm_s, current_pc)
        return imm, rs1

    # Core Assembly Logic

    def assemble(self, lines: List[str]) -> Tuple[List[int], List[int]]:
        # 1. Strip comments & parse structure
        cleaned_lines = []
        for ln, raw in enumerate(lines, 1):
            line = strip_comment(raw)
            if line: cleaned_lines.append((ln, line, raw))

        # 2. Pass 1: Address calculation & Symbol Table
        self.pass1(cleaned_lines)

        # 3. Check global label
        if self.global_label and self.global_label not in self.labels:
            raise ValueError(f".global label '{self.global_label}' not found")

        # 4. Pass 2: Encoding
        words = self.pass2()
        return words, self.data_words

    def pass1(self, lines: List[Tuple[int, str, str]]) -> None:
        self.pc = self.text_base
        self.data_pc = self.data_base
        self.labels = {}
        self.instrs = []
        self.data_words = []
        section = "text"

        for ln, line, raw in lines:
            # Directives
            if line.startswith("."):
                if line.startswith(".text"):
                    section = "text"
                elif line.startswith(".data"):
                    section = "data"
                elif line.startswith(".globl") or line.startswith(".global"):
                    parts = line.split()
                    if len(parts) > 1: self.global_label = parts[1]
                elif section == "data":
                    self.handle_data(line, ln)
                continue

            # Labels
            while ":" in line:
                lbl_str, rest = line.split(":", 1)
                lbl = lbl_str.strip()
                # If label is in string (e.g. .asciiz "l:"), ignore. Simplified parser assumes no colons in strings.
                if " " in lbl and not lbl.startswith("."): # Basic check for bad label
                    break 
                if lbl in self.labels: raise ValueError(f"Duplicate label: {lbl}")
                if section == "data":
                    # Assign label after processing .word/.byte/.space/.ascii
                    # Save rest of line for later
                    pending_label = lbl
                    line = rest.strip()
                    # If next is .word/.byte/.space/.ascii, process and then assign label
                    m = re.match(r"^\.(\w+)", line)
                    if m:
                        self.handle_data(line, ln)
                        self.labels[pending_label] = self.data_pc - self.get_data_size(line)
                        line = ''
                    else:
                        self.labels[pending_label] = self.data_pc
                else:
                    self.labels[lbl] = self.pc
                    line = rest.strip()
            
            if not line: continue

            if section == "text":
                parts = line.split(None, 1)
                mnem = parts[0].lower()
                ops = split_operands(parts[1]) if len(parts) > 1 else []
                
                # Sizing for Pseudos
                size = 4
                if mnem == "li":
                    # If immediate fits in 12-bit signed, 4 bytes. Else 8 (lui+addi).
                    try:
                        val = parse_imm(ops[1])
                        if not (-2048 <= val <= 2047): size = 8
                    except:
                        # If label or unknown, assume worst case (8)
                        size = 8
                elif mnem == "la": size = 8
                elif mnem == "call": size = 8
                elif mnem == "tail": size = 8
                
                self.instrs.append(InstrRecord(ln, mnem, ops, self.pc))
                self.pc += size

    def get_data_size(self, line: str) -> int:
        m = re.match(r"^\.(\w+)\s*(.*)$", line)
        if not m:
            return 0
        d, args = m.group(1), m.group(2).strip()
        if d == "word":
            return 4 * len(split_operands(args))
        elif d == "byte":
            return len(split_operands(args))
        elif d == "space":
            return parse_imm(args)
        elif d in ("ascii", "asciiz"):
            return len(args)
        return 0

    def handle_data(self, line: str, ln: int):
        m = re.match(r"^\.(\w+)\s*(.*)$", line)
        if not m: return
        d, args = m.group(1), m.group(2).strip()
        if d == "word":
            for tok in split_operands(args):
                try:
                    val = parse_imm(tok) & 0xFFFFFFFF
                except ValueError:
                    val = 0  # unresolved label placeholder; resolve in pass2 if needed
                self.data_words.append(val)
                self.data_pc += 4
        elif d == "byte":
            for tok in split_operands(args):
                self.data_pc += 1
        elif d == "space":
            self.data_pc += parse_imm(args)
        elif d in ("ascii", "asciiz"):
            self.data_pc += len(args)

    def pass2(self) -> List[int]:
        binaries = []
        for rec in self.instrs:
            m = rec.mnemonic
            o = rec.operands
            pc = rec.addr
            
            # PSEUDO INSTRUCTIONS
            
            if m == "nop": # addi x0, x0, 0
                binaries.append(enc_i(0x13, 0, 0, 0, 0))

            elif m == "mv": # addi rd, rs, 0
                rd, rs = reg_num(o[0]), reg_num(o[1])
                binaries.append(enc_i(0x13, rd, 0, rs, 0))

            elif m == "not": # xori rd, rs, -1
                rd, rs = reg_num(o[0]), reg_num(o[1])
                binaries.append(enc_i(0x13, rd, 4, rs, -1))

            elif m == "neg": # sub rd, x0, rs
                rd, rs = reg_num(o[0]), reg_num(o[1])
                binaries.append(enc_r(0x33, rd, 0, 0, rs, 0x20))

            elif m == "j": # jal x0, label
                off = self.resolve_val(o[0], pc) - pc
                binaries.append(enc_j(0x6F, 0, off))

            elif m == "jr": # jalr x0, 0(rs)
                rs = reg_num(o[0])
                binaries.append(enc_i(0x67, 0, 0, rs, 0))

            elif m == "ret": # jalr x0, 0(ra)
                binaries.append(enc_i(0x67, 0, 0, 1, 0))

            elif m == "call": # auipc x1, off_hi -> jalr x1, off_lo(x1)
                target = self.resolve_val(o[0], pc)
                off = target - pc
                hi = (off + 0x800) >> 12
                lo = off & 0xFFF
                binaries.append(enc_u(0x17, 1, hi))
                binaries.append(enc_i(0x67, 1, 0, 1, lo))

            elif m == "li": 
                rd = reg_num(o[0])
                val = self.resolve_val(o[1], pc)
                if -2048 <= val <= 2047:
                    binaries.append(enc_i(0x13, rd, 0, 0, val))
                else:
                    # lui rd, hi; addi rd, rd, lo
                    lo = val & 0xFFF
                    hi = (val + 0x800) >> 12
                    binaries.append(enc_u(0x37, rd, hi))
                    binaries.append(enc_i(0x13, rd, 0, rd, lo))

            elif m == "la": # lui rd, hi; addi rd, rd, lo (Absolute address load)
                rd = reg_num(o[0])
                val = self.resolve_val(o[1], pc)
                lo = val & 0xFFF
                hi = (val + 0x800) >> 12
                binaries.append(enc_u(0x37, rd, hi))
                binaries.append(enc_i(0x13, rd, 0, rd, lo))

            elif m == "beqz": # beq rs, x0, offset
                rs = reg_num(o[0])
                off = self.resolve_val(o[1], pc) - pc
                binaries.append(enc_b(0x63, 0, rs, 0, off))

            elif m == "bnez": # bne rs, x0, offset
                rs = reg_num(o[0])
                off = self.resolve_val(o[1], pc) - pc
                binaries.append(enc_b(0x63, 1, rs, 0, off))

            # STANDARD INSTRUCTIONS [cite: 71, 79]

            # R-Type
            elif m in ("add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"):
                rd, rs1, rs2 = reg_num(o[0]), reg_num(o[1]), reg_num(o[2])
                DATA = {
                    "add": (0x33,0,0x00), "sub": (0x33,0,0x20), "sll": (0x33,1,0x00),
                    "slt": (0x33,2,0x00), "sltu":(0x33,3,0x00), "xor": (0x33,4,0x00),
                    "srl": (0x33,5,0x00), "sra": (0x33,5,0x20), "or":  (0x33,6,0x00), "and": (0x33,7,0x00)
                }
                op, f3, f7 = DATA[m]
                binaries.append(enc_r(op, rd, f3, rs1, rs2, f7))

            # I-Type Arithmetic
            elif m in ("addi", "slti", "sltiu", "xori", "ori", "andi"):
                rd, rs1 = reg_num(o[0]), reg_num(o[1])
                imm = self.resolve_val(o[2], pc)
                DATA = {
                    "addi": (0x13,0), "slti": (0x13,2), "sltiu":(0x13,3),
                    "xori": (0x13,4), "ori":  (0x13,6), "andi": (0x13,7)
                }
                op, f3 = DATA[m]
                binaries.append(enc_i(op, rd, f3, rs1, imm))

            # I-Type Shift
            elif m in ("slli", "srli", "srai"):
                rd, rs1 = reg_num(o[0]), reg_num(o[1])
                shamt = self.resolve_val(o[2], pc)
                f3 = 1 if m == "slli" else 5
                f7 = 0x20 if m == "srai" else 0x00
                binaries.append(enc_i_shift(0x13, rd, f3, rs1, shamt, f7))

            # Loads
            elif m in ("lb", "lh", "lw", "lbu", "lhu"):
                rd = reg_num(o[0])
                imm, rs1 = self.parse_mem(o[1], pc)
                DATA = {"lb":(0x03,0), "lh":(0x03,1), "lw":(0x03,2), "lbu":(0x03,4), "lhu":(0x03,5)}
                op, f3 = DATA[m]
                binaries.append(enc_i(op, rd, f3, rs1, imm))

            # Stores
            elif m in ("sb", "sh", "sw"):
                rs2 = reg_num(o[0])
                imm, rs1 = self.parse_mem(o[1], pc)
                DATA = {"sb":(0x23,0), "sh":(0x23,1), "sw":(0x23,2)}
                op, f3 = DATA[m]
                binaries.append(enc_s(op, f3, rs1, rs2, imm))

            # Branches
            elif m in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
                rs1, rs2 = reg_num(o[0]), reg_num(o[1])
                off = self.resolve_val(o[2], pc) - pc
                DATA = {
                    "beq": (0x63,0), "bne": (0x63,1), "blt": (0x63,4),
                    "bge": (0x63,5), "bltu":(0x63,6), "bgeu":(0x63,7)
                }
                op, f3 = DATA[m]
                binaries.append(enc_b(op, f3, rs1, rs2, off))

            # U-Type
            elif m in ("lui", "auipc"):
                rd = reg_num(o[0])
                imm = self.resolve_val(o[1], pc) # Expects 20-bit or raw
                # Note: 'lui t0, 0x1' usually means load 0x1 into top 20. 
                # resolve_val returns raw int. enc_u shifts it.
                op = 0x37 if m == "lui" else 0x17
                binaries.append(enc_u(op, rd, imm))

            # J-Type
            elif m == "jal":
                if len(o) == 1: rd, tgt = 1, o[0]
                else: rd, tgt = reg_num(o[0]), o[1]
                off = self.resolve_val(tgt, pc) - pc
                binaries.append(enc_j(0x6F, rd, off))

            elif m == "jalr":
                # jalr rd, imm(rs1)
                if len(o) == 2:
                    rd = reg_num(o[0])
                    imm, rs1 = self.parse_mem(o[1], pc)
                elif len(o) == 3:
                    rd, rs1 = reg_num(o[0]), reg_num(o[1])
                    imm = self.resolve_val(o[2], pc)
                else:
                    raise ValueError("Invalid jalr format")
                binaries.append(enc_i(0x67, rd, 0, rs1, imm))
            
            elif m in ("ecall", "ebreak"):
                binaries.append(0x00000073 if m == "ecall" else 0x00100073)

            else:
                raise ValueError(f"Unsupported instruction: {m}")

        return binaries

def write_little_endian_bytes(filepath: str, words: List[int]) -> None:
    """Write a list of 32-bit words to a file, one byte per line, little-endian.
    e.g. 0x00AD7318 -> 18 / 73 / AD / 00
    """
    with open(filepath, "w") as f:
        for w in words:
            w = w & 0xFFFFFFFF
            f.write(f"{(w >> 0)  & 0xFF:02x}\n")
            f.write(f"{(w >> 8)  & 0xFF:02x}\n")
            f.write(f"{(w >> 16) & 0xFF:02x}\n")
            f.write(f"{(w >> 24) & 0xFF:02x}\n")

# Main

def main():
    if len(sys.argv) != 3:
        print("Usage: python assembler.py <file.s> <out_dir>", file=sys.stderr)
        return 2

    out_dir = sys.argv[2]
    full_path  = sys.argv[1]

    try:
        with open(full_path, "r") as f:
            lines = f.readlines()

        asm = Assembler()
        instr_words, data_words = asm.assemble(lines)

        # instr.txt — instructions only, little-endian, one byte per line
        write_little_endian_bytes(os.path.join(out_dir, "instr.txt"), instr_words)

        # data.txt — .data section words only, little-endian, one byte per line
        write_little_endian_bytes(os.path.join(out_dir, "data.txt"), data_words)

        print(f"Wrote {len(instr_words)} instruction(s) to instr.txt")
        print(f"Wrote {len(data_words)} data word(s) to data.txt")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
