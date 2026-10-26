# RTL Review Checklist

## Overview

RTL code review is the most effective method for catching design bugs before simulation. A structured review process with comprehensive checklists ensures that reviews are consistent, thorough, and efficient. Studies consistently show that code reviews catch 50-70% of all bugs, and bugs found in review cost 10-100x less to fix than bugs found in simulation, synthesis, or silicon. This guide provides a complete RTL review checklist organized by category, along with process guidelines for conducting effective reviews.

## Review Process

### Pre-Review Preparation

1. **Author prepares**: The RTL author ensures the code is lint-clean, compiles without errors, and has basic simulation passing before requesting review.
2. **Documentation ready**: The micro-architecture spec and register spec are available for the reviewer to reference.
3. **Diff available**: For modifications to existing code, provide a clear diff showing what changed and why.
4. **Review scope**: Define the scope (new module, bug fix, optimization) so the reviewer knows what to focus on.

### Review Meeting

1. **Author walks through the design**: Explain the purpose, architecture, and key design decisions.
2. **Reviewers ask questions**: Focus on understanding intent before judging implementation.
3. **Record all findings**: Every issue, question, and suggestion is captured.
4. **Classify findings**: Critical (must fix), Major (should fix), Minor (nice to fix).

### Post-Review

1. **Author addresses all findings**: Fix critical and major issues; document disposition of minor issues.
2. **Re-review if significant changes**: Major fixes require a follow-up review.
3. **Sign-off**: All reviewers approve before the code is committed.

## Code Review Checklist

### 1. Module Structure and Hierarchy

- [ ] Module interface matches the specification (port names, widths, directions).
- [ ] All ports have explicit direction (`input`, `output`, `inout`).
- [ ] All ports have explicit types and widths (no implicit nets).
- [ ] Module name matches the file name.
- [ ] One module per file.
- [ ] Parameters have sensible defaults and are validated.
- [ ] Localparams are used for derived constants (not overridable parameters).
- [ ] File header includes module name, description, and author.
- [ ] Naming conventions are followed consistently.

### 2. Combinational Logic

- [ ] Every output is assigned on every path (no latches unless intentional).
- [ ] Default assignments are at the top of every `always_comb` block.
- [ ] Every `case` statement has a `default` branch.
- [ ] `always_comb` (not `always @(*)`) is used for combinational logic.
- [ ] Blocking assignments (`=`) used exclusively in combinational blocks.
- [ ] No combinational loops (a signal depends on itself without a register).
- [ ] `casez` used instead of `casex` for don't-care matching.
- [ ] `unique case` or `priority case` used where appropriate (not pragmas).
- [ ] Ternary operator nesting limited to two levels maximum.

### 3. Sequential Logic

- [ ] `always_ff` (not `always @(posedge clk)`) is used for sequential logic.
- [ ] Non-blocking assignments (`<=`) used exclusively in sequential blocks.
- [ ] Asynchronous reset appears first in the `if` chain.
- [ ] Reset polarity in the sensitivity list matches the `if` condition.
- [ ] Reset values are constants (not signals, not expressions).
- [ ] Only registers that need reset have reset (data path registers may skip reset).
- [ ] Clock and reset are not used as data inputs to combinational logic.
- [ ] No same signal driven from multiple `always` blocks.

### 4. Clock Domain Crossings

- [ ] Every CDC crossing is identified and documented.
- [ ] Single-bit crossings use a two-FF synchronizer.
- [ ] Multi-bit crossings use Gray code, FIFO, or handshake protocol.
- [ ] No multi-bit bus crosses a domain boundary without a synchronization scheme.
- [ ] Reset synchronizers are present in every clock domain.
- [ ] Asynchronous FIFO depths are power of two.
- [ ] SpyGlass CDC (or equivalent) has been run and is clean.

### 5. Clock and Reset

- [ ] Only one clock edge per `always_ff` block.
- [ ] No internally generated clocks (use clock enables instead).
- [ ] Clock gating uses ICG cells or inference-friendly patterns.
- [ ] Reset strategy is documented (sync vs async, active polarity).
- [ ] Reset tree fanout is manageable (no single reset driving thousands of registers without buffering plan).
- [ ] Warm reset vs cold reset behavior is clearly separated.

### 6. Memory and FIFO

- [ ] SRAM interfaces match macro specifications.
- [ ] BIST mux is present for all SRAM instances.
- [ ] FIFO depth is justified by bandwidth analysis.
- [ ] FIFO overflow/underflow protections are in place.
- [ ] Async FIFO uses Gray-coded pointers.
- [ ] Memory read data is registered for timing.
- [ ] Byte-enable logic is correct for sub-word writes.

### 7. Arithmetic and Data Path

- [ ] Operand widths are appropriate (no unnecessary extension).
- [ ] Signed/unsigned operations match the intended behavior.
- [ ] Overflow/underflow conditions are handled or documented as acceptable.
- [ ] Division is avoided (or uses multi-cycle sequential implementation).
- [ ] Shift by power-of-two is used instead of multiply/divide where applicable.
- [ ] Fixed-point scaling is correct (binary point alignment verified).

### 8. FSM Review

- [ ] FSM uses two-block or three-block coding style.
- [ ] All states are reachable from the reset state.
- [ ] No deadlock states (every state has an exit condition).
- [ ] Default case returns to a safe state (e.g., IDLE).
- [ ] All outputs are assigned in every state (defaults at top of block).
- [ ] State encoding is appropriate (one-hot for speed, binary for area).
- [ ] FSM state coverage is verified in simulation.

## Synthesis Review Checklist

### 9. Synthesizability

- [ ] No `initial` blocks in synthesizable RTL (testbench only).
- [ ] No `$display`, `$monitor`, or other system tasks in synthesizable RTL.
- [ ] No delay statements (`#10`) in synthesizable RTL.
- [ ] No `force`/`release` in synthesizable RTL.
- [ ] No `real` type in synthesizable data paths.
- [ ] No tri-state on internal buses (use muxes).
- [ ] Synthesis warnings are reviewed and addressed.

### 10. Optimization Intent

- [ ] `dont_touch` is applied only where necessary and documented.
- [ ] Register retiming is possible for pipeline registers (no async reset on pipeline stages if retiming is intended).
- [ ] Resource sharing intent is documented (shared or dedicated operators).
- [ ] Clock gating patterns are correct for synthesis inference.
- [ ] Ungrouping decisions are documented.

### 11. Area Considerations

- [ ] No unnecessary register duplication.
- [ ] No oversized data paths (e.g., 64-bit bus where 32-bit suffices).
- [ ] Memories use compiled macros, not flip-flop arrays, for sizes above threshold.
- [ ] Parameterization does not create excessively large structures for the intended configuration.

## Timing Intent Review

### 12. Timing

- [ ] Critical paths are identified and documented.
- [ ] Logic depth between registers is reasonable for the target frequency.
- [ ] Wide muxes and deep priority chains are avoided on critical paths.
- [ ] Memory access time is accounted for in the pipeline design.
- [ ] Registered outputs on module boundaries for clean timing closure.
- [ ] High-fanout signals are identified for buffer insertion or replication.
- [ ] Multicycle paths are intentional and documented (not accidental).

### 13. Pipeline Design

- [ ] Pipeline stages are balanced (within 10-15% of each other).
- [ ] Valid/ready handshake follows protocol rules (no combinational loops).
- [ ] Pipeline flush mechanism exists where needed.
- [ ] Pipeline bypass/forwarding logic is correct.
- [ ] Latency matches the specification.

## DFT Review

### 14. Testability

- [ ] No manual clock gating (use ICG cells or inference).
- [ ] Synchronous reset on data path registers (for scan-friendliness).
- [ ] No internal tri-state buses.
- [ ] Minimal latch usage (latches complicate scan).
- [ ] SRAM wrappers include BIST mux interface.
- [ ] JTAG-accessible debug registers are identified.

## Power Review

### 15. Low Power

- [ ] Clock gating patterns are present for conditional registers.
- [ ] Registers are grouped by enable for efficient gating.
- [ ] Operand isolation is applied to large idle arithmetic blocks.
- [ ] Power domains are defined and align with module hierarchy.
- [ ] Isolation and retention strategies are documented.
- [ ] Memory banking is used for independent power control.

## Verification Interface Review

### 16. Verifiability

- [ ] All interfaces have protocol assertions.
- [ ] Internal invariants have assertions.
- [ ] Coverage points are defined for FSMs and critical functionality.
- [ ] Test hooks are available (scan, BIST, debug registers).
- [ ] Error injection points exist for fault testing.

## Common Review Findings

### Most Frequent Critical Issues

1. **Missing default case**: Causes latch inference.
2. **Blocking in sequential / non-blocking in combinational**: Simulation-synthesis mismatch.
3. **Unsynchronized CDC**: Metastability in silicon.
4. **Incomplete reset**: Registers start in unknown state.
5. **Combinational loop**: Causes simulation instability and synthesis failure.

### Most Frequent Major Issues

1. **Width mismatch on port connections**: Silent truncation or extension.
2. **Incorrect sensitivity list**: `always @(a, b)` missing `c`.
3. **FIFO depth too small**: Overflow under burst conditions.
4. **Missing overflow/underflow check**: Arithmetic wraps silently.
5. **Magic numbers**: Hard-coded values instead of parameters.

### Most Frequent Minor Issues

1. **Naming convention violations**: Inconsistent signal names.
2. **Missing comments**: No explanation of non-obvious logic.
3. **Dead code**: Unused signals or unreachable logic.
4. **Excessive hierarchy**: Wrappers without purpose.
5. **Formatting inconsistencies**: Mixed indentation or alignment.

## Review Metrics

Track the following metrics to improve the review process:

- **Defect density**: Findings per KLOC (thousand lines of code). Expect 5-15 findings per KLOC for new code.
- **Defect escape rate**: Bugs found in simulation that should have been caught in review.
- **Review velocity**: Lines reviewed per hour. Target 100-200 LOC per hour for thorough review.
- **Fix response time**: Time from review finding to fix committed.

## Summary

RTL review is a structured, checklist-driven process that catches the majority of design bugs at the lowest cost. The checklist covers module structure, combinational and sequential logic, CDC, clock/reset, memory, arithmetic, FSMs, synthesizability, timing intent, DFT, power, and verifiability. Conduct reviews early and often, treat critical findings as must-fix, and track metrics to continuously improve review effectiveness.
