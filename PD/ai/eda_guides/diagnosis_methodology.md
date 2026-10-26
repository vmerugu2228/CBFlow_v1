# Fault Diagnosis Methodology

## Purpose of Fault Diagnosis

Fault diagnosis is the process of identifying the most likely location and type of a manufacturing defect in a failing integrated circuit. While ATPG and test patterns detect that a defect exists (pass/fail), diagnosis pinpoints where and what the defect is. This information is critical for:

- **Failure analysis (FA)**: Guides physical inspection (FIB, SEM, TEM) to the suspected defect site, dramatically reducing FA time from weeks to days
- **Yield learning**: Aggregated diagnosis results across many failing die reveal systematic defect patterns that indicate process issues
- **Design improvement**: Identifies design structures that are vulnerable to specific defect types
- **Process improvement**: Correlates diagnosed defects with specific process steps for root cause analysis
- **Quality improvement**: Validates that the test program effectively screens the defect types present in production

Without diagnosis, failure analysis is a needle-in-a-haystack problem on a chip with billions of transistors. With diagnosis, the search is narrowed to a handful of candidate locations.

## Scan-Based Diagnosis

Scan-based diagnosis uses the fail data from structural test patterns to infer the defect location. The fundamental approach:

1. **Collect fail data**: For each pattern, record which scan outputs show incorrect responses (fail bits)
2. **Model candidate faults**: For each candidate fault location, simulate what fail pattern it would produce
3. **Compare and rank**: Score each candidate by how well its predicted fail pattern matches the actual fail data
4. **Report top candidates**: Present the highest-scoring candidates as the most likely defect locations

### Types of Scan Diagnosis

**Chain Diagnosis**: Identifies failures in the scan shift mechanism itself -- typically a stuck-at fault on a scan cell's SI, SO, or SE path, or a hold violation causing shift data corruption. Chain failures manifest as systematic errors in the shifted-out data that are correlated with chain position rather than pattern content.

**Logic Diagnosis**: Identifies failures in the combinational logic that are captured during the test cycle. The scan chains shift correctly, but the captured response at specific cells differs from expected. Logic diagnosis analyzes which logic faults could explain the observed capture failures.

**Mixed Diagnosis**: Handles cases where both chain and logic defects coexist, which is common in practice.

## Logic Diagnosis Algorithms

### Effect-Cause Diagnosis

Start from the observed failing outputs and trace backward through the logic to find candidate fault locations:

1. Identify all scan cells with incorrect captured values (failing bits)
2. Trace backward through the logic cones driving the failing cells
3. Identify nodes in the intersection of failing logic cones (potential fault sites)
4. For each candidate, simulate the fault and compare predicted fails with actual fails
5. Score candidates by match quality

**Advantages**: Fast for small numbers of failing bits. Natural for focused defects.
**Limitations**: May miss defects with complex propagation. Less effective for multiple defects.

### Cause-Effect Diagnosis

Systematically enumerate candidate fault locations and simulate each one forward to predict its fail signature:

1. For each net in the design (or a filtered subset), inject a stuck-at fault
2. Simulate all failing patterns with the injected fault
3. Compare predicted failing bits with actual failing bits
4. Score: (matching fails) / (total predicted fails + total actual fails - matching fails)

**Advantages**: Thorough; considers all candidate locations. Better for complex faults.
**Limitations**: Computationally expensive for large designs. Requires pruning strategies.

### Direct Diagnosis

Modern tools use a hybrid approach combining effect-cause and cause-effect techniques:
1. Effect-cause analysis narrows the search space to a region of interest
2. Cause-effect analysis within that region refines the candidate list
3. Advanced scoring considers both matching and non-matching patterns
4. Multiple fault types are considered (SA0, SA1, transition, bridge)

## Diagnosis Scoring

The quality of a diagnosis candidate is measured by its score:

**Match score**: What fraction of actual failing patterns are explained by this candidate fault?
```
Match = (Patterns where candidate predicts fail AND actual is fail) / (Actual failing patterns)
```

**False alarm score**: What fraction of the candidate's predicted fails are not actual fails?
```
False alarms = (Patterns where candidate predicts fail AND actual is pass) / (Candidate predicted fails)
```

**Overall score**: Combines match and false alarm into a single metric. A perfect diagnosis has 100% match and 0% false alarms.

In practice, scores above 80% match with low false alarms indicate high-confidence diagnosis. Scores of 50-80% suggest the candidate is in the right region but may not be the exact defect location (common for bridging faults or distributed defects).

## Chain Diagnosis Details

Scan chain failures are diagnosed separately from logic failures because they corrupt the shift data, making logic diagnosis impossible until chains are fixed.

### Chain Failure Symptoms

- **Stuck-at on scan path**: A fixed 0 or 1 appears at a consistent position in the chain, regardless of pattern content. All bits after the stuck point show the wrong value.
- **Hold violation**: Data shifts correctly at low speed but fails at higher shift frequencies. Adjacent bits may be corrupted.
- **SE failure**: Scan enable not reaching some cells, causing them to capture functional data during shift.
- **Multiple faults**: Several cells in the chain may be faulty, creating a complex failure signature.

### Chain Diagnosis Process

1. Apply chain integrity patterns (flush test: shift in all-0s, then all-1s, then alternating)
2. Compare observed outputs with expected shifted data
3. Identify the first cell in the chain where the shifted data diverges from expected
4. Analyze the divergence pattern to determine fault type (stuck, hold, bridge)
5. Report the suspected cell position and fault type

## Diagnosis for Different Fault Types

### Stuck-At Diagnosis
Most straightforward: the diagnosed location has a permanent stuck value. High diagnosis resolution (exact net identification) is common.

### Transition Fault Diagnosis
The defect is a slow gate or interconnect. Diagnosis identifies the node that fails to transition in time. Resolution is good but may be ambiguous between the slow gate output and its adjacent interconnect.

### Bridging Fault Diagnosis
Two nets are shorted together. Diagnosis must identify both nets involved in the bridge. This is more challenging because the bridging behavior (AND, OR, dominant) depends on relative drive strengths. Modern tools test multiple bridging models for each candidate pair.

### Open Fault Diagnosis
An interconnect is broken (high resistance or complete open). Opens can cause complex symptoms because a floating net may resolve to different values depending on charge, coupling, and leakage. Diagnosis for opens often has lower confidence than for shorts.

## Diagnosis Data Requirements

### Fail Data Collection

The quality of diagnosis depends directly on the quality of fail data:

**Per-pattern fail data**: For each pattern, record which scan outputs fail. This is the minimum required for logic diagnosis.

**Per-cycle fail data**: Record the fail/pass status at each shift cycle, not just the final output. Provides much more diagnostic information for chain diagnosis.

**Fail count**: Record the number of failing patterns (not just which ones). Helps distinguish hard faults from marginal/intermittent faults.

**ATE data format**: Most ATE platforms can export fail data in formats compatible with diagnosis tools (Tessent Diagnosis, TetraMAX Diagnosis, Modus Diagnosis).

### Pattern Selection for Diagnosis

Not all test patterns are equally useful for diagnosis:
- Patterns that target the suspected fault region provide the most diagnostic information
- A diverse set of passing and failing patterns helps distinguish between candidate locations
- Some tools generate dedicated diagnostic patterns that maximize discrimination between candidates

## Yield Learning Through Diagnosis

### Volume Diagnosis

Running diagnosis on hundreds or thousands of failing die from production reveals:

**Common failure sites**: Locations that appear frequently across many die indicate systematic defects -- process issues affecting a specific layout structure.

**Random vs. systematic defects**: Random defects appear at different locations on each die (particle contamination). Systematic defects repeat at the same design location (lithographic hotspot, stress-induced void).

**Defect Pareto**: Ranking defect locations by frequency creates a Pareto chart showing the top yield limiters. This directly guides process improvement priorities.

### Inline Diagnosis

Running diagnosis continuously during production (not just during yield ramp):
- Monitors for new systematic defects that may emerge as process drifts
- Provides real-time feedback on process excursions
- Enables rapid response to yield drops

### Diagnosis-Driven Design Changes

When diagnosis reveals a design vulnerability:
- Metal widening at frequent failure sites
- Via doubling or tripling at high-failure-rate via locations
- Layout-level fixes for lithographic hotspots
- Addition of redundant structures at critical locations
- DFT improvements (more test points, better coverage) for hard-to-diagnose regions

## Advanced Diagnosis Topics

### Layout-Aware Diagnosis

Incorporating physical layout information improves diagnosis accuracy:
- Candidate fault locations are scored considering physical proximity to known defect-prone areas
- Bridging fault candidates are filtered by physical adjacency (only nearby nets can bridge)
- Layout coordinates of diagnosed faults enable direct navigation to the FA target

### Cell-Aware Diagnosis

Uses transistor-level fault models within standard cells:
- Identifies intra-cell defects (transistor shorts/opens) that appear as ambiguous from gate-level analysis
- Provides finer-grained diagnosis resolution
- Requires cell-aware fault libraries from cell characterization

### Diagnosis of Intermittent Faults

Some defects are intermittent -- they fail on some test insertions but pass on others:
- Collect fail data from multiple test insertions of the same die
- Statistical analysis identifies locations with high failure probability
- Environmental sensitivity (voltage, temperature) provides additional diagnostic information

## Diagnosis Flow Integration

A practical diagnosis flow:

1. **Production test**: Collect fail data during regular production testing
2. **Data filtering**: Remove die with catastrophic failures (e.g., power short) that cannot be diagnosed
3. **Chain diagnosis**: Identify and fix chain failures first
4. **Logic diagnosis**: Diagnose logic failures for chain-passing die
5. **Result aggregation**: Combine diagnosis results across all analyzed die
6. **Yield reporting**: Generate Pareto charts, trend analysis, and systematic defect reports
7. **Feedback loop**: Feed diagnosis insights back to design and process teams
