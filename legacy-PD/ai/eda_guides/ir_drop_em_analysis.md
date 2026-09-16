# IR Drop and Electromigration Analysis

## Overview

IR drop and electromigration (EM) analysis verify the integrity of the power delivery network (PDN). IR drop causes voltage reduction at standard cell power pins, degrading timing and potentially causing functional failures. Electromigration causes physical degradation of metal wires carrying excessive current density, leading to reliability failures over the chip's lifetime. Both analyses are mandatory for tapeout signoff.

## IR Drop Fundamentals

### What Is IR Drop

IR drop is the voltage difference between the power source (pad/bump) and the power pin of a standard cell, caused by current flowing through the resistive power grid.

```
V_drop = I * R
V_cell = VDD_source - V_drop
```

A 5% IR drop on a 0.72V supply means cells see 0.684V instead of 0.72V, slowing them by 5-15% depending on the technology node.

### Static IR Drop

Static IR drop uses the average current drawn by each cell to compute a DC steady-state voltage map across the power grid.

**Methodology:**

1. Compute average current per cell from power analysis (PTPX or vectorless estimation).
2. Build a resistive network model of the power grid (from DEF/LEF + parasitic extraction).
3. Solve the linear system (Ohm's law + Kirchhoff's current law) for voltage at every node.
4. Report the voltage at each standard cell power pin.

**Acceptance criteria:** Maximum static IR drop typically < 3-5% of VDD.

### Dynamic IR Drop

Dynamic IR drop captures transient voltage fluctuations caused by simultaneous switching of many cells on the same clock edge. Dynamic IR drop is typically 2-5x worse than static IR drop because large current spikes occur during clock transitions.

**Methodology:**

1. Obtain time-resolved switching activity from VCD or power simulation.
2. Model the power grid as an RLC network (inductance matters for transient analysis).
3. Model decoupling capacitance (on-die decaps, cell intrinsic caps).
4. Run transient simulation to compute voltage at every node over time.
5. Report worst-case voltage droop at each cell location.

**Acceptance criteria:** Maximum dynamic IR drop typically < 8-10% of VDD.

### IR Drop Impact on Timing

When cells receive lower voltage, their delay increases:

```
Delay increase ~ (VDD / (VDD - V_drop - Vt))^alpha
```

Where alpha is typically 1.5-2.0 for advanced nodes. This means a 10% voltage drop can cause 15-25% delay increase, potentially causing timing failures.

**STA integration:** IR drop-aware timing analysis applies per-cell voltage derating based on the IR drop map.

```tcl
# In PrimeTime: apply IR drop derating
read_voltage_drop_profile -file ir_drop_map.vdp
set_app_var timing_pocv_enable_voltage_derate true
update_timing -full
report_timing -max_paths 50
```

## Electromigration (EM) Fundamentals

### What Is Electromigration

Electromigration is the physical transport of metal atoms by momentum transfer from conducting electrons. Over time, EM causes voids (open circuits) at the cathode end and hillocks (short circuits) at the anode end of a conductor.

### EM Current Density Limits

Foundries specify maximum current density limits for each metal layer and via type. These limits are specified as:

- **Average current density (Javg):** Limit for DC or average current.
- **Peak current density (Jpeak):** Limit for instantaneous current spikes.
- **RMS current density (Jrms):** Limit for power/ground and signal wires based on Joule heating.

```
J_limit depends on:
- Metal layer and width
- Wire temperature
- Required chip lifetime (typically 10 years at 105C)
- Duty cycle for signal wires
```

### EM Rule Types

| Type | Applied To | Concern |
|------|-----------|---------|
| Average EM | Power/ground wires | Atom migration from sustained DC current |
| Peak EM | Signal wires | Short-duration high-current events |
| RMS EM | All wires | Joule heating from current |
| Via EM | Via connections | Current crowding at via interfaces |

## Analysis Tools

### ANSYS RedHawk (Synopsys)

RedHawk is the industry-standard power integrity analysis tool for IR drop and EM analysis. (Now part of Synopsys after acquisition.)

#### RedHawk Flow

```tcl
# Technology setup
setup_tech -tech_file redhawk_tech.lib
setup_design -def top_routed.def

# Power grid extraction
import_design -lef {tech.lef stdcell.lef macro.lef}
import_def top_routed.def

# Power model
setup_power -power_model {power_map.inst}
# Or from PTPX
import_power_data -ptpx_power ptpx_output.power

# Static IR drop analysis
analyze_power_rail -type static

# Dynamic IR drop analysis
analyze_power_rail -type dynamic -waveform vcd_power.vcd

# EM analysis
analyze_em -type average
analyze_em -type peak

# Reports
report_power_rail -type static -output static_ir.rpt
report_power_rail -type dynamic -output dynamic_ir.rpt
report_em -output em_violations.rpt
```

### Cadence Voltus

Voltus is Cadence's power integrity tool, integrated with the Innovus PnR flow.

#### Voltus Flow

```tcl
# In Innovus or standalone Voltus
set_power_analysis_mode -method static

# Read power data
read_activity_file -format SAIF -scope top simulation.saif

# Run static IR drop
analyze_power_grid -nets {VDD VSS}
report_power_grid -type ir_drop -output ir_drop.rpt

# Dynamic IR drop
set_power_analysis_mode -method dynamic
set_dynamic_power_analysis -time_window {0 10ns}
analyze_power_grid -nets {VDD VSS}

# EM analysis
analyze_power_grid -type em
report_power_grid -type em -output em.rpt
```

### In-Design Power Grid Analysis (Innovus/FC)

PnR tools provide built-in power grid analysis for quick iteration:

```tcl
# In Innovus
set_power_analysis_mode -method static
analyze_power_rail -nets {VDD VSS}

# In FC
analyze_power_plan -nets {VDD VSS}
report_power_plan -type ir_drop
```

## Power Grid Design for Low IR Drop

### Bump/C4 Planning

The package-to-die interface (bumps/C4 balls) is the first bottleneck in power delivery.

**Guidelines:**

- Distribute power bumps uniformly across the die
- Ensure adequate VDD/VSS bump ratio (typically 40-50% of total bumps are power/ground)
- Place power bumps near high-current blocks (processors, memory controllers)
- Maintain L/R ratio for supply-return current paths

### Power Grid Topology

**Ring + Stripe architecture:**

```
Package bumps
    |
Top metal power ring (M10/M11)
    |
Vertical power stripes (M10) — wide, low R
    |
Horizontal power stripes (M9) — wide, low R
    |
... intermediate metal stripes ...
    |
M1 standard cell power rails
```

### Design Guidelines

| Parameter | Guideline |
|-----------|-----------|
| Power ring width | 2-5 um per ring on top metals |
| Stripe width | 1-3 um |
| Stripe pitch | 20-50 um (depends on current density) |
| M1 rail width | Standard cell height dependent |
| Via arrays | Maximize via count at stripe-rail intersections |
| Decap cells | 5-10% of core area as decap filler |

### Decoupling Capacitance

On-die decoupling capacitors (decaps) provide local charge storage to mitigate dynamic IR drop during current spikes.

```tcl
# Insert decap filler cells
addFiller -cell {DCAP64 DCAP32 DCAP16 DCAP8 DCAP4} -prefix DCAP

# Or mixed with standard fillers
addFiller -cell {DCAP64 DCAP32 FILL16 FILL8 FILL4 FILL2 FILL1} -prefix FILLER
```

**Decap placement strategy:**

- Fill empty spaces near high-switching blocks with decap cells
- Place larger decaps near clock tree root buffers
- Target 5-10% of core area as decap
- Verify that decap cells do not cause leakage concerns (decap cells have gate leakage)

## EM Fixing Strategies

### Power Grid EM Fixes

1. **Widen power stripes:** Increase stripe width to reduce current density.
2. **Add more stripes:** Reduce per-stripe current by distributing across more stripes.
3. **Add via arrays:** Increase via count at stripe intersections to reduce per-via current density.
4. **Add more bumps:** Reduce current per bump and per top-level stripe.
5. **Redistribute bumps:** Move power bumps closer to high-current regions.

### Signal Wire EM Fixes

1. **Upsize drivers:** Reduce peak current by increasing the transition time (lower dI/dt).
2. **Widen critical signal wires:** Apply NDR on high-toggle-rate nets.
3. **Multi-cut vias:** Use double or triple-cut vias to reduce per-cut current density.
4. **Layer promotion:** Route high-current nets on thicker upper metals.

## Common Issues and Fixes

**Issue: Static IR drop exceeds 5% in certain regions**
- Add more power stripes in the high-IR-drop region.
- Add power bumps (package redesign) near the hotspot.
- Reduce cell density in the region (less current demand).
- Verify that all vias between power grid layers are present (missing vias cause high R).

**Issue: Dynamic IR drop spikes during clock edges**
- Add decoupling capacitors near the hotspot.
- Spread high-switching cells across a larger area.
- Consider clock skewing to stagger switching events.
- Add more power stripes and bumps.

**Issue: EM violations on power grid stripes**
- Widen the violating stripes.
- Add parallel stripes to share the current load.
- Increase via array size at connections.

**Issue: EM violations on signal nets**
- Check for high-toggle-rate nets (clocks, data buses) with narrow routing.
- Apply NDR to increase wire width on violating nets.
- Use multi-cut vias to reduce per-via current density.

**Issue: IR drop-aware timing analysis reveals new timing violations**
- These are real — cells in high-IR-drop regions are slower than nominal STA predicts.
- Fix the power grid to reduce IR drop, or add timing margin in STA.
- Move timing-critical cells to low-IR-drop regions if possible.

## Best Practices

1. **Design the power grid early** — before placement — based on estimated power budget.
2. **Run static IR drop after placement** to catch power grid issues before investing in CTS and routing.
3. **Use dynamic IR drop for signoff** — static analysis underestimates transient droops.
4. **Include decap cells in the filler cell list** — they are free area-wise and essential for dynamic IR drop.
5. **Budget 3-5% IR drop maximum for static**, 8-10% for dynamic.
6. **Verify EM at the signoff temperature** — EM limits degrade at higher temperatures.
7. **Include package model** in the analysis for accurate supply impedance.
8. **Correlate IR drop with timing** — run IR drop-aware STA for the most accurate timing signoff.
9. **Plan bump placement early** in the chip architecture phase — it constrains the entire power grid.
10. **Iterate between PG design and IR drop analysis** — power grid design is not a one-shot process.
