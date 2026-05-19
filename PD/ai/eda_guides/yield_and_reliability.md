# Yield and Reliability

## Overview

Yield is the percentage of manufactured dies that function correctly. Reliability is the probability that a working die continues to function correctly over its intended lifetime. Both are critical economic and engineering concerns: yield determines manufacturing cost per good die, and reliability determines warranty costs, customer satisfaction, and product reputation. PD engineers influence both through their physical design decisions. This guide covers the fundamentals of yield analysis, yield enhancement techniques, and reliability mechanisms relevant to physical design.

## Yield Fundamentals

### Defect Density

Manufacturing defects (particles, lithographic errors, via voids, etc.) occur randomly across the wafer. The defect density (D0) is the average number of defects per unit area, typically expressed in defects/cm2.

- **Leading-edge nodes**: D0 = 0.1-0.5 defects/cm2 (mature process)
- **Early production**: D0 = 1-5 defects/cm2 (process not yet optimized)
- **Mature nodes**: D0 = 0.01-0.1 defects/cm2

### Yield Models

**Poisson model** (simplest):
```
Y = exp(-D0 * A)
```
Where A is the die area. This model assumes defects are uniformly distributed.

**Murphy model** (more realistic):
```
Y = ((1 - exp(-D0 * A)) / (D0 * A))^2
```
Accounts for non-uniform defect distribution across the wafer (defects tend to cluster).

**Negative binomial model** (most commonly used):
```
Y = (1 + D0 * A / alpha)^(-alpha)
```
Where alpha is the clustering parameter. This model fits empirical data well.

### Yield vs. Die Area

Yield decreases with die area. A die twice as large has more than twice the chance of containing a defect. This relationship makes die area reduction a direct yield improvement technique.

Example (using Poisson model, D0 = 0.2/cm2):
| Die Area (mm2) | Yield |
|----------------|-------|
| 50 | 90.5% |
| 100 | 81.9% |
| 200 | 67.0% |
| 400 | 44.9% |
| 800 | 20.2% |

This illustrates why very large dies (server processors, GPUs) have significantly lower yield and higher cost.

## Critical Area Analysis

### Concept

Not all defects cause failures. A defect only matters if it lands in a "critical area" where it can cause a short circuit (between adjacent wires) or an open circuit (breaking a wire or via).

**Critical area** is the area within which a defect of a given size would cause a failure.

### Types of Critical Area

- **Short critical area**: The area between adjacent conductors where a conductive particle would bridge them
- **Open critical area**: The area along a conductor where a void or break would disconnect it
- **Via critical area**: The area around vias where a defect would prevent electrical connection

### Analysis Tools

Tools like Calibre YieldAnalyzer, ICV, or dedicated yield analysis tools compute critical area by:

1. Identifying all pairs of conductors that could be shorted
2. Computing the area where a defect of each size would cause a short or open
3. Integrating over the defect size distribution to get the failure probability

### Reducing Critical Area

- **Wider spacing**: Increasing wire spacing reduces short critical area (defect must be larger to bridge the gap)
- **Wider wires**: Increasing wire width reduces open critical area (harder to break a wider wire)
- **Redundant vias**: Adding extra vias at every via location reduces via open failures
- **Metal fill**: Uniform metal density reduces lithographic variation that can cause opens or shorts

**Physical implication**: PD engineers can directly influence critical area through routing strategies, via insertion, and fill patterns.

## Yield Enhancement Techniques

### Redundant Vias

Single vias are a yield vulnerability. If a single via fails (void, misalignment), the connection is lost. Adding a second (or third) via at the same location provides a redundant path.

- **Double via insertion**: After routing, the tool attempts to insert a second via at every via location where space permits
- **Achievable coverage**: 80-95% of vias can be doubled in a typical design
- **Impact**: 5-15% yield improvement, depending on the process's via failure rate
- **Tradeoff**: Redundant vias consume routing space; may slightly increase congestion

### Metal Fill (Dummy Fill)

Metal fill inserts non-functional metal shapes to equalize metal density across the die. This improves:

- **CMP uniformity**: Chemical Mechanical Polishing removes metal unevenly if density varies. Fill prevents dishing (low-density regions) and erosion (high-density regions), maintaining flat topography
- **Lithographic uniformity**: Uniform density improves lithographic focus and exposure consistency

Fill rules specify:
- Minimum and maximum density per layer within a defined window
- Minimum spacing between fill shapes and functional wires
- Fill shape size constraints (minimum width, maximum width)

**Physical implication**: Fill is inserted after routing and before final verification. PD engineers must verify that fill does not violate DRC rules or cause unacceptable coupling capacitance to critical nets.

### Recommended Rules (DFM Rules)

Beyond minimum DRC rules, foundries provide recommended rules that improve yield:

- **Wider wire widths** (beyond minimum) for critical signal paths
- **Larger via enclosures** (beyond minimum) for better via yield
- **Preferred routing directions** (minimize jogs and bends)
- **Minimum wire end extension** (avoid line-end shortening during lithography)
- **Via pillar stacking** (align vias vertically across layers for better via yield)

These rules do not prevent tapeout if violated but improve yield when followed.

### Redundancy

For memories (SRAMs), built-in redundancy allows spare rows and columns to replace defective ones. This is essential for large memory arrays where the probability of a defect is high.

- **Repair analysis**: Test the memory, identify defective rows/columns, and program fuses to activate spares
- **Overhead**: Spare rows/columns add 5-10% area
- **Yield improvement**: Dramatic for large memories (without redundancy, yield of a 4MB SRAM would be very low)

## Reliability Mechanisms

### Electromigration (EM)

Electromigration is the physical movement of metal atoms under high current density. Over time, it creates voids (increasing resistance) or hillocks (causing shorts).

**Key parameters**:
- **Current density limit (J_max)**: Maximum sustainable current per unit cross-section (mA/um2)
- **Black's equation**: MTF (Mean Time to Failure) = A * J^(-n) * exp(Ea / kT), where n ~ 2 and Ea is the activation energy
- **Temperature dependence**: EM is exponentially worse at higher temperatures

**Physical implication**:
- Power grid wires must be wide enough to carry the expected current below J_max
- Signal wires with high average current (clocks, frequently toggling buses) must be checked
- Vias are often the weakest link (smallest cross-section)
- EM analysis tools (RedHawk, Voltus) check all wires and vias against EM limits

### Hot Carrier Injection (HCI)

High-energy carriers (electrons or holes) can become trapped in the gate oxide, gradually shifting the transistor's threshold voltage and degrading performance over time.

- **Affected transistors**: NMOS under high VDS and high switching activity
- **Impact**: Gradual performance degradation (slower circuits) over the product lifetime
- **Mitigation**: Limit voltage stress on critical transistors; derate timing for end-of-life

### Bias Temperature Instability (BTI)

**NBTI (Negative Bias Temperature Instability)**: Affects PMOS transistors under negative gate bias. Causes threshold voltage increase over time, slowing the transistor.

**PBTI (Positive Bias Temperature Instability)**: Affects NMOS transistors in high-k metal gate processes. Similar mechanism to NBTI.

- **Impact**: 5-10% performance degradation over 10-year lifetime at typical operating conditions
- **Physical implication**: Timing signoff must include aging derating (apply timing margin for end-of-life degradation). Libraries may provide fresh and aged timing models

### Time-Dependent Dielectric Breakdown (TDDB)

Under voltage stress, the gate oxide gradually degrades until it breaks down, creating a conductive path that destroys the transistor.

- **Dependence**: Exponentially dependent on voltage and temperature
- **Mitigation**: Stay within the foundry's specified operating voltage range
- **Physical implication**: Overvoltage conditions (during ESD events or power supply transients) must be managed by ESD protection structures

### Stress Migration

Mechanical stress from the metal interconnect stack can cause void formation in metal lines and vias, even without current flow. This is driven by thermal cycling and residual stress from manufacturing.

- **Impact**: Open circuit failures, especially in wide metal lines and at via connections
- **Mitigation**: Follow foundry recommended metal width and via count rules; avoid very long unconnected metal stubs

## Reliability Testing

### Accelerated Life Testing

Products are subjected to accelerated stress conditions (high temperature, high voltage, high current) to predict lifetime under normal operating conditions.

**Common tests**:
- **HTOL (High Temperature Operating Life)**: Run the chip at 125-150C with elevated voltage for 1000+ hours
- **Temperature cycling**: Cycle between -40C and +125C (or wider range) to stress solder joints and die attach
- **Moisture resistance**: High humidity exposure to test package sealing
- **ESD testing**: Apply electrostatic discharge pulses to verify ESD protection

### Burn-In

Short-duration high-temperature operation to screen out "infant mortality" failures (early failures caused by manufacturing marginalities).

- **Duration**: Typically 24-168 hours at 125C with elevated voltage
- **Purpose**: Remove weak parts from the population before shipping
- **Trade-off**: Burn-in consumes product lifetime; only used for high-reliability markets (automotive, aerospace, medical)

## Yield and Reliability in Physical Design

### PD Engineer Responsibilities

1. **Follow DFM rules**: Use recommended rules, not just minimum rules, where possible
2. **Insert redundant vias**: Target > 90% double via coverage
3. **Insert proper fill**: Meet density requirements for all layers
4. **Design robust power grid**: Size wires for EM limits with margin
5. **Check EM**: Run EM analysis on all wires and vias; fix violations
6. **Apply aging derating**: Include BTI/HCI degradation in timing signoff
7. **Minimize critical area**: Use wider spacing for critical nets, avoid narrow channels between macros
8. **Enable memory redundancy**: Ensure BIST and repair infrastructure is properly implemented

### Cost of Yield

The cost per good die depends directly on yield:

```
Cost_per_good_die = (Wafer_cost / Dies_per_wafer) / Yield
```

A 10% yield improvement on a 300mm wafer producing 500 dies can save millions of dollars per year in high-volume production. PD engineers who understand and optimize for yield provide direct economic value.
