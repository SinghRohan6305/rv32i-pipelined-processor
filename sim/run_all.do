# =============================================================================
# run_all.do  —  ModelSim/QuestaSim script: compile and run all 30+ testbenches
# Usage: vsim -do run_all.do
# =============================================================================

quietly set SRCDIR "../src"
quietly set TBDIR  "../tb"

# Create/open work library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# ---- Compile source files (order matters: pkg first) ----
vcom -2008 -work work $SRCDIR/pkg_riscv.vhd
vcom -2008 -work work $SRCDIR/alu.vhd
vcom -2008 -work work $SRCDIR/regfile.vhd
vcom -2008 -work work $SRCDIR/branch_predictor.vhd
vcom -2008 -work work $SRCDIR/hazard_unit.vhd
vcom -2008 -work work $SRCDIR/imem.vhd
vcom -2008 -work work $SRCDIR/dmem.vhd
vcom -2008 -work work $SRCDIR/control_unit.vhd
vcom -2008 -work work $SRCDIR/pipeline_top.vhd

# ---- Compile testbench files ----
vcom -2008 -work work $TBDIR/tb_pkg.vhd
vcom -2008 -work work $TBDIR/tb_alu.vhd
vcom -2008 -work work $TBDIR/tb_regfile.vhd
vcom -2008 -work work $TBDIR/tb_dmem.vhd
vcom -2008 -work work $TBDIR/tb_imem.vhd
vcom -2008 -work work $TBDIR/tb_control_unit.vhd
vcom -2008 -work work $TBDIR/tb_hazard_unit.vhd
vcom -2008 -work work $TBDIR/tb_branch_predictor.vhd
vcom -2008 -work work $TBDIR/tb_r_type.vhd
vcom -2008 -work work $TBDIR/tb_i_type.vhd
vcom -2008 -work work $TBDIR/tb_lui_auipc.vhd
vcom -2008 -work work $TBDIR/tb_jal_jalr.vhd
vcom -2008 -work work $TBDIR/tb_branch.vhd
vcom -2008 -work work $TBDIR/tb_branch_not_taken.vhd
vcom -2008 -work work $TBDIR/tb_load_store.vhd
vcom -2008 -work work $TBDIR/tb_all_loads.vhd
vcom -2008 -work work $TBDIR/tb_all_stores.vhd
vcom -2008 -work work $TBDIR/tb_hazard_raw.vhd
vcom -2008 -work work $TBDIR/tb_hazard_load_use.vhd
vcom -2008 -work work $TBDIR/tb_forwarding.vhd
vcom -2008 -work work $TBDIR/tb_store_forward.vhd
vcom -2008 -work work $TBDIR/tb_branch_with_forwarding.vhd
vcom -2008 -work work $TBDIR/tb_consecutive_branches.vhd
vcom -2008 -work work $TBDIR/tb_pipeline_stall_count.vhd
vcom -2008 -work work $TBDIR/tb_overflow_edge.vhd
vcom -2008 -work work $TBDIR/tb_fence_system.vhd
vcom -2008 -work work $TBDIR/tb_reset.vhd
vcom -2008 -work work $TBDIR/tb_full_fibonacci.vhd

# ---- Helper: run a single testbench ----
proc run_tb {name} {
    puts "\n========================================="
    puts "Running: $name"
    puts "========================================="
    vsim -quiet -lib work $name
    run -all
    quit -sim
}

# ---- Run all testbenches ----
run_tb tb_alu
run_tb tb_regfile
run_tb tb_dmem
run_tb tb_imem
run_tb tb_control_unit
run_tb tb_hazard_unit
run_tb tb_branch_predictor
run_tb tb_r_type
run_tb tb_i_type
run_tb tb_lui_auipc
run_tb tb_jal_jalr
run_tb tb_branch
run_tb tb_branch_not_taken
run_tb tb_load_store
run_tb tb_all_loads
run_tb tb_all_stores
run_tb tb_hazard_raw
run_tb tb_hazard_load_use
run_tb tb_forwarding
run_tb tb_store_forward
run_tb tb_branch_with_forwarding
run_tb tb_consecutive_branches
run_tb tb_pipeline_stall_count
run_tb tb_overflow_edge
run_tb tb_fence_system
run_tb tb_reset
run_tb tb_full_fibonacci

puts "\n========================================="
puts "ALL TESTBENCHES COMPLETE"
puts "========================================="
