-- =============================================================================
-- tb_i_type.vhd  —  Tests all 9 I-type ALU instructions
-- ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_i_type is
end entity tb_i_type;

architecture sim of tb_i_type is
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal dbg_pc     : std_logic_vector(31 downto 0);
    signal dbg_instr  : std_logic_vector(31 downto 0);
    signal dbg_reg_we : std_logic;
    signal dbg_reg_wa : std_logic_vector(4 downto 0);
    signal dbg_reg_wd : std_logic_vector(31 downto 0);

    type reg_file_t is array(0 to 31) of integer;
    signal regs : reg_file_t := (others => 0);

    constant CLK_P    : time := 10 ns;
    constant HEX_FILE : string := "/tmp/tb_i_type.hex";

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 17) := (
        -- x1 = 100 (base value)
        x"06400093",  --  0: addi  x1, x0,  100
        -- ADDI: x2 = x1 + (-10) = 90
        x"FF608113",  --  4: addi  x2, x1,  -10    -> 90
        -- SLTI: x3 = (100 < 200) = 1
        x"0C80A193",  --  8: slti  x3, x1,  200    -> 1
        -- SLTI: x4 = (100 < 50) = 0
        x"0320A213",  --  C: slti  x4, x1,  50     -> 0
        -- SLTIU: x5 = (100 < 4294967295) unsigned = 1
        x"FFF0B293",  -- 10: sltiu x5, x1,  -1(u)  -> 1
        -- XORI: x6 = 100 ^ 0xFF = 155
        x"0FF0C313",  -- 14: xori  x6, x1,  255    -> 155 (0x64 ^ 0xFF)
        -- ORI:  x7 = 100 | 0x0F = 111
        x"00F0E393",  -- 18: ori   x7, x1,  15     -> 111
        -- ANDI: x8 = 100 & 0xF0 = 96
        x"0F00F413",  -- 1C: andi  x8, x1,  240    -> 96  (0x64 & 0xF0)
        -- SLLI: x9 = 100 << 2 = 400
        x"00209493",  -- 20: slli  x9, x1,  2      -> 400
        -- SRLI: x10 = 100 >> 2 = 25
        x"00205513",  -- 24: srli  x10, x1, 2      -> 25
        -- SRAI: x11 = 100 >> 2 = 25 (positive, same as srli)
        x"40205593",  -- 28: srai  x11, x1, 2      -> 25
        -- Load negative value for SRAI test
        x"FFC00613",  -- 2C: addi  x12, x0, -4
        -- SRAI: x13 = -4 >> 1 = -2
        x"40165693",  -- 30: srai  x13, x12, 1     -> -2
        -- SRLI: x14 = -4 >> 1 = very large positive (0x7FFFFFFF...not -4)
        -- -4 = 0xFFFFFFFC >> 1 = 0x7FFFFFFE = 2147483646
        x"00165713",  -- 34: srli  x14, x12, 1     -> 2147483646
        -- SLTIU boundary: 0 < anything = 1 except 0
        x"00103793",  -- 38: sltiu x15, x0, 1      -> 1
        x"00003813",  -- 3C: sltiu x16, x0, 0      -> 0
        x"00000013",  -- 40: nop
        x"00000013"   -- 44: nop
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
                regs(to_integer(unsigned(dbg_reg_wa))) <=
                    to_integer(signed(dbg_reg_wd));
            end if;
        end if;
    end process;

    process
    begin
        rst <= '1';
        wait for 3 * CLK_P;
        rst <= '0';
        wait for 35 * CLK_P;

        assert regs(1)  = 100        report "FAIL addi x1=100"    severity error;
        assert regs(2)  = 90         report "FAIL addi x2=90"     severity error;
        assert regs(3)  = 1          report "FAIL slti x3=1"      severity error;
        assert regs(4)  = 0          report "FAIL slti x4=0"      severity error;
        assert regs(5)  = 1          report "FAIL sltiu x5=1"     severity error;
        assert regs(6)  = 155        report "FAIL xori x6=155"    severity error;
        assert regs(7)  = 111        report "FAIL ori x7=111"     severity error;
        assert regs(8)  = 96         report "FAIL andi x8=96"     severity error;
        assert regs(9)  = 400        report "FAIL slli x9=400"    severity error;
        assert regs(10) = 25         report "FAIL srli x10=25"    severity error;
        assert regs(11) = 25         report "FAIL srai x11=25"    severity error;
        assert regs(12) = -4         report "FAIL x12=-4"         severity error;
        assert regs(13) = -2         report "FAIL srai x13=-2"    severity error;
        assert regs(14) = 2147483646 report "FAIL srli x14=2G-2"  severity error;
        assert regs(15) = 1          report "FAIL sltiu x15=1"    severity error;
        assert regs(16) = 0          report "FAIL sltiu x16=0"    severity error;

        report "=== tb_i_type PASS ===" severity note;
        wait;
    end process;
end architecture sim;
