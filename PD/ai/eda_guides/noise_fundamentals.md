# Noise Fundamentals

## Overview

Noise in VLSI circuits refers to any unwanted disturbance that can alter signal integrity, corrupt data, or cause timing violations. As transistors shrink and supply voltages decrease, noise margins shrink correspondingly, making noise analysis and mitigation essential for reliable chip design. PD engineers must understand the sources of noise, the analysis techniques used to quantify it, and the physical design strategies that mitigate it.

## Noise Margin

### Definition

Noise margin is the amount of noise a circuit can tolerate before an incorrect logic level is produced. For CMOS logic:

```
NM_high = V_OH - V_IH  (margin for logic '1')
NM_low  = V_IL - V_OL  (margin for logic '0')
```

Where:
- V_OH: Output high voltage
- V_IH: Input high threshold
- V_IL: Input low threshold
- V_OL: Output low voltage

### Shrinking Margins

At older nodes (180nm, 130nm), supply voltages were 1.8V or 1.2V, providing hundreds of millivolts of noise margin. At advanced nodes (5nm, 3nm), supply voltages are 0.5-0.75V, and noise margins are proportionally smaller. A 50mV noise event that was harmless at 1.2V can cause a functional failure at 0.65V.

**Physical implication**: Every source of noise that was negligible at older nodes may become significant at advanced nodes. PD engineers must analyze and mitigate noise more carefully.

## Supply Noise

### Static IR Drop

When current flows through the resistive power delivery network (PDN), voltage drops occur. The voltage at a cell's power pin is lower than the supply pad voltage.

```
V_cell = V_pad - I * R_pdn
```

Where R_pdn is the resistance of the power grid from the pad to the cell.

**Analysis**: Static IR drop analysis computes the average voltage drop at every node in the power grid, assuming a uniform or weighted current distribution.

**Impact**: Cells operating at reduced voltage are slower (increased delay). A 10% voltage drop can cause 15-20% delay increase at advanced nodes.

**Mitigation**:
- Design a robust power grid with sufficient metal width and via density
- Place power pads close to high-current regions
- Minimize resistance in the PDN (wider stripes, more vias, lower-resistance metal layers)

### Dynamic IR Drop

During switching events, the instantaneous current demand creates transient voltage drops that can be much larger than static IR drop.

**Causes**:
- Simultaneous switching of many cells (e.g., clock edge triggering thousands of flip-flops)
- Large bus transitions (e.g., 128-bit bus switching from all zeros to all ones)
- Memory read/write operations creating large current spikes

**Analysis**: Dynamic IR drop analysis uses switching activity (VCD/SAIF) to model time-varying current demand and compute transient voltage at every PDN node.

**Impact**: Peak dynamic IR drop can be 2-5x larger than static IR drop. It can cause:
- Timing failures (cells momentarily too slow)
- Functional failures (noise exceeding noise margin)
- Clock jitter (supply noise on clock buffers)

**Mitigation**:
- Insert decoupling capacitors (decap cells) near high-switching regions to provide local charge storage
- Stagger clock gating enables to avoid simultaneous wake-up of large blocks
- Design the PDN for peak current, not just average current
- Add on-chip voltage regulators for critical domains

## Ground Bounce

### Mechanism

Ground bounce occurs when current flowing through the parasitic inductance of the ground connection causes the local ground voltage to rise above the reference ground.

```
V_bounce = L * (dI/dt)
```

Where L is the parasitic inductance (primarily from package bond wires or bumps) and dI/dt is the rate of change of current.

### When It Occurs

Ground bounce is worst when many outputs switch simultaneously (Simultaneous Switching Output, SSO). For example, if 32 output buffers driving an off-chip bus all switch from 1 to 0 at the same time, the aggregate dI/dt through the shared ground bond wire creates significant bounce.

### Impact

- **I/O signal integrity**: Ground bounce on I/O pads corrupts off-chip signal levels
- **Core logic**: If I/O ground is shared with core ground, bounce can propagate to internal logic
- **Timing**: Ground bounce on clock buffers creates clock jitter

### Mitigation

- **Distributed ground pads**: Use many ground pads/bumps to reduce per-pad inductance
- **SSO analysis**: Limit the number of simultaneously switching outputs per ground pad group
- **Separated power domains**: Isolate I/O power/ground from core power/ground
- **Slew rate control**: Reduce output driver slew rate to decrease dI/dt (at the cost of speed)
- **Decoupling capacitors**: On-chip and on-package decaps to provide local current

## Substrate Coupling

### Mechanism

In a shared silicon substrate, noise from one circuit can propagate through the substrate to affect another circuit. The substrate acts as a resistive network connecting all devices.

### Sources of Substrate Noise

- **Digital switching**: Large digital blocks inject noise into the substrate through source/drain junctions
- **I/O drivers**: High-current output buffers inject significant substrate noise
- **Clock buffers**: Clock tree buffers toggle every cycle, injecting periodic noise

### Victims of Substrate Noise

- **Analog circuits**: PLLs, ADCs, DACs, and voltage references are highly sensitive to substrate noise. Even millivolts of substrate noise can degrade analog performance
- **SRAM**: Sense amplifiers in SRAMs are sensitive to substrate noise during read operations
- **Phase-locked loops**: Substrate noise coupling to the VCO causes jitter

### Mitigation

- **Guard rings**: Place deep N-well or substrate contact rings around sensitive analog blocks to absorb substrate noise before it reaches the sensitive circuit
- **Physical separation**: Place noisy digital blocks far from sensitive analog blocks on the floorplan
- **Dedicated substrate taps**: Provide separate substrate contact connections for analog and digital domains
- **Triple-well isolation**: Use deep N-well process option to isolate NMOS devices from the common P-substrate

**Physical implication**: Floorplanning must account for substrate noise. PD engineers should not place high-activity digital blocks (clock generators, I/O banks) adjacent to sensitive analog IP. A floorplan-level noise analysis should be performed early.

## Crosstalk

### Mechanism

When two wires run parallel to each other, capacitive and inductive coupling causes signal transitions on one wire (the aggressor) to affect the other wire (the victim).

### Capacitive Crosstalk

The dominant coupling mechanism in on-chip wiring.

```
V_noise = C_coupling / (C_coupling + C_ground) * V_swing * (1 - exp(-t/RC))
```

**Functional crosstalk (glitch)**: When the victim is quiet and the aggressor transitions, a voltage glitch appears on the victim. If the glitch is large enough, it can cause a logic error.

**Timing crosstalk (delta delay)**: When both aggressor and victim are transitioning:
- Same direction: Effective coupling capacitance is reduced; victim speeds up
- Opposite direction: Effective coupling capacitance is increased; victim slows down

The worst case for setup timing is when the aggressor transitions opposite to the victim (slowdown). The worst case for hold timing is when the aggressor transitions in the same direction as the victim (speedup).

### Crosstalk Analysis

**SI-aware STA** computes delta delays and adds them to path delays. The analysis considers:

- Coupling capacitance between adjacent wires
- Relative timing of aggressor and victim transitions (timing windows)
- Driver strength of both aggressor and victim
- Multiple aggressors affecting a single victim (superposition)

**Glitch analysis** determines whether crosstalk-induced glitches can propagate through logic gates to reach a register input during its capture window.

### Crosstalk Mitigation

**Spacing**: Increase wire spacing between sensitive nets. Doubling the spacing approximately halves the coupling capacitance.

**Shielding**: Route a grounded wire (shield) between sensitive nets. This blocks coupling but consumes routing resources.

**Layer assignment**: Route critical signals on different metal layers from aggressors (vertical vs. horizontal routing reduces parallel run length).

**Net ordering**: During routing, place critical nets first to give them preferred routing resources.

**Driver sizing**: Larger victim drivers have lower output impedance, making them more resilient to crosstalk-induced noise.

**Aggressor activity reduction**: Reduce switching on aggressor nets through clock gating or encoding techniques (e.g., bus inversion coding to reduce transitions).

**Physical implication**: Crosstalk is a routing-stage concern. PD engineers must ensure that critical nets (clocks, resets, high-speed data) have adequate spacing and shielding. Post-route SI analysis is mandatory at signoff.

## Power Supply Noise Analysis

### Full PDN Analysis Flow

1. **Build PDN model**: Extract the power grid as an RLC network from the layout
2. **Determine current demand**: Either from static power estimates or dynamic switching activity
3. **Add package model**: Include package bump/wire inductance and decoupling capacitance
4. **Simulate**: Solve the RLC network with the current demand to compute voltage at every node
5. **Check against limits**: Verify that voltage at every cell meets the minimum operating voltage

### Tools

- **RedHawk** (Synopsys/Ansys): Industry-standard power integrity analysis
- **Voltus** (Cadence): Power analysis integrated with Innovus
- **Totem** (Ansys): Package-level power integrity

### PDN Design Guidelines

| Parameter | Guideline |
|-----------|-----------|
| Static IR drop | < 3-5% of VDD |
| Dynamic IR drop | < 8-10% of VDD |
| Power grid resistance | Minimize (wide stripes, dense vias) |
| Decap density | 5-10% of core area in decap cells |
| Via density | Maximum allowed by DRC rules |

## Noise Budgeting

A noise budget allocates the total noise margin among all noise sources:

```
Total Noise = IR_drop + Ground_bounce + Crosstalk + Substrate_noise + Thermal_noise
Total Noise < Noise Margin
```

Example noise budget at VDD = 0.7V:

| Source | Budget |
|--------|--------|
| Static IR drop | 25mV |
| Dynamic IR drop | 40mV |
| Crosstalk | 20mV |
| Ground bounce | 15mV |
| Substrate noise | 10mV |
| **Total** | **110mV** |
| **Available margin** | **~150mV** |
| **Remaining margin** | **40mV** |

Keeping a positive remaining margin ensures reliable operation. If the budget is exceeded, specific noise sources must be reduced through physical design changes.

## Noise-Aware Physical Design

1. **Floorplanning**: Separate noisy and sensitive blocks; plan power grid for adequate PDN impedance
2. **Power grid design**: Size grid for worst-case dynamic current; insert decap cells
3. **Clock tree**: Shield clock nets; minimize clock wire capacitance
4. **Routing**: Apply spacing rules for critical nets; use shielding where needed
5. **Signoff**: Run SI-aware STA, static/dynamic IR drop analysis, and glitch analysis

Noise is not a single-step verification; it is a concern that permeates every stage of physical design. Early planning and continuous analysis are essential to avoid late-stage noise problems that are expensive to fix.
