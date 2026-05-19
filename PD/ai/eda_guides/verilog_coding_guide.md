# Verilog Coding Guide

## Overview

Verilog HDL (IEEE 1364) is the foundational hardware description language for ASIC and FPGA design. While SystemVerilog has extended the language significantly, Verilog remains the baseline that every RTL designer must master. This guide covers the essential language constructs for writing synthesizable, production-quality RTL code.

## Module Structure

The module is Verilog's fundamental unit of hierarchy. Every design block, from a simple AND gate to a complete SoC subsystem, is encapsulated as a module.

### ANSI-Style Port Declaration (Verilog-2001)

```verilog
module adder #(
  parameter WIDTH = 8
)(
  input  wire [WIDTH-1:0] a,
  input  wire [WIDTH-1:0] b,
  input  wire             cin,
  output wire [WIDTH-1:0] sum,
  output wire             cout
);

  assign {cout, sum} = a + b + cin;

endmodule
```

Always use ANSI-style port declarations (Verilog-2001). The older Verilog-1995 style, which separates port names from their declarations, is redundant and error-prone. ANSI style declares direction, type, and width in a single location.

### Module Instantiation

```verilog
adder #(.WIDTH(16)) u_adder (
  .a    (op_a),
  .b    (op_b),
  .cin  (carry_in),
  .sum  (result),
  .cout (carry_out)
);
```

Always use named port connections (`.port(signal)`) rather than positional connections. Named connections are self-documenting and resilient to port reordering. Use a `u_` prefix for instance names to distinguish them from signal names.

## Data Types

### Wire

`wire` represents a combinational connection. It cannot hold a value; it is continuously driven by an `assign` statement, a module output, or a primitive gate.

### Reg

`reg` is a variable that can hold a value within procedural blocks (`always`, `initial`). Despite the name, `reg` does not necessarily synthesize to a register. A `reg` assigned in a combinational always block synthesizes to combinational logic. A `reg` assigned in a clocked always block synthesizes to a flip-flop.

### Integer and Real

`integer` is a 32-bit signed type useful for loop indices and testbench calculations. `real` is for floating-point in simulation only. Neither should appear in synthesizable RTL data paths.

### Net Types

Beyond `wire`, Verilog provides `tri`, `wand`, `wor`, and `supply0`/`supply1`. In practice, `wire` covers nearly all needs. Use `supply0` and `supply1` for tie-off connections to ground and power.

### Vector Declaration

```verilog
wire [31:0] data_bus;    // 32-bit bus, MSB=31, LSB=0
reg  [7:0]  mem [0:255]; // 256-entry memory, 8 bits each
```

Always use descending ranges `[MSB:LSB]` with LSB=0. Ascending ranges and non-zero LSBs cause confusion and tool issues.

## Operators

### Arithmetic Operators

`+`, `-`, `*`, `/`, `%` (modulus). Division and modulus by non-powers-of-two synthesize to large combinational circuits. Use only when area/timing budgets permit, or replace with shift operations where possible.

### Logical and Bitwise Operators

- **Bitwise**: `&`, `|`, `^`, `~` operate on each bit independently.
- **Logical**: `&&`, `||`, `!` return single-bit results.
- **Reduction**: `&data`, `|data`, `^data` reduce a vector to a single bit (AND, OR, XOR of all bits).

### Relational and Equality

`<`, `>`, `<=`, `>=` for comparisons. `==` and `!=` for equality (treats X as unknown in simulation). `===` and `!==` for case equality (matches X exactly, simulation only, not synthesizable).

### Shift Operators

`<<` and `>>` are logical shifts (fill with zeros). `<<<` and `>>>` are arithmetic shifts (sign-extend on right shift). Shifts by a constant power-of-two are free in hardware (just wiring); variable shifts synthesize to barrel shifters.

### Concatenation and Replication

```verilog
assign bus = {a, b, c};       // concatenation
assign wide = {4{byte}};      // replication: 4 copies of byte
assign sign_ext = {{24{val[7]}}, val[7:0]};  // sign extension
```

## Conditional Constructs

### if-else

Used inside always blocks for priority-encoded logic:

```verilog
always @(*) begin
  if (sel == 2'b00)      out = a;
  else if (sel == 2'b01) out = b;
  else if (sel == 2'b10) out = c;
  else                   out = d;
end
```

The `if-else` chain implies priority; the first matching condition wins. For non-priority logic, use `case`.

### case, casex, casez

```verilog
always @(*) begin
  case (opcode)
    4'b0001: result = a + b;
    4'b0010: result = a - b;
    4'b0100: result = a & b;
    default: result = '0;
  endcase
end
```

Always include a `default` branch to avoid latch inference. `casez` treats `z` (or `?`) as don't-care in comparisons, useful for instruction decoding. `casex` also treats `x` as don't-care but is dangerous because it masks simulation unknowns. Prefer `casez` over `casex`.

### Ternary Operator

```verilog
assign out = sel ? a : b;
```

The ternary operator is the continuous-assignment equivalent of `if-else`. It is concise for simple muxes but becomes unreadable when nested more than two levels.

## Loop Constructs

### for Loop

```verilog
integer i;
always @(*) begin
  for (i = 0; i < 8; i = i + 1) begin
    reversed[i] = data[7-i];
  end
end
```

Synthesizable `for` loops must have static bounds (known at compile time). The loop is unrolled by synthesis into parallel hardware. Variable-bound loops are not synthesizable.

### generate for

```verilog
genvar g;
generate
  for (g = 0; g < NUM_CHANNELS; g = g + 1) begin : gen_ch
    channel_proc u_ch (.data_in(data[g]), .data_out(result[g]));
  end
endgenerate
```

Generate loops create multiple instances of hardware at elaboration time. They are essential for parameterized, scalable designs.

### while and repeat

`while` and `repeat` loops are used in testbenches and simulation. They are generally not synthesizable unless the loop bound is static and the tool can unroll them.

## Tasks and Functions

### Functions

Functions are combinational: they execute in zero simulation time, cannot contain timing controls, and return a single value.

```verilog
function [7:0] parity_gen;
  input [7:0] data;
  begin
    parity_gen = ^data;  // XOR reduction for parity
  end
endfunction
```

Functions are ideal for encapsulating reusable combinational computations. They synthesize to combinational logic.

### Tasks

Tasks can contain timing controls (delays, waits) and can have multiple outputs. In synthesizable RTL, tasks without timing controls are equivalent to functions with multiple outputs. Tasks with timing controls are simulation-only.

```verilog
task automatic compute_checksum;
  input  [31:0] data;
  output [7:0]  checksum;
  output        valid;
  begin
    checksum = data[7:0] ^ data[15:8] ^ data[23:16] ^ data[31:24];
    valid    = |data;
  end
endtask
```

Use the `automatic` keyword for reentrant tasks (important when called from multiple places concurrently in simulation).

## Parameters and Localparam

```verilog
module fifo #(
  parameter DEPTH = 16,
  parameter WIDTH = 32
)(
  // ports
);
  localparam ADDR_W = $clog2(DEPTH);  // derived, not overridable
endmodule
```

Use `parameter` for values that module instantiators can override. Use `localparam` for derived constants that should not be overridden. `$clog2()` is the standard function for computing address widths from depths.

## Preprocessor Directives

```verilog
`define BUS_WIDTH 64
`ifdef SIMULATION
  // simulation-only code
`else
  // synthesis code
`endif
`include "header.vh"
```

Use `define` sparingly. Prefer parameters for module-level constants and `localparam` for derived values. `define` creates global namespace pollution. Reserve it for truly global compile-time switches.

## Best Practices Summary

1. Use ANSI-style ports and named connections exclusively.
2. Use `wire` for continuous assignments, `reg` for procedural blocks.
3. Always provide default cases and default assignments.
4. Use `casez` instead of `casex` for don't-care matching.
5. Keep loop bounds static for synthesizability.
6. Prefer functions over tasks for combinational computations.
7. Use `parameter` for configurable values, `localparam` for derived constants.
8. Avoid `define` for module-level constants; use parameters instead.
9. Use `$clog2()` for address width calculations.
10. Write self-documenting code with meaningful signal and module names.
