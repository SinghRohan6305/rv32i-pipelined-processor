-- =============================================================================
-- tb_dmem.vhd  —  Data memory unit tests
-- Tests byte/halfword/word writes and reads (signed and unsigned extension).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

entity tb_dmem is
end entity tb_dmem;

architecture sim of tb_dmem is
    signal clk   : std_logic := '0';
    signal we    : std_logic := '0';
    signal re    : std_logic := '0';
    signal size  : std_logic_vector(2 downto 0) := "010";
    signal addr  : std_logic_vector(31 downto 0) := (others => '0');
    signal wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal rdata : std_logic_vector(31 downto 0);

    constant CLK_P : time := 10 ns;

    procedure write_mem(
        signal clk   : in  std_logic;
        signal we    : out std_logic;
        signal size  : out std_logic_vector(2 downto 0);
        signal addr  : out std_logic_vector(31 downto 0);
        signal wdata : out std_logic_vector(31 downto 0);
        sz           : std_logic_vector(2 downto 0);
        a            : integer;
        d            : std_logic_vector(31 downto 0)) is
    begin
        addr  <= std_logic_vector(to_unsigned(a, 32));
        wdata <= d;
        size  <= sz;
        we    <= '1';
        wait until rising_edge(clk);
        we <= '0';
    end procedure;

    procedure read_mem(
        signal clk  : in  std_logic;
        signal re   : out std_logic;
        signal size : out std_logic_vector(2 downto 0);
        signal addr : out std_logic_vector(31 downto 0);
        sz          : std_logic_vector(2 downto 0);
        a           : integer) is
    begin
        addr <= std_logic_vector(to_unsigned(a, 32));
        size <= sz;
        re   <= '1';
        wait until rising_edge(clk);
        re <= '0';
        wait for 1 ns;
    end procedure;

begin
    clk <= not clk after CLK_P/2;

    dut: entity work.dmem
        generic map (MEM_DEPTH => 256)
        port map (clk => clk, we => we, size => size, addr => addr,
                  wdata => wdata, re => re, rdata => rdata);

    process
    begin
        -- ---- Word write/read ----
        write_mem(clk, we, size, addr, wdata, F3_SW, 0, x"DEADBEEF");
        read_mem (clk, re, size, addr,        F3_LW, 0);
        assert rdata = x"DEADBEEF" report "FAIL LW" severity error;
        report "PASS LW/SW" severity note;

        -- ---- Halfword write, signed read ----
        write_mem(clk, we, size, addr, wdata, F3_SH, 4, x"FFFF8000");
        read_mem (clk, re, size, addr,        F3_LH, 4);
        assert rdata = x"FFFF8000" report "FAIL LH sign ext" severity error;
        report "PASS LH signed extend 0x8000->0xFFFF8000" severity note;

        -- ---- Halfword write, unsigned read ----
        read_mem (clk, re, size, addr, F3_LHU, 4);
        assert rdata = x"00008000" report "FAIL LHU zero ext" severity error;
        report "PASS LHU zero extend 0x8000->0x00008000" severity note;

        -- ---- Positive halfword ----
        write_mem(clk, we, size, addr, wdata, F3_SH, 8, x"00007FFF");
        read_mem (clk, re, size, addr, F3_LH, 8);
        assert rdata = x"00007FFF" report "FAIL LH positive" severity error;
        report "PASS LH positive halfword" severity note;

        -- ---- Byte write, signed read ----
        write_mem(clk, we, size, addr, wdata, F3_SB, 12, x"000000FF");
        read_mem (clk, re, size, addr, F3_LB, 12);
        assert rdata = x"FFFFFFFF" report "FAIL LB sign ext 0xFF" severity error;
        report "PASS LB signed extend 0xFF->-1" severity note;

        -- ---- Byte write, unsigned read ----
        read_mem (clk, re, size, addr, F3_LBU, 12);
        assert rdata = x"000000FF" report "FAIL LBU zero ext" severity error;
        report "PASS LBU zero extend 0xFF->255" severity note;

        -- ---- Positive byte ----
        write_mem(clk, we, size, addr, wdata, F3_SB, 16, x"0000007F");
        read_mem (clk, re, size, addr, F3_LB, 16);
        assert rdata = x"0000007F" report "FAIL LB positive 0x7F" severity error;
        report "PASS LB positive byte" severity note;

        -- ---- Write to different byte offsets in same word ----
        write_mem(clk, we, size, addr, wdata, F3_SB, 20, x"000000AA");
        write_mem(clk, we, size, addr, wdata, F3_SB, 21, x"000000BB");
        write_mem(clk, we, size, addr, wdata, F3_SB, 22, x"000000CC");
        write_mem(clk, we, size, addr, wdata, F3_SB, 23, x"000000DD");
        read_mem (clk, re, size, addr, F3_LW, 20);
        assert rdata = x"DDCCBBAA" report "FAIL byte-addressed LW" severity error;
        report "PASS byte-addressed word assembly" severity note;

        report "=== tb_dmem PASS ===" severity note;
        wait;
    end process;
end architecture sim;
