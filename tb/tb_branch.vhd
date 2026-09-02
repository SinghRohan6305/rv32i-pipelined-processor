-- =============================================================================
-- tb_branch.vhd  —  Tests BEQ BNE BLT BGE BLTU BGEU
-- Each branch test: set a sentinel register if the wrong path executes.
-- If branch taken correctly -> sentinel stays 0.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_branch is
end entity tb_branch;

architecture sim of tb_branch is
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
    constant HEX_FILE : string := "/tmp/tb_branch.hex";

    -- Program layout (each instruction = 4 bytes):
    -- Addr 0x00: addi x1, x0, 5         x1=5
    -- Addr 0x04: addi x2, x0, 5         x2=5
    -- Addr 0x08: addi x3, x0, 10        x3=10
    -- Addr 0x0C: addi x28,x0, 0         x28=0 (error sentinel)
    --
    -- === BEQ taken: x1==x2 -> jump to 0x18 ===
    -- Addr 0x10: beq  x1, x2, +8        -> should jump to 0x18
    -- Addr 0x14: addi x28,x0, 1         ERROR if reached
    -- Addr 0x18: addi x10,x0, 1         PASS marker: x10=1
    --
    -- === BNE taken: x1!=x3 -> jump to 0x28 ===
    -- Addr 0x1C: bne  x1, x3, +8        -> should jump to 0x28
    -- Addr 0x20: addi x28,x0, 2         ERROR if reached
    -- Addr 0x24: nop
    -- Addr 0x28: addi x11,x0, 1         PASS: x11=1
    --
    -- === BLT taken: x1 < x3 -> jump to 0x38 ===
    -- Addr 0x2C: blt  x1, x3, +8        -> jump to 0x38? offset from 0x2C
    -- Addr 0x30: addi x28,x0, 3
    -- Addr 0x34: nop
    -- Addr 0x38: addi x12,x0, 1         PASS: x12=1
    --
    -- === BGE taken: x3 >= x1 -> jump ===
    -- Addr 0x3C: bge  x3, x1, +8
    -- Addr 0x40: addi x28,x0, 4
    -- Addr 0x44: nop
    -- Addr 0x48: addi x13,x0, 1         PASS: x13=1
    --
    -- === BLTU taken: unsigned x1(5) < x3(10) ===
    -- Addr 0x4C: bltu x1, x3, +8
    -- Addr 0x50: addi x28,x0, 5
    -- Addr 0x54: nop
    -- Addr 0x58: addi x14,x0, 1         PASS: x14=1
    --
    -- === BGEU taken: x3(10) >= x1(5) ===
    -- Addr 0x5C: bgeu x3, x1, +8
    -- Addr 0x60: addi x28,x0, 6
    -- Addr 0x64: nop
    -- Addr 0x68: addi x15,x0, 1         PASS: x15=1
    --
    -- Addr 0x6C...: nops

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 31) := (
        x"00500093",  -- 0x00: addi x1, x0, 5
        x"00500113",  -- 0x04: addi x2, x0, 5
        x"00A00193",  -- 0x08: addi x3, x0, 10
        x"00000E13",  -- 0x0C: addi x28,x0, 0  (sentinel)

        -- BEQ x1, x2, +8 (offset=8 -> target=0x10+8=0x18)
        x"00208463",  -- 0x10: beq x1, x2, +8
        x"00100E13",  -- 0x14: addi x28,x0,1   ERROR
        x"00100513",  -- 0x18: addi x10,x0,1   PASS

        -- BNE x1, x3, +8 (from 0x1C, target=0x24... wait need +12 to reach 0x28)
        -- offset = target - PC = 0x28 - 0x1C = 0xC = 12
        x"00309663",  -- 0x1C: bne x1, x3, +12 (0x1C+12=0x28)
        x"00200E13",  -- 0x20: addi x28,x0,2   ERROR
        x"00000013",  -- 0x24: nop
        x"00100593",  -- 0x28: addi x11,x0,1   PASS

        -- BLT x1, x3, +12 (from 0x2C, target=0x38; 0x38-0x2C=0xC=12)
        x"0030C663",  -- 0x2C: blt x1, x3, +12
        x"00300E13",  -- 0x30: addi x28,x0,3   ERROR
        x"00000013",  -- 0x34: nop
        x"00100613",  -- 0x38: addi x12,x0,1   PASS

        -- BGE x3, x1, +12 (from 0x3C, target=0x48; 0x48-0x3C=0xC=12)
        x"0011D663",  -- 0x3C: bge x3, x1, +12
        x"00400E13",  -- 0x40: addi x28,x0,4   ERROR
        x"00000013",  -- 0x44: nop
        x"00100693",  -- 0x48: addi x13,x0,1   PASS

        -- BLTU x1, x3, +12 (from 0x4C, target=0x58; 0x58-0x4C=0xC=12)
        x"0030E663",  -- 0x4C: bltu x1, x3, +12
        x"00500E13",  -- 0x50: addi x28,x0,5   ERROR
        x"00000013",  -- 0x54: nop
        x"00100713",  -- 0x58: addi x14,x0,1   PASS

        -- BGEU x3, x1, +12 (from 0x5C, target=0x68; 0x68-0x5C=0xC=12)
        x"0011F663",  -- 0x5C: bgeu x3, x1, +12
        x"00600E13",  -- 0x60: addi x28,x0,6   ERROR
        x"00000013",  -- 0x64: nop
        x"00100793",  -- 0x68: addi x15,x0,1   PASS

        x"00000013",  -- 0x6C: nop
        x"00000013",  -- 0x70: nop
        x"00000013",  -- 0x74: nop
        x"00000013"   -- 0x78: nop
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
        wait for 80 * CLK_P;

        assert regs(28) = 0  report "FAIL: wrong branch path executed (x28 != 0)" severity error;
        assert regs(10) = 1  report "FAIL BEQ  not taken"  severity error;
        assert regs(11) = 1  report "FAIL BNE  not taken"  severity error;
        assert regs(12) = 1  report "FAIL BLT  not taken"  severity error;
        assert regs(13) = 1  report "FAIL BGE  not taken"  severity error;
        assert regs(14) = 1  report "FAIL BLTU not taken"  severity error;
        assert regs(15) = 1  report "FAIL BGEU not taken"  severity error;

        report "=== tb_branch PASS ===" severity note;
        wait;
    end process;
end architecture sim;
