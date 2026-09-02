-- =============================================================================
-- tb_lui_auipc.vhd  —  Tests LUI and AUIPC
-- LUI  x1, 0xDEADB   -> x1 = 0xDEADB000
-- AUIPC x2, 4        -> x2 = PC_at_instr + 0x4000 = 4 + 0x4000 = 0x4004
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_lui_auipc is
end entity tb_lui_auipc;

architecture sim of tb_lui_auipc is
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal dbg_pc     : std_logic_vector(31 downto 0);
    signal dbg_instr  : std_logic_vector(31 downto 0);
    signal dbg_reg_we : std_logic;
    signal dbg_reg_wa : std_logic_vector(4 downto 0);
    signal dbg_reg_wd : std_logic_vector(31 downto 0);

    type reg_file_t is array(0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_file_t := (others => (others => '0'));

    constant CLK_P    : time := 10 ns;
    constant HEX_FILE : string := "/tmp/tb_lui_auipc.hex";

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 7) := (
        -- PC=0x00: LUI x1, 0xDEADB => x1 = 0xDEADB000
        x"DEADB0B7",  -- 0x00
        -- PC=0x04: AUIPC x2, 4 => x2 = 0x04 + 0x4000 = 0x4004
        x"00004117",  -- 0x04
        -- PC=0x08: AUIPC x3, 0 => x3 = 0x08
        x"00000197",  -- 0x08
        -- PC=0x0C: LUI x4, 0xFFFFF => x4 = 0xFFFFF000 = -4096
        x"FFFFF237",  -- 0x0C
        -- PC=0x10: LUI x5, 0 => x5 = 0
        x"000002B7",  -- 0x10
        x"00000013",  -- nop
        x"00000013",  -- nop
        x"00000013"   -- nop
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
                regs(to_integer(unsigned(dbg_reg_wa))) <= dbg_reg_wd;
            end if;
        end if;
    end process;

    process
    begin
        rst <= '1';
        wait for 3 * CLK_P;
        rst <= '0';
        wait for 20 * CLK_P;

        assert regs(1) = x"DEADB000"
            report "FAIL LUI x1=0xDEADB000" severity error;
        assert regs(2) = x"00004004"
            report "FAIL AUIPC x2=0x4004" severity error;
        assert regs(3) = x"00000008"
            report "FAIL AUIPC x3=0x8" severity error;
        assert regs(4) = x"FFFFF000"
            report "FAIL LUI x4=0xFFFFF000" severity error;
        assert regs(5) = x"00000000"
            report "FAIL LUI x5=0" severity error;

        report "=== tb_lui_auipc PASS ===" severity note;
        wait;
    end process;
end architecture sim;
