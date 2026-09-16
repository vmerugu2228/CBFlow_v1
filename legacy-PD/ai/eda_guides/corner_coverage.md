# Corner Coverage: PVT Selection, Extraction Corners, and Signoff Matrix

## Overview

Corner coverage is the discipline of selecting the right set of Process, Voltage, and Temperature (PVT) combinations to ensure timing, power, and reliability signoff captures all real-world operating conditions. Insufficient corner coverage results in silicon that fails under certain conditions; excessive corner coverage wastes computational resources and slows the design schedule. PD engineers must understand how to construct an efficient yet comprehensive signoff matrix.

## Process Corners

### What Process Variation Means

Semiconductor manufacturing introduces variation in transistor and interconnect parameters. These variations are classified as:

- **Global (inter-die) variation**: Affects all transistors on a die uniformly. Caused by wafer-to-wafer and lot-to-lot differences in implant dose, oxide thickness, and etch depth. Modeled by process corners (SS, FF, TT, SF, FS).
- **Local (intra-die) variation**: Affects transistors differently within the same die. Caused by random dopant fluctuation, line-edge roughness, and local stress. Modeled by OCV/AOCV/POCV derating.

### Standard Process Corners

| Corner | NMOS | PMOS | Description |
|---|---|---|---|
| TT | Typical | Typical | Nominal; used for power estimation and initial timing |
| SS | Slow | Slow | Worst setup; both transistor types are slow |
| FF | Fast | Fast | Worst hold; both transistor types are fast |
| SF | Slow | Fast | NMOS slow, PMOS fast; skew corner |
| FS | Fast | Slow | NMOS fast, PMOS slow; skew corner |
| SSG | Slow global | Slow global | More realistic slow corner (tighter than SS) |
| FFG | Fast global | Fast global | More realistic fast corner (tighter than FF) |

### When Skew Corners Matter

SF and FS corners are important for circuits where NMOS and PMOS contribute differently to the critical path:
- Circuits with asymmetric pull-up/pull-down (e.g., dynamic logic, sense amplifiers).
- Level shifters and I/O circuits where NMOS and PMOS have different roles.
- Clock inverter chains where skew between rise and fall times matters.

For standard digital logic with balanced CMOS gates, SS and FF dominate. Skew corners are checked but rarely limit timing.

## Voltage Corners

### Voltage Variation Sources

The supply voltage at a transistor differs from the external supply due to:
- **Package IR drop**: Voltage drop across package bumps, traces, and planes (10-30mV).
- **On-chip IR drop**: Voltage drop across the on-chip power grid (20-50mV).
- **Regulator tolerance**: Voltage regulator output accuracy (typically +/-3-5%).
- **DVFS operating points**: Deliberately different voltages for different performance modes.

### Voltage Corner Selection

For each power domain, define:

| Voltage Corner | Value | Use |
|---|---|---|
| V_max | Nominal + regulator tolerance + overshoot | Worst hold, EM, reliability |
| V_nom | Nominal operating voltage | Power estimation |
| V_min | Nominal - regulator tolerance - IR drop | Worst setup |
| V_dvfs_low | Lowest DVFS operating point | Setup at low voltage |

Example for a 0.85V nominal design:
- V_max = 0.935V (0.85V + 5% + 5% overshoot)
- V_nom = 0.85V
- V_min = 0.765V (0.85V - 5% - 5% IR drop)
- V_dvfs_low = 0.65V

## Temperature Corners

### Temperature Variation

The junction temperature varies based on:
- **Ambient temperature**: Environmental conditions (commercial: 0-70C, industrial: -40-85C, automotive: -40-150C).
- **Self-heating**: The chip's own power dissipation raises junction temperature above ambient.
- **Local hotspots**: Regions with high power density can be 10-20C above the die average.

### Temperature Corner Selection

| Temperature Corner | Value | Use |
|---|---|---|
| T_high | Maximum Tj (e.g., 125C) | Worst case for setup (at high V), EM, leakage |
| T_low | Minimum Tj (e.g., -40C) | Worst case for hold, setup at low V (inversion) |
| T_nom | Typical (25C) | Power estimation |

### Temperature Inversion

At advanced nodes (below 16nm), temperature inversion occurs at low voltages: transistors become faster at high temperature because Vth reduction dominates over mobility degradation. This means:

- **At high voltage (>0.75V)**: High temperature is slow, low temperature is fast (traditional behavior).
- **At low voltage (<0.65V)**: Low temperature is slow, high temperature is fast (inverted behavior).
- **Crossover voltage**: Between 0.65V and 0.75V, the relationship transitions.

This has critical implications for corner selection:
- Setup-critical analysis at low DVFS voltages must include the LOW temperature corner.
- The traditional assumption that "slow = hot" does not hold universally at advanced nodes.

## Setup-Critical vs. Hold-Critical Corners

### Setup-Critical Corners

Setup timing requires the data to arrive before the clock edge. The worst case for setup is when:
- Data path is slow (high delay).
- Clock path is fast (early clock arrival at the capture flop).

Setup-critical corners:
- **Process**: SS or SSG (slow transistors, high wire resistance).
- **Voltage**: V_min (slow transistors, high wire resistance per unit current).
- **Temperature**: T_high at high voltage, T_low at low voltage (temperature inversion).

### Hold-Critical Corners

Hold timing requires the data to remain stable after the clock edge. The worst case for hold is when:
- Data path is fast (data changes too quickly after the clock).
- Clock path is slow (late clock arrival at the capture flop).

Hold-critical corners:
- **Process**: FF or FFG (fast transistors, low wire resistance).
- **Voltage**: V_max (fast transistors).
- **Temperature**: T_low at high voltage, T_high at low voltage (temperature inversion).

### Corner Assignment Table

| Corner Name | Process | Voltage | Temperature | Primary Check |
|---|---|---|---|---|
| func_ss_minv_hot | SS | V_min | 125C | Setup |
| func_ss_minv_cold | SS | V_min | -40C | Setup (inversion) |
| func_ff_maxv_cold | FF | V_max | -40C | Hold |
| func_ff_maxv_hot | FF | V_max | 125C | Hold (inversion) |
| func_tt_nom_nom | TT | V_nom | 25C | Power estimation |
| dvfs_ss_lowv_cold | SS | V_dvfs_low | -40C | Setup (low DVFS) |
| dvfs_ff_lowv_hot | FF | V_dvfs_low | 125C | Hold (low DVFS) |

## Extraction Corners

Parasitic extraction (RC extraction) also has corners that model interconnect variation.

### Extraction Corner Types

- **Cmax (RCmax)**: Maximum capacitance, maximum resistance. Worst case for delay.
- **Cmin (RCmin)**: Minimum capacitance, minimum resistance. Worst case for hold and noise.
- **Cbest (RCbest)**: Minimum capacitance, minimum resistance (same as Cmin for most extractors).
- **Cworst (RCworst)**: Maximum capacitance, maximum resistance (same as Cmax).
- **Rc_typ**: Typical RC extraction. Used for power estimation.

### Advanced Extraction Corners

At advanced nodes, extraction corners decouple resistance and capacitance variation:

| Corner | Resistance | Capacitance | Use |
|---|---|---|---|
| RCmax | Max | Max | Worst delay (setup) |
| RCmin | Min | Min | Least delay (hold) |
| RCmax_Cmin | Max R | Min C | Worst RC delay, optimistic coupling |
| RCmin_Cmax | Min R | Max C | Worst coupling, optimistic RC delay |

The RCmin_Cmax corner is particularly important for SI (signal integrity) analysis because it maximizes the coupling-to-ground capacitance ratio.

### Extraction Corner Pairing

Each timing corner uses a specific extraction corner:

| Timing Corner | Extraction Corner | Rationale |
|---|---|---|
| Setup (slow) | RCmax or RCworst | Maximum delay |
| Hold (fast) | RCmin or RCbest | Minimum delay |
| SI/Noise | RCmin_Cmax | Maximum coupling ratio |
| Power | RC_typ | Typical conditions |

## Signoff Matrix Construction

### Building the Full Matrix

The signoff matrix is the cross-product of:
- Timing modes (functional, scan, JTAG, etc.)
- Process corners (SS, FF, TT, SF, FS)
- Voltage corners (per domain: Vmin, Vnom, Vmax, DVFS points)
- Temperature corners (Tmin, Tnom, Tmax)
- Extraction corners (RCmax, RCmin, RC_typ)

### Matrix Reduction

The full cross-product would be enormous. Practical reduction techniques:

1. **Eliminate redundant corners**: Not every mode needs every PVT. Scan shift mode at reduced frequency only needs 2-3 corners.
2. **Merge symmetric corners**: If SF and FS never limit timing, they can be dropped after initial verification.
3. **Mode-corner mapping**: Map each mode to only its relevant corners (setup-critical modes get slow corners, hold-critical modes get fast corners).
4. **Risk-based prioritization**: Analyze the most critical mode-corner combinations first. Add additional corners only if silicon data reveals coverage gaps.

### Example Signoff Matrix for a DVFS Design

A design with 2 voltage domains, 3 DVFS points, and 3 modes might have:

```
Modes: functional, scan_shift, scan_capture (3 modes)
Process: SS, FF, TT (3 process corners)
Voltage: Vmin, Vnom, Vmax x 3 DVFS points (up to 9 voltage settings)
Temperature: -40C, 25C, 125C (3 temperatures)
Extraction: RCmax, RCmin, RC_typ (3 extraction corners)

Full cross-product: 3 x 3 x 9 x 3 x 3 = 729 corners
After reduction: typically 25-50 signoff corners
```

## Validating Corner Coverage

### Post-Silicon Correlation

After silicon arrives, measure timing at multiple PVT conditions to verify:
- The timing model (library + extraction) matches silicon within the expected accuracy (typically +/-5-10%).
- No unexpected failures at conditions not covered by the signoff matrix.
- Temperature inversion behavior matches predictions.

### Shmoo Plots

Shmoo plots map pass/fail across voltage and frequency space. They reveal:
- The operating envelope of the chip.
- Whether the signoff corners correctly bound the operating space.
- Corner gaps where failures occur at unexpected PVT combinations.

## Common Pitfalls

- Not including temperature inversion corners at low voltage (missing setup failures at cold temperature).
- Using only RCmax for all timing analysis (missing hold violations that only appear at RCmin).
- Forgetting to add extraction corners for SI analysis (using ground-only extraction for noise checks).
- Over-reducing the corner matrix and missing a failure mode.
- Not correlating signoff corners with silicon data from previous tapeouts.

A well-constructed signoff matrix is the foundation of timing closure. PD engineers must understand the physics driving each corner and judiciously select corners that provide complete coverage without unnecessary computational overhead.
