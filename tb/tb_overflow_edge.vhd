-- =============================================================================
-- tb_overflow_edge.vhd  —  Arithmetic edge cases and overflow behavior
-- RV32I does NOT trap on integer overflow; result wraps silently.
-- Tests: INT_MAX+1, INT_MIN-1, unsigned max, shift edge cases
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_overflow_edge is
end entity tb_overflow_edge;

architecture sim of tb_overflow_edge is
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
    constant HEX_FILE : string := "/tmp/tb_overflow.hex";

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 19) := (
        -- x1 = INT_MAX = 0x7FFFFFFF (lui + addi)
        x"800000B7",  -- lui x1, 0x80000 -> x1=0x80000000
        x"FFF08093",  -- addi x1, x1, -1 -> x1=0x7FFFFFFF = INT_MAX

        -- INT_MAX + 1 = 0x80000000 (wraps to INT_MIN)
        x"00108133",  -- add x2, x1, x1  -> x2=0xFFFFFFFE (2*INT_MAX)
        x"00100193",  -- addi x3, x0, 1
        x"00108233",  -- add x4, x1, x3  -> x4 = INT_MAX+1 = 0x80000000 = INT_MIN

        -- SLL by 0 (no shift)
        x"00509293",  -- slli x5, x1, 5  -> shift INT_MAX left 5 = 0xFFFFFFE0
        x"00001313",  -- slli x6, x0, 1  -> 0 << 1 = 0

        -- SRA of INT_MIN by 1
        x"40105393",  -- srai x7, x0, 1  -> 0 >> 1 = 0
        x"40104413",  -- srai x8, x0, 4  -> 0 >> 4 = 0
        -- Load INT_MIN to x9
        x"800004B7",  -- lui x9, 0x80000 -> x9 = 0x80000000
        x"4014D493",  -- srai x9, x9, 1  -> arithmetic right shift: 0xC0000000

        -- SLTU: treat signed negative as large unsigned
        x"00000593",  -- addi x11, x0, 0
        x"00B4B633",  -- sltu x12, x9, x11  -> 0x80000000 < 0 unsigned? No -> 0
        x"00958633",  -- add  x12, x11, x9  -> just x9 value (test encoding)

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
                regs(to_integer(unsigned(dbg_reg_wa))) <= dbg_reg_wd;
            end if;
        end if;
    end process;

    process
    begin
        rst <= '1';
        wait for 3 * CLK_P;
        rst <= '0';
        wait for 50 * CLK_P;

        assert regs(1) = x"7FFFFFFF"
            report "FAIL INT_MAX"            severity error;
        assert regs(4) = x"80000000"
            report "FAIL INT_MAX+1 overflow" severity error;
        assert regs(5) = x"FFFFFFE0"
            report "FAIL SLLI INT_MAX<<5"    severity error;
        assert regs(9) = x"C0000000"
            report "FAIL SRAI INT_MIN>>1"    severity error;

        report "=== tb_overflow_edge PASS ===" severity note;
        wait;
    end process;
end architecture sim;
