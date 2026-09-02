-- =============================================================================
-- pipeline_top.vhd  —  RV32I 5-stage pipeline top-level
--
-- Stages: IF → ID → EX → MEM → WB
-- Features:
--   • All 40 RV32I base instructions
--   • Hazard detection unit (load-use stall)
--   • 2-stage data forwarding (EX/MEM → EX, MEM/WB → EX)
--   • 1-bit branch predictor with misprediction flush
--   • Separate instruction and data memories (Harvard, on-chip BRAM)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_riscv.all;

entity pipeline_top is
    generic (
        MEM_DEPTH    : integer := 256;
        IMEM_INIT    : string  := ""
    );
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        -- Debug / testbench observation ports
        dbg_pc      : out std_logic_vector(31 downto 0);
        dbg_instr   : out std_logic_vector(31 downto 0);
        dbg_reg_we  : out std_logic;
        dbg_reg_wa  : out std_logic_vector(4 downto 0);
        dbg_reg_wd  : out std_logic_vector(31 downto 0)
    );
end entity pipeline_top;

architecture rtl of pipeline_top is

    -- =========================================================================
    -- Component declarations
    -- =========================================================================
    component imem is
        generic (MEM_DEPTH : integer; INIT_FILE : string);
        port (clk : in std_logic; addr : in std_logic_vector(31 downto 0);
              instr : out std_logic_vector(31 downto 0));
    end component;

    component dmem is
        generic (MEM_DEPTH : integer);
        port (clk : in std_logic; we : in std_logic;
              size : in std_logic_vector(2 downto 0);
              addr : in std_logic_vector(31 downto 0);
              wdata : in std_logic_vector(31 downto 0);
              re : in std_logic; rdata : out std_logic_vector(31 downto 0));
    end component;

    component alu is
        port (op : in std_logic_vector(3 downto 0);
              a : in std_logic_vector(31 downto 0);
              b : in std_logic_vector(31 downto 0);
              result : out std_logic_vector(31 downto 0);
              zero : out std_logic);
    end component;

    component regfile is
        port (clk : in std_logic; we : in std_logic;
              wa : in std_logic_vector(4 downto 0);
              wd : in std_logic_vector(31 downto 0);
              ra1 : in std_logic_vector(4 downto 0);
              rd1 : out std_logic_vector(31 downto 0);
              ra2 : in std_logic_vector(4 downto 0);
              rd2 : out std_logic_vector(31 downto 0));
    end component;

    component control_unit is
        port (instr : in std_logic_vector(31 downto 0);
              imm : out std_logic_vector(31 downto 0);
              rs1 : out std_logic_vector(4 downto 0);
              rs2 : out std_logic_vector(4 downto 0);
              rd  : out std_logic_vector(4 downto 0);
              ctrl_ex  : out ctrl_ex_t;
              ctrl_mem : out ctrl_mem_t;
              ctrl_wb  : out ctrl_wb_t;
              is_auipc : out std_logic);
    end component;

    component hazard_unit is
        port (idex_mem_read   : in std_logic;
              idex_rd         : in std_logic_vector(4 downto 0);
              idex_rs1        : in std_logic_vector(4 downto 0);
              idex_rs2        : in std_logic_vector(4 downto 0);
              ifid_rs1        : in std_logic_vector(4 downto 0);
              ifid_rs2        : in std_logic_vector(4 downto 0);
              exmem_reg_write : in std_logic;
              exmem_rd        : in std_logic_vector(4 downto 0);
              memwb_reg_write : in std_logic;
              memwb_rd        : in std_logic_vector(4 downto 0);
              fwd_a           : out std_logic_vector(1 downto 0);
              fwd_b           : out std_logic_vector(1 downto 0);
              stall           : out std_logic;
              flush_ifid      : out std_logic;
              flush_idex      : out std_logic;
              branch_mispredict : in std_logic);
    end component;

    component branch_predictor is
        port (clk : in std_logic; rst : in std_logic;
              pc_fetch      : in std_logic_vector(31 downto 0);
              predict_taken : out std_logic;
              update_en     : in std_logic;
              update_pc     : in std_logic_vector(31 downto 0);
              actual_taken  : in std_logic);
    end component;

    -- =========================================================================
    -- Pipeline register types
    -- =========================================================================

    -- IF/ID register
    type ifid_reg_t is record
        pc    : std_logic_vector(31 downto 0);
        instr : std_logic_vector(31 downto 0);
        valid : std_logic;
    end record;

    -- ID/EX register
    type idex_reg_t is record
        pc       : std_logic_vector(31 downto 0);
        rs1_data : std_logic_vector(31 downto 0);
        rs2_data : std_logic_vector(31 downto 0);
        imm      : std_logic_vector(31 downto 0);
        rs1_addr : std_logic_vector(4 downto 0);
        rs2_addr : std_logic_vector(4 downto 0);
        rd_addr  : std_logic_vector(4 downto 0);
        ctrl_ex  : ctrl_ex_t;
        ctrl_mem : ctrl_mem_t;
        ctrl_wb  : ctrl_wb_t;
        is_auipc : std_logic;
    end record;

    -- EX/MEM register
    type exmem_reg_t is record
        pc          : std_logic_vector(31 downto 0);
        alu_result  : std_logic_vector(31 downto 0);
        rs2_data    : std_logic_vector(31 downto 0);  -- for store
        rd_addr     : std_logic_vector(4 downto 0);
        branch_target : std_logic_vector(31 downto 0);
        branch_taken  : std_logic;
        ctrl_mem    : ctrl_mem_t;
        ctrl_wb     : ctrl_wb_t;
    end record;

    -- MEM/WB register
    type memwb_reg_t is record
        alu_result : std_logic_vector(31 downto 0);
        mem_rdata  : std_logic_vector(31 downto 0);
        rd_addr    : std_logic_vector(4 downto 0);
        pc_plus4   : std_logic_vector(31 downto 0);  -- for JAL/JALR link
        is_jump    : std_logic;
        ctrl_wb    : ctrl_wb_t;
    end record;

    -- =========================================================================
    -- Pipeline registers (D flip-flops)
    -- =========================================================================
    signal ifid  : ifid_reg_t  := (pc => (others=>'0'), instr => NOP_INSTR, valid => '0');
    signal idex  : idex_reg_t  := (pc => (others=>'0'), rs1_data => (others=>'0'),
                                    rs2_data => (others=>'0'), imm => (others=>'0'),
                                    rs1_addr => (others=>'0'), rs2_addr => (others=>'0'),
                                    rd_addr => (others=>'0'),
                                    ctrl_ex => CTRL_EX_NOP, ctrl_mem => CTRL_MEM_NOP,
                                    ctrl_wb => CTRL_WB_NOP, is_auipc => '0');
    signal exmem : exmem_reg_t := (pc => (others=>'0'), alu_result => (others=>'0'),
                                    rs2_data => (others=>'0'), rd_addr => (others=>'0'),
                                    branch_target => (others=>'0'), branch_taken => '0',
                                    ctrl_mem => CTRL_MEM_NOP, ctrl_wb => CTRL_WB_NOP);
    signal memwb : memwb_reg_t := (alu_result => (others=>'0'), mem_rdata => (others=>'0'),
                                    rd_addr => (others=>'0'), pc_plus4 => (others=>'0'),
                                    is_jump => '0', ctrl_wb => CTRL_WB_NOP);

    -- =========================================================================
    -- IF stage signals
    -- =========================================================================
    signal pc         : std_logic_vector(31 downto 0) := (others => '0');
    signal pc_plus4   : std_logic_vector(31 downto 0);
    signal next_pc    : std_logic_vector(31 downto 0);
    signal if_instr   : std_logic_vector(31 downto 0);
    signal predict_taken : std_logic;

    -- =========================================================================
    -- ID stage signals
    -- =========================================================================
    signal id_imm      : std_logic_vector(31 downto 0);
    signal id_rs1      : std_logic_vector(4 downto 0);
    signal id_rs2      : std_logic_vector(4 downto 0);
    signal id_rd       : std_logic_vector(4 downto 0);
    signal id_ctrl_ex  : ctrl_ex_t;
    signal id_ctrl_mem : ctrl_mem_t;
    signal id_ctrl_wb  : ctrl_wb_t;
    signal id_is_auipc : std_logic;
    signal id_rs1_data : std_logic_vector(31 downto 0);
    signal id_rs2_data : std_logic_vector(31 downto 0);

    -- =========================================================================
    -- EX stage signals
    -- =========================================================================
    signal ex_alu_a     : std_logic_vector(31 downto 0);
    signal ex_alu_b_pre : std_logic_vector(31 downto 0);  -- before imm mux
    signal ex_alu_b     : std_logic_vector(31 downto 0);
    signal ex_alu_op    : std_logic_vector(3 downto 0);
    signal ex_alu_result: std_logic_vector(31 downto 0);
    signal ex_alu_zero  : std_logic;
    signal ex_branch_target : std_logic_vector(31 downto 0);
    signal ex_branch_taken  : std_logic;
    signal ex_fwd_rs1   : std_logic_vector(31 downto 0);
    signal ex_fwd_rs2   : std_logic_vector(31 downto 0);
    signal ex_pc_or_rs1 : std_logic_vector(31 downto 0);  -- AUIPC / JALR mux

    -- =========================================================================
    -- WB stage signals
    -- =========================================================================
    signal wb_result    : std_logic_vector(31 downto 0);
    signal wb_we        : std_logic;
    signal wb_wa        : std_logic_vector(4 downto 0);
    signal wb_wd        : std_logic_vector(31 downto 0);

    -- =========================================================================
    -- Hazard / forwarding signals
    -- =========================================================================
    signal stall        : std_logic;
    signal flush_ifid   : std_logic;
    signal flush_idex   : std_logic;
    signal fwd_a        : std_logic_vector(1 downto 0);
    signal fwd_b        : std_logic_vector(1 downto 0);
    signal branch_mispredict : std_logic;

    -- MEM data output
    signal dmem_rdata   : std_logic_vector(31 downto 0);

begin

    -- =========================================================================
    -- Submodule instantiations
    -- =========================================================================

    u_imem : imem
        generic map (MEM_DEPTH => MEM_DEPTH, INIT_FILE => IMEM_INIT)
        port map (clk => clk, addr => pc, instr => if_instr);

    u_dmem : dmem
        generic map (MEM_DEPTH => MEM_DEPTH)
        port map (
            clk   => clk,
            we    => exmem.ctrl_mem.mem_write,
            size  => exmem.ctrl_mem.mem_size,
            addr  => exmem.alu_result,
            wdata => exmem.rs2_data,
            re    => exmem.ctrl_mem.mem_read,
            rdata => dmem_rdata);

    u_regfile : regfile
        port map (
            clk => clk,
            we  => wb_we, wa => wb_wa, wd => wb_wd,
            ra1 => id_rs1, rd1 => id_rs1_data,
            ra2 => id_rs2, rd2 => id_rs2_data);

    u_ctrl : control_unit
        port map (
            instr    => ifid.instr,
            imm      => id_imm,
            rs1      => id_rs1, rs2 => id_rs2, rd => id_rd,
            ctrl_ex  => id_ctrl_ex,
            ctrl_mem => id_ctrl_mem,
            ctrl_wb  => id_ctrl_wb,
            is_auipc => id_is_auipc);

    u_alu : alu
        port map (op => ex_alu_op, a => ex_alu_a, b => ex_alu_b,
                  result => ex_alu_result, zero => ex_alu_zero);

    u_hazard : hazard_unit
        port map (
            idex_mem_read    => idex.ctrl_mem.mem_read,
            idex_rd          => idex.rd_addr,
            idex_rs1         => idex.rs1_addr,
            idex_rs2         => idex.rs2_addr,
            ifid_rs1         => id_rs1,
            ifid_rs2         => id_rs2,
            exmem_reg_write  => exmem.ctrl_wb.reg_write,
            exmem_rd         => exmem.rd_addr,
            memwb_reg_write  => memwb.ctrl_wb.reg_write,
            memwb_rd         => memwb.rd_addr,
            fwd_a            => fwd_a,
            fwd_b            => fwd_b,
            stall            => stall,
            flush_ifid       => flush_ifid,
            flush_idex       => flush_idex,
            branch_mispredict => branch_mispredict);

    u_bpred : branch_predictor
        port map (
            clk           => clk,
            rst           => rst,
            pc_fetch      => pc,
            predict_taken => predict_taken,
            update_en     => exmem.ctrl_mem.branch,
            update_pc     => exmem.pc,
            actual_taken  => exmem.branch_taken);

    -- =========================================================================
    -- IF STAGE  —  Program counter and instruction fetch
    -- =========================================================================
    pc_plus4 <= std_logic_vector(unsigned(pc) + 4);

    -- PC mux: misprediction correction takes priority, then predictor
    next_pc <=
        exmem.branch_target when branch_mispredict = '1' and exmem.branch_taken = '1' else
        -- if mispredict + not-taken: fall-through (exmem.pc + 4)
        std_logic_vector(unsigned(exmem.pc) + 4)
                            when branch_mispredict = '1' and exmem.branch_taken = '0' else
        -- JALR/JAL target
        exmem.alu_result    when exmem.ctrl_mem.jump = '1' and memwb.is_jump = '0' else
        -- predicted-taken branch: jump to target
        std_logic_vector(unsigned(ifid.pc) + unsigned(id_imm))
                            when predict_taken = '1' and id_ctrl_mem.branch = '1' else
        pc_plus4;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pc <= (others => '0');
            elsif stall = '0' then
                pc <= next_pc;
            end if;
        end if;
    end process;

    -- IF/ID register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush_ifid = '1' then
                ifid.pc    <= (others => '0');
                ifid.instr <= NOP_INSTR;
                ifid.valid <= '0';
            elsif stall = '0' then
                ifid.pc    <= pc;
                ifid.instr <= if_instr;
                ifid.valid <= '1';
            end if;
        end if;
    end process;

    -- =========================================================================
    -- ID STAGE  —  Decode, immediate generation, register read
    -- (control_unit and regfile are instantiated above)
    -- =========================================================================

    -- ID/EX register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush_idex = '1' then
                idex.pc       <= (others => '0');
                idex.rs1_data <= (others => '0');
                idex.rs2_data <= (others => '0');
                idex.imm      <= (others => '0');
                idex.rs1_addr <= (others => '0');
                idex.rs2_addr <= (others => '0');
                idex.rd_addr  <= (others => '0');
                idex.ctrl_ex  <= CTRL_EX_NOP;
                idex.ctrl_mem <= CTRL_MEM_NOP;
                idex.ctrl_wb  <= CTRL_WB_NOP;
                idex.is_auipc <= '0';
            else
                idex.pc       <= ifid.pc;
                idex.rs1_data <= id_rs1_data;
                idex.rs2_data <= id_rs2_data;
                idex.imm      <= id_imm;
                idex.rs1_addr <= id_rs1;
                idex.rs2_addr <= id_rs2;
                idex.rd_addr  <= id_rd;
                idex.ctrl_ex  <= id_ctrl_ex;
                idex.ctrl_mem <= id_ctrl_mem;
                idex.ctrl_wb  <= id_ctrl_wb;
                idex.is_auipc <= id_is_auipc;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- EX STAGE  —  ALU, forwarding muxes, branch condition
    -- =========================================================================

    -- Forwarding mux for RS1
    ex_fwd_rs1 <=
        exmem.alu_result when fwd_a = FWD_MEM else
        wb_wd            when fwd_a = FWD_WB  else
        idex.rs1_data;

    -- Forwarding mux for RS2
    ex_fwd_rs2 <=
        exmem.alu_result when fwd_b = FWD_MEM else
        wb_wd            when fwd_b = FWD_WB  else
        idex.rs2_data;

    -- For AUIPC: ALU input A = PC; for JALR: ALU input A = RS1 (normal)
    -- For JAL: ALU computes PC + imm for branch target (A = PC)
    ex_pc_or_rs1 <=
        idex.pc when (idex.is_auipc = '1' or
                      (idex.ctrl_mem.jump = '1' and idex.ctrl_ex.is_jalr = '0'))
                else ex_fwd_rs1;

    ex_alu_a <= ex_pc_or_rs1;

    -- ALU B mux: immediate or RS2
    ex_alu_b_pre <= ex_fwd_rs2;
    ex_alu_b <= idex.imm when idex.ctrl_ex.alu_src = '1' else ex_alu_b_pre;

    ex_alu_op <= idex.ctrl_ex.alu_op;

    -- Branch target = ID/EX PC + imm  (same logic for JAL; JALR uses ALU result directly)
    ex_branch_target <= std_logic_vector(unsigned(idex.pc) + unsigned(idex.imm));

    -- Branch condition evaluation
    process(idex.ctrl_mem.branch, idex.ctrl_mem.mem_size, ex_fwd_rs1, ex_fwd_rs2)
        variable taken : std_logic;
    begin
        taken := '0';
        if idex.ctrl_mem.branch = '1' then
            case idex.ctrl_mem.mem_size is  -- mem_size carries funct3 for branches
                when F3_BEQ  => taken := '1' when signed(ex_fwd_rs1)   =  signed(ex_fwd_rs2)   else '0';
                when F3_BNE  => taken := '1' when signed(ex_fwd_rs1)  /=  signed(ex_fwd_rs2)   else '0';
                when F3_BLT  => taken := '1' when signed(ex_fwd_rs1)   <  signed(ex_fwd_rs2)   else '0';
                when F3_BGE  => taken := '1' when signed(ex_fwd_rs1)  >=  signed(ex_fwd_rs2)   else '0';
                when F3_BLTU => taken := '1' when unsigned(ex_fwd_rs1) < unsigned(ex_fwd_rs2)  else '0';
                when F3_BGEU => taken := '1' when unsigned(ex_fwd_rs1) >= unsigned(ex_fwd_rs2) else '0';
                when others  => taken := '0';
            end case;
        end if;
        ex_branch_taken <= taken;
    end process;

    -- Misprediction: predicted_taken != actual_taken
    -- predict_taken was sampled when the branch was in IF; it's in EX now.
    -- We stored the prediction in the pipeline... but for simplicity we use
    -- a conservative approach: always re-evaluate and flush on any taken branch.
    -- True misprediction = (predict ≠ actual) for the branch in EX/MEM stage.
    -- Here branch_mispredict fires from EX/MEM (one cycle after EX).
    branch_mispredict <= '1' when (exmem.ctrl_mem.branch = '1' and
                                   exmem.branch_taken /= predict_taken)
                              or  (exmem.ctrl_mem.jump = '1')
                         else '0';

    -- EX/MEM register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                exmem.pc            <= (others => '0');
                exmem.alu_result    <= (others => '0');
                exmem.rs2_data      <= (others => '0');
                exmem.rd_addr       <= (others => '0');
                exmem.branch_target <= (others => '0');
                exmem.branch_taken  <= '0';
                exmem.ctrl_mem      <= CTRL_MEM_NOP;
                exmem.ctrl_wb       <= CTRL_WB_NOP;
            else
                exmem.pc            <= idex.pc;
                exmem.alu_result    <= ex_alu_result;
                exmem.rs2_data      <= ex_fwd_rs2;
                exmem.rd_addr       <= idex.rd_addr;
                exmem.branch_target <= ex_branch_target;
                exmem.branch_taken  <= ex_branch_taken;
                exmem.ctrl_mem      <= idex.ctrl_mem;
                exmem.ctrl_wb       <= idex.ctrl_wb;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- MEM STAGE  —  Memory access (dmem handles sync read/write)
    -- =========================================================================

    -- MEM/WB register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                memwb.alu_result <= (others => '0');
                memwb.mem_rdata  <= (others => '0');
                memwb.rd_addr    <= (others => '0');
                memwb.pc_plus4   <= (others => '0');
                memwb.is_jump    <= '0';
                memwb.ctrl_wb   <= CTRL_WB_NOP;
            else
                memwb.alu_result <= exmem.alu_result;
                memwb.mem_rdata  <= dmem_rdata;
                memwb.rd_addr    <= exmem.rd_addr;
                memwb.pc_plus4   <= std_logic_vector(unsigned(exmem.pc) + 4);
                memwb.is_jump    <= exmem.ctrl_mem.jump;
                memwb.ctrl_wb   <= exmem.ctrl_wb;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- WB STAGE  —  Write-back mux
    -- =========================================================================
    wb_result <= memwb.pc_plus4   when memwb.is_jump = '1'         else
                 memwb.mem_rdata  when memwb.ctrl_wb.mem_to_reg='1' else
                 memwb.alu_result;

    wb_we <= memwb.ctrl_wb.reg_write;
    wb_wa <= memwb.rd_addr;
    wb_wd <= wb_result;

    -- =========================================================================
    -- Debug outputs
    -- =========================================================================
    dbg_pc     <= pc;
    dbg_instr  <= ifid.instr;
    dbg_reg_we <= wb_we;
    dbg_reg_wa <= wb_wa;
    dbg_reg_wd <= wb_wd;

end architecture rtl;
