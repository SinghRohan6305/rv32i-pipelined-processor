-- =============================================================================
-- tb_consecutive_branches.vhd  —  Two branches back-to-back
-- Tests that the pipeline flushes correctly when two branches are in flight.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_consecutive_branches is
end entity tb_consecutive_branches;

architecture sim of tb_consecutive_branches is
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
    constant HEX_FILE : string := "/tmp/tb_consec_br.hex";

    -- Program:
    -- 0x00: addi x1, x0, 5
    -- 0x04: addi x2, x0, 5
    -- 0x08: addi x3, x0, 10
    -- First branch (taken): BEQ x1, x2 -> +20 = 0x1C
    -- 0x0C: beq x1, x2, +16    -> target=0x0C+16=0x1C
    -- 0x10: addi x29, x0, 1    (ERROR: should be flushed)
    -- 0x14: addi x29, x0, 2    (ERROR: should be flushed)
    -- 0x18: nop
    -- Second branch (taken): BNE x1, x3 -> +16 = 0x2C
    -- 0x1C: bne x1, x3, +16    -> target=0x1C+16=0x2C
    -- 0x20: addi x29, x0, 3    (ERROR: should be flushed)
    -- 0x24: addi x29, x0, 4    (ERROR: should be flushed)
    -- 0x28: nop
    -- 0x2C: addi x10, x0, 99   PASS

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 15) := (
        x"00500093",  -- 0x00: addi x1, x0, 5
        x"00500113",  -- 0x04: addi x2, x0, 5
        x"00A00193",  -- 0x08: addi x3, x0, 10
        -- BEQ x1, x2, +16  (offset=16 from 0x0C -> 0x1C)
        -- B-type: imm=16=0x10: bit12=0,bit11=0,bit10:5=000000,bit4:1=1000
        -- [31]=0,[30:25]=000000,[24:20]=x2,[19:15]=x1,[14:12]=000,[11:8]=1000,[7]=0,[6:0]=1100011
        -- = 0000 0000 0010 0000 1000 1000 0110 0011 = 0x00208863
        x"00208863",  -- 0x0C: beq x1, x2, +16
        x"00100E93",  -- 0x10: addi x29, x0, 1  ERROR
        x"00200E93",  -- 0x14: addi x29, x0, 2  ERROR
        x"00000013",  -- 0x18: nop
        -- BNE x1, x3, +16  (offset=16 from 0x1C -> 0x2C)
        -- [31]=0,[30:25]=000000,rs2=x3=00011,rs1=x1=00001,funct3=001,[11:8]=1000,[7]=0,op=1100011
        -- = 0000 0000 0011 0000 1001 1000 0110 0011 = 0x00309863
        x"00309863",  -- 0x1C: bne x1, x3, +16
        x"00300E93",  -- 0x20: addi x29, x0, 3  ERROR
        x"00400E93",  -- 0x24: addi x29, x0, 4  ERROR
        x"00000013",  -- 0x28: nop
        x"06300513",  -- 0x2C: addi x10, x0, 99  PASS
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
        wait for 60 * CLK_P;

        assert regs(29) = 0  report "FAIL: wrong path executed" severity error;
        assert regs(10) = 99 report "FAIL: x10 should be 99"   severity error;

        report "=== tb_consecutive_branches PASS ===" severity note;
        wait;
    end process;
end architecture sim;
