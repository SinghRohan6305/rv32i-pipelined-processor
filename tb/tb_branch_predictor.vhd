-- =============================================================================
-- tb_branch_predictor.vhd  —  Unit test for 1-bit branch predictor
-- Verifies: initial predict-not-taken, update on taken, convergence.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_branch_predictor is
end entity tb_branch_predictor;

architecture sim of tb_branch_predictor is
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal pc_fetch     : std_logic_vector(31 downto 0) := (others => '0');
    signal predict_taken: std_logic;
    signal update_en    : std_logic := '0';
    signal update_pc    : std_logic_vector(31 downto 0) := (others => '0');
    signal actual_taken : std_logic := '0';

    constant CLK_P : time := 10 ns;
begin
    clk <= not clk after CLK_P/2;

    dut: entity work.branch_predictor
        port map (clk => clk, rst => rst,
                  pc_fetch => pc_fetch, predict_taken => predict_taken,
                  update_en => update_en, update_pc => update_pc,
                  actual_taken => actual_taken);

    process
    begin
        -- After reset: all entries = 0 (predict not-taken)
        rst <= '1';
        wait for 2 * CLK_P;
        rst <= '0';
        wait for 1 ns;

        pc_fetch <= x"00000010";  -- index = bits[5:2] = 4
        wait for 1 ns;
        assert predict_taken = '0'
            report "FAIL: initial prediction should be not-taken" severity error;
        report "PASS: initial not-taken" severity note;

        -- Update: branch at PC=0x10 was actually taken
        wait until rising_edge(clk);
        update_en    <= '1';
        update_pc    <= x"00000010";
        actual_taken <= '1';
        wait until rising_edge(clk);
        update_en    <= '0';
        wait for 1 ns;

        -- Now predict for same PC: should predict taken
        pc_fetch <= x"00000010";
        wait for 1 ns;
        assert predict_taken = '1'
            report "FAIL: after taken update, should predict taken" severity error;
        report "PASS: predict taken after update" severity note;

        -- Update: was not-taken
        wait until rising_edge(clk);
        update_en    <= '1';
        update_pc    <= x"00000010";
        actual_taken <= '0';
        wait until rising_edge(clk);
        update_en    <= '0';
        wait for 1 ns;

        pc_fetch <= x"00000010";
        wait for 1 ns;
        assert predict_taken = '0'
            report "FAIL: after not-taken update, should predict not-taken" severity error;
        report "PASS: predict not-taken after update" severity note;

        -- Test different PC index (PC = 0x24, bits[5:2] = 9)
        pc_fetch <= x"00000024";
        wait for 1 ns;
        assert predict_taken = '0'
            report "FAIL: different entry should be not-taken" severity error;
        report "PASS: independent entries" severity note;

        -- Test reset clears predictor state
        wait until rising_edge(clk);
        update_en    <= '1';
        update_pc    <= x"00000024";
        actual_taken <= '1';
        wait until rising_edge(clk);
        update_en    <= '0';
        rst <= '1';
        wait until rising_edge(clk);
        rst <= '0';
        wait for 1 ns;

        pc_fetch <= x"00000024";
        wait for 1 ns;
        assert predict_taken = '0'
            report "FAIL: reset should clear prediction" severity error;
        report "PASS: reset clears predictor" severity note;

        report "=== tb_branch_predictor PASS ===" severity note;
        wait;
    end process;
end architecture sim;
