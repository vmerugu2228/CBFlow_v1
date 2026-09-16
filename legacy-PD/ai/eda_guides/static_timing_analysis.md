# Static Timing Analysis (STA) Fundamentals

## Overview

Static Timing Analysis is a mathematical method for verifying timing correctness of a digital circuit without requiring simulation vectors. STA exhaustively checks all timing paths in the design by computing arrival times and required times at every node, then comparing them to determine slack. It is the gold standard for timing signoff in ASIC and SoC design.

Unlike dynamic simulation, STA does not require input stimulus and checks all possible paths (including rare corner cases that simulation might miss). However, STA is inherently pessimistic — it considers worst-case conditions across all modes and corners.

## Fundamental Timing Checks

### Setup Check

A setup check verifies that data arrives at a flip-flop's D input sufficiently before the capturing clock edge.

**Setup Slack = Required Arrival Time - Data Arrival Time**

```
Required Arrival Time = Capture Clock Arrival - Setup Time of FF - Clock Uncertainty
Data Arrival Time = Launch Clock Arrival + Tclk-to-Q + Combinational Delay
```

A positive setup slack means the path meets timing. Negative slack is a timing violation.

**Setup is checked at the slow corner** (high temperature, low voltage, slow process) where delays are maximum.

### Hold Check

A hold check verifies that data remains stable at the D input for a minimum duration after the capturing clock edge.

**Hold Slack = Data Arrival Time - Required Arrival Time**

```
Required Arrival Time = Capture Clock Arrival + Hold Time of FF + Clock Uncertainty
Data Arrival Time = Launch Clock Arrival + Tclk-to-Q (min) + Combinational Delay (min)
```

**Hold is checked at the fast corner** (low temperature, high voltage, fast process) where delays are minimum.

### Recovery and Removal Checks

These are the asynchronous equivalents of setup and hold, applied to asynchronous signals (reset, set, clear) relative to the clock.

- **Recovery:** Async signal must deassert sufficiently before the active clock edge (like setup).
- **Removal:** Async signal must deassert sufficiently after the active clock edge (like hold).

## Timing Path Components

### Clock Path (Launch)

The path from the clock source through the clock tree to the clock pin of the launching flip-flop.

```
Clock Source -> Clock Buffer Chain -> Launch FF Clock Pin
```

### Data Path

The path from the launching flip-flop's Q output through combinational logic to the capturing flip-flop's D input.

```
Launch FF/Q -> Combinational Logic -> Capture FF/D
```

### Clock Path (Capture)

The path from the clock source through the clock tree to the clock pin of the capturing flip-flop.

```
Clock Source -> Clock Buffer Chain -> Capture FF Clock Pin
```

### Path Delay Components

| Component | Description |
|-----------|-------------|
| Cell delay | Propagation delay through a logic gate, function of input transition and output load |
| Wire delay | Signal propagation delay through interconnect, function of R and C |
| Clock-to-Q | Delay from clock edge to Q output transition of a flip-flop |
| Setup time | Minimum time data must be stable before clock edge |
| Hold time | Minimum time data must be stable after clock edge |

## Clock Uncertainty and OCV

### Clock Uncertainty

Clock uncertainty (or clock pessimism) accounts for variations in clock arrival time due to jitter, skew uncertainty, and margin.

```tcl
set_clock_uncertainty -setup 0.050 [get_clocks clk]
set_clock_uncertainty -hold  0.030 [get_clocks clk]
```

### On-Chip Variation (OCV)

OCV models the fact that different parts of the chip experience different process, voltage, and temperature conditions simultaneously.

**OCV Derating:** Apply different delay multipliers to launch and capture paths.

```tcl
# Flat OCV derates
set_timing_derate -early 0.95  ;# speeds up early paths (for hold)
set_timing_derate -late  1.05  ;# slows down late paths (for setup)
```

### AOCV (Advanced OCV)

AOCV applies depth-dependent and distance-dependent derates. Deeper paths (more stages) have smaller per-stage variation because variations average out. This is less pessimistic than flat OCV.

```tcl
read_aocv aocv_table.aocv
```

### POCV (Parametric OCV) / SOCV (Statistical OCV)

POCV/SOCV model variation as a statistical distribution (Gaussian) rather than a fixed derate. Each cell and net contributes a mean and sigma to the path delay. The total path variation is the root-sum-square (RSS) of individual sigmas.

This is significantly less pessimistic than flat OCV and is the industry-standard methodology at 7nm and below.

```tcl
# In PrimeTime
set_app_var si_pocv_analysis_mode true
read_pocvm pocv_models.pocvm
```

## CPPR (Clock Path Pessimism Removal)

CPPR removes artificial pessimism caused by applying different OCV derates to the common portion of the launch and capture clock paths.

**Problem:** The launch clock path has a late derate (slower) and the capture clock path has an early derate (faster). But the common portion of both paths sees the same actual delay — applying different derates to it is doubly pessimistic.

**Solution:** CPPR identifies the common clock path and removes the derate difference on that portion.

```
CPPR Credit = (Late Derate - Early Derate) * Common Clock Path Delay
```

CPPR is always enabled in production STA. Without CPPR, designs would show significant artificial violations.

## Path Groups and Timing Exceptions

### Path Groups

Path groups categorize timing paths for separate reporting and optimization priority.

```tcl
# Create path groups
group_path -name critical_paths -from [get_cells -hier *critical_reg*] -weight 2.0
group_path -name memory_intf -from [get_cells u_mem/*] -to [get_cells u_ctrl/*]
group_path -name io_paths -from [all_inputs] -to [all_outputs]
```

### False Paths

Paths that exist structurally but can never be sensitized functionally.

```tcl
# Clock domain crossing (CDC) false path
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]

# Static configuration register
set_false_path -from [get_cells config_reg*]
```

### Multicycle Paths

Paths where data is launched on one clock edge and captured multiple cycles later.

```tcl
# 2-cycle multicycle path
set_multicycle_path 2 -setup -from [get_pins slow_reg/CK] -to [get_pins result_reg/D]
set_multicycle_path 1 -hold  -from [get_pins slow_reg/CK] -to [get_pins result_reg/D]
```

The hold multicycle should always be setup_multicycle - 1, unless there is a specific reason otherwise.

### Min/Max Delays

```tcl
set_min_delay 0.5 -from [get_ports data_in] -to [get_cells capture_reg/D]
set_max_delay 2.0 -from [get_ports data_in] -to [get_cells capture_reg/D]
```

## Bottleneck Analysis

Bottleneck analysis identifies cells and nets that appear on the largest number of critical (negative-slack) paths. Fixing bottleneck cells yields the highest timing improvement per ECO action.

```tcl
# In PrimeTime
report_bottleneck -max_cells 20

# Identifies cells appearing on the most violation paths
# Focus ECO effort on these cells first
```

## Timing Reports: How to Read Them

A standard timing report shows:

```
Startpoint: reg_a (rising edge-triggered flip-flop clocked by clk)
Endpoint:   reg_b (rising edge-triggered flip-flop clocked by clk)
Path Group: clk
Path Type:  max (setup check)

  Point                                    Incr       Path
  -------------------------------------------------------
  clock clk (rise edge)                   0.000      0.000
  clock network delay (propagated)        0.300      0.300
  reg_a/CK (rising)                       0.000      0.300
  reg_a/Q (DFFRX1)                        0.120      0.420
  u1/Y (AND2X1)                           0.050      0.470
  u2/Y (BUFX4)                            0.035      0.505
  reg_b/D (DFFRX1)                        0.000      0.505
  data arrival time                                  0.505

  clock clk (rise edge)                   1.000      1.000
  clock network delay (propagated)        0.310      1.310
  clock uncertainty                      -0.050      1.260
  reg_b/CK (rising)                       0.000      1.260
  library setup time                     -0.030      1.230
  data required time                                 1.230
  -------------------------------------------------------
  slack (MET)                                        0.725
```

**Key things to check:**

- Path group and path type (setup or hold)
- Clock network delay (propagated = real CTS, ideal = pre-CTS)
- Largest delay contributors (cells with high Incr values)
- Clock uncertainty value
- Library setup/hold time
- Final slack value

## Common Issues and Fixes

**Issue: Unexpected timing violations on paths that should be false**
- Review SDC for missing false_path or multicycle_path exceptions.
- Use `report_exceptions` to verify which exceptions are applied.
- Check for unintended clock relationships — `report_clock_timing -type interclock`.

**Issue: Large CPPR credit suggesting excessive OCV pessimism**
- CPPR credit > 50% of clock period indicates overly aggressive OCV derates.
- Consider switching from flat OCV to AOCV or POCV for more realistic analysis.

**Issue: Hold violations appearing only post-CTS**
- This is normal — pre-CTS uses ideal clocks with zero skew. Real clock trees introduce skew.
- Fix with hold buffer insertion during post-CTS optimization.

**Issue: Timing report shows unexpected clock paths**
- Verify `create_generated_clock` definitions — incorrect source or division can create wrong clock relationships.
- Use `report_clocks` and `report_clock_timing` to visualize clock structure.

## Best Practices

1. **Use POCV/AOCV for signoff** at 7nm and below — flat OCV is too pessimistic.
2. **Always enable CPPR** — there is no valid reason to disable it for signoff.
3. **Define path groups** for all major interfaces to enable targeted optimization.
4. **Review the top 50-100 failing paths**, not just the worst path — pattern recognition across multiple paths reveals systemic issues.
5. **Cross-check SDC constraints** between synthesis, PnR, and signoff STA to avoid inconsistencies.
6. **Use bottleneck analysis** to prioritize ECO effort on high-impact cells.
7. **Set realistic clock uncertainty** — include PLL jitter, CTS uncertainty, and OCV margin.
8. **Verify timing with SI (signal integrity) enabled** — crosstalk can add 5-15% delay on critical paths at advanced nodes.
