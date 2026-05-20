# Siemens Tessent DFT — Complete Command Reference

## Table of Contents

1. [Overview and Architecture](#overview-and-architecture)
2. [Tessent Shell Basics](#tessent-shell-basics)
3. [Scan Architecture and Insertion](#scan-architecture-and-insertion)
4. [EDT (Embedded Deterministic Test) Compression](#edt-compression)
5. [ATPG (Automatic Test Pattern Generation)](#atpg)
6. [Fault Simulation](#fault-simulation)
7. [LogicBIST](#logicbist)
8. [MemoryBIST (MBIST)](#memorybist)
9. [Boundary Scan / JTAG (IEEE 1149.1)](#boundary-scan-jtag)
10. [Test Point Insertion](#test-point-insertion)
11. [Low-Power Test](#low-power-test)
12. [Pattern Porting and Format Conversion](#pattern-porting-and-format-conversion)
13. [Tessent Diagnosis and Yield Analysis](#tessent-diagnosis-and-yield-analysis)
14. [Tessent Safety (ISO 26262)](#tessent-safety)
15. [Common Flows and Recipes](#common-flows-and-recipes)

---

## 1. Overview and Architecture

### Tessent Tool Suite

| Tool | Purpose |
|------|---------|
| Tessent Shell | Unified DFT insertion, ATPG, diagnosis environment |
| Tessent Scan | Scan insertion and chain optimization |
| Tessent EDT | Embedded deterministic test (compression) |
| Tessent ATPG | Automatic test pattern generation |
| Tessent Diagnosis | Silicon diagnosis for yield learning |
| Tessent LogicBIST | Logic built-in self-test |
| Tessent MemoryBIST | Memory built-in self-test |
| Tessent BoundaryScan | IEEE 1149.1 JTAG |
| Tessent Safety | ISO 26262 functional safety DFT |
| Tessent SSN | Streaming Scan Network |
| Tessent Cell Library | Cell characterization for DFT |
| Tessent IJTAG | IEEE 1687 instrument access |

### Tessent Invocation

```bash
# Launch Tessent Shell (unified environment)
tessent -shell

# Launch specific tool modes
tessent -shell -mode scan_insert
tessent -shell -mode atpg
tessent -shell -mode diagnosis
tessent -shell -mode mbist

# Batch mode
tessent -shell -script script.tcl
tessent -shell -mode atpg -script atpg_run.tcl

# With log file
tessent -shell -logfile tessent.log -script script.tcl

# Version info
tessent -version
```

### Licensing

```bash
# License environment
export MGLS_LICENSE_FILE=27000@license_server
export LM_LICENSE_FILE=27000@license_server

# Check license availability
tessent -shell -check_license
```

---

## 2. Tessent Shell Basics

### 2.1 Design Loading

```tcl
# ========================================
# Design Read-In
# ========================================

# Read library
read_cell_library /path/to/library.atpg
# or
read_cell_library {lib1.atpg lib2.atpg lib3.atpg}

# Read Verilog netlist
read_verilog /path/to/design.v
# or for multiple files
read_verilog {design.v subblock1.v subblock2.v}

# Read VHDL
read_vhdl /path/to/design.vhd

# Set top-level module
set_current_design top_module

# Elaborate
elaborate top_module

# Set context for DFT
set_context dft -scan          ;# scan insertion mode
set_context dft -atpg          ;# ATPG mode
set_context dft -diagnosis     ;# diagnosis mode
set_context dft -mbist         ;# MBIST mode
```

### 2.2 Design Setup

```tcl
# ========================================
# Clock and Reset Definitions
# ========================================

# Define clocks
add_clocks 0 clk               ;# clock with default off-state 0
add_clocks 1 reset_n            ;# active-low reset, off-state 1

# Clock with period
add_clocks 0 clk -period 10ns

# Multiple clocks
add_clocks 0 {clk1 clk2}
add_clocks 1 {reset_n scan_reset_n}

# Define clock groups
set_procfile clock_groups {
    {clk1 clk2}                 ;# group 1
    {clk3}                      ;# group 2
}

# ========================================
# Pin Constraints
# ========================================

# Constrain inputs
add_input_constraints scan_en -c0      ;# constrained to 0 in functional
add_input_constraints scan_en -c1      ;# constrained to 1
add_input_constraints test_mode -c0

# Float pins
add_input_constraints float_pin -floating

# Output constraints
add_output_constraints obs_pin -observe

# ========================================
# Scan Configuration
# ========================================

# Define scan enable
set_scan_enable scan_en

# Define test mode
set_dft_signal test_mode -type test_mode

# Scan chain count
set_scan_configuration -chain_count 16

# Scan clock
set_scan_clock clk -period 100ns
```

### 2.3 System Mode Commands

```tcl
# ========================================
# System Mode Transitions
# ========================================

# Switch between modes
set_system_mode setup           ;# initial setup
set_system_mode analysis        ;# DRC/analysis
set_system_mode insertion       ;# DFT insertion
set_system_mode atpg            ;# ATPG mode

# Check current mode
report_system_mode

# Design flow
# setup -> analysis -> insertion (for scan insert)
# setup -> analysis -> atpg (for pattern generation)
```

### 2.4 Reporting Commands

```tcl
# General reports
report_clocks
report_input_constraints
report_output_constraints
report_scan_configuration
report_scan_chains
report_scan_cells
report_dft_violations         ;# DFT DRC violations
report_statistics             ;# design statistics
report_cell_models            ;# cell library models

# Detailed reports
report_scan_chains -detail
report_dft_violations -detail -limit 100
report_statistics -verbose
```

---

## 3. Scan Architecture and Insertion

### 3.1 Scan Configuration

```tcl
# ========================================
# Scan Chain Configuration
# ========================================

# Number of scan chains
set_scan_configuration -chain_count 32

# Chain length balancing
set_scan_configuration -balance_chain_length on

# Scan routing order
set_scan_configuration -routing_order physical  ;# or logical
set_scan_configuration -routing_order physical -placement_file placement.def

# Chain naming
set_scan_configuration -chain_prefix "scan_ch"

# Scan style
set_scan_configuration -scan_style multiplexed_flip_flop  ;# default
set_scan_configuration -scan_style lssd                    ;# level-sensitive
set_scan_configuration -scan_style clocked_scan

# Clock mixing
set_scan_configuration -clock_mixing mix_clocks    ;# allow different clocks in chain
set_scan_configuration -clock_mixing no_mix        ;# same clock per chain
set_scan_configuration -clock_mixing mix_edges     ;# mix pos/neg edge

# Lockup latches
set_scan_configuration -lockup_latch required      ;# insert lockup latches
set_scan_configuration -lockup_latch optional
set_scan_configuration -lockup_latch none

# Scan data routing
set_scan_configuration -scan_data_in_side left     ;# or right
set_scan_configuration -scan_data_out_side right
```

### 3.2 Scan Cell Selection

```tcl
# ========================================
# Scan Cell Configuration
# ========================================

# Mark cells as scannable
set_scan_type scan_ff -include {DFF* SDFF*}
set_scan_type non_scan -exclude {latch* ICG*}

# Replace non-scan cells with scan equivalents
set_scan_replacement on
set_scan_replacement_options -mapping_file scan_map.txt

# Mapping file format:
# non_scan_cell  scan_cell
# DFFX1          SDFFX1
# DFFX2          SDFFX2

# Exclude specific instances from scan
add_nonscan_instances {u_ram/* u_analog/*}

# Set scan cell type
set_scan_cell_type -type mux_scan {SDFF*}
set_scan_cell_type -type clocked_scan {CSFF*}
```

### 3.3 DFT DRC (Design Rule Check)

```tcl
# ========================================
# DFT DRC Analysis
# ========================================

# Run DFT DRC
set_system_mode analysis

# Check DFT rules
check_design_rules

# Report violations
report_dft_violations
report_dft_violations -type all
report_dft_violations -type clock
report_dft_violations -type reset
report_dft_violations -type scan
report_dft_violations -type constraint

# Violation types:
# C1 - Clock not controlled
# C2 - Clock feeds data input
# C3 - Gated clock
# R1 - Reset not controlled
# R2 - Asynchronous set/reset
# S1 - Scan chain rule violation
# S2 - Scan cell cannot be identified

# Fix DFT violations
set_dft_signal clk_gate_en -type clock_gate_enable
add_input_constraints async_reset -c1  ;# tie off async reset

# Waive violations
add_dft_violation_waiver -type C3 -instance "u_clk_gate/ICG*" \
    -reason "Clock gate handled by OCC"
```

### 3.4 Scan Insertion

```tcl
# ========================================
# Scan Chain Insertion
# ========================================

# Enter insertion mode
set_system_mode insertion

# Insert scan chains
insert_scan

# Or with specific options
insert_scan -chain_count 32 \
    -balance on \
    -lockup_latch required

# Write out scan-inserted netlist
write_verilog /path/to/scan_inserted.v
write_verilog /path/to/scan_inserted.v -replace_scan_cells

# Write scan chain definition file (for ATPG)
write_scan_chain_definition /path/to/scan_def.txt

# Write test protocol
write_test_protocol /path/to/test_protocol.spf

# Reports after insertion
report_scan_chains
report_scan_chains -detail
report_scan_cells -summary
report_statistics
```

### 3.5 Scan Chain Ordering (Physical-Aware)

```tcl
# ========================================
# Physical-Aware Scan Ordering
# ========================================

# Read DEF for physical info
read_def /path/to/placement.def

# Physical-aware scan ordering
set_scan_configuration -routing_order physical

# Or specify placement constraints
set_scan_physical_options \
    -placement_file placement.def \
    -max_wire_length 500

# Reorder existing chains
reorder_scan_chains -method physical

# Write reordered chains
write_scan_chain_definition /path/to/reordered_chains.txt
```

---

## 4. EDT (Embedded Deterministic Test) Compression

### 4.1 EDT Architecture

```tcl
# ========================================
# EDT Configuration
# ========================================

# Enable EDT compression
set_edt_configuration on

# EDT channel configuration
set_edt_configuration -channels 8          ;# number of scan channels
set_edt_configuration -ip_channels 4       ;# input channels
set_edt_configuration -op_channels 4       ;# output channels

# EDT options
set_edt_configuration -compression_ratio 100x    ;# target compression
set_edt_configuration -compactor_type xor_network ;# or misr
set_edt_configuration -decompressor_type ring     ;# or xor_network

# Masking
set_edt_configuration -masking dynamic     ;# dynamic masking for X handling
set_edt_configuration -masking static      ;# static masking

# EDT pins
set_edt_pins edt_clock -type clock
set_edt_pins edt_update -type update
set_edt_pins edt_bypass -type bypass
set_edt_pins edt_channel_in[0:3] -type channel_in
set_edt_pins edt_channel_out[0:3] -type channel_out
```

### 4.2 EDT Insertion

```tcl
# ========================================
# EDT Logic Insertion
# ========================================

# Enter insertion mode
set_system_mode insertion

# Insert EDT logic (with scan)
insert_edt

# EDT with specific options
insert_edt -channels 8 \
    -scan_chain_count 64 \
    -compression_ratio 100

# Write EDT-inserted netlist
write_verilog /path/to/edt_design.v

# Write EDT configuration
write_edt_configuration /path/to/edt_config.txt

# Write test protocol for EDT
write_test_protocol /path/to/edt_protocol.spf

# Report EDT details
report_edt_configuration
report_edt_chains
report_edt_statistics
```

### 4.3 EDT Advanced Features

```tcl
# ========================================
# Multi-Mode EDT
# ========================================

# Define multiple test modes
set_edt_configuration -mode mission_mode
set_edt_configuration -mode bist_mode

# Per-mode configuration
set_edt_configuration -mode mission_mode -channels 4
set_edt_configuration -mode bist_mode -channels 8

# ========================================
# EDT Bandwidth Management
# ========================================

# Set ATE bandwidth
set_edt_configuration -ate_bandwidth 400MHz

# Channel sharing
set_edt_configuration -channel_sharing on

# Pipeline stages
set_edt_configuration -pipeline_stages 2

# ========================================
# Low-Pin-Count EDT
# ========================================

# Minimal pin count configuration
set_edt_configuration -ip_channels 1
set_edt_configuration -op_channels 1
set_edt_configuration -serial_mode on
```

---

## 5. ATPG (Automatic Test Pattern Generation)

### 5.1 ATPG Setup

```tcl
# ========================================
# ATPG Configuration
# ========================================

# Read design (scan-inserted)
read_cell_library /path/to/library.atpg
read_verilog /path/to/scan_inserted.v
set_current_design top_module

# Read test protocol
read_test_protocol /path/to/test_protocol.spf

# Set ATPG mode
set_system_mode atpg

# Define fault model
set_fault_type stuck          ;# stuck-at (default)
set_fault_type transition     ;# transition delay
set_fault_type path_delay     ;# path delay
set_fault_type bridging       ;# bridging faults
set_fault_type iddq           ;# IDDQ testing
set_fault_type cell_aware     ;# cell-aware (defect-based)

# ========================================
# Clock Definitions for ATPG
# ========================================
add_clocks 0 clk
add_clocks 1 reset_n

# Scan enable
set_scan_enable scan_en

# Test mode pin
add_input_constraints test_mode -c1

# ========================================
# ATPG Options
# ========================================

# Pattern type
set_pattern_type -type combinational    ;# basic scan
set_pattern_type -type sequential       ;# multi-cycle
set_pattern_type -type clock_sequential ;# launch-on-capture

# For transition faults
set_pattern_type -type launch_on_shift    ;# LOS
set_pattern_type -type launch_on_capture  ;# LOC (broadside)

# Abort limit
set_atpg_options -abort_limit 100       ;# max backtracks per fault

# Pattern count limit
set_atpg_options -pattern_count_limit 10000

# Merge level
set_atpg_options -merge_level high      ;# aggressive pattern merging

# Coverage target
set_atpg_options -coverage_target 99.0  ;# target fault coverage %

# X handling
set_atpg_options -x_handling fill_random ;# fill Xs randomly
set_atpg_options -x_handling fill_zero   ;# fill with 0
set_atpg_options -x_handling fill_one    ;# fill with 1
set_atpg_options -x_handling fill_adjacent ;# copy adjacent values
```

### 5.2 Running ATPG

```tcl
# ========================================
# ATPG Execution
# ========================================

# Add all faults
add_faults -all

# Or add specific fault types
add_faults -all -fault_type stuck_at
add_faults -all -fault_type transition

# Add faults for specific instances
add_faults -instance "u_core/*"

# Create patterns
create_patterns

# Or step-by-step
create_patterns -step deterministic   ;# deterministic ATPG
create_patterns -step random           ;# random pattern fill
create_patterns -step top_off          ;# top-off hard faults

# ========================================
# ATPG Reports
# ========================================

# Fault coverage report
report_faults -summary
report_faults -class AU                ;# undetected faults
report_faults -class UD                ;# undetectable faults
report_faults -class AN                ;# ATPG untestable
report_faults -class BL                ;# blocked faults
report_faults -class RE                ;# redundant faults

# Pattern statistics
report_patterns -summary
report_patterns -detail

# Coverage report
report_statistics
report_statistics -detail

# Fault classes:
# DT - Detected
# PT - Possibly Detected
# UD - Undetectable
# AU - ATPG Untestable
# AN - Uncontrolled
# BL - Blocked
# RE - Redundant
# UU - Unused
# TI - Tied
# EF - Effectively detected
```

### 5.3 Writing Patterns

```tcl
# ========================================
# Pattern Output
# ========================================

# Write patterns in various formats
write_patterns /path/to/patterns.stil -format stil
write_patterns /path/to/patterns.wgl -format wgl
write_patterns /path/to/patterns.v -format verilog
write_patterns /path/to/patterns.bin -format binary
write_patterns /path/to/patterns.ascii -format ascii

# WGL (Waveform Generation Language) - common for ATE
write_patterns patterns.wgl -format wgl \
    -ate_config /path/to/ate_config.txt

# STIL (Standard Test Interface Language - IEEE 1450)
write_patterns patterns.stil -format stil \
    -timing /path/to/timing.stil

# Verilog testbench for simulation
write_patterns patterns_tb.v -format verilog \
    -simulation_mode on

# Per-mode patterns
write_patterns stuck_at_patterns.stil -format stil \
    -fault_type stuck_at
write_patterns transition_patterns.stil -format stil \
    -fault_type transition

# Compressed patterns (for EDT)
write_patterns compressed.stil -format stil \
    -compressed on
```

### 5.4 Advanced ATPG Features

```tcl
# ========================================
# Cell-Aware ATPG
# ========================================

# Read cell-aware fault models
read_cell_library /path/to/cell_aware.atpg

# Enable cell-aware ATPG
set_fault_type cell_aware

# Add cell-aware faults
add_faults -all -fault_type cell_aware

# Create cell-aware patterns (on top of stuck-at)
create_patterns -step cell_aware

# ========================================
# N-Detect ATPG
# ========================================

# Generate N patterns per fault (for screening)
set_atpg_options -n_detect 3    ;# 3 detections per fault

# ========================================
# Timing-Aware ATPG
# ========================================

# Read SDF for timing
read_sdf /path/to/design.sdf

# Timing-aware transition ATPG
set_fault_type transition
set_pattern_type -type launch_on_capture
set_atpg_options -timing_aware on

# At-speed test frequency
set_atpg_options -test_frequency 500MHz

# ========================================
# Multi-Load Patterns
# ========================================
set_atpg_options -multi_load on
set_atpg_options -multi_load_count 4

# ========================================
# Incremental ATPG
# ========================================

# Read existing patterns
read_patterns /path/to/existing_patterns.stil

# Run incremental ATPG for uncovered faults
add_faults -all
run_fault_simulation              ;# simulate existing patterns
create_patterns                   ;# generate patterns for remaining faults
```

---

## 6. Fault Simulation

### 6.1 Fault Simulation Commands

```tcl
# ========================================
# Fault Simulation
# ========================================

# Read design and patterns
read_cell_library /path/to/library.atpg
read_verilog /path/to/design.v
set_current_design top_module
read_test_protocol /path/to/protocol.spf

# Enter ATPG mode
set_system_mode atpg

# Add faults
add_faults -all

# Read patterns to simulate
read_patterns /path/to/patterns.stil

# Run fault simulation
run_fault_simulation

# Report results
report_faults -summary
report_statistics

# ========================================
# Fault Simulation Options
# ========================================

# Simulation type
set_fault_simulation_options -type parallel     ;# parallel fault sim
set_fault_simulation_options -type single        ;# single fault sim

# Fault dropping
set_fault_simulation_options -fault_dropping on  ;# drop detected faults

# Pattern limit
set_fault_simulation_options -pattern_limit 1000

# Coverage calculation
set_fault_simulation_options -coverage_formula standard
# standard = DT / (total - UD - TI - UU - BL)
```

### 6.2 Coverage Analysis

```tcl
# ========================================
# Coverage Reports
# ========================================

# Overall coverage
report_statistics

# Per-module coverage
report_faults -summary -by_module

# Per-fault-class breakdown
report_faults -summary -by_class

# Export coverage data
write_faults /path/to/fault_list.txt -class ALL
write_faults /path/to/undetected.txt -class AU

# Coverage by instance hierarchy
report_faults -summary -hierarchical

# ========================================
# Testability Analysis
# ========================================

# SCOAP testability measures
report_testability -scoap
report_testability -scoap -by_instance

# Controllability/observability
report_testability -controllability
report_testability -observability
```

---

## 7. LogicBIST

### 7.1 LogicBIST Configuration

```tcl
# ========================================
# LogicBIST Setup
# ========================================

# Set context for LogicBIST
set_context dft -logic_bist

# Read design
read_cell_library /path/to/library.atpg
read_verilog /path/to/design.v
set_current_design top_module

# ========================================
# LBIST Architecture
# ========================================

# LFSR (Linear Feedback Shift Register) configuration
set_logic_bist_configuration -lfsr_length 32
set_logic_bist_configuration -lfsr_polynomial "x^32 + x^7 + x^5 + x^3 + x^2 + x + 1"

# MISR (Multiple Input Signature Register)
set_logic_bist_configuration -misr_length 32

# Pattern count
set_logic_bist_configuration -pattern_count 10000

# Shift count (patterns per session)
set_logic_bist_configuration -shift_count 1000

# Clock configuration
set_logic_bist_configuration -clock clk
set_logic_bist_configuration -bist_clock bist_clk

# ========================================
# LBIST Controller
# ========================================

# Controller type
set_logic_bist_configuration -controller_type standard

# BIST enable pin
set_logic_bist_pins bist_en -type enable
set_logic_bist_pins bist_done -type done
set_logic_bist_pins bist_fail -type fail

# Signature output
set_logic_bist_pins signature_out[31:0] -type signature

# ========================================
# LBIST Insertion
# ========================================

set_system_mode insertion
insert_logic_bist

# Write LBIST-inserted design
write_verilog /path/to/lbist_design.v

# Report
report_logic_bist_configuration
report_logic_bist_statistics
```

### 7.2 LogicBIST Pattern Analysis

```tcl
# ========================================
# LBIST Pattern Quality Analysis
# ========================================

# Simulate LBIST patterns
set_system_mode atpg
add_faults -all

# Run LBIST simulation
run_logic_bist_simulation -pattern_count 10000

# Coverage report
report_faults -summary
report_statistics

# Weighted random pattern optimization
set_logic_bist_configuration -weighted_random on

# Weight calculation
compute_logic_bist_weights

# Write weights
write_logic_bist_weights /path/to/weights.txt
```

---

## 8. MemoryBIST (MBIST)

### 8.1 MBIST Configuration

```tcl
# ========================================
# MemoryBIST Setup
# ========================================

# Set context
set_context dft -memory_bist

# Read design
read_cell_library /path/to/library.atpg
read_verilog /path/to/design.v
set_current_design top_module

# ========================================
# Memory Instance Identification
# ========================================

# Automatic memory detection
identify_memories

# Manual memory specification
add_memory -instance "u_sram_0" \
    -type sram \
    -width 32 \
    -depth 1024 \
    -address_port "addr[9:0]" \
    -data_in_port "din[31:0]" \
    -data_out_port "dout[31:0]" \
    -write_enable "wen" \
    -chip_select "cs" \
    -clock "clk"

# Memory groups (tested together)
add_memory_group -name "sram_group1" \
    -instances {u_sram_0 u_sram_1 u_sram_2}

# ========================================
# MBIST Controller Configuration
# ========================================

# Controller type
set_mbist_configuration -controller_type standard

# Algorithm selection
set_mbist_configuration -algorithm march_c_minus    ;# default
# Available algorithms:
# march_c_minus    - March C- (13N operations)
# march_c_plus     - March C+ (10N)
# march_lr         - March LR (14N, address decoder faults)
# march_b          - March B
# march_ss         - March SS (self-scaling)
# checkerboard     - Checkerboard pattern
# walking_ones     - Walking 1/0
# galloping        - Galloping pattern
# custom           - User-defined

# Test data backgrounds
set_mbist_configuration -data_backgrounds {0x00 0xFF 0x55 0xAA}

# Retention test
set_mbist_configuration -retention_test on
set_mbist_configuration -retention_time 100ms

# ========================================
# MBIST Pins
# ========================================

set_mbist_pins mbist_en -type enable
set_mbist_pins mbist_done -type done
set_mbist_pins mbist_fail -type fail
set_mbist_pins mbist_clk -type clock
set_mbist_pins mbist_rst -type reset
set_mbist_pins mbist_diag[7:0] -type diagnostic
set_mbist_pins mbist_mode[1:0] -type mode

# ========================================
# MBIST Controller Options
# ========================================

# Shared controller for multiple memories
set_mbist_configuration -shared_controller on
set_mbist_configuration -max_memories_per_controller 16

# Pipeline stages
set_mbist_configuration -pipeline on

# Repair interface (for redundancy)
set_mbist_configuration -repair_enable on
set_mbist_configuration -repair_type soft    ;# or hard, efuse
```

### 8.2 MBIST Insertion

```tcl
# ========================================
# MBIST Logic Insertion
# ========================================

set_system_mode insertion

# Insert MBIST
insert_memory_bist

# Write MBIST-inserted design
write_verilog /path/to/mbist_design.v

# Write MBIST controller RTL
write_mbist_controller /path/to/mbist_ctrl.v

# Write memory wrapper
write_memory_wrapper /path/to/mem_wrapper.v

# Reports
report_mbist_configuration
report_mbist_statistics
report_memories
report_memory_groups
```

### 8.3 MBIST Advanced Features

```tcl
# ========================================
# Memory Repair
# ========================================

# Configure repair
set_mbist_repair_configuration \
    -type row_column \
    -spare_rows 2 \
    -spare_columns 2

# Repair analysis
analyze_memory_repair

# ========================================
# Multi-Port Memory
# ========================================

add_memory -instance "u_dp_sram" \
    -type dual_port_sram \
    -width 64 \
    -depth 512 \
    -port_a_address "addr_a[8:0]" \
    -port_a_data_in "din_a[63:0]" \
    -port_a_data_out "dout_a[63:0]" \
    -port_a_write_enable "wen_a" \
    -port_a_clock "clk_a" \
    -port_b_address "addr_b[8:0]" \
    -port_b_data_out "dout_b[63:0]" \
    -port_b_clock "clk_b"

# ========================================
# Custom March Algorithm
# ========================================

set_mbist_configuration -algorithm custom
define_march_algorithm {
    {UP   write 0}                    ;# M0: write 0 ascending
    {UP   read 0 write 1}            ;# M1: read 0, write 1 ascending
    {UP   read 1 write 0}            ;# M2: read 1, write 0 ascending
    {DOWN read 0 write 1}            ;# M3: read 0, write 1 descending
    {DOWN read 1 write 0}            ;# M4: read 1, write 0 descending
    {ANY  read 0}                    ;# M5: read 0 any order
}
```

---

## 9. Boundary Scan / JTAG (IEEE 1149.1)

### 9.1 Boundary Scan Configuration

```tcl
# ========================================
# JTAG / Boundary Scan Setup
# ========================================

# Set context
set_context dft -boundary_scan

# Read design
read_cell_library /path/to/library.atpg
read_verilog /path/to/design.v
set_current_design top_module

# ========================================
# TAP Controller Configuration
# ========================================

# Standard JTAG pins
set_boundary_scan_pins tck -type tck
set_boundary_scan_pins tms -type tms
set_boundary_scan_pins tdi -type tdi
set_boundary_scan_pins tdo -type tdo
set_boundary_scan_pins trst_n -type trst      ;# optional

# TAP controller options
set_boundary_scan_configuration -tap_type standard    ;# IEEE 1149.1
set_boundary_scan_configuration -idcode 32'h12345678
set_boundary_scan_configuration -ir_length 8

# ========================================
# Boundary Scan Cell Configuration
# ========================================

# Add boundary cells to all I/O
set_boundary_scan_configuration -all_ios on

# Exclude specific pins
add_boundary_scan_exclusion {analog_pin power_pin}

# Cell type selection
set_boundary_scan_cell_type -input BC_1     ;# input cell type
set_boundary_scan_cell_type -output BC_2    ;# output cell type
set_boundary_scan_cell_type -bidir BC_7     ;# bidirectional

# ========================================
# Instruction Register
# ========================================

# Standard instructions (automatically included)
# EXTEST    - external test (boundary scan)
# SAMPLE    - sample/preload
# BYPASS    - bypass register
# IDCODE    - identification

# Custom instructions
add_boundary_scan_instruction -name INTEST -opcode 8'h0C
add_boundary_scan_instruction -name USERDR -opcode 8'h20
add_boundary_scan_instruction -name SCAN_MODE -opcode 8'h30
```

### 9.2 Boundary Scan Insertion

```tcl
# ========================================
# Insert Boundary Scan Logic
# ========================================

set_system_mode insertion

# Insert boundary scan
insert_boundary_scan

# Write design
write_verilog /path/to/jtag_design.v

# Write BSDL (Boundary Scan Description Language)
write_bsdl /path/to/design.bsdl

# Write SVF (Serial Vector Format) for board test
write_svf /path/to/board_test.svf

# Reports
report_boundary_scan_configuration
report_boundary_scan_cells
report_boundary_scan_instructions
```

### 9.3 IEEE 1687 (IJTAG) Integration

```tcl
# ========================================
# IJTAG (Tessent SSN - Streaming Scan Network)
# ========================================

# Configure IJTAG network
set_ijtag_configuration -network_type ssn

# Add instruments
add_ijtag_instrument -name "scan_ctrl" -type scan_controller
add_ijtag_instrument -name "mbist_ctrl" -type mbist_controller
add_ijtag_instrument -name "occ" -type on_chip_clock

# Network topology
set_ijtag_network_topology -daisy_chain    ;# or star, tree

# Access policy
set_ijtag_access_policy -instrument "mbist_ctrl" \
    -access_level production

# Insert IJTAG network
insert_ijtag_network

# Write ICL (Instrument Connectivity Language)
write_icl /path/to/design.icl

# Write PDL (Procedural Description Language)
write_pdl /path/to/design.pdl
```

---

## 10. Test Point Insertion

### 10.1 Test Point Configuration

```tcl
# ========================================
# Test Point Insertion
# ========================================

# Set context
set_context dft -scan

# Read design
read_cell_library /path/to/library.atpg
read_verilog /path/to/design.v
set_current_design top_module

# ========================================
# Test Point Types
# ========================================

# Control test points (improve controllability)
set_test_point_configuration -type control
set_test_point_configuration -control_method or_gate    ;# OR with scan FF
set_test_point_configuration -control_method and_gate   ;# AND with scan FF
set_test_point_configuration -control_method mux        ;# MUX with scan FF

# Observe test points (improve observability)
set_test_point_configuration -type observe
set_test_point_configuration -observe_method or_xor     ;# XOR into scan chain

# Both
set_test_point_configuration -type both

# ========================================
# Test Point Budget
# ========================================

# Maximum test points
set_test_point_configuration -max_points 100

# Area budget (percentage overhead)
set_test_point_configuration -area_budget 2.0     ;# 2% area overhead

# ========================================
# Test Point Analysis and Insertion
# ========================================

# Analyze testability (identify candidates)
analyze_test_points

# Report candidates
report_test_point_candidates

# Insert test points
set_system_mode insertion
insert_test_points

# Report inserted test points
report_test_points

# Write design
write_verilog /path/to/tp_design.v
```

### 10.2 Advanced Test Point Strategies

```tcl
# ========================================
# Targeted Test Points
# ========================================

# Focus on specific fault classes
set_test_point_configuration -target_faults AU     ;# ATPG untestable
set_test_point_configuration -target_faults BL     ;# blocked

# Region-specific test points
add_test_point_region -instance "u_crypto/*" -max_points 50

# Exclude regions
add_test_point_exclusion -instance "u_analog/*"

# ========================================
# Test Point Sharing
# ========================================

# Share control signals
set_test_point_configuration -shared_control on

# Maximum fan-in per control point
set_test_point_configuration -max_fan_in 8
```

---

## 11. Low-Power Test

### 11.1 Power-Aware ATPG

```tcl
# ========================================
# Low-Power Test Configuration
# ========================================

# Read UPF power intent
read_power_intent /path/to/design.upf

# ========================================
# Shift Power Reduction
# ========================================

# Limit switching during shift
set_low_power_options -shift_power_limit 0.3    ;# 30% toggle rate

# Low-power shift techniques
set_low_power_options -shift_method adjacent_fill  ;# fill with adjacent values
set_low_power_options -shift_method low_toggle      ;# minimize toggles

# ========================================
# Capture Power Reduction
# ========================================

# Limit switching during capture
set_low_power_options -capture_power_limit 0.2

# Launch-on-shift for lower power
set_pattern_type -type launch_on_shift

# Multi-cycle capture
set_low_power_options -multi_cycle_capture on

# ========================================
# Power Domain Awareness
# ========================================

# Define power domains
add_power_domain -name "PD_CORE" -instances "u_core/*" -supply VDD
add_power_domain -name "PD_IO" -instances "u_io/*" -supply VDDQ
add_power_domain -name "PD_ALWAYS_ON" -instances "u_aon/*" -supply VDD_AON

# Power domain test order
set_low_power_options -domain_test_order {PD_ALWAYS_ON PD_CORE PD_IO}

# Isolation during test
set_low_power_options -isolation_during_test on

# ========================================
# Power-Aware Pattern Generation
# ========================================

# Run power-aware ATPG
create_patterns -low_power on

# Report power estimates
report_power_estimates
report_power_estimates -per_pattern
report_power_estimates -per_domain
```

---

## 12. Pattern Porting and Format Conversion

### 12.1 Pattern Format Conversion

```tcl
# ========================================
# Pattern Format Conversion
# ========================================

# Read patterns in one format
read_patterns /path/to/patterns.stil

# Write in another format
write_patterns /path/to/patterns.wgl -format wgl
write_patterns /path/to/patterns.v -format verilog

# Supported formats:
# STIL (Standard Test Interface Language) - IEEE 1450
# WGL (Waveform Generation Language)
# Verilog - for simulation
# Binary - compressed binary
# ASCII - human-readable
# VCD - Value Change Dump
# STIL_2005 - STIL 2005 version

# ========================================
# ATE-Specific Formats
# ========================================

# Advantest
write_patterns patterns.atp -format advantest -ate_model 93000

# Teradyne
write_patterns patterns.pat -format teradyne -ate_model ultraFLEX

# For specific ATE configuration
write_patterns patterns.stil -format stil \
    -ate_configuration /path/to/ate_config.txt

# ========================================
# Pattern Timing
# ========================================

# Specify timing for pattern conversion
set_pattern_timing -period 20ns
set_pattern_timing -strobe_offset 15ns
set_pattern_timing -drive_offset 2ns

# Timing file
write_timing /path/to/timing.stil
```

### 12.2 Pattern Porting Between Designs

```tcl
# ========================================
# Pattern Porting (ECO Re-targeting)
# ========================================

# Read original design and patterns
read_cell_library /path/to/library.atpg
read_verilog /path/to/original_design.v
set_current_design original_top

read_patterns /path/to/original_patterns.stil

# Read modified design
read_verilog /path/to/eco_design.v -design eco_top

# Port patterns
port_patterns -from_design original_top \
    -to_design eco_top \
    -output_patterns /path/to/ported_patterns.stil

# Validate ported patterns
run_fault_simulation

# Report porting results
report_pattern_porting_results
```

---

## 13. Tessent Diagnosis and Yield Analysis

### 13.1 Diagnosis Setup

```tcl
# ========================================
# Silicon Diagnosis
# ========================================

# Set context
set_context dft -diagnosis

# Read design
read_cell_library /path/to/library.atpg
read_verilog /path/to/design.v
set_current_design top_module
read_test_protocol /path/to/protocol.spf

# Enter diagnosis mode
set_system_mode atpg

# ========================================
# Read Fail Data
# ========================================

# Read ATE fail log
read_fail_data /path/to/fail_log.txt -format ascii
read_fail_data /path/to/fail_log.datalog -format datalog

# Specify failing patterns
set_diagnosis_options -patterns /path/to/patterns.stil

# ========================================
# Run Diagnosis
# ========================================

# Run diagnosis
run_diagnosis

# Diagnosis options
set_diagnosis_options -max_suspects 10       ;# max suspect faults
set_diagnosis_options -resolution_limit 95   ;# min resolution %
set_diagnosis_options -fault_model stuck     ;# or transition, bridging
set_diagnosis_options -include_bridging on

# ========================================
# Diagnosis Reports
# ========================================

report_diagnosis_results
report_diagnosis_results -detail
report_diagnosis_results -suspects

# Write diagnosis results
write_diagnosis_results /path/to/diag_results.txt

# Export for yield analysis
write_diagnosis_results /path/to/diag_results.xml -format xml
```

### 13.2 Yield Analysis

```tcl
# ========================================
# Yield Learning Flow
# ========================================

# Read multiple diagnosis results
read_diagnosis_results /path/to/lot1_diag.xml
read_diagnosis_results /path/to/lot2_diag.xml

# Statistical analysis
run_yield_analysis

# Pareto analysis of failure modes
report_yield_pareto
report_yield_pareto -by_defect_type
report_yield_pareto -by_location

# Correlation with process data
set_yield_analysis_options -process_data /path/to/process_data.csv

# Wafer map analysis
generate_wafer_map -output /path/to/wafer_map.html

# Trend analysis
report_yield_trend -lots {LOT001 LOT002 LOT003}
```

### 13.3 Layout-Aware Diagnosis

```tcl
# ========================================
# Layout-Aware Diagnosis
# ========================================

# Read DEF for physical info
read_def /path/to/design.def

# Enable layout-aware diagnosis
set_diagnosis_options -layout_aware on

# Physical neighborhood analysis
set_diagnosis_options -neighborhood_radius 5.0    ;# um

# Run layout-aware diagnosis
run_diagnosis

# Report with physical coordinates
report_diagnosis_results -physical
report_diagnosis_results -coordinates

# Defect localization
report_defect_localization
```

---

## 14. Tessent Safety (ISO 26262)

### 14.1 Safety Architecture

```tcl
# ========================================
# ISO 26262 Functional Safety DFT
# ========================================

# Set context for safety
set_context dft -safety

# Read design
read_cell_library /path/to/library.atpg
read_verilog /path/to/design.v
set_current_design top_module

# ========================================
# Safety Mechanism Configuration
# ========================================

# Define safety-critical regions
add_safety_region -name "safety_critical" \
    -instances {u_braking/* u_steering/*} \
    -asil D

# In-system test (periodic online test)
set_safety_configuration -online_test on
set_safety_configuration -test_interval 10ms     ;# fault detection time interval
set_safety_configuration -test_coverage 90       ;# target FMEDA coverage

# ========================================
# Online BIST for Safety
# ========================================

# Configure online LBIST
set_safety_configuration -online_lbist on
set_safety_configuration -lbist_pattern_count 1000
set_safety_configuration -lbist_interval 100ms

# Concurrent test
set_safety_configuration -concurrent_test on

# ========================================
# Safety Analysis
# ========================================

# FMEDA (Failure Mode Effects and Diagnostic Analysis)
run_fmeda_analysis

# Report safety metrics
report_safety_metrics
report_safety_metrics -spfm    ;# Single-Point Fault Metric
report_safety_metrics -lfm     ;# Latent Fault Metric
report_safety_metrics -pmhf    ;# Probabilistic Metric for Hardware Failures

# Export FMEDA report
write_fmeda_report /path/to/fmeda_report.xlsx
```

---

## 15. Common Flows and Recipes

### 15.1 Complete Scan Insertion Flow

```tcl
#!/usr/bin/env tessent -shell -script

# ========================================
# Complete Scan Insertion Flow
# ========================================

# 1. Read design
read_cell_library {lib_std.atpg lib_mem.atpg}
read_verilog {top.v core.v io.v memories.v}
set_current_design top_chip

# 2. Setup
set_context dft -scan
add_clocks 0 clk
add_clocks 1 reset_n
add_input_constraints test_mode -c1
add_input_constraints scan_en -c0

# 3. Configure scan
set_scan_configuration -chain_count 32
set_scan_configuration -clock_mixing mix_clocks
set_scan_configuration -lockup_latch required
set_scan_configuration -balance_chain_length on

# 4. DFT DRC
set_system_mode analysis
check_design_rules
report_dft_violations

# 5. Fix violations (if any)
# ... handle violations ...

# 6. Insert scan
set_system_mode insertion
insert_scan

# 7. Write outputs
write_verilog scan_inserted.v
write_scan_chain_definition scan_chains.txt
write_test_protocol test_protocol.spf

# 8. Report
report_scan_chains -detail
report_statistics

puts "Scan insertion complete"
exit
```

### 15.2 Complete ATPG Flow

```tcl
#!/usr/bin/env tessent -shell -script

# ========================================
# Complete ATPG Flow
# ========================================

# 1. Read scan-inserted design
read_cell_library {lib_std.atpg lib_mem.atpg}
read_verilog scan_inserted.v
set_current_design top_chip

# 2. Read test protocol
read_test_protocol test_protocol.spf

# 3. Setup
set_context dft -atpg
add_clocks 0 clk
add_clocks 1 reset_n

# 4. Enter ATPG mode
set_system_mode atpg

# 5. Stuck-at ATPG
set_fault_type stuck
add_faults -all
set_atpg_options -coverage_target 99.0
set_atpg_options -abort_limit 200
set_atpg_options -merge_level high
create_patterns
report_statistics

# Save stuck-at patterns
write_patterns stuck_at.stil -format stil

# 6. Transition ATPG
set_fault_type transition
add_faults -all
set_pattern_type -type launch_on_capture
create_patterns
report_statistics

# Save transition patterns
write_patterns transition.stil -format stil

# 7. Summary
report_faults -summary
report_patterns -summary

puts "ATPG complete"
exit
```

### 15.3 Complete MBIST Flow

```tcl
#!/usr/bin/env tessent -shell -script

# ========================================
# Complete MBIST Flow
# ========================================

# 1. Read design
read_cell_library {lib_std.atpg lib_mem.atpg}
read_verilog design.v
set_current_design top_chip

# 2. Setup
set_context dft -memory_bist

# 3. Identify memories
identify_memories
report_memories

# 4. Configure MBIST
set_mbist_configuration -algorithm march_c_minus
set_mbist_configuration -data_backgrounds {0x00 0xFF 0x55 0xAA}
set_mbist_configuration -shared_controller on
set_mbist_configuration -repair_enable on

# 5. Configure pins
set_mbist_pins mbist_en -type enable
set_mbist_pins mbist_done -type done
set_mbist_pins mbist_fail -type fail
set_mbist_pins mbist_clk -type clock

# 6. Insert MBIST
set_system_mode insertion
insert_memory_bist

# 7. Write outputs
write_verilog mbist_design.v
write_mbist_controller mbist_ctrl.v

# 8. Report
report_mbist_configuration
report_mbist_statistics

puts "MBIST insertion complete"
exit
```

### 15.4 Environment Variables

```bash
# Tessent environment variables
export TESSENT_HOME=/opt/siemens/tessent/2024.1
export PATH=$TESSENT_HOME/bin:$PATH
export MGLS_LICENSE_FILE=27000@license_server

# Performance
export TESSENT_THREADS=8
export TESSENT_MEMORY_LIMIT=32768

# Temporary directory
export TESSENT_TMPDIR=/fast_disk/tmp

# Debug
export TESSENT_DEBUG=1
export TESSENT_LOGFILE=tessent_debug.log
```

---

*This document covers the Siemens Tessent DFT tool suite including scan insertion, EDT compression, ATPG, LogicBIST, MemoryBIST, boundary scan, test points, low-power test, pattern porting, and silicon diagnosis. For technology-specific DFT rules and cell library characterization, consult your foundry DFT kit documentation.*
