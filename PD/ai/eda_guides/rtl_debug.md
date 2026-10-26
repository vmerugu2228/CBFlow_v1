# RTL Debugging

## Overview

Debugging RTL designs is a systematic process of identifying, isolating, and fixing functional or timing bugs in hardware descriptions. Unlike software, where a debugger can step through execution, hardware debug involves analyzing parallel, concurrent behavior across thousands of signals over millions of clock cycles. Effective debug requires mastery of simulation tools, waveform analysis, assertion-based techniques, and formal property checking. This guide covers practical debug strategies and tool usage for production RTL design.

## Simulation-Based Debugging

### Simulation Flow

The primary debug method is running a testbench that applies stimulus to the design and checks the output against expected results.

```
Testbench -> Stimulus -> DUT -> Response -> Checker -> Pass/Fail
```

### Simulators

- **Synopsys VCS**: Industry-leading performance, extensive debug features.
- **Cadence Xcelium**: Strong mixed-signal and multi-language support.
- **Mentor Questa**: Excellent coverage and formal integration.
- **Verilator**: Open-source, fast cycle-accurate simulation (limited debug features).

### Running a Simulation

```bash
# VCS compilation and simulation
vcs -sverilog -debug_all -timescale=1ns/1ps \
    -f filelist.f top_tb -o simv
./simv +vcd+dump.vcd

# Xcelium
xrun -sv -access +rwc -timescale 1ns/1ps \
    -f filelist.f top_tb

# Questa
vlog -sv +acc filelist.f
vsim -voptargs="+acc" top_tb -do "run -all"
```

### Debug Compilation Options

- **`-debug_all`** (VCS) / **`+acc`** (Questa) / **`-access +rwc`** (Xcelium): Enable signal access for waveform dumping and interactive debug. These options slow simulation; use them only for debug runs.
- **`-timescale`**: Set the time unit and precision for delay annotations.

## Waveform Analysis

Waveforms are the primary visual tool for hardware debug. They show the value of every signal at every point in time.

### Waveform Formats

- **VCD (Value Change Dump)**: Standard IEEE format. Widely supported but large file sizes.
- **FSDB (Fast Signal Database)**: Verdi proprietary format. Smaller files, faster loading, hierarchical browsing.
- **WLF (Waveform Log File)**: Questa native format.
- **SHM**: Xcelium native format.

### Dumping Waveforms

```systemverilog
// In testbench: VCD dump
initial begin
  $dumpfile("dump.vcd");
  $dumpvars(0, top_tb);  // dump all signals from top_tb down
end

// FSDB dump (requires Verdi library)
initial begin
  $fsdbDumpfile("dump.fsdb");
  $fsdbDumpvars(0, top_tb);
end
```

### Waveform Viewers

- **Synopsys Verdi**: The dominant waveform viewer in the industry. Features source-code linkage, schematic view, temporal flow analysis, and automated signal tracing.
- **Cadence SimVision**: Integrated with Xcelium.
- **GTKWave**: Open-source VCD viewer.

### Effective Waveform Debug Strategy

1. **Start at the failure point**: Find the first cycle where the output diverges from expected.
2. **Trace backward**: From the incorrect output, trace back through the logic to find where the correct value was lost.
3. **Use driver tracing**: In Verdi, right-click a signal and "Trace Driver" to find what logic drives it.
4. **Use fan-in cone analysis**: Highlight all signals in the fan-in cone of the failing output to narrow the search.
5. **Set waveform markers**: Mark key events (error occurrence, trigger conditions) for reference.
6. **Use analog display for multi-bit buses**: Display buses as analog waveforms to quickly spot unexpected values.

## Print-Based Debugging

When waveforms are impractical (long simulations, large designs), print-based debug provides targeted visibility.

```systemverilog
// Conditional print on key events
always @(posedge clk) begin
  if (valid && ready) begin
    $display("[%0t] TRANSFER: addr=%h data=%h", $time, addr, data);
  end
end

// Error detection with context
always @(posedge clk) begin
  if (error_detected) begin
    $error("[%0t] ERROR in %m: state=%s expected=%h got=%h",
           $time, state.name(), expected, actual);
    $display("  History: prev_state=%s, last_addr=%h", prev_state.name(), last_addr);
  end
end
```

### Structured Logging

For complex systems, implement a structured logging framework:

```systemverilog
`define LOG_INFO(msg)  $display("[INFO][%0t][%m] %s", $time, msg)
`define LOG_WARN(msg)  $display("[WARN][%0t][%m] %s", $time, msg)
`define LOG_ERROR(msg) $display("[ERROR][%0t][%m] %s", $time, msg)
```

## Assertion-Based Debug

Assertions catch bugs at the point of violation, not downstream where the symptom appears. This dramatically reduces debug time.

### Immediate Assertions

```systemverilog
always_comb begin
  assert (state != ILLEGAL_STATE)
    else $error("FSM entered illegal state at time %0t", $time);
end
```

### Concurrent Assertions for Protocol Checking

```systemverilog
// AXI valid must not deassert before ready
property p_axi_valid_stable;
  @(posedge clk) disable iff (!rst_n)
  (awvalid && !awready) |=> awvalid;
endproperty
assert property (p_axi_valid_stable)
  else $error("AXI AWVALID dropped before AWREADY");

// Data must be stable while valid is asserted
property p_data_stable;
  @(posedge clk) disable iff (!rst_n)
  (valid && !ready) |=> $stable(data);
endproperty
assert property (p_data_stable)
  else $error("Data changed while valid without ready");
```

### Assertions as Bug Locators

Place assertions at every module interface and at every internal invariant. When a bug occurs, the assertion closest to the root cause fires first, pinpointing the problem.

```systemverilog
// FIFO internal invariants
assert property (@(posedge clk) disable iff (!rst_n)
  count <= DEPTH) else $error("FIFO count exceeds depth");

assert property (@(posedge clk) disable iff (!rst_n)
  !(wr_en && full)) else $error("FIFO write when full");

assert property (@(posedge clk) disable iff (!rst_n)
  !(rd_en && empty)) else $error("FIFO read when empty");
```

## Formal Property Checking

Formal verification exhaustively proves or disproves properties without simulation. It explores all possible input sequences and state configurations.

### Formal Debug Flow

```tcl
# Synopsys VC Formal / Cadence JasperGold
analyze -sv design.sv
elaborate top
clock clk
reset rst_n

# Check assertions
prove -all

# If a property fails, the tool provides a counterexample trace
# that can be viewed as a waveform
```

### Bounded vs Unbounded Proofs

- **Bounded proof**: Checks the property up to N clock cycles. Fast but does not guarantee correctness beyond N cycles.
- **Unbounded proof**: Proves the property for all possible execution traces of any length. Computationally expensive; may not converge for complex designs.

### When to Use Formal

1. **Control logic**: FSMs, arbiters, protocol controllers.
2. **Interface compliance**: AXI/AHB protocol rules.
3. **Safety properties**: No deadlock, no illegal states, no data corruption.
4. **Small-to-medium blocks**: Formal scales well up to ~100K gates; larger blocks require abstraction.

### Cover Properties

Cover properties verify that interesting scenarios are reachable:

```systemverilog
cover property (@(posedge clk) disable iff (!rst_n)
  (state == IDLE) ##[1:10] (state == ACTIVE) ##[1:100] (state == DONE));
```

If a cover property fails (unreachable), it may indicate dead code or a design bug.

## X-Propagation Debug

In simulation, `X` (unknown) values propagate through logic, potentially masking bugs or causing false failures.

### Sources of X

1. Uninitialized registers (no reset).
2. Reading from an uninitialized memory location.
3. Multi-driver conflicts.
4. Out-of-range array indices.
5. Division by zero.

### X-Optimism vs X-Pessimism

Standard Verilog simulation is X-optimistic: `if (x_signal)` is treated as false, hiding the bug. Real hardware resolves X to either 0 or 1, which may take the true branch.

**X-pessimism** modes (available in modern simulators) propagate X more aggressively:

```bash
# VCS: enable X-propagation
vcs -xprop

# Xcelium
xrun -xprop
```

### Debug Strategy for X Issues

1. Identify all signals that are X at the failure point.
2. Trace backward to find the source of the X (usually an uninitialized register or memory).
3. Add reset to the source register, or initialize the memory.
4. Use assertions to catch X values: `assert (!$isunknown(signal))`.

## Gate-Level Debug

After synthesis, gate-level simulation may reveal bugs not visible in RTL simulation (due to synthesis pragmas, optimization, or timing effects).

### Common Gate-Level-Only Bugs

1. **Latch inference**: An unintended latch was created by synthesis.
2. **Optimization removal**: Synthesis optimized away logic that was needed.
3. **Timing violations**: Setup/hold violations cause incorrect capture.
4. **X-initialization differences**: Gate-level reset behavior may differ from RTL.

### Gate-Level Debug with Back-Annotation

```tcl
# SDF annotation for gate-level timing simulation
$sdf_annotate("design.sdf", top_tb.u_dut);
```

## Debug Methodology Summary

1. **Reproduce the failure**: Run the failing test case with waveform dumping enabled.
2. **Localize the failure**: Find the first cycle and signal where behavior diverges from expected.
3. **Trace to root cause**: Use driver tracing, fan-in analysis, or backward temporal analysis.
4. **Understand the bug**: Determine why the RTL produces incorrect behavior.
5. **Fix and regress**: Apply the fix, verify the failing test passes, and run the full regression suite to ensure no new failures.
6. **Add assertions**: Add assertions that would have caught this bug earlier, preventing future recurrence.

## Summary

Effective RTL debug combines waveform analysis for detailed signal inspection, assertions for early bug detection, formal verification for exhaustive property checking, and X-propagation analysis for initialization issues. The key principle is to catch bugs as close to their root cause as possible: assertions at interfaces, invariants in logic, and formal proofs for protocols. Every bug found should result in a new assertion added to the design.
