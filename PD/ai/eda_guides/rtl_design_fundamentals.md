# RTL Design Fundamentals

## Overview

Register Transfer Level (RTL) design is the abstraction layer where digital circuits are described in terms of data flow between registers and the combinational logic that transforms that data. RTL sits between algorithmic/behavioral descriptions and gate-level netlists, making it the primary entry point for synthesis-driven ASIC and FPGA design. Mastery of RTL fundamentals is essential for producing hardware that is functionally correct, synthesizable, and timing-clean.

## Combinational vs Sequential Logic

All digital circuits decompose into two fundamental categories.

### Combinational Logic

Combinational logic produces outputs that are purely a function of the current inputs, with no memory of past states. Examples include multiplexers, decoders, adders, and comparators. In Verilog, combinational logic is modeled with `always @(*)` blocks (or `always_comb` in SystemVerilog). The critical rule is that every path through the block must assign every output; failure to do so infers latches, which is almost always unintentional.

```verilog
always @(*) begin
  case (sel)
    2'b00: out = a;
    2'b01: out = b;
    2'b10: out = c;
    default: out = d;  // default prevents latch inference
  endcase
end
```

### Sequential Logic

Sequential logic incorporates storage elements (flip-flops or latches) whose outputs depend on both current inputs and previous state. Flip-flops are edge-triggered and are the backbone of synchronous design. In Verilog, sequential logic uses `always @(posedge clk)` blocks (or `always_ff` in SystemVerilog).

```verilog
always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    q <= 1'b0;
  else
    q <= d;
end
```

The separation of combinational and sequential logic into distinct always blocks is a widely adopted best practice. Mixing them in a single block makes the code harder to read, harder to lint, and more error-prone.

## Blocking vs Non-Blocking Assignments

This is the single most important coding rule in RTL design, and violations cause simulation-synthesis mismatches that are extremely difficult to debug.

### Blocking Assignments (=)

Blocking assignments execute sequentially within a procedural block. The right-hand side is evaluated and the left-hand side is updated immediately before the next statement executes. Use blocking assignments exclusively in combinational always blocks.

```verilog
always @(*) begin
  temp = a & b;       // temp is updated immediately
  out  = temp | c;    // uses the just-updated value of temp
end
```

### Non-Blocking Assignments (<=)

Non-blocking assignments schedule updates to occur at the end of the current simulation time step. All right-hand sides are evaluated first, then all left-hand sides are updated simultaneously. Use non-blocking assignments exclusively in sequential always blocks.

```verilog
always @(posedge clk) begin
  q1 <= d;    // both RHS evaluated using values at posedge
  q2 <= q1;   // this creates a proper two-stage pipeline
end
```

If blocking assignments were used in the sequential block above, `q2` would get the value of `d` (not the old `q1`), collapsing the pipeline into a single register. This is a classic bug.

### The Golden Rules

1. Use `=` (blocking) in `always @(*)` / `always_comb` blocks.
2. Use `<=` (non-blocking) in `always @(posedge clk)` / `always_ff` blocks.
3. Never mix blocking and non-blocking in the same always block.
4. Never assign the same signal from multiple always blocks.

## Sensitivity Lists

The sensitivity list determines when an always block is evaluated during simulation.

### Combinational Sensitivity Lists

For combinational logic, the sensitivity list must include every signal read within the block. Omitting a signal causes simulation-synthesis mismatch: simulation will not re-evaluate when the missing signal changes, but synthesis will create logic that responds to all inputs.

The wildcard `always @(*)` (Verilog-2001) or `always_comb` (SystemVerilog) automatically includes all read signals and should always be used for combinational logic. Never manually enumerate signals in combinational sensitivity lists.

### Sequential Sensitivity Lists

For sequential logic, the sensitivity list contains the clock edge and optionally the asynchronous reset edge:

```verilog
// Synchronous reset (reset not in sensitivity list)
always @(posedge clk) begin
  if (!rst_n) q <= 1'b0;
  else        q <= d;
end

// Asynchronous reset (reset IS in sensitivity list)
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) q <= 1'b0;
  else        q <= d;
end
```

With asynchronous reset, the reset condition must be the first `if` in the block. The reset polarity in the sensitivity list (negedge for active-low) must match the `if` condition.

## Always Blocks in Detail

### Verilog Always Block Types

Verilog has a single `always` keyword. The designer communicates intent through the sensitivity list and assignment type. This is error-prone because the compiler does not enforce the intent.

### SystemVerilog Always Block Types

SystemVerilog introduces three specialized always blocks that encode the designer's intent and allow the compiler to check for violations:

- **`always_comb`**: Models combinational logic. Automatically infers the sensitivity list. The compiler warns if the block infers latches or uses non-blocking assignments.
- **`always_ff`**: Models sequential logic (flip-flops). Requires an edge-sensitive sensitivity list. The compiler warns if blocking assignments are used.
- **`always_latch`**: Models level-sensitive latches. Rarely used intentionally but provides explicit intent when latches are needed.

Always prefer the SystemVerilog variants when the project allows it. They catch a large class of bugs at compile time.

### Continuous Assignments

The `assign` statement models simple combinational logic outside of always blocks:

```verilog
assign sum = a + b;
assign mux_out = sel ? a : b;
```

Continuous assignments are appropriate for single-line combinational expressions. For multi-line combinational logic with intermediate variables, use `always_comb`.

## Common Pitfalls and Best Practices

### Incomplete Assignments Cause Latches

If a signal is not assigned on all paths through a combinational block, synthesis infers a latch to hold the previous value. Always provide a default assignment at the top of the block or ensure all branches cover all outputs.

```verilog
always_comb begin
  out = '0;           // default assignment prevents latches
  if (en) out = data;
end
```

### Multi-Driven Signals

Assigning the same signal from multiple always blocks is illegal for synthesis and produces unpredictable simulation results. Use a single always block per signal, or combine drivers through explicit logic (e.g., a mux or OR gate).

### Clock and Reset as Logic Inputs

Never use the clock or reset signal as a data input to combinational logic. This breaks the synchronous design methodology and causes synthesis and timing analysis failures.

### Inferred vs Instantiated

RTL designers infer hardware by writing behavioral code that synthesis interprets. Alternatively, designers can instantiate library cells or IP directly. Inference is preferred for portability and readability, but instantiation is sometimes necessary for technology-specific cells (clock gating cells, memories, analog blocks).

### Hierarchy and Modularity

Partition the design into well-defined modules with clean interfaces. Each module should have a single responsibility. Avoid deep hierarchy that adds unnecessary levels without functional benefit, but also avoid monolithic modules that are difficult to read and constrain.

## Simulation and Synthesis Alignment

The ultimate goal of RTL coding discipline is to ensure that simulation behavior matches synthesized hardware behavior. The major sources of mismatch are:

1. Incomplete sensitivity lists (solved by `always_comb`).
2. Incorrect blocking/non-blocking usage.
3. Simulation-only constructs (`initial`, `$display`, delays) that have no synthesis equivalent.
4. Race conditions from multiple drivers or improper clocking.
5. Uninitialized signals that simulation resolves to X but synthesis resolves to 0 or 1.

Rigorous adherence to the coding rules above, combined with lint checks and formal equivalence checking, minimizes these risks.

## Summary

RTL design fundamentals come down to a small number of principles applied consistently: separate combinational from sequential logic, use the correct assignment type in each context, write complete sensitivity lists (or use `always_comb`/`always_ff`), and ensure every signal is assigned on every path. These rules are simple to state but demand discipline to follow across a large design. The reward is RTL that simulates correctly, synthesizes cleanly, and maps to timing-clean gates.
