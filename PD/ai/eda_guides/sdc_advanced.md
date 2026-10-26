# Advanced SDC: Generated Clocks, Clock Groups, Latency Modeling, and Jitter

## Overview

Synopsys Design Constraints (SDC) is the industry-standard format for specifying timing constraints in VLSI design. While basic SDC covers clock definitions and I/O timing, advanced SDC usage is essential for complex SoCs with multiple clock domains, generated clocks, source latency requirements, and sophisticated clock relationships. Mastering advanced SDC directly impacts timing closure efficiency, as incorrect constraints lead to either false violations (over-constraining) or missed real timing issues (under-constraining).

## Generated Clocks

### Fundamentals

Generated clocks are derived from a master (source) clock through frequency division, multiplication, or phase shifting:

```tcl
# Master clock definition
create_clock -name CLK_SYS -period 2.0 -waveform {0 1.0} [get_ports clk_sys]

# Divide-by-2 generated clock
create_generated_clock -name CLK_DIV2 \
  -source [get_ports clk_sys] \
  -divide_by 2 \
  [get_pins u_divider/clk_out]

# Multiply-by-2 (PLL output)
create_generated_clock -name CLK_PLL_2X \
  -source [get_pins u_pll/clk_ref] \
  -multiply_by 2 \
  [get_pins u_pll/clk_out]
```

### Generated Clock Properties

- **Source latency**: inherits source latency from the master clock
- **Timing relationship**: generated clocks maintain a known phase relationship to their master
- **Phase specification**: can specify exact edges using `-edges` and `-edge_shift`

### Complex Edge Specifications

For non-integer division or duty cycle modification:

```tcl
# Divide-by-3 with specific edges
create_generated_clock -name CLK_DIV3 \
  -source [get_pins u_pll/clk_ref] \
  -edges {1 4 7} \
  [get_pins u_divider/clk_out]

# Divide-by-2 with duty cycle adjustment (60/40)
create_generated_clock -name CLK_ASYM \
  -source [get_ports clk_sys] \
  -edges {1 2 3} \
  -edge_shift {0 0.2 0} \
  [get_pins u_divider/clk_out]
```

The `-edges` option specifies which edges of the master clock define the generated clock edges (1-based counting of both rise and fall edges).

### Multiple Generated Clocks on Same Pin

When a mux selects between clock sources:

```tcl
# Two possible clocks on the same mux output
create_generated_clock -name CLK_MUX_A \
  -source [get_pins u_mux/A] \
  -divide_by 1 \
  [get_pins u_mux/Y] \
  -add -master_clock CLK_A

create_generated_clock -name CLK_MUX_B \
  -source [get_pins u_mux/B] \
  -divide_by 1 \
  [get_pins u_mux/Y] \
  -add -master_clock CLK_B
```

The `-add` flag allows multiple clock definitions on the same pin. The tool analyzes timing for both clocks.

## Clock Groups

### set_clock_groups

Clock groups define the timing relationship between clocks:

```tcl
# Asynchronous clocks: no timing paths checked between groups
set_clock_groups -asynchronous \
  -group {CLK_SYS CLK_DIV2} \
  -group {CLK_USB} \
  -group {CLK_PCIE}

# Exclusive clocks: never active simultaneously (mux-selected)
set_clock_groups -exclusive \
  -group {CLK_MUX_A} \
  -group {CLK_MUX_B}

# Physically exclusive: different clocks on the same pin
set_clock_groups -physically_exclusive \
  -group {CLK_TEST} \
  -group {CLK_FUNC}
```

### Asynchronous vs. Exclusive

- **Asynchronous**: clocks exist simultaneously but have no known phase relationship; the tool does not time paths between these groups. CDC (clock domain crossing) logic handles the actual synchronization.
- **Exclusive**: clocks are never active at the same time (mux-selected). No timing analysis between groups because they are mutually exclusive in operation.
- **Physically exclusive**: different clock definitions on the same physical pin (e.g., test clock vs. functional clock). Only one is active per mode.

### Logically Exclusive

```tcl
set_clock_groups -logically_exclusive \
  -group {CLK_MUX_A} \
  -group {CLK_MUX_B}
```

Logically exclusive clocks come from different source pins but are never active simultaneously (controlled by a mux). The tool removes timing paths between these groups but still checks each group independently.

### Common Mistakes with Clock Groups

- **Over-grouping**: making clocks asynchronous when they actually have a known relationship; masks real timing violations
- **Missing groups**: forgetting to declare asynchronous clocks; the tool assumes they are synchronous and may report false violations or (worse) apply incorrect timing relationships
- **Exclusive vs. asynchronous**: using exclusive for clocks that ARE active simultaneously (e.g., in different parts of the chip); this suppresses valid timing checks

## Clock Latency

### set_clock_latency

Clock latency represents the delay from the clock source to the clock pin of sequential elements:

```tcl
# Source latency: delay from actual clock source (crystal, PLL) to clock definition point
set_clock_latency -source -early 0.5 [get_clocks CLK_SYS]
set_clock_latency -source -late 0.8 [get_clocks CLK_SYS]

# Network latency: delay from clock definition point to register clock pins
# (typically estimated pre-CTS; replaced by actual CTS post-CTS)
set_clock_latency -early 0.3 [get_clocks CLK_SYS]
set_clock_latency -late 0.5 [get_clocks CLK_SYS]
```

### Source Latency

Source latency models the delay from the true clock origin to the SDC clock definition point:

- **Off-chip source latency**: crystal oscillator to PLL input, board trace delay
- **PLL output latency**: PLL internal delay from reference input to output
- **Use case**: when the clock definition point is not the true origin (e.g., create_clock on a chip pin, but actual clock starts at off-chip crystal)

```tcl
# Model PLL jitter and delay as source latency on the generated clock
set_clock_latency -source -early 0.1 [get_clocks CLK_PLL_OUT]
set_clock_latency -source -late 0.3 [get_clocks CLK_PLL_OUT]
```

The difference between early and late source latency creates on-chip variation (OCV) in clock arrival, which must be accounted for in timing analysis.

### Network Latency

Network latency estimates the on-chip clock distribution delay:

- **Pre-CTS**: set estimated network latency to guide synthesis optimization
- **Post-CTS**: remove network latency; actual clock tree delay is computed from the clock tree
- **set_propagated_clock**: tells the tool to use actual clock tree delay instead of ideal latency

```tcl
# After CTS, propagate actual clock tree delays
set_propagated_clock [all_clocks]
```

## Clock Uncertainty

### set_clock_uncertainty

Clock uncertainty models the unknown timing variation between launch and capture clocks:

```tcl
# Inter-clock uncertainty (between different clocks)
set_clock_uncertainty -setup 0.3 -from CLK_A -to CLK_B
set_clock_uncertainty -hold 0.1 -from CLK_A -to CLK_B

# Intra-clock uncertainty (same clock, setup)
set_clock_uncertainty -setup 0.2 [get_clocks CLK_SYS]
set_clock_uncertainty -hold 0.05 [get_clocks CLK_SYS]
```

### Components of Uncertainty

Clock uncertainty encompasses several physical effects:

- **PLL jitter**: cycle-to-cycle and period jitter from the PLL
- **Clock tree skew** (pre-CTS): estimated skew before clock tree is built
- **OCV (On-Chip Variation)**: process variation causing different delays in launch vs. capture clock paths
- **Margin**: additional timing margin for design guardband

**Pre-CTS uncertainty:**
```
uncertainty_setup = skew_estimate + jitter + OCV_margin + guardband
uncertainty_hold = skew_estimate + jitter
```

**Post-CTS uncertainty (actual skew is computed):**
```
uncertainty_setup = jitter + OCV_margin + guardband
uncertainty_hold = jitter
```

## Jitter Modeling

### Types of Jitter

- **Period jitter**: variation in clock period from cycle to cycle
- **Cycle-to-cycle jitter**: variation between consecutive periods
- **Long-term jitter**: accumulated phase error over many cycles (affects source-synchronous interfaces)
- **Duty cycle distortion**: difference between positive and negative half-periods

### Modeling Jitter in SDC

Jitter is modeled through clock uncertainty:

```tcl
# PLL with 50 ps peak-to-peak jitter
# Setup: add jitter to uncertainty (affects available timing window)
set_clock_uncertainty -setup 0.05 [get_clocks CLK_PLL_OUT]

# Hold: jitter also affects hold (opposite clock edge uncertainty)
set_clock_uncertainty -hold 0.025 [get_clocks CLK_PLL_OUT]
```

For more detailed jitter modeling, some tools support `set_clock_jitter` or equivalent commands.

### Source Latency for Jitter

An alternative approach for PLL jitter modeling:

```tcl
# Model jitter as variation in source latency
set_clock_latency -source -early -0.025 [get_clocks CLK_PLL_OUT]
set_clock_latency -source -late 0.025 [get_clocks CLK_PLL_OUT]
```

This applies the jitter at the clock source, which may be more physically accurate than applying it uniformly at all endpoints.

## Advanced Constraint Techniques

### Multi-Cycle Paths

```tcl
# Path that takes 2 clock cycles (launch to capture)
set_multicycle_path -setup 2 -from [get_clocks CLK_SLOW] -to [get_clocks CLK_FAST]
set_multicycle_path -hold 1 -from [get_clocks CLK_SLOW] -to [get_clocks CLK_FAST]
```

**Hold adjustment**: when specifying multi-cycle setup of N, the hold check moves to cycle N-1 by default. Typically, you want hold checked at the same launch edge, so set hold multi-cycle to N-1.

### False Paths

```tcl
# Paths between asynchronous domains (covered by CDC logic)
set_false_path -from [get_clocks CLK_USB] -to [get_clocks CLK_SYS]

# Static configuration registers (set once, never changes during operation)
set_false_path -from [get_cells u_config/reg_*]

# Test-only paths in functional mode
set_false_path -from [get_ports scan_enable]
```

### Min/Max Delay

For specific interface timing requirements:

```tcl
# Source-synchronous output (specify skew budget)
set_max_delay 0.5 -from [get_clocks CLK_TX] -to [get_ports data_out[*]]
set_min_delay -0.2 -from [get_clocks CLK_TX] -to [get_ports data_out[*]]
```

### set_disable_timing

Disable timing through specific cell arcs:

```tcl
# Break combinational loop for timing analysis
set_disable_timing -from A -to Y [get_cells u_mux]
```

## SDC Verification

### Constraint Checking

- **check_timing**: identify unconstrained paths, unclocked registers, missing exceptions
- **report_clock -skew**: verify clock relationships
- **report_exceptions**: list all false paths, multi-cycle paths, and other exceptions
- **report_analysis_coverage**: identify what percentage of timing paths are constrained

### Common SDC Issues

1. **Unconstrained paths**: registers not reached by any clock; invisible to timing analysis
2. **Over-constraining**: unnecessary false path removal that masks real violations
3. **Incorrect multi-cycle**: wrong hold adjustment causing hold violations
4. **Missing clock groups**: synchronous analysis of asynchronous domains (false path coverage)
5. **Post-CTS mismatch**: forgetting to update uncertainty after CTS; double-counting skew

Well-crafted SDC constraints are the foundation of timing closure. Every constraint should be justified by the actual hardware behavior, documented for maintainability, and verified for correctness before relying on timing analysis results.
