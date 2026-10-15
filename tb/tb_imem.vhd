-- =============================================================================
-- tb_imem.vhd  —  Instruction memory unit test
-- Writes a hex init file then verifies fetch at several addresses.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.tb_pkg.all;

entity tb_imem is
end entity tb_imem;

architecture sim of tb_imem is
    signal clk  : std_logic := '0';
    signal addr : std_logic_vector(31 downto 0) := (others => '0');
    signal instr: std_logic_vector(31 downto 0);

    constant CLK_P    : time := 10 ns;
    constant PROG : prog_t := (
        x"00000013",  -- NOP
        x"DEADBEEF",  -- sentinel
        x"12345678",  -- sentinel 2
        x"CAFEBABE"   -- sentinel 3
    );
    -- Written during elaboration, before IMEM reads it
    constant HEX_FILE : string := write_hex("/tmp/tb_imem.hex", PROG);

begin
    clk <= not clk after CLK_P/2;


    dut: entity work.imem
        generic map (MEM_DEPTH => 256, INIT_FILE => HEX_FILE)
        port map (clk => clk, addr => addr, instr => instr);

    process
        variable errors : natural := 0;
    begin
        addr <= x"00000000";
        wait until rising_edge(clk);
        wait for 1 ns;
        check_cond(instr = x"00000013", "imem[0]", errors);

        addr <= x"00000004";
        wait until rising_edge(clk);
        wait for 1 ns;
        check_cond(instr = x"DEADBEEF", "imem[4]", errors);

        addr <= x"00000008";
        wait until rising_edge(clk);
        wait for 1 ns;
        check_cond(instr = x"12345678", "imem[8]", errors);

        addr <= x"0000000C";
        wait until rising_edge(clk);
        wait for 1 ns;
        check_cond(instr = x"CAFEBABE", "imem[12]", errors);

        -- Uninitialized locations should return NOP
        addr <= x"000000FF";
        wait until rising_edge(clk);
        wait for 1 ns;
        check_cond(instr = x"00000013", "imem[uninitialized]!=NOP", errors);

        finish_test("tb_imem", errors);
        wait;
    end process;
end architecture sim;
