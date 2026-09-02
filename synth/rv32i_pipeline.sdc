# =============================================================================
# rv32i_pipeline.sdc  —  Timing constraints for 100 MHz operation
# =============================================================================

# 100 MHz system clock
create_clock -name clk -period 10.000 [get_ports clk]

# Constrain all registers to 100 MHz domain
derive_clock_uncertainty

# Input/Output delays (assuming no external timing requirements for debug ports)
set_input_delay  -clock clk -max 2.0 [get_ports rst]
set_input_delay  -clock clk -min 0.5 [get_ports rst]

set_output_delay -clock clk -max 2.0 [get_ports {dbg_pc[*]}]
set_output_delay -clock clk -max 2.0 [get_ports {dbg_instr[*]}]
set_output_delay -clock clk -max 2.0 [get_ports dbg_reg_we]
set_output_delay -clock clk -max 2.0 [get_ports {dbg_reg_wa[*]}]
set_output_delay -clock clk -max 2.0 [get_ports {dbg_reg_wd[*]}]

# False paths for reset (async in intent)
set_false_path -from [get_ports rst]
