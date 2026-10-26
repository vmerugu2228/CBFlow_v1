# Synopsys SpyGlass RTL Analysis — Complete Command Reference

## Table of Contents

1. [Overview and Architecture](#overview-and-architecture)
2. [SpyGlass Setup and Invocation](#spyglass-setup-and-invocation)
3. [Design Read-In](#design-read-in)
4. [RTL Lint](#rtl-lint)
5. [CDC (Clock Domain Crossing)](#cdc)
6. [RDC (Reset Domain Crossing)](#rdc)
7. [DFT Analysis](#dft-analysis)
8. [Power Analysis (SpyGlass Power)](#power-analysis)
9. [Constraints and SDC Verification](#constraints-verification)
10. [Custom Rules and Policies](#custom-rules-and-policies)
11. [Waivers](#waivers)
12. [Reporting and Debug](#reporting-and-debug)
13. [Common Flows and Recipes](#common-flows-and-recipes)

---

## 1. Overview and Architecture

### SpyGlass Products

| Product | Purpose |
|---------|---------|
| SpyGlass Lint | RTL quality and coding style checks |
| SpyGlass CDC | Clock domain crossing verification |
| SpyGlass RDC | Reset domain crossing verification |
| SpyGlass DFT | Design-for-test analysis |
| SpyGlass Power | Low-power intent verification |
| SpyGlass Constraints | SDC/timing constraint verification |
| SpyGlass LP | UPF/CPF low-power verification |

### SpyGlass Analysis Flow

```
RTL + Libraries + Constraints
        |
   Design Read-In (read_file, read_lib)
        |
   Goal Selection (current_goal)
        |
   Analysis (run_goal)
        |
   Results (reports, violations, waveforms)
```

### Invocation

```bash
# GUI mode
spyglass -gui

# Batch mode
spyglass -batch -project design.prj

# Command-line with Tcl script
spyglass -tcl -source run_spyglass.tcl

# Shell mode (interactive)
spyglass -shell

# With specific methodology
spyglass -batch -project design.prj -methodology SpyGlass_CDC

# License check
spyglass -check_license
```

---

## 2. SpyGlass Setup and Invocation

### 2.1 Project File (.prj)

```tcl
# ========================================
# SpyGlass Project File (.prj)
# ========================================

# Project name
set_option projectname "my_design"

# Design top module
set_option top "top_chip"

# Technology library
read_file -type gateslevel /path/to/std_cells.lib

# RTL files
read_file -type verilog {
    /path/to/rtl/package.sv
    /path/to/rtl/defines.vh
    /path/to/rtl/top_chip.v
    /path/to/rtl/core.v
    /path/to/rtl/memory_ctrl.v
}

# Or using file list
read_file -type sourcelist /path/to/filelist.f

# Include directories
set_option incdir {/path/to/includes /path/to/common}

# Define macros
set_option define {SIMULATION SPYGLASS_CHECK}

# SDC constraints
read_file -type sdc /path/to/design.sdc

# UPF power intent
read_file -type upf /path/to/design.upf

# Waiver file
read_file -type waiver /path/to/waivers.swl

# Goal selection
current_goal lint/lint_rtl
run_goal

current_goal cdc/cdc_verify_struct
run_goal
```

### 2.2 Environment Setup

```bash
# SpyGlass environment
export SPYGLASS_HOME=/opt/synopsys/spyglass/2024.06
export PATH=$SPYGLASS_HOME/bin:$PATH
export SNPSLMD_LICENSE_FILE=27000@license_server

# SpyGlass methodology path
export SPYGLASS_METHODOLOGY_PATH=$SPYGLASS_HOME/GuideWare

# Working directory
export SPYGLASS_WORK_DIR=./spyglass_work
```

---

## 3. Design Read-In

### 3.1 read_file

```tcl
# ========================================
# File Reading Commands
# ========================================

# Verilog files
read_file -type verilog design.v
read_file -type verilog {file1.v file2.v file3.v}

# SystemVerilog
read_file -type systemverilog design.sv
read_file -type sv design.sv                    ;# shorthand

# VHDL
read_file -type vhdl design.vhd

# Mixed language
read_file -type verilog top.v
read_file -type vhdl subblock.vhd

# Gate-level netlist
read_file -type gateslevel netlist.v

# Liberty library
read_file -type lib /path/to/std_cells.lib
read_file -type lib {fast.lib slow.lib}

# LEF
read_file -type lef /path/to/tech.lef /path/to/cells.lef

# SDC constraints
read_file -type sdc design.sdc
read_file -type sdc {func_mode.sdc test_mode.sdc}

# UPF power intent
read_file -type upf design.upf

# CPF power intent
read_file -type cpf design.cpf

# SGDC (SpyGlass Design Constraints)
read_file -type sgdc design.sgdc

# File list
read_file -type sourcelist filelist.f

# Waiver file
read_file -type waiver waivers.swl
read_file -type awl waivers.awl      ;# auto-waiver

# SDF
read_file -type sdf design.sdf
```

### 3.2 read_lib

```tcl
# ========================================
# Library Reading
# ========================================

# Read Liberty library
read_lib -type lib /path/to/library.lib

# Read multiple libraries
read_lib -type lib {
    /path/to/fast_ff_0p99v_m40c.lib
    /path/to/slow_ss_0p81v_125c.lib
    /path/to/typical_tt_0p90v_25c.lib
}

# Read technology LEF
read_lib -type lef /path/to/tech.lef

# Cell LEF
read_lib -type lef /path/to/cells.lef
```

### 3.3 Design Configuration

```tcl
# ========================================
# Design Options
# ========================================

# Set top module
set_option top "top_chip"

# Include directories
set_option incdir {./includes ./src/common}

# Define macros
set_option define {SYNTHESIS SPYGLASS_FLOW}
set_option define {WIDTH=32 DEPTH=1024}

# Undefine
set_option undefine {DEBUG_MODE}

# Language options
set_option language_mode mixed          ;# mixed Verilog/VHDL
set_option language_mode verilog2001    ;# Verilog 2001
set_option language_mode systemverilog  ;# SystemVerilog

# Library search
set_option y {/path/to/lib1 /path/to/lib2}     ;# -y equivalent
set_option libext {.v .sv .vhd}                  ;# +libext+

# Black box handling
set_option allowblackbox yes           ;# allow unresolved modules
set_option blackbox {mem_wrapper analog_block}

# Parameters
set_option param {top_chip.WIDTH=16 top_chip.DEPTH=512}

# Enable SystemVerilog assertions
set_option enableSVA yes

# Handle generate blocks
set_option handlealiases yes

# Handle `ifdef
set_option handlemacro yes
```

---

## 4. RTL Lint

### 4.1 Lint Goals

```tcl
# ========================================
# RTL Lint Goals
# ========================================

# Basic lint
current_goal lint/lint_rtl
run_goal

# Synthesis lint (checks synthesizability)
current_goal lint/lint_rtl_enhanced
run_goal

# Abstract lint
current_goal lint/lint_abstract
run_goal

# Full lint (all checks)
current_goal lint/lint_turbo
run_goal

# Lint with specific policy
current_goal lint/lint_rtl -policy {STARC Madhyam}
run_goal
```

### 4.2 Common Lint Rules

```tcl
# ========================================
# Key Lint Rule Categories
# ========================================

# Naming conventions
# W123 - Signal name too short
# W124 - Signal name too long
# W125 - Signal naming convention violation

# Coding style
# W110 - Missing default in case statement
# W116 - Inferred latch (incomplete if/case)
# W120 - Combinational loop detected
# W156 - Unused signal
# W164 - Undriven signal/port
# W175 - Unused input port
# W182 - Multi-driven signal
# W192 - Width mismatch in assignment
# W213 - Always block sensitivity list incomplete
# W224 - Multi-bit expression in boolean context
# W240 - Input port not connected
# W241 - Output port not connected

# Synthesis issues
# W263 - Non-synthesizable construct
# W287 - Blocking assignment in sequential block
# W289 - Non-blocking assignment in combinational block
# W336 - Truncation in assignment
# W362 - Bit-select out of range
# W402 - Inferred memory/register
# W415 - Signal used before assignment
# W446 - Arithmetic overflow possible

# Clock/Reset
# W391 - Clock used as data
# W392 - Data used as clock
# W395 - Reset used as data
# W396 - Data used as reset

# Safety
# W480 - Tristate in core logic
# W484 - Potential race condition
```

### 4.3 Lint Options

```tcl
# ========================================
# Lint Configuration
# ========================================

# Enable/disable specific rules
set_option enable_rule {W116 W120 W156}
set_option disable_rule {W123 W124}

# Set rule severity
set_option severity {W116 error}
set_option severity {W156 warning}
set_option severity {W175 info}

# Rule parameters
set_rule_parameter W192 -max_width_ratio 2    ;# width mismatch threshold

# Policy-based configuration
set_option policy STARC                        ;# STARC coding guidelines
set_option policy MADHYAM                      ;# Madhyam rules
set_option policy RMM                          ;# Reuse Methodology Manual
set_option policy custom_policy                ;# custom policy

# File-level control
set_option enable_rule_for_file {W116} design.v
set_option disable_rule_for_file {W156} testbench.sv

# Module-level control
set_option enable_rule_for_module {W120} core_module
set_option disable_rule_for_module {W156} debug_module
```

### 4.4 Lint Pragmas (In-Source)

```verilog
// Disable SpyGlass check for a line
assign data = 32'b0; // spyglass disable W164

// Disable for a block
// spyglass disable_block W116
always @(*) begin
    if (sel) out = a;
    // no else — intentional latch
end
// spyglass enable_block W116

// Disable for specific reason
// spyglass disable W156 -msg "Intentionally unused"

// Coverage exclusion
// spyglass disable_block SYNTH_1
// synthesis translate_off
`ifdef SIMULATION
    // simulation-only code
`endif
// synthesis translate_on
// spyglass enable_block SYNTH_1
```

---

## 5. CDC (Clock Domain Crossing)

### 5.1 CDC Goals

```tcl
# ========================================
# CDC Analysis Goals
# ========================================

# Structural CDC analysis
current_goal cdc/cdc_verify_struct
run_goal

# CDC with functional analysis
current_goal cdc/cdc_verify
run_goal

# CDC setup (generates SGDC template)
current_goal cdc/cdc_setup
run_goal

# CDC abstract (for IP blocks)
current_goal cdc/cdc_abstract
run_goal

# CDC at gate level
current_goal cdc/cdc_verify_struct_gate
run_goal
```

### 5.2 CDC Setup (SGDC Constraints)

```tcl
# ========================================
# SpyGlass Design Constraints (SGDC) for CDC
# ========================================

# Clock definitions (supplement SDC)
clock -name clk_a -period 10 -edge {0 5} [get_ports clk_a]
clock -name clk_b -period 8 -edge {0 4} [get_ports clk_b]

# Clock domain definitions
clock_domain -name CD_A -clock clk_a
clock_domain -name CD_B -clock clk_b

# Clock relationship
clock_relationship -from clk_a -to clk_b -type async    ;# asynchronous
clock_relationship -from clk_a -to clk_b -type sync     ;# synchronous
clock_relationship -from clk_a -to clk_b -type ratio 2:1 ;# ratio

# ========================================
# CDC Synchronizer Specification
# ========================================

# Specify synchronizer cells
cdc_synchronizer -type flip_flop -depth 2 \
    -cell "SYNC_FF2"

# Multi-flop synchronizer
cdc_synchronizer -type multi_flop -depth 3 \
    -cell "SYNC_FF3"

# FIFO synchronizer
cdc_synchronizer -type fifo \
    -cell "ASYNC_FIFO"

# Handshake synchronizer
cdc_synchronizer -type handshake \
    -cell "HANDSHAKE_SYNC"

# MUX-based synchronizer
cdc_synchronizer -type mux_sync \
    -cell "MUX_SYNC"

# Gray code synchronizer
cdc_synchronizer -type gray_code \
    -cell "GRAY_SYNC"

# ========================================
# CDC Exceptions
# ========================================

# Quasi-static signal (rarely changes, synchronized by protocol)
cdc_false_path -from [get_cells config_reg*] -to CD_B \
    -comment "Configuration register, quasi-static"

# Known safe crossing
cdc_false_path -from [get_pins u_sync/d] -to [get_pins u_sync/q]

# Abstract synchronizer (treat as synchronized)
abstract -type cdc_sync -instance u_custom_sync \
    -from_clock clk_a -to_clock clk_b
```

### 5.3 CDC Analysis Commands

```tcl
# ========================================
# CDC Analysis and Reporting
# ========================================

# Set CDC options
set_option cdc yes
set_option cdc_report_all_crossings yes

# CDC report options
set_option cdc_report_reconvergence yes
set_option cdc_report_glitch yes
set_option cdc_report_data_stability yes

# Report CDC crossings
report_cdc
report_cdc -summary
report_cdc -detail
report_cdc -type all

# Report specific crossing types
report_cdc -type unsynchronized        ;# no synchronizer
report_cdc -type single_flop           ;# only 1 sync flop
report_cdc -type multi_bit             ;# multi-bit crossing
report_cdc -type reconvergent          ;# reconvergent paths
report_cdc -type glitch                ;# glitch-prone
report_cdc -type combo_logic           ;# combinational before sync

# Report by domain
report_cdc -from CD_A -to CD_B
report_cdc -crossing_type async

# ========================================
# CDC Rule Categories
# ========================================

# Ac_cdc01 - No synchronizer on CDC path
# Ac_cdc02 - Single-flop synchronizer (need 2+)
# Ac_cdc03 - Combinational logic between source and synchronizer
# Ac_cdc04 - Multi-bit signal crossing without proper sync
# Ac_cdc05 - Reconvergent CDC paths
# Ac_cdc06 - Glitch on CDC path
# Ac_cdc07 - FIFO pointer crossing issue
# Ac_cdc08 - Reset crossing domain
# Ac_cdc09 - Data stability violation
# Ac_cdc10 - Gray code violation
# Ac_cdc11 - MUX-recirculation on CDC path

# ========================================
# CDC Schematic
# ========================================

# Generate CDC crossing schematic
report_cdc -schematic -output cdc_crossing.html
```

### 5.4 CDC Functional Verification

```tcl
# ========================================
# CDC Functional (Formal) Verification
# ========================================

# Enable CDC formal
current_goal cdc/cdc_verify
set_option cdc_formal yes

# Formal CDC options
set_option cdc_formal_depth 20         ;# bounded model checking depth
set_option cdc_formal_timeout 3600     ;# timeout in seconds

# Data stability checks (formal)
set_option cdc_data_stability_check yes

# Grey code checks
set_option cdc_gray_code_check yes

# FIFO overflow/underflow
set_option cdc_fifo_check yes

# Run formal CDC
run_goal

# Report formal results
report_cdc -formal_results
```

### 5.5 CDC Metastability Injection

```tcl
# ========================================
# Metastability Analysis
# ========================================

# Enable metastability injection
set_option cdc_metastability_inject yes

# Injection options
set_option cdc_ms_inject_depth 2       ;# injection depth
set_option cdc_ms_inject_random yes    ;# random injection

# Generate testbench for metastability simulation
write_cdc_testbench -output cdc_tb.sv -type metastability
```

---

## 6. RDC (Reset Domain Crossing)

### 6.1 RDC Goals

```tcl
# ========================================
# RDC Analysis
# ========================================

# RDC structural analysis
current_goal rdc/rdc_verify_struct
run_goal

# RDC setup
current_goal rdc/rdc_setup
run_goal

# Full RDC verification
current_goal rdc/rdc_verify
run_goal
```

### 6.2 RDC Constraints

```tcl
# ========================================
# RDC Setup (SGDC)
# ========================================

# Reset definitions
reset -name rst_a -active low [get_ports rst_a_n]
reset -name rst_b -active low [get_ports rst_b_n]

# Reset domain definitions
reset_domain -name RD_A -reset rst_a
reset_domain -name RD_B -reset rst_b

# Reset relationship
reset_relationship -from rst_a -to rst_b -type async
reset_relationship -from rst_a -to rst_b -type ordered ;# rst_a deasserts before rst_b

# Reset synchronizer
rdc_synchronizer -type sync_deassert -cell "RST_SYNC"

# ========================================
# RDC Reporting
# ========================================

report_rdc
report_rdc -summary
report_rdc -detail
report_rdc -type unsynchronized
report_rdc -from RD_A -to RD_B
```

### 6.3 RDC Rules

```tcl
# Key RDC rules:
# Ar_rdc01 - Asynchronous reset crossing without synchronizer
# Ar_rdc02 - Reset glitch possible
# Ar_rdc03 - Reset deassertion order violation
# Ar_rdc04 - Reset used as data
# Ar_rdc05 - Missing reset on sequential element
# Ar_rdc06 - Reset tree imbalance
```

---

## 7. DFT Analysis

### 7.1 DFT Goals

```tcl
# ========================================
# DFT Analysis Goals
# ========================================

# DFT rule checking
current_goal dft/dft_check
run_goal

# Scan readiness
current_goal dft/dft_scan_ready
run_goal

# DFT testability
current_goal dft/dft_testability
run_goal
```

### 7.2 DFT Rules

```tcl
# ========================================
# DFT Analysis Commands
# ========================================

# Set DFT options
set_option dft yes
set_option dft_scan_style muxed_ff

# DFT clock definition
set_option dft_clock clk
set_option dft_scan_enable scan_en
set_option dft_test_mode test_mode

# Report DFT issues
report_dft
report_dft -summary
report_dft -detail

# Key DFT rules:
# DFTC_01 - Uncontrollable clock
# DFTC_02 - Uncontrollable reset
# DFTC_03 - Reconvergent clock/data path
# DFTC_04 - Gated clock without test control
# DFTC_05 - Combinational feedback loop
# DFTC_06 - Asynchronous set/reset without test control
# DFTC_07 - Tristate bus without test control
# DFTC_08 - Memory without BIST/bypass
# DFTC_09 - Non-scannable sequential element
# DFTC_10 - Potential bus contention during test

# Testability analysis
report_testability
report_testability -controllability
report_testability -observability
```

---

## 8. Power Analysis (SpyGlass Power)

### 8.1 Power Goals

```tcl
# ========================================
# Power Analysis Goals
# ========================================

# Power lint (UPF verification)
current_goal power/power_lint
run_goal

# Power verification
current_goal power/power_verify
run_goal

# Low-power structural check
current_goal power/power_check
run_goal

# Power estimation
current_goal power/power_estimate
run_goal
```

### 8.2 Power Intent Reading

```tcl
# ========================================
# Power Intent (UPF/CPF)
# ========================================

# Read UPF
read_file -type upf design.upf

# Read CPF
read_file -type cpf design.cpf

# Power-specific SGDC
read_file -type sgdc power_constraints.sgdc

# ========================================
# Power Domain Constraints
# ========================================

# Power domain specification (in SGDC)
power_domain -name PD_CORE -default
power_domain -name PD_IO -instances {u_io/*}
power_domain -name PD_USB -instances {u_usb/*}

# Supply definitions
supply -name VDD_CORE -voltage 0.9
supply -name VDD_IO -voltage 1.8
supply -name VSS -voltage 0.0

# Domain-supply mapping
power_domain_supply -domain PD_CORE -primary_power VDD_CORE -primary_ground VSS
power_domain_supply -domain PD_IO -primary_power VDD_IO -primary_ground VSS
```

### 8.3 Power Rules

```tcl
# Key power rules:
# PW_01 - Missing isolation cell
# PW_02 - Missing level shifter
# PW_03 - Missing retention cell
# PW_04 - Incorrect isolation polarity
# PW_05 - Power domain not connected
# PW_06 - Supply net not connected
# PW_07 - Missing power switch
# PW_08 - Incorrect power state table
# PW_09 - Missing always-on buffer
# PW_10 - Incorrect UPF syntax

# ========================================
# Power Reporting
# ========================================

report_power
report_power -summary
report_power -detail
report_power -domain PD_CORE
report_power -violations

# Power state reporting
report_power_states
report_power_states -detail

# Isolation reporting
report_isolation
report_isolation -detail

# Level shifter reporting
report_level_shifters
report_level_shifters -detail

# Retention reporting
report_retention
report_retention -detail
```

### 8.4 Power Estimation

```tcl
# ========================================
# Power Estimation
# ========================================

# Read activity file
read_file -type saif design.saif
read_file -type vcd design.vcd

# Set default toggle rates
set_option default_toggle_rate 0.1     ;# 10% toggle rate
set_option clock_toggle_rate 1.0       ;# clock at full rate

# Power estimation options
set_option power_estimation_mode rtl
set_option power_report_type detailed

# Generate power report
current_goal power/power_estimate
run_goal

# Report
report_power_estimate
report_power_estimate -by_module
report_power_estimate -by_type          ;# dynamic, leakage, etc.
report_power_estimate -by_domain
```

---

## 9. Constraints and SDC Verification

### 9.1 Constraint Goals

```tcl
# ========================================
# Constraint Verification Goals
# ========================================

# SDC verification
current_goal constraint/sdc_check
run_goal

# Constraint consistency
current_goal constraint/constraint_check
run_goal

# Timing constraint analysis
current_goal constraint/timing_check
run_goal
```

### 9.2 SDC Verification Commands

```tcl
# ========================================
# SDC Analysis
# ========================================

# Read SDC
read_file -type sdc func_mode.sdc
read_file -type sdc test_mode.sdc

# Check SDC syntax
check_sdc
check_sdc -detail

# Verify SDC against design
verify_sdc
verify_sdc -report sdc_verify.rpt

# Report SDC issues
report_sdc_issues
report_sdc_issues -type error
report_sdc_issues -type warning

# Key SDC rules:
# SDC_01 - Clock not reaching flop
# SDC_02 - Conflicting constraints
# SDC_03 - Missing clock definition
# SDC_04 - Over-constrained path
# SDC_05 - Under-constrained path
# SDC_06 - False path removes valid timing
# SDC_07 - Multicycle path incorrect
# SDC_08 - Input/output delay missing
# SDC_09 - Generated clock definition error
# SDC_10 - Clock group specification error

# ========================================
# Constraint Completeness
# ========================================

report_constraint_completeness
report_constraint_completeness -unconstrained_paths
report_constraint_completeness -unconstrained_ports
```

---

## 10. Custom Rules and Policies

### 10.1 Custom Rule Definition

```tcl
# ========================================
# Custom SpyGlass Rules
# ========================================

# Custom rule file (.spyrule)
define_rule CUSTOM_01 {
    -message "Clock signal must have 'clk' prefix"
    -severity error
    -description "All clock signals should be named with 'clk_' prefix"
    -check {
        foreach clock [get_clocks] {
            if {![regexp {^clk_} [get_property name $clock]]} {
                report_violation -rule CUSTOM_01 \
                    -object $clock \
                    -message "Clock [get_property name $clock] missing 'clk_' prefix"
            }
        }
    }
}

define_rule CUSTOM_02 {
    -message "Reset signal must be active-low"
    -severity warning
    -check {
        foreach reset [get_resets] {
            if {[get_property active_level $reset] != "low"} {
                report_violation -rule CUSTOM_02 \
                    -object $reset \
                    -message "Reset [get_property name $reset] should be active-low"
            }
        }
    }
}
```

### 10.2 Policy Configuration

```tcl
# ========================================
# Policy Files
# ========================================

# Create custom policy
create_policy MY_COMPANY_RULES {
    # Include standard rules
    include_goal lint/lint_rtl

    # Enable specific rules
    enable_rule {W116 W120 W156 W164 CUSTOM_01 CUSTOM_02}

    # Disable rules
    disable_rule {W123 W124}

    # Set severities
    set_severity {W116 error}
    set_severity {W156 warning}
    set_severity {W175 info}

    # Rule parameters
    set_rule_parameter W192 -max_width 32
}

# Apply policy
current_goal lint/lint_rtl -policy MY_COMPANY_RULES
run_goal
```

### 10.3 GuideWare Methodology

```tcl
# ========================================
# GuideWare Built-in Methodologies
# ========================================

# Available methodologies
# SpyGlass_CDC     - Clock domain crossing
# SpyGlass_RDC     - Reset domain crossing
# SpyGlass_DFT     - Design for test
# SpyGlass_Power   - Power analysis
# SpyGlass_Constraints - Constraint verification
# STARC            - STARC design guidelines
# Madhyam          - Madhyam coding guidelines

# Use GuideWare methodology
set_option methodology SpyGlass_CDC

# List available goals
list_goals

# List available rules
list_rules -goal lint/lint_rtl
list_rules -methodology SpyGlass_CDC
```

---

## 11. Waivers

### 11.1 Waiver File Format (.swl)

```tcl
# ========================================
# SpyGlass Waiver Language (.swl)
# ========================================

# Waiver by rule and instance
waiver -rule W116 -instance "u_debug/*" \
    -reason "Debug logic intentionally uses latches" \
    -owner "vmerugu" \
    -date "2024-01-15"

# Waiver by rule and signal
waiver -rule W156 -signal "unused_port" \
    -reason "Port reserved for future use" \
    -owner "vmerugu"

# Waiver by rule and file
waiver -rule W164 -file "legacy_block.v" \
    -reason "Legacy code, will not be modified"

# Waiver by rule and module
waiver -rule W182 -module "bus_mux" \
    -reason "Multi-driven by design (bus architecture)"

# CDC waiver
waiver -rule Ac_cdc01 -from "clk_a" -to "clk_b" \
    -signal "config_reg*" \
    -reason "Quasi-static configuration, protocol ensures safe crossing"

# Wildcard waiver
waiver -rule W175 -instance "u_pad_ring/*" \
    -reason "Pad ring has intentionally unconnected ports"

# Conditional waiver
waiver -rule W116 -module "test_wrapper" \
    -condition "ifdef GATE_SIM" \
    -reason "Gate-level specific latch inference"

# Temporary waiver (with expiration)
waiver -rule W120 -instance "u_pll/*" \
    -reason "PLL feedback loop under investigation" \
    -expires "2024-06-30"
```

### 11.2 Auto-Waiver Generation

```tcl
# ========================================
# Auto-Waiver
# ========================================

# Generate waiver template from violations
write_waiver_template -output waiver_template.swl

# Apply waivers
read_file -type waiver waivers.swl

# Report waived violations
report_waivers
report_waivers -detail
report_waivers -unused          ;# waivers that match no violations
report_waivers -expired         ;# expired waivers
```

---

## 12. Reporting and Debug

### 12.1 Report Commands

```tcl
# ========================================
# Reporting
# ========================================

# Summary report
report_summary
report_summary -goal lint/lint_rtl

# Detailed violation report
report_violations
report_violations -detail
report_violations -rule W116
report_violations -severity error
report_violations -module core_logic
report_violations -instance "u_core/*"

# Report by category
report_violations -category LINT
report_violations -category CDC
report_violations -category RDC
report_violations -category DFT
report_violations -category POWER

# Export reports
write_report -output lint_report.txt -goal lint/lint_rtl
write_report -output cdc_report.txt -goal cdc/cdc_verify_struct
write_report -format html -output report.html
write_report -format csv -output report.csv
write_report -format xml -output report.xml

# Statistics
report_statistics
report_statistics -by_rule
report_statistics -by_severity
report_statistics -by_module
```

### 12.2 Schematic and Debug Views

```tcl
# ========================================
# Debug Commands
# ========================================

# Generate schematic
write_schematic -output schematic.html -type crossing
write_schematic -output schematic.html -type cone -signal data_out

# Trace path
trace_path -from clk_a_domain/reg1/D -to clk_b_domain/sync_ff/D
trace_path -from [get_pins u_src/q] -to [get_pins u_dst/d]

# Cone analysis
analyze_cone -signal data_out -depth 10
analyze_cone -signal data_out -type fanin
analyze_cone -signal data_out -type fanout

# Cross-reference
xref -signal data_bus[0] -type driver
xref -signal data_bus[0] -type load

# Design browser
browse_design -module core_logic
browse_design -instance u_core
```

### 12.3 SpyGlass GUI Debug

```tcl
# ========================================
# GUI-Specific Commands
# ========================================

# Open SpyGlass GUI with results
spyglass -gui -project design.prj -goal lint/lint_rtl

# In GUI:
# - Violation browser (tree view)
# - Schematic view (crossing diagram for CDC)
# - Source view (highlighted violations)
# - Cone view (signal fan-in/fan-out)
# - Waiver editor
# - Report generator

# Load results in GUI
open_project design.prj
load_goal_results lint/lint_rtl
```

---

## 13. Common Flows and Recipes

### 13.1 Complete Lint Flow

```tcl
#!/usr/bin/env spyglass -tcl -source

# ========================================
# Complete RTL Lint Flow
# ========================================

# Project setup
set_option projectname "my_design_lint"
set_option top "top_chip"

# Read libraries
read_file -type lib /foundry/libs/std_cells.lib

# Read RTL
read_file -type sourcelist rtl_filelist.f

# Include directories
set_option incdir {./src/includes ./src/common}
set_option define {SYNTHESIS}

# Read SDC
read_file -type sdc design.sdc

# Read waivers
read_file -type waiver project_waivers.swl

# ========================================
# Run Lint Goals
# ========================================

# Basic lint
current_goal lint/lint_rtl
run_goal
write_report -output reports/lint_rtl.txt
write_report -format html -output reports/lint_rtl.html

# Enhanced lint
current_goal lint/lint_rtl_enhanced
run_goal
write_report -output reports/lint_enhanced.txt

# Report summary
report_summary
report_statistics -by_severity

puts "Lint analysis complete"
save_project
exit
```

### 13.2 Complete CDC Flow

```tcl
#!/usr/bin/env spyglass -tcl -source

# ========================================
# Complete CDC Verification Flow
# ========================================

# Project setup
set_option projectname "my_design_cdc"
set_option top "top_chip"

# Read libraries
read_file -type lib /foundry/libs/std_cells.lib

# Read RTL
read_file -type sourcelist rtl_filelist.f
set_option incdir {./src/includes}
set_option define {SYNTHESIS}

# Read SDC
read_file -type sdc design.sdc

# Read CDC constraints
read_file -type sgdc cdc_constraints.sgdc

# Read waivers
read_file -type waiver cdc_waivers.swl

# ========================================
# CDC Analysis Steps
# ========================================

# Step 1: CDC Setup (generates constraint template)
current_goal cdc/cdc_setup
run_goal
write_report -output reports/cdc_setup.txt

# Step 2: Structural CDC verification
current_goal cdc/cdc_verify_struct
run_goal
write_report -output reports/cdc_struct.txt
write_report -format html -output reports/cdc_struct.html

# Step 3: CDC with formal (optional, requires license)
# current_goal cdc/cdc_verify
# run_goal
# write_report -output reports/cdc_formal.txt

# ========================================
# CDC Reports
# ========================================

report_cdc -summary
report_cdc -type unsynchronized
report_cdc -type multi_bit
report_cdc -type reconvergent

# Generate CDC crossing schematic
write_schematic -output reports/cdc_crossings.html -type crossing

report_summary
puts "CDC analysis complete"
save_project
exit
```

### 13.3 Complete Power Verification Flow

```tcl
#!/usr/bin/env spyglass -tcl -source

# ========================================
# Power Verification Flow
# ========================================

# Project setup
set_option projectname "my_design_power"
set_option top "top_chip"

# Read design
read_file -type lib /foundry/libs/std_cells.lib
read_file -type sourcelist rtl_filelist.f
set_option incdir {./src/includes}

# Read power intent
read_file -type upf design.upf

# Read SDC
read_file -type sdc design.sdc

# ========================================
# Power Goals
# ========================================

# Power lint
current_goal power/power_lint
run_goal
write_report -output reports/power_lint.txt

# Power verification
current_goal power/power_verify
run_goal
write_report -output reports/power_verify.txt

# Reports
report_power -summary
report_isolation -detail
report_level_shifters -detail
report_retention -detail

report_summary
puts "Power verification complete"
save_project
exit
```

### 13.4 Batch Script for CI/CD

```bash
#!/bin/bash
# SpyGlass batch run for CI/CD

DESIGN_NAME="my_design"
SPYGLASS_DIR="./spyglass_results"

mkdir -p $SPYGLASS_DIR/reports

# Run SpyGlass
spyglass -batch \
    -tcl -source run_spyglass.tcl \
    -logfile $SPYGLASS_DIR/spyglass.log \
    2>&1 | tee $SPYGLASS_DIR/console.log

# Check for errors
LINT_ERRORS=$(grep -c "Error" $SPYGLASS_DIR/reports/lint_rtl.txt 2>/dev/null || echo 0)
CDC_ERRORS=$(grep -c "Error" $SPYGLASS_DIR/reports/cdc_struct.txt 2>/dev/null || echo 0)

echo "Lint errors: $LINT_ERRORS"
echo "CDC errors: $CDC_ERRORS"

if [ "$LINT_ERRORS" -gt 0 ] || [ "$CDC_ERRORS" -gt 0 ]; then
    echo "SPYGLASS FAILED"
    exit 1
else
    echo "SPYGLASS PASSED"
    exit 0
fi
```

### 13.5 Makefile Template

```makefile
# SpyGlass Makefile
SPYGLASS = spyglass
PRJ = design.prj
REPORTS = ./reports

.PHONY: lint cdc rdc power all clean

all: lint cdc rdc power

lint:
	$(SPYGLASS) -batch -project $(PRJ) \
		-goal lint/lint_rtl \
		-output_dir $(REPORTS)/lint

cdc:
	$(SPYGLASS) -batch -project $(PRJ) \
		-goal cdc/cdc_verify_struct \
		-output_dir $(REPORTS)/cdc

rdc:
	$(SPYGLASS) -batch -project $(PRJ) \
		-goal rdc/rdc_verify_struct \
		-output_dir $(REPORTS)/rdc

power:
	$(SPYGLASS) -batch -project $(PRJ) \
		-goal power/power_lint \
		-output_dir $(REPORTS)/power

clean:
	rm -rf $(REPORTS) spyglass_work *.prj.bak
```

---

*This document covers the Synopsys SpyGlass RTL analysis platform including lint, CDC, RDC, DFT, power verification, constraint checking, custom rules, waivers, and reporting. For foundry-specific rule decks and technology-specific configurations, consult your foundry methodology documentation.*
