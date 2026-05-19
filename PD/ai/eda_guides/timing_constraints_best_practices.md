# Timing Constraints Best Practices: SDC Quality and Reliability

## The Cost of Bad Constraints

Timing constraints (SDC) are the specification that drives every optimization decision in synthesis and physical design. Incorrect constraints lead to one of two outcomes: over-constraining (wasted area, power, and schedule) or under-constraining (silicon failures). Studies at major semiconductor companies consistently show that SDC errors are the number-one cause of functional silicon failures related to timing. Investing time in constraint quality is the highest-leverage activity in the entire PD flow.

## Clock Modeling Best Practices

### Define All Clocks Explicitly

Never rely on the tool to infer clocks. Every clock source must have a `create_clock` or `create_generated_clock` command.

```tcl
# Every clock port gets a definition
create_clock -name sys_clk -period 1.0 [get_ports sys_clk]
create_clock -name ref_clk -period 10.0 [get_ports ref_clk]
create_clock -name jtag_tck -period 50.0 [get_ports TCK]
```

### Use Generated Clocks Correctly

Generated clocks maintain a master-source relationship. This allows the tool to compute the phase relationship between the generated clock and its master.

```tcl
# Correct: generated clock with source
create_generated_clock -name pll_clk \
  -source [get_pins pll/ref_in] \
  -multiply_by 8 \
  [get_pins pll/clk_out]

# Wrong: defining PLL output as a primary clock
# This loses the phase relationship with the reference
create_clock -name pll_clk -period 0.5 [get_pins pll/clk_out]  ;# DON'T DO THIS
```

Use `create_clock` for a PLL output only when the PLL is treated as an ideal clock source with no known phase relationship to the reference.

### Model Clock Muxes with Multiple Generated Clocks

When a clock mux selects between two sources, define a generated clock for each source:

```tcl
create_generated_clock -name clk_from_pll \
  -source [get_pins pll/clk_out] \
  -combinational [get_pins clk_mux/Y]

create_generated_clock -name clk_from_osc \
  -source [get_ports osc_clk] \
  -combinational [get_pins clk_mux/Y] -add

# Mark as physically exclusive (only one active at a time)
set_clock_groups -physically_exclusive \
  -group [get_clocks clk_from_pll] \
  -group [get_clocks clk_from_osc]
```

### Virtual Clocks for IO Timing

Use virtual clocks as references for IO constraints when the external clock is not directly present in the design:

```tcl
# Virtual clock -- no source pin
create_clock -name vclk_ddr -period 2.5

# IO delays reference the virtual clock
set_input_delay -clock vclk_ddr -max 1.0 [get_ports ddr_data_in[*]]
set_output_delay -clock vclk_ddr -max 0.8 [get_ports ddr_data_out[*]]
```

### Clock Uncertainty Management

Pre-CTS uncertainty should account for estimated clock jitter plus clock tree skew. Post-CTS uncertainty should be reduced to just jitter (since actual skew is now known):

```tcl
# Pre-CTS
set_clock_uncertainty -setup 0.150 [get_clocks sys_clk]  ;# jitter + skew estimate
set_clock_uncertainty -hold  0.050 [get_clocks sys_clk]

# Post-CTS (update to jitter only)
set_clock_uncertainty -setup 0.030 [get_clocks sys_clk]  ;# jitter only
set_clock_uncertainty -hold  0.020 [get_clocks sys_clk]
```

## IO Constraint Best Practices

### Constrain Every Port

Every input and output port must have timing constraints. Unconstrained ports mean unconstrained paths, which the tool ignores during optimization.

```tcl
# Check for unconstrained ports
report_port -verbose
check_timing -override_defaults {no_input_delay no_output_delay}
```

### Realistic IO Delays

IO delays should reflect actual board timing, not arbitrary numbers. Work with the system architect or board designer to get:

- **Input delay:** Board trace delay + external device output delay + clock skew between chips
- **Output delay:** Board trace delay + external device setup/hold time + clock skew

```tcl
# Based on actual board timing analysis
# External device Tco_max = 3.0ns, board trace = 0.5ns
set_input_delay -clock sys_clk -max 3.5 [get_ports ext_data_in]

# External device Tsu = 1.0ns, board trace = 0.5ns
set_output_delay -clock sys_clk -max 1.5 [get_ports ext_data_out]
```

### IO Budget Accounting

The total timing budget for an IO path must equal the clock period:

```
Tperiod = Tco_internal + Tboard_out + Tsetup_external + Tboard_clk_skew
        = output_path_delay + output_delay
```

If `set_output_delay -max 1.5` and the clock period is 5.0ns, the internal path budget is 5.0 - 1.5 = 3.5ns.

## Inter-Clock Exception Best Practices

### Be Specific with False Paths

Avoid blanket false paths that cover too many paths:

```tcl
# Too broad -- false-paths ALL paths from clk_a, even intra-domain
set_false_path -from [get_clocks clk_a]  ;# DANGEROUS

# Correct -- only false-path the crossing, not intra-domain
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
```

### Validate Asynchronous Claims

Before marking two clocks as asynchronous, verify they are truly unrelated:

- Are they derived from the same PLL? If so, they may have a fixed phase relationship and should not be false-pathed.
- Is there a frequency relationship (e.g., one is 2x the other)? Related clocks need proper setup/hold analysis, not false paths.

### Use set_clock_groups Consistently

Group all asynchronous clocks in a single `set_clock_groups` command rather than multiple `set_false_path` commands:

```tcl
# Clean and comprehensive
set_clock_groups -asynchronous \
  -group [get_clocks {sys_clk pll_clk_div2}] \
  -group [get_clocks {usb_clk}] \
  -group [get_clocks {pcie_clk}] \
  -group [get_clocks {jtag_tck}]
```

## Constraint File Organization

### Structure by Purpose

```
constraints/
  clocks.sdc              # All clock definitions (shared across all modes)
  io_constraints.sdc      # All IO delay and drive/load constraints
  exceptions_common.sdc   # Exceptions common to all modes
  func_mode.sdc           # Functional mode case analysis + exceptions
  scan_mode.sdc           # Scan mode case analysis + exceptions
  jtag_mode.sdc           # JTAG mode constraints
  design_rules.sdc        # max_transition, max_capacitance, max_fanout
```

### Loading Order Matters

SDC commands are order-dependent. Clocks must be defined before they are referenced in constraints:

```tcl
# Correct order
source clocks.sdc              ;# 1. Define all clocks first
source io_constraints.sdc      ;# 2. IO constraints reference clocks
source exceptions_common.sdc   ;# 3. Exceptions reference clocks
source func_mode.sdc           ;# 4. Mode-specific overrides
source design_rules.sdc        ;# 5. Design rules last
```

## Constraint Validation Methodology

### Automated Checks

Run these checks after loading every SDC set:

```tcl
# Check for unconstrained paths
check_timing -verbose

# Report all exceptions
report_exceptions

# Report unclocked registers
report_clock -skew

# Report unconstrained endpoints
report_timing -unconstrained -max_paths 100

# Check for conflicting exceptions
report_exceptions -conflict
```

### Manual Review Checklist

1. Every clock has a `create_clock` or `create_generated_clock`
2. Every IO port has input/output delay constraints
3. Every inter-clock relationship is defined (synchronous, asynchronous, or exclusive)
4. Every `set_multicycle_path -setup N` has a matching `-hold N-1`
5. Every `set_false_path` has a documented justification
6. No duplicate or conflicting constraints
7. Clock uncertainty values are reasonable for the technology and design stage
8. Design rule constraints (max_transition, max_cap) match the foundry spec

### Constraint Coverage Metrics

Track these metrics across the project:

| Metric | Target |
|---|---|
| Unconstrained endpoints | 0 |
| Unclocked registers | 0 |
| Unconstrained IO ports | 0 |
| Undocumented false paths | 0 |
| Missing hold MCPs | 0 |

## Common Anti-Patterns

### The "set_false_path -to" Hammer

```tcl
# Hiding violations by false-pathing the endpoint
set_false_path -to [get_cells problem_reg]  ;# WRONG: masks real timing issue
```

### Overly Optimistic IO Delays

```tcl
# IO delay of 0 means the tool assumes infinite budget internally
set_input_delay -clock sys_clk 0.0 [get_ports data_in]  ;# WRONG: unrealistic
```

### Stale Constraints After RTL Changes

When the RTL adds a new clock domain, new IO ports, or changes the pipeline structure, the SDC must be updated immediately. Stale constraints that do not match the current RTL are the most common constraint quality issue.

### Copy-Paste Constraint Errors

Constraints copied from one project to another without adapting clock names, port names, and timing values.

## Signoff Constraint Review

Before final timing signoff, conduct a formal constraint review:

1. **Diff the SDC against the design specification.** Every clock, every mode, every IO interface should be traceable to a specification.
2. **Run formal constraint verification** (e.g., Synopsys VC SpyGlass CDC, Cadence Conformal) to identify structural constraint issues.
3. **Compare constraint coverage** between modes to identify gaps.
4. **Review with the design team.** The designers know the design intent; the PD team knows the constraint syntax. Both must agree.

High-quality SDC is not optional. It is the foundation of reliable timing closure and the single most important factor in achieving silicon success on the first tapeout.
