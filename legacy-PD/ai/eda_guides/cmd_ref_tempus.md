# Cadence Tempus Timing Signoff -- Comprehensive Command Reference

## Table of Contents

1. [Design Import and Setup](#design-import-and-setup)
2. [MMMC (Multi-Mode Multi-Corner) Setup](#mmmc-multi-mode-multi-corner-setup)
3. [Analysis Configuration](#analysis-configuration)
4. [SOCV (Statistical On-Chip Variation)](#socv-statistical-on-chip-variation)
5. [Signal Integrity (SI) Analysis](#signal-integrity-si-analysis)
6. [Timing Reports](#timing-reports)
7. [Constraint Reports](#constraint-reports)
8. [Clock Timing Analysis](#clock-timing-analysis)
9. [ECO Commands](#eco-commands)
10. [Concurrent Multi-Corner Analysis](#concurrent-multi-corner-analysis)
11. [Timing Debug Commands](#timing-debug-commands)
12. [Advanced Timing Features](#advanced-timing-features)
13. [Output and Export Commands](#output-and-export-commands)
14. [Utility and Session Commands](#utility-and-session-commands)

---

## Design Import and Setup

### read_lib

Reads Liberty timing libraries into the Tempus database.

```tcl
# Read Liberty library
read_lib /libs/stdcells/ss_0p75v_125c.lib

# Read multiple libraries
read_lib {/libs/stdcells/ss_0p75v_125c.lib /libs/sram/sram_ss.lib /libs/io/io_ss.lib}

# Read ECSM library (Effective Current Source Model)
read_lib -ecsm /libs/stdcells/ss_ecsm.lib

# Read CCS library (Composite Current Source)
read_lib -ccs /libs/stdcells/ss_ccs.lib

# Read NLDM library (Non-Linear Delay Model)
read_lib /libs/stdcells/ss_nldm.lib

# Read library with process variation
read_lib -aocv /libs/stdcells/ss_aocv.lib
```

### read_verilog

Reads gate-level netlist.

```tcl
# Read single netlist
read_verilog /output/innovus/top_chip.v

# Read multiple files
read_verilog {/output/innovus/top_chip.v /libs/sram/sram_bb.v}

# Set top cell
set_top_module top_chip
```

### read_spef

Reads parasitic data (SPEF/DSPF).

```tcl
# Read SPEF
read_spef /extraction/top_chip.spef

# Read SPEF for specific RC corner
read_spef -rc_corner rc_wc /extraction/top_chip_wc.spef
read_spef -rc_corner rc_bc /extraction/top_chip_bc.spef

# Read SPEF with options
read_spef -rc_corner rc_wc -map_file /extraction/spef_map.txt \
    /extraction/top_chip_wc.spef

# Read reduced SPEF (block-level)
read_spef -partition u_sub_block /extraction/sub_block.spef

# Read incremental SPEF
read_spef -incremental /extraction/top_chip_eco.spef
```

### read_sdc

Reads timing constraints.

```tcl
# Read SDC
read_sdc /constraints/top_chip.sdc

# Read SDC with echo
read_sdc -echo /constraints/top_chip.sdc

# Read SDC for specific mode
read_sdc -mode func /constraints/func.sdc
read_sdc -mode test /constraints/test.sdc
```

### read_def

Reads physical data (for physical-aware STA).

```tcl
# Read DEF
read_def /output/innovus/top_chip.def

# Read DEF for physical context
read_def -physical_only /output/innovus/top_chip.def
```

### read_design

Loads design from database.

```tcl
# Read Innovus database
read_design /output/innovus/top_chip_final.inn

# Read OA database
read_design -oa -lib top_lib -cell top_chip -view layout
```

### Full Setup Flow

```tcl
# Read libraries and technology
read_lib {ss_0p75v_125c.lib sram_ss.lib io_ss.lib}
read_lib {ff_0p95v_m40c.lib sram_ff.lib io_ff.lib}

# Read netlist
read_verilog /output/innovus/top_chip.v
set_top_module top_chip

# Read physical data
read_def /output/innovus/top_chip.def

# Read parasitics
read_spef /extraction/top_chip_wc.spef

# Read constraints
read_sdc /constraints/top_chip.sdc

# OR use MMMC file
source /scripts/mmmc.tcl
```

---

## MMMC (Multi-Mode Multi-Corner) Setup

### create_library_set

```tcl
# Worst case
create_library_set -name ls_wc \
    -timing {/libs/stdcells/ss_0p75v_125c.lib \
             /libs/sram/sram_ss_0p75v_125c.lib \
             /libs/io/io_ss_0p75v_125c.lib}

# Best case
create_library_set -name ls_bc \
    -timing {/libs/stdcells/ff_0p95v_m40c.lib \
             /libs/sram/sram_ff_0p95v_m40c.lib \
             /libs/io/io_ff_0p95v_m40c.lib}

# Typical
create_library_set -name ls_tc \
    -timing {/libs/stdcells/tt_0p85v_25c.lib \
             /libs/sram/sram_tt_0p85v_25c.lib \
             /libs/io/io_tt_0p85v_25c.lib}

# With SI libraries
create_library_set -name ls_wc_si \
    -timing {/libs/stdcells/ss_0p75v_125c.lib} \
    -si {/libs/stdcells/ss_0p75v_125c_ccs.lib}

# With AOCV library
create_library_set -name ls_wc_aocv \
    -timing {/libs/stdcells/ss_0p75v_125c.lib} \
    -aocv {/libs/stdcells/ss_aocv.lib}
```

### create_rc_corner

```tcl
# Worst-case RC
create_rc_corner -name rc_wc \
    -qrc_tech /libs/tech/qrcTechFile \
    -T 125 \
    -preRoute_res 1.2 \
    -preRoute_cap 1.1 \
    -postRoute_res 1.2 \
    -postRoute_cap 1.1

# Best-case RC
create_rc_corner -name rc_bc \
    -qrc_tech /libs/tech/qrcTechFile \
    -T -40 \
    -preRoute_res 0.8 \
    -preRoute_cap 0.9 \
    -postRoute_res 0.8 \
    -postRoute_cap 0.9

# Typical RC
create_rc_corner -name rc_tc \
    -qrc_tech /libs/tech/qrcTechFile \
    -T 25
```

### create_delay_corner

```tcl
# Worst case
create_delay_corner -name dc_wc \
    -library_set ls_wc \
    -rc_corner rc_wc

# Best case
create_delay_corner -name dc_bc \
    -library_set ls_bc \
    -rc_corner rc_bc

# Typical
create_delay_corner -name dc_tc \
    -library_set ls_tc \
    -rc_corner rc_tc

# With opcond override
create_delay_corner -name dc_wc_slow \
    -library_set ls_wc \
    -rc_corner rc_wc \
    -opcond_library ss_0p75v_125c \
    -opcond ss_0p75v_125c
```

### create_constraint_mode

```tcl
# Functional mode
create_constraint_mode -name cm_func \
    -sdc_files {/constraints/func.sdc}

# Test/scan mode
create_constraint_mode -name cm_test \
    -sdc_files {/constraints/test.sdc}

# Multiple SDC files
create_constraint_mode -name cm_func_full \
    -sdc_files {/constraints/clocks.sdc \
                /constraints/io_delays.sdc \
                /constraints/exceptions.sdc}
```

### create_analysis_view

```tcl
# Setup views
create_analysis_view -name av_wc_func \
    -constraint_mode cm_func \
    -delay_corner dc_wc

create_analysis_view -name av_wc_test \
    -constraint_mode cm_test \
    -delay_corner dc_wc

# Hold views
create_analysis_view -name av_bc_func \
    -constraint_mode cm_func \
    -delay_corner dc_bc

# Additional corner views
create_analysis_view -name av_tc_func \
    -constraint_mode cm_func \
    -delay_corner dc_tc
```

### set_analysis_view

```tcl
# Set active views
set_analysis_view -setup {av_wc_func av_wc_test} \
                  -hold {av_bc_func}

# Set all views
set_analysis_view -setup {av_wc_func av_wc_test av_tc_func} \
                  -hold {av_bc_func av_tc_func}

# Query views
report_analysis_view
get_analysis_view -list
```

---

## Analysis Configuration

### setAnalysisMode

```tcl
# Analysis type
setAnalysisMode -analysisType onChipVariation
# Options: single, bcwc (best-case/worst-case), onChipVariation

# CPPR (Clock Path Pessimism Removal)
setAnalysisMode -cppr both
# Options: none, setup, hold, both

# Check type
setAnalysisMode -checkType setup
# Options: setup, hold

# SI analysis
setAnalysisMode -analysisType onChipVariation

# Timing window for SI
setAnalysisMode -timingWindowAnalysis true

# Glitch analysis
setAnalysisMode -glitchAnalysis true

# Advanced settings
setAnalysisMode -honorClockDomains true
setAnalysisMode -skew true
setAnalysisMode -useOutputPinCap true
```

### Timing Derates

```tcl
# Flat OCV derates
set_timing_derate -early 0.95 -cell_delay -net_delay
set_timing_derate -late 1.05 -cell_delay -net_delay

# Separate cell and net derates
set_timing_derate -early 0.93 -cell_delay
set_timing_derate -late 1.07 -cell_delay
set_timing_derate -early 0.97 -net_delay
set_timing_derate -late 1.03 -net_delay

# Per-cell-type derates
set_timing_derate -early 0.90 -cell_delay [get_lib_cells */SRAM*]
set_timing_derate -late 1.10 -cell_delay [get_lib_cells */SRAM*]

# Clock-specific derates
set_timing_derate -early 0.95 -clock -cell_delay
set_timing_derate -late 1.05 -clock -cell_delay
set_timing_derate -early 0.93 -data -cell_delay
set_timing_derate -late 1.07 -data -cell_delay

# Report derates
report_timing_derate
```

---

## SOCV (Statistical On-Chip Variation)

### SOCV Setup

```tcl
# Enable SOCV
setAnalysisMode -analysisType onChipVariation

# Read SOCV data (LVF - Liberty Variation Format)
read_lib -socv /libs/stdcells/ss_socv.lib

# OR specify through MMMC
create_library_set -name ls_wc_socv \
    -timing {ss_0p75v_125c.lib} \
    -socv {ss_socv.lib}
```

### set_timing_derate_model

```tcl
# Set SOCV derate model
set_timing_derate_model -socv

# Set AOCV derate model
set_timing_derate_model -aocv

# Set flat OCV
set_timing_derate_model -flat

# Combined model
set_timing_derate_model -socv -aocv_guardband 0.02
```

### read_socv

```tcl
# Read SOCV LVF data
read_socv /libs/stdcells/ss_lvf.lib

# Read SOCV with distance-based variation
read_socv -distance /libs/stdcells/ss_lvf_distance.lib

# Verify SOCV data
report_socv_data
```

### AOCV (Advanced OCV)

```tcl
# Read AOCV table
read_aocv /libs/stdcells/ss_aocv_table.lib

# Set AOCV mode
set_timing_derate -aocv

# AOCV with depth and distance
set_db timing_analysis_aocv true
set_db timing_aocv_analysis_mode combine_launch_capture

# Report AOCV derates
report_timing -path_type full_clock -derate
```

---

## Signal Integrity (SI) Analysis

### SI Setup

```tcl
# Enable SI
set_si_mode -analysisType aae    ;# aae (Arnoldi Approximation Engine)

# SI thresholds
set_si_mode -deltaDelayThreshold 0.01
set_si_mode -glitchAnalysis true
set_si_mode -glitchThreshold 0.15
set_si_mode -noisePessimism 0.0

# SI aggressor settings
set_si_mode -numAggressorAlignment 3

# Enable timing window based filtering
set_si_mode -enableTimingWindow true

# Delta delay calculation
set_si_mode -deltaDelayCalcMode accurate
```

### set_si_mode (Full Reference)

```tcl
# Core SI settings
set_si_mode -analysisType aae
set_si_mode -enableTimingWindow true
set_si_mode -deltaDelayThreshold 0.005

# Noise analysis
set_si_mode -glitchAnalysis true
set_si_mode -glitchThreshold 0.10
set_si_mode -noiseVddPct 0.15
set_si_mode -noiseVssPct 0.15

# Aggressor settings
set_si_mode -numAggressorAlignment 5
set_si_mode -maxAggressors 100

# Coupling cap settings
set_si_mode -couplingCapThreshold 0.001

# Functional mode (reduce pessimism)
set_si_mode -enableFunctionality true

# Reporting
set_si_mode -reportGlitchDetails true
```

### report_noise

```tcl
# Report noise violations
report_noise

# Report above threshold
report_noise -above_threshold

# Report noise on specific net
report_noise -net clock_net

# Report noise with details
report_noise -above_threshold -detail -max_violations 100

# Report noise summary
report_noise -summary

# Report glitch
report_noise -glitch -above_threshold

# Report to file
report_noise -above_threshold > reports/noise.rpt
```

### SI Timing

```tcl
# Run SI-aware timing
report_timing -si -max_paths 100

# SI delta delay report
report_si_delay_summary

# Report coupling caps
report_si_coupling_caps -net critical_net

# SI ECO
fixSI -postRoute
```

---

## Timing Reports

### report_timing (Complete Reference)

The most important command in Tempus. Full options reference.

```tcl
# ==================================================================
# Basic Usage
# ==================================================================

# Worst setup path
report_timing

# Worst hold path
report_timing -early

# Top N paths
report_timing -max_paths 100

# Paths per endpoint
report_timing -max_paths 100 -nworst 5

# ==================================================================
# Path Type and Format
# ==================================================================

# Full clock path
report_timing -path_type full_clock

# Endpoint only
report_timing -path_type endpoint

# Summary
report_timing -path_type summary

# Full path with all details
report_timing -path_type full_clock -net -cap -tran -input_pins -derate

# ==================================================================
# Filtering by Start/End Points
# ==================================================================

# From specific cell
report_timing -from [get_pins reg_a/CK]

# To specific cell
report_timing -to [get_pins reg_b/D]

# Through specific point
report_timing -through [get_pins mux/Y]

# Multiple through points
report_timing -through [get_pins mux1/Y] -through [get_pins mux2/Y]

# From clock domain
report_timing -from [get_clocks clk_a]

# To clock domain
report_timing -to [get_clocks clk_b]

# Between clock domains
report_timing -from [get_clocks clk_a] -to [get_clocks clk_b]

# From input ports
report_timing -from [get_ports data_in*]

# To output ports
report_timing -to [get_ports data_out*]

# ==================================================================
# Slack Filtering
# ==================================================================

# Only violating paths
report_timing -max_slack 0.0

# Paths with slack between -0.5 and 0.0
report_timing -max_slack 0.0 -min_slack -0.5

# Paths with positive slack up to 0.1
report_timing -max_slack 0.1

# ==================================================================
# Path Group Filtering
# ==================================================================

# Specific path group
report_timing -group reg2reg
report_timing -group in2reg
report_timing -group reg2out
report_timing -group in2out

# ==================================================================
# Detailed Path Information
# ==================================================================

# Net names
report_timing -net

# Capacitance
report_timing -cap

# Transition (slew)
report_timing -tran

# Input pin arrivals
report_timing -input_pins

# Derate values
report_timing -derate

# Physical distance
report_timing -physical

# CPPR credit
report_timing -cppr

# All details combined
report_timing -max_paths 10 -path_type full_clock \
    -net -cap -tran -input_pins -derate -physical -cppr \
    -significant_digits 4

# ==================================================================
# View-Specific Reporting
# ==================================================================

# Specific analysis view
report_timing -view av_wc_func

# All views
report_timing -view {av_wc_func av_bc_func av_tc_func}

# ==================================================================
# SI-Aware Reporting
# ==================================================================

# With SI effects
report_timing -si

# SI with noise details
report_timing -si -nosplit

# ==================================================================
# Output Control
# ==================================================================

# To file
report_timing -max_paths 100 > reports/timing.rpt

# Significant digits
report_timing -significant_digits 4

# No split (single-line format)
report_timing -nosplit

# Format for machine parsing
report_timing -format {instance cell arc delay arrival}

# ==================================================================
# Special Modes
# ==================================================================

# Unconstrained paths
report_timing -unconstrained

# Disabled paths
report_timing -disabled

# Ideal clocks only
report_timing -ideal_clocks

# Propagated clocks only
report_timing -propagated_clocks

# Report with CRPR/CPPR
report_timing -cppr -path_type full_clock

# Bottleneck analysis
report_timing -max_paths 1000 -path_type endpoint -collection
```

**Complete report_timing options table:**

| Option | Description |
|--------|-------------|
| `-max_paths <N>` | Max paths to report |
| `-nworst <N>` | Max paths per endpoint |
| `-path_type <type>` | `full_clock`, `full`, `endpoint`, `summary` |
| `-early` | Hold (early) analysis |
| `-late` | Setup (late) analysis (default) |
| `-from <obj>` | Startpoint filter |
| `-to <obj>` | Endpoint filter |
| `-through <obj>` | Through-point filter (repeatable) |
| `-group <name>` | Path group filter |
| `-view <name>` | Analysis view filter |
| `-max_slack <val>` | Maximum slack filter |
| `-min_slack <val>` | Minimum slack filter |
| `-net` | Show net names in path |
| `-cap` | Show capacitance values |
| `-tran` | Show transition/slew |
| `-input_pins` | Show input pin arrivals |
| `-derate` | Show OCV derate factors |
| `-physical` | Show physical distance |
| `-cppr` | Show CPPR credit |
| `-si` | Include SI effects |
| `-significant_digits <N>` | Decimal precision |
| `-nosplit` | Single-line format |
| `-unconstrained` | Show unconstrained paths |
| `-format <fields>` | Custom output format |
| `-collection` | Return as collection object |

---

## Constraint Reports

### report_constraint

```tcl
# All violators
report_constraint -all_violators

# Setup violators
report_constraint -late -all_violators

# Hold violators
report_constraint -early -all_violators

# Max transition violators
report_constraint -max_transition -all_violators

# Max capacitance violators
report_constraint -max_capacitance -all_violators

# Max fanout violators
report_constraint -max_fanout -all_violators

# Min pulse width violators
report_constraint -min_pulse_width -all_violators

# All DRC violators
report_constraint -drv_violation_type {max_transition max_capacitance max_fanout} \
    -all_violators

# Verbose
report_constraint -all_violators -verbose

# Output to file
report_constraint -all_violators > reports/violations.rpt

# By view
report_constraint -all_violators -view av_wc_func

# Specific cells
report_constraint -all_violators -from [get_cells u_core/*]
```

### check_timing

Validates timing constraints completeness.

```tcl
# Full check
check_timing

# Verbose check
check_timing -verbose

# Specific checks
check_timing -type {no_clock unconstrained_endpoints}

# Check for missing constraints
check_timing -type {no_input_delay no_output_delay}

# All check types
check_timing -type {
    no_clock
    unconstrained_endpoints
    no_input_delay
    no_output_delay
    loop
    partial_input_delay
    partial_output_delay
    unexpandable_clocks
}

# Output
check_timing -verbose > reports/check_timing.rpt
```

---

## Clock Timing Analysis

### report_clock_timing

```tcl
# Clock skew report
report_clock_timing -type skew

# Clock latency report
report_clock_timing -type latency

# Clock summary
report_clock_timing -type summary

# Specific clock
report_clock_timing -type skew -clock sys_clk

# Report with details
report_clock_timing -type skew -clock sys_clk \
    -max_paths 20 -significant_digits 4

# Clock transition report
report_clock_timing -type transition -clock sys_clk

# Source latency
report_clock_timing -type source_latency -clock sys_clk

# All clock types
report_clock_timing -type skew -clock [get_clocks *]
report_clock_timing -type latency -clock [get_clocks *]

# Output
report_clock_timing -type skew > reports/clock_skew.rpt
report_clock_timing -type latency > reports/clock_latency.rpt
```

### report_clocks

```tcl
# Report all clocks
report_clocks

# Report with attributes
report_clocks -verbose

# Report specific clock
report_clocks sys_clk

# Report generated clocks
report_clocks -generated_clocks

# Report clock relationships
report_clocks -relationships
```

### report_clock_tree_summary (if CTS data available)

```tcl
# Clock tree summary
report_clock_tree_summary

# Detailed clock tree
report_clock_tree_summary -clock sys_clk
```

---

## ECO Commands

### ecoDesign

Tempus-driven timing ECO optimization.

```tcl
# Setup ECO
ecoDesign -setup

# Hold ECO
ecoDesign -hold

# Setup and hold ECO
ecoDesign -setup -hold

# ECO with specific views
ecoDesign -setup -hold -view {av_wc_func av_bc_func}

# Post-route ECO
ecoDesign -postRoute -setup -hold
```

### ecoAddRepeater

Inserts buffer/inverter for timing fix.

```tcl
# Add buffer
ecoAddRepeater -term [get_pins reg/D] -cell BUFX4

# Add inverter pair
ecoAddRepeater -term [get_pins reg/D] -cell INVX2 -numInverters 2

# Add buffer at specific location
ecoAddRepeater -term [get_pins reg/D] -cell BUFX8 -loc {500.0 300.0}
```

### ecoChangeCell

Changes cell type (upsizing/downsizing/Vt swap).

```tcl
# Upsize cell
ecoChangeCell -inst u_buf1 -cell BUFX8

# Downsize cell
ecoChangeCell -inst u_buf1 -cell BUFX2

# Vt swap (HVT to SVT)
ecoChangeCell -inst u_reg1 -cell DFFSVTX1

# Vt swap (SVT to LVT)
ecoChangeCell -inst u_reg1 -cell DFFLVTX1

# Batch ECO changes
foreach inst [get_cells -filter "ref_name == BUFX2"] {
    ecoChangeCell -inst $inst -cell BUFX4
}
```

### ecoSwapCell

Swaps cell to a different type.

```tcl
# Swap cell
ecoSwapCell -inst u_and1 -cell AND2X4

# Swap to equivalent cell from different library
ecoSwapCell -inst u_and1 -cell svt_lib/AND2X4
```

### ECO Analysis

```tcl
# Report ECO changes
report_eco_changes

# Verify ECO
verify_eco

# Write ECO changes
write_eco -output output/eco_changes.tcl

# Undo ECO
undo_eco
```

---

## Concurrent Multi-Corner Analysis

### Multi-Corner Setup

```tcl
# Define all corners
create_analysis_view -name setup_wc_func -constraint_mode cm_func -delay_corner dc_wc
create_analysis_view -name setup_wc_test -constraint_mode cm_test -delay_corner dc_wc
create_analysis_view -name hold_bc_func -constraint_mode cm_func -delay_corner dc_bc
create_analysis_view -name hold_tc_func -constraint_mode cm_func -delay_corner dc_tc

# Activate all for concurrent analysis
set_analysis_view \
    -setup {setup_wc_func setup_wc_test} \
    -hold {hold_bc_func hold_tc_func}
```

### Multi-Corner Timing

```tcl
# Report timing across all active setup views
report_timing -max_paths 50 -view {setup_wc_func setup_wc_test}

# Report timing across all active hold views
report_timing -early -max_paths 50 -view {hold_bc_func hold_tc_func}

# Worst-across-corners report
report_timing -max_paths 50 ;# reports worst across all active views

# Per-view reports
foreach view {setup_wc_func setup_wc_test} {
    report_timing -view $view -max_paths 50 > reports/timing_${view}.rpt
}
```

### Multi-Corner with SPEF

```tcl
# Read SPEF per corner
read_spef -rc_corner rc_wc /extraction/top_wc.spef
read_spef -rc_corner rc_bc /extraction/top_bc.spef
read_spef -rc_corner rc_tc /extraction/top_tc.spef
```

---

## Timing Debug Commands

### Detailed Path Analysis

```tcl
# Detailed single path
report_timing -max_paths 1 -path_type full_clock \
    -net -cap -tran -input_pins -derate -cppr \
    -significant_digits 4

# Analyze why path is slow
report_timing -through [get_pins slow_cell/Y] -path_type full_clock \
    -net -cap -tran

# Check for high-fanout nets
report_timing -max_paths 1 -net -cap
```

### Slack Histogram

```tcl
# Generate slack histogram
report_timing -max_paths 10000 -path_type endpoint -collection > /dev/null
report_histogram -type slack

# Setup slack histogram
report_histogram -type slack -check_type setup

# Hold slack histogram
report_histogram -type slack -check_type hold
```

### Path Group Analysis

```tcl
# Path group summary
report_path_group

# Timing by path group
report_timing -group reg2reg -max_paths 50
report_timing -group in2reg -max_paths 50
report_timing -group reg2out -max_paths 50
report_timing -group in2out -max_paths 50

# Create custom path group for debug
group_path -name debug_path -from [get_cells suspicious_reg*] \
    -to [get_cells target_reg*]
report_timing -group debug_path -max_paths 20
```

### Bottleneck Analysis

```tcl
# Find timing bottlenecks
report_bottleneck -max_paths 1000 -cost_type path_count

# Bottleneck on cells
report_bottleneck -max_paths 500 -cost_type cell_delay

# Bottleneck on nets
report_bottleneck -max_paths 500 -cost_type net_delay
```

### Why Analysis

```tcl
# Why is a path failing?
# Step 1: Get the failing path
report_timing -to [get_pins failing_reg/D] -max_paths 1 \
    -path_type full_clock -net -cap -tran -derate

# Step 2: Check if it's clock skew
report_clock_timing -type skew -to [get_pins failing_reg/CK]

# Step 3: Check if it's data path delay
report_timing -to [get_pins failing_reg/D] -path_type full \
    -net -cap -tran

# Step 4: Check constraints
report_constraint -to [get_pins failing_reg/D]

# Step 5: Check CPPR
report_timing -to [get_pins failing_reg/D] -cppr \
    -path_type full_clock
```

### Cross-Probing with Innovus

```tcl
# Write timing data for Innovus
write_timing_data -format innovus output/timing_data

# Write slack data
write_slack_data output/slack_data

# Write path-based timing
write_timing_path -max_paths 100 output/timing_paths
```

---

## Advanced Timing Features

### POCV (Parametric OCV)

```tcl
# Enable POCV
setAnalysisMode -analysisType onChipVariation

# Read POCV/LVF data
read_lib -socv /libs/stdcells/ss_lvf.lib

# Set POCV sigma
set_db timing_pocv_sigma 3.0

# Report with POCV
report_timing -derate -max_paths 10
```

### Clock Reconvergence Pessimism Removal (CRPR/CPPR)

```tcl
# Enable CPPR
setAnalysisMode -cppr both

# CPPR for setup only
setAnalysisMode -cppr setup

# CPPR for hold only
setAnalysisMode -cppr hold

# Report CPPR credit
report_timing -cppr -path_type full_clock -max_paths 10
```

### Useful Skew Analysis

```tcl
# Report useful skew opportunities
report_useful_skew

# Report with details
report_useful_skew -detail -max_paths 50

# Useful skew optimization targets
report_useful_skew -optimization_target
```

### GBA vs PBA

```tcl
# Graph-Based Analysis (default, faster)
setAnalysisMode -analysisType onChipVariation

# Path-Based Analysis (more accurate, slower)
report_timing -max_paths 10 -pba_mode path
report_timing -max_paths 10 -pba_mode exhaustive

# PBA for specific paths
report_timing -to [get_pins critical_reg/D] -pba_mode exhaustive

# GBA then PBA refinement
report_timing -max_paths 100 ;# GBA
report_timing -max_paths 100 -max_slack 0.050 -pba_mode path ;# PBA on near-critical
```

### Timing Exceptions Debug

```tcl
# Report all timing exceptions
report_timing_exceptions

# Report false paths
report_timing_exceptions -type false_path

# Report multicycle paths
report_timing_exceptions -type multicycle_path

# Report disabled timing arcs
report_timing_exceptions -type disable_timing

# Check if exception applies to a path
report_timing -to [get_pins reg/D] -exceptions

# Find unused exceptions
check_timing -type {unconstrained_endpoints}
```

### Min Pulse Width Analysis

```tcl
# Report min pulse width violations
report_constraint -min_pulse_width -all_violators

# Detailed pulse width
report_min_pulse_width -max_violations 100

# Per clock
report_min_pulse_width -clock sys_clk
```

---

## Output and Export Commands

### write_sdf

```tcl
# Write SDF
write_sdf output/top_chip.sdf

# Write SDF for specific view
write_sdf -view av_wc_func output/top_chip_wc.sdf
write_sdf -view av_bc_func output/top_chip_bc.sdf

# Write with options
write_sdf -significant_digits 4 -timescale ns \
    -recompute_parallel_arcs output/top_chip.sdf

# Write interconnect-only SDF
write_sdf -interconn output/top_chip_interconn.sdf

# Write cell-only SDF
write_sdf -cell_only output/top_chip_cell.sdf
```

### write_sdc

```tcl
# Write SDC
write_sdc output/top_chip_signoff.sdc

# Write SDC for specific mode
write_sdc -mode cm_func output/top_chip_func.sdc
```

### write_timing_data

```tcl
# Write timing data for downstream tools
write_timing_data output/timing_data

# Write timing abstract
write_timing_abstract -lib_name top_chip_lib output/top_chip.lib
```

### Session Save/Restore

```tcl
# Save Tempus session
write_db output/tempus_db

# Restore session
read_db output/tempus_db

# Save snapshot
write_snapshot -outdir output/snapshot -tag signoff
```

---

## Utility and Session Commands

### Multi-Threading

```tcl
# Set number of CPUs
set_multi_cpu_usage -local_cpu 8

# Distributed processing
set_multi_cpu_usage -remote_host 4

# Check CPU usage
report_multi_cpu_usage
```

### Memory Management

```tcl
# Report memory usage
report_resource -memory

# Set memory limit
set_resource -memory_limit 64G
```

### Logging

```tcl
# Set log file
set_log_file output/tempus.log

# Verbose logging
set_db information_level 7
```

### Object Queries

```tcl
# Get objects
get_cells -hierarchical *
get_cells -hierarchical -filter {is_sequential == true}
get_cells -hierarchical -filter {ref_name =~ BUF*}

get_nets -hierarchical *
get_nets -hierarchical -filter {fanout > 100}

get_ports *
get_ports -filter {direction == in}

get_pins -hierarchical */D
get_pins -hierarchical */CK

get_clocks *
get_clocks -filter {period < 2.0}

# Count objects
llength [get_cells -hierarchical *]
llength [get_cells -hierarchical -filter {is_sequential == true}]
```

---

## Quick Reference: Complete Tempus Signoff Flow

```tcl
#============================================================
# Tempus Signoff STA Script -- Production Template
#============================================================

# Library and design read
read_lib {ss_0p75v_125c.lib sram_ss.lib io_ss.lib}
read_lib {ff_0p95v_m40c.lib sram_ff.lib io_ff.lib}
read_verilog /output/innovus/top_chip.v
set_top_module top_chip
read_def /output/innovus/top_chip.def

# MMMC setup
source scripts/mmmc.tcl

# Read parasitics per corner
read_spef -rc_corner rc_wc /extraction/top_chip_wc.spef
read_spef -rc_corner rc_bc /extraction/top_chip_bc.spef

# Set active views
set_analysis_view -setup {av_wc_func av_wc_test} -hold {av_bc_func}

# Analysis mode
setAnalysisMode -analysisType onChipVariation
setAnalysisMode -cppr both

# SI mode
set_si_mode -analysisType aae
set_si_mode -enableTimingWindow true

# OCV derates
set_timing_derate -early 0.95 -cell_delay -clock
set_timing_derate -late 1.05 -cell_delay -clock
set_timing_derate -early 0.93 -cell_delay -data
set_timing_derate -late 1.07 -cell_delay -data

# Check constraints
check_timing -verbose > reports/check_timing.rpt

# Setup timing
report_timing -late -max_paths 200 -path_type full_clock \
    -net -cap -tran -derate -si \
    > reports/setup_timing.rpt

report_timing -late -max_paths 200 -path_type endpoint \
    > reports/setup_endpoints.rpt

# Hold timing
report_timing -early -max_paths 200 -path_type full_clock \
    -net -cap -tran -derate -si \
    > reports/hold_timing.rpt

# Constraint violations
report_constraint -all_violators > reports/violations.rpt
report_constraint -max_transition -all_violators > reports/max_tran.rpt
report_constraint -max_capacitance -all_violators > reports/max_cap.rpt
report_constraint -min_pulse_width -all_violators > reports/min_pw.rpt

# Clock timing
report_clock_timing -type skew > reports/clock_skew.rpt
report_clock_timing -type latency > reports/clock_latency.rpt

# Noise
report_noise -above_threshold > reports/noise.rpt

# Summary
report_timing -summary > reports/timing_summary.rpt

# Write SDF for gate-level simulation
write_sdf -view av_wc_func output/top_chip_wc.sdf
write_sdf -view av_bc_func output/top_chip_bc.sdf

# Save session
write_db output/tempus_signoff_db

puts "Tempus signoff complete."
```

---

## Tempus Command Index (Alphabetical)

| Command | Category | Description |
|---------|----------|-------------|
| `check_timing` | Validation | Check constraint completeness |
| `create_analysis_view` | MMMC | Create analysis view |
| `create_constraint_mode` | MMMC | Create constraint mode |
| `create_delay_corner` | MMMC | Create delay corner |
| `create_library_set` | MMMC | Create library set |
| `create_rc_corner` | MMMC | Create RC corner |
| `ecoAddRepeater` | ECO | Add buffer for timing ECO |
| `ecoChangeCell` | ECO | Swap cell for ECO |
| `ecoDesign` | ECO | Automated timing ECO |
| `ecoSwapCell` | ECO | Swap cell type |
| `get_cells` | Query | Get cell objects |
| `get_clocks` | Query | Get clock objects |
| `get_nets` | Query | Get net objects |
| `get_pins` | Query | Get pin objects |
| `get_ports` | Query | Get port objects |
| `group_path` | Constraints | Create path group |
| `read_aocv` | Import | Read AOCV tables |
| `read_def` | Import | Read DEF file |
| `read_lib` | Import | Read Liberty library |
| `read_sdc` | Import | Read SDC constraints |
| `read_socv` | Import | Read SOCV/LVF data |
| `read_spef` | Import | Read SPEF parasitics |
| `read_verilog` | Import | Read gate-level netlist |
| `report_bottleneck` | Debug | Report timing bottlenecks |
| `report_clock_timing` | Report | Report clock timing |
| `report_clocks` | Report | Report clock definitions |
| `report_constraint` | Report | Report constraint violations |
| `report_histogram` | Report | Generate slack histogram |
| `report_min_pulse_width` | Report | Report min pulse width |
| `report_noise` | SI | Report noise violations |
| `report_path_group` | Report | Report path groups |
| `report_timing` | Report | Report timing paths |
| `report_timing_derate` | Report | Report OCV derates |
| `report_timing_exceptions` | Debug | Report timing exceptions |
| `report_useful_skew` | Report | Report useful skew |
| `set_analysis_view` | MMMC | Set active analysis views |
| `set_si_mode` | SI | Configure SI analysis |
| `set_timing_derate` | Analysis | Set OCV derates |
| `set_timing_derate_model` | Analysis | Set derate model type |
| `setAnalysisMode` | Analysis | Configure analysis mode |
| `write_db` | Export | Save session database |
| `write_sdc` | Export | Write SDC constraints |
| `write_sdf` | Export | Write SDF delays |
| `write_timing_data` | Export | Write timing data |
