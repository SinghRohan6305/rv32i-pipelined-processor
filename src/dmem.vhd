-- =============================================================================
-- dmem.vhd  —  Data memory  (1 KB, byte-addressable, synchronous)
-- Supports byte (LB/SB), halfword (LH/SH), and word (LW/SW) accesses.
-- Sign/zero-extension for loads is done here.
-- On Cyclone V this maps to an M10K block.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

entity dmem is
    generic (
        MEM_DEPTH : integer := 256  -- words (1 KB)
    );
    port (
        clk      : in  std_logic;
        -- Write port (synchronous)
        we       : in  std_logic;
        size     : in  std_logic_vector(2 downto 0);  -- funct3
        addr     : in  std_logic_vector(31 downto 0);
        wdata    : in  std_logic_vector(31 downto 0);
        -- Read port (synchronous, registered)
        re       : in  std_logic;
        rdata    : out std_logic_vector(31 downto 0)
    );
end entity dmem;

architecture rtl of dmem is
    -- Byte-addressable storage: 4 * MEM_DEPTH bytes
    type mem_t is array(0 to MEM_DEPTH*4 - 1) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => x"00");

    constant MEM_BYTES : integer := MEM_DEPTH * 4;

    -- Byte addresses of the 4 bytes starting at addr, wrapped into the array.
    -- Only the low 16 address bits are used, so a 32-bit address (which may be
    -- larger than VHDL's integer range) never has to be converted whole.
    signal b0, b1, b2, b3 : integer range 0 to MEM_BYTES - 1;
begin
    b0 <= to_integer(unsigned(addr(15 downto 0)))     mod MEM_BYTES;
    b1 <= (to_integer(unsigned(addr(15 downto 0))) + 1) mod MEM_BYTES;
    b2 <= (to_integer(unsigned(addr(15 downto 0))) + 2) mod MEM_BYTES;
    b3 <= (to_integer(unsigned(addr(15 downto 0))) + 3) mod MEM_BYTES;

    -- -------------------------------------------------------------------------
    -- Synchronous write (byte-enable)
    -- -------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                case size is
                    when F3_SW =>  -- word
                        mem(b0) <= wdata( 7 downto  0);
                        mem(b1) <= wdata(15 downto  8);
                        mem(b2) <= wdata(23 downto 16);
                        mem(b3) <= wdata(31 downto 24);
                    when F3_SH =>  -- halfword
                        mem(b0) <= wdata( 7 downto  0);
                        mem(b1) <= wdata(15 downto  8);
                    when F3_SB =>  -- byte
                        mem(b0) <= wdata( 7 downto  0);
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Synchronous read with sign/zero extension
    -- -------------------------------------------------------------------------
    process(clk)
        variable raw_byte : std_logic_vector(7 downto 0);
        variable raw_half : std_logic_vector(15 downto 0);
        variable raw_word : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk) then
            if re = '1' then
                raw_byte := mem(b0);
                raw_half := mem(b1) & mem(b0);
                raw_word := mem(b3) & mem(b2)
                          & mem(b1) & mem(b0);
                case size is
                    when F3_LW  => rdata <= raw_word;
                    when F3_LH  => rdata <= std_logic_vector(resize(signed(raw_half),   32));
                    when F3_LHU => rdata <= std_logic_vector(resize(unsigned(raw_half), 32));
                    when F3_LB  => rdata <= std_logic_vector(resize(signed(raw_byte),   32));
                    when F3_LBU => rdata <= std_logic_vector(resize(unsigned(raw_byte), 32));
                    when others => rdata <= raw_word;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
