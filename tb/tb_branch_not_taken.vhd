-- =============================================================================
-- tb_branch_not_taken.vhd  —  Tests branches that should NOT be taken
-- Verifies fall-through behaviour for all 6 branch types.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_branch_not_taken is
end entity tb_branch_not_taken;

architecture sim of tb_branch_not_taken is
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal dbg_pc     : std_logic_vector(31 downto 0);
    signal dbg_instr  : std_logic_vector(31 downto 0);
    signal dbg_reg_we : std_logic;
    signal dbg_reg_wa : std_logic_vector(4 downto 0);
    signal dbg_reg_wd : std_logic_vector(31 downto 0);

    type reg_file_t is array(0 to 31) of integer;
    signal regs : reg_file_t := (others => 0);

    constant CLK_P    : time := 10 ns;
    constant HEX_FILE : string := "/tmp/tb_branch_not_taken.hex";

    -- Program: each branch should NOT be taken; the instruction after each
    -- branch sets a PASS register.
    -- x1 = 5, x2 = 10
    -- BEQ  x1,x2: not equal -> fall through  -> x10=1
    -- BNE  x1,x1: equal     -> fall through  -> x11=1
    -- BLT  x2,x1: 10 not < 5 -> fall through -> x12=1
    -- BGE  x1,x2: 5 not >= 10 -> fall through -> x13=1
    -- BLTU x2,x1: 10 not < 5 unsigned -> fall through -> x14=1
    -- BGEU x1,x2: 5 not >= 10 unsigned -> fall through -> x15=1
    -- Each branch target is a distant ERROR marker (addi x29, x0, N)

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 23) := (
        x"00500093",  -- 0x00: addi x1, x0, 5
        x"00A00113",  -- 0x04: addi x2, x0, 10

        -- BEQ x1, x2, +40 (not taken, should fall through)
        x"02208463",  -- 0x08: beq x1, x2, +40
        x"00100513",  -- 0x0C: addi x10, x0, 1   PASS

        -- BNE x1, x1, +40 (not taken)
        x"02109463",  -- 0x10: bne x1, x1, +40
        x"00100593",  -- 0x14: addi x11, x0, 1   PASS

        -- BLT x2, x1 (10 < 5 false, not taken)  +40
        x"0210C463",  -- 0x18: blt x2, x1, +40
        x"00100613",  -- 0x1C: addi x12, x0, 1   PASS

        -- BGE x1, x2 (5 >= 10 false, not taken) +40
        x"0220D463",  -- 0x20: bge x1, x2, +40
        x"00100693",  -- 0x24: addi x13, x0, 1   PASS

        -- BLTU x2, x1 (10 < 5 unsigned false) +40
        x"0210E463",  -- 0x28: bltu x2, x1, +40
        x"00100713",  -- 0x2C: addi x14, x0, 1   PASS

        -- BGEU x1, x2 (5 >= 10 unsigned false) +40
        x"0220F463",  -- 0x30: bgeu x1, x2, +40
        x"00100793",  -- 0x34: addi x15, x0, 1   PASS

        x"00000013",  -- 0x38 nop
        x"00000013",  -- 0x3C nop
        -- Error target (if any branch is wrongly taken):
        x"00100E93",  -- 0x40: addi x29, x0, 1   ERROR sentinel
        x"00000013",
        x"00000013",
        x"00000013",
        x"00000013",
        x"00000013",
        x"00000013",
        x"00000013"
    );

begin
    clk <= not clk after CLK_P/2;

    process
        file fh : text open WRITE_MODE is HEX_FILE;
        variable l : line;
    begin
        for i in PROG'range loop
            hwrite(l, PROG(i));
            writeline(fh, l);
        end loop;
        file_close(fh);
        wait;
    end process;

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
            if dbg_reg_we = '1' and unsigned(dbg_reg_wa) /= 0 then
                regs(to_integer(unsigned(dbg_reg_wa))) <=
                    to_integer(signed(dbg_reg_wd));
            end if;
        end if;
    end process;

    process
    begin
        rst <= '1';
        wait for 3 * CLK_P;
        rst <= '0';
        wait for 60 * CLK_P;

        assert regs(29) = 0  report "FAIL: wrong branch taken (x29 != 0)" severity error;
        assert regs(10) = 1  report "FAIL BEQ fall-through"  severity error;
        assert regs(11) = 1  report "FAIL BNE fall-through"  severity error;
        assert regs(12) = 1  report "FAIL BLT fall-through"  severity error;
        assert regs(13) = 1  report "FAIL BGE fall-through"  severity error;
        assert regs(14) = 1  report "FAIL BLTU fall-through" severity error;
        assert regs(15) = 1  report "FAIL BGEU fall-through" severity error;

        report "=== tb_branch_not_taken PASS ===" severity note;
        wait;
    end process;
end architecture sim;
