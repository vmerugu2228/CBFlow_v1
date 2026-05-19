# Design Closure: Convergence, Multi-Objective Optimization, and Knowing When to Stop

## Overview

Design closure is the process of iteratively optimizing a design until it simultaneously meets all signoff requirements: timing, power, area, DRC, LVS, EM, IR drop, and signal integrity. It is the most time-consuming and skill-intensive phase of physical design, often accounting for 40-60% of total implementation effort.

Design closure is fundamentally about convergence -- making measurable progress toward all targets with each iteration and recognizing when further effort yields diminishing returns. The ability to diagnose root causes, prioritize effectively, and make strategic decisions about where to invest effort distinguishes experienced PD engineers.

## The Convergence Challenge

### Multi-Objective Nature

Design closure requires satisfying multiple competing objectives simultaneously:

- **Setup timing**: All setup paths must have non-negative slack
- **Hold timing**: All hold paths must have non-negative slack
- **Power**: Total power (dynamic + leakage) must be within the power budget
- **Area**: Die size and utilization must be within targets
- **DRC**: Zero design rule violations (or approved waivers)
- **EM**: All wires and vias within electromigration limits
- **IR drop**: Voltage drop within budget at all locations
- **Signal integrity**: Crosstalk noise within acceptable bounds

### Trade-offs Between Objectives

Improving one metric often degrades another:

| Action | Improves | Degrades |
|---|---|---|
| Upsize cells | Setup timing | Area, power |
| Swap to LVT | Setup timing | Leakage power |
| Swap to HVT | Leakage power | Setup timing |
| Add buffers | Setup timing, SI | Area, power, routing |
| Widen wires (NDR) | Timing, EM | Routing congestion |
| Increase utilization | Area | Timing, congestion |
| Spread cells | Congestion | Wire length, timing |

The art of design closure is navigating these trade-offs efficiently.

## Iterative Optimization Process

### Typical Iteration Loop

1. **Analyze**: Run timing, power, DRC, EM analysis. Categorize all violations
2. **Diagnose**: Identify root causes of worst violations. Is it placement? Routing? Clock tree? Constraints?
3. **Prioritize**: Focus on the violations with the largest impact or that block the most downstream fixes
4. **Fix**: Apply targeted fixes (optimization commands, constraint adjustments, manual ECOs)
5. **Verify**: Re-analyze to confirm fixes worked and did not introduce new violations
6. **Repeat**: Continue until all metrics converge to targets

### Convergence Tracking

Track key metrics across iterations:

```
Iteration | WNS (ps) | TNS (ns) | Hold Viol | DRC | Leakage (mW) | Max IR Drop (mV)
---------|----------|----------|-----------|-----|-------------|----------------
1        | -250     | -45.0    | 1200      | 350 | 85          | 42
2        | -120     | -18.5    | 450       | 120 | 78          | 38
3        | -55      | -5.2     | 80        | 25  | 82          | 35
4        | -15      | -0.8     | 12        | 5   | 80          | 34
5        | -3       | -0.1     | 2         | 0   | 81          | 34
6        | +2       | 0        | 0         | 0   | 80          | 34
```

Key observations:
- WNS (Worst Negative Slack) should improve monotonically
- TNS (Total Negative Slack) should decrease steadily
- If any metric worsens between iterations, investigate the regression immediately
- Plot convergence graphs to visualize trends

## Root Cause Analysis

### Common Root Causes of Timing Violations

1. **Floorplan issues**: Macros blocking direct paths, insufficient channels, poor pin placement
2. **Clock tree quality**: Excessive skew, long insertion delay, clock reconvergence issues
3. **Constraint errors**: Missing or incorrect SDC constraints, wrong clock definitions
4. **Library issues**: Missing cells, incorrect characterization, wrong operating conditions
5. **Congestion**: Routes detoured around congested areas, adding delay
6. **Cross-talk**: Coupling from aggressor nets adding delay to victim nets
7. **RC estimation mismatch**: Difference between PnR estimated parasitics and signoff extraction

### Diagnosis Techniques

- **Path analysis**: Examine the top failing paths in detail. What cells, what routing, what crosstalk?
- **Histogram analysis**: Plot slack distribution. Is it a few outlier paths or a systemic issue?
- **Comparison**: Compare current timing to previous iteration. What changed and why?
- **Correlation**: Compare PnR timing to signoff timing. Large discrepancies indicate tool settings issues
- **Physical inspection**: Visualize failing paths on the layout. Are routes detoured? Are cells far apart?

## Multi-Objective Optimization Strategy

### Phased Approach

Tackle objectives in a strategic order:

**Phase 1: Foundation (Floorplan + Placement)**
- Fix floorplan issues first. No amount of optimization fixes a bad floorplan
- Achieve reasonable placement quality (congestion < 90%, WNS within 2x of target)
- Get power grid IR drop within budget

**Phase 2: Clock (CTS)**
- Build a clean clock tree with target skew and insertion delay
- Fix hold violations from CTS
- Verify clock power is reasonable

**Phase 3: Timing (Post-Route Optimization)**
- Close setup timing through cell sizing, Vt swapping, buffering
- Fix remaining hold violations
- Iterate optimization 3-5 times

**Phase 4: Signoff (Convergence)**
- Correlate PnR timing with signoff timing; fix discrepancies
- Fix DRC violations
- Fix EM violations
- Insert fill, re-extract, verify timing
- Final hold fixing at all corners

### Priority Rules

When multiple metrics are failing:

1. **Fix DRC first if blocking other analysis**: DRC violations can invalidate extraction and timing
2. **Fix setup timing before hold**: Hold is fixed by adding delay, which is always possible. Setup requires structural changes
3. **Fix worst corner first**: Close timing at the worst-case corner, then verify other corners
4. **Fix power last** (within reason): Power optimization (HVT swapping) should happen after timing is stable

## Diminishing Returns

### Recognizing the Plateau

Every optimization has diminishing returns:
- First iterations fix the easy problems (large violations, obvious fixes)
- Later iterations face harder problems (interacting constraints, fragile optimizations)
- Eventually, each iteration takes longer and yields smaller improvements

### Quantifying Diminishing Returns

Track improvement per iteration:
- If iteration N+1 improves WNS by less than 10% of iteration N's improvement, you are on the plateau
- If TNS improvement per iteration is less than the natural variation (noise), further optimization is unlikely to help
- If the tool is oscillating (fixing path A breaks path B, fixing B breaks A), a structural change is needed

### When Effort Stops Paying Off

Signs that you have reached the practical limit:
- WNS is within 10-20 ps of target and not improving
- Optimization runtime is increasing while improvement is decreasing
- The same paths appear and disappear across iterations (oscillation)
- Hold fixes are creating setup violations and vice versa

## When to Stop

### Signoff Criteria

The design is "closed" when:
- [ ] Setup timing passes at all required corners with zero WNS
- [ ] Hold timing passes at all required corners with zero violations
- [ ] DRC is clean (zero violations or approved waivers)
- [ ] LVS is clean
- [ ] EM analysis passes at all corners
- [ ] IR drop is within budget (static and dynamic)
- [ ] Power is within budget
- [ ] Signal integrity (noise) passes

### Guardband Philosophy

Most designs add guardband (margin) beyond the minimum requirement:
- **Timing guardband**: 20-50 ps margin on WNS. Accounts for PnR-to-signoff correlation error
- **IR drop guardband**: 5-10% margin on IR drop budget
- **EM guardband**: 10-20% margin on current density

The guardband should be proportional to the uncertainty in the analysis. More mature flows with good tool correlation need less guardband.

### Escalation Criteria

If the design cannot close:
- WNS stuck at -50 ps or worse after 5+ iterations: escalate to architecture/RTL team for micro-architecture changes
- Congestion preventing routing: need die size increase or floorplan restructuring
- IR drop exceeding budget: need package change (more bumps) or power grid redesign
- Clock cannot meet target frequency: need clock architecture changes

## QoR Plateaus and Breaking Through

### Common Plateaus

1. **Timing plateau at -50 to -100 ps**: Usually caused by a structural issue (long wire, congested path, clock reconvergence)
2. **Congestion plateau**: Routing cannot be clean regardless of optimization. Need placement or floorplan change
3. **Power plateau**: Leakage dominated by memories and always-on logic that cannot be optimized

### Breaking Through Plateaus

- **Re-examine constraints**: Are constraints correct? Over-constrained paths waste optimization effort
- **Re-floorplan**: A different macro arrangement may open up new optimization opportunities
- **Change strategy**: Switch from incremental optimization to a fresh placement from a modified netlist
- **RTL changes**: Sometimes the right fix is a pipeline stage, a different memory configuration, or restructured logic
- **Technology change**: If a design cannot close at the target utilization, consider a larger die or a more advanced node

## Practical Guidance

1. **Automate convergence tracking**: Script the analysis-fix-verify loop and automatically log metrics per iteration
2. **Fix root causes, not symptoms**: A timing violation caused by congestion will recur if you only fix the timing without addressing congestion
3. **Do not chase the last 5 ps**: If WNS is -3 ps and you have been trying for a week, it is likely a guardband issue, not a real problem. Discuss with the timing lead
4. **Keep a log**: Document what was tried and what worked/did not work. This institutional knowledge is invaluable for the next project
5. **Parallel paths**: While waiting for long optimization runs, analyze the current results to plan next steps
6. **Set a deadline**: Define a "done" date and work backward. Allocate more time to early phases (floorplan, CTS) where changes have the most leverage
7. **Review with the team**: Regular design reviews catch issues that one engineer might miss. Share QoR summaries and discuss strategy
8. **Learn from each tapeout**: Post-tapeout analysis of what worked, what did not, and what should change improves the next design's closure efficiency
