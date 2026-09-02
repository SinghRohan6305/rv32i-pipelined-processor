-- =============================================================================
-- tb_hazard_raw.vhd  —  RAW hazard forwarding: back-to-back dependent instructions
-- Tests that 2-stage forwarding produces correct results with NO stalls
-- for EX→EX and MEM→EX forwarding paths.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_hazard_raw is
end entity tb_hazard_raw;

architecture sim of tb_hazard_raw is
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
    constant HEX_FILE : string := "/tmp/tb_hazard_raw.hex";

    -- Program - back-to-back RAW dependencies requiring forwarding:
    -- Test 1: EX/MEM → EX forwarding (1-cycle-old result)
    --   addi x1, x0, 10   x1 = 10
    --   addi x1, x1, 5    x1 = 15  (reads x1 from EX/MEM forward)
    --   addi x1, x1, 3    x1 = 18  (reads x1 from EX/MEM forward again)
    --
    -- Test 2: MEM/WB → EX forwarding (2-cycle-old result)
    --   addi x2, x0, 100
    --   addi x3, x0, 0    (no dependency, just spacer)
    --   add  x4, x2, x3   (x2 from MEM/WB = 100, x3 = 0)  -> x4 = 100
    --
    -- Test 3: Triple chain
    --   addi x5, x0, 1
    --   add  x6, x5, x5   x6 = 2  (double forward of x5)
    --   add  x7, x6, x5   x7 = 3  (x6 from EX/MEM, x5 from MEM/WB)
    --   add  x8, x7, x6   x8 = 5  (x7 from EX/MEM, x6 from MEM/WB)

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 19) := (
        -- Test 1
        x"00A00093",  -- addi x1, x0, 10
        x"00508093",  -- addi x1, x1, 5
        x"00308093",  -- addi x1, x1, 3    -> x1 = 18

        -- Test 2
        x"06400113",  -- addi x2, x0, 100
        x"00000193",  -- addi x3, x0, 0
        x"00310233",  -- add  x4, x2, x3   -> x4 = 100

        -- Test 3
        x"00100293",  -- addi x5, x0, 1
        x"005282B3",  -- add  x6, x5, x5   -> x6 = 2
        x"00528383",  -- add  x7, x5, x6   -> x7 = 3   (Note: x5 from MEM/WB, x6 from EX/MEM? or both from different stages)
        x"00630433",  -- add  x8, x6, x7   -> x8 = 5

        x"00000013",  -- nop
        x"00000013",  -- nop
        x"00000013",  -- nop
        x"00000013",  -- nop
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
        wait for 40 * CLK_P;

        assert regs(1) = 18  report "FAIL forwarding chain x1=18"  severity error;
        assert regs(4) = 100 report "FAIL 2-cycle fwd x4=100" severity error;
        assert regs(5) = 1   report "FAIL x5=1"   severity error;
        assert regs(6) = 2   report "FAIL x6=2"   severity error;
        assert regs(7) = 3   report "FAIL x7=3"   severity error;
        assert regs(8) = 5   report "FAIL x8=5"   severity error;

        report "=== tb_hazard_raw PASS ===" severity note;
        wait;
    end process;
end architecture sim;
