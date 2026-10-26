# CDC Verification

## Overview

Clock Domain Crossing (CDC) verification ensures the correctness and reliability of signals that cross between asynchronous clock domains in a digital design. CDC errors are among the most insidious bugs in silicon — they are non-deterministic, depend on exact clock phase relationships, and are extremely difficult to detect through simulation alone. Dedicated CDC verification combining structural analysis, formal checking, and protocol verification is essential for any multi-clock design.

## CDC Fundamentals

### Why CDC Is a Problem

When a signal generated in one clock domain is sampled by a flip-flop in a different, asynchronous clock domain, the setup and hold timing requirements of the sampling flip-flop may be violated. This can cause metastability — a state where the flip-flop output is neither logic 0 nor logic 1, oscillating unpredictably before settling to a random value. Metastability can corrupt data and cause functional failures.

### Types of Clock Relationships

- **Synchronous clocks**: Derived from the same source with a known, fixed phase relationship. CDC between synchronous domains is safe if timing constraints are met.
- **Asynchronous clocks**: No fixed phase relationship. CDC between asynchronous domains requires synchronization structures.
- **Rationally related clocks**: Frequencies are integer multiples of each other but with variable phase. Treated as asynchronous for CDC purposes.

## Synchronization Structures

### Two-Flip-Flop Synchronizer

The most basic synchronizer for single-bit signals crossing between asynchronous domains:

```systemverilog
module sync_ff #(parameter STAGES = 2) (
  input  logic clk_dest,
  input  logic async_in,
  output logic sync_out
);
  logic [STAGES-1:0] sync_reg;

  always_ff @(posedge clk_dest) begin
    sync_reg <= {sync_reg[STAGES-2:0], async_in};
  end

  assign sync_out = sync_reg[STAGES-1];
endmodule
```

Two stages provide a MTBF (Mean Time Between Failures) sufficient for most applications. Three stages are used when the MTBF requirement is higher (high-frequency or safety-critical designs).

### Gray Code Encoding

For multi-bit values (counters, pointers), Gray code encoding ensures only one bit changes per transition, making the value safe to synchronize:

```systemverilog
// Binary to Gray conversion
assign gray_code = binary_code ^ (binary_code >> 1);

// Gray to Binary conversion
always_comb begin
  binary_code[N-1] = gray_code[N-1];
  for (int i = N-2; i >= 0; i--)
    binary_code[i] = binary_code[i+1] ^ gray_code[i];
end
```

Gray code is commonly used for FIFO read/write pointers in asynchronous FIFOs.

### Handshake Synchronization

For multi-bit data transfers, a handshake protocol ensures data stability:

```
Source domain:                    Destination domain:
1. Assert req, present data
                                  2. Synchronize req (2-FF)
                                  3. Capture data (stable)
                                  4. Assert ack
5. Synchronize ack (2-FF)
6. Deassert req, change data
                                  7. Synchronize req deassert
                                  8. Deassert ack
```

Data is stable during the entire handshake period, avoiding metastability on multi-bit data.

### Asynchronous FIFO

The asynchronous FIFO is the most common CDC structure for streaming data:

- Write pointer in the write clock domain (binary).
- Read pointer in the read clock domain (binary).
- Gray-coded pointers synchronized across domains.
- Full/empty flags generated from synchronized pointer comparison.

### MUX Synchronization (MUX Recirculation)

For data that changes infrequently (configuration registers), a MUX-based synchronizer holds the current value while new data stabilizes:

```systemverilog
always_ff @(posedge clk_dest) begin
  if (load_sync)    // Synchronized load signal
    data_reg <= data_in;  // Capture new data (must be stable)
end
```

## Structural CDC Checks

### Static CDC Analysis

Static CDC tools analyze the RTL netlist to identify all clock domain crossings and verify that proper synchronization structures are in place. This is the first line of defense.

**Tools:**
- **Synopsys SpyGlass CDC**: Industry-leading CDC analysis.
- **Cadence Conformal CDC (JasperGold CDC)**: Formal-based CDC verification.
- **Siemens Questa CDC**: CDC analysis and formal checking.
- **Real Intent Meridian CDC**: Specialized CDC verification.

### What Structural Checks Catch

- **Missing synchronizers**: Single-bit signals crossing domains without a synchronization flip-flop.
- **Multi-bit CDC without encoding**: Multi-bit buses crossing without Gray coding or handshake.
- **Combinational logic on CDC path**: Logic between the source domain and the synchronizer input (increases metastability window).
- **Convergence issues**: Multiple signals crossing the same CDC boundary and reconverging in the destination domain.
- **Glitch-prone paths**: Combinational logic generating the CDC signal that could create glitches (short pulses missed by the synchronizer).

### CDC Rule Categories

| Category | Description | Severity |
|----------|-------------|----------|
| No synchronizer | Signal crosses domains without any synchronizer | Critical |
| Insufficient stages | Synchronizer has fewer stages than required | Critical |
| Combo on CDC path | Combinational logic on the CDC path | Warning/Error |
| Multi-bit CDC | Multi-bit bus without proper encoding | Critical |
| Reconvergence | Multiple CDC signals reconverge | Warning |
| Glitch detection | CDC path may have glitches | Warning |

## Protocol Verification

### Beyond Structural Checks

Structural analysis ensures synchronizers exist but does not verify that the synchronization protocol is followed correctly. Protocol verification checks:

- **Data stability**: Data is held stable long enough to be safely captured.
- **Handshake compliance**: Request/acknowledge signals follow the proper handshake protocol.
- **Pulse width requirements**: Signals are held long enough (minimum 1 destination clock cycle plus margin) to be captured.
- **Gray code correctness**: Multi-bit transitions change exactly one bit at a time.

### Formal CDC Verification

Formal CDC analysis uses model checking to prove protocol properties:

```systemverilog
// Assertion: data must be stable when control signal is synchronized
assume property (@(posedge clk_dest)
  sync_valid |-> $stable(data_crossing));

// Assertion: request signal held long enough to be captured
assert property (@(posedge clk_src)
  $rose(req) |-> req[*2:$]);  // Held for at least 2 source clock cycles
```

Formal CDC verification provides exhaustive proof that the synchronization protocol is correct under all possible clock phase relationships.

## Reconvergence

### The Reconvergence Problem

When two or more signals cross the same CDC boundary independently, they may arrive in the destination domain with different latencies (due to metastability settling time). If these signals reconverge in combinational logic, the result may be inconsistent.

```
Source domain:        Destination domain:
  sig_a ─── sync ───┐
                      ├── combined logic (potential mismatch)
  sig_b ─── sync ───┘
```

`sig_a` and `sig_b` may have been consistent in the source domain but arrive at different times in the destination domain.

### Reconvergence Mitigation

- **Use a single-bit handshake** to control the transfer of multi-signal groups.
- **Use an asynchronous FIFO** for data that includes multiple related fields.
- **Gray code encoding** for pointer/counter values.
- **Register and hold** in the source domain until the handshake confirms capture.

### Structural Reconvergence Analysis

CDC tools trace signal paths to identify reconvergence:
1. Identify all CDC crossing points.
2. Trace forward from each crossing into the destination domain.
3. Flag any combinational logic where paths from multiple CDC crossings converge.
4. The designer must confirm that reconvergence is safe (e.g., all signals synchronized together) or fix the design.

## Gray Coding Verification

### Gray Code Properties

For Gray-coded pointers in asynchronous FIFOs, verification must confirm:
- Only one bit changes per clock cycle in the source domain.
- The Gray-encoded value is correctly synchronized.
- Full/empty detection is conservative (may report full/empty when not exactly so, but never reports not-full/not-empty when the FIFO is actually full/empty).

### Formal Verification of Gray Code

```systemverilog
// Assert single-bit transition for Gray code pointer
assert property (@(posedge wr_clk)
  $countones(gray_wr_ptr ^ $past(gray_wr_ptr)) <= 1
);

// Assert conservative full detection
assert property (@(posedge wr_clk)
  (actual_count == DEPTH) |-> full
);
```

## CDC Verification Flow

### Recommended Flow

1. **Define clock domains**: Specify all clocks, their relationships (synchronous, asynchronous, generated), and reset domains.
2. **Run structural CDC analysis**: Identify all crossings and check for proper synchronization structures.
3. **Review and waive**: Review violations. Waive false positives with documented justification.
4. **Run protocol verification**: Use formal methods to verify synchronization protocol compliance.
5. **Check reconvergence**: Analyze and resolve reconvergence issues.
6. **Verify gray coding**: Prove gray code properties for asynchronous FIFOs.
7. **Simulation validation**: Run targeted simulation tests that exercise CDC paths with varying clock frequencies and phases.
8. **Sign-off**: Confirm all critical CDC violations are resolved; all waivers are documented and reviewed.

### Clock Definition

```tcl
# SpyGlass CDC clock definition
set_clock clk_core -period 2.0
set_clock clk_bus  -period 5.0
set_clock clk_io   -period 10.0

# Specify asynchronous relationship
set_clock_groups -asynchronous -group {clk_core} -group {clk_bus} -group {clk_io}
```

### Constraint Refinement

Initial CDC analysis often produces many false violations due to missing constraints. Iterative constraint refinement is necessary:
- Specify quasi-static signals (configuration registers that do not change during normal operation).
- Constrain test/debug signals that are static during functional mode.
- Define generated clocks and their source relationships.

## Common CDC Bugs

1. **Missing synchronizer on reset release**: The release of an asynchronous reset crossing domains without synchronization can cause metastability.
2. **Pulse too narrow**: A pulse generated in a fast clock domain may be too narrow to be captured by a synchronizer in a slow clock domain.
3. **Data changing during handshake**: Source domain modifies data before the handshake completes.
4. **Incorrect full/empty detection**: Asynchronous FIFO full/empty logic fails under specific clock phase relationships.
5. **Clock gating interaction**: Clock gating in the destination domain causes the synchronizer to miss transitions.

## Best Practices

1. **Run CDC analysis early and continuously** — CDC bugs found late are expensive to fix.
2. **Minimize CDC crossings by design** — fewer crossings mean fewer potential bugs.
3. **Use proven synchronization structures** — avoid inventing custom synchronizers.
4. **Document all CDC crossings** with the synchronization method and protocol.
5. **Verify both directions** — crossing from domain A to B and from B to A.
6. **Use formal CDC verification** for protocol compliance — simulation alone cannot guarantee CDC correctness.

## Summary

CDC verification is essential for any multi-clock design. Structural analysis identifies missing or improper synchronization. Protocol verification using formal methods proves that synchronization protocols are correctly implemented. Reconvergence analysis ensures multi-signal crossings do not create inconsistencies. Gray code verification confirms the correctness of asynchronous FIFO pointers. A disciplined CDC verification flow combining static analysis, formal proofs, and simulation is required to achieve confidence in CDC correctness before tapeout.
