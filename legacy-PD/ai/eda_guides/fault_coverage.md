# Fault Coverage Metrics and Analysis

## Understanding Fault Coverage

Fault coverage is the primary metric for evaluating test quality in structural testing. It quantifies the percentage of modeled faults that the test pattern set can detect. High fault coverage correlates with high defect detection capability, and coverage targets are a key specification in every test program.

However, fault coverage is not a single number -- it is a collection of related metrics, each providing different insights into test effectiveness. Understanding these metrics and their relationships is essential for making informed DFT decisions and communicating test quality to stakeholders.

## Fault Classification

ATPG tools classify every fault in the design into one of several categories:

**Detected (DT)**: A test pattern exists that produces different outputs for the good circuit and the faulty circuit. This is the goal -- every detectable fault should have at least one pattern that detects it.

**Possibly Detected (PT)**: The pattern produces a difference at some output, but the difference may be masked by other effects (e.g., X-values at the observation point). Some tools further subdivide into PT-detected and PT-not-detected.

**Undetectable (UD)**: The fault is provably untestable -- no possible input pattern can distinguish the faulty circuit from the good circuit. This occurs due to:
- Tied-off inputs (e.g., a pin permanently tied to VDD makes SA1 on that pin undetectable)
- Redundant logic (the fault-free and faulty circuits are functionally identical)
- Unused outputs (a fault effect can never reach any observed point)

**ATPG Untestable (AU)**: The ATPG tool could not find a pattern within its allocated effort (backtrack limit), but the fault is not proven undetectable. These faults might be detected with more effort or different algorithms.

**Not Analyzed (NA)**: Faults not yet processed by the ATPG tool, either due to abort or early termination.

**Blocked (BL)**: Faults that cannot be tested due to DFT DRC violations (e.g., a fault behind an uncontrollable clock gate).

## Coverage Metric Definitions

### Fault Coverage (FC)

The most commonly reported metric:

```
FC = (Detected Faults) / (Total Faults) x 100%
```

Total faults include all modeled faults: detected, undetectable, ATPG-untestable, and not-analyzed. This is the most conservative metric because undetectable faults are in the denominator even though they can never be tested.

### Test Coverage (TC)

Excludes provably undetectable faults from the denominator:

```
TC = (Detected Faults) / (Total Faults - Undetectable Faults) x 100%
```

Test coverage gives a more realistic picture of test quality since it measures detection among faults that are theoretically detectable. TC >= FC always.

### ATPG Effectiveness (AE)

Measures how completely the ATPG tool explored the fault space:

```
AE = (Detected + Undetectable) / (Total Faults) x 100%
```

High effectiveness (>99%) means the tool resolved almost every fault -- either finding a pattern to detect it or proving it undetectable. Low effectiveness indicates many faults remain unresolved, often due to insufficient ATPG effort or tool limitations.

### Adjusted Fault Coverage

Some organizations define custom metrics that weight different fault categories:

```
AFC = (DT + weight * PT) / (Total - UD) x 100%
```

where PT faults are counted with a weight factor (e.g., 0.5 for possibly detected faults).

## Coverage Targets by Application

| Application | Stuck-At FC | Transition FC | Notes |
|-------------|-------------|---------------|-------|
| Consumer electronics | 95-97% | 90-95% | Cost-sensitive, moderate quality |
| Mobile/wireless | 97-98% | 93-96% | Moderate quality, power focus |
| Networking/server | 98-99% | 95-98% | High reliability requirement |
| Automotive (ASIL-B) | 98-99% | 96-98% | ISO 26262 compliance |
| Automotive (ASIL-D) | 99%+ | 98%+ | Strictest safety requirement |
| Medical devices | 99%+ | 97-99% | Regulatory compliance |
| Military/aerospace | 99%+ | 98%+ | Zero-tolerance for field failure |

These targets are for test coverage (TC), not raw fault coverage. The distinction matters when there are many undetectable faults.

## Pattern Count Analysis

Pattern count directly impacts test time and cost:

```
Test Time = (Pattern Count x Chain Length x Shift Period) + (Pattern Count x Capture Time) + Overhead
```

Factors affecting pattern count:
- **Fault coverage target**: Higher targets require disproportionately more patterns (the last 1% of coverage may need 30% of total patterns)
- **Compression ratio**: Higher compression = shorter chains = less shift time per pattern
- **Compaction efficiency**: Dynamic compaction packs multiple fault detections into one pattern. Typical compaction: 10-50 faults per pattern for stuck-at, 2-10 for transition
- **Design complexity**: Reconvergent fanout, deep logic cones, and shared resources increase pattern count

Typical pattern counts:
- Small blocks (100K gates): 500-2,000 patterns
- Medium SoCs (10M gates): 5,000-20,000 patterns
- Large SoCs (100M+ gates): 20,000-100,000+ patterns

## Coverage Analysis and Debugging

When coverage falls short of targets, systematic analysis identifies the causes:

### Step 1: Analyze Fault Categories

Examine the ATPG report to understand fault distribution:
```
Total faults:     2,000,000
Detected:         1,940,000  (97.0%)
Undetectable:        30,000  (1.5%)
ATPG Untestable:     20,000  (1.0%)
Not Analyzed:         5,000  (0.25%)
Blocked:              5,000  (0.25%)
```

In this example:
- Test coverage = 1,940,000 / (2,000,000 - 30,000) = 98.5%
- ATPG effectiveness = (1,940,000 + 30,000) / 2,000,000 = 98.5%

### Step 2: Investigate Undetectable Faults

Large numbers of undetectable faults may indicate:
- Excessive tied-off signals: Review if tie-offs are necessary
- Redundant logic: Synthesis may have left redundant gates; re-synthesis with different settings may help
- Unused pins: Expected if spare logic or unused configuration options exist

### Step 3: Address ATPG Untestable Faults

These are the primary opportunity for improvement:
- Increase ATPG abort limit (e.g., from 10,000 to 100,000 backtracks)
- Add test points at hard-to-control/observe nodes
- Review DFT exclusions -- are there flip-flops excluded from scan that shouldn't be?
- Check for uncontrolled clock gating or reset signals

### Step 4: Resolve Blocked Faults

Blocked faults indicate DFT structural issues:
- Fix DFT DRC violations
- Ensure all clock gates have test bypass
- Verify all async resets are controllable during test
- Check for missing scan connections

### Step 5: Reduce Not-Analyzed Faults

Increase ATPG runtime or effort:
- Run ATPG with higher effort settings
- Use incremental ATPG: low effort first, then high effort on remaining faults
- Consider SAT-based ATPG for hard-to-solve faults

## Coverage Closure Techniques

### Test Points

The most effective technique for improving coverage. EDA tools can automatically identify optimal test point locations:

```
analyze_testability -coverage_improvement
insert_test_points -count 1000 -coverage_target 99.0
```

Typical improvement: 1-3% coverage gain from 0.5-2% area overhead.

### Scan Chain Optimization

Ensure all possible flip-flops are in scan chains:
- Review dont_scan attributes -- remove any that are not justified
- Scan multi-bit registers that may have been excluded
- Add scan to registers in IP blocks if possible

### Clock Domain Handling

Improve coverage for multi-clock designs:
- Ensure all clock domains are testable (have both shift and capture capability)
- Add lockup latches for inter-domain chain connections
- Provide test clocks for domains that may not have functional clocks during test

### Design Modifications

For persistent coverage gaps:
- Add observability paths for deeply buried signals
- Break reconvergent fanout with additional pipeline stages
- Add test modes that simplify hard-to-test structures

## Coverage Reporting and Sign-Off

DFT sign-off requires comprehensive coverage reporting:

1. **Coverage summary**: FC, TC, AE for all fault models (stuck-at, transition, cell-aware)
2. **Block-level breakdown**: Coverage by hierarchical block to identify weak areas
3. **Fault category analysis**: Detailed classification of all non-detected faults
4. **Pattern count and test time**: Estimated ATE test time per insertion
5. **Coverage trend**: Historical coverage from previous milestones to show improvement
6. **Uncovered fault justification**: Explanation for any faults below target

This report is reviewed by the DFT team, design team, and quality assurance before tape-out. Coverage shortfalls must be justified with risk analysis or addressed with design changes.

## Beyond Fault Coverage: DPPM

Fault coverage alone does not fully predict test quality. Two test sets with identical fault coverage can have different defect detection capabilities depending on which faults they detect. The ultimate metric is Defects Per Million (DPPM) -- the number of defective parts that escape testing per million shipped.

DPPM is estimated using the Williams-Brown yield model:

```
DPPM = 10,000 x (1 - Y^((1-T)/(1-Y)))
```

where Y is die yield and T is test coverage. This model shows that going from 98% to 99% coverage may reduce DPPM by 50% or more, justifying the significant effort needed for the last percentage points of coverage improvement.
