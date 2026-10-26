# Regression Methodology: Automated QoR Tracking and Build Management

## Overview

Regression methodology is the systematic practice of running automated design builds on a regular schedule (typically nightly or weekly), extracting quality-of-results (QoR) metrics, comparing against baselines, and tracking trends over time. Regression is essential for managing the complexity of modern SoC physical design, where small changes in RTL, constraints, libraries, or tool settings can cause unexpected degradation. A robust regression infrastructure catches issues early, prevents silent QoR erosion, and provides data-driven decision-making for the design team.

## Nightly Builds

### Purpose

Nightly builds (also called nightly regressions) automatically run the complete or partial design flow every night using the latest design data. They serve multiple purposes:

1. **Early bug detection**: Catch RTL issues, constraint errors, or tool regressions within 24 hours.
2. **QoR trending**: Track timing, area, power, and congestion metrics over time.
3. **Integration verification**: Verify that changes from multiple engineers integrate correctly.
4. **Tapeout readiness**: As tapeout approaches, nightly builds provide a continuous assessment of signoff readiness.

### Build Types

**Full build**: Runs the complete flow from synthesis through routing and signoff. Takes 8-24+ hours depending on design size. Run nightly or weekly.

**Incremental build**: Starts from a checkpoint (e.g., post-placement) and runs only the remaining stages. Faster (4-8 hours) and useful for testing routing or signoff changes.

**Signoff-only build**: Runs signoff checks (STA, DRC, LVS) on existing layout data. Useful for constraint or library updates that do not require re-implementation.

### Nightly Build Infrastructure

A typical nightly build system includes:

1. **Scheduler**: Cron job, Jenkins, or a custom scheduler triggers the build at a fixed time (e.g., midnight).
2. **Environment setup**: Source the correct tool versions, library paths, and design data.
3. **Build script**: Executes the design flow (synthesis, P&R, signoff) with fixed settings.
4. **Metric extraction**: Parses tool reports to extract key metrics.
5. **Comparison engine**: Compares current metrics against the baseline.
6. **Notification**: Sends email or Slack alerts if metrics degrade beyond thresholds.
7. **Dashboard**: Web-based dashboard displaying metrics, trends, and build status.

```bash
# Example nightly build cron entry:
0 0 * * * /proj/scripts/run_nightly.sh my_soc > /proj/logs/nightly_$(date +%Y%m%d).log 2>&1
```

### Build Configuration Management

- **Frozen tool versions**: The build always uses the same EDA tool versions unless explicitly updated.
- **Latest RTL**: The build pulls the latest RTL from the version control system (Git, Perforce).
- **Fixed constraints**: Constraint files are version-controlled and the build uses a specific tag/branch.
- **Reproducibility**: Every build must be reproducible given the same inputs. Log the exact commit hashes, tool versions, and settings.

## QoR Tracking

### Key Metrics

Physical design QoR is measured by a standard set of metrics extracted from tool reports:

**Timing Metrics:**
- WNS (Worst Negative Slack): The worst setup slack across all paths and corners.
- TNS (Total Negative Slack): The sum of all negative slacks.
- WHS (Worst Hold Slack): The worst hold slack.
- THS (Total Hold Slack): The sum of all hold violations.
- Number of violating paths (NVP): Count of paths with negative slack.
- Maximum transition violations: Count and worst value.
- Maximum capacitance violations: Count and worst value.

**Physical Metrics:**
- Total cell area.
- Cell utilization (cell area / core area).
- Routing congestion (peak overflow, average congestion).
- DRC violation count.
- Via doubling percentage.
- Wire length (total, per layer).

**Power Metrics:**
- Total power (leakage + dynamic).
- Leakage power.
- Clock power.
- Vt distribution (% HVT, % SVT, % LVT).

**Runtime Metrics:**
- Total flow runtime.
- Per-stage runtime (synthesis, placement, CTS, routing).
- Peak memory usage.

### Metric Extraction

Metrics are extracted from tool reports using scripts (Python, Perl, or TCL):

```python
# Example: Extract WNS from PrimeTime report
import re

def extract_wns(pt_report_file):
    with open(pt_report_file, 'r') as f:
        for line in f:
            match = re.search(r'WNS\s+(-?\d+\.?\d*)', line)
            if match:
                return float(match.group(1))
    return None
```

More robust extraction uses the tool's TCL interface:

```tcl
# Inside PrimeTime:
set wns [get_attribute [get_timing_paths -max_paths 1 -slack_lesser_than 0] slack]
puts "WNS: $wns"
```

## Baseline Comparison

### What is a Baseline?

A baseline is a reference set of QoR metrics representing the known-good state of the design. All subsequent builds are compared against the baseline to detect improvements or degradations.

### Baseline Management

1. **Initial baseline**: Set after the first clean build that meets preliminary targets.
2. **Baseline updates**: Update the baseline when intentional changes improve QoR (e.g., after a successful optimization effort). Never update the baseline to hide degradation.
3. **Per-block baselines**: In a multi-block SoC, each block has its own baseline.
4. **Corner-specific baselines**: Track baselines per MMMC corner, not just the worst corner.

### Comparison Methodology

For each metric, compute the delta from the baseline:

```
Delta = Current_Value - Baseline_Value
Delta_Percent = (Delta / |Baseline_Value|) * 100%
```

Flag degradation beyond thresholds:

| Metric | Warning Threshold | Error Threshold |
|---|---|---|
| WNS | Any degradation > 10ps | Regression from positive to negative |
| TNS | Any degradation > 5% | Degradation > 20% |
| Area | Increase > 2% | Increase > 5% |
| Leakage | Increase > 5% | Increase > 15% |
| DRC violations | Any increase | > 100 new violations |
| Runtime | Increase > 20% | Increase > 50% |

### Regression Report Format

```
============================================================
NIGHTLY REGRESSION REPORT: my_soc_top
Date: 2025-05-18    Build: #347    Status: WARNING
============================================================

TIMING (corner: ss_0p75v_125c)
  Metric          Current    Baseline    Delta      Status
  WNS (ps)        -12        +5          -17        ERROR
  TNS (ps)        -345       0           -345       ERROR
  NVP             23         0           23         ERROR
  WHS (ps)        +15        +18         -3         OK

AREA
  Cell Area (um2)  1,234,567  1,230,000   +4,567    OK (+0.4%)
  Utilization      67.2%      67.0%       +0.2%     OK

POWER (TT, 0.85V, 25C)
  Total (mW)       523        518         +5        OK (+1.0%)
  Leakage (mW)     89         85          +4        WARNING (+4.7%)

DRC
  Violations       0          0           0         PASS

RUNTIME
  Total (hours)    14.2       13.8        +0.4      OK (+2.9%)
============================================================
```

## Pass/Fail Criteria

### Pre-Tapeout Criteria

As the design progresses toward tapeout, the pass/fail criteria become stricter:

**Early phase (floorplan to initial placement):**
- WNS can be negative (target: > -200ps).
- DRC violations expected.
- Focus on congestion and utilization feasibility.

**Mid phase (CTS to initial routing):**
- WNS improving toward zero (target: > -50ps).
- DRC violations decreasing.
- Hold violations being fixed.

**Late phase (post-route optimization):**
- WNS = 0 (zero negative slack).
- TNS = 0.
- DRC = 0 (or documented waivers only).
- LVS = clean.

**Signoff phase:**
- All signoff criteria met (see timing_signoff.md, manufacturing_signoff.md).
- Any regression from clean is an immediate escalation.

### Automated Gating

Some teams implement automated gating where a build that fails critical criteria:
- Blocks the RTL commit that caused the regression.
- Prevents downstream flows from running on bad data.
- Triggers automatic email to the committer and design lead.

## Trending

### Why Trending Matters

Individual build results are less informative than trends. A metric that is slowly degrading over weeks may not trigger a single-build alarm but represents a real problem.

### Trend Analysis

1. **Plot metrics over time**: Generate charts showing WNS, TNS, area, and power over the last 30-90 days.
2. **Moving average**: Smooth noise by plotting 7-day moving averages.
3. **Slope detection**: Alert if a metric's trend slope indicates it will miss the tapeout target at the current rate.
4. **Correlation analysis**: Identify which changes (RTL commits, constraint updates, tool upgrades) correlate with QoR changes.

### Dashboard

A regression dashboard provides at-a-glance visibility into design health:

```
Block Name       WNS    TNS    DRC    LVS    Power    Status
cpu_core         0      0      0      PASS   287mW    GREEN
gpu_core         -15    -230   12     PASS   456mW    RED
mem_ctrl         0      0      3      PASS   89mW     YELLOW
io_subsys        0      0      0      PASS   112mW    GREEN
soc_top          -8     -120   47     FAIL   1.2W     RED
```

Color coding: GREEN = all metrics pass, YELLOW = warnings, RED = errors.

## Regression Infrastructure Best Practices

1. **Automate everything**: No manual steps in the nightly build. Every step must be scripted and reproducible.
2. **Version control build scripts**: Build scripts are part of the project repository, versioned alongside the design data.
3. **Archive all results**: Keep build logs, reports, and metrics for the entire project duration. Storage is cheap; rebuilding is expensive.
4. **Independent builds**: Each block builds independently. A failure in one block does not block others.
5. **Fast feedback**: Send notifications within minutes of build completion, not the next morning.
6. **Root cause tracking**: When a regression occurs, document the root cause and the fix. Build a knowledge base of common regression causes.
7. **Scale compute**: Use distributed computing (LSF, SGE, Kubernetes) to run multiple blocks in parallel.
8. **Regular review**: Hold weekly QoR review meetings where the team examines trends and prioritizes fixes.

## Common Regression Causes

| Cause | Impact | Prevention |
|---|---|---|
| RTL change (new logic) | Area/timing degradation | Require RTL review before merge |
| Constraint change | Timing shift (better or worse) | Constraint review process |
| Library update | Timing/power change | Test new libraries on representative design first |
| Tool version update | Unpredictable QoR shift | Lock tool versions; test upgrades separately |
| Floorplan change | Congestion, timing | Version-control floorplan DEFs |
| IP update | Various | Verify IP QoR independently |

A mature regression methodology is the backbone of successful physical design execution. It transforms the design process from reactive fire-fighting to proactive, data-driven engineering.
