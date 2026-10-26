# Back-End Metal Stack: Layers, Routing Resources, and Design Considerations

## Overview

The back-end-of-line (BEOL) metal stack is the interconnect system that connects transistors to each other and to the outside world. It consists of multiple metal layers separated by dielectric, connected vertically by vias. Understanding the metal stack is fundamental to physical design because every signal, clock, and power connection must be routed through these layers.

The metal stack architecture, number of layers, metal thicknesses, and routing resources per layer directly impact timing, power, signal integrity, and routability of a design.

## Metal Layer Categories

Modern metal stacks are organized into three or four tiers based on wire thickness and pitch:

### Local Interconnect (M0/M1)

- Thinnest and tightest-pitch metal layers
- Used primarily within standard cells for internal connections
- At advanced nodes, M0 may be a dedicated intra-cell layer not available for inter-cell routing
- M1 pitch ranges from 64nm (22nm node) to 21nm (3nm node)
- Very high resistance per unit length due to thin, narrow cross-section
- Preferred routing direction is typically horizontal for M1

### Intermediate Metals (M2-M5/M6)

- Moderate pitch and thickness, used for the majority of signal routing
- Alternating preferred routing directions (H-V-H-V) to facilitate Manhattan routing
- M2 is the first general-purpose routing layer available to the place-and-route tool
- Pitch gradually increases from M2 upward (e.g., M2 at 36nm, M4 at 48nm at N7)
- These layers handle signal routing, local clock distribution, and short power connections
- Routing congestion is most critical on these layers

### Semi-Global Metals (M6/M7-M8/M9)

- Thicker metals with wider pitch (2x-4x the intermediate metal pitch)
- Lower resistance, suitable for:
  - Power grid stripes
  - Clock trunk routing
  - Long-distance signal routing for timing-critical nets
  - Bus routing
- Fewer routing tracks per unit width, so not suitable for dense signal routing

### Global Metals / Top Metals (M9/M10-M11/AP)

- Thickest metal layers, often including an aluminum cap (AP layer)
- Very low sheet resistance (< 0.05 ohm/square for thick Cu, ~0.01 for AP)
- Used exclusively for:
  - Power grid rings and wide stripes
  - Bond pad connections
  - RDL (redistribution layer) for flip-chip bumps
  - Package-level connections
- Typically only 1-2 layers in this tier

## Routing Resources Per Layer

The number of available routing tracks on each metal layer depends on the design area and metal pitch:

```
Tracks per layer = floor(die_dimension / metal_pitch)
```

For a 1mm x 1mm die at N7:
- M2 (36nm pitch): ~27,778 tracks
- M5 (48nm pitch): ~20,833 tracks
- M8 (80nm pitch): ~12,500 tracks

In practice, not all tracks are available:
- **Power grid**: Stripes on intermediate/upper metals consume routing tracks
- **Clock routing**: CTS uses tracks on preferred layers
- **Blockages**: Routing blockages from macros, IP blocks, and pin access reduce available tracks
- **Via access**: Track positions that cannot accommodate vias are effectively unusable

### Estimating Routing Demand

A rough estimate of routing demand:
- Signal nets consume ~3-4 tracks per net (average) across multiple layers
- A design with 500K nets needs ~1.5-2M track segments
- If the total available track supply is 2.5M, utilization is ~60-80%
- Congestion above 80-85% capacity on any local region causes routing failures

## Via Stacks

Vias connect adjacent metal layers. The via naming convention follows the metals they connect:

- VIA1 connects M1 to M2
- VIA2 connects M2 to M3
- And so on

### Single-Cut vs. Multi-Cut Vias

- **Single-cut via**: One via hole connecting two metals. Minimum area, but higher resistance and reliability risk
- **Multi-cut via (via array)**: Multiple via holes in a group. Lower resistance, better EM reliability, but requires more space
- Target: 90%+ multi-cut via rate for production designs
- Via optimization is a standard post-route step

### Via Stacking

When a signal must transition across multiple metal layers (e.g., M2 to M6), a via stack is required:
- Each layer transition needs its own via
- Stacked vias (VIA2 + VIA3 + VIA4 + VIA5) must each meet enclosure rules
- Stacked via pillars require adequate metal landing pads on intermediate layers
- Some processes restrict direct stacking (vias must be offset) for manufacturing reasons

### Via Resistance

Via resistance is significant and should not be ignored:
- Single M1-M2 via: ~5-20 ohms (depends on node)
- A via stack from M1 to M8 through 7 via levels: ~50-100+ ohms total
- For timing-critical nets, minimize layer transitions
- For power nets, use wide via arrays to reduce resistance

## RDL (Redistribution Layer)

For flip-chip packages, a redistribution layer is used to route signals from the die's top metal to bump pad locations:

- RDL is a thick metal layer (often aluminum or thick copper) above the top metal
- RDL pitch is much larger than signal routing metals (5-10 um)
- Used to redistribute IOs from the core to a bump array pattern
- Under-bump metallization (UBM) sits on top of RDL for solder bump attachment

Not all designs use RDL; wire-bond designs connect directly through bond pads on the top metal.

## Metal Fill Requirements

Metal fill (also called dummy metal or floating fill) is required on every metal and via layer to meet density rules:

### Purpose

1. **CMP uniformity**: Chemical Mechanical Polishing requires uniform metal density across the die to achieve flat topography
2. **Stress management**: Uniform density reduces mechanical stress variation
3. **Prevent dishing**: Large empty areas cause the metal to dish (become concave) during CMP

### Density Windows

- Density is checked in rectangular windows (e.g., 25x25 um, 50x50 um)
- Minimum density: typically 20-30% per window
- Maximum density: typically 70-85% per window
- Density gradient between adjacent windows must be below a threshold (e.g., 30%)

### Fill Types

- **Floating fill**: Electrically unconnected metal shapes. Simplest but adds parasitic capacitance to nearby signals
- **Grounded fill**: Fill shapes connected to VSS. Reduces noise but requires VSS connections
- **Timing-aware fill**: Fill shapes kept away from timing-critical nets to minimize capacitive impact

### Fill Insertion Strategy

1. Run density analysis to identify under-dense regions
2. Insert fill shapes meeting minimum size and spacing rules
3. Keep fill shapes away from critical nets (configurable keep-out distance)
4. Verify density after fill insertion
5. Re-extract parasitics and verify timing impact

## Practical Guidelines for PD Engineers

1. **Layer assignment planning**: Decide early which layers are for signals, clocks, and power. Document in the routing strategy
2. **Reserve upper metals for power**: Top 2-3 metal layers should be primarily reserved for power grid. Allowing signals on these layers complicates power integrity
3. **Preferred direction discipline**: Strongly follow preferred routing directions. Off-preferred routing increases cross-layer coupling and congestion
4. **Via minimization on critical paths**: Each via adds resistance and capacitance. Keep timing-critical paths on fewer layers
5. **NDR for clocks and critical signals**: Use wider wires and larger spacing on intermediate metals for clock trunks and critical buses
6. **Metal stack selection**: Choose the right number of metal layers based on design complexity. More layers = more cost per die. An 8M stack is significantly cheaper than a 12M stack
7. **Density awareness throughout flow**: Do not leave fill insertion to the last minute. Plan routing to avoid creating large empty regions that are hard to fill uniformly
8. **RDL planning for flip-chip**: Plan bump map and RDL routing early. Bump pitch and count constrain the IO count and placement
