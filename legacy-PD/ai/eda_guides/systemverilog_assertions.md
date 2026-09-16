# SystemVerilog Assertions (SVA)

## Overview

SystemVerilog Assertions (SVA) are a formal specification language embedded within SystemVerilog for expressing temporal properties of digital designs. Assertions serve as executable specifications: they continuously monitor the design during simulation and can be formally proven using model checking tools. SVA is the primary assertion language used in the semiconductor industry and is supported by all major EDA tool vendors.

## Assertion Types

### Immediate Assertions

Immediate assertions are procedural statements that check a condition at a specific point in simulation time. They execute like any other procedural statement — in the context of an `always`, `initial`, or task/function block.

```systemverilog
always @(posedge clk) begin
  assert (grant |-> request)
    else $error("Grant asserted without request");
end
```

**Deferred immediate assertions** (introduced in SystemVerilog 2012) postpone evaluation to the Observed or Reactive region, avoiding race conditions with NBA (Non-Blocking Assignment) updates:

```systemverilog
always @(posedge clk) begin
  assert #0 (data_valid !== 1'bx)
    else $error("data_valid is X");
end
```

- `assert #0` evaluates in the Observed region.
- `assert final` evaluates in the Postponed region (guaranteed stable values).

### Concurrent Assertions

Concurrent assertions describe temporal behavior across multiple clock cycles. They are sampled at clock edges and evaluate sequences and properties over time.

```systemverilog
assert property (@(posedge clk) disable iff (reset)
  req |-> ##[1:3] ack
);
```

This asserts that whenever `req` is high, `ack` must go high within 1 to 3 clock cycles (unless `reset` is active). Concurrent assertions are the workhorse of SVA, enabling specification of complex protocol rules.

## Sequences

Sequences describe temporal patterns of signal values across clock cycles.

### Basic Sequence Operators

- **`##N`**: Cycle delay. `a ##2 b` means `a` is true, then after exactly 2 cycles, `b` is true.
- **`##[M:N]`**: Delay range. `a ##[1:5] b` means `b` occurs 1 to 5 cycles after `a`.
- **`##[0:$]`**: Unbounded delay (eventually). `a ##[0:$] b` means `b` eventually follows `a`.

### Sequence Combinators

- **`and`**: Both sequences complete, starting from the same point.
- **`or`**: Either sequence completes.
- **`intersect`**: Both sequences complete and have the same length.
- **`within`**: One sequence completes within the time span of another.
- **`throughout`**: An expression holds true throughout a sequence.
- **`first_match`**: Matches only the first successful completion of a sequence.

### Repetition Operators

- **`[*N]`**: Consecutive repetition. `a[*3]` means `a` is true for 3 consecutive cycles.
- **`[*M:N]`**: Repetition range. `a[*2:5]` means `a` is true for 2 to 5 consecutive cycles.
- **`[->N]`**: Goto repetition. `a[->3]` means `a` becomes true exactly 3 times (not necessarily consecutive).
- **`[=N]`**: Non-consecutive repetition. Similar to goto but the match point is the cycle when the count is reached, regardless of trailing cycles.

### Named Sequences

```systemverilog
sequence handshake;
  req ##[1:5] ack ##1 !req ##1 !ack;
endsequence
```

Named sequences promote reuse and readability. They can accept arguments:

```systemverilog
sequence delayed_signal(sig, delay);
  ##delay sig;
endsequence
```

## Properties

Properties build on sequences to express complete verification intent. Properties add implication operators and temporal logic.

### Implication Operators

- **`|->` (overlapping implication)**: If the antecedent matches, the consequent must begin in the same cycle the antecedent completes.
- **`|=>` (non-overlapping implication)**: If the antecedent matches, the consequent must begin one cycle after the antecedent completes. Equivalent to `|-> ##1`.

```systemverilog
property req_ack_protocol;
  @(posedge clk) disable iff (reset)
  req |-> ##[1:3] ack;
endproperty
```

### Vacuous Success

If the antecedent of an implication never matches, the property is "vacuously true." This is a common verification pitfall — a property may appear to pass simply because its trigger condition never occurred. Coverage of assertion antecedents is essential to detect vacuous passes.

### Property Operators

- **`not`**: Negation. `not property_p` holds if `property_p` does not hold.
- **`if...else`**: Conditional property. Different properties checked based on a condition.
- **`strong()` / `weak()`**: Strong sequences must complete (used in formal); weak sequences may not (default in simulation).

## Assert, Cover, Assume, Restrict

SVA provides four directives that determine how a property is used:

### Assert

```systemverilog
assert property (req_ack_protocol)
  else $error("Protocol violation: ack not received");
```

The assertion fires an error if the property fails during simulation. In formal verification, the tool attempts to prove the property holds for all possible inputs.

### Cover

```systemverilog
cover property (@(posedge clk) req ##[1:3] ack);
```

Cover directives track whether a property (or sequence) has been observed during simulation. They do not flag errors — they collect coverage. This is essential for verifying that interesting scenarios have been exercised.

### Assume

```systemverilog
assume property (@(posedge clk) disable iff (reset)
  !req || data_valid
);
```

In formal verification, `assume` constrains the input space — the tool treats the assumption as an axiom and only explores states where it holds. In simulation, `assume` behaves like `assert`. Assumptions are critical for making formal proofs tractable.

### Restrict

```systemverilog
restrict property (@(posedge clk) $fell(reset) |-> ##[0:$] !reset);
```

`restrict` is similar to `assume` but is used exclusively in formal verification to restrict the state space exploration. It has no effect in simulation. Typical use: constraining reset behavior, clock relationships, or other environmental conditions.

## Clocking and Reset

### Clock Specification

Every concurrent assertion must have a clocking event:

```systemverilog
// Inline clock
assert property (@(posedge clk) a |-> b);

// Default clocking block
default clocking cb @(posedge clk);
  property p; a |-> b; endproperty
endclocking
```

### Disable Condition

The `disable iff` clause specifies an asynchronous reset condition. When active, the assertion is deactivated without firing:

```systemverilog
assert property (@(posedge clk) disable iff (reset || !power_good)
  req |-> ##[1:5] ack
);
```

## Local Variables in Sequences

SVA supports local variables within sequences for capturing and propagating values across cycles:

```systemverilog
sequence data_integrity;
  int captured_data;
  (req, captured_data = data_in) ##[1:5] (ack && data_out == captured_data);
endsequence
```

Local variables enable checking data consistency across pipeline stages, multi-cycle operations, and protocol sequences where values must be preserved.

## System Functions in SVA

SVA provides built-in system functions for common temporal patterns:

- **`$rose(signal)`**: True when signal transitions from 0 to 1.
- **`$fell(signal)`**: True when signal transitions from 1 to 0.
- **`$stable(signal)`**: True when signal value is unchanged from previous cycle.
- **`$changed(signal)`**: True when signal value changed from previous cycle.
- **`$past(signal, N)`**: Returns the value of signal N cycles ago.
- **`$onehot(signal)`**: True when exactly one bit is set.
- **`$onehot0(signal)`**: True when zero or one bit is set.
- **`$countones(signal)`**: Returns number of bits set to 1.

## Practical Guidelines

### Assertion Density

Industry best practice recommends 2-5 assertions per RTL module for every output signal, state machine transition, and critical internal node. High assertion density improves debug productivity by localizing failures closer to the root cause.

### Naming Conventions

Name assertions descriptively to improve waveform readability and log parsing:

```systemverilog
AST_REQ_ACK_HANDSHAKE: assert property (req_ack_protocol);
COV_BURST_LENGTH_MAX: cover property (burst_len == MAX_BURST);
```

### X-Propagation

By default, SVA treats X values pessimistically in Boolean expressions (X causes assertion failure). Be aware of this when writing assertions for signals that may legitimately be X during reset or initialization.

### Bind Statements

The `bind` construct allows assertions to be placed in a separate file and bound to the DUT module without modifying RTL source:

```systemverilog
bind my_module my_assertions #(.WIDTH(8)) u_assertions (.*);
```

This is critical for IP reuse where the RTL source cannot be modified.

## Summary

SystemVerilog Assertions provide a concise, expressive language for specifying temporal properties. Immediate assertions handle point-in-time checks; concurrent assertions verify multi-cycle protocols. Sequences and properties compose into powerful specifications. Assert, cover, assume, and restrict directives connect properties to simulation and formal engines. SVA is foundational to modern assertion-based verification and is used throughout block, subsystem, and SoC-level verification environments.
