-- =============================================================================
-- tb_pkg.vhd  —  Shared testbench utilities
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package tb_pkg is

    -- Program image and shadow register file used by the pipeline TBs
    type prog_t is array(natural range <>) of std_logic_vector(31 downto 0);
    type reg_array_t is array(0 to 31) of std_logic_vector(31 downto 0);
    type int_array_t is array(0 to 31) of integer;

    -- Write a program to a hex file and return the path. Called while the TB
    -- architecture is elaborated, so the file exists before IMEM (which reads
    -- it during its own elaboration) is elaborated.
    impure function write_hex(path : string; prog : prog_t) return string;

    -- Compare one shadow register; on mismatch report and count an error.
    procedure check_reg(regs     : reg_array_t;
                        n        : natural;
                        expected : std_logic_vector(31 downto 0);
                        msg      : string;
                        variable errors : inout natural);

    -- Generic condition check with the same error counting.
    procedure check_cond(cond : boolean;
                         msg  : string;
                         variable errors : inout natural);

    -- Print the final verdict. Ends the simulation with a failure on errors.
    procedure finish_test(name : string; errors : natural);

    -- Clock period for 100 MHz
    constant CLK_PERIOD : time := 10 ns;

    -- Build a full 32-bit instruction word from fields
    function r_instr(funct7 : std_logic_vector(6 downto 0);
                     rs2    : std_logic_vector(4 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector;

    function i_instr(imm12  : std_logic_vector(11 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector;

    function s_instr(imm12  : std_logic_vector(11 downto 0);
                     rs2    : std_logic_vector(4 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector;

    function b_instr(imm13  : std_logic_vector(12 downto 0);  -- signed byte-offset, bit 0 = 0
                     rs2    : std_logic_vector(4 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector;

    function u_instr(imm20  : std_logic_vector(19 downto 0);
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector;

    function j_instr(imm21  : std_logic_vector(20 downto 0);  -- signed, bit 0 = 0
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector;

    -- Integer register address shorthand
    function reg(n : integer) return std_logic_vector;

    -- Assertion helper
    procedure check(signal clk : in std_logic;
                    actual   : std_logic_vector;
                    expected : std_logic_vector;
                    msg      : string);

end package tb_pkg;

package body tb_pkg is

    impure function write_hex(path : string; prog : prog_t) return string is
        file fh    : text;
        variable l : line;
    begin
        file_open(fh, path, WRITE_MODE);
        for i in prog'range loop
            hwrite(l, prog(i));
            writeline(fh, l);
        end loop;
        file_close(fh);
        return path;
    end function;

    procedure check_reg(regs     : reg_array_t;
                        n        : natural;
                        expected : std_logic_vector(31 downto 0);
                        msg      : string;
                        variable errors : inout natural) is
    begin
        if regs(n) /= expected then
            report "FAIL: " & msg & "  x" & integer'image(n) &
                   " = 0x" & to_hstring(regs(n)) &
                   ", expected 0x" & to_hstring(expected)
                severity error;
            errors := errors + 1;
        end if;
    end procedure;

    procedure check_cond(cond : boolean;
                         msg  : string;
                         variable errors : inout natural) is
    begin
        if not cond then
            report "FAIL: " & msg severity error;
            errors := errors + 1;
        end if;
    end procedure;

    procedure finish_test(name : string; errors : natural) is
    begin
        if errors = 0 then
            report "=== " & name & " PASS ===" severity note;
        else
            report "=== " & name & " FAILED with " & integer'image(errors) &
                   " error(s) ===" severity failure;
        end if;
    end procedure;

    function r_instr(funct7 : std_logic_vector(6 downto 0);
                     rs2    : std_logic_vector(4 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector is
    begin
        return funct7 & rs2 & rs1 & funct3 & rd & opcode;
    end function;

    function i_instr(imm12  : std_logic_vector(11 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector is
    begin
        return imm12 & rs1 & funct3 & rd & opcode;
    end function;

    function s_instr(imm12  : std_logic_vector(11 downto 0);
                     rs2    : std_logic_vector(4 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector is
    begin
        return imm12(11 downto 5) & rs2 & rs1 & funct3 & imm12(4 downto 0) & opcode;
    end function;

    function b_instr(imm13  : std_logic_vector(12 downto 0);
                     rs2    : std_logic_vector(4 downto 0);
                     rs1    : std_logic_vector(4 downto 0);
                     funct3 : std_logic_vector(2 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector is
    begin
        -- B-type: [31]=imm[12], [30:25]=imm[10:5], [11:8]=imm[4:1], [7]=imm[11]
        return imm13(12) & imm13(10 downto 5) & rs2 & rs1 & funct3
             & imm13(4 downto 1) & imm13(11) & opcode;
    end function;

    function u_instr(imm20  : std_logic_vector(19 downto 0);
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector is
    begin
        return imm20 & rd & opcode;
    end function;

    function j_instr(imm21  : std_logic_vector(20 downto 0);
                     rd     : std_logic_vector(4 downto 0);
                     opcode : std_logic_vector(6 downto 0))
             return std_logic_vector is
    begin
        -- J-type: [31]=imm[20],[30:21]=imm[10:1],[20]=imm[11],[19:12]=imm[19:12]
        return imm21(20) & imm21(10 downto 1) & imm21(11) & imm21(19 downto 12)
             & rd & opcode;
    end function;

    function reg(n : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 5));
    end function;

    procedure check(signal clk : in std_logic;
                    actual   : std_logic_vector;
                    expected : std_logic_vector;
                    msg      : string) is
    begin
        assert actual = expected
            report "FAIL: " & msg &
                   "  got=" & integer'image(to_integer(unsigned(actual))) &
                   " exp=" & integer'image(to_integer(unsigned(expected)))
            severity error;
    end procedure;

end package body tb_pkg;
