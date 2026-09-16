# Low-Power DFT: Managing Test Power

## The Test Power Problem

Power consumption during structural testing is dramatically higher than during functional operation. During scan shift, every flip-flop in the design toggles at the shift clock frequency, creating near-50% switching activity across the entire chip simultaneously. During capture, the uncorrelated nature of ATPG patterns causes massive combinational logic switching as the functional logic evaluates the test vector. This results in:

- **Shift power**: 2-5x higher than functional peak power, sustained for thousands of shift cycles
- **Capture power**: Can spike to 5-10x functional average power for a single cycle
- **Total test power**: Consistently exceeds thermal design limits if not managed

Excessive test power causes several problems:
- **IR drop**: Voltage droop at flip-flops and logic gates causes timing violations, leading to false failures (good dies rejected as bad)
- **Thermal damage**: Sustained high power during shift can overheat the die, especially during wafer sort where heat dissipation is poor
- **Electromigration stress**: High current density during test can accelerate EM degradation
- **Yield loss**: False failures reduce apparent yield, increasing manufacturing cost
- **Reliability degradation**: Thermal and electrical stress during test can damage marginal structures

Managing test power is not optional in modern designs -- it is a fundamental requirement for accurate, reliable testing.

## Shift Power Reduction

### Low-Power Scan Shift Fill

ATPG patterns specify values for only a small percentage of scan flip-flops (typically 1-5%). The remaining don't-care (X) positions can be filled with any value. Low-power fill strategies set these X-values to minimize toggling during shift:

**Adjacent fill**: Set each X-bit equal to its neighbor in the scan chain. If bit N is a care bit with value 1, then adjacent X-bits are filled with 1, creating long runs of identical values. Transitions occur only at boundaries between care bits.

**Zero fill / One fill**: Fill all X-bits with 0 (or all with 1). Simple but less effective than adjacent fill since transitions still occur at care bit boundaries.

**Minimum-transition fill**: An optimization that considers the entire chain and fills X-bits to globally minimize the total number of transitions during the complete shift operation. This provides the best power reduction but is more computationally expensive.

Low-power fill typically reduces shift power by 50-80% compared to random fill, with negligible impact on pattern count or coverage.

### Shift Frequency Reduction

Reducing the shift clock frequency proportionally reduces dynamic power:
```
P_dynamic = alpha * C * V^2 * f
```

Halving the shift frequency halves the shift power but doubles the test time. This is a direct trade-off between power and cost. Typical shift frequencies are 50-200 MHz, chosen to balance power and throughput.

### Multi-Phase Shift

Divide scan chains into groups that shift at different times. While group A shifts, group B's clocks are gated off, and vice versa. This reduces peak shift power by the number of phases (2-phase shift halves peak power). Trade-off: test time increases proportionally.

### Scan Chain Partitioning

Physical partitioning of scan chains into segments that can be independently clocked. Only the segments being actively loaded shift; others remain static. Requires more complex clock gating control but provides fine-grained power management.

## Capture Power Reduction

### Toggle-Budget ATPG

Modern ATPG tools accept a toggle budget constraint that limits the number of flip-flops allowed to change state during capture:

```
set_atpg_constraints -capture_toggle_limit 15%
```

The tool generates patterns where at most 15% of flip-flops toggle during the capture cycle. This may require more patterns to achieve the same coverage (some patterns that detect multiple faults may be split into lower-power alternatives).

Typical toggle budgets:
- Aggressive low-power: 10-15% (minimal yield loss risk, may increase pattern count 20-50%)
- Moderate low-power: 15-25% (good balance of power and pattern efficiency)
- Relaxed: 25-40% (some power reduction with minimal pattern count impact)

### Preferred Fill for Capture

Beyond shift power, the fill strategy also affects capture power. Capture-power-aware fill considers the combinational logic response to the filled values, choosing fills that minimize logic switching during capture. This requires logic simulation during fill, making it more computationally intensive.

### Clock Gating During Capture

During the capture cycle, clock gates that are enabled in functional mode may or may not be enabled depending on the ATPG pattern. Forcing some clock gates off during capture reduces the number of flip-flops that toggle:

- Identify clock gate groups that are not needed for the current pattern's targeted faults
- Gate their clocks during capture to prevent unnecessary switching
- Requires clock gate control points accessible from scan

### Chain-Based Power Management

Some compression architectures support selective chain activation during capture. Only the chains relevant to the current pattern's fault targets are clocked during capture; others remain static. This significantly reduces capture switching activity.

## Clock Gating During Test

Clock gating cells (ICGs) are ubiquitous in modern designs for functional power reduction. During test, these gates must be handled carefully:

### Test Enable on Clock Gates

Every clock gating cell should have a test enable (TE) input that bypasses the functional enable:
```
gated_clock = CLK AND (functional_enable OR test_enable)
```

During scan shift, TE=1 forces all clock gates open, allowing all gated flip-flops to shift. During capture, TE can be 0 (allowing functional clock gating to control which flip-flops capture) or 1 (all flip-flops capture).

### Selective Clock Gating Control During Capture

For low-power capture, the test strategy can exploit clock gating:

**TE=0 during capture**: Only functionally-gated flip-flops with enabled clock gates capture. This reduces capture power but may reduce coverage since some flip-flops do not toggle.

**Partial TE control**: Different clock gate groups have independently controllable TE signals. ATPG selectively enables only the clock gates needed for each pattern's fault targets.

**Multi-capture-cycle approach**: Some tools support multiple capture cycles with different clock gate configurations, testing different sets of flip-flops in each cycle while keeping power low.

## Power-Aware DFT Flow

A power-aware DFT flow integrates power management throughout:

### Planning Phase
1. Analyze functional power profile to establish test power budget
2. Define toggle budget targets based on IR drop analysis
3. Allocate clock gating test enable strategy
4. Plan multi-phase shift if needed

### Insertion Phase
1. Insert clock gates with test enable
2. Add scan chain partitioning for multi-phase shift
3. Insert power management control registers in scan chains
4. Add on-chip power monitors for test power feedback

### ATPG Phase
1. Run power-aware ATPG with toggle budget constraints
2. Apply low-power fill (adjacent fill or minimum-transition fill)
3. Analyze power profile of generated patterns
4. Iterate if power targets are not met (tighten constraints, accept more patterns)

### Validation Phase
1. Simulate patterns with power analysis (vectorless or vector-based)
2. Verify IR drop during shift and capture stays within limits
3. Validate that power reduction has not impacted coverage excessively
4. Check ATE compatibility (power-optimized patterns may have different structure)

## Power Analysis for Test Patterns

### Vector-Based Power Analysis

Simulate actual test patterns and compute switching activity at every node:
- Accurate but computationally expensive
- Can identify specific patterns with excessive power
- Enables pattern-level power filtering (remove or regenerate high-power patterns)

### Vectorless Power Analysis

Estimate switching activity statistically without simulating specific patterns:
- Fast but less accurate
- Good for early-stage power budgeting
- Assumes a toggle rate (e.g., 50% for shift, 20% for capture) and computes power

### IR Drop Analysis

Critical for ensuring test patterns do not cause timing violations:
1. Run dynamic IR drop analysis with test pattern switching activity
2. Identify flip-flops and logic gates experiencing excessive voltage droop
3. Correlate with timing paths to identify potential false failures
4. Adjust toggle budget or pattern fill to reduce IR drop at critical locations

## Advanced Low-Power Techniques

### Broadside Power Reduction for LOC

In LOC transition testing, the launch pulse creates a functional state that drives the capture response. The power during the launch-to-capture window depends on the correlation between the launch and capture states. Power-aware LOC ATPG minimizes the difference between launch and capture states.

### LBIST Power Management

LBIST patterns have inherently high toggle rates (~50%) since they are pseudo-random. Power management for LBIST:
- Multi-phase LBIST: Clock only a subset of scan chains in each BIST cycle
- Weighted PRPG: Bias toggle rates to reduce switching
- Reduced pattern count: Accept lower LBIST coverage to limit power duration
- Power throttling: Monitor on-chip temperature and throttle BIST speed

### Adaptive Test Power

Advanced test strategies adjust power management dynamically:
- Apply high-toggle patterns first while the die is cool
- Monitor temperature and reduce toggle rate as the die heats up
- Skip low-value patterns if power budget is exhausted
- Use per-die power profiles to optimize test time

## Metrics and Targets

| Metric | Target | Method |
|--------|--------|--------|
| Shift toggle rate | <20% | Low-power fill |
| Capture toggle rate | <15-25% | Toggle budget ATPG |
| Peak IR drop (shift) | <10% Vdd | Multi-phase shift |
| Peak IR drop (capture) | <8% Vdd | Toggle-budget + fill |
| Pattern count increase | <30% vs. unconstrained | Power-coverage trade-off |
| Test time increase | <50% vs. unconstrained | Acceptable for power safety |
