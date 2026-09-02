-- =============================================================================
-- tb_jal_jalr.vhd  —  Tests JAL and JALR
-- JAL  jumps forward, writes PC+4 to rd
-- JALR jumps to RS1+imm, writes PC+4 to rd
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_jal_jalr is
end entity tb_jal_jalr;

architecture sim of tb_jal_jalr is
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
    constant HEX_FILE : string := "/tmp/tb_jal_jalr.hex";

    -- Program:
    -- 0x00: JAL x1, +12    -> jump to 0x0C, x1 = 0x04
    -- 0x04: addi x29,x0,1  ERROR (should be skipped)
    -- 0x08: addi x29,x0,2  ERROR
    -- 0x0C: addi x10,x0,1  PASS: x10=1
    -- 0x10: addi x5, x0, 0x20   x5 = 32 (target for JALR)
    -- 0x14: JALR x2, x5, 0x10  -> PC = 32+16 = 48 = 0x30, x2=0x18
    -- 0x18: addi x29,x0,3  ERROR
    -- 0x1C..0x2C: nops
    -- 0x30: addi x11,x0,1  PASS: x11=1
    -- Verify: x1 = 0x04, x2 = 0x18

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 19) := (
        x"00C000EF",  -- 0x00: jal x1, +12    target=0x0C
        x"00100E93",  -- 0x04: addi x29,x0,1  (ERROR)
        x"00200E93",  -- 0x08: addi x29,x0,2  (ERROR)
        x"00100513",  -- 0x0C: addi x10,x0,1  PASS x10=1
        x"02000293",  -- 0x10: addi x5,x0,32
        x"01028167",  -- 0x14: jalr x2,x5,16  -> 32+16=48=0x30, x2=0x18
        x"00300E93",  -- 0x18: addi x29,x0,3  (ERROR)
        x"00000013",  -- 0x1C: nop
        x"00000013",  -- 0x20: nop
        x"00000013",  -- 0x24: nop
        x"00000013",  -- 0x28: nop
        x"00000013",  -- 0x2C: nop
        x"00100593",  -- 0x30: addi x11,x0,1  PASS x11=1
        x"00000013",  -- 0x34: nop
        x"00000013",  -- 0x38: nop
        x"00000013",  -- 0x3C: nop
        x"00000013",  -- 0x40: nop
        x"00000013",  -- 0x44
        x"00000013",  -- 0x48
        x"00000013"   -- 0x4C
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
        wait for 50 * CLK_P;

        assert regs(29) = x"00000000"
            report "FAIL: wrong path executed (x29 != 0)" severity error;
        assert regs(1) = x"00000004"
            report "FAIL JAL link x1=0x04" severity error;
        assert regs(2) = x"00000018"
            report "FAIL JALR link x2=0x18" severity error;
        assert regs(10) = x"00000001"
            report "FAIL JAL target x10=1" severity error;
        assert regs(11) = x"00000001"
            report "FAIL JALR target x11=1" severity error;

        report "=== tb_jal_jalr PASS ===" severity note;
        wait;
    end process;
end architecture sim;
