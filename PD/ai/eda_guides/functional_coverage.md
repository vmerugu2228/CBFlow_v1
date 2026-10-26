# Functional Coverage

## Overview

Functional coverage is a user-defined metric that measures whether the verification plan's intended scenarios have been exercised during simulation. Unlike code coverage (which is automatically extracted from the RTL), functional coverage is explicitly defined by the verification engineer based on the design specification. It answers the question: "Have we tested what we intended to test?" Functional coverage is the primary metric driving coverage-driven verification closure.

## Coverage Model Concepts

### Covergroups

A `covergroup` is the fundamental unit of functional coverage in SystemVerilog. It defines a collection of coverpoints and cross-coverage to be sampled at specific events.

```systemverilog
covergroup cg_bus_transaction @(posedge clk);
  option.per_instance = 1;
  option.name = "bus_txn_cov";

  cp_opcode:  coverpoint txn.opcode;
  cp_addr:    coverpoint txn.addr[31:28];
  cp_size:    coverpoint txn.size {
    bins small  = {[1:4]};
    bins medium = {[5:16]};
    bins large  = {[17:64]};
  }
endgroup
```

### Sampling Events

Coverage is sampled when the specified event occurs:
- **Clock edge**: `@(posedge clk)` — sample every clock cycle.
- **Explicit trigger**: Call `cg.sample()` from procedural code.
- **Transaction completion**: Sample in a UVM subscriber's `write()` function.

The UVM subscriber pattern is the most common approach in production testbenches:

```systemverilog
class my_coverage extends uvm_subscriber #(my_transaction);
  covergroup cg with function sample(my_transaction txn);
    cp_opcode: coverpoint txn.opcode;
  endgroup

  function void write(my_transaction t);
    cg.sample(t);
  endfunction
endclass
```

## Coverpoints

### Automatic Bins

When no bins are explicitly defined, SystemVerilog automatically creates bins based on the coverpoint expression's type:

```systemverilog
coverpoint txn.opcode;  // Auto-bins: one bin per enum value (or 64 auto-bins for integers)
```

The `option.auto_bin_max` setting controls the maximum number of automatic bins (default is 64).

### Explicit Bins

```systemverilog
coverpoint txn.addr {
  bins low_range    = {[32'h0000:32'h0FFF]};
  bins mid_range    = {[32'h1000:32'h7FFF]};
  bins high_range   = {[32'h8000:32'hFFFE]};
  bins max_addr     = {32'hFFFF};
  bins others       = default;
}
```

### Bin Types

- **`bins`**: Standard bins that contribute to coverage.
- **`illegal_bins`**: Values that should never occur. If sampled, a runtime error is flagged.
- **`ignore_bins`**: Values that are legal but should not count toward coverage (excluded from the coverage percentage).
- **`wildcard bins`**: Pattern-matched bins using `?` for don't-care bits. `wildcard bins aligned = {32'b????_????_????_????_????_????_????_00??};`

### Array Bins

```systemverilog
coverpoint txn.burst_length {
  bins individual[] = {[1:16]};  // One bin per value (16 bins)
  bins grouped[4]   = {[1:16]};  // 4 bins, each covering 4 values
}
```

## Transition Coverage

Transition bins capture sequences of values across successive samples:

```systemverilog
coverpoint txn.state {
  bins idle_to_active = (IDLE => ACTIVE);
  bins active_to_done = (ACTIVE => DONE);
  bins full_sequence  = (IDLE => ACTIVE => DONE => IDLE);
  bins any_to_error   = (IDLE, ACTIVE, DONE => ERROR);
}
```

Transition coverage is essential for verifying state machine behavior and protocol sequences.

## Cross Coverage

Cross coverage measures the Cartesian product of two or more coverpoints — ensuring that specific combinations of values have been observed.

```systemverilog
covergroup cg_protocol @(posedge clk);
  cp_opcode: coverpoint txn.opcode {
    bins read  = {OP_READ};
    bins write = {OP_WRITE};
    bins rmw   = {OP_RMW};
  }

  cp_size: coverpoint txn.size {
    bins byte_access = {1};
    bins word_access = {4};
    bins line_access = {64};
  }

  cp_priority: coverpoint txn.priority {
    bins low  = {[0:3]};
    bins high = {[4:7]};
  }

  // 3x3x2 = 18 cross bins
  cx_op_size_pri: cross cp_opcode, cp_size, cp_priority;
endgroup
```

### Cross Bin Filtering

Cross coverage can explode combinatorially. Use `binsof` and `intersect` to select specific cross bins:

```systemverilog
cx_op_size: cross cp_opcode, cp_size {
  // Only care about write + line access
  bins write_line = binsof(cp_opcode.write) && binsof(cp_size.line_access);

  // Ignore read + byte (not interesting)
  ignore_bins read_byte = binsof(cp_opcode.read) && binsof(cp_size.byte_access);
}
```

## Coverage Options

### Instance vs. Type Coverage

- **`option.per_instance = 1`**: Each instance of the covergroup maintains its own coverage data. Essential when multiple instances exist and each must independently achieve coverage.
- **Type-level coverage** (default): All instances share coverage. A bin is considered covered if any instance hits it.

### Goal and Weight

```systemverilog
covergroup cg;
  option.goal = 90;          // Consider covered at 90% (default 100%)
  option.weight = 2;         // Double weight in aggregate calculation

  cp_addr: coverpoint addr {
    option.goal = 100;       // This coverpoint requires 100%
    option.weight = 3;       // Triple weight within this covergroup
  }
endgroup
```

### At Least

```systemverilog
option.at_least = 5;  // Each bin must be hit at least 5 times
```

This prevents declaring a bin "covered" from a single accidental hit, increasing confidence.

## Coverage Closure Methodology

### The Coverage Closure Loop

1. **Initial runs**: Execute the base regression suite with constrained random tests.
2. **Coverage analysis**: Merge coverage databases from all tests. Identify uncovered bins and low-coverage cross products.
3. **Gap analysis**: For each coverage hole, determine the root cause:
   - Missing constraints (the random generator cannot reach the scenario).
   - Missing sequences (no test targets this combination).
   - Design behavior (the scenario is unreachable by design — requires `ignore_bins` or exclusion).
4. **Targeted closure**: Write new constraints, sequences, or directed tests to fill gaps.
5. **Re-run and merge**: Add new tests to regression and re-merge coverage.
6. **Iterate** until sign-off goals are met.

### Coverage Merging

Coverage databases from multiple simulations are merged to produce an aggregate view:

```bash
# VCS
urg -dir simv.vdb test1.vdb test2.vdb -dbname merged.vdb

# Xcelium
imc -exec merge_script.tcl

# Questa
vcover merge merged.ucdb test1.ucdb test2.ucdb
```

Merging is essential because no single test covers everything. The aggregate across the full regression suite is what matters.

### Exclusions

Some coverage points are unreachable by design (e.g., a cross bin combining mutually exclusive modes). These are excluded with justification:

```systemverilog
// In the coverage model
ignore_bins impossible = binsof(cp_mode.sleep) && binsof(cp_opcode.write);
```

Or excluded in the tool's coverage database with a documented waiver. Every exclusion must be reviewed and approved.

## Functional Coverage vs. Code Coverage

| Aspect | Functional Coverage | Code Coverage |
|--------|-------------------|---------------|
| Definition | User-defined | Automatically extracted |
| Measures | Specification features | Code structures |
| Can miss | Bugs in unspecified features | Nothing structural |
| Can falsely satisfy | If model is incomplete | If dead code exists |
| Relationship | What we intended to test | What code was exercised |

Both metrics are necessary. High code coverage with low functional coverage means tests exercise code but not meaningful scenarios. High functional coverage with low code coverage suggests incomplete RTL utilization or dead code.

## Coverage in UVM

### UVM Coverage Subscriber

```systemverilog
class my_cov_subscriber extends uvm_subscriber #(my_transaction);
  `uvm_component_utils(my_cov_subscriber)

  covergroup cg with function sample(my_transaction t);
    cp_op:   coverpoint t.opcode;
    cp_addr: coverpoint t.addr[15:12];
    cx_op_addr: cross cp_op, cp_addr;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();
  endfunction

  function void write(my_transaction t);
    cg.sample(t);
  endfunction
endclass
```

### Verification Plan Linkage

Modern tools (Cadence vManager, Synopsys Verdi/URG, Siemens Questa) support linking functional coverage to the verification plan. Each Vplan feature maps to specific covergroups and coverpoints, providing traceability from specification to coverage to tests.

## Best Practices

1. **Derive coverage from the specification**, not the implementation. Coverage should reflect what the design must do, not how it does it.
2. **Start with coarse bins and refine**. Begin with high-level feature coverage and add detail as needed during closure.
3. **Use cross coverage judiciously**. Unconstrained crosses create exponential bins; filter to meaningful combinations.
4. **Set meaningful `at_least` counts** (typically 3-10) to avoid coverage by accident.
5. **Review and document all exclusions**. Unreviewed exclusions hide verification holes.
6. **Merge early, merge often**. Regular coverage analysis reveals gaps before they block schedule.

## Summary

Functional coverage is the verification engineer's primary tool for measuring verification completeness against the specification. Covergroups, coverpoints, cross coverage, and transition bins provide a rich modeling language. Combined with the coverage-driven closure loop — analyze, target, re-run, merge — functional coverage guides the verification effort toward sign-off with quantifiable confidence.
