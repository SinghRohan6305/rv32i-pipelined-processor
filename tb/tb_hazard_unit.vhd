-- =============================================================================
-- tb_hazard_unit.vhd  —  Unit tests for hazard detection and forwarding logic
-- Tests load-use stall generation and forwarding mux select signals.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

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
        assert stall  = '0' report "FAIL: no-hazard stall" severity error;
        assert fwd_a  = FWD_REG report "FAIL: no-fwd fwd_a" severity error;
        assert fwd_b  = FWD_REG report "FAIL: no-fwd fwd_b" severity error;
        report "PASS: no hazard" severity note;

        -- =====================================================================
        -- Load-use hazard: ID/EX is a load, rd matches IF/ID rs1
        -- =====================================================================
        idex_mem_read <= '1';
        idex_rd       <= "00001";
        ifid_rs1      <= "00001";  -- matches!
        ifid_rs2      <= "00010";
        wait for 5 ns;
        assert stall    = '1' report "FAIL: load-use stall on rs1" severity error;
        assert flush_idex = '1' report "FAIL: flush_idex on stall" severity error;
        report "PASS: load-use stall (rs1)" severity note;

        -- Load-use on rs2
        ifid_rs1 <= "00000";
        ifid_rs2 <= "00001";
        wait for 5 ns;
        assert stall = '1' report "FAIL: load-use stall on rs2" severity error;
        report "PASS: load-use stall (rs2)" severity note;

        -- Load-use with rd=x0: no stall (x0 never causes dependency)
        idex_rd  <= "00000";
        ifid_rs1 <= "00000";
        ifid_rs2 <= "00000";
        wait for 5 ns;
        assert stall = '0' report "FAIL: x0 should not cause load-use stall" severity error;
        report "PASS: x0 no load-use stall" severity note;

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
        assert fwd_a = FWD_MEM report "FAIL: EX/MEM fwd_a" severity error;
        assert fwd_b = FWD_REG report "FAIL: no fwd_b"    severity error;
        report "PASS: EX/MEM fwd_a" severity note;

        -- EX/MEM → RS2 forwarding
        exmem_rd  <= "00010";
        idex_rs1  <= "00001";   -- no match
        idex_rs2  <= "00010";   -- match
        wait for 5 ns;
        assert fwd_a = FWD_REG report "FAIL: no fwd_a"    severity error;
        assert fwd_b = FWD_MEM report "FAIL: EX/MEM fwd_b" severity error;
        report "PASS: EX/MEM fwd_b" severity note;

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
        assert fwd_a = FWD_WB report "FAIL: MEM/WB fwd_a" severity error;
        assert fwd_b = FWD_WB report "FAIL: MEM/WB fwd_b" severity error;
        report "PASS: MEM/WB forwarding" severity note;

        -- EX/MEM takes priority over MEM/WB when both match
        exmem_reg_write <= '1';
        exmem_rd        <= "00001";
        idex_rs1        <= "00001";
        wait for 5 ns;
        assert fwd_a = FWD_MEM report "FAIL: priority EX/MEM over MEM/WB" severity error;
        report "PASS: EX/MEM priority over MEM/WB" severity note;

        -- =====================================================================
        -- Branch misprediction: flush_ifid and flush_idex
        -- =====================================================================
        exmem_reg_write <= '0';
        memwb_reg_write <= '0';
        idex_mem_read   <= '0';
        branch_mispredict <= '1';
        wait for 5 ns;
        assert flush_ifid = '1' report "FAIL: mispredict flush_ifid" severity error;
        assert flush_idex = '1' report "FAIL: mispredict flush_idex" severity error;
        report "PASS: branch misprediction flush" severity note;

        branch_mispredict <= '0';
        wait for 5 ns;
        assert flush_ifid = '0' report "FAIL: no flush when no mispredict" severity error;
        report "PASS: no flush when normal" severity note;

        report "=== tb_hazard_unit PASS ===" severity note;
        wait;
    end process;
end architecture sim;
