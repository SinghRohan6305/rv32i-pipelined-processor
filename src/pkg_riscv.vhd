-- =============================================================================
-- pkg_riscv.vhd  —  Shared constants and types for the RV32I pipeline
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pkg_riscv is

    -- -------------------------------------------------------------------------
    -- Opcodes (inst[6:0])
    -- -------------------------------------------------------------------------
    constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant OP_IMM    : std_logic_vector(6 downto 0) := "0010011";
    constant OP_REG    : std_logic_vector(6 downto 0) := "0110011";
    constant OP_FENCE  : std_logic_vector(6 downto 0) := "0001111";
    constant OP_SYSTEM : std_logic_vector(6 downto 0) := "1110011";

    -- -------------------------------------------------------------------------
    -- Funct3 encodings
    -- -------------------------------------------------------------------------
    -- Branches
    constant F3_BEQ  : std_logic_vector(2 downto 0) := "000";
    constant F3_BNE  : std_logic_vector(2 downto 0) := "001";
    constant F3_BLT  : std_logic_vector(2 downto 0) := "100";
    constant F3_BGE  : std_logic_vector(2 downto 0) := "101";
    constant F3_BLTU : std_logic_vector(2 downto 0) := "110";
    constant F3_BGEU : std_logic_vector(2 downto 0) := "111";

    -- Loads
    constant F3_LB  : std_logic_vector(2 downto 0) := "000";
    constant F3_LH  : std_logic_vector(2 downto 0) := "001";
    constant F3_LW  : std_logic_vector(2 downto 0) := "010";
    constant F3_LBU : std_logic_vector(2 downto 0) := "100";
    constant F3_LHU : std_logic_vector(2 downto 0) := "101";

    -- Stores
    constant F3_SB : std_logic_vector(2 downto 0) := "000";
    constant F3_SH : std_logic_vector(2 downto 0) := "001";
    constant F3_SW : std_logic_vector(2 downto 0) := "010";

    -- ALU immediate / register (shared funct3)
    constant F3_ADD_SUB : std_logic_vector(2 downto 0) := "000";
    constant F3_SLL     : std_logic_vector(2 downto 0) := "001";
    constant F3_SLT     : std_logic_vector(2 downto 0) := "010";
    constant F3_SLTU    : std_logic_vector(2 downto 0) := "011";
    constant F3_XOR     : std_logic_vector(2 downto 0) := "100";
    constant F3_SRL_SRA : std_logic_vector(2 downto 0) := "101";
    constant F3_OR      : std_logic_vector(2 downto 0) := "110";
    constant F3_AND     : std_logic_vector(2 downto 0) := "111";

    -- -------------------------------------------------------------------------
    -- ALU operation codes (4-bit)
    -- -------------------------------------------------------------------------
    constant ALU_ADD  : std_logic_vector(3 downto 0) := "0000";
    constant ALU_SUB  : std_logic_vector(3 downto 0) := "0001";
    constant ALU_AND  : std_logic_vector(3 downto 0) := "0010";
    constant ALU_OR   : std_logic_vector(3 downto 0) := "0011";
    constant ALU_XOR  : std_logic_vector(3 downto 0) := "0100";
    constant ALU_SLL  : std_logic_vector(3 downto 0) := "0101";
    constant ALU_SRL  : std_logic_vector(3 downto 0) := "0110";
    constant ALU_SRA  : std_logic_vector(3 downto 0) := "0111";
    constant ALU_SLT  : std_logic_vector(3 downto 0) := "1000";
    constant ALU_SLTU : std_logic_vector(3 downto 0) := "1001";
    constant ALU_PASSB: std_logic_vector(3 downto 0) := "1010";  -- LUI: result = B
    constant ALU_NOP  : std_logic_vector(3 downto 0) := "1111";

    -- -------------------------------------------------------------------------
    -- Forwarding mux selects (2-bit)
    -- -------------------------------------------------------------------------
    constant FWD_REG    : std_logic_vector(1 downto 0) := "00";  -- from register file
    constant FWD_WB     : std_logic_vector(1 downto 0) := "01";  -- from MEM/WB
    constant FWD_MEM    : std_logic_vector(1 downto 0) := "10";  -- from EX/MEM

    -- -------------------------------------------------------------------------
    -- NOP instruction: ADDI x0, x0, 0 = 0x00000013
    -- -------------------------------------------------------------------------
    constant NOP_INSTR : std_logic_vector(31 downto 0) := x"00000013";

    -- -------------------------------------------------------------------------
    -- Pipeline control bundle types (passed through pipeline registers)
    -- -------------------------------------------------------------------------

    -- EX-stage controls
    type ctrl_ex_t is record
        alu_op  : std_logic_vector(3 downto 0);
        alu_src : std_logic;   -- 0 = RS2, 1 = immediate
        is_jalr : std_logic;   -- special: PC = RS1 + imm (uses ALU ADD)
    end record;

    -- MEM-stage controls
    type ctrl_mem_t is record
        mem_read  : std_logic;
        mem_write : std_logic;
        mem_size  : std_logic_vector(2 downto 0);  -- funct3 determines byte/half/word + signed
        branch    : std_logic;
        jump      : std_logic;  -- JAL or JALR: always write PC+4 to rd
    end record;

    -- WB-stage controls
    type ctrl_wb_t is record
        reg_write  : std_logic;
        mem_to_reg : std_logic;  -- 0 = ALU result, 1 = memory data
    end record;

    -- Null/bubble control values
    constant CTRL_EX_NOP  : ctrl_ex_t  := (alu_op => ALU_ADD, alu_src => '0', is_jalr => '0');
    constant CTRL_MEM_NOP : ctrl_mem_t := (mem_read => '0', mem_write => '0',
                                            mem_size => "010", branch => '0', jump => '0');
    constant CTRL_WB_NOP  : ctrl_wb_t  := (reg_write => '0', mem_to_reg => '0');

end package pkg_riscv;
