# Reliability Checks: Comprehensive Reliability Verification for Silicon Longevity

## Overview

Reliability verification ensures that a chip will function correctly over its intended lifetime under the specified operating conditions. While DRC/LVS/ERC verify that the design is correctly manufactured and connected, reliability checks verify that it will not degrade or fail over time. Key reliability concerns include electromigration, IR drop, ESD, latch-up, transistor aging (NBTI/PBTI), hot carrier injection, and time-dependent dielectric breakdown. PD engineers must understand each failure mechanism and the verification methodology to ensure silicon longevity.

## Electromigration and IR Drop (EM/IR)

EM and IR drop are the most common reliability checks performed by PD engineers. They are covered in detail in the dedicated electromigration.md document. Here we provide a summary in the context of the broader reliability picture.

### IR Drop

IR drop is the voltage reduction across the power distribution network due to resistive losses. Excessive IR drop causes timing degradation and functional failure.

- **Static IR drop**: Average voltage drop under steady-state conditions. Target: <5% of VDD (e.g., <42mV for 0.85V VDD).
- **Dynamic IR drop**: Transient voltage droop caused by sudden current demand (e.g., clock edge, simultaneous switching). Can be 2-5x worse than static. Target: <10% of VDD.
- **Analysis tools**: Synopsys RedHawk/RHDP, Cadence Voltus, ANSYS RedHawk-SC.

### EM Analysis

Electromigration analysis verifies that current densities through wires and vias do not exceed foundry limits. Both signal EM (AC) and power EM (DC) must be checked. Refer to electromigration.md for detailed coverage.

## Electrostatic Discharge (ESD)

ESD events occur when a charged object (human body, machine, charged device) contacts a chip pin, discharging a high-energy pulse through the chip in nanoseconds or picoseconds.

### ESD Models

**Human Body Model (HBM)**: Simulates a charged person touching a chip pin. Characterized by a 100pF capacitor discharged through a 1.5k-ohm resistor. Peak current: approximately 1.3A for 2kV HBM. The chip must survive without damage.

- HBM target levels: Class 1 (250V), Class 1A (500V), Class 1B (1000V), Class 1C (1500V), Class 2 (2000V).
- Most commercial chips target Class 2 (2000V HBM).

**Charged Device Model (CDM)**: Simulates the chip itself becoming charged during handling and then discharging when a pin touches a grounded surface. CDM events are much faster (sub-nanosecond) with higher peak currents (5-10A) but shorter duration.

- CDM is often the more challenging ESD spec at advanced nodes.
- CDM target levels: C1 (125V), C2 (250V), C3 (500V).
- Internal gate oxide protection is critical for CDM.

**Machine Model (MM)**: Less commonly used today; simulates a charged machine tool touching the chip. Being phased out in favor of CDM.

### ESD Verification in PD

- Verify ESD clamp placement at every I/O pad.
- Check ESD discharge path resistance from pad to supply.
- Verify cross-domain ESD protection for multi-supply designs.
- Check CDM protection for internal gates connected to long metal runs.
- Tools: Calibre PERC, Synopsys IC Validator, Cadence Pegasus.

## Latch-Up

Latch-up is a parasitic thyristor (SCR) effect in CMOS circuits where the parasitic PNP and NPN transistors formed by the well structure turn on, creating a low-resistance path between VDD and VSS. Once triggered, latch-up draws excessive current that can destroy the chip.

### Latch-Up Trigger Conditions

- Input or output voltage exceeding supply rails (overshoot/undershoot).
- ESD events.
- High-current transients near well boundaries.
- Insufficient well/substrate biasing.

### Prevention Measures in PD

1. **Guard rings**: N+ guard rings around NMOS and P+ guard rings around PMOS in I/O cells and sensitive analog blocks. Guard rings collect minority carriers before they can trigger the parasitic SCR.
2. **Well tap spacing**: Ensure adequate N-well and P-substrate tap density per foundry rules (typically <15-25um between taps).
3. **I/O cell design**: I/O cells have built-in latch-up protection (guard rings, large taps).
4. **Supply sequencing**: Ensure VDD powers up before or simultaneously with I/O signals to prevent rail-exceeding conditions.

### Latch-Up Verification

Foundries specify latch-up DRC rules that check:
- Guard ring continuity and width.
- Well tap spacing and density.
- Spacing between N-well and P-well regions (NMOS to PMOS spacing).
- I/O cell to core distance.

## NBTI and PBTI Aging

Negative Bias Temperature Instability (NBTI) and Positive Bias Temperature Instability (PBTI) are transistor aging mechanisms that cause threshold voltage (Vth) to increase over time, degrading circuit speed.

### NBTI (Primarily PMOS)

NBTI occurs in PMOS transistors when the gate is negatively biased (logic 0 at the gate, transistor ON). Interface traps form at the Si-SiO2 interface, increasing Vth. The effect worsens at higher temperature and lower (more negative) gate voltage.

- NBTI is the dominant aging mechanism for planar CMOS and FinFETs.
- Typical Vth shift: 10-50mV over 10 years at use conditions.
- Impact on timing: 2-5% delay increase over product lifetime.

### PBTI (Primarily NMOS)

PBTI affects NMOS transistors when the gate is positively biased. It involves charge trapping in the high-k gate dielectric (more significant in HKMG processes).

- PBTI is less severe than NBTI in most processes but not negligible.
- Typical Vth shift: 5-20mV over 10 years.

### Aging-Aware Timing Analysis

PD engineers account for NBTI/PBTI through:
- **Library derating**: Libraries characterized with aged device models (e.g., 10-year aged Vth).
- **Timing margin**: Additional timing margin (AOCV/POCV derating) to account for aging.
- **Gate-level aging analysis**: Tools like Synopsys PrimeTime SI can compute per-instance aging based on signal probability and switching activity.

## Hot Carrier Injection (HCI)

HCI occurs when high-energy (hot) carriers (electrons or holes) gain enough energy from the electric field to be injected into the gate oxide, creating trapped charges and interface states.

### Mechanism

- Occurs primarily in NMOS transistors during switching events.
- The worst case is when both VDS and VGS are high (saturation region during transition).
- Creates localized damage near the drain.
- Causes Vth shift and mobility degradation.

### Impact on Physical Design

- HCI is proportional to switching activity. High-frequency signals (clocks, data buses) are most affected.
- Shorter channel lengths increase HCI susceptibility.
- The impact is typically captured in library characterization with aged models.
- PD engineers should ensure clock and high-activity nets are not oversized (which could increase HCI by increasing switching current).

## Time-Dependent Dielectric Breakdown (TDDB)

TDDB is the progressive degradation of the gate dielectric under electrical stress, eventually leading to a conductive path (breakdown) through the oxide. TDDB is a wear-out mechanism where the probability of failure increases with time, temperature, and electric field.

### Mechanism

Under constant electric field, defects accumulate in the gate oxide. When a critical density of defects is reached, they form a percolation path and the oxide breaks down, causing a gate-to-channel short.

### Factors Affecting TDDB

- **Electric field**: Higher VGS increases the field across the oxide, accelerating breakdown. Overvoltage stress (signals exceeding the rated supply) is extremely dangerous.
- **Temperature**: Higher temperature accelerates defect generation.
- **Oxide thickness**: Thinner oxides have fewer defect sites needed for percolation but are subjected to higher electric fields for the same voltage.
- **Area**: Larger total gate oxide area (more transistors) increases the statistical probability of breakdown somewhere on the chip.

### TDDB in Physical Design

- TDDB is primarily a design-for-reliability concern at the architecture and circuit level.
- PD impact: Ensure that no signal exceeds the rated voltage for its connected devices. Level shifters must be inserted at all voltage domain boundaries.
- Multi-Vt libraries: Thick-oxide (high-Vt) devices have better TDDB margins. Use thick-oxide devices for I/O and level-shifting circuits.
- TDDB analysis: Specialty tools compute TDDB lifetime based on per-transistor operating conditions.

## Comprehensive Reliability Signoff Flow

A complete reliability signoff addresses all mechanisms:

1. **EM/IR analysis**: Verify power grid integrity, wire and via EM compliance.
2. **ESD verification**: Confirm ESD clamp placement, discharge paths, CDM protection.
3. **Latch-up DRC**: Verify guard rings, well taps, spacing rules.
4. **Aging analysis**: Run timing with aged libraries or aging-derated timing.
5. **Antenna check**: Verify no antenna violations (process reliability).
6. **ERC**: Floating gates, well connectivity, power connectivity.

### Reliability Corner Matrix

Reliability checks must be performed at the worst-case conditions:

| Check | Worst-Case Temperature | Worst-Case Voltage | Activity |
|---|---|---|---|
| EM (wire) | Highest | Lowest VDD (highest current per watt) | Maximum switching |
| IR drop (static) | Highest | Nominal | Maximum current |
| IR drop (dynamic) | Highest | Nominal | Burst activity |
| NBTI/PBTI | Highest | Highest | Per-signal probability |
| HCI | Highest | Highest | Maximum switching |
| TDDB | Highest | Highest | Static stress |

## Best Practices

- Integrate reliability checks into the automated signoff flow, not as an afterthought.
- Use realistic switching activity vectors (from RTL simulation) for EM and IR analysis.
- Budget timing margin for aging effects early in the constraint setup.
- Communicate reliability requirements (ESD level, lifetime target, operating temperature) clearly in the design specification.
- Track reliability metrics across design iterations to catch degradation trends.

Reliability is what separates a prototype from a product. PD engineers who incorporate reliability awareness throughout the design flow deliver chips that function correctly for their intended lifetime.
