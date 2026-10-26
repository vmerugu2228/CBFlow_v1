# Synopsys Design Compiler Command Reference

Comprehensive command reference for Synopsys Design Compiler (DC), the
industry-standard RTL synthesis tool. Covers dc_shell commands for reading
design data, constraints, compilation, optimization, reporting, and writing
outputs. Includes Design Compiler NXT and topographical mode (DCT) commands.

DC version baseline: T-2022.03 and later.

---

## Table of Contents

1. [Setup and Environment](#1-setup-and-environment)
2. [Reading Design Data](#2-reading-design-data)
3. [Elaboration and Linking](#3-elaboration-and-linking)
4. [Timing Constraints](#4-timing-constraints)
5. [Design Rule Constraints](#5-design-rule-constraints)
6. [Optimization Directives](#6-optimization-directives)
7. [Compilation](#7-compilation)
8. [Incremental Compilation](#8-incremental-compilation)
9. [DFT Integration](#9-dft-integration)
10. [Multi-Voltage / Low Power (UPF)](#10-multi-voltage--low-power-upf)
11. [Reporting](#11-reporting)
12. [Writing Output](#12-writing-output)
13. [Topographical Mode (DCT)](#13-topographical-mode-dct)
14. [Useful Variables and Settings](#14-useful-variables-and-settings)
15. [Utility Commands](#15-utility-commands)

---

## 1. Setup and Environment

### Library Setup

```tcl
# Target library — cells DC maps to
set target_library "saed14_rvt_ss_0p72v_125c.db saed14_hvt_ss_0p72v_125c.db"

# Link library — all libraries needed for linking (includes target + macros + IP)
set link_library "* $target_library sram_256x32.db pll.db io_cells.db"

# Symbol library (for schematic generation, optional)
set symbol_library "saed14.sdb"

# Search path
set search_path ". /libs/synopsys/db /libs/sram /project/rtl $search_path"

# Synthetic library (DesignWare)
set synthetic_library "dw_foundation.sldb"
lappend link_library $synthetic_library

# Physical library for topographical mode
set_app_var mw_reference_library "/libs/mw/saed14_rvt /libs/mw/saed14_hvt"
set_app_var mw_design_library "DC_LIB"
```

### Starting DC

```bash
# Standard mode
dc_shell

# Topographical mode (layout-aware)
dc_shell -topographical_mode

# With 64-bit
dc_shell-xg-t -64bit

# Batch mode
dc_shell -f run_synth.tcl -output_log_file synth.log
```

---

## 2. Reading Design Data

### read_file

General-purpose file reader.

```
read_file <file_list>
  -format {verilog | sverilog | vhdl | ddc | db | edif}
  [-define <macro_list>]
  [-autoread]
```

**Examples**

```tcl
read_file -format verilog {top.v sub_a.v sub_b.v}
read_file -format sverilog {top.sv pkg.sv}
read_file -format ddc top_elab.ddc
read_file -format db {sram.db pll.db}
```

### read_verilog

Read Verilog source files.

```
read_verilog <file_list>
  [-define <macro_list>]
  [-include <dir_list>]
```

```tcl
read_verilog {./rtl/top.v ./rtl/sub_a.v ./rtl/sub_b.v}
read_verilog -define {SYNTHESIS FPGA_OFF} {./rtl/top.v}
```

### read_sverilog

Read SystemVerilog source files.

```
read_sverilog <file_list>
  [-define <macro_list>]
  [-include <dir_list>]
```

```tcl
read_sverilog {./rtl/top.sv ./rtl/pkg.sv ./rtl/intf.sv}
```

### read_vhdl

Read VHDL source files.

```
read_vhdl <file_list>
  [-library <lib_name>]
  [-93 | -2008]
```

```tcl
read_vhdl -library work {entity.vhd arch.vhd}
read_vhdl -2008 {./rtl/top.vhd}
```

### read_ddc

Read Design Compiler compiled database.

```
read_ddc <file>
```

```tcl
read_ddc ./work/top_elab.ddc
```

### read_db

Read a Synopsys .db library file.

```
read_db <file_list>
```

```tcl
read_db {/libs/db/saed14_rvt_ss.db /libs/db/saed14_hvt_ss.db}
```

### analyze

Analyze source files (check syntax, create intermediate representation) without
reading into memory. Used with the `analyze`/`elaborate` two-step flow.

```
analyze -format {verilog | sverilog | vhdl} <file_list>
  [-define <macro_list>]
  [-library <work_lib>]
  [-vcs {+define+MACRO}]
```

**Examples**

```tcl
analyze -format sverilog -define {SYNTHESIS} [glob ./rtl/*.sv]
analyze -format verilog {top.v sub_a.v sub_b.v}
analyze -format vhdl -library work {entity.vhd}
```

### elaborate

Elaborate a previously analyzed design — resolves parameters, generates
hardware for generate blocks, creates the design hierarchy.

```
elaborate <design_name>
  [-architecture <arch_name>]
  [-library <work_lib>]
  [-parameters <param_list>]
  [-update]
```

**Examples**

```tcl
# Basic elaborate
elaborate top_chip

# Elaborate with parameter override
elaborate fifo -parameters "DEPTH=64,WIDTH=32"

# Elaborate specific VHDL architecture
elaborate cpu -architecture rtl -library work
```

### Two-Step Flow (Recommended)

```tcl
# Step 1: Analyze all files
analyze -format sverilog [glob ./rtl/pkg/*.sv]
analyze -format sverilog [glob ./rtl/src/*.sv]
analyze -format sverilog [glob ./rtl/top/*.sv]

# Step 2: Elaborate the top
elaborate chip_top

# Step 3: Link
link

# Alternative: use current_design
current_design chip_top
link
```

---

## 3. Elaboration and Linking

### current_design

Set the active design for subsequent commands.

```
current_design <design_name>
```

```tcl
current_design chip_top
```

### link

Resolve all cell references in the design using the link_library.

```
link
```

```tcl
current_design chip_top
link
# Check link status
check_design
```

### uniquify

Make every instance in the hierarchy unique (required if the same module is
instantiated multiple times with different constraints).

```
uniquify
  [-force]
  [-dont_skip_empty_designs]
```

```tcl
uniquify -force
```

### check_design

Verify the design for common issues before compilation.

```
check_design
  [-summary]
  [-multiple_designs]
  [-no_warnings]
```

```tcl
check_design > ./reports/check_design.rpt
check_design -summary
```

---

## 4. Timing Constraints

### create_clock

Define a clock signal.

```
create_clock <port_or_pin>
  -period <period>
  [-name <clock_name>]
  [-waveform {rise_time fall_time}]
  [-add]
```

**Examples**

```tcl
# Simple clock
create_clock [get_ports clk] -period 2.0 -name sys_clk

# Clock with duty cycle 40/60
create_clock [get_ports clk] -period 5.0 -waveform {0 2.0} -name sys_clk

# Virtual clock (no source port)
create_clock -period 3.33 -name virt_clk

# Generated clock
create_generated_clock [get_pins pll/clk_out] \
  -source [get_ports clk_ref] \
  -divide_by 2 \
  -name pll_clk

# Generated clock with multiply
create_generated_clock [get_pins pll/clk_fast] \
  -source [get_ports clk_ref] \
  -multiply_by 4 \
  -name pll_fast_clk

# Generated clock with edges
create_generated_clock [get_pins div/clk_out] \
  -source [get_pins div/clk_in] \
  -edges {1 3 5} \
  -name div2_clk
```

### Clock Uncertainty

```tcl
# Setup uncertainty
set_clock_uncertainty -setup 0.100 [get_clocks sys_clk]

# Hold uncertainty
set_clock_uncertainty -hold 0.050 [get_clocks sys_clk]

# Inter-clock uncertainty
set_clock_uncertainty -from [get_clocks clk_a] -to [get_clocks clk_b] \
  -setup 0.200

# Clock transition
set_clock_transition 0.080 [get_clocks sys_clk]

# Clock latency
set_clock_latency -source 0.500 [get_clocks sys_clk]
set_clock_latency 0.200 [get_clocks sys_clk]
```

### Input/Output Delays

```tcl
# Input delay (setup analysis)
set_input_delay -max 1.2 -clock sys_clk [get_ports data_in*]
set_input_delay -min 0.3 -clock sys_clk [get_ports data_in*]

# Output delay
set_output_delay -max 0.8 -clock sys_clk [get_ports data_out*]
set_output_delay -min 0.2 -clock sys_clk [get_ports data_out*]

# Input delay with clock_fall (DDR)
set_input_delay -max 1.0 -clock ddr_clk -clock_fall [get_ports ddr_data*]

# Adding to existing (for multi-clock)
set_input_delay -max 1.5 -clock clk_b -add_delay [get_ports shared_bus*]
```

### Path Delay Constraints

```tcl
# Max delay (setup)
set_max_delay 3.0 -from [get_ports data_in] -to [get_ports data_out]

# Min delay (hold)
set_min_delay 0.5 -from [get_ports data_in] -to [get_ports data_out]

# Multicycle path
set_multicycle_path 2 -setup -from [get_cells slow_reg*] -to [get_cells fast_reg*]
set_multicycle_path 1 -hold  -from [get_cells slow_reg*] -to [get_cells fast_reg*]

# False path
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
set_false_path -from [get_ports reset_n]
set_false_path -through [get_pins mux/sel]

# Case analysis
set_case_analysis 0 [get_ports test_mode]
set_case_analysis 1 [get_ports func_mode]

# Disable timing
set_disable_timing [get_cells bypass_mux]
```

### Driving Cell and Load

```tcl
# Set driving cell on inputs
set_driving_cell -lib_cell BUFX4 [get_ports data_in*]
set_driving_cell -lib_cell CLKBUFX8 [get_ports clk]

# Set input transition directly
set_input_transition 0.080 [get_ports data_in*]

# Set output load
set_load 0.050 [get_ports data_out*]
set_load -pin_load 0.100 [get_ports clk_out]

# Set fanout load
set_fanout_load 4 [get_ports data_out*]
```

### Clock Groups

```tcl
# Asynchronous clocks
set_clock_groups -asynchronous \
  -group [get_clocks sys_clk] \
  -group [get_clocks usb_clk] \
  -group [get_clocks jtag_clk]

# Physically exclusive clocks (muxed)
set_clock_groups -physically_exclusive \
  -group [get_clocks pll_clk_fast] \
  -group [get_clocks pll_clk_slow]

# Logically exclusive
set_clock_groups -logically_exclusive \
  -group [get_clocks func_clk] \
  -group [get_clocks test_clk]
```

### Path Groups

```tcl
# Create custom path groups for better optimization focus
group_path -name reg2reg -from [all_registers -clock_pins] -to [all_registers -data_pins]
group_path -name in2reg  -from [all_inputs] -to [all_registers -data_pins]
group_path -name reg2out -from [all_registers -clock_pins] -to [all_outputs]
group_path -name in2out  -from [all_inputs] -to [all_outputs]

# Critical path group with higher weight
group_path -name critical_paths -from [get_cells u_cpu/*] -to [get_cells u_cache/*] -weight 2.0
```

---

## 5. Design Rule Constraints

```tcl
# Max transition time
set_max_transition 0.200 [current_design]
set_max_transition 0.100 [get_clocks sys_clk]

# Max capacitance
set_max_capacitance 0.150 [current_design]

# Max fanout
set_max_fanout 32 [current_design]

# Max area (in library units)
set_max_area 0

# Min capacitance
set_min_capacitance 0.001 [get_ports data_in*]

# Operating conditions
set_operating_conditions -max ss_0p72v_125c -min ff_0p88v_m40c
set_operating_conditions ss_0p72v_125c -library saed14_rvt_ss

# Wire load model (for pre-layout)
set_wire_load_model -name "medium" -library saed14_rvt_ss
set_wire_load_mode enclosed
# Or top mode
set_wire_load_mode top
```

---

## 6. Optimization Directives

### Cell Usage Control

```tcl
# Dont use specific cells
set_dont_use [get_lib_cells saed14_rvt_ss/FILL*]
set_dont_use [get_lib_cells saed14_rvt_ss/DELCELL*]
set_dont_use [get_lib_cells saed14_rvt_ss/ANTENNA*]

# Remove dont_use
remove_attribute [get_lib_cells saed14_rvt_ss/DELCELL*] dont_use

# Dont touch — prevent optimization of a cell/net/design
set_dont_touch [get_cells u_analog_glue/*]
set_dont_touch [get_nets clk_root]
set_dont_touch [get_designs sub_block]

# Remove dont_touch
remove_attribute [get_cells u_analog_glue/*] dont_touch

# Size only — cell can be resized but not restructured
set_size_only [get_cells u_boundary_ff*]

# Prefer cells
set_prefer -min [get_lib_cells saed14_rvt_ss/DFFX1]
```

### Hierarchy Control

```tcl
# Ungroup a submodule (merge into parent for better optimization)
set_ungroup [get_designs small_sub_block]

# Dont ungroup
set_dont_touch [get_cells u_critical_sub]

# Auto-ungroup control
set_app_var compile_ultra_ungroup_dw true
set_app_var compile_delete_unloaded_sequential_cells true

# Flatten
ungroup -all -flatten
```

### Register Control

```tcl
# Prevent register merging
set_register_merging [get_cells u_fifo/*] false

# Register duplication for fanout
set_register_type -flip_flop DFFX1

# Preferred flop
set_app_var hdlin_ff_always_sync_set_reset true
set_app_var hdlin_ff_always_async_set_reset false
```

---

## 7. Compilation

### compile

Basic compile command (older, less powerful than compile_ultra).

```
compile
  [-map_effort {low | medium | high}]
  [-area_effort {low | medium | high}]
  [-incremental_mapping]
  [-no_design_rule]
  [-exact_map]
  [-ungroup_all]
  [-gate_clock]
  [-scan]
```

```tcl
compile -map_effort high -area_effort high
```

### compile_ultra

Advanced compile with aggressive optimizations.

```
compile_ultra
  [-incremental]
  [-gate_clock]
  [-retime]
  [-no_autoungroup]
  [-no_boundary_optimization]
  [-no_seq_output_inversion]
  [-area_high_effort_script]
  [-timing_high_effort_script]
  [-scan]
  [-exact_map]
  [-no_design_rule]
  [-check_only]
  [-spg]
```

**Key Options**

| Option | Description |
|---|---|
| `-incremental` | Incremental optimization (keeps current mapping, improves QoR) |
| `-gate_clock` | Insert clock gating to reduce dynamic power |
| `-retime` | Enable adaptive register retiming |
| `-no_autoungroup` | Disable automatic ungrouping of small modules |
| `-no_boundary_optimization` | Prevent optimization across hierarchical boundaries |
| `-no_seq_output_inversion` | Prevent inverting flip-flop outputs |
| `-area_high_effort_script` | Run area-focused multi-pass optimization |
| `-timing_high_effort_script` | Run timing-focused multi-pass optimization |
| `-scan` | Account for DFT scan chains during compilation |
| `-spg` | Enable Synopsys Physical Guidance (DC in topographical mode) |

**Examples**

```tcl
# Standard high-quality compile
compile_ultra -gate_clock -retime -scan

# Incremental optimization
compile_ultra -incremental

# Preserve hierarchy
compile_ultra -no_autoungroup -no_boundary_optimization

# Area-focused
compile_ultra -area_high_effort_script -gate_clock

# Timing-focused
compile_ultra -timing_high_effort_script -retime

# With SPG (topographical mode)
compile_ultra -spg -gate_clock -retime -scan
```

### compile_ultra -incremental

Special considerations for incremental compile:

```tcl
# First compile
compile_ultra -gate_clock -retime -scan

# Check QoR
report_qor

# Apply additional constraints or fixes
set_max_delay 1.5 -from [get_cells slow_path_reg*] -to [get_cells dest_reg*]

# Incremental (refines without destroying prior mapping)
compile_ultra -incremental

# Multiple incremental passes
compile_ultra -incremental
compile_ultra -incremental
```

---

## 8. Incremental Compilation

### Strategies for Closure

```tcl
# Strategy 1: Multi-pass compile
compile_ultra -gate_clock -retime -scan
report_timing -max_paths 20
compile_ultra -incremental
report_timing -max_paths 20

# Strategy 2: Targeted ungrouping
set_ungroup [get_designs critical_sub_block] true
compile_ultra -incremental

# Strategy 3: Path-specific effort
group_path -name critical -from [get_cells u_cpu/alu/*] -to [get_cells u_cpu/rf/*] -weight 5
compile_ultra -incremental

# Strategy 4: Boundary optimization
set_boundary_optimization [get_designs sub_block] true
compile_ultra -incremental
```

---

## 9. DFT Integration

### Scan Configuration

```tcl
# Set scan style
set_scan_configuration -style multiplexed_flip_flop
set_scan_configuration -chain_count 8
set_scan_configuration -clock_mixing mix_clocks
set_scan_configuration -add_lockup true

# Set DFT signal
set_dft_signal -view existing_dft -type ScanClock -timing {45 55} -port clk
set_dft_signal -view spec -type ScanEnable -port scan_en -active_state 1
set_dft_signal -view spec -type ScanDataIn -port {si_1 si_2 si_3 si_4}
set_dft_signal -view spec -type ScanDataOut -port {so_1 so_2 so_3 so_4}

# Test mode
set_dft_signal -view spec -type TestMode -port test_mode -active_state 1
set_dft_signal -view spec -type Reset -port reset_n -active_state 0

# Create test protocol
create_test_protocol

# Preview scan chains
preview_dft > ./reports/dft_preview.rpt
dft_drc > ./reports/dft_drc.rpt

# Insert scan
insert_dft

# Post-DFT checks
dft_drc -coverage_estimate > ./reports/dft_drc_post.rpt
```

### DFT Variables

```tcl
set_app_var test_default_scan_style multiplexed_flip_flop
set_app_var test_default_delay 0
set_app_var test_default_bidir_delay 0
set_app_var test_default_strobe 40
set_app_var test_default_period 100
```

---

## 10. Multi-Voltage / Low Power (UPF)

### Reading Power Intent

```tcl
# Set multi-voltage mode
set_app_var enable_golden_upf true

# Read UPF
load_upf ./upf/top.upf

# Or read UPF file
read_upf ./upf/top.upf

# Set scope-specific UPF
load_upf ./upf/cpu.upf -scope u_cpu

# Verify power intent
check_mv_design
check_mv_design -verbose
```

### UPF-Related Commands

```tcl
# Create power domain (usually in UPF file, can also be in TCL)
create_power_domain PD_TOP

# Create supply ports and nets
create_supply_port VDD
create_supply_net VDD -domain PD_TOP
connect_supply_net VDD -ports VDD

# Set domain supply
set_domain_supply_net PD_TOP -primary_power_net VDD -primary_ground_net VSS

# Isolation strategy
set_isolation iso_cpu \
  -domain PD_CPU \
  -isolation_power_net VDD_AO \
  -isolation_ground_net VSS \
  -clamp_value 0 \
  -applies_to outputs

# Level shifter strategy
set_level_shifter ls_cpu \
  -domain PD_CPU \
  -applies_to both \
  -rule both

# Retention strategy
set_retention ret_cpu \
  -domain PD_CPU \
  -retention_power_net VDD_RET \
  -retention_ground_net VSS

# Map isolation cells
map_isolation_cell iso_cpu -lib_cells {ISO_LOW_TO_HIGH}
map_level_shifter_cell ls_cpu -lib_cells {LS_HH LS_HL LS_LH}
map_retention_cell ret_cpu -lib_cells {RET_DFF}
```

---

## 11. Reporting

### report_timing

```
report_timing
  [-delay_type {max | min | min_max}]
  [-path_type {full | full_clock | full_clock_expanded | summary | end}]
  [-max_paths <N>]
  [-nworst <N>]
  [-group <path_group_list>]
  [-from <startpoints>]
  [-through <through_points>]
  [-to <endpoints>]
  [-nets]
  [-capacitance]
  [-transition_time]
  [-input_pins]
  [-significant_digits <N>]
  [-sort_by {slack | group}]
  [-nosplit]
  > <output_file>
```

**Examples**

```tcl
# Basic worst path
report_timing > ./reports/timing.rpt

# Detailed setup timing
report_timing \
  -delay_type max \
  -path_type full_clock_expanded \
  -max_paths 100 \
  -nworst 5 \
  -nets \
  -capacitance \
  -transition_time \
  -input_pins \
  -significant_digits 4 \
  > ./reports/timing_setup.rpt

# Hold timing
report_timing -delay_type min -max_paths 50 > ./reports/timing_hold.rpt

# Specific path group
report_timing -group {clk_sys} -max_paths 20

# Timing through a point
report_timing -through [get_pins u_alu/carry_out] -max_paths 10

# Timing from/to specific
report_timing -from [get_cells u_fifo/wr_ptr_reg*] \
              -to [get_cells u_fifo/rd_ptr_reg*] \
              -max_paths 10
```

### report_area

```
report_area
  [-hierarchy]
  [-nosplit]
  > <output_file>
```

```tcl
report_area > ./reports/area.rpt
report_area -hierarchy > ./reports/area_hier.rpt
```

### report_power

```
report_power
  [-hierarchy]
  [-verbose]
  [-analysis_effort {low | medium | high}]
  [-net_switching_power]
  [-cell_power]
  [-leakage_power]
  > <output_file>
```

```tcl
report_power > ./reports/power.rpt
report_power -hierarchy -verbose > ./reports/power_hier.rpt
report_power -analysis_effort high > ./reports/power_detailed.rpt
```

### report_constraint

```
report_constraint
  [-all_violators]
  [-max_delay]
  [-min_delay]
  [-max_transition]
  [-max_capacitance]
  [-max_fanout]
  [-verbose]
  [-nosplit]
  > <output_file>
```

```tcl
report_constraint -all_violators > ./reports/constraint_violations.rpt
report_constraint -all_violators -verbose > ./reports/constraint_violations_verbose.rpt
```

### report_qor

```
report_qor
  [-summary]
  [-significant_digits <N>]
  > <output_file>
```

```tcl
report_qor > ./reports/qor.rpt
report_qor -summary
```

### report_reference

```tcl
# Cell usage report
report_reference > ./reports/references.rpt

# With hierarchy
report_reference -hierarchy > ./reports/references_hier.rpt
```

### Additional Reports

```tcl
# Clock report
report_clock > ./reports/clocks.rpt
report_clock -skew > ./reports/clock_skew.rpt

# Port report
report_port > ./reports/ports.rpt

# Net report
report_net > ./reports/nets.rpt
report_net -connections -verbose [get_nets high_fanout_net]

# Cell report
report_cell [get_cells -hier *] > ./reports/cells.rpt

# Design report
report_design > ./reports/design.rpt

# Compile status
report_compile_options

# Hierarchy
report_hierarchy > ./reports/hierarchy.rpt

# Clock gating
report_clock_gating > ./reports/clock_gating.rpt

# Resources (DesignWare usage)
report_resources > ./reports/resources.rpt

# Timing exceptions
report_timing_requirements > ./reports/timing_reqs.rpt

# Threshold voltage groups
report_threshold_voltage_group > ./reports/vth_groups.rpt

# Multi-voltage
report_mv_cell > ./reports/mv_cells.rpt
check_mv_design > ./reports/mv_check.rpt

# DFT
report_dft_signal > ./reports/dft_signals.rpt
report_scan_chain > ./reports/scan_chains.rpt
report_scan_configuration > ./reports/scan_config.rpt
```

---

## 12. Writing Output

### write_file

General-purpose output writer.

```
write_file -format {verilog | ddc | db | svsim} <design>
  -hierarchy
  -output <file>
```

```tcl
# Write DDC
write_file -format ddc -hierarchy -output ./output/top_synth.ddc

# Write gate-level Verilog
write_file -format verilog -hierarchy -output ./output/top_synth.v
```

### write -format verilog (Equivalent)

```
write -format verilog -hierarchy -output <file>
```

```tcl
write -format verilog -hierarchy -output ./output/top_netlist.v
```

### write_sdc

Write timing constraints.

```
write_sdc <file>
  [-version <version>]
  [-nosplit]
```

```tcl
write_sdc ./output/top_synth.sdc -nosplit
write_sdc ./output/top_synth_sdc2.0.sdc -version 2.0
```

### write_sdf

Write Standard Delay Format for gate-level simulation.

```
write_sdf <file>
  [-version <version>]
  [-significant_digits <N>]
  [-context {verilog | vhdl}]
```

```tcl
write_sdf ./output/top_synth.sdf -version 3.0
```

### write_script

Write the current constraints as a TCL script.

```
write_script
  [-output <file>]
  [-format {dctcl | ptsh}]
  [-nosplit]
```

```tcl
write_script -output ./output/constraints.tcl -format dctcl
```

### change_names

Rename design objects to be compatible with downstream tools.

```
change_names
  -rules <rule_name>
  -hierarchy
  [-verbose]
```

```tcl
# Define naming rules
define_name_rules custom_rules \
  -allowed "A-Za-z0-9_" \
  -first_restricted "0-9_" \
  -last_restricted "_" \
  -max_length 256 \
  -type cell \
  -map {{"\\[" "_"} {"\\]" "_"} {"/" "__"}}

# Apply
change_names -rules verilog -hierarchy
# or
change_names -rules custom_rules -hierarchy
```

### write_test_protocol

```tcl
write_test_protocol -output ./output/top.spf
```

### write_scan_def

```tcl
write_scan_def -output ./output/top_scan.def
```

### Additional Write Commands

```tcl
# Write UPF
save_upf ./output/top.upf

# Write SVF (for Formality)
set_svf ./output/top.svf  # Do this BEFORE compile

# Write SAIF name mapping
write_saif_name_mapping -output ./output/saif_map.txt

# Write milkyway (topographical mode)
write_milkyway -output DC_MW_LIB -overwrite

# Write DEF (topographical mode)
write_def -output ./output/top_synth.def
```

---

## 13. Topographical Mode (DCT)

DCT provides layout-aware synthesis for better correlation with PnR.

### Setup for Topographical Mode

```tcl
# Start dc_shell in topo mode
# dc_shell -topographical_mode

# Set physical libraries
set_app_var mw_reference_library [list \
  /libs/mw/saed14_rvt \
  /libs/mw/saed14_hvt \
  /libs/mw/sram_macros \
]
set_app_var mw_design_library "DC_MW_LIB"

# Create MW design library
create_mw_lib DC_MW_LIB \
  -technology /pdk/tech/saed14nm.tf \
  -mw_reference_library $mw_reference_library

# Open MW lib
open_mw_lib DC_MW_LIB

# Set TLU+ for parasitic estimation
set_tlu_plus_files \
  -max_tluplus /pdk/tluplus/saed14_1p9m_Cmax.tluplus \
  -min_tluplus /pdk/tluplus/saed14_1p9m_Cmin.tluplus \
  -tech2itf_map /pdk/tluplus/saed14_tf_itf_tluplus.map
```

### DCT-Specific Commands

```tcl
# Read floorplan DEF
read_def ./floorplan/top.def

# Extract RC
extract_rc

# Physical constraints
set_fuzzy_query_options -threshold 10
set_congestion_options -max_util 0.80

# Compile with SPG
compile_ultra -spg -gate_clock -retime -scan

# Check congestion
report_congestion > ./reports/congestion.rpt

# Write out DEF and MW
write_def -output ./output/top_dct.def
write_milkyway -output DC_MW_LIB -overwrite

# Close MW lib
close_mw_lib
```

### DCT App Vars

```tcl
set_app_var physopt_enable_via_res_support true
set_app_var spg_enable_via_resistance_support true
set_app_var enable_recovery_removal_arcs true
set_app_var case_analysis_with_logic_constants true
```

---

## 14. Useful Variables and Settings

### Commonly Used App Variables

```tcl
# --- Compilation Behavior ---
set_app_var compile_ultra_ungroup_dw true
set_app_var compile_delete_unloaded_sequential_cells true
set_app_var compile_seqmap_propagate_constants true
set_app_var compile_seqmap_propagate_high_effort true
set_app_var compile_enable_register_merging true

# --- HDL Interpretation ---
set_app_var hdlin_enable_presto_for_vhdl true
set_app_var hdlin_auto_save_templates true
set_app_var hdlin_check_no_latch true
set_app_var hdlin_ff_always_sync_set_reset true
set_app_var hdlin_while_loop_iterations 1024
set_app_var hdlin_infer_multibit default_all

# --- Timing ---
set_app_var timing_enable_multiple_clocks_per_reg true
set_app_var timing_input_port_default_clock true
set_app_var enable_recovery_removal_arcs true
set_app_var case_analysis_with_logic_constants true

# --- Optimization ---
set_app_var compile_timing_high_effort true
set_app_var compile_register_replication true

# --- Power ---
set_app_var power_preserve_rtl_hier_names true
set_app_var default_input_transition 0.080

# --- General ---
set_app_var sh_new_variable_message false
set_app_var report_default_significant_digits 4
set_app_var alib_library_analysis_path ./alib
set_app_var verilogout_no_tri true
set_app_var verilogout_show_unconnected_pins true
set_app_var bus_naming_style {%s[%d]}

# --- SVF for Formality ---
set_svf ./output/top.svf
```

---

## 15. Utility Commands

### Object Access

```tcl
# Get objects
get_cells [-hier] [-filter <expr>] [<pattern>]
get_nets [-hier] [-filter <expr>] [<pattern>]
get_pins [-hier] [-filter <expr>] [<pattern>]
get_ports [<pattern>]
get_clocks [<pattern>]
get_designs [<pattern>]
get_lib_cells [<pattern>]
get_lib_pins [<pattern>]
get_libs [<pattern>]

# All inputs/outputs
all_inputs
all_outputs
all_registers
all_registers -clock_pins
all_registers -data_pins
all_clocks

# Attributes
get_attribute [get_cells u_cpu] area
get_attribute [get_cells u_cpu] ref_name
set_attribute [get_cells u_cpu] dont_touch true
list_attributes -application -class cell

# Filter
get_cells -hier -filter "ref_name =~ BUF* && dont_touch != true"
get_cells -hier -filter "area > 10.0"

# Collection operations
sizeof_collection [get_cells -hier *]
foreach_in_collection c [get_cells -hier -filter "is_sequential==true"] {
  puts [get_attribute $c full_name]
}
sort_collection [get_cells -hier *] area -descending
add_to_collection $set1 $set2
remove_from_collection $set1 $set2
compare_collections $set1 $set2
```

### Session Management

```tcl
# History
history
alias ll "report_timing -max_paths 20"

# Source a script
source ./scripts/constraints.tcl

# Redirect output
redirect -file ./reports/timing.rpt {report_timing -max_paths 100}
redirect -append -file ./reports/log.txt {report_qor}

# Suppress messages
suppress_message {UID-401 TEST-130}
unsuppress_message {UID-401}

# Print messages
printvar target_library
echo "Current design: [current_design]"

# Timing
sh date
set start_time [clock seconds]
# ... do stuff ...
set elapsed [expr [clock seconds] - $start_time]
echo "Elapsed: ${elapsed}s"

# Exit
quit
exit
```

### Design Exploration

```tcl
# List designs in memory
list_designs

# List libraries
list_libs

# Remove design
remove_design -all
remove_design [get_designs sub_block]

# Check library
check_library > ./reports/check_lib.rpt
```

---

*End of Design Compiler Command Reference*
