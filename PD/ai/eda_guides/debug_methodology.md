# Debug Methodology

## Overview

Debug is the process of identifying and localizing the root cause of a verification failure. In modern SoC verification, debug consumes a significant portion of the verification engineer's time — often 30-50% of total effort. Effective debug methodology combines systematic techniques (waveform analysis, log analysis, assertion debug, coverage debug) with tool proficiency to minimize the time from failure detection to root cause identification. The goal is not just to find bugs but to find them quickly and systematically.

## Waveform Debug

### Waveform Viewers

The waveform viewer is the primary debug tool for hardware design:

- **Synopsys Verdi**: The industry-leading debug platform. Provides RTL-aware debug, schematic navigation, temporal flow analysis, and assertion visualization.
- **Cadence SimVision / Indago**: Cadence's debug platform with transaction-level debug, assertion debug, and coverage visualization.
- **Siemens Questa Visualizer**: Siemens' debug environment with dataflow visualization and assertion analysis.

### Waveform Debug Flow

1. **Load the failure**: Open the waveform database at the time of failure (assertion fail, scoreboard mismatch, timeout).
2. **Add signals**: Start with the failing signal(s) and add related signals (control path, data path, clock, reset).
3. **Navigate in time**: Move to the failure time, then work backward to find where the incorrect behavior originated.
4. **Trace causality**: Follow the signal back through the logic cone using the tool's schematic or dataflow views.
5. **Identify the root cause**: The point where actual behavior diverges from expected behavior is the bug.

### Effective Signal Selection

Start with a minimal set of signals and expand:
- **Output signals**: The failing check's inputs (scoreboard output, assertion signals).
- **State machine states**: The current state of relevant FSMs.
- **Control signals**: Enable, valid, ready, select signals in the data path.
- **Data signals**: Address, data, and transaction ID at key pipeline stages.
- **Clock and reset**: Verify correct clock and reset behavior.

### Verdi-Specific Techniques

**nTrace (Signal Tracing)**:
Right-click a signal and trace its drivers or loads through the design hierarchy. Verdi follows the logic cone automatically.

**Temporal Flow View**:
Visualizes how a signal's value propagated through logic over time. Shows the chain of events leading to the current value.

**Schematic View**:
Displays the logic around a signal as a schematic diagram. Enables clicking through logic stages to follow the data path.

**Transaction Debug**:
For UVM-based testbenches, Verdi can display transactions overlaid on waveforms, correlating protocol-level events with signal-level activity.

## Log Analysis

### Structured Logging

A well-designed testbench produces structured, grep-friendly log messages:

```
UVM_INFO @ 100ns [DRIVER] Write transaction: addr=0x1000, data=0xDEADBEEF
UVM_INFO @ 150ns [MONITOR] Observed write: addr=0x1000, data=0xDEADBEEF
UVM_INFO @ 200ns [SCOREBOARD] Match: expected=0xDEADBEEF, actual=0xDEADBEEF
UVM_ERROR @ 350ns [SCOREBOARD] Mismatch: expected=0x12345678, actual=0x00000000
```

### Log Analysis Techniques

**Keyword search**: Search for ERROR, WARNING, FATAL, and assertion-specific messages:
```bash
grep -E "UVM_ERROR|UVM_FATAL|assert" simulation.log
```

**Timeline reconstruction**: Extract timestamps from log messages to reconstruct the sequence of events:
```bash
grep "SCOREBOARD" simulation.log | sort -t@ -k2 -n
```

**Differential analysis**: Compare logs from a passing and failing seed to identify divergence:
```bash
diff <(grep "MONITOR" pass.log) <(grep "MONITOR" fail.log)
```

**Pattern matching**: Search for specific transaction IDs, addresses, or data values across all log sources:
```bash
grep "addr=0x1000" simulation.log  # Track all accesses to a specific address
```

### Verbosity Control

UVM verbosity levels control log volume:
- `UVM_NONE`: Always printed.
- `UVM_LOW`: Important operational messages.
- `UVM_MEDIUM`: Standard operational detail.
- `UVM_HIGH`: Detailed debug information.
- `UVM_FULL`: Maximum detail (very verbose).
- `UVM_DEBUG`: Tool-level debug information.

During initial debug, run with `UVM_HIGH` or `UVM_FULL` verbosity. For regression, use `UVM_LOW` or `UVM_MEDIUM` to keep log sizes manageable.

```bash
# Run with high verbosity
simv +UVM_VERBOSITY=UVM_HIGH

# Set verbosity per component
simv +uvm_set_verbosity=env.agent.monitor,_ALL_,UVM_DEBUG
```

## Assertion Debug

### Assertion Failure Analysis

When an assertion fails, the debug process is:

1. **Read the assertion message**: The name, instance, and time of failure.
2. **Understand the assertion**: Read the SVA property to understand what condition was violated.
3. **Open the waveform at failure time**: Examine the signals referenced in the assertion.
4. **Trace the cause**: Determine why the signal values violated the property.
5. **Classify**: RTL bug, testbench issue, or incorrect assertion.

### Using Assertions for Localization

High assertion density in the RTL acts as a distributed debugging system:
- When an assertion inside module A fails, the bug is in or near module A.
- Without internal assertions, the failure is detected only at the testbench boundary, and the root cause could be anywhere.

### Assertion Waveform Markers

Modern debug tools display assertion pass/fail markers on waveforms:
- Green markers: Assertion passed at this time.
- Red markers: Assertion failed at this time.
- Yellow markers: Assertion attempt (antecedent matched but consequent not yet resolved).

This visual representation helps correlate assertion activity with signal behavior.

## Coverage Debug

### Why Coverage Holes Exist

When functional or code coverage targets are not met, the causes include:

1. **Missing stimulus**: The constrained random generator has not produced the required scenario.
2. **Unreachable code**: The RTL contains code that cannot be activated (dead logic, disabled features).
3. **Incorrect constraints**: Constraints prevent the generator from reaching certain scenarios.
4. **Missing sequences**: No directed sequence targets the specific scenario.

### Coverage Gap Debug Flow

1. **Identify the uncovered item**: Coverage report shows uncovered bins, branches, or states.
2. **Analyze reachability**: Determine if the scenario is reachable given the current constraints and environment.
3. **If reachable**:
   - Adjust constraints to increase probability.
   - Write a targeted directed sequence.
   - Add a new seed that hits the scenario.
4. **If unreachable**:
   - Determine if this is by design (document and exclude).
   - Determine if this indicates a design bug (report to design team).

### Coverage-Driven Debug

Use coverage data to guide stimulus development:
- Cross-coverage holes reveal untested combinations.
- FSM transition coverage shows untested state machine paths.
- Condition coverage reveals untested Boolean expression combinations.

## Root Cause Analysis

### The 5-Whys Technique

Apply iterative questioning to trace from symptom to root cause:

1. **Why did the scoreboard mismatch?** Because the output data was zero instead of the expected value.
2. **Why was the output data zero?** Because the read request was not serviced by the memory controller.
3. **Why was it not serviced?** Because the request was dropped at the arbiter.
4. **Why was it dropped?** Because the arbiter's grant FIFO was full.
5. **Why was the FIFO full?** Because the response path was stalled, and the FIFO did not handle backpressure correctly.

Root cause: Missing backpressure handling in the arbiter's grant FIFO.

### Binary Search (Bisection)

For complex failures, use binary search to narrow the root cause in time:

1. Identify the failing time (T_fail) and a known-good time (T_good).
2. Check the midpoint (T_mid = (T_good + T_fail) / 2).
3. If the state is correct at T_mid, the bug occurred between T_mid and T_fail.
4. If the state is incorrect at T_mid, the bug occurred between T_good and T_mid.
5. Repeat until the narrow window around the bug is found.

### Comparison Debug

Compare a passing and failing simulation to identify the divergence point:

1. Run both simulations with identical configurations except the trigger (different seed, different stimulus).
2. Dump waveforms for both.
3. Compare key signals between the two runs.
4. The point of divergence localizes the bug.

## Debug Automation

### Automated Failure Signature Extraction

Parse simulation logs to extract structured failure information:

```python
def extract_signature(log_file):
    signatures = []
    for line in open(log_file):
        if "UVM_ERROR" in line or "UVM_FATAL" in line:
            component = re.search(r'\[(\w+)\]', line).group(1)
            message = re.search(r'\] (.+)', line).group(1)
            signatures.append((component, message[:80]))
    return signatures
```

### Post-Simulation Checks

Automated scripts run after simulation to check for:
- Non-zero UVM error count.
- Unexpected warnings.
- Performance metric violations.
- Incomplete transactions (items stuck in scoreboards).
- Coverage regression (coverage decreased from previous run).

### Debug Scripts

Maintain a library of debug scripts for common tasks:
- Extract all transactions for a specific address.
- Dump the state of all FIFOs at a specific time.
- Generate a protocol timeline from log messages.
- Compare register values against expected values at a specific time.

## Debug Tool Features

### Source-Level Debug

Modern simulators support setting breakpoints in SystemVerilog source code:
- Break on line, signal value change, or assertion failure.
- Step through procedural code (task/function bodies).
- Inspect variable values at breakpoints.

### Memory/Array Inspection

Debug tools provide views of memory contents, FIFO state, and array values at any simulation time.

### Transaction-Level Debug

UVM-aware debug tools correlate transactions with signal activity:
- See which transaction caused a particular signal pattern.
- Navigate from a scoreboard mismatch directly to the corresponding transaction in the waveform.

## Best Practices

1. **Start with the failure point and work backward** — do not start from the beginning of the simulation.
2. **Use assertions for localization** — high assertion density narrows the search space dramatically.
3. **Minimize the reproduce case** — create a shorter, simpler test that reproduces the failure.
4. **Use structured logging** with consistent formatting for efficient log analysis.
5. **Automate repetitive debug tasks** with scripts and custom tool configurations.
6. **Document root causes** and add regression tests to prevent recurrence.
7. **Build a failure knowledge base** — past debug experiences accelerate future debug.

## Summary

Debug methodology combines waveform analysis, log analysis, assertion-based localization, coverage-driven investigation, and systematic root cause analysis. Effective debug starts at the failure point and works backward through the causal chain. Assertion density, structured logging, and automation are force multipliers. Mastery of debug tools (Verdi, SimVision, Visualizer) and systematic techniques (5-Whys, bisection, differential analysis) enables verification engineers to find bugs quickly and confidently.
