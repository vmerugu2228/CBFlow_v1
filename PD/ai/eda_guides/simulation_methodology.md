# Simulation Methodology

## Overview

Simulation is the most widely used verification technique in digital design, responsible for validating the vast majority of design functionality before tapeout. Modern simulation methodology encompasses event-driven simulation, cycle-based simulation, mixed-signal co-simulation, and various acceleration techniques. Understanding the strengths, limitations, and optimization strategies for each approach is essential for building an efficient verification infrastructure.

## Event-Driven Simulation

### Fundamentals

Event-driven simulation tracks changes (events) on signals and evaluates only the logic affected by those changes. The simulator maintains a time-ordered event queue and processes events chronologically. This approach supports the full semantics of SystemVerilog and VHDL, including:

- **Four-state logic** (0, 1, X, Z) for detecting initialization issues and bus contention.
- **Timing delays** (inertial and transport) for gate-level timing verification.
- **Concurrent processes** (always blocks, initial blocks, continuous assignments) modeled as separate threads.

### Simulation Regions

The SystemVerilog scheduling semantics define multiple regions within each time step:

1. **Active**: Execute blocking assignments, continuous assignments, evaluate RHS of NBA.
2. **Inactive**: Execute `#0` delayed assignments.
3. **NBA (Non-Blocking Assignment)**: Execute LHS updates of non-blocking assignments.
4. **Observed**: Evaluate concurrent assertion expressions.
5. **Reactive**: Execute program block code, assertion action blocks.
6. **Postponed**: Execute `$monitor`, `$strobe`, read-only phase.

Understanding these regions is critical for avoiding race conditions and writing correct testbenches.

### Event-Driven Performance

Event-driven simulation performance depends on:
- **Design toggle rate**: More switching activity means more events to process.
- **Simulation resolution**: Finer time resolution (e.g., 1ps vs 1ns) increases the number of time steps.
- **Testbench complexity**: Complex scoreboards, coverage models, and assertions add overhead.
- **Typical speed**: 1-100 Hz for large SoC designs (1-100 clock cycles per wall-clock second for full-chip).

## Cycle-Based Simulation

### Concept

Cycle-based simulation evaluates the entire design once per clock cycle, computing all combinational logic values simultaneously rather than propagating events. It sacrifices intra-cycle timing information for speed.

### Advantages

- **Speed**: 5-10x faster than event-driven simulation for synchronous designs.
- **Deterministic**: No race conditions since all logic is evaluated atomically per cycle.

### Limitations

- **No timing information**: Cannot detect glitches, timing violations, or setup/hold issues.
- **No four-state logic**: Typically uses two-state (0/1) which misses X-propagation bugs.
- **Synchronous only**: Asynchronous interfaces and multi-clock designs require special handling.

### Use Cases

Cycle-based simulation is ideal for long-running software-driven tests where cycle-accurate behavior is sufficient (boot sequences, firmware tests, algorithm verification).

## Mixed-Signal Simulation

### The Challenge

Modern SoCs contain both digital and analog components (PLLs, ADCs, DACs, SerDes, voltage regulators). Verifying the interaction between digital and analog domains requires mixed-signal simulation.

### Approaches

- **Real-Number Modeling (RNM)**: Model analog blocks as SystemVerilog real-valued functions. Fast but approximate. Suitable for architectural exploration and digital-centric verification.
- **Verilog-AMS**: Co-simulate digital (Verilog/SV) and analog (SPICE-level or behavioral) blocks in a unified environment. Moderate speed, good accuracy.
- **SPICE Co-Simulation**: Full SPICE accuracy for analog blocks coupled with digital simulation. Slowest but most accurate. Used for critical analog-digital interfaces.

### Mixed-Signal Tool Flows

- **Cadence**: Xcelium + Spectre (AMS Designer).
- **Synopsys**: VCS + CustomSim/HSPICE (VCS-AMS).
- **Siemens**: Questa + Eldo (Questa AMS).

## Co-Simulation

### Hardware-Software Co-Simulation

Verifying embedded software running on the hardware model is critical for SoC verification. Co-simulation connects a processor model (ISS — Instruction Set Simulator) with the RTL simulation.

- **ISS-RTL co-simulation**: An ISS executes firmware while the RTL simulation models the hardware. Transactions are exchanged at bus interfaces.
- **QEMU co-simulation**: QEMU provides fast virtual-platform-level software execution. It connects to RTL simulation for hardware blocks under verification.
- **Virtual platforms + RTL hybrid**: Fast virtual platform for most of the SoC, RTL simulation for the block under test.

### SystemC-RTL Co-Simulation

SystemC transaction-level models (TLMs) run alongside RTL simulation, providing fast models for blocks not under test:

```
RTL simulation (DUT) <-> TLM socket <-> SystemC model (memory, bus fabric)
```

This approach accelerates simulation by replacing non-critical RTL blocks with fast SystemC models while maintaining RTL accuracy for the design under test.

## Simulation Performance Optimization

### Compile-Time Optimizations

- **Two-state simulation**: Use `bit` instead of `logic` where X/Z detection is not needed. Enables more efficient internal representations.
- **Optimized compilation**: Enable tool-specific optimization flags (`vcs -O3`, `xrun -optimize`, `vsim -vopt`).
- **Partitioning**: Split the design across multiple simulation engines for parallel execution.

### Runtime Optimizations

- **Waveform dumping control**: Dump waveforms only for signals of interest. Full-chip waveform dumps can slow simulation by 5-10x.
  ```systemverilog
  $fsdbDumpvars(0, "tb.dut.block_under_test");  // Dump only relevant hierarchy
  ```
- **Assertion control**: Disable assertions in stable blocks during long-running tests.
- **Coverage control**: Collect coverage only in targeted runs, not every regression test.
- **Memory optimization**: Use `+define+` to reduce memory arrays in verification mode. Use sparse memory models for large address spaces.

### Parallel Simulation

- **Multi-core simulation**: Modern simulators partition the design across CPU cores (VCS Partition Compile, Xcelium ML-driven partition).
- **Distributed regression**: Run independent tests on different machines in parallel. Coverage is merged post-regression.
- **GPU acceleration**: Some tools offload specific computations (UPF power simulation, assertion evaluation) to GPUs.

## Simulation Infrastructure

### Regression Framework

A production regression framework manages:
- **Test selection**: Choosing which tests to run based on code changes, coverage gaps, or risk assessment.
- **Seed management**: Recording random seeds for reproducibility. Storing seeds that hit interesting coverage.
- **Resource allocation**: Distributing tests across compute farm (LSF, SGE, Slurm).
- **Result collection**: Aggregating pass/fail results, coverage data, and performance metrics.

### Waveform Databases

- **FSDB** (Fast Signal Database): Synopsys/Springsoft format. Supported by Verdi.
- **VCD** (Value Change Dump): IEEE standard, large file sizes.
- **WLF** (Waveform Log File): Siemens Questa format.
- **SHM** (Simulation History Manager): Cadence format.

FSDB is the most widely used due to its compression efficiency and Verdi debug ecosystem.

### Log Management

Simulation logs can be enormous (GB-scale for long tests). Best practices:
- Use verbosity control (UVM verbosity levels) to manage log volume.
- Implement structured logging with grep-friendly prefixes.
- Archive compressed logs with indexing for post-mortem analysis.

## Simulation Accuracy Modes

### RTL Simulation (Pre-Synthesis)

- Full design intent verification.
- No timing information — functional correctness only.
- Fastest compile, most debug visibility.

### Gate-Level Simulation (Post-Synthesis, Post-PnR)

- Verifies synthesis/PnR correctness.
- SDF back-annotation for timing accuracy.
- X-propagation checking for uninitialized registers.
- 10-100x slower than RTL simulation.

### Power-Aware Simulation (UPF/CPF)

- Models power domains, isolation, retention, and level shifting.
- Verifies power state transitions and corruption/retention behavior.
- Requires UPF (Unified Power Format) or CPF (Common Power Format) specification.

## Simulation Debug Flow

1. **Reproduce**: Run failing test with the same seed and configuration.
2. **Narrow**: Identify the failing check (assertion, scoreboard error, protocol violation).
3. **Trace back**: From the failing point, trace backward through the signal path using waveforms.
4. **Root cause**: Identify the RTL bug, testbench issue, or environmental problem.
5. **Fix and verify**: Apply the fix and run the failing test plus related regression tests.

## Best Practices

1. **Use constrained random as the primary stimulus strategy**, supplemented by directed tests for critical corners.
2. **Optimize waveform dumping** — full dumps are prohibitively expensive for large designs.
3. **Build a robust regression infrastructure** with seed management, coverage merging, and automated triage.
4. **Profile simulation performance** regularly — identify and optimize bottlenecks (slow testbench code, excessive assertion overhead, memory pressure).
5. **Layer simulation accuracy** — use RTL simulation for most verification, gate-level only for targeted timing and X-prop checks.

## Summary

Simulation remains the workhorse of design verification. Event-driven simulation provides maximum accuracy; cycle-based simulation offers speed for software-centric tests. Mixed-signal and co-simulation handle analog integration and software verification. Performance optimization through compile flags, selective waveform dumping, and parallel execution is essential for managing simulation capacity. A well-designed simulation infrastructure — including regression management, coverage collection, and debug tools — is the backbone of any production verification environment.
