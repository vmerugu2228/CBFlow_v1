# QoR Tracking

## Overview

Quality of Results (QoR) tracking is the systematic practice of collecting, storing, comparing, and analyzing physical design metrics across implementation runs. Without disciplined QoR tracking, teams operate blind: they cannot detect regressions, quantify improvements, or make data-driven decisions. This guide covers the infrastructure, methodology, and analytical techniques for effective QoR tracking in physical design projects.

## Why QoR Tracking Matters

A typical PD block goes through hundreds of implementation runs during a project: floorplan exploration, optimization sweeps, ECO iterations, tool version changes, library updates, and constraint refinements. Each run produces dozens of metrics. Without tracking:

- Regressions go undetected until signoff, when they are expensive to fix
- Engineers repeat experiments because previous results were lost or forgotten
- Management lacks visibility into design health and schedule risk
- Root cause analysis is impossible without historical data to compare against

## Metric Collection

### What to Collect

At minimum, collect these metrics from every implementation run:

**Timing**: WNS, TNS, FEP (failing endpoint count) per scenario (mode/corner combination). Include both setup and hold.

**Physical**: Cell utilization, routing congestion (peak and average), routing overflow, total wire length, via count, DRC violation count (by category).

**Power**: Total power, dynamic power, leakage power, clock network power. Collect per power domain if applicable.

**Area**: Die area, core area, standard cell area, macro area, cell count by type (sequential, combinational, buffer, inverter).

**Runtime**: CPU time, elapsed wall time, peak memory usage. These are important for flow efficiency tracking.

### Where to Collect From

Each tool in the flow produces reports that contain QoR data:

- **Synthesis** (Design Compiler, Genus): Area, timing, power from synthesis reports
- **PnR** (Innovus, ICC2/FC): Placement utilization, congestion, post-route timing, DRC summary
- **STA** (PrimeTime, Tempus): Signoff timing (WNS, TNS, FEP per scenario)
- **Power analysis** (PTPX, Voltus): Detailed power breakdown
- **Physical verification** (Calibre, ICV, Pegasus): DRC/LVS violation counts
- **IR drop** (RedHawk, Voltus): Static and dynamic IR drop numbers

### Collection Automation

Never rely on manual metric extraction. Automate collection using scripts that:

1. Parse tool log files and reports using regex or structured output formats
2. Extract key metrics into a standardized data structure (JSON, CSV, or database records)
3. Tag each record with metadata: run ID, timestamp, design version (git hash), tool version, constraint version, engineer name
4. Store results in a persistent database

Example collection flow:

```
Tool Run Completes
    |
    v
Post-processing Script (parse reports)
    |
    v
Metric Extraction (regex / structured parsing)
    |
    v
Database Insert (with metadata tags)
    |
    v
Dashboard Update (automated refresh)
```

### Database Schema Design

A practical schema includes:

- **runs** table: run_id, timestamp, design, block, stage, tool_version, engineer, git_hash, constraint_version, status
- **timing_metrics** table: run_id, scenario, wns, tns, fep, clock_period
- **physical_metrics** table: run_id, utilization, congestion_h, congestion_v, overflow, wirelength, drc_count
- **power_metrics** table: run_id, scenario, total_power, dynamic_power, leakage_power, clock_power
- **area_metrics** table: run_id, die_area, core_area, cell_area, cell_count

Use a relational database (SQLite for small teams, PostgreSQL for larger organizations) or a structured file format (JSON lines, Parquet) for simpler setups.

## Baseline Comparison

### Establishing Baselines

A baseline is a reference run that represents the "known good" state of the design. Baselines are set at key milestones:

- **Post-synthesis baseline**: After initial synthesis completes with acceptable QoR
- **Post-placement baseline**: After floorplan and placement are frozen
- **Post-CTS baseline**: After clock tree synthesis meets skew and timing targets
- **Post-route baseline**: After routing completes with acceptable DRC and timing
- **Signoff baseline**: The golden signoff run, used as the reference for all subsequent ECOs

### Baseline Comparison Methodology

For every new run, compare metrics against the active baseline:

```
Delta_WNS = WNS_current - WNS_baseline
Delta_TNS = TNS_current - TNS_baseline
Delta_Power = (Power_current - Power_baseline) / Power_baseline * 100%
Delta_Area = (Area_current - Area_baseline) / Area_baseline * 100%
```

Present deltas prominently in dashboards. Color-code: green for improvement, red for regression, yellow for within noise margin.

### Noise Margin

Small metric fluctuations between runs are normal due to tool non-determinism (different random seeds, parallel execution order). Define noise margins:

- WNS: +/- 5ps is noise for most designs
- TNS: +/- 5% is noise
- Power: +/- 2% is noise
- Area: +/- 0.5% is noise (area should be very stable)

Only flag regressions that exceed the noise margin.

## Trending Graphs

### Essential Trend Plots

1. **WNS over time**: X-axis = run date/number, Y-axis = WNS. Plot per scenario, with a horizontal line at zero (target). Shows whether timing is converging
2. **TNS over time**: Same axes. TNS should trend toward zero monotonically
3. **FEP over time**: Shows how many endpoints remain to be fixed
4. **DRC count over time**: Should decrease monotonically after routing. Any increase is a red flag
5. **Power over time**: Watch for unexpected increases from optimization (cell upsizing, buffer insertion)
6. **Utilization over time**: Should be stable; increases indicate netlist growth (ECOs adding cells)

### Multi-Run Comparison

When comparing optimization strategies, plot multiple runs on the same chart:

- Run A (default optimization) vs. Run B (aggressive optimization) vs. Run C (power-focused optimization)
- Use consistent colors and labels
- Include confidence intervals if running with multiple seeds

### Stage-by-Stage Waterfall

A waterfall chart showing metric progression through implementation stages:

```
Synthesis -> Placement -> CTS -> Route -> Opt -> Signoff
WNS: -200ps -> -80ps -> -30ps -> -15ps -> -5ps -> +2ps
```

This reveals which stage contributes most to metric improvement and where bottlenecks exist.

## Regression Detection

### Automated Regression Detection

Implement automated checks that run after every implementation run:

1. Compare current run against baseline
2. If any metric regresses beyond noise margin, generate an alert
3. Alert includes: metric name, current value, baseline value, delta, and suspected cause

### Regression Triggers

Common causes of QoR regressions:

- **RTL changes**: New logic, modified interfaces, or ECOs that increase path depth or cell count
- **Constraint changes**: Modified clock definitions, false paths, multicycle paths, or I/O constraints
- **Library updates**: New .lib files with different cell characterization
- **Tool version changes**: New PnR or STA tool version with different optimization algorithms
- **Flow changes**: Modified script options, optimization passes, or run order

### Bisection Strategy

When a regression is detected but the cause is unclear:

1. Identify the last known good run and the first bad run
2. Check what changed between them (RTL, constraints, flow, tool version)
3. If multiple things changed, isolate each change and rerun independently
4. Narrow down to the single change that caused the regression

## Root Cause Analysis

### Timing Regression Analysis

When WNS/TNS regresses:

1. Identify the top violating paths in the current run
2. Check if these same paths existed in the baseline (new paths vs. degraded existing paths)
3. For degraded paths: compare cell sizing, placement, routing between runs
4. For new paths: trace back to RTL/constraint changes that created them
5. Check clock skew differences if CTS changed
6. Check route detour lengths if congestion changed

### Power Regression Analysis

When power increases:

1. Break down by component (dynamic vs. leakage vs. clock)
2. If leakage increased: check Vt distribution (more LVT cells from timing optimization)
3. If dynamic increased: check switching activity, cell count, wire capacitance
4. If clock power increased: check clock tree buffer count and wire length

### Area Regression Analysis

When area increases:

1. Compare cell counts by category (was it buffers, registers, or logic?)
2. Check if ECOs added new logic
3. Check if optimization added excessive buffering
4. Compare utilization; if utilization increased but area is the same, macros may have shifted

## Dashboard Design

### Executive Dashboard

For management and milestone reviews:

- Traffic light status per block (green/yellow/red) based on metric targets
- Key metrics: WNS, TNS, power, area, DRC count
- Schedule status: current milestone vs. plan
- Top 3 risk items

### Engineering Dashboard

For daily PD work:

- Detailed metrics per scenario with baseline comparison
- Trend plots for the last 20 runs
- Path group breakdown (which clock domains are failing)
- DRC category breakdown
- Congestion heatmap snapshots

### Refresh Frequency

- Engineering dashboards: refresh after every run (automated)
- Executive dashboards: refresh daily or at milestone gates
- Alerts: real-time (triggered immediately upon regression detection)

## Best Practices

1. **Start tracking from day one**: Do not wait until signoff to start collecting metrics
2. **Version everything**: Tag each run with the exact versions of RTL, constraints, libraries, tools, and flow scripts
3. **Automate relentlessly**: Manual tracking introduces gaps and errors
4. **Define targets early**: Set metric targets at project kickoff and track against them throughout
5. **Review weekly**: Hold a weekly QoR review meeting where the team examines trends and discusses regressions
6. **Archive baselines**: Never delete baseline data; it is the reference point for all future analysis
7. **Correlate across stages**: A synthesis regression often predicts a PnR regression; catch it early
8. **Use consistent environments**: Changes in compute environment (machine, OS version, memory) can cause metric noise; control for this
