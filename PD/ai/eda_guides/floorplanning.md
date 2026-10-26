# Floorplanning: Die Size, Macro Placement, and Channel Planning

## Overview

Floorplanning is the first and arguably most impactful step in physical design. It defines the chip's physical organization: die size, macro locations, power grid structure, IO placement, and routing channel allocation. A good floorplan enables smooth implementation; a poor one guarantees weeks of debugging and rework.

Floorplanning is part art, part engineering. It requires understanding the design's architecture, data flow, timing requirements, and physical constraints simultaneously.

## Die Size Estimation

### Core-Limited vs. Pad-Limited

The first question is whether die size is determined by internal logic area or by IO pad count:

**Core-limited design:**
- Die size is determined by the area of logic, memories, and macros
- Total core area = (standard cell area / target utilization) + macro area + overhead
- Standard cell area comes from synthesis reports
- Target utilization: 60-80% (higher utilization = more congestion risk)

**Pad-limited design:**
- Die size is determined by the number of IO pads and their pitch
- Minimum die perimeter = number_of_pads x pad_pitch
- The internal area may be under-utilized

### Die Size Calculation

For a core-limited design:

```
Core area = SC_area / utilization + macro_area + channel_area + power_grid_overhead
Die area = core_area + pad_ring_area
```

Example:
- Synthesis reports 2.0 mm^2 of standard cell area
- Target utilization: 70%
- Effective SC area: 2.0 / 0.70 = 2.86 mm^2
- Macro area: 1.5 mm^2
- Channels and overhead: 0.5 mm^2
- Total core area: 4.86 mm^2
- Die dimension: ~2.2 mm x 2.2 mm (plus pad ring)

### Utilization Guidelines

| Utilization | Use Case | Risk |
|---|---|---|
| 50-60% | Low-risk, easy routing | Wastes area |
| 65-70% | Standard target | Good balance |
| 70-75% | Aggressive density | Congestion likely |
| 75-80% | Very aggressive | Significant congestion risk |
| >80% | Exceptional only | Almost certain routing failure |

At advanced nodes (N7/N5/N3), lower utilization targets are recommended due to more constrained routing.

## Macro Placement Strategies

### General Principles

1. **Data flow alignment**: Place macros to minimize wire length for the dominant data flow. If data flows from left to right, place source macros on the left and sink macros on the right
2. **Edge and corner placement**: Place macros at die edges or corners to avoid fragmenting the standard cell placement area
3. **Memory banking**: Group SRAM banks together with shared decoders/controllers nearby
4. **Pin access**: Orient macros so that frequently-accessed pins face the logic that connects to them
5. **Avoid central placement**: Macros in the center of the die create routing congestion. Push macros to edges when possible

### Macro Placement Methodology

Step-by-step approach:

1. **List all macros**: Catalog every hard macro with dimensions, pin count, and IO edge requirements
2. **Identify fixed macros**: PHYs, SerDes, and IO-connected macros have fixed edge locations
3. **Analyze connectivity**: Use fly-line (ratsnest) analysis to understand which macros connect to which
4. **Place fixed macros first**: Lock PHYs and IO-connected macros at their required positions
5. **Place large macros next**: Large SRAMs and analog macros, guided by connectivity and data flow
6. **Place remaining macros**: Smaller macros in remaining positions, optimizing for wire length
7. **Verify channels**: Ensure adequate routing channels between all macros
8. **Iterate**: Adjust placement based on congestion estimates, timing analysis, and routing resource analysis

### Macro Orientation

Each macro can be placed in one of eight orientations (R0, R90, R180, R270, MX, MY, MX90, MY90). Choose orientation based on:
- Pin accessibility (data pins face the logic)
- Power pin alignment with the power grid
- DRC rules (some macros have orientation restrictions)

### Macro Halo

Add placement halos around macros:
- 5-10 um for small macros
- 10-20 um for large macros with many pins
- Larger halos for analog macros requiring noise isolation

## Channel Planning

### What Are Channels?

Channels are the routing corridors between macros and between macros and the die edge. Adequate channel width is essential for:
- Signal routing between blocks
- Power grid stripes passing through
- Clock tree routing
- Feedthrough connections

### Channel Width Estimation

Minimum channel width depends on:
- Number of signals crossing the channel
- Power stripes in the channel
- Metal pitch on the layers used

```
Min channel width = max(signal_demand, power_stripe_demand)
Signal demand = (crossing_nets x tracks_per_net) / available_layers x metal_pitch
Power demand = num_stripes x (stripe_width + stripe_spacing)
```

### Channel Planning Guidelines

- Minimum 10-20 um between macros for signal routing
- 30-50 um between macro and die edge for power grid and routing
- Wider channels (50-100 um) for high-fanout buses crossing between blocks
- Never place macros abutting with no channel (unless designed for it)

## Pin Access Analysis

### Fly-Line Analysis

After initial macro placement, run fly-line (ratsnest) analysis:
- Visualize the connection between every pair of connected instances
- Identify congested regions where many fly-lines converge
- Detect macros that are placed far from their connected logic
- Use fly-line length histogram to identify placement quality

### Pin Accessibility Check

Verify that all macro pins are accessible:
- No pin should face another macro with zero routing channel
- Pins on higher metal layers need via-down access to routing layers
- Dense pin arrays (e.g., wide SRAM data buses) need adequate channel width

## Floorplan Quality Metrics

### Congestion Estimation

Modern PnR tools provide early congestion estimates after global placement:
- **GRC (Global Routing Congestion)**: Shows overflow by region
- **Target**: No hotspots with >100% congestion on any layer
- **Fix**: Adjust macro placement, widen channels, reduce utilization

### Wire Length Estimation

- Total half-perimeter wire length (HPWL) is a proxy for routing quality
- Compare HPWL across floorplan iterations
- Lower HPWL generally means better timing and less congestion

### Timing Estimation

- Run a quick global place and timing estimate after floorplanning
- Identify paths that are failing by large margins -- these indicate floorplan issues
- Paths crossing many channels or going around macros may need floorplan adjustment

## Power Grid Integration

The floorplan must accommodate the power grid:
- Reserve metal layers for power stripes
- Plan stripe locations to pass through channels
- Align macro power pins with power stripes
- Leave space for power switches in power-gated domains
- Verify that power stripes do not conflict with macro pin access

## Special Considerations

### Multi-Voltage Domains

- Group cells from the same voltage domain together
- Place level shifters and isolation cells at domain boundaries
- Ensure power grid supports multiple supplies
- Plan domain boundaries during floorplanning, not during placement

### Clock Domain Planning

- Place clock sources (PLLs) and primary clock sinks in proximity
- Plan clock tree routing corridors
- Keep clock domain crossings in well-defined regions

### DFT Considerations

- Scan chain ordering benefits from physical proximity of scan cells
- Place JTAG/TAP controller near test IO pads
- BIST controllers should be near the memories they test
- Plan for at-speed test clock routing

## Practical Guidance

1. **Start with a sketch**: Before opening the tool, sketch the floorplan on paper based on the block diagram and data flow
2. **Iterate rapidly**: Expect 5-10 floorplan iterations. Automate floorplan generation for quick exploration
3. **Validate early**: Run quick placement and congestion analysis after each iteration. Do not spend days on detailed placement before validating the floorplan
4. **Document constraints**: Record all placement constraints, channel requirements, and keep-outs in a constraint file
5. **Aspect ratio flexibility**: If possible, explore different die aspect ratios. A 2:1 aspect ratio may floorplan better than 1:1 for some designs
6. **Plan for ECO space**: Leave 2-5% area for engineering change orders (ECOs). Distribute spare cells across the design
7. **Review with architects**: Share the floorplan with the system architect to validate data flow and block connectivity assumptions
8. **Benchmark against similar designs**: If a previous version exists, compare macro count, die size, and utilization for sanity checking
