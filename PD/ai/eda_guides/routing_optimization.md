# Routing Optimization: Post-Route Timing, Via Optimization, and Signal Integrity

## Overview

Routing is the process of creating the physical metal interconnections between all placed cells. The router must connect every net while respecting design rules (DRC), meeting timing constraints, staying within routing resource limits, and maintaining signal integrity. Post-route optimization is then applied to fix timing violations, improve via reliability, manage antenna effects, and mitigate crosstalk.

Routing and post-route optimization are where the design converges toward its final quality. The decisions made during and after routing determine whether the chip meets signoff requirements.

## Routing Flow

### Global Routing

Global routing determines the approximate path for each net through the routing grid:
- The chip is divided into global routing cells (GRCs)
- Each GRC has a capacity (number of tracks) per metal layer
- The global router assigns each net to a sequence of GRCs
- The objective is to minimize total wire length while keeping demand below capacity
- Global routing identifies congestion hotspots (GRCs with demand > capacity)

### Track Assignment

Track assignment refines global routes to specific metal tracks:
- Within each GRC, nets are assigned to specific routing tracks
- Track assignment respects spacing rules and preferred directions
- This step bridges global and detailed routing

### Detailed Routing

Detailed routing creates the actual metal shapes and vias:
- Each net gets exact geometric shapes on specific metal layers
- The router resolves local DRC violations (spacing, width, via enclosure)
- Detailed routing handles jogs, bends, via placement, and layer transitions
- This is the most computationally expensive routing step

### Post-Route Optimization

After routing is complete, optimization passes improve the design:
- Timing optimization (buffer insertion, cell resizing, wire optimization)
- Via optimization (single-cut to multi-cut conversion)
- Antenna fixing (diode insertion or rerouting)
- Crosstalk mitigation (wire spreading, shielding)
- DRC fixing (incremental reroute of violating segments)

## Post-Route Timing Optimization

### Why Post-Route Timing Differs from Pre-Route

Pre-route timing uses estimated wire delays (based on Steiner tree or global route estimates). Post-route timing uses actual extracted parasitics from the routed geometry. Differences arise from:

- Actual routing detours (longer than estimated)
- Crosstalk-induced delay (coupling to adjacent wires)
- Via resistance (actual via count and type)
- Layer assignment (different layers have different RC per unit length)

Post-route timing is always worse than pre-route estimates for some paths and better for others. The net effect requires careful analysis.

### Post-Route Optimization Techniques

1. **Wire optimization**: Reroute timing-critical nets on lower-resistance (upper) layers
2. **Buffer insertion**: Add buffers on long nets to reduce delay
3. **Cell resizing**: Upsize cells on critical paths, downsize cells on non-critical paths
4. **Vt swapping**: Swap to LVT on critical paths, HVT on non-critical paths for power
5. **Logic restructuring**: Clone high-fanout drivers, decompose complex gates
6. **Layer promotion**: Move critical net segments to upper (lower resistance) metal layers

### Diminishing Returns

Each optimization iteration yields smaller improvements. Typical convergence:
- 1st iteration: 40-60% of violations fixed
- 2nd iteration: 20-30% of remaining violations fixed
- 3rd iteration: 10-15% of remaining violations fixed
- Beyond 3-4 iterations, improvement is marginal and runtime increases

## Via Optimization

### Single-Cut vs. Multi-Cut Vias

Single-cut vias (one via hole) have higher resistance and are more susceptible to manufacturing defects. Multi-cut vias (2 or more via holes) provide:

- **Lower resistance**: Multiple parallel vias reduce total via resistance
- **Better reliability**: Redundancy -- if one via is defective, others carry the current
- **Lower EM risk**: Current is distributed across multiple vias
- **Improved yield**: Manufacturing variation is less likely to affect all vias simultaneously

### Via Optimization Process

1. After detailed routing, identify all single-cut vias
2. Attempt to replace each single-cut via with a multi-cut via array
3. Check DRC legality of the multi-cut via (sufficient space for additional cuts)
4. Accept the replacement if DRC-clean; keep single-cut otherwise
5. Target: >90% multi-cut via rate (some single-cut vias are unavoidable in tight spaces)

### Via Optimization Impact

- Negligible impact on timing (via resistance changes are small per via)
- Significant impact on yield and reliability
- Foundries may require minimum multi-cut via percentage for yield qualification
- Multi-cut via optimization should run after all routing modifications are complete

## Wire Spreading

### Concept

Wire spreading takes advantage of available routing space to increase spacing between parallel wires:

- After routing, some tracks may be unused between routed wires
- The router can push wires apart to use this space
- Increased spacing reduces capacitive coupling between wires
- Benefits: reduced crosstalk, improved timing (less coupling capacitance)

### When to Apply

- After detailed routing is complete
- On layers where coupling is most critical (tight-pitch lower metals)
- Focus on timing-critical nets and clock nets
- Wire spreading may increase wire length slightly (due to jog insertion) but usually improves overall timing

## Antenna Fixing

### What Is the Antenna Effect?

During manufacturing, metal layers are fabricated sequentially. Before all connections are complete, partially fabricated metal segments can collect charge from the plasma etch process. This charge accumulates on the metal and, if connected to a gate oxide through a via, can damage the thin gate oxide.

### Antenna Rules

The antenna ratio is the ratio of exposed metal area to connected gate area:
```
Antenna ratio = Metal_area_connected_to_gate / Gate_area
```
If this ratio exceeds the allowed limit (varies by process, typically 400-1000:1), the antenna rule is violated.

### Antenna Fixing Methods

1. **Diode insertion**: Add a reverse-biased diode near the gate input. The diode provides a discharge path for accumulated charge. This is the most common fix
2. **Rerouting**: Change the route to reduce the metal area before the via connection to the gate. For example, connect to the gate from a higher metal layer (bridge routing)
3. **Layer hopping**: Add via jumps to break long metal segments into shorter segments on different layers

### Antenna Analysis and Fixing Flow

1. Run antenna analysis after routing
2. Identify all nets violating antenna ratios
3. Apply automatic antenna fixing (diode insertion or rerouting)
4. Re-run antenna analysis to verify all violations are fixed
5. Verify that fixes do not introduce new DRC or timing violations

## Crosstalk Mitigation

### Crosstalk Mechanisms

Crosstalk occurs when a switching signal (aggressor) couples capacitively to a neighboring signal (victim):

- **Functional crosstalk (glitches)**: Aggressor transition induces a voltage glitch on the victim. If the glitch exceeds the noise margin, it can cause logic errors
- **Timing crosstalk (delta delay)**: Aggressor transition changes the effective delay of the victim signal. Same-direction switching speeds up the victim; opposite-direction slows it down

### Crosstalk Impact

- **Setup timing**: Opposite-direction crosstalk increases delay on critical paths, causing setup violations
- **Hold timing**: Same-direction crosstalk decreases delay on short paths, causing hold violations
- **Noise**: Glitches can cause functional failures, especially on asynchronous signals and level-sensitive latches

### Mitigation Techniques

1. **Wire spacing**: Increase spacing between aggressors and victims. NDR rules (2x spacing) are effective
2. **Shielding**: Route VDD or VSS wires between an aggressor and victim. Complete isolation but consumes routing resources
3. **Net ordering**: Route timing-critical nets first to give them preferred positions with less coupling
4. **Layer assignment**: Separate critical signals to different layers
5. **Buffer insertion**: Adding buffers reduces the length over which coupling occurs and provides drive strength to resist noise

## NDR (Non-Default Rules) for Critical Nets

NDR rules specify wider wires and larger spacing for specific nets:

### Common NDR Applications

- **Clock nets**: 2x width, 2x spacing, double-cut vias. Reduces clock jitter and crosstalk sensitivity
- **Critical data paths**: 2x spacing on timing-critical nets to reduce coupling
- **High-speed buses**: Custom width/spacing for controlled impedance
- **Analog signals**: Maximum spacing, shielding for noise immunity

### NDR Implementation

```
Define NDR rule:
  create_routing_rule ndr_clock -widths {M2:0.072 M3:0.072 M4:0.072} \
    -spacings {M2:0.072 M3:0.072 M4:0.072} -min_cuts {VIA1:2 VIA2:2 VIA3:2}

Apply to clock nets:
  set_routing_rule [get_nets clk*] -rule ndr_clock
```

### NDR Trade-offs

- NDR nets consume more routing resources (2x width + 2x space = 4x track consumption)
- Excessive NDR usage causes congestion
- Apply NDR only to nets that need it (clocks, timing-critical paths)
- Verify that NDR does not cause routing overflow

## Practical Guidance

1. **Route clocks first**: Prioritize clock routing with NDR before signal routing
2. **Monitor congestion during routing**: If overflow persists after routing, the design needs placement or floorplan changes, not just routing effort
3. **Extract and analyze early**: Run post-route extraction (SPEF) and timing analysis after the first routing pass. Identify problem areas early
4. **Via optimization last**: Run via optimization after all timing and DRC fixes are complete
5. **Antenna as part of signoff**: Include antenna checking in the signoff DRC deck, not just the PnR tool's internal check
6. **Crosstalk corners**: Analyze crosstalk at the corner with maximum coupling capacitance (typically slow process, high temperature)
7. **NDR budget**: Plan routing resources for NDR nets during floorplanning. Reserve capacity on clock layers
8. **Incremental routing**: After ECO changes, use incremental routing to fix only affected nets rather than rerouting everything
