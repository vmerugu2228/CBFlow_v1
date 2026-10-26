# Cadence Voltus Power Analysis -- Comprehensive Command Reference

## Table of Contents

1. [Design Import and Setup](#design-import-and-setup)
2. [Power Analysis Modes](#power-analysis-modes)
3. [Static IR Drop Analysis](#static-ir-drop-analysis)
4. [Dynamic IR Drop Analysis](#dynamic-ir-drop-analysis)
5. [Electromigration (EM) Analysis](#electromigration-em-analysis)
6. [Power Grid Analysis](#power-grid-analysis)
7. [Switching Activity](#switching-activity)
8. [Thermal Analysis](#thermal-analysis)
9. [Power Reporting](#power-reporting)
10. [Advanced Analysis Features](#advanced-analysis-features)
11. [Output and Export](#output-and-export)
12. [Utility Commands](#utility-commands)

---

## Design Import and Setup

### Design Read-In

```tcl
# Read Liberty libraries
read_lib {/libs/stdcells/ss_0p75v_125c.lib /libs/sram/sram_ss.lib}

# Read LEF files
read_lef {/libs/tech/tech.lef /libs/stdcells/stdcells.lef /libs/sram/sram.lef}

# Read Verilog netlist
read_verilog /output/innovus/top_chip.v
set_top_module top_chip

# Read DEF
read_def /output/innovus/top_chip.def

# Read SPEF parasitics
read_spef /extraction/top_chip.spef

# Read SDC constraints
read_sdc /constraints/top_chip.sdc

# OR: Read Innovus design database directly
read_design /output/innovus/top_chip_final.inn
```

### Power Net Configuration

```tcl
# Define power nets
set_db init_power_nets {VDD VDDH VDD_CORE VDD_IO}
set_db init_ground_nets {VSS VSSQ}

# Assign global nets
globalNetConnect VDD -type pgpin -pin VDD -all
globalNetConnect VSS -type pgpin -pin VSS -all
globalNetConnect VDD -type tiehi
globalNetConnect VSS -type tielo
```

### Technology Setup

```tcl
# Read power grid model
read_power_grid_model /libs/tech/pg_model.tcl

# Read QRC tech file for RC extraction
read_qrc /libs/tech/qrcTechFile

# Set technology parameters
set_db power_tech_file /libs/tech/voltus_tech.tcl

# Temperature
set_db power_temperature 125.0

# Voltage
set_db power_default_voltage 0.75
```

---

## Power Analysis Modes

### set_power_analysis_mode

The primary command for configuring power analysis type.

```tcl
# ============================================================
# Static Power Analysis
# ============================================================

# Vector-less (statistical) power analysis
set_power_analysis_mode -method static \
    -analysis_view av_wc_func

# Vector-based (simulation-driven) static analysis
set_power_analysis_mode -method static \
    -analysis_view av_wc_func \
    -create_binary_db true

# ============================================================
# Dynamic Power Analysis
# ============================================================

# Dynamic (time-based) analysis
set_power_analysis_mode -method dynamic \
    -analysis_view av_wc_func

# Dynamic vectorless
set_power_analysis_mode -method dynamic_vectorless \
    -analysis_view av_wc_func

# ============================================================
# Leakage-Only Analysis
# ============================================================

set_power_analysis_mode -method static \
    -analysis_view av_wc_func \
    -leakage_only true

# ============================================================
# Common Options
# ============================================================

# Hierarchical analysis
set_power_analysis_mode -method static \
    -analysis_view av_wc_func \
    -hierarchy all

# Write binary database
set_power_analysis_mode -create_binary_db true \
    -binary_db_name output/power_db

# Multi-corner
set_power_analysis_mode -method static \
    -analysis_view {av_wc_func av_tc_func}
```

**set_power_analysis_mode options:**

| Option | Description |
|--------|-------------|
| `-method <type>` | `static`, `dynamic`, `dynamic_vectorless` |
| `-analysis_view <views>` | Active analysis views |
| `-create_binary_db <bool>` | Create binary power DB |
| `-binary_db_name <path>` | Path for binary DB |
| `-hierarchy <mode>` | `all`, `top`, or specific hierarchy |
| `-leakage_only <bool>` | Leakage power only |
| `-ignore_control_signals <bool>` | Ignore control signal effects |
| `-write_static_currents <bool>` | Write per-instance current data |
| `-honor_negative_arc_power <bool>` | Honor negative arc power |

---

## Static IR Drop Analysis

### Static IR Setup and Execution

```tcl
# ============================================================
# Step 1: Configure power analysis
# ============================================================
set_power_analysis_mode -method static \
    -analysis_view av_wc_func \
    -create_binary_db true

# ============================================================
# Step 2: Set switching activity (vectorless)
# ============================================================
set_default_switching_activity -input_activity 0.2 \
    -period 2.0

# OR read activity from VCD/SAIF (see Switching Activity section)

# ============================================================
# Step 3: Set power grid analysis options
# ============================================================
set_pg_analysis_mode -power_grid_analysis static

# ============================================================
# Step 4: Run power analysis
# ============================================================
report_power

# ============================================================
# Step 5: Run IR drop analysis
# ============================================================
set_pg_analysis_mode -power_grid_analysis static \
    -voltage_from_pg_pin true

analyze_power_grid -net VDD
analyze_power_grid -net VSS

# ============================================================
# Step 6: Report results
# ============================================================
report_power_rail -net VDD -type ir_drop
report_power_rail -net VSS -type ir_drop

# Write IR drop map
report_power_rail -net VDD -type ir_drop -output_file output/ir_drop_vdd.rpt
```

### report_power_rail

```tcl
# IR drop report for VDD
report_power_rail -net VDD -type ir_drop

# IR drop report for VSS
report_power_rail -net VSS -type ir_drop

# Detailed report with thresholds
report_power_rail -net VDD -type ir_drop \
    -threshold 0.010 \
    -output_file reports/ir_drop_vdd.rpt

# Current density report
report_power_rail -net VDD -type current_density

# Voltage report
report_power_rail -net VDD -type voltage

# Report by layer
report_power_rail -net VDD -type ir_drop -layer M8

# Report by instance
report_power_rail -net VDD -type ir_drop -inst_report \
    -output_file reports/ir_drop_by_inst.rpt

# Summary report
report_power_rail -net VDD -type ir_drop -summary

# Worst-case instances
report_power_rail -net VDD -type ir_drop \
    -worst_instances 100 \
    -output_file reports/worst_ir_instances.rpt
```

### set_pg_analysis_mode

```tcl
# Static analysis mode
set_pg_analysis_mode -power_grid_analysis static

# Dynamic analysis mode
set_pg_analysis_mode -power_grid_analysis dynamic

# Time-based analysis
set_pg_analysis_mode -power_grid_analysis time_based

# Options
set_pg_analysis_mode -power_grid_analysis static \
    -voltage_from_pg_pin true \
    -ignore_incomplete_pg_connection false \
    -enable_pg_grid_short_check true

# EM analysis mode
set_pg_analysis_mode -power_grid_analysis static \
    -enable_em_analysis true
```

### analyze_power_grid

```tcl
# Analyze VDD grid
analyze_power_grid -net VDD

# Analyze VSS grid
analyze_power_grid -net VSS

# Analyze all power nets
analyze_power_grid -net {VDD VDD_CORE VDD_IO}

# Analyze with options
analyze_power_grid -net VDD \
    -voltage_from_pg_pin true

# Write analysis results
analyze_power_grid -net VDD \
    -output_dir output/pg_analysis
```

---

## Dynamic IR Drop Analysis

### set_dynamic_power_simulation

Configure dynamic power simulation for time-based IR analysis.

```tcl
# ============================================================
# Dynamic IR Flow
# ============================================================

# Step 1: Read VCD
read_activity_file -format VCD -scope top_tb/dut \
    -start_time 100ns -end_time 200ns \
    /simulation/dump.vcd

# Step 2: Set dynamic analysis mode
set_power_analysis_mode -method dynamic \
    -analysis_view av_wc_func

# Step 3: Configure dynamic simulation
set_dynamic_power_simulation -resolution 0.01ns

# Step 4: Set PG analysis for dynamic
set_pg_analysis_mode -power_grid_analysis dynamic

# Step 5: Run analysis
analyze_power_grid -net VDD

# Step 6: Report
report_power_rail -net VDD -type ir_drop
```

### Dynamic Simulation Options

```tcl
# Set simulation resolution
set_dynamic_power_simulation -resolution 0.010

# Set simulation window
set_dynamic_power_simulation -start_time 100.0 -end_time 200.0

# Set number of cycles
set_dynamic_power_simulation -num_cycles 10

# VCD-based dynamic
set_dynamic_power_simulation -input_vcd /sim/dump.vcd \
    -vcd_scope top_tb/dut

# FSDB-based dynamic
set_dynamic_power_simulation -input_fsdb /sim/dump.fsdb \
    -fsdb_scope top_tb/dut

# Worst-case dynamic
set_dynamic_power_simulation -worst_case true

# Event-driven simulation
set_dynamic_power_simulation -event_driven true
```

### Dynamic IR Report

```tcl
# Time-based IR report
report_power_rail -net VDD -type ir_drop -time_based

# Peak dynamic IR
report_power_rail -net VDD -type ir_drop -peak

# Average dynamic IR
report_power_rail -net VDD -type ir_drop -average

# Dynamic IR at specific time
report_power_rail -net VDD -type ir_drop -time 150.5

# Generate waveform data
report_power_rail -net VDD -type ir_drop \
    -waveform -output_file output/ir_waveform.csv
```

---

## Electromigration (EM) Analysis

### EM Setup

```tcl
# Enable EM analysis
set_pg_analysis_mode -power_grid_analysis static \
    -enable_em_analysis true

# Set EM technology rules
set_em_tech_rule -current_density_limit {
    M1 1.0e6
    M2 1.5e6
    M3 2.0e6
    M4 2.5e6
    M5 3.0e6
    M6 3.5e6
    M7 4.0e6
    M8 5.0e6
    M9 6.0e6
    AP 8.0e6
}

# Set EM temperature
set_db em_temperature 125.0

# Set EM lifetime
set_db em_target_lifetime 10.0 ;# years
```

### report_em_violation

```tcl
# Report all EM violations
report_em_violation

# Report EM for specific net
report_em_violation -net VDD

# Report with threshold
report_em_violation -threshold 80.0 ;# 80% of limit

# Report by layer
report_em_violation -layer M1
report_em_violation -layer {M1 M2 M3}

# Report worst violations
report_em_violation -worst 100

# Report to file
report_em_violation -output_file reports/em_violations.rpt

# Detailed EM report
report_em_violation -detail -output_file reports/em_detail.rpt

# Report EM for signal nets
report_em_violation -net_type signal

# Report EM for power nets
report_em_violation -net_type power

# Summary
report_em_violation -summary
```

### EM Analysis Options

```tcl
# Average current EM
set_em_analysis_mode -type average

# RMS current EM
set_em_analysis_mode -type rms

# Peak current EM
set_em_analysis_mode -type peak

# Set current density limit multiplier
set_em_analysis_mode -limit_multiplier 0.8

# Consider AC vs DC EM
set_em_analysis_mode -ac_analysis true
set_em_analysis_mode -dc_analysis true
```

---

## Power Grid Analysis

### check_power_grid

Comprehensive power grid integrity check.

```tcl
# Basic power grid check
check_power_grid

# Check specific net
check_power_grid -net VDD

# Check all power nets
check_power_grid -net {VDD VSS VDD_CORE VDD_IO}

# Detailed check
check_power_grid -detail

# Check with EM
check_power_grid -em

# Check connectivity
check_power_grid -connectivity

# Report to file
check_power_grid -output_file reports/pg_check.rpt
```

### Power Grid Visualization

```tcl
# Generate IR drop map
generate_pg_map -net VDD -type ir_drop

# Generate current density map
generate_pg_map -net VDD -type current_density

# Generate EM map
generate_pg_map -net VDD -type em_violation

# Generate voltage map
generate_pg_map -net VDD -type voltage

# Customize map settings
set_pg_map_settings -resolution high \
    -color_scale auto \
    -threshold 0.010
```

### Power Grid Debug

```tcl
# Find disconnected instances
find_pg_disconnect -net VDD

# Report open connections
report_pg_open -net VDD

# Report short circuits
report_pg_short

# Report via resistance
report_pg_via_resistance -net VDD

# Report wire resistance
report_pg_wire_resistance -net VDD -layer M8

# Report power grid density
report_pg_density -net VDD

# Report power grid summary
report_pg_summary
```

---

## Switching Activity

### read_activity_file

Reads simulation activity data.

```tcl
# Read VCD file
read_activity_file -format VCD \
    -scope top_tb/dut \
    /simulation/dump.vcd

# Read VCD with time window
read_activity_file -format VCD \
    -scope top_tb/dut \
    -start_time 100ns -end_time 200ns \
    /simulation/dump.vcd

# Read SAIF file
read_activity_file -format SAIF \
    -scope top_chip \
    /simulation/top.saif

# Read FSDB file
read_activity_file -format FSDB \
    -scope top_tb/dut \
    /simulation/dump.fsdb

# Read TCF (Toggle Count Format)
read_activity_file -format TCF \
    /simulation/top.tcf
```

**read_activity_file options:**

| Option | Description |
|--------|-------------|
| `-format <fmt>` | `VCD`, `SAIF`, `FSDB`, `TCF` |
| `-scope <path>` | Hierarchical scope in simulation |
| `-start_time <time>` | Start time for activity window |
| `-end_time <time>` | End time for activity window |
| `-block <name>` | Apply to specific block |

### set_switching_activity

Set switching activity manually (vectorless mode).

```tcl
# Set default switching activity
set_default_switching_activity -input_activity 0.2 \
    -period 2.0

# Set activity on specific ports
set_switching_activity -input_port_activity 0.5 \
    -port [get_ports data_in*]

# Set activity on specific nets
set_switching_activity -activity 0.3 \
    -net [get_nets bus_data*]

# Set static probability
set_switching_activity -static_probability 0.5 \
    -net [get_nets *]

# Set toggle rate
set_switching_activity -toggle_rate 0.2 \
    -net [get_nets *]

# Set activity on clock
set_switching_activity -activity 2.0 \
    -net [get_nets clk]

# Set activity on sequential outputs
set_switching_activity -activity 0.1 \
    -sequential_output

# Set memory activity
set_switching_activity -activity 0.3 \
    -inst [get_cells u_sram*]

# Hierarchical activity
set_switching_activity -hierarchy u_core -activity 0.25

# Reset all activity
reset_switching_activity
```

### Activity Propagation

```tcl
# Propagate switching activity
propagate_switching_activity

# Propagate with options
propagate_switching_activity -effort high

# Report activity statistics
report_switching_activity
report_switching_activity -net [get_nets *clk*]
```

---

## Thermal Analysis

### Thermal Integration

```tcl
# Read thermal model
read_thermal_model /libs/tech/thermal_model.tcl

# Set thermal map
set_thermal_map -file /thermal/thermal_map.csv

# Set ambient temperature
set_db thermal_ambient_temperature 25.0

# Set thermal conductivity
set_thermal_conductivity -layer M1 100.0

# Run thermal-aware power analysis
set_power_analysis_mode -method static \
    -analysis_view av_wc_func \
    -thermal_aware true

# Report thermal results
report_thermal -output_file reports/thermal.rpt
```

### Temperature-Dependent Analysis

```tcl
# Set operating temperature
set_db power_temperature 125.0

# Temperature map-based analysis
read_temperature_map /thermal/temp_map.csv

# Run analysis with temperature variation
analyze_power_grid -net VDD -temperature_dependent true

# Report temperature-dependent IR
report_power_rail -net VDD -type ir_drop -temperature_dependent
```

---

## Power Reporting

### report_power (Complete Reference)

```tcl
# ============================================================
# Basic Power Reports
# ============================================================

# Total power summary
report_power

# Hierarchical power
report_power -hierarchy all

# Top-level only
report_power -hierarchy top

# Specific hierarchy depth
report_power -hierarchy 3

# ============================================================
# Power Breakdown Types
# ============================================================

# Leakage power
report_power -leakage

# Internal (switching) power
report_power -internal

# Switching (dynamic) power
report_power -switching

# All components
report_power -detail

# ============================================================
# Filtering
# ============================================================

# By instance
report_power -inst [get_cells u_core]

# By module
report_power -module u_core

# By cell type
report_power -cell_type BUFX4

# By clock domain
report_power -clock_domain sys_clk

# By power domain
report_power -power_domain PD_core

# ============================================================
# Format Options
# ============================================================

# Output to file
report_power -hierarchy all -detail > reports/power.rpt

# CSV format
report_power -format csv -output_file reports/power.csv

# Verbose
report_power -verbose

# Per-instance
report_power -per_instance > reports/power_per_inst.rpt

# ============================================================
# Multi-View Power
# ============================================================

# Specific view
report_power -view av_wc_func

# All views
report_power -view {av_wc_func av_tc_func}
```

### Power Report Details

```tcl
# Gate-level power
report_gates -power

# Sequential vs combinational power
report_power -sequential
report_power -combinational

# Clock network power
report_power -clock_network

# Memory power
report_power -memories

# IO power
report_power -io

# Power density
report_power -density

# Power efficiency
report_power -efficiency
```

---

## Advanced Analysis Features

### Rail Analysis with Package Model

```tcl
# Read package model
read_package_model /libs/package/package.spice
read_package_model /libs/package/package.s2p

# Set package model
set_package_model -file /libs/package/package.spice \
    -pin_map /libs/package/pin_map.tcl

# Run analysis with package
analyze_power_grid -net VDD -include_package true

# Report with package
report_power_rail -net VDD -type ir_drop -include_package
```

### Decoupling Capacitor Analysis

```tcl
# Add decap cells
set_db decap_cells {DCAP4 DCAP8 DCAP16}

# Analyze decap effectiveness
analyze_decap -net VDD

# Report decap
report_decap -net VDD

# Optimize decap placement
optimize_decap -net VDD -target_ir 0.010
```

### Power State Analysis

```tcl
# Define power states
create_power_state -name active -voltage {VDD 0.85}
create_power_state -name sleep -voltage {VDD 0.0}
create_power_state -name retention -voltage {VDD 0.60}

# Analyze per state
set_power_state active
report_power
analyze_power_grid -net VDD

set_power_state sleep
report_power -leakage
```

### Noise Analysis Integration

```tcl
# Enable noise-aware IR analysis
set_pg_analysis_mode -power_grid_analysis static \
    -noise_aware true

# Report noise-induced IR
report_power_rail -net VDD -type ir_drop -noise_aware
```

---

## Output and Export

### Write Results

```tcl
# Write power database
write_power_db output/power.db

# Write IR drop data
write_ir_drop_data -net VDD -output output/ir_drop_vdd.data

# Write EM data
write_em_data -output output/em_data.rpt

# Write power data for signoff
write_power_data -output output/power_signoff.data

# Write current map
write_current_map -net VDD -output output/current_map.csv

# Write voltage map
write_voltage_map -net VDD -output output/voltage_map.csv
```

### Export for Downstream Tools

```tcl
# Export for Tempus (timing derating from IR)
write_timing_derate_from_ir -output output/ir_derates.tcl

# Export power constraints
write_power_constraints -output output/power_constraints.tcl

# Export for board-level analysis
write_package_current -output output/package_current.csv
```

### Generate Visual Reports

```tcl
# Generate HTML report
report_power -format html -output_file output/power_report.html

# Generate power map (for GUI visualization)
generate_pg_map -net VDD -type ir_drop -output output/ir_map
generate_pg_map -net VDD -type current_density -output output/jmap
generate_pg_map -net VDD -type em_violation -output output/em_map
```

---

## Utility Commands

### Multi-Threading

```tcl
# Set CPU usage
set_multi_cpu_usage -local_cpu 8

# Distributed processing
set_multi_cpu_usage -remote_host 4
```

### Memory Management

```tcl
# Report memory
report_resource -memory

# Set memory limit
set_resource -memory_limit 32G
```

### Session Management

```tcl
# Save session
write_db output/voltus_session.db

# Restore session
read_db output/voltus_session.db

# Log file
set_log_file output/voltus.log
```

### Design Queries

```tcl
# Power net info
get_db [get_nets VDD] .is_power
get_db [get_nets VSS] .is_ground

# Instance power info
get_db [get_cells u_core] .power

# Get all power nets
get_nets -filter {is_power == true}
get_nets -filter {is_ground == true}
```

---

## Quick Reference: Complete Voltus Analysis Flow

```tcl
#============================================================
# Voltus Power/IR/EM Analysis -- Production Template
#============================================================

# Design read-in
read_lib {ss_0p75v_125c.lib sram_ss.lib}
read_lef {tech.lef stdcells.lef sram.lef}
read_verilog /output/innovus/top_chip.v
set_top_module top_chip
read_def /output/innovus/top_chip.def
read_spef /extraction/top_chip.spef
read_sdc /constraints/top_chip.sdc

# Power net setup
globalNetConnect VDD -type pgpin -pin VDD -all
globalNetConnect VSS -type pgpin -pin VSS -all

# ============================================================
# Static Power Analysis
# ============================================================
set_power_analysis_mode -method static -analysis_view av_wc_func
set_default_switching_activity -input_activity 0.2 -period 2.0
report_power -hierarchy all > reports/power_static.rpt

# ============================================================
# Static IR Drop Analysis
# ============================================================
set_pg_analysis_mode -power_grid_analysis static \
    -voltage_from_pg_pin true
analyze_power_grid -net VDD
analyze_power_grid -net VSS
report_power_rail -net VDD -type ir_drop > reports/ir_drop_vdd.rpt
report_power_rail -net VSS -type ir_drop > reports/ir_drop_vss.rpt

# ============================================================
# EM Analysis
# ============================================================
set_pg_analysis_mode -enable_em_analysis true
report_em_violation -output_file reports/em_violations.rpt

# ============================================================
# Dynamic IR Drop Analysis
# ============================================================
read_activity_file -format VCD -scope top_tb/dut \
    -start_time 100ns -end_time 200ns /sim/dump.vcd
set_power_analysis_mode -method dynamic -analysis_view av_wc_func
set_pg_analysis_mode -power_grid_analysis dynamic
analyze_power_grid -net VDD
report_power_rail -net VDD -type ir_drop -time_based > reports/dynamic_ir.rpt

# ============================================================
# Power Grid Integrity Check
# ============================================================
check_power_grid -net {VDD VSS} -output_file reports/pg_check.rpt

# Save session
write_db output/voltus_session.db

puts "Voltus analysis complete."
```

---

## Voltus Command Index (Alphabetical)

| Command | Category | Description |
|---------|----------|-------------|
| `analyze_decap` | Advanced | Analyze decoupling capacitors |
| `analyze_power_grid` | IR | Run power grid analysis |
| `check_power_grid` | PG Check | Check power grid integrity |
| `find_pg_disconnect` | Debug | Find disconnected PG |
| `generate_pg_map` | Visual | Generate power grid map |
| `globalNetConnect` | Setup | Connect global power nets |
| `propagate_switching_activity` | Activity | Propagate activity |
| `read_activity_file` | Import | Read VCD/SAIF/FSDB |
| `read_def` | Import | Read DEF |
| `read_lef` | Import | Read LEF |
| `read_lib` | Import | Read Liberty |
| `read_package_model` | Import | Read package model |
| `read_spef` | Import | Read SPEF |
| `read_thermal_model` | Import | Read thermal model |
| `read_verilog` | Import | Read netlist |
| `report_em_violation` | EM | Report EM violations |
| `report_pg_density` | Report | Report PG density |
| `report_pg_summary` | Report | Report PG summary |
| `report_power` | Report | Report power analysis |
| `report_power_rail` | IR | Report IR drop/current |
| `report_switching_activity` | Report | Report activity |
| `report_thermal` | Report | Report thermal |
| `set_default_switching_activity` | Activity | Set default activity |
| `set_dynamic_power_simulation` | Dynamic | Configure dynamic sim |
| `set_em_analysis_mode` | EM | Configure EM analysis |
| `set_pg_analysis_mode` | Analysis | Set PG analysis mode |
| `set_power_analysis_mode` | Analysis | Set power analysis mode |
| `set_switching_activity` | Activity | Set activity on objects |
| `write_db` | Export | Save session |
| `write_ir_drop_data` | Export | Write IR drop data |
| `write_power_data` | Export | Write power data |
| `write_power_db` | Export | Write power database |
