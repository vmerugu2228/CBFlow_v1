# Electromigration: Physics, Analysis, Rules, and EM-Aware Physical Design

## Overview

Electromigration (EM) is the gradual displacement of metal atoms in a conductor due to momentum transfer from conducting electrons. Over the operating lifetime of an integrated circuit, EM causes material transport that creates voids (open circuits) and hillocks (short circuits) in metal interconnects. EM is one of the most critical reliability failure mechanisms in VLSI, directly constraining wire sizing, via count, power grid design, and signal routing decisions.

EM severity increases with technology scaling because wire cross-sections shrink (higher current density), operating temperatures increase (faster diffusion), and reliability requirements become more stringent (10+ year lifetimes for automotive, 7+ years for consumer). Every metal wire, via, and contact in a design must satisfy EM rules to ensure the chip survives its intended lifetime.

---

## Physics of Electromigration

### Momentum Transfer Mechanism

In a metallic conductor, conduction electrons collide with metal atoms (lattice ions) as they drift under an applied electric field. Each collision transfers momentum from the electron to the atom. While individual collisions produce negligible displacement, the cumulative effect of billions of electrons per second over years of operation produces measurable atomic displacement.

The net force on a metal atom has two components:

1. **Electron wind force (F_wind)**: The momentum transferred from drifting electrons to metal atoms. This force acts in the direction of electron flow (opposite to conventional current direction). F_wind is proportional to current density.

2. **Direct electrostatic force (F_direct)**: The electric field acts directly on the ionic cores of metal atoms. This force acts in the direction of the electric field (same as conventional current). For most interconnect metals, F_direct is smaller than F_wind.

The net force determines the direction of atomic transport: in aluminum and copper interconnects, the electron wind force dominates, so atoms move in the direction of electron flow.

### Huntington-Grone Equation

The atomic flux due to electromigration is described by the Huntington-Grone equation:

```
J_atom = (N * D * Z* * e * rho * j) / (k * T)
```

Where:
- J_atom = atomic flux (atoms per unit area per unit time)
- N = atomic density of the metal
- D = diffusion coefficient = D_0 * exp(-E_a / (k * T))
- Z* = effective charge number (captures both wind and direct forces)
- e = electron charge
- rho = metal resistivity
- j = current density
- k = Boltzmann constant
- T = absolute temperature

This equation shows that EM flux depends on:
- **Current density (j)**: Linear dependence — doubling current doubles EM flux
- **Temperature (T)**: Exponential dependence through D — EM rate roughly doubles per 10-15C increase
- **Activation energy (E_a)**: Higher E_a means slower diffusion and better EM resistance. E_a depends on the dominant diffusion path

### Diffusion Paths

Atomic diffusion in interconnects occurs through several paths, each with a different activation energy:

| Diffusion Path | E_a (eV) for Cu | Dominance |
|---------------|-----------------|-----------|
| Bulk (lattice) | 2.1-2.3 | Negligible in thin films |
| Grain boundary | 0.7-1.0 | Important in narrow wires with bamboo grain structure |
| Interface (Cu/barrier) | 0.7-0.9 | **Dominant in damascene Cu** |
| Surface | 0.5-0.7 | Important in very narrow wires |

For modern copper dual-damascene interconnects, the interface diffusion path (between the copper fill and the Ta/TaN barrier layer) is the dominant mechanism. This is why barrier quality and adhesion are critical for EM reliability.

For aluminum interconnects (legacy processes), grain boundary diffusion dominated, and bamboo grain structures (where the grain spans the full wire width) were used to block this path.

---

## Black's Equation

### Mean Time to Failure (MTTF)

The industry-standard model for EM lifetime prediction is Black's equation:

```
MTTF = A * j^(-n) * exp(E_a / (k * T))
```

Where:
- MTTF = mean time to failure (hours)
- A = empirical constant (depends on metal/process/geometry)
- j = current density (MA/cm^2 or mA/um^2)
- n = current density exponent (typically 1-2; n=2 is common for void nucleation-limited failure)
- E_a = activation energy (eV)
- k = Boltzmann constant (8.617 x 10^-5 eV/K)
- T = absolute temperature (Kelvin)

### Understanding Black's Equation Parameters

**Current density exponent (n):**
- n = 1: Void growth-limited failure (EM flux linearly proportional to j)
- n = 2: Void nucleation-limited failure (EM-induced stress must exceed a threshold, leading to j^2 dependence)
- Most foundries use n = 1 or n = 2. The value affects how aggressively current density limits scale.

**Activation energy (E_a):**
- Higher E_a → longer lifetime → better EM resistance
- Cu interface diffusion: E_a ≈ 0.7-0.9 eV
- Cu grain boundary: E_a ≈ 0.9-1.0 eV
- Al grain boundary: E_a ≈ 0.5-0.7 eV

**Temperature dependence:**
- At E_a = 0.8 eV, increasing temperature from 105C to 125C (a 20C increase) reduces MTTF by roughly 3x
- This extreme temperature sensitivity makes thermal management critical for EM

### MTTF Calculation Example

For a copper wire at 105C carrying 1 mA/um^2:
```
E_a = 0.8 eV, n = 2, A = 1e12 (process-dependent)
T = 105 + 273 = 378 K
MTTF = 1e12 * (1.0)^(-2) * exp(0.8 / (8.617e-5 * 378))
MTTF = 1e12 * 1 * exp(24.5)
MTTF = 1e12 * 4.4e10 = 4.4e22 hours (effectively infinite)
```

At 2 mA/um^2 (doubling current density with n=2):
```
MTTF = 1e12 * (2.0)^(-2) * exp(24.5)
MTTF = 1e12 * 0.25 * 4.4e10 = 1.1e22 hours (still very long)
```

At 10 mA/um^2 (typical stress condition):
```
MTTF = 1e12 * (10.0)^(-2) * exp(24.5)
MTTF = 1e12 * 0.01 * 4.4e10 = 4.4e20 hours
```

Foundries calibrate the A parameter against accelerated EM test data to derive current density limits for a target MTTF (typically 10 years = 87,600 hours at the specified operating temperature).

---

## Blech Length (Short-Line Effect)

### The Blech Effect

In 1976, I.A. Blech discovered that below a critical wire length, no EM failure occurs regardless of current density. This is because the back-stress (mechanical stress gradient) created by atom accumulation at the anode end and depletion at the cathode end opposes further EM transport, creating a steady-state equilibrium.

### Blech Length Equation

```
j * L_critical = (delta_sigma * omega) / (Z* * e * rho)
```

Where:
- j = current density
- L_critical = Blech length (critical length below which no EM occurs)
- delta_sigma = critical back-stress (material-dependent, typically 100-500 MPa)
- omega = atomic volume

For copper at typical operating conditions, the Blech length product (j * L) is approximately:

```
j * L_Blech ≈ 3000-5000 A/cm (for Cu at 105C)
```

This means:
- At j = 1 MA/cm^2 = 1e6 A/cm^2, L_Blech = 3000/1e6 = 30um
- Wires shorter than 30um at this current density are immune to EM failure

### Practical Implications of Blech Length

- Short signal wires (most standard-cell-to-standard-cell connections) are often below the Blech length and are EM-immune
- Long power/ground buses, clock trunks, and inter-block signal routes are typically above the Blech length and must be checked
- The Blech effect allows routers to use narrower wires for short connections without EM concern
- Advanced EM analysis tools (RedHawk, Voltus) incorporate the Blech effect to avoid false EM violations on short wires

---

## EM Current Density Types

### Average (DC) Current Density

The time-averaged current through the wire over the switching cycle. Relevant for:
- Power/ground wires (carry unidirectional current)
- Signal wires with strong directional bias (e.g., data buses that are mostly writing)

```
j_avg = I_avg / (wire_width * wire_thickness)
```

Most EM rules are specified in terms of average current density because EM is a long-term phenomenon driven by net atomic displacement.

### Peak Current Density

The maximum instantaneous current through the wire. Relevant for:
- Short-duration high-current events
- Rush current during power-on
- Signal wires with large current spikes

Some foundries specify peak current density limits (typically 5-10x the average limit) to prevent instantaneous damage mechanisms like Joule heating.

### RMS Current Density

The root-mean-square current density. Relevant for:
- Joule heating calculations (self-heating of wires)
- Temperature estimation for EM analysis
- Via EM (where heating effects are more pronounced)

```
j_RMS = sqrt(1/T * integral(j(t)^2 dt, 0, T))
```

### AC Enhancement Factor

For signal wires that carry bidirectional current (switching between 0 and 1), the net EM force partially cancels during each switching cycle. Foundries provide AC enhancement factors that increase the allowed current density for AC (bidirectional) wires:

```
j_limit_AC = j_limit_DC * AC_factor

Typical AC_factor: 5-20 (depends on frequency, duty cycle, foundry)
```

For a wire with 50% duty cycle carrying current in alternating directions, the effective EM driving force is much less than for a DC wire carrying the same peak current.

---

## EM Rules Per Metal Layer

### Foundry EM Rule Tables

Foundries specify EM current density limits per metal layer, wire width, and temperature:

| Layer | Width (nm) | j_avg_limit (mA/um) @ 105C | j_peak_limit (mA/um) | Notes |
|-------|-----------|------------------------------|----------------------|-------|
| M1 | 36 | 0.15 | 1.5 | Thinnest, most vulnerable |
| M2 | 36 | 0.15 | 1.5 | |
| M3 | 40 | 0.18 | 1.8 | Slightly wider |
| M4 | 40 | 0.18 | 1.8 | |
| M5 | 48 | 0.25 | 2.5 | Semi-global |
| M6 | 48 | 0.25 | 2.5 | |
| M7 | 80 | 0.50 | 5.0 | Thick global |
| M8 | 80 | 0.50 | 5.0 | |
| M9 | 800 | 5.0 | 50.0 | Ultra-thick (AP) |
| M10 | 3200 | 20.0 | 200.0 | RDL |

**Important**: These are illustrative values. Actual limits depend on the specific foundry process, reliability qualification data, and operating lifetime requirements.

### Via EM Rules

Vias have their own EM limits, typically expressed as current per via:

| Via Layer | j_limit (mA/via) @ 105C | Notes |
|-----------|-------------------------|-------|
| Via1 | 0.05-0.10 | Single via between M1-M2 |
| Via2 | 0.05-0.10 | |
| Via3 | 0.08-0.12 | |
| Via4 | 0.08-0.12 | |
| Via5 | 0.10-0.15 | |
| Via6+ | 0.15-0.30 | Larger vias |

Via EM is often more critical than wire EM because:
- Vias are small (single via has very small cross-section)
- Via-metal interfaces are diffusion bottlenecks
- Via failure modes include voiding at the via bottom (cathode end)

### Temperature Derating

EM limits decrease at higher temperatures due to Black's equation. Foundries provide temperature derating factors:

```
j_limit(T) = j_limit(T_ref) * exp(E_a/k * (1/T - 1/T_ref))
```

Example: If j_limit at 105C = 0.5 mA/um, then at 125C:
```
j_limit(125C) = 0.5 * exp(0.8/8.617e-5 * (1/398 - 1/378))
             = 0.5 * exp(0.8/8.617e-5 * (-1.33e-4))
             = 0.5 * exp(-1.23)
             = 0.5 * 0.29
             = 0.15 mA/um
```

A 20C increase reduces the EM limit by 3.3x. This illustrates why temperature management is critical.

---

## EM-Aware Routing

### Wire Widening

The most direct EM fix for a wire carrying too much current is to widen it:

```
j = I / (W * T)
```

Doubling the wire width halves the current density. However, widening has costs:
- More routing area consumed
- Higher capacitance (impacts timing and power)
- May cause congestion and DRC violations

```tcl
# Innovus: set minimum width for EM-critical nets
setAttribute -net VDD -preferred_extra_space 2
setNanoRouteMode -routeWithEco true

# Set non-default width rules for power nets
create_routing_rule EM_WIDE_RULE \
  -widths {M5:0.1 M6:0.1 M7:0.2 M8:0.2} \
  -spacings {M5:0.08 M6:0.08 M7:0.1 M8:0.1}

setAttribute -net VDD -routing_rule EM_WIDE_RULE
setAttribute -net VSS -routing_rule EM_WIDE_RULE
```

### Via Arrays (Redundant Vias)

Since via EM limits are often the bottleneck, using multiple vias in parallel (via arrays) distributes the current:

```
I_per_via = I_total / N_vias
```

Doubling the number of vias halves the current per via. Via arrays also improve yield (redundancy against via voiding).

```tcl
# Innovus: enable redundant via insertion
setNanoRouteMode -droutePostRouteViaInsertionEffort high
addRedundantVia -net {VDD VSS clk_core} \
  -allLayers \
  -maxViaCount 4
```

### EM-Aware Power Grid Design

Power grid design must account for EM from the outset:

1. **Calculate total current per metal stripe**: From power analysis, determine current drawn by each row of standard cells
2. **Size stripes for EM**: Ensure each stripe width satisfies j_avg < j_limit for its current load
3. **Use multiple vias at stripe-to-stripe connections**: Via arrays at every stripe intersection
4. **Distribute current paths**: Mesh topology distributes current more evenly than tree topology
5. **Consider local hotspots**: High-activity logic creates local current spikes that may exceed average-based EM limits

```tcl
# Innovus: power grid with EM-aware stripe widths
addStripe -nets {VDD VSS} \
  -layer M8 -direction horizontal \
  -width 2.0 -spacing 0.5 \
  -set_to_set_distance 20.0 \
  -start_from bottom -start_offset 5.0

addStripe -nets {VDD VSS} \
  -layer M9 -direction vertical \
  -width 4.0 -spacing 1.0 \
  -set_to_set_distance 30.0 \
  -start_from left -start_offset 5.0
```

### Signal Net EM

Signal nets are typically less EM-critical than power nets because:
- Signal currents are transient (AC), benefiting from the AC enhancement factor
- Most signal wires are short (below Blech length)
- Signal current magnitudes are much lower than power currents

However, signal EM can be a concern for:
- Clock nets (high frequency, large fanout, significant average current)
- High-speed serial I/O (continuous switching, high current)
- Scan chains (high toggle rate during test mode)
- Bus drivers (large output buffers with high peak current)

---

## EM Analysis in EDA Tools

### Static EM Analysis

Static analysis computes average current from power data (switching activity) without time-domain simulation:

```tcl
# RedHawk static EM analysis
set_power_analysis_mode -method static
set_power_pads_from_file padfile.tcl
set_pg_net_voltage VDD 0.9
set_pg_net_voltage VSS 0.0

# Load switching activity
set_switching_activity -global_activity 0.1 -global_freq 1e9

# Run EM analysis
run_em_analysis
report_em_violation -limit 100 -file em_violations.rpt
```

```tcl
# Voltus static EM analysis
set_power_analysis_mode -method static
set_default_switching_activity -input_activity 0.1 -period 1e-9
run_power_analysis
report_em -file em_report.rpt -limit 100
```

### Dynamic EM Analysis

Dynamic analysis uses time-domain current waveforms (from VCD or FSDB) for more accurate EM assessment:

```tcl
# Voltus dynamic EM
set_power_analysis_mode -method dynamic
read_activity_file -format vcd -scope tb/dut chip.vcd -start 100ns -end 200ns
run_power_analysis
report_em -file em_dynamic.rpt -detail
```

Dynamic analysis captures:
- Time-varying current profiles
- Peak current events
- RMS current for self-heating analysis
- Proper AC enhancement factor calculation

### EM Signoff Flow

1. **Run power analysis** (static or dynamic) to determine current per net/segment
2. **Run EM check** against foundry EM rules (temperature-derated)
3. **Identify violations**: Sort by severity (worst j/j_limit ratio first)
4. **Fix violations**:
   - Power nets: Widen stripes, add vias, redistribute current
   - Signal nets: Upsize drivers (reduce current per output), widen wires, add vias
   - Clock nets: Widen clock trunk, add redundant vias
5. **Re-run EM analysis** to verify fixes
6. **Final signoff** with EM clean report

### EM Reports and Metrics

Key metrics in EM reports:

- **j/j_limit ratio**: Current density divided by limit. Must be < 1.0 for all segments. Values > 0.8 are marginal.
- **Worst violating net**: The net with the highest j/j_limit ratio
- **Number of violations**: Total segments exceeding EM limits
- **Lifetime (MTTF)**: Predicted failure time based on Black's equation
- **Current per via**: Via current vs via EM limit

```
# Example EM violation report
Net: VDD
  Segment: M8 stripe from (100,200) to (100,800)
  Width: 2.0um, Current: 5.2mA, j = 2.6 mA/um
  j_limit: 2.0 mA/um, j/j_limit: 1.30  ** VIOLATION **
  Fix: Widen to 3.0um (j = 1.73 mA/um, j/j_limit: 0.87)

Net: clk_core
  Via: Via6 at (250,350)
  Current per via: 0.18mA, limit: 0.15mA, ratio: 1.20  ** VIOLATION **
  Fix: Add redundant via (2 vias, 0.09mA each, ratio: 0.60)
```

---

## Advanced EM Topics

### Self-Heating and EM

Current flow through a resistive wire generates Joule heat (P = I^2 * R), raising the local temperature above the ambient. This self-heating increases the EM rate (through Black's equation temperature dependence), creating a positive feedback loop:

```
More current → More heat → Higher temperature → Faster EM → Void formation → Higher resistance → More heat → ...
```

Self-heating is most severe in:
- Narrow wires carrying high current
- Dense routing regions with poor thermal dissipation
- Power grid stripes at current bottlenecks

Advanced EM analysis tools (RedHawk/Voltus) include self-heating models that compute the temperature rise and use the elevated temperature for EM evaluation.

### EM in Back-End-of-Line (BEOL) Reliability

EM testing is performed during technology qualification using accelerated stress tests:

1. **Wafer-level EM test**: Test structures (serpentine wires) are stressed at elevated temperature (250-350C) and high current density (10-50 mA/um^2)
2. **Failure criteria**: Resistance increase > 10-20% indicates void formation
3. **Statistical analysis**: MTTF is extracted using log-normal distribution
4. **Extrapolation**: Black's equation extrapolates from test conditions to operating conditions

### EM in Advanced Nodes

At 7nm/5nm/3nm:
- Wire cross-sections are extremely small (e.g., M1 at 36nm pitch, ~18nm wide, ~40nm tall)
- Resistivity increases due to surface scattering and grain boundary scattering (approaching the electron mean free path in copper)
- Alternative metals (cobalt, ruthenium) are being used for lower layers due to better EM resistance at small dimensions
- Via resistance increases, and single vias are more vulnerable
- Self-aligned vias improve via reliability but have different EM characteristics
- Barrier thickness becomes a significant fraction of total wire width, reducing effective copper area

### EM and Reliability Budgeting

The chip's total reliability budget is shared among all failure mechanisms (EM, TDDB, NBTI, HCI). EM typically gets 10-30% of the total failure budget:

```
Total chip FIT (Failures In Time) budget: 100 FIT
EM allocation: 20 FIT
Number of EM-critical segments: 10,000
Per-segment FIT budget: 20/10000 = 0.002 FIT
Required MTTF per segment: 1/0.002 = 500 billion hours
```

This extreme MTTF requirement (far beyond the chip's lifetime) is necessary because the weakest segment determines the chip's EM reliability.

---

## Troubleshooting

### Common EM Issues

**Power grid EM violations**: The most common EM issue. Fix by widening stripes, adding more stripes, improving via arrays, or reducing the current demand (optimize power at the source).

**Clock tree EM violations**: Clock nets switch at full frequency with significant current. Fix by upsizing clock buffers (lower output resistance = less current per buffer), widening clock wires, or using lower metal layers for local distribution (shorter segments).

**Via EM violations**: Single vias between layers. Fix by adding redundant vias (2x, 3x, 4x arrays). Ensure the router is configured for maximum via redundancy.

**EM violations at high temperature**: EM limits are very sensitive to temperature. If the thermal analysis shows local hotspots, the EM limits at those locations are much tighter. Fix by reducing local power density or improving thermal dissipation.

**EM violations during stress modes (test/burn-in)**: Burn-in and ATPG test modes may have much higher switching activity than functional mode. Verify EM under these conditions separately.

### Expert Tips

- Design the power grid with 20-30% EM margin from the start. Late-stage EM fixes are expensive and disruptive.
- Always use redundant vias, especially on power nets and clock nets. Set the router to maximum via redundancy effort.
- Run EM analysis at the maximum operating temperature, not room temperature. A design that passes EM at 25C may fail at 105C.
- Account for voltage drop when calculating EM: IR drop reduces the effective voltage, which changes the current distribution and can create EM hotspots.
- Use the Blech length effect to avoid over-designing short wires. This can save significant area.
- For power grid EM, consider the worst-case switching activity scenario, not just the typical case.
- Track EM violations as a QoR metric. Zero EM violations should be achieved well before tapeout.
- Coordinate EM analysis with thermal analysis — they are coupled through Black's equation temperature dependence.
- When widening wires for EM, verify that the wider wire does not cause timing degradation (increased capacitance) or DRC violations (spacing).
- Consider wire and via EM limits together; fixing wire EM by widening may shift the bottleneck to vias.
