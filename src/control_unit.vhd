-- =============================================================================
-- control_unit.vhd  —  Instruction decode and control signal generation
-- Combinatorial block; sits in the ID stage.
-- Covers all 40 RV32I instructions.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

entity control_unit is
    port (
        instr      : in  std_logic_vector(31 downto 0);
        -- Immediate value (sign-extended)
        imm        : out std_logic_vector(31 downto 0);
        -- Register addresses
        rs1        : out std_logic_vector(4 downto 0);
        rs2        : out std_logic_vector(4 downto 0);
        rd         : out std_logic_vector(4 downto 0);
        -- Control bundles
        ctrl_ex    : out ctrl_ex_t;
        ctrl_mem   : out ctrl_mem_t;
        ctrl_wb    : out ctrl_wb_t;
        -- AUIPC flag (needs PC in EX stage)
        is_auipc   : out std_logic
    );
end entity control_unit;

architecture rtl of control_unit is
    signal opcode : std_logic_vector(6 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);
begin
    opcode <= instr(6 downto 0);
    funct3 <= instr(14 downto 12);
    funct7 <= instr(31 downto 25);

    rs1 <= instr(19 downto 15);
    rs2 <= instr(24 downto 20);
    rd  <= instr(11 downto  7);

    -- -------------------------------------------------------------------------
    -- Immediate generation
    -- -------------------------------------------------------------------------
    process(instr, opcode)
    begin
        case opcode is
            when OP_IMM | OP_LOAD | OP_JALR =>   -- I-type
                imm <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));

            when OP_STORE =>                       -- S-type
                imm <= std_logic_vector(resize(
                    signed(instr(31 downto 25) & instr(11 downto 7)), 32));

            when OP_BRANCH =>                      -- B-type
                imm <= std_logic_vector(resize(
                    signed(instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0'),
                    32));

            when OP_LUI | OP_AUIPC =>              -- U-type
                imm <= instr(31 downto 12) & x"000";

            when OP_JAL =>                         -- J-type
                imm <= std_logic_vector(resize(
                    signed(instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0'),
                    32));

            when others =>                         -- R-type: no immediate needed
                imm <= (others => '0');
        end case;
    end process;

    -- -------------------------------------------------------------------------
    -- ALU op decode helper
    -- -------------------------------------------------------------------------
    -- Shared between OP_REG and OP_IMM (shift-right disambiguation via funct7)
    -- -------------------------------------------------------------------------

    -- -------------------------------------------------------------------------
    -- Main control decode
    -- -------------------------------------------------------------------------
    process(opcode, funct3, funct7)
        variable ex  : ctrl_ex_t;
        variable mem : ctrl_mem_t;
        variable wb  : ctrl_wb_t;
        variable apc : std_logic;
    begin
        -- Defaults (NOP-safe)
        ex  := CTRL_EX_NOP;
        mem := CTRL_MEM_NOP;
        wb  := CTRL_WB_NOP;
        apc := '0';

        case opcode is

            -- -----------------------------------------------------------------
            -- R-type: ADD SUB SLL SLT SLTU XOR SRL SRA OR AND
            -- -----------------------------------------------------------------
            when OP_REG =>
                ex.alu_src  := '0';
                wb.reg_write := '1';
                case funct3 is
                    when F3_ADD_SUB =>
                        if funct7(5) = '1' then ex.alu_op := ALU_SUB;
                        else                     ex.alu_op := ALU_ADD;
                        end if;
                    when F3_SLL     => ex.alu_op := ALU_SLL;
                    when F3_SLT     => ex.alu_op := ALU_SLT;
                    when F3_SLTU    => ex.alu_op := ALU_SLTU;
                    when F3_XOR     => ex.alu_op := ALU_XOR;
                    when F3_SRL_SRA =>
                        if funct7(5) = '1' then ex.alu_op := ALU_SRA;
                        else                     ex.alu_op := ALU_SRL;
                        end if;
                    when F3_OR      => ex.alu_op := ALU_OR;
                    when F3_AND     => ex.alu_op := ALU_AND;
                    when others     => null;
                end case;

            -- -----------------------------------------------------------------
            -- I-type ALU: ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
            -- -----------------------------------------------------------------
            when OP_IMM =>
                ex.alu_src   := '1';
                wb.reg_write := '1';
                case funct3 is
                    when F3_ADD_SUB => ex.alu_op := ALU_ADD;   -- ADDI
                    when F3_SLT     => ex.alu_op := ALU_SLT;   -- SLTI
                    when F3_SLTU    => ex.alu_op := ALU_SLTU;  -- SLTIU
                    when F3_XOR     => ex.alu_op := ALU_XOR;   -- XORI
                    when F3_OR      => ex.alu_op := ALU_OR;    -- ORI
                    when F3_AND     => ex.alu_op := ALU_AND;   -- ANDI
                    when F3_SLL     => ex.alu_op := ALU_SLL;   -- SLLI
                    when F3_SRL_SRA =>
                        if funct7(5) = '1' then ex.alu_op := ALU_SRA;  -- SRAI
                        else                     ex.alu_op := ALU_SRL;  -- SRLI
                        end if;
                    when others => null;
                end case;

            -- -----------------------------------------------------------------
            -- LUI
            -- -----------------------------------------------------------------
            when OP_LUI =>
                ex.alu_src   := '1';
                ex.alu_op    := ALU_PASSB;
                wb.reg_write := '1';

            -- -----------------------------------------------------------------
            -- AUIPC
            -- -----------------------------------------------------------------
            when OP_AUIPC =>
                ex.alu_src   := '1';
                ex.alu_op    := ALU_ADD;   -- PC + imm computed in EX using pc_ex
                wb.reg_write := '1';
                apc          := '1';

            -- -----------------------------------------------------------------
            -- JAL
            -- -----------------------------------------------------------------
            when OP_JAL =>
                ex.alu_src   := '1';
                ex.alu_op    := ALU_ADD;   -- branch target = PC + imm
                mem.jump     := '1';
                wb.reg_write := '1';       -- rd = PC+4

            -- -----------------------------------------------------------------
            -- JALR
            -- -----------------------------------------------------------------
            when OP_JALR =>
                ex.alu_src   := '1';
                ex.alu_op    := ALU_ADD;   -- target = RS1 + imm
                ex.is_jalr   := '1';
                mem.jump     := '1';
                wb.reg_write := '1';

            -- -----------------------------------------------------------------
            -- Branches: BEQ BNE BLT BGE BLTU BGEU
            -- -----------------------------------------------------------------
            when OP_BRANCH =>
                ex.alu_src  := '0';
                mem.branch  := '1';
                -- funct3 passed through mem.mem_size for branch condition eval
                mem.mem_size := funct3;

            -- -----------------------------------------------------------------
            -- Loads: LB LH LW LBU LHU
            -- -----------------------------------------------------------------
            when OP_LOAD =>
                ex.alu_src      := '1';
                ex.alu_op       := ALU_ADD;   -- address = RS1 + imm
                mem.mem_read    := '1';
                mem.mem_size    := funct3;
                wb.reg_write    := '1';
                wb.mem_to_reg   := '1';

            -- -----------------------------------------------------------------
            -- Stores: SB SH SW
            -- -----------------------------------------------------------------
            when OP_STORE =>
                ex.alu_src      := '1';
                ex.alu_op       := ALU_ADD;   -- address = RS1 + imm
                mem.mem_write   := '1';
                mem.mem_size    := funct3;

            -- -----------------------------------------------------------------
            -- FENCE  — treated as NOP (memory ordering; no out-of-order here)
            -- SYSTEM — ECALL/EBREAK treated as NOP for hardware impl
            -- -----------------------------------------------------------------
            when OP_FENCE | OP_SYSTEM => null;

            when others => null;
        end case;

        ctrl_ex   <= ex;
        ctrl_mem  <= mem;
        ctrl_wb   <= wb;
        is_auipc  <= apc;
    end process;

end architecture rtl;
