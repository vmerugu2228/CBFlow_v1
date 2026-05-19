# RTL Synthesis Constraints

## Overview

While SDC timing constraints define the performance targets for synthesis, there are additional constraints and directives applied at the RTL level that control how the synthesis tool transforms the design. These directives influence optimization, preserve design intent, enable or disable specific transformations, and guide the tool toward better QoR (Quality of Results). Understanding when and how to apply these constraints is essential for achieving timing closure efficiently.

## dont_touch

The `dont_touch` attribute prevents the synthesis tool from optimizing, removing, or modifying a specific net, cell, or hierarchical instance.

### Use Cases

1. **Preserving debug signals**: Nets needed for post-silicon debug that synthesis would otherwise optimize away.
2. **Preventing constant propagation**: Signals tied to configuration that appear constant during synthesis but are dynamically controlled in silicon.
3. **ECO points**: Nets that must be preserved for potential Engineering Change Orders after tape-out.
4. **Synchronizer flip-flops**: CDC synchronizer registers that must not be merged, replicated, or retimed.
5. **Analog/mixed-signal connections**: Signals connecting to analog blocks that must maintain specific naming.

### Application Methods

```tcl
# In RTL (Verilog attribute)
(* dont_touch = "true" *) wire debug_signal;
(* dont_touch = "true" *) reg [31:0] config_reg;

# In synthesis script (DC)
set_dont_touch [get_nets debug_signal]
set_dont_touch [get_cells u_sync/meta_ff_reg]
set_dont_touch [get_designs sub_block]
```

### Cautions

Overuse of `dont_touch` prevents the synthesis tool from performing beneficial optimizations. Apply it only where necessary and document the reason. Each `dont_touch` should have a justification in the constraint file comments.

## set_size_only

The `set_size_only` attribute allows the synthesis tool to resize a cell (change drive strength) but prevents it from replacing the cell with a functionally different implementation.

```tcl
set_size_only [get_cells u_buf/buffer_chain_*]
```

### Use Cases

1. **Buffer chains**: Buffers inserted for specific fanout or delay purposes that should not be merged or removed.
2. **Library-specific cells**: Cells chosen for specific electrical characteristics (e.g., balanced rise/fall).
3. **Hold fix buffers**: Buffers inserted to fix hold violations that should not be optimized away.

## Register Retiming

Register retiming moves flip-flops across combinational logic to balance pipeline stage delays, improving timing without changing functionality.

### Enabling Retiming

```tcl
# Synopsys DC
set_register_type -flip_flop          ;# allow retiming of flip-flops
compile_ultra -retime                  ;# enable retiming during optimization

# Cadence Genus
set_db design:des/retiming true
```

### RTL Requirements for Retiming

1. **No asynchronous reset on pipeline registers**: Asynchronous reset pins the register to a specific location. Use synchronous reset or no reset for pipeline registers that should be retimable.

```systemverilog
// Retimable: no async reset
always_ff @(posedge clk) begin
  pipe_s1 <= data_in;
  pipe_s2 <= pipe_s1;
  pipe_s3 <= pipe_s2;
end

// NOT retimable: async reset prevents movement
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) pipe_s1 <= '0;
  else        pipe_s1 <= data_in;
end
```

2. **No feedback paths**: Registers in a feedback loop cannot be retimed because moving them changes the loop behavior.
3. **Flat hierarchy**: Retiming works best when the pipeline stages are in the same hierarchical level. Cross-hierarchy retiming requires `set_ungroup` or `compile_ultra -no_autoungroup`.

### Retiming Constraints

```tcl
# Prevent retiming of specific registers
set_dont_retime [get_cells u_fsm/state_reg*]

# Allow retiming through specific boundaries
set_optimize_registers true -design pipe_stage
```

### Verifying Retiming

After retiming, run formal equivalence checking (Formality, Conformal LEC) to verify that the retimed netlist is functionally equivalent to the original RTL. Retiming changes register locations, which can confuse simulation-based verification.

## Ungrouping

Ungrouping dissolves hierarchical boundaries, allowing the synthesis tool to optimize logic across module boundaries.

### Benefits

- **Cross-boundary optimization**: Logic from adjacent modules can be combined, reducing area and delay.
- **Better timing**: Critical paths spanning multiple modules can be optimized as a single combinational cloud.
- **Reduced cell count**: Duplicate logic at module boundaries can be merged.

### Application

```tcl
# Ungroup a specific instance
set_ungroup [get_designs small_module]

# Ungroup during compile
compile_ultra -no_autoungroup false   ;# enable automatic ungrouping

# Selectively preserve hierarchy
set_dont_touch [get_designs critical_module]  ;# prevents ungrouping
```

### Cautions

1. **Debug difficulty**: Ungrouped designs lose hierarchy, making waveform debug and ECO harder.
2. **Constraint application**: If constraints reference hierarchical paths, ungrouping invalidates those paths.
3. **Floorplanning**: Physical design often depends on hierarchical boundaries for placement guidance.

### Best Practice

Ungroup small, leaf-level modules (glue logic, simple muxes, encoders). Preserve hierarchy for large, well-defined blocks (FIFOs, memories, IP blocks, FSMs).

## Boundary Optimization

Boundary optimization allows the synthesis tool to optimize logic at the input and output ports of a module, even if the port connections are fixed.

```tcl
# Enable boundary optimization
set_boundary_optimization [get_designs sub_block] true

# Disable for specific modules
set_boundary_optimization [get_designs interface_block] false
```

Boundary optimization can remove unused ports, propagate constants through ports, and combine logic across port boundaries. Disable it for blocks whose interfaces are fixed contracts (e.g., IP blocks, reusable library modules).

## Datapath Optimization

Synthesis tools have specialized datapath optimization engines that recognize arithmetic structures and implement them efficiently.

```tcl
# Enable datapath optimization (DC)
set_dp_smartgen true

# Control arithmetic implementation
set_implementation_style [get_cells u_mult] -name mult -implementation csa
```

### Carry-Save Arithmetic

For designs with multiple chained additions (e.g., multiply-accumulate), carry-save optimization delays the carry propagation to the final stage, reducing the critical path.

### Resource Sharing

```tcl
# Control resource sharing
set_resource_allocation -method exact
set_resource_implementation -method shared [get_cells {u_add1 u_add2}]
```

Resource sharing uses a single arithmetic operator with muxed inputs instead of multiple operators. This saves area but adds mux delay. Control sharing explicitly when timing is critical.

## Compile Strategies

### Top-Down Compile

Compile the entire design as one unit. The tool has full visibility for cross-hierarchy optimization.

```tcl
read_file -format sverilog {file_list}
compile_ultra
```

- Pros: Best QoR, full optimization freedom.
- Cons: Long runtime, high memory usage for large designs.

### Bottom-Up Compile

Compile leaf modules first, then assemble and compile the top.

```tcl
# Compile sub-block
compile_ultra -design sub_block

# Mark as dont_touch to preserve during top compile
set_dont_touch sub_block

# Compile top
compile_ultra -design top
```

- Pros: Faster iteration, manageable memory.
- Cons: No cross-boundary optimization, potential interface timing issues.

### Hierarchical Compile

A hybrid approach where critical blocks are compiled with their context for better boundary optimization.

```tcl
# Characterize sub-block interfaces
characterize [get_designs sub_block]

# Compile sub-block with interface models
compile_ultra -design sub_block
```

## Preserving Signal Names

For debug, DFT, and ECO, certain signal names must survive synthesis.

```tcl
# Preserve net name
set_dont_touch [get_nets important_signal] ;# also preserves the net

# In RTL
(* keep = "true" *) wire debug_net;
```

## Multi-Vt Cell Usage

Control the mix of high-Vt (low leakage, slow) and low-Vt (high leakage, fast) cells:

```tcl
# Set target leakage power
set_leakage_optimization true
set_max_leakage_power 0

# Prefer high-Vt cells where timing permits
set_multi_vth_constraint -lvth_percentage 20  ;# max 20% low-Vt cells
```

## Summary of Key Directives

| Directive | Effect | Use Case |
|-----------|--------|----------|
| `dont_touch` | Prevents all optimization | Debug nets, synchronizers, ECO points |
| `set_size_only` | Allows sizing only | Buffer chains, hold fix buffers |
| `set_dont_retime` | Prevents retiming | FSM registers, protocol registers |
| `set_ungroup` | Dissolves hierarchy | Small glue logic modules |
| `set_boundary_optimization` | Cross-port optimization | Internal modules (not for fixed interfaces) |
| `set_dp_smartgen` | Datapath optimization | Arithmetic-heavy designs |
| `set_dont_use` | Excludes library cells | Cells with known issues or high leakage |

Apply these constraints judiciously, document every directive with a justification, and verify the results with formal equivalence checking and timing analysis.
