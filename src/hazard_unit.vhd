-- =============================================================================
-- hazard_unit.vhd  —  Hazard detection + 2-stage forwarding control
--
-- Hazards handled:
--   1. Load-use RAW: ID/EX stage issued a load; its destination matches a source
--      in the instruction currently in IF/ID → stall (1 cycle bubble).
--   2. Branch misprediction flush: flush IF and ID stages (2 NOP cycles).
--
-- Forwarding (EX stage muxes):
--   FWD_MEM (10): forward from EX/MEM ALU result  (1-cycle-old result)
--   FWD_WB  (01): forward from MEM/WB write-back   (2-cycle-old result)
--   FWD_REG (00): use register-file value (no hazard)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

entity hazard_unit is
    port (
        -- From ID/EX register
        idex_mem_read  : in  std_logic;
        idex_rd        : in  std_logic_vector(4 downto 0);
        idex_rs1       : in  std_logic_vector(4 downto 0);
        idex_rs2       : in  std_logic_vector(4 downto 0);

        -- From IF/ID register (source regs of the instruction behind)
        ifid_rs1       : in  std_logic_vector(4 downto 0);
        ifid_rs2       : in  std_logic_vector(4 downto 0);

        -- From EX/MEM register
        exmem_reg_write: in  std_logic;
        exmem_rd       : in  std_logic_vector(4 downto 0);

        -- From MEM/WB register
        memwb_reg_write: in  std_logic;
        memwb_rd       : in  std_logic_vector(4 downto 0);

        -- Forwarding selects for EX-stage ALU inputs
        fwd_a          : out std_logic_vector(1 downto 0);  -- for RS1
        fwd_b          : out std_logic_vector(1 downto 0);  -- for RS2

        -- Load-use stall
        stall          : out std_logic;  -- stall IF and ID, insert bubble in EX

        -- Misprediction / branch flush (supplied externally, routed here for clarity)
        flush_ifid     : out std_logic;
        flush_idex     : out std_logic;

        -- Branch misprediction signal from EX stage
        branch_mispredict : in std_logic
    );
end entity hazard_unit;

architecture rtl of hazard_unit is
    signal load_use : std_logic;
begin
    -- -------------------------------------------------------------------------
    -- Load-use hazard detection
    -- Condition: instruction in ID/EX is a load AND its rd matches rs1 or rs2
    -- of the instruction currently being decoded (in IF/ID).
    -- -------------------------------------------------------------------------
    load_use <= '1' when (idex_mem_read = '1'
                      and unsigned(idex_rd) /= 0
                      and (idex_rd = ifid_rs1 or idex_rd = ifid_rs2))
                else '0';

    stall       <= load_use;
    flush_ifid  <= branch_mispredict;
    flush_idex  <= branch_mispredict or load_use;

    -- -------------------------------------------------------------------------
    -- Forwarding logic (EX-stage: look at rs1/rs2 of instruction in ID/EX)
    -- Priority: EX/MEM forwarding (more recent) over MEM/WB forwarding.
    -- -------------------------------------------------------------------------
    process(exmem_reg_write, exmem_rd, memwb_reg_write, memwb_rd,
            idex_rs1, idex_rs2)
    begin
        -- Forward A (RS1)
        if (exmem_reg_write = '1'
            and unsigned(exmem_rd) /= 0
            and exmem_rd = idex_rs1) then
            fwd_a <= FWD_MEM;
        elsif (memwb_reg_write = '1'
               and unsigned(memwb_rd) /= 0
               and memwb_rd = idex_rs1) then
            fwd_a <= FWD_WB;
        else
            fwd_a <= FWD_REG;
        end if;

        -- Forward B (RS2)
        if (exmem_reg_write = '1'
            and unsigned(exmem_rd) /= 0
            and exmem_rd = idex_rs2) then
            fwd_b <= FWD_MEM;
        elsif (memwb_reg_write = '1'
               and unsigned(memwb_rd) /= 0
               and memwb_rd = idex_rs2) then
            fwd_b <= FWD_WB;
        else
            fwd_b <= FWD_REG;
        end if;
    end process;

end architecture rtl;
