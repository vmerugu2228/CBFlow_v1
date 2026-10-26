# Timing Signoff: Corner Matrix, Margins, and Signoff Criteria

## Overview

Timing signoff is the process of verifying that a design meets all timing requirements across all operating conditions before tapeout. It is arguably the most critical signoff step because timing violations directly cause functional failure. Timing signoff involves defining the corner matrix, establishing margin budgets, configuring on-chip variation (OCV) settings, running signal integrity (SI) analysis, and applying signoff criteria. PD engineers must master these concepts to deliver silicon that works at speed.

## Corner Matrix

A timing corner defines a specific combination of process, voltage, and temperature (PVT) conditions under which timing analysis is performed. The corner matrix is the set of all PVT combinations that must be analyzed.

### Process Corners

Process variation causes transistor and interconnect parameters to vary across the wafer and between manufacturing lots. Standard process corners include:

- **SS (Slow-Slow)**: Both NMOS and PMOS are slow. Worst case for setup timing.
- **FF (Fast-Fast)**: Both NMOS and PMOS are fast. Worst case for hold timing.
- **TT (Typical-Typical)**: Nominal process conditions. Used for power estimation.
- **SF (Slow-Fast)**: NMOS slow, PMOS fast. Skewed corner for specific circuit topologies.
- **FS (Fast-Slow)**: NMOS fast, PMOS slow. Complementary skew corner.
- **SSG (Slow-Slow Global)**: A tighter slow corner used for signoff, more realistic than SS.

### Voltage Corners

Operating voltage varies due to on-chip IR drop and supply regulation tolerance.

- **Nominal**: The target operating voltage (e.g., 0.85V).
- **Nominal - IR drop**: The minimum voltage at the standard cell after IR drop (e.g., 0.80V).
- **Maximum**: Maximum voltage under overshoot conditions (e.g., 0.95V).
- **DVFS voltages**: Each DVFS operating point is a separate voltage corner.

### Temperature Corners

Temperature affects both transistor speed and wire resistance.

- **High temperature**: Typically 125C (commercial), 150C (automotive). Worst case for setup at higher voltages.
- **Low temperature**: Typically -40C (commercial/industrial), 0C (mobile). Worst case for hold and potentially setup at low voltage (temperature inversion).
- **Typical**: 25C. Used for nominal analysis.

### Example Corner Matrix

| Corner Name | Process | Voltage | Temperature | Primary Use |
|---|---|---|---|---|
| ss_0p75v_125c | SS | 0.75V | 125C | Setup (worst case) |
| ss_0p75v_m40c | SS | 0.75V | -40C | Setup (temp inversion) |
| ff_0p95v_m40c | FF | 0.95V | -40C | Hold (worst case) |
| ff_0p95v_125c | FF | 0.95V | 125C | Hold (alternate) |
| tt_0p85v_25c | TT | 0.85V | 25C | Power estimation |
| ss_0p65v_125c | SS | 0.65V | 125C | Setup (low DVFS point) |

A modern SoC may have 20-40 signoff corners when considering multiple voltage domains, DVFS operating points, and process options.

## Mode Coverage

A timing mode defines a specific functional configuration of the design (e.g., functional mode, test mode, scan mode, JTAG mode). Each mode may have different clock frequencies, different active blocks, and different timing constraints.

### Common Modes

- **Functional mode**: Normal operating mode with full-speed clocks.
- **Scan shift mode**: Scan chain shift operation at reduced frequency.
- **Scan capture mode**: Capture clock at or near full speed.
- **JTAG/boundary scan mode**: JTAG TAP controller operating at TCK frequency.
- **MBIST mode**: Memory built-in self-test, typically at reduced frequency.
- **Low-power mode**: Reduced frequency/voltage operating mode.

### Mode-Corner Combinations

Each mode must be analyzed at relevant corners. The total analysis space is modes x corners. To manage this:

- Not every mode needs every corner (e.g., scan shift at reduced frequency may only need 2-3 corners).
- Functional mode at maximum frequency needs the most corners.
- Tools support multi-mode multi-corner (MMMC) analysis to efficiently handle the full matrix.

## Margin Budgeting

Timing margins account for uncertainties not captured by the PVT corners and library characterization. The total margin is the sum of individual margin components.

### Margin Components

1. **OCV margin**: On-chip variation (see next section). Accounts for local process variation between cells on the same chip.
2. **SI margin**: Signal integrity penalty for crosstalk-induced delay change (see SI section below).
3. **Library margin**: Additional margin for library characterization uncertainty (typically 2-5%).
4. **Extraction margin**: Uncertainty in parasitic extraction (RC correlation to silicon). Typically 5-10% for pre-silicon, 2-5% post-silicon correlation.
5. **Clock uncertainty**: Jitter, clock network skew uncertainty, PLL uncertainty.
6. **Aging margin**: Margin for NBTI/PBTI/HCI degradation over product lifetime (5-10%).

### Total Margin Budget

A well-managed timing closure effort tracks the total margin budget:

```
Total setup margin = OCV_margin + SI_margin + library_margin + extraction_margin + aging_margin
Example: 5% + 3% + 3% + 5% + 5% = 21% total margin

This means the design effectively operates at ~79% of the nominal cell speed.
```

Reducing margins (through better analysis accuracy, silicon correlation, etc.) directly improves achievable frequency or reduces area/power.

## OCV Settings

On-Chip Variation (OCV) models the fact that cells on the same chip, at the same PVT corner, still have slightly different delays due to local process variation (random dopant fluctuation, line-edge roughness, etc.).

### OCV Methodologies

**Flat OCV (FOCV)**: A single derating factor applied to all cells uniformly. Pessimistic because it assumes worst-case variation on every cell simultaneously.

```
# Example: 5% setup derate, 3% hold derate
set_timing_derate -late -cell_delay 1.05
set_timing_derate -early -cell_delay 0.97
```

**Advanced OCV (AOCV)**: Depth-dependent derating. Cells deeper in the logic path have smaller derating because variation averages out over many stages. AOCV uses a table of derating factors indexed by path depth and cell distance.

```
# AOCV table specifies derate vs. depth:
# Depth 1: 1.08 (large variation for single cell)
# Depth 5: 1.04
# Depth 10: 1.02
# Depth 20: 1.01 (variation averages out)
```

**Parametric OCV (POCV)**: The most accurate OCV methodology. POCV uses a statistical model (mean and sigma) for each cell's delay, computing path delay as a statistical distribution rather than a deterministic derate.

```
# POCV uses Liberty Variation Format (LVF) libraries
# Each cell has:
#   - Nominal delay
#   - Sigma (random variation)
#   - Systematic variation component
# Path delay = sum of means +/- sqrt(sum of sigma^2)
```

**POCV advantages over AOCV**:
- Less pessimistic (5-10% better timing margin).
- Accounts for cell-specific variation (different cells have different sigma).
- Distance-aware (nearby cells correlate, far cells are independent).

### Recommended Practice

For signoff, POCV is the preferred methodology at advanced nodes (7nm and below). AOCV is acceptable at 16nm and above. Flat OCV should only be used for quick estimates, not signoff.

## Signal Integrity (SI) Analysis

Crosstalk between adjacent wires causes timing changes (delay increase or decrease) and potential glitches. SI analysis is integral to timing signoff.

### SI Analysis Settings

```tcl
# PrimeTime SI settings:
set_app_options -name si.enable_analysis -value true
set_app_options -name si.enable_delay_analysis -value true
set_app_options -name si.enable_glitch_analysis -value true

# Aggressor alignment: how many aggressors switch simultaneously
set_app_options -name si.aggressor_alignment_mode -value pessimistic
```

### Crosstalk Delay Impact

- **Setup worsening**: Aggressors switching in the opposite direction slow down the victim, increasing data path delay.
- **Hold worsening**: Aggressors switching in the same direction speed up the victim, decreasing data path delay.
- Typical SI impact: 5-15% of total path delay at advanced nodes.

### SI Signoff Criteria

- All setup and hold checks must pass with SI effects included.
- No functional glitches: Crosstalk-induced glitches must not propagate to sequential elements or memory inputs.
- Noise immunity: The peak glitch voltage at any gate input must not exceed the noise immunity threshold.

## Signoff Criteria

### Standard Signoff Requirements

| Check | Criterion |
|---|---|
| Setup (WNS) | >= 0ps (no negative slack) |
| Setup (TNS) | >= 0ps (no total negative slack) |
| Hold (WNS) | >= 0ps |
| Hold (TNS) | >= 0ps |
| Max transition | No violations > limit (typically 0.3-0.5ns) |
| Max capacitance | No violations > limit |
| Max fanout | No violations > limit |
| Clock skew | Within budget |
| SI glitch | No functional glitches |

### Timing Signoff Checklist

1. All MMMC corners analyzed with correct libraries and constraints.
2. POCV/AOCV enabled with correct derating files.
3. SI analysis enabled with extracted coupling capacitances.
4. Clock uncertainty includes PLL jitter and network uncertainty.
5. All IO timing (input/output delays) correctly constrained.
6. All false paths and multicycle paths reviewed and approved.
7. All generated clocks verified for correctness.
8. No unconstrained endpoints.
9. WNS = 0, TNS = 0 across all corners and modes.
10. Formal equivalence check (LEC) passes between the signoff netlist and the RTL.

## Signoff Tool Flow

The standard signoff timing tool is Synopsys PrimeTime (PT) or Cadence Tempus. These are independent of the P&R tool and provide golden timing results.

```tcl
# PrimeTime signoff flow outline:
read_verilog final_netlist.v
read_parasitics final.spef
read_sdc constraints.sdc
set_pvt -process ss -voltage 0.75 -temperature 125
update_timing
report_timing -max_paths 100 -slack_lesser_than 0
report_constraint -all_violators
```

Timing signoff is the gatekeeper for tapeout. A design with timing violations will fail in silicon. PD engineers must rigorously define the corner matrix, apply appropriate margins, and verify every corner and mode before clearing the design for manufacturing.
