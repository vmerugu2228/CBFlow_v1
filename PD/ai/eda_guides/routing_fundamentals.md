# Routing Fundamentals

## Overview

Routing is the process of creating physical metal interconnections between the pins of placed standard cells, macros, and I/O pads. It is the final geometric realization of the netlist connectivity. Routing quality directly impacts timing (wire delay, crosstalk), power (coupling capacitance, resistance), reliability (electromigration, antenna effects), and manufacturability (DRC clean layout).

## Routing Stages

### 1. Global Routing

Global routing divides the chip into a coarse grid of rectangular tiles (GCells) and assigns each net to a sequence of tiles, creating a rough routing topology without determining exact wire positions.

**Key objectives:**

- Minimize total wirelength across all nets
- Distribute routing demand evenly across tiles (congestion balancing)
- Respect routing layer capacities (tracks available per tile)

**Congestion is measured as:** demand / capacity per GCell. Overflow occurs when demand exceeds capacity.

```tcl
# In Innovus
setNanoRouteMode -routeWithTimingDriven true
globalRoute

# In FC
route_global
```

### 2. Track Assignment

Track assignment maps each global route segment to a specific routing track within its assigned tile. This intermediate step bridges the gap between global routing (tile-level) and detail routing (exact geometry).

- Assigns nets to specific tracks while respecting spacing rules
- Resolves conflicts where multiple nets compete for the same track
- Minimizes via usage by keeping nets on the same layer when possible

### 3. Detail Routing

Detail routing creates the exact geometric shapes (metal rectangles and vias) for every net, ensuring full compliance with all design rules.

**Key actions during detail routing:**

- Wire geometry creation on assigned layers and tracks
- Via insertion at layer transitions
- DRC checking and violation resolution
- Jog insertion to resolve spacing violations
- Search and repair iterations to fix remaining DRC errors

```tcl
# In Innovus
detailRoute

# Or combined global + detail
route_design

# In FC
route_auto
```

### 4. Post-Route Optimization and Repair

After initial detail routing, the router performs iterative repair to fix remaining DRC violations, optimize via usage, and improve timing.

```tcl
# In Innovus
opt_design -post_route

# In FC
route_opt
```

## Routing Concepts

### Metal Layer Stack

Modern process nodes use 8-15+ metal layers. Each layer has a preferred routing direction:

| Layer | Direction | Typical Use |
|-------|-----------|-------------|
| M1 | Horizontal | Standard cell internal routing, pins |
| M2 | Vertical | Local interconnect |
| M3 | Horizontal | Local/semi-global routing |
| M4 | Vertical | Semi-global routing |
| M5 | Horizontal | Semi-global routing, clock trunks |
| M6 | Vertical | Global routing, power |
| M7+ | Alternating | Global routing, power stripes |

Higher metal layers have lower resistance (thicker, wider) but higher capacitance to adjacent layers. They are preferred for long-distance and clock routing.

### Preferred Direction Routing

Each metal layer has a preferred routing direction (horizontal or vertical). Routing in the preferred direction minimizes via usage and DRC violations. Non-preferred direction (wrong-way) routing is sometimes necessary but should be minimized.

### Via Optimization

Vias are the vertical connections between metal layers. They contribute significant resistance and are potential yield-loss sites.

**Redundant via insertion:** After routing, tools insert additional vias (double or triple vias) wherever space permits. This improves yield and reduces via resistance.

```tcl
# Enable redundant via insertion
setNanoRouteMode -droutePostRouteViaInsertion high
# Or in FC
set_app_options -name route.common.post_detail_route_redundant_via_insertion -value medium
```

**Via rules:**

- Single-cut vias: minimum area, used where space is limited
- Multi-cut vias: multiple cuts in parallel, lower resistance, better yield
- Stacked vias: vias spanning multiple layers, used for power grid connections

### Non-Default Rules (NDR)

NDR specifies wider wires and/or larger spacing for specific nets. Used for:

- Clock nets (reduced RC delay, noise immunity)
- Critical timing nets (reduced resistance)
- High-current power nets (electromigration compliance)

```tcl
# Define NDR
add_ndr -name wide_rule -width_multiplier {M3:M5 2} -spacing_multiplier {M3:M5 2}

# Apply to specific nets
set_routing_rule -nets {clk_net critical_bus[*]} -rule wide_rule
```

## DRC Fixing

Design Rule Check violations after routing must be resolved to zero for tapeout.

### Common DRC Violation Types

- **Short:** Two different nets occupying the same metal space. Fix by rerouting one of the nets.
- **Spacing:** Insufficient space between adjacent wires. Fix by spreading or jogging wires.
- **MinArea:** Wire segment does not meet minimum metal area. Fix by extending the wire or adding a metal patch.
- **MinWidth:** Wire is narrower than the minimum width for the layer. Fix by widening or rerouting.
- **Via enclosure:** Insufficient metal overlap around a via. Fix by extending the metal landing pad.
- **MinStep:** Jog in wire violates minimum step rule. Fix by smoothing the jog.

### DRC Repair Strategies

```tcl
# In Innovus — run ECO routing for DRC fixing
setNanoRouteMode -drouteUseMultiCutViaEffort high
globalDetailRoute

# Verify DRC
verify_drc -limit 1000

# Targeted repair
editTrim -net net_name
ecoRoute
```

## Antenna Fixing

### The Antenna Effect

During fabrication, metal layers are deposited and etched sequentially. Long metal wires connected to gate oxide can accumulate charge during plasma etching. If the charge exceeds the gate oxide tolerance, it causes damage (antenna effect).

**Antenna ratio:** The ratio of metal area exposed during etching to the gate oxide area connected to that metal. Foundries specify maximum allowed antenna ratios per layer.

### Antenna Fixing Strategies

1. **Layer hopping:** Route part of the wire on a higher metal layer, breaking the antenna ratio at the lower layer.
2. **Diode insertion:** Place antenna diodes near affected gates to provide a discharge path.
3. **Buffer insertion:** Insert a buffer to break the direct metal-to-gate connection.

```tcl
# Enable antenna fixing during routing
setNanoRouteMode -drouteFixAntenna true
setNanoRouteMode -routeAntennaCellName "ANTENNACELLBWP7T"

# Post-route antenna repair
repair_antenna -diode_cell ANTENNACELLBWP7T

# Verify antenna
verifyProcessAntenna
```

## Crosstalk-Aware Routing

### Crosstalk Mechanisms

When two parallel wires on the same layer switch simultaneously, coupling capacitance between them causes:

- **Delay increase (victim slowing):** Aggressor switches opposite to victim, adding delay.
- **Delay decrease (victim speeding):** Aggressor switches same direction as victim.
- **Glitch (noise):** Aggressor switches while victim is stable, inducing voltage bump.

### Crosstalk Prevention During Routing

```tcl
# Enable SI-aware routing
setNanoRouteMode -routeWithSiDriven true
setNanoRouteMode -routeWithSiPostRouteFix true

# Set noise threshold
set_app_options -name route.common.threshold_noise_ratio -value 0.25

# Use shielding for critical nets
create_routing_rule shielded_rule \
    -shield_widths {M3 0.05 M4 0.05} \
    -shield_spacings {M3 0.03 M4 0.03}
```

### Post-Route SI Fixing

- **Net re-ordering:** Change the relative position of aggressor and victim.
- **Spacing increase:** Add space between aggressor and victim wires.
- **Layer change:** Move one net to a different layer.
- **Buffer insertion:** Reduce victim net transition time to reduce susceptibility.
- **Shielding:** Insert grounded shield wires between critical nets.

## Routing Congestion Management

### Identifying Congestion

```tcl
# Generate congestion report
reportCongestion -hotSpot

# View congestion map in GUI
gui_show_congestion_map
```

### Congestion Mitigation

1. **Macro channel spacing:** Ensure at least 10-20 tracks between macros for signal routing.
2. **Pin access optimization:** Orient macros so pins face open routing channels.
3. **Placement density control:** Reduce local utilization in congested regions.
4. **Layer promotion:** Move long nets to upper layers to free lower-layer resources.
5. **Topology optimization:** Restructure net topology (Steiner tree vs. chain) to reduce wire demand.
6. **Blockage management:** Add routing blockages to force nets around congested areas.

## Common Issues and Fixes

**Issue: Persistent DRC violations after multiple route_opt iterations**
- Check for placement legality issues — illegal cell positions cause unsolvable DRC.
- Verify that all routing layers have sufficient tracks (check GCell capacity).
- Look for pin access problems on macros — add routing guide to help the router.
- Consider reducing utilization in the problem area.

**Issue: Timing degrades significantly after routing**
- Check for long detours caused by congestion — the router may be taking suboptimal paths.
- Enable timing-driven routing: `setNanoRouteMode -routeWithTimingDriven true`
- Verify that critical nets are not being routed on high-resistance lower layers.

**Issue: Excessive via count**
- Allow wider layer ranges for routing to reduce layer transitions.
- Enable via optimization: redundant vias improve reliability but check total via count.
- Review topology — chain topology may use fewer vias than Steiner tree for some nets.

**Issue: Metal density violations (too sparse or too dense)**
- Run metal fill insertion after routing: `addMetalFill`
- Adjust fill rules to meet foundry density requirements (typically 20-80% per layer).
- Exclude fill from timing-critical regions if capacitance impact is significant.

## Best Practices

1. **Route with timing and SI driven modes enabled** — the runtime penalty is small, the QoR benefit is significant.
2. **Run global route after placement** to assess congestion before investing time in CTS and detail routing.
3. **Use NDR for clock nets** — double-width, double-spacing minimum.
4. **Target zero DRC after detail route** — every additional DRC-fix iteration risks disturbing previously clean nets.
5. **Enable redundant via insertion** — it improves yield with minimal timing impact.
6. **Verify antenna rules** as part of the routing flow, not as a post-routing afterthought.
7. **Monitor routing layer utilization** — no single layer should exceed 80% utilization.
8. **Keep lower metals (M1-M2) for local routing** — avoid long M1/M2 routes that cause congestion and SI issues.
9. **Verify connectivity after routing** — run `verify_connectivity` to catch open nets.
10. **Save the design before and after routing** — routing is time-consuming, and a checkpoint allows recovery.
