-- =============================================================================
-- tb_regfile.vhd  —  Unit tests for the register file
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_regfile is
end entity tb_regfile;

architecture sim of tb_regfile is
    signal clk : std_logic := '0';
    signal we  : std_logic := '0';
    signal wa  : std_logic_vector(4 downto 0) := (others => '0');
    signal wd  : std_logic_vector(31 downto 0) := (others => '0');
    signal ra1 : std_logic_vector(4 downto 0) := (others => '0');
    signal rd1 : std_logic_vector(31 downto 0);
    signal ra2 : std_logic_vector(4 downto 0) := (others => '0');
    signal rd2 : std_logic_vector(31 downto 0);

    constant CLK_P : time := 10 ns;
begin
    clk <= not clk after CLK_P/2;

    dut: entity work.regfile
        port map (clk=>clk, we=>we, wa=>wa, wd=>wd, ra1=>ra1, rd1=>rd1, ra2=>ra2, rd2=>rd2);

    process
    begin
        -- x0 always reads as 0
        we <= '1'; wa <= "00000"; wd <= x"DEADBEEF";
        wait until rising_edge(clk);
        we <= '0';
        ra1 <= "00000";
        wait for 1 ns;
        assert rd1 = x"00000000" report "FAIL: x0 must be 0" severity error;
        report "PASS: x0 = 0" severity note;

        -- Write x1 = 0xABCD1234, read back
        we <= '1'; wa <= "00001"; wd <= x"ABCD1234";
        wait until rising_edge(clk);
        we <= '0';
        ra1 <= "00001";
        wait for 1 ns;
        assert rd1 = x"ABCD1234" report "FAIL: x1 read-back" severity error;
        report "PASS: x1 read-back" severity note;

        -- Write x2, read both ports simultaneously
        we <= '1'; wa <= "00010"; wd <= x"CAFEBABE";
        wait until rising_edge(clk);
        we <= '0';
        ra1 <= "00001";
        ra2 <= "00010";
        wait for 1 ns;
        assert rd1 = x"ABCD1234" report "FAIL: x1 simultaneous read" severity error;
        assert rd2 = x"CAFEBABE" report "FAIL: x2 simultaneous read" severity error;
        report "PASS: dual read" severity note;

        -- Write-through forwarding: write and read same reg in same cycle
        we <= '1'; wa <= "00011"; wd <= x"12345678";
        ra1 <= "00011";
        wait for 1 ns;  -- combinatorial, before clock edge
        assert rd1 = x"12345678" report "FAIL: write-through forward" severity error;
        report "PASS: write-through forward" severity note;
        wait until rising_edge(clk);
        we <= '0';

        -- Write all 31 regs and verify
        for i in 1 to 31 loop
            we <= '1';
            wa <= std_logic_vector(to_unsigned(i, 5));
            wd <= std_logic_vector(to_unsigned(i * 100, 32));
            wait until rising_edge(clk);
        end loop;
        we <= '0';
        for i in 1 to 31 loop
            ra1 <= std_logic_vector(to_unsigned(i, 5));
            wait for 1 ns;
            assert rd1 = std_logic_vector(to_unsigned(i * 100, 32))
                report "FAIL: reg x" & integer'image(i) severity error;
        end loop;
        report "PASS: all 31 registers" severity note;

        report "=== tb_regfile COMPLETE ===" severity note;
        wait;
    end process;
end architecture sim;
