# Cadence Innovus Implementation -- Comprehensive Command Reference

## Table of Contents

1. [Design Import and Setup](#design-import-and-setup)
2. [Floorplanning](#floorplanning)
3. [Power Planning](#power-planning)
4. [Placement](#placement)
5. [Clock Tree Synthesis (CTS)](#clock-tree-synthesis-cts)
6. [Routing](#routing)
7. [Optimization](#optimization)
8. [Timing Analysis](#timing-analysis)
9. [Design Export](#design-export)
10. [Analysis and Verification](#analysis-and-verification)
11. [Multi-Mode Multi-Corner (MMMC)](#multi-mode-multi-corner-mmmc)
12. [ECO Commands](#eco-commands)
13. [Physical Verification](#physical-verification)
14. [Useful Utility Commands](#useful-utility-commands)
15. [Advanced Placement Controls](#advanced-placement-controls)
16. [Signal Integrity](#signal-integrity)
17. [Low Power Implementation](#low-power-implementation)

---

## Design Import and Setup

### read_lib

Reads Liberty timing libraries.

```tcl
# Read a single library
read_lib /libs/stdcells/ss_0p75v_125c.lib

# Read multiple libraries
read_lib {/libs/stdcells/ss_0p75v_125c.lib /libs/sram/sram_ss.lib /libs/io/io_ss.lib}

# Read CDB/OA library (for advanced node physical data)
read_lib -oa_lib_name stdcells -oa_cell_name top -oa_view_name abstract
```

### read_lef

Reads Library Exchange Format files (physical cell definitions).

```tcl
# Read technology LEF
read_lef /libs/tech/tech.lef

# Read cell LEFs
read_lef /libs/stdcells/stdcells.lef
read_lef /libs/sram/sram.lef
read_lef /libs/io/io.lef

# Read all LEF files together
read_lef {/libs/tech/tech.lef /libs/stdcells/stdcells.lef /libs/sram/sram.lef}
```

### read_verilog

Reads gate-level Verilog netlist.

```tcl
# Read synthesized netlist
read_verilog /output/genus/top_chip.v

# Read multiple netlist files
read_verilog {/output/genus/top_chip.v /libs/sram/sram_bb.v}

# Read with top module specification
set init_top_cell top_chip
read_verilog /output/genus/top_chip.v
```

### read_def

Reads Design Exchange Format (floorplan, placement, routing).

```tcl
# Read DEF file
read_def /data/floorplan/top_chip.def

# Read floorplan-only DEF
read_def -floorplan_only /data/floorplan/top_chip_fp.def

# Read DEF with options
read_def -skip_nets /data/placement/top_chip_placed.def
```

### read_sdc

Reads timing constraints (SDC format).

```tcl
# Read SDC file
read_sdc /constraints/top_chip.sdc

# Read SDC from Genus output
read_sdc /output/genus/top_chip.sdc
```

### read_spef / read_parasitics

Reads parasitic extraction data.

```tcl
# Read SPEF file
read_spef /extraction/top_chip.spef

# Read SPEF for specific corner
read_spef -rc_corner rc_wc /extraction/top_chip_wc.spef

# Read multiple SPEF files
read_spef -rc_corner rc_wc /extraction/top_chip_wc.spef
read_spef -rc_corner rc_bc /extraction/top_chip_bc.spef
```

### init_design / Design Initialization

```tcl
# Method 1: Direct file-based init
set init_verilog /output/genus/top_chip.v
set init_top_cell top_chip
set init_lef_file {/libs/tech/tech.lef /libs/stdcells/stdcells.lef /libs/sram/sram.lef}
set init_mmmc_file /scripts/mmmc.tcl
set init_pwr_net {VDD VDDH}
set init_gnd_net {VSS}
init_design

# Method 2: Using Genus output (GII)
source /output/genus/top_chip.invs_setup.tcl
init_design

# Method 3: Read design database
read_db /databases/top_chip_placed.db

# Design initialization options
set init_assign_buffer 1         ;# insert buffers for assign statements
set init_import_mode {-treatUndefinedCellAsBbox 0}
```

### MMMC File Structure

The MMMC (Multi-Mode Multi-Corner) configuration file:

```tcl
# mmmc.tcl -- MMMC configuration
# Library sets
create_library_set -name ls_wc \
    -timing {/libs/stdcells/ss_0p75v_125c.lib /libs/sram/sram_ss.lib}
create_library_set -name ls_bc \
    -timing {/libs/stdcells/ff_0p95v_m40c.lib /libs/sram/sram_ff.lib}
create_library_set -name ls_tc \
    -timing {/libs/stdcells/tt_0p85v_25c.lib /libs/sram/sram_tt.lib}

# RC corners
create_rc_corner -name rc_wc -qrc_tech /libs/tech/qrcTechFile \
    -T 125 -preRoute_res 1.2 -preRoute_cap 1.1 -postRoute_res 1.2 -postRoute_cap 1.1
create_rc_corner -name rc_bc -qrc_tech /libs/tech/qrcTechFile \
    -T -40 -preRoute_res 0.8 -preRoute_cap 0.9 -postRoute_res 0.8 -postRoute_cap 0.9
create_rc_corner -name rc_tc -qrc_tech /libs/tech/qrcTechFile \
    -T 25

# Delay corners
create_delay_corner -name dc_wc -library_set ls_wc -rc_corner rc_wc
create_delay_corner -name dc_bc -library_set ls_bc -rc_corner rc_bc
create_delay_corner -name dc_tc -library_set ls_tc -rc_corner rc_tc

# Constraint modes
create_constraint_mode -name cm_func -sdc_files {/constraints/func.sdc}
create_constraint_mode -name cm_test -sdc_files {/constraints/test.sdc}

# Analysis views
create_analysis_view -name av_wc_func -constraint_mode cm_func -delay_corner dc_wc
create_analysis_view -name av_bc_func -constraint_mode cm_func -delay_corner dc_bc
create_analysis_view -name av_wc_test -constraint_mode cm_test -delay_corner dc_wc

# Set active views
set_analysis_view -setup {av_wc_func} -hold {av_bc_func}
```

---

## Floorplanning

### floorPlan

Creates or modifies the chip floorplan.

```tcl
# Create floorplan by die size
floorPlan -site core_site -d <dieWidth> <dieHeight> \
    <leftMargin> <bottomMargin> <rightMargin> <topMargin>

# Example: 1000x1000um die with 10um margins
floorPlan -site core_site -d 1000.0 1000.0 10.0 10.0 10.0 10.0

# Create floorplan by core utilization
floorPlan -site core_site -r <aspectRatio> <utilization> \
    <leftMargin> <bottomMargin> <rightMargin> <topMargin>

# Example: 0.7 utilization, aspect ratio 1.0
floorPlan -site core_site -r 1.0 0.7 10.0 10.0 10.0 10.0

# Create floorplan by core size
floorPlan -site core_site -s <coreWidth> <coreHeight> \
    <leftMargin> <bottomMargin> <rightMargin> <topMargin>

# Floorplan with IO rows
floorPlan -site core_site -d 1200.0 1200.0 50.0 50.0 50.0 50.0 \
    -coreMarginsBy io
```

**Options reference:**
| Option | Description |
|--------|-------------|
| `-site <name>` | Placement site from LEF |
| `-d <W> <H> <L> <B> <R> <T>` | Die size with margins |
| `-r <AR> <util> <L> <B> <R> <T>` | Aspect ratio + utilization |
| `-s <W> <H> <L> <B> <R> <T>` | Core size with margins |
| `-coreMarginsBy io` | Account for IO pad height in margins |
| `-noSnapToGrid` | Disable grid snapping |

### Macro Placement

```tcl
# Place a macro at specific coordinates
placeInstance u_sram_bank0 100.0 200.0 R0

# Place macro with specific orientation
placeInstance u_sram_bank1 100.0 400.0 MY
# Orientations: R0, R90, R180, R270, MX, MY, MX90, MY90

# Fix macro placement
set_db [get_cells u_sram*] .place_status fixed

# Unfix macro placement
set_db [get_cells u_sram*] .place_status placed

# Auto-place macros
planDesign

# Place macros with channel constraints
set_db place_design_floorplan_mode true
planDesign -channel_width 10.0

# Snap macros to grid
snapFPlan -macro
```

### createRouteBlk / Blockages

```tcl
# Create routing blockage (all layers)
createRouteBlk -box {100.0 200.0 300.0 400.0}

# Create routing blockage on specific layer
createRouteBlk -box {100.0 200.0 300.0 400.0} -layer M1

# Create routing blockage on layer range
createRouteBlk -box {100.0 200.0 300.0 400.0} -layer {M1 M6}

# Create placement blockage
createPlaceBlockage -box {100.0 200.0 300.0 400.0}

# Create soft placement blockage (reduced density)
createPlaceBlockage -box {100.0 200.0 300.0 400.0} -type soft -density 0.3

# Create partial routing blockage
createRouteBlk -box {100.0 200.0 300.0 400.0} -layer M3 -partial 50

# Create pin blockage
createPinBlk -box {100.0 200.0 300.0 400.0} -layer M4

# Delete blockages
deleteRouteBlk -all
deleteRouteBlk -box {100.0 200.0 300.0 400.0}
deletePlaceBlockage -all

# Create rectilinear blockage
createRouteBlk -polygon {100 200 200 200 200 300 150 300 150 250 100 250}
```

### Pin Placement

```tcl
# Edit pin placement
editPin -pin {data_in[0] data_in[1]} -edge 0 -start 50.0 -end 100.0 \
    -layer M4 -spreadType center -spacing 1.0

# Pin edges: 0=left, 1=bottom, 2=right, 3=top

# Assign pins by side
editPin -pin [get_ports data_in*] -edge 0 -layer M4 -spreadType range \
    -start 50.0 -end 200.0

# Place all unplaced pins
assignIoPins

# Create pin guide
createPinGuide -edge 0 -from 50.0 -to 200.0 -layer {M4 M5} \
    -pin [get_ports data_in*]

# Fix pin locations
set_db [get_ports data_in*] .place_status fixed
```

### Partition / Fence / Region

```tcl
# Create a fence (hard boundary) for a module
createFence u_core 200.0 200.0 800.0 800.0

# Create a region (soft guide)
createRegion u_io_ctrl 50.0 50.0 200.0 200.0

# Create guide (softer than region)
createGuide u_peripheral 100.0 100.0 400.0 400.0

# Resize fence
resizeFP -fence u_core -box {200.0 200.0 900.0 900.0}

# Delete fence
deleteFence u_core
```

### Row and Site Operations

```tcl
# Add rows
addRow -site core_site -area {10.0 10.0 990.0 990.0}

# Cut rows around macros
cutRow -area {100.0 200.0 300.0 400.0}

# Merge short rows
mergeRow -short 5.0

# Report row usage
report_row
```

---

## Power Planning

### addRing

Creates power/ground rings around the core or specific blocks.

```tcl
# Add core ring
addRing -nets {VDD VSS} \
    -type core_rings \
    -layer {top M9 bottom M9 left M8 right M8} \
    -width {top 5.0 bottom 5.0 left 5.0 right 5.0} \
    -spacing {top 1.0 bottom 1.0 left 1.0 right 1.0} \
    -offset {top 2.0 bottom 2.0 left 2.0 right 2.0} \
    -center 0 \
    -threshold 0.0

# Add ring around a macro
addRing -nets {VDD VSS} \
    -type block_rings \
    -around [get_cells u_sram_bank0] \
    -layer {top M5 bottom M5 left M4 right M4} \
    -width {top 2.0 bottom 2.0 left 2.0 right 2.0} \
    -spacing {top 0.5 bottom 0.5 left 0.5 right 0.5} \
    -offset {top 1.0 bottom 1.0 left 1.0 right 1.0}

# Add ring around all macros
addRing -nets {VDD VSS} \
    -type block_rings \
    -around {*} \
    -layer {top M5 bottom M5 left M4 right M4} \
    -width 2.0 -spacing 0.5 -offset 1.0
```

### addStripe

Creates power/ground stripes.

```tcl
# Add vertical stripes
addStripe -nets {VDD VSS} \
    -layer M8 \
    -direction vertical \
    -width 2.0 \
    -spacing 1.0 \
    -set_to_set_distance 40.0 \
    -start_from left \
    -start_offset 20.0 \
    -stop_offset 20.0

# Add horizontal stripes
addStripe -nets {VDD VSS} \
    -layer M9 \
    -direction horizontal \
    -width 2.0 \
    -spacing 1.0 \
    -set_to_set_distance 40.0 \
    -start_from bottom \
    -start_offset 20.0

# Add stripes over a block
addStripe -nets {VDD VSS} \
    -layer M6 \
    -direction vertical \
    -width 1.0 \
    -spacing 0.5 \
    -set_to_set_distance 20.0 \
    -area {100.0 200.0 300.0 400.0}

# Add stripes with via generation
addStripe -nets {VDD VSS} \
    -layer M8 \
    -direction vertical \
    -width 2.0 \
    -spacing 1.0 \
    -set_to_set_distance 40.0 \
    -create_pins 1 \
    -extend_to design_boundary
```

**Stripe options:**
| Option | Description |
|--------|-------------|
| `-nets <list>` | Power/ground net names |
| `-layer <name>` | Metal layer for stripes |
| `-direction <dir>` | `vertical` or `horizontal` |
| `-width <val>` | Stripe width |
| `-spacing <val>` | Spacing between VDD and VSS stripes |
| `-set_to_set_distance <val>` | Center-to-center distance of stripe pairs |
| `-start_from <side>` | Reference edge: `left`, `right`, `top`, `bottom` |
| `-start_offset <val>` | Offset from start edge |
| `-stop_offset <val>` | Offset from stop edge |
| `-area <box>` | Restrict stripes to area |
| `-create_pins 1` | Create pins on stripes |
| `-extend_to design_boundary` | Extend stripes to boundary |

### sroute

Special route for power/ground connections.

```tcl
# Route standard cell power rails
sroute -nets {VDD VSS} \
    -connect {blockPin padPin corePin floatingStripe} \
    -layerChangeRange {M1 M9} \
    -blockPinTarget nearestTarget \
    -padPinPortConnect allPort \
    -corePinTarget firstAfterRowEnd \
    -crossoverViaLayerRange {M1 M9} \
    -allowJogging 1 \
    -allowLayerChange 1

# Quick sroute for standard cells
sroute -nets {VDD VSS} -connect corePin

# Route macro pins to stripes
sroute -nets {VDD VSS} -connect blockPin \
    -blockPinTarget nearestTarget

# Route IO pad connections
sroute -nets {VDD VSS} -connect padPin

# Route with via optimization
sroute -nets {VDD VSS} \
    -connect {blockPin corePin} \
    -layerChangeRange {M1 M9} \
    -allowJogging 1 \
    -targetViaLayerRange {M1 M9}
```

### addWellTap

```tcl
# Add well taps
addWellTap -cell TAPCELLD4 -cellInterval 30.0

# Add well taps with checkerboard pattern
addWellTap -cell TAPCELLD4 -cellInterval 30.0 -checkerBoard

# Add well taps in specific area
addWellTap -cell TAPCELLD4 -cellInterval 30.0 \
    -prefix WELLTAP -area {100.0 200.0 300.0 400.0}
```

### addEndCap

```tcl
# Add end-cap cells
addEndCap -preCap ENDCAPL -postCap ENDCAPR

# Add end-cap cells with corner cells
addEndCap -preCap ENDCAPL -postCap ENDCAPR \
    -topLeftCorner CORNERTL -topRightCorner CORNERTR \
    -bottomLeftCorner CORNERBL -bottomRightCorner CORNERBR

# Delete end-cap cells (before re-adding)
deleteEndCapCells
```

---

## Placement

### place_opt_design

The primary placement and optimization command.

```tcl
# Basic placement
place_opt_design

# Placement with pre-place optimization
place_opt_design -out_dir reports/place

# Incremental placement
place_opt_design -incremental

# Placement with congestion driven
place_opt_design -congestion
```

### setPlaceMode

Configure placement behavior.

```tcl
# Congestion effort
setPlaceMode -congEffort high    ;# low|medium|high|auto

# Timing driven placement
setPlaceMode -timingDriven 1

# Place IO pins
setPlaceMode -placeIOPins 1

# Reset buffer mode
setPlaceMode -reset_buf_mode 1

# Wire length optimization
setPlaceMode -wirelenOpt high

# Density screen
setPlaceMode -maxDensity 0.70

# Place with uniform density
setPlaceMode -uniformDensity true

# Allow row utilization
setPlaceMode -maxRouteLayer 9

# Congestion repair
setPlaceMode -congRepair 1

# Allow cell padding
setPlaceMode -padForHalo 1

# Detailed placement settings
setPlaceMode -dptFlow true
setPlaceMode -place_detail_legalization_inst_gap 1

# For advanced nodes
setPlaceMode -place_detail_color_aware_legal true
setPlaceMode -place_detail_dpt_flow true
setPlaceMode -place_detail_preroute_as_obs {M1 M2}

# Reset all placement modes
setPlaceMode -reset
```

### addInstHalo

Adds spacing halo around instances (typically macros).

```tcl
# Add halo to a specific macro
addInstHalo -cell u_sram_bank0 -allSides 5.0

# Add halo with different margins per side
addInstHalo -cell u_sram_bank0 -left 5.0 -bottom 5.0 -right 5.0 -top 10.0

# Add halos to all hard macros
addInstHalo -allMacros -allSides 5.0

# Add halo to specific cell type
addInstHalo -cellMaster SRAM_32K -allSides 3.0

# Remove halo
deleteInstHalo -cell u_sram_bank0

# Remove all halos
deleteInstHalo -allMacros
```

### Additional Placement Commands

```tcl
# Pre-place specific instances
placeInstance u_critical_reg 500.0 500.0 -placed

# Relative placement
create_relative_floorplan -place {u_regA u_regB} -orient R0

# Set placement density
setPlaceDensityMode -maxDensity 0.70 -check true

# Run detailed placement only
refinePlace

# Legalize placement
legalizePlace

# Check placement
checkPlace

# Report placement
report_placement_utilization
```

---

## Clock Tree Synthesis (CTS)

### ccopt_design

The unified CTS and optimization command.

```tcl
# Run CTS
ccopt_design

# CTS with post-CTS optimization
ccopt_design -cts

# Post-CTS optimization only
ccopt_design -post_cts

# Hold fixing during CTS
ccopt_design -hold
```

### create_ccopt_clock_tree_spec

Creates CTS specification.

```tcl
# Auto-create CTS spec from SDC
create_ccopt_clock_tree_spec

# Create spec from file
create_ccopt_clock_tree_spec -file cts_spec.tcl

# View/edit spec
get_ccopt_clock_trees *
get_ccopt_property -clock_tree sys_clk target_skew
```

### setCTSMode

Configure CTS behavior.

```tcl
# Set CTS engine
set_ccopt_property route_type trunk   ;# trunk|top
set_ccopt_property buffer_cells {CLKBUF_X4 CLKBUF_X8 CLKBUF_X16}
set_ccopt_property inverter_cells {CLKINV_X4 CLKINV_X8 CLKINV_X16}

# Target skew
set_ccopt_property target_skew 0.050

# Max insertion delay
set_ccopt_property target_max_trans 0.080

# Clock tree routing layers
set_ccopt_property -net_type trunk routing_rule trunk_rule
set_ccopt_property -net_type leaf routing_rule leaf_rule

# NDR for clock routing
create_route_rule -name trunk_rule -widths {M3 0.1 M4 0.1 M5 0.1} \
    -spacings {M3 0.1 M4 0.1 M5 0.1}
create_route_rule -name leaf_rule -widths {M3 0.07} -spacings {M3 0.07}

# Legacy CTS mode settings
setCTSMode -engine ccopt
setCTSMode -routeClkNet true
setCTSMode -topPreferredLayer M5
setCTSMode -bottomPreferredLayer M3

# CTS cell usage
set_ccopt_property use_inverters true
set_ccopt_property buffer_cells_for_sink {CLKBUF_X2 CLKBUF_X4}

# Insertion delay balancing
set_ccopt_property -clock_tree clk balance_mode better_balance

# Useful skew
set_ccopt_effort -high
set_ccopt_property use_useful_skew true
```

### CTS Analysis and Debug

```tcl
# Report CTS results
report_ccopt_clock_trees
report_ccopt_skew_groups

# Detailed CTS summary
report_clock_tree_summary

# Report clock tree structure
report_ccopt_clock_tree_structure -clock_tree sys_clk

# CTS debug
report_ccopt_violations

# Clock tree timing
report_clock_timing -type summary
report_clock_timing -type skew -clock sys_clk

# Latency report
report_clock_timing -type latency -clock sys_clk
```

---

## Routing

### routeDesign

The primary routing command.

```tcl
# Basic routing (all signal nets)
routeDesign

# Route with detailed options
routeDesign -globalDetail

# Global route only
routeDesign -global

# Detail route only
routeDesign -detail

# Track assignment only
routeDesign -track

# Incremental routing (fix DRC)
routeDesign -viaOpt

# Route specific nets
routeDesign -nets [get_nets data_bus*]
```

### setNanoRouteMode

Configure the NanoRoute routing engine.

```tcl
# Basic routing modes
setNanoRouteMode -routeTopRoutingLayer 9
setNanoRouteMode -routeBottomRoutingLayer 2

# Timing-driven routing
setNanoRouteMode -drouteUseMinSpaceForBlockage true
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -routeWithSiDriven true

# Congestion management
setNanoRouteMode -routeTdrEffort 10
setNanoRouteMode -drouteEndIteration 50

# Via optimization
setNanoRouteMode -routeWithViaInPin true
setNanoRouteMode -routeWithViaOnlyForStandardCellPin auto

# DRC fixing
setNanoRouteMode -drouteFixAntenna true
setNanoRouteMode -drouteAutoStop true

# Multi-cut vias
setNanoRouteMode -routePreferMultiCutVia true

# Routing effort
setNanoRouteMode -routeExpTdDriven true
setNanoRouteMode -drouteExpAdvancedMarFix true

# Crosstalk prevention
setNanoRouteMode -routeWithSiDriven true
setNanoRouteMode -routeWithSiPostRouteFix true

# Advanced node settings
setNanoRouteMode -drouteUseMultiCutViaEffort high
setNanoRouteMode -routeStrictlyHonorNonDefaultRule true

# Reset all
setNanoRouteMode -reset
```

### routeAutoEco

ECO routing for modified nets.

```tcl
# Route ECO nets
routeAutoEco

# Route ECO with options
ecoRoute -target /path/to/eco_def_or_nets

# Incremental route for specific nets
editRoute -net net_name
```

### Non-Default Rules (NDR)

```tcl
# Create NDR
create_route_rule -name wide_rule \
    -widths {M3 0.12 M4 0.12 M5 0.12} \
    -spacings {M3 0.12 M4 0.12 M5 0.12}

# Create double-width double-space rule
create_route_rule -name dw_ds_rule \
    -width_multiplier {M3:M6 2} \
    -spacing_multiplier {M3:M6 2}

# Apply NDR to nets
set_db [get_nets critical_bus*] .route_rule wide_rule

# Create shielded rule
create_route_rule -name shielded_rule \
    -widths {M4 0.12} \
    -spacings {M4 0.12} \
    -shield_nets {VSS}
```

### Route Guides and Constraints

```tcl
# Set preferred routing direction
setPreference -layer M3 -direction horizontal
setPreference -layer M4 -direction vertical

# Set routing tracks
add_tracks -direction horizontal -layer M3 \
    -start 0.0 -step 0.14 -count 5000

# Non-default spacing
setNanoRouteMode -routeStrictlyHonorNonDefaultRule true
```

---

## Optimization

### optDesign

The unified optimization command (post-placement, post-CTS, post-route).

```tcl
# Pre-CTS optimization
optDesign -preCTS

# Pre-CTS with hold fix
optDesign -preCTS -hold

# Post-CTS optimization
optDesign -postCTS
optDesign -postCTS -hold

# Post-route optimization
optDesign -postRoute
optDesign -postRoute -hold

# Post-route with setup and hold
optDesign -postRoute -setup -hold

# Incremental optimization
optDesign -postRoute -incr

# Drv (design rule violation) fixing
optDesign -postRoute -drv

# Output directory for reports
optDesign -postRoute -outDir reports/opt
```

**optDesign options:**
| Option | Description |
|--------|-------------|
| `-preCTS` | Pre-CTS optimization |
| `-postCTS` | Post-CTS optimization |
| `-postRoute` | Post-route optimization |
| `-setup` | Fix setup violations |
| `-hold` | Fix hold violations |
| `-drv` | Fix design rule violations |
| `-incr` | Incremental mode |
| `-outDir <dir>` | Report output directory |
| `-prefix <str>` | Report filename prefix |
| `-expandedViews <views>` | Views to optimize |

### setOptMode

Configure optimization behavior.

```tcl
# Effort level
setOptMode -effort high

# Hold fixing settings
setOptMode -holdTargetSlack 0.050
setOptMode -holdFixingCells {BUFX2 BUFX4 DELX1 DELX2}
setOptMode -addHoldBuffersToCritPaths true

# Setup fixing
setOptMode -setupTargetSlack 0.010

# Area recovery
setOptMode -areaRecovery true

# Useful skew
setOptMode -usefulSkew true
setOptMode -usefulSkewPreCTS true
setOptMode -usefulSkewPostRoute true

# DRV fixing
setOptMode -fixDrc true
setOptMode -fixFanoutLoad true

# Multi-bit optimization
setOptMode -multiBitFlop true

# Leakage optimization
setOptMode -leakagePowerEffort high

# Dynamic power
setOptMode -dynamicPowerEffort high

# Verbose
setOptMode -verbose true

# Max density check during opt
setOptMode -maxDensity 0.75

# Reset
setOptMode -reset
```

### ecoDesign

Performs timing ECO (Engineering Change Order).

```tcl
# Post-route ECO for timing
ecoDesign -postRoute

# ECO with specific focus
ecoDesign -postRoute -setup -hold

# ECO with specific views
ecoDesign -postRoute -expandedViews {av_wc_func av_bc_func}

# ECO for specific paths
ecoDesign -postRoute -fixPath {path1 path2}
```

---

## Timing Analysis

### timeDesign

Comprehensive timing analysis.

```tcl
# Pre-CTS timing
timeDesign -preCTS -outDir reports/timing_preCTS

# Pre-CTS hold
timeDesign -preCTS -hold -outDir reports/timing_preCTS_hold

# Post-CTS timing
timeDesign -postCTS -outDir reports/timing_postCTS
timeDesign -postCTS -hold -outDir reports/timing_postCTS_hold

# Post-route timing
timeDesign -postRoute -outDir reports/timing_postRoute
timeDesign -postRoute -hold -outDir reports/timing_postRoute_hold

# With SI analysis
timeDesign -postRoute -si -outDir reports/timing_postRoute_si

# With specific reporting
timeDesign -postRoute -numPaths 50 -outDir reports/timing

# Generate timing report only (no optimization)
timeDesign -postRoute -reportOnly
```

### setAnalysisMode

Configure timing analysis behavior.

```tcl
# Analysis type
setAnalysisMode -analysisType onChipVariation  ;# single|bcwc|onChipVariation

# Clock propagation (post-CTS)
setAnalysisMode -cppr both      ;# none|setup|hold|both

# SI analysis
setAnalysisMode -analysisType onChipVariation
setAnalysisMode -checkType setup

# Advanced OCV
setAnalysisMode -aocv true
setAnalysisMode -socv true

# Timing derate
set_timing_derate -early 0.95 -cell_delay
set_timing_derate -late 1.05 -cell_delay
set_timing_derate -early 0.97 -net_delay
set_timing_derate -late 1.03 -net_delay

# Reset
setAnalysisMode -reset
```

### report_timing (Innovus)

```tcl
# Basic timing report
report_timing

# Detailed timing report
report_timing -max_paths 100 -max_slack 0.0 -path_type full_clock \
    -net -cap -tran

# Report for specific endpoint
report_timing -to [get_pins reg_bank/D] -max_paths 5

# Report hold timing
report_timing -early -max_paths 50

# Report by path group
report_timing -group reg2reg -max_paths 20

# Report to file
report_timing -max_paths 200 -path_type full_clock \
    -net -cap -tran > reports/timing_detail.rpt

# Summary timing
report_timing -summary

# Report unconstrained paths
report_timing -unconstrained

# Nworst per endpoint
report_timing -max_paths 100 -nworst 3
```

### setTimingMode

```tcl
# Propagated clock (post-CTS)
setTimingMode -propagated

# Ideal clock (pre-CTS)
setTimingMode -ideal

# CPPR
setTimingMode -cppr both
```

---

## Design Export

### saveDesign

Saves the Innovus design database.

```tcl
# Save design (OA format)
saveDesign output/top_chip_placed.oa

# Save design (Innovus native format)
saveDesign output/top_chip_placed.inn

# Save design with specific options
saveDesign -cellview {lib cell view} output/top_chip.oa

# Save and compress
saveDesign -compress output/top_chip.inn
```

### streamOut (GDS)

Exports GDS-II layout.

```tcl
# Basic GDS export
streamOut output/top_chip.gds -mapFile /libs/tech/gds_layermap.map \
    -libName DesignLib -structureName top_chip

# GDS with options
streamOut output/top_chip.gds \
    -mapFile /libs/tech/gds_layermap.map \
    -libName DesignLib \
    -structureName top_chip \
    -units 1000 \
    -mode ALL

# GDS with merge
streamOut output/top_chip.gds \
    -mapFile /libs/tech/gds_layermap.map \
    -libName DesignLib \
    -structureName top_chip \
    -merge {/libs/sram/sram.gds /libs/io/io.gds}

# GDS with compression
streamOut output/top_chip.gds.gz \
    -mapFile /libs/tech/gds_layermap.map \
    -compress
```

**streamOut options:**
| Option | Description |
|--------|-------------|
| `-mapFile <file>` | Layer mapping file |
| `-libName <name>` | Library name in GDS |
| `-structureName <name>` | Top-level structure name |
| `-units <N>` | Database units per micron |
| `-mode ALL` | Export all cells |
| `-merge <files>` | Merge macro GDS files |
| `-compress` | Compress output |
| `-uniquifyCellNames` | Make cell names unique |

### write_lef_abstract

Exports LEF abstract for block-level integration.

```tcl
# Write LEF abstract
write_lef_abstract output/top_chip.lef -5.8

# LEF with options
write_lef_abstract output/top_chip.lef \
    -specifyTopLayer M9 \
    -PGpinLayers {M1 M8 M9} \
    -stripePin

# Write detailed LEF
write_lef_abstract output/top_chip.lef \
    -5.8 \
    -extractBlockObs \
    -extractBlockPin
```

### defOut

Exports DEF (Design Exchange Format).

```tcl
# Write full DEF
defOut -floorplan -netlist -routing output/top_chip.def

# Write floorplan-only DEF
defOut -floorplan output/top_chip_fp.def

# Write placement DEF
defOut -placement output/top_chip_placed.def

# Write with options
defOut -floorplan -netlist -routing \
    -version 5.8 \
    output/top_chip.def
```

### Other Export Commands

```tcl
# Write netlist
write_netlist output/top_chip.v
write_netlist -exclude_leaf_cells output/top_chip_noleaf.v

# Write SDF
write_sdf output/top_chip.sdf
write_sdf -max_view av_wc_func output/top_chip_max.sdf
write_sdf -min_view av_bc_func output/top_chip_min.sdf

# Write SDC
write_sdc output/top_chip.sdc

# Write SPEF
rcOut -spef output/top_chip.spef
rcOut -spef output/top_chip.spef -rc_corner rc_wc

# Write power intent
write_power_intent -cpf output/top_chip.cpf
write_power_intent -1801 output/top_chip.upf

# Write scan DEF
write_scandef output/top_chip.scandef

# Write LEC dofile
write_do_lec -revised_design output/top_chip.v > output/lec.do
```

---

## Analysis and Verification

### report_power

```tcl
# Static power report
report_power

# Hierarchical power
report_power -hierarchy all

# Power by view
report_power -view av_wc_func

# Detailed power
report_power -detail -hierarchy all > reports/power.rpt

# Dynamic power (with activity)
read_activity_file -format VCD -scope top_tb/dut simulation.vcd
report_power -hierarchy all

# SAIF-based power
read_activity_file -format SAIF -scope top_chip top.saif
report_power
```

### report_congestion

```tcl
# Congestion report
report_congestion

# Detailed congestion
report_congestion -hotspot

# Congestion map
reportCongestion -overflow

# GRC-based congestion
reportCongestion -gcell -overflow
```

### verify_drc

```tcl
# Verify DRC (geometric)
verify_drc -report reports/drc.rpt

# Verify DRC with options
verify_drc -limit 1000 -report reports/drc.rpt

# Verify connectivity
verify_connectivity -report reports/conn.rpt

# Verify geometry
verifyGeometry -report reports/geometry.rpt

# Verify process antenna
verifyProcessAntenna -report reports/antenna.rpt

# Verify metal density
verifyMetalDensity -report reports/density.rpt
```

### Additional Analysis Commands

```tcl
# Area report
report_area

# Cell usage
report_gates

# Design statistics
report_design_summary

# Check timing intent
check_timing -verbose

# Constraint report
report_constraint -all_violators

# DRV report
report_constraint -max_transition -all_violators
report_constraint -max_capacitance -all_violators
report_constraint -max_fanout -all_violators

# Net statistics
report_net_fanout -threshold 50

# Route statistics
report_route

# Wire length
report_wire_length

# Via count
report_via_count

# Density
report_density

# Clock tree
report_ccopt_clock_trees
report_ccopt_skew_groups
```

---

## Multi-Mode Multi-Corner (MMMC)

### create_analysis_view

```tcl
# Create analysis view
create_analysis_view -name av_wc_func \
    -constraint_mode cm_func \
    -delay_corner dc_wc

# Create view with AOCV
create_analysis_view -name av_wc_aocv \
    -constraint_mode cm_func \
    -delay_corner dc_wc

# Create view with specific derates
create_analysis_view -name av_custom \
    -constraint_mode cm_func \
    -delay_corner dc_wc \
    -latency_corner lc_wc
```

### set_analysis_view

```tcl
# Set active views for optimization
set_analysis_view -setup {av_wc_func av_wc_test} -hold {av_bc_func}

# Set views for specific operations
set_analysis_view -setup {av_wc_func} -hold {av_bc_func av_tc_func}

# Query current views
get_analysis_view -list
report_analysis_view
```

### MMMC Management

```tcl
# Update library set
update_library_set -name ls_wc -timing {ss_0p75v_125c_v2.lib}

# Update constraint mode
update_constraint_mode -name cm_func -sdc_files {func_v2.sdc}

# Update delay corner
update_delay_corner -name dc_wc -library_set ls_wc_v2

# Delete views
delete_analysis_view -name av_old

# Report all MMMC objects
report_delay_corner
report_library_set
report_constraint_mode
report_rc_corner
```

---

## ECO Commands

### ecoDesign

```tcl
# Timing ECO (post-route)
ecoDesign -postRoute -setup -hold

# ECO with specific views
ecoDesign -postRoute -expandedViews {av_wc_func}
```

### Manual ECO Operations

```tcl
# Add a buffer
ecoAddRepeater -term [get_pins reg/D] -cell BUFX4

# Delete a buffer
ecoDeleteRepeater -inst eco_buf_1

# Change cell size
ecoChangeCell -inst u_buf_1 -cell BUFX8

# Swap cell
ecoSwapCell -inst u_inv -cell INVX4

# Add an instance
addInst -cell BUFX4 -inst eco_buf_new

# Delete an instance
deleteInst eco_buf_old

# Add a net
addNet eco_net_new

# Connect net
attachTerm eco_buf_new/A eco_net_new

# Disconnect
detachTerm eco_buf_old/Y

# Place ECO cells
ecoPlace

# Route ECO nets
ecoRoute

# Full ECO flow
ecoDesign -postRoute
ecoPlace
ecoRoute

# Write ECO file
write_eco_opt_db output/eco_db
```

### Freeze Operations for ECO

```tcl
# Freeze cells (prevent optimization from moving them)
set_db [get_cells -hierarchical *] .eco_freeze placement

# Unfreeze
set_db [get_cells -hierarchical *] .eco_freeze none

# Freeze specific instances
set_db [get_cells u_critical/*] .eco_freeze placement
```

---

## Physical Verification

### verify_drc

```tcl
# Full DRC check
verify_drc -report reports/drc.rpt -limit 10000

# DRC on specific layer
verify_drc -layer M3 -report reports/drc_M3.rpt

# Short check
verify_drc -check_short -report reports/shorts.rpt

# Open check
verify_drc -check_open -report reports/opens.rpt
```

### verify_connectivity

```tcl
# Full connectivity check
verify_connectivity -report reports/conn.rpt

# Check specific nets
verify_connectivity -net {VDD VSS clk} -report reports/conn_critical.rpt

# Check with error limit
verify_connectivity -error 1000 -report reports/conn.rpt
```

### verifyGeometry

```tcl
# Full geometry check
verifyGeometry -report reports/geom.rpt

# Check specific layers
verifyGeometry -allowedLayer {M1 M2 M3 M4 M5 M6 M7 M8 M9} \
    -report reports/geom.rpt

# Check with limits
verifyGeometry -limit 10000 -report reports/geom.rpt
```

### verifyProcessAntenna

```tcl
# Antenna check
verifyProcessAntenna -report reports/antenna.rpt

# Antenna check with fixing
verifyProcessAntenna -report reports/antenna.rpt -fix
```

---

## Useful Utility Commands

### GUI and Display

```tcl
# Window operations
win    ;# show GUI
fit    ;# fit design in window

# Zoom
zoomIn
zoomOut
zoomTo {100 200 300 400}

# Highlight
highlight_objects [get_cells u_core/*] -color red
highlight_objects [get_nets critical_net] -color blue

# Unhighlight
unhighlight_objects -all

# Display settings
setLayerPreference -visible M1 -color blue
setLayerPreference -visible M2 -color green

# View floorplan
viewFloorplan

# View placement
viewPlacement
```

### Database Queries

```tcl
# Get cells
get_cells -hierarchical *
get_cells -hierarchical -filter {ref_name == BUFX4}
get_cells -hierarchical -filter {is_sequential == true}
get_cells -hierarchical -filter {is_macro == true}

# Get nets
get_nets *
get_nets -hierarchical -filter {num_connections > 50}

# Get ports
get_ports *
get_ports -filter {direction == in}

# Get pins
get_pins -hierarchical */D
get_pins -hierarchical */Q

# Get clocks
get_clocks *

# Get via count
dbGet top.numVias

# Get instance count
dbGet top.numInsts

# Get net count
dbGet top.numNets

# Get area
dbGet top.fplan.area
dbGet top.fplan.coreBox

# Get utilization
dbGet top.fplan.util
```

### Session Management

```tcl
# Save/restore design
saveDesign output/checkpoint.inn

# Read design
read_db output/checkpoint.inn

# Write snapshot
write_flow_template -dir output/flow_template

# Source a script
source scripts/setup.tcl

# Logging
setLogFile output/innovus_run.log

# Set distributed processing
setDistributeHost -local
setMultiCpuUsage -localCpu 8

# Distributed multi-processing
setDistributeHost -add {host1 host2 host3}
setMultiCpuUsage -remoteHost 8
```

---

## Advanced Placement Controls

### Placement Guidance

```tcl
# Relative placement constraints
create_relative_floorplan -place {instA instB instC} -orient R0

# Cluster placement
createInstGroup grp_critical -region {100 200 300 400}
addInstToInstGroup grp_critical {u_regA u_regB u_regC}

# Spread placement
setPlaceMode -uniformDensity true
setPlaceMode -maxDensity 0.65

# Timing-critical instance binding
set_db [get_cells critical_reg*] .place_status softFixed
```

### Spare Cell Insertion

```tcl
# Add spare cells
addSpareCells -cell {BUFX4 INVX4 NAND2X2 NOR2X2} \
    -prefix SPARE -numEachCell 50

# Add spare cells in specific area
addSpareCells -cell {BUFX4 INVX4} -prefix SPARE \
    -numEachCell 20 -area {100 200 300 400}

# Tie off spare cell inputs
tieHiLoInst -inst [get_cells SPARE*]
```

---

## Signal Integrity

### SI Analysis

```tcl
# Enable SI
setAnalysisMode -analysisType onChipVariation
setNanoRouteMode -routeWithSiDriven true
setNanoRouteMode -routeWithSiPostRouteFix true

# SI timing
setSIMode -analyzeNoiseThreshold 0.3
setSIMode -analyzeFunctionality true

# Report SI
report_noise -above_threshold
report_noise -net critical_net

# Fix SI violations
fixSI -postRoute
```

---

## Low Power Implementation

### Power Domain Setup

```tcl
# Read UPF
read_power_intent -1801 power.upf

# Commit power intent
commit_power_intent

# Verify power structure
check_power_intent

# Report power domains
report_power_domain -all
```

### Isolation and Level Shifter

```tcl
# Check isolation cells
verify_power_domain -iso_net_pd

# Check level shifters
verify_power_domain -ls_net_pd

# Add isolation cells
addIsoCell

# Add level shifters
addLevelShifter

# Power switch insertion
addPowerSwitch -globalSwitchCellName HEADX4 \
    -column -powerDomain PD_core \
    -enablePin EN
```

### Retention

```tcl
# Check retention
verify_power_domain -ret_net_pd

# Report retention cells
report_retention_cells
```

### Multi-Voltage Routing

```tcl
# Route by voltage domain
routeDesign
sroute -nets {VDD_CORE VDD_IO VDD_MEM VSS}
```

---

## Quick Reference: Complete PnR Flow Script

```tcl
#============================================================
# Innovus PnR Script -- Production Template
#============================================================

# Design init
set init_verilog /output/genus/top_chip.v
set init_top_cell top_chip
set init_lef_file {tech.lef stdcells.lef sram.lef io.lef}
set init_mmmc_file scripts/mmmc.tcl
set init_pwr_net {VDD}
set init_gnd_net {VSS}
init_design

# Floorplan
floorPlan -site core_site -d 1000.0 1000.0 10.0 10.0 10.0 10.0
placeInstance u_sram 100.0 200.0 R0
addInstHalo -allMacros -allSides 5.0
snapFPlan -macro

# Power planning
addRing -nets {VDD VSS} -type core_rings \
    -layer {top M9 bottom M9 left M8 right M8} \
    -width 5.0 -spacing 1.0 -offset 2.0
addStripe -nets {VDD VSS} -layer M8 -direction vertical \
    -width 2.0 -spacing 1.0 -set_to_set_distance 40.0 -start_offset 20.0
sroute -nets {VDD VSS} -connect {blockPin padPin corePin}
addWellTap -cell TAPCELLD4 -cellInterval 30.0
addEndCap -preCap ENDCAPL -postCap ENDCAPR

# Placement
setPlaceMode -congEffort high -timingDriven 1
place_opt_design
timeDesign -preCTS -outDir reports/timing_preCTS

# CTS
create_ccopt_clock_tree_spec
ccopt_design
timeDesign -postCTS -outDir reports/timing_postCTS
optDesign -postCTS -hold

# Routing
setNanoRouteMode -routeTopRoutingLayer 9 -routeBottomRoutingLayer 2
setNanoRouteMode -routeWithTimingDriven true -routeWithSiDriven true
routeDesign -globalDetail

# Post-route optimization
optDesign -postRoute -setup -hold

# Timing analysis
timeDesign -postRoute -outDir reports/timing_postRoute
timeDesign -postRoute -hold -outDir reports/timing_postRoute_hold

# Signoff timing
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute -si -outDir reports/timing_signoff

# Verification
verify_drc -report reports/drc.rpt
verify_connectivity -report reports/conn.rpt
verifyProcessAntenna -report reports/antenna.rpt

# Reports
report_power -hierarchy all > reports/power.rpt
report_congestion > reports/congestion.rpt
report_area > reports/area.rpt
report_route > reports/route.rpt

# Export
saveDesign output/top_chip_final.inn
streamOut output/top_chip.gds -mapFile gds_layermap.map \
    -libName DesignLib -structureName top_chip \
    -merge {sram.gds io.gds}
defOut -floorplan -netlist -routing output/top_chip.def
write_netlist output/top_chip.v
write_sdc output/top_chip.sdc
rcOut -spef output/top_chip.spef
write_sdf -max_view av_wc_func output/top_chip.sdf

puts "PnR complete."
```

---

## Innovus Command Index (Alphabetical)

| Command | Category | Description |
|---------|----------|-------------|
| `addEndCap` | Physical | Insert end-cap cells |
| `addInstHalo` | Placement | Add halo around instances |
| `addInst` | ECO | Add new instance |
| `addRing` | Power | Create power/ground rings |
| `addSpareCells` | Physical | Insert spare cells |
| `addStripe` | Power | Create power/ground stripes |
| `addWellTap` | Physical | Insert well tap cells |
| `assignIoPins` | Floorplan | Auto-assign IO pin locations |
| `ccopt_design` | CTS | Run clock tree synthesis |
| `checkPlace` | Placement | Verify placement legality |
| `create_analysis_view` | MMMC | Define analysis view |
| `create_ccopt_clock_tree_spec` | CTS | Create CTS specification |
| `create_constraint_mode` | MMMC | Define constraint mode |
| `create_delay_corner` | MMMC | Define delay corner |
| `create_library_set` | MMMC | Define library set |
| `create_rc_corner` | MMMC | Define RC corner |
| `create_route_rule` | Routing | Create non-default routing rule |
| `createFence` | Floorplan | Create hard boundary |
| `createGuide` | Floorplan | Create soft placement guide |
| `createPlaceBlockage` | Floorplan | Create placement blockage |
| `createRegion` | Floorplan | Create soft boundary |
| `createRouteBlk` | Floorplan | Create routing blockage |
| `defOut` | Export | Write DEF file |
| `deleteInst` | ECO | Delete instance |
| `ecoAddRepeater` | ECO | Add buffer for ECO |
| `ecoChangeCell` | ECO | Swap cell for ECO |
| `ecoDesign` | ECO | Run timing ECO |
| `ecoPlace` | ECO | Place ECO cells |
| `ecoRoute` | ECO | Route ECO nets |
| `editPin` | Floorplan | Edit pin placement |
| `fit` | GUI | Fit design in window |
| `floorPlan` | Floorplan | Create/modify floorplan |
| `get_cells` | Query | Get cell objects |
| `get_clocks` | Query | Get clock objects |
| `get_nets` | Query | Get net objects |
| `get_pins` | Query | Get pin objects |
| `get_ports` | Query | Get port objects |
| `init_design` | Setup | Initialize design |
| `legalizePlace` | Placement | Legalize placement |
| `optDesign` | Optimization | Run optimization |
| `place_opt_design` | Placement | Run placement |
| `placeInstance` | Placement | Place specific instance |
| `planDesign` | Floorplan | Auto-place macros |
| `rcOut` | Export | Write SPEF parasitics |
| `read_def` | Import | Read DEF file |
| `read_lef` | Import | Read LEF file |
| `read_lib` | Import | Read Liberty library |
| `read_sdc` | Import | Read SDC constraints |
| `read_spef` | Import | Read SPEF parasitics |
| `read_verilog` | Import | Read Verilog netlist |
| `refinePlace` | Placement | Detailed placement |
| `report_area` | Report | Area breakdown |
| `report_ccopt_clock_trees` | Report | CTS results |
| `report_congestion` | Report | Routing congestion |
| `report_constraint` | Report | Constraint violations |
| `report_density` | Report | Placement density |
| `report_power` | Report | Power analysis |
| `report_route` | Report | Routing statistics |
| `report_timing` | Report | Timing paths |
| `report_wire_length` | Report | Wire length stats |
| `routeAutoEco` | Routing | ECO routing |
| `routeDesign` | Routing | Signal routing |
| `saveDesign` | Export | Save design database |
| `set_analysis_view` | MMMC | Set active views |
| `setAnalysisMode` | Timing | Configure analysis |
| `setNanoRouteMode` | Routing | Configure router |
| `setOptMode` | Optimization | Configure optimizer |
| `setPlaceMode` | Placement | Configure placer |
| `sroute` | Power | Route power/ground |
| `streamOut` | Export | Write GDS-II |
| `timeDesign` | Timing | Run timing analysis |
| `verify_connectivity` | Verify | Check connectivity |
| `verify_drc` | Verify | Check DRC |
| `verifyGeometry` | Verify | Check geometry |
| `verifyProcessAntenna` | Verify | Check antenna |
| `write_lef_abstract` | Export | Write LEF abstract |
| `write_netlist` | Export | Write Verilog netlist |
| `write_sdc` | Export | Write SDC constraints |
| `write_sdf` | Export | Write SDF delays |
