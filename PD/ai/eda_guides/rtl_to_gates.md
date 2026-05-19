# RTL to Gates: The Synthesis Process

## Overview

RTL synthesis transforms a behavioral hardware description into a gate-level netlist composed of technology-specific standard cells. This process is the bridge between the designer's intent (RTL) and the physical implementation (gates, wires, transistors). Understanding the synthesis process helps RTL designers write code that synthesizes efficiently and helps physical design engineers interpret and optimize the resulting netlist. This guide walks through each phase of the synthesis flow.

## Synthesis Flow Overview

```
RTL (Verilog/SystemVerilog)
        |
   [1] Reading & Analysis
        |
   [2] Elaboration
        |
   [3] Generic (GTECH) Mapping
        |
   [4] Logic Optimization
        |
   [5] Technology Mapping
        |
   [6] Design Optimization
        |
   [7] Incremental Optimization
        |
Gate-Level Netlist (.v + .sdc)
```

## Phase 1: Reading and Analysis

The synthesis tool reads the RTL source files and checks for syntax and semantic correctness.

```tcl
# Synopsys DC
analyze -format sverilog {design_top.sv alu.sv regfile.sv}
# Or
read_file -format sverilog {design_top.sv alu.sv regfile.sv}

# Cadence Genus
read_hdl -sv {design_top.sv alu.sv regfile.sv}
```

During analysis, the tool:
- Parses the HDL syntax.
- Resolves `include` directives and `define` macros.
- Checks for compile errors.
- Builds an internal syntax tree representation.

At this stage, the tool does not resolve parameters or generate blocks because it does not yet know the specific configuration.

## Phase 2: Elaboration

Elaboration resolves the design hierarchy, creating concrete instances of all parameterized modules and expanding generate blocks.

```tcl
# Synopsys DC
elaborate design_top -parameters {WIDTH=32, DEPTH=16}

# Cadence Genus
elaborate design_top
```

During elaboration:
- **Parameter resolution**: All parameters are set to their final values (either defaults or overrides from instantiation).
- **Generate expansion**: `generate for`, `generate if`, and `generate case` blocks are evaluated and the selected hardware is instantiated.
- **Hierarchy construction**: The full design hierarchy is built with all module instances.
- **Port binding**: Module ports are connected to the signals in the parent module.
- **Type checking**: Signal widths, types, and connection compatibility are verified.

After elaboration, the design is a fully resolved, technology-independent representation.

### Common Elaboration Issues

- **Unresolved module**: A module instantiated in the RTL is not found in the source file list.
- **Parameter out of range**: A parameter value causes a generate assertion to fail.
- **Width mismatch**: Port width does not match the connected signal width.
- **Multiple driver**: The same signal is driven by multiple continuous assignments or always blocks.

## Phase 3: Generic (GTECH) Mapping

The elaborated design is translated into a generic technology-independent gate network. This representation uses abstract gates (AND, OR, MUX, ADDER, REGISTER) that are not tied to any specific technology library.

### What Happens

- **Combinational logic inference**: `always_comb` blocks and `assign` statements are mapped to boolean expressions and generic gates.
- **Sequential logic inference**: `always_ff` blocks are mapped to generic flip-flops with optional reset and enable.
- **Arithmetic inference**: `+`, `-`, `*` operators are mapped to generic arithmetic operators (adders, multipliers).
- **Memory inference**: Array access patterns may be mapped to generic RAM structures.
- **Latch inference**: Incomplete combinational assignments are mapped to generic latches (usually unintentional).

The GTECH representation is the tool's starting point for optimization. A clean GTECH indicates well-written RTL; warnings about inferred latches, multiply-driven signals, or combinational loops indicate RTL issues.

### Reviewing GTECH

```tcl
# Check for inferred latches
report_compile_statistics  ;# should show 0 inferred latches

# Check the generic representation
report_area -generic       ;# area in generic gate equivalents
```

## Phase 4: Logic Optimization

The generic gate network is optimized for area, timing, or a combination. This is the core intelligence of the synthesis tool.

### Boolean Optimization

- **Two-level optimization**: Collapse logic into sum-of-products form and minimize using techniques like Espresso.
- **Multi-level optimization**: Factor and restructure boolean expressions into a multi-level gate network that balances area and delay.
- **Redundancy removal**: Identify and remove redundant logic (gates whose output does not affect any primary output).
- **Constant propagation**: If a signal is tied to a constant, propagate that constant through the logic and eliminate the dead gates.

### Structural Optimization

- **Sharing**: Identify common sub-expressions and share hardware.
- **Decomposition**: Break complex gates into simpler gates that map to library cells.
- **Substitution**: Replace sub-circuits with more efficient equivalent implementations.

### Timing-Driven Optimization

When timing constraints (SDC) are provided, the optimizer prioritizes timing-critical paths:

```tcl
create_clock -period 2.0 [get_ports clk]  ;# 500 MHz target
set_input_delay -clock clk 0.5 [all_inputs]
set_output_delay -clock clk 0.5 [all_outputs]
```

The tool allocates faster (and larger) logic to critical paths and slower (and smaller) logic to paths with slack. This is the area-timing tradeoff.

## Phase 5: Technology Mapping

The optimized generic gate network is mapped to cells from the target technology library. Each generic gate is replaced with a specific standard cell.

### Cell Selection

The mapper selects cells from the library that implement each logic function. Multiple library cells may implement the same function (e.g., a 2-input NAND is available in drive strengths X1, X2, X4, X8). The mapper chooses the appropriate drive strength based on load and timing requirements.

### Mapping Algorithms

- **Tree covering**: Decompose the logic network into a forest of trees and cover each tree with library cells using dynamic programming.
- **DAG mapping**: More advanced than tree covering, handles reconvergent fanout by mapping Directed Acyclic Graphs.

### Library Information

The technology library (`.lib` or `.db`) provides:
- **Cell function**: Boolean function implemented by each cell.
- **Timing models**: Delay as a function of input transition and output capacitance.
- **Power models**: Switching and leakage power per cell.
- **Area**: Physical area of each cell.
- **Design rules**: Maximum fanout, maximum capacitance, maximum transition.

## Phase 6: Design Optimization

After technology mapping, the tool performs additional optimizations using the actual cell characteristics.

### Gate Sizing

Replace cells with equivalent cells of different drive strengths to meet timing:
- Upsize cells on critical paths (larger = faster but more area).
- Downsize cells on non-critical paths (smaller = less area and power).

### Buffer Insertion

Insert buffers to fix:
- **Design rule violations**: Maximum fanout, maximum capacitance, maximum transition.
- **Hold violations**: Buffers add delay to fix hold time violations.
- **Long wire delays**: Buffers drive long interconnect segments.

### Clock Gating Insertion

If enabled, the tool identifies registers with conditional enables and inserts ICG cells.

```tcl
set_clock_gating_style -sequential_cell latch
insert_clock_gating
```

### Multi-Vt Optimization

The tool swaps cells between high-Vt (low leakage, slow) and low-Vt (high leakage, fast) variants:
- Critical path cells: low-Vt for speed.
- Non-critical path cells: high-Vt for low leakage.

## Phase 7: Incremental Optimization

After the initial compile, incremental optimization passes refine the result:

```tcl
# Synopsys DC
compile_ultra -incremental   ;# refine without restructuring

# Cadence Genus
opt_design -incremental
```

Incremental optimization:
- Fine-tunes gate sizing.
- Fixes remaining timing violations.
- Resolves DRC (Design Rule Check) violations.
- Reduces area on non-critical paths.

## Compile Strategies

### Single Pass

```tcl
compile_ultra
```

A single optimization pass. Fast but may not achieve optimal results for complex designs.

### Multi-Pass with Different Strategies

```tcl
# First pass: area-focused
compile_ultra -area
# Second pass: timing-focused
compile_ultra -incremental -timing
```

### Adaptive Compile

Modern tools use machine-learning-guided optimization:

```tcl
# DC: adaptive retiming
compile_ultra -retime -timing_high_effort

# Genus: ML-guided
set_db opt_effort high
```

## Output Products

After synthesis, the tool produces:

### Gate-Level Netlist

```verilog
// Synthesized netlist (simplified)
module alu (clk, rst_n, a, b, opcode, result);
  DFFQX1 result_reg_0 (.D(n42), .CK(clk), .Q(result[0]));
  DFFQX1 result_reg_1 (.D(n43), .CK(clk), .Q(result[1]));
  NAND2X1 U10 (.A(a[0]), .B(b[0]), .Y(n42));
  AOI22X1 U11 (.A0(a[1]), .A1(b[1]), .B0(n44), .B1(opcode[0]), .Y(n43));
  // ...
endmodule
```

### Timing Reports

```tcl
report_timing -max_paths 10
# Slack, path delay, cell delays, wire delays
```

### Area Reports

```tcl
report_area -hierarchy
# Cell count, combinational area, sequential area, total area
```

### Power Reports

```tcl
report_power -hierarchy
# Dynamic power, leakage power, per-hierarchy breakdown
```

### Constraints (SDC)

The updated SDC file with any modifications made during synthesis (e.g., dont_touch, case analysis).

## Verifying Synthesis Results

### Formal Equivalence Checking

Prove that the gate-level netlist is functionally equivalent to the RTL:

```tcl
# Synopsys Formality
set_reference_design rtl_top
set_implementation_design gate_top
verify
```

### Gate-Level Simulation

Run the RTL test suite on the gate-level netlist to verify functional correctness with actual cell delays.

## Summary

Synthesis transforms RTL into gates through a structured pipeline: elaboration resolves the design hierarchy, generic mapping creates a technology-independent representation, logic optimization minimizes the logic, and technology mapping selects the actual standard cells. Understanding each phase helps the designer write synthesizable RTL, interpret synthesis reports, and guide the tool toward optimal results through constraints and directives.
