# Timing Closure: Strategies for Achieving Signoff Timing

## What Is Timing Closure?

Timing closure is the process of ensuring that all timing constraints -- setup, hold, max transition, max capacitance, and clock domain crossing -- are met across all signoff scenarios after physical implementation. It is the central challenge of physical design and typically consumes the majority of a project's PD schedule.

Timing closure is measured by two primary metrics: **WNS** (Worst Negative Slack) and **TNS** (Total Negative Slack). WNS is the most negative slack across all paths; TNS is the sum of all negative slacks. The goal is WNS >= 0 and TNS = 0 across all active signoff views.

## The Timing Closure Flow

### Pre-Placement

Before placement begins, ensure the design is set up for success:

- **Constraint quality:** Validate SDC completeness and correctness. Wrong constraints waste days of optimization effort.
- **Floorplan quality:** Macro placement, pin assignment, and blockage placement directly affect timing. Poor floorplanning cannot be compensated by downstream optimization.
- **Logical optimization:** Ensure synthesis has produced a well-optimized netlist. If synthesis WNS is deeply negative, placement will not fix it.

### Placement Optimization

During placement, the tool simultaneously optimizes cell locations for timing, congestion, and routability:

- **Timing-driven placement** positions cells to minimize critical path wire lengths
- **Congestion-driven placement** spreads cells to avoid routing hotspots
- **Scan chain reordering** during placement minimizes scan chain wire lengths

Monitor placement timing carefully. If post-placement WNS is worse than -200ps for a 500MHz design (more than 10% of the clock period), investigate root causes before proceeding.

### Clock Tree Synthesis (CTS)

CTS builds the clock distribution network and has a major impact on timing:

- **Skew targets:** Specify useful skew targets that favor setup-critical paths
- **Insertion delay:** Longer clock trees mean more latency variation and OCV impact
- **Post-CTS optimization:** Run post-CTS timing optimization to fix violations introduced by actual clock tree delays

### Routing and Post-Route Optimization

Routing converts estimated wire delays to actual routed parasitics:

- **Post-route timing** is the first realistic timing view
- **SI (Signal Integrity)** analysis adds crosstalk-induced delay and noise
- **Post-route optimization** performs ECO-style fixes: buffer insertion, gate sizing, VT swapping

## WNS and TNS Reduction Strategies

### Critical Path Optimization

Identify the critical path and systematically address each delay component:

1. **Cell delay dominance:** If cell delays dominate, upsize gates or swap to faster VT cells
2. **Wire delay dominance:** If wire delay dominates, add repeater buffers or move cells closer
3. **Clock skew issues:** If the launch clock arrives late or capture clock arrives early, adjust clock tree or apply useful skew
4. **Logic depth:** If the path has too many logic stages, restructure or retime

### Gate Sizing

Gate sizing is the most commonly used optimization technique. Larger cells have lower delay but higher power and area. The tool selects the optimal drive strength for each cell.

- **Upsizing:** Replace a cell with a higher drive strength version (e.g., BUF_X4 to BUF_X8). Reduces cell delay but increases load on the driver.
- **Downsizing:** Replace with a lower drive strength on non-critical paths to save power and reduce congestion.

### VT Swapping

Threshold voltage (VT) swapping trades leakage power for speed:

- **LVT (Low-VT):** Fastest cells, highest leakage. Use on critical paths.
- **SVT (Standard-VT):** Balanced speed and leakage. Default for most cells.
- **HVT (High-VT):** Slowest cells, lowest leakage. Use on non-critical paths.
- **ULVT (Ultra-Low-VT):** Fastest available, very high leakage. Use sparingly on the most critical paths.

A typical post-optimization VT distribution is 10-15% LVT, 50-60% SVT, 25-35% HVT.

### Buffer Insertion and Removal

- **Buffer insertion** on long nets reduces delay by breaking a large RC network into smaller segments
- **Buffer removal** on short nets where the buffer adds unnecessary delay
- **Inverter pairing** can sometimes be faster than a buffer due to faster inverter cells

### Useful Skew

Useful skew intentionally introduces clock skew to borrow time from paths with positive slack and give it to paths with negative slack.

```
Before useful skew:
  Path A: launch_clk -> data -> capture_clk  slack = -50ps
  Path B: launch_clk -> data -> capture_clk  slack = +200ps

After useful skew (delay capture clock of Path A by 100ps):
  Path A: slack = +50ps  (improved)
  Path B: slack = +100ps (reduced but still positive)
```

Useful skew is powerful but must be applied carefully because it shifts timing budget between paths and can introduce hold violations.

### Logic Restructuring

When cell-level optimization is insufficient, restructure the logic:

- **Critical path decomposition:** Break a complex gate (e.g., 4-input AND-OR) into simpler stages to reduce the critical arc delay
- **Logic duplication:** Duplicate a high-fanout cell and distribute the load to reduce delay
- **Path balancing:** Equalize path delays to arriving signals at a gate to minimize the worst-case delay

### Register Retiming

Retiming moves flip-flops across combinational logic to balance the pipeline stages:

- If Stage 1 has 2ns of logic and Stage 2 has 0.5ns, retiming can move logic from Stage 1 to Stage 2 to equalize at ~1.25ns each
- Retiming changes the pipeline latency but maintains functional equivalence
- Tools like Fusion Compiler support automatic retiming during synthesis and placement

## Iterative Closure Strategy

### The Convergence Loop

1. Run full-scenario timing analysis
2. Identify top 20 failing endpoints and classify by root cause
3. Apply targeted fixes (sizing, buffering, restructuring)
4. Re-run timing to verify improvement without new violations
5. Repeat until WNS >= 0 and TNS = 0

### When Timing Will Not Close

If iterations stall with persistent violations:

- **Re-evaluate floorplan:** Move macros, adjust pin placement, add placement guides for critical modules
- **Re-evaluate constraints:** Verify that the failing paths are real and correctly constrained
- **Re-evaluate the microarchitecture:** Request RTL changes to reduce logic depth (add pipeline stages, simplify logic)
- **Escalate to the design team:** Persistent timing failures may indicate an unreachable frequency target

## Advanced Techniques

### Endpoint-Based Optimization

Instead of optimizing globally, focus on specific failing endpoints with targeted ECO operations:

```tcl
# In Innovus: ECO optimization targeting specific endpoints
ecoPlace
ecoRoute
optDesign -postRoute -setup -drv
```

### Multibit Optimization

Merging single-bit flip-flops into multibit cells reduces clock tree load and can improve timing by sharing clock pins.

### Physical-Aware Synthesis

Running synthesis with a physical floorplan allows the synthesizer to estimate wire delays more accurately, producing netlists that are easier to close in PnR.

## Metrics and Reporting

Track these metrics throughout the flow:

| Metric | Target | Acceptable | Needs Work |
|---|---|---|---|
| WNS (setup) | >= 0ps | > -50ps | < -100ps |
| TNS (setup) | 0ps | > -500ps | < -2000ps |
| Failing endpoints | 0 | < 20 | > 100 |
| Max transition violations | 0 | < 10 | > 100 |
| Max capacitance violations | 0 | < 5 | > 50 |

## Practical Recommendations

1. **Fix timing early.** Every stage of the flow should improve timing, not degrade it. If post-placement timing is significantly worse than synthesis, investigate before proceeding.

2. **Understand the critical path.** Do not blindly run optimization. Analyze the top failing paths, understand why they fail, and apply the right technique.

3. **Preserve hold margin during setup optimization.** Aggressive setup optimization (upsizing, useful skew) can introduce hold violations. Always check hold after setup optimization.

4. **Use incremental optimization.** After fixing specific paths, run incremental rather than full optimization to avoid disturbing converged paths.

5. **Monitor power during timing closure.** Aggressive upsizing and LVT swapping can blow the power budget. Set VT usage limits and power targets in the optimization commands.

Timing closure is as much art as science. The best engineers develop intuition for which techniques to apply and when, built on deep understanding of the underlying physics and tool behavior.
