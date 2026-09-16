# RTL Performance Optimization

## Overview

Performance optimization at the RTL level is about achieving the target clock frequency while meeting area and power budgets. The synthesis tool transforms RTL into gates, but the quality of that transformation depends heavily on the RTL structure. A skilled RTL designer writes code that gives the synthesis tool the best possible starting point for optimization. This guide covers critical path analysis, logic depth reduction, retiming, resource sharing, and architectural techniques for meeting aggressive timing targets.

## Critical Path Analysis

### Identifying the Critical Path

The critical path is the longest combinational delay between any two sequential elements (flip-flop to flip-flop). It determines the maximum clock frequency.

```tcl
# Synopsys DC: report timing on worst path
report_timing -max_paths 10 -sort_by slack

# Cadence Genus
report_timing -max_paths 10
```

### Anatomy of a Critical Path

```
FF_src -> [combo logic] -> [combo logic] -> ... -> FF_dst

Timing budget: T_clk = T_cq + T_combo + T_setup + T_skew + T_margin
  T_cq:     clock-to-Q of source flip-flop
  T_combo:  total combinational delay
  T_setup:  setup time of destination flip-flop
  T_skew:   clock skew between source and destination
  T_margin: design margin (OCV, jitter, etc.)
```

The available time for combinational logic is:

```
T_combo_available = T_clk - T_cq - T_setup - T_skew - T_margin
```

### What Makes Paths Slow

1. **Long logic chains**: Deep combinational logic between registers.
2. **Wide muxes**: Large multiplexers with many inputs.
3. **Long carry chains**: Wide adders or comparators without fast carry architectures.
4. **High fanout nets**: Signals driving many loads require buffer chains that add delay.
5. **Memory access**: SRAM read access time is often on the critical path.
6. **Cross-hierarchy boundaries**: Unoptimized boundaries between modules.

## Logic Depth Reduction

### Restructuring If-Else Chains

Deep if-else chains create priority logic with cascaded muxes:

```systemverilog
// Deep priority chain: 4 levels of mux logic
always_comb begin
  if (cond_a)      out = val_a;
  else if (cond_b) out = val_b;
  else if (cond_c) out = val_c;
  else if (cond_d) out = val_d;
  else             out = val_default;
end
```

If conditions are mutually exclusive, convert to a parallel structure:

```systemverilog
// Parallel mux: 1 level of logic (one-hot select)
always_comb begin
  unique case (1'b1)
    cond_a:  out = val_a;
    cond_b:  out = val_b;
    cond_c:  out = val_c;
    cond_d:  out = val_d;
    default: out = val_default;
  endcase
end
```

### Reducing Arithmetic Depth

When multiple operations chain together, restructure for minimum depth:

```systemverilog
// BAD: serial chain (3 adder levels)
wire [31:0] sum = a + b + c + d;
// Synthesis may create: ((a + b) + c) + d

// GOOD: balanced tree (2 adder levels)
wire [31:0] sum_ab = a + b;
wire [31:0] sum_cd = c + d;
wire [31:0] sum    = sum_ab + sum_cd;
```

The balanced tree reduces the logic depth from O(N) to O(log N) for N operands.

### Pre-Computation

Move computation before the select point to reduce the post-select critical path:

```systemverilog
// BAD: select then compute (mux + adder on critical path)
wire [31:0] operand = sel ? a : b;
wire [31:0] result  = operand + c;

// GOOD: compute both then select (adder and mux in parallel, then mux only)
wire [31:0] result_a = a + c;
wire [31:0] result_b = b + c;
wire [31:0] result   = sel ? result_a : result_b;
```

This trades area (two adders instead of one) for timing (shorter critical path). Use this technique selectively on actual critical paths, not everywhere.

## Pipelining

Insert registers to break long combinational paths into shorter stages.

```systemverilog
// Unpipelined: 40ns combinational delay -> max 25 MHz
wire [31:0] result = complex_function(a, b, c, d);

// Pipelined: 10ns per stage -> 100 MHz
logic [31:0] stage1_out;
always_ff @(posedge clk) stage1_out <= partial_func_1(a, b);

logic [31:0] stage2_out;
always_ff @(posedge clk) stage2_out <= partial_func_2(stage1_out, c);

logic [31:0] stage3_out;
always_ff @(posedge clk) stage3_out <= partial_func_3(stage2_out, d);
```

### Pipeline Insertion Guidelines

1. Insert pipeline registers at natural functional boundaries.
2. Balance stage delays to within 10-15%.
3. Forward all signals that cross stages (not just the data path but also control signals).
4. Track pipeline latency in the system-level model.

## Register Retiming

Register retiming is a synthesis optimization that moves registers across combinational logic to balance stage delays without changing functionality.

### Forward Retiming

Moves a register from the input to the output of a combinational block, effectively pushing the register downstream.

```
Before: FF -> [fast logic] -> [slow logic] -> FF
After:  [fast logic] -> FF -> [slow logic] -> FF
```

### Backward Retiming

Moves a register from the output to the input, pulling it upstream. This is useful when the last stage of a pipeline is too slow.

### RTL for Retiming

To enable retiming, follow these rules:

1. **No asynchronous resets on pipeline registers**: Async reset pins the register's location.
2. **No feedback loops**: Registers in feedback cannot be moved.
3. **Flat hierarchy**: Retiming cannot move registers across module boundaries by default.
4. **Simple register patterns**: The tool must recognize the registers as pipeline stages.

```tcl
# Enable retiming in DC
compile_ultra -retime

# Enable retiming in Genus
set_db design:top .retiming true
```

## Resource Sharing

Resource sharing uses one hardware operator with multiplexed inputs instead of multiple operators.

```systemverilog
// Unshared: two adders
always_comb begin
  if (mode_a)
    result = x + y;
  else
    result = p + q;
end

// Shared equivalent (synthesis may do this automatically):
// MUX(mode_a, {x,y}, {p,q}) -> single adder -> result
```

### When Sharing Helps

Sharing reduces area when:
- The operator is large (multiplier, divider, wide adder).
- The operations are mutually exclusive (only one executes per cycle).

### When Sharing Hurts

Sharing increases delay because of the added muxes on the operator inputs. For timing-critical paths, dedicated operators may be necessary.

```tcl
# Control sharing in DC
set_resource_allocation none    ;# no sharing (max performance)
set_resource_allocation area    ;# maximum sharing (min area)
```

## High-Fanout Optimization

High-fanout signals (driving many loads) require buffer chains that add delay and consume area.

### RTL Strategies

1. **Register replication**: Instantiate multiple copies of a register, each driving a subset of loads.

```systemverilog
// Manual replication for high-fanout enable signal
logic enable_rep_a, enable_rep_b, enable_rep_c;

always_ff @(posedge clk) begin
  enable_rep_a <= enable_src;
  enable_rep_b <= enable_src;
  enable_rep_c <= enable_src;
end
// Route enable_rep_a to group A, enable_rep_b to group B, etc.
```

2. **Structured fanout**: Design the logic so that high-fanout signals drive through a balanced buffer tree naturally.

3. **Synthesis directives**: Let the tool handle replication.

```tcl
set_max_fanout 32 [get_ports enable]
```

## Memory Access Optimization

SRAM access time is often on the critical path, especially for read operations.

### Address Pipelining

Pre-compute the address one cycle early so the SRAM access starts at the beginning of the clock cycle.

```systemverilog
// Compute address in cycle N
always_ff @(posedge clk) begin
  sram_addr <= compute_addr(index, offset);
end
// SRAM read in cycle N+1 (full cycle for access)
// Data available at end of cycle N+1
```

### Output Registration

Register the SRAM output to break the SRAM-to-logic critical path.

```systemverilog
always_ff @(posedge clk) begin
  rdata_reg <= sram_rdata;  // register SRAM output
end
// Use rdata_reg in the rest of the pipeline
```

### Banking

Split a large SRAM into smaller banks. Smaller SRAMs have faster access times.

## Architectural Optimization Techniques

### Speculative Execution

Compute multiple possible results in parallel and select the correct one after the controlling condition is resolved.

### Precomputation

Compute partial results in advance based on predicted inputs. When the actual inputs arrive, only a small correction is needed.

### Strength Reduction

Replace expensive operations with cheaper equivalents:
- Multiply by constant -> shift and add
- Divide by power-of-2 -> shift
- Modulo power-of-2 -> bit mask

```systemverilog
// Replace multiply by 5 with shift-and-add
assign result = (data << 2) + data;  // data * 5
```

## Optimization Workflow

1. **Synthesize and report timing**: Identify the top 10 critical paths.
2. **Analyze each path**: Determine what makes it slow (logic depth, fanout, memory access).
3. **Apply targeted optimization**: Use the appropriate technique for each path type.
4. **Re-synthesize and verify**: Check that the optimization improved timing without breaking functionality.
5. **Iterate**: Continue until timing is met with adequate margin.

Do not optimize speculatively. Profile first, then optimize the actual bottleneck.

## Summary

RTL performance optimization is a targeted activity driven by timing analysis. Reduce logic depth through restructuring and pre-computation. Use pipelining for throughput and retiming for balance. Apply resource sharing for area and replication for fanout. Optimize memory access with address pipelining and output registration. Always profile first, optimize the critical path, and verify that the optimization achieves the intended improvement.
