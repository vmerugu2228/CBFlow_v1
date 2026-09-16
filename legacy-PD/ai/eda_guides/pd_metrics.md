# PD Metrics

## Overview

Physical design metrics are the quantitative measures that determine whether an implementation meets its design targets. Tracking the right metrics at the right stage prevents late-stage surprises, enables objective decision-making, and provides a common language for PD engineers, architects, and management. This guide covers the core metrics every PD engineer must understand, how they are measured, what constitutes healthy values, and how they interact with each other.

## Timing Metrics

### WNS (Worst Negative Slack)

WNS is the single worst slack value across all timing paths in a given mode/corner. A negative WNS means at least one path violates its timing constraint.

- **Measurement**: Reported by STA tools (PrimeTime, Tempus) per scenario (mode + corner + RC extraction)
- **Healthy values**: WNS >= 0ps at signoff; during implementation, WNS should converge monotonically toward zero
- **Pitfalls**: A small negative WNS (-10ps) on a single path is very different from a large negative WNS (-500ps). Always look at WNS alongside TNS
- **Typical targets**: Post-synthesis WNS > -100ps; post-CTS WNS > -50ps; signoff WNS >= 0ps

### TNS (Total Negative Slack)

TNS is the sum of all negative slack values across all violating endpoints. It measures the breadth of timing violations.

- **Measurement**: Sum of slack for all endpoints with negative slack in a given scenario
- **Healthy values**: TNS of -1ns with WNS of -10ps means ~100 paths are marginally failing (often fixable with minor optimization). TNS of -1ns with WNS of -500ps means a few paths are badly broken
- **Relationship to WNS**: WNS tells you how bad the worst case is; TNS tells you how widespread the problem is. Both must converge to zero for signoff

### FEP (Failing Endpoint Count)

FEP counts the number of unique endpoints (registers, output ports) with negative slack.

- **Measurement**: Count of endpoints where slack < 0 in STA
- **Healthy values**: Signoff FEP = 0. During implementation, FEP trending downward is a good sign
- **Usage**: FEP is particularly useful for tracking ECO progress. If an ECO fixes 50 FEPs but WNS barely improves, the remaining violations are concentrated on a few hard paths

### Setup vs Hold

All three metrics above apply separately to setup and hold timing. Setup is typically the harder constraint during implementation; hold is fixed with buffer insertion and is usually closed during post-route optimization or as a final ECO step.

## Physical Metrics

### Utilization

Cell utilization is the ratio of standard cell area to available placement area.

- **Formula**: Utilization = (Total standard cell area) / (Placement area - Macro area - Blockage area)
- **Healthy values**: 60-75% for most designs. Above 80% creates severe congestion and routability problems. Below 50% wastes silicon area
- **Variants**: "Reported utilization" from PnR tools may differ from "effective utilization" that accounts for cell padding, placement blockages, and keep-out zones
- **Impact**: High utilization degrades timing (longer wires), increases congestion, and makes ECOs harder

### Congestion

Congestion measures how much routing demand exceeds routing supply in a given region.

- **Measurement**: Typically reported as a percentage overflow per global routing cell (Gcell). Tools report both horizontal and vertical congestion
- **Healthy values**: Peak congestion < 1% overflow after global routing. Hotspots above 5% usually cause DRC issues
- **Metrics**: Global routing overflow count, peak congestion percentage, congestion histogram
- **Visualization**: Congestion maps (heatmaps) are essential for identifying problem areas

### Routing Overflow

Routing overflow counts the number of global routing cells where routing demand exceeds available tracks.

- **Measurement**: Sum of (demand - supply) across all Gcells where demand > supply
- **Healthy values**: Zero overflow at signoff. During placement, small overflow in non-critical areas may be acceptable
- **Horizontal vs Vertical**: Track both directions separately. An imbalance often indicates poor layer assignment or floorplan issues

### Cell Density

Cell density measures the local packing of standard cells, often reported per placement tile or bin.

- **Measurement**: Standard cell area / Bin area, reported as a spatial distribution
- **Healthy values**: Peak density < 90% with uniform distribution. Density hotspots correlate with congestion and IR drop issues
- **Distinction from utilization**: Utilization is a global metric; density is local. A design can have 65% global utilization but 95% local density in a hotspot

### DRC Count

Design Rule Check violations count measures physical manufacturability compliance.

- **Measurement**: Total number of DRC violations from the DRC checker (Calibre, ICV, Pegasus)
- **Categories**: Spacing violations, width violations, enclosure violations, antenna violations, density violations
- **Healthy values**: Zero at signoff. During implementation, DRC count should decrease monotonically. A sudden increase indicates a problem
- **Weighted DRC**: Some teams assign severity weights (critical/major/minor) to prioritize fixing effort

## Power Metrics

### Total Power

Total power consumption, typically broken into dynamic and static (leakage) components.

- **Dynamic power**: Proportional to switching activity, capacitance, voltage squared, and frequency. Measured from power analysis tools using switching activity from simulation (VCD/SAIF) or statistical estimation
- **Static power (leakage)**: Determined by technology node, threshold voltage, temperature, and cell count. Measured from library characterization data
- **Healthy values**: Must meet the power budget defined by the package thermal limits and battery life requirements
- **Corners**: Power is analyzed at different scenarios (typical for average power, worst-case for peak power)

### Clock Power

Power consumed by the clock network, typically 30-50% of total dynamic power in modern designs.

- **Measurement**: Reported by power analysis tools, broken down by clock domain
- **Optimization**: Clock gating effectiveness (percentage of gated registers) directly impacts clock power. Target > 90% clock gating coverage

### IR Drop

Voltage drop across the power delivery network under switching load.

- **Static IR drop**: Average drop from pad to cell, assuming uniform current draw
- **Dynamic IR drop**: Peak instantaneous drop considering switching activity patterns
- **Healthy values**: Static IR drop < 3-5% of VDD; dynamic IR drop < 8-10% of VDD
- **Impact**: Excessive IR drop causes timing degradation (cells run slower at lower voltage) and potential functional failure

## Area Metrics

### Die Area

Total chip area including core area, I/O ring, and seal ring.

- **Measurement**: Width x Height of the die boundary
- **Impact**: Directly affects manufacturing cost (more dies per wafer = lower cost)

### Core Area

Area available for standard cells, macros, and routing.

- **Measurement**: Core boundary dimensions, excluding I/O ring
- **Relationship**: Core area = Standard cell area + Macro area + Routing channels + Whitespace

### Macro Area Ratio

Percentage of core area occupied by hard macros (memories, analog IP, etc.).

- **Healthy values**: Designs with > 60% macro area ratio are "macro-dominated" and require careful floorplanning. Channel routing between macros becomes the bottleneck

## Derived and Composite Metrics

### Power-Performance-Area (PPA)

PPA is the fundamental tradeoff triangle. Improving one metric often degrades another:

- Faster clock (performance) increases power and may require more area for buffering
- Lower power (multi-Vt optimization) may sacrifice some timing margin
- Smaller area (higher utilization) increases congestion and degrades both timing and power

### Figure of Merit (FoM)

Many teams define a composite FoM to track overall design health:

```
FoM = w1 * (WNS_normalized) + w2 * (TNS_normalized) + w3 * (Power_normalized) + w4 * (Area_normalized)
```

Weights are project-specific and reflect design priorities.

### QoR Score

A single number summarizing design quality, typically combining timing, power, area, and DRC metrics. Useful for comparing runs and detecting regressions.

## Metric Collection Best Practices

### When to Collect

- After every major implementation step (synthesis, placement, CTS, routing, optimization)
- After every ECO iteration
- At every milestone gate review
- For every new tool version qualification run

### How to Store

- Use a structured database (SQL, JSON, CSV) rather than ad-hoc log parsing
- Include metadata: run name, timestamp, tool version, design version, constraint version
- Automate collection; manual entry introduces errors and gaps

### How to Visualize

- Trend plots showing metric evolution across runs (WNS over time, DRC count over time)
- Scatter plots showing metric correlations (utilization vs. WNS, congestion vs. DRC)
- Histograms showing slack distribution (helps distinguish WNS-dominated vs. TNS-dominated issues)
- Heatmaps for spatial metrics (congestion, IR drop, cell density)

### Alert Thresholds

Define thresholds that trigger alerts:

- WNS regression > 20ps from previous run
- TNS increase > 10% from baseline
- DRC count increase > 50 from previous run
- Power increase > 5% from baseline

These thresholds catch regressions early, before they compound into signoff-blocking issues.

## Metric Interactions

Understanding how metrics interact is critical for effective optimization:

| Action | WNS | TNS | Power | Area | Congestion |
|--------|-----|-----|-------|------|------------|
| Upsize cells | Improves | Improves | Increases | Increases | May worsen |
| Add buffers | Improves | Improves | Increases | Increases | May worsen |
| Increase utilization | May degrade | May degrade | Neutral | Decreases | Worsens |
| Multi-Vt swap (HVT) | May degrade | May degrade | Decreases | Neutral | Neutral |
| Clock gating | Neutral | Neutral | Decreases | Slight increase | Neutral |
| Layer promotion | Improves | Improves | Neutral | Neutral | May improve |

The best PD engineers develop an intuition for these tradeoffs and make deliberate choices rather than relying solely on tool automation.
