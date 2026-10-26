# Hold Time Fixing: Causes, Strategies, and Implementation

## Understanding Hold Violations

A hold violation occurs when data at the capturing flip-flop changes too quickly after the active clock edge, violating the hold time requirement of the flip-flop. The hold time (Th) is the minimum duration after the clock edge during which the data input must remain stable for reliable capture.

The hold timing equation is:

```
Hold Slack = Data Arrival Time - Data Required Time
           = (Tlaunch_clk + Tcq + Tdata_path) - (Tcapture_clk + Thold)
```

For hold slack to be positive (no violation), the data must not arrive at the capture flop before the hold window closes.

## Root Causes of Hold Violations

### Short Combinational Paths

The most common cause. When the combinational logic between two flip-flops is minimal (e.g., a direct connection or a single buffer), the data propagates faster than the hold requirement.

### Clock Skew

If the launch clock arrives later than the capture clock (positive skew), the hold margin is reduced. This is particularly problematic when:
- Launch and capture flops are on different clock tree branches
- Clock tree insertion delay varies across the chip
- CTS could not balance skew between certain flop pairs

### Fast Process Corners

At FF (Fast-Fast) corners with high voltage and low temperature, cell delays are minimized, making data paths faster while hold time requirements may increase.

### Useful Skew Side Effects

When useful skew is applied for setup improvement (delaying the capture clock), it directly reduces hold margin on paths feeding that same capture flop.

### Post-CTS Clock Tree Imbalance

Before CTS, ideal clocks assume zero skew. After CTS, real clock tree skew can introduce hold violations that did not exist in the ideal clock analysis.

## Hold-Critical Corners

Hold analysis must be performed at corners where data paths are fastest:

- **FF process** with high voltage and low temperature (fastest cells)
- **Cmin extraction** (minimum parasitic capacitance = fastest wire propagation)
- **AOCV/POCV derating** that makes clock paths slower while data paths are at nominal

Typically, the most critical hold corner is `ff_0p825v_m40c` with Cmin RC extraction.

Important: hold must also be checked at slow corners because clock tree implementation can create skew-dominated hold violations regardless of process speed.

## Hold Fixing Strategies

### Buffer Insertion

The primary technique for hold fixing. Buffers are inserted in the data path to add delay, ensuring data does not arrive too early.

```
Before: FF_launch -> [short path] -> FF_capture  (hold violation)
After:  FF_launch -> BUF -> BUF -> [short path] -> FF_capture  (hold met)
```

**Buffer selection guidelines:**
- Use minimum-sized buffers (e.g., BUFX1, BUFX2) to minimize area and power impact
- Use HVT buffers when possible -- they are slower and consume less leakage
- Avoid using LVT buffers for hold fixing; they add area without sufficient delay
- Some libraries include dedicated "delay cells" optimized for hold fixing

### Delay Cell Insertion

Dedicated delay cells are designed specifically for hold fixing. They provide a known, stable delay with minimal area.

- **DEL cells** have calibrated delays (e.g., DEL_1, DEL_2, DEL_4 for 1x, 2x, 4x delay)
- They are more area-efficient than buffer chains for large delay requirements
- Not all libraries include dedicated delay cells

### Clock Concurrent Delay (CCD) Skewing

Instead of adding delay to the data path, CCD adjusts the clock arrival time by modifying the clock tree. This is a more elegant solution when many paths feeding a single capture flop have hold violations.

```tcl
# In Innovus: enable CCD for hold fixing
setOptMode -holdFixingCells {BUFX1_HVT BUFX2_HVT DELAY1_HVT}
setOptMode -usefulSkew true
optDesign -postCTS -hold
```

CCD is preferred when:
- Many data paths to the same capture flop all have hold violations
- Buffer insertion would cause excessive area and congestion
- The setup margin on those paths can tolerate the skew adjustment

### Gate Sizing (Downsizing)

Downsizing cells on the data path slows them down, helping hold. However, this technique is rarely used for hold fixing because it also degrades setup timing.

## Implementation: Post-CTS Hold Fixing

Hold fixing is performed after CTS because hold analysis requires actual clock tree delays. The standard flow is:

### Step 1: Post-CTS Optimization

```tcl
# Innovus post-CTS hold fixing
optDesign -postCTS -hold

# Fusion Compiler
clock_opt -from route_clock -to route_clock
```

### Step 2: Post-Route Hold Fixing

After routing, parasitics are more accurate and new hold violations may appear. SI-aware hold analysis may also reveal crosstalk-induced hold failures.

```tcl
# Innovus post-route hold optimization
setOptMode -holdTargetSlack 0.020  ;# 20ps margin for SI and uncertainty
setOptMode -holdFixingCells {BUFX1_HVT BUFX2_HVT}
optDesign -postRoute -hold

# Fusion Compiler
route_opt -stage hold
```

### Step 3: SI-Aware Hold Fixing

Crosstalk can advance a data signal (making it arrive earlier) or retard a clock signal (making the clock arrive later), both of which worsen hold. SI-aware hold fixing accounts for these effects.

```tcl
# Enable SI-aware analysis
setAnalysisMode -analysisType onChipVariation
setAnalysisMode -cppr both
setSIMode -analyzeNoiseThreshold 0.1
optDesign -postRoute -hold -si
```

## Hold Fixing Margin and Guardbanding

### Why Add Hold Margin?

Even after hold fixing, several factors can reduce hold slack in silicon:

- **Clock tree uncertainty:** Post-silicon clock skew may differ from the model
- **SI effects:** Crosstalk-induced timing shifts not fully modeled
- **OCV uncertainty:** Local variation in clock and data paths
- **Temperature variation across the die:** Localized hot spots can shift timing

A typical hold margin (target slack) is 20-50ps above zero.

### Setting Hold Margin

```tcl
# Innovus
setOptMode -holdTargetSlack 0.030  ;# 30ps margin

# Fusion Compiler
set_app_options -name time.hold_slack_target -value 0.030
```

## Scan Chain Hold Fixing

Scan chains are particularly susceptible to hold violations because:

- Adjacent scan flops are often physically close (short data paths)
- Scan shift mode uses a single clock domain (no inter-domain skew benefit)
- Scan chains span large physical distances, creating clock tree skew

Hold fixing in scan chains typically requires extensive buffer insertion. To minimize impact:

- **Scan chain reordering** during placement can increase physical distance between adjacent scan flops
- **Scan-specific hold fixing** targets only scan paths without disturbing functional hold
- **Dedicated scan hold buffers** are placed near scan flop pairs

## Common Pitfalls

### Over-Fixing Hold

Adding too many hold buffers causes:
- Area bloat (hold buffers can add 5-15% cell area)
- Congestion hotspots where many buffers cluster
- Power increase from buffer switching
- Setup timing degradation if buffers are placed on shared setup/hold paths

### Fixing Hold Before CTS

Hold violations reported pre-CTS with ideal clocks are meaningless. Do not fix hold until real clock tree delays are available.

### Ignoring Hold at Slow Corners

While FF corners are typically hold-critical, skew-dominated hold violations can appear at SS corners. Always check hold at both fast and slow corners.

### Not Accounting for CPPR

Common Path Pessimism Removal (CPPR) removes pessimism from paths where launch and capture clocks share common tree segments. Without CPPR, hold analysis is overly pessimistic and leads to unnecessary buffer insertion.

## ECO Hold Fixing

Late-stage hold fixes after design freeze use ECO (Engineering Change Order) methods:

```tcl
# Innovus ECO hold fixing
ecoAddRepeater -term capture_ff/D -cell BUFX2_HVT
ecoPlace
ecoRoute
```

ECO hold fixes must be verified to ensure they do not:
- Introduce DRC violations
- Create new setup or hold violations on other paths
- Cause antenna violations on rerouted nets

## Practical Recommendations

1. **Fix hold incrementally.** Run hold optimization after each major step (post-CTS, post-route, post-SI) rather than trying to fix everything at the end.

2. **Use HVT hold cells.** They provide more delay per cell, are less susceptible to process variation, and have lower leakage.

3. **Set appropriate hold margin.** 20-30ps is typical for advanced nodes. Too much margin wastes area; too little risks silicon failures.

4. **Monitor hold buffer count and area.** If hold buffers exceed 10% of total cell area, investigate root causes (clock tree quality, scan chain ordering, floorplan issues).

5. **Always run CPPR-enabled hold analysis.** Without CPPR, hold slack is artificially pessimistic, leading to over-insertion of hold buffers.

Hold fixing is one of the final critical steps in physical design. Unlike setup violations, which can sometimes be worked around with frequency reduction, hold violations cause functional failures at any frequency and cannot be fixed post-silicon.
