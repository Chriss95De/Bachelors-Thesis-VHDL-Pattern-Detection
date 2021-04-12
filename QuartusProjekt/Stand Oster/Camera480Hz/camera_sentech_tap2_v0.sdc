#**************************************************************
# Create Clock
#**************************************************************
#create_clock -period 20 [get_ports CLOCK_50]
###create_clock -period 20 [get_ports CLK50]
### siehe unten create_clock -period 12 [get_ports CLRRXCLK_BASE]

#**************************************************************
# gi 2018-01-27
#  - SDRAM addresses change in the middle of each idle state 
#  - data lines change at negative clock edge, 
#  - output enable flipflop changes at negative clock edge
# DRAM data, address and control signal are placed into fast IO registers 
 
set period  10.0             ;# 10.0
set reserve  0.9             ;# 0.7 ns : pll normal or source synchronous mode, shifted clock by -36°
                             ;# 0.7 ns : pll normal mode, shifted clock by -45°

# For output delays:
set tSU_external     [expr 1.5 + $reserve] ;# 1.5 + reserve of 0.1  
set tH_external      [expr 0.8 + $reserve] ;# 0.8 + reserve of 0.1

# For input delays: 
set tCOmax_external  [expr 6.0 + $reserve] ;# 5.4 @ CL=3 + reserve of 0.1
                                           ;# 6.0 @ CL=2
set tCOmin_external  [expr 2.7 - $reserve] ;# 2.7 ns - reserve of 0.1 

# Clock constraints
create_clock -name "CLOCK_50" -period 20.000ns [get_ports {CLK50}] -waveform {0.000 10.000}
create_clock -name "clk_cam"  -period 11.000ns [get_ports {CLRRXCLK_BASE}]

#
create_generated_clock -add -source "inst_pll|altpll_component|auto_generated|pll1|inclk[0]" -master_clock "CLOCK_50" \
             -name "clk_data" -multiply_by 2 -divide_by 1 \
             [get_pins "inst_pll|altpll_component|auto_generated|pll1|clk[1]"]

create_generated_clock -add -source "inst_pll|altpll_component|auto_generated|pll1|inclk[0]" -master_clock "CLOCK_50" \
             -name "clk_vga" -divide_by 2 \
             [get_pins "inst_pll|altpll_component|auto_generated|pll1|clk[0]"]

create_generated_clock -add -source "inst_pll|altpll_component|auto_generated|pll1|inclk[0]" -master_clock "CLOCK_50" \
             -name "clk_shifted" -phase -60.0 -multiply_by 2 -divide_by 1 \
             [get_pins "inst_pll|altpll_component|auto_generated|pll1|clk[2]"]

create_generated_clock -name "clk_out" \
                       -source [get_pins "inst_pll|altpll_component|auto_generated|pll1|clk[2]"] \
                       [get_ports {DRAM_CLK}]

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

### Input constraints
#
set_multicycle_path -setup -end  2 -rise_from [get_clocks clk_out] -rise_to [get_clocks clk_data]
set_multicycle_path -setup -end  2 -fall_from [get_clocks clk_out] -fall_to [get_clocks clk_data]
# Not necessary, since normal condition
set_multicycle_path -hold  -end  0 -rise_from [get_clocks clk_out] -rise_to [get_clocks clk_data]
set_multicycle_path -hold  -end  0 -fall_from [get_clocks clk_out] -fall_to [get_clocks clk_data]
#
set_input_delay -add_delay -clock clk_out -max $tCOmax_external [get_ports {DRAM_DQ[*]}]
set_input_delay -add_delay -clock clk_out -min $tCOmin_external [get_ports {DRAM_DQ[*]}]

### Output constraints: tco constraints
set_output_delay -add_delay -clock clk_out -max $tSU_external         [get_ports {DRAM_A* DRAM_B* DRAM_CA* DRAM_CK* DRAM_CS* DRAM_D* DRAM_RA* DRAM_W*}]
set_output_delay -add_delay -clock clk_out -min [expr - $tH_external] [get_ports {DRAM_A* DRAM_B* DRAM_CA* DRAM_CK* DRAM_CS* DRAM_D* DRAM_RA* DRAM_W*}]

#################################
# No constraints on KEY[] and HEX[]
set_false_path -from [get_ports {SW* KEY*}]
set_false_path -to [get_ports {LED* HEX0* HEX1* HEX2* HEX3* HEX4* HEX5* HEX6* HEX7*}]
set_false_path -to [get_ports {DRAM_CLK}]
#???set_false_path -from [get_clocks {CLK_VGA}] -to [get_clocks {clk_data}]
set_false_path -from [get_clocks {clk_data}] -to [get_clocks {clk_vga}]
set_false_path -from [get_clocks {clk_cam}] -to [get_clocks {clk_data}]
set_false_path -from [get_clocks {clk_data}] -to [get_clocks {clk_cam}]

