-- =============================================================================
-- tb_hazard_unit.vhd  —  Unit tests for hazard detection and forwarding logic
-- Tests load-use stall generation and forwarding mux select signals.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;
use work.tb_pkg.all;

entity tb_hazard_unit is
end entity tb_hazard_unit;

architecture sim of tb_hazard_unit is
    signal idex_mem_read   : std_logic := '0';
    signal idex_rd         : std_logic_vector(4 downto 0) := (others => '0');
    signal idex_rs1        : std_logic_vector(4 downto 0) := (others => '0');
    signal idex_rs2        : std_logic_vector(4 downto 0) := (others => '0');
    signal ifid_rs1        : std_logic_vector(4 downto 0) := (others => '0');
    signal ifid_rs2        : std_logic_vector(4 downto 0) := (others => '0');
    signal exmem_reg_write : std_logic := '0';
    signal exmem_rd        : std_logic_vector(4 downto 0) := (others => '0');
    signal memwb_reg_write : std_logic := '0';
    signal memwb_rd        : std_logic_vector(4 downto 0) := (others => '0');
    signal fwd_a           : std_logic_vector(1 downto 0);
    signal fwd_b           : std_logic_vector(1 downto 0);
    signal stall           : std_logic;
    signal flush_ifid      : std_logic;
    signal flush_idex      : std_logic;
    signal branch_mispredict : std_logic := '0';

begin
    dut: entity work.hazard_unit
        port map (
            idex_mem_read => idex_mem_read, idex_rd => idex_rd,
            idex_rs1 => idex_rs1, idex_rs2 => idex_rs2,
            ifid_rs1 => ifid_rs1, ifid_rs2 => ifid_rs2,
            exmem_reg_write => exmem_reg_write, exmem_rd => exmem_rd,
            memwb_reg_write => memwb_reg_write, memwb_rd => memwb_rd,
            fwd_a => fwd_a, fwd_b => fwd_b,
            stall => stall, flush_ifid => flush_ifid, flush_idex => flush_idex,
            branch_mispredict => branch_mispredict);

    process
        variable errors : natural := 0;
    begin
        -- =====================================================================
        -- No hazard: stall=0, fwd=REG
        -- =====================================================================
        idex_mem_read   <= '0';
        idex_rd         <= "00000";
        ifid_rs1        <= "00001";
        ifid_rs2        <= "00010";
        exmem_reg_write <= '0';
        exmem_rd        <= "00000";
        memwb_reg_write <= '0';
        memwb_rd        <= "00000";
        idex_rs1        <= "00011";
        idex_rs2        <= "00100";
        wait for 5 ns;
        check_cond(stall  = '0', "no-hazard stall", errors);
        check_cond(fwd_a  = FWD_REG, "no-fwd fwd_a", errors);
        check_cond(fwd_b  = FWD_REG, "no-fwd fwd_b", errors);

        -- =====================================================================
        -- Load-use hazard: ID/EX is a load, rd matches IF/ID rs1
        -- =====================================================================
        idex_mem_read <= '1';
        idex_rd       <= "00001";
        ifid_rs1      <= "00001";  -- matches!
        ifid_rs2      <= "00010";
        wait for 5 ns;
        check_cond(stall    = '1', "load-use stall on rs1", errors);
        check_cond(flush_idex = '1', "flush_idex on stall", errors);

        -- Load-use on rs2
        ifid_rs1 <= "00000";
        ifid_rs2 <= "00001";
        wait for 5 ns;
        check_cond(stall = '1', "load-use stall on rs2", errors);

        -- Load-use with rd=x0: no stall (x0 never causes dependency)
        idex_rd  <= "00000";
        ifid_rs1 <= "00000";
        ifid_rs2 <= "00000";
        wait for 5 ns;
        check_cond(stall = '0', "x0 should not cause load-use stall", errors);

        -- Reset
        idex_mem_read <= '0';

        -- =====================================================================
        -- EX/MEM → RS1 forwarding
        -- =====================================================================
        exmem_reg_write <= '1';
        exmem_rd        <= "00001";
        idex_rs1        <= "00001";   -- match
        idex_rs2        <= "00010";
        wait for 5 ns;
        check_cond(fwd_a = FWD_MEM, "EX/MEM fwd_a", errors);
        check_cond(fwd_b = FWD_REG, "no fwd_b", errors);

        -- EX/MEM → RS2 forwarding
        exmem_rd  <= "00010";
        idex_rs1  <= "00001";   -- no match
        idex_rs2  <= "00010";   -- match
        wait for 5 ns;
        check_cond(fwd_a = FWD_REG, "no fwd_a", errors);
        check_cond(fwd_b = FWD_MEM, "EX/MEM fwd_b", errors);

        -- =====================================================================
        -- MEM/WB → forwarding (lower priority than EX/MEM)
        -- =====================================================================
        exmem_reg_write <= '0';
        exmem_rd        <= "00000";
        memwb_reg_write <= '1';
        memwb_rd        <= "00001";
        idex_rs1        <= "00001";
        idex_rs2        <= "00001";
        wait for 5 ns;
        check_cond(fwd_a = FWD_WB, "MEM/WB fwd_a", errors);
        check_cond(fwd_b = FWD_WB, "MEM/WB fwd_b", errors);

        -- EX/MEM takes priority over MEM/WB when both match
        exmem_reg_write <= '1';
        exmem_rd        <= "00001";
        idex_rs1        <= "00001";
        wait for 5 ns;
        check_cond(fwd_a = FWD_MEM, "priority EX/MEM over MEM/WB", errors);

        -- =====================================================================
        -- Branch misprediction: flush_ifid and flush_idex
        -- =====================================================================
        exmem_reg_write <= '0';
        memwb_reg_write <= '0';
        idex_mem_read   <= '0';
        branch_mispredict <= '1';
        wait for 5 ns;
        check_cond(flush_ifid = '1', "mispredict flush_ifid", errors);
        check_cond(flush_idex = '1', "mispredict flush_idex", errors);

        branch_mispredict <= '0';
        wait for 5 ns;
        check_cond(flush_ifid = '0', "no flush when no mispredict", errors);

        finish_test("tb_hazard_unit", errors);
        wait;
    end process;
end architecture sim;
