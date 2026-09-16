# Synthesis-Friendly RTL Coding Style

## Overview

Synthesis translates RTL into a gate-level netlist, but the quality of that translation depends heavily on how the RTL is written. Poorly coded RTL can produce latches where flip-flops were intended, generate unnecessarily complex logic, or prevent the synthesis tool from applying critical optimizations. This guide covers the coding patterns that lead to clean, efficient, predictable synthesis results.

## Latch Avoidance

Unintentional latches are the most common synthesis coding error. A latch is inferred when a signal is not assigned on every path through a combinational always block.

### How Latches Get Inferred

```verilog
// BAD: latch inferred for 'out' when en is low
always_comb begin
  if (en)
    out = data;
  // missing else branch -> latch
end
```

### Prevention Strategies

**Default assignment at the top of the block:**

```verilog
always_comb begin
  out = '0;         // default prevents latch
  if (en)
    out = data;
end
```

**Complete case statements with default:**

```verilog
always_comb begin
  case (sel)
    2'b00: out = a;
    2'b01: out = b;
    2'b10: out = c;
    default: out = '0;
  endcase
end
```

**Complete if-else chains:**

```verilog
always_comb begin
  if (cond_a)
    out = val_a;
  else if (cond_b)
    out = val_b;
  else
    out = val_default;  // always terminate with else
end
```

The principle is simple: every output of a combinational block must be assigned a value on every possible execution path. Modern lint tools (SpyGlass, HAL) flag incomplete assignments automatically and should be run before synthesis.

## Full Case and Parallel Case

### The Problem with Pragmas

Synopsys-style pragmas `// synopsys full_case parallel_case` were historically used to tell synthesis that a case statement covers all possible values (`full_case`) or that case items are mutually exclusive (`parallel_case`). These pragmas are dangerous because they affect synthesis but not simulation, creating simulation-synthesis mismatches.

### full_case

`full_case` tells synthesis to assume all input values are covered, allowing the tool to treat unspecified inputs as don't-cares. This can mask bugs where unexpected input values occur.

**Better alternative:** Always write an explicit `default` branch. This is visible to both simulation and synthesis.

### parallel_case

`parallel_case` tells synthesis that no two case items can match simultaneously, allowing the tool to generate a mux tree instead of priority logic. This is relevant when case items overlap.

**Better alternative:** Use SystemVerilog `unique case`, which asserts mutual exclusivity in both simulation and synthesis. If a violation occurs, simulation reports it.

```systemverilog
unique case (1'b1)
  req[0]: grant = 4'b0001;
  req[1]: grant = 4'b0010;
  req[2]: grant = 4'b0100;
  req[3]: grant = 4'b1000;
  default: grant = 4'b0000;
endcase
```

## Clock Gating Inference

Clock gating reduces dynamic power by stopping the clock to idle registers. Modern synthesis tools can automatically infer clock gating from enable-based RTL patterns.

### Gating-Friendly Pattern

```verilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    data_reg <= '0;
  else if (load_en)
    data_reg <= data_in;
  // implicit: else data_reg holds its value
end
```

When the synthesis tool sees a register that conditionally loads (with an enable), it can replace the register with a clock-gated register: the enable signal gates the clock, and the register always loads from `data_in` when the gated clock toggles.

### Requirements for Inference

1. The enable condition must be a simple expression (not deeply nested).
2. All bits of the register must share the same enable.
3. The tool must be configured for clock gating (e.g., `set_clock_gating_style` in DC).
4. A clock gating cell (ICG) must be available in the library.

### Gating-Unfriendly Patterns

```verilog
// BAD: different enables for different bits prevent gating
always_ff @(posedge clk) begin
  if (en_a) data_reg[7:0]  <= data_a;
  if (en_b) data_reg[15:8] <= data_b;
end

// BAD: mux before register instead of enable
always_ff @(posedge clk) begin
  data_reg <= sel ? data_a : data_b;  // always loads, no gating opportunity
end
```

## Multiplier and Operator Inference

Synthesis tools infer dedicated hardware for arithmetic operators. The coding style affects the quality of inference.

### Resource Sharing

```verilog
// Synthesis may or may not share the adder
always_comb begin
  if (sel)
    result = a + b;
  else
    result = c + d;
end
```

If the tool shares the adder, it uses a single adder with muxed inputs. If not, it uses two adders with a muxed output. Use `set_resource_allocation` directives to control this.

### Operator Sizing

```verilog
// BAD: 32-bit multiply when only 16 bits are needed
wire [31:0] product = a * b;  // a, b are 16 bits but product is 32

// GOOD: explicit sizing
wire [31:0] product = {{16{a[15]}}, a} * {{16{b[15]}}, b};
```

Ensure operand widths match the intended precision. Oversized operations waste area and power.

## Register Inference Patterns

### Standard Flip-Flop

```verilog
always_ff @(posedge clk) begin
  q <= d;
end
```

### Flip-Flop with Synchronous Reset

```verilog
always_ff @(posedge clk) begin
  if (!rst_n) q <= '0;
  else        q <= d;
end
```

### Flip-Flop with Asynchronous Reset

```verilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) q <= '0;
  else        q <= d;
end
```

### Flip-Flop with Enable

```verilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)    q <= '0;
  else if (en)   q <= d;
end
```

### Common Errors

Do not mix reset with data logic in ways the tool cannot map to library cells:

```verilog
// BAD: conditional reset value
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) q <= init_val;  // init_val is not constant -> unmappable
  else        q <= d;
end
```

Asynchronous reset values must be constants (usually 0).

## Avoiding Combinational Loops

A combinational loop occurs when a signal depends on itself through purely combinational logic, with no register breaking the loop. Combinational loops cause simulation instability and synthesis failures.

```verilog
// BAD: combinational loop
assign a = b & c;
assign b = a | d;  // a -> b -> a
```

Synthesis tools report combinational loops as errors. The fix is to insert a register in the feedback path or restructure the logic.

## Memory Inference

Synthesis tools can infer RAM or ROM from array patterns:

```verilog
reg [31:0] mem [0:1023];

// Single-port RAM inference
always_ff @(posedge clk) begin
  if (we)
    mem[addr] <= wdata;
  rdata <= mem[addr];
end
```

For memory inference to succeed, the array access must use a single clock, a simple address expression, and a write enable. Complex access patterns (multiple read ports, asynchronous read) may not infer and will synthesize to flip-flop arrays, consuming enormous area.

## Tri-State and Bus Coding

Internal tri-state buses are not supported in modern ASIC synthesis. All tri-state logic must be at I/O pads. Internally, replace tri-state with muxes:

```verilog
// BAD: internal tri-state
assign bus = en_a ? data_a : 'z;
assign bus = en_b ? data_b : 'z;

// GOOD: mux-based
assign bus = en_a ? data_a : (en_b ? data_b : '0);
```

## Synthesis Directives Summary

While coding style should minimize the need for directives, some are commonly used:

- `dont_touch`: Prevents optimization of a net or cell (for debug or ECO).
- `keep`: Preserves a net name through synthesis.
- `set_dont_use`: Excludes specific library cells.
- `set_clock_gating_style`: Configures clock gating inference.

## Best Practices Checklist

1. Assign every output on every path in combinational blocks.
2. Always include a `default` in case statements.
3. Use `unique case` instead of `parallel_case` pragmas.
4. Write enable-based register patterns for clock gating inference.
5. Avoid combinational loops.
6. Use constant reset values for asynchronous resets.
7. Avoid internal tri-state; use muxes instead.
8. Match operator widths to intended precision.
9. Run lint before synthesis to catch coding issues early.
10. Review synthesis reports for inferred latches, combinational loops, and unmapped cells.
