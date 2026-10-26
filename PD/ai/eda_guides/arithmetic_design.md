# Arithmetic Design

## Overview

Arithmetic circuits are the computational heart of digital systems. From simple incrementers to complex floating-point units, the choice of arithmetic architecture directly determines the area, timing, and power characteristics of the data path. RTL designers must understand the underlying architectures to write code that synthesizes efficiently and to evaluate the tradeoffs when the synthesis tool's automatic choices are not optimal. This guide covers adders, multipliers, dividers, shifters, and number representations.

## Adder Architectures

### Ripple Carry Adder (RCA)

The simplest adder. Each full adder produces a carry that propagates to the next bit position.

```
Delay: O(N) - linear in bit width
Area: O(N) - minimal
```

```systemverilog
// RCA is what synthesis infers from: assign sum = a + b;
// For small widths (<8 bits) or non-critical paths, this is sufficient
assign {cout, sum} = a + b + cin;
```

The RCA is area-efficient but timing-limited. The carry must ripple through all N bits, making the critical path proportional to the bit width.

### Carry Lookahead Adder (CLA)

Computes carry bits in parallel using generate (G) and propagate (P) signals:

```
G[i] = a[i] & b[i]     (generate: bit i produces a carry)
P[i] = a[i] ^ b[i]     (propagate: bit i passes an incoming carry)
C[i+1] = G[i] | (P[i] & C[i])
```

By expanding the recurrence, carries for multiple bits are computed simultaneously:

```
C[4] = G[3] | P[3]&G[2] | P[3]&P[2]&G[1] | P[3]&P[2]&P[1]&G[0] | P[3]&P[2]&P[1]&P[0]&C[0]
```

```
Delay: O(log N) - logarithmic
Area: O(N log N) - larger than RCA
```

The CLA is the workhorse of high-performance adders. Synthesis tools typically infer CLA-like structures for medium-to-large adder widths.

### Carry Select Adder (CSA)

Computes two sums in parallel: one assuming carry-in = 0, one assuming carry-in = 1. When the actual carry arrives, a mux selects the correct result.

```
Delay: O(sqrt(N)) with optimal group sizing
Area: ~2x RCA (duplicate adders)
```

Carry select is effective when the critical path must be shorter than CLA but area is available.

### Carry Skip Adder

Divides the operands into groups. If all bits in a group propagate, the carry skips the entire group. Delay is between RCA and CLA.

### Prefix Adders (Brent-Kung, Kogge-Stone, Han-Carlson)

Prefix adders use a tree structure to compute all carries in O(log N) time. Different prefix tree topologies trade off between:

- **Kogge-Stone**: Minimum logic depth, maximum wiring (fastest, largest).
- **Brent-Kung**: Minimum area, slightly more depth.
- **Han-Carlson**: Balanced compromise.

Synthesis tools typically choose the prefix adder topology automatically based on timing constraints.

### Synthesis Implications

When you write `assign sum = a + b;`, the synthesis tool selects the adder architecture based on the bit width and timing constraint. For tight timing, it chooses a fast architecture (prefix adder); for relaxed timing, it chooses a small architecture (RCA). You can influence this with:

```tcl
# Synopsys DC: control implementation
set_implementation_style [get_designs alu] -method ripple  ;# or cla, csa
```

## Multiplier Architectures

### Array Multiplier

Generates all partial products and sums them using a regular array of full adders.

```
Delay: O(N) - proportional to bit width
Area: O(N^2) - quadratic
```

Simple but slow and large. Suitable for small widths or non-critical paths.

### Wallace Tree Multiplier

Uses carry-save adders (3:2 compressors) to reduce partial products in O(log N) stages, followed by a final carry-propagate adder.

```
Delay: O(log N) stages of reduction + O(log N) final adder
Area: O(N^2) - but fewer adder levels than array
```

### Booth Multiplier

Booth encoding (radix-2 or radix-4) reduces the number of partial products. Radix-4 Booth cuts the partial product count in half.

```systemverilog
// Synthesis infers optimized multiplier from:
assign product = a * b;

// For signed multiplication:
logic signed [15:0] a_signed, b_signed;
logic signed [31:0] product_signed;
assign product_signed = a_signed * b_signed;
```

### Synthesis Multiplier Inference

Modern synthesis tools infer highly optimized multipliers. For most designs, simply writing `a * b` produces the best result. Manual multiplier architectures are rarely needed unless targeting specific FPGA DSP blocks or unusual precision requirements.

### Multiply-Accumulate (MAC)

```systemverilog
always_ff @(posedge clk) begin
  if (rst)
    accum <= '0;
  else if (en)
    accum <= accum + (a * b);
end
```

Synthesis tools can infer fused MAC units that share the adder between the multiplier reduction and the accumulation, saving area and improving timing.

## Divider Architectures

Division is the most expensive arithmetic operation. It is inherently sequential, requiring N iterations for an N-bit quotient.

### Restoring Division

At each step, subtract the divisor from the partial remainder. If the result is negative, restore (add the divisor back) and set the quotient bit to 0. Otherwise, set the quotient bit to 1.

### Non-Restoring Division

Similar to restoring, but instead of adding the divisor back on a negative result, the next step adds instead of subtracting. This eliminates the restore step but requires a final correction.

### SRT Division

Used in high-performance processors. Selects quotient digits from a redundant digit set, allowing multiple bits per iteration with a lookup table.

### RTL Approach

For synthesis, avoid the `/` operator unless the divisor is a power of two (which becomes a shift). For arbitrary division, implement a sequential divider with a multi-cycle handshake:

```systemverilog
module divider #(parameter WIDTH = 32)(
  input  logic             clk, rst_n,
  input  logic             start,
  input  logic [WIDTH-1:0] dividend, divisor,
  output logic [WIDTH-1:0] quotient, remainder,
  output logic             done
);
  // Sequential non-restoring algorithm over WIDTH cycles
  logic [WIDTH-1:0] q, r;
  logic [$clog2(WIDTH):0] count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done  <= 1'b0;
      count <= '0;
    end else if (start) begin
      q     <= dividend;
      r     <= '0;
      count <= WIDTH;
      done  <= 1'b0;
    end else if (count > 0) begin
      // Non-restoring division step
      if (r[WIDTH-1]) begin
        r <= {r[WIDTH-2:0], q[WIDTH-1]} + divisor;
      end else begin
        r <= {r[WIDTH-2:0], q[WIDTH-1]} - divisor;
      end
      q     <= {q[WIDTH-2:0], ~r[WIDTH-1]};
      count <= count - 1;
      if (count == 1) done <= 1'b1;
    end
  end

  assign quotient  = q;
  assign remainder = r[WIDTH-1] ? r + divisor : r;  // final correction
endmodule
```

## Shifter Design

### Logical Shift

Fill vacated bits with zeros. `<<` and `>>` in Verilog.

### Arithmetic Shift

Right shift preserves the sign bit (fills with MSB). `>>>` in Verilog (requires `signed` operands).

### Barrel Shifter

A barrel shifter performs any shift amount in a single cycle using a cascade of muxes:

```systemverilog
// Synthesis infers a barrel shifter from:
assign result = data << shift_amount;  // variable shift
```

For N-bit data with log2(N)-bit shift amount, the barrel shifter uses log2(N) stages of 2:1 muxes, each controlled by one bit of the shift amount.

### Rotate

Rotation wraps bits from one end to the other:

```systemverilog
assign rot_left  = (data << amt) | (data >> (WIDTH - amt));
assign rot_right = (data >> amt) | (data << (WIDTH - amt));
```

## Fixed-Point Arithmetic

Fixed-point represents fractional values using an implied binary point within an integer register.

```
Q8.8 format: 8 integer bits, 8 fractional bits (16 bits total)
Value = integer_representation / 2^8
```

```systemverilog
// Q8.8 multiplication (result needs double width)
logic [15:0] a_q8_8, b_q8_8;
logic [31:0] product_full;
logic [15:0] product_q8_8;

assign product_full = a_q8_8 * b_q8_8;
assign product_q8_8 = product_full[23:8];  // select Q8.8 portion
```

Fixed-point is far more area and power efficient than floating-point for applications where the dynamic range is known (audio, video, control systems, DSP).

## Floating-Point Basics

IEEE 754 floating-point uses sign, exponent, and mantissa fields:

```
Single precision (32-bit): 1 sign + 8 exponent + 23 mantissa
Double precision (64-bit): 1 sign + 11 exponent + 52 mantissa
```

Floating-point addition requires exponent alignment, mantissa addition, and normalization. Multiplication requires exponent addition, mantissa multiplication, and normalization. Both are significantly more complex than integer operations.

For RTL design, use vendor-provided floating-point IP (DesignWare, Synopsys; FloPoCo, open-source) rather than implementing from scratch. The exception handling (NaN, infinity, denormals, rounding modes) is extremely complex and error-prone.

## Synthesis Best Practices for Arithmetic

1. **Let synthesis choose**: For most cases, `+`, `-`, `*` produce optimal results. Override only when timing analysis shows a specific bottleneck.
2. **Match operand widths**: Avoid unnecessary width extension that creates larger-than-needed operators.
3. **Use shift instead of multiply/divide by powers of 2**: `a << 3` is free in hardware; `a * 8` requires the tool to recognize and optimize.
4. **Pipeline wide multipliers**: A 32x32 multiply may not meet timing in a single cycle; insert pipeline registers.
5. **Avoid division**: Replace with multiplication by reciprocal, shift, or look-up table where possible.
6. **Use signed types explicitly**: For signed arithmetic, declare operands as `logic signed` to ensure correct sign extension and arithmetic shift behavior.
7. **Check synthesis reports**: Review the arithmetic implementation chosen by the tool; rearchitect if the inferred structure does not meet timing or area targets.
