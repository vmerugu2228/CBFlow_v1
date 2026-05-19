# Cadence Innovus Place and Route Guide

## Overview

Innovus Implementation System is Cadence's flagship place-and-route tool, the successor to Encounter Digital Implementation (EDI). Innovus features a unified optimization engine (GigaOpt), concurrent multi-corner multi-mode (MMMC) optimization, and machine-learning-driven placement. It is the PnR counterpart to Genus (synthesis) and Tempus (signoff STA) in the Cadence digital full flow.

## Flow Overview

A typical Innovus PnR flow proceeds through these stages:

1. **Design Import** — Read netlist, constraints, libraries, and physical data
2. **Floorplanning** — Define die size, place macros, create power grid
3. **Placement** — `place_opt_design`
4. **CTS** — `ccopt_design`
5. **Post-CTS Optimization** — `opt_design -post_cts`
6. **Routing** — `route_design`
7. **Post-Route Optimization** — `opt_design -post_route`
8. **Signoff and Export** — DRC, timing signoff, GDSII/DEF/netlist export

## Design Import

### Library and Technology Setup

```tcl
# Set multi-mode multi-corner configuration
set init_mmmc_file mmmc_setup.tcl

# Set LEF files
set init_lef_file "tech.lef stdcell.lef sram.lef"

# Set power/ground nets
set init_pwr_nets_list {VDD}
set init_gnd_nets_list {VSS}

# Set top-level netlist
set init_verilog top_syn.v

# Set top cell name
set init_top_cell top

# Initialize design
init_design
```

### MMMC Setup File (mmmc_setup.tcl)

```tcl
# Library sets
create_library_set -name ss_libs \
    -timing {libs/ss_0p72v_125c.lib mem_ss.lib}
create_library_set -name ff_libs \
    -timing {libs/ff_0p88v_m40c.lib mem_ff.lib}

# RC corners
create_rc_corner -name rc_worst -cap_table worst.captable \
    -qrc_tech worst.qrcTechFile
create_rc_corner -name rc_best -cap_table best.captable \
    -qrc_tech best.qrcTechFile

# Delay corners
create_delay_corner -name dc_ss -library_set ss_libs -rc_corner rc_worst
create_delay_corner -name dc_ff -library_set ff_libs -rc_corner rc_best

# Constraint modes
create_constraint_mode -name cm_func -sdc_files func.sdc
create_constraint_mode -name cm_test -sdc_files test.sdc

# Analysis views
create_analysis_view -name av_func_ss -constraint_mode cm_func -delay_corner dc_ss
create_analysis_view -name av_func_ff -constraint_mode cm_func -delay_corner dc_ff
create_analysis_view -name av_test_ss -constraint_mode cm_test -delay_corner dc_ss

# Set active views
set_analysis_view -setup {av_func_ss av_test_ss} -hold {av_func_ff}
```

## Floorplanning

### Die and Core Specification

```tcl
# Specify floorplan with utilization target
floorPlan -r 1.0 0.70 10 10 10 10
# aspect_ratio utilization left bottom right top margins

# Or specify explicit dimensions
floorPlan -d 800 600 10 10 10 10
# width height margins
```

### Macro Placement

```tcl
# Interactive or script-based macro placement
placeInstance u_sram_0 100.0 200.0 N
placeInstance u_sram_1 100.0 350.0 N

# Add halos around macros
addHaloToBlock -allMacros 5 5 5 5

# Add routing blockages if needed
createRouteBlk -box 95 195 220 510 -layer {M1 M2 M3}
```

### Power Grid

```tcl
# Global net connections
globalNetConnect VDD -type pgpin -pin VDD -all
globalNetConnect VSS -type pgpin -pin VSS -all

# Standard cell follow-pin rails
sroute -connect {blockPin padPin corePin} -layerChangeRange {M1 M1} \
    -blockPinTarget nearestTarget -padPinPortConnect allPort \
    -nets {VDD VSS}

# Power rings
addRing -nets {VDD VSS} -type core_rings -layer {top M9 bottom M9 left M8 right M8} \
    -width 2.0 -spacing 1.0 -offset 2.0

# Power stripes
addStripe -nets {VDD VSS} -layer M8 -direction vertical \
    -width 1.0 -spacing 0.5 -set_to_set_distance 40 -start_from left -start_offset 10

addStripe -nets {VDD VSS} -layer M9 -direction horizontal \
    -width 1.0 -spacing 0.5 -set_to_set_distance 40 -start_from bottom -start_offset 10

# Verify PG connectivity
verifyConnectivity -nets {VDD VSS} -type special
```

## Placement: place_opt_design

```tcl
# Set placement controls
setPlaceMode -place_detail_legalization_inst_gap 1
setPlaceMode -place_global_cong_effort high
setPlaceMode -place_global_timing_effort high

# Run placement + optimization
place_opt_design

# Review results
report_timing -max_paths 20
reportCongestion -hotSpot
```

`place_opt_design` runs global placement, legalization, detail placement, and pre-CTS optimization (buffering, sizing, Vt swapping) in a single command.

### Placement Controls

```tcl
# Density control
setPlaceMode -place_global_max_density 0.85

# Module-level density
setDensityMode -area {100 100 300 300} -maxDensity 0.75

# Placement blockages
createPlaceBlockage -box {50 50 150 200} -type hard
createPlaceBlockage -box {200 200 400 400} -type partial -density 60
```

## CTS: ccopt_design

Innovus uses CCOpt (Concurrent Clock Optimization) for CTS, which simultaneously builds clock trees and optimizes timing.

### CTS Configuration

```tcl
# Specify CTS cells
set_ccopt_property buffer_cells {CKBUFX4 CKBUFX8 CKBUFX12 CKBUFX16}
set_ccopt_property inverter_cells {CKINVX4 CKINVX8 CKINVX12 CKINVX16}

# NDR for clock nets
add_ndr -name cts_2w2s -width_multiplier {M3:M5 2} -spacing_multiplier {M3:M5 2}
create_route_type -name cts_trunk -non_default_rule cts_2w2s \
    -top_preferred_layer M5 -bottom_preferred_layer M3
create_route_type -name cts_leaf -top_preferred_layer M4 -bottom_preferred_layer M3

set_ccopt_property -net_type trunk route_type cts_trunk
set_ccopt_property -net_type leaf route_type cts_leaf

# Skew and latency targets
set_ccopt_property target_skew 0.050
set_ccopt_property target_max_trans 0.080
```

### Running CTS

```tcl
# Create clock tree spec
create_ccopt_clock_tree_spec

# Run CTS + optimization
ccopt_design

# Review clock tree
report_ccopt_skew_groups
report_ccopt_clock_trees -summary
```

### Post-CTS Optimization

```tcl
# Fix hold after CTS (hold fixing requires real clock tree)
setOptMode -holdTargetSlack 0.020 -holdFixingCells {DLYX1 DLYX2 BUFX2}
opt_design -post_cts -hold

report_timing -max_paths 20
report_timing -max_paths 20 -check_type hold
```

## Routing: route_design

```tcl
# Set routing controls
setNanoRouteMode -drouteVerboseViolationSummary 1
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -routeWithSiDriven true
setNanoRouteMode -drouteFixAntenna true
setNanoRouteMode -routeAntennaCellName ANTENNACELLBWP7T

# Run routing
route_design

# Check routing DRC
verify_drc
```

## Post-Route Optimization: opt_design -post_route

```tcl
# Post-route timing and SI optimization
setOptMode -postRouteFixCrosstalk true
opt_design -post_route

# Final hold fixing
opt_design -post_route -hold

# Report final timing
report_timing -max_paths 50 > rpt/final_setup.rpt
report_timing -max_paths 50 -check_type hold > rpt/final_hold.rpt
```

## Filler Cell and Metal Fill

```tcl
# Insert filler cells
addFiller -cell {FILLX64 FILLX32 FILLX16 FILLX8 FILLX4 FILLX2 FILLX1} -prefix FILLER

# Insert metal fill for density rules
addMetalFill -layer {M1 M2 M3 M4 M5 M6 M7 M8} -nets {VDD VSS}
```

## Design Export

```tcl
# Write final netlist
saveNetlist output/top_final.v

# Write DEF
defOut output/top_final.def

# Write GDS
streamOut output/top_final.gds -mapFile gds_map.map -libName top_lib \
    -merge {sram.gds stdcell.gds}

# Write SDF
write_sdf output/top_final.sdf

# Write final SDC
write_sdc output/top_final.sdc

# Save design database
saveDesign output/top_final.enc
```

## Common Issues and Fixes

**Issue: Placement congestion causing routing DRC overflow**
- Increase congestion effort: `setPlaceMode -place_global_cong_effort high`
- Reduce utilization target by 3-5%
- Add partial density blockages in hotspot regions
- Ensure macro halos are sufficient

**Issue: Hold violations not closing after opt_design**
- Verify hold fixing cells are available and not excluded
- Increase hold target slack margin: `setOptMode -holdTargetSlack 0.030`
- Check that the correct hold view (fast corner) is active
- Run `opt_design -post_route -hold` iteratively

**Issue: Clock skew exceeds target**
- Review CTS cell list — ensure sufficient drive strengths are available
- Check NDR rules — overly aggressive NDR can limit CTS routing
- Verify macro clock pin accessibility
- Consider useful skew: `set_ccopt_property enable_useful_skew true`

**Issue: Antenna violations post-route**
- Enable antenna fixing during route: `setNanoRouteMode -drouteFixAntenna true`
- Provide antenna cell: `setNanoRouteMode -routeAntennaCellName ANTCELL`
- Run `repair_antenna` as a post-route step
- Add antenna diodes near gates with long lower-metal connections

**Issue: Signal integrity (SI) crosstalk violations**
- Enable SI-aware routing: `setNanoRouteMode -routeWithSiDriven true`
- Run `opt_design -post_route` with crosstalk fixing enabled
- Check for parallel aggressor nets — increase spacing via NDR on critical nets

## Best Practices

1. **Save design checkpoints** after each major stage (post-place, post-CTS, post-route) for debug and recovery.
2. **Run `verify_connectivity` and `verify_drc`** at each stage, not just at the end.
3. **Use `checkPlace`** after placement to catch legalization errors early.
4. **Set realistic hold margins** (20-30 ps) to account for OCV and extraction uncertainty.
5. **Run trial route** after placement to assess congestion before investing in CTS.
6. **Use `timeDesign -preRoute`** and `timeDesign -postRoute`** to compare timing at each stage.
7. **Avoid over-constraining** — if synthesis already over-constrained by 10%, do not add more margin in PnR.
8. **Use the Innovus GUI** (invs_cmd) for visual debugging of congestion, timing paths, and clock trees — text reports miss spatial context.
