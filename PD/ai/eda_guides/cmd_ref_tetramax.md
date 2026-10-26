# Synopsys TetraMAX ATPG Command Reference

Comprehensive command reference for Synopsys TetraMAX Automatic Test Pattern Generation (ATPG) tool. Covers netlist reading, model building, DRC, fault injection, ATPG execution, fault simulation, pattern management, diagnosis, and coverage reporting.

---

## Table of Contents

1. [Environment and Setup](#environment-and-setup)
2. [Netlist Reading](#netlist-reading)
3. [Model Building](#model-building)
4. [Design Rule Checking](#design-rule-checking)
5. [Fault Management](#fault-management)
6. [ATPG Execution](#atpg-execution)
7. [Fault Simulation](#fault-simulation)
8. [Pattern Management](#pattern-management)
9. [Diagnosis](#diagnosis)
10. [Coverage and Reporting](#coverage-and-reporting)
11. [Fast Sequential ATPG](#fast-sequential-atpg)
12. [Pattern Merging](#pattern-merging)
13. [Advanced ATPG Modes](#advanced-atpg-modes)
14. [Variables and Settings](#variables-and-settings)
15. [Complete Flow Examples](#complete-flow-examples)

---

## 1. Environment and Setup

### Invoking TetraMAX

```bash
# Command-line invocation
tmax                          # Interactive GUI mode
tmax -shell                   # Interactive shell mode
tmax -shell script.tcl        # Batch mode with script
tmax -shell -f script.tcl     # Batch mode, alternative syntax
tmax -shell < script.tcl      # Pipe script to stdin
tmax -64bit -shell             # 64-bit mode

# With specific memory allocation
tmax -shell -max_memory 16000  # 16 GB memory limit
```

### Basic Environment Setup

```tcl
# Set up search path for libraries
set_messages -log tmax.log

# Set verbosity
set_messages -level detailed

# Set working directory
# TetraMAX uses current directory by default

# License checkout
# TetraMAX automatically checks out license on startup
```

### Key Application Variables

```tcl
# Memory management
set_simulation -max_memory 16000     ;# MB

# Pattern limits
set_atpg -max_patterns 10000

# Abort limits
set_atpg -abort_limit 50

# Simulation performance
set_simulation -num_processes 4       ;# Parallel simulation
```

---

## 2. Netlist Reading

### read_netlist

Reads gate-level netlist into TetraMAX.

**Syntax:**
```tcl
read_netlist <filename>
    [-library]
    [-define <macro_list>]
    [-insensitive]
    [-mux_net_name <name>]
    [-net_name_prefix <prefix>]
    [-net_name_suffix <suffix>]
    [-top <module_name>]
    [-verilog]
    [-vhdl]
```

**Examples:**
```tcl
# Read technology library models
read_netlist lib/saed32hvt_tt1p05v25c.v -library
read_netlist lib/saed32lvt_tt1p05v25c.v -library
read_netlist lib/saed32rvt_tt1p05v25c.v -library

# Read standard cell libraries
read_netlist lib/std_cells.v -library

# Read memory models
read_netlist lib/memories.v -library

# Read design netlist
read_netlist design/top_scan.v

# Read with defines
read_netlist design/top_scan.v -define {SCAN_MODE FUNC_TEST}

# Read VHDL netlist
read_netlist design/top_scan.vhd -vhdl

# Read with case insensitive names
read_netlist design/top_scan.v -insensitive

# Read multiple files
read_netlist lib/io_cells.v -library
read_netlist lib/macros.v -library
read_netlist design/sub_block1.v
read_netlist design/sub_block2.v
read_netlist design/top.v
```

### set_netlist

Configures netlist reading options.

**Syntax:**
```tcl
set_netlist
    [-top_module <name>]
    [-net_connection_check <on | off>]
    [-net_resolution <wired_or | wired_and | resolve_x | resolve_0 | resolve_1>]
    [-port_connection_check <on | off>]
```

**Examples:**
```tcl
# Set top module
set_netlist -top_module top_chip

# Enable connection checks
set_netlist -net_connection_check on -port_connection_check on

# Set net resolution for tri-state
set_netlist -net_resolution resolve_x
```

---

## 3. Model Building

### run_build_model

Builds the internal simulation model from the netlist.

**Syntax:**
```tcl
run_build_model <design_name>
    [-hierarchy]
    [-nodesign_instances]
    [-delay_type <zero | unit | estimated | sdf>]
    [-sdf_file <filename>]
```

**Examples:**
```tcl
# Build model for top module
run_build_model top_chip

# Build with hierarchy
run_build_model top_chip -hierarchy

# Build with estimated delays
run_build_model top_chip -delay_type estimated

# Build with SDF back-annotation
run_build_model top_chip -delay_type sdf -sdf_file top_chip.sdf

# Build with zero delay (stuck-at only)
run_build_model top_chip -delay_type zero
```

### set_build_model

Configures model building options.

**Syntax:**
```tcl
set_build_model
    [-latch <transparent | opaque>]
    [-memory <read_write | read_only>]
    [-clock_auto_identification <on | off>]
    [-tristate_handling <bus | point>]
    [-design_level <top | sub>]
```

**Examples:**
```tcl
# Configure latch handling
set_build_model -latch transparent

# Configure memory handling
set_build_model -memory read_write

# Enable clock auto-identification
set_build_model -clock_auto_identification on

# Configure tristate handling
set_build_model -tristate_handling bus
```

---

## 4. Design Rule Checking

### run_drc

Runs design rule checks on the built model.

**Syntax:**
```tcl
run_drc <test_protocol_file>
    [-force]
    [-auto_fix]
    [-report <filename>]
```

**Examples:**
```tcl
# Run DRC with test protocol
run_drc top_scan.spf

# Run DRC with STIL protocol
run_drc top_scan.stil

# Force DRC (ignore previous DRC results)
run_drc top_scan.spf -force

# Run DRC with auto-fix
run_drc top_scan.spf -auto_fix

# Run DRC and save report
run_drc top_scan.spf -report drc_report.txt
```

### set_drc

Configures DRC behavior.

**Syntax:**
```tcl
set_drc
    [-clock_handling <on | off | auto>]
    [-bidirectional_handling <on | off>]
    [-overlap_handling <on | off>]
    [-reset_handling <on | off>]
    [-tristate_handling <on | off>]
    [-allow_unstable_set_reset]
    [-connect_floating_signal <0 | 1 | x>]
```

**Examples:**
```tcl
# Standard DRC configuration
set_drc -clock_handling auto \
    -bidirectional_handling on \
    -overlap_handling on

# Allow unstable set/reset
set_drc -allow_unstable_set_reset

# Connect floating signals to 0
set_drc -connect_floating_signal 0

# Full DRC configuration
set_drc \
    -clock_handling auto \
    -bidirectional_handling on \
    -overlap_handling on \
    -reset_handling on \
    -tristate_handling on
```

### report_drc_rules

```tcl
# Report DRC results
report_drc_rules

# Report specific rule
report_drc_rules -rule D1

# Report with severity filter
report_drc_rules -severity error
report_drc_rules -severity warning
```

### Common DRC Rules

| Rule | Description |
|------|-------------|
| D1 | No scan chain connected |
| D2 | Clock not constrained |
| D3 | Scan enable not constrained |
| D4 | Reset signal not constrained |
| D5 | Bidirectional port not constrained |
| D6 | Test mode signal not constrained |
| C1 | Clock has reconvergence |
| C2 | Clock feeds data input |
| C3 | Multiple clocks on scan chain |
| S1 | Scan chain broken |
| S2 | Scan chain has loop |
| S3 | Scan chain order violation |

---

## 5. Fault Management

### add_faults

Adds faults for ATPG.

**Syntax:**
```tcl
add_faults
    [-type <stuck | transition | path_delay | bridging | iddq | hold>]
    [-all]
    [-module <module_name>]
    [-instance <instance_path>]
    [-pin <pin_name>]
    [-net <net_name>]
    [-fault_value <0 | 1>]
    [-port_faults]
```

**Fault Types:**

| Type | Description |
|------|-------------|
| `stuck` | Stuck-at faults (SA0, SA1) |
| `transition` | Slow-to-rise, slow-to-fall |
| `path_delay` | Path delay faults |
| `bridging` | Bridging faults between nets |
| `iddq` | IDDQ faults |
| `hold` | Hold time faults |

**Examples:**
```tcl
# Add all stuck-at faults
add_faults -all

# Add transition faults
add_faults -all -type transition

# Add path delay faults
add_faults -all -type path_delay

# Add bridging faults
add_faults -all -type bridging

# Add faults for specific module
add_faults -module cpu_core

# Add faults for specific instance
add_faults -instance u_alu/u_adder

# Add faults on specific pin
add_faults -pin u_reg/Q -fault_value 0

# Add faults on specific net
add_faults -net data_bus[0] -fault_value 1

# Add stuck-at-0 faults only
add_faults -all -fault_value 0

# Add port faults
add_faults -port_faults
```

### remove_faults

Removes faults from fault list.

**Syntax:**
```tcl
remove_faults
    [-all]
    [-type <fault_type>]
    [-status <detected | undetected | untestable | ...>]
    [-module <module_name>]
    [-instance <instance_path>]
```

**Examples:**
```tcl
# Remove all faults
remove_faults -all

# Remove only untestable faults
remove_faults -status untestable

# Remove faults for specific module
remove_faults -module mem_wrapper

# Remove specific fault type
remove_faults -type bridging
```

### set_faults

Configures fault options.

**Syntax:**
```tcl
set_faults
    [-model <stuck | transition | path_delay | bridging | iddq>]
    [-fault_coverage <true | false>]
    [-equivalence <on | off>]
    [-pt_credit <true | false>]
    [-summary <verbose | normal | none>]
    [-report <collapsed | uncollapsed>]
```

**Examples:**
```tcl
# Set stuck-at fault model
set_faults -model stuck

# Set transition fault model
set_faults -model transition

# Enable fault equivalence
set_faults -equivalence on

# Enable PrimeTime credit
set_faults -pt_credit true

# Set verbose fault summary
set_faults -summary verbose

# Report collapsed faults
set_faults -report collapsed
```

---

## 6. ATPG Execution

### run_atpg

Runs automatic test pattern generation.

**Syntax:**
```tcl
run_atpg
    [-auto]
    [-auto_compression]
    [-patterns <max_patterns>]
    [-coverage <target_coverage>]
    [-abort_limit <integer>]
    [-merge <high | medium | low | none>]
    [-effort <low | medium | high>]
    [-verbose]
    [-ndetects <integer>]
```

**Examples:**
```tcl
# Basic ATPG run
run_atpg -auto

# ATPG with auto compression
run_atpg -auto_compression

# ATPG with target coverage
run_atpg -auto -coverage 99.5

# ATPG with pattern limit
run_atpg -auto -patterns 5000

# High-effort ATPG
run_atpg -auto -effort high -abort_limit 100

# ATPG with N-detect
run_atpg -auto -ndetects 3

# ATPG with merge
run_atpg -auto -merge high

# Verbose ATPG
run_atpg -auto -verbose

# Combined options
run_atpg -auto_compression \
    -coverage 99.0 \
    -patterns 10000 \
    -abort_limit 50 \
    -merge high \
    -effort high
```

### set_atpg

Configures ATPG parameters.

**Syntax:**
```tcl
set_atpg
    [-abort_limit <integer>]
    [-merge <high | medium | low | none>]
    [-patterns <integer>]
    [-coverage <float>]
    [-decision_order <random | simulation | reverse>]
    [-fill <random | 0 | 1 | x | adjacent>]
    [-capture_cycles <integer>]
    [-power_effort <none | low | medium | high>]
    [-compression <on | off | auto>]
    [-num_processes <integer>]
    [-clock_sequential_depth <integer>]
    [-pi_constraints <on | off>]
    [-po_masking <on | off>]
    [-x_handling <auto | optimistic | pessimistic>]
    [-verbose <on | off>]
```

**Key Options Explained:**

| Option | Description | Default |
|--------|-------------|---------|
| `-abort_limit` | Max backtracks per fault | 10 |
| `-merge` | Pattern compaction level | `high` |
| `-patterns` | Max patterns to generate | unlimited |
| `-coverage` | Target fault coverage | 100% |
| `-fill` | Pattern fill strategy | `random` |
| `-capture_cycles` | Capture cycles per pattern | 1 |
| `-power_effort` | Shift/capture power reduction | `none` |
| `-compression` | Enable scan compression | `auto` |
| `-num_processes` | Parallel ATPG processes | 1 |
| `-clock_sequential_depth` | Sequential depth for fast-seq | 0 |

**Examples:**
```tcl
# Configure for stuck-at ATPG
set_atpg -abort_limit 50 \
    -merge high \
    -fill random \
    -coverage 99.0

# Configure for transition ATPG
set_atpg -abort_limit 100 \
    -capture_cycles 2 \
    -fill adjacent \
    -power_effort medium

# Configure parallel ATPG
set_atpg -num_processes 8 \
    -abort_limit 50

# Low-power ATPG
set_atpg -power_effort high \
    -fill 0 \
    -merge medium

# Fast sequential ATPG
set_atpg -clock_sequential_depth 3 \
    -abort_limit 100

# Conservative X handling
set_atpg -x_handling pessimistic
```

### ATPG Pattern Fill Options

```tcl
# Random fill (best for defect coverage)
set_atpg -fill random

# Zero fill (lowest power)
set_atpg -fill 0

# One fill
set_atpg -fill 1

# X fill (don't care, smallest patterns)
set_atpg -fill x

# Adjacent fill (for transition tests, reduces toggle)
set_atpg -fill adjacent
```

---

## 7. Fault Simulation

### run_fault_sim

Runs fault simulation on existing patterns.

**Syntax:**
```tcl
run_fault_sim
    [-patterns <pattern_file>]
    [-format <binary | wgl | stil>]
    [-verbose]
```

**Examples:**
```tcl
# Fault simulate internal patterns
run_fault_sim

# Fault simulate external patterns
run_fault_sim -patterns external_patterns.bin -format binary

# Fault simulate WGL patterns
run_fault_sim -patterns test.wgl -format wgl

# Fault simulate STIL patterns
run_fault_sim -patterns test.stil -format stil

# Verbose fault simulation
run_fault_sim -verbose
```

### set_simulation

Configures fault simulation parameters.

**Syntax:**
```tcl
set_simulation
    [-num_processes <integer>]
    [-max_memory <integer>]
    [-timing <zero | unit | estimated | sdf>]
    [-sequential_depth <integer>]
```

**Examples:**
```tcl
# Parallel fault simulation
set_simulation -num_processes 8

# Memory limit
set_simulation -max_memory 16000

# SDF-based timing simulation
set_simulation -timing sdf

# Sequential depth for simulation
set_simulation -sequential_depth 5
```

### report_faults

Reports fault status after ATPG or fault simulation.

**Syntax:**
```tcl
report_faults
    [-class <detected | undetected | untestable | ...>]
    [-summary]
    [-verbose]
    [-module <module_name>]
    [-instance <instance_path>]
    [-limit <integer>]
    [-output <filename>]
    [-collapsed]
    [-uncollapsed]
```

**Fault Classes:**

| Class | Description |
|-------|-------------|
| `DT` (Detected) | Fault detected by patterns |
| `PT` (Possibly Detected) | Possibly detected |
| `UD` (Undetected) | Not yet targeted/detected |
| `AU` (ATPG Untestable) | Cannot be tested by ATPG |
| `TI` (Tied) | Tied to constant value |
| `BL` (Blocked) | Blocked by untestable logic |
| `RE` (Redundant) | Logically redundant |
| `UO` (Unobservable) | Cannot observe at output |
| `UC` (Uncontrollable) | Cannot control fault site |
| `ND` (Not Detected) | Targeted but not detected |

**Examples:**
```tcl
# Fault summary
report_faults -summary

# Report undetected faults
report_faults -class UD

# Report untestable faults
report_faults -class AU

# Report faults for module
report_faults -module u_core -summary

# Report faults for instance
report_faults -instance u_core/u_alu -verbose

# Report with limit
report_faults -class UD -limit 100

# Save fault report
report_faults -class UD -output undetected_faults.rpt

# Report collapsed faults
report_faults -summary -collapsed

# Report uncollapsed faults
report_faults -summary -uncollapsed
```

---

## 8. Pattern Management

### write_patterns

Writes generated patterns to file.

**Syntax:**
```tcl
write_patterns <filename>
    [-format <binary | wgl | stil | verilog | ascii>]
    [-compress <gzip>]
    [-replace]
    [-internal]
    [-external]
    [-scan_order <original | reverse>]
    [-serial]
    [-parallel]
    [-begin <pattern_number>]
    [-end <pattern_number>]
    [-mode <shift | capture | all>]
```

**Pattern Formats:**

| Format | Description | Use Case |
|--------|-------------|----------|
| `binary` | TetraMAX binary format | Internal storage, fast I/O |
| `wgl` | Waveform Generation Language | ATE programming |
| `stil` | Standard Test Interface Language (IEEE 1450) | ATE programming |
| `verilog` | Verilog testbench | Simulation |
| `ascii` | Human-readable ASCII | Debug |

**Examples:**
```tcl
# Write binary patterns
write_patterns top_patterns.bin -format binary -replace

# Write WGL patterns
write_patterns top_patterns.wgl -format wgl -replace

# Write STIL patterns
write_patterns top_patterns.stil -format stil -replace

# Write Verilog testbench
write_patterns top_patterns_tb.v -format verilog -replace

# Write compressed patterns
write_patterns top_patterns.stil.gz -format stil -compress gzip

# Write specific pattern range
write_patterns partial.bin -format binary -begin 0 -end 100

# Write serial patterns
write_patterns serial_patterns.stil -format stil -serial

# Write parallel patterns
write_patterns parallel_patterns.stil -format stil -parallel

# Write ASCII for debug
write_patterns debug_patterns.txt -format ascii -replace

# Write internal patterns only
write_patterns internal.bin -format binary -internal

# Write external patterns only
write_patterns external.bin -format binary -external
```

### read_patterns

Reads patterns from file.

**Syntax:**
```tcl
read_patterns <filename>
    [-format <binary | wgl | stil>]
    [-delete]
    [-external]
```

**Examples:**
```tcl
# Read binary patterns
read_patterns top_patterns.bin -format binary

# Read STIL patterns
read_patterns top_patterns.stil -format stil

# Read WGL patterns
read_patterns top_patterns.wgl -format wgl

# Delete existing patterns before reading
read_patterns new_patterns.bin -format binary -delete

# Read external patterns
read_patterns ate_patterns.stil -format stil -external
```

### Pattern Operations

```tcl
# Report pattern statistics
report_patterns

# Report specific pattern
report_patterns -pattern_number 42

# Report pattern count
report_patterns -summary

# Delete patterns
remove_patterns -all

# Delete specific pattern range
remove_patterns -begin 100 -end 200
```

---

## 9. Diagnosis

### run_diagnosis

Runs diagnosis on failing patterns to identify likely defect locations.

**Syntax:**
```tcl
run_diagnosis
    [-algorithm <effect_cause | cause_effect | direct | combined>]
    [-max_suspects <integer>]
    [-num_processes <integer>]
    [-verbose]
```

**Diagnosis Algorithms:**

| Algorithm | Description |
|-----------|-------------|
| `effect_cause` | Back-traces from failing outputs |
| `cause_effect` | Forward-traces from fault sites |
| `direct` | Direct cause diagnosis |
| `combined` | Combines effect-cause and cause-effect |

**Examples:**
```tcl
# Basic diagnosis
run_diagnosis

# Effect-cause diagnosis
run_diagnosis -algorithm effect_cause

# Combined diagnosis with max suspects
run_diagnosis -algorithm combined -max_suspects 10

# Parallel diagnosis
run_diagnosis -num_processes 8 -verbose

# High-accuracy diagnosis
run_diagnosis -algorithm combined \
    -max_suspects 20 \
    -verbose
```

### set_diagnosis

Configures diagnosis options.

**Syntax:**
```tcl
set_diagnosis
    [-algorithm <effect_cause | cause_effect | direct | combined>]
    [-max_suspects <integer>]
    [-failing_patterns <filename>]
    [-passing_patterns <filename>]
    [-fail_log <filename>]
    [-output <filename>]
    [-verbose <on | off>]
```

**Examples:**
```tcl
# Configure diagnosis
set_diagnosis \
    -algorithm combined \
    -max_suspects 15 \
    -failing_patterns fail.bin \
    -fail_log fail.log \
    -output diag_results.rpt

# Set failing and passing patterns
set_diagnosis \
    -failing_patterns fail_patterns.bin \
    -passing_patterns pass_patterns.bin
```

### report_diagnosis

Reports diagnosis results.

**Syntax:**
```tcl
report_diagnosis
    [-summary]
    [-verbose]
    [-suspects <integer>]
    [-output <filename>]
    [-score_limit <float>]
```

**Examples:**
```tcl
# Report diagnosis summary
report_diagnosis -summary

# Report detailed diagnosis
report_diagnosis -verbose

# Report top N suspects
report_diagnosis -suspects 10

# Report with score limit
report_diagnosis -score_limit 0.5

# Save diagnosis report
report_diagnosis -verbose -output diagnosis_report.rpt
```

---

## 10. Coverage and Reporting

### report_summaries

Provides comprehensive test summary.

**Syntax:**
```tcl
report_summaries
    [-fault_type <stuck | transition | path_delay | bridging | iddq>]
    [-output <filename>]
```

**Examples:**
```tcl
# Overall test summary
report_summaries

# Summary for stuck-at faults
report_summaries -fault_type stuck

# Summary for transition faults
report_summaries -fault_type transition

# Save summary
report_summaries -output test_summary.rpt
```

### report_statistics

Provides detailed ATPG statistics.

**Syntax:**
```tcl
report_statistics
    [-output <filename>]
    [-verbose]
```

**Examples:**
```tcl
# Report statistics
report_statistics

# Verbose statistics
report_statistics -verbose

# Save statistics
report_statistics -output atpg_stats.rpt
```

### Coverage Reporting

```tcl
# Report overall fault coverage
report_faults -summary

# Report coverage by module
report_faults -module u_core -summary
report_faults -module u_mem -summary
report_faults -module u_io -summary

# Report coverage by fault type
set_faults -model stuck
report_faults -summary

set_faults -model transition
report_faults -summary

# Report test coverage breakdown
report_summaries

# Report pattern efficiency
report_patterns -summary
```

### Coverage Metrics

```tcl
# Fault coverage = (DT + PT) / (Total - TI - BL)
# Test coverage  = DT / (Total - TI - BL - RE - UO - UC)
# ATPG effectiveness = (DT + AU + RE + UO + UC + TI + BL) / Total

# Example coverage report output:
#   Fault Class           Faults
#   ---------------------- ------
#   Detected         (DT)  98500
#   Possibly Det     (PT)    200
#   Undetectable     (UD)    100
#   ATPG Untestable  (AU)    500
#   Not Detected     (ND)     50
#   Redundant        (RE)    150
#   Untestable       (UO)    100
#   Tied             (TI)    200
#   Blocked          (BL)    200
#   ---------------------- ------
#   Total                 100000
#   Test Coverage:         99.23%
#   Fault Coverage:        98.87%
#   ATPG Effectiveness:    99.85%
```

---

## 11. Fast Sequential ATPG

Fast sequential ATPG targets faults that require multiple clock cycles to detect, going beyond single-cycle combinational ATPG.

### Configuration

```tcl
# Enable fast sequential ATPG
set_atpg -clock_sequential_depth <depth>

# depth = 0: combinational only (default)
# depth = 1-N: N sequential frames
```

### Fast Sequential Flow

```tcl
# 1. Read netlist and build model
read_netlist lib/std_cells.v -library
read_netlist design/top_scan.v
run_build_model top_chip

# 2. Run DRC
run_drc top_scan.spf

# 3. Add faults
add_faults -all

# 4. Run combinational ATPG first
set_atpg -clock_sequential_depth 0
run_atpg -auto

# 5. Run fast sequential ATPG on remaining faults
set_atpg -clock_sequential_depth 3 -abort_limit 100
run_atpg -auto -coverage 99.5

# 6. Optionally increase depth for remaining
set_atpg -clock_sequential_depth 5 -abort_limit 200
run_atpg -auto

# 7. Report
report_faults -summary
report_summaries
```

### Sequential Depth Guidelines

```tcl
# Depth 0: Standard combinational ATPG (fastest)
# Depth 1: Detects most sequential faults
# Depth 2-3: Good balance of coverage vs runtime
# Depth 4-6: Higher coverage, longer runtime
# Depth 7+: Diminishing returns, very long runtime
```

---

## 12. Pattern Merging

### Merging Patterns from Multiple Runs

```tcl
# Method 1: Merge within session
# Run first ATPG
add_faults -all -type stuck
run_atpg -auto
write_patterns stuck_at.bin -format binary -replace

# Add transition faults without removing stuck-at patterns
add_faults -all -type transition
run_atpg -auto
write_patterns all_patterns.bin -format binary -replace

# Method 2: Read and merge from files
read_patterns stuck_at.bin -format binary
read_patterns transition.bin -format binary
write_patterns merged.bin -format binary -replace
```

### Pattern Compaction

```tcl
# Static compaction (merge during ATPG)
set_atpg -merge high
run_atpg -auto

# Dynamic compaction (post-ATPG merge)
run_atpg -auto -merge high

# Report compaction results
report_patterns -summary
```

### Pattern Set Operations

```tcl
# Validate merged patterns
read_patterns merged.bin -format binary
run_fault_sim
report_faults -summary

# Incremental ATPG (top-up)
read_patterns existing.bin -format binary
run_fault_sim    ;# Credit existing patterns
run_atpg -auto   ;# Generate additional patterns for uncovered faults
write_patterns complete.bin -format binary -replace
```

---

## 13. Advanced ATPG Modes

### N-Detect ATPG

```tcl
# Generate patterns to detect each fault N times
set_atpg -ndetects 3
run_atpg -auto

# N-detect improves defect coverage beyond stuck-at
# Typical N values: 2-5
# Higher N = more patterns but better defect coverage
```

### IDDQ Testing

```tcl
# Configure for IDDQ
set_faults -model iddq
add_faults -all

# IDDQ ATPG
set_atpg -fill 0          ;# Low power fill
run_atpg -auto

# Write IDDQ patterns
write_patterns iddq_patterns.stil -format stil -replace
```

### Path Delay Testing

```tcl
# Add path delay faults
add_faults -all -type path_delay

# Configure for path delay
set_atpg -capture_cycles 2 \
    -abort_limit 200

# Run path delay ATPG
run_atpg -auto

# Report path delay coverage
report_faults -summary
```

### Bridging Fault Testing

```tcl
# Add bridging faults
add_faults -all -type bridging

# Configure for bridging
set_atpg -abort_limit 100

# Run bridging ATPG
run_atpg -auto

# Report
report_faults -summary
```

### Low Power ATPG

```tcl
# Configure low power options
set_atpg -power_effort high \
    -fill 0

# Limit shift power by controlling scan chain toggles
set_atpg -merge low        ;# Less merging = lower power

# Configure capture power
set_atpg -capture_cycles 1  ;# Minimum capture cycles

# Run low-power ATPG
run_atpg -auto

# Report power metrics
report_patterns -summary
```

### Compression-Aware ATPG

```tcl
# TetraMAX automatically detects DFTMAX compression
# Compression is handled transparently

# Force compression mode
set_atpg -compression on

# Disable compression (for debug)
set_atpg -compression off

# Auto detect compression (default)
set_atpg -compression auto
```

---

## 14. Variables and Settings

### Complete Variable Reference

```tcl
# === ATPG Variables ===
set_atpg -abort_limit 50           ;# Backtrack limit per fault
set_atpg -merge high               ;# Pattern compaction: high/medium/low/none
set_atpg -patterns 10000           ;# Max patterns
set_atpg -coverage 99.0            ;# Target coverage (%)
set_atpg -fill random              ;# Pattern fill: random/0/1/x/adjacent
set_atpg -capture_cycles 2         ;# Capture cycles (transition)
set_atpg -power_effort medium      ;# Power reduction: none/low/medium/high
set_atpg -clock_sequential_depth 0 ;# Sequential depth
set_atpg -num_processes 4          ;# Parallel processes
set_atpg -ndetects 1               ;# N-detect count
set_atpg -decision_order random    ;# Decision order
set_atpg -compression auto         ;# Compression mode

# === Fault Variables ===
set_faults -model stuck             ;# Fault model
set_faults -equivalence on          ;# Fault equivalence
set_faults -pt_credit true          ;# PrimeTime credit
set_faults -report collapsed        ;# Report style

# === Simulation Variables ===
set_simulation -num_processes 8     ;# Parallel sim processes
set_simulation -max_memory 16000    ;# Memory limit (MB)

# === DRC Variables ===
set_drc -clock_handling auto        ;# Clock handling
set_drc -bidirectional_handling on  ;# Bidir handling

# === Build Model Variables ===
set_build_model -latch transparent  ;# Latch handling
set_build_model -memory read_write  ;# Memory handling

# === Message Variables ===
set_messages -log tmax.log          ;# Log file
set_messages -level detailed        ;# Verbosity
```

---

## 15. Complete Flow Examples

### Stuck-At ATPG Flow

```tcl
#!/usr/bin/tmax -shell

# Setup
set_messages -log stuck_at_atpg.log

# Read libraries
read_netlist lib/saed32rvt.v -library
read_netlist lib/saed32lvt.v -library
read_netlist lib/saed32hvt.v -library
read_netlist lib/sram_models.v -library
read_netlist lib/io_cells.v -library

# Read design
read_netlist design/top_scan.v

# Build model
run_build_model top_chip

# Run DRC
run_drc protocols/top_scan.spf

# Add stuck-at faults
add_faults -all

# Configure ATPG
set_atpg -abort_limit 50 \
    -merge high \
    -fill random \
    -num_processes 8

# Run ATPG
run_atpg -auto

# Report
report_faults -summary
report_summaries
report_statistics

# Write patterns
write_patterns output/stuck_at.bin -format binary -replace
write_patterns output/stuck_at.stil -format stil -replace
write_patterns output/stuck_at_tb.v -format verilog -replace

# Exit
exit
```

### Transition ATPG Flow

```tcl
#!/usr/bin/tmax -shell

# Setup
set_messages -log transition_atpg.log

# Read libraries and design
read_netlist lib/saed32rvt.v -library
read_netlist lib/saed32lvt.v -library
read_netlist lib/saed32hvt.v -library
read_netlist lib/sram_models.v -library
read_netlist design/top_scan.v

# Build model with delays
run_build_model top_chip -delay_type estimated

# Run DRC
run_drc protocols/top_scan.spf

# Add transition faults
set_faults -model transition
add_faults -all

# Configure transition ATPG
set_atpg -abort_limit 100 \
    -merge high \
    -fill adjacent \
    -capture_cycles 2 \
    -power_effort medium \
    -num_processes 8

# Run ATPG
run_atpg -auto -coverage 98.0

# Fast sequential for remaining faults
set_atpg -clock_sequential_depth 2 -abort_limit 200
run_atpg -auto

# Report
report_faults -summary
report_summaries

# Write patterns
write_patterns output/transition.bin -format binary -replace
write_patterns output/transition.stil -format stil -replace

exit
```

### Diagnosis Flow

```tcl
#!/usr/bin/tmax -shell

# Setup
set_messages -log diagnosis.log

# Read libraries and design
read_netlist lib/saed32rvt.v -library
read_netlist lib/saed32lvt.v -library
read_netlist design/top_scan.v

# Build model
run_build_model top_chip

# Run DRC
run_drc protocols/top_scan.spf

# Read original test patterns
read_patterns output/stuck_at.bin -format binary

# Configure diagnosis
set_diagnosis \
    -algorithm combined \
    -max_suspects 20 \
    -fail_log tester/fail_log.txt

# Run diagnosis
run_diagnosis -verbose

# Report diagnosis results
report_diagnosis -summary
report_diagnosis -suspects 10 -verbose
report_diagnosis -output diagnosis_results.rpt

exit
```

### Incremental ATPG Flow

```tcl
#!/usr/bin/tmax -shell

# Setup
set_messages -log incremental_atpg.log

# Read libraries and design
read_netlist lib/saed32rvt.v -library
read_netlist design/top_scan_v2.v    ;# Updated design

# Build model
run_build_model top_chip

# Run DRC
run_drc protocols/top_scan_v2.spf

# Add all faults
add_faults -all

# Read existing patterns and fault simulate
read_patterns output/existing_patterns.bin -format binary
run_fault_sim

# Check current coverage
report_faults -summary

# Run incremental ATPG for uncovered faults
set_atpg -abort_limit 50 -merge high -fill random
run_atpg -auto

# Report final coverage
report_faults -summary
report_summaries

# Write complete pattern set
write_patterns output/complete_patterns.bin -format binary -replace
write_patterns output/complete_patterns.stil -format stil -replace

exit
```

### Multi-Fault-Type Flow

```tcl
#!/usr/bin/tmax -shell

set_messages -log multi_fault_atpg.log

# Read libraries and design
read_netlist lib/saed32rvt.v -library
read_netlist lib/saed32lvt.v -library
read_netlist design/top_scan.v
run_build_model top_chip
run_drc protocols/top_scan.spf

# === Phase 1: Stuck-At ===
set_faults -model stuck
add_faults -all
set_atpg -abort_limit 50 -merge high -fill random -num_processes 8
run_atpg -auto
report_faults -summary
write_patterns output/sa_patterns.bin -format binary -replace

# === Phase 2: Transition ===
remove_faults -all
set_faults -model transition
add_faults -all
set_atpg -abort_limit 100 -merge high -fill adjacent \
    -capture_cycles 2 -power_effort medium -num_processes 8
run_atpg -auto
report_faults -summary
write_patterns output/trans_patterns.bin -format binary -replace

# === Phase 3: IDDQ ===
remove_faults -all
set_faults -model iddq
add_faults -all
set_atpg -fill 0
run_atpg -auto
report_faults -summary
write_patterns output/iddq_patterns.bin -format binary -replace

# === Final Report ===
report_summaries
report_statistics -verbose

exit
```

---

## Quick Reference: Command Cheat Sheet

| Task | Command |
|------|---------|
| Read library netlist | `read_netlist file.v -library` |
| Read design netlist | `read_netlist design.v` |
| Build simulation model | `run_build_model top` |
| Run DRC | `run_drc protocol.spf` |
| Add all stuck-at faults | `add_faults -all` |
| Add transition faults | `add_faults -all -type transition` |
| Configure ATPG | `set_atpg -abort_limit 50 -merge high` |
| Run ATPG | `run_atpg -auto` |
| Run fault simulation | `run_fault_sim` |
| Report fault summary | `report_faults -summary` |
| Report test summary | `report_summaries` |
| Write STIL patterns | `write_patterns out.stil -format stil` |
| Write binary patterns | `write_patterns out.bin -format binary` |
| Write Verilog testbench | `write_patterns out.v -format verilog` |
| Read patterns | `read_patterns in.bin -format binary` |
| Run diagnosis | `run_diagnosis -algorithm combined` |
| Report diagnosis | `report_diagnosis -summary` |
| Report statistics | `report_statistics` |
