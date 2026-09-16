# Place and Route Fundamentals

## Overview

Place and Route (PnR) is the core of physical design, transforming a gate-level netlist into a geometrically legal layout ready for fabrication. PnR encompasses floorplanning, power grid construction, cell placement, clock tree synthesis, signal routing, and optimization. The quality of PnR execution directly determines whether a chip meets its timing, power, area, and reliability targets.

## Placement

### Placement Stages

Placement proceeds through multiple refinement stages:

1. **Global Placement** — Assigns approximate locations to all standard cells. Uses analytical or quadratic solvers to minimize total wirelength while respecting density constraints. Cells may overlap at this stage.

2. **Legalization** — Snaps cells to legal row sites, resolves overlaps, and ensures all cells are on-grid. This is a constraint-satisfaction step that respects:
   - Row alignment and site spacing
   - Power rail connectivity (cells must be on correct VDD/VSS rows)
   - Well proximity rules

3. **Detail Placement** — Local optimization within a neighborhood. Swaps adjacent cells to reduce local wirelength, improve timing, and resolve congestion. Typically operates within a sliding window of 5-10 rows.

### Timing-Driven Placement

Modern placers are timing-driven: they read the SDC constraints and bias placement to minimize delay on critical paths.

**How it works:**

- The placer estimates net delays using a wire-load or Steiner tree model.
- Cells on critical timing paths are placed closer together.
- Non-critical cells may be displaced to relieve congestion, as long as they maintain positive slack.
- Net weighting assigns higher importance to timing-critical nets during the wirelength objective.

```tcl
# Increase timing weight in placement
set_app_options -name place_opt.flow.timing_effort -value high
```

### Congestion-Driven Placement

Congestion-driven placement prevents routing failures by spreading cells away from congested regions.

**Key concepts:**

- **Congestion map:** Tile-based grid showing demand vs. capacity for routing tracks.
- **Overflow:** When routing demand exceeds available tracks in a tile, overflow occurs.
- **Density screens:** Limit maximum cell utilization per tile (e.g., 85%) to reserve space for routing.

```tcl
# Set congestion effort
set_app_options -name place_opt.flow.congestion_effort -value high

# Limit placement density
set_app_options -name place.coarse.congestion_driven_max_util -value 0.82
```

### Cell Padding

Cell padding adds artificial spacing between standard cells to:

- Relieve local congestion
- Provide space for filler cell insertion
- Meet minimum spacing DRC rules for certain cell types (e.g., multi-Vt cells with different well implants)

```tcl
# Add 1-site padding on each side of all cells
set_cell_padding -left 1 -right 1 [get_lib_cells */*]

# Extra padding for specific cells (e.g., clock buffers)
set_cell_padding -left 2 -right 2 [get_lib_cells */CK*]
```

### Placement Blockages

Placement blockages prevent cells from being placed in specific regions:

- **Hard blockage:** No cells allowed — used for macro halos and keep-out zones.
- **Soft blockage:** Allows buffer/inverter insertion for optimization but prevents initial placement.
- **Partial blockage:** Limits utilization in the region (e.g., 50% max density).

```tcl
# Hard blockage around macros (halo)
create_placement_blockage -boundary {{10 10} {50 60}} -type hard

# Partial blockage for congestion relief
create_placement_blockage -boundary {{100 100} {200 200}} -type partial -blocked_percentage 40
```

## Floorplanning

Floorplanning defines the chip's physical architecture before detailed placement.

### Key Floorplan Decisions

1. **Die/core size:** Based on target utilization (typically 65-80%).
2. **IO/pad ring:** Placement of IO pads or bump locations.
3. **Macro placement:** SRAM, ROM, analog blocks positioned for optimal dataflow and minimal routing congestion.
4. **Power domain partitioning:** Voltage islands for multi-supply designs.
5. **Channel planning:** Routing channels between macros must accommodate signal and clock routing.

### Macro Placement Guidelines

- Place macros at the periphery to minimize routing obstructions.
- Align macros to the placement grid.
- Ensure pin accessibility — macro pins should face the standard cell region.
- Leave channels of at least 10-20 routing tracks between macros.
- Create halos around macros (typically 5-10 um) to prevent standard cells from crowding macro pins.

```tcl
# Macro halo
create_keepout_margin -type hard -outer {5 5 5 5} [get_cells -filter "is_hard_macro"]
```

## Power Grid (Power Planning)

A robust power grid is critical for low IR drop and electromigration compliance.

### Power Grid Structure

- **Rings:** Power/ground rings around the core and around macros.
- **Stripes:** Horizontal and vertical power stripes across the core.
- **Rails:** Standard cell power rails on the lowest metal layer (typically M1).
- **Vias:** Stacked vias connecting rings, stripes, and rails.

```tcl
# Create power ring
create_pg_ring -nets {VDD VSS} -layers {M8 M9} -widths {2.0 2.0} -spacing 1.0

# Create power stripes
create_pg_stripes -nets {VDD VSS} -layer M8 -direction vertical \
    -width 1.0 -spacing 0.5 -set_to_set_distance 40.0

create_pg_stripes -nets {VDD VSS} -layer M9 -direction horizontal \
    -width 1.0 -spacing 0.5 -set_to_set_distance 40.0

# Connect standard cell rails to stripes
create_pg_vias -nets {VDD VSS}
```

### Power Grid Validation

After power grid creation, always verify:

- Connectivity from pads/bumps to all standard cell rails
- IR drop analysis at target current density
- EM current density on all PG segments

## Key Metrics to Monitor

### Timing

| Metric | Target |
|--------|--------|
| WNS (Worst Negative Slack) | > 0 ps (positive) |
| TNS (Total Negative Slack) | > -100 ps at placement |
| WHS (Worst Hold Slack) | > 0 ps after CTS |

### Physical

| Metric | Guideline |
|--------|-----------|
| Core utilization | 65-80% |
| Routing congestion overflow | < 1% after global route |
| Cell density peak | < 90% in any tile |
| Wirelength | Minimize; compare across runs |

### Power

| Metric | Guideline |
|--------|-----------|
| IR drop (static) | < 5% of VDD |
| IR drop (dynamic) | < 10% of VDD |
| EM current density | Below foundry limits |

## Common Issues and Fixes

**Issue: Placement congestion hotspots**
- Add partial placement blockages in congested areas.
- Increase macro channels.
- Reduce core utilization by 2-5%.
- Enable congestion-driven placement with high effort.

**Issue: Large timing degradation from global placement to legalization**
- Cells are being displaced too far during legalization. Reduce utilization or add soft blockages.
- Check for macros blocking key data paths — rearrange macro placement.

**Issue: Standard cells placed inside macro halos**
- Verify that placement blockages or keepout margins are correctly defined.
- Check that the blockage type is "hard" not "soft."

**Issue: Unroutable pin access on macros**
- Rotate macros so pins face the routing channels.
- Increase halo size.
- Add routing blockages to force routing around obstructed regions.

**Issue: Power grid is disconnected**
- Run connectivity check: `check_pg_connectivity`
- Ensure vias are created between all power grid layers.
- Verify that macro power pins are connected to the grid.

## Best Practices

1. **Iterate on floorplan before committing to full PnR** — macro placement changes are cheap early and catastrophically expensive late.
2. **Run trial routing** after placement to assess congestion before investing time in CTS and detail routing.
3. **Use density screens** — never allow 100% utilization anywhere in the design.
4. **Verify power grid early** with static IR drop analysis before placement.
5. **Monitor the placement-to-route timing correlation** — if WNS degrades by more than 50 ps after routing, revisit placement constraints.
6. **Use incremental optimization** rather than re-running full placement from scratch when making late-stage changes.
7. **Keep macro placement consistent** across synthesis, PnR, and extraction to maintain timing correlation.
8. **Document your floorplan decisions** — macro positions, blockage rationale, power grid topology — as they affect all downstream steps.
