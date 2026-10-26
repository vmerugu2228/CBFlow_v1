# Chiplet Design

## Overview

Chiplet design is a paradigm shift in semiconductor architecture where a monolithic SoC is decomposed into multiple smaller dies (chiplets) that are assembled in a single package. Each chiplet can be manufactured on a different process node optimized for its function: compute logic on the most advanced node for density and performance, I/O on a mature node for cost and analog performance, and memory on a specialized process for density. This approach addresses the escalating cost and yield challenges of monolithic designs at advanced nodes.

## Why Chiplets?

### Economic Motivation

The cost of manufacturing at advanced nodes (5nm, 3nm) has increased dramatically:

- **Mask set cost**: $10-15M at 5nm (vs. $1-2M at 28nm)
- **Wafer cost**: $15,000-20,000 per wafer at 5nm (vs. $2,000-3,000 at 28nm)
- **Yield**: Large monolithic dies at advanced nodes have low yield (die area is the enemy of yield)

Chiplets reduce cost by:
- Fabricating only the compute-critical chiplets on expensive advanced nodes
- Using mature, cheap nodes for I/O, analog, and other functions
- Improving effective yield (smaller dies yield better)
- Enabling IP reuse across multiple products (one I/O chiplet serves many products)

### Technical Motivation

- **Beyond reticle limit**: The largest die that can be printed in a single exposure is limited by the reticle size (~800mm2). Chiplets enable designs larger than a single reticle
- **Heterogeneous integration**: Combine digital, analog, RF, optical, and memory technologies that cannot coexist on the same process
- **Design modularity**: Different teams can design chiplets independently, reducing integration risk and enabling parallel development

### Industry Adoption

- **AMD EPYC**: CPU chiplets + I/O die on a single package
- **Intel Ponte Vecchio**: 47 chiplets across 5 process nodes
- **Apple M1 Ultra**: Two M1 Max dies connected via UltraFusion
- **AMD MI300**: CPU and GPU chiplets with HBM stacks on a common interposer

## Die-to-Die Interfaces

### Requirements

Die-to-die (D2D) interfaces must provide:
- **High bandwidth**: Tens of TB/s for compute-to-memory interfaces
- **Low latency**: Sub-nanosecond for tightly coupled compute chiplets
- **Low power**: < 0.5 pJ/bit for energy efficiency
- **High density**: Thousands of connections per mm of edge length

### Interface Types

**Parallel interfaces**: Wide buses (hundreds to thousands of signals) at moderate frequency. Low per-pin bandwidth but high aggregate bandwidth through parallelism.

**SerDes-based interfaces**: Serialized high-speed lanes (e.g., 16-32 Gbps per lane). Fewer pins but requires SerDes circuits. Used for longer-distance or lower-pin-count connections.

**Organic substrate interfaces**: Signals routed through the package substrate. Pitch limited to 100-200um (C4 bumps). Bandwidth limited by pin count and substrate routing.

**Silicon interposer interfaces**: Signals routed through a silicon interposer with fine-pitch routing (1-5um). Pitch limited to 40-55um (micro-bumps). Much higher bandwidth density than organic substrates.

**Direct die-to-die bonding**: Hybrid bonding with sub-micron pitch (< 1um). Highest bandwidth density, lowest latency, lowest power per bit.

## UCIe Standard

### Universal Chiplet Interconnect Express

UCIe is an open industry standard for chiplet-to-chiplet interconnect, announced in 2022 by Intel, AMD, ARM, Qualcomm, Samsung, TSMC, and others.

### UCIe Architecture

**Protocol layer**: Supports PCIe and CXL protocols for standardized data transfer. Enables chiplets from different vendors to interoperate.

**Die-to-die adapter layer**: Maps protocol-layer packets to the physical interface. Handles link training, flow control, and error correction.

**Physical layer**: Defines the electrical signaling, bump pitch, and signal assignment:
- **Standard package**: 100um bump pitch, for organic substrate assembly. ~28 Gbps/lane
- **Advanced package**: 25um or 55um bump pitch, for silicon interposer or bridge assembly. ~32 Gbps/lane or higher

### UCIe Key Parameters

| Parameter | Standard Package | Advanced Package |
|-----------|-----------------|------------------|
| Bump pitch | 100um | 25um / 55um |
| Bandwidth density | ~20 GB/s/mm | ~200 GB/s/mm |
| Energy efficiency | ~0.5 pJ/bit | ~0.25 pJ/bit |
| Latency | ~2ns | ~2ns |
| Reach | 10-25mm | 2-10mm |
| Packaging | Organic substrate | Silicon interposer / bridge |

### Physical Design Relevance

PD engineers working on chiplets must:
- Place D2D interface PHY macros at the die edge
- Route bump connections from PHY to the die edge bump array
- Ensure power delivery to the high-current D2D PHY (significant IR drop concern)
- Meet D2D timing constraints (PHY-to-bump delay matching)
- Handle ESD protection at the D2D interface (lower than standard I/O ESD requirements)

## Interposer Design

### Silicon Interposer

A passive silicon die that provides fine-pitch routing between chiplets and TSVs for connection to the package substrate below.

**Design flow**:
1. Define chiplet placement on the interposer (chiplet-level floorplan)
2. Route D2D signals between chiplets through interposer metal layers
3. Place and route TSVs for power and signal connections to the substrate
4. Design the interposer power grid (must deliver power to chiplets through TSVs)
5. Perform signal integrity analysis on D2D routes
6. Verify DRC/LVS on the interposer
7. Generate interposer GDSII for fabrication

**Design rules**: Interposer routing rules are different from standard BEOL. Typically 1-4 metal layers with 1-5um pitch. TSVs are 5-10um diameter with 40-50um pitch.

### EMIB (Embedded Multi-Die Interconnect Bridge)

Intel's alternative to a full-wafer interposer. A small silicon bridge is embedded in the organic package substrate, providing fine-pitch routing only where chiplets are adjacent.

- **Advantage**: Lower cost than full interposer (bridge is much smaller)
- **Limitation**: Only provides fine-pitch connectivity in the bridge region, not across the entire package

### Organic Interposer

An organic substrate (similar to a PCB) used as the interposer. Lower cost than silicon but coarser routing (10-20um line/space) and fewer layers.

- **Usage**: Suitable for D2D interfaces with wider bump pitch (100um+)
- **Limitation**: Cannot support micro-bump connections

## Packaging Considerations

### Chiplet Assembly

Assembling multiple chiplets in a single package is more complex than single-die packaging:

- **Known Good Die (KGD)**: Each chiplet must be tested before assembly (cannot rework a defective chiplet after bonding)
- **Placement accuracy**: Chiplets must be aligned to bump arrays on the interposer with sub-micron precision
- **Thermal management**: Multiple heat sources in close proximity require careful thermal design
- **Warpage control**: Differential thermal expansion between chiplets, interposer, and substrate can cause warpage and bump failures

### Thermal Challenges

- Each chiplet generates heat; total power can be 200-500W for high-performance products
- Chiplets on the interior of the package have limited thermal dissipation paths
- Thermal coupling between adjacent chiplets raises local temperature
- Thermal simulation must model the full 3D stack (chiplet + interposer + substrate + package lid + heatsink)

### Power Delivery

Delivering power to chiplets through an interposer is more challenging than direct bump connection to a substrate:

- Power flows: Substrate bumps -> Interposer TSVs -> Interposer routing -> Chiplet micro-bumps -> Chiplet PDN
- Each interface adds resistance: TSV resistance, interposer metal resistance, micro-bump resistance
- Total PDN resistance can be 2-3x higher than a monolithic flip-chip design
- Requires careful PDN analysis and more decoupling capacitance

## Heterogeneous Integration

### Concept

Heterogeneous integration combines chiplets manufactured in different technologies:

- **Compute chiplet**: 3nm or 2nm for highest logic density and performance
- **I/O chiplet**: 12nm or 16nm for analog I/O circuits (SerDes, ADC, PLL) at lower cost
- **Memory chiplet**: HBM DRAM stacks for massive bandwidth
- **Photonic chiplet**: Silicon photonics for optical I/O
- **RF chiplet**: Specialized RF process for wireless interfaces

### Benefits

- Each function uses its optimal technology
- Expensive advanced nodes are used only where they provide the most benefit
- IP can be developed once and reused across multiple products
- Faster time-to-market (parallel development of independent chiplets)

### Challenges

- D2D interface design for different voltage domains and process technologies
- Unified verification across heterogeneous chiplets
- Thermal management of chiplets with very different power densities
- System-level STA spanning multiple chiplets (timing closure at the D2D boundary)
- Supply chain complexity (chiplets from different fabs)

## Chiplet Design Flow

### Architectural Phase

1. **Partition decision**: Which functions become separate chiplets vs. staying monolithic
2. **D2D interface definition**: Protocol, bandwidth, latency, pin count
3. **Process node selection**: Per chiplet, based on function and cost optimization
4. **Package selection**: Interposer type (silicon, bridge, organic), package form factor

### Implementation Phase (Per Chiplet)

5. **Standard PD flow**: Each chiplet follows the normal synthesis -> PnR -> signoff flow
6. **D2D PHY integration**: Place and route the D2D interface PHY at the die edge
7. **Bump assignment**: Map signals and power to the bump array
8. **Intra-chiplet signoff**: Full timing, power, DRC/LVS signoff per chiplet

### System-Level Phase

9. **Interposer design**: Route D2D signals on the interposer
10. **System-level timing**: Verify timing across chiplet boundaries (D2D latency, skew)
11. **System-level power**: Analyze IR drop through the full PDN stack (chiplet + interposer + substrate)
12. **System-level thermal**: Verify thermal design meets junction temperature limits
13. **Assembly verification**: Verify physical compatibility (bump alignment, keep-out zones)

## Physical Design Impact

### For PD Engineers

Chiplet design changes the PD engineer's scope:

- **Die-edge planning**: D2D interface placement at the die edge becomes a critical floorplan decision
- **Bump map co-design**: Bump assignment is constrained by the interposer routing and chiplet placement
- **PDN analysis**: Must model the full power delivery chain, not just the on-die power grid
- **Timing budgeting**: D2D interface latency consumes timing budget; on-chiplet timing must be tighter to compensate
- **Thermal awareness**: Floorplanning must consider the chiplet's position in the package and its neighbors' heat output
- **Test access**: DFT must include D2D boundary test structures for known-good-die testing

### Tool Requirements

Current EDA tools are evolving to support chiplet design:

- **3D-IC tools**: Cadence Integrity 3D-IC, Synopsys 3DIC Compiler for multi-die integration
- **System-level analysis**: Cross-chiplet timing, power, and thermal analysis
- **Interposer routing**: Specialized routers for interposer metal and TSV assignment
- **Package-die co-design**: Unified tools that handle die, interposer, and package simultaneously

Chiplet design represents the future of high-performance and high-complexity semiconductor products. PD engineers who understand chiplet partitioning, D2D interfaces, interposer design, and system-level integration will be essential to the next generation of chip development.
