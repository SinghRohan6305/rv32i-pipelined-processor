-- =============================================================================
-- regfile.vhd  —  32 x 32-bit register file
-- x0 is hardwired to 0.  Two async read ports, one sync write port.
-- Write-then-read in same cycle: forwarded combinatorially to avoid stale read.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regfile is
    port (
        clk    : in  std_logic;
        -- Write port (WB stage)
        we     : in  std_logic;
        wa     : in  std_logic_vector(4 downto 0);
        wd     : in  std_logic_vector(31 downto 0);
        -- Read port 1 (ID stage, RS1)
        ra1    : in  std_logic_vector(4 downto 0);
        rd1    : out std_logic_vector(31 downto 0);
        -- Read port 2 (ID stage, RS2)
        ra2    : in  std_logic_vector(4 downto 0);
        rd2    : out std_logic_vector(31 downto 0)
    );
end entity regfile;

architecture rtl of regfile is
    type reg_array is array(0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));
begin
    -- Synchronous write
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' and unsigned(wa) /= 0 then
                regs(to_integer(unsigned(wa))) <= wd;
            end if;
        end if;
    end process;

    -- Asynchronous read with write-through forwarding
    rd1 <= (others => '0')       when unsigned(ra1) = 0 else
           wd                    when (we = '1' and ra1 = wa) else
           regs(to_integer(unsigned(ra1)));

    rd2 <= (others => '0')       when unsigned(ra2) = 0 else
           wd                    when (we = '1' and ra2 = wa) else
           regs(to_integer(unsigned(ra2)));

end architecture rtl;
