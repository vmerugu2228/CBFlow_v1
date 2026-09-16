# TSMC Process Nodes: N7, N5, N3 and the FinFET to GAA Transition

## Overview

TSMC (Taiwan Semiconductor Manufacturing Company) is the world's leading foundry and defines the cutting edge of semiconductor manufacturing. For physical design engineers, understanding the characteristics and differences between TSMC's major nodes -- N7, N5, and N3 -- is essential for making informed decisions about design methodology, timing closure strategy, and physical implementation tradeoffs.

This document covers the key features of each node, the transition from FinFET to Gate-All-Around (GAA) architecture, metal stack evolution, cell architecture changes, and practical design rule comparisons.

## TSMC N7 (7nm FinFET)

### Process Characteristics

- **Transistor**: 2nd-generation FinFET
- **Fin pitch**: ~30nm
- **Gate pitch (CPP)**: ~54nm
- **Minimum metal pitch**: 36nm (M1, M2)
- **Lithography**: 193i immersion with multi-patterning (SADP/LELE); N7+ variant uses EUV on select layers
- **Voltage**: Typical 0.75V nominal
- **SRAM bit-cell**: ~0.027 um^2

### Cell Architecture

- Standard cell track heights: 7.5T (mainstream), 6T (high-density)
- 7.5T cells provide balanced routing resources and performance
- 6T cells push density but reduce internal routing tracks, creating pin access challenges
- Typical fin count per device: 2-3 fins for standard-Vt cells

### Design Rule Highlights

- Multi-patterning is required for M1-M4 and select via layers
- Coloring (decomposition) constraints impact routing legality
- End-of-line (EOL) rules are stringent due to lithography limitations
- Via enclosure rules are direction-dependent (prefer horizontal enclosure on even metals, vertical on odd)
- Metal minimum area rules prevent small floating shapes that are hard to print

### PD Considerations

- Routing congestion is a primary concern. M1-M2 pin access limits placement density
- NDR (non-default rules) for clocks: typically 2x width, 2x spacing with double-via
- Multi-patterning-aware routing is mandatory; the router must respect coloring constraints
- EUV variant (N7+) simplifies some metal layers, reducing coloring complexity

## TSMC N5 (5nm FinFET)

### Process Characteristics

- **Transistor**: 3rd-generation FinFET with improved fin profile
- **Fin pitch**: ~25-27nm
- **Gate pitch (CPP)**: ~48nm
- **Minimum metal pitch**: 28nm (M1, M2)
- **Lithography**: EUV used on ~14 critical layers; 193i for remaining layers
- **Voltage**: Typical 0.7V nominal
- **SRAM bit-cell**: ~0.021 um^2

### Cell Architecture

- Standard cell track heights: 6T (mainstream), 5T (high-density variant)
- 6T cells at N5 have fewer routing resources than 7.5T cells at N7
- Fin count: typically 2 fins, with some high-performance cells using 3 fins
- Reduced fin count means less drive per device; sizing granularity is coarser

### Design Rule Highlights

- EUV eliminates multi-patterning for many critical metal layers, simplifying routing
- However, EUV introduces stochastic printing effects (random via opens, line breaks)
- Via pillar rules: some via layers require "pillar" vias with specific aspect ratios
- Metal tip-to-tip rules become more restrictive
- M0 (below M1) routing layer may exist for intra-cell connections

### PD Considerations

- Pin access is the dominant placement challenge. Detailed pin access analysis is essential before global placement
- Wire resistance increases significantly (~40-50% vs N7 for same metal level) due to thinner, narrower wires and barrier effects
- Buffer insertion must be more aggressive to compensate for interconnect RC
- Clock tree synthesis is harder due to increased wire delay; consider useful skew and multi-source CTS
- Power grid IR drop is more critical due to higher current density per unit area

## TSMC N3 (3nm FinFET)

### Process Characteristics

- **Transistor**: Advanced FinFET (TSMC chose FinFET for N3, unlike Samsung's GAA at 3nm)
- **Fin pitch**: ~22-23nm
- **Gate pitch (CPP)**: ~45-48nm
- **Minimum metal pitch**: 21-23nm (M1, M2)
- **Lithography**: Extensive EUV usage (~20+ layers)
- **Voltage**: Typical 0.65-0.7V nominal
- **SRAM bit-cell**: ~0.0199 um^2

### Cell Architecture

- Standard cell track heights: 5T (high-density), 6T (performance)
- 5T cells offer the highest logic density ever achieved in a FinFET process
- Pin access is extremely constrained; some cells may have only 1-2 accessible M1 tracks
- Cell-level routing optimization becomes critical; libraries are co-optimized with the router

### Design Rule Highlights

- EUV covers most critical layers, but stochastic effects require additional design guards
- Very tight metal pitch introduces new local density and uniformity rules
- Self-aligned gate contact (SAGC) may be used for tighter gate-to-contact spacing
- Cut metal rules become more complex with multi-cut requirements

### PD Considerations

- Interconnect RC dominates delay for all but the shortest nets
- Detailed routing quality is as important as placement quality for timing closure
- Power delivery is a major challenge; denser power grid or back-side power delivery exploration
- SRAM density improvement is modest vs N5; diminishing returns on memory area scaling
- Analog/mixed-signal blocks are increasingly difficult; may stay at N5/N7 in chiplet configurations

## FinFET to GAA Transition

### TSMC N2 and Beyond

TSMC transitions from FinFET to GAA nanosheet architecture at the N2 node (expected 2025):

- **Nanosheet transistors**: Gate wraps around stacked horizontal nanosheets
- **Variable sheet width**: Unlike fins (fixed width), nanosheet width can be varied for performance/power tuning
- **Back-side power delivery network (BSPDN)**: Power rails move to the backside of the wafer, freeing front-side metal for signal routing
- **Benefits**: ~15% speed improvement or ~30% power reduction vs N3 at same speed

### PD Impact of GAA

- New cell libraries optimized for nanosheet architecture
- BSPDN fundamentally changes power grid design -- no more follow-pin power on M1
- Front-side routing resources increase significantly with BSPDN
- New design rules for nanosheet dimensions and spacing
- Timing characterization must account for nanosheet-specific effects

## Metal Stack Comparison

| Feature | N7 | N5 | N3 |
|---|---|---|---|
| Min metal pitch | 36nm | 28nm | 21-23nm |
| Total metal layers | 12-15 | 13-15 | 13-17 |
| M1 resistance (ohm/sq) | ~15 | ~25 | ~40 |
| EUV layers | 0 (4 for N7+) | ~14 | ~20+ |
| Dominant routing layers | M2-M5 | M2-M6 | M2-M7 |

Key trends across nodes:
- Metal resistance increases ~1.5-2x per node at lower metals
- More metal layers are added to compensate for reduced per-layer routing capacity
- Upper thick metals remain essential for power distribution
- Via resistance also increases, making multi-cut vias even more critical

## Design Rule Comparison

| Rule | N7 | N5 | N3 |
|---|---|---|---|
| Cell track height | 7.5T/6T | 6T/5T | 6T/5T |
| Multi-patterning | Heavy (193i) | Reduced (EUV) | Minimal (EUV) |
| Pin access tracks | 3-4 (7.5T) | 2-3 (6T) | 1-2 (5T) |
| Coloring constraints | Yes | Reduced | Minimal |
| EOL rules | Strict | Stricter | Strictest |
| Via pillar rules | No | Some layers | More layers |

## Practical Guidance

1. **Node selection**: Choose the node based on the design's primary requirement. N7 for mature ecosystem and cost, N5 for mainstream high-performance, N3 for leading-edge density
2. **Pin access analysis**: Run pin access checks early. At N5/N3, poor pin access can make a placement illegal even if it looks good on paper
3. **Wire RC budgeting**: At N5/N3, account for 40-100% higher wire delay than N7 for equivalent routing
4. **Power grid early**: IR drop budgets are tighter at each node. Design the power grid before detailed placement
5. **Multi-corner complexity**: Each node adds more PVT corners. Invest in efficient MCMM (multi-corner multi-mode) methodology
6. **Library quality**: At advanced nodes, library quality and completeness directly impact achievable QoR. Work closely with the library team
