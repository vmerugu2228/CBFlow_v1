# Synopsys Fusion Compiler Guide

## Overview

Fusion Compiler (FC) is Synopsys's unified synthesis-through-routing platform. Unlike the traditional Design Compiler + IC Compiler II two-tool flow, FC integrates synthesis and physical implementation into a single data model. This enables placement-aware synthesis, routing-aware optimization, and eliminates the traditional handoff gap between synthesis and PnR.

## Architecture and Key Differentiators

FC operates on a single unified data model (UDM) throughout the entire flow, from RTL to GDSII. Key advantages:

- **No netlist handoff:** Synthesis and placement happen concurrently — no need to export/import between DC and ICC2.
- **Physical-aware synthesis:** Cell placement information feeds back into synthesis optimization decisions.
- **Consistent timing engine:** The same timer runs from synthesis through signoff, reducing correlation gaps.
- **SPG (Synopsys Physical Guidance):** Layout-aware logic structuring during synthesis.

## Flow Topology

### Non-SPG Flow (Compile + Place)

The simpler flow separates synthesis and placement into distinct stages:

1. `compile_fusion` — Logic synthesis (similar to compile_ultra in DC)
2. `create_floorplan` / `initialize_floorplan`
3. `place_opt` — Placement and placement-based optimization
4. `clock_opt` — CTS and post-CTS optimization
5. `route_auto` — Global and detail routing
6. `route_opt` — Post-route optimization

### SPG Flow (Recommended)

SPG interleaves placement with synthesis for superior QoR:

1. `compile_fusion -scan` — Performs synthesis with simultaneous coarse placement
2. Floorplanning (macro placement, blockage creation)
3. `place_opt` — Refines placement with full physical context
4. `clock_opt` — CTS
5. `route_auto` + `route_opt` — Routing and post-route optimization

SPG typically delivers 3-8% better timing and 5-10% better area compared to non-SPG on complex designs.

## Key Commands and Usage

### Design Setup

```tcl
# Read technology
set_technology -node 5
read_lef tech.lef macro.lef stdcell.lef

# Read libraries — NLDM or CCS
set_lib_cell_purpose -include optimization [get_lib_cells */BUFX*]
create_lib -technology tech.tf -ref_libs {std.ndm macro.ndm}

# Read RTL
read_file -type verilog {top.v sub1.v sub2.v}
elaborate top

# Read constraints
read_sdc top.sdc
```

### Compile Fusion

```tcl
# SPG compile — performs synthesis + coarse placement
compile_fusion -scan

# Non-SPG compile
set_app_options -name compile.flow.enable_spg -value false
compile_fusion
```

### Floorplanning

```tcl
initialize_floorplan -core_utilization 0.70 -core_offset {5 5}

# Macro placement
create_placement_blockage -boundary {{0 0} {10 100}} -type hard
set_macro_constraints -allowed_orientations {N FN} [get_cells -filter "is_hard_macro"]
create_macro_array -num_rows 2 -num_cols 4 -orientation N \
  -horizontal_channel_height 2.0 -vertical_channel_width 2.0 \
  [get_cells u_mem/ram*]

# Place macros
place_opt -floorplan
```

### Placement

```tcl
# Full placement optimization
place_opt

# With specific effort
set_app_options -name place_opt.flow.effort -value high
place_opt
```

### Clock Tree Synthesis

```tcl
# Define clock tree constraints
set_clock_tree_options -target_skew 0.050 -target_latency 0.300
create_routing_rule cts_ndr -widths {M3 0.1 M4 0.1 M5 0.1} \
  -spacings {M3 0.1 M4 0.1 M5 0.1}
set_clock_routing_rules -rules cts_ndr -min_routing_layer M3 -max_routing_layer M5

# CTS + post-CTS optimization
clock_opt
```

### Routing

```tcl
# Global + track assignment + detail routing
route_auto

# Post-route optimization
route_opt

# With specific focus
set_app_options -name route_opt.flow.enable_power -value true
route_opt
```

## Critical App Options

FC uses `app_options` instead of the traditional DC/ICC2 variable system.

### Synthesis App Options

```tcl
# Compile effort
set_app_options -name compile.flow.compile_effort -value high

# Enable retiming
set_app_options -name compile.flow.enable_retime -value true

# SPG control
set_app_options -name compile.flow.enable_spg -value true

# Clock gating
set_app_options -name compile.flow.clock_gate_insertion -value true

# Multi-Vt
set_app_options -name compile.flow.optimize_power -value true
```

### Placement App Options

```tcl
# Congestion effort
set_app_options -name place_opt.flow.congestion_effort -value high

# Timing effort
set_app_options -name place_opt.flow.timing_effort -value high

# Enable layer optimization
set_app_options -name place_opt.flow.enable_layer_optimization -value true
```

### CTS App Options

```tcl
# CTS engine
set_app_options -name cts.compile.enable_global_route -value true

# Useful skew
set_app_options -name clock_opt.flow.enable_ccd -value true

# Buffer/inverter cells for CTS
set_lib_cell_purpose -include cts [get_lib_cells "*/CK*"]
```

### Route App Options

```tcl
# Antenna fixing
set_app_options -name route.common.antenna_fixing -value true

# Crosstalk prevention
set_app_options -name route.common.threshold_noise_ratio -value 0.25

# Via optimization
set_app_options -name route.common.post_detail_route_redundant_via_insertion -value medium
```

## MMMC (Multi-Mode Multi-Corner) Setup

FC supports concurrent multi-scenario optimization, which is essential for advanced-node designs.

```tcl
# Create corners
create_corner ss_0p72v_125c
create_corner ff_0p88v_m40c
create_corner tt_0p80v_25c

# Create modes
create_mode func_mode
create_mode test_mode

# Create scenarios
create_scenario -name func_ss -mode func_mode -corner ss_0p72v_125c
create_scenario -name func_ff -mode func_mode -corner ff_0p88v_m40c
create_scenario -name test_ss -mode test_mode -corner ss_0p72v_125c

# Set scenario-specific constraints
current_scenario func_ss
read_sdc func_ss.sdc
set_operating_conditions ss_0p72v_125c

# Mark active scenarios for optimization
set_scenario_status func_ss -active true -setup true -hold true
set_scenario_status func_ff -active true -hold true
set_scenario_status test_ss -active true -setup true
```

## Common Issues and Fixes

### Issue: SPG Placement Is Poor After compile_fusion

- Verify that LEF/tech files and NDMS are loaded before compile. SPG needs physical data.
- Check that `compile.flow.enable_spg` is true.
- Ensure the floorplan dimensions are reasonable (60-75% utilization target).

### Issue: Large Timing Gap Between FC and PrimeTime

- Ensure parasitic extraction settings match: same RC corner, same extraction engine version.
- Check `set_app_options -name time.si_enable_analysis -value true` for SI-aware analysis.
- Verify POCV/AOCV library settings are consistent.
- Use `compare_timing` utility to identify systematic differences.

### Issue: High Congestion After place_opt

- Increase placement density screens: `set_app_options -name place.coarse.congestion_driven_max_util -value 0.85`
- Add soft placement blockages in congestion hotspots.
- Review macro channel spacing — insufficient channels cause local congestion.
- Enable congestion-aware restructuring in compile: `set_app_options -name compile.flow.enable_congestion_aware_restructuring -value true`

### Issue: Antenna Violations After Routing

- Enable antenna fixing: `set_app_options -name route.common.antenna_fixing -value true`
- Add diode insertion as fallback: `set_app_options -name route.detail.antenna_cell_name -value "ANTENNACELL"`
- Run `route_opt` with antenna fixing enabled post-route.

### Issue: Hold Violations Not Fixing

- Verify hold fixing is enabled: `set_app_options -name clock_opt.hold.effort -value high`
- Ensure delay cells are available: `set_lib_cell_purpose -include hold [get_lib_cells "*/DLY*"]`
- Check that the correct hold scenario is active and marked `-hold true`.

## Best Practices

1. **Use SPG flow** for all production tapeouts — the QoR advantage is consistent and significant.
2. **Start with high effort** for compile and place_opt on critical blocks; use medium for exploration runs.
3. **Set up MMMC from the beginning** — adding scenarios later forces re-optimization.
4. **Use `save_block` liberally** at each major stage — FC session recovery from saved blocks is fast.
5. **Monitor congestion maps** after placement — catching congestion early avoids routing DRC explosions.
6. **Run `check_design -checks all`** before each major step to catch setup errors early.
7. **Use `report_app_options -non_default`** to audit your settings before each run.
8. **Target PPA closure in FC** rather than deferring to standalone PT-ECO loops — FC's integrated timer makes in-tool closure more efficient.
