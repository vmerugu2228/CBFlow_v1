# Cadence Genus Synthesis Guide

## Overview

Genus Synthesis Solution is Cadence's RTL-to-gate synthesis tool, the successor to RTL Compiler (RC). Genus supports advanced synthesis techniques including physical-aware synthesis, low-power optimization with CPF/UPF, and tight integration with the Cadence Innovus PnR flow. It serves as the synthesis engine in Cadence's digital full-flow alongside Tempus (STA) and Conformal (formal verification).

## Synthesis Flow Stages

The Genus flow follows a well-defined progression:

1. **Setup** — Library, HDL, and constraint loading
2. **Elaborate** — RTL parsing and internal representation
3. **syn_generic** — Technology-independent optimization
4. **syn_map** — Technology mapping to target library cells
5. **syn_opt** — Final gate-level optimization
6. **Export** — Write netlist, constraints, and verification collateral

## Setup and Design Read-In

### Library Setup

```tcl
# Set library search paths
set_db lib_search_path {./libs/nldm ./libs/ccs}

# Read timing libraries
set_db library {
    ss_0p72v_125c.lib
    ff_0p88v_m40c.lib
}

# Set operating conditions
set_db operating_conditions ss_0p72v_125c

# Read LEF for physical-aware synthesis
set_db lef_library {tech.lef stdcell.lef macros.lef}
```

### Reading HDL

```tcl
# Read Verilog/SystemVerilog
read_hdl -sv {rtl/top.sv rtl/sub1.v rtl/sub2.v}

# Read VHDL
read_hdl -vhdl {rtl/top.vhd}

# Read filelist
read_hdl -f rtl/filelist.f
```

### Elaboration

```tcl
elaborate top_module

# Check for elaboration issues
check_design -unresolved
```

During elaboration, Genus infers flip-flops, latches, RAMs, and ROMs from the RTL coding style. Review the elaboration log for unexpected inferences.

### Constraint Application

```tcl
# Read SDC constraints
read_sdc constraints/func_mode.sdc

# Or apply inline
create_clock -name clk -period 0.8 [get_ports clk]
set_input_delay -clock clk -max 0.2 [all_inputs]
set_output_delay -clock clk -max 0.2 [all_outputs]
set_max_transition 0.12 [current_design]
set_clock_uncertainty -setup 0.05 [all_clocks]
set_clock_uncertainty -hold 0.03 [all_clocks]
```

## Core Synthesis Commands

### syn_generic — Generic Optimization

```tcl
syn_generic
```

This phase performs technology-independent optimizations:

- Boolean optimization and logic minimization
- Common sub-expression extraction
- Resource sharing
- Arithmetic optimization (carry-save, Wallace tree selection)
- Register retiming (if enabled)

**Key attributes for syn_generic:**

```tcl
# Enable retiming
set_db syn_generic_effort high

# Control hierarchy
set_db auto_ungroup both
```

### syn_map — Technology Mapping

```tcl
syn_map
```

Maps the generic representation to target library cells. Considers:

- Cell area, timing, and power characteristics
- Multi-Vt cell availability (HVT, SVT, LVT)
- Complex cell utilization (AOI, OAI, MUX cells)

**Key attributes for syn_map:**

```tcl
set_db syn_map_effort high
```

### syn_opt — Gate-Level Optimization

```tcl
syn_opt
```

Final optimization pass operating on the mapped netlist:

- Cell sizing (upsizing critical, downsizing non-critical)
- Buffer insertion and removal
- Pin swapping
- Vt swapping for leakage reduction
- Logic restructuring within timing windows

**Key attributes for syn_opt:**

```tcl
set_db syn_opt_effort high
```

### Incremental Synthesis

After an initial synthesis run, incremental mode preserves the existing netlist structure while fixing remaining violations:

```tcl
# Read previously synthesized netlist
read_netlist post_syn.v
read_sdc updated.sdc

syn_opt -incr
```

Incremental synthesis is valuable after SDC updates, ECO changes, or when importing timing feedback from PnR.

## Physical-Aware Synthesis (iSpatial)

Genus can incorporate physical information to improve post-PnR correlation:

```tcl
# Enable physical-aware synthesis
set_db design_process_node 5
read_physical -lef {tech.lef stdcell.lef}

# Provide floorplan (optional but recommended)
read_physical -def floorplan.def

# Run with physical awareness
syn_generic -physical
syn_map -physical
syn_opt -physical
```

Physical-aware synthesis estimates wire lengths and congestion, resulting in netlists that correlate much better with PnR outcomes (typically 5-15% WNS improvement post-PnR).

## Clock Gating

```tcl
# Enable clock gating insertion
set_db lp_insert_clock_gating true

# Clock gating style
set_db lp_clock_gating_min_flops 4
set_db lp_clock_gating_max_flops 64

# Specify ICG cell
set_db lp_clock_gating_cell [get_lib_cells */CKLNQD*]
```

Target clock gating coverage of 85% or higher. Review with:

```tcl
report_clock_gating
```

## DFT Integration

Genus supports DFT-aware synthesis and scan insertion:

```tcl
# Define scan configuration
define_scan_chain -name chain1 -sdi scan_in1 -sdo scan_out1
set_db dft_scan_style muxed_scan
set_db dft_scan_map_mode tdrc_pass

# Insert scan after syn_opt
syn_opt
insert_dft

# Verify scan chains
check_dft_rules
report_scan_chains
```

## Multi-Mode Multi-Corner (MMMC)

```tcl
# Create analysis views
create_constraint_mode -name func -sdc_files func.sdc
create_constraint_mode -name test -sdc_files test.sdc

create_library_set -name ss_libs -timing {ss.lib}
create_library_set -name ff_libs -timing {ff.lib}

create_timing_condition -name ss_cond -library_sets ss_libs
create_timing_condition -name ff_cond -library_sets ff_libs

create_rc_corner -name rc_worst -qrc_tech qrc_worst.tech
create_rc_corner -name rc_best  -qrc_tech qrc_best.tech

create_delay_corner -name ss_corner -timing_condition ss_cond -rc_corner rc_worst
create_delay_corner -name ff_corner -timing_condition ff_cond -rc_corner rc_best

create_analysis_view -name func_ss -constraint_mode func -delay_corner ss_corner
create_analysis_view -name func_ff -constraint_mode func -delay_corner ff_corner
create_analysis_view -name test_ss -constraint_mode test -delay_corner ss_corner

set_analysis_view -setup {func_ss test_ss} -hold {func_ff}
```

## Key Reports

```tcl
# Timing
report_timing -max_paths 50 -nworst 3 > rpt/timing.rpt

# Area
report_area > rpt/area.rpt

# Power
report_power > rpt/power.rpt

# DRC (design rule) violations
report_violations > rpt/violations.rpt

# QoR summary
report_qor > rpt/qor.rpt

# Clock gating
report_clock_gating > rpt/cg.rpt

# Datapath
report_dp > rpt/datapath.rpt

# Messages summary
report_messages > rpt/messages.rpt
```

## Design Export

```tcl
# Write gate-level netlist
write_hdl > output/top_syn.v

# Write SDC
write_sdc > output/top_syn.sdc

# Write DEF (for physical-aware handoff)
write_def > output/top_syn.def

# Write SDF
write_sdf > output/top_syn.sdf

# Write design database
write_design -innovus -base_name output/top_syn
```

The `write_design -innovus` command generates all necessary files for Innovus import: netlist, SDC, scan DEF, and MMMC configuration.

## Common Issues and Fixes

**Issue: syn_opt runtime is excessive (>24 hours for a moderate block)**
- Reduce effort: `set_db syn_opt_effort medium`
- Limit optimization iterations: `set_db syn_opt_max_iterations 3`
- Ungroup only critical hierarchies instead of flattening everything
- Use physical-aware mode — better initial correlation means fewer optimization passes

**Issue: Poor correlation with Innovus PnR timing**
- Enable physical-aware synthesis with actual floorplan DEF
- Ensure wire load models match PnR extraction settings
- Over-constrain by 10% in synthesis to absorb routing pessimism
- Use `write_design -innovus` for clean handoff

**Issue: Clock gating not being inserted**
- Verify `lp_insert_clock_gating` is true
- Check that ICG cells are in the library and not excluded
- Ensure register enable widths meet the `lp_clock_gating_min_flops` threshold
- Review `report_clock_gating -ungated` to understand why specific registers are skipped

**Issue: High leakage power**
- Confirm multi-Vt libraries are loaded with all threshold variants
- Set leakage optimization: `set_db lp_power_optimization_weight 0.5`
- Target: majority of cells on HVT, only timing-critical paths on LVT/SVT

**Issue: Formal verification failures (Conformal LEC)**
- Write the `do` file for Conformal: `write_do_lec -revised output/lec.do`
- Ensure boundary optimization is disabled on verification boundaries
- Check for retiming or register merging that changes sequential equivalence

## Best Practices

1. **Run all three synthesis stages** (syn_generic, syn_map, syn_opt) — skipping stages loses optimization opportunities.
2. **Use physical-aware synthesis** for any design targeting advanced nodes (7nm and below).
3. **Start with high effort** and only reduce if runtime is unacceptable.
4. **Write the Conformal do file** immediately after synthesis — it captures the transformation sequence Genus applied.
5. **Review the datapath report** to verify that arithmetic operators are mapped to efficient structures (carry-save adders, Booth multipliers).
6. **Constrain realistically** — over-constraining by more than 15-20% leads to area bloat and diminishing returns.
7. **Use MMMC from the start** — post-hoc addition of corners causes optimization churn.
8. **Archive the Genus database** (`write_db`) at each milestone for debug and incremental re-runs.
