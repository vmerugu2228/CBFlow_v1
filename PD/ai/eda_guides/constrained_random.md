# Constrained Random Verification

## Overview

Constrained random verification (CRV) is a methodology where the testbench generates stimulus automatically by randomizing transaction fields within user-defined constraints. Instead of manually specifying every input value, the verification engineer defines the legal input space through constraints, and the simulator's solver generates values that satisfy those constraints. CRV is the foundation of coverage-driven verification and is implemented in SystemVerilog as a first-class language feature.

## Randomization in SystemVerilog

### The `rand` and `randc` Keywords

Class members declared with `rand` are randomized each time `randomize()` is called. Members declared with `randc` (random cyclic) cycle through all possible values before repeating.

```systemverilog
class my_transaction extends uvm_sequence_item;
  rand  bit [31:0] addr;
  rand  bit [7:0]  data[];
  randc bit [2:0]  burst_type;
  rand  int        delay;
endclass
```

- `rand addr`: Each randomization independently selects a value.
- `randc burst_type`: All 8 possible values (0-7) are visited before any repeats.

### The `randomize()` Method

Every class with `rand`/`randc` members inherits a `randomize()` method:

```systemverilog
my_transaction txn = new();
if (!txn.randomize())
  `uvm_error("RAND_FAIL", "Randomization failed")
```

Randomization failure occurs when constraints are contradictory (unsatisfiable). Always check the return value.

### Inline Constraints with `with`

The `with` clause adds constraints at the point of randomization, supplementing (not replacing) the class constraints:

```systemverilog
assert(txn.randomize() with {
  addr inside {[32'h1000:32'h1FFF]};
  data.size() == 64;
});
```

This is essential for test-specific customization without modifying the transaction class.

## Constraint Blocks

### Basic Constraints

```systemverilog
class my_transaction extends uvm_sequence_item;
  rand bit [31:0] addr;
  rand bit [7:0]  length;
  rand bit        write;

  constraint c_addr_align {
    addr[1:0] == 2'b00;  // Word-aligned
  }

  constraint c_length_range {
    length inside {[1:16]};
  }

  constraint c_addr_write {
    write -> addr inside {[32'h0000:32'h0FFF]};
  }
endclass
```

### Constraint Types

- **Value constraints**: Restrict a variable to specific values or ranges.
- **Relational constraints**: Express relationships between variables (`a < b`, `addr + length < MAX`).
- **Implication constraints**: Conditional constraints using `->` (if-then) or `if-else`.
- **Iterative constraints**: Apply constraints to array elements using `foreach`.

### Implication and Conditional Constraints

```systemverilog
constraint c_protocol {
  // Implication: if write, data must be non-zero
  write -> data != 0;

  // If-else: different address ranges for read vs write
  if (write) {
    addr inside {[32'h0000:32'h7FFF]};
  } else {
    addr inside {[32'h8000:32'hFFFF]};
  }
}
```

### Array Constraints

```systemverilog
constraint c_array {
  data.size() inside {[4:128]};
  foreach (data[i]) data[i] != 8'hFF;
  unique {data};  // All elements must be unique
}
```

### Soft Constraints

Soft constraints can be overridden by hard constraints without causing randomization failure:

```systemverilog
constraint c_default_delay {
  soft delay inside {[1:10]};
}
```

A test can override: `txn.randomize() with { delay == 100; }` — the soft constraint yields.

## Distributions

### `dist` Operator

The `dist` operator specifies weighted random distributions:

```systemverilog
constraint c_weighted {
  addr dist {
    [32'h0000:32'h00FF] := 10,  // Each value gets weight 10
    [32'h0100:32'h0FFF] :/ 20,  // Total range gets weight 20
    32'hDEAD_BEEF       := 5
  };
}
```

- **`:=`** assigns the weight to each value in the range individually.
- **`:/`** distributes the weight across the entire range.

### Practical Distribution Patterns

```systemverilog
// Bias toward boundary values
constraint c_boundary_bias {
  length dist {
    1       := 20,    // Minimum value: high weight
    [2:14]  :/ 40,    // Middle range: moderate weight
    15      := 20,    // Near-maximum: high weight
    16      := 20     // Maximum value: high weight
  };
}
```

Distributions are invaluable for hitting corner cases: by weighting boundary values, error codes, and edge conditions, the random generator naturally exercises them more frequently.

## Solve Order

### The `solve...before` Construct

When constraints create dependencies between variables, `solve...before` controls the order of resolution:

```systemverilog
constraint c_mode_dependent {
  mode inside {0, 1, 2};
  if (mode == 0) length inside {[1:4]};
  if (mode == 1) length inside {[5:16]};
  if (mode == 2) length inside {[17:64]};

  solve mode before length;
}
```

Without `solve...before`, the solver might favor `mode == 2` because it has the most valid `length` values. With `solve mode before length`, `mode` is selected uniformly first, then `length` is solved within the mode-specific range.

### When to Use Solve Order

Use `solve...before` when:
- A small enumeration controls a larger dependent range.
- Uniform distribution over the controlling variable is desired.
- Probability distortion due to constraint interactions is observed.

## Constraint Management

### Enabling and Disabling Constraints

```systemverilog
txn.c_addr_align.constraint_mode(0);  // Disable alignment constraint
txn.randomize();  // Randomize without alignment
txn.c_addr_align.constraint_mode(1);  // Re-enable
```

### Randomization Mode Control

```systemverilog
txn.addr.rand_mode(0);  // Exclude addr from randomization
txn.addr = 32'hCAFE_0000;  // Set manually
txn.randomize();  // Randomize other fields only
```

### Constraint Inheritance

Derived classes inherit all constraints from the base class and can add new ones:

```systemverilog
class error_transaction extends my_transaction;
  constraint c_error_addr {
    addr inside {[32'hFFFF_0000:32'hFFFF_FFFF]};  // Error address range
  }
endclass
```

If the inherited and derived constraints conflict, randomization fails. Use `constraint_mode()` to selectively disable base class constraints.

## Pre/Post Randomization

### `pre_randomize()` and `post_randomize()`

```systemverilog
function void pre_randomize();
  // Set up state before randomization
  if (test_mode == ERROR_INJECT)
    c_normal_addr.constraint_mode(0);
endfunction

function void post_randomize();
  // Calculate derived fields after randomization
  checksum = calculate_crc(data);
  parity = ^data;
endfunction
```

`post_randomize()` is commonly used for calculating CRCs, checksums, parity bits, and other derived values that depend on the randomized fields.

## Functional Coverage Integration

Constrained random verification is incomplete without functional coverage to measure what has been generated. The feedback loop is:

1. **Randomize**: Generate transactions with constraints.
2. **Simulate**: Drive transactions into the DUT.
3. **Collect coverage**: Sample coverpoints on the generated and observed transactions.
4. **Analyze gaps**: Identify uncovered bins and cross-coverage holes.
5. **Refine constraints**: Add new constraints, adjust distributions, or write directed sequences to close coverage gaps.

## Common Pitfalls

### Over-Constraining

Too many constraints reduce the randomization space, making the stimulus predictable and preventing exploration of unexpected scenarios. Start with minimal constraints and add only what the protocol requires.

### Under-Constraining

Too few constraints generate illegal stimulus that fails protocol checks rather than exercising interesting corners. Balance is key.

### Solver Performance

Complex constraints (large arrays, nested implications, multiple `unique` clauses) can slow the constraint solver significantly. Profile randomization time and simplify constraints if they become a bottleneck.

### Randomization Stability

Changing constraint order or adding unrelated constraints can alter the random sequence for a given seed. This "butterfly effect" makes regression debug challenging. Use `std::randomize()` with explicit seed control for reproducible results.

## Summary

Constrained random verification automates stimulus generation while keeping it within legal bounds. SystemVerilog provides a rich constraint language including ranges, distributions, implications, arrays, and solve ordering. Combined with functional coverage, CRV enables efficient exploration of vast input spaces, discovering bugs that directed tests would miss. Mastering constraints, distributions, and the interplay with coverage collection is essential for modern verification engineers.
