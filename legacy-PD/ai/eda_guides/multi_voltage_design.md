# Multi-Voltage Design: DVFS, Voltage Islands, Level Shifters, Isolation, and Power Switches

## Overview and Motivation

Multi-voltage design is the foundational technique for power optimization in modern SoC architectures. By partitioning a chip into regions that operate at different supply voltages, designers exploit the quadratic relationship between voltage and dynamic power (P_dynamic = alpha * C * V^2 * f) and the exponential relationship between voltage and leakage power to achieve dramatic energy savings. A functional block running at 0.72V instead of 0.90V consumes roughly 64% of the dynamic power, while leakage may drop by 3-5x depending on threshold voltage sensitivity.

Multi-voltage design is not a single technique but an umbrella encompassing Dynamic Voltage and Frequency Scaling (DVFS), static voltage islands, power gating with isolation and retention, level shifting between domains, and power sequencing. Every modern mobile processor, automotive SoC, IoT chip, and server processor uses some combination of these techniques. The complexity of multi-voltage design lies not in any single element but in the interaction of all these elements together with the physical implementation, timing closure, and verification flows.

This guide covers every aspect in production-level depth: the physics, the architecture, the standard cell library requirements, the UPF specification, the EDA tool implementation, and the verification and signoff methodology.

---

## Dynamic Voltage and Frequency Scaling (DVFS)

### Fundamental Concept

DVFS dynamically adjusts both the supply voltage and operating frequency of a logic domain based on real-time workload demands. When the workload is light, voltage and frequency are reduced together to save power. When peak performance is needed, both are increased. The key insight is that reducing voltage requires reducing frequency (because gate delay increases with lower voltage), but the power savings from voltage reduction far outweigh the performance loss from frequency reduction.

### Operating Performance Points (OPPs)

A DVFS domain defines a discrete set of voltage/frequency pairs called Operating Performance Points:

| OPP Name | Voltage (V) | Frequency (GHz) | Use Case | Power Ratio |
|----------|-------------|------------------|----------|-------------|
| TURBO | 1.05 | 3.0 | Peak burst | 1.00x |
| NOM | 0.90 | 2.4 | Normal operation | 0.61x |
| SVS | 0.75 | 1.6 | Medium workload | 0.36x |
| SVS_L1 | 0.65 | 1.0 | Light workload | 0.23x |
| LOW_SVS | 0.55 | 0.6 | Background tasks | 0.14x |
| RETENTION | 0.50 | 0.0 | State retention | Leakage only |

The power ratio column shows approximate dynamic power relative to TURBO, illustrating the dramatic savings from DVFS. At SVS, the domain uses only 36% of the dynamic power while delivering 53% of peak performance -- an excellent tradeoff for most workloads.

### DVFS Transition Sequencing

The transition between OPPs must follow strict sequencing rules to avoid timing violations:

**Upward transition (increasing performance):**
1. Raise the voltage first (voltage regulator ramp)
2. Wait for voltage to stabilize (regulator settling time, typically 1-10us)
3. Increase the frequency (PLL re-lock or clock divider change)
4. Wait for frequency to stabilize (PLL lock time, typically 5-50us)
5. Resume operation

**Downward transition (decreasing performance):**
1. Reduce the frequency first
2. Wait for frequency to stabilize
3. Reduce the voltage
4. Wait for voltage to stabilize

The reason for this ordering: if voltage drops before frequency, gates become too slow to meet the current clock period, causing timing violations and data corruption. If frequency increases before voltage rises, the same problem occurs.

### DVFS Hardware Implementation

A complete DVFS system requires:

- **Power Management IC (PMIC) or on-chip LDO**: Provides the variable voltage supply. Off-chip PMICs (buck converters) are more efficient but slower to transition. On-chip LDOs are faster but less efficient and produce more heat.
- **PLL or clock generator**: Provides the variable-frequency clock. May use a PLL with programmable dividers or a digitally controlled oscillator (DCO).
- **Performance monitors**: On-chip ring oscillator monitors (ROMs) or critical path replicas that measure actual silicon speed, enabling Adaptive Voltage Scaling (AVS) where the voltage is adjusted to the minimum level that meets the frequency target for the specific die.
- **Power management controller (PMC)**: Firmware-driven controller that orchestrates voltage/frequency transitions, enforces sequencing, and responds to workload changes.
- **Voltage comparator/detector**: Detects when voltage has reached the target level before allowing frequency changes.

### DVFS Timing Implications

Each OPP creates a unique timing scenario that must be closed independently. For a domain with 5 OPPs across 3 PVT corners (slow/typical/fast) and 2 extraction corners (Cmax/Cmin), you may have 5 x 3 x 2 = 30 timing scenarios for that single domain. Multiply by 4 power modes (active, clock-gated, retention, off) and the scenario count explodes.

Practical strategies to manage this:
- **Voltage-frequency co-optimization**: Each OPP is designed so the timing margin is roughly equal, meaning the voltage is the minimum needed for the frequency
- **Critical OPP identification**: Usually the lowest voltage OPP with active logic is the hardest to close timing-wise; focus optimization effort there
- **Shared constraints**: Use a single SDC with voltage-parameterized clock definitions
- **Scenario reduction**: Use sensitivity analysis to identify which corners are truly bounding

### Adaptive Voltage Scaling (AVS)

AVS extends DVFS by dynamically adjusting voltage based on actual silicon performance rather than worst-case assumptions. On-chip speed monitors (ring oscillators or critical path replicas) measure the actual delay of the silicon at the current PVT conditions. If the silicon is faster than expected (fast process corner, low temperature), the voltage can be reduced below the nominal OPP voltage while still meeting the frequency target. AVS typically saves an additional 50-100mV beyond nominal DVFS voltages, yielding 10-20% additional power savings.

AVS requires:
- Calibrated ring oscillator monitors placed in representative locations
- A lookup table or closed-loop controller that maps monitor frequency to minimum voltage
- Guard-band management to account for monitor-to-critical-path correlation

---

## Voltage Islands

### Definition and Architecture

A voltage island is a contiguous physical region of the chip that operates at a fixed (or DVFS-variable) supply voltage distinct from neighboring regions. Unlike DVFS which changes voltage dynamically, the concept of voltage islands refers to the spatial partitioning of the chip into distinct supply domains.

### Partitioning Strategies

**Performance-based partitioning**: High-performance blocks (CPU cores, DSP accelerators) operate at higher voltage; low-performance blocks (peripherals, configuration logic) operate at lower voltage.

**Activity-based partitioning**: Blocks that are frequently active (clock controllers, interrupt handlers) are kept at nominal voltage; blocks that are rarely active (specialized accelerators, debug logic) can be power-gated or run at reduced voltage.

**IP-based partitioning**: Third-party IP blocks (PHYs, PLLs, memory compilers) often require specific voltages that differ from the core logic voltage. These naturally form separate voltage islands.

**Reliability-based partitioning**: Analog blocks, I/O cells, and high-reliability blocks may require dedicated voltage levels for noise isolation or oxide reliability.

### Physical Implementation of Voltage Islands

Each voltage island requires:

1. **Dedicated power grid**: Separate VDD mesh connected through package bumps or redistribution layers to the appropriate supply. The power grid must be sized for the peak current of the island.

2. **Guard ring / boundary definition**: The physical boundary between islands must be clearly defined in the floorplan. Typically, a gap of several microns separates islands to accommodate power grid transitions and level shifter placement.

3. **Level shifters at every signal crossing**: Every signal that crosses from one voltage domain to another must pass through a level shifter. Missing a single level shifter causes incorrect logic levels and potential reliability failure.

4. **Isolation cells for power-gated domains**: If the island can be powered down, every output signal must pass through an isolation cell that clamps the output to a safe value during power-off.

5. **Decoupling capacitance**: Each island needs its own decoupling capacitance budget, sized for the switching current of the island's logic.

6. **ESD protection**: Each supply pin requires its own ESD clamp structure.

```tcl
# Floorplan with voltage islands in Innovus
create_power_domain PD_CPU -elements {u_cpu_subsys}
create_power_domain PD_GPU -elements {u_gpu_subsys}
create_power_domain PD_PERIPH -elements {u_uart u_spi u_i2c u_gpio u_timer}
create_power_domain PD_ALWAYS_ON -elements {u_pmc u_wakeup u_retention_ctrl}

# Each domain gets its own supply
create_supply_net VDD_CPU -domain PD_CPU
create_supply_net VDD_GPU -domain PD_GPU
create_supply_net VDD_PERIPH -domain PD_PERIPH
create_supply_net VDD_AON -domain PD_ALWAYS_ON
create_supply_net VSS  ;# Ground is shared

# Power rings around each island
create_pg_ring -nets {VDD_CPU VSS} -layer {M9 M10} -width {2.0 2.0} -spacing 1.0 -around PD_CPU
create_pg_ring -nets {VDD_GPU VSS} -layer {M9 M10} -width {3.0 2.0} -spacing 1.0 -around PD_GPU
```

### Voltage Island Floorplanning Guidelines

- Keep islands rectangular with clean, straight boundaries
- Minimize the number of signal crossings between islands (partition signals early in RTL)
- Place level shifters and isolation cells along the island boundary in dedicated rows
- Ensure adequate spacing between islands for power grid isolation (minimum 5-10um at advanced nodes)
- Consider thermal adjacency: do not place two high-power islands adjacent without thermal relief
- Route island power supplies on upper metal layers to minimize IR drop

---

## Level Shifters

### Why Level Shifters Are Necessary

When a signal transitions from a low-voltage domain (e.g., 0.72V) to a high-voltage domain (e.g., 0.90V), the input signal swing does not reach the full VDD of the receiving domain. This causes:

- **Increased short-circuit current**: The receiving inverter/gate sees an input that dwells in the transition region longer, causing both PMOS and NMOS to be partially on simultaneously
- **Reduced noise margin**: The logic-high level is below VDD of the receiving domain
- **Potential functional failure**: If the low-voltage swing does not exceed the switching threshold of the high-voltage gate
- **Reliability degradation**: Sustained intermediate voltages on gate oxides accelerate NBTI/PBTI aging

Conversely, when a signal transitions from a high-voltage domain to a low-voltage domain, the input signal exceeds VDD of the receiving domain. This causes:

- **Gate oxide overstress**: The input voltage exceeds the rated oxide voltage of thin-oxide devices
- **Increased leakage**: Forward-biased junctions in the receiving domain
- **Potential latch-up**: Excessive voltage can trigger parasitic thyristor structures

### Level Shifter Types: Low-to-High (LH)

LH level shifters convert a low-voltage-swing signal to a high-voltage-swing signal. This is the more challenging direction because the low-voltage input may not have sufficient drive strength to switch high-voltage transistors.

#### Cross-Coupled PMOS LH Shifter
The classic LH level shifter uses two cross-coupled PMOS pull-up transistors and two NMOS pull-down transistors. The input and its complement drive the NMOS gates. When the input is high (at V_low), the corresponding NMOS pulls one node low, which through the cross-coupled PMOS feedback, pulls the other node to V_high.

- Advantages: Simple, small area, reliable
- Disadvantages: Requires complementary input or internal inverter; has a minimum V_low/V_high ratio (~0.4) below which it fails to switch
- Typical delay: 150-300ps depending on voltage ratio and node

#### Differential Cascode LH Shifter
Uses a cascode structure with both thin-oxide and thick-oxide devices. The thin-oxide devices handle the low-voltage input; the thick-oxide devices handle the high-voltage output. Better for large voltage ratios.

- Advantages: Works at lower V_low/V_high ratios (~0.3), more robust
- Disadvantages: Larger area (4-6 more transistors), higher power
- Typical delay: 200-400ps

#### Current-Mirror LH Shifter
Uses a current mirror to sense the low-voltage input current and reproduce it in the high-voltage domain. The most robust approach for very low input voltages.

- Advantages: Works at very low V_low/V_high ratios (~0.25), monotonic transfer
- Disadvantages: Static current consumption, larger area
- Typical delay: 300-500ps

### Level Shifter Types: High-to-Low (HL)

HL level shifters convert a high-voltage-swing signal to a low-voltage-swing signal. This direction is simpler because the high-voltage input already exceeds the threshold of low-voltage devices, but care must be taken not to overstress thin-oxide gates.

#### Thick-Oxide Pass Gate HL Shifter
A thick-oxide pass transistor limits the voltage swing before driving a thin-oxide buffer/inverter powered by the low supply.

- Advantages: Simple, small, fast
- Disadvantages: Threshold voltage drop across pass gate reduces noise margin

#### Voltage Clamp HL Shifter
Uses a diode-connected or gate-biased clamping device to limit the voltage swing to the low-voltage range before buffering.

- Advantages: Better noise margin than pass-gate approach
- Disadvantages: Slightly more complex, static leakage through clamp

#### Dual-Rail HL Shifter
Uses both V_high and V_low supplies internally, with thick-oxide input stage and thin-oxide output stage. The most common production approach.

- Advantages: Full voltage swing at output, good noise margin, no static current
- Disadvantages: Requires both supply rails routed to the cell
- Typical delay: 100-200ps (easier direction, faster than LH)

### Enable-Level Shifters

An enable-level shifter includes an enable control that forces the output to a defined value when disabled. This is critical for signals originating from power-gated domains. When the source domain is off, the input to the level shifter is undefined (floating). The enable pin (driven by always-on logic) forces the output to a known state (0 or 1).

Enable LS variants:
- **ELS_LH_CLAMP0**: LH shifter that clamps output to 0 when disabled
- **ELS_LH_CLAMP1**: LH shifter that clamps output to 1 when disabled
- **ELS_HL_CLAMP0**: HL shifter that clamps output to 0 when disabled

### Combined Isolation-Level Shifter (ISO-LS) Cells

When a signal from a power-gated domain crosses a voltage boundary, it needs both isolation (to handle the undefined state during power-off) and level shifting (to handle the voltage difference). Using separate cells wastes area and increases delay. Combined ISO-LS cells integrate both functions:

- **ISO_LS_LH_CLAMP0**: Isolates to 0 and shifts low-to-high
- **ISO_LS_LH_CLAMP1**: Isolates to 1 and shifts low-to-high
- **ISO_LS_HL_CLAMP0**: Isolates to 0 and shifts high-to-low
- **ISO_LS_LH_LATCH**: Latches last value and shifts low-to-high

Area savings: 30-40% compared to separate ISO + LS cells. Delay savings: 20-30%.

### Level Shifter Placement Rules

```tcl
# UPF level shifter specification
set_level_shifter ls_cpu_out \
  -domain PD_CPU \
  -applies_to outputs \
  -rule low_to_high \
  -threshold 0.05 \
  -location self

set_level_shifter ls_cpu_in \
  -domain PD_CPU \
  -applies_to inputs \
  -rule high_to_low \
  -threshold 0.05 \
  -location parent
```

The `-location` option controls placement:
- **self**: Place in the source domain. The LS is powered by the source domain's supply. Best for HL shifters.
- **parent**: Place in the receiving (parent) domain. The LS is powered by the receiving domain's supply. Best for LH shifters and for power-gated source domains.
- **fanout**: Place one LS per fanout endpoint. Used when the signal fans out to multiple domains.

The `-threshold` option specifies the minimum voltage difference that triggers LS insertion. Setting it to 0.0 inserts LS for any voltage difference; 0.05 means only insert when the difference exceeds 50mV.

### Level Shifter Timing Modeling

Level shifters are modeled in Liberty (.lib) with delay tables indexed by:
- Input transition time
- Output load capacitance
- Input supply voltage (for multi-voltage characterization)
- Output supply voltage

Example Liberty snippet:
```
cell (LSLH_D1_X1) {
  pg_pin (VDD_IN) { voltage_name : VDD_LOW; pg_type : primary_power; }
  pg_pin (VDD_OUT) { voltage_name : VDD_HIGH; pg_type : primary_power; }
  pg_pin (VSS) { voltage_name : VSS; pg_type : primary_ground; }
  pin (I) { direction : input; related_power_pin : VDD_IN; }
  pin (Z) { direction : output; related_power_pin : VDD_OUT;
    timing () {
      related_pin : "I";
      cell_rise (delay_7x7) { ... }
      cell_fall (delay_7x7) { ... }
      rise_transition (delay_7x7) { ... }
      fall_transition (delay_7x7) { ... }
    }
  }
}
```

Level shifter delay must be properly accounted for in STA. Typical LS delays range from 100ps to 500ps depending on direction, voltage ratio, and drive strength.

---

## Isolation Cells

### Purpose and Necessity

When a power domain is turned off (power-gated), all logic within it loses state and its outputs float to undefined values. These undefined outputs can cause:
- Spurious switching in the active receiving domain (wasting power, causing noise)
- Logic corruption leading to functional failure
- Crowbar current if floating inputs sit at mid-rail voltage
- Latch-up if floating outputs forward-bias junctions

Isolation cells force the outputs of a powered-down domain to known, safe logic values.

### Isolation Cell Types

#### AND-Based Isolation (Clamp-to-0)

```
ISO_EN_B (active low) ─┐
                        ├─ AND ─── Output
Signal ────────────────┘
```

When ISO_EN_B is low (isolation active), output is forced to 0 regardless of signal. When ISO_EN_B is high (isolation inactive), output follows signal. Used for signals where the safe default is logic 0 (enables, requests, valid signals).

#### OR-Based Isolation (Clamp-to-1)

```
ISO_EN (active high) ──┐
                        ├─ OR ─── Output
Signal ────────────────┘
```

When ISO_EN is high (isolation active), output is forced to 1. Used for signals where the safe default is logic 1 (active-low resets, ready signals, acknowledge signals).

#### Latch-Based Isolation

A transparent latch captures the last valid value of the signal before power-down and holds it during the off state. More complex than clamp isolation but preserves the pre-power-down state.

Used when the receiving logic needs continuity of the signal value across power transitions, or when neither 0 nor 1 is universally safe.

Implementation: A level-sensitive latch with the enable connected to the isolation control signal. When isolation is about to activate, the latch captures the current value and holds it.

#### High-Z (Tri-State) Isolation

A tri-state buffer that drives the output to high-impedance when isolation is active. Used primarily for shared bus interfaces where only one driver should be active at a time. Requires pull-up or pull-down resistors on the bus to define the idle state.

### Isolation Cell Power Supply

**Critical design rule**: The isolation cell must be powered by a supply that remains active when the source domain is off. This is typically:
- The receiving domain's supply (if the receiving domain is always on)
- A dedicated always-on supply (VDD_AON)
- The parent domain's supply in a hierarchical power architecture

If the isolation cell loses power, it cannot perform its function, and the outputs become undefined -- the exact problem isolation is supposed to prevent.

### UPF Isolation Specification

```tcl
# Define isolation strategy for CPU domain outputs
set_isolation iso_cpu_out \
  -domain PD_CPU \
  -applies_to outputs \
  -clamp_value 0 \
  -isolation_power_net VDD_AON \
  -isolation_ground_net VSS

# Define the control signal and its sense
set_isolation_control iso_cpu_out \
  -domain PD_CPU \
  -isolation_signal pmc_iso_en_cpu \
  -isolation_sense high \
  -location parent

# For signals needing clamp-to-1
set_isolation iso_cpu_rst \
  -domain PD_CPU \
  -applies_to outputs \
  -clamp_value 1 \
  -elements {u_cpu/rst_n_out u_cpu/ack_out} \
  -isolation_power_net VDD_AON \
  -isolation_ground_net VSS
```

### Isolation Timing and Sequencing

The isolation enable signal must be managed with precise timing relative to the power switch control:

**Power-Down Sequence:**
1. Software completes all pending transactions
2. Gate clocks to the domain (to prevent partial operations)
3. Save retention registers (SAVE signal)
4. **Assert isolation enable** (outputs clamp to safe values)
5. Turn off power switches (domain powers down)

**Power-Up Sequence:**
1. Turn on power switches (staged to limit rush current)
2. Wait for supply voltage to stabilize (100us-1ms typical)
3. Assert reset to the domain
4. De-assert reset (logic initializes)
5. Restore retention registers (RESTORE signal)
6. **De-assert isolation enable** (outputs now driven by active logic)
7. Enable clocks
8. Software resumes operation

The key constraint: isolation must be asserted BEFORE power switches turn off, and de-asserted AFTER the domain is fully operational. Violating this causes undefined values to propagate.

### Isolation Verification

```tcl
# Check isolation completeness (Innovus)
check_mv_design -isolation

# Report missing isolation
report_mv_cells -isolation -missing

# Verify isolation control signal connectivity
check_power_intent -isolation_control
```

Common isolation bugs:
- Missing isolation on a signal path (causes X propagation during power-down)
- Wrong clamp value (0 when it should be 1, causes functional failure on wake-up)
- Isolation on feedback loops (can cause deadlock if the isolation value prevents the domain from being powered back on)
- Isolation enable timing violation (de-asserted before domain is ready)

---

## Power Switches (Header and Footer MTCMOS)

### Operating Principle

Power switches are large MOS transistors that connect or disconnect a power supply from a logic domain. When the switch is on, it provides a low-resistance path from the global supply (VDD) to the local supply (virtual VDD, abbreviated VVDD). When off, it disconnects the domain, eliminating all leakage current.

### Header Switches (PMOS)

Header switches use PMOS transistors connected between VDD (source) and VVDD (drain):

```
VDD (global) ──┤ PMOS ├── VVDD (local/virtual)
                │ Gate │
                └──┬───┘
                   │
              SLEEP_B (active low to turn ON)
```

- Gate = 0 (SLEEP_B low): PMOS is ON, VDD connects to VVDD
- Gate = VDD (SLEEP_B high): PMOS is OFF, VVDD floats to ground through leakage

**Advantages of header switches:**
- Ground (VSS) is uninterrupted through the domain, providing a stable reference for all cells
- No ground bounce, which is critical for noise-sensitive circuits
- Better for mixed-signal or clock generation logic where ground integrity matters

**Disadvantages:**
- PMOS mobility is ~2x lower than NMOS, requiring ~2x larger transistors for the same on-resistance
- More area consumed for the same current-carrying capacity
- PMOS switches are slower to turn on/off

### Footer Switches (NMOS)

Footer switches use NMOS transistors connected between VVSS (virtual ground, local) and VSS (global ground):

```
VVSS (local/virtual) ──┤ NMOS ├── VSS (global)
                        │ Gate │
                        └──┬───┘
                           │
                      SLEEP (active high to turn ON)
```

**Advantages of footer switches:**
- NMOS is smaller for the same on-resistance (higher electron mobility)
- Less area, faster switching
- Lower cost per unit of current-carrying capacity

**Disadvantages:**
- Virtual ground introduces ground bounce during switching, degrading noise margins
- Cell delay increases due to the voltage drop across the switch (body effect, source degeneration)
- Not suitable for noise-sensitive analog/mixed-signal blocks

### MTCMOS (Multi-Threshold CMOS) Technology

The power switch transistors use high-Vt (HVT) devices to minimize their own leakage in the off state. The logic within the domain uses standard-Vt (SVT) or low-Vt (LVT) devices for performance. This combination is called MTCMOS:

- **Switch off-state leakage**: HVT PMOS/NMOS leakage is 10-100x lower than SVT equivalent
- **Switch on-state resistance**: HVT devices have higher Vt and thus higher on-resistance; compensated by using larger transistor width
- **Overall benefit**: Total domain leakage in off state is dominated by the switch leakage, which is extremely low

### Power Switch Sizing

The on-resistance of the power switch network must be low enough that the IR drop across it does not cause timing failures. Sizing procedure:

1. **Determine peak current**: From dynamic power analysis, find the peak switching current of the domain: I_peak = P_dynamic_peak / VDD

2. **Set IR drop budget**: Typically 3-5% of VDD. For VDD = 0.9V, that is 27-45mV.

3. **Calculate required total Ron**: Ron_total = V_drop_budget / I_peak. For 30mV drop at 500mA peak: Ron = 60 milliohms.

4. **Determine switch cell Ron**: From the library datasheet, a single power switch cell might have Ron = 2 ohms.

5. **Calculate number of switches**: N = Ron_cell / Ron_total = 2.0 / 0.06 = 33 switches (minimum). Add 20-30% margin: use 40-50 switches.

6. **Distribute switches**: Place uniformly around or across the domain for balanced current distribution.

```tcl
# Power switch specification in UPF
create_power_switch ps_cpu \
  -domain PD_CPU \
  -output_supply_port {vvdd VDD_CPU_SW} \
  -input_supply_port {vdd VDD_CPU} \
  -control_port {sleep pmc_sleep_cpu} \
  -on_state {on_state vdd {!sleep}} \
  -off_state {off_state {}}

# Physical implementation in Innovus
addPowerSwitch -powerDomain PD_CPU \
  -globalSwitchCellName HDRSW_HVT_X8 \
  -column \
  -leftOffset 10 \
  -horizontalPitch 40 \
  -checkerBoard \
  -loopBackAtEnd \
  -enableNetOut ack_chain
```

### Daisy-Chain Power Switch Control

To limit rush current, power switches are connected in a daisy chain where each switch's acknowledge output enables the next switch:

```
SLEEP ──> SW1 ──ack1──> SW2 ──ack2──> SW3 ──ack3──> ... ──ackN──> ALL_ON
```

The daisy chain adds latency to the power-on sequence (each switch adds ~1-5ns), but the total power-on time for 50 switches is only ~50-250ns, which is negligible compared to software wake-up overhead.

### Staged Power-On

For domains with very large decoupling capacitance (e.g., large memory arrays), even daisy-chain may not suffice. Staged power-on uses multiple phases:

**Stage 1 (pre-charge):** Turn on 5-10% of switches. These have high effective Ron, so current is limited. The VVDD rail slowly charges through the high resistance. Duration: ~1-10us.

**Stage 2 (ramp):** Turn on 50% of switches. Lower Ron, faster charging. Duration: ~0.5-2us.

**Stage 3 (full-on):** Turn on remaining switches. VVDD reaches full VDD. Duration: ~0.1-0.5us.

Some foundry libraries provide special "current-limited" switch cells with built-in resistance for Stage 1, and regular switch cells for Stages 2-3.

---

## Rush Current (Inrush Current)

### Physics of Rush Current

When power switches close, the virtual VDD rail (which was at ~0V during off state) must charge to VDD. The charge stored in the domain's decoupling capacitance (both intentional decap cells and intrinsic gate capacitance of all cells) is Q = C * V. The current required is I = C * dV/dt. If all switches close simultaneously, dV/dt is very large, and the transient current can reach tens of amperes.

### Rush Current Problems

1. **Global VDD droop**: The rush current flows through the package and board power delivery, causing a voltage drop (L * dI/dt from package inductance). This droop affects all active domains on the chip, potentially causing timing failures.

2. **Ground bounce**: The return current through VSS creates ground bounce, affecting signal integrity.

3. **Electromigration stress**: The instantaneous current density in power grid wires may exceed EM limits, though EM rules typically apply to average (DC) current, not transient spikes.

4. **Latch-up trigger**: Large transient currents can inject sufficient charge to trigger parasitic thyristors, especially at domain boundaries.

### Rush Current Estimation

I_peak = C_total * VDD / t_rise

Where:
- C_total = total capacitance of the domain (decap + gate cap + wire cap)
- VDD = supply voltage
- t_rise = time for VVDD to reach VDD

Example: C_total = 100nF, VDD = 0.9V, t_rise = 10ns (aggressive)
I_peak = 100e-9 * 0.9 / 10e-9 = 9A

This would likely cause severe VDD droop. With daisy-chain (t_rise = 1us):
I_peak = 100e-9 * 0.9 / 1e-6 = 90mA -- much more manageable.

### Rush Current Mitigation Techniques

1. **Daisy-chain turn-on**: As described above, sequential switch activation
2. **Staged turn-on**: Progressive activation of switch groups
3. **Current-limiting switches**: Switches with built-in series resistance for initial phase
4. **Bleeder resistors**: Weak pull-up to pre-charge VVDD slowly before switch activation
5. **Decap reduction**: Minimize unnecessary decoupling in power-gated domains
6. **Package/board design**: Low-inductance PDN to tolerate higher dI/dt
7. **PMC scheduling**: Avoid powering on multiple domains simultaneously

---

## Power Sequencing

### System-Level Power Sequencing

The order in which supply voltages are applied at the chip level is critical for reliability:

1. **Core supplies before I/O supplies**: Prevents I/O ESD structures from forward-biasing into unpowered core, potentially causing latch-up
2. **Always-on supplies first**: The power management controller must be operational before it can manage other domains
3. **PLL supplies before clock domains**: PLLs need time to lock before clocks are distributed
4. **Memory supplies with retention timing**: SRAM arrays have specific power-up timing requirements

### Domain-Level Power Sequencing

Within the chip, domain power-on/off sequences are managed by the Power Management Controller (PMC). The PMC implements a finite state machine with the following states for each domain:

```
OFF → PRE_ON → RISING → ON_ISO → ON → ACTIVE
ACTIVE → PRE_OFF → ISO → FALLING → OFF
```

State descriptions:
- **OFF**: Power switches open, VVDD at 0V, isolation active
- **PRE_ON**: Preparing to power on, checking dependencies
- **RISING**: Power switches closing in sequence, VVDD ramping
- **ON_ISO**: VVDD stable, isolation still active, reset asserted
- **ON**: Isolation de-asserted, clocks gated, retention restored
- **ACTIVE**: Fully operational

### Power State Table

The power state table defines all legal combinations of domain states and the transitions between them:

```tcl
# UPF power state table
add_power_state PD_TOP \
  -state {ALL_ON \
    -logic_expr {PD_CPU==ON && PD_GPU==ON && PD_MEM==ON && PD_PERIPH==ON}} \
  -state {GPU_OFF \
    -logic_expr {PD_CPU==ON && PD_GPU==OFF && PD_MEM==ON && PD_PERIPH==ON}} \
  -state {GPU_PERIPH_OFF \
    -logic_expr {PD_CPU==ON && PD_GPU==OFF && PD_MEM==ON && PD_PERIPH==OFF}} \
  -state {DEEP_SLEEP \
    -logic_expr {PD_CPU==RET && PD_GPU==OFF && PD_MEM==RET && PD_PERIPH==OFF}} \
  -state {ILLEGAL_1 \
    -logic_expr {PD_GPU==ON && PD_MEM==OFF}} -illegal \
  -state {ILLEGAL_2 \
    -logic_expr {PD_CPU==OFF && PD_GPU==ON}} -illegal
```

Illegal states represent physically dangerous or functionally nonsensical combinations. The PMC must prevent these states from occurring.

---

## Always-On Logic

### What Must Be Always-On

- **Power Management Controller (PMC)**: The sequencing and control logic for power switches, isolation, retention, and reset
- **Wake-up interrupt controller**: Must detect wake-up events (GPIO, timer, debug) while domains are off
- **Isolation cells**: Must drive valid outputs when source domain is off
- **Retention control logic**: Save/restore signal generation
- **Level shifters from gated domains**: Must be powered to drive valid outputs
- **Clock generation for always-on domain**: A simple oscillator or reference clock
- **Brown-out/voltage monitors**: Must detect supply anomalies even during low-power states

### Always-On Cell Library

Foundries provide always-on variants of standard cells. These are physically identical to regular cells but have a separate power pin (VDD_AO) connected to the always-on supply rail:

```
Regular cell:  VDD (switched) ──── cell logic ──── VSS
Always-on:     VDD_AO (unswitched) ── cell logic ──── VSS
```

In the physical design, always-on cells must be placed on rows where the always-on power rail is available. This requires:

1. **AO power stripes**: Dedicated metal stripes carrying VDD_AON within the power-gated domain
2. **AO cell rows**: Standard cell rows connected to VDD_AON instead of VVDD
3. **AO cell clustering**: Group AO cells near AO power stripes to minimize IR drop on the AO supply

### Always-On Routing Challenges

Always-on routing is one of the most challenging aspects of multi-voltage physical design:

- AO power stripes consume routing resources within the power-gated domain
- AO cells create routing blockages if placed in regular rows
- AO supply must have low IR drop (these cells are the most critical -- they must function during all power states)
- AO logic should be minimized (every AO cell adds leakage that cannot be eliminated by power gating)

Best practices:
- Budget 5-10% of the power-gated domain area for AO logic and routing
- Place AO cells along the domain boundary to minimize AO stripe length
- Use dedicated AO rows at the domain periphery
- Run AO supply stripes on upper metal layers to avoid congestion with signal routing

---

## Retention Registers and State Preservation

### Retention Register Architecture

#### Balloon Latch Retention
The most common approach adds a small auxiliary latch (the "balloon") to each flip-flop that needs retention. The balloon is powered by the always-on supply and stores one bit.

```
Normal operation:          Power-down (save):        Power-up (restore):
┌─────────────┐           ┌─────────────┐           ┌─────────────┐
│ Main FF     │──Q──>     │ Main FF     │──SAVE──>  │ Main FF  <──RESTORE──│
│ (VDD_SW)    │           │ (going off) │           │ (VDD_SW)    │
└─────────────┘           └─────────────┘           └─────────────┘
┌─────────────┐           ┌─────────────┐           ┌─────────────┐
│ Balloon     │           │ Balloon     │──stored   │ Balloon     │──>
│ (VDD_AON)   │           │ (VDD_AON)   │  value    │ (VDD_AON)   │
└─────────────┘           └─────────────┘           └─────────────┘
```

- SAVE signal: Transfers FF state to balloon (one clock cycle before power-off)
- RESTORE signal: Transfers balloon state back to FF (one clock cycle after power-on)
- Area overhead: ~30-50% per retention flip-flop
- Power overhead: The balloon latch adds leakage on VDD_AON

#### Master-Retention Flip-Flop
The master latch of the flip-flop is powered by VDD_AON. During power-down, the clock is stopped with the master latch holding valid data. The slave latch (powered by VDD_SW) loses state but the master retains it.

- Advantages: No separate save/restore signals needed, smaller area
- Disadvantages: Clock must stop in the correct phase, less flexible timing

### UPF Retention Specification

```tcl
set_retention ret_cpu \
  -domain PD_CPU \
  -retention_power_net VDD_RET \
  -retention_ground_net VSS \
  -elements {u_cpu/reg_bank/* u_cpu/config_regs/*}

set_retention_control ret_cpu \
  -domain PD_CPU \
  -save_signal {pmc_save_cpu high} \
  -restore_signal {pmc_restore_cpu low} \
  -assert_count 2  ;# save pulse must be 2 cycles wide
```

### Selective Retention

Not every register needs retention. Registers that are re-initialized by the power-on reset sequence (pipeline registers, temporary buffers) do not need retention. Only registers whose state is not easily reconstructable should be retained:

- Configuration registers (programmed by software, costly to reprogram)
- FSM state registers (needed to resume operation)
- Counters and timers (if time continuity is required)
- Security registers (keys, permissions)

Selective retention significantly reduces the number of retention flip-flops, saving area and always-on leakage.

---

## EDA Tool Implementation

### Synopsys Fusion Compiler / Design Compiler

```tcl
# Read UPF power intent
load_upf design.upf

# Map physical cells
set_isolation_cell -domain PD_CPU \
  -lib_cells {ISO_CLAMP0_LVT_X1 ISO_CLAMP1_LVT_X1}
set_level_shifter_cell -domain PD_CPU \
  -lib_cells {LSLH_X1 LSHL_X1}
set_retention_cell -domain PD_CPU \
  -lib_cells {DFFRTN_X1}

# Synthesize with multi-voltage awareness
compile_ultra -gate_clock -scan

# Verify MV design
check_mv_design
report_mv_cells -all
```

### Cadence Innovus Implementation

```tcl
# Read and commit power intent
read_power_intent design.upf
commit_power_intent

# Verify power intent
check_power_intent -verbose

# Add power switches
addPowerSwitch -column -powerDomain PD_CPU \
  -globalSwitchCellName HDRSW_HVT_X8 \
  -leftOffset 5 -horizontalPitch 30 \
  -checkerBoard -loopBackAtEnd

# Insert isolation cells
addIsolationCell -powerDomain PD_CPU
verifyIsolationCell -powerDomain PD_CPU

# Insert level shifters
addLevelShifterCell -powerDomain PD_CPU
verifyLevelShifterCell -powerDomain PD_CPU

# Route power for AO cells
sroute -connect {blockPin padPin padRing corePin} \
  -layerChangeRange {M1 M4} \
  -allowJogging 1 \
  -nets {VDD_AON VSS}
```

### Verification Commands

```tcl
# Comprehensive MV design check
check_mv_design -isolation
check_mv_design -level_shifter
check_mv_design -power_switch
check_mv_design -retention

# Report all MV cells
report_mv_cells -isolation -verbose
report_mv_cells -level_shifter -verbose
report_mv_cells -power_switch -verbose
report_mv_cells -retention -verbose

# Check power domain connectivity
verify_power_domain -all

# Check for missing always-on connections
check_mv_design -always_on_logic
```

---

## Troubleshooting Multi-Voltage Designs

### Common Issues and Solutions

**Missing level shifters**: Signal crosses voltage boundary without LS. Run `check_mv_design -level_shifter` and review the UPF `-applies_to` and `-rule` settings. Ensure the voltage threshold is not set too high.

**Wrong level shifter direction**: LH shifter used where HL is needed, or vice versa. Verify the voltage values of source and destination domains for each crossing.

**Isolation clamp value mismatch**: The clamp value does not match the receiving logic's safe default. Verify against the functional specification. Common mistake: clamping a request signal to 1 instead of 0, causing spurious transactions on wake-up.

**Isolation before retention save**: If isolation activates before the SAVE signal, the balloon latches capture the isolated (clamped) value instead of the true state. Verify PMC sequencing in simulation.

**Power switch IR drop**: Virtual VDD drops too much under peak current, causing timing failures that appear only under high activity. Run dynamic IR drop analysis with realistic switching activity vectors.

**Always-on routing congestion**: AO stripes and AO cell placement compete with signal routing, causing congestion. Plan AO routing early, reserve metal layers, and cluster AO cells.

**Retention voltage too low**: If VDD_RET drops below the minimum data retention voltage of the balloon latch (specified in the cell characterization), state is corrupted. Verify across all PVT corners.

**Rush current exceeding package limits**: Power-on sequence too fast for the package PDN to handle. Increase daisy-chain length, add current limiting, or stagger domain wake-ups.

### Expert Tips

- Define the UPF power intent at the architecture phase, before RTL coding begins. Retrofitting multi-voltage after synthesis is extremely costly.
- Use UPF-aware simulation from the RTL phase to catch power intent bugs before physical implementation.
- Budget 10-20% area overhead for multi-voltage infrastructure (isolation cells, level shifters, power switches, AO logic, retention latches).
- Use combined ISO-LS cells wherever possible to save area and reduce delay.
- Model the power switch on-resistance as an additional IR drop in timing analysis.
- For DVFS domains, ensure all operating points are timed with the correct library corners and operating conditions.
- Keep always-on logic to an absolute minimum because it directly adds to the leakage floor.
- Verify the complete power state table in UPF, marking illegal states explicitly.
- Run power-aware gate-level simulation with UPF to verify isolation, retention, and corruption semantics end-to-end.
- Consider voltage regulator efficiency when calculating total system power: an 85%-efficient LDO dissipates 15% of the domain's power as heat.
- Use physical-aware synthesis to estimate level shifter and isolation cell placement early, before detailed P&R.
- Review foundry-specific level shifter and isolation cell offerings, as performance varies significantly between foundry libraries.
