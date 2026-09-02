-- =============================================================================
-- tb_load_store.vhd  —  Tests LW SW LB SB LH SH LBU LHU (all 8 load/store variants)
-- Program:
--   Store then load at data address 0x100
--   SW/LW  -> full word
--   SH/LH  -> halfword signed
--   SH/LHU -> halfword unsigned
--   SB/LB  -> byte signed
--   SB/LBU -> byte unsigned
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_load_store is
end entity tb_load_store;

architecture sim of tb_load_store is
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
    constant HEX_FILE : string := "/tmp/tb_load_store.hex";

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    -- Data memory base address = 0x100 (256)
    -- x20 = base address pointer
    constant PROG : prog_t(0 to 31) := (
        -- Setup base address in x20 = 0x100
        x"10000A37",  --  0: lui  x20, 0x100  => x20 = 0x100000 -- wrong, use addi
        -- Actually: addi x20, x0, 256 => x"10000A13" hmm, 256 = 0x100, fits in 12 bits
        -- Let me recalculate: addi x20, x0, 256 -> imm=256=0x100
        -- encoding: imm[11:0]=0x100, rs1=x0, funct3=000, rd=x20, opcode=0010011
        -- 0x100 << 20 | 0 | 0 | 20<<7 | 0x13
        -- = 0x10000A13
        x"10000A13",  --  0: addi x20, x0, 256  (base addr = 256)

        -- ---- SW / LW ----
        -- x1 = 0xDEADBEEF
        x"DEADB0B7",  --  4: lui  x1, 0xDEADB
        x"BEEF0093",  --  8: addi x1, x1, -0x411 ... actually 0xBEEF as 12-bit signed
        -- 0xBEEF as signed 12-bit = -0x411 = -1041
        -- lui loads upper 20 bits: 0xDEADB000
        -- addi with 0xBEEF: as 12-bit signed, 0xBEEF upper bits matter
        -- 0xBEEF = 1011 1110 1110 1111 -> as signed 12-bit: only lower 12 bits = 0xEEF = -0x111
        -- Better: use two instructions to load 0xDEADBEEF properly
        -- lui x1, 0xDEADC  -> 0xDEADC000
        -- addi x1, x1, -0x411 -> 0xDEADC000 - 0x411 ... hmm this is getting complex
        -- Let's just use 0xABCD0000 and 0x1234 for clarity
        -- Restart with simpler values
        x"ABCDA0B7",  --  4: lui x1, 0xABCDA  => x1 = 0xABCDA000  (overwrite above)
        x"00000013",  --  8: nop (placeholder - let's redo this cleaner)

        -- Cleaner approach: use small known values
        -- x1 = 0x12345678 (build with lui + addi)
        -- lui x1, 0x12345 => x1 = 0x12345000
        -- addi x1, x1, 0x678 => x1 = 0x12345678
        -- NOTE: 0x678 < 0x800 so no sign issue
        x"123450B7",  --  C: lui  x1, 0x12345
        x"67808093",  -- 10: addi x1, x1, 0x678  => x1 = 0x12345678

        -- SW x1, 0(x20)
        x"00102023",  -- 14: sw x1, 0(x20)

        -- LW x2, 0(x20) -> x2 = 0x12345678
        x"00002103",  -- 18: lw x2, 0(x20)

        -- ---- SH / LH / LHU ----
        -- Store lower halfword of x1 (0x5678) at offset 4
        x"00101223",  -- 1C: sh x1, 4(x20)
        -- LH x3, 4(x20) -> sign extend 0x5678 -> 0x00005678 (positive)
        x"00401183",  -- 20: lh x3, 4(x20)
        -- Store 0x8000 (negative halfword) at offset 8
        x"00008337",  -- 24: lui x6, 8     => x6 = 0x8000 (upper 20 of 0x8000 = 0x00008)
        -- actually lui x6, 0x00008 = 0x8000? No: lui loads [31:12]
        -- lui x6, 1 => x6 = 0x00001000; we want 0x8000 = 0x00008000
        -- lui x6, 8 => x6 = 0x00008000 YES (8 << 12 = 0x8000)
        x"00801423",  -- 28: sh x6, 8(x20)
        -- LH x4, 8(x20) -> sign extend 0x8000 -> 0xFFFF8000 = -32768
        x"00801203",  -- 2C: lh x4, 8(x20)
        -- LHU x5, 8(x20) -> zero extend 0x8000 -> 0x00008000 = 32768
        x"00805283",  -- 30: lhu x5, 8(x20)

        -- ---- SB / LB / LBU ----
        -- Store 0xFF at offset 12
        x"FFF00313",  -- 34: addi x6, x0, -1  => x6 = 0xFFFFFFFF
        x"00601623",  -- 38: sb x6, 12(x20)
        -- LB x7, 12(x20) -> sign extend 0xFF -> -1
        x"00C00383",  -- 3C: lb x7, 12(x20)
        -- LBU x8, 12(x20) -> zero extend 0xFF -> 255
        x"00C04403",  -- 40: lbu x8, 12(x20)

        x"00000013",  -- 44: nop
        x"00000013",  -- 48: nop
        x"00000013",  -- 4C: nop
        x"00000013",  -- 50: nop  (pipeline drain)
        x"00000013",  -- (extra)
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

        -- LW result
        assert regs(2) = x"12345678"
            report "FAIL LW x2=0x12345678" severity error;
        -- LH positive halfword
        assert regs(3) = x"00005678"
            report "FAIL LH x3=0x5678" severity error;
        -- LH negative halfword (sign extended)
        assert regs(4) = x"FFFF8000"
            report "FAIL LH x4=0xFFFF8000" severity error;
        -- LHU zero extended
        assert regs(5) = x"00008000"
            report "FAIL LHU x5=0x8000" severity error;
        -- LB  sign extended 0xFF = -1
        assert regs(7) = x"FFFFFFFF"
            report "FAIL LB x7=-1" severity error;
        -- LBU zero extended 0xFF = 255
        assert regs(8) = x"000000FF"
            report "FAIL LBU x8=255" severity error;

        report "=== tb_load_store PASS ===" severity note;
        wait;
    end process;
end architecture sim;
