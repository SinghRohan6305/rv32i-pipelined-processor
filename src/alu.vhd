-- =============================================================================
-- alu.vhd  —  32-bit RV32I ALU
-- Supports: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, PASSB (LUI)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

entity alu is
    port (
        op     : in  std_logic_vector(3 downto 0);
        a      : in  std_logic_vector(31 downto 0);
        b      : in  std_logic_vector(31 downto 0);
        result : out std_logic_vector(31 downto 0);
        zero   : out std_logic  -- result == 0 (used for BEQ/BNE)
    );
end entity alu;

architecture rtl of alu is
    signal shamt : natural range 0 to 31;
    signal res   : std_logic_vector(31 downto 0);
begin
    shamt <= to_integer(unsigned(b(4 downto 0)));

    process(op, a, b, shamt)
        variable sa : signed(31 downto 0);
        variable ua : unsigned(31 downto 0);
        variable ub : unsigned(31 downto 0);
    begin
        sa := signed(a);
        ua := unsigned(a);
        ub := unsigned(b);

        case op is
            when ALU_ADD  => res <= std_logic_vector(signed(a)   + signed(b));
            when ALU_SUB  => res <= std_logic_vector(signed(a)   - signed(b));
            when ALU_AND  => res <= a and b;
            when ALU_OR   => res <= a or  b;
            when ALU_XOR  => res <= a xor b;
            when ALU_SLL  => res <= std_logic_vector(shift_left (ua, shamt));
            when ALU_SRL  => res <= std_logic_vector(shift_right(ua, shamt));
            when ALU_SRA  => res <= std_logic_vector(shift_right(sa, shamt));
            when ALU_SLT  =>
                if signed(a) < signed(b) then
                    res <= (0 => '1', others => '0');
                else
                    res <= (others => '0');
                end if;
            when ALU_SLTU =>
                if unsigned(a) < unsigned(b) then
                    res <= (0 => '1', others => '0');
                else
                    res <= (others => '0');
                end if;
            when ALU_PASSB => res <= b;           -- LUI: upper immediate already shifted in imm gen
            when others    => res <= (others => '0');
        end case;
    end process;

    result <= res;
    zero   <= '1' when res = x"00000000" else '0';

end architecture rtl;
