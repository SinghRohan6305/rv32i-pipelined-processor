-- =============================================================================
-- tb_branch_predictor.vhd  —  Unit test for 1-bit branch predictor
-- Verifies: initial predict-not-taken, update on taken, convergence.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tb_pkg.all;

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
        variable errors : natural := 0;
    begin
        -- After reset: all entries = 0 (predict not-taken)
        rst <= '1';
        wait for 2 * CLK_P;
        rst <= '0';
        wait for 1 ns;

        pc_fetch <= x"00000010";  -- index = bits[5:2] = 4
        wait for 1 ns;
        check_cond(predict_taken = '0', "initial prediction should be not-taken", errors);

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
        check_cond(predict_taken = '1', "after taken update, should predict taken", errors);

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
        check_cond(predict_taken = '0', "after not-taken update, should predict not-taken", errors);

        -- Test different PC index (PC = 0x24, bits[5:2] = 9)
        pc_fetch <= x"00000024";
        wait for 1 ns;
        check_cond(predict_taken = '0', "different entry should be not-taken", errors);

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
        check_cond(predict_taken = '0', "reset should clear prediction", errors);

        finish_test("tb_branch_predictor", errors);
        wait;
    end process;
end architecture sim;
