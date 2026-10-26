# Timing Budgets: IO Budgets, Interface Timing, Margin Allocation, and Corner Variation

## Overview

Timing budgeting is the process of allocating the total available timing window among the various contributors along a signal path, ensuring that every stage has sufficient margin to meet its timing requirement. Effective budgeting is essential at chip boundaries (I/O interfaces), between hierarchical blocks, and across process/voltage/temperature corners. Poor budgeting leads to either over-design (wasted area and power) or under-design (timing failures in silicon). This guide covers I/O timing budgets, interface timing analysis, margin allocation strategies, and multi-corner variation management.

## I/O Timing Budget Fundamentals

### The Timing Equation

For a synchronous interface, the fundamental timing relationship is:

**Setup check:**
```
T_clk >= T_cq + T_comb + T_flight + T_setup + T_skew + T_jitter + T_margin
```

**Hold check:**
```
T_cq + T_comb + T_flight > T_hold + T_skew + T_jitter
```

Where:
- T_clk: clock period
- T_cq: clock-to-Q delay of the launching flip-flop
- T_comb: combinational logic delay
- T_flight: wire flight time (on-chip + package + board + package + on-chip)
- T_setup: setup time of the capturing flip-flop
- T_skew: clock skew between launch and capture clocks
- T_jitter: clock jitter contribution
- T_margin: design margin (guardband)

### Budget Partitioning

The total timing budget is divided among contributors:

```
Total budget (clock period) = Source budget + Flight time + Destination budget + Margin

Source budget: T_cq + internal source logic + output driver delay
Flight time:  package delay + board trace + package delay
Destination:  input receiver + internal destination logic + T_setup
Margin:       skew + jitter + OCV + guardband
```

## I/O Interface Timing Models

### System-Synchronous Interface

Source and destination share a common clock (distributed on the board):

```
                    Board Clock
                    /         \
            [Source Chip]   [Dest Chip]
              CLK  Q -->  D  CLK
```

**Budget:**
```
T_period > T_co(max) + T_board_flight(max) + T_su + T_clock_skew(max)
T_co(min) + T_board_flight(min) > T_hold + T_clock_skew(max)
```

Where T_co is clock-to-output delay and T_su is setup time.

**SDC constraints on source chip:**
```tcl
# Output delay = destination setup time + board flight time - board clock skew
set_output_delay -clock CLK_SYS -max 2.5 [get_ports data_out[*]]
set_output_delay -clock CLK_SYS -min 0.5 [get_ports data_out[*]]
```

### Source-Synchronous Interface

Clock is transmitted alongside data from the source:

```
            [Source Chip]     Board      [Dest Chip]
              CLK_TX  ----> CLK_trace --> CLK_RX
              DATA    ----> DATA_trace -> DATA
```

**Key principle**: clock and data travel through the same (or matched) path, so board flight time cancels out. The timing budget depends on the skew between clock and data at the receiver.

**Budget:**
```
T_unit_interval/2 > T_skew(board) + T_setup(receiver) + T_jitter + T_margin
```

**SDC constraints (source chip, center-aligned clock):**
```tcl
create_clock -name CLK_TX -period 5.0 [get_ports clk_tx_out]
set_output_delay -clock CLK_TX -max 0.5 [get_ports data_out[*]]
set_output_delay -clock CLK_TX -min -0.5 [get_ports data_out[*]]
```

The max/min output delay represents the allowable skew window.

### Interface Timing with Virtual Clocks

For chip-level I/O constraints where the clock is not physically present at the chip boundary:

```tcl
# Virtual clock representing the external interface clock
create_clock -name VCLK_INTF -period 10.0

# Input delay referenced to virtual clock
set_input_delay -clock VCLK_INTF -max 6.0 [get_ports data_in[*]]
set_input_delay -clock VCLK_INTF -min 1.0 [get_ports data_in[*]]

# Output delay referenced to virtual clock
set_output_delay -clock VCLK_INTF -max 4.0 [get_ports data_out[*]]
set_output_delay -clock VCLK_INTF -min -0.5 [get_ports data_out[*]]
```

## Block-Level Timing Budgets

### Hierarchical Budget Allocation

For a signal path crossing multiple hierarchical blocks:

```
[Block A] -> [Top-level interconnect] -> [Block B]
```

Total path budget: T_period - T_uncertainty

Allocation:
- Block A internal: 40% of budget (includes register-to-output)
- Top-level interconnect: 20% of budget (includes repeaters)
- Block B internal: 30% of budget (includes input-to-register)
- Margin: 10% reserved

### Block-Level Constraint Generation

Top-level budgets are converted to block-level SDC:

```tcl
# Block A output constraint (from Block A's perspective)
# Block A gets 40% of 10ns period = 4ns for internal logic
# Remaining 6ns is "output delay" (destination logic + interconnect)
set_output_delay -clock CLK -max 6.0 [get_ports block_a_out[*]]

# Block B input constraint
# Block B gets 3ns for internal logic (30%)
# The "input delay" is 7ns (source logic + interconnect)
set_input_delay -clock CLK -max 7.0 [get_ports block_b_in[*]]
```

### Budget Balancing

When initial budgets do not lead to clean timing:

1. **Identify bottleneck**: which block or path segment is over-budget?
2. **Redistribute**: take margin from blocks with surplus and give to the bottleneck
3. **Architectural change**: pipeline stage insertion, register retiming, or logic restructuring
4. **Iterate**: re-run timing with adjusted budgets until all blocks close

## Margin Allocation

### Types of Margin

**Clock uncertainty margin:**
- PLL jitter (typically 50-200 ps)
- Clock tree skew (pre-CTS: estimated; post-CTS: actual)
- OCV (on-chip variation): 5-15% of clock period depending on technology node

**Process margin:**
- Library derating: additional timing derating beyond characterized corners
- Aging margin: account for BTI, HCI, and electromigration degradation over lifetime
- Typical value: 3-5% of clock period

**Design margin (guardband):**
- Engineering margin for unknowns: unmodeled effects, extraction accuracy, model-to-silicon correlation
- Should be systematically reduced as design matures
- Initial: 10-15% of clock period; final: 3-5%

**Signal integrity margin:**
- Crosstalk-induced delay: modeled in SI-aware STA or added as margin
- Power supply noise (IR drop): modeled explicitly or added as margin
- Typical: 50-200 ps depending on technology and analysis sophistication

### Margin Budget Table

| Contributor | Pre-CTS | Post-CTS | Post-Route |
|---|---|---|---|
| Clock jitter | 100 ps | 100 ps | 100 ps |
| Clock skew | 200 ps (est.) | 0 (actual) | 0 (actual) |
| OCV | 150 ps | 150 ps | 100 ps (AOCV) |
| SI margin | 100 ps | 100 ps | 0 (SI-aware STA) |
| IR drop | 50 ps | 50 ps | 50 ps |
| Design guardband | 200 ps | 100 ps | 50 ps |
| **Total** | **800 ps** | **500 ps** | **300 ps** |

Note how margin decreases as more accurate analysis replaces estimates.

### Margin Management Strategy

1. **Early design**: use generous margins to avoid false optimism
2. **Mid design**: refine margins as physical design data becomes available
3. **Sign-off**: use minimum justifiable margins; explicit analysis replaces margin for each contributor
4. **Document**: maintain a margin budget spreadsheet tracking every contributor and its justification

## Corner-to-Corner Variation

### PVT Corners

Timing analysis is performed across Process, Voltage, and Temperature corners:

| Corner | Process | Voltage | Temperature | Purpose |
|---|---|---|---|---|
| SS_0p72V_125C | Slow-Slow | 0.72V | 125C | Setup (worst) |
| FF_0p88V_m40C | Fast-Fast | 0.88V | -40C | Hold (worst) |
| TT_0p80V_25C | Typical | 0.80V | 25C | Nominal analysis |
| SS_0p72V_m40C | Slow-Slow | 0.72V | -40C | Setup (cold, advanced nodes) |
| FF_0p88V_125C | Fast-Fast | 0.88V | 125C | Hold (hot, advanced nodes) |

At advanced nodes (below 16nm), temperature inversion makes cold corners relevant for setup as well.

### Multi-Corner Multi-Mode (MCMM)

Modern STA runs all corners and modes simultaneously:

**Modes**: functional, test (scan), MBIST, JTAG, low-power, each with different clock configurations and constraints

**Corner x Mode matrix**: every combination of PVT corner and operating mode must be analyzed
- 5 corners x 3 modes = 15 analysis scenarios
- Each scenario has its own library, SDC, and parasitic model

### Cross-Corner Budget Variation

The same path may have different slack across corners:

```
Path: REG_A -> COMB -> REG_B

SS corner: 2.0ns combinational delay, 200ps setup, -100ps slack
FF corner: 0.8ns combinational delay, 100ps setup, -50ps hold violation
TT corner: 1.4ns combinational delay, 150ps setup, 400ps slack
```

**Budget implications:**
- The budget must close across ALL relevant corners
- Corner-specific optimization: size cells for the worst corner, then verify others
- Some paths may be critical in different corners (setup-critical in SS, hold-critical in FF)

### AOCV and POCV

Advanced OCV modeling reduces pessimism compared to flat OCV derating:

**AOCV (Advanced OCV)**: derating varies with path depth and distance
- Longer paths have less variation (statistical averaging)
- Shorter paths have more variation
- Reduces pessimism by 10-30% compared to flat OCV

**POCV (Parametric OCV)**: statistical modeling of delay variation
- Each cell and wire has a mean and sigma
- Path delay is computed as mean + N*sigma (statistical summation)
- Most accurate OCV modeling; further reduces pessimism
- Requires POCV-enabled libraries from the foundry

### Budgeting Across Corners

For I/O interfaces, the worst-case budget must account for cross-corner scenarios:

- **Source chip at slow corner, destination chip at fast corner**: worst for setup
- **Source chip at fast corner, destination chip at slow corner**: worst for hold
- Board and package delays have their own temperature and process variation

```
Setup budget worst case:
  T_co(slow) + T_board(max) + T_su(fast) + T_skew(max) < T_period

Hold budget worst case:
  T_co(fast) + T_board(min) > T_hold(slow) + T_skew(max)
```

## Practical Budgeting Workflow

1. **System-level budgeting**: partition total timing between chips, board, and connectors
2. **Chip-level budgeting**: partition chip timing between I/O, internal logic, and clock distribution
3. **Block-level budgeting**: partition internal timing among hierarchical blocks
4. **Constraint generation**: convert budgets into SDC constraints for each block
5. **Implementation**: run synthesis and P&R with block-level constraints
6. **Timing analysis**: verify timing at each level; compare actual results against budgets
7. **Budget adjustment**: redistribute margin based on actual results; iterate until closure

Timing budgeting is an iterative engineering discipline. Start with reasonable estimates, refine as data becomes available, and maintain explicit documentation of every assumption. A well-managed timing budget accelerates closure and reduces risk of silicon timing failures.
