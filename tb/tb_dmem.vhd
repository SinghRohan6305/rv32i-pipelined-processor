-- =============================================================================
-- tb_dmem.vhd  —  Data memory unit tests
-- Tests byte/halfword/word writes and reads (signed and unsigned extension).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;
use work.tb_pkg.all;

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
        variable errors : natural := 0;

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
    begin
        -- ---- Word write/read ----
        write_mem(clk, we, size, addr, wdata, F3_SW, 0, x"DEADBEEF");
        read_mem (clk, re, size, addr,        F3_LW, 0);
        check_cond(rdata = x"DEADBEEF", "LW", errors);

        -- ---- Halfword write, signed read ----
        write_mem(clk, we, size, addr, wdata, F3_SH, 4, x"FFFF8000");
        read_mem (clk, re, size, addr,        F3_LH, 4);
        check_cond(rdata = x"FFFF8000", "LH sign ext", errors);

        -- ---- Halfword write, unsigned read ----
        read_mem (clk, re, size, addr, F3_LHU, 4);
        check_cond(rdata = x"00008000", "LHU zero ext", errors);

        -- ---- Positive halfword ----
        write_mem(clk, we, size, addr, wdata, F3_SH, 8, x"00007FFF");
        read_mem (clk, re, size, addr, F3_LH, 8);
        check_cond(rdata = x"00007FFF", "LH positive", errors);

        -- ---- Byte write, signed read ----
        write_mem(clk, we, size, addr, wdata, F3_SB, 12, x"000000FF");
        read_mem (clk, re, size, addr, F3_LB, 12);
        check_cond(rdata = x"FFFFFFFF", "LB sign ext 0xFF", errors);

        -- ---- Byte write, unsigned read ----
        read_mem (clk, re, size, addr, F3_LBU, 12);
        check_cond(rdata = x"000000FF", "LBU zero ext", errors);

        -- ---- Positive byte ----
        write_mem(clk, we, size, addr, wdata, F3_SB, 16, x"0000007F");
        read_mem (clk, re, size, addr, F3_LB, 16);
        check_cond(rdata = x"0000007F", "LB positive 0x7F", errors);

        -- ---- Write to different byte offsets in same word ----
        write_mem(clk, we, size, addr, wdata, F3_SB, 20, x"000000AA");
        write_mem(clk, we, size, addr, wdata, F3_SB, 21, x"000000BB");
        write_mem(clk, we, size, addr, wdata, F3_SB, 22, x"000000CC");
        write_mem(clk, we, size, addr, wdata, F3_SB, 23, x"000000DD");
        read_mem (clk, re, size, addr, F3_LW, 20);
        check_cond(rdata = x"DDCCBBAA", "byte-addressed LW", errors);

        finish_test("tb_dmem", errors);
        wait;
    end process;
end architecture sim;
