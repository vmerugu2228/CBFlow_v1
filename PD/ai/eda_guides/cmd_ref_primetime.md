# Synopsys PrimeTime Command Reference

Comprehensive command reference for Synopsys PrimeTime (PT), the gold-standard
static timing analysis (STA) signoff tool. Covers PT shell commands for design
setup, timing analysis, signal integrity, on-chip variation, ECO, distributed
multi-scenario analysis (DMSA), and PrimeTime PX (PTPX) power analysis.

PT version baseline: T-2022.03 and later.

---

## Table of Contents

1. [Design Setup and Linking](#1-design-setup-and-linking)
2. [Constraint and Parasitic Input](#2-constraint-and-parasitic-input)
3. [Timing Analysis Fundamentals](#3-timing-analysis-fundamentals)
4. [report_timing — Complete Reference](#4-report_timing--complete-reference)
5. [Operating Conditions and Derating](#5-operating-conditions-and-derating)
6. [On-Chip Variation (OCV/AOCV/POCV)](#6-on-chip-variation-ocvaocvpocv)
7. [Signal Integrity (SI / Crosstalk)](#7-signal-integrity-si--crosstalk)
8. [ECO Commands](#8-eco-commands)
9. [DMSA — Distributed Multi-Scenario Analysis](#9-dmsa--distributed-multi-scenario-analysis)
10. [PTPX — PrimeTime Power Analysis](#10-ptpx--primetime-power-analysis)
11. [Advanced Timing Analysis](#11-advanced-timing-analysis)
12. [Reporting Commands](#12-reporting-commands)
13. [Useful Variables and Settings](#13-useful-variables-and-settings)
14. [Utility Commands](#14-utility-commands)

---

## 1. Design Setup and Linking

### Library Setup

```tcl
# Set library paths
set search_path ". /libs/db /libs/sram /project/netlists $search_path"

# Link library
set link_library "* saed14_rvt_ss_0p72v_125c.db \
                     saed14_hvt_ss_0p72v_125c.db \
                     saed14_lvt_ss_0p72v_125c.db \
                     sram_256x32_ss.db \
                     pll_ss.db \
                     io_ss.db"

# Target library (not strictly needed in PT, but used for ECO sizing)
set target_library "saed14_rvt_ss_0p72v_125c.db saed14_hvt_ss_0p72v_125c.db"
```

### read_verilog

Read a gate-level netlist.

```
read_verilog <file_list>
  [-define <macro_list>]
  [-top <module_name>]
```

```tcl
read_verilog {./netlist/top_post_route.v}
read_verilog -define FUNC_MODE ./netlist/top.v
```

### read_db

Read .db library files.

```
read_db <file_list>
```

```tcl
read_db {saed14_rvt_ss_0p72v_125c.db saed14_hvt_ss_0p72v_125c.db}
```

### link_design

Resolve all references — link the netlist to library cells.

```
link_design <top_design_name>
  [-keep_sub_designs]
```

```tcl
current_design chip_top
link_design chip_top
# or just
link_design
```

### Full Setup Example

```tcl
set search_path ". /libs/db /project/netlist"
set link_library "* saed14_rvt_ss.db saed14_hvt_ss.db sram.db"

read_verilog ./netlist/chip_top_post_route.v
current_design chip_top
link_design

read_parasitics ./spef/chip_top_ss_125c.spef
read_sdc ./constraints/chip_top_func.sdc

update_timing -full
report_timing -max_paths 100 > ./reports/timing_setup.rpt
```

---

## 2. Constraint and Parasitic Input

### read_sdc

Read SDC timing constraints.

```
read_sdc <file>
  [-echo]
  [-version <sdc_version>]
```

```tcl
read_sdc ./constraints/func_mode.sdc
read_sdc ./constraints/scan_mode.sdc -echo
```

### read_parasitics / read_parasitic

Read SPEF/SBPF/DSPF parasitic data.

```
read_parasitics <file>
  [-format {spef | sbpf | dspf}]
  [-path <instance_path>]
  [-increment]
  [-keep_capacitive_coupling]
  [-complete_with {wlm | zero}]
```

**Examples**

```tcl
# Basic SPEF read
read_parasitics ./spef/chip_top_ss_125c.spef

# With coupling kept for SI analysis
read_parasitics ./spef/chip_top_ss_125c.spef -keep_capacitive_coupling

# Hierarchical SPEF
read_parasitics ./spef/cpu_core.spef -path cpu_core_inst
read_parasitics ./spef/mem_ctrl.spef -path mem_ctrl_inst

# Incremental parasitic
read_parasitics ./spef/eco_region.spef -increment

# Complete unannotated nets with wire load model
read_parasitics ./spef/chip_top.spef -complete_with wlm
```

### annotate_parasitics (Alias)

```tcl
# Same as read_parasitics in most contexts
annotate_parasitics -format spef ./spef/chip_top.spef
```

### Source SDC Manually

```tcl
# Source constraint file directly
source ./constraints/chip_top_func.sdc

# Or set constraints programmatically
create_clock [get_ports clk] -period 2.0 -name sys_clk
set_input_delay -max 1.0 -clock sys_clk [all_inputs]
set_output_delay -max 0.8 -clock sys_clk [all_outputs]
set_false_path -from [get_ports reset_n]
```

---

## 3. Timing Analysis Fundamentals

### update_timing

Update the timing graph. Must be called after reading design data or changing
constraints.

```
update_timing
  [-full]
  [-verbose]
```

```tcl
update_timing -full
```

### check_timing

Verify timing constraints are applied correctly.

```
check_timing
  [-verbose]
  [-override_defaults {all | no_clock | no_input_delay | no_output_delay |
                       unconstrained_endpoints | no_driving_cell |
                       ideal_clocks | partial_input_delay |
                       unexpandable_clocks}]
```

```tcl
check_timing -verbose > ./reports/check_timing.rpt
check_timing -override_defaults {no_clock unconstrained_endpoints}
```

### Timing Update Variables

```tcl
set_app_var timing_report_unconstrained_paths true
set_app_var timing_save_pin_arrival_and_slack true
set_app_var timing_remove_clock_reconvergence_pessimism true
set_app_var timing_crpr_threshold_ps 1.0
```

---

## 4. report_timing -- Complete Reference

The primary timing report command, with exhaustive options.

```
report_timing
  [-delay_type {max | min | min_max}]
  [-path_type {full | full_clock | full_clock_expanded | summary | end |
               short}]
  [-max_paths <N>]
  [-nworst <N>]
  [-group <path_group_list>]
  [-from <startpoints>]
  [-through <through_list>]
  [-to <endpoints>]
  [-rise_from <pins> | -fall_from <pins>]
  [-rise_through <pins> | -fall_through <pins>]
  [-rise_to <pins> | -fall_to <pins>]
  [-point_to_point]
  [-slack_lesser_than <value>]
  [-slack_greater_than <value>]
  [-nets]
  [-capacitance]
  [-transition_time]
  [-input_pins]
  [-crosstalk_delta]
  [-derate]
  [-voltage]
  [-pba_mode {path | exhaustive | none}]
  [-nosplit]
  [-significant_digits <N>]
  [-sort_by {slack | group | endpoint}]
  [-include_hierarchical_pins]
  [-unique_pins]
  [-physical]
  [-attributes {<attr_list>}]
  > <output_file>
```

### Option Details

| Option | Description |
|---|---|
| `-delay_type max` | Setup (late) analysis |
| `-delay_type min` | Hold (early) analysis |
| `-delay_type min_max` | Both setup and hold |
| `-path_type full` | Full path detail |
| `-path_type full_clock` | Full path + clock path |
| `-path_type full_clock_expanded` | Full path + expanded clock tree |
| `-path_type summary` | One-line summary per path |
| `-path_type end` | Endpoint only |
| `-max_paths N` | Maximum number of paths to report |
| `-nworst N` | Worst N paths per endpoint |
| `-group` | Report paths in specific path groups |
| `-from` / `-to` / `-through` | Constrain path search |
| `-slack_lesser_than` | Only paths with slack worse than this |
| `-nets` | Show net names in path |
| `-capacitance` | Show pin capacitance values |
| `-transition_time` | Show slew/transition values |
| `-input_pins` | Show input pin arrivals |
| `-crosstalk_delta` | Show SI-induced delta delays |
| `-derate` | Show OCV derate factors |
| `-voltage` | Show voltage at each stage |
| `-pba_mode path` | Path-based analysis (more accurate) |
| `-pba_mode exhaustive` | Exhaustive PBA (most accurate, slower) |
| `-physical` | Show physical coordinates |
| `-unique_pins` | Remove paths sharing same critical pin |

### Examples

```tcl
# Most comprehensive setup timing report
report_timing \
  -delay_type max \
  -path_type full_clock_expanded \
  -max_paths 200 \
  -nworst 5 \
  -nets \
  -capacitance \
  -transition_time \
  -input_pins \
  -crosstalk_delta \
  -derate \
  -significant_digits 4 \
  -nosplit \
  > ./reports/timing_setup_detailed.rpt

# Hold timing
report_timing \
  -delay_type min \
  -path_type full_clock_expanded \
  -max_paths 200 \
  -nworst 5 \
  -nets \
  -transition_time \
  -crosstalk_delta \
  -derate \
  -significant_digits 4 \
  > ./reports/timing_hold_detailed.rpt

# Only violating paths
report_timing -delay_type max -slack_lesser_than 0 -max_paths 500 \
  > ./reports/timing_violations.rpt

# Paths through a specific instance
report_timing -through [get_pins u_alu/carry_out] -max_paths 20

# Endpoint-specific
report_timing -to [get_pins u_fifo/wr_data_reg[0]/D] -nworst 10

# From-to constrained
report_timing -from [get_cells u_cpu/alu/*] -to [get_cells u_cpu/rf/*] -max_paths 50

# Cross-clock paths
report_timing -from [get_clocks clk_a] -to [get_clocks clk_b] -max_paths 20

# PBA mode
report_timing -pba_mode path -max_paths 50 > ./reports/timing_pba.rpt
report_timing -pba_mode exhaustive -max_paths 20 > ./reports/timing_epba.rpt

# Summary report
report_timing -path_type summary -max_paths 500 > ./reports/timing_summary.rpt

# Path with physical info
report_timing -physical -max_paths 20 > ./reports/timing_physical.rpt
```

---

## 5. Operating Conditions and Derating

### set_operating_conditions

```
set_operating_conditions <condition_name>
  [-library <lib_name>]
  [-analysis_type {single | bc_wc | on_chip_variation}]
  [-max <condition>]
  [-min <condition>]
  [-max_library <lib>]
  [-min_library <lib>]
```

**Examples**

```tcl
# Single corner
set_operating_conditions ss_0p72v_125c

# Best-case/worst-case
set_operating_conditions -max ss_0p72v_125c -min ff_0p88v_m40c

# OCV analysis mode
set_operating_conditions -analysis_type on_chip_variation \
  -max ss_0p72v_125c -min ff_0p88v_m40c
```

### set_timing_derate

Apply flat OCV derating.

```
set_timing_derate <factor>
  [-early | -late]
  [-cell_delay | -net_delay | -data | -clock]
  [-cell_check]
  [-static]
  [-dynamic]
```

**Examples**

```tcl
# Simple flat derate
set_timing_derate -early 0.93
set_timing_derate -late  1.07

# Separate cell and net derates
set_timing_derate -early 0.95 -cell_delay
set_timing_derate -early 0.90 -net_delay
set_timing_derate -late  1.05 -cell_delay
set_timing_derate -late  1.10 -net_delay

# Derate specific cells
set_timing_derate -early 0.90 -cell_delay [get_cells u_memory/*]
set_timing_derate -late  1.10 -cell_delay [get_cells u_memory/*]

# Clock path only
set_timing_derate -late 1.03 -clock
set_timing_derate -early 0.97 -clock

# Data path only
set_timing_derate -late 1.07 -data
set_timing_derate -early 0.93 -data
```

---

## 6. On-Chip Variation (OCV/AOCV/POCV)

### Flat OCV

```tcl
# Enable OCV
set_app_var timing_ocvm_enable_analysis true
# or
set_operating_conditions -analysis_type on_chip_variation

# Apply derates (see set_timing_derate above)
set_timing_derate -early 0.93
set_timing_derate -late  1.07
```

### AOCV (Advanced OCV)

AOCV uses depth/distance-based derate tables instead of flat derates.

```tcl
# Enable AOCV
set_app_var timing_aocvm_enable_analysis true

# Read AOCV tables
read_aocvm ./aocv/saed14_rvt.aocvm
read_aocvm ./aocv/saed14_hvt.aocvm
read_aocvm ./aocv/saed14_lvt.aocvm

# Configure AOCV behavior
set_app_var timing_aocvm_analysis_mode combined_launch_capture_depth
```

### AOCV Commands

```tcl
# Read AOCV derate table
read_aocvm <file>

# Set AOCV analysis mode
set_aocvm_analysis_mode
  [-mode {combined_launch_capture_depth | separate_launch_capture_depth}]

# Report AOCV derates on a path
report_timing -derate -max_paths 10

# Check AOCV setup
report_aocvm
```

### POCV (Parametric OCV)

POCV uses statistical (Gaussian) variation models — the most advanced OCV.

```tcl
# Enable POCV
set_app_var timing_pocvm_enable_analysis true

# Read POCV coefficient data (Liberty Variation Format)
read_pocvm ./pocv/saed14_rvt_pocv.lut
read_pocvm ./pocv/saed14_hvt_pocv.lut
read_pocvm ./pocv/saed14_lvt_pocv.lut

# Or read LVF data from Liberty
# (POCV data is embedded in .db files from the library vendor)
# No explicit read needed if the .db files contain LVF/POCV data.

# POCV configuration
set_app_var pocvm_enable_analysis true
set_app_var timing_pocvm_corner_sigma 3.0
set_app_var timing_report_pocvm true
```

### POCV Variables

```tcl
set_app_var timing_pocvm_enable_analysis true
set_app_var timing_pocvm_corner_sigma 3.0
set_app_var timing_pocvm_guard_band 0.0
set_app_var timing_pocvm_net_variation_mode true
set_app_var timing_report_pocvm true
```

### read_lut (For POCV)

```
read_lut <file>
```

```tcl
read_lut ./pocv/saed14_rvt_cell_variation.lut
```

### Choosing OCV Method

| Method | Accuracy | Runtime | Recommended Use |
|---|---|---|---|
| Flat OCV | Low | Fast | Early analysis, guard-banding |
| AOCV | Medium | Medium | Production signoff (older nodes) |
| POCV/LVF | High | Slower | Production signoff (advanced nodes) |

```tcl
# Typical POCV setup for signoff
set_app_var timing_pocvm_enable_analysis true
set_app_var timing_remove_clock_reconvergence_pessimism true
set_app_var timing_pocvm_corner_sigma 3.0
read_parasitics ./spef/top.spef -keep_capacitive_coupling
read_sdc ./constraints/func.sdc
update_timing -full
report_timing -delay_type max -max_paths 200 -derate > ./reports/pocv_setup.rpt
report_timing -delay_type min -max_paths 200 -derate > ./reports/pocv_hold.rpt
```

---

## 7. Signal Integrity (SI / Crosstalk)

### SI Setup

```tcl
# Enable SI analysis
set_app_var si_enable_analysis true

# Must read parasitics with coupling
read_parasitics ./spef/top.spef -keep_capacitive_coupling

# Set SI thresholds
set_app_var si_xtalk_delay_analysis_mode all_violating_paths
set_app_var si_filter_per_aggressor_noise_peak_ratio 0.01
set_app_var si_xtalk_exit_on_max_iteration_count 5
```

### SI Analysis Commands

```tcl
# Update timing with SI
update_timing -full

# Report SI delay impact
report_si_delay_analysis > ./reports/si_delay.rpt

# Report noise
report_noise > ./reports/noise.rpt
report_noise -above -threshold 0.1 > ./reports/noise_above.rpt
report_noise -all_violators > ./reports/noise_violations.rpt

# Report SI on specific nets
report_si_delay_analysis -nets [get_nets critical_bus*]

# Noise per net
report_noise -nets [get_nets data_bus[0]]
```

### SI-Specific Commands

```tcl
# Set noise parameters
set_noise_parameters
  [-static_noise_margin_above <value>]
  [-static_noise_margin_below <value>]

set_noise_parameters \
  -static_noise_margin_above 0.15 \
  -static_noise_margin_below 0.15

# Set SI options
set_si_delay_analysis_options
  [-max_transition_mode {normal | worst}]
  [-delta_delay_threshold <value>]

# Annotate SI delay
set_si_delay_analysis
  [-enable | -disable]

# Report SI bottleneck
report_si_bottleneck -cost_type {noise | delay | total} -max_nets 50

# Report crosstalk delta per path
report_timing -crosstalk_delta -max_paths 50
```

### SI Variables

```tcl
set_app_var si_enable_analysis true
set_app_var si_xtalk_delay_analysis_mode all_violating_paths
set_app_var si_xtalk_double_switching_mode clock_as_aggressor
set_app_var si_filter_per_aggressor_noise_peak_ratio 0.01
set_app_var si_noise_update_status true
set_app_var si_ccs_use_gate_level_simulation true
set_app_var si_xtalk_reselect_critical_path true
```

---

## 8. ECO Commands

### fix_eco_timing

Automatically fix timing violations through cell sizing, buffering, etc.

```
fix_eco_timing
  [-type {setup | hold}]
  [-methods {size_cell | insert_buffer | remove_buffer}]
  [-slack_lesser_than <value>]
  [-max_paths <N>]
  [-max_iterations <N>]
  [-buffer_list <lib_cell_list>]
  [-target_slack <value>]
```

**Examples**

```tcl
# Fix setup violations
fix_eco_timing -type setup \
  -methods {size_cell insert_buffer} \
  -slack_lesser_than 0 \
  -max_paths 1000

# Fix hold violations
fix_eco_timing -type hold \
  -methods {size_cell insert_buffer} \
  -slack_lesser_than 0 \
  -buffer_list {BUFX2 BUFX4 BUFX8 DELX1 DELX2} \
  -max_paths 5000

# Fix with target slack margin
fix_eco_timing -type hold \
  -methods {insert_buffer size_cell} \
  -target_slack 0.020
```

### size_cell

Resize a cell to a different library cell.

```
size_cell <instance> <lib_cell>
```

```tcl
size_cell u_buf_42 saed14_rvt/BUFX8
size_cell [get_cells u_cpu/alu/add_reg] saed14_lvt/DFFX2
```

### insert_buffer

Insert a buffer on a net or before a pin.

```
insert_buffer <pin_or_net> <lib_cell>
  [-new_cell_name <name>]
  [-new_net_name <name>]
```

```tcl
insert_buffer [get_pins u_fifo/data_reg[0]/D] saed14_rvt/BUFX4
insert_buffer [get_nets long_wire] saed14_rvt/BUFX8 -new_cell_name eco_buf_1
```

### remove_buffer

Remove a buffer from a path.

```
remove_buffer <cell_list>
```

```tcl
remove_buffer [get_cells eco_old_buf*]
```

### ECO Reporting

```tcl
# Write ECO changes as TCL script
write_changes -format iccompiler2 -output ./eco/timing_eco.tcl
write_changes -format icc -output ./eco/timing_eco_icc.tcl

# Report ECO summary
report_eco_summary > ./reports/eco_summary.rpt

# Compare timing before/after
report_timing -delay_type max -max_paths 20 > ./reports/timing_post_eco.rpt
```

---

## 9. DMSA -- Distributed Multi-Scenario Analysis

DMSA enables parallel timing analysis across multiple PVT corners and
functional modes.

### DMSA Setup

```tcl
# Start PT in DMSA mode
# pt_shell -dmsa

# Or enable DMSA in a running session
set_app_var distributed_enable true

# Set host options
set_host_options -max_cores 32
set_host_options -name local_hosts -submit_command "bsub -q normal"
```

### DMSA Configuration Script

```tcl
# Master script: dmsa_setup.tcl

# Define scenarios
create_scenario -name func_ss_125c
create_scenario -name func_ff_m40c
create_scenario -name func_ss_0p72v
create_scenario -name scan_ss_125c

# Configure each scenario
set_scenario_options -name func_ss_125c \
  -setup true -hold false \
  -script ./scripts/func_ss_125c.tcl

set_scenario_options -name func_ff_m40c \
  -setup false -hold true \
  -script ./scripts/func_ff_m40c.tcl

set_scenario_options -name func_ss_0p72v \
  -setup true -hold false \
  -script ./scripts/func_ss_0p72v.tcl

set_scenario_options -name scan_ss_125c \
  -setup true -hold true \
  -script ./scripts/scan_ss_125c.tcl
```

### Scenario Script Example

```tcl
# scripts/func_ss_125c.tcl
set link_library "* saed14_rvt_ss_0p72v_125c.db saed14_hvt_ss_0p72v_125c.db"
read_verilog ./netlist/top_post_route.v
current_design chip_top
link_design

read_parasitics ./spef/top_Cmax.spef
read_sdc ./constraints/func_mode.sdc
set_operating_conditions ss_0p72v_125c

# OCV setup
set_timing_derate -early 0.93
set_timing_derate -late  1.07

update_timing -full
```

### Running DMSA

```tcl
# Distribute scenarios to remote hosts
remote_execute {
  report_timing -delay_type max -max_paths 100 > timing_setup.rpt
  report_timing -delay_type min -max_paths 100 > timing_hold.rpt
  report_constraint -all_violators > violations.rpt
}

# Collect results
report_analysis_coverage > ./reports/dmsa_coverage.rpt

# Cross-scenario worst slack
report_global_timing > ./reports/dmsa_global_timing.rpt
```

### DMSA Commands

```tcl
# List scenarios
list_scenarios

# Set active scenarios
set_active_scenarios {func_ss_125c func_ff_m40c}

# Get scenario info
get_scenario_options -name func_ss_125c

# Remove scenario
remove_scenario func_ss_125c

# Report across scenarios
report_timing -scenarios all -max_paths 20
```

---

## 10. PTPX -- PrimeTime Power Analysis

### PTPX Setup

```tcl
# Set power analysis mode
set_power_analysis_options -waveform_format fsdb
# or
set_power_analysis_options -waveform_format saif
```

### Reading Activity Data

```tcl
# Read SAIF (Switching Activity Interchange Format)
read_activity <file>
  [-format {saif | fsdb | vcd}]
  [-strip_path <path>]
  [-scope <scope>]

read_activity ./saif/top_func.saif -format saif -strip_path testbench/dut

# Read FSDB
read_activity ./fsdb/top_func.fsdb -format fsdb -strip_path testbench/dut

# Read VCD
read_activity ./vcd/top_func.vcd -format vcd -strip_path testbench/dut
```

### Power Analysis

```tcl
# Set default switching activity
set_switching_activity -toggle_rate 0.1 -static_probability 0.5 [all_inputs]
set_switching_activity -toggle_rate 0.2 [get_nets -hier *]

# Propagate activity
propagate_switching_activity

# Update power
update_power

# Report power
report_power
  [-hierarchy]
  [-levels <N>]
  [-verbose]
  [-net]
  [-cell]
  [-groups <group_list>]
  [-nosplit]
  [-significant_digits <N>]
  > <output_file>
```

**Examples**

```tcl
# Basic power report
report_power > ./reports/power.rpt

# Hierarchical power
report_power -hierarchy -levels 3 > ./reports/power_hier.rpt

# Verbose with net/cell breakdown
report_power -verbose -net -cell > ./reports/power_verbose.rpt

# Power by group
report_power -groups {clock_network register combinational memory io}
```

### PTPX Power Variables

```tcl
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged   ;# or time_based
set_app_var power_default_toggle_rate 0.1
set_app_var power_default_static_probability 0.5
set_app_var power_clock_network_include_register_clock_pin_power true
```

### Time-Based Power Analysis

```tcl
# Time-based mode for dynamic analysis
set_app_var power_analysis_mode time_based

# Read FSDB or VCD with time window
read_activity ./fsdb/top.fsdb -format fsdb -strip_path tb/dut

# Set time window
set_power_analysis_options \
  -waveform_interval {100ns 500ns}

# Update and report
update_power
report_power -verbose > ./reports/power_time_based.rpt

# Write per-instance power
write_power_data -output ./reports/power_data.ptpx
```

### Power Report by Category

```tcl
# Leakage power
report_power -cell -nosplit -significant_digits 4 \
  > ./reports/leakage_power.rpt

# Dynamic power
report_power -net -nosplit -significant_digits 4 \
  > ./reports/dynamic_power.rpt

# Clock network power
report_power -groups clock_network \
  > ./reports/clock_power.rpt
```

---

## 11. Advanced Timing Analysis

### Path-Based Analysis (PBA)

```tcl
# GBA (Graph-Based Analysis) — default, conservative
report_timing -max_paths 100

# PBA — path-specific slew propagation
report_timing -pba_mode path -max_paths 100

# Exhaustive PBA — most accurate
report_timing -pba_mode exhaustive -max_paths 50

# Variables
set_app_var pba_enable_path_based_analysis true
set_app_var pba_exhaustive_endpoint_path_limit 100
set_app_var pba_recalculate_full_path true
```

### Clock Reconvergence Pessimism Removal (CRPR)

```tcl
set_app_var timing_remove_clock_reconvergence_pessimism true
set_app_var timing_crpr_threshold_ps 1.0
set_app_var timing_disable_clock_gating_checks false
```

### Bottleneck Analysis

```tcl
# Find timing bottlenecks
report_bottleneck
  [-max_cells <N>]
  [-cost_type {path_count | slack}]
  > <output_file>

report_bottleneck -max_cells 50 -cost_type slack > ./reports/bottleneck.rpt
```

### Analysis Bounds

```tcl
# Report analysis bounds
report_analysis_coverage > ./reports/analysis_coverage.rpt

# Report unconstrained paths
report_timing -unconstrained > ./reports/unconstrained.rpt
```

### Recovery/Removal Checks

```tcl
# Enable recovery/removal
set_app_var enable_recovery_removal_arcs true

# Report recovery/removal timing
report_timing -delay_type max -group **async_default** -max_paths 20
```

---

## 12. Reporting Commands

### report_qor

```tcl
report_qor > ./reports/qor.rpt
report_qor -summary
```

### report_constraint

```tcl
report_constraint -all_violators > ./reports/all_violations.rpt
report_constraint -all_violators -verbose -nosplit > ./reports/violations_verbose.rpt
report_constraint -max_transition -all_violators
report_constraint -max_capacitance -all_violators
report_constraint -max_fanout -all_violators
```

### report_clock_timing

```
report_clock_timing
  [-type {skew | latency | transition | summary | interclock_skew}]
  [-clock <clock_list>]
  [-nworst <N>]
  [-setup | -hold]
  [-verbose]
  [-to <endpoints>]
  > <output_file>
```

```tcl
report_clock_timing -type skew -nworst 50 > ./reports/clock_skew.rpt
report_clock_timing -type latency -clock sys_clk > ./reports/clock_latency.rpt
report_clock_timing -type transition > ./reports/clock_transition.rpt
report_clock_timing -type summary > ./reports/clock_summary.rpt
report_clock_timing -type interclock_skew > ./reports/interclock_skew.rpt
```

### report_global_timing

```tcl
report_global_timing > ./reports/global_timing.rpt
report_global_timing -significant_digits 4
```

### report_design

```tcl
report_design > ./reports/design.rpt
report_design -physical > ./reports/design_physical.rpt
```

### report_net

```tcl
report_net -connections -verbose [get_nets critical_net]
report_net_fanout -threshold 100 > ./reports/high_fanout.rpt
```

### report_cell

```tcl
report_cell [get_cells -hier *] > ./reports/cells.rpt
```

### report_port

```tcl
report_port > ./reports/ports.rpt
report_port -verbose [get_ports clk]
```

### report_clock

```tcl
report_clock > ./reports/clocks.rpt
report_clock -skew > ./reports/clocks_skew.rpt
```

### report_annotated_parasitics

```tcl
report_annotated_parasitics > ./reports/parasitic_coverage.rpt
```

### report_exceptions

```tcl
report_exceptions > ./reports/timing_exceptions.rpt
report_exceptions -ignored > ./reports/ignored_exceptions.rpt
```

---

## 13. Useful Variables and Settings

### Timing Variables

```tcl
set_app_var timing_report_unconstrained_paths true
set_app_var timing_save_pin_arrival_and_slack true
set_app_var timing_remove_clock_reconvergence_pessimism true
set_app_var timing_crpr_threshold_ps 1.0
set_app_var timing_disable_clock_gating_checks false
set_app_var enable_recovery_removal_arcs true
set_app_var case_analysis_with_logic_constants true
set_app_var timing_input_port_default_clock true
set_app_var timing_enable_multiple_clocks_per_reg true
set_app_var timing_report_use_worst_parallel_cell_arc true
```

### SI Variables

```tcl
set_app_var si_enable_analysis true
set_app_var si_xtalk_delay_analysis_mode all_violating_paths
set_app_var si_filter_per_aggressor_noise_peak_ratio 0.01
set_app_var si_xtalk_double_switching_mode clock_as_aggressor
set_app_var si_xtalk_reselect_critical_path true
set_app_var si_noise_update_status true
```

### OCV Variables

```tcl
set_app_var timing_ocvm_enable_analysis true
set_app_var timing_aocvm_enable_analysis true   ;# for AOCV
set_app_var timing_pocvm_enable_analysis true    ;# for POCV
set_app_var timing_pocvm_corner_sigma 3.0
```

### Report Variables

```tcl
set_app_var report_default_significant_digits 4
set_app_var timing_report_unconstrained_paths true
set_app_var timing_save_pin_arrival_and_slack true
set_app_var sh_new_variable_message false
```

---

## 14. Utility Commands

### Object Access

```tcl
get_cells [-hier] [-filter <expr>] [<pattern>]
get_nets [-hier] [-filter <expr>] [<pattern>]
get_pins [-hier] [-filter <expr>] [<pattern>]
get_ports [<pattern>]
get_clocks [<pattern>]
get_lib_cells [<pattern>]
get_lib_pins [<pattern>]

all_inputs
all_outputs
all_registers
all_clocks
all_fanout -from [get_pins u_drv/Y] -flat -endpoints_only
all_fanin -to [get_pins u_ff/D] -flat -startpoints_only

# Attributes
get_attribute [get_cells u_buf] ref_name
get_attribute [get_pins u_ff/CK] arrival_time
get_attribute [get_pins u_ff/D] slack
list_attributes -class pin -application

# Collection operations
sizeof_collection [get_cells -hier *]
foreach_in_collection p [get_pins -hier -filter "is_clock_pin==true"] {
  puts "[get_attribute $p full_name] arrival=[get_attribute $p arrival_time]"
}
```

### Redirect and Logging

```tcl
redirect -file ./reports/timing.rpt {report_timing -max_paths 100}
redirect -append -file ./reports/log.txt {report_qor}

# Suppress messages
suppress_message {PTE-003 PTE-015}
unsuppress_message {PTE-003}
```

### Session

```tcl
# Save session
save_session ./sessions/pt_session

# Restore
restore_session ./sessions/pt_session

# History
history

# Exit
quit
exit
```

---

*End of PrimeTime Command Reference*
