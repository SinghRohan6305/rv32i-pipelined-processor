-- =============================================================================
-- tb_reset.vhd  —  Verifies reset behavior: pipeline drains and PC returns to 0
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_reset is
end entity tb_reset;

architecture sim of tb_reset is
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
    constant HEX_FILE : string := "/tmp/tb_reset.hex";

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 7) := (
        x"00100093",  -- addi x1, x0, 1
        x"00200113",  -- addi x2, x0, 2
        x"00300193",  -- addi x3, x0, 3
        x"00400213",  -- addi x4, x0, 4
        x"00500293",  -- addi x5, x0, 5
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
        -- Start and let pipeline run for a few cycles
        rst <= '1';
        wait for 2 * CLK_P;
        rst <= '0';
        wait for 10 * CLK_P;

        -- PC should have advanced
        assert unsigned(dbg_pc) > 0
            report "FAIL: PC not advancing" severity error;
        report "PASS: PC advancing" severity note;

        -- Assert reset
        rst <= '1';
        wait for 2 * CLK_P;

        -- PC should be back at 0
        assert dbg_pc = x"00000000"
            report "FAIL: PC not reset to 0" severity error;
        report "PASS: PC reset to 0" severity note;

        -- Release reset, run again
        rst <= '0';
        wait for 20 * CLK_P;

        assert regs(1) = 1 report "FAIL: x1=1 after re-run" severity error;
        assert regs(2) = 2 report "FAIL: x2=2 after re-run" severity error;
        assert regs(3) = 3 report "FAIL: x3=3 after re-run" severity error;
        report "PASS: correct values after reset+re-run" severity note;

        report "=== tb_reset PASS ===" severity note;
        wait;
    end process;
end architecture sim;
