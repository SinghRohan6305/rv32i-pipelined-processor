-- =============================================================================
-- tb_fence_system.vhd  —  FENCE and SYSTEM (ECALL/EBREAK) treated as NOP
-- Verifies pipeline continues executing correctly after FENCE/ECALL/EBREAK.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_fence_system is
end entity tb_fence_system;

architecture sim of tb_fence_system is
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
    constant HEX_FILE : string := "/tmp/tb_fence_system.hex";

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 11) := (
        x"00500093",  -- addi x1, x0, 5
        x"0FF0000F",  -- FENCE (all bits set)
        x"00A00113",  -- addi x2, x0, 10   should execute after FENCE
        x"00000073",  -- ECALL
        x"01400193",  -- addi x3, x0, 20   should execute after ECALL
        x"00100073",  -- EBREAK
        x"01E00213",  -- addi x4, x0, 30   should execute after EBREAK
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
        wait for 30 * CLK_P;

        assert regs(1) = 5  report "FAIL x1=5 before FENCE"   severity error;
        assert regs(2) = 10 report "FAIL x2=10 after FENCE"   severity error;
        assert regs(3) = 20 report "FAIL x3=20 after ECALL"   severity error;
        assert regs(4) = 30 report "FAIL x4=30 after EBREAK"  severity error;

        report "=== tb_fence_system PASS ===" severity note;
        wait;
    end process;
end architecture sim;
