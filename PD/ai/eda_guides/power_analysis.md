# Power Analysis

## Overview

Power analysis quantifies the energy consumption of a digital design across all operating conditions. With modern SoCs operating under stringent power budgets (battery life for mobile, thermal envelope for data center), power analysis and optimization are as critical as timing closure. Power analysis encompasses switching power, internal power, leakage power, and is performed using methodologies ranging from vectorless estimation to detailed vector-based simulation.

## Power Components

### Dynamic Power

Dynamic power is consumed when transistors switch states. It has two components:

#### Switching Power (External)

Power consumed charging and discharging the output load capacitance of a gate.

```
P_switching = alpha * C_load * V^2 * f
```

Where:
- alpha = switching activity (probability of a 0->1 transition per clock cycle)
- C_load = total output capacitance (gate + wire)
- V = supply voltage
- f = clock frequency

Switching power is typically 50-60% of total dynamic power.

#### Internal Power (Short-Circuit)

Power consumed inside a cell during switching, primarily from the short-circuit current that flows when both PMOS and NMOS stacks are partially on during a transition.

Internal power is characterized in the technology library as a function of input transition time and output load capacitance. It is typically 20-30% of total dynamic power.

### Static Power (Leakage)

Power consumed even when the circuit is not switching. Sources include:

- **Sub-threshold leakage:** Current flow through the channel when the transistor is "off." Exponentially dependent on threshold voltage (Vt) and temperature.
- **Gate leakage:** Tunneling current through thin gate oxide. Significant at 45nm and below.
- **Junction leakage:** Reverse-bias leakage through drain/source junctions.

```
P_leakage ~ I_leak * V
```

Leakage power is highly sensitive to temperature and Vt:
- Doubling temperature roughly doubles sub-threshold leakage.
- Reducing Vt by 100mV increases leakage by approximately 10x.

At advanced nodes (7nm and below), leakage can constitute 30-50% of total power.

## Power Analysis Methodology

### Vectorless Power Analysis

Estimates power without requiring simulation vectors. Uses statistical switching activity annotation.

**How it works:**

1. Tool propagates default or user-specified toggle rates from primary inputs through the logic cone.
2. Each net gets an estimated switching activity based on logic function and input activities.
3. Power is calculated using the estimated activities and library power models.

```tcl
# Set default switching activity
set_switching_activity -toggle_rate 0.1 -static_probability 0.5 [all_inputs]

# Set clock activity
set_switching_activity -toggle_rate 1.0 -static_probability 0.5 [get_ports clk]

# Run vectorless analysis
report_power
```

**Advantages:** Fast, no simulation required, available early in the flow.
**Disadvantages:** Less accurate (10-30% error), cannot capture workload-dependent behavior.

### Vector-Based Power Analysis

Uses actual switching activity from simulation to compute power with high accuracy.

**Flow:**

1. Run RTL or gate-level simulation with representative workload vectors.
2. Dump switching activity in SAIF (Switching Activity Interchange Format) or VCD (Value Change Dump) format.
3. Read activity into the power analysis tool.
4. Compute power using actual per-net switching rates.

```tcl
# Read switching activity from simulation
read_saif -input top.saif -instance top/u_core

# Or read VCD
read_vcd -input top.vcd -instance top/u_core

# Run power analysis
update_power
report_power -hierarchy
```

**Advantages:** High accuracy (5-10% error), captures real workload behavior.
**Disadvantages:** Requires simulation infrastructure, runtime-intensive, results are workload-dependent.

### SAIF vs. VCD

| Format | Content | Size | Accuracy |
|--------|---------|------|----------|
| SAIF | Aggregated toggle counts per net | Small (MBs) | Good (average activity) |
| VCD | Time-stamped transitions for every net | Large (GBs) | Best (temporal activity) |
| FSDB | Fast Signal Database (Synopsys) | Medium | Best (compressed VCD) |

**Recommendation:** Use SAIF for average power estimation. Use VCD/FSDB for peak power and dynamic IR drop analysis.

## PrimeTime PX (PTPX) Methodology

PTPX is Synopsys's signoff power analysis tool, built on the PrimeTime timing engine.

### PTPX Flow

```tcl
# Read design
read_verilog top_routed.v
link_design top
read_sdc top.sdc
read_parasitics -format SPEF top.spef

# Set operating conditions
set_operating_conditions ss_0p72v_125c

# Vectorless analysis
set_switching_activity -toggle_rate 0.1 -static_probability 0.5 [all_inputs]
update_power
report_power > rpt/power_vectorless.rpt
report_power -hierarchy > rpt/power_hier.rpt

# Vector-based analysis
read_saif -input simulation.saif -instance top
update_power
report_power > rpt/power_saif.rpt
```

### PTPX Reports

```tcl
# Total power summary
report_power

# Hierarchical power breakdown
report_power -hierarchy -levels 3

# Power by module
report_power -hierarchy -leaf

# Power by power domain
report_power -power_domain

# Clock network power
report_power -clock_network

# Switching activity coverage
report_switching_activity -coverage
```

### PTPX Output Example

```
Internal  Switching  Leakage    Total      Module
Power     Power      Power      Power      Name
(mW)      (mW)       (mW)       (mW)
-------   ---------  --------   -------    ------
120.5     185.3      45.2       351.0      top (total)
 42.3      65.1      12.8       120.2      u_core
 28.7      48.2       8.3        85.2      u_cache
 15.4      22.0       6.1        43.5      u_bus
  8.2      12.5       4.0        24.7      u_pll
 25.9      37.5      14.0        77.4      others
```

## Power Intent (UPF)

Unified Power Format (UPF, IEEE 1801) specifies the power architecture of a design:

### Power Domains

```tcl
# Create power domains
create_power_domain PD_TOP -elements {top}
create_power_domain PD_CORE -elements {u_core} \
    -supply {primary VDD_CORE} -supply {primary VSS}
create_power_domain PD_IO -elements {u_io} \
    -supply {primary VDDIO} -supply {primary VSSIO}

# Create supply nets and ports
create_supply_net VDD -domain PD_TOP
create_supply_net VSS -domain PD_TOP
create_supply_net VDD_CORE -domain PD_CORE

# Supply connections
create_supply_set SS_CORE -function {power VDD_CORE} -function {ground VSS}
associate_supply_set SS_CORE -handle PD_CORE.primary
```

### Power States

```tcl
# Define supply states
add_port_state VDD_CORE -state {ON 0.72} -state {OFF off}
add_port_state VSS -state {ON 0.0}

# Power state table
create_pst pst_top -supplies {VDD_CORE VSS}
add_pst_state ON_STATE -pst pst_top -state {ON ON}
add_pst_state OFF_STATE -pst pst_top -state {OFF ON}
```

### Isolation and Retention

```tcl
# Isolation cells for signals crossing power domain boundaries
set_isolation iso_core -domain PD_CORE \
    -applies_to outputs \
    -clamp_value 0 \
    -isolation_signal iso_en

# Retention registers
set_retention ret_core -domain PD_CORE \
    -retention_power_net VDD \
    -retention_ground_net VSS \
    -save_signal {save_en high} \
    -restore_signal {restore_en high}
```

## Power Optimization Techniques

### Clock Gating

The single most effective power reduction technique. Gates the clock to register banks when they are not being updated.

**Impact:** 30-60% reduction in clock network dynamic power.

```tcl
# Check clock gating coverage
report_clock_gating -coverage

# Target: > 85% of sequential bits gated
```

### Multi-Vt Optimization

Use high-Vt (HVT) cells on non-critical paths to reduce leakage, and low-Vt (LVT) cells only where timing demands it.

**Impact:** 2-5x leakage reduction compared to all-LVT design.

```tcl
# Report Vt distribution
report_threshold_voltage_group

# Target: > 60% HVT, < 20% LVT
```

### Power Gating

Shut off entire power domains when not in use by turning off the power supply via header/footer switches.

**Impact:** Near-zero leakage in powered-off domains.

### Dynamic Voltage and Frequency Scaling (DVFS)

Adjust supply voltage and clock frequency based on workload demands. Lower V and f when full performance is not needed.

**Impact:** Quadratic power reduction with voltage (P ~ V^2).

### Operand Isolation

Gate inputs to datapath blocks when their outputs are not needed, preventing unnecessary switching.

```tcl
set_operand_isolation -domain PD_CORE -elements {u_core/u_alu} \
    -isolation_signal alu_en
```

## Common Issues and Fixes

**Issue: Vectorless power estimate is 2-3x higher than vector-based**
- Vectorless assumes uniform toggle rates, which overestimates activity in idle logic.
- Annotate more realistic default toggle rates (0.05-0.1 for data, 0.02-0.05 for control).
- Use SAIF from simulation for accurate results whenever possible.

**Issue: Leakage power exceeds budget**
- Check Vt distribution — too many LVT/SVT cells.
- Run multi-Vt optimization with leakage priority.
- Consider power gating for idle domains.
- Verify operating temperature — leakage doubles roughly every 10-15 degrees C.

**Issue: Clock power dominates total power**
- Check clock gating coverage — ungated clocks waste power.
- Review CTS buffer count — over-buffered trees consume more power.
- Consider clock mesh alternatives only if skew requirements demand it.

**Issue: SAIF activity coverage is low (<60%)**
- Simulation workload does not exercise enough of the design.
- Add more test scenarios to the simulation.
- Use vectorless annotation for uncovered nets as a fallback.

**Issue: Power analysis results differ between tools**
- Verify library power models match (CCS vs. NLDM).
- Check parasitic extraction consistency.
- Ensure switching activity annotation is identical.
- Compare per-cell power on a few cells to isolate systematic differences.

## Best Practices

1. **Run power analysis at every major flow stage** — synthesis, post-place, post-route — to track power trend.
2. **Use vector-based analysis for signoff** — vectorless is for estimation only.
3. **Annotate SAIF from representative workloads** — non-representative vectors give misleading results.
4. **Target clock gating coverage > 85%** for mobile/battery-powered designs.
5. **Optimize Vt distribution** — most cells should be HVT for leakage reduction.
6. **Include clock network in power reports** — it is typically 30-50% of dynamic power.
7. **Report power by hierarchy** to identify power-hungry modules for targeted optimization.
8. **Use PTPX for signoff** (Synopsys flow) or Voltus for signoff (Cadence flow).
9. **Simulate multiple workload scenarios** — idle, typical, and peak — to understand the power envelope.
10. **Budget power early** in the architecture phase and track against budget throughout implementation.
