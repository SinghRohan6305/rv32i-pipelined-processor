-- =============================================================================
-- imem.vhd  —  Instruction memory  (1 KB, word-addressed, synchronous read)
-- Initialised from the generic INIT_FILE or left as all-NOPs.
-- On Cyclone V this maps to an M10K block.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity imem is
    generic (
        MEM_DEPTH : integer := 256;  -- number of 32-bit words (1 KB)
        INIT_FILE : string  := ""    -- optional .hex file path
    );
    port (
        clk  : in  std_logic;
        addr : in  std_logic_vector(31 downto 0);  -- byte address, word-aligned
        instr: out std_logic_vector(31 downto 0)
    );
end entity imem;

architecture rtl of imem is
    type mem_t is array(0 to MEM_DEPTH-1) of std_logic_vector(31 downto 0);

    -- Initialise all words to NOP (ADDI x0,x0,0 = 0x00000013)
    impure function init_mem return mem_t is
        variable m   : mem_t := (others => x"00000013");
        variable l   : line;
        variable w   : std_logic_vector(31 downto 0);
        file fh      : text;
        variable idx : integer := 0;
    begin
        if INIT_FILE /= "" then
            file_open(fh, INIT_FILE, READ_MODE);
            while not endfile(fh) and idx < MEM_DEPTH loop
                readline(fh, l);
                hread(l, w);
                m(idx) := w;
                idx := idx + 1;
            end loop;
            file_close(fh);
        end if;
        return m;
    end function;

    signal mem : mem_t := init_mem;
    signal word_addr : integer range 0 to MEM_DEPTH-1;
begin
    word_addr <= to_integer(unsigned(addr(31 downto 2))) mod MEM_DEPTH;

    process(clk)
    begin
        if rising_edge(clk) then
            instr <= mem(word_addr);
        end if;
    end process;

end architecture rtl;
