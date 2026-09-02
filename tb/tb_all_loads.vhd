-- =============================================================================
-- tb_all_loads.vhd  —  Dedicated test for all 5 load instructions
-- LB LH LW LBU LHU with careful sign/zero extension verification
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_all_loads is
end entity tb_all_loads;

architecture sim of tb_all_loads is
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal dbg_pc     : std_logic_vector(31 downto 0);
    signal dbg_instr  : std_logic_vector(31 downto 0);
    signal dbg_reg_we : std_logic;
    signal dbg_reg_wa : std_logic_vector(4 downto 0);
    signal dbg_reg_wd : std_logic_vector(31 downto 0);

    type reg_file_t is array(0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_file_t := (others => (others => '0'));

    constant CLK_P    : time := 10 ns;
    constant HEX_FILE : string := "/tmp/tb_all_loads.hex";

    -- Stores: mem[256] = 0xABCD1234 (word)
    -- Byte layout (little-endian):
    --   addr 256: 0x34
    --   addr 257: 0x12
    --   addr 258: 0xCD
    --   addr 259: 0xAB
    --
    -- Expected:
    --   LW  @ 256: 0xABCD1234
    --   LH  @ 256: 0x00001234  (sign-extend 0x1234 = positive)
    --   LH  @ 258: 0xFFFFABCD  (sign-extend 0xABCD = negative)
    --   LHU @ 256: 0x00001234
    --   LHU @ 258: 0x0000ABCD
    --   LB  @ 256: 0x00000034  (sign-extend 0x34 = positive)
    --   LB  @ 258: 0xFFFFFFCD  (sign-extend 0xCD = negative)
    --   LBU @ 256: 0x00000034
    --   LBU @ 258: 0x000000CD

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 25) := (
        -- Setup
        x"ABCDB0B7",  -- 0x00: lui x1, 0xABCDB
        x"234080B3",  -- 0x04: addI x1, x1, ... hmm need ADDI not ADD
        -- Let me use proper encoding:
        -- lui x1, 0xABCDB -> x1 = 0xABCDB000
        -- We need 0xABCD1234. 0xABCDB000 + 0x1234 = 0xABCCC234? Wrong.
        -- Better: lui x1, 0xABCDE -> 0xABCDE000; addi x1, x1, 0x234 -> 0xABCDE234. Nope.
        -- 0xABCD1234: upper 20 = 0xABCD1, lower 12 = 0x234
        -- But lower 12 is sign-extended: 0x234 = positive, fine.
        -- lui x1, 0xABCD1 -> 0xABCD1000; addi x1, x1, 0x234 -> 0xABCD1234. YES!
        x"ABCD10B7",  -- 0x00: lui x1, 0xABCD1 -> 0xABCD1000
        x"23408093",  -- 0x04: addi x1, x1, 0x234 -> 0xABCD1234
        x"10000A13",  -- 0x08: addi x20, x0, 256
        x"00102023",  -- 0x0C: sw x1, 0(x20)

        -- LW
        x"00002083",  -- 0x10: lw x1, 0(x20)   -> 0xABCD1234 (overwrite x1)

        -- LH @ 256 (lower half = 0x1234, positive)
        x"00001103",  -- 0x14: lh x2, 0(x20)   -> 0x00001234

        -- LH @ 258 (upper half = 0xABCD, negative)
        x"002A1183",  -- 0x18: lh x3, 2(x20)   -> 0xFFFFABCD

        -- LHU @ 256
        x"00005203",  -- 0x1C: lhu x4, 0(x20)  -> 0x00001234

        -- LHU @ 258
        x"002A5283",  -- 0x20: lhu x5, 2(x20)  -> 0x0000ABCD

        -- LB @ 256 (0x34, positive)
        x"00000303",  -- 0x24: lb x6, 0(x20)   -> 0x00000034

        -- LB @ 258 (0xCD, negative)
        x"002A0383",  -- 0x28: lb x7, 2(x20)   -> 0xFFFFFFCD

        -- LBU @ 256
        x"00004403",  -- 0x2C: lbu x8, 0(x20)  -> 0x00000034

        -- LBU @ 258
        x"002A4483",  -- 0x30: lbu x9, 2(x20)  -> 0x000000CD

        x"00000013",
        x"00000013",
        x"00000013",
        x"00000013",
        x"00000013",
        x"00000013",
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
                regs(to_integer(unsigned(dbg_reg_wa))) <= dbg_reg_wd;
            end if;
        end if;
    end process;

    process
    begin
        rst <= '1';
        wait for 3 * CLK_P;
        rst <= '0';
        wait for 60 * CLK_P;

        assert regs(1) = x"ABCD1234" report "FAIL LW"            severity error;
        assert regs(2) = x"00001234" report "FAIL LH pos"        severity error;
        assert regs(3) = x"FFFFABCD" report "FAIL LH neg"        severity error;
        assert regs(4) = x"00001234" report "FAIL LHU pos"       severity error;
        assert regs(5) = x"0000ABCD" report "FAIL LHU"           severity error;
        assert regs(6) = x"00000034" report "FAIL LB pos 0x34"   severity error;
        assert regs(7) = x"FFFFFFCD" report "FAIL LB neg 0xCD"   severity error;
        assert regs(8) = x"00000034" report "FAIL LBU 0x34"      severity error;
        assert regs(9) = x"000000CD" report "FAIL LBU 0xCD"      severity error;

        report "=== tb_all_loads PASS ===" severity note;
        wait;
    end process;
end architecture sim;
