-- =============================================================================
-- tb_control_unit.vhd  —  Unit tests for the instruction decoder
-- Verifies every opcode produces the correct control signals and immediate.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

entity tb_control_unit is
end entity tb_control_unit;

architecture sim of tb_control_unit is
    signal instr    : std_logic_vector(31 downto 0) := (others => '0');
    signal imm      : std_logic_vector(31 downto 0);
    signal rs1, rs2 : std_logic_vector(4 downto 0);
    signal rd       : std_logic_vector(4 downto 0);
    signal ctrl_ex  : ctrl_ex_t;
    signal ctrl_mem : ctrl_mem_t;
    signal ctrl_wb  : ctrl_wb_t;
    signal is_auipc : std_logic;

    procedure chk_ctrl(
        instr_in     : std_logic_vector(31 downto 0);
        exp_alu_src  : std_logic;
        exp_reg_write: std_logic;
        exp_mem_read : std_logic;
        exp_mem_write: std_logic;
        exp_branch   : std_logic;
        exp_jump     : std_logic;
        msg          : string) is
    begin
        instr <= instr_in;
        wait for 5 ns;
        assert ctrl_ex.alu_src     = exp_alu_src   report "FAIL " & msg & " alu_src"   severity error;
        assert ctrl_wb.reg_write   = exp_reg_write  report "FAIL " & msg & " reg_write" severity error;
        assert ctrl_mem.mem_read   = exp_mem_read   report "FAIL " & msg & " mem_read"  severity error;
        assert ctrl_mem.mem_write  = exp_mem_write  report "FAIL " & msg & " mem_write" severity error;
        assert ctrl_mem.branch     = exp_branch     report "FAIL " & msg & " branch"    severity error;
        assert ctrl_mem.jump       = exp_jump       report "FAIL " & msg & " jump"      severity error;
        report "PASS " & msg severity note;
    end procedure;

begin
    dut: entity work.control_unit
        port map (instr => instr, imm => imm, rs1 => rs1, rs2 => rs2, rd => rd,
                  ctrl_ex => ctrl_ex, ctrl_mem => ctrl_mem, ctrl_wb => ctrl_wb,
                  is_auipc => is_auipc);

    process
    begin
        -- R-type: ADD x3, x1, x2
        --         alu_src=0, reg_write=1, mem_read=0, mem_write=0, branch=0, jump=0
        chk_ctrl(x"002081B3", '0','1','0','0','0','0', "ADD");

        -- I-type: ADDI x1, x0, 100
        chk_ctrl(x"06400093", '1','1','0','0','0','0', "ADDI");

        -- LUI x1, 0xABCDE
        chk_ctrl(x"ABCDE0B7", '1','1','0','0','0','0', "LUI");
        instr <= x"ABCDE0B7";
        wait for 5 ns;
        assert imm = x"ABCDE000" report "FAIL LUI immediate" severity error;
        report "PASS LUI immediate" severity note;

        -- AUIPC x2, 0x10
        chk_ctrl(x"00010117", '1','1','0','0','0','0', "AUIPC");
        instr <= x"00010117";
        wait for 5 ns;
        assert is_auipc = '1' report "FAIL AUIPC flag" severity error;
        assert imm = x"00010000" report "FAIL AUIPC immediate" severity error;
        report "PASS AUIPC" severity note;

        -- LOAD: LW x2, 8(x1)
        chk_ctrl(x"00802103", '1','1','1','0','0','0', "LW");
        instr <= x"00802103";
        wait for 5 ns;
        assert imm = x"00000008" report "FAIL LW immediate" severity error;
        assert ctrl_wb.mem_to_reg = '1' report "FAIL LW mem_to_reg" severity error;
        report "PASS LW ctrl" severity note;

        -- STORE: SW x2, 8(x1) -> imm=8
        chk_ctrl(x"00212423", '1','0','0','1','0','0', "SW");
        instr <= x"00212423";
        wait for 5 ns;
        assert imm = x"00000008" report "FAIL SW immediate" severity error;
        report "PASS SW ctrl" severity note;

        -- BRANCH: BEQ x1, x2, +8
        chk_ctrl(x"00208463", '0','0','0','0','1','0', "BEQ");
        instr <= x"00208463";
        wait for 5 ns;
        assert imm = x"00000008" report "FAIL BEQ immediate" severity error;
        report "PASS BEQ ctrl" severity note;

        -- JAL x1, +12
        chk_ctrl(x"00C000EF", '1','1','0','0','0','1', "JAL");

        -- JALR x2, x1, 4
        chk_ctrl(x"00408167", '1','1','0','0','0','1', "JALR");
        instr <= x"00408167";
        wait for 5 ns;
        assert ctrl_ex.is_jalr = '1' report "FAIL JALR flag" severity error;
        report "PASS JALR flag" severity note;

        -- NOP (ADDI x0, x0, 0) -> reg_write='1' but rd=x0 (hardware guards)
        chk_ctrl(x"00000013", '1','1','0','0','0','0', "NOP");

        -- FENCE: all zeros except opcode  -> nothing written
        chk_ctrl(x"0FF0000F", '0','0','0','0','0','0', "FENCE");

        -- ECALL
        chk_ctrl(x"00000073", '0','0','0','0','0','0', "ECALL");

        report "=== tb_control_unit PASS ===" severity note;
        wait;
    end process;
end architecture sim;
