-- =============================================================================
-- tb_branch_with_forwarding.vhd  —  Branch uses forwarded value as comparand
-- The branch condition operands come from instructions still in the pipeline.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_branch_with_forwarding is
end entity tb_branch_with_forwarding;

architecture sim of tb_branch_with_forwarding is
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
    constant HEX_FILE : string := "/tmp/tb_branch_fwd.hex";

    -- Program:
    -- addi x1, x0, 5    x1=5
    -- addi x2, x1, 0    x2=5 (depends on x1, forwarded)
    -- beq  x1, x2, +8   branch taken (x1==x2==5, both may be forwarded)
    -- addi x29, x0, 1   ERROR if reached
    -- addi x10, x0, 1   PASS: x10=1

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 9) := (
        x"00500093",  -- addi x1, x0, 5
        x"00008113",  -- addi x2, x1, 0   x2=x1 (forwarded)
        -- BEQ x1, x2, +8 from 0x08 = target 0x10
        -- offset=8: [31]=0,[30:25]=000000,rs2=x2=00010,rs1=x1=00001,funct3=000,[11:8]=0100,[7]=0
        -- = 0000 0000 0010 0000 1000 0100 0110 0011 = 0x00208463
        x"00208463",  -- beq x1, x2, +8
        x"00100E93",  -- addi x29, x0, 1  ERROR
        x"00100513",  -- addi x10, x0, 1  PASS
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

        assert regs(29) = 0 report "FAIL: wrong path executed" severity error;
        assert regs(10) = 1 report "FAIL: branch with forwarding" severity error;

        report "=== tb_branch_with_forwarding PASS ===" severity note;
        wait;
    end process;
end architecture sim;
