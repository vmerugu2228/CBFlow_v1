# Yield Learning: DFT for Yield Improvement

## Yield Fundamentals

Yield -- the percentage of manufactured die that pass all tests and meet specifications -- is the primary economic metric of semiconductor manufacturing. For a new product on a new process, initial yields might be 30-50%. Through systematic yield learning, yields improve to 80-95%+ over time. DFT plays a central role in this learning process by providing the diagnostic data needed to identify, understand, and eliminate yield-limiting defects.

The yield equation for random defects follows the Poisson or negative binomial model:

```
Y = (1 + D0 * A / alpha) ^ (-alpha)
```

where D0 is the defect density (defects per cm^2), A is the die area, and alpha is the clustering parameter. Reducing D0 (through process improvement) and A (through design shrink) are the primary levers for yield improvement.

## Systematic vs. Random Defects

Understanding the defect population is essential for effective yield improvement:

### Random Defects

- Caused by particle contamination, random process variations
- Appear at different locations on each die
- Follow Poisson statistics
- Reduced by cleanroom improvements, process controls
- DFT contribution: High fault coverage catches random defects efficiently; no specific design changes needed

### Systematic Defects

- Caused by design-process interactions: lithographic hotspots, stress-induced voids, pattern-dependent effects
- Repeat at the same design location across many die
- Do not follow Poisson statistics -- they cluster at specific layout features
- Reduced by design rule improvements, restricted design rules, OPC enhancements
- DFT contribution: Diagnosis identifies the repeating failure locations; design-for-manufacturability (DFM) fixes eliminate them

The ratio of systematic to random defects has increased dramatically at advanced nodes (28nm and below), making diagnosis-driven yield learning increasingly important.

## DFT-Driven Yield Learning Flow

### Phase 1: Test Program Development

Before silicon arrives:
1. Define fault coverage targets that ensure adequate defect detection
2. Build test patterns for all fault models (stuck-at, transition, cell-aware, IDDQ)
3. Plan diagnosis pattern sets (may differ from production patterns)
4. Establish fail data collection infrastructure on ATE

### Phase 2: Initial Silicon Characterization

First silicon yield learning:
1. Apply comprehensive test patterns to all die on initial wafers
2. Collect detailed fail data (per-pattern, per-cycle for chain diagnosis)
3. Run chain diagnosis on all chain-failing die
4. Run logic diagnosis on all pattern-failing die
5. Generate initial yield Pareto and defect maps

### Phase 3: Failure Analysis Correlation

Validate diagnosis accuracy:
1. Select top diagnosis candidates for physical FA
2. Perform FIB cross-section, SEM imaging at diagnosed locations
3. Correlate physical defect with diagnosis prediction
4. Refine diagnosis methodology based on correlation results
5. Target: >70% diagnosis-to-FA correlation rate

### Phase 4: Volume Diagnosis and Statistical Analysis

Production yield learning:
1. Run diagnosis on a statistically significant sample (hundreds to thousands of die)
2. Aggregate diagnosis results to identify common failure sites
3. Classify defects as random or systematic
4. Generate systematic defect Pareto
5. Feed results to process and design teams

### Phase 5: Root Cause Analysis and Corrective Action

Close the loop:
1. For each top systematic defect, perform root cause analysis
2. Determine if the cause is design, process, or interaction
3. Implement corrective actions (design rule change, process adjustment, layout fix)
4. Verify improvement with subsequent diagnosis data
5. Iterate until yield targets are met

## Inline Test and Monitoring

### Inline Defect Inspection

Optical and e-beam inspection at intermediate process steps detects defects before the wafer is complete. Correlation between inline defects and final test failures:
- Helps identify which process steps produce yield-limiting defects
- Enables early wafer scrapping (save the cost of completing defective wafers)
- DFT supports this by providing the final test data for correlation

### Parametric Test

Wafer-level parametric tests (Vth, Idsat, contact resistance, etc.) measured at test structures:
- Monitor process parameters that affect yield
- Correlate with final test results to identify parameter drift impact
- DFT patterns can include parametric-sensitive tests (e.g., IDDQ correlates with leakage parameters)

### SRAM Bit Cell Yield

SRAM bit cells are the densest structures on chip and the first to reveal process defects:
- MBIST failure data provides a direct measure of cell-level yield
- SRAM fail bitmap analysis reveals defect spatial patterns
- SRAM yield models predict logic yield based on SRAM results
- Early SRAM results guide process adjustments before complex logic is fabricated

## Test Chip Strategies

### Yield Test Chips

Dedicated test chips designed specifically for yield learning:

**SRAM test chips**: Large SRAM arrays (much larger than product memories) for statistically significant bit cell yield measurement. Include multiple cell variants, array configurations, and stress conditions.

**Logic test chips**: Scan-based logic blocks designed with known layout patterns that are vulnerable to specific defect types. Diagnosis on these chips directly maps to layout features.

**Short-loop test chips**: Simplified process flows (e.g., front-end only, metal-1 only) that isolate specific process steps for yield analysis.

### Product-Like Test Chips

Test chips that replicate product design patterns:
- Same standard cell library, same metal stack, same design rules
- Include critical product layout features (dense routing, via arrays, clock trees)
- DFT structures enable efficient testing and diagnosis
- Results directly predict product yield

### Yield Vehicle Design Guidelines

- Include structures that stress known yield-limiting design rules
- Provide comprehensive MBIST for all memory variants
- Include scan chains with high fault coverage for logic
- Add dedicated diagnosis structures (test points, observation paths)
- Enable both structural and parametric testing
- Include process monitor structures alongside functional blocks

## DPPM and Test Escapes

### DPPM Estimation

The test program's ultimate quality metric -- defective parts per million shipped:

```
DPPM = 10^6 * (1 - Y_test / Y_actual)
```

where Y_test is the yield seen by the test program and Y_actual is the true yield (including defects the test misses).

Using the Williams-Brown model:
```
DPPM ≈ 10^4 * (1 - Y^((1-T)/(1-Y)))
```

where Y is die yield and T is test coverage.

Example: With 90% yield and 99% test coverage, DPPM ≈ 105. With 99.5% test coverage, DPPM ≈ 52. Each 0.5% of additional coverage roughly halves the escape rate.

### Reducing Test Escapes

When DPPM targets are not met:
1. **Increase coverage**: Add patterns for uncovered faults, insert test points
2. **Add fault models**: Cell-aware, IDDQ, small-delay-defect models catch defects missed by stuck-at and transition
3. **Tighten IDDQ limits**: More aggressive current thresholds catch marginal defects
4. **Burn-in**: Stress testing at elevated voltage/temperature catches reliability defects
5. **Adaptive test**: Adjust test stringency based on wafer-level indicators (neighboring die results, parametric measurements)

## Advanced Yield Learning Techniques

### Machine Learning for Yield Prediction

ML models trained on test data, parametric data, and diagnosis results:
- Predict yield of incoming wafer lots
- Identify wafer regions with elevated defect risk
- Optimize test flow by focusing effort on high-risk die
- Detect process excursions earlier than traditional SPC methods

### Spatial Yield Analysis

Mapping yield and diagnosis results across the wafer:
- **Wafer maps**: Visualize pass/fail patterns to identify edge effects, center hot spots, radial patterns
- **Defect clustering**: Identify localized process issues (e.g., contamination on specific chucks)
- **Die-to-die correlation**: Neighboring die failure correlation indicates systematic process issues

### Feedback to Design

Yield data drives design improvements:
- **Layout modifications**: Widen metals, add redundant vias at high-failure locations
- **Design rule updates**: Tighten rules where systematic failures occur
- **Library improvements**: Modify cell layouts that show elevated failure rates
- **DFT enhancements**: Add coverage for defect types discovered during yield learning

### Feedback to Process

Yield data drives process improvements:
- **Defect reduction**: Target specific process steps that contribute most to yield loss
- **Recipe optimization**: Adjust etch, deposition, CMP, and litho recipes based on defect data
- **Equipment maintenance**: Correlate yield excursions with specific tools and chambers
- **Spec tightening**: Adjust process control limits based on yield sensitivity analysis

## Yield Learning Metrics

| Metric | Definition | Target |
|--------|-----------|--------|
| Yield (per wafer) | Good die / Total die | 85-95% (mature) |
| D0 (defect density) | Defects / cm^2 | <0.1 (mature 7nm+) |
| DPPM | Escapes per million | <10 (automotive) |
| Diagnosis resolution | Located / Total diagnosed | >80% |
| FA correlation | Confirmed / Diagnosed | >70% |
| Time to yield | Months from first silicon to target yield | <6 months |

## DFT for Yield: Best Practices

1. Achieve the highest possible fault coverage -- every percentage point matters for DPPM
2. Use multiple fault models to cover different defect types
3. Build diagnosis-capable test programs from day one, not as an afterthought
4. Invest in volume diagnosis infrastructure for production yield learning
5. Close the feedback loop: diagnosis results must reach process and design teams quickly
6. Monitor yield continuously -- systematic defects can emerge at any time
7. Correlate DFT diagnosis with physical failure analysis to validate and improve diagnosis accuracy
8. Use SRAM yield as a leading indicator for overall product yield
9. Design yield test chips for new process nodes before product tape-out
10. Treat yield learning as an ongoing program, not a one-time activity
