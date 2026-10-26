# GF 22FDX: FD-SOI Technology for Physical Design

## Overview

GlobalFoundries 22FDX is a 22nm Fully Depleted Silicon-On-Insulator (FD-SOI) technology platform that offers a compelling alternative to FinFET-based processes for a wide range of applications including IoT, automotive, RF, and low-power SoCs. FD-SOI's distinguishing characteristic is the ultra-thin silicon body on a buried oxide (BOX) layer, which provides excellent electrostatic control without the complex 3D fin structures of FinFET.

22FDX is particularly attractive for designs that prioritize low power, analog/RF performance, or cost sensitivity relative to FinFET nodes.

## FD-SOI Technology Fundamentals

### Device Structure

The FD-SOI transistor is built on a thin silicon film (~6-7nm) sitting atop a buried oxide layer (~25nm BOX). Key structural elements:

- **Ultra-thin body (UTB)**: The channel is fully depleted, meaning no mobile carriers exist in the body at zero gate bias. This eliminates random dopant fluctuation, a major source of variability in bulk CMOS
- **Buried oxide (BOX)**: The insulating BOX layer isolates the channel from the substrate, reducing parasitic capacitance and eliminating latch-up
- **Undoped channel**: Since the thin body is fully depleted, the channel does not need doping for Vt control. This dramatically improves variability (sigma-Vt is ~50% lower than bulk)
- **Back gate**: The substrate beneath the BOX acts as a second gate (back gate) that can electrically tune the threshold voltage

### Advantages Over Bulk CMOS

- Lower variability (no RDF -- random dopant fluctuation)
- Reduced parasitic capacitance (BOX isolation)
- No latch-up (SOI isolation)
- Simpler well structure (no deep N-well needed for isolation)
- Body biasing capability (see below)

### Comparison with FinFET

- FD-SOI offers competitive performance at 22nm vs. 16nm/14nm FinFET for many applications
- FinFET provides higher drive current density for compute-intensive designs
- FD-SOI excels in analog/RF, low-voltage operation, and ultra-low-power
- FD-SOI has lower mask count and process complexity than FinFET, reducing cost

## Back-Gate Biasing (Body Biasing)

The most unique and powerful feature of 22FDX for physical design is back-gate (body) biasing. By applying voltage to the substrate beneath the BOX, the threshold voltage can be electrically tuned post-fabrication.

### Forward Body Biasing (FBB)

- Applying positive voltage to the back gate of an NMOS (negative for PMOS) lowers Vt
- Lower Vt increases speed but also increases leakage
- FBB can boost performance by 20-30% at the cost of higher leakage
- Useful for performance-critical modes or turbo modes

### Reverse Body Biasing (RBB)

- Applying negative voltage to the back gate of NMOS (positive for PMOS) raises Vt
- Higher Vt reduces leakage dramatically (10x or more reduction possible)
- RBB enables ultra-low-power sleep/standby modes
- Useful for battery-powered and always-on applications

### Biasing Ranges

- Typical FBB range: 0V to +2.0V (NMOS back gate)
- Typical RBB range: 0V to -1.5V (NMOS back gate)
- The wide biasing range provides enormous flexibility in trading speed for power
- Biasing can be applied per-domain, enabling different power/performance profiles for different blocks

### PD Implications of Body Biasing

- **Well-tap placement**: Body bias voltage is delivered through well taps connected to the back gate. Well-tap density must be sufficient to ensure uniform bias across the block
- **Bias domains**: Different blocks can have different body bias voltages, requiring domain isolation similar to voltage domain planning
- **Timing libraries**: Libraries are characterized at multiple body bias voltages. Multi-mode analysis must include different bias corners
- **IR drop**: Body bias supply networks must be analyzed for IR drop, similar to VDD/VSS
- **Floorplanning**: Bias domain boundaries must be planned during floorplanning

## Metal Stack

22FDX offers several metal stack options depending on application needs:

### Standard Metal Stack (10M or 11M)

- **M1**: Thin, tight-pitch local interconnect layer
- **M2-M4**: Thin metals for signal routing (pitch ~64-90nm)
- **M5-M8**: Intermediate metals with progressively increasing pitch
- **M9-M10**: Semi-global metals for power and clock distribution
- **M11 (AP)**: Thick aluminum cap layer for power distribution and bond pads

### Key Metal Characteristics

- Lower metals (M1-M4): High density, high resistance, used for local signals
- Middle metals (M5-M8): Balanced density/resistance for signal and clock routing
- Upper metals (M9+): Low resistance, used for power grid and long-distance signals
- RDL (redistribution layer): Available for flip-chip bump connectivity

### Routing Recommendations

- Use M1 sparingly for inter-cell routing (primarily used within standard cells)
- M2-M4 handle the bulk of signal routing
- Reserve M9+ for power grid stripes and wide clock trunks
- Via stacking rules and enclosure rules follow standard practices but with FD-SOI-specific dimensions

## Design Rules

22FDX design rules are simpler than FinFET nodes in several important respects:

- **No multi-patterning**: 22nm FD-SOI uses single-patterning lithography for all layers, eliminating coloring constraints
- **No fin quantization**: Drive strength is continuous (controlled by gate width), unlike FinFET where current is quantized by fin count
- **Standard well rules**: SOI isolation simplifies well and implant rules compared to deep bulk processes

Key design rule parameters:
- Gate length: 20nm (nominal)
- Contacted poly pitch (CPP): ~90nm
- M1 pitch: ~64nm
- SRAM bit-cell size: ~0.060 um^2 (competitive with 14nm FinFET)

## Standard Cell Libraries

22FDX cell libraries are available in multiple track heights:
- **9T (9-track)**: Standard performance/density tradeoff
- **7.5T**: Higher density option with reduced routing tracks
- **12T**: High-performance option with more routing resources

Each track height is available in multiple Vt flavors:
- **RVT (Regular Vt)**: Baseline performance and leakage
- **LVT (Low Vt)**: Higher performance, higher leakage
- **SLVT (Super-Low Vt)**: Maximum performance (use sparingly)

Combined with body biasing, the effective Vt range spans from ultra-low-leakage (HVT + RBB) to maximum performance (SLVT + FBB), all from a single set of physical cells.

## Advantages for Specific Applications

### IoT and Wearables

- Body biasing enables near-threshold voltage operation (0.4-0.5V) for extreme energy efficiency
- RBB in standby mode reduces leakage to sub-nA levels per gate
- Low-cost single-patterning process suitable for cost-sensitive consumer products

### Automotive

- FD-SOI inherently tolerant to soft errors (reduced collection volume due to BOX)
- Wide temperature range operation (-40C to 175C)
- Excellent analog performance on the same die (low 1/f noise, good matching)

### RF and Connectivity

- FD-SOI provides excellent RF FoM (fT > 300 GHz)
- Back-gate biasing can tune RF circuit performance dynamically
- Suitable for 5G mmWave, WiFi 6/7, and Bluetooth designs
- Low parasitic capacitance from BOX improves high-frequency behavior

### Low-Power Compute

- Competitive single-thread performance with 16/14nm FinFET at lower cost
- Adaptive body biasing compensates for process variation and aging
- Wide voltage scaling range (0.4V to 0.9V) enables aggressive DVFS

## PD Flow Considerations

1. **Body bias-aware timing analysis**: Characterize and analyze at multiple body bias voltages. Include bias corners in MCMM analysis
2. **Well-tap planning**: Ensure adequate well-tap density for bias distribution. Consider IR drop on bias networks
3. **No coloring**: Single-patterning simplifies routing and reduces DRC complexity compared to FinFET nodes
4. **Analog integration**: FD-SOI's excellent analog properties make mixed-signal integration straightforward. Plan analog/digital boundaries carefully
5. **ESD and IO**: FD-SOI IO cells differ from bulk. Ensure correct IO library selection and pad ring planning
6. **Memory**: SRAM compilers are available with body-bias-aware power modes. Use RBB for retention and FBB for fast read/write

22FDX represents a pragmatic technology choice for designs where FinFET's raw performance is not required but low power, analog quality, and cost efficiency are paramount. The body biasing capability is a unique tool that PD engineers should leverage fully.
