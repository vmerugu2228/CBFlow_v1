# Gate-Level Simulation

## Overview

Gate-level simulation (GLS) verifies the design after synthesis and/or place-and-route by simulating the netlist of standard cells rather than the original RTL. GLS serves multiple purposes: confirming that synthesis produced a functionally correct netlist, validating timing behavior with back-annotated delays, detecting X-propagation issues caused by uninitialized registers, and verifying the correct insertion of DFT logic. While GLS is significantly slower than RTL simulation (10-100x), it provides verification at the implementation level that cannot be achieved through RTL simulation alone.

## GLS Objectives

### Synthesis Verification

GLS verifies that the synthesis tool correctly translated RTL into a gate-level netlist:
- Logical equivalence between RTL and gates (complementing formal equivalence checking).
- Correct mapping of RTL constructs to standard cells.
- Proper handling of clock gating, operand isolation, and other synthesis optimizations.

### Timing Verification

With SDF (Standard Delay Format) back-annotation, GLS verifies that the design meets timing under realistic delay conditions:
- Setup and hold time violations.
- Clock-to-output delays.
- Recovery and removal times for asynchronous signals.
- Pulse width violations.

### X-Propagation Detection

GLS with gate-level models exposes uninitialized register issues:
- Registers without reset may have X values after power-on.
- X values propagating through combinational logic can mask or create bugs.
- Gate-level X-propagation behavior may differ from RTL behavior due to technology-specific cell behavior.

### DFT Verification

GLS verifies DFT (Design for Test) insertions:
- Scan chain connectivity and ordering.
- BIST (Built-In Self-Test) logic operation.
- JTAG TAP controller functionality.
- Test mode isolation from functional mode.

## SDF Back-Annotation

### SDF File Structure

SDF (Standard Delay Format, IEEE 1497) specifies delays for all paths in the gate-level netlist:

```sdf
(DELAYFILE
  (SDFVERSION "3.0")
  (DESIGN "my_design")
  (DATE "2024-01-15")
  (VENDOR "TSMC")
  (PROCESS "tt_0p85v_25c")
  (TIMESCALE 1ps)

  (CELL
    (CELLTYPE "DFFRQX2")
    (INSTANCE u_reg_bank/data_reg_0_)
    (DELAY
      (ABSOLUTE
        (IOPATH CK Q (120:150:200) (110:140:190))
      )
    )
    (TIMINGCHECK
      (SETUP D (posedge CK) (80:100:130))
      (HOLD D (posedge CK) (30:40:55))
    )
  )
)
```

### SDF Annotation Types

- **Pre-layout SDF (post-synthesis)**: Contains cell delays only. Interconnect delays are estimated or zero.
- **Post-layout SDF (post-PnR)**: Contains both cell delays and extracted interconnect delays. Most accurate for timing verification.

### SDF Annotation Commands

```bash
# VCS
vcs -sdf max:tb.dut:design.sdf netlist.v

# Xcelium
xrun -sdf_cmd_file sdf_annotation.cmd
# sdf_annotation.cmd:
# SDF_FILE = "design.sdf", SCOPE = tb.dut, MTM = MAX

# Questa
vsim -sdfmax tb.dut=design.sdf tb_top
```

### Min/Typ/Max Annotation

SDF files contain three delay values (min:typ:max) corresponding to best-case, typical, and worst-case process corners:

- **Max annotation**: Used for setup time verification (worst-case delays).
- **Min annotation**: Used for hold time verification (best-case delays).
- **Typ annotation**: Used for functional verification with typical delays.

## Timing Checks in GLS

### Setup and Hold Violations

When the simulator detects a timing violation (setup or hold), it typically outputs the register to X, indicating that the captured value is indeterminate:

```
Warning: Setup violation on instance tb.dut.u_reg_bank.data_reg[0]
  Setup time: 100ps, Required: 80ps
  Data changed at 900ps, Clock edge at 980ps
  Output set to X
```

### Timing Violation Handling

- **Default (pessimistic)**: Register output goes to X on timing violation. This is the safest behavior but can cause X-explosion where a single violation corrupts large portions of the design.
- **Optimistic (no timing check)**: Timing violations are logged but do not affect simulation values. Used when timing is not the focus of the test.
- **Conditioned**: Timing checks are disabled during specific conditions (e.g., during scan shift when hold violations on scan chain inputs are expected).

```bash
# VCS: suppress timing violations during scan mode
+neg_tchk  # Report negative timing checks without X output
+notimingcheck  # Disable all timing checks (use with caution)
```

### Pulse Filtering

Gate-level models include pulse filtering (minimum pulse width checks). Pulses shorter than the specified minimum width are filtered out, which can cause functional differences between RTL and GLS.

## X-Propagation in GLS

### Sources of X in GLS

1. **Uninitialized registers**: Flip-flops without reset start as X.
2. **Timing violations**: Setup/hold violations set register outputs to X.
3. **Metastability modeling**: CDC synchronizers may output X during metastability.
4. **Contention**: Multiple drivers on the same net produce X.

### X-Propagation Differences: RTL vs. GLS

RTL simulation with four-state logic handles X in conditional expressions pessimistically but differently from gate-level:

```systemverilog
// RTL: if-else with X condition
if (sel)      // sel = X → condition is false → else branch taken
  out = a;
else
  out = b;    // RTL: out = b

// Gate-level: MUX cell with X select
// out = X (because the MUX cannot determine which input to select)
```

This difference means bugs masked in RTL simulation may be exposed in GLS, and vice versa. This is one of the primary values of GLS.

### X-Propagation Modes

Modern simulators offer enhanced X-propagation modes:

```bash
# VCS Xprop mode
vcs -xprop=tmerge    # Propagates X through ternary operators and MUXes

# Xcelium Xprop mode
xrun -xprop f         # Forward X-propagation
xrun -xprop c         # Conditional X-propagation

# Questa X-propagation
vsim -xpropaliases    # Enhanced X handling
```

## GLS Debug Methodology

### Debugging GLS Failures

GLS debugging is challenging because:
- Gate-level netlists are difficult to read (instance names are cryptic).
- Waveforms show individual gate outputs rather than RTL-level signals.
- X-propagation creates cascading failures that obscure root causes.
- Simulation is slow, making iterative debug tedious.

### Debug Flow

1. **Identify the failure**: Note the failing check, assertion, or output mismatch.
2. **Cross-reference with RTL**: Use the netlist-to-RTL mapping to identify the corresponding RTL signal.
3. **Check for X at the failure point**: If the output is X, trace backward to find the X source.
4. **Classify the X source**:
   - Uninitialized register → Add reset or initialization.
   - Timing violation → Fix the timing path or investigate if the violation is real.
   - Functional bug → Debug using RTL methodology, then verify fix in GLS.
5. **Use cross-probing tools**: Verdi, SimVision, or Visualizer provide RTL-to-gate cross-referencing.

### Back-Annotation Debug

When timing violations cause failures:
1. Identify the violating path from the SDF file.
2. Cross-reference with static timing analysis (STA) results.
3. Determine if the violation is real (STA also reports it) or an artifact of simulation stimulus.
4. If real, fix the timing path. If an artifact, adjust the stimulus or timing constraints.

## GLS Performance Optimization

### Test Selection

Do not run the full regression suite at gate level. Select a representative subset:

- **Smoke tests**: Basic functionality verification.
- **Reset tests**: Verify proper initialization (X-propagation focus).
- **Critical path tests**: Sequences that exercise timing-critical paths.
- **DFT tests**: Scan chain, BIST, and JTAG tests.
- **Power-on sequence tests**: Verify the boot sequence at gate level.

### Simulation Speed Improvements

- **Reduce waveform dumping**: Dump only signals of interest.
- **Use two-state simulation** where X detection is not needed.
- **Parallel simulation**: Partition the netlist across CPU cores.
- **Selective SDF annotation**: Annotate delays only on the critical block under test.
- **Use Verilog `$sdf_annotate`**: Allows conditional annotation in the testbench.

### Typical GLS Speed

| Design Size | RTL Speed | GLS Speed | Ratio |
|------------|-----------|-----------|-------|
| 100K gates | ~100 KHz | ~10 KHz | 10x |
| 1M gates | ~10 KHz | ~100 Hz | 100x |
| 10M gates | ~1 KHz | ~10 Hz | 100x |

## Post-Synthesis vs. Post-PnR GLS

### Post-Synthesis GLS

- Uses the synthesis netlist (no interconnect delays).
- Faster than post-PnR GLS.
- Good for verifying synthesis correctness and X-propagation.
- Timing is approximate (cell delays only).

### Post-PnR GLS

- Uses the final placed-and-routed netlist with extracted parasitics.
- Most accurate timing (cell + interconnect delays).
- Slowest GLS mode.
- Required for timing sign-off.

### GLS Flow

```
RTL simulation (functional verification)
    ↓
Post-synthesis GLS (synthesis correctness, X-prop)
    ↓
Equivalence checking (RTL vs. gate)
    ↓
Post-PnR GLS (timing verification)
    ↓
STA (comprehensive timing analysis)
```

## Best Practices

1. **Run GLS on a representative test subset**, not the full regression — GLS is too slow for complete regression.
2. **Focus on X-propagation** in post-synthesis GLS to find uninitialized register bugs.
3. **Use max SDF for setup checks** and min SDF for hold checks.
4. **Cross-reference GLS timing violations with STA** — STA is the authority on timing; GLS validates specific scenarios.
5. **Maintain netlist-to-RTL mapping** for efficient debug using cross-probing tools.
6. **Run DFT-specific tests at gate level** to verify scan chain insertion and test mode functionality.
7. **Use enhanced X-propagation modes** (Xprop) for more accurate X handling during GLS.

## Summary

Gate-level simulation verifies the design at the implementation level, complementing RTL simulation and formal verification. It validates synthesis correctness, timing behavior (with SDF back-annotation), X-propagation behavior, and DFT insertion. While significantly slower than RTL simulation, GLS provides critical verification that cannot be achieved at the RTL level. A selective test strategy, efficient debug methodology, and proper SDF annotation are essential for making GLS productive within project schedules.
