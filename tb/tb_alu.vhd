-- =============================================================================
-- tb_alu.vhd  —  Unit tests for the ALU (all operations)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;
use work.tb_pkg.all;

entity tb_alu is
end entity tb_alu;

architecture sim of tb_alu is
    signal op     : std_logic_vector(3 downto 0);
    signal a, b   : std_logic_vector(31 downto 0);
    signal result : std_logic_vector(31 downto 0);
    signal zero   : std_logic;


begin
    dut: entity work.alu
        port map (op => op, a => a, b => b, result => result, zero => zero);

    process
        variable errors : natural := 0;

        procedure chk(op_i : std_logic_vector(3 downto 0);
                      a_i  : integer;
                      b_i  : integer;
                      exp  : integer;
                      msg  : string) is
            variable exp_v : std_logic_vector(31 downto 0);
        begin
            op <= op_i;
            a  <= std_logic_vector(to_signed(a_i, 32));
            b  <= std_logic_vector(to_signed(b_i, 32));
            wait for 5 ns;
            exp_v := std_logic_vector(to_signed(exp, 32));
            check_cond(result = exp_v, "" & msg &
                       " got=" & integer'image(to_integer(signed(result))) &
                       " exp=" & integer'image(exp), errors);
        end procedure;
    begin
        -- ADD
        chk(ALU_ADD, 10,  20,  30,  "ADD 10+20");
        chk(ALU_ADD, -5,   3,  -2,  "ADD -5+3");
        chk(ALU_ADD,  0,   0,   0,  "ADD 0+0");

        -- SUB
        chk(ALU_SUB, 20,  10,  10,  "SUB 20-10");
        chk(ALU_SUB,  5,  10,  -5,  "SUB 5-10");

        -- AND
        chk(ALU_AND, 16#FF00#, 16#0FF0#, 16#0F00#, "AND");

        -- OR
        chk(ALU_OR,  16#FF00#, 16#00FF#, 16#FFFF#, "OR");

        -- XOR
        chk(ALU_XOR, 16#AAAA#, 16#5555#, 16#FFFF#, "XOR");

        -- SLL
        chk(ALU_SLL, 1, 4, 16, "SLL 1<<4");
        chk(ALU_SLL, 1, 31, -2147483648, "SLL 1<<31");

        -- SRL  (logical)
        chk(ALU_SRL, -2, 1, 2147483647, "SRL -2>>1 logical");  -- 0x7FFFFFFF

        -- SRA  (arithmetic)
        chk(ALU_SRA, -4, 1, -2, "SRA -4>>1");
        chk(ALU_SRA, 8,  2,  2, "SRA 8>>2");

        -- SLT  (signed)
        chk(ALU_SLT, -1, 0,  1, "SLT -1 < 0");
        chk(ALU_SLT,  1, 0,  0, "SLT 1 < 0 false");

        -- SLTU (unsigned)
        op <= ALU_SLTU;
        a  <= x"FFFFFFFF";  -- 4294967295 unsigned
        b  <= x"00000001";  -- 1
        wait for 5 ns;
        check_cond(result = x"00000000", "SLTU large < 1", errors);

        op <= ALU_SLTU;
        a  <= x"00000001";
        b  <= x"FFFFFFFF";
        wait for 5 ns;
        check_cond(result = x"00000001", "SLTU 1 < large", errors);

        -- PASSB (LUI)
        chk(ALU_PASSB, 0, 16#5EAD0000#, 16#5EAD0000#, "PASSB LUI");  -- must fit a VHDL integer

        -- ZERO flag
        op <= ALU_SUB;
        a  <= x"00000005";
        b  <= x"00000005";
        wait for 5 ns;
        check_cond(zero = '1', "zero flag", errors);

        op <= ALU_ADD;
        a  <= x"00000001";
        b  <= x"00000000";
        wait for 5 ns;
        check_cond(zero = '0', "non-zero flag", errors);

        finish_test("tb_alu", errors);
        wait;
    end process;
end architecture sim;
