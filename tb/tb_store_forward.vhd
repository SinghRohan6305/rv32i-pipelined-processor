-- =============================================================================
-- tb_store_forward.vhd  —  Forwarding to store's RS2 (data port)
-- Tests that a value computed in EX can be forwarded to the store data input.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.pkg_riscv.all;

entity tb_store_forward is
end entity tb_store_forward;

architecture sim of tb_store_forward is
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
    constant HEX_FILE : string := "/tmp/tb_store_fwd.hex";

    -- Program:
    -- addi x1, x0, 77      x1 = 77
    -- addi x20, x0, 256    x20 = base addr
    -- sw   x1, 0(x20)      store 77  (x1 should be forwarded to store)
    -- addi x2, x0, 88      x2 = 88
    -- sw   x2, 4(x20)      store 88  (x2 forward from EX/MEM to store data)
    -- lw   x3, 0(x20)      x3 = 77
    -- lw   x4, 4(x20)      x4 = 88

    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    constant PROG : prog_t(0 to 13) := (
        x"04D00093",  -- addi x1, x0, 77
        x"10000A13",  -- addi x20, x0, 256
        x"001A2023",  -- sw x1, 0(x20)
        x"05800113",  -- addi x2, x0, 88
        x"002A2223",  -- sw x2, 4(x20)
        x"000A2183",  -- lw x3, 0(x20)    -> 77
        x"004A2203",  -- lw x4, 4(x20)    -> 88
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
        wait for 40 * CLK_P;

        assert regs(3) = 77 report "FAIL store-fwd x3=77" severity error;
        assert regs(4) = 88 report "FAIL store-fwd x4=88" severity error;

        report "=== tb_store_forward PASS ===" severity note;
        wait;
    end process;
end architecture sim;
