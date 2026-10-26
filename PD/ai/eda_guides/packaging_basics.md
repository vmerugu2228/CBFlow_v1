# Packaging Basics

## Overview

IC packaging provides the physical, electrical, and thermal interface between the silicon die and the printed circuit board (PCB). The package protects the die from mechanical damage and environmental contamination, provides electrical connections from die pads to board-level pins, and dissipates heat generated during operation. Packaging decisions directly affect PD engineers through bump map constraints, package parasitics, thermal limits, and I/O planning. This guide covers the major packaging technologies, their tradeoffs, and their impact on physical design.

## Package Functions

### Electrical Connection

The package routes signals and power from the tiny die pads (50-100um pitch) to the much larger board-level connections (0.4-1.0mm pitch). This fan-out is the fundamental geometric challenge of packaging.

### Mechanical Protection

The die is a thin, brittle silicon wafer fragment. The package provides structural support, protects against mechanical shock and vibration, and shields the die from moisture and contaminants.

### Thermal Management

Every watt of power consumed by the die must be dissipated through the package. The package's thermal resistance (junction-to-ambient, theta_JA) determines the maximum power the die can sustain without exceeding its operating temperature limit.

### Signal Integrity

Package parasitics (inductance, capacitance, resistance) affect signal integrity for high-speed I/O. Package design must minimize crosstalk, impedance discontinuities, and resonance.

## Wire Bond Packaging

### Technology

Gold or copper wires connect die bond pads to package lead fingers. The die sits face-up on a die paddle (lead frame) or substrate, and wires are bonded from each pad to the corresponding package pin.

### Characteristics

- **Pad pitch**: 50-80um (limited by wire bonding tool capability)
- **Wire length**: 1-5mm (creates parasitic inductance of 1-5nH per wire)
- **Cost**: Low (mature, high-volume technology)
- **Pin count**: Up to ~500 pins (limited by die edge perimeter)
- **Speed**: Suitable for signals up to ~200 MHz (wire inductance limits bandwidth)

### Package Types

- **QFP (Quad Flat Package)**: Leads on all four sides; low pin count, very low cost
- **QFN (Quad Flat No-lead)**: Leads on the bottom surface; smaller footprint than QFP
- **BGA with wire bond**: Wire bond to a laminate substrate with solder balls on the bottom

### Physical Design Impact

- Bond pads must be on the die periphery (edge pads)
- Pad pitch limited by wire bonding rules
- Wire inductance creates ground bounce for SSO analysis
- Power/ground pads must be distributed around the perimeter for adequate PDN
- No access to die center for I/O connections

## Flip-Chip Packaging

### Technology

The die is flipped face-down and connected to the package substrate through solder bumps. This eliminates wire bonds and allows connections across the entire die surface, not just the periphery.

### Characteristics

- **Bump pitch**: 100-200um (standard); 40-80um (fine pitch for advanced nodes)
- **Inductance**: Much lower than wire bond (0.1-0.5nH per bump)
- **Cost**: Higher than wire bond (requires bump processing and substrate with fine routing)
- **Pin count**: Thousands of pins (full die area available for bumps)
- **Speed**: Suitable for multi-GHz signaling

### Bump Types

- **C4 bumps (Controlled Collapse Chip Connection)**: Solder bumps, 100-200um pitch. Standard for decades
- **Copper pillar bumps**: Copper post with solder cap, enabling finer pitch (40-80um). Used in advanced nodes
- **Micro-bumps**: Very fine pitch (20-40um) for 2.5D/3D integration

### Physical Design Impact

- Bump map (arrangement of signal and power/ground bumps) is a critical input to floorplanning
- Power/ground bumps must be distributed across the die area for uniform IR drop
- Signal bumps near their corresponding logic reduces routing congestion
- RDL (redistribution layer) on the die may be needed to route from cell-level pads to bump locations
- Package substrate routing (number of layers, line/space) affects bump assignment flexibility

## Ball Grid Array (BGA)

### Technology

BGA packages have an array of solder balls on the bottom surface that connect to the PCB. The die-to-package connection can be wire bond or flip-chip.

### Variants

- **PBGA (Plastic BGA)**: Plastic substrate, low cost, general-purpose
- **FCBGA (Flip-Chip BGA)**: Flip-chip die attachment to BGA substrate. Standard for high-performance chips
- **CSP (Chip-Scale Package)**: Package size is within 1.2x of the die size. Minimal fan-out

### Characteristics

- **Ball pitch**: 0.4mm, 0.5mm, 0.65mm, 0.8mm, 1.0mm (application dependent)
- **Ball count**: 100 to 5000+ balls
- **Substrate layers**: 2-12 layers (more layers for high pin count and fine routing)

### Physical Design Impact

- BGA ball map defines the board-level footprint and affects PCB routing
- Power integrity depends on the number and distribution of power/ground balls
- Signal integrity analysis must include BGA ball parasitics and substrate trace routing

## Fan-Out Wafer-Level Packaging (FO-WLP)

### Technology

FO-WLP creates the package directly on the wafer (or reconstituted wafer), using redistribution layers (RDL) to fan out the die connections to a larger area.

### Process

1. Singulate dies from the wafer
2. Place known-good dies on a carrier wafer with spacing between them
3. Mold the dies in epoxy to create a reconstituted wafer
4. Deposit RDL layers on top to route from die pads to package balls
5. Attach solder balls and singulate into individual packages

### Characteristics

- **Size**: Very thin profile (0.3-0.5mm), close to chip-scale
- **Cost**: Competitive for small-to-medium die sizes; cost-effective for mobile and IoT
- **Performance**: Short, low-inductance RDL connections
- **Pin count**: Moderate (limited by RDL routing density)

### Variants

- **eWLB** (Infineon/TSMC): Embedded Wafer-Level Ball grid array
- **InFO** (TSMC): Integrated Fan-Out, used in Apple A-series chips

### Physical Design Impact

- RDL routing rules (line width, spacing, layer count) constrain I/O planning
- Thin package has limited thermal dissipation capability
- Tight integration with die design; bump map and RDL are co-designed

## 2.5D Packaging

### Technology

Multiple dies are placed side-by-side on a silicon interposer. The interposer provides fine-pitch wiring between dies, connecting through TSVs (Through-Silicon Vias) to the package substrate below.

### Key Components

- **Silicon interposer**: A passive silicon die with fine-pitch metal routing (1-5um line/space) and TSVs
- **TSVs (Through-Silicon Vias)**: Vertical connections through the interposer silicon, connecting top-side routing to bottom-side bumps
- **Micro-bumps**: Fine-pitch connections (40um) between dies and the interposer
- **C4 bumps**: Standard-pitch connections between the interposer and the package substrate

### Use Cases

- **HBM (High Bandwidth Memory)**: DRAM stacks connected to a logic die via a silicon interposer. Enables massive memory bandwidth (>1 TB/s)
- **Heterogeneous integration**: Combining dies from different process nodes (e.g., 5nm logic + 12nm I/O)
- **Large designs**: Designs too large for a single reticle can be split into chiplets on an interposer

### Physical Design Impact

- Die-to-die interfaces must be designed for the micro-bump pitch and interposer routing
- Interposer TSV placement affects die floorplan (TSV keep-out zones)
- Power delivery through the interposer adds resistance; careful PDN analysis required
- Thermal analysis must account for multiple heat sources on the interposer

## 3D Packaging

### Technology

In 3D packaging, dies are stacked vertically and connected through TSVs within the dies themselves (not just an interposer).

### Variants

- **Die-to-die stacking**: Two or more logic dies stacked with TSV connections
- **Die-on-wafer**: Known-good dies bonded to a wafer
- **Wafer-to-wafer**: Two processed wafers bonded face-to-face (hybrid bonding)

### Hybrid Bonding

The most advanced form of 3D integration. Two wafers are bonded with direct copper-to-copper connections at sub-micron pitch (< 1um). This enables:

- Extremely high connection density (millions of connections per mm2)
- Very low parasitic capacitance and resistance
- Backside power delivery (power comes from the bottom wafer, signals from the top)

### Physical Design Impact

- 3D floorplanning: must consider vertical connectivity and thermal stack-up
- TSV placement reduces available routing area on each die
- Thermal management is critical: heat from the bottom die must dissipate through the top die
- Design tools are evolving to support true 3D-aware placement and routing

## Thermal Considerations

### Thermal Metrics

- **Theta_JA (Junction-to-Ambient)**: Total thermal resistance from die to ambient air. Lower is better
- **Theta_JC (Junction-to-Case)**: Thermal resistance from die to package top. Relevant for heatsink design
- **Theta_JB (Junction-to-Board)**: Thermal resistance from die to PCB. Relevant for board-cooled designs

### Thermal Design Power (TDP)

TDP is the maximum sustained power the package can dissipate while keeping the junction temperature within limits.

```
T_junction = T_ambient + P_total * Theta_JA
```

If T_junction must be < 105C and T_ambient = 40C, then:
```
P_max = (105 - 40) / Theta_JA = 65 / Theta_JA watts
```

### Package Thermal Solutions

| Solution | Theta_JA | Cost | Application |
|----------|----------|------|-------------|
| Exposed pad (no heatsink) | 30-50 C/W | Low | Low-power mobile |
| Heatsink with fan | 5-15 C/W | Medium | Desktop/laptop |
| Liquid cooling | 1-3 C/W | High | Data center, HPC |
| Embedded heat spreader | 10-20 C/W | Medium | General purpose |

### Physical Design Impact

- Power density hotspots on the die create thermal hotspots that degrade reliability and performance
- Floorplanning should spread high-power blocks across the die, not cluster them
- Power gating reduces thermal load during idle periods
- Thermal analysis (ANSYS, thermal simulation) should be run during floorplan exploration

## RDL Routing

### Purpose

Redistribution Layers (RDL) are additional metal layers deposited on top of the die's passivation layer. They redistribute (reroute) the die pad connections to the bump locations.

### When RDL is Needed

- Die pad locations do not align with the desired bump map
- Bump pitch is different from pad pitch
- Peripheral pads need to be redistributed to area-array bumps

### RDL Design Rules

- Typically 1-3 RDL layers with 2-10um line width/spacing
- Via connections between RDL layers and to the die's top metal pads
- Must meet electromigration rules for power connections
- Signal integrity analysis for high-speed signals routed through RDL

### Physical Design Impact

- RDL design is typically co-owned by PD and package teams
- Die pad placement must consider RDL routability
- RDL adds parasitic resistance and capacitance that must be included in timing and IR drop analysis

Understanding packaging is essential for PD engineers because package constraints flow directly into die-level floorplanning, I/O placement, power grid design, and timing analysis. A package-aware physical design approach prevents late-stage integration problems and ensures the die and package work together as an optimized system.
