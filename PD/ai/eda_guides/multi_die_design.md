# Multi-Die Design: 2.5D/3D, Interposer, TSV, Micro-Bumps, and Thermal Challenges

## Overview

Multi-die design has emerged as a critical strategy for overcoming the scaling limitations of monolithic SoCs. By partitioning a design across multiple die (chiplets) and connecting them through advanced packaging technologies, designers can achieve higher transistor counts, mix process technologies, improve yield, and reduce cost. This guide covers 2.5D and 3D integration, interposer design, through-silicon vias (TSVs), micro-bump technology, die-to-die interfaces, and the thermal challenges unique to multi-die systems.

## Multi-Die Architectures

### 2.5D Integration

In 2.5D integration, multiple die are placed side-by-side on a silicon interposer:

```
    [Die A]    [Die B]    [HBM Stack]
    |   |      |   |       |   |
    ========= Interposer ===========
    |||||||||||||||||||||||||||||||||
    ============ Package ============
    |||||||||||||||||||||||||||||||||
              PCB
```

**Characteristics:**
- Die placed side-by-side on silicon or organic interposer
- High-density interconnect through interposer wiring (2-4 um pitch)
- TSVs connect interposer wiring to package substrate
- Proven technology (AMD Fiji, NVIDIA A100/H100 with HBM)

### 3D Integration

In 3D integration, die are stacked vertically:

```
    ============
    [  Die B   ]  <- Top die
    ============
    | TSV | TSV |
    ============
    [  Die A   ]  <- Bottom die
    ============
    ||||||||||||
    == Package ==
```

**Characteristics:**
- Die stacked vertically with TSV connections through silicon
- Very short interconnect (10-50 um TSV height)
- Highest bandwidth density (TSVs on ~10 um pitch possible)
- Thermal challenge: bottom die has limited heat dissipation path

### Chiplet-Based Design

Chiplet architecture decomposes an SoC into reusable die:

**Partitioning strategies:**
- **Functional partitioning**: CPU die + I/O die + memory die (AMD Zen architecture)
- **Technology partitioning**: compute chiplets on advanced node, I/O die on mature node
- **Yield partitioning**: smaller die have higher yield than one large monolithic die
- **Reuse**: same chiplet used across multiple products with different configurations

## Interposer Design

### Silicon Interposer

Silicon interposers provide the highest interconnect density:

- **Wiring**: 4-6 metal layers on silicon with 2-4 um pitch (vs. 10-20 um on organic)
- **TSVs**: 5-10 um diameter, 50-100 um pitch, connecting top metal to bottom bumps
- **Die size**: interposer can be very large (AMD MI300: ~5,000 mm2)
- **Passive**: no active devices (though active interposers with embedded logic exist)

**Design rules:**
- Metal pitch: 2-4 um (similar to mature CMOS back-end)
- Via pitch: 2-3 um
- TSV keep-out zone: 5-20 um around each TSV (stress exclusion zone)
- Minimum die-to-die spacing: 100-200 um (for underfill and assembly tolerance)

### Organic Interposer

Organic interposers use standard PCB-like substrate technology:

- **Wiring**: 5-10 um line/space on high-density organic substrate
- **Lower cost**: standard substrate manufacturing
- **Larger area**: can be fabricated larger than silicon interposer (no reticle limit)
- **Lower density**: fewer interconnects between chiplets
- **Example**: Intel EMIB (Embedded Multi-die Interconnect Bridge) -- localized silicon bridge in organic substrate

### Bridge-Based Integration

Intel EMIB and TSMC InFO/CoWoS variants:

- **EMIB**: small silicon bridge die embedded in organic substrate; provides high-density interconnect only where needed
- **CoWoS (Chip-on-Wafer-on-Substrate)**: TSMC's silicon interposer technology
- **InFO (Integrated Fan-Out)**: TSMC's fan-out wafer-level packaging; reconstructed wafer with redistribution layers

## Through-Silicon Via (TSV)

### TSV Fabrication

**Via-first**: TSV formed before FEOL (front-end-of-line) transistor fabrication
- Smallest TSVs (1-5 um diameter)
- Integrated into standard process flow
- Limited to interposer or MEMS applications

**Via-middle**: TSV formed after FEOL but before BEOL metallization
- 5-10 um diameter, 50-100 um depth
- Most common for 3D IC (used in HBM stacks)
- Compatible with standard CMOS process

**Via-last (from front side)**: TSV formed after BEOL
- 10-50 um diameter
- No impact on FEOL/BEOL process
- Larger pitch limits interconnect density

**Via-last (from back side)**: TSV etched from wafer backside after thinning
- Largest TSVs (20-100 um)
- Used for interposer manufacturing
- Backside reveal after wafer thinning to 50-100 um

### TSV Electrical Properties

- **Resistance**: 10-100 milliohms depending on dimensions and fill material (copper, tungsten)
- **Capacitance**: 10-100 fF (dominated by TSV-to-substrate coupling)
- **Inductance**: 10-50 pH
- **Bandwidth**: multi-GHz signaling through TSV is feasible

### TSV Stress Effects

TSVs create mechanical stress in surrounding silicon due to CTE mismatch between copper fill and silicon:

- **Keep-out zone (KOZ)**: region around TSV where transistor performance is affected
- **Typical KOZ**: 5-20 um radius depending on TSV size and technology node
- **Impact**: threshold voltage shift, mobility change, reliability degradation
- **Mitigation**: avoid placing sensitive analog circuits or critical-path logic in KOZ

## Micro-Bump Technology

### Bump Types

| Technology | Pitch | Diameter | Application |
|---|---|---|---|
| C4 (flip-chip) | 130-200 um | 80-100 um | Die to package |
| Micro-bump | 40-55 um | 20-30 um | Die to interposer |
| Hybrid bonding | 1-10 um | 1-5 um | Direct die-to-die stacking |
| Pillar bump | 100-150 um | 50-80 um | Standard flip-chip |

### Micro-Bump Design

For die-to-interposer connections:

- **Solder composition**: SnAg (tin-silver) or Cu pillar with solder cap
- **Under-bump metallization (UBM)**: Ti/Cu or TiW/Cu stack under the solder
- **Underfill**: epoxy material fills gap between die and interposer for mechanical strength
- **Reliability**: electromigration, thermal cycling, and solder joint fatigue are primary concerns

### Hybrid Bonding

Direct Cu-Cu bonding without solder:

- **Pitch**: sub-10 um (down to 1 um demonstrated)
- **Density**: 1M+ connections per mm2
- **Process**: oxide-oxide bonding followed by Cu-Cu thermal annealing
- **Application**: HBM4 (planned), TSMC SoIC, AMD 3D V-Cache
- **Advantage**: highest interconnect density, lowest parasitic capacitance

## Die-to-Die (D2D) Interfaces

### Interface Standards

**UCIe (Universal Chiplet Interconnect Express):**
- Open standard for chiplet interconnect
- Standard package (bump pitch ~100-130 um): ~28 Gbps/lane, ~200 GB/s per mm of edge
- Advanced package (micro-bump or hybrid bond): ~32 Gbps/lane, ~1350 GB/s per mm
- Protocol layers: flit mode (raw data), CXL-based (cache coherent), streaming
- Supports retimers for signal integrity

**BoW (Bunch of Wires):**
- OCP (Open Compute Project) standard for parallel D2D interface
- Simple, low-latency, parallel signaling
- 1-16 Gbps per wire, wide data paths

**Custom PHY:**
- Many implementations use custom D2D PHY optimized for specific interposer/package technology
- Trade-off: performance optimization vs. ecosystem compatibility

### D2D Interface Design Considerations

- **Bandwidth**: aggregate bandwidth from hundreds to thousands of signal lines
- **Latency**: <5 ns for short interposer connections; critical for coherency protocols
- **Power**: ~0.5-2 pJ/bit for short-reach D2D vs. ~5-20 pJ/bit for long-reach SerDes
- **Redundancy**: spare lanes and repair capability for yield improvement
- **ECC/CRC**: error detection and correction on D2D links for reliability

## Thermal Challenges

### Heat Dissipation in 3D Stacks

Stacked die create thermal challenges:

- **Bottom die**: heat must pass through top die(s) or through limited lateral paths
- **Thermal resistance**: each die and bonding layer adds thermal resistance
- **Hot spots**: concentrated heat sources (e.g., CPU core under memory stack) can exceed thermal limits

### Thermal Modeling

```
Junction temperature = T_ambient + P_total * R_thermal_total

R_thermal_total = R_junction_to_case + R_case_to_ambient

For 3D stack:
R_thermal(bottom) = R_through_die + R_bonding + R_through_top_die + R_TIM + R_heatsink
```

**Key parameters:**
- Silicon thermal conductivity: ~150 W/m*K
- Copper TSV thermal conductivity: ~400 W/m*K (TSVs can serve as thermal vias)
- Bonding layer thermal resistance: depends on material and thickness
- Underfill thermal conductivity: ~0.5-2 W/m*K (relatively poor)

### Thermal Mitigation

**Physical design:**
- **Thermal TSVs**: dedicated TSVs for heat conduction (not electrical signals)
- **Power map optimization**: distribute high-power blocks to avoid concentrated hot spots
- **Thermal-aware floorplanning**: place hot blocks on different chiplets or away from stack center

**System-level:**
- **DVFS**: reduce voltage/frequency when thermal limit is approached
- **Thermal throttling**: firmware monitors die temperature sensors and throttles workload
- **Advanced cooling**: vapor chamber, liquid cooling, or thermoelectric coolers for high-power stacks

**Package-level:**
- **Thick heat spreader**: copper lid with high thermal conductivity
- **TIM (Thermal Interface Material)**: high-conductivity compound between die and heat spreader
- **Backside cooling**: for 3D stacks, cooling from both top and bottom if possible

## Design Flow for Multi-Die

### Chiplet Design Flow

1. **System architecture**: define chiplet partitioning, interface protocols, power/thermal budget
2. **Interface specification**: define D2D PHY, protocol, and pin assignment
3. **Individual chiplet design**: full RTL-to-GDSII flow for each chiplet
4. **Interposer design**: routing between chiplets, TSV placement, power delivery network
5. **Package design**: bump assignment, substrate routing, BGA/LGA pin-out
6. **Thermal analysis**: FEA simulation of thermal performance under various workloads
7. **System-level verification**: co-simulation of multiple chiplets with interface models
8. **Assembly and test**: known-good-die (KGD) testing before assembly

### Known-Good-Die (KGD)

Testing individual die before assembly is critical for multi-die yield:

- **Wafer-level testing**: probe test with temporary connections
- **Burn-in**: stress testing at elevated voltage/temperature
- **Die-level BIST**: built-in self-test for memories, logic, D2D interface
- **Repair**: spare rows/columns in memory; spare lanes in D2D interface
- **KGD yield**: each die must pass before assembly; assembly yield = product of individual KGD yields

Multi-die design represents the future of high-performance computing, enabling continued scaling of transistor count and system capability beyond what monolithic die can achieve. Success requires co-optimization across chip design, packaging, thermal management, and testing.
