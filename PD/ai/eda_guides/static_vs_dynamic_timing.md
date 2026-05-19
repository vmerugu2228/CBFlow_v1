# Static vs. Dynamic Timing Analysis

## Overview

Timing verification ensures that a digital circuit operates correctly at the intended clock frequency. Two fundamentally different approaches exist: Static Timing Analysis (STA), which exhaustively checks all paths without requiring input vectors, and dynamic simulation, which verifies timing by simulating the circuit with specific input stimuli. Each approach has distinct strengths and limitations. Understanding when to use each and how they complement each other is critical for PD engineers responsible for signoff.

## Static Timing Analysis (STA)

### Fundamental Concept

STA computes the delay through every possible timing path in the design by propagating arrival times from inputs to outputs and comparing them against required times defined by clock constraints.

For every path from a launch flip-flop through combinational logic to a capture flip-flop:

```
Setup check:  Data Arrival Time < Data Required Time
              (T_launch + T_cq + T_comb) < (T_capture + T_period - T_setup)

Hold check:   Data Arrival Time > Data Required Time
              (T_launch + T_cq + T_comb) > (T_capture + T_hold)
```

Slack = Required Time - Arrival Time. Positive slack means the constraint is met; negative slack means violation.

### How STA Works

1. **Build timing graph**: Represent the design as a directed acyclic graph (DAG) where nodes are pins and edges are timing arcs (cell delays, wire delays)
2. **Propagate arrival times**: Starting from clock sources and input ports, propagate arrival times forward through the graph
3. **Compute required times**: Starting from output ports and capture flip-flop constraints, propagate required times backward
4. **Calculate slack**: At every endpoint, slack = required time - arrival time
5. **Report violations**: Any endpoint with negative slack is a timing violation

### STA Strengths

**Exhaustive coverage**: STA checks every possible path, including paths that may never be sensitized during normal operation. No input vectors are needed, so there is no coverage gap.

**Speed**: STA runs in minutes to hours even for multi-million gate designs. It scales linearly with design size.

**Corner-based analysis**: STA can analyze multiple PVT corners simultaneously (MMMC methodology), ensuring timing is met across all operating conditions.

**Incremental analysis**: After ECOs, STA can quickly re-analyze only the affected paths.

**Design flow integration**: STA is tightly integrated with PnR tools, enabling timing-driven optimization during implementation.

### STA Limitations

**Path-based, not vector-based**: STA cannot determine whether a path is functionally reachable. It may report violations on false paths that can never be activated.

- **Solution**: Engineers specify false paths (set_false_path) and multicycle paths (set_multicycle_path) in SDC constraints. However, missing or incorrect exceptions are a common source of errors.

**Cannot model dynamic effects accurately**: STA models crosstalk, power supply noise, and simultaneous switching using pessimistic approximations rather than actual switching activity.

**Limited analog/mixed-signal support**: STA does not handle analog circuits (PLLs, ADCs). Interface timing between digital and analog domains requires special modeling.

**Static power supply**: STA typically assumes a fixed supply voltage. Dynamic IR drop effects are accounted for through derating factors, not actual supply waveforms.

**Clock jitter modeling**: STA models jitter as a fixed value (from SDC or OCV analysis), not as a distribution. Actual jitter behavior may be more complex.

### STA Tools

- **PrimeTime** (Synopsys): Industry-standard signoff STA tool
- **Tempus** (Cadence): Integrated with Innovus PnR flow
- **Timer** (integrated in PnR tools): Used during implementation for timing-driven optimization

### Key STA Concepts

**MMMC (Multi-Mode Multi-Corner)**: Analyze multiple operating modes (functional, test, standby) across multiple PVT corners simultaneously. A modern SoC may have 20-50 MMMC scenarios.

**OCV (On-Chip Variation)**: Accounts for local process variation within a single die. Methods include:
- **Flat OCV**: Apply a fixed derating factor (e.g., 5% faster for early paths, 5% slower for late paths)
- **AOCV**: Advanced OCV with depth and distance-dependent derating
- **SOCV**: Statistical OCV using per-cell variation data from the library

**Signal Integrity (SI)**: Crosstalk from adjacent wires can cause delta delays (timing impact) and glitches (functional impact). SI-aware STA adds aggressor-induced delay to victim nets.

**CPPR (Clock Path Pessimism Removal)**: The common portion of the launch and capture clock paths should not have OCV derating applied (it is the same physical path). CPPR removes this artificial pessimism.

## Dynamic Timing Simulation

### Fundamental Concept

Dynamic simulation applies input stimulus vectors to a circuit model and simulates the circuit's behavior over time, checking whether all timing constraints are met during the simulation.

### How Dynamic Simulation Works

1. **Create stimulus**: Define input waveforms (VCD from RTL simulation, or targeted analog stimulus)
2. **Simulate**: Run a timing simulation that models gate delays, wire delays, and timing checks
3. **Check timing**: During simulation, timing checks (setup, hold) fire at every active clock edge
4. **Report violations**: Any timing check that fires indicates a violation for that specific input sequence

### Types of Dynamic Simulation

**Gate-level simulation (GLS)**: Simulate the gate-level netlist with SDF (Standard Delay Format) back-annotation. The SDF file contains actual delays from STA/extraction.

```
Gate-Level Netlist + SDF Delays + Testbench -> Event-Driven Simulator -> Timing Violations
```

**SPICE simulation**: Full transistor-level simulation for analog or critical digital paths. Most accurate but extremely slow.

**FastSPICE**: Approximate transistor-level simulation (e.g., FineSim, XA, HSIM) trading accuracy for speed.

### Dynamic Simulation Strengths

**Vector-based accuracy**: Only checks paths that are actually exercised by the input stimulus. No false positives from false paths.

**Dynamic effects captured**: Naturally models simultaneous switching output (SSO), ground bounce, power supply noise, and actual crosstalk patterns.

**Functional verification**: Simultaneously verifies functional correctness and timing, catching issues like race conditions, glitches, and metastability.

**Analog interaction**: Can simulate mixed analog-digital interactions (PLL lock time, ADC settling, I/O driver behavior).

**Actual switching activity**: Uses real switching patterns, so dynamic power and noise effects are modeled accurately.

### Dynamic Simulation Limitations

**Coverage gap**: Only checks paths exercised by the input stimulus. If a critical path is not activated by the test vectors, the violation is missed. Achieving full path coverage through simulation is impossible for any realistic design.

**Slow**: Gate-level simulation is 100-1000x slower than STA. A full regression suite may take days to weeks.

**Limited corner coverage**: Running simulation across all PVT corners is prohibitively expensive. Typically only 1-2 corners are simulated.

**Scalability**: Does not scale well to multi-million gate designs. Full-chip gate-level simulation of a large SoC can take weeks.

**Debug complexity**: When a violation is found, tracing the root cause through waveform analysis is time-consuming.

### Dynamic Simulation Tools

- **VCS** (Synopsys): Industry-standard Verilog simulator
- **Xcelium** (Cadence): Verilog/SystemVerilog simulator
- **HSPICE/FineSim** (Synopsys): SPICE/FastSPICE simulators
- **Spectre** (Cadence): Analog/mixed-signal simulator

## When to Use Each

### STA is Primary for

- **All digital timing signoff**: STA is the standard method for signoff across the industry
- **Timing-driven optimization**: During PnR, STA guides placement and routing optimization
- **Multi-corner analysis**: Checking timing across all PVT corners
- **ECO verification**: Quick re-verification after netlist changes
- **Hold fixing**: STA identifies all hold violations; simulation would miss most of them

### Dynamic Simulation is Primary for

- **Asynchronous interface verification**: CDC paths, asynchronous resets, handshake protocols
- **Mixed-signal interface timing**: Digital-analog boundaries (PLL, ADC, DAC, I/O PHY)
- **Dynamic power verification**: Verifying power delivery network under realistic switching
- **Post-silicon correlation**: Comparing simulation waveforms with silicon measurements
- **Reset and initialization sequences**: Verifying correct power-up behavior

### When Both are Needed

- **Clock domain crossings**: STA handles intra-domain timing; simulation verifies CDC synchronizer behavior
- **Asynchronous protocols**: STA ensures individual paths meet timing; simulation verifies protocol correctness
- **SRAM/memory interfaces**: STA checks setup/hold at memory pins; simulation verifies read/write protocol timing
- **I/O interfaces**: STA checks internal timing; simulation verifies compliance with I/O protocol (DDR, PCIe, USB)

## Hybrid Approaches

### STA with Timing Exceptions from Simulation

Use simulation to identify actually-sensitized paths, then feed this information back to STA as false path or multicycle path constraints. This reduces STA pessimism without sacrificing coverage.

### STA with Dynamic IR Drop Derating

Run dynamic IR drop analysis to determine voltage drop under realistic switching conditions. Apply the resulting voltage derating to STA for more accurate timing.

### DMSA (Distributed Multi-Scenario Analysis)

Run STA across many scenarios in parallel, using distributed computing. This is purely static but addresses the scale challenge of analyzing 50+ MMMC scenarios.

### Statistical STA (SSTA)

Instead of analyzing discrete corners, SSTA propagates probability distributions through the timing graph. This captures the interaction between process parameters more accurately than discrete-corner STA but is computationally more expensive and not yet universally adopted.

## Practical Workflow for PD Engineers

1. **During implementation**: Use STA (integrated in PnR tool) for all timing-driven optimization
2. **At signoff**: Run signoff STA (PrimeTime/Tempus) across all MMMC scenarios with SI and OCV
3. **For async interfaces**: Run gate-level simulation with SDF back-annotation to verify CDC and async protocol behavior
4. **For power signoff**: Run dynamic IR drop analysis with realistic switching activity
5. **For mixed-signal**: Run SPICE/FastSPICE simulation on the analog-digital interface blocks
6. **For silicon correlation**: Compare STA predictions against silicon speed measurements using ring oscillators and test structures

The combination of STA for exhaustive coverage and simulation for dynamic accuracy provides complete timing verification. Neither alone is sufficient for a robust signoff methodology.
