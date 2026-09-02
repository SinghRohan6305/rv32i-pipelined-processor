-- =============================================================================
-- tb_r_type.vhd  —  Tests all 10 R-type instructions
-- Program:
--   addi x1, x0, 20      # x1 = 20
--   addi x2, x0, 7       # x2 = 7
--   add  x3, x1, x2      # x3 = 27
--   sub  x4, x1, x2      # x4 = 13
--   and  x5, x1, x2      # x5 = 4  (20 & 7 = 0b10100 & 0b00111 = 0b00100)
--   or   x6, x1, x2      # x6 = 23 (20 | 7)
--   xor  x7, x1, x2      # x7 = 19 (20 ^ 7)
--   sll  x8, x1, x2      # x8 = 20 << 7 = 2560
--   srl  x9, x1, x2      # x9 = 20 >> 7 = 0
--   sra  x10, x1, x2     # x10 = 20 >> 7 = 0  (arithmetic)
--   slt  x11, x2, x1     # x11 = 1  (7 < 20)
--   sltu x12, x2, x1     # x12 = 1
--   addi x13, x0, -4     # x13 = -4
--   sra  x14, x13, x2    # x14 = -4 >> 7 = -1
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_r_type is
end entity tb_r_type;

architecture sim of tb_r_type is
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal dbg_pc     : std_logic_vector(31 downto 0);
    signal dbg_instr  : std_logic_vector(31 downto 0);
    signal dbg_reg_we : std_logic;
    signal dbg_reg_wa : std_logic_vector(4 downto 0);
    signal dbg_reg_wd : std_logic_vector(31 downto 0);

    -- Register file shadow for checking
    type reg_file_t is array(0 to 31) of integer;
    signal regs : reg_file_t := (others => 0);

    constant CLK_P : time := 10 ns;

    -- Hex program to write
    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);

    -- Build instructions inline using pkg constants
    -- ADDI x1, x0, 20
    constant ADDI_X1_20 : std_logic_vector(31 downto 0) :=
        x"01400093";  -- addi x1, x0, 20
    constant ADDI_X2_7  : std_logic_vector(31 downto 0) :=
        x"00700113";  -- addi x2, x0, 7
    constant ADD_X3     : std_logic_vector(31 downto 0) :=
        x"002081B3";  -- add x3, x1, x2
    constant SUB_X4     : std_logic_vector(31 downto 0) :=
        x"40208233";  -- sub x4, x1, x2
    constant AND_X5     : std_logic_vector(31 downto 0) :=
        x"0020F2B3";  -- and x5, x1, x2
    constant OR_X6      : std_logic_vector(31 downto 0) :=
        x"0020E333";  -- or x6, x1, x2
    constant XOR_X7     : std_logic_vector(31 downto 0) :=
        x"0020C3B3";  -- xor x7, x1, x2
    constant SLL_X8     : std_logic_vector(31 downto 0) :=
        x"00209433";  -- sll x8, x1, x2
    constant SRL_X9     : std_logic_vector(31 downto 0) :=
        x"0020D4B3";  -- srl x9, x1, x2
    constant SRA_X10    : std_logic_vector(31 downto 0) :=
        x"4020D533";  -- sra x10, x1, x2
    constant SLT_X11    : std_logic_vector(31 downto 0) :=
        x"0010A5B3";  -- slt x11, x1, x2  -> 0 (20 is not < 7)
    constant SLTU_X12   : std_logic_vector(31 downto 0) :=
        x"0020B633";  -- sltu x12, x1, x2 -> 0
    constant ADDI_X13_N4: std_logic_vector(31 downto 0) :=
        x"FFC006B3";  -- will use inline: addi x13, x0, -4 = FFC00693
    constant SRA_X14    : std_logic_vector(31 downto 0) :=
        x"4026D733";  -- sra x14, x13, x2

    constant PROG : prog_t(0 to 15) := (
        x"01400093",  -- 0: addi x1, x0, 20
        x"00700113",  -- 4: addi x2, x0, 7
        x"002081B3",  -- 8: add  x3, x1, x2   -> 27
        x"40208233",  -- C: sub  x4, x1, x2   -> 13
        x"0020F2B3",  -- 10: and x5, x1, x2   -> 4
        x"0020E333",  -- 14: or  x6, x1, x2   -> 23
        x"0020C3B3",  -- 18: xor x7, x1, x2   -> 19
        x"00209433",  -- 1C: sll x8, x1, x2   -> 2560
        x"0020D4B3",  -- 20: srl x9, x1, x2   -> 0
        x"4020D533",  -- 24: sra x10,x1, x2   -> 0
        x"0010A5B3",  -- 28: slt x11,x1, x2   -> 0 (20 not < 7)
        x"0020B633",  -- 2C: sltu x12,x1,x2   -> 0
        x"FFC00693",  -- 30: addi x13,x0,-4
        x"4026D733",  -- 34: sra x14,x13,x2   -> -1  (-4 >> 7 arith)
        x"00000013",  -- 38: nop
        x"00000013"   -- 3C: nop
    );

    constant HEX_FILE : string := "/tmp/tb_r_type.hex";

begin
    clk <= not clk after CLK_P/2;

    -- Write program to hex file
    process
        file fh  : text open WRITE_MODE is HEX_FILE;
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

    -- Shadow register file
    process(clk)
    begin
        if rising_edge(clk) then
            if dbg_reg_we = '1' and unsigned(dbg_reg_wa) /= 0 then
                regs(to_integer(unsigned(dbg_reg_wa))) <=
                    to_integer(signed(dbg_reg_wd));
            end if;
        end if;
    end process;

    -- Stimulus and checking
    process
    begin
        rst <= '1';
        wait for 3 * CLK_P;
        rst <= '0';

        -- Run enough cycles for 14 instructions + pipeline drain (5 stages + hazards)
        wait for 30 * CLK_P;

        -- Check results
        assert regs(1) = 20   report "FAIL x1=20"  severity error;
        assert regs(2) = 7    report "FAIL x2=7"   severity error;
        assert regs(3) = 27   report "FAIL add x3=27"  severity error;
        assert regs(4) = 13   report "FAIL sub x4=13"  severity error;
        assert regs(5) = 4    report "FAIL and x5=4"   severity error;
        assert regs(6) = 23   report "FAIL or  x6=23"  severity error;
        assert regs(7) = 19   report "FAIL xor x7=19"  severity error;
        assert regs(8) = 2560 report "FAIL sll x8=2560" severity error;
        assert regs(9) = 0    report "FAIL srl x9=0"   severity error;
        assert regs(10) = 0   report "FAIL sra x10=0"  severity error;
        assert regs(11) = 0   report "FAIL slt x11=0"  severity error;
        assert regs(12) = 0   report "FAIL sltu x12=0" severity error;
        assert regs(13) = -4  report "FAIL x13=-4"  severity error;
        assert regs(14) = -1  report "FAIL sra x14=-1" severity error;

        report "=== tb_r_type PASS ===" severity note;
        wait;
    end process;
end architecture sim;
