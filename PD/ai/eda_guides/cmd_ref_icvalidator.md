# Synopsys IC Validator Command Reference

Comprehensive command reference for Synopsys IC Validator (ICV), the physical
verification signoff tool. Covers DRC, LVS, metal fill, PERC (electrical rule
checking), distributed processing, and in-design integration with Fusion
Compiler / IC Compiler II.

ICV version baseline: T-2022.03 and later.

---

## Table of Contents

1. [Overview and Invocation](#1-overview-and-invocation)
2. [DRC — Design Rule Checking](#2-drc--design-rule-checking)
3. [LVS — Layout vs. Schematic](#3-lvs--layout-vs-schematic)
4. [Metal Fill](#4-metal-fill)
5. [PERC — Electrical Rule Checking](#5-perc--electrical-rule-checking)
6. [Rule File Syntax](#6-rule-file-syntax)
7. [Layer Definitions and Operations](#7-layer-definitions-and-operations)
8. [Check Commands](#8-check-commands)
9. [Distributed / Parallel Processing](#9-distributed--parallel-processing)
10. [In-Design Integration](#10-in-design-integration)
11. [Output and Reporting](#11-output-and-reporting)
12. [Complete Flow Examples](#12-complete-flow-examples)

---

## 1. Overview and Invocation

ICV can be invoked standalone or from within FC/ICC2 (in-design mode).

### Standalone Invocation

```bash
# DRC
icv -i chip_top.gds -c chip_top -f drc_rules.rs -sf results_dir

# LVS
icv -i chip_top.gds -c chip_top -f lvs_rules.rs -sf results_dir

# With options file
icv -dp 16 -i chip_top.gds -c chip_top -f drc_rules.rs -sf results_dir

# Metal fill
icv -i chip_top.gds -c chip_top -f fill_rules.rs -sf results_dir
```

### Common Command-Line Options

| Option | Description |
|---|---|
| `-i <file>` | Input layout file (GDS, OASIS) |
| `-c <cell>` | Top cell name |
| `-f <file>` | Rule file (runset) |
| `-sf <dir>` | Results directory |
| `-dp <N>` | Number of distributed processors |
| `-mt <N>` | Number of threads per processor |
| `-64` | 64-bit mode |
| `-o <file>` | Output error database |
| `-E` | Error limit per rule |
| `-v` | Verbose output |
| `-s <file>` | SVRF/ICV setup file |

### Full Invocation Examples

```bash
# DRC with 16 distributed processes, 4 threads each
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/drc_rules.rs \
  -sf ./drc_results \
  -dp 16 -mt 4 \
  2>&1 | tee icv_drc.log

# LVS
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/lvs_rules.rs \
  -sf ./lvs_results \
  -dp 8 -mt 4 \
  -s ./lvs_setup.rs \
  2>&1 | tee icv_lvs.log

# Metal fill
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/fill_rules.rs \
  -sf ./fill_results \
  -dp 16 \
  2>&1 | tee icv_fill.log
```

---

## 2. DRC -- Design Rule Checking

### DRC Rule File Structure

```
// DRC Rule File: drc_rules.rs

// Include foundry rule deck
#include "/pdk/icv/saed14nm_drc.rs"

// Setup
layout_path = "chip_top.gds"
layout_primary = "chip_top"
results_db_path = "./drc_results"

// Layer definitions
M1       = layer_map(1, 0)
M1_DRW   = M1
VIA1     = layer_map(2, 0)
M2       = layer_map(3, 0)

// DRC checks
// Minimum width
rule M1_MIN_WIDTH {
  caption "M1 minimum width = 0.040um"
  internal(M1, < 0.040, extension = NONE)
}

// Minimum spacing
rule M1_MIN_SPACE {
  caption "M1 minimum spacing = 0.040um"
  external(M1, < 0.040)
}
```

### DRC Command-Line

```bash
# Basic DRC
icv -i chip_top.gds -c chip_top -f drc_rules.rs -sf ./drc_results

# DRC with error limit
icv -i chip_top.gds -c chip_top -f drc_rules.rs -sf ./drc_results -E 1000

# DRC for specific rules only
icv -i chip_top.gds -c chip_top -f drc_rules.rs -sf ./drc_results \
  -rr "M1_MIN_WIDTH M1_MIN_SPACE"
```

### DRC Error Output

```
// View DRC results
// Results are stored in the -sf directory as an error database
// Can be viewed with:
//   - ICV Workbench (GUI)
//   - Loaded into FC/ICC2 GUI
//   - Converted to ASCII: icv_error_viewer
```

---

## 3. LVS -- Layout vs. Schematic

### LVS Rule File Structure

```
// LVS Rule File: lvs_rules.rs

// Include foundry LVS deck
#include "/pdk/icv/saed14nm_lvs.rs"

// Setup
layout_path     = "chip_top.gds"
layout_primary  = "chip_top"
source_path     = "chip_top.cdl"
source_primary  = "chip_top"
results_db_path = "./lvs_results"

// Power/Ground connectivity
connect_global(VDD)
connect_global(VSS)

// Device recognition (usually in foundry deck)
// NMOS definition
device NMOS(gate, source, drain, bulk) {
  gate   = POLY and ACTIVE and NPLUS
  source = ACTIVE and NPLUS
  drain  = ACTIVE and NPLUS
  bulk   = PWELL
}

// PMOS definition
device PMOS(gate, source, drain, bulk) {
  gate   = POLY and ACTIVE and PPLUS
  source = ACTIVE and PPLUS
  drain  = ACTIVE and PPLUS
  bulk   = NWELL
}

// Property checking
property NMOS(W, L)
property PMOS(W, L)

// Comparison
compare
```

### LVS Setup File

```
// lvs_setup.rs

// Source netlist (schematic)
source_path     = "./netlist/chip_top.cdl"
source_primary  = "chip_top"

// Alternative: Verilog netlist
// source_path     = "./netlist/chip_top.v"
// source_format   = VERILOG

// Box (black-box) cells — cells without layout
lvs_box_cell = "analog_block pll_core"

// Ignore cells
lvs_ignore_cell = "FILL* DECAP* TAP*"

// Power/ground net names
power_name = "VDD VDDH VDD_RET"
ground_name = "VSS"

// Soft-connect (merge nets that should be the same)
lvs_softconnect = "VDD VDDH"

// Property tolerance
property_tolerance NMOS(W=0.001, L=0.001)
property_tolerance PMOS(W=0.001, L=0.001)
```

### LVS Command-Line

```bash
# Full LVS
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/lvs_rules.rs \
  -sf ./lvs_results \
  -s ./lvs_setup.rs \
  -dp 8

# LVS with Verilog source
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/lvs_rules.rs \
  -sf ./lvs_results \
  -src ./netlist/chip_top.v \
  -src_format VERILOG \
  -dp 8
```

### LVS Results

```
// LVS results include:
//   - Match/mismatch summary
//   - Device count comparison
//   - Net count comparison
//   - Unmatched devices
//   - Unmatched nets
//   - Property mismatches
//   - Short/open reports

// View with ICV Workbench or parse the summary file
```

### LVS-Specific Directives

```
// Compare options
compare {
  // Tolerance for device matching
  property_tolerance NMOS(W=0.001, L=0.001)
  property_tolerance PMOS(W=0.001, L=0.001)

  // Swappable pins
  swap_pin NAND2(A, B)
  swap_pin NOR2(A, B)

  // Permutable devices
  permute_device(NMOS)
  permute_device(PMOS)

  // Max mismatches to report
  max_mismatch = 1000

  // Report level
  report_level = VERBOSE
}
```

---

## 4. Metal Fill

### Metal Fill Rule File

```
// fill_rules.rs

// Include foundry fill deck
#include "/pdk/icv/saed14nm_fill.rs"

// Setup
layout_path     = "chip_top.gds"
layout_primary  = "chip_top"
results_db_path = "./fill_results"

// Layer definitions
M1 = layer_map(1, 0)
M2 = layer_map(3, 0)
M3 = layer_map(5, 0)
M4 = layer_map(7, 0)
M5 = layer_map(9, 0)
```

### Fill Density Targets

```
// Minimum and maximum density targets per layer
density_rule M1 {
  min_density = 0.20
  max_density = 0.80
  window_size = 50.0
  window_step = 25.0
}

density_rule M2 {
  min_density = 0.20
  max_density = 0.80
  window_size = 50.0
  window_step = 25.0
}
```

### Fill Commands

```
// Basic fill insertion
fill_layer(M1) {
  fill_width  = {0.100 0.200 0.500 1.000}
  fill_height = {0.100 0.200 0.500 1.000}
  fill_space  = 0.080
  fill_to_wire_space = 0.100
  density_target = 0.60
}

// Grounded fill (connected to ground)
fill_layer(M1) {
  fill_width  = {0.200}
  fill_height = {0.200}
  fill_space  = 0.080
  fill_to_wire_space = 0.100
  density_target = 0.60
  connect_to = VSS
}
```

### Timing-Aware Fill

When integrated with FC, fill insertion considers timing impact.

```tcl
# In FC shell — timing-aware ICV fill
signoff_metal_fill \
  -runset /pdk/icv/fill_rules.rs \
  -timing_preserve_setup_slack_threshold 0.050 \
  -timing_preserve_hold_slack_threshold 0.020 \
  -select_layers {M1 M2 M3 M4 M5}
```

### Fill Generation Command-Line

```bash
# Standalone fill
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/fill_rules.rs \
  -sf ./fill_results \
  -dp 16 \
  2>&1 | tee fill.log

# Fill output as GDS
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/fill_rules.rs \
  -sf ./fill_results \
  -o ./gds/chip_top_fill.gds \
  -dp 16
```

### Fill Removal

```tcl
# In FC shell
remove_metal_fill

# Standalone — typically re-run fill from clean layout
```

---

## 5. PERC -- Electrical Rule Checking

PERC checks electrical connectivity and reliability rules.

### PERC Rule File

```
// perc_rules.rs

// ESD checks
esd_rule ESD_PATH {
  caption "ESD discharge path required from pad to supply"
  from = PAD_LAYER
  to   = VDD_RING
  max_resistance = 10.0  // ohms
}

// Latch-up checks
latchup_rule GUARD_RING {
  caption "Guard ring required around NWELL"
  check_guard_ring(NWELL, PTAP, max_distance = 15.0)
}

// Antenna checks
antenna_rule ANTENNA_M1 {
  caption "M1 antenna ratio check"
  layer = M1
  max_ratio = 400
  diode_layer = DIODE
}
```

### PERC Command-Line

```bash
icv -64 \
  -i ./gds/chip_top.gds \
  -c chip_top \
  -f /pdk/icv/perc_rules.rs \
  -sf ./perc_results \
  -dp 8 \
  2>&1 | tee perc.log
```

### PERC Checks (Common Types)

| Check | Description |
|---|---|
| ESD path | Verify discharge paths from pads to supplies |
| Latch-up | Check guard rings and well contacts |
| Antenna | Gate oxide antenna ratio checks |
| IR drop awareness | Resistive path checks |
| Back-to-back diode | ESD protection verification |
| Well connectivity | N-well and P-well tie checks |

---

## 6. Rule File Syntax

### Basic Syntax Elements

```
// Comments
// This is a line comment
/* This is a
   block comment */

// Variables
width_m1 = 0.040
space_m1 = 0.040

// Include files
#include "common_layers.rs"
#include "/pdk/icv/tech_specific.rs"

// Conditional compilation
#ifdef METAL_9
  M9 = layer_map(17, 0)
#endif
```

### Layer Definitions

```
// GDS layer mapping
M1       = layer_map(31, 0)    // layer 31, datatype 0
M1_PIN   = layer_map(31, 2)
M1_LABEL = layer_map(31, 5)
VIA1     = layer_map(32, 0)
M2       = layer_map(33, 0)

// Derived layers (Boolean operations)
M1_WIDE  = M1 sizing 0.100
M1_THIN  = M1 not M1_WIDE
ACTIVE   = NPLUS or PPLUS
GATE     = POLY and ACTIVE
```

### Boolean Operations

```
// AND (intersection)
layer_c = layer_a and layer_b

// OR (union)
layer_c = layer_a or layer_b

// NOT (subtraction)
layer_c = layer_a not layer_b

// XOR (symmetric difference)
layer_c = layer_a xor layer_b

// INTERACT (layers that touch)
layer_c = layer_a interact layer_b

// INSIDE (completely inside)
layer_c = layer_a inside layer_b

// OUTSIDE (completely outside)
layer_c = layer_a outside layer_b

// TOUCHING (edges touching)
layer_c = layer_a touching layer_b

// ENCLOSING (completely encloses)
layer_c = layer_a enclosing layer_b
```

### Sizing Operations

```
// Grow
layer_grown = layer_a sizing 0.050

// Shrink
layer_shrunk = layer_a sizing -0.050

// Directional sizing
layer_c = layer_a sizing(0.050, 0.100)  // x, y different

// Edge sizing
layer_c = edge_size(layer_a, inside = 0.050, outside = 0.050)
```

---

## 7. Layer Definitions and Operations

### Measurement Functions

```
// Width (internal spacing)
internal(layer, < min_width)
internal(layer, < min_width, extension = NONE)
internal(layer, < min_width, projection = PARALLEL)

// Spacing (external spacing)
external(layer, < min_space)
external(layer_a, layer_b, < min_space)

// Enclosure
enclosure(inner_layer, outer_layer, < min_enc)
enclosure(inner_layer, outer_layer, < min_enc_h, < min_enc_v)

// Extension
extension(layer_a, layer_b, < min_ext)

// Area
area(layer, < min_area)
area(layer, > max_area)

// Edge length
edge_length(layer, < min_length)
edge_length(layer, > max_length)

// Density
density(layer, < min_density, window = 50.0, step = 25.0)
density(layer, > max_density, window = 50.0, step = 25.0)
```

### Selection Functions

```
// Select by area
select_area(layer, >= min_area, <= max_area)

// Select by edge count
select_edge_count(layer, == 4)  // rectangles only

// Select by perimeter
select_perimeter(layer, > min_perim)

// Select by width
select_width(layer, >= min_width, <= max_width)

// Select by interaction
select_interact(layer_a, layer_b, count >= 2)

// Select touching
select_touching(layer_a, layer_b)

// Select inside
select_inside(layer_a, layer_b)

// Select with property
select_property(layer, "net_name == VDD")
```

### Edge Operations

```
// Get edges
edges_a = edge(layer_a)

// Edge interaction
edge_interact(edges_a, edges_b)

// Angle-based selection
angle_edge(layer, == 45)
angle_edge(layer, != 90)  // non-manhattan

// Convex/concave edges
convex_edge(layer)
concave_edge(layer)
```

---

## 8. Check Commands

### Width Check

```
rule MIN_WIDTH_M1 {
  caption "M1 minimum width = 0.040um"
  internal(M1, < 0.040, extension = NONE)
}
```

### Spacing Check

```
rule MIN_SPACE_M1 {
  caption "M1 minimum spacing = 0.040um"
  external(M1, < 0.040)
}

// Same-net spacing
rule SAME_NET_SPACE_M1 {
  caption "M1 same-net minimum spacing"
  internal(M1, < 0.060, opposite)
}

// Different-net spacing
rule DIFF_NET_SPACE_M1 {
  caption "M1 different-net spacing"
  external(M1, < 0.040, connect = DIFFERENT_NET)
}
```

### Enclosure Check

```
rule VIA1_ENC_M1 {
  caption "VIA1 enclosure by M1 >= 0.020"
  enclosure(VIA1, M1, < 0.020)
}

// Directional enclosure
rule VIA1_ENC_M1_DIR {
  caption "VIA1 directional enclosure by M1"
  enclosure(VIA1, M1, < 0.010, < 0.030, direction = HORIZONTAL)
}
```

### Area Check

```
rule MIN_AREA_M1 {
  caption "M1 minimum area = 0.005 sq um"
  area(M1, < 0.005)
}
```

### Width-Dependent Spacing

```
rule WDS_M1 {
  caption "M1 width-dependent spacing"
  external(M1, < 0.080, projection = PARALLEL, width >= 0.200)
  external(M1, < 0.120, projection = PARALLEL, width >= 0.500)
  external(M1, < 0.200, projection = PARALLEL, width >= 1.000)
}
```

### End-of-Line (EOL) Spacing

```
rule EOL_SPACE_M1 {
  caption "M1 end-of-line spacing"
  external(M1, < 0.060,
    extension = NONE,
    edge1_type = EOL,
    eol_width = 0.060)
}
```

### Antenna Check

```
rule ANTENNA_M1 {
  caption "M1 antenna ratio"
  antenna_check(
    gate_layer  = GATE,
    metal_layer = M1,
    max_ratio   = 400,
    diode_layer = DIODE,
    diode_ratio = 500
  )
}
```

### Density Check

```
rule DENSITY_M1 {
  caption "M1 density check"
  density(M1, < 0.20, window = 50.0, step = 25.0)  // minimum density
  density(M1, > 0.80, window = 50.0, step = 25.0)  // maximum density
}
```

### Via Count and Redundancy

```
rule MIN_VIA_COUNT {
  caption "Minimum via count for wide wires"
  via_count(VIA1, M1, width >= 0.200, min_count = 2)
}
```

---

## 9. Distributed / Parallel Processing

### Multi-Thread

```bash
# Use 8 threads on a single machine
icv -mt 8 -i chip_top.gds -c chip_top -f drc_rules.rs -sf results
```

### Distributed Processing

```bash
# Distribute across 16 processes, 4 threads each
icv -dp 16 -mt 4 -i chip_top.gds -c chip_top -f drc_rules.rs -sf results

# With host file for multi-machine
icv -dp 32 -mt 4 -hf host_file.txt \
    -i chip_top.gds -c chip_top -f drc_rules.rs -sf results
```

### Host File Format

```
# host_file.txt
# hostname  num_processes  num_threads
server1     8              4
server2     8              4
server3     8              4
server4     8              4
```

### Resource Control

```bash
# Memory limit per process
icv -dp 16 -mt 4 -mem 16000 \
    -i chip_top.gds -c chip_top -f drc_rules.rs -sf results

# Disk space control
icv -dp 16 -tmp_dir /scratch/icv_tmp \
    -i chip_top.gds -c chip_top -f drc_rules.rs -sf results
```

---

## 10. In-Design Integration

### FC In-Design DRC

```tcl
# In FC shell

# Set ICV options
set_app_options -name signoff.check_drc.runset -value /pdk/icv/drc_rules.rs
set_app_options -name signoff.check_drc.max_errors_per_rule -value 1000

# Run DRC
signoff_check_drc

# View DRC results
report_drc_errors > ./reports/drc_errors.rpt

# Auto-fix DRC violations
signoff_fix_drc -max_iterations 5

# View remaining violations
signoff_check_drc
```

### FC In-Design LVS

```tcl
# In FC shell
set_app_options -name signoff.check_lvs.runset -value /pdk/icv/lvs_rules.rs

signoff_check_lvs
```

### FC In-Design Metal Fill

```tcl
# In FC shell
set_app_options -name signoff.create_metal_fill.runset -value /pdk/icv/fill_rules.rs

# Basic fill
signoff_metal_fill

# Timing-aware fill
signoff_metal_fill \
  -timing_preserve_setup_slack_threshold 0.050 \
  -timing_preserve_hold_slack_threshold 0.020

# Selective layer fill
signoff_metal_fill -select_layers {M1 M2 M3 M4 M5}

# Remove fill
remove_metal_fill
remove_metal_fill -layers {M3 M4}  ;# Remove from specific layers only
```

### ICC2 In-Design Integration

```tcl
# In ICC2 shell
set_app_options -name signoff.check_drc.run_dir -value ./drc_results
set_app_options -name signoff.check_drc.runset -value /pdk/icv/drc_rules.rs

signoff_check_drc
signoff_fix_drc
signoff_create_metal_fill
```

---

## 11. Output and Reporting

### Error Database

```
// DRC errors are stored in the results directory (-sf)
// Files include:
//   - <rule_name>.err     — error markers
//   - summary.rpt         — summary report
//   - cell_errors.rpt     — per-cell error count
```

### ASCII Error Report

```bash
# Convert error database to ASCII
icv_error_viewer -sf ./drc_results -o ./reports/drc_ascii.rpt

# Summary only
icv_error_viewer -sf ./drc_results -summary -o ./reports/drc_summary.rpt
```

### Error Count Summary

```bash
# Quick error count
icv -sf ./drc_results -count
```

### GDS Output (for fill)

```bash
# Write fill as separate GDS
icv -i chip_top.gds -c chip_top -f fill_rules.rs \
    -sf ./fill_results \
    -o ./gds/fill_shapes.gds
```

### LVS Report

```
// LVS results include:
//   - MATCH / MISMATCH status
//   - Device comparison table
//   - Net comparison table
//   - Property comparison
//   - Unmatched devices list
//   - Unmatched nets list
//   - Short report
//   - Open report
```

---

## 12. Complete Flow Examples

### Example 1: Full DRC Flow

```bash
#!/bin/bash
# run_drc.sh

DESIGN="chip_top"
GDS_FILE="./gds/${DESIGN}.gds"
DRC_RULES="/pdk/icv/saed14nm_drc.rs"
RESULTS_DIR="./drc_results"
LOG_FILE="./logs/icv_drc.log"

# Clean previous results
rm -rf ${RESULTS_DIR}

# Run DRC
icv -64 \
  -i ${GDS_FILE} \
  -c ${DESIGN} \
  -f ${DRC_RULES} \
  -sf ${RESULTS_DIR} \
  -dp 16 -mt 4 \
  -E 10000 \
  2>&1 | tee ${LOG_FILE}

# Generate ASCII report
icv_error_viewer -sf ${RESULTS_DIR} -summary -o ./reports/drc_summary.rpt

echo "DRC complete. See ${RESULTS_DIR} for results."
```

### Example 2: Full LVS Flow

```bash
#!/bin/bash
# run_lvs.sh

DESIGN="chip_top"
GDS_FILE="./gds/${DESIGN}.gds"
SOURCE_FILE="./netlist/${DESIGN}.cdl"
LVS_RULES="/pdk/icv/saed14nm_lvs.rs"
RESULTS_DIR="./lvs_results"
LOG_FILE="./logs/icv_lvs.log"

# Clean previous results
rm -rf ${RESULTS_DIR}

# Create setup file
cat > lvs_setup.rs << 'EOF'
source_path     = "./netlist/chip_top.cdl"
source_primary  = "chip_top"
lvs_ignore_cell = "FILL* DECAP* TAPCELL*"
power_name      = "VDD"
ground_name     = "VSS"
EOF

# Run LVS
icv -64 \
  -i ${GDS_FILE} \
  -c ${DESIGN} \
  -f ${LVS_RULES} \
  -s lvs_setup.rs \
  -sf ${RESULTS_DIR} \
  -dp 8 -mt 4 \
  2>&1 | tee ${LOG_FILE}

echo "LVS complete. See ${RESULTS_DIR} for results."
```

### Example 3: Metal Fill Flow

```bash
#!/bin/bash
# run_fill.sh

DESIGN="chip_top"
GDS_FILE="./gds/${DESIGN}.gds"
FILL_RULES="/pdk/icv/saed14nm_fill.rs"
RESULTS_DIR="./fill_results"
FILL_GDS="./gds/${DESIGN}_fill.gds"
LOG_FILE="./logs/icv_fill.log"

rm -rf ${RESULTS_DIR}

icv -64 \
  -i ${GDS_FILE} \
  -c ${DESIGN} \
  -f ${FILL_RULES} \
  -sf ${RESULTS_DIR} \
  -o ${FILL_GDS} \
  -dp 16 -mt 4 \
  2>&1 | tee ${LOG_FILE}

echo "Metal fill complete. Fill GDS: ${FILL_GDS}"
```

### Example 4: In-Design FC Flow (TCL)

```tcl
# In FC shell

# === DRC ===
puts "Running in-design DRC..."
set_app_options -name signoff.check_drc.runset -value /pdk/icv/drc_rules.rs
signoff_check_drc
report_drc_errors > ./reports/drc_before_fix.rpt

# === Auto-fix DRC ===
puts "Fixing DRC violations..."
signoff_fix_drc -max_iterations 10
signoff_check_drc
report_drc_errors > ./reports/drc_after_fix.rpt

# === Metal Fill ===
puts "Inserting timing-aware metal fill..."
set_app_options -name signoff.create_metal_fill.runset -value /pdk/icv/fill_rules.rs
signoff_metal_fill \
  -timing_preserve_setup_slack_threshold 0.050 \
  -timing_preserve_hold_slack_threshold 0.020

# === Post-Fill DRC ===
puts "Running post-fill DRC..."
signoff_check_drc
report_drc_errors > ./reports/drc_post_fill.rpt

# === Write Final GDS ===
write_gds ./output/chip_top_final.gds \
  -long_names \
  -merge_gds_files [list /libs/gds/sram.gds /libs/gds/pll.gds]

puts "Physical verification complete."
```

---

### Quick Reference: ICV Command-Line Options

| Option | Description |
|---|---|
| `-i <file>` | Input layout (GDS/OASIS) |
| `-c <cell>` | Top cell name |
| `-f <file>` | Rule file / runset |
| `-sf <dir>` | Results / scratch directory |
| `-s <file>` | Setup file (overrides in rule file) |
| `-o <file>` | Output GDS (for fill) |
| `-dp <N>` | Distributed processes |
| `-mt <N>` | Threads per process |
| `-hf <file>` | Host file for multi-machine |
| `-mem <MB>` | Memory limit per process |
| `-E <N>` | Error limit per rule |
| `-rr "<rules>"` | Run only specified rules |
| `-tmp_dir <dir>` | Temporary file directory |
| `-64` | 64-bit mode |
| `-v` | Verbose |

---

*End of IC Validator Command Reference*
