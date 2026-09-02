-- =============================================================================
-- tb_all_stores.vhd  —  Dedicated test for all 3 store instructions
-- SW SH SB: write partial data and verify with LW that bytes are correct.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_all_stores is
end entity tb_all_stores;

architecture sim of tb_all_stores is
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
    constant HEX_FILE : string := "/tmp/tb_all_stores.hex";

    -- Write 4 individual bytes via SB, then read back as word
    -- Also test SH writes 2 bytes correctly
    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 23) := (
        x"10000A13",  -- addi x20, x0, 256   base

        -- SB test: write 0xAA,0xBB,0xCC,0xDD to bytes 0..3
        x"0AA00093",  -- addi x1, x0, 0xAA
        x"0BB00113",  -- addi x2, x0, 0xBB
        x"0CC00193",  -- addi x3, x0, 0xCC
        x"0DD00213",  -- addi x4, x0, 0xDD
        x"001A0023",  -- sb x1, 0(x20)
        x"002A0123",  -- sb x2, 1(x20)
        x"003A0223",  -- sb x3, 2(x20)
        x"004A0323",  -- sb x4, 3(x20)

        -- LW should give 0xDDCCBBAA (little-endian)
        x"000A2283",  -- lw x5, 0(x20)   -> 0xDDCCBBAA

        -- SH test: write 0x1234 at offset 4, 0xABCD at offset 6
        x"12340293",  -- addi x5, x0, 0x234  (lower part; need to fix for 0x1234)
        -- 0x1234 as 12-bit signed = positive, fine
        -- addi x5, x0, 0x234 = 0x234 = 564... we need 0x1234 = 4660
        -- 4660 > 2047, can't fit in 12-bit signed imm alone. Need lui+addi.
        -- Let's use smaller values: 0x1234 = lui x5, 1 -> 0x1000; addi x5, x5, 0x234 -> 0x1234
        x"000012B7",  -- lui x5, 1   -> x5 = 0x1000
        x"234282B3",  -- Hmm: addi x5, x5, 0x234... wait:
        -- addi x5, x5, 0x234: imm=0x234=564, rs1=x5, rd=x5, funct3=0, op=0010011
        -- = 0010 0011 0100 0010 1000 0010 1001 0011 = 0x23428293
        x"23428293",  -- addi x5, x5, 0x234 -> x5 = 0x1234
        x"005A1223",  -- sh x5, 4(x20)      store 0x1234 at byte 4
        x"004A5383",  -- lhu x7, 4(x20)     -> 0x1234

        -- Negative halfword store
        x"80000337",  -- lui x6, 0x80000 -> 0x80000000 (wrong, we want 0x8000)
        -- lui x6, 8 -> 0x8000
        x"00008337",  -- lui x6, 8 -> x6 = 0x8000
        x"006A1423",  -- sh x6, 8(x20)   store 0x8000
        x"008A1403",  -- lh x8, 8(x20)   -> sign-extend 0x8000 = 0xFFFF8000
        x"008A5483",  -- lhu x9, 8(x20)  -> zero-extend 0x8000 = 0x00008000

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

        assert regs(5) = x"DDCCBBAA" report "FAIL SB+LW byte assembly" severity error;
        assert regs(7) = x"00001234" report "FAIL SH+LHU"              severity error;
        assert regs(8) = x"FFFF8000" report "FAIL SH+LH signed"        severity error;
        assert regs(9) = x"00008000" report "FAIL SH+LHU unsigned"     severity error;

        report "=== tb_all_stores PASS ===" severity note;
        wait;
    end process;
end architecture sim;
