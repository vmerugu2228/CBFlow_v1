# RTL-to-Gate Synthesis Fundamentals

## Overview

Logic synthesis transforms a Register Transfer Level (RTL) description written in Verilog or VHDL into a gate-level netlist mapped to a specific technology library. This transformation is the critical bridge between design intent and physical implementation. A well-executed synthesis run sets the trajectory for all downstream PnR steps — poor synthesis results propagate into timing closure nightmares, excessive area, and power overruns.

## Synthesis Flow Stages

### 1. Reading and Elaboration

Elaboration parses the RTL source, resolves parameters and generate statements, infers sequential and combinational logic, and builds an internal generic (technology-independent) representation.

**Key actions during elaboration:**

- Latch and flip-flop inference from `always` blocks
- Memory inference from array declarations
- Operator sharing and resource allocation decisions
- Hierarchy preservation or automatic ungrouping

**Common pitfalls:**

- Incomplete sensitivity lists causing simulation/synthesis mismatch
- Unintended latch inference from missing `else` or `default` in case statements
- Multi-driven nets causing X-propagation differences

### 2. Technology Mapping

The generic (GTECH) representation is mapped to cells from the target standard cell library. The mapper evaluates the technology library's timing models, area values, and drive strengths to select the best-fit cells.

**Mapping considerations:**

- Threshold voltage variants (SVT, HVT, LVT, ULVT) — tool selects Vt mix to meet timing with minimal leakage
- Drive strength selection based on estimated load and transition requirements
- Complex cell mapping (AOI, OAI, MUX, full-adder) vs. decomposed primitives

### 3. Optimization

After initial mapping, the synthesis tool iteratively optimizes the netlist to meet constraints. Optimization targets include:

- **Timing:** Meet setup time on all endpoints; minimize worst negative slack (WNS) and total negative slack (TNS)
- **Area:** Minimize total cell area and cell count
- **Power:** Reduce dynamic switching power and static leakage power

## Design Constraints (SDC)

Synopsys Design Constraints (SDC) is the industry-standard format for communicating design intent to synthesis and STA tools. A robust SDC is the single most important input to synthesis.

### Clock Definitions

```tcl
create_clock -name clk_core -period 1.0 [get_ports clk]
create_generated_clock -name clk_div2 -source [get_ports clk] -divide_by 2 [get_pins div_reg/Q]
```

### Input/Output Delays

```tcl
set_input_delay -clock clk_core -max 0.3 [all_inputs]
set_input_delay -clock clk_core -min 0.1 [all_inputs]
set_output_delay -clock clk_core -max 0.2 [all_outputs]
```

### Design Rule Constraints

```tcl
set_max_transition 0.15 [current_design]
set_max_fanout 20 [current_design]
set_max_capacitance 0.05 [current_design]
```

### False Paths and Multicycle Paths

```tcl
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
set_multicycle_path 2 -setup -from [get_pins mul_reg/Q] -to [get_pins result_reg/D]
set_multicycle_path 1 -hold  -from [get_pins mul_reg/Q] -to [get_pins result_reg/D]
```

## Compile Strategies

### Single-Pass Compile

A single `compile` or `compile_ultra` invocation. Suitable for small to mid-size blocks or initial exploration.

### Two-Pass (Compile + Incremental) Strategy

1. **First pass:** Aggressive optimization with `compile_ultra` targeting timing closure.
2. **Second pass:** `compile_ultra -incremental` preserves the structure from pass 1 while cleaning up remaining violations.

This prevents the tool from thrashing the netlist and destroying good paths while fixing bad ones.

### Top-Down vs. Bottom-Up

- **Top-down:** Entire hierarchy compiled together. The tool has full visibility but runtime and memory scale poorly for large designs.
- **Bottom-up:** Sub-blocks synthesized independently with budgeted constraints, then stitched at the top level. Essential for designs exceeding 5-10M instances.
- **Hybrid:** Critical blocks compiled top-down within a partition; non-critical blocks handled bottom-up.

### Boundary Optimization

```tcl
set_boundary_optimization [get_designs sub_block] false
```

Disabling boundary optimization preserves port-level equivalence for formal verification, at the cost of some QoR.

## Optimization Techniques

### Timing Optimization

- **Buffering and resizing:** Insert buffers on high-fanout nets; upsize cells on critical paths.
- **Logic restructuring:** Re-synthesize combinational clouds to reduce depth.
- **Register retiming:** Move registers across combinational logic to balance pipeline stages.
- **Operand isolation:** Gate inputs to datapath blocks when enable is deasserted to reduce switching power.
- **Ungrouping:** Flatten hierarchy boundaries to expose cross-boundary optimization opportunities.

### Area Optimization

- **Cell sharing:** Map multiple operations onto a single operator with mux-based selection.
- **Logic minimization:** Boolean optimization to reduce literal count.
- **Threshold voltage swapping:** Swap LVT cells to HVT on non-critical paths to reduce leakage (also a power technique).

### Power Optimization

- **Clock gating insertion:** Automatically insert clock gating cells for registers with enable conditions. This is the single highest-impact power optimization.
- **Multi-Vt optimization:** Start with all-HVT and selectively swap to LVT/SVT only where timing demands it.
- **Operand isolation:** Prevent toggling of unused datapath blocks.
- **Dynamic power optimization:** Restructure logic to minimize switching activity on high-capacitance nets.

```tcl
# Enable clock gating
set_clock_gating_style -num_stages 1 -positive_edge_logic integrated
insert_clock_gating
```

## Key Reports

After every synthesis run, review these reports:

| Report | Purpose |
|--------|---------|
| `report_timing` | Setup/hold slack on critical paths |
| `report_area` | Cell area, net area, total area |
| `report_power` | Dynamic, leakage, total power |
| `report_constraint -all_violators` | All constraint violations |
| `report_qor` | Summary: WNS, TNS, cell count |
| `report_clock_gating` | Clock gating coverage percentage |
| `report_threshold_voltage_group` | Vt distribution across the design |

## Common Issues and Fixes

**Issue: Large negative slack after compile**
- Check SDC for missing or incorrect clock definitions
- Verify input/output delays are realistic (not over-constraining)
- Increase compile effort: `-retime`, `compile_ultra`

**Issue: Excessive area**
- Review clock gating coverage — low coverage means flip-flops are not gated
- Check for unintended memory inference that should be mapped to SRAMs
- Enable `compile_ultra -area_high_effort_script`

**Issue: High leakage power**
- Confirm multi-Vt libraries are loaded and Vt swapping is enabled
- Set `set_max_leakage_power` constraint
- Check that HVT cells are available for the target node

**Issue: Formal verification failures post-synthesis**
- Disable boundary optimization on blocks that cause mismatches
- Verify the naming convention is preserved (`set_verification_top`)
- Write out the SVF (Setup Verification Guidance) file for Formality

## Best Practices

1. **Over-constrain by 10-15%** during synthesis to give PnR margin for wire delay and SI effects.
2. **Always run incremental compile** after the first pass — it typically recovers 10-20% of remaining violations.
3. **Target clock gating coverage above 85%** for power-sensitive designs.
4. **Preserve hierarchy** at the synthesis-PnR handoff boundary; flatten only inside blocks.
5. **Check max_transition and max_fanout violations** — these cause degradation during routing and SI.
6. **Write out the SDC, netlist, and parasitics** in consistent formats for downstream tools.
7. **Version-control your constraint files** and tag them with the synthesis tool version used.
8. **Profile runtime and memory** — synthesis of a 1M-gate block should not exceed 20-30 GB RAM with reasonable tool settings.
