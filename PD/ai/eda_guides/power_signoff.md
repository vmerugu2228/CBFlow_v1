# Power Signoff: Budgeting, Analysis, and Verification

## Overview

Power signoff verifies that a design meets its power budget across all operating conditions and that the power delivery network can reliably supply the required current. Power has become a first-order design constraint, often determining the maximum achievable performance and directly impacting battery life (mobile), cooling cost (server), and reliability. PD engineers must understand leakage budgeting, dynamic power analysis, peak current management, voltage drop limits, thermal constraints, and power-aware clock tree synthesis.

## Leakage Power Budget

Leakage power is the static power dissipated when the chip is powered on but not switching. At advanced nodes, leakage can account for 20-40% of total power.

### Leakage Components

- **Sub-threshold leakage**: Current flowing from source to drain when VGS < Vth. Exponentially dependent on Vth and temperature. Dominant leakage component.
- **Gate leakage**: Tunneling current through the gate oxide. Reduced by HKMG technology but still significant.
- **Junction leakage**: Reverse-bias leakage at source/drain junctions.

### Leakage Budget Methodology

1. **Allocate top-down**: The total chip leakage budget is derived from the package thermal limit and the target operating temperature. For example, if the package supports 2W total and the dynamic power budget is 1.5W, the leakage budget is 0.5W.
2. **Distribute to blocks**: Allocate leakage budget proportionally by area and function. CPU cores typically get 40-50% of the total leakage budget.
3. **Multi-Vt optimization**: Use high-Vt (HVT) cells to reduce leakage on non-critical paths. PD tools optimize Vt assignment to minimize leakage while meeting timing.
4. **Temperature derating**: Leakage doubles approximately every 10-12C. The leakage budget must account for worst-case junction temperature.

### Leakage Analysis

```tcl
# PrimeTime power analysis:
read_verilog final_netlist.v
read_parasitics final.spef
set_operating_conditions ss_0p85v_125c
report_power -leakage

# Result shows per-instance and total leakage power
```

### Leakage Reduction Techniques

- **Multi-Vt swap**: Replace SVT/LVT cells with HVT/UHVT on non-critical paths (20-40% leakage reduction).
- **Power gating**: Shut down idle blocks completely (90%+ leakage reduction for gated blocks).
- **Body biasing**: Apply reverse body bias to increase Vth and reduce leakage (where process supports it).
- **Voltage scaling**: Reducing VDD reduces both dynamic and leakage power (leakage reduces approximately quadratically with voltage in sub-threshold regime).

## Dynamic Power Budget

Dynamic power is consumed during switching and is typically the dominant power component.

### Dynamic Power Equation

```
P_dynamic = alpha * C_load * VDD^2 * f_clock
```

Where alpha is switching activity, C_load is load capacitance, VDD is supply voltage, and f_clock is clock frequency.

### Dynamic Power Budgeting

1. **Top-down allocation**: Similar to leakage, the total dynamic power budget is derived from the thermal/battery constraint.
2. **Activity-based estimation**: Use RTL simulation vectors to estimate switching activity per block. Vectorless estimation (statistical) is used when vectors are unavailable.
3. **Clock power**: Clock distribution (tree + sequential elements) typically consumes 30-50% of total dynamic power. Budget this explicitly.
4. **Memory power**: SRAM read/write power is a significant contributor. Memory access patterns directly impact power.

### Dynamic Power Analysis Flow

```tcl
# Vector-based power analysis in PrimeTime PX:
read_verilog final_netlist.v
read_parasitics final.spef
read_saif switching_activity.saif  ;# From RTL simulation
set_operating_conditions tt_0p85v_25c
update_power
report_power -hierarchy -verbose
```

Vector-based analysis is more accurate than vectorless. Always use realistic simulation vectors that represent the target workload.

## Peak Current Analysis

Peak current is the maximum instantaneous current drawn from the supply. It determines the worst-case voltage drop and is critical for power grid sizing.

### Peak Current Scenarios

- **Clock edge**: When all flip-flops toggle simultaneously, the clock network draws maximum current. This is the most common peak current scenario.
- **Simultaneous switching output (SSO)**: Multiple I/O drivers switching simultaneously.
- **Power-on rush current**: Inrush current when a power domain is enabled.
- **Burst workload**: Specific functional patterns that cause maximum concurrent switching (e.g., all multipliers active).

### Peak Current Analysis

Tools like RedHawk and Voltus perform dynamic analysis with realistic or worst-case switching scenarios:

1. **VCD-based**: Use Value Change Dump from gate-level simulation for the most accurate current profile.
2. **Vectorless**: Statistical estimation of peak current based on cell types and toggle rates.
3. **Worst-case**: Assume all cells switch simultaneously (extremely pessimistic, used for sanity checks only).

### Peak Current Budget

The power grid must be designed to handle peak current with acceptable voltage drop. Typical design targets:

- Average current: sized for the typical workload.
- Peak current: 2-5x average current, lasting 1-2 clock cycles.
- Power grid designed for peak current with <10% VDD dynamic voltage drop.

## Voltage Drop Limits

### Static IR Drop

Static IR drop is the steady-state voltage drop across the power grid due to resistive losses.

- **Target**: Typically <3-5% of VDD at worst-case current.
- **Analysis**: Compute the voltage at every cell's VDD pin. Flag cells with voltage below the threshold.
- **Fixing**: Add power straps, widen existing straps, add via arrays, improve grid mesh density in hot spots.

### Dynamic Voltage Drop

Dynamic voltage drop includes both IR drop and Ldi/dt effects (inductance-induced voltage droop from rapid current changes).

- **Target**: Typically <8-10% of VDD during worst-case transients.
- **Transient duration**: The worst droop occurs within the first few nanoseconds after a current surge.
- **Decoupling capacitance**: On-chip decap cells provide local charge storage to supply current during transients before the package can respond.
- **Package inductance**: The package power delivery network (PDN) inductance determines how quickly the external supply can respond to current demands.

### Analysis Flow

```tcl
# RedHawk dynamic IR drop analysis:
# 1. Import design (DEF/LEF + parasitics)
# 2. Set up power grid model
# 3. Apply switching activity (VCD or vectorless)
# 4. Run transient simulation
# 5. Report voltage drop at every cell
# 6. Identify cells below threshold
```

## Thermal Limits

Power dissipation and thermal management are inseparable. Power signoff must verify that the chip operates within its thermal envelope.

### Thermal Budget Integration

```
Tj = Ta + P_total * Rth_ja

Where:
Tj = junction temperature (must be < Tj_max, typically 105-125C)
Ta = ambient temperature
P_total = leakage + dynamic power
Rth_ja = package thermal resistance
```

The relationship is circular: higher temperature increases leakage, which increases power, which further increases temperature. Convergence requires iterative electro-thermal analysis.

### Thermal-Power Feedback

1. Estimate power at nominal temperature.
2. Compute temperature from power using thermal model.
3. Re-compute leakage at the new temperature.
4. Iterate until power and temperature converge (typically 3-5 iterations).

## Power-Aware Clock Tree Synthesis (CTS)

The clock network is the largest single contributor to dynamic power (30-50% of total). Power-aware CTS optimizes the clock tree to minimize power while meeting skew and latency targets.

### Power-Aware CTS Techniques

1. **Clock gating**: Insert clock gates (ICG cells) to disable clock propagation to idle registers. Clock gating can reduce clock power by 30-60%.

```tcl
# Enable clock gating in synthesis:
set_clock_gating_style -type integrated -max_fanout 32
insert_clock_gating
```

2. **Useful skew**: Intentionally skew the clock arrival to borrow time from slack-rich paths, allowing the use of smaller (lower power) clock buffers on those paths.

3. **Multi-Vt clock cells**: Use HVT clock buffers where the clock tree has timing slack. This reduces leakage in the clock tree.

4. **Clock mesh vs. clock tree**: A clock mesh provides lower skew but higher power. A clock tree uses less power but has higher skew. The choice depends on the design's skew sensitivity.

5. **Minimum buffer sizing**: Use the smallest clock buffers that meet the transition time and fanout constraints. Oversized buffers waste dynamic power.

### CTS Power Optimization in Tools

```tcl
# Synopsys FC/ICC2:
set_app_options -name clock_opt.flow.enable_power -value true
set_app_options -name cts.common.max_fanout -value 32

# Cadence Innovus:
set_ccopt_property target_max_trans 0.15
set_ccopt_property attempt_to_minimize_power true
```

## Power Signoff Checklist

1. **Leakage check**: Total leakage at worst-case temperature within budget.
2. **Dynamic power check**: Total power (leakage + dynamic) within package thermal budget.
3. **Static IR drop**: All cells receive VDD within the allowed drop threshold.
4. **Dynamic IR drop**: Transient voltage droop within limits during worst-case switching.
5. **EM check**: All power grid wires and vias meet EM current density limits.
6. **Rush current**: Power-on sequence current within package and switch capability.
7. **Decap adequacy**: Sufficient on-chip decoupling capacitance for transient response.
8. **Thermal compliance**: Tj within spec at worst-case power and ambient temperature.
9. **Multi-Vt distribution**: Vt mix meets leakage target while maintaining timing closure.
10. **Clock power**: Clock network power within budget; clock gating effectiveness verified.

## Common Pitfalls

- Using average power for IR drop analysis instead of peak/worst-case power.
- Ignoring dynamic IR drop (static-only analysis misses transient droops).
- Not derating leakage for actual junction temperature.
- Undersizing the power grid for the worst-case operating point in a DVFS design.
- Not budgeting adequate clock gating, leading to excessive clock power.
- Treating power analysis as a signoff-only activity rather than tracking it throughout implementation.

Power signoff is a multi-faceted verification discipline that encompasses electrical, thermal, and reliability aspects. PD engineers must integrate power awareness from floorplanning through final signoff to deliver power-efficient, reliable silicon.
