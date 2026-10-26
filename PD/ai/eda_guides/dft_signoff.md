# DFT Signoff: Verification, Coverage, and Timing Closure for Test

## DFT Signoff Overview

DFT signoff is the formal verification milestone confirming that all test infrastructure is correctly implemented, coverage targets are met, test patterns are validated, and timing closure is achieved for all test modes. DFT signoff occurs before tape-out and is as critical as functional signoff, STA signoff, and physical verification signoff. A DFT deficiency discovered post-silicon can mean the difference between a testable chip and an untestable one -- and an untestable chip cannot be shipped.

DFT signoff encompasses four major areas: structural DFT verification (DRC), fault coverage achievement, pattern validation, and test-mode timing closure.

## DFT Design Rule Checking (DRC)

DFT DRC verifies the structural integrity of all test infrastructure. DRC must pass cleanly before ATPG can generate valid patterns.

### Scan DRC Rules

**Chain connectivity**: Every scan chain must be fully connected from scan-in pad to scan-out pad. No opens, no shorts between chains, no feedback loops. The tool traces each chain and reports any breaks or anomalies.

**Flip-flop inclusion**: All scannable flip-flops must be in scan chains. Any flip-flop not in a chain is flagged. Intentional exclusions (dont_scan) must be documented and justified.

**Clock domain separation**: Verify that scan chain connections respect clock domain constraints. Lockup latches must be present at positive-edge to negative-edge transitions within chains.

**Asynchronous control**: All asynchronous set/reset signals must be held inactive during scan shift. An active reset during shift would overwrite shifted data. DRC checks that set/reset pins are either tied off or controlled by scan-accessible signals.

**Scan enable**: SE must reach all scan flip-flops. DRC verifies SE connectivity and flags any flip-flops with unconnected or incorrectly connected SE.

### Compression DRC

**Decompressor/compressor connectivity**: Verify codec connections to internal chains and external channels.

**X-source identification**: Identify all sources of unknown values that could reach the compressor. Flag unmasked X-sources.

**Chain balance**: Internal chains within a compression domain must be balanced (equal length within tolerance).

### BIST DRC

**MBIST coverage**: Every embedded memory must have MBIST coverage. Flag memories without BIST connections.

**MBIST interface**: Verify mux logic correctly switches between functional and BIST ports.

**LBIST structure**: Verify PRPG and MISR connections, polynomial correctness, and controller state machine completeness.

### JTAG DRC

**TAP controller**: Verify IEEE 1149.1 compliance -- all mandatory states and instructions implemented.

**Boundary scan**: Verify BSC on all I/O pads, correct cell types, and proper chain connectivity.

**BSDL validation**: Generate and validate BSDL file against the physical implementation.

## Coverage Signoff

### Coverage Targets

Coverage targets must be defined in the test plan and achieved before signoff:

| Fault Model | Consumer | Automotive | Safety-Critical |
|-------------|----------|------------|-----------------|
| Stuck-at TC | >97% | >99% | >99.5% |
| Transition TC | >93% | >97% | >98% |
| Cell-aware TC | >95% | >98% | >99% |
| ATPG effectiveness | >99% | >99.5% | >99.8% |

### Coverage Analysis

For signoff, the coverage report must include:

**Fault summary**: Total faults, detected, undetectable, ATPG-untestable, not-analyzed, blocked. Each category must be within acceptable limits.

**Block-level breakdown**: Coverage per hierarchical block. Identifies blocks dragging overall coverage down.

**Uncovered fault analysis**: Every undetected fault above a threshold must be categorized:
- Structurally untestable (tied logic, redundancy) -- acceptable
- ATPG effort limited -- increase effort or accept with justification
- DFT limitation -- requires design change or waiver
- Intentional exclusion -- documented reason (security, analog, etc.)

**Coverage waiver process**: Faults that cannot be covered must go through a formal waiver process:
1. Identify the fault and its location
2. Explain why it cannot be detected
3. Assess the risk (what physical defect would this fault represent?)
4. Obtain sign-off from DFT lead, design lead, and quality
5. Document in the test plan

### Multi-Model Coverage

Production test quality requires coverage across multiple fault models:
- Stuck-at alone is insufficient for modern process nodes
- Transition coverage catches timing defects missed by stuck-at
- Cell-aware catches intra-cell defects missed by both
- IDDQ catches bridging defects
- The combined coverage provides comprehensive defect detection

## Pattern Validation

### Gate-Level Pattern Simulation

Simulate all ATPG patterns on the gate-level netlist to verify:
- Pattern application sequence is correct
- Expected responses match simulation results
- No setup/hold violations in functional simulation
- Scan chain shift operates correctly

This is a full digital simulation (not ATPG's internal simulation) and serves as an independent verification.

### Timing-Annotated Pattern Simulation

Simulate with SDF back-annotation to verify at-speed patterns:
- Transition fault patterns must be simulated at functional timing
- Verify that at-speed capture meets timing with actual gate delays
- Identify any patterns that cause timing violations (these would be false failures on silicon)

### Pattern-Level Power Verification

Analyze power for the generated pattern set:
- Verify shift power stays within IR drop budget
- Verify capture power meets toggle budget
- Flag patterns with excessive switching activity
- Remove or regenerate high-power patterns

### ATE Compatibility Check

Before signoff, verify patterns are ATE-compatible:
- Pattern data fits in ATE memory (with compression)
- Pattern timing is achievable by the target ATE platform
- Total test time (all pattern sets) meets the test time budget
- Pattern format (STIL, WGL, binary) is correct for the ATE

## Test-Mode Timing Closure

### Test Mode SDC

Dedicated timing constraints for test modes:

**Shift mode constraints**:
```
create_clock -name SHIFT_CLK -period 10.0 [get_ports scan_clk]
set_case_analysis 1 [get_ports scan_enable]
set_case_analysis 1 [get_ports test_mode]
```

**Capture mode constraints (stuck-at)**:
```
create_clock -name CAPTURE_CLK -period 2.0 [get_ports func_clk]
set_case_analysis 0 [get_ports scan_enable]
set_case_analysis 1 [get_ports test_mode]
```

**At-speed capture constraints (transition)**:
```
create_clock -name AT_SPEED_CLK -period 1.0 [get_pins OCC/clk_out]
set_case_analysis 0 [get_ports scan_enable]
set_false_path -from [get_clocks SHIFT_CLK] -to [get_clocks AT_SPEED_CLK]
```

### Critical Timing Paths in Test Mode

**Scan enable path**: SE must meet setup at every scan flip-flop relative to the capture clock. This is often the most critical test-mode timing path because SE has enormous fanout and must transition from 1 to 0 just before the at-speed capture.

**Scan shift paths**: SI-to-SO paths must meet timing at shift frequency. Usually easy because shift is slow, but long chains or poorly routed chains can have issues.

**OCC paths**: Internal OCC timing must meet constraints. Clock mux control, pulse generation, and mode transition paths.

**Compression paths**: Decompressor-to-chain and chain-to-compressor paths must meet shift timing.

**BIST paths**: PRPG-to-chain and chain-to-MISR paths must meet timing at BIST operating frequency.

### Test Mode Timing Closure Flow

1. Add test mode constraints to SDC
2. Run STA in test mode (shift, capture, at-speed capture)
3. Fix timing violations (buffer insertion, gate sizing, routing optimization)
4. Verify fixes do not impact functional mode timing
5. Iterate until all test modes meet timing
6. Signoff with multi-mode multi-corner STA including all test modes

## DFT Signoff Checklist

### Pre-Signoff Verification
- [ ] DFT DRC clean (zero violations or all waived)
- [ ] Stuck-at coverage meets target
- [ ] Transition coverage meets target
- [ ] Cell-aware coverage meets target (if applicable)
- [ ] ATPG effectiveness >99%
- [ ] All uncovered faults analyzed and waived
- [ ] Pattern simulation passes (zero mismatches)
- [ ] Timing-annotated simulation passes for at-speed patterns
- [ ] Pattern power analysis within budget
- [ ] ATE memory and time budget met

### Structural Verification
- [ ] Scan chains verified (chain count, length, connectivity)
- [ ] Compression verified (ratio, X-handling, codec function)
- [ ] MBIST verified for all memories
- [ ] JTAG verified (TAP, boundary scan, BSDL)
- [ ] OCC verified (all modes, clock switching, pulse generation)

### Timing Verification
- [ ] Shift mode timing clean
- [ ] Stuck-at capture timing clean
- [ ] At-speed capture timing clean
- [ ] SE timing verified at all corners
- [ ] OCC timing verified

### Documentation
- [ ] Test plan updated with final coverage numbers
- [ ] Coverage waiver documents signed
- [ ] Pattern file manifest created
- [ ] ATE test program specification updated
- [ ] BSDL file validated and delivered

## Post-Silicon DFT Validation

After silicon arrives, DFT validation is the first activity:

1. **JTAG connectivity**: Verify TAP controller operation, read IDCODE
2. **Scan chain integrity**: Run flush patterns (shift known data through all chains)
3. **Compression validation**: Verify codec operation with simple compressed patterns
4. **MBIST execution**: Run all MBIST controllers, check pass/fail
5. **At-speed OCC**: Verify PLL lock and at-speed pulse generation
6. **Full pattern application**: Apply all production patterns and analyze results
7. **Coverage correlation**: Compare predicted coverage with actual defect detection
