# Noise Signoff: Glitch Analysis, Noise Propagation, and Signal Integrity Verification

## Overview

Noise signoff verifies that crosstalk-induced noise does not cause functional failures in the design. As wire spacing decreases at advanced nodes, coupling capacitance between adjacent wires increases, making crosstalk noise a significant concern. Noise signoff encompasses glitch analysis, noise propagation checking, functional noise verification, bump analysis, and noise immunity ratio assessment. PD engineers must ensure that no noise event can corrupt data or trigger false switching in the design.

## Glitch Analysis

A glitch is a transient voltage spike on a victim net caused by capacitive coupling from one or more switching aggressor nets. Glitches are dangerous because they can propagate through combinational logic and be captured by flip-flops, causing functional errors.

### Glitch Characterization

A glitch is characterized by three parameters:

- **Peak voltage (Vpeak)**: The maximum voltage deviation from the stable state. A larger peak is more likely to trigger a false transition in downstream logic.
- **Width (Twidth)**: The duration of the glitch. Wider glitches are more likely to propagate through multiple stages of logic.
- **Area (V * T)**: The integral of voltage over time. This combined metric captures the energy of the glitch.

### How Glitches Occur

When an aggressor wire switches (e.g., rising transition), the coupling capacitance between the aggressor and victim injects charge onto the victim. If the victim is stable (not switching), this charge creates a voltage bump (glitch):

```
V_glitch approximately equal to (Cc / (Cc + Cv + Cg)) * V_swing * f(timing)

Where:
Cc = coupling capacitance between aggressor and victim
Cv = victim net total capacitance to ground
Cg = gate capacitance of victim receivers
V_swing = aggressor switching voltage (approximately VDD)
f(timing) = timing alignment factor
```

The worst case occurs when multiple aggressors on both sides of the victim switch simultaneously in the same direction.

### Glitch Analysis Tools

Signoff noise analysis is performed by:
- **Synopsys PrimeTime SI**: Computes glitch height and width at every net in the design.
- **Cadence Tempus**: Integrated SI and noise analysis.
- **Synopsys StarRC**: Extracts coupling capacitances needed for noise analysis.
- **Cadence Quantus**: Extraction with coupling.

```tcl
# PrimeTime SI glitch analysis:
set si_enable_analysis true
set si_noise_analysis true
report_noise -above -threshold 0.3  ;# Report glitches above 30% of VDD
report_noise -all_violators
```

## Noise Propagation

Not all glitches cause functional failures. A glitch must propagate through combinational logic and arrive at a sequential element's data input during the capture window to cause corruption. Noise propagation analysis determines whether a glitch at a specific point can actually reach and corrupt a flip-flop.

### Propagation Attenuation

As a glitch propagates through logic gates, it is attenuated:

- **Gain attenuation**: Each gate has a noise transfer function. Small glitches below the gate's switching threshold are suppressed. The gate's DC gain at the operating point determines how much the glitch is amplified or attenuated.
- **RC filtering**: Wire RC and gate input capacitance create a low-pass filter that attenuates narrow (high-frequency) glitches.
- **Logic masking**: If a gate has multiple inputs, a glitch on one input may not affect the output if other inputs hold the output at a fixed value (e.g., a glitch on one input of an AND gate when another input is 0).
- **Timing masking**: A glitch arriving at a flip-flop outside the setup/hold window does not cause corruption.

### Propagation Analysis Methodology

Advanced tools perform multi-stage noise propagation:

1. Compute the glitch at the first victim net.
2. Propagate the glitch through each combinational gate, applying the gate's noise transfer function.
3. Check if the attenuated glitch at the flip-flop data pin exceeds the noise immunity threshold during the capture window.
4. Flag nets where the propagated glitch violates the threshold.

## Functional Noise

Functional noise analysis considers the logical state of the design when determining aggressor activity. Not all aggressors can switch at the same time; functional constraints limit simultaneous switching.

### Static vs. Functional Noise Analysis

**Static noise analysis**: Assumes all possible aggressors switch simultaneously in the worst-case direction. This is pessimistic but conservative.

**Functional noise analysis**: Uses logic constraints (derived from RTL simulation or formal analysis) to determine which aggressors can realistically switch simultaneously. This reduces pessimism but requires additional setup.

```tcl
# PrimeTime SI functional noise:
# Provide timing windows and logic constraints
set si_filter_per_aggressor true
set si_aggressor_filtering_enable true
# Use SAIF or toggle information to bound aggressor activity
```

### Noise-Aware Timing

Crosstalk affects not only noise (glitches) but also timing (delay change). Noise-aware timing analysis (SI timing) accounts for both:

- **Delay increase**: Aggressors switching opposite to the victim slow the victim transition (setup-critical).
- **Delay decrease**: Aggressors switching in the same direction as the victim speed up the transition (hold-critical).
- **Effective capacitance change**: Coupling capacitance appears as 0x Cground (same-direction switching) to 2x Cground (opposite-direction switching), known as the Miller coupling factor.

## Bump Analysis

Bump analysis (or noise bump analysis) quantifies the worst-case voltage deviation at each net in the design, considering all aggressors.

### Methodology

1. For each victim net, identify all coupled aggressors.
2. Compute the individual noise contribution from each aggressor.
3. Determine the worst-case alignment of aggressor transitions (superposition).
4. Compute the total noise bump (peak voltage deviation).
5. Compare against the noise immunity threshold.

### Bump Categories

- **Rise bump**: Glitch in the positive direction on a low-stable net. Can cause a false logic-1.
- **Fall bump**: Glitch in the negative direction on a high-stable net. Can cause a false logic-0.
- **Overshoot/undershoot**: Glitch that drives the net above VDD or below VSS. Besides functional risk, this can cause reliability issues (oxide stress, latch-up trigger).

## Noise Immunity Ratio

The Noise Immunity Ratio (NIR) quantifies how much margin exists between the actual noise and the maximum tolerable noise.

### Definition

```
NIR = V_noise / V_immunity

Where:
V_noise = peak noise voltage at the victim
V_immunity = maximum tolerable noise voltage (gate switching threshold)
```

- **NIR < 1.0**: The noise is below the immunity threshold. The net passes.
- **NIR >= 1.0**: The noise exceeds the immunity threshold. The net fails and must be fixed.
- **NIR margin**: Teams typically target NIR < 0.7-0.8 to provide design margin.

### Factors Affecting Noise Immunity

- **Gate type**: Inverters and buffers have the highest noise immunity (symmetric transfer curve). Complex gates (NAND, NOR, MUX) have asymmetric immunity.
- **Drive strength**: Stronger drivers on the victim net reduce noise (lower output impedance provides a discharge path).
- **Fanout**: Higher fanout increases victim capacitance, which helps absorb noise.
- **Input threshold**: Standard cells with Schmitt trigger inputs have higher noise immunity.

## Noise Fixing Techniques

When noise violations are identified, PD engineers have several fixing strategies:

### Routing Fixes

1. **Increase spacing**: Route the victim and aggressor with larger spacing (double-spacing NDR).
2. **Shield wires**: Insert grounded shield wires between the victim and aggressor (used for critical signals like clocks and analog signals).
3. **Layer change**: Move the victim to a different routing layer where it has fewer aggressors.
4. **Shorter parallel runs**: Reroute to reduce the parallel coupling length between victim and aggressor.

### Cell-Level Fixes

5. **Upsizing victim driver**: A stronger driver reduces the effective noise at the victim.
6. **Buffer insertion**: Insert a buffer on the victim net to segment the coupling and restore signal integrity.
7. **Decoupling**: Add decap cells near the victim to provide local charge support.

### Design-Level Fixes

8. **Net ordering**: During detailed routing, route sensitive nets (clocks, resets) before general signals to give them preferred tracks.
9. **NDR rules**: Apply non-default routing rules (wider spacing, wider wires) to critical nets.

```tcl
# Apply shielding to clock nets in ICC2/FC:
set_routing_rule clock_nets -min_spacing 0.08 -shield {VSS}

# Apply double-spacing NDR in Innovus:
create_route_rule double_space -spacing {M2 0.08 M3 0.08}
set_net_routing_rule -rule double_space -nets {clk_main}
```

## Noise Signoff Criteria

| Check | Criterion |
|---|---|
| Glitch peak voltage | Below noise immunity threshold at all sequential inputs |
| Noise propagation | No propagated glitch exceeds capture threshold |
| NIR | < 0.8 (with margin) at all nets |
| SI timing (setup) | No setup violations with SI delays |
| SI timing (hold) | No hold violations with SI delays |
| Overshoot/undershoot | No net exceeds VDD + 10% or VSS - 10% |

## Noise Signoff Flow

1. Extract parasitics with coupling capacitances (StarRC/Quantus with coupling extraction).
2. Run SI timing analysis (PrimeTime SI / Tempus) for all MMMC corners.
3. Run glitch/noise analysis for critical modes.
4. Fix timing violations caused by SI effects (reroute, upsize, buffer).
5. Fix noise/glitch violations (reroute, shield, NDR).
6. Re-extract and re-analyze until clean.
7. Verify that noise fixes did not introduce new timing violations.

## Common Pitfalls

- Not extracting coupling capacitances (using grounded capacitance only) leads to missing all SI effects.
- Ignoring noise on clock nets (a glitch on a clock can cause setup/hold violations everywhere).
- Fixing timing SI but forgetting noise/glitch checks.
- Over-shielding (consuming excessive routing resources and increasing capacitance).
- Not re-running noise analysis after ECO changes.

Noise signoff is critical for first-silicon success at advanced nodes where coupling capacitance dominates. PD engineers must treat noise as a first-class signoff criterion alongside timing, power, and physical verification.
