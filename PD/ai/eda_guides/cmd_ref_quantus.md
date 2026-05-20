# Cadence Quantus Parasitic Extraction -- Comprehensive Command Reference

## Table of Contents

1. [Overview and Setup](#overview-and-setup)
2. [QRC Techfile Configuration](#qrc-techfile-configuration)
3. [Design Input](#design-input)
4. [Extraction Modes](#extraction-modes)
5. [Extraction Configuration](#extraction-configuration)
6. [Output Formats](#output-formats)
7. [Temperature-Dependent Extraction](#temperature-dependent-extraction)
8. [Incremental Extraction](#incremental-extraction)
9. [Distributed Extraction](#distributed-extraction)
10. [Extraction Commands Reference](#extraction-commands-reference)
11. [Reporting and Debug](#reporting-and-debug)
12. [Advanced Features](#advanced-features)
13. [Integration with Other Tools](#integration-with-other-tools)
14. [Utility Commands](#utility-commands)

---

## Overview and Setup

Cadence Quantus (formerly QRC -- Quantus RC) is the parasitic extraction engine used to generate SPEF, DSPF, or SBPF parasitic data from routed physical designs. It can run standalone or integrated within Innovus and Tempus.

### Standalone Invocation

```bash
# Launch Quantus standalone
quantus -cmd quantus_setup.tcl

# Launch with specific tech file
quantus -tech_file /libs/tech/qrcTechFile

# Batch mode
quantus -cmd extract.tcl -log quantus.log -overwrite
```

### Within Innovus

```tcl
# Extraction within Innovus (uses built-in Quantus engine)
setExtractRCMode -engine postRoute
setExtractRCMode -effortLevel signoff

# Run extraction
extractRC

# Write SPEF
rcOut -spef output/top_chip.spef
```

---

## QRC Techfile Configuration

### Techfile Setup

The QRC techfile (.tch or qrcTechFile) contains process-specific interconnect parameters.

```tcl
# Specify techfile
set_qrc_tech -file /libs/tech/qrcTechFile

# Specify techfile with temperature
set_qrc_tech -file /libs/tech/qrcTechFile -temperature 125

# Specify corner-specific techfile
set_qrc_tech -file /libs/tech/qrcTechFile_wc  ;# worst case
set_qrc_tech -file /libs/tech/qrcTechFile_bc  ;# best case
set_qrc_tech -file /libs/tech/qrcTechFile_tc  ;# typical

# In MMMC, assign techfile per RC corner
create_rc_corner -name rc_wc -qrc_tech /libs/tech/qrcTechFile -T 125
create_rc_corner -name rc_bc -qrc_tech /libs/tech/qrcTechFile -T -40
create_rc_corner -name rc_tc -qrc_tech /libs/tech/qrcTechFile -T 25
```

### Techfile Contents (Conceptual)

A QRC techfile typically contains:
- Metal layer stack information (thickness, width, spacing)
- Dielectric constants (ILD, IMD)
- Resistivity per layer
- Via resistance values
- Temperature coefficients
- Process variation parameters

```tcl
# Verify techfile
report_qrc_tech

# Report layer information from techfile
report_qrc_tech -layer_info

# Report process corners in techfile
report_qrc_tech -corners
```

---

## Design Input

### Reading Design Data

```tcl
# ============================================================
# Standalone Quantus Input
# ============================================================

# Read LEF
read_lef /libs/tech/tech.lef
read_lef /libs/stdcells/stdcells.lef
read_lef /libs/sram/sram.lef

# Read DEF (routed design)
read_def /output/innovus/top_chip.def

# Read GDS (for field solver extraction)
read_gds /output/innovus/top_chip.gds \
    -layer_map /libs/tech/gds_layermap.map

# ============================================================
# Within Innovus
# ============================================================

# Design already loaded; set extraction mode
setExtractRCMode -engine postRoute
setExtractRCMode -effortLevel signoff
setExtractRCMode -coupled true
```

### Design Preparation

```tcl
# Verify design for extraction
check_extraction_readiness

# Verify connectivity
verify_connectivity

# Set extraction boundary
set_extraction_boundary -box {0 0 1000 1000}

# Set extraction area (partial extraction)
set_extraction_area -area {100 200 500 600}
```

---

## Extraction Modes

### Coupled Extraction

Includes coupling capacitances between neighboring nets. Required for SI-aware timing.

```tcl
# Enable coupled extraction
setExtractRCMode -coupled true

# Coupled extraction with coupling cap threshold
setExtractRCMode -coupled true -coupling_c_th 0.001  ;# in fF

# Coupled extraction with aggressors
setExtractRCMode -coupled true -total_c_th 0.01

# Full coupled RC
setExtractRCMode -engine postRoute \
    -effortLevel signoff \
    -coupled true

# Run extraction
extractRC
```

### Decoupled Extraction

Lumps all coupling caps to ground. Faster but less accurate for SI.

```tcl
# Decoupled (total cap) extraction
setExtractRCMode -coupled false

# Decoupled with specific settings
setExtractRCMode -engine postRoute \
    -effortLevel medium \
    -coupled false

extractRC
```

### Field Solver Extraction

Most accurate extraction using 3D field solver. Slowest but highest accuracy.

```tcl
# Enable field solver
setExtractRCMode -engine postRoute \
    -effortLevel signoff \
    -fieldSolver true

# Field solver for specific nets
setExtractRCMode -fieldSolver true \
    -fieldSolverNets [get_nets critical_net*]

# Field solver with settings
setExtractRCMode -fieldSolverAccuracy high
setExtractRCMode -fieldSolverMaxFreq 5e9  ;# 5 GHz
```

### Extraction Effort Levels

```tcl
# Low effort (fastest, least accurate)
setExtractRCMode -effortLevel low

# Medium effort
setExtractRCMode -effortLevel medium

# High effort (signoff-quality)
setExtractRCMode -effortLevel signoff

# Detail extraction
setExtractRCMode -effortLevel detail
```

### Comparison of Modes

| Mode | Coupling Caps | Accuracy | Speed | Use Case |
|------|---------------|----------|-------|----------|
| Decoupled, Low | No | Low | Fastest | Early estimation |
| Decoupled, Medium | No | Medium | Fast | Pre-route timing |
| Coupled, Medium | Yes | Medium-High | Medium | Post-route timing |
| Coupled, Signoff | Yes | High | Slow | Signoff timing |
| Field Solver | Yes | Highest | Slowest | Critical nets, RF |

---

## Extraction Configuration

### setExtractRCMode (Complete Reference)

```tcl
# ============================================================
# Engine Selection
# ============================================================

# Post-route engine (standard for signoff)
setExtractRCMode -engine postRoute

# Pre-route engine (estimation)
setExtractRCMode -engine preRoute

# ============================================================
# Effort and Accuracy
# ============================================================

setExtractRCMode -effortLevel signoff    ;# low|medium|signoff|detail
setExtractRCMode -coupled true           ;# enable coupling caps
setExtractRCMode -coupling_c_th 0.001    ;# coupling cap threshold (fF)
setExtractRCMode -total_c_th 0.01        ;# total cap threshold (fF)

# ============================================================
# RC Reduction
# ============================================================

setExtractRCMode -reduce true            ;# enable RC reduction
setExtractRCMode -reduce_model star      ;# star|pi|elmore
setExtractRCMode -max_freq 2e9           ;# max frequency for reduction

# ============================================================
# Via and Contact Modeling
# ============================================================

setExtractRCMode -via_extraction true
setExtractRCMode -via_cap true
setExtractRCMode -via_res true

# ============================================================
# Layer-Specific Controls
# ============================================================

setExtractRCMode -topLayer M9
setExtractRCMode -bottomLayer M1

# ============================================================
# Special Extraction Options
# ============================================================

# Metal fill aware
setExtractRCMode -metalFillAware true

# Consider power/ground nets
setExtractRCMode -includePGnets true

# Include clock nets (separate extraction)
setExtractRCMode -clockNets true

# Lef-based extraction (for pre-route)
setExtractRCMode -lefTechFileDistanceFactor 1.0

# ============================================================
# Debug and Verbose
# ============================================================

setExtractRCMode -verbose true
setExtractRCMode -debug_level 3

# ============================================================
# Reset All Modes
# ============================================================

setExtractRCMode -reset
```

### extractRC

The main extraction command.

```tcl
# Run full extraction
extractRC

# Extract specific nets
extractRC -nets [get_nets data_bus*]

# Extract with output file
extractRC -outfile output/top_chip.spef

# Extract and keep detailed model
extractRC -detailed
```

---

## Output Formats

### SPEF (Standard Parasitic Exchange Format)

The most common output format for STA tools.

```tcl
# Write SPEF (from Innovus)
rcOut -spef output/top_chip.spef

# Write SPEF for specific RC corner
rcOut -spef output/top_chip_wc.spef -rc_corner rc_wc
rcOut -spef output/top_chip_bc.spef -rc_corner rc_bc

# Write SPEF with options
rcOut -spef output/top_chip.spef \
    -rcBased \
    -precision 6 \
    -cleanName

# Write compressed SPEF
rcOut -spef output/top_chip.spef.gz

# SPEF for specific nets
rcOut -spef output/critical_nets.spef \
    -net [get_nets critical_*]

# Reduced SPEF (smaller file)
rcOut -spef output/top_chip_reduced.spef -reduce

# SPEF with coupled caps
rcOut -spef output/top_chip_coupled.spef -coupled

# SPEF without coupling (total cap only)
rcOut -spef output/top_chip_total.spef -total_c_only
```

**rcOut SPEF options:**

| Option | Description |
|--------|-------------|
| `-spef <file>` | Output SPEF file path |
| `-rc_corner <name>` | RC corner name |
| `-precision <N>` | Floating-point precision |
| `-reduce` | Write reduced parasitics |
| `-coupled` | Include coupling caps |
| `-total_c_only` | Write total cap only (no coupling) |
| `-net <nets>` | Extract specific nets only |
| `-cleanName` | Clean net/inst names |
| `-rcBased` | RC-based reduction |

### DSPF (Detailed Standard Parasitic Format)

More detailed than SPEF, contains full RC network.

```tcl
# Write DSPF
rcOut -dspf output/top_chip.dspf

# Write DSPF for specific corner
rcOut -dspf output/top_chip_wc.dspf -rc_corner rc_wc

# Write DSPF for specific nets
rcOut -dspf output/critical.dspf -net [get_nets critical_*]

# DSPF with specific precision
rcOut -dspf output/top_chip.dspf -precision 8
```

### SBPF (Synopsys Binary Parasitic Format)

Binary format for faster read/write, used by some tools.

```tcl
# Write SBPF
rcOut -sbpf output/top_chip.sbpf

# Read SBPF (in timing tool)
read_parasitics -format sbpf output/top_chip.sbpf
```

### Format Comparison

| Format | Size | Read Speed | Detail Level | Coupling | Primary Use |
|--------|------|------------|--------------|----------|-------------|
| SPEF | Medium | Fast | Configurable | Optional | STA, power analysis |
| DSPF | Large | Slow | Full detail | Yes | SPICE simulation |
| SBPF | Small | Fastest | Configurable | Optional | Fast STA reads |

---

## Temperature-Dependent Extraction

### Temperature Configuration

```tcl
# Set extraction temperature
setExtractRCMode -temperature 125.0

# Temperature-dependent extraction (multiple temperatures)
setExtractRCMode -temperature 125.0
extractRC
rcOut -spef output/top_chip_125c.spef

setExtractRCMode -temperature 25.0
extractRC
rcOut -spef output/top_chip_25c.spef

setExtractRCMode -temperature -40.0
extractRC
rcOut -spef output/top_chip_m40c.spef
```

### Per-RC-Corner Temperature

```tcl
# In MMMC setup
create_rc_corner -name rc_wc -qrc_tech /libs/tech/qrcTechFile -T 125
create_rc_corner -name rc_bc -qrc_tech /libs/tech/qrcTechFile -T -40
create_rc_corner -name rc_tc -qrc_tech /libs/tech/qrcTechFile -T 25

# Extract per corner
rcOut -spef output/top_wc.spef -rc_corner rc_wc
rcOut -spef output/top_bc.spef -rc_corner rc_bc
rcOut -spef output/top_tc.spef -rc_corner rc_tc
```

### Temperature Scaling

```tcl
# Scale existing parasitics by temperature
set_rc_scaling_factor -temperature 125 \
    -res_factor 1.2 -cap_factor 1.1

# Apply scaling
apply_rc_scaling
```

---

## Incremental Extraction

### Incremental Extraction After ECO

```tcl
# After ECO changes, extract only modified nets
setExtractRCMode -engine postRoute -effortLevel signoff

# Incremental extraction
extractRC -incremental

# Incremental extraction for specific nets
extractRC -incremental -nets [get_nets eco_net_*]

# Write incremental SPEF
rcOut -spef output/top_chip_eco.spef -incremental
```

### Incremental Extraction Setup

```tcl
# Mark nets for incremental extraction
set_incremental_extraction_nets [get_nets modified_net*]

# Run incremental
extractRC -incremental

# Merge incremental with full SPEF
merge_spef -base output/top_chip_full.spef \
    -incremental output/top_chip_eco.spef \
    -output output/top_chip_merged.spef
```

---

## Distributed Extraction

### Multi-CPU Extraction

```tcl
# Set CPU count
setExtractRCMode -numThreads 8

# Set multi-CPU usage
set_multi_cpu_usage -local_cpu 8

# Run extraction with multi-threading
extractRC
```

### Distributed (Multi-Machine) Extraction

```tcl
# Set distributed hosts
setDistributeHost -add {host1 host2 host3 host4}

# Configure distributed extraction
setExtractRCMode -engine postRoute \
    -effortLevel signoff \
    -distributed true

# Set number of partitions
setExtractRCMode -distributed_partitions 8

# Run distributed extraction
extractRC

# Merge distributed results
merge_distributed_extraction -output output/top_chip.spef
```

### Hierarchical Extraction

```tcl
# Set hierarchical extraction
setExtractRCMode -hierarchical true

# Define extraction partitions
set_extraction_partition -block u_core
set_extraction_partition -block u_sram_bank
set_extraction_partition -block u_io_ring

# Extract per partition
extractRC -partition u_core
extractRC -partition u_sram_bank
extractRC -partition u_io_ring

# Merge partitions
merge_extraction_partitions -output output/top_chip.spef
```

---

## Extraction Commands Reference

### Core Extraction Commands

```tcl
# ============================================================
# extractRC -- Main extraction command
# ============================================================

extractRC
extractRC -incremental
extractRC -nets [get_nets *]
extractRC -outfile output/extraction.spef

# ============================================================
# rcOut -- Write parasitic output
# ============================================================

rcOut -spef output/top_chip.spef
rcOut -dspf output/top_chip.dspf
rcOut -sbpf output/top_chip.sbpf
rcOut -spef output/top_chip.spef -rc_corner rc_wc
rcOut -spef output/top_chip.spef -coupled
rcOut -spef output/top_chip.spef -reduce
rcOut -spef output/top_chip.spef -precision 6
rcOut -spef output/top_chip.spef -net [get_nets critical*]

# ============================================================
# setExtractRCMode -- Configure extraction
# ============================================================

setExtractRCMode -engine postRoute
setExtractRCMode -effortLevel signoff
setExtractRCMode -coupled true
setExtractRCMode -temperature 125.0
setExtractRCMode -via_extraction true
setExtractRCMode -metalFillAware true
setExtractRCMode -numThreads 8
setExtractRCMode -coupling_c_th 0.001
setExtractRCMode -total_c_th 0.01
setExtractRCMode -fieldSolver true
setExtractRCMode -reduce true
setExtractRCMode -topLayer M9
setExtractRCMode -bottomLayer M1
```

---

## Reporting and Debug

### Extraction Reports

```tcl
# Report extraction settings
report_extraction_mode

# Report extraction statistics
report_extraction_stats

# Report parasitic summary
report_parasitic_summary

# Report per-net parasitics
report_net_parasitics -net clk
report_net_parasitics -net data_bus[0]
report_net_parasitics -net [get_nets critical_*]

# Report coupling caps
report_coupling_caps -net clk -threshold 0.001

# Report total caps
report_total_caps -net [get_nets *]

# Report resistance
report_net_resistance -net [get_nets critical_*]

# Report via resistance
report_via_resistance

# Report extraction corners
report_rc_corners

# Capacitance comparison (cross-tool)
compare_spef -golden output/signoff.spef \
    -test output/innovus.spef \
    -output reports/spef_compare.rpt
```

### Parasitic Debug

```tcl
# Dump parasitic detail for a net
dump_parasitic -net critical_net -output output/net_parasitic.txt

# Check SPEF integrity
check_spef output/top_chip.spef

# Annotate parasitics
read_spef output/top_chip.spef
report_annotated_parasitics

# Report unannotated nets
report_unannotated_nets
report_unannotated_nets -type {net pin port}

# Parasitic mismatch report
report_parasitic_mismatch -spef output/top_chip.spef
```

---

## Advanced Features

### Metal Fill-Aware Extraction

```tcl
# Enable metal fill awareness
setExtractRCMode -metalFillAware true

# Read fill GDS/DEF
read_metal_fill /output/innovus/metal_fill.gds

# Extract with fill
extractRC
```

### Via Array Extraction

```tcl
# Enable via array modeling
setExtractRCMode -via_array_model true

# Set via array threshold
setExtractRCMode -via_array_min_cut 4
```

### Process Variation-Aware Extraction

```tcl
# Enable process variation
setExtractRCMode -process_variation true

# Set variation parameters
setExtractRCMode -process_variation_sigma 3.0

# Extract with variation
extractRC

# Write variation-aware SPEF
rcOut -spef output/top_chip_var.spef -process_variation
```

### Frequency-Dependent Extraction

```tcl
# Set target frequency
setExtractRCMode -targetFrequency 2e9  ;# 2 GHz

# Frequency-dependent field solver
setExtractRCMode -fieldSolver true \
    -fieldSolverMaxFreq 5e9

# Broadband extraction
setExtractRCMode -broadband true \
    -freqRange {1e6 5e9}
```

### Power Grid Extraction

```tcl
# Extract power/ground nets
setExtractRCMode -includePGnets true

# Extract power grid only
extractRC -nets [get_nets -filter {is_power == true || is_ground == true}]

# Write PG SPEF
rcOut -spef output/pg.spef -net [get_nets VDD] [get_nets VSS]
```

---

## Integration with Other Tools

### Quantus with Innovus

```tcl
# In Innovus: configure Quantus extraction
setExtractRCMode -engine postRoute -effortLevel signoff
setExtractRCMode -coupled true

# Extract
extractRC

# Use extracted parasitics for timing
timeDesign -postRoute -si

# Write SPEF for external STA
rcOut -spef output/top_chip.spef
rcOut -spef output/top_chip_wc.spef -rc_corner rc_wc
rcOut -spef output/top_chip_bc.spef -rc_corner rc_bc
```

### Quantus with Tempus

```tcl
# In Tempus: read Quantus SPEF
read_spef -rc_corner rc_wc /extraction/top_chip_wc.spef
read_spef -rc_corner rc_bc /extraction/top_chip_bc.spef

# Verify annotation
report_annotated_parasitics
report_unannotated_nets
```

### Quantus with Voltus

```tcl
# In Voltus: read SPEF for power analysis
read_spef /extraction/top_chip.spef

# Use extracted data for IR analysis
set_pg_analysis_mode -power_grid_analysis static
analyze_power_grid -net VDD
```

---

## Utility Commands

### Multi-Threading

```tcl
# Set threads
setExtractRCMode -numThreads 8
set_multi_cpu_usage -local_cpu 8

# Verify
report_multi_cpu_usage
```

### Memory and Performance

```tcl
# Report memory usage
report_resource -memory

# Optimize memory usage
setExtractRCMode -memory_optimize true

# Stream mode (low memory)
setExtractRCMode -stream_mode true
```

### Logging

```tcl
# Set log file
set_log_file output/quantus.log

# Verbose extraction
setExtractRCMode -verbose true
```

---

## Quick Reference: Complete Extraction Flow

```tcl
#============================================================
# Quantus Extraction -- Production Template (within Innovus)
#============================================================

# Configure extraction engine
setExtractRCMode -engine postRoute
setExtractRCMode -effortLevel signoff
setExtractRCMode -coupled true
setExtractRCMode -via_extraction true
setExtractRCMode -metalFillAware true
setExtractRCMode -numThreads 8

# Worst-case extraction
setExtractRCMode -temperature 125.0
extractRC
rcOut -spef output/top_chip_wc.spef -rc_corner rc_wc

# Best-case extraction
setExtractRCMode -temperature -40.0
extractRC
rcOut -spef output/top_chip_bc.spef -rc_corner rc_bc

# Typical extraction
setExtractRCMode -temperature 25.0
extractRC
rcOut -spef output/top_chip_tc.spef -rc_corner rc_tc

# Report extraction quality
report_extraction_stats > reports/extraction_stats.rpt
report_parasitic_summary > reports/parasitic_summary.rpt

puts "Extraction complete."
```

---

## Quantus Command Index (Alphabetical)

| Command | Category | Description |
|---------|----------|-------------|
| `check_extraction_readiness` | Validation | Verify design readiness |
| `check_spef` | Validation | Verify SPEF integrity |
| `compare_spef` | Debug | Compare two SPEF files |
| `dump_parasitic` | Debug | Dump net parasitic detail |
| `extractRC` | Extraction | Run parasitic extraction |
| `merge_distributed_extraction` | Distributed | Merge distributed results |
| `merge_spef` | Utility | Merge SPEF files |
| `rcOut` | Output | Write SPEF/DSPF/SBPF |
| `read_def` | Import | Read design DEF |
| `read_gds` | Import | Read GDS layout |
| `read_lef` | Import | Read LEF files |
| `read_metal_fill` | Import | Read metal fill data |
| `report_annotated_parasitics` | Report | Report annotated nets |
| `report_coupling_caps` | Report | Report coupling caps |
| `report_extraction_mode` | Report | Report extraction settings |
| `report_extraction_stats` | Report | Report extraction statistics |
| `report_net_parasitics` | Report | Report per-net parasitics |
| `report_net_resistance` | Report | Report net resistance |
| `report_parasitic_mismatch` | Report | Report mismatches |
| `report_parasitic_summary` | Report | Report parasitic summary |
| `report_rc_corners` | Report | Report RC corners |
| `report_total_caps` | Report | Report total capacitance |
| `report_unannotated_nets` | Report | Report unannotated nets |
| `report_via_resistance` | Report | Report via resistance |
| `set_extraction_area` | Config | Set extraction region |
| `set_extraction_boundary` | Config | Set extraction boundary |
| `set_qrc_tech` | Config | Set QRC techfile |
| `setExtractRCMode` | Config | Configure extraction mode |
