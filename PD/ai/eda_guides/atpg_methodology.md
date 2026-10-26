# ATPG Methodology: Automatic Test Pattern Generation

## ATPG Fundamentals

Automatic Test Pattern Generation (ATPG) is the algorithmic process of creating test stimuli (patterns) that detect manufacturing defects in integrated circuits. ATPG tools model physical defects as logical faults, then use Boolean satisfiability and structural analysis to generate input vectors that sensitize each fault and propagate its effect to an observable output.

The ATPG process for a single fault follows three fundamental steps: (1) **Activation** -- set the fault site to the value opposite the fault (e.g., drive a 1 to a SA0 site to activate it), (2) **Propagation** -- create a sensitized path from the fault site to a primary output or scan flip-flop where the faulty response differs from the good response, and (3) **Justification** -- determine the primary input and scan flip-flop values needed to achieve activation and propagation. These steps are implemented through sophisticated search algorithms with backtracking.

## Fault Models in ATPG

### Stuck-At Fault Model

The stuck-at model assumes a single node is permanently fixed at logic 0 (SA0) or logic 1 (SA1). For a circuit with N nodes, there are 2N possible single stuck-at faults. This is the most mature fault model with the highest tool support and is the baseline for all test strategies.

A stuck-at test pattern needs only a single capture cycle after the scan shift. The pattern sets up the combinational logic inputs (via scan load), and the capture clock propagates the response through the logic. No at-speed requirement exists because the model is a static fault.

Industry targets: 97-99% stuck-at fault coverage for consumer products, 99%+ for automotive.

### Transition Fault Model (TDF)

The transition fault model detects timing-related defects -- slow-to-rise (STR) and slow-to-fall (STF) faults. A transition fault at a node means the node can hold a static value but cannot transition fast enough within the clock period.

Testing requires two capture cycles at functional speed:
1. **Launch cycle**: Establishes the initial value at the fault site
2. **Capture cycle**: Applies the transition and captures the response

Two launch strategies exist:
- **Launch-Off-Shift (LOS)**: The last shift cycle serves as the launch. Simpler OCC requirements but limits the initial values achievable at internal nodes.
- **Launch-Off-Capture (LOC)**: A functional clock pulse serves as the launch, followed by another for capture. More flexible initialization but requires the OCC to generate two at-speed pulses.

Industry targets: 95-98% transition fault coverage.

### Path Delay Fault Model

Path delay faults model the cumulative delay along a specific structural path. Unlike transition faults (which are node-based), path delay faults are path-based, capturing distributed delay degradation that no single gate exceeds its timing but the path sum does.

The challenge is the exponential number of paths: a circuit with N levels of logic can have O(2^N) paths. ATPG tools typically target a subset: critical paths, timing-near-critical paths, or paths identified by STA as vulnerable.

Path delay ATPG generates a pattern pair that (1) creates a transition at the path input, (2) sensitizes the specific path (all side inputs set to non-controlling values), and (3) captures the path output. This is called a robust test. Non-robust tests relax the sensitization requirement.

### Other Fault Models

**BridgingAults**: Model shorts between two signal lines. ATPG must drive the two bridged lines to opposite values and observe the resulting logic behavior. Requires knowledge of bridge resolution (AND, OR, dominant, etc.).

**Cell-Aware Faults**: Use transistor-level defect analysis within standard cells to generate fault models that go beyond stuck-at and transition. These capture intra-cell defects like transistor shorts and opens that may not be detected by traditional models. Cell-aware testing can improve defect detection by 2-5% over stuck-at alone.

**Small Delay Defects (SDD)**: Target gates with slightly increased delay that pass standard transition tests but fail at marginal timing conditions. Requires careful timing-aware ATPG with path-based analysis.

## ATPG Algorithms

### D-Algorithm

The classic ATPG algorithm uses the D-calculus with five-valued logic: 0, 1, X, D (1/0 good/faulty), and D' (0/1 good/faulty). It works through:
1. Fault activation: Drive D or D' at the fault site
2. D-frontier propagation: Advance the D/D' toward outputs
3. Line justification: Backtrack to determine consistent input values

### PODEM (Path-Oriented Decision Making)

Improves on D-algorithm by making decisions only at primary inputs, avoiding the internal backtracking inefficiencies. PODEM uses an objective function to guide input assignments toward fault detection.

### FAN (Fanout-Oriented Test Generation)

Extends PODEM with multiple backtrace and headline/bound concepts that reduce the search space. FAN identifies independent subproblems that can be solved without interaction.

### Modern ATPG Engines

Commercial tools use highly optimized variants of these algorithms combined with:
- SAT-based solving for hard faults
- Structural analysis for fault classification (untestable proofs)
- Dynamic compaction (packing multiple fault detections into one pattern)
- Static compaction (merging compatible patterns post-generation)
- Random pattern simulation as a fast first pass

## Fault Simulation

Fault simulation evaluates the fault coverage achieved by a set of patterns without generating new ones. It is used to:

1. **Measure coverage** of any pattern set (including functional vectors)
2. **Identify detected faults** to avoid redundant ATPG effort
3. **Evaluate ATPG quality** by comparing coverage across fault models

Fault simulation techniques include:
- **Parallel fault simulation**: Simulates multiple faults simultaneously using bit-parallel operations
- **Concurrent fault simulation**: Maintains a fault-free and faulty simulation concurrently, tracking differences
- **Differential fault simulation**: Only simulates in the cone of influence of each fault

## ATPG Flow

A typical ATPG flow proceeds as follows:

1. **Read design**: Import the gate-level netlist and scan chain definitions
2. **Set fault model**: Specify stuck-at, transition, or other models
3. **Run DRC**: Verify scan structure integrity, identify test rule violations
4. **Classify faults**: Identify structurally untestable faults (tied signals, redundant logic)
5. **Generate patterns**: Run ATPG engine with specified parameters (effort level, abort limit, pattern count limit)
6. **Report coverage**: Analyze fault categories -- detected, possibly detected, undetectable, ATPG-untestable, not analyzed
7. **Verify patterns**: Simulate patterns on the netlist to validate correctness
8. **Write patterns**: Export in ATE-compatible formats (STIL, WGL, etc.)

## Pattern Generation Strategies

**Random Pattern Resistant Faults**: Some faults cannot be detected by random patterns due to reconvergent fanout or XOR-like structures. ATPG specifically targets these after the random-pattern-detectable faults are covered.

**Abort Limits**: The ATPG tool allows a configurable number of backtracks per fault before aborting. Higher abort limits find more faults but increase runtime. Typical values: 1,000-100,000 backtracks.

**Pattern Ordering**: Patterns can be reordered to optimize test time, power, or fault coverage ramp. A common strategy is to place patterns with the highest incremental coverage first.

**Incremental ATPG**: Run ATPG incrementally -- first with low effort to catch easy faults, then increase effort for remaining hard faults. This optimizes total runtime since most faults are easy to detect.

## ATPG for Compressed Scan

When scan compression is present, ATPG must account for the decompressor and compressor structures. The decompressor constrains what scan chain values are achievable (not all 2^N combinations are possible from C input channels). The compressor can cause aliasing where two different responses produce the same compressed output.

Commercial ATPG tools are compression-aware -- they generate patterns that work within decompressor constraints and avoid compressor aliasing. The patterns are specified in the compressed domain (channel inputs/outputs), and the tool handles mapping to internal chains.

## ATPG Effectiveness and Troubleshooting

When coverage falls short of targets:
- **Analyze untestable faults**: Many are structurally untestable due to tied-off signals, constants, or redundant logic. These should be excluded from the coverage denominator.
- **Add test points**: Controllability and observability test points at hard-to-test nodes can dramatically improve coverage.
- **Increase ATPG effort**: Higher abort limits, more random patterns, and advanced algorithms may find additional detections.
- **Review scan exclusions**: Flip-flops excluded from scan reduce controllability/observability of surrounding logic.
- **Check DFT DRC violations**: Unresolved violations often correlate with undetectable faults.
- **Consider additional fault models**: Cell-aware or bridging fault ATPG may target defects missed by stuck-at and transition models.

## Pattern Formats

ATPG tools export patterns in standard formats for ATE consumption:
- **STIL (Standard Test Interface Language)**: IEEE 1450 standard, widely supported, text-based
- **WGL (Waveform Generation Language)**: Another common format, especially for older ATE
- **Binary formats**: Tool-specific compressed formats for efficient data transfer

Pattern translation between formats and porting between ATE platforms is a common requirement. Tools like Tessent PatternPort and Synopsys TetraMAX support format conversion.
