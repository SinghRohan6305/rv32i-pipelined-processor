-- =============================================================================
-- branch_predictor.vhd  —  1-bit direct-mapped branch predictor
-- 16-entry BHT indexed by PC[5:2].  Each entry: 0=predict-not-taken, 1=taken.
-- All entries initialise to 0 (predict-not-taken).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_predictor is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        -- Prediction request (IF stage)
        pc_fetch     : in  std_logic_vector(31 downto 0);
        predict_taken: out std_logic;
        -- Update from EX stage (after branch resolves)
        update_en    : in  std_logic;
        update_pc    : in  std_logic_vector(31 downto 0);
        actual_taken : in  std_logic
    );
end entity branch_predictor;

architecture rtl of branch_predictor is
    type bht_t is array(0 to 15) of std_logic;
    signal bht : bht_t := (others => '0');

    signal fetch_idx  : integer range 0 to 15;
    signal update_idx : integer range 0 to 15;
begin
    fetch_idx  <= to_integer(unsigned(pc_fetch (5 downto 2)));
    update_idx <= to_integer(unsigned(update_pc(5 downto 2)));

    -- Combinatorial prediction
    predict_taken <= bht(fetch_idx);

    -- Synchronous update
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                bht <= (others => '0');
            elsif update_en = '1' then
                bht(update_idx) <= actual_taken;
            end if;
        end if;
    end process;

end architecture rtl;
