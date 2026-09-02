-- =============================================================================
-- tb_imem.vhd  —  Instruction memory unit test
-- Writes a hex init file then verifies fetch at several addresses.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_imem is
end entity tb_imem;

architecture sim of tb_imem is
    signal clk  : std_logic := '0';
    signal addr : std_logic_vector(31 downto 0) := (others => '0');
    signal instr: std_logic_vector(31 downto 0);

    constant CLK_P    : time := 10 ns;
    constant HEX_FILE : string := "/tmp/tb_imem.hex";

    type prog_t is array(0 to 3) of std_logic_vector(31 downto 0);
    constant PROG : prog_t := (
        x"00000013",  -- NOP
        x"DEADBEEF",  -- sentinel
        x"12345678",  -- sentinel 2
        x"CAFEBABE"   -- sentinel 3
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

    dut: entity work.imem
        generic map (MEM_DEPTH => 256, INIT_FILE => HEX_FILE)
        port map (clk => clk, addr => addr, instr => instr);

    process
    begin
        addr <= x"00000000";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert instr = x"00000013" report "FAIL imem[0]" severity error;
        report "PASS imem[0]=NOP" severity note;

        addr <= x"00000004";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert instr = x"DEADBEEF" report "FAIL imem[4]" severity error;
        report "PASS imem[4]=0xDEADBEEF" severity note;

        addr <= x"00000008";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert instr = x"12345678" report "FAIL imem[8]" severity error;
        report "PASS imem[8]=0x12345678" severity note;

        addr <= x"0000000C";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert instr = x"CAFEBABE" report "FAIL imem[12]" severity error;
        report "PASS imem[12]=0xCAFEBABE" severity note;

        -- Uninitialized locations should return NOP
        addr <= x"000000FF";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert instr = x"00000013" report "FAIL imem[uninitialized]!=NOP" severity error;
        report "PASS imem[uninitialized]=NOP" severity note;

        report "=== tb_imem PASS ===" severity note;
        wait;
    end process;
end architecture sim;
