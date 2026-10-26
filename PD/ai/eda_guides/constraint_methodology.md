# Constraint Methodology: SDC Writing for Timing Analysis

## SDC Fundamentals

Synopsys Design Constraints (SDC) is the industry-standard format for specifying timing constraints. SDC commands are Tcl-based and define clocks, input/output timing relationships, timing exceptions, and design rule constraints. The quality of SDC directly determines the quality of synthesis, placement, optimization, and timing signoff. Incorrect or incomplete SDC is the single most common cause of silicon failures related to timing.

## Clock Definition

### Primary Clocks

Every clock entering the design must be explicitly defined. The tool will not infer clocks from the netlist.

```tcl
# Simple clock definition
create_clock -name sys_clk -period 2.0 [get_ports clk]

# Clock with explicit waveform (rise at 0, fall at 1.0ns = 50% duty cycle)
create_clock -name sys_clk -period 2.0 -waveform {0 1.0} [get_ports clk]

# Non-50% duty cycle
create_clock -name asym_clk -period 10.0 -waveform {0 3.0} [get_ports clk_asym]
```

### Virtual Clocks

Virtual clocks have no physical source pin. They serve as timing references for IO constraints when the external clock is not directly accessible in the design.

```tcl
# Virtual clock for IO constraint reference
create_clock -name vclk_ext -period 5.0
# No get_ports -- this clock has no physical source

set_input_delay -clock vclk_ext 2.0 [get_ports data_in]
set_output_delay -clock vclk_ext 1.5 [get_ports data_out]
```

### Generated Clocks

Generated clocks are derived from primary clocks through dividers, multiplexers, or other clock-modifying logic. They maintain a master-clock relationship that the tool uses for inter-clock timing analysis.

```tcl
# Divided clock (divide by 2)
create_generated_clock -name clk_div2 -source [get_ports clk] \
  -divide_by 2 [get_pins divider/clk_out]

# Multiplied clock (PLL output)
create_generated_clock -name pll_out -source [get_pins pll/clk_in] \
  -multiply_by 4 [get_pins pll/clk_out]

# Mux-selected clock (two possible sources)
create_generated_clock -name clk_mux_a -source [get_pins mux/A] \
  -combinational [get_pins mux/Y]
create_generated_clock -name clk_mux_b -source [get_pins mux/B] \
  -combinational [get_pins mux/Y] -add

# Edge-based generated clock
create_generated_clock -name clk_edge -source [get_ports clk] \
  -edges {1 3 5} [get_pins edge_div/out]
```

## Input and Output Delays

IO delays constrain paths that cross the design boundary. They tell the tool how much of the clock period is consumed outside the block.

### Input Delay

Specifies the delay from the clock edge to when data arrives at the input port.

```tcl
# Setup: data arrives 1.5ns after clock edge
set_input_delay -clock sys_clk -max 1.5 [get_ports data_in]

# Hold: data is stable at least 0.3ns after clock edge
set_input_delay -clock sys_clk -min 0.3 [get_ports data_in]

# Both rise and fall edges
set_input_delay -clock sys_clk -max 1.5 -rise [get_ports data_in]
set_input_delay -clock sys_clk -max 1.8 -fall [get_ports data_in]

# DDR interface (constrained on both edges)
set_input_delay -clock ddr_clk -max 0.8 [get_ports ddr_data]
set_input_delay -clock ddr_clk -max 0.8 -clock_fall -add [get_ports ddr_data]
```

### Output Delay

Specifies the delay from the output port to the external capturing flip-flop, including board trace and setup time.

```tcl
# Setup: external path consumes 1.0ns after the output port
set_output_delay -clock sys_clk -max 1.0 [get_ports data_out]

# Hold: external path has minimum 0.2ns delay
set_output_delay -clock sys_clk -min 0.2 [get_ports data_out]
```

## Timing Exceptions

### False Paths

False paths are timing paths that are logically or functionally impossible and should be excluded from timing analysis. Over-using false paths is dangerous -- it can mask real violations.

```tcl
# CDC false path (synchronizer handles the crossing)
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]

# Static configuration register (written once, read always)
set_false_path -from [get_cells config_reg/*]

# Mutually exclusive mux paths
set_false_path -through [get_pins mux/sel_a] -through [get_pins mux/sel_b]
```

### Multicycle Paths

Multicycle paths are real paths that are allowed more than one clock cycle to propagate. The data is sampled every N cycles, not every cycle.

```tcl
# 2-cycle setup path (data valid every 2 clocks)
set_multicycle_path 2 -setup -from [get_cells slow_reg/*] -to [get_cells fast_reg/*]
# Corresponding hold adjustment (hold is checked at edge N-1 = 1)
set_multicycle_path 1 -hold -from [get_cells slow_reg/*] -to [get_cells fast_reg/*]

# 3-cycle path
set_multicycle_path 3 -setup -from [get_pins pipeline/stage1/*/Q]
set_multicycle_path 2 -hold  -from [get_pins pipeline/stage1/*/Q]
```

The hold multicycle value for a setup multicycle of N is typically N-1. This moves the hold check edge back so it aligns with the launch edge, preventing the tool from checking hold at an incorrect edge.

### Max and Min Delay

Explicit delay constraints override the default clock-based analysis for specific paths.

```tcl
# Maximum delay constraint (async path with known timing budget)
set_max_delay 3.0 -from [get_ports async_in] -to [get_cells sync_reg/D]

# Minimum delay constraint
set_min_delay 0.5 -from [get_cells launch_reg/Q] -to [get_cells capture_reg/D]

# set_max_delay with -datapath_only (ignores clock path, useful for CDC)
set_max_delay 2.0 -datapath_only \
  -from [get_clocks clk_a] -to [get_clocks clk_b]
```

## Clock Uncertainty and Latency

```tcl
# Pre-CTS: model estimated clock tree insertion delay and skew
set_clock_uncertainty -setup 0.15 [get_clocks sys_clk]
set_clock_uncertainty -hold  0.05 [get_clocks sys_clk]

# Inter-clock uncertainty
set_clock_uncertainty -setup 0.20 -from [get_clocks clk_a] -to [get_clocks clk_b]

# Clock latency (pre-CTS, replaced by propagated clock post-CTS)
set_clock_latency -source 1.5 [get_clocks sys_clk]
set_clock_latency 0.8 [get_clocks sys_clk]  ;# network latency
```

## Clock Groups

Define relationships between clocks that do not have a known phase relationship.

```tcl
# Asynchronous clocks -- no timing checks between them
set_clock_groups -asynchronous \
  -group [get_clocks sys_clk] \
  -group [get_clocks usb_clk] \
  -group [get_clocks pcie_clk]

# Physically exclusive clocks (share same source, mux-selected)
set_clock_groups -physically_exclusive \
  -group [get_clocks clk_mux_a] \
  -group [get_clocks clk_mux_b]

# Logically exclusive clocks (active in different modes)
set_clock_groups -logically_exclusive \
  -group [get_clocks func_clk] \
  -group [get_clocks test_clk]
```

## Design Rule Constraints

```tcl
# Maximum transition (slew) on all nets
set_max_transition 0.2 [current_design]

# Maximum capacitance
set_max_capacitance 0.15 [current_design]

# Maximum fanout
set_max_fanout 30 [current_design]

# Tighter constraints on clock nets
set_max_transition 0.1 [get_clocks sys_clk]
```

## Constraint Validation Checklist

1. **Every flip-flop must be clocked.** Run `report_clock -skew` and check for unclocked registers.
2. **Every IO port must be constrained.** Run `report_port -verbose` to find unconstrained ports.
3. **No unconstrained paths.** Use `report_timing -unconstrained` to identify gaps.
4. **False paths are justified.** Every `set_false_path` should have a comment explaining why the path is false.
5. **Multicycle paths have matching hold adjustments.** A `set_multicycle_path N -setup` without the corresponding `-hold` is almost always a bug.
6. **Clock groups are correct.** Verify that asynchronous clock groups actually have no phase relationship and that exclusive groups are truly exclusive.
7. **No conflicting constraints.** Check for overlapping or contradictory exceptions using `report_exceptions`.
8. **Constraint consistency across modes.** Clock definitions should be identical across all modes; only exceptions and case analysis differ.

Well-written SDC is the single most important deliverable from the design team to the physical design team. Time invested in constraint quality pays dividends in fewer timing iterations and higher confidence in silicon correctness.
