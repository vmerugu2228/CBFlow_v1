# Code Coverage

## Overview

Code coverage is an automatically extracted metric that measures which structural elements of the RTL source code have been exercised during simulation. Unlike functional coverage (which is user-defined), code coverage is derived directly from the HDL code and does not require explicit definition by the verification engineer. Code coverage serves as a complementary metric to functional coverage: it reveals untested code regions that might harbor bugs, regardless of whether the verification plan explicitly targeted those regions.

## Coverage Types

### Statement Coverage (Line Coverage)

Statement coverage measures whether each executable statement in the RTL has been executed at least once during simulation.

```systemverilog
always @(posedge clk) begin
  if (enable) begin
    count <= count + 1;    // Statement 1 — covered?
    if (count == MAX) begin
      overflow <= 1'b1;    // Statement 2 — covered?
      count <= 0;          // Statement 3 — covered?
    end
  end
end
```

Statement coverage is the most basic code coverage type. 100% statement coverage means every line of code has been executed, but it does not guarantee that all decision paths have been tested.

### Branch Coverage (Decision Coverage)

Branch coverage measures whether each branch of every conditional statement (if/else, case, ternary) has been taken.

```systemverilog
always @(posedge clk) begin
  if (mode == 2'b00)        // Branch: mode == 00 (true/false)
    out <= data_a;
  else if (mode == 2'b01)   // Branch: mode == 01 (true/false)
    out <= data_b;
  else if (mode == 2'b10)   // Branch: mode == 10 (true/false)
    out <= data_c;
  else                       // Default branch
    out <= data_d;
end
```

Branch coverage requires that both the true and false outcomes of each decision have been exercised. For case statements, every case arm (including default) must be taken.

### Condition Coverage (Expression Coverage)

Condition coverage measures whether each Boolean sub-expression within a decision has been evaluated to both true and false independently.

```systemverilog
if (req && grant && !stall)  // 3 conditions: req, grant, !stall
  proceed <= 1'b1;
```

For this example, condition coverage requires:
- `req` evaluated to both 0 and 1.
- `grant` evaluated to both 0 and 1.
- `stall` evaluated to both 0 and 1.

**Modified Condition/Decision Coverage (MC/DC)** is a stronger criterion used in safety-critical designs: each condition must independently affect the decision outcome. MC/DC is required by DO-254 (airborne hardware) and similar safety standards.

### Toggle Coverage

Toggle coverage measures whether each signal (bit) in the design has transitioned from 0-to-1 and from 1-to-0 during simulation.

```
Signal: data[7:0]
  data[0]: 0->1 covered, 1->0 covered  ✓
  data[1]: 0->1 covered, 1->0 covered  ✓
  data[7]: 0->1 NOT covered, 1->0 NOT covered  ✗
```

Toggle coverage is particularly useful for:
- Detecting dead logic (bits that never toggle).
- Verifying data path connectivity.
- Ensuring all control signals are exercised.

Toggle coverage targets vary by design type: control logic typically requires 95%+, while data paths may have lower targets due to data-dependent toggling patterns.

### FSM Coverage

FSM (Finite State Machine) coverage measures:

- **State coverage**: Whether each defined state has been visited.
- **Transition coverage**: Whether each valid state transition has been exercised.
- **Arc coverage**: Whether every possible transition (including self-loops) has occurred.

```
FSM States: IDLE, ACTIVE, WAIT, DONE, ERROR
State coverage: 4/5 (ERROR never entered)
Transitions: 8/12 (some transitions from WAIT never exercised)
```

FSM coverage is critical because state machines are the primary control logic, and untested states or transitions are a common source of bugs.

## Coverage Collection

### Tool-Specific Commands

**Synopsys VCS**
```bash
# Compile with coverage enabled
vcs -cm line+cond+fsm+tgl+branch -cm_dir coverage.vdb

# Run simulation
simv -cm line+cond+fsm+tgl+branch -cm_name test_name

# Generate report
urg -dir coverage.vdb -report urgReport
```

**Cadence Xcelium**
```bash
# Compile and run with coverage
xrun -coverage all -covdut my_dut design.sv testbench.sv

# Merge and report
imc -exec merge_report.tcl
```

**Siemens Questa**
```bash
# Compile with coverage
vlog +cover=bcefst design.sv

# Run with coverage
vsim -coverage my_dut

# Merge and report
vcover merge merged.ucdb test1.ucdb test2.ucdb
vcover report merged.ucdb -output report.txt
```

### Coverage Scoping

Coverage should be collected on the DUT, not the testbench. Common scoping practices:
- **Include list**: Explicitly specify which modules to cover (preferred).
- **Exclude list**: Cover everything except specified modules.
- **Hierarchy-based**: Cover the DUT hierarchy starting from a specific instance.

```bash
# VCS: cover only the DUT hierarchy
vcs -cm_hier coverage_scope.cfg
# coverage_scope.cfg:
# +tree tb.dut
# -module testbench_pkg
```

## Coverage Merging

### Why Merge

No single simulation test covers the entire design. Coverage databases from hundreds or thousands of regression tests must be merged to produce the aggregate coverage view.

### Merge Strategies

- **Incremental merge**: Add new test results to an existing merged database. Efficient for nightly regressions.
- **Full merge**: Merge all databases from scratch. Used for milestone reports.
- **Hierarchical merge**: Merge at block level first, then combine block-level results for subsystem and SoC-level views.

### Seed-Based Coverage Tracking

Track which seeds contribute unique coverage:
```
Seed 12345: Covered bins A, B, C (3 unique)
Seed 67890: Covered bins D, E (2 unique)
Seed 11111: Covered bins A, B (0 unique — redundant)
```

Seeds that contribute no unique coverage can be deprioritized in regression, saving compute resources.

## Coverage Exclusions

### Types of Exclusions

- **Unreachable code**: Logic that cannot be activated due to design constraints (e.g., a configuration parameter disables a feature permanently).
- **Unused features**: Features that are documented as not supported in the current design revision.
- **Verification limitations**: Scenarios that are provably unreachable in the testbench environment but possible in silicon (these are high-risk exclusions).

### Exclusion Process

1. **Identify**: Code coverage analysis reveals uncovered items.
2. **Analyze**: Determine why the item is uncovered — is it a verification gap or unreachable code?
3. **Document**: Record the exclusion with technical justification (RTL reference, specification section, design team confirmation).
4. **Review**: All exclusions must be reviewed by a second engineer and approved by the verification lead.
5. **Implement**: Apply the exclusion in the coverage tool's database.

### Exclusion Files

```tcl
# VCS exclusion file
INSTANCE tb.dut.unused_block -toggle
MODULE debug_port -line -cond -branch
BLOCK BEGIN:ANNOTATION "Feature disabled" tb.dut.feature_x
```

## Coverage Analysis

### Gap Analysis Workflow

1. Generate merged coverage report.
2. Sort uncovered items by type (statement, branch, condition, toggle, FSM).
3. For each uncovered item:
   - Is this a real verification gap? Write a new test or constraint.
   - Is this unreachable code? Document and exclude with justification.
   - Is this redundant logic? Flag to the design team for potential RTL simplification.

### Coverage Report Interpretation

```
Module: my_controller
  Statement coverage: 97.2% (2,431 / 2,500)
  Branch coverage:    93.8% (1,407 / 1,500)
  Condition coverage: 89.5% (716 / 800)
  Toggle coverage:    91.3% (7,304 / 8,000)
  FSM coverage:
    State:      100% (8/8)
    Transition: 87.5% (21/24)
```

Branch and condition coverage below statement coverage is normal — branches require specific decision outcomes that may need targeted tests.

## Code Coverage Goals

### Industry Typical Targets

| Coverage Type | Block Level | Subsystem | SoC |
|--------------|-------------|-----------|-----|
| Statement | 100% | 98% | 95% |
| Branch | 100% | 95% | 90% |
| Condition | 95% | 90% | 85% |
| Toggle | 95% | 90% | 85% |
| FSM State | 100% | 100% | 100% |
| FSM Transition | 95% | 90% | 85% |

Targets vary by project criticality. Safety-critical designs (automotive, aerospace) may require 100% MC/DC coverage.

## Code Coverage Limitations

Code coverage has fundamental limitations:
- **Does not verify correctness**: Code may execute without producing correct results. A scoreboard with no checks would show 100% code coverage with zero verification value.
- **Missing feature detection**: If a feature is missing from the RTL, code coverage cannot detect it (there is no code to cover).
- **Combinational explosion**: Condition coverage for expressions with many terms produces exponential combinations.
- **Data-dependent paths**: Some code paths depend on specific data values that toggle coverage alone does not capture.

These limitations reinforce why code coverage must be used alongside functional coverage, not as a replacement.

## Best Practices

1. **Collect code coverage from the beginning** — do not wait until the end of the project.
2. **Use all coverage types together** — statement, branch, condition, toggle, and FSM provide complementary information.
3. **Scope coverage to the DUT** — excluding testbench and verification IP from code coverage metrics.
4. **Review exclusions rigorously** — every exclusion is a potential verification hole.
5. **Correlate with functional coverage** — high code coverage with low functional coverage indicates ineffective tests.
6. **Automate coverage collection and merging** in the regression infrastructure.

## Summary

Code coverage provides an automatically extracted measure of RTL structural exercise during simulation. Statement, branch, condition, toggle, and FSM coverage types each reveal different aspects of code utilization. Coverage merging across regression tests produces the aggregate view needed for sign-off. Exclusions must be documented and reviewed. While code coverage has limitations (it cannot verify correctness or detect missing features), it is an essential complement to functional coverage in achieving comprehensive verification closure.
