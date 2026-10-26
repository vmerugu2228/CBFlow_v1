# Assertion-Based Verification

## Overview

Assertion-Based Verification (ABV) embeds executable checks directly into the design and testbench to continuously monitor correctness during simulation and to serve as proof targets for formal verification. Assertions act as distributed, always-on checkers that catch bugs closer to the root cause than end-to-end scoreboard checks. ABV is widely recognized as one of the most cost-effective verification techniques, with industry data showing that designs with high assertion density find bugs 2-5x faster than those relying solely on output checking.

## Assertion Categories

### White-Box Assertions (Design Assertions)

White-box assertions are embedded inside the RTL modules by the design engineer. They check internal invariants that are not visible from the module's external interface.

```systemverilog
module fifo #(parameter DEPTH = 16) (
  input  logic clk, reset,
  input  logic push, pop,
  output logic full, empty
);
  logic [$clog2(DEPTH):0] count;

  // Internal invariant: count never exceeds DEPTH
  AST_COUNT_RANGE: assert property (@(posedge clk) disable iff (reset)
    count <= DEPTH
  ) else $error("FIFO count %0d exceeds depth %0d", count, DEPTH);

  // No push when full
  AST_NO_PUSH_FULL: assert property (@(posedge clk) disable iff (reset)
    full |-> !push
  ) else $error("Push attempted while FIFO is full");

  // No pop when empty
  AST_NO_POP_EMPTY: assert property (@(posedge clk) disable iff (reset)
    empty |-> !pop
  ) else $error("Pop attempted while FIFO is empty");

  // Full/empty consistency
  AST_FULL_EMPTY_MUTEX: assert property (@(posedge clk) disable iff (reset)
    !(full && empty)
  ) else $error("FIFO simultaneously full and empty");
endmodule
```

**Benefits of white-box assertions:**
- Catch bugs at the source before they propagate.
- Document design intent in executable form.
- Serve as regression checks that persist across design revisions.
- Enable formal property checking on internal logic.

### Interface Assertions

Interface assertions verify protocol compliance at module boundaries. They check that signals conform to the protocol specification (timing, handshaking, encoding).

```systemverilog
interface axi_intf (input logic clk, reset);
  logic        awvalid, awready;
  logic [31:0] awaddr;
  logic [7:0]  awlen;
  // ... more AXI signals

  // AXI protocol: AWVALID must remain asserted until AWREADY
  AST_AW_STABLE: assert property (@(posedge clk) disable iff (reset)
    awvalid && !awready |=> awvalid
  );

  // AXI protocol: Address must be stable while AWVALID is asserted
  AST_AW_ADDR_STABLE: assert property (@(posedge clk) disable iff (reset)
    awvalid && !awready |=> $stable(awaddr)
  );

  // AXI protocol: AWLEN must be stable during valid
  AST_AW_LEN_STABLE: assert property (@(posedge clk) disable iff (reset)
    awvalid && !awready |=> $stable(awlen)
  );
endinterface
```

### Protocol Checkers

Protocol checkers are comprehensive assertion packages that verify all rules of a standard protocol. They are typically provided as verification IP (VIP) or developed as reusable assertion libraries.

**Common protocol checkers:**
- AXI/AHB/APB protocol checkers (ARM AMBA specifications).
- PCIe TLP/DLLP protocol checkers.
- USB protocol checkers (token, data, handshake packets).
- DDR/LPDDR protocol checkers (command sequencing, timing).
- Ethernet/IP/TCP protocol checkers.

Protocol checkers typically contain hundreds of assertions covering every protocol rule, significantly reducing the chance of protocol-level bugs escaping to silicon.

## Assertion Placement Strategy

### Where to Place Assertions

1. **Module interfaces**: Every module input and output should have at least basic protocol assertions.
2. **State machines**: Assert legal transitions, no deadlock, and reachability of all states.
3. **FIFOs and queues**: Assert overflow/underflow conditions, pointer integrity, and count consistency.
4. **Arbiters**: Assert mutual exclusion, fairness, and no starvation.
5. **Data paths**: Assert data integrity through pipelines, FIFOs, and crossbar switches.
6. **Control signals**: Assert one-hot encoding, valid ranges, and proper sequencing.
7. **Clock domain crossings**: Assert synchronizer protocols and data stability.

### Assertion Density Guidelines

Industry best practice recommends:
- **2-5 assertions per output signal**: Check that each output is generated correctly under all conditions.
- **1 assertion per state machine transition**: Verify legal transitions and absence of illegal ones.
- **Invariant assertions for every data structure**: FIFO counts, pointer relationships, queue lengths.
- **Protocol assertions on every bus interface**: Complete protocol compliance checking.

A well-asserted design typically has 1 assertion for every 5-10 lines of RTL code.

## X-Propagation in Assertions

### The X Problem

In four-state simulation, uninitialized or indeterminate signals carry the value X. X-propagation through logic can mask bugs or create false assertion failures.

### X-Aware Assertions

By default, SVA treats X pessimistically in Boolean contexts: `if (X)` evaluates to false. This means assertions may not fire when they should if control signals are X.

**Strategies for X-aware assertions:**

```systemverilog
// Check for X values explicitly
AST_NO_X_DATA: assert property (@(posedge clk) disable iff (reset)
  valid |-> !$isunknown(data)
) else $error("Data is X while valid is asserted");

// Use $isunknown to detect X on control signals
AST_NO_X_CTRL: assert property (@(posedge clk) disable iff (reset)
  !$isunknown({enable, mode, select})
) else $error("Control signal is X");
```

### X-Propagation Verification

Dedicated X-propagation analysis identifies cases where X values on inputs can reach outputs or affect control flow. Tools like Synopsys VCS Xprop and Cadence Xcelium X-propagation mode provide enhanced X-handling that is more pessimistic than default simulation.

```bash
# VCS X-propagation mode
vcs -xprop=tmerge  # Applies X-propagation through muxes and conditional operators

# Xcelium X-propagation mode
xrun -xprop f      # Forward X-propagation mode
```

## Bind Statements

The `bind` construct attaches assertions to a module without modifying the RTL source code. This is essential for:
- Verifying third-party IP whose source cannot be modified.
- Maintaining separation between design and verification code.
- Deploying different assertion sets for different verification contexts.

```systemverilog
// Assertion module
module fifo_assertions #(parameter DEPTH = 16) (
  input logic clk, reset,
  input logic push, pop, full, empty,
  input logic [$clog2(DEPTH):0] count
);
  AST_NO_OVERFLOW: assert property (@(posedge clk) disable iff (reset)
    count <= DEPTH);
  // ... more assertions
endmodule

// Bind to the DUT without modifying its source
bind fifo fifo_assertions #(.DEPTH(DEPTH)) u_assertions (.*);
```

### Bind Scope

- **Module bind**: Attaches to every instance of the specified module.
- **Instance bind**: Attaches to a specific instance only.

```systemverilog
// Bind to all instances of 'fifo'
bind fifo fifo_assertions u_assert (.*);

// Bind to a specific instance only
bind tb.dut.u_rx_fifo fifo_assertions u_assert (.*);
```

## Assertion Coverage

### Tracking Assertion Activity

It is critical to verify that assertions are actually being exercised — an assertion that never fires provides no verification value (vacuous pass).

**Assertion coverage metrics:**
- **Attempt count**: Number of times the assertion's antecedent was evaluated.
- **Pass count**: Number of successful evaluations.
- **Fail count**: Number of failures (should be 0 for a passing regression).
- **Vacuous pass count**: Number of evaluations where the antecedent was false (property trivially true).

### Cover Properties

Pair each assertion with a cover property to verify that the trigger condition has been exercised:

```systemverilog
// Assertion: if valid, data must not be X
AST_VALID_DATA: assert property (@(posedge clk) valid |-> !$isunknown(data));

// Coverage: verify that valid has been asserted
COV_VALID_SEEN: cover property (@(posedge clk) valid);

// Coverage: verify that the interesting case (valid with specific data) is exercised
COV_VALID_MAX_DATA: cover property (@(posedge clk) valid && data == '1);
```

## Assertion Debug

### Failure Analysis

When an assertion fails:
1. **Identify the assertion**: The failure log contains the assertion name, module instance, and simulation time.
2. **Examine the waveform**: Open the waveform at the failure time and examine the signals in the assertion expression.
3. **Trace the root cause**: Follow the signal path backward from the assertion failure to the originating event.
4. **Classify**: Is this an RTL bug, a testbench issue, or an incorrect assertion?

### Common Causes of Assertion Failures

- **RTL bugs**: The most valuable outcome — the assertion caught a real design error.
- **Incorrect assertions**: The assertion does not accurately reflect the specification.
- **Testbench issues**: The stimulus violates assumptions that the assertion depends on.
- **Reset timing**: Assertions firing during reset before the design reaches a stable state.

## Assertion Methodology in Practice

### Assertion-Driven Development

Write assertions before or concurrently with RTL development:
1. Extract assertions from the specification.
2. Write assertions and `assume` constraints.
3. Develop RTL to satisfy the assertions.
4. Run formal proofs and simulation simultaneously.

This "shift-left" approach catches design issues earlier and produces better-documented designs.

### Assertion Reuse

Assertions written for block-level verification should be preserved and active at subsystem and SoC levels. The `bind` mechanism enables this without modifying higher-level testbenches.

### Assertion Libraries

Maintain a library of reusable assertion templates for common patterns:
- FIFO overflow/underflow checkers.
- One-hot/one-cold signal checkers.
- Handshake protocol checkers (valid/ready, req/ack).
- Counter overflow/underflow checkers.
- Bus protocol compliance checkers.

## Best Practices

1. **Name all assertions** with a consistent prefix (AST_ for assert, COV_ for cover, ASM_ for assume) and descriptive names.
2. **Use `disable iff` for reset** to prevent false failures during reset.
3. **Always check for vacuity** using cover properties or assertion coverage reports.
4. **Write assertions as close to the design as possible** using bind when RTL cannot be modified.
5. **Treat assertion failures as high-priority bugs** — do not disable assertions to make tests pass.
6. **Pair assertions with coverage** to ensure the verification plan's assertion goals are met.

## Summary

Assertion-Based Verification embeds executable checks throughout the design and testbench, catching bugs at their source. White-box assertions verify internal invariants; interface assertions enforce protocol compliance; protocol checkers provide comprehensive standard-protocol verification. X-propagation awareness prevents X-related masking. Bind statements enable assertion deployment without modifying RTL. Assertion coverage ensures assertions are exercised, preventing vacuous passes. ABV is one of the highest-ROI verification techniques and should be a foundational element of every verification methodology.
