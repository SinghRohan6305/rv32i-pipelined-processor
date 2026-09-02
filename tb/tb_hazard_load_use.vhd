-- =============================================================================
-- tb_hazard_load_use.vhd  —  Load-use hazard: pipeline must stall 1 cycle
-- LW followed immediately by an instruction that uses the loaded value.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_hazard_load_use is
end entity tb_hazard_load_use;

architecture sim of tb_hazard_load_use is
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
    constant HEX_FILE : string := "/tmp/tb_hazard_load_use.hex";

    -- Program:
    -- Step 1: store known value to data memory
    --   addi x1, x0, 42         x1 = 42
    --   addi x20, x0, 0x100     x20 = base addr = 256
    --   sw   x1, 0(x20)         mem[256] = 42
    --
    -- Step 2: load-use hazard test
    --   lw   x2, 0(x20)         x2 = 42  (load)
    --   add  x3, x2, x2         x3 = 84  (USE x2 immediately = load-use hazard -> stall)
    --
    -- Step 3: load then skip-one then use (no stall needed)
    --   lw   x4, 0(x20)         x4 = 42
    --   addi x5, x0, 8          (independent, no dependency on x4)
    --   add  x6, x4, x5         x6 = 50  (x4 forwarded from MEM/WB, no stall)
    --
    -- Step 4: LB sign-extend test
    --   addi x7, x0, -128       x7 = 0xFFFFFF80
    --   sb   x7, 4(x20)         store byte -128 at 260
    --   lb   x8, 4(x20)         x8 = -128 (sign extended)
    --   add  x9, x8, x8         x9 = -256

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 23) := (
        x"02A00093",  -- 0x00: addi x1, x0, 42
        x"10000A13",  -- 0x04: addi x20, x0, 256
        x"00102023",  -- 0x08: sw x1, 0(x20)
        x"00002103",  -- 0x0C: lw x2, 0(x20)        LOAD
        x"00210133",  -- 0x10: add x3, x2, x2       USE x2 (load-use hazard)
        x"00002203",  -- 0x14: lw x4, 0(x20)        LOAD
        x"00800293",  -- 0x18: addi x5, x0, 8       independent
        x"00520333",  -- 0x1C: add x6, x4, x5       USE x4 (no stall needed)
        x"F8000393",  -- 0x20: addi x7, x0, -128
        x"007A0223",  -- 0x24: sb x7, 4(x20)
        x"004A0403",  -- 0x28: lb x8, 4(x20)        LOAD BYTE
        x"00840433",  -- 0x2C: add x9, x8, x8       USE x8 (load-use)
        x"00000013",  -- nop
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

        assert regs(2)  = 42   report "FAIL lw x2=42"      severity error;
        assert regs(3)  = 84   report "FAIL load-use x3=84" severity error;
        assert regs(4)  = 42   report "FAIL lw x4=42"       severity error;
        assert regs(5)  = 8    report "FAIL x5=8"           severity error;
        assert regs(6)  = 50   report "FAIL no-stall x6=50" severity error;
        assert regs(8)  = -128 report "FAIL lb x8=-128"     severity error;
        assert regs(9)  = -256 report "FAIL load-use x9=-256" severity error;

        report "=== tb_hazard_load_use PASS ===" severity note;
        wait;
    end process;
end architecture sim;
